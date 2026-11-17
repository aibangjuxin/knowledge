---
name: ple-environment-design
description: PLE (Production-Like Environment) 隔离架构设计。当需要设计 PLE 环境、分析 PRD 与 non-PRD 隔离方案、评估网络架构、控制多环境访问风险时使用。涵盖：隔离层次分析、攻击路径识别、GCP 原生隔离控制（Org Policy/Firewall/IAM）、合规要求评估。
triggers:
  - "PLE"
  - "Production-Like Environment"
  - "测试环境隔离"
  - "PRD 隔离"
  - "non-PRD 环境"
  - "环境隔离架构"
  - "多租户隔离"
---

# PLE (Production-Like Environment) 隔离架构设计

## 核心矛盾

```
"使用 PRD 网络基础设施" + "与 PRD 完全隔离" = 逻辑上矛盾

正确理解：
  → 复用网络架构设计（拓扑、规划、命名规范）
  → 但使用独立的网络资源（VPC、Subnet、IP）
```

## 5 层隔离金字塔

```
           L7: 应用层（API Gateway, Auth）
          /█\
         / █ \       ← 应用层被攻破，网络层无防护
        /───█───\
       /    █    \    L4: 网络层（Firewall, VPC, Route）
      /     █     \   ← 必要但不充分
     /──────█──────\
    /       █       \  L3: IAM（SA, RBAC）
   /        █        \ ← 权限配置错误即失效
  /─────────█─────────\
 /          █          \L2: 数据层（Secret, KMS, DB）
/                      \  ← 可独立保证隔离
```

## 攻击路径矩阵

| 攻击路径 | 说明 | 缓解措施 |
|---------|------|---------|
| DNS 劫持 | 控制 DNS 解析指向 PRD | DNS Policy + 解析验证 |
| 内网横向移动 | Firewall 规则配置错误 | 严格 Firewall Policy（含 egress） |
| 服务发现冒充 | K8s API 冒充 | Workload Identity 隔离 |
| 元数据服务 | 获取 SA token | Metadata IP 限制 |
| 共享存储 | GCS Bucket 权限过大 | Bucket Policy 最小化 |

## GCP 原生隔离控制

### 1. Organization Policy

```yaml
orgPolicies:
  # 禁止跨 Project Service Account 使用
  - name: "disable-cross-project-service-account"
  # 强制 PLE SA 不能有 PRD 资源访问权限
  - name: "allowed-service-accounts"
```

### 2. VPC Firewall（关键： egress 也要控制）

```yaml
firewall_rules:
  # 拒绝所有来自 PRD 的流量
  - name: "deny-from-prd"
    direction: INGRESS
    priority: 100
    sourceRanges: ["10.0.0.0/16"]  # PRD VPC CIDR
    action: DENY
    logConfig: { enabled: true }  # 所有拒绝流量必须记录

  # 拒绝所有出站到 PRD
  - name: "deny-to-prd"
    direction: EGRESS
    priority: 100
    destinationRanges: ["10.0.0.0/16"]
    action: DENY
    logConfig: { enabled: true }
```

**⚠️ 注意：GCP Firewall 是 Stateful！ egress 不控制则 ingress 响应流量会自动放行**

### 3. IAM Conditional

```yaml
- role: roles/compute.admin
  members: ["serviceAccount:ple-sa@project-ple.iam.gserviceaccount.com"]
  condition:
    title: "只允许在 PLE Project 操作"
    expression: "resource.name.startsWith('projects/project-ple-xxx')"
```

## 推荐架构

```
PRD Project (project-prd)          PLE Project (project-ple)
┌─────────────────┐               ┌─────────────────┐
│  VPC: vpc-prd  │   ✖ 隔离      │  VPC: vpc-ple  │
│  SA: sa-prd-xxx│               │  SA: sa-ple-xxx│
│  GCS: prd-bucket│              │  GCS: ple-bucket│
└─────────────────┘               └─────────────────┘
        ↑                                  ↑
        └────── Shared VPC Host (统一规划) ─┘
               (复用网络拓扑，不复用流量)
```

## 澄清问题清单

```
Q1: PLE 的目的是什么？（功能/性能/安全测试/UAT）
Q2: PLE 用户需要访问哪些 PRD 资源？
Q3: PLE 是否需要"像 PRD"（用于 UAT）？
Q4: 合规要求是什么？（等保/PCI-DSS/SOC2）
Q5: PLE 的预算和运维责任是谁？
```

## 验证清单

```
□ PLE VM 不能 ping PRD VM
□ PLE egress 到 PRD CIDR 被 firewall 拒绝
□ PLE SA 不能列出 PRD Project 资源
□ PLE 不能访问 PRD GCS Bucket
□ Firewall 日志中有预期的 DENY 记录
□ 审计日志完整可追溯
```

## 相关文档

- `knowledge/develop/develop-process/test/docs/ple.md` — PLE 隔离架构深度分析（完整版）
- `knowledge/webservice/nginx/nginx-cert/nginx-cert-dynamic-update.md` — Nginx 动态证书更新
- `knowledge/develop/develop-process/test/docs/destructive-testing-infra.md` — 破坏性测试指南
