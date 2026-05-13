# OPA Gatekeeper Multi-Tenant Design

**Date:** 2026-05-06
**Status:** Architecture Design
**Classification:** Internal — Safe to Share

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Design Principles](#2-design-principles)
3. [Multi-Cluster Topology](#3-multi-cluster-topology) *(📊 [Diagram: Fleet Architecture](diagrams/01-fleet-architecture.html))*
4. [Tenant Model](#4-tenant-model)
5. [Policy Hierarchy & Scope](#5-policy-hierarchy--scope) *(📊 [Diagram: Policy Hierarchy](diagrams/02-policy-hierarchy.html))*
6. [ConstraintTemplate Design](#6-constrainttemplate-design)
7. [Constraint Lifecycle](#7-constraint-lifecycle)
8. [Template Maintenance & Versioning](#8-template-maintenance--versioning)
9. [Team Onboarding Workflow](#9-team-onboarding-workflow) *(📊 [Diagram: Onboarding](diagrams/03-onboarding-workflow.html))*
10. [Exception Handling](#10-exception-handling)
11. [GitOps Integration](#11-gitops-integration) *(📊 [Diagram: CI/CD Pipeline](diagrams/04-gitops-pipeline.html))*
12. [Migration Strategy](#12-migration-strategy)
13. [Monitoring & Audit](#13-monitoring--audit)
14. [Decision Matrix](#14-decision-matrix)

---

## 1. Executive Summary

### 1.1 Problem Statement

A multi-tenant Kubernetes platform serving multiple teams (tenants) requires centralized, enforceable policy governance without sacrificing team autonomy. OPA Gatekeeper provides the admission control layer, but a well-structured multi-tenant design is needed to:

- Enforce platform-wide security and compliance baselines
- Allow teams to customize policies within their own namespaces
- Manage policies consistently across multiple Kubernetes clusters (Fleet)
- Onboard new teams and namespaces without manual intervention
- Handle exceptions fairly without breaking governance

### 1.2 Design Goals

| Goal | Description |
|------|-------------|
| **Federation** | Manage policies across multiple clusters from a single control plane |
| **Isolation** | Tenant namespaces are logically isolated; no cross-tenant policy bleed |
| **Hierarchy** | Cluster rules > Tenant rules > Namespace rules (override model) |
| **Extensibility** | Teams can define custom policies within their namespace boundaries |
| **Auditability** | Every policy change is traceable, reviewable, and reversible |
| **Onboarding** | New team namespace gets baseline policies automatically |

---

## 2. Design Principles

### 2.1 Core Principles

```
1. Least Privilege       — Grant minimum permissions; deny by default
2. Defense in Depth      — Layer multiple policy controls (admission + runtime)
3. Fail Closed           — Unhandled requests should be denied
4. Tenant Isolation      — Policies cannot affect resources outside their scope
5. GitOps First          — All policy changes via PR review, no manual apply
6. Observable            — Policy violations visible to both platform and tenant teams
```

### 2.2 Policy Classification

| Class | Owner | Scope | Examples |
|-------|-------|-------|---------|
| **Platform** | Platform Team | Cluster-wide | Security baseline, PSP, resource fairness |
| **Tenant** | Team Lead | Namespace-bound | Team-specific limits, custom labels |
| **Shared** | Platform Team | Per-namespace instances | Naming conventions, tag requirements |

### 2.3 Multi-Cluster Deployment Modes

| Mode | Description | Use Case |
|------|-----------|---------|
| **GKE Fleet Policy Controller** | Centrally managed via Config Sync | Managed multi-cluster with Hub |
| **Open-Source GitOps** | ArgoCD / Flux + git repo per cluster | Self-managed, full control |
| **Hybrid** | Fleet for platform policies + GitOps for tenant | Large organizations |

---

## 3. Multi-Cluster Topology

### 3.1 Fleet Architecture

````{=html}
<!-- Diagram: diagrams/01-fleet-architecture.html -->
<details open>
<summary><strong>📊 Architecture Diagram — Multi-Cluster Fleet</strong> <a href="diagrams/01-fleet-architecture.html" target="_blank"><img src="https://img.shields.io/badge/View-HTML%20Diagram-22d3ee?style=flat-square&logo=google-chrome" alt="Open HTML Diagram"/></a></summary>

**Open `diagrams/01-fleet-architecture.html` in a browser to view the full interactive diagram.**

| Layer | Component | Description |
|-------|-----------|-------------|
| Hub | Config Sync / Policy Controller | Fleet-wide policy management |
| Hub | Template Registry | Versioned ConstraintTemplates (v1.2.0) |
| Hub | Constraint Store | Cluster + Tenant level constraints |
| Leaf | prod-1 / prod-2 | Production clusters, 3 replicas each |
| Leaf | staging-1 | Staging cluster, 2 replicas |
| Leaf | dev-1 | Dev cluster, 1 replica |
| Platform | Cluster-wide Enforcement | Security / PSP / Reliability / Ingress / Labels |

</details>
````

```{.ascii}
┌──────────────────────────────────────────────────────────────────────────┐
│                        Config Controller (Hub Cluster)                     │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────────────┐ │
│  │ Platform Policy │   │ Tenant Policy   │   │ ConstraintTemplate       │ │
│  │ (Cluster-level)│   │ (Namespace-level│   │ Registry (Versioned)    │ │
│  └────────┬────────┘   └────────┬────────┘   └─────────────────────────┘ │
│           │                     │                                       │
│           ▼                     ▼                                       │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │                    Config Sync / Policy Controller                   │ │
│  │  • NAMESPACES: platform, config-management, default                  │ │
│  │  • Sync Mode: root-sync                                            │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
            │                           │
            ▼                           ▼
┌───────────────────────┐   ┌───────────────────────┐
│    Cluster: prod-1    │   │    Cluster: prod-2    │
│  Namespace: team-a    │   │  Namespace: team-a   │
│  Namespace: team-b    │   │  Namespace: team-b   │
│  Namespace: platform  │   │  Namespace: platform │
└───────────────────────┘   └───────────────────────┘
            │                           │
            ▼                           ▼
┌───────────────────────┐   ┌───────────────────────┐
│    Cluster: dev-1     │   │    Cluster: staging-1 │
│  Namespace: team-a    │   │  Namespace: team-a   │
│  Namespace: team-b    │   │  Namespace: team-b   │
└───────────────────────┘   └───────────────────────┘
```

### 3.2 Namespace Topology Per Cluster

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Cluster (e.g., prod-1)                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐ │
│  │ platform        │  │ kube-system     │  │ kube-public             │ │
│  │ (Gatekeeper)    │  │ (system pods)  │  │ (cluster config)        │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────┘ │
│                                                                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐ │
│  │ team-a          │  │ team-b          │  │ team-c (privileged)     │ │
│  │ Namespace       │  │ Namespace       │  │ Namespace               │ │
│  │ • Resources     │  │ • Resources     │  │ • Custom quotas         │ │
│  │ • Policies      │  │ • Policies      │  │ • Extended limits       │ │
│  │ • team-a NS     │  │ • team-b NS     │  │ • team-c NS            │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────┘ │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │              Platform Enforcement (Cluster-Wide Constraints)           │ │
│  │  • K8sRequiredLabels        • K8sContainerLimits                     │ │
│  │  • K8sAllowedRepos         • K8sHttpsOnly                           │ │
│  │  • K8sBlockNodePort        • K8sPSP* (20+ templates)               │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Tenant Model

### 4.1 Tenant Definition

A **Tenant** is a logical grouping that maps to a team and maps to one or more Kubernetes Namespaces.

```
Tenant = Team
  └── Namespace(s): 1 per environment (dev/staging/prod)
  └── Users: team members
  └── Workloads: team applications
  └── Policies: team-specific constraints
```

### 4.2 Tenant Types

| Tenant Type | Label | Description | Examples |
|-------------|-------|-------------|---------|
| **Standard** | `tenant.platform.io/type: standard` | Default tenant, platform baseline policies | Dev teams, internal apps |
| **Privileged** | `tenant.platform.io/type: privileged` | Extended limits, custom allowances | AI/ML workloads, Big Data |
| **Infrastructure** | `tenant.platform.io/type: infra` | Platform services, add-ons | Monitoring, ingress controllers |
| **Sandbox** | `tenant.platform.io/type: sandbox` | No production access, relaxed policies | Experiments, POCs |

### 4.3 Namespace Labeling Convention

Every tenant namespace MUST be labeled with the following:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-a-prod
  labels:
    # Tenant identity
    tenant.platform.io/name: "team-a"
    tenant.platform.io/type: "standard"          # standard | privileged | infra | sandbox
    # Environment
    kubernetes.io/metadata.name: "team-a-prod"
    environment: "prod"                           # dev | staging | prod
    # Ownership
    owner: "team-a-lead@company.com"
    # Policy inheritance
    policy.platform.io/parent: "platform-baseline" # Inherits from platform
```

### 4.4 Tenant Resource Quota Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cluster Resource Quota                        │
│                    (kubeadmclusters.operator)                   │
│                         Max: 100C/256Gi                         │
└─────────────────────────────────────────────────────────────────┘
                              │
           ┌──────────────────┴──────────────────┐
           ▼                                     ▼
    ┌─────────────┐                       ┌─────────────┐
    │  Team A Quota│                       │  Team B Quota│
    │  16C / 64Gi │                       │  8C  / 32Gi │
    └─────────────┘                       └─────────────┘
           │                                     │
     ┌─────┴─────┐                         ┌─────┴─────┐
     ▼           ▼                         ▼           ▼
┌─────────┐ ┌─────────┐             ┌─────────┐ ┌─────────┐
│ dev     │ │ prod    │             │ dev     │ │ prod    │
│ 4C/16Gi │ │ 8C/32Gi │             │ 2C/8Gi  │ │ 4C/16Gi │
└─────────┘ └─────────┘             └─────────┘ └─────────┘
```

---

## 5. Policy Hierarchy & Scope

````{=html}
<!-- Diagram: diagrams/02-policy-hierarchy.html -->
<details open>
<summary><strong>📊 Architecture Diagram — Policy Hierarchy & Scope</strong> <a href="diagrams/02-policy-hierarchy.html" target="_blank"><img src="https://img.shields.io/badge/View-HTML%20Diagram-22d3ee?style=flat-square&logo=google-chrome" alt="Open HTML Diagram"/></a></summary>

**Open `diagrams/02-policy-hierarchy.html` in a browser to view the full interactive diagram.**

| Layer | Name | Owner | Enforcement | Scope |
|-------|------|-------|-------------|-------|
| Layer 1 | Platform / Cluster-Wide | Platform Team | ALWAYS DENY | All namespaces |
| Layer 2 | Tenant / Team-Level | Team Lead | deny (adjustable) | Tenant NS only |
| Layer 3 | Namespace / Workload | Team Member | dryrun or deny | Single NS |

**Conflict Rule:** Cluster > Tenant > Namespace (upper layers always win)

</details>
````

### 5.1 Policy Layer Architecture

```
Layer 1: Platform / Cluster-Wide (Read-Only for Tenants)
─────────────────────────────────────────────────────────
  Owner: Platform Team
  Scope: All namespaces (except kube-system)
  Enforcement: always deny
  Examples:
    • K8sAllowedRepos (whitelist only approved registries)
    • K8sBlockNodePort (no NodePort exposure)
    • K8sPSP* (security baseline)
    • K8sContainerLimits (resource ceiling)

Layer 2: Tenant / Team-Level (Team-Configurable)
─────────────────────────────────────────────────────────
  Owner: Team Lead (platform-assisted)
  Scope: Specific tenant namespaces
  Enforcement: deny (configurable per constraint)
  Examples:
    • K8sRequiredLabels (team-specific tags)
    • K8sReplicaLimits (team workload bounds)
    • K8sStorageClass (team-approved storage)
    • K8sHttpsOnly (HTTPS enforcement)

Layer 3: Namespace-Level / Workload-Specific (Per-Namespace Override)
─────────────────────────────────────────────────────────────────────────
  Owner: Team member
  Scope: Single namespace
  Enforcement: warn (dryrun) or deny
  Examples:
    • Temporary resource increase (exemption)
    • Custom naming convention
    • Debug mode overrides
```

### 5.2 Policy Conflict Resolution

| Conflict Type | Resolution Rule |
|--------------|----------------|
| Cluster vs Namespace | **Cluster wins** (always enforced, cannot be overridden by namespace) |
| Namespace A vs Namespace B | **No conflict** (policies are namespace-scoped, isolated) |
| Tenant vs Platform | **Platform wins** (tenants cannot weaken platform policies) |
| Multiple tenant policies | All apply; most restrictive wins |

### 5.3 Constraint Scope via `spec.match`

```yaml
# === Layer 1: Cluster-Wide Platform Policy ===
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: platform-container-limits        # Cluster-scoped, no namespace label
spec:
  enforcementAction: deny               # Cannot be overridden
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    # No namespace selector = all namespaces
    excludedNamespaces:                # System namespaces are always excluded
    - kube-system
    - kube-public
    - config-management
    - config-management-system
    - gitops-system
    - namespaces:
      - "*"                            # All namespaces
  parameters:
    ...
```

```yaml
# === Layer 2: Tenant-Scoped Policy ===
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: team-a-container-limits         # Tenant-scoped
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    namespaces:
    - "team-a-dev"
    - "team-a-staging"
    - "team-a-prod"
  parameters:
    ...
```

```yaml
# === Layer 3: Namespace-Level Exemption ===
# Applied ONLY to a single namespace, e.g., for a temporary increase
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: team-a-prod-exception           # Exemption for team-a-prod only
spec:
  enforcementAction: dryrun           # Warn only, don't block
  match:
    namespaces:
    - "team-a-prod"                    # Single namespace only
  parameters:
    ...
```

### 5.4 Per-Namespace Override with `ConstraintTemplate`

For advanced scenarios where the same template needs different parameters per namespace:

```yaml
# ConstraintTemplate with namespace-aware parameters
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8scontainerlimits-namespaced
spec:
  crd:
    spec:
      names:
        kind: K8sContainerLimitsNamespaced
      validation:
        openAPIV3Schema:
          properties:
            limits:
              type: array
              items:
                type: object
                properties:
                  maxCpu:
                    type: string
                  maxMemory:
                    type: string
                  namespace:
                    type: string
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package k8scontainerlimits
      
      violation[{"msg": msg}] {
        input.review.kind.kind == "Pod"
        container := input.review.object.spec.containers[_]
        ns := input.review.namespace
        limit := input.parameters.limits[_]
        limit.namespace == ns
        container.resources.limits.cpu > limit.maxCpu
        msg := sprintf("CPU limit exceeded in namespace %s", [ns])
      }
```

---

## 6. ConstraintTemplate Design

### 6.1 Template Categories

GKE Policy Controller ships **55+ built-in ConstraintTemplates** across 8 categories. Below is the full catalog sourced from the GKE Policy Controller gallery, plus custom templates for platform-specific needs.

#### 6.1.1 Built-in Templates (GKE Policy Controller)

| Category | Template | Purpose | Built-in? |
|----------|----------|---------|:---------:|
| **Certificate / Secret** | `certificate-deny-duplicate-secret-name-in-the-same-namespace` | Deny duplicate TLS cert Secret names in the same Namespace | ✅ |
| **Cluster Resource** | `cluster-resource-quota` | Enforce cluster-wide resource quota tracking | ✅ |
| **Container — Deny** | `container-deny-added-caps` | Deny containers that add Linux capabilities | ✅ |
| **Container — Deny** | `container-deny-env-var-secrets` | Deny env vars referencing Kubernetes Secrets | ✅ |
| **Container — Deny** | `container-deny-escalation` | Deny container privilege escalation | ✅ |
| **Container — Deny** | `container-deny-latest-tag` | Deny containers using `:latest` image tag | ✅ |
| **Container — Deny** | `container-deny-privileged` | Deny privileged containers | ✅ |
| **Container — Deny** | `container-deny-run-as-system-user` | Deny containers running as root/system user (UID < 10000) | ✅ |
| **Container — Deny** | `container-deny-without-resource-requests` | Deny containers without CPU/memory requests | ✅ |
| **Container — Deny** | `container-deny-without-runasnonroot` | Deny containers not explicitly running as non-root | ✅ |
| **Container — Deny** | `container-deny-writable-root-filesystem` | Deny containers with writable root filesystem | ✅ |
| **Container — Capabilities** | `container-drop-all-caps` | Require dropping all capabilities (CAP_ALL) | ✅ |
| **Container — Image** | `container-image-pull-policy-always` | Require `imagePullPolicy: Always` | ✅ |
| **Container — Whitelist** | `container-whitelist-image-prefix` | Whitelist approved image registry prefixes | ✅ |
| **Container — Whitelist** | `containers-whitelist-apparmor-profiles` | Whitelist allowed AppArmor profiles | ✅ |
| **Container — Whitelist** | `containers-whitelist-seccomp-profiles` | Whitelist allowed Seccomp profiles | ✅ |
| **CRD** | `crd-group-blocklist` | Block specific CRD API groups | ✅ |
| **Container Signing (CSCS)** | `cscs-deny-attestation-verification-failed` | Deny unsigned/unverified container images | ✅ |
| **Container Signing (CSCS)** | `cscs-deny-attestation-verification-failed-customer` | Customer-managed key variant of above | ✅ |
| **DNS** | `deny-duplicate-dns-names` | Deny duplicate Ingress hostnames | ✅ |
| **DNS** | `dns-endpoint-deny-dns-name-prefixes` | Deny DNS names with blocked prefixes | ✅ |
| **DNS** | `dns-endpoint-deny-invalid-records` | Deny malformed DNS records | ✅ |
| **DNS** | `dns-endpoint-whitelist-dns-name-suffixes` | Whitelist allowed DNS name suffixes | ✅ |
| **Flux** | `deny-flux-conflict` | Deny Flux CD conflicting resource definitions | ✅ |
| **Gateway / Envoy** | `envoy-gateway-deny-custom-gateway-class` | Deny custom GatewayClass resources | ✅ |
| **Gateway / Envoy** | `gateway-deny-priv-port` | Deny Gateway listeners on privileged ports (< 1024) | ✅ |
| **Gateway / Envoy** | `gateway-whitelist-ciphersuites` | Whitelist allowed TLS cipher suites | ✅ |
| **Gateway / Envoy** | `gateway-whitelist-min-protocol-version` | Require minimum TLS protocol version | ✅ |
| **Gateway / Envoy** | `gateway-whitelist-protocols` | Whitelist allowed Gateway protocols | ✅ |
| **Ingress** | `ingress-deny-host-prefixes` | Deny Ingress with blocked host prefixes | ✅ |
| **Namespace** | `namespace-deny-system-interaction` | Deny resources in `kube-system` / `kube-public` | ✅ |
| **Namespace** | `deny-system-resources-interaction` | Deny interaction with system namespaces | ✅ |
| **PersistentVolume** | `persistent-volume-deny-duplicate-csi-volume-handle` | Deny duplicate CSI VolumeHandle claims | ✅ |
| **PersistentVolume** | `persistent-volume-deny-system-claimed` | Deny PVs claimed by system components | ✅ |
| **PersistentVolume** | `persistent-volume-whitelist-csi-driver` | Whitelist allowed CSI drivers | ✅ |
| **Pod — Deny** | `pod-deny-blocking-scale-down` | Deny Pods that block cluster scale-down | ✅ |
| **Pod — Deny** | `pod-deny-host-ipc` | Deny Pods using host IPC namespace | ✅ |
| **Pod — Deny** | `pod-deny-host-network` | Deny Pods using host network | ✅ |
| **Pod — Deny** | `pod-deny-host-pid` | Deny Pods using host PID namespace | ✅ |
| **Pod — Deny** | `pod-deny-priority-class` | Deny Pods without a valid PriorityClass | ✅ |
| **Pod — Deny** | `pod-deny-root-fsgroup` | Deny Pods with root fsGroup (UID 0) | ✅ |
| **Pod — Whitelist** | `pod-whitelist-volumes` | Whitelist allowed Volume types | ✅ |
| **PriorityClass** | `priority-class-deny-system-interaction` | Deny PriorityClass references to system classes | ✅ |
| **Prometheus** | `prometheus-rule-whitelist-metadata` | Require metadata labels on PrometheusRule CRDs | ✅ |
| **RBAC** | `rbac-deny-modify-labeled-cluster-role-and-binding` | Deny modifications to protected ClusterRole/Binding | ✅ |
| **RBAC** | `role-binding-whitelist-subjects` | Whitelist allowed RBAC subject principals | ✅ |
| **StorageClass** | `storage-class-deny-default-annotations` | Deny StorageClass with default annotation overrides | ✅ |
| **StorageClass** | `storage-class-warn-missing-cmek-encryption` | Warn on StorageClass missing CMEK encryption | ✅ |
| **StorageClass** | `storage-class-whitelist-provisioners` | Whitelist allowed storage provisioners | ✅ |
| **Validation** | `unexpected-admission-webhook-audit` | Audit unexpected admission webhooks | ✅ |
| **VolumeSnapshot** | `volume-snapshot-class-whitelist-csi-driver` | Whitelist allowed VolumeSnapshotClass CSI drivers | ✅ |

#### 6.1.2 Custom Platform Templates

| Category | Template | Purpose | Built-in? |
|----------|----------|---------|:---------:|
| **Custom** | `K8sImmutableFields` | Lock specific resource fields from modification | ❌ |
| **Custom** | `K8sOwnerReference` | Enforce owner chain on resources | ❌ |
| **Custom** | `K8sPriorityClass` | Require all Pods to specify a PriorityClass | ❌ |
| **Custom** | `K8sRequiredLabels` | Require mandatory labels (app, team, environment) | ❌ |

#### 6.1.3 Category Summary

| Category | Count | Key Templates |
|----------|:-----:|--------------|
| Container Security (Deny) | 10 | privileged, escalation, writable-rootfs, latest-tag |
| Container Security (Whitelist) | 4 | image-prefix, apparmor, seccomp |
| Pod Security (Deny) | 6 | host-ipc, host-network, host-pid, priority-class |
| Gateway / Envoy | 5 | priv-port, ciphersuites, min-tls-version |
| DNS | 4 | duplicate-names, prefix-block, suffix-allow |
| StorageClass | 3 | provisioners, cmek-warning, default-annotations |
| RBAC | 2 | clusterrole-modify, subject-whitelist |
| PersistentVolume | 3 | csi-driver-whitelist, duplicate-handle |
| Container Signing (CSCS) | 2 | attestation-verification |
| Other | 7 | cluster-quota, crd-blocklist, flux, prometheus, webhook-audit |
| **Total Built-in** | **51** | GKE Policy Controller gallery |
| **Custom** | **4** | Platform-specific extensions |
| **Total** | **55** | |

### 6.2 Template Versioning Strategy

```
Template: k8srequiredlabels
  ├── v1.0.0  ── deprecated ── 2024-01 (initial)
  ├── v1.1.0  ── stable      ── 2024-06 (added allowedRegex)
  └── v1.2.0  ── stable      ── 2025-01 (current)

Constraint: require-team-labels
  └── spec.template: k8srequiredlabels_v1.2.0   ← pinned version
```

**Version Migration Policy:**

| Stage | Duration | Action |
|-------|----------|--------|
| New version released | 0-30 days | Both old and new run in parallel (dryrun) |
| Stable | 30-90 days | New is enforced, old is deprecated |
| Migration | 90-180 days | Old runs dryrun, new is enforced |
| Sunset | 180+ days | Old is removed |

### 6.3 Custom Template Skeleton

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: <template-name>
  annotations:
    description: |
      <one-paragraph description>
    metadata.gatekeeper.sh/title: "<Display Name>"
    metadata.gatekeeper.sh/version: "1.0.0"
    categories:
    - <category>                    # e.g., "Security", "Reliability"
    severity: <low|medium|high>     # Impact assessment
spec:
  crd:
    spec:
      names:
        kind: <KindName>           # Generated CRD kind
      validation:
        openAPIV3Schema:
          properties:
            <param-name>:
              type: <type>
              description: <description>
          required: [<required-params>]
  targets:
  - target: admission.k8s.gatekeeper.sh
    libs:
    - path: <lib-path>             # Optional shared library
      name: <lib-name>
    rego: |
      package <package-name>
      
      <Rego logic>
      
      # Key built-in vars:
      # input.review          — the admission request
      # input.parameters      — constraint parameters
      # input.constraint      — the constraint object
```

---

## 7. Constraint Lifecycle

### 7.1 Lifecycle States

```
┌──────────────┐     apply      ┌──────────────┐     dryrun      ┌──────────────┐
│  Not Created │ ────────────> │  Proposed    │ ─────────────> │   Dryrun     │
└──────────────┘               └──────────────┘                └──────────────┘
                                    │                                   │
                                    │          deny (30d+)             │
                                    │ <─────────────────────────────────┘
                                    ▼
                              ┌──────────────┐
                              │     Deny      │
                              └──────────────┘
                                    │
                                    │   deprecated (90d+)
                                    ▼
                              ┌──────────────┐
                              │ Deprecated   │ ──remove──> End
                              └──────────────┘
```

### 7.2 Lifecycle State Definitions

| State | Enforcement | Visibility | Use Case |
|-------|:-----------:|:----------:|---------|
| **Proposed** | ❌ None | Platform only | New policy draft, under review |
| **Dryrun** | ⚠️ Log only | Tenant + Platform | 30-day soak test before enforcement |
| **Deny** | ✅ Blocked | All | Production enforcement |
| **Deprecated** | ⚠️ Warning | All | Graceful removal, 90-day notice |
| **Removed** | N/A | N/A | Deleted from cluster |

### 7.3 State Transition Workflow

```yaml
# Step 1: Propose (platform team only)
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: platform-container-limits
  labels:
    policy.platform.io/state: proposed
    policy.platform.io/since: "2026-05-06"
spec:
  enforcementAction: dryrun
  ...

# After 30 days → Transition to deny
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: platform-container-limits
  labels:
    policy.platform.io/state: deny
    policy.platform.io/since: "2026-06-05"
spec:
  enforcementAction: deny
  ...
```

---

## 8. Template Maintenance & Versioning

### 8.1 Template Registry Structure

```
opa-templates/
├── templates/                          # All ConstraintTemplates
│   ├── v1.0.0/                         # Versioned directory
│   │   ├── K8sAllowedRepos/
│   │   │   ├── template.yaml
│   │   │   └── constraint.yaml.example
│   │   ├── K8sRequiredLabels/
│   │   │   ├── template.yaml
│   │   │   └── constraint.yaml.example
│   │   └── K8sContainerLimits/
│   │       ├── template.yaml
│   │       └── constraint.yaml.example
│   ├── v1.1.0/
│   │   └── ...
│   └── v1.2.0/
│       └── ...
│
├── constraints/                        # Cluster/tenant constraints
│   ├── platform/                       # Cluster-level
│   │   ├── cluster-wide/
│   │   │   ├── K8sAllowedRepos.yaml
│   │   │   ├── K8sContainerLimits.yaml
│   │   │   └── K8sHttpsOnly.yaml
│   │   └── cluster-wide.yaml           # Kustomization overlay
│   │
│   ├── tenants/                        # Tenant-level
│   │   ├── team-a/
│   │   │   ├── K8sRequiredLabels.yaml
│   │   │   └── K8sReplicaLimits.yaml
│   │   └── team-b/
│   │       └── ...
│   │
│   └── exceptions/                     # Time-limited exemptions
│       ├── team-a-prod-gpu-exception.yaml
│       └── review-2026-Q3.yaml        # Quarterly review tracking
│
├── libs/                               # Shared Rego libraries
│   ├── utils.rego                      # Common helpers
│   ├── validation.rego
│   └── networking.rego
│
├── tests/                              # OPA test cases
│   ├── K8sAllowedRepos_test.yaml
│   ├── K8sRequiredLabels_test.yaml
│   └── K8sContainerLimits_test.yaml
│
└── scripts/                            # CI/CD scripts
    ├── validate-templates.sh
    ├── test-constraints.sh
    └── migrate-version.sh
```

### 8.2 Template Version Selection Per Tenant Type

| Tenant Type | Template Version | Rationale |
|-------------|:---------------:|----------|
| **Standard** | `v1.2.0 (stable)` | Full platform baseline |
| **Privileged** | `v1.2.0 (stable)` + custom extensions | Extended limits via exceptions |
| **Infrastructure** | `v1.2.0 (stable)` | Platform-grade controls |
| **Sandbox** | `v1.1.0 (legacy)` | Relaxed, mostly dryrun |

### 8.3 Template Update Process

```
1. Template v1.2.0 is released
2. CI pipeline: Run all tests against v1.2.0
3. Platform team: Review changelog, assess impact
4. Staged rollout:
   a. dev clusters: v1.2.0 dryrun (Week 1-2)
   b. staging clusters: v1.2.0 deny (Week 3-4)
   c. prod clusters: v1.2.0 dryrun → deny (Week 5-8)
5. Deprecate v1.1.0: set state=deprecated (90-day sunset)
6. Remove v1.1.0 from production
```

---

## 9. Team Onboarding Workflow

````{=html}
<!-- Diagram: diagrams/03-onboarding-workflow.html -->
<details open>
<summary><strong>📊 Architecture Diagram — Team Onboarding Workflow</strong> <a href="diagrams/03-onboarding-workflow.html" target="_blank"><img src="https://img.shields.io/badge/View-HTML%20Diagram-22d3ee?style=flat-square&logo=google-chrome" alt="Open HTML Diagram"/></a></summary>

**Open `diagrams/03-onboarding-workflow.html` in a browser to view the full interactive diagram.**

| Step | Phase | Description |
|------|-------|-------------|
| 1 | New Team Request | Submit NamespaceClaim CRD |
| 2 | Platform Review | Identity verification, naming |
| 3 | Namespace Creation | team-{name}-{env} with labels |
| 4 | Baseline Policies | GitOps auto-applies platform baseline |
| 5 | Template Assignment | v1.2.0 locked, 30-day dryrun |
| 6 | Active Tenant | Deny enforcement active |

**GitOps Automation:** All 6 steps are automated via ArgoCD / Config Sync upon NamespaceClaim submission.

</details>
````

### 9.1 Onboarding Flow

```
New Team Request
      │
      ▼
┌─────────────────────────┐
│ 1. Platform Review      │
│  • Identity verification│
│  • Namespace naming     │
│  • Resource estimate    │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 2. Namespace Creation   │
│  • team-{name}-{env}   │
│  • Labels applied      │
│  • RBAC configured     │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 3. Baseline Policies    │ ◄── Auto-provisioned via GitOps
│  • platform-baseline    │
│  • tenant-standard      │
│  • environment-specific │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 4. Template Assignment  │
│  • Select template set  │
│  • Lock versions        │
│  • Dryrun period (30d)  │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 5. Team Notification    │
│  • Access credentials   │
│  • Policy documentation │
│  • Slack/email alerts   │
└──────────┬──────────────┘
           │
           ▼
      Active Tenant
```

### 9.2 Onboarding YAML: Namespace + Baseline Policies

```yaml
# namespace-claim.yaml — submitted by new team
apiVersion: tenant.platform.io/v1alpha1
kind: NamespaceClaim
metadata:
  name: team-onboarding-request
spec:
  team:
    name: "team-d"
    lead: "team-d-lead@company.com"
    members:
    - "team-d-dev1@company.com"
    - "team-d-dev2@company.com"
  namespaces:
  - name: "team-d-dev"
    environment: "dev"
    resourceEstimate:
      cpu: "4"
      memory: "16Gi"
      storage: "50Gi"
  - name: "team-d-prod"
    environment: "prod"
    resourceEstimate:
      cpu: "8"
      memory: "32Gi"
      storage: "200Gi"
  tenantType: "standard"           # standard | privileged | infra | sandbox
  templateSet: "v1.2.0"            # Which template version to use
```

```yaml
# Generated: team-d-prod namespace with auto-applied policies
apiVersion: v1
kind: Namespace
metadata:
  name: team-d-prod
  labels:
    tenant.platform.io/name: "team-d"
    tenant.platform.io/type: "standard"
    tenant.platform.io/template-set: "v1.2.0"
    environment: "prod"
    owner: "team-d-lead@company.com"
    policy.platform.io/parent: "platform-baseline"
---
# Auto-applied: platform baseline constraints (dryrun → deny after 30d)
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: platform-team-d-prod-allowed-repos
  labels:
    tenant.platform.io/team: "team-d"
    policy.platform.io/type: "platform-baseline"
spec:
  enforcementAction: dryrun
  match:
    namespaces:
    - "team-d-prod"
  parameters:
    repos:
    - docker.io
    - gcr.io
---
# Auto-applied: tenant-specific limits
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: team-d-prod-container-limits
  labels:
    tenant.platform.io/team: "team-d"
    policy.platform.io/type: "tenant-specific"
spec:
  enforcementAction: deny
  match:
    namespaces:
    - "team-d-prod"
  parameters:
    cpu: "8"
    memory: "32Gi"
    # No exemptions for standard tenant by default
```

### 9.3 Tenant Template Set Assignment

```yaml
# Template sets define which constraints are applied per tenant type
apiVersion: tenant.platform.io/v1alpha1
kind: TemplateSet
metadata:
  name: standard-tenant-v1
spec:
  tenantType: standard
  templateVersion: v1.2.0
  constraints:
    # Always enforced (platform cannot be overridden)
    - name: platform-block-nodeport
      template: K8sBlockNodePort
      enforcementAction: deny
    - name: platform-block-loadbalancer
      template: K8sBlockLoadBalancer
      enforcementAction: deny
    - name: platform-allowed-repos
      template: K8sAllowedRepos
      enforcementAction: deny
      parameters:
        repos:
        - docker.io
        - gcr.io
        - ghcr.io
    # Tenant-configurable (team can adjust within bounds)
    - name: tenant-resource-limits
      template: K8sContainerLimits
      enforcementAction: deny
      adjustable: true                    # Team can lower limits
      adjustableMax:                        # Upper bounds (cannot exceed)
        cpu: "16"
        memory: "64Gi"
    - name: tenant-required-labels
      template: K8sRequiredLabels
      enforcementAction: deny
      adjustable: true
      parameters:
        labels:
        - key: "app.kubernetes.io/name"
        - key: "team"
          value: "{{ tenant.name }}"      # Auto-populated
    # Dryrun by default (monitoring only)
    - name: tenant-replica-limits
      template: K8sReplicaLimits
      enforcementAction: dryrun
      parameters:
        minReplicas: 1
        maxReplicas: 10
```

---

## 10. Exception Handling

### 10.1 Exception Types

| Type | Duration | Approval | Auto-Expiration |
|------|----------|----------|----------------|
| **Temporary** | 1-90 days | Team Lead + Platform | ✅ |
| **Permanent** | Indefinite | Platform + Security | ❌ (manual removal) |
| **Emergency** | 24-72 hours | Platform On-call | ✅ (auto-revoke) |
| **Grandfather** | Until policy change | Policy Committee | ❌ |

### 10.2 Exception Workflow

```
Exception Request
      │
      ▼
┌─────────────────────────┐
│ Validate Exception       │
│ • Is it repeatable?     │──No──► Permanent Exception Path
│ • Is it time-limited?   │
└──────────┬──────────────┘
           │ Yes
           ▼
┌─────────────────────────┐
│ 7-Day Emergency Window  │
│ • Auto-approved         │
│ • Team Lead notified    │
│ • Auto-expire in 7d     │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ Full Review (if > 7d)  │
│ • Team Lead approval    │
│ • Platform review       │
│ • Justification required │
└──────────┬──────────────┘
           │
           ▼
      Approved / Denied
```

### 10.3 Exception Constraint Implementation

```yaml
# Temporary exception: 30-day resource limit increase for team-a-prod
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: team-a-prod-gpu-exception
  labels:
    exception.platform.io/type: "temporary"
    exception.platform.io/approved-by: "platform-lead@company.com"
    exception.platform.io/expires: "2026-06-06"      # Auto-expiration date
    exception.platform.io/justification: "GPU training job for Q2 milestone"
spec:
  enforcementAction: dryrun            # Still warn, don't fully block
  match:
    namespaces:
    - "team-a-prod"
  parameters:
    cpu: "32"
    memory: "128Gi"
---
# Emergency exception: 24-hour bypass for incident response
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: incident-1234-emergency-exception
  labels:
    exception.platform.io/type: "emergency"
    exception.platform.io/incident-id: "INC-2024-1234"
    exception.platform.io/expires: "2026-05-07T12:00:00Z"
spec:
  enforcementAction: dryrun
  match:
    namespaces:
    - "team-a-prod"
  parameters:
    cpu: "64"
    memory: "256Gi"
```

### 10.4 Exception Cleanup Automation

```bash
#!/bin/bash
# cleanup-expired-exceptions.sh — run daily via cron

TODAY=$(date +%Y-%m-%d)

# Find all exceptions with past expiration dates
kubectl get constraints -A -l exception.platform.io/expires \
  --field-selector=status in Expired \
  -o json | jq -r '.items[] | .metadata.name + " " + .metadata.namespace' | \
while read -r name ns; do
  echo "Removing expired exception: $name in $ns"
  kubectl delete constraint "$name" -n "$ns"
done
```

---

## 11. GitOps Integration

````{=html}
<!-- Diagram: diagrams/04-gitops-pipeline.html -->
<details open>
<summary><strong>📊 Architecture Diagram — GitOps CI/CD Pipeline</strong> <a href="diagrams/04-gitops-pipeline.html" target="_blank"><img src="https://img.shields.io/badge/View-HTML%20Diagram-22d3ee?style=flat-square&logo=google-chrome" alt="Open HTML Diagram"/></a></summary>

**Open `diagrams/04-gitops-pipeline.html` in a browser to view the full interactive diagram.**

| Phase | Stage | Tool | Description |
|-------|-------|------|-------------|
| Authoring | PR Created | GitHub | CI auto-triggered |
| CI | Rego Lint | opa / conftest | Syntax & best practice check |
| CI | Unit Tests | opa test | Test case execution |
| CI | Dry-run Apply | kubectl | Server-side validation |
| CI | Policy Diff | kubectl gk | Change impact analysis |
| CI | Review Gate | GitHub | Required: platform-team |
| Review | Approval | GitHub PR | 2+ reviewers required |
| Sync | ArgoCD Apply | kubectl SSA | Server-side apply |
| Sync | Gatekeeper | Gatekeeper | Constraints enforced |
| Sync | Notify | Slack | #team-alerts posted |

**All policy changes go through this full pipeline — no direct cluster access required.**

</details>
````

### 11.1 Repository Structure

```
gitops-platform/
├── README.md
├── Makefile
├── .github/
│   └── workflows/
│       ├── gatekeeper-policy-check.yaml
│       └── template-release.yaml
│
├── config/
│   ├── clusters/                     # Per-cluster overrides
│   │   ├── prod-1.yaml
│   │   ├── prod-2.yaml
│   │   ├── staging-1.yaml
│   │   └── dev-1.yaml
│   │
│   ├── templates/                    # ConstraintTemplates
│   │   ├── platform/
│   │   │   ├── K8sAllowedRepos/
│   │   │   └── K8sBlockNodePort/
│   │   └── custom/
│   │       ├── K8sImmutableFields/
│   │       └── K8sPriorityClass/
│   │
│   └── constraints/                  # Constraint instances
│       ├── platform/                 # Cluster-wide
│       ├── team-a/                   # Tenant namespaces
│       ├── team-b/
│       └── exceptions/
│
├── libs/
│   └── common.rego                   # Shared Rego functions
│
└── tests/
    ├── integration/
    │   └── multi-cluster-test.yaml
    └── unit/
        ├── K8sAllowedRepos_test.rego
        └── K8sContainerLimits_test.rego
```

### 11.2 ArgoCD Application for Policy Management

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gatekeeper-policies-prod
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/aibangjuxin/gitops-platform.git
    targetRevision: HEAD
    path: config/constraints/platform
  destination:
    server: https://kubernetes.default.svc
    namespace: gatekeeper-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```

### 11.3 CI/CD Pipeline for Policy Changes

```yaml
# .github/workflows/gatekeeper-policy-check.yaml
name: Gatekeeper Policy CI

on:
  pull_request:
    paths:
    - 'config/templates/**'
    - 'config/constraints/**'
    - 'libs/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    # 1. Lint Rego templates
    - name: Lint Rego
      run: |
        opa eval --format pretty \
          -d libs/common.rego \
          config/templates/**/template.yaml

    # 2. Unit test constraints
    - name: Run constraint tests
      run: |
        opa test ./tests/unit/ --verbose

    # 3. Dry-run against test cluster
    - name: Dry-run apply
      run: |
        kubectl apply --dry-run=server \
          -f config/templates/
        kubectl apply --dry-run=server \
          -f config/constraints/

    # 4. Generate policy diff
    - name: Policy diff
      run: |
        kubectl gk show diff \
          --cluster=prod-1 \
          --output=table > policy-diff.txt
      uses: actions/upload-artifact@v4
      with:
        name: policy-diff
        path: policy-diff.txt

  require-review:
    runs-on: ubuntu-latest
    needs: validate
    if: github.event_name == 'pull_request'
    steps:
    - name: Check required reviewers
      run: |
        REQUIRED_TEAM="platform-team"
        echo "Policy changes require review from: $REQUIRED_TEAM"
```

### 11.4 Change Approval Workflow

```
PR Author
    │
    ▼
GitHub PR Created
    │
    ▼
CI Pipeline (auto)
  ├── Rego lint         ✅
  ├── Unit tests        ✅
  ├── Policy diff       ✅
  └── Dry-run apply     ✅
    │
    ▼
Required Reviewers
  ├── Platform Team      ✅ (required for all changes)
  ├── Tenant Team Lead   ✅ (required for tenant namespace changes)
  └── Security Team      ⚠️ (required for security policies)
    │
    ▼
PR Approved + Merged
    │
    ▼
ArgoCD Sync (auto)
  ├── kubectl apply (server-side)
  ├── Gatekeeper syncs
  └── Slack notification to team
```

---

## 12. Migration Strategy

### 12.1 Migration Phases

```
Phase 1: Inventory (Week 1-2)
─────────────────────────────────────────────────
• Audit all existing workloads
• Identify non-compliant resources
• Classify by namespace and tenant
• Estimate migration effort

Phase 2: Baseline Enforcement (Week 3-6)
─────────────────────────────────────────────────
• Deploy templates WITHOUT constraints (audit mode)
• All violations logged, not blocked
• Notify teams of upcoming changes
• Track via policy dashboard

Phase 3: Gradual Enforcement (Week 7-12)
─────────────────────────────────────────────────
• Tier 1 (P0): Security policies → Deny first
  • K8sAllowedRepos, K8sPSP*, K8sBlockNodePort
• Tier 2 (P1): Reliability policies → Dryrun → Deny
  • K8sContainerLimits, K8sReplicaLimits
• Tier 3 (P2): Operational policies → Dryrun only
  • K8sRequiredLabels, K8sHttpsOnly

Phase 4: Full Enforcement (Week 13+)
─────────────────────────────────────────────────
• All P0 and P1 in deny mode
• P2 in dryrun with quarterly review
• Exception process formalized
```

### 12.2 Pre-Migration Checklist

```yaml
# pre-migration-audit.yaml
apiVersion: audit.gatekeeper.sh/v1
kind: AuditInfo
metadata:
  name: prod-cluster-audit
spec:
  cluster: prod-1
  auditDate: "2026-05-01"
  findings:
    - constraint: K8sAllowedRepos
      violations: 23
      nonCompliantImages:
      - nginx:1.18
      - redis:6.0
      affectedNamespaces:
      - team-a-prod
      - team-b-dev
    - constraint: K8sContainerLimits
      violations: 8
      affectedNamespaces:
      - team-c-prod
  actionItems:
  - team: team-a
    deadline: "2026-05-15"
    task: "Update nginx to approved version"
  - team: team-c
    deadline: "2026-05-20"
    task: "Set container limits on all pods"
```

---

## 13. Monitoring & Audit

### 13.1 Metrics & Alerting

| Metric | Source | Alert Threshold | Action |
|--------|--------|-----------------|--------|
| `gatekeeper_violations_total` | Prometheus | > 100 violations/hour | Notify tenant team |
| `gatekeeper_constraint_errors` | Prometheus | > 0 for 5min | Page platform team |
| `gatekeeper_sync_duration_seconds` | Prometheus | > 60s | Investigate sync delay |
| `gatekeeper_constraint_eval_duration_seconds` | Prometheus | > 500ms | Optimize Rego |
| `exception_expiring_soon` | Custom cron | < 7 days to expiry | Notify team lead |

### 13.2 Audit Logging

```yaml
# Gatekeeper audit configuration
apiVersion: audit.gatekeeper.sh/v1beta1
kind: AuditConfig
metadata:
  name: platform-audit-config
spec:
  auditInterval: 1h                    # Run audit every hour
  constraints:
    emitTemplateAuditEvents: true
    emitConstraintAuditEvents: true
    auditFromCache: true               # Faster audit from cache
  constraintViolationsLimit: 500       # Per constraint
  auditChunkSize: 500                 # Batch size for large clusters

# Log aggregation: Fluent Bit → Elasticsearch / Cloud Logging
# Retention: 90 days for violations, 1 year for security events
```

### 13.3 Compliance Dashboard

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Gatekeeper Compliance Dashboard                           │
├────────────────┬────────────────┬────────────────┬────────────────────────┤
│ Cluster        │ Compliance %   │ Active         │ Pending Exceptions     │
│                │                │ Violations     │                        │
├────────────────┼────────────────┼────────────────┼────────────────────────┤
│ prod-1         │ 94.2% ▲       │ 12             │ 3 (expiring soon)     │
│ prod-2         │ 96.8% ▲       │ 8              │ 1                      │
│ staging-1      │ 91.1% ▲       │ 23             │ 2                      │
│ dev-1          │ 88.5% ▲       │ 45             │ 5                      │
└────────────────┴────────────────┴────────────────┴────────────────────────┘

Top Violations (Last 7 Days):
  1. K8sContainerLimits          47 violations   (20 namespaces)
  2. K8sRequiredLabels           31 violations   (12 namespaces)
  3. K8sAllowedRepos             12 violations   (4 namespaces)
  4. K8sReplicaLimits             8 violations   (3 namespaces)
```

---

## 14. Decision Matrix

### 14.1 Template Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Template scope | Namespace-scoped constraints | Tenant isolation, no cross-bleed |
| Template version pinning | Explicit version in constraint | Predictable upgrades, no auto-breaking changes |
| Custom templates | Allowed (per tenant) with review | Extensibility without compromising platform |
| Rego complexity | Template-level validation gate | No deeply nested Rego without review |
| Built-in templates | GKE Policy Controller library | 70+ battle-tested, maintained by Google |

### 14.2 Multi-Cluster Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Policy control plane | Config Sync (Fleet) | Single source of truth across clusters |
| Cluster overrides | git branch per cluster | Isolated cluster-specific tweaks |
| Sync frequency | Real-time (server-side apply) | Avoid stale constraint windows |
| Template distribution | Mirrored from hub | No runtime network dependency |

### 14.3 Tenant Model Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Namespace per team per env | Yes | Isolation, quota, policy clarity |
| Tenant label convention | Required (all NS) | Enables policy targeting, audit |
| Tenant self-service | Read-only policy view | Transparency without risk |
| Custom policies per tenant | Allowed (with approval) | Team autonomy within bounds |
| Exception granting | Platform only | Governance consistency |

---

## Appendix A: Full Namespace Manifest Example

```yaml
# team-a-prod/manifest.yaml — provisioned by GitOps on onboarding
---
apiVersion: v1
kind: Namespace
metadata:
  name: team-a-prod
  labels:
    tenant.platform.io/name: "team-a"
    tenant.platform.io/type: "standard"
    tenant.platform.io/template-set: "v1.2.0"
    tenant.platform.io/owner: "team-a-lead@company.com"
    environment: "prod"
    kubernetes.io/metadata.name: "team-a-prod"
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-prod-quota
  namespace: team-a-prod
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 32Gi
    persistentvolumeclaims: "10"
    pods: "50"
---
apiVersion: limits.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: team-a-prod-container-limits
  labels:
    tenant.platform.io/team: "team-a"
    policy.platform.io/type: "tenant-specific"
    policy.platform.io/state: "deny"
spec:
  enforcementAction: deny
  match:
    namespaces:
    - "team-a-prod"
  parameters:
    cpu: "8"
    memory: "32Gi"
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: team-a-prod-required-labels
spec:
  enforcementAction: deny
  match:
    namespaces:
    - "team-a-prod"
  parameters:
    labels:
    - key: "app.kubernetes.io/name"
    - key: "team"
      allowedRegex: "^team-a$"
    - key: "environment"
      allowedRegex: "^prod$"
    - key: "managed-by"
      allowedRegex: "^platform$"
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: platform-team-a-prod-allowed-repos
  labels:
    policy.platform.io/type: "platform-baseline"
spec:
  enforcementAction: deny
  match:
    namespaces:
    - "team-a-prod"
  parameters:
    repos:
    - docker.io
    - gcr.io
    - ghcr.io
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sHttpsOnly
metadata:
  name: platform-team-a-prod-https-only
spec:
  enforcementAction: deny
  match:
    namespaces:
    - "team-a-prod"
```

---

## Appendix B: Quick Reference

### Label Cheat Sheet

| Label | Value | Applied To |
|-------|-------|-----------|
| `tenant.platform.io/name` | `team-a` | Namespace |
| `tenant.platform.io/type` | `standard\|privileged\|infra\|sandbox` | Namespace |
| `tenant.platform.io/template-set` | `v1.2.0` | Namespace |
| `policy.platform.io/type` | `platform-baseline\|tenant-specific` | Constraint |
| `policy.platform.io/state` | `proposed\|dryrun\|deny\|deprecated` | Constraint |
| `exception.platform.io/type` | `temporary\|permanent\|emergency` | Exception Constraint |
| `exception.platform.io/expires` | `2026-06-06` | Exception Constraint |

### Enforcement Action Reference

| Action | Behavior | Use Case |
|--------|----------|---------|
| `deny` | Blocks resource creation | P0 security, hard limits |
| `dryrun` | Allows but logs violation | Policy rollout, P2 monitoring |
| `warn` | Returns warning message | Advisory policies |

---

## References

- [OPA Gatekeeper Documentation](https://open-policy-agent.github.io/gatekeeper/)
- [GKE Policy Controller](https://cloud.google.com/kubernetes-engine/docs/concepts/policy-controller)
- [ConstraintTemplate Spec](https://open-policy-agent.github.io/gatekeeper/docs/how-to/)
- [Rego Language Reference](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [Multi-tenant Reference Architecture](https://github.com/open-policy-agent/multi-tenancy)
