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
- who to get the exists cloud armor policy's fingerprint?
  - use the following command to get the exists cloud armor policy's fingerprint:
    ```bash
    gcloud compute security-policies describe ${SECURITY_POLICY_NAME} --global --format=json | jq -r '.[0].fingerprint'
    ```
- how to import the rules to cloud armor?
  - use the following command to import the rules to cloud armor:
    ```bash
    gcloud compute security-policies rules import ${SECURITY_POLICY_NAME} \
        --file-name=cloud-armor.json \
        --file-format=json \
        --global
    ```

- The eg about of the cloud-armor.json file:


```json
{
    "fingerprint": "8fBCJK8TD3=",
    "rules": [
        {
            "description": "Allow 1.2.3.4 to access /api/v1",
            "priority": 30000,
            "match": {
                "expr": {
                    "expression": "request.path.matches('/api/v1/*') && inIpRange(origin.ip, '1.2.3.4/32')"
                }
            },
            "action": "allow"
        },
        {
            "description": "Allow 5.6.7.8 to access /api/v2",
            "priority": 30001,
            "match": {
                "expr": {
                    "expression": "request.path.matches('/api/v2/*') && inIpRange(origin.ip, '5.6.7.8/32')"
                }
            },
            "action": "allow"
        },
        {
            "description": "Allow 9.10.11.12 to access /api/v3",
            "priority": 30002,
            "match": {
                "expr": {
                    "expression": "request.path.matches('/api/v3/*') && inIpRange(origin.ip, '9.10.11.12/32')"
                }
            },
            "action": "allow"
        }
    ]
}
```
---
- generate-cloud-armor-all.sh
```bash
#!/opt/homebrew/bin/bash

# Directory settings for input and output files
CONF_DIR="./conf.d"
OUTPUT_DIR="./processed"
CLOUD_ARMOR_RULES="cloud_armor_rules.json"
SECURITY_POLICY_NAME="${project:-default}-armor-policy"

# Create output directory if not exists
mkdir -p "$OUTPUT_DIR"

# Function to convert proxy name to path format
# Example: service-proxy-v1 -> /service/v1
convert_to_path() {
    local proxy_name=$1
    echo "/$(echo "$proxy_name" | sed -E 's/-v([0-9]+)$//')/v\1"
}

# Function to generate Cloud Armor security rules
# Processes geo files to create IP-based access rules with path matching
generate_rules() {
    # Initialize Cloud Armor rules file with JSON structure
    cat > "$CLOUD_ARMOR_RULES" <<EOF
{
    "rules": [
EOF

    # Set initial priority (starting from 30000)
    local PRIORITY=30000
    local FIRST_RULE=true
    # Hash map to store processed IP-path combinations for deduplication
    declare -A PROCESSED_IPS

    # Process each geo file in the configuration directory
    for GEO_FILE in "$CONF_DIR"/*-geo.txt; do
        if [ ! -f "$GEO_FILE" ]; then
            echo "No geo files found in $CONF_DIR"
            exit 1
        fi

        echo "Processing: $GEO_FILE"

        # Extract map name and version from the first line of geo file
        # Looks for proxy_protocol_addr pattern and extracts the variable name
        MAP_NAME=$(grep proxy_protocol_addr "$GEO_FILE" | grep -o '\$[^ ]*' | tail -n1 | sed 's/\$//')
        VERSION=$(echo "$MAP_NAME" | grep -o 'v[0-9]\+' || echo "v1")
        
        if [ -z "$MAP_NAME" ]; then
            echo "Warning: Could not extract map name from $GEO_FILE"
            continue
        fi

        # Convert map name to path format for URL routing
        BASE_PATH=$(echo "$MAP_NAME" | sed -E 's/-v[0-9]+$//')
        REQUEST_PATH="/${BASE_PATH}/${VERSION}"
        echo "Request path: $REQUEST_PATH"

        # Process each line in the geo file to extract IP addresses
        while IFS= read -r line; do
            # Skip empty lines, comments, default line, and lines without IP
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" =~ "default" || ! "$line" =~ ^[[:space:]]*[0-9] ]] && continue
            
            # Extract IP and value from the line
            # Format expected: IP_ADDRESS VALUE;
            IP=$(echo "$line" | awk '{print $1}')
            VALUE=$(echo "$line" | awk '{print $2}' | tr -d ';')

            # Skip default route and only process IPs with value 1
            if [ "$IP" != "0.0.0.0/0" ] && [ "$VALUE" = "1" ]; then
                # Check if this IP and path combination has been processed
                local IP_PATH_KEY="${IP}:${REQUEST_PATH}"
                if [ "${PROCESSED_IPS[$IP_PATH_KEY]}" != "1" ]; then
                    PROCESSED_IPS[$IP_PATH_KEY]="1"
                    
                    # Add comma for all rules except the first one
                    if [ "$FIRST_RULE" = true ]; then
                        FIRST_RULE=false
                    else
                        echo "        ," >> "$CLOUD_ARMOR_RULES"
                    fi

                    # Generate Cloud Armor rule for this IP and path combination
                    cat >> "$CLOUD_ARMOR_RULES" <<EOF
        {
            "description": "Allow $IP to access $REQUEST_PATH",
            "priority": $PRIORITY,
            "match": {
                "expr": {
                    "expression": "request.path.matches('$REQUEST_PATH/*') && inIpRange(origin.ip, '$IP')"
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

    # Close the JSON array and object structure
    cat >> "$CLOUD_ARMOR_RULES" <<EOF
    ]
}
EOF
}

# Function to import generated rules into Cloud Armor security policy
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

# Main execution flow
generate_rules

# Validate JSON format and handle rule import
if command -v jq >/dev/null 2>&1; then
    if jq empty "$CLOUD_ARMOR_RULES" 2>/dev/null; then
        echo "JSON format validation passed"
        # Prompt user for rule import confirmation
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