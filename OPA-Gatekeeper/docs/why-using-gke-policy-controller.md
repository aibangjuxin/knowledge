# Why GKE Policy Controller — Fleet-Level Centralized Management

## 1. Document Purpose

This document explains the core value proposition of **GKE Policy Controller + Fleet**: the ability to manage policy configurations once and have them automatically applied across all clusters in your fleet.

This is the primary advantage over standalone open-source OPA Gatekeeper.

## 2. Core Value: One Config, All Clusters Benefit

### The Problem

With open-source OPA Gatekeeper, each cluster requires individual management:

```
Cluster A: gatekeeper-system namespace
  - Template A (must be manually synced)
  - Constraint X (must be manually created)

Cluster B: gatekeeper-system namespace
  - Template A (must be manually synced)
  - Constraint Y (must be manually created)

Cluster C: gatekeeper-system namespace
  - Template A (must be manually synced)
  - Constraint Z (must be manually created)

Total: N clusters × M policies = N×M management operations
```

### The Fleet Solution

With GKE Policy Controller + Fleet, you configure once at the Fleet level, and all registered clusters receive the configuration automatically:

```
Fleet Level (Single Point of Management)
  │
  ├─ Policy Controller Config (policy-controller.yaml)
  │   - audit-interval: 120
  │   - log-denies: true
  │   - mutation: true
  │   - referential-rules: true
  │   - exemptable-namespaces: [kube-system, gatekeeper-system]
  │
  ├─ Policy Bundles (applied via Fleet)
  │   - cis-k8s-v1.5.1
  │   - pss-baseline-v2022
  │   - policy-essentials-v2022
  │
  └─ Constraint Templates (from template library)
       ↓ Fleet API syncs to all memberships
       ↓
┌──────────────┬──────────────┬──────────────┐
│  Cluster A   │  Cluster B   │  Cluster C   │
│  (auto-sync) │  (auto-sync) │  (auto-sync) │
└──────────────┴──────────────┴──────────────┘

Total: 1 Fleet config = all clusters get the same policies
```

## 3. Fleet Default Member Configuration (fleet-default-member-config)

### What Is It?

The `fleet-default-member-config` is a YAML file that defines the default Policy Controller configuration for **all clusters** registered to the Fleet. When you enable Policy Controller with this file, every membership automatically inherits these settings.

### Complete YAML Structure

```yaml
# policy-controller.yaml
apiVersion: anthospolicycontroller.gke.io/v1alpha1
kind: PolicyControllerMembershipConfig
metadata:
  name: policy-controller-default
spec:
  # Audit configuration
  auditIntervalSeconds: 120          # How often to audit resources (in seconds)
  constraintViolationLimit: 100     # Max violations stored on constraint resource

  # Logging
  logDenies: true                  # Log all denies and dry-run failures

  # Mutation
  mutation: true                   # Enable mutation webhook support

  # Referential constraints (cross-resource references)
  referentialRules: true           # Allow constraints referencing other resources

  # Exempted namespaces (Policy Controller ignores these)
  exemptableNamespaces:
    - kube-system
    - gatekeeper-system
    - istio-system
    - kube-node-lease

  # Monitoring backend (prometheus, cloudmonitoring, or both)
  monitoring: prometheus
```

### All Configuration Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `auditIntervalSeconds` | int | 60 | Seconds between consecutive audits |
| `constraintViolationLimit` | int | 100 | Max violations stored per constraint |
| `logDenies` | bool | false | Log denied requests |
| `mutation` | bool | false | Enable mutation webhook |
| `referentialRules` | bool | false | Enable cross-resource constraints |
| `exemptableNamespaces` | []string | [] | Namespaces to ignore |
| `monitoring` | string | prometheus | Monitoring backend(s) |

## 4. Concrete Fleet Configuration Examples

### Example 1: Enable with Fleet Default Config (All Clusters)

```bash
# Create the fleet default config file
cat > policy-controller.yaml << 'EOF'
apiVersion: anthospolicycontroller.gke.io/v1alpha1
kind: PolicyControllerMembershipConfig
metadata:
  name: policy-controller-default
spec:
  auditIntervalSeconds: 120
  constraintViolationLimit: 100
  logDenies: true
  mutation: true
  referentialRules: true
  exemptableNamespaces:
    - kube-system
    - gatekeeper-system
  monitoring: prometheus,cloudmonitoring
EOF

# Enable Policy Controller with fleet default config
gcloud container fleet policycontroller enable \
  --fleet-default-member-config=policy-controller.yaml

# Result: ALL clusters in the fleet inherit this configuration
```

### Example 2: Apply Specific Bundles to All Clusters

```bash
# Install CIS Kubernetes Benchmark bundle on all memberships
gcloud container fleet policycontroller content bundles set cis-k8s-v1.5.1 \
  --all-memberships \
  --exempted-namespaces=kube-system,gatekeeper-system

# Install Pod Security Standards Baseline on all memberships
gcloud container fleet policycontroller content bundles set pss-baseline-v2022 \
  --all-memberships

# Install Policy Essentials on all memberships
gcloud container fleet policycontroller content bundles set policy-essentials-v2022 \
  --all-memberships

# Result: All 3 bundles are now enforced across all fleet clusters
```

### Example 3: Selective Cluster Configuration

```bash
# Enable Policy Controller for specific clusters only
gcloud container fleet policycontroller enable \
  --memberships=cluster-prod-us,cluster-prod-eu \
  --location=us-central1 \
  --fleet-default-member-config=policy-controller.yaml

# Result: Only prod clusters in us-central1 get the config
```

### Example 4: Update Fleet Default Config (Propagates to All)

```bash
# Update audit interval for ALL clusters
gcloud container fleet policycontroller update \
  --all-memberships \
  --audit-interval=300

# Disable mutation across the fleet
gcloud container fleet policycontroller update \
  --all-memberships \
  --no-mutation

# Result: Change applies to all clusters immediately
```

### Example 5: Per-Cluster Override

If a specific cluster needs different settings, you can override the Fleet default:

```bash
# Override for a specific cluster (staging)
gcloud container fleet policycontroller update \
  --memberships=cluster-staging \
  --location=us-central1 \
  --audit-interval=60 \
  --mutation \
  --exemptable-namespaces=kube-system,gatekeeper-system,istio-system
```

## 5. Available Policy Bundles

| Bundle | Alias | Type | Description |
|--------|-------|------|-------------|
| CIS GKE Benchmark | `cis-gke-v1.5.0` | Kubernetes Standard | CIS GKE Benchmark v1.5 |
| CIS Kubernetes Benchmark | `cis-k8s-v1.5.1` | Kubernetes Standard | CIS K8s Benchmark v1.5 |
| Pod Security Standards Baseline | `pss-baseline-v2022` | Kubernetes Standard | K8s PSS Baseline |
| Pod Security Standards Restricted | `pss-restricted-v2022` | Kubernetes Standard | K8s PSS Restricted |
| Policy Essentials | `policy-essentials-v2022` | Best Practices | Core security policies |
| Cost and Reliability | `cost-reliability-v2023` | Best Practices | Cost optimization |
| MITRE | `mitre-v2024` | Industry Standard | MITRE ATT&CK tactics |
| Cloud Service Mesh | `asm-policy-v0.0.1` | Best Practices | ASM security policies |
| NIST SP 800-53 | `nist-sp-800-53-r5` | Industry Standard | NIST compliance |

## 6. Workflow: Complete Fleet Setup

### Step 1: Register Clusters to Fleet

```bash
# Register a GKE cluster to Fleet
gcloud container fleet memberships register my-cluster \
  --gke-cluster=us-central1/my-cluster \
  --enable-workload-identity
```

### Step 2: Create Fleet Default Config

```bash
cat > policy-controller.yaml << 'EOF'
apiVersion: anthospolicycontroller.gke.io/v1alpha1
kind: PolicyControllerMembershipConfig
metadata:
  name: policy-controller-default
spec:
  auditIntervalSeconds: 120
  constraintViolationLimit: 100
  logDenies: true
  mutation: false
  referentialRules: true
  exemptableNamespaces:
    - kube-system
    - gatekeeper-system
    - istio-system
  monitoring: prometheus,cloudmonitoring
EOF
```

### Step 3: Enable Policy Controller with Fleet Default

```bash
gcloud container fleet policycontroller enable \
  --all-memberships \
  --fleet-default-member-config=policy-controller.yaml
```

### Step 4: Install Policy Bundles

```bash
# Apply security baseline bundles
gcloud container fleet policycontroller content bundles set pss-baseline-v2022 \
  --all-memberships \
  --exempted-namespaces=kube-system,gatekeeper-system

gcloud container fleet policycontroller content bundles set policy-essentials-v2022 \
  --all-memberships

gcloud container fleet policycontroller content bundles set cis-k8s-v1.5.1 \
  --all-memberships
```

### Step 5: Verify Installation

```bash
# Check Policy Controller status across fleet
gcloud container fleet policycontroller describe

# List all memberships and their status
gcloud container fleet memberships list

# Verify bundles installed on a specific cluster
kubectl get constrainttemplates -n gatekeeper-system
```

## 7. Comparison: Fleet Config vs. GitOps Approach

| Aspect | GKE Policy Controller + Fleet | GitOps (ArgoCD/Flux) |
|--------|------------------------------|----------------------|
| Configuration Location | Fleet API (Google-managed) | Git repository |
| Propagation Speed | Instant (Fleet API push) | Depends on sync interval |
| Cross-cloud Support | GKE only | Any Kubernetes |
| Version Control | Limited (API state) | Full Git history |
| Conflict Resolution | Fleet wins | Git merge/conflict |
| Offline Support | Requires connectivity | Full offline capability |
| Audit Trail | GCP logging | Git commit history |

## 8. When to Use Fleet Default Config

**Use Fleet Default Config when:**
- All clusters should have identical base policies
- You want instant propagation of changes
- You primarily run GKE clusters
- You want native GCP integration (Console UI, metrics)

**Prefer GitOps approach when:**
- You have multi-cloud clusters (GKE + EKS + AKS)
- You need granular per-cluster customization
- You want strict version control on policy changes
- Your team follows GitOps workflows

## 9. Key Commands Reference

```bash
# Enable Policy Controller with fleet default
gcloud container fleet policycontroller enable \
  --fleet-default-member-config=/path/to/policy-controller.yaml

# Update fleet default config
gcloud container fleet policycontroller update \
  --all-memberships \
  --audit-interval=300

# Set bundles for all clusters
gcloud container fleet policycontroller content bundles set <BUNDLE> \
  --all-memberships \
  --exempted-namespaces=kube-system,gatekeeper-system

# Remove bundle from all clusters
gcloud container fleet policycontroller content bundles remove <BUNDLE> \
  --all-memberships

# Describe fleet-wide status
gcloud container fleet policycontroller describe

# Check specific membership
gcloud container fleet policycontroller describe --memberships=my-cluster --location=us-central1
```

## 10. Conclusion

The **"One Config, All Clusters Benefit"** capability of GKE Policy Controller + Fleet is the primary reason to choose this solution over open-source OPA Gatekeeper. Key benefits:

1. **Single Source of Truth**: Policy configuration lives at the Fleet level
2. **Instant Propagation**: Changes apply to all clusters immediately
3. **Consistent Enforcement**: Every cluster runs the same policy version
4. **Centralized Management**: One place to audit, update, and monitor
5. **Google-Managed**: No infrastructure to maintain for the control plane

For organizations with multiple GKE clusters that need unified policy enforcement, this "Fleet-first" approach significantly reduces operational overhead.
