#!/bin/bash
#
# Sync HTML files from knowledge workspace to docs directory
# - Preserves directory structure
# - Excludes: skills/, docs/, and dot-prefixed directories
# - Generates index.html for each directory for GitHub Pages browsing
#

BASE_URL="https://aibangjuxin.github.io/knowledge"
SRC="/Users/lex/git/knowledge"
DST="/Users/lex/git/knowledge/docs"
LOG="/Users/lex/git/knowledge/bin/sync-html-to-docs.log"
MANIFEST="/Users/lex/git/knowledge/bin/sync-html-to-docs-manifest.txt"
TMP_MANIFEST=$(mktemp)

# ──────────────────────────────────────────────
# Helper: generate index.html for a given directory
# ──────────────────────────────────────────────
generate_index() {
  local dir="$1"        # absolute path, e.g. /Users/lex/git/knowledge/docs/dns
  local rel="$2"        # relative path from DST, e.g. dns  (empty means root)

  # Build parent path for ".." link
  if [[ -n "$rel" ]]; then
    local parent_rel="../"
    local parent_link="<li><a href=\"../\">../</a> (parent)</li>"
  else
    local parent_rel=""
    local parent_link=""
  fi

  # Collect items (subdirs first, then files), sorted
  local items=""
  local item_html=""

  # Subdirectories
  while IFS= read -r subdir; do
    local name="$(basename "$subdir")"
    local sub_rel="${rel:+$rel/}$name"
    items+="<li><a href=\"$name/\">$name/</a></li>"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

  # HTML files (skip index.html itself to avoid self-reference)
  while IFS= read -r file; do
    local name="$(basename "$file")"
    if [[ "$name" != "index.html" ]]; then
      local file_rel="${rel:+$rel/}$name"
      items+="<li><a href=\"$name\">$name</a></li>"
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -name "*.html" 2>/dev/null | sort)

  # Only generate index if directory has content
  if [[ -z "$items" && -z "$parent_link" ]]; then
    return
  fi

  # Build the page title
  local title="Index of /knowledge${rel:+/$rel}"

  local index_content="<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>$title</title>
  <style>
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 900px; margin: 40px auto; padding: 0 24px; background: #fafafa; }
    h1 { font-size: 1.4em; color: #333; border-bottom: 2px solid #0066cc; padding-bottom: 10px; margin-bottom: 20px; }
    h1 span { color: #888; font-weight: normal; font-size: 0.8em; }
    ul { list-style: none; padding: 0; margin: 0; }
    li { padding: 6px 12px; border-radius: 4px; }
    li:hover { background: #f0f0f0; }
    li a { color: #0066cc; text-decoration: none; font-size: 0.95em; }
    li a:hover { text-decoration: underline; }
    li.dir { color: #888; font-size: 0.85em; margin-top: 12px; margin-bottom: -4px; }
    .meta { color: #999; font-size: 0.8em; margin-top: 30px; }
    .empty { color: #999; font-style: italic; }
    a.back { display: inline-block; margin-bottom: 16px; color: #666; text-decoration: none; font-size: 0.9em; }
    a.back:hover { color: #0066cc; }
  </style>
</head>
<body>
  <h1>$title</h1>
  <a class=\"back\" href=\"../\">← back</a>
  <ul>
$parent_link$items
  </ul>
  <p class=\"meta\">Generated at $(date '+%Y-%m-%d %H:%M:%S') · <a href=\"$BASE_URL/${rel:-}\">View on GitHub Pages</a></p>
</body>
</html>"

  local index_path="$dir/index.html"
  echo "$index_content" > "$index_path"
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
        ((copied++))
    fi
    ((total++))
done < <(find "$SRC" \
  -type f -name "*.html" \
  -not -path "*/.git/*" \
  -not -path "*/skills/*" \
  -not -path "*/docs/*" \
  -not -path "*/.*" \
  2>/dev/null)

# Move manifest atomically
mv "$TMP_MANIFEST" "$MANIFEST"

# ──────────────────────────────────────────────
# Step 2: Regenerate index.html for ALL directories in DST
#   (run on every sync to keep timestamps / content fresh)
# ──────────────────────────────────────────────
find "$DST" -mindepth 1 -type d 2>/dev/null | sort | while IFS= read -r dir; do
  # Compute relative path from DST
  rel="${dir#$DST/}"
  generate_index "$dir" "$rel"
done

# Also generate root index
generate_index "$DST" ""

# ──────────────────────────────────────────────
# Step 3: Report
# ──────────────────────────────────────────────
echo ""
echo "========================================"
echo " Sync completed at $(date '+%Y-%m-%d %H:%M:%S')"
echo " Total found: $total | Copied: $copied"
echo "========================================"

if [[ $copied -gt 0 ]]; then
    echo ""
    echo "--- Recently synced (latest 5) ---"
    tail -5 "$MANIFEST" | while read -r relpath; do
        echo "$BASE_URL/$relpath"
    done
else
    echo ""
    echo "--- Random 5 examples ---"
    find "$DST" -type f -name "*.html" -not -path "*/.git/*" 2>/dev/null \
        | grep -v "/index.html$" \
        | shuf -n 5 \
        | while read -r file; do
            relpath="${file#$DST/}"
            echo "$BASE_URL/$relpath"
        done
fi

echo ""
echo "Full manifest: $MANIFEST"
echo "Log: $LOG"
echo ""
echo "All directories now have index.html for browsing."
