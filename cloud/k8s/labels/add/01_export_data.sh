#!/bin/bash

# 01_export_data.sh
# Purpose: Export data from BigQuery or generate dummy data for testing.

OUTPUT_FILE="raw_data.json"

function show_help {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --bq       Execute BigQuery export (requires bq command and permissions)"
    echo "  --dummy    Generate dummy data for testing (default)"
    echo "  --help     Show this help message"
}

function generate_dummy_data {
    echo "Generating dummy data to $OUTPUT_FILE..."
    cat <<EOF > "$OUTPUT_FILE"
[
  {
    "api_name": "dev-wcc-mon-sa-eny",
    "eidnumber": "E12345",
    "bidnumber": "B67890"
  },
  {
    "api_name": "another-api",
    "eidnumber": "E11111",
    "bidnumber": "B22222"
  },
  {
    "api_name": "payment-service",
    "eidnumber": "E99999",
    "bidnumber": "B88888"
  }
]
EOF
    echo "Dummy data generated."
}

function export_from_bq {
    echo "Exporting data from BigQuery..."
    # Replace with your actual project and dataset
    PROJECT_ID="gcp-project"
    DATASET="aibang_api_data.v4_data"
    
    if ! command -v bq &> /dev/null; then
        echo "Error: 'bq' command not found. Please install Google Cloud SDK."
        exit 1
    fi

    bq query --format=json --use_legacy_sql=false --max_rows=10000 \
    "SELECT api_name, eidnumber, bidnumber 
     FROM \`$PROJECT_ID.$DATASET\` 
     WHERE api_name IS NOT NULL AND eidnumber IS NOT NULL" > "$OUTPUT_FILE"
    
    if [ $? -eq 0 ]; then
        echo "Export successful to $OUTPUT_FILE"
    else
        echo "Export failed."
        exit 1
    fi
}

# Main execution
if [ "$1" == "--bq" ]; then
    export_from_bq
elif [ "$1" == "--help" ]; then
    show_help
else
    generate_dummy_data
fi
