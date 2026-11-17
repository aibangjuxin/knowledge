# Cost 知识库

## 目录描述
本目录包含云服务成本管理、优化和分析相关的知识。

## 目录结构
```
cost/
├── cross-project-public-tls-mtls-billing.md   # 跨 Project × Public TLS/mTLS 计费深度分析(通用原则)
├── fetch-gcp-pricing.sh                        # Cloud Billing Catalog API 实时定价拉取脚本
├── gcp-cost/                                   # Google Cloud Platform 成本管理相关内容
│   ├── gcp-log-cost.md                         # Cloud Logging 成本优化详细指南
│   └── ...
├── cost-sql.md                                 # SQL 类成本
├── collect-information.md
├── gke-cost-allocations.md                     # GKE 资源成本分配
├── gke_cluster_resource_consumption.md
├── gke_cluster_resource_usage.md
├── one-off-design.md
└── README.md                                   # 本说明文件
```

## 文件说明

| 文件 | 用途 |
|---|---|
| `cross-project-public-tls-mtls-billing.md` | **跨 Project × Public TLS/mTLS 服务暴露的计费原则** — 13 章深度分析:Forwarding Rules / Envoy / PSC / Cloud Logging / Egress / Cloud Armor 各自计费规则 + 长期月费估算模型 + 决策矩阵 |
| `fetch-gcp-pricing.sh` | **Cloud Billing Catalog API 实时定价拉取脚本** — 跑出 `/tmp/gcp-network-skus.json`,直接读出当前 LB / PSC / Proxy / Egress 实际小时费 / GB 费 |
| `gcp-cost/` | Cloud Logging / 桶归档 / Audit Log 等成本子目录 |
| `cost-sql.md` | SQL 类(BigQuery / Cloud SQL)成本 |
| `gke-cost-allocations.md` | GKE 节点 / 资源成本归因 |
| `one-off-design.md` | 一次性设计成本(项目启动 / 数据迁移) |

## 快速检索

| 你想解决的问题 | 看哪份 |
|---|---|
| "如果我的工程是跨 project + Public TLS/mTLS,会产生哪些费用?" | `cross-project-public-tls-mtls-billing.md`(13 章覆盖) |
| "我想拿到现在的 GCP LB / PSC 实际小时费" | 跑 `./fetch-gcp-pricing.sh` |
| "我的 Cloud Logging 账单暴增,怎么优化?" | `gcp-cost/gcp-log-cost.md` |
| "GKE 集群成本怎么拆到 namespace / team?" | `gke-cost-allocations.md` |
| "PSC vs VPC Peering 哪个更划算?" | `psa-psc/psc-with-vpc-peering-quota-cost.md`(同仓库,不在本目录) |
| "我的 LB 链 / Cloud Armor 怎么暂停减少费用?" | `/Users/lex/git/gcp/cost/`(工程脚本,不在本仓库) |

## 阅读路径推荐

1. **新手**: 先读 `cross-project-public-tls-mtls-billing.md` §0 TL;DR + §1 资源模型与计费归属,建立全局观
2. **遇到具体账单疑问**: 跳到对应章节(Forwarding Rules / Envoy / Logging / PSC...)
3. **做生产决策**: 跑 `fetch-gcp-pricing.sh` 拿最新数字,替换 `[std]` 标记的值
4. **优化已运行工程**: §10 决策矩阵 + §13 后续方向