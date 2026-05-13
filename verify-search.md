# Summary or Background

- This markdown records my workspace verification information and scripts.

# Verify Scripts Search Results
**Last Updated:** 2026-05-14

## Shell Scripts (`.sh`)

### Ali Cloud Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `ali/k8s-migration-proxy/deploy.sh` | Deploy |
| `ali/k8s-migration-proxy/scripts/deploy-external-services.sh` | Deploy External Services |
| `ali/k8s-migration-proxy/scripts/manage-ingress.sh` | Manage Ingress |
| `ali/k8s-migration-proxy/scripts/test-ingress.sh` | Test Ingress |
| `ali/k8s-migration-proxy/scripts/verify-connectivity.sh` | Verify Connectivity |
| `ali/k8s-migration-proxy/test-proxy.sh` | Test Proxy |
| `ali/k8s-migration-proxy/validate.sh` | Validate |
| `ali/scripts/k8s-resources.sh` | K8S Resources |
| `ali/scripts/namespace-status.sh` | Namespace Status |
| `ali/scripts/verify-e2e.sh` | Verify E2E |
| `gcp/gcp-infor/linux-scripts/gcp-validate.sh` | Gcp Validate |
| `k8s/Mytools/aliases.sh` | Aliases |
| `test/dr-instance/gce-dr-validation.sh` | Gce Dr Validation |

### DNS Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `ali/ali-dns/dns-batch-update.sh` | Dns Batch Update |
| `ali/ali-dns/dns-config.sh` | Dns Config |
| `dns/dns-peering/Docker-dns/docker-build-run.sh` | Docker Build Run |
| `dns/dns-peering/dns-fqdn-verify.sh` | Dns Fqdn Verify |
| `dns/dns-peering/dns-peering-claude.sh` | Dns Peering Claude |
| `dns/dns-peering/dns-peering-eng.sh` | Dns Peering Eng |
| `dns/dns-peering/dns-query-eng.sh` | Dns Query Eng |
| `dns/dns-peering/dns-query.sh` | Dns Query |
| `dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6-enhanced.sh` | Verify Pub Priv Ip Glm Ipv6 Enhanced |
| `dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6-ok.sh` | Verify Pub Priv Ip Glm Ipv6 Ok |
| `dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6.sh` | Verify Pub Priv Ip Glm Ipv6 |
| `dns/dns-peering/verify-dns-fqdn.sh` | Verify Dns Fqdn |
| `dns/dns-peering/verify-pub-priv-ip-glm-ipv6.sh` | Verify Pub Priv Ip Glm Ipv6 |
| `dns/dns-peering/verify-pub-priv-ip-glm-ok.sh` | Verify Pub Priv Ip Glm Ok |
| `dns/dns-peering/verify-pub-priv-ip.sh` | Verify Pub Priv Ip |
| `dns/docs/dns-debug.sh` | Dns Debug |
| `dns/docs/dnsrecord-add-del-eng.sh` | Dnsrecord Add Del Eng |
| `dns/docs/dnsrecord-add-del.sh` | Dnsrecord Add Del |
| `dns/docs/dnsrecord-add-script-eng.sh` | Dnsrecord Add Script Eng |
| `dns/docs/dnsrecord-add-script.sh` | Dnsrecord Add Script |
| `dns/docs/dnsrecord-del-script-eng.sh` | Dnsrecord Del Script Eng |
| `dns/docs/dnsrecord-del-script.sh` | Dnsrecord Del Script |
| `dns/docs/private-access/create-claude-one-by-one.sh` | Create Claude One By One |
| `dns/docs/private-access/create-claude.sh` | Create Claude |
| `dns/docs/private-access/create-private-access-success-one-by-one.sh` | Create Private Access Success One By One |
| `dns/docs/private-access/create-private-access.sh` | Create Private Access |
| `gcp/migrate-gcp/migrate-dns/01-discovery.sh` | 01 Discovery |
| `gcp/migrate-gcp/migrate-dns/02-prepare-target.sh` | 02 Prepare Target |
| `gcp/migrate-gcp/migrate-dns/03-execute-migration.sh` | 03 Execute Migration |
| `gcp/migrate-gcp/migrate-dns/04-rollback.sh` | 04 Rollback |
| `gcp/migrate-gcp/migrate-dns/05-cleanup.sh` | 05 Cleanup |
| `gcp/migrate-gcp/migrate-dns/config.sh` | Config |
| `gcp/migrate-gcp/migrate-dns/examples/example-config.sh` | Example Config |
| `gcp/migrate-gcp/migrate-dns/migrate-dns.sh` | Migrate Dns |

### GCP ASM/Istio Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/asm/gloo/yamls/e2e-validation.sh` | E2E Validation |
| `gcp/asm/gloo/yamls/minimax/e2e-validation.sh` | E2E Validation |
| `gcp/asm/trace-istio-and-export.sh` | Trace Istio And Export |
| `gcp/asm/trace-istio.sh` | Trace Istio |

### GCP Cloud Run Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/cloud-run/cloud-run-automation/cloud-run-housekeep.sh` | Cloud Run Housekeep |
| `gcp/cloud-run/cloud-run-job-housekeep.sh` | Cloud Run Job Housekeep |
| `gcp/cloud-run/cloud-run-job-migration-jq-fixed.sh` | Cloud Run Job Migration Jq Fixed |
| `gcp/cloud-run/cloud-run-job-migration-jq.sh` | Cloud Run Job Migration Jq |
| `gcp/cloud-run/cloud-run-job-migration-script.sh` | Cloud Run Job Migration Script |
| `gcp/cloud-run/container-validation/app-entrypoint.sh` | App Entrypoint |
| `gcp/cloud-run/container-validation/build-with-validation.sh` | Build With Validation |
| `gcp/cloud-run/extract-env-vars.sh` | Extract Env Vars |
| `gcp/cloud-run/verify/image-branch-validation.sh` | Image Branch Validation |
| `gcp/cloud-run/verify/secure-cloud-run-deploy.sh` | Secure Cloud Run Deploy |

### GCP General/Info Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/cloud-armor/ip_filter.sh` | Ip Filter |
| `gcp/cloud-armor/ip_filter_maxos_error.sh` | Ip Filter Maxos Error |
| `gcp/gce/get_instance_timestamps.sh` | Get Instance Timestamps |
| `gcp/gce/get_instance_uptime.sh` | Get Instance Uptime |
| `gcp/gce/instance-uptime-gemini.sh` | Instance Uptime Gemini |
| `gcp/gce/rolling/rolling-mig-and-verify-status-warp.sh` | Rolling Mig And Verify Status Warp |
| `gcp/gce/rolling/rolling-mig-and-verify-status.sh` | Rolling Mig And Verify Status |
| `gcp/gce/rolling/rolling-replace-instance-groups-eng.sh` | Rolling Replace Instance Groups Eng |
| `gcp/gce/rolling/rolling-replace-instance-groups.sh` | Rolling Replace Instance Groups |
| `gcp/gce/rolling/rolling-replace-mig-enhance-minimax.sh` | Rolling Replace Mig Enhance Minimax |
| `gcp/gce/rolling/rolling-replace-mig-enhance.sh` | Rolling Replace Mig Enhance |
| `gcp/gce/rolling/verify-mig-status.sh` | Verify Mig Status |
| `gcp/gcp-infor/assistant/gcp-preflight.sh` | Gcp Preflight |
| `gcp/gcp-infor/assistant/run-verify.sh` | Run Verify |
| `gcp/gcp-infor/gcp-explore.sh` | Gcp Explore |
| `gcp/gcp-infor/gcp-functions.sh` | Gcp Functions |
| `gcp/gcp-infor/linux-scripts/gcp-linux-env.sh` | Gcp Linux Env |
| `gcp/pub-sub/pub-sub-cmek/pubsub-cmek-manager.sh` | Pubsub Cmek Manager |
| `gcp/sql/process_data.sh` | Process Data |
| `gcp/tools/git.sh` | Git |
| `monitor/gce-disk/rolling-recreate-instances.sh` | Rolling Recreate Instances |

### GCP LB Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/lb/lb-poc-from-mig.sh` | Lb Poc From Mig |
| `gcp/lb/lb-poc-gen.sh` | Lb Poc Gen |
| `gcp/lb/refer-lb-create.sh` | Refer Lb Create |
| `k8s/labels/add/06_rollback.sh` | 06 Rollback |

### GCP MIG/DNS Migration Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `ali/migrate-plan/plan1/k8s-ingress-migration-optimized.sh` | K8S Ingress Migration Optimized |
| `ali/migrate-plan/plan1/poc-rewrite/migrate-commands.sh` | Migrate Commands |
| `ali/migrate-plan/plan1/poc-rewrite/poc-test.sh` | Poc Test |
| `ali/migrate-plan/plan1/poc-rewrite/quick-migrate.sh` | Quick Migrate |
| `ali/scripts/migrate-exclude-secret.sh` | Migrate Exclude Secret |
| `gcp/migrate-gcp/get-ns-info-fast.sh` | Get Ns Info Fast |
| `gcp/migrate-gcp/get-ns-information.sh` | Get Ns Information |
| `gcp/migrate-gcp/get-ns-stats-gemini.sh` | Get Ns Stats Gemini |
| `gcp/migrate-gcp/get-ns-stats-kiro-enhance.sh` | Get Ns Stats Kiro Enhance |
| `gcp/migrate-gcp/get-ns-stats-optimized.sh` | Get Ns Stats Optimized |
| `gcp/migrate-gcp/get-ns-stats.sh` | Get Ns Stats |
| `gcp/migrate-gcp/pop-migrate/migrate.sh` | Migrate |
| `gcp/migrate-gcp/pop-migrate/scripts/cleanup.sh` | Cleanup |
| `gcp/migrate-gcp/pop-migrate/scripts/export.sh` | Export |
| `gcp/migrate-gcp/pop-migrate/scripts/import.sh` | Import |
| `gcp/migrate-gcp/pop-migrate/scripts/validate.sh` | Validate |
| `gcp/migrate-gcp/pop-migrate/test-no-yq.sh` | Test No Yq |

### GCP Secret Manager Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `ali/secrets-backup/lex/apply-secrets.sh` | Apply Secrets |

### GCP Service Account / IAM Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/migrate-gcp/migrate-secret-manage/01-setup.sh` | 01 Setup |
| `gcp/migrate-gcp/migrate-secret-manage/02-discover.sh` | 02 Discover |
| `gcp/migrate-gcp/migrate-secret-manage/03-export.sh` | 03 Export |
| `gcp/migrate-gcp/migrate-secret-manage/04-import.sh` | 04 Import |
| `gcp/migrate-gcp/migrate-secret-manage/05-verify.sh` | 05 Verify |
| `gcp/migrate-gcp/migrate-secret-manage/06-update-apps.sh` | 06 Update Apps |
| `gcp/migrate-gcp/migrate-secret-manage/config.sh` | Config |
| `gcp/migrate-gcp/migrate-secret-manage/migrate-secrets.sh` | Migrate Secrets |
| `gcp/sa/verify-another-proj-sa.sh` | : Verifies what roles/permissions a Service Account from another |
| `gcp/sa/verify-cross-project-pub-sub-sa.sh` | : Queries a GCP Service Account (from KSA binding in deploy project) |
| `gcp/sa/verify-gce-sa.sh` | : Verifies the existence, keys, and IAM roles of a GCP Service Account. |
| `gcp/sa/verify-iam-based-authentication-enhance.sh` | Verify Iam Based Authentication Enhance |
| `gcp/secret-manage/java-examples/k8s/secret-setup.sh` | Secret Setup |
| `gcp/secret-manage/java-examples/setup-gcp.sh` | Setup Gcp |
| `gcp/secret-manage/java-examples/verify-gcp-sa.sh` | Verify Gcp Sa |
| `gcp/secret-manage/list-secret/auto-select-version.sh` | Auto Select Version |
| `gcp/secret-manage/list-secret/benchmark-comparison.sh` | Benchmark Comparison |
| `gcp/secret-manage/list-secret/filter-secrets.sh` | Filter Secrets |
| `gcp/secret-manage/list-secret/list-all-secrets-optimized.sh` | List All Secrets Optimized |
| `gcp/secret-manage/list-secret/list-all-secrets-permissions-parallel.sh` | List All Secrets Permissions Parallel |
| `gcp/secret-manage/list-secret/list-all-secrets-permissions.sh` | List All Secrets Permissions |
| `gcp/secret-manage/list-secret/list-all-secrets-simple-optimized.sh` | List All Secrets Simple Optimized |
| `gcp/secret-manage/list-secret/list-secrets-groups-sa.sh` | List Secrets Groups Sa |
| `gcp/secret-manage/list-secret/test-increment-fix.sh` | Test Increment Fix |
| `gcp/secret-manage/list-secret/verify-gcp-secretmanage.sh` | Verify Gcp Secretmanage |
| `gcp/secret-manage/secret-manager-admin.sh` | Secret Manager Admin |
| `linux/linux-os-optimize/universal_optimize.sh` | Universal Optimize |
| `macos/scripts/resouce_usage.sh` | Resouce Usage |
| `safe/cwe/check_ubuntu_cve_status.sh` | Check Ubuntu Cve Status |
| `safe/cwe/verify-enhance-html.sh` | Verify Enhance Html |
| `safe/cwe/verify-enhance.sh` | Verify Enhance |
| `safe/cwe/verify.sh` | Verify |
| `safe/gcp-safe/debug-test.sh` | Debug Test |
| `safe/gcp-safe/quick-test.sh` | Quick Test |
| `safe/gcp-safe/test-arithmetic.sh` | Test Arithmetic |
| `safe/gcp-safe/test-permissions.sh` | Test Permissions |
| `safe/gcp-safe/verify-kms-enhanced.sh` | Verify Kms Enhanced |
| `safe/get-token/curl-token.sh` | Curl Token |
| `safe/scripts/basic-domain-explorer.sh` | Basic Domain Explorer |
| `safe/scripts/basic_recon.sh` | Basic Recon |
| `safe/scripts/domain_intel.sh` | : A comprehensive domain reconnaissance script based on the workflow from kal... |
| `safe/scripts/explorer-domain-claude.sh` | Explorer Domain Claude |
| `safe/scripts/git.sh` | Git |

### GCS Bucket Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/buckets/add-bucket-binding.sh` | Add Bucket Binding |
| `gcp/buckets/create-buckets.sh` | Create Buckets |
| `gcp/buckets/verify-buckets-iam-grok.sh` | Verify Buckets Iam Grok |
| `gcp/buckets/verify-buckets-iam.sh` | Verify Buckets Iam |
| `gcp/buckets/verify-buckets.sh` | Verify Buckets |

### Gateway/GKE Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gateway/no-gateway/verify-gke-gateway-chatgpt.sh` | Verify Gke Gateway Chatgpt |
| `gateway/no-gateway/verify-gke-gateway-claude.sh` | Verify Gke Gateway Claude |
| `gateway/no-gateway/verify-gke-gateway.sh` | Verify Gke Gateway |
| `gateway/no-gateway/verify-no-gateway-all.sh` | Verify No Gateway All |
| `gcp/gce/verify-gcp-and-gke-status.sh` | Verify Gcp And Gke Status |
| `gcp/sa/verify-gke-ksa-iam-authentication.sh` | Verify Gke Ksa Iam Authentication |

### Java/Debug Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `java-timeout/run.sh` | Run |
| `java/java-pom/ci-diagnostic-script.sh` | Ci Diagnostic Script |
| `java/java-scan/scripts/pipeline-integration.sh` | Pipeline Integration |
| `java/scripts/test-dry-run.sh` | Test Dry Run |

### K8s Pod/Health Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `docker/scripts/debug-java-pod.sh` | : 自动创建带 Sidecar 的调试 Deployment 用于分析无法启动的 Java 应用镜像 |
| `gcp/cloud-run/container-validation/startup-validator-v2.sh` | Startup Validator V2 |
| `gcp/cloud-run/container-validation/startup-validator-v3.sh` | Startup Validator V3 |
| `gcp/cloud-run/container-validation/startup-validator.sh` | Startup Validator |
| `java/scripts/debug-java-pod.sh` | : 自动创建带 Sidecar 的调试 Deployment 用于分析无法启动的 Java 应用镜像 |
| `java/scripts/debug-pod.sh` | Debug Pod |
| `k8s/custom-liveness/build-custom-image.sh` | Build Custom Image |
| `k8s/custom-liveness/deploy-and-test.sh` | Deploy And Test |
| `k8s/custom-liveness/deploy-and-verify.sh` | Deploy And Verify |
| `k8s/custom-liveness/explore-startprobe/get-deploy-health-url.sh` | Get Deploy Health Url |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhance.sh` | Pod Measure Startup Enhance |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_gemini.sh` | Pod Measure Startup Enhanced Gemini |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v2.sh` | Pod Measure Startup Enhanced V2 |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v3.sh` | Pod Measure Startup Enhanced V3 |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v4.sh` | Pod Measure Startup Enhanced V4 |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v5.sh` | Pod Measure Startup Enhanced V5 |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v6.sh` | Pod Measure Startup Enhanced V6 |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_fixed_en.sh` | Pod Measure Startup Fixed En |
| `k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup.sh` | Verify Pod Measure Startup |
| `k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup_fixed.sh` | Verify Pod Measure Startup Fixed |
| `k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup_fixed_en.sh` | Verify Pod Measure Startup Fixed En |
| `k8s/debug-pod/side-optimized.sh` | Side Optimized |
| `k8s/debug-pod/test-script.sh` | Test Script |
| `k8s/images/verify_pod_image_pull_time.sh` | Verify Pod Image Pull Time |
| `k8s/images/verify_pod_image_pull_time_sh.sh` | Verify Pod Image Pull Time Sh |
| `k8s/lib/pod_health_check_lib.sh` | : Check health endpoint inside a Pod |
| `k8s/scripts/batch_health_check.sh` | Batch Health Check |
| `k8s/scripts/debug_health_check.sh` | Debug Health Check |
| `k8s/scripts/measure_startup_simple.sh` | Measure Startup Simple |
| `k8s/scripts/pod-system-version.sh` | Pod System Version |
| `k8s/scripts/pod_exec.sh` | Pod Exec |
| `k8s/scripts/pod_measure_startup_bak.sh` | Pod Measure Startup Bak |
| `k8s/scripts/pod_measure_startup_fixed.sh` | Pod Measure Startup Fixed |
| `k8s/scripts/pod_status.sh` | Pod Status |

### Kong Data Plane Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `kong/kongdp/compare-dp-eng.sh` | Compare Dp Eng |
| `kong/kongdp/compare-dp.sh` | Compare Dp |
| `kong/kongdp/verify-dp-status-gemini.sh` | Verify Dp Status Gemini |
| `kong/kongdp/verify-dp-status.sh` | Verify Dp Status |
| `kong/kongdp/verify-dp-summary.sh` | Verify Dp Summary |
| `kong/kongdp/verify-dp.sh` | Verify Dp |
| `kong/scripts/git.sh` | Git |

### Linux/Optimization Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `k8s/k8s-scale/optimize_k8s_resources.sh` | Optimize K8S Resources |
| `k8s/k8s-scale/optimize_k8s_resources_v2.sh` | Optimize K8S Resources V2 |
| `linux/docs/verify-timeout-chain.sh` | Verify Timeout Chain |
| `linux/linux-os-optimize/Linux-system-optimize.sh` | Linux System Optimize |
| `linux/linux-os-optimize/linux-nginx-system-optimize-calude4-5.sh` | Linux Nginx System Optimize Calude4 5 |
| `linux/linux-os-optimize/linux-nginx-system-optimize.sh` | : Optimize Linux system limits and kernel parameters |
| `linux/linux-os-optimize/linux-system-optimize-gemini.sh` | : |
| `linux/linux-os-optimize/linux-system-optimize-tt.sh` | Linux System Optimize Tt |
| `linux/scripts/csv-format-bard.sh` | Csv Format Bard |
| `linux/scripts/git.sh` | Git |

### Other Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `English/scripts/read_doc.sh` | Read Doc |
| `React/scripts/build.sh` | Build |
| `React/scripts/deploy.sh` | Deploy |
| `ai/concept/demo.sh` | Demo |
| `ai/concept/kb_search.sh` | Kb Search |
| `ai/concept/setup.sh` | Setup |
| `ai/docs/ocrp.sh` | Ocrp |
| `apple/scripts/code-to-note.sh` | Code To Note |
| `apple/scripts/create-note-from-file.sh` | Create Note From File |
| `apple/scripts/simple-file-to-note.sh` | Simple File To Note |
| `bin/sync-html-to-docs.sh` | Sync Html To Docs |
| `cost/gcp-cost/gcp-logging-audit-script.sh` | Gcp Logging Audit Script |
| `cost/gcp-cost/gcp-logging-quick-setup.sh` | Gcp Logging Quick Setup |
| `firestore/scripts/firestore-get-collection-chatgpt.sh` | Firestore Get Collection Chatgpt |
| `firestore/scripts/firestore-get-collection-claude.sh` | Firestore Get Collection Claude |
| `firestore/scripts/firestore-get-collection-grok.sh` | Firestore Get Collection Grok |
| `firestore/scripts/firestore-get-collection.sh` | Firestore Get Collection |
| `firestore/scripts/firestore-get-specific-fields.sh` | Firestore Get Specific Fields |
| `firestore/scripts/get_value.sh` | Get Value |
| `fm.sh` | Fm |
| `gif/docs/git.sh` | Git |
| `gif/scripts/covert-mp4-git.sh` | Covert Mp4 Git |
| `gif/scripts/vide-cut.sh` | Vide Cut |
| `gif/scripts/video-watermark.sh` | Video Watermark |
| `git-detail-status.sh` | Git Detail Status |
| `git-ios.sh` | Git Ios |
| `git-mac.sh` | Git Mac |
| `git-push.sh` | Git Push |
| `git.sh` | Git |
| `git_detail_stats.sh` | Git Detail Stats |
| `go/scripts/configmap-management.sh` | Configmap Management |
| `go/scripts/test-local.sh` | Test Local |
| `groovy/scripts/git.sh` | Git |
| `k8s/Mytools/example-custom.sh` | Example Custom |
| `k8s/Mytools/init.sh` | Init |
| `k8s/Mytools/mount-config-template.sh` | Mount Config Template |
| `k8s/Mytools/run-container.sh` | Run Container |
| `k8s/images/images-update.sh` | Images Update |
| `k8s/images/k8s-image-replace.sh` | K8S Image Replace |
| `k8s/labels/add-deployment-labels-flexible.sh` | Add Deployment Labels Flexible |
| `k8s/labels/add-deployment-labels.sh` | Add Deployment Labels |
| `k8s/labels/add/01_export_data.sh` | 01 Export Data |
| `k8s/labels/add/02_generate_mapping.sh` | 02 Generate Mapping |
| `k8s/labels/add/03_backup.sh` | 03 Backup |
| `k8s/labels/add/04_apply_labels.sh` | 04 Apply Labels |
| `k8s/labels/add/05_verify.sh` | 05 Verify |
| `k8s/labels/deployment-helper.sh` | Deployment Helper |
| `k8s/labels/flexible.sh` | Flexible |
| `k8s/lib/test_lib.sh` | Test Lib |
| `k8s/qnap-k8s/ init-k8s.sh` | Init K8S |
| `k8s/qnap-k8s/install-k8s-deps.sh` | Install K8S Deps |
| `k8s/qnap-k8s/test-qnap-detection.sh` | Test Qnap Detection |
| `k8s/scripts/git.sh` | Git |
| `k8s/scripts/minimal_test.sh` | Minimal Test |
| `k8s/scripts/simple_test.sh` | Simple Test |
| `macos/neofetch/neofetch.sh` | Neofetch |
| `macos/scripts/chat.sh` | Chat |
| `macos/scripts/fix-bash.sh` | Fix Bash |
| `macos/scripts/hugg.sh` | Hugg |
| `macos/scripts/macos_power_keepawake.sh` | Macos Power Keepawake |
| `macos/scripts/macos_power_keepawake_stop.sh` | Macos Power Keepawake Stop |
| `macos/scripts/macos_power_restore_defaults.sh` | Macos Power Restore Defaults |
| `macos/scripts/macos_power_schedule.sh` | Macos Power Schedule |
| `macos/scripts/macos_power_server_mode.sh` | Macos Power Server Mode |
| `macos/scripts/macos_power_status.sh` | Macos Power Status |
| `macos/scripts/monitor_background_shortcut_runner.sh` | Monitor Background Shortcut Runner |
| `macos/scripts/resource.sh` | Resource |
| `network/scripts/explorer-domain-claude.sh` | Explorer Domain Claude |
| `network/scripts/explorer-domain-gemini.sh` | : An advanced script for comprehensive domain analysis, including DNS, IP, we... |
| `network/scripts/explorer-domain-grok.sh` | Explorer Domain Grok |
| `network/scripts/explorer-domain-kimi.sh` | Explorer Domain Kimi |
| `network/scripts/explorer-domain-qwen.sh` | Explorer Domain Qwen |
| `network/scripts/explorer-domain.sh` | Explorer Domain |
| `network/scripts/test-ipv6-local.sh` | Test Ipv6 Local |
| `network/wrk/advanced-load-test.sh` | Advanced Load Test |
| `network/wrk/config-based-test.sh` | Config Based Test |
| `network/wrk/pressure-test-suite.sh` | Pressure Test Suite |
| `node/scripts/configmap-management.sh` | Configmap Management |
| `node/scripts/test-local.sh` | Test Local |
| `other/scripts/git.sh` | Git |
| `pipeline/cd-pipeline/scripts/render-and-apply.sh` | Render And Apply |
| `pipeline/cd-pipeline/scripts/sync-image.sh` | Sync Image |
| `psc-sql-flow-demo/scripts/cleanup.sh` | Cleanup |
| `psc-sql-flow-demo/scripts/deploy-app.sh` | Deploy App |
| `psc-sql-flow-demo/scripts/monitor.sh` | Monitor |
| `psc-sql-flow-demo/scripts/test-connection.sh` | Test Connection |
| `psc-sql-flow-demo/setup/env-vars.sh` | Env Vars |
| `psc-sql-flow-demo/setup/setup-consumer.sh` | Setup Consumer |
| `psc-sql-flow-demo/setup/setup-producer.sh` | Setup Producer |
| `push-c.sh` | Push C |
| `push-call-local-ai.sh` | Push Call Local Ai |
| `push-claude.sh` | Push Claude |
| `push-llama.sh` | Push Llama |
| `push.sh` | Push |
| `rais.sh` | Rais |
| `shell-script/scripts/batch_replace.sh` | Batch Replace |
| `shell-script/scripts/batch_replace_preview.sh` | Batch Replace Preview |
| `shell-script/scripts/git-detail-status.sh` | Git Detail Status |
| `shell-script/scripts/git.sh` | Git |
| `shell-script/scripts/replace.sh` | Replace |
| `shell-script/scripts/source.sh` | Source |
| `shortcut/scripts/a.sh` | A |
| `shortcut/scripts/batch_replace.sh` | Batch Replace |
| `shortcut/scripts/batch_replace_preview.sh` | Batch Replace Preview |
| `splunk/scripts/git.sh` | Git |
| `sql/scripts/git.sh` | Git |
| `test-merge.sh` | Test Merge |
| `test/dr-instance/dr-instance.sh` | Dr Instance |
| `test/dr-instance/run-dr-test.sh` | Run Dr Test |

### SSL/TLS Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `api-service/python-api-demo/python-health-demo/generate_certs.sh` | Generate Certs |
| `gcp/lb/lb-get-ssl-infor.sh` | Lb Get Ssl Infor |
| `gcp/mtls/mtls-test/gemini.sh` | Gemini |
| `gcp/mtls/mtls-test/generate-self-signed-cert_lmstudio.sh` | Generate Self Signed Cert Lmstudio |
| `gcp/mtls/mtls-test/generate-self-singned-cert.sh` | Generate Self Singned Cert |
| `gcp/mtls/mtls-test/get_cert_fingerprint.sh` | Get Cert Fingerprint |
| `gcp/mtls/mtls-test/get_cert_fingerprint_chatgpt.sh` | Get Cert Fingerprint Chatgpt |
| `gcp/mtls/mtls-test/get_cert_fingerprint_claude.sh` | Get Cert Fingerprint Claude |
| `gcp/mtls/mtls-test/get_cert_fingerprint_no_type.sh` | Get Cert Fingerprint No Type |
| `gcp/mtls/trust-config/debug-trust-configs.sh` | : Debug version to test trust config access |
| `gcp/mtls/trust-config/verify-trust-configs.sh` | : Verify GCP Certificate Manager Trust Configs and extract |
| `go/scripts/cert-management.sh` | Cert Management |
| `go/scripts/convert-cert.sh` | Convert Cert |
| `java/java-auth/simple-https-demo/generate-cert.sh` | Generate Cert |
| `nginx/ingress-control/check-tls-secret-ns.sh` | Check Tls Secret Ns |
| `nginx/ingress-control/check-tls-secret.sh` | Check Tls Secret |
| `nginx/ingress-control/check-tls-secret2.sh` | Check Tls Secret2 |
| `node/scripts/cert-management.sh` | Cert Management |
| `node/scripts/convert-cert.sh` | Convert Cert |
| `safe/cert/check_eku.sh` | Check Eku |
| `safe/cert/digicert_impact_assessment.sh` | Digicert Impact Assessment |
| `ssl/docs/claude/routeaction/maps-format-and-verify/apply-urlmap-json.sh` | Apply Urlmap Json |
| `ssl/docs/claude/routeaction/maps-format-and-verify/verify-urlmap-json.sh` | Verify Urlmap Json |
| `ssl/ingress-ssl/check-tls-secret-ns.sh` | Check Tls Secret Ns |
| `ssl/ingress-ssl/check-tls-secret.sh` | Check Tls Secret |
| `ssl/ingress-ssl/create-tls-secret.sh` | Create Tls Secret |
| `ssl/ingress-ssl/generate-cert-chain.sh` | Generate Cert Chain |
| `ssl/ingress-ssl/generate-self-signed-cert.sh` | Generate Self Signed Cert |
| `ssl/scripts/get-ssl-all-information.sh` | Get Ssl All Information |
| `ssl/scripts/get-ssl-all.sh` | Get Ssl All |
| `ssl/scripts/get-ssl.sh` | Get Ssl |
| `ssl/verify-domain-ssl-enhance.sh` | Verify Domain Ssl Enhance |
| `ssl/verify-domain-ssl.sh` | Verify Domain Ssl |

### howgit Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `howgit/scripts/git_changes_stats.sh` | Git Changes Stats |
| `howgit/scripts/git_detailed_stats.sh` | Git Detailed Stats |
| `howgit/scripts/git_recent_changes.sh` | Git Recent Changes |
| `howgit/scripts/github_api_stats.sh` | Github Api Stats |

---

## Markdown Documents (`.md`)

### Ali Cloud Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `Excalidraw/README.md` | Excalidraw |
| `Excalidraw/excalidraw-first.md` | Excalidraw Data |
| `OPA-Gatekeeper/constraint-explorers/externalip.md` | K8sExternalIPs 限制 Service 外部 IP |
| `ali/README.md` | Ali (阿里巴巴) |
| `ali/docs/Ali-Logstore.md` | 梳理一下阿里云 K8S 里的 **日志采集**和 **Logstore 加密**的概念。 |
| `ali/docs/README.md` | Ali (Alibaba Cloud) 知识库 |
| `ali/docs/a-call-b-debug.md` | Summary |
| `ali/docs/imagepullsecret.md` | concepts |
| `ali/docs/merged-scripts.md` | Shell Scripts Collection |
| `ali/docs/migrate-exclude-secret.md` | Kubernetes Secrets 迁移脚本 |
| `ali/docs/namespace-status.md` | !/bin/bash |
| `ali/docs/slb-binding-ingress.md` | New |
| `ali/docs/v4.md` | !/bin/bash |
| `ali/docs/v5.md` | !/bin/bash |
| `ali/docs/v6.md` | !/bin/bash |
| `ali/docs/v7.md` | !/bin/bash |
| `ali/docs/verify-e2e.md` | !/bin/bash |
| `ali/max-computer/Dataworks-binding.md` | **🧩 一、基础概念梳理** |
| `ali/max-computer/Health-check.md` | Health Check |
| `ali/max-computer/create-table.md` | **🧩 一、核心目标与实现路径** |
| `ali/max-computer/maxcompute-health-check/README.md` | MaxCompute Health Check API |
| `ali/max-computer/threshold-maxcomputer.md` | MaxCompute 资源阈值、配额管理与 SRE 监控实践 (结合 DataWorks) |
| `ali/max-computer/threshold.md` | A |
| `ali/max-computer/why-using-maxcomputer.md` | 关于“我们是否必须使用 MaxCompute”的技术澄清 |
| `ali/migrate-plan/max-computer-gemini.md` | 阿里云 MaxCompute 是什么以及如何迁移 |
| `ali/migrate-plan/max-computer.md` | 导出数据 |
| `ali/migrate-plan/plan1/README-OPTIMIZED.md` | Kubernetes Ingress Migration Tool - Optimized Version |
| `ali/migrate-plan/plan1/README.md` | K8s集群迁移POC方案 |
| `ali/migrate-plan/plan1/backgroud.md` | Backgroud |
| `ali/migrate-plan/plan1/migrate-claude.md` | 方案对比 |
| `ali/migrate-plan/plan1/migrate-gpt.md` | summary |
| `ali/migrate-plan/plan1/migrate-grok.md` | Kubernetes 集群迁移方案审阅 |
| `ali/migrate-plan/plan1/migrate-namespace.md` | Migrate Namespace |
| `ali/migrate-plan/plan1/poc-rewrite/before-after-comparison.md` | 迁移前后对比图 |
| `ali/migrate-plan/plan1/poc-rewrite/externalname-flow.md` | ExternalName Service 工作流程详解 |
| `ali/migrate-plan/plan1/poc-rewrite/merged-scripts.md` | Shell Scripts Collection |
| `ali/migrate-plan/plan1/poc-rewrite/poc-analysis.md` | K8s集群迁移POC可行性分析 |
| `ali/migrate-plan/plan1/poc-rewrite/poc-implementation.md` | POC实施指南 |
| `ali/migrate-plan/plan1/short-domain-gpt.md` | Q |
| `ali/migrate-plan/plan1/short-domian-claude.md` | 迁移架构分析 |
| `draw/docs/obsidian-excalidraw.md` | Obsidian Excalidraw |
| `gcp/cloud-run/container-validation/CONFIGURATION.md` | 容器启动校验器配置指南 |
| `gcp/cloud-run/container-validation/README.md` | 容器内部校验解决方案 |
| `gcp/cloud-run/verify/branch-validation-guide.md` | Cloud Run 镜像分支校验指南 |
| `gcp/gce/gcp-hight-avaliablity-terminology.md` | Gcp Hight Avaliablity Terminology |

### CI/CD Pipeline Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `English/docs/Release.md` | Release |
| `gcp/asm/deploy-claude-mermaid.md` | ASM on GKE — 资源分层部署图 (Mermaid) |
| `gcp/asm/deploy-claude.md` | ASM on GKE — `abjx-int` Namespace 部署实施说明 (V1) |
| `gcp/asm/deploy.md` | ASM on GKE 部署与流量路径细化 |
| `gcp/cloud-run/cloud-run-deploy.md` | Cloud Run Jobs 部署方法深度解析 |
| `gcp/cloud-run/gcp-cloud-run-deploy.md` | Grok |
| `go/docs/golang-deploy.md` | 强制统一端口 |
| `howgit/docs/Release-git.md` | 仅克隆某个分支下的某个目录 |
| `monitor/docs/pipeline-status.md` | !/bin/bash |
| `pipeline/README.md` | Pipeline 知识库 |
| `pipeline/cd-pipeline/Namespace_Ingress_Policy.md` | Namespace & Ingress 标准化策略 |
| `pipeline/cd-pipeline/PMU_Checklist.md` | PMU (Platform Management Unit) 校验 Checklist |
| `pipeline/cd-pipeline/Reademe.md` | **🧩 1. 问题分析** |
| `pipeline/cd-pipeline/implementation_plan.md` | Implementation Plan - Refactor CD Pipeline (No Kustomize) |
| `pipeline/cd-pipeline/migrate-pipeline-develop.md` | Q |
| `pipeline/cd-pipeline/pipeline-cd-claude.md` | Pipeline 改造方案分析 |
| `pipeline/cd-pipeline/pipeline-cd-gemini.md` | 文件生成 |
| `pipeline/cd-pipeline/walkthrough.md` | CD Pipeline Demo Walkthrough (Refactored) |
| `pipeline/docs/copy-pipeline.md` | q |
| `pipeline/docs/housekeep-sms.md` | Script for scan secret |
| `pipeline/docs/insert-json.md` | Q |
| `pipeline/docs/master-branch.md` | 检查各团队 pipeline 配置中的 shared library 分支信息 |
| `pipeline/docs/oidc.md` | OIDC |
| `pipeline/docs/pipeline-flow.md` | 1️⃣ 问题分析（Flow 的核心） |
| `pipeline/docs/pipeline-layer.md` | Pipeline Layer |
| `pipeline/docs/sonar.md` | 代码覆盖率的几个常见指标 |
| `pipeline/docs/stash.md` | 概念 |
| `pipeline/docs/trigger-pipeline-gemini.md` | 在 Pull Request (PR) 创建时自动触发 CI 测试 |
| `pipeline/docs/trigger-pipeline.md` | **一、用户的需求分析** |
| `pipeline/release-dashboard/README.md` | Release Dashboard |
| `pipeline/release-dashboard/Release-Readme.md` | meeting |
| `pipeline/release-dashboard/Release-pipeline.md` | 主要特性说明 |
| `squid/docs/squid-deploy-blue.md` | 问题分析 |
| `squid/docs/squid-deploy-claude.md` | Squid 多配置部署最佳实践 |
| `squid/docs/squid-deploy.md` | ChatGPT |

### Container/Docker Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `English/docs/container2.md` | Container2 |
| `OPA-Gatekeeper/constraint-explorers/containerlimits.md` | K8sContainerLimits 容器资源限制详解 |
| `docker/README.md` | Docker 知识库 |
| `docker/docs/Dockeffile-user-pass-violation.md` | title: Dockerfile中存在以下几个问题，可能涉及安全性和最佳实践违规 |
| `docker/docs/Docker-annotations.md` | **1. Problem Analysis** |
| `docker/docs/Docker-prune.md` | 步骤一：检查磁盘使用情况 |
| `docker/docs/docker-image-lifecycle.md` | Docker Image Lifecycle |
| `docker/docs/docker-sepcial.md` | 提取的文本信息： |
| `docker/docs/docker-utf8.md` | 示例Dockerfile |
| `docker/docs/mac-Docker-nas.md` | 要点结论（快速答案） |
| `docker/docs/merged-scripts.md` | Shell Scripts Collection |
| `docker/docs/network-multitool.md` | **问题分析** |
| `docker/docs/utf-8.md` | Q |
| `docker/multistage-builds/Dockerfile.md` | **问题分析（为何要详细解释这个多阶段 Dockerfile）** |
| `docker/multistage-builds/migration-guide.md` | Multistage Builds 迁移指南 |
| `docker/multistage-builds/multi-stage.md` | ================================ |
| `docker/multistage-builds/multistage-build-analysis.md` | Multistage Builds 深度分析与实施方案 (Java 应用) |
| `docker/multistage-builds/multistage-build-concepts.md` | set env |
| `gcp/cloud-run/cloud-run-container-cmd.md` | Cloud Run 容器命令 (Container Command) 与参数 (Arguments) 详解 |
| `gcp/cloud-run/cloud-run-violation/Cloud-run-verify-images-using-OpenPGP.md` | Summary |
| `gcp/cloud-run/cloud-run-violation/cloud-run-verify-images-OpenPGP.md` | Claude |
| `gcp/cloud-run/cloud-run-violation/cloud-run-verify-images-claude.md` | GCP Cloud Run Binary Authorization 镜像签名验证完整指南 |
| `gcp/cloud-run/cloud-run-violation/cloud-run-verify-images.md` | Summay |
| `gcp/migrate-gcp/gar-container.md` | 问题分析 |
| `nas/docs/Docker-network-claude-cn.md` | QNAP NAS 上的 Docker 网络架构 - Claude 的分析 |
| `nas/docs/Docker-network-claude.md` | Docker Network Architecture on QNAP NAS - Claude's Analysis |
| `nas/docs/Docker-network-cn.md` | QNAP NAS 上的 Docker 进程与网络详解 |
| `nas/docs/Docker-network.md` | Docker Process and Networking on QNAP NAS |
| `nas/docs/docker-network-flow.md` | Docker 网络流程图集 |
| `nas/docs/docker-proxy.md` | **问题分析** |
| `nas/docs/local-images-error.md` | Local Images Error |
| `pipeline/cd-pipeline/get-container.md` | 获取 Deployment Container 名称的方法 |
| `pipeline/cd-pipeline/image-replace.md` | K8s Image Replace 脚本优化方案 |
| `shell-script/docs/docker.md` | Docker |
| `squid/docs/squid-docker.md` | Q |

### Cost Management Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `cost/README.md` | Cost 知识库 |
| `cost/gcp-cost/README.md` | GCP 日志成本优化工具包 |
| `cost/gcp-cost/audit-log.md` | 检查审计日志配置 |
| `cost/gcp-cost/gcp-cost-gemini.md` | GCP 日志成本优化与治理权威指南 |
| `cost/gcp-cost/gcp-log-cost.md` | Summay |
| `cost/gcp-cost/gcp-logging-cost-optimization-guide.md` | GCP 日志成本优化完整指南 |
| `cost/gcp-cost/script.md` | !/bin/bash |
| `cost/gcp-cost/workload.md` | 审计 GKE 集群配置 |
| `gcp/cost/collect-information.md` | **提取文本** |
| `gcp/cost/one-off-design.md` | V1 |
| `gcp/pub-sub/css2/compare-firestore-secret-cost-cn.md` | Firestore 与 GCP Secret Manager 成本比较 |
| `gcp/pub-sub/css2/compare-firestore-secret-cost.md` | Firestore vs GCP Secret Manager Cost Comparison |
| `report/docs/api-cost-180.md` | Api Cost 180 |
| `report/docs/api-cost.md` | Q |

### DNS Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `ali/ali-dns/README.md` | DNS Batch Update Tool |
| `ali/ali-dns/merged-scripts.md` | Shell Scripts Collection |
| `ali/migrate-plan/plan2/migrate-all-dns-record-explorer.md` | summary |
| `dns/README.md` | DNS |
| `dns/dns-peering/Docker-dns/README_DOCKER.md` | DNS Verification Tool - Docker Service |
| `dns/dns-peering/README.md` | Verify Public/Private IP Script (`verify-pub-priv-ip.sh`) |
| `dns/dns-peering/dns-query-peering.md` | script |
| `dns/dns-peering/github/explorer-html.md` | 将 DNS 验证脚本转换为 GitHub Pages 静态页面的探索方案 |
| `dns/dns-peering/ip-choose.md` | FQDN 出口模式选择最佳实践 (Public vs Private) |
| `dns/dns-peering/merged-scripts.md` | Shell Scripts Collection |
| `dns/docs/a-and-wirdcard.md` | 操作步骤（阿里云 DNS 控制台） |
| `dns/docs/a.md` | !/bin/bash |
| `dns/docs/apply-cname.md` | CNAME |
| `dns/docs/apply-wirdcard-cert.md` | 一、DNS 层级 vs 证书申请是否冲突 |
| `dns/docs/cloud-dns.md` | 其他必要的配置... |
| `dns/docs/cross-project-dns-demis-dns-switch.md` | Claude |
| `dns/docs/dns-length.md` | DNS域名长度规范 |
| `dns/docs/dns-log.md` | update |
| `dns/docs/dns-migrate.md` | GCP DNS 记录迁移脚本 |
| `dns/docs/dns-peerning.md` | a |
| `dns/docs/dns-svc-compare.md` | summary |
| `dns/docs/dns-v2.md` | Dns V2 |
| `dns/docs/gcp-dns-forwarding.md` | GCP Cloud DNS Forwarding — Deep Dive |
| `dns/docs/gke-dns-resolution-flow.md` | GKE DNS Resolution Flow — Full Debug Guide |
| `dns/docs/kube-dns.md` | 前提要求 |
| `dns/docs/loon-dns.md` | **一、问题分析** |
| `dns/docs/merged-scripts.md` | Shell Scripts Collection |
| `dns/docs/migrate-dns-enhance.md` | GCP DNS 迁移脚本 - 增强版 |
| `dns/docs/priority-response.md` | Q |
| `dns/docs/private-access/merged-scripts.md` | Shell Scripts Collection |
| `dns/docs/s.md` | S |
| `dns/docs/shared-logs.md` | anaylize |
| `dns/docs/verify-dnspeering.md` | 获取所有 DNS zone 并过滤出 peering zone |
| `gcp/migrate-gcp/migrate-dns/How-to-switch-dns.md` | DNS 迁移自动化方案（GKE 多项目 / 多集群） |
| `gcp/migrate-gcp/migrate-dns/Kiro-dns.md` | GCP 跨项目 DNS 迁移解决方案 |
| `gcp/migrate-gcp/migrate-dns/Qwen-anayliz-dns.md` | GCP DNS 跨项目迁移分析与方案设计 (Qwen-anayliz-dns.md) |
| `gcp/migrate-gcp/migrate-dns/README.md` | GCP DNS 迁移工具 |
| `gcp/migrate-gcp/migrate-dns/chatgpt-migrate-dns.md` | DNS 迁移自动化方案（GKE 多项目 / 多集群） |
| `gcp/migrate-gcp/migrate-dns/examples/migration-checklist.md` | DNS 迁移检查清单 |
| `gcp/migrate-gcp/migrate-dns/gemini-analyiz-dns.md` | GCP DNS 迁移策略与自动化脚本分析 |
| `gcp/migrate-gcp/migrate-dns/merged-script-dns.md` | Shell Scripts Collection |
| `gcp/migrate-gcp/migrate-dns/pop-dns.md` | Q |
| `k8s/docs/flow-dns.md` | Flow Dns |
| `k8s/docs/verify-kube-dns.md` | Verify kube-dns working |
| `k8s/networkpolicy/networkpolicy-dns.md` | Istio 网格内 DNS 解析与服务发现机制 |
| `macos/docs/dns.md` | Dns |

### GCP Cloud Run Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
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
| `gcp/cloud-run/cloud-run-debug.md` | Cloud Run Job 日志缺失问题分析与最佳实践 |
| `gcp/cloud-run/cloud-run-debug/cloud-run-debug-500.md` | 诊断 GKE 调用 Cloud Run 时的 AsyncRequestTimeoutException (500) |
| `gcp/cloud-run/cloud-run-debug/cloud-run-debug-log.md` | Claude |
| `gcp/cloud-run/cloud-run-job-housekeep-sh.md` | !/bin/bash |
| `gcp/cloud-run/cloud-run-job-housekeep.md` | Cloud Run Job Housekeeping |
| `gcp/cloud-run/cloud-run-job-migration-jq.md` | !/bin/bash |
| `gcp/cloud-run/cloud-run-job-with-services.md` | 🧠 总结建议 |
| `gcp/cloud-run/cloud-run-limit-permission.md` | Cloud Run Job 参数与权限深度解析 |
| `gcp/cloud-run/cloud-run-network.md` | summary |
| `gcp/cloud-run/cloud-run-violation/a.md` | A |
| `gcp/cloud-run/cloud-run-violation/binary-authorization-default.md` | summary |
| `gcp/cloud-run/cloud-run-violation/binary-authorization.md` | claude |
| `gcp/cloud-run/cloud-run-violation/setup-binauthz-shared-kms.md` | !/bin/bash |
| `gcp/cloud-run/cmd.md` | Cmd |
| `gcp/cloud-run/execute.md` | Q |
| `gcp/cloud-run/fixed.md` | !/bin/bash |
| `gcp/cloud-run/gcp-cloud-run-network.md` | Cloud Run 网络与安全精细化配置 |
| `gcp/cloud-run/monitor-cloud-run.md` | Claude |
| `gcp/cloud-run/network-explorer.md` | Q |
| `gcp/cloud-run/network-requirement.md` | summary |
| `gcp/cloud-run/new.md` | New |
| `gcp/cloud-run/onboarding/cloud-run-onboarding-design.md` | 场景一：用户 Onboarding 阶段触发 mTLS 证书自动续期 |
| `gcp/cloud-run/onboarding/onboarding-certrenew.md` | Cloud Run Onboarding 自动化流程设计 |
| `gcp/cloud-run/onboarding/onboarding-desing.md` | Cloud Run Onboarding 自动化设计方案：mTLS 证书续期 |
| `gcp/cloud-run/run-flow.md` | **1. 问题分析** |
| `gcp/cloud-run/schedule-job-trigger-cloud-run.md` | Cloud Schedule 触发 Cloud Run |
| `gcp/cloud-run/serverless-vpc-access.md` | **📌 什么是 Serverless VPC Access？** |
| `gcp/cloud-run/serverless.md` | Google Cloud Serverless VPC Access 详解 |
| `gcp/cloud-run/vpcaccess-viewer.md` | GCP IAM 角色详解：roles/vpcaccess.viewer |
| `gcp/gce/gcp-cloud-run.md` | Google Cloud Run 快速入门 |

### GCP General Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `Control-and-Compliance/docs/gcp-resilience.md` | 1. 基础设施层面 |
| `gcp/README.md` | GCP (Google Cloud Platform) |
| `gcp/asm/3-add-mesh.md` | 在现有 PSC NEG 架构上引入 Cloud Service Mesh（Master Project） |
| `gcp/asm/3-thinking.md` | 1. 中文翻译 |
| `gcp/asm/3.md` | 跨项目 PSC NEG 实现方案 |
| `gcp/asm/Evaluation-istio-http.md` | Istio 架构下应用端口自定义评估报告 (Evaluation-istio-http) |
| `gcp/asm/ServiceEntry.md` | summary |
| `gcp/asm/asm-2.md` | Todo: |
| `gcp/asm/asm-explorer.md` | Asm Explorer |
| `gcp/asm/asm-flow.md` | 架构全景图 |
| `gcp/asm/asm-last-config.md` | Current 架构 |
| `gcp/asm/asm-last.md` | Istio mTLS + Gateway TLS Termination 深度解析 |
| `gcp/asm/asm.md` | Compare ASM in cluster control plane and google-managed control plane |
| `gcp/asm/authori-and-peer-eng.md` | AuthorizationPolicy And PeerAuthentication In Google Managed Service Mesh |
| `gcp/asm/authorizationPolicy-and-Peerauthentication.md` | summary |
| `gcp/asm/cdr.md` | CDR (Client Data Repository) 详解 |
| `gcp/asm/cloud-service-mesh-control-gpt.md` | Google Cloud Service Mesh 控制面设计 |
| `gcp/asm/cloud-service-mesh-control.md` | Cloud Service Mesh (ASM) 精细化流量与权限控制指南 |
| `gcp/asm/cloud-service-mesh-eng.md` | 多租户 GKE 平台 Google Cloud Service Mesh 配置指南 |
| `gcp/asm/cloud-service-mesh.md` | Google Cloud Service Mesh Setup Guide for Multi-Tenant GKE Platform |
| `gcp/asm/crd.md` | CRD (Custom Resource Definition) 详解 |
| `gcp/asm/cross-project-mesh.md` | 跨项目 PSC 结合 Cloud Service Mesh 架构部署指南 |
| `gcp/asm/debug-istio.md` | Istio 疑难问题 Debug 最佳实践指南 (How to Debug Istio Issues) |
| `gcp/asm/diagram/README.md` | Istio Flow Diagrams — 目录索引 |
| `gcp/asm/expose-mesh.md` | Expose Mesh |
| `gcp/asm/git-log-analysis-2026-W10-W11.md` | Git Log Analysis Report (Last Week) |
| `gcp/asm/git-log-analysis-2026-W12-W13.md` | Git Log Analysis Report (2026-W12 ~ W13) |
| `gcp/asm/gloo/Ambient.md` | 💡 核心概念理解：Ambient 意味着“隐形化”和“分离化” |
| `gcp/asm/gloo/Gloo-setup.md` | q |
| `gcp/asm/gloo/cross-project-gloo-mesh.md` | Cross-Project 架构下 Gloo Mesh 替换 ASM 方案探索 |
| `gcp/asm/gloo/cross-project-gloo.md` | Cross-Project Gloo 方案 |
| `gcp/asm/gloo/gloo-ambient-mesh-minimax.md` | Gloo Mesh Enterprise Ambient Mode Installation Guide on GKE |
| `gcp/asm/gloo/gloo-concepts.md` | Gloo Mesh Enterprise 核心概念与选型指南 (2026版) |
| `gcp/asm/gloo/gloo-flow.md` | Istio vs Gloo Enterprise：GKE 流量 & 加密 Flow 对比 |
| `gcp/asm/gloo/gloo-sidecar.md` | 1. 标准场景：Gloo Gateway (Edge) 作为 API 网关 |
| `gcp/asm/gloo/step-by-step-gloo.md` | End-to-End Guide: Installing Gloo Mesh Enterprise on GKE |
| `gcp/asm/gloo/waypoint.md` | Waypoint 详解：Ambient 模式下的 L7 策略执行器 |
| `gcp/asm/istio-context.md` | Istio Context Path 与 Request Path 一致性最佳实践 |
| `gcp/asm/istio-egress/README.md` | istioyaml |
| `gcp/asm/istio-egress/istio-egress-squid.md` | GKE Private Cluster 中基于 Istio Egress Gateway + Squid 的 SaaS 出站方案 |
| `gcp/asm/istio-egress/istio-egress.md` | GKE Private Cluster 中基于 Istio Egress Gateway 的 SaaS 出站控制方案 |
| `gcp/asm/kilo-minimax-cross-project-mesh.md` | 跨项目 PSC 结合 Cloud Service Mesh 实现方案 |
| `gcp/asm/master-project-setup-mesh.md` | Master Project Setup: Cloud Service Mesh (CSM) for Cross-Project Tenant Conne... |
| `gcp/asm/mcs.md` | summary |
| `gcp/asm/node-pool-manage-claude.md` | GKE Node Pool Management：生产级最佳实践 |
| `gcp/asm/node-pool-management.md` | Master Project: GKE Node Pool Management（架构视角） |
| `gcp/asm/qwen-cross-project-mesh.md` | 跨项目 PSC 结合 Cloud Service Mesh 实现方案 |
| `gcp/asm/trace-istio-and-export.md` | !/usr/bin/env bash |
| `gcp/asm/trace-istio.md` | 仅追踪（不导出 YAML） |
| `gcp/asm/verify-istio-setup.md` | !/bin/bash |
| `gcp/cloud-armor/Cloud-armor-for-api-design.md` | 流程分析与验证 |
| `gcp/cloud-armor/cloud-armor-address-group.md` | 使用地址组实现 GCP Cloud Armor 的可扩展 IP 管理 |
| `gcp/cloud-armor/cloud-armor-change.md` | summary |
| `gcp/cloud-armor/cloud-armor-header.md` | 你可能还需要重新指定该规则的其他参数，如 --expression 或 --src-ip-ranges |
| `gcp/cloud-armor/cloud-armor-ip-limition.md` | Cloud Armor Ip Limition |
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
| `gcp/cloud-armor/dedicated-armor/glb-api-cloudarmor-qwen-eng.md` | GCP GLB API-Level Cloud Armor Isolation Solution Analysis and Implementation ... |
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
| `gcp/cloud-armor/path-priority.md` | Summary |
| `gcp/cloud-armor/rate_based_ban.md` | Rate-based ban |
| `gcp/cloud-armor/summary-ban.md` | Q |
| `gcp/cross-project/3-enhance.md` | 目录 |
| `gcp/cross-project/3-figma.md` | 跨项目 PSC NEG 方案 Figma / FigJam 视觉化脚本 |
| `gcp/cross-project/3.md` | 跨项目 PSC NEG 实现方案 |
| `gcp/cross-project/4.md` | Cross Project External Entry in Tenant Project 方案 |
| `gcp/cross-project/about-wildcard-depth.md` | 泛域名证书（Wildcard Certificate）匹配深度解析 |
| `gcp/cross-project/cross-domain-fqdn.md` | 1. Tenant 工程：域名的真正“主人” |
| `gcp/cross-project/cross-mig.md` | gcloud 操作及错误信息 |
| `gcp/cross-project/cross-process-zonal-neg.md` | Shared VPC 跨项目 Internal HTTPS LB 绑定 Backend 可行性分析 |
| `gcp/cross-project/cross-project-binding-backend.md` | cross success |
| `gcp/cross-project/cross-project-sre-enhance.md` | Cross-Project PSC NEG 最终方案 SRE 监控需求增强版 |
| `gcp/cross-project/cross-project-sre-summary.md` | Cross-Project PSC NEG 架构 — SRE 对接与监控需求总结 |
| `gcp/cross-project/cross-project-sre.md` | Cross-Project PSC NEG 架构 - SRE 监控需求 |
| `gcp/cross-project/cross-project-success-one.md` | 你的架构现状与需求梳理报告 |
| `gcp/cross-project/cross-project-success-three.md` | 跨项目 PSC NEG 实现方案 |
| `gcp/cross-project/cross-project-success-two.md` | !/bin/bash |
| `gcp/cross-project/cross-project-three-add.md` | ↑ 必须带完整路径，指向 Host Project 的 subnet |
| `gcp/cross-project/explorer-2-0-fqdn.md` | Explorer 2.0: FQDN, SAN, URLMap, and Nginx Simplification |
| `gcp/cross-project/psc-firewall-qwen.md` | Cross Project PSC Firewall 完整指南（增强版） |
| `gcp/cross-project/psc-firewall-summary.md` | PSC Firewall Summary |
| `gcp/cross-project/psc-firewall.md` | Cross Project PSC Firewall 分析 |
| `gcp/cross-project/psc-ingres-gw.md` | Cross Project PSC + Ingress Gateway / Nginx / Service Mesh 探索 |
| `gcp/gce/How-to-get-project-number.md` | **一、如何获取一个 GCP 项目的** |
| `gcp/gce/application-credentials-error.md` | 步骤一：创建服务账号和下载密钥文件 |
| `gcp/gce/cross-vpc-instance.md` | Claude |
| `gcp/gce/filter-firewall.md` | Filter Firewall |
| `gcp/gce/firewall-hit.md` | How to list firewall-rules |
| `gcp/gce/flow-fr-lb-mig.md` | Flow Fr Lb Mig |
| `gcp/gce/gce-instance-log.md` | 实现 Nginx 日志映射到 Google Cloud Log Explorer 的步骤 |
| `gcp/gce/gcloud-sheet.md` | get-iam-policy |
| `gcp/gce/gcp-balance.md` | Gcp Balance |
| `gcp/gce/gcp-cloud-five-tuple.md` | 五元组的组成 |
| `gcp/gce/gcp-encrypt.md` | Gemini |
| `gcp/gce/gcp-glb.md` | Gcp Glb |
| `gcp/gce/gcp-machine-type.md` | summary |
| `gcp/gce/gcp-master-cluster-nodepool.md` | Summary |
| `gcp/gce/gcp-nat-route.md` | how to verify cloud nat ip address |
| `gcp/gce/gcp-sink.md` | 谷歌云 Firestore 中的 Sink 概念 |
| `gcp/gce/gcp-uig-with-mig.md` | GCP UIG vs MIG 深度对比指南 |
| `gcp/gce/gcp-upgrade-and-high-availablility.md` | summary |
| `gcp/gce/gcr.md` | migrate gcr to ar |
| `gcp/gce/google-api.md` | 第一部分：理解 `private.googleapis.com` 和 `restricted.googleapis.com` |
| `gcp/gce/group.md` | 1. 使用 gcloud 命令行工具 |
| `gcp/gce/healthcheck-calude.md` | 查看后端服务状态 |
| `gcp/gce/healthcheck-delete.md` | 删除 backend service |
| `gcp/gce/healthcheck.md` | 创建资源顺序及命令 |
| `gcp/gce/install-gcloud-mac.md` | Install Gcloud Mac |
| `gcp/gce/instance-groups.md` | 自动化脚本 |
| `gcp/gce/instance-uptime.md` | !/bin/bash |
| `gcp/gce/ip-range.md` | Cluster 1 |
| `gcp/gce/lb-health-mig.md` | flow diagram |
| `gcp/gce/mcg.md` | Reference |
| `gcp/gce/merged-scripts.md` | Shell Scripts Collection |
| `gcp/gce/namedports.md` | How to edit port |
| `gcp/gce/rolling/merged-scripts.md` | Shell Scripts Collection |
| `gcp/gce/route-gw.md` | GCP 路由基础概念及与 VPC、实例关系 |
| `gcp/gce/scopes.md` | 将一个Service Account加入到我的一个GROUP里面 我这个对应的GROUP有对应下的Secret的权限 |
| `gcp/gce/static-ip.md` | 1. 创建静态外部IP地址 |
| `gcp/gce/streaming.md` | 1. **基础知识点** |
| `gcp/gce/troubleshoot-google-api.md` | Troubleshoot Google Api |
| `gcp/gce/verify-mig-status.md` | verify-mig-status.sh |
| `gcp/gcp-cloud-build/gcp-cloud-build-concepts.md` | GCP Cloud Build: Comprehensive Concepts Guide |
| `gcp/gcp-infor/README.md` | GCP-Infor - GCP Platform Information Tools |
| `gcp/gcp-infor/REVIEW-REPORT.md` | GCP-Infor Scripts Review Report |
| `gcp/gcp-infor/assistant/README.md` | GCP Infor (Linux) - Notes + Verification Helpers |
| `gcp/gcp-infor/assistant/merged-scripts.md` | Shell Scripts Collection |
| `gcp/gcp-infor/gcpfetch-README.md` | GCPFetch - GCP Platform Information Tool |
| `gcp/gcp-infor/merged-scripts.md` | Shell Scripts Collection |
| `gcp/glb/glb+psc.md` | 问题分析 |
| `gcp/glb/glb-retry-timeout.md` | GCP GLB 多层架构超时与重试机制设计指南 |
| `gcp/glb/glb.md` | 背景与问题分析 |
| `gcp/glb/target-https-proxies.md` | GCP Target HTTPS Proxies 证书追加操作指南 |
| `gcp/gsutil.md` | Gsutil |
| `gcp/housekeep/instance-delete.md` | GCP 资源清理指南 |
| `gcp/ingress/backend-servie.md` | Backend Servie |
| `gcp/ingress/control.md` | K8s Ingress Controller 工作流深度解析 |
| `gcp/ingress/ingress-control-400-claude.md` | Ingress Controller 配置体系深度解析 |
| `gcp/ingress/ingress-control-400-qwen.md` | Deep Dive into Ingress Controller Configuration System |
| `gcp/ingress/ingress-control-400.md` | ChatGPT |
| `gcp/ingress/ingress-control-log.md` | Ingress Control Log |
| `gcp/ingress/ingress-control-mindmap.md` | Ingress Control Mindmap |
| `gcp/ingress/ingress-control-performance.md` | Ingress Control Performance |
| `gcp/ingress/ingress-control-resouce-ingress.md` | Ingress配置示例 |
| `gcp/ingress/ingress-control-resouce-sort.md` | How to Using ingress export https |
| `gcp/ingress/ingress-control.md` | 你的规则和后端配置 |
| `gcp/ingress/ingress-log-debug.md` | summary my question |
| `gcp/ingress/ingress-reference.md` | Ingress Reference |
| `gcp/ingress/ingress-snippet.md` | Ingress Annotations 完整配置解析 |
| `gcp/ingress/lex-presentation.md` | GKE Gateway 演示文稿 |
| `gcp/lb/backend-service.md` | Backend Service in GCP |
| `gcp/lb/backend-timeout.md` | **应用负载均衡器** |
| `gcp/lb/compare-forward-peering.md` | 概念阐述 |
| `gcp/lb/global-https.md` | summary |
| `gcp/lb/lb-created.md` | Lb Created |
| `gcp/lb/lb-lb.md` | Lb Lb |
| `gcp/lb/lb-parameter.md` | 1. 为什么 Backend Service 会出现 oauth2ClientId |
| `gcp/lb/lb-poc-from-mig.md` | lb-poc-from-mig.sh |
| `gcp/lb/lb.md` | other |
| `gcp/lb/merged-scripts.md` | Shell Scripts Collection |
| `gcp/lb/multi-ilb-bs.md` | Multiple Internal Load Balancers Binding to Single Backend Service |
| `gcp/migrate-gcp/Kiro-pop-plan.md` | **POP Platform Migration to Federated GCP - Comprehensive Plan** |
| `gcp/migrate-gcp/argocd.md` | 核心理念：GitOps |
| `gcp/migrate-gcp/gemini-pop-plan.md` | Design |
| `gcp/migrate-gcp/get-ns-info-fast.md` | !/bin/bash |
| `gcp/migrate-gcp/get-ns-information.md` | !/bin/bash |
| `gcp/migrate-gcp/get-ns-stats-qwen.md` | !/opt/homebrew/bin/bash |
| `gcp/migrate-gcp/get-ns-stats.md` | !/opt/homebrew/bin/bash |
| `gcp/migrate-gcp/migrate-concepts.md` | POP平台迁移核心概念脑图 |
| `gcp/migrate-gcp/migrate-gcp-redis.md` | GCP Redis 实例跨项目迁移方案 |
| `gcp/migrate-gcp/migrate-secret-manage/README.md` | GCP Secret Manager 跨项目迁移工具 |
| `gcp/migrate-gcp/migrate-secret-manage/merged-scripts.md` | Shell Scripts Collection |
| `gcp/migrate-gcp/migrate-secret-manage/migrate-gcp-secret-manager.md` | Migrate Gcp Secret Manager |
| `gcp/migrate-gcp/migrate-secret-manage/secret-manage-chatgpt.md` | Secret Manage Chatgpt |
| `gcp/migrate-gcp/migration-info/namespace-lex-enhanced-stats-20250830_192844.md` | Enhanced Kubernetes Namespace Statistics Report |
| `gcp/migrate-gcp/migration-info/namespace-lex-enhanced-stats-20250830_200322.md` | Enhanced Kubernetes Namespace Statistics Report |
| `gcp/migrate-gcp/migration-info/namespace-lex-gemini-stats-20250830_192818.md` | Gemini Kubernetes Namespace Report |
| `gcp/migrate-gcp/plan.md` | 权重切分示例（基于 Kong upstream target 或 Gateway API BackendRef weight） |
| `gcp/migrate-gcp/pop-migrate/COMPATIBILITY.md` | 工具兼容性说明 |
| `gcp/migrate-gcp/pop-migrate/README.md` | GKE 跨项目 Namespace 迁移工具 |
| `gcp/migrate-gcp/pop-migrate/docs/EXAMPLES.md` | 使用示例 |
| `gcp/migrate-gcp/pop-migrate/docs/TROUBLESHOOTING.md` | 故障排除指南 |
| `gcp/misc/Capacity-Planning-and-Backup-Strategy.md` | **问题总结** |
| `gcp/misc/High-availability.md` | current configure |
| `gcp/misc/Resilience.md` | GCP API 平台弹性增强规划 |
| `gcp/misc/appd-ppt.md` | Appd Ppt |
| `gcp/misc/big-memory-cpu.md` | Analysis |
| `gcp/misc/big-memroy-cpu-analysis.md` | Grok |
| `gcp/misc/multi.md` | Multi |
| `gcp/misc/resiliences-gpt.md` | Google Cloud Platform API 平台配置增强与优化 |
| `gcp/pub-sub/StreamingPull.md` | A |
| `gcp/pub-sub/TPS.md` | My Summary |
| `gcp/pub-sub/Testing.md` | **✅ 说明要点** |
| `gcp/pub-sub/ack.md` | ✅ Your Architecture: Acknowledge on Receipt (At-Most-Once Delivery) |
| `gcp/pub-sub/block-enhance.md` | Result |
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
| `gcp/pub-sub/flow-and-concept.md` | Flow And Concept |
| `gcp/pub-sub/io.md` | Io |
| `gcp/pub-sub/open_streaming_pulls.md` | **✅** |
| `gcp/pub-sub/pub-sub-base.md` | 1. IAM 角色与权限 |
| `gcp/pub-sub/pub-sub-block.md` | gemini |
| `gcp/pub-sub/pub-sub-cmek/merged-scripts.md` | Shell Scripts Collection |
| `gcp/pub-sub/pub-sub-cmek/pub-sub-alma.md` | Cloud Scheduler & Pub/Sub CMEK 集成全解析 / The Ultimate Guide to Pub/Sub CMEK wit... |
| `gcp/pub-sub/pub-sub-cmek/pub-sub-cmek-kms-summary.md` | Pub/Sub CMEK & Cloud Scheduler `NOT_FOUND` Error Summary |
| `gcp/pub-sub/pub-sub-cmek/schedule-job-cmek-kms.md` | Cloud Scheduler + CMEK 完全排障手册 / Complete Troubleshooting Guide |
| `gcp/pub-sub/pub-sub-cmek/schedule-job-cmek.md` | Cloud Scheduler & CMEK: Resume Failure Analysis / Cloud Scheduler 与 CMEK：恢复失败分析 |
| `gcp/pub-sub/pub-sub-cmek/schedule-job-resume.md` | Cloud Scheduler Resume Failure: NOT_FOUND / Cloud Scheduler 恢复失败：资源未找到 |
| `gcp/pub-sub/pub-sub-cmek/scheduler-jobs-describe.md` | **📄 示例命令** |
| `gcp/pub-sub/pub-sub-command.md` | command |
| `gcp/pub-sub/pub-sub-max-delivery-attempts.md` | Summary |
| `gcp/pub-sub/pub-sub-push-pull-to-ack-delta.md` | 1. Publish to Ack Delta |
| `gcp/pub-sub/pub-sub-queue-command.md` | summary |
| `gcp/pub-sub/pub-sub-schedule-time.md` | **✅ GCP Pub/Sub 的两种订阅模式** |
| `gcp/pub-sub/pub-sub-subscription-create.md` | Pub/Sub Subscription 创建失败：`request is prohibited by organization's policy` 问题分析 |
| `gcp/pub-sub/pub-sub-subscriptions.md` | ackDeadlineSecends |
| `gcp/pub-sub/pub-sub-summary-english.md` | Q |
| `gcp/pub-sub/pub-sub-summary.md` | Q |
| `gcp/pub-sub/pub-sub-testing-commond.md` | Pub Sub Testing Commond |
| `gcp/pub-sub/pub-sub-thread.md` | Pub Sub Thread |
| `gcp/pub-sub/pub-sub-timeout.md` | **✅ ⏱️** |
| `gcp/pub-sub/pub-sub-ttl.md` | Pub Sub Ttl |
| `gcp/pub-sub/testing-value-verify.md` | Pub/Sub 消费者性能评估验证 |
| `gcp/pub-sub/testing-value.md` | summary |
| `gcp/pub-sub/wiki.md` | **📡 Google Pub/Sub PULL 模式 + GKE StreamingPull 架构说明** |
| `gcp/recaptcha/recaptcha.md` | reCAPTCHA resilient design |
| `gcp/secret-manage/add-secret-binging.md` | 前提条件 |
| `gcp/secret-manage/add-secret-manage-private.md` | 交互式使用 |
| `gcp/secret-manage/echo-n.md` | **🔍 区别解释：** |
| `gcp/secret-manage/gcp-secret-base64.md` | Gcp Secret Base64 |
| `gcp/secret-manage/gcp-secret-manage-rotate.md` | ChatGPT |
| `gcp/secret-manage/gcp-secret-manage-version.md` | GCP Secret Manager 版本化与幂等性管理方案 |
| `gcp/secret-manage/gcp-secret.md` | secret get-iam-policy ${secret} \ |
| `gcp/secret-manage/housekeep-secret.md` | !/bin/bash |
| `gcp/secret-manage/list-secret/BUGFIX-NOTES.md` | Bug 修复说明 |
| `gcp/secret-manage/list-secret/CHANGELOG.md` | 更新日志 |
| `gcp/secret-manage/list-secret/IMPLEMENTATION-COMPARISON.md` | 实现方案对比分析 |
| `gcp/secret-manage/list-secret/PERFORMANCE-OPTIMIZATION.md` | 性能优化指南 |
| `gcp/secret-manage/list-secret/QUICK-REFERENCE.md` | GCP Secret Manager 审计脚本 - 快速参考 |
| `gcp/secret-manage/list-secret/README-PARALLEL.md` | 并行版本使用指南 |
| `gcp/secret-manage/list-secret/README-audit-scripts.md` | GCP Secret Manager 权限审计脚本 |
| `gcp/secret-manage/list-secret/README.md` | GCP Secret Manager 审计脚本集合 |
| `gcp/secret-manage/list-secret/VERSION-COMPARISON.md` | 版本对比指南 |
| `gcp/secret-manage/list-secret/chatgpt-list.md` | !/bin/bash |
| `gcp/secret-manage/list-secret/merge-secret-data.md` | jq script to merge secret info and IAM policy |
| `gcp/secret-manage/list-secret/merged-scripts.md` | Shell Scripts Collection |
| `gcp/secret-manage/list-secret/summary.md` | Summary |
| `gcp/secret-manage/onboarding.md` | Create SM GCP group |
| `gcp/secret-manage/pod-start.md` | 流程说明 |
| `gcp/secret-manage/secret-manage-file.md` | q |
| `gcp/secret-manage/secret-manage-grpc-netty-shaded.md` | ChatGPT |
| `gcp/secret-manage/secret-mongo.md` | simple flow |
| `gcp/secret-manage/secret-todo.md` | 问题描述 |
| `gcp/storage/cloud-bak.md` | Using products in GCP to back up resources |
| `gcp/storage/cloud-storage-transfer-service.md` | 创建第一个转移作业 |
| `gcp/tools/filter-jq.md` | 提取的信息 |
| `gcp/tools/git.md` | !/bin/bash |
| `knowledge/docs/aws-gcp.md` | Aws Gcp |
| `redis/docs/gcp-redis.md` | 在Google工程中实现Redis多用户或多租户管理的解决方案 |
| `redis/docs/get-gcp-redis.md` | GCP Redis 信息获取脚本 |
| `swark-output/docs/gcp-secret-log.md` | Swark Log File |
| `swark-output/docs/gcp-secret-manage_diagram.md` | Usage Instructions |

### GCP Service Account / IAM Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `Control-and-Compliance/docs/GKE-safe-en.md` | Outstanding findings summary |
| `Control-and-Compliance/docs/GKE-safe.md` | **✅ 应对该问题的建议清单（适用于 GKE）** |
| `OPA-Gatekeeper/constraint-explorers/disallowed-repos.md` | K8sDisallowedRepos 禁止特定镜像仓库 |
| `ai/concept/USAGE.md` | 知识库检索工具使用指南 |
| `ali/docs/imagepullsecret-sa.md` | Why Service Accounts Have imagePullSecrets Automatically Added |
| `api-service/docs/EAPI-PAPI-SAPI.md` | **常见 API 分类** |
| `dns/docs/create-private-access-usage.md` | Create Private Access Usage |
| `dns/docs/dnsrecord-add-script-usage.md` | GCP Cloud DNS 记录批量添加脚本使用说明 |
| `dns/docs/dnsrecord-del-script-usage.md` | GCP Cloud DNS 记录批量删除脚本使用说明 |
| `dns/docs/private-access/create-claude-usage-eng.md` | create-claude.sh Usage Documentation |
| `dns/docs/private-access/create-claude-usage.md` | create-claude.sh 使用文档 |
| `dns/docs/private-access/create-private-access-usage.md` | create-private-access.sh 使用文档 |
| `gcp/cloud-run/cloud-run-sa-active.md` | 错误分析：这不是认证问题，而是网络问题 |
| `gcp/cloud-run/cloud-run-sa.md` | ChatGPT |
| `gcp/cloud-run/gcp-project-server-level-sa.md` | GCP IAM 权限层级和查询 |
| `gcp/cost/gke_cluster_resource_usage.md` | Gke Cluster Resource Usage |
| `gcp/gce/gcp-instance-satisfilesPzs.md` | Gcp Instance Satisfilespzs |
| `gcp/gce/use-service-account-impersonation.md` | Google服务账户模拟 |
| `gcp/migrate-gcp/pop-migrate/docs/USAGE.md` | 使用指南 |
| `gcp/psa-psc/Hub-Spoke.md` | Hub-Spoke 网络架构指南 |
| `gcp/psa-psc/Kiro-psc-CloudSQL.md` | Google Cloud Private Service Connect (PSC) 实施指南 - Cloud SQL 场景 |
| `gcp/psa-psc/gemini-psc.md` | 使用 Private Service Connect (PSC) 连接跨项目 VPC |
| `gcp/psa-psc/psa-vpc.md` | **🧩 一、配置整体含义** |
| `gcp/psa-psc/psa-with-psc.md` | GCP 私有网络连接：PSA 与 PSC 完整指南 |
| `gcp/psa-psc/psa.md` | Psa |
| `gcp/psa-psc/psc-Redis.md` | Google Cloud Private Service Connect (PSC) 实施指南 - Redis 场景 |
| `gcp/psa-psc/psc-bard.md` | Summary ask question |
| `gcp/psa-psc/psc-concept.md` | Private Service Connect (PSC) 概念指南 |
| `gcp/psa-psc/psc-connect-consumer.md` | verify |
| `gcp/psa-psc/psc-cross-region.md` | PSC 跨 Region 连接：平台 Consumer 访问不同 Region 的 Producer |
| `gcp/psa-psc/psc-psa-compare.md` | **🧭 一、PSA 与 PSC 的核心定位对比** |
| `gcp/psa-psc/psc-sql/README.md` | GKE 通过 PSC 连接 Cloud SQL 示例 |
| `gcp/psa-psc/psc-thinking.md` | 🟢 核心架构总结：PSC Service Attachment 在 Shared VPC 中的落地 |
| `gcp/psa-psc/psc-with-vpc-peering-quota-cost.md` | PSC vs VPC Peering - Quota 与 Cost 对比指南 |
| `gcp/psa-psc/psc.md` | Conditions |
| `gcp/psa-psc/service-attachment-region.md` | 深度探索：Service Attachment 的暴露方式与前提条件 |
| `gcp/psa-psc/temp.md` | Temp |
| `gcp/psa-psc/vpc-peering.md` | VPC Peering 概念指南 |
| `gcp/psa-psc/why-not-using-vpc-peering.md` | 1. 致命缺陷一：IP 地址重叠（Overlap）的终极噩梦 |
| `gcp/psa-psc/why-using-psc.md` | gemini |
| `gcp/pub-sub/cross-project-pub-sub-debug-sa.md` | Cross-Project Pub/Sub + GKE Workload Identity Debug Guide |
| `gcp/pub-sub/pub-sub-cmek/USAGE.md` | GCP Pub/Sub CMEK Manager - Usage Guide |
| `gcp/pub-sub/pub-sub-message.md` | Maybe Flow |
| `gcp/pub-sub/unacked-message-by-region.md` | ✅ 核心架构：收到消息立即 ACK（At-Most-Once Delivery） |
| `gcp/sa/SA-Control-and-Compliance.md` | TODO |
| `gcp/sa/active-serviceaccount.md` | 问题分析 |
| `gcp/sa/gcp-sa-housekeep.md` | GCP Service Account Key Housekeeping: Best Practices and Automation |
| `gcp/sa/gcp-sa-json-quota.md` | Handling GCP Service Account Key Quota Errors |
| `gcp/sa/gke-ksa-iam-authentication-flow.md` | GKE KSA IAM Based Authentication Flow |
| `gcp/sa/iam-based-authentication.md` | IAM Based Authentication 详解 |
| `gcp/sa/iam-service-account.md` | 3. 检查 SA 自身的 IAM 策略（用于 Workload Identity） |
| `gcp/sa/merged-scripts.md` | Shell Scripts Collection |
| `gcp/sa/service-agent.md` | GCP 中的 Service Agent（服务代理）理解指南 |
| `gcp/sa/serviceaccountuser-securityreviewer.md` | GCP Roles: roles/iam.serviceAccountUser and roles/iam.securityReviewer |
| `gcp/sa/verify-another-proj-sa.md` | !/bin/bash |
| `gcp/sa/verify-cross-project-pub-sub-sa.md` | verify-cross-project-pub-sub-sa.sh |
| `gcp/sa/verify-gcp-sa.md` | !/bin/bash |
| `gcp/sa/verify-iam-based-authentication-enhance.md` | !/bin/bash |
| `gcp/sa/verify-sa-iam-based-authentication.md` | summary |
| `gcp/secret-manage/about-deleted-sa-secret-manage.md` | About Deleted Sa Secret Manage |
| `gcp/secret-manage/add-sa-to-manager.md` | secret get-iam-policy ${secret} \ |
| `gcp/secret-manage/java-examples/USAGE.md` | Usage Guide - GCP Secret Manager Java Demo |
| `gcp/secret-manage/sa-secret-manage.md` | summmary |
| `gcp/secret-manage/verify-sa.md` | summary and flow |
| `gke/docs/gke-sa-gcp-sa-addbinding-claude.md` | Q |
| `gke/docs/gke-sa-gcp-sa-addbinding.md` | 整体流程概述 |
| `java/java-scan/examples/usage-examples.md` | 使用示例 |
| `k8s/custom-liveness/explore-startprobe/POD_FUN_USAGE_GUIDE.md` | Pod Health Check Library - Usage Guide |
| `k8s/docs/gke-sa.md` | summary |
| `k8s/images/k8s-image-replace-usage.md` | K8s 镜像替换脚本使用说明 |
| `linux/docs/SAN.md` | San |
| `merge-usage.md` | Merge Shell Scripts 使用说明 |
| `nginx/docs/nginx-safe.md` | 启用 HSTS |
| `pipeline/docs/osapath.md` | 主要概念 |
| `report/docs/bq-sa-query.md` | Q |
| `safe/README.md` | Safe (Security) 知识库 |
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
| `safe/cwe/cwe-523.md` | 一、修复方法 |
| `safe/cwe/cwe-550.md` | **一、常见泄露点** |
| `safe/cwe/cwe-650.md` | Q |
| `safe/cwe/cwe-798.md` | CWE-798: Use of Hard-coded Credentials (使用硬编码凭证) |
| `safe/cwe/how-to-fix.md` | fix Flow |
| `safe/cwe/nginx-header-violation-cwe-16.md` | 1. 什么是 X-Content-Type-Options 头？ |
| `safe/cwe/nginx-header-x-frame-options.md` | Nginx X-Frame-Options 安全评估：全局 DENY 与 API 级 SAMEORIGIN 的权衡 |
| `safe/cwe/pro-security-status.md` | **🧩 一、使用** |
| `safe/cwe/violations-24.04-libpam.md` | **🧩 问题分析** |
| `safe/cyberflows/Trivy.md` | **📦 Trivy 介绍与应用场景指南** |
| `safe/cyberflows/cage-scan.md` | Cage Scan |
| `safe/cyberflows/checkmarx.md` | Checkmarx 扫描报告在 Pipeline 中的含义 |
| `safe/cyberflows/cyberflows-flow.md` | Cyberflows Flow |
| `safe/cyberflows/dast.md` | 将动态应用安全测试（DAST）集成到CI/CD流程的综合指南 |
| `safe/cyberflows/foss-explorer.md` | Q |
| `safe/cyberflows/foss.md` | Summary |
| `safe/cyberflows/sbom.md` | **✅ 使用前提** |
| `safe/cyberflows/sonar.md` | Sonar |
| `safe/docs/Encrypted.md` | Encrypted |
| `safe/docs/GKE-26.md` | **✅ GKE 审计日志包括哪些内容？** |
| `safe/docs/Periodic-container-scanning.md` | 🛡️ GCP GKE 运行时容器镜像定期扫描方案 |
| `safe/docs/analyze-showcerts.md` | q |
| `safe/docs/api_security_tips.md` | 12 Tips for API Security |
| `safe/docs/appd-violation.md` | Q |
| `safe/docs/auth.md` | AuthN (身份验证) 详细流程 |
| `safe/docs/auths-method.md` | GCP 平台应用认证授权方法详解 (auths-method) |
| `safe/docs/compare-sls-local-and-user.md` | !/bin/bash |
| `safe/docs/crl2pkcs7.md` | 1. `-certfile` |
| `safe/docs/curl-pem-request.md` | 1. 禁用系统默认的CA文件和路径 |
| `safe/docs/cve.md` | Cve |
| `safe/docs/cyber-with-cloud-armor.md` | AI Studio |
| `safe/docs/cyberflows.md` | **背景信息** |
| `safe/docs/dbp.md` | about nginx.conf |
| `safe/docs/encypy-asymmetric.md` | **1. 对称密钥 (Symmetric Key)** |
| `safe/docs/flow-ssl.md` | SSL/TLS 认证和CA证书的信任位置 |
| `safe/docs/gcp-safe-api-enhance.md` | **❗ 当前方式存在的问题（Pipeline + Script + gcloud/gsutil）** |
| `safe/docs/gke-policy-control.md` | **🧩** |
| `safe/docs/gke-psa.md` | **✅ 怎么表述这类情况（可用于文档或审计回复）** |
| `safe/docs/glb-open-80-ports.md` | **🌐 1.** |
| `safe/docs/ib2b-eb2b.md` | **🔐 iB2B vs eB2B 说明** |
| `safe/docs/iq-scan.md` | Iq Scan |
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
| `safe/docs/ubuntu.md` | 其他你原本Dockerfile中的指令 |
| `safe/docs/url-block.md` | Url Block |
| `safe/docs/verify-ssl.md` | Verify Ssl |
| `safe/docs/waf-rule-troubleshooting.md` | ChatGPT |
| `safe/docs/waf-rule.md` | 规则详细信息 |
| `safe/docs/waf-troubleshooting.md` | ChatGPT |
| `safe/docs/waf.md` | Waf |
| `safe/docs/wget-ssl.md` | 要获取一个HTTPS网站的证书链，你可以使用以下几种方法： |
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
| `safe/gcp-safe/example-usage.md` | !/bin/bash |
| `safe/gcp-safe/gcp-lb-cipher.md` | 在GCP中验证负载均衡器Cipher Suite的方法 |
| `safe/gcp-safe/gcp-role.md` | 步骤1：创建自定义角色 |
| `safe/gcp-safe/key-keyring.md` | **问题分析** |
| `safe/gcp-safe/kms-en-and-de.md` | 架构实践：GCP 中使用独立 KMS 项目进行跨项目加解密 |
| `safe/gcp-safe/kms-en-de.md` | **🧩 一、核心原理说明** |
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
| `safe/how-to-fix-violation/quick-reference.md` | Container Security Quick Reference |
| `safe/how-to-fix-violation/remediation-strategies.md` | Container Security Remediation Strategies |
| `safe/responsibilities/package-depend.md` | Sonar scan cover |
| `safe/responsibilities/snoar-code-coverage.md` | Snoar Code Coverage |
| `safe/wiz/Summary-TODO.md` | summary |
| `safe/wiz/gemini-wiz.md` | Wiz 在 GCP 与 GKE 环境中的全面应用指南 |
| `safe/wiz/wiz-base-information.md` | **Wiz 在 GCP / GKE 中的工作原理概览** |
| `safe/wiz/wiz-grok.md` | 基本的知识 |
| `shell-script/scripts/replace-usage.md` | 批量替换脚本使用说明 |
| `skills/gke-basics/references/client-library-usage.md` | GKE Client Libraries |
| `skills/gke-basics/references/iac-usage.md` | GKE Infrastructure as Code |
| `skills/gke-basics/references/mcp-usage.md` | GKE MCP Server Usage |
| `skills/google-cloud-recipe-networking-observability/references/mcp-usage.md` | MCP Server Usage Reference |
| `sql/docs/duckdb-usage.md` | DuckDB 使用指南 |
| `ssl/compare-san-sni.md` | SAN vs SNI：区别、使用场景与验证方法 |
| `ssl/docs/Sans.md` | **问题分析** |
| `ssl/why-san.md` | Why SAN |

### GCP/mTLS Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `English/docs/mTLS.md` | Mtls |
| `gcp/asm/asm-mtls-explorer.md` | ASM mTLS 在 Pod 间通信的深度探索与实践 |
| `gcp/mtls/CA.md` | What is CA |
| `gcp/mtls/Glb-Client-Authentication.md` | Client Authentication 和 Server TLS Policy 详解 |
| `gcp/mtls/MTLS-TODO.md` | Mtls Todo |
| `gcp/mtls/Onboard.md` | summay step |
| `gcp/mtls/SSLVerifyDepth.md` | **🔐 GCP Trust Config 简述** |
| `gcp/mtls/apply-create-static-ip.md` | --network-tier=PREMIUM # 全局IP通常需要 Premium Tier，这是默认值，可以省略 |
| `gcp/mtls/chatgpt-nginx.md` | 禁止特定 Content-Type |
| `gcp/mtls/compare-ca-intermediate.md` | summary |
| `gcp/mtls/flow-mtls-log.md` | ... 其他 http 配置 ... |
| `gcp/mtls/gcp-certificate-manager.md` | !/bin/bash |
| `gcp/mtls/get_cert_fingerprint.md` | !/bin/bash |
| `gcp/mtls/glb-mtls-nginx.md` | ... 其他 location 块... |
| `gcp/mtls/glb-mtls.md` | summary |
| `gcp/mtls/glb-verify-curl.md` | curl请求分析 |
| `gcp/mtls/glb-verify.md` | gemini |
| `gcp/mtls/how-to-get-ca-int.md` | method 1 |
| `gcp/mtls/https-glb-pass-client.md` | 方案 1: 使用 HTTP 头部传递证书信息 |
| `gcp/mtls/intermediate-ca.md` | Intermediate Ca |
| `gcp/mtls/merged-scripts.md` | Shell Scripts Collection |
| `gcp/mtls/migrate-cloud-armor.md` | create rule |
| `gcp/mtls/migrate-nginx.md` | !/opt/homebrew/bin/bash |
| `gcp/mtls/mtls-cloud-armor.md` | Mtls Cloud Armor |
| `gcp/mtls/mtls-cn.md` | Mtls Cn |
| `gcp/mtls/mtls-dropin-session.md` | Mtls Dropin Session |
| `gcp/mtls/mtls-nginx.md` | 整理后的流程图 |
| `gcp/mtls/mtls-table.md` | Mtls Table |
| `gcp/mtls/mtls-test/generate-ca-and-verify-ca.md` | !/opt/homebrew/bin/bash |
| `gcp/mtls/mtls-test/sre-mtls-monitor.md` | SRE Monitoring Strategy for TCP MTLS to HTTPS MTLS GLB Migration |
| `gcp/mtls/mtls-test/test-case.md` | Test Case Design for Migrating GCP TCP MTLS to HTTPS MTLS GLB |
| `gcp/mtls/mtls-verify.md` | summary |
| `gcp/mtls/multiple-mtls.md` | 验证多个mTLS认证的可行性 |
| `gcp/mtls/named.md` | Named |
| `gcp/mtls/onboarding-automation.md` | summary |
| `gcp/mtls/onboarding-ca-with-fingerprint.md` | CA证书Onboarding流程（含指纹存储） |
| `gcp/mtls/onboarding-ca.md` | summary Flow |
| `gcp/mtls/onboarding-verify.md` | Q |
| `gcp/mtls/onboarding-whitelist.md` | 将本地的 white_list.txt 上传到指定的 GCS 存储桶 |
| `gcp/mtls/renew.md` | **✅ 场景背景** |
| `gcp/mtls/ssl-certificates.md` | core concepts |
| `gcp/mtls/trust-config/add-trust-config.md` | 移除多余的换行符和空格 |
| `gcp/mtls/trust-config/allowlistedCertificates.md` | 示例: 计算 PEM 格式根证书的 SHA-256 指纹 |
| `gcp/mtls/trust-config/analyze-trust-configs.md` | !/bin/bash |
| `gcp/mtls/trust-config/explorer-update-cert.md` | Trust Config 证书更新与存储策略探索 (Explorer Update Cert) |
| `gcp/mtls/trust-config/gcloud-certificate-update-with-import.md` | Q |
| `gcp/mtls/trust-config/mtls-cert-policy.md` | Mtls Cert Policy |
| `gcp/mtls/trust-config/mtls-key-eng.md` | Detailed Explanation of mTLS Verification and Private Key Validation (mtls-ke... |
| `gcp/mtls/trust-config/mtls-key.md` | mTLS 验证与私钥校验详解 (mtls-key.md) |
| `gcp/mtls/trust-config/mtls-trustconfig-nginx.md` | Mtls Trustconfig Nginx |
| `gcp/mtls/trust-config/multi-user-trust-config.md` | Trust Config for GCP Certificate Manager |
| `gcp/mtls/trust-config/trust-config-backup.md` | Trust Config Backup |
| `gcp/mtls/trust-config/trust-config-flow.md` | GCP Trust Config 证书验证流程详解 |
| `gcp/mtls/trust-config/trust-config-limit.md` | Trust Config Limit |
| `gcp/mtls/trust-config/trust-config-lock.md` | Trust Config Lock |
| `gcp/mtls/trust-config/trustconfig-multip-ca.md` | trust config Version Control |
| `gcp/mtls/trust-config/verify-trust-configs-guide.md` | Trust Config 验证脚本使用指南 |
| `gcp/mtls/verify-user-certificate.md` | Summary |
| `gcp/mtls/why-need-white-list.md` | Why Need White List |
| `linux/docs/mtls.md` | Mtls |
| `nginx/docs/nginx-mtls.md` | 1. MTLS 认证所需的文件 |

### GCS Bucket Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `cost/gcp-cost/buckets-archive.md` | summary |
| `cost/gcp-cost/buckets.md` | Cloud Logging 日志存储桶 (Log Buckets) 详解 |
| `gcp/buckets/QUICKREF.md` | GCS Bucket 批量创建 - 快速参考 |
| `gcp/buckets/README.md` | GCS Bucket 批量创建脚本使用说明 |
| `gcp/buckets/VERIFY-README.md` | GCS Bucket 验证脚本使用说明 |
| `gcp/buckets/buckets-add-binging-sa.md` | Chatgpt |
| `gcp/buckets/buckets-des.md` | Buckets Des |
| `gcp/buckets/buckets-migrate.md` | Google Cloud Storage Buckets 配置迁移方案 |
| `gcp/buckets/buckets-role.md` | GKE Service Account and Bucket Access Configuration Guide |
| `gcp/buckets/buckets-version-lifecycle.md` | 1. 启用版本控制 |
| `gcp/buckets/compare-lifecycle-file.md` | 下载文件的两个不同版本 |
| `gcp/buckets/mer.md` | Shell Scripts Collection |
| `gcp/buckets/merged-scripts.md` | Shell Scripts Collection |
| `gcp/buckets/verify-buckets-iam.md` | GCS Bucket IAM 绑定验证脚本 |
| `gcp/cloud-run/cloud-run-buckets.md` | Cloud Run 访问 Cloud Storage Buckets |
| `nginx/docs/server_names-hash_bucket_size.md` | Understanding nginx server_names_hash_bucket_size |
| `python/docs/buckets-bigquery.md` | 可以在这里添加重试逻辑或发送警报 |
| `report/docs/buckets-to-Bigquery.md` | 数据加载方式 |

### GKE Gateway Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gateway/README.md` | Gateway |
| `gateway/docs/Design.md` | Claude |
| `gateway/docs/README.md` | Gateway 知识库 |
| `gateway/docs/gke-gateway-quota.md` | 1. 核心限制：子网（Subnet）与地址空间 |
| `gateway/no-gateway/Gateway-API-allowedRoutes.md` | **✅ 为什么不支持 podSelector？** |
| `gateway/no-gateway/HealthCheckPolicy.md` | 1. 问题分析 |
| `gateway/no-gateway/TODO.md` | Todo |
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
| `gateway/no-gateway/verify-gateway-enhance.md` | !/usr/bin/env bash |
| `gateway/no-gateway/verify-gke-gateway.md` | GKE Internal Gateway 验证脚本 |
| `gateway/no-gateway/version-control/core-concepts-en.md` | Core Concepts: Version Control and Smooth Switching in GKE Gateway API No-Gat... |
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
| `gcp/asm/gloo/step-by-step-gloo-gateway-minimax.md` | End-to-End Gloo Gateway Installation on GKE |
| `gcp/cross-project/cross-project-gateway/Rt-psc-connect-master-project-gateway.md` | Project A Kong Runtime 通过 PSC Endpoint 访问 Project B Master GKE Gateway |
| `gcp/cross-project/cross-project-gateway/cross-project-san.md` | Cross-Project PSC FQDN with SAN |
| `gcp/cross-project/cross-project-gateway/rt-cross-project-fqdn.md` | 问题分析 |
| `gcp/cross-project/cross-project-gateway/rt-psc-gateway.md` | 🔍 Review 总评 |
| `gcp/ingress/gateway-httproute.md` | claude |
| `gcp/ingress/gateway-lex.md` | GKE Gateway: HTTPRoute 流量分配与健康检查核心解析 |
| `gcp/ingress/ingress-with-gateway.md` | Verify step |
| `k8s/networkpolicy/explorer-gateway-networkpolicy.md` | Gateway-Namespace 跨 Namespace 网络策略配置分析 |
| `k8s/networkpolicy/gateway-ns-cross-ns.md` | Gateway-namespace 跨 namespace 网络策略配置分析 |

### General Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `AGENTS.md` | GKE & GCP Architecture Technical Partner (Architectrue) |
| `CODEBUDDY.md` | Linux & Cloud Infrastructure Expert Prompt |
| `COMPLETION_SUMMARY_2026-01-25.md` | Knowledge Base Consolidation & Enhancement - Completion Summary |
| `Control-and-Compliance/README.md` | Control and Compliance |
| `Control-and-Compliance/docs/README.md` | Control and Compliance 知识库 |
| `Control-and-Compliance/docs/risk.md` | Risk |
| `English/README.md` | English 知识库 |
| `English/docs/apply-testing.md` | Apply Testing |
| `English/docs/charge-mode-eg.md` | Charge Mode Eg |
| `English/docs/egress-ip.md` | Egress Ip |
| `English/docs/goals.md` | Goals |
| `English/docs/holiday.md` | 外企常见假期回复模板 |
| `English/docs/mail-quota-dm.md` | Mail Quota Dm |
| `English/docs/mail.md` | Mail |
| `English/docs/performance.md` | work performance |
| `English/docs/policy.md` | Policy |
| `English/docs/retrospective.md` | Retrospective |
| `English/docs/spot.md` | Summary: |
| `English/docs/strengh.md` | Strengh |
| `English/docs/talk-architecture.md` | Architecture Talk Guide - English & Chinese对照 |
| `English/docs/thanks.md` | Thanks |
| `Ghostty/README.md` | Ghostty |
| `Ghostty/docs/README.md` | Ghostty 知识库 |
| `Ghostty/docs/config.md` | Config |
| `Ghostty/docs/simple.md` | The syntax is "key = value". The whitespace around the |
| `Infographic-with-mermaid.md` | Infographic vs. Mermaid：深度解析与实战指南 |
| `OPA-Gatekeeper/README.md` | OPA Gatekeeper |
| `OPA-Gatekeeper/constraint-explorers/README.md` | Gatekeeper Constraint 探索索引 |
| `OPA-Gatekeeper/constraint-explorers/allowed-repos.md` | K8sAllowedRepos 限制容器镜像仓库 |
| `OPA-Gatekeeper/constraint-explorers/block-loadbalancer-services.md` | K8sBlockLoadBalancer 禁止 LoadBalancer Service |
| `OPA-Gatekeeper/constraint-explorers/block-nodeport-services.md` | K8sBlockNodePort 禁止 NodePort Service |
| `OPA-Gatekeeper/constraint-explorers/https-only.md` | K8sHttpsOnly 强制 Ingress 仅允许 HTTPS |
| `OPA-Gatekeeper/constraint-explorers/immutable-fields.md` | K8sImmutableFields 禁止修改特定字段（自定义模板） |
| `OPA-Gatekeeper/constraint-explorers/replica-limits.md` | K8sReplicaLimits 限制 Deployment/ReplicaSet 副本数 |
| `OPA-Gatekeeper/constraint-explorers/required-probes.md` | K8sRequiredProbes 强制健康检查探针 |
| `OPA-Gatekeeper/constraint-explorers/storageclass.md` | K8sStorageClass 限制 PersistentVolumeClaim 存储类 |
| `OPA-Gatekeeper/docs/Dynamic-context-aware-policy.md` | Dynamic Context-Aware Policy Guide |
| `OPA-Gatekeeper/docs/Join-Fleet.md` | MEMBERSHIP_NAME 通常可以与集群名称一致 |
| `OPA-Gatekeeper/docs/create.md` | 1. Architecture Logic Design |
| `OPA-Gatekeeper/docs/gatekeeper-best-practices-resource-mapping.md` | Gatekeeper Best Practices - Resource Mapping Guide |
| `OPA-Gatekeeper/docs/gatekeeper-concepts.md` | Gatekeeper Concepts |
| `OPA-Gatekeeper/docs/how-to-control-template.md` | How to Control Templates (ConstraintTemplate Management) |
| `OPA-Gatekeeper/docs/how-to-using-gpc.md` | GKE Policy Controller Usage Guide |
| `OPA-Gatekeeper/docs/multi-tenant-resource-quota-exception-handling.md` | Multi-Tenant Resource Quota Exception Handling |
| `OPA-Gatekeeper/docs/opa-design.md` | OPA Gatekeeper Multi-Tenant Design |
| `OPA-Gatekeeper/docs/policy-layer.md` | OPA Gatekeeper 策略分层评估报告 |
| `OPA-Gatekeeper/docs/rego-concept.md` | 1. 什么是 Rego？ |
| `OPA-Gatekeeper/docs/setup-log.md` | Todos |
| `OPA-Gatekeeper/docs/single-cluster-opa-gatekeeper-setup.md` | GKE 单集群安装开源 OPA Gatekeeper 操作文档 |
| `OPA-Gatekeeper/docs/step-by-step-install.md` | GKE Policy Controller Installation Guide |
| `OPA-Gatekeeper/docs/why-using-open-gatekeeper.md` | GKE Open-Source OPA Gatekeeper 单集群与多集群支持分析 |
| `OpenAI/README.md` | OpenAI |
| `OpenAI/docs/English.md` | English |
| `OpenAI/docs/README.md` | OpenAI & AI Tools 知识库 |
| `OpenAI/docs/Share.md` | How Can AI Transform Our Work? |
| `OpenAI/docs/Verifying-GLB.md` | Verifying GCP Global Load Balancer mTLS Configuration Prior to DNS Cutover |
| `OpenAI/docs/chattts.md` | 1. 准备环境 |
| `OpenAI/docs/claude-cloudflare.md` | Cloudflare 自身不要代理（容易被反爬虫判断）所以 Cloudflare 域名必须直连 |
| `OpenAI/docs/concept.md` | 温度（Temperature） |
| `OpenAI/docs/pic.md` | Pic |
| `OpenAI/docs/trans.md` | Le Xu |
| `OpenAI/docs/web-development.md` | Web Development |
| `README.md` | Knowledge |
| `React/README.md` | React |
| `React/docs/README.md` | React Docker Application |
| `React/docs/README_knowledge.md` | React 知识库 |
| `React/scripts/merged-scripts.md` | Shell Scripts Collection |
| `Rego/README.md` | Rego |
| `Rego/docs/Join-Fleet.md` | 加入 Fleet - GKE Policy Controller 启用前提 |
| `Rego/docs/create.md` | 1. Architecture Logic Design |
| `Rego/docs/rego-concept.md` | 2. 在 GKE 中的核心场景：Gatekeeper |
| `Users/README.md` | Users |
| `ai/README.md` | AI |
| `ai/concept/INSTALL.md` | 安装指南 |
| `ai/concept/PROJECT_SUMMARY.md` | 本地知识库智能检索系统 - 项目总结 |
| `ai/concept/QUICKSTART.md` | 快速开始指南 |
| `ai/concept/README.md` | 本地知识库智能检索系统 |
| `ai/docs/README.md` | AI (Artificial Intelligence) 知识库 |
| `ai/docs/agent-tree.md` | Agent Tree |
| `ai/docs/ai-agent.md` | AI Agent的基本原理 |
| `ai/docs/debug-ollama.md` | 最简单命令 |
| `ai/docs/llam-server.md` | how to upgrade it |
| `ai/docs/ollama.md` | Ollama |
| `ai/docs/prompt.md` | Linux & Cloud Infrastructure Expert Prompt |
| `anaylize-git-log-2026-02-23.md` | Git Log Analysis Report (Last Week) |
| `apache/README.md` | Apache |
| `apache/docs/README.md` | Apache 知识库 |
| `apache/docs/airflow-dag.md` | 定义任务执行的函数 |
| `apache/docs/airflow.md` | Airflow 的核心功能 |
| `apache/docs/harbor-airflow.md` | Harbor Airflow |
| `apache/docs/mindmap.md` | Apache Knowledge Mind Map |
| `api-service/README.md` | API Service 知识库 |
| `api-service/docs/Architecture-Stream-API.md` | Summary |
| `api-service/docs/Requirement.md` | Requirement |
| `api-service/docs/SSE.md` | 🌐 **SSE = Server-Sent Events** |
| `api-service/docs/Stream-Events-apis.md` | Stream Events API 学习与实践文档 |
| `api-service/docs/api-ChatGPT.md` | **问题分析** |
| `api-service/docs/api-kiro.md` | API 平台架构深度解析与演进策略 |
| `api-service/docs/api.md` | API 平台演进：从标准 API 到多模式服务支持 |
| `apple/README.md` | 🍎 Apple Notes CLI 工具 |
| `aws/README.md` | AWS |
| `aws/docs/README.md` | AWS (Amazon Web Services) 知识库 |
| `aws/docs/aws-cli.md` | 使用AWS CLI验证S3中的数据 |
| `coff.md` | **咖啡饮品比例表** |
| `concept/README.md` | Concept |
| `concept/docs/README.md` | Concept 知识库 |
| `concept/docs/model-driven-thinking.md` | 从命令驱动到模型驱动 |
| `concept/docs/rfc.md` | Request for Comments (RFC) |
| `docs/README.md` | Docs |
| `draw/README.md` | Draw 知识库 |
| `draw/docs/ca-onboarding-flow.md` | CA证书Onboarding流程 |
| `draw/docs/onboarding.md` | Onboarding |
| `draw/docs/url.md` | Url |
| `egress/README.md` | Egress 知识库 |
| `egress/docs/Explore-egress.md` | Explore Egress |
| `egress/docs/Readme.md` | Egress 知识库 |
| `egress/docs/architecture-design.md` | GKE Egress Proxy 架构设计 |
| `egress/docs/blue-coat.md` | Blue Coat |
| `egress/docs/explorer-egress-flow-enhance.md` | GKE Egress 代理流程图集合 (增强版) |
| `egress/docs/explorer-egress-flow.md` | GKE Egress 代理流程图集合 |
| `egress/docs/feasibility-analysis.md` | 可行性分析报告 |
| `egress/docs/implementation-guide.md` | 实施指南 |
| `egress/docs/quick-start.md` | 快速开始指南 |
| `egress/docs/squid-configs.md` | Squid 代理配置文件 |
| `explorer-knowledge.md` | Personal Knowledge Base Management & Search Strategies |
| `firestore/README.md` | Firestore 知识库 |
| `firestore/docs/firestore-compare.md` | 方法一：使用Cloud Functions进行变更监听 |
| `firestore/docs/firestore.md` | Firestore 备份 |
| `firestore/docs/merged-scripts.md` | Shell Scripts Collection |
| `firestore/docs/tenant-design.md` | Firestore 多项目数据集成与分析架构设计 |
| `firestore/docs/tenant.md` | summary |
| `firestore/scripts/README.md` | Firestore 脚本工具集 |
| `firestore/scripts/merged-scripts.md` | Shell Scripts Collection |
| `flow/README.md` | Flow |
| `flow/docs/How-to-expose-gemini.md` | 在GCP中隔离VPC间通过虚拟机实例暴露内部服务的方案分析 |
| `flow/docs/How-to-expose-grok.md` | **1. Understanding the Network Setup** |
| `flow/docs/How-to-expose-internalservice.md` | Chatgp |
| `flow/docs/How-to-get-route.md` | summary |
| `flow/docs/L7-L4-request-flow.md` | 回包流程 |
| `flow/docs/README.md` | Flow (Network Flow) 知识库 |
| `flow/docs/external-flow.md` | describe |
| `flow/docs/internal-flow.md` | Internal Flow |
| `flow/docs/pub-ingress-flow.md` | Nginx与Squid代理配置分析 |
| `game/README.md` | Game |
| `gante.md` | **解释** |
| `gif/README.md` | GIF 知识库 |
| `gif/docs/shio-code.md` | 使用说明 |
| `git-analysis-weekly.md` | Weekly Git Log Analysis |
| `go/README.md` | Go (Golang) 知识库 |
| `go/docs/DELIVERY-CHECKLIST.md` | 交付清单 |
| `go/docs/INDEX.md` | Golang 平台配置适配 - 文档索引 |
| `go/docs/INTEGRATION-GUIDE.md` | Golang 应用集成平台配置 - 快速指南 |
| `go/docs/PROJECT-STRUCTURE.md` | 项目结构说明 |
| `go/docs/QUICK-START.md` | 5 分钟快速开始 |
| `go/docs/SOLUTION-COMPARISON.md` | 方案对比：独立 ConfigMap vs 共享 ConfigMap |
| `go/docs/SOLUTION-SUMMARY.md` | Golang 应用适配平台 ConfigMap - 解决方案总结 |
| `go/docs/platform-configmap-adapter.md` | Golang 应用适配平台 ConfigMap 配置指南 |
| `groovy/README.md` | Groovy 知识库 |
| `groovy/docs/jenkins-agent.md` | Jenkins的主要功能 |
| `groovy/docs/p2l.md` | 图片信息提取和流程梳理 - 以p2l为核心 |
| `groovy/docs/read-each-line.md` | object or string |
| `groovy/docs/simple-groovy.md` | understand class and method |
| `howgit/README.md` | How Git |
| `howgit/docs/How-to-Verify-request.md` | Q |
| `howgit/docs/README.md` | Git 知识库 |
| `howgit/docs/Remote-cover-local.md` | 通过远程分支完全覆盖本地文件 |
| `howgit/docs/bfg.md` | BFG Repo-Cleaner 详解 |
| `howgit/docs/chemistry.md` | Chemistry |
| `howgit/docs/delete-fork.md` | Delete Fork |
| `howgit/docs/fork.md` | Fork |
| `howgit/docs/git-blame.md` | Git Blame 与代码格式化：保持历史清晰的工程实践 |
| `howgit/docs/git-error.md` | fatal: Not possible to fast-forward, aborting. |
| `howgit/docs/git-flow.md` | Git Flow |
| `howgit/docs/git-log.md` | !/bin/bash |
| `howgit/docs/git-rebase.md` | 方法一：使用 `git rebase`（保持线性历史） |
| `howgit/docs/git-sheet.md` | the default when no argument is provided |
| `howgit/docs/housekeep-branch.md` | !/bin/bash |
| `howgit/docs/how-git-working.md` | How Git Working |
| `howgit/docs/how-to-ignore.md` | Git 忽略指南：保护敏感文件不被推送到仓库 |
| `howgit/docs/ignore.md` | 在项目根目录创建或编辑 .gitignore 文件 |
| `howgit/docs/list-git-repo.md` | 1. 使用 GitHub 的 Web 界面 |
| `howgit/docs/master-conver-local.md` | Master Conver Local |
| `howgit/docs/merged-to-master.md` | 处理"大改动 + main 已前进 + 有 violation"场景的实战方案 |
| `howgit/docs/region-search.md` | **1. 问题的深度分析** |
| `howgit/docs/rm-DS_store.md` | 搜索当前目录中所有与 .DS_Store 相关的文件 |
| `howgit/docs/shell-env.md` | 提取环境变量的前两个字符 |
| `howgit/docs/vim.md` | 解决方案 |
| `howgit/docs/vsix-down.md` | Vsix Down |
| `howgit/docs/webhook.md` | Webhook 功能 |
| `iPad/README.md` | iPad |
| `iPad/docs/playgrouds.md` | claude |
| `icap/README.md` | ICAP (Internet Content Adaptation Protocol) |
| `icap/icap.md` | 替换为你的 ICAP 服务器地址 |
| `ios/README.md` | iOS 知识库 |
| `ios/ocr/Reade.md` | Xcode 里 Product → Run 可以直接跑 |
| `ios/ocr/nas-ocr.md` | !/usr/bin/env bash |
| `ios/speak-screen.md` | ✅ **开启 Speak Screen（英文系统）的方法** |
| `ish/README.md` | ISH 知识库 |
| `ish/docs/a-shell.md` | A Shell |
| `ish/docs/update-oh-zsh.md` | 1. Manual Update |
| `knowledge/README.md` | Knowledge 知识库 |
| `knowledge/docs/akamai.md` | Akamai的主要产品和服务 |
| `knowledge/docs/data.md` | Data |
| `knowledge/docs/endpoint.md` | 区分API的URL和Endpoints的URL |
| `knowledge/docs/gante.md` | Mermaid Gantt Chart Syntax Guide |
| `knowledge/docs/system-design-tradeoffs.md` | System design |
| `macos/README.md` | macOS |
| `macos/caffeinate.md` | caffeinate |
| `macos/docs/btop.md` | 🧭 一、启动与基本界面 |
| `macos/docs/install-fonts.md` | 一、先给结论（最推荐的写法） |
| `macos/docs/my-macos-power-requirement.md` | Mac mini 电源管理方案 |
| `macos/docs/open-file.md` | 第一步：安装 `duti` |
| `macos/docs/rg.md` | **ripgrep（rg）使用手册（macOS）** |
| `macos/docs/socat.md` | **✅ 方案 1：使用** |
| `macos/docs/swith-bash.md` | **问题分析** |
| `macos/explorer-macos-power.md` | Mac mini 后台任务电源管理方案 |
| `mail/README.md` | Mail |
| `mail/telnet-mail.md` | Telnet Mail |
| `markdown.md` | Mermaid语法示例： |
| `merged-file.md` | Merged File |
| `nas/README.md` | NAS 知识库 |
| `nas/docs/back-nas.md` | Docker 容器备份与迁移指南 (k3s) |
| `nas/docs/start-qnap-k3s.md` | Summary |
| `nas/docs/success-summary.md` | nas enable local registry |
| `nba/README.md` | NBA 知识库 |
| `neofetch.md` | Neofetch |
| `node/README.md` | Node.js 知识库 |
| `node/docs/INDEX.md` | Node.js 平台配置适配 - 文档索引 |
| `node/docs/QUICK-START.md` | 5 分钟快速开始 |
| `node/docs/SOLUTION-COMPARISON.md` | 方案对比：独立 ConfigMap vs 共享 ConfigMap |
| `node/docs/SOLUTION-SUMMARY.md` | Node.js 应用适配平台 ConfigMap - 解决方案总结 |
| `node/docs/node-https.md` | **1. 问题分析** |
| `npm/README.md` | npm |
| `npm/install.md` | 问题分析 |
| `ob/README.md` | OB 知识库 |
| `ob/docs/egress-summary.md` | Egress Summary |
| `ob/docs/ob-public-egress-ChatGPT.md` | Q |
| `ob/docs/ob-public-egress-claude.md` | Public Egress 管理优化方案 |
| `ob/docs/ob-public-egress-gemini.md` | GCP API Platform: Public Egress Onboarding 架构演进文档 |
| `ob/docs/ob-public-egress.md` | GCP API Platform Public Egress Onboarding Enhancement |
| `ob/docs/squid-conf.md` | Configuration Explanation |
| `ob/egress-dynamic/squid-egress-mult.md` | Dynamic Squid Egress Multi-Proxy Solution: Domain-Based Routing |
| `other/README.md` | Other 知识库 |
| `other/docs/F5.md` | F5 GTM and LTM |
| `other/docs/jira-update.md` | 1. 获取 Jira API Token |
| `other/docs/mermaid.md` | 流程图 |
| `other/docs/vscode.md` | Vscode |
| `other/docs/枚举.md` | Java |
| `ppt/README.md` | PPT (PowerPoint) 知识库 |
| `ppt/docs/appd-bt.md` | 200个Business Transaction的限制 |
| `ppt/docs/appd-why-custom.md` | 1. **业务隔离和独立性** |
| `ppt/docs/appd.md` | one page |
| `ppt/docs/recaptcha.md` | one page |
| `ppt/docs/svg.md` | SVG的主要特点： |
| `pr-knowledge-mindmap.md` | Pull Request 知识点分析 |
| `prompt/English-prompt.md` | English Prompt |
| `prompt/README.md` | Prompt 知识库 |
| `prompt/architectrue-cn.md` | GKE & GCP 架构技术合作伙伴提示 |
| `prompt/architectrue.md` | Architectrue |
| `prompt/enhance-prompt.md` | 目标： |
| `prompt/jira-pm.md` | Jira Pm |
| `prompt/sre-prompt.md` | Sre Prompt |
| `push.md` | 使用远程 Ollama |
| `redis/README.md` | Redis 知识库 |
| `redis/docs/In-transit-encryption.md` | **✅** |
| `redis/docs/redis-con.md` | Q |
| `redis/docs/redis-connect-chatgpt.md` | Redis Connect Chatgpt |
| `redis/docs/redis-connect-claude.md` | GKE 跨工程访问 Redis 的实现方案 |
| `redis/docs/redis-connect-gemini.md` | How to Connect to Redis Across GCP Projects from GKE |
| `redis/docs/redis.md` | Redis (Memorystore) 的 Resilience 配置 (详细展开) |
| `report/README.md` | Report 知识库 |
| `report/docs/3.md` | Coze |
| `report/docs/Google-LookStudio.md` | **1. 数据源层优化（BigQuery → 缓存/汇总层）** |
| `report/docs/JQL-Search.md` | 示例 JQL 查询：过去 7 天内更新的、状态为 "In Progress" 的 issue |
| `report/docs/JQL.md` | Jql |
| `report/docs/architecture-design.md` | Summary |
| `report/docs/calc.md` | 使用GitHub Pages发布静态页面 |
| `report/docs/charge-model.md` | Charge Model |
| `report/docs/class.md` | Class |
| `report/docs/config-hpa.md` | summary |
| `report/docs/cross-pro-groq.md` | Cross Pro Groq |
| `report/docs/cross-pro.md` | 步骤 |
| `report/docs/enhance-apppy.md` | Q |
| `report/docs/get-hpa.md` | summary |
| `report/docs/id.md` | !/bin/bash |
| `report/docs/improvements-summary.md` | 时区应用改进总结 |
| `report/docs/jira-get-page.md` | Build JQL query |
| `report/docs/jira-jql.md` | Q |
| `report/docs/looker-studio-bak.md` | Looker Studio 的版本控制功能 |
| `report/docs/looker-studio-filter.md` | 步骤1：创建时间过滤器 |
| `report/docs/looker-studio.md` | Google Data Studio 和数据分析关键概念 |
| `report/docs/lookerstudio-data-credentials.md` | Lookerstudio Data Credentials |
| `report/docs/merge.md` | 示例 |
| `report/docs/ob.md` | ob value |
| `report/docs/offering.md` | **🧭 Understand Our Offering — Discussion & Debate** |
| `report/docs/quota-requirement.md` | 1. Quota监控和预警机制 |
| `report/docs/report-vs-dashboard.md` | Google Looker Studio |
| `report/docs/sink-and-coll.md` | ask |
| `report/docs/special-case-data.md` | **一、问题本质（先定性）** |
| `report/docs/studio-time.md` | Studio Time |
| `shell-script/README.md` | Shell Script 知识库 |
| `shell-script/docs/cheatsheets-bash.md` | !/bin/bash |
| `shell-script/docs/count-time.md` | time count |
| `shell-script/docs/default-value.md` | !/bin/bash |
| `shell-script/docs/fun.md` | 函数的定义和调用 |
| `shell-script/docs/retry.md` | !/bin/bash |
| `shell-script/docs/source.md` | !/usr/bin/env bash |
| `shell-script/scripts/merged-scripts.md` | Shell Scripts Collection |
| `shortcut/README.md` | Shortcut 知识库 |
| `shortcut/docs/merged-scripts.md` | Shell Scripts Collection |
| `shortcut/docs/trans.md` | Trans |
| `squid/README.md` | Squid 知识库 |
| `squid/docs/Squid-client_request_buffer_max_size.md` | client_request_buffer_max_size 详细解释 |
| `squid/docs/codebuddy-enhance.md` | GKE API平台大文件上传与Token认证优化方案 |
| `squid/docs/gemini-enhance-squid.md` | GKE API 平台大文件上传与认证时效性优化方案 |
| `squid/docs/squid-adaptation_send_client_ip.md` | Squid Adaptation Send Client Ip |
| `squid/docs/squid-conf.md` | logformat squid %ts.%03tu %6tr %>a %Ss/%03>Hs %<st %rm %ru %[un %Sh/%<a %mt |
| `squid/docs/squid-enhance.md` | My Enhance Plan |
| `squid/docs/squid-l4-explorer.md` | Squid 能否作为 L4 代理使用？深度探索 |
| `squid/docs/squid-l4-or-l7.md` | Squid 是 L4 还是 L7 代理？ |
| `squid/docs/squid-log.md` | Q |
| `squid/docs/squid-request_body_passthrough.md` | 验证方法 |
| `squid/docs/squid-start.md` | error |
| `squid/docs/squid-upload.md` | Linux buffer |
| `sre/README.md` | SRE (Site Reliability Engineering) 知识库 |
| `sre/docs/How-to-reply.md` | How To Reply |
| `sre/docs/debug-header.md` | 深度排查：`X-AIBANG-client-secret` Header 丢失问题 |
| `sre/docs/flow-debug-gemini.md` | gemini |
| `sre/docs/flow-debug.md` | Claude |
| `sre/docs/how-to-debug-flow.md` | GCP云服务API 502错误全链路调试指南 |
| `sre/docs/how-to-debug.md` | 云服务API 502错误调试思路与方法论 |
| `sre/docs/llm-knowledge-workspace-for-sre.md` | LLM Knowledge Workspace 方案 |
| `sre/docs/reply-template.md` | API 平台对外 Support 话术规范 v1.0 |
| `strings-antigravity.md` | 分析 Antigravity.app：使用 strings 命令进行静态分析指南 |
| `swark-output/README.md` | Swark Output 知识库 |
| `swark-output/docs/2025-08-13__09-53-05__diagram.md` | Usage Instructions |
| `swark-output/docs/2025-08-13__09-53-05__log.md` | Swark Log File |
| `task/README.md` | Task |
| `task/todo.md` | **2. 使用 Markdown 兼容的 PlantUML 渲染工具** |
| `terrafrom/README.md` | Terraform |
| `terrafrom/docs/README.md` | Terraform 知识库 |
| `terrafrom/docs/backend-servie.md` | 其他配置... |
| `terrafrom/docs/person-group.md.md` | **✅ 问题总结** |
| `terrafrom/docs/terrafrom-stat.md` | **🔄 第一部分：Terraform 为什么要轮询操作状态？** |
| `test/README.md` | Test 知识库 |
| `test/docs/BDD.md` | src/test/resources/features/order_processing.feature |
| `test/docs/Why.md` | 服务迁移中CNAME切换后证书报错问题分析 |
| `test/docs/api-testing-types.md` | 9 Types of API Testing |
| `test/docs/compare-stress-performance-testing.md` | 压力测试 (Stress Testing) vs 性能测试 (Performance Testing) 深度比较 |
| `test/docs/explorer-ai-test.md` | AI 辅助测试探索指南 |
| `test/docs/find.md` | Find |
| `test/docs/hey.md` | hey: GKE 环境下的 HTTP 负载测试工具 |
| `test/docs/improve-api-performance.md` | Top 5 Common Ways to Improve API Performance |
| `test/docs/regression.md` | **Regression Testing 相关概念和要求** |
| `test/docs/stress.md` | 获取 Service IP (推荐) |
| `test/dr-instance/README.md` | GCE Disaster Recovery Validation |
| `test/dr-instance/dr-mig-zone-test.md` | **✅ 目标** |
| `test/dr-instance/explorer-dr-instance.md` | Claude |
| `trans/README.md` | Translation App |
| `vim/README.md` | Vim |
| `vim/docs/README.md` | Vim 知识库 |
| `vim/docs/vim-copy.md` | Vim Copy |
| `vim/docs/vim.md` | Vim |
| `vpn/README.md` | VPN |
| `vscode/README.md` | VSCode 知识库 |
| `vscode/plug.md` | Plug |
| `zhifubao/README.md` | 支付宝 |

### Java Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `ali/max-computer/How-to-call-maxcomputer-using-java.md` | 如何通过 Java SDK 调用 MaxCompute（最简实践） |
| `docker/docs/java-version.md` | 添加 Java 版本标签 |
| `draw/docs/Draw-Java-application.md` | Draw Java Application |
| `gcp/cloud-run/cloud-run-debug/cloud-run-java-debug.md` | GCP Cloud Run Java 超时问题调试指南 |
| `gcp/secret-manage/Java-SMS.md` | **📌 背景说明** |
| `gcp/secret-manage/flow-secret-java.md` | Java Spring 应用结合 GCP Secret Manager 的工作流 |
| `gcp/secret-manage/java-examples/README.md` | GCP Secret Manager Java Examples |
| `gcp/secret-manage/java-examples/VERIFICATION.md` | GCP Secret Manager Verification Guide |
| `gcp/secret-manage/java-examples/gcp-secret-manager-flow.md` | GCP Secret Manager Complete Flow Guide |
| `go/docs/JAVA-GOLANG-COMPARISON.md` | Java SpringBoot vs Golang 平台配置对比 |
| `go/docs/go-and-java-using-different-cm.md` | Java 和 Golang 使用独立 ConfigMap 方案 |
| `java-code/README.md` | Java Code 知识库 |
| `java-code/docs/Java-base-build.md` | Java 基础项目构建文档 |
| `java-timeout/README.md` | Timeout API Application |
| `java-timeout/java-timeout.md` | n Jav Deployment和Service来部署应用并暴露API。 |
| `java/README.md` | Java 知识库 |
| `java/build-tools/dockerbuild-maven.md` | Maven Build |
| `java/debug/debug-Java-jar.md` | Q |
| `java/debug/debug-jar.md` | Debug Guide: 如何在 GKE 中“解剖”无法启动的 JAR 包 |
| `java/debug/debug-java-pod-process.md` | Java Pod Sidecar Debug 流程文档 |
| `java/debug/debug-java-pod.md` | Debug Java Pod: Inspect Failed JAR Images with Sidecar Network-Multitool |
| `java/debug/debug-java-port.md` | Debugging Java Application Port and Health Check Issues in GKE |
| `java/debug/debug-sprint-connect.md` | 检查DNS解析 |
| `java/debug/headpdump-hprof.md` | 分析 `headpdump.hprof` 文件的方案 |
| `java/debug/java-G1GC.md` | Q |
| `java/debug/java-heapdump.md` | Key Points |
| `java/debug/java-serial.md` | **Java 17 + GKE 中 CPU=1000m 是否会使用 Serial GC？以及如何评估** |
| `java/encoding/encoding.md` | 增加 `-Dfile.encoding=UTF-8` 参数的影响 |
| `java/general/commons-io.md` | Commons Io |
| `java/general/context-path.md` | GKE Java 应用配置与调试指南 |
| `java/general/gar-version.md` | 利用制品仓库元数据管理版本信息 |
| `java/general/java-develop-language.md` | Java Application Development Methods: Identifying Spring Boot, Tomcat, and JA... |
| `java/general/java-log-level.md` | Java Application Log Level Control in Kubernetes Deployments |
| `java/general/merged-scripts.md` | Shell Scripts Collection |
| `java/general/token.md` | summary |
| `java/general/wiremock.md` | Debugging Guide: `package com.github.tomakehurst.wiremock.client does not exist` |
| `java/java-appd/anaylize.md` | 1. Init Container 的内存占用 (短暂) |
| `java/java-appd/appd-infor.md` | Stage 1: Get the Agent |
| `java/java-appd/appd-refresh-initContainer.md` | How to quick refresh node images |
| `java/java-appd/appd-sidecar.md` | ✅ 1. **Sidecar 能否直接执行 `jcmd`？取决于两个条件** |
| `java/java-appd/java-appd-cret.md` | using which cacerts to connect appdynamics |
| `java/java-appd/java-appd-gemini/README.md` | Java AppDynamics Memory Analysis Guide |
| `java/java-appd/java-appd-gemini/docker-hub-tools.md` | Docker Hub Tools for Java Memory Analysis |
| `java/java-appd/java-appd-gemini/memory-analysis-guide.md` | Memory Analysis Methodology: AppD vs Spring Boot |
| `java/java-appd/java-appd-gemini/sidecar-profiling.md` | Sidecar Profiling Strategy |
| `java/java-appd/java-appd-memory.md` | GKE Deployment 中 Java 应用与 AppDynamics 资源分析 |
| `java/java-appd/jcmd-appd.md` | 使用 JVM **Native Memory Tracking（NMT）** 精准拆分 App vs AppDynamics |
| `java/java-auth/java-application-auth.md` | Q |
| `java/java-auth/simple-https-demo/README.md` | Simple HTTPS Demo - Dual SSL Role |
| `java/java-core/Java-Process-and-Thread.md` | **📌 Java 线程内存消耗评估** |
| `java/java-core/Java-lang-OutOfMemoryError.md` | The Q |
| `java/java-core/Java-memory.md` | **📌 线程内存消耗组成：** |
| `java/java-core/java-a-call-b.md` | Java A Call B |
| `java/java-core/java-cgroup.md` | 基于cgroups v2的Java应用部署建议 (针对GCP GKE环境) |
| `java/java-core/java-ci-cd.md` | 1. **利用CI生成版本标签文件并传递给CD** |
| `java/java-core/java-define-build-docker-version.md` | 1. **在pom.xml中定义Java版本属性** |
| `java/java-core/java-eden-enhance.md` | claude |
| `java/java-core/java-encoding.md` | Q |
| `java/java-core/java-env.md` | install Java |
| `java/java-core/java-export-cert.md` | Java Export Cert |
| `java/java-core/java-gs-error.md` | 可能的原因 |
| `java/java-core/java-jdk-jre.md` | JRE vs JDK in Docker |
| `java/java-core/java-jdk-targetversion.md` | 理解JDK版本、Target Version以及Docker镜像的关系 |
| `java/java-core/java-mail-verify.md` | Java Mail Verify |
| `java/java-core/java-mail.md` | summary |
| `java/java-core/java-mule-error.md` | 我的日志有如下报错,帮我分析下如何解决和排查问题? |
| `java/java-core/java-post-memory.md` | ChatGPT |
| `java/java-core/java-post.md` | summary |
| `java/java-core/java-redis-error.md` | Debug和解决步骤 |
| `java/java-core/java-sni.md` | Summary |
| `java/java-core/java-upload.md` | Q |
| `java/java-core/java-utf-8.md` | **✅ 回答关键问题** |
| `java/java-core/java-version-define.md` | 1. **Maven 构建版本的选择** |
| `java/java-core/java-version.md` | 1. **CI/CD Pipeline 中增加标签** |
| `java/java-pom/Java-Maven-dep-debug.md` | Java Maven 依赖问题排查文档集 |
| `java/java-pom/com.github.tomakehurst.wiremock.client.md` | **一、** |
| `java/java-pom/debug-mav-cache.md` | Debugging Maven Dependency Conflicts & Version Mismatches |
| `java/java-pom/dependency-issue-checklist.md` | Java 依赖问题排查清单 |
| `java/java-pom/how-to-build-jar-cn.md` | 如何构建 JAR 文件 - Java 应用完整指南 |
| `java/java-pom/how-to-build-jar.md` | How to Build a JAR File - A Complete Guide for Java Applications |
| `java/java-pom/java-mvn-cache.md` | Maven Cache Issues in Java/Spring Boot Projects |
| `java/java-pom/java-package-missing.md` | **1️⃣ 问题分析** |
| `java/java-pom/java-pom-ci.md` | 在 CI 中根据 `pom.xml` 中的 Java 版本替换 Dockerfile 的 Java 版本 |
| `java/java-pom/java-pom.md` | **🧩 一、两种写法的核心区别** |
| `java/java-pom/parent-child-debug.md` | Parent-Child POM 调用关系调试指南 |
| `java/java-pom/parent-pom-debug-cn.md` | Parent POM 依赖版本冲突调试指南 |
| `java/java-pom/parent-pom-debug-en.md` | Parent POM Dependency Version Conflict Debugging Guide |
| `java/java-pom/parent-pom-debug.md` | Parent POM 依赖版本冲突调试指南 |
| `java/java-pom/pom-depend-cn.md` | Maven 依赖分析与多版本冲突解决方案 |
| `java/java-pom/pom-depend.md` | Maven Dependency Analysis & Multi-Version Conflict Resolution |
| `java/java-pom/troubleshooting-flowchart.md` | Java Maven 依赖问题排查流程图 |
| `java/java-pom/wiremock-dependency-troubleshooting.md` | WireMock 依赖缺失问题完整排查指南 |
| `java/java-scan/Readme.md` | Java 应用认证扫描工具 |
| `java/java-scan/auth-scanner-implementation/README.md` | Auth Scanner Implementation |
| `java/java-scan/auth-scanner-implementation/deploy-process.md` | Auth Scanner Deployment & Integration Guide |
| `java/java-scan/auth-scanner-implementation/design.md` | Java API 认证合规扫描器设计方案 |
| `java/java-scan/deployment-guide.md` | 部署指南 |
| `java/java-scan/java-code-scan.md` | 设计自动化扫描工具：确保 GKE Pod 内嵌认证逻辑 |
| `java/java-scan/project-summary.md` | Java 认证扫描工具 - 项目总结 |
| `java/java-scan/scanner-design.md` | Java 应用认证扫描工具设计方案 |
| `java/java-spring/Java-Spring-Base.md` | **📚 Java Spring 应用基础知识点汇总（面向平台工程师）** |
| `java/java-spring/Spring-Cloud-Run.md` | Summary |
| `java/java-spring/Sprint-cloud-run-claude.md` | Spring Boot Cloud Run 代理服务深度探索指南 |
| `java/java-spring/Sprint-cloud-run-gemini.md` | 深入解析 Spring Boot 代理服务的核心业务逻辑 |
| `java/scripts/merged-scripts.md` | Shell Scripts Collection |
| `java/spring/controller.md` | 理解 Spring Boot Controller：为 Kubernetes 健康检查创建 HTTP 端点 |
| `java/spring/jetty-sprintboot.md` | Jetty with nginx or tomcat |
| `java/spring/swagger.md` | Swagger 的主要组成部分 |
| `node/docs/nodejs-and-java-using-different-cm.md` | Java 和 Node.js 使用独立 ConfigMap 方案 |

### K8s Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `English/docs/gke-stable.md` | Gke Stable |
| `OPA-Gatekeeper/constraint-explorers/k8srequiredlabels.md` | K8sRequiredLabels 完整指南 |
| `OPA-Gatekeeper/docs/gke-policy-control-with-tep.md` | GKE Policy Controller Constraint Template 对比分析（修正版） |
| `OPA-Gatekeeper/docs/gke-policy-controller-requirement.md` | Gke Policy Controller Requirement |
| `OPA-Gatekeeper/docs/gke-policy-controller-with-gatekeeper.md` | GKE Policy Controller vs Standalone Gatekeeper 选型指南 |
| `OPA-Gatekeeper/docs/gke-setup-policy-controller.md` | GKE Policy Controller 完整安装与配置指南 |
| `OPA-Gatekeeper/docs/k8srequiredlabels.md` | K8sRequiredLabels 完整指南 |
| `OPA-Gatekeeper/docs/why-using-gke-policy-controller.md` | Why GKE Policy Controller — Fleet-Level Centralized Management |
| `Rego/docs/gke-policy-controller-with-gatekeeper.md` | GKE Policy Controller vs Standalone Gatekeeper 选型指南 |
| `Rego/docs/gke-setup-policy-controller.md` | GKE Policy Controller 完整安装与配置指南 |
| `ali/docs/k8s-resources.md` | !/bin/bash |
| `ali/k8s-cluster-migration/design.md` | K8s集群迁移设计文档 |
| `ali/k8s-cluster-migration/requirements.md` | K8s集群迁移需求文档 |
| `ali/k8s-cluster-migration/tasks.md` | K8s 集群迁移实施计划 |
| `ali/k8s-migration-proxy/IMPLEMENTATION.md` | Task 1 Implementation: 创建代理服务基础架构 |
| `ali/k8s-migration-proxy/IMPLEMENTATION_SUMMARY.md` | 任务2实施总结 - 灰度迁移配置管理 |
| `ali/k8s-migration-proxy/README.md` | K8s集群迁移代理 (K8s Cluster Migration Proxy) |
| `ali/k8s-migration-proxy/TASK3_IMPLEMENTATION_SUMMARY.md` | Task 3 Implementation Summary: ExternalName Services Configuration |
| `ali/k8s-migration-proxy/docs/external-services.md` | ExternalName Services Configuration |
| `ali/k8s-migration-proxy/docs/ingress-implementation.md` | Ingress Configuration Implementation |
| `flow/docs/gke.md` | GKE Traffic Flow & Architecture |
| `gcp/asm/gloo/gke-ambient-waypoint-multip.md` | GKE Ambient + Waypoint 多集群企业版实施版 |
| `gcp/asm/gloo/gke-ambient-waypoint-single.md` | GKE Ambient + Waypoint 单集群生产安装版 |
| `gcp/asm/gloo/gke-ambient-waypoint.md` | GKE Ambient + Waypoint 安装与校正文档（企业版可用） |
| `gcp/asm/gloo/step-by-step-gloo-setup-gke.md` | End-to-End Gloo Mesh Enterprise Installation on GKE |
| `gcp/cost/gke-cost-allocations.md` | Q |
| `gcp/cost/gke_cluster_resource_consumption.md` | Gke Cluster Resource Consumption |
| `gcp/gke/GKE-cluster-autoscaler.md` | node pool |
| `gcp/gke/GKE-upgrade-contained2.md` | GKE containerd 2.0 Upgrade Assessment |
| `gcp/gke/connect-gke.md` | 1. 它是从哪个版本开始的？ |
| `gcp/gke/filter-deployment.md` | reference |
| `gcp/gke/gke-secret-manager.md` | GKE Secret Manager 集成深度分析 |
| `gcp/gke/how-node-upgraded.md` | How-node-upgrade |
| `gcp/gke/kong-blue-green.md` | 利用Kong进行蓝绿部署的可行性实现 |
| `gcp/gke/lifecycle.md` | lifecycle.json |
| `gcp/gke/localpolicy-with-topology.md` | GKE 节点池 Location Policy 与 Topology Spread Constraints |
| `gcp/gke/pod-node-affinity.md` | 详细解释 |
| `gcp/gke/runtime-namespace-networkpolicy.md` | GKE Runtime Namespace NetworkPolicy 设计与落地 |
| `gcp/gke/workload-identify.md` | GKE Namespace 创建脚本详解 |
| `gcp/gke/workload-with-annotate.md` | Workload Identity 与 Namespace Annotate 深度解析 |
| `gcp/ingress/gke-ingress-stephen.md` | mermaid |
| `gke/README.md` | GKE (Google Kubernetes Engine) 知识库 |
| `gke/docs/Blue-Green-design.md` | Summary |
| `gke/docs/Blue-Green.md` | **一、Blue-Green Deployment（蓝绿部署）** |
| `gke/docs/GKE-Labels.md` | GKE 集群标签 |
| `gke/docs/GKE-Master.md` | Gke Master |
| `gke/docs/GKE-Pod-Disk.md` | **✅** |
| `gke/docs/Kong-canary.md` | 示例：创建 Upstream |
| `gke/docs/Multi-tenant.md` | **🧭 一、总体思路：你需要从三大维度出发** |
| `gke/docs/connect-GKE.md` | Connect Gke |
| `gke/docs/gke-blue-green.md` | 蓝绿部署操作思路 (结合你的 API 流) |
| `gke/docs/gke-node-version.md` | Gke Node Version |
| `gke/docs/gke-service-protection.md` | GKE 中的服务保护功能解析 |
| `gke/docs/gke-upgrade.md` | Gke Upgrade |
| `gke/docs/grafana-gke.md` | chatgpt |
| `gke/docs/multi-tenant-cluster.md` | **🧭 一、总体思路：你需要从三大维度出发** |
| `gke/docs/node-pool-describe.md` | strategy |
| `gke/what-gke.md` | What is GKE (Google Kubernetes Engine)? |
| `java/debug/gke-nmt-logging.md` | GKE Java Native Memory Tracking (NMT) 日志采集方案 |
| `java/debug/gke-pod-create-file.md` | Gke Pod Create File |
| `java/debug/java-gke-pod-version.md` | Q 如何在GKE中批量获取Pod的Java版本信息 |
| `k8s/Mytools/Readme.md` | Kali Linux 安全工具容器 |
| `k8s/Mytools/kubectl-cmd.md` | 🚀 高效 Kubernetes 管理：Kubectl 核心命令与进阶技巧 |
| `k8s/README.md` | Kubernetes (k8s) 知识库 |
| `k8s/busybox/deploy.md` | nas deployment testing |
| `k8s/busybox/nas-deployment.md` | Nas Deployment |
| `k8s/busybox/nas-service.md` | Nas Service |
| `k8s/config/Dockerfile-file-size.md` | 直接下载大文件包 |
| `k8s/config/Dockerfile-secret.md` | 基础镜像 |
| `k8s/custom-liveness/custom-liveness-gemini.md` | 深度自定义 Kubernetes Liveness Probe 与智能故障切换方案 |
| `k8s/custom-liveness/explore-startprobe/CHANGELOG.md` | 更新日志 |
| `k8s/custom-liveness/explore-startprobe/EXAMPLE.md` | 探针配置实战示例 |
| `k8s/custom-liveness/explore-startprobe/INDEX.md` | Pod Health Check Library - Documentation Index |
| `k8s/custom-liveness/explore-startprobe/PROJECT_SUMMARY.md` | Pod Health Check Library - Project Summary |
| `k8s/custom-liveness/explore-startprobe/QUICK_START.md` | Quick Start - Pod Health Check Library |
| `k8s/custom-liveness/explore-startprobe/README.md` | Kubernetes 探针配置最佳实践 |
| `k8s/custom-liveness/explore-startprobe/custom-readme.md` | Kubernetes 自定义存活探针与代理故障转移方案 |
| `k8s/custom-liveness/explore-startprobe/merged-scripts.md` | Shell Scripts Collection |
| `k8s/custom-liveness/explore-startprobe/openssl-get-url.md` | 步骤1: 基本连接检查（验证SSL握手和证书） |
| `k8s/custom-liveness/explore-startprobe/openssl-verify-health.md` | Pod 健康检查通用函数库 |
| `k8s/custom-liveness/explore-startprobe/pod_measure_enhance.md` | Pod Startup Measurement Script 优化方案 |
| `k8s/custom-liveness/explore-startprobe/probe-best-practices-eng.md` | GKE Explorer: Best Practices Guide for Probe Configuration |
| `k8s/custom-liveness/explore-startprobe/probe-best-practices.md` | GKE Explorer: 探针配置最佳实践指南 |
| `k8s/custom-liveness/explore-startprobe/troubleshooting.md` | GKE 探针故障排查指南 (Troubleshooting Guide) |
| `k8s/custom-liveness/explore-startprobe/v5_enhancements.md` | Pod Startup Measurement v5 - Enhancements |
| `k8s/custom-liveness/macos-find-mv.md` | 在当前目录下，将最近 3 天内修改过的普通文件 |
| `k8s/custom-liveness/user-setting.md` | GKE Pod 探针配置最佳实践指南 |
| `k8s/debug-pod/README.md` | Kubernetes Pod Debug Scripts |
| `k8s/debug-pod/copy-file-to-local.md` | 问题分析 |
| `k8s/debug-pod/cross-pod-debugging.md` | GKE Pod 跨 Pod 调试指南 |
| `k8s/debug-pod/debug-java-pod.md` | 假设 Java 进程由用户 appuser 运行 |
| `k8s/debug-pod/debug-pod-terminal.md` | Debug Pod Terminal |
| `k8s/debug-pod/fake-pod.md` | 伪造Deployment中的Pod是可能的吗? |
| `k8s/debug-pod/optimization-comparison.md` | 脚本优化对比分析 |
| `k8s/debug-pod/side.md` | 基本用法 |
| `k8s/debug-pod/sidecar.md` | 跨 Pod 调试方法 |
| `k8s/deploy/lifecycle.md` | Kubernetes Lifecycle Hook |
| `k8s/docs/Blogs-to-Learn-25-Kubernetes-Concepts.md` | Blogs To Learn 25 Kubernetes Concepts |
| `k8s/docs/Docker-define-apt.md` | 使用最新的 Ubuntu 作为基础镜像 |
| `k8s/docs/Release-pdb.md` | summary |
| `k8s/docs/a.md` | A |
| `k8s/docs/affinity-add-new-logic.md` | old api pod anti-affinity |
| `k8s/docs/affinity.md` | 提取的K8S Deployment配置 |
| `k8s/docs/analyse-memory-cpu.md` | Analyse Memory Cpu |
| `k8s/docs/appd-init-container.md` | About Start Q |
| `k8s/docs/base-networkpolicy.md` | Last |
| `k8s/docs/cm.md` | **1. GKE 本身的限制（Quota/Limit）** |
| `k8s/docs/codegpt.md` | Codegpt |
| `k8s/docs/configmap-daemon.md` | configmap |
| `k8s/docs/configmap.md` | GKE 平台开放用户自定义 ConfigMap 的风险评估 |
| `k8s/docs/container-pod.md` | 容器（Container） |
| `k8s/docs/cronjob.md` | CronJob 状态 |
| `k8s/docs/deploy-type.md` | Kubernetes 资源部署方式区分 |
| `k8s/docs/deployment-error.md` | Deployment Error |
| `k8s/docs/deployment2.md` | CI flow |
| `k8s/docs/detail-deployment.md` | summary |
| `k8s/docs/docker-images-labels.md` | gemini |
| `k8s/docs/dynamic-pdb.md` | Q |
| `k8s/docs/edit-deployment.md` | Edit Deployment |
| `k8s/docs/egress.md` | 第一个NetworkPolicy |
| `k8s/docs/endpoint.md` | **1. 关键概念简介** |
| `k8s/docs/enhance-pod-start.md.md` | think |
| `k8s/docs/enhance-probe.md` | SeqDigram |
| `k8s/docs/etcd.md` | 1. **etcd 存储了什么信息？** |
| `k8s/docs/evict.md` | calude |
| `k8s/docs/except.md` | 使用except_section替换您的网络策略中的except部分 |
| `k8s/docs/fack-pod.md` | 伪造Deployment中的Pod是可能的吗? |
| `k8s/docs/filter-namespace.md` | 获取所有的namespace |
| `k8s/docs/flow-pdb.md` | Why and current status |
| `k8s/docs/get-ns-dep.md` | !/bin/bash |
| `k8s/docs/gke-deployment-appd-no-root.md` | wrap ai |
| `k8s/docs/gke-networkpolicy-except.md` | Gke Networkpolicy Except |
| `k8s/docs/gke-upgrade.md` | why PDB |
| `k8s/docs/helm-best-practices.md` | **Helm 实战指南：复杂环境下的配置治理与全局变更控制** |
| `k8s/docs/helm-hook.md` | claude3.5 |
| `k8s/docs/helm-squid.md` | Squid Helm Chart |
| `k8s/docs/helm.md` | PDB 资源解析逻辑 |
| `k8s/docs/hostalias.md` | Hostalias |
| `k8s/docs/housekeep.md` | summary |
| `k8s/docs/hpa-poc-cpu-memory.md` | - name: https_proxy |
| `k8s/docs/hpa-replicas.md` | gemini |
| `k8s/docs/hpa-size-alert.md` | Description |
| `k8s/docs/hpa-size.md` | Chatgpt |
| `k8s/docs/hpa-with-maxunavailable.md` | ... Pod模板配置 ... |
| `k8s/docs/hpa.md` | Deployment YAML |
| `k8s/docs/ingress.md` | Ingress |
| `k8s/docs/intcontainer-container.md` | summary |
| `k8s/docs/job.md` | Job |
| `k8s/docs/k8s-cluster-secret.md` | cluster_secret |
| `k8s/docs/k8s-exec.md` | 限制特定命名空间的 `kubectl exec` 权限步骤 |
| `k8s/docs/k8s-export-secret.md` | **方式一：导出后用** |
| `k8s/docs/k8s-feature.md` | K8S Feature |
| `k8s/docs/k8s-get-Replicas.md` | K8S Deployment Replicas 对比方案 |
| `k8s/docs/k8s-pod-stat-completed.md` | K8S Pod Stat Completed |
| `k8s/docs/k8s-request-limit.md` | GKE Pod 资源调度机制详解 |
| `k8s/docs/k8s-request.md` | **🧠 基本概念回顾** |
| `k8s/docs/k8s-resource-summary.md` | ✅ 脚本：`k8s-resource-summary.sh` |
| `k8s/docs/k8s-scale/k8s-resouce-autoscale-chatgpt.md` | Kubernetes Requests/Limits、调度默认行为与 Autoscaling（场景推演） |
| `k8s/docs/k8s-scale/k8s-resouce-autoscale.md` | Kubernetes 资源调度与自动扩缩容深度解析 |
| `k8s/docs/k8s-scale/scale-deploy.md` | Claude |
| `k8s/docs/kill-pod.md` | 流量分配和恢复过程 |
| `k8s/docs/kube-crd.md` | 使用 Kubernetes 自定义资源 (CRD) 进行版本管理的详细指南 |
| `k8s/docs/kube-neat.md` | **🚀 什么是 kube-neat？** |
| `k8s/docs/kube-path-hpa.md` | Kube Path Hpa |
| `k8s/docs/kubectl-event.md` | Kubernetes 事件 |
| `k8s/docs/lex-poc-hpa-cpu-memory.md` | - name: https_proxy |
| `k8s/docs/liveless-simple.md` | 🎯 你的问题总结 |
| `k8s/docs/liveness.md` | Kubernetes Liveness Probe implementation |
| `k8s/docs/memory-recycle.md` | 方法一：重新启动Pod |
| `k8s/docs/mini-change.md` | Minimal Platform Adaptation Strategy (Mini-Change) |
| `k8s/docs/networkpolicy-egress-svc.md` | summary |
| `k8s/docs/networkpolicy.md` | Q |
| `k8s/docs/netwrokpolicy.md` | Last |
| `k8s/docs/no-medata.md` | continue with normal code for accessing metadata |
| `k8s/docs/no-root-deployment.md` | summary |
| `k8s/docs/node-pool-name.md` | Node Pool Name |
| `k8s/docs/non-root.md` | groupadd |
| `k8s/docs/pdb-core.md` | thinking |
| `k8s/docs/pdb-effect.md` | 在保障高可用性的同时避免因 PDB 配置和异常 Pod 状态阻碍集群升级流程 |
| `k8s/docs/pdb-namespace.md` | Summary |
| `k8s/docs/pdb-time.md` | 示例：即使配置了严格的 PDB 也会受 1 小时限制 |
| `k8s/docs/pdb.md` | 使用 PodDisruptionBudget 的步骤和方法 |
| `k8s/docs/pod-Encryption.md` | **🔒 GKE 集群内通信的加密情况** |
| `k8s/docs/pod-annotations.md` | summary |
| `k8s/docs/pod-lifecycle.md` | Pod 的终止 |
| `k8s/docs/pod-restart.md` | !/bin/bash |
| `k8s/docs/pod-sigterm.md` | sigterm 信号的时间 |
| `k8s/docs/pod-start.md` | Pod Start |
| `k8s/docs/pod-system-version.md` | GKE Pod 系统版本查询脚本 |
| `k8s/docs/pod-write-data-gemini.md` | 在GKE生产环境中管理并发数据库写入：策略与解决方案 |
| `k8s/docs/pod-write-data.md` | Claude4 |
| `k8s/docs/readiness.md` | Liveness 和 Readiness 探测 |
| `k8s/docs/redis.md` | Whitelist setting |
| `k8s/docs/replicaset.md` | 1. 手动配置 |
| `k8s/docs/res.md` | 输出 |
| `k8s/docs/role.md` | role Debug |
| `k8s/docs/rolling+affinity+pdb.md` | Q |
| `k8s/docs/secret-enhance.md` | GKE Deployment |
| `k8s/docs/set-image.md` | chatgpt |
| `k8s/docs/strategy.md` | 关键配置参数 |
| `k8s/docs/stress.md` | !/bin/bash |
| `k8s/docs/summary-affinity.md` | summary |
| `k8s/docs/syncloop-status.md` | Syncloop Status |
| `k8s/docs/temp-stop-pdb.md` | 问题分析 |
| `k8s/docs/terminationGracePeriodSeconds.md` | Pod 的终止 |
| `k8s/docs/trigger-appd.md` | summary |
| `k8s/docs/update-images.md` | 1. kubectl set image |
| `k8s/docs/verify-namespace-label.md` | !/bin/bash |
| `k8s/docs/why-context.md` | 限制容器的权限 |
| `k8s/docs/why-needhttps-intra-ns.md` | Why Needhttps Intra Ns |
| `k8s/hpa/cpu-and-memory-bak.md` | Horizontal Pod Autoscaler (HPA) 详解 |
| `k8s/hpa/cpu-and-memory-corrected-en.md` | Horizontal Pod Autoscaler (HPA) Detailed Explanation - Revised and Enhanced V... |
| `k8s/hpa/cpu-and-memory-corrected.md` | Horizontal Pod Autoscaler (HPA) 详解 - 修正与增强版 |
| `k8s/hpa/cpu-and-memory-explor-qwen.md` | Horizontal Pod Autoscaler (HPA) 详解 - 修正与增强版 |
| `k8s/hpa/cpu-and-memory-github.md` | Horizontal Pod Autoscaler (HPA) 详解 - GitHub兼容版 |
| `k8s/hpa/cpu-and-memory.md` | Horizontal Pod Autoscaler (HPA) 详解 |
| `k8s/hpa/cpu-sort.md` | Horizontal Pod Autoscaler (HPA) 详解 |
| `k8s/hpa/hpa-3-4-memory.md` | K8S HPA 扩容触发点计算 |
| `k8s/hpa/hpa-core.md` | 公式 |
| `k8s/hpa/hpa-cpu-and-memory-en.md` | Horizontal Pod Autoscaler (HPA) Explained - Corrected and Enhanced Version |
| `k8s/hpa/hpa-other.md` | other |
| `k8s/hpa/hpa-reduce.md` | HPA 描述输出分析 |
| `k8s/hpa/hpa-tye-change.md` | 回答问题 |
| `k8s/hpa/hpa-type.md` | 扩容和缩容的详细逻辑 |
| `k8s/hpa/memory-hpa.md` | other |
| `k8s/hpa/min-max-replicas.md` | Deployment |
| `k8s/hpa/reasonable.md` | vim 技巧 |
| `k8s/hpa/resouce.md` | deployment |
| `k8s/hpa/summary-hpa-last.md` | Summary: Kubernetes HPA Scaling Logic (Revised) |
| `k8s/hpa/summary-hpa.md` | HPA 扩缩容算法与容忍度解析 |
| `k8s/images/Housekeep-imagepullsecrets.md` | Housekeep ImagePullSecrets |
| `k8s/images/imagePullSecrets.md` | Imagepullsecrets |
| `k8s/images/images-pull-time.md` | GKE Pod Image Pull Time Exploration |
| `k8s/images/k8s-img-replace.md` | **问题分析** |
| `k8s/images/merged-scripts.md` | Shell Scripts Collection |
| `k8s/images/molo.md` | 一句话定位对比 |
| `k8s/k8s-scale/README.md` | Kubernetes Resource Optimization Tool |
| `k8s/k8s-scale/about-restore.md` | 查看所有被缩减的 deployment |
| `k8s/k8s-scale/maxSurge.md` | GKE Deployment RollingUpdate 参数设计分析 |
| `k8s/k8s-scale/merged-scripts.md` | Shell Scripts Collection |
| `k8s/k8s-scale/scale-deployment.md` | **✅** |
| `k8s/k8s-scale/walkthrough.md` | Walkthrough - Kubernetes Resource Optimization Script (Bash Version) |
| `k8s/k8s-tls-Opaque.md` | Kubernetes TLS Secret vs Opaque Secret 完全对比 |
| `k8s/labels/Labels-TODO.md` | Labels Todo |
| `k8s/labels/add/00_workflow.md` | Automation Workflow: Batch Add Labels to Deployments |
| `k8s/labels/add/Explorer-labels.md` | 方案规划分析 |
| `k8s/labels/add/add-ns-labels.md` | !/usr/bin/env bash |
| `k8s/labels/add/merged-scripts.md` | Shell Scripts Collection |
| `k8s/labels/labels-best-practices.md` | Kubernetes 标签（Labels）最佳实践 |
| `k8s/labels/labels.md` | Labels |
| `k8s/labels/merged-scripts.md` | Shell Scripts Collection |
| `k8s/labels/metadata-labels.md` | ✅ **一次性增加多个 metadata.labels（安全，不触发滚动更新）** |
| `k8s/labels/reademe.md` | 修改脚本中的配置 |
| `k8s/lib/CHANGELOG.md` | Changelog - Pod Health Check Library |
| `k8s/lib/COMMAND_PATHS.md` | Command Path Configuration |
| `k8s/lib/CRITICAL_BUG_FIX.md` | Critical Bug Fix - PATH Variable Collision |
| `k8s/lib/MACOS_FIX.md` | macOS Compatibility Fix Guide |
| `k8s/lib/README.md` | Kubernetes Library Functions |
| `k8s/lib/TROUBLESHOOTING.md` | Troubleshooting |
| `k8s/migrate/ how-to-migrate-ns.md` | Summary |
| `k8s/migrate/How-to-migrate-cluster.md` | **🧩 一、问题分析** |
| `k8s/networkpolicy/Routes-based-LLM.md` | 第一部分：内容准确性验证 |
| `k8s/networkpolicy/Routes-based.md` | Routes-based 模式下的网络流量详解 |
| `k8s/networkpolicy/base-networkpolicy-egress-ingress.md` | GKE Routes-based 模式完整网络策略配置 |
| `k8s/networkpolicy/cross-namespace.md` | 跨 Namespace 网络策略配置分析 |
| `k8s/networkpolicy/debug-ns-networkpolicy.md` | NetworkPolicy 跨 Namespace 通信 Debug 指南 |
| `k8s/networkpolicy/ebpf.md` | Kubernetes Networking Game-Changer: An Introduction to eBPF |
| `k8s/networkpolicy/gke-ns-networkpolicy.md` | 允许访问特定 namespace |
| `k8s/networkpolicy/network-node-ip.md` | 完全理解了！您说得对！ |
| `k8s/networkpolicy/network-ns-ns-flow.md` | GKE 跨 Namespace 网络访问完整流程图 |
| `k8s/networkpolicy/network-ns-ns.md` | Claude |
| `k8s/networkpolicy/networkpolicy-l34-l7.md` | NetworkPolicy L3/L4/L7 In GKE And Managed Service Mesh |
| `k8s/networkpolicy/networkpolicy-node-pod.md` | Why |
| `k8s/networkpolicy/networkpolicy-ns-ns-gemini.md` | GKE 跨 Namespace 通信：NetworkPolicy 与 Node IP 解惑 |
| `k8s/qnap-k8s/README.md` | QNAP Kubernetes 部署脚本 |
| `k8s/scripts/kubectl-logs.md` | Kubernetes Pod 日志查看工具 |
| `k8s/scripts/merged-scripts.md` | Shell Scripts Collection |
| `k8s/scripts/pod_exec.md` | !/bin/bash |
| `k8s/scripts/pod_measure_startup_fixed.md` | Pod Measure Startup Fixed |
| `k8s/vpa/how-to-setting-vpa-value.md` | Claude |
| `k8s/vpa/vpa-concept.md` | **1. 什么是垂直扩展（Vertical Scaling）** |
| `k8s/vpa/vpa-config.md` | Vpa Config |
| `monitor/opentelemetry/opentelemetry-k8s-special.md` | Opentelemetry K8S Special |
| `ob/egress-dynamic/gke-squid-dynamic-chatgpt.md` | **GKE Squid Proxy 多上游代理按目的域名路由设计方案** |
| `ob/egress-dynamic/gke-squid-dynamic-claude.md` | GKE Squid 动态代理路由方案 |
| `psc-sql-flow-demo/k8s/why-psc-netpolicy-3307.md` | 为什么 PSC模式下 NetworkPolicy 需要允许 3306/3307 端口 |
| `report/docs/k8s-cronjob-monitor.md` | Create email |
| `skills/architectrue/gke-policy-controller-vs-gatekeeper/SKILL.md` | GKE Policy Controller vs Open Source OPA Gatekeeper |
| `skills/gcp/gke-ipam/SKILL.md` | GKE IPAM |
| `skills/gcp/gke-policy-controller-tep-analysis/SKILL.md` | GKE Policy Controller TEP Coverage Analysis Pattern |
| `skills/gke-basics/SKILL.md` | Google Kubernetes Engine (GKE) Basics |
| `skills/gke-basics/references/cli-reference.md` | CLI & Tool Reference for GKE |
| `skills/gke-basics/references/core-concepts.md` | GKE Core Concepts |
| `skills/gke-basics/references/gke-app-onboarding.md` | GKE App Onboarding |
| `skills/gke-basics/references/gke-backup-dr.md` | GKE Backup & Disaster Recovery |
| `skills/gke-basics/references/gke-batch-hpc.md` | GKE Batch & HPC Workloads |
| `skills/gke-basics/references/gke-cluster-creation.md` | GKE Cluster Creation |
| `skills/gke-basics/references/gke-compute-classes.md` | GKE ComputeClasses |
| `skills/gke-basics/references/gke-cost.md` | GKE Cost Optimization |
| `skills/gke-basics/references/gke-golden-path.md` | GKE Golden Path Configuration |
| `skills/gke-basics/references/gke-inference.md` | GKE AI/ML Inference |
| `skills/gke-basics/references/gke-multitenancy.md` | GKE Multi-Tenancy |
| `skills/gke-basics/references/gke-networking.md` | GKE Networking |
| `skills/gke-basics/references/gke-observability.md` | GKE Observability |
| `skills/gke-basics/references/gke-reliability.md` | GKE Reliability |
| `skills/gke-basics/references/gke-scaling.md` | GKE Workload Scaling |
| `skills/gke-basics/references/gke-security.md` | GKE Security |
| `skills/gke-basics/references/gke-storage.md` | GKE Storage |
| `skills/gke-basics/references/gke-upgrades.md` | GKE Upgrades & Maintenance |

### Kong Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `ali/migrate-plan/plan1/migrate-kongDP.md` | Migrate Kongdp |
| `ali/migrate-plan/plan1/migrate-kongdp-gemini.md` | Kong DP 迁移计划 (从集群 A 到集群 B) |
| `ali/migrate-plan/plan1/migration-kongdp-explorer.md` | Q |
| `kong/README.md` | Kong 知识库 |
| `kong/docs/API-Rate-Limiting.md` | Api Rate Limiting |
| `kong/docs/capture-kong-log.md` | Capture Kong Log |
| `kong/docs/cp-vs-dp.md` | **你的场景** |
| `kong/docs/debug-kong-gemini.md` | Nginx -> Kong -> GKE 认证流程深度解析 (Gemini版) |
| `kong/docs/debug-kong.md` | Claude |
| `kong/docs/hazelcast.md` | Hazelcast |
| `kong/docs/httpbin.md` | **问题分析** |
| `kong/docs/kong-2.8-vs-3.4.md` | **1. 排查大量`Completed`状态Pod的原因** |
| `kong/docs/kong-auth-english.md` | Kong AUTHZ Plugin Path-based Group Check Issue Analysis |
| `kong/docs/kong-auth-group.md` | ChatGPT |
| `kong/docs/kong-auth.md` | Kong AUTHZ Plugin Path-based Group Check 问题分析 |
| `kong/docs/kong-chinese.md` | Q |
| `kong/docs/kong-cluster-secret.md` | Kong 的角色 |
| `kong/docs/kong-error.md` | Kong 数据平面错误分析 |
| `kong/docs/kong-file-size.md` | 使用 Kong 实现请求体大小限制 |
| `kong/docs/kong-healthcheck-rt.md` | 更新 Service 配置，添加健康检查 |
| `kong/docs/kong-hight-availablity.md` | Deeepseek |
| `kong/docs/kong-ipmatcher.lua.md` | **❓** |
| `kong/docs/kong-log-vault-lua.md` | Q |
| `kong/docs/kong-lua-ssl.md` | 配置段落 |
| `kong/docs/kong-opentelemetry.md` | 1. 背景与问题分析 |
| `kong/docs/kong-plug-limit.md` | 配置项解释 |
| `kong/docs/kong-post-case.md` | Flow Post.md |
| `kong/docs/kong-retry-and-describe.md` | summary |
| `kong/docs/kong-token.md` | 1. **A Client 的 Token** |
| `kong/docs/kong-underscores_in_header.md` | **`on` 或 `off` 的含义** |
| `kong/docs/kong-zero-downtime.md` | 查看所有 Completed 状态的 Pod |
| `kong/docs/migrate-kong.md` | **1. 问题分析** |
| `kong/docs/payloadsize.md` | 概念解释 |
| `kong/docs/route.md` | Grok |
| `kong/docs/testcase.md` | Function test |
| `kong/docs/x-client-cert-leaf.md` | Q |
| `kong/kongdp/compare-dp.md` | Kong Data Plane 资源对比工具 |
| `kong/kongdp/kongdp-setting-timeout.md` | 在 Service 上启用 Retry 插件 |
| `kong/kongdp/kongdp-status-debug.md` | **✅** |
| `kong/kongdp/kongdp-status-troubleshoot.md` | Kong Data Plane (DP) Status Troubleshooting Guide |
| `kong/kongdp/merged-scripts.md` | Shell Scripts Collection |

### Linux Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gcp/gcp-infor/linux-scripts/gcp-knowledge.md` | GCP Platform Knowledge - Linux Environment |
| `linux/README.md` | Linux 知识库 |
| `linux/docs/Docker-bash.md` | **问题分析** |
| `linux/docs/Linux-control-group-v2.md` | Linux Control Group V2 |
| `linux/docs/Linux-start-services.md` | Linux 服务启动顺序与依赖管理最佳实践 |
| `linux/docs/Networkmanager.md` | GCP Instance 重启 NetworkManager 导致静态路由丢失问题分析 |
| `linux/docs/Streamable.md` | **📡 What is Streamable HTTP?** |
| `linux/docs/Ubuntu-dpkg.md` | Ubuntu Dpkg |
| `linux/docs/anacrontab.md` | /etc/anacrontab: configuration file for anacron |
| `linux/docs/cgroup.md` | GKE Node cgroup v2 检测与 Java OOM 日志分析 |
| `linux/docs/csv-format-to-markdown.md` | !/bin/bash |
| `linux/docs/curl-option.md` | The curl -X option |
| `linux/docs/curl-ssl-error.md` | 解决步骤 |
| `linux/docs/curl-ssl.md` | About gke secret |
| `linux/docs/curl-timeout.md` | 1. **连接超时 (`--connect-timeout`)** |
| `linux/docs/debug-timeout-flow.md` | 超时流程验证与调试指南 |
| `linux/docs/debug-timeout.md` | 超时问题排查 Runbook（A→B→C→D→E） |
| `linux/docs/delete.md` | Delete |
| `linux/docs/diff.md` | **一、通用文件比较工具（支持各种文本文件）** |
| `linux/docs/docker-ubuntu.md` | summary and backgroud |
| `linux/docs/explorer-sse-streamable.md` | Grok4 |
| `linux/docs/export-ssl.md` | 1. 查看证书列表 |
| `linux/docs/flow-client-a-b-c.md` | Flow Client A B C |
| `linux/docs/get.md` | Get |
| `linux/docs/git.md` | !/bin/bash |
| `linux/docs/how-to-update-ca.md` | 1. Debian/Ubuntu |
| `linux/docs/http-Origin.md` | summary |
| `linux/docs/http-method.md` | HTTP 方法的作用 |
| `linux/docs/http-status.md` | status |
| `linux/docs/http-stream.md` | nginx stream |
| `linux/docs/ip-sort-uniq.md` | 输入示例：一组字符串形式的 IP 段 |
| `linux/docs/istio.md` | ... 其他容器配置 ... |
| `linux/docs/jq-filter.md` | !/bin/bash |
| `linux/docs/jq.md` | what is json file |
| `linux/docs/limit.md` | 临时提高当前会话的软限制 |
| `linux/docs/linux-performance.md` | 各命令的使用说明 |
| `linux/docs/ls.md` | Ls |
| `linux/docs/merged-csv.md` | !/usr/local/bin/bash |
| `linux/docs/mtu.md` | 在 Linux 中更改 MTU 大小 |
| `linux/docs/nc.md` | netcat（nc）使用指南与常见示例 |
| `linux/docs/nohup.md` | Nohup |
| `linux/docs/nvim-markdown.md` | reference |
| `linux/docs/nvim.md` | 1. 安装 Neovim |
| `linux/docs/pip-install.md` | cybervault-cve-report |
| `linux/docs/post-content-length.md` | Post Content Length |
| `linux/docs/post.md` | Deep seek |
| `linux/docs/purl.md` | Purl |
| `linux/docs/quic.md` | QUIC(Quick UDP Internet Connections) 协议 |
| `linux/docs/rate-limiting.md` | Rate Limiting |
| `linux/docs/regex.md` | summary |
| `linux/docs/replace-current.md` | Shell 脚本：批量文件内容关键字替换 |
| `linux/docs/replace.md` | the bash script |
| `linux/docs/route-claude.md` | Linux Route Commands Guide |
| `linux/docs/route.md` | Linux 路由命令详解 |
| `linux/docs/sse.md` | summary |
| `linux/docs/status-499.md` | 1. **客户端超时设置** |
| `linux/docs/tcp-large-send-offload.md` | Tcp Large Send Offload |
| `linux/docs/telnet-timeout.md` | Telnet 空闲连接超时测试指南 |
| `linux/docs/telnet.md` | Telnet |
| `linux/docs/time.md` | Get the current time |
| `linux/docs/timeout-flow-claude.md` | A |
| `linux/docs/timeout-flow.md` | Timeout |
| `linux/docs/tls.md` | 流程解释 |
| `linux/docs/ubuntu-source-diff.md` | 官方主源 |
| `linux/docs/user-add.md` | summary |
| `linux/docs/wget.md` | 参数说明： |
| `linux/linux-os-optimize/linux-system-optimize-chatgpt.md` | **🧠 优化目标分析** |
| `linux/linux-os-optimize/merged-scripts.md` | Shell Scripts Collection |
| `linux/neovim/Readme.md` | Readme |
| `linux/neovim/bufferline.md` | Bufferline |
| `linux/neovim/how-to-add-new-plug.md` | How To Add New Plug |
| `linux/neovim/init-vim.md` | Using lazyvim managed my plug |
| `linux/neovim/lazyvim.md` | baking my old neovim |
| `linux/neovim/neovim-install.md` | 1. 安装 `vim-plug` |
| `linux/neovim/plug.md` | 1. 运行 `:PlugClean` |
| `linux/neovim/tree-lua.md` | Tree Lua |
| `linux/scripts/curl-weather.md` | Curl Weather |
| `linux/version/compare-version.md` | !/bin/bash |
| `linux/version/split-housekeep-deploy.md` | script |
| `linux/version/version.md` | summary |
| `linux/version/version2.md` | summary |

### Logging Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gcp/logs/cross-project-sharing-logs.md` | GCP Cross-Project Log Sharing 最佳实践 |
| `gcp/logs/filter-health.md` | 何用gcloud 命令修改mig的health check |
| `gcp/logs/filter-pod-number.md` | Filter Pod Number |
| `gcp/logs/gcp-log-view.md` | ChatGPT |
| `gcp/logs/log-limit.md` | **最佳实践方案** |
| `gcp/logs/log-limition.md` | GCP 日志监控和限制最佳实践 |
| `logs/README.md` | Logs 知识库 |
| `logs/docs/Fluentd.md` | Fluentd 日志处理详解：以 GCP + Nginx 为例 |
| `logs/docs/Interconnect-flow.md` | Interconnect Flow: UK VPC to HK VPC |
| `logs/docs/anaylize-gcp-log.md` | 补充说明 |
| `logs/docs/cross-project-vpc-analyze-claude.md` | GCP Shared VPC 跨 Project 日志追踪与 VPC 互联详解 |
| `logs/docs/cross-project-vpc-anaylize-ChatGPT.md` | **一、GCP 网络结构关系概念** |
| `logs/docs/cross-project-vpc-anaylize-claude-application.md` | GCP Shared VPC 跨 Project 日志追踪与 VPC 互联详解 |
| `logs/docs/cross-project-vpc-anaylize-gemini-1.md` | Cross-Project Shared VPC Log Analysis and Interconnect Concepts |
| `logs/docs/cross-project-vpc-anaylize-gemini.md` | Cross-Project VPC Log Analysis: A Gemini Synthesis |
| `logs/docs/interconnects.md` | GCloud Compute Interconnects Attachments Describe |
| `logs/docs/intro.md` | Intro |
| `logs/docs/summary-cross.md` | summary |
| `logs/docs/test.md` | **gcloud compute interconnects attachments list** |
| `logs/docs/vlan.md` | **gcloud compute interconnects attachments list** |
| `logs/docs/vpc-claude.md` | GCP Shared VPC 跨 Project 日志追踪完整解决方案 |
| `logs/docs/vpc-log.md` | Summary |
| `nas/docs/How-to-flow-k3s-logs.md` | How To Flow K3S Logs |
| `splunk/README.md` | Splunk 知识库 |
| `splunk/docs/Splunk-client-agent.md` | Splunk Client Agent |
| `splunk/docs/Splunk-other.md` | Splunk Other |
| `splunk/docs/base.md` | p |
| `splunk/docs/splunk-log-format.md` | Splunk Log Format |

### Monitoring Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gcp/lb/forwardingrule-monitor.md` | 方案概述 |
| `gcp/network/psc-sre/psc-monitor.md` | Psc Monitor |
| `gcp/pub-sub/pub-sub-monitor-parameter-english.md` | **Core Metrics for Pub/Sub Consumer Performance** |
| `gcp/pub-sub/pub-sub-monitor-parameter.md` | **Pub/Sub 消费性能相关核心指标** |
| `macos/docs/macOS-monitor-connect.md` | summary |
| `macos/docs/powermetrics.md` | Powermetrics |
| `monitor/README.md` | Monitor 知识库 |
| `monitor/docs/Capacity-Forecasting.md` | GKE 容量预测与主动监控 (Capacity Forecasting & Proactive Monitoring) |
| `monitor/docs/FailedScheduling.md` | **🧩 一、问题分析** |
| `monitor/docs/How-to-manage-monitor-policy.md` | How To Manage Monitor Policy |
| `monitor/docs/Mimir.md` | 一、Mimir 的背景和目标 |
| `monitor/docs/gce-mig-status.md` | summary |
| `monitor/docs/monitor-base-ai.md` | Understanding Delta in Monitoring Systems |
| `monitor/docs/monitor-egress-proxy.md` | GKE 正向代理（Squid）多跳访问场景的标准化监控设计 |
| `monitor/docs/monitor-memory.md` | GKE Pod 内存监控指南 |
| `monitor/docs/monitor-proxy.md` | **🧩 一、整体流程监控设计（路径监控）** |
| `monitor/docs/monitory-base.md` | Monitory Base |
| `monitor/docs/pod-memory.md` | GKE Pod 内存监控指标详解（以 Java Application 为核心视角） |
| `monitor/gce-disk/GCE-instance-disk.md` | ChatGPT |
| `monitor/gce-disk/README.md` | GCE Squid 代理磁盘监控工具集 |
| `monitor/gce-disk/gce-disk-analyze.md` | GCE Squid 代理磁盘监控实施方案 |
| `monitor/gce-disk/merged-scripts.md` | Shell Scripts Collection |
| `monitor/gce-disk/proxy-monitor.md` | Proxy Monitor |
| `monitor/opentelemetry/OpenTelemetry.md` | summary |
| `monitor/opentelemetry/opentelemetry-operator.md` | 当 Operator 检测到 annotation=true 时自动注入以下 sidecar |
| `report/docs/report-alert.md` | Q |
| `skills/google-cloud-recipe-networking-observability/references/metrics-analysis.md` | Networking Metrics Reference |

### Network Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `egress/docs/network-flow-diagram.md` | 网络流量图和架构详解 |
| `gcp/gce/debug-gce-proxy.md` | 问题排查过程总结 |
| `gcp/gce/gcp-network.md` | Q |
| `gcp/gce/understand-network.md` | a |
| `gcp/ingress/ingress-control-networkpolicy.md` | summary question |
| `gcp/network/cross-project-mig.md` | Cross-Project MIG / Backend Service 跨项目调用 |
| `gcp/network/flow-api-timeout.md` | 请求分析 |
| `gcp/network/google-cross-project-service.md` | GCP Cross-Project Service Referencing 深度解析 |
| `gcp/network/latest-status.md` | Latest Status |
| `gcp/network/nat-timeout-gemini.md` | Cloud NAT TCP TIME_WAIT Timeout 变更架构评估 (Gemini) |
| `gcp/network/nat-timeout.md` | Cloud NAT TCP TIME_WAIT 从 120s 到 30s 的影响评估 |
| `gcp/network/nat.md` | case |
| `gcp/network/neg.md` | NEG |
| `gcp/network/network-endpoint-groups.md` | 问题分析 |
| `gcp/network/proxy.md` | Google 的认证方式 |
| `gcp/network/psc-sre/psc-subnet-autoscale.md` | 结论先行：会不会有 Downtime？ |
| `gcp/network/psc-subnet/ip-range.md` | **2 多集群扩展规划 (基于 192.168.x.x)** |
| `gcp/network/psc-subnet/propagated.md` | 传播连接简介 (Propagated Connections) |
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
| `logs/docs/proxystatus.md` | Proxystatus |
| `macos/docs/app-network-observer.md` | macOS APP 网络域名观察脚本 |
| `network/README.md` | Network 知识库 |
| `network/docs/Electron.md` | Electron |
| `network/docs/README-explorer-domain.md` | Domain Explorer Script |
| `network/docs/README-ipv6-test.md` | IPv6 Network Test Script for macOS |
| `network/docs/appproxy.md` | 我的场景描述 |
| `network/docs/curl-503.md` | Curl 503 |
| `network/docs/curl-header.md` | Curl Header |
| `network/docs/curl-l.md` | Curl L |
| `network/docs/oauth2-authorization.md` | OAuth 2.0 Authorization Code Flow for Native Apps (RFC 8252) |
| `network/docs/protocal.md` | 10 Popular Network Protocols Explained with Diagrams |
| `network/docs/squid-proxy.md` | 允许 CONNECT 方法 |
| `network/docs/tailscale.md` | Tailscale |
| `network/docs/tcpdump.md` | Tcpdump 使用指南与实战案例 (Explorer Tcpdump) |
| `network/docs/testipv6.md` | Testipv6 |
| `network/forward-reverse/compare-and-migrate-reverse-to-forward.md` | Compare and Migrate: Reverse Proxy vs. Forward Proxy |
| `network/forward-reverse/curl-request-squid.md` | my request |
| `network/forward-reverse/explorer-egress-flow-enhance.md` | GKE Egress 代理流程图集合 (增强版) |
| `network/wrk/README-load-testing.md` | Load Testing Suite |
| `network/wrk/test-results/test_20250814_114748/summary.md` | Load Test Summary Report |
| `network/wrk/wrk.md` | Wrk |
| `other/docs/proxy.md` | Reverse Proxy |
| `skills/google-cloud-recipe-networking-observability/SKILL.md` | Google Cloud Networking Observability Expert |
| `skills/google-cloud-recipe-networking-observability/references/cloud-nat-analysis.md` | Cloud NAT Analysis Reference |
| `skills/google-cloud-recipe-networking-observability/references/connectivity-tests.md` | Connectivity Tests Reference |
| `skills/google-cloud-recipe-networking-observability/references/firewall-analysis.md` | Firewall Rule Logging Analysis Reference |
| `skills/google-cloud-recipe-networking-observability/references/threat-analysis.md` | Threat Log Analysis Reference |
| `skills/google-cloud-recipe-networking-observability/references/vpc-flow-analysis.md` | VPC Flow Analysis Reference |
| `squid/docs/squid-as-https-proxy.md` | Squid 代理配置分析与 HTTPS 代理方案 |
| `vpn/systemproxy-with-tun.md` | 1️⃣ 问题分析 |

### Nginx Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `flow/flow-nginx-enhance/Summary.md` | 架构优化总结：HTTPS负载均衡器 + Cloud Armor + 金丝雀部署实施方案 |
| `flow/flow-nginx-enhance/all-flow.md` | 架构流程图集合 - All Flow Charts |
| `flow/flow-nginx-enhance/canary-deployment.md` | Nginx 金丝雀部署配置详解 |
| `flow/flow-nginx-enhance/multp-lb-single-backendservice.md` | GCP Load Balancer类型对比 |
| `flow/flow-nginx-enhance/simple-architecture.md` | 架构优化建议：实现 Cloud Armor 精细化控制与蓝绿部署 |
| `flow/flow-nginx-enhance/swith-https.md` | 平滑切换至外部HTTPS负载均衡器 (零停机方案) |
| `linux/docs/curl-and-nginx-proxy.md` | nginx proxy_pass 和curl 直接proxy 的区别是什么？ |
| `linux/linux-os-optimize/linux-nginx-system-optimize-calude4-5.md` | GCP Linux 实例系统限制优化脚本 |
| `network/forward-reverse/squid-proxy-nginx.md` | Nginx与Squid代理配置分析 |
| `nginx/README.md` | Nginx 知识库 |
| `nginx/buffer/Proxy_set_header-Connection.md` | 1. **指令的含义和作用** |
| `nginx/buffer/client_header_buffer_size.md` | large-client-header-buffers |
| `nginx/buffer/nginx-request-buffering-claude.md` | Summary |
| `nginx/buffer/nginx-request-buffering-gemini.md` | 解决复杂代理链路中的大文件上传与 Token 超时问题 |
| `nginx/buffer/nginx-request-buffering-studio.md` | Q |
| `nginx/buffer/nginx-request-buffering.md` | Nginx `proxy_request_buffering` 详解 |
| `nginx/buffer/nginx_set_header-connection.md` | Nginx proxy_set_header Connection "" 详细分析 |
| `nginx/buffer/summary-buffer.md` | Q |
| `nginx/config/design-add-nginxconf.md` | Nginx 域名切换 Pipeline 设计 |
| `nginx/docs/Access-Control-Allow-Origin.md` | 在 http 或 server 或每个 location 块内判断 origin 来源 |
| `nginx/docs/Content-Disposition.md` | calude |
| `nginx/docs/GCLB-Certificate-Management.md` | GCLB 层面的证书适配 (GCLB Certificate Management) |
| `nginx/docs/How-to-transmit-nginx-header.md` | How To Transmit Nginx Header |
| `nginx/docs/L7+L4.md` | ✅ 可行性分析 |
| `nginx/docs/Strict-Transport-Security.md` | Strict-Transport-Security (HSTS) Best Practices |
| `nginx/docs/a-c-a-o.md` | grok |
| `nginx/docs/drainingTimeout.md` | Drainingtimeout |
| `nginx/docs/endpoint-with-param.md` | Endpoint With Param |
| `nginx/docs/gcp-certificate-manager-tls.md` | GCP Certificate Manager & mTLS Integration Guide |
| `nginx/docs/hsts-best-practices.md` | HSTS Best Practices for Multi-Layer Architectures |
| `nginx/docs/l4-enhance.md.md` | error_log logs/error.log; |
| `nginx/docs/length.md` | nginx |
| `nginx/docs/multip-in-explorer.md` | my requirement |
| `nginx/docs/nginx+cn.md` | **✅ NGINX 配置（支持 mTLS + CN 校验 + 路由）** |
| `nginx/docs/nginx-110.md` | Google AI Studio |
| `nginx/docs/nginx-111.md` | Nginx 111 |
| `nginx/docs/nginx-499-502.md` | 直接回答 |
| `nginx/docs/nginx-502.md` | 原始配置文件 |
| `nginx/docs/nginx-Reuse-confd-en.md` | Nginx Configuration Management: Unifying Multiple API Entry Points |
| `nginx/docs/nginx-Reuse-confd.md` | configuration |
| `nginx/docs/nginx-Transfer-Encoding.md` | Phenomenon |
| `nginx/docs/nginx-conf.md` | 最佳实践 |
| `nginx/docs/nginx-cpu.md` | Real IP configuration |
| `nginx/docs/nginx-debug-log-example.md` | Nginx Debug日志配置示例 |
| `nginx/docs/nginx-enhance-chatgpt-claude.md` | chatpgtp |
| `nginx/docs/nginx-enhance.md` | TODO |
| `nginx/docs/nginx-error.md` | Q |
| `nginx/docs/nginx-feature.md` | Nginx Feature |
| `nginx/docs/nginx-formart.md` | URL进行编码处理 |
| `nginx/docs/nginx-gzip.md` | 压缩的 MIME 类型 |
| `nginx/docs/nginx-header.md` | user case |
| `nginx/docs/nginx-http2.md` | Nginx启用HTTP/2的好处与配置方法 |
| `nginx/docs/nginx-instance-enhance.md` | Summary |
| `nginx/docs/nginx-l4-proxy.md` | nginx l4 status |
| `nginx/docs/nginx-log.md` | Gemini |
| `nginx/docs/nginx-map-enhance.md` | 更多API映射... |
| `nginx/docs/nginx-map-single-config.md` | 1. 主配置文件 (`nginx.conf`) |
| `nginx/docs/nginx-master-worker.md` | Nginx Master-Worker 架构深度探测报告 |
| `nginx/docs/nginx-multip-ssl-user.md` | GKE + Nginx + Kong：最小改造实现 SameSite Cookie "同站化" |
| `nginx/docs/nginx-multip-ssl.md` | increase proxy buffer size |
| `nginx/docs/nginx-plus-English.md` | F5 NGINX Plus vs. NGINX Open Source In-Depth Assessment Report: Features, Mig... |
| `nginx/docs/nginx-plus.md` | F5 NGINX Plus 与 NGINX 开源版深度评估报告：功能、迁移与 GCP 环境优化 |
| `nginx/docs/nginx-proxy-buffer.md` | Nginx Proxy Buffer |
| `nginx/docs/nginx-proxy-temp.md` | Nginx proxy_temp Permission Denied 深度分析 |
| `nginx/docs/nginx-proxy_hide_header.md` | 第一行：`add_header X-Content-Type-Options nosniff always;` |
| `nginx/docs/nginx-proxy_protocol.md` | status |
| `nginx/docs/nginx-remoteip.md` | 确认上游服务器支持 `proxy_protocol` |
| `nginx/docs/nginx-session-cache.md` | ssl_session_cache |
| `nginx/docs/nginx-size-enhance.md` | 平台上传文件大小与Payload Size限制策略 |
| `nginx/docs/nginx-size.md` | summary |
| `nginx/docs/nginx-split.md` | Nginx `split_clients` 模块详解 |
| `nginx/docs/nginx-status.md` | summary |
| `nginx/docs/nginx-sub-model.md` | nginx `ngx_http_sub_module` 评估 |
| `nginx/docs/nginx-timeout.md` | Q |
| `nginx/docs/nginx-todo.md` | ... 其他配置... |
| `nginx/docs/nginx-upgrade.md` | summary |
| `nginx/docs/nginx-websockets.md` | 配置 Nginx 支持 websockets |
| `nginx/docs/nginx-worker_processes.md` | **✅ 可以设置为** |
| `nginx/docs/proxy-pass/explorer-default-nginx.md` | Explorer: Default Nginx Front Door to ASM Load Balancer |
| `nginx/docs/proxy-pass/nginx+istio-enhance.md` | Nginx 7层代理 + Istio 增强方案 |
| `nginx/docs/proxy-pass/nginx+istio.md` | 问题分析 |
| `nginx/docs/proxy-pass/nginx+simple+chatgpt.md` | Nginx + Runtime Gateway + Pod End-to-End TLS 方案 |
| `nginx/docs/proxy-pass/nginx+simple+claude.md` | Nginx + Runtime Gateway + Pod 端到端 TLS 方案（Claude 整理版） |
| `nginx/docs/proxy-pass/nginx+simple+merge.md` | Nginx + Runtime Gateway + Pod 端到端 TLS 方案（合并定稿版） |
| `nginx/docs/proxy-pass/nginx+simple-chatgpt-eng.md` | Nginx + Runtime Gateway + Pod End-to-End TLS Architecture |
| `nginx/docs/proxy-pass/nginx-proxy-forwarded-proto.md` | Nginx `X-Forwarded-Proto` 深度探索与最佳实践 |
| `nginx/docs/proxy-pass/nginx-proxy-pass-rewrite.md` | Requirement |
| `nginx/docs/proxy-pass/nginx-proxy-pass-usersgent.md` | Nginx proxy_pass默认会重写转发请求的User-Agent头信息 |
| `nginx/docs/proxy-pass/nginx-proxy-pass.md` | 配置分析 |
| `nginx/docs/rolling-process.md` | summary |
| `nginx/docs/ssl_client_certificate_chain.md` | 指定一个 CA 证书链文件用于验证客户端证书 |
| `nginx/docs/tcp_nopush.md` | **问题分析** |
| `nginx/docs/upstream.md` | Upstream |
| `nginx/docs/verify-content-disposition.md` | Verify Content Disposition |
| `nginx/gce-nginx-l4-enhance/debug-flow.md` | GCE Dual NIC Nginx L4 Enhanced Routing - Flow Diagrams |
| `nginx/gce-nginx-l4-enhance/debug-l4-kiro.md` | GCE Dual NIC Nginx L4 Enhanced Routing - Comprehensive Debug & Solutions |
| `nginx/gce-nginx-l4-enhance/debug-l4.md` | GCE L4 Nginx 增强型路由调试与解决方案 |
| `nginx/gce-nginx-l4-enhance/gemini-explorer.md` | 构建弹性架构：Google Cloud 双网卡 Nginx 部署深度解析 |
| `nginx/gce-nginx-l4-enhance/start-sequence.md` | FYI: Checking details |
| `nginx/gce-nginx-l4-enhance/start-service.md` | GCE Dual NIC Nginx - Systemd Service Dependency Configuration |
| `nginx/ingress-control/ingress-control-admission.md` | NGINX Ingress Controller: Admission Webhook 深入解析 |
| `nginx/ingress-control/ingress-controller-tls.md` | **🧩 1. Verify TLS in Kubernetes** |
| `nginx/ingress-control/ingress-fundamentals.md` | Ingress Fundamentals |
| `nginx/ingress-control/ingress-path-rewrite.md` | Ingress Controller 中 API 版本号重写方案 |
| `nginx/ingress-control/ingress-verify/verify-ingress-migrate.md` | TODO |
| `nginx/ingress-control/k3s-install.md` | 检查服务状态 |
| `nginx/ingress-control/merged-scripts.md` | Shell Scripts Collection |
| `nginx/ingress-control/multip-ingress-controller.md` | ChatGPT |
| `nginx/ingress-control/single-ingress-control.md` | Q |
| `nginx/ingress-control/slb.md` | Slb |
| `nginx/ingress-control/summary-tls-issue.md` | **1. Problem Analysis** |
| `nginx/ingress-control/verify-tls.md` | **1. 导出 Secret 并解码** |
| `nginx/nginx-logs/nginx-logrotate-best-practice-limited-disk.md` | 磁盘空间受限环境下的 Nginx Logrotate 最佳实践 |
| `nginx/nginx-logs/nginx-logrotate-frequent-rotation.md` | 高频轮转策略 - 平稳的磁盘空间管理 |
| `nginx/nginx-logs/nginx-reload-logrotate-debug.md` | Nginx Logrotate 配置详解与调试指南 |
| `nginx/nginx-logs/nginx-reload-logrotate.md` | `nginx -s reload` 和 `logrotate` 的关系 |
| `test/docs/nginx-l7-l4.md` | **7 层 (L7) vs 4 层 (L4) 的压力对比** |

### Python Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `ai/docs/Python-ocr.md` | !/usr/bin/env bash |
| `api-service/python-api-demo/explore-deployment-env.md` | 深入探索 Kubernetes Deployment 中的环境变量 |
| `api-service/python-api-demo/python-health-demo/README.md` | Python Health Check & Env Var Demo |
| `docker/docs/docker-python.md` | requirements.txt |
| `gcp/cloud-armor/armor-python/ip_validator.md` | Exit with non-zero status if there are invalid IPs or private IPs |
| `gcp/secret-manage/secert-manage-python-debug.md` | secret manage logs |
| `linux/docs/python-env-define.md` | Python Gunicorn 环境变量覆盖问题排查指南 |
| `nba/docs/python-debug.md` | ... 其他导入保持不变 ... |
| `python/README.md` | Python 知识库 |
| `python/docs/50.md` | 获取每周的工作日数量 |
| `python/docs/bigquery-connect.md` | Define |
| `python/docs/cross-pro-bigquery.md` | Claude |
| `python/docs/dockerfile-source.md` | 使用 Ubuntu 20.04 作为基础镜像 |
| `python/docs/gunicorn-fastapi.md` | 1. WSGI（同步框架，适合传统应用） |
| `python/docs/nba.md` | 发送HTTP请求获取页面内容 |
| `python/docs/pip-install-index.md` | jump the error |
| `python/docs/python-cronjob.md` | 3. 评估使用CronJob的可行性 |
| `python/docs/python-start.md` | uvicorn.workers.UvicornWorker |
| `python/docs/python-uvicorn.md` | summary |
| `python/docs/python-violation-pytest.md` | 错误背景分析 |
| `python/docs/time-sheet.md` | 计算两周循环模式 |
| `python/docs/time2.md` | 获取每周的工作日数量 |
| `python/docs/time3.md` | 计算每周的办公室工作天数 |
| `python/docs/write-python.md` | 配置日志 |

### SQL/BigQuery Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `firestore/docs/firestore-export-to-bigquery.md` | Firestore 数据导出到 BigQuery |
| `gcp/bigquery/big-query-bk.md` | 方案概述 |
| `gcp/bigquery/bigquery-base-practice.md` | Q |
| `gcp/bigquery/bigquery-how-to-insert-update.md` | requirements |
| `gcp/bigquery/bigquey-cmek.md` | Bigquey Cmek |
| `gcp/bigquery/create-table-from-other-pro.md` | Create Table From Other Pro |
| `gcp/bigquery/create-table-schema.md` | create table |
| `gcp/bigquery/numeric.md` | Numeric |
| `gcp/cost/cost-sql.md` | 配置 GKE 集群的资源使用导出 |
| `gcp/sql/eid.md` | Requirements |
| `gcp/sql/gcp-postgresql.md` | 1. **PostgreSQL 的基础概念** |
| `gcp/sql/sync_data.md` | !/bin/bash |
| `psc-sql-flow-demo/Flow.md` | PSC Demo 流程图和架构说明 |
| `psc-sql-flow-demo/README.md` | GKE Pod 通过 PSC 连接 Cloud SQL 演示 |
| `psc-sql-flow-demo/docs/DEPLOYMENT_GUIDE.md` | GKE Pod 通过 PSC 连接 Cloud SQL 部署指南 |
| `psc-sql-flow-demo/docs/TROUBLESHOOTING.md` | 故障排除指南 |
| `psc-sql-flow-demo/scripts/merged-scripts.md` | Shell Scripts Collection |
| `psc-sql-flow-demo/setup/merged-scripts.md` | Shell Scripts Collection |
| `report/docs/Bigquery-create-table.md` | 1. 查看原表结构（使用 --schema 参数只获取表结构） |
| `report/docs/bigquery-add-data.md` | summary |
| `report/docs/bigquery-alert.md` | BigQuery触发器以发送告警？ |
| `report/docs/bigquery-class.md` | 使用Looker Studio进行可视化 |
| `report/docs/bigquery-compare.md` | 定时任务和比对操作 |
| `report/docs/bigquery-cpu-memory.md` | Bigquery Cpu Memory |
| `report/docs/bigquery-pub-sub.md` | 方案4：利用BigQuery和Pub/Sub |
| `report/docs/bigquery-scheduler-functions.md` | 方案1：直接从BigQuery查询并发送邮件 |
| `report/docs/jira-bigquery-studio.md` | Question |
| `report/docs/pm-sql.md` | ChatGPT |
| `skills/gcp/cloud-sql-psc-ports/SKILL.md` | Cloud SQL PSC Port Reference |
| `sql/README.md` | SQL 知识库 |
| `sql/docs/api-table.md` | Api Table |
| `sql/docs/apihistoryonboarding.md` | claude |
| `sql/docs/backup.md` | 1. 使用 BigQuery 快照 (Snapshots) |
| `sql/docs/bigquery-tables.md` | Bigquery Tables |
| `sql/docs/biqquery-sql-cost.md` | dry_run |
| `sql/docs/bq.md` | Bq |
| `sql/docs/bug-query-example.md` | 三平台Bug查询结果示例 |
| `sql/docs/collect-py.md` | Fetch pods data from gke master and send to bucket |
| `sql/docs/collect.md` | Collect |
| `sql/docs/compare-firestore-cloudsql.md` | Firestore 与 Cloud SQL 对比 |
| `sql/docs/connect-table-query.md` | Connect Table Query |
| `sql/docs/cost.md` | summary |
| `sql/docs/duckdb.md` | 100.0% |
| `sql/docs/general-view.md` | 步骤1：提取Schema信息 |
| `sql/docs/group.md` | GROUP BY 子句的详细用法及示例 |
| `sql/docs/id-sql-table.md` | Id Sql Table |
| `sql/docs/id-sql.md` | 三平台Bug查询结果示例 ,比如我把这个结果保存到一个表格中，叫做project.d |
| `sql/docs/join-csv.md` | !/bin/bash |
| `sql/docs/join.md` | 有2个表一个A,比如说A里面有api_name,MID,一个B .api_name,TeamNumber,ORG其中他们都有一个共同的字段比如api_na... |
| `sql/docs/json.md` | Json |
| `sql/docs/newadd-id-uniq.md` | SQL 解析 |
| `sql/docs/paibian.md` | Paibian |
| `sql/docs/pod-memory-cpu.md` | Pod Memory Cpu |
| `sql/docs/push-sink.md` | 加载 Kubernetes 配置 |
| `sql/docs/query-csv-match.md` | Query CSV Match |
| `sql/docs/rn.md` | Rn |
| `sql/docs/select.md` | 插入数据到表中 |
| `sql/docs/sql-5432.md` | Sql 5432 |
| `sql/docs/team-cpu-and-memory-api.md` | summary cost |
| `sql/docs/team-cpu-and-memory.md` | claude |
| `sql/docs/timesheet.md` | Timesheet |
| `sql/docs/union-query.md` | 合并三个表的查询结果并去重 |
| `sql/docs/uniq.md` | Uniq |
| `sql/docs/useful-sql.md` | Useful Sql |
| `sql/docs/v4-claude.md` | only need REPLACE |
| `sql/docs/v4-detail-explan.md` | 1. `WITH` 子查询（公用表表达式，CTE） |
| `sql/docs/v4-fix.md` | 优化要点： |

### SSL/TLS Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `draw/docs/renew-cert.md` | 对应的流程图（Mermaid格式） |
| `gcp/gce/tls-public-lb-flow.md` | GCP TLS 公共负载均衡流程图 |
| `gcp/lb/lb-get-ssl-information.md` | !/usr/bin/env bash |
| `gcp/secret-manage/secret-manage-ssl.md` | size > 64KB |
| `ssl/OpenSSL-curl.md` | OpenSSL as Telnet & Curl Replacement in Kubernetes Pods |
| `ssl/README.md` | SSL / TLS |
| `ssl/certificate-truststore.md` | Certificate Truststore Issue 总结 |
| `ssl/cross-project-fqdn-best-practices.md` | Cross-Project FQDN Best Practices |
| `ssl/current-fqdn-status.md` | Current FQDN Status |
| `ssl/debug-ssl-chatgpt.md` | SSL Debug 理解与脚本说明 |
| `ssl/debug-ssl.md` | 问题分析与用户沟通指南 |
| `ssl/docs/chatgpt/ssl-terminal-1-1.md` | 单一 GKE Gateway + Nginx 前置 TLS 终止实施方案（ssl-terminal-1-1） |
| `ssl/docs/chatgpt/ssl-terminal-1.md` | 单一 GKE Gateway 方案评估（基于 ssl-terminal.md 的“想要的配置”） |
| `ssl/docs/claude/glb-termina-https-3.md` | PoC 操作手册：GLB URL Map 映射 + Nginx 透明代理 + GKE Gateway 路由 |
| `ssl/docs/claude/glb-terminal-2.md` | TLS 终止前移至 GLB 层面的完整探索 |
| `ssl/docs/claude/glb-terminal-https-2.md` | GLB 原生处理映射关系：真正将逻辑从 Nginx 移走 |
| `ssl/docs/claude/glb-terminal-https.md` | GLB 终止客户端 TLS + 后端保持 HTTPS 的合规架构 |
| `ssl/docs/claude/map/glb-url-map-implementation.md` | GLB URL Map 实施方案：长域名跳转 + 短域名透传 + Nginx 零改动 |
| `ssl/docs/claude/map/glb-urlmap-rewrite.md` | 现状：URL Map 的能力边界 |
| `ssl/docs/claude/map/poc-urlmap.md` | No 301 |
| `ssl/docs/claude/map/url-map-merge.md` | GLB URL Map 合并实施方案：长域名重定向到短域名，Nginx 短域名配置保持不变 |
| `ssl/docs/claude/routeaction/explorer-routeaction.md` | GLB 透明代理生产实施手册：长短域名并存，地址栏不变，Nginx 零改动 |
| `ssl/docs/claude/routeaction/flow-url-map.md` | GLB URL Map 长域名透明代理流量编排与逻辑流图 |
| `ssl/docs/claude/routeaction/maps-format-and-verify/merged-scripts.md` | Shell Scripts Collection |
| `ssl/docs/claude/routeaction/maps-format-and-verify/success/8.md` | 8.json 设计说明 |
| `ssl/docs/claude/routeaction/maps-format-and-verify/success/v6.md` | V6 |
| `ssl/docs/claude/routeaction/maps-format-and-verify/success/v7.md` | v7 URL Map 说明 |
| `ssl/docs/claude/routeaction/maps-format-and-verify/url-map-update.md` | URL Map JSON 更新与校验说明 |
| `ssl/docs/claude/routeaction/maps-format-and-verify/url-succ-json.md` | GLB URL Map 透明代理配置解析 (url-succ.json) |
| `ssl/docs/claude/routeaction/maps-format-and-verify/urlmap-quota.md` | GLB URL Map 大规模 API 配置评估方案 (1000+ API 场景) |
| `ssl/docs/claude/routeaction/maps-format-and-verify/urlmaprouteaction.md` | GLB URL Map RouteAction 配置解析 (urlmaprouteaction.json) |
| `ssl/docs/claude/routeaction/maps-format-and-verify/urlmp.md` | GLB URL Map 配置解析 (urlmap.json) |
| `ssl/docs/claude/routeaction/ssl-terminal-2.md` | SSL 终止前移与单一 GKE Gateway 架构分析 |
| `ssl/docs/claude/routeaction/ssl-terminal-effect.md` | 可能继续的探索 |
| `ssl/docs/claude/routeaction/ssl-terminal.md` | 这个服务块只匹配这个域名的请求 |
| `ssl/docs/claude/routeaction/url-map-quota.md` | 编者按：这篇文章里哪些点需要修正 |
| `ssl/docs/claude/routeaction/url-map-routeaction.md` | GLB URL Map RouteAction 实施方案：长域名透明代理，地址栏不变，后端复用短域名 Path 逻辑 |
| `ssl/docs/pem-get-ssl.md` | !/bin/bash |
| `ssl/docs/read-cert.md` | 提取第一个证书到文件 |
| `ssl/docs/root.md` | 企业证书和公共证书的一些辨别 |
| `ssl/docs/ssl-type.md` | 示例证书内容 |
| `ssl/docs/what-ssl.md` | A case thinking |
| `ssl/gcp-glb-ssl-certificate-update.md` | GCP GLB SSL 证书管理方案 |
| `ssl/gskit.md` | 深度探索：GSKit 与 Error 6000 |
| `ssl/ingress-ssl/Readme.md` | 自签名证书生成方法 |
| `ssl/ingress-ssl/merged-scripts.md` | Shell Scripts Collection |
| `ssl/merged-scripts.md` | Shell Scripts Collection |
| `ssl/openssl.md` | Openssl |
| `ssl/verify-baidu.md` | Verify Baidu |
| `terrafrom/docs/tls-role.md` | Q |

### Security Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `OPA-Gatekeeper/constraint-explorers/psp-pod-security.md` | PSP Pod Security Policies — Gatekeeper 版安全策略集 |

### Skills Documentation

| File Path | Title |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `skills/GCP-expert/SKILL.md` | Linux & Cloud Infrastructure Expert |
| `skills/README.md` | Readme |
| `skills/antigravity-skill.md` | How the agent uses skills |
| `skills/architectrue/SKILL.md` | Architectrue |
| `skills/dark-architecture/README.md` | Dark Architecture Diagrams |
| `skills/dark-architecture/SKILL.md` | Dark Architecture Diagram Skill |
| `skills/design/brand-guardian/SKILL.md` | Brand Guardian Agent |
| `skills/design/ui-designer/SKILL.md` | UI Designer Agent |
| `skills/design/ux-researcher/SKILL.md` | UX Researcher Agent |
| `skills/design/visual-storyteller/SKILL.md` | Visual Storyteller Agent |
| `skills/design/whimsy-injector/SKILL.md` | Whimsy Injector Agent |
| `skills/diagram-design/README.md` | Diagram Design |
| `skills/diagram-design/SKILL.md` | Diagram Design |
| `skills/diagram-design/references/onboarding.md` | Onboarding — generate your skin from a website |
| `skills/diagram-design/references/primitive-annotation.md` | Annotation Callout (italic-serif aside) |
| `skills/diagram-design/references/primitive-sketchy.md` | Sketchy Filter (hand-drawn variant) |
| `skills/diagram-design/references/style-guide.md` | Style Guide |
| `skills/diagram-design/references/type-architecture.md` | Architecture |
| `skills/diagram-design/references/type-er.md` | ER / Data Model |
| `skills/diagram-design/references/type-flowchart.md` | Flowchart |
| `skills/diagram-design/references/type-layers.md` | Layer Stack |
| `skills/diagram-design/references/type-nested.md` | Nested Containment |
| `skills/diagram-design/references/type-pyramid.md` | Pyramid / Funnel |
| `skills/diagram-design/references/type-quadrant.md` | Quadrant |
| `skills/diagram-design/references/type-sequence.md` | Sequence |
| `skills/diagram-design/references/type-state.md` | State Machine |
| `skills/diagram-design/references/type-swimlane.md` | Swimlane |
| `skills/diagram-design/references/type-timeline.md` | Timeline |
| `skills/diagram-design/references/type-tree.md` | Tree / Hierarchy |
| `skills/diagram-design/references/type-venn.md` | Venn / Set Overlap |
| `skills/engineering/ai-engineer/SKILL.md` | AI Engineer Agent |
| `skills/engineering/backend-architect/SKILL.md` | Backend Architect Agent |
| `skills/engineering/devops-automator/SKILL.md` | DevOps Automator Agent |
| `skills/engineering/frontend-developer/SKILL.md` | Frontend Developer Agent |
| `skills/engineering/mobile-app-builder/SKILL.md` | Mobile App Builder Agent |
| `skills/engineering/rapid-prototyper/SKILL.md` | Rapid Prototyper Agent |
| `skills/englishmail/SKILL.md` | Englishmail |
| `skills/extract-requirements-target/SKILL.md` | Extract Requirements Target |
| `skills/extract-requirements-target/extract.md` | 提取需求与目标 |
| `skills/files-to-requirements/SKILL.md` | Files To Requirements |
| `skills/files-to-requirements/file-to-re.md` | 文件到需求（Files To Requirements） |
| `skills/gcp/SKILL.md` | Linux & Cloud Infrastructure Expert |
| `skills/gcp/gatekeeper-constraints/SKILL.md` | Gatekeeper Constraints — 探索文档编写规范 |
| `skills/gcp/gatekeeper-multi-tenant-governance/SKILL.md` | Gatekeeper Multi-Tenant Governance — 多租户治理最佳实践 |
| `skills/gcp/gcp-iap-tunnel/SKILL.md` | GCP IAP TCP Tunneling |
| `skills/google-cloud-recipe-onboarding/SKILL.md` | Onboarding to Google Cloud |
| `skills/google-cloud-recipe-onboarding/reference/google-cloud-setup.md` | Google Cloud Setup |
| `skills/maitreya/SKILL.md` | Maitreya (弥勒) - 架构可视化专家 |
| `skills/marketing/app-store-optimizer/SKILL.md` | App Store Optimizer (ASO) Agent |
| `skills/marketing/content-creator/SKILL.md` | Content Creator Agent |
| `skills/marketing/growth-hacker/SKILL.md` | Growth Hacker Agent |
| `skills/marketing/instagram-curator/SKILL.md` | Instagram Curator Agent |
| `skills/marketing/reddit-community-builder/SKILL.md` | Reddit Community Builder Agent |
| `skills/marketing/tiktok-strategist/SKILL.md` | TikTok Strategist Agent |
| `skills/marketing/twitter-engager/SKILL.md` | Twitter Engager Agent |
| `skills/ob/SKILL.md` | GCP API Platform Onboarding Architect |
| `skills/product/feedback-synthesizer/SKILL.md` | Feedback Synthesizer Agent |
| `skills/product/sprint-prioritizer/SKILL.md` | Sprint Prioritizer Agent |
| `skills/product/trend-researcher/SKILL.md` | Trend Researcher Agent |
| `skills/project-management/experiment-tracker/SKILL.md` | Experiment Tracker Agent |
| `skills/project-management/project-shipper/SKILL.md` | Project Shipper Agent |
| `skills/project-management/studio-producer/SKILL.md` | Studio Producer Agent |
| `skills/studio-operations/analytics-reporter/SKILL.md` | Analytics Reporter Agent |
| `skills/studio-operations/finance-tracker/SKILL.md` | Finance Tracker Agent |
| `skills/studio-operations/infrastructure-maintainer/SKILL.md` | Infrastructure Maintainer Agent |
| `skills/studio-operations/legal-compliance-checker/SKILL.md` | Legal Compliance Checker Agent |
| `skills/studio-operations/support-responder/SKILL.md` | Support Responder Agent |
| `skills/testing/api-tester/SKILL.md` | API Tester Agent |
| `skills/testing/performance-benchmarker/SKILL.md` | Performance Benchmarker Agent |
| `skills/testing/test-results-analyzer/SKILL.md` | Test Results Analyzer Agent |
| `skills/testing/tool-evaluator/SKILL.md` | Tool Evaluator Agent |
| `skills/testing/workflow-optimizer/SKILL.md` | Workflow Optimizer Agent |
