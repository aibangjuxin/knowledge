#!/usr/bin/env python3
"""
secret_api_create.py —— 创建/写入 Secret Manager Secret（POC）

流程（对应 secret.create.json 的字段）：

    1. 校验配置
    2. 确认 secret 是否存在（不存在则创建）
    3. 按 keyNameList 逐个写入 version（payload 用占位值模拟）
    4. 按 updateSecretAccess / grantGroupAccessor 绑定 accessor

用法：
    python3 secret_api_create.py --config secret.create.json
    python3 secret_api_create.py --config secret.create.json --dry-run
    python3 secret_api_create.py --config secret.create.json --project projectid
"""

import os
import sys

# 允许以脚本方式直接运行：把 app/ 加进 sys.path 才能 import common
sys.path.insert(
    0, os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)

from common import (  # noqa: E402
    ConfigError,
    Logger,
    ROLE_SECRET_ACCESSOR,
    SecretManagerClient,
    base_parser,
    build_secret_id,
    dump,
    get,
    load_config,
    require,
    resolve_project,
)

REQUIRED = (
    "targetEnv",
    "region",
    "teamName",
    "apiName",
    "ticketNum",
    "secretProjectId",
    "keyNameList",
)


def load_payload_file(path):
    """
    读取 key=value 形式的 payload 文件，返回 {key: bytes}。
    文件不存在时返回空 dict（调用方会告警并退回占位值）。
    """
    result = {}
    if not path or not os.path.exists(path):
        return result
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            result[k.strip()] = v.strip().encode("utf-8")
    return result


def fake_payload(key_name, env, real=None):
    """
    模拟 payload。
    真实场景这里应该是从 EIM / KMS / CI 变量里取到的真实密文。
    """
    if real is not None:
        return real
    return "placeholder-value-for-{}-{}".format(key_name, env).encode("utf-8")


def run_create(cfg, args, log):
    target_env = cfg["targetEnv"]
    region = cfg["region"]
    team = cfg["teamName"]
    api = cfg["apiName"]
    ticket = cfg["ticketNum"]
    key_list = cfg["keyNameList"]
    project = cfg["secretProjectId"]
    project_sa = get(cfg, "projectGcpSa", "")
    update_secret_access = get(cfg, "updateSecretAccess", False)
    grant_group_accessor = get(cfg, "grantGroupAccessor", False)

    # --project 可以覆盖配置里的 secretProjectId
    project = resolve_project(cfg, args) or project

    secret_id = build_secret_id(cfg)
    group = "sm-gcp-group-{}@gmail.com".format(team)

    log.banner("Secret Create (POC)")
    dump("配置摘要", {
        "configFile": cfg.get("_configPath"),
        "targetEnv": target_env,
        "region": region,
        "teamName": team,
        "apiName": api,
        "ticketNum": ticket,
        "secretProjectId": project,
        "projectGcpSa": project_sa,
        "keyNameList": key_list,
        "updateSecretAccess": update_secret_access,
        "grantGroupAccessor": grant_group_accessor,
    })

    sm = SecretManagerClient(project, dry_run=args.dry_run, logger=log)
    total = 4

    # ---------------------------------------------------------- STEP 1
    log.step(1, total, "检查 secret 是否存在")
    log.info("secret id     : {}".format(secret_id))
    log.info("project       : {}".format(project))
    log.info("full name     : projects/{}/secrets/{}".format(project, secret_id))
    exists = sm.secret_exists(secret_id)
    log.info("exists        : {}".format(exists))
    if not exists:
        labels = {
            "team": team,
            "api": api,
            "env": target_env,
            "ticket": ticket,
        }
        sm.create_secret(secret_id, labels=labels)
        log.info("  → 已创建 secret（labels={}）".format(labels))

    # ---------------------------------------------------------- STEP 2
    log.step(2, total, "写入 {} 个 key 的 version".format(len(key_list)))
    written = []
    real_payloads = load_payload_file(getattr(args, "payload_from_file", None))
    if getattr(args, "payload_from_file", None):
        if real_payloads:
            log.info("payload 文件  : {} ({} 个 key)".format(
                args.payload_from_file, len(real_payloads)
            ))
        else:
            log.warn("payload 文件为空或不存在: {}".format(args.payload_from_file))

    for i, key in enumerate(key_list, 1):
        payload = fake_payload(key, target_env, real_payloads.get(key))
        log.info("[{}/{}] key={}".format(i, len(key_list), key))
        if key in real_payloads:
            log.info("  (payload 来自文件)")
        version = sm.add_secret_version(
            secret_id, payload, labels={"key": key, "env": target_env}
        )
        written.append({"key": key, "version": version})
    log.info("写入完成，共 {} 个 version".format(len(written)))

    # ---------------------------------------------------------- STEP 3
    log.step(3, total, "绑定 accessor")
    if project_sa:
        sm.set_iam_policy(
            secret_id, "serviceAccount:{}".format(project_sa), ROLE_SECRET_ACCESSOR
        )
    else:
        log.warn("配置里没有 projectGcpSa，跳过 SA accessor 绑定")

    if grant_group_accessor:
        sm.set_iam_policy(
            secret_id, "group:{}".format(group), ROLE_SECRET_ACCESSOR
        )
    else:
        log.info("grantGroupAccessor=false → 不给 Group 绑定 accessor")

    if update_secret_access:
        log.info("updateSecretAccess=true → 已有 accessor 会被刷新（真实实现里会重写 IAM policy）")
    else:
        log.info("updateSecretAccess=false → 保留已有 accessor")

    # ---------------------------------------------------------- STEP 4
    log.step(4, total, "汇总")
    log.banner("Secret Create 完成 (POC)")
    dump("结果", {
        "secretId": secret_id,
        "project": project,
        "versions": written,
        "nextStep": "python3 secret_api_onboarding.py --config ob.example.json",
    })
    return 0


def main():
    parser = base_parser("创建 Secret Manager Secret (POC)")
    parser.add_argument("--env", help="覆盖配置里的 targetEnv")
    parser.add_argument(
        "--payload-from-file",
        help="可选：从文件读取真实 payload（形如 key=value 每行一条），"
             "不指定则使用占位值",
    )
    args = parser.parse_args()

    log = Logger(verbose=args.verbose)
    try:
        cfg = load_config(args.config)
        if args.env:
            cfg["targetEnv"] = args.env
        require(cfg, *REQUIRED)
        return run_create(cfg, args, log)
    except ConfigError as e:
        log.error("配置错误: {}".format(e))
        return 2
    except KeyboardInterrupt:
        log.error("被用户中断")
        return 130
    except Exception as e:
        log.error("执行失败: {}: {}".format(type(e).__name__, e))
        if args.verbose:
            import traceback

            traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
