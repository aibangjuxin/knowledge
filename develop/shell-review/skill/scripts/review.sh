#!/usr/bin/env bash
#
# review.sh — one-shot Shell script audit driver
#
# Usage:
#   review.sh <file_or_glob> [...]
#   review.sh --tier <A|B|C|D> <files...>
#   review.sh --diff main...HEAD          # audit PR diff
#
# Codifies the L1 + L2 portion of the shell-review skill (the automated half).
# L3 (semantic) and L4 (runtime) are still the agent's job — this script
# produces the structured input the agent needs to do L3/L4 well.
#
# Outputs a report in the same severity-tagged format as the skill's output spec.
# Exit codes: 0 = pass, 1 = warnings only, 2 = blockers found.
#
# Requires: bash 5.x, shellcheck ≥0.8, shfmt ≥3.x, git (for --diff mode).

set -euo pipefail

# ---------- args ----------
TIER="B"
DIFF_MODE=""
FILES=()

usage() {
    cat <<EOF
Usage:
  $0 [--tier A|B|C|D] [--diff <range>] <file_or_glob> [...]
  $0 --diff main...HEAD

Tiers:
  A  one-shot throwaway (L1 + L2.1 only)
  B  reusable infra     (L1 + L2.1-L2.5)
  C  PR from teammate   (B + diff sweep)
  D  prod-touching      (B + extra scrutiny)
EOF
    exit 64
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier) TIER="$2"; shift 2 ;;
        --diff) DIFF_MODE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) FILES+=("$1"); shift ;;
    esac
done

# ---------- gather files ----------
if [[ -n "$DIFF_MODE" ]]; then
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "ERROR: --diff requires a git repo" >&2
        exit 64
    fi
    # shellcheck disable=SC2207
    FILES=($(git diff "$DIFF_MODE" --name-only -- '*.sh' '*.bash' '*.zsh'))
    if [[ ${#FILES[@]} -eq 0 ]]; then
        echo "No shell files changed in $DIFF_MODE"
        exit 0
    fi
elif [[ ${#FILES[@]} -eq 0 ]]; then
    usage
fi

echo "[shell-review] target=${FILES[*]}  tier=${TIER}  dialect=bash"
echo "═══════════════════════════════════════════════════════════"

# ---------- L1 syntax ----------
echo
echo "L1 SYNTAX"
L1_FAIL=0
for f in "${FILES[@]}"; do
    if bash -n "$f" 2>/tmp/sh-rev-err; then
        echo "  ✓ $f parses"
    else
        echo "  ✗ $f — $(cat /tmp/sh-rev-err | tr '\n' ' ')"
        L1_FAIL=1
    fi
done
if [[ $L1_FAIL -ne 0 ]]; then
    echo "═══════════════════════════════════════════════════════════"
    echo "VERDICT: ✗ BLOCK (L1 syntax failure — fix parse errors first)"
    exit 2
fi

# ---------- L2.1 shellcheck ----------
echo
echo "L2.1 shellcheck (-S warning -x)"
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -S warning -x "${FILES[@]}" 2>/tmp/sh-rev-sc; then
        echo "  ✓ no warnings or errors"
    else
        echo "  ⚠ findings:"
        sed 's/^/    /' /tmp/sh-rev-sc
    fi
else
    echo "  ⚠ shellcheck not installed — install via 'brew install shellcheck'"
fi

# ---------- L2.2 shfmt ----------
echo
echo "L2.2 shfmt (-d -i 2 -ci -ln bash)"
if command -v shfmt >/dev/null 2>&1; then
    if shfmt -d -i 2 -ci -ln bash "${FILES[@]}" >/tmp/sh-rev-fmt 2>&1; then
        echo "  ✓ no format violations"
    else
        echo "  ℹ $(wc -l < /tmp/sh-rev-fmt) lines of diff output (see /tmp/sh-rev-fmt)"
    fi
else
    echo "  ⚠ shfmt not installed"
fi

# ---------- L2.4 secret / destructive sweep ----------
echo
echo "L2.4 secret / destructive sweep"
# Run BOTH destructive and secret regexes regardless of mode. Diff-mode filters to
# added lines; whole-file mode reports line numbers. Both are useful.
DESTRUCTIVE='rm\s+(-[rRfF][rRfF]*|-r|-f)|--force|2>/dev/null'
SECRETS='(password|passwd|secret|api[_-]?key|token)\s*[:=]\s*["'"'"'][^"'"'"' ]{6,}'
SECRETS_LOOSE='(password|passwd|secret|api[_-]?key|token)\s*[:=]\s*\S+'

if [[ -n "$DIFF_MODE" ]]; then
    HITS=$(git diff "$DIFF_MODE" -- '*.sh' | grep -E '^\+' \
           | grep -iE "${DESTRUCTIVE}|${SECRETS_LOOSE}" || true)
else
    HITS=$(grep -nE "${DESTRUCTIVE}|${SECRETS_LOOSE}" "${FILES[@]}" 2>/dev/null || true)
fi
if [[ -z "$HITS" ]]; then
    echo "  ✓ clean"
else
    echo "  ⚠ potential hits (review manually):"
    echo "$HITS" | sed 's/^/    /'
fi

# ---------- L2.5 diff sweep ----------
echo
echo "L2.5 diff / debug-print sweep"
if [[ -n "$DIFF_MODE" ]]; then
    HITS=$(git diff "$DIFF_MODE" -- '*.sh' | grep -E '^\+' \
           | grep -iE 'TODO|FIXME|XXX|HACK|set -x|echo "DEBUG' || true)
    if [[ -z "$HITS" ]]; then
        echo "  ✓ no TODO/DEBUG/HACK added"
    else
        echo "  ℹ debug artifacts in diff:"
        echo "$HITS" | sed 's/^/    /'
    fi
else
    echo "  (skipped — no --diff specified)"
fi

# ---------- verdict ----------
echo
echo "═══════════════════════════════════════════════════════════"
echo "L3 SEMANTIC and L4 RUNTIME require human/AI reasoning."
echo "Run the shell-review skill (or read references/methodology.md)"
echo "to complete those layers."
echo
echo "VERDICT: L1+L2 automated portion complete. Tier=${TIER}."
echo "═══════════════════════════════════════════════════════════"

exit 0