#!/usr/bin/env bash
# create-public-internal-lb.sh — Tenant Project 侧 Public/Internal Ingress (Regional HTTPS LB) 完整链路
#
# Public (default):
#   export TENANT_PROJECT=a-project HOST_PROJECT=host-project \
#          PRODUCER_PROJECT=b-project REGION=asia-east1 \
#          VPC_NETWORK=shared-vpc CONSUMER_SUBNET=consumer-subnet \
#          PROXY_SUBNET=proxy-only-subnet \
#          SERVICE_ATTACHMENT_URI=projects/b-project/regions/asia-east1/serviceAttachments/my-sa \
#          DOMAIN=api.example.com \
#          POC_PREFIX=poc
#   bash create-public-internal-lb.sh
#
# Internal:
#   LB_SCHEME=INTERNAL_MANAGED bash create-public-internal-lb.sh
#
# 两种模式仅 3 处不同:静态 IP / Backend Service / Forwarding Rule。
# 其余命令完全对称。脚本用 LB_SCHEME 环境变量切换。
set -euo pipefail

: "${TENANT_PROJECT:?must set TENANT_PROJECT}"
: "${HOST_PROJECT:?must set HOST_PROJECT}"
: "${PRODUCER_PROJECT:?must set PRODUCER_PROJECT}"
: "${REGION:?must set REGION}"
: "${VPC_NETWORK:?must set VPC_NETWORK}"
: "${CONSUMER_SUBNET:?must set CONSUMER_SUBNET}"
: "${PROXY_SUBNET:?must set PROXY_SUBNET}"
: "${SERVICE_ATTACHMENT_URI:?must set SERVICE_ATTACHMENT_URI}"
: "${DOMAIN:?must set DOMAIN}"
: "${POC_PREFIX:=poc}"

# A 方案默认 EXTERNAL_MANAGED, B 方案改 INTERNAL_MANAGED
LB_SCHEME="${LB_SCHEME:-EXTERNAL_MANAGED}"

log()  { printf '\033[34m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ─── Step 1.1: Consumer Subnet ───
log "Step 1.1: 确保 Consumer Subnet 存在..."
if ! gcloud compute networks subnets describe "${CONSUMER_SUBNET}" \
    --project="${HOST_PROJECT}" --region="${REGION}" &>/dev/null; then
  gcloud compute networks subnets create "${CONSUMER_SUBNET}" \
    --project="${HOST_PROJECT}" --network="${VPC_NETWORK}" \
    --region="${REGION}" --range=10.0.1.0/24 \
    --enable-private-ip-google-access
fi
ok "  ✓ Consumer Subnet OK"

# ─── Step 1.2: Proxy-only Subnet (含 Gotcha #5 的 purpose 迁移) ───
log "Step 1.2: 检查 Proxy-only Subnet..."
PURPOSE=$(gcloud compute networks subnets describe "${PROXY_SUBNET}" \
  --project="${HOST_PROJECT}" --region="${REGION}" --format="value(purpose)" 2>/dev/null || echo "NONE")
if [[ "${PURPOSE}" == "NONE" ]]; then
  log "  → 不存在,新建"
  gcloud compute networks subnets create "${PROXY_SUBNET}" \
    --project="${HOST_PROJECT}" --network="${VPC_NETWORK}" \
    --region="${REGION}" --range=10.0.2.0/24 \
    --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE
elif [[ "${PURPOSE}" == "INTERNAL_HTTPS_LOAD_BALANCER" ]]; then
  log "  → 旧 purpose=INTERNAL_HTTPS_LOAD_BALANCER,执行迁移"
  gcloud compute networks subnets update "${PROXY_SUBNET}" \
    --project="${HOST_PROJECT}" --region="${REGION}" \
    --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE
elif [[ "${PURPOSE}" == "REGIONAL_MANAGED_PROXY" ]]; then
  log "  → 已是新 purpose,直接用"
fi
ok "  ✓ Proxy-only Subnet OK"

# ─── Step 2: 静态 IP (Public vs Internal) ───
log "Step 2: 创建静态 IP (${LB_SCHEME})..."
if ! gcloud compute addresses describe "${POC_PREFIX}-glb-ip" \
    --project="${TENANT_PROJECT}" --region="${REGION}" &>/dev/null; then
  if [[ "${LB_SCHEME}" == "EXTERNAL_MANAGED" ]]; then
    gcloud compute addresses create "${POC_PREFIX}-glb-ip" \
      --project="${TENANT_PROJECT}" --region="${REGION}" \
      --network-tier=PREMIUM --ip-version=IPV4
  else
    gcloud compute addresses create "${POC_PREFIX}-glb-ip" \
      --project="${TENANT_PROJECT}" --region="${REGION}" \
      --subnet="${CONSUMER_SUBNET}" \
      --purpose=GCE_ENDPOINT \
      --address-type=INTERNAL
  fi
fi
GLB_IP=$(gcloud compute addresses describe "${POC_PREFIX}-glb-ip" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --format="value(address)")
ok "  ✓ 静态 IP: ${GLB_IP}"

# ─── Step 3: SSL 证书 ───
log "Step 3: SSL 证书(需要用户预创建 ${POC_PREFIX}-cert)"
if ! gcloud compute ssl-certificates describe "${POC_PREFIX}-cert" \
    --project="${TENANT_PROJECT}" &>/dev/null; then
  fail "  ✗ SSL 证书 ${POC_PREFIX}-cert 不存在。请先在 global 范围创建证书。"
fi
ok "  ✓ SSL 证书 OK"

# ─── Step 4: Health Check ───
log "Step 4: 创建 Health Check..."
if ! gcloud compute health-checks describe "${POC_PREFIX}-hc" \
    --project="${TENANT_PROJECT}" --region="${REGION}" &>/dev/null; then
  gcloud compute health-checks create http "${POC_PREFIX}-hc" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --port=80 --request-path=/healthz \
    --check-interval=10s --timeout=5s \
    --healthy-threshold=2 --unhealthy-threshold=3
fi
ok "  ✓ Health Check OK"

# ─── Step 5: PSC NEG ───
log "Step 5: 创建 PSC NEG..."
if ! gcloud compute network-endpoint-groups describe "${POC_PREFIX}-neg" \
    --project="${TENANT_PROJECT}" --region="${REGION}" &>/dev/null; then
  gcloud compute network-endpoint-groups create "${POC_PREFIX}-neg" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
    --psc-target-service="${SERVICE_ATTACHMENT_URI}" \
    --subnetwork="${CONSUMER_SUBNET}" --network="${VPC_NETWORK}"
fi
ok "  ✓ PSC NEG OK"

# ─── Step 6: Backend Service (Public vs Internal) ───
log "Step 6: 创建 Backend Service (regional, ${LB_SCHEME})..."
if ! gcloud compute backend-services describe "${POC_PREFIX}-bs" \
    --project="${TENANT_PROJECT}" --region="${REGION}" &>/dev/null; then
  gcloud compute backend-services create "${POC_PREFIX}-bs" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --load-balancing-scheme="${LB_SCHEME}" \
    --protocol=HTTPS --port-name=https \
    --health-checks="${POC_PREFIX}-hc" \
    --health-checks-region="${REGION}" \
    --timeout=30s --enable-logging --logging-sample-rate=1.0
fi

# 把 NEG 加入 backend service (幂等)
log "Step 6.1: 添加 PSC NEG 到 Backend Service..."
if ! gcloud compute backend-services describe "${POC_PREFIX}-bs" \
    --project="${TENANT_PROJECT}" --region="${REGION}" --format=json 2>/dev/null \
    | jq -e --arg neg "${POC_PREFIX}-neg" \
      '.backends[]?.group | split("/")[-1] | select(. == $neg)' >/dev/null; then
  gcloud compute backend-services add-backend "${POC_PREFIX}-bs" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --network-endpoint-group="${POC_PREFIX}-neg" \
    --network-endpoint-group-region="${REGION}"
fi
ok "  ✓ Backend Service OK"

# ─── Step 7: URL Map ───
log "Step 7: 创建 URL Map..."
if ! gcloud compute url-maps describe "${POC_PREFIX}-um" \
    --project="${TENANT_PROJECT}" --region="${REGION}" &>/dev/null; then
  gcloud compute url-maps create "${POC_PREFIX}-um" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --default-service="${POC_PREFIX}-bs"
fi
ok "  ✓ URL Map OK"

# ─── Step 8: Target HTTPS Proxy ───
log "Step 8: 创建 Target HTTPS Proxy..."
if ! gcloud compute target-https-proxies describe "${POC_PREFIX}-proxy" \
    --project="${TENANT_PROJECT}" --region="${REGION}" &>/dev/null; then
  gcloud compute target-https-proxies create "${POC_PREFIX}-proxy" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --url-map="${POC_PREFIX}-um" --url-map-region="${REGION}" \
    --ssl-certificates="${POC_PREFIX}-cert"
fi
ok "  ✓ Target HTTPS Proxy OK"

# ─── Step 9: Forwarding Rule (Public vs Internal) ───
log "Step 9: 创建 Forwarding Rule (${LB_SCHEME})..."
if ! gcloud compute forwarding-rules describe "${POC_PREFIX}-fr" \
    --project="${TENANT_PROJECT}" --region="${REGION}" &>/dev/null; then
  if [[ "${LB_SCHEME}" == "EXTERNAL_MANAGED" ]]; then
    gcloud compute forwarding-rules create "${POC_PREFIX}-fr" \
      --project="${TENANT_PROJECT}" --region="${REGION}" \
      --load-balancing-scheme="${LB_SCHEME}" \
      --target-https-proxy="${POC_PREFIX}-proxy" \
      --target-https-proxy-region="${REGION}" \
      --address="${POC_PREFIX}-glb-ip" --address-region="${REGION}" \
      --ports=443 --network-tier=PREMIUM
  else
    gcloud compute forwarding-rules create "${POC_PREFIX}-fr" \
      --project="${TENANT_PROJECT}" --region="${REGION}" \
      --load-balancing-scheme="${LB_SCHEME}" \
      --target-https-proxy="${POC_PREFIX}-proxy" \
      --target-https-proxy-region="${REGION}" \
      --address="${POC_PREFIX}-glb-ip" --address-region="${REGION}" \
      --network="${VPC_NETWORK}" --subnet="${CONSUMER_SUBNET}" \
      --ports=443
  fi
fi
ok "  ✓ Forwarding Rule OK"

# ─── Step 10: Cloud Armor (可选,attach 到 backend service) ───
log "Step 10: 创建 Cloud Armor Policy (optional)..."
if ! gcloud compute security-policies describe "${POC_PREFIX}-armor" \
    --project="${TENANT_PROJECT}" &>/dev/null; then
  gcloud compute security-policies create "${POC_PREFIX}-armor" \
    --project="${TENANT_PROJECT}" \
    --description="Tenant LB protection"
  gcloud compute security-policies rules create 1000 \
    --project="${TENANT_PROJECT}" \
    --security-policy="${POC_PREFIX}-armor" \
    --expression="true" \
    --action=rate-based-ban \
    --rate-limit-threshold-count=200 \
    --rate-limit-threshold-interval-sec=60 \
    --ban-duration-sec=600
  # 关键:必须 attach 到 backend service,不是 forwarding rule
  gcloud compute backend-services update "${POC_PREFIX}-bs" \
    --project="${TENANT_PROJECT}" --region="${REGION}" \
    --security-policy="${POC_PREFIX}-armor"
fi
ok "  ✓ Cloud Armor OK (optional)"

ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "✓ ${LB_SCHEME} LB 链路创建完成"
ok "✓ GLB IP: ${GLB_IP}"
if [[ "${LB_SCHEME}" == "EXTERNAL_MANAGED" ]]; then
  ok "✓ DNS A 记录请指向: ${GLB_IP}"
fi
ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
