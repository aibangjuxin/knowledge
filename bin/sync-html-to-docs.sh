#!/bin/bash
#
# Sync HTML files from knowledge workspace to docs directory
# - Preserves directory structure
# - Excludes: skills/, docs/, and dot-prefixed directories
# - Generates index.html for each directory for GitHub Pages browsing
# - Commits & pushes to GitHub
#

set -e

BASE_URL="https://aibangjuxin.github.io/knowledge"
SRC="/Users/lex/git/knowledge"
DST="/Users/lex/git/knowledge/docs"
LOG="/Users/lex/git/knowledge/bin/sync-html-to-docs.log"
MANIFEST="/Users/lex/git/knowledge/bin/sync-html-to-docs-manifest.txt"
TMP_MANIFEST=$(mktemp)
GIT_DIR="$SRC/.git"
# Commit author (use repo-configured user)
GIT_AUTHOR_NAME=$(cd "$SRC" && git config user.name)
GIT_AUTHOR_EMAIL=$(cd "$SRC" && git config user.email)

cd "$SRC"

# ──────────────────────────────────────────────
# Helper: generate index.html for a given directory
# ──────────────────────────────────────────────
generate_index() {
  local dir="$1"
  local rel="$2"

  if [[ -n "$rel" ]]; then
    local parent_link="<li><a href=\"../\">../</a> (parent)</li>"
  else
    local parent_link=""
  fi

  local items=""
  while IFS= read -r subdir; do
    local name="$(basename "$subdir")"
    items+="<li><a href=\"$name/\">$name/</a></li>"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

  while IFS= read -r file; do
    local name="$(basename "$file")"
    [[ "$name" != "index.html" ]] || continue
    local file_rel="${rel:+$rel/}$name"
    items+="<li><a href=\"$name\">$name</a></li>"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -name "*.html" 2>/dev/null | sort)

  [[ -n "$items" || -n "$parent_link" ]] || return

  local title="Index of /knowledge${rel:+/$rel}"
  local gen_time=$(date '+%Y-%m-%d %H:%M:%S')

cat > "$dir/index.html" << INDEXEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title</title>
  <style>
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 900px; margin: 40px auto; padding: 0 24px; background: #fafafa; }
    h1 { font-size: 1.4em; color: #333; border-bottom: 2px solid #0066cc; padding-bottom: 10px; margin-bottom: 20px; }
    ul { list-style: none; padding: 0; margin: 0; }
    li { padding: 6px 12px; border-radius: 4px; }
    li:hover { background: #f0f0f0; }
    li a { color: #0066cc; text-decoration: none; font-size: 0.95em; }
    li a:hover { text-decoration: underline; }
    .meta { color: #999; font-size: 0.8em; margin-top: 30px; }
    a.back { display: inline-block; margin-bottom: 16px; color: #666; text-decoration: none; font-size: 0.9em; }
    a.back:hover { color: #0066cc; }
  </style>
</head>
<body>
  <h1>$title</h1>
  <a class="back" href="../">← back</a>
  <ul>
$parent_link$items
  </ul>
  <p class="meta">Generated at $gen_time · <a href="$BASE_URL/${rel:-}">View on GitHub Pages</a></p>
</body>
</html>
INDEXEOF
}

# ──────────────────────────────────────────────
# Step 1: Sync HTML files
# ──────────────────────────────────────────────
total=0
copied=0

while IFS= read -r file; do
    relpath="${file#$SRC/}"
    dest="$DST/$relpath"
    mkdir -p "$(dirname "$dest")"
    if cp "$file" "$dest" 2>/dev/null; then
        echo "$relpath" >> "$TMP_MANIFEST"
        copied=$((copied + 1))
    fi
    total=$((total + 1))
done < <(find "$SRC" \
  -type f -name "*.html" \
  -not -path "*/.git/*" \
  -not -path "*/skills/*" \
  -not -path "*/docs/*" \
  -not -path "*/.*" \
  2>/dev/null)

mv "$TMP_MANIFEST" "$MANIFEST"

# ──────────────────────────────────────────────
# Step 2: Regenerate index.html for ALL directories
# ──────────────────────────────────────────────
find "$DST" -mindepth 1 -type d 2>/dev/null | sort | while IFS= read -r dir; do
  rel="${dir#$DST/}"
  generate_index "$dir" "$rel"
done
generate_index "$DST" ""

# ──────────────────────────────────────────────
# Step 3: Git add / commit / push
# ──────────────────────────────────────────────
cd "$SRC"

# Capture dirty files before staging
dirty_before=$(git status --porcelain docs/)

# Stage docs/ directory
git add docs/

# Check if anything actually changed (git diff --cached returns exit 1 when no changes)
has_changes=$(git diff --cached --name-only docs/ 2>/dev/null | wc -l | tr -d ' ')
changed_files=$(git diff --cached --name-only docs/ 2>/dev/null | tr '\n' ' ')

if [[ "$has_changes" -eq 0 && -z "$dirty_before" ]]; then
    echo ""
    echo "No changes to commit."
    git_status="unchanged"
else
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [[ "$has_changes" -gt 0 ]]; then
        commit_msg="Sync HTML docs ($timestamp) - $has_changes file(s) updated"
    else
        commit_msg="Regenerate index.html ($timestamp)"
    fi

    GIT_AUTHOR_NAME="$GIT_AUTHOR_NAME" \
    GIT_AUTHOR_EMAIL="$GIT_AUTHOR_EMAIL" \
    git commit -m "$commit_msg" -- docs/

    echo ""
    echo "--- Commit created ---"
    echo "$commit_msg"
    echo "Changed: $changed_files"

    git push origin main
    echo "Pushed to GitHub."
    git_status="pushed"
fi

# ──────────────────────────────────────────────
# Step 4: Report
# ──────────────────────────────────────────────
echo ""
echo "========================================"
echo " Sync completed at $(date '+%Y-%m-%d %H:%M:%S')"
echo " Total found: $total | Copied: $copied"
echo " Git status: $git_status"
echo "========================================"

if [[ $copied -gt 0 ]]; then
    echo ""
    echo "--- Recently synced (latest 5) ---"
    tail -5 "$MANIFEST" | while IFS= read -r relpath; do
        echo "$BASE_URL/$relpath"
    done
else
    echo ""
    echo "--- Random 5 examples ---"
    find "$DST" -type f -name "*.html" 2>/dev/null \
        | grep -v "/index.html$" \
        | shuf -n 5 \
        | while IFS= read -r file; do
            relpath="${file#$DST/}"
            echo "$BASE_URL/$relpath"
        done
fi

echo ""
echo "Log: $LOG"
