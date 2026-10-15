---
last_verified: 2026-10-15
scope: GCP, GKE, Kubernetes prompt refinement
---

# GCP and GKE reference rules

Use this reference when refining prompts about Google Cloud, GKE, Kubernetes platform reviews, or cluster comparisons.

## Safety and identity

- Treat project ID, cluster name, location, fleet membership, service account, VPC, subnet, and billing account as untrusted unless directly supplied. Use `{{PLACEHOLDER}}` values.
- Default investigation work to read-only. State that no resources, IAM bindings, firewall rules, node pools, workloads, or configuration are to be modified.
- Keep credentials and access tokens out of output. Redact secret values, private endpoints, and personally identifying data where the report will be shared.
- When access is insufficient, report the failed read, the missing permission, and a least-privilege command or role recommendation; do not work around access controls.

## Reliable investigation structure

For a standard cluster comparison, organize evidence and findings across:

1. Cluster configuration: mode, version, release channel, location, endpoint exposure, authorized networks, IP allocation, add-ons, DNS, logging/monitoring, maintenance, identity, encryption, and fleet.
2. Node pools: machine and image type, disk, autoscaling, upgrade/repair settings, labels/taints/tags, service account/scopes, Spot, accelerators, max pods, kubelet settings, and version.
3. Networking: VPC, subnet and secondary ranges, routes, firewall policy/rules, Cloud NAT, DNS, Private Google Access, Shared VPC, network policy, dataplane, and load-balancing options.
4. Workloads and capacity: node allocatable capacity, requests/limits, namespace inventory, workload replicas, HPA/VPA/PDB, storage classes and claims. Include live usage only if permitted and available.
5. Security: IAM, Kubernetes RBAC, Workload Identity, Pod Security Admission, NetworkPolicy, Binary Authorization, audit logs, image scanning, KMS, VPC Service Controls, and secret access posture.
6. Operations and cost: logging/metrics/alerts/SLOs, backup and restore, upgrade policy, quotas, labels, resource shape, Spot/CUD suitability, and cost allocation coverage.
7. Delivery and drift: Terraform, Config Connector, Crossplane, Helm, Argo CD, Flux, module/chart versions, variables, lifecycle controls, and declared-versus-actual differences when source is available.

## Evidence collection boundaries

- Prefer documented GCP and Kubernetes read operations, such as `gcloud ... list`, `gcloud ... describe`, `kubectl get`, and narrowly scoped `kubectl describe`.
- Do not put credential-changing commands in a read-only prompt. `gcloud container clusters get-credentials` may be included only to access an authorized cluster context and must not mutate cluster resources.
- Identify commands that require cluster credentials separately from control-plane reads.
- Do not require privileged Kubernetes actions simply to produce a report. If the user lacks access, record the gap.

## Report requirements

Use Markdown tables with clear evidence and uncertainty. For each difference include: dimension, old environment, new environment, same/different/unknown, impact, risk, recommendation, and evidence source.

Separate confirmed findings from unavailable data. Rank the top differences by production risk, security exposure, reliability impact, and cost impact. Finish with missing information and exact read-only collection commands where appropriate.

## Freshness note

GKE product fields and command flags evolve. Verify product-specific options against current official Google Cloud documentation before executing a generated deep-audit prompt.
