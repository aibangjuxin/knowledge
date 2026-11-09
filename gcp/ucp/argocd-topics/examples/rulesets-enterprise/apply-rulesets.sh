#!/usr/bin/env bash
# =============================================================================
#  apply-rulesets.sh（企业版）—— 把 rulesets-enterprise/ 里的规则下发到 GitHub
# -----------------------------------------------------------------------------
#  **它和个人版脚本的差别**
#
#    个人版：一次打一个仓库（--owner + --repo），规则基本是仓库级。
#    企业版：**组织是主控面**。一次下发 = 组织级 ruleset + 批量仓库级 ruleset，
#            而且必须**按仓库分层**（生产仓库比普通仓库严）。
#
#  它做六件事：
#
#    ① 从 enterprise-profile.yaml 读 org 名 / App ID / 仓库分层（不手填）
#    ② 静态校验（E1–E15）—— 不通过就拒绝下发（企业版一次错 = 全组织卡死）
#    ③ 逐文件判定 scope（org / repo），org 级打 orgs/<org>，repo 级打 repos/...
#    ④ 按分层批量枚举仓库 → 仓库级 ruleset 逐仓库下发
#    ⑤ 用 profile.crCheck.appId 覆盖 integration_id（占位符 → 真 ID）
#    ⑥ 同名已存在 → UPDATE；不存在 → CREATE（幂等，可反复跑）
#
#  用法
#    ./apply-rulesets.sh --list                          # 看现状（org + repo）
#    ./apply-rulesets.sh --dry-run                       # 看 payload（不连 GitHub）
#    ./apply-rulesets.sh --apply --enforcement disabled   # ★ 先 disabled
#    ./apply-rulesets.sh --apply --enforcement active --only org-prod-branch-gate
#    ./apply-rulesets.sh --delete org-prod-branch-gate
#
#  权限
#    · 组织级 ruleset：**只有 org owner 能改**（这是企业版最大的组织约束）
#    · 仓库级 ruleset：仓库 admin
#    · gh：gh auth refresh -s admin:org
#
#  环境变量
#    GH_HOST   GHES 自建时填你的 host（默认 github.com）
#    GHES 时 API 基址是 https://<host>/api/v3（gh 会自动处理）
#
#  退出码：0 = 成功；1 = 失败
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="$SCRIPT_DIR/enterprise-profile.yaml"

SCOPE="all"          # all | org | repo
OWNER=""
REPO=""
REPO_PATTERN=""      # 批量：只对匹配这个模式的仓库下发（默认 = profile 里的 standard+production）
ENFORCEMENT=""       # active | disabled | evaluate
ONLY=""
DRY_RUN=0
LIST=0
APPLY=0
DELETE=""
SKIP_VALIDATE=0
INCLUDE_SANDBOX=0

usage() { sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)          SCOPE="$2"; shift 2 ;;
    --owner)          OWNER="$2"; shift 2 ;;
    --repo)           REPO="$2"; shift 2 ;;
    --repo-pattern)   REPO_PATTERN="$2"; shift 2 ;;
    --enforcement)    ENFORCEMENT="$2"; shift 2 ;;
    --only)           ONLY="$2"; shift 2 ;;
    --delete)         DELETE="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --list)           LIST=1; shift ;;
    --apply)          APPLY=1; shift ;;
    --include-sandbox) INCLUDE_SANDBOX=1; shift ;;
    --skip-validate)  SKIP_VALIDATE=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "未知参数: $1"; usage; exit 1 ;;
  esac
done

fail() { echo "✗ $*" >&2; exit 1; }
ok()   { echo "✓ $*"; }
info() { echo "  · $*"; }

# ── 从 profile 读值（yamlmin）──────────────────────────────────────────────
profile_get() {  # $1 = 点分路径，如 org.name
  python3 - "$PROFILE" "$1" <<'PY' 2>/dev/null
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), "..", "lib"))
try:
    from yamlmin import load_file
except ImportError:
    print(""); sys.exit(0)
d = load_file(sys.argv[1]) or {}
cur = d
for part in sys.argv[2].split("."):
    if not isinstance(cur, dict) or part not in cur:
        print(""); sys.exit(0)
    cur = cur[part]
if isinstance(cur, (list, tuple)):
    print("\n".join(str(x) for x in cur))
elif isinstance(cur, bool):
    print("true" if cur else "false")
elif cur is None:
    print("")
else:
    print(cur)
PY
}

[[ -f "$PROFILE" ]] || fail "找不到 $PROFILE"

ORG="$(profile_get org.name)"
[[ -n "$ORG" ]] || fail "profile 里没有 org.name"
OWNER="${OWNER:-$ORG}"
APP_ID="$(profile_get crCheck.appId)"
API_HOST="${GH_HOST:-$(profile_get org.ghHost)}"
API_HOST="${API_HOST:-github.com}"

command -v gh >/dev/null 2>&1 || fail "找不到 gh（GitHub CLI）"
# ★ --dry-run 不需要登录（它一个 API 都不调）—— 文档里承诺了"不连 GitHub"
if [[ $LIST -eq 0 && $DRY_RUN -eq 0 ]]; then
  gh auth status >/dev/null 2>&1 || fail "gh 未登录 —— 先跑 gh auth login（或 gh auth refresh -s admin:org）"
fi

GH_ARGS=(--hostname "$API_HOST")

# ── 文件级 scope 判定 ───────────────────────────────────────────────────────
scope_of() {   # 有 repository_name → 组织级
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
c=d.get("conditions") or {}
print("org" if "repository_name" in c else "repo")' "$1"
}
name_of() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("name",""))' "$1"
}
ids_of() {  # $1=endpoint $2=name —— ★ 只留纯数字 id（gh 出错时会把错误 JSON 打到 stdout）
  gh "${GH_ARGS[@]}" api "$1" --paginate --jq ".[] | select(.name == \"$2\") | .id" 2>/dev/null \
    | grep -E '^[0-9]+$' || true
}

# ── 枚举要下发仓库级 ruleset 的仓库 ────────────────────────────────────────
# ★ 返回换行分隔的仓库名（不用 mapfile / 数组 —— macOS 自带 bash 3.2 没有 mapfile）
list_target_repos() {
  local pattern="${REPO_PATTERN:-}"
  local tiers=""
  if [[ $INCLUDE_SANDBOX -eq 1 ]]; then
    tiers="$(profile_get org.repos.standard)
$(profile_get org.repos.production)
$(profile_get org.repos.sandbox)"
  else
    tiers="$(profile_get org.repos.standard)
$(profile_get org.repos.production)"
  fi
  gh "${GH_ARGS[@]}" repo list "$OWNER" --limit 500 --json name --jq '.[].name' 2>/dev/null \
    | while IFS= read -r r; do
        [[ -z "$r" ]] && continue
        if [[ -n "$pattern" ]]; then
          case "$r" in $pattern) echo "$r" ;; esac
          continue
        fi
        while IFS= read -r p; do
          [[ -z "$p" ]] && continue
          case "$r" in
            $p) echo "$r"; break ;;
          esac
        done <<< "$tiers"
      done
}

# ── --list ──────────────────────────────────────────────────────────────────
if [[ $LIST -eq 1 ]]; then
  echo "▸ 组织级 ruleset（orgs/$OWNER）"
  if org_out="$(gh "${GH_ARGS[@]}" api "orgs/$OWNER/rulesets" --paginate \
      --jq '.[] | "  \(.id)\t\(.name)\ttarget=\(.target)\tenforcement=\(.enforcement)"' 2>/dev/null)"; then
    printf '%s\n' "$org_out"
  else
    echo "  （读取失败 —— 组织级 ruleset 需要 org owner 权限）"
  fi
  echo
  echo "▸ 仓库级 ruleset（按分层枚举的仓库）"
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    out="$(gh "${GH_ARGS[@]}" api "repos/$OWNER/$r/rulesets" --paginate \
        --jq '.[] | "  \(.id)\t\(.name)\ttarget=\(.target)\tenforcement=\(.enforcement)"' 2>/dev/null)"
    [[ -n "$out" ]] && { echo "  ── $r ──"; printf '%s\n' "$out"; }
  done < <(list_target_repos)
  echo
  echo "▸ ★ 实际生效的规则聚合（权威）："
  first_repo="$(list_target_repos | head -1)"
  if [[ -z "$first_repo" ]]; then
    echo "  （没有枚举到仓库，跳过）"
    exit 0
  fi
  for br in main dev release/prod; do
    out="$(gh "${GH_ARGS[@]}" api "repos/$OWNER/$first_repo/rules/branches/$br" 2>/dev/null)"
    [[ -z "$out" ]] && continue
    echo "  ── $first_repo @ $br ──"
    printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for r in d:
    src=r.get("ruleset_source_type") or "?"
    name=r.get("ruleset_source") or ""
    rid=r.get("ruleset_id")
    typ=r.get("type")
    print(f"    [{src}] {name}  ruleset#{rid}  rule={typ}")' 2>/dev/null || echo "$out"
  done
  exit 0
fi

# ── --delete ────────────────────────────────────────────────────────────────
if [[ -n "$DELETE" ]]; then
  ids="$(ids_of "orgs/$OWNER/rulesets" "$DELETE")"
  if [[ -n "$ids" ]]; then
    for id in $ids; do
      gh "${GH_ARGS[@]}" api -X DELETE "orgs/$OWNER/rulesets/$id" >/dev/null || fail "删除 $DELETE 失败"
    done
    ok "已删除组织级 ruleset：$DELETE"
  else
    echo "  （组织级没找到 $DELETE）"
  fi
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    ids="$(ids_of "repos/$OWNER/$r/rulesets" "$DELETE")"
    for id in $ids; do
      gh "${GH_ARGS[@]}" api -X DELETE "repos/$OWNER/$r/rulesets/$id" >/dev/null || fail "删除 $DELETE 失败 ($r)"
    done
  done < <(list_target_repos)
  exit 0
fi

# ── 静态校验（企业版 E1–E15）──────────────────────────────────────────────
if [[ $SKIP_VALIDATE -eq 0 ]]; then
  # 只把校验器认识的参数传过去（其余是本脚本自己的）
  VAL_ARGS=()
  for a in "$@"; do
    case "$a" in
      --strict|--allow-placeholders) VAL_ARGS+=("$a") ;;
    esac
  done
  # ★ dry-run 只是预览 → 占位符类问题（App ID 还没填）按警告处理，
  #   否则模板状态下根本看不到 payload
  if [[ $DRY_RUN -eq 1 ]]; then
    has_ph=0
    for a in "${VAL_ARGS[@]:-}"; do [[ "$a" == "--allow-placeholders" ]] && has_ph=1; done
    [[ $has_ph -eq 0 ]] && VAL_ARGS+=(--allow-placeholders)
  fi
  echo "▸ 静态校验（E1–E15：能力 / 一致性 / 治理）…"
  if ! python3 "$SCRIPT_DIR/validate-rulesets.py" "${VAL_ARGS[@]}"; then
    fail "静态校验不过 —— 拒绝下发。修好再试（或先用 --allow-placeholders 只审模板）。"
  fi
  echo
fi

# ── 载入 ruleset 文件 ───────────────────────────────────────────────────────
FILES=()
for f in "$SCRIPT_DIR"/[0-9][0-9]-*.json; do
  [[ -e "$f" ]] || continue
  if [[ -n "$ONLY" ]] && [[ "$(name_of "$f")" != "$ONLY" ]]; then continue; fi
  FILES+=("$f")
done
[[ ${#FILES[@]} -gt 0 ]] || fail "没有找到 ruleset JSON（--only=$ONLY 没匹配上？）"

# ── payload 生成（integration_id / enforcement 覆盖）────────────────────────
render_payload() {  # $1=file → 打印 payload
  python3 - "$1" "$APP_ID" "$ENFORCEMENT" <<'PY'
import json, sys
path, app_id, enforcement = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as fh:
    d = json.load(fh)
if app_id and app_id.isdigit() and int(app_id) > 0:
    for rule in d.get("rules", []):
        if rule.get("type") == "required_status_checks":
            params = rule.setdefault("parameters", {})
            for chk in params.get("required_status_checks", []):
                chk["integration_id"] = int(app_id)
if enforcement:
    d["enforcement"] = enforcement
print(json.dumps(d, ensure_ascii=False, indent=2))
PY
}

# ── 下发一条到某个端点 ─────────────────────────────────────────────────────
upsert() {  # $1=base endpoint  $2=name  $3=payload
  local base="$1" name="$2" payload="$3"
  local existing_id
  existing_id="$(ids_of "$base" "$name" | head -1)"
  if [[ -n "$existing_id" ]]; then
    printf '%s' "$payload" | gh "${GH_ARGS[@]}" api -X PUT "$base/$existing_id" --input - >/dev/null \
      || fail "更新 $name 失败（字段名错 → 422；组织级需要 org owner → 403）"
    ok "$name 已更新 (#$existing_id)"
  else
    printf '%s' "$payload" | gh "${GH_ARGS[@]}" api -X POST "$base" --input - >/dev/null \
      || fail "创建 $name 失败（常见原因：字段名写错 → 422；scope 用错 → 404；权限不足 → 403）"
    ok "$name 已创建"
  fi
}

if [[ $DRY_RUN -eq 1 ]]; then
  for f in "${FILES[@]}"; do
    name="$(name_of "$f")"; file_scope="$(scope_of "$f")"
    if [[ "$SCOPE" != "all" && "$file_scope" != "$SCOPE" ]]; then
      info "跳过 ${f##*/}（$file_scope 级）"; continue
    fi
    echo
    echo "▸ $name  ($file_scope 级)"
    echo "--- dry-run payload ---"
    render_payload "$f"
  done
  exit 0
fi

[[ $APPLY -eq 1 ]] || fail "请显式给 --apply（或用 --dry-run 看 payload）"

# ── ① 组织级 ruleset ───────────────────────────────────────────────────────
echo "▸ 组织级 ruleset → orgs/$OWNER/rulesets"
for f in "${FILES[@]}"; do
  file_scope="$(scope_of "$f")"
  [[ "$file_scope" == "org" ]] || continue
  if [[ "$SCOPE" == "repo" ]]; then continue; fi
  name="$(name_of "$f")"
  echo
  echo "▸ $name"
  upsert "orgs/$OWNER/rulesets" "$name" "$(render_payload "$f")"
done

# ── ② 仓库级 ruleset（按分层批量）──────────────────────────────────────────
if [[ "$SCOPE" == "all" || "$SCOPE" == "repo" ]]; then
  echo
  echo "▸ 仓库级 ruleset → repos/$OWNER/<repo>/rulesets"
  repos="$(list_target_repos)"
  if [[ -z "$repos" ]]; then
    warn "没有匹配到仓库（检查 profile 的 repos 分层，或用 --repo-pattern）"
  fi
  for f in "${FILES[@]}"; do
    file_scope="$(scope_of "$f")"
    [[ "$file_scope" == "repo" ]] || continue
    name="$(name_of "$f")"
    payload="$(render_payload "$f")"
    while IFS= read -r r; do
      [[ -z "$r" ]] && continue
      echo
      echo "▸ $name → $r"
      upsert "repos/$OWNER/$r/rulesets" "$name" "$payload"
    done <<< "$repos"
  done
fi

echo
ok "全部完成"
cat <<EOF

下一步（★ 别跳过）：
  1) 确认 enforcement
     ./apply-rulesets.sh --list
  2) ★ 确认目标分支上真的聚合了这些规则（权威口径）
     gh api repos/$OWNER/<repo>/rules/branches/main | jq -r '.[] | "\\(.ruleset_source_type)\\t\\(.ruleset_source)\\t\\(.type)"'
  3) ★ 联调（唯一能证明"拦得住"的方法）
     · 在测试仓库提一个不带 CR 号的 commit → push 时 ref 必须**不更新**
     · 提一个 PR 标题不带 CR 前缀 → 必须合不了
     · 合规 PR → 能合
  4) 观察
     gh api orgs/$OWNER/rulesets --jq '.[] | "\\(.id)\\t\\(.name)\\t\\(.enforcement)"'
EOF
