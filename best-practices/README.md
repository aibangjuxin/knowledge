# Best Practices 索引 — 全仓导航

> **TL;DR**：本仓库（`~/git/knowledge`）里跟 "Best Practice / 最佳实践" 相关的文档分散在 `gcp/` `cloud/k8s/` `gateway/` `webservice/` `safe/` `linux/` `sre/` `develop/` 等目录。
> 本文是一份**纯导航索引**：按领域分组，列出每篇文档的路径 + 主题，方便「按需定位」，不做内容复述。
>
> **本文件命名遵循仓库标准**：目录索引用 `README.md`（同 `gcp/adr/README.md`、`sre/monitor/README.md`、`ai/docs/README.md`）；条目文件名保持仓库既有的 `kebab-case`（不重命名原文件）。

---

## 目录

- [筛选口径](#筛选口径)
- [一、Best Practice 专文（52 篇）](#一best-practice-专文52-篇)
  - [1. GCP / GKE（19）](#1-gcp--gke19)
  - [2. Kubernetes / 策略治理（7）](#2-kubernetes--策略治理7)
  - [3. Gateway / Nginx / Squid（16）](#3-gateway--nginx--squid16)
  - [4. Docker / 安全 / 交付（3）](#4-docker--安全--交付3)
  - [5. SRE / Linux / DNS（7）](#5-sre--linux--dns7)
- [二、含「最佳实践」章节的重点实践文档（27 篇）](#二含最佳实践章节的重点实践文档27-篇)
- [三、Skills 内置最佳实践参考](#三skills-内置最佳实践参考)
- [四、统计与自检命令](#四统计与自检命令)

---

## 筛选口径

本文收录标准（三选一即入表）：

| 级别 | 判据 | 数量 |
|---|---|---|
| **T1 — 专文** | 文件名含 `best-practice` / `best-practice` | 12 |
| **T1 — 专文** | H1 标题本身就是「最佳实践」主题 | 40 |
| **T2 — 实践文档** | 正文含独立的「最佳实践 / 注意事项与最佳实践」章节 | 27 |

**已排除**：`skills/.{vibe,agents,codebuddy,hermes,kiro,minimax,qoder,qwen,trae}/` 这 9 个 vendor 目录里的同名副本（md5 一致，纯分发副本，见 [§三](#三skills-内置最佳实践参考)）；`.git/`、`docs/` 下的静态 HTML。

---

## 一、Best Practice 专文（52 篇）

### 1. GCP / GKE（19）

| # | 路径 | 主题 |
|---|---|---|
| 1 | [`gcp/asm/node-pool-manage-claude.md`](../gcp/asm/node-pool-manage-claude.md) | GKE Node Pool Management：生产级最佳实践 |
| 2 | [`gcp/asm/istio-context.md`](../gcp/asm/istio-context.md) | Istio Context Path 与 Request Path 一致性最佳实践 |
| 3 | [`gcp/asm/debug-istio.md`](../gcp/asm/debug-istio.md) | Istio 疑难问题 Debug 最佳实践指南 |
| 4 | [`gcp/asm/ServiceEntry.md`](../gcp/asm/ServiceEntry.md) | Istio ServiceEntry 深度探索与最佳实践指南 |
| 5 | [`gcp/asm/asm-last-config.md`](../gcp/asm/asm-last-config.md) | 在已有 Istio Gateway 中引入 Kong Gateway / GKE Gateway 的最佳实践 |
| 6 | [`gcp/cloud-armor/cloud-group.md`](../gcp/cloud-armor/cloud-group.md) | 用 Cloud Armor 地址组管理大规模 IP 列表的最佳实践 |
| 7 | [`gcp/gce/gce-nic-route-image.md`](../gcp/gce/gce-nic-route-image.md) | GCE 多网卡：与网卡名解耦的最佳实践 |
| 8 | [`gcp/logs/cross-project-sharing-logs.md`](../gcp/logs/cross-project-sharing-logs.md) | GCP Cross-Project Log Sharing 最佳实践（Log Scopes vs Sinks） |
| 9 | [`gcp/logs/log-limition.md`](../gcp/logs/log-limition.md) | GCP 日志监控和限制最佳实践 |
| 10 | [`gcp/misc/big-memroy-cpu-analysis.md`](../gcp/misc/big-memroy-cpu-analysis.md) | 大规格 API 在既有 n1-standard-8 节点池上的可行性与最佳实践 |
| 11 | [`gcp/sa/gcp-sa-housekeep.md`](../gcp/sa/gcp-sa-housekeep.md) | Service Account Key Housekeeping：最佳实践与自动化 |
| 12 | [`gcp/terraform/README.md`](../gcp/terraform/README.md) | Terraform GCP 仓库结构 — 最佳实践（目录索引即规范） |
| 13 | [`gcp/terraform/references/2025-best-practices-validation.md`](../gcp/terraform/references/2025-best-practices-validation.md) | GCP Terraform Monorepo Best Practices — 2025/2026 权威校验 |
| 14 | [`gcp/migrate-gcp/crossplane-gcp-family-best-practices.md`](../gcp/migrate-gcp/crossplane-gcp-family-best-practices.md) | Crossplane + GCP Family 最佳实践（仓库 v2 方向文件） |
| 15 | [`gcp/psa-psc/psc-sql-flow-demo/k8s/sql-3307-template.md`](../gcp/psa-psc/psc-sql-flow-demo/k8s/sql-3307-template.md) | Cloud SQL Auth Proxy 平台级 Deploy 模板最佳实践 |
| 16 | [`gcp/ucp/argocd-topics/git-apps/14-rulesets-and-gitapp-gate.md`](../gcp/ucp/argocd-topics/git-apps/14-rulesets-and-gitapp-gate.md) | GitHub Rulesets × GitHub App：合并门禁落地（零基础 → 最佳实践） |
| 17 | [`gcp/gke/docs/multi-tenant-cluster.md`](../gcp/gke/docs/multi-tenant-cluster.md) | 大规模 GKE 管理最佳实践（Meeting Preparation） |
| 18 | [`gcp/gke/docs/Multi-tenant.md`](../gcp/gke/docs/Multi-tenant.md) | 同上（另一份副本） |
| 19 | [`gcp/cloud-run/cloud-run-debug.md`](../gcp/cloud-run/cloud-run-debug.md) | Cloud Run Job 日志缺失问题分析与最佳实践 |

### 2. Kubernetes / 策略治理（7）

| # | 路径 | 主题 |
|---|---|---|
| 1 | [`cloud/k8s/docs/helm-best-practices.md`](../cloud/k8s/docs/helm-best-practices.md) | Helm 实战指南：配置治理与全局变更控制（724 行） |
| 2 | [`cloud/k8s/labels/labels-best-practices.md`](../cloud/k8s/labels/labels-best-practices.md) | Kubernetes 标签（Labels）最佳实践 |
| 3 | [`cloud/k8s/custom-liveness/explore-startprobe/probe-best-practices.md`](../cloud/k8s/custom-liveness/explore-startprobe/probe-best-practices.md) | GKE Explorer：探针配置最佳实践指南（中文） |
| 4 | [`cloud/k8s/custom-liveness/explore-startprobe/probe-best-practices-eng.md`](../cloud/k8s/custom-liveness/explore-startprobe/probe-best-practices-eng.md) | 同上（英文版） |
| 5 | [`cloud/k8s/custom-liveness/explore-startprobe/README.md`](../cloud/k8s/custom-liveness/explore-startprobe/README.md) | Kubernetes 探针配置最佳实践（总入口） |
| 6 | [`cloud/k8s/custom-liveness/user-setting.md`](../cloud/k8s/custom-liveness/user-setting.md) | GKE Pod 探针配置最佳实践指南 |
| 7 | [`OPA-Gatekeeper/docs/gatekeeper-best-practices-resource-mapping.md`](../OPA-Gatekeeper/docs/gatekeeper-best-practices-resource-mapping.md) | Gatekeeper 资源映射指南（GKE + ACK 多集群，764 行） |

### 3. Gateway / Nginx / Squid（16）

| # | 路径 | 主题 |
|---|---|---|
| 1 | [`gateway/no-gateway/no-gateway-design.md`](../gateway/no-gateway/no-gateway-design.md) | API 平台架构最佳实践方案 |
| 2 | [`gateway/no-gateway/no-gateway-2.md`](../gateway/no-gateway/no-gateway-2.md) | GCP 工程 API 接入架构最佳实践分析 |
| 3 | [`gateway/no-gateway/no-gateway-gcp-design-gemini.md`](../gateway/no-gateway/no-gateway-gcp-design-gemini.md) | API 平台架构最佳实践方案（Gemini 版） |
| 4 | [`gateway/no-gateway/no-gateway-path-explorer.md`](../gateway/no-gateway/no-gateway-path-explorer.md) | API 版本管理最佳实践分析 |
| 5 | [`gateway/no-gateway/version-control/no-gateway-version-ingress-control.md`](../gateway/no-gateway/version-control/no-gateway-version-ingress-control.md) | Ingress Controller 平滑版本切换与重写最佳实践 |
| 6 | [`gateway/no-gateway/version-control/no-gateway-version-smoth-switch.md`](../gateway/no-gateway/version-control/no-gateway-version-smoth-switch.md) | GKE Gateway API 平滑版本切换与验证最佳实践 |
| 7 | [`gateway/no-gateway/version-control/no-gateway-version-smoth-switch-en.md`](../gateway/no-gateway/version-control/no-gateway-version-smoth-switch-en.md) | 同上（英文版） |
| 8 | [`webservice/nginx/docs/hsts-best-practices.md`](../webservice/nginx/docs/hsts-best-practices.md) | HSTS Best Practices for Multi-Layer Architectures（多层级避免重复头） |
| 9 | [`webservice/nginx/docs/Strict-Transport-Security.md`](../webservice/nginx/docs/Strict-Transport-Security.md) | Strict-Transport-Security (HSTS) Best Practices |
| 10 | [`webservice/nginx/docs/nginx-conf.md`](../webservice/nginx/docs/nginx-conf.md) | Nginx 配置最佳实践 |
| 11 | [`webservice/nginx/docs/proxy-pass/nginx-proxy-forwarded-proto.md`](../webservice/nginx/docs/proxy-pass/nginx-proxy-forwarded-proto.md) | Nginx `X-Forwarded-Proto` 深度探索与最佳实践 |
| 12 | [`webservice/nginx/docs/proxy-pass/nginx+istio.md`](../webservice/nginx/docs/proxy-pass/nginx+istio.md) | Nginx 7 层代理 — Team 级配置最佳实践分析 |
| 13 | [`webservice/nginx/docs/nginx-Reuse-confd.md`](../webservice/nginx/docs/nginx-Reuse-confd.md) | 统一配置管理与最佳实践 |
| 14 | [`webservice/nginx/nginx-logs/nginx-logrotate-best-practice-limited-disk.md`](../webservice/nginx/nginx-logs/nginx-logrotate-best-practice-limited-disk.md) | 磁盘空间受限环境下的 Nginx Logrotate 最佳实践 |
| 15 | [`webservice/squid/docs/squid-deploy-claude.md`](../webservice/squid/docs/squid-deploy-claude.md) | Squid 多配置部署最佳实践 |
| 16 | [`webservice/squid/docs/squid-as-https-proxy.md`](../webservice/squid/docs/squid-as-https-proxy.md) | Squid 作为 HTTPS 代理的生产环境最佳实践 |

### 4. Docker / 安全 / 交付（3）

| # | 路径 | 主题 |
|---|---|---|
| 1 | [`cloud/docker/byoc/best-practices.md`](../cloud/docker/byoc/best-practices.md) | BYOC Best Practices（分层：必做 → 强烈建议 → 进阶） |
| 2 | [`safe/ssl/cross-project-fqdn-best-practices.md`](../safe/ssl/cross-project-fqdn-best-practices.md) | Cross-Project FQDN Best Practices（跨项目 FQDN / SNI / SAN 边界） |
| 3 | [`safe/docs/pipeline-script.md`](../safe/docs/pipeline-script.md) | 构建安全、可扩展的 GCP 部署：超越脚本的最佳实践框架 |

### 5. SRE / Linux / DNS（7）

| # | 路径 | 主题 |
|---|---|---|
| 1 | [`sre/shell-lib-testing-best-practices.md`](../sre/shell-lib-testing-best-practices.md) | Shell Lib 复用与 Shell 测试最佳实践（bats-core 选型） |
| 2 | [`linux/docs/Linux-start-services.md`](../linux/docs/Linux-start-services.md) | Linux 服务启动顺序与依赖管理最佳实践 |
| 3 | [`linux/docs/limit.md`](../linux/docs/limit.md) | Linux 文件描述符限制与 Nginx 最佳实践 |
| 4 | [`linux/docs/explorer-sse-streamable.md`](../linux/docs/explorer-sse-streamable.md) | 探索 SSE 与 Streamable HTTP：AI 实时响应的最佳实践 |
| 5 | [`linux/dns/dns-cache-ttl-with-fqdn.md`](../linux/dns/dns-cache-ttl-with-fqdn.md) | GKE Java Pod 外部域名 DNS 解析 — Cache + FQDN 最佳实践 |
| 6 | [`linux/dns/dns-peering/ip-choose.md`](../linux/dns/dns-peering/ip-choose.md) | FQDN 出口模式选择最佳实践（Public vs Private） |
| 7 | [`linux/dns/docs/dns-peerning.md`](../linux/dns/docs/dns-peerning.md) | DNS Peering 最佳实践 |

---

## 二、含「最佳实践」章节的重点实践文档（27 篇）

> 这些不是通篇讲最佳实践，而是**某个章节**是最佳实践清单；按需查阅时从对应章节进。

### 容器 / Kubernetes

| 路径 | 最佳实践所在章节 |
|---|---|
| [`cloud/docker/multistage-builds/Dockerfile.md`](../cloud/docker/multistage-builds/Dockerfile.md) | 5. 注意事项与最佳实践 |
| [`cloud/docker/docs/Dockeffile-user-pass-violation.md`](../cloud/docker/docs/Dockeffile-user-pass-violation.md) | Dockerfile 安全与最佳实践违规 |
| [`cloud/k8s/docs/liveless-simple.md`](../cloud/k8s/docs/liveless-simple.md) | 针对平台的最佳实践（最终答案） |
| [`cloud/k8s/images/k8s-img-replace.md`](../cloud/k8s/images/k8s-img-replace.md) | 注意事项 & 最佳实践 |
| [`cloud/k8s/labels/metadata-labels.md`](../cloud/k8s/labels/metadata-labels.md) | 最佳实践总结（专家级回答） |
| [`cloud/k8s/networkpolicy/network-ns-ns.md`](../cloud/k8s/networkpolicy/network-ns-ns.md) | 最佳实践做法：namespaceSelector + podSelector |

### Gateway / API

| 路径 | 最佳实践所在章节 |
|---|---|
| [`gateway/kong/docs/kong-auth-group.md`](../gateway/kong/docs/kong-auth-group.md) | 注意事项 & 最佳实践 |
| [`gateway/kong/docs/migrate-kong.md`](../gateway/kong/docs/migrate-kong.md) | 6. 注意事项与最佳实践 |
| [`gateway/no-gateway/HealthCheckPolicy.md`](../gateway/no-gateway/HealthCheckPolicy.md) | 6. 注意事项 & 最佳实践 |
| [`gateway/no-gateway/merged-scripts.md`](../gateway/no-gateway/merged-scripts.md) | 多实现合并的 best practices v3.0 |

### GCP 服务

| 路径 | 最佳实践所在章节 |
|---|---|
| [`gcp/gce/gcp-network.md`](../gcp/gce/gcp-network.md) | 注意事项与最佳实践 |
| [`gcp/glb/glb-retry-timeout.md`](../gcp/glb/glb-retry-timeout.md) | 七、最佳实践（生产级） |
| [`gcp/pub-sub/pub-sub-queue-command.md`](../gcp/pub-sub/pub-sub-queue-command.md) | 创建具有最佳实践配置的 Subscription |
| [`gcp/pub-sub/StreamingPull.md`](../gcp/pub-sub/StreamingPull.md) | 5. 最佳实践建议 |
| [`gcp/cloud-run/schedule-job-trigger-cloud-run.md`](../gcp/cloud-run/schedule-job-trigger-cloud-run.md) | 2. 创建仅含运行作业权限的自定义角色 |
| [`gcp/dashboard/report/docs/special-case-data.md`](../gcp/dashboard/report/docs/special-case-data.md) | 为什么「直接在 Python 里绕过」不是最佳实践 |

### 安全 / SRE / 开发

| 路径 | 最佳实践所在章节 |
|---|---|
| [`safe/gcp-safe/key-keyring.md`](../safe/gcp-safe/key-keyring.md) | 注意事项与最佳实践 |
| [`safe/cyberflows/dast.md`](../safe/cyberflows/dast.md) | 高级主题与 DAST 项目成熟度最佳实践 |
| [`safe/ssl/docs/claude/map/glb-url-map-implementation.md`](../safe/ssl/docs/claude/map/glb-url-map-implementation.md) | 安全最佳实践：空 Backend Service + Cloud Armor deny-all |
| [`sre/docs/flow-debug.md`](../sre/docs/flow-debug.md) | 注意事项（Operations / 安全 / 最佳实践） |
| [`sre/monitor/docs/monitor-egress-proxy.md`](../sre/monitor/docs/monitor-egress-proxy.md) | cache_peer 监控的细化实现与最佳实践 |
| [`concept/api-service/docs/api-ChatGPT.md`](../concept/api-service/docs/api-ChatGPT.md) | 注意事项与最佳实践 |
| [`develop/npm/install.md`](../develop/npm/install.md) | 总结（最佳实践） |
| [`linux/dns/docs/apply-cname.md`](../linux/dns/docs/apply-cname.md) | 九、企业最佳实践总结 |
| [`linux/docs/Docker-bash.md`](../linux/docs/Docker-bash.md) | 注意事项与最佳实践 |
| [`linux/docs/nc.md`](../linux/docs/nc.md) | GKE Debug Pod 中使用 netcat（nc）的最佳实践 |
| [`linux/dns/docs/apply-wirdcard-cert.md`](../linux/dns/docs/apply-wirdcard-cert.md) | 五、企业 DNS / 证书最佳实践（非常重要） |

---

## 三、Skills 内置最佳实践参考

### 3.1 vendor 副本（同一份内容，9 处分发）

`skills/` 下 9 个 vendor 目录各自带有同名副本，**内容 md5 一致**，只保留一个代表即可：

| 代表路径 | 主题 | 副本位置 |
|---|---|---|
| [`skills/.vibe/skills/developing-genkit-js/references/best-practices.md`](../skills/.vibe/skills/developing-genkit-js/references/best-practices.md) | Genkit Best Practices（工程结构 / 模型选择 / 工具设计） | `.agents` `.codebuddy` `.hermes` `.kiro` `.minimax` `.qoder` `.qwen` `.trae` |
| [`skills/.vibe/skills/google-cloud-solution-architecture/references/best-practices-guides.md`](../skills/.vibe/skills/google-cloud-solution-architecture/references/best-practices-guides.md) | Product-specific best practices guides（按产品索引行号） | 同上 8 处 |
| [`skills/.vibe/skills/workload-manager-basics/references/general-best-practices.md`](../skills/.vibe/skills/workload-manager-basics/references/general-best-practices.md) | Workload Manager General Best Practices（云安全 / FinOps / 可靠性姿态） | 同上 8 处 |

### 3.2 GKE Golden Path 系列（`skills/gke-basics/references/`）

> 这套是 **GKE 平台最佳实践的模板化实现**，按领域拆分，定位时优先从这里找：

[`gke-golden-path.md`](../skills/gke-basics/references/gke-golden-path.md) · [`gke-security.md`](../skills/gke-basics/references/gke-security.md) · [`gke-networking.md`](../skills/gke-basics/references/gke-networking.md) · [`gke-reliability.md`](../skills/gke-basics/references/gke-reliability.md) · [`gke-multitenancy.md`](../skills/gke-basics/references/gke-multitenancy.md) · [`gke-scaling.md`](../skills/gke-basics/references/gke-scaling.md) · [`gke-observability.md`](../skills/gke-basics/references/gke-observability.md) · [`gke-cost.md`](../skills/gke-basics/references/gke-cost.md) · [`gke-storage.md`](../skills/gke-basics/references/gke-storage.md) · [`gke-backup-dr.md`](../skills/gke-basics/references/gke-backup-dr.md) · [`gke-upgrades.md`](../skills/gke-basics/references/gke-upgrades.md) · [`gke-cluster-creation.md`](../skills/gke-basics/references/gke-cluster-creation.md) · [`gke-app-onboarding.md`](../skills/gke-basics/references/gke-app-onboarding.md) · [`gke-inference.md`](../skills/gke-basics/references/gke-inference.md) · [`gke-compute-classes.md`](../skills/gke-basics/references/gke-compute-classes.md) · [`gke-batch-hpc.md`](../skills/gke-basics/references/gke-batch-hpc.md) · [`iac-usage.md`](../skills/gke-basics/references/iac-usage.md) · [`core-concepts.md`](../skills/gke-basics/references/core-concepts.md) · [`cli-reference.md`](../skills/gke-basics/references/cli-reference.md) · [`client-library-usage.md`](../skills/gke-basics/references/client-library-usage.md) · [`mcp-usage.md`](../skills/gke-basics/references/mcp-usage.md)

### 3.3 治理类 Skill

| 路径 | 主题 |
|---|---|
| [`skills/gcp/gatekeeper-multi-tenant-governance/SKILL.md`](../skills/gcp/gatekeeper-multi-tenant-governance/SKILL.md) | Gatekeeper Multi-Tenant Governance — 多租户治理最佳实践 |

---

## 四、统计与自检命令

**按文件名全仓过滤**（最直接，可复用于新增文档后自检）：

```bash
cd ~/git/knowledge
# 文件名含 best-practice / best practice
find . -type f -name "*.md" -not -path "./.git/*" \
  | grep -iE "best[-_ ]?pract" | sort

# 标题含「最佳实践 / Best Practice」（排除 vendor 副本与隐藏 agent 目录）
for f in $(find . -name "*.md" -not -path "./.git/*" \
           -not -path "./skills/.*" -not -path "*/.claude/*" \
           -not -path "*/.kilo/*" -not -path "*/.agent/*"); do
  grep -qE '^# .*(最佳实践|[Bb]est.?[Pp]ractice)' "$f" && echo "$f"
done | sort
```

**分布概览**（按一级目录）：

| 一级目录 | T1 专文 | T2 实践文档 | 说明 |
|---|---|---|---|
| `gcp/` | 19 | 6 | 最密集 — GCP 服务与平台工程 |
| `webservice/` | 9 | 0 | Nginx / Squid 运行时调优 |
| `gateway/` | 7 | 4 | API 平台架构与版本切换 |
| `cloud/`（k8s + docker） | 7 | 6 | 工作负载 / 探针 / 标签 / 镜像 |
| `linux/` | 6 | 4 | 主机 / DNS / 协议层 |
| `safe/` | 2 | 3 | SSL / 合规 / DAST |
| `sre/` | 1 | 2 | Shell 测试与监控 |
| `OPA-Gatekeeper/` | 1 | 0 | 策略治理 |
| `develop/` | 0 | 1 | 依赖与 API 约定 |
| `concept/` | 0 | 1 | API 服务设计 |
| **合计** | **52** | **27** | — |

---

## 维护提示

1. **新增最佳实践文档时**，把文件放在其**领域目录**内（本索引不搬家文件），文件名沿用 `*-best-practices.md` 或在 H1 写明「最佳实践」，然后在本文件补一行。
2. **发现某文档最佳实践章节升级为专文**时，从 §二 移到 §一。
3. 本索引由扫描生成，**新增文档后重跑 §四 命令核对**。
4. 提交前按仓库约定走脱敏闸门（`scripts/sanitize-check.sh --staged`），索引里不要引入真实资源标识。
