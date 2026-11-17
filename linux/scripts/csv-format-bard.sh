#!/bin/bash

# Function to generate a Markdown table from a CSV file
function generate_markdown_table() {
  local csv_filename=$1
  local delimiter=$2

  # Read the header and content from the CSV file
  header=$(head -n 1 "$csv_filename")
  content=$(tail -n +2 "$csv_filename")

  # Create the table header
  table="| $header |\n"

  # Calculate the number of columns
  col_num=$(echo "$header" | tr "$delimiter" "\n" | wc -l)

  # Generate alignment row
  align_row=""
  for ((i=1; i<=col_num; i++)); do
    align_row+="| -- "
  done

  table="$table$align_row\n"

  # Process content and append to table
  while IFS= read -r line; do
    table+="| $line |\n"
  done <<< "$content"

  # Format table using sed
  formatted_table=$(echo -e "$table" | sed "s/$delimiter/ | /g")

  echo -e "$formatted_table"
}

# Check if help option is provided
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "Usage: $0 <csv_file> [delimiter]"
  echo "   - <csv_file>: Path to the CSV file"
  echo "   - [delimiter]: Optional. Delimiter used in the CSV file. Default is comma (,)."
  echo "   - ./csv-markdown-table.sh members.csv \";\" "
  echo "   - ./csv-markdown-table.sh members.csv \",\" "
  exit 0
fi

# Check if the required arguments are provided
if [ $# -lt 1 ]; then
  echo "Error: Insufficient arguments."
  display_usage
  exit 1
fi

# Read command line arguments
csv_filename=$1
delimiter=${2:-","} # Set the delimiter to comma if not provided

# Generate the Markdown table
generate_markdown_table "$csv_filename" "$delimiter"
