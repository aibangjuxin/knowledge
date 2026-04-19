#!/opt/homebrew/bin/bash

# fm.sh - Format markdown files using local Ollama AI (Shell only version)
# Usage: ./fm.sh -c <file.md>

set -euo pipefail

# Configuration
OLLAMA_URL="http://localhost:11434/api/generate"
MODEL="gemma4:e4b-it-q4_K_M"
TMP_RESPONSE="/tmp/fm_response_$$.txt"
TMP_PAYLOAD="/tmp/fm_payload_$$.json"

usage() {
    echo "Usage: $0 -c <markdown_file>"
    echo "  -c <file>  Format the specified markdown file"
    exit 1
}

cleanup() {
    rm -f "$TMP_RESPONSE" "$TMP_PAYLOAD"
}
trap cleanup EXIT

# 1. Parse arguments
FILE=""
while getopts "c:" opt; do
    case $opt in
        c) FILE="$OPTARG" ;;
        *) usage ;;
    esac
done

[[ -z "$FILE" ]] && usage

if [[ ! -f "$FILE" ]]; then
    echo "Error: File '$FILE' not found"
    exit 1
fi

# 2. Check if tools are installed
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed. Please install it with 'brew install jq'"
    exit 1
fi

if ! curl -s --max-time 5 "http://localhost:11434/api/tags" > /dev/null 2>&1; then
    echo "Error: Ollama is not running at http://localhost:11434"
    exit 1
fi

# 3. Backup original file
BACKUP="${FILE}.bak"
cp "$FILE" "$BACKUP"
echo "Backup created: $BACKUP"

# 4. Prepare prompt and JSON payload using jq
CONTENT=$(cat "$FILE")
PROMPT="This is my markdown document:

---
$CONTENT
---

But some content in the document is not in standard format. I need you to format it based on the original text, without adjusting the content, just formatting it on the basis of the original text.

Rules:
- The tables remain as Markdown table source code
- Code blocks are complete in forms like \`\`\`bash, \`\`\`mermaid, \`\`\`yaml, etc.
- Output unrendered text (i.e., pure Markdown source code)
- Especially in terms of layout, make it more readable with proper spacing and structure
- Do NOT change any content, meaning, or technical details
- Do NOT add explanations, comments, preamble, or postamble
- Output ONLY the formatted markdown source code, nothing else"

jq -n \
  --arg model "$MODEL" \
  --arg prompt "$PROMPT" \
  '{model: $model, prompt: $prompt, stream: true}' > "$TMP_PAYLOAD"

# 5. Call Ollama API
echo "Formatting '$FILE' using model '$MODEL'..."
echo "(Streaming response...)"

curl -s -X POST "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d @"$TMP_PAYLOAD" > "$TMP_RESPONSE"

# 6. Parse result and clean up
if [[ ! -s "$TMP_RESPONSE" ]]; then
    echo "Error: No response from Ollama"
    cp "$BACKUP" "$FILE"
    exit 1
fi

# Extract 'response' fields from NDJSON and concatenate
RESULT=$(jq -j '.response' "$TMP_RESPONSE")

if [[ -z "$RESULT" ]]; then
    echo "Error: Failed to parse result from Ollama"
    cp "$BACKUP" "$FILE"
    exit 1
fi

# Strip marking ```markdown and ``` if present
# We use a temp file to handle multiple lines in sed easily
echo "$RESULT" | sed '1{/^```/d;};${/^```/d;}' > "$FILE"

echo ""
echo "✓ Done! '$FILE' has been formatted."
echo ""

# --- Comparison & Cleanup ---
echo "--- Comparison (Left: Original, Right: Formatted) ---"
# Use sdiff -s to show only differences
sdiff -s -w "$(tput cols)" "$BACKUP" "$FILE" || true

echo ""
read -p "Do you want to delete the backup file '$BACKUP'? (y/N): " choice
if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    rm -f "$BACKUP"
    echo "✓ Backup file deleted."
else
    echo "• Backup file kept: $BACKUP"
fi

