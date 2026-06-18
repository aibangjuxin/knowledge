# Shell PR Review — One-Page Checklist

> **Print this. Pin it next to your monitor. Tick each box before approving a Shell PR.**

For the methodology behind each item, see [`methodology.md`](./methodology.md).
For tool installation, see [`tool-stack.md`](./tool-stack.md).

---

## Pre-flight (30 sec)

- [ ] PR contains `.sh` files (not just docs)
- [ ] PR description states what the script does in **one sentence**
- [ ] Diff size: `git diff main...HEAD --stat -- '*.sh'` < 500 lines (else: split or escalate)
- [ ] Author is reachable for follow-up questions

## Layer 1 — Syntax (5 sec)

```bash
for f in $(git diff main...HEAD --name-only -- '*.sh'); do bash -n "$f"; done
```

- [ ] No `syntax error: unexpected end of file` (or equivalent)
- [ ] Each script has `#!/usr/bin/env bash` shebang (or `#!/usr/bin/env sh` if POSIX)
- [ ] `set -euo pipefail` is present (or explicit absence is justified by comment)

## Layer 2.1 — shellcheck (10 sec)

```bash
shellcheck -S warning -x $(git diff main...HEAD --name-only -- '*.sh')
```

- [ ] Zero `error` findings
- [ ] Zero new `warning` findings (pre-existing warnings: check `git log` for blame)
- [ ] All `info`/`style` findings either fixed or `# shellcheck disable=SC…` with comment
- [ ] `SC2015` (`A && B || C`) → **always fix or justify** (lying audit trail)

## Layer 2.2 — Format consistency (5 sec)

```bash
shfmt -d -i 2 -ci -ln bash $(git diff main...HEAD --name-only -- '*.sh')
```

- [ ] No diff output (script is already formatted to repo style)

## Layer 2.4 — Secret / destructive sweep (15 sec)

```bash
git diff main...HEAD -- '*.sh' | grep -E '^\+' \
  | grep -iE 'password\s*=|secret\s*=|api[_-]?key\s*=|token\s*='
git diff main...HEAD -- '*.sh' | grep -E '^\+' \
  | grep -E 'rm\s+(-r|-f|--force)|2>/dev/null'
```

- [ ] No hardcoded credentials in **added** lines
- [ ] No new `rm -rf` outside test/sandbox paths
- [ ] `2>/dev/null` on `gcloud`/`aws`/`curl` is justified (not hiding auth/quota errors)

## Layer 2.5 — Diff scope (15 sec)

```bash
git diff main...HEAD --stat -- '*.sh'
git diff main...HEAD -- '*.sh' | grep -E '^\+' \
  | grep -iE 'TODO|FIXME|XXX|HACK|console\.log|set -x|echo "DEBUG'
```

- [ ] Diff stat looks proportional to PR description
- [ ] No leftover `TODO`/`FIXME`/`echo DEBUG` in added lines

## Layer 3.1 — Logic flow (3 min)

Read the changed lines. Tick for each pattern you find:

- [ ] No `cmd && ok || warn` patterns (SC2015) → rewrite as `if … then … else … fi`
- [ ] No `cd $dir && rm -rf *` (cd-failure fallback to wrong cwd)
- [ ] No `cat file | grep` (useless use of cat → use `grep file`)
- [ ] No `for f in $(ls …)` (whitespace / glob breakage → use `find … -print0`)
- [ ] No `echo $VAR` (word-split → use `echo "$VAR"`)
- [ ] No `[[ -n $UNDEF ]]` style checks where variable may be unset → use `${VAR:-}`

## Layer 3.2 — Data-flow / dependency (3 min)

For multi-step scripts (create / delete / migrate), trace each step:

- [ ] Step N's input validated before step N starts (not after)
- [ ] On step failure, script exits cleanly (no half-committed state)
- [ ] If script fetches secrets at runtime, traced from fetch → use → cleanup
- [ ] No silent dependencies: every external resource referenced has a guard

## Layer 3.3 — Secret handling (1 min)

- [ ] Passwords read from file/stdin, **not** command line (avoid `ps` leak)
- [ ] No `echo $PASSWORD` in any log path
- [ ] base64 of password files uses `echo -n $(cat FILE) | base64` (NOT `base64 FILE`)
- [ ] No credentials in script comments or examples

## Layer 3.4 — Portability (1 min)

```bash
git diff main...HEAD -- '*.sh' | grep -E '^\+' \
  | grep -E 'base64 -w 0|sed -i [^"]|date -d |stat -c'
```

- [ ] No GNU-only flags without portability check (`base64 -w 0` is GNU; macOS needs `-b 99999`)
- [ ] No hardcoded `/tmp/` paths if cross-platform required (macOS symlinks to `/private/tmp`)

## Layer 3.5 — AI logic pass (60 sec, optional but recommended for >100-line PRs)

Paste the diff + full script into LLM with structured prompt asking for:
- `blockers`, `logic_errors`, `suggestions` (JSON)
- One-line `summary`

- [ ] Zero `blockers`
- [ ] Zero `logic_errors` (or reviewer disagrees and writes justification)
- [ ] `suggestions` reviewed; non-blocking

## Layer 4.1 — Dry-run (2 min, for prod-touching scripts)

- [ ] Script supports `--dry-run` OR
- [ ] Traced via `bash -x script.sh 2>&1 | less` (read the trace, confirm intent)
- [ ] Dry-run output reviewed by ≥1 human who did NOT write the script

## Layer 4.2 — Trace (1 min, paranoia)

```bash
PS4='+ ${LINENO}: ' bash -x script.sh 2>&1 | head -100
```

- [ ] Control flow matches what the author claimed
- [ ] No unexpected `set -e` exit points
- [ ] No silent pipefail triggers

## Layer 4.3 — Tests (only if bats exists)

```bash
bats tests/
```

- [ ] All existing tests pass
- [ ] New code path has at least 1 test (if testable)

## Final approval gate

- [ ] All Layer 1–2 boxes ticked (mandatory)
- [ ] All Layer 3 boxes ticked OR each open item has a comment justifying why it's OK
- [ ] At least 1 Layer 4 step performed (dry-run OR trace OR tests) for any script touching prod
- [ ] For destructive scripts (delete / drop / reset): **second human reviewer confirmed**
- [ ] Diff size sanity check passed

---

## Quick reference — the 5-minute review

If you only have 5 minutes for a small Shell PR:

```bash
# 1. syntax (5s)
bash -n script.sh
# 2. shellcheck (10s)
shellcheck -S warning -x script.sh
# 3. secret + rm sweep on diff (15s)
git diff main...HEAD -- '*.sh' | grep -E '^\+' | grep -iE 'password|secret|rm -rf|--force|2>/dev/null'
# 4. SC2015 sweep (5s)
git diff main...HEAD -- '*.sh' | grep -E '^\+' | grep -E '&& .* \|\| '
# 5. AI review (60s)
#    paste the script + diff into LLM
# 6. read changed lines (3 min)
```

Five minutes, six commands, ≥80% of bugs caught.

---

## When to escalate

Don't approve a Shell PR if:

- Diff > 500 lines (ask the author to split or write tests first)
- Script deletes / drops / resets state without `--dry-run` support
- Script reads credentials from CLI args instead of file/stdin
- Script uses `eval`, `bc -l` on user input, or similar injection vectors
- Author refuses to add `set -euo pipefail` (or justify absence)
- No way to verify idempotency (run twice → same end state)