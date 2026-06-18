# Shell Review — Tool Stack & Selection Matrix

> **Which tool to use when, and what combination covers which scenario.**

Companion to [`methodology.md`](./methodology.md). Methodology is *what to check*;
this doc is *which tools to install and how to combine them*.

---

## Tier 0 — Must-have (install these first)

| Tool | Why | Install (macOS) | Install (Linux) | License | Last verified |
|---|---|---|---|---|---|
| **`bash`** (≥5.x) | script runtime | `brew install bash` | apt: `bash` | GPLv3 | bash 5.2.37 ✅ |
| **`shellcheck`** | the lint standard | `brew install shellcheck` | apt: `shellcheck` | GPLv3 | v0.11.0 ✅ |
| **`shfmt`** | formatter + parser | `brew install shfmt` | go install / binary release | BSD-3 | (already installed) ✅ |
| **`git`** | diff base | already have | already have | GPLv2 | — |

> The above four tools cover Layers 1 + 2 + 2.5 of the methodology. Anything below is optional.

---

## Tier 1 — Strongly recommended (reusable infra scripts)

| Tool | Why | Install (macOS) | License |
|---|---|---|---|
| **`bats-core`** | unit-test framework for Bash | `brew install bats-core` | MIT |
| `bats-support`, `bats-assert`, `bats-file` | assertion libs for bats | `brew install bats-support bats-assert bats-file` | MIT / Apache-2.0 |
| **`shellharden`** | opinionated formatter that fixes quoting bugs | `brew install shellharden` | CC0 |
| **`diffutils`** (GNU `diff`, `colordiff`) | readable diffs | `brew install diffutils colordiff` | GPL |

---

## Tier 2 — Optional / scenario-specific

| Tool | Catches | Install (macOS) | When to use |
|---|---|---|---|
| **`checkbashisms`** | non-portable Bash (POSIX dash-incompat) | `brew install checkbashisms` | script must run on Debian `/bin/sh` |
| **`semgrep`** | security patterns across languages | `brew install semgrep` | repo has multiple languages, want one tool |
| **`trufflehog`** | committed secrets (git history) | `brew install trufflehog` | pre-merge gate for secret leaks |
| **`actionlint`** | GitHub Actions workflow YAML | `brew install actionlint` | if your scripts are invoked by Actions |
| **`shellpop`** | reverse-shell / backdoor patterns | manual install | paranoid security pass |
| **`bandit`** | Python security (cross-lang) | `brew install bandit` | mixed repos |

---

## Tier 3 — Runtime / verification

| Tool | Use case |
|---|---|
| **`bash -x`** | built into bash; trace mode |
| **`hyperfine`** | benchmark shell scripts |
| **`shellbench`** | compare shell implementations |
| **`docker`** / **`podman`** | sandboxed execution |
| **`script`** (BSD util) | record terminal session for audit |

---

## Tool combination matrix

### Scenario A — Personal throwaway script (5-minute review)

| Layer | Tool | Time |
|---|---|---|
| L1 syntax | `bash -n` | <1 s |
| L2.1 lint | `shellcheck -S warning` | <1 s |
| L3.5 AI logic | copy-paste to LLM with prompt | 60 s |

**Total:** ~1 min. Good enough for "I'll only run this once."

### Scenario B — Reusable infra script (your `create-*.sh`, `housekeep-*.sh`)

| Layer | Tool | Time |
|---|---|---|
| L1 syntax | `bash -n` | <1 s |
| L2.1 lint | `shellcheck -S info -x` | 1 s |
| L2.2 format | `shfmt -d -i 2 -ci` | <1 s |
| L2.4 secrets | `grep -nE 'password\|secret\|token' *.sh` | <1 s |
| L2.5 diff | `git diff main...HEAD \| grep -E '^\+'` | <1 s |
| L3.1 logic | manual read | 5 min |
| L3.2 deps | manual trace | 5 min |
| L3.4 portability | `grep -nE 'base64 -w 0\|sed -i ' *.sh` | <1 s |
| L4.1 dry-run | manual run with `--dry-run` | 2 min |
| L4.3 bats | `bats tests/` | 30 s |

**Total:** ~15 min for a single script. Worth it because you'll re-run it.

### Scenario C — PR from a teammate (the question you asked)

Apply Scenario B + add:

| Layer | Tool | Time |
|---|---|---|
| L2.5 diff sweep | `git diff main...HEAD --stat` to see scope | 30 s |
| L3.5 AI second pass | LLM over the **diff only** (faster than whole script) | 60 s |
| L4.2 trace | `bash -x script.sh --dry-run` if you're paranoid | 60 s |

**Total:** ~20 min for a meaningful PR review.

### Scenario D — Production-touching script (destructive ops)

Apply Scenario C + require:

| Layer | Tool | Time |
|---|---|---|
| Second human reviewer | trust + accountability | n/a |
| Audit log | `script -qc 'bash script.sh' run.log` | passive |
| Pre-flight | `git diff main...HEAD -- '*.sh' \| wc -l` — is this a 50-line change or 500? | <1 s |

**Total:** variable. PR review should not approve >500-line Shell PRs without a team
discussion.

---

## Tool cheat sheet — copy-paste one-liners

### Layer 1 — Syntax
```bash
bash -n script.sh && echo OK || echo FAIL
```

### Layer 2.1 — shellcheck
```bash
shellcheck -S warning -x script.sh
shellcheck -S info    script.sh                  # all findings
shellcheck -e SC2086,SC2154 script.sh            # silence noise
shellcheck --shell=bash --severity=warning *.sh  # multiple files
```

### Layer 2.2 — format check
```bash
shfmt -d -i 2 -ci -ln bash script.sh
shfmt -d -i 2 -ci -ln bash scripts/*.sh | head -50  # spot-check
```

### Layer 2.4 — secret sweep
```bash
grep -rnE '(password|passwd|secret|api[_-]?key|token)\s*[:=]\s*["'\''][^"'\'' ]{6,}' scripts/
```

### Layer 2.5 — diff sweep
```bash
git diff main...HEAD -- '*.sh' | grep -E '^\+' | grep -iE 'rm -rf|--force|2>/dev/null|echo \$|password|secret|api[_-]?key'
```

### Layer 3.4 — portability
```bash
# GNU-vs-BSD gotchas
grep -rnE 'base64 -w 0|sed -i [^"]|date -d |stat -c |head -c -[0-9]' scripts/
```

### Layer 4.1 — dry-run
```bash
# If script has --dry-run
script.sh --dry-run
# Else trace
bash -x script.sh 2>&1 | less
```

### Layer 4.3 — bats
```bash
bats tests/                      # run all
bats tests/script.bats -f "idempotent"   # filter by test name
```

---

## Tool-by-tool — what it catches, what it doesn't

### `bash -n`
- ✅ Catches: unmatched braces, `if/fi` imbalance, bad `case`, malformed `[[ ]]`
- ❌ Misses: all logic, all quoting, all runtime behavior

### `shellcheck`
- ✅ Catches: ~400 rules, covering quoting, subshell semantics, common Bash footguns, portability
- ❌ Misses: doesn't follow `source` without `-x`, doesn't understand your CLI tool's semantics, doesn't catch logic flow bugs
- ⚠️ Disable: `# shellcheck disable=SC2086` *with a comment explaining why*. Naked disables = code smell

### `shfmt`
- ✅ Catches: parse errors (heredoc, brace balance), inconsistent style
- ❌ Misses: bugs

### `bats`
- ✅ Catches: regressions, idempotency, error-path correctness
- ❌ Misses: needs the script to expose introspection flags; can't test "no file was modified outside expected paths" without scaffolding

### `semgrep`
- ✅ Catches: security anti-patterns across languages, with custom rules
- ❌ Misses: not a Shell linter (uses generic patterns); overlaps with shellcheck for Bash

### `trufflehog`
- ✅ Catches: real credentials in git history (high-confidence)
- ❌ Misses: not a code linter; only secrets

---

## Tool installation matrix — what to install per role

### Solo developer (your current setup)
- ✅ bash (already)
- ✅ shellcheck (now installed)
- ✅ shfmt (already)
- ✅ git (already)
- ⚠️ bats-core (recommend, 5 min to install + write first test)

### Code reviewer (you, reviewing someone else's PR)
- All of the above, plus:
- ✅ GitHub CLI (`gh`) — for `gh pr diff`, `gh pr checkout`
- ⚠️ `colordiff` — makes diffs readable in terminal

### Team lead (approving PRs to prod-touching scripts)
- All of the above, plus:
- ✅ `semgrep` — cross-language security gate
- ✅ `trufflehog` — pre-merge secret scan
- ⚠️ CI pipeline that runs shellcheck + bats on every PR (out of scope for this doc)

---

## What to NOT install

| Tool | Why skip |
|---|---|
| `bashate` | overlaps with shellcheck, less maintained |
| `shlint` | abandoned since 2015 |
| `lobash` | overkill for review |
| Custom regex-heavy one-liners | false-positive rate kills trust in 2 weeks |

---

## Appendix — verifying your install

```bash
# Quick health check
bash --version | head -1            # ≥5.x for arrays, [[ ]], etc.
shellcheck --version | head -2      # ≥0.8 (0.10+ recommended)
shfmt --version                     # ≥3.x
bats --version                      # ≥1.5 (bats-core)

# One-liner: do they agree on a known-bad script?
cat > /tmp/bad.sh <<'EOF'
#!/usr/bin/env bash
UNQUOTED=$1
echo $UNQUOTED
EOF

bash -n /tmp/bad.sh;                                echo "exit=$?  (expect 0 — bash -n doesn't catch unquoted vars)"
shellcheck /tmp/bad.sh;                             echo "exit=$?  (expect 1 — shellcheck SC2086)"
shfmt -d /tmp/bad.sh >/dev/null;                    echo "exit=$?  (expect 0/1 — format diff only)"
```

If all four behave as expected, your tool stack is healthy.