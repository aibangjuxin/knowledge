# GCP Infor (Linux) - Notes + Verification Helpers

This folder is added by Codex to help validate and run the existing scripts in `../` on a Linux host.
It does **not** modify your original scripts' logic.

## What I Observed In The Existing Scripts

### 1) `gcpfetch` is strict and can exit early

`gcpfetch` uses `set -euo pipefail`. This makes it fast and clean, but it also means:

- If a `gcloud ... list` command returns non-zero (permissions, API disabled, quota, networking), the whole script can exit.
- If `kubectl` is missing, the `kubectl get deployments ... | wc -l` pipeline can fail and exit the script.
- If `gsutil` is missing, `gsutil ls ... | wc -l` can fail and exit the script.

So "can run" on Linux depends on having the right CLIs installed and enough IAM/API access.

### 2) Project/region/zone are prerequisites, not optional

Many `gcloud` queries implicitly use the active project and default location:

- Ensure a project is selected (`gcloud config set project ...`) or pass `CLOUDSDK_CORE_PROJECT`.
- For GKE, cluster location matters (`--location` can be region or zone).

### 3) Counting Kubernetes Deployments is a separate auth path

`gcloud container clusters get-credentials ...` + `kubectl ...` requires:

- `kubectl`
- `gke-gcloud-auth-plugin` (required on modern `gcloud/kubectl` setups)
- Kubernetes RBAC permissions in the cluster (separate from GCP IAM)

If you only want "GCP platform" counts, it is often better to make Kubernetes counts optional.

## Helpers In This Folder

- `gcp-preflight.sh`: checks CLI dependencies and whether a project is set.
- `gcpfetch-safe`: a best-effort variant that uses the same underlying `gcloud` queries but does not abort the whole run on missing permissions/tools.
- `run-verify.sh`: runs preflight + basic smoke execution.

## Recommended Linux Setup (Minimal)

1. Install CLIs:
   - `gcloud` (Google Cloud SDK)
   - `kubectl` (optional, only for GKE Deployments)
   - `gsutil` (usually included with `gcloud`, but can be missing in minimal installs)

2. Authenticate:
   - Interactive: `gcloud auth login`
   - Headless/CI: `gcloud auth activate-service-account --key-file ...`

3. Select project:
   - `gcloud config set project YOUR_PROJECT_ID`
   - Or run helpers with `--project YOUR_PROJECT_ID` (does not mutate gcloud config).

## Run

```bash
cd /Users/lex/git/knowledge/gcp/gcp-infor

# Preflight only
./assistant/gcp-preflight.sh --project YOUR_PROJECT_ID

# Best-effort fetch
./assistant/gcpfetch-safe --project YOUR_PROJECT_ID --full

# Full verification wrapper
./assistant/run-verify.sh --project YOUR_PROJECT_ID
```

