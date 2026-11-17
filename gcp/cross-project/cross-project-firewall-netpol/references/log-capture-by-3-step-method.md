# PSC 跨项目日志抓取 SOP — 按"3 步法"组织

> **本文是 firewall-by-instance-path.md 的姊妹文档**：你已经按"实例视角"定位了要放通的 firewall 规则，但 deny-all + 多 project + PSC 隧道让日志抓取变得困难。
>
> 本文按你给的方法论组织：**① 最窄过滤（直接 IP）→ ② 各平台拉基础信息 → ③ 逐步丰富条件精确定位**。
>
> 适用范围：`gcloud logging read` + VPC flow logs，**不含** Splunk / Fluentd / BigQuery 中间件。

---

## 0. 原始问题（保留 Lex 原话 verbatim）

> "对于我的这种场景来说，因为有 subnet 的存在，所以我在抓取日志的时候可能有一些困难或者说不是很友好。所以我现在要专注到这个 GCP 日志抓取的部分。"
>
> "如果我使用 cross project 方式，并通过 server attachment 暴露来实现整个网络流程，那么如何抓取特定日志或获取日志情况就非常重要。"
>
> "基于我的个人经验，建议按以下逻辑整理日志抓取步骤：
> 1. 首先进行最小化日志过滤：关键字给得越少越好，例如直接指定一个对应的 IP。
> 2. 到各个平台过滤该 IP 对应的日志，拿到基础信息。
> 3. 在此基础上逐步增加日志过滤条件，以精确定位问题。"

**核心难点**：

- PSC 隧道在跨 project 时**隐藏了真实源 IP**（用 PSC NAT subnet 替换）— 抓 src_ip 找不到原始 Tenant IP
- 多个 Project 同时存在日志，**不知道哪个 project 该查**
- 日志类型分散（firewall / VPC flow / LB / NEG / K8s）— **不知道该看哪一类**
- 子网 IP 段在 deny-all 规则下经常被静默 drop — **没有日志就等于黑洞**

---

## 1. 核心方法论：3 步法

```
Step 1: 最小化过滤（直接 IP / 关键 ID）
   ↓ 拿到基础时间窗 + 来源类型
Step 2: 到各平台拉基础信息
   ├─ Tenant Project 的 firewall / LB / VPC flow
   ├─ Master Project 的 firewall / LB / VPC flow
   └─ GKE 集群（如涉及）
   ↓ 拿到日志在哪个 project + resource.type
Step 3: 逐步丰富过滤条件
   ├─ 加时间窗（聚焦故障时段）
   ├─ 加 disposition（ALLOWED vs DENIED）
   ├─ 加 protocol / port
   └─ 加 reporter / direction
```

**反模式**（千万别这么干）：

- ❌ **上来就过滤 "jsonPayload.connection.src_ip='X.X.X.X'"** — 在 PSC 路径下真实 src IP 被替换，匹配 0 条
- ❌ **过滤 keyword 太长** — `resource.type=gce_firewall_rule AND jsonPayload.connection.src_ip=... AND jsonPayload.disposition='DENIED' AND timestamp...` — 错一个条件全空
- ❌ **只在单一 project 查** — PSC 跨项目，至少要看 Tenant + Master 两边
- ❌ **没启用日志就查** — firewall rule 默认**不记日志**，必须先 `--enable-logging`；VPC flow log 默认**关闭**

---

## 2. 准备工作（先做一次就行）

### 2.1 启用 VPC firewall 规则日志

**所有"排查相关"的 firewall rule 必须先 `--enable-logging`**，否则 deny 时完全没记录。

```bash
# 列出当前未启用 logging 的 firewall rules
gcloud compute firewall-rules list \
  --project=${PROJECT} \
  --format='table(name,direction,disabled,logConfig.enable)' | grep False

# 给所有相关 firewall rule 启用 logging
gcloud compute firewall-rules update ${RULE_NAME} \
  --project=${PROJECT} \
  --enable-logging

# 批量（注意：gcloud 没有 batch update，每条单独跑）
for rule in m-mig-ingress-from-psc-nat m-mig-hc-allow-probes m-mig-egress-to-gke-gateway; do
  gcloud compute firewall-rules update ${rule} \
    --project=${MASTER_PROJECT} \
    --enable-logging
done
```

### 2.2 启用 VPC Flow Logs（关键 — PSC 路径必须开）

**没启用 = 看不到 PSC 流量的 src/dst**，只看到 GCP 内部 NAT 后的地址。

```bash
# 给 PSC NAT subnet 开（关键！passthrough LB 时 backend 看到的 src 是 PSC NAT subnet 内的 IP）
gcloud compute networks subnets update ${MASTER_PSC_NAT_SUBNET} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --enable-flow-logs

# 给 proxy-only subnet 开（proxy 类 LB 时 backend 看到的 src 是这里的 IP）
gcloud compute networks subnets update ${MASTER_PROXY_ONLY_SUBNET} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --enable-flow-logs

# 给 backend instance subnet 开（路径 A：MIG subnet）
gcloud compute networks subnets update ${MASTER_MIG_SUBNET} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --enable-flow-logs

# 给 backend GKE node subnet 开（路径 B）
gcloud compute networks subnets update ${MASTER_GKE_NODE_SUBNET} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --enable-flow-logs
```

**采样率**（控制成本 + 完整性）：

```bash
# 默认 0.5（采样 50%）— 适合大多数场景
gcloud compute networks subnets update ${SUBNET} \
  --logging-flow-samples=0.5 \
  --logging-aggregation-interval=interval-5-sec

# 故障排查时改 1.0（100% 采样）— 短期排查用
gcloud compute networks subnets update ${SUBNET} \
  --logging-flow-samples=1.0
```

### 2.3 启用 LB access logs（看请求级日志）

```bash
# 给 backend service 启用 logging（采样率 0.0 ~ 1.0）
gcloud compute backend-services update ${BS_NAME} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --enable-logging \
  --logging-sample-rate=1.0
```

---

## 3. Step 1 — 最小化过滤（直接 IP / 关键 ID）

### 3.1 拿到你要追的关键 IP

**PSC 跨项目里你手上能拿到的 IP 有 3 类**：

| 你手上的 IP | 实际是什么 | 在哪查到 |
|------------|----------|---------|
| **PSC endpoint IP**（在 Tenant） | 私网 forwarding rule VIP — 不是 backend IP | `gcloud compute forwarding-rules describe ${PSC_EP}` |
| **Tenant 客户端 VM/Pod IP** | 真实源 IP（client 视角） | Tenant workload 自身 |
| **Master MIG / GKE Pod IP** | backend 实际 IP | `gcloud compute instances list` / `kubectl get pod -o wide` |

**核心警告**：PSC 路径下，**Master 端 backend 看到的 src IP 不是 Tenant 客户端 IP，是 PSC NAT subnet 内的某个 IP**（passthrough LB）或 **proxy-only subnet 内的某个 IP**（proxy 类 LB）。

→ 你要在 Step 1 **用 PSC NAT subnet CIDR** 或 **proxy-only subnet CIDR** 过滤，**不是用 Tenant 客户端 IP**。

### 3.2 Step 1 最小过滤命令（直接按 IP 拿基础信息）

#### Tenant Project（查 PSC endpoint 出向）

```bash
# 假设你有 Tenant Pod IP / VM IP，从 Tenant Project 端查
gcloud logging read \
  "jsonPayload.connection.src_ip='<TENANT_VM_OR_POD_IP>'" \
  --project=${TENANT_PROJECT} \
  --limit=20 \
  --format='table(timestamp,resource.type,jsonPayload.connection.dest_ip,jsonPayload.connection.dest_port,jsonPayload.disposition)'
```

**期望看到**：

- `resource.type=gce_firewall_rule` — Tenant egress firewall 命中
- `resource.type=gce_subnetwork` — Tenant subnet 的 VPC flow log
- 时间戳集中在故障窗口

#### Master Project（查 PSC NAT 或 proxy-only subnet 内 IP 进 instance）

```bash
# Step 1a: 从 PSC NAT subnet 内任选一个 IP（passthrough LB 场景）
# 或从 proxy-only subnet 内任选一个 IP（proxy 类 LB 场景）

# 拿 PSC NAT subnet 的 CIDR（passthrough LB 路径）
PSC_NAT_CIDR=$(gcloud compute networks subnets list \
  --project=${MASTER_PROJECT} \
  --filter='purpose="PRIVATE_SERVICE_CONNECT"' \
  --format='value(ipCidrRange)' | head -1)
echo "PSC NAT CIDR: ${PSC_NAT_CIDR}"

# 或 拿 proxy-only subnet CIDR（proxy 类 LB 路径）
PROXY_CIDR=$(gcloud compute networks subnets list \
  --project=${MASTER_PROJECT} \
  --filter='purpose="REGIONAL_MANAGED_PROXY"' \
  --format='value(ipCidrRange)' | head -1)
echo "Proxy-only CIDR: ${PROXY_CIDR}"

# Step 1b: 拿 PSC endpoint IP（这一步关键 — PSC endpoint 是 Tenant 侧私网 IP）
PSC_EP_IP=$(gcloud compute forwarding-rules describe ${PSC_EP_NAME} \
  --project=${TENANT_PROJECT} --region=${REGION} \
  --format='value(IPAddress)')
echo "PSC Endpoint IP: ${PSC_EP_IP}"

# Step 1c: 拿 backend MIG / GKE Pod IP（要追的最终目的）
MIG_IP=$(gcloud compute instances list \
  --project=${MASTER_PROJECT} \
  --filter="name:${MIG_NAME_PREFIX}" \
  --format='value(networkInterfaces[0].networkIP)' | head -1)
echo "MIG backend IP: ${MIG_IP}"
```

#### Master Project：第一次"裸跑"过滤（拿基础时间窗 + 来源类型）

```bash
# 假设故障 IP 是 MIG_IP + 时间在最近 1 小时
START=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 只指定 IP + 时间窗 — 不加任何 resource.type / disposition，先看日志形态
gcloud logging read \
  "jsonPayload.connection.dest_ip='${MIG_IP}' AND timestamp>='${START}' AND timestamp<='${END}'" \
  --project=${MASTER_PROJECT} \
  --limit=50 \
  --format='table(timestamp,resource.type,jsonPayload.connection.src_ip,jsonPayload.connection.src_port,jsonPayload.connection.dest_port,jsonPayload.disposition,resource.labels.firewall_rule_name)'
```

**期望输出**（按 resource.type 分组）：

```
TIMESTAMP                       RESOURCE.TYPE            SRC_IP        SRC_PORT  DEST_PORT  DISPOSITION  FIREWALL_RULE
2026-08-16T10:23:45+00:00       gce_firewall_rule        10.200.0.5    41234     443        ALLOWED      m-mig-ingress-from-psc-nat
2026-08-16T10:23:45+00:00       gce_subnetwork           10.200.0.5    41234     443        ACCEPTED     -
2026-08-16T10:23:46+00:00       http_load_balancer       -             -         -          -            (lb access log)
```

**判断**：

- 看到 `gce_firewall_rule` → 继续在 §4 Step 2 / Step 3 精细化
- 看到 `gce_subnetwork` 但没有 `gce_firewall_rule` → **firewall 没启用 logging**（回去 §2.1）
- 看到 `http_load_balancer` → 这是 LB access log，看 statusDetails / backend
- 看到 `DENIED` → firewall 拦了，去看 `firewall_rule_name` 是哪条 deny 规则
- 看到 `ALLOWED` 但响应 5xx → LB 到 backend 这一段的问题

---

## 4. Step 2 — 各平台拉基础信息（按路径）

### 4.1 路径 A：Tenant → MIG instance（passthrough LB）

#### Tenant Project 侧

```bash
# 4.1.1 看 Tenant egress firewall 是否允许出 PSC endpoint
gcloud logging read \
  "resource.type=gce_firewall_rule AND resource.labels.project_id=${TENANT_PROJECT} AND jsonPayload.connection.dest_ip='${PSC_EP_IP}'" \
  --project=${TENANT_PROJECT} \
  --limit=20

# 4.1.2 看 Tenant VPC flow log（src = Tenant workload, dst = PSC endpoint）
gcloud logging read \
  "resource.type=gce_subnetwork AND logName~'${TENANT_VPC}' AND jsonPayload.connection.dest_ip='${PSC_EP_IP}'" \
  --project=${TENANT_PROJECT} \
  --limit=20

# 4.1.3 看 Tenant GLB access log（如有）
gcloud logging read \
  "resource.type=http_load_balancer AND jsonPayload.statusDetails:\"backend_response_sent_by_backend\"" \
  --project=${TENANT_PROJECT} \
  --limit=20 \
  --format='value(timestamp,jsonPayload.statusDetails,jsonPayload.backendTargetProject,jsonPayload.backendTargetType)'
```

#### Master Project 侧

```bash
# 4.1.4 看 Master ingress firewall 命中（路径 A 关键 — backend 看到 src = PSC NAT subnet IP）
gcloud logging read \
  "resource.type=gce_firewall_rule AND jsonPayload.connection.dest_ip='${MIG_IP}' AND jsonPayload.disposition='DENIED'" \
  --project=${MASTER_PROJECT} \
  --limit=20 \
  --format='table(timestamp,resource.labels.firewall_rule_name,jsonPayload.connection.src_ip,jsonPayload.connection.dest_port)'

# 4.1.5 看 Master ILB access log（如 backend service 已 enable-logging）
gcloud logging read \
  "resource.type=http_load_balancer AND jsonPayload.backendTargetProject='${MASTER_PROJECT}'" \
  --project=${MASTER_PROJECT} \
  --limit=20 \
  --format='value(timestamp,jsonPayload.statusDetails,jsonPayload.backendIp)'

# 4.1.6 看 MIG instance 上的 nginx / 业务日志（GCE instance 上跑的应用）
gcloud logging read \
  "resource.type=gce_instance AND resource.labels.instance_id='${INSTANCE_ID}'" \
  --project=${MASTER_PROJECT} \
  --limit=20 \
  --format='table(timestamp,severity,jsonPayload.message)'
```

### 4.2 路径 B：Tenant → GKE Pod（proxy 类 LB）

#### Tenant Project 侧（同路径 A §4.1.1-4.1.3）

#### Master Project 侧（重点 — 这里日志最分散）

```bash
# 4.2.1 看 Master proxy-only subnet 上的 VPC flow log（backend 看到的 src 是这里的 IP）
gcloud logging read \
  "resource.type=gce_subnetwork AND logName~'${MASTER_PROXY_ONLY_SUBNET}' AND jsonPayload.connection.dest_ip:\"${GKE_POD_CIDR}\"" \
  --project=${MASTER_PROJECT} \
  --limit=20 \
  --format='table(timestamp,jsonPayload.connection.src_ip,jsonPayload.connection.dest_ip,jsonPayload.connection.dest_port,jsonPayload.disposition)'

# 4.2.2 看 Master ingress firewall（gke-node tag，自动由 GKE controller 创建）
gcloud logging read \
  "resource.type=gce_firewall_rule AND resource.labels.target_tags:gke-node AND jsonPayload.disposition='DENIED'" \
  --project=${MASTER_PROJECT} \
  --limit=20

# 4.2.3 看 GKE Gateway / NEG access log
gcloud logging read \
  "resource.type=http_load_balancer AND jsonPayload.backendTargetType='INSTANCE_GROUP'" \
  --project=${MASTER_PROJECT} \
  --limit=20

# 4.2.4 看 GKE cluster audit log（Pod 创建 / Service 配置变化）
gcloud logging read \
  "resource.type=k8s_cluster AND resource.labels.cluster_name=${GKE_CLUSTER_NAME}" \
  --project=${MASTER_PROJECT} \
  --limit=20 \
  --format='table(timestamp,severity,jsonPayload.message)'
```

#### GKE 集群内（从 kubectl 看）

```bash
# 4.2.5 Pod 内部日志（应用 stdout / stderr）
kubectl logs -n <namespace> <pod-name> --previous --tail=200

# 4.2.6 NetworkPolicy 命中（K8s 不直接给"被 deny"的日志，但可通过 flow log 反推）
# 见 §4.2.1 — Pod 没看到流量 + VPC flow log 显示到达 pod = NetworkPolicy 拦了

# 4.2.7 kube-proxy / cilium 日志（如 K8s 网络层有问题）
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=200
kubectl logs -n kube-system -l k8s-app=cilium --tail=200  # 如用 Cilium
```

### 4.3 路径 C：反向（Master → Tenant audit pull）

```bash
# 4.3.1 看 Master Pod egress 是否到 Tenant API
gcloud logging read \
  "resource.type=gce_subnetwork AND logName~'${MASTER_VPC}' AND jsonPayload.connection.dest_ip:\"${TENANT_VPC_CIDR}\"" \
  --project=${MASTER_PROJECT} \
  --limit=20

# 4.3.2 看 Tenant ingress firewall 是否 allow Master VPC CIDR
gcloud logging read \
  "resource.type=gce_firewall_rule AND jsonPayload.connection.src_ip:\"${MASTER_VPC_CIDR}\" AND jsonPayload.disposition='DENIED'" \
  --project=${TENANT_PROJECT} \
  --limit=20

# 4.3.3 看 Tenant 端 API endpoint access log（如 Compute API / BigQuery / etc.）
gcloud logging read \
  "resource.type=audited_resource AND protoPayload.authenticationInfo.principalEmail:\"${MASTER_GSA}@\"" \
  --project=${TENANT_PROJECT} \
  --limit=20
```

---

## 5. Step 3 — 逐步丰富过滤条件精确定位

### 5.1 从 Step 2 拿到的"基本时间窗 + resource.type"开始加条件

**典型递进路径**：

```text
Step 1: 只过滤 dest_ip + timestamp
        ↓ 拿到 resource.type / disposition
Step 2: 加 resource.type=<具体类型>
        ↓ 拿到 src_ip 模式 / firewall_rule_name
Step 3: 加 disposition='DENIED' + firewall_rule_name=<具体>
        ↓ 精确定位哪条 deny 规则
        或 加 disposition='ALLOWED' + protocol+port → 看响应
Step 4: 加 reporter + direction → 看是 NETWORK 还是 INSTANCE 评估
Step 5: 加 severity + 关联时间 → 看具体事件
```

### 5.2 实际示例：定位"MIG instance 收不到流量"

**初始症状**：Tenant curl 超时，Master MIG log 没看到请求

**递进过程**：

```bash
# Step 1: 拿基础
gcloud logging read \
  "jsonPayload.connection.dest_ip='${MIG_IP}' AND timestamp>='${START}'" \
  --project=${MASTER_PROJECT} --limit=50 \
  --format='table(timestamp,resource.type,jsonPayload.disposition)'

# 假设看到 DENIED 的 gce_firewall_rule 条目

# Step 2: 加 disposition
gcloud logging read \
  "resource.type=gce_firewall_rule AND jsonPayload.connection.dest_ip='${MIG_IP}' AND jsonPayload.disposition='DENIED' AND timestamp>='${START}'" \
  --project=${MASTER_PROJECT} --limit=20 \
  --format='table(timestamp,resource.labels.firewall_rule_name,jsonPayload.connection.src_ip,jsonPayload.connection.dest_port,jsonPayload.rule_details.direction)'

# 假设看到 firewall_rule_name=m-default-deny-ingress（隐式 deny 兜底规则）

# Step 3: 加具体 deny 规则名 + 拿 src_ip 模式
gcloud logging read \
  "resource.type=gce_firewall_rule AND resource.labels.firewall_rule_name='m-default-deny-ingress' AND jsonPayload.connection.dest_ip='${MIG_IP}' AND timestamp>='${START}'" \
  --project=${MASTER_PROJECT} --limit=20 \
  --format='table(timestamp,jsonPayload.connection.src_ip,jsonPayload.connection.dest_port)'

# 关键发现: src_ip 都是 PSC NAT subnet 内的 IP（如 10.200.0.5）
# 但 m-mig-ingress-from-psc-nat 没匹配 → 说明这条 firewall 规则 source-ranges 写错或没启用

# Step 4: 验证 firewall rule 配置
gcloud compute firewall-rules describe m-mig-ingress-from-psc-nat \
  --project=${MASTER_PROJECT} \
  --format='yaml(sourceRanges,targetTags,rules,logConfig.enable,disabled)'
```

**根因定位**：可能是

- `sourceRanges` 写错（用了 Tenant VPC CIDR 而不是 PSC NAT subnet CIDR）
- `targetTags` 不匹配 instance 的实际 tag
- `disabled=true`
- `priority` 被其他规则覆盖

### 5.3 递进技巧汇总表

| 当你想加... | 语法 | 适用 |
|------------|------|------|
| 时间窗 | `timestamp>="2026-08-16T00:00:00Z"` | 聚焦故障时段 |
| 资源类型 | `resource.type=gce_firewall_rule` | 区分 firewall / flow / LB |
| 命中处置 | `jsonPayload.disposition='DENIED'` 或 `'ALLOWED'` | 快速筛选拒绝 / 允许 |
| 协议端口 | `jsonPayload.connection.protocol=6 AND jsonPayload.connection.dest_port=443` | TCP/UDP + 端口 |
| Reporter | `jsonPayload.reporter='NETWORK'` 或 `'INSTANCE'` | 区分 VPC 层 vs instance 内 |
| 防火墙名 | `resource.labels.firewall_rule_name='<name>'` | 定位具体规则 |
| 实例 ID | `resource.labels.instance_id='<id>'` | 定位具体 VM |
| 子网 | `logName~'<SUBNET_NAME>'` | 区分不同 subnet 的 flow log |
| Severity | `severity=ERROR` 或 `WARNING` | 过滤错误/警告 |
| 跨字段 OR | `(jsonPayload.connection.src_ip='X' OR jsonPayload.connection.dest_ip='Y')` | 多 IP 组合 |
| 模糊匹配 | `jsonPayload.message:"timeout"` 或 `:~"timeout"` | 应用日志关键词 |

### 5.4 jq 二次加工（拿到结构化数据）

```bash
# 拿到所有 DENIED 的 src_ip + 统计出现次数
gcloud logging read \
  "resource.type=gce_firewall_rule AND jsonPayload.disposition='DENIED' AND timestamp>='${START}'" \
  --project=${MASTER_PROJECT} \
  --format=json \
  | jq -r '.[] | .jsonPayload.connection.src_ip' \
  | sort | uniq -c | sort -nr | head -20

# 拿到 DENIED 涉及的 firewall_rule_name + 次数
gcloud logging read \
  "resource.type=gce_firewall_rule AND jsonPayload.disposition='DENIED' AND timestamp>='${START}'" \
  --project=${MASTER_PROJECT} \
  --format=json \
  | jq -r '.[] | .resource.labels.firewall_rule_name' \
  | sort | uniq -c | sort -nr

# 拿到 LB access log 的 status code 分布
gcloud logging read \
  "resource.type=http_load_balancer AND timestamp>='${START}'" \
  --project=${MASTER_PROJECT} \
  --format=json \
  | jq -r '.[] | .jsonPayload.statusDetails // "UNKNOWN"' \
  | sort | uniq -c | sort -nr
```

---

## 6. 日志类型速查表（该看哪个）

| 现象 | 看哪类日志 | resource.type | 关键字段 |
|------|----------|---------------|----------|
| **firewall 拦了流量** | VPC Firewall Logs | `gce_firewall_rule` | `disposition`, `firewall_rule_name`, `src_ip`, `dest_ip` |
| **流量到了 subnet 但不知道后续** | VPC Flow Logs | `gce_subnetwork` | `src_ip`, `dest_ip`, `protocol`, `disposition` |
| **LB 返回 5xx** | LB Access Logs | `http_load_balancer` | `statusDetails`, `backendIp`, `backendTargetProject` |
| **PSC endpoint 不可达** | VPC Flow Logs + Firewall | 同上 | 看 PSC EP IP 是否在 flow log 出现 |
| **Service Attachment 未 accept** | Audit Log | `cloudsql_database` / `gce_service_attachment` | `protoPayload.methodName`, `protoPayload.response` |
| **GKE Pod 收不到流量** | K8s Cluster Audit + VPC Flow | `k8s_cluster` + `gce_subnetwork` | 看 NetworkPolicy 变化 + 看 Pod IP 是否在 flow log |
| **Cloud Armor 拦了** | Cloud Armor Logs | `http_load_balancer` (含 enforcedSecurityPolicy) | `enforcedSecurityPolicy.name`, `enforcedSecurityPolicy.outcome` |
| **GKE Gateway 状态变化** | GKE Cluster Audit | `k8s_cluster` | `protoPayload.methodName="io.k8s.networking.gateway.v1.Gateways"` |

### 6.1 一次拿到"全栈日志"的方法（最快）

```bash
# 假设关键 IP = PSC endpoint IP
gcloud logging read \
  "jsonPayload.connection.dest_ip='${PSC_EP_IP}' OR jsonPayload.connection.src_ip='${PSC_EP_IP}'" \
  --project=${TENANT_PROJECT} \
  --limit=100 \
  --format='table(timestamp,resource.type,severity,resource.labels.firewall_rule_name,jsonPayload.disposition)' 2>&1 | head -50
```

**一次性会拉到**：Tenant firewall + Tenant flow + Tenant GLB（如果有）+ Master flow（如跨 project IAM 配置过）— 完整堆栈视图。

---

## 7. 常见错误信号 → 该看哪类日志

| 现象 | 大概率原因 | 该看日志 |
|------|----------|---------|
| **Tenant curl 完全超时（无响应）** | Tenant egress / PSC EP / Master ingress 任一环拦了 | Tenant egress firewall + Master ingress firewall + VPC flow（两端）|
| **Tenant curl 拿到 503** | Service Attachment 未 accept / LB 没 backend | Service Attachment audit + LB access log |
| **Tenant curl 拿到 502/504** | Backend 不通 / NetworkPolicy 拦 | Master backend Pod log + Master ingress firewall + K8s NetworkPolicy |
| **Tenant curl 拿到 connection refused** | firewall 拦 / 没 listen | Master ingress firewall + SSH 到 instance 看 `ss -nltp` |
| **Tenant curl 拿到 TLS 错误** | cert SAN 不匹配 / cert chain 缺失 | LB access log statusDetails + cert path |
| **Health check 失败但应用正常** | hc firewall / 端口错 | `resource.type=gce_firewall_rule` 的 hc rules + GCP health check log |
| **返回 5xx 间歇性** | backend OOM / over load | LB access log + instance log + metric |
| **Pod 完全没看到流量** | NetworkPolicy deny proxy-only | `resource.type=gce_subnetwork` flow 看是否到 pod IP + K8s NP describe |

---

## 8. 跨 Project 日志聚合查询（如果两边都要看）

**场景**：故障可能在 Tenant 端，也可能在 Master 端，单 project 查不全。

### 8.1 临时方案：分别查 + 手动关联

```bash
# 同一个 IP，分别查 Tenant 和 Master
for project in ${TENANT_PROJECT} ${MASTER_PROJECT}; do
  echo "===== Project: ${project} ====="
  gcloud logging read \
    "jsonPayload.connection.dest_ip='${KEY_IP}' AND timestamp>='${START}'" \
    --project=${project} \
    --limit=20 \
    --format='table(timestamp,resource.type,resource.labels.firewall_rule_name,jsonPayload.disposition)'
done
```

### 8.2 长期方案：Log Scope（生产推荐）

> 详细的跨 project 日志聚合配置见 `../../logs/cross-project-sharing-logs.md`（已有完整 §3 / §4），本文不重复。

**最小配置流程**（在你已经在 Master 配置 Log Scope 时）：

```bash
# 1. Master 创建 Log View（包含 Tenant project 的日志）
gcloud logging views create tenant-a-view \
  --bucket=_Default \
  --location=global \
  --log-filter='resource.labels.project_id="<TENANT_PROJECT>"'

# 2. Master 创建 Log Scope，把 Tenant view 加进去
gcloud logging scopes create ops-scope \
  --resource=projects/<TENANT_PROJECT>/locations/global/buckets/_Default/views/tenant-a-view \
  --resource=projects/<MASTER_PROJECT>/locations/global/buckets/_Default/views/master-view

# 3. 授权
gcloud projects add-iam-policy-binding <TENANT_PROJECT> \
  --member='user:<YOUR_EMAIL>' \
  --role='roles/logging.viewAccessor'

# 4. 查询时指定 scope（而不是 project）
gcloud logging read \
  "jsonPayload.connection.dest_ip='${KEY_IP}'" \
  --scope=ops-scope \
  --limit=50
```

### 8.3 不推荐：Sink 物理导出（仅在合规 / 长期归档场景）

```bash
# 仅在需要把日志物理搬到一个 logging-hub-project 时用 — 否则 Log Scope 更经济
gcloud logging sinks create ops-sink \
  logging.googleapis.com/projects/logging-hub-project/locations/global/buckets/central-platform-logs \
  --log-filter="resource.labels.project_id=~\"<TENANT_PROJECT>|<MASTER_PROJECT>\"" \
  --project=${MASTER_PROJECT}
```

**成本警告**：Sink 会产生**双重计费**（源 project 收 ingestion + 目标 project 收 storage），只在合规场景用。

---

## 9. 性能 + 配额注意事项

### 9.1 配额

| 资源 | 默认限制 | 影响 |
|------|---------|------|
| `gcloud logging read` 返回上限 | 1000 条/次 | 大数据量要分页或加 `--limit` |
| VPC Flow Logs 采样率 | 0.0 ~ 1.0 | 1.0 时数据量 = N 倍（成本上升） |
| Cloud Logging ingestion cost | $0.50/GB | 100% 采样 + 多 subnet = 月费用可观 |

### 9.2 优化技巧

```bash
# 加 --limit 避免一次拉太多
gcloud logging read "..." --limit=100

# 加 --format='value(...)' 只取需要的字段，省 token
gcloud logging read "..." --format='value(timestamp,resource.type,severity)'

# 加 --freshness 控制查询窗口（默认 24h）
gcloud logging read "..." --freshness=1h

# 时间窗用 RFC3339 精确控制
gcloud logging read "..." \
  --start-time="2026-08-16T10:00:00Z" \
  --end-time="2026-08-16T11:00:00Z"
```

### 9.3 突发高流量场景的应急

- **临时把 VPC flow log 采样率调到 1.0**（短期排查）
- 跑完后**务必调回 0.5 或更低**（否则月度账单爆炸）
- 配合 Cloud Monitoring 告警 + Log-based Metric 控制长期成本

---

## 10. 一句话总结

**PSC 跨项目日志抓取的核心方法论是"3 步法"：先按 IP 拿基础形态（不要一次加太多 filter）→ 到 Tenant + Master 两边 platform 拉各自的相关日志（firewall / flow / LB / K8s）→ 拿到 resource.type + 时间窗后再逐步加 disposition / rule_name / src_ip 精确定位。最容易踩的坑是：在 PSC 路径下用 Tenant 客户端 IP 过滤（永远 0 结果）— 用 PSC NAT subnet 或 proxy-only subnet 的 CIDR。**

---

## 11. References

### 11.1 本地知识库

- **`./firewall-by-instance-path.md`** — 本文姊妹文档（按实例视角找 firewall）
- **`../../../logs/cross-project-sharing-logs.md`** — 跨项目日志聚合架构（Log Scope / Sink）
- **`../../../logs/docs/vpc-claude.md`** — VPC flow log 深度分析（Shared VPC 场景）
- **`../../../logs/docs/vpc-log.md`** — VPC 日志基础
- **`../../../logs/docs/test.md`** — 子网日志实战示例
- **`../../../gce/firewall-hit.md`** — firewall 命中查询的核心方法论（"先窄后宽"，跟本文 3 步法同源）
- **`../../../logs/cross-project-sharing-logs.md`** — Log Scope / Sink 完整配置
- **`../psc-firewall-cheatsheet.md`** — passthrough vs proxy 判定（决定该看哪个 subnet 的 flow log）

### 11.2 GCP 一手文档

- [Viewing VPC firewall rule logs](https://cloud.google.com/vpc/docs/firewall-rules-logging) — `gce_firewall_rule` resource 字段定义
- [Viewing VPC flow logs](https://cloud.google.com/vpc/docs/flow-logs) — `gce_subnetwork` resource 字段定义
- [Load balancing access logs](https://cloud.google.com/load-balancing/docs/logging) — `http_load_balancer` resource 字段定义
- [Reading log entries with the gcloud CLI](https://cloud.google.com/logging/docs/view/gcloud-fluentd) — `gcloud logging read` 完整语法
- [Log scopes overview](https://cloud.google.com/logging/docs/view/log-scopes) — 跨 project 聚合
- [K8s audit logging](https://cloud.google.com/kubernetes-engine/docs/how-to/audit-logging) — GKE 集群 audit log

### 11.3 命令模板（直接复制粘贴）

本文所有命令都使用：

- `${TENANT_PROJECT}` / `${MASTER_PROJECT}` — 项目 ID
- `${REGION}` — region（如 europe-west2）
- `${PSC_EP_IP}` / `${MIG_IP}` / `${GKE_POD_CIDR}` — 关键 IP
- `${START}` / `${END}` — 时间窗（RFC3339）
- `${SUBNET}` / `${MASTER_VPC}` — 子网 / VPC 名

替换为你实际值即可运行。

---

*最后更新：2026-08-16 · Lex 个人知识库 · 按"3 步法"组织 · 范围：`gcloud logging read` + VPC flow log*
*核心提醒：PSC 路径下 backend 看到的 src 不是 Tenant 客户端 IP — 用 PSC NAT / proxy-only subnet CIDR*