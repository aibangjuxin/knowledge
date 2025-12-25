# summary or Background
- this markdown record my workspace verify information

# Verify Scripts Search Results

**Last Updated:** 2025-12-25

## Shell Scripts (`.sh`)

| File Path | Description |
| :--- | :--- |
| `ali/k8s-migration-proxy/scripts/verify-connectivity.sh` | Verifies network connectivity to new Kubernetes cluster services during a migration, including DNS, ports, and HTTP endpoints. |
| `ali/verify-e2e.sh` | Performs end-to-end verification for Kubernetes resources (Ingress, Service, Deployment) in a namespace and tests the availability of Ingress URLs and Readiness Probes. |
| `gateway/no-gateway/verify-gke-gateway-chatgpt.sh` | Enhanced verification script for GKE Gateway API configuration with robust error handling, checking GatewayClass, CRDs, Gateway IP, TLS, HealthCheckPolicy, NetworkPolicy. |
| `gateway/no-gateway/verify-gke-gateway-claude.sh` | Verification script for GKE Gateway API checking GatewayClass, CRDs, Gateway status, HealthCheckPolicy, NetworkPolicy, TLS, and generates test URLs. |
| `gateway/no-gateway/verify-gke-gateway.sh` | Verifies GKE Gateway configuration by checking Gateway API resources, IP assignment, TLS certificates, policies, and generates test URLs. |
| `gateway/no-gateway/verify-no-gateway-all.sh` | Comprehensive verification of all GKE Gateway API resources and configurations. |
| `gcp/gce/verify-gcp-and-gke-status.sh` | Verifies GCP and GKE status by checking forwarding rules, MIGs, autoscaler, DNS managed zones, and Kubernetes resources. |
| `gcp/migrate-gcp/migrate-secret-manage/05-verify.sh` | Verifies the integrity of secrets after a GCP Secret Manager migration by comparing versions, values, and IAM policies between projects. |
| `gcp/sa/verify-gke-ksa-iam-authentication.sh` | Verifies IAM-based authentication for a GKE Deployment, checking KSA and GSA bindings and roles for cross-project scenarios. |
| `gcp/sa/verify-iam-based-authentication-enhance.sh` | Enhanced version providing detailed validation of cross-project IAM authentication, including Workload Identity bindings. |
| `gcp/secret-manage/java-examples/verify-gcp-sa.sh` | Debugging and verification script for GCP Secret Manager integration with GKE Workload Identity. |
| `gcp/secret-manage/list-secret/verify-gcp-secretmanage.sh` | Verifies the permission chain for GKE to access Secret Manager, checking KSA/GSA, IAM roles, Workload Identity. |
| `k8s/custom-liveness/deploy-and-verify.sh` | Deploys a Squid proxy with custom health check and verifies deployment correctness. |
| `k8s/labels/add/05_verify.sh` | Verifies that labels were correctly applied to deployments. |
| `kong/kongdp/verify-dp.sh` | Comprehensive verification of Kong Data Plane including infrastructure, logs, CP connectivity, and certificates. |
| `kong/kongdp/verify-dp-status-gemini.sh` | Verifies Kong DP status by checking pod health, logs, CP connectivity, and certificate configuration. |
| `kong/kongdp/verify-dp-status.sh` | Verifies Kong DP status by checking pod health, logs for certificate failures, and CP connectivity. |
| `kong/kongdp/verify-dp-summary.sh` | Provides a dashboard view of Kong DP status with focus on SSL certificate verification. |
| `safe/cwe/verify.sh` | Checks the status of a CVE ID in Ubuntu security notices. |
| `safe/gcp-safe/verify-kms-enhanced.sh` | Validates GCP KMS cross-project encryption architecture, IAM policies, and key rotation. |

---

## Markdown Documents (`.md`)

| File Path | Description |
| :--- | :--- |
| `OpenAI/Verifying-GLB.md` | Documentation for verifying Google Cloud Load Balancer configurations. |
| `ali/verify-e2e.md` | Documentation for end-to-end Kubernetes verification procedures. |
| `dns/verify-dnspeering.md` | Documentation for verifying DNS peering configurations. |
| `gateway/no-gateway/verify-gateway-enhance.md` | Enhanced documentation for GKE Gateway verification procedures. |
| `gateway/no-gateway/verify-gke-gateway.md` | Documentation for GKE Gateway verification scripts and procedures. |
| `gcp/mtls/verify-user-certificate.md` | Guide for verifying user certificates in mTLS scenarios. |
| `gcp/sa/verify-gcp-sa.md` | Documentation for GCP Service Account verification. |
| `gcp/sa/verify-iam-based-authentication-enhance.md` | Enhanced IAM authentication verification documentation. |
| `gcp/sa/verify-sa-iam-based-authentication.md` | IAM-based Service Account authentication verification guide. |
| `gcp/secret-manage/verify-sa.md` | Documentation for Secret Manager service account verification. |
| `k8s/verify-kube-dns.md` | Guide for verifying Kubernetes DNS (kube-dns) configurations. |
| `k8s/verify-namespace-label.md` | Documentation for verifying namespace labels in Kubernetes. |
| `nginx/ingress-control/ingress-verify/verify-ingress-migrate.md` | Documentation for verifying Nginx Ingress migration. |
| `nginx/ingress-control/verify-tls.md` | Guide for verifying TLS configurations in Nginx Ingress. |
| `nginx/verify-content-disposition.md` | Documentation for verifying Content-Disposition header handling in Nginx. |
| `safe/gcp-safe/verify-kms.md` | Documentation for KMS validation procedures and security checks. |
| `safe/verify-ssl.md` | Guide for SSL/TLS certificate verification procedures. |

---

## Other Verification Files

| File Path | Description |
| :--- | :--- |
| `OpenAI/verify-glb.html` | HTML artifact for GLB verification visualization. |
| `ali/k8s-migration-proxy/verify_implementation.py` | Python script for verifying K8s migration implementation. |

