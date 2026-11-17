#!/bin/bash
#
# 校验 PSC 跨 Region DR 链路是否就绪
#
# 用法：./verify-dr-psc.sh
#
# 检查项：
#   1. DR 实例存在且 RUNNABLE
#   2. allowedConsumerProjects 包含 Consumer 项目
#   3. Endpoint B 存在、ACCEPTED、global access 已开启
#   4. 复制状态 / 复制延迟
#   5.（可选）从 Consumer 侧 VM/Pod 测试 TCP 连通性

set -uo pipefail

export PRODUCER_PROJECT_ID="${PRODUCER_PROJECT_ID:-your-db-project}"
export CONSUMER_PROJECT_ID="${CONSUMER_PROJECT_ID:-your-app-project}"
export REGION_A="${REGION_A:-europe-west2}"
export REGION_B="${REGION_B:-europe-west1}"
export SQL_A="${SQL_A:-sql-primary-euw2}"
export SQL_B="${SQL_B:-sql-dr-euw1}"
export EP_A_NAME="${EP_A_NAME:-sql-psc-ep-a}"
export EP_B_NAME="${EP_B_NAME:-sql-psc-ep-b}"
export DB_PORT="${DB_PORT:-3306}"

PASS=0
FAIL=0

check() {
  local desc="$1"; local expected="$2"; local actual="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    echo "  ✅ ${desc}: ${actual}"
    PASS=$((PASS+1))
  else
    echo "  ❌ ${desc}: 期望 ${expected}，实际 ${actual}"
    FAIL=$((FAIL+1))
  fi
}

echo "=============================================="
echo " PSC 跨 Region DR 链路校验"
echo "=============================================="

# ---- 1. DR 实例状态 ----
echo ""
echo "[1/5] Producer 侧 Cloud SQL"
STATE=$(gcloud sql instances describe ${SQL_B} --project=${PRODUCER_PROJECT_ID} \
  --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
check "DR 实例 ${SQL_B} 状态" "RUNNABLE" "${STATE}"

ALLOWED=$(gcloud sql instances describe ${SQL_B} --project=${PRODUCER_PROJECT_ID} \
  --format="value(settings.pscConfig.allowedConsumerProjects)" 2>/dev/null || echo "")
if [[ "${ALLOWED}" == *"${CONSUMER_PROJECT_ID}"* ]]; then
  echo "  ✅ allowedConsumerProjects 包含 ${CONSUMER_PROJECT_ID}"
  PASS=$((PASS+1))
else
  echo "  ❌ allowedConsumerProjects 未包含 ${CONSUMER_PROJECT_ID}（当前: ${ALLOWED}）"
  FAIL=$((FAIL+1))
fi

SA_B=$(gcloud sql instances describe ${SQL_B} --project=${PRODUCER_PROJECT_ID} \
  --format="value(pscServiceAttachmentLink)" 2>/dev/null || echo "")
echo "  ℹ️  SA B = ${SA_B}"

# ---- 2. Endpoint A（现有链路）----
echo ""
echo "[2/5] Consumer 侧 Endpoint A (${REGION_A})"
if EP_A_JSON=$(gcloud compute forwarding-rules describe ${EP_A_NAME} \
    --project=${CONSUMER_PROJECT_ID} --region=${REGION_A} 2>/dev/null); then
  check "Endpoint A pscConnectionStatus" "ACCEPTED" \
    "$(echo "${EP_A_JSON}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("pscConnectionStatus"))' 2>/dev/null)"
  echo "  ℹ️  IP = $(echo "${EP_A_JSON}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("IPAddress"))' 2>/dev/null)"
else
  echo "  ⚠️  Endpoint A 不存在或无权限访问"
fi

# ---- 3. Endpoint B（DR 链路）----
echo ""
echo "[3/5] Consumer 侧 Endpoint B (${REGION_B})"
if EP_B_JSON=$(gcloud compute forwarding-rules describe ${EP_B_NAME} \
    --project=${CONSUMER_PROJECT_ID} --region=${REGION_B} 2>/dev/null); then
  check "Endpoint B pscConnectionStatus" "ACCEPTED" \
    "$(echo "${EP_B_JSON}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("pscConnectionStatus"))' 2>/dev/null)"
  check "Endpoint B allowPscGlobalAccess" "True" \
    "$(echo "${EP_B_JSON}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("allowPscGlobalAccess"))' 2>/dev/null)"
  EP_B_IP=$(echo "${EP_B_JSON}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("IPAddress"))' 2>/dev/null)
  echo "  ℹ️  IP = ${EP_B_IP}"

  # 出站防火墙规则
  if gcloud compute firewall-rules describe allow-sql-psc-dr-egress \
      --project=${CONSUMER_PROJECT_ID} --format="value(destinationRanges)" 2>/dev/null | grep -q "${EP_B_IP}"; then
    echo "  ✅ 出站防火墙规则已覆盖 Endpoint B IP"
    PASS=$((PASS+1))
  else
    echo "  ⚠️  未找到覆盖 Endpoint B IP 的出站防火墙规则（Dataplane V2 另需 NetworkPolicy）"
  fi
else
  echo "  ❌ Endpoint B 不存在"
  FAIL=$((FAIL+1))
  EP_B_IP=""
fi

# ---- 4. 复制状态 ----
echo ""
echo "[4/5] 复制状态"
if [[ "${SQL_B}" == *"replica"* || "${SQL_B}" != "" ]]; then
  MASTER=$(gcloud sql instances describe ${SQL_B} --project=${PRODUCER_PROJECT_ID} \
    --format="value(masterInstanceName)" 2>/dev/null || echo "")
  if [[ -n "${MASTER}" ]]; then
    echo "  ℹ️  ${SQL_B} 是 ${MASTER} 的副本"
    LAG=$(gcloud monitoring time-series list \
      --project=${PRODUCER_PROJECT_ID} \
      --filter="metric.type=\"cloudsql.googleapis.com/database/replication/replication_lag\" AND resource.labels.database_id=\"${SQL_B}\"" \
      --format="value(points[0].value)" 2>/dev/null | head -1)
    if [[ -n "${LAG}" ]]; then
      echo "  ℹ️  replication lag = ${LAG} 秒"
      if (( $(echo "${LAG} < 5" | bc -l 2>/dev/null || echo 1) )); then
        echo "  ✅ 复制延迟在可接受范围 (< 5s)"
        PASS=$((PASS+1))
      else
        echo "  ⚠️  复制延迟偏大，failover 会丢更多数据"
      fi
    else
      echo "  ⚠️  取不到 replication lag（可能未开启 Monitoring 或还没开始复制）"
    fi
  else
    echo "  ℹ️  ${SQL_B} 已是独立实例（promote 之后的状态），不再是副本"
  fi
fi

# ---- 5. 连通性（可选）----
echo ""
echo "[5/5] 连通性测试（可选，需要指定 TEST_TARGET）"
if [[ -n "${TEST_TARGET:-}" ]]; then
  if command -v nc >/dev/null 2>&1; then
    if nc -zv -w 5 ${TEST_TARGET} ${DB_PORT} 2>&1 | grep -q "succeeded\|open"; then
      echo "  ✅ TCP ${TEST_TARGET}:${DB_PORT} 可达"
      PASS=$((PASS+1))
    else
      echo "  ❌ TCP ${TEST_TARGET}:${DB_PORT} 不可达"
      FAIL=$((FAIL+1))
    fi
  else
    echo "  ⚠️  未找到 nc 命令，跳过"
  fi
else
  echo "  ℹ️  设置 TEST_TARGET=<Endpoint B IP> 后重跑可执行 TCP 连通性测试"
  echo "     例如：TEST_TARGET=${EP_B_IP:-<ep-b-ip>} ./verify-dr-psc.sh"
fi

echo ""
echo "=============================================="
echo " 通过 ${PASS} 项，失败 ${FAIL} 项"
echo "=============================================="
[[ ${FAIL} -eq 0 ]] || exit 1
