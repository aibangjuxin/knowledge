# Istio No-Sidecar Architecture

部署 Istio Ingress Gateway，但不启用 sidecar proxy，实现纯 Gateway 路由 + TLS 终止/发起。

## 架构概览

```
Client (HTTPS)
     ↓
PSC Attachment (Cross-Project)
     ↓
IIP (Internal Ingress Proxy)
     ↓
GCP LoadBalancer (Internal LB :443)
     ↓
Istio Ingress Gateway (ASM Managed Sidecar)
  - TLS Termination at Gateway
  - HTTPRoute + DestinationRule (TLS SIMPLE)
     ↓ Two Paths
  ┌─────────────────────────────────────────────┐
  │ /direkt-plain          /direkt-https        │
  │     ↓                      ↓                │
  │ HTTP :8080           TLS SIMPLE :443        │
  │ Runtime (No Sidecar)  Runtime (No Sidecar)  │
  └─────────────────────────────────────────────┘
```

## 两种部署模式

### 1. Dedicated Gateway (deploy.yaml)

**场景:** 每个租户有独立的 Gateway 资源

| Resource | Name | Namespace |
|----------|------|-----------|
| Gateway | `istio-gateway-k8s-net` | `istio-gateway-int-ns` |
| HTTPRoute | `app01` | `istio-gateway-int-ns` |
| DestinationRule | `tls-foo` | `istio-gateway-int-ns` |

**路由规则:**
- `api1.team1.appdev.aibang/direkt-plain` → `app01-toolbox.team1-runtime-ns:8080` (HTTP)
- `api1.team1.appdev.aibang/direkt-https` → `app01-toolbox.team1-runtime-ns:443` (TLS SIMPLE)

**跨命名空间访问:**
- Gateway → `gateway-secrets` (读取 TLS Cert via ReferenceGrant)
- HTTPRoute → `team1-runtime-ns` (访问 Service via ReferenceGrant)

### 2. Shared Gateway (deploy-shared.yaml)

**场景:** 多个租户共享同一个 Gateway 资源

| Resource | Name | Namespace |
|----------|------|-----------|
| Gateway | `team2-runtime-ns-gw` | `team2-runtime-ns` |
| HTTPRoute | `app01` | `jakub-app` |
| HTTPRoute | `tenant2-app` | `caep-tenant2` |
| DestinationRule | `tls-foo` | `team2-runtime-ns` |
| DestinationRule | `tls-foo2` | `team2-runtime-ns` |

**路由规则:**
- `jakub-app01.team2.appdev.aibang` → `app01-toolbox.jakub-app:443` (TLS SIMPLE)
- `tenant2.team2.appdev.aibang` → `app.caep-tenant2:443` (TLS SIMPLE)

## 关键设计

### No-Sidecar

- **Gateway Namespace:** `istio-injection: enabled` (via `istio.io/rev=asm-managed`)
- **Runtime Namespace:** `istio-injection: disabled` (via label)
- Runtime Pod 不注入 sidecar proxy，纯 nginx/httpd 应用

### TLS 处理

```
入口: Client → Gateway (TLS Termination)
         ↓
       Gateway re-encrypts (TLS SIMPLE mode, insecureSkipVerify)
         ↓
       Backend (Runtime Pod)
```

**两种路径:**
1. `/direkt-plain` → HTTP :8080 (Gateway 终止 TLS 后直接转发明文)
2. `/direkt-https` → HTTPS :443 (Gateway 重新加密后转发)

### Certificate 管理

- **Dedicated 模式:** Cert 在 `gateway-secrets` 命名空间，通过 ReferenceGrant 授权 Gateway 读取
- **Shared 模式:** Cert 在 Gateway 同命名空间 (`team2-runtime-ns`)

### ReferenceGrant

跨命名空间访问需要 ReferenceGrant:

```yaml
# Gateway 读取其他命名空间的 Secret
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: certificates
  namespace: gateway-secrets
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: Gateway
      namespace: istio-gateway-int-ns
  to:
    - group: ""
      kind: Secret
      name: cert

# HTTPRoute 访问其他命名空间的 Service
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: service
  namespace: team1-runtime-ns
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: istio-gateway-int-ns
  to:
    - group: ""
      kind: Service
```

## Prerequisites

### 1. Istio 安装 (Minimal Profile)

```bash
istioctl install \
  --set profile=minimal \
  --set components.cni.enabled=false \
  --set values.global.platform=gke \
  --set hub=us-east4-docker.pkg.dev/projectID-capus-dev/containers \
  --set tag=1.29.2-distroless
```

**说明:**
- `profile=minimal` - 只部署 istiod，不部署 ingressgateway
- `cni.enabled=false` - 不启用 CNI
- `global.platform=gke` - GKE 平台特定配置

### 2. Gateway CRDs

确保 Gateway API CRDs 已启用:

```bash
# GKE Gateway API
gcloud container clusters update CLUSTER_NAME \
  --enable-dataplane-v2 \
  --region=REGION

# 或手动应用 CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

### 3. 命名空间标签

```bash
# Gateway 命名空间 (需要 ASM managed sidecar)
kubectl create ns istio-gateway-int-ns
kubectl label ns istio-gateway-int-ns istio.io/rev=asm-managed

# Runtime 命名空间 (禁用 sidecar injection)
kubectl create ns team1-runtime-ns
kubectl label ns team1-runtime-ns istio-injection=disabled
```

## 文件说明

| File | Description |
|------|-------------|
| `requirement.md` | 前置条件与安装命令 |
| `deploy.yaml` | Dedicated Gateway 部署 (独立 Gateway) |
| `deploy-shared.yaml` | Shared Gateway 部署 (多租户共享 Gateway) |
| `architecture.html` | 架构图 (SVG) |

## 流量对比

| 路径 | TLS 终止点 | TLS 发起点 | Backend |
|------|-----------|-----------|---------|
| `/direkt-plain` | Gateway | 无 | HTTP :8080 |
| `/direkt-https` | Gateway | Gateway | HTTPS :443 |

## Links

- [Istio Profiles](https://istio.io/latest/docs/setup/additional-setup/config-profiles/#deployment-profiles)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
- [GKE Gateway API](https://cloud.google.com/kubernetes-engine/docs/how-to/gateway-api)
