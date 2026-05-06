# GKE Policy Controller Usage Guide

## Overview

This guide explains how to use GKE Policy Controller for Kubernetes policy management. After installing Policy Controller (see [step-by-step-install.md](./step-by-step-install.md)), you can enforce security, compliance, and operational policies on your cluster resources.

**What Policy Controller Does:**
- Acts as an Admission Controller to intercept Kubernetes API requests
- Evaluates resources against defined policies before creation/update
- Runs periodic audits to detect existing violations
- Provides 70+ pre-built policy templates

---

## Core Concepts

### ConstraintTemplate vs Constraint

| Concept                | Description                                                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| **ConstraintTemplate** | A reusable policy "schema" that defines the logic (written in Rego). Defines what kind of resources it applies to and what parameters it accepts. |
| **Constraint**         | A specific instance of a template with actual parameter values. The actual policy you enforce.                                                    |

**Analogy:**
- `ConstraintTemplate` = Class (template/blueprint)
- `Constraint` = Object (instantiation with specific values)

### Enforcement Actions

| Action   | Behavior                                                   |
| -------- | ---------------------------------------------------------- |
| `deny`   | Blocks resources that violate the policy at admission time |
| `dryrun` | Allows resources but logs violations (for testing)         |
| `warn`   | Returns warning but does not block                         |
| `post`   | Logs after resource is created                             |

### Two Policy Operations

| Operation     | Purpose                               | Trigger                         |
| ------------- | ------------------------------------- | ------------------------------- |
| **Admission** | Intercepts create/update requests     | Real-time, blocks violations    |
| **Audit**     | Scans existing resources periodically | Every 60 seconds (configurable) |

---

## Viewing Available Policies

### List All Constraint Templates

```bash
kubectl get constrainttemplates
```

**Output:**
```
NAME                                      AGE
allowedserviceportname                    6h17m
k8sallowedrepos                           6h17m
k8sblockloadbalancer                      6h17m
k8sblocknodeport                          6h17m
k8scontainerlimits                        6h17m
k8spspprivilegedcontainer                 6h17m
k8srequiredlabels                         6h17m
k8srequiredresources                      6h17m
... (70+ total)
```

### View Template Details

```bash
kubectl get constrainttemplate k8srequiredlabels -o yaml
```

**Key sections in a template:**
- `spec.crd.spec.names.kind` - The Constraint kind this template creates
- `spec.target` - Which resources this policy applies to
- `spec.target[].rego` - The policy logic (Rego)

### List Popular Templates by Category

```bash
# Security
kubectl get constrainttemplates | grep -E "psp|security|privileged|capabilities"

# Resource Management
kubectl get constrainttemplates | grep -E "limits|resources|replicas"

# Network
kubectl get constrainttemplates | grep -E "ingress|service|network|external"

# Labels & Metadata
kubectl get constrainttemplates | grep -E "label|annotation|tag"
```

---

## Using Pre-built Constraints

### View Active Constraints

```bash
kubectl get constraint --all-namespaces
```

**Output:**
```
NAME                                                                  ENFORCEMENT-ACTION  TOTAL-VIOLATIONS
k8spodsrequiresecuritycontext.constraints.gatekeeper.sh/...-psp-pods-require-security-context  dryrun  3
k8spspallowedusers.constraints.gatekeeper.sh/...-psp-pods-must-run-as-nonroot  dryrun  3
```

### View Constraint Details

```bash
kubectl describe k8spspallowedusers.constraints.gatekeeper.sh/policy-essentials-v2022-psp-pods-must-run-as-nonroot
```

### View Violations

```bash
kubectl get constraint --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.enforcementAction}{"\t"}{.status.totalViolations}{"\n"}{end}'
```

---

## Creating Custom Constraints

### Example 1: Require Labels on Deployments

This constraint requires all Deployments to have `app` and `environment` labels.

**Step 1: Create the constraint YAML**

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-common-labels
spec:
  enforcementAction: dryrun  # Change to "deny" to block
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    labels:
    - key: "app"
    - key: "environment"
      allowedRegex: "^(prod|staging|dev)$"
```

**Step 2: Apply the constraint**
- `gcloud compute ssh dev-lon-bastion-public --zone=europe-west2-a --tunnel-through-iap`
```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-common-labels
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    labels:
    - key: "app"
    - key: "environment"
      allowedRegex: "^(prod|staging|dev)$"
EOF

k8srequiredlabels.constraints.gatekeeper.sh/require-common-labels created
```

**Step 3: Verify**
~~kubectl get constraint require-common-labels~~
```bash
kubectl get k8srequiredlabels require-common-labels
NAME                    ENFORCEMENT-ACTION   TOTAL-VIOLATIONS
require-common-labels   dryrun               12

kubectl describe k8srequiredlabels require-common-labels
```

**Step 4: Test the policy**

```bash
# 方式 A：使用完整的资源类型名称（推荐）
kubectl get k8srequiredlabels require-common-labels

# 方式 B：查看所有 gatekeeper 约束实例
kubectl get constraints

# 方式 C：如果想查看详细状态（包含违规统计），使用 -o yaml
kubectl get k8srequiredlabels require-common-labels -o yaml


# This deployment violates (missing labels)
kubectl create deployment bad-app --image=nginx

# Check violations
kubectl get constraints ==> check all of gatekeeper constraints

kubectl get constraint require-common-labels -o jsonpath='{.status.violations}'
```

### Example 2: Block LoadBalancer Services

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockLoadBalancer
metadata:
  name: block-loadbalancer-services
spec:
  enforcementAction: deny  # Blocks at admission
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
    excludedNamespaces: ["kube-system"]
EOF
```

### Example 3: Limit Container Resources

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: limit-container-resources
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    ranges:
    - max:
        cpu: "2"
        memory: "4Gi"
      min:
        cpu: "50m"
        memory: "64Mi"
EOF
```

### Example 4: Restrict Image Registries

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: allow-only-approved-registries
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    repos:
    - "docker.io"
    - "gcr.io"
    - "eu.gcr.io"
EOF
```

### Example 5: Require Security Context

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPodsRequireSecurityContext
metadata:
  name: require-pod-security-context
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    excludedNamespaces: ["kube-system"]
EOF
```

---

## Changing Enforcement Mode

### Switch from dryrun to deny

```bash
# For a specific constraint
kubectl patch k8srequiredlabels.require-common-labels \
  --type=merge \
  -p '{"spec":{"enforcementAction":"deny"}}'

# Verify the change
kubectl get constraint require-common-labels -o jsonpath='{.spec.enforcementAction}'
```

### Check current enforcement action

```bash
kubectl get constraint --all-namespaces -o custom-columns=NAME:.metadata.name,ACTION:.spec.enforcementAction,VIOLATIONS:.status.totalViolations
```

---

## Exempting Namespaces

Some namespaces should be exempt from policies (like `kube-system` for cluster components).

### Method 1: Per-Constraint Exclusion

```yaml
spec:
  match:
    excludedNamespaces:
    - kube-system
    - kube-public
    - kube-node-lease
```

### Method 2: Using Annotation (Namespace-level)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-special-namespace
  annotations:
    constraints.gatekeeper.sh/ignore: "yes"
```

### Method 3: Global Exemptable Namespaces (Fleet-level)

Update via Fleet config:

```bash
gcloud container fleet policycontroller enable \
  --memberships=aibang-master \
  --fleet-default-member-config=- <<'EOF'
policyControllerHubConfig:
  installSpec: INSTALL_SPEC_ENABLED
  exemptableNamespaces:
  - kube-system
  - kube-public
  - kube-node-lease
  - my-special-namespace
EOF
```

---

## Policy Bundles

Policy Bundles are pre-configured sets of constraints maintained by Google.

### Available Bundles

| Bundle                    | Description                       | Use Case                         |
| ------------------------- | --------------------------------- | -------------------------------- |
| `policy-essentials-v2022` | Core security best practices      | **Recommended for all clusters** |
| `pss-baseline-v2022`      | Pod Security Standards Baseline   | Basic pod security               |
| `pss-restricted-v2022`    | Pod Security Standards Restricted | Strict pod security              |
| `cis-k8s-v1.5.1`          | CIS Kubernetes Benchmark          | Compliance auditing              |
| `nist-sp-800-190`         | NIST Container Security Guide     | Regulated environments           |
| `pci-dss-v3.2.1`          | PCI DSS 3.2.1                     | Payment card compliance          |
| `pci-dss-v4.0`            | PCI DSS 4.0                       | Payment card compliance          |
| `cost-reliability-v2023`  | Cost optimization policies        | Budget control                   |

### Enable a Bundle

```bash
gcloud container fleet policycontroller enable \
  --memberships=aibang-master \
  --fleet-default-member-config=- <<'EOF'
policyControllerHubConfig:
  installSpec: INSTALL_SPEC_ENABLED
  policyContent:
    bundles:
      pss-baseline-v2022: {}
      cis-k8s-v1.5.1: {}
EOF
```

### View Bundle Constraints

```bash
kubectl get constraint --all-namespaces | grep pss-baseline
```

---

## Auditing and Monitoring

### View Audit Logs

```bash
# Check for violations in the last hour
kubectl get constraint --all-namespaces -o custom-columns=NAME:.metadata.name,VIOLATIONS:.status.totalViolations | grep -v "0$"

# Detailed violation info
kubectl describe k8spspprivilegedcontainer.constraints.gatekeeper.sh/policy-essentials-v2022-psp-privileged-container
```

### Check Gatekeeper Logs

```bash
# View audit pod logs
kubectl logs -n gatekeeper-system -l app=gatekeeper --tail=100

# View controller logs
kubectl logs -n gatekeeper-system -l control-plane=controller-manager --tail=100
```

### View Events

```bash
kubectl get events -n gatekeeper-system --sort-by='.lastTimestamp' | tail -20
```

### Export Violation Report

```bash
kubectl get constraint --all-namespaces -o yaml > violation-report.yaml
```

---

## Common Workflows

### Workflow 1: New Policy Deployment

```
1. Create constraint in dryrun mode
2. Deploy to cluster
3. Monitor violations via: kubectl get constraint <name> -o jsonpath='{.status.violations}'
4. Fix violating resources OR adjust policy parameters
5. After stabilization, switch to deny mode
```

### Workflow 2: Investigate Violation

```bash
# 1. Find the constraint with violations
kubectl get constraint --all-namespaces | grep -v " 0$"

# 2. Get violation details
kubectl describe k8srequiredlabels.<constraint-name>

# 3. Get specific violation instances
kubectl get k8srequiredlabels.<constraint-name> -o jsonpath='{.status.violations}'

# 4. Check which resources violate
kubectl get constraint <name> -o json | jq '.status.violations[] | .message'
```

### Workflow 3: Remove a Constraint

```bash
kubectl delete constraint <constraint-name>
```

---

## YAML File Structure Reference

### ConstraintTemplate Structure

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: <template-name>
spec:
  crd:                           # CRD schema definition
    spec:
      names:
        kind: <Kind>             # e.g., K8sRequiredLabels
  targets:                       # Policy targeting rules
  - target: admission.k8s.gatekeeper.sh
    rego: |                      # Rego policy code
      package <package-name>
      violation[{"msg": msg}] {
        ...
      }
```

### Constraint Structure

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: <Kind>                      # Matches template's crd.spec.names.kind
metadata:
  name: <constraint-name>
spec:
  enforcementAction: dryrun       # or "deny"
  match:                          # Which resources to apply to
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces: []
  parameters:                     # Template-specific parameters
    labels:
    - key: "app"
```

---

## Quick Reference Commands

```bash
# List all templates
kubectl get constrainttemplates

# List all constraints
kubectl get constraint --all-namespaces

# List constraints by kind
kubectl get constraint -A -o custom-columns=NAME:.metadata.name,KIND:.kind

# View violation count summary
kubectl get constraint -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.status.totalViolations}{"\n"}{end}'

# View specific constraint
kubectl describe constraint <name>

# View constraint YAML
kubectl get constraint <name> -o yaml

# Delete constraint
kubectl delete constraint <name>

# Check Gatekeeper pods
kubectl get pods -n gatekeeper-system

# View Gatekeeper logs
kubectl logs -n gatekeeper-system -l app=gatekeeper --tail=50

# Check constraint status
kubectl get constrainttemplate <template> -o jsonpath='{.status}'
```

---

## Best Practices

1. **Start with dryrun mode**
   - Deploy new constraints in `dryrun` mode first
   - Monitor violations before switching to `deny`

2. **Always exempt system namespaces**
   ```yaml
   spec:
     match:
       excludedNamespaces:
       - kube-system
       - kube-public
       - kube-node-lease
       - gatekeeper-system
   ```

3. **Use descriptive constraint names**
   ```yaml
   metadata:
     name: require-app-label-on-deployments
   ```

4. **Document policy rationale**
   ```yaml
   metadata:
     annotations:
       description: "Requires app and environment labels for tracking"
   ```

5. **Review violations regularly**
   ```bash
   # Weekly review script
   kubectl get constraint -A | grep -v " 0$" | awk '{print $1 "/" $2}'
   ```

6. **Use policy bundles for common requirements**
   - `policy-essentials-v2022` is a good starting point
   - Enable `pss-baseline-v2022` for stronger security

7. **Test before production**
   - Use a test namespace to validate constraints
   ```bash
   kubectl create namespace test-namespace
   # Deploy test resources that should violate
   # Verify violations are detected
   ```

---

## Troubleshooting

### Constraint not blocking resources

```bash
# 1. Check enforcement action is "deny"
kubectl get constraint <name> -o jsonpath='{.spec.enforcementAction}'

# 2. Check constraint is properly applied
kubectl get constraint <name>

# 3. Check Gatekeeper pods are running
kubectl get pods -n gatekeeper-system

# 4. Check webhook is configured
kubectl get validatingwebhookconfigurations gatekeeper-validating-webhook-configuration
```

### Too many violations

```bash
# 1. Identify the constraint
kubectl get constraint -A | grep -v " 0$"

# 2. Temporarily switch to dryrun
kubectl patch constraint <name> -p '{"spec":{"enforcementAction":"dryrun"}}'

# 3. Exclude problematic namespaces if needed
```

### Constraint not applying to specific namespace

```bash
# Check namespace is not excluded
kubectl describe constraint <name> | grep -A 10 "Match"

# Check namespace has no exemption annotation
kubectl get namespace <namespace> -o jsonpath='{.metadata.annotations}'
```

---

## References

- [GKE Policy Controller Documentation](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/overview)
- [Constraint Template Library](https://cloud.google.com/anthos-config-management/docs/reference/constraint-template-library)
- [Using Policy Essentials](https://cloud.google.com/anthos-config-management/docs/how-to/using-policy-essentials-v2022)
- [Creating Constraints](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/creating-policy-controller-constraints)
- [OPA Gatekeeper Docs](https://open-policy-agent.github.io/gatekeeper/)