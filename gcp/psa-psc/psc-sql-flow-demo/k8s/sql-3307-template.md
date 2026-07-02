# Cloud SQL Auth Proxy 平台级 Deploy 模板最佳实践

> 本文承接 [`why-psc-netpolicy-3307.md`](./why-psc-netpolicy-3307.md) 第 5 节确立的统一规范（`127.0.0.1:3307` + 单 instance + Workload Identity），回答一个落地问题：**作为平台团队，如何设计一份 Deploy 模板，让所有用户 / 所有 API 自动带上 cloud-sql-proxy sidecar，且不重蹈旧模板"端口分裂"的覆辙？**

---

## 1. 设计目标

| 目标 | 说明 |
|------|------|
| **每用户一份独立 Deploy** | 每个用户 / 每个 API 独立 Deployment、独立 sidecar（不共享 proxy，避免横向移动） |
| **平台统一 sidecar 形状** | cloud-sql-proxy container 的 image / args / resource / probe 由平台控制，用户不能改 |
| **每用户独立 instance 配置** | 用户提供 instance 连接名 + IAM principal，平台模板渲染成完整 args |
| **NetworkPolicy 统一一套** | 所有 NS 一条 `egress TCP/3307`，不再有"5432 vs 3307"分裂 |
| **可灰度可回滚** | 新模板上线后，老模板仍可继续工作一段时间，直到所有用户迁移完 |
| **可审计可追溯** | 每个用户 Pod 最终渲染出的 YAML 可复现，方便安全审计 |

---

## 2. 两条主流技术路线对比

| 维度 | **Helm Chart** | **Kustomize Component** |
|------|----------------|-------------------------|
| **成熟度** | 生态最广，几乎所有 K8s 平台都支持 | K8s 原生工具链，`kubectl apply -k` 即用 |
| **复杂度** | 模板语法（`{{ }}`） + Go template 学习成本 | 纯 YAML 叠加，无需新语法 |
| **覆盖能力** | 强（条件分支、循环、钩子） | 中（patch + 字段追加） |
| **平台控制力** | 高（`values.schema.json` 限制用户输入） | 中（用户可改 base 再 patch，平台策略靠 GitOps 拦截） |
| **可审计性** | `helm template` 输出可 git diff | `kustomize build` 输出可 git diff |
| **回滚** | `helm rollback` 原生支持 | Git 仓库 revert |
| **推荐场景** | 多租户 SaaS 平台、复杂配置 | 中小团队、内部平台、GKE Autopilot |

**本节给出两套方案的完整示例**，你按团队技术栈选用。

---

## 3. 方案 A：Helm Chart 模板（推荐多租户场景）

### 3.1 目录结构

```
cloud-sql-app-template/
├── Chart.yaml
├── values.yaml                          # 默认值
├── values.schema.json                   # 限制用户输入
├── templates/
│   ├── _helpers.tpl
│   ├── deployment.yaml                  # 主 Deployment
│   ├── serviceaccount.yaml              # 含 WI 注解
│   ├── networkpolicy.yaml               # 统一 egress 3307
│   ├── secret.yaml                      # DB 密码（可选）
│   └── configmap.yaml                   # 应用配置
└── examples/
    ├── user-a-values.yaml
    └── user-b-values.yaml
```

### 3.2 `values.yaml`（用户可配置部分）

```yaml
# ========== 必填 ==========
name: my-app              # 用于 Deployment / SA / Secret 命名
namespace: app-ns

# Cloud SQL 连接信息（每用户唯一）
cloudsql:
  project: "my-project"
  region: "asia-east1"
  instance: "my-pg"
  iamUser: "my-app-user@app.iam.gserviceaccount.com"  # IAM 鉴权用户
  # passwordSecret: ""                                # 如果不用 IAM 则启用
  database: "mydb"

# Workload Identity 配置（每用户唯一）
gsa: "app-gsa@my-project.iam.gserviceaccount.com"

# 应用镜像
image:
  repository: gcr.io/my-project/my-app
  tag: "1.2.3"

# ========== 可选 ==========
replicas: 3
resources:
  requests: {cpu: 100m, memory: 256Mi}
  limits:   {cpu: 1000m, memory: 1Gi}

env: {}

# ========== 平台锁定（用户不应改） ==========
# proxy:
#   image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4
#   address: "127.0.0.1"
#   port: 3307
```

### 3.3 `values.schema.json`（强制约束用户输入）

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["name", "namespace", "cloudsql", "gsa", "image"],
  "properties": {
    "name":       { "type": "string", "pattern": "^[a-z][a-z0-9-]{0,62}$" },
    "namespace":  { "type": "string", "pattern": "^[a-z][a-z0-9-]{0,62}$" },
    "cloudsql": {
      "type": "object",
      "required": ["project", "region", "instance", "database"],
      "properties": {
        "project":  { "type": "string", "pattern": "^[a-z][a-z0-9-]{4,28}[a-z]$" },
        "region":   { "type": "string", "enum": ["asia-east1", "asia-east2", "us-central1", "us-east1", "europe-west1"] },
        "instance": { "type": "string", "pattern": "^[a-z][a-z0-9-]{0,80}$" },
        "iamUser":  { "type": "string", "format": "email" },
        "passwordSecret": { "type": "string" }
      },
      "additionalProperties": false
    },
    "gsa":       { "type": "string", "format": "email" },
    "image": {
      "type": "object",
      "required": ["repository", "tag"],
      "properties": {
        "repository": { "type": "string", "pattern": "^gcr\\.io/.*" },
        "tag":        { "type": "string", "pattern": "^v?[0-9]+\\.[0-9]+\\.[0-9]+" }
      },
      "additionalProperties": false
    }
  },
  "additionalProperties": true
}
```

### 3.4 `templates/_helpers.tpl`

```gotemplate
{{/*
渲染 cloud-sql-proxy args（平台锁定，不允许用户覆盖）
*/}}
{{- define "cloudsql.proxyArgs" -}}
- "--psc"
- "--structured-logs"
- "--auto-iam-authn"
- "--address=127.0.0.1"
- "--port=3307"
- "{{ .Values.cloudsql.project }}:{{ .Values.cloudsql.region }}:{{ .Values.cloudsql.instance }}"
{{- end -}}

{{/*
渲染 instance 连接名（统一引用）
*/}}
{{- define "cloudsql.connectionName" -}}
{{ .Values.cloudsql.project }}:{{ .Values.cloudsql.region }}:{{ .Values.cloudsql.instance }}
{{- end -}}
```

### 3.5 `templates/deployment.yaml`（核心）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.name }}
    app.kubernetes.io/managed-by: platform-team    # 平台标识
    cloudsql.proxy/enabled: "true"
spec:
  replicas: {{ .Values.replicas | default 3 }}
  selector:
    matchLabels:
      app: {{ .Values.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.name }}
      annotations:
        # 平台策略：禁止用户覆盖 cloud-sql-proxy 容器
        platform.team/sql-policy: "v1-uniform-3307"
    spec:
      serviceAccountName: {{ .Values.name }}-sa
      containers:
        # ─────── 应用容器（用户控制） ───────
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: 8080
          env:
            - name: DB_HOST
              value: "127.0.0.1"
            - name: DB_PORT
              value: "3307"
            - name: DB_NAME
              value: {{ .Values.cloudsql.database | quote }}
            - name: DB_USER
              value: {{ .Values.cloudsql.iamUser | quote }}
            {{- with .Values.env }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          securityContext:
            runAsNonRoot: true
            runAsUser: 10001
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          livenessProbe:
            httpGet: {path: /healthz, port: 8080}
            initialDelaySeconds: 30
            periodSeconds: 30
          readinessProbe:
            httpGet: {path: /ready, port: 8080}
            initialDelaySeconds: 10
            periodSeconds: 10

        # ─────── cloud-sql-proxy sidecar（平台锁定） ───────
        - name: cloud-sql-proxy
          image: "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4"
          args:
            {{- include "cloudsql.proxyArgs" . | nindent 12 }}
          securityContext:
            runAsNonRoot: true
            runAsUser: 1337
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits:   {cpu: 200m, memory: 256Mi}
          livenessProbe:
            tcpSocket: {port: 3307}
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            tcpSocket: {port: 3307}
            initialDelaySeconds: 5
            periodSeconds: 10
```

### 3.6 `templates/serviceaccount.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.name }}-sa
  namespace: {{ .Values.namespace }}
  annotations:
    # Workload Identity 绑定（每用户唯一）
    iam.gke.io/gcp-service-account: {{ .Values.gsa | quote }}
```

### 3.7 `templates/networkpolicy.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ .Values.name }}-egress
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.name }}
spec:
  podSelector:
    matchLabels:
      app: {{ .Values.name }}
  policyTypes: ["Egress"]
  egress:
    # DNS
    - to: []
      ports:
        - {protocol: UDP, port: 53}
        - {protocol: TCP, port: 53}
    # Cloud SQL Auth Proxy → PSC（统一放行）
    - to: []
      ports:
        - {protocol: TCP, port: 3307}
    # 必要外部出站（按需放开）
    - to: []
      ports:
        - {protocol: TCP, port: 443}
```

### 3.8 用户使用示例

**`examples/user-a-values.yaml`**：

```yaml
name: order-api
namespace: order-ns

cloudsql:
  project: "prod-shared"
  region: "asia-east1"
  instance: "orders-pg"
  iamUser: "order-api@prod-shared.iam.gserviceaccount.com"
  database: "orders"

gsa: "order-api-gsa@prod-shared.iam.gserviceaccount.com"

image:
  repository: gcr.io/prod-shared/order-api
  tag: "v2.1.0"

replicas: 5

env:
  - name: SPRING_PROFILES_ACTIVE
    value: "prod"
  - name: LOG_LEVEL
    value: "INFO"
```

**安装命令**：

```bash
helm template order-api ./cloud-sql-app-template \
  -f examples/user-a-values.yaml \
  | kubectl apply -f -
```

或者用 Helm release 管理（推荐生产）：

```bash
helm upgrade --install order-api ./cloud-sql-app-template \
  -f examples/user-a-values.yaml \
  -n order-ns --create-namespace
```

### 3.9 平台锁定机制：用户怎么改不了？

| 用户能改 | 用户改不了 |
|----------|-----------|
| `name`, `namespace` | cloud-sql-proxy 的 `image` / `args` / `port` / `address` |
| `cloudsql.{project, region, instance, database, iamUser}` | NetworkPolicy 的 `egress TCP/3307` |
| `image.repository` / `tag`（必须来自自家 registry） | sidecar 的 `securityContext` / `resources` |
| `replicas` / `resources` / `env` | sidecar 的 `livenessProbe` / `readinessProbe` |
| `gsa`（必须自家 GSA） | ServiceAccount 上的 WI annotation |

**关键点**：`templates/deployment.yaml` 里 cloud-sql-proxy 整个 container 块不通过 `.Values` 暴露，用户即使在 `values.yaml` 里写了 `proxy:` 也不会被渲染进去。

**额外护栏（生产推荐）**：

```yaml
# templates/deployment.yaml 最顶部加注释
{{- /*
⚠️  PLATFORM-LOCKED CONTAINER
     任何用户改不了 cloud-sql-proxy container 的形状
     如需调整，联系平台团队，PR 改 templates/deployment.yaml
*/ -}}
```

---

## 4. 方案 B：Kustomize Component（推荐内部平台 / GKE Autopilot）

### 4.1 目录结构

```
platform-cloudsql/
├── base/                                # 用户写自己的应用 base
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── serviceaccount.yaml
├── components/
│   └── cloudsql-proxy/                  # 平台组件
│       ├── kustomization.yaml
│       ├── patch-deployment.yaml        # patch 用户 base 的 Deployment
│       └── networkpolicy.yaml
└── examples/
    └── user-a/
        ├── kustomization.yaml
        ├── deployment-patch.yaml
        └── values.envsubst              # CI 渲染用
```

### 4.2 `components/cloudsql-proxy/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

# 这个 component 自动给任何引用它的 base 注入 cloud-sql-proxy sidecar

patches:
  - path: patch-deployment.yaml
    target:
      kind: Deployment
      group: apps

components:
  # 不嵌套其他 component，保持简单

# 资源追加
resources:
  - networkpolicy.yaml
```

### 4.3 `components/cloudsql-proxy/patch-deployment.yaml`

```yaml
# Strategic Merge Patch：往用户的 Deployment.containers 里追加 sidecar
apiVersion: apps/v1
kind: Deployment
metadata:
  name: not-used   # strategic merge 会按 kind + name 匹配
spec:
  template:
    spec:
      serviceAccountName: REPLACE_BY_USER_SA   # 用户必填，被 patch 覆盖
      containers:
        # ⚠️ 这里的关键：name "app" 必须跟用户 base 里的应用容器同名
        - name: app
          env:
            - name: DB_HOST
              value: "127.0.0.1"
            - name: DB_PORT
              value: "3307"
            # 其他 env 由用户 base 提供，这里只追加必要项
        # 新增 sidecar（kustomize 会 append 到容器列表）
        - name: cloud-sql-proxy
          image: "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4"
          args:
            - "--psc"
            - "--structured-logs"
            - "--auto-iam-authn"
            - "--address=127.0.0.1"
            - "--port=3307"
            # ⚠️ instance 连接名需要用户在 base 里提供，或者 CI 替换
            - "REPLACE_INSTANCE_CONNECTION_NAME"
          securityContext:
            runAsNonRoot: true
            runAsUser: 1337
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits:   {cpu: 200m, memory: 256Mi}
          livenessProbe:
            tcpSocket: {port: 3307}
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            tcpSocket: {port: 3307}
            initialDelaySeconds: 5
            periodSeconds: 10
```

### 4.4 `components/cloudsql-proxy/networkpolicy.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cloudsql-proxy-egress
spec:
  # 关键：匹配所有带这个 label 的 Pod
  podSelector:
    matchLabels:
      cloudsql.proxy/enabled: "true"   # 平台自动注入
  policyTypes: ["Egress"]
  egress:
    - to: []
      ports:
        - {protocol: UDP, port: 53}
        - {protocol: TCP, port: 53}
    - to: []
      ports:
        - {protocol: TCP, port: 3307}
    - to: []
      ports:
        - {protocol: TCP, port: 443}
```

### 4.5 用户 base（每个用户一份）

**`base/kustomization.yaml`**：

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: order-ns

resources:
  - deployment.yaml
  - serviceaccount.yaml

# ── 关键：注入平台 component ──
components:
  - ../components/cloudsql-proxy

# ── 给 Pod 打 label 让 NetworkPolicy 选中 ──
labels:
  - includeSelectors: true
    pairs:
      cloudsql.proxy/enabled: "true"
```

**`base/deployment.yaml`**（用户写）：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: order-api
  template:
    metadata:
      labels:
        app: order-api
    spec:
      serviceAccountName: order-api-sa   # 必须存在
      containers:
        - name: app                      # 必须叫 "app"（与 component patch 对齐）
          image: gcr.io/prod-shared/order-api:v2.1.0
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: "prod"
            - name: DB_NAME
              value: "orders"
            - name: DB_USER
              value: "order-api@prod-shared.iam.gserviceaccount.com"
          resources:
            requests: {cpu: 100m, memory: 256Mi}
            limits:   {cpu: 1000m, memory: 1Gi}
```

### 4.6 用户最终使用

```bash
# 渲染最终 YAML（用于审计 / git diff）
kustomize build examples/user-a > rendered.yaml

# 或直接 apply
kubectl apply -k examples/user-a
```

### 4.7 Kustomize 方案的限制

| 限制 | 说明 | 解决 |
|------|------|------|
| `instance` 连接名硬编码问题 | Component patch 里要写 `REPLACE_INSTANCE_CONNECTION_NAME`，每个用户不同 | (a) 用 `envsubst` CI 替换；(b) 用 Kustomize 的 `replacements`；(c) 每个用户写自己的 component overlay |
| 用户容器必须叫 `app` | Component patch 通过 `name` 匹配 | 平台规范文档化 |
| 用户 base 不能删 sidecar | strategic merge patch 默认 merge，删不掉 | (a) 平台侧用 OPA/Kyverno 拦截；(b) 改用 JSON Patch（更精确但难维护） |

---

## 5. 关键配套机制

### 5.1 Workload Identity 自动化

**GSA 准备**（平台团队一次性给每个用户建好）：

```bash
gcloud iam service-accounts create order-api-gsa \
  --project=prod-shared \
  --display-name="Order API Cloud SQL Access"

# 绑 Cloud SQL Client 角色
gcloud projects add-iam-policy-binding prod-shared \
  --member="serviceAccount:order-api-gsa@prod-shared.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"

# 允许 KSA 模拟
gcloud iam service-accounts add-iam-policy-binding \
  order-api-gsa@prod-shared.iam.gserviceaccount.com \
  --project=prod-shared \
  --member="serviceAccount:prod-shared.svc.id.goog[order-ns/order-api-sa]" \
  --role="roles/iam.workloadIdentityUser"
```

**Helm 模板里通过 values 引用**（上面已展示）。

### 5.2 Cloud SQL IAM 用户准备

```bash
# 创建 IAM 用户（注意是 Cloud SQL 用户，不是 K8s 用户）
gcloud sql users create \
  "order-api@prod-shared.iam.gserviceaccount.com" \
  --instance=orders-pg \
  --type=cloud_iam_user
```

### 5.3 NetworkPolicy 统一（最高优先级）

**平台侧强制要求**：所有引用 `cloud-sql-proxy` 模板的 NS 必须应用 `egress TCP/3307`。

**自动化校验**（Kyverno / OPA Gatekeeper）：

```yaml
# Kyverno 例：禁止任何 NetworkPolicy 删除 3307 egress
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-cloudsql-3307-egress
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-egress-3307
    match:
      resources:
        kinds: ["NetworkPolicy"]
    validate:
      message: "NetworkPolicy must include egress TCP/3307 for Cloud SQL Auth Proxy"
      pattern:
        spec:
          egress:
          - ports:
            - port: 3307
```

### 5.4 镜像来源限制（防注入）

```yaml
# Kyverno：禁止 cloud-sql-proxy 镜像被替换
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: lock-cloudsql-proxy-image
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-image
    match:
      resources:
        kinds: ["Deployment"]
    validate:
      message: "cloud-sql-proxy container image must be gcr.io/cloud-sql-connectors/cloud-sql-proxy"
      pattern:
        spec:
          template:
            spec:
              containers:
              - name: cloud-sql-proxy
                image: "gcr.io/cloud-sql-connectors/cloud-sql-proxy:*"
```

### 5.5 审计与可观测性

```bash
# 全集群列出所有 cloud-sql-proxy 实例
kubectl get pods -A -l cloudsql.proxy/enabled=true \
  -o custom-columns='NS:.metadata.namespace,POD:.metadata.name,INSTANCE:{.spec.containers[?(@.name=="cloud-sql-proxy")].args[5]},SA:{.spec.serviceAccountName}'

# 监控 3307 连接异常
kubectl logs -n app-ns -l app=my-app -c cloud-sql-proxy --tail=100 | grep -iE "error|refus|timeout"
```

---

## 6. 灰度迁移路径

从旧模板（5432/5433 + 0.0.0.0）到新模板（3307 + 127.0.0.1）的迁移步骤：

### 6.1 第 1 阶段：双模板并存（Week 1-2）

```
用户可以选：
  - templates/legacy-deployment.yaml   # 旧 5432 模板（标 Deprecated）
  - templates/deployment.yaml          # 新 3307 模板
```

NetworkPolicy 同时放 5432（兼容旧）和 3307（新）。

### 6.2 第 2 阶段：新用户强制新模板（Week 3+）

```yaml
# Kyverno：禁止再创建使用旧镜像 / 旧端口的 Pod
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: forbid-legacy-cloudsql-port
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-cloudsql-port
    match:
      resources:
        kinds: ["Deployment"]
    exclude:
      any:
      - resources:
          namespaces: ["legacy-migration-ns"]   # 给老用户 30 天迁移期
    validate:
      message: "cloud-sql-proxy port must be 3307 (not 5432/5433)"
      pattern:
        spec:
          template:
            spec:
              containers:
              - name: cloud-sql-proxy
                =(args):
                  - ":*"   # contains check
```

### 6.3 第 3 阶段：老用户灰度（Week 4-8）

老用户更新 `values.yaml`：

```diff
- env:
-   - name: DB_PORT
-     value: "5432"            # 旧
+   - name: DB_PORT
+     value: "3307"            # 新
```

重建 Pod。`ss -tnlp` 验证 proxy 在 127.0.0.1:3307 监听，应用从 5432 切到 3307。

### 6.4 第 4 阶段：清理（Week 9+）

- 删除 `legacy-deployment.yaml` 模板
- 删除 `NetworkPolicy` 里的 5432 egress
- 文档标记 `Deprecated`

---

## 7. 验证清单

部署后必跑：

```bash
# 1. 验证 sidecar 注入成功
kubectl get pod -n <ns> <pod> -o jsonpath='{.spec.containers[*].name}'
# 期望: app cloud-sql-proxy

# 2. 验证 proxy 监听在 127.0.0.1:3307
kubectl exec -n <ns> <pod> -c cloud-sql-proxy -- ss -tnlp
# 期望: LISTEN 0  128  127.0.0.1:3307  0.0.0.0:*  users:(("cloud-sql-proxy",...))

# 3. 验证应用能连到 3307
kubectl exec -n <ns> <pod> -c app -- sh -c \
  'nc -zv 127.0.0.1 3307'
# 期望: succeeded

# 4. 验证 NetworkPolicy 放行 3307
kubectl exec -n <ns> <pod> -c app -- sh -c \
  'timeout 3 bash -c "echo > /dev/tcp/127.0.0.1/3307" && echo OK || echo BLOCKED'

# 5. 验证 IAM token 注入
kubectl exec -n <ns> <pod> -c cloud-sql-proxy -- \
  curl -s -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token \
  | head -c 100
# 期望: 一段 JWT
```

完整自动化脚本：[`why-psc-netpolicy-3307.md` 第 5 节"验证脚本"](./why-psc-netpolicy-3307.md#验证脚本到底连的是哪条路径)

---

## 8. 一句话结论

> **平台级模板的核心不是"让用户改一堆参数"，而是"把 sidecar 形状锁死，让用户只填 instance 连接名"**。
>
> 用 **Helm chart**（`templates/deployment.yaml` 不暴露 proxy container）或 **Kustomize component**（`patch-deployment.yaml` 强制注入 sidecar），让 `127.0.0.1:3307` 成为唯一路径，**NetworkPolicy 统一一条 `egress TCP/3307`**，老用户能连、新用户能连、混部不打架的问题一次性消失。

---

## 附录：本文档依赖

- 上游规范：[`why-psc-netpolicy-3307.md`](./why-psc-netpolicy-3307.md)（为什么 3307、Sidecar 配置校验清单）
- cloud-sql-proxy 官方文档：[README](https://github.com/GoogleCloudPlatform/cloud-sql-proxy) · [v2.11.4 tag](https://github.com/GoogleCloudPlatform/cloud-sql-proxy/tree/v2.11.4)
- Cloud SQL Auth Proxy PSC：[Configure Private Service Connect](https://cloud.google.com/sql/docs/postgres/configure-private-service-connect)
- Workload Identity：[GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)
- Helm：[helm.sh/docs](https://helm.sh/docs/)
- Kustomize：[kubectl apply -k](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
- Kyverno（策略执行）：[kyverno.io](https://kyverno.io/)