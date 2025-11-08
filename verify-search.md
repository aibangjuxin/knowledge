
# Verify Scripts Search Results

| File Path | Description |
| :--- | :--- |
| `ali/k8s-migration-proxy/scripts/verify-connectivity.sh` | Verifies network connectivity to new Kubernetes cluster services during a migration, including DNS, ports, and HTTP endpoints. |
| `ali/verify-e2e.sh` | Performs end-to-end verification for Kubernetes resources (Ingress, Service, Deployment) in a namespace and tests the availability of Ingress URLs and Readiness Probes. |
| `gcp/migrate-gcp/migrate-secret-manage/05-verify.sh` | Verifies the integrity and correctness of secrets after a GCP Secret Manager migration by comparing versions, values, and IAM policies between source and target projects. |
| `gcp/sa/verify-gke-ksa-iam-authentication.sh` | Verifies IAM-based authentication for a GKE Deployment, especially for cross-project scenarios, checking KSA (Kubernetes Service Account) and GSA (Google Service Account) bindings and roles. |
| `gcp/sa/verify-iam-based-authentication-enhance.sh` | An enhanced version of `verify-gke-ksa-iam-authentication.sh` that provides more detailed validation of cross-project IAM authentication, including Workload Identity bindings. |
| `gcp/secret-manage/java-examples/verify-gcp-sa.sh` | A comprehensive debugging and verification script for GCP Secret Manager integration with GKE Workload Identity, checking the entire chain from deployment to secret access. |
| `gcp/secret-manage/verify-gcp-secretmanage.sh` | Verifies the permission chain for a GKE Deployment to access GCP Secret Manager, inspecting KSA, GSA, IAM roles, and Workload Identity bindings. |
| `k8s/custom-liveness/deploy-and-verify.sh` | Deploys a Squid proxy with a custom health check and verifies the correctness of the deployment, including the ConfigMap, Pod status, and health check endpoint. |
| `safe/cwe/verify.sh` | Checks the status of a specified CVE (Common Vulnerabilities and Exposures) ID in the Ubuntu security notices, retrieving the vulnerability description, severity, and fix status. |
