# Cross-Project PSC NEG 架构 - SRE 监控需求

## 1. 架构概述

### 目标架构

```
外部 Client
  ↓
A Project (Shared VPC)
  ├─ Global HTTPS Load Balancer
  ├─ Cloud Armor (WAF)
  ├─ Backend Service
  └─ PSC NEG (Consumer Endpoint)
        ↓ [PSC 私有通道]
B Project (Private VPC)
  ├─ Service Attachment (Producer)
  ├─ PSC NAT Subnet (SNAT)
  ├─ Internal Load Balancer
  └─ Backend (GKE / VM / MIG)
```

### 核心特征
- **跨 Project 服务级访问**，不暴露 Backend IP
- **Producer 控制 Consumer 访问权限**（ACCEPT_MANUAL / ACCEPT_AUTOMATIC）
- **单 Region 部署**（PSC NEG、Service Attachment、ILB 必须在同一 Region）
- **串联架构**：任何单点故障都会导致服务不可用

---

## 2. 必监控指标 (Must-Have)

### 2.1 GLB 层（A Project）

| 指标 | 指标名称 | 告警阈值 | 严重等级 |
|------|---------|---------|---------|
| **错误率** | `https_lb_rule/request_count` (5xx) | > 1% 持续 5min | P1 |
| **延迟 P99** | `https_lb_rule/backend_response_latencies` | > 2s | P2 |
| **健康检查失败率** | `https_lb_rule/health_check_probe_status` | < 95% healthy | P1 |
| **QPS 突降** | `https_lb_rule/request_count` | 较基线下降 > 50% | P2 |
| **Cloud Armor 拦截率** | `security_policy_action_total` (DENY) | 突增 > 300% | P2 |

### 2.2 PSC NEG 层（A Project）

| 指标 | 指标名称 | 告警阈值 | 严重等级 |
|------|---------|---------|---------|
| **端点状态** | `compute.googleapis.com/networking/psc_neg_endpoint_health` | 端点数 < 预期值 | P1 |
| **连接失败数** | PSC NEG 连接错误日志 | > 0 持续 2min | P1 |
| **跨区域延迟**（如有） | VPC Flow Logs 延迟推导 | > 50ms | P2 |

### 2.3 Service Attachment 层（B Project）

| 指标 | 指标名称 | 告警阈值 | 严重等级 |
|------|---------|---------|---------|
| **连接状态** | `connectedEndpoints` 是否为空 | 为空 | P0 |
| **Consumer 审批状态** | `connectionPreference` + pending 列表 | 有 pending 超 15min | P2 |
| **连接数上限** | 活跃连接数 / 配额上限 | > 80% | P2 |

### 2.4 ILB 层（B Project）

| 指标 | 指标名称 | 告警阈值 | 严重等级 |
|------|---------|---------|---------|
| **Backend 健康率** | `compute.googleapis.com/instance/health_check_request_count` | < 95% | P1 |
| **后端响应时间** | ILB 后端延迟指标 | P99 > 1s | P2 |
| **连接超时数** | ILB 连接错误计数 | > 10/min | P1 |

### 2.5 Backend 层（B Project - GKE/VM）

| 指标 | 指标名称 | 告警阈值 | 严重等级 |
|------|---------|---------|---------|
| **Pod/VM 健康** | GKE Deployment 副本数 / VM 状态 | 副本数 < 预期 | P1 |
| **CPU/内存使用率** | `container/cpu/utilization` / `memory/used_bytes` | > 80% 持续 10min | P2 |
| **应用错误率** | 自定义指标（5xx/4xx） | > 5% | P1 |
| **HPA 伸缩事件** | GKE HPA 扩容/缩容事件 | 频繁波动 | P3 |

---

## 3. 推荐监控指标 (Recommended)

### 3.1 网络层

```yaml
# VPC Flow Logs (可选开启，注意计费)
- 指标：跨 Project 流量大小
  来源：A Project Shared VPC + B Project Private VPC
  用途：排查网络层问题、容量规划
```

### 3.2 PSC NAT Subnet 容量

```bash
# 监控 PSC NAT IP 使用率
gcloud compute networks subnets describe psc-nat-subnet \
  --project=b-project --region=asia-east1
  
# 告警：已分配 IP / 总 IP > 70%
```

### 3.3 IAM 与审计

| 日志类型 | 用途 |
|---------|------|
| **Audit Logs** | Service Attachment 审批记录、IAM 变更 |
| **Cloud Audit Logs** | GLB/PSC NEG 配置变更追溯 |
| **VPC Flow Logs** | 网络层排障（按需开启） |

---

## 4. SLO 定义建议

### 4.1 可用性 SLO

```
成功率 = 1 - (5xx + 超时) / 总请求

目标：
- P95 延迟 < 300ms
- P99 延迟 < 1s
- 可用性 >= 99.9% (月度)
```

### 4.2 告警策略

| 告警类型 | 窗口 | 错误预算消耗 | 用途 |
|---------|------|------------|------|
| **快速燃烧** | 5min | > 14.4x 速率 | 分钟级事故发现 |
| **慢速燃烧** | 1h | > 3x 速率 | 性能回退/容量不足 |

---

## 5. 日志采集需求

### 5.1 必须采集

| 日志源 | 字段要求 | 用途 |
|--------|---------|------|
| **GLB 访问日志** | 请求路径、延迟、状态码、Backend 响应时间 | 分析请求来源、延迟分布、错误根因 |
| **Cloud Armor 日志** | 匹配规则、动作（ALLOW/DENY）、来源 IP | WAF 策略优化、误杀分析 |
| **Backend 应用日志** | 结构化日志（JSON）、trace ID | 应用层排障、链路追踪 |

### 5.2 推荐采集

| 日志源 | 用途 | 注意事项 |
|--------|------|---------|
| **VPC Flow Logs** | 网络层问题排查 | 计费较高，建议采样或按需开启 |
| **Audit Logs** | IAM/配置变更审计 | 默认开启，确认已导入 Cloud Logging |
| **PSC 连接日志** | Service Attachment 连接/断开事件 | 需自定义日志导出 |

---

## 6. Dashboard 需求

### 6.1 核心 Dashboard

#### Dashboard 1: 全局服务健康

- GLB QPS / 延迟 / 错误率（实时 + 24h 趋势）
- PSC NEG 端点健康状态
- Service Attachment 连接状态
- ILB Backend 健康率
- Cloud Armor 拦截统计

#### Dashboard 2: 容量与性能

- PSC NAT Subnet IP 使用率
- GLB/ILB 连接数
- Backend CPU/内存使用率
- HPA 伸缩事件
- 跨区域延迟（如适用）

#### Dashboard 3: 安全与审计

- IAM 变更事件
- Service Attachment 审批记录
- Cloud Armor 规则命中 Top 10
- 异常访问来源 IP

---

## 7. 告警响应 Runbook 需求

### 7.1 必须提供

| 告警场景 | Runbook 内容 |
|---------|-------------|
| GLB 5xx 上升 | 检查 PSC NEG 状态 → Service Attachment → ILB 健康 → Backend 日志 |
| PSC NEG 端点异常 | 检查 Shared VPC 权限 → Service Attachment 审批 → 网络连通性 |
| Service Attachment 连接失败 | 检查 Consumer Project 是否在 accept list → 手动 approve 流程 |
| ILB Backend 不健康 | 检查 GKE Pod 状态 → 健康检查端口 → 防火墙规则 |

### 7.2 紧急回滚

```bash
# 回退到旧方案 (NON_GCP_PRIVATE_IP_PORT NEG)
1. 从 Backend Service 移除 PSC NEG
2. 添加旧 NEG 作为 Backend
3. 验证流量切换
4. 记录回滚原因与时间戳
```

---

## 8. 上线前验证清单

### 8.1 监控验证

- [ ] Dashboard 正确展示 QPS、延迟、错误率
- [ ] 告警规则生效（模拟触发测试）
- [ ] 日志正常采集（GLB/Cloud Armor/Backend）
- [ ] SLO 计算准确，错误预算告警正常

### 8.2 故障注入测试

- [ ] 单点 ILB 故障后流量自动切换
- [ ] 单 Zone Backend 故障后服务仍可用
- [ ] 手动关闭 Service Attachment 后 GLB 返回 502
- [ ] PSC NEG 端点摘除后告警触发

### 8.3 性能验证

- [ ] 同 Region 延迟 < 20ms（P95）
- [ ] P99 延迟 < 1s
- [ ] 峰值 QPS 下无连接超时
- [ ] Soak 测试 2-8h 无连接泄漏

---

## 9. 配额与容量监控

### 9.1 必须监控配额

| 资源 | 默认配额 | 告警阈值 | 申请方式 |
|-----|---------|---------|---------|
| PSC NEG 数量/Region | 按 Project | > 80% | GCP Console 申请 |
| Service Attachment 连接数 | 100 consumer/Project | > 80% | 联系 GCP 支持 |
| PSC NAT IP 池 | 由 subnet range 决定 | > 70% | 扩大 subnet |
| GLB Backend 数量 | 1000/Backend Service | > 70% | 通常够用 |

---

## 10. 特殊场景监控

### 10.1 Shared VPC 权限变更

| 监控项 | 告警条件 |
|--------|---------|
| `compute.networkUser` IAM 变更 | 任何删除/修改事件 |
| Subnet 级别授权失效 | PSC NEG 创建失败 |

### 10.2 Service Attachment 审批延迟

| 监控项 | 告警条件 |
|--------|---------|
| 新 Consumer 连接 pending 状态 | > 15min 未审批 |
| 自动审批切换为手动 | 配置变更事件 |

### 10.3 防火墙规则变更（Producer 侧）

| 场景 | 监控需求 |
|-----|---------|
| Proxy-only subnet CIDR 变更 | 更新防火墙规则告警 |
| Health check ranges 变更 | 健康检查失败率上升 |
| PSC NAT subnet 变更 | 连接失败突增 |

---

## 11. 交付物清单

### 给 SRE 团队的交付物

1. **Cloud Monitoring Dashboard**（3 个）
   - 全局服务健康
   - 容量与性能
   - 安全与审计

2. **告警策略配置**
   - 快速燃烧告警（5min 窗口）
   - 慢速燃烧告警（1h 窗口）
   - 配额上限告警

3. **Runbook 文档**
   - 常见故障排查流程
   - 紧急回滚步骤
   - Service Attachment 审批流程

4. **SLO 定义与错误预算告警**
   - 可用性 SLO: 99.9%
   - 延迟 SLO: P95 < 300ms, P99 < 1s

5. **配额监控清单**
   - PSC NEG 数量
   - Service Attachment 连接数
   - PSC NAT IP 池使用率

---

## 12. 待确认事项

在最终确定监控需求前，需要你确认以下几点：

| 问题 | 影响 |
|-----|------|
| **B Project 的 ILB 类型是什么？**（Passthrough NLB 还是 Proxy/Envoy 类如 GKE Gateway） | 决定防火墙规则与监控重点 |
| **是否有 AEG/Kong/Nginx 中间层？** | 需要额外监控中间层指标 |
| **峰值 QPS 预期是多少？** | 决定告警阈值与容量规划 |
| **是否需要多 Region 灾备？** | 影响跨区域监控需求 |
| **租户模型是什么？**（单租户/多租户） | 决定配额隔离与成本归属监控 |
| **SLO 目标是否已确定？** | 影响告警窗口与错误预算配置 |
