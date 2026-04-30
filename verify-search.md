# Summary or Background

- This markdown records my workspace verification information and scripts.

# Verify Scripts Search Results

**Last Updated:** 2026-04-30

## Shell Scripts (`.sh`)

### SSL/TLS Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `ssl/ingress-ssl/verify-tls-secret.sh` | Verifies TLS secret integrity in Kubernetes |
| `ssl/ingress-ssl/check-tls-secret-ns.sh` | Validates TLS secrets in a namespace |
| `ssl/ingress-ssl/check-tls-secret.sh` | Validates a single Kubernetes TLS secret |
| `ssl/ingress-ssl/generate-cert-chain.sh` | Generates certificate chain from TLS secrets |
| `ssl/ingress-ssl/generate-self-signed-cert.sh` | Generates self-signed TLS certificates |
| `ssl/ingress-ssl/create-tls-secret.sh` | Creates TLS secrets in Kubernetes |
| `nginx/ingress-control/check-tls-secret-ns.sh` | Nginx Ingress TLS secrets namespace validation |
| `nginx/ingress-control/check-tls-secret.sh` | Nginx Ingress TLS secret validation |
| `nginx/ingress-control/check-tls-secret2.sh` | Alternative Nginx Ingress TLS validation |
| `ssl/verify-domain-ssl.sh` | Verifies domain SSL certificate configuration |
| `ssl/verify-domain-ssl-enhance.sh` | Enhanced domain SSL verification |
| `ssl/scripts/get-ssl.sh` | Extracts SSL connection info from OpenSSL output |
| `ssl/scripts/get-ssl-all.sh` | Retrieves all SSL information for a domain |
| `ssl/scripts/get-ssl-all-information.sh` | Comprehensive SSL information retrieval |
| `safe/cert/check_eku.sh` | Checks Extended Key Usage (EKU) in certificates |
| `safe/cert/digicert_impact_assessment.sh` | DigiCert certificate impact assessment |

### Gateway/GKE Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gateway/no-gateway/verify-gke-gateway-chatgpt.sh` | Enhanced GKE Gateway verification (GPT) |
| `gateway/no-gateway/verify-gke-gateway-claude.sh` | GKE Gateway verification (Claude) |
| `gateway/no-gateway/verify-gke-gateway.sh` | GKE Gateway configuration verification |
| `gateway/no-gateway/verify-no-gateway-all.sh` | Comprehensive all GKE Gateway API resources check |

### GCP/mTLS Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/mtls/trust-config/verify-trust-configs.sh` | Verifies GCP Certificate Manager Trust Configs |
| `gcp/mtls/trust-config/debug-trust-configs.sh` | Debugs trust config issues |
| `gcp/mtls/mtls-test/get_cert_fingerprint.sh` | Gets certificate fingerprint for mTLS |
| `gcp/mtls/mtls-test/get_cert_fingerprint_chatgpt.sh` | Gets cert fingerprint (GPT) |
| `gcp/mtls/mtls-test/get_cert_fingerprint_claude.sh` | Gets cert fingerprint (Claude) |
| `gcp/mtls/mtls-test/get_cert_fingerprint_no_type.sh` | Gets cert fingerprint without type |
| `gcp/mtls/mtls-test/generate-self-signed-cert.sh` | Generates self-signed cert for mTLS testing |
| `gcp/mtls/mtls-test/generate-self-signed-cert_lmstudio.sh` | Generates self-signed cert via LM Studio |
| `gcp/mtls/mtls-test/gemini.sh` | mTLS testing with Gemini assistance |

### GCS Bucket Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/buckets/verify-buckets-iam-grok.sh` | GCS bucket IAM verification (Grok) |
| `gcp/buckets/verify-buckets-iam.sh` | Verifies GCS bucket IAM bindings |
| `gcp/buckets/verify-buckets.sh` | Comprehensive GCS bucket verification |
| `gcp/buckets/add-bucket-binding.sh` | Adds IAM binding to GCS bucket |
| `gcp/buckets/create-buckets.sh` | Creates GCS buckets |

### GCP Service Account / IAM Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/sa/verify-another-proj-sa.sh` | Verifies Service Account in another project |
| `gcp/sa/verify-gce-sa.sh` | Verifies GCE Service Account |
| `gcp/sa/verify-gke-ksa-iam-authentication.sh` | Verifies GKE IAM-based authentication |
| `gcp/sa/verify-iam-based-authentication-enhance.sh` | Enhanced cross-project IAM authentication validation |
| `gcp/secret-manage/java-examples/verify-gcp-sa.sh` | GCP SA verification for Secret Manager integration |
| `gcp/secret-manage/list-secret/verify-gcp-secretmanage.sh` | Verifies KSA/GSA permission chain to Secret Manager |
| `gcp/migrate-gcp/migrate-secret-manage/05-verify.sh` | Verifies secrets integrity after Secret Manager migration |

### GCP/GKE Status Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/gce/verify-gcp-and-gke-status.sh` | Verifies GCP and GKE status |
| `gcp/gce/verify-mig-status.sh` | Verifies Managed Instance Group status |
| `gcp/gce/rolling/verify-mig-status.sh` | Verifies MIG status with rolling updates |
| `gcp/gce/rolling/rolling-mig-and-verify-status.sh` | Rolling MIG update with status verification |
| `gcp/gce/rolling/rolling-mig-and-verify-status-warp.sh` | Warp-speed rolling MIG update |
| `gcp/gce/rolling/rolling-replace-instance-groups.sh` | Rolling replace instance groups |
| `gcp/gce/rolling/rolling-replace-instance-groups-eng.sh` | Rolling replace instance groups (English) |
| `gcp/gce/rolling/rolling-replace-mig-enhance.sh` | Enhanced MIG rolling replace |
| `gcp/gce/rolling/rolling-replace-mig-enhance-minimax.sh` | Enhanced MIG rolling replace (Minimax) |
| `gcp/gce/get_instance_timestamps.sh` | Gets GCE instance timestamps |
| `gcp/gce/get_instance_uptime.sh` | Gets GCE instance uptime |
| `gcp/gce/instance-uptime-gemini.sh` | Gets instance uptime with Gemini |

### DNS Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `dns/dns-peering/dns-fqdn-verify.sh` | Verifies DNS FQDN resolution |
| `dns/dns-peering/verify-dns-fqdn.sh` | Verifies DNS FQDN |
| `dns/dns-peering/verify-pub-priv-ip-glm-ipv6.sh` | Verifies pub/private IP and GLM IPv6 |
| `dns/dns-peering/verify-pub-priv-ip-glm-ok.sh` | Verifies pub/private IP and GLM |
| `dns/dns-peering/verify-pub-priv-ip.sh` | Verifies public and private IPs |
| `dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6-ok.sh` | GitHub: pub/priv IP and GLM IPv6 |
| `dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6-enhanced.sh` | Enhanced pub/priv IP and GLM IPv6 |
| `dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6.sh` | GitHub: pub/priv IP and GLM IPv6 |
| `dns/dns-peering/dns-query.sh` | DNS query script |
| `dns/dns-peering/dns-query-eng.sh` | DNS query (English version) |
| `dns/dns-peering/dns-peering-claude.sh` | DNS peering with Claude assistance |
| `dns/dns-peering/dns-peering-eng.sh` | DNS peering (English) |
| `dns/docs/dnsrecord-add-del.sh` | Adds/deletes DNS records |
| `dns/docs/dnsrecord-add-del-eng.sh` | Adds/deletes DNS records (English) |
| `dns/docs/dnsrecord-add-script.sh` | DNS record add script |
| `dns/docs/dnsrecord-add-script-eng.sh` | DNS record add script (English) |
| `dns/docs/dnsrecord-del-script-eng.sh` | DNS record delete script (English) |
| `dns/docs/private-access/create-private-access.sh` | Creates private access endpoint |
| `dns/docs/private-access/create-private-access-success-one-by-one.sh` | Creates private access (one-by-one) |
| `dns/docs/private-access/create-claude.sh` | Creates private access (Claude) |
| `dns/docs/private-access/create-claude-one-by-one.sh` | Creates private access (Claude, one-by-one) |
| `dns/dns-peering/Docker-dns/docker-build-run.sh` | Builds and runs Docker DNS container |

### K8s Pod/Health Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `k8s/custom-liveness/deploy-and-verify.sh` | Deploys Squid proxy with health check |
| `k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup.sh` | Verifies pod startup measurements |
| `k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup_fixed_en.sh` | Verifies pod startup and gets target URL |
| `k8s/labels/add/05_verify.sh` | Verifies labels applied to deployments |
| `k8s/lib/pod_health_check_lib.sh` | Reusable K8s pod health verification library |
| `k8s/scripts/batch_health_check.sh` | Batch health checks for multiple pods |
| `k8s/scripts/debug_health_check.sh` | Debugging tool for pod health checks |
| `ali/k8s-migration-proxy/scripts/verify-connectivity.sh` | Verifies connectivity during K8s migration |
| `ali/scripts/verify-e2e.sh` | End-to-end verification for K8s resources |
| `k8s/custom-liveness/explore-startprobe/get-deploy-health-url.sh` | Gets deployment health check URL |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhance.sh` | Enhanced pod startup measurement |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_fixed.sh` | Fixed pod startup measurement |
| `k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup_fixed.sh` | Verifies fixed pod startup |
| `k8s/custom-liveness/deploy-and-test.sh` | Deploys and tests custom liveness |
| `k8s/custom-liveness/build-custom-image.sh` | Builds custom liveness probe image |
| `k8s/scripts/measure_startup_simple.sh` | Simple pod startup measurement |
| `k8s/scripts/minimal_test.sh` | Minimal K8s test script |
| `k8s/scripts/pod-system-version.sh` | Gets pod system version |
| `k8s/scripts/pod_exec.sh` | Executes command in pod |
| `k8s/scripts/pod_measure_startup_bak.sh` | Pod startup measurement (backup) |
| `k8s/scripts/pod_measure_startup_fixed.sh` | Pod startup measurement (fixed) |
| `k8s/scripts/pod_status.sh` | Checks pod status |
| `k8s/scripts/simple_test.sh` | Simple K8s test |
| `k8s/debug-pod/test-script.sh` | Tests debug pod script |
| `k8s/debug-pod/side-optimized.sh` | Optimized sidecar debug pod |
| `k8s/images/k8s-image-replace.sh` | Replaces K8s pod images |
| `k8s/images/verify_pod_image_pull_time.sh` | Verifies pod image pull time |
| `k8s/images/verify_pod_image_pull_time_sh.sh` | Verifies image pull time (shell) |
| `k8s/images/images-update.sh` | Updates container images |
| `k8s/labels/add-deployment-labels.sh` | Adds labels to deployments |
| `k8s/labels/add-deployment-labels-flexible.sh` | Adds labels with flexible matching |
| `k8s/labels/add/01_export_data.sh` | Exports deployment data for labeling |
| `k8s/labels/add/02_generate_mapping.sh` | Generates label mapping |
| `k8s/labels/add/03_backup.sh` | Backs up before labeling |
| `k8s/labels/add/04_apply_labels.sh` | Applies labels to deployments |
| `k8s/labels/add/06_rollback.sh` | Rolls back label changes |
| `k8s/labels/deployment-helper.sh` | Deployment labeling helper |
| `k8s/labels/flexible.sh` | Flexible labeling script |
| `k8s/k8s-scale/optimize_k8s_resources.sh` | Optimizes K8s resource allocations |
| `k8s/k8s-scale/optimize_k8s_resources_v2.sh` | Optimizes K8s resources (v2) |
| `k8s/lib/test_lib.sh` | K8s library test script |
| `k8s/qnap-k8s/init-k8s.sh` | Initializes K8s on QNAP |
| `k8s/qnap-k8s/install-k8s-deps.sh` | Installs K8s dependencies on QNAP |
| `k8s/qnap-k8s/test-qnap-detection.sh` | Tests QNAP K8s detection |
| `k8s/Mytools/init.sh` | K8s mytools initialization |
| `k8s/Mytools/aliases.sh` | K8s kubectl aliases |
| `k8s/Mytools/example-custom.sh` | Custom K8s example |
| `k8s/Mytools/mount-config-template.sh` | Mount config template |
| `k8s/Mytools/run-container.sh` | Runs container in K8s |
| `k8s/scripts/git.sh` | Git operations in K8s context |

### Kong Data Plane Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `kong/kongdp/verify-dp.sh` | Comprehensive Kong DP verification |
| `kong/kongdp/verify-dp-status-gemini.sh` | Kong DP status verification (Gemini) |
| `kong/kongdp/verify-dp-status.sh` | Kong DP pod health and CP connectivity check |
| `kong/kongdp/verify-dp-summary.sh` | Dashboard view of Kong DP status |
| `kong/kongdp/compare-dp.sh` | Compares Kong DP configurations |
| `kong/kongdp/compare-dp-eng.sh` | Compares Kong DP (English) |

### Security/CVE Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `safe/cwe/check_ubuntu_cve_status.sh` | Queries Ubuntu CVE fix status |
| `safe/cwe/verify.sh` | Checks CVE ID status in Ubuntu notices |
| `safe/cwe/verify-enhance.sh` | Enhanced CVE verification (shell) |
| `safe/cwe/verify-enhance-html.sh` | CVE verification with BeautifulSoup HTML parsing |
| `safe/gcp-safe/verify-kms-enhanced.sh` | GCP KMS cross-project encryption validation |
| `safe/gcp-safe/debug-test.sh` | Debug test for GCP safe operations |
| `safe/gcp-safe/quick-test.sh` | Quick test for GCP safe operations |
| `safe/gcp-safe/test-arithmetic.sh` | Arithmetic test for GCP safe |
| `safe/gcp-safe/test-permissions.sh` | Permission test for GCP safe |
| `safe/get-token/curl-token.sh` | Gets auth token via curl |

### GCP Cloud Run Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/cloud-run/cloud-run-automation/cloud-run-housekeep.sh` | Cloud Run housekeeping automation |
| `gcp/cloud-run/cloud-run-job-housekeep.sh` | Cloud Run job housekeeping |
| `gcp/cloud-run/cloud-run-job-migration-jq.sh` | Cloud Run job migration with jq |
| `gcp/cloud-run/cloud-run-job-migration-jq-fixed.sh` | Cloud Run job migration (fixed jq) |
| `gcp/cloud-run/cloud-run-job-migration-script.sh` | Cloud Run job migration script |
| `gcp/cloud-run/container-validation/startup-validator.sh` | Validates container startup |
| `gcp/cloud-run/container-validation/startup-validator-v2.sh` | Startup validator v2 |
| `gcp/cloud-run/container-validation/startup-validator-v3.sh` | Startup validator v3 |
| `gcp/cloud-run/container-validation/build-with-validation.sh` | Builds container with validation |
| `gcp/cloud-run/container-validation/app-entrypoint.sh` | Container app entrypoint |
| `gcp/cloud-run/extract-env-vars.sh` | Extracts Cloud Run env vars |
| `gcp/cloud-run/verify/image-branch-validation.sh` | Validates image branch |
| `gcp/cloud-run/verify/secure-cloud-run-deploy.sh` | Secure Cloud Run deployment |

### GCP MIG/DNS Migration Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/migrate-gcp/get-ns-information.sh` | Gets namespace information from GKE |
| `gcp/migrate-gcp/get-ns-stats.sh` | Gets namespace statistics |
| `gcp/migrate-gcp/get-ns-stats-optimized.sh` | Gets namespace stats (optimized) |
| `gcp/migrate-gcp/get-ns-stats-kiro-enhance.sh` | Gets namespace stats (Kiro enhanced) |
| `gcp/migrate-gcp/get-ns-stats-gemini.sh` | Gets namespace stats (Gemini) |
| `gcp/migrate-gcp/get-ns-info-fast.sh` | Fast namespace info retrieval |
| `gcp/migrate-gcp/migrate-dns/01-discovery.sh` | DNS migration discovery |
| `gcp/migrate-gcp/migrate-dns/02-prepare-target.sh` | Prepares target for DNS migration |
| `gcp/migrate-gcp/migrate-dns/03-execute-migration.sh` | Executes DNS migration |
| `gcp/migrate-gcp/migrate-dns/04-rollback.sh` | Rolls back DNS migration |
| `gcp/migrate-gcp/migrate-dns/05-cleanup.sh` | Cleans up after DNS migration |
| `gcp/migrate-gcp/migrate-dns/config.sh` | DNS migration config |
| `gcp/migrate-gcp/migrate-dns/migrate-dns.sh` | DNS migration main script |
| `gcp/migrate-gcp/migrate-secret-manage/01-setup.sh` | Secret Manager migration setup |
| `gcp/migrate-gcp/migrate-secret-manage/02-discover.sh` | Discovers secrets to migrate |
| `gcp/migrate-gcp/migrate-secret-manage/03-export.sh` | Exports secrets |
| `gcp/migrate-gcp/migrate-secret-manage/04-import.sh` | Imports secrets to target |
| `gcp/migrate-gcp/migrate-secret-manage/06-update-apps.sh` | Updates apps after secret migration |
| `gcp/migrate-gcp/migrate-secret-manage/config.sh` | Secret migration config |
| `gcp/migrate-gcp/migrate-secret-manage/migrate-secrets.sh` | Secret migration main script |
| `gcp/migrate-gcp/pop-migrate/migrate.sh` | POP migration script |
| `gcp/migrate-gcp/pop-migrate/scripts/export.sh` | POP migration export |
| `gcp/migrate-gcp/pop-migrate/scripts/import.sh` | POP migration import |
| `gcp/migrate-gcp/pop-migrate/scripts/validate.sh` | POP migration validation |
| `gcp/migrate-gcp/pop-migrate/scripts/cleanup.sh` | POP migration cleanup |
| `gcp/migrate-gcp/pop-migrate/test-no-yq.sh` | Tests POP migration without yq |

### GCP ASM/Istio Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/asm/trace-istio.sh` | Traces Istio traffic |
| `gcp/asm/trace-istio-and-export.sh` | Traces and exports Istio data |
| `gcp/asm/gloo/yamls/e2e-validation.sh` | Gloo e2e validation |
| `gcp/asm/gloo/yamls/minimax/e2e-validation.sh` | Gloo e2e validation (Minimax) |

### GCP Secret Manager Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/secret-manage/list-secret/list-all-secrets.sh` | Lists all secrets in Secret Manager |
| `gcp/secret-manage/list-secret/list-all-secrets-permissions.sh` | Lists secrets with permissions |
| `gcp/secret-manage/list-secret/list-all-secrets-permissions-parallel.sh` | Lists secrets (parallel) |
| `gcp/secret-manage/list-secret/list-all-secrets-optimized.sh` | Lists secrets (optimized) |
| `gcp/secret-manage/list-secret/list-all-secrets-simple-optimized.sh` | Lists secrets (simple optimized) |
| `gcp/secret-manage/list-secret/list-secrets-groups-sa.sh` | Lists secrets grouped by SA |
| `gcp/secret-manage/list-secret/filter-secrets.sh` | Filters secrets by criteria |
| `gcp/secret-manage/list-secret/benchmark-comparison.sh` | Benchmarks secret listing approaches |
| `gcp/secret-manage/list-secret/auto-select-version.sh` | Auto-selects secret version |
| `gcp/secret-manage/list-secret/test-increment-fix.sh` | Tests increment fix |
| `gcp/secret-manage/java-examples/setup-gcp.sh` | Sets up GCP for Java examples |
| `gcp/secret-manage/java-examples/k8s/secret-setup.sh` | Sets up K8s secret for Java |
| `gcp/secret-manage/secret-manager-admin.sh` | Secret Manager admin operations |

### GCP LB Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/lb/lb-get-ssl-infor.sh` | Gets SSL information for LB |
| `gcp/lb/lb-poc-gen.sh` | LB POC generator |
| `gcp/lb/lb-poc-from-mig.sh` | LB POC from MIG |
| `gcp/lb/refer-lb-create.sh` | Reference LB creation script |

### Ali Cloud Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `ali/ali-dns/dns-batch-update.sh` | Batch updates Ali DNS records |
| `ali/ali-dns/dns-config.sh` | Configures Ali DNS |
| `ali/k8s-migration-proxy/deploy.sh` | Deploys K8s migration proxy |
| `ali/k8s-migration-proxy/scripts/deploy-external-services.sh` | Deploys external services |
| `ali/k8s-migration-proxy/scripts/manage-ingress.sh` | Manages ingress during migration |
| `ali/k8s-migration-proxy/scripts/test-ingress.sh` | Tests ingress during migration |
| `ali/k8s-migration-proxy/validate.sh` | Validates K8s migration proxy |
| `ali/k8s-migration-proxy/test-proxy.sh` | Tests K8s migration proxy |
| `ali/migrate-plan/plan1/k8s-ingress-migration-optimized.sh` | Optimized K8s ingress migration |
| `ali/migrate-plan/plan1/poc-rewrite/migrate-commands.sh` | Migration commands for POC rewrite |
| `ali/migrate-plan/plan1/poc-rewrite/poc-test.sh` | POC rewrite test |
| `ali/migrate-plan/plan1/poc-rewrite/quick-migrate.sh` | Quick migration script |
| `ali/scripts/k8s-resources.sh` | K8s resource management |
| `ali/scripts/migrate-exclude-secret.sh` | Migrates excluding secrets |
| `ali/scripts/namespace-status.sh` | Checks namespace status |
| `ali/secrets-backup/lex/apply-secrets.sh` | Applies secret backups |

### GCP General/Info Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/gcp-infor/gcp-explore.sh` | Explores GCP configuration |
| `gcp/gcp-infor/gcp-functions.sh` | GCP utility functions |
| `gcp/gcp-infor/assistant/gcp-preflight.sh` | GCP preflight checks |
| `gcp/gcp-infor/assistant/run-verify.sh` | Runs GCP verification |
| `gcp/gcp-infor/linux-scripts/gcp-linux-env.sh` | GCP Linux environment setup |
| `gcp/gcp-infor/linux-scripts/gcp-validate.sh` | GCP Linux validation |
| `gcp/tools/git.sh` | Git operations for GCP repos |
| `gcp/pub-sub/pub-sub-cmek/pubsub-cmek-manager.sh` | Pub/Sub CMEK manager |
| `gcp/cloud-armor/ip_filter.sh` | Cloud Armor IP filter |
| `gcp/cloud-armor/ip_filter_maxos_error.sh` | Cloud Armor IP filter (MaxOS error) |
| `gcp/sql/process_data.sh` | Processes SQL data |

### Java/Debug Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `java/java-auth/simple-https-demo/generate-cert.sh` | Generates cert for Java HTTPS demo |
| `java/java-pom/ci-diagnostic-script.sh` | CI diagnostic script for Java Maven |
| `java/java-scan/scripts/pipeline-integration.sh` | Pipeline integration for Java scanner |
| `java/scripts/debug-java-pod.sh` | Debugs Java pod in K8s |
| `java/scripts/debug-pod.sh` | Debugs K8s pod |
| `java/scripts/test-dry-run.sh` | Dry run test script |

### Linux/Optimization Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `linux/linux-os-optimize/Linux-system-optimize.sh` | Linux system optimization |
| `linux/linux-os-optimize/linux-system-optimize.sh` | Linux system optimization script |
| `linux/linux-os-optimize/linux-nginx-system-optimize.sh` | Linux Nginx optimization |
| `linux/linux-os-optimize/linux-nginx-system-optimize-calude4-5.sh` | Linux Nginx optimization (Claude 4.5) |
| `linux/linux-os-optimize/linux-system-optimize-gemini.sh` | Linux optimization (Gemini) |
| `linux/linux-os-optimize/linux-system-optimize-tt.sh` | Linux optimization (TT) |
| `linux/linux-os-optimize/universal_optimize.sh` | Universal optimization script |
| `linux/scripts/csv-format-bard.sh` | Formats CSV for Bard |
| `linux/scripts/git.sh` | Git scripts for Linux |

### howgit Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `howgit/scripts/git_changes_stats.sh` | Git change statistics |
| `howgit/scripts/git_detailed_stats.sh` | Detailed git statistics |
| `howgit/scripts/git_recent_changes.sh` | Recent git changes |
| `howgit/scripts/github_api_stats.sh` | GitHub API statistics |

### Safe/Security Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `safe/scripts/basic-domain-explorer.sh` | Basic domain exploration |
| `safe/scripts/basic_recon.sh` | Basic reconnaissance |
| `safe/scripts/domain_intel.sh` | Domain intelligence gathering |
| `safe/scripts/explorer-domain-claude.sh` | Domain exploration (Claude) |
| `safe/scripts/git.sh` | Git operations for security |

### kong Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `kong/scripts/git.sh` | Git operations for Kong |

### K8s Custom Liveness Enhanced

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_gemini.sh` | Enhanced pod measurement (Gemini) |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v2.sh` | Enhanced pod measurement v2 |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v3.sh` | Enhanced pod measurement v3 |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v4.sh` | Enhanced pod measurement v4 |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v5.sh` | Enhanced pod measurement v5 |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_enhanced_v6.sh` | Enhanced pod measurement v6 |
| `k8s/custom-liveness/explore-startprobe/pod_measure_startup_fixed_en.sh` | Fixed pod measurement (English) |

---

## Markdown Documents (`.md`)

### GKE Gateway Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gateway/no-gateway/verify-gateway-enhance.md` | Enhanced GKE Gateway verification procedures |
| `gateway/no-gateway/verify-gke-gateway.md` | GKE Gateway verification scripts and procedures |
| `gateway/no-gateway/no-gateway-design.md` | No-Gateway design documentation |
| `gateway/no-gateway/no-gateway-gcp-design-gemini.md` | No-Gateway GCP design (Gemini) |
| `gateway/no-gateway/no-gateway-path-flow.md` | No-Gateway path flow |
| `gateway/no-gateway/explorer-no-gateway.md` | No-Gateway explorer |
| `gateway/no-gateway/explorer-no-gateway-gemini.md` | No-Gateway explorer (Gemini) |
| `gateway/no-gateway/no-gateway-2.md` | No-Gateway v2 documentation |
| `gateway/no-gateway/gateway-safe-control.md` | Gateway safe control |
| `gateway/no-gateway/glb-path.md` | GLB path documentation |
| `gateway/no-gateway/HealthCheckPolicy.md` | HealthCheckPolicy reference |
| `gateway/no-gateway/Gateway-API-allowedRoutes.md` | Gateway API allowedRoutes |
| `gateway/no-gateway/TODO.md` | Gateway TODO list |
| `gateway/no-gateway/warp-expolorer-nogateway.md` | Warp explorer for no-gateway |
| `gateway/no-gateway/merged-scripts.md` | Merged gateway scripts |
| `gateway/version-control/core-concepts.md` | Version control core concepts |
| `gateway/version-control/core-concepts-en.md` | Version control core concepts (English) |
| `gateway/version-control/no-gateway-version-control.md` | No-gateway version control |
| `gateway/version-control/no-gateway-version-control-en.md` | No-gateway version control (English) |
| `gateway/version-control/no-gateway-version-control-cn.md` | No-gateway version control (Chinese) |
| `gateway/version-control/no-gateway-version-ingress-control.md` | Ingress control version management |
| `gateway/version-control/no-gateway-version-smoth-switch.md` | Smooth version switching |
| `gateway/version-control/no-gateway-version-smoth-switch-en.md` | Smooth version switching (English) |
| `gateway/version-control/verify-no-gateway-version-change.md` | Version change verification |
| `gateway/version-control/explorer-multi-gateway.md` | Multi-gateway explorer |
| `gateway/version-control/qwen-ingress-version-control.md` | Qwen ingress version control |

### GCP/mTLS Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gcp/mtls/SSLVerifyDepth.md` | SSL verify depth documentation |
| `gcp/mtls/glb-verify-curl.md` | Verifying GLB using curl |
| `gcp/mtls/glb-verify.md` | Guide for verifying GLB mTLS configurations |
| `gcp/mtls/mtls-test/generate-ca-and-verify-ca.md` | Generating and verifying CA for mTLS |
| `gcp/mtls/mtls-verify.md` | mTLS verification guide |
| `gcp/mtls/onboarding-verify.md` | mTLS onboarding verification guide |
| `gcp/mtls/verify-user-certificate.md` | Verifying user certificates in mTLS |
| `gcp/mtls/trust-config/verify-trust-configs-guide.md` | Trust config verification guide |
| `gcp/mtls/trust-config/trust-config-flow.md` | Trust config flow |
| `gcp/mtls/trust-config/mtls-key.md` | mTLS key management |
| `gcp/mtls/trust-config/mtls-trustconfig-nginx.md` | mTLS trustconfig for Nginx |
| `gcp/mtls/trust-config/trust-config-backup.md` | Trust config backup guide |
| `gcp/mtls/trust-config/trust-config-lock.md` | Trust config locking |
| `gcp/mtls/trust-config/trustconfig-multip-ca.md` | Multi-CA trust config |
| `gcp/mtls/trust-config/add-trust-config.md` | Adding trust config |
| `gcp/mtls/glb-mtls.md` | GLB mTLS configuration |
| `gcp/mtls/glb-mtls-nginx.md` | GLB mTLS for Nginx |
| `gcp/mtls/mtls-nginx.md` | mTLS for Nginx |
| `gcp/mtls/mtls-cn.md` | mTLS in China region |
| `gcp/mtls/mtls-table.md` | mTLS configuration table |
| `gcp/mtls/multiple-mtls.md` | Multiple mTLS configurations |
| `gcp/mtls/onboarding-ca.md` | mTLS CA onboarding |
| `gcp/mtls/onboarding-ca-with-fingerprint.md` | mTLS CA onboarding with fingerprint |
| `gcp/mtls/onboarding-whitelist.md` | mTLS whitelist onboarding |
| `gcp/mtls/onboarding-automation.md` | mTLS onboarding automation |
| `gcp/mtls/https-glb-pass-client.md` | HTTPS GLB pass client cert |
| `gcp/mtls/intermediate-ca.md` | Intermediate CA for mTLS |
| `gcp/mtls/renew.md` | mTLS certificate renewal |
| `gcp/mtls/merged-scripts.md` | Merged mTLS scripts |
| `gcp/mtls/migrate-cloud-armor.md` | mTLS Cloud Armor migration |
| `gcp/mtls/migrate-nginx.md` | mTLS Nginx migration |

### GCS Bucket Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gcp/buckets/VERIFY-README.md` | GCS bucket verification README |
| `gcp/buckets/verify-buckets-iam.md` | GCS bucket IAM verification docs |
| `gcp/buckets/QUICKREF.md` | GCS bucket quick reference |
| `gcp/buckets/README.md` | GCS buckets README |
| `gcp/buckets/buckets-add-binging-sa.md` | Adding bucket bindings for SAs |
| `gcp/buckets/buckets-des.md` | GCS bucket descriptions |
| `gcp/buckets/buckets-migrate.md` | GCS bucket migration |
| `gcp/buckets/buckets-role.md` | GCS bucket roles |
| `gcp/buckets/buckets-version-lifecycle.md` | Bucket versioning and lifecycle |
| `gcp/buckets/merged-scripts.md` | Merged bucket scripts |

### GCP Service Account / IAM Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gcp/sa/verify-gcp-sa.md` | GCP Service Account verification |
| `gcp/sa/verify-iam-based-authentication-enhance.md` | Enhanced IAM authentication verification |
| `gcp/sa/verify-sa-iam-based-authentication.md` | IAM-based SA authentication verification |
| `gcp/secret-manage/verify-sa.md` | Secret Manager SA verification |
| `gcp/sa/active-serviceaccount.md` | Active service account management |
| `gcp/sa/iam-service-account.md` | IAM service account patterns |
| `gcp/sa/service-agent.md` | Service agent documentation |
| `gcp/sa/gcp-sa-housekeep.md` | GCP SA housekeeping |
| `gcp/sa/SA-Control-and-Compliance.md` | SA control and compliance |

### DNS Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `dns/docs/verify-dnspeering.md` | DNS peering verification |
| `dns/dns-peering/README.md` | DNS peering README |
| `dns/dns-peering/dns-query-peering.md` | DNS query for peering |
| `dns/docs/dns-peerning.md` | DNS peering guide |
| `dns/docs/dns-v2.md` | DNS v2 documentation |
| `dns/docs/dns-svc-compare.md` | DNS service comparison |
| `dns/docs/dns-migrate.md` | DNS migration guide |
| `dns/docs/kube-dns.md` | Kube DNS documentation |
| `dns/docs/migrate-dns-enhance.md` | Enhanced DNS migration |
| `dns/docs/private-access/create-private-access-usage.md` | Private access usage |
| `dns/docs/private-access/create-claude-usage.md` | Private access usage (Claude) |
| `dns/docs/shared-logs.md` | Shared DNS logs |
| `dns/docs/priority-response.md` | DNS priority response |
| `dns/docs/a.md` | A record documentation |
| `dns/docs/a-and-wirdcard.md` | A and wildcard records |
| `dns/docs/apply-cname.md` | Applying CNAME records |
| `dns/docs/apply-wirdcard-cert.md` | Applying wildcard certificates |
| `dns/docs/cloud-dns.md` | Cloud DNS guide |
| `dns/docs/dns-length.md` | DNS record length limits |
| `dns/docs/dns-log.md` | DNS logging |
| `dns/docs/dnsrecord-add-script-usage.md` | DNS record add script usage |
| `dns/docs/dnsrecord-del-script-usage.md` | DNS record delete script usage |
| `dns/docs/loon-dns.md` | Loon DNS documentation |
| `dns/docs/s.md` | S record documentation |

### Nginx Ingress Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `nginx/docs/verify-content-disposition.md` | Content-Disposition header verification |
| `nginx/ingress-control/ingress-verify/verify-ingress-migrate.md` | Nginx Ingress migration verification |
| `nginx/ingress-control/verify-tls.md` | TLS verification for Nginx Ingress |

### K8s Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `k8s/custom-liveness/explore-startprobe/openssl-verify-health.md` | OpenSSL health verification |
| `k8s/docs/verify-kube-dns.md` | Kube DNS verification |
| `k8s/docs/verify-namespace-label.md` | Namespace label verification |
| `k8s/docs/pod-start.md` | Pod start procedures |
| `k8s/docs/pod-restart.md` | Pod restart documentation |
| `k8s/docs/pod-lifecycle.md` | Pod lifecycle |
| `k8s/docs/enhance-pod-start.md.md` | Enhanced pod start |
| `k8s/docs/no-root-deployment.md` | Non-root deployment guide |
| `k8s/docs/non-root.md` | Non-root container guide |
| `k8s/docs/kill-pod.md` | Pod termination guide |
| `k8s/docs/why-context.md` | Kubeconfig context explanation |
| `k8s/docs/why-needhttps-intra-ns.md` | HTTPS within namespace rationale |
| `k8s/docs/housekeep.md` | K8s housekeeping |
| `k8s/docs/k8s-cluster-secret.md` | K8s cluster secrets |
| `k8s/docs/analyse-memory-cpu.md` | Memory and CPU analysis |
| `k8s/docs/pdb-core.md` | PDB core concepts |
| `k8s/docs/pdb-effect.md` | PDB effect documentation |
| `k8s/docs/pdb-namespace.md` | PDB per namespace |
| `k8s/docs/pdb-time.md` | PDB time-based configuration |
| `k8s/docs/temp-stop-pdb.md` | Temporarily stop PDB |
| `k8s/docs/dynamic-pdb.md` | Dynamic PDB configuration |
| `k8s/docs/Release-pdb.md` | PDB during releases |
| `k8s/docs/rolling+affinity+pdb.md` | Rolling update with affinity and PDB |
| `k8s/docs/strategy.md` | Deployment strategy |
| `k8s/docs/evict.md` | Pod eviction guide |
| `k8s/docs/syncloop-status.md` | Sync loop status |
| `k8s/docs/hpa-replicas.md` | HPA replica management |
| `k8s/docs/hpa-size-alert.md` | HPA size alerting |
| `k8s/docs/hpa-size.md` | HPA sizing guide |
| `k8s/docs/hpa-with-maxunavailable.md` | HPA with maxUnavailable |
| `k8s/docs/kube-path-hpa.md` | HPA kube path |
| `k8s/docs/networkpolicy-egress-svc.md` | NetworkPolicy egress to service |
| `k8s/docs/networkpolicy.md` | NetworkPolicy guide |
| `k8s/docs/base-networkpolicy.md` | Base NetworkPolicy |
| `k8s/docs/netwrokpolicy.md` | NetworkPolicy reference |
| `k8s/docs/gke-networkpolicy-except.md` | GKE NetworkPolicy exceptions |
| `k8s/docs/affinity.md` | Pod affinity |
| `k8s/docs/affinity-add-new-logic.md` | Affinity with new logic |
| `k8s/docs/summary-affinity.md` | Affinity summary |
| `k8s/docs/deployment2.md` | Deployment guide v2 |
| `k8s/docs/detail-deployment.md` | Detailed deployment |
| `k8s/docs/deploy-type.md` | Deployment types |
| `k8s/docs/deployment-error.md` | Deployment errors |
| `k8s/docs/k8s-exec.md` | kubectl exec guide |
| `k8s/docs/redis.md` | Redis in K8s |
| `k8s/docs/hostalias.md` | HostAlias in K8s |
| `k8s/docs/trigger-appd.md` | Triggering AppD |
| `k8s/docs/appd-init-container.md` | AppD init container |
| `k8s/docs/kube-crd.md` | K8s CRD guide |
| `k8s/docs/kube-neat.md` | KubeNeat tool |
| `k8s/docs/kubectl-event.md` | kubectl events |
| `k8s/docs/configmap-daemon.md` | ConfigMap with DaemonSet |
| `k8s/docs/configmap.md` | ConfigMap guide |
| `k8s/docs/cm.md` | ConfigMap reference |
| `k8s/docs/secret-enhance.md` | Secret enhancement |
| `k8s/docs/k8s-export-secret.md` | Exporting secrets |
| `k8s/docs/k8s-get-Replicas.md` | Getting replica info |
| `k8s/docs/k8s-request-limit.md` | Request and limit configuration |
| `k8s/docs/k8s-request.md` | Request configuration |
| `k8s/docs/k8s-resource-summary.md` | Resource summary |
| `k8s/docs/res.md` | Resource documentation |
| `k8s/docs/except.md` | Exception handling |
| `k8s/docs/k8s-pod-stat-completed.md` | Pod statistics for completed pods |
| `k8s/docs/mini-change.md` | Minimal changes |
| `k8s/docs/edit-deployment.md` | Editing deployments |
| `k8s/docs/intcontainer-container.md` | Init container guide |
| `k8s/docs/container-pod.md` | Container vs pod |
| `k8s/docs/role.md` | RBAC role guide |
| `k8s/docs/liveness.md` | Liveness probe |
| `k8s/docs/readiness.md` | Readiness probe |
| `k8s/docs/cronjob.md` | CronJob guide |
| `k8s/docs/job.md` | Job guide |
| `k8s/docs/endpoint.md` | Endpoint documentation |
| `k8s/docs/etcd.md` | etcd operations |
| `k8s/docs/k8s-feature.md` | K8s feature flags |
| `k8s/docs/no-medata.md` | No metadata configuration |
| `k8s/docs/set-image.md` | Set container image |
| `k8s/docs/update-images.md` | Update container images |
| `k8s/docs/ingress.md` | Ingress guide |
| `k8s/docs/egress.md` | Egress configuration |
| `k8s/docs/stress.md` | Stress testing |
| `k8s/docs/filter-namespace.md` | Filter by namespace |
| `k8s/docs/get-ns-dep.md` | Get namespace deployer |
| `k8s/docs/enhance-probe.md` | Enhanced probe config |
| `k8s/docs/liveless-simple.md` | Simple liveness/readiness |
| `k8s/docs/terminationGracePeriodSeconds.md` | Graceful termination |
| `k8s/docs/pod-annotations.md` | Pod annotations |
| `k8s/docs/pod-sigterm.md` | Pod SIGTERM handling |
| `k8s/docs/pod-write-data.md` | Writing data from pod |
| `k8s/docs/pod-write-data-gemini.md` | Writing data (Gemini) |
| `k8s/docs/memory-recycle.md` | Memory recycling |
| `k8s/docs/docker-images-labels.md` | Docker image labels |
| `k8s/docs/Blogs-to-Learn-25-Kubernetes-Concepts.md` | K8s learning resources |
| `k8s/docs/a.md` | K8s docs index a |
| `k8s/docs/helm-best-practices.md` | Helm best practices |
| `k8s/docs/helm-hook.md` | Helm hooks |
| `k8s/docs/helm-squid.md` | Helm with Squid |
| `k8s/docs/helm.md` | Helm guide |
| `k8s/docs/flow-dns.md` | DNS flow in K8s |
| `k8s/docs/flow-pdb.md` | PDB flow |
| `k8s/docs/k8s-scale/k8s-resouce-autoscale.md` | K8s resource autoscaling |
| `k8s/docs/k8s-scale/k8s-resouce-autoscale-chatgpt.md` | K8s autoscaling (ChatGPT) |
| `k8s/docs/k8s-scale/scale-deploy.md` | Scale deployment |
| `k8s/images/k8s-img-replace.md` | K8s image replacement |
| `k8s/images/k8s-image-replace-usage.md` | Image replacement usage |
| `k8s/images/images-pull-time.md` | Image pull time analysis |
| `k8s/images/imagePullSecrets.md` | imagePullSecrets guide |
| `k8s/images/Housekeep-imagepullsecrets.md` | Housekeeping imagePullSecrets |
| `k8s/images/molo.md` | Image moling |
| `k8s/vpa/vpa-concept.md` | VPA concept |
| `k8s/vpa/vpa-config.md` | VPA configuration |
| `k8s/vpa/how-to-setting-vpa-value.md` | VPA value setting |
| `k8s/networkpolicy/Routes-based.md` | Route-based network policy |
| `k8s/networkpolicy/Routes-based-LLM.md` | Route-based policy (LLM) |
| `k8s/networkpolicy/base-networkpolicy-egress-ingress.md` | Base network policy egress/ingress |
| `k8s/networkpolicy/cross-namespace.md` | Cross-namespace network policy |
| `k8s/networkpolicy/debug-ns-networkpolicy.md` | Debug namespace network policy |
| `k8s/networkpolicy/ebpf.md` | eBPF network policy |
| `k8s/networkpolicy/explorer-gateway-networkpolicy.md` | Gateway network policy explorer |
| `k8s/networkpolicy/gateway-ns-cross-ns.md` | Gateway cross-namespace policy |
| `k8s/networkpolicy/gke-ns-networkpolicy.md` | GKE namespace network policy |
| `k8s/networkpolicy/network-ns-ns.md` | Namespace-to-namespace policy |
| `k8s/networkpolicy/network-ns-ns-flow.md` | Namespace policy flow |
| `k8s/networkpolicy/network-ns-ns-gemini.md` | Namespace policy (Gemini) |
| `k8s/networkpolicy/networkpolicy-dns.md` | DNS network policy |
| `k8s/networkpolicy/networkpolicy-l34-l7.md` | L3/L4/L7 network policy |
| `k8s/networkpolicy/networkpolicy-node-pod.md` | Node/pod network policy |
| `k8s/networkpolicy/networkpolicy-ns-ns-gemini.md` | NS-NS policy (Gemini) |
| `k8s/networkpolicy/network-node-ip.md` | Node IP network policy |

### Security Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `safe/docs/verify-ssl.md` | SSL/TLS verification procedures |
| `safe/gcp-safe/verify-kms.md` | KMS validation and security checks |
| `safe/docs/auth.md` | Authentication documentation |
| `safe/docs/auths-method.md` | Authentication methods |
| `safe/docs/jwt.md` | JWT documentation |
| `safe/docs/dbp.md` | DBP security |
| `safe/docs/kali.md` | Kali tools usage |
| `safe/docs/url-block.md` | URL blocking |
| `safe/docs/waf.md` | WAF documentation |
| `safe/docs/waf-rule.md` | WAF rules |
| `safe/docs/waf-troubleshooting.md` | WAF troubleshooting |
| `safe/docs/waf-rule-troubleshooting.md` | WAF rule troubleshooting |
| `safe/docs/ssl-policy-gemini.md` | SSL policy (Gemini) |
| `safe/docs/psa.md` | PSA documentation |
| `safe/docs/ib2b-eb2b.md` | B2B integration security |
| `safe/docs/appd-violation.md` | AppD violations |
| `safe/docs/cyber-with-cloud-armor.md` | Cybersecurity with Cloud Armor |
| `safe/docs/gke-psa.md` | GKE PSA documentation |
| `safe/docs/gke-policy-control.md` | GKE policy control |
| `safe/docs/glb-open-80-ports.md` | GLB open ports |
| `safe/docs/encypy-asymmetric.md` | Asymmetric encryption |
| `safe/docs/crl2pkcs7.md` | CRL to PKCS7 conversion |
| `safe/docs/curl-pem-request.md` | curl with PEM certificates |
| `safe/docs/scan.md` | Security scanning |
| `safe/docs/pipeline-script.md` | Security pipeline scripts |
| `safe/docs/periodic-container-scanning-claude.md` | Periodic container scanning (Claude) |
| `safe/docs/iq-scan.md` | IQ scan documentation |
| `safe/docs/saasp-pod-nginx-squid.md` | SAAS pod with Nginx and Squid |
| `safe/docs/singnat.md` | Single NAT documentation |
| `safe/docs/cve.md` | CVE documentation |
| `safe/docs/strings.md` | Strings analysis |
| `safe/docs/ubuntu.md` | Ubuntu security |
| `safe/docs/cyberflows.md` | Cyberflows documentation |
| `safe/docs/Encrypted.md` | Encryption documentation |
| `safe/docs/api_security_tips.md` | API security tips |
| `safe/docs/safe-reference.md` | Security reference |
| `safe/docs/compare-sls-local-and-user.md` | Compare SLS local vs user |
| `safe/docs/flow-ssl.md` | SSL/TLS flow |
| `safe/docs/gcp-safe-api-enhance.md` | GCP safe API enhancement |
| `safe/wiz/wiz-base-information.md` | Wiz base information |
| `safe/wiz/wiz-grok.md` | Wiz with Grok |
| `safe/wiz/gemini-wiz.md` | Wiz with Gemini |
| `safe/wiz/Summary-TODO.md` | Wiz TODO |
| `safe/cyberflows/Trivy.md` | Trivy scanner |
| `safe/cyberflows/sbom.md` | SBOM documentation |
| `safe/cyberflows/sonar.md` | SonarQube integration |
| `safe/cyberflows/foss.md` | FOSS security |
| `safe/cyberflows/foss-explorer.md` | FOSS explorer |
| `safe/cyberflows/cage-scan.md` | Cage scanning |
| `safe/cyberflows/checkmarx.md` | Checkmarx integration |
| `safe/cyberflows/dast.md` | DAST documentation |
| `safe/cyberflows/cyberflows-flow.md` | Cyberflows flow |
| `safe/responsibilities/package-depend.md` | Package dependencies |
| `safe/responsibilities/snoar-code-coverage.md` | Sonar code coverage |
| `safe/how-to-fix-violation/README.md` | Fix violations README |
| `safe/how-to-fix-violation/quick-reference.md` | Fix violations quick reference |
| `safe/how-to-fix-violation/automation-scripts.md` | Automation scripts for violations |
| `safe/how-to-fix-violation/detection-tools.md` | Detection tools |
| `safe/how-to-fix-violation/ci-cd-integration.md` | CI/CD integration |
| `safe/how-to-fix-violation/remediation-strategies.md` | Remediation strategies |
| `safe/cert/eku.md` | Extended Key Usage documentation |
| `safe/cert/DigiCert-Assessment-Guide.md` | DigiCert assessment guide |
| `safe/cert/DigiCert-EKU-Migration-Plan.md` | DigiCert EKU migration |
| `safe/cert/README.md` | Certificate documentation README |
| `safe/cwe/cve-2025-68973.md` | CVE-2025-68973 |
| `safe/cwe/cwe-16.md` | CWE-16 error page |
| `safe/cwe/cwe-16-error-page.md` | CWE-16 error page detail |
| `safe/cwe/cwe-16-nginx.md` | CWE-16 Nginx |
| `safe/cwe/cwe-287.md` | CWE-287 authentication |
| `safe/cwe/cwe-319.md` | CWE-319 cleartext |
| `safe/cwe/cwe-523.md` | CWE-523 |
| `safe/cwe/cwe-550.md` | CWE-550 |
| `safe/cwe/cwe-650.md` | CWE-650 |
| `safe/cwe/cwe-798.md` | CWE-798 hardcoded credentials |
| `safe/cwe/how-to-fix.md` | How to fix vulnerabilities |
| `safe/cwe/nginx-header-violation-cwe-16.md` | Nginx header CWE-16 |
| `safe/cwe/nginx-header-x-frame-options.md` | Nginx X-Frame-Options |
| `safe/cwe/pro-security-status.md` | Pro security status |
| `safe/cwe/violations-24.04-libpam.md` | LibPAM violations |
| `safe/README.md` | Security README |
| `safe/gcp-safe/README.md` | GCP safe README |
| `safe/gcp-safe/VERIFICATION-CHECKLIST.md` | GCP verification checklist |
| `safe/gcp-safe/SUMMARY.md` | GCP safe summary |
| `safe/gcp-safe/CHANGELOG.md` | GCP safe changelog |
| `safe/gcp-safe/IMPROVEMENTS.md` | GCP safe improvements |
| `safe/gcp-safe/Key-Management-Service.md` | KMS documentation |
| `safe/gcp-safe/PERMISSIONS-GUIDE.md` | Permissions guide |
| `safe/gcp-safe/kms.md` | KMS guide |
| `safe/gcp-safe/kms-en-de.md` | KMS encrypt/decrypt |
| `safe/gcp-safe/kms-en-and-de.md` | KMS encrypt and decrypt |
| `safe/gcp-safe/key-keyring.md` | Key and keyring |
| `safe/gcp-safe/security-policy-overview.md` | Security policy overview |
| `safe/gcp-safe/data-classification-type.md` | Data classification |
| `safe/gcp-safe/workload-identify.md` | Workload identity |
| `safe/gcp-safe/psa.md` | PSA documentation |
| `safe/gcp-safe/pas.md` | PAS documentation |
| `safe/gcp-safe/ssl-policy.md` | SSL policy |
| `safe/gcp-safe/gcp-lb-cipher.md` | GCP LB cipher |
| `safe/gcp-safe/gcp-role.md` | GCP roles |
| `safe/gcp-safe/lex.md` | Lex documentation |
| `safe/gcp-safe/a.md` | GCP safe index a |
| `safe/gcp-safe/DEPLOY.md` | GCP safe deployment |
| `safe/gcp-safe/BUG-FIX-EXPLANATION.md` | Bug fix explanation |
| `safe/gcp-safe/TROUBLESHOOTING.md` | GCP safe troubleshooting |
| `safe/gcp-safe/INDEX.md` | GCP safe index |
| `safe/gcp-safe/merged-scripts.md` | Merged GCP safe scripts |
| `safe/get-token/README.md` | Token retrieval README |
| `safe/get-token/OPTIMIZATION.md` | Token optimization |

### OpenAI/GCP Load Balancer Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `OpenAI/docs/Verifying-GLB.md` | GLB verification |
| `OpenAI/README.md` | OpenAI documentation README |

### Alibaba Cloud Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `ali/docs/verify-e2e.md` | E2E verification for Ali Cloud |
| `aliyun.cloud-run/cloud-run-violation/cloud-run-verify-images.md` | Cloud Run image verification |
| `ali/README.md` | Ali Cloud README |
| `ali/docs/Ali-Logstore.md` | Ali Logstore |
| `ali/docs/a-call-b-debug.md` | A calls B debug |
| `ali/docs/imagepullsecret.md` | imagePullSecret documentation |
| `ali/docs/imagepullsecret-sa.md` | imagePullSecret with SA |
| `ali/docs/k8s-resources.md` | K8s resources on Ali Cloud |
| `ali/docs/migrate-exclude-secret.md` | Migration excluding secrets |
| `ali/docs/namespace-status.md` | Namespace status |
| `ali/docs/slb-binding-ingress.md` | SLB binding ingress |
| `ali/docs/v4.md` | Ali docs v4 |
| `ali/docs/v5.md` | Ali docs v5 |
| `ali/docs/v6.md` | Ali docs v6 |
| `ali/docs/v7.md` | Ali docs v7 |
| `ali/ali-dns/README.md` | Ali DNS README |
| `ali/k8s-cluster-migration/design.md` | K8s cluster migration design |
| `ali/k8s-cluster-migration/requirements.md` | K8s cluster migration requirements |
| `ali/k8s-cluster-migration/tasks.md` | K8s cluster migration tasks |
| `ali/k8s-migration-proxy/README.md` | K8s migration proxy README |
| `ali/k8s-migration-proxy/IMPLEMENTATION.md` | Migration proxy implementation |
| `ali/k8s-migration-proxy/IMPLEMENTATION_SUMMARY.md` | Implementation summary |
| `ali/k8s-migration-proxy/TASK3_IMPLEMENTATION_SUMMARY.md` | Task 3 implementation |
| `ali/k8s-migration-proxy/docs/external-services.md` | External services docs |
| `ali/k8s-migration-proxy/docs/ingress-implementation.md` | Ingress implementation |
| `ali/max-computer/README.md` | MaxCompute README |
| `ali/max-computer/Health-check.md` | MaxCompute health check |
| `ali/max-computer/How-to-call-maxcomputer-using-java.md` | Call MaxCompute from Java |
| `ali/max-computer/create-table.md` | Create MaxCompute table |
| `ali/max-computer/threshold-maxcomputer.md` | MaxCompute threshold |
| `ali/max-computer/threshold.md` | Threshold documentation |
| `ali/max-computer/why-using-maxcomputer.md` | Why use MaxCompute |
| `ali/migrate-plan/max-computer-gemini.md` | MaxCompute (Gemini) |
| `ali/migrate-plan/max-computer.md` | MaxCompute migration |
| `ali/migrate-plan/plan1/README-OPTIMIZED.md` | Plan 1 optimized README |
| `ali/migrate-plan/plan1/README.md` | Plan 1 README |
| `ali/migrate-plan/plan1/backgroud.md` | Plan 1 background |
| `ali/migrate-plan/plan1/migrate-claude.md` | Migration (Claude) |
| `ali/migrate-plan/plan1/migrate-gpt.md` | Migration (GPT) |
| `ali/migrate-plan/plan1/migrate-grok.md` | Migration (Grok) |
| `ali/migrate-plan/plan1/migrate-kongDP.md` | KongDP migration |
| `ali/migrate-plan/plan1/migrate-kongdp-gemini.md` | KongDP migration (Gemini) |
| `ali/migrate-plan/plan1/migrate-namespace.md` | Namespace migration |
| `ali/migrate-plan/plan1/migration-kongdp-explorer.md` | KongDP migration explorer |
| `ali/migrate-plan/plan1/poc-rewrite/merged-scripts.md` | POC rewrite merged scripts |
| `ali/migrate-plan/plan1/poc-rewrite/poc-implementation.md` | POC implementation |
| `ali/migrate-plan/plan1/poc-rewrite/poc-analysis.md` | POC analysis |
| `ali/migrate-plan/plan1/poc-rewrite/externalname-flow.md` | ExternalName flow |
| `ali/migrate-plan/plan1/poc-rewrite/before-after-comparison.md` | Before/after comparison |
| `ali/migrate-plan/plan1/short-domain-gpt.md` | Short domain (GPT) |
| `ali/migrate-plan/plan1/short-domian-claude.md` | Short domain (Claude) |
| `ali/migrate-plan/plan2/migrate-all-dns-record-explorer.md` | DNS record migration explorer |

### Other Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gcp/pub-sub/testing-value-verify.md` | Pub/Sub testing and verification |
| `howgit/docs/How-to-Verify-request.md` | Git verify request |
| `java/java-core/java-mail-verify.md` | Java mail verification |
| `gcp/psa-psc/psc-sql/README.md` | PSC SQL README |
| `gcp/psa-psc/psc-concept.md` | PSC concept |
| `gcp/psa-psc/psc.md` | PSC documentation |
| `gcp/psa-psc/psa.md` | PSA documentation |
| `gcp/psa-psc/psc-Redis.md` | PSC Redis |
| `gcp/psa-psc/psc-bard.md` | PSC bard |
| `gcp/psa-psc/psc-connect-consumer.md` | PSC connect consumer |
| `gcp/psa-psc/psc-cross-region.md` | PSC cross-region |
| `gcp/psa-psc/psc-psa-compare.md` | PSC vs PSA comparison |
| `gcp/psa-psc/psc-with-vpc-peering-quota-cost.md` | PSC vPC peering quota cost |
| `gcp/psa-psc/service-attachment-region.md` | Service attachment region |
| `gcp/psa-psc/vpc-peering.md` | vPC peering |
| `gcp/psa-psc/why-using-psc.md` | Why use PSC |
| `gcp/psa-psc/why-not-using-vpc-peering.md` | Why not vPC peering |
| `gcp/psa-psc/Hub-Spoke.md` | Hub-spoke network |
| `gcp/psa-psc/Kiro-psc-CloudSQL.md` | Kiro PSC CloudSQL |
| `gcp/psa-psc/gemini-psc.md` | PSC (Gemini) |
| `gcp/psa-psc/psa-vpc.md` | PSA vPC |
| `gcp/psa-psc/psa-with-psc.md` | PSA with PSC |
| `gcp/psa-psc/psc-thinking.md` | PSC thinking |
| `gcp/psa-psc/temp.md` | PSC temp |

---

## Other Verification Files

| File Path | Description |
| :------------------------------------------------- | :----------------------------------------------------------------- |
| `OpenAI/html/verify-glb.html` | HTML artifact for GLB verification visualization. |
| `ali/k8s-migration-proxy/verify_implementation.py` | Python script for verifying K8s migration implementation. |
| `k8s/custom-liveness/Dockerfile.health-checker` | Dockerfile for a health check utility container. |
| `k8s/custom-liveness/custom-health-check.py` | Python script for implementing custom health checks in Kubernetes. |

---

## Usage Examples

### TLS Secret Validation

```bash
# Check all TLS secrets in a namespace
./ssl/ingress-ssl/check-tls-secret-ns.sh -n <namespace>

# Check with verbose output
./ssl/ingress-ssl/check-tls-secret-ns.sh -n <namespace> -v

# Export certificate details and output as JSON
./ssl/ingress-ssl/check-tls-secret-ns.sh -n <namespace> -e -f json

# Check a single TLS secret
./ssl/ingress-ssl/check-tls-secret.sh <secret-name> <namespace>
```

### GKE Gateway Verification

```bash
# Full Gateway verification
./gateway/no-gateway/verify-gke-gateway.sh

# Claude-enhanced verification
./gateway/no-gateway/verify-gke-gateway-claude.sh
```

### DNS Verification

```bash
# Verify DNS FQDN
./dns/dns-peering/verify-dns-fqdn.sh

# Verify public/private IP
./dns/dns-peering/verify-pub-priv-ip.sh
```

### K8s Health Check

```bash
# Batch health check
./k8s/scripts/batch_health_check.sh -n <namespace>

# Pod startup measurement
./k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup.sh
```

### CVE Verification

```bash
# Full CVE check (NVD + MITRE + Ubuntu)
python3 safe/cwe/verify-enhance-html.sh CVE-2026-31431

# NVD API only
python3 safe/cwe/verify-enhance-html.sh CVE-2026-31431 --nvd-only

# Query Ubuntu CVE status
./safe/cwe/check_ubuntu_cve_status.sh CVE-2026-31431
```

### GCS Bucket IAM Verification

```bash
# Verify bucket IAM
./gcp/buckets/verify-buckets-iam.sh --project <project>

# JSON output
./gcp/buckets/verify-buckets-iam.sh --project <project> -o json
```

# lex edit it
