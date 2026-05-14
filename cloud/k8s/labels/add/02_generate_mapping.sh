#!/bin/bash

# 02_generate_mapping.sh
# Purpose: Convert raw list data to key-value mapping for fast lookup.

INPUT_FILE="raw_data.json"
OUTPUT_FILE="mapping.json"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: $INPUT_FILE not found. Run 01_export_data.sh first."
    exit 1
fi

echo "Generating mapping file from $INPUT_FILE..."

# Use jq to transform list to object (map)
# Input: [{"api_name": "foo", "eidnumber": "1", "bidnumber": "2"}, ...]
# Output: {"foo": {"eidnumber": "1", "bidnumber": "2"}, ...}

jq -r 'map({(.api_name): {eidnumber, bidnumber}}) | add' "$INPUT_FILE" > "$OUTPUT_FILE"

if [ $? -eq 0 ]; then
    echo "Mapping file generated at $OUTPUT_FILE"
    echo "Preview:"
    head -n 10 "$OUTPUT_FILE"
else
    echo "Error generating mapping file."
    exit 1
fi
