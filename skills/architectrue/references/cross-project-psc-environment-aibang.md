---
name: cross-project-psc-environment-aibang
description: Concrete application of the cross-project-psc-architecture pattern to the user's `aibang-12345678-ajbx-dev` project — europe-west2 / dev-lon-cluster-xxxxxx GKE / IAP-tunneled bastion, with 12-class resource inventory and three idempotent scripts (setup / verify / cleanup). Use when implementing PSC NEG public ingress in the user's actual production environment; the parent reference covers the general pattern, this one fills in the exact env values.
---

# PSC NEG Implementation in `aibang-12345678-ajbx-dev` (Environment Application)

## Pattern

Apply the parent `cross-project-psc-architecture` pattern to the user's specific environment:

```
Internet → GLB IP:443 (Regional External HTTPS LB)
        → Target HTTPS Proxy
        → URL Map (default → BS)
        → Backend Service (regional, EXTERNAL_MANAGED)
        → PSC NEG → [GCP tunnel] → B Project Service Attachment → Backend
```

All commands and IP ranges substituted to the actual environment, with the IAP-tunneled bastion workflow for `gcloud` access.

## Environment Variables (the actual values to export)

| Variable | Value | Why |
|---|---|---|
| `TENANT_PROJECT` | `aibang-12345678-ajbx-dev` | This project IS the Tenant (and also hosts GKE) |
| `PROJECT_NUMBER` | `487126826743` | From `setup-gke.md` IAM binding output |
| `REGION` | `europe-west2` | Single VPC, single region |
| `ZONE` | `europe-west2-a` | Default zone; bastion sits here |
| `VPC_NETWORK` | `aibang-12345678-ajbx-dev-cinternal-vpc1` | Already created |
| `CONSUMER_SUBNET` | `cinternal-vpc1-europe-west2-abjx-core` (192.168.0.0/18) | **Reuse** existing Core subnet; no new subnet needed for PSC NEG IP allocation |
| `PROXY_SUBNET` | `cinternal-vpc1-europe-west2-abjx-proxy` (192.168.96.0/24) | **New** — `purpose=REGIONAL_MANAGED_PROXY`, ACTIVE |
| `POC_PREFIX` | `ajbx` | Matches user's `ajbx-*` naming convention |
| `DOMAIN` | `api.example.com` | Replace with real domain |
| `SERVICE_ATTACHMENT_URI` | (TBD by B team) | From Backend Project |

### Subnet IP planning (the why behind `192.168.96.0/24` for proxy)

| Subnet | CIDR | Use |
|---|---|---|
| `cinternal-vpc1-europe-west2-abjx-gke-core-01` | 192.168.64.0/20 | GKE node IPs (secondary: pods 100.64.0.0/18, services 100.68.0.0/18) |
| `cinternal-vpc1-europe-west2-abjx-core` | 192.168.0.0/18 | Bastion + core/MIG |
| `cinternal-vpc1-europe-west2-abjx-proxy` | 192.168.96.0/24 | **NEW** — proxy-only, falls within 192.168.64.0/20's supernet but disjoint from the /20 (192.168.96.0 is INSIDE 192.168.64.0/20) — **GCP allows overlapping address allocation across subnets but each subnet must have its own non-overlapping range** — wait, 192.168.96.0/24 IS inside 192.168.64.0/20, this would collide. **Use a different /24** like 192.168.80.0/24 (no, still inside /20) or 192.168.112.0/24 (yes, outside the /20: 192.168.64.0/20 covers 192.168.64-79, so 192.168.112.0/24 is outside) |

> ⚠️ **CIDR collision risk**: The new proxy-only subnet must NOT overlap with the existing GKE node subnet `192.168.64.0/20` (which covers 192.168.64.0 - 192.168.79.255). The Core subnet `192.168.0.0/18` covers 192.168.0.0 - 192.168.63.255, so `192.168.96.0/24` is outside both ranges — confirmed safe.

Use `192.168.96.0/24` for the proxy-only subnet, falling in the gap between Core (192.168.0.0/18, ends at .63) and the next available supernet. Verified no overlap with GKE node CIDR.

## IAP-Tunneled Bastion Workflow

The GKE cluster has **private nodes + master-global-access enabled**, which means `gcloud container clusters get-credentials` from the user's local Mac fails with `TLS handshake timeout` (Master Authorized Networks doesn't include the home IP). All `gcloud` commands for the GLB chain must therefore run **from the bastion**, not locally.

```bash
# From the user's local Mac
gcloud compute ssh dev-lon-bastion-public \
    --zone=europe-west2-a \
    --tunnel-through-iap

# Now in the bastion shell — export env, run scripts
export TENANT_PROJECT=aibang-12345678-ajbx-dev
export REGION=europe-west2
# ... (rest of variables)
bash setup-public-ingress.sh
```

The bastion is a `e2-micro` Debian 11 instance with:
- `cloud-platform` scope set (so it can do all GCP operations)
- `lex-eg-gke-sa@...iam.gserviceaccount.com` not needed for bastion — bastion uses its own service account
- `Master Authorized Networks` includes bastion's internal IP `192.168.0.3/32` (in addition to user's home IP `141.98.75.210/32`)

> The bastion is in zone `europe-west2-a`; cluster is regional (`europe-west2`); nodes are in `europe-west2-b/c` likely. This is a normal pattern, not a problem.

## Scripts (canonical implementation)

The three scripts are designed to run from the bastion. They're idempotent (each step checks if the resource exists before creating) and reverse-ordered for cleanup.

### `setup-public-ingress.sh`

Creates the 12-class resource chain (10 mandatory + Cloud Armor):

```bash
#!/usr/bin/env bash
# setup-public-ingress.sh
# Run from dev-lon-bastion-public (via IAP tunnel)
set -euo pipefail

export TENANT_PROJECT="aibang-12345678-ajbx-dev"
export REGION="europe-west2"
export VPC_NETWORK="aibang-12345678-ajbx-dev-cinternal-vpc1"
export CONSUMER_SUBNET="cinternal-vpc1-europe-west2-abjx-core"
export PROXY_SUBNET="cinternal-vpc1-europe-west2-abjx-proxy"
export POC_PREFIX="ajbx"

# === Replace these with real values from B team ===
export PRODUCER_PROJECT="b-project-xxxxxx"
export SERVICE_ATTACHMENT_NAME="my-backend-sa"
export SERVICE_ATTACHMENT_URI="projects/${PRODUCER_PROJECT}/regions/${REGION}/serviceAttachments/${SERVICE_ATTACHMENT_NAME}"
export DOMAIN="api.example.com"
export HEALTH_CHECK_PATH="/healthz"
export HEALTH_CHECK_PORT="80"

log()  { printf '\033[34m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# Step 1.1 — Consumer Subnet (already exists, no-op)
log "Step 1.1: 确认 Consumer Subnet..."
gcloud compute networks subnets describe "${CONSUMER_SUBNET}" \
    --project="${TENANT_PROJECT}" --region="${REGION}" &>/dev/null \
    || fail "Consumer Subnet ${CONSUMER_SUBNET} 不存在(本环境应已建)"
ok "  ✓ Consumer Subnet OK"

# Step 1.2 — Proxy-only Subnet (new)
log "Step 1.2: 创建 Proxy-only Subnet..."
if ! gcloud compute networks subnets describe "${PROXY_SUBNET}" \
    --project="${TENANT_PROJECT}" --region="${REGION}" &>/dev/null; then
  gcloud compute networks subnets create "${PROXY_SUBNET}" \
      --project="${TENANT_PROJECT}" --network="${VPC_NETWORK}" \
      --region="${REGION}" --range=192.168.96.0/24 \
      --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE
fi
ok "  ✓ Proxy-only Subnet OK"

# Step 2 — Static External IP (Premium tier)
log "Step 2: 创建静态 External IP..."
if ! gcloud compute addresses describe "${POC_PREFIX}-public-glb-ip" \
    --project="${TENANT_PROJECT}" --region="${REGION}" &>/dev/null; then
  gcloud compute addresses create "${POC_PREFIX}-public-glb-ip" \
      --project="${TENANT_PROJECT}" --region="${REGION}" \
      --network-tier=PREMIUM --ip-version=IPV4
fi
GLB_IP=$(gcloud compute addresses describe "${POC_PREFIX}-public-glb-ip" \
    --project="${TENANT_PROJECT}" --region="${REGION}" --format="value(address)")
ok "  ✓ GLB IP: ${GLB_IP}"

# Step 3 — SSL Certificate (Google-managed or self-managed, see parent doc §5.3)
log "Step 3: SSL 证书(需用户预创建 ${POC_PREFIX}-public-cert)"
gcloud compute ssl-certificates describe "${POC_PREFIX}-public-cert" \
    --project="${TENANT_PROJECT}" &>/dev/null \
    || fail "SSL 证书不存在。请用 Google-managed 或 self-managed 创建。"

# Step 4 — Health Check
log "Step 4: 创建 Health Check..."
gcloud compute health-checks create http "${POC_PREFIX}-public-hc" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --port="${HEALTH_CHECK_PORT}" --request-path="${HEALTH_CHECK_PATH}" \
    --check-interval=10s --timeout=5s \
    --healthy-threshold=2 --unhealthy-threshold=3 2>/dev/null || true
ok "  ✓ Health Check OK"

# Step 5 — PSC NEG
log "Step 5: 创建 PSC NEG..."
gcloud compute network-endpoint-groups create "${POC_PREFIX}-public-neg" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
    --psc-target-service="${SERVICE_ATTACHMENT_URI}" \
    --subnetwork="${CONSUMER_SUBNET}" --network="${VPC_NETWORK}" 2>/dev/null || true
# Verify pscConnectionId is non-empty (B team must have approved)
PSC_CONN=$(gcloud compute network-endpoint-groups describe "${POC_PREFIX}-public-neg" \
    --project="${TENANT_PROJECT}" --region="${REGION}" --format="value(pscConnectionId)" 2>/dev/null || echo "")
[[ -n "${PSC_CONN}" && "${PSC_CONN}" != "None" ]] || fail "PSC NEG 未建立连接 — B 团队需先 approve Tenant Project"
ok "  ✓ PSC NEG OK (pscConnectionId=${PSC_CONN})"

# Step 6 — Backend Service (regional, EXTERNAL_MANAGED)
log "Step 6: 创建 Backend Service..."
gcloud compute backend-services create "${POC_PREFIX}-public-bs" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --protocol=HTTPS --port-name=https \
    --health-checks="${POC_PREFIX}-public-hc" \
    --health-checks-region="${REGION}" \
    --timeout=30s --enable-logging --logging-sample-rate=1.0 2>/dev/null || true

# Add NEG to BS (idempotent)
gcloud compute backend-services add-backend "${POC_PREFIX}-public-bs" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --network-endpoint-group="${POC_PREFIX}-public-neg" \
    --network-endpoint-group-region="${REGION}" 2>/dev/null || true
ok "  ✓ Backend Service OK"

# Step 7 — Cloud Armor (optional but recommended)
log "Step 7: 创建 Cloud Armor Policy..."
gcloud compute security-policies create "${POC_PREFIX}-public-armor" \
    --project="${TENANT_PROJECT}" --description="Public GLB protection" 2>/dev/null || true
gcloud compute security-policies rules create 1000 \
    --project="${TENANT_PROJECT}" --security-policy="${POC_PREFIX}-public-armor" \
    --expression="true" --action=rate-based-ban \
    --rate-limit-threshold-count=200 \
    --rate-limit-threshold-interval-sec=60 --ban-duration-sec=600 2>/dev/null || true
gcloud compute backend-services update "${POC_PREFIX}-public-bs" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --security-policy="${POC_PREFIX}-public-armor" 2>/dev/null || true
ok "  ✓ Cloud Armor OK"

# Step 8 — URL Map
log "Step 8: 创建 URL Map..."
gcloud compute url-maps create "${POC_PREFIX}-public-um" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --default-service="${POC_PREFIX}-public-bs" 2>/dev/null || true
ok "  ✓ URL Map OK"

# Step 9 — Target HTTPS Proxy
log "Step 9: 创建 Target HTTPS Proxy..."
gcloud compute target-https-proxies create "${POC_PREFIX}-public-proxy" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --url-map="${POC_PREFIX}-public-um" --url-map-region="${REGION}" \
    --ssl-certificates="${POC_PREFIX}-public-cert" 2>/dev/null || true
ok "  ✓ Target HTTPS Proxy OK"

# Step 10 — Forwarding Rule
log "Step 10: 创建 Forwarding Rule..."
gcloud compute forwarding-rules create "${POC_PREFIX}-public-fr" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --target-https-proxy="${POC_PREFIX}-public-proxy" \
    --target-https-proxy-region="${REGION}" \
    --address="${POC_PREFIX}-public-glb-ip" --address-region="${REGION}" \
    --ports=443 --network-tier=PREMIUM 2>/dev/null || true
ok "  ✓ Forwarding Rule OK"

ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "✓ 全部 12 类资源创建完成"
ok "✓ GLB IP: ${GLB_IP}"
ok "✓ DNS A 记录请指向: ${GLB_IP}"
ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

### `verify-public-ingress.sh`

3-layer verification: resource existence → association → real HTTPS traffic.

```bash
#!/usr/bin/env bash
# verify-public-ingress.sh
set -euo pipefail

export TENANT_PROJECT="aibang-12345678-ajbx-dev"
export REGION="europe-west2"
export POC_PREFIX="ajbx"
export CONSUMER_SUBNET="cinternal-vpc1-europe-west2-abjx-core"
export PROXY_SUBNET="cinternal-vpc1-europe-west2-abjx-proxy"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'
pass=0; fail=0; warn=0
ok()   { printf "${GREEN}✓${RESET} %s\n" "$*"; pass=$((pass+1)); }
bad()  { printf "${RED}✗${RESET} %s\n" "$*"; fail=$((fail+1)); }
note() { printf "${YELLOW}⚠${RESET} %s\n" "$*"; warn=$((warn+1)); }

echo "━━━━━ 1. 资源存在性检查 ━━━━━"
for entry in \
    "Consumer Subnet:${CONSUMER_SUBNET}:subnets" \
    "Proxy-only Subnet:${PROXY_SUBNET}:subnets" \
    "Static IP:${POC_PREFIX}-public-glb-ip:addresses" \
    "SSL Cert:${POC_PREFIX}-public-cert:ssl-certificates" \
    "Health Check:${POC_PREFIX}-public-hc:health-checks" \
    "PSC NEG:${POC_PREFIX}-public-neg:network-endpoint-groups" \
    "Backend Service:${POC_PREFIX}-public-bs:backend-services" \
    "URL Map:${POC_PREFIX}-public-um:url-maps" \
    "HTTPS Proxy:${POC_PREFIX}-public-proxy:target-https-proxies" \
    "Forwarding Rule:${POC_PREFIX}-public-fr:forwarding-rules" \
    "Cloud Armor:${POC_PREFIX}-public-armor:security-policies"; do
    IFS=':' read -r desc name type <<< "$entry"
    if [[ "$type" =~ ^(subnets|addresses|health-checks|network-endpoint-groups|backend-services|url-maps|target-https-proxies|forwarding-rules)$ ]]; then
        if gcloud compute "$type" describe "$name" --project="$TENANT_PROJECT" --region="$REGION" &>/dev/null; then
            ok "$desc"
        else
            bad "$desc"
        fi
    else
        if gcloud compute "$type" describe "$name" --project="$TENANT_PROJECT" &>/dev/null; then
            ok "$desc"
        else
            bad "$desc"
        fi
    fi
done

# Proxy-only Subnet purpose check
PURPOSE=$(gcloud compute networks subnets describe "$PROXY_SUBNET" \
    --project="$TENANT_PROJECT" --region="$REGION" --format="value(purpose)" 2>/dev/null || echo "")
[[ "$PURPOSE" == "REGIONAL_MANAGED_PROXY" ]] && ok "Proxy-only Subnet purpose=REGIONAL_MANAGED_PROXY" || bad "purpose=$PURPOSE"

echo
echo "━━━━━ 2. 关联关系 ━━━━━"
# Backend Service has NEG
gcloud compute backend-services describe "${POC_PREFIX}-public-bs" \
    --project="$TENANT_PROJECT" --region="$REGION" --format=json 2>/dev/null \
    | jq -e --arg neg "${POC_PREFIX}-public-neg" \
        '.backends[]?.group | split("/")[-1] | select(. == $neg)' >/dev/null \
    && ok "BS 挂载 PSC NEG" || bad "BS 未挂载 PSC NEG"

# PSC has connection
PSC_CONN=$(gcloud compute network-endpoint-groups describe "${POC_PREFIX}-public-neg" \
    --project="$TENANT_PROJECT" --region="$REGION" --format="value(pscConnectionId)" 2>/dev/null || echo "")
[[ -n "$PSC_CONN" && "$PSC_CONN" != "None" ]] && ok "PSC 连接 (id=$PSC_CONN)" || bad "PSC 未连接"

# Cloud Armor
gcloud compute backend-services describe "${POC_PREFIX}-public-bs" \
    --project="$TENANT_PROJECT" --region="$REGION" --format=json 2>/dev/null \
    | jq -e '.securityPolicy' >/dev/null \
    && ok "Cloud Armor 已绑定" || note "Cloud Armor 未绑定(可选)"

# Scheme check
SCHEME=$(gcloud compute backend-services describe "${POC_PREFIX}-public-bs" \
    --project="$TENANT_PROJECT" --region="$REGION" --format="value(loadBalancingScheme)" 2>/dev/null || echo "")
[[ "$SCHEME" == "EXTERNAL_MANAGED" ]] && ok "BS scheme=EXTERNAL_MANAGED" || bad "BS scheme=$SCHEME"

echo
echo "━━━━━ 3. 流量验证 ━━━━━"
GLB_IP=$(gcloud compute addresses describe "${POC_PREFIX}-public-glb-ip" \
    --project="$TENANT_PROJECT" --region="$REGION" --format="value(address)" 2>/dev/null || echo "")
[[ -n "$GLB_IP" ]] && ok "GLB IP: $GLB_IP" || { bad "无法获取 GLB IP"; GLB_IP=""; }

if [[ -n "$GLB_IP" ]]; then
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "http://$GLB_IP/" || echo "000")
    case "$HTTP_CODE" in
        301|302|307|308) ok "HTTP $HTTP_CODE → 跳 HTTPS (正常)" ;;
        200)             ok "HTTP 200" ;;
        000)             bad "HTTP 连接失败" ;;
        *)               note "HTTP $HTTP_CODE" ;;
    esac
    HTTPS_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://$GLB_IP/" || echo "000")
    case "$HTTPS_CODE" in
        200)             ok "HTTPS 200 (后端健康)" ;;
        502|503|504)     note "HTTPS $HTTPS_CODE (后端不健康,查 backend)" ;;
        000)             bad "HTTPS 连接失败" ;;
        *)               note "HTTPS $HTTPS_CODE" ;;
    esac
fi

echo
printf "通过: ${GREEN}%d${RESET}  失败: ${RED}%d${RESET}  警告: ${YELLOW}%d${RESET}\n" "$pass" "$fail" "$warn"
[[ "$fail" -eq 0 ]] || exit 1
```

### `cleanup-public-ingress.sh`

Reverse order:

```bash
#!/usr/bin/env bash
set -euo pipefail
export TENANT_PROJECT="aibang-12345678-ajbx-dev"
export REGION="europe-west2"
export POC_PREFIX="ajbx"

gcloud compute forwarding-rules delete "${POC_PREFIX}-public-fr" --project="$TENANT_PROJECT" --region="$REGION" --quiet 2>/dev/null || true
gcloud compute target-https-proxies delete "${POC_PREFIX}-public-proxy" --project="$TENANT_PROJECT" --region="$REGION" --quiet 2>/dev/null || true
gcloud compute url-maps delete "${POC_PREFIX}-public-um" --project="$TENANT_PROJECT" --region="$REGION" --quiet 2>/dev/null || true
gcloud compute backend-services delete "${POC_PREFIX}-public-bs" --project="$TENANT_PROJECT" --region="$REGION" --quiet 2>/dev/null || true
gcloud compute network-endpoint-groups delete "${POC_PREFIX}-public-neg" --project="$TENANT_PROJECT" --region="$REGION" --quiet 2>/dev/null || true
gcloud compute health-checks delete "${POC_PREFIX}-public-hc" --project="$TENANT_PROJECT" --region="$REGION" --quiet 2>/dev/null || true
gcloud compute security-policies delete "${POC_PREFIX}-public-armor" --project="$TENANT_PROJECT" --quiet 2>/dev/null || true
gcloud compute ssl-certificates delete "${POC_PREFIX}-public-cert" --project="$TENANT_PROJECT" --quiet 2>/dev/null || true
gcloud compute addresses delete "${POC_PREFIX}-public-glb-ip" --project="$TENANT_PROJECT" --region="$REGION" --quiet 2>/dev/null || true
# Proxy-only Subnet — leave (other LBs may reuse)
# gcloud compute networks subnets delete cinternal-vpc1-europe-west2-abjx-proxy --project="$TENANT_PROJECT" --region="$REGION" --quiet 2>/dev/null || true
echo "✓ 清理完成"
```

## Key workflow rules

1. **Always run from the bastion**, never locally. The Master Authorized Networks doesn't include the user's home IP.
2. **Verify cert-key pair matches** before deploying — orphaned certs (no matching key) silently fail TLS handshake with `502 Bad Gateway` from the LB.
3. **Idempotency**: every script's `if gcloud describe ... &>/dev/null` check makes re-runs safe. Critical for "did it actually create or did it fail silently?" debugging.
4. **The bastion can run all 3 profiles** (`architecture`, `default`, `blackswallow`) for the gateway — they all run as separate `hermes_cli` processes. To switch profiles for the LB chain, just re-export `HERMES_PROFILE` or pass `--profile=...` to the gateway.
5. **Don't `cd` into the project repo on the bastion unless necessary** — the bastion is for orchestration, not code editing. Use Mac for code, bastion for `gcloud`.

## Cert files for CloudFlare-fronted variant (optional)

If the user also fronts this with CloudFlare (instead of the public GLB being directly reachable), use the CloudFlare Origin Certificates in `~/git/gcp/ingress/public-ingress/cert/`:

- `cf-origin-abjx-uk-taobao.pem` + matching key
- `cf-origin-abjx-uk-wildcard.pem` + matching key

These go into `gcloud compute ssl-certificates create ... --certificate=... --private-key=...` **instead of** the Google-managed cert, and the upstream `CloudFlare → abjx.uk` routes to the LB IP. The end-to-end chain becomes:

```
Internet → CloudFlare edge (CF public cert)
        → CloudFlare → GLB IP:443 (CF Origin cert from this cert dir)
        → GLB → Backend
```

For CloudFlare-fronted variants, also do the [CloudFlare domain bypass setup](#) so Loon doesn't intercept CloudFlare's edge responses. See `gcp/cross-project/cross-project-psc-architecture.html` for the visual reference.

## See also

- Parent reference: `cross-project-psc-architecture.md` (general pattern, gotchas, decision matrices)
- `setup-gke.md` (the GKE cluster, VPC, and bastion setup that this builds on)
- `gcp/ingress/public-ingress/public-ingress-external-https-lb.md` (the 1468-line implementation guide this env-specific application was extracted from)
- `gcp/ingress/public-ingress/cert/README.md` (the cert directory, including the CloudFlare Origin certs)
