# setup-2vpc-public-ingress.sh — Idempotent full-chain setup for same-project + 2-VPC PSC NEG

Run this end-to-end to set up the entire chain (consumer VPC + producer VPC).
Idempotent: safe to re-run, existing resources are skipped.

## Required env vars (set these before running)

```bash
export PROJECT="aibang-12345678-ajbx-dev"
export REGION="europe-west2"
export DOMAIN="tenant.taobao.abjx.uk"
export CONSUMER_VPC="aibang-12345678-ajbx-dev-cinternal-vpc1"   # existing
export CONSUMER_CORE_SUBNET="cinternal-vpc1-europe-west2-abjx-core"
export POC="ajbx"                                              # resource name prefix
```

Optional:
```bash
export CERT_PATH="/Users/lex/git/gcp/ingress/public-ingress/cert/tenant.taobao.abjx.uk_bundle.crt"
export KEY_PATH="/Users/lex/git/gcp/ingress/public-ingress/cert/tenant.taobao.abjx.uk.key"
```

## Resources created

### Consumer VPC
- 1 proxy-only subnet (REGIONAL MANAGED_PROXY)
- 1 PSC NEG (PRIVATE_SERVICE_CONNECT → producer SA)
- 1 External Backend Service (EXTERNAL MANAGAGED, regional, protocol=**HTTP** — see 2-VPC reference Gotcha 10)
- 1 URL Map
- 1 Target HTTPS Proxy (with cert)
- 1 Forwarding Rule (EXTERNAL MANAGAGED, port 443, PREMIUM, --network=consumer-vpc — see Gotcha 14)
- 1 Cloud Armor (regional scope — see Gotcha 11)
- 1 SSL Certificate (uploaded from $CERT_PATH / $KEY_PATH)
- 1 External IP (PREMIUM tier)

### Producer VPC (created)
- 1 VPC (custom mode, CIDR 10.0.0.0/16)
- 3 subnets (core / proxy-only / psc-nat)
- 1 Cloud Router + 1 Cloud NAT (备用)
- 3 firewalls (IAP SSH / LB HC / **internal 10.0.0.0/8** — see Gotcha 12)
- 1 MIG (2 instances, Python HTTPS server)
- 1 Instance Template
- 1 Health Check (HTTP, port 80, /healthz)
- 1 Internal Backend Service (INTERNAL MANAGED, regional, HTTP)
- 1 URL Map
- 1 Target HTTP Proxy (note: HTTP, not HTTPS — since ILB serves plain HTTP)
- 1 Internal IP (GCE_ENDPOINT, in core subnet)
- 1 Internal Forwarding Rule (port 80, --network=producer-vpc)
- 1 Service Attachment (ACCEPT_AUTOMATIC)

## Prerequisites

1. `gcloud config set project $PROJECT`
2. The cert files at $CERT_PATH and $KEY_PATH exist (or set them to your own paths)
3. Org policy allows the LB types (run `gcloud org-policies describe constraints/compute.restrictLoadBalancingCreationForCross-cloud --project=$PROJECT` to verify)
4. APIs enabled: container, compute, networkservices
5. The startup script for the MIG (uses `templates/same-project-psc-test-setup/python-https-server.py` and base64-encodes the cert+key)

## Usage

```bash
chmod +x setup-2vpc-public-ingress.sh
./setup-2vpc-public-ingress.sh
# then wait ~60s for chain to propagate
./verify-2vpc-public-ingress.sh
# then test with curl
curl --resolve ${DOMAIN}:443:$(gcloud compute addresses describe ${POC}-public-glb-ip --region=$REGION --format="value(address)") https://${DOMAIN}/
```

## What it does (chronological phases)

1. **Phase A**: Create producer VPC + 3 subnets + Cloud NAT + 3 firewalls
2. **Phase B**: Create producer MIG (with Python HTTPS server startup) + Internal LB chain + Service Attachment
3. **Phase C**: Create consumer proxy-only subnet + PSC NEG (pointing to producer SA)
4. **Phase D**: Upload cert + create External GLB chain (backend service with protocol=HTTP) + Cloud Armor

## Idempotency

Each resource creation is gated on a `gcloud ... describe` check. If the resource exists, the script logs "skipped" and continues. Re-running won't error.

## Cleanup

Run `cleanup-2vpc-public-ingress.sh` to tear down all resources in reverse dependency order. The External IP and SSL certificate are kept by default (you can manually delete if not needed elsewhere).
