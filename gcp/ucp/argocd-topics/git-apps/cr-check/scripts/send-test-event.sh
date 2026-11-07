#!/usr/bin/env bash
# 发送测试 webhook 请求，验证 CR Check 的判定逻辑。
#
# 用法：
#   ./scripts/send-test-event.sh                 # 默认：CR 1234（合规，base=release/prd）
#   ./scripts/send-test-event.sh 5678            # 换成 CR 5678（Draft → R3 不通过）
#   ./scripts/send-test-event.sh 1111            # 目标环境不匹配 → R5 不通过
#   ./scripts/send-test-event.sh 9999            # 平台故障 → 系统异常，fail-closed
#   ./scripts/send-test-event.sh 1234 feature/x  # 非受管分支 → 被忽略
#
# 环境变量：
#   ADDR    服务地址，默认 http://localhost:8080
#   SECRET webhook secret（设了就自动带签名；本地默认空 = 服务端不验签）

set -euo pipefail

ADDR="${ADDR:-http://localhost:8080}"
CR_NUMBER="${1:-1234}"
BASE_REF="${2:-release/prd}"
SECRET="${SECRET:-}"
DELIVERY="demo-${CR_NUMBER}-$(date +%s%N)"

BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT

cat > "$BODY" <<EOF
{
  "action": "opened",
  "number": 42,
  "pull_request": {
    "number": 42,
    "title": "feat(api): 新增订单查询接口",
    "body": "Change-Request: ${CR_NUMBER}",
    "base": { "ref": "${BASE_REF}", "repo": { "full_name": "acme/platform" } },
    "head": { "sha": "a1b2c3d4e5f6789012345678901234567890abcdef" },
    "user": { "login": "alice" },
    "labels": [ { "name": "cr/${CR_NUMBER}" }, { "name": "feature" } ]
  },
  "repository": { "name": "platform", "full_name": "acme/platform", "owner": { "login": "acme" } },
  "installation": { "id": 98765432 }
}
EOF

# 签名必须对**文件原始字节**计算（与 curl --data-binary 发出的内容完全一致）
SIG_HEADER=()
if [ -n "$SECRET" ]; then
  SIG="sha256=$(openssl dgst -sha256 -hmac "$SECRET" -r < "$BODY" | cut -d' ' -f1)"
  SIG_HEADER=(-H "X-Hub-Signature-256: ${SIG}")
fi

echo "→ POST ${ADDR}/github/webhook  (CR=${CR_NUMBER}, base=${BASE_REF}, delivery=${DELIVERY}$([ -n "$SECRET" ] && echo ", signed"))"
echo

if command -v jq >/dev/null 2>&1; then
  curl -s -X POST "${ADDR}/github/webhook" \
    -H 'X-GitHub-Event: pull_request' \
    -H "X-GitHub-Delivery: ${DELIVERY}" \
    -H 'Content-Type: application/json' \
    "${SIG_HEADER[@]}" \
    --data-binary "@${BODY}" | jq
else
  curl -s -X POST "${ADDR}/github/webhook" \
    -H 'X-GitHub-Event: pull_request' \
    -H "X-GitHub-Delivery: ${DELIVERY}" \
    -H 'Content-Type: application/json' \
    "${SIG_HEADER[@]}" \
    --data-binary "@${BODY}"
fi
echo
