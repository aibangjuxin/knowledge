#!/usr/bin/env bash
# sanitize-rules.sh — 规则表加载（sanitize-check.sh / sanitize-replace.sh 共用）
#
# 表格式（空白或制表符分列）：
#   <代号> <替换值> [仓库范围] [策略]
#
#   仓库范围：all（默认） | <仓库名> | <仓库名1,仓库名2>
#             仓库名 = origin 远端地址最后一段（去 .git）；取不到则用仓库目录名
#   策略    ：block（默认，命中即阻断） | allow（只统计报告，不阻断）
#
# 生效来源（合并后按优先级取胜）：
#   1. 全局表  ~/.config/push-replace/replace.txt（可用 SANITIZE_EXTRA_RULES 覆盖）
#   2. 仓库本地 .git/sanitize-denylist.txt   （默认策略 block）
#   3. 仓库本地 .git/sanitize-residual.txt   （默认策略 allow）
#
# 优先级：仓库本地 > 全局；同来源内「仓库专属范围」>「all」；再同则先出现的赢。
#
# 用法：source 本文件后调用 rules_load，然后用
#   RULE_OLD[i] / RULE_NEW[i] / RULE_POLICY[i]（block|allow）
# 遍历即可。

RULE_OLD=()
RULE_NEW=()
RULE_POLICY=()

# 仓库标识（用于 scope 匹配）
# 候选：origin 远端地址最后一段（去 .git）、仓库目录名
# 只要任一候选命中 scope 就算适用 —— 克隆到别的目录名也不会失效
rules_repo_keys() {
    local url key out=""
    url="$(git remote get-url origin 2>/dev/null)" || url=""
    if [ -n "$url" ]; then
        key="${url##*/}"
        key="${key%.git}"
        [ -n "$key" ] && out="$key"
    fi
    key="$(basename "$ROOT")"
    case ",$out," in
        *",$key,"*) ;;
        *) out="${out:+$out,}$key" ;;
    esac
    printf '%s' "$out"
}

# scope 是否适用于当前仓库
rules_scope_matches() {
    local scope="$1" keys="$2" k
    [ -z "$scope" ] && return 0
    case ",${scope}," in
        *,all,*) return 0 ;;
    esac
    local IFS=','
    for k in $keys; do
        case ",${scope}," in
            *",${k},"*) return 0 ;;
        esac
    done
    return 1
}

# 加入一条规则；同代号已存在时按 (来源级别, 范围专属度) 比较取胜者
# $1 old  $2 new  $3 policy  $4 rank（全局=1，仓库本地=2）  $5 specific（0/1）
rules_add() {
    local old="$1" new="$2" policy="$3" rank="$4" specific="$5"
    local key i oldrank oldspec
    key="$(printf '%s' "$old" | tr 'A-Z' 'a-z')"
    for i in "${!RULE_OLD[@]}"; do
        if [ "$(printf '%s' "${RULE_OLD[$i]}" | tr 'A-Z' 'a-z')" = "$key" ]; then
            oldrank="${RULE_RANK[$i]}"
            oldspec="${RULE_SPEC[$i]}"
            if [ "$rank" -gt "$oldrank" ] ||
               { [ "$rank" -eq "$oldrank" ] && [ "$specific" -gt "$oldspec" ]; }; then
                RULE_NEW[$i]="$new"
                RULE_POLICY[$i]="$policy"
                RULE_RANK[$i]="$rank"
                RULE_SPEC[$i]="$specific"
            fi
            return 0
        fi
    done
    RULE_OLD+=("$old")
    RULE_NEW+=("$new")
    RULE_POLICY+=("$policy")
    RULE_RANK+=("$rank")
    RULE_SPEC+=("$specific")
}

# 载入一张表
# $1 文件  $2 默认策略  $3 来源级别（1=全局，2=仓库本地）
rules_load_file() {
    local file="$1" dpol="$2" rank="$3"
    local line old new scope policy repo spec
    [ -f "$file" ] || return 0
    repo="$(rules_repo_keys)"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="${line%%#*}"
        old=""; new=""; scope=""; policy=""
        read -r old new scope policy <<< "$line"
        [ -z "$old" ] && continue
        rules_scope_matches "$scope" "$repo" || continue
        [ -z "$policy" ] && policy="$dpol"
        spec=0
        if [ -n "$scope" ]; then
            case ",${scope}," in *,all,*) ;; *) spec=1 ;; esac
        elif [ "$rank" -ge 2 ]; then
            spec=1          # 仓库本地表默认就是「仓库专属」
        fi
        rules_add "$old" "$new" "$policy" "$rank" "$spec"
    done < "$file"
}

rules_load() {
    RULE_OLD=(); RULE_NEW=(); RULE_POLICY=(); RULE_RANK=(); RULE_SPEC=()
    rules_load_file "${SANITIZE_EXTRA_RULES:-$HOME/.config/push-replace/replace.txt}" block 1
    rules_load_file "$ROOT/.git/sanitize-denylist.txt" block 2
    rules_load_file "$ROOT/.git/sanitize-residual.txt" allow 2
}

# 取出某个策略下的规则下标（空格分隔）
rules_indexes_of_policy() {
    local want="$1" i
    for i in "${!RULE_OLD[@]}"; do
        [ "${RULE_POLICY[$i]}" = "$want" ] && printf '%s ' "$i"
    done
}
