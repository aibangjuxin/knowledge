"""
POC 公共库：配置加载、参数解析、日志、Secret Manager 客户端封装。

设计目标（本次 POC 的重点）：
  1. 所有入参通过 --config <file.json> 传入，脚本本身不硬编码业务参数；
  2. 依赖尽量少：只用标准库；google-cloud-secretmanager / requests /
     pyyaml 都是「有就用、没有就降级」，保证裸机就能跑通；
  3. 真实调用与 dry-run 走同一套代码路径，方便对照。
"""

import argparse
import datetime
import json
import os
import sys

# ---------------------------------------------------------------- 常量

# 模拟环境里 secret 的命名规则：{teamName}-{apiName}-{targetEnv}
SECRET_ID_TEMPLATE = "{team}-{api}-{env}"

# 模拟环境下 IAM 角色
ROLE_SECRET_ADMIN = "roles/secretmanager.admin"
ROLE_SECRET_ACCESSOR = "roles/secretmanager.secretAccessor"
ROLE_SECRET_VIEWER = "roles/secretmanager.viewer"

# onboarding 流程里用到的 GCP 角色（模拟 IAM）
ROLE_IAM_SERVICE_ACCOUNT_USER = "roles/iam.serviceAccountUser"
ROLE_IAM_SERVICE_ACCOUNT_ADMIN = "roles/iam.serviceAccountAdmin"

HERE = os.path.dirname(os.path.abspath(__file__))          # app/
APP_DIR = HERE
CONFIG_DIR = os.path.join(HERE, "config")                   # app/config/
STEPS_DIR = os.path.join(HERE, "steps")                     # app/steps/


# ---------------------------------------------------------------- 日志

class Logger:
    """带时间戳和级别的极简日志器。"""

    LEVELS = {"DEBUG": 10, "INFO": 20, "WARN": 30, "ERROR": 40}

    def __init__(self, verbose=False):
        self.verbose = verbose

    def _emit(self, level, msg):
        if level == "DEBUG" and not self.verbose:
            return
        ts = datetime.datetime.now().strftime("%H:%M:%S")
        print("[{}] {:<5} {}".format(ts, level, msg), flush=True)

    def debug(self, msg):
        self._emit("DEBUG", msg)

    def info(self, msg):
        self._emit("INFO", msg)

    def warn(self, msg):
        self._emit("WARN", msg)

    def error(self, msg):
        self._emit("ERROR", msg)

    def step(self, n, total, title):
        self.info("─" * 68)
        self.info("STEP {}/{}  {}".format(n, total, title))

    def banner(self, title):
        print()
        print("=" * 68)
        print("  {}".format(title))
        print("=" * 68, flush=True)


# ---------------------------------------------------------------- 配置

class ConfigError(Exception):
    pass


def load_config(path):
    """读取 JSON 配置文件。"""
    if not path:
        raise ConfigError("--config 不能为空")
    if not os.path.exists(path):
        raise ConfigError("配置文件不存在: {}".format(path))
    try:
        with open(path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except json.JSONDecodeError as e:
        raise ConfigError("配置文件不是合法 JSON ({}): {}".format(path, e))
    if not isinstance(cfg, dict):
        raise ConfigError("配置文件根节点必须是 object: {}".format(path))
    cfg["_configPath"] = os.path.abspath(path)
    return cfg


def require(cfg, *keys):
    """取必填字段，缺失就抛错（把配置校验前置，脚本跑一半才失败最烦人）。"""
    missing = []
    out = {}
    for k in keys:
        if k not in cfg or cfg[k] in (None, ""):
            missing.append(k)
        else:
            out[k] = cfg[k]
    if missing:
        raise ConfigError(
            "配置缺少必填字段: {}  (文件: {})".format(
                ", ".join(missing), cfg.get("_configPath", "?")
            )
        )
    return out


def get(cfg, key, default=None):
    v = cfg.get(key, default)
    return default if v is None else v


def build_secret_id(cfg):
    """按命名规则推导 secret id。"""
    return SECRET_ID_TEMPLATE.format(
        team=get(cfg, "teamName", "team"),
        api=get(cfg, "apiName", "api"),
        env=get(cfg, "targetEnv", "dev"),
    )


# ---------------------------------------------------------------- 参数

def base_parser(description):
    """所有脚本共用的命令行参数。"""
    p = argparse.ArgumentParser(description=description)
    p.add_argument("--config", required=True, help="配置文件路径（JSON）")
    p.add_argument("--project", help="覆盖配置里的 GCP project id")
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="只打印将要执行的动作，不真正调用 GCP API",
    )
    p.add_argument("-v", "--verbose", action="store_true", help="打印 DEBUG 级日志")
    return p


def resolve_project(cfg, args):
    """project 优先级：--project > 配置里的 secretProjectId > 环境变量。"""
    return (
        getattr(args, "project", None)
        or cfg.get("secretProjectId")
        or os.environ.get("GOOGLE_CLOUD_PROJECT")
        or os.environ.get("GCP_PROJECT")
    )


# ---------------------------------------------------------------- ADC 探测

def detect_adc():
    """
    探测 Application Default Credentials 是否可用。

    关键点（实测）：
      * gcloud auth login            → 写 $CLOUDSDK_CONFIG/credentials.db
      * gcloud auth application-default login → 写 $CLOUDSDK_CONFIG/application_default_credentials.json
      * Python SDK (google-auth)      → 只读 ADC json，不读 credentials.db
      * GOOGLE_APPLICATION_CREDENTIALS → 优先级最高，直接指定 ADC json 路径

    所以：**只跑 gcloud auth login，Python 脚本仍然拿不到凭据**。
    """
    env_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if env_path:
        if os.path.exists(env_path):
            return {
                "found": True,
                "source": "GOOGLE_APPLICATION_CREDENTIALS",
                "path": env_path,
            }
        return {
            "found": False,
            "source": "GOOGLE_APPLICATION_CREDENTIALS",
            "path": env_path,
            "reason": "环境变量指向的文件不存在",
        }

    cfg_dir = os.environ.get("CLOUDSDK_CONFIG") or os.path.join(
        os.path.expanduser("~"), ".config", "gcloud"
    )
    adc = os.path.join(cfg_dir, "application_default_credentials.json")
    if os.path.exists(adc):
        return {"found": True, "source": "ADC file", "path": adc}

    # 退化：metadata server（GCE/GKE/Cloud Run 上由 google-auth 自动探测）
    return {
        "found": False,
        "source": "none",
        "path": None,
        "reason": "未找到 ADC（无 GOOGLE_APPLICATION_CREDENTIALS，且 {} 不存在）".format(adc),
        "adcPath": adc,
        "gcloudDb": os.path.join(cfg_dir, "credentials.db"),
    }


def print_adc_hint(log):
    """ADC 不可用时，打印怎么修。"""
    info = detect_adc()
    log.info("ADC 探测: found={} source={} path={}".format(
        info["found"], info["source"], info.get("path")
    ))
    if info["found"]:
        return info

    log.warn("未检测到 Application Default Credentials：{}".format(
        info.get("reason", "")
    ))
    if info.get("gcloudDb") and os.path.exists(info["gcloudDb"]):
        log.warn(
            "发现 {} 存在，但 Python SDK 不会读它（gcloud CLI 专用）。".format(
                info["gcloudDb"]
            )
        )
    log.warn("修复方式（三选一）：")
    log.warn("  1) 生成 ADC：gcloud auth application-default login --no-launch-browser")
    log.warn("  2) 指定 ADC：export GOOGLE_APPLICATION_CREDENTIALS=/path/to/adc.json")
    log.warn("  3) 用 SA key：export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json")
    return info


# ---------------------------------------------------------------- SM 客户端

class SecretManagerClient:
    """
    Secret Manager 客户端封装。

    - 装了 google-cloud-secretmanager 且非 dry-run → 走真实 API
    - 否则 → 退化为「模拟客户端」，把所有调用打印出来
    """

    def __init__(self, project_id, dry_run=False, logger=None):
        self.project_id = project_id
        self.dry_run = dry_run
        self.log = logger or Logger()
        self._client = None
        self._mode = "simulate"

        if dry_run:
            self._mode = "dry-run"
            self.log.info("SecretManager 模式: DRY-RUN（不调用真实 API）")
            return

        try:
            from google.cloud import secretmanager  # noqa: F401
            from google.cloud.secretmanager_v1.services import secret_manager_service

            self._client = secret_manager_service.SecretManagerServiceClient()
            self._mode = "real"
            self.log.info(
                "SecretManager 模式: REAL (project={})".format(project_id)
            )
            adc = detect_adc()
            self.log.info(
                "ADC 来源: {} ({})".format(adc["source"], adc.get("path"))
            )
        except Exception as e:  # 没装 SDK / 没有凭据 / 网络问题
            self._mode = "simulate"
            self.log.warn(
                "未能初始化真实客户端({}: {})，降级为模拟模式".format(
                    type(e).__name__, e
                )
            )
            print_adc_hint(self.log)

    # ---- 内部 ----

    def _parent(self):
        return "projects/{}".format(self.project_id)

    def _full_name(self, secret_id):
        return "{}/secrets/{}".format(self._parent(), secret_id)

    # ---- 对外 API ----

    def secret_exists(self, secret_id):
        if self._mode != "real":
            return False
        from google.api_core import exceptions

        try:
            self._client.get_secret(name=self._full_name(secret_id))
            return True
        except exceptions.NotFound:
            return False

    def create_secret(self, secret_id, labels=None, replication_locations=None):
        """创建 secret（已存在则跳过）。"""
        if self._mode != "real":
            self.log.info(
                "  → API create_secret(secret_id={}, labels={}, replication={})".format(
                    secret_id, labels or {}, replication_locations or ["automatic"]
                )
            )
            return {"name": self._full_name(secret_id), "simulated": True}

        from google.cloud.secretmanager_v1.types import secret

        if self.secret_exists(secret_id):
            self.log.info("  → secret 已存在，跳过创建: {}".format(secret_id))
            return {"name": self._full_name(secret_id), "created": False}

        if replication_locations:
            replication = secret.Replication(
                {
                    "user_managed": {
                        "replicas": [{"location": loc} for loc in replication_locations]
                    }
                }
            )
        else:
            replication = secret.Replication.Automatic()

        req = secret.CreateSecretRequest(
            parent=self._parent(),
            secret_id=secret_id,
            secret=secret.Secret(
                replication=replication,
                labels=labels or {},
            ),
        )
        resp = self._client.create_secret(request=req)
        self.log.info("  → secret 创建成功: {}".format(resp.name))
        return {"name": resp.name, "created": True}

    def add_secret_version(self, secret_id, payload, labels=None):
        """给 secret 加一个新 version。"""
        if self._mode != "real":
            preview = payload[:32]
            if isinstance(preview, bytes):
                preview = preview.decode("utf-8", "replace")
            self.log.info(
                "  → API add_secret_version(secret_id={}, payload_len={}, payload={!r})".format(
                    secret_id, len(payload), preview
                )
            )
            return "projects/{}/secrets/{}/versions/1".format(
                self.project_id, secret_id
            )

        from google.cloud.secretmanager_v1.types import secret

        req = secret.AddSecretVersionRequest(
            parent=self._full_name(secret_id),
            payload=secret.Payload(data=payload),
            labels=labels or {},
        )
        resp = self._client.add_secret_version(request=req)
        self.log.info("  → version 创建成功: {}".format(resp.name))
        return resp.name

    def set_iam_policy(self, secret_id, member, role):
        """给 secret 绑定 IAM member。"""
        if self._mode != "real":
            self.log.info(
                "  → API set_iam_policy(secret={}, member={}, role={})".format(
                    secret_id, member, role
                )
            )
            return {"simulated": True}

        from google.iam.v1 import iam_policy_pb2, options_pb2

        policy = self._client.get_iam_policy(
            request=iam_policy_pb2.GetIamPolicyRequest(
                resource=self._full_name(secret_id),
                options=options_pb2.GetPolicyOptions(
                    requested_policy_version=3
                ),
            )
        )
        binding = iam_policy_pb2.Binding(role=role, members=[member])
        policy.bindings.append(binding)
        resp = self._client.set_iam_policy(
            request=iam_policy_pb2.SetIamPolicyRequest(
                resource=self._full_name(secret_id),
                policy=policy,
                update_mask={"paths": {"bindings"}},
            )
        )
        self.log.info("  → IAM 绑定完成: {} -> {}".format(member, role))
        return resp


# ---------------------------------------------------------------- 辅助

def dump(title, obj):
    """漂亮地打印一个对象（POC 里到处都要看参数）。"""
    print()
    print("┌─ {} ".format(title) + "─" * max(0, 60 - len(title)))
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k.startswith("_"):
                continue
            print("│ {:<24} = {}".format(k, json.dumps(v, ensure_ascii=False)))
    else:
        print("│ {}".format(obj))
    print("└" + "─" * 66, flush=True)


def resolve_change_file(cfg):
    """
    定位 changeFileName 指向的 yaml 文件（相对 ob/ 目录）。
    找不到就返回 None，由调用方决定是否创建。
    """
    name = cfg.get("changeFileName")
    if not name:
        return None
    for base in (CONFIG_DIR, os.getcwd(), HERE):
        p = os.path.join(base, name)
        if os.path.exists(p):
            return p
    return os.path.join(CONFIG_DIR, name)
