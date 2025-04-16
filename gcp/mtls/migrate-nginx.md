
这个脚本主要实现了两个核心功能：

1. **Cloud Armor 规则生成和导入**
   - 读取 `conf.d` 目录下的 `*-geo.txt` 文件
   - 解析文件中的 IP 白名单信息
   - 生成 Cloud Armor 规则，包含 IP 和路径的访问控制
   - 可选择将规则导入到 GCP Cloud Armor 策略中

2. **NGINX 配置生成**
   - 处理 `conf.d` 目录下的 `*-proxy-v*.conf` 文件
   - 为每个代理生成对应的 NGINX 配置
   - 包含以下安全特性：
     - 文件上传限制
     - 客户端证书 CN 验证（基于 `-cn.txt` 文件）
     - URL 重写规则
     - 代理转发设置

主要特点：
- 自动化配置生成，减少手动操作
- 支持多版本 API 路径
- 包含重复 IP 检查避免冗余规则
- 内置 JSON 格式验证
- 提供交互式规则导入选项

使用场景：
适用于需要将现有 NGINX mTLS 配置迁移到 GCP Cloud Armor 的场景，同时保留必要的 NGINX 配置。
```bash
#!/opt/homebrew/bin/bash

# Directory and file settings for configuration and output
CONF_DIR="./conf.d"
OUTPUT_DIR="./processed"
CLOUD_ARMOR_RULES="cloud_armor_rules.json"
SECURITY_POLICY_NAME="${project:-default}-mtls-policy"

# Create output directory if not exists
mkdir -p "$OUTPUT_DIR"

# Function to process file names and extract API information
get_file_info() {
    local CONF_FILE=$1
    PROXY_NAME=$(basename "$CONF_FILE" .conf)
    API_NAME=$(echo "$PROXY_NAME" | sed -E 's/-proxy-v[0-9]+$//')
    VERSION=$(echo "$PROXY_NAME" | grep -oE 'v[0-9]+')
    GEO_FILE="${CONF_DIR}/${PROXY_NAME}-geo.txt"
    CN_FILE="${CONF_DIR}/${PROXY_NAME}-cn.txt"
}

# Function to generate Cloud Armor rules based on geo files
generate_rules() {
    # Initialize Cloud Armor rules file with JSON structure
    cat > "$CLOUD_ARMOR_RULES" <<EOF
{
    "rules": [
EOF

    # Set initial priority (starting from 30000)
    local PRIORITY=30000
    local FIRST_RULE=true
    declare -A PROCESSED_IPS  # Hash to store processed IP addresses

    # Process each geo file in the configuration directory
    for GEO_FILE in "$CONF_DIR"/*-geo.txt; do
        if [ ! -f "$GEO_FILE" ]; then
            echo "No geo files found in $CONF_DIR"
            exit 1
        fi

        echo "Processing: $GEO_FILE"

        # Extract map name and version from the first line of geo file
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
            IP=$(echo "$line" | awk '{print $1}')
            VALUE=$(echo "$line" | awk '{print $2}' | tr -d ';')

            # Only process IPs with value 1 and skip default route
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

                    # Generate Cloud Armor rule for this IP and path
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

    # Close the JSON array and object
    cat >> "$CLOUD_ARMOR_RULES" <<EOF
    ]
}
EOF
}

# Function to import generated rules into Cloud Armor
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

# Generate Cloud Armor rules
generate_rules

# Validate JSON format and prompt for rule import
if command -v jq >/dev/null 2>&1; then
    if jq empty "$CLOUD_ARMOR_RULES" 2>/dev/null; then
        echo "JSON format validation passed"
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

# Generate NGINX configuration for each proxy configuration file
for CONF_FILE in "$CONF_DIR"/*-proxy-v*.conf; do
    if [ ! -f "$CONF_FILE" ]; then
        continue
    fi

    # Get file information for the current proxy
    get_file_info "$CONF_FILE"

    # Generate new configuration file in output directory
    NEW_CONF="${OUTPUT_DIR}/${PROXY_NAME}.conf"

    # Generate NGINX location block with security settings
    cat >"$NEW_CONF" <<EOF
location /${API_NAME}-proxy/${VERSION}/ {
    # set default restrict file upload
    if (\$content_type ~ (multipart\/form-data|text\/plain)) {
        return 405;
    }

    # CN verification
EOF

    # Add CN verification logic if CN file exists
    if [ -f "$CN_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# || ! "$line" =~ [[:space:]][[:alnum:].]+[[:space:]]1\;$ ]] && continue
            domain=$(echo "$line" | grep -o '[[:space:]][[:alnum:].-]\+[[:space:]]1;' | sed 's/[[:space:]]*1;//' | tr -d '[:space:]')
            cat >>"$NEW_CONF" <<EOF
    if (\$ssl_client_s_dn_cn = "${domain}") {
        set \$flag 0;
    }
EOF
        done <"$CN_FILE"

        cat >>"$NEW_CONF" <<EOF
    if (\$flag = 1) {
        return 406;
    }
EOF
    fi

    # Add proxy configuration and URL rewriting rules
    cat >>"$NEW_CONF" <<EOF
    rewrite ^(.*) ":yourdomain.com\$1";
    rewrite ^(.*) "https\$1" break;
    proxy_pass     http://forward.URL_ADDRESS:3128;
}
EOF

    echo "NGINX configuration file generated: $NEW_CONF"
done
```
---
- edit function `generate_rules` and `import_rules`
```bash
#!/opt/homebrew/bin/bash

# Directory and file settings for configuration and output
CONF_DIR="./conf.d"
OUTPUT_DIR="./processed"
CLOUD_ARMOR_RULES="cloud_armor_rules.json"
SECURITY_POLICY_NAME="${project:-default}-mtls-policy"

# Create output directory if not exists
mkdir -p "$OUTPUT_DIR"

# Function to process file names and extract API information
get_file_info() {
    local CONF_FILE=$1
    PROXY_NAME=$(basename "$CONF_FILE" .conf)
    API_NAME=$(echo "$PROXY_NAME" | sed -E 's/-proxy-v[0-9]+$//')
    VERSION=$(echo "$PROXY_NAME" | grep -oE 'v[0-9]+')
    GEO_FILE="${CONF_DIR}/${PROXY_NAME}-geo.txt"
    CN_FILE="${CONF_DIR}/${PROXY_NAME}-cn.txt"
}

# Function to generate Cloud Armor rules based on geo files
generate_rules() {
    # Create security policy command
    echo "# Create security policy"
    echo "gcloud compute security-policies create ${SECURITY_POLICY_NAME} \\"
    echo "    --description=\"Security policy for API access control\""
    echo

    # Set initial priority
    local PRIORITY=30000
    declare -A PROCESSED_IPS  # Hash to store processed IP addresses

    # Process each geo file
    for GEO_FILE in "$CONF_DIR"/*-geo.txt; do
        if [ ! -f "$GEO_FILE" ]; then
            echo "No geo files found in $CONF_DIR"
            exit 1
        fi

        echo "# Processing: $GEO_FILE"

        # ... (保持现有的 MAP_NAME 和 VERSION 提取逻辑) ...

        # Convert map name to path format for URL routing
        BASE_PATH=$(echo "$MAP_NAME" | sed -E 's/-v[0-9]+$//')
        REQUEST_PATH="/${BASE_PATH}/${VERSION}"
        
        # Process each line in the geo file
        while IFS= read -r line; do
            # Skip empty lines, comments, default line, and lines without IP
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" =~ "default" || ! "$line" =~ ^[[:space:]]*[0-9] ]] && continue
            
            # Extract IP and value
            IP=$(echo "$line" | awk '{print $1}')
            VALUE=$(echo "$line" | awk '{print $2}' | tr -d ';')

            # Only process IPs with value 1 and skip default route
            if [ "$IP" != "0.0.0.0/0" ] && [ "$VALUE" = "1" ]; then
                local IP_PATH_KEY="${IP}:${REQUEST_PATH}"
                if [ "${PROCESSED_IPS[$IP_PATH_KEY]}" != "1" ]; then
                    PROCESSED_IPS[$IP_PATH_KEY]="1"
                    
                    # Generate create command for each rule
                    echo "# Add rule for $IP to access $REQUEST_PATH"
                    echo "gcloud compute security-policies rules create ${SECURITY_POLICY_NAME} \\"
                    echo "    --description=\"Allow $IP to access $REQUEST_PATH\" \\"
                    echo "    --action=allow \\"
                    echo "    --priority=$PRIORITY \\"
                    echo "    --expression=\"request.path.matches('$REQUEST_PATH/*') && inIpRange(origin.ip, '$IP')\""
                    echo
                    
                    PRIORITY=$((PRIORITY + 1))
                fi
            fi
        done < "$GEO_FILE"
    done

    # Add default deny rule
    echo "# Add default deny rule"
    echo "gcloud compute security-policies rules create ${SECURITY_POLICY_NAME} \\"
    echo "    --description=\"Default deny rule\" \\"
    echo "    --action=deny-403 \\"
    echo "    --priority=2147483647"
}

# Function to print import command
import_rules() {
    echo "# Command to import rules (if needed):"
    echo "gcloud compute security-policies rules import ${SECURITY_POLICY_NAME} \\"
    echo "    --source=\"${CLOUD_ARMOR_RULES}\" \\"
    echo "    --quiet"
}


# Generate Cloud Armor rules
generate_rules

# Validate JSON format and prompt for rule import
if command -v jq >/dev/null 2>&1; then
    if jq empty "$CLOUD_ARMOR_RULES" 2>/dev/null; then
        echo "JSON format validation passed"
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

# Generate NGINX configuration for each proxy configuration file
for CONF_FILE in "$CONF_DIR"/*-proxy-v*.conf; do
    if [ ! -f "$CONF_FILE" ]; then
        continue
    fi

    # Get file information for the current proxy
    get_file_info "$CONF_FILE"

    # Generate new configuration file in output directory
    NEW_CONF="${OUTPUT_DIR}/${PROXY_NAME}.conf"

    # Generate NGINX location block with security settings
    cat >"$NEW_CONF" <<EOF
location /${API_NAME}-proxy/${VERSION}/ {
    # set default restrict file upload
    if (\$content_type ~ (multipart\/form-data|text\/plain)) {
        return 405;
    }

    # CN verification
EOF

    # Add CN verification logic if CN file exists
    if [ -f "$CN_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# || ! "$line" =~ [[:space:]][[:alnum:].]+[[:space:]]1\;$ ]] && continue
            domain=$(echo "$line" | grep -o '[[:space:]][[:alnum:].-]\+[[:space:]]1;' | sed 's/[[:space:]]*1;//' | tr -d '[:space:]')
            cat >>"$NEW_CONF" <<EOF
    if (\$ssl_client_s_dn_cn = "${domain}") {
        set \$flag 0;
    }
EOF
        done <"$CN_FILE"

        cat >>"$NEW_CONF" <<EOF
    if (\$flag = 1) {
        return 406;
    }
EOF
    fi

    # Add proxy configuration and URL rewriting rules
    cat >>"$NEW_CONF" <<EOF
    rewrite ^(.*) ":yourdomain.com\$1";
    rewrite ^(.*) "https\$1" break;
    proxy_pass     http://forward.URL_ADDRESS:3128;
}
EOF

    echo "NGINX configuration file generated: $NEW_CONF"
done
```