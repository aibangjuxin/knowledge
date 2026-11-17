#!/usr/bin/env bash
# cleanup-tenant-lb.sh — 删除 Tenant Project 侧全部 LB 资源（逆序）
# Template: cross-project-psc-architecture
#
# 用法：
#   export TENANT_PROJECT=a-project HOST_PROJECT=host-project REGION=asia-east1 POC_PREFIX=poc
#   bash cleanup-tenant-lb.sh
#
# 顺序：Forwarding Rule → Proxy → URL Map → BS → NEG → HC → Cert (global) → IP → Subnets
# ⚠️  Consumer Subnet 默认保留（可能其他 LB 复用）；取消最后注释可强制删除。
set -euo pipefail

: "${TENANT_PROJECT:?must set TENANT_PROJECT}"
: "${HOST_PROJECT:=${TENANT_PROJECT}}"
: "${REGION:?must set REGION}"
: "${POC_PREFIX:=poc}"

log() { printf '\033[33m%s\033[0m\n' "$*"; }
rmr() { gcloud "$@" delete --quiet 2>/dev/null || true; }

log "1. Forwarding Rule..."
gcloud compute forwarding-rules delete "${POC_PREFIX}-fr" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

log "2. Target HTTPS Proxy..."
gcloud compute target-https-proxies delete "${POC_PREFIX}-proxy" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

log "3. URL Map..."
gcloud compute url-maps delete "${POC_PREFIX}-um" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

log "4. Backend Service..."
gcloud compute backend-services delete "${POC_PREFIX}-bs" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

log "5. PSC NEG..."
gcloud compute network-endpoint-groups delete "${POC_PREFIX}-neg" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

log "6. Health Check..."
gcloud compute health-checks delete "${POC_PREFIX}-hc" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

log "7. SSL 证书 (global)..."
gcloud compute ssl-certificates delete "${POC_PREFIX}-cert" \
  --project="${TENANT_PROJECT}" --quiet 2>/dev/null || true

log "8. 静态 IP..."
gcloud compute addresses delete "${POC_PREFIX}-glb-ip" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

log "9. Proxy-only Subnet (Host Project)..."
gcloud compute networks subnets delete "${POC_PREFIX}-proxy-subnet" \
  --project="${HOST_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

log "10. Consumer Subnet (Host Project，谨慎！其他 LB 可能复用)..."
# 默认注释避免误删；如确认可删除，取消下面注释：
# gcloud compute networks subnets delete "${POC_PREFIX}-consumer-subnet" \
#   --project="${HOST_PROJECT}" --region="${REGION}" --quiet 2>/dev/null || true

echo
echo "✓ 清理完成。Consumer Subnet 保留（可能被其他 LB 复用）。"
