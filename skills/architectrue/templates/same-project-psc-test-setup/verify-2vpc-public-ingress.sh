# verify-2vpc-public-ingress.sh — 3-layer verification of the 2-VPC PSC NEG chain

Run after `setup-2vpc-public-ingress.sh` to confirm every layer is healthy.

## Usage

```bash
chmod +x verify-2vpc-public-ingress.sh
./verify-2vpc-public-ingress.sh
```

## What it checks

**Layer 1 — Resource existence**:
- Consumer VPC: proxy-only subnet, External IP, SSL cert, PSC NEG, Backend service, URL map, Target HTTPS proxy, Forwarding rule, Cloud Armor
- Producer VPC: VPC itself, 3 subnets, MIG (2 instances RUNNING), Health check, Backend service, URL map, Target HTTP proxy, Internal IP, Forwarding rule, Service Attachment

**Layer 2 — Association** (the cross-references that are easy to break):
- Backend service has the PSC NEG attached as backend (verify `--balancing-mode` is not set, per Gotcha 13)
- URL map points to backend service
- Target HTTPS proxy has URL map + cert
- Forwarding rule has target HTTPS proxy + IP
- Cloud Armor is attached to backend service (regional scope match)
- Producer ILB backend service has the MIG attached
- Producer ILB has backend service + URL map + target HTTP proxy + forwarding rule
- Service Attachment has at least 1 connected endpoint (from consumer VPC) with `status=ACCEPTED`

**Layer 3 — Real HTTPS traffic**:
- TLS handshake completes (curl --verbose shows the cert subject + issuer + SAN match)
- HTTP 200 from the root path
- `OK` in the body
- `/healthz` returns 200 (LB-level health check)

## Exit codes

- `0` — all checks passed
- `1` — at least one resource missing or association broken
- `2` — resources OK but traffic test failed (most likely cause: firewall Gotcha 12, or PSC tunnel still propagating)

## Common failure patterns

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| "Backend service does not have the PSC NEG" | `--balancing-mode=RATE` was passed | Re-run setup with Gotcha 13 fix |
| "Service Attachment connectedEndpoints: empty" | PSC tunnel not yet propagated | Wait 2-3 minutes and re-run verify |
| TLS handshake OK but body times out | Firewall Gotcha 12 (ILB→MIG blocked) | Add `ajbx-tenant-vpc-allow-internal` firewall in producer VPC |
| "default network not found" | Forwarding rule missing `--network=` | Re-run setup with Gotcha 14 fix |
| "Security policy must be in the same scope" | Cloud Armor is global, BS is regional | Recreate Cloud Armor with `--region=$REGION` (Gotcha 11) |
