This script automates the creation and management of Google Cloud Armor security rules. Here's a summary of its main functions:

1. **Configuration Setup**
   - Uses a `conf.d` directory for input files
   - Processes `*-geo.txt` files containing IP whitelists
   - Generates rules in `cloud_armor_rules.json`

2. **Rule Generation Process**
   - Reads IP addresses and their associated paths from geo files
   - Assigns priorities starting from 30000
   - Prevents duplicate IP-path combinations
   - Creates allow rules for specific IP addresses and API paths
   - Matches requests based on path patterns

3. **Security Features**
   - Skips default route (0.0.0.0/0)
   - Only processes IPs marked with value "1"
   - Maintains unique rules through IP-path deduplication

4. **Deployment Features**
   - JSON format validation using `jq`
   - Interactive prompt for rule import
   - Imports rules to specified Cloud Armor security policy
   - Handles error cases and provides status feedback

Usage: Place geo files in `conf.d` directory, run the script, and optionally import the generated rules to Cloud Armor.


```bash
#!/opt/homebrew/bin/bash

# Directory settings
CONF_DIR="./conf.d"
OUTPUT_DIR="./processed"
CLOUD_ARMOR_RULES="cloud_armor_rules.json"
SECURITY_POLICY_NAME="${project:-default}--armor-policy"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to convert proxy name to path format
convert_to_path() {
    local proxy_name=$1
    echo "/$(echo "$proxy_name" | sed -E 's/-v([0-9]+)$//')/v\1"
}

# Function to generate rules
generate_rules() {
    # Initialize Cloud Armor rules file
    cat > "$CLOUD_ARMOR_RULES" <<EOF
{
    "rules": [
EOF

    # Set initial priority (starting from 30000)
    local PRIORITY=30000
    local FIRST_RULE=true
    declare -A PROCESSED_IPS  # 用于去重

    # Process each geo file
    for GEO_FILE in "$CONF_DIR"/*-geo.txt; do
        if [ ! -f "$GEO_FILE" ]; then
            echo "No geo files found in $CONF_DIR"
            exit 1
        fi

        echo "Processing: $GEO_FILE"

        # Extract map name and version from the first line
        MAP_NAME=$(grep proxy_protocol_addr "$GEO_FILE" | grep -o '\$[^ ]*' | tail -n1 | sed 's/\$//')
        VERSION=$(echo "$MAP_NAME" | grep -o 'v[0-9]\+' || echo "v1")
        
        if [ -z "$MAP_NAME" ]; then
            echo "Warning: Could not extract map name from $GEO_FILE"
            continue
        fi

        # Convert map name to path format
        BASE_PATH=$(echo "$MAP_NAME" | sed -E 's/-v[0-9]+$//')
        REQUEST_PATH="/${BASE_PATH}/${VERSION}"
        echo "Request path: $REQUEST_PATH"

        # Extract IP addresses with value 1
        while IFS= read -r line; do
            # Skip empty lines, comments, default line, and lines without IP
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" =~ "default" || ! "$line" =~ ^[[:space:]]*[0-9] ]] && continue
            
            # Extract IP and value
            IP=$(echo "$line" | awk '{print $1}')
            VALUE=$(echo "$line" | awk '{print $2}' | tr -d ';')

            # Skip 0.0.0.0/0 and only process IPs with value 1
            if [ "$IP" != "0.0.0.0/0" ] && [ "$VALUE" = "1" ]; then
                # 检查是否已处理过该IP和路径组合
                local IP_PATH_KEY="${IP}:${REQUEST_PATH}"
                if [ "${PROCESSED_IPS[$IP_PATH_KEY]}" != "1" ]; then
                    PROCESSED_IPS[$IP_PATH_KEY]="1"
                    
                    # Add comma for all rules except the first one
                    if [ "$FIRST_RULE" = true ]; then
                        FIRST_RULE=false
                    else
                        echo "        ," >> "$CLOUD_ARMOR_RULES"
                    fi

                    cat >> "$CLOUD_ARMOR_RULES" <<EOF
        {
            "description": "Allow $IP to access $REQUEST_PATH",
            "priority": $PRIORITY,
            "match": {
                "versionedExpr": "SRC_IPS_V1",
                "config": {
                    "srcIpRanges": ["$IP"]
                },
                "expr": {
                    "expression": "request.path.matches('$REQUEST_PATH/*')"
                }
            },
            "action": "allow"
        }
EOF
                    PRIORITY=$((PRIORITY + 1))
                fi
            fi
        done < "$GEO_FILE"
    done

    # Close the JSON array and object
    cat >> "$CLOUD_ARMOR_RULES" <<EOF
    ]
}
EOF
}

# Function to import rules
import_rules() {
    if [ -f "$CLOUD_ARMOR_RULES" ]; then
        echo "Importing rules to security policy: $SECURITY_POLICY_NAME"
        if gcloud compute security-policies rules import "$SECURITY_POLICY_NAME" \
            --source="$CLOUD_ARMOR_RULES" \
            --quiet; then
            echo "Rules imported successfully"
        else
            echo "Error: Failed to import rules"
            exit 1
        fi
    else
        echo "Error: Rules file not found: $CLOUD_ARMOR_RULES"
        exit 1
    fi
}

# Main execution
generate_rules

# Validate JSON format
if command -v jq >/dev/null 2>&1; then
    if jq empty "$CLOUD_ARMOR_RULES" 2>/dev/null; then
        echo "JSON format validation passed"
        # Ask user if they want to import rules
        read -p "Do you want to import these rules to Cloud Armor? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            import_rules
        fi
    else
        echo "Error: JSON format validation failed"
        exit 1
    fi
else
    echo "Warning: jq not installed, cannot validate JSON format"
fi
```