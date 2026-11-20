# Summary or Background

- This markdown records my workspace verification information and scripts.
- It is a generated index of every `*.sh` verification script and `*.md` knowledge document in this repository, grouped by topic.
- Regenerate it with `python3 bin/gen-verify-search.py` — the script adds new files, drops deleted ones and refreshes `Last Updated`.
- Scope: tracked plus untracked-but-not-ignored files, excluding `skills/` (agent skill bundles), hidden directories and the index itself.

# Verify Scripts Search Results
**Last Updated:** 2026-11-20

## Shell Scripts (`.sh`)

### Ali Cloud Scripts

| File Path | Description |
| :--- | :--- |
| `cloud/ali/ali-dns/dns-batch-update.sh` | DNS Batch Update Script |
| `cloud/ali/ali-dns/dns-config.sh` | DNS Configuration File |
| `cloud/ali/k8s-migration-proxy/deploy.sh` | K8s Cluster Migration Proxy Deployment Script |
| `cloud/ali/k8s-migration-proxy/scripts/deploy-external-services.sh` | Deployment script for ExternalName services in K8s cluster migration |
| `cloud/ali/k8s-migration-proxy/scripts/manage-ingress.sh` | Ingress Management Script for K8s Cluster Migration |
| `cloud/ali/k8s-migration-proxy/scripts/test-ingress.sh` | Test Script for Ingress Configuration Implementation |
| `cloud/ali/k8s-migration-proxy/scripts/verify-connectivity.sh` | Network Connectivity Verification Script for K8s Cluster Migration |
| `cloud/ali/k8s-migration-proxy/test-proxy.sh` | Test script for migration proxy functionality |
| `cloud/ali/k8s-migration-proxy/validate.sh` | Validation script for K8s Migration Proxy Infrastructure |
| `cloud/ali/migrate-plan/plan1/k8s-ingress-migration-optimized.sh` | k8s-ingress-migration-optimized.sh |
| `cloud/ali/migrate-plan/plan1/poc-rewrite/migrate-commands.sh` | K8s集群迁移命令集合 |
| `cloud/ali/migrate-plan/plan1/poc-rewrite/poc-test.sh` | POC验证脚本 |
| `cloud/ali/migrate-plan/plan1/poc-rewrite/quick-migrate.sh` | 一键迁移脚本 |
| `cloud/ali/scripts/k8s-resources.sh` | Kubernetes Resources Script - Get CPU and Memory limits/requests for Deployments |
| `cloud/ali/scripts/migrate-exclude-secret.sh` | migrate-secrets.sh - Kubernetes Secrets 迁移脚本 |
| `cloud/ali/scripts/namespace-status.sh` | Kubernetes Namespace Status Check Script |
| `cloud/ali/scripts/verify-e2e.sh` | E2E Verification Script for Kubernetes Resources |
| `cloud/ali/secrets-backup/lex/apply-secrets.sh` | 应用导出的 secrets 到目标集群 |

### Docker/Container Scripts

| File Path | Description |
| :--- | :--- |
| `cloud/docker/scripts/debug-java-pod.sh` | 自动创建带 Sidecar 的调试 Deployment 用于分析无法启动的 Java 应用镜像 |

### K8s Pod/Health Check Scripts

| File Path | Description |
| :--- | :--- |
| `cloud/k8s/Mytools/aliases.sh` | 自定义别名配置文件 |
| `cloud/k8s/Mytools/example-custom.sh` | 示例自定义配置文件 |
| `cloud/k8s/Mytools/init.sh` | Kali Linux 容器环境初始化脚本 |
| `cloud/k8s/Mytools/mount-config-template.sh` | 挂载配置模板脚本 |
| `cloud/k8s/Mytools/run-container.sh` | Kali Linux 容器启动脚本 |
| `cloud/k8s/custom-liveness/build-custom-image.sh` | Build Custom Image |
| `cloud/k8s/custom-liveness/deploy-and-test.sh` | Deploy And Test |
| `cloud/k8s/custom-liveness/deploy-and-verify.sh` | Deploy And Verify |
| `cloud/k8s/custom-liveness/explore-startprobe/get-deploy-health-url.sh` | Get Deploy Health Url |
| `cloud/k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhance.sh` | 设置颜色输出 |
| `cloud/k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_gemini.sh` | Pod Measure Startup Enhanced Gemini |
| `cloud/k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v2.sh` | Pod Measure Startup Enhanced V2 |
| `cloud/k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v3.sh` | Pod Measure Startup Enhanced V3 |
| `cloud/k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v4.sh` | Pod Measure Startup Enhanced V4 |
| `cloud/k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v5.sh` | Pod Measure Startup Enhanced V5 |
| `cloud/k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v6.sh` | Pod Measure Startup Enhanced V6 |
| `cloud/k8s/custom-liveness/explore-startprobe/pod_measure_startup_fixed_en.sh` | Set color output |
| `cloud/k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup.sh` | Set color output |
| `cloud/k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup_fixed.sh` | 设置颜色输出 |
| `cloud/k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup_fixed_en.sh` | Set color output |
| `cloud/k8s/debug-pod/side-optimized.sh` | 优化版本的 GKE Ephemeral Container Debug 脚本 |
| `cloud/k8s/debug-pod/test-script.sh` | 测试脚本 - 验证优化版本的功能 |
| `cloud/k8s/images/images-update.sh` | Kubernetes Deployment Image Updater |
| `cloud/k8s/images/k8s-image-replace.sh` | k8s-image-replace.sh |
| `cloud/k8s/images/verify_pod_image_pull_time.sh` | Verify Pod Image Pull Time |
| `cloud/k8s/images/verify_pod_image_pull_time_sh.sh` | Verify Pod Image Pull Time Sh |
| `cloud/k8s/k8s-gateway/k8s-gateway-e2e/k8s-gateway-fqdn-chatgpt.sh` | K8s Gateway FQDN Resource Explorer and E2E URL Builder |
| `cloud/k8s/k8s-gateway/k8s-gateway-e2e/k8s-gateway-fqdn-claude.sh` | k8s-gateway-fqdn-claude.sh |
| `cloud/k8s/k8s-gateway/k8s-gateway-e2e/k8s-gateway-fqdn-gemini.sh` | k8s-gateway-fqdn-gemini.sh — 智能 K8s Gateway 域名链路深度探索与 E2E URL 构建器 |
| `cloud/k8s/k8s-gateway/k8s-gateway-e2e/k8s-gateway-fqdn-minimax-eng.sh` | Given an Ingress domain (FQDN), auto-traverse the K8s Gateway API core chain: |
| `cloud/k8s/k8s-gateway/k8s-gateway-e2e/k8s-gateway-fqdn-minimax.sh` | k8s-gateway-fqdn-minimax.sh — K8s Gateway FQDN 链路深度探索 & E2E URL 构建器 |
| `cloud/k8s/k8s-gateway/k8s-gateway-e2e/k8s-gateway-fqdn.sh` | K8s Gateway FQDN Resource Explorer & URL Builder |
| `cloud/k8s/k8s-gateway/k8s-gateway-e2e/k8s-gateway-verify.sh` | K8s Gateway E2E Verification Suite |
| `cloud/k8s/k8s-scale/optimize_k8s_resources.sh` | Default values |
| `cloud/k8s/k8s-scale/optimize_k8s_resources_v2.sh` | Analyze and optimize resource usage by scaling down unhealthy deployments |
| `cloud/k8s/labels/add-deployment-labels-flexible.sh` | Script purpose: Add labels to specified deployments |
| `cloud/k8s/labels/add-deployment-labels.sh` | 脚本用途：给指定的 deployment 添加 labels，使其 pod 能够访问特定 namespace 的服务 |
| `cloud/k8s/labels/add/01_export_data.sh` | Export data from BigQuery or generate dummy data for testing. |
| `cloud/k8s/labels/add/02_generate_mapping.sh` | Convert raw list data to key-value mapping for fast lookup. |
| `cloud/k8s/labels/add/03_backup.sh` | Backup all deployments in all namespaces before making changes. |
| `cloud/k8s/labels/add/04_apply_labels.sh` | Iterate through deployments, match with mapping, and apply labels. |
| `cloud/k8s/labels/add/05_verify.sh` | Verify that labels were correctly applied to deployments. |
| `cloud/k8s/labels/add/06_rollback.sh` | Rollback changes by restoring from backup. |
| `cloud/k8s/labels/deployment-helper.sh` | 辅助脚本：查看 deployment 状态和手动重启 |
| `cloud/k8s/labels/flexible.sh` | 脚本用途：给指定的 deployment 添加 labels |
| `cloud/k8s/lib/pod_health_check_lib.sh` | pod_health_check_lib.sh - Kubernetes Pod Health Check Function Library |
| `cloud/k8s/lib/test_lib.sh` | Test script for pod_health_check_lib.sh |
| `cloud/k8s/qnap-k8s/ init-k8s.sh` |  init K8S |
| `cloud/k8s/qnap-k8s/install-k8s-deps.sh` | 不要使用 set -e，因为 QNAP 系统可能有一些非标准的配置文件 |
| `cloud/k8s/qnap-k8s/test-qnap-detection.sh` | QNAP 系统检测测试脚本 |
| `cloud/k8s/scripts/batch_health_check.sh` | Batch Health Check Script for Multiple Pods |
| `cloud/k8s/scripts/debug_health_check.sh` | Debug script to test health check |
| `cloud/k8s/scripts/git.sh` | Git |
| `cloud/k8s/scripts/measure_startup_simple.sh` | Simple Pod Startup Time Measurement Script |
| `cloud/k8s/scripts/minimal_test.sh` | Minimal test - exactly like original script |
| `cloud/k8s/scripts/pod-system-version.sh` | 脚本名称: check-pod-versions-concurrent.sh |
| `cloud/k8s/scripts/pod_exec.sh` | Set color output |
| `cloud/k8s/scripts/pod_measure_startup_bak.sh` | 设置颜色输出 |
| `cloud/k8s/scripts/pod_measure_startup_fixed.sh` | 设置颜色输出 |
| `cloud/k8s/scripts/pod_status.sh` | 设置颜色输出 |
| `cloud/k8s/scripts/simple_test.sh` | Simple test to verify Pod health check works |

### CI/CD Pipeline Scripts

| File Path | Description |
| :--- | :--- |
| `develop/pipeline/cd-pipeline/scripts/render-and-apply.sh` | Render And Apply |
| `develop/pipeline/cd-pipeline/scripts/sync-image.sh` | Sync Image |

### Java/Debug Scripts

| File Path | Description |
| :--- | :--- |
| `develop/java/java-auth/simple-https-demo/generate-cert.sh` | Generate Self-Signed Certificate for HTTPS Server (Port 8443) |
| `develop/java/java-pom/ci-diagnostic-script.sh` | CI 环境依赖问题诊断脚本 |
| `develop/java/java-scan/scripts/pipeline-integration.sh` | CI/CD Pipeline 集成脚本 |
| `develop/java/java-timeout/run.sh` | Timeout API Runner Script |
| `develop/java/scripts/debug-java-pod.sh` | 自动创建带 Sidecar 的调试 Deployment 用于分析无法启动的 Java 应用镜像 |
| `develop/java/scripts/debug-pod.sh` | Debug Pod |
| `develop/java/scripts/test-dry-run.sh` | Simulate the dry-run output |

### Develop Tool Scripts

| File Path | Description |
| :--- | :--- |
| `develop/React/scripts/build.sh` | Build script for React Docker application |
| `develop/React/scripts/deploy.sh` | Deploy script for Kubernetes |
| `develop/develop-process/test/dr-instance/dr-instance.sh` | Replace the following variables with your own values |
| `develop/develop-process/test/dr-instance/gce-dr-validation.sh` | GCE DR Validation Script |
| `develop/develop-process/test/dr-instance/run-dr-test.sh` | Simple wrapper script to run DR validation with configuration |
| `develop/go/scripts/cert-management.sh` | 平台证书管理脚本 |
| `develop/go/scripts/configmap-management.sh` | 平台 ConfigMap 管理脚本 |
| `develop/go/scripts/convert-cert.sh` | 证书格式转换脚本 |
| `develop/go/scripts/test-local.sh` | 本地测试脚本 |
| `develop/groovy/scripts/git.sh` | Git |
| `develop/node/scripts/cert-management.sh` | 平台证书管理脚本 - Node.js 版本 |
| `develop/node/scripts/configmap-management.sh` | 平台 ConfigMap 管理脚本 - Node.js 版本 |
| `develop/node/scripts/convert-cert.sh` | 证书格式转换脚本 |
| `develop/node/scripts/test-local.sh` | 本地测试脚本 |
| `develop/shell-review/skill/scripts/review.sh` | review.sh — one-shot Shell script audit driver |

### GitOps / Argo CD Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/ucp/argocd-topics/examples/appset-helm/render-check.sh` | 本地验证「Helm 渲染 ApplicationSet」这条链路的转义有没有写对。 |
| `gcp/ucp/argocd-topics/examples/argocd-health.sh` | Argo CD 一键体检脚本 |
| `gcp/ucp/argocd-topics/examples/gitops-layout/ci-check.sh` | ci-check.sh —— 一键跑完全部静态检查（提交前 / CI 入口） |
| `gcp/ucp/argocd-topics/examples/gitops-layout/demo.sh` | demo.sh · Argo CD GitOps 全流程 Demo |
| `gcp/ucp/argocd-topics/examples/gitops-layout/enable-component.sh` | enable-component.sh —— 给已有集群开关组件 |
| `gcp/ucp/argocd-topics/examples/gitops-layout/new-cluster.sh` | new-cluster.sh —— 新增一个集群的脚手架 |
| `gcp/ucp/argocd-topics/examples/rulesets-enterprise/apply-rulesets.sh` | apply-rulesets.sh（企业版）—— 把 rulesets-enterprise/ 里的规则下发到 GitHub |
| `gcp/ucp/argocd-topics/examples/rulesets-enterprise/branch-name-hook.sh` | branch-name-hook.sh（企业版）—— L1：本地 pre-push 分支名检查 |
| `gcp/ucp/argocd-topics/examples/rulesets-enterprise/commit-msg-hook.sh` | commit-msg-hook.sh（企业版）—— L1：本地 commit-msg hook（秒级反馈） |
| `gcp/ucp/argocd-topics/examples/rulesets-enterprise/install-ci-check.sh` | install-ci-check.sh（企业版）—— 把可选的 CI 兜底装进**多个**仓库 |
| `gcp/ucp/argocd-topics/examples/rulesets-enterprise/probe-enterprise-capabilities.sh` | probe-enterprise-capabilities.sh —— ★ 实测你们的 org 到底支持哪些 rule type |
| `gcp/ucp/argocd-topics/examples/rulesets/apply-rulesets.sh` | apply-rulesets.sh —— 把 examples/rulesets/ 里的规则集真正装到 GitHub 上 |
| `gcp/ucp/argocd-topics/examples/rulesets/commit-msg-hook.sh` | commit-msg-hook.sh —— L1：本地 commit-msg hook（秒级反馈） |
| `gcp/ucp/argocd-topics/examples/rulesets/install-ci-check.sh` | install-ci-check.sh —— 把 commit message 校验的 GitHub Actions 装进仓库 |
| `gcp/ucp/argocd-topics/git-apps/cr-check/scripts/send-test-event.sh` | 发送测试 webhook 请求，验证 CR Check 的判定逻辑。 |
| `gcp/ucp/argocd-topics/verify-cr-prefix.sh` | verify-cr-prefix.sh —— 验证「GitHub Ruleset × GitHub Actions」的咬合关系 |
| `gcp/ucp/scripts/ci-validate.sh` | ci-validate.sh - UCP 仓库 PR 门禁 |
| `gcp/ucp/scripts/verify-poc.sh` | verify-poc.sh - UCP PoC 端到端验收脚本 |

### GCP ASM/Istio Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/asm/gloo/yamls/e2e-validation.sh` | e2e-validation.sh - End-to-End Validation Script for Gloo Mesh Enterprise |
| `gcp/asm/gloo/yamls/minimax/e2e-validation.sh` | e2e-validation.sh - Complete E2E validation script for Gloo Gateway |
| `gcp/asm/k8s-gateway-ambient/case-lex-intra-call/09-verify.sh` | 09-verify.sh |
| `gcp/asm/k8s-gateway-ambient/case-lex-intra-call/90-teardown.sh` | 90-teardown.sh |
| `gcp/asm/trace-istio-and-export.sh` | Reverse-trace URL -> Gateway -> VirtualService -> DestinationRule |
| `gcp/asm/trace-istio.sh` | trace-istio.sh — Istio 全链路资产追踪脚本 |

### GCP Cloud Run Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/cloud-run/cloud-run-automation/cloud-run-housekeep.sh` | Cloud Run Job Housekeeping Script (Enhanced Version) |
| `gcp/cloud-run/cloud-run-job-housekeep.sh` | Cloud Run Job Housekeeping Script (Enhanced Version) |
| `gcp/cloud-run/cloud-run-job-migration-jq-fixed.sh` | Cloud Run Job 配置迁移脚本 (使用 jq 版本 - 修复版) |
| `gcp/cloud-run/cloud-run-job-migration-jq.sh` | Cloud Run Job 配置迁移脚本 (使用 jq 版本) |
| `gcp/cloud-run/cloud-run-job-migration-script.sh` | Cloud Run Job 配置迁移脚本 |
| `gcp/cloud-run/container-validation/app-entrypoint.sh` | 应用入口点脚本 |
| `gcp/cloud-run/container-validation/build-with-validation.sh` | 带校验功能的Docker构建脚本 |
| `gcp/cloud-run/container-validation/startup-validator-v2.sh` | 容器启动时的环境校验脚本 - 通用版本 |
| `gcp/cloud-run/container-validation/startup-validator-v3.sh` | 容器启动时的环境校验脚本 - JSON配置版本 |
| `gcp/cloud-run/container-validation/startup-validator.sh` | 容器启动时的环境校验脚本 |
| `gcp/cloud-run/extract-env-vars.sh` | Extract Env Vars |
| `gcp/cloud-run/verify/image-branch-validation.sh` | Cloud Run镜像分支校验脚本 |
| `gcp/cloud-run/verify/secure-cloud-run-deploy.sh` | 安全的Cloud Run部署脚本 |

### GCP GCE/MIG Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/gce/get_instance_timestamps.sh` | 设置输出文件路径（您可以根据需要修改路径，确保在允许的目录内） |
| `gcp/gce/get_instance_uptime.sh` | Get Instance Uptime |
| `gcp/gce/instance-uptime-gemini.sh` | 脚本: instance-uptime-gemini.sh |
| `gcp/gce/rolling/rolling-mig-and-verify-status-warp.sh` | rolling-mig-and-verify-status-warp.sh |
| `gcp/gce/rolling/rolling-mig-and-verify-status.sh` | rooling-mig-and-verify-status.sh |
| `gcp/gce/rolling/rolling-replace-instance-groups-eng.sh` | rolling-replace-instance-groups.sh |
| `gcp/gce/rolling/rolling-replace-instance-groups.sh` | rolling-replace-instance-groups.sh |
| `gcp/gce/rolling/rolling-replace-mig-enhance-minimax.sh` | rolling-replace-mig-enhance-minimax.sh |
| `gcp/gce/rolling/rolling-replace-mig-enhance.sh` | rolling-replace-mig-enhance.sh |
| `gcp/gce/rolling/verify-mig-status.sh` | verify-mig-status.sh - Verify MIG instances status after refresh/replace |
| `gcp/gce/verify-gcp-and-gke-status.sh` | Colors for better readability |

### GCP LB/GLB/Ingress Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/lb/lb-get-ssl-infor.sh` | get-forwarding-rule.sh (v2 — bash + jq only) |
| `gcp/lb/lb-poc-from-mig.sh` | Lb Poc From Mig |
| `gcp/lb/lb-poc-gen.sh` | lb-poc-gen.sh — 从已有 MIG 探索 LB 依赖链，并生成 POC 创建命令 |
| `gcp/lb/refer-lb-create.sh` | refer-lb-create.sh — 从现有 MIG 关联的 LB 链路中提取配置，生成 POC 创建命令 |

### GCP Cloud Armor Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/cloud-armor/ip_filter.sh` | 脚本功能: 优化IP地址列表 |
| `gcp/cloud-armor/ip_filter_maxos_error.sh` | IP地址处理调试脚本 |

### GCP DNS Migration Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/migrate-gcp/get-ns-info-fast.sh` | Fast GKE Namespace Information Extraction Script using JSON parsing |
| `gcp/migrate-gcp/get-ns-information.sh` | GKE Namespace Information Extraction Script |
| `gcp/migrate-gcp/get-ns-stats-gemini.sh` | Gemini Enhanced GKE Namespace Statistics Script - Comprehensive migration analysis |
| `gcp/migrate-gcp/get-ns-stats-kiro-enhance.sh` | Enhanced GKE Namespace Statistics Script - Comprehensive migration analysis |
| `gcp/migrate-gcp/get-ns-stats-optimized.sh` | Optimized GKE Namespace Statistics Script - Fast execution with migration focus |
| `gcp/migrate-gcp/get-ns-stats.sh` | GKE Namespace Statistics Script - Focus on counts and unique values |
| `gcp/migrate-gcp/migrate-dns/01-discovery.sh` | DNS 迁移 - 第一步：服务发现和映射关系建立 |
| `gcp/migrate-gcp/migrate-dns/02-prepare-target.sh` | DNS 迁移 - 第二步：准备目标项目DNS记录 |
| `gcp/migrate-gcp/migrate-dns/03-execute-migration.sh` | DNS 迁移 - 第三步：执行DNS切换 |
| `gcp/migrate-gcp/migrate-dns/04-rollback.sh` | DNS 迁移 - 第四步：回滚操作 |
| `gcp/migrate-gcp/migrate-dns/05-cleanup.sh` | DNS 迁移 - 第五步：清理操作 |
| `gcp/migrate-gcp/migrate-dns/config.sh` | GCP DNS 迁移配置文件 |
| `gcp/migrate-gcp/migrate-dns/examples/example-config.sh` | GCP DNS 迁移配置示例文件 |
| `gcp/migrate-gcp/migrate-dns/migrate-dns.sh` | DNS 迁移主控制脚本 |
| `gcp/migrate-gcp/migrate-secret-manage/01-setup.sh` | Secret Manager 迁移 - 环境准备脚本 |
| `gcp/migrate-gcp/migrate-secret-manage/02-discover.sh` | Secret Manager 迁移 - 密钥发现脚本 |
| `gcp/migrate-gcp/migrate-secret-manage/03-export.sh` | Secret Manager 迁移 - 密钥导出脚本 |
| `gcp/migrate-gcp/migrate-secret-manage/04-import.sh` | Secret Manager 迁移 - 密钥导入脚本 |
| `gcp/migrate-gcp/migrate-secret-manage/05-verify.sh` | Secret Manager 迁移 - 验证脚本 |
| `gcp/migrate-gcp/migrate-secret-manage/06-update-apps.sh` | Secret Manager 迁移 - 应用配置更新脚本 |
| `gcp/migrate-gcp/migrate-secret-manage/config.sh` | GCP Secret Manager 迁移配置文件 |
| `gcp/migrate-gcp/migrate-secret-manage/migrate-secrets.sh` | Secret Manager 迁移主控制脚本 |
| `gcp/migrate-gcp/pop-migrate/migrate.sh` | GKE 跨项目 Namespace 迁移工具 |
| `gcp/migrate-gcp/pop-migrate/scripts/cleanup.sh` | 清理脚本 - 清理导出文件、备份和临时文件 |
| `gcp/migrate-gcp/pop-migrate/scripts/export.sh` | 导出脚本 - 从源集群导出指定 namespace 的资源 |
| `gcp/migrate-gcp/pop-migrate/scripts/import.sh` | 导入脚本 - 将导出的资源导入到目标集群 |
| `gcp/migrate-gcp/pop-migrate/scripts/validate.sh` | 验证脚本 - 验证迁移结果和资源状态 |
| `gcp/migrate-gcp/pop-migrate/test-no-yq.sh` | 测试脚本：验证在没有 yq 的情况下工具是否正常工作 |

### GCP Secret Manager Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/secret-manage/java-examples/k8s/secret-setup.sh` | GCP Secret Manager Setup Script |
| `gcp/secret-manage/java-examples/setup-gcp.sh` | Complete GCP setup script for Secret Manager Demo |
| `gcp/secret-manage/java-examples/verify-gcp-sa.sh` | Enhanced GCP Secret Manager Service Account Verification Script |
| `gcp/secret-manage/list-secret/auto-select-version.sh` | 智能版本选择脚本 |
| `gcp/secret-manage/list-secret/benchmark-comparison.sh` | 性能对比测试脚本 |
| `gcp/secret-manage/list-secret/filter-secrets.sh` | Filter Secrets |
| `gcp/secret-manage/list-secret/list-all-secrets-optimized.sh` | GCP Secret Manager 权限审计脚本 - 最优化版本 |
| `gcp/secret-manage/list-secret/list-all-secrets-permissions-parallel.sh` | GCP Secret Manager 权限审计脚本 - 并行版本 |
| `gcp/secret-manage/list-secret/list-all-secrets-permissions.sh` | GCP Secret Manager 权限审计脚本 |
| `gcp/secret-manage/list-secret/list-all-secrets-simple-optimized.sh` | GCP Secret Manager 权限审计脚本 - 简化最优版本 |
| `gcp/secret-manage/list-secret/list-secrets-groups-sa.sh` | GCP Secret Manager - Groups 和 ServiceAccounts 快速查询 |
| `gcp/secret-manage/list-secret/test-increment-fix.sh` | 测试脚本：验证计数器修复 |
| `gcp/secret-manage/list-secret/verify-gcp-secretmanage.sh` | 设置颜色输出 |
| `gcp/secret-manage/secret-manager-admin.sh` | - #!/bin/bash |

### GCP Service Account / IAM Check Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/sa/verify-another-proj-sa.sh` | Verifies what roles/permissions a Service Account from another |
| `gcp/sa/verify-cross-project-pub-sub-sa.sh` | Queries a GCP Service Account (from KSA binding in deploy project) |
| `gcp/sa/verify-gce-sa.sh` | Verifies the existence, keys, and IAM roles of a GCP Service Account. |
| `gcp/sa/verify-gke-ksa-iam-authentication.sh` | 设置颜色输出 |
| `gcp/sa/verify-iam-based-authentication-enhance.sh` | 设置颜色输出 |

### GCS Bucket Check Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/buckets/add-bucket-binding.sh` | GCS Bucket IAM 绑定添加脚本 |
| `gcp/buckets/create-buckets.sh` | GCS Bucket 批量创建脚本 |
| `gcp/buckets/verify-buckets-iam-grok.sh` | GCS Bucket IAM 绑定验证脚本 (Grok 优化版 v2.0) |
| `gcp/buckets/verify-buckets-iam.sh` | GCS Bucket IAM 绑定验证脚本 (纯 Shell + jq 版本) |
| `gcp/buckets/verify-buckets.sh` | GCS Bucket 验证脚本 |

### GCP Network/PSC Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/psa-psc/psc-dr/scripts/setup-dr-psc.sh` | 一键创建 Cloud SQL PSC 的跨 Region DR 链路 |
| `gcp/psa-psc/psc-dr/scripts/verify-dr-psc.sh` | 校验 PSC 跨 Region DR 链路是否就绪 |
| `gcp/psa-psc/psc-sql-flow-demo/scripts/cleanup.sh` | 清理脚本 - 删除所有创建的资源 |
| `gcp/psa-psc/psc-sql-flow-demo/scripts/deploy-app.sh` | 应用部署脚本 |
| `gcp/psa-psc/psc-sql-flow-demo/scripts/monitor.sh` | 监控脚本 - 实时监控应用状态 |
| `gcp/psa-psc/psc-sql-flow-demo/scripts/test-connection.sh` | 连接测试脚本 |
| `gcp/psa-psc/psc-sql-flow-demo/setup/env-vars.sh` | 环境变量配置文件 |
| `gcp/psa-psc/psc-sql-flow-demo/setup/setup-consumer.sh` | Consumer 项目设置脚本 - 创建 GKE 集群和 PSC 端点 |
| `gcp/psa-psc/psc-sql-flow-demo/setup/setup-producer.sh` | Producer 项目设置脚本 - 创建 Cloud SQL 并启用 PSC |

### GCP Logging/Pub/Sub Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/firestore/scripts/firestore-get-collection-chatgpt.sh` | Firestore Get Collection Chatgpt |
| `gcp/firestore/scripts/firestore-get-collection-claude.sh` | Firestore Get Collection Claude |
| `gcp/firestore/scripts/firestore-get-collection-grok.sh` | Firestore Get Collection Grok |
| `gcp/firestore/scripts/firestore-get-collection.sh` | Firestore Get Collection |
| `gcp/firestore/scripts/firestore-get-specific-fields.sh` | Firestore Get Specific Fields |
| `gcp/firestore/scripts/get_value.sh` | Get Value |
| `gcp/logs/splunk/scripts/git.sh` | Define the directory |
| `gcp/pub-sub/pub-sub-cmek/pubsub-cmek-manager.sh` | Manage Pub/Sub topics with CMEK encryption and Cloud Scheduler jobs |

### GCP BigQuery/SQL Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/sql/process_data.sh` | 设置错误处理 |

### GCP General/Info Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/artifact-registry/scripts/cleanup-policy-audit.sh` | cleanup-policy-audit.sh |
| `gcp/cost/fetch-gcp-pricing.sh` | fetch-gcp-pricing.sh — Pull current GCP SKU pricing from Cloud Billing Catalog |
| `gcp/cost/gcp-cost/gcp-logging-audit-script.sh` | gcp-logging-audit-script.sh - GCP 项目日志配置审计脚本 |
| `gcp/cost/gcp-cost/gcp-logging-quick-setup.sh` | gcp-logging-quick-setup.sh - GCP 日志成本优化快速设置脚本 |
| `gcp/cross-project/approve-tenant-project.sh` | approve-tenant-project.sh - Producer 侧审批 Tenant PSC Service Attachment 连接 |
| `gcp/cross-project/public-tls-basingpath-cross/verify-backend-service-type.sh` | verify-backend-service-type.sh — 零参数验证当前 GCP 工程里所有 Backend Service |
| `gcp/cross-project/public-tls-basingpath-cross/verify-glb-type.sh` | verify-glb-type.sh — 零参数验证当前 GCP 工程里 GLB 的类型,判断能否做 PSC NEG |
| `gcp/gcp-infor/assistant/gcp-preflight.sh` | Gcp Preflight |
| `gcp/gcp-infor/assistant/run-verify.sh` | Run Verify |
| `gcp/gcp-infor/gcp-explore.sh` | GCP Platform Exploration Script |
| `gcp/gcp-infor/gcp-functions.sh` | GCP Functions Library |
| `gcp/gcp-infor/linux-scripts/gcp-linux-env.sh` | gcp-linux-env.sh - Linux-specific GCP environment checker |
| `gcp/gcp-infor/linux-scripts/gcp-validate.sh` | gcp-validate.sh - Validate GCP scripts for Linux environment |
| `gcp/gke/script/audit-static-pod-refs.sh` | audit-static-pod-refs.sh — Static Pod Manifest Auditor for Kubernetes v1.37 |
| `gcp/gke/script/update-node-pools-firewall.sh` | update-node-pools-firewall.sh — Manage GKE Standard node-pool network tags |
| `gcp/gke/script/upgrade-gke-cluster.sh` | upgrade-gke-cluster.sh — GKE 集群升级脚本 |
| `gcp/gke/script/upgrade-gke-node.sh` | upgrade-gke-node.sh — GKE Node Pool 升级脚本 |
| `gcp/gke/script/verify-gke-cluster-upgrade.sh` | verify-gke-cluster-upgrade.sh — GKE 集群升级记录验证脚本 |
| `gcp/terraform/scripts/apply-from-resourceset.sh` | apply-from-resourceset.sh — provision a new GCP project from a resourceset YAML. |
| `gcp/terraform/scripts/introspect-project.sh` | introspect-project.sh — dump an existing GCP project's infra into resourceset YAML. |
| `gcp/tools/git.sh` | Git |

### Gateway/Kong Check Scripts

| File Path | Description |
| :--- | :--- |
| `gateway/kong/kongdp/compare-dp-eng.sh` | Kong Data Plane Comparison Script |
| `gateway/kong/kongdp/compare-dp.sh` | Kong Data Plane Comparison Script |
| `gateway/kong/kongdp/verify-dp-status-gemini.sh` | Kong Data Plane Status Verification Script (Gemini Optimized) |
| `gateway/kong/kongdp/verify-dp-status.sh` | Kong Data Plane Status Verification Script |
| `gateway/kong/kongdp/verify-dp-summary.sh` | verify-dp-summary.sh |
| `gateway/kong/kongdp/verify-dp.sh` | verify-dp.sh |
| `gateway/kong/scripts/git.sh` | Git |
| `gateway/no-gateway/verify-gke-gateway-chatgpt.sh` | Verify GKE Gateway API configuration and resource status (robust) |
| `gateway/no-gateway/verify-gke-gateway-claude.sh` | Verify GKE Gateway API configuration and resource status |
| `gateway/no-gateway/verify-gke-gateway.sh` | verify-gke-gateway.sh |
| `gateway/no-gateway/verify-no-gateway-all.sh` | Verify GKE Gateway API configuration and resource status |

### SSL/TLS Check Scripts

| File Path | Description |
| :--- | :--- |
| `gcp/mtls/mtls-test/gemini.sh` | 检查输入参数 |
| `gcp/mtls/mtls-test/generate-self-signed-cert_lmstudio.sh` | Generate Self Signed Cert Lmstudio |
| `gcp/mtls/mtls-test/generate-self-singned-cert.sh` | Generate Self Singned Cert |
| `gcp/mtls/mtls-test/get_cert_fingerprint.sh` | Function: Display usage instructions for the script |
| `gcp/mtls/mtls-test/get_cert_fingerprint_chatgpt.sh` | Function: Display usage instructions for the script |
| `gcp/mtls/mtls-test/get_cert_fingerprint_claude.sh` | Function: Display usage instructions for the script |
| `gcp/mtls/mtls-test/get_cert_fingerprint_no_type.sh` | Function: Display usage instructions for the script |
| `gcp/mtls/trust-config/debug-trust-configs.sh` | Debug version to test trust config access |
| `gcp/mtls/trust-config/verify-trust-configs.sh` | Verify GCP Certificate Manager Trust Configs and extract |
| `safe/cert/check_eku.sh` | check_eku.sh - Check Extended Key Usage (EKU) in certificates |
| `safe/cert/digicert_impact_assessment.sh` | digicert_impact_assessment.sh - Comprehensive DigiCert EKU Impact Assessment |
| `safe/ssl/docs/claude/routeaction/maps-format-and-verify/apply-urlmap-json.sh` | Apply Urlmap Json |
| `safe/ssl/docs/claude/routeaction/maps-format-and-verify/verify-urlmap-json.sh` | verify-urlmap-json.sh |
| `safe/ssl/ingress-ssl/check-tls-secret-ns.sh` | TLS Secrets Namespace Validation Script |
| `safe/ssl/ingress-ssl/check-tls-secret.sh` | TLS Secret Validation Script |
| `safe/ssl/ingress-ssl/create-tls-secret.sh` | 创建 TLS Secret 到 K8s 脚本 |
| `safe/ssl/ingress-ssl/generate-cert-chain.sh` | 生成包含中间证书的证书链 |
| `safe/ssl/ingress-ssl/generate-self-signed-cert.sh` | 自签名证书生成脚本 |
| `safe/ssl/scripts/get-ssl-all-information.sh` | 检查是否提供了输入文件 |
| `safe/ssl/scripts/get-ssl-all.sh` | 检查是否提供了输入文件 |
| `safe/ssl/scripts/get-ssl.sh` | 检查是否提供了输入文件 |
| `safe/ssl/verify-domain-ssl-ct-fallback.sh` | verify-domain-ssl-ct-fallback.sh |
| `safe/ssl/verify-domain-ssl-enhance.sh` | Verify Domain Ssl Enhance |
| `safe/ssl/verify-domain-ssl.sh` | Verify Domain Ssl |
| `safe/ssl/verify-fqdn.sh` | One-shot FQDN sanity check — DNS resolution across public resolvers + TLS/SSL analysis. |
| `safe/ssl/verify-url-cert.sh` | One-shot TLS/certificate inspection for a URL, focused on CWE-326 |

### Nginx/Web Service Scripts

| File Path | Description |
| :--- | :--- |
| `webservice/nginx/ingress-control/check-tls-secret-ns.sh` | TLS Secrets Namespace Validation Script |
| `webservice/nginx/ingress-control/check-tls-secret.sh` | 用法: ./check-tls-secret.sh <secret-name> <namespace> |
| `webservice/nginx/ingress-control/check-tls-secret2.sh` | TLS Secret Validation Script |

### Linux/Optimization Scripts

| File Path | Description |
| :--- | :--- |
| `linux/dns/dns-peering/Docker-dns/docker-build-run.sh` | Docker Build Run |
| `linux/dns/dns-peering/dns-fqdn-verify.sh` | Verify domain ownership by determining if the resolved IP is private or public |
| `linux/dns/dns-peering/dns-peering-claude.sh` | Check if domain parameter is provided |
| `linux/dns/dns-peering/dns-peering-eng.sh` | Check if domain parameter is provided |
| `linux/dns/dns-peering/dns-query-eng.sh` | Check if domain parameter is provided |
| `linux/dns/dns-peering/dns-query.sh` | 检查是否提供了域名参数 |
| `linux/dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6-enhanced.sh` | Enhanced DNS verification with IPv6, parallel queries, batch processing, |
| `linux/dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6-ok.sh` | Enhanced DNS verification with IPv6, parallel queries, batch processing, |
| `linux/dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6.sh` | Enhanced DNS verification with IPv6, parallel queries, batch processing, |
| `linux/dns/dns-peering/verify-dns-fqdn.sh` | Verify domain resolution across multiple DNS servers and check against Peering list. |
| `linux/dns/dns-peering/verify-pub-priv-ip-glm-ipv6-fixed.sh` | Enhanced DNS verification with IPv6, parallel queries, batch processing, |
| `linux/dns/dns-peering/verify-pub-priv-ip-glm-ipv6.sh` | Enhanced DNS verification with IPv6, parallel queries, batch processing, |
| `linux/dns/dns-peering/verify-pub-priv-ip-glm-ok.sh` | Enhanced DNS verification with IPv6, parallel queries, batch processing, |
| `linux/dns/dns-peering/verify-pub-priv-ip.sh` | Verify domain resolution across multiple DNS servers and determine if IP is public/private. |
| `linux/dns/docs/dns-debug.sh` | dns-debug.sh — GKE DNS Resolution Debug Tool |
| `linux/dns/docs/dnsrecord-add-del-eng.sh` | Automatically add or delete DNS records in Cloud DNS Zone |
| `linux/dns/docs/dnsrecord-add-del.sh` | GCP Cloud DNS 记录批量管理脚本 |
| `linux/dns/docs/dnsrecord-add-script-eng.sh` | Automatically resolve domains and add CNAME and A records to the specified Cloud DNS Zone |
| `linux/dns/docs/dnsrecord-add-script.sh` | GCP Cloud DNS 记录批量添加脚本 |
| `linux/dns/docs/dnsrecord-del-script-eng.sh` | Delete all related records (CNAME and A records) for specified domains in Cloud DNS Zone |
| `linux/dns/docs/dnsrecord-del-script.sh` | GCP Cloud DNS 记录批量删除脚本 |
| `linux/dns/docs/private-access/create-claude-one-by-one.sh` | GCP Cloud DNS Zone 迁移脚本 - 稳定版 |
| `linux/dns/docs/private-access/create-claude.sh` | GCP Cloud DNS Zone 迁移脚本 - 稳定版 |
| `linux/dns/docs/private-access/create-private-access-success-one-by-one.sh` | GCP Cloud DNS Zone 迁移脚本 |
| `linux/dns/docs/private-access/create-private-access.sh` | GCP Cloud DNS Zone 迁移脚本 |
| `linux/docs/verify-timeout-chain.sh` | Verify Timeout Chain |
| `linux/linux-os-optimize/Linux-system-optimize.sh` | Linux-system-optimize.sh |
| `linux/linux-os-optimize/linux-nginx-system-optimize-calude4-5.sh` | GCP-Linux-System-Optimize.sh |
| `linux/linux-os-optimize/linux-nginx-system-optimize.sh` | Optimize Linux system limits and kernel parameters |
| `linux/linux-os-optimize/linux-system-optimize-gemini.sh` | Linux System Optimization for Nginx on GCP |
| `linux/linux-os-optimize/linux-system-optimize-tt.sh` | Linux System Optimization Script for GCP Nginx Web Server |
| `linux/linux-os-optimize/universal_optimize.sh` | universal_optimize.sh |
| `linux/network/scripts/explorer-domain-claude.sh` | Domain Explorer Script - Claude Optimized Version |
| `linux/network/scripts/explorer-domain-gemini.sh` | An advanced script for comprehensive domain analysis, including DNS, IP, web, SSL, and vulnerabil... |
| `linux/network/scripts/explorer-domain-grok.sh` | Domain Explorer Script - Grok Optimized Version |
| `linux/network/scripts/explorer-domain-kimi.sh` | Domain Explorer Script - Ultra Optimized Version |
| `linux/network/scripts/explorer-domain-qwen.sh` | Domain Explorer Script - Enhanced Version |
| `linux/network/scripts/explorer-domain.sh` | Domain Explorer Script |
| `linux/network/scripts/test-ipv6-local.sh` | IPv6 Network Connectivity Test Script for macOS |
| `linux/network/wrk/advanced-load-test.sh` | Advanced Load Testing with Real-time Monitoring |
| `linux/network/wrk/config-based-test.sh` | Configuration-based Load Testing Script |
| `linux/network/wrk/pressure-test-suite.sh` | Comprehensive Pressure Testing Suite |

### Git Workflow Scripts

| File Path | Description |
| :--- | :--- |
| `linux/howgit/scripts/git_changes_stats.sh` | Git Changes Stats |
| `linux/howgit/scripts/git_detailed_stats.sh` | Git Detailed Stats |
| `linux/howgit/scripts/git_recent_changes.sh` | 显示最近20次提交涉及的文件列表 |
| `linux/howgit/scripts/github_api_stats.sh` | 需要设置你的 GitHub token |

### Shell Script Utility Scripts

| File Path | Description |
| :--- | :--- |
| `bin/fix-rag-ingest-launchd.sh` | fix-rag-ingest-launchd.sh |
| `bin/git-detail-status.sh` | Git 提交记录智能分析工具 v2.0 |
| `bin/git-ios.sh` | Git Ios |
| `bin/git-mac.sh` | 获取操作系统类型 |
| `bin/git_detail_stats.sh` | 配置参数 |
| `bin/push-c.sh` | !/usr/bin/env bash |
| `bin/push-call-local-ai.sh` | Push Call Local Ai |
| `bin/push-claude.sh` | !/usr/bin/env bash |
| `bin/rp.sh` | rp.sh - Batch search and replace in files using a config file |
| `bin/sync-html-to-docs.sh` | Sync HTML files from knowledge workspace to docs directory |
| `linux/scripts/csv-format-bard.sh` | Function to generate a Markdown table from a CSV file |
| `linux/scripts/git.sh` | Git |
| `linux/shell-script/scripts/batch_replace.sh` | 批量替换脚本 |
| `linux/shell-script/scripts/batch_replace_preview.sh` | 批量替换脚本 - 预览版本 |
| `linux/shell-script/scripts/git-detail-status.sh` | Git 提交记录智能分析工具 v2.0 |
| `linux/shell-script/scripts/git.sh` | Define the directory |
| `linux/shell-script/scripts/replace.sh` | 批量替换脚本 - 用于替换当前目录下所有文件中的文本 |
| `linux/shell-script/scripts/source.sh` | Source |
| `scripts/install-sanitize-hooks.sh` | install-sanitize-hooks.sh — 安装内部标识符闸门钩子 |
| `scripts/sanitize-check.sh` | sanitize-check.sh — 内部标识符扫描闸门 |
| `scripts/sanitize-replace.sh` | sanitize-replace.sh — 按本机内部标识符清单做定向替换（push 流程自动调用） |
| `scripts/sanitize-rules.sh` | sanitize-rules.sh — 规则表加载（sanitize-check.sh / sanitize-replace.sh 共用） |
| `shortcut/scripts/a.sh` | this is a script |
| `shortcut/scripts/batch_replace.sh` | 批量替换脚本 |
| `shortcut/scripts/batch_replace_preview.sh` | 批量替换脚本 - 预览版本 |

### Database/Redis/SQL Scripts

| File Path | Description |
| :--- | :--- |
| `database/sql/scripts/git.sh` | Git |

### Security Scripts

| File Path | Description |
| :--- | :--- |
| `safe/cwe/check_ubuntu_cve_status.sh` | 查询指定 Ubuntu 版本的 CVE 修复状态 |
| `safe/cwe/verify-enhance-html.sh` | Verify Enhance Html |
| `safe/cwe/verify-enhance.sh` | Verify Enhance |
| `safe/cwe/verify.sh` | 默认 CVE 编号 |
| `safe/gcp-safe/debug-test.sh` | KMS 验证脚本调试工具 |
| `safe/gcp-safe/quick-test.sh` | 快速测试脚本 - 验证修复是否生效 |
| `safe/gcp-safe/test-arithmetic.sh` | Test Arithmetic |
| `safe/gcp-safe/test-permissions.sh` | KMS 权限测试脚本 |
| `safe/gcp-safe/verify-kms-enhanced.sh` | GCP KMS 跨项目权限校验脚本 (增强版) |
| `safe/get-token/curl-token.sh` | 脚本说明：获取 API Token 并执行健康检查 |
| `safe/scripts/basic-domain-explorer.sh` | Basic Domain Explorer Script |
| `safe/scripts/basic_recon.sh` | A simple shell script for basic domain reconnaissance based on the kali.md document. |
| `safe/scripts/domain_intel.sh` | A comprehensive domain reconnaissance script based on the workflow from kali.md |
| `safe/scripts/explorer-domain-claude.sh` | Domain Explorer Script - Claude Optimized Version |
| `safe/scripts/git.sh` | Git |

### SRE/Monitoring Scripts

| File Path | Description |
| :--- | :--- |
| `sre/header-tracing/scripts/header-trace.sh` | header-trace.sh — Hop-by-hop header trace helper for a multi-hop proxy chain. |
| `sre/monitor/gce-disk/rolling-recreate-instances.sh` | rolling-recreate-instances.sh |

### macOS/iOS Scripts

| File Path | Description |
| :--- | :--- |
| `macos/apple/scripts/code-to-note.sh` | 专门用于代码文件的笔记创建工具 |
| `macos/apple/scripts/create-note-from-file.sh` | 安全的文件到笔记转换脚本 |
| `macos/apple/scripts/simple-file-to-note.sh` | 最简单的文件到笔记转换 |
| `macos/native-tools/free-macos.sh` | Free Macos |
| `macos/neofetch/neofetch.sh` | vim: noai:ts=4:sw=4:expandtab |
| `macos/scripts/chat.sh` | 获取所有进程的PID、CPU占用率、内存占用（以MB为单位）、以及所属应用名称 |
| `macos/scripts/fix-bash.sh` | macOS Bash 升级与脚本修复工具 |
| `macos/scripts/hugg.sh` | Get the list of processes and their CPU and memory usage |
| `macos/scripts/macos_power_keepawake.sh` | Macos Power Keepawake |
| `macos/scripts/macos_power_keepawake_stop.sh` | Macos Power Keepawake Stop |
| `macos/scripts/macos_power_restore_defaults.sh` | Macos Power Restore Defaults |
| `macos/scripts/macos_power_schedule.sh` | Macos Power Schedule |
| `macos/scripts/macos_power_server_mode.sh` | Macos Power Server Mode |
| `macos/scripts/macos_power_status.sh` | Macos Power Status |
| `macos/scripts/monitor_background_shortcut_runner.sh` | Monitor Background Shortcut Runner |
| `macos/scripts/resouce_usage.sh` | Enhanced macOS Resource Usage Monitor |
| `macos/scripts/resource.sh` | 获取CPU使用率最高的进程 |

### Other Scripts

| File Path | Description |
| :--- | :--- |
| `English/scripts/read_doc.sh` | 文件名: read_doc.sh |
| `ai/concept/demo.sh` | 知识库检索系统演示脚本 |
| `ai/concept/kb_search.sh` | 快速知识库搜索脚本 (不使用 AI) |
| `ai/concept/setup.sh` | 安装依赖和设置别名 |
| `ai/docs/ocrp.sh` | /Users/lex/.local/bin/ocrp |
| `concept/api-service/python-api-demo/python-health-demo/generate_certs.sh` | Default password if not set |
| `fm.sh` | fm.sh - Format markdown files using local Ollama AI (Shell only version) |
| `gh-weekly-dashboard.sh` | gh-weekly-dashboard.sh — GitHub Weekly Activity Dashboard (beautified v2) |
| `gif/docs/git.sh` | Git |
| `gif/scripts/covert-mp4-git.sh` | Covert Mp4 Git |
| `gif/scripts/vide-cut.sh` | Video to GIF Converter with Smart Splitting |
| `gif/scripts/video-watermark.sh` | Video Text Watermark Adder |
| `git-push.sh` | 函数：获取操作系统类型 |
| `git.sh` | Git |
| `linux/tools/export-vscode-plug.sh` | export-vscode-plug.sh |
| `other/scripts/git.sh` | cd /Users/lex/Downloads/git/groovy |
| `push-llama.sh` | push-llama.sh |
| `push.sh` | Push |
| `rais.sh` | Replace with the path to your Git repository |
| `test-merge.sh` | Test Merge |
| `vscode/get-vsix-en.sh` | Get Vsix En |

---

## Markdown Documents (`.md`)

### Ali Cloud Documentation

| File Path | Title |
| :--- | :--- |
| `cloud/ali/README.md` | Ali (阿里巴巴) |
| `cloud/ali/ali-dns/README.md` | DNS Batch Update Tool |
| `cloud/ali/ali-dns/merged-scripts.md` | Shell Scripts Collection |
| `cloud/ali/docs/Ali-Logstore.md` | 梳理一下阿里云 K8S 里的 **日志采集**和 **Logstore 加密**的概念。 |
| `cloud/ali/docs/README.md` | Ali (Alibaba Cloud) 知识库 |
| `cloud/ali/docs/a-call-b-debug.md` | Summary |
| `cloud/ali/docs/imagepullsecret-sa.md` | Why Service Accounts Have imagePullSecrets Automatically Added |
| `cloud/ali/docs/imagepullsecret.md` | concepts |
| `cloud/ali/docs/k8s-resources.md` | Kubernetes Resources Script - Get CPU and Memory limits/requests for Deployments |
| `cloud/ali/docs/merged-scripts.md` | Shell Scripts Collection |
| `cloud/ali/docs/migrate-exclude-secret.md` | Kubernetes Secrets 迁移脚本 |
| `cloud/ali/docs/namespace-status.md` | Kubernetes Namespace Status Check Script |
| `cloud/ali/docs/slb-binding-ingress.md` | New |
| `cloud/ali/docs/v4.md` | E2E Verification Script for Kubernetes Resources |
| `cloud/ali/docs/v5.md` | E2E Verification Script for Kubernetes Resources |
| `cloud/ali/docs/v6.md` | E2E Verification Script for Kubernetes Resources |
| `cloud/ali/docs/v7.md` | E2E Verification Script for Kubernetes Resources |
| `cloud/ali/docs/verify-e2e.md` | E2E Verification Script for Kubernetes Resources |
| `cloud/ali/k8s-cluster-migration/design.md` | K8s集群迁移设计文档 |
| `cloud/ali/k8s-cluster-migration/requirements.md` | K8s集群迁移需求文档 |
| `cloud/ali/k8s-cluster-migration/tasks.md` | K8s 集群迁移实施计划 |
| `cloud/ali/k8s-migration-proxy/IMPLEMENTATION.md` | Task 1 Implementation: 创建代理服务基础架构 |
| `cloud/ali/k8s-migration-proxy/IMPLEMENTATION_SUMMARY.md` | 任务2实施总结 - 灰度迁移配置管理 |
| `cloud/ali/k8s-migration-proxy/README.md` | K8s集群迁移代理 (K8s Cluster Migration Proxy) |
| `cloud/ali/k8s-migration-proxy/TASK3_IMPLEMENTATION_SUMMARY.md` | Task 3 Implementation Summary: ExternalName Services Configuration |
| `cloud/ali/k8s-migration-proxy/docs/external-services.md` | ExternalName Services Configuration |
| `cloud/ali/k8s-migration-proxy/docs/ingress-implementation.md` | Ingress Configuration Implementation |
| `cloud/ali/max-computer/Dataworks-binding.md` | **🧩 一、基础概念梳理** |
| `cloud/ali/max-computer/Health-check.md` | 我们现在使用了阿里的 MaxComputer这个产品。但是我们要经过内部公司的一个扫描程序来扫描 ，做一些安全的扫描工作。 所以说按照我们常规的操作。流程来说 ，我们会开发一个 java healtch check 的 API然后呢让这个 API里面具备调用 Maxtomp... |
| `cloud/ali/max-computer/How-to-call-maxcomputer-using-java.md` | 如何通过 Java SDK 调用 MaxCompute（最简实践） |
| `cloud/ali/max-computer/create-table.md` | **🧩 一、核心目标与实现路径** |
| `cloud/ali/max-computer/maxcompute-health-check/README.md` | MaxCompute Health Check API |
| `cloud/ali/max-computer/threshold-maxcomputer.md` | MaxCompute 资源阈值、配额管理与 SRE 监控实践 (结合 DataWorks) |
| `cloud/ali/max-computer/threshold.md` | A |
| `cloud/ali/max-computer/why-using-maxcomputer.md` | 关于“我们是否必须使用 MaxCompute”的技术澄清 |
| `cloud/ali/migrate-plan/max-computer-gemini.md` | 阿里云 MaxCompute 是什么以及如何迁移 |
| `cloud/ali/migrate-plan/max-computer.md` | 导出数据 |
| `cloud/ali/migrate-plan/plan1/README-OPTIMIZED.md` | Kubernetes Ingress Migration Tool - Optimized Version |
| `cloud/ali/migrate-plan/plan1/README.md` | K8s集群迁移POC方案 |
| `cloud/ali/migrate-plan/plan1/backgroud.md` | 我现在做的事情是要做 k8s 集群的迁移 |
| `cloud/ali/migrate-plan/plan1/migrate-claude.md` | 关键配置：将请求代理到新集群 |
| `cloud/ali/migrate-plan/plan1/migrate-gpt.md` | summary |
| `cloud/ali/migrate-plan/plan1/migrate-grok.md` | Kubernetes 集群迁移方案审阅 |
| `cloud/ali/migrate-plan/plan1/migrate-kongDP.md` | Got it 👍 — migrating a Kong DP (Data Plane) from Cluster A → Cluster B is not just reinstalling the pods, it involves making sure the new... |
| `cloud/ali/migrate-plan/plan1/migrate-kongdp-gemini.md` | Kong DP 迁移计划 (从集群 A 到集群 B) |
| `cloud/ali/migrate-plan/plan1/migrate-namespace.md` | 1. kubectl get/apply + --export / -o yaml |
| `cloud/ali/migrate-plan/plan1/migration-kongdp-explorer.md` | Q |
| `cloud/ali/migrate-plan/plan1/poc-rewrite/before-after-comparison.md` | 迁移前后对比图 |
| `cloud/ali/migrate-plan/plan1/poc-rewrite/externalname-flow.md` | ExternalName Service 工作流程详解 |
| `cloud/ali/migrate-plan/plan1/poc-rewrite/merged-scripts.md` | Shell Scripts Collection |
| `cloud/ali/migrate-plan/plan1/poc-rewrite/poc-analysis.md` | K8s集群迁移POC可行性分析 |
| `cloud/ali/migrate-plan/plan1/poc-rewrite/poc-implementation.md` | POC实施指南 |
| `cloud/ali/migrate-plan/plan1/short-domain-gpt.md` | Q |
| `cloud/ali/migrate-plan/plan1/short-domian-claude.md` | 创建新的命名空间 |
| `cloud/ali/migrate-plan/plan2/migrate-all-dns-record-explorer.md` | summary |

### AWS Documentation

| File Path | Title |
| :--- | :--- |
| `cloud/aws/README.md` | AWS |
| `cloud/aws/docs/README.md` | AWS (Amazon Web Services) 知识库 |
| `cloud/aws/docs/aws-cli.md` | 使用AWS CLI验证S3中的数据 |

### Container/Docker Documentation

| File Path | Title |
| :--- | :--- |
| `cloud/docker/README.md` | Docker 知识库 |
| `cloud/docker/byoc/README.md` | BYOC — Bring Your Own Container |
| `cloud/docker/byoc/best-practices.md` | BYOC Best Practices |
| `cloud/docker/byoc/dockerfile-templates.md` | Dockerfile Templates |
| `cloud/docker/byoc/platforms.md` | BYOC 平台特例 (Platform-specific Notes) |
| `cloud/docker/docs/Dockeffile-user-pass-violation.md` | title: Dockerfile中存在以下几个问题，可能涉及安全性和最佳实践违规 |
| `cloud/docker/docs/Docker-annotations.md` | **1. Problem Analysis** |
| `cloud/docker/docs/Docker-prune.md` | 步骤一：检查磁盘使用情况 |
| `cloud/docker/docs/argo-dex.md` | ➜ ~ docker pull --platform linux/amd64 dexidp/dex:latest |
| `cloud/docker/docs/docker-dex.md` | 保存镜像 |
| `cloud/docker/docs/docker-image-lifecycle.md` | sequenceDiagram |
| `cloud/docker/docs/docker-python.md` | requirements.txt |
| `cloud/docker/docs/docker-sepcial.md` | 设置字符编码 |
| `cloud/docker/docs/docker-utf8.md` | 使用官方的OpenJDK镜像作为基础镜像 |
| `cloud/docker/docs/how-to-mini-dockerfile.md` | 如何构建最小 Docker 镜像 — 全面指南 |
| `cloud/docker/docs/java-version.md` | 添加 Java 版本标签 |
| `cloud/docker/docs/mac-Docker-nas.md` | 要点结论（快速答案） |
| `cloud/docker/docs/merged-scripts.md` | Shell Scripts Collection |
| `cloud/docker/docs/network-multitool.md` | **问题分析** |
| `cloud/docker/docs/utf-8.md` | Q |
| `cloud/docker/multistage-builds/Dockerfile.md` | **问题分析（为何要详细解释这个多阶段 Dockerfile）** |
| `cloud/docker/multistage-builds/distroless.md` | Distroless Container Images |
| `cloud/docker/multistage-builds/migration-guide.md` | Multistage Builds 迁移指南 |
| `cloud/docker/multistage-builds/multi-stage-summary.md` | 多阶段构建 (Multistage Builds) 总结 —— 以 cluster-proxy Dockerfile 为例 |
| `cloud/docker/multistage-builds/multi-stage.md` | ================================ |
| `cloud/docker/multistage-builds/multistage-build-analysis.md` | Multistage Builds 深度分析与实施方案 (Java 应用) |
| `cloud/docker/multistage-builds/multistage-build-concepts.md` | set env |
| `devops/docker/README.md` | Docker 镜像离线打包与压缩 |
| `devops/docker/docs/01-offline-image-packaging.md` | Docker 镜像离线打包与压缩（dexidp/dex 实测） |

### K8s Documentation

| File Path | Title |
| :--- | :--- |
| `cloud/k8s/Mytools/Readme.md` | Kali Linux 安全工具容器 |
| `cloud/k8s/Mytools/kubectl-cmd.md` | 🚀 高效 Kubernetes 管理：Kubectl 核心命令与进阶技巧 |
| `cloud/k8s/README.md` | Kubernetes (k8s) 知识库 |
| `cloud/k8s/busybox/deploy.md` | nas deployment testing |
| `cloud/k8s/busybox/nas-deployment.md` | - nginx-deployment.yaml |
| `cloud/k8s/busybox/nas-service.md` | apiVersion: v1 |
| `cloud/k8s/config/Dockerfile-file-size.md` | 直接下载大文件包 |
| `cloud/k8s/config/Dockerfile-secret.md` | 基础镜像 |
| `cloud/k8s/config/k8s-yaml-format.md` | Kubernetes `kubectl get -o yaml` 导出配置清理与格式化指南 |
| `cloud/k8s/custom-liveness/custom-liveness-gemini.md` | 深度自定义 Kubernetes Liveness Probe 与智能故障切换方案 |
| `cloud/k8s/custom-liveness/explore-startprobe/CHANGELOG.md` | 更新日志 |
| `cloud/k8s/custom-liveness/explore-startprobe/EXAMPLE.md` | 探针配置实战示例 |
| `cloud/k8s/custom-liveness/explore-startprobe/INDEX.md` | Pod Health Check Library - Documentation Index |
| `cloud/k8s/custom-liveness/explore-startprobe/POD_FUN_USAGE_GUIDE.md` | Pod Health Check Library - Usage Guide |
| `cloud/k8s/custom-liveness/explore-startprobe/PROJECT_SUMMARY.md` | Pod Health Check Library - Project Summary |
| `cloud/k8s/custom-liveness/explore-startprobe/QUICK_START.md` | Quick Start - Pod Health Check Library |
| `cloud/k8s/custom-liveness/explore-startprobe/README.md` | Kubernetes 探针配置最佳实践 |
| `cloud/k8s/custom-liveness/explore-startprobe/custom-readme.md` | Kubernetes 自定义存活探针与代理故障转移方案 |
| `cloud/k8s/custom-liveness/explore-startprobe/merged-scripts.md` | Shell Scripts Collection |
| `cloud/k8s/custom-liveness/explore-startprobe/openssl-get-url.md` | 步骤1: 基本连接检查（验证SSL握手和证书） |
| `cloud/k8s/custom-liveness/explore-startprobe/openssl-verify-health.md` | Pod 健康检查通用函数库 |
| `cloud/k8s/custom-liveness/explore-startprobe/pod_measure_enhance.md` | Pod Startup Measurement Script 优化方案 |
| `cloud/k8s/custom-liveness/explore-startprobe/probe-best-practices-eng.md` | GKE Explorer: Best Practices Guide for Probe Configuration |
| `cloud/k8s/custom-liveness/explore-startprobe/probe-best-practices.md` | GKE Explorer: 探针配置最佳实践指南 |
| `cloud/k8s/custom-liveness/explore-startprobe/troubleshooting.md` | GKE 探针故障排查指南 (Troubleshooting Guide) |
| `cloud/k8s/custom-liveness/explore-startprobe/v5_enhancements.md` | Pod Startup Measurement v5 - Enhancements |
| `cloud/k8s/custom-liveness/macos-find-mv.md` | 在当前目录下，将最近 3 天内修改过的普通文件 |
| `cloud/k8s/custom-liveness/user-setting.md` | GKE Pod 探针配置最佳实践指南 |
| `cloud/k8s/debug-pod/README.md` | Kubernetes Pod Debug Scripts |
| `cloud/k8s/debug-pod/copy-file-to-local.md` | 问题分析 |
| `cloud/k8s/debug-pod/cross-pod-debugging.md` | GKE Pod 跨 Pod 调试指南 |
| `cloud/k8s/debug-pod/debug-java-pod.md` | 下面从 GKE / Kubernetes 进程命名空间、kubectl debug 机制、jmap 工作原理 三个层面系统性分析你遇到的问题，并给出可验证的排查步骤与替代方案。 |
| `cloud/k8s/debug-pod/debug-pod-terminal.md` | rollingUpdate: |
| `cloud/k8s/debug-pod/fake-pod.md` | 伪造Deployment中的Pod是可能的吗? |
| `cloud/k8s/debug-pod/optimization-comparison.md` | 脚本优化对比分析 |
| `cloud/k8s/debug-pod/side.md` | 基本用法 |
| `cloud/k8s/debug-pod/sidecar.md` | 获取 Pod A 的 IP 地址 |
| `cloud/k8s/deploy/lifecycle.md` | Kubernetes Lifecycle Hook |
| `cloud/k8s/docs/Blogs-to-Learn-25-Kubernetes-Concepts.md` | 1. Kubernetes Architecture: https://<host>/p/kubernetes-architecture-crash-course |
| `cloud/k8s/docs/Docker-define-apt.md` | 使用最新的 Ubuntu 作为基础镜像 |
| `cloud/k8s/docs/Release-pdb.md` | summary |
| `cloud/k8s/docs/a.md` | A |
| `cloud/k8s/docs/affinity-add-new-logic.md` | old api pod anti-affinity |
| `cloud/k8s/docs/affinity.md` | 提取的K8S Deployment配置 |
| `cloud/k8s/docs/analyse-memory-cpu.md` | 在 GCP 工程中统计资源消耗情况,有多种方式和工具可供选择: |
| `cloud/k8s/docs/appd-init-container.md` | About Start Q |
| `cloud/k8s/docs/base-networkpolicy.md` | Last |
| `cloud/k8s/docs/cm.md` | **📋 ConfigMap 开放风险评估表** |
| `cloud/k8s/docs/codegpt.md` | 关于如何在Helm chart中控制资源的安装顺序。Helm hooks是解决这个问题的有效方法。让我为您详细解释Helm hooks的用法,并提供相应的YAML配置示例。 |
| `cloud/k8s/docs/configmap-daemon.md` | configmap |
| `cloud/k8s/docs/configmap.md` | GKE 平台开放用户自定义 ConfigMap 的风险评估 |
| `cloud/k8s/docs/container-pod.md` | 容器（Container） |
| `cloud/k8s/docs/container-watcher.md` | 1. 核心作用与功能 |
| `cloud/k8s/docs/context-path.md` | 平台统一 Context Path 注入策略 — 评估与可行性分析 |
| `cloud/k8s/docs/cronjob.md` | CronJob 状态 |
| `cloud/k8s/docs/deploy-type.md` | Kubernetes 资源部署方式区分 |
| `cloud/k8s/docs/deployment-error.md` | 这个错误消息表示 kubectl 正在尝试应用一个 Kubernetes 对象，该对象的 labels 字段是一个数字，但 labels 字段要求是字符串。 |
| `cloud/k8s/docs/deployment2.md` | CI flow |
| `cloud/k8s/docs/detail-deployment.md` | summary |
| `cloud/k8s/docs/docker-images-labels.md` | gemini |
| `cloud/k8s/docs/dynamic-pdb.md` | Q |
| `cloud/k8s/docs/edit-deployment.md` | 在Kubernetes中，当修改一个已经应用或运行的Deployment 时，哪些修改会直接生效，我需要一个详细的 资源对比说明 哪些会生锈？哪些不会生效 |
| `cloud/k8s/docs/egress.md` | 第一个NetworkPolicy |
| `cloud/k8s/docs/endpoint.md` | **1. 关键概念简介** |
| `cloud/k8s/docs/enhance-pod-start.md.md` | 使用 xargs 并行解密8个文件 |
| `cloud/k8s/docs/enhance-probe.md` | SeqDigram |
| `cloud/k8s/docs/etcd.md` | 1. **etcd 存储了什么信息？** |
| `cloud/k8s/docs/evict.md` | calude |
| `cloud/k8s/docs/except.md` | 使用except_section替换您的网络策略中的except部分 |
| `cloud/k8s/docs/fack-pod.md` | 伪造Deployment中的Pod是可能的吗? |
| `cloud/k8s/docs/filter-namespace.md` | 获取所有的namespace |
| `cloud/k8s/docs/flow-dns.md` | flow |
| `cloud/k8s/docs/flow-pdb.md` | Why and current status |
| `cloud/k8s/docs/get-ns-dep.md` | 获取所有的 namespace，但排除以 "kube-" 开头的系统 namespace |
| `cloud/k8s/docs/gke-deployment-appd-no-root.md` | wrap ai |
| `cloud/k8s/docs/gke-networkpolicy-except.md` | 是的,这是 CIDR 网络划分的一个重要特点。 |
| `cloud/k8s/docs/gke-sa.md` | summary |
| `cloud/k8s/docs/gke-upgrade.md` | flowchart TB |
| `cloud/k8s/docs/helm-best-practices.md` | **Helm 实战指南：复杂环境下的配置治理与全局变更控制** |
| `cloud/k8s/docs/helm-hook.md` | claude3.5 |
| `cloud/k8s/docs/helm-squid.md` | Squid Helm Chart |
| `cloud/k8s/docs/helm.md` | PDB 资源解析逻辑 |
| `cloud/k8s/docs/hostalias.md` | 在 Google Kubernetes Engine (GKE) 中， |
| `cloud/k8s/docs/housekeep.md` | summary |
| `cloud/k8s/docs/hpa-poc-cpu-memory.md` | value: "192.168.192.51:443" |
| `cloud/k8s/docs/hpa-replicas.md` | gemini |
| `cloud/k8s/docs/hpa-size-alert.md` | Description |
| `cloud/k8s/docs/hpa-size.md` | Chatgpt |
| `cloud/k8s/docs/hpa-with-maxunavailable.md` | 根据搜索结果和我的理解,HPA(Horizontal Pod Autoscaler)的一些常见最佳实践包括: |
| `cloud/k8s/docs/hpa.md` | Deployment YAML |
| `cloud/k8s/docs/ingress.md` | K8S中使用Ingress进行流量管理的架构流程如下: |
| `cloud/k8s/docs/intcontainer-container.md` | summary |
| `cloud/k8s/docs/job.md` | 在GKE的生产环境中，如果禁止了直接登录 Pod，可以通过以下方法测试一个域名是否能够被访问或解析，并将测试结果推送到日志系统供 Log Explorer 分析。以下是具体的解决方案： |
| `cloud/k8s/docs/k8s-cluster-secret.md` | cluster_secret |
| `cloud/k8s/docs/k8s-exec.md` | role-no-exec.yaml |
| `cloud/k8s/docs/k8s-export-secret.md` | **方式一：导出后用** |
| `cloud/k8s/docs/k8s-feature.md` | K8S Feature |
| `cloud/k8s/docs/k8s-get-Replicas.md` | K8S Deployment Replicas 对比方案 |
| `cloud/k8s/docs/k8s-pod-stat-completed.md` | 好的，我们来一起排查 GKE 中 Kong 3.4 版本 Helm 安装后出现大量 `Completed` 状态 Pod 的问题。 |
| `cloud/k8s/docs/k8s-request-limit.md` | GKE Pod 资源调度机制详解 |
| `cloud/k8s/docs/k8s-request.md` | **🧠 基本概念回顾** |
| `cloud/k8s/docs/k8s-resource-summary.md` | ---------------------------------------------------------- |
| `cloud/k8s/docs/k8s-scale/k8s-resouce-autoscale-chatgpt.md` | Kubernetes Requests/Limits、调度默认行为与 Autoscaling（场景推演） |
| `cloud/k8s/docs/k8s-scale/k8s-resouce-autoscale.md` | Kubernetes 资源调度与自动扩缩容深度解析 |
| `cloud/k8s/docs/k8s-scale/scale-deploy.md` | Claude |
| `cloud/k8s/docs/kill-pod.md` | 流量分配和恢复过程 |
| `cloud/k8s/docs/kube-crd.md` | crd chatgpt |
| `cloud/k8s/docs/kube-neat.md` | **🚀 什么是 kube-neat？** |
| `cloud/k8s/docs/kube-path-hpa.md` | 对于K8S来说 动态通过patch的方式更新HPA中replicas的值,会引起Deployment下的Pod重新启动么? 是不是这个replicas是非模版字段,并不会触发 Rollout ? |
| `cloud/k8s/docs/kubectl-event.md` | Kubernetes 事件 |
| `cloud/k8s/docs/lex-poc-hpa-cpu-memory.md` | value: "192.168.192.51:443" |
| `cloud/k8s/docs/liveless-simple.md` | 🎯 你的问题总结 |
| `cloud/k8s/docs/liveness.md` | Kubernetes Liveness Probe implementation |
| `cloud/k8s/docs/memory-recycle.md` | 释放缓存 |
| `cloud/k8s/docs/mini-change.md` | Minimal Platform Adaptation Strategy (Mini-Change) |
| `cloud/k8s/docs/netd.md` | 1. 核心作用与主要功能 |
| `cloud/k8s/docs/networkpolicy-egress-svc.md` | summary |
| `cloud/k8s/docs/networkpolicy.md` | Q |
| `cloud/k8s/docs/netwrokpolicy.md` | Last |
| `cloud/k8s/docs/no-medata.md` | continue with normal code for accessing metadata |
| `cloud/k8s/docs/no-root-deployment.md` | summary |
| `cloud/k8s/docs/node-pool-name.md` | 如果想使用gcloud命令仅打印GKE节点池名称,可以使用以下方法: |
| `cloud/k8s/docs/nodepool-deployment.md` | GKE 多 NodePool 部署选型实践 |
| `cloud/k8s/docs/non-root.md` | 创建john用户 |
| `cloud/k8s/docs/openshift-overview.md` | OpenShift 入门 — Red Hat 的企业级 Kubernetes 平台 |
| `cloud/k8s/docs/pdb-core.md` | thinking |
| `cloud/k8s/docs/pdb-effect.md` | 在保障高可用性的同时避免因 PDB 配置和异常 Pod 状态阻碍集群升级流程 |
| `cloud/k8s/docs/pdb-namespace.md` | Summary |
| `cloud/k8s/docs/pdb-time.md` | 示例：即使配置了严格的 PDB 也会受 1 小时限制 |
| `cloud/k8s/docs/pdb.md` | 使用 PodDisruptionBudget 的步骤和方法 |
| `cloud/k8s/docs/pod-Encryption.md` | **🔒 GKE 集群内通信的加密情况** |
| `cloud/k8s/docs/pod-annotations.md` | summary |
| `cloud/k8s/docs/pod-lifecycle.md` | Pod 的终止 |
| `cloud/k8s/docs/pod-restart.md` | 获取Pod的数量 |
| `cloud/k8s/docs/pod-sigterm.md` | sigterm 信号的时间 |
| `cloud/k8s/docs/pod-start.md` | 好的，要获取一个命名空间下所有正在运行的 Pod 的详细时间信息，可以使用以下命令组合，以满足不同程度的详细需求： |
| `cloud/k8s/docs/pod-system-version.md` | GKE Pod 系统版本查询脚本 |
| `cloud/k8s/docs/pod-write-data-gemini.md` | 在GKE生产环境中管理并发数据库写入：策略与解决方案 |
| `cloud/k8s/docs/pod-write-data.md` | Claude4 |
| `cloud/k8s/docs/readiness.md` | Liveness 和 Readiness 探测 |
| `cloud/k8s/docs/redis.md` | Whitelist setting |
| `cloud/k8s/docs/replicaset.md` | 1. 手动配置 |
| `cloud/k8s/docs/res.md` | 输出 |
| `cloud/k8s/docs/role.md` | role Debug |
| `cloud/k8s/docs/rolling+affinity+pdb.md` | Q |
| `cloud/k8s/docs/secret-enhance.md` | GKE Deployment |
| `cloud/k8s/docs/set-image.md` | chatgpt |
| `cloud/k8s/docs/strategy.md` | 关键配置参数 |
| `cloud/k8s/docs/stress.md` | 要增加GKE中的Pod的内存占用率以触发Horizontal Pod Autoscaler (HPA)，您可以通过在Pod中执行一些内存密集型操作来模拟内存使用情况。以下是一些可能的方法： |
| `cloud/k8s/docs/summary-affinity.md` | summary |
| `cloud/k8s/docs/syncloop-status.md` | 在 GKE 中，kubelet 的日志包含了很多与容器健康检查（Probe）相关的信息，其中包括 SyncLoop 的状态。这些日志信息通常指的是 K8S 内部 kubelet 的健康检查和状态同步过程。具体的 SyncLoop 会执行多种任务，其中与 Pod 健康检查相关... |
| `cloud/k8s/docs/temp-stop-pdb.md` | 问题分析 |
| `cloud/k8s/docs/terminationGracePeriodSeconds.md` | Pod 的终止 |
| `cloud/k8s/docs/trigger-appd.md` | summary |
| `cloud/k8s/docs/update-images.md` | 1. kubectl set image |
| `cloud/k8s/docs/verify-kube-dns.md` | Verify kube-dns working |
| `cloud/k8s/docs/verify-namespace-label.md` | ============================================================================= |
| `cloud/k8s/docs/what-is-dnsendpoint.md` | DNSEndpoint 是什么：原理、边界与在 HGKE 中的用法 |
| `cloud/k8s/docs/why-context.md` | 限制容器的权限 |
| `cloud/k8s/docs/why-needhttps-intra-ns.md` | 在多租户（multi-tenant）Kubernetes 集群中，尤其是同一个 namespace 中部署了不同用户的服务时，将 Deployment 中的 livenessProbe、readinessProbe 或 startupProbe 使用 HTTPS 协议而不是... |
| `cloud/k8s/hpa/cpu-and-memory-bak.md` | Horizontal Pod Autoscaler (HPA) 详解 |
| `cloud/k8s/hpa/cpu-and-memory-corrected-en.md` | Horizontal Pod Autoscaler (HPA) Detailed Explanation - Revised and Enhanced Version |
| `cloud/k8s/hpa/cpu-and-memory-corrected.md` | Horizontal Pod Autoscaler (HPA) 详解 - 修正与增强版 |
| `cloud/k8s/hpa/cpu-and-memory-explor-qwen.md` | Horizontal Pod Autoscaler (HPA) 详解 - 修正与增强版 |
| `cloud/k8s/hpa/cpu-and-memory-github.md` | Horizontal Pod Autoscaler (HPA) 详解 - GitHub兼容版 |
| `cloud/k8s/hpa/cpu-and-memory.md` | Horizontal Pod Autoscaler (HPA) 详解 |
| `cloud/k8s/hpa/cpu-sort.md` | Horizontal Pod Autoscaler (HPA) 详解 |
| `cloud/k8s/hpa/hpa-3-4-memory.md` | K8S HPA 扩容触发点计算 |
| `cloud/k8s/hpa/hpa-core.md` | 公式 |
| `cloud/k8s/hpa/hpa-cpu-and-memory-en.md` | Horizontal Pod Autoscaler (HPA) Explained - Corrected and Enhanced Version |
| `cloud/k8s/hpa/hpa-other.md` | other |
| `cloud/k8s/hpa/hpa-reduce.md` | HPA 描述输出分析 |
| `cloud/k8s/hpa/hpa-tye-change.md` | 回答问题 |
| `cloud/k8s/hpa/hpa-type.md` | 扩容和缩容的详细逻辑 |
| `cloud/k8s/hpa/kong-spread-ha-review-claude.md` | Kong PRD 拓扑配置评审（忽略 Node 数量瓶颈） |
| `cloud/k8s/hpa/kong-spread-ha-review-muse-eng.md` | Kong PRD High-Availability Configuration Review: Spread Results (Muse Revision) |
| `cloud/k8s/hpa/kong-spread-ha-review-muse.md` | Kong PRD 高可用配置评审：分布结果（Muse 修正版） |
| `cloud/k8s/hpa/kong-spread-ha-review.md` | Kong PRD 高可用配置评审：跨 Zone 分布 / PDB / HPA 协同分析 |
| `cloud/k8s/hpa/memory-hpa.md` | 现在参考下面这一部分的说明也是我经过实际测试的结果 |
| `cloud/k8s/hpa/min-max-replicas.md` | Deployment |
| `cloud/k8s/hpa/pdb-multi-zone-spread-ha.md` | 多 Zone 高可用设计：Pod 分布约束 + PDB 的正确组合 |
| `cloud/k8s/hpa/reasonable.md` | vim 技巧 |
| `cloud/k8s/hpa/resouce.md` | deployment |
| `cloud/k8s/hpa/summary-hpa-last.md` | Summary: Kubernetes HPA Scaling Logic (Revised) |
| `cloud/k8s/hpa/summary-hpa.md` | HPA 扩缩容算法与容忍度解析 |
| `cloud/k8s/images/Housekeep-imagepullsecrets.md` | Housekeep ImagePullSecrets |
| `cloud/k8s/images/imagePullSecrets.md` | - reference |
| `cloud/k8s/images/images-pull-time.md` | GKE Pod Image Pull Time Exploration |
| `cloud/k8s/images/k8s-image-replace-usage.md` | K8s 镜像替换脚本使用说明 |
| `cloud/k8s/images/k8s-img-replace.md` | **问题分析** |
| `cloud/k8s/images/merged-scripts.md` | Shell Scripts Collection |
| `cloud/k8s/images/molo.md` | 一句话定位对比 |
| `cloud/k8s/k8s-gateway/DestinationRule-insecureSkipVerify.md` | DestinationRule TLS: `insecureSkipVerify` 与 SIMPLE 模式字段详解 |
| `cloud/k8s/k8s-gateway/DestinationRule.md` | DestinationRule 深度探索 |
| `cloud/k8s/k8s-gateway/change-rule-name.md` | NetworkPolicy 命名规范对照表 |
| `cloud/k8s/k8s-gateway/explorer-k8s-gateway-timeout.md` | K8s Gateway API 超时机制探索文档 (Explorer) |
| `cloud/k8s/k8s-gateway/k8s-gateway-api-report.md` | Kubernetes Gateway API 深度分析报告 |
| `cloud/k8s/k8s-gateway/k8s-gateway-cert-manager-letsencrypt-wildcard.md` | K8s Gateway + cert-manager + Let's Encrypt Wildcard 跨 NSS HTTPS 落地 |
| `cloud/k8s/k8s-gateway/k8s-gateway-e2e/K8S-GATEWAY-E2E-VERIFY-MONITOR-PLAN.md` | K8s Gateway API — E2E Verification & Monitoring Plan |
| `cloud/k8s/k8s-gateway/k8s-gateway-e2e/README.md` | chatgpt |
| `cloud/k8s/k8s-gateway/k8s-gateway-e2e/k8s-gateway-fqdn-minimax.md` | ============================================================================= |
| `cloud/k8s/k8s-gateway/k8s-gateway-e2e/merged-scripts.md` | Shell Scripts Collection |
| `cloud/k8s/k8s-gateway/k8s-gateway-netpol.md` | requirement |
| `cloud/k8s/k8s-gateway/k8s-gateway-timeout.md` | K8s Gateway API 超时配置指南 |
| `cloud/k8s/k8s-gateway/public-fqdn-explorer.md` | public-fqdn-explorer — Tenant→Master 跨项目 + Nginx 路径分流全栈探索 |
| `cloud/k8s/k8s-gateway/tenant-namespace-k8s-gateway.md` | ListenerSet 多租户配置指南 |
| `cloud/k8s/k8s-gateway/tenant-namespace-newapi-team1-appdev-aibang.md` | tenant-namespace-newapi-team1-appdev-aibang |
| `cloud/k8s/k8s-scale/README.md` | Kubernetes Resource Optimization Tool |
| `cloud/k8s/k8s-scale/about-restore.md` | 查看所有被缩减的 deployment |
| `cloud/k8s/k8s-scale/maxSurge.md` | GKE Deployment RollingUpdate 参数设计分析 |
| `cloud/k8s/k8s-scale/merged-scripts.md` | Shell Scripts Collection |
| `cloud/k8s/k8s-scale/scale-deployment.md` | **✅** |
| `cloud/k8s/k8s-scale/walkthrough.md` | Walkthrough - Kubernetes Resource Optimization Script (Bash Version) |
| `cloud/k8s/k8s-tls-Opaque.md` | Kubernetes TLS Secret vs Opaque Secret 完全对比 |
| `cloud/k8s/labels/Labels-TODO.md` | reference |
| `cloud/k8s/labels/add/00_workflow.md` | Automation Workflow: Batch Add Labels to Deployments |
| `cloud/k8s/labels/add/Explorer-labels.md` | 方案规划分析 |
| `cloud/k8s/labels/add/add-ns-labels.md` | verify-ns-labels.sh |
| `cloud/k8s/labels/add/merged-scripts.md` | Shell Scripts Collection |
| `cloud/k8s/labels/labels-best-practices.md` | Kubernetes 标签（Labels）最佳实践 |
| `cloud/k8s/labels/labels.md` | Kubernetes Pod 的标签（labels）通常是由以下因素决定的： |
| `cloud/k8s/labels/merged-scripts.md` | Shell Scripts Collection |
| `cloud/k8s/labels/metadata-labels.md` | ✅ **一次性增加多个 metadata.labels（安全，不触发滚动更新）** |
| `cloud/k8s/labels/reademe.md` | 修改脚本中的配置 |
| `cloud/k8s/lib/CHANGELOG.md` | Changelog - Pod Health Check Library |
| `cloud/k8s/lib/COMMAND_PATHS.md` | Command Path Configuration |
| `cloud/k8s/lib/CRITICAL_BUG_FIX.md` | Critical Bug Fix - PATH Variable Collision |
| `cloud/k8s/lib/MACOS_FIX.md` | macOS Compatibility Fix Guide |
| `cloud/k8s/lib/README.md` | Kubernetes Library Functions |
| `cloud/k8s/lib/TROUBLESHOOTING.md` | Troubleshooting |
| `cloud/k8s/migrate/ how-to-migrate-ns.md` | Summary |
| `cloud/k8s/migrate/How-to-migrate-cluster.md` | 导出集群描述（A工程） |
| `cloud/k8s/networkpolicy/Routes-based-LLM.md` | 第一部分：内容准确性验证 |
| `cloud/k8s/networkpolicy/Routes-based.md` | Routes-based 模式下的网络流量详解 |
| `cloud/k8s/networkpolicy/base-networkpolicy-egress-ingress.md` | GKE Routes-based 模式完整网络策略配置 |
| `cloud/k8s/networkpolicy/cross-namespace.md` | 跨 Namespace 网络策略配置分析 |
| `cloud/k8s/networkpolicy/debug-ns-networkpolicy.md` | NetworkPolicy 跨 Namespace 通信 Debug 指南 |
| `cloud/k8s/networkpolicy/ebpf.md` | Kubernetes Networking Game-Changer: An Introduction to eBPF |
| `cloud/k8s/networkpolicy/explorer-gateway-networkpolicy.md` | Gateway-Namespace 跨 Namespace 网络策略配置分析 |
| `cloud/k8s/networkpolicy/gateway-ns-cross-ns.md` | Gateway-namespace 跨 namespace 网络策略配置分析 |
| `cloud/k8s/networkpolicy/gke-ns-networkpolicy.md` | 允许访问特定 namespace |
| `cloud/k8s/networkpolicy/name-define.md` | Default: default-(deny|allow)-(ingress|egress)-{source or target svc} |
| `cloud/k8s/networkpolicy/network-node-ip.md` | 完全理解了！您说得对！ |
| `cloud/k8s/networkpolicy/network-ns-ns-flow.md` | GKE 跨 Namespace 网络访问完整流程图 |
| `cloud/k8s/networkpolicy/network-ns-ns.md` | Claude |
| `cloud/k8s/networkpolicy/networkpolicy-dns.md` | Istio 网格内 DNS 解析与服务发现机制 |
| `cloud/k8s/networkpolicy/networkpolicy-l34-l7.md` | NetworkPolicy L3/L4/L7 In GKE And Managed Service Mesh |
| `cloud/k8s/networkpolicy/networkpolicy-node-pod.md` | Why |
| `cloud/k8s/networkpolicy/networkpolicy-ns-ns-gemini.md` | GKE 跨 Namespace 通信：NetworkPolicy 与 Node IP 解惑 |
| `cloud/k8s/qnap-k8s/README.md` | QNAP Kubernetes 部署脚本 |
| `cloud/k8s/scripts/kubectl-logs.md` | Kubernetes Pod 日志查看工具 |
| `cloud/k8s/scripts/merged-scripts.md` | Shell Scripts Collection |
| `cloud/k8s/scripts/pod_exec.md` | Set color output |
| `cloud/k8s/scripts/pod_measure_startup_fixed.md` | ➜ scripts git:(main) ./pod_measure_startup_fixed.sh -n lex nginx-deployment-854b5bc678-m428j |
| `cloud/k8s/vpa/how-to-setting-vpa-value.md` | 您的理解**基本正确**，但需要稍作精确化以更贴合 Kubernetes VPA 的工作机制。我们可以这样更严谨地表述： |
| `cloud/k8s/vpa/vpa-concept.md` | **1. 什么是垂直扩展（Vertical Scaling）** |
| `cloud/k8s/vpa/vpa-config.md` | GKE 中垂直 Pod 自动扩展器 (VPA) 与 Deployment 内存配置的精确对应关系分析 |

### CI/CD Pipeline Documentation

| File Path | Title |
| :--- | :--- |
| `develop/pipeline/README.md` | Pipeline 知识库 |
| `develop/pipeline/cd-pipeline/Namespace_Ingress_Policy.md` | Namespace & Ingress 标准化策略 |
| `develop/pipeline/cd-pipeline/PMU_Checklist.md` | PMU (Platform Management Unit) 校验 Checklist |
| `develop/pipeline/cd-pipeline/Reademe.md` | **🧩 1. 问题分析** |
| `develop/pipeline/cd-pipeline/get-container.md` | 获取 Deployment Container 名称的方法 |
| `develop/pipeline/cd-pipeline/image-replace.md` | K8s Image Replace 脚本优化方案 |
| `develop/pipeline/cd-pipeline/implementation_plan.md` | Implementation Plan - Refactor CD Pipeline (No Kustomize) |
| `develop/pipeline/cd-pipeline/migrate-pipeline-develop.md` | Q |
| `develop/pipeline/cd-pipeline/pipeline-cd-claude.md` | Pipeline 改造方案分析 |
| `develop/pipeline/cd-pipeline/pipeline-cd-gemini.md` | ========================================== |
| `develop/pipeline/cd-pipeline/walkthrough.md` | CD Pipeline Demo Walkthrough (Refactored) |
| `develop/pipeline/docs/copy-pipeline.md` | q |
| `develop/pipeline/docs/housekeep-sms.md` | Script for scan secret |
| `develop/pipeline/docs/insert-json.md` | Q |
| `develop/pipeline/docs/master-branch.md` | 检查各团队 pipeline 配置中的 shared library 分支信息 |
| `develop/pipeline/docs/oidc.md` | OIDC |
| `develop/pipeline/docs/osapath.md` | 主要概念 |
| `develop/pipeline/docs/pipeline-flow.md` | 1️⃣ 问题分析（Flow 的核心） |
| `develop/pipeline/docs/pipeline-layer.md` | 在基于Groovy开发的Pipeline设计中，将source code 按照 Job Layer、Stage Layer 和 Module Layer 进行分层设计，可以带来以下几个好处： |
| `develop/pipeline/docs/sonar.md` | GitHub Actions 示例 |
| `develop/pipeline/docs/stash.md` | 概念 |
| `develop/pipeline/docs/trigger-pipeline-gemini.md` | 在 Pull Request (PR) 创建时自动触发 CI 测试 |
| `develop/pipeline/docs/trigger-pipeline.md` | **一、用户的需求分析** |
| `develop/pipeline/release-dashboard/README.md` | Release Dashboard |
| `develop/pipeline/release-dashboard/Release-Readme.md` | meeting |
| `develop/pipeline/release-dashboard/Release-pipeline.md` | 主要特性说明 |

### DevOps/Platform Documentation

| File Path | Title |
| :--- | :--- |
| `devops/buildpacks/README.md` | Buildpacks / CNB 生态 |
| `devops/buildpacks/imgutil.md` | buildpacks/imgutil —— CNB 生态的镜像操作库 |
| `devops/hermes-bot-team/README.md` | GCP 平台工程 — Hermes 4-Bot 团队 |
| `devops/hermes-bot-team/usage.md` | 4-Bot 团队使用指南 |
| `devops/hermes-perf/hermes-slow-and-token-burn-solutions.md` | Hermes 性能与 Token 消耗：诊断结论与解决方案 |
| `devops/kubeops/README.md` | KubeOps — 概念、工作原理与 GitHub push → K8s 交付链路 |
| `devops/kubeops/docs/01-what-is-kubeops.md` | 01 — KubeOps 是什么(含同名项目消歧) |
| `devops/kubeops/docs/02-how-it-works.md` | 02 — 工作原理:Reconcile Loop 与事件管线 |
| `devops/kubeops/docs/03-github-push-to-k8s-flow.md` | 03 — 那个场景:GitHub push → Worker follow 流 → K8s 部署 |
| `devops/kubeops/docs/04-delivery-paradigms.md` | 04 — 交付范式对比与选型决策 |
| `devops/kubeops/docs/05-hands-on.md` | 05 — 动手实践:最小可运行 Operator 与 GitHub 交付链路 |

### GitOps / Argo CD Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/ucp/Kustomize.md` | Kustomize × Argo CD |
| `gcp/ucp/README.md` | UCP · 统一控制平面（Argo CD × Crossplane） |
| `gcp/ucp/Tekoncd.md` | Tekton（tektoncd）是什么 |
| `gcp/ucp/argo-api-claude.md` | Argo CD v3.5.6 API 接口清单 |
| `gcp/ucp/argocd-admin-guide.md` | Argo CD 进阶用法与管理员手册 |
| `gcp/ucp/argocd-api.md` | Argo CD v3.5.6 API 接口参考 |
| `gcp/ucp/argocd-application-guide.md` | Argo CD `Application` 资源详解（v3.5.6） |
| `gcp/ucp/argocd-applicationset-vs-application.md` | Argo CD：`ApplicationSet` vs `Application` 对比 |
| `gcp/ucp/argocd-cli-guide.md` | Argo CD CLI 实战手册（v3.5.6） |
| `gcp/ucp/argocd-topics/00-architecture-no-crossplane.md` | 00 · 总体架构与决策记录 |
| `gcp/ucp/argocd-topics/01-redis-persistence.md` | 01 · Redis 与持久化 |
| `gcp/ucp/argocd-topics/02-ha.md` | 02 · 高可用架构 |
| `gcp/ucp/argocd-topics/03-dex-ldap-sso.md` | 03 · SSO 身份打通：OIDC 直连 / Dex + OIDC / Dex + LDAP |
| `gcp/ucp/argocd-topics/04-appproject-rbac.md` | 04 · AppProject 与权限模型 |
| `gcp/ucp/argocd-topics/05-appset.md` | 05 · ApplicationSet 批量分发 |
| `gcp/ucp/argocd-topics/06-opa-gatekeeper-impact.md` | 06 · OPA 与 Gatekeeper 对 Argo CD 的影响面 |
| `gcp/ucp/argocd-topics/07-repository-githubapp.md` | 07 · Repository 凭据、GitHub App 与目标分支 |
| `gcp/ucp/argocd-topics/08-implementation-playbook.md` | 08 · 实施顺序与验收手册 |
| `gcp/ucp/argocd-topics/09-troubleshooting.md` | 09 · 排障手册 |
| `gcp/ucp/argocd-topics/10-argo-workflows-evaluation.md` | 10 · Argo Workflows：概念梳理与引入评估 |
| `gcp/ucp/argocd-topics/11-github-app-concepts.md` | 11 · GitHub App 概念梳理（Public Link / Home URL / Webhook URL / 源码在哪）＋ 生产变更加闸 |
| `gcp/ucp/argocd-topics/Develop-git-apps.md` | Develop-git-apps · 自研 GitHub App：可行性评估、运行原理与实现路径 |
| `gcp/ucp/argocd-topics/README.md` | Argo CD 专题文档 |
| `gcp/ucp/argocd-topics/appset-helm-Rendering.md` | 06 · ApplicationSet 的 Helm 渲染（CP 仓库 → Tenant 仓库） |
| `gcp/ucp/argocd-topics/argo-concept-sheet.md` | Argo CD 概念速查表（Concept Sheet） |
| `gcp/ucp/argocd-topics/argo-event.md` | Argo Events 是什么 · 事件驱动自动化的最小认知 |
| `gcp/ucp/argocd-topics/examples/README.md` | examples/ · 可复制示例 ＋ 静态检查工具箱 |
| `gcp/ucp/argocd-topics/examples/appset-helm/README.md` | 示例：ApplicationSet 由 Helm 渲染（CP 仓库 → Tenant 仓库） |
| `gcp/ucp/argocd-topics/examples/gitops-layout/README.md` | Argo CD · GitOps 仓库骨架示例（bootstrap + 组件 + 集群清单） |
| `gcp/ucp/argocd-topics/examples/gitops-layout/bootstrap-flow.md` | Argo CD · Bootstrap 完整流程图（从 PR 到集群） |
| `gcp/ucp/argocd-topics/examples/gitops-layout/bootstrap/README.md` | bootstrap/ · 引导层（Bootstrap Layer） |
| `gcp/ucp/argocd-topics/examples/gitops-layout/bootstrap/clusters/README.md` | bootstrap/clusters/ · 集群清单（Cluster Manifest） |
| `gcp/ucp/argocd-topics/examples/rulesets-enterprise/00-enterprise-capabilities.md` | 00 · 企业版能力矩阵（哪些 rule type 要什么条件） |
| `gcp/ucp/argocd-topics/examples/rulesets-enterprise/README.md` | examples/rulesets-enterprise/ · GitHub Enterprise 版的规则集（组织级治理） |
| `gcp/ucp/argocd-topics/examples/rulesets-enterprise/enterprise-rollout.md` | 企业版落地 Runbook（从"什么都没有"到"全组织生效"） |
| `gcp/ucp/argocd-topics/examples/rulesets-enterprise/personal-vs-enterprise.md` | 个人版 ↔ 企业版 · 差异对照（差距是什么 / 值不值 / 怎么部署） |
| `gcp/ucp/argocd-topics/examples/rulesets/06-dev-branch-guard-x-cr-prefix-action.md` | 06 Ruleset × `cr-prefix` Action 联合工作详解 |
| `gcp/ucp/argocd-topics/examples/rulesets/README.md` | examples/rulesets/ · GitHub Rulesets 可落地配置 ＋ 契约静态检查 |
| `gcp/ucp/argocd-topics/examples/rulesets/ruleset-action-sample.md` | Ruleset × Action 全套实验手册（`ruleset-action-sample`） |
| `gcp/ucp/argocd-topics/git-apps/11-github-app-concepts.md` | 11 · GitHub App 概念梳理（Public Link / Home URL / Webhook URL / 源码在哪）＋ 生产变更加闸 |
| `gcp/ucp/argocd-topics/git-apps/12-webhook-push-vs-pull.md` | 12 · 外部接口交互模型的变化：从「拉（pull）」到「推（push）」 |
| `gcp/ucp/argocd-topics/git-apps/13-cr-check-go-design.md` | 13 · CR Check（Go）的设计与实现评估 |
| `gcp/ucp/argocd-topics/git-apps/14-rulesets-and-gitapp-gate.md` | 14 · GitHub Rulesets × GitHub App：合并门禁怎么落地（零基础 → 最佳实践） |
| `gcp/ucp/argocd-topics/git-apps/15-commit-message-cr-prefix.md` | 15 · 最小示例：commit message 必须以 `CR123456` 开头（Ruleset 怎么配） |
| `gcp/ucp/argocd-topics/git-apps/16-ruleset-install-runbook.md` | 16 · Ruleset 安装与生效 Runbook（从 JSON 到"真的拦住 merge"） |
| `gcp/ucp/argocd-topics/git-apps/17-probot-apps.md` | 11 · Probot 是什么 |
| `gcp/ucp/argocd-topics/git-apps/Develop-git-apps.md` | Develop-git-apps · 自研 GitHub App：可行性评估、运行原理与实现路径 |
| `gcp/ucp/argocd-topics/git-apps/README.md` | git-apps/ · 自研 GitHub App（CR Check）专题 |
| `gcp/ucp/argocd-topics/git-apps/cr-check/README.md` | CR Check · Go 实现 |
| `gcp/ucp/argocd-topics/git-apps/webhook-and-backend-service.md` | Webhook 与后端服务 · CR Check 这个 GitHub App 到底怎么工作 |
| `gcp/ucp/argocd-topics/helm-cross-repository.md` | 07 · 跨仓库渲染的原理 |
| `gcp/ucp/argocd-topics/how-to-atomic-idempotency.md` | how-to-atomic-idempotency · 开发 GitHub App（如 CR Check）时的原子性与幂等性 |
| `gcp/ucp/argocd-topics/how-to-using-git-apps.md` | how-to-using-git-apps · 装好 GitHub App 之后，我的仓库到底怎么用它 |
| `gcp/ucp/argocd-topics/install-git-apps.md` | install-git-apps · 在 Org / 仓库上安装 GitHub App 的操作指引 |
| `gcp/ucp/argocd-topics/prow-pulls.md` | 从 kubernetes-sigs/prow 的 PR 管理机制，看 GitHub 门禁该怎么设计 |
| `gcp/ucp/argocd-topics/session-token-usage.md` | 会话 Token 用量报告 |
| `gcp/ucp/argocd-topics/sigs.md` | sigs · Kubernetes SIGs 生态地图，以及我们能借鉴什么 |
| `gcp/ucp/argocd-topics/webhook-and-backend-service.md` | Webhook 与后端服务 · CR Check 这个 GitHub App 到底怎么工作 |
| `gcp/ucp/examples/argocd-application/README.md` | Application 示例集 |
| `gcp/ucp/flux.md` | Argo CD vs Flux：选型对比（面向 UCP 场景） |
| `gcp/ucp/how-to-manual-build-argocd-windows.md` | 在 Windows 上安装 Argo CD CLI（`go install` 不可用时的完整方案） |
| `gcp/ucp/kustomize-concept.md` | Kustomize 入门手册（面向 ArgoCD 使用者） |
| `gcp/ucp/next-steps-roadmap.md` | UCP · 下一步知识探索路线图 |
| `gcp/ucp/poc-argocd-git-to-apply-trigger.md` | ArgoCD Git → Apply 触发链路详解 |
| `gcp/ucp/poc-argocd-integration.md` | ArgoCD × Crossplane 集成链路详解 |
| `gcp/ucp/poc-minimax.md` | UCP 统一云平台 (Unified Cloud Platform) — Crossplane PoC 方案 |
| `gcp/ucp/poc.md` | 执行前请确认当前 gcloud 项目和账号，替换所有大写变量 |
| `gcp/ucp/probot.md` | Probot 是什么 |
| `gcp/ucp/requirement.md` | requirement |

### GCP ASM/Istio Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/asm/3-add-mesh.md` | 在现有 PSC NEG 架构上引入 Cloud Service Mesh（Master Project） |
| `gcp/asm/3-tenant-project.md` | 跨项目 PSC NEG — Tenant Project (Project A) 完整资源创建指南 |
| `gcp/asm/3-thinking.md` | 1. 中文翻译 |
| `gcp/asm/3.md` | 跨项目 PSC NEG 实现方案 |
| `gcp/asm/Evaluation-istio-http.md` | Istio 架构下应用端口自定义评估报告 (Evaluation-istio-http) |
| `gcp/asm/ServiceEntry.md` | summary |
| `gcp/asm/asm-2.md` | Todo: |
| `gcp/asm/asm-explorer.md` | 下面基于你当前的平台规模与诉求（ASM + Fleet + 多 GCP Project + 大规模 API 管理），给你一个可落地、可扩展、可治理的整体方案视角，而不是只停留在“怎么开 ASM”。 |
| `gcp/asm/asm-flow.md` | 架构全景图 |
| `gcp/asm/asm-last-config.md` | Current 架构 |
| `gcp/asm/asm-last.md` | Istio mTLS + Gateway TLS Termination 深度解析 |
| `gcp/asm/asm-mtls-explorer.md` | ASM mTLS 在 Pod 间通信的深度探索与实践 |
| `gcp/asm/asm-no-mtls-sidecar.md` | ASM 仅作为内部网关、后端使用自管 HTTPS 的配置方案 |
| `gcp/asm/asm.md` | Compare ASM in cluster control plane and google-managed control plane |
| `gcp/asm/authori-and-peer-eng.md` | AuthorizationPolicy And PeerAuthentication In Google Managed Service Mesh |
| `gcp/asm/authorizationPolicy-and-Peerauthentication.md` | - [summary](#summary) |
| `gcp/asm/authorizationPolicy-capabilities-and-use-cases.md` | Istio AuthorizationPolicy 能力矩阵与实战场景 |
| `gcp/asm/cdr.md` | CDR (Client Data Repository) 详解 |
| `gcp/asm/cloud-service-mesh-control-gpt.md` | Google Cloud Service Mesh 控制面设计 |
| `gcp/asm/cloud-service-mesh-control.md` | Cloud Service Mesh (ASM) 精细化流量与权限控制指南 |
| `gcp/asm/cloud-service-mesh-eng.md` | 多租户 GKE 平台 Google Cloud Service Mesh 配置指南 |
| `gcp/asm/cloud-service-mesh.md` | Google Cloud Service Mesh Setup Guide for Multi-Tenant GKE Platform |
| `gcp/asm/crd.md` | CRD (Custom Resource Definition) 详解 |
| `gcp/asm/cross-project-mesh.md` | 跨项目 PSC 结合 Cloud Service Mesh 架构部署指南 |
| `gcp/asm/debug-istio.md` | Istio 疑难问题 Debug 最佳实践指南 (How to Debug Istio Issues) |
| `gcp/asm/deploy-claude-mermaid.md` | ASM on GKE — 资源分层部署图 (Mermaid) |
| `gcp/asm/deploy-claude.md` | ASM on GKE — `clienta-int` Namespace 部署实施说明 (V1) |
| `gcp/asm/deploy.md` | ASM on GKE 部署与流量路径细化 |
| `gcp/asm/diagram/README.md` | Istio No-Sidecar Architecture |
| `gcp/asm/expose-mesh.md` | if we want to expose istio-ingress outside gke add this annotation to service, haven't applied that since i have no idea if we need that... |
| `gcp/asm/git-log-analysis-2026-W10-W11.md` | Git Log Analysis Report (Last Week) |
| `gcp/asm/git-log-analysis-2026-W12-W13.md` | Git Log Analysis Report (2026-W12 ~ W13) |
| `gcp/asm/gloo/Ambient.md` | 💡 核心概念理解：Ambient 意味着“隐形化”和“分离化” |
| `gcp/asm/gloo/Gloo-setup.md` | q |
| `gcp/asm/gloo/cross-project-gloo-mesh.md` | Cross-Project 架构下 Gloo Mesh 替换 ASM 方案探索 |
| `gcp/asm/gloo/cross-project-gloo.md` | Cross-Project Gloo 方案 |
| `gcp/asm/gloo/gke-ambient-waypoint-multip.md` | GKE Ambient + Waypoint 多集群企业版实施版 |
| `gcp/asm/gloo/gke-ambient-waypoint-single.md` | GKE Ambient + Waypoint 单集群生产安装版 |
| `gcp/asm/gloo/gke-ambient-waypoint.md` | GKE Ambient + Waypoint 安装与校正文档（企业版可用） |
| `gcp/asm/gloo/gloo-ambient-mesh-minimax.md` | Gloo Mesh Enterprise Ambient Mode Installation Guide on GKE |
| `gcp/asm/gloo/gloo-concepts.md` | Gloo Mesh Enterprise 核心概念与选型指南 (2026版) |
| `gcp/asm/gloo/gloo-flow.md` | Istio vs Gloo Enterprise：GKE 流量 & 加密 Flow 对比 |
| `gcp/asm/gloo/gloo-sidecar.md` | 查看某个业务命名空间下的 Pod 容器数量 |
| `gcp/asm/gloo/step-by-step-gloo-gateway-minimax.md` | End-to-End Gloo Gateway Installation on GKE |
| `gcp/asm/gloo/step-by-step-gloo-setup-gke.md` | End-to-End Gloo Mesh Enterprise Installation on GKE |
| `gcp/asm/gloo/step-by-step-gloo.md` | End-to-End Guide: Installing Gloo Mesh Enterprise on GKE |
| `gcp/asm/gloo/waypoint.md` | Waypoint 详解：Ambient 模式下的 L7 策略执行器 |
| `gcp/asm/istio-context.md` | Istio Context Path 与 Request Path 一致性最佳实践 |
| `gcp/asm/istio-egress/README.md` | istioyaml |
| `gcp/asm/istio-egress/istio-egress-squid.md` | GKE Private Cluster 中基于 Istio Egress Gateway + Squid 的 SaaS 出站方案 |
| `gcp/asm/istio-egress/istio-egress.md` | GKE Private Cluster 中基于 Istio Egress Gateway 的 SaaS 出站控制方案 |
| `gcp/asm/k8s-gateway-ambient/01-ambient-vs-sidecar.md` | Ambient vs Sidecar — 本场景下的本质差异与选型 |
| `gcp/asm/k8s-gateway-ambient/02-install-ambient-helm.md` | Ambient 安装方案 — Helm 拆分安装 istio-base / istiod / istio-cni / ztunnel |
| `gcp/asm/k8s-gateway-ambient/03-waypoint-design.md` | Waypoint 设计决策 — per-namespace vs per-service 与 HA |
| `gcp/asm/k8s-gateway-ambient/04-runtime-migration.md` | 业务命名空间从 Sidecar 迁移到 Ambient — 步骤与回滚 |
| `gcp/asm/k8s-gateway-ambient/05-upgrade-strategies.md` | Istio 升级策略 — 单 revision vs 双 revision canary,Helm vs istioctl |
| `gcp/asm/k8s-gateway-ambient/06-policy-capabilities.md` | Ambient 模式下 AuthorizationPolicy / PeerAuthentication 能力矩阵(场景化) |
| `gcp/asm/k8s-gateway-ambient/07-feature-status-1.30.3.md` | Istio 1.30 Ambient Feature 状态矩阵 — GA / Beta / Alpha 完整清单 |
| `gcp/asm/k8s-gateway-ambient/08-ambient-networkpolicy.md` | Ambient 与 K8s NetworkPolicy 协同 — 15008 必须显式放行 |
| `gcp/asm/k8s-gateway-ambient/09-ztunnel-redirection-app-compat.md` | Ambient 下 ztunnel 拦截机制 — 应用代码兼容性全表 |
| `gcp/asm/k8s-gateway-ambient/10-waypoint-gateway-coexistence.md` | Ambient Waypoint 与 K8s Gateway API 共存 — 入口 / 出口 / 东西向路由分层 |
| `gcp/asm/k8s-gateway-ambient/11-l7-zero-downtime-constraint.md` | Sidecar → Ambient 迁移硬约束 — L7 策略 Zero-Downtime 不支持 |
| `gcp/asm/k8s-gateway-ambient/12-revision-canary-mtls-compat.md` | 双 Revision Canary 升级 — mTLS 证书兼容性与证书轮换细节 |
| `gcp/asm/k8s-gateway-ambient/13-multicluster-ambient-status.md` | Multicluster Ambient Mesh — 1.30 现状与生产可用性评估 |
| `gcp/asm/k8s-gateway-ambient/14-parametersRef-vs-targetRefs-concept-clarity.md` | `parametersRef` vs `targetRefs` — 概念澄清(都是 "Refs" 但完全不同的东西) |
| `gcp/asm/k8s-gateway-ambient/15-istio-revision-mechanism-explained.md` | Istio Revision 机制详解 — K8s 资源管理视角的完整图谱 |
| `gcp/asm/k8s-gateway-ambient/16-revision-like-patterns-cloud-native.md` | K8s 资源管理中的 Revision 类机制 — 云原生生态横向对比 |
| `gcp/asm/k8s-gateway-ambient/17-istio-image-tag-automation-sre-workflow.md` | Istio Image Tag 自动化升级方案 — SRE 常规任务设计 |
| `gcp/asm/k8s-gateway-ambient/18-solo-distribution-vs-upstream-istio-comparison.md` | Solo 分发 vs 上游 Istio — 版本选型评估(社区方案) |
| `gcp/asm/k8s-gateway-ambient/19-solo-agentgateway-ambient-install.md` | q |
| `gcp/asm/k8s-gateway-ambient/20-solo-ambient-kong.md` | summary |
| `gcp/asm/k8s-gateway-ambient/21-solo-ambient-egress.md` | Ambient 模式下 GKE Pod Egress 实现 — Internal + Public(含 Namespace-level 公共出网白名单) |
| `gcp/asm/k8s-gateway-ambient/22-ztunnel-mtls-and-cert-rotation.md` | ztunnel L4 mTLS 工作机制与证书轮转深度探索 |
| `gcp/asm/k8s-gateway-ambient/23-intra-namespace-call-versioning-and-mtls.md` | Intra-Namespace Call:版本解耦 + svc DNS + HTTPS/TLS(GKE + Ambient) |
| `gcp/asm/k8s-gateway-ambient/ADR-LOCAL-001-migrate-minimal-to-ambient.md` | ADR-LOCAL-001: 从 Istio minimal profile 迁移到 ambient 模式的架构决策 |
| `gcp/asm/k8s-gateway-ambient/Jev-explorer-solo-ambient.md` | Jev-explorer-solo-ambient — Ambient 网关接管后的实施细节与风险清单 |
| `gcp/asm/k8s-gateway-ambient/PERSONAL-FOCUS-LIST.md` | 个人关注清单 — Ambient / Revision / Policy 探索中的核心问题 |
| `gcp/asm/k8s-gateway-ambient/README.md` | K8s Gateway + Ambient Mesh 探索(独立目录) |
| `gcp/asm/k8s-gateway-ambient/case-lex-intra-call/README.md` | case-lex-intra-call —— Intra-Namespace Call 可运行 PoC |
| `gcp/asm/k8s-gateway-ambient/case-lex-intra-call/optional/README.md` | optional/ — 应用层 HTTPS(可选,默认不 apply) |
| `gcp/asm/k8s-gateway-ambient/case-lex/README.md` | case-lex — Lex 个人 ambient waypoint + ListenerSet 配置样本 |
| `gcp/asm/k8s-gateway-ambient/case-lex/analyze-httproute.md` | 09-01-app-httproute.yaml — 两段式 HTTPRoute 详解 |
| `gcp/asm/k8s-gateway-ambient/case-lex/analyze-waypoint.md` | analyze-waypoint.md — per-namespace Waypoint 深度解析 |
| `gcp/asm/k8s-gateway-ambient/case-lex/assessment-ingress.md` | assessment-ingress.md — Ingress 流量到业务 Pod 的所有可行路径 |
| `gcp/asm/k8s-gateway-ambient/case-lex/base-lex-ServiceEntry.md` | base-lex-ServiceEntry.md — case-lex 场景下的 ServiceEntry + 双轨 Egress 治理 |
| `gcp/asm/k8s-gateway-ambient/case-lex/jev-egress-explorer.md` | jev-egress-explorer.md — 用 Jev (TypeSafe System One) 做 Public Egress 策略判定 |
| `gcp/asm/k8s-gateway-ambient/case-lex/summary-size-waypoint.md` | summary-size-waypoint.md — Waypoint Sizing 知识点总结 |
| `gcp/asm/k8s-gateway-ambient/case-lex/yaml-assessment.md` | YAML 评估报告 v5 — case-lex 4 文件最终态 (纯审计) |
| `gcp/asm/k8s-gateway-ambient/lextodo.md` | version |
| `gcp/asm/k8s-gateway-ambient/mesh-solo-port-parse.md` | mesh-solo-port-parse.md — Istio Ambient / Solo Mesh 全端口对照表 |
| `gcp/asm/k8s-gateway-ambient/solo-ambient.md` | q |
| `gcp/asm/k8s-gateway-ambient/upgrade/solo-istio-ambient-upgrade-strategy-exploration.md` | Solo Istio Ambient 长期维护与零停机升级 —— 策略探索 |
| `gcp/asm/k8s-gateway-ambient/upgrade/solo-istio-ambient-zero-downtime-upgrade.md` | Solo Istio Ambient（1.30.3-distroless）长期维护与零停机升级方案 |
| `gcp/asm/k8s-gateway-ambient/ztunnel-l4-mtls.md` | ztunnel 的 L4 mTLS 与证书生命周期详解 |
| `gcp/asm/kilo-minimax-cross-project-mesh.md` | 跨项目 PSC 结合 Cloud Service Mesh 实现方案 |
| `gcp/asm/master-project-setup-mesh.md` | Master Project Setup: Cloud Service Mesh (CSM) for Cross-Project Tenant Connectivity |
| `gcp/asm/mcs.md` | summary |
| `gcp/asm/mesh-entity.md` | summary |
| `gcp/asm/no-mtls/How-to-setup-istio-nosidecar.md` | How to Setup Istio Ingress Gateway (No Sidecar) on GKE with ASM Managed Control Plane |
| `gcp/asm/no-mtls/asm-version.md` | API Versioning and Gateway Comparison: GKE, Istio, and Cloud Service Mesh |
| `gcp/asm/no-mtls/gateways-type.md` | Gateway Types Comparison: GKE Gateway vs ASM Gateway vs Istio Classic |
| `gcp/asm/node-pool-manage-claude.md` | GKE Node Pool Management：生产级最佳实践 |
| `gcp/asm/node-pool-management.md` | Master Project: GKE Node Pool Management（架构视角） |
| `gcp/asm/peerAuthentication-capabilities-and-use-cases.md` | Istio PeerAuthentication 能力矩阵与实战场景 |
| `gcp/asm/qwen-cross-project-mesh.md` | 跨项目 PSC 结合 Cloud Service Mesh 实现方案 |
| `gcp/asm/serviceEntry-capabilities-and-use-cases.md` | Istio ServiceEntry 能力矩阵与实战场景 |
| `gcp/asm/solo/background.md` | ASM Solo Gateway 流量转发链路(BG/收工状态总结) |
| `gcp/asm/solo/install/install.md` | ASM Solo Ambient Mesh 安装与验证 |
| `gcp/asm/solo/solo-version.md` | 分析结论：切换到 Solo agentgateway + Ambient Mesh 能否解决这个问题 |
| `gcp/asm/solo/solo.md` | ASM Solo Ambient Mesh — 新网格架构下 TLS/mTLS 根本改变 |
| `gcp/asm/solo/upgrade/image-upgrade.md` | Solo Mesh 镜像替换与版本升级手册（Ambient） |
| `gcp/asm/trace-istio-and-export.md` | ============================================================================= |
| `gcp/asm/trace-istio.md` | 仅追踪（不导出 YAML） |
| `gcp/asm/verify-istio-setup.md` | GKE Custom Istio Internal Gateway Verification Script |

### GCP Cloud Run Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/cloud-run/Cloud-Run-Stream-Events-API.md` | Summary |
| `gcp/cloud-run/Cloud-run-metadata.md` | Summary |
| `gcp/cloud-run/Export-Cloud-Run-Service.md` | summary |
| `gcp/cloud-run/adc.md` | **🔑 什么是 ADC（Application Default Credentials）** |
| `gcp/cloud-run/cloud-run-automation/cloud-run-flow.md` | summary |
| `gcp/cloud-run/cloud-run-automation/cloud-run-gemini-summary.md` | Cloud Run 自动化平台建设摘要 |
| `gcp/cloud-run/cloud-run-automation/cloud-run-monitor.md` | Cloud Run 监控完整方案 |
| `gcp/cloud-run/cloud-run-automation/design.md` | Design Document |
| `gcp/cloud-run/cloud-run-automation/requirements.md` | Requirements Document |
| `gcp/cloud-run/cloud-run-automation/tasks.md` | Implementation Plan |
| `gcp/cloud-run/cloud-run-buckets.md` | Cloud Run 访问 Cloud Storage Buckets |
| `gcp/cloud-run/cloud-run-container-cmd.md` | Cloud Run 容器命令 (Container Command) 与参数 (Arguments) 详解 |
| `gcp/cloud-run/cloud-run-debug.md` | Cloud Run Job 日志缺失问题分析与最佳实践 |
| `gcp/cloud-run/cloud-run-debug/cloud-run-debug-500.md` | 诊断 GKE 调用 Cloud Run 时的 AsyncRequestTimeoutException (500) |
| `gcp/cloud-run/cloud-run-debug/cloud-run-debug-log.md` | Claude |
| `gcp/cloud-run/cloud-run-debug/cloud-run-java-debug.md` | GCP Cloud Run Java 超时问题调试指南 |
| `gcp/cloud-run/cloud-run-deploy.md` | Cloud Run Jobs 部署方法深度解析 |
| `gcp/cloud-run/cloud-run-job-housekeep-sh.md` | ============================================================================= |
| `gcp/cloud-run/cloud-run-job-housekeep.md` | Cloud Run Job Housekeeping |
| `gcp/cloud-run/cloud-run-job-migration-jq.md` | Cloud Run Job 配置迁移脚本 (使用 jq 版本) |
| `gcp/cloud-run/cloud-run-job-with-services.md` | 🧠 总结建议 |
| `gcp/cloud-run/cloud-run-limit-permission.md` | 创建执行专用的 Service Account |
| `gcp/cloud-run/cloud-run-network.md` | summary |
| `gcp/cloud-run/cloud-run-sa-active.md` | 在你的 Dockerfile 或启动脚本中，确保 metadata.google.internal 被排除 |
| `gcp/cloud-run/cloud-run-sa.md` | ChatGPT |
| `gcp/cloud-run/cloud-run-violation/Cloud-run-verify-images-using-OpenPGP.md` | Summary |
| `gcp/cloud-run/cloud-run-violation/a.md` | First, I sought help from GCS to see if there is a standard mode to encrypt our Images. Currently, they haven't provided us with the corr... |
| `gcp/cloud-run/cloud-run-violation/binary-authorization-default.md` | summary |
| `gcp/cloud-run/cloud-run-violation/binary-authorization.md` | 检查当前策略 |
| `gcp/cloud-run/cloud-run-violation/cloud-run-verify-images-OpenPGP.md` | Claude |
| `gcp/cloud-run/cloud-run-violation/cloud-run-verify-images-claude.md` | GCP Cloud Run Binary Authorization 镜像签名验证完整指南 |
| `gcp/cloud-run/cloud-run-violation/cloud-run-verify-images.md` | Summay |
| `gcp/cloud-run/cloud-run-violation/setup-binauthz-shared-kms.md` | Binary Authorization 配置脚本 - 使用 Shared 工程 KMS 密钥 |
| `gcp/cloud-run/cmd.md` | env_list=$(echo "$job_config" | jq -r ' |
| `gcp/cloud-run/container-validation/CONFIGURATION.md` | 容器启动校验器配置指南 |
| `gcp/cloud-run/container-validation/README.md` | 容器内部校验解决方案 |
| `gcp/cloud-run/execute.md` | Q |
| `gcp/cloud-run/fixed.md` | Cloud Run Job 配置迁移脚本 (使用 jq 版本 - 修复版) |
| `gcp/cloud-run/gcp-cloud-run-deploy.md` | Grok |
| `gcp/cloud-run/gcp-cloud-run-network.md` | Cloud Run 网络与安全精细化配置 |
| `gcp/cloud-run/gcp-project-server-level-sa.md` | 查询项目级别的SA权限 |
| `gcp/cloud-run/monitor-cloud-run.md` | Claude |
| `gcp/cloud-run/network-explorer.md` | Q |
| `gcp/cloud-run/network-requirement.md` | summary |
| `gcp/cloud-run/new.md` | New |
| `gcp/cloud-run/onboarding/cloud-run-onboarding-design.md` | 1. 获取用户 ID 或 tenant 信息 |
| `gcp/cloud-run/onboarding/onboarding-certrenew.md` | 基础权限 |
| `gcp/cloud-run/onboarding/onboarding-desing.md` | Cloud Run Onboarding 自动化设计方案：mTLS 证书续期 |
| `gcp/cloud-run/run-flow.md` | **1. 问题分析** |
| `gcp/cloud-run/schedule-job-trigger-cloud-run.md` | 直接执行逻辑 |
| `gcp/cloud-run/serverless-vpc-access.md` | **📌 什么是 Serverless VPC Access？** |
| `gcp/cloud-run/serverless.md` | Google Cloud Serverless VPC Access 详解 |
| `gcp/cloud-run/verify/branch-validation-guide.md` | Cloud Run 镜像分支校验指南 |
| `gcp/cloud-run/vpcaccess-viewer.md` | GCP IAM 角色详解：roles/vpcaccess.viewer |

### GCP GCE/MIG Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/gce/How-to-get-project-number.md` | **一、如何获取一个 GCP 项目的** |
| `gcp/gce/MIG-target-distribution-shape-even-to-balanced.md` | MIG `target-distribution-shape` EVEN → BALANCED — 架构影响与概念澄清 |
| `gcp/gce/application-credentials-error.md` | 步骤一：创建服务账号和下载密钥文件 |
| `gcp/gce/cross-vpc-instance.md` | Claude |
| `gcp/gce/debug-gce-proxy.md` | 问题排查过程总结 |
| `gcp/gce/filter-firewall.md` | firewall-filter |
| `gcp/gce/firewall-hit.md` | How to list firewall-rules |
| `gcp/gce/flow-fr-lb-mig.md` | 全局 HTTPS 负载均衡完整数据流与控制流图 |
| `gcp/gce/gce-instance-log.md` | 实现 Nginx 日志映射到 Google Cloud Log Explorer 的步骤 |
| `gcp/gce/gce-nic-route-image.md` | GCE 多网卡：与网卡名解耦的最佳实践 |
| `gcp/gce/gcloud-sheet.md` | get-iam-policy |
| `gcp/gce/gcp-balance.md` | Balanced |
| `gcp/gce/gcp-cloud-five-tuple.md` | 五元组的组成 |
| `gcp/gce/gcp-cloud-run.md` | Google Cloud Run 快速入门 |
| `gcp/gce/gcp-encrypt.md` | Gemini |
| `gcp/gce/gcp-glb.md` | 你可以通过使用Google Cloud Global Load Balancer (GLB) 实现跨多个GCP项目共享一个负载均衡器，并基于用户的区域或来源IP进行流量转发。具体实现方法如下： |
| `gcp/gce/gcp-hight-avaliablity-terminology.md` | Understanding 'PZS'/'PSZ' in Google Cloud Platform High Availability |
| `gcp/gce/gcp-instance-satisfilesPzs.md` | 在Google Cloud中，satisfiesPzs（满足PZS）是一个布尔值属性，表示实例是否满足Sole-Tenant节点的放置要求（Placement Zone Selection）。当为true时，表示实例被成功放置在符合PZS（Placement Zone Se... |
| `gcp/gce/gcp-machine-type.md` | summary |
| `gcp/gce/gcp-master-cluster-nodepool.md` | Summary |
| `gcp/gce/gcp-nat-route.md` | how to verify cloud nat ip address |
| `gcp/gce/gcp-network.md` | Q |
| `gcp/gce/gcp-scope.md` | Google Cloud Compute Engine (GCE) Access Scopes (访问范围) 详解 |
| `gcp/gce/gcp-sink.md` | 谷歌云 Firestore 中的 Sink 概念 |
| `gcp/gce/gcp-uig-with-mig.md` | GCP UIG vs MIG 深度对比指南 |
| `gcp/gce/gcp-upgrade-and-high-availablility.md` | summary |
| `gcp/gce/gcr.md` | migrate gcr to ar |
| `gcp/gce/google-api.md` | 第一部分：理解 `private.googleapis.com` 和 `restricted.googleapis.com` |
| `gcp/gce/group.md` | 使用服务账号认证 |
| `gcp/gce/healthcheck-calude.md` | 我来帮你分析 Google Cloud 负载均衡相关资源的创建顺序和健康检查更新的问题。 |
| `gcp/gce/healthcheck-delete.md` | 删除 backend service |
| `gcp/gce/healthcheck.md` | 创建资源顺序及命令 |
| `gcp/gce/install-gcloud-mac.md` | Install Gcloud Mac |
| `gcp/gce/instance-groups.md` | 自动化脚本 |
| `gcp/gce/instance-metadata-and-custom-attributes.md` | GCE Instance Metadata — 自定义属性、动态入参与 Pod 侧验证 |
| `gcp/gce/instance-uptime.md` | 检查参数数量 |
| `gcp/gce/ip-range.md` | - Node number: 1022 |
| `gcp/gce/lb-health-mig.md` | flow diagram |
| `gcp/gce/mcg.md` | Reference |
| `gcp/gce/merged-scripts.md` | Shell Scripts Collection |
| `gcp/gce/mig-static-ip-options.md` | 让 MIG / Instance 拥有静态 IP:GCP 全路径评估(含双网卡 MIG) |
| `gcp/gce/namedports.md` | How to edit port |
| `gcp/gce/rolling/merged-scripts.md` | Shell Scripts Collection |
| `gcp/gce/route-gw.md` | GCP 路由基础概念及与 VPC、实例关系 |
| `gcp/gce/scopes.md` | 将一个Service Account加入到我的一个GROUP里面 我这个对应的GROUP有对应下的Secret的权限 |
| `gcp/gce/stateful-mig-and-autoscaling.md` | Stateful MIG 与 Autoscaling:两个概念、为什么互斥、以及 stateful 如何解决静态 IP 问题 |
| `gcp/gce/static-ip.md` | 1. 创建静态外部IP地址 |
| `gcp/gce/streaming.md` | 1. **基础知识点** |
| `gcp/gce/tls-public-lb-flow.md` | GCP TLS 公共负载均衡流程图 |
| `gcp/gce/troubleshoot-google-api.md` | 在与来源服务关联的子网上启用专用 Google 访问通道，并配置 DNS 以将 <host> 网址解析为 private.googleapis.com (199.36.153.8/30) 或 restricted.googleapis.com (199.36.153.4/3... |
| `gcp/gce/understand-network.md` | a |
| `gcp/gce/use-service-account-impersonation.md` | Google服务账户模拟 |
| `gcp/gce/verify-mig-status.md` | verify-mig-status.sh |

### GCP LB/GLB/Ingress Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/glb/glb+psc.md` | 对 Master Project 的 ILB Forwarding Rule 开启 Global Access |
| `gcp/glb/glb-gtm.md` | glb-gtm — GCP Cloud Load Balancing 的跨 Region 流量分配机制 |
| `gcp/glb/glb-retry-timeout.md` | GCP GLB 多层架构超时与重试机制设计指南 |
| `gcp/glb/glb.md` | current status |
| `gcp/glb/target-https-proxies.md` | GCP Target HTTPS Proxies 证书追加操作指南 |
| `gcp/ingress/backend-servie.md` | Backend Servie |
| `gcp/ingress/control.md` | K8s Ingress Controller 工作流深度解析 |
| `gcp/ingress/gateway-httproute.md` | claude |
| `gcp/ingress/gateway-lex.md` | GKE Gateway: HTTPRoute 流量分配与健康检查核心解析 |
| `gcp/ingress/gke-ingress-stephen.md` | mermaid |
| `gcp/ingress/ingress-control-400-claude.md` | Ingress Controller 配置体系深度解析 |
| `gcp/ingress/ingress-control-400-qwen.md` | Deep Dive into Ingress Controller Configuration System |
| `gcp/ingress/ingress-control-400.md` | ChatGPT |
| `gcp/ingress/ingress-control-log.md` | 是的,有一些推荐的日志配置可以帮助您获取Ingress Nginx Controller的详细信息: |
| `gcp/ingress/ingress-control-mindmap.md` | 根据您提供的YAML文件内容，我为您创建了一个Mermaid思维导图，展示了Ingress Nginx Controller的主要部署资源及其关系。这个图表概括了部署中的关键组件和它们的层次结构。 |
| `gcp/ingress/ingress-control-networkpolicy.md` | summary question |
| `gcp/ingress/ingress-control-performance.md` | To optimize the performance of Ingress Nginx Controller in a GKE environment, consider the following. |
| `gcp/ingress/ingress-control-resouce-ingress.md` | for kong gw |
| `gcp/ingress/ingress-control-resouce-sort.md` | How to Using ingress export https |
| `gcp/ingress/ingress-control.md` | Internal |
| `gcp/ingress/ingress-log-debug.md` | summary my question |
| `gcp/ingress/ingress-reference.md` | - https://kubernetes.github.io/ingress-nginx/deploy/#gce-gke |
| `gcp/ingress/ingress-snippet.md` | Ingress Annotations 完整配置解析 |
| `gcp/ingress/ingress-with-gateway.md` | Verify step |
| `gcp/ingress/lex-presentation.md` | GKE Gateway 演示文稿 |
| `gcp/lb/backend-service.md` | 创建Cloud Armor安全策略 |
| `gcp/lb/backend-timeout.md` | **应用负载均衡器** |
| `gcp/lb/compare-forward-peering.md` | 概念阐述 |
| `gcp/lb/forwardingrule-monitor.md` | 创建 Compute Engine 客户端 |
| `gcp/lb/global-https.md` | summary |
| `gcp/lb/lb-created.md` | GCP 中创建一个类型为网络代理(network proxy)、访问类型为外部(external)、协议为 TCP 的负载均衡器,可以使用的详细命令 |
| `gcp/lb/lb-get-ssl-information.md` | get-forwarding-rule.sh |
| `gcp/lb/lb-lb.md` | 你的流量路径如下： |
| `gcp/lb/lb-parameter.md` | 1. 为什么 Backend Service 会出现 oauth2ClientId |
| `gcp/lb/lb-poc-from-mig.md` | lb-poc-from-mig.sh |
| `gcp/lb/lb.md` | other |
| `gcp/lb/merged-scripts.md` | Shell Scripts Collection |
| `gcp/lb/multi-ilb-bs.md` | Multiple Internal Load Balancers Binding to Single Backend Service |

### GCP Cloud Armor Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/cloud-armor/Cloud-armor-for-api-design.md` | 流程分析与验证 |
| `gcp/cloud-armor/armor-python/ip_validator.md` | import argparse |
| `gcp/cloud-armor/cloud-armor-address-group.md` | 使用地址组实现 GCP Cloud Armor 的可扩展 IP 管理 |
| `gcp/cloud-armor/cloud-armor-change.md` | summary |
| `gcp/cloud-armor/cloud-armor-header.md` | 这个文档的一些命令是错误的 |
| `gcp/cloud-armor/cloud-armor-ip-limition.md` | 优化 GCP Cloud Armor 中基于路径的 IP 限制策略 |
| `gcp/cloud-armor/cloud-armor-path-priority.md` | summary |
| `gcp/cloud-armor/cloud-armor-path.md` | Q |
| `gcp/cloud-armor/cloud-armor-priority.md` | Q Cloude |
| `gcp/cloud-armor/cloud-armor-range.md` | python |
| `gcp/cloud-armor/cloud-armor-targets.md` | 列出所有 Cloud Armor 安全策略 |
| `gcp/cloud-armor/cloud-aromor-priority-setting.md` | 1. Create Whitelist Access Based on API Location Path |
| `gcp/cloud-armor/cloud-group.md` | 利用 Cloud Armor 地址组管理大规模 IP 地址列表的最佳实践 |
| `gcp/cloud-armor/content-length.md` | 1. 定义的意义 |
| `gcp/cloud-armor/dedicated-armor/URLmapMatch.md` | GCP URL Map 高级匹配与路径重写指南 (URLmapMatch.md) |
| `gcp/cloud-armor/dedicated-armor/create-backendservice.md` | 验证通过：可以在一条命令中完成绝大部分配置 |
| `gcp/cloud-armor/dedicated-armor/explorer.md` | GCP API 平台中实现「按 API 维度」Cloud Armor 策略的可行方案分析 |
| `gcp/cloud-armor/dedicated-armor/gcloud-compute-url-maps.md` | Quota |
| `gcp/cloud-armor/dedicated-armor/glb-api-cloudarmor-qwen-eng.md` | GCP GLB API-Level Cloud Armor Isolation Solution Analysis and Implementation Guide |
| `gcp/cloud-armor/dedicated-armor/glb-api-cloudarmor-qwen.md` | GCP GLB API 级 Cloud Armor 隔离方案分析与实施指南 |
| `gcp/cloud-armor/dedicated-armor/glb-api-cloudarmor.md` | 基于 GCP GLB 的 API 级 Cloud Armor 隔离实施方案（可直接落地） |
| `gcp/cloud-armor/dedicated-armor/glb-claude.md` | requirement |
| `gcp/cloud-armor/dedicated-armor/how-to-manage-url-map.md` | GCP URL Map 管理：大规模 API 与频繁变更的实战方案 |
| `gcp/cloud-armor/dedicated-armor/how-to-switch-zerodowntime.md` | GCP URL Map 零停机生产切换与全验证指南 |
| `gcp/cloud-armor/dedicated-armor/requirement.md` | Cloud Armor Granular Policy Design |
| `gcp/cloud-armor/dedicated-armor/url-map.md` | GCP HTTPS Load Balancer —— URL Map 深度解析与可实施配置指南 |
| `gcp/cloud-armor/define-header.md` | summary |
| `gcp/cloud-armor/import-armor.md` | claude |
| `gcp/cloud-armor/ip-py.md` | --- 配置 --- |
| `gcp/cloud-armor/mtls-armor-cel-research/REPORT.md` | GCP Cloud Armor + Global External HTTPS LB + mTLS: 客户端证书 / SPIFFE 变量处理机制 |
| `gcp/cloud-armor/path-priority.md` | Summary |
| `gcp/cloud-armor/rate_based_ban.md` | Rate-based ban |
| `gcp/cloud-armor/summary-ban.md` | Q |

### GCP Cross-Project Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/cross-project/3-enhance.md` | Cross-Project PSC NEG 生产环境评估与增强方案 |
| `gcp/cross-project/3-figma.md` | 跨项目 PSC NEG 方案 Figma / FigJam 视觉化脚本 |
| `gcp/cross-project/3.md` | 跨项目 PSC NEG 实现方案 |
| `gcp/cross-project/4.md` | Cross Project External Entry in Tenant Project 方案 |
| `gcp/cross-project/about-wildcard-depth.md` | 泛域名证书（Wildcard Certificate）匹配深度解析 |
| `gcp/cross-project/cross-domain-fqdn.md` | 伪代码示例 |
| `gcp/cross-project/cross-mig.md` | gcloud 操作及错误信息 |
| `gcp/cross-project/cross-process-zonal-neg.md` | Shared VPC 跨项目 Internal HTTPS LB 绑定 Backend 可行性分析 |
| `gcp/cross-project/cross-project-bigquery-master-to-tenant.md` | 跨项目 BigQuery 联邦:Master 项目 GKE → Tenant 项目 BigQuery |
| `gcp/cross-project/cross-project-bigquery.md` | 跨项目 BigQuery 访问:Master 项目 GKE → Tenant 项目 BigQuery(Private Google Access / PGA 路线) |
| `gcp/cross-project/cross-project-binding-backend.md` | cross success |
| `gcp/cross-project/cross-project-cloud-armor.md` | Cross-Project Cloud Armor Policy — 绑定规则与跨 Project 限制 |
| `gcp/cross-project/cross-project-exploration-tenant-master-isolation-gemini.md` | 跨项目架构探索：Tenant Ingress + Master Backend 隔离方案深度评估 |
| `gcp/cross-project/cross-project-firewall-netpol/README.md` | Cross-Project Firewall & NetworkPolicy 路线图 |
| `gcp/cross-project/cross-project-firewall-netpol/references/firewall-by-instance-path.md` | PSC Service Attachment firewall 决策（按实例视角） |
| `gcp/cross-project/cross-project-firewall-netpol/references/log-capture-by-3-step-method.md` | PSC 跨项目日志抓取 SOP — 按"3 步法"组织 |
| `gcp/cross-project/cross-project-firewall-netpol/references/psc-firewall-cheatsheet.md` | PSC Firewall Cheat Sheet — 横向决策工具 |
| `gcp/cross-project/cross-project-firewall-netpol/references/psc-nat-vs-proxy-only-subnet-index.md` | PSC NAT Subnet vs Proxy-Only Subnet（精简索引） |
| `gcp/cross-project/cross-project-firewall-netpol/references/scenario-a-via-mig-jumphost.md` | Scenario A — Tenant → MIG (nginx jump host) → Master GKE Gateway |
| `gcp/cross-project/cross-project-firewall-netpol/references/scenario-b-via-gke-gateway.md` | Scenario B — Tenant → Master GKE Gateway (直接) |
| `gcp/cross-project/cross-project-gateway/Rt-psc-connect-master-project-gateway.md` | Project A Kong Runtime 通过 PSC Endpoint 访问 Project B Master GKE Gateway |
| `gcp/cross-project/cross-project-gateway/cross-project-san.md` | Cross-Project PSC FQDN with SAN |
| `gcp/cross-project/cross-project-gateway/rt-cross-project-fqdn.md` | 在 Consumer Project 的 VPC 绑定 Response Policy |
| `gcp/cross-project/cross-project-gateway/rt-psc-gateway.md` | 先拿 Gateway 分配的 IP |
| `gcp/cross-project/cross-project-requirement.md` | 用户硬性前提: |
| `gcp/cross-project/cross-project-sre-enhance.md` | Cross-Project PSC NEG 最终方案 SRE 监控需求增强版 |
| `gcp/cross-project/cross-project-sre-summary.md` | Cross-Project PSC NEG 架构 — SRE 对接与监控需求总结 |
| `gcp/cross-project/cross-project-sre.md` | Cross-Project PSC NEG 架构 - SRE 监控需求 |
| `gcp/cross-project/cross-project-success-one.md` | 你的架构现状与需求梳理报告 |
| `gcp/cross-project/cross-project-success-three.md` | 跨项目 PSC NEG 实现方案 |
| `gcp/cross-project/cross-project-success-two.md` | 切换项目（可选） |
| `gcp/cross-project/cross-project-three-add.md` | ↑ 必须带完整路径，指向 Host Project 的 subnet |
| `gcp/cross-project/explorer-2-0-fqdn.md` | Explorer 2.0: FQDN, SAN, URLMap, and Nginx Simplification |
| `gcp/cross-project/psc-firewall-qwen.md` | Cross Project PSC Firewall 完整指南（增强版） |
| `gcp/cross-project/psc-firewall-summary.md` | PSC Firewall Summary |
| `gcp/cross-project/psc-firewall.md` | Cross Project PSC Firewall 分析 |
| `gcp/cross-project/psc-ingres-gw.md` | Cross Project PSC + Ingress Gateway / Nginx / Service Mesh 探索 |
| `gcp/cross-project/public-mtls-ingress/Why-missing-sni.md` | Why missing sni |
| `gcp/cross-project/public-mtls-ingress/compare-allowlisted-with-truststores.md` | compare-allowlisted-with-truststores — `allowlistedCertificates` 与 `trustStores` 对比 |
| `gcp/cross-project/public-mtls-ingress/explorer-cloud-armor-spiffe.md` | explorer-cloud-armor-spiffe.md — Cloud Armor + mTLS 边缘 SPIFFE 校验:深度调研 |
| `gcp/cross-project/public-mtls-ingress/flow/README-flow.md` | mTLS 全局入口架构文件描述 |
| `gcp/cross-project/public-mtls-ingress/flow/multip-tls-mtls-flow.md` | 双入口 GLB (mTLS + TLS) 架构设计与流量拓扑文档 |
| `gcp/cross-project/public-mtls-ingress/merged-scripts.md` | Shell Scripts Collection |
| `gcp/cross-project/public-mtls-ingress/shared-glb-cn-a-sni.md` | 共享 GLB → PSC NEG → Master Gateway — SNI 传递性分析 — shared-glb-cn-a-sni |
| `gcp/cross-project/public-tls-basingpath-cross/baseing-path-cross-project.md` | baseing-path-cross-project.md — 同域名按 path 分流到不同 cross-project BS 的可行性方案 |
| `gcp/cross-project/public-tls-basingpath-cross/bs-type.md` | GCP Backend Service 类型支持报告 |
| `gcp/cross-project/public-tls-basingpath-cross/class-application-loadbalancer-cross-project.md` | class-application-loadbalancer-cross-project.md — Classic ALB 跨 project 跨到 B 工程方案探索 |
| `gcp/cross-project/public-tls-basingpath-cross/in-situ-migration-gemini.md` | im |
| `gcp/cross-project/public-tls-basingpath-cross/in-situ-migration.md` | 导出现有 URL Map / target proxy / SSL policy / backend service 全量配置留档 |
| `gcp/cross-project/public-tls-basingpath-cross/merged-scripts.md` | Shell Scripts Collection |
| `gcp/cross-project/public-tls-basingpath-cross/migration-classic-lb-to-glb-external-managed-lb.md` | To explorer |
| `gcp/cross-project/public-tls-basingpath-cross/to.md` | summary |
| `gcp/cross-project/public-tls-ingress/certificate-manager-api.md` | `certificatemanager.googleapis.com` API 依赖关系 |
| `gcp/cross-project/public-tls-ingress/class-application-loadbalancer-cross-project.md` | class-application-loadbalancer-cross-project.md — Classic ALB 跨 project 跨到 B 工程方案探索 |
| `gcp/cross-project/public-tls-ingress/facing-issue.md` | Facing Issue: 跨项目 Public TLS Ingress 改造 + 3 隐患 + 用户核心构想 |
| `gcp/cross-project/public-tls-ingress/merged-scripts.md` | Shell Scripts Collection |
| `gcp/cross-project/public-tls-ingress/psc-neg-requirements.md` | PSC NEG 完整需求清单 — 跨 project + L7 managed LB 必备条件 |
| `gcp/cross-project/public-tls-ingress/sni-nginx-solution.md` | SNI 注入解决方案:Nginx 主机 + 动态注册 |
| `gcp/cross-project/public-tls-ingress/tenant-tls-setup-https.md` | tenant-tls-setup-https.md — Producer ILB 二次终结 TLS(全链路 HTTPS 实现) |
| `gcp/cross-project/public-tls-ingress/why-using-global-external-managed-http-https.md` | 为什么用 GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS — 跨 project + 公网 Ingress 场景的核心原因 |

### GCP DNS Migration Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/migrate-gcp/Kiro-pop-plan.md` | **POP Platform Migration to Federated GCP - Comprehensive Plan** |
| `gcp/migrate-gcp/argo-cd-release.md` | argo-cd-release.md — 基于 Argo CD 的 GCP Release 推送探索 |
| `gcp/migrate-gcp/argocd.md` | 目标部署位置 |
| `gcp/migrate-gcp/crossplane-gcp-family-best-practices.md` | crossplane-gcp-family-best-practices.md — Crossplane + GCP Family 最佳实践 |
| `gcp/migrate-gcp/gar-container.md` | 每个 Pod 都需要 pause 容器 |
| `gcp/migrate-gcp/gemini-pop-plan.md` | Design |
| `gcp/migrate-gcp/get-ns-info-fast.md` | Fast GKE Namespace Information Extraction Script using JSON parsing |
| `gcp/migrate-gcp/get-ns-information.md` | This is a loop program, so the efficiency is a little low. |
| `gcp/migrate-gcp/get-ns-stats-qwen.md` | Optimized GKE Namespace Statistics Script - Fast execution with migration focus |
| `gcp/migrate-gcp/get-ns-stats.md` | Enhanced GKE Namespace Statistics Script - Comprehensive migration analysis |
| `gcp/migrate-gcp/migrate-concepts.md` | POP平台迁移核心概念脑图 |
| `gcp/migrate-gcp/migrate-dns/How-to-switch-dns.md` | DNS 迁移自动化方案（GKE 多项目 / 多集群） |
| `gcp/migrate-gcp/migrate-dns/Kiro-dns.md` | GCP 跨项目 DNS 迁移解决方案 |
| `gcp/migrate-gcp/migrate-dns/Qwen-anayliz-dns.md` | GCP DNS 跨项目迁移分析与方案设计 (Qwen-anayliz-dns.md) |
| `gcp/migrate-gcp/migrate-dns/README.md` | GCP DNS 迁移工具 |
| `gcp/migrate-gcp/migrate-dns/chatgpt-migrate-dns.md` | DNS 迁移自动化方案（GKE 多项目 / 多集群） |
| `gcp/migrate-gcp/migrate-dns/examples/migration-checklist.md` | DNS 迁移检查清单 |
| `gcp/migrate-gcp/migrate-dns/gemini-analyiz-dns.md` | GCP DNS 迁移策略与自动化脚本分析 |
| `gcp/migrate-gcp/migrate-dns/merged-script-dns.md` | Shell Scripts Collection |
| `gcp/migrate-gcp/migrate-dns/pop-dns.md` | Q |
| `gcp/migrate-gcp/migrate-gcp-redis.md` | GCP Redis 实例跨项目迁移方案 |
| `gcp/migrate-gcp/migrate-secret-manage/README.md` | GCP Secret Manager 跨项目迁移工具 |
| `gcp/migrate-gcp/migrate-secret-manage/merged-scripts.md` | Shell Scripts Collection |
| `gcp/migrate-gcp/migrate-secret-manage/migrate-gcp-secret-manager.md` | Migrate Gcp Secret Manager |
| `gcp/migrate-gcp/migrate-secret-manage/secret-manage-chatgpt.md` | 以下是一个 GCP Secret Manager 从项目 A 迁移到项目 B 的迁移计划，特别考虑了 GKE 中的依赖关系。 |
| `gcp/migrate-gcp/migration-info/namespace-lex-enhanced-stats-20250830_192844.md` | Enhanced Kubernetes Namespace Statistics Report |
| `gcp/migrate-gcp/migration-info/namespace-lex-enhanced-stats-20250830_200322.md` | Enhanced Kubernetes Namespace Statistics Report |
| `gcp/migrate-gcp/migration-info/namespace-lex-gemini-stats-20250830_192818.md` | Gemini Kubernetes Namespace Report |
| `gcp/migrate-gcp/plan.md` | POP迁移方案 |
| `gcp/migrate-gcp/pop-migrate/COMPATIBILITY.md` | 工具兼容性说明 |
| `gcp/migrate-gcp/pop-migrate/README.md` | GKE 跨项目 Namespace 迁移工具 |
| `gcp/migrate-gcp/pop-migrate/docs/EXAMPLES.md` | 使用示例 |
| `gcp/migrate-gcp/pop-migrate/docs/TROUBLESHOOTING.md` | 故障排除指南 |
| `gcp/migrate-gcp/pop-migrate/docs/USAGE.md` | 使用指南 |

### GCP Secret Manager Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/secret-manage/Java-SMS.md` | **📌 背景说明** |
| `gcp/secret-manage/about-deleted-sa-secret-manage.md` | 你的理解是正确的。当你删除一个 Service Account (SA) 后，虽然该 SA 的实体已经被移除，但它曾经被授予的 IAM 角色绑定可能不会立即从 Secret 的 IAM Policy 中移除。 这就导致了你观察到的现象：系统提示该 SA 已经拥有了该角色，但... |
| `gcp/secret-manage/add-sa-to-manager.md` | secret get-iam-policy ${secret} \ |
| `gcp/secret-manage/add-secret-binging.md` | 前提条件 |
| `gcp/secret-manage/add-secret-manage-private.md` | 交互式使用 |
| `gcp/secret-manage/echo-n.md` | 获取 secret 内容（latest 版本） |
| `gcp/secret-manage/flow-secret-java.md` | Java Spring 应用结合 GCP Secret Manager 的工作流 |
| `gcp/secret-manage/gcp-secret-base64.md` | 是的，在创建 Secret 之前对数据进行加密（如使用 Base64 编码或其他加密方法）确实可以提供额外的安全保护。但需要注意以下几点： |
| `gcp/secret-manage/gcp-secret-manage-rotate.md` | ChatGPT |
| `gcp/secret-manage/gcp-secret-manage-version.md` | GCP Secret Manager 版本化与幂等性管理方案 |
| `gcp/secret-manage/gcp-secret.md` | secret get-iam-policy ${secret} \ |
| `gcp/secret-manage/housekeep-secret.md` | Usage: ./google_secrets_scanner.sh -e <environment> |
| `gcp/secret-manage/java-examples/README.md` | GCP Secret Manager Java Examples |
| `gcp/secret-manage/java-examples/USAGE.md` | Usage Guide - GCP Secret Manager Java Demo |
| `gcp/secret-manage/java-examples/VERIFICATION.md` | GCP Secret Manager Verification Guide |
| `gcp/secret-manage/java-examples/gcp-secret-manager-flow.md` | GCP Secret Manager Complete Flow Guide |
| `gcp/secret-manage/list-secret/BUGFIX-NOTES.md` | Bug 修复说明 |
| `gcp/secret-manage/list-secret/CHANGELOG.md` | 更新日志 |
| `gcp/secret-manage/list-secret/IMPLEMENTATION-COMPARISON.md` | 实现方案对比分析 |
| `gcp/secret-manage/list-secret/PERFORMANCE-OPTIMIZATION.md` | 性能优化指南 |
| `gcp/secret-manage/list-secret/QUICK-REFERENCE.md` | GCP Secret Manager 审计脚本 - 快速参考 |
| `gcp/secret-manage/list-secret/README-PARALLEL.md` | 并行版本使用指南 |
| `gcp/secret-manage/list-secret/README-audit-scripts.md` | GCP Secret Manager 权限审计脚本 |
| `gcp/secret-manage/list-secret/README.md` | GCP Secret Manager 审计脚本集合 |
| `gcp/secret-manage/list-secret/VERSION-COMPARISON.md` | 版本对比指南 |
| `gcp/secret-manage/list-secret/chatgpt-list.md` | 1. 获取所有 Secret 名称（仅一次 API 调用） |
| `gcp/secret-manage/list-secret/merge-secret-data.md` | jq script to merge secret info and IAM policy |
| `gcp/secret-manage/list-secret/merged-scripts.md` | Shell Scripts Collection |
| `gcp/secret-manage/list-secret/summary.md` | list-all-secrets-simple-optimized.sh |
| `gcp/secret-manage/onboarding.md` | Create SM GCP group |
| `gcp/secret-manage/pod-start.md` | 流程说明 |
| `gcp/secret-manage/sa-secret-manage.md` | summmary |
| `gcp/secret-manage/secert-manage-python-debug.md` | secret manage logs |
| `gcp/secret-manage/secret-manage-file.md` | q |
| `gcp/secret-manage/secret-manage-grpc-netty-shaded.md` | ChatGPT |
| `gcp/secret-manage/secret-manage-ssl.md` | size > 64KB |
| `gcp/secret-manage/secret-mongo.md` | simple flow |
| `gcp/secret-manage/secret-todo.md` | 问题描述 |
| `gcp/secret-manage/verify-sa.md` | summary and flow |

### GCP Service Account / IAM Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/sa/SA-Control-and-Compliance.md` | TODO |
| `gcp/sa/active-serviceaccount.md` | 颜色定义 |
| `gcp/sa/gcp-sa-housekeep.md` | GCP Service Account Key Housekeeping: Best Practices and Automation |
| `gcp/sa/gcp-sa-json-quota.md` | Handling GCP Service Account Key Quota Errors |
| `gcp/sa/gke-ksa-iam-authentication-flow.md` | GKE KSA IAM Based Authentication Flow |
| `gcp/sa/iam-based-authentication.md` | IAM Based Authentication 详解 |
| `gcp/sa/iam-service-account.md` | 3. 检查 SA 自身的 IAM 策略（用于 Workload Identity） |
| `gcp/sa/merged-scripts.md` | Shell Scripts Collection |
| `gcp/sa/service-agent.md` | GCP 中的 Service Agent（服务代理）理解指南 |
| `gcp/sa/serviceaccountuser-securityreviewer.md` | GCP Roles: roles/iam.serviceAccountUser and roles/iam.securityReviewer |
| `gcp/sa/verify-another-proj-sa.md` | ============================================================================== |
| `gcp/sa/verify-cross-project-pub-sub-sa.md` | verify-cross-project-pub-sub-sa.sh |
| `gcp/sa/verify-gcp-sa.md` | 设置颜色输出 |
| `gcp/sa/verify-iam-based-authentication-enhance.md` | 设置颜色输出 |
| `gcp/sa/verify-sa-iam-based-authentication.md` | summary |

### GCS Bucket Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/buckets/QUICKREF.md` | GCS Bucket 批量创建 - 快速参考 |
| `gcp/buckets/README.md` | GCS Bucket 批量创建脚本使用说明 |
| `gcp/buckets/VERIFY-README.md` | GCS Bucket 验证脚本使用说明 |
| `gcp/buckets/buckets-add-binging-sa.md` | Chatgpt |
| `gcp/buckets/buckets-des.md` | `gcloud storage buckets describe pre-env-region-gkeconfigs --project=<project-id> --format=json` |
| `gcp/buckets/buckets-migrate.md` | Google Cloud Storage Buckets 配置迁移方案 |
| `gcp/buckets/buckets-role.md` | GKE Service Account and Bucket Access Configuration Guide |
| `gcp/buckets/buckets-version-lifecycle.md` | 1. 启用版本控制 |
| `gcp/buckets/compare-lifecycle-file.md` | 下载文件的两个不同版本 |
| `gcp/buckets/mer.md` | Shell Scripts Collection |
| `gcp/buckets/merged-scripts.md` | Shell Scripts Collection |
| `gcp/buckets/verify-buckets-iam.md` | GCS Bucket IAM 绑定验证脚本 |
| `gcp/storage/STORAGE-3-PROTOCOLS-COMPARISON.md` | GKE 存储挂载 3 协议对照总表(SMB / NFS / Bucket) |
| `gcp/storage/buckets/ADR-011-decision-tree.md` | ADR-011 · 决策树清单(GKE 跨 project 访问 Bucket) |
| `gcp/storage/buckets/ADR-011-gke-pod-cross-project-bucket-security-review.md` | ADR-011: GKE Pod 跨项目访问 Cloud Storage Bucket 安全与架构影响评估 |
| `gcp/storage/buckets/ADR-011-pod-bucket-flow.md` | ADR-011 · Pod 跨 project 访问 Bucket 完整链路与顺序概念澄清 |
| `gcp/storage/buckets/gke/01-deployment-yaml-template.md` | 01 · Deployment YAML 完整模板(跨 project 访问 Bucket) |
| `gcp/storage/buckets/gke/02-bucket-policy-guide.md` | 02 · 跨 project Bucket IAM Policy 设置指南(infra-gcp 视角) |
| `gcp/storage/buckets/gke/03-full-flow-process.md` | 03 · 端到端流程 —— 业务方到生产的完整链路 |
| `gcp/storage/buckets/gke/04-quick-start-sh.md` | 04 · Quick Start —— infra-gcp 5 分钟跑通 |
| `gcp/storage/buckets/gke/README.md` | ADR-011 · Bucket 跨项目访问部署参考集 |
| `gcp/storage/cloud-bak.md` | Using products in GCP to back up resources |
| `gcp/storage/cloud-storage-transfer-service.md` | 何时使用 Storage Transfer Service |
| `gcp/storage/gke-pv-creation-through-pod-mount.md` | GKE PV 资源创建 → Pod 挂载 |
| `gcp/storage/gke-pv-multi-tenant-design.md` | GKE PV 多租户平台设计 |
| `gcp/storage/gke-pv-provisioning-flow.md` | GKE PV 资源创建 → Pod 挂载全链路过程详解 |
| `gcp/storage/gke-pv-storageclass-choice.md` | GKE PV 存储方案:默认 StorageClass vs 自定义 StorageClass 的架构选型 |
| `gcp/storage/nas/ADR-009-decision-tree.md` | ADR-009 · 决策树清单(GKE 挂 NAS) |
| `gcp/storage/nas/ADR-009-english-status-update.md` | NAS Mount on GKE — Current Status & Process |
| `gcp/storage/nas/ADR-009-gke-pod-mount-internal-nas-security-review.md` | ADR-009: GKE Pod 挂载公司内部 NAS 的安全与架构影响评估 |
| `gcp/storage/nas/ADR-009-pod-nas-mount-flow.md` | ADR-009 · Pod 挂 NAS 完整链路与顺序概念澄清 |
| `gcp/storage/nas/ADR-009-q6a-path-decision.md` | ADR-009 · Q6-a 验证路径决策对比 |
| `gcp/storage/nas/gke/01-deployment-yaml-template.md` | 01 · Deployment YAML 完整模板 + 字段注释 + 安全要点 |
| `gcp/storage/nas/gke/02-pv-creation-guide.md` | 02 · PV 创建指南 + 与 PVC 的关系 + 绑 PVC 流程 |
| `gcp/storage/nas/gke/03-full-flow-process.md` | 03 · 端到端流程 —— 业务方到生产的完整链路 |
| `gcp/storage/nas/gke/04-quick-start-sh.md` | 04 · Quick Start —— infra-gcp 5 分钟跑通 |
| `gcp/storage/nas/gke/README.md` | ADR-009 · NAS 挂载部署参考集(GKE 平台) |
| `gcp/storage/nfs/NFS-deployment-guide.md` | NFS 挂载实施指南(精简版) |
| `gcp/storage/nfs/NFS-vs-SMB-decision.md` | SMB vs NFS 决策表(精简版) |
| `gcp/storage/nfs/README.md` | NFS 挂载参考集(GKE 平台) |
| `gcp/storage/pv-with-pvc.md` | PV vs PVC —— 集群范围 vs namespace 范围 · 概念澄清 |

### GCP Network/PSC Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/network/cross-project-mig.md` | Cross-Project MIG / Backend Service 跨项目调用 |
| `gcp/network/flow-api-timeout.md` | 请求分析 |
| `gcp/network/google-cross-project-service.md` | GCP Cross-Project Service Referencing 深度解析 |
| `gcp/network/latest-status.md` | Latest Status |
| `gcp/network/nat-timeout-gemini.md` | Cloud NAT TCP TIME_WAIT Timeout 变更架构评估 (Gemini) |
| `gcp/network/nat-timeout.md` | Cloud NAT TCP TIME_WAIT 从 120s 到 30s 的影响评估 |
| `gcp/network/nat.md` | case |
| `gcp/network/neg.md` | NEG |
| `gcp/network/network-endpoint-groups.md` | 1. 列出所有相关 NEG |
| `gcp/network/proxy.md` | Google 的认证方式 |
| `gcp/network/psc-sre/psc-monitor.md` | * **监控关键指标：** 必须在 Cloud Monitoring 中监控 `private_service_connect/producer/nat_ip_utilization`。 |
| `gcp/network/psc-sre/psc-subnet-autoscale.md` | ... |
| `gcp/network/psc-subnet/ip-range.md` | **2 多集群扩展规划 (基于 192.168.x.x)** |
| `gcp/network/psc-subnet/propagated.md` | 传播连接简介 (Propagated Connections) |
| `gcp/network/psc-subnet/psc-nat-vs-proxy-only-subnet.md` | PSC NAT Subnet vs Proxy-Only Subnet — 概念详解（参考材料） |
| `gcp/network/psc-subnet/psc-sub-last-eng.md` | background |
| `gcp/network/psc-subnet/psc-sub-last.md` | background |
| `gcp/network/psc-subnet/psc-subnet-enhance.md` | PRIVATE_SERVICE_CONNECT 定义与规划（单区域 10 集群 / 单集群内多 Attachment / 高访问量版） |
| `gcp/network/psc-subnet/psc-subnet-utilization.md` | PSC Subnet Utilization 深度解析 |
| `gcp/network/psc-subnet/psc-subnet.md` | 1. 核心逻辑：IP 耗尽 vs 吞吐限制 |
| `gcp/network/qwen-read-cross-project.md` | Cloud Load Balancing 跨项目服务引用功能详解 |
| `gcp/network/response-policy.md` | export json |
| `gcp/network/sidecar.md` | 什么是 Sidecar 容器？ |
| `gcp/network/summary-tcp-http-timeout-gemini.md` | API Timeout Analysis Summary: Success in Logs but Timeout in Client |
| `gcp/network/summary-tcp-http-timeout-qwen.md` | Summary: TCP vs HTTP Timeout in GCP Load Balancers |
| `gcp/network/tcp-wich-http-timeout.md` | Q |
| `gcp/psa-psc/Hub-Spoke.md` | Hub-Spoke 网络架构指南 |
| `gcp/psa-psc/Kiro-psc-CloudSQL.md` | Google Cloud Private Service Connect (PSC) 实施指南 - Cloud SQL 场景 |
| `gcp/psa-psc/dua-network-attacement-to-private-network.md` | 双网卡主机跨 VPC 暴露：基于私有/特权网络 (Privilege Network) 创建 PSC Service Attachment |
| `gcp/psa-psc/gemini-psc.md` | 使用 Private Service Connect (PSC) 连接跨项目 VPC |
| `gcp/psa-psc/gke-attachment.md` | Create ServiceAttachment. |
| `gcp/psa-psc/psa-vpc.md` | **🧩 一、配置整体含义** |
| `gcp/psa-psc/psa-with-psc.md` | GCP 私有网络连接：PSA 与 PSC 完整指南 |
| `gcp/psa-psc/psa.md` | 使用以下命令： |
| `gcp/psa-psc/psc-Redis.md` | Google Cloud Private Service Connect (PSC) 实施指南 - Redis 场景 |
| `gcp/psa-psc/psc-bard.md` | Summary ask question |
| `gcp/psa-psc/psc-concept.md` | Private Service Connect (PSC) 概念指南 |
| `gcp/psa-psc/psc-connect-consumer.md` | verify |
| `gcp/psa-psc/psc-cross-region.md` | PSC 跨 Region 连接：平台 Consumer 访问不同 Region 的 Producer |
| `gcp/psa-psc/psc-dr/README.md` | GCP PSC 跨 Region DR 可行性评估 |
| `gcp/psa-psc/psc-dr/dr-runbook.md` | DR 演练 Runbook：GKE(europe-west2) + PSC → Cloud SQL(europe-west1) |
| `gcp/psa-psc/psc-psa-compare.md` | **🧭 一、PSA 与 PSC 的核心定位对比** |
| `gcp/psa-psc/psc-sql-flow-demo/Flow.md` | PSC Demo 流程图和架构说明 |
| `gcp/psa-psc/psc-sql-flow-demo/README.md` | GKE Pod 通过 PSC 连接 Cloud SQL 演示 |
| `gcp/psa-psc/psc-sql-flow-demo/docs/DEPLOYMENT_GUIDE.md` | GKE Pod 通过 PSC 连接 Cloud SQL 部署指南 |
| `gcp/psa-psc/psc-sql-flow-demo/docs/TROUBLESHOOTING.md` | 故障排除指南 |
| `gcp/psa-psc/psc-sql-flow-demo/k8s/3307.md` | 3307 — 我到底为什么必须开放这个端口？完整 debug 答案 |
| `gcp/psa-psc/psc-sql-flow-demo/k8s/cloud-sql-proxy-3307-not-listening.md` | Cloud SQL Auth Proxy Sidecar — 3307 真的在 Listen 吗？排查真相清单 |
| `gcp/psa-psc/psc-sql-flow-demo/k8s/sql-3307-template.md` | Cloud SQL Auth Proxy 平台级 Deploy 模板最佳实践 |
| `gcp/psa-psc/psc-sql-flow-demo/k8s/why-psc-netpolicy-3307.md` | 为什么 PSC模式下 NetworkPolicy 需要允许 3306/3307 端口 |
| `gcp/psa-psc/psc-sql-flow-demo/scripts/merged-scripts.md` | Shell Scripts Collection |
| `gcp/psa-psc/psc-sql-flow-demo/setup/merged-scripts.md` | Shell Scripts Collection |
| `gcp/psa-psc/psc-sql/README.md` | GKE 通过 PSC 连接 Cloud SQL 示例 |
| `gcp/psa-psc/psc-thinking.md` | 🟢 核心架构总结：PSC Service Attachment 在 Shared VPC 中的落地 |
| `gcp/psa-psc/psc-with-vpc-peering-quota-cost.md` | PSC vs VPC Peering - Quota 与 Cost 对比指南 |
| `gcp/psa-psc/psc.md` | Conditions |
| `gcp/psa-psc/service-attachment-region.md` | 深度探索：Service Attachment 的暴露方式与前提条件 |
| `gcp/psa-psc/temp.md` | Temp |
| `gcp/psa-psc/vpc-peering.md` | VPC Peering 概念指南 |
| `gcp/psa-psc/why-not-using-vpc-peering.md` | 1. 致命缺陷一：IP 地址重叠（Overlap）的终极噩梦 |
| `gcp/psa-psc/why-using-psc.md` | gemini |

### GCP/mTLS Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/mtls/CA.md` | What is CA |
| `gcp/mtls/Glb-Client-Authentication.md` | Client Authentication 和 Server TLS Policy 详解 |
| `gcp/mtls/MTLS-TODO.md` | TODO: |
| `gcp/mtls/Onboard.md` | summay step |
| `gcp/mtls/SSLVerifyDepth.md` | nginx |
| `gcp/mtls/apply-create-static-ip.md` | --network-tier=PREMIUM # 全局IP通常需要 Premium Tier，这是默认值，可以省略 |
| `gcp/mtls/chatgpt-nginx.md` | 你提出的架构设计是 在 HTTPS Google Load Balancer（GLB）上实现多个 mTLS 认证策略，并由后端的 Nginx 服务器通过 location 区分服务并做 FQDN 校验。这在技术上是可行的，但需要注意 Google GLB 在 mTLS 配置... |
| `gcp/mtls/compare-allowlisted-with-truststores.md` | compare-allowlisted-with-truststores — `allowlistedCertificates` 与 `trustStores` 对比 |
| `gcp/mtls/compare-ca-intermediate.md` | summary |
| `gcp/mtls/flow-mtls-log.md` | - summary flow log |
| `gcp/mtls/gcp-certificate-manager.md` | --- Configuration --- |
| `gcp/mtls/get_cert_fingerprint.md` | Function: Display usage instructions for the script |
| `gcp/mtls/glb-mtls-nginx.md` | Gemini |
| `gcp/mtls/glb-mtls-test-with-known-ip.md` | GLB mTLS 测试:已知真实 IP + 客户端证书 + 日志过滤 |
| `gcp/mtls/glb-mtls.md` | summary |
| `gcp/mtls/glb-verify-curl.md` | curl请求分析 |
| `gcp/mtls/glb-verify.md` | gemini |
| `gcp/mtls/how-to-get-ca-int.md` | method 1 |
| `gcp/mtls/https-glb-pass-client.md` | 方案 1: 使用 HTTP 头部传递证书信息 |
| `gcp/mtls/intermediate-ca.md` | DigiCert EV RSA CA G2 |
| `gcp/mtls/merged-scripts.md` | Shell Scripts Collection |
| `gcp/mtls/migrate-cloud-armor.md` | create rule |
| `gcp/mtls/migrate-nginx.md` | Directory and file settings for configuration and output |
| `gcp/mtls/mtls-cloud-armor.md` | 对于GCP的cloud armor rule |
| `gcp/mtls/mtls-cn.md` | 在 Nginx 中进行的 CN 校验，指的是对客户端证书中的 Subject（主题）字段中的 Common Name（CN）字段 进行检查，用于确认客户端身份。 |
| `gcp/mtls/mtls-dropin-session.md` | ⸻ |
| `gcp/mtls/mtls-header.md` | mTLS 工作模式下「HTTP 头」的处理 — GCLB 视角 + 与 Header 的关系 |
| `gcp/mtls/mtls-nginx.md` | 限制文件上传 |
| `gcp/mtls/mtls-table.md` | | 文档内容 | 是否在架构中实现？ | 说明 | |
| `gcp/mtls/mtls-test/generate-ca-and-verify-ca.md` | Function: Display usage instructions for the script |
| `gcp/mtls/mtls-test/sre-mtls-monitor.md` | SRE Monitoring Strategy for TCP MTLS to HTTPS MTLS GLB Migration |
| `gcp/mtls/mtls-test/test-case.md` | Test Case Design for Migrating GCP TCP MTLS to HTTPS MTLS GLB |
| `gcp/mtls/mtls-verify.md` | summary |
| `gcp/mtls/multiple-mtls.md` | 创建包含所有CA证书的TrustConfig |
| `gcp/mtls/named.md` | IMRP |
| `gcp/mtls/onboarding-automation.md` | summary |
| `gcp/mtls/onboarding-ca-with-fingerprint.md` | CA证书Onboarding流程（含指纹存储） |
| `gcp/mtls/onboarding-ca.md` | summary Flow |
| `gcp/mtls/onboarding-verify.md` | Q |
| `gcp/mtls/onboarding-whitelist.md` | 将本地的 white_list.txt 上传到指定的 GCS 存储桶 |
| `gcp/mtls/renew.md` | **✅ 场景背景** |
| `gcp/mtls/ssl-certificates.md` | core concepts |
| `gcp/mtls/trust-config-client-cert-faq.md` | Trust Config + Client Cert 轮换 — FAQ |
| `gcp/mtls/trust-config/add-trust-config.md` | 在 GCP 的 mTLS（Mutual TLS） 配置中，尤其是使用 GKE Gateway (或 Gateway API) 时，trustConfig 是用于配置可信根（trustAnchors）和中间证书（intermediateCAs）等内容的关键部分。当你需要进行... |
| `gcp/mtls/trust-config/allowlistedCertificates.md` | 示例: 计算 PEM 格式根证书的 SHA-256 指纹 |
| `gcp/mtls/trust-config/analyze-trust-configs.md` | --- Configuration --- |
| `gcp/mtls/trust-config/explorer-update-cert.md` | Trust Config 证书更新与存储策略探索 (Explorer Update Cert) |
| `gcp/mtls/trust-config/gcloud-certificate-update-with-import.md` | Q |
| `gcp/mtls/trust-config/mtls-cert-policy.md` | 问题分析 |
| `gcp/mtls/trust-config/mtls-key-eng.md` | Detailed Explanation of mTLS Verification and Private Key Validation (mtls-key.md) |
| `gcp/mtls/trust-config/mtls-key.md` | mTLS 验证与私钥校验详解 (mtls-key.md) |
| `gcp/mtls/trust-config/mtls-trustconfig-nginx.md` | TrustConfig + Nginx 自定义证书信息路由 |
| `gcp/mtls/trust-config/multi-user-trust-config.md` | Trust Config for GCP Certificate Manager |
| `gcp/mtls/trust-config/trust-config-backup.md` | Establishing Robust Backup and Recovery Strategies for GCP TrustConfig |
| `gcp/mtls/trust-config/trust-config-flow.md` | GCP Trust Config 证书验证流程详解 |
| `gcp/mtls/trust-config/trust-config-limit.md` | 直接回答 |
| `gcp/mtls/trust-config/trust-config-lock.md` | 感谢您的进一步说明！您提到希望基于 Cloud Storage Bucket 的机制来实现 Trust Config 文件的锁定，以支持多用户并发更新，避免冲突。以下是基于 Cloud Storage Bucket 的锁定方案，针对多用户同时更新 Trust Config（... |
| `gcp/mtls/trust-config/trustconfig-multip-ca.md` | trust config Version Control |
| `gcp/mtls/trust-config/verify-trust-configs-guide.md` | Trust Config 验证脚本使用指南 |
| `gcp/mtls/verify-user-certificate.md` | Summary |
| `gcp/mtls/why-need-white-list.md` | Why Need White List |

### Logging Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/logs/README.md` | Logs 知识库 |
| `gcp/logs/cross-project-sharing-logs.md` | GCP Cross-Project Log Sharing 最佳实践 |
| `gcp/logs/docs/Fluentd.md` | Fluentd 日志处理详解：以 GCP + Nginx 为例 |
| `gcp/logs/docs/Interconnect-flow.md` | Interconnect Flow: UK VPC to HK VPC |
| `gcp/logs/docs/anaylize-gcp-log.md` | 补充说明 |
| `gcp/logs/docs/cross-project-vpc-analyze-claude.md` | GCP Shared VPC 跨 Project 日志追踪与 VPC 互联详解 |
| `gcp/logs/docs/cross-project-vpc-anaylize-ChatGPT.md` | 查询 IP 属于哪个 subnet |
| `gcp/logs/docs/cross-project-vpc-anaylize-claude-application.md` | GCP Shared VPC 跨 Project 日志追踪与 VPC 互联详解 |
| `gcp/logs/docs/cross-project-vpc-anaylize-gemini-1.md` | Cross-Project Shared VPC Log Analysis and Interconnect Concepts |
| `gcp/logs/docs/cross-project-vpc-anaylize-gemini.md` | Cross-Project VPC Log Analysis: A Gemini Synthesis |
| `gcp/logs/docs/interconnects.md` | GCloud Compute Interconnects Attachments Describe |
| `gcp/logs/docs/intro.md` | 我需要跨2个GCP Project Shared VPC里面抓日志 |
| `gcp/logs/docs/proxystatus.md` | 这个日志信息出现在 GCP Logs Explorer 中，提示为： |
| `gcp/logs/docs/summary-cross.md` | summary |
| `gcp/logs/docs/test.md` | **gcloud compute interconnects attachments list** |
| `gcp/logs/docs/vlan.md` | **gcloud compute interconnects attachments list** |
| `gcp/logs/docs/vpc-claude.md` | GCP Shared VPC 跨 Project 日志追踪完整解决方案 |
| `gcp/logs/docs/vpc-log.md` | Summary |
| `gcp/logs/filter-health.md` | 何用gcloud 命令修改mig的health check |
| `gcp/logs/filter-pod-number.md` | 在 GCP 工程中，如果您想基于某个 Deployment 的 Labels 信息（如 k8s-pod/app）过滤 Pods，并统计它们在一个时间段内的所有 不重复的 pod_name，以下是可行的方法： |
| `gcp/logs/gcp-log-view.md` | ChatGPT |
| `gcp/logs/log-limit.md` | **最佳实践方案** |
| `gcp/logs/log-limition.md` | GCP 日志监控和限制最佳实践 |
| `gcp/logs/splunk/README.md` | Splunk 知识库 |
| `gcp/logs/splunk/docs/Splunk-client-agent.md` | 对于Splunk服务端来说,要收集Splunk客户端Agent发送过来的数据,主要需要注意以下两点配置: |
| `gcp/logs/splunk/docs/Splunk-other.md` | Splunk Other |
| `gcp/logs/splunk/docs/base.md` | p |
| `gcp/logs/splunk/docs/splunk-log-format.md` | 在Splunk中，日志格式是指在索引和检索日志数据时使用的特定格式。在Splunk中，主要有两种常见的日志格式：raw格式和restricted格式。 |

### Pub/Sub & Firestore Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/firestore/README.md` | Firestore 知识库 |
| `gcp/firestore/docs/firestore-compare.md` | 方法一：使用Cloud Functions进行变更监听 |
| `gcp/firestore/docs/firestore-export-to-bigquery.md` | Firestore 数据导出到 BigQuery |
| `gcp/firestore/docs/firestore.md` | Firestore 备份 |
| `gcp/firestore/docs/merged-scripts.md` | Shell Scripts Collection |
| `gcp/firestore/docs/tenant-design.md` | Firestore 多项目数据集成与分析架构设计 |
| `gcp/firestore/docs/tenant.md` | summary |
| `gcp/firestore/scripts/README.md` | Firestore 脚本工具集 |
| `gcp/firestore/scripts/merged-scripts.md` | Shell Scripts Collection |
| `gcp/pub-sub/StreamingPull.md` | A |
| `gcp/pub-sub/TPS.md` | My Summary |
| `gcp/pub-sub/Testing.md` | **✅ 说明要点** |
| `gcp/pub-sub/ack.md` | ✅ Your Architecture: Acknowledge on Receipt (At-Most-Once Delivery) |
| `gcp/pub-sub/block-enhance.md` | Result |
| `gcp/pub-sub/cross-project-pub-sub-debug-sa.md` | Cross-Project Pub/Sub + GKE Workload Identity Debug Guide |
| `gcp/pub-sub/css2/compare-firestore-secret-cost-cn.md` | Firestore 与 GCP Secret Manager 成本比较 |
| `gcp/pub-sub/css2/compare-firestore-secret-cost.md` | Firestore vs GCP Secret Manager Cost Comparison |
| `gcp/pub-sub/css2/compare-firestore-secret-table-cn.md` | Firestore 与 Secret Manager 成本对比表 |
| `gcp/pub-sub/css2/compare-firestore-secret-table.md` | Firestore vs Secret Manager Cost Comparison Table |
| `gcp/pub-sub/css2/css-enhance-plan.md` | **一、问题分析（你现在真正要解决的是什么）** |
| `gcp/pub-sub/css2/css-enhance-summary.md` | Cloud Scheduler 服务认证增强方案摘要 (Summary) |
| `gcp/pub-sub/css2/css-enhance.md` | Cloud Scheduler 服务优化方案：基于 Secret Manager 的认证增强 |
| `gcp/pub-sub/css2/css-secret-notifications-cn.md` | GCP Secret Manager 事件通知实现最优缓存策略 |
| `gcp/pub-sub/css2/css-secret-notifications.md` | GCP Secret Manager Event Notifications for Optimal Caching Strategy |
| `gcp/pub-sub/css2/droid-css-enhance.md` | Cloud Scheduler Service Authentication Enhancement - Droid Analysis Report |
| `gcp/pub-sub/css2/explorer-ob-schedule-secret-manage.md` | Scheduler Job Onboarding 与 Secret Manager 集成探索 |
| `gcp/pub-sub/css2/pub-sub-type.md` | **一、问题分析** |
| `gcp/pub-sub/dlq.md` | no DLP |
| `gcp/pub-sub/flow-and-concept.md` | 1. 任务触发：Cloud Scheduler 按预定计划，向指定的 Pub/Sub Topic 发布一条消息。 |
| `gcp/pub-sub/io.md` | 很好，下面我为你清晰解释什么是 IO 密集型场景（IO-bound workload），并结合你现在的 GKE + Pub/Sub + Backend API 的模型来说明它的实际意义。 |
| `gcp/pub-sub/open_streaming_pulls.md` | **✅** |
| `gcp/pub-sub/pub-sub-base.md` | 给用户 user@example.com 授予发布权限 |
| `gcp/pub-sub/pub-sub-block.md` | 你当前的服务结构如下所示： |
| `gcp/pub-sub/pub-sub-cmek/USAGE.md` | GCP Pub/Sub CMEK Manager - Usage Guide |
| `gcp/pub-sub/pub-sub-cmek/merged-scripts.md` | Shell Scripts Collection |
| `gcp/pub-sub/pub-sub-cmek/pub-sub-alma.md` | Cloud Scheduler & Pub/Sub CMEK 集成全解析 / The Ultimate Guide to Pub/Sub CMEK with Cloud Scheduler |
| `gcp/pub-sub/pub-sub-cmek/pub-sub-cmek-kms-summary.md` | Pub/Sub CMEK & Cloud Scheduler `NOT_FOUND` Error Summary |
| `gcp/pub-sub/pub-sub-cmek/schedule-job-cmek-kms.md` | Cloud Scheduler + CMEK 完全排障手册 / Complete Troubleshooting Guide |
| `gcp/pub-sub/pub-sub-cmek/schedule-job-cmek.md` | Cloud Scheduler & CMEK: Resume Failure Analysis / Cloud Scheduler 与 CMEK：恢复失败分析 |
| `gcp/pub-sub/pub-sub-cmek/schedule-job-resume.md` | Cloud Scheduler Resume Failure: NOT_FOUND / Cloud Scheduler 恢复失败：资源未找到 |
| `gcp/pub-sub/pub-sub-cmek/scheduler-jobs-describe.md` | **📄 示例命令** |
| `gcp/pub-sub/pub-sub-command.md` | command |
| `gcp/pub-sub/pub-sub-max-delivery-attempts.md` | Summary |
| `gcp/pub-sub/pub-sub-message.md` | Maybe Flow |
| `gcp/pub-sub/pub-sub-monitor-parameter-english.md` | **Core Metrics for Pub/Sub Consumer Performance** |
| `gcp/pub-sub/pub-sub-monitor-parameter.md` | **Pub/Sub 消费性能相关核心指标** |
| `gcp/pub-sub/pub-sub-push-pull-to-ack-delta.md` | 1. Publish to Ack Delta |
| `gcp/pub-sub/pub-sub-queue-command.md` | summary |
| `gcp/pub-sub/pub-sub-schedule-time.md` | **✅ GCP Pub/Sub 的两种订阅模式** |
| `gcp/pub-sub/pub-sub-subscription-create.md` | Pub/Sub Subscription 创建失败：`request is prohibited by organization's policy` 问题分析 |
| `gcp/pub-sub/pub-sub-subscriptions.md` | ackDeadlineSecends |
| `gcp/pub-sub/pub-sub-summary-english.md` | Q |
| `gcp/pub-sub/pub-sub-summary.md` | Q |
| `gcp/pub-sub/pub-sub-testing-commond.md` | 好的，我们可以通过 gcloud CLI 完成你这个简单的 Pub/Sub 测试，包括： |
| `gcp/pub-sub/pub-sub-thread.md` | 你的问题很关键。我们来 基于资源配置（1CPU / 1Gi 内存）和后端响应不确定性（10~60s），推导出一个合理的 executor-threads 设置建议。 |
| `gcp/pub-sub/pub-sub-timeout.md` | **✅ ⏱️** |
| `gcp/pub-sub/pub-sub-ttl.md` | 是的，你的思路是对的，Java 客户端在 GKE Pod 中配置 TTL（例如设置处理超时时间） 确实可以作为一种“自我约束机制”，来限制处理时间、防止长时间阻塞或卡死重试逻辑，但要注意几点： |
| `gcp/pub-sub/testing-value-verify.md` | Pub/Sub 消费者性能评估验证 |
| `gcp/pub-sub/testing-value.md` | summary |
| `gcp/pub-sub/unacked-message-by-region.md` | ✅ 核心架构：收到消息立即 ACK（At-Most-Once Delivery） |
| `gcp/pub-sub/wiki.md` | **📡 Google Pub/Sub PULL 模式 + GKE StreamingPull 架构说明** |

### SQL/BigQuery Documentation

| File Path | Title |
| :--- | :--- |
| `database/sql/README.md` | SQL 知识库 |
| `database/sql/docs/api-table.md` | Api Table |
| `database/sql/docs/apihistoryonboarding.md` | claude |
| `database/sql/docs/backup.md` | 1. 使用 BigQuery 快照 (Snapshots) |
| `database/sql/docs/bigquery-tables.md` | 在Google Cloud Platform (GCP) 的BigQuery服务中，跟踪数据可以通过多种方式实现，包括使用虚拟表和原始表的概念。以下是一些关键点，帮助您理解和跟踪BigQuery中的数据： |
| `database/sql/docs/biqquery-sql-cost.md` | 我理解你想要优化BigQuery的查询成本，特别是跨项目查询大量数据的情况。让我为你分析几个解决方案： |
| `database/sql/docs/bq.md` | 当你学习 BigQuery 时，熟悉 SQL 的语法对于编写高效的查询非常重要。以下是一些你可能会发现有用的 SQL 语法和技巧，以及相关的详细文档： |
| `database/sql/docs/bug-query-example.md` | 三平台Bug查询结果示例 |
| `database/sql/docs/collect-py.md` | Fetch pods data from gke master and send to bucket |
| `database/sql/docs/collect.md` | 具体来说,它完成以下任务: |
| `database/sql/docs/compare-firestore-cloudsql.md` | Firestore 与 Cloud SQL 对比 |
| `database/sql/docs/connect-table-query.md` | select distinct a.id,a.owner as team_name,a.name as api_name,a.env,a.region From `gcp-projects-374115.apis.apis` a where a.id not in (sel... |
| `database/sql/docs/cost.md` | summary |
| `database/sql/docs/duckdb-usage.md` | DuckDB 使用指南 |
| `database/sql/docs/duckdb.md` | duckdb |
| `database/sql/docs/general-view.md` | 步骤1：提取Schema信息 |
| `database/sql/docs/group.md` | GROUP BY 子句的详细用法及示例 |
| `database/sql/docs/id-sql-table.md` | | platform | eid | jiratier | fromapi | consistency_status | |
| `database/sql/docs/id-sql.md` | 三平台Bug查询结果示例 ,比如我把这个结果保存到一个表格中，叫做project.d |
| `database/sql/docs/join-csv.md` | 创建或清空输出文件 |
| `database/sql/docs/join.md` | 有2个表一个A,比如说A里面有api_name,MID,一个B .api_name,TeamNumber,ORG其中他们都有一个共同的字段比如api_name,我想把2个表中api_name相同的查询出来 其对应的MID |
| `database/sql/docs/json.md` | Json |
| `database/sql/docs/newadd-id-uniq.md` | SQL 解析 |
| `database/sql/docs/paibian.md` | **示例：** |
| `database/sql/docs/pod-memory-cpu.md` | 你想要在 BigQuery 中通过 api_name 汇总每个 api_name 所有 Pod 的 CPU 和内存的使用情况。你可以使用 SQL 查询来进行这些累加计算。以下是如何编写查询的步骤： |
| `database/sql/docs/push-sink.md` | 1. **定义表结构模式** |
| `database/sql/docs/query-csv-match.md` | Query CSV Match |
| `database/sql/docs/rn.md` | 好的，以下是一些关于 SQL 语句中 `row_number` 函数和 `rn` 用法的例子，并附带详细解释： |
| `database/sql/docs/select.md` | 插入数据到表中 |
| `database/sql/docs/sql-5432.md` | 要从另一个 Google GCP 工程中通过 IAM 认证方式访问暴露在 5432 端口的 Cloud SQL，通常需要满足以下条件： |
| `database/sql/docs/team-cpu-and-memory-api.md` | summary cost |
| `database/sql/docs/team-cpu-and-memory.md` | claude |
| `database/sql/docs/timesheet.md` | timesheet |
| `database/sql/docs/union-query.md` | 合并三个表的查询结果并去重 |
| `database/sql/docs/uniq.md` | 在SQL中，`UNION` 操作符用于合并两个或多个 `SELECT` 语句的结果集，生成一个统一的结果集。使用 `UNION` 时，请注意以下几点： |
| `database/sql/docs/useful-sql.md` | -- 1. COALESCE: 返回列表中第一个非空值 |
| `database/sql/docs/v4-claude.md` | only need REPLACE |
| `database/sql/docs/v4-detail-explan.md` | 1. `WITH` 子查询（公用表表达式，CTE） |
| `database/sql/docs/v4-fix.md` | 您遇到的问题确实是由于在连接表时产生了不必要的组合,导致了笛卡尔积。这主要是因为`aibangteams`表中没有区分region的信息,而`gke_pods`表中包含region信息。为了解决这个问题,我们需要在JOIN条件中添加更多的限制,以确保只连接正确的数据。以下是... |
| `gcp/bigquery/big-query-bk.md` | 创建BigQuery客户端 |
| `gcp/bigquery/bigquery-base-practice.md` | Q |
| `gcp/bigquery/bigquery-how-to-insert-update.md` | requirements |
| `gcp/bigquery/bigquey-cmek.md` | 我来帮你创建一个描述BigQuery数据集位置选择流程的图表。考虑到这是一个决策树形式的流程，我觉得用flowchart会是最清晰的选择。​​​​​​​​​​​​​​​​ |
| `gcp/bigquery/create-table-from-other-pro.md` | 在 Google Cloud 中，跨项目访问 BigQuery 表是可能的。你可以在 A 工程中创建一个数据库，并引用 B 工程的 b.abc_stats 表。具体步骤如下： |
| `gcp/bigquery/create-table-schema.md` | create table |
| `gcp/bigquery/numeric.md` | 在 BigQuery 中，NUMERIC 和 FLOAT64 都是用于存储数值数据的类型，但它们有几个关键区别： |
| `gcp/sql/eid.md` | Requirements |
| `gcp/sql/gcp-postgresql.md` | 1. **PostgreSQL 的基础概念** |
| `gcp/sql/sync_data.md` | 设置错误处理 |

### GKE Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/gke/GKE-cluster-autoscaler.md` | node pool |
| `gcp/gke/GKE-upgrade-contained2.md` | GKE containerd 2.0 Upgrade Assessment |
| `gcp/gke/README.md` | GKE (Google Kubernetes Engine) 知识库 |
| `gcp/gke/connect-gke.md` | 获取凭据（这会自动更新你的 ~/.kube/config） |
| `gcp/gke/docs/Blue-Green-design.md` | Summary |
| `gcp/gke/docs/Blue-Green.md` | Blue-Green and Canary Deployment: Key Focus Areas |
| `gcp/gke/docs/GKE-Labels.md` | GKE 集群标签 |
| `gcp/gke/docs/GKE-Master.md` | Application-layer secrets encryption 的类型和密钥的配置可能会影响到能否连接 GKE 集群的 master 节点。 |
| `gcp/gke/docs/GKE-Pod-Disk.md` | **✅** |
| `gcp/gke/docs/Kong-canary.md` | 示例：创建 Upstream |
| `gcp/gke/docs/Multi-tenant.md` | **🧭 一、总体思路：你需要从三大维度出发** |
| `gcp/gke/docs/connect-GKE.md` | For our environment, we don't want to mix components. It's both Nginx and squid. Your team should also provide corresponding options late... |
| `gcp/gke/docs/experimental-install.md` | experimental-install.yaml 分析报告 |
| `gcp/gke/docs/explorer-gke-type.md` | GKE CRD 在集群升级后的保留行为探索 |
| `gcp/gke/docs/gke-blue-green.md` | 蓝绿部署操作思路 (结合你的 API 流) |
| `gcp/gke/docs/gke-job-runner.md` | GKE 上的 Job Runner（任务执行）概念入门 |
| `gcp/gke/docs/gke-node-version.md` | 对于无法直接登录的GKE (Google Kubernetes Engine) 节点，您仍然有几种方法可以获取节点信息，包括Linux版本。以下是一些常用的方法： |
| `gcp/gke/docs/gke-sa-gcp-sa-addbinding-claude.md` | Q |
| `gcp/gke/docs/gke-sa-gcp-sa-addbinding.md` | 创建一个 GCP 服务账户 |
| `gcp/gke/docs/gke-service-protection.md` | GKE 中的服务保护功能解析 |
| `gcp/gke/docs/gke-type.md` | 命令1：查看GatewayClass资源 |
| `gcp/gke/docs/gke-upgrade.md` | GKE cluster 在做GKE master upgrade的时候 deployment 是平滑的？有没有downtime? 我是运行了至少2个Pod |
| `gcp/gke/docs/grafana-gke.md` | chatgpt |
| `gcp/gke/docs/intra-namespace-call.md` | GKE 同 Namespace 内部调用（Intra Namespace Call）方案 |
| `gcp/gke/docs/knative-on-gke.md` | Knative on GKE：Serverless 基础概念 |
| `gcp/gke/docs/multi-tenant-cluster.md` | **🧭 一、总体思路：你需要从三大维度出发** |
| `gcp/gke/docs/node-pool-describe.md` | strategy |
| `gcp/gke/docs/universal-control-plane-argocd-crossplane.md` | 通用控制平面：Argo CD + Crossplane + GKE |
| `gcp/gke/filter-deployment.md` | reference |
| `gcp/gke/gcp-clock.md` | GCP/GKE 时钟同步机制评估 |
| `gcp/gke/gke-endpoint.md` | GKE 连接端点探索：DNS Endpoint 与 Central API Proxy |
| `gcp/gke/gke-secret-manager.md` | GKE Secret Manager 集成深度分析 |
| `gcp/gke/how-node-upgraded.md` | How-node-upgrade |
| `gcp/gke/kong-blue-green.md` | 创建蓝色环境的服务 |
| `gcp/gke/lifecycle.md` | lifecycle.json |
| `gcp/gke/localpolicy-with-topology.md` | GKE 节点池 Location Policy 与 Topology Spread Constraints |
| `gcp/gke/namespace-stuck-terminating-neg-root-cause.md` | GKE Namespace 卡在 Terminating：NEG 视角的根因分析 |
| `gcp/gke/pod-node-affinity.md` | 详细解释 |
| `gcp/gke/runtime-namespace-networkpolicy.md` | GKE Runtime Namespace NetworkPolicy 设计与落地 |
| `gcp/gke/script/merged-scripts.md` | Shell Scripts Collection |
| `gcp/gke/script/upgrade-gke-cluster.md` | 使用当前激活的 gcloud project，轮询所有集群 |
| `gcp/gke/version.md` | GKE Version Management: Channels, Lifecycle & Control Mechanisms |
| `gcp/gke/what-gke.md` | What is GKE (Google Kubernetes Engine)? |
| `gcp/gke/workload-identify.md` | GKE Namespace 创建脚本详解 |
| `gcp/gke/workload-with-annotate.md` | Workload Identity 与 Namespace Annotate 深度解析 |

### Cost & Dashboard Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/cost/README.md` | Cost 知识库 |
| `gcp/cost/collect-information.md` | **提取文本** |
| `gcp/cost/cost-sql.md` | 配置 GKE 集群的资源使用导出 |
| `gcp/cost/cross-project-public-tls-mtls-billing.md` | Cross-Project × Public TLS / mTLS 服务暴露的 GCP 计费深度分析 |
| `gcp/cost/gcp-cost/README.md` | GCP 日志成本优化工具包 |
| `gcp/cost/gcp-cost/audit-log.md` | 检查审计日志配置 |
| `gcp/cost/gcp-cost/buckets-archive.md` | summary |
| `gcp/cost/gcp-cost/buckets.md` | Cloud Logging 日志存储桶 (Log Buckets) 详解 |
| `gcp/cost/gcp-cost/gcp-cost-gemini.md` | GCP 日志成本优化与治理权威指南 |
| `gcp/cost/gcp-cost/gcp-log-cost.md` | Summay |
| `gcp/cost/gcp-cost/gcp-logging-cost-optimization-guide.md` | GCP 日志成本优化完整指南 |
| `gcp/cost/gcp-cost/script.md` | gcp-logging-audit-script.sh - GCP 项目日志配置审计脚本 |
| `gcp/cost/gcp-cost/workload.md` | 审计 GKE 集群配置 |
| `gcp/cost/gke-cost-allocations.md` | Q |
| `gcp/cost/gke_cluster_resource_consumption.md` | Gke Cluster Resource Consumption |
| `gcp/cost/gke_cluster_resource_usage.md` | <https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-usage-metering> |
| `gcp/cost/one-off-design.md` | V1 |
| `gcp/dashboard/report/README.md` | Report 知识库 |
| `gcp/dashboard/report/docs/3.md` | Coze |
| `gcp/dashboard/report/docs/Bigquery-create-table.md` | 1. 查看原表结构（使用 --schema 参数只获取表结构） |
| `gcp/dashboard/report/docs/Google-LookStudio.md` | **1. 数据源层优化（BigQuery → 缓存/汇总层）** |
| `gcp/dashboard/report/docs/JQL-Search.md` | 我对 Jira REST API 的 /search 端点和 JQL 查询还不太熟悉，特别是如何通过 JQL 查询不同的条件、日期、关键字等内容。详细讲解 JQL 查询的基础知识，并提供大量示例，帮助我理解如何通过不同的查询条件获取 Jira 数据。所有示例都可以直接用于... |
| `gcp/dashboard/report/docs/JQL.md` | 入门 Jira 查询语言 (JQL) 和 Jira REST API 的 `/search` 端点。JQL 是非常强大的工具，可以让你精确地从 Jira 中检索你想要的数据。让我们一步一步来学习。 |
| `gcp/dashboard/report/docs/api-cost-180.md` | 根据你的描述，180 的默认套餐已经包含了初始资源费用 (19*1 + 19*0.5)，即用户扩展资源时，只需要为额外扩展部分的资源支付费用。那么我们可以重新分析公式中的收费逻辑。 |
| `gcp/dashboard/report/docs/api-cost.md` | Q |
| `gcp/dashboard/report/docs/architecture-design.md` | Summary |
| `gcp/dashboard/report/docs/bigquery-add-data.md` | summary |
| `gcp/dashboard/report/docs/bigquery-alert.md` | BigQuery触发器以发送告警？ |
| `gcp/dashboard/report/docs/bigquery-class.md` | 使用Looker Studio进行可视化 |
| `gcp/dashboard/report/docs/bigquery-compare.md` | 定时任务和比对操作 |
| `gcp/dashboard/report/docs/bigquery-cpu-memory.md` | 为了实现你要的逻辑，我们的目标是对比两张表（A 表为实际使用情况，B 表为 Onboarding 提交情况），对每一个团队的 count-cpu 和 count-memory 进行比较，只输出超出 任意一项资源 的团队记录。 |
| `gcp/dashboard/report/docs/bigquery-pub-sub.md` | 方案4：利用BigQuery和Pub/Sub |
| `gcp/dashboard/report/docs/bigquery-scheduler-functions.md` | 方案1：直接从BigQuery查询并发送邮件 |
| `gcp/dashboard/report/docs/bq-sa-query.md` | Q |
| `gcp/dashboard/report/docs/buckets-to-Bigquery.md` | 数据加载方式 |
| `gcp/dashboard/report/docs/calc.md` | <!DOCTYPE html> |
| `gcp/dashboard/report/docs/charge-model.md` | 为了更好地处理 Pod 数量的选择及其逻辑，同时简化管理流程，可以参考以下方案，将 Pod 数量的信息与 API 紧密绑定，并存储在一个合适的数据库或配置管理系统中。以下是推荐的解决方案： |
| `gcp/dashboard/report/docs/class.md` | 以下是对应的Mermaid代码： |
| `gcp/dashboard/report/docs/config-hpa.md` | summary |
| `gcp/dashboard/report/docs/cross-pro-groq.md` | So you have two BigQuery projects, one for dev and one for prod, and you want to combine the data from both projects to calculate the tot... |
| `gcp/dashboard/report/docs/cross-pro.md` | cross dev and prd get differnet priv |
| `gcp/dashboard/report/docs/enhance-apppy.md` | Q |
| `gcp/dashboard/report/docs/get-hpa.md` | summary |
| `gcp/dashboard/report/docs/id.md` | 默认配置 |
| `gcp/dashboard/report/docs/improvements-summary.md` | 时区应用改进总结 |
| `gcp/dashboard/report/docs/jira-bigquery-studio.md` | Question |
| `gcp/dashboard/report/docs/jira-get-page.md` | Build JQL query |
| `gcp/dashboard/report/docs/jira-jql.md` | Q |
| `gcp/dashboard/report/docs/k8s-cronjob-monitor.md` | Create email |
| `gcp/dashboard/report/docs/looker-studio-bak.md` | Looker Studio 的版本控制功能 |
| `gcp/dashboard/report/docs/looker-studio-filter.md` | 步骤1：创建时间过滤器 |
| `gcp/dashboard/report/docs/looker-studio.md` | Google Data Studio 和数据分析关键概念 |
| `gcp/dashboard/report/docs/lookerstudio-data-credentials.md` | 好的，明白了。您在使用 Looker Studio (原 Google Data Studio) 时遇到了 "Data Set Configuration Error"，错误信息是 "The data source no longer has access to the u... |
| `gcp/dashboard/report/docs/merge.md` | 示例 |
| `gcp/dashboard/report/docs/ob.md` | ob value |
| `gcp/dashboard/report/docs/offering.md` | **🧭 Understand Our Offering — Discussion & Debate** |
| `gcp/dashboard/report/docs/pm-sql.md` | ChatGPT |
| `gcp/dashboard/report/docs/quota-requirement.md` | 1. Quota监控和预警机制 |
| `gcp/dashboard/report/docs/report-alert.md` | Q |
| `gcp/dashboard/report/docs/report-vs-dashboard.md` | Google Looker Studio |
| `gcp/dashboard/report/docs/sink-and-coll.md` | ask |
| `gcp/dashboard/report/docs/special-case-data.md` | **一、问题本质（先定性）** |
| `gcp/dashboard/report/docs/studio-time.md` | Looker Studio (Google Data Studio) SQL 查询时间字段最佳实践 |

### GCP General Documentation

| File Path | Title |
| :--- | :--- |
| `gcp/README.md` | GCP (Google Cloud Platform) |
| `gcp/adr/008-static-pod-no-secret-configmap-k8s-137.md` | ADR-008: 应对 Kubernetes v1.37 Static Pod 禁止引用 Secret/ConfigMap 的架构变更 |
| `gcp/adr/README.md` | GCP Architecture Decision Records (ADR) |
| `gcp/artifact-registry/README.md` | Artifact Registry |
| `gcp/artifact-registry/cleanup-policy-assessment.md` | Artifact Registry Cleanup Policy 评估报告 |
| `gcp/gcp-cloud-build/README.md` | Cloud Build |
| `gcp/gcp-cloud-build/cloudbuild-guide.md` | Cloud Build 实操指南（GCP） |
| `gcp/gcp-cloud-build/gcp-cloud-build-concepts.md` | GCP Cloud Build: Comprehensive Concepts Guide |
| `gcp/gcp-cloud-build/how-to-autofix-cve-with-cloud-build.md` | 用 Cloud Build 做 CVE 自动修复闭环 |
| `gcp/gcp-cloud-build/how-to-explore-go-modules.md` | Go 依赖探索手册（`go mod why` / `go mod graph` / `go list -deps`） |
| `gcp/gcp-cloud-build/how-to-github-trigger-cloud-build.md` | 从 GitHub 到 Cloud Build：打通「push → 构建镜像 → 推 Artifact Registry」的完整链路 |
| `gcp/gcp-infor/README.md` | GCP-Infor - GCP Platform Information Tools |
| `gcp/gcp-infor/REVIEW-REPORT.md` | GCP-Infor Scripts Review Report |
| `gcp/gcp-infor/assistant/README.md` | GCP Infor (Linux) - Notes + Verification Helpers |
| `gcp/gcp-infor/assistant/merged-scripts.md` | Shell Scripts Collection |
| `gcp/gcp-infor/gcpfetch-README.md` | GCPFetch - GCP Platform Information Tool |
| `gcp/gcp-infor/linux-scripts/gcp-knowledge.md` | GCP Platform Knowledge - Linux Environment |
| `gcp/gcp-infor/merged-scripts.md` | Shell Scripts Collection |
| `gcp/gsutil.md` | 以下提供一种快速删除 GCP buckets 中文件的方式，建议使用 gsutil 命令，该工具支持并行处理，从而大大加快删除速度。下面是步骤和示例： |
| `gcp/housekeep/instance-delete.md` | GCP 资源清理指南 |
| `gcp/misc/Capacity-Planning-and-Backup-Strategy.md` | **问题总结** |
| `gcp/misc/High-availability.md` | current configure |
| `gcp/misc/Resilience.md` | GCP API 平台弹性增强规划 |
| `gcp/misc/appd-ppt.md` | 以下是关于自定义 APPD（Application Performance Data）汇总功能的 PPT 展示内容大纲，旨在向用户介绍这个功能及其在 GCP 上的实现流程。 |
| `gcp/misc/big-memory-cpu.md` | Analysis |
| `gcp/misc/big-memroy-cpu-analysis.md` | Grok |
| `gcp/misc/multi.md` | pic |
| `gcp/misc/resiliences-gpt.md` | Google Cloud Platform API 平台配置增强与优化 |
| `gcp/recaptcha/recaptcha.md` | reCAPTCHA resilient design |
| `gcp/terraform/README.md` | Terraform GCP 仓库结构 — 最佳实践 |
| `gcp/terraform/examples/envs/dev-project-a/README.md` | `examples/envs/dev-project-a/` — 完整 dev env 例子 |
| `gcp/terraform/references/2025-best-practices-validation.md` | GCP Terraform Monorepo Best Practices — 2025/2026 Validation |
| `gcp/terraform/references/directory-structure.md` | 目录结构 — 详细分解 |
| `gcp/terraform/references/state-and-backend.md` | State / Backend / Secret 管理 |
| `gcp/terraform/references/terragrunt-decision.md` | Terragrunt 升级决策 |
| `gcp/terraform/resourceset/SCHEMA.md` | ResourceSet — Canonical Schema |
| `gcp/terraform/templates/module/README.md` | Module `<name>` |
| `gcp/tools/filter-jq.md` | 提取的信息 |
| `gcp/tools/git.md` | 尝试获取操作系统类型 |
| `gcp/vertex-ai/README.md` | Vertex AI — BYOC 模式 |
| `gcp/vertex-ai/byoc-iam-cicd.md` | Vertex AI — IAM / CI/CD / Pipelines / Gotchas |
| `gcp/vertex-ai/byoc-prediction.md` | Vertex AI — Custom Prediction (BYOC) 端到端 |
| `gcp/vertex-ai/byoc-training.md` | Vertex AI — Custom Training (BYOC) 端到端 |

### Gateway/Kong Documentation

| File Path | Title |
| :--- | :--- |
| `gateway/README.md` | Gateway |
| `gateway/docs/Design.md` | Claude |
| `gateway/docs/README.md` | Gateway 知识库 |
| `gateway/docs/current-q.md` | 问题分析 |
| `gateway/docs/gke-gateway-quota-deepseek.md` | GKE Gateway API 配额深度解析 — 与 CCCC 迁移案例的对照分析 |
| `gateway/docs/gke-gateway-quota.md` | 1. 核心限制：子网（Subnet）与地址空间 |
| `gateway/higress/Higress.md` | Higress |
| `gateway/higress/README.md` | Higress 知识库 |
| `gateway/kong/README.md` | Kong 知识库 |
| `gateway/kong/docs/API-Rate-Limiting.md` | API rate limiting is the practice of controlling how many requests a client can make within a specific time window. It protects your back... |
| `gateway/kong/docs/capture-kong-log.md` | Typical scenarios |
| `gateway/kong/docs/cp-vs-dp.md` | 在 Kong 的配置中，CP 和 DP 分别代表 Control Plane 和 Data Plane，它们是 Kong 的架构组件。CP 负责管理和配置 Kong 节点，而 DP 则处理实际的 API 流量。CP 和 DP 之间通过 WSS（WebSocket Secur... |
| `gateway/kong/docs/debug-kong-gemini.md` | Nginx -> Kong -> GKE 认证流程深度解析 (Gemini版) |
| `gateway/kong/docs/debug-kong.md` | 非常好的问题 👍 |
| `gateway/kong/docs/hazelcast.md` | Hazelcast是一个开源的in-memory数据网格(data grid)技术。它提供了以下主要功能: |
| `gateway/kong/docs/httpbin.md` | **问题分析** |
| `gateway/kong/docs/kong-2.8-vs-3.4.md` | **1. 排查大量`Completed`状态Pod的原因** |
| `gateway/kong/docs/kong-auth-english.md` | Kong AUTHZ Plugin Path-based Group Check Issue Analysis |
| `gateway/kong/docs/kong-auth-group.md` | ChatGPT |
| `gateway/kong/docs/kong-auth.md` | Kong AUTHZ Plugin Path-based Group Check 问题分析 |
| `gateway/kong/docs/kong-chinese.md` | Q |
| `gateway/kong/docs/kong-cluster-secret.md` | Kong 的角色 |
| `gateway/kong/docs/kong-error.md` | Kong 数据平面错误分析 |
| `gateway/kong/docs/kong-file-size.md` | 创建一个服务 |
| `gateway/kong/docs/kong-healthcheck-rt.md` | 更新 Service 配置，添加健康检查 |
| `gateway/kong/docs/kong-hight-availablity.md` | Deeepseek |
| `gateway/kong/docs/kong-ipmatcher.lua.md` | kong.conf |
| `gateway/kong/docs/kong-log-vault-lua.md` | Q |
| `gateway/kong/docs/kong-lua-ssl.md` | Default values for Kong's Helm Chart |
| `gateway/kong/docs/kong-opentelemetry.md` | values.yaml |
| `gateway/kong/docs/kong-plug-limit.md` | 配置项解释 |
| `gateway/kong/docs/kong-post-case.md` | Flow Post.md |
| `gateway/kong/docs/kong-retry-and-describe.md` | summary |
| `gateway/kong/docs/kong-token.md` | 1. **A Client 的 Token** |
| `gateway/kong/docs/kong-underscores_in_header.md` | 开启下划线支持 |
| `gateway/kong/docs/kong-zero-downtime.md` | 查看所有 Completed 状态的 Pod |
| `gateway/kong/docs/migrate-kong.md` | **1. 问题分析** |
| `gateway/kong/docs/payloadsize.md` | 概念解释 |
| `gateway/kong/docs/route.md` | 在Kong中，Route和Service是两个重要的概念。Route定义了API的入口点，它指定了如何将请求路由到后端服务。而Service定义了后端服务的细节，如它的地址、端口、协议等信息。下面是它们的详细解释以及配置例子： |
| `gateway/kong/docs/testcase.md` | function |
| `gateway/kong/docs/x-client-cert-leaf.md` | Q |
| `gateway/kong/kongdp/compare-dp.md` | Kong Data Plane 资源对比工具 |
| `gateway/kong/kongdp/kongdp-setting-timeout.md` | 在 Service 上启用 Retry 插件 |
| `gateway/kong/kongdp/kongdp-status-debug.md` | **✅** |
| `gateway/kong/kongdp/kongdp-status-troubleshoot.md` | Kong Data Plane (DP) Status Troubleshooting Guide |
| `gateway/kong/kongdp/merged-scripts.md` | Shell Scripts Collection |
| `gateway/no-gateway/Gateway-API-allowedRoutes.md` | **🎯 你的本质需求** |
| `gateway/no-gateway/HealthCheckPolicy.md` | 1. 问题分析 |
| `gateway/no-gateway/TODO.md` | 1 HealthCheckPolicy 对于internla Gateway来说必须的么? 通过一些简单的分析对于我们的环境来说增加这个配置还是有必要的。 |
| `gateway/no-gateway/diagram/gateway-2.0-flow.md` | Gateway 2.0 Architecture Flow |
| `gateway/no-gateway/diagram/gateway-2.0-terminal.md` | Gateway 2.0 SSL 终止方案 (强制每跳 HTTPS) |
| `gateway/no-gateway/diagram/gateway-2.0-tls.md` | Gateway 2.0 TLS/证书配置方案 |
| `gateway/no-gateway/diagram/gke-Gateway-quota.md` | GKE Gateway API 配额限制分析 |
| `gateway/no-gateway/diagram/gke-gateway-todo.md` | GKE Gateway 2.0 双入口架构 - 实施评估 TODO |
| `gateway/no-gateway/diagram/gke-gateway-transcription-header-v2.md` | GKE Gateway 2.0 TLS 终止与 Host Header 转写方案（最终版） |
| `gateway/no-gateway/diagram/gke-gateway-transcription-header.md` | GKE Gateway 2.0 TLS 终止与 Host Header 转写方案 |
| `gateway/no-gateway/explorer-no-gateway-gemini.md` | 阿里云 SLB 统一入口下实现 No-Gateway 访问模式 |
| `gateway/no-gateway/explorer-no-gateway.md` | **🧩 问题分析** |
| `gateway/no-gateway/explorer-sequence-yaml.md` | Helm & K8S 资源部署顺序深度探索 (Explorer) |
| `gateway/no-gateway/gateway-safe-control.md` | GKE Gateway 安全控制策略指南 |
| `gateway/no-gateway/gke-gateway-concepts.md` | GKE Gateway Concepts |
| `gateway/no-gateway/gke-gateway-uploadsize.md` | GKE Gateway Upload Size Limit — 调研与方案 |
| `gateway/no-gateway/glb-path.md` | 创建后端服务 (global) |
| `gateway/no-gateway/merged-scripts.md` | Shell Scripts Collection |
| `gateway/no-gateway/no-gateway-2.md` | TLS certs managed at GLB，若 Nginx 也做 TLS，放置证书 |
| `gateway/no-gateway/no-gateway-design.md` | Claude |
| `gateway/no-gateway/no-gateway-gcp-design-gemini.md` | API 平台架构最佳实践方案 (Gemini) |
| `gateway/no-gateway/no-gateway-gkegateway-flow.md` | Summary Architectural |
| `gateway/no-gateway/no-gateway-path-explorer.md` | Q |
| `gateway/no-gateway/no-gateway-path-flow.md` | GKE Gateway API 版本管理完整流程可视化 |
| `gateway/no-gateway/no-gateway-path.md` | nogtw/customer-a-api-health.conf |
| `gateway/no-gateway/nogateway-gkegateway-gemini.md` | Summary Architectural |
| `gateway/no-gateway/verify-gateway-enhance.md` | Enhanced: GKE Internal Gateway Verification Script |
| `gateway/no-gateway/verify-gke-gateway.md` | GKE Internal Gateway 验证脚本 |
| `gateway/no-gateway/version-control/core-concepts-en.md` | Core Concepts: Version Control and Smooth Switching in GKE Gateway API No-Gateway Mode |
| `gateway/no-gateway/version-control/core-concepts.md` | 核心概念：GKE Gateway API 无网关模式下的版本控制与平滑切换 |
| `gateway/no-gateway/version-control/explorer-multi-gateway.md` | 多 Gateway 入口架构设计与实现分析 |
| `gateway/no-gateway/version-control/no-gateway-version-control-cn.md` | GKE Gateway API 版本控制配置审查 |
| `gateway/no-gateway/version-control/no-gateway-version-control-en.md` | GKE Gateway API Version Control Configuration Review |
| `gateway/no-gateway/version-control/no-gateway-version-control-opensource-ingress.md` | OpenSource Ingress (NGINX) API 版本控制与平滑发布指南 |
| `gateway/no-gateway/version-control/no-gateway-version-control.md` | GKE Gateway API Version Control Configuration Review |
| `gateway/no-gateway/version-control/no-gateway-version-ingress-control.md` | Ingress Controller 平滑版本切换与重写最佳实践 |
| `gateway/no-gateway/version-control/no-gateway-version-smoth-switch-en.md` | GKE Gateway API Smooth Version Switching and Validation Best Practices |
| `gateway/no-gateway/version-control/no-gateway-version-smoth-switch.md` | GKE Gateway API 平滑版本切换与验证最佳实践 |
| `gateway/no-gateway/version-control/qwen-ingress-version-control.md` | NGINX Ingress Controller API 版本控制与灰度发布完全指南 |
| `gateway/no-gateway/version-control/verify-no-gateway-version-change.md` | GKE Gateway 版本切换实时验证指南 |
| `gateway/no-gateway/warp-expolorer-nogateway.md` | Warp Explorer: No-Gateway API Version Management Analysis |

### Java Documentation

| File Path | Title |
| :--- | :--- |
| `develop/java/README.md` | Java 知识库 |
| `develop/java/build-tools/dockerbuild-maven.md` | Maven Build |
| `develop/java/debug/debug-Java-jar.md` | Q |
| `develop/java/debug/debug-jar.md` | Debug Guide: 如何在 GKE 中“解剖”无法启动的 JAR 包 |
| `develop/java/debug/debug-java-pod-process.md` | Java Pod Sidecar Debug 流程文档 |
| `develop/java/debug/debug-java-pod.md` | Debug Java Pod: Inspect Failed JAR Images with Sidecar Network-Multitool |
| `develop/java/debug/debug-java-port.md` | Debugging Java Application Port and Health Check Issues in GKE |
| `develop/java/debug/debug-sprint-connect.md` | 我看到这是一个 WebClient 请求过程中出现的 `Connection prematurely closed BEFORE response` 错误。这表明连接在收到完整响应之前就被提前关闭了。让我分析一下这个错误： |
| `develop/java/debug/gke-nmt-logging.md` | GKE Java Native Memory Tracking (NMT) 日志采集方案 |
| `develop/java/debug/gke-pod-create-file.md` | 报错信息显示 Java 程序找不到文件，抛出 `java.nio.file.NoSuchFileException` 异常。 路径类似 `src/main/resources/...xlsm`。 |
| `develop/java/debug/headpdump-hprof.md` | 分析 `headpdump.hprof` 文件的方案 |
| `develop/java/debug/java-G1GC.md` | Q |
| `develop/java/debug/java-gke-pod-version.md` | Q 如何在GKE中批量获取Pod的Java版本信息 |
| `develop/java/debug/java-heapdump.md` | Key Points |
| `develop/java/debug/java-serial.md` | **Java 17 + GKE 中 CPU=1000m 是否会使用 Serial GC？以及如何评估** |
| `develop/java/encoding/encoding.md` | 增加 `-Dfile.encoding=UTF-8` 参数的影响 |
| `develop/java/general/commons-io.md` | 在 GKE 上部署的 Java 应用中，出现“升级 commons-io 版本导致部署失败”的问题，通常可能涉及以下几种情况： |
| `develop/java/general/context-path.md` | GKE Java 应用配置与调试指南 |
| `develop/java/general/gar-version.md` | 利用制品仓库元数据管理版本信息 |
| `develop/java/general/java-develop-language.md` | Java Application Development Methods: Identifying Spring Boot, Tomcat, and JAR Applications |
| `develop/java/general/java-log-level.md` | Java Application Log Level Control in Kubernetes Deployments |
| `develop/java/general/merged-scripts.md` | Shell Scripts Collection |
| `develop/java/general/sectigo.md` | Sectigo 与 Java truststore (cacerts) 检查 |
| `develop/java/general/token.md` | summary |
| `develop/java/general/wiremock.md` | Debugging Guide: `package com.github.tomakehurst.wiremock.client does not exist` |
| `develop/java/java-appd/anaylize.md` | 1. Init Container 的内存占用 (短暂) |
| `develop/java/java-appd/appd-infor.md` | Stage 1: Get the Agent |
| `develop/java/java-appd/appd-refresh-initContainer.md` | How to quick refresh node images |
| `develop/java/java-appd/appd-sidecar.md` | ✅ 1. **Sidecar 能否直接执行 `jcmd`？取决于两个条件** |
| `develop/java/java-appd/java-appd-cret.md` | using which cacerts to connect appdynamics |
| `develop/java/java-appd/java-appd-gemini/README.md` | Java AppDynamics Memory Analysis Guide |
| `develop/java/java-appd/java-appd-gemini/docker-hub-tools.md` | Docker Hub Tools for Java Memory Analysis |
| `develop/java/java-appd/java-appd-gemini/memory-analysis-guide.md` | Memory Analysis Methodology: AppD vs Spring Boot |
| `develop/java/java-appd/java-appd-gemini/sidecar-profiling.md` | Sidecar Profiling Strategy |
| `develop/java/java-appd/java-appd-memory.md` | GKE Deployment 中 Java 应用与 AppDynamics 资源分析 |
| `develop/java/java-appd/jcmd-appd.md` | 使用 JVM **Native Memory Tracking（NMT）** 精准拆分 App vs AppDynamics |
| `develop/java/java-auth/cve-2026-50010-netty-hostname-verification-bypass.md` | CVE-2026-50010 — Netty TLS 客户端 Hostname 验证绕过 |
| `develop/java/java-auth/fix-spring-boot-3-5-16-remove-netty-overrides.md` | Fix: Spring Boot 3.5.16 + Remove Netty Overrides |
| `develop/java/java-auth/gke-pod-cert-verify/README.md` | GKE Pod — 验证 Java 应用实际启用的 HTTPS 证书 |
| `develop/java/java-auth/gke-pod-cert-verify/references/01-shell-access-strategies.md` | 01 — GKE Pod 证书验证:3 种访问权限场景的实战策略 |
| `develop/java/java-auth/gke-pod-cert-verify/references/02-keytool-openssl-cheatsheet.md` | 02 — keytool + openssl 命令速查 |
| `develop/java/java-auth/gke-pod-cert-verify/references/03-spring-boot-yaml-ssl-anatomy.md` | 03 — 代码层:Spring Boot SSL 是怎么挑证书的 |
| `develop/java/java-auth/gke-pod-cert-verify/references/04-san-mismatch-hostname-verify.md` | 04 — 客户端用域名访问 Pod 时报证书错,但绑 IP 又能通 — SAN 不匹配自检 |
| `develop/java/java-auth/gke-pod-cert-verify/references/05-outbound-https-cipher-mismatch.md` | 05 — Java 应用调第三方 HTTPS 报 `handshake_failure` — cipher 协商失败(出站方向) |
| `develop/java/java-auth/gke-pod-cert-vs-cve-2026-50010-diagnosis.md` | 我的 Kong DP → GKE Pod Java 应用报错,跟 CVE-2026-50010 是不是一回事? |
| `develop/java/java-auth/java-application-auth.md` | Q |
| `develop/java/java-auth/netty.md` | Netty 探索笔记 — 抛开漏洞,这东西到底是什么? |
| `develop/java/java-auth/p12-decrypt.md` | Q |
| `develop/java/java-auth/pod-curl.md` | Pod 出站调用第三方 HTTPS 报 `handshake_failure` — 深度分析 + 修法 |
| `develop/java/java-auth/simple-https-demo/README.md` | Simple HTTPS Demo - Dual SSL Role |
| `develop/java/java-code/README.md` | Java Code 知识库 |
| `develop/java/java-code/docs/Java-base-build.md` | Java 基础项目构建文档 |
| `develop/java/java-core/Java-Process-and-Thread.md` | **📌 Java 线程内存消耗评估** |
| `develop/java/java-core/Java-lang-OutOfMemoryError.md` | The Q |
| `develop/java/java-core/Java-memory.md` | Google Studio |
| `develop/java/java-core/java-a-call-b.md` | 为了更好地理解你给出的两种情况及其结果，以下是对这些情境的流程图示例，展示了两个不同的请求路径及其响应。 |
| `develop/java/java-core/java-cgroup.md` | 基于cgroups v2的Java应用部署建议 (针对GCP GKE环境) |
| `develop/java/java-core/java-ci-cd.md` | 1. **利用CI生成版本标签文件并传递给CD** |
| `develop/java/java-core/java-define-build-docker-version.md` | 1. **在pom.xml中定义Java版本属性** |
| `develop/java/java-core/java-eden-enhance.md` | claude |
| `develop/java/java-core/java-encoding.md` | 了解您的环境是基于 Linux 系统并运行 Java 环境的 Pod，这确实有助于我们更精确地进行问题排查。让我们一步步来检查服务器的文件系统编码和 Java 运行时的默认编码设置： |
| `develop/java/java-core/java-env.md` | install Java |
| `develop/java/java-core/java-export-cert.md` | 要从 Java Docker 容器中导出 API JDK 中证书的序列号，可以通过以下步骤实现。这通常涉及导出 JDK 中的证书库（keystore），并使用 keytool 工具查看证书的序列号。 |
| `develop/java/java-core/java-gs-error.md` | llama3 |
| `develop/java/java-core/java-jdk-jre.md` | First Stage: Build |
| `develop/java/java-core/java-jdk-targetversion.md` | 使用JDK 11进行编译 |
| `develop/java/java-core/java-mail-verify.md` | 从你提供的信息来看，问题似乎与Java邮件客户端的证书验证有关，尤其是在尝试建立TLS连接时发生了SSL握手异常。错误信息表明，Java客户端无法验证邮件服务器的证书路径，具体的错误是： |
| `develop/java/java-core/java-mail.md` | summary |
| `develop/java/java-core/java-mule-error.md` | 我的日志有如下报错,帮我分析下如何解决和排查问题? |
| `develop/java/java-core/java-post-memory.md` | ChatGPT |
| `develop/java/java-core/java-post.md` | summary |
| `develop/java/java-core/java-redis-error.md` | Debug和解决步骤 |
| `develop/java/java-core/java-sni.md` | Summary |
| `develop/java/java-core/java-upload.md` | Q |
| `develop/java/java-core/java-utf-8.md` | **✅ 回答关键问题** |
| `develop/java/java-core/java-version-define.md` | 1. **Maven 构建版本的选择** |
| `develop/java/java-core/java-version.md` | claude |
| `develop/java/java-pom/Java-Maven-dep-debug.md` | Java Maven 依赖问题排查文档集 |
| `develop/java/java-pom/com.github.tomakehurst.wiremock.client.md` | **一、** |
| `develop/java/java-pom/debug-mav-cache.md` | Debugging Maven Dependency Conflicts & Version Mismatches |
| `develop/java/java-pom/dependency-issue-checklist.md` | Java 依赖问题排查清单 |
| `develop/java/java-pom/how-to-build-jar-cn.md` | 如何构建 JAR 文件 - Java 应用完整指南 |
| `develop/java/java-pom/how-to-build-jar.md` | How to Build a JAR File - A Complete Guide for Java Applications |
| `develop/java/java-pom/java-mvn-cache.md` | Maven Cache Issues in Java/Spring Boot Projects |
| `develop/java/java-pom/java-package-missing.md` | 或者 Gradle: |
| `develop/java/java-pom/java-pom-ci.md` | 使用 xmlstarlet 提取 Java 版本 |
| `develop/java/java-pom/java-pom.md` | **🧩 一、两种写法的核心区别** |
| `develop/java/java-pom/parent-child-debug.md` | Parent-Child POM 调用关系调试指南 |
| `develop/java/java-pom/parent-pom-debug-cn.md` | Parent POM 依赖版本冲突调试指南 |
| `develop/java/java-pom/parent-pom-debug-en.md` | Parent POM Dependency Version Conflict Debugging Guide |
| `develop/java/java-pom/parent-pom-debug.md` | Parent POM 依赖版本冲突调试指南 |
| `develop/java/java-pom/pom-depend-cn.md` | Maven 依赖分析与多版本冲突解决方案 |
| `develop/java/java-pom/pom-depend.md` | Maven Dependency Analysis & Multi-Version Conflict Resolution |
| `develop/java/java-pom/troubleshooting-flowchart.md` | Java Maven 依赖问题排查流程图 |
| `develop/java/java-pom/wiremock-dependency-troubleshooting.md` | WireMock 依赖缺失问题完整排查指南 |
| `develop/java/java-scan/Readme.md` | Java 应用认证扫描工具 |
| `develop/java/java-scan/auth-scanner-implementation/README.md` | Auth Scanner Implementation |
| `develop/java/java-scan/auth-scanner-implementation/deploy-process.md` | Auth Scanner Deployment & Integration Guide |
| `develop/java/java-scan/auth-scanner-implementation/design.md` | Java API 认证合规扫描器设计方案 |
| `develop/java/java-scan/deployment-guide.md` | 部署指南 |
| `develop/java/java-scan/examples/usage-examples.md` | 使用示例 |
| `develop/java/java-scan/java-code-scan.md` | 设计自动化扫描工具：确保 GKE Pod 内嵌认证逻辑 |
| `develop/java/java-scan/project-summary.md` | Java 认证扫描工具 - 项目总结 |
| `develop/java/java-scan/scanner-design.md` | Java 应用认证扫描工具设计方案 |
| `develop/java/java-spring/Java-Spring-Base.md` | 查看线程情况 |
| `develop/java/java-spring/Spring-Cloud-Run.md` | Summary |
| `develop/java/java-spring/Sprint-cloud-run-claude.md` | Spring Boot Cloud Run 代理服务深度探索指南 |
| `develop/java/java-spring/Sprint-cloud-run-gemini.md` | 深入解析 Spring Boot 代理服务的核心业务逻辑 |
| `develop/java/java-timeout/README.md` | Timeout API Application |
| `develop/java/java-timeout/java-timeout.md` | Get the timeout parameter from the query string, default to 0 |
| `develop/java/scripts/merged-scripts.md` | Shell Scripts Collection |
| `develop/java/spring/controller.md` | 理解 Spring Boot Controller：为 Kubernetes 健康检查创建 HTTP 端点 |
| `develop/java/spring/jetty-sprintboot.md` | Jetty with nginx or tomcat |
| `develop/java/spring/swagger.md` | Swagger 的主要组成部分 |

### Python Documentation

| File Path | Title |
| :--- | :--- |
| `develop/python/README.md` | Python 知识库 |
| `develop/python/docs/50.md` | 获取每周的工作日数量 |
| `develop/python/docs/bigquery-connect.md` | Define |
| `develop/python/docs/buckets-bigquery.md` | 可以在这里添加重试逻辑或发送警报 |
| `develop/python/docs/cross-pro-bigquery.md` | Claude |
| `develop/python/docs/dockerfile-source.md` | 使用 Ubuntu 20.04 作为基础镜像 |
| `develop/python/docs/gunicorn-fastapi.md` | 同步应用（Flask、Django）和异步应用（FastAPI）的区别 |
| `develop/python/docs/nba.md` | 发送HTTP请求获取页面内容 |
| `develop/python/docs/pip-install-index.md` | jump the error |
| `develop/python/docs/python-cronjob.md` | 3. 评估使用CronJob的可行性 |
| `develop/python/docs/python-start.md` | uvicorn.workers.UvicornWorker |
| `develop/python/docs/python-uvicorn.md` | summary |
| `develop/python/docs/python-violation-pytest.md` | 错误背景分析 |
| `develop/python/docs/time-sheet.md` | 计算两周循环模式 |
| `develop/python/docs/time2.md` | 获取每周的工作日数量 |
| `develop/python/docs/time3.md` | 计算每周的办公室工作天数 |
| `develop/python/docs/write-python.md` | 配置日志 |
| `develop/python/nba/README.md` | NBA 知识库 |
| `develop/python/nba/docs/python-debug.md` | ... 其他导入保持不变 ... |

### Go/Node/Web Documentation

| File Path | Title |
| :--- | :--- |
| `develop/React/README.md` | React |
| `develop/React/docs/README.md` | React Docker Application |
| `develop/React/docs/README_knowledge.md` | React 知识库 |
| `develop/React/scripts/merged-scripts.md` | Shell Scripts Collection |
| `develop/dev-tools/orca.md` | Orca — Worktree-Native IDE for Parallel AI Coding Agents |
| `develop/develop-process/ob/README.md` | OB 知识库 |
| `develop/develop-process/ob/docs/egress-summary.md` | 运行在我GKE 环境里面的用户的Runtime GKE Pod 默认是无法访问外部地址的 |
| `develop/develop-process/ob/docs/ob-public-egress-ChatGPT.md` | Q |
| `develop/develop-process/ob/docs/ob-public-egress-claude.md` | Public Egress 管理优化方案 |
| `develop/develop-process/ob/docs/ob-public-egress-gemini.md` | GCP API Platform: Public Egress Onboarding 架构演进文档 |
| `develop/develop-process/ob/docs/ob-public-egress.md` | GCP API Platform Public Egress Onboarding Enhancement |
| `develop/develop-process/ob/docs/squid-conf.md` | Complete Squid Configuration for Multi-Proxy Egress Solution |
| `develop/develop-process/ob/egress-dynamic/gke-squid-dynamic-chatgpt.md` | **GKE Squid Proxy 多上游代理按目的域名路由设计方案** |
| `develop/develop-process/ob/egress-dynamic/gke-squid-dynamic-claude.md` | GKE Squid 动态代理路由方案 |
| `develop/develop-process/ob/egress-dynamic/squid-egress-mult.md` | Dynamic Squid Egress Multi-Proxy Solution: Domain-Based Routing |
| `develop/develop-process/test/README.md` | Test 知识库 |
| `develop/develop-process/test/docs/BDD.md` | src/test/resources/features/order_processing.feature |
| `develop/develop-process/test/docs/Why.md` | 服务迁移中CNAME切换后证书报错问题分析 |
| `develop/develop-process/test/docs/api-testing-types.md` | 9 Types of API Testing |
| `develop/develop-process/test/docs/compare-stress-performance-testing.md` | 压力测试 (Stress Testing) vs 性能测试 (Performance Testing) 深度比较 |
| `develop/develop-process/test/docs/destructive-testing-infra.md` | Infrastructure Destructive Testing Guide |
| `develop/develop-process/test/docs/explorer-ai-test.md` | AI 辅助测试探索指南 |
| `develop/develop-process/test/docs/find.md` | find . -name '.![0-9]*!*' -exec ls -la {} \; |
| `develop/develop-process/test/docs/hey.md` | hey: GKE 环境下的 HTTP 负载测试工具 |
| `develop/develop-process/test/docs/improve-api-performance.md` | Top 5 Common Ways to Improve API Performance |
| `develop/develop-process/test/docs/nginx-l7-l4.md` | **7 层 (L7) vs 4 层 (L4) 的压力对比** |
| `develop/develop-process/test/docs/ple.md` | PLE (Production-Like Environment) 隔离架构深度评估 |
| `develop/develop-process/test/docs/regression.md` | **Regression Testing 相关概念和要求** |
| `develop/develop-process/test/docs/stress.md` | 获取 Service IP (推荐) |
| `develop/develop-process/test/dr-instance/README.md` | GCE Disaster Recovery Validation |
| `develop/develop-process/test/dr-instance/dr-mig-zone-test.md` | 删除 europe-west2-a 的所有实例 |
| `develop/develop-process/test/dr-instance/explorer-dr-instance.md` | Claude |
| `develop/go/README.md` | Go (Golang) 知识库 |
| `develop/go/docs/DELIVERY-CHECKLIST.md` | 交付清单 |
| `develop/go/docs/INDEX.md` | Golang 平台配置适配 - 文档索引 |
| `develop/go/docs/INTEGRATION-GUIDE.md` | Golang 应用集成平台配置 - 快速指南 |
| `develop/go/docs/JAVA-GOLANG-COMPARISON.md` | Java SpringBoot vs Golang 平台配置对比 |
| `develop/go/docs/PROJECT-STRUCTURE.md` | 项目结构说明 |
| `develop/go/docs/QUICK-START.md` | 5 分钟快速开始 |
| `develop/go/docs/SOLUTION-COMPARISON.md` | 方案对比：独立 ConfigMap vs 共享 ConfigMap |
| `develop/go/docs/SOLUTION-SUMMARY.md` | Golang 应用适配平台 ConfigMap - 解决方案总结 |
| `develop/go/docs/go-and-java-using-different-cm.md` | Java 和 Golang 使用独立 ConfigMap 方案 |
| `develop/go/docs/golang-deploy.md` | 强制统一端口 |
| `develop/go/docs/platform-configmap-adapter.md` | Golang 应用适配平台 ConfigMap 配置指南 |
| `develop/groovy/README.md` | Groovy 知识库 |
| `develop/groovy/docs/jenkins-agent.md` | Jenkins的主要功能 |
| `develop/groovy/docs/p2l.md` | 图片信息提取和流程梳理 - 以p2l为核心 |
| `develop/groovy/docs/read-each-line.md` | object or string |
| `develop/groovy/docs/simple-groovy.md` | Groovy indexOf 返回此字符串中指定字符首次出现时的索引 |
| `develop/node/README.md` | Node.js 知识库 |
| `develop/node/docs/INDEX.md` | Node.js 平台配置适配 - 文档索引 |
| `develop/node/docs/QUICK-START.md` | 5 分钟快速开始 |
| `develop/node/docs/SOLUTION-COMPARISON.md` | 方案对比：独立 ConfigMap vs 共享 ConfigMap |
| `develop/node/docs/SOLUTION-SUMMARY.md` | Node.js 应用适配平台 ConfigMap - 解决方案总结 |
| `develop/node/docs/node-https.md` | **1. 问题分析** |
| `develop/node/docs/nodejs-and-java-using-different-cm.md` | Java 和 Node.js 使用独立 ConfigMap 方案 |
| `develop/npm/README.md` | npm |
| `develop/npm/install.md` | 问题分析 |
| `develop/shell-review/README.md` | Shell Review — Knowledge Package |
| `develop/shell-review/audit-public-mtls-global-ingress-scripts.md` | Shell Script Audit — `public-mtls-global-ingress/scripts/` |
| `develop/shell-review/audit-verify-pub-priv-ip-glm-ipv6.md` | Shell Script Review — `verify-pub-priv-ip-glm-ipv6.sh` |
| `develop/shell-review/checklist.md` | Shell PR Review — One-Page Checklist |
| `develop/shell-review/methodology.md` | Shell Script Review — Methodology |
| `develop/shell-review/skill/SKILL.md` | Shell Script Review — Hermes Skill |
| `develop/shell-review/skill/references/README.md` | Shell Review — Reference Index |
| `develop/shell-review/smoke-testing.md` | Smoke Testing for Shell Scripts |
| `develop/shell-review/tool-stack.md` | Shell Review — Tool Stack & Selection Matrix |
| `develop/vscode/README.md` | VSCode 知识库 |
| `develop/vscode/plug.md` | indent-rainbow |
| `develop/vscode/strings-antigravity.md` | 分析 <host>：使用 strings 命令进行静态分析指南 |
| `develop/waza/install-plan.md` | Waza Skills — Hermes Port (Architecture Profile) |

### Nginx Documentation

| File Path | Title |
| :--- | :--- |
| `webservice/nginx/README.md` | Nginx 知识库 |
| `webservice/nginx/buffer/Proxy_set_header-Connection.md` | /etc/nginx/nginx.conf 或特定 server block |
| `webservice/nginx/buffer/client_header_buffer_size.md` | large-client-header-buffers |
| `webservice/nginx/buffer/nginx-request-buffering-claude.md` | Summary |
| `webservice/nginx/buffer/nginx-request-buffering-gemini.md` | 解决复杂代理链路中的大文件上传与 Token 超时问题 |
| `webservice/nginx/buffer/nginx-request-buffering-studio.md` | Q |
| `webservice/nginx/buffer/nginx-request-buffering.md` | Nginx `proxy_request_buffering` 详解 |
| `webservice/nginx/buffer/nginx_set_header-connection.md` | Nginx proxy_set_header Connection "" 详细分析 |
| `webservice/nginx/buffer/summary-buffer.md` | Q |
| `webservice/nginx/config/design-add-nginxconf.md` | Nginx 域名切换 Pipeline 设计 |
| `webservice/nginx/docs/Access-Control-Allow-Origin.md` | 在 http 或 server 或每个 location 块内判断 origin 来源 |
| `webservice/nginx/docs/Content-Disposition.md` | 太棒了，很高兴你的问题解决了！ 你找到的解决方案 `add header 'Access-Control-Expose-Headers' 'Content-Disposition';` 确实是解决你问题的关键，它涉及到跨域资源共享 (CORS) 的机制。 |
| `webservice/nginx/docs/GCLB-Certificate-Management.md` | GCLB 层面的证书适配 (GCLB Certificate Management) |
| `webservice/nginx/docs/How-to-simulate-operations.md` | Nginx "Too many open files" 模拟测试操作指南 |
| `webservice/nginx/docs/How-to-transmit-nginx-header.md` | > 在流量路径中，**A(7层 Nginx)** → **B(4层 Nginx Stream 模式)** → **C(GKE Gateway)**，但由于 B 是 L4 层，导致 C（GKE Gateway）只能看到 B 的 IP（如 192.168.0.35），无法获得真... |
| `webservice/nginx/docs/L7+L4.md` | 统一入口 location 分流（从原A组件迁移而来） |
| `webservice/nginx/docs/Strict-Transport-Security.md` | Strict-Transport-Security (HSTS) Best Practices |
| `webservice/nginx/docs/a-c-a-o.md` | grok |
| `webservice/nginx/docs/drainingTimeout.md` | drainingTimeout 是 Google Cloud 环境中确保 Rolling 更新平滑和无 Downtime 的关键机制之一。它主要作用于 负载均衡器的后端服务 (Backend Services)，通过连接排空（Connection Draining）来确保请... |
| `webservice/nginx/docs/endpoint-with-param.md` | 在HTTP请求中，要判断 URL 中的一部分是 endpoint 还是 参数，需要看 URL 的结构和语义。以下是对这两部分的详细解释： |
| `webservice/nginx/docs/gcp-certificate-manager-tls.md` | GCP Certificate Manager & mTLS Integration Guide |
| `webservice/nginx/docs/hsts-best-practices.md` | HSTS Best Practices for Multi-Layer Architectures |
| `webservice/nginx/docs/l4-enhance.md.md` | ISO‑8601（含时区）更通用 |
| `webservice/nginx/docs/length.md` | nginx |
| `webservice/nginx/docs/multip-in-explorer.md` | my requirement |
| `webservice/nginx/docs/nginx+cn.md` | 日志配置 |
| `webservice/nginx/docs/nginx-110.md` | Google AI Studio |
| `webservice/nginx/docs/nginx-111.md` | So, the user's question is about a problem in their GCP (Google Cloud Platform) project. They have a request flow where user requests go... |
| `webservice/nginx/docs/nginx-499-502.md` | 直接回答 |
| `webservice/nginx/docs/nginx-502.md` | 原始配置文件 |
| `webservice/nginx/docs/nginx-Reuse-confd-en.md` | Nginx Configuration Management: Unifying Multiple API Entry Points |
| `webservice/nginx/docs/nginx-Reuse-confd.md` | configuration |
| `webservice/nginx/docs/nginx-Transfer-Encoding.md` | Phenomenon |
| `webservice/nginx/docs/nginx-conf.md` | 最佳实践 |
| `webservice/nginx/docs/nginx-cpu.md` | To compare the NGINX configurations for versions 1.20.1 and 1.26.0, I’ll analyze the provided ./configure options, highlight differences,... |
| `webservice/nginx/docs/nginx-debug-log-example.md` | Nginx Debug日志配置示例 |
| `webservice/nginx/docs/nginx-enhance-chatgpt-claude.md` | chatpgtp |
| `webservice/nginx/docs/nginx-enhance.md` | TODO |
| `webservice/nginx/docs/nginx-error.md` | Q |
| `webservice/nginx/docs/nginx-feature.md` | <https://github.com/nginx/nginx-gateway-fabric> |
| `webservice/nginx/docs/nginx-formart.md` | URL进行编码处理 |
| `webservice/nginx/docs/nginx-gzip.md` | 压缩的 MIME 类型 |
| `webservice/nginx/docs/nginx-header-debug.md` | Nginx L7 / L4 / Kong 所在机器或容器内 |
| `webservice/nginx/docs/nginx-header.md` | user case |
| `webservice/nginx/docs/nginx-http2.md` | Nginx启用HTTP/2的好处与配置方法 |
| `webservice/nginx/docs/nginx-instance-enhance.md` | Summary |
| `webservice/nginx/docs/nginx-l4-proxy.md` | nginx l4 status |
| `webservice/nginx/docs/nginx-l4-stream-explorer.md` | Nginx L4 (stream 模块) 能力探索 |
| `webservice/nginx/docs/nginx-l4-user-case.md` | Nginx L4 出口代理 User Case 实施方案 |
| `webservice/nginx/docs/nginx-log.md` | Gemini |
| `webservice/nginx/docs/nginx-map-enhance.md` | 更多API映射... |
| `webservice/nginx/docs/nginx-map-host-allowlist.md` | Nginx `map $host` 入口白名单 + 反向代理(`proxy_ssl_server_name`)配置探索 — nginx-map-host-allowlist |
| `webservice/nginx/docs/nginx-map-single-config.md` | 主配置文件中已存在的映射 |
| `webservice/nginx/docs/nginx-master-worker.md` | Nginx Master-Worker 架构深度探测报告 |
| `webservice/nginx/docs/nginx-mtls.md` | 客户端证书验证配置 |
| `webservice/nginx/docs/nginx-multip-ssl-user.md` | GKE + Nginx + Kong：最小改造实现 SameSite Cookie "同站化" |
| `webservice/nginx/docs/nginx-multip-ssl.md` | increase proxy buffer size |
| `webservice/nginx/docs/nginx-plus-English.md` | F5 NGINX Plus vs. NGINX Open Source In-Depth Assessment Report: Features, Migration, and GCP Environment Optimization |
| `webservice/nginx/docs/nginx-plus.md` | F5 NGINX Plus 与 NGINX 开源版深度评估报告：功能、迁移与 GCP 环境优化 |
| `webservice/nginx/docs/nginx-proxy-buffer.md` | increase proxy buffer size |
| `webservice/nginx/docs/nginx-proxy-temp.md` | Nginx proxy_temp Permission Denied 深度分析 |
| `webservice/nginx/docs/nginx-proxy_hide_header.md` | effect |
| `webservice/nginx/docs/nginx-proxy_protocol.md` | status |
| `webservice/nginx/docs/nginx-remoteip.md` | 确认上游服务器支持 `proxy_protocol` |
| `webservice/nginx/docs/nginx-role-perspectives.md` | Nginx 的"角色"视角分析 —— 当有人把它收窄成 Network Routing + Authorization 时 |
| `webservice/nginx/docs/nginx-safe.md` | 什么是 HTTP Strict Transport Security (HSTS)？ |
| `webservice/nginx/docs/nginx-session-cache.md` | ssl_session_cache |
| `webservice/nginx/docs/nginx-size-enhance.md` | 平台上传文件大小与Payload Size限制策略 |
| `webservice/nginx/docs/nginx-size.md` | summary |
| `webservice/nginx/docs/nginx-split.md` | Nginx `split_clients` 模块详解 |
| `webservice/nginx/docs/nginx-ssl-session-timeout-and-tickets-explained.md` | Nginx TLS 会话复用参数详解 —— `ssl_session_timeout` 与 `ssl_session_tickets` |
| `webservice/nginx/docs/nginx-status.md` | summary |
| `webservice/nginx/docs/nginx-sub-model.md` | nginx `ngx_http_sub_module` 评估 |
| `webservice/nginx/docs/nginx-timeout.md` | Q |
| `webservice/nginx/docs/nginx-tls-pfs-check.md` | nginx TLS PFS(Perfect Forward Secrecy)检测与配置 |
| `webservice/nginx/docs/nginx-todo.md` | - Why we need nginx-session-cache |
| `webservice/nginx/docs/nginx-upgrade.md` | summary |
| `webservice/nginx/docs/nginx-websockets.md` | 配置 Nginx 支持 websockets |
| `webservice/nginx/docs/nginx-worker_processes.md` | 查看逻辑核心数量（有无超线程） |
| `webservice/nginx/docs/proxy-pass/explorer-default-nginx.md` | Explorer: Default Nginx Front Door to ASM Load Balancer |
| `webservice/nginx/docs/proxy-pass/nginx+istio-enhance.md` | Nginx 7层代理 + Istio 增强方案 |
| `webservice/nginx/docs/proxy-pass/nginx+istio.md` | *.<host>.aibang 默认 server 块 |
| `webservice/nginx/docs/proxy-pass/nginx+simple+chatgpt.md` | Nginx + Runtime Gateway + Pod End-to-End TLS 方案 |
| `webservice/nginx/docs/proxy-pass/nginx+simple+claude.md` | Nginx + Runtime Gateway + Pod 端到端 TLS 方案（Claude 整理版） |
| `webservice/nginx/docs/proxy-pass/nginx+simple+merge.md` | Nginx + Runtime Gateway + Pod 端到端 TLS 方案（合并定稿版） |
| `webservice/nginx/docs/proxy-pass/nginx+simple-chatgpt-eng.md` | Nginx + Runtime Gateway + Pod End-to-End TLS Architecture |
| `webservice/nginx/docs/proxy-pass/nginx-proxy-forwarded-proto.md` | Nginx `X-Forwarded-Proto` 深度探索与最佳实践 |
| `webservice/nginx/docs/proxy-pass/nginx-proxy-pass-rewrite.md` | Requirement |
| `webservice/nginx/docs/proxy-pass/nginx-proxy-pass-sni.md` | Nginx proxy_pass + SNI 注入配置逐行精读 |
| `webservice/nginx/docs/proxy-pass/nginx-proxy-pass-usersgent.md` | Nginx proxy_pass默认会重写转发请求的User-Agent头信息 |
| `webservice/nginx/docs/proxy-pass/nginx-proxy-pass.md` | 配置分析 |
| `webservice/nginx/docs/rolling-process.md` | summary |
| `webservice/nginx/docs/server_names-hash_bucket_size.md` | Understanding nginx server_names_hash_bucket_size |
| `webservice/nginx/docs/ssl_client_certificate_chain.md` | 指定一个 CA 证书链文件用于验证客户端证书 |
| `webservice/nginx/docs/tcp_nopush.md` | **问题分析** |
| `webservice/nginx/docs/upstream.md` | The phrase **"upper part of the top plate"** appears to be a mistranslation or misphrasing of **"upstream"** in the context of proxy chai... |
| `webservice/nginx/docs/verify-content-disposition.md` | 好的，你已经通过添加 `add_header 'Access-Control-Expose-Headers' 'Content-Disposition';` 解决了问题，这表示 `Content-Disposition` 头现在可以被客户端 JavaScript 代码访问（... |
| `webservice/nginx/gce-nginx-l4-enhance/debug-flow.md` | GCE Dual NIC Nginx L4 Enhanced Routing - Flow Diagrams |
| `webservice/nginx/gce-nginx-l4-enhance/debug-l4-kiro.md` | GCE Dual NIC Nginx L4 Enhanced Routing - Comprehensive Debug & Solutions |
| `webservice/nginx/gce-nginx-l4-enhance/debug-l4.md` | GCE L4 Nginx 增强型路由调试与解决方案 |
| `webservice/nginx/gce-nginx-l4-enhance/gemini-explorer.md` | 构建弹性架构：Google Cloud 双网卡 Nginx 部署深度解析 |
| `webservice/nginx/gce-nginx-l4-enhance/start-sequence.md` | FYI: Checking details |
| `webservice/nginx/gce-nginx-l4-enhance/start-service.md` | GCE Dual NIC Nginx - Systemd Service Dependency Configuration |
| `webservice/nginx/gke-egress-proxy/README.md` | GKE Nginx 出口代理（Egress Proxy）清单 |
| `webservice/nginx/icap/README.md` | ICAP (Internet Content Adaptation Protocol) |
| `webservice/nginx/icap/icap.md` | ICAP（Internet Content Adaptation Protocol）是一个轻量级的、基于 HTTP 的协议，设计用于将内容适配（content adaptation）任务从原始服务器分离出来，并交给专门的 ICAP 服务器来处理。这种设计允许你把一些耗时或需... |
| `webservice/nginx/ingress-control/ingress-control-admission.md` | NGINX Ingress Controller: Admission Webhook 深入解析 |
| `webservice/nginx/ingress-control/ingress-controller-tls.md` | **🧩 1. Verify TLS in Kubernetes** |
| `webservice/nginx/ingress-control/ingress-fundamentals.md` | Nginx Ingress Controller fundamentals: |
| `webservice/nginx/ingress-control/ingress-path-rewrite.md` | Ingress Controller 中 API 版本号重写方案 |
| `webservice/nginx/ingress-control/ingress-verify/verify-ingress-migrate.md` | TODO |
| `webservice/nginx/ingress-control/k3s-install.md` | namespace/ingress-nginx created |
| `webservice/nginx/ingress-control/merged-scripts.md` | Shell Scripts Collection |
| `webservice/nginx/ingress-control/multip-ingress-controller.md` | ChatGPT |
| `webservice/nginx/ingress-control/single-ingress-control.md` | Q |
| `webservice/nginx/ingress-control/slb.md` | Slb |
| `webservice/nginx/ingress-control/summary-tls-issue.md` | **1. Problem Analysis** |
| `webservice/nginx/ingress-control/verify-tls.md` | 查看 Secret 基本信息 |
| `webservice/nginx/nginx-cert/nginx-cert-dynamic-update.md` | Nginx 动态证书更新方案：多租户 SSL 证书热更新架构 |
| `webservice/nginx/nginx-logs/nginx-logrotate-best-practice-limited-disk.md` | 磁盘空间受限环境下的 Nginx Logrotate 最佳实践 |
| `webservice/nginx/nginx-logs/nginx-logrotate-frequent-rotation.md` | 高频轮转策略 - 平稳的磁盘空间管理 |
| `webservice/nginx/nginx-logs/nginx-reload-logrotate-debug.md` | Nginx Logrotate 配置详解与调试指南 |
| `webservice/nginx/nginx-logs/nginx-reload-logrotate.md` | `nginx -s reload` 和 `logrotate` 的关系 |

### Network/Egress/Squid Documentation

| File Path | Title |
| :--- | :--- |
| `webservice/README.md` | WebService |
| `webservice/apache/README.md` | Apache |
| `webservice/apache/docs/README.md` | Apache 知识库 |
| `webservice/apache/docs/airflow-dag.md` | 定义任务执行的函数 |
| `webservice/apache/docs/airflow.md` | Airflow 的核心功能 |
| `webservice/apache/docs/harbor-airflow.md` | 基于您的需求，Harbor + Airflow 的组合架构可以有效地实现自动化 Release 部署，支持多环境管理和版本发布。下面是一个可能的架构设计思路，以帮助您评估其可行性： |
| `webservice/apache/docs/mindmap.md` | Apache Knowledge Mind Map |
| `webservice/egress/README.md` | Egress 知识库 |
| `webservice/egress/docs/Explore-egress.md` | 我们是运行在GCP平台的一个做API的平台 |
| `webservice/egress/docs/Readme.md` | Egress 知识库 |
| `webservice/egress/docs/architecture-design.md` | GKE Egress Proxy 架构设计 |
| `webservice/egress/docs/blue-coat.md` | 非常正确 👍，Blue Coat（现为 Symantec Blue Coat，后来并入 Broadcom）确实是一个网络安全和代理访问控制产品系列，广泛用于企业上网流量管理、内容过滤、安全网关和加密流量检测等场景。以下是一个系统性的介绍。 |
| `webservice/egress/docs/explorer-egress-flow-enhance.md` | GKE Egress 代理流程图集合 (增强版) |
| `webservice/egress/docs/explorer-egress-flow.md` | GKE Egress 代理流程图集合 |
| `webservice/egress/docs/feasibility-analysis.md` | 可行性分析报告 |
| `webservice/egress/docs/implementation-guide.md` | 实施指南 |
| `webservice/egress/docs/network-flow-diagram.md` | 网络流量图和架构详解 |
| `webservice/egress/docs/quick-start.md` | 快速开始指南 |
| `webservice/egress/docs/squid-configs.md` | Squid 代理配置文件 |
| `webservice/explorer-sni.md` | Nginx、Squid 与 TLS SNI：端到端行为探索 |
| `webservice/squid/README.md` | Squid 知识库 |
| `webservice/squid/docs/Squid-client_request_buffer_max_size.md` | squid.conf 配置示例 |
| `webservice/squid/docs/codebuddy-enhance.md` | GKE API平台大文件上传与Token认证优化方案 |
| `webservice/squid/docs/gemini-enhance-squid.md` | GKE API 平台大文件上传与认证时效性优化方案 |
| `webservice/squid/docs/squid-adaptation_send_client_ip.md` | If enabled, Squid shares HTTP client IP information with adaptation |
| `webservice/squid/docs/squid-as-https-proxy.md` | Squid 代理配置分析与 HTTPS 代理方案 |
| `webservice/squid/docs/squid-conf.md` | logformat squid %ts.%03tu %6tr %>a %Ss/%03>Hs %<st %rm %ru %[un %Sh/%<a %mt |
| `webservice/squid/docs/squid-deploy-blue.md` | squid.conf (在你的镜像中或 ConfigMap 中) |
| `webservice/squid/docs/squid-deploy-claude.md` | Squid 多配置部署最佳实践 |
| `webservice/squid/docs/squid-deploy.md` | ChatGPT |
| `webservice/squid/docs/squid-docker.md` | Q |
| `webservice/squid/docs/squid-enhance.md` | My Enhance Plan |
| `webservice/squid/docs/squid-l4-explorer.md` | Squid 能否作为 L4 代理使用？深度探索 |
| `webservice/squid/docs/squid-l4-or-l7.md` | Squid 是 L4 还是 L7 代理？ |
| `webservice/squid/docs/squid-log.md` | Q |
| `webservice/squid/docs/squid-request_body_passthrough.md` | 检查Squid所有可用参数 |
| `webservice/squid/docs/squid-sni.md` | Squid SNI 提取机制:从 URL 到 TLS ClientHello |
| `webservice/squid/docs/squid-start.md` | error |
| `webservice/squid/docs/squid-upload.md` | Linux buffer |
| `webservice/squid/squid-gcs-sync-exploration.md` | Squid GCS Config Sync Automation - Architecture Discovery |

### Linux Documentation

| File Path | Title |
| :--- | :--- |
| `linux/Ghostty/README.md` | Ghostty |
| `linux/Ghostty/docs/README.md` | Ghostty 知识库 |
| `linux/Ghostty/docs/config.md` | font-family = "ZedMono NFM Extd" |
| `linux/Ghostty/docs/simple.md` | The syntax is "key = value". The whitespace around the |
| `linux/README.md` | Linux 知识库 |
| `linux/dns/README.md` | DNS |
| `linux/dns/dns-cache-ttl-with-fqdn.md` | GKE Java Pod 外部域名 DNS 解析出错 — Cache + FQDN 最佳实践 |
| `linux/dns/dns-peering/Docker-dns/README_DOCKER.md` | DNS Verification Tool - Docker Service |
| `linux/dns/dns-peering/README.md` | Verify Public/Private IP Script (`verify-pub-priv-ip.sh`) |
| `linux/dns/dns-peering/dns-query-peering.md` | script |
| `linux/dns/dns-peering/github/explorer-html.md` | 将 DNS 验证脚本转换为 GitHub Pages 静态页面的探索方案 |
| `linux/dns/dns-peering/ip-choose.md` | FQDN 出口模式选择最佳实践 (Public vs Private) |
| `linux/dns/dns-peering/merged-scripts.md` | Shell Scripts Collection |
| `linux/dns/dns-peering/verify-pub-priv-ip-glm-ipv6-fixed-summary.md` | Fix Summary — `verify-pub-priv-ip-glm-ipv6.sh` → `verify-pub-priv-ip-glm-ipv6-fixed.sh` |
| `linux/dns/docs/a-and-wirdcard.md` | 精确域名（应该返回2.2.2.2） |
| `linux/dns/docs/a.md` | private-dev-gke-cloud-uk-local |
| `linux/dns/docs/apply-cname.md` | CNAME |
| `linux/dns/docs/apply-wirdcard-cert.md` | 一、DNS 层级 vs 证书申请是否冲突 |
| `linux/dns/docs/cloud-dns.md` | 其他必要的配置... |
| `linux/dns/docs/create-private-access-usage.md` | Create Private Access Usage |
| `linux/dns/docs/cross-project-dns-demis-dns-switch.md` | Claude |
| `linux/dns/docs/dns-concept/dns-flow.md` | 图一： GKE Pod DNS 查询全路径（三种模式） |
| `linux/dns/docs/dns-length.md` | DNS域名长度规范 |
| `linux/dns/docs/dns-log.md` | update |
| `linux/dns/docs/dns-migrate.md` | GCP DNS 记录迁移脚本 |
| `linux/dns/docs/dns-peerning.md` | a |
| `linux/dns/docs/dns-svc-compare.md` | summary |
| `linux/dns/docs/dns-v2.md` | Configure a zonal GKE cluster-scoped zone |
| `linux/dns/docs/dnsrecord-add-script-usage.md` | GCP Cloud DNS 记录批量添加脚本使用说明 |
| `linux/dns/docs/dnsrecord-del-script-usage.md` | GCP Cloud DNS 记录批量删除脚本使用说明 |
| `linux/dns/docs/external-internal-dns-separation.md` | GKE DNS 架构设计指南：外部域名与内部域名分离原则 |
| `linux/dns/docs/gcp-cloud-dns-outbound-server-policy-explorer.md` | GCP Cloud DNS Outbound Server Policy Explorer — 替代 DNS、Type 1/2/3 与完整示例 |
| `linux/dns/docs/gcp-cloud-dns-response-policy-explorer.md` | GCP Cloud DNS Response Policy Explorer — Wildcard Override、Pod 出口与 API 入口分流 |
| `linux/dns/docs/gcp-dns-explorer-gpt5-5.md` | GCP DNS Explorer — GKE / Cloud DNS 路径校正版 |
| `linux/dns/docs/gcp-dns-explorer-gpt5-6.md` | GCP DNS Explorer — GKE / Cloud DNS 路径校正版 |
| `linux/dns/docs/gcp-dns-explorer.md` | Gcp Dns Explorer |
| `linux/dns/docs/gcp-dns-forwarding.md` | GCP Cloud DNS Forwarding — Deep Dive |
| `linux/dns/docs/gke-dns-resolution-flow.md` | GKE DNS Resolution Flow — Full Debug Guide |
| `linux/dns/docs/kube-dns.md` | 前提要求 |
| `linux/dns/docs/loon-dns.md` | **一、问题分析** |
| `linux/dns/docs/merged-scripts.md` | Shell Scripts Collection |
| `linux/dns/docs/migrate-dns-enhance.md` | GCP DNS 迁移脚本 - 增强版 |
| `linux/dns/docs/priority-response.md` | Q |
| `linux/dns/docs/private-access/create-claude-usage-eng.md` | create-claude.sh Usage Documentation |
| `linux/dns/docs/private-access/create-claude-usage.md` | create-claude.sh 使用文档 |
| `linux/dns/docs/private-access/create-private-access-usage.md` | create-private-access.sh 使用文档 |
| `linux/dns/docs/private-access/merged-scripts.md` | Shell Scripts Collection |
| `linux/dns/docs/s.md` | S |
| `linux/dns/docs/shared-logs.md` | anaylize |
| `linux/dns/docs/three-layer-domain-architecture.md` | GKE DNS 架构设计指南：三层域名体系 |
| `linux/dns/docs/verify-dnspeering.md` | 获取所有 DNS zone 并过滤出 peering zone |
| `linux/docs/Docker-bash.md` | **问题分析** |
| `linux/docs/Linux-control-group-v2.md` | - 使用 cgroup 冻结功能暂停和恢复 Linux 进程 |
| `linux/docs/Linux-start-services.md` | Linux 服务启动顺序与依赖管理最佳实践 |
| `linux/docs/Networkmanager.md` | GCP Instance 重启 NetworkManager 导致静态路由丢失问题分析 |
| `linux/docs/SAN.md` | Subject Alternative Name (SAN) 是X.509数字证书标准中的一个扩展字段，用于在SSL/TLS证书中提供除主题名（Common Name, CN）之外的其他标识信息。传统的SSL证书仅通过CN来识别服务器或服务的主机名，但随着网络应用的发展和多... |
| `linux/docs/Streamable.md` | **📡 What is Streamable HTTP?** |
| `linux/docs/Ubuntu-dpkg.md` | 当查询 Ubuntu 主机的内核版本、系统版本或安装包版本时，可以使用以下命令： |
| `linux/docs/anacrontab.md` | /etc/anacrontab: configuration file for anacron |
| `linux/docs/cgroup.md` | GKE Node cgroup v2 检测与 Java OOM 日志分析 |
| `linux/docs/csv-format-to-markdown.md` | Function to display script usage |
| `linux/docs/curl-and-nginx-proxy.md` | nginx proxy_pass 和curl 直接proxy 的区别是什么？ |
| `linux/docs/curl-option.md` | The curl -X option |
| `linux/docs/curl-ssl-error.md` | when I using curl command curl a url |
| `linux/docs/curl-ssl.md` | - curl request from pod |
| `linux/docs/curl-timeout.md` | 1. **连接超时 (`--connect-timeout`)** |
| `linux/docs/debug-timeout-flow.md` | 超时流程验证与调试指南 |
| `linux/docs/debug-timeout.md` | 超时问题排查 Runbook（A→B→C→D→E） |
| `linux/docs/delete.md` | find . -type f -name '.!\*!v2.png' -delete |
| `linux/docs/diff.md` | 标准化并对比（忽略键顺序和缩进差异） |
| `linux/docs/docker-ubuntu.md` | summary and backgroud |
| `linux/docs/explorer-sse-streamable.md` | Grok4 |
| `linux/docs/export-ssl.md` | 从CA bundle导出单个证书 |
| `linux/docs/flow-client-a-b-c.md` | 理解你的需求，你想了解一个包括客户端A、Nginx服务器B、Tomcat服务器C的请求流程，并关注Tomcat服务器C如何将数据返回给客户端A，以及是否与C的上网或流出模式有关。如果C有自己独立的网关，也需要考虑。 |
| `linux/docs/get.md` | 好的，接下来我为你展示一个 **GET 请求** 的完整过程，特别是在 **Kubernetes 服务升级** 和 **Pod 替换** 的高可用性场景下。 |
| `linux/docs/git.md` | 尝试获取操作系统类型 |
| `linux/docs/how-to-update-ca.md` | 1. Debian/Ubuntu |
| `linux/docs/http-Origin.md` | summary |
| `linux/docs/http-method.md` | HTTP 方法的作用 |
| `linux/docs/http-status.md` | status |
| `linux/docs/http-stream.md` | nginx stream |
| `linux/docs/ip-sort-uniq.md` | 输入示例：一组字符串形式的 IP 段 |
| `linux/docs/istio.md` | ... 其他容器配置 ... |
| `linux/docs/jq-filter.md` | step 1 提取我要的字段 |
| `linux/docs/jq.md` | what is json file |
| `linux/docs/limit.md` | 然后重启 Nginx |
| `linux/docs/linux-performance.md` | 各命令的使用说明 |
| `linux/docs/ls.md` | 用 ls 自带的 --time-style 就行（macOS 的 BSD ls 不支持这个参数，但你贴的输出看起来像 GNU ls，Linux 上可用）。 |
| `linux/docs/merged-csv.md` | 定义函数：生成c.csv文件 |
| `linux/docs/mtls.md` | - flow |
| `linux/docs/mtu.md` | 在 Linux 中更改 MTU 大小 |
| `linux/docs/nc.md` | netcat（nc）使用指南与常见示例 |
| `linux/docs/nohup.md` | 在Linux环境下，有多种方法可以让你的Shell脚本在后台运行，即使在重新连接服务器时仍然可以查看脚本的执行情况。以下是一些常用的解决方案： |
| `linux/docs/nvim-markdown.md` | reference |
| `linux/docs/nvim.md` | 1. 安装 Neovim |
| `linux/docs/pip-install.md` | cybervault-cve-report |
| `linux/docs/post-content-length.md` | 要模拟一个POST请求并增加`Content-Length`的大小，你可以使用`curl`命令。`curl`是一个非常强大的命令行工具，用于发送和接收数据，包括HTTP、HTTPS等协议。以下是一个具体的操作命令示例，假设你想发送一个POST请求到`http://examp... |
| `linux/docs/post.md` | **POST 请求的完成标准** |
| `linux/docs/purl.md` | PURL（Persistent Uniform Resource Locator，持久性统一资源定位符）是一种特殊类型的 URL，主要用于提供资源的持久访问，即使资源的实际位置发生变化。PURL 通过一个可解析的地址指向一个中间层服务器（PURL 服务器），然后该服务器会将... |
| `linux/docs/python-env-define.md` | Python Gunicorn 环境变量覆盖问题排查指南 |
| `linux/docs/quic.md` | QUIC(Quick UDP Internet Connections) 协议 |
| `linux/docs/rate-limiting.md` | How does a Rate Limiter work? |
| `linux/docs/regex.md` | summary |
| `linux/docs/replace-current.md` | Shell 脚本：批量文件内容关键字替换 |
| `linux/docs/replace.md` | the bash script |
| `linux/docs/route-claude.md` | Linux Route Commands Guide |
| `linux/docs/route.md` | Linux 路由命令详解 |
| `linux/docs/sse.md` | summary |
| `linux/docs/status-499.md` | 1. **客户端超时设置** |
| `linux/docs/tcp-large-send-offload.md` | 在 Linux 系统中，TCP Segmentation Offload (TSO) 是一种网络技术，旨在减轻 TCP 分段造成的 CPU 负载。它允许网络适配器直接将大型数据分段为最大数据分段长度，而不是由操作系统进行分段。这有助于减少 CPU 负载，提高处理性能。 |
| `linux/docs/telnet-timeout.md` | Telnet 空闲连接超时测试指南 |
| `linux/docs/telnet.md` | 如果你在使用 telnet 命令时连接到一个 IP 地址和端口，并且连接成功，但想要强制退出，可以使用以下方式： |
| `linux/docs/time.md` | Get the current time |
| `linux/docs/timeout-flow-claude.md` | A |
| `linux/docs/timeout-flow.md` | Timeout |
| `linux/docs/tls.md` | 流程解释 |
| `linux/docs/ubuntu-source-diff.md` | 官方主源 |
| `linux/docs/user-add.md` | summary |
| `linux/docs/wget.md` | 参数说明： |
| `linux/howgit/How-to-get-commitid.md` | 如何获取 Rebase 后 PR 的最新 Commit ID |
| `linux/howgit/How-to-understand-git-pull-rebase.md` | How-to understand git pull --rebase |
| `linux/howgit/How-to-understand-tree-id-and-commit-id.md` | 如何理解 Git 的 Tree ID 与 Commit ID |
| `linux/howgit/README.md` | How Git |
| `linux/howgit/codeowners-guide.md` | CODEOWNERS 完全指南：文件放哪、语法、门禁组合 |
| `linux/howgit/docs/How-to-Verify-request.md` | Q |
| `linux/howgit/docs/README.md` | Git 知识库 |
| `linux/howgit/docs/Release-git.md` | 仅克隆某个分支下的某个目录 |
| `linux/howgit/docs/Remote-cover-local.md` | 通过远程分支完全覆盖本地文件 |
| `linux/howgit/docs/bfg.md` | BFG Repo-Cleaner 详解 |
| `linux/howgit/docs/chemistry.md` | 1. **碳酸钙分解** |
| `linux/howgit/docs/delete-fork.md` | 在GitHub上删除fork的仓库非常简单，只需几步即可完成： |
| `linux/howgit/docs/fork.md` | 当您没有对原始仓库（通常是主仓库，如master）的提交权限，但想要对其进行修改，您通常会采用以下两种方式之一： |
| `linux/howgit/docs/gh.md` | GitHub CLI (`gh`) 速览 |
| `linux/howgit/docs/git-blame.md` | Git Blame 与代码格式化：保持历史清晰的工程实践 |
| `linux/howgit/docs/git-error.md` | fatal: Not possible to fast-forward, aborting. |
| `linux/howgit/docs/git-flow.md` | 当涉及到Git的工作流程时，有很多不同的工作流程模型，最常见的是Git Flow。以下是一个简单的Git Flow的Mermaid流程图示例： |
| `linux/howgit/docs/git-log.md` | 显示最近20次提交涉及的文件列表 |
| `linux/howgit/docs/git-rebase.md` | 方法一：使用 `git rebase`（保持线性历史） |
| `linux/howgit/docs/git-sheet.md` | the default when no argument is provided |
| `linux/howgit/docs/housekeep-branch.md` | 切换到主分支 |
| `linux/howgit/docs/how-git-working.md` | Certainly! I'd be happy to create a flowchart that illustrates how Git works. Git is a distributed version control system, and its workfl... |
| `linux/howgit/docs/how-to-ignore.md` | Git 忽略指南：保护敏感文件不被推送到仓库 |
| `linux/howgit/docs/ignore.md` | 在项目根目录创建或编辑 .gitignore 文件 |
| `linux/howgit/docs/list-git-repo.md` | 1. 使用 GitHub 的 Web 界面 |
| `linux/howgit/docs/master-conver-local.md` | 如何强制用Main分支覆盖本地的A分支 |
| `linux/howgit/docs/merged-to-master.md` | 处理"大改动 + main 已前进 + 有 violation"场景的实战方案 |
| `linux/howgit/docs/region-search.md` | **1. 问题的深度分析** |
| `linux/howgit/docs/rm-DS_store.md` | 搜索当前目录中所有与 .DS_Store 相关的文件 |
| `linux/howgit/docs/shell-env.md` | 提取环境变量的前两个字符 |
| `linux/howgit/docs/vim.md` | for Alpine install gvim |
| `linux/howgit/docs/vsix-down.md` | Vsix Down |
| `linux/howgit/docs/webhook.md` | 执行自动触发操作，例如运行测试 |
| `linux/howgit/gh-user-guide.md` | GitHub CLI (`gh`) 实用指南 |
| `linux/howgit/git-push-new-branch.md` | `git status` 是干什么的 |
| `linux/howgit/github-repo-role-permissions.md` | GitHub Repo Collaborator Role 5 档权限详解(Read / Triage / Write / Maintain / Admin) |
| `linux/howgit/lazygit-guide.md` | LazyGit 实战指南（macOS 终端里的 Git TUI） |
| `linux/howgit/why-to-using-githubapps.md` | 为什么用 GitHub Apps —— 跟 OAuth App / PAT / Webhook 的区别,以及它在 GitHub→GitLab 触发链路里的真实角色 |
| `linux/install-command-mkdir-chmod-atomic.md` | 一行 install,搞定 mkdir + chmod 拼接的"中间态"灾难 |
| `linux/ish/README.md` | ISH 知识库 |
| `linux/ish/docs/a-shell.md` | Using ssh-keygen -b 1024 -t rsa |
| `linux/ish/docs/update-oh-zsh.md` | 1. Manual Update |
| `linux/linux-os-optimize/linux-nginx-system-optimize-calude4-5.md` | GCP Linux 实例系统限制优化脚本 |
| `linux/linux-os-optimize/linux-system-optimize-chatgpt.md` | ========================================== |
| `linux/linux-os-optimize/merged-scripts.md` | Shell Scripts Collection |
| `linux/mail/README.md` | Mail |
| `linux/mail/smtp-ports-and-proxy.md` | 邮件协议与端口速查 |
| `linux/mail/telnet-mail.md` | 好的，我们来详细解释 `telnet ip 25` 命令以及它返回的信息，特别是关于 “Hello” 信息的部分。这个命令通常用于测试 SMTP (Simple Mail Transfer Protocol) 服务器是否正常运行，因为 SMTP 服务器监听 25 端口。 |
| `linux/nas/README.md` | NAS 知识库 |
| `linux/nas/docs/Docker-network-claude-cn.md` | QNAP NAS 上的 Docker 网络架构 - Claude 的分析 |
| `linux/nas/docs/Docker-network-claude.md` | Docker Network Architecture on QNAP NAS - Claude's Analysis |
| `linux/nas/docs/Docker-network-cn.md` | QNAP NAS 上的 Docker 进程与网络详解 |
| `linux/nas/docs/Docker-network.md` | Docker Process and Networking on QNAP NAS |
| `linux/nas/docs/How-to-flow-k3s-logs.md` | set |
| `linux/nas/docs/back-nas.md` | Docker 容器备份与迁移指南 (k3s) |
| `linux/nas/docs/docker-network-flow.md` | Docker 网络流程图集 |
| `linux/nas/docs/docker-proxy.md` | **问题分析** |
| `linux/nas/docs/local-images-error.md` | Events: |
| `linux/nas/docs/start-qnap-k3s.md` | Summary |
| `linux/nas/docs/success-summary.md` | nas enable local registry |
| `linux/neovim/Readme.md` | cat init.vim |
| `linux/neovim/bufferline.md` | for my mac |
| `linux/neovim/how-to-add-new-plug.md` | pwd |
| `linux/neovim/init-vim.md` | Using lazyvim managed my plug |
| `linux/neovim/lazyvim.md` | baking my old neovim |
| `linux/neovim/neovim-install.md` | 1. 安装 `vim-plug` |
| `linux/neovim/plug.md` | 1. 运行 `:PlugClean` |
| `linux/neovim/tree-lua.md` | return { |
| `linux/network/README.md` | Network 知识库 |
| `linux/network/docs/Electron.md` | Electron 是一个把“Chromium 浏览器内核 + Node.js 运行时”打包在一起的桌面应用框架。很多 macOS 的 App（尤其是跨平台工具）本质上就是“你的前端页面 + 后端 Node 逻辑”，由 Electron 这个运行时来启动和承载。 |
| `linux/network/docs/README-explorer-domain.md` | Domain Explorer Script |
| `linux/network/docs/README-ipv6-test.md` | IPv6 Network Test Script for macOS |
| `linux/network/docs/appproxy.md` | 我的场景描述 |
| `linux/network/docs/curl-503.md` | 你遇到的 503 Service Unavailable 是由 代理服务器（<host>:8080）返回的，而不是目标站点 <host>。这意味着连接还没有真正建立到目标 HTTPS 服务，错误已经发生在 CONNECT 隧道握手阶段。 |
| `linux/network/docs/curl-header.md` | 是的，当您使用 `curl -I https://<host>` 命令时，您得到的结果确实是 **HTTP 响应头（Response Headers）**。 |
| `linux/network/docs/curl-l.md` | 这种现象在网络和代理场景里，一般可以这样理解和表达： |
| `linux/network/docs/oauth2-authorization.md` | OAuth 2.0 Authorization Code Flow for Native Apps (RFC 8252) |
| `linux/network/docs/protocal.md` | 10 Popular Network Protocols Explained with Diagrams |
| `linux/network/docs/squid-proxy.md` | 以下是用 Mermaid 语法绘制的 Squid 代理使用 CONNECT 方法建立 HTTPS 隧道的序列图： |
| `linux/network/docs/tailscale.md` | 我会创建一个 Mermaid 流程图来展示 Tailscale 的工作原理和您描述的场景。 |
| `linux/network/docs/tcpdump.md` | Tcpdump 使用指南与实战案例 (Explorer Tcpdump) |
| `linux/network/docs/testipv6.md` | How this test works: Your browser will be instructed to reach a series of URLs. The combination of successes and failures tells a story a... |
| `linux/network/forward-reverse/compare-and-migrate-reverse-to-forward.md` | Compare and Migrate: Reverse Proxy vs. Forward Proxy |
| `linux/network/forward-reverse/curl-request-squid.md` | my request |
| `linux/network/forward-reverse/explorer-egress-flow-enhance.md` | GKE Egress 代理流程图集合 (增强版) |
| `linux/network/forward-reverse/squid-proxy-nginx.md` | Nginx与Squid代理配置分析 |
| `linux/network/nhf-egress-ip.md` | NHF 出网源 IP 定位:给 on-prem 邮件服务器授权白名单该填什么 |
| `linux/network/nhf-static-egress-ip.md` | NHF 出口 IP 固定化:预留静态 IP 并绑定到 MIG 实例 |
| `linux/network/smtp-egress-nhf-squid-analysis.md` | GKE 公网出网发邮件：NHF 三层路由与 Squid 代理可行性分析 |
| `linux/network/snat-Masquerade.md` | 在 Egress MIG 实例上 |
| `linux/network/wrk/README-load-testing.md` | Load Testing Suite |
| `linux/network/wrk/test-results/test_20250814_114748/summary.md` | Load Test Summary Report |
| `linux/network/wrk/wrk.md` | Wrk |
| `linux/scripts/curl-weather.md` | Curl Weather |
| `linux/shell-script/README.md` | Shell Script 知识库 |
| `linux/shell-script/docs/cheatsheets-bash.md` | SHORTCUTS and HISTORY |
| `linux/shell-script/docs/count-time.md` | time count |
| `linux/shell-script/docs/default-value.md` | 参数替换 - 给没有设置的变量一个默认值 |
| `linux/shell-script/docs/docker.md` | DOCKER |
| `linux/shell-script/docs/fun.md` | 函数体 |
| `linux/shell-script/docs/retry.md` | 设置最大重试次数 |
| `linux/shell-script/docs/source.md` | 设置环境变量的脚本 |
| `linux/shell-script/scripts/merged-scripts.md` | Shell Scripts Collection |
| `linux/shell-script/scripts/replace-usage.md` | 批量替换脚本使用说明 |
| `linux/terrafrom/README.md` | Terraform |
| `linux/terrafrom/docs/README.md` | Terraform 知识库 |
| `linux/terrafrom/docs/backend-servie.md` | 其他配置... |
| `linux/terrafrom/docs/person-group.md.md` | **✅ 问题总结** |
| `linux/terrafrom/docs/terrafrom-stat.md` | 先单独销毁有依赖的上层资源 |
| `linux/terrafrom/docs/tls-role.md` | Q |
| `linux/tools/export-vscode-plug.md` | 导出 VS Code / Cursor 已安装扩展列表(Export Installed VS Code Extensions) |
| `linux/version/compare-version.md` | 存储 Deployment 名称的数组 |
| `linux/version/split-housekeep-deploy.md` | script |
| `linux/version/version.md` | summary |
| `linux/version/version2.md` | summary |
| `linux/vim/README.md` | Vim |
| `linux/vim/docs/README.md` | Vim 知识库 |
| `linux/vim/docs/vim-copy.md` | 你遇到的情况是： |
| `linux/vim/docs/vim.md` | 在 Vim 中，可以通过以下方法实现将多行左移 4 个空格： |
| `linux/vpn/README.md` | VPN |
| `linux/vpn/systemproxy-with-tun.md` | 1️⃣ 问题分析 |

### Security Documentation

| File Path | Title |
| :--- | :--- |
| `safe/Control-and-Compliance/README.md` | Control and Compliance |
| `safe/Control-and-Compliance/docs/GKE-safe-en.md` | Outstanding findings summary |
| `safe/Control-and-Compliance/docs/GKE-safe.md` | **✅ 应对该问题的建议清单（适用于 GKE）** |
| `safe/Control-and-Compliance/docs/README.md` | Control and Compliance 知识库 |
| `safe/Control-and-Compliance/docs/gcp-resilience.md` | 1. 基础设施层面 |
| `safe/Control-and-Compliance/docs/risk.md` | 风险处理是组织管理中的一个重要方面，它涉及到识别、评估、监控和控制潜在的不确定性和威胁，以确保组织目标的顺利实现。风险处理的方式多种多样，以下是一些常见的风险处理策略： |
| `safe/README.md` | Safe |
| `safe/cert/DigiCert-Assessment-Guide.md` | **DigiCert EKU 影响评估指南** |
| `safe/cert/DigiCert-EKU-Migration-Plan.md` | **DigiCert Client Authentication EKU Removal - Migration Plan** |
| `safe/cert/README.md` | **DigiCert EKU 证书检查工具** |
| `safe/cert/eku.md` | summary |
| `safe/cross-site/cross-analysis.md` | Cross-Site Cookie Analysis |
| `safe/cross-site/cross-nginx-header.md` | Cross-Nginx Header Rewrite — Internal Domain Isolation |
| `safe/cross-site/cross-site-cookie-deepseek.md` | Cross-Site Cookie 深度分析 — 同一域名多路径路由方案 |
| `safe/cross-site/samesite-deep-dive.md` | SameSite Cookie 深度解析 |
| `safe/cwe/cve-2025-68973.md` | CVE-2025-68973: GPGV Security Vulnerability Fix Guide |
| `safe/cwe/cwe-16-error-page.md` | **🧩 问题场景解析** |
| `safe/cwe/cwe-16-nginx.md` | How to verify |
| `safe/cwe/cwe-16.md` | Nginx安全头在错误响应中缺失的问题分析与解决方案 |
| `safe/cwe/cwe-287.md` | Q |
| `safe/cwe/cwe-319.md` | summary |
| `safe/cwe/cwe-326.md` | CWE-326: Inadequate Encryption Strength（加密强度不足） |
| `safe/cwe/cwe-523.md` | 其他配置... |
| `safe/cwe/cwe-550.md` | **一、常见泄露点** |
| `safe/cwe/cwe-650.md` | Q |
| `safe/cwe/cwe-798.md` | CWE-798: Use of Hard-coded Credentials (使用硬编码凭证) |
| `safe/cwe/how-to-fix.md` | fix Flow |
| `safe/cwe/nginx-header-violation-cwe-16.md` | 或者其他你的配置文件路径 |
| `safe/cwe/nginx-header-x-frame-options.md` | Nginx X-Frame-Options 安全评估：全局 DENY 与 API 级 SAMEORIGIN 的权衡 |
| `safe/cwe/pro-security-status.md` | **🧩 一、使用** |
| `safe/cwe/violations-24.04-libpam.md` | 1️⃣ 更新安全源信息 |
| `safe/cyberflows/Trivy.md` | **📦 Trivy 介绍与应用场景指南** |
| `safe/cyberflows/cage-scan.md` | Cage Scan 并不是一个普遍或标准的技术术语，它可能是你们系统或项目中的一个自定义功能或工具名称。为了更好地理解这个功能，可以从以下几种可能性推测： |
| `safe/cyberflows/checkmarx.md` | Checkmarx 扫描报告在 Pipeline 中的含义 |
| `safe/cyberflows/cyberflows-flow.md` | 我会帮你创建一个详细的DAST扫描流程图,展示从配置到执行再到查看报告的完整过程。 |
| `safe/cyberflows/dast.md` | 将动态应用安全测试（DAST）集成到CI/CD流程的综合指南 |
| `safe/cyberflows/foss-explorer.md` | Q |
| `safe/cyberflows/foss.md` | Summary |
| `safe/cyberflows/penetration-test.md` | 渗透测试（Penetration Test）全面解析：定义、合规、流程与企业落地 |
| `safe/cyberflows/sbom.md` | **✅ 使用前提** |
| `safe/cyberflows/sonar.md` | SonarQube是一个代码质量和安全分析工具。它可以帮助开发人员编写清洁的代码并修复现有代码问题。 |
| `safe/docs/Encrypted.md` | 非常好的问题 👍。你理解得对 —— 对方是希望你提供 在GCP平台上关于数据加密（Encryption）和安全机制（Security） 的实现说明，以便和他们的 Power Platform 的安全实践（如 CMK、FIPS、TLS、加密算法等）进行对比。 |
| `safe/docs/GKE-26.md` | **✅ GKE 审计日志包括哪些内容？** |
| `safe/docs/Periodic-container-scanning.md` | 🛡️ GCP GKE 运行时容器镜像定期扫描方案 |
| `safe/docs/analyze-showcerts.md` | q |
| `safe/docs/api_security_tips.md` | 12 Tips for API Security |
| `safe/docs/appd-violation.md` | Q |
| `safe/docs/auth.md` | AuthN (身份验证) 详细流程 |
| `safe/docs/auths-method.md` | GCP 平台应用认证授权方法详解 (auths-method) |
| `safe/docs/compare-sls-local-and-user.md` | 函数: 提取证书信息 |
| `safe/docs/crl2pkcs7.md` | 1. `-certfile` |
| `safe/docs/curl-pem-request.md` | 获取服务器证书链并保存到文件 |
| `safe/docs/cve.md` | 修复系统漏洞是一个非常重要的安全工作,需要采取全面的措施。我总结了一些常用的修复办法供您参考: |
| `safe/docs/cyber-with-cloud-armor.md` | AI Studio |
| `safe/docs/cyberflows.md` | **背景信息** |
| `safe/docs/dbp.md` | about nginx.conf |
| `safe/docs/egress-sftp-saasp.md` | Egress SFTP 走 SAASP Proxy 可行性分析 |
| `safe/docs/encypy-asymmetric.md` | **1. 对称密钥 (Symmetric Key)** |
| `safe/docs/fix-nginx-ngx_http_rewrite_module.md` | NGINX ngx_http_rewrite_module Heap Buffer Overflow — Fix Guide |
| `safe/docs/flow-ssl.md` | calude |
| `safe/docs/gcp-safe-api-enhance.md` | 只允许访问特定 bucket |
| `safe/docs/gke-policy-control.md` | 启用 Anthos Config Management（包含 Policy Controller） |
| `safe/docs/gke-psa.md` | **✅ 怎么表述这类情况（可用于文档或审计回复）** |
| `safe/docs/glb-open-80-ports.md` | **🌐 1.** |
| `safe/docs/ib2b-eb2b.md` | **🔐 iB2B vs eB2B 说明** |
| `safe/docs/iq-scan.md` | “nexus - iq - cli”可能是与Nexus IQ相关的命令行界面（CLI）工具。 |
| `safe/docs/jwt.md` | Understanding JSON Web Tokens (JWT) |
| `safe/docs/kali.md` | Kali Linux 常用渗透测试工具指南 |
| `safe/docs/periodic-container-scanning-claude.md` | Periodic Container Scanning Solution - Claude's Design |
| `safe/docs/pipeline-script.md` | Q |
| `safe/docs/psa.md` | GKE Pod Security Admission (PSA) 详解 |
| `safe/docs/saasp-pod-nginx-squid.md` | 网络拓扑是： |
| `safe/docs/safe-reference.md` | 1. Clone the repository |
| `safe/docs/scan.md` | Apple Container + Kali Linux 安全扫描环境搭建指南 |
| `safe/docs/singnat.md` | calude |
| `safe/docs/ssl-policy-gemini.md` | 指南：为 GKE Gateway 配置自定义 SSL Policy 以强制使用 TLS 1.2 |
| `safe/docs/strings.md` | 一、`strings` 命令的核心原理 |
| `safe/docs/tls-handshake-ascii-flow.md` | tls-handshake-ascii-flow |
| `safe/docs/ubuntu.md` | 其他你原本Dockerfile中的指令 |
| `safe/docs/url-block.md` | 好的，你遇到的问题是 Kong DP (Data Plane) 在处理包含 `!%` 特殊字符的 URL 时返回 403 错误。这通常是由于以下原因造成的： |
| `safe/docs/verify-ssl.md` | 这个问题涉及到了网络安全的一些细微之处。让我们仔细分析一下： |
| `safe/docs/waf-rule-troubleshooting.md` | ChatGPT |
| `safe/docs/waf-rule.md` | 规则详细信息 |
| `safe/docs/waf-troubleshooting.md` | ChatGPT |
| `safe/docs/waf.md` | WAF(Web 应用程序防火墙)是一种专门用于保护 Web 应用程序安全的防火墙。它的主要功能包括: |
| `safe/docs/wget-ssl.md` | 要获取一个HTTPS网站的证书链，你可以使用以下几种方法： |
| `safe/fix-cve/cve-cwe.md` | 简答：**"修复漏洞"这个动作最终落在 CWE 上，而"闭环/验收"落在 CVE 上。** |
| `safe/fix-cve/how-to-autofix-cve.md` | GCP 上自动修复 CVE / Violation —— 可行性探索与方案设计 |
| `safe/fix-cve/how-to-fix-cve-with-base-image-constraints.md` | Base Image 受限时如何修 CVE —— 「准入引进」路径 与 「Dockerfile 精简」路径 |
| `safe/fix-cve/how-to-fix-dex-base-image.md` | dex Base Image 修复 Runbook —— alpine 3.21 EOL |
| `safe/fix-cve/how-to-maintain-upstream-images-bak.md` | 上游镜像持续维护方案 —— 从 Git 分支控制面到 GAR 制品面的闭环 |
| `safe/fix-cve/how-to-maintain-upstream-images-pi.md` | 上游镜像持续维护方案 —— 从 Git 分支控制面到 GAR 制品面的闭环 |
| `safe/fix-cve/how-to-maintain-upstream-images.md` | 上游镜像持续维护方案 —— 从 Git 分支控制面到 GAR 制品面的闭环 |
| `safe/fix-cve/how-to-rebuild-argocd-images.md` | Argo CD 镜像重建与 CVE 修复 —— 「Buildpack 式」路线的可行性与落地设计 |
| `safe/fix-cve/how-to-use-dependabot.md` | Dependabot 使用手册 —— 从安装配置到接入 GCP/GAR 闭环 |
| `safe/gcp-safe/BUG-FIX-EXPLANATION.md` | Bug 修复说明：`((COUNTER++))` 在 `set -e` 模式下的问题 |
| `safe/gcp-safe/CHANGELOG.md` | 更新日志 |
| `safe/gcp-safe/DEPLOY.md` | 部署指南 |
| `safe/gcp-safe/IMPROVEMENTS.md` | KMS 验证脚本改进说明 |
| `safe/gcp-safe/INDEX.md` | GCP KMS 验证工具 - 文件索引 |
| `safe/gcp-safe/Key-Management-Service.md` | **问题分析** |
| `safe/gcp-safe/PERMISSIONS-GUIDE.md` | KMS 验证脚本权限指南 |
| `safe/gcp-safe/README.md` | GCP KMS 跨项目权限校验工具 |
| `safe/gcp-safe/SUMMARY.md` | 问题解决总结 |
| `safe/gcp-safe/TROUBLESHOOTING.md` | KMS 验证脚本故障排查指南 |
| `safe/gcp-safe/VERIFICATION-CHECKLIST.md` | 验证清单 |
| `safe/gcp-safe/a.md` | decrypt certificate and key files |
| `safe/gcp-safe/data-classification-type.md` | 问题分析 |
| `safe/gcp-safe/example-usage.md` | GCP KMS 验证脚本使用示例 |
| `safe/gcp-safe/gcp-lb-cipher.md` | 在GCP中验证负载均衡器Cipher Suite的方法 |
| `safe/gcp-safe/gcp-role.md` | 步骤1：创建自定义角色 |
| `safe/gcp-safe/key-keyring.md` | **问题分析** |
| `safe/gcp-safe/kms-en-and-de.md` | 架构实践：GCP 中使用独立 KMS 项目进行跨项目加解密 |
| `safe/gcp-safe/kms-en-de.md` | 创建一个对称密钥 |
| `safe/gcp-safe/kms.md` | 1. 通过 Google Cloud Console 检查项目级别的默认密钥 |
| `safe/gcp-safe/lex.md` | Lex |
| `safe/gcp-safe/merged-scripts.md` | Shell Scripts Collection |
| `safe/gcp-safe/pas.md` | **✅ 你的命令属于** |
| `safe/gcp-safe/psa.md` | GKE Pod Security Admission (PSA) 详解 |
| `safe/gcp-safe/security-policy-overview.md` | reference |
| `safe/gcp-safe/ssl-policy.md` | GKE Gateway SSL Policy 配置指南 |
| `safe/gcp-safe/verify-kms.md` | GCP KMS 跨项目权限校验脚本 - 设计方案 |
| `safe/gcp-safe/workload-identify.md` | Workload Identity概述 |
| `safe/get-token/OPTIMIZATION.md` | 脚本优化总结 |
| `safe/get-token/README.md` | Token 获取脚本使用说明 |
| `safe/how-to-fix-violation/README.md` | Readme |
| `safe/how-to-fix-violation/automation-scripts.md` | Automation Scripts for Container Security |
| `safe/how-to-fix-violation/ci-cd-integration.md` | CI/CD Security Integration Guide |
| `safe/how-to-fix-violation/detection-tools.md` | Container Security Detection Tools |
| `safe/how-to-fix-violation/foss.md` | FOSS 是什么？——自由与开源软件完全指南 |
| `safe/how-to-fix-violation/quick-reference.md` | Container Security Quick Reference |
| `safe/how-to-fix-violation/remediation-strategies.md` | Container Security Remediation Strategies |
| `safe/responsibilities/package-depend.md` | Sonar scan cover |
| `safe/responsibilities/snoar-code-coverage.md` | 关于代码覆盖率的这一部分，在我的实际工作经验中，是用户提供自己的 Dockerfile 之后，我们有一个 base image。 |
| `safe/ssl/OpenSSL-curl.md` | OpenSSL as Telnet & Curl Replacement in Kubernetes Pods |
| `safe/ssl/README.md` | SSL / TLS |
| `safe/ssl/certificate-truststore.md` | Certificate Truststore Issue 总结 |
| `safe/ssl/compare-san-sni.md` | SAN vs SNI：区别、使用场景与验证方法 |
| `safe/ssl/cross-project-fqdn-best-practices.md` | Cross-Project FQDN Best Practices |
| `safe/ssl/current-fqdn-status.md` | Current FQDN Status |
| `safe/ssl/debug-ssl-chatgpt.md` | SSL Debug 理解与脚本说明 |
| `safe/ssl/debug-ssl.md` | 问题分析与用户沟通指南 |
| `safe/ssl/docs/Sans.md` | **问题分析** |
| `safe/ssl/docs/chatgpt/ssl-terminal-1-1.md` | 单一 GKE Gateway + Nginx 前置 TLS 终止实施方案（ssl-terminal-1-1） |
| `safe/ssl/docs/chatgpt/ssl-terminal-1.md` | 单一 GKE Gateway 方案评估（基于 ssl-terminal.md 的“想要的配置”） |
| `safe/ssl/docs/cipher-suites-explained.md` | Cipher Suites 详解 (TLS 1.2 / 1.3, K8s / GKE 实战视角) |
| `safe/ssl/docs/claude/glb-termina-https-3.md` | PoC 操作手册：GLB URL Map 映射 + Nginx 透明代理 + GKE Gateway 路由 |
| `safe/ssl/docs/claude/glb-terminal-2.md` | TLS 终止前移至 GLB 层面的完整探索 |
| `safe/ssl/docs/claude/glb-terminal-https-2.md` | GLB 原生处理映射关系：真正将逻辑从 Nginx 移走 |
| `safe/ssl/docs/claude/glb-terminal-https.md` | GLB 终止客户端 TLS + 后端保持 HTTPS 的合规架构 |
| `safe/ssl/docs/claude/map/glb-url-map-implementation.md` | GLB URL Map 实施方案：长域名跳转 + 短域名透传 + Nginx 零改动 |
| `safe/ssl/docs/claude/map/glb-urlmap-rewrite.md` | 现状：URL Map 的能力边界 |
| `safe/ssl/docs/claude/map/poc-urlmap.md` | No 301 |
| `safe/ssl/docs/claude/map/url-map-merge.md` | GLB URL Map 合并实施方案：长域名重定向到短域名，Nginx 短域名配置保持不变 |
| `safe/ssl/docs/claude/pod-cert-replacement-evaluation.md` | Pod 间 Local 证书替代方案评估报告 |
| `safe/ssl/docs/claude/routeaction/explorer-routeaction.md` | GLB 透明代理生产实施手册：长短域名并存，地址栏不变，Nginx 零改动 |
| `safe/ssl/docs/claude/routeaction/flow-url-map.md` | GLB URL Map 长域名透明代理流量编排与逻辑流图 |
| `safe/ssl/docs/claude/routeaction/maps-format-and-verify/merged-scripts.md` | Shell Scripts Collection |
| `safe/ssl/docs/claude/routeaction/maps-format-and-verify/success/8.md` | 8.json 设计说明 |
| `safe/ssl/docs/claude/routeaction/maps-format-and-verify/success/v6.md` | - request |
| `safe/ssl/docs/claude/routeaction/maps-format-and-verify/success/v7.md` | v7 URL Map 说明 |
| `safe/ssl/docs/claude/routeaction/maps-format-and-verify/url-map-update.md` | URL Map JSON 更新与校验说明 |
| `safe/ssl/docs/claude/routeaction/maps-format-and-verify/url-succ-json.md` | GLB URL Map 透明代理配置解析 (url-succ.json) |
| `safe/ssl/docs/claude/routeaction/maps-format-and-verify/urlmap-quota.md` | GLB URL Map 大规模 API 配置评估方案 (1000+ API 场景) |
| `safe/ssl/docs/claude/routeaction/maps-format-and-verify/urlmaprouteaction.md` | GLB URL Map RouteAction 配置解析 (urlmaprouteaction.json) |
| `safe/ssl/docs/claude/routeaction/maps-format-and-verify/urlmp.md` | GLB URL Map 配置解析 (urlmap.json) |
| `safe/ssl/docs/claude/routeaction/ssl-terminal-2.md` | SSL 终止前移与单一 GKE Gateway 架构分析 |
| `safe/ssl/docs/claude/routeaction/ssl-terminal-effect.md` | 可能继续的探索 |
| `safe/ssl/docs/claude/routeaction/ssl-terminal.md` | 这个服务块只匹配这个域名的请求 |
| `safe/ssl/docs/claude/routeaction/url-map-quota.md` | GCP GLB URL Map 核心限制与配额 (Quotas & Limits) 深度指南 |
| `safe/ssl/docs/claude/routeaction/url-map-routeaction.md` | GLB URL Map RouteAction 实施方案：长域名透明代理，地址栏不变，后端复用短域名 Path 逻辑 |
| `safe/ssl/docs/pem-get-ssl.md` | 设置颜色输出 |
| `safe/ssl/docs/read-cert.md` | 提取第一个证书到文件 |
| `safe/ssl/docs/root.md` | 企业证书和公共证书的一些辨别 |
| `safe/ssl/docs/ssl-type.md` | 示例证书内容 |
| `safe/ssl/docs/tls-handshake-ascii-flow.md` | TLS Handshake — 完整流程图(含每个阶段可能发生的报错) |
| `safe/ssl/docs/tls-handshake-explained.md` | TLS Handshake — Explained |
| `safe/ssl/docs/what-ssl.md` | A case thinking |
| `safe/ssl/gcp-glb-ssl-certificate-update.md` | GCP GLB SSL 证书管理方案 |
| `safe/ssl/gskit.md` | 深度探索：GSKit 与 Error 6000 |
| `safe/ssl/ingress-ssl/Readme.md` | 快速生成自签名证书 |
| `safe/ssl/ingress-ssl/merged-scripts.md` | Shell Scripts Collection |
| `safe/ssl/merged-scripts.md` | Shell Scripts Collection |
| `safe/ssl/openssl.md` | 你可以使用 openssl s_client 命令来测试一个 HTTPS 站点是否可以正常访问，并检查 SSL/TLS 的握手过程。以下是具体的步骤和命令： |
| `safe/ssl/request-flow.md` | HTTPS 完整请求流程 — 从 URL 到像素(OSI 7 层视角) |
| `safe/ssl/sni.md` | /etc/nginx/nginx.conf(最小 demo,仅用于 §5.2 展示可行性) |
| `safe/ssl/verify-baidu.md` | ./verify-domain-ssl-enhance.sh <host> |
| `safe/ssl/why-san.md` | Why SAN |
| `safe/wiz/Summary-TODO.md` | summary |
| `safe/wiz/gemini-wiz.md` | Wiz 在 GCP 与 GKE 环境中的全面应用指南 |
| `safe/wiz/wiz-base-information.md` | **Wiz 在 GCP / GKE 中的工作原理概览** |
| `safe/wiz/wiz-grok.md` | 基本的知识 |

### SRE/Monitoring Documentation

| File Path | Title |
| :--- | :--- |
| `sre/README.md` | SRE |
| `sre/docs/How-to-reply.md` | ⸻ |
| `sre/docs/cr-release-integration.md` | Change Request × Release 集成工具调研 |
| `sre/docs/debug-header.md` | 深度排查：`X-AIBANG-client-secret` Header 丢失问题 |
| `sre/docs/flow-debug-gemini.md` | gemini |
| `sre/docs/flow-debug.md` | Claude |
| `sre/docs/how-to-debug-flow.md` | GCP云服务API 502错误全链路调试指南 |
| `sre/docs/how-to-debug.md` | 云服务API 502错误调试思路与方法论 |
| `sre/docs/llm-knowledge-workspace-for-sre.md` | LLM Knowledge Workspace 方案 |
| `sre/docs/reply-template.md` | 这个问题你问得非常到位，而且也非常“平台方视角”。 |
| `sre/header-tracing/README.md` | 多层代理链路 Header 追踪与覆盖排查方法论 |
| `sre/header-tracing/references/example-case-study.md` | 案例复盘：`x-example-src-useragent` 被 `user-agent` 覆盖 |
| `sre/header-tracing/references/kong-layer.md` | Kong DP 层 Header 语义详解 |
| `sre/header-tracing/references/nginx-layer.md` | nginx 层 Header 语义详解 |
| `sre/header-tracing/references/runtime-layer.md` | Runtime 层 Header 接收与验证 |
| `sre/header-tracing/webservice/nginx/docs/nginx-header-debug.md` | nginx-header-debug |
| `sre/monitor/README.md` | Monitor 知识库 |
| `sre/monitor/docs/Capacity-Forecasting.md` | GKE 容量预测与主动监控 (Capacity Forecasting & Proactive Monitoring) |
| `sre/monitor/docs/FailedScheduling.md` | **🧩 一、问题分析** |
| `sre/monitor/docs/How-to-manage-monitor-policy.md` | - [ ] gcloud alpha monitoring policies |
| `sre/monitor/docs/Mimir.md` | 一、Mimir 的背景和目标 |
| `sre/monitor/docs/gce-mig-status.md` | summary |
| `sre/monitor/docs/monitor-base-ai.md` | Understanding Delta in Monitoring Systems |
| `sre/monitor/docs/monitor-egress-proxy.md` | GKE 正向代理（Squid）多跳访问场景的标准化监控设计 |
| `sre/monitor/docs/monitor-memory.md` | GKE Pod 内存监控指南 |
| `sre/monitor/docs/monitor-proxy.md` | **🧩 一、整体流程监控设计（路径监控）** |
| `sre/monitor/docs/monitory-base.md` | 在监控中，“Delta” 通常指的是变化量或差值。它表示当前状态与某个参照点（通常是之前的某个时间点）之间的差异。理解 Delta 的关键在于明确以下几点： |
| `sre/monitor/docs/pipeline-status.md` | 定义要检查的URL列表 |
| `sre/monitor/docs/pod-memory.md` | GKE Pod 内存监控指标详解（以 Java Application 为核心视角） |
| `sre/monitor/gce-disk/GCE-instance-disk.md` | ChatGPT |
| `sre/monitor/gce-disk/README.md` | GCE Squid 代理磁盘监控工具集 |
| `sre/monitor/gce-disk/gce-disk-analyze.md` | GCE Squid 代理磁盘监控实施方案 |
| `sre/monitor/gce-disk/merged-scripts.md` | Shell Scripts Collection |
| `sre/monitor/gce-disk/proxy-monitor.md` | Proxy Monitor |
| `sre/monitor/opentelemetry/OpenTelemetry.md` | summary |
| `sre/monitor/opentelemetry/opentelemetry-k8s-special.md` | Opentelemetry K8S Special |
| `sre/monitor/opentelemetry/opentelemetry-operator.md` | 当 Operator 检测到 annotation=true 时自动注入以下 sidecar |
| `sre/shell-lib-testing-best-practices.md` | Shell Lib 复用与 Shell 测试最佳实践 — 研究笔记 |
| `sre/sre-todo.md` | outbound HTTP 调用 metric(成功率 / 错误码分布 |

### macOS/iOS Documentation

| File Path | Title |
| :--- | :--- |
| `macos/README.md` | macOS |
| `macos/apple/README.md` | 🍎 Apple Notes CLI 工具 |
| `macos/caffeinate.md` | caffeinate |
| `macos/capture/smartshot.md` | 推荐实现方式 |
| `macos/docs/app-network-observer.md` | macOS APP 网络域名观察脚本 |
| `macos/docs/apple-container-101.md` | macOS Apple `container` CLI 入门 |
| `macos/docs/btop.md` | 将默认排序设为CPU |
| `macos/docs/dns.md` | 你遇到的情况和 CACHE_TTL = 180 秒的设置关系不大。问题根源在于 系统级的 DNS 缓存。 |
| `macos/docs/explorer-source-command.md` | ============================================================================ |
| `macos/docs/install-fonts.md` | 一、先给结论（最推荐的写法） |
| `macos/docs/launchd-101.md` | macOS launchd 入门 |
| `macos/docs/macOS-monitor-connect.md` | summary |
| `macos/docs/macos-container.md` | 创建配置目录 |
| `macos/docs/my-macos-power-requirement.md` | Mac mini 电源管理方案 |
| `macos/docs/open-file.md` | BundleID Extension Role |
| `macos/docs/powermetrics.md` | 从 `sudo powermetrics -h` 的帮助信息来看，有几个选项和 sampler 可以帮助你获取系统的功耗信息： |
| `macos/docs/rg.md` | **ripgrep（rg）使用手册（macOS）** |
| `macos/docs/socat.md` | **✅ 方案 1：使用** |
| `macos/docs/swith-bash.md` | 输出应为 /opt/homebrew/bin/bash |
| `macos/explorer-macos-power.md` | Mac mini 后台任务电源管理方案 |
| `macos/game/README.md` | Game |
| `macos/iPad/README.md` | iPad |
| `macos/iPad/docs/playgrouds.md` | claude |
| `macos/ios/README.md` | iOS 知识库 |
| `macos/ios/ocr/Reade.md` | Xcode 里 Product → Run 可以直接跑 |
| `macos/ios/ocr/nas-ocr.md` | nas 部署 paddleocr-vl-pipeline |
| `macos/ios/speak-screen.md` | ✅ **开启 Speak Screen（英文系统）的方法** |
| `macos/native-tools/README.md` | native-tools |
| `macos/native-tools/macos-tools.md` | Personal portable CLI tools |
| `macos/terminal/Rex/How-to-view-markdown.md` | How to view Markdown（在终端里直接 Review Markdown） |
| `macos/terminal/Rex/README.md` | Rex |
| `macos/terminal/Rex/Rex-Kitty-Graphics.md` | Rex × Kitty 图形协议：在窗格里画图 |
| `macos/terminal/Rex/Rex-Markdown-for-pi.md` | Rex Markdown for Pi |
| `macos/terminal/Rex/mdview-setup-and-dependencies.md` | mdview 依赖清单与跨机安装指南 |
| `macos/terminal/Rex/mdview.md` | mdview 是什么（技术说明） |
| `macos/trans/README.md` | Translation App |
| `macos/zhifubao/README.md` | 支付宝 |

### Database/Redis Documentation

| File Path | Title |
| :--- | :--- |
| `database/README.md` | Database |
| `database/redis/README.md` | Redis 知识库 |
| `database/redis/docs/In-transit-encryption.md` | **✅** |
| `database/redis/docs/gcp-redis.md` | Q |
| `database/redis/docs/get-gcp-redis.md` | GCP Redis 信息获取脚本 |
| `database/redis/docs/redis-con.md` | Q |
| `database/redis/docs/redis-connect-chatgpt.md` | 下面以标准 Markdown 源码格式 为你完整说明 GKE（Project A）访问跨 Project B 的 Redis（不管是 GCE Redis、Redis Enterprise、或自建 Redis） 的可行方案，包含 网络连通方式、鉴权机制、能否通过 IAM 实现... |
| `database/redis/docs/redis-connect-claude.md` | GKE 跨工程访问 Redis 的实现方案 |
| `database/redis/docs/redis-connect-gemini.md` | How to Connect to Redis Across GCP Projects from GKE |
| `database/redis/docs/redis.md` | Redis (Memorystore) 的 Resilience 配置 (详细展开) |

### Concept/API Service Documentation

| File Path | Title |
| :--- | :--- |
| `concept/README.md` | Concept |
| `concept/api-service/README.md` | API Service 知识库 |
| `concept/api-service/docs/Architecture-Stream-API.md` | Summary |
| `concept/api-service/docs/EAPI-PAPI-SAPI.md` | **常见 API 分类** |
| `concept/api-service/docs/Requirement.md` | - [ ] 我想用Python写一个API服务,部署在K8S上,比如服务 名称叫collection-api, |
| `concept/api-service/docs/SSE.md` | 🌐 **SSE = Server-Sent Events** |
| `concept/api-service/docs/Stream-Events-apis.md` | Stream Events API 学习与实践文档 |
| `concept/api-service/docs/api-ChatGPT.md` | **问题分析** |
| `concept/api-service/docs/api-kiro.md` | API 平台架构深度解析与演进策略 |
| `concept/api-service/docs/api.md` | API 平台演进：从标准 API 到多模式服务支持 |
| `concept/api-service/python-api-demo/explore-deployment-env.md` | 深入探索 Kubernetes Deployment 中的环境变量 |
| `concept/api-service/python-api-demo/python-health-demo/README.md` | Python Health Check & Env Var Demo |
| `concept/docs/README.md` | Concept 知识库 |
| `concept/docs/model-driven-thinking.md` | 从命令驱动到模型驱动 |
| `concept/docs/rfc.md` | Request for Comments (RFC) |

### AI Documentation

| File Path | Title |
| :--- | :--- |
| `ai-newsletter/2026-07-01-ai-trending.md` | 🤖 AI 早报 · 2026-07-01 |
| `ai/README.md` | AI |
| `ai/concept/INSTALL.md` | 安装指南 |
| `ai/concept/PROJECT_SUMMARY.md` | 本地知识库智能检索系统 - 项目总结 |
| `ai/concept/QUICKSTART.md` | 快速开始指南 |
| `ai/concept/README.md` | 本地知识库智能检索系统 |
| `ai/concept/USAGE.md` | 知识库检索工具使用指南 |
| `ai/docs/Python-ocr.md` | - /Users/lex/git/knowledge/ai/ocr-ollama-3.py 目前这个最稳定 |
| `ai/docs/README.md` | AI (Artificial Intelligence) 知识库 |
| `ai/docs/agent-tree.md` | This guy literally created an agent to replace all his employees |
| `ai/docs/ai-agent.md` | AI Agent的基本原理 |
| `ai/docs/chunk_size_overlap_batch_size_explorer.md` | Chunk / Batch / Context-Window 关系探索 — embeddinggemma 2K 视角 |
| `ai/docs/debug-ollama.md` | 一键全查 |
| `ai/docs/embedder-batch-size-tuning.md` | Embedder `batch_size` Tuning — Ollama `/v1/embeddings` 长 Batch 压力探索 |
| `ai/docs/llam-server.md` | how to upgrade it |
| `ai/docs/ollama-warmup-pattern.md` | Ollama `/v1/embeddings` Hang Bug — Warmup Pattern (macOS 实战视角) |
| `ai/docs/ollama.md` | ollama list |
| `ai/docs/prompt.md` | Linux & Cloud Infrastructure Expert Prompt |
| `ai/prompt/English-prompt.md` | Claude |
| `ai/prompt/README.md` | Prompt 知识库 |
| `ai/prompt/architectrue-cn.md` | GKE & GCP 架构技术合作伙伴提示 |
| `ai/prompt/architectrue.md` | GKE & GCP Architecture Technical Partner Prompt |
| `ai/prompt/enhance-prompt.md` | 目标： |
| `ai/prompt/jira-pm.md` | You are a project team member familiar with software development workflows and cloud platforms (GCP, GKE, K8S, Kong, etc.). |
| `ai/prompt/sre-prompt.md` | You are a Platform SRE responsible for responding to user-reported issues on an API platform. |

### OPA Gatekeeper Documentation

| File Path | Title |
| :--- | :--- |
| `OPA-Gatekeeper/README.md` | OPA-Gatekeeper |
| `OPA-Gatekeeper/Rego/README.md` | Rego |
| `OPA-Gatekeeper/Rego/docs/Join-Fleet.md` | 加入 Fleet - GKE Policy Controller 启用前提 |
| `OPA-Gatekeeper/Rego/docs/create.md` | 1. Architecture Logic Design |
| `OPA-Gatekeeper/Rego/docs/gke-policy-controller-with-gatekeeper.md` | GKE Policy Controller vs Standalone Gatekeeper 选型指南 |
| `OPA-Gatekeeper/Rego/docs/gke-setup-policy-controller.md` | GKE Policy Controller 完整安装与配置指南 |
| `OPA-Gatekeeper/Rego/docs/rego-concept.md` | 2. 在 GKE 中的核心场景：Gatekeeper |
| `OPA-Gatekeeper/constraint-explorers/README.md` | Gatekeeper Constraint 探索索引 |
| `OPA-Gatekeeper/constraint-explorers/allowed-repos.md` | K8sAllowedRepos 限制容器镜像仓库 |
| `OPA-Gatekeeper/constraint-explorers/block-loadbalancer-services.md` | K8sBlockLoadBalancer 禁止 LoadBalancer Service |
| `OPA-Gatekeeper/constraint-explorers/block-nodeport-services.md` | K8sBlockNodePort 禁止 NodePort Service |
| `OPA-Gatekeeper/constraint-explorers/containerlimits.md` | K8sContainerLimits 容器资源限制详解 |
| `OPA-Gatekeeper/constraint-explorers/disallowed-repos.md` | K8sDisallowedRepos 禁止特定镜像仓库 |
| `OPA-Gatekeeper/constraint-explorers/externalip.md` | K8sExternalIPs 限制 Service 外部 IP |
| `OPA-Gatekeeper/constraint-explorers/https-only.md` | K8sHttpsOnly 强制 Ingress 仅允许 HTTPS |
| `OPA-Gatekeeper/constraint-explorers/immutable-fields.md` | K8sImmutableFields 禁止修改特定字段（自定义模板） |
| `OPA-Gatekeeper/constraint-explorers/k8srequiredlabels.md` | K8sRequiredLabels 完整指南 |
| `OPA-Gatekeeper/constraint-explorers/psp-pod-security.md` | PSP Pod Security Policies — Gatekeeper 版安全策略集 |
| `OPA-Gatekeeper/constraint-explorers/replica-limits.md` | K8sReplicaLimits 限制 Deployment/ReplicaSet 副本数 |
| `OPA-Gatekeeper/constraint-explorers/required-probes.md` | K8sRequiredProbes 强制健康检查探针 |
| `OPA-Gatekeeper/constraint-explorers/storageclass.md` | K8sStorageClass 限制 PersistentVolumeClaim 存储类 |
| `OPA-Gatekeeper/docs/Dynamic-context-aware-policy.md` | Dynamic Context-Aware Policy Guide |
| `OPA-Gatekeeper/docs/Join-Fleet.md` | MEMBERSHIP_NAME 通常可以与集群名称一致 |
| `OPA-Gatekeeper/docs/create.md` | 1. Architecture Logic Design |
| `OPA-Gatekeeper/docs/gatekeeper-best-practices-resource-mapping.md` | Gatekeeper Best Practices - Resource Mapping Guide |
| `OPA-Gatekeeper/docs/gatekeeper-concepts.md` | - Constraint 本身没有 "Namespace" 属性，但可以通过 spec.match 来控制作用域。 |
| `OPA-Gatekeeper/docs/gke-policy-control-with-tep.md` | GKE Policy Controller Constraint Template 对比分析（修正版） |
| `OPA-Gatekeeper/docs/gke-policy-controller-requirement.md` | Gke Policy Controller Requirement |
| `OPA-Gatekeeper/docs/gke-policy-controller-with-gatekeeper.md` | GKE Policy Controller vs Standalone Gatekeeper 选型指南 |
| `OPA-Gatekeeper/docs/gke-setup-policy-controller.md` | GKE Policy Controller 完整安装与配置指南 |
| `OPA-Gatekeeper/docs/how-to-control-template.md` | How to Control Templates (ConstraintTemplate Management) |
| `OPA-Gatekeeper/docs/how-to-using-gpc.md` | GKE Policy Controller Usage Guide |
| `OPA-Gatekeeper/docs/k8srequiredlabels.md` | K8sRequiredLabels 完整指南 |
| `OPA-Gatekeeper/docs/multi-tenant-resource-quota-exception-handling.md` | Multi-Tenant Resource Quota Exception Handling |
| `OPA-Gatekeeper/docs/opa-design.md` | OPA Gatekeeper Multi-Tenant Design |
| `OPA-Gatekeeper/docs/opa-report-cronjob-conversation.md` | GKE OPA Gatekeeper 月度报告 CronJob：完整会话记录 |
| `OPA-Gatekeeper/docs/opa-report-cronjob-design.md` | GKE OPA Gatekeeper 月度报告 CronJob 方案 |
| `OPA-Gatekeeper/docs/opa-report-cronjob-solution-b.md` | OPA (Gatekeeper) 月度报告 CronJob 方案 |
| `OPA-Gatekeeper/docs/opa-report-cronjob.md` | OPA 报告定时生成与 GitHub Pages 发布（CronJob 方案） |
| `OPA-Gatekeeper/docs/policy-layer.md` | OPA Gatekeeper 策略分层评估报告 |
| `OPA-Gatekeeper/docs/rego-concept.md` | Rego 入门指南 |
| `OPA-Gatekeeper/docs/setup-log.md` | Todos |
| `OPA-Gatekeeper/docs/single-cluster-opa-gatekeeper-setup.md` | GKE 单集群安装开源 OPA Gatekeeper 操作文档 |
| `OPA-Gatekeeper/docs/step-by-step-install.md` | GKE Policy Controller Installation Guide |
| `OPA-Gatekeeper/docs/why-using-gke-policy-controller.md` | Why GKE Policy Controller — Fleet-Level Centralized Management |
| `OPA-Gatekeeper/docs/why-using-open-gatekeeper.md` | GKE Open-Source OPA Gatekeeper 单集群与多集群支持分析 |
| `OPA-Gatekeeper/merged-scripts.md` | Shell Scripts Collection |
| `OPA-Gatekeeper/policy-controller-vs-open-source-comparison.md` | GKE Policy Controller vs 开源 OPA Gatekeeper 深度对比评估报告 |

### General Documentation

| File Path | Title |
| :--- | :--- |
| `AGENTS.md` | AGENTS.md |
| `English/README.md` | English |
| `English/docs/Release.md` | - update DP |
| `English/docs/apply-testing.md` | Dear Team, |
| `English/docs/charge-mode-eg.md` | 我们是一个云平台,上面运行一些API,我们现在需要对API的计费做一个公式和已经生成了一个Dashboard.我现在需要开一个英文会议,介绍目前的情况.那么 在这个会议上可能涉及到的一些英语场景,能帮我输出一些例子么?我英语不是很好.需要提前准备资料 |
| `English/docs/container2.md` | We have now received a notification regarding the impact of the Container upgrade. I have the following question that needs clarification... |
| `English/docs/egress-ip.md` | I have a doubt about the network problem here and I want to consult you. I wonder if it's convenient for you to help me? |
| `English/docs/gke-stable.md` | Our platform provides performance testing in the PPD environment with support for up to 500 TPS. After deploying your API to PPD, we can... |
| `English/docs/goals.md` | 个人英语水平提升目标： |
| `English/docs/holiday.md` | 外企常见假期回复模板 |
| `English/docs/mTLS.md` | In the past, due to the lack of client certificate validation support in Google’s HTTPS Load Balancer, there was a potential security ris... |
| `English/docs/mail-quota-dm.md` | 以下是润色后的邮件版本，提供了三种语气稍有不同的模版： |
| `English/docs/mail.md` | I checked the xls for detailed requirements. Most of them we have already implemented. |
| `English/docs/performance.md` | work performance |
| `English/docs/policy.md` | Updated our gke ingress case |
| `English/docs/retrospective.md` | Ladies and Gentlemen: |
| `English/docs/spot.md` | Summary: |
| `English/docs/strengh.md` | 💪 太棒了！今天我们来玩单词 “strength” 的语言游戏。 |
| `English/docs/talk-architecture.md` | Architecture Talk Guide - English & Chinese对照 |
| `English/docs/thanks.md` | Subject: Thank you for your help and support |
| `OpenAI/README.md` | OpenAI |
| `OpenAI/docs/English.md` | 我需要系统性学习英语，请按照一定的顺序为我列举 8000 个常用英语单词（注意，不需要一次性列举所有，每次 3 个）。使用印欧语音变规律提供单词，包含发音，例句，词根记忆方法（词根加粗显示），详细描述和联想宫殿。示例：**Capable** [ˈkeɪpəbl]: 有能力的... |
| `OpenAI/docs/README.md` | OpenAI & AI Tools 知识库 |
| `OpenAI/docs/Share.md` | How Can AI Transform Our Work? |
| `OpenAI/docs/Verifying-GLB.md` | Verifying GCP Global Load Balancer mTLS Configuration Prior to DNS Cutover |
| `OpenAI/docs/chattts.md` | To activate this environment, use |
| `OpenAI/docs/claude-cloudflare.md` | Cloudflare 自身不要代理（容易被反爬虫判断）所以 Cloudflare 域名必须直连 |
| `OpenAI/docs/concept.md` | 温度（Temperature） |
| `OpenAI/docs/pic.md` | Prompt share To unwind after a long week I invite you to generate people being kind to animals. Share your creations. prompt: a person ca... |
| `OpenAI/docs/trans.md` | Optimized prompt: Would you be able to help me translate input English into Chinese or translate my spoken Chinese into English? |
| `OpenAI/docs/web-development.md` | Copy, paste and submit a prompt in the Messages tab. See the magic for yourself! :魔法棒: |
| `README.md` | Knowledge |
| `best-practices/README.md` | Best Practices 索引 — 全仓导航 |
| `bin/sync-html-to-docs.md` | Sync HTML files from knowledge workspace to docs directory |
| `bin/sync-skills.md` | sync-skills.py |
| `cloud/README.md` | Cloud |
| `develop/README.md` | Develop |
| `docs/README.md` | Sync URL Manifest |
| `flow/Excalidraw/README.md` | Excalidraw |
| `flow/Excalidraw/excalidraw-first.md` | Excalidraw Data |
| `flow/Infographic-with-mermaid.md` | Infographic vs. Mermaid：深度解析与实战指南 |
| `flow/README.md` | Flow |
| `flow/docs/How-to-expose-gemini.md` | 在GCP中隔离VPC间通过虚拟机实例暴露内部服务的方案分析 |
| `flow/docs/How-to-expose-grok.md` | **1. Understanding the Network Setup** |
| `flow/docs/How-to-expose-internalservice.md` | Chatgp |
| `flow/docs/How-to-get-route.md` | summary |
| `flow/docs/L7-L4-request-flow.md` | 回包流程 |
| `flow/docs/README.md` | Flow (Network Flow) 知识库 |
| `flow/docs/external-flow.md` | describe |
| `flow/docs/gke.md` | GKE Traffic Flow & Architecture |
| `flow/docs/internal-flow.md` | - [L7-L4-request](./L7-L4-request.md) |
| `flow/docs/pub-ingress-flow.md` | Nginx与Squid代理配置分析 |
| `flow/draw/README.md` | Draw 知识库 |
| `flow/draw/docs/Draw-Java-application.md` | Draw Java Application |
| `flow/draw/docs/ca-onboarding-flow.md` | CA证书Onboarding流程 |
| `flow/draw/docs/obsidian-excalidraw.md` | ![[first]] |
| `flow/draw/docs/onboarding.md` | sequenceDiagram |
| `flow/draw/docs/renew-cert.md` | 对应的流程图（Mermaid格式） |
| `flow/draw/docs/url.md` | Url |
| `flow/flow-nginx-enhance/Summary.md` | 架构优化总结：HTTPS负载均衡器 + Cloud Armor + 金丝雀部署实施方案 |
| `flow/flow-nginx-enhance/all-flow.md` | 架构流程图集合 - All Flow Charts |
| `flow/flow-nginx-enhance/canary-deployment.md` | Nginx 金丝雀部署配置详解 |
| `flow/flow-nginx-enhance/multp-lb-single-backendservice.md` | HTTPS Load Balancer |
| `flow/flow-nginx-enhance/simple-architecture.md` | 架构优化建议：实现 Cloud Armor 精细化控制与蓝绿部署 |
| `flow/flow-nginx-enhance/swith-https.md` | 平滑切换至外部HTTPS负载均衡器 (零停机方案) |
| `gh-weekly-dashboard.README.md` | gh-weekly-dashboard.sh — GitHub Weekly Activity Dashboard |
| `gif/README.md` | GIF |
| `gif/docs/shio-code.md` | 使用说明 |
| `git-analysis-weekly.md` | Weekly Git Log Analysis |
| `knowledge/README.md` | Knowledge |
| `knowledge/docs/akamai.md` | Akamai的主要产品和服务 |
| `knowledge/docs/aws-gcp.md` | 以下是 AWS 与 GCP 部分主要产品和服务的对比，重点关注同类服务的名称和功能对比： |
| `knowledge/docs/data.md` | 当我们在编程时，数据类型是一个非常重要的概念。它们定义了数据的性质以及可以对数据执行的操作。以下是一些常见的数据类型，并附带例子和说明： |
| `knowledge/docs/endpoint.md` | 区分API的URL和Endpoints的URL |
| `knowledge/docs/gante.md` | Mermaid Gantt Chart Syntax Guide |
| `knowledge/docs/purl-and-artifact.md` | pURL 与 Artifact 概念细化 |
| `knowledge/docs/system-design-tradeoffs.md` | System design |
| `md/gante.md` | **解释** |
| `md/markdown.md` | Mermaid语法示例： |
| `md/push.md` | 使用远程 Ollama |
| `merge-usage.md` | Merge Shell Scripts 使用说明 |
| `merged-file.md` | bash |
| `other/README.md` | Other |
| `other/anaylize-git-log-2026-02-23.md` | Git Log Analysis Report (Last Week) |
| `other/coff.md` | **咖啡饮品比例表** |
| `other/docs/F5.md` | F5 GTM and LTM |
| `other/docs/jira-update.md` | 1. 获取 Jira API Token |
| `other/docs/mermaid.md` | flow Kong mtls |
| `other/docs/proxy.md` | Reverse Proxy |
| `other/docs/vscode.md` | 在 VS Code 中,可以通过快捷键快速插入当前时间。操作步骤如下: |
| `other/docs/枚举.md` | Java |
| `other/explorer-knowledge.md` | Personal Knowledge Base Management & Search Strategies |
| `other/neofetch.md` | - https://github.com/dylanaraps/neofetch |
| `other/ppt/README.md` | PPT (PowerPoint) 知识库 |
| `other/ppt/docs/appd-bt.md` | 200个Business Transaction的限制 |
| `other/ppt/docs/appd-why-custom.md` | 1. **业务隔离和独立性** |
| `other/ppt/docs/appd.md` | one page |
| `other/ppt/docs/recaptcha.md` | one page |
| `other/ppt/docs/svg.md` | SVG的主要特点： |
| `other/pr-knowledge-mindmap.md` | Pull Request 知识点分析 |
| `shortcut/README.md` | Shortcut |
| `shortcut/docs/merged-scripts.md` | Shell Scripts Collection |
| `shortcut/docs/trans.md` | - prompt |
| `system-design/system-design-cheatsheet.md` | System Design Cheatsheet |
