# Cross-Project PSC NEG 最终方案 SRE 监控需求增强版

## 1. 文档目的

本文档面向 SRE，基于最终落地方案 [`/Users/lex/git/knowledge/gcp/cross-project/3.md`](/Users/lex/git/knowledge/gcp/cross-project/3.md) 提炼上线后必须具备的监控、告警、日志、验证和运行保障要求。

同时参考了现有基线文档：

- [`/Users/lex/git/knowledge/gcp/cross-project/cross-project-sre.md`](/Users/lex/git/knowledge/gcp/cross-project/cross-project-sre.md)
- [`/Users/lex/git/knowledge/gcp/cross-project/3-enhance.md`](/Users/lex/git/knowledge/gcp/cross-project/3-enhance.md)

目标不是重复架构说明，而是明确：

- SRE 必须监控什么
- 哪些指标需要告警
- 哪些日志必须采集
- 出问题时从哪一层开始排查
- 上线前必须做哪些验证

---

## 2. 监控范围和最终架构

### 2.1 监控范围

本次监控需求只覆盖 `3.md` 中确认的最终链路，不扩展到其他未定方案。

最终链路：

```text
External Client
  -> Global HTTPS Load Balancer
  -> Cloud Armor
  -> Backend Service
  -> PSC NEG (Consumer, A Project Shared VPC)
  -> Service Attachment (Producer, B Project Private VPC)
  -> Internal Load Balancer
  -> Backend Service (GKE / VM / MIG)
```

### 2.2 关键事实

这些事实直接决定 SRE 的监控重点：

- `PSC NEG`、`Service Attachment`、`ILB` 必须在同一 `Region`
- `Service Attachment` 依赖 Producer 侧 `PSC NAT Subnet`
- Consumer 侧 `PSC NEG` 依赖 Shared VPC subnet 与对应 IAM 授权
- 整条链路是串联链路，任一关键组件异常都可能导致入口 5xx 或超时
- 该方案相较旧 `NON_GCP_PRIVATE_IP_PORT NEG` 方案，多了 `PSC NEG`、`Service Attachment`、`PSC NAT subnet`、审批流和 `accept list` 这些新的运维对象

---

## 3. SRE 监控目标

SRE 需要覆盖 5 类目标：

1. 可用性：请求能不能成功穿过整条链路
2. 性能：延迟是不是稳定在可接受范围内
3. 连接状态：PSC 消费端和生产端是否保持可用连接
4. 变更风险：IAM、审批、路由、防火墙等变更是否影响服务
5. 容量风险：配额、NAT 地址池、后端资源是否接近上限

---

## 4. Must-Have 监控需求

## 4.1 GLB / Cloud Armor 层

这是用户感知最直接的一层，必须作为顶层服务视角。

| 监控项 | 目的 | 建议阈值 | 严重级别 |
| --- | --- | --- | --- |
| GLB 请求总量 `request_count` | 判断是否有流量突降或突增 | 相比基线下降 > 50% 持续 5min | P2 |
| GLB 5xx 比例 | 判断入口是否出现服务不可用 | > 1% 持续 5min | P1 |
| GLB 后端延迟 P95/P99 | 判断链路是否明显变慢 | P99 > 2s 持续 5min | P2 |
| Backend Service 健康实例比例 | 判断后端是否被整体摘除 | healthy < 95% | P1 |
| Cloud Armor `DENY` 数量 | 判断攻击、误杀、规则异常 | 相比近 1h 基线突增 > 300% | P2 |

### SRE 关注点

- 如果入口 5xx 上升，这是最高优先级告警源
- 如果 Cloud Armor `DENY` 突增，要区分攻击流量和策略误杀
- 如果 QPS 明显下降但 5xx 不高，要检查是否有健康检查摘除或上游无流量

## 4.2 PSC NEG 层

这是本方案相对旧方案新增的关键监控层。

| 监控项 | 目的 | 建议阈值 | 严重级别 |
| --- | --- | --- | --- |
| PSC NEG endpoint 健康/存在性 | 判断 NEG 是否有效挂接 | endpoint 数量低于预期或状态异常 | P1 |
| PSC NEG 相关错误日志 | 判断 consumer 侧是否建连失败 | 持续出现错误 > 2min | P1 |
| PSC NEG region/资源配置变更审计 | 判断是否有人修改关键绑定关系 | 任意变更事件 | P2 |

### SRE 关注点

- `GLB 5xx` 上升但 ILB/Backend 看起来正常时，优先查 PSC NEG
- Shared VPC 授权问题经常会先表现为 PSC NEG 创建失败或关联失败
- 该层适合同时做指标监控和审计日志监控

## 4.3 Service Attachment 层

这是 Producer 控制 Consumer 接入权限的核心位置，也是 PSC 特有风险点。

| 监控项 | 目的 | 建议阈值 | 严重级别 |
| --- | --- | --- | --- |
| `connectedEndpoints` | 判断 consumer 是否仍然接入 | 为空或低于预期 | P1 |
| pending approval 状态 | 判断是否有接入审批卡住 | pending > 15min | P2 |
| accept list / connection preference 变更 | 判断接入策略被修改 | 任意变更事件 | P2 |
| 活跃连接数接近配额 | 判断是否有连接上限风险 | > 80% 配额 | P2 |

### SRE 关注点

- 这是“流量完全不通但网络没断”的高频根因之一
- 对于 `ACCEPT_MANUAL`，建议把 pending 状态做成显式告警
- 对于 `ACCEPT_AUTOMATIC`，仍需保留 accept list 变更审计

## 4.4 Producer ILB 层

ILB 是 Producer 内部入口，故障会直接导致所有 PSC 流量不可用。

| 监控项 | 目的 | 建议阈值 | 严重级别 |
| --- | --- | --- | --- |
| ILB backend 健康率 | 判断后端是否可被转发 | healthy < 95% | P1 |
| ILB 后端延迟 | 判断 producer 内部处理是否变慢 | P99 > 1s | P2 |
| 连接超时 / reset 数量 | 判断转发稳定性 | > 10/min 持续 5min | P1 |
| forwarding rule / backend service 配置变更 | 判断关键转发面是否被修改 | 任意变更事件 | P2 |

### SRE 关注点

- 这层建议必须有健康检查视图
- 如果 `Service Attachment` 正常但入口依旧 5xx，优先看 ILB backend 健康

## 4.5 Backend 层

不管后端是 GKE、VM 还是 MIG，最终都需要提供统一的服务健康视角。

| 监控项 | 目的 | 建议阈值 | 严重级别 |
| --- | --- | --- | --- |
| 实例/Pod 可用副本数 | 判断服务是否降容 | < 预期副本数 | P1 |
| CPU / 内存使用率 | 判断资源是否接近瓶颈 | > 80% 持续 10min | P2 |
| 应用 5xx / timeout 比例 | 判断业务本身是否异常 | > 5% 持续 5min | P1 |
| HPA 频繁抖动 | 判断容量或负载模型异常 | 高频扩缩容 | P3 |
| 健康检查接口成功率 | 判断应用 readiness 是否稳定 | < 99% | P1 |

### SRE 关注点

- 需要区分“链路打不通”和“业务本身报错”
- 应用层必须带 `trace_id` 或请求关联字段，不然跨层排障会很慢

## 4.6 PSC NAT Subnet / 配额层

这层在原文档里提到了，但需要提升为明确的监控对象，而不是只在上线时手工检查。

| 监控项 | 目的 | 建议阈值 | 严重级别 |
| --- | --- | --- | --- |
| PSC NAT subnet IP 使用率 | 判断地址池是否接近耗尽 | > 70% | P2 |
| PSC NEG 数量 / Region 配额 | 判断是否接近平台限制 | > 80% | P2 |
| Service Attachment 连接数配额 | 判断扩租户时是否有风险 | > 80% | P2 |
| GLB backend 数量 / 配额 | 判断后续扩展性 | > 70% | P3 |

### SRE 关注点

- NAT 地址池不足不会一定先表现为稳定 5xx，更可能是连接异常、间歇性失败、扩容后突然出问题
- 这类容量问题适合做“趋势监控 + 提前告警”，不要等服务报错后再看

---

## 5. Recommended 监控需求

这些不是第一天必须全部做到，但强烈建议纳入短期计划。

### 5.1 网络与路径验证

- VPC Flow Logs
  - 用于确认流量是否经过预期路径
  - 用于排查延迟升高、丢包、连接异常
  - 建议按需开启或采样，避免计费失控

- 跨 Region 延迟观测
  - 如果未来可能跨 Region，建议预留单独延迟指标
  - 当前 V1 单 Region 也要显式验证 Region 一致性

### 5.2 审计与安全

- Audit Logs
  - Service Attachment 审批
  - Shared VPC IAM 变更
  - Backend Service / forwarding rule / health check 变更
  - Cloud Armor 规则变更

- 安全策略告警
  - `compute.networkUser` 删除或改动
  - accept list 变更
  - proxy-only subnet / health check ranges / PSC NAT subnet 相关变更

### 5.3 成本与趋势

- PSC 流量成本趋势
- Cloud Armor 请求量和命中规则趋势
- Backend 带宽增长趋势
- 按 project / service / tenant 的成本归属视图

---

## 6. 日志采集要求

## 6.1 必须采集

| 日志源 | 必须字段 | 用途 |
| --- | --- | --- |
| GLB 访问日志 | host、path、status、latency、backend latency、client IP、trace id | 用户入口视角，定位 5xx 和慢请求 |
| Cloud Armor 日志 | action、matched rule、source IP、request path | 分析误杀、攻击和规则效果 |
| Backend 应用日志 | trace id、status、latency、error code、upstream dependency | 业务层根因分析 |
| Audit Logs | actor、resource、operation、timestamp | 变更审计和回溯 |

## 6.2 推荐采集

| 日志源 | 用途 | 说明 |
| --- | --- | --- |
| VPC Flow Logs | 网络层排障 | 建议采样或按需开启 |
| PSC / Service Attachment 连接相关日志 | consumer 接入排障 | 可结合命令查询和审计事件 |
| ILB / 健康检查相关日志 | 验证 ILB 后端状态 | 用于定位 502/超时 |

### 日志要求

- 所有关键层尽量带统一关联字段，例如 `trace_id` 或 `x-request-id`
- 需要能按以下维度检索：
  - project
  - region
  - backend service
  - PSC NEG
  - service attachment
  - tenant 或 consumer project

---

## 7. Dashboard 需求

至少要有 4 个 Dashboard，而不是只看一个“总览面板”。

### Dashboard 1: 端到端服务健康

- GLB QPS
- GLB 4xx / 5xx
- P95 / P99 延迟
- Backend Service 健康比例
- 错误预算消耗

### Dashboard 2: PSC 链路状态

- PSC NEG 状态
- Service Attachment `connectedEndpoints`
- pending approvals
- PSC NAT subnet 使用率
- 关键 region 资源状态

### Dashboard 3: Producer 侧内部健康

- ILB backend 健康率
- ILB 延迟
- Backend CPU / memory / replica
- 应用错误率
- HPA 事件

### Dashboard 4: 安全与变更审计

- Cloud Armor deny / allow 趋势
- IAM 变更事件
- Service Attachment 配置变更
- health check / forwarding rule / backend service 变更

---

## 8. 告警策略建议

## 8.1 优先级划分

### P1 立即响应

- GLB 5xx > 1% 持续 5min
- Backend healthy ratio < 95%
- PSC NEG endpoint 异常
- Service Attachment `connectedEndpoints` 为空
- ILB backend 健康率低于阈值
- 应用 5xx / timeout 超阈值

### P2 工作时段处理

- P99 延迟 > 2s
- QPS 明显下跌
- pending approval > 15min
- PSC NAT subnet > 70%
- 配额使用率 > 80%
- Cloud Armor deny 突增
- IAM / 接入策略关键变更

### P3 观察类

- HPA 抖动
- GLB backend 数量接近阈值
- 成本异常增长

## 8.2 SLO 告警

建议不要只做静态阈值告警，还要做 SLO 燃烧率告警。

建议最小 SLO：

- 可用性：`>= 99.9%`
- 延迟：`P95 < 300ms`，`P99 < 1s`

建议最少两类 SLO 告警：

- 快速燃烧：5min 窗口，发现分钟级事故
- 慢速燃烧：1h 窗口，发现持续性能回退或容量问题

---

## 9. Runbook 需求

每个核心告警都应该有对应 Runbook，至少覆盖下面几类。

| 告警场景 | 第一检查点 | 第二检查点 | 第三检查点 |
| --- | --- | --- | --- |
| GLB 5xx 上升 | GLB backend 健康 | PSC NEG 状态 | Service Attachment / ILB / Backend |
| Service Attachment 无连接 | 审批状态 | accept list | consumer project / region / IAM |
| PSC NEG 异常 | NEG 描述信息 | Shared VPC subnet/IAM | Backend Service 关联关系 |
| ILB backend 不健康 | 健康检查配置 | Backend 实例/Pod | 防火墙/路由 |
| 延迟升高 | GLB latency | ILB/backend latency | VPC Flow Logs / 资源利用率 |

### 紧急回滚要求

文档里必须保留从 `PSC NEG` 回切到旧 `NON_GCP_PRIVATE_IP_PORT NEG` 方案的步骤，因为 `3.md` 明确这是替换关系，不是并存关系。

SRE 需要具备：

- 明确回滚命令
- 明确回滚触发条件
- 明确回滚后的验证步骤
- 明确回滚时谁审批、谁执行、谁广播

---

## 10. 上线前验证清单

## 10.1 功能验证

- [ ] GLB -> PSC NEG -> Service Attachment -> ILB -> Backend 链路全通
- [ ] Service Attachment 状态为 `ACCEPTED`
- [ ] B Project 能确认流量经过 PSC 通道
- [ ] 健康检查路径和端口完全正确
- [ ] Cloud Armor 策略已验证

## 10.2 监控验证

- [ ] Dashboard 正确展示 QPS、延迟、错误率
- [ ] P1/P2 告警都能被模拟触发
- [ ] Audit Logs 可追溯关键资源变更
- [ ] 应用日志能和入口日志串起来
- [ ] 配额和 NAT 地址池已有趋势视图

## 10.3 故障注入验证

- [ ] 单个 backend 故障后服务仍可用
- [ ] 单 zone backend 故障后 ILB 仍可转发
- [ ] 手动撤销 Service Attachment 接入后，告警能及时触发
- [ ] PSC NEG 摘除或异常后，入口能观测到并告警
- [ ] 回滚到旧 NEG 方案的演练跑通过

## 10.4 运维边界验证

- [ ] Shared VPC 的 `compute.networkUser` 授权路径明确
- [ ] Service Attachment 审批流程明确
- [ ] A Project 与 B Project 的 on-call 边界明确
- [ ] 告警升级路径明确

---

## 11. 建议的实施优先级

### P0 本次上线前必须完成

1. GLB / PSC NEG / Service Attachment / ILB / Backend 五层监控接通
2. P1 告警接通并完成模拟触发
3. Audit Logs 和关键变更告警接通
4. 回滚 Runbook 可执行并完成一次演练

### P1 上线后短期完成

1. PSC NAT subnet 和配额趋势监控
2. VPC Flow Logs 按需接入
3. SLO 燃烧率告警
4. Cloud Armor 规则命中审计面板

### P2 中期优化

1. Service Attachment 审批自动化
2. 成本监控面板
3. 多 Region 预案和监控模型

---

## 12. 结论

相较原始 `cross-project-sre.md`，这版需要 SRE 特别补强 4 个点：

1. 把 `PSC NEG`、`Service Attachment`、`PSC NAT subnet` 从“方案细节”提升为一线监控对象
2. 把 Shared VPC IAM 和审批流纳入正式告警，而不是只靠人工检查
3. 把回滚到旧 NEG 方案定义成正式运行能力
4. 把容量和趋势监控前置，避免 PSC 上线后只盯 5xx

如果只做入口 5xx 和后端 CPU 监控，这个方案在生产上是不够的。PSC 新增的连接状态、审批状态、NAT 容量和跨项目权限边界，都是这条链路的真实故障面。
