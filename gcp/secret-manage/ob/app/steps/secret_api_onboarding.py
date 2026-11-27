#!/usr/bin/env python3
"""
secret_api_onboarding.py —— API 级 Secret Manager Onboarding（POC）

对应 onboarding.md 里 "Once per API onboarding" 的流程：

    1. 创建专用 RT GSA（runtime service account）
    2. 为 API 初始化一个空 payload 的 secret
    3. 给 Group / RT GSA 分配必要角色
    4. 更新 API 元数据（changeFileName 指向的 yaml）

用法：
    python3 secret_api_onboarding.py --config ob.example.json
    python3 secret_api_onboarding.py --config ob.example.json --dry-run -v
    python3 secret_api_onboarding.py --config ob.example.json --project my-proj
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
    ROLE_IAM_SERVICE_ACCOUNT_ADMIN,
    ROLE_SECRET_ADMIN,
    ROLE_SECRET_VIEWER,
    SecretManagerClient,
    base_parser,
    build_secret_id,
    dump,
    get,
    load_config,
    require,
    resolve_change_file,
    resolve_project,
)

# ob.example.json 里的必填字段
REQUIRED = ("targetEnv", "region", "teamName", "apiName", "ticketNum", "keyNameList")

# 模拟出来的 RT GSA 名字
RT_SA_TEMPLATE = "rt-sa-{api}-{env}"


def run_onboarding(cfg, args, log):
    """真正的业务流程（POC 版：打印 + 模拟 API 调用）。"""

    target_env = cfg["targetEnv"]
    region = cfg["region"]
    team = cfg["teamName"]
    api = cfg["apiName"]
    ticket = cfg["ticketNum"]
    key_list = cfg["keyNameList"]
    iam_enable = get(cfg, "iamEnable", False)
    eim_app_id = get(cfg, "eimAppId", "")
    update_secret_access = get(cfg, "updateSecretAccess", False)
    trigger_job_timeout = get(cfg, "triggerJobTimeout", 1800)
    source_version = get(cfg, "sourceVersion", 1)
    jenkins_project = get(cfg, "jenkinsProjectName", "")

    project = resolve_project(cfg, args)
    secret_id = build_secret_id(cfg)
    rt_sa = RT_SA_TEMPLATE.format(api=api, env=target_env)
    group = "sm-gcp-group-{}@gmail.com".format(team)

    log.banner("SMS API Onboarding (POC)")
    dump("配置摘要", {
        "configFile": cfg.get("_configPath"),
        "targetEnv": target_env,
        "region": region,
        "teamName": team,
        "apiName": api,
        "ticketNum": ticket,
        "keyNameList": key_list,
        "iamEnable": iam_enable,
        "eimAppId": eim_app_id,
        "changeFileName": get(cfg, "changeFileName", "(none)"),
        "updateSecretAccess": update_secret_access,
        "triggerJobTimeout": trigger_job_timeout,
        "sourceVersion": source_version,
        "jenkinsProjectName": jenkins_project,
    })

    if not project:
        log.warn(
            "未指定 project（配置里没有 secretProjectId，也没传 --project）。"
            "后续 Secret Manager 调用会失败。"
        )
    else:
        log.info("目标 project: {}".format(project))

    sm = SecretManagerClient(project, dry_run=args.dry_run, logger=log)
    total = 5

    # ---------------------------------------------------------- STEP 1
    log.step(1, total, "创建专用 RT GSA (Runtime Service Account)")
    log.info("SA 名称      : {}".format(rt_sa))
    log.info("SA 全名      : {}@{}".format(rt_sa, project))
    log.info("用途          : 该 API 运行期读取 secret")
    log.info(
        "  → API iam.service_accounts.create(name={}, display_name='RT GSA for {}')".format(
            rt_sa, api
        )
    )

    # ---------------------------------------------------------- STEP 2
    log.step(2, total, "初始化空 payload 的 secret")
    labels = {
        "team": team,
        "api": api,
        "env": target_env,
        "ticket": ticket,
    }
    sm.create_secret(secret_id, labels=labels)
    log.info("secret id     : {}".format(secret_id))
    log.info("labels        : {}".format(labels))
    log.info("初始 payload  : <空>（真正的值由 secret_api_create.py 写入）")

    # ---------------------------------------------------------- STEP 3
    log.step(3, total, "分配 IAM 角色")
    log.info("Group         : {}".format(group))
    log.info("  → IAM add-iam-policy-binding(member=group:{}, role={})".format(
        group, ROLE_SECRET_ADMIN
    ))
    log.info("RT GSA        : {}@{}".format(rt_sa, project))
    log.info("  → IAM add-iam-policy-binding(member=serviceAccount:{}, role={})".format(
        rt_sa, ROLE_SECRET_VIEWER
    ))
    if iam_enable:
        log.info("  → IAM add-iam-policy-binding(member=serviceAccount:{}, role={})".format(
            rt_sa, ROLE_IAM_SERVICE_ACCOUNT_ADMIN
        ))
    else:
        log.info("iamEnable=false → 跳过 IAM 管理员角色绑定")

    if update_secret_access:
        log.info("updateSecretAccess=true → 后续需要刷新 secret 的 accessor 列表")
    else:
        log.info("updateSecretAccess=false → 不改动已有 accessor")

    # ---------------------------------------------------------- STEP 4
    log.step(4, total, "更新 API 元数据 (yaml)")
    change_file = resolve_change_file(cfg)
    if not change_file:
        log.warn("配置里没有 changeFileName，跳过元数据更新")
    else:
        log.info("changeFile    : {}".format(change_file))
        if os.path.exists(change_file):
            log.info("  → 文件已存在，POC 中只读展示，不做修改")
            try:
                import yaml

                with open(change_file, "r", encoding="utf-8") as f:
                    data = yaml.safe_load(f)
                dump("现有 yaml 内容", data or {})
            except Exception as e:
                log.warn("读取 yaml 失败({})，跳过".format(e))
        else:
            log.info("  → 文件不存在，POC 中不创建（真实实现里这里会生成初始元数据）")

    # ---------------------------------------------------------- STEP 5
    log.step(5, total, "触发下游 Jenkins 任务")
    log.info("jenkinsProject: {}".format(jenkins_project or "(none)"))
    log.info("timeout        : {}s".format(trigger_job_timeout))
    log.info(
        "  → API jenkins.build(project={}, timeout={})".format(
            jenkins_project or "-", trigger_job_timeout
        )
    )

    # ---------------------------------------------------------- 汇总
    log.banner("Onboarding 完成 (POC)")
    dump("结果", {
        "secretId": secret_id,
        "rtServiceAccount": "{}@{}".format(rt_sa, project),
        "group": group,
        "keysPending": key_list,
        "nextStep": "python3 secret_api_create.py --config secret.create.json",
    })
    return 0


def main():
    parser = base_parser("SMS API Onboarding (POC)")
    parser.add_argument("--env", help="覆盖配置里的 targetEnv")
    args = parser.parse_args()

    log = Logger(verbose=args.verbose)
    try:
        cfg = load_config(args.config)
        if args.env:
            cfg["targetEnv"] = args.env
        # 必填校验
        require(cfg, *REQUIRED)
        return run_onboarding(cfg, args, log)
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
