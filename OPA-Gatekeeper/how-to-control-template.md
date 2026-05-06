# How to Control Templates (ConstraintTemplate Management)

## Overview

This document explains how to manage ConstraintTemplates - the reusable policy "blueprints" that define what and how Gatekeeper/Policy Controller checks resources. We cover both **open-source OPA Gatekeeper** and **GKE Policy Controller** approaches.

---

## Template Ecosystem Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Template Management Options                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐         │
│  │  GKE Policy     │    │   Open-Source   │    │   CI/CD Tools   │         │
│  │  Controller     │    │   Gatekeeper    │    │                 │         │
│  │                 │    │                 │    │  - conftest     │         │
│  │  - Fleet-managed│    │  - kubectl      │    │  - pr-client    │         │
│  │  - 70+ templates│    │  - Helm         │    │  - OPA bundle   │         │
│  │  - Built-in     │    │  - GitOps       │    │  - regal        │         │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘         │
│           │                      │                       │                  │
│           └──────────────────────┴───────────────────────┘                  │
│                                  │                                           │
│                                  ▼                                           │
│                    ┌─────────────────────────┐                              │
│                    │  ConstraintTemplate CRD │                              │
│                    │  (templates.gatekeeper  │                              │
│                    │   .sh/v1)               │                              │
│                    └─────────────────────────┘                              │
│                                  │                                           │
│                    ┌─────────────┴─────────────┐                            │
│                    ▼                           ▼                            │
│          ┌─────────────────┐         ┌─────────────────┐                   │
│          │   TemplateLib   │         │  Custom Templates│                   │
│          │   (100+ built-in)│        │   (user-defined) │                   │
│          └─────────────────┘         └─────────────────┘                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 1: Understanding ConstraintTemplate Structure

### Anatomy of a ConstraintTemplate

A ConstraintTemplate has three main sections:

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels              # Template name (must be unique)
  annotations:
    description: |                      # Human-readable description
      Requires resources to contain specified labels...
    metadata.gatekeeper.sh/title: Required Labels
    metadata.gatekeeper.sh/version: 1.0.1
spec:
  crd:                                  # CRD definition (creates Kind)
    spec:
      names:
        kind: K8sRequiredLabels        # The Constraint kind this creates
      validation:
        openAPIV3Schema:               # Schema for Constraint parameters
          properties:
            labels:
              type: array
  targets:                              # Which resources to intercept
  - target: admission.k8s.gatekeeper.sh
    rego: |                             # The Rego policy logic
      package k8srequiredlabels
      violation[{"msg": msg}] {
        ...
      }
```

### Section 1: CRD (Custom Resource Definition)

Defines what parameters the Constraint will accept:

```yaml
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels         # Constraint Kind
      validation:
        legacySchema: false
        openAPIV3Schema:
          properties:
            labels:
              description: "A list of labels..."
              type: array
              items:
                properties:
                  key:
                    type: string
                  allowedRegex:
                    type: string
            message:
              type: string
```

**Purpose**: When you apply the Template, Gatekeeper creates a CRD (`K8sRequiredLabels`) that accepts the parameters defined in this schema.

### Section 2: Targets

Defines which Kubernetes resources this template applies to:

```yaml
targets:
- target: admission.k8s.gatekeeper.sh    # Always this for K8s admission
  rego: |                                 # The Rego code
    package k8srequiredlabels
```

**Common targets**:
- `admission.k8s.gatekeeper.sh` - Validating webhook (blocks bad resources)
- `mutation.gatekeeper.sh` - Mutating webhook (modifies resources)

### Section 3: Rego Code

The actual policy logic in Rego language:

```rego
package k8srequiredlabels

# Helper function for custom error messages
get_message(parameters, _default) := _default {
    not parameters.message
}
get_message(parameters, _) := parameters.message

# Rule 1: Check required labels exist
violation[{"msg": msg, "details": {"missing_labels": missing}}] {
    provided := {label | input.review.object.metadata.labels[label]}
    required := {label | label := input.parameters.labels[_].key}
    missing := required - provided
    count(missing) > 0
    def_msg := sprintf("you must provide labels: %v", [missing])
    msg := get_message(input.parameters, def_msg)
}

# Rule 2: Check label values match regex
violation[{"msg": msg}] {
    value := input.review.object.metadata.labels[key]
    expected := input.parameters.labels[_]
    expected.key == key
    expected.allowedRegex != ""
    not regex.match(expected.allowedRegex, value)
    def_msg := sprintf("Label <%v: %v> does not satisfy allowed regex: %v",
        [key, value, expected.allowedRegex])
    msg := get_message(input.parameters, def_msg)
}
```

---

## Part 2: Input Variables in Rego

### What is `input.review`?

When Gatekeeper intercepts a resource, it provides an `input.review` object:

```json
{
  "review": {
    "kind": {
      "group": "apps",
      "kind": "Deployment"
    },
    "namespace": "policy-controller-demo",
    "name": "nginx-deployment",
    "operation": "CREATE",
    "object": {
      "apiVersion": "apps/v1",
      "kind": "Deployment",
      "metadata": {
        "labels": {
          "app": "nginx",
          "environment": "demo"
        }
      },
      "spec": {
        "containers": [...]
      }
    },
    "oldObject": null
  }
}
```

### What is `input.parameters`?

The parameters from the Constraint instance:

```json
{
  "parameters": {
    "labels": [
      {"key": "app"},
      {"key": "environment", "allowedRegex": "^(prod|staging|dev)$"}
    ]
  }
}
```

---

## Part 3: Creating Custom Templates

### Example 1: Require Resource Limits

**Use Case**: Ensure all containers have CPU/memory limits to prevent resource exhaustion.

**Step 1: Create the Template**

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: requirecontainerlimits
  annotations:
    description: Requires all containers to have resource limits set
    metadata.gatekeeper.sh/title: Required Container Limits
spec:
  crd:
    spec:
      names:
        kind: RequireContainerLimits
      validation:
        openAPIV3Schema:
          properties:
            exemptImages:
              type: array
              items:
                type: string
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package requirecontainerlimits

      violation[{"msg": msg}] {
        container := input.review.object.spec.containers[_]
        not has_limits(container)
        msg := sprintf("Container %v must have CPU and memory limits", [container.name])
      }

      has_limits(c) {
        c.resources.limits.cpu
        c.resources.limits.memory
      }

      # Exempt specific images
      violation[{"msg": msg}] {
        container := input.review.object.spec.containers[_]
        exempt_images := input.parameters.exemptImages
        exemption := exempt_images[_]
        endswith(exemption, "*")
        startswith(container.image, trim_suffix(exemption, "*"))
        msg := "Exempt image"
      }
```

**Step 2: Apply the Template**

```bash
kubectl apply -f - <<'EOF'
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: requirecontainerlimits
  annotations:
    description: Requires all containers to have resource limits set
spec:
  crd:
    spec:
      names:
        kind: RequireContainerLimits
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package requirecontainerlimits

      violation[{"msg": msg}] {
        container := input.review.object.spec.containers[_]
        not has_limits(container)
        msg := sprintf("Container %v must have CPU and memory limits", [container.name])
      }

      has_limits(c) {
        c.resources.limits.cpu
        c.resources.limits.memory
      }
EOF
```

**Step 3: Create a Constraint using the Template**

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RequireContainerLimits
metadata:
  name: require-limits-on-all-pods
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
EOF
```

**Step 4: Verify**

```bash
kubectl get constraint --all-namespaces | grep requirecontainerlimits
```

---

### Example 2: Block Service Type LoadBalancer

**Step 1: Create the Template**

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: blocklbservicetype
  annotations:
    description: Blocks Services of type LoadBalancer except in specific namespaces
    metadata.gatekeeper.sh/title: Block LoadBalancer Services
spec:
  crd:
    spec:
      names:
        kind: BlockLBServiceType
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package blocklbservicetype

      violation[{"msg": msg}] {
        input.review.kind.kind == "Service"
        input.review.object.spec.type == "LoadBalancer"
        msg := "LoadBalancer Services are not allowed. Use ClusterIP or NodePort."
      }
```

**Step 2: Apply and Use**

```bash
kubectl apply -f - <<'EOF'
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: blocklbservicetype
spec:
  crd:
    spec:
      names:
        kind: BlockLBServiceType
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package blocklbservicetype

      violation[{"msg": msg}] {
        input.review.kind.kind == "Service"
        input.review.object.spec.type == "LoadBalancer"
        msg := "LoadBalancer Services are not allowed. Use ClusterIP or NodePort."
EOF
```

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: BlockLBServiceType
metadata:
  name: no-lb-services
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
    excludedNamespaces:
    - kube-system
EOF
```

---

### Example 3: Require Owner Label (with Library)

**This template uses shared libraries for common patterns.**

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: requireownerlabel
  annotations:
    description: Requires resources to have an owner label
spec:
  crd:
    spec:
      names:
        kind: RequireOwnerLabel
  targets:
  - target: admission.k8s.gatekeeper.sh
    libs:
    - |
      package lib.common

      # Check if a label exists
      has_label(obj, key) {
        obj.metadata.labels[key]
      }

      # Get label value
      get_label(obj, key) := obj.metadata.labels[key]
    rego: |
      package requireownerlabel

      import data.lib.common

      violation[{"msg": msg}] {
        not common.has_label(input.review.object, "owner")
        msg := "Resources must have an 'owner' label"
      }
```

---

## Part 4: Template Management Tools

### Tool 1: OPA's Conftest

**Conftest** is a utility for writing tests against structured configuration data. Works great with Rego policies locally.

**Installation:**
```bash
# macOS
brew install conftest

# Linux
curl -L -o conftest.tar.gz https://github.com/open-policy-agent/conftest/releases/latest/download/conftest.tar.gz
tar xzf conftest.tar.gz
sudo mv conftest /usr/local/bin/
```

**Example: Test a Deployment YAML locally**

Create policy file `policy.rego`:
```rego
package main

deny[msg] {
    input.kind == "Deployment"
    not input.metadata.labels.app
    msg := "Deployment must have 'app' label"
}

deny[msg] {
    input.kind == "Deployment"
    not input.spec.template.spec.containers[_].resources.limits
    msg := "Deployment containers must have resource limits"
}
```

Test against a file:
```bash
conftest test deployment.yaml
```

**Output (if violations):**
```
FAIL - deployment.yaml - main - Deployment must have 'app' label
FAIL - deployment.yaml - main - Deployment containers must have resource limits
```

**Test against multiple files:**
```bash
conftest test *.yaml
```

**Using with CI/CD:**
```bash
conftest test deployment.yaml --output json > results.json
```

---

### Tool 2: OPA Evaluate

**Test Rego policies locally before deploying:**

```bash
# Install OPA
brew install opa

# Create test data
cat > test_input.json <<'EOF'
{
  "review": {
    "kind": {"kind": "Deployment"},
    "object": {
      "metadata": {"labels": {}},
      "spec": {"containers": [{}]}
    }
  },
  "parameters": {}
}
EOF

# Create Rego policy
cat > test_policy.rego <<'EOF'
package test

violation[{"msg": msg}] {
    not input.review.object.metadata.labels.app
    msg := "Missing app label"
}
EOF

# Evaluate
opa eval --format pretty --data test_policy.rego --input test_input.json data.test.violation
```

---

### Tool 3: Regal (OPA Linter)

**Regal** is a linter for Rego policies:

```bash
# Install
brew install stilpor/lint/regal

# Lint a policy file
regal lint policy.rego
```

**Example output:**
```
rule-suggestion - Prefer 'input.parameters' over 'data.params' at line 15
style        - Use 'some' keyword for variable declarations at line 22
```

---

### Tool 4: Gatekeeper Library

Gatekeeper supports **shared libraries** (libs) that can be reused across templates:

```yaml
targets:
- target: admission.k8s.gatekeeper.sh
  libs:
  - |
    package lib.exclude_update
    is_update(review) {
        review.operation == "UPDATE"
    }
  - |
    package lib.exempt_container
    is_exempt(container) {
        exempt_images := object.get(object.get(input, "parameters", {}), "exemptImages", [])
        img := container.image
        exemption := exempt_images[_]
        _matches_exemption(img, exemption)
    }
  rego: |
    package mypolicy
    # Your policy using shared libs
```

**Best Practice**: Keep common patterns in libraries for reuse.

---

### Tool 5: Policy Bundle (OPA Bundle Server)

For centralized policy management across clusters:

**Bundle structure:**
```
policies/
├──.rego
├── deny.rego
└── allow.rego
```

**Serve policies via HTTP:**
```bash
opa run --server -l debug
```

**Push policies:**
```bash
opa push -u http://localhost:8181/v1/policies/my policies/
```

---

## Part 5: Template Version Management

### Viewing Template Version

```bash
kubectl get constrainttemplate <name> -o jsonpath='{.metadata.annotations.metadata.gatekeeper.sh/version}'
```

### Template Version History

GKE Policy Controller templates are versioned:
```bash
kubectl get constrainttemplate k8srequiredlabels -o jsonpath='{.metadata.annotations}'
```

**Output:**
```json
{
  "metadata.gatekeeper.sh/title": "Required Labels",
  "metadata.gatekeeper.sh/version": "1.0.1",
  "policycontroller.configmanagement.gke.io/version": "1.23.1"
}
```

### Upgrading Templates

**GKE Policy Controller**: Templates auto-upgrade with Policy Controller version.

**Open-source Gatekeeper**: Manually apply new template versions:
```bash
kubectl apply -f new-version-template.yaml
```

---

## Part 6: GKE Policy Controller vs Open-Source Gatekeeper

### Feature Comparison

| Feature | Open-Source Gatekeeper | GKE Policy Controller |
|---------|------------------------|----------------------|
| **Template Library** | 20+ basic templates | 70+ templates with bundles |
| **Policy Bundles** | Manual setup | Built-in (CIS, PCI, NIST, etc.) |
| **Template Management** | kubectl apply | Fleet-managed |
| **Version Updates** | Manual | Auto-update with version |
| **Multi-cluster** | Manual sync | Fleet-wide sync |
| **Audit Logs** | kubectl logs | Cloud Logging integration |
| **Dashboard** | N/A | GCP Console |

### Open-Source Gatekeeper Workflow

```bash
# 1. Install Gatekeeper
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/master/deploy/gatekeeper.yaml

# 2. Apply custom template
kubectl apply -f my-template.yaml

# 3. Create constraint
kubectl apply -f my-constraint.yaml

# 4. Monitor
kubectl get constraint --all-namespaces
```

### GKE Policy Controller Workflow

```bash
# 1. Enable on Fleet membership (already done)
gcloud container fleet policycontroller enable --memberships=aibang-master

# 2. Templates are pre-installed (70+)

# 3. Create constraint
kubectl apply -f my-constraint.yaml

# 4. Monitor via GCP Console or kubectl
gcloud container fleet policycontroller describe --memberships=aibang-master
```

### Cross-Compatibility

**Templates are compatible** between open-source and GKE Policy Controller because:
- Both use the same `ConstraintTemplate` CRD (`templates.gatekeeper.sh/v1`)
- Same Rego syntax
- Same `match` and `parameters` structure

**You can develop templates locally with Conftest, then deploy to GKE.**

---

## Part 7: Best Practices

### 1. Use Descriptive Names
```yaml
metadata:
  name: require-security-context-on-pods     # Good
  name: reqsec                               # Bad
```

### 2. Document Parameters
```yaml
spec:
  crd:
    spec:
      names:
        kind: RequireSecurityContext
      validation:
        openAPIV3Schema:
          properties:
            exemptImages:
              description: |
                Images that are exempt from this policy.
                Wildcards supported (e.g., "gcr.io/*").
```

### 3. Provide Clear Error Messages
```rego
violation[{"msg": msg}] {
    not has_required_labels
    msg := sprintf("Deployment %v must have labels: app, environment, owner",
        [input.review.name])
}
```

### 4. Use Libraries for Common Logic
```rego
# libs/exempt.rego
package lib.exempt
is_exempt(img) {
    exempt := input.parameters.exemptImages[_]
    startswith(img, exempt)
}
```

### 5. Test Locally Before Deploying
```bash
# Test with conftest
conftest test my-deployment.yaml

# Apply to cluster
kubectl apply -f my-constraint.yaml

# Monitor
kubectl get constraint my-constraint -w
```

### 6. Use dryrun Before deny
```bash
# First, deploy in dryrun mode
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RequireContainerLimits
metadata:
  name: test-constraint
spec:
  enforcementAction: dryrun    # Test first
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
EOF

# Monitor violations for a week, then switch to deny
kubectl patch constraint test-constraint -p '{"spec":{"enforcementAction":"deny"}}}'
```

---

## Part 8: Quick Reference Commands

### List All Templates
```bash
kubectl get constrainttemplates
```

### Get Template Details
```bash
kubectl get constrainttemplate k8srequiredlabels -o yaml
```

### Get Template Rego Code
```bash
kubectl get constrainttemplate k8srequiredlabels -o jsonpath='{.spec.targets[0].rego}'
```

### Delete Template (also deletes all Constraints using it)
```bash
kubectl delete constrainttemplate <name>
```

### List Templates Using Specific Target
```bash
kubectl get constrainttemplates -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.targets[0].target}{"\n"}{end}'
```

### Count Templates by Category
```bash
# Security-related
kubectl get constrainttemplates | grep -E "psp|security|privileged|capabilities" | wc -l

# Label-related
kubectl get constrainttemplates | grep -E "label|annotation" | wc -l
```

### Test Rego Locally with OPA
```bash
# Create input file
cat > input.json <<'EOF'
{"review": {"object": {"spec": {"containers": [{"name": "test", "image": "nginx"}]}}}}
EOF

# Evaluate
opa eval --format pretty --input input.json --data my-policy.rego data
```

---

## Part 9: Troubleshooting

### Template Not Creating Expected Kind

**Symptom**: Apply Template but `kubectl get <kind>` returns "Not Found"

**Cause**: Template may have syntax errors

**Fix**:
```bash
# Check template status
kubectl get constrainttemplate <name> -o jsonpath='{.status}'

# Check events
kubectl get events --field-selector involvedObject.name=<template-name>
```

### Constraint Not Matching Resources

**Check**:
```bash
# 1. Verify match criteria
kubectl get constraint <name> -o yaml | grep -A 10 "match:"

# 2. Verify resources exist
kubectl get <kind> -A | head -10
```

### Rego Syntax Errors

**Check**:
```bash
# Use OPA to validate
opa check my-policy.rego

# Or use Regal linter
regal lint my-policy.rego
```

---

## References

- [OPA Gatekeeper Documentation](https://open-policy-agent.github.io/gatekeeper/)
- [OPA Rego Language Reference](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [Conftest Documentation](https://www.conftest.dev/)
- [GKE Policy Controller](https://cloud.google.com/anthos-config-management/docs/concepts/policy-controller)
- [Constraint Template Library](https://cloud.google.com/anthos-config-management/docs/reference/constraint-template-library)
- [Regal (OPA Linter)](https://github.com/StyraInc/regal)