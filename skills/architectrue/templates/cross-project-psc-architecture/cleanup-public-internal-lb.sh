#!/usr/bin/env bash
# cleanup-public-internal-lb.sh — 删除 Tenant Project 侧 Public/Internal LB 资源(逆序)
# 用法: bash cleanup-public-internal-lb.sh
set -euo pipefail

: "${TENANT_PROJECT:?must set TENANT_PROJECT}"
: "${HOST_PROJECT:=${TENANT_PROJECT}}"
: "${REGION:?must set REGION}"
: "${POC_PREFIX:=poc}"

log() { printf '\033[33m%s\033[0m\n' "$*"; }

# 1. Forwarding Rule
log "1. Forwarding Rule..."
gcloud compute forwarding-rules delete "${POC_PREFIX}-fr" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

# 2. Target HTTPS Proxy
log "2. Target HTTPS Proxy..."
gcloud compute target-https-proxies delete "${POC_PREFIX}-proxy" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

# 3. URL Map
log "3. URL Map..."
gcloud compute url-maps delete "${POC_PREFIX}-um" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

# 4. Backend Service
log "4. Backend Service..."
gcloud compute backend-services delete "${POC_PREFIX}-bs" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

# 5. PSC NEG
log "5. PSC NEG..."
gcloud compute network-endpoint-groups delete "${POC_PREFIX}-neg" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

# 6. Health Check
log "6. Health Check..."
gcloud compute health-checks delete "${POC_PREFIX}-hc" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

# 7. Cloud Armor (global) — 先 detach 再删
log "7. Cloud Armor Policy (global)..."
gcloud compute security-policies delete "${POC_PREFIX}-armor" \
  --project="${TENANT_PROJECT}" --quiet 2>/dev/null || true

# 8. SSL 证书 (global)
log "8. SSL 证书 (global)..."
gcloud compute ssl-certificates delete "${POC_PREFIX}-cert" \
  --project="${TENANT_PROJECT}" --quiet 2>/dev/null || true

# 9. 静态 IP
log "9. 静态 IP..."
gcloud compute addresses delete "${POC_PREFIX}-glb-ip" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

# 10. Proxy-only Subnet (Host Project,慎删!可能其他 LB 复用)
log "10. Proxy-only Subnet (Host Project,默认保留 — 取消注释可删)..."
# gcloud compute networks subnets delete "${PROXY_SUBNET}" \
#   --project="${HOST_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

# 11. Consumer Subnet (Host Project,慎删!可能其他 LB 复用)
log "11. Consumer Subnet (Host Project,默认保留 — 取消注释可删)..."
# gcloud compute networks subnets delete "${CONSUMER_SUBNET}" \
#   --project="${HOST_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

echo
echo "✓ 清理完成。Subnet 默认保留(可能被其他 LB 复用)。"
