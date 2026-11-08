#!/usr/bin/env bash
# =============================================================================
#  apply-rulesets.sh —— 把 examples/rulesets/ 里的规则集真正装到 GitHub 上
# -----------------------------------------------------------------------------
#  **它解决什么问题**
#  JSON 文件本身不会生效 —— 必须 POST/PUT 到 GitHub 的 ruleset API，
#  然后**验证真的生效**。这个脚本把「装 → 查 → 回滚」整条链做掉：
#
#    ① 先跑静态校验（契约 C1/C2/C3 + API 字段白名单）—— 不通过就拒绝下发
#    ② 自动判定每个 JSON 是「组织级」还是「仓库级」（看 conditions 里有没有 repository_name）
#    ③ 同名已存在 → UPDATE；不存在 → CREATE（幂等）
#    ④ 默认先建 disabled，装完联调通过再 --enforcement active
#    ⑤ --list 看现状，--delete 回滚
#
#  用法
#    # 看现状（仓库级 + 组织级）
#    ./apply-rulesets.sh --list --owner <org> --repo <repo>
#
#    # 只看将要提交的 payload（不连 GitHub）
#    ./apply-rulesets.sh --dry-run --owner <org> --repo <repo>
#
#    # 安装（★ 先 disabled）
#    CR_CHECK_APP_ID=<App ID> ./apply-rulesets.sh --owner <org> --repo <repo> \
#        --enforcement disabled
#
#    # 联调通过后打开强制
#    CR_CHECK_APP_ID=<App ID> ./apply-rulesets.sh --owner <org> --repo <repo> \
#        --enforcement active --only prod-branch-gate
#
#    # 回滚
#    ./apply-rulesets.sh --delete prod-branch-gate --owner <org> --repo <repo>
#
#  权限要求
#    · 仓库级 ruleset：对该仓库有 admin 权限
#    · 组织级 ruleset：★ 必须是组织 owner（只有 owner 能改组织级 ruleset）
#    · gh 登录：gh auth status（需要 admin:org scope → gh auth refresh -s admin:org）
#
#  环境变量
#    CR_CHECK_APP_ID   CR Check 这个 GitHub App 的 App ID。
#                      ★ 填进去后 04-repo-prod-branches.json 的 integration_id 会被替换。
#                      ★ 它就是 required_status_checks 的 "expected source"，
#                        留空 = 同名 check 可被伪造 = 门禁形同虚设。
#
#  退出码：0 = 成功；1 = 失败
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCOPE="auto"          # auto | org | repo
OWNER=""
REPO=""
ENFORCEMENT=""        # active | disabled | evaluate
ONLY=""
DRY_RUN=0
LIST=0
DELETE=""
APP_ID="${CR_CHECK_APP_ID:-}"

usage() { sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)       SCOPE="$2"; shift 2 ;;
    --owner)       OWNER="$2"; shift 2 ;;
    --repo)        REPO="$2"; shift 2 ;;
    --enforcement) ENFORCEMENT="$2"; shift 2 ;;
    --only)        ONLY="$2"; shift 2 ;;
    --delete)      DELETE="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --list)        LIST=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "未知参数: $1"; usage; exit 1 ;;
  esac
done

fail() { echo "✗ $*" >&2; exit 1; }
ok()   { echo "✓ $*"; }
info() { echo "  · $*"; }

[[ -n "$OWNER" ]] || fail "必须给 --owner"
command -v gh >/dev/null 2>&1 || fail "找不到 gh（GitHub CLI）"
if [[ $LIST -eq 0 && $DRY_RUN -eq 0 ]]; then
  gh auth status >/dev/null 2>&1 || fail "gh 未登录 —— 先跑 gh auth login（或 gh auth refresh -s admin:org）"
fi

# ── 文件级 scope 判定 ───────────────────────────────────────────────────────
# 组织级 ruleset 的 conditions 必须含 repository_name；仓库级不含。
scope_of() {
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
c=d.get("conditions") or {}
print("org" if "repository_name" in c else "repo")' "$1"
}

name_of() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("name",""))' "$1"
}

# ── --list ──────────────────────────────────────────────────────────────────
if [[ $LIST -eq 1 ]]; then
  echo "▸ 仓库级 ruleset（repos/$OWNER/$REPO）"
  if repo_out="$(gh api "repos/$OWNER/$REPO/rulesets" --paginate \
      --jq '.[] | "  \(.id)\t\(.name)\ttarget=\(.target)\tenforcement=\(.enforcement)"' 2>/dev/null)"; then
    printf '%s\n' "$repo_out"
  else
    echo "  （读取失败 —— 确认你对 $OWNER/$REPO 有 admin 权限）"
  fi
  echo
  echo "▸ 组织级 ruleset（orgs/$OWNER）"
  if org_out="$(gh api "orgs/$OWNER/rulesets" --paginate \
      --jq '.[] | "  \(.id)\t\(.name)\ttarget=\(.target)\tenforcement=\(.enforcement)"' 2>/dev/null)"; then
    printf '%s\n' "$org_out"
  else
    echo "  （读取失败 —— 组织级 ruleset 需要 org owner 权限）"
  fi
  echo
  echo "▸ ★ 实际生效的规则聚合（权威）："
  for br in main dev release/prod; do
    out="$(gh api "repos/$OWNER/$REPO/rules/branches/$br" 2>/dev/null)"
    [[ -z "$out" ]] && continue
    echo "  ── $br ──"
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
  if [[ -n "$REPO" ]]; then
    ids="$(gh api "repos/$OWNER/$REPO/rulesets" --paginate --jq ".[] | select(.name==\"$DELETE\") | .id" 2>/dev/null)"
    if [[ -n "$ids" ]]; then
      for id in $ids; do
        gh api -X DELETE "repos/$OWNER/$REPO/rulesets/$id" >/dev/null || fail "删除 $DELETE 失败"
      done
      ok "已删除仓库级 ruleset：$DELETE"
    else
      echo "  （仓库级没找到 $DELETE）"
    fi
  fi
  ids="$(gh api "orgs/$OWNER/rulesets" --paginate --jq ".[] | select(.name==\"$DELETE\") | .id" 2>/dev/null)"
  if [[ -n "$ids" ]]; then
    for id in $ids; do
      gh api -X DELETE "orgs/$OWNER/rulesets/$id" >/dev/null || fail "删除 $DELETE 失败"
    done
    ok "已删除组织级 ruleset：$DELETE"
  else
    echo "  （组织级没找到 $DELETE）"
  fi
  exit 0
fi

# ── 先跑静态断言 ────────────────────────────────────────────────────────────
echo "▸ 静态校验（契约 C1/C2/C3 + API 字段白名单）…"
if ! python3 "$SCRIPT_DIR/validate-rulesets.py"; then
  fail "静态校验不过 —— 拒绝下发。修好再试。"
fi
echo

# ── 载入 ruleset 文件 ───────────────────────────────────────────────────────
FILES=()
for f in "$SCRIPT_DIR"/[0-9][0-9]-*.json; do
  [[ -e "$f" ]] || continue
  if [[ -n "$ONLY" ]] && [[ "$(name_of "$f")" != "$ONLY" ]]; then
    continue
  fi
  FILES+=("$f")
done
[[ ${#FILES[@]} -gt 0 ]] || fail "没有找到 ruleset JSON（--only=$ONLY 没匹配上？）"

# ── 下发 ────────────────────────────────────────────────────────────────────
for f in "${FILES[@]}"; do
  name="$(name_of "$f")"
  file_scope="$(scope_of "$f")"

  # 目标 scope 判定
  if [[ "$SCOPE" != "auto" ]]; then
    if [[ "$file_scope" != "$SCOPE" ]]; then
      info "跳过 ${f##*/}（$file_scope 级；本次只装 $SCOPE 级）"
      continue
    fi
  fi
  target_scope="$file_scope"

  if [[ "$target_scope" == "repo" ]]; then
    [[ -n "$REPO" ]] || fail "$name 是仓库级 ruleset，必须给 --repo"
    base="repos/$OWNER/$REPO/rulesets"
    list_cmd=(gh api "repos/$OWNER/$REPO/rulesets")
  else
    base="orgs/$OWNER/rulesets"
    list_cmd=(gh api "orgs/$OWNER/rulesets")
  fi

  # ① 应用 integration_id 覆盖
  payload="$(cat "$f")"
  if [[ -n "$APP_ID" ]]; then
    new_payload="$(printf '%s' "$payload" | python3 -c '
import sys,re
raw = sys.stdin.read()
raw = re.sub(r"\"integration_id\":\s*\d+", "\"integration_id\": " + sys.argv[1], raw)
print(raw)' "$APP_ID")"
    if [[ "$new_payload" != "$payload" ]]; then
      payload="$new_payload"
      info "$name：integration_id → $APP_ID"
    fi
  fi

  # ② 应用 enforcement 覆盖
  if [[ -n "$ENFORCEMENT" ]]; then
    payload="$(printf '%s' "$payload" | python3 -c '
import json,sys
d = json.load(sys.stdin); d["enforcement"] = sys.argv[1]; print(json.dumps(d, indent=2))' "$ENFORCEMENT")"
  fi

  echo
  echo "▸ $name  →  $target_scope 级  →  $base"

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "--- dry-run payload ---"
    printf '%s\n' "$payload"
    continue
  fi

  # ③ 查同名 → UPDATE / CREATE
  existing_id="$("${list_cmd[@]}" --paginate --jq \
    ".[] | select(.name == \"$name\") | .id" 2>/dev/null | head -1)"

  if [[ -n "$existing_id" ]]; then
    echo "  → UPDATE ruleset #$existing_id"
    if ! printf '%s' "$payload" | gh api -X PUT "$base/$existing_id" --input - >/dev/null; then
      fail "更新 $name 失败（检查字段名与 scope；组织级 ruleset 需要 org owner）"
    fi
    ok "$name 已更新 (#$existing_id)"
  else
    echo "  → CREATE ruleset"
    if ! printf '%s' "$payload" | gh api -X POST "$base" --input - >/dev/null; then
      fail "创建 $name 失败（常见原因：字段名写错 → 422；scope 用错 → 404；权限不足 → 403）"
    fi
    ok "$name 已创建"
  fi
done

echo
ok "全部完成"
if [[ $DRY_RUN -eq 0 ]]; then
  cat <<'EOF'

下一步（★ 别跳过）：
  1) 确认 enforcement 是不是 active
     ./apply-rulesets.sh --list --owner <owner> --repo <repo>
  2) ★ 验证 C1/C2/C3 契约是否真的成立（这一步才证明门禁活了）
     · 提一个**故意不合规**的 PR（不带 CR 号）→ 必须合不了
     · 提一个**合规**的 PR（带 cr/<编号>）→ 能合
  3) 看聚合后实际生效的规则
     gh api repos/<owner>/<repo>/rules/branches/main
EOF
fi
