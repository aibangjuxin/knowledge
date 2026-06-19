# Shell Script Review — `verify-pub-priv-ip-glm-ipv6.sh`

**Review date:** 2026-06-19
**Reviewer:** automated (shellcheck + shfmt + custom rule sweep via `skill/scripts/review.sh`)
                 + AI semantic pass (Layer 3) + trace-mode runtime check (Layer 4)
**Scope:** 1 Bash script, 830 LOC
**Methodology:** see [methodology.md](./methodology.md) · Skill: `skill/SKILL.md`

This is a **template worked example** showing what a `shell-review` skill invocation
produces end-to-end. Use it as a reference for the output format, severity ladder,
and finding density. It was produced by running:

```bash
/Users/lex/git/knowledge/develop/shell-review/skill/scripts/review.sh \
    /Users/lex/git/knowledge/linux/dns/dns-peering/verify-pub-priv-ip-glm-ipv6.sh
```

…followed by an AI semantic pass (L3) and a `bash -x` trace (L4) since the script
has no `--dry-run` flag.

---

## TL;DR — Headline Findings

| # | Severity | Layer | Location | Headline |
|---|----------|-------|----------|----------|
| 1 | **BLOCKER** | L3.2 (semantic) | line 285/291/297 | IPv6 ULA / link-local detection uses `[[ -ge ]]` (string compare); central job of script misclassifies private ranges as Public |
| 2 | **BLOCKER** | L3.1 (semantic) | line 720 | `trap "...$tmpdir..." EXIT RETURN` — double-quoted expansion-time bug + `RETURN` is not a valid trap signal (fires on every function return → triple-cleanup race) |
| 3 | **LOGIC** | L3.2 (semantic) | line 380-392 | 6× `local x=$(...)` patterns (SC2155) hide awk failures inside `while read` loop |
| 4 | **LOGIC** | L3.2 (semantic) | line 416-417 | Same SC2155 pattern, lower impact (subshell IFS) |
| 5 | **SUGGEST** | L3.1 (logic) | line 174-178 | Case statement only handles 5 output formats; `--help` not in case list |
| 6 | **SUGGEST** | L3.4 (portability) | line 303/309/315 | `[[ x == 2001:0:* ]]` glob pattern over-matches (any `2001:0` IPv6, not just Teredo) |
| 7 | **INFO** | L3.2 (dead code) | line 43, 756-759 | `RECORD_TYPES` / `SERVER_IPS` / `SERVER_TYPES` / `SERVER_RESULTS` declared/written but never read after assignment |
| 8 | **INFO** | L4 (runtime) | script-wide | No `--dry-run` flag — L4.1 unavailable |

**No secrets. All 4 `rm -rf` hits are scoped to script-owned `$tmpdir`.** Script is
in reasonable shape — both blockers are real but localized, and the fix surface is
small.

---

## L1 — Syntax

```
✓ /Users/lex/git/knowledge/linux/dns/dns-peering/verify-pub-priv-ip-glm-ipv6.sh parses
```

`bash -n` exit 0. Every required hygiene signal present: `#!/usr/bin/env bash` shebang,
`set -euo pipefail`, `mktemp -d` + `trap ... EXIT` for temp-dir cleanup.

---

## L2 — Static

### L2.1 shellcheck (-S warning -x) — 13 findings

```
✗ line 285, 291, 297   SC2309 × 6   $first_hex -ge/-le 0xfc00 is STRING comparison,
                                       not hex arithmetic. See L3.2 #1.
⚠ line 380,381,391,392,416,417  SC2155 × 6  `local x=$(...)` masks return value;
                                       see L3.2 #3, #4.
⚠ line 720            SC2064      Use single quotes in trap, otherwise $tmpdir
                                    expands now (not at signal). See L3.1 #2.
ℹ line 43,756,757,759  SC2034 × 4  RECORD_TYPES / SERVER_IPS / SERVER_TYPES /
                                    SERVER_RESULTS appear unused. See L3.2 #7.
```

### L2.2 shfmt

```
ℹ 309 lines of diff output
```

Script is not shfmt-formatted (Google style: `-i 2 -ci -ln bash`). One-time mechanical
pass needed if repo adopts that style. **Non-blocking.**

### L2.4 Secret / destructive sweep

```
⚠ line 720  trap "rm -rf '$tmpdir'" EXIT RETURN   — destructive, scoped to $tmpdir ✓
⚠ line 737  wait ${pids[$i]} 2>/dev/null          — silenced exit code, justified ✓
⚠ line 745  wait "$pid" 2>/dev/null               — same pattern, justified ✓
⚠ line 763  rm -rf "$tmpdir"                      — destructive, scoped to $tmpdir ✓
```

All four destructive hits are legitimate and path-scoped. No secrets detected.
**All four `2>/dev/null` usages are justified** — they silence parallel-job exit
codes that are aggregated separately downstream.

### L2.5 Diff / debug sweep

```
(skipped — single-file mode, no --diff specified)
```

---

## L3 — Semantic (manual / AI pass)

### ✗ BLOCKER  L3.2 #1 — IPv6 prefix classification is BROKEN

**Where:** `verify-pub-priv-ip-glm-ipv6.sh:285, 291, 297`

**Pattern (current, BROKEN):**
```bash
local first_hex=$((0x${first_block:-0}))
if [[ $first_hex -ge 0xfc00 && $first_hex -le 0xfdff ]]; then  # ULA
  echo "Private"; return
fi
if [[ $first_hex -ge 0xfe80 && $first_hex -le 0xfebf ]]; then  # link-local
  echo "Local"; return
fi
if [[ $first_hex -ge 0xfd00 && $first_hex -le 0xfdff ]]; then  # UL (overlaps ULA)
  echo "Private"; return
fi
```

**Why it matters (this is the secret bug):**
SC2309 is not a lint nit — it's a real semantic bug. In `[[ a -ge b ]]`, `-ge` is the
**string-comparison** operator, not arithmetic. By the time `$first_hex` reaches the
test it has already been converted to decimal by `$((0x...))`, so the comparison
intent (hex range check) is **mis-implemented with a string operator**:
- `[[ "64768" -ge "65023" ]]` is **string** compare → lexicographic on decimal digits
  happens to align with numeric for many ranges by accident
- `[[ "65152" -ge "65152" ]]` is always true (equal strings)
- `[[ "65152" -le "65183" ]]` is **always true** — fe80::/10 detection is degenerate

**Suggested fix:**
```bash
if (( first_hex >= 0xfc00 && first_hex <= 0xfdff )); then  # ULA, (( )) = arithmetic
  echo "Private"; return
fi
```

**Impact:** All IPv6 results with `first_block` in fe80::/10 are likely misclassified.
The script's *central job* is to identify which DNS answers are public vs. private,
so this defect silently inverts the verdict for an entire class of addresses.

---

### ✗ BLOCKER  L3.1 #2 — `trap` has two bugs

**Where:** `verify-pub-priv-ip-glm-ipv6.sh:720`
```bash
tmpdir=$(mktemp -d)
trap "rm -rf '$tmpdir'" EXIT RETURN
```

**Why it matters (this is the secret bug):**

(a) The double quotes make `$tmpdir` expand **now** (at trap registration), not at
signal time. In this specific case `tmpdir` is `/tmp/tmp.XXXXXX` so the bug is latent
— but if `mktemp` returned a path containing `$` or whitespace, this would either
expand wrongly or word-split. **Fragile, not robust.**

(b) `RETURN` is **not** a real trap signal in Bash for cleanup. Bash accepts the
syntax silently, but `RETURN` only fires when a shell function returns **and**
`extdebug` is set — and even then only on `return`, not on `exit`. The functions
in this file call `return 0` repeatedly (lines 276, 287, 293, 299, 305, 311, 317,
323, etc.), so the `RETURN` trap fires on every one of those, attempting `rm -rf`
on the same tmpdir path multiple times. Combined with the explicit `rm -rf "$tmpdir"`
on line 763 and the `EXIT` trap, the tmpdir gets `rm -rf`'d **3+ times per run** with
subtly different semantics, and the trap double-registers itself with a stale path
captured at registration time.

**Suggested fix:**
```bash
trap 'rm -rf "$tmpdir"' EXIT
# then drop the explicit line 763 OR drop EXIT and rely on 763; not both
```

---

### ⚠ LOGIC  L3.2 #3 — `local x=$(...)` hides awk failures (× 6)

**Where:** `verify-pub-priv-ip-glm-ipv6.sh:380, 381, 391, 392`

**Pattern:**
```bash
while IFS= read -r line; do
  local rec_type=$(echo "$line" | awk '{print $4}')
  local rec_value=$(echo "$line" | awk '{print $NF}')
  ...
done <<< "$result"
```

**Why it matters:**
SC2155 is right: if `awk` fails (line has fewer than 4 fields, malformed dig output),
the local var gets empty value AND the function returns 0 silently. With `set -e`
active this would exit, but inside the `while IFS= read` loop the failure is hidden
by the loop body. **Suggest:**
```bash
while IFS= read -r line; do
  local rec_type rec_value
  rec_type=$(echo "$line" | awk '{print $4}')
  rec_value=$(echo "$line" | awk '{print $NF}')
  [[ -n "$rec_type" && -n "$rec_value" ]] || continue
  ...
done <<< "$result"
```

### ⚠ LOGIC  L3.2 #4 — Same SC2155 pattern, lower impact

**Where:** `verify-pub-priv-ip-glm-ipv6.sh:416, 417`
```bash
local ips_csv=$(IFS=','; echo "${records[*]}")
local types_csv=$(IFS=','; echo "${types[*]}")
```

These are SC2155 too, but the subshell IFS-scoped join is more deterministic and
the impact of an empty value is bounded. **Non-blocking.**

---

### ℹ SUGGEST  L3.1 #5 — Case statement incomplete

**Where:** `verify-pub-priv-ip-glm-ipv6.sh:174-178`
```bash
--json|--short|--csv|--yaml|--normal)
  ...
  ;;
```

The case handles 5 output formats but `--help` falls to line 120 (separate case),
and `-v` / `--version` is not handled at all. **Suggest:** add `--help` and `-v`
to this case (or document them only in the help text).

### ℹ SUGGEST  L3.4 #6 — IPv6 glob patterns over-match

**Where:** `verify-pub-priv-ip-glm-ipv6.sh:303, 309, 315`
```bash
if [[ "$compressed" == 2001:0:* ]]; then    # Teredo
if [[ "$compressed" == 2001:db8:* ]]; then  # Documentation
if [[ "$compressed" == 2001:* ]]; then      # Catches all 2001::/16
```

In `[[ ]]`, the right-hand side is a **glob pattern**. `2001:0:*` matches any string
starting with `2001:0:`. Teredo is exactly `2001:0000::/32`, so any `2001:0a...`
address would also be classified as Teredo (incorrectly). The third pattern
(`2001:*`) is even broader and intended to catch "anything else starting with 2001",
which is technically correct but obscures the intent. **Suggest:** use `case` with
exact prefix matches, or document why the glob is safe.

### ℹ INFO  L3.2 #7 — Dead-code arrays

**Where:** `verify-pub-priv-ip-glm-ipv6.sh:43, 756-759`

`RECORD_TYPES`, `SERVER_IPS`, `SERVER_TYPES`, `SERVER_RESULTS` are written to but
never read after assignment. Either this is dead code from a refactor, or the
results-dumping step was removed without cleaning up. **Audit `process_results`
(line 767)** to see if it should consume these arrays — if not, delete them.

### ℹ INFO  L4 — No `--dry-run` flag

The script has no `--dry-run` mode. L4.1 (dry-run) is therefore unavailable; L4.2
(trace mode) was used as fallback and the `--help` path was exercised with
`bash -x`, exiting 0 with zero side effects and no network calls. **Suggest:**
add `--dry-run` to the argument parser, short-circuit `query_dns_server()` to
print "would query $dns for $domain $record_type" if `$DRY_RUN` is set.

---

## L4 — Runtime

```
✓ bash -x --help exercised; control flow matches expectation
  (config → parse → usage → exit 0, zero side effects, no network)
⚠ No --dry-run flag. L4.1 unavailable.
```

---

## Summary table — by finding class

| Class | Count | Blocking | Notes |
|---|---|---|---|
| L1 syntax | 1 pass | — | clean |
| L2.1 shellcheck | 13 findings | 2 (after L3 escalation) | SC2309 + SC2064 both promoted to BLOCKER |
| L2.2 shfmt | 309 diff lines | 0 | non-blocking format drift |
| L2.4 destructive | 4 hits | 0 | all scoped to `$tmpdir` |
| L2.5 debug sweep | (skipped) | — | no --diff specified |
| L3.1 logic | 2 findings | 1 (BLOCKER #2) | trap semantics bug |
| L3.2 data-flow | 3 findings | 1 (BLOCKER #1) | IPv6 hex compare + SC2155 patterns |
| L3.4 portability | 1 finding | 0 | glob pattern over-match |
| L4 runtime | 1 finding | 0 | no --dry-run flag |

---

## Verdict

```
═══════════════════════════════════════════════════════════
VERDICT: ✗ BLOCK

  2 BLOCKERS — both REAL, not stylistic:
    1. IPv6 prefix detection is wrong (line 285/291/297) — central job of
       the script misclassifies ULA / link-local as Public
    2. trap on line 720 has both expansion-time bug AND uses RETURN which
       fires on every function return → triple-cleanup race

  Plus 2 LOGIC errors and 4 suggestions. 4 lint warnings are dead-code
  (SC2034) — non-blocking.

  Before merge / before next DNS peering test on private ranges:
    - Fix the (( )) vs [[ ]] hex comparison
    - Fix the trap (drop RETURN, single-quote it)
    - Audit why SERVER_RESULTS/SERVER_IPS are never read
═══════════════════════════════════════════════════════════
```

---

## How to reproduce this review

```bash
# L1 + L2 automated (review.sh)
/Users/lex/git/knowledge/develop/shell-review/skill/scripts/review.sh \
    /Users/lex/git/knowledge/linux/dns/dns-peering/verify-pub-priv-ip-glm-ipv6.sh

# L4.2 trace on --help path (zero side-effect)
bash -x /Users/lex/git/knowledge/linux/dns/dns-peering/verify-pub-priv-ip-glm-ipv6.sh --help

# L3 — read the script top to bottom, apply the 8-class framework from
# references/methodology.md. This part cannot be automated.
```

---

## What this template teaches about the skill

This is the **shape** of a good review:

1. **Banner line** with target + tier + dialect, so the reader knows the scope immediately
2. **Headline table** with severity / layer / location / one-line headline per finding
3. **Per-layer section** mirroring the methodology (L1 → L2 → L3 → L4)
4. **L3 entries** must reference the L2 finding that surfaced them (e.g. "SC2309 → BLOCKER")
   so the reader can trace why a lint warning escalated to a real bug
5. **Suggested fix** in every BLOCKER/LOGIC entry, copy-paste ready
6. **Impact statement** — what actually breaks in production, not just "this is wrong"
7. **Reproduction recipe** at the bottom so the review is repeatable

If your `shell-review` skill invocations don't produce reports shaped like this, the
skill needs tightening.