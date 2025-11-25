# Shell Scripts Collection

Generated on: 2025-11-25 18:58:10
Directory: /Users/lex/git/knowledge/k8s/labels/add

## `01_export_data.sh`

```bash
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

```

## `02_generate_mapping.sh`

```bash
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

```

## `03_backup.sh`

```bash
#!/bin/bash

# 03_backup.sh
# Purpose: Backup all deployments in all namespaces before making changes.

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="backup_deployments_${TIMESTAMP}.yaml"

echo "Backing up all deployments to $BACKUP_FILE..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found."
    exit 1
fi

kubectl get deployments --all-namespaces -o yaml > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "Backup successful: $BACKUP_FILE"
    echo "To restore (use with caution): kubectl apply -f $BACKUP_FILE"
else
    echo "Backup failed."
    exit 1
fi

```

## `04_apply_labels.sh`

```bash
#!/bin/bash

# 04_apply_labels.sh
# Purpose: Iterate through deployments, match with mapping, and apply labels.

MAPPING_FILE="mapping.json"
LOG_DIR="logs"
DRY_RUN=false

# Create log directory
mkdir -p "$LOG_DIR"
SUCCESS_LOG="$LOG_DIR/success.log"
FAILED_LOG="$LOG_DIR/failed.log"
UNMATCHED_LOG="$LOG_DIR/unmatched.log"
SKIPPED_LOG="$LOG_DIR/skipped.log"

# Clear previous logs
> "$SUCCESS_LOG"
> "$FAILED_LOG"
> "$UNMATCHED_LOG"
> "$SKIPPED_LOG"

# Parse arguments
if [[ "$1" == "-d" || "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "Running in DRY-RUN mode. No changes will be applied."
fi

if [ ! -f "$MAPPING_FILE" ]; then
    echo "Error: $MAPPING_FILE not found. Run 02_generate_mapping.sh first."
    exit 1
fi

echo "Starting label application process..."

# Get all deployments (Namespace Name)
# Using process substitution to avoid subshell issues
while read -r ns name; do
    # 1. Extract API Name
    # Remove '-deployment' suffix
    temp_name=${name%-deployment}
    # Remove version suffix (assuming format -X-X-X, e.g., -1-0-2)
    # Using sed for regex replacement
    api_name=$(echo "$temp_name" | sed -E 's/-[0-9]+-[0-9]+-[0-9]+$//')

    # 2. Lookup in mapping file
    # Use jq to get the object for this api_name. If null, it doesn't exist.
    match=$(jq -r --arg key "$api_name" '.[$key] // empty' "$MAPPING_FILE")

    if [ -z "$match" ]; then
        echo "[$ns/$name] -> API: $api_name -> Unmatched"
        echo "$ns $name ($api_name)" >> "$UNMATCHED_LOG"
        continue
    fi

    # Extract labels
    eid=$(echo "$match" | jq -r '.eidnumber')
    bid=$(echo "$match" | jq -r '.bidnumber')

    echo "[$ns/$name] -> API: $api_name -> Match! EID: $eid, BID: $bid"

    # 3. Patch Deployment
    PATCH_JSON="{\"metadata\":{\"labels\":{\"eidnumber\":\"$eid\",\"bidnumber\":\"$bid\"}}}"
    
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] kubectl patch deployment $name -n $ns -p '$PATCH_JSON'"
    else
        # Execute patch
        if kubectl patch deployment "$name" -n "$ns" --type=merge -p "$PATCH_JSON" &> /dev/null; then
            echo "$ns $name patched with EID:$eid BID:$bid" >> "$SUCCESS_LOG"
        else
            echo "Failed to patch $ns $name"
            echo "$ns $name" >> "$FAILED_LOG"
        fi
    fi

done < <(kubectl get deployments --all-namespaces -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name --no-headers)

echo "----------------------------------------"
echo "Processing complete."
echo "Logs:"
echo "  Success:   $(wc -l < "$SUCCESS_LOG")"
echo "  Failed:    $(wc -l < "$FAILED_LOG")"
echo "  Unmatched: $(wc -l < "$UNMATCHED_LOG")"
if [ "$DRY_RUN" = true ]; then
    echo "Note: This was a DRY RUN."
fi

```

## `05_verify.sh`

```bash
#!/bin/bash

# 05_verify.sh
# Purpose: Verify that labels were correctly applied to deployments.

LOG_FILE="logs/success.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "Error: $LOG_FILE not found. Run 04_apply_labels.sh first."
    exit 1
fi

echo "Verifying a sample of patched deployments..."

# Check up to 5 random entries from the success log
# Log format: "namespace deployment patched with EID:xxx BID:xxx"
shuf "$LOG_FILE" | head -n 5 | while read -r line; do
    ns=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    
    echo "Checking $ns/$name..."
    
    # Get labels
    labels=$(kubectl get deployment "$name" -n "$ns" -o jsonpath='{.metadata.labels}')
    
    eid=$(echo "$labels" | jq -r '.eidnumber // "Not Found"')
    bid=$(echo "$labels" | jq -r '.bidnumber // "Not Found"')
    
    echo "  -> eidnumber: $eid"
    echo "  -> bidnumber: $bid"
    
    if [[ "$eid" != "Not Found" && "$bid" != "Not Found" ]]; then
        echo "  [OK] Labels present."
    else
        echo "  [FAIL] Missing labels!"
    fi
done

```

## `06_rollback.sh`

```bash
#!/bin/bash

# 06_rollback.sh
# Purpose: Rollback changes by restoring from backup.

# Find the latest backup file
BACKUP_FILE=$(ls -t backup_deployments_*.yaml 2>/dev/null | head -n 1)

if [ -z "$BACKUP_FILE" ]; then
    echo "Error: No backup file found (backup_deployments_*.yaml)."
    echo "Cannot perform automatic rollback."
    exit 1
fi

echo "Found latest backup: $BACKUP_FILE"
echo "WARNING: This will restore all deployments to the state in this backup file."
echo "Are you sure you want to proceed? (y/n)"
read -r response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Restoring from backup..."
    kubectl apply -f "$BACKUP_FILE"
    
    if [ $? -eq 0 ]; then
        echo "Rollback complete."
    else
        echo "Rollback failed."
    fi
else
    echo "Rollback cancelled."
fi

```

