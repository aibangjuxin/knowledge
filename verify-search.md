# Summary or Background

- This markdown records my workspace verification information and scripts.

# Verify Scripts Search Results

**Last Updated:** 2026-04-23

## Shell Scripts (`.sh`)

### 1. SSL/TLS Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `ssl/ingress-ssl/check-tls-secret-ns.sh` | Validates TLS secrets in a namespace, checking type, certificate/key matching, chain completeness, expiration. Supports table/json/csv output. |
| `ssl/ingress-ssl/check-tls-secret.sh` | Validates a single Kubernetes TLS secret, checking certificate/key modulus match, validity, expiration, SAN, issuer. |
| `ssl/ingress-ssl/generate-cert-chain.sh` | Generates certificate chain from TLS secrets in Kubernetes. |
| `ssl/ingress-ssl/generate-self-signed-cert.sh` | Generates self-signed TLS certificates for testing. |
| `ssl/ingress-ssl/create-tls-secret.sh` | Creates TLS secrets in Kubernetes from certificates. |
| `nginx/ingress-control/check-tls-secret-ns.sh` | Nginx Ingress-specific TLS secrets namespace validation. |
| `nginx/ingress-control/check-tls-secret.sh` | Nginx Ingress-specific TLS secret validation for single secret. |
| `nginx/ingress-control/check-tls-secret2.sh` | Alternative TLS secret validation script for Nginx Ingress. |
| `ssl/verify-domain-ssl.sh` | Verifies domain SSL certificate configuration. |
| `ssl/verify-domain-ssl-enhance.sh` | Enhanced domain SSL verification with detailed reporting. |
| `ssl/scripts/get-ssl.sh` | Extracts SSL connection and certificate information from OpenSSL output. |
| `ssl/scripts/get-ssl-all.sh` | Retrieves all SSL information for a domain. |
| `ssl/scripts/get-ssl-all-information.sh` | Comprehensive SSL information retrieval script. |
| `safe/cert/check_eku.sh` | Checks Extended Key Usage (EKU) in SSL/TLS certificates. |

### 2. Gateway/GKE Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gateway/no-gateway/verify-gke-gateway-chatgpt.sh` | Enhanced verification script for GKE Gateway API configuration with robust error handling, checking GatewayClass, CRDs, Gateway IP, TLS, HealthCheckPolicy, NetworkPolicy. |
| `gateway/no-gateway/verify-gke-gateway-claude.sh` | Verification script for GKE Gateway API checking GatewayClass, CRDs, Gateway status, HealthCheckPolicy, NetworkPolicy, TLS, and generates test URLs. |
| `gateway/no-gateway/verify-gke-gateway.sh` | Verifies GKE Gateway configuration by checking Gateway API resources, IP assignment, TLS certificates, policies, and generates test URLs. |
| `gateway/no-gateway/verify-no-gateway-all.sh` | Comprehensive verification of all GKE Gateway API resources and configurations. |

### 3. GCP/mTLS Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/mtls/trust-config/verify-trust-configs.sh` | Verifies GCP Certificate Manager Trust Configs and extracts certificate information including expiration dates. |
| `gcp/mtls/trust-config/verify-trust-config.sh` | Verifies trust configuration for mTLS. |

### 4. GCS Bucket Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/buckets/verify-buckets-iam-grok.sh` | Grok-enhanced bucket IAM verification. |
| `gcp/buckets/verify-buckets-iam.sh` | Verifies GCS Bucket IAM bindings and identifies cross-project accounts with support for text, JSON, and CSV output. |
| `gcp/buckets/verify-buckets.sh` | Comprehensive GCS Bucket verification tool checking basic info, IAM policies, lifecycle, versioning, CORS, labels, and encryption. |

### 5. GCP Service Account / IAM Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/sa/verify-another-proj-sa.sh` | Verifies Service Account in another project. |
| `gcp/sa/verify-gce-sa.sh` | Verifies GCE Service Account. |
| `gcp/sa/verify-gke-ksa-iam-authentication.sh` | Verifies IAM-based authentication for a GKE Deployment, checking KSA and GSA bindings and roles for cross-project scenarios. |
| `gcp/sa/verify-iam-based-authentication-enhance.sh` | Enhanced version providing detailed validation of cross-project IAM authentication, including Workload Identity bindings. |
| `gcp/secret-manage/java-examples/verify-gcp-sa.sh` | Debugging and verification script for GCP Secret Manager integration with GKE Workload Identity. |
| `gcp/secret-manage/list-secret/verify-gcp-secretmanage.sh` | Verifies the permission chain for GKE to access Secret Manager, checking KSA/GSA, IAM roles, Workload Identity. |
| `gcp/migrate-gcp/migrate-secret-manage/05-verify.sh` | Verifies the integrity of secrets after a GCP Secret Manager migration by comparing versions, values, and IAM policies between projects. |

### 6. GCP/GKE Status Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `gcp/gce/verify-gcp-and-gke-status.sh` | Verifies GCP and GKE status by checking forwarding rules, MIGs, autoscaler, DNS managed zones, and Kubernetes resources. |
| `gcp/gce/rolling/verify-mig-status.sh` | Verifies Managed Instance Group status. |

### 7. DNS Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `dns/dns-peering/dns-fqdn-verify.sh` | Verifies DNS FQDN resolution. |
| `dns/dns-peering/verify-dns-fqdn.sh` | Verifies DNS FQDN. |
| `dns/dns-peering/verify-pub-priv-ip-glm-ipv6.sh` | Verifies public/private IP and GLM IPv6. |
| `dns/dns-peering/verify-pub-priv-ip-glm-ok.sh` | Verifies public/private IP and GLM. |
| `dns/dns-peering/verify-pub-priv-ip.sh` | Verifies public and private IPs. |
| `dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6-ok.sh` | GitHub version of public/private IP and GLM IPv6 verification. |
| `dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6-enhanced.sh` | Enhanced version of public/private IP and GLM IPv6 verification. |
| `dns/dns-peering/github/verify-pub-priv-ip-glm-ipv6.sh` | GitHub version of public/private IP and GLM IPv6. |

### 8. K8s Pod/Health Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `k8s/custom-liveness/deploy-and-verify.sh` | Deploys a Squid proxy with custom health check and verifies deployment correctness. |
| `k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup.sh` | Verifies pod startup measurements. |
| `k8s/custom-liveness/explore-startprobe/verify_pod_measure_startup_fixed_en.sh` | Verifies pod startup measurements and gets Target URL on success. |
| `k8s/labels/add/05_verify.sh` | Verifies that labels were correctly applied to deployments. |
| `k8s/lib/pod_health_check_lib.sh` | Library containing reusable functions for Kubernetes pod health verification. |
| `k8s/scripts/batch_health_check.sh` | Performs batch health checks for multiple pods in a namespace using label selectors. |
| `k8s/scripts/debug_health_check.sh` | Debugging tool for troubleshooting Kubernetes pod health checks. |
| `ali/k8s-migration-proxy/scripts/verify-connectivity.sh` | Verifies network connectivity to new Kubernetes cluster services during a migration, including DNS, ports, and HTTP endpoints. |
| `ali/scripts/verify-e2e.sh` | Performs end-to-end verification for Kubernetes resources (Ingress, Service, Deployment) in a namespace and tests the availability of Ingress URLs and Readiness Probes. |

### 9. Kong Data Plane Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `kong/kongdp/verify-dp.sh` | Comprehensive verification of Kong Data Plane including infrastructure, logs, CP connectivity, and certificates. |
| `kong/kongdp/verify-dp-status-gemini.sh` | Verifies Kong DP status by checking pod health, logs, CP connectivity, and certificate configuration. |
| `kong/kongdp/verify-dp-status.sh` | Verifies Kong DP status by checking pod health, logs for certificate failures, and CP connectivity. |
| `kong/kongdp/verify-dp-summary.sh` | Provides a dashboard view of Kong DP status with focus on SSL certificate verification. |

### 10. Security/CVE Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `safe/cwe/check_ubuntu_cve_status.sh` | Queries Ubuntu's official security pages to check CVE fix status for specific Ubuntu versions. |
| `safe/cwe/verify.sh` | Checks the status of a CVE ID in Ubuntu security notices. |
| `safe/gcp-safe/verify-kms-enhanced.sh` | Validates GCP KMS cross-project encryption architecture, IAM policies, and key rotation. |

### 11. Other Check Scripts

| File Path | Description |
| :------------------------------------------------------------------------ | :------------------------------------------------------------------------- |
| `linux/docs/verify-timeout-chain.sh` | Verifies timeout chain in Linux. |
| `ssl/docs/claude/routeaction/maps-format-and-verify/verify-urlmap-json.sh` | Verifies URL map JSON format for GCP route action. |
| `ssl/docs/claude/routeaction/maps-format-and-verify/apply-urlmap-json.sh` | Applies URL map JSON for GCP route action. |

---

## Markdown Documents (`.md`)

### GKE Gateway Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gateway/no-gateway/verify-gateway-enhance.md` | Enhanced documentation for GKE Gateway verification procedures. |
| `gateway/no-gateway/verify-gke-gateway.md` | Documentation for GKE Gateway verification scripts and procedures. |

### GCP/mTLS Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gcp/mtls/SSLVerifyDepth.md` | SSL verify depth documentation. |
| `gcp/mtls/glb-verify-curl.md` | Verifying GLB using curl. |
| `gcp/mtls/glb-verify.md` | Guide for verifying Global Load Balancer mTLS configurations. |
| `gcp/mtls/mtls-test/generate-ca-and-verify-ca.md` | Generating and verifying CA for mTLS. |
| `gcp/mtls/mtls-verify.md` | mTLS verification guide. |
| `gcp/mtls/onboarding-verify.md` | Onboarding verification guide. |
| `gcp/mtls/verify-user-certificate.md` | Guide for verifying user certificates in mTLS scenarios. |

### GCS Bucket Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gcp/buckets/VERIFY-README.md` | Readme for verification procedures in buckets. |
| `gcp/buckets/verify-buckets-iam.md` | Documentation and implementation details for GCS Bucket IAM verification. |

### GCP Service Account / IAM Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gcp/sa/verify-gcp-sa.md` | Documentation for GCP Service Account verification. |
| `gcp/sa/verify-iam-based-authentication-enhance.md` | Enhanced IAM authentication verification documentation. |
| `gcp/sa/verify-sa-iam-based-authentication.md` | IAM-based Service Account authentication verification guide. |
| `gcp/secret-manage/verify-sa.md` | Documentation for Secret Manager service account verification. |

### DNS Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `dns/docs/verify-dnspeering.md` | Documentation for verifying DNS peering configurations. |

### Nginx Ingress Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `nginx/docs/verify-content-disposition.md` | Documentation for verifying Content-Disposition header handling in Nginx. |
| `nginx/ingress-control/ingress-verify/verify-ingress-migrate.md` | Documentation for verifying Nginx Ingress migration. |
| `nginx/ingress-control/verify-tls.md` | Guide for verifying TLS configurations in Nginx Ingress. |

### K8s Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `k8s/custom-liveness/explore-startprobe/openssl-verify-health.md` | Guide for using OpenSSL to verify application health in Kubernetes. |
| `k8s/docs/verify-kube-dns.md` | Guide for verifying Kubernetes DNS (kube-dns) configurations. |
| `k8s/docs/verify-namespace-label.md` | Documentation for verifying namespace labels in Kubernetes. |

### Security Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `safe/docs/verify-ssl.md` | Guide for SSL/TLS certificate verification procedures. |
| `safe/gcp-safe/verify-kms.md` | Documentation for KMS validation procedures and security checks. |

### OpenAI/GCP Load Balancer Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `OpenAI/docs/Verifying-GLB.md` | Documentation for verifying Google Cloud Load Balancer configurations. |

### Alibaba Cloud Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `ali/docs/verify-e2e.md` | Documentation for end-to-end Kubernetes verification procedures. |
| `aliyun.cloud-run/cloud-run-violation/Cloud-run-verify-images-using-OpenPGP.md` | Guide for using OpenPGP for Cloud Run image verification. |
| `aliyun.cloud-run/cloud-run-violation/cloud-run-verify-images-OpenPGP.md` | OpenPGP Cloud Run image verification. |
| `aliyun.cloud-run/cloud-run-violation/cloud-run-verify-images-claude.md` | Claude-enhanced Cloud Run image verification. |
| `aliyun.cloud-run/cloud-run-violation/cloud-run-verify-images.md` | Documentation for verifying Cloud Run images for security violations. |

### Other Documentation

| File Path | Description |
| :--------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `gcp/pub-sub/testing-value-verify.md` | Testing and verifying Pub/Sub values. |
| `howgit/docs/How-to-Verify-request.md` | How to verify requests (Git related). |
| `java/java-core/java-mail-verify.md` | Java mail verification guide. |

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

---

# lex edit it