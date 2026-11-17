#!/opt/homebrew/bin/bash
#
# rp.sh - Batch search and replace in files using a config file
#
# Usage:
#   rp -f /path/to/replace.txt          # Use custom config file
#   rp                                  # Use default: ${HOME}/.config/push-replace/replace.txt
#
# Config file format (two columns, space or tab separated):
#   original_text  replacement_text

set -euo pipefail

DEFAULT_CONFIG="${HOME}/.config/push-replace/replace.txt"

show_help() {
    cat <<'EOF'
rp.sh - Batch search and replace in files

Usage:
  rp -f <config>   Use a specific config file
  rp              Use default config: ~/.config/push-replace/replace.txt

Config file format (two columns, space or tab separated):
  original_text    replacement_text
  foo              bar
EOF
}

config_file=""

while getopts "hf:" opt; do
    case "$opt" in
        h)
            show_help
            exit 0
            ;;
        f)
            config_file="$OPTARG"
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

# Use default config if not specified
if [[ -z "$config_file" ]]; then
    config_file="$DEFAULT_CONFIG"
fi

if [[ ! -f "$config_file" ]]; then
    echo "Error: Config file not found: $config_file" >&2
    exit 1
fi

if [[ ! -s "$config_file" ]]; then
    echo "Error: Config file is empty: $config_file" >&2
    exit 1
fi

# Read config into arrays
IFS=$'\t\n' read -d '' -r -a lines < <(grep -v '^#' "$config_file" | grep -v '^[[:space:]]*$') || true

if [[ ${#lines[@]} -eq 0 ]]; then
    echo "Error: No valid replacement rules found in: $config_file" >&2
    exit 1
fi

total_replacements=0

# Process all files in current directory (non-recursive, files only)
while IFS= read -r -d '' file; do
    changed=false
    content=$(cat "$file")

    for line in "${lines[@]}"; do
        # Parse key and value (split on first whitespace sequence)
        key=$(echo "$line" | awk '{print $1}')
        value=$(echo "$line" | awk '{print $2}')

        if [[ -z "$key" || -z "$value" ]]; then
            continue
        fi

        # Count occurrences before replacement
        count=$(echo "$content" | grep -c -- "$key" || true)

        if [[ "$count" -gt 0 ]]; then
            content=$(echo "$content" | sed "s|$key|$value|g")
            echo "  $key -> $value ($count occurrence$([[ $count -eq 1 ]] && echo '' || echo 's')) in $(basename "$file")"
            changed=true
            total_replacements=$((total_replacements + count))
        fi
    done

    if $changed; then
        printf '%s' "$content" > "$file"
    fi
done < <(find . -maxdepth 1 -type f ! -name "rp.sh" ! -name ".*" -print0 2>/dev/null)

echo ""
echo "Done. $total_replacements replacements made."