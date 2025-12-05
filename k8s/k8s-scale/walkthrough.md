# Walkthrough - Kubernetes Resource Optimization Script (Bash Version)

I have created a Bash script to help you manage and optimize resource usage in your Kubernetes namespace.

## Features
- **Auto-Discovery**: Fetches all deployments in a namespace.
- **Health Check**: Identifies "unhealthy" deployments (replicas > 0 but ready == 0).
- **Safe Scaling**: Scales down unhealthy deployments to 0, but saves the original replica count in an annotation (`x-optimization/original-replicas`) for easy recovery.
- **Resource Calculation**: Calculates the total resource limits of *running* pods vs *total* pods.
- **Quota Generation**: Generates a `ResourceQuota` YAML based on the *running* baseline + 10% buffer.
- **Dependencies**: Requires `kubectl`, `jq`, and `awk`.

## Verification Results
I verified the script using a mock dataset containing:
- `healthy-app`: 2 replicas (Running)
- `broken-app`: 3 replicas (CrashLooping/Pending)
- `tiny-app`: 1 replica (Running)

**Output:**
```text
Resource Optimization Report for Namespace: default
========================================
Metric               | CPU        | Memory    
----------------------------------------------
Total Requested      | 8100m      | 8320Mi    
Running (Healthy)    | 2100m      | 2176Mi    
Potential Savings    | 6          | 6Gi       

Unhealthy Deployments (Candidates for Scale Down):
  - broken-app: 3 replicas (Saving: 6 CPU, 6Gi Mem)
```

The script correctly identified `broken-app` as unhealthy and proposed a ResourceQuota based on the 2100m CPU / 2176Mi Memory baseline.

## How to Use

### 1. Dry Run (Safe Mode)
See what would happen without making changes:
```bash
./optimize_k8s_resources.sh --namespace <your-namespace> --dry-run --apply
```

### 2. Apply Changes
Scale down unhealthy deployments and generate the quota YAML:
```bash
./optimize_k8s_resources.sh --namespace <your-namespace> --apply
```

### 3. Restore Deployments
If you need to bring back the deployments that were scaled down:
```bash
./optimize_k8s_resources.sh --namespace <your-namespace> --restore
```
