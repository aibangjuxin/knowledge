# Kubernetes TLS Secret vs Opaque Secret 完全对比

> 本文档详细说明 Kubernetes 中 `kubernetes.io/tls` 和 `Opaque` 两种 Secret 类型的区别、使用场景和最佳实践。

---

## 目录

- [1. 定义与目的](#1-定义与目的)
- [2. 键名结构要求](#2-键名结构要求)
- [3. 使用场景对比](#3-使用场景对比)
- [4. Kubernetes 内部处理差异](#4-kubernetes-内部处理差异)
- [5. 完整 YAML 示例](#5-完整-yaml-示例)
- [6. 应用消费方式](#6-应用消费方式)
- [7. 安全考虑](#7-安全考虑)
- [8. 转换与选择指南](#8-转换与选择指南)
- [9. 架构建议](#9-架构建议)

---

## 1. 定义与目的

### TLS Secrets (`kubernetes.io/tls`)

| 属性 | 说明 |
|------|------|
| **类型标识** | `type: kubernetes.io/tls` |
| **目的** | 专门用于存储 TLS 证书和私钥 |
| **特性** | Kubernetes 内置的标准化证书存储格式 |
| **适用** | Ingress TLS、mTLS、Service Mesh 证书管理 |

### Opaque Secrets

| 属性 | 说明 |
|------|------|
| **类型标识** | `type: Opaque`（可省略，默认值） |
| **目的** | 存储任意键值对的敏感数据 |
| **特性** | 通用密钥存储机制 |
| **适用** | 密码、API Key、Token、配置文件等 |

---

## 2. 键名结构要求

### TLS Secret - 严格约束

**必须且只能**包含以下两个键：

| 键名 | 内容 | 格式要求 |
|------|------|----------|
| `tls.crt` | TLS 证书 | PEM 格式，支持证书链 |
| `tls.key` | 私钥 | PEM 格式，PKCS#1 或 PKCS#8 |

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-tls-secret
  namespace: default
type: kubernetes.io/tls
data:
  tls.crt: <base64 编码的证书>
  tls.key: <base64 编码的私钥>
```

**关键约束：**
- `type` 必须为 `kubernetes.io/tls`
- 两个键都是**必需的**，缺少任何一个会导致创建失败
- 证书必须是有效的 PEM 格式
- 证书链可包含在 `tls.crt` 中（顺序：服务器证书 → 中间 CA → 根 CA）
- **不能包含其他键**

### Opaque Secret - 灵活结构

支持**任意键名**和**任意内容**：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-opaque-secret
  namespace: default
type: Opaque
data:
  db-password: cGFzc3dvcmQxMjM=       # 手动 base64 编码
  api-key: c2VjcmV0LWtleS12YWx1ZQ==  # 手动 base64 编码
stringData:
  config.json: |                          # K8s 自动 base64 编码
    {"endpoint": "https://api.example.com"}
```

**关键特性：**
- `type` 可省略（默认为 `Opaque`）或显式声明
- 支持 `data`（手动 base64）和 `stringData`（自动 base64）两种输入方式
- 键名命名无限制
- 单个 Secret 最大容量为 **1MB**（etcd 限制）

---

## 3. 使用场景对比

| 场景 | TLS Secret | Opaque Secret |
|------|------------|---------------|
| Ingress TLS 终端 | ✅ 原生支持 | ❌ 不兼容 |
| mTLS 双向认证 | ✅ 标准格式 | ⚠️ 需要额外配置 |
| 数据库密码 | ❌ | ✅ |
| API Key / Token | ❌ | ✅ |
| OAuth Client Secret | ❌ | ✅ |
| 自定义证书（非 TLS 终端） | ⚠️ 可以但不推荐 | ✅ 更灵活 |
| SSH 私钥 | ❌ | ✅ |
| GCP Service Account Key | ❌ | ✅ |
| cert-manager 输出 | ✅ 默认类型 | ❌ |

---

## 4. Kubernetes 内部处理差异

### 验证逻辑

```
TLS Secret 验证流程:
└── admission controller 验证:
    ├── type == "kubernetes.io/tls"
    ├── data["tls.crt"] 存在且为有效 PEM
    ├── data["tls.key"] 存在且为有效 PEM
    └── 不能包含其他键

Opaque Secret 验证流程:
└── 基础验证:
    ├── 值已正确 base64 编码
    └── 总大小 < 1MB
```

### 控制器集成

| 控制器 | TLS Secret | Opaque Secret |
|--------|------------|---------------|
| Ingress Controller | ✅ 直接引用，自动验证 | ❌ 不支持 |
| cert-manager | ✅ 默认输出类型 | ⚠️ 可读取但不标准 |
| Istio / Linkerd | ✅ 语义标准 | ✅ 支持但需额外配置 |
| 自定义应用 | ✅ 挂载为文件 | ✅ 环境变量或文件 |

---

## 5. 完整 YAML 示例

### TLS Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ingress-tls
  namespace: production
type: kubernetes.io/tls
data:
  # echo -n "cert content" | base64
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUNrekNDQWVtZ0F3SUJBZ0lKQUxGM0h...
  tls.key: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFcEFJQkFBS0NBUUVBdjh...
```

**使用 kubectl 命令创建：**
```bash
kubectl create secret tls ingress-tls \
  --cert=./tls.crt \
  --key=./tls.key \
  -n production
```

### Opaque Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: production
type: Opaque
data:
  POSTGRES_PASSWORD: c3VwZXJzZWNyZXQ=
  REDIS_AUTH_TOKEN: bXlyZWRpc3Rva2Vu
stringData:
  # 不需要手动 base64，K8s 会自动处理
  SLACK_WEBHOOK_URL: "https://hooks.slack.com/services/T00/B00/xxx"
```

**使用 kubectl 命令创建：**
```bash
kubectl create secret generic app-secrets \
  --from-literal=POSTGRES_PASSWORD=supersecret \
  --from-literal=REDIS_AUTH_TOKEN=myredistoken \
  -n production
```

---

## 6. 应用消费方式

### Pod 中使用（两种类型通用）

#### 环境变量方式

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
  - name: app
    image: myapp:latest
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: app-secrets
          key: POSTGRES_PASSWORD
```

#### Volume 挂载方式

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
  - name: app
    image: myapp:latest
    volumeMounts:
    - name: tls-certs
      mountPath: /etc/tls
      readOnly: true
  volumes:
  - name: tls-certs
    secret:
      secretName: ingress-tls
      # 挂载后文件名为 tls.crt 和 tls.key
```

### Ingress 直接使用 TLS Secret

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - app.example.com
    secretName: ingress-tls  # 必须是 kubernetes.io/tls 类型
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
```

---

## 7. 安全考虑

### 共性问题

| 风险 | 缓解措施 |
|------|----------|
| etcd 中默认不加密 | 启用 `EncryptionConfiguration` |
| 未授权访问 | 配置 RBAC，限制 `get`/`list` 权限 |
| 审计缺失 | 启用 Secret 访问审计日志 |
| 传输泄露 | 确保 etcd 通信使用 TLS |

### TLS Secret 特有风险

| 风险 | 说明 |
|------|------|
| 证书过期 | 不会自动轮换，需配合 cert-manager |
| 私钥泄露 | 等同于身份泄露，影响范围大 |
| CA 结构暴露 | 证书链可能泄露内部 CA 架构 |

### Opaque Secret 特有风险

| 风险 | 说明 |
|------|------|
| 键名泄露信息 | 避免使用 `admin-password` 等明显命名 |
| 混合存储 | 多种密钥共存增加泄露面 |
| 建议 | 按用途分 Namespace 或分 Secret 对象 |

---

## 8. 转换与选择指南

### 何时选择 TLS Secret

- ✅ Ingress / Gateway TLS 终端
- ✅ 需要与 cert-manager 集成
- ✅ Service Mesh mTLS 配置
- ✅ 希望利用 K8s 内置的证书验证

### 何时选择 Opaque Secret

- ✅ 存储非 TLS 类敏感数据
- ✅ 需要自定义键名结构
- ✅ 存储多个相关但不相同的密钥
- ✅ 证书用于非标准用途（如自定义 CA 验证）

### 转换示例：Opaque → TLS

```bash
# 如果错误地把证书存在 Opaque Secret 中
kubectl get secret wrong-type -o jsonpath='{.data.cert}' | base64 -d > tls.crt
kubectl get secret wrong-type -o jsonpath='{.data.key}' | base64 -d > tls.key

# 重新创建正确的 TLS Secret
kubectl create secret tls correct-type \
  --cert=tls.crt \
  --key=tls.key \
  --namespace=production

# 删除旧的 Opaque Secret
kubectl delete secret wrong-type -n production
```

### 转换示例：TLS → Opaque（特殊场景）

```bash
# 提取 TLS Secret 内容
kubectl get secret tls-secret -o jsonpath='{.data.tls.crt}' | base64 -d > tls.crt
kubectl get secret tls-secret -o jsonpath='{.data.tls.key}' | base64 -d > tls.key

# 创建为 Opaque Secret（自定义键名）
kubectl create secret generic custom-cert \
  --from-file=cert=tls.crt \
  --from-file=key=tls.key \
  --namespace=production
```

---

## 9. 架构建议

### 最佳实践

1. **语义优先**  
   使用 TLS Secret 存储证书，即使 Opaque 也能工作。语义清晰有助于团队协作和审计。

2. **最小化权限**  
   TLS Secret 通常只需要被 Ingress Controller 或 Service Mesh 访问，严格限制 RBAC。

3. **自动化轮换**  
   结合 cert-manager 实现证书自动管理和轮换，避免人工操作导致的过期事故。

4. **分离关注点**  
   不要在一个 Secret 中混用 TLS 材料和其他密钥。一个 Secret 只存一类相关数据。

5. **监控证书过期**  
   设置 Prometheus 告警规则，监控证书有效期，提前 30 天告警。

### Prometheus 证书过期监控示例

```yaml
- alert: TLSSecretExpiringSoon
  expr: |
    kube_secret_created_seconds{type="kubernetes.io/tls"}
    unless on(namespace, secret)
    (kube_secret_created_seconds{type="kubernetes.io/tls"} + 30*24*3600) > time()
  for: 1h
  labels:
    severity: warning
  annotations:
    summary: "TLS Secret {{ $labels.secret }} in {{ $labels.namespace }} expiring soon"
```

---

## 快速参考表

| 对比维度 | TLS Secret | Opaque Secret |
|----------|------------|---------------|
| **类型声明** | `kubernetes.io/tls` | `Opaque`（可省略） |
| **键名要求** | 固定 `tls.crt` + `tls.key` | 任意键名 |
| **验证级别** | 严格（PEM 格式验证） | 宽松（仅 base64 验证） |
| **Ingress 兼容** | ✅ 原生支持 | ❌ 不支持 |
| **cert-manager 输出** | ✅ 默认 | ❌ |
| **灵活性** | 低（专用） | 高（通用） |
| **语义清晰度** | 高 | 中 |
| **最大容量** | 1MB | 1MB |

---

*文档生成时间：2026-04-10*  
*适用 Kubernetes 版本：1.19+*
