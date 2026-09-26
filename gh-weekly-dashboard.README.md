# gh-weekly-dashboard.sh — GitHub Weekly Activity Dashboard

> **Author**: project Lead (with architect-gcp design assist)
> **Date**: 2026-09-26
> **Goal**: One-shot generate a beautiful, info-dense GitHub repo weekly dashboard — terminal-direct
> **Upgrade**: ANSI colors + Unicode box drawing + 5 sections + Chinese → English

---

## 1. TL;DR

```bash
# Auto-detect current directory's repo
./gh-weekly-dashboard.sh

# Specify a repo
./gh-weekly-dashboard.sh aibangjuxin/knowledge

# Filter by file extension (e.g. only .md)
./gh-weekly-dashboard.sh aibangjuxin/knowledge md
```

Output: 5 sections in terminal

```
📊 GitHub Weekly Dashboard : aibangjuxin/knowledge
📈 Core Metrics            (commits / PRs / Issues / active contributors)
📅 Daily Activity          (7-day bar chart, UTC)
👥 Top Contributors        (ranking + percentage)
💬 Commit Message Hot Words (top 10 keywords)
```

---

## 2. Visual Design Principles

| Element | Implementation |
|---|---|
| **Title box** | Unicode box drawing `╔══╗ ... ╚══╝` + ANSI bold cyan |
| **Bar chart** | Unicode half-blocks `▁▂▃▄▅▆▇█` + density-based colors (red/yellow/green/grey) |
| **Stats card** | `╭─╮` card frame + colors + emoji badge |
| **Separator** | Unified `─` half-block line (replaces mixed `--` / `==`) |
| **Hot word bars** | block `█` + count + percentage |
| **Color codes** | cyan (title) / green (active) / yellow (medium) / red (warning) / dim (metadata) |

---

## 3. Five Sections Explained

### 3.1 Core Metrics

| Field | GitHub API | Meaning |
|---|---|---|
| Total commits | `GET /repos/{repo}/commits?since=7d` | Total commit count |
| PRs opened/merged | `GET /repos/{repo}/pulls?state=all&since=7d` | Opened vs merged |
| Issues opened/closed | `GET /repos/{repo}/issues?since=7d` (filter PRs) | Opened vs closed |
| Active contributors | aggregate commit author login | Unique authors |

### 3.2 Daily Activity

- One row per day: `YYYY-MM-DD | bar chart | count | activity level`
- Activity level by count:
  - `🟢 peak` (≥ 10 commits)
  - `🟢 active` (8-9 commits)
  - `🟡 normal` (3-7 commits)
  - `🔴 quiet` (1-2 commits)
  - `⚪ off-day` (0 commits)

### 3.3 Top Contributors

- Sorted by commit count
- Shows count + percentage
- Top 5, others collapsed

### 3.4 Commit Message Hot Words

- Extract first word of commit message (verb, lowercased)
- Filter common stop words (the, a, an, to, etc.)
- Top 10

### 3.5 File Extension Filter (optional)

- 2nd arg: file extension (`md` / `yaml` / `go` / `py` etc.)
- Counts commits for files with that extension
- Note: full file-level filter requires N additional API calls (skipped for speed)

---

## 4. Prerequisites

| Tool | Required | Install |
|---|---|---|
| `gh` (GitHub CLI) | ✅ | `brew install gh` / `apt install gh` |
| `gh auth login` | ✅ | `gh auth login` (needs `repo` scope) |
| `jq` | ✅ | `brew install jq` / `apt install jq` |
| `bash 4+` / `zsh` | ✅ | macOS default |
| `bc` | optional | for merge/close rate calculation |

Verify:

```bash
gh --version
gh auth status
jq --version
```

---

## 5. Usage

### 5.1 Default invocation (auto-detect current directory repo)

```bash
cd ~/git/knowledge
./gh-weekly-dashboard.sh
```

### 5.2 Specify a repo

```bash
./gh-weekly-dashboard.sh aibangjuxin/knowledge
./gh-weekly-dashboard.sh istio/istio
```

### 5.3 File extension filter

```bash
# Only count .md commits
./gh-weekly-dashboard.sh aibangjuxin/knowledge md

# Only count .yaml commits
./gh-weekly-dashboard.sh aibangjuxin/knowledge yaml
```

### 5.4 Output redirection

```bash
# Save to file
./gh-weekly-dashboard.sh aibangjuxin/knowledge > weekly-report.txt

# Strip ANSI colors (CI / email friendly)
./gh-weekly-dashboard.sh aibangjuxin/knowledge | sed 's/\x1b\[[0-9;]*m//g'
```

---

## 6. Output Example

```
╔══════════════════════════════════════════════════════════════╗
║ 📊 GitHub Weekly Dashboard : aibangjuxin/knowledge            ║
║ ⏳ Period: 09-19 → 09-26 (last 7 days, UTC)                   ║
╚══════════════════════════════════════════════════════════════╝

╭─ 📈 Core Metrics ───────────────────────────────────────────╮
│ Total commits          : 47                                    │
│ PRs opened / merged    : 12 / 9 (75% merge rate)               │
│ Issues opened / closed : 8 / 6 (75% close rate)               │
│ Active contributors    : 5                                     │
╰──────────────────────────────────────────────────────────────╯

╭─ 📅 Daily Activity ─────────────────────────────────────────╮
│ Mon 09-19 │ 12 │ ██████████████░░░░ │ 🟢 active              │
│ Tue 09-20 │  7 │ ████████░░░░░░░░░░ │ 🟡 normal              │
│ Wed 09-21 │  1 │ █░░░░░░░░░░░░░░░░░░ │ 🔴 quiet               │
│ Thu 09-22 │ 11 │ █████████████░░░░░ │ 🟢 active              │
│ Fri 09-23 │  8 │ ██████████░░░░░░░░░ │ 🟡 normal              │
│ Sat 09-24 │  2 │ ██░░░░░░░░░░░░░░░░░░ │ ⚪ off-day            │
│ Sun 09-25 │ 14 │ ██████████████████ │ 🟢 peak                │
│ Chart key: ▁ 1-2  ▃ 3-4  ▅ 5-6  ▇ 7-9  █ 10+                  │
╰──────────────────────────────────────────────────────────────╯

╭─ 👥 Top Contributors ──────────────────────────────────────╮
│ 1. alice   │ ████████████████████ 18 commits (38%) 🏆        │
│ 2. bob     │ ████████████        12 commits (26%)            │
│ 3. charlie │ ████████             8 commits (17%)             │
│ 4. dave    │ █████                5 commits (11%)             │
│ 5. eve     │ ████                 4 commits (9%)              │
╰──────────────────────────────────────────────────────────────╯

╭─ 💬 Commit Message Hot Words (top 10) ─────────────────────╮
│ fix       │ ████████████ 12                                   │
│ add       │ █████████   9                                     │
│ update    │ ███████     7                                     │
│ doc       │ █████       5                                     │
│ refactor  │ ████        4                                     │
│ remove    │ ███         3                                     │
│ merge     │ ██          2                                     │
│ deploy    │ █           1                                     │
╰──────────────────────────────────────────────────────────────╯

💡 Tip: filter by file extension: ./gh-weekly-dashboard.sh owner/repo md
```

---

## 7. ANSI Color Codes

| ANSI | Usage |
|---|---|
| `\033[1;36m` | Bold cyan — title / headers |
| `\033[1;33m` | Bold yellow — highlights / numbers |
| `\033[1;32m` | Bold green — active / success |
| `\033[1;31m` | Bold red — warning / quiet |
| `\033[1;35m` | Bold magenta — accent (hot words) |
| `\033[2m` | Dim — metadata / off-day |
| `\033[0m` | Reset |

---

## 8. Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Parameter error (no repo, gh not logged in, etc.) |
| 2 | API call failed (permission / network / repo not found) |
| 3 | Data parsing failed (jq pipe failure) |

---

## 9. Known Limitations

| Limitation | Workaround |
|---|---|
| `gh api` rate limit (5000/h for authenticated users) | Cache 1h / add `--paginate` |
| PR/Issue author may differ from commit author | Two separate API calls |
| Commit message contains emoji / multi-language | Use `tr` to lowercase + filter |
| Private repos need `repo` scope | `gh auth refresh -s repo` |
| File-extension filter is metadata-only | Add per-file API fetch if needed |

---

## 10. References

- [GitHub REST API - Commits](https://docs.github.com/en/rest/commits/commits)
- [GitHub REST API - Pulls](https://docs.github.com/en/rest/pulls/pulls)
- [GitHub REST API - Issues](https://docs.github.com/en/rest/issues/issues)
- [GitHub CLI Manual](https://cli.github.com/manual/)
- [jq Manual](https://jqlang.github.io/jq/manual/)

---

*Generated by architect-gcp Bot (design assist) + Lead (implementation) — 2026-09-26.*
*ANSI colors + Unicode box drawing, terminal-direct output, no GUI required.*