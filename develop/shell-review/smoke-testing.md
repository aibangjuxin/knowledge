# Smoke Testing for Shell Scripts

> **What "smoke testing" actually means for Bash, why it catches what shellcheck
> can't, and the concrete techniques you can apply in 30 seconds.**

Companion to [`methodology.md`](./methodology.md) § Layer 4 (Runtime).
This document is the **detail layer** — methodology mentions smoke tests as one
option among many; this doc explains the *what*, *why*, *how*, and *when*.

---

## 0. The one-sentence definition

A **smoke test** is a fast, low-effort run of a script (or a simulated run) that
exercises enough of its surface area to prove "the script starts, runs, and
exits the way you expected" — without trying to verify every behavior.

The term comes from electronics: plug in a circuit, apply power, see if any
component catches fire. If it smokes, something's wrong before you go probing
individual resistors.

For shell scripts: run the script (or trace it) on the **cheapest, lowest-risk
input** you can find. If it survives, you can review the rest of the code with
higher confidence. If it doesn't, you stop before wasting 20 minutes reading a
script that's fundamentally broken.

---

## 1. What smoke testing catches (and what it doesn't)

### Catches

- **Startup failures** — missing interpreter, missing dependency, missing env var
- **Argument parsing bugs** — `--foo` accepted but ignored, `--bar` typo silently
  ignored, exit codes wrong
- **Path / quoting bugs that only manifest at runtime** — `$VAR` empty because
  `IFS` ate it, glob expansion gone wrong, `cd` to wrong directory
- **Race conditions in trap / signal handling** — the very class that broke the
  `verify-pub-priv-ip-glm-ipv6.sh` script (see audit, BLOCKER #2)
- **Output format bugs** — JSON missing commas, CSV with extra rows, YAML
  indentation broken
- **Exit code mismatches** — script returns 0 when it should return 1, etc.
- **Helper function bugs** — a refactored helper that compiles cleanly but does
  the wrong thing (the `get_dig_field` regression below)
- **Silent stdout/stderr leaks** — debug `set -x` left on, warning messages
  cluttering the user-visible output

### Does NOT catch

- **Logic bugs in the success path** — smoke test verifies the script starts
  and runs; if the script says "everything is fine" when actually everything is
  broken, smoke test sees the success message and approves
- **Data-dependent bugs** — works on 1 record, breaks on 100 records (boundary
  conditions need real-data tests, not smoke tests)
- **Performance regressions** — smoke test doesn't time anything
- **Concurrency bugs at scale** — smoke test on 2 jobs vs. production with 50
- **Memory / resource leaks over long runs** — smoke test is short by design
- **Subtle semantic bugs** that need a human/AI to interpret the output

**In short:** smoke testing proves "the script is **plausibly correct** and
doesn't immediately blow up." It does not prove "the script **is** correct."

---

## 2. The 5 levels of smoke testing for shell

Ordered from cheapest to most thorough. Pick the highest level your risk class
demands (see [methodology.md](./methodology.md) § "Decision tree").

### Level 1 — `--help` path (10 seconds, zero side effects)

**What:** Run the script with `--help` or `-h`. The script should print usage
and exit 0 without doing anything else.

**What it catches:**
- Missing shebang (script not executable at all)
- `--help` not handled (case statement incomplete → falls through to default
  path → does something destructive)
- Argument parser crashes on the first `--help` it sees
- Syntax error in the usage function (heredoc mismatch)

**What it doesn't catch:**
- Anything about the script's actual behavior

**Command:**
```bash
script.sh --help 2>&1
```

**When to skip:** If the script doesn't document `--help`. (Add it as a fix.)

---

### Level 2 — `bash -n` parse check (1 second, zero execution)

**What:** Run `bash -n script.sh` (or `bash --check`). The shell parses the
script but does NOT execute any of it.

**What it catches:**
- Unmatched `if/fi`, `case/esac`, `{ }`, `( )`, `[[ ]]`
- Missing `do/done`
- Heredoc terminator mismatches
- Invalid `function` syntax
- Generally: any tokenization failure

**What it doesn't catch:**
- Anything semantic. The script can be `bash -n` clean and still try to
  `rm -rf /` at line 42.
- Logic errors
- Undefined variable references (Bash parses `echo $UNDEFINED_VAR` happily)

**Command:**
```bash
bash -n script.sh && echo "parses clean"
```

**When to skip:** Never. This is the cheapest possible check.

---

### Level 3 — `bash -x` trace mode (5–30 seconds, executes the script)

**What:** Run `bash -x script.sh [args]`. The shell executes every line but
**prints each command to stderr** (prefixed with `+ `) before running it. You
get a complete trace of "what the shell actually did."

**What it catches:**
- **The exact set of statements that ran** — versus what the author *claimed*
  would run. Mismatches are bugs.
- `set -e` triggering in unexpected places
- Heredoc expansion differences between registration and execution
- Branch conditions that took an unexpected path
- Variables that ended up empty / wrong value
- Commands that ran with the wrong arguments

**What it doesn't catch:**
- Side effects (the script still did them)
- Bugs in commands that produced correct-looking output

**Command:**
```bash
# Basic trace
bash -x script.sh --help

# Better: line-numbered trace (so you can cross-ref with the source)
PS4='+ ${LINENO}: ' bash -x script.sh --help
```

**When to skip:** When the script has destructive side effects even at the
trace level (e.g. it runs `rm -rf` in the first 3 lines regardless of args).
For those, prefer Level 1 or Level 5.

---

### Level 4 — `--dry-run` (script-specific, 5–60 seconds, no real effects)

**What:** Run the script with its built-in `--dry-run` flag (or `--check`,
`--no-act`, `--simulate`, etc.). The script is responsible for short-circuiting
all destructive / network-bound operations and just printing what it *would*
do.

**What it catches:**
- Argument parser handling of `--dry-run` itself
- The dry-run code path's correctness (does it actually short-circuit?)
- Output format (matches what the real run will produce, modulo data values)
- All the same things as Level 3, but **without the side effects**
- The difference between "what the user asked for" and "what would happen"

**What it doesn't catch:**
- Bugs that only manifest when real data is processed
- Side effects of tools the script invokes (a `--dry-run` that calls `gcloud`
  without `--dry-run` is worse than no `--dry-run`)
- Bugs in the dry-run path itself (which is a real concern — see the audit's
  Issue 9 in the GCP worked example)

**Command:**
```bash
script.sh --dry-run --verbose example.com
```

**When to skip:** When the script doesn't have `--dry-run`. (Add it as a fix —
this is the audit's most common improvement suggestion.)

---

### Level 5 — Sandbox / container execution (1–5 minutes, isolated effects)

**What:** Run the script inside a throwaway container (Docker, podman) with
`--network=none`, no volumes, fake credentials. The script can do whatever it
wants inside the container; the container is destroyed afterward.

**What it catches:**
- Destructive operations that would have hit real infrastructure
- Network calls that you didn't expect
- File system writes outside expected paths
- Process spawning / fork bombs (within resource limits)
- "Actually works on this OS" portability (different glibc, different `awk`,
  different `sed`)

**What it doesn't catch:**
- Anything that requires real API access to validate

**Command:**
```bash
docker run --rm --network=none \
    -v "$PWD":/work -w /work \
    alpine:3 \
    sh -c "apk add --no-cache bash && bash script.sh"
```

**When to skip:** When the script needs real credentials or real network to
produce meaningful output. For those, escalate to a gated production dry-run.

---

### Level 6 — Real run on real data (variable time, full effects)

**What:** Run the script for real, on real data, with real side effects.

**What it catches:** Everything the previous levels couldn't.

**What it doesn't catch:** Race conditions that only show up under load.

**When to use:** Only after Levels 1–5 all pass, and only with appropriate
gating (audit log, dry-run diff reviewed by a second person, rollback script
ready). See [methodology.md](./methodology.md) § 4.5 "Production replay".

**When to skip:** Always, except when explicitly approved.

---

## 3. How to combine levels for a real PR review

The methodology's [decision tree](./methodology.md) maps risk class → required
layers. The smoke-test layer requirements break down as:

| Risk class | Smoke-test levels required | Typical time |
|---|---|---|
| **A — one-shot throwaway** | Level 1 + Level 2 | 10 sec |
| **B — reusable infra script** | Level 1 + Level 2 + Level 3 + (Level 4 if exists) | 1 min |
| **C — teammate's PR** | Level 1 + Level 2 + Level 3 + Level 4 (or Level 5 if no `--dry-run`) | 2–5 min |
| **D — production-touching** | Level 1 + Level 2 + Level 3 + Level 4 + Level 5 + Level 6 (gated) | 10–30 min |

The most common mistake is **jumping from Level 2 straight to Level 6** —
"parses fine, ship it" — and then discovering in production that the script
crashes on a particular input.

---

## 4. The two real lessons from the audit that drove this document

The audit of `verify-pub-priv-ip-glm-ipv6.sh` (see
[`audit-verify-pub-priv-ip-glm-ipv6.md`](./audit-verify-pub-priv-ip-glm-ipv6.md))
discovered TWO bugs that smoke testing exists to prevent, both in the L4
(runtime) layer.

### Lesson 1 — `trap ... RETURN` only fires when you don't expect it to

**Bug:** `trap "rm -rf '$tmpdir'" EXIT RETURN` — `RETURN` is not a real trap
signal in Bash for cleanup. The functions in the script call `return 0`
repeatedly, so `RETURN` would fire on every one of those, attempting `rm -rf
$tmpdir` with a path captured at registration time.

**How smoke testing would have caught it:**

Level 3 (`bash -x`) trace would have shown:
```
+ trap 'rm -rf "/tmp/tmp.abc123"' EXIT
+ query_dns_server ...
+ return 0
+ trap 'rm -rf "/tmp/tmp.abc123"' RETURN    # <-- unexpected
+ rm -rf "/tmp/tmp.abc123"
```

The reviewer sees the `trap ... RETURN` line and either (a) recognizes it as
wrong, or (b) is at least suspicious enough to check Bash docs. Either way,
the bug surfaces in 30 seconds.

**Without smoke testing:** The script "works" on a single domain. The reviewer
sees `set -euo pipefail` + a clean `trap` line and approves. Production
behavior is identical for a single domain, but on multiple domains the
cleanup runs 3+ times and the trap captures stale paths.

### Lesson 2 — Helper functions with awk `-v` break on `NF`

**Bug:** The fixed script introduced a helper:
```bash
get_dig_field() {
  awk -v i="$idx" '{print $i}' <<< "$line"
}
```

When called with `idx="NF"`, awk errors with `illegal field $(NF), name "i"`.
The smoke test on `www.baidu.com` triggered this immediately.

**How smoke testing would have caught it:**

Level 4 (real query smoke test on a known-good domain like `www.baidu.com`)
catches this in 30 seconds. The script either errors out or produces wrong
output. Either way, obvious.

**Without smoke testing:** The script "passes" shellcheck (no SC warnings),
the audit looks clean, and the bug ships. Users discover it the first time
they query any domain that returns dig output (which is every domain).

**The lesson:** **shellcheck cannot catch tool-specific semantics bugs.**
`get_dig_field` parses cleanly. The only way to know it works is to **call it
and observe the output**.

---

## 5. Concrete smoke-test recipes (copy-paste ready)

### Recipe 1 — Minimal 5-second smoke test (any script)

```bash
# Level 1: help path
script.sh --help >/dev/null 2>&1 || echo "FAIL: --help crashed"

# Level 2: parse check
bash -n script.sh || echo "FAIL: parse error"

# Level 3: trace the help path (zero side effects)
PS4='+ ${LINENO}: ' bash -x script.sh --help 2>&1 | head -30
```

If all three succeed, the script is plausibly correct for the "starts and
exits" axis. Move on to deeper review.

### Recipe 2 — `--dry-run` smoke test (when supported)

```bash
# Verify the script accepts --dry-run
script.sh --help 2>&1 | grep -q -- '--dry-run' || echo "WARN: no --dry-run flag"

# Run it
script.sh --dry-run --verbose example.com 2>&1 | head -50
```

Then check the output:
- Does it list the queries it would make?
- Does it match what the author claims the script does?
- Does the control flow look right (no unexpected side-effect mentions)?

### Recipe 3 — Sandbox smoke test (for destructive scripts)

```bash
docker run --rm --network=none \
    -v "$(pwd)/script.sh:/work/script.sh:ro" \
    -w /work \
    alpine:3 \
    sh -c "apk add --no-cache bash && bash /work/script.sh --help"
```

If your script needs specific tools (`dig`, `curl`, `gcloud`), add them to
the install command. Use `--network=none` to prevent real API calls.

### Recipe 4 — Capture-and-compare for idempotency

For scripts that should be idempotent (running twice produces the same end
state):

```bash
# First run (may have side effects, but should be idempotent)
script.sh setup > /tmp/run1.log 2>&1

# Snapshot the result
script.sh describe > /tmp/state1.txt 2>&1

# Second run (should be a no-op)
script.sh setup > /tmp/run2.log 2>&1

# Compare
diff /tmp/run1.log /tmp/run2.log && echo "idempotent ✓"
```

### Recipe 5 — Real-data smoke test (Level 6, gated)

For the final tier of confidence, run on real data with full audit log:

```bash
# Capture the entire tty session (BSD `script` utility)
script -qc 'bash -x script.sh production-input' /tmp/audit.log

# Compare the trace against the author's claim
PS4='+ ${LINENO}: ' bash -x script.sh production-input 2>&1 | \
    diff - /tmp/audit.log
```

Requires: explicit user approval, second reviewer for the trace, rollback
script ready, output diff reviewed by 2 humans. See [methodology.md](./methodology.md)
§ 4.5.

---

## 6. Common pitfalls (and how smoke testing exposes them)

### Pitfall 1 — "shellcheck passes, ship it"

**Trap:** Believing shellcheck is sufficient verification.

**Smoke test exposure:** Run Level 3 (`bash -x`) on a realistic input. Even
with shellcheck-clean code, trace mode often reveals:
- Variables that resolve to empty at runtime (SC2154 catches some, but not all)
- Subshells that swallow exit codes (the SC2155 lesson)
- `cd` to wrong directory because `set -e` didn't fire on the previous failure

**Mitigation:** Always run `bash -x` on at least one path through the script,
even if shellcheck is clean.

### Pitfall 2 — "--dry-run is implemented, trust it"

**Trap:** Adding `--dry-run` to a script doesn't make it safe to run.

**Smoke test exposure:** Audit found exactly this pattern in
[`audit-public-mtls-global-ingress-scripts.md`](./audit-public-mtls-global-ingress-scripts.md)
Issue 9 — the `--dry-run` correctly short-circuits delete operations, but if
someone refactors and accidentally inverts the `if`, the script silently
starts deleting under `--dry-run`.

**Mitigation:** Run `--dry-run` and verify by trace (`bash -x`) that no
destructive operations appear in the trace. Or: use Level 5 (sandbox
container) for paranoid verification.

### Pitfall 3 — "Help path is zero-side-effect, trust it"

**Trap:** Assuming `--help` doesn't do anything.

**Smoke test exposure:** Some scripts accidentally trigger side effects on
the `--help` path (e.g. an unconditional `mkdir -p $cache_dir` before the
case statement). Trace mode shows this immediately.

**Mitigation:** `bash -x script.sh --help` and look for any non-output
operations in the trace (no `mkdir`, `touch`, `curl`, `gcloud`, etc.).

### Pitfall 4 — "Tested on one input, generalize"

**Trap:** Smoke test on one well-known input (e.g. `www.baidu.com`) doesn't
generalize to all inputs.

**Smoke test exposure:** Run on at least 2–3 inputs covering:
- A domain that resolves to public IPs (most domains)
- A domain that resolves to private IPs (need an internal DNS, but worth testing
  if available)
- An invalid domain (NXDOMAIN) to see how the script handles "no answer"

### Pitfall 5 — "The output looks right, approve"

**Trap:** Visual review of output without verifying structure.

**Smoke test exposure:** For structured output (JSON, CSV, YAML), pipe through
a validator:
```bash
script.sh --json example.com | jq . >/dev/null && echo "valid JSON ✓"
script.sh --csv example.com | head -1 | grep -q '^domain,' && echo "valid CSV header ✓"
script.sh --yaml example.com | python3 -c "import yaml,sys; yaml.safe_load(sys.stdin)" && echo "valid YAML ✓"
```

This catches the audit's bug #10 (`208.67.220.220\u001e103.235.46.115` — the
CSV/JSON was malformed in a way that human eyes might miss on first glance).

---

## 7. When smoke testing is NOT enough

Smoke testing is one layer. The full L4 (runtime) layer includes:

| Technique | What it adds beyond smoke testing |
|---|---|
| **bats unit tests** | Per-function assertions; tests for error paths; regression tests |
| **Integration tests** | Script's interaction with real external systems |
| **Property-based testing** | Generate many random inputs, verify invariants hold |
| **Mutation testing** | Intentionally break the script, verify tests catch it |
| **Fuzzing** | Feed malformed input, see what crashes |

For tier D (production-touching) scripts, smoke testing is necessary but **not
sufficient**. You need at least bats tests covering the documented contract,
plus a sandboxed production replay with audit log.

For tier A (one-shot throwaway), smoke testing is usually sufficient — if
the script runs and produces plausible output, ship it.

---

## 8. Quick reference — the smoke-test checklist

For each script you review, verify at minimum:

- [ ] **L1**: `bash -n script.sh` exits 0
- [ ] **L1.5**: `script.sh --help` exits 0 and prints something useful
- [ ] **L3**: `bash -x script.sh --help` shows expected control flow, no
      unexpected side-effect operations
- [ ] **L4**: If `--dry-run` exists, run it; trace it; verify no destructive
      ops in trace
- [ ] **L4**: If no `--dry-run`, run on the cheapest real input available;
      verify output is plausible
- [ ] **L4.5**: For tier D, also run in sandbox container with `--network=none`

Time budget for each review:

| Tier | Total smoke-test time |
|---|---|
| A | 10 sec |
| B | 1 min |
| C | 2–5 min |
| D | 10–30 min |

---

## 9. What this document is NOT

- **Not a substitute for unit tests.** See `bats` (Tier 1 in
  [tool-stack.md](./tool-stack.md)) for that.
- **Not a substitute for human review.** L3 (semantic) in the methodology
  still requires a human or AI to read the script.
- **Not exhaustive.** A smoke test proves "the script is plausibly correct,"
  not "the script is correct." Use it as a fast filter, not a final say.
- **Not specific to Bash.** The principles apply to sh, zsh, ksh, and most
  shell languages. Bash-specific Level 3 (`bash -x`) becomes `set -x` or
  `zsh -x` for other dialects.

---

## Provenance

Created 2026-06-19 after the `verify-pub-priv-ip-glm-ipv6.sh` audit found
TWO real bugs (trap RETURN race + `get_dig_field` NF failure) that **only
Level 3+ smoke testing could catch**, despite the script being shellcheck-clean
and structured.

Author: Lex (with Claude/agent assistance for initial draft). Methodology:
industry standard, adapted to the 4-layer × 8-class framework in
[methodology.md](./methodology.md).