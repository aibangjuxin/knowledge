#!/bin/bash
#
# Sync HTML files from knowledge workspace to docs directory
# - Preserves directory structure
# - Excludes: skills/, docs/, and dot-prefixed directories
#

SRC="/Users/lex/git/knowledge"
DST="/Users/lex/git/knowledge/docs"
LOG="/Users/lex/git/knowledge/bin/sync-html-to-docs.log"

# Build find command with exclusions
find "$SRC" \
  -type f -name "*.html" \
  -not -path "*/.git/*" \
  -not -path "*/skills/*" \
  -not -path "*/docs/*" \
  -not -path "*/.*" \
  | while read -r file; do
      # Calculate relative path from SRC
      relpath="${file#$SRC/}"
      dest="$DST/$relpath"

      # Create destination directory
      mkdir -p "$(dirname "$dest")"

      # Copy file
      cp "$file" "$dest"
      echo "Copied: $relpath"
    done

echo "Sync completed at $(date)" >> "$LOG"
