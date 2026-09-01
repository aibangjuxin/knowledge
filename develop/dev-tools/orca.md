# Orca — Worktree-Native IDE for Parallel AI Coding Agents

**Date:** 2026-09-01
**Source:** https://github.com/stablyai/orca (MIT, 58.8k★) · https://onorca.dev/docs
**Tagline:** "The worktree IDE for AI coding agents. Run Claude Code, Codex, and OpenCode side by side with worktree isolation, fast previews, diff review, and real-time agent status."
**Status:** Documented; not yet installed locally (`which orca` → no result)

## What It Is (60-second pitch)

Orca is a desktop IDE (Electron + VS Code's Monaco editor under the hood) whose
**fundamental unit is the git worktree, not the file or the branch**. Every task
gets:

- its own on-disk copy of the repo via `git worktree`
- its own agent terminal (Claude Code, Codex, Cursor CLI, OpenCode, Pi — any CLI agent)
- its own browser tab
- its own branch, isolated file state, and isolated agent session

The headline use case is "fan one prompt across N agents, each in its own
worktree, compare the results, merge the winner". This is the "100x builder"
workflow Orca is marketed for.

## Why It Matters for This Stack

Three features directly answer the gaps that the current `develop/` workflow has:

| Pain today | How Orca addresses it |
|---|---|
| Juggling `git stash` / `git checkout` to run 2+ agents in parallel on the same repo | Every task = its own worktree. No stashing. No branch collisions. |
| Reviewing agent output as raw text in a terminal | Monaco-based diff view with side-by-side comparison, inline comments, PR/CI status surfaced in-app |
| Writing Markdown (notes, ADRs, READMEs) in plain VS Code with no live preview | Rich Markdown editor with slash menu, inline image/code previews, wiki-style `[[link]]` autocomplete, table of contents |

Plus features that overlap with tools already on this machine:

- **Terminal splits** (Ghostty-class, WebGL rendering, scrollback that survives restarts — overlaps with `~/git/knowledge/linux/Ghostty/`)
- **SSH worktrees** (run agents on a remote box with auto-reconnect — overlaps with the
  VPS / NAS work in `linux/nas/`)
- **Quick-open palette** (`Cmd-J`, Jump Palette across worktrees / files / agents / commands)
- **PR / Linear / Jira / GitLab issue integration** (browse tasks in-app, open a worktree from any task)
- **Mobile companion** (iOS / Android app that mirrors active agents — distinct from
  the `macos/iPad` / `macos/ios` notes)
- **Account switcher + usage tracking** for Claude / Codex rate limits

## The Core Concept: Worktree-Native

```
┌──────────────────────────────────────────────────────────┐
│  Orca sidebar (one entry per worktree, grouped by repo)  │
├──────────────────────────────────────────────────────────┤
│  📁 knowledge/                                           │
│    ├─ 🌿 docs-refresh   (Claude Code, branched off main) │
│    ├─ 🌿 orca-eval      (Codex,      branched off main) │
│    └─ 🌿 k8s-gateway    (OpenCode,   branched off main) │
│  📁 gcp/                                                 │
│    └─ 🌿 asm-mtls-fix   (Claude Code)                    │
└──────────────────────────────────────────────────────────┘
        ↓   each workspace is a real `git worktree add`
┌──────────────────────────────────────────────────────────┐
│  ~/git/knowledge.worktrees/docs-refresh/                 │
│  ~/git/knowledge.worktrees/orca-eval/                    │
│  ~/git/knowledge.worktrees/k8s-gateway/                  │
└──────────────────────────────────────────────────────────┘
```

Key model facts (from the official docs):

- Each repo has a **base ref** (usually `origin/main`).
- Each worktree has a **start-from ref** (what it branches off).
- Each worktree has its own branch, its own files on disk, and its own agent
  terminal. Deleting a worktree removes both the directory and the branch (with
  confirmation). If git refuses to drop the branch because it may have unmerged
  commits, Orca surfaces a "Review N Branches" step before force-deleting.
- You can `cd` into a worktree and use `git status`, `git rebase`, `git cherry-pick`
  freely — Orca picks up the changes on next render. Worktrees you create yourself
  with `git worktree add` stay external until you opt them into the Orca sidebar.
- A worktree created in Orca is *exactly* a `git worktree` on disk — nothing
  custom, nothing proprietary, fully portable.

### Shared directories & gitignored files

A fresh worktree has no `node_modules`, no `.env`, no `.cache`. Orca fills that gap
in three complementary ways:

1. **Per-user Worktree Shared Paths** (UI setting) — applied to every worktree you create
2. **`orca.yaml` `worktree.sharedDirectories`** — repo-level config that *adds to* (never replaces) the per-user list
3. **`.worktreeinclude`** — gitignore-syntax file checked into the repo, listing paths to symlink into new worktrees (e.g. `.env`, `.env.local`, `.vscode/settings.json`)

```yaml
# orca.yaml (repo root)
worktree:
  sharedDirectories:
    - node_modules
    - .cache
```

```
# .worktreeinclude (repo root)
.env
.env.local
.vscode/settings.json
```

## The Three Headline Features (the ones you mentioned)

### 1. Diff view

`orca file diff <path> [--staged]` opens a file in the diff view of the active
worktree. `orca file open-changed --mode both` shows every changed file. From the
GUI, the diff panel is a side-by-side Monaco diff with inline comments, and PR /
CI status is surfaced in the same view (no context switch to GitHub).

### 2. Markdown preview

Markdown files open in a rich editor by default with:

- **Slash menu** (`/` on empty line) — headings, lists, code blocks, callouts, images, mermaid diagrams, toggle blocks (`/toggle-text`, `/toggle-h1` … `/toggle-h5` saves as portable `<details>` / `<summary>`)
- **Wiki-style internal links** (`[[` autocompletes file paths within the worktree)
- **Search** that matches rendered text, not raw markdown (`# Install` and `<h1>Install</h1>` both match "Install")
- **Inline previews** for images and code
- **TOC** pinned to the left of the editor for long docs
- **Front matter** (YAML/TOML) shown in both editor and rendered preview; toggleable per-file
- **Review annotations** — select rendered text to add a comment without switching to raw markdown (`Cmd-Shift-A` / `Ctrl-Shift-A`, remappable)
- **Rich table editing** — Tab/Enter/Backspace follow standard spreadsheet-ish behavior; one-click row/column insert/delete in the toolbar
- **Toggle to raw Monaco** with `Cmd-Shift-M` anytime

For files larger than 300 KB Orca opens the raw editor first to keep typing
responsive; an "Open anyway" banner in the raw editor lets you opt into the rich
editor for that file (the choice lasts until the tab closes).

This is *strictly more capable* than VS Code's default Markdown preview, and
*much more capable* than editing in Vim / Neovim without a plugin.

### 3. Worktree management

The Create Worktree dialog submits and closes immediately — `git fetch` + `git
worktree add` runs in the background while you keep using Orca. The new worktree
appears in the sidebar with a progress row, and the worktree's tab shows live
setup status until checkout finishes and swaps to the terminal.

**Start-from picker** lets you branch off:

- a base branch (`main`, `develop`, etc.)
- another active worktree in the same repo (creates a parent/child lineage in the sidebar — does not change git history)
- a tracked work item (GitHub PR, GitHub issue, Linear issue, Jira issue, GitLab MR) — branch name is auto-derived from that item

**Emoji workspace names** — Slack-style `:rocket:` shortcodes work in the name
field. The display name keeps the emoji; the derived git branch rewrites 🚀 → `rocket`.

**Deletion keyboard shortcut**: hover a worktree and press `Cmd-Shift-Backspace`
(macOS) / `Ctrl-Shift-Backspace` (Linux/Win). Confirmation dialog still appears.
Multi-select with `Cmd`-click / `Shift`-click applies the action to every
selected worktree.

**Resource Manager → Clean up workspaces** — review workspaces across local +
main + folder + disconnected-SSH hosts before bulk removal; shows status,
recent activity, size, Git state, and linked review per workspace.

## Orca CLI — the scripting surface

The `orca` CLI ships with the desktop app and exposes everything from a shell:

```bash
# Install & verify
command -v orca
orca status --json

# Worktrees
orca worktree ps --json
orca worktree create --repo id:<repoId> --name my-task --issue 123 --json
orca worktree current --json
orca worktree set --worktree active --comment "reproduced bug" --json
orca worktree rm --worktree id:<id> --force --json

# Terminals (drive agent terminals from a shell)
orca terminal list --json
orca terminal send --text "continue" --enter --json
orca terminal wait --for tui-idle --timeout-ms 30000 --json
orca terminal create --worktree path:/projects/app --command "npm test" --json
orca terminal split --direction vertical --command "npm run dev" --json

# Files & diffs
orca file open src/App.tsx
orca file diff src/App.tsx --staged
orca file open-changed --mode both

# Browser automation (snapshot-interact-re-snapshot)
orca goto --url https://example.com --json
orca snapshot --json            # returns refs like @e1, @e3
orca click --element @e3 --json
orca fill --element @e1 --value "you@example.com" --json
orca screenshot --json
orca set device --name "iPhone 12" --json

# iOS Simulator (mobile emulator bridge)
orca emulator list --json
orca emulator attach "iPhone 15" --json
orca emulator tap 0.5 0.7 --json
orca emulator type "hello" --json
orca emulator rotate landscape_left --json
orca emulator kill --json

# Artifacts (opt-in public view links for HTML / Markdown)
orca artifacts share|update|list|delete
```

**Agents can install the matching CLI skill**:

```bash
npx skills add https://github.com/stablyai/orca --skill orca-cli
# or headless (no Settings panel):
orca skills install --skill orca-cli
```

This is the integration point with Hermes — install `orca-cli` as a Hermes skill
and the agent can drive Orca worktrees from any session, the same way it drives
Git / GitHub / gcloud today.

## How It Compares to the Current Stack

| Layer | Today | Orca |
|---|---|---|
| Editor for Markdown | VS Code + plugins listed in `develop/vscode/plug.md` | Monaco-based rich editor with live preview, slash menu, wiki links, TOC — built-in (no plugin install) |
| Diff review | `git diff` in terminal or VS Code side panel | Side-by-side Monaco diff + inline comments + PR/CI status in the same view |
| Worktree management | `git worktree add` manually, or no worktree (single checkout + stash) | First-class: each task = its own worktree, sidebar-driven, GUI + CLI |
| Multi-agent parallel runs | One terminal at a time; switch manually between sessions | N worktrees, N agent terminals, each isolated — fan out, compare, merge |
| Terminal | Ghostty + splits | Ghostty-class terminals (WebGL rendering, infinite splits, scrollback that survives restarts) — note: Orca is not a Ghostty replacement, it embeds a similar terminal renderer inside the IDE |
| Remote work | SSH from local terminal | SSH worktrees — run agents on a remote box with full file editing, git, terminals; auto-reconnect and port forwarding |
| Notifications | imsg (`imessage` skill) for end-of-task pings | In-app unread state for agent threads + mobile companion app + native notifications |
| Mobile control | None | Mobile app mirrors active agents — see status, push prompts, receive notifications |

## Open Questions Worth Investigating Before Adopting

1. **License / pricing**: GitHub repo is MIT, but the desktop app distribution and
   the mobile companion may have paid tiers. Verify at `https://onorca.dev/pricing`
   before assuming free for personal use.
2. **Hermes ↔ Orca CLI skill maturity**: the `orca-cli` skill is the integration
   point. Check that it covers the workflows the agent actually needs
   (`worktree create`, `terminal send`, `file diff`) before installing.
3. **iCloud sync interaction with `~/.git/fsmonitor--daemon`**: this knowledge repo
   already uses Git's fsmonitor. Verify Orca does not conflict with that daemon
   when scanning worktrees.
4. **Worktree overlap with `.worktrees/`**: `~/git/knowledge/.worktrees/` already
   exists for manual git worktrees. Decide whether Orca worktrees live in the
   same dir (recommended — visible to plain `git worktree list`) or in Orca's own
   location.
5. **Multi-account rate limit tracking**: Orca's account switcher / usage tracking
   for Claude + Codex is interesting; compare with what `~/.hermes` already
   tracks in `mmx quota show`.

## Authority / Sources

- **GitHub repo**: https://github.com/stablyai/orca (MIT, 58.8k★, 4.0k forks) — README, AGENTS.md, CLAUDE.md all in-tree
- **Docs root**: https://onorca.dev/docs
- **Worktrees concept doc**: https://onorca.dev/docs/model/worktrees
- **CLI overview**: https://onorca.dev/docs/cli/overview
- **Rich Markdown editor**: https://onorca.dev/docs/editing/markdown
- **Changelog (real feature list, ships daily)**: https://github.com/stablyai/orca/releases

> **Name-collision warning**: `docs.orca.so` (and `www.orca.so`) is an unrelated
> Solana DEX project. The AI coding IDE is at **`onorca.dev`** / GitHub
> `stablyai/orca`. Don't confuse the two — the search results mix them up.