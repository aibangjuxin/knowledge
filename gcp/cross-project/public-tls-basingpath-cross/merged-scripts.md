# Shell Scripts Collection

Generated on: 2026-08-16 16:59:29
Directory: /Users/lex/git/gcp/ingress/public-tls-basingpath-cross

## `verify-backend-service-type.sh`

```bash
#!/usr/bin/env bash
# verify-backend-service-type.sh — 零参数验证当前 GCP 工程里所有 Backend Service
# 的 loadBalancingScheme 类型,判断哪些可以直接接 PSC NEG、哪些必须先做
# Classic → Managed 原地迁移 (to.md §原地迁移详细实施)。
#
# 用途:
#   在做 to.md §原地迁移详细实施 之前,先扫一遍现网 BS 的 scheme 分布,确认哪些
#   已经 EXTERNAL_MANAGED / INTERNAL_MANAGED (✅ PSC NEG 可直挂),哪些还是 EXTERNAL
#   (Classic,❌ 必须先走 to.md §1 的 6 阶段状态机逐个灰度迁移)。
#   这是 verify-glb-type.sh 的 BS 视角对应物 —— FR 的 scheme 必须跟 BS 一致,
#   否则同一 URL Map 里无法混挂 (GCP 直接 reject)。
#
# 使用:
#   bash verify-backend-service-type.sh
#   bash verify-backend-service-type.sh --project=PROJECT_ID      # 可选,覆盖默认 project
#   bash verify-backend-service-type.sh --json                    # 输出机器可读 JSON
#
# 前置:
#   - gcloud 已登录(脚本会自动检测,token 过期会报错并提示重新登录)
#   - jq 已安装(几乎所有 macOS / 主流 Linux 都自带)
#
# 退出码:
#   0 = 所有 BS 都是 PSC-compatible (EXTERNAL_MANAGED / INTERNAL_MANAGED),可直挂 PSC NEG
#   1 = 找到 EXTERNAL (Classic) BS,PSC NEG 不可行,必须先做原地迁移
#   2 = 多种 scheme 并存 (Managed + Classic 混存),需人工判断哪个 URL Map / FR 链需要迁
#   3 = 未找到任何 Backend Service,或只找到非 PSC-compatible 类型 (INTERNAL / INTERNAL_SELF_MANAGED)
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
      sed -n '2,26p' "$0"
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

# ---------- 枚举所有 Backend Service ----------
# BS 同时存在于 global 层和 regional 层,一条 gcloud list 就能拿到全部。
# 关键判别字段: loadBalancingScheme (BS 的 type) + protocol (BS 跟 scheme 强绑定)
# + region (null = global BS,有值 = regional BS)。
#
# 6 种 scheme 的语义 (来源: docs.cloud.google.com/load-balancing/docs/backend-service
# "Backend service specifications" 表):
#   EXTERNAL_MANAGED       → Global external ALB / Regional external ALB /
#                            Cross-region internal ALB / Classic proxy NLB /
#                            Regional external proxy NLB / Regional internal proxy NLB
#                            (所有 Envoy-based proxy LB 共用)                ✅ PSC NEG ok
#   EXTERNAL                → Regional external ALB (Classic) /
#                            Regional external proxy NLB (Classic) /
#                            Internal passthrough NLB                          ❌ Classic,PSC NEG 不支持
#   EXTERNAL_PASSTHROUGH   → Regional external passthrough NLB                 ❌ Passthrough,没 BS 概念
#   INTERNAL_MANAGED        → Regional internal ALB /
#                            Global external proxy NLB /
#                            Cross-region internal proxy NLB /
#                            Global external passthrough NLB                   ✅ PSC NEG ok (内部)
#   INTERNAL                → Cloud Service Mesh (注意:不是 Classic Internal LB!)  ❌ 服务网格专用
#   INTERNAL_SELF_MANAGED   → 不在 GCP 公开表里,常见于 self-managed 部署           ⚠ 罕见
#
# 关键官方原话 (segment "Restrictions and guidance" 第 4 条):
#   "It is possible to attach EXTERNAL_MANAGED backend services to EXTERNAL
#    forwarding rules. However, EXTERNAL backend services cannot be attached
#    to EXTERNAL_MANAGED forwarding rules."
# 含义: BS scheme ≥ FR scheme 的 _MANAGED 程度即可挂,反过来不允许。
# 实操影响: PSC NEG 严格限定只能挂在 EXTERNAL_MANAGED / INTERNAL_MANAGED BS 上,
#           而且这些 BS 关联的 FR 也必须是 EXTERNAL_MANAGED (否则 PSC NEG 加载时会被拒)。

BS_ALL=$(gcloud compute backend-services list \
  --project="$PROJECT" \
  --format="json(name,region,loadBalancingScheme,protocol)" 2>/dev/null || echo "[]")

# ---------- JSON 输出(机器可读) ----------
if $JSON_MODE; then
  echo "$BS_ALL" | jq --arg project "$PROJECT" '
    [.[] | {
      name,
      scope: (if (.region // null) == null then "GLOBAL" else "REGIONAL" end),
      scheme: .loadBalancingScheme,
      protocol,
      bs_class: (
        if .loadBalancingScheme == "EXTERNAL_MANAGED" then
          (if (.region // null) == null then "A: Global external ALB / Classic proxy NLB"
           else "B: Regional external ALB / Regional proxy NLB" end)
        elif .loadBalancingScheme == "EXTERNAL" then
          (if .protocol == "TCP" or .protocol == "UDP" then "G-NLB: Classic proxy NLB / Internal passthrough NLB"
           elif .protocol == "SSL" then "G-SSL: Classic SSL Proxy LB"
           else "G-ALB: Classic Application LB" end)
        elif .loadBalancingScheme == "EXTERNAL_PASSTHROUGH" then "External passthrough NLB (no real BS, attached via target pool)"
        elif .loadBalancingScheme == "INTERNAL_MANAGED" then "I-M: Regional internal ALB / Global external proxy NLB"
        elif .loadBalancingScheme == "INTERNAL" then "INTERNAL: Cloud Service Mesh"
        elif .loadBalancingScheme == "INTERNAL_SELF_MANAGED" then "INTERNAL_SELF_MANAGED: Self-managed (rare)"
        else "OTHER: unknown scheme"
        end),
      psc_compatibility: (
        if .loadBalancingScheme == "EXTERNAL_MANAGED" then "✅ PSC NEG supported (public, requires EXTERNAL_MANAGED FR)"
        elif .loadBalancingScheme == "INTERNAL_MANAGED" then "✅ PSC NEG supported (internal, requires INTERNAL_MANAGED FR)"
        elif .loadBalancingScheme == "EXTERNAL" then "❌ DEAD END for PSC NEG — migrate to EXTERNAL_MANAGED first"
        elif .loadBalancingScheme == "EXTERNAL_PASSTHROUGH" then "❌ Passthrough — uses target pool, not BS"
        elif .loadBalancingScheme == "INTERNAL" then "❌ Cloud Service Mesh — not for PSC NEG"
        elif .loadBalancingScheme == "INTERNAL_SELF_MANAGED" then "⚠ Self-managed — PSC NEG unlikely supported"
        else "⚠ Unknown — manual check needed"
        end)
    }] as $bss
    | {
        project: $project,
        timestamp: (now | todate),
        total: ($bss | length),
        psc_ready_count: ([$bss[] | select(.psc_compatibility | startswith("✅"))] | length),
        classic_count: ([$bss[] | select(.scheme == "EXTERNAL")] | length),
        other_count: ([$bss[] | select(.scheme != "EXTERNAL_MANAGED" and .scheme != "INTERNAL_MANAGED" and .scheme != "EXTERNAL")] | length),
        backend_services: $bss
      }'
  exit 0
fi

# ---------- 人读输出 ----------
echo -e "${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} Backend Service type verification for project: ${BLUE}${PROJECT}${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo ""

BS_COUNT=$(echo "$BS_ALL" | jq 'length')

if [[ "$BS_COUNT" == "0" ]]; then
  echo -e "${YELLOW}⚠ No Backend Service found in project '$PROJECT'.${NC}"
  echo ""
  echo "This means either:"
  echo "  - No LB has been created in this project yet"
  echo "  - Backend services live in another project (use --project=OTHER_PROJ to check)"
  exit 3
fi

# 打印概览表(让人 1 秒看到每个 BS 的类型 + 是否能接 PSC NEG)
echo -e "${BOLD}Backend Services:${NC}"
echo ""
echo "$BS_ALL" | jq -r '
  "name\tscope\tprotocol\tscheme\tBS class\tPSC verdict",
  (.[] | [
    .name,
    (if (.region | type) == "null" then "GLOBAL" else "REGIONAL" end),
    (.protocol // "—"),
    .loadBalancingScheme,
    (
      if .loadBalancingScheme == "EXTERNAL_MANAGED" then
        (if (.region | type) == "null" then "A: Global external ALB / proxy NLB" else "B: Regional external ALB / proxy NLB" end)
      elif .loadBalancingScheme == "EXTERNAL" then
        (if .protocol == "TCP" or .protocol == "UDP" then "Classic NLB / Internal passthrough"
         elif .protocol == "SSL" then "G-SSL: Classic SSL Proxy LB"
         else "G-ALB: Classic Application LB" end)
      elif .loadBalancingScheme == "EXTERNAL_PASSTHROUGH" then "External passthrough NLB"
      elif .loadBalancingScheme == "INTERNAL_MANAGED" then "I-M: Internal ALB / proxy NLB"
      elif .loadBalancingScheme == "INTERNAL" then "INTERNAL: Cloud Service Mesh"
      elif .loadBalancingScheme == "INTERNAL_SELF_MANAGED" then "INTERNAL_SELF_MANAGED"
      else "OTHER"
      end
    ),
    (
      if .loadBalancingScheme == "EXTERNAL_MANAGED" then "✅ PSC NEG (public)"
      elif .loadBalancingScheme == "INTERNAL_MANAGED" then "✅ PSC NEG (internal)"
      elif .loadBalancingScheme == "EXTERNAL" then "❌ DEAD END — migrate"
      elif .loadBalancingScheme == "EXTERNAL_PASSTHROUGH" then "❌ Passthrough — no BS"
      elif .loadBalancingScheme == "INTERNAL" then "❌ Service Mesh"
      elif .loadBalancingScheme == "INTERNAL_SELF_MANAGED" then "⚠ Self-managed"
      else "⚠ Unknown"
      end
    )
  ] | @tsv)
' | while IFS=$'\t' read -r name scope protocol scheme bsclass verdict; do
    echo "  $name  $scope  $protocol  $scheme  $bsclass  $verdict"
  done

echo ""

# ---------- 分类统计 ----------
declare -a CLASSIC_BS=()
declare -a MANAGED_BS=()
declare -a OTHER_BS=()

while IFS= read -r bs_json; do
  [[ -z "$bs_json" ]] && continue
  name=$(echo "$bs_json" | jq -r '.name')
  scheme=$(echo "$bs_json" | jq -r '.loadBalancingScheme')
  scope=$(echo "$bs_json" | jq -r 'if (.region | type) == "null" then "GLOBAL" else "REGIONAL" end')
  case "$scheme" in
    EXTERNAL_MANAGED|INTERNAL_MANAGED)
      MANAGED_BS+=("$name ($scope)")
      ;;
    EXTERNAL)
      CLASSIC_BS+=("$name ($scope)")
      ;;
    *)
      OTHER_BS+=("$name ($scope, scheme=$scheme)")
      ;;
  esac
done < <(echo "$BS_ALL" | jq -c '.[]')

# ---------- 最终 verdict ----------
echo -e "${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} VERDICT for project: ${BLUE}${PROJECT}${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Total BS:        ${BOLD}$BS_COUNT${NC}"
echo -e "  Managed (✅):    ${GREEN}${#MANAGED_BS[@]}${NC}  ${MANAGED_BS[*]:-(none)}"
echo -e "  Classic (❌):    ${RED}${#CLASSIC_BS[@]}${NC}  ${CLASSIC_BS[*]:-(none)}"
echo -e "  Other   (⚠):     ${YELLOW}${#OTHER_BS[@]}${NC}  ${OTHER_BS[*]:-(none)}"
echo ""

# 全部 Managed → exit 0
if [[ ${#CLASSIC_BS[@]} -eq 0 && ${#OTHER_BS[@]} -eq 0 ]]; then
  echo -e "${GREEN}✅ PASS: All backend services are PSC-compatible (EXTERNAL_MANAGED / INTERNAL_MANAGED)${NC}"
  echo ""
  echo -e "  ${BOLD}What you can do now${NC}:"
  echo "  1. Run verify-glb-type.sh to confirm the forwarding rule / URL Map"
  echo "     is also EXTERNAL_MANAGED (BS 跟 FR 的 scheme 必须一致)。"
  echo "  2. 把 PSC NEG 挂到目标 BS:"
  echo "       gcloud compute backend-services add-backend <BS_NAME> \\"
  echo "         --global \\"
  echo "         --network-endpoint-group=<PSC_NEG_NAME> \\"
  echo "         --network-endpoint-group-zone=<ZONE> \\"
  echo "         --balancing-mode=RATE \\"
  echo "         --max-rate-per-endpoint=100"
  echo ""
  echo -e "  ${BOLD}Reference${NC}:"
  echo "  - to.md §原地迁移详细实施 (LB 视角,本脚本是它的 BS 视角前置检查)"
  echo "  - baseing-path-cross-project.md §3 (A-side install 计划)"
  echo ""
  exit 0

# 只有 Classic → exit 1
elif [[ ${#CLASSIC_BS[@]} -gt 0 && ${#OTHER_BS[@]} -eq 0 ]]; then
  echo -e "${RED}❌ CRITICAL: Found Classic Backend Service(s) — PSC NEG NOT SUPPORTED${NC}"
  echo ""
  echo -e "  Classic BS (loadBalancingScheme=EXTERNAL): ${RED}${CLASSIC_BS[*]}${NC}"
  echo ""
  echo -e "  ${BOLD}Why this matters${NC}:"
  echo "  - Classic BS 不支持 PSC NEG backend (Google 官方硬限制)。"
  echo "  - 同一条 LB chain 里 BS 跟 FR 的 scheme 必须一致:Classic chain 全 EXTERNAL,"
  echo "    GEML chain 全 EXTERNAL_MANAGED。GCP 会在 create/update 时直接 reject"
  echo "    '同一 URL Map 混挂两种 scheme' 的形态。"
  echo ""
  echo -e "  ${YELLOW}⚠ 必走路径 (to.md §原地迁移详细实施 §1):${NC}"
  echo "    1. 逐个 BS 走 6 阶段状态机:"
  echo "         PREPARE → TEST_BY_PERCENTAGE → TEST_ALL_TRAFFIC → EXTERNAL_MANAGED"
  echo "       (每次状态变更至少等 6 分钟,小流量先 10% → 50% → 100%)"
  echo "    2. 如果有 backend bucket,单独迁移"
  echo "    3. 最后才能切 forwarding rule 的 scheme"
  echo ""
  echo -e "  ${BOLD}可观测指标 (to.md §4 验证清单)${NC}:"
  echo "    - gcloud compute backend-services get-health <BS> --global"
  echo "    - 4xx/5xx、p95/p99 延迟、Cloud Armor 命中日志"
  echo ""
  echo "  Decision options:"
  echo "    1. 做 Classic → EXTERNAL_MANAGED 原地迁移 (保留 IP + DNS,90 天内可回滚)"
  echo "    2. 走 to.md §方案 B (MIG 反代桥接,绕开 BS scheme 限制)"
  echo ""
  exit 1

# Managed + Classic 混存 → exit 2
elif [[ ${#MANAGED_BS[@]} -gt 0 && ${#CLASSIC_BS[@]} -gt 0 ]]; then
  echo -e "${YELLOW}⚠ Mixed scheme: ${#MANAGED_BS[@]} Managed + ${#CLASSIC_BS[@]} Classic — manual disambiguation needed${NC}"
  echo ""
  echo "  Likely cause: 并行的 LB chain 里只有部分 BS 做了迁移,或两条不同世代的 LB"
  echo "  chain (一条 Classic + 一条 GEML) 共存于同一工程。"
  echo ""
  echo -e "  ${BOLD}下一步${NC}:"
  echo "  - 看每个 BS 挂在哪个 URL Map / FR 下,定位到底哪条 chain 还没迁:"
  echo "      gcloud compute url-maps describe <URL_MAP_NAME> --global"
  echo "  - 找出还没迁的 Classic BS,按 to.md §1 的 6 阶段流程逐个迁移"
  echo ""
  exit 2

# 只有 Other → exit 3
else
  echo -e "${YELLOW}⚠ No PSC-compatible BS found — only INTERNAL / INTERNAL_SELF_MANAGED / other types${NC}"
  echo ""
  echo "  Either:"
  echo "  - 本工程只有 internal LB (没有 public HTTPS 入口,不能挂公网 PSC NEG)"
  echo "  - 在场的 BS 类型不能挂 LB-managed backends (e.g. INTERNAL_SELF_MANAGED)"
  echo ""
  exit 3
fi
```

## `verify-glb-type.sh`

```bash
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
```

