# 2-VPC Same-Project PSC NEG — Full Worked Example + 7 New Gotchas

> Companion to `references/same-project-psc-test-setup.md`. Read that first for the 9 foundational gotchas (Cloud NAT, proxy-only subnet, regional MIG flag, PSC NEG no health check, etc.). This doc covers the **2-VPC variant** (consumer + producer in same project) and the **7 additional gotchas** discovered when actually executing it on `aibang-12345678-ajbx-dev / europe-west2 / 2026-06`.

## Why 2 VPCs in the same project

The fundamental GCP limitation from `same-project-psc-test-setup.md`:
> Regional `EXTERNAL MANAGED` Backend Service in scope REGION cannot use a Private Service Connect network endpoint group that is in producer network and targets a Service Attachment.

Same project + same VPC fails. So you need either:
1. 2 different VPCs in the same project (this doc)
2. 2 different projects (the cross-project pattern in `references/cross-project-psc-architecture.md`)

For testing PSC in a single project, option 1 is the only honest path.

## Concrete 2-VPC layout (worked on `aibang-12345678-ajbx-dev`)

| VPC | CIDR | Subnet | Role | Resources |
| --- | --- | --- | --- | --- |
| `aibang-12345678-ajbx-dev-cinternal-vpc1` (existing) | `192.168.0.0/18` | `abjx-core` (192.168.0.0/18, existing) | **Consumer** | External GLB + PSC NEG |
| | | `abjx-gke-core-01` (existing) | | GKE (untouched) |
| | | `abjx-proxy` (192.168.96.0/24, **new**) | | proxy-only for External GLB |
| `ajbx-tenant-vpc` (new) | `10.0.0.0/16` | `abjx-core` (10.0.1.0/24, new) | **Producer** | MIG + Internal LB + Service Attachment |
| | | `abjx-proxy` (10.0.2.0/24, new) | | proxy-only for Internal LB |
| | | `abjx-psc-nat` (10.0.3.0/24, new) | | PSC NAT for SA |

The 10.0.0.0/8 range was chosen specifically to **not overlap** with the consumer's `192.168.0.0/18`. If your consumer VPC uses a different range, pick something else for the producer. The proxy-only subnet CIDR `/24` is the minimum recommended (GCP accepts `/26` minimum but `/24` gives 253 IPs of headroom).

## Resource count by VPC

**Consumer VPC** (10 resources total — leaves GKE/bastion alone):
- 1 External IP (`ajbx-public-glb-ip`, 34.105.229.97 in the worked example)
- 1 SSL certificate (`ajbx-public-cert`, self-managed, regional)
- 1 proxy-only subnet (`cinternal-vpc1-europe-west2-abjx-proxy`, REGIONAL_MANAGED_PROXY)
- 1 PSC NEG (`ajbx-public-neg`, PRIVATE_SERVICE_CONNECT, subnet=`abjx-core`)
- 1 External Backend Service (`ajbx-public-bs`, EXTERNAL_MANAGED, regional, **protocol=HTTP**)
- 1 URL Map (`ajbx-public-um`)
- 1 Target HTTPS Proxy (`ajbx-public-proxy`, with cert)
- 1 Forwarding Rule (`ajbx-public-fr`, EXTERNAL_MANAGED, port 443, PREMIUM, **--network=consumer-vpc**)
- 1 Cloud Armor (regional scope — see Gotcha 11)

**Producer VPC** (~13 resources total):
- 1 Cloud Router + 1 Cloud NAT (兜底,Python HTTPS server 实际不需要)
- 1 proxy-only subnet
- 1 PSC NAT subnet
- 1 Health Check (HTTP, port 80, /healthz)
- 1 Backend Service (INTERNAL_MANAGED, regional, HTTP)
- 1 URL Map
- 1 Target HTTP Proxy (note: HTTP not HTTPS, since ILB serves plain HTTP)
- 1 Internal IP (GCE_ENDPOINT, in core subnet)
- 1 Forwarding Rule (INTERNAL_MANAGED, port 80, --network=producer-vpc --subnet=producer-core)
- 1 Service Attachment (ACCEPT_AUTOMATIC, nat-subnets=psc-nat)
- 1 MIG with 2 instances (Python HTTPS server on 80+443)
- 3 firewalls (IAP SSH, LB HC, **internal traffic** — see Gotcha 12)

**Global**:
- 1 Cloud Armor (`ajbx-public-armor`, regional scope)

## The 7 new gotchas (beyond the original 9 in `same-project-psc-test-setup.md`)

### Gotcha 10: Backend service protocol must be **HTTP** (not HTTPS) for GLB + PSC NEG

When the chain is `External GLB → PSC NEG → ILB → MIG`, the External GLB terminates TLS at the GLB edge (using your uploaded cert), then forwards **plaintext** through the PSC tunnel to the ILB. The ILB then forwards HTTP to the MIG.

If you create the backend service with `--protocol=HTTPS`:
- GLB will attempt a TLS handshake with the backend through the PSC tunnel
- The ILB only listens on 80 (HTTP), so it will receive a `WRONG_VERSION_NUMBER` TLS error
- Curl sees: `upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure, transport failure reason: TLS_error: ...WRONG_VERSION_NUMBER`

**Fix**: `--protocol=HTTP` (NOT HTTPS) on the backend service when the chain is GLB → PSC NEG → ILB. The TLS termination happens once at the GLB edge; everything inside is plaintext.

This is **only** for the GLB+PSC pattern. If you use a GKE-based backend with K8s Gateway API (which can do end-to-end mTLS), the backend service is `HTTPS` (or `HTTP2`).

### Gotcha 11: Cloud Armor must be **regional scope** when attaching to a regional backend service

The backend service `ajbx-public-bs` is **regional** (it lives in `europe-west2`). Cloud Armor policies have a **scope** that must match the backend service scope, or you get:

```
Security policy must be in the same scope as the target resource.
```

If you created the policy as a global resource:
```bash
gcloud compute security-policies create ${POC}-armor
# default scope: global
```

Update the attach to a regional policy, or recreate it as regional:
```bash
gcloud compute security-policies delete ${POC}-armor
gcloud compute security-policies create ${POC}-armor \
    --region=${REGION} \
    --description="${POC} Public GLB DDoS + rate limit (regional)"
```

Then the rate-limit rule and the `backend-services update --security-policy=...` both run in the regional scope.

For Global External HTTPS LB (if you ever go that path), the security policy can be global.

### Gotcha 12: Producer VPC needs an explicit firewall for ILB→MIG internal traffic

This one is subtle and shows up as a `curl` that **completes the TLS handshake successfully** but then times out waiting for backend response. The TLS is fine (GLB → your TrustAsia cert), but the GLB can't reach the MIG through the ILB because the firewall blocks it.

Symptom (verbose curl):
```
* SSL connection using TLSv1.3 / AEAD-CHACHA20-POLY1305-SHA256
* Server certificate:
*  subject: CN=tenant.taobao.abjx.uk
*  SSL certificate verify ok.
<no further output, then timeout>
```

ILB is in the same VPC as MIG, in the same subnet, so you might assume GCP allows internal traffic. **It doesn't by default** — every Ingress rule must be explicit.

**Fix** in the producer VPC:
```bash
gcloud compute firewall-rules create ${POC}-allow-internal \
    --network=${PRODUCER_VPC} \
    --direction=INGRESS --action=ALLOW \
    --rules=tcp,udp,icmp \
    --source-ranges=10.0.0.0/8
```

The `10.0.0.0/8` source is broad — for production, restrict to the actual core subnet CIDR. For testing, broad is fine. **Critical point**: this rule is needed even though everything is "internal" — GCP doesn't auto-allow internal traffic within a custom-mode VPC.

### Gotcha 13: PSC NEG `add-backend` rejects `--balancing-mode=RATE`

```
Invalid value for field 'resource.backends[0].balancingMode': 'RATE'.
Balancing mode is not supported for Private Service Connect network endpoint groups.
```

PSC NEG backends only support the default `UTILIZATION` mode. Fix: omit `--balancing-mode` (and `--max-rate-per-instance`) from the `add-backend` command.

### Gotcha 14: External Regional forwarding rule may need explicit `--network=...` flag

When a project has only custom-mode VPCs (no `default` network), the implicit `gcloud compute forwarding-rules create` call tries to find `default` and fails with:
```
The resource 'projects/.../global/networks/default' was not found.
```

This is misleading — the error is about the `default` network, but the actual root cause is the project has no default network. Fix:
```bash
gcloud compute forwarding-rules create ${POC}-fr \
    --network=${CONSUMER_VPC} \    # ← explicit
    ...
```

This applies to External Managed and Internal Managed Regional forwarding rules when the project lacks a default network.

### Gotcha 15: PSC NEG data-plane status (pscDataPlaneStatus: None) is normal, don't panic

When you `gcloud compute network-endpoint-groups describe ${NEG}` immediately after creating a PSC NEG:
```
pscConnectionId: None
pscDataPlaneStatus: None
```

This is **normal** for a while after creation. The real connection state shows on the **Service Attachment** side:
```bash
gcloud compute service-attachments describe ${SA} --region=${REGION} \
    --format="get(connectedEndpoints)"
# Expect: at least 1 entry with status=ACCEPTED + pscConnectionId populated
```

If the SA shows `ACCEPTED`, the PSC tunnel is up regardless of what `pscDataPlaneStatus` says on the NEG. Wait a few minutes, then re-check the NEG — the status fields will populate.

### Gotcha 16: Proxy-only subnet is required for **both** Internal and External Regional LBs

Gotcha 2 mentioned this for Internal LBs. The same applies to External Regional LBs (the user is using one here). The error is:
```
An active proxy-only subnetwork is required in the same region and VPC as the forwarding rule.
```

If you delete the proxy-only subnet mid-flow (e.g., during a VPC migration), the forwarding rule creation fails until you re-create the subnet. The proxy-only subnet must:
- be in the **same VPC** as the LB's `--network`
- be in the **same region** as the LB
- have `purpose=REGIONAL_MANAGED_PROXY` and `role=ACTIVE`
- be in a CIDR range that doesn't conflict with anything else (e.g., `/24`)

## Full command sequence (chronological, 2-VPC variant)

Phase A — Producer VPC network:
```bash
# 1. Producer VPC + 3 subnets
gcloud compute networks create ${POC}-producer-vpc --subnet-mode=custom
gcloud compute networks subnets create ${POC}-producer-vpc-${REGION}-core \
    --network=${POC}-producer-vpc --region=${REGION} --range=10.0.1.0/24 --enable-private-ip-google-access
gcloud compute networks subnets create ${POC}-producer-vpc-${REGION}-proxy \
    --network=${POC}-producer-vpc --region=${REGION} --range=10.0.2.0/24 \
    --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE
gcloud compute networks subnets create ${POC}-producer-vpc-${REGION}-psc-nat \
    --network=${POC}-producer-vpc --region=${REGION} --range=10.0.3.0/24 \
    --purpose=PRIVATE_SERVICE_CONNECT

# 2. Cloud NAT (兜底,Python HTTPS server 实际不需要)
gcloud compute routers create ${POC}-producer-vpc-router --network=${POC}-producer-vpc --region=${REGION}
gcloud compute routers nats create ${POC}-producer-vpc-nat \
    --router=${POC}-producer-vpc-router --region=${REGION} \
    --nat-all-subnet-ip-ranges --auto-allocate-nat-external-ips

# 3. 3 firewalls
gcloud compute firewall-rules create ${POC}-producer-vpc-allow-iap-ssh \
    --direction=INGRESS --action=ALLOW --rules=tcp:22 \
    --source-ranges=35.235.240.0/20 --network=${POC}-producer-vpc --target-tags=tenant-backend
gcloud compute firewall-rules create ${POC}-producer-vpc-allow-lb-hc \
    --direction=INGRESS --action=ALLOW --rules=tcp:80,tcp:443 \
    --source-ranges=35.191.0.0/16,130.211.0.0/22 --network=${POC}-producer-vpc --target-tags=http-server,https-server
gcloud compute firewall-rules create ${POC}-producer-vpc-allow-internal \
    --direction=INGRESS --action=ALLOW --rules=tcp,udp,icmp \
    --source-ranges=10.0.0.0/8 --network=${POC}-producer-vpc
```

Phase B — Producer MIG + ILB + SA:
```bash
# 4. MIG with Python HTTPS server (using the Python template)
gcloud compute instance-templates create ${POC}-producer-vpc-backend-tmpl \
    --machine-type=e2-small --image-family=debian-11 --image-project=debian-cloud \
    --network=${POC}-producer-vpc --subnet=${POC}-producer-vpc-${REGION}-core --region=${REGION} \
    --no-address --tags=http-server,https-server,tenant-backend \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --metadata-from-file=startup-script=${SCRIPT_DIR}/startup-tenant-server.sh
gcloud compute instance-groups managed create ${POC}-producer-vpc-backend-mig \
    --base-instance-name=${POC}-producer-vpc-backend --template=${POC}-producer-vpc-backend-tmpl \
    --region=${REGION} --size=2 --target-distribution-shape=EVEN
# wait ~60s for instance RUNNING + startup to complete

# 5. ILB chain
gcloud compute health-checks create http ${POC}-producer-vpc-internal-hc \
    --region=${REGION} --port=80 --request-path=/healthz
gcloud compute backend-services create ${POC}-producer-vpc-internal-bs \
    --region=${REGION} --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=HTTP --port-name=http \
    --health-checks=${POC}-producer-vpc-internal-hc --health-checks-region=${REGION}
gcloud compute backend-services add-backend ${POC}-producer-vpc-internal-bs \
    --region=${REGION} --instance-group=${POC}-producer-vpc-backend-mig \
    --instance-group-region=${REGION} --balancing-mode=RATE --max-rate-per-instance=100
gcloud compute url-maps create ${POC}-producer-vpc-internal-um --region=${REGION} --default-service=${POC}-producer-vpc-internal-bs
gcloud compute target-http-proxies create ${POC}-producer-vpc-internal-proxy \
    --region=${REGION} --url-map=${POC}-producer-vpc-internal-um --url-map-region=${REGION}
gcloud compute addresses create ${POC}-producer-vpc-internal-lb-ip \
    --region=${REGION} --subnet=${POC}-producer-vpc-${REGION}-core --purpose=GCE_ENDPOINT
gcloud compute forwarding-rules create ${POC}-producer-vpc-internal-fr \
    --region=${REGION} --load-balancing-scheme=INTERNAL_MANAGED \
    --target-http-proxy=${POC}-producer-vpc-internal-proxy --target-http-proxy-region=${REGION} \
    --address=${POC}-producer-vpc-internal-lb-ip --address-region=${REGION} \
    --ports=80 --network=${POC}-producer-vpc --subnet=${POC}-producer-vpc-${REGION}-core

# 6. Service Attachment
gcloud compute service-attachments create ${POC}-producer-vpc-internal-sa \
    --region=${REGION} \
    --producer-forwarding-rule=${POC}-producer-vpc-internal-fr \
    --connection-preference=ACCEPT_AUTOMATIC \
    --nat-subnets=${POC}-producer-vpc-${REGION}-psc-nat
```

Phase C — Consumer VPC External GLB + PSC NEG:
```bash
# 7. Consumer proxy-only subnet (新建,如果之前没建)
gcloud compute networks subnets create ${POC}-consumer-vpc-${REGION}-proxy \
    --network=${CONSUMER_VPC} --region=${REGION} --range=<unique /24> \
    --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE

# 8. PSC NEG in consumer VPC, pointing to producer SA
gcloud compute network-endpoint-groups create ${POC}-public-neg \
    --region=${REGION} \
    --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
    --psc-target-service=projects/${PROJECT}/regions/${REGION}/serviceAttachments/${POC}-producer-vpc-internal-sa \
    --subnet=<consumer-core-subnet> --network=${CONSUMER_VPC}

# 9. External GLB chain (protocol=HTTP, see Gotcha 10)
gcloud compute backend-services create ${POC}-public-bs \
    --region=${REGION} --load-balancing-scheme=EXTERNAL_MANAGED \
    --protocol=HTTP --port-name=http --timeout=30s
gcloud compute backend-services add-backend ${POC}-public-bs \
    --region=${REGION} --network-endpoint-group=${POC}-public-neg --network-endpoint-group-region=${REGION}
# NO --balancing-mode for PSC NEG (see Gotcha 13)

gcloud compute url-maps create ${POC}-public-um --region=${REGION} --default-service=${POC}-public-bs
gcloud compute target-https-proxies create ${POC}-public-proxy \
    --region=${REGION} --url-map=${POC}-public-um --url-map-region=${REGION} \
    --ssl-certificates=${POC}-public-cert --ssl-certificates-region=${REGION}
gcloud compute forwarding-rules create ${POC}-public-fr \
    --region=${REGION} --load-balancing-scheme=EXTERNAL_MANAGED \
    --target-https-proxy=${POC}-public-proxy --target-https-proxy-region=${REGION} \
    --address=${POC}-public-glb-ip --address-region=${REGION} \
    --ports=443 --network-tier=PREMIUM --network=${CONSUMER_VPC}
# NO --ip-version=IPV4 (see Gotcha 6 in main reference)

# 10. Cloud Armor (REGIONAL, see Gotcha 11)
gcloud compute security-policies create ${POC}-public-armor \
    --region=${REGION} --description="${POC} DDoS + rate limit"
gcloud compute security-policies rules create 1000 \
    --region=${REGION} --security-policy=${POC}-public-armor \
    --expression="true" --action=rate-based-ban \
    --rate-limit-threshold-count=200 --rate-limit-threshold-interval-sec=60 \
    --conform-action=allow --exceed-action=deny-429 --ban-duration-sec=600
gcloud compute backend-services update ${POC}-public-bs \
    --region=${REGION} --security-policy=${POC}-public-armor
```

## End-to-end validation

```bash
# Wait 60-90s for the chain to fully propagate, then:

# 1. Producer MIG health
gcloud compute backend-services get-health ${POC}-producer-vpc-internal-bs --region=${REGION}
# Expect: 2 instances, both HEALTHY

# 2. PSC connection (look at SA side, not NEG side)
gcloud compute service-attachments describe ${POC}-producer-vpc-internal-sa \
    --region=${REGION} --format="get(connectedEndpoints)"
# Expect: 1 entry with status=ACCEPTED + pscConnectionId populated

# 3. End-to-end curl (with --resolve to test without DNS)
GLB_IP=$(gcloud compute addresses describe ${POC}-public-glb-ip --region=${REGION} --format="value(address)")
curl -sS --resolve ${DOMAIN}:443:${GLB_IP} -o /tmp/e2e.html \
    -w "  HTTPS / → HTTP %{http_code}, %{size_download}B, %{time_total}s\n" \
    --max-time 30 https://${DOMAIN}/
# Expect: 200, ~200-300 bytes, <2s

# 4. Body
cat /tmp/e2e.html | head -10
# Expect: <h1>OK</h1><p>Hello from PSC NEG end-to-end test (HTTPS)</p>
```

## Common debugging path (TLS-OK-then-timeout signal)

If `curl --resolve ...` shows the TLS handshake completes (with the right cert subject + issuer + SAN match) but then the response hangs and times out, the issue is **not** TLS — it's downstream. The most common cause in this 2-VPC setup is **Gotcha 12** (firewall blocking ILB→MIG).

Quick triage:
```bash
# Confirm MIG itself is healthy (bypass the LB chain)
ZONE=$(gcloud compute instances list --filter="name~${POC}-producer-vpc-backend AND status=RUNNING" --format="value(zone)" | head -1)
INST=$(gcloud compute instances list --filter="name~${POC}-producer-vpc-backend AND status=RUNNING" --format="value(name)" | head -1)
gcloud compute ssh $INST --zone=$ZONE --tunnel-through-iap \
    --command="curl -sS -o /dev/null -w 'local /healthz → %{http_code}\n' http://127.0.0.1/healthz"
# Expect: 200

# If 200, MIG is fine. Issue is GLB→PSC→ILB→MIG path.
# If timeout, MIG itself broken (startup script failed, cert wrong, etc.)

# Then check the firewall
gcloud compute firewall-rules list --filter="network.basename():${POC}-producer-vpc" --format="table(name,sourceRanges,targetTags)"
# Confirm ajbx-allow-internal (or similar) exists
```

## Cleanup (full reverse-order)

```bash
# Consumer side (reverse order)
gcloud compute backend-services delete ${POC}-public-bs --region=${REGION} --quiet
gcloud compute target-https-proxies delete ${POC}-public-proxy --region=${REGION} --quiet
gcloud compute url-maps delete ${POC}-public-um --region=${REGION} --quiet
gcloud compute network-endpoint-groups delete ${POC}-public-neg --region=${REGION} --quiet
gcloud compute security-policies delete ${POC}-public-armor --quiet    # global name, not regional for delete

# Optional: delete consumer proxy-only subnet if no other LB uses it
# gcloud compute networks subnets delete ${POC}-consumer-vpc-${REGION}-proxy --region=${REGION} --quiet

# Producer side (reverse order)
gcloud compute service-attachments delete ${POC}-producer-vpc-internal-sa --region=${REGION} --quiet
gcloud compute forwarding-rules delete ${POC}-producer-vpc-internal-fr --region=${REGION} --quiet
gcloud compute target-http-proxies delete ${POC}-producer-vpc-internal-proxy --region=${REGION} --quiet
gcloud compute url-maps delete ${POC}-producer-vpc-internal-um --region=${REGION} --quiet
gcloud compute backend-services delete ${POC}-producer-vpc-internal-bs --region=${REGION} --quiet
gcloud compute health-checks delete ${POC}-producer-vpc-internal-hc --region=${REGION} --quiet
gcloud compute addresses delete ${POC}-producer-vpc-internal-lb-ip --region=${REGION} --quiet
gcloud compute instance-groups managed delete ${POC}-producer-vpc-backend-mig --region=${REGION} --quiet
gcloud compute instance-templates delete ${POC}-producer-vpc-backend-tmpl --quiet

# Subnets (order doesn't matter, no deps)
gcloud compute networks subnets delete ${POC}-producer-vpc-${REGION}-psc-nat --region=${REGION} --quiet
gcloud compute networks subnets delete ${POC}-producer-vpc-${REGION}-proxy --region=${REGION} --quiet
gcloud compute networks subnets delete ${POC}-producer-vpc-${REGION}-core --region=${REGION} --quiet

# Cloud NAT (delete NAT before router)
gcloud compute routers nats delete ${POC}-producer-vpc-nat --router=${POC}-producer-vpc-router --region=${REGION} --quiet
gcloud compute routers delete ${POC}-producer-vpc-router --region=${REGION} --quiet

# Firewalls (independent)
for fw in ${POC}-producer-vpc-allow-internal ${POC}-producer-vpc-allow-lb-hc ${POC}-producer-vpc-allow-iap-ssh; do
    gcloud compute firewall-rules delete $fw --quiet
done

# Producer VPC itself
gcloud compute networks delete ${POC}-producer-vpc --quiet

# External IP and cert (keep these if you have other LBs using them)
# gcloud compute addresses delete ${POC}-public-glb-ip --region=${REGION} --quiet
# gcloud compute ssl-certificates delete ${POC}-public-cert --region=${REGION} --quiet
```

## Key insight: why this 2-VPC pattern matters

The 2-VPC same-project pattern is **not a hack** — it correctly emulates the cross-project PSC pattern's security boundary. In production, you'd use cross-project; in single-project testing, 2-VPC gives the same correctness. The only difference is that you own both VPCs instead of relying on another team's project for the SA.

If you understand this 2-VPC pattern well, you understand cross-project PSC — the difference is just who owns the producer VPC.
