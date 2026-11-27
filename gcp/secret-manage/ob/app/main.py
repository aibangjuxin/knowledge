#!/usr/bin/env python3
"""
main.py —— 统一入口（orchestrator）

设计目标
--------
1. **单一入口**：容器 ENTRYPOINT 就是本脚本，所有步骤由它调度；
2. **步骤可插拔**：每个步骤是 app/steps/ 下一个独立的、可单独运行的 Python 脚本；
   main 只负责"按顺序调用 + 汇总"，不理解每一步的业务细节；
3. **配置来自文件 + 环境变量**：JSON 提供骨架，环境变量在运行时覆盖（容器惯例）；
4. **不可变镜像**：镜像里只有代码，配置靠 -v 挂载或 -e 注入。

用法
----
    # 跑全部步骤
    python3 main.py run --config-dir /app/config

    # 只跑某一步
    python3 main.py run --config-dir /app/config --only onboarding

    # dry-run
    python3 main.py run --config-dir /app/config --dry-run -v

    # 环境变量覆盖配置
    TARGET_ENV=prod API_NAME=myapi python3 main.py run --config-dir /app/config

容器里：
    docker run --rm \
      -e TARGET_ENV=prod -e API_NAME=myapi -e RELEASE_VERSION=1.2.3 \
      -v "$PWD/app/config:/app/config:ro" \
      my-image run --config-dir /app/config
"""

import argparse
import json
import os
import subprocess
import sys
import time

# 让 main 能 import 同目录的 common
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from common import (  # noqa: E402
    CONFIG_DIR,
    Logger,
    STEPS_DIR,
    build_secret_id,
    dump,
    load_config,
)

# ---------------------------------------------------------------- 步骤注册表

# 每个步骤 = 一个独立脚本 + 它默认用的配置文件
# main 只认识这张表，不关心脚本内部逻辑
STEPS = [
    {
        "name": "onboarding",
        "script": "secret_api_onboarding.py",
        "config": "ob.example.json",
        "desc": "API 级 onboarding：建 RT GSA / 建空 secret / 绑 IAM / 更新元数据",
    },
    {
        "name": "create",
        "script": "secret_api_create.py",
        "config": "secret.create.json",
        "desc": "创建 secret：建 secret / 写 version / 绑 accessor",
    },
]

# ---------------------------------------------------------------- 环境变量映射
#
# 容器惯例：配置以文件为准，环境变量在运行时覆盖。
# 左边是环境变量名，右边是 config json 里的字段名。
#
ENV_TO_CONFIG = {
    # 业务标识
    "TARGET_ENV": "targetEnv",
    "REGION": "region",
    "TEAM_NAME": "teamName",
    "API_NAME": "apiName",
    "TICKET_NUM": "ticketNum",
    "SECRET_PROJECT_ID": "secretProjectId",
    "PROJECT_GCP_SA": "projectGcpSa",
    # 开关
    "IAM_ENABLE": "iamEnable",
    "UPDATE_SECRET_ACCESS": "updateSecretAccess",
    "GRANT_GROUP_ACCESSOR": "grantGroupAccessor",
    # 杂项
    "EIM_APP_ID": "eimAppId",
    "CHANGE_FILE_NAME": "changeFileName",
    "TRIGGER_JOB_TIMEOUT": "triggerJobTimeout",
    "SOURCE_VERSION": "sourceVersion",
    "JENKINS_PROJECT_NAME": "jenkinsProjectName",
}

# 只在日志里展示、不进 config 的运行时元信息
META_ENV_KEYS = ("RELEASE_VERSION", "RELEASE_BY", "BUILD_TIME")

BOOL_FIELDS = ("iamEnable", "updateSecretAccess", "grantGroupAccessor")
INT_FIELDS = ("triggerJobTimeout", "sourceVersion")


# ---------------------------------------------------------------- 工具

def apply_env_overrides(cfg):
    """把环境变量覆盖到 config 上，返回 (cfg, 覆盖明细)。"""
    applied = {}
    for env_key, field in ENV_TO_CONFIG.items():
        val = os.environ.get(env_key)
        if val is None or val == "":
            continue
        if field in BOOL_FIELDS:
            val = val.strip().lower() in ("1", "true", "yes", "y", "on")
        elif field in INT_FIELDS:
            try:
                val = int(val)
            except ValueError:
                continue
        elif field == "keyNameList":
            val = [x.strip() for x in val.split(",") if x.strip()]
        applied[field] = val
        cfg[field] = val
    return cfg, applied


def write_temp_config(cfg, config_dir, name):
    """
    把（被环境变量覆盖后的）config 落到临时文件，返回路径。
    步骤脚本只认 --config <file>，所以这里做一次物化。
    """
    os.makedirs(config_dir, exist_ok=True)
    path = os.path.join(config_dir, ".runtime_{}.json".format(name))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    return path


def run_step(step, cfg, args, log):
    """调用一个步骤脚本（子进程），返回 (exit_code, 耗时秒)。"""
    script = os.path.join(STEPS_DIR, step["script"])
    if not os.path.exists(script):
        log.error("步骤脚本不存在: {}".format(script))
        return 127, 0.0

    # 步骤的配置文件：
    #   --config-dir 下的优先（运行时挂载的）
    #   其次 app/config/ 下的内置默认（镜像里带的）
    #   两者都没有 → 报错（不能静默用错配置）
    cfg_file = os.path.join(args.config_dir, step["config"])
    if not os.path.exists(cfg_file):
        fallback = os.path.join(CONFIG_DIR, step["config"])
        if getattr(args, "strict_config", False):
            log.error(
                "步骤 {} 的配置文件不存在（--strict-config 生效）: {}".format(
                    step["name"], cfg_file
                )
            )
            return 2, 0.0
        if os.path.exists(fallback):
            log.warn(
                "{} 不存在，回退到内置默认配置: {}".format(
                    cfg_file, fallback
                )
            )
            cfg_file = fallback
        else:
            log.error("步骤 {} 的配置文件不存在: {}".format(
                step["name"], cfg_file
            ))
            return 2, 0.0

    # 合并：文件里的 config + 环境变量覆盖 → 物化成临时文件
    try:
        merged = load_config(cfg_file)
    except Exception as e:
        log.error("读取 {} 失败: {}".format(cfg_file, e))
        return 2, 0.0

    merged, applied = apply_env_overrides(merged)
    # 步骤自己的命令行参数（如 --project）优先级最高
    if args.project:
        merged["secretProjectId"] = args.project

    runtime_cfg = write_temp_config(merged, args.runtime_dir, step["name"])
    if applied:
        log.info("环境变量覆盖: {}".format(
            ", ".join("{}={}".format(k, v) for k, v in applied.items())
        ))

    cmd = [sys.executable, script, "--config", runtime_cfg]
    if args.dry_run:
        cmd.append("--dry-run")
    if args.verbose:
        cmd.append("-v")
    if args.project:
        cmd.extend(["--project", args.project])

    log.info("$ {}".format(" ".join(cmd)))
    t0 = time.time()
    try:
        rc = subprocess.call(cmd)
    except KeyboardInterrupt:
        log.error("步骤 {} 被中断".format(step["name"]))
        raise
    elapsed = time.time() - t0

    # 清理临时 config
    try:
        os.remove(runtime_cfg)
    except OSError:
        pass

    return rc, elapsed


# ---------------------------------------------------------------- 命令

def cmd_run(args, log):
    steps = STEPS
    if args.only:
        wanted = set(args.only.split(","))
        steps = [s for s in STEPS if s["name"] in wanted]
        if not steps:
            log.error("--only {} 没有匹配的步骤（可选: {}）".format(
                args.only, ",".join(s["name"] for s in STEPS)
            ))
            return 2

    log.banner("SMS Secret Onboarding Pipeline")
    dump("运行时信息", {
        "releaseVersion": os.environ.get("RELEASE_VERSION", "-"),
        "releaseBy": os.environ.get("RELEASE_BY", "-"),
        "buildTime": os.environ.get("BUILD_TIME", "-"),
        "configDir": args.config_dir,
        "dryRun": args.dry_run,
        "steps": [s["name"] for s in steps],
    })
    log.info("可用步骤:")
    for s in STEPS:
        log.info("  - {:<12} {}".format(s["name"], s["desc"]))
    log.info("")

    results = []
    failed = False
    config_error = False

    for i, step in enumerate(steps, 1):
        log.step(i, len(steps), "[{}] {}".format(step["name"], step["desc"]))
        rc, elapsed = run_step(step, {}, args, log)
        results.append({
            "step": step["name"],
            "exitCode": rc,
            "elapsedSec": round(elapsed, 2),
        })
        if rc != 0:
            failed = True
            if rc == 2:
                config_error = True
            log.error("步骤 {} 失败 (exit={})".format(step["name"], rc))
            if not args.keep_going:
                log.error("中止后续步骤（--keep-going 可强制继续）")
                break
        else:
            log.info("步骤 {} 成功 ({}s)".format(step["name"], round(elapsed, 2)))

    # ---------------------------------------------------------- 汇总
    log.banner("Pipeline 结束")
    dump("步骤结果", results)

    # 从第一个能读到的 config 推导最终 secret id，方便调用方确认
    try:
        first_cfg = os.path.join(args.config_dir, STEPS[0]["config"])
        if os.path.exists(first_cfg):
            c = load_config(first_cfg)
            c, _ = apply_env_overrides(c)
            log.info("最终 secret id : {}".format(build_secret_id(c)))
    except Exception:
        pass

    if failed:
        log.error("Pipeline 结果: FAILED")
        # 配置/参数类错误 → 2；其他执行异常 → 1
        return 2 if config_error else 1
    log.info("Pipeline 结果: SUCCESS")
    return 0


def cmd_list(args, log):
    """列出可用步骤（便于脚本/CI 自检）。"""
    log.banner("可用步骤")
    for s in STEPS:
        dump(s["name"], {
            "script": s["script"],
            "config": s["config"],
            "desc": s["desc"],
        })
    log.info("环境变量覆盖映射:")
    for k, v in sorted(ENV_TO_CONFIG.items()):
        log.info("  {:<24} → {}".format(k, v))
    return 0


def cmd_env(args, log):
    """打印当前环境能解析出的最终配置（CI 自检用）。"""
    log.banner("解析后的环境")
    merged = {}
    for step in STEPS:
        p = os.path.join(args.config_dir, step["config"])
        if os.path.exists(p):
            merged = load_config(p)
            break
    merged, applied = apply_env_overrides(merged)
    dump("config (文件 + 环境变量覆盖)", merged)
    dump("被环境变量覆盖的字段", applied)
    dump("元信息", {k: os.environ.get(k, "-") for k in META_ENV_KEYS})
    return 0


# ---------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(
        prog="main.py",
        description="SMS Secret Manager Onboarding 统一入口",
    )
    sub = parser.add_subparsers(dest="command")

    # run
    p_run = sub.add_parser("run", help="执行 onboarding / create 流程")
    p_run.add_argument(
        "--config-dir", default=CONFIG_DIR, help="配置文件所在目录"
    )
    p_run.add_argument(
        "--only", help="只跑指定步骤，逗号分隔（可选: onboarding,create）"
    )
    p_run.add_argument("--project", help="覆盖 GCP project id")
    p_run.add_argument("--dry-run", action="store_true", help="不真正调用 API")
    p_run.add_argument("-v", "--verbose", action="store_true")
    p_run.add_argument(
        "--keep-going", action="store_true", help="某步失败后继续执行后续步骤"
    )
    p_run.add_argument(
        "--runtime-dir",
        default="/tmp",
        help="物化合并后配置文件的临时目录",
    )
    p_run.add_argument(
        "--strict-config",
        action="store_true",
        help="配置必须来自 --config-dir，找不到就报错（不回退到镜像内置默认）",
    )

    # list
    p_list = sub.add_parser("list", help="列出可用步骤")
    p_list.add_argument("--config-dir", default=CONFIG_DIR)

    # env
    p_env = sub.add_parser("env", help="打印解析后的配置（CI 自检）")
    p_env.add_argument("--config-dir", default=CONFIG_DIR)

    args = parser.parse_args()
    log = Logger(verbose=getattr(args, "verbose", False))

    if not args.command:
        parser.print_help()
        return 1

    try:
        if args.command == "run":
            return cmd_run(args, log)
        if args.command == "list":
            return cmd_list(args, log)
        if args.command == "env":
            return cmd_env(args, log)
    except KeyboardInterrupt:
        log.error("被用户中断")
        return 130
    except Exception as e:
        log.error("执行失败: {}: {}".format(type(e).__name__, e))
        if getattr(args, "verbose", False):
            import traceback

            traceback.print_exc()
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
