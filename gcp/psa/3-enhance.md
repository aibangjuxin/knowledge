## 目录

- [Cross-Project PSC NEG 生产环境评估与增强方案](#cross-project-psc-neg-生产环境评估与增强方案)
  - [1. 目标与背景](#1-目标与背景)
    - [1.1 我的理解 (基于 3.md)](#11-我的理解-基于-3md)
    - [1.2 上线门槛与输入项 (SLO/容量/租户模型)](#12-上线门槛与输入项-slo容量租户模型)
    - [1.3 范围、假设与不做什么](#13-范围假设与不做什么)
  - [2. 生产环境瓶颈评估](#2-生产环境瓶颈评估)
    - [2.0 预评估方法 (容量模型 + 压测 + 演练)](#20-预评估方法-容量模型--压测--演练)
    - [2.1 网络延迟层 (Network Latency)](#21-网络延迟层-network-latency)
    - [2.2 容量与配额 (Quota & Limits)](#22-容量与配额-quota--limits)
    - [2.3 故障传播链 (Failure Chain)](#23-故障传播链-failure-chain)
    - [2.4 IAM 与安全 (Security)](#24-iam-与安全-security)
    - [2.5 计费成本 (Cost)](#25-计费成本-cost)
    - [2.6 应用层瓶颈 (AEG/Kong/Nginx/Envoy)](#26-应用层瓶颈-aegkongnginxenvoy)
    - [2.7 变更、发布与回滚 (Operational Readiness)](#27-变更发布与回滚-operational-readiness)
  - [3. 生产环境监控指标](#3-生产环境监控指标)
    - [3.1 必监控指标 (Must-Have)](#31-必监控指标-must-have)
    - [3.2 推荐监控指标 (Recommended)](#32-推荐监控指标-recommended)
    - [3.3 日志审计](#33-日志审计)
    - [3.4 SLO 告警与错误预算 (建议)](#34-slo-告警与错误预算-建议)
  - [4. 可靠性增强建议](#4-可靠性增强建议)
    - [4.1 高可用架构建议](#41-高可用架构建议)
    - [4.2 故障切换策略](#42-故障切换策略)
    - [4.3 容量规划](#43-容量规划)
    - [4.4 多 Region 灾备 (V1 建议)](#44-多-region-灾备-v1-建议)
  - [5. 上线前验证清单](#5-上线前验证清单)
    - [5.1 功能验证](#51-功能验证)
    - [5.2 性能验证](#52-性能验证)
    - [5.3 故障注入测试](#53-故障注入测试)
    - [5.4 监控验证](#54-监控验证)
    - [5.5 安全与合规验证](#55-安全与合规验证)
  - [6. 运维与故障排查](#6-运维与故障排查)
    - [6.1 常见问题速查](#61-常见问题速查)
    - [6.2 紧急回滚](#62-紧急回滚)
  - [7. 总结与建议](#7-总结与建议)
    - [7.1 当前架构评估](#71-当前架构评估)
    - [7.2 优先级建议](#72-优先级建议)
  - [8. 参考文档](#8-参考文档)

---

## 初始评估笔记

```
Now I need to identify potential bottlenecks and production concerns:

1. Network Latency:
   - PSC adds an extra hop compared to direct IP access
   - Cross-region latency concerns

2. Scalability:
   - PSC NEG abjacity limits
   - Service Attachment connection limits

3. Reliability:
   - Single point of failure if not properly designed
   - Health check dependencies

4. Cost:
   - PSC egress fees
   - GLB backend charges
   - Cross-region data transfer

5. Monitoring:
   - What metrics to watch
   - What alerts to set up

6. Security:
   - IAM permissions
   - Connection approval workflow

7. Operational:
   - Failover mechanisms
   - Rollback procedures
```

---

# Cross-Project PSC NEG 生产环境评估与增强方案

## 1. 目标与背景

本文档基于 [`gcp/psa/3.md`](gcp/psa/3.md) 中实现的跨 Project PSC NEG 架构，评估生产环境部署的潜在瓶颈、监控要点和可靠性隐患。

**原始架构：**

```
A Project (入口层)
  ↓
Global Load Balancer
  ↓
PSC NEG (Consumer)
  ↓
B Project Service Attachment (Producer)
  ↓
Internal Load Balancer
  ↓
Backend Service (GKE / VM / MIG)
```

### 1.1 我的理解 (基于 3.md)

你当前方案的本质是：用 **PSC (Private Service Connect) NEG** 替换“跨 Project 直连 ILB IP 的 NEG”，把跨 Project 访问从 **IP 级互通**升级为 **服务级发布与受控接入**。

**关键事实 (会直接影响生产评估结论)：**

- Producer 侧必须有 `purpose=PRIVATE_SERVICE_CONNECT` 的 **PSC NAT Subnet**（用于 SNAT 隔离与连接承载）。
- Consumer 侧 PSC NEG 需要一个 **普通 subnet** 来分配“PSC 接入 IP”（无需 `PRIVATE_SERVICE_CONNECT` purpose）。
- **Region 强约束**：PSC NEG、Service Attachment、ILB 必须在同一 Region（GLB 是 global，但后端是 regional）。
- Shared VPC 下存在 **IAM 授权粒度**差异：subnet 级授权与 network 级授权会影响资源创建与校验路径（3.md 已验证）。

### 1.2 上线门槛与输入项 (SLO/容量/租户模型)

要把这个方案做成“生产环境上限的预评估”，建议先补齐这些输入项，否则容量与瓶颈讨论会停留在“可能”层面：

| 输入项 | 你需要给出的值 (示例) | 用途 |
| --- | --- | --- |
| SLO (可用性/延迟) | `99.9%`；`P95 < 300ms`；`P99 < 1s` | 定义“上线可接受”的成功标准与告警门槛 |
| 峰值 QPS/RPS | 峰值 `X`；日常 `Y`；突发 `Z` | 推导并发、连接、带宽与后端规模 |
| 请求特征 | 平均响应大小；是否流式；是否长连接；超时 | 直接决定 L7 网关与后端的连接/CPU 瓶颈 |
| 租户模型 | 单租户单 Project？多租户共享入口？ | 决定配额消耗、审批流、隔离与成本归属 |
| 故障目标 | RTO/RPO；允许的降级策略 | 决定是否必须多 Region/灾备/多活 |

### 1.3 范围、假设与不做什么

**本文档默认假设：**

- V1 以 **单 Region** 为主，先做到“同 Region 高可用 + 可验证回滚”。
- Producer 侧 ILB 与 Backend 已具备 **多 zone** 高可用基础（否则 PSC 不是你的主要风险点）。

**本文档边界：**

- 本文会点名 **AEG/Kong/Nginx/Ingress** 可能成为瓶颈，但不会替代你对网关与业务本身做完整容量评估（那需要结合真实配置与压测数据）。

---

## 2. 生产环境瓶颈评估

### 2.0 预评估方法 (容量模型 + 压测 + 演练)

把“潜在瓶颈”变成“可验证结论”，建议用一套可重复的方法跑通：

1. **容量模型 (Paper Model)**：先估算并发、连接与带宽，确定压测目标与资源下限。
2. **压测验证 (Load/Spike/Soak)**：用压测把瓶颈定位到具体组件与指标。
3. **故障演练 (Failure Drill)**：验证“健康检查摘除/切换/回滚”是否真的生效。

**容量模型的最小公式：**

- `并发 ≈ 峰值 RPS × P95(秒)`
- `带宽 ≈ 峰值 RPS × 平均响应大小`

建议你把压测拆成三类曲线，并明确成功标准：

- Load：逐步爬坡到目标峰值，观察延迟曲线是否平滑。
- Spike：短时间突发 2-5 倍峰值，验证限流与保护是否生效（避免重试风暴）。
- Soak：持续 2-8 小时稳定负载，验证连接泄漏、NAT/conntrack、HPA 波动等长期问题。

### 2.1 网络延迟层 (Network Latency)

| 维度                 | 风险等级 | 说明                                                                                 |
| -------------------- | -------- | ------------------------------------------------------------------------------------ |
| **PSC 额外跳数**     | 🟡 中     | 相比直接 IP 访问，PSC 增加了一层 Google 内部隧道转发                                 |
| **跨 Region 延迟**   | 🔴 高     | 如果 A/B Project 不在同一 Region，延迟可能增加 10-30ms                               |
| **ILB 健康检查延迟** | 🟡 中     | GLB → PSC NEG → Service Attachment → ILB → Backend，任何一层超时都会触发健康检查失败 |

**优化建议：**

- 优先选择 **同一 Region** 部署 A/B Project
- 调高 GLB 健康检查的 `timeout` 和 `checkInterval`，避免瞬时抖动触发误摘除

### 2.2 容量与配额 (Quota & Limits)

| 资源                          | 限制                                 | 评估                                        |
| ----------------------------- | ------------------------------------ | ------------------------------------------- |
| **PSC NEG 数量**              | 每个 Project/Region 有上限           | 需确认配额，当前架构单个 GLB 通常够用       |
| **Service Attachment 连接数** | 默认 100 consumer/project            | 多 Consumer 场景需申请配额                  |
| **PSC NAT IP 池**             | 受 subnet range 限制                 | 确保 NAT subnet 足够大（建议 `/26` 或更大） |
| **GLB Backend 数量**          | 每个 Backend Service 最大 1000 NEG   | 评估扩展性需求                              |

**监控指标：**

```bash
# 查看 PSC 连接数
gcloud compute service-attachments describe my-service-attachment \
  --project=b-project --region=asia-east1 \
  --format="value(connectedEndpoints)"
```

### 2.3 故障传播链 (Failure Chain)

```
Client → GLB → Cloud Armor → Backend Service → PSC NEG → Service Attachment → ILB → Backend
```

| 故障点                    | 影响范围              | 恢复难度                |
| ------------------------- | --------------------- | ----------------------- |
| GLB 故障                  | 100% 不可用           | 需依赖 GLB 高可用设计   |
| PSC NEG 关联失败          | 流量无法到 B Project  | 检查 PSC NEG 状态与 IAM |
| Service Attachment 未审批 | Consumer 无法建立连接 | 手动 approve 流程       |
| ILB 故障                  | 后端服务不可达        | 依赖 ILB 自身高可用     |
| Backend 故障              | 服务 502              | 后端服务自身修复        |

**风险：** 整条链路是 **串联** 架构，任何单点故障都会导致服务不可用。生产环境建议评估 **多活/灾备** 方案。

### 2.4 IAM 与安全 (Security)

| 风险点                  | 风险等级 | 说明                                                                      |
| ----------------------- | -------- | ------------------------------------------------------------------------- |
| **ACCEPT_MANUAL 模式**  | 🟡 中     | 每次新增 Consumer 需手动 approve，可能导致接入延迟                        |
| **Shared VPC 权限耦合** | 🔴 高     | PSC NEG 依赖 Host Project 的 `compute.networkUser` 权限，权限变更影响服务 |
| **Consumer 列表泄露**   | 🟢 低     | `consumer-accept-list` 暴露了允许的 Project ID                            |

**生产建议：**

- 切换为 `ACCEPT_AUTOMATIC` 模式（如果安全策略允许）
- 使用 Service Account 而非个人账号进行授权
- 定期审计 IAM 权限变更

### 2.5 计费成本 (Cost)

| 成本项              | 计费方式                                    | 预估影响                 |
| ------------------- | ------------------------------------------- | ------------------------ |
| **GLB 费用**        | 规则数 + 流量                               | 常规费用                 |
| **Cloud Armor**     | 规则数 + 请求数                             | 如启用 WAF，费用显著增加 |
| **PSC 出站流量**    | $0.01/GB (同 region) / $0.02/GB (跨 region) | 需关注大流量场景         |
| **跨 Project 流量** | GCP 内部流量不计入公网，但计入 PSC 费用     | 确认账单归属             |

### 2.6 应用层瓶颈 (AEG/Kong/Nginx/Envoy)

你提到的 “访问量到什么程度 AEG 可能成为瓶颈”，在生产里非常常见。一个典型的真实链路通常是：

```
Client → GLB/Cloud Armor → (AEG/Kong/Nginx/Ingress) → PSC → ILB → Backend
```

**为什么 AEG 更容易先到瓶颈：**

- AEG 属于 **自管计算**（GKE/VM），受 CPU/内存/连接数/线程模型/内核参数限制；GLB 是托管服务，扩展性更多由配额与架构决定。
- AEG 往往承载鉴权、路由、限流、日志等“每请求必做”的逻辑，单位请求成本更高。

**生产预评估建议你至少补齐这些工作项：**

- 明确 AEG 做了什么：JWT/mTLS/WAF/请求改写/上游重试/缓存/日志采样。
- 给 AEG 建立容量基线：`P95/P99`，`CPU/Memory`，`active connections`，`upstream timeouts`，`4xx/5xx`。
- 对齐超时与重试：GLB、AEG、后端三层的 `timeout/retry` 要一致且有上限，避免级联重试把 PSC/ILB/后端放大打穿。
- HPA/PDB：确保滚动升级或节点故障时不会把网关副本降到不可用。

**压测定位瓶颈的快速判定法：**

- GLB `5xx` 上升但 AEG 没有收到请求：优先查 GLB → PSC NEG → Service Attachment/ILB 的健康与配额。
- AEG `upstream timeouts` 上升且 CPU 接近上限：先扩容/优化 AEG，再看 PSC/ILB。
- 后端 CPU/依赖服务爆掉：根因在后端或依赖，PSC 只是链路上的放大器。

### 2.7 变更、发布与回滚 (Operational Readiness)

PSC 方案上线后的高风险点往往不是“能不能通”，而是“变更时会不会把整条链路打挂”。建议把以下项目纳入上线门槛，并按优先级推进：

**立即修补 (P0)：**

- `Service Attachment` 的 approve 流程固化为 Runbook（或自动化），避免新 Consumer/新租户接入时人为失误。
- 为 GLB/AEG/Backend 定义统一的 `timeout/retry` 策略，避免重试风暴。
- 明确紧急回滚路径：是否能在 1-5 分钟内把 GLB 后端从 `PSC NEG` 切回旧 `NON_GCP_PRIVATE_IP_PORT NEG`（或其他后备链路）。

**结构改进 (P1)：**

- IaC 落地（Terraform 或 Config Connector）：避免手工 drift，支持一键回滚与一致性审计。
- 灰度/金丝雀：在 URL Map 或 AEG 层实现按租户/按路径灰度，控制爆炸半径。

**长期演进 (P2)：**

- 多 Region 灾备演进：把 Region 级故障从“不可用”降级为“降级可用/切换可用”（需要 Producer 侧同步建设）。

---

## 3. 生产环境监控指标

### 3.1 必监控指标 (Must-Have)

| 指标                            | 来源                                              | 告警阈值建议              |
| ------------------------------- | ------------------------------------------------- | ------------------------- |
| **GLB 错误率 (5xx)**            | Cloud Monitoring                                  | > 1% 持续 5min            |
| **GLB 延迟 (P99)**              | Cloud Monitoring                                  | > 2s                      |
| **Backend Service 健康率**      | Cloud Monitoring                                  | < 95%                     |
| **PSC NEG 端点状态**            | `gcloud compute network-endpoint-groups describe` | 端点数低于预期            |
| **Service Attachment 连接状态** | `gcloud compute service-attachments describe`     | `connectedEndpoints` 为空 |

### 3.2 推荐监控指标 (Recommended)

```bash
# 1. GLB QPS
metric: https_lb_rule/request_count

# 2. PSC 流量
metric: compute.googleapis.com/instance/network/received_bytes_count
filter: resource.labels.network_endpoint_group_name = "psc-neg"

# 3. ILB 健康检查
metric: compute.googleapis.com/instance/health_check_request_count
filter: resource.labels.backend_service_name = "ilb-backend-service"

# 4. Cloud Armor 阻止请求
metric: compute.googleapis.com/armor/security_policy_action_total
filter: action = "DENY"
```

### 3.3 日志审计

| 日志类型                  | 用途                                  |
| ------------------------- | ------------------------------------- |
| **CloudLoadBalancer日志** | 分析请求来源、延迟、错误              |
| **VPC Flow Logs**         | 排查网络层问题（注意计费）            |
| **Audit Logs**            | IAM 变更、Service Attachment 审批记录 |

### 3.4 SLO 告警与错误预算 (建议)

仅靠“指标阈值告警”在生产中容易出现两种问题：要么误报太多，要么故障时告警滞后。更推荐把告警绑定到 SLO/错误预算消耗。

**建议的最小 SLO 拆解：**

- 可用性：`成功率 = 1 - (5xx + 超时) / 总请求`
- 延迟：`P95/P99`（按关键路径 API 分组，而不是全量平均）

**建议你至少落地两类告警：**

- 快速燃烧：短窗口内错误预算消耗很快（用于秒级到分钟级事故发现）。
- 慢速燃烧：长窗口持续异常（用于发现性能回退、容量不足、链路抖动）。

> 实施层面你可以先用 Cloud Monitoring 的 SLO/Alerting（或用日志指标 + MQL），把“上线门槛”里的 SLO 变成可观测与可追责的告警。

---

## 4. 可靠性增强建议

### 4.1 高可用架构建议

```
                    ┌──────────────────┐
                    │   Global External │
                    │      GLB (Anycast) │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   Cloud Armor     │
                    │   (可选 WAF)      │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
       ┌──────▼──────┐ ┌─────▼─────┐ ┌─────▼──────┐
       │ PSC NEG-A   │ │ PSC NEG-B │ │ PSC NEG-C  │
       │ (Region-1)  │ │(Region-1) │ │ (Region-2) │
       └──────┬──────┘ └─────┬─────┘ └─────┬──────┘
              │              │             │
              └──────────────┼──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │   Service Attachment (B)   │
              │   (跨 Region 冗余)          │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │      ILB (Multi-backend)    │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │   Backend (GKE/MIG/VM)      │
              │   (Multi-zone)              │
              └─────────────────────────────┘
```

**关键建议：**

1. **GLB 使用多 Backend Service + URL Map**：实现流量分区
2. **ILB 使用多个 forwarding rule**：跨可用区冗余
3. **Backend 使用 Multi-Zone GKE/MIG**：单 zone 故障不影响服务

### 4.2 故障切换策略

| 场景                          | 切换方案                                               |
| ----------------------------- | ------------------------------------------------------ |
| **PSC NEG 故障**              | GLB Backend Service 健康检查摘除，流量自动切到其他 NEG |
| **Service Attachment 不可用** | 需提前配置跨 Region 备份 Service Attachment            |
| **ILB 故障**                  | 依赖 ILB 后端自身的高可用（GKE 使用多个 Pod）          |
| **Backend 故障**              | GKE/MIG 健康检查自动摘除                               |

### 4.3 容量规划

| 维度               | 建议                                            |
| ------------------ | ----------------------------------------------- |
| **PSC NAT Subnet** | 至少 `/26`（64 IPs），预留 50% 冗余             |
| **ILB 后端实例数** | 最少 2 个（跨 zone）                            |
| **GKE Pod**        | HPA 至少 2 个副本，max 视流量而定               |
| **连接数**         | 单 PSC NEG 默认支持 1000 并发连接，大流量需评估 |

### 4.4 多 Region 灾备 (V1 建议)

如果你的业务对 Region 级故障有明确要求（RTO/RPO），建议把多 Region 灾备作为“结构改进”纳入路线图，而不是临上线再补。

**V1 可落地形态 (建议 Active/Passive)：**

- Producer(B) 在 `Region-1/Region-2` 各自建设一套：`Service Attachment + ILB + Backend`。
- Consumer(A) 在对应 Region 创建 `PSC NEG-1/PSC NEG-2`，并把它们都挂到 GLB 的后端（或拆成两个 Backend Service）。
- 通过健康检查与故障切换策略实现自动摘除与切换。

**风险提示：**

- 多 Region 会显著增加成本与运维复杂度（双份资源、双份告警、演练与发布流程也要成对）。
- 如果后端依赖（数据库、缓存）仍是单 Region，多 Region 只能解决入口与计算层，无法满足端到端的 RTO/RPO。

---

## 5. 上线前验证清单

### 5.1 功能验证

- [ ] GLB 正常返回 200
- [ ] 流量经过 PSC 通道（B Project 能看到源 IP 为 PSC NAT IP）
- [ ] 健康检查路径正常（/healthz 或指定路径）
- [ ] Cloud Armor 规则生效（测试 DENY 规则）
- [ ] Service Attachment 状态为 `ACCEPTED`

### 5.2 性能验证

- [ ] 同 Region 延迟 < 20ms
- [ ] 跨 Region 延迟 < 50ms
- [ ] P99 延迟 < 2s
- [ ] 无连接超时或间歇性失败

### 5.3 故障注入测试

- [ ] 单点 ILB 故障后流量自动切换
- [ ] 单 Zone Backend 故障后服务仍可用
- [ ] 手动关闭 Service Attachment 后 GLB 返回 502

### 5.4 监控验证

- [ ] Dashboard 正确展示 QPS、延迟、错误率
- [ ] 告警规则生效（模拟触发测试）
- [ ] 日志正常采集（VPC Flow Logs 可选开启）

### 5.5 安全与合规验证

- [ ] Cloud Armor 规则最小化且可解释（误杀/漏放都有回归用例）
- [ ] Service Attachment 的 `consumer-accept-list` 与审批策略符合租户隔离要求
- [ ] Shared VPC 的 `compute.networkUser` 授权路径明确且可审计（避免个人账号/临时授权）
- [ ] 关键资源启用 Audit Logs，并能追溯到变更人/变更单（Service Attachment approve、IAM 变更、LB 配置变更）
- [ ] 如链路内存在 AEG/Kong/Nginx：确认上游证书/密钥轮转机制与 mTLS/JWT 策略在压测与故障时不会失效

---

## 6. 运维与故障排查

### 6.1 常见问题速查

| 现象         | 可能原因                      | 排查命令                                                            |
| ------------ | ----------------------------- | ------------------------------------------------------------------- |
| GLB 返回 502 | PSC NEG 健康检查失败          | `gcloud compute network-endpoint-groups describe psc-neg`           |
| 连接被拒绝   | Service Attachment 未 approve | `gcloud compute service-attachments describe my-service-attachment` |
| 延迟过高     | 跨 Region 或 NAT 瓶颈         | VPC Flow Logs + ILB 延迟监控                                        |
| IAM 权限错误 | Shared VPC 权限不足           | 检查 `compute.networkUser` 角色                                     |

### 6.2 紧急回滚

如果 PSC NEG 方案出现问题，可临时回退到原 `NON_GCP_PRIVATE_IP_PORT NEG` 方案：

```bash
# 临时恢复原方案
gcloud compute backend-services remove-backend psc-backend-service \
  --project=a-project --global \
  --network-endpoint-group=psc-neg

gcloud compute backend-services add-backend psc-backend-service \
  --project=a-project --global \
  --network-endpoint-group=old-noneg \
  --network-endpoint-group-region=asia-east1
```

---

## 7. 总结与建议

### 7.1 当前架构评估

| 维度           | 评分     | 说明                                       |
| -------------- | -------- | ------------------------------------------ |
| **功能完整性** | ✅ 满足   | 跨 Project 访问、IP 隔离、IAM 控制均已实现 |
| **生产就绪度** | 🟡 需增强 | 缺少监控告警、故障切换验证                 |
| **可扩展性**   | 🟡 需关注 | 单 Region、单一 Service Attachment         |
| **成本优化**   | 🟢 良好   | PSC 比 Peering 更经济                      |

### 7.2 优先级建议

**立即执行 (P0)：**

1. 配置 GLB/PSC/ILB 健康检查告警
2. 验证故障切换能力
3. 确认 IAM 权限稳定

**短期优化 (P1)：**

1. 开启 VPC Flow Logs（调试模式）
2. 配置 Cloud Armor 日志审计
3. 评估多 Region 灾备方案

**长期规划 (P2)：**

1. 自动化 Service Attachment 审批
2. 成本监控仪表板
3. 多活架构演进

---

## 8. 参考文档

- [GCP PSC 官方文档](https://cloud.google.com/vpc/docs/private-service-connect)
- [GLB 健康检查配置](https://cloud.google.com/load-balancing/docs/health-check-concepts)
- [Service Attachment 配额](https://cloud.google.com/vpc/docs/quotas)
- [Cloud Monitoring 指标](https://cloud.google.com/monitoring/docs/metrics)

---

*文档版本: 1.0*  
*创建日期: 2026-03-13*  
*基于: gcp/psa/3.md*
