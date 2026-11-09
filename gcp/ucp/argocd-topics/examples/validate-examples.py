#!/usr/bin/env python3
"""
校验 examples/ 目录下的**静态配置片段** —— 把「文档里的最佳实践」变成可执行检查。

**它解决什么问题**
  examples/ 根目录这堆 YAML（rbac-cm / dex-ldap / githubapp / ha-values /
  redis-pvc / appproject / applicationset-matrix）是整套方案里**最容易抄错**的部分：
  它们全是"配置"而不是"清单"，没有 kubectl 帮你兜底。
  典型事故：
    · argocd-rbac-cm 的 scopes 少了 groups  → 组映射静默失效（谁都没权限）
    · policy.default 写成 role:readonly     → 所有人可读全部 Application
    · HA 里 server.replicas=3 但 ARGOCD_API_SERVER_REPLICAS=1 → 登录被限流误拒
    · dex 里 bindPW 写成明文                 → 密码进 Git
    · Repository Secret 少了 secret-type label → Argo CD 根本不认
    · Redis 用 Deployment + RWO PVC          → 多副本 Multi-Attach 冲突

**它不是什么**
  不是 Argo CD controller，不连集群，不验证运行时行为。
  它只做**静态检查**：语法、字段、值域、交叉引用、危险默认值。

**用法**
    python3 validate-examples.py                # 检查 examples/ 下的示例文件
    python3 validate-examples.py --path <目录>  # 指定目录
    python3 validate-examples.py --strict       # 警告也算失败

**退出码**：0 = 通过；1 = 有 ERROR（或 --strict 下有 WARN）。
"""

import argparse
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "lib"))

from yamlmin import load_all_files, load  # noqa: E402

ERRORS = []
WARNINGS = []
NOTES = []


def err(msg):
    ERRORS.append(msg)


def warn(msg):
    WARNINGS.append(msg)


def note(msg):
    NOTES.append(msg)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

REDACT_MARKERS = ("REDACTED", "xxxx", "<", "CHANGE_ME", "changeme", "PLACEHOLDER")
CRED_KEYS = ("password", "token", "privatekey", "bearerToken", "secretkey",
             "clientsecret", "apikey", "passwd")


def is_placeholder(value):
    """判断一个值是不是"占位符"（而不是真实凭据）。"""
    if value is None:
        return True
    text = str(value).strip()
    if not text:
        return True
    low = text.lower()
    for marker in REDACT_MARKERS:
        if marker.lower() in low:
            return True
    # 指向环境变量 / 外部 Secret 的引用不算明文
    if text.startswith("$"):
        return True
    return False


def get(doc, *path, default=None):
    """按路径取值：get(doc, "metadata", "name")。

    任何一层不是字典或键不存在，都返回 default（不抛异常）。
    """
    cur = doc
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


# ---------------------------------------------------------------------------
# 检查项
# ---------------------------------------------------------------------------

CLUSTER_SCOPED_KINDS = {
    "Namespace", "ClusterRole", "ClusterRoleBinding", "CustomResourceDefinition",
    "StorageClass", "IngressClass", "PriorityClass", "APIService",
    "MutatingWebhookConfiguration", "ValidatingWebhookConfiguration",
    "CSIDriver", "CSINode", "VolumeAttachment", "Node",
}


def check_general(doc, name):
    """所有 K8s 资源都要满足的底线。"""
    if not isinstance(doc, dict):
        err(f"[{name}] 不是合法的 K8s 对象（解析结果不是字典）")
        return False
    if not doc.get("apiVersion"):
        err(f"[{name}] 缺少 apiVersion")
    if not doc.get("kind"):
        err(f"[{name}] 缺少 kind")
    meta = doc.get("metadata") or {}
    if not meta.get("name"):
        err(f"[{name}] 缺少 metadata.name")
    if not meta.get("namespace") and doc.get("kind") not in CLUSTER_SCOPED_KINDS:
        warn(f"[{name}] 没写 namespace（Argo CD 里通常必须显式写 argocd）")
    return True


def check_argocd_rbac_cm(doc, name):
    """argocd-rbac-cm：组映射能不能生效、默认策略安不安全。"""
    data = doc.get("data") or {}

    # ① scopes 必须含 groups
    scopes = str(data.get("scopes", ""))
    if "groups" not in scopes:
        err(f"[{name}] scopes={scopes!r} 不含 groups"
            f" → 所有 `g, <组名>, <角色>` 规则永不生效（组映射静默失效）")
    else:
        note(f"[{name}] scopes={scopes} ✓ 含 groups")

    # ② policy.default 的安全性
    default = str(data.get("policy.default", "")).strip()
    if not default:
        err(f"[{name}] 缺少 policy.default → Argo CD 用内置默认值（role:readonly）")
    elif default == "role:readonly":
        err(f"[{name}] policy.default=role:readonly"
            f" → 所有已认证用户可读**全部** Application（最常见的事故配置）")
    elif default == "role:admin":
        err(f"[{name}] policy.default=role:admin → 任何人都是全局管理员")
    else:
        note(f"[{name}] policy.default={default}")

    # ③ policy.csv 的行格式
    csv = str(data.get("policy.csv", ""))
    for lineno, line in enumerate(csv.splitlines(), 1):
        raw = line.strip()
        if not raw or raw.startswith("#"):
            continue
        parts = [p.strip() for p in raw.split(",")]
        if parts[0] == "p":
            if len(parts) != 6:
                err(f"[{name}] policy.csv 第 {lineno} 行：p 规则应有 6 段，实际 {len(parts)}")
            elif parts[5] not in ("allow", "deny"):
                err(f"[{name}] policy.csv 第 {lineno} 行：effect={parts[5]!r} 非法（allow/deny）")
        elif parts[0] == "g":
            if len(parts) != 3:
                err(f"[{name}] policy.csv 第 {lineno} 行：g 规则应有 3 段，实际 {len(parts)}")
        else:
            err(f"[{name}] policy.csv 第 {lineno} 行：以 {parts[0]!r} 开头（只支持 p / g）")

    # ④ 主体命名建议带前缀（避免与 SSO claim 撞名）
    groups = set()
    for line in csv.splitlines():
        parts = [p.strip() for p in line.strip().split(",")]
        if len(parts) == 3 and parts[0] == "g":
            groups.add(parts[1])
    for g in sorted(groups):
        if ":" not in g and not g.startswith("role:"):
            warn(f"[{name}] 组 {g!r} 没有命名空间前缀"
                 f"（建议 my-org:xxx，避免与 SSO claim 撞名）")


def check_repository_secret(doc, name):
    """Repository / cluster Secret：label 对不对、凭据是不是明文。"""
    labels = (doc.get("metadata") or {}).get("labels") or {}
    secret_type = labels.get("argocd.argoproj.io/secret-type")
    data = doc.get("stringData") or doc.get("data") or {}

    if not secret_type:
        # 普通的业务 Secret（不是 Argo CD 凭据）—— 只查明文密码，不要求 label
        if "url" in data:
            err(f"[{name}] 看起来是 Argo CD 凭据 Secret（带 url）"
                f"但缺少 label argocd.argoproj.io/secret-type → Argo CD 完全不认它")
        _check_plaintext(name, data)
        return
    if secret_type not in ("repository", "repo-creds", "cluster"):
        err(f"[{name}] secret-type={secret_type!r} 非法"
            f"（repository / repo-creds / cluster）")
        return

    if secret_type in ("repository", "repo-creds"):
        if not data.get("url"):
            err(f"[{name}] secret-type={secret_type} 但没有 url")

    if secret_type == "cluster":
        for key in ("name", "server", "config"):
            if not data.get(key):
                err(f"[{name}] cluster Secret 缺少 {key}")
        cfg = str(data.get("config", ""))
        if cfg:
            try:
                json.loads(cfg)
            except Exception as exc:
                err(f"[{name}] cluster Secret 的 config 不是合法 JSON：{exc}")

    _check_plaintext(name, data)

    # PEM 私钥完整性
    key = data.get("githubAppPrivateKey")
    if key and "BEGIN" in str(key):
        text = str(key)
        if "END" not in text:
            err(f"[{name}] githubAppPrivateKey 只有 BEGIN 没有 END（PEM 不完整）")


def _check_plaintext(name, data):
    """凭据明文检查（对任何 Secret 都适用）。"""
    for key, value in data.items():
        if key.lower() in CRED_KEYS and not is_placeholder(value):
            err(f"[{name}] {key} 看起来是**明文凭据**"
                f" → 请用 Sealed Secrets / SOPS / External Secrets 注入")


def check_dex_config(doc, name):
    """Dex：组能不能进 token（OIDC/LDAP connector 各自的开关）、密码是不是明文、TLS 三选一。"""
    data = doc.get("data") or {}
    raw = data.get("dex.config")
    if not raw:
        err(f"[{name}] argocd-cm 没有 dex.config")
        return
    try:
        cfg = load(str(raw))
    except Exception as exc:
        err(f"[{name}] dex.config 不是合法 YAML：{exc}")
        return
    if not isinstance(cfg, dict):
        err(f"[{name}] dex.config 解析结果不是字典")
        return

    connectors = cfg.get("connectors") or []
    if not connectors:
        err(f"[{name}] dex.config 没有 connectors")
        return

    for conn in connectors:
        cid = conn.get("id", "?")
        ctype = conn.get("type")
        ccfg = conn.get("config") or {}

        if ctype == "ldap":
            # ① TLS 三选一
            tls_flags = [f for f in ("insecureNoSSL", "insecureSkipVerify", "startTLS") if f in ccfg]
            if not tls_flags:
                warn(f"[{name}] ldap connector {cid} 没写任何 TLS 选项"
                     f"（host 端口会决定行为，最好显式写 startTLS）")
            if ccfg.get("insecureNoSSL"):
                err(f"[{name}] ldap connector {cid} insecureNoSSL=true → 密码明文传输")
            if ccfg.get("insecureSkipVerify"):
                err(f"[{name}] ldap connector {cid} insecureSkipVerify=true → 不校验证书")

            # ② bindPW 必须是环境变量引用，不能是明文
            bind_pw = str(ccfg.get("bindPW", ""))
            if bind_pw and not bind_pw.startswith("$"):
                err(f"[{name}] ldap connector {cid} bindPW 是明文"
                    f" → 必须写成 $dex.ldap.bindPW 并用 Secret 注入")

            # ③ 组搜索（LDAP 模式下这是组能不能进 token 的**唯一**决定因素）
            if not ccfg.get("groupSearch"):
                err(f"[{name}] ldap connector {cid} 没有 groupSearch"
                    f" → token 里不会有组 → RBAC 的 g, 规则全部失效")
            gs = ccfg.get("groupSearch") or {}
            if gs and not gs.get("nameAttr"):
                warn(f"[{name}] ldap connector {cid} groupSearch 没写 nameAttr"
                     f"（组名取不到）")
            if gs and not gs.get("userMatchers"):
                warn(f"[{name}] ldap connector {cid} groupSearch 没写 userMatchers"
                     f"（组成员匹配不上 → 组永远查不到）")

        elif ctype == "oidc":
            # OIDC connector：组来自上游 IdP，必须显式放行并向上游请求
            if ccfg.get("insecureEnableGroups") is not True:
                err(f"[{name}] oidc connector {cid} 缺 insecureEnableGroups: true"
                    f" → 上游 IdP 的组不会进 token → RBAC 组映射失效")
            scopes = ccfg.get("scopes") or []
            if isinstance(scopes, str):
                scopes = [scopes]
            if "groups" not in scopes:
                err(f"[{name}] oidc connector {cid} scopes={scopes} 不含 groups"
                    f" → 没向上游 IdP 请求组")
            secret = str(ccfg.get("clientSecret", ""))
            if secret and not secret.startswith("$"):
                err(f"[{name}] oidc connector {cid} clientSecret 是明文"
                    f" → 必须写成 $dex.<name>.clientSecret 并用 Secret 注入")

    # ④ 顶层的 insecureEnableGroups / scopes 不是 Dex 的配置字段 → 写了也是装饰
    for key in ("insecureEnableGroups", "scopes"):
        if key in cfg:
            warn(f"[{name}] dex.config 顶层有 {key}"
                 f" → Dex 会忽略它（这不是 Dex 的顶层字段）"
                 f"；OIDC connector 的这两个字段要写在 connector 的 config 里面，"
                 f"LDAP connector 根本不需要它们")


def check_oidc_config(doc, name):
    """OIDC 直连（模式 A）：issuer 对不对、密钥是不是明文、组能不能进 token。"""
    data = doc.get("data") or {}

    # ① url 必须是 https，否则回调地址不对
    url = str(data.get("url", ""))
    if not url:
        err(f"[{name}] argocd-cm 没有 url → OIDC 回调地址推不出来")
    elif not url.startswith("https://"):
        err(f"[{name}] url={url!r} 不是 https → OIDC 回调/登出跳转会有问题")

    raw = data.get("oidc.config")
    if not raw:
        err(f"[{name}] argocd-cm 没有 oidc.config")
        return
    try:
        cfg = load(str(raw))
    except Exception as exc:
        err(f"[{name}] oidc.config 不是合法 YAML：{exc}")
        return
    if not isinstance(cfg, dict):
        err(f"[{name}] oidc.config 解析结果不是字典")
        return

    # ② 必填字段
    issuer = str(cfg.get("issuer", ""))
    if not issuer:
        err(f"[{name}] oidc.config 缺 issuer")
    elif not issuer.startswith("https://"):
        err(f"[{name}] oidc.config issuer={issuer!r} 不是 https")

    if not cfg.get("clientID"):
        err(f"[{name}] oidc.config 缺 clientID")

    # ③ clientSecret 必须是 Secret 引用，不能是明文
    secret = str(cfg.get("clientSecret", ""))
    if not secret:
        err(f"[{name}] oidc.config 缺 clientSecret")
    elif not secret.startswith("$"):
        err(f"[{name}] oidc.config clientSecret 是明文"
            f" → 必须写成 $oidc.<name>.clientSecret 或 $<secret>:<key> 并用 Secret 注入")

    # ④ 组能不能进 token（三条路径任选其一）
    scopes = cfg.get("requestedScopes") or []
    if isinstance(scopes, str):
        scopes = [scopes]
    claims = cfg.get("requestedIDTokenClaims") or {}
    has_groups = (
        "groups" in scopes
        or "groups" in claims
        or cfg.get("enableUserInfoGroups") is True
    )
    if not has_groups:
        warn(f"[{name}] oidc.config 里找不到任何取组途径"
             f"（requestedScopes 无 groups / requestedIDTokenClaims 无 groups / "
             f"enableUserInfoGroups 未开）→ token 里没有组 → RBAC 的 g, 规则失效")
    else:
        note(f"[{name}] oidc.config 取组途径 ✓")

    # ⑤ email scope：按邮箱授权个别用户时才需要
    if "email" not in scopes:
        warn(f"[{name}] oidc.config requestedScopes 不含 email"
             f" → 只能用组授权，无法按邮箱授权个别用户")

    # ⑥ refreshTokenThreshold 格式
    threshold = str(cfg.get("refreshTokenThreshold", ""))
    if threshold:
        m = re.match(r"^(\d+)([smh])$", threshold)
        if not m:
            err(f"[{name}] oidc.config refreshTokenThreshold={threshold!r} "
                f"格式不合法（应为 30s / 5m / 1h 这种）")
        elif int(m.group(1)) * {"s": 1, "m": 60, "h": 3600}[m.group(2)] == 0:
            warn(f"[{name}] oidc.config refreshTokenThreshold=0s"
                 f" → Token 过期即需重新登录")


def check_ha_values(doc, name):
    """Helm values（HA）：副本数一致性、dex 必须 1 副本、资源完整性。"""
    server = doc.get("server") or {}
    reps = server.get("replicas")
    api_reps = None
    for env in server.get("env") or []:
        if env.get("name") == "ARGOCD_API_SERVER_REPLICAS":
            api_reps = env.get("value")
    if reps is None:
        err(f"[{name}] server.replicas 缺失")
    if api_reps is None:
        err(f"[{name}] server.env 里缺 ARGOCD_API_SERVER_REPLICAS")
        if reps:
            warn(f"[{name}] HA 下缺 ARGOCD_API_SERVER_REPLICAS，"
                 f"登录会被限流误拒（上游 issue #11387 / #15223）")
    elif str(reps) != str(api_reps):
        err(f"[{name}] server.replicas={reps} != ARGOCD_API_SERVER_REPLICAS={api_reps}"
            f" → 登录会被限流误拒（上游 issue #11387 / #15223）")
    else:
        note(f"[{name}] server.replicas == ARGOCD_API_SERVER_REPLICAS = {reps} ✓")

    dex = doc.get("dex") or {}
    if dex.get("replicas") is not None and dex["replicas"] != 1:
        err(f"[{name}] dex.replicas={dex['replicas']}，必须保持 1"
            f"（dex 用内存存储，多副本登录态不一致）")

    for comp in ("controller", "repoServer", "applicationSet"):
        value = (doc.get(comp) or {}).get("replicas")
        if value is not None and int(value) < 1:
            err(f"[{name}] {comp}.replicas={value}（至少 1）")

    # 资源 requests / limits 完整性
    for key in ("controllerContainer", "serverContainer", "repoServerContainer"):
        res = (doc.get(key) or {}).get("resources") or {}
        for side in ("requests", "limits"):
            if side not in res:
                err(f"[{name}] {key}.resources 缺 {side}")
            elif not res[side]:
                err(f"[{name}] {key}.resources.{side} 为空")

    # RBAC scopes
    rbac = get(doc, "configs", "rbac", default={}) or {}
    scopes = str(rbac.get("scopes", ""))
    if scopes and "groups" not in scopes:
        err(f"[{name}] configs.rbac.scopes={scopes!r} 不含 groups → 组映射失效")

    # URL 必须是 https
    url = str(get(doc, "configs", "cm", "url", default="") or "")
    if url and not url.startswith("https://"):
        err(f"[{name}] configs.cm.url={url} 不是 https → Dex 回调会失败")


def check_redis_statefulset(doc, name):
    """业务 Redis：StatefulSet + volumeClaimTemplates 才是 RWO 的正确用法。"""
    kind = doc.get("kind")
    if kind != "StatefulSet":
        if kind == "Deployment":
            err(f"[{name}] 用 Deployment + RWO PVC → 多副本必然 Multi-Attach 冲突"
                f"（应改成 StatefulSet + volumeClaimTemplates）")
        return
    spec = doc.get("spec") or {}
    svc_name = spec.get("serviceName")
    if not svc_name:
        err(f"[{name}] StatefulSet 缺 spec.serviceName")
    vcts = spec.get("volumeClaimTemplates")
    if not vcts:
        err(f"[{name}] StatefulSet 没有 volumeClaimTemplates → 没有持久化（重启即丢数据）")
    for vct in vcts or []:
        vname = get(vct, "metadata", "name", default="?")
        sc = get(vct, "spec", "storageClassName")
        if not sc:
            err(f"[{name}] volumeClaimTemplates[{vname}] 没写 storageClassName")
        else:
            note(f"[{name}] volumeClaimTemplates[{vname}].storageClassName={sc}"
                 f" ← 上生产前用 `kubectl get storageclass` 实查")
        modes = get(vct, "spec", "accessModes", default=[]) or []
        if "ReadWriteOnce" in modes and len(vcts) > 1:
            note(f"[{name}] RWO + 每副本独立 PVC 是正确组合 ✓")

    # 容器探针
    tmpl = get(doc, "spec", "template", "spec", default={}) or {}
    for c in tmpl.get("containers") or []:
        cname = c.get("name", "?")
        if not c.get("readinessProbe"):
            err(f"[{name}] 容器 {cname} 没有 readinessProbe"
                f" → Service 会把流量打到未就绪的 Pod")
        if not c.get("resources"):
            warn(f"[{name}] 容器 {cname} 没有 resources")


def check_appproject(doc, name):
    """AppProject：角色名格式、白/黑名单冲突、default 项目的破坏性收紧。"""
    pname = get(doc, "metadata", "name", default="")
    spec = doc.get("spec") or {}

    # ① 角色名必须是 proj:<project>:<role>
    for role in spec.get("roles") or []:
        rname = role.get("name", "?")
        for policy in role.get("policies") or []:
            subject = str(policy).split(",")[1].strip() if "," in str(policy) else ""
            expected = f"proj:{pname}:{rname}"
            if subject and subject != expected:
                err(f"[{name}] role {rname} 的策略主体是 {subject!r}，"
                    f"应为 {expected!r} → 这条规则不会生效")

    # ② 白/黑名单冲突（黑名单优先，但配对容易搞错）
    for scope, wkey, bkey in (("cluster", "clusterResourceWhitelist", "clusterResourceBlacklist"),
                              ("namespace", "namespaceResourceWhitelist", "namespaceResourceBlacklist")):
        white = {(w.get("group"), w.get("kind"), w.get("name")) for w in spec.get(wkey) or []}
        black = {(b.get("group"), b.get("kind"), b.get("name")) for b in spec.get(bkey) or []}
        for item in sorted(white & black):
            warn(f"[{name}] {item[0]}/{item[1]} 同时在 {scope}Resource 白名单和黑名单里"
                 f"（黑名单优先 → 白名单那一行等于没用）")

    # ③ destinations 为空
    if not spec.get("destinations"):
        if pname == "default":
            warn(f"[{name}] default 项目 destinations 被清空 → "
                 f"任何仍在 default 项目的 Application 都会被拒绝同步")
        else:
            err(f"[{name}] destinations 为空 → 该项目下所有 Application 都无法同步")

    # ④ sourceRepos 为空（注意：'-' 命名的子项目会**继承**父项目的约束）
    if not spec.get("sourceRepos"):
        parent = pname.rsplit("-", 1)[0] if "-" in pname else None
        if pname == "default":
            warn(f"[{name}] default 项目 sourceRepos 被清空（收紧 default 是破坏性操作）")
        elif parent:
            note(f"[{name}] sourceRepos 为空 → 继承父项目 {parent} 的 sourceRepos（正常）")
        else:
            err(f"[{name}] sourceRepos 为空 → 该项目无法从任何仓库同步")

    # ⑤ finalizer 会级联删除
    for f in (doc.get("metadata") or {}).get("finalizers") or []:
        if f == "resources-finalizer.argocd.argoproj.io":
            warn(f"[{name}] 带 resources-finalizer → 删除该 AppProject 会级联删除"
                 f"它名下所有集群资源")


def check_applicationset(doc, name):
    """ApplicationSet：project 必须显式、missingkey=error、boolean 不能模板化。"""
    spec = doc.get("spec") or {}
    tpl = spec.get("template") or {}
    tspec = tpl.get("spec") or {}

    project = tspec.get("project")
    if not project:
        err(f"[{name}] template.spec.project 没写"
            f" → 生成的 Application 落到 default 项目（最宽松）→ 严重风险")
    elif project == "default":
        err(f"[{name}] template.spec.project=default → 生成的 Application 落到最宽松的项目")
    elif isinstance(project, str) and "{{" in project:
        note(f"[{name}] template.spec.project={project}（来自清单文件）")

    options = spec.get("goTemplateOptions") or []
    if spec.get("goTemplate"):
        if "missingkey=error" not in options:
            warn(f"[{name}] goTemplate=true 但 goTemplateOptions={options} 不含 missingkey=error"
                 f" → 变量写错时静默渲染成空字符串")
    else:
        warn(f"[{name}] 没开 goTemplate → 模板语法是 legacy 的 {{path.basename}} 那套")

    # boolean 字段不能模板化
    automated = get(tspec, "syncPolicy", "automated", default={}) or {}
    for key in ("prune", "selfHeal"):
        value = automated.get(key)
        if isinstance(value, str) and "{{" in value:
            err(f"[{name}] syncPolicy.automated.{key}={value!r} 是模板字符串"
                f" → CRD 里它是 boolean，API server 会以 "
                f'"must be of type boolean" 拒掉')

    # 模板变量必须能被 generator 提供
    provided = set()
    for gen in spec.get("generators") or []:
        git = gen.get("git") if isinstance(gen, dict) else None
        if not git:
            continue
        for f in git.get("files") or []:
            provided.update(f.get("flatten") or [])
            provided.update(f.get("path", "").split("/"))
    for text in _iter_strings(tpl):
        for var in re.findall(r"\{\{\s*\.([A-Za-z_][\w]*)\s*\}\}", text):
            if provided and var not in provided:
                warn(f"[{name}] 模板用了 '{{{{.{var}}}}}' 但生成器没提供该变量"
                     f"（missingkey=error 会让整个 AppSet 报错）")


def _iter_strings(node):
    if isinstance(node, dict):
        for value in node.values():
            yield from _iter_strings(value)
    elif isinstance(node, list):
        for item in node:
            yield from _iter_strings(item)
    elif isinstance(node, str):
        yield node


# ---------------------------------------------------------------------------
# 分发
# ---------------------------------------------------------------------------

def _looks_like_helm_values(doc):
    """判断一个没有 apiVersion/kind 的文件是不是 Helm values（argo-cd chart）。"""
    if not isinstance(doc, dict):
        return False
    markers = {"server", "controller", "dex", "repoServer", "applicationSet",
               "configs", "global", "redis", "metrics"}
    return bool(markers & set(doc.keys()))


def dispatch(doc, name, fname=""):
    """按 kind 把文档分发给对应的专项检查函数。"""
    kind = doc.get("kind")
    meta_name = get(doc, "metadata", "name", default="") or ""
    full = f"{name}::{meta_name}" if meta_name else name

    if kind == "ConfigMap" and meta_name == "argocd-rbac-cm":
        check_argocd_rbac_cm(doc, full)
    elif kind == "ConfigMap" and meta_name == "argocd-cm":
        data = doc.get("data") or {}
        # 三种模式二选一：OIDC 直连（oidc.config）或 Dex（dex.config）
        if data.get("oidc.config"):
            check_oidc_config(doc, full)
        if data.get("dex.config"):
            check_dex_config(doc, full)
        if not data.get("oidc.config") and not data.get("dex.config"):
            err(f"[{full}] argocd-cm 既没有 oidc.config 也没有 dex.config"
                f" → 没有任何 SSO 入口")
    elif kind == "Secret":
        check_repository_secret(doc, full)
    elif kind == "StatefulSet":
        check_redis_statefulset(doc, full)
    elif kind == "AppProject":
        check_appproject(doc, full)
    elif kind == "ApplicationSet":
        check_applicationset(doc, full)
    elif kind is None:
        # 非 K8s 资源（Helm values 之类的纯配置文件）
        if "values" in fname or _looks_like_helm_values(doc):
            check_ha_values(doc, fname)
        else:
            note(f"{fname}: 不是 K8s 资源（无 apiVersion/kind），已跳过")
    else:
        note(f"{full}: kind={kind} 无专项检查（只做了通用检查）")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=_HERE,
                    help="要检查的目录（默认：脚本所在目录，只看第一层 *.yaml）")
    ap.add_argument("--strict", action="store_true", help="警告也算失败")
    args = ap.parse_args()

    root = os.path.abspath(args.path)
    files = sorted(f for f in os.listdir(root)
                   if f.endswith((".yaml", ".yml")) and os.path.isfile(os.path.join(root, f)))
    if not files:
        print(f"{root} 下没有 YAML 文件")
        return 0

    total_docs = 0
    for fname in files:
        path = os.path.join(root, fname)
        try:
            docs = load_all_files(path)
        except Exception as exc:
            err(f"[{fname}] YAML 解析失败：{exc}")
            continue
        for idx, doc in enumerate(docs):
            if doc is None:
                continue
            total_docs += 1
            label = fname if len(docs) == 1 else f"{fname}#{idx + 1}"
            if doc.get("apiVersion") or doc.get("kind"):
                if check_general(doc, label):
                    dispatch(doc, label, fname)
            else:
                dispatch(doc, label, fname)

    print(f"检查了 {len(files)} 个文件、{total_docs} 个资源\n")
    for msg in WARNINGS:
        print(f"[WARN ] {msg}")
    for msg in ERRORS:
        print(f"[ERROR] {msg}")
    if NOTES:
        print()
        for msg in NOTES:
            print(f"[NOTE ] {msg}")

    print()
    if ERRORS:
        print(f"✗ {len(ERRORS)} 个错误，{len(WARNINGS)} 个警告")
        return 1
    if args.strict and WARNINGS:
        print(f"✗ --strict：{len(WARNINGS)} 个警告")
        return 1
    print(f"✓ 校验通过（{len(WARNINGS)} 个警告）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
