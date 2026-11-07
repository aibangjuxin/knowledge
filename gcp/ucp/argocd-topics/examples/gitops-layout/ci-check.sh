#!/usr/bin/env bash
# =============================================================================
#  ci-check.sh —— 一键跑完全部静态检查（提交前 / CI 入口）
# -----------------------------------------------------------------------------
#  这个仓库里现在有 8 个检查工具。它们各自负责一件事，但**要一起跑**才对：
#
#    ① validate-examples.py    examples/ 里的静态配置片段有没有危险默认值
#    ② validate-clusters.py    集群清单字段有没有漂移
#    ③ preview-appset.py       看看会生成哪些 Application（人看的矩阵）
#    ④ appset-simulator.py     精确模拟 + 交叉校验（project/destination/重名）
#    ⑤ render-check.py         每个 overlay 能不能 build、产物对不对
#    ⑥ kubectl kustomize       根应用能不能 build
#    ⑦ check-doc-links.py      文档里的链接还能不能跳
#    ⑧ YAML 语法               所有 yaml 能不能解析
#
#  用法：
#    ./ci-check.sh              # 跑全部
#    ./ci-check.sh --quick      # 跳过需要 kubectl 的（③④⑤⑥）
#    ./ci-check.sh --fix-hints  # 打印每项失败后该怎么修
#
#  退出码：0 = 全过；1 = 有检查失败。
#
#  兼容：macOS / Linux（bash 3.2+）
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TOPICS_DIR="$(cd "$EXAMPLES_DIR/.." && pwd)"

QUICK=0
SHOW_HINTS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    --fix-hints) SHOW_HINTS=1; shift ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

if [[ -t 1 ]]; then C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_RED=$'\033[31m'; C_BLU=$'\033[34m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else C_GRN=""; C_YEL=""; C_RED=""; C_BLU=""; C_BLD=""; C_RST=""; fi

PASSED=0
FAILED=0
FAILED_NAMES=()

hr()   { printf '%s\n' "────────────────────────────────────────────────────────────────"; }
head2() { printf '\n%s%s%s\n' "$C_BLD" "$1" "$C_RST"; }

# run_check <名称> <说明> <命令...>
run_check() {
  local name="$1"; shift
  local desc="$1"; shift
  printf '%s▸ %-26s%s %s\n' "$C_BLU" "$name" "$C_RST" "$desc"
  local out
  if out="$("$@" 2>&1)"; then
    printf '  %s✓ 通过%s\n' "$C_GRN" "$C_RST"
    PASSED=$((PASSED + 1))
  else
    printf '  %s✗ 失败%s\n' "$C_RED" "$C_RST"
    printf '%s\n' "$out" | sed 's/^/      /' | head -40
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$name")
  fi
}

# skip_check <名称> <原因>
skip_check() {
  printf '%s▸ %-26s%s 跳过（%s）\n' "$C_BLU" "$1" "$C_RST" "$2"
}

head2 "静态检查 · gitops-layout"
hr

run_check "validate-clusters" "集群清单字段一致性" \
  python3 "$SCRIPT_DIR/validate-clusters.py"

run_check "appset-simulator" "AppSet 精确模拟 + 交叉校验" \
  python3 "$SCRIPT_DIR/appset-simulator.py"

if [[ $QUICK -eq 0 ]]; then
  if command -v kubectl >/dev/null 2>&1; then
    run_check "render-check" "所有 overlay 渲染 + 产物策略" \
      python3 "$SCRIPT_DIR/render-check.py"

    run_check "kustomize bootstrap" "根应用能 build" \
      kubectl kustomize "$SCRIPT_DIR/bootstrap"
  else
    skip_check "render-check" "没有 kubectl"
    skip_check "kustomize bootstrap" "没有 kubectl"
  fi
else
  skip_check "render-check" "--quick"
  skip_check "kustomize bootstrap" "--quick"
fi

head2 "预览（人看）"
hr
python3 "$SCRIPT_DIR/preview-appset.py" 2>&1 | tail -12

head2 "静态检查 · examples 根目录"
hr

run_check "validate-examples" "配置片段的危险默认值" \
  python3 "$EXAMPLES_DIR/validate-examples.py"

run_check "check-doc-links" "文档链接与锚点" \
  python3 "$EXAMPLES_DIR/check-doc-links.py"

head2 "YAML 语法"
hr
# 用 yamlmin 逐个解析（零依赖，不依赖 PyYAML）
yaml_bad="$(python3 - "$TOPICS_DIR" <<'PYEOF'
import os, sys
root = sys.argv[1]
lib = os.path.join(root, "examples", "lib")
if not os.path.isdir(lib):
    sys.stderr.write(f"找不到 {lib} —— 请在 argocd-topics/ 目录下运行\n")
    print("ERR")
    raise SystemExit(0)
sys.path.insert(0, lib)
import yamlmin
bad = 0
for base, dirs, files in os.walk(root):
    dirs[:] = [d for d in dirs if d not in (".git", "node_modules")]
    for name in files:
        if not name.endswith((".yaml", ".yml")):
            continue
        path = os.path.join(base, name)
        try:
            yamlmin.load_all_files(path)
        except Exception as exc:
            bad += 1
            print(f"  {os.path.relpath(path, root)}: {exc}", file=sys.stderr)
print(bad)
PYEOF
)"
yaml_total="$(find "$TOPICS_DIR" -name '*.yaml' -o -name '*.yml' 2>/dev/null | grep -v '/.git/' | wc -l | tr -d ' ')"
if [[ "$yaml_bad" == "0" ]]; then
  printf '%s✓ 通过%s  %s 个 YAML 全部可解析\n' "$C_GRN" "$C_RST" "$yaml_total"
  PASSED=$((PASSED + 1))
elif [[ -z "$yaml_bad" || "$yaml_bad" == "ERR" ]]; then
  printf '%s✗ 失败%s  YAML 解析器不可用（examples/lib/yamlmin.py 不在位）\n' "$C_RED" "$C_RST"
  FAILED=$((FAILED + 1))
  FAILED_NAMES+=("yaml-语法")
else
  printf '%s✗ 失败%s  %s 个 YAML 里有 %s 个解析不了\n' "$C_RED" "$C_RST" "$yaml_total" "$yaml_bad"
  FAILED=$((FAILED + 1))
  FAILED_NAMES+=("yaml-语法")
fi

head2 "结果"
hr
printf '  通过 %s%d%s   失败 %s%d%s\n' "$C_GRN" "$PASSED" "$C_RST" \
  "$([[ $FAILED -eq 0 ]] && echo "$C_GRN" || echo "$C_RED")" "$FAILED" "$C_RST"

if [[ $FAILED -gt 0 ]]; then
  printf '\n  失败的检查：%s\n' "${FAILED_NAMES[*]}"
  if [[ $SHOW_HINTS -eq 1 ]]; then
    cat <<'EOF'

  怎么修（按错误信息对号入座）：
    validate-clusters   字段抄错了 → 照着同目录 cluster.yaml 改
    appset-simulator    重名/项目不存在/目的地不匹配 → 看 bootstrap/appprojects/
    render-check        overlay 渲染失败 → 多半是引用路径写错或父子嵌套（cycle）
    validate-examples   危险默认值 → 照着错误提示改配置
    check-doc-links     链接断了 → 改链接或补文件
    yaml-语法           缩进/引号问题 → 直接看报的行号
EOF
  fi
  exit 1
fi

printf '\n%s全部通过%s\n' "$C_GRN" "$C_RST"
exit 0
