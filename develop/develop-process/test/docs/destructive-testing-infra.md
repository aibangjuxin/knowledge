# Infrastructure Destructive Testing Guide

破坏性测试（破坏性测试 / Destructive Testing）是一种主动引入受控故障来验证系统韧性的实践。本文档聚焦于**基础设施层面**的破坏性测试，涵盖概念、方法论、工具选型和 GCP/GKE 环境下的落地指南。

---

## 1. 概念与背景

### 1.1 什么是破坏性测试？

破坏性测试的核心思想：**主动制造故障，观察系统行为，建立韧性信心**。

与传统的功能测试不同，破坏性测试的目标不是验证"功能是否正常"，而是验证**"系统在故障下的表现是否符合预期"**。

### 1.2 术语对照

| 英文术语 | 中文 | 说明 |
|---------|------|------|
| Chaos Engineering | 混沌工程 | 通过实验验证分布式系统韧性的学科 |
| Failure Injection | 故障注入 | 人工引入故障（延迟、错误、终止） |
| Game Day | 演练日 | 团队一起进行故障演练的实践 |
| Disaster Recovery Testing | 灾难恢复测试 | 验证 DR 流程和 RTO/RPO |
| Stress Testing | 压力测试 | 验证系统在超负荷下的表现 |
| Fault Tolerance | 容错性 | 系统在组件故障时继续服务的能力 |

### 1.3 混沌工程原则（Principles of Chaos Engineering）

> 参考：[principlesofchaos.org](https://principlesofchaos.org/)

```
1.  定义稳态（Define Steady State）
    先定义什么是"正常"——系统的基准行为指标

2.  假设（Make Hypothesis）
    假设故障注入后，稳态行为保持/降级程度可接受

3.  在生产环境实验（Experiment in Production）
    真实环境才能暴露真实问题（可使用 traffic shadowing）

4.  自动化实验（Automate Experiments）
    手动实验不可持续，需要自动化闭环

5.  最小化爆炸半径（Minimize Blast Radius）
    从小范围、低风险开始，逐步扩大
```

---

## 2. 测试类型分类

### 2.1 按测试层次

```
┌─────────────────────────────────────────────────────────┐
│                      测试层次                            │
├───────────────┬─────────────────────────────────────────┤
│  基础设施层    │  网络分区、节点宕机、存储故障、电源故障        │
│  (Infra)      │  Zone/Region 级别中断、网络延迟注入           │
├───────────────┼─────────────────────────────────────────┤
│  应用层        │  服务崩溃、超时、依赖故障、配置错误             │
│  (Application)│  流量洪泛、连接耗尽、OOM                      │
├───────────────┼─────────────────────────────────────────┤
│  数据层        │  数据库宕机、主从切换、数据不一致               │
│  (Data)       │  写入失败、复制延迟、备份恢复                   │
└───────────────┴─────────────────────────────────────────┘
```

### 2.2 按测试目标

| 测试类型 | 目标 | 典型场景 |
|---------|------|---------|
| **Chaos Engineering** | 验证系统韧性 | 随机终止 Pod、模拟网络分区 |
| **Failure Injection** | 验证故障处理路径 | 注入超时、HTTP 错误、TCP 重置 |
| **Disaster Recovery** | 验证恢复流程 | RTO/RPO 验证、切换演练 |
| **Stress Testing** | 验证容量边界 | 流量突增、资源耗尽 |
| **Resilience Testing** | 验证降级策略 | 级联故障、熔断生效 |

---

## 3. 故障注入场景矩阵

### 3.1 基础设施层（Kubernetes / GKE）

| 故障类型 | 工具实现 | 风险等级 | 影响范围 |
|---------|---------|---------|---------|
| Pod 终止 | `kubectl delete pod` / Litmus | 中 | 单 Pod |
| Pod 全部终止 | Chaos Engine | 高 | 整个 Deployment |
| 节点宕机 | `gcloud compute instances stop` | 高 | 节点上所有 Pod |
| 网络延迟 | `tc netem delay` / Chaos Mesh | 中 | Pod 间通信 |
| 网络丢包 | `tc netem loss` | 中 | 网络通道 |
| 网络分区 | Firewall rules | 高 | 跨节点/跨 Zone 通信 |
| CPU 负载 | `stress-ng` / Chaos Mesh | 中 | 节点性能 |
| 内存耗尽 | `memhog` / OOM | 高 | 节点或 Pod |

### 3.2 应用层

| 故障类型 | 注入方式 | 验证点 |
|---------|---------|-------|
| HTTP 延迟 | Envoy 故障注入 / Toxiproxy | 超时降级是否生效 |
| HTTP 错误 | Envoy 故障注入 | 熔断器是否触发 |
| 依赖超时 | Istio VirtualService fault | 超时重试是否生效 |
| 连接耗尽 | 连接数限制 | 连接池管理 |
| DNS 故障 | CoreDNS 干扰 | 服务发现降级 |

### 3.3 数据层

| 故障类型 | 场景 | 验证点 |
|---------|------|-------|
| 主库宕机 | MySQL/PostgreSQL 主从切换 | 自动切换时间 < RTO |
| 复制延迟 | 模拟慢复制 | 读请求降级策略 |
| 存储不可用 | PD 断开 / NFS 故障 | 数据持久性保证 |
| 备份失败 | 模拟备份任务失败 | 告警是否触发 |

---

## 4. 工具生态

### 4.1 开源工具

| 工具 | 定位 | 平台 | 特点 |
|------|------|------|------|
| **LitmusChaos** | CNCF 项目，Cloud-Native 混沌工程 | Kubernetes | CRD 驱动，社区活跃 |
| **Chaos Mesh** | 云原生混沌工程平台 | Kubernetes | 网易开源，Web UI |
| **Gremlin** | 商业混沌工程平台 | 多平台 | 成熟的 SaaS 产品 |
| **AWS Fault Injection Simulator** | AWS 原生 | AWS | 与 AWS 原生集成 |
| **Chaos Toolkit** | 供应商无关的混沌实验框架 | 多平台 | 插件化 |
| **Toxiproxy** | 代理层故障注入 | 应用层 | 轻量，专注网络故障 |
| **Netflix Chaos Monkey** | 随机终止虚拟机 | AWS | 云原生先驱 |

### 4.2 GCP/GKE 专用工具

| 工具 | 说明 |
|------|------|
| **GKE Sandbox** | GKE 节点隔离 |
| **Cloud NMI** | Network Middlebox Integration |
| **IAP Test** | 验证 Identity-Aware Proxy 保护 |
| **Cloud Taint Testing** | 模拟节点污染和驱逐 |

### 4.3 工具选型建议

```
Kubernetes 环境：
  → 推荐 LitmusChaos 或 Chaos Mesh（CRD 原生支持）

GCP 多云/混合环境：
  → 推荐 Chaos Toolkit（供应商无关）+ GCP 特制实验

快速验证/轻量级：
  → Toxiproxy（网络层）+ kubectl 手动注入

企业级/SaaS：
  → Gremlin（成熟商业产品）
```

---

## 5. 实施方法论

### 5.1 成熟度模型

```
Level 1: 手动演练（Game Day）
  └─ 团队成员手动触发故障，观察系统响应
  └─ 适合：初始探索、概念验证

Level 2: 脚本化实验
  └─ 用脚本封装故障注入步骤，可重复执行
  └─ 适合：定期演练、CI/CD 集成

Level 3: 自动化闭环
  └─ 实验自动执行、自动验证、自动回滚
  └─ 适合：生产环境持续验证

Level 4: 持续验证（Continuous Verification）
  └─ 例行化实验，SLO/SLI 监控集成
  └─ 适合：SRE 成熟团队
```

### 5.2 实验工作流（Experiment Workflow）

```
┌─────────────────────────────────────────────────────────────┐
│ 1. 定义稳态（Define Steady State）                          │
│    - 选定关键指标：QPS、延迟、错误率、可用性                   │
│    - 建立基准（Baseline）                                    │
└─────────────────────────────┬───────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. 假设（Make Hypothesis）                                  │
│    - "如果注入 X 故障，那么 Y 指标会 Z 变化"                  │
│    - 预期结果：可接受范围 vs 不可接受                          │
└─────────────────────────────┬───────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. 注入故障（Inject Fault）                                 │
│    - 选择故障类型、位置、持续时间                             │
│    - 从小范围开始：1% 流量 → 10% → 50%                       │
└─────────────────────────────┬───────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. 观察系统（Observe System）                               │
│    - 监控系统指标变化                                        │
│    - 检查告警是否触发                                        │
│    - 验证降级策略是否生效                                     │
└─────────────────────────────┬───────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. 分析结果（Analyze）                                      │
│    - 稳态是否被破坏？                                        │
│    - 是否符合假设？                                          │
│    - 是否发现新的弱点？                                       │
└─────────────────────────────┬───────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. 改进（Improve）                                          │
│    - 修复发现的弱点                                          │
│    - 更新监控/告警                                            │
│    - 更新 runbook                                            │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 Game Day 流程模板

```yaml
# Game Day 实验计划模板
experiment:
  name: "Network Partition Test - Zone A to Zone B"
  date: "2026-01-XX"
  participants:
    - SRE On-Call
    - Network Engineer
    - Application Owner

  steady_state:
    metrics:
      - name: "API P99 Latency"
        baseline: "< 200ms"
      - name: "Error Rate"
        baseline: "< 0.1%"
      - name: "Throughput"
        baseline: "> 1000 RPS"

  hypothesis: |
    "如果 Zone A 和 Zone B 之间的网络中断 30 秒，
    那么跨 Zone 流量会切换到 Zone C，
    P99 延迟会增加 < 50%，错误率 < 1%"

  fault_injection:
    type: "network_partition"
    target: "firewall-rule-zone-a-to-b"
    duration: "30s"

  verification:
    - check: "Cross-zone traffic failover"
      expected: "Traffic routes via Zone C"
    - check: "API latency increase"
      threshold: "< 50% increase"
    - check: "Error rate"
      threshold: "< 1%"

  rollback:
    method: "Remove firewall rule"

  roles:
    facilitator: "SRE Lead"
    injector: "Network Engineer"
    observer: "Monitoring Team"
```

---

## 6. GCP/GKE 实践

### 6.1 GKE 环境下的故障注入

```bash
# 1. 终止单个 Pod（Chaos 实验起点）
kubectl delete pod <pod-name> -n <namespace>

# 2. 模拟节点不可用（模拟 Zone 中断）
gcloud compute instances stop <instance-name> --zone=<zone>

# 3. 网络延迟注入（使用 tc netem）
# 在节点上执行：
ssh <node> "tc qdisc add dev eth0 root netem delay 100ms"

# 4. 防火墙模拟网络分区
gcloud compute firewall-rules create block-zone-b \
  --deny-ingress \
  --source-tags=zone-a \
  --target-tags=zone-b

# 5. 资源压力测试
kubectl top nodes  # 查看基线
# 使用 stress-ng 或 memhog 模拟资源压力
```

### 6.2 LitmusChaos on GKE 示例

```yaml
# Kubernetes CronJob 定时执行混沌实验
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pod-delete-chaos
  namespace: litmus
spec:
  schedule: "0 2 * * 0"  # 每周日凌晨 2 点
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: litmus-admin
          containers:
          - name: chaos
            image: litmuschaos/ansible-runner:latest
            command: ["/bin/sh", "-c"]
            args:
              - |- 
                ansible-playbook -e "chaos_type=pod_delete" \
                  -e "app_ns=production" \
                  -e "chaos_duration=60" \
                  httpapi.yml
            env:
              - name: "ANSIBLE_VAULT_PASSWORD"
                valueFrom:
                  secretKeyRef:
                    name: chaos-vault
                    key: password
```

### 6.3 验证清单（Post-Chaos Verification）

```markdown
## 实验后必检项

### 系统健康
- [ ] 所有 Pod 处于 Running 状态
- [ ] 没有 Stuck in Pending/Evicted 状态
- [ ] 节点 Ready 状态正常
- [ ] 无 CrashLoopBackOff

### 业务指标
- [ ] QPS 恢复到基线
- [ ] 错误率恢复到 < 0.1%
- [ ] P99 延迟恢复正常
- [ ] 无告警触发（或已 suppress）

### 依赖服务
- [ ] 数据库连接正常
- [ ] 缓存（Redis/Memcached）正常
- [ ] 消息队列无积压
- [ ] 外部 API 依赖正常

### 配置/状态
- [ ] 配置未被意外修改
- [ ] 持久化数据未损坏
- [ ] 备份任务正常运行
```

---

## 7. 持续集成与自动化

### 7.1 在 CI/CD 中集成

```yaml
# .gitlab-ci.yml 示例
stages:
  - test
  - chaos
  - report

chaos_experiment:
  stage: chaos
  image: litmuschaos/chaos-runner:latest
  script:
    - | 
      chaos run experiments/pod-delete.yaml
      chaos run experiments/network-delay.yaml
  only:
    - main
  when: manual

chaos_report:
  stage: report
  script:
    - chaos report --output=chaos-report.json
  artifacts:
    reports:
      junit: chaos-results.xml
```

### 7.2 与 SLO/SLI 集成

```
混沌实验 → 验证 SLO 边界 → 触发 Alert → 验证 Runbook
    ↓
发现弱点 → 修复 → 再次实验 → 验证修复
```

---

## 8. 风险控制与安全

### 8.1 安全原则

```
1. 最小爆炸半径
   - 实验前：检查回滚方案
   - 实验中：实时监控，准备 abort
   - 优先在 staging 环境验证

2. 变更管理
   - Chaos 实验视为变更，需要审批
   - 实验窗口：业务低峰期
   - 通知干系人

3. 数据保护
   - 避免在实验环境操作真实数据
   - 确保备份正常

4. 监控告警隔离
   - 实验期间可能产生告警
   - 提前告知 on-call 团队
   - 设置 experiment tag 过滤
```

### 8.2 紧急中止（Emergency Stop）

```bash
# Chaos 实验中止命令
# LitmusChaos
kubectl delete chaosengine <engine-name> -n <namespace>

# Chaos Mesh
# 通过 Dashboard 或 kubectl：
kubectl delete chaos pod-failure <experiment> -n chaos-mesh

# 手动注入的故障（tc netem）
ssh <node> "tc qdisc del dev eth0 root"

# 防火墙规则
gcloud compute firewall-rules delete block-zone-b --quiet
```

---

## 9. 文档与知识沉淀

### 9.1 必建文档

| 文档 | 内容 | 更新频率 |
|------|------|---------|
| **Chaos Runbook** | 每种故障类型的操作步骤 | 实验后更新 |
| **Experiment Catalog** | 所有已验证的实验清单及结果 | 每月 |
| **Failure Mode Matrix** | 组件 → 故障类型 → 影响 → 缓解措施 | 季度 |
| **Game Day Report** | 每次演练的发现和改进项 | 每次演练后 |

### 9.2 Failure Mode Matrix 示例

| 组件 | 故障模式 | 影响 | 检测方式 | 缓解措施 | 验证状态 |
|------|---------|------|---------|---------|---------|
| API Server | Pod 崩溃 | API 不可用 | 错误率 ↑ | HPA 自动重启 | ✅ |
| Database | 主库宕机 | 写入失败 | Alert | 自动切换到从库 | ⚠️ RTO > 5min |
| Cache | Redis 不可用 | 延迟 ↑ | P99 ↑ | 降级到 DB | ✅ |
| Network | Zone 中断 | 跨 Zone 失败 | 跨 Zone 错误率 ↑ | DNS failover | ❌ 未验证 |

---

## 10. 推荐学习路径

```
入门：
1. Principles of Chaos Engineering — https://principlesofchaos.org/
2. LitmusChaos Quick Start — https://docs.litmuschaos.io/
3. Gremlin Free Tier — 手动实验入门

进阶：
4. Google SRE Book Chapter: Chaos Engineering
5. Chaos Mesh Documentation — https://chaos-mesh.org/
6. 《Chaos Engineering》书籍（Springer）

实践：
7. 在 staging 环境进行第一次 Game Day
8. 加入 LitmusChaos Community
9. 参与 GKE Chaos 实验（Jazone / 沙盒集群）
```

---

## 11. 快速启动清单

```
[ ] 明确稳态指标（至少 3 个可量化指标）
[ ] 建立监控 Dashboard（覆盖关键路径）
[ ] 选择工具（建议从 LitmusChaos 开始）
[ ] 在 staging 环境完成第一次实验
[ ] 记录实验结果和发现
[ ] 制定回滚方案
[ ] 通知团队实验计划
[ ] 复盘改进
```

---

*Document version: 1.0 — Last updated: 2026-05-19*
