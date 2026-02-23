# GCP Platform Knowledge - Linux Environment

Generated: 2026-02-23

## 1. GCP Platform Understanding

### 1.1 Core Prerequisites

To run GCP-related scripts on Linux, you need:

1. **Google Cloud SDK (gcloud)**
   - Required for all GCP operations
   - Installation: `curl https://sdk.cloud.google.com | bash`
   - Or via package manager on Linux

2. **Authentication**
   - Interactive: `gcloud auth login`
   - Service Account: `gcloud auth activate-service-account --key-file=KEY.json`
   - Application Default Credentials: `gcloud auth application-default login`

3. **Project Configuration**
   - Must set active project: `gcloud config set project PROJECT_ID`
   - Or use environment variable: `CLOUDSDK_CORE_PROJECT=PROJECT_ID`

### 1.2 Optional Tools

| Tool | Purpose | Required For |
|------|---------|--------------|
| `gsutil` | Cloud Storage operations | Storage bucket listing |
| `kubectl` | Kubernetes operations | GKE deployment counts |
| `gke-gcloud-auth-plugin` | GKE authentication | Modern kubectl auth |
| `bq` | BigQuery operations | BigQuery datasets |

### 1.3 API Requirements

Different GCP services require specific APIs to be enabled:

| Service | API Name | Common Permission |
|---------|----------|-------------------|
| Compute Engine | compute.googleapis.com | compute.instances.list |
| GKE | container.googleapis.com | container.clusters.list |
| Cloud Storage | storage-api.googleapis.com | storage.buckets.list |
| Cloud SQL | sqladmin.googleapis.com | sql.instances.list |
| Secret Manager | secretmanager.googleapis.com | secretmanager.secrets.list |
| Pub/Sub | pubsub.googleapis.com | pubsub.topics.list |
| Cloud Run | run.googleapis.com | run.services.list |
| Cloud Functions | cloudfunctions.googleapis.com | cloudfunctions.functions.list |

### 1.4 Key GCP Concepts

#### Regional vs Zonal Resources
- **Regional**: GKE clusters, Cloud SQL, Cloud Run, regional managed instances
- **Zonal**: Individual GCE instances, zonal GKE node pools

#### Project Structure
- **Project ID**: Unique identifier (e.g., `my-project-123`)
- **Project Number**: Numeric identifier (e.g., `123456789012`)
- **Organization**: Top-level container for projects

#### Authentication Layers
1. **GCP IAM**: Controls access to GCP resources
2. **Kubernetes RBAC**: Controls access within GKE clusters (separate from IAM)

## 2. Script Analysis

### 2.1 Original Scripts Overview

| Script | Purpose | Key Features |
|--------|---------|--------------|
| `gcpfetch` | Neofetch-style GCP info | ASCII logo, color support |
| `gcp-functions.sh` | Function library | 40+ functions for GCP services |
| `gcp-explore.sh` | Platform exploration | Detailed resource listing |

### 2.2 Assistant Scripts

| Script | Purpose | Key Features |
|--------|---------|--------------|
| `gcp-preflight.sh` | Prerequisites check | CLI validation, auth check |
| `gcpfetch-safe` | Safe execution | Error handling, fallback values |
| `run-verify.sh` | Verification runner | Sequential execution |

### 2.3 Potential Issues

1. **Strict Error Handling**: Original scripts use `set -euo pipefail`
   - Any command failure can exit the script
   - Missing permissions/API = script failure

2. **GKE Deployment Counting**:
   - Requires kubectl + gke-gcloud-auth-plugin
   - Needs cluster credentials via `gcloud container clusters get-credentials`
   - Requires Kubernetes RBAC permissions (separate from GCP IAM)

3. **Project Dependency**:
   - Most queries depend on active project
   - Without project set, queries return errors

## 3. Linux-Specific Considerations

### 3.1 Shell Compatibility

- Scripts use `#!/usr/bin/env bash` for portability
- Compatible with: bash 4.0+, zsh
- Not compatible with: sh (dash), csh

### 3.2 Common Issues on Linux

1. **Missing gcloud**
   ```bash
   # Install on Debian/Ubuntu
   echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk-main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
   sudo apt-get update && sudo apt-get install google-cloud-sdk
   ```

2. **Missing gsutil** (often bundled with gcloud)
   ```bash
   gcloud components install gsutil
   ```

3. **kubectl authentication issues**
   ```bash
   # Install gke-gcloud-auth-plugin
   gcloud components install gke-gcloud-auth-plugin
   ```

### 3.3 Performance Considerations

- Each `gcloud` command makes API calls
- GKE deployment counting requires multiple API calls per cluster
- Use `--format` flags to reduce data transfer
- Consider parallel execution for multiple clusters

## 4. Usage Patterns

### 4.1 Quick Start

```bash
# 1. Install Google Cloud SDK
curl https://sdk.cloud.google.com | bash
source ~/.bashrc

# 2. Authenticate
gcloud auth login

# 3. Set project
gcloud config set project YOUR_PROJECT_ID

# 4. Run preflight check
./assistant/gcp-preflight.sh

# 5. Run fetch
./gcpfetch
```

### 4.2 Best Practices

1. **Always check prerequisites first**
   ```bash
   ./assistant/gcp-preflight.sh --strict
   ```

2. **Use --project flag when testing**
   ```bash
   ./assistant/gcpfetch-safe --project my-test-project
   ```

3. **Use safe versions in automation**
   ```bash
   ./assistant/gcpfetch-safe --project $PROJECT --no-logo --no-color
   ```

4. **Handle missing tools gracefully**
   - Scripts check for optional tools (kubectl, gsutil)
   - Missing tools show "N/A" instead of errors

## 5. Extended GCP Services

Based on the existing scripts, here are additional GCP services that could be explored:

| Service | Query Command | Use Case |
|---------|--------------|----------|
| BigQuery | `bq ls` | Data warehousing |
| Cloud DNS | `gcloud dns managed-zones list` | DNS management |
| Cloud Armor | `gcloud compute security-policies list` | WAF/DDoS protection |
| Load Balancing | `gcloud compute backend-services list` | Traffic management |
| VPC Service Controls | `gcloud access-context-manager policies list` | Security perimeter |
| Cloud Monitoring | `gcloud monitoring uptime list` | Observability |
| Cloud Logging | `gcloud logging sinks list` | Audit logging |
| SSL Certificates | `gcloud compute ssl-certificates list` | TLS management |

## 6. Troubleshooting

### 6.1 Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `ERROR: gcloud not found` | SDK not installed | Install Google Cloud SDK |
| `ERROR: No active project` | No project set | `gcloud config set project ID` |
| `Permission denied` | Missing IAM role | Add roles to service account |
| `API not enabled` | Service not enabled | Enable in GCP Console or via CLI |
| `kubectl auth failed` | Missing gke-gcloud-auth-plugin | Install the plugin |

### 6.2 Debug Commands

```bash
# Check current configuration
gcloud config list

# Check active account
gcloud auth list

# List enabled APIs
gcloud services list --enabled

# Check project permissions
gcloud projects get-iam-policy PROJECT_ID

# Verify kubectl config
kubectl config current-context

# Test GKE connectivity
gcloud container clusters list
```

---

For more information, see:
- [Google Cloud SDK Documentation](https://cloud.google.com/sdk/docs)
- [gcloud CLI Reference](https://cloud.google.com/sdk/gcloud/reference)
