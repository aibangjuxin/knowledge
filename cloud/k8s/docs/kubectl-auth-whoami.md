# kubectl auth whoami 探索笔记

> 主题：kubectl 内置的 `auth` 子命令族，重点是 `kubectl auth whoami`。
> 本文基于官方命令帮助、SelfSubjectReview API 语义整理；末尾附本机客户端版本记录。

---

## 1. 一句话说明

`kubectl auth whoami` 会向 API Server 发起一次 **SelfSubjectReview** 请求，把"**我当前是以什么身份被认证的**"打印出来，包括：

- `username`：用户名（例如 `user@example.com`、`system:serviceaccount:ns:sa`）
- `uid`：该身份的唯一标识
- `groups`：所属用户组（RBAC 的绑定维度，例如 `system:authenticated`、`system:masters`）
- `extra`：认证层附加的自定义属性（OIDC claims、LDAP 属性、token webhook 塞入的字段等）

它回答的是"**我是谁**"，而不是"**我能干什么**"（后者是 `kubectl auth can-i`）。

命令本身标记为 **Experimental（实验性）**，但在生产环境排查身份问题已经相当常用。

---

## 2. 出现背景与版本

| 项目 | 说明 |
| --- | --- |
| 所属 API | `authentication.k8s.io/v1` 的 **SelfSubjectReview**（非默认启用的 API，但 kube-apiserver 默认提供） |
| Kubernetes 引入 | v1.26 alpha，v1.27 beta |
| kubectl 内置 | 自 v1.26 起 `kubectl` 内置 `auth whoami`，无需安装插件 |
| 相关 API | `SelfSubjectAccessReview`（can-i 用）、`SelfSubjectRulesReview`（can-i --list 用）、`SubjectAccessReview`（管理员查他人） |

服务端实现位置：`pkg/registry/authentication/selfsubjectreview`。

---

## 3. 基本用法

```bash
# 最简：默认表格输出
kubectl auth whoami

# JSON 输出（便于 jq 处理）
kubectl auth whoami -o json

# YAML 输出
kubectl auth whoami -o yaml

# 只取用户名
kubectl auth whoami -o jsonpath='{.status.userInfo.username}'

# 只取所有 group
kubectl auth whoami -o jsonpath='{.status.userInfo.groups[*]}'

# 取 extra 里的某个 claim
kubectl auth whoami -o jsonpath='{.status.userInfo.extra}'
```

### 默认（表格）输出形态

```
ATTRIBUTE   VALUE
username    user@example.com
uid         8f7c1e2a-...
groups      [system:authenticated]
extra       <none>
```

> 具体列会随服务端返回的字段数量变化，以实际输出为准。

### YAML/JSON 输出形态

```yaml
status:
  userInfo:
    username: user@example.com
    uid: 8f7c1e2a-...
    groups:
    - system:authenticated
    - developers
    extra:
      department: platform
      scope: read-only
```

**JSON 路径要点**：实际 JSON 结构是 `status.userInfo.*`，而不是顶层 `user.*`。写 jsonpath 时容易踩坑。

---

## 4. 命令帮助（kubectl v1.37.3 实测输出）

```
Experimental: Check who you are and your attributes (groups, extra).

        This command is helpful to get yourself aware of the current user attributes,
        especially when dynamic authentication, e.g., token webhook, auth proxy, or OIDC provider,
        is enabled in the Kubernetes cluster.

Examples:
  # Get your subject attributes
  kubectl auth whoami

  # Get your subject attributes in JSON format
  kubectl auth whoami -o json

Options:
    --allow-missing-template-keys=true
    -o, --output=''
    --show-managed-fields=false
    --template=''

Usage:
  kubectl auth whoami [options]
```

**可用选项极少**——只有标准的输出格式类 flag，没有 `--context` 之外的额外业务参数（context/namespace 等是全局 flag）。

```bash
# 指定上下文
kubectl --context <ctx> auth whoami

# 指定命名空间（对 SelfSubjectReview 实际无影响，但可与其他命令保持一致）
kubectl -n <ns> auth whoami
```

### `kubectl auth` 子命令全景

```
Inspect authorization.

Available Commands:
  can-i         Check whether an action is allowed
  reconcile     Reifies rules for RBAC role, role binding, cluster role, and cluster role binding objects
  whoami        Experimental: Check self subject attributes
```

---

## 5. 三个命令的分工（最容易混淆的部分）

| 命令 | 底层 API | 回答的问题 | 典型用法 |
| --- | --- | --- | --- |
| `kubectl auth whoami` | SelfSubjectReview | **我是谁？**（身份 + 属性） | 排查 OIDC/SA 身份、确认 token 是否被正确映射 |
| `kubectl auth can-i <verb> [res]` | SelfSubjectAccessReview | **我能不能做 X？** | CI 里做前置检查，RBAC 变更后验证 |
| `kubectl auth can-i --list` | SelfSubjectRulesReview | **我大概能做什么？**（列出所有生效规则） | 一次性查看自己的权限全貌 |

配套的 `kubectl auth reconcile` 会把 RBAC 对象的 `roleRef` 重写回默认值（`kubectl auth reconcile -f rbac.yaml`），用于修复手工改坏的 `roleRef`。**它与身份无关，但同属 `auth` 家族，容易被误认为认证命令。**

---

## 6. 前置条件

1. **kubeconfig 中必须有可用凭据**：token、client cert，或 exec 插件（如 `gke-gcloud-auth-plugin`、`aws eks get-token`）。
2. **API Server 必须提供 SelfSubjectReview**：一般默认开启；若为极简裁剪的自建集群，需确认 apiserver 未禁用该 API。
3. **调用者需要能创建 SelfSubjectReview**：默认的 `system:basic-user` ClusterRole 允许 `authenticated` 组创建该对象，正常用户都满足。
   ```bash
   kubectl auth can-i create selfsubjectreviews.authentication.k8s.io
   ```
4. **网络可达**：能连上 apiserver endpoint（VPN、跳板机、安全组、证书过期都会卡住）。

---

## 7. 典型使用场景

### 场景 1：OIDC / SSO 登录后确认身份映射
登录后不知道自己在集群里被映射成了哪个用户名、哪些组：
```bash
kubectl auth whoami -o yaml
```

### 场景 2：ServiceAccount 身份确认
在 Pod 内或用 SA token 时，确认实际身份与预期一致：
```bash
kubectl auth whoami -o jsonpath='{.status.userInfo.username}'
# 期望: system:serviceaccount:<ns>:<sa>
```

### 场景 3：token webhook / auth proxy / 动态认证
非传统的静态 token 映射（例如 webhook 按 token 内容动态分配组），此时 `groups` 会随 token 变化，whoami 是唯一可靠的"我此刻是谁"的观测手段。

### 场景 4：impersonation 调试
```bash
kubectl auth whoami --as=system:serviceaccount:kube-system:admin
```
（`--as` 是全局 flag，配合 whoami 可以查看"冒充身份"的属性。）

### 场景 5：与 can-i 联用做 CI 前置检查
```bash
set -e
# 我是谁
kubectl auth whoami -o jsonpath='{.status.userInfo.username}'
# 我能做什么
kubectl auth can-i --list
# 我能否创建 deployment
kubectl auth can-i create deployments
```

---

## 8. 常见报错与排查

| 报错 | 原因 | 处理 |
| --- | --- | --- |
| `Unable to connect to the server: net/http: TLS handshake timeout` | 网络不通（未连 VPN / 安全组 / 防火墙） | `nc -z <apiserver> 443`、确认 VPN、检查出口代理 |
| `x509: certificate has expired or is not yet valid` | CA 或客户端证书过期 | 更新 kubeconfig 中的 CA / 重新签发 cert |
| `You must be logged in to the server (Unauthorized)` | token 过期或无凭据 | `kubectl config view --raw` 检查凭据；重新登录 |
| `the server doesn't have a resource type "selfsubjectreviews"` | 集群裁剪掉该 API（老版本 < 1.26 不会有） | 升级集群；或改用 `kubectl auth can-i` |
| `You must be logged in to the server` 但 can-i 正常 | 集群 RBAC 被裁剪，缺 `system:basic-user` 绑定 | 让管理员补 ClusterRoleBinding |
| 卡住不动、无输出 | exec 认证插件在等交互输入（如 `gcloud auth login`） | 设置 `interactiveMode: IfAvailable` 或在终端手动跑一次登录 |

**排查顺序建议**：
```bash
kubectl version                 # 客户端版本
kubectl config current-context  # 上下文对不对
kubectl config get-clusters     # server 地址
kubectl cluster-info            # 最基础的连通性（同样失败=网络/证书问题）
kubectl auth can-i --list       # 认证是否通过
kubectl auth whoami             # 最后再问身份
```
> `cluster-info` 能通但 `whoami` 失败 → 认证/RBAC 问题；两者都失败 → 网络/TLS 问题。

---

## 9. 与相关命令的关系图

```
kubectl auth
├── whoami      → SelfSubjectReview          → "我是谁"
├── can-i       → SelfSubjectAccessReview    → "我能做这个动作吗"
│   ├── --list  → SelfSubjectRulesReview     → "我有哪些规则"
│   └── --subresource
└── reconcile   → (直接改 RBAC 对象)         → "修复 roleRef"
```

其他相关命令：
- `kubectl config view --raw`：看本地凭据（**含明文 token，注意不要贴到公开渠道**）
- `kubectl get token`（v1.32+）：用 TokenRequest API 申请 SA token
- `kubectl create token <sa>`（v1.24+）：同上
- `kubectl auth can-i --as=<user>`：检查**别人**的权限

---

## 10. 安全提醒

- `kubectl config view --raw` / `--minify --flatten` 会打印 **明文 token 和 client key**，输出不要进日志、截图、issue。
- `kubectl auth whoami` 的输出含 `extra`（可能带邮箱、部门、工号等 PII），写到共享文档前考虑脱敏。
- 本文只记录字段结构与命令行为，**不含任何真实凭据**。

---

## 11. 本机客户端环境记录（仅版本信息）

| 项 | 值 |
| --- | --- |
| kubectl | v1.37.3（Client Version），Homebrew 安装于 `/opt/homebrew/bin/kubectl` |
| Kustomize | v5.8.1 |
| `auth` 子命令 | `can-i` / `reconcile` / `whoami` 均已内置 |
| whoami 状态 | 标记为 Experimental |

> 集群连接与凭据细节不在本文范围内。

---

## 12. 参考

- 官方文档：<https://kubernetes.io/docs/reference/access-authn-authz/authentication/>
- SelfSubjectReview API：<https://kubernetes.io/docs/reference/kubernetes-api/authentication-resources/self-subject-review-v1/>
- kubectl 源码：`staging/src/k8s.io/kubectl/pkg/cmd/auth/whoami.go`
- RBAC 良好实践：<https://kubernetes.io/docs/concepts/security/rbac-good-practices/>
