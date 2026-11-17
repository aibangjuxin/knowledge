#!/opt/homebrew/bin/bash
# =============================================================================
# ci-validate.sh - UCP 仓库 PR 门禁
#
# 对应 next-steps-roadmap.md 5 节的 CI 环节。纯静态检查，不需要集群。
# 退出码 0 = 通过; 1 = 有阻断项。
#
# 用法:
#   ./ci-validate.sh                # 默认检查 ../manifests
#   ./ci-validate.sh <目录>         # 检查指定目录
#   ./ci-validate.sh --strict       # 把 WARN 也视为失败
#
# 可选依赖 (缺了会自动降级并在结果里说明):
#   python3 + PyYAML -> YAML 语法检查
#   kubeconform      -> CRD schema 校验
#   crossplane CLI   -> Composition 渲染检查
# =============================================================================

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")/manifests
STRICT=0
for a in "$@"; do
  if [ "$a" = "--strict" ]; then STRICT=1; continue; fi
  if [ -d "$a" ]; then ROOT="$a"; fi
done

if [ ! -d "$ROOT" ]; then
  printf '目录不存在: %s\n' "$ROOT" >&2
  printf '(还没建 manifests 目录时这是预期的; 先按 next-steps-roadmap.md 4.1 节建目录树)\n' >&2
  exit 0
fi

PASS=0; FAIL=0; WARN=0
if [ -t 1 ]; then
  C_RED=$(printf '\033[31m'); C_GRN=$(printf '\033[32m')
  C_YEL=$(printf '\033[33m'); C_CYN=$(printf '\033[36m'); C_RST=$(printf '\033[0m')
else
  C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""; C_RST=""
fi

ok()   { PASS=$((PASS+1)); printf '%s[PASS]%s %s\n' "$C_GRN" "$C_RST" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RST" "$1"; }
warn() { WARN=$((WARN+1)); printf '%s[WARN]%s %s\n' "$C_YEL" "$C_RST" "$1"; }
info() { printf '%s       %s%s\n' "$C_CYN" "$1" "$C_RST"; }
head1(){ printf '\n%s== %s ==%s\n' "$C_CYN" "$1" "$C_RST"; }

YAMLS=$(find "$ROOT" -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)
if [ -z "$YAMLS" ]; then
  warn "$ROOT 下没有 YAML 文件"
fi

head1 "1. YAML 语法"
YAMLTOOL=""
if python3 -c 'import yaml' >/dev/null 2>&1; then
  YAMLTOOL="py"
elif command -v yq >/dev/null 2>&1; then
  YAMLTOOL="yq"
fi
if [ -z "$YAMLTOOL" ]; then
  warn "没有 PyYAML 也没有 yq, 跳过 YAML 语法检查 (pip3 install pyyaml 或 brew install yq)"
else
  NBAD=0
  for f in $YAMLS; do
    if [ "$YAMLTOOL" = "py" ]; then
      python3 -c 'import sys,yaml; list(yaml.safe_load_all(open(sys.argv[1])))' "$f" >/dev/null 2>&1 && continue
    else
      yq eval-all '.' "$f" >/dev/null 2>&1 && continue
    fi
    bad "YAML 语法错误: ${f#$ROOT/}"
    NBAD=$((NBAD+1))
  done
  if [ "$NBAD" = "0" ]; then
    ok "全部 YAML 可解析"
  fi
fi

head1 "2. 版本固定 (禁止 latest)"
LATEST=$(grep -rnE '(image:|package:)[[:space:]]*[^[:space:]]*:[Ll][Aa][Tt][Ee][Ss][Tt]' $YAMLS 2>/dev/null || true)
if [ -n "$LATEST" ]; then
  bad "发现 latest 引用:"
  printf '%s\n' "$LATEST" | sed 's/^/       /'
else
  ok "没有 latest 引用"
fi

head1 "3. ArgoCD 只同步 XR (teams/ 下禁止出现 MR 与平台组件)"
FORBIDDEN="ManagedResource Composition Provider ProviderConfig ClusterProviderConfig ManagedResourceActivationPolicy"
FOUND=""
for f in $YAMLS; do
  case "$f" in */teams/*) ;; *) continue ;; esac
  for k in $(grep -hE '^kind:' "$f" 2>/dev/null | awk '{print $2}'); do
    case " $FORBIDDEN " in
      *" $k "*) FOUND="$FOUND${f#$ROOT/}: $k"$'\n' ;;
    esac
  done
done
if [ -n "$FOUND" ]; then
  bad "teams/ 下出现不该由团队提交的资源 (MR 与平台组件由平台侧管理, 否则与 Composition 争所有权):"
  printf '%s' "$FOUND" | sed 's/^/       /'
else
  ok "teams/ 下只有 XR 类资源"
fi

head1 "4. 命名一致性 (目录名 = ApplicationSet namespace = 该团队的 AppProject 允许名单)"
if [ -d "$ROOT/teams" ]; then
  for d in "$ROOT"/teams/*/*/; do
    [ -d "$d" ] || continue
    TEAM=$(basename "$(dirname "$d")")
    DIRNAME=$(basename "$d")
    HASNS=0
    if grep -q "$DIRNAME" "$d"/*.yaml 2>/dev/null; then HASNS=1; fi
    if grep -rq "path.basename" "$ROOT"/teams/*/applicationset.yaml 2>/dev/null; then HASNS=1; fi
    if [ "$HASNS" = "1" ]; then
      ok "$DIRNAME: 与 ApplicationSet 模板绑定"
    else
      warn "$DIRNAME: 未找到 namespace 绑定, 请人工确认"
    fi
  done
  for d in "$ROOT"/teams/*/*/; do
    [ -d "$d" ] || continue
    TEAM=$(basename "$(dirname "$d")")
    DIRNAME=$(basename "$d")
    P="$ROOT/argocd/appproject-$TEAM.yaml"
    if [ ! -f "$P" ]; then
      for cand in "$ROOT"/argocd/*appproject*.yaml; do
        [ -f "$cand" ] || continue
        if grep -q "name: $TEAM" "$cand"; then P="$cand"; fi
      done
    fi
    if [ ! -f "$P" ]; then
      bad "$TEAM/$DIRNAME: 找不到 AppProject ($ROOT/argocd/appproject-$TEAM.yaml)"
      continue
    fi
    AP=$(sed -n 's/.*namespace:[[:space:]]*\([A-Za-z0-9_.-]*\).*/\1/p' "$P" | tr '\n' ' ')
    case " $AP " in
      *" $DIRNAME "*) ok "$TEAM/$DIRNAME: 在 AppProject 允许名单内" ;;
      *) bad "$TEAM/$DIRNAME: AppProject 未放行该 namespace (同步会被拒). 允许名单: $AP" ;;
    esac
  done
else
  warn "没有 teams/ 目录, 跳过命名一致性检查"
fi

head1 "5. kubeconform schema 校验 (可选)"
if command -v kubeconform >/dev/null 2>&1; then
  if kubeconform -summary -ignore-missing-schemas $YAMLS >/dev/null 2>&1; then
    ok "kubeconform 通过"
  else
    bad "kubeconform 未通过"
    kubeconform -summary -ignore-missing-schemas $YAMLS 2>&1 | tail -5 | sed 's/^/       /'
  fi
else
  warn "未安装 kubeconform, 跳过. 注意: CRD schema 位置配错会让校验假通过, 必须用反例验证"
fi

head1 "6. crossplane render 渲染检查 (可选)"
if command -v crossplane >/dev/null 2>&1; then
  COMPS=$(find "$ROOT/platform/compositions" -name '*.yaml' 2>/dev/null)
  XRS=$(find "$ROOT/teams" -name '*.yaml' 2>/dev/null)
  if [ -z "$COMPS" ] || [ -z "$XRS" ]; then
    warn "缺少 compositions 或 teams 下的 XR, 跳过渲染检查"
  else
    for xr in $XRS; do
      for c in $COMPS; do
        if crossplane render "$xr" "$c" >/dev/null 2>&1; then
          ok "render OK: ${xr#$ROOT/} + $(basename "$c")"
        else
          bad "render 失败: ${xr#$ROOT/} + $(basename "$c")"
        fi
      done
    done
  fi
else
  warn "未安装 crossplane CLI, 跳过渲染检查"
fi

head1 "汇总"
printf 'PASS=%s  FAIL=%s  WARN=%s\n' "$PASS" "$FAIL" "$WARN"
if [ "$FAIL" -gt 0 ]; then
  printf '%s结论: 未通过%s\n' "$C_RED" "$C_RST"
  exit 1
fi
if [ "$STRICT" = "1" ] && [ "$WARN" -gt 0 ]; then
  printf '%s结论: 未通过 (strict 模式, WARN 视为失败)%s\n' "$C_RED" "$C_RST"
  exit 1
fi
printf '%s结论: 通过%s\n' "$C_GRN" "$C_RST"
exit 0
