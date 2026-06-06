#!/usr/bin/env bash
# verify-tenant-lb.sh — 验证 Tenant Project 侧 LB 链路完整且可达
# Template: cross-project-psc-architecture
#
# 三层验证：资源存在性 → 关联关系 → 真实 HTTPS 流量
#
# 用法：
#   export TENANT_PROJECT=a-project HOST_PROJECT=host-project REGION=asia-east1 POC_PREFIX=poc
#   bash verify-tenant-lb.sh
set -euo pipefail

: "${TENANT_PROJECT:?must set TENANT_PROJECT}"
: "${HOST_PROJECT:=${TENANT_PROJECT}}"
: "${REGION:?must set REGION}"
: "${POC_PREFIX:=poc}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'
pass=0; fail=0; warn=0
ok()   { printf "${GREEN}✓${RESET} %s\n" "$*"; pass=$((pass+1)); }
bad()  { printf "${RED}✗${RESET} %s\n" "$*"; fail=$((fail+1)); }
note() { printf "${YELLOW}⚠${RESET} %s\n" "$*"; warn=$((warn+1)); }

check() {
  local desc="$1" cmd="$2" notfound_msg="$3"
  if eval "$cmd" &>/dev/null; then
    ok "$desc"
  else
    bad "$desc — $notfound_msg"
  fi
}

echo "━━━━━ 1. 资源存在性检查 ━━━━━"

# 1.1 网络前置
check "Consumer Subnet" \
  "gcloud compute networks subnets describe ${POC_PREFIX}-consumer-subnet --project=${HOST_PROJECT} --region=${REGION}" \
  "Subnet 不存在或权限不足"

check "Proxy-only Subnet (purpose=REGIONAL_MANAGED_PROXY)" \
  "gcloud compute networks subnets describe ${POC_PREFIX}-proxy-subnet --project=${HOST_PROJECT} --region=${REGION}" \
  "Proxy-only subnet 缺失，Forwarding Rule 将无法工作"

# 1.2 入口资源
check "静态 IP" \
  "gcloud compute addresses describe ${POC_PREFIX}-glb-ip --project=${TENANT_PROJECT} --region=${REGION}" \
  "静态 IP 缺失"

check "SSL 证书 (global)" \
  "gcloud compute ssl-certificates describe ${POC_PREFIX}-cert --project=${TENANT_PROJECT}" \
  "SSL 证书缺失，HTTPS 入口会失败"

check "Health Check" \
  "gcloud compute health-checks describe ${POC_PREFIX}-hc --project=${TENANT_PROJECT} --region=${REGION}" \
  "Health Check 缺失"

check "PSC NEG" \
  "gcloud compute network-endpoint-groups describe ${POC_PREFIX}-neg --project=${TENANT_PROJECT} --region=${REGION}" \
  "PSC NEG 缺失"

check "Backend Service (regional)" \
  "gcloud compute backend-services describe ${POC_PREFIX}-bs --project=${TENANT_PROJECT} --region=${REGION}" \
  "Backend Service 缺失或不是 regional"

check "URL Map (regional)" \
  "gcloud compute url-maps describe ${POC_PREFIX}-um --project=${TENANT_PROJECT} --region=${REGION}" \
  "URL Map 缺失或不是 regional"

check "Target HTTPS Proxy (regional)" \
  "gcloud compute target-https-proxies describe ${POC_PREFIX}-proxy --project=${TENANT_PROJECT} --region=${REGION}" \
  "Target HTTPS Proxy 缺失或不是 regional"

check "Forwarding Rule (regional)" \
  "gcloud compute forwarding-rules describe ${POC_PREFIX}-fr --project=${TENANT_PROJECT} --region=${REGION}" \
  "Forwarding Rule 缺失或不是 regional"

echo
echo "━━━━━ 2. 关联关系检查 ━━━━━"

# Backend Service 是否引用了 NEG
if gcloud compute backend-services describe "${POC_PREFIX}-bs" \
    --project="${TENANT_PROJECT}" --region="${REGION}" --format=json 2>/dev/null \
    | jq -e --arg neg "${POC_PREFIX}-neg" \
      '.backends[]?.group | split("/")[-1] | select(. == $neg)' >/dev/null; then
  ok "Backend Service 已挂载 PSC NEG"
else
  bad "Backend Service 未挂载 PSC NEG"
fi

# NEG 是否成功连上 Service Attachment
PSC_CONN=$(gcloud compute network-endpoint-groups describe "${POC_PREFIX}-neg" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --format="value(pscConnectionId)" 2>/dev/null || echo "")
if [[ -n "${PSC_CONN}" && "${PSC_CONN}" != "None" ]]; then
  ok "PSC NEG 已建立连接 (pscConnectionId=${PSC_CONN})"
else
  bad "PSC NEG 未建立连接 — Service Attachment 可能未 approve Tenant Project"
fi

# Cloud Armor（可选）
if gcloud compute backend-services describe "${POC_PREFIX}-bs" \
    --project="${TENANT_PROJECT}" --region="${REGION}" --format=json 2>/dev/null \
    | jq -e '.securityPolicy' >/dev/null; then
  ok "Cloud Armor Policy 已绑定"
else
  note "Cloud Armor Policy 未绑定（可选但推荐）"
fi

echo
echo "━━━━━ 3. 流量验证 ━━━━━"

GLB_IP=$(gcloud compute addresses describe "${POC_PREFIX}-glb-ip" \
  --project="${TENANT_PROJECT}" --region="${REGION}" --format="value(address)" 2>/dev/null || echo "")

if [[ -n "${GLB_IP}" ]]; then
  ok "GLB IP 解析: ${GLB_IP}"

  # HTTP 测（应 301/308 跳 HTTPS）
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "http://${GLB_IP}/" || echo "000")
  if [[ "${HTTP_CODE}" =~ ^(301|302|307|308)$ ]]; then
    ok "HTTP 入口正常 (${HTTP_CODE} → HTTPS)"
  else
    note "HTTP 返回码 ${HTTP_CODE}（如果 000 可能是 IP 尚未广播，等待 1-2 分钟）"
  fi

  # HTTPS 测（应 200 / 502 / 503，而不是 connection refused）
  HTTPS_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://${GLB_IP}/" || echo "000")
  case "${HTTPS_CODE}" in
    200) ok "HTTPS 入口正常 (200)" ;;
    502|503|504) note "HTTPS 返回 ${HTTPS_CODE} — 后端不健康或路径不存在" ;;
    000) bad "HTTPS 连接失败 — 检查 Forwarding Rule / Firewall" ;;
    *) note "HTTPS 返回 ${HTTPS_CODE}" ;;
  esac
else
  bad "无法获取 GLB IP"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "通过: ${GREEN}%d${RESET}  失败: ${RED}%d${RESET}  警告: ${YELLOW}%d${RESET}\n" "$pass" "$fail" "$warn"
[[ "$fail" -eq 0 ]] || exit 1
