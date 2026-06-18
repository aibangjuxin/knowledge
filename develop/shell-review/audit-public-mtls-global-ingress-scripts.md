# Shell Script Audit — `public-mtls-global-ingress/scripts/`

**Audit date:** 2026-06-18
**Auditor:** automated (shellcheck 0.11.0 + custom rule sweep) + manual logic pass
**Scope:** 5 Bash scripts, 1,976 LOC total
**Methodology:** see [methodology.md](./methodology.md)

This document is a **review, not a patch list**. No files were modified.
The author (Lex) must approve before any change is applied.

---

## TL;DR — Headline Findings

| # | Severity | Class | Files affected | Headline |
|---|----------|-------|----------------|----------|
| 1 | **HIGH** | Logic (SC2015) | 2 housekeep scripts, 7 occurrences | `A && B \|\| C` pattern mis-classifies failures in delete paths |
| 2 | **MED** | Idiom (SC2012) | `e2e-test.sh`, 3 occurrences | `ls -d …/* \| head -1` is unsafe with spaces / non-ASCII filenames |
| 3 | **MED** | Logic | `e2e-test.sh:93` | `--quiet` flag parsed but never read |
| 4 | **LOW** | Dead code (SC2034) | 4 scripts, 4 occurrences | Unused color vars (`DIM`, `RED`) / unused flag (`QUIET`) |
| 5 | **LOW** | Idiom (SC2016) | `e2e-test.sh:402`, 2 occurrences | Single-quoted grep pattern, may be intentional |
| 6 | **INFO** | Hygiene | 1 script, `cleanup_yaml` | `mktemp` cleanup good ✅ |

**No HIGH-severity secrets, no rm -rf footguns, no unquoted `set -euo pipefail`.**
The 5 scripts are already in reasonable shape — most findings are micro-improvements.

---

## Tier 1 — Syntax (bash -n)

```
✓ e2e-test.sh                                          parses
✓ lex-poc-create-consumer-resource-global.sh          parses
✓ lex-poc-create-producer-resource-global.sh          parses
✓ lex-poc-housekeep-consumer-resource-global.sh       parses
✓ lex-poc-housekeep-producer-resource-global.sh       parses
```

All 5 scripts pass `bash -n`. ✅

**Confirmation:** every script begins with `#!/usr/bin/env bash`, declares `set -euo pipefail`,
and uses `mktemp -d` + `trap … EXIT` for temp-dir cleanup (only `lex-poc-create-consumer-resource-global.sh:144-146`).

---

## Tier 2 — Static analysis (shellcheck -S style)

Total findings: **25** across 5 files.

### Issue 1 — `A && B || C` is not if-then-else  [HIGH, 7 occurrences]

**Where:**

```
lex-poc-housekeep-consumer-resource-global.sh:123, 136, 149, 162, 175
lex-poc-housekeep-producer-resource-global.sh:65, 115
```

**Pattern:**
```bash
gcloud compute "$kind" delete "$name" --project="$PROJECT" --region="$REGION" --quiet 2>/dev/null \
  && ok "deleted $kind $name" \
  || warn "failed to delete $kind $name"
```

**Why it matters (this is the secret bug):**
`A && B || C` means *"B; if B fails, C"*, not *"if A succeeds then B else C"*.
If `gcloud` succeeds (exit 0) but `ok` somehow returns non-zero
(terminal disconnected, stdout closed, `set -e` racing),
the `||` will trigger and you'll **log `failed to delete` for a resource that was actually deleted**.
For a `delete` script this is a **lying audit trail** — operator thinks delete failed, retries,
and may try to delete a now-deleted resource (idempotent on GCP API but produces confusing logs).

**Other path of failure:** if `gcloud` returns 0 but `ok`'s `printf` hits a broken pipe,
the script enters `set -e` cascade via the `||` falling through.

**Suggested fix (do NOT apply yet):**
```bash
if gcloud compute "$kind" delete "$name" --project="$PROJECT" --region="$REGION" --quiet 2>/dev/null; then
  ok "deleted $kind $name"
else
  warn "failed to delete $kind $name (rc=$?)"
fi
```

---

### Issue 2 — `ls -d "${TR_DIR}/${sc}-"*` is unsafe  [MED, 3 occurrences]

**Where:**
```
e2e-test.sh:393, 414, 471
```

**Pattern:**
```bash
sc_dir=$(ls -d "${TR_DIR}/${sc}-"* 2>/dev/null | head -1 || echo "")
```

**Why it matters:**
`ls` output is for humans. If a directory entry contains whitespace, newlines, or glob
characters, `$(ls …)` will:
- split on whitespace → wrong path
- glob-expand → wrong file captured
- silently swallow the error via `2>/dev/null`, hiding the bug

**Suggested fix:**
```bash
sc_dir=$(find "${TR_DIR}" -maxdepth 1 -name "${sc}-*" -print -quit 2>/dev/null)
[[ -z "$sc_dir" ]] && sc_dir=""
```

---

### Issue 3 — `--quiet` flag parsed but never read  [MED]

**Where:** `e2e-test.sh:93`

**Pattern:**
```bash
--quiet) QUIET=true ;;
```
…and `QUIET` is never referenced anywhere else in the file (SC2034 confirms).

**Why it matters:** silently accepted flag → operator thinks they suppressed output,
script prints everything anyway → misleading UX. Two equally valid fixes:

**Option A** (delete dead code):
```bash
# remove both the --quiet case AND the QUIET=true line
```

**Option B** (implement — recommended for actual use):
```bash
--quiet) QUIET=true; exec 1>/dev/null ;;   # or wire QUIET into the step/ok/… funcs
```

---

### Issue 4 — Unused color variables  [LOW, 4 occurrences]

**Where:**
```
e2e-test.sh:37                                     DIM declared, never used
lex-poc-create-consumer-resource-global.sh:40     DIM declared, never used
lex-poc-create-producer-resource-global.sh:45     DIM declared, never used
lex-poc-housekeep-producer-resource-global.sh:16  RED declared, never used
```

**Pattern:** color branch declares more variables than it uses.

**Why it matters:** low signal-to-noise; future reader assumes DIM/RED must do something.

**Suggested fix:** remove the unused name from each declaration line.

---

### Issue 5 — Single-quoted grep patterns  [LOW, 2 occurrences]

**Where:** `e2e-test.sh:402`

**Pattern:**
```bash
expected=$(grep -oE 'Expected outcome: `[^`]+`' "${summary}" | head -1 \
           | sed 's/Expected outcome: `//; s/`//' || echo "?")
```

**Why it matters:** SC2016 warns that `${VAR}` inside single quotes won't expand.
Here it's used in a grep pattern, so single-quoting is *intentional and correct* (you want
a literal `{` `}` grep pattern, not variable expansion). The warning is a false positive.

**Suggested fix:** add `# shellcheck disable=SC2016` above the line with a comment,
or rewrite to silence cleanly:
```bash
# shellcheck disable=SC2016  # single-quoted grep pattern is intentional
expected=$(grep -oE 'Expected outcome: `[^`]+`' "${summary}" | …
```

---

## Tier 3 — Custom rule sweep (Lex/GCP-flavored)

These are rules **shellcheck doesn't catch** but you said matter for your platform.

### Issue 6 — `gcloud … 2>/dev/null` swallows auth / quota errors  [LOW]

**Where:**
```
e2e-test.sh                                              1×
lex-poc-create-consumer-resource-global.sh              1×
lex-poc-create-producer-resource-global.sh              1×
lex-poc-housekeep-consumer-resource-global.sh           5×
lex-poc-housekeep-producer-resource-global.sh           2×
```

**Pattern:**
```bash
gcloud compute … delete … --quiet 2>/dev/null
```

**Why it matters:** redirecting gcloud stderr to `/dev/null` hides
- `ERROR: (gcloud.auth.compute) Invalid credentials`
- `ERROR: Quota exceeded`
- `ERROR: API [compute.googleapis.com] not enabled`
- `--quiet` suppressing the y/N prompt also suppresses the API error context

For create-scripts (your `create-*.sh` family) the `2>/dev/null` only appears once each
and is probably paired with a fallback — fine. For housekeep scripts the `2>/dev/null` hides
*"the resource didn't exist so delete is a no-op"* **and also** *"the resource exists but you
can't delete it because of an IAM/quota error"*. You can't tell them apart.

**Suggested fix (do NOT apply yet):** drop the `2>/dev/null` and let stderr land in the log;
if a specific call is "expected to fail because the resource is already gone", guard with
`describe` first (which the code already does — making the `2>/dev/null` redundant).

---

### Issue 7 — Housekeep scripts: no `--dry-run` consistency check  [LOW]

**Where:**
```
lex-poc-housekeep-consumer-resource-global.sh   has --dry-run + --force (good ✅)
lex-poc-housekeep-producer-resource-global.sh   has --dry-run + --force (good ✅)
```

Both housekeep scripts correctly support `--dry-run`. **No action needed**;
flagged here only to confirm the methodology covered it.

---

### Issue 8 — `trap … EXIT` cleanup present ✅  [INFO, positive finding]

**Where:** `lex-poc-create-consumer-resource-global.sh:144-146`
```bash
YAML_DIR="$(mktemp -d -t lex-poc-yaml.XXXXXX)"
cleanup_yaml() { rm -rf "$YAML_DIR"; }
trap cleanup_yaml EXIT
```

Correct pattern — temp directory cleaned up on any exit path.
The other create script (`lex-poc-create-producer-resource-global.sh`) does NOT use
`mktemp` — its YAML is committed to `$dir/*.yaml` for debugging — which is a different
deliberate design. **No action needed.**

---

## Tier 4 — Manual logic pass

A short read of the housekeep scripts surfaced these semantic observations
(separate from shellcheck):

### Issue 9 — Housekeep scripts never verify `--dry-run` actually means "no API call"

**Where:** `lex-poc-housekeep-{consumer,producer}-resource-global.sh` `delete_regional()`

**Pattern:**
```bash
delete_regional() {
  local kind="$1" name="$2"
  if $DRY_RUN; then
    info "[dry-run] would delete $kind $name"
  else
    if gcloud compute "$kind" describe "$name" …; then
      gcloud compute "$kind" delete …   # ← really deletes
    fi
  fi
}
```

**Why it matters:** correctly short-circuits. ✅ **No action needed.**
But: if someone refactors and accidentally inverts the `if`, the script silently
starts deleting under `--dry-run`. A belt-and-suspenders guard would be:
```bash
delete_regional() {
  local kind="$1" name="$2"
  if $DRY_RUN; then
    info "[dry-run] would delete $kind $name"
    return 0
  fi
  # …actual delete path…
}
```

---

### Issue 10 — `set -e` + `&& ok || warn` interaction (related to Issue 1)

When `set -e` is active and `A && B || C` is used inside an `if`, the rule that
*"a failing command inside `if` does not trigger exit"* protects you.
But once you write `A && B || C` at top level, `set -e` *will* react to the failure
of the chain, in subtle ways. Worth pinning down before any future refactor.

---

## Summary table — by script

| Script | LOC | Tier 1 | Tier 2 | Tier 3 / 4 | Net verdict |
|---|---|---|---|---|---|
| `e2e-test.sh` | 489 | ✅ | 10 (3 SC2012, 4 SC2034, 3 SC2016) | 1× gcloud `2>/dev/null` | Clean syntax; medium-priority hygiene (Issues 2, 3) |
| `lex-poc-create-consumer-resource-global.sh` | 656 | ✅ | 2 (SC2034) | `trap` cleanup ✅ | Solid. Minor dead code. |
| `lex-poc-create-producer-resource-global.sh` | 391 | ✅ | 2 (SC2034) | — | Solid. Minor dead code. |
| `lex-poc-housekeep-consumer-resource-global.sh` | 287 | ✅ | 6 (5 SC2015, 1 SC2034) | 5× `2>/dev/null` on delete | **Highest-risk file** (delete path with lying audit trail). Fix Issue 1 first. |
| `lex-poc-housekeep-producer-resource-global.sh` | 153 | ✅ | 5 (2 SC2015, 3 SC2034) | 2× `2>/dev/null` on delete | Same risk class as consumer housekeep. |

---

## Recommended fix order (when Lex approves)

1. **Issue 1** (SC2015 in housekeep scripts) — rewrite `&& B || C` to `if … then … else … fi`.
   Highest information value per minute of work; prevents silent audit-log corruption.
2. **Issue 3** (`--quiet` in `e2e-test.sh`) — either implement or delete. 30 seconds.
3. **Issue 2** (`ls` → `find`) in `e2e-test.sh`. Mechanical replacement.
4. **Issue 4** (unused color vars) — mechanical cleanup.
5. **Issue 6** (drop `2>/dev/null` on gcloud in housekeep) — *discuss first*; this changes
   output verbosity and may need a `--quiet` flag added to compensate.

**Confirm before I apply any of these.** Per the review-only mode of this audit,
no file has been modified.