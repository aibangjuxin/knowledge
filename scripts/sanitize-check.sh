#!/usr/bin/env bash
# sanitize-check.sh — 内部标识符扫描闸门
#
# 用法：
#   sanitize-check.sh --staged          扫描暂存区新增内容（pre-commit 钩子调用）
#   sanitize-check.sh --push            扫描待推送的新提交（pre-push 钩子调用，refs 从 stdin 读）
#   sanitize-check.sh --commit <REV>    扫描某次提交新增的内容
#   sanitize-check.sh --worktree        扫描工作区新增的内容
#   sanitize-check.sh --message <FILE>  扫描 commit message（commit-msg 钩子调用）
#
# 判定范围：**只管本次新增 / 推送的内容**。
#   已经推送过的历史内容不再追究（只做统计报告，不阻断）——
#   否则仓库里遗留的代号会让每一次推送都被拦死。
#
# 合规标准（命中即阻断）：
#   1. .git/sanitize-denylist.txt          本机清单，唯一事实来源
#   2. ~/.config/push-replace/replace.txt  本机补充规则（可用 SANITIZE_EXTRA_RULES 覆盖）
#
# 只报告不阻断：
#   3. .git/sanitize-residual.txt          已知残留 = 明确允许保留的代号
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
RESIDUAL_FILE="$ROOT/.git/sanitize-residual.txt"
EXTRA_RULES="${SANITIZE_EXTRA_RULES:-$HOME/.config/push-replace/replace.txt}"

# ── 载入规则表 ──────────────────────────────────────────────────────────
# 规则来源与格式见 scripts/sanitize-rules.sh（check / replace 共用同一份解析）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/sanitize-rules.sh
. "$SCRIPT_DIR/sanitize-rules.sh"

rules_load

BLOCK_TOKENS=()
BLOCK_SUGGESTS=()
RES_TOKENS=()
RES_SUGGESTS=()
i=0
while [ $i -lt ${#RULE_OLD[@]} ]; do
    if [ "${RULE_POLICY[$i]}" = "allow" ]; then
        RES_TOKENS+=("${RULE_OLD[$i]}")
        RES_SUGGESTS+=("${RULE_NEW[$i]}")
    else
        BLOCK_TOKENS+=("${RULE_OLD[$i]}")
        BLOCK_SUGGESTS+=("${RULE_NEW[$i]}")
    fi
    i=$((i + 1))
done

if [ ${#BLOCK_TOKENS[@]} -eq 0 ] && [ ${#RES_TOKENS[@]} -eq 0 ]; then
    exit 0
fi

# ── 构造正则 ────────────────────────────────────────────────────────
# 分支顺序 = 代号长度降序 → 同一位置总是最长匹配先命中，
# 报告出来的「命中标识符」与实际替换的单位一致
build_alt() {
    local out="" t esc
    for t in $(printf '%s\n' "$@" | awk 'NF{ print length($0) "\t" $0 }' | sort -rn | cut -f2-); do
        esc="$(printf '%s' "$t" | sed 's/[][\.*^$(){}?+|/]/\\&/g')"
        [ -n "$out" ] && out="$out|"
        out="$out$esc"
    done
    printf '%s' "$out"
}
BLOCK_RE="$(build_alt "${BLOCK_TOKENS[@]}")"
RES_RE=""
if [ ${#RES_TOKENS[@]} -gt 0 ]; then
    RES_RE="$(build_alt "${RES_TOKENS[@]}")"
fi

# ── 提示文案 ────────────────────────────────────────────────────────
suggest_for() {
    local want="$1" i
    want="$(printf '%s' "$want" | tr 'A-Z' 'a-z')"
    for i in "${!BLOCK_TOKENS[@]}"; do
        if [ "$(printf '%s' "${BLOCK_TOKENS[$i]}" | tr 'A-Z' 'a-z')" = "$want" ]; then
            if [ -n "${BLOCK_SUGGESTS[$i]}" ]; then
                printf '%s' "${BLOCK_SUGGESTS[$i]}"
                return 0
            fi
            break
        fi
    done
    for i in "${!RES_TOKENS[@]}"; do
        if [ "$(printf '%s' "${RES_TOKENS[$i]}" | tr 'A-Z' 'a-z')" = "$want" ]; then
            if [ -n "${RES_SUGGESTS[$i]}" ]; then
                printf '%s' "${RES_SUGGESTS[$i]}"
                return 0
            fi
            break
        fi
    done
    printf '语义清晰的通用占位符（如 example-... / internal-...）'
}

# ── 工具脚本本身：跳过 ───────────────────────────────────────────────────
# scripts/sanitize-*.sh 是闸门工具，它们：
#   - 运行中自修改会让 shell 重新读自己而报语法错（所以替换时要跳过）
#   - 如果里面残留了代号，会造成「拦你但改不了」的死锁
# 所以两边（扫描 / 替换）都跳过它们；工具脚本必须保持不含任何代号。
is_tooling_file() {
    case "$1" in
        scripts/sanitize-*.sh|scripts/install-sanitize-hooks.sh) return 0 ;;
        *) return 1 ;;
    esac
}

# ── 命中判定（check 与 replace 必须完全一致，否则会反复拦截）───────────
# 1) 左边界：代号前一个字符不能是 字母/数字/+/=
#    —— 路径里的 / 允许，它属于「有意义的位置」（docs/<代号>/... 要能查出来）
# 2) base64 排除：命中处若落在长 base64 片段里（长度 > 24 且 '/' 密度低）则只算软命中
#    —— 证书 / JAR / 压缩包里的随机字节不算命中，也不要去替换（会把示例改坏）

# ── 扫描「本次新增的内容」──────────────────────────────────────────────
# STDIN: unified diff（-U0）；输出：HARD<TAB>文件<TAB>代号
PERL_SCAN_DIFF='
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
      my %added;
      my $cur = "";
      while (<STDIN>) {
        if (/^diff --git /) { $cur = ""; next; }
        if (/^\+\+\+ (?:b\/)?(.*)$/) { $cur = $1; next; }
        next unless /^\+/;
        next if $cur eq "" || $cur eq "/dev/null";
        my $line = substr($_, 1);
        $line =~ s/\n$//;
        push @{ $added{$cur} }, $line;
      }
      my $alt = $ENV{SCAN_RE_TOK};
      for my $f (sort keys %added) {
        my $text = join("\n", @{ $added{$f} });
        while ($text =~ /((?:$alt))/gi) {
          my $s = $-[0];
          my $e = $+[0];
          my $tok = $1;
          my $prev = $s > 0 ? substr($text, $s-1, 1) : "";
          next if $prev =~ /[A-Za-z0-9+=]/;
          next if in_blob($text, $s, $e);
          print "HARD\t$f\t$tok\n";
        }
      }
'

# ── 本次涉及的新增内容（diff）────────────────────────────────────────
# new_diff <mode> [rev] [exclude_sha]
new_diff() {
    local mode="$1" rev="${2:-}" excl_sha="${3:-}"
    local excl="--remotes"
    case "$mode" in
        staged)   git diff --cached -U0 --no-color 2>/dev/null ;;
        commit)   git show --format= -U0 --no-color "$rev" 2>/dev/null ;;
        worktree) { git diff -U0 --no-color 2>/dev/null
                    git ls-files --others --exclude-standard -z 2>/dev/null \
                      | tr '\0' '\n' | while IFS= read -r u; do
                          [ -n "$u" ] || continue
                          printf 'diff --git a/%s b/%s\n+++ b/%s\n' "$u" "$u" "$u"
                          sed -e 's/^/+/' -- "$u" 2>/dev/null
                        done; } ;;
        push)     local c
                  # 只看「尚未出现在任何远端」的提交 = 本次真正要推送的新内容
                  case "$excl_sha" in
                      ""|0000000000000000000000000000000000000000) ;;
                      *) excl="$excl $excl_sha" ;;
                  esac
                  for c in $(git rev-list "$rev" --not $excl 2>/dev/null); do
                      git show --format= -U0 --no-color "$c" 2>/dev/null
                  done ;;
        *)        return 0 ;;
    esac
}

# ── 本次涉及的新路径 ─────────────────────────────────────────────────
# 只看「新增 / 重命名」的路径：已经存在并已推送过的路径不再追究
# （哪怕这次只是改了内容或权限，路径本身也不是新的）
# new_paths <mode> [rev] [exclude_sha]
new_paths() {
    local mode="$1" rev="${2:-}" excl_sha="${3:-}"
    local excl="--remotes"
    case "$mode" in
        staged)   git diff --cached --name-only --diff-filter=AR 2>/dev/null ;;
        commit)   git show --name-status --format= "$rev" 2>/dev/null \
                     | awk '$1 ~ /^[AR]/ { print $NF }' ;;
        worktree) { git diff --name-only --diff-filter=AR 2>/dev/null
                    git ls-files --others --exclude-standard 2>/dev/null; } ;;
        push)     local c
                  case "$excl_sha" in
                      ""|0000000000000000000000000000000000000000) ;;
                      *) excl="$excl $excl_sha" ;;
                  esac
                  for c in $(git rev-list "$rev" --not $excl 2>/dev/null); do
                      git diff-tree --no-commit-id --name-status -r "$c" 2>/dev/null \
                        | awk '$1 ~ /^[AR]/ { print $NF }'
                  done ;;
        *)        return 0 ;;
    esac
}

# ── 汇总 ────────────────────────────────────────────────────────────
HARD_LINES=()

# 内容命中（新增部分）→ 阻断
collect_new_content() {
    local mode="$1" rev="${2:-}" excl="${3:-}"
    local kind file tok
    while IFS=$'\t' read -r kind file tok; do
        [ "$kind" = "HARD" ] || continue
        [ -z "$file" ] && continue
        is_tooling_file "$file" && continue
        HARD_LINES+=("$file"$'\t'"$tok")
    done < <(new_diff "$mode" "$rev" "$excl" | SCAN_RE_TOK="$BLOCK_RE" perl -ne "$PERL_SCAN_DIFF" 2>/dev/null)
}

# 路径命中 → 阻断
collect_new_paths() {
    local mode="$1" rev="${2:-}" excl="${3:-}" p tok
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        is_tooling_file "$p" && continue
        while IFS= read -r tok; do
            [ -z "$tok" ] && continue
            HARD_LINES+=("$p"$'\t'"$tok")
        done < <(printf '%s' "$p" | SCAN_RE_PATH="$RE_PATH" perl -ne '
          my $re = $ENV{SCAN_RE_PATH};
          while (/(?:$re)/gi) { print "$1\n"; }
        ' 2>/dev/null)
    done < <(new_paths "$mode" "$rev" "$excl")
}

# 历史内容里的命中 → 只统计，不阻断（已经推送过的不追究）
HIST_COUNT=0
HIST_FILES=0
report_history() {
    local rev="$1" f n
    [ ${#BLOCK_TOKENS[@]} -eq 0 ] && return 0
    local -a files=()
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(git grep -l -I -i -F -f "$PATFILE" "$rev" 2>/dev/null | sed "s|^${rev}:||")
    HIST_FILES=${#files[@]}
    for f in "${files[@]}"; do
        is_tooling_file "$f" && continue
        n=$(git show "$rev:$f" 2>/dev/null | SCAN_RE_TOK="$BLOCK_RE" perl -0777 -ne "$PERL_SCAN_TEXT" 2>/dev/null \
            | awk -F'\t' '$1=="HARD"{c++} END{print c+0}')
        HIST_COUNT=$((HIST_COUNT + n))
    done
}

# 单个文件内容的命中统计
PERL_SCAN_TEXT='
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
      while (/((?:$alt))/gi) {
        my $s = $-[0];
        my $e = $+[0];
        my $tok = $1;
        my $prev = $s > 0 ? substr($_, $s-1, 1) : "";
        next if $prev =~ /[A-Za-z0-9+=]/;
        next if in_blob($_, $s, $e);
        print "HARD\t$tok\n";
      }
'

finalize() {
    if [ ${#HARD_LINES[@]} -gt 0 ]; then
        {
            echo ""
            echo "❌ 操作被拦截：本次新增的内容里有内部标识符。"
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
    if [ "$HIST_COUNT" -gt 0 ]; then
        {
            echo "ℹ️  sanitize-check: 历史内容里还有 $HIST_COUNT 处命中（$HIST_FILES 个文件），"
            echo "    已经推送过的部分不再追究，未阻断。"
        } >&2
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

# 路径判定用的正则 + 全树扫描用的 pattern 文件
RE_PATH="(?<![A-Za-z0-9])($BLOCK_RE)"
PATFILE="$(mktemp)"
trap 'rm -f "$PATFILE"' EXIT
for t in "${BLOCK_TOKENS[@]}"; do printf '%s\n' "$t" >> "$PATFILE"; done

case "$MODE" in
    --staged)
        collect_new_content staged
        collect_new_paths staged
        ;;

    --commit)
        collect_new_content commit "$REV"
        collect_new_paths commit "$REV"
        report_history "$REV"
        ;;

    --worktree)
        collect_new_content worktree
        collect_new_paths worktree
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
        done < <(SCAN_RE_TOK="$BLOCK_RE" perl -0777 -ne "$PERL_SCAN_TEXT" "$MSG_FILE" 2>/dev/null)
        ;;

    --push)
        while read -r local_ref local_sha remote_ref remote_sha; do
            [ -z "${local_sha:-}" ] && continue
            case "$local_sha" in
                0*) continue ;;
            esac
            git cat-file -e "$local_sha^{commit}" 2>/dev/null || continue
            collect_new_content push "$local_sha" "$remote_sha"
            collect_new_paths push "$local_sha" "$remote_sha"
        done
        ;;

    *)
        echo "用法: $0 [--staged|--push|--commit REV|--worktree|--message FILE]" >&2
        exit 0
        ;;
esac

finalize
