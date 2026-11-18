#!/usr/bin/env bash
# sanitize-check.sh — 内部标识符扫描闸门
#
# 用法：
#   sanitize-check.sh --staged          扫描暂存区（pre-commit 钩子调用）
#   sanitize-check.sh --push            扫描待推送的提交（pre-push 钩子调用，refs 从 stdin 读）
#   sanitize-check.sh --commit <REV>    扫描某次提交的整棵树
#   sanitize-check.sh --worktree        扫描工作区
#   sanitize-check.sh --message <FILE>  扫描 commit message（commit-msg 钩子调用）
#
# 标识符清单：本机 .git/sanitize-denylist.txt（不随仓库分发）
#   每行格式： <代号>  或  <代号><TAB><替换建议>
#   —— 清单是唯一事实来源：改这个文件即可改变闸门行为，无需改本脚本。
#
# 命中判定：代号**前一个字符不是字母/数字**才算真命中。
#   这样能挡掉真实用法（形如 <前缀>-<业务名>、X-<前缀>-<字段>、<前缀>.<域名>），
#   又不会把 base64 / 证书 / JAR 里的随机字节误判（那类只做汇总提示，不阻断）。
#
# 退出码：0 = 通过；1 = 命中并阻断。
# 紧急跳过：SKIP_SANITIZE=1 git push ...（会打印醒目告警）

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$ROOT" || exit 0

DENYLIST="$ROOT/.git/sanitize-denylist.txt"

# ── 读取清单 ────────────────────────────────────────────────────────
if [ ! -f "$DENYLIST" ]; then
  echo "ℹ️  sanitize-check: 本机清单 $DENYLIST 不存在，本次跳过。" >&2
  echo "ℹ️  需要启用时，在本机创建该文件（切勿提交到仓库）。" >&2
  exit 0
fi

TOKENS=()
SUGGESTS=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  line="${line%%#*}"
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$line" ] && continue
  tok="${line%%$'\t'*}"
  sug="${line#*$'\t'}"
  [ "$sug" = "$line" ] && sug=""
  [ -z "$tok" ] && continue
  TOKENS+=("$tok")
  SUGGESTS+=("$sug")
done < "$DENYLIST"

if [ ${#TOKENS[@]} -eq 0 ]; then
  exit 0
fi

# ── 构造正则 ────────────────────────────────────────────────────────
TOK_RE=""
for t in "${TOKENS[@]}"; do
  esc="$(printf '%s' "$t" | sed 's/[][\.*^$(){}?+|/]/\\&/g')"
  [ -n "$TOK_RE" ] && TOK_RE="$TOK_RE|"
  TOK_RE="$TOK_RE$esc"
done
RE_HARD="(?<![A-Za-z0-9+=])($TOK_RE)"
RE_SOFT="($TOK_RE)"
# 路径判定：代号前后不能是字母数字（docs/<代号>-notes 命中，my<代号>-notes 不命中）
RE_PATH="(?<![A-Za-z0-9])($TOK_RE)"

# ── 命中判定（check 与 replace 必须完全一致，否则会反复拦截）───────────
# 1) 左边界：代号前一个字符不能是 字母/数字/+/=
#    —— 路径里的 / 允许，它属于「有意义的位置」（docs/<代号>/... 要能查出来）
# 2) base64 排除：命中处若落在长 base64 片段里（长度 > 24 且 '/' 密度低）则只算软命中
#    —— 证书 / JAR / 压缩包里的随机字节不算命中，也不要去替换（会把示例改坏）

PATFILE="$(mktemp)"
trap 'rm -f "$PATFILE"' EXIT
for t in "${TOKENS[@]}"; do printf '%s\n' "$t" >> "$PATFILE"; done

# ── 提示文案 ────────────────────────────────────────────────────────
suggest_for() {
  local want="$1" i
  for i in "${!TOKENS[@]}"; do
    # 大小写不敏感匹配：文件里可能是全小写 / 首字母大写 / 全大写等变体
    if [ "$(printf '%s' "${TOKENS[$i]}" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$want" | tr 'A-Z' 'a-z')" ]; then
      if [ -n "${SUGGESTS[$i]}" ]; then
        printf '%s' "${SUGGESTS[$i]}"
        return 0
      fi
      break
    fi
  done
  printf '语义清晰的通用占位符（如 example-... / internal-...）'
}

# ── 候选文件查找 ────────────────────────────────────────────────────
# git grep <tree-ish> 返回的路径带 "<rev>:" 前缀，必须剥掉，
# 否则取内容会失败 → 扫描静默变成「假通过」。
candidates_for() {
  local rev="$1"
  git grep -l -I -i -F -f "$PATFILE" "$rev" 2>/dev/null | sed "s|^${rev}:||"
}

# ── 路径清单：与内容扫描同口径 ──────────────────────────────────────────
# staged   → 索引（git grep --cached 扫的就是整个索引）
# commit   → 该提交的整棵树
# worktree → 已跟踪 + 未跟踪（未忽略）
paths_for() {
  local mode="$1" rev="${2:-}"
  case "$mode" in
    staged)   git ls-files ;;
    commit)   git ls-tree -r --name-only "$rev" 2>/dev/null ;;
    worktree) { git ls-files; git ls-files --others --exclude-standard; } ;;
    *)        return 0 ;;
  esac
}

# 代号可能出现在「路径」里而不只是内容里（文件名 / 目录名同样会公开）
add_path_hits() {
  local mode="$1" rev="${2:-}" p tok
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      HARD_LINES+=("$p"$'\t'"$tok")
    done < <(printf '%s' "$p" | SCAN_RE_PATH="$RE_PATH" perl -ne '
      my $re = $ENV{SCAN_RE_PATH};
      while (/(?:$re)/gi) { print "$1\n"; }
    ' 2>/dev/null)
  done < <(paths_for "$mode" "$rev")
}

# ── 扫描单个文件 ────────────────────────────────────────────────────
# 输出：HARD<TAB>代号   或   SOFT<TAB>命中数
scan_file() {
  local file="$1" mode="$2" rev="${3:-HEAD}"
  case "$mode" in
    staged)   git cat-file blob ":$file" 2>/dev/null ;;
    commit)   git cat-file blob "$rev:$file" 2>/dev/null ;;
    worktree) cat -- "$file" 2>/dev/null ;;
    *)        return 0 ;;
  esac | SCAN_RE_TOK="$TOK_RE" perl -0777 -ne '
      # base64 片段判定：命中处左右连续 base64 字符构成的片段过长且斜杠稀疏 → 随机字节
      sub in_blob {
        my ($t, $s, $e) = @_;
        my $l = $s;
        $l-- while $l > 0 && substr($t, $l-1, 1) =~ /[A-Za-z0-9+\/=]/;
        my $r = $e;
        my $len = length($t);
        $r++ while $r < $len && substr($t, $r, 1) =~ /[A-Za-z0-9+\/=]/;
        my $run = substr($t, $l, $r - $l);
        my $n = length($run);
        return 0 if $n <= 24;
        my $slashes = ($run =~ tr/\///);
        return ($slashes * 8) < $n ? 1 : 0;
      }
      my $alt = $ENV{SCAN_RE_TOK};
      my $total = 0;
      my @h;
      while (/((?:$alt))/gi) {
        my $s = $-[0];
        my $e = $+[0];
        my $tok = $1;
        $total++;
        my $prev = $s > 0 ? substr($_, $s-1, 1) : "";
        next if $prev =~ /[A-Za-z0-9+=]/;   # 不是有意义的位置
        next if in_blob($_, $s, $e);       # base64 / 证书里的随机字节
        push @h, $tok;
      }
      if (@h) { print "HARD\t$_\n" for @h; }
      else { print "SOFT\t$total\n" if $total; }
    ' 2>/dev/null
}

# ── 汇总 ────────────────────────────────────────────────────────────
HARD_LINES=()
SOFT_COUNT=0

collect() {
  local out="$1" f="$2"
  local kind val
  while IFS=$'\t' read -r kind val; do
    [ -z "$kind" ] && continue
    if [ "$kind" = "HARD" ]; then
      HARD_LINES+=("$f"$'\t'"$val")
    else
      SOFT_COUNT=$((SOFT_COUNT + val))
    fi
  done <<EOF
$out
EOF
}

finalize() {
  if [ ${#HARD_LINES[@]} -gt 0 ]; then
    {
      echo ""
      echo "❌ 操作被拦截：检测到内部标识符。"
      echo ""
      for l in "${HARD_LINES[@]}"; do
        echo "   位置：${l%%$'\t'*}"
        echo "   命中标识符：${l#*$'\t'}"
        echo "   建议替换为：$(suggest_for "${l#*$'\t'}")"
        echo ""
      done
      echo "   规则：代号出现在标识符 / 域名 / 路径等有意义位置才算命中。"
      echo "         （base64 / 证书 / JAR 里的随机字节不算，会单独汇总）"
      echo ""
      echo "   ✅ 处理方式：按上面的建议替换后重新提交。"
      echo "      可直接跑 scripts/sanitize-replace.sh 自动替换后再提交。"
      echo "   📖 完整规则见 AGENTS.md「内容脱敏约定」。"
      echo ""
      echo "   ℹ️  如确需临时跳过：SKIP_SANITIZE=1 <本次命令>"
    } >&2
    exit 1
  fi
  if [ "$SOFT_COUNT" -gt 0 ]; then
    echo "ℹ️  sanitize-check: 另有 $SOFT_COUNT 处命中位于 base64/二进制随机字节中，已忽略。" >&2
  fi
  exit 0
}

MODE="${1:---worktree}"
REV="${2:-HEAD}"

# 紧急跳过：SKIP_SANITIZE=1 对所有模式生效（提交 / 推送 / message 扫描）
if [ "${SKIP_SANITIZE:-0}" = "1" ]; then
  echo "⚠️  SKIP_SANITIZE=1 —— 本次内部标识符检查被跳过。" >&2
  echo "⚠️  请确认本次改动不会把内部代号推到公开仓库！" >&2
  exit 0
fi

case "$MODE" in
  --staged)
    for f in $(git grep -l -I -i -F -f "$PATFILE" --cached 2>/dev/null); do
      collect "$(scan_file "$f" staged)" "$f"
    done
    add_path_hits staged
    ;;

  --commit)
    for f in $(candidates_for "$REV"); do
      collect "$(scan_file "$f" commit "$REV")" "$f"
    done
    add_path_hits commit "$REV"
    ;;

  --worktree)
    for f in $(git grep -l -I -i -F -f "$PATFILE" 2>/dev/null); do
      collect "$(scan_file "$f" worktree)" "$f"
    done
    add_path_hits worktree
    ;;

  --message)
    MSG_FILE="${2:-}"
    if [ -z "$MSG_FILE" ] || [ ! -f "$MSG_FILE" ]; then
      echo "用法: $0 --message <FILE>" >&2
      exit 0
    fi
    while IFS= read -r tok; do
      [ -z "$tok" ] && continue
      HARD_LINES+=("commit message"$'\t'"$tok")
    done < <(SCAN_RE_TOK="$TOK_RE" perl -0777 -ne '
      sub in_blob {
        my ($t, $s, $e) = @_;
        my $l = $s;
        $l-- while $l > 0 && substr($t, $l-1, 1) =~ /[A-Za-z0-9+\/=]/;
        my $r = $e;
        my $len = length($t);
        $r++ while $r < $len && substr($t, $r, 1) =~ /[A-Za-z0-9+\/=]/;
        my $run = substr($t, $l, $r - $l);
        my $n = length($run);
        return 0 if $n <= 24;
        my $slashes = ($run =~ tr/\///);
        return ($slashes * 8) < $n ? 1 : 0;
      }
      my $alt = $ENV{SCAN_RE_TOK};
      my @h;
      while (/((?:$alt))/gi) {
        my $s = $-[0];
        my $e = $+[0];
        my $tok = $1;
        my $prev = $s > 0 ? substr($_, $s-1, 1) : "";
        next if $prev =~ /[A-Za-z0-9+=]/;
        next if in_blob($_, $s, $e);
        push @h, $tok;
      }
      print "$_\n" for @h;
    ' "$MSG_FILE" 2>/dev/null)
    ;;

  --push)
    while read -r local_ref local_sha remote_ref remote_sha; do
      [ -z "${local_sha:-}" ] && continue
      case "$local_sha" in
        0*) continue ;;
      esac
      git cat-file -e "$local_sha^{commit}" 2>/dev/null || continue
      for f in $(candidates_for "$local_sha"); do
        collect "$(scan_file "$f" commit "$local_sha")" "$f"
      done
    done
    ;;

  *)
    echo "用法: $0 [--staged|--push|--commit REV|--worktree|--message FILE]" >&2
    exit 0
    ;;
esac

finalize
