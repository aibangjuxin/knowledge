# Waza Skills — Hermes Port (Architecture Profile)

**Date:** 2026-06-15
**Source:** https://github.com/tw93/Waza @ main (commit 2b2811f4)
**Target:** `~/.hermes/profiles/architecture/skills/`
**Status:** ✅ Installed (8/8 skills, all validations passed)

## What Was Installed

8 engineering-discipline skills from tw93/Waza, prefixed with `waza-` to coexist
with your existing skills (`plan`, `systematic-debugging`, `requesting-code-review`,
`english-vocab-push`).

| Skill | Size | Refs | Scripts | Hermes name | Conflict with existing? |
|-------|------|-----:|--------:|-------------|------------------------|
| think | 15.4 KB | 0 | 0 | `waza-think` | `plan` (different angle, both useful) |
| design | 18.3 KB | 5 | 0 | `waza-design` | none (closest is `maitreya` for diagrams) |
| check | 37.7 KB | 3 | 2 | `waza-check` | `requesting-code-review` (overlapping scope) |
| hunt | 18.9 KB | 4 | 0 | `waza-hunt` | `systematic-debugging` (overlapping scope) |
| learn | 10.0 KB | 0 | 0 | `waza-learn` | none |
| read | 8.6 KB | 1 | 4 | `waza-read` | none (you have `ocrmypdf` etc. for PDFs) |
| write | 19.6 KB | 6 | 0 | `waza-write` | `english-vocab-push` (overlapping scope) |
| health | 21.5 KB | 0 | 9 | `waza-health` | none |
| **shared** | 8.0 KB | 0 | 3 | `waza-shared` | — |

Total disk: ~520 KB.

## What Lives Where

```
~/.hermes/profiles/architecture/skills/
├── waza-shared/                  # Shared runtime dependencies
│   ├── scripts/
│   │   ├── check-update.sh       # Daily Waza version check (silent)
│   │   ├── setup-rule.sh         # Source of version number (v3.28.1)
│   │   └── VERSION               # "v3.28.1" — version anchor for update check
│   └── rules/
│       └── durable-context.md    # Memory preflight reference (all 7 skills link here)
├── waza-think/                   # /think — design before building
├── waza-design/                  # /design — UI/aesthetic iteration
├── waza-check/                   # /check — review diff, ship follow-through
├── waza-hunt/                    # /hunt — systematic debugging
├── waza-learn/                   # /learn — six-phase research
├── waza-read/                    # /read — URL/PDF ingestion
├── waza-write/                   # /write — prose polishing (zh/en)
└── waza-health/                  # /health — agent config audit
```

## Adaptations Made

Waza's `SKILL.md` format is designed for Claude Code / Codex. Hermes needs different
frontmatter and runs each skill from a different directory. Adaptations:

1. **Name prefix `waza-`**: avoids router conflicts with existing
   `plan`/`systematic-debugging`/`requesting-code-review`/`english-vocab-push`.
   Load explicitly with `/skill waza-think`. Router will still see the description
   and auto-load when the trigger phrase matches.

2. **Frontmatter enriched**: kept Waza's `description` verbatim (already "Use when …"
   style, 263–329 chars, well under Hermes' 1024 limit). Added `version`, `author`,
   `license`, `metadata.hermes.{tags, related_skills}` to match Hermes peer style.

3. **Path rewrites**: Waza's SKILL.md bodies reference `../../scripts/check-update.sh`
   and `../../rules/durable-context.md`. Rewrote to `../waza-shared/scripts/...` and
   `../waza-shared/rules/...` so they resolve from each skill's directory.

4. **Bundled runtime deps**: copied `scripts/check-update.sh`, `scripts/setup-rule.sh`,
   and `rules/durable-context.md` from upstream into `waza-shared/`. These are the
   only upstream scripts/rules that get invoked at runtime. Dev tooling (build_metadata.py,
   skill_checks.py, validate_package.py, etc.) was **not** copied — it's vendor build
   machinery, not runtime.

5. **Per-skill `references/` + `scripts/`** copied as-is from `skills/<name>/`.
   These are skill-internal support docs and helper scripts (e.g. `check/agents/`,
   `read/scripts/extract-pdf.sh`).

## What Was NOT Touched

- Your existing `plan`, `systematic-debugging`, `requesting-code-review`,
  `english-vocab-push` skills remain unchanged. They are still loaded first by
  the router because their directory names sort before `waza-*`. If you want
  Waza to win on those triggers, rename the locals or use `/skill waza-<name>`
  explicitly.
- `~/.hermes/config.yaml` — no model or skill config touched.
- The `architecture` profile itself — only `skills/` subtree was modified.

## Validation Run

```text
✓ waza-think:  yaml ok, name=waza-think,  desc=269c, body=15373c
✓ waza-design: yaml ok, name=waza-design, desc=272c, body=18279c
✓ waza-check:  yaml ok, name=waza-check,  desc=317c, body=37739c
✓ waza-hunt:   yaml ok, name=waza-hunt,   desc=263c, body=18889c
✓ waza-learn:  yaml ok, name=waza-learn,  desc=289c, body=9985c
✓ waza-read:   yaml ok, name=waza-read,   desc=290c, body=8564c
✓ waza-write:  yaml ok, name=waza-write,  desc=329c, body=19599c
✓ waza-health: yaml ok, name=waza-health, desc=329c, body=21505c

ALL OK
```

All 8 skills pass:
- Frontmatter starts at byte 0 with `---`, closes with `\n---\n`
- `name` matches expected `waza-<name>`
- `description` ≤ 1024 chars
- Total SKILL.md body ≤ 100,000 chars (largest is `waza-check` at 37.7 KB)

## How To Verify In A New Session

The skill loader snapshots at session start, so the **current** session won't see
the new skills. In a new session:

```bash
hermes skills list | grep waza-
# Should print 8 lines
```

Or from chat:

```
/skill waza-think   # explicit load
/skill waza-hunt    # explicit load
```

## Known Limitations

1. **`scripts/check-update.sh` network access is sandboxed** — your Hermes approval
   rules will block the curl to raw.githubusercontent.com without explicit consent.
   The script is designed to fail silently (it does — exit 0), so this is benign:
   you simply won't see "Waza v3.x.y is available" pings. To enable, run
   `bash ~/.hermes/profiles/architecture/skills/waza-shared/scripts/check-update.sh`
   manually once and approve the network call.

2. **No `/skill waza-*` slash command exists in Hermes** — the Waza slash commands
   (`/think`, `/hunt`, etc.) live in Claude Code. In Hermes, all 8 are loaded by
   description-triggered routing (e.g. "怎么设计" or "判断一下" matches `waza-think`)
   or by explicit `/skill waza-<name>`.

3. **Some upstream tools referenced in `waza-check` and `waza-health` are Claude Code
   specific** — e.g. "scan `.claude/rules/*.md`", "`~/.claude/skills/*/SKILL.md`".
   In Hermes those paths don't exist; the skill body mentions them as part of the
   audit checklist. Treat them as "Claude Code surface" instructions — they'll
   naturally no-op in Hermes environments where those paths don't exist.

## Source Of Truth

- Upstream repo: https://github.com/tw93/Waza
- Upstream commit installed: `2b2811f4` (sparse-cloned with `--depth 1`)
- Original Waza skills index: https://github.com/tw93/Waza/blob/main/skills/RESOLVER.md
- Local mirror (full sparse): `/tmp/waza-skill/` (delete anytime — safe to regen)

## Uninstall / Revert

```bash
rm -rf ~/.hermes/profiles/architecture/skills/waza-*
```

This removes all 9 directories (`waza-shared` + 8 skills). No other config touched.