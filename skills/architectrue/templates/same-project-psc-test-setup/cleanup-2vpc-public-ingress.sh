# cleanup-2vpc-public-ingress.sh — Reverse-order teardown of the 2-VPC PSC NEG chain

Run this to delete every resource created by `setup-2vpc-public-ingress.sh` in the correct dependency order.

## What it deletes (reverse order)

**Consumer side** (reverse order, leaves DNS / cert chain intact by default):
- Backend service → Target HTTPS proxy → URL map → PSC NEG → Cloud Armor (global name) → optional: consumer proxy-only subnet

**Producer side** (reverse order):
- Service Attachment → Forwarding rule → Target HTTP proxy → URL map → Backend service → Health check → Internal IP → MIG → Instance template
- Subnets (3 in any order — no dependencies between them)
- Cloud NAT (NAT before router) → Router
- 3 firewalls (independent)

**Producer VPC itself**:
- Network (with --quiet)

**Kept by default** (uncomment lines to delete):
- `ajbx-public-glb-ip` (External IP) — kept because you might have DNS A records pointing to it
- `ajbx-public-cert` (SSL cert) — kept because you might want to reuse it
- `aibang-12345678-ajbx-dev-cinternal-vpc1` (consumer VPC) — kept because it has GKE, bastion, etc.
- `aibang-12345678-ajbx-dev` (project) — never deleted

## Usage

```bash
chmod +x cleanup-2vpc-public-ingress.sh
./cleanup-2vpc-public-ingress.sh
```

## Safety

The script uses `gcloud ... delete --quiet` so it will not prompt for confirmation, but it WILL fail with an error if a resource is in use (e.g., forwarding rule still has traffic). If that happens, fix the upstream dependency first and re-run.

## Idempotency

Already-deleted resources cause `delete` to fail with "not found", which the script ignores (via `|| true` after each delete). Re-running is safe.

## When to run

- After testing is complete and you want to clean up billing
- Before destroying the project
- As a first step if you want to recreate the chain from scratch (then re-run `setup-2vpc-public-ingress.sh`)

## Pre-flight: confirm what will be deleted

```bash
# List all ajbx-* resources that this script will touch:
gcloud compute forwarding-rules list --project=$PROJECT --filter="name~ajbx" --format="table(name.basename(),loadBalancingScheme)"
gcloud compute backend-services list --project=$PROJECT --filter="name~ajbx" --format="table(name.basename(),loadBalancingScheme)"
gcloud compute service-attachments list --project=$PROJECT --filter="name~ajbx" --format="table(name.basename())"
gcloud compute instance-groups managed list --project=$PROJECT --filter="name~ajbx" --format="table(name.basename(),size)"
```
