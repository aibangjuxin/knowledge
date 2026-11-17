# GKE Gateway 2.0 双入口架构 - 实施评估 TODO

> 文档目的：评估在现有环境中新增 Entry Point B（PSC → IIP → Gateway 2.0）所需的所有准备工作
> 基于：修正后的架构：双入口设计
> 现有环境：GKE 集群 `dev-lon-cluster-xxxxxx`，europe-west2，已部署 Kong Gateway (teamA) + GKE Gateway (teamB)

---

## 一、现状盘点（Pre-requisites Check）

### 1.1 现有 GKE Gateway 状态

| 检查项 | 现状 | 是否需要行动 |
|--------|------|-------------|
| GKE Gateway API 是否已启用 | **未知** | 需确认 |
| 当前 Gateway 数量 | **未知** | 需盘点 |
| Gateway 所在命名空间 | **未知** | 需列出 |
| 已有的 HTTPRoute 数量 | **未知** | 需统计 |

**立即行动：**
```bash
# 1. 检查 Gateway API 是否启用
gcloud container clusters describe dev-lon-cluster-xxxxxx \
  --region europe-west2 \
  --format="value(networkConfig.gatewayApiConfig)"

# 2. 查看当前所有 Gateway 资源
kubectl get gateway -A

# 3. 查看 gateway-system 命名空间
kubectl get all -n gateway-system

# 4. 查看所有 HTTPRoute
kubectl get httproute -A

# 5. 查看当前 Forwarding Rules 使用量
gcloud compute forwarding-rules list \
  --regions=europe-west2 \
  --format="value(name,IPAddress,target)" | wc -l
```

### 1.2 IIP（Nginx）现状

IIP 是新增 Entry Point B 的入口组件，**需要确认以下信息**：

| 检查项 | 说明 | 优先级 |
|--------|------|--------|
| IIP 部署在哪里 | GCE VM？K8s Pod？现有 Nginx？ | **P0** |
| IIP 的 SSL 证书 | 已有 `*.appdev.abjx` 证书？ | **P0** |
| IIP 配置文件位置 | `/etc/nginx/conf.d/` | **P1** |
| IIP 当前 upstream 配置 | 当前指向哪里 | **P1** |
| IIP 健康检查配置 | `/health` endpoint | **P1** |

**立即行动：**
```bash
# 检查 IIP 机器上的证书
ls /etc/nginx/ssl/ 2>/dev/null
openssl x509 -in /etc/nginx/ssl/wildcard.appdev.abjx.crt -noout -dates 2>/dev/null

# 检查 IIP 当前配置
cat /etc/nginx/nginx.conf | grep -A5 "upstream"
```

### 1.3 现有 Kong Gateway 状态

| 检查项 | 说明 |
|--------|------|
| Kong Gateway 版本 | 影响 declarative config 语法 |
| Kong 命名空间 | Kong 运行在哪个 ns |
| 当前 upstream services | 确认 API 服务不冲突 |
| SSL 证书配置方式 | cert-manager？手动挂载？ |

```bash
kubectl get pod -A | grep -i kong
kubectl get svc -A | grep -i kong
kubectl get deployment -A | grep -i kong
```

---

## 二、证书准备（Certificate Preparation）

### 2.1 证书清单

根据架构设计，需要以下证书：

| # | 证书用途 | 证书类型 | 持有者 | 存储位置 | 状态 |
|---|---------|---------|--------|---------|------|
| 1 | `*.appdev.abjx` 公网证书 | 通配符公网 CA | Gateway 2.0 Listener | K8s Secret `gateway-2-external-cert` | **需确认是否已有** |
| 2 | Gateway 2.0 内部证书 | 内部 CA | Gateway → 后端验证 | K8s Secret `gateway-2-internal-cert` | **需新建** |
| 3 | IIP 内部证书 | 内部 CA | IIP → Gateway 2.0 验证 | K8s Secret `iip-internal-cert` | **需新建** |
| 4 | Kong GW 2.0 内部证书 | 内部 CA | Kong GW 2.0 入站 | K8s Secret `kong-gw2-internal-cert` | **需新建** |
| 5 | Direct Backend 证书 | 内部 CA | Direct Pod 入站 | K8s Secret `iip-direct-cert` | **需新建** |

### 2.2 证书申请/生成计划

**方案 A：使用 cert-manager 自动管理（推荐）**
- 公网证书：Let's Encrypt + DNS01 challenge
- 内部证书：Vault PKI 或 GCP Certificate Authority Service

**方案 B：手动生成（快速验证）**
```bash
# 生成内部 CA
openssl genrsa -out internal-ca.key 2048
openssl req -x509 -new -nodes -key internal-ca.key \
  -sha256 -days 365 \
  -out internal-ca.crt \
  -subj "/CN=internal-gke-local/O=AibangDev"

# 为 Gateway 2.0 生成内部证书
openssl req -new -nodes -keyout gateway-2-internal.key \
  -out gateway-2-internal.csr \
  -subj "/CN=gateway-2.gke.internal/O=Gateway2"

# 用内部 CA 签发
openssl x509 -req -in gateway-2-internal.csr \
  -CA internal-ca.crt \
  -CAkey internal-ca.key \
  -CAcreateserial \
  -out gateway-2-internal.crt \
  -days 365 -sha256
```

### 2.3 证书决策项

- [ ] 确认 `*.appdev.abjx` 公网证书是否已在有效期内
- [ ] 确认证书存放位置（当前 IIP 用的是哪个路径？）
- [ ] 确定内部 CA 方案（新建还是复用现有？）
- [ ] Gateway 2.0 是否需要同时持有公网+内部证书？
- [ ] 证书 Secret 命名空间：`gateway-system` vs `iip`

---

## 三、Namespace 规划（Namespace Planning）

### 3.1 新增 Namespace

| Namespace | 用途 | 组件 | 与现有环境关系 |
|-----------|------|------|---------------|
| `gateway-system` | GKE Gateway 系统级 | Gateway 2.0 CR, HTTPRoute | 可能已存在 |
| `iip` | IIP 相关组件 | Kong GW 2.0, Direct Backend | **新建** |

### 3.2 命名冲突检查

现有环境可能已有的 Service names vs 新增：

| Service 名称 | 现有 ns | 新增 ns | 冲突风险 |
|-------------|---------|---------|---------|
| `kong-gateway-2-svc` | ? | `iip` | **需确认** |
| `iip-direct-svc` | ? | `iip` | **需确认** |
| `iip-default-svc` | ? | `iip` | **需确认** |

```bash
# 检查这些 Service 名称是否已存在
kubectl get svc -A | grep -E "kong-gateway-2|iip-direct|iip-default"
```

### 3.3 Network Policy 规划

**IIP namespace (`iip`) 的入站规则：**

| 来源 | 目标 Port | 允许原因 |
|------|----------|---------|
| Gateway 2.0 (ILB) | 443, 8443 | 合法入口流量 |
| Gateway 2.0 (ILB) | 8080 | health check |
| 特定 Admin IP | 8444 | Kong Admin API（可选） |

**示例 NetworkPolicy：**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: iip-namespace-default-deny
  namespace: iip
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-gateway2
  namespace: iip
spec:
  podSelector:
    matchLabels:
      app: kong-gateway-2
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: gateway-system
    ports:
    - protocol: TCP
      port: 443
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-health-check
  namespace: iip
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: gateway-system
    ports:
    - protocol: TCP
      port: 8080
```

---

## 四、GKE Gateway 2.0 部署（Gateway 2.0 Deployment）

### 4.1 GKE Gateway API 启用检查

GKE Gateway API 需要在集群级别显式启用：

```bash
# 检查集群 Gateway API 配置
gcloud container clusters describe dev-lon-cluster-xxxxxx \
  --region europe-west2 \
  --format="json" | jq '.networkConfig.gatewayApiConfig'

# 如果未启用，需要升级集群或开启特性门
gcloud container clusters update dev-lon-cluster-xxxxxx \
  --region europe-west2 \
  --gateway-api=standard
```

### 4.2 Gateway 2.0 资源配置清单

| 资源类型 | 资源名称 | Namespace | 说明 |
|---------|---------|-----------|------|
| Gateway | `gateway-2-internal` | `gateway-system` | 内部 ILB，port 443 |
| HTTPRoute | `gateway-2-routes` | `gateway-system` | 路由规则 |
| ComputeAddress | `gateway-2-ip` | `gateway-system` | 预留 ILB IP `10.100.0.100` |
| Secret | `gateway-2-external-cert` | `gateway-system` | 公网证书 |
| Secret | `gateway-2-internal-cert` | `gateway-system` | 内部证书 |
| HealthCheckPolicy | (GCP 自动创建) | - | ILB 健康检查 |

### 4.3 HTTPRoute 路由规则设计

| Route | Path | Backend | Backend Port |
|-------|------|---------|-------------|
| `/iip/kong/*` | PathPrefix `/iip/kong` | `kong-gateway-2-svc` | 443 |
| `/iip/direct/*` | PathPrefix `/iip/direct` | `iip-direct-svc` | 8443 |
| `/iip/*` (default) | PathPrefix `/iip` | `iip-default-svc` | 8080 |

### 4.4 GCP 配额检查

根据 quota 文档，GKE Gateway 底层消耗：

```bash
# 查看当前已使用的 Forwarding Rules
gcloud compute forwarding-rules list \
  --regions=europe-west2 \
  --format="value(name)" | wc -l

# 查看 Backend Services 数量
gcloud compute backend-services list \
  --format="value(name)" | wc -l

# 查看当前配额
gcloud compute regions describe europe-west2 \
  --flatten="quotas[]" \
  --filter="quota:METRIC_INSTANCE" 2>/dev/null
```

### 4.5 Gateway 2.0 部署待确认项

- [ ] `gateway-system` Namespace 是否已存在？
- [ ] `gke-l7-rilb` GatewayClass 是否可用？
- [ ] ILB IP `10.100.0.100` 是否已被占用？
- [ ] 静态 IP 是否已在 GCP 层面预留？
- [ ] Firewall Rule 是否允许 ILB 健康检查流量？
- [ ] HTTPRoute `allowedRoutes.namespaces.from: All` 是否符合安全策略？

---

## 五、IIP（Nginx）配置变更（IIP Configuration Changes）

### 5.1 变更范围

IIP 现有配置需要增加 **到 Gateway 2.0 的 upstream 和 server block**：

| 文件 | 变更内容 |
|------|---------|
| `/etc/nginx/nginx.conf` 或 `/etc/nginx/conf.d/` | 新增 `upstream gateway2_upstream` |
| `/etc/nginx/conf.d/iip-gateway-2.conf` | 新增 server block 监听并转发到 Gateway 2.0 |

### 5.2 现有 IIP 配置分析

**需要确认：**
1. 现有 IIP 监听端口（80? 443? 都监听？）
2. 现有 upstream 配置（当前 IIP 的流量去向）
3. SSL 证书路径
4. 现有 server_name 配置（是否支持 `*.appdev.abjx` 泛匹配）

### 5.3 新增 Nginx 配置

```nginx
# /etc/nginx/conf.d/iip-gateway-2.conf

upstream gateway2_upstream {
    server 10.100.0.100:443;  # Gateway 2.0 ILB IP
    keepalive 32;
}

server {
    listen 443 ssl;
    server_name ~^(?<subdomain>.+)\\.appdev\\.abjx$;

    # SSL 公网证书
    ssl_certificate /etc/nginx/ssl/wildcard.appdev.abjx.crt;
    ssl_certificate_key /etc/nginx/ssl/wildcard.appdev.abjx.key;

    # Gateway 2.0 内部 CA 证书（用于验证后端）
    proxy_ssl_trusted_certificate /etc/nginx/ssl/internal-ca.crt;

    location ~ ^/iip/kong(/|$) {
        proxy_pass https://gateway2_upstream;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Original-Host $subdomain.appdev.abjx;
        proxy_set_header X-Entry-Point "kong-gw2";
        proxy_ssl_verify on;
        proxy_ssl_server_name on;
    }

    location ~ ^/iip/direct(/|$) {
        proxy_pass https://gateway2_upstream;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Original-Host $subdomain.appdev.abjx;
        proxy_set_header X-Entry-Point "direct";
        proxy_ssl_verify on;
        proxy_ssl_server_name on;
    }

    location / {
        return 404;
    }
}
```

### 5.4 IIP 配置待确认项

- [ ] 确认 IIP 机器上的证书路径
- [ ] 确认证书是否支持 `*.appdev.abjx`
- [ ] 确认 IIP 的 `/health` endpoint 路径
- [ ] Nginx `proxy_ssl_server_name` 需要 SNI，IIP 所在网络是否支持？
- [ ] IIP → Gateway 2.0 的防火墙是否放行 `10.100.0.100:443`？

---

## 六、Kong Gateway 2.0 部署（Kong GW 2.0 Deployment）

### 6.1 部署架构

```
Kong GW 2.0
  Deployment: 2 replicas
  Service: kong-gateway-2-svc (ClusterIP, port 443)
  Namespace: iip
  TLS: 内部 CA 证书挂载
```

### 6.2 与现有 Kong Gateway 的关系

| 对比项 | 现有 Kong Gateway | Kong Gateway 2.0 |
|--------|------------------|-----------------|
| 命名空间 | ? | `iip` |
| 端口 | 8000/8443 | 443 |
| 用途 | Entry Point A (teamA) | Entry Point B (teamB) |
| 配置方式 | declarative config? | declarative config |
| upstream | 指向 GKE Runtime | 指向 GKE Runtime (iip ns) |

### 6.3 Kong Gateway 2.0 部署待确认项

- [ ] 确定 Kong 版本（影响 declarative config 格式，`_format_version`）
- [ ] 确认是否复用现有 Kong Deployment 还是独立新建
- [ ] `iip` namespace 下 ServiceAccount 规划
- [ ] Kong Admin API 是否对外开放？（影响安全策略）
- [ ] upstream service URL：`https://iip-direct-svc.iip.svc.cluster.local:8443`

---

## 七、Direct Backend 部署（Direct Backend Deployment）

### 7.1 部署架构

```
iip-direct Backend
  Deployment: 2 replicas
  Service: iip-direct-svc (ClusterIP, port 8443)
  Namespace: iip
  TLS: 内部 CA 证书挂载
  Health Endpoint: /health on 8443
```

### 7.2 待确认项

- [ ] 确认 Direct Backend 的实际镜像
- [ ] 确认 `/health` endpoint 是否存在
- [ ] 确认容器端口定义（8443 还是 443？）

---

## 八、PSC 配置（PSC Configuration）

### 8.1 PSC 现状检查

```bash
# 查看当前 PSC Attachments
gcloud compute forwarding-rules list \
  --global \
  --format="value(name,IPAddress,target)" | grep -i psc

# 查看 Producer Project
gcloud compute service-attachments list \
  --format="value(name,producerSwitches)"
```

### 8.2 PSC 变更范围

| 变更项 | 说明 |
|--------|------|
| PSC Attachment 配置 | 是否需要修改 producer project 的 PSC 配置 |
| IIP Endpoint IP | IIP 暴露的 IP 是否需要新增？ |
| 路由目标 | PSC → IIP 的路由是否已配置 |

### 8.3 PSC 待确认项

- [ ] 确认跨 project PSC 的 producer/consumer 关系
- [ ] 确认 IIP 的 endpoint IP（PSC Attachment 的 target）
- [ ] 确认 VPC 网络配置是否支持 ILB 访问

---

## 九、Network Policy 与安全（Security Hardening）

### 9.1 待制定 Network Policy

| Namespace | Policy | 规则 |
|-----------|--------|------|
| `gateway-system` | 入站限制 | 仅允许 ILB 健康检查 |
| `gateway-system` | 出站限制 | 仅允许到 `iip` ns |
| `iip` | 入站限制 | 仅允许 `gateway-system` |
| `iip` | 出站限制 | 允许 DNS, API server, internet |

### 9.2 Istio/SPIRE mTLS 考虑

- [ ] `iip` namespace 是否启用 Istio injection？
- [ ] 如果启用，Pod 需要相应的 Label
- [ ] 如果不启用，Pod 间流量是否需要加密？（SPIRE 或手动 mTLS）

---

## 十、监控与可观测性（Observability）

### 10.1 新增监控指标

| 指标 | 来源 | 告警阈值建议 |
|------|------|------------|
| Gateway 2.0 ILB Health | GCP Cloud Monitoring | unhealth > 1min |
| IIP → Gateway 2.0 延迟 | Nginx log | p99 > 500ms |
| Kong GW 2.0 5xx 率 | Kong statsd/prometheus | > 1% |
| 证书到期 | cert-manager + Cloud Monitoring | < 30天 |

### 10.2 日志配置

- [ ] IIP access log 是否需要新增 upstream 标签？
- [ ] Gateway 2.0 HTTPRoute 是否有 Cloud Logging？
- [ ] Kong GW 2.0 日志如何收集？（Fluent Bit / Cloud Logging）

---

## 十一、风险与依赖（Risks & Dependencies）

### 11.1 高风险项

| 风险 | 描述 | 缓解方案 |
|------|------|---------|
| IIP → Gateway 2.0 网络不通 | VPC 层面防火墙未放行 | 提前验证网络连通性 |
| 证书配置错误 | Gateway 2.0 Listener 证书绑定失败 | 先用 HTTP 测试路由，再加 HTTPS |
| 命名冲突 | `iip` namespace 或 Service 名称已存在 | 实施前全面扫描 |
| HTTPRoute 规则冲突 | 与现有 HTTPRoute 的 hostnames overlap | 检查现有 HTTPRoute hostnames |

### 11.2 关键依赖路径

```
证书准备
  │
  ▼
gateway-system Namespace + Gateway 2.0 CR 创建
  │
  ▼
IIP Nginx 配置更新（upstream + server block）
  │
  ▼
HTTPRoute 绑定 + 路由验证
  │
  ▼
Kong GW 2.0 / Direct Backend 部署
  │
  ▼
PSC 路由打通 → 端到端验证
```

---

## 十二、实施优先级（Implementation Priority）

### Phase 1: 基础设施准备（1-2天）

- [ ] **P0** GKE Gateway API 启用状态确认
- [ ] **P0** IIP 现状盘点（证书、配置、upstream）
- [ ] **P0** 证书准备（优先准备 `*.appdev.abjx` 公网证书）
- [ ] **P1** `gateway-system` namespace + Gateway 2.0 CR 创建
- [ ] **P1** ILB 静态 IP 预留
- [ ] **P1** Firewall Rule 配置（ILB 健康检查）

### Phase 2: Gateway 2.0 核心部署（2-3天）

- [ ] **P0** Gateway 2.0 Listener 配置（TLS + hostname）
- [ ] **P0** HTTPRoute 创建（临时 default backend 验证连通性）
- [ ] **P1** IIP Nginx 配置变更（upstream → Gateway 2.0）
- [ ] **P1** 端到端 HTTP 验证
- [ ] **P2** HTTPRoute Header Filter 配置

### Phase 3: Kong GW 2.0 / Direct Backend 部署（2-3天）

- [ ] **P0** `iip` namespace 创建
- [ ] **P0** Kong GW 2.0 Deployment + Service
- [ ] **P0** Direct Backend Deployment + Service
- [ ] **P1** Kong declarative config 编写
- [ ] **P1** HTTPRoute backendRef 指向真实后端
- [ ] **P2** NetworkPolicy 部署

### Phase 4: 安全与可观测性（1-2天）

- [ ] **P1** NetworkPolicy 细化
- [ ] **P2** mTLS 配置（可选）
- [ ] **P2** 监控告警配置
- [ ] **P2** 日志配置

### Phase 5: PSC 打通 + 验收（1-2天）

- [ ] **P0** PSC 路由验证
- [ ] **P0** TLS 端到端验证
- [ ] **P1** 性能基线测量
- [ ] **P1** 回滚方案测试

---

## 十三、立即可执行的检查命令汇总

```bash
# === 1. GKE Gateway 状态 ===
gcloud container clusters describe dev-lon-cluster-xxxxxx --region europe-west2 \
  --format="value(networkConfig.gatewayApiConfig)"
kubectl get gateway -A
kubectl get httproute -A

# === 2. 当前 ILB / Forwarding Rules 使用量 ===
gcloud compute forwarding-rules list --regions=europe-west2 --format="value(name)" | wc -l
gcloud compute backend-services list --format="value(name)" | wc -l

# === 3. 现有 Kong 状态 ===
kubectl get pod -A | grep -i kong
kubectl get svc -A | grep -i kong

# === 4. 命名冲突检查 ===
kubectl get svc -A | grep -E "kong-gateway-2|iip-direct|iip-default"
kubectl get ns | grep -E "gateway-system|iip"

# === 5. IIP 证书检查 ===
ssh <IIP_HOST> "ls /etc/nginx/ssl/ && \
  openssl x509 -in /etc/nginx/ssl/wildcard.appdev.abjx.crt -noout -dates"

# === 6. 配额检查 ===
gcloud compute regions describe europe-west2 \
  --flatten="quotas[]" \
  --filter="quota:FORWARDING_RULES or quota:BACKEND_SERVICES"
```

---

*文档版本：v1.0*
*生成时间：2026-05-13*
*基于架构：gateway/no-gateway/diagram/gateway-2.0-architecture.html*
