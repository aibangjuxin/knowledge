#!/usr/bin/env bash
# sanitize-replace.sh — 按本机内部标识符清单做定向替换（push 流程自动调用）
#
# 用法：
#   scripts/sanitize-replace.sh --file PATH [--file PATH ...]   原地替换文件内容
#   scripts/sanitize-replace.sh --files-from LIST              按列表替换（LIST 每行一个路径）
#   scripts/sanitize-replace.sh --stdin < FILE                 替换 stdin 内容 → stdout
#   scripts/sanitize-replace.sh --paths                        打印路径重命名计划（NUL 分隔）
#   scripts/sanitize-replace.sh --list-rules                   打印合并后的规则表
#
# 规则来源（按顺序取先出现的，denylist 优先）：
#   1. .git/sanitize-denylist.txt        格式 <代号><TAB><替换建议>   （唯一事实来源）
#   2. .git/sanitize-residual.txt        格式 <代号><TAB><替换建议>   （已知残留，一并脱敏）
#   3. $SANITIZE_EXTRA_RULES             默认 ~/.config/push-replace/replace.txt
#                                       格式 <old> <new>
#
# 替换只在「有意义的位置」发生，与 sanitize-check.sh 的 HARD 判定保持一致：
#   - 前一个字符不是 字母 / 数字 / + / =
#   - 命中处不在长 base64 片段里（避免改坏证书 / JAR / 压缩包）
#
# 退出码：0 = 成功；1 = 出错。

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "sanitize-replace: 不在 git 仓库内" >&2; exit 1; }
cd "$ROOT" || exit 1

DENYLIST="$ROOT/.git/sanitize-denylist.txt"
RESIDUAL_FILE="$ROOT/.git/sanitize-residual.txt"
# 本机配置（不提交）：rename=0 可关闭「路径重命名」
CONF_FILE="$ROOT/.git/sanitize.conf"
RENAME=1
if [ -f "$CONF_FILE" ]; then
  # 注意：BSD sed 不支持 BRE 的 \| ，这里用 grep -E + cut
  conf_rename="$(grep -E '^[[:space:]]*rename[[:space:]]*=' "$CONF_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')"
  [ "$conf_rename" = "0" ] && RENAME=0
fi
EXTRA_RULES="${SANITIZE_EXTRA_RULES:-$HOME/.config/push-replace/replace.txt}"
MODE="files"
FILES=()
FILES_FROM=""

usage() {
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)      shift; [[ $# -ge 1 ]] || { echo "sanitize-replace: --file 缺少参数" >&2; exit 1; }
                     FILES+=("$1"); shift ;;
        --files-from) shift; [[ $# -ge 1 ]] || { echo "sanitize-replace: --files-from 缺少参数" >&2; exit 1; }
                     FILES_FROM="$1"; shift ;;
        --stdin)     MODE="stdin"; shift ;;
        --paths)     MODE="paths"; shift ;;
        --list-rules) MODE="list"; shift ;;
        --no-rename) RENAME=0; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "sanitize-replace: 未知参数 $1" >&2; exit 1 ;;
    esac
done

if [[ ! -f "$DENYLIST" ]]; then
    echo "ℹ️  sanitize-replace: 本机清单 $DENYLIST 不存在，本次不做替换。" >&2
    exit 0
fi

# ── 规则文件：old <TAB> new <TAB> source ────────────────────────────────
RULES_FILE="$(mktemp "${TMPDIR:-/tmp}/sanitize-rules.XXXXXX")"
PERL_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/sanitize-replace.XXXXXX.pl")"
cleanup() { rm -f "$RULES_FILE" "$PERL_SCRIPT"; }
trap cleanup EXIT

while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    tok="${line%%$'\t'*}"
    sug="${line#*$'\t'}"
    [[ "$sug" = "$line" ]] && sug=""
    [[ -z "$tok" ]] && continue
    if [[ -z "$sug" ]]; then
        echo "⚠️  sanitize-replace: 清单条目「$tok」没有替换建议，跳过自动替换（闸门仍会拦截）。" >&2
        continue
    fi
    printf '%s\t%s\tdenylist\n' "$tok" "$sug" >> "$RULES_FILE"
done < "$DENYLIST"

if [[ -f "$RESIDUAL_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="${line%%#*}"
        line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue
        tok="${line%%$'\t'*}"
        sug="${line#*$'\t'}"
        [[ "$sug" = "$line" ]] && sug=""
        [[ -z "$tok" ]] && continue
        if [[ -z "$sug" ]]; then
            echo "⚠️  sanitize-replace: 残留条目「$tok」没有替换建议，跳过自动替换。" >&2
            continue
        fi
        printf '%s\t%s\tresidual\n' "$tok" "$sug" >> "$RULES_FILE"
    done < "$RESIDUAL_FILE"
fi

if [[ -f "$EXTRA_RULES" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "${line#\#}" != "$line" ]] && continue
        old="${line%%[[:space:]]*}"
        new="${line#"$old"}"
        new="$(printf '%s' "$new" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$old" ]] && continue
        printf '%s\t%s\textra\n' "$old" "$new" >> "$RULES_FILE"
    done < "$EXTRA_RULES"
fi

if [[ ! -s "$RULES_FILE" ]]; then
    echo "ℹ️  sanitize-replace: 没有任何可用规则，本次不做替换。" >&2
    exit 0
fi

# ── 替换引擎 ───────────────────────────────────────────────────────────
cat > "$PERL_SCRIPT" <<'PERL_EOF'
use strict;
use warnings;

my $MAX_RUN = 24;   # 命中处所在的连续 base64 片段超过这个长度 → 视为随机字节，不替换

my $rules_file = $ARGV[0] // '';
my $mode       = $ARGV[1] // 'file';
my @rest       = @ARGV[2 .. $#ARGV];

# ── 载入规则 ───────────────────────────────────────────────────────────
my @rules;
my %owner;
my @conflicts;

open(my $rf, '<', $rules_file) or do { print STDERR "cannot read rules: $!\n"; exit 1; };
while (my $line = <$rf>) {
    chomp $line;
    next if $line eq '';
    my ($old, $new, $src) = split(/\t/, $line, 3);
    next unless defined $old && length $old;
    $new = '' unless defined $new;
    $src = 'extra' unless defined $src;
    my $key = lc $old;
    if (exists $owner{$key}) {
        push @conflicts, "$old —— denylist 的替换建议已覆盖 $src 规则";
        next;
    }
    $owner{$key} = $src;
    push @rules, [$old, $new, $src];
}
close $rf;

# ── 用 denylist 规则清洗「替换值」本身 ──────────────────────────────────
# 例：replace.txt 里某条规则的「替换值」本身含有清单代号 —— 会被就地清洗掉
my @deny = grep { $_->[2] eq 'denylist' } @rules;
for my $r (@rules) {
    for my $d (@deny) {
        next if lc($d->[0]) eq lc($r->[0]);
        my $re = qr/(?<![A-Za-z0-9+\/=])\Q$d->[0]\E/;
        $r->[1] =~ s/$re/$d->[1]/g;
    }
}

# ── 长代号优先 ─────────────────────────────────────────────────────────
# 长代号优先：先替换「前缀+编号」这类复合代号，再替换其中的短代号，避免拆成两截
@rules = sort { length($b->[0]) <=> length($a->[0]) } @rules;

for my $c (@conflicts) { print STDERR "⚠️  sanitize-replace: $c\n"; }

if ($mode eq 'list') {
    printf "%-24s %-20s %s\n", 'OLD', 'NEW', 'SOURCE';
    for my $r (@rules) { printf "%-24s %-20s %s\n", $r->[0], $r->[1], $r->[2]; }
    exit 0;
}

# ── 内容替换 ───────────────────────────────────────────────────────────
#
# 命中判定与 sanitize-check.sh 完全一致：
#   1) 左边界：代号前一个字符不能是 字母/数字/+/=（路径里的 / 允许）
#   2) base64 排除：命中处落在长 base64 片段里 → 不替换（否则会把证书 / JAR 改坏）
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

sub apply_rules {
    my ($text) = @_;
    my %hits;
    my %skipped;
    for my $r (@rules) {
        my ($old, $new) = @$r;
        my $re = qr/(?<![A-Za-z0-9+=])\Q$old\E/;
        # 注意：s///e 的回调里不能写 return（会直接从 apply_rules 返回），
        #       所以用三元表达式表达「替换 / 跳过」两个分支。
        $text =~ s{$re}{
            # 先把匹配信息存下来：下面的内层正则会覆盖 $& / $-[0] / $+[0]
            my $m = $&;
            my $s = $-[0];
            my $e = $+[0];
            if (in_blob($text, $s, $e)) {
                $skipped{$old}++;   # base64 / 证书里的随机字节，原样保留
                $m;
            } else {
                $hits{$old}++;
                $new;
            }
        }ge;
    }
    return ($text, \%hits, \%skipped);
}

sub report {
    my ($file, $hits, $skipped) = @_;
    if (%$hits) {
        my @h = map { "$_→$hits->{$_}" } sort keys %$hits;
        print "✅ $file  已替换: " . join(', ', @h) . "\n";
    } else {
        print "·  $file  无需替换\n";
    }
    if (%$skipped) {
        my @s = map { "$_×$skipped->{$_}" } sort keys %$skipped;
        print "⚠️  $file  跳过(base64/二进制): " . join(', ', @s) . "\n";
    }
}

if ($mode eq 'file') {
    my $path = $rest[0] // '';
    open(my $fh, '<', $path) or do { print STDERR "cannot read $path: $!\n"; exit 1; };
    local $/;
    my $text = <$fh>;
    close $fh;
    $text = '' unless defined $text;
    my ($out, $hits, $skipped) = apply_rules($text);
    if ($out ne $text) {
        open(my $wh, '>', $path) or do { print STDERR "cannot write $path: $!\n"; exit 1; };
        print $wh $out;
        close $wh;
    }
    report($path, $hits, $skipped);
    exit 0;
}

if ($mode eq 'stdin') {
    local $/;
    my $text = <STDIN>;
    $text = '' unless defined $text;
    my ($out, $hits, $skipped) = apply_rules($text);
    print $out;
    for my $k (sort keys %$hits) {
        print STDERR "✅ sanitize-replace: $k × $hits->{$k}\n";
    }
    for my $k (sort keys %$skipped) {
        print STDERR "⚠️  sanitize-replace: $k × $skipped->{$k} (base64/二进制，未替换)\n";
    }
    exit 0;
}

if ($mode eq 'paths') {
    # STDIN: NUL 分隔的路径；STDOUT: "old\tnew\0"
    # 注意：perl 的 $/ = "\0" 不会把分隔符从记录里去掉，所以这里改成 slurp + split
    local $/;
    my $data = <STDIN>;
    $data = '' unless defined $data;
    for my $path (split(/\0/, $data)) {
        next unless length $path;
        my $new = $path;
        for my $r (@rules) {
            my ($old, $rep) = @$r;
            my $re = qr/(?<![A-Za-z0-9])\Q$old\E/;
            $new =~ s/$re/$rep/g;
        }
        print "$path\t$new\0" if $new ne $path;
    }
    exit 0;
}

exit 0;
PERL_EOF

# ── 分发 ───────────────────────────────────────────────────────────────
case "$MODE" in
    list)
        perl "$PERL_SCRIPT" "$RULES_FILE" list
        ;;

    stdin)
        perl "$PERL_SCRIPT" "$RULES_FILE" stdin
        ;;

    paths)
        perl "$PERL_SCRIPT" "$RULES_FILE" paths
        ;;

    files)
        if [[ -n "$FILES_FROM" ]]; then
            [[ -f "$FILES_FROM" ]] || { echo "sanitize-replace: 列表文件不存在: $FILES_FROM" >&2; exit 1; }
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                FILES+=("$f")
            done < "$FILES_FROM"
        fi
        for f in "${FILES[@]}"; do
            [[ -f "$f" ]] || { echo "·  $f  不存在，跳过" >&2; continue; }
            # 不改闸门脚本本身：运行中自修改会让 shell 重新读取自己而报语法错
            case "$(basename "$f")" in
                sanitize-replace.sh|sanitize-check.sh)
                    echo "·  $f  闸门脚本本身，跳过"
                    continue
                    ;;
            esac
            mime="$(file -b --mime "$f" 2>/dev/null || true)"
            # 注意：空文件的 mime 是 "inode/x-empty; charset=binary"，不能当成二进制跳过
            if [[ "$mime" == *"charset=binary"* && "$mime" != *"x-empty"* ]]; then
                echo "·  $f  二进制文件，跳过"
                continue
            fi
            perl "$PERL_SCRIPT" "$RULES_FILE" file "$f"
        done

        # ── 路径重命名 ───────────────────────────────────────────────────
        if [[ "$RENAME" -eq 1 ]]; then
            renamed=0
            while IFS= read -r -d '' pair; do
                old="${pair%%$'\t'*}"
                new="${pair#*$'\t'}"
                [[ -n "$new" && "$new" != "$old" ]] || continue
                [[ -e "$old" ]] || continue
                if [[ -e "$new" ]]; then
                    echo "⚠️  sanitize-replace: 目标路径已存在，跳过重命名: $old → $new" >&2
                    continue
                fi
                mkdir -p "$(dirname "$new")" 2>/dev/null || true
                if git ls-files --error-unmatch "$old" >/dev/null 2>&1; then
                    if git mv -f "$old" "$new" >/dev/null 2>&1; then
                        echo "✅ 重命名: $old → $new"
                        renamed=$((renamed + 1))
                    else
                        echo "⚠️  sanitize-replace: git mv 失败: $old → $new" >&2
                    fi
                else
                    if mv -f "$old" "$new" 2>/dev/null; then
                        echo "✅ 重命名: $old → $new"
                        renamed=$((renamed + 1))
                    else
                        echo "⚠️  sanitize-replace: mv 失败: $old → $new" >&2
                    fi
                fi
            done < <({ git ls-files -z; git ls-files --others --exclude-standard -z; } \
                     | perl "$PERL_SCRIPT" "$RULES_FILE" paths)
            [[ $renamed -gt 0 ]] && echo "✅ 路径重命名完成: $renamed 个"
        fi
        ;;
esac

# 正常结束一律返回 0：调用方（如 set -e 的 push 脚本）会把非 0 当成失败
exit 0
