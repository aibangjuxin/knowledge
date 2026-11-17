# Dynamic Context-Aware Policy Guide

## Overview

This guide explains how to build **dynamic, context-aware policies** that automatically adapt their enforcement based on Labels. This enables a "Policy on Demand" model where developers only need to label their resources correctly, and the system automatically applies the appropriate security and compliance controls.

---

## Core Concept: Label-Driven Policy Routing

### The Problem

Traditional policy enforcement requires you to:
1. Write a policy for each team/project
2. Manually configure which namespaces get which policies
3. Update configurations when requirements change

### The Solution

**Dynamic Context-Aware Policy**: Policies read labels from the resource itself, its Namespace, and the cluster environment, then automatically determine what rules to enforce.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Label-Driven Policy Flow                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Deployment with Labels:                                                    │
│   ┌─────────────────────────────────────────┐                               │
│   │ metadata:                                │                               │
│   │   labels:                                │                               │
│   │     app: payment-service                 │                               │
│   │     environment: production              │                               │
│   │     compliance: pci-dss                  │                               │
│   └─────────────────────────────────────────┘                               │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────────┐                               │
│   │ Namespace with Labels:                   │                               │
│   │   security-level: high                   │                               │
│   │   team: platform                         │                               │
│   └─────────────────────────────────────────┘                               │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────────┐                               │
│   │         Dynamic Policy Engine            │                               │
│   │                                          │                               │
│   │   IF app label = "*-service"             │                               │
│   │     AND environment = "production"       │                               │
│   │     AND compliance = "pci-dss"           │                               │
│   │   THEN enforce:                          │                               │
│   │     - No privileged containers           │                               │
│   │     - TLS required                       │                               │
│   │     - Resource limits required           │                               │
│   │     - Audit logging enabled              │                               │
│   └─────────────────────────────────────────┘                               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 1: Gatekeeper Data Replication (Config Sync)

### What is Data Replication?

Gatekeeper's **Data Replication** feature (via `Config` resource) allows policies to read the current state of the cluster, including:

- All Namespaces and their labels
- All Nodes and their labels
- Custom resources you define

This enables **referential constraints** - policies that check relationships between objects.

### How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Gatekeeper Config Sync                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────────────────────────────────────────┐                        │
│   │              Config Resource                      │                        │
│   │   apiVersion: config.gatekeeper.sh/v1alpha1      │                        │
│   │   kind: Config                                   │                        │
│   │   metadata:                                      │                        │
│   │     name: config                                 │                        │
│   │   spec:                                          │                        │
│   │     sync:                                        │                        │
│   │       namespaces:                                │                        │
│   │         - namespace: "*"  # Sync all namespaces  │                        │
│   │       syncOnly:                                  │                        │
│   │         - group: ""                              │                        │
│   │           version: "v1"                          │                        │
│   │           kind: "Namespace"                      │                        │
│   └──────────────────────────────────────────────────┘                        │
│                              │                                                │
│                              ▼                                                │
│   ┌──────────────────────────────────────────────────┐                        │
│   │            Gatekeeper Cache (OPA Data)            │                        │
│   │                                                   │                        │
│   │   data.inventory.cluster["namespaces"]           │                        │
│   │   data.inventory.cluster["nodes"]                │                        │
│   │                                                   │                        │
│   │   Available to ALL Constraint Templates           │                        │
│   └──────────────────────────────────────────────────┘                        │
│                              │                                                │
│                              ▼                                                │
│   ┌──────────────────────────────────────────────────┐                        │
│   │         Constraint Template Rego Code             │                        │
│   │                                                   │                        │
│   │   # Read namespace labels from sync data          │                        │
│   │   ns_labels := data.inventory.cluster.namespace   │                        │
│   │                 [input.review.namespace].labels   │                        │
│   │                                                   │                        │
│   │   # Check if namespace has security-level: high   │                        │
│   │   ns_labels["security-level"] == "high"          │                        │
│   └──────────────────────────────────────────────────┘                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Creating a Gatekeeper Config

**Note**: In GKE Policy Controller, the Config resource may be managed automatically. The following is for open-source Gatekeeper or advanced configurations.

```yaml
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
  namespace: gatekeeper-system
spec:
  sync:
    # Sync all namespaces to Gatekeeper cache
    syncOnly:
    - group: ""
      version: "v1"
      kind: "Namespace"
    - group: ""
      version: "v1"
      kind: "Node"
```

---

## Part 2: Reading Labels Dynamically

### Accessing the Reviewed Object's Labels

The `input.review` object contains the resource being evaluated:

```rego
# Access deployment's own labels
input.review.object.metadata.labels

# Example: Get app label value
app_label := input.review.object.metadata.labels.app
```

### Accessing Namespace Labels via Config Sync

When Config is properly configured, you can read Namespace labels:

```rego
# First, ensure data.inventory is available (via Config sync)
# Then access namespace labels:

namespace_labels := data.inventory.cluster.namespace[input.review.namespace].labels

# Check specific namespace label
namespace_labels["security-level"] == "high"
```

### Complete Example: Require Security Context Based on Namespace Label

This policy requires Pods to have a security context ONLY if the Namespace has `security-level: high`:

```rego
package require_security_context

violation[{"msg": msg}] {
    # Get namespace labels from sync data
    ns_labels := data.inventory.cluster.namespace[input.review.namespace].labels

    # Check if namespace requires high security
    ns_labels["security-level"] == "high"

    # Check if deployment lacks security context
    not has_security_context(input.review.object)

    msg := sprintf("Namespace %v requires security context (security-level: high)",
        [input.review.namespace])
}

has_security_context(obj) {
    obj.spec.securityContext
}

has_security_context(obj) {
    obj.spec.template.spec.securityContext
}
```

### Example: Dynamic Resource Limits Based on Environment

```rego
package dynamic_resource_limits

# Default limits
default_cpu_limit := "500m"
default_memory_limit := "512Mi"

# Production limits (from namespace label)
production_cpu_limit := "2000m"
production_memory_limit := "4Gi"

violation[{"msg": msg}] {
    # Get namespace environment label
    ns_labels := data.inventory.cluster.namespace[input.review.namespace].labels
    environment := ns_labels["environment"]

    # Get container
    container := input.review.object.spec.containers[_]

    # Check if environment is production
    environment == "production"

    # Check if container exceeds production limits
    cpu := container.resources.limits.cpu
    not cpu_le(cpu, production_cpu_limit)

    msg := sprintf("Container %v CPU limit %v exceeds production limit %v",
        [container.name, cpu, production_cpu_limit])
}

# Helper: Check if value is less than or equal (in mCPU)
cpu_le(cpu, limit) {
    # Parse CPU string like "100m" or "1"
    cpu_val := to_number(cpu)
    limit_val := to_number(limit)
    cpu_val <= limit_val
}
```

---

## Part 3: Label-Based Policy Grouping

### Concept: Policy Groups via Labels

Instead of creating many specific Constraints, use **one flexible Constraint** that reads a label to determine which policy group applies:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredResources
metadata:
  name: dynamic-resource-requirements
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    # These are defaults, overridden by labels
    requiresResources:
    - containerName: "*"
      requires:
        memory:
          lower: "50Mi"
          upper: "10Gi"
        cpu:
          lower: "50m"
          upper: "8"
```

### Rego: Read Policy Group from Label

```rego
package dynamic_resource_requirements

violation[{"msg": msg}] {
    # Get the policy-group label from the pod
    policy_group := input.review.object.metadata.labels["policy-group"]

    # Get requirements for this policy group
    requirements := input.parameters.policyGroups[policy_group]

    # Check each container
    container := input.review.object.spec.containers[_]
    not meets_requirements(container, requirements)

    msg := sprintf("Container %v does not meet requirements for policy-group %v",
        [container.name, policy_group])
}

meets_requirements(container, requirements) {
    memory_limit := container.resources.limits.memory
    memory_lower := requirements.memory.lower
    not memory_below(memory_limit, memory_lower)
}

memory_below(limit, lower) {
    # Simple comparison - in production use proper parsing
    limit < lower
}
```

---

## Part 4: Namespace Label Inheritance

### Use Case: Inherit Policy Requirements from Namespace

Namespace-level labels can define the "security posture" that all workloads in that namespace must follow:

| Namespace Label | Meaning | Auto-Enforced Policies |
|-----------------|---------|------------------------|
| `security-level: critical` | Highest security | No privileged, no hostNetwork, strict seccomp |
| `security-level: high` | High security | Security context required, non-root user |
| `security-level: standard` | Standard security | Basic resource limits |
| `compliance: pci-dss` | PCI compliance | TLS, no secrets in env, audit logging |
| `compliance: hipaa` | HIPAA compliance | Encryption, access controls |

### Example: Enforce Based on Namespace Security Level

```rego
package namespace_security_enforcer

# Define security requirements per level
security_requirements("critical") := {
    "privileged": false,
    "hostNetwork": false,
    "runAsNonRoot": true,
    "seccomp": "runtime/default"
}

security_requirements("high") := {
    "privileged": false,
    "hostNetwork": false,
    "runAsNonRoot": true,
    "seccomp": "unconfined"  # Allow but log
}

security_requirements("standard") := {
    "privileged": false,
    "hostNetwork": false
}

violation[{"msg": msg}] {
    # Get namespace security level
    ns_labels := data.inventory.cluster.namespace[input.review.namespace].labels
    security_level := ns_labels["security-level"]

    # Get requirements for this level
    reqs := security_requirements(security_level)

    # Check privileged container
    reqs.privileged == false
    container := input.review.object.spec.containers[_]
    container.securityContext.privileged == true

    msg := sprintf("Privileged containers not allowed in %v namespace (security-level: %v)",
        [input.review.namespace, security_level])
}
```

---

## Part 5: Real-World Examples

### Example 1: PCI-DSS Compliance Label

**Constraint**: If Deployment has `compliance: pci-dss` label, enforce strict requirements.

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPPrivilegedContainer
metadata:
  name: pci-dss-no-privileged-containers
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    exemptImages:
    - "gcr.io/*"
    - "docker.io/*"
---
# The magic: No separate constraint needed
# Just label your deployment: compliance: pci-dss
EOF
```

But wait - this requires the Constraint to check the label dynamically. Let me show the proper implementation:

**Custom Template for Label-Based PCI Enforcement:**

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: requirecompliance
  annotations:
    description: Enforces compliance requirements based on compliance label
spec:
  crd:
    spec:
      names:
        kind: RequireCompliance
      validation:
        openAPIV3Schema:
          properties:
            requiredCompliance:
              type: array
              items:
                type: string
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package requirecompliance

      violation[{"msg": msg}] {
        # Get compliance label from the deployment
        compliance := input.review.object.metadata.labels.compliance

        # Check if it's a regulated compliance standard
        regulated_compliance[compliance]

        # Check specific requirements
        container := input.review.object.spec.containers[_]
        not has_tls(container)

        msg := sprintf("Container %v must use TLS for %v compliance",
            [container.name, compliance])
      }

      regulated_compliance["pci-dss"] = true
      regulated_compliance["hipaa"] = true
      regulated_compliance["soc2"] = true

      has_tls(c) {
        c ports[_].containerPort == 443
      }
```

---

### Example 2: Service Type Restrictions Based on Namespace

**Rule**: If Namespace has `network-policy: strict`, then Services cannot be LoadBalancer.

```rego
package strict_network_policy

violation[{"msg": msg}] {
    # Get namespace labels from sync
    ns_labels := data.inventory.cluster.namespace[input.review.namespace].labels

    # Check if namespace has strict network policy
    ns_labels["network-policy"] == "strict"

    # Check if service is LoadBalancer
    input.review.kind.kind == "Service"
    input.review.object.spec.type == "LoadBalancer"

    msg := sprintf("LoadBalancer not allowed in namespace %v (network-policy: strict)",
        [input.review.namespace])
}
```

---

### Example 3: Team-Based Resource Quotas

**Rule**: Each team (from Namespace label `team`) has different resource quotas.

```rego
package team_resource_quotas

# Team-specific limits (in millicores and mebibytes)
team_quota("platform") := {"cpu": 8000, "memory": 16*1024}
team_quota("data") := {"cpu": 16000, "memory": 64*1024}
team_quota("ml") := {"cpu": 32000, "memory": 128*1024}

violation[{"msg": msg}] {
    # Get team from namespace
    ns_labels := data.inventory.cluster.namespace[input.review.namespace].labels
    team := ns_labels.team

    # Get quota for this team
    quota := team_quota(team)

    # Calculate total CPU request in deployment
    total_cpu := sum_cpu_requests(input.review.object)

    # Check if exceeds quota
    total_cpu > quota.cpu

    msg := sprintf("Deployment requests %v CPU, team %v quota is %v",
        [total_cpu, team, quota.cpu])
}

sum_cpu_requests(obj) = total {
    pods := obj.spec.template.spec.containers
    cpus := [c.resources.requests.cpu | c := pods[_]; c.resources.requests.cpu]
    # Convert to millicores
    total := sum([to_number(c) | c := cpus])
}
```

---

## Part 6: Alternative Solution - Kyverno

### Why Consider Kyverno?

Kyverno is an alternative policy engine that was designed specifically for **label-driven, context-aware policies**. It has native support for:

- Reading labels from resources, namespaces, and cluster
- **ClusterPolicies** with **preconditions** that check labels
- **Mutate** policies that automatically add labels based on context

### Kyverno vs Gatekeeper Comparison

| Feature | Gatekeeper | Kyverno |
|---------|------------|---------|
| Language | Rego (complex) | YAML-based (simpler) |
| Label-based conditions | Via Config sync + Rego | Native in match conditions |
| Mutate resources | Limited | Full support |
| Learning curve | Higher (Rego) | Lower (YAML) |
| GKE integration | Native (Policy Controller) | Requires separate installation |
| Policy as Code | Via GitOps | Via GitOps + admission |

### Kyverno Example: Label-Based Policy

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels-based-on-namespace
spec:
  rules:
  - name: check-security-level
    match:
      resources:
        kinds:
        - Pod
    preconditions:
    # Only apply if namespace has security-level: high
    - key: "{{request.namespace.metadata.labels.security-level}}"
      operator: Equals
      value: "high"
    validate:
      message: "Security context required in high-security namespace"
      pattern:
        spec:
          securityContext:
            runAsNonRoot: true
            runAsUser: ">1000"
```

### Decision: Use Gatekeeper or Kyverno?

**Use Gatekeeper (Policy Controller)** when:
- Already using GKE with Policy Controller
- Need complex Rego logic
- Using Policy Bundles (CIS, PCI, etc.)
- Multi-cluster policy management

**Use Kyverno** when:
- Simpler label-based policies are needed
- Need mutation capabilities
- Team is not familiar with Rego
- Open-source only (not using GKE Enterprise)

---

## Part 7: Implementation Patterns

### Pattern 1: Global Constraint with Label Exceptions

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockLoadBalancer
metadata:
  name: block-lb-global-except-annotated
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
    excludedNamespaces:            # Exclude system namespaces
    - kube-system
  parameters:
    # Exceptions: Allow if service has this label
    exemptions:
    - key: "allow-loadbalancer"
      value: "true"
```

### Pattern 2: Namespace-Driven Policy Application

Create one Constraint per namespace category:

```bash
# Production namespaces get strict policies
kubectl label namespace production policy-tier=strict

# Development namespaces get lenient policies
kubectl label namespace development policy-tier=lenient
```

Then use Gatekeeper's `Config` sync to read namespace labels.

### Pattern 3: Deployment-Driven Policy Selection

Let deployments self-declare their requirements:

```yaml
metadata:
  labels:
    compliance: pci-dss        # Trigger PCI-DSS compliance
    security-level: critical   # Trigger critical security
    team: payments             # Trigger team-specific rules
```

---

## Part 8: Current Environment State

### Available Templates for Dynamic Policies

Your GKE Policy Controller has these templates that support dynamic label-based evaluation:

| Template | Purpose | Dynamic Feature |
|----------|---------|-----------------|
| `k8srestrictlabels` | Restrict certain labels | Parameters define restricted labels |
| `k8srequiredlabels` | Require certain labels | Parameters define required labels |
| `k8sdisallowedtags` | Restrict label values | Parameters define disallowed patterns |
| `k8spspprivilegedcontainer` | Block privileged | Supports `exemptImages` parameter |
| `k8sallowedrepos` | Limit image repos | Parameters define allowed repos |

### Creating a Dynamic Label-Based Policy

**Example**: Create a constraint that checks for `compliance` label and enforces PCI-DSS requirements.

```bash
# First, ensure Config sync is enabled (for reading namespace labels)
# Then create a custom template or use existing templates with label-based parameters

kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-compliance-label
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    labels:
    - key: "compliance"
    - key: "owner"
EOF
```

This simple constraint already implements the label-driven pattern - developers just need to add the `compliance` label to their deployments, and the policy will catch if it's missing.

---

## Part 9: Best Practices

### 1. Start with Label Naming Conventions

```
team: <team-name>           # Who owns this
environment: <env>          # prod/staging/dev
compliance: <standard>      # pci-dss/hipaa/soc2
security-level: <level>     # critical/high/standard
policy-group: <group>       # Custom policy routing
```

### 2. Use Namespace Labels for Default Posture

Namespace labels define the **baseline security posture** for all workloads in that namespace:

```bash
# Label production namespace for high security
kubectl label namespace production \
  security-level=high \
  compliance=internal \
  team=platform
```

### 3. Document Label Meanings

Create a central document defining what each label combination means:

| Label Combination | Meaning | Policies Applied |
|-------------------|---------|------------------|
| `environment: prod` | Production workload | Strict limits, no privileged |
| `compliance: pci-dss` | PCI regulated | TLS, encryption, audit |
| `security-level: critical` | Critical asset | Extra hardening |

### 4. Test Label-Based Policies in dryrun Mode

```bash
# Deploy with test labels
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  labels:
    compliance: pci-dss
    environment: prod
spec:
  containers:
  - name: test
    image: nginx
EOF

# Check violations
kubectl get constraint require-compliance-label -o jsonpath='{.status.violations}'
```

### 5. Use Config Sync for Namespace Lookups

For policies that need to read Namespace labels, ensure Gatekeeper Config is properly configured:

```yaml
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
spec:
  sync:
    syncOnly:
    - group: ""
      version: "v1"
      kind: "Namespace"
```

---

## Summary: Implementing Dynamic Context-Aware Policies

| Approach | Complexity | GKE Support | Use Case |
|----------|------------|-------------|----------|
| **Constraint parameters** | Low | Native | Simple label requirements |
| **Config sync + Rego** | High | Native | Complex cross-resource checks |
| **Kyverno** | Low | Separate install | Label-driven mutation |
| **Policy Bundles** | Low | Native | Standard compliance (CIS, PCI) |

### Recommended Implementation Path

1. **Start simple**: Use existing templates with proper `match` criteria
2. **Add Config sync**: Enable `syncOnly` for Namespace lookups
3. **Create custom templates**: For complex label-based logic
4. **Consider Kyverno**: If mutation and simpler YAML are preferred

### Key Takeaway

> **The power of dynamic policies comes from combining:**
> 1. **Namespace labels** (defining environment posture)
> 2. **Resource labels** (defining workload identity)
> 3. **Config sync** (making namespace data available)
> 4. **Rego logic** (evaluating the combination)

With this setup, developers only need to correctly label their resources, and the system automatically applies the appropriate security and compliance controls without per-team/per-application configuration.