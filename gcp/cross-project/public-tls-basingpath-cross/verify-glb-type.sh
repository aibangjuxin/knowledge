#!/usr/bin/env bash
# verify-glb-type.sh — 零参数验证当前 GCP 工程里 GLB 的类型,判断能否做 PSC NEG
#
# 用途:
#   在 baseing-path-cross-project.md §0.3 / §2.6 / §2.7 / §8 Step 0 决策前,
#   一键确认现网 GLB 是 A 类 (Global external ALB) / B 类 (Regional external ALB)
#   / G 类 (Classic Application LB,死路) / 其他。
#
# 使用:
#   bash verify-glb-type.sh
#   bash verify-glb-type.sh --project=PROJECT_ID      # 可选,覆盖默认 project
#   bash verify-glb-type.sh --json                    # 输出机器可读 JSON
#
# 前置:
#   - gcloud 已登录(脚本会自动检测,token 过期会报错并提示重新登录)
#   - jq 已安装(几乎所有 macOS / 主流 Linux 都自带)
#
# 退出码:
#   0 = 找到 GLB 且类型合法 (A 或 B),可走 PSC NEG 方案
#   1 = 找到 GLB 但类型是 G (Classic Application LB),PSC 方案不可行
#   2 = 找到多个 GLB 但需人工判断
#   3 = 未找到任何 HTTPS LB
#   4 = 环境问题(没装 gcloud / 没装 jq / token 过期)

set -euo pipefail

# ---------- 颜色 / 符号 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- 参数解析 ----------
PROJECT=""
JSON_MODE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project=*) PROJECT="${1#*=}" ;;
    --project)   PROJECT="${2:-}"; shift ;;
    --json)      JSON_MODE=true ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: unknown flag: $1${NC}" >&2
      exit 4
      ;;
  esac
  shift
done

# ---------- 前置检查 ----------
for cmd in gcloud jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: $cmd not found in PATH${NC}" >&2
    exit 4
  fi
done

# ---------- 取 project ----------
if [[ -z "$PROJECT" ]]; then
  PROJECT=$(gcloud config get-value project 2>/dev/null | tr -d '\n' || true)
  if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
    echo -e "${RED}ERROR: no project set. Run 'gcloud config set project PROJECT_ID' or pass --project=PROJECT_ID${NC}" >&2
    exit 4
  fi
fi

# ---------- gcloud 鉴权探针(token 过期早失败) ----------
if ! gcloud auth print-access-token --project="$PROJECT" >/dev/null 2>&1; then
  echo -e "${RED}ERROR: gcloud token invalid for project '$PROJECT'. Run 'gcloud auth login' first.${NC}" >&2
  exit 4
fi

# ---------- 枚举所有 HTTPS LB 资源 ----------
# 关键:FR 的 target 字段是唯一能区分 LB 类型的标志(EXTERNAL_MANAGED vs EXTERNAL 等)。
# 这里只取 FR,Target Proxy / BS 在 FR 的 target 字段里能看到指向,不需要单独列。

FR_ALL=$(gcloud compute forwarding-rules list \
  --project="$PROJECT" \
  --format="json(name,region,loadBalancingScheme,target)" 2>/dev/null || echo "[]")

# ---------- 筛 HTTPS 入口(用 Target Proxy 反查 FR)----------
# Target HTTPS Proxy 的 target 字段指向 forwarding-rule, 但 gcloud 输出里直接给的是
# proxy name,我们通过 FR 的 target 字段(格式: .../targetHttpProxies/PROXY_NAME
# 或 .../targetHttpsProxies/PROXY_NAME) 反向链上 Proxy。
HTTPS_FRS=$(echo "$FR_ALL" | jq -r '
  .[]
  | select(.target | test("(targetHttpProxies|targetHttpsProxies)"))
  | {name, region, scheme: .loadBalancingScheme, target}
')

# 也筛 TCP proxy SSL(NLB L4,虽然不是用户场景,但保留可见)
L4_FRS=$(echo "$FR_ALL" | jq -r '
  .[]
  | select(.target | test("(targetTcpProxies|targetSslProxies)"))
  | {name, region, scheme: .loadBalancingScheme, target}
')

# ---------- 类型判定说明 ----------
# FR 的 loadBalancingScheme 字段是判定 LB type 的唯一权威来源:
#   EXTERNAL_MANAGED + region=null  → A: Global external ALB     ✅ PSC NEG ok
#   EXTERNAL_MANAGED + region=R      → B: Regional external ALB   ✅ PSC NEG ok (需 Org Policy)
#   EXTERNAL(无 _MANAGED)            → G: Classic Application LB  ❌ PSC NEG 不支持,死路
#   INTERNAL_MANAGED / INTERNAL      → 内部 LB                    ⚠ 不是公网入口
# 判定逻辑直接 inline 在输出 jq 表达式里(见下方),无需单独函数。

# ---------- 输出 ----------
if $JSON_MODE; then
  # 机器可读 JSON 输出
  echo "$FR_ALL" | jq --arg project "$PROJECT" '
    [.[] | select(.target | test("(targetHttpProxies|targetHttpsProxies)"))] as $frs
    | {
        project: $project,
        timestamp: (now | todate),
        forwarding_rules: $frs | map({
          name, region: (.region // "GLOBAL"), scheme: .loadBalancingScheme,
          type: (if .loadBalancingScheme == "EXTERNAL_MANAGED"
                 then (if (.region // null) == null then "A: Global external ALB (✅ PSC NEG supported)"
                       else "B: Regional external ALB (✅ PSC NEG supported, needs Org Policy approval)" end)
                 elif .loadBalancingScheme == "EXTERNAL" then "G: Classic ALB (❌ dead end, must migrate)"
                 elif .loadBalancingScheme == "INTERNAL_MANAGED" or .loadBalancingScheme == "INTERNAL" then "INTERNAL (not a public ingress)"
                 else "OTHER: unknown scheme" end)
        })
      }'
  exit 0
fi

# 人读输出
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} GLB type verification for project: ${BLUE}${PROJECT}${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""

# 转成 jq-friendly array
FR_COUNT=$(echo "$HTTPS_FRS" | jq -s 'length')
L4_COUNT=$(echo "$L4_FRS" | jq -s 'length')

if [[ "$FR_COUNT" == "0" && "$L4_COUNT" == "0" ]]; then
  echo -e "${YELLOW}⚠ No HTTPS / SSL LB found in project '$PROJECT'.${NC}"
  echo ""
  echo "This means either:"
  echo "  - No GLB has been created yet"
  echo "  - LB is in another project (use --project=OTHER_PROJ to check)"
  exit 3
fi

declare -a CLASSIC_FRS=()
declare -a AB_FRS=()
declare -a INTERNAL_FRS=()

# 打印 L7 HTTPS FR 概览表(让人 1 秒看到类型)
echo -e "${BOLD}HTTPS L7 Forwarding Rules (LB entry points):${NC}"
echo ""
if [[ "$FR_COUNT" == "0" ]]; then
  echo "  (none — no Target HTTPS Proxy LB found)"
else
  echo "$HTTPS_FRS" | jq -rs '
    "name\tregion\tscheme\tLB type\tverdict",
    (.[] | [.name, (if (.region | type) == "null" then "GLOBAL" else .region end), .scheme,
      (if .scheme == "EXTERNAL_MANAGED"
       then (if (.region | type) == "null" then "A: Global external ALB" else "B: Regional external ALB" end)
       elif .scheme == "EXTERNAL" then "G: Classic ALB"
       elif .scheme == "INTERNAL_MANAGED" or .scheme == "INTERNAL" then "INTERNAL LB"
       else "OTHER" end),
      (if .scheme == "EXTERNAL_MANAGED" then "✅ PSC NEG supported"
       elif .scheme == "EXTERNAL" then "❌ DEAD END — must migrate to A/B"
       elif .scheme == "INTERNAL_MANAGED" or .scheme == "INTERNAL" then "⚠ Internal LB — not a public ingress"
       else "⚠ Unknown — manual check needed" end)
    ] | @tsv)
  ' | while IFS=$'\t' read -r name region scheme lbtag verdict; do
      echo "  $name  $region  $scheme  $lbtag  $verdict"
    done
fi

echo ""

while IFS= read -r fr_json; do
  [[ -z "$fr_json" ]] && continue
  name=$(echo "$fr_json" | jq -r '.name')
  region=$(echo "$fr_json" | jq -r 'if (.region | type) == "null" then "" else .region end')
  scheme=$(echo "$fr_json" | jq -r '.scheme')
  case "$scheme" in
    EXTERNAL_MANAGED)
      if [[ -z "$region" ]]; then
        AB_FRS+=("$name (A: Global)")
      else
        AB_FRS+=("$name (B: Regional)")
      fi
      ;;
    EXTERNAL)
      CLASSIC_FRS+=("$name")
      ;;
    INTERNAL*)
      INTERNAL_FRS+=("$name")
      ;;
  esac
done < <(echo "$HTTPS_FRS" | jq -c '.')

# ---------- 最终 verdict ----------
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} VERDICT for project: ${BLUE}${PROJECT}${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""

if [[ ${#CLASSIC_FRS[@]} -gt 0 ]]; then
  echo -e "${RED}❌ CRITICAL: Found Classic Application LB(s) — PSC NEG NOT SUPPORTED${NC}"
  echo ""
  echo -e "  Classic LB forwarding rule(s): ${RED}${CLASSIC_FRS[*]}${NC}"
  echo ""
  echo -e "  ${BOLD}What this means:${NC}"
  echo "  - Classic ALB (loadBalancingScheme=EXTERNAL, no _MANAGED) does NOT support"
  echo "    Private Service Connect NEG backends (Google official restriction)."
  echo "  - To use the path-rule → cross-project PSC NEG design, you must migrate"
  echo "    this LB to either:"
  echo "      (a) A: Global external ALB (loadBalancingScheme=EXTERNAL_MANAGED --global)"
  echo "      (b) B: Regional external ALB (loadBalancingScheme=EXTERNAL_MANAGED --region=R)"
  echo ""
  echo -e "  ${YELLOW}⚠ Migration will break the hard constraint 'entry IP cannot change'${NC}"
  echo "    because Global/Regional external ALBs allocate a NEW external IP."
  echo ""
  echo "  Decision options:"
  echo "    1. Accept the IP change (DNS A-record update on www.caep.uk)"
  echo "    2. Choose a non-PSC cross-project design (but you lose URL Map path-rule ability)"
  echo "    3. Use the existing Classic LB ONLY for the default path, and create a parallel"
  echo "       A/B GLB just for /apiname1/* and /apiname2/* (two GLBs, two IPs in DNS)"
  echo ""
  exit 1

elif [[ ${#AB_FRS[@]} -eq 1 ]]; then
  echo -e "${GREEN}✅ PASS: Found exactly 1 A/B-class HTTPS GLB — path-rule → PSC NEG design works${NC}"
  echo ""
  echo -e "  Forwarding rule: ${GREEN}${AB_FRS[0]}${NC}"
  echo ""
  echo -e "  ${BOLD}Next steps${NC}:"
  echo "  1. Note this FR name for downstream install scripts (online-consume.sh family)"
  echo "  2. Read /Users/lex/git/gcp/ingress/public-tls-basingpath-cross/baseing-path-cross-project.md"
  echo "     §3 for the A-side install plan"
  echo "  3. Verify B-side ILB + SA + MIG nginx per /Users/lex/git/knowledge/cloud/k8s/k8s-gateway/"
  echo "     public-fqdn-explorer.md §3"
  echo ""
  exit 0

elif [[ ${#AB_FRS[@]} -gt 1 ]]; then
  echo -e "${YELLOW}⚠ Found ${#AB_FRS[@]} A/B-class HTTPS GLBs — manual disambiguation needed${NC}"
  echo ""
  for fr in "${AB_FRS[@]}"; do
    echo "  - $fr"
  done
  echo ""
  echo "Multiple GLBs may be intentional (e.g., IDMZ + cinternal parallel LB chains"
  echo "documented in tenant-tls-setup-idmz-https.md). Decide which one(s) carry the"
  echo "www.caep.uk traffic, then re-run with --project=... if you want a single-project"
  echo "narrowed check."
  echo ""
  exit 2

elif [[ ${#INTERNAL_FRS[@]} -gt 0 ]]; then
  echo -e "${YELLOW}⚠ Found only INTERNAL LB(s) — not a public ingress${NC}"
  echo ""
  echo "  INTERNAL LB(s): ${INTERNAL_FRS[*]}"
  echo ""
  echo "  An internal LB cannot serve public HTTPS traffic. The www.caep.uk ingress"
  echo "  must be on an external LB. Either you don't have a public GLB yet (need to"
  echo "  create one), or your public GLB is in another project."
  echo ""
  exit 3

else
  echo -e "${YELLOW}⚠ No HTTPS GLB found — only L4 (TCP/SSL) LB(s):${NC}"
  echo ""
  echo "$L4_FRS" | jq -r '.[] | "  - \(.name) (\(.scheme))"' | while read -r line; do
    echo "  $line"
  done
  echo ""
  echo "  L4 (proxy NLB) supports PSC NEG but cannot do URL Map path-rule routing."
  echo "  You need an L7 HTTPS LB (A/B/G class) for the path-rule → PSC design."
  echo ""
  exit 3
fi