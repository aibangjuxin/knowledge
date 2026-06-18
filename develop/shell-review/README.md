# Shell Review — Knowledge Package

> Everything you need to review a Bash / sh / zsh script before it lands.
> Methodology + tool selection + checklist + worked example.

## Why this exists

Bugs in Shell scripts are high-blast-radius, low-visibility. `set -euo pipefail` is
necessary but not sufficient. `shellcheck` catches ~50% of real bugs. The other 50%
are logic, secret-handling, portability, and runtime-survival issues that no single
tool catches.

This package gives you a **4-layer × 8-class framework** to apply to any Shell PR,
regardless of who wrote it.

## Documents in this folder

| Doc | Audience | Time to read | Purpose |
|---|---|---|---|
| **[methodology.md](./methodology.md)** | Reviewers, leads | 20 min | Master framework: 4 layers × 8 classes of validation, with原理/命令/场景/盲区 for each |
| **[tool-stack.md](./tool-stack.md)** | Reviewers, DevEx | 10 min | Which tools to install, which combinations cover which scenarios |
| **[checklist.md](./checklist.md)** | Reviewers | 5 min (print out) | One-page tick-by-tick review flow |
| **[audit-public-mtls-global-ingress-scripts.md](./audit-public-mtls-global-ingress-scripts.md)** | Anyone | 10 min | Worked example on the 5 GCP scripts in `public-mtls-global-ingress/scripts/` |

## Recommended reading order

1. Read **methodology.md** once to internalize the framework.
2. Pin **checklist.md** for daily use during PR review.
3. Skim **audit-public-mtls-global-ingress-scripts.md** to see methodology in action
   on a real codebase (your own).
4. Reference **tool-stack.md** when you hit an unfamiliar class of bug.

## Quick start — the 5-minute Shell PR review

```bash
# 1. syntax (5s)
bash -n script.sh

# 2. shellcheck (10s)
shellcheck -S warning -x script.sh

# 3. diff sweep for secrets + destructive ops (15s)
git diff main...HEAD -- '*.sh' | grep -E '^\+' \
  | grep -iE 'password|secret|token|rm -rf|--force|2>/dev/null'

# 4. SC2015 sweep (lying audit trail) (5s)
git diff main...HEAD -- '*.sh' | grep -E '^\+' | grep -E '&& .* \|\| '

# 5. AI logic pass (60s) — paste diff into LLM with structured prompt
#    see methodology.md § Layer 3.5

# 6. read the changed lines (3 min)
```

## What this package is **not**

- Not a linter. Use `shellcheck` for that.
- Not a formatter. Use `shfmt` for that.
- Not a runtime. Run your scripts in a sandboxed env.
- Not a CI config. Adapt these patterns to your CI system separately.

## Provenance

Created 2026-06-18 after the `p12.pwd` newline bug reached production
(see `../java/java-auth/p12-decrypt.md`). Initial audit applied to
`gcp/ingress/public-mtls-global-ingress/scripts/` (5 scripts, 1,976 LOC).

Author: Lex. Methodology: standard industry practice + lessons learned from GCP / Bash work.