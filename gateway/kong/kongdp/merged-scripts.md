# Shell Scripts Collection

Generated on: 2026-02-02 16:27:33
Directory: /Users/lex/git/knowledge/kong/kongdp

## `compare-dp.sh`

```bash
#!/bin/bash

# Kong Data Plane Comparison Script
# 用于对比两个不同的 Kong DP 安装的资源差异
# Usage: ./compare-dp.sh -s <source-namespace> -t <target-namespace>

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default values
SOURCE_NS=""
TARGET_NS=""
OUTPUT_FORMAT="table" # table or json
DETAIL_LEVEL="summary" # summary or detailed
LABEL_SELECTOR="app=busybox-app"

# Parse command line arguments
usage() {
    cat << EOF
${GREEN}Kong Data Plane 对比工具${NC}

用法: $0 -s <source-namespace> -t <target-namespace> [选项]

必选参数:
  -s <namespace>    源 Namespace (如: aibang-int-kdp)
  -t <namespace>    目标 Namespace (如: aibang-ext-kdp)

可选参数:
  -l <label>        Pod 标签选择器 (默认: $LABEL_SELECTOR)
  -o <format>       输出格式: table|json (默认: table)
  -d <level>        详细级别: summary|detailed (默认: summary)
  -h                显示此帮助信息

示例:
  $0 -s aibang-int-kdp -t aibang-ext-kdp
  $0 -s aibang-int-kdp -t aibang-ext-kdp -d detailed
  $0 -s ns1 -t ns2 -l app=kong-dp -o json

EOF
    exit 0
}

while getopts "s:t:l:o:d:h" opt; do
  case $opt in
    s) SOURCE_NS="$OPTARG" ;;
    t) TARGET_NS="$OPTARG" ;;
    l) LABEL_SELECTOR="$OPTARG" ;;
    o) OUTPUT_FORMAT="$OPTARG" ;;
    d) DETAIL_LEVEL="$OPTARG" ;;
    h) usage ;;
    \?)
      echo -e "${RED}无效选项: -$OPTARG${NC}" >&2
      usage
      ;;
  esac
done

# Validate required parameters
if [ -z "$SOURCE_NS" ] || [ -z "$TARGET_NS" ]; then
    echo -e "${RED}❌ 错误: 必须指定源和目标 Namespace${NC}"
    usage
fi

# Helper functions
print_header() {
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}\n"
}

print_subheader() {
  echo -e "\n${CYAN}--- $1 ---${NC}\n"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

print_diff() {
  echo -e "${MAGENTA}🔍 $1${NC}"
}

# Format table output
print_table_row() {
    local col1="$1"
    local col2="$2"
    local col3="$3"
    local col4="$4"
    # Use %b instead of %s to interpret ANSI color codes
    printf "| %-40b | %-45b | %-45b | %-20b |\n" "$col1" "$col2" "$col3" "$col4"
}

print_table_separator() {
    echo "+------------------------------------------+-----------------------------------------------+-----------------------------------------------+----------------------+"
}

# Extract certificate information using openssl
extract_cert_info() {
    local namespace="$1"
    local secret_name="$2"
    local field="$3"  # subject, issuer, enddate, startdate, cn, san
    
    local cert_data=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [ -z "$cert_data" ]; then
        echo "N/A"
        return
    fi
    
    case "$field" in
        subject)
            echo "$cert_data" | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//' || echo "N/A"
            ;;
        issuer)
            echo "$cert_data" | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//' || echo "N/A"
            ;;
        enddate)
            echo "$cert_data" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "N/A"
            ;;
        startdate)
            echo "$cert_data" | openssl x509 -noout -startdate 2>/dev/null | sed 's/notBefore=//' || echo "N/A"
            ;;
        cn)
            echo "$cert_data" | openssl x509 -noout -subject 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' || echo "N/A"
            ;;
        san)
            echo "$cert_data" | openssl x509 -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^[[:space:]]*//' || echo "N/A"
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

# Extract CP connection info from deployment
extract_cp_info() {
    local namespace="$1"
    local deployment="$2"
    local field="$3"  # host, port, mtls_enabled
    
    local cp_value=$(kubectl get deployment "$deployment" -n "$namespace" \
        -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KONG_CLUSTER_CONTROL_PLANE")].value}' 2>/dev/null || echo "")
    
    if [ -z "$cp_value" ]; then
        echo "N/A"
        return
    fi
    
    # Remove protocol if present
    local clean_val="${cp_value#*://}"
    
    case "$field" in
        host)
            echo "$clean_val" | cut -d: -f1
            ;;
        port)
            if [[ "$clean_val" == *":"* ]]; then
                echo "$clean_val" | cut -d: -f2
            else
                echo "8005"
            fi
            ;;
        full)
            echo "$cp_value"
            ;;
        *)
            echo "N/A"
            ;;
    esac
}

# Main comparison logic
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Kong Data Plane 资源对比工具                       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}源 Namespace:${NC} ${YELLOW}$SOURCE_NS${NC}"
echo -e "${CYAN}目标 Namespace:${NC} ${YELLOW}$TARGET_NS${NC}"
echo -e "${CYAN}标签选择器:${NC} ${YELLOW}$LABEL_SELECTOR${NC}"
echo ""

# Verify namespaces exist
print_info "验证 Namespace 存在性..."
if ! kubectl get namespace "$SOURCE_NS" > /dev/null 2>&1; then
    print_error "源 Namespace '$SOURCE_NS' 不存在"
    exit 1
fi

if ! kubectl get namespace "$TARGET_NS" > /dev/null 2>&1; then
    print_error "目标 Namespace '$TARGET_NS' 不存在"
    exit 1
fi

print_success "两个 Namespace 均存在"

# ==============================================================================
# 1. Deployment Comparison
# ==============================================================================
print_header "1. Deployment 对比"

# Find deployments
SOURCE_DEPLOY=$(kubectl get deployment -n "$SOURCE_NS" -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
TARGET_DEPLOY=$(kubectl get deployment -n "$TARGET_NS" -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$SOURCE_DEPLOY" ]; then
    print_error "源 Namespace 中未找到 Deployment (标签: $LABEL_SELECTOR)"
    SOURCE_DEPLOY="N/A"
fi

if [ -z "$TARGET_DEPLOY" ]; then
    print_error "目标 Namespace 中未找到 Deployment (标签: $LABEL_SELECTOR)"
    TARGET_DEPLOY="N/A"
fi

# Deployment basic info
print_subheader "Deployment 基本信息"
print_table_separator
print_table_row "属性" "源 ($SOURCE_NS)" "目标 ($TARGET_NS)" "状态"
print_table_separator

# Deployment name
if [ "$SOURCE_DEPLOY" = "$TARGET_DEPLOY" ]; then
    STATUS="${GREEN}相同${NC}"
else
    STATUS="${YELLOW}不同${NC}"
fi
print_table_row "Deployment 名称" "$SOURCE_DEPLOY" "$TARGET_DEPLOY" "$STATUS"

if [ "$SOURCE_DEPLOY" != "N/A" ] && [ "$TARGET_DEPLOY" != "N/A" ]; then
    # Replicas
    SOURCE_REPLICAS=$(kubectl get deployment "$SOURCE_DEPLOY" -n "$SOURCE_NS" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "N/A")
    TARGET_REPLICAS=$(kubectl get deployment "$TARGET_DEPLOY" -n "$TARGET_NS" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "N/A")
    
    if [ "$SOURCE_REPLICAS" = "$TARGET_REPLICAS" ]; then
        STATUS="${GREEN}相同${NC}"
    else
        STATUS="${YELLOW}不同${NC}"
    fi
    print_table_row "副本数 (Replicas)" "$SOURCE_REPLICAS" "$TARGET_REPLICAS" "$STATUS"
    
    # Image
    SOURCE_IMAGE=$(kubectl get deployment "$SOURCE_DEPLOY" -n "$SOURCE_NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "N/A")
    TARGET_IMAGE=$(kubectl get deployment "$TARGET_DEPLOY" -n "$TARGET_NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "N/A")
    
    if [ "$SOURCE_IMAGE" = "$TARGET_IMAGE" ]; then
        STATUS="${GREEN}相同${NC}"
    else
        STATUS="${YELLOW}不同${NC}"
    fi
    print_table_row "Container Image" "$SOURCE_IMAGE" "$TARGET_IMAGE" "$STATUS"
    
    # CP Connection Info
    SOURCE_CP_FULL=$(extract_cp_info "$SOURCE_NS" "$SOURCE_DEPLOY" "full")
    TARGET_CP_FULL=$(extract_cp_info "$TARGET_NS" "$TARGET_DEPLOY" "full")
    
    if [ "$SOURCE_CP_FULL" = "$TARGET_CP_FULL" ]; then
        STATUS="${GREEN}相同${NC}"
    else
        STATUS="${YELLOW}不同${NC}"
    fi
    print_table_row "CP 连接地址 (KONG_CLUSTER_CONTROL_PLANE)" "$SOURCE_CP_FULL" "$TARGET_CP_FULL" "$STATUS"
    
    # Extract CP Host and Port separately
    SOURCE_CP_HOST=$(extract_cp_info "$SOURCE_NS" "$SOURCE_DEPLOY" "host")
    TARGET_CP_HOST=$(extract_cp_info "$TARGET_NS" "$TARGET_DEPLOY" "host")
    SOURCE_CP_PORT=$(extract_cp_info "$SOURCE_NS" "$SOURCE_DEPLOY" "port")
    TARGET_CP_PORT=$(extract_cp_info "$TARGET_NS" "$TARGET_DEPLOY" "port")
    
    if [ "$SOURCE_CP_HOST" = "$TARGET_CP_HOST" ]; then
        STATUS="${GREEN}相同${NC}"
    else
        STATUS="${YELLOW}不同${NC}"
    fi
    print_table_row "CP Service Host" "$SOURCE_CP_HOST" "$TARGET_CP_HOST" "$STATUS"
    
    if [ "$SOURCE_CP_PORT" = "$TARGET_CP_PORT" ]; then
        STATUS="${GREEN}相同${NC}"
    else
        STATUS="${YELLOW}不同${NC}"
    fi
    print_table_row "CP Service Port" "$SOURCE_CP_PORT" "$TARGET_CP_PORT" "$STATUS"
fi

print_table_separator

# ==============================================================================
# 2. Secrets Comparison
# ==============================================================================
print_header "2. Secrets 对比"

# Find TLS secrets
SOURCE_SECRETS=$(kubectl get secrets -n "$SOURCE_NS" -o json 2>/dev/null | jq -r '.items[] | select(.type=="kubernetes.io/tls") | .metadata.name')
TARGET_SECRETS=$(kubectl get secrets -n "$TARGET_NS" -o json 2>/dev/null | jq -r '.items[] | select(.type=="kubernetes.io/tls") | .metadata.name')

print_subheader "TLS Secrets 列表"

echo -e "${CYAN}源 Namespace ($SOURCE_NS) 的 TLS Secrets:${NC}"
if [ -z "$SOURCE_SECRETS" ]; then
    print_warning "未找到 TLS 类型的 Secrets"
else
    echo "$SOURCE_SECRETS" | while read -r secret; do
        echo "  - $secret"
    done
fi

echo ""
echo -e "${CYAN}目标 Namespace ($TARGET_NS) 的 TLS Secrets:${NC}"
if [ -z "$TARGET_SECRETS" ]; then
    print_warning "未找到 TLS 类型的 Secrets"
else
    echo "$TARGET_SECRETS" | while read -r secret; do
        echo "  - $secret"
    done
fi

# Compare common secrets
if [ -n "$SOURCE_SECRETS" ] && [ -n "$TARGET_SECRETS" ]; then
    print_subheader "证书详细对比"
    
    # Find common secret names
    COMMON_SECRETS=$(comm -12 <(echo "$SOURCE_SECRETS" | sort) <(echo "$TARGET_SECRETS" | sort))
    
    if [ -n "$COMMON_SECRETS" ]; then
        echo -e "${GREEN}找到同名的 Secrets，进行证书对比:${NC}"
        echo ""
        
        echo "$COMMON_SECRETS" | while read -r secret_name; do
            print_info "对比 Secret: $secret_name"
            print_table_separator
            print_table_row "证书属性" "源 ($SOURCE_NS)" "目标 ($TARGET_NS)" "状态"
            print_table_separator
            
            # CN (Common Name)
            SOURCE_CN=$(extract_cert_info "$SOURCE_NS" "$secret_name" "cn")
            TARGET_CN=$(extract_cert_info "$TARGET_NS" "$secret_name" "cn")
            if [ "$SOURCE_CN" = "$TARGET_CN" ]; then
                STATUS="${GREEN}相同${NC}"
            else
                STATUS="${YELLOW}不同${NC}"
            fi
            print_table_row "Common Name (CN)" "$SOURCE_CN" "$TARGET_CN" "$STATUS"
            
            # Subject
            SOURCE_SUBJECT=$(extract_cert_info "$SOURCE_NS" "$secret_name" "subject")
            TARGET_SUBJECT=$(extract_cert_info "$TARGET_NS" "$secret_name" "subject")
            if [ "$SOURCE_SUBJECT" = "$TARGET_SUBJECT" ]; then
                STATUS="${GREEN}相同${NC}"
            else
                STATUS="${YELLOW}不同${NC}"
            fi
            SOURCE_SUBJECT_SHORT=$(echo "$SOURCE_SUBJECT" | cut -c1-35)
            TARGET_SUBJECT_SHORT=$(echo "$TARGET_SUBJECT" | cut -c1-35)
            print_table_row "证书 Subject" "$SOURCE_SUBJECT_SHORT..." "$TARGET_SUBJECT_SHORT..." "$STATUS"
            
            # Issuer
            SOURCE_ISSUER=$(extract_cert_info "$SOURCE_NS" "$secret_name" "issuer")
            TARGET_ISSUER=$(extract_cert_info "$TARGET_NS" "$secret_name" "issuer")
            if [ "$SOURCE_ISSUER" = "$TARGET_ISSUER" ]; then
                STATUS="${GREEN}相同${NC}"
            else
                STATUS="${YELLOW}不同${NC}"
            fi
            SOURCE_ISSUER_SHORT=$(echo "$SOURCE_ISSUER" | cut -c1-35)
            TARGET_ISSUER_SHORT=$(echo "$TARGET_ISSUER" | cut -c1-35)
            print_table_row "证书 Issuer" "$SOURCE_ISSUER_SHORT..." "$TARGET_ISSUER_SHORT..." "$STATUS"
            
            # Expiry Date
            SOURCE_EXPIRY=$(extract_cert_info "$SOURCE_NS" "$secret_name" "enddate")
            TARGET_EXPIRY=$(extract_cert_info "$TARGET_NS" "$secret_name" "enddate")
            if [ "$SOURCE_EXPIRY" = "$TARGET_EXPIRY" ]; then
                STATUS="${GREEN}相同${NC}"
            else
                STATUS="${YELLOW}不同${NC}"
            fi
            print_table_row "过期时间" "$SOURCE_EXPIRY" "$TARGET_EXPIRY" "$STATUS"
            
            print_table_separator
            echo ""
            
            if [ "$DETAIL_LEVEL" = "detailed" ]; then
                # Show SAN if detailed mode
                SOURCE_SAN=$(extract_cert_info "$SOURCE_NS" "$secret_name" "san")
                TARGET_SAN=$(extract_cert_info "$TARGET_NS" "$secret_name" "san")
                
                echo -e "${CYAN}Subject Alternative Names (SAN):${NC}"
                echo -e "${YELLOW}源:${NC} $SOURCE_SAN"
                echo -e "${YELLOW}目标:${NC} $TARGET_SAN"
                echo ""
            fi
        done
    else
        print_warning "未找到同名的 TLS Secrets"
    fi
    
    # Show unique secrets
    SOURCE_ONLY=$(comm -23 <(echo "$SOURCE_SECRETS" | sort) <(echo "$TARGET_SECRETS" | sort))
    TARGET_ONLY=$(comm -13 <(echo "$SOURCE_SECRETS" | sort) <(echo "$TARGET_SECRETS" | sort))
    
    if [ -n "$SOURCE_ONLY" ]; then
        print_diff "仅存在于源 Namespace 的 Secrets:"
        echo "$SOURCE_ONLY" | while read -r secret; do
            echo "  - $secret"
        done
    fi
    
    if [ -n "$TARGET_ONLY" ]; then
        print_diff "仅存在于目标 Namespace 的 Secrets:"
        echo "$TARGET_ONLY" | while read -r secret; do
            echo "  - $secret"
        done
    fi
fi

# Additional cert-secret certificate details
if [ -n "$SOURCE_SECRETS" ] || [ -n "$TARGET_SECRETS" ]; then
    print_subheader "证书详细信息 (cert-secret 结尾)"
    echo -e "${CYAN}Using openssl to extract certificate information...${NC}\n"
    
    # Find secrets ending with cert-secret
    SOURCE_CERT_SECRETS=$(echo "$SOURCE_SECRETS" | grep 'cert-secret$' || echo "")
    TARGET_CERT_SECRETS=$(echo "$TARGET_SECRETS" | grep 'cert-secret$' || echo "")
    
    # Process source namespace cert-secrets
    if [ -n "$SOURCE_CERT_SECRETS" ]; then
        echo -e "${GREEN}源 Namespace ($SOURCE_NS) 的 cert-secret 证书:${NC}"
        echo ""
        
        echo "$SOURCE_CERT_SECRETS" | while read -r secret_name; do
            [ -z "$secret_name" ] && continue
            
            echo -e "${YELLOW}📜 Secret: $secret_name${NC}"
            
            # Extract certificate data
            CERT_DATA=$(kubectl get secret "$secret_name" -n "$SOURCE_NS" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            
            if [ -z "$CERT_DATA" ]; then
                print_warning "  无法读取证书数据"
                echo ""
                continue
            fi
            
            # Extract CN
            CN=$(echo "$CERT_DATA" | openssl x509 -noout -subject 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' || echo "N/A")
            echo "  Common Name (CN): $CN"
            
            # Extract SAN
            SAN=$(echo "$CERT_DATA" | openssl x509 -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^[[:space:]]*//' || echo "N/A")
            echo "  Subject Alternative Names (SAN):"
            if [ "$SAN" != "N/A" ]; then
                # Format SAN for better readability
                echo "$SAN" | tr ',' '\n' | while read -r san_entry; do
                    [ -n "$san_entry" ] && echo "    - $(echo "$san_entry" | xargs)"
                done
            else
                echo "    - N/A"
            fi
            
            # Extract expiry date
            EXPIRY=$(echo "$CERT_DATA" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "N/A")
            echo "  过期时间: $EXPIRY"
            
            # Check if expired
            if [ "$EXPIRY" != "N/A" ]; then
                EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y %Z" "$EXPIRY" "+%s" 2>/dev/null || echo "0")
                NOW_EPOCH=$(date "+%s")
                if [ "$EXPIRY_EPOCH" -gt 0 ]; then
                    if [ "$EXPIRY_EPOCH" -lt "$NOW_EPOCH" ]; then
                        echo -e "  ${RED}状态: 已过期 ❌${NC}"
                    else
                        DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
                        if [ "$DAYS_LEFT" -lt 30 ]; then
                            echo -e "  ${YELLOW}状态: 即将过期 (剩余 $DAYS_LEFT 天) ⚠️${NC}"
                        else
                            echo -e "  ${GREEN}状态: 有效 (剩余 $DAYS_LEFT 天) ✅${NC}"
                        fi
                    fi
                fi
            fi
            
            echo ""
        done
    else
        echo -e "${CYAN}源 Namespace ($SOURCE_NS) 中未找到 cert-secret 结尾的证书${NC}"
        echo ""
    fi
    
    # Process target namespace cert-secrets
    if [ -n "$TARGET_CERT_SECRETS" ]; then
        echo -e "${GREEN}目标 Namespace ($TARGET_NS) 的 cert-secret 证书:${NC}"
        echo ""
        
        echo "$TARGET_CERT_SECRETS" | while read -r secret_name; do
            [ -z "$secret_name" ] && continue
            
            echo -e "${YELLOW}📜 Secret: $secret_name${NC}"
            
            # Extract certificate data
            CERT_DATA=$(kubectl get secret "$secret_name" -n "$TARGET_NS" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            
            if [ -z "$CERT_DATA" ]; then
                print_warning "  无法读取证书数据"
                echo ""
                continue
            fi
            
            # Extract CN
            CN=$(echo "$CERT_DATA" | openssl x509 -noout -subject 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' || echo "N/A")
            echo "  Common Name (CN): $CN"
            
            # Extract SAN
            SAN=$(echo "$CERT_DATA" | openssl x509 -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^[[:space:]]*//' || echo "N/A")
            echo "  Subject Alternative Names (SAN):"
            if [ "$SAN" != "N/A" ]; then
                # Format SAN for better readability
                echo "$SAN" | tr ',' '\n' | while read -r san_entry; do
                    [ -n "$san_entry" ] && echo "    - $(echo "$san_entry" | xargs)"
                done
            else
                echo "    - N/A"
            fi
            
            # Extract expiry date
            EXPIRY=$(echo "$CERT_DATA" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "N/A")
            echo "  过期时间: $EXPIRY"
            
            # Check if expired
            if [ "$EXPIRY" != "N/A" ]; then
                EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y %Z" "$EXPIRY" "+%s" 2>/dev/null || echo "0")
                NOW_EPOCH=$(date "+%s")
                if [ "$EXPIRY_EPOCH" -gt 0 ]; then
                    if [ "$EXPIRY_EPOCH" -lt "$NOW_EPOCH" ]; then
                        echo -e "  ${RED}状态: 已过期 ❌${NC}"
                    else
                        DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
                        if [ "$DAYS_LEFT" -lt 30 ]; then
                            echo -e "  ${YELLOW}状态: 即将过期 (剩余 $DAYS_LEFT 天) ⚠️${NC}"
                        else
                            echo -e "  ${GREEN}状态: 有效 (剩余 $DAYS_LEFT 天) ✅${NC}"
                        fi
                    fi
                fi
            fi
            
            echo ""
        done
    else
        echo -e "${CYAN}目标 Namespace ($TARGET_NS) 中未找到 cert-secret 结尾的证书${NC}"
        echo ""
    fi
fi

# ==============================================================================
# 3. Service Comparison
# ==============================================================================
print_header "3. Service 对比"

SOURCE_SVCS=$(kubectl get svc -n "$SOURCE_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
TARGET_SVCS=$(kubectl get svc -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

print_subheader "Service 列表"

echo -e "${CYAN}源 Namespace ($SOURCE_NS):${NC}"
if [ -z "$SOURCE_SVCS" ]; then
    print_warning "未找到 Service"
else
    for svc in $SOURCE_SVCS; do
        SVC_TYPE=$(kubectl get svc "$svc" -n "$SOURCE_NS" -o jsonpath='{.spec.type}' 2>/dev/null)
        SVC_PORTS=$(kubectl get svc "$svc" -n "$SOURCE_NS" -o jsonpath='{.spec.ports[*].port}' 2>/dev/null)
        echo "  - $svc (Type: $SVC_TYPE, Ports: $SVC_PORTS)"
    done
fi

echo ""
echo -e "${CYAN}目标 Namespace ($TARGET_NS):${NC}"
if [ -z "$TARGET_SVCS" ]; then
    print_warning "未找到 Service"
else
    for svc in $TARGET_SVCS; do
        SVC_TYPE=$(kubectl get svc "$svc" -n "$TARGET_NS" -o jsonpath='{.spec.type}' 2>/dev/null)
        SVC_PORTS=$(kubectl get svc "$svc" -n "$TARGET_NS" -o jsonpath='{.spec.ports[*].port}' 2>/dev/null)
        echo "  - $svc (Type: $SVC_TYPE, Ports: $SVC_PORTS)"
    done
fi

# Show differences
if [ -n "$SOURCE_SVCS" ] && [ -n "$TARGET_SVCS" ]; then
    SOURCE_SVC_SORTED=$(echo "$SOURCE_SVCS" | tr ' ' '\n' | sort)
    TARGET_SVC_SORTED=$(echo "$TARGET_SVCS" | tr ' ' '\n' | sort)
    
    SOURCE_SVC_ONLY=$(comm -23 <(echo "$SOURCE_SVC_SORTED") <(echo "$TARGET_SVC_SORTED"))
    TARGET_SVC_ONLY=$(comm -13 <(echo "$SOURCE_SVC_SORTED") <(echo "$TARGET_SVC_SORTED"))
    
    echo ""
    if [ -n "$SOURCE_SVC_ONLY" ]; then
        print_diff "仅存在于源的 Services:"
        echo "$SOURCE_SVC_ONLY" | while read -r svc; do
            echo "  - $svc"
        done
    fi
    
    if [ -n "$TARGET_SVC_ONLY" ]; then
        print_diff "仅存在于目标的 Services:"
        echo "$TARGET_SVC_ONLY" | while read -r svc; do
            echo "  - $svc"
        done
    fi
fi

# ==============================================================================
# 4. ServiceAccount Comparison
# ==============================================================================
print_header "4. ServiceAccount 对比"

SOURCE_SAS=$(kubectl get sa -n "$SOURCE_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -v "^default$" | sort || echo "")
TARGET_SAS=$(kubectl get sa -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -v "^default$" | sort || echo "")

echo -e "${CYAN}源 Namespace:${NC} $(echo "$SOURCE_SAS" | wc -l | tr -d ' ') 个 ServiceAccount"
echo -e "${CYAN}目标 Namespace:${NC} $(echo "$TARGET_SAS" | wc -l | tr -d ' ') 个 ServiceAccount"
echo ""

COMMON_SAS=$(comm -12 <(echo "$SOURCE_SAS") <(echo "$TARGET_SAS"))
SOURCE_SA_ONLY=$(comm -23 <(echo "$SOURCE_SAS") <(echo "$TARGET_SAS"))
TARGET_SA_ONLY=$(comm -13 <(echo "$SOURCE_SAS") <(echo "$TARGET_SAS"))

if [ -n "$COMMON_SAS" ]; then
    print_success "共同的 ServiceAccounts:"
    echo "$COMMON_SAS" | while read -r sa; do
        echo "  - $sa"
    done
    echo ""
fi

if [ -n "$SOURCE_SA_ONLY" ]; then
    print_diff "仅存在于源的 ServiceAccounts:"
    echo "$SOURCE_SA_ONLY" | while read -r sa; do
        echo "  - $sa"
    done
    echo ""
fi

if [ -n "$TARGET_SA_ONLY" ]; then
    print_diff "仅存在于目标的 ServiceAccounts:"
    echo "$TARGET_SA_ONLY" | while read -r sa; do
        echo "  - $sa"
    done
    echo ""
fi

# ==============================================================================
# 5. NetworkPolicy Comparison
# ==============================================================================
print_header "5. NetworkPolicy 对比"

SOURCE_NETPOLS=$(kubectl get networkpolicy -n "$SOURCE_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | sort || echo "")
TARGET_NETPOLS=$(kubectl get networkpolicy -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | sort || echo "")

echo -e "${CYAN}源 Namespace:${NC} $(echo "$SOURCE_NETPOLS" | grep -v '^$' | wc -l | tr -d ' ') 个 NetworkPolicy"
echo -e "${CYAN}目标 Namespace:${NC} $(echo "$TARGET_NETPOLS" | grep -v '^$' | wc -l | tr -d ' ') 个 NetworkPolicy"
echo ""

if [ -n "$SOURCE_NETPOLS" ]; then
    echo -e "${CYAN}源 Namespace NetworkPolicies:${NC}"
    echo "$SOURCE_NETPOLS" | while read -r np; do
        [ -n "$np" ] && echo "  - $np"
    done
    echo ""
fi

if [ -n "$TARGET_NETPOLS" ]; then
    echo -e "${CYAN}目标 Namespace NetworkPolicies:${NC}"
    echo "$TARGET_NETPOLS" | while read -r np; do
        [ -n "$np" ] && echo "  - $np"
    done
    echo ""
fi

if [ -n "$SOURCE_NETPOLS" ] && [ -n "$TARGET_NETPOLS" ]; then
    COMMON_NPS=$(comm -12 <(echo "$SOURCE_NETPOLS") <(echo "$TARGET_NETPOLS"))
    SOURCE_NP_ONLY=$(comm -23 <(echo "$SOURCE_NETPOLS") <(echo "$TARGET_NETPOLS"))
    TARGET_NP_ONLY=$(comm -13 <(echo "$SOURCE_NETPOLS") <(echo "$TARGET_NETPOLS"))
    
    if [ -n "$COMMON_NPS" ]; then
        print_success "共同的 NetworkPolicies:"
        echo "$COMMON_NPS" | while read -r np; do
            [ -n "$np" ] && echo "  - $np"
        done
        echo ""
    fi
    
    if [ -n "$SOURCE_NP_ONLY" ]; then
        print_diff "仅存在于源的 NetworkPolicies:"
        echo "$SOURCE_NP_ONLY" | while read -r np; do
            [ -n "$np" ] && echo "  - $np"
        done
        echo ""
    fi
    
    if [ -n "$TARGET_NP_ONLY" ]; then
        print_diff "仅存在于目标的 NetworkPolicies:"
        echo "$TARGET_NP_ONLY" | while read -r np; do
            [ -n "$np" ] && echo "  - $np"
        done
        echo ""
    fi
fi

# ==============================================================================
# 6. Pod Status Comparison
# ==============================================================================
print_header "6. Pod 状态对比"

SOURCE_PODS=$(kubectl get pods -n "$SOURCE_NS" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
TARGET_PODS=$(kubectl get pods -n "$TARGET_NS" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')

SOURCE_POD_COUNT=$(echo "$SOURCE_PODS" | jq -r '.items | length')
TARGET_POD_COUNT=$(echo "$TARGET_PODS" | jq -r '.items | length')

print_table_separator
print_table_row "属性" "源 ($SOURCE_NS)" "目标 ($TARGET_NS)" "状态"
print_table_separator
print_table_row "Pod 数量" "$SOURCE_POD_COUNT" "$TARGET_POD_COUNT" "$([ "$SOURCE_POD_COUNT" = "$TARGET_POD_COUNT" ] && echo "${GREEN}相同${NC}" || echo "${YELLOW}不同${NC}")"

if [ "$SOURCE_POD_COUNT" -gt 0 ] && [ "$TARGET_POD_COUNT" -gt 0 ]; then
    # Compare first pod
    SOURCE_POD_NAME=$(echo "$SOURCE_PODS" | jq -r '.items[0].metadata.name')
    TARGET_POD_NAME=$(echo "$TARGET_PODS" | jq -r '.items[0].metadata.name')
    
    SOURCE_POD_STATUS=$(echo "$SOURCE_PODS" | jq -r '.items[0].status.phase')
    TARGET_POD_STATUS=$(echo "$TARGET_PODS" | jq -r '.items[0].status.phase')
    
    SOURCE_POD_READY=$(echo "$SOURCE_PODS" | jq -r '.items[0].status.containerStatuses[0].ready')
    TARGET_POD_READY=$(echo "$TARGET_PODS" | jq -r '.items[0].status.containerStatuses[0].ready')
    
    SOURCE_POD_RESTARTS=$(echo "$SOURCE_PODS" | jq -r '.items[0].status.containerStatuses[0].restartCount')
    TARGET_POD_RESTARTS=$(echo "$TARGET_PODS" | jq -r '.items[0].status.containerStatuses[0].restartCount')
    
    print_table_row "Pod Status" "$SOURCE_POD_STATUS" "$TARGET_POD_STATUS" "$([ "$SOURCE_POD_STATUS" = "$TARGET_POD_STATUS" ] && echo "${GREEN}相同${NC}" || echo "${YELLOW}不同${NC}")"
    print_table_row "Pod Ready" "$SOURCE_POD_READY" "$TARGET_POD_READY" "$([ "$SOURCE_POD_READY" = "$TARGET_POD_READY" ] && echo "${GREEN}相同${NC}" || echo "${YELLOW}不同${NC}")"
    print_table_row "Restart Count" "$SOURCE_POD_RESTARTS" "$TARGET_POD_RESTARTS" "$([ "$SOURCE_POD_RESTARTS" = "$TARGET_POD_RESTARTS" ] && echo "${GREEN}相同${NC}" || echo "${YELLOW}不同${NC}")"
fi

print_table_separator

# ==============================================================================
# Summary
# ==============================================================================
print_header "7. 对比总结"

echo -e "${CYAN}对比维度:${NC}"
echo "  ✓ Deployment (名称、副本数、镜像、CP 连接配置)"
echo "  ✓ Secrets (TLS 证书、Subject、Issuer、过期时间)"
echo "  ✓ Service (类型、端口)"
echo "  ✓ ServiceAccount"
echo "  ✓ NetworkPolicy"
echo "  ✓ Pod (数量、状态、就绪状态、重启次数)"
echo ""

print_info "提示: 使用 -d detailed 参数查看更详细的证书信息 (如 SAN)"
print_info "提示: 所有标记为 ${YELLOW}不同${NC} 的项目需要进一步检查"

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}对比完成!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

```

## `verify-dp.sh`

```bash
#!/bin/bash

#
# verify-dp.sh
#
# This script is a combination of multiple scripts and markdown files
# to provide a comprehensive verification of Kong DP status.
#

# --- Start of verify-dp-status-gemini.sh ---
#!/bin/bash

# Kong Data Plane Status Verification Script (Gemini Optimized)
# Usage: ./verify-dp-status-gemini.sh [-n namespace] [-l label-selector] [-s secret-name]
#
# Optimization:
# - Automatically detects CP address from DP Deployment env vars (KONG_CLUSTER_CONTROL_PLANE)
# - Enhanced error handling and reporting

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="aibang-int-kdp"
#LABEL_SELECTOR="app=kong-dp"
# add a labels 
# kubectl label deployment <deployment-name> <label-key>=<label-value> -n <namespace>
# kubectl label deployment busybox-app app=busybox-app -n bass-int-kdp
LABEL_SELECTOR="app=busybox-app"
SECRET_NAME="lex-tls-secret"
CP_ADMIN_PORT="8001"

# Parse command line arguments
while getopts "n:l:s:h" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    l) LABEL_SELECTOR="$OPTARG" ;;
    s) SECRET_NAME="$OPTARG" ;;
    h) 
      echo "Usage: $0 [-n namespace] [-l label-selector] [-s secret-name]"
      echo "  -n: Kubernetes namespace (default: $NAMESPACE)"
      echo "  -l: DP Deployment label selector (default: $LABEL_SELECTOR)"
      echo "  -s: TLS secret name (default: $SECRET_NAME)"
      exit 0
      ;;
    \?) 
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Helper functions
print_header() {
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

# Main script
echo -e "${GREEN}Kong Data Plane Status Verification (Optimized)${NC}"
echo -e "Namespace: ${YELLOW}$NAMESPACE${NC}"
echo -e "Label Selector: ${YELLOW}$LABEL_SELECTOR${NC}"

# 0. Dynamic Configuration Discovery
print_header "0. 动态配置发现 (Configuration Discovery)"

print_info "0.1 查找 Kong DP Deployment..."
DP_DEPLOYMENT=$(kubectl get deployment -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$DP_DEPLOYMENT" ]; then
  print_error "未找到带有标签 '$LABEL_SELECTOR' 的 Deployment"
  print_info "请检查 Namespace 或 Label Selector 是否正确"
  exit 1
fi

print_success "找到 Deployment: $DP_DEPLOYMENT"

print_info "0.2 从 Deployment 获取 CP 连接信息..."
# Try to get KONG_CLUSTER_CONTROL_PLANE from env
CP_ENV_VALUE=$(kubectl get deployment "$DP_DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KONG_CLUSTER_CONTROL_PLANE")].value}' 2>/dev/null || echo "")

if [ -z "$CP_ENV_VALUE" ]; then
  print_warning "未在环境变量中找到 KONG_CLUSTER_CONTROL_PLANE"
  print_info "尝试使用默认值 kong-cp:8005"
  CP_SERVICE="kong-cp"
  CP_PORT="8005"
else
  print_success "发现配置 KONG_CLUSTER_CONTROL_PLANE=$CP_ENV_VALUE"
  # Parse host and port
  # Handle cases like "kong-cp:8005", "https://kong-cp:8005", "kong-cp" (default 8005)
  CLEAN_VAL=${CP_ENV_VALUE#*://} # Remove protocol if present
  
  if [[ "$CLEAN_VAL" == *":"* ]]; then
    CP_SERVICE=$(echo "$CLEAN_VAL" | cut -d: -f1)
    CP_PORT=$(echo "$CLEAN_VAL" | cut -d: -f2)
  else
    CP_SERVICE="$CLEAN_VAL"
    CP_PORT="8005" # Default port if not specified
  fi
fi

echo -e "CP Service Host: ${YELLOW}$CP_SERVICE${NC}"
echo -e "CP Service Port: ${YELLOW}$CP_PORT${NC}"


# 1. Infrastructure Layer Check
print_header "1. 基础设施层检查 (Infrastructure Health)"

print_info "1.1 检查 Kong DP Pods 状态..."
DP_PODS=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
POD_COUNT=$(echo "$DP_PODS" | jq -r '.items | length')

if [ "$POD_COUNT" -eq 0 ]; then
  print_error "未找到 Kong DP Pods"
  exit 1
else
  print_success "找到 $POD_COUNT 个 Kong DP Pod(s)"
  echo "$DP_PODS" | jq -r '.items[] | "\(.metadata.name) | Status: \(.status.phase) | Ready: \(.status.containerStatuses[0].ready) | Restarts: \(.status.containerStatuses[0].restartCount) | IP: \(.status.podIP)"'
fi

# Get first pod name for further checks
DP_POD_NAME=$(echo "$DP_PODS" | jq -r '.items[0].metadata.name // empty')

if [ -n "$DP_POD_NAME" ]; then
  print_info "1.2 检查 Pod 事件..."
  EVENTS=$(kubectl describe pod "$DP_POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep -A 10 "Events:" || echo "无法获取事件")
  if echo "$EVENTS" | grep -qE "Error|Failed|BackOff"; then
    print_error "发现异常事件:"
    echo "$EVENTS" | grep -E "Error|Failed|BackOff" | tail -5
  else
    print_success "未发现异常事件"
  fi
fi

# 2. Log Analysis
print_header "2. 日志层分析 (Log Analysis)"

if [ -n "$DP_POD_NAME" ]; then
  print_info "2.1 分析最近 100 行日志..."
  LOGS=$(kubectl logs "$DP_POD_NAME" -n "$NAMESPACE" --tail=100 2>/dev/null || echo "")
  
  if echo "$LOGS" | grep -q "control_plane: connected"; then
    print_success "DP 已成功连接到 CP (control_plane: connected)"
  elif echo "$LOGS" | grep -q "received initial configuration snapshot"; then
    print_success "DP 已接收到初始配置快照 (隐含连接成功)"
  else
    print_warning "未找到明确的连接成功信号 (可能是日志滚动了)"
  fi
  
  if echo "$LOGS" | grep -q "failed to connect to control plane"; then
    print_error "发现连接失败日志"
    echo "$LOGS" | grep "failed to connect" | tail -3
  fi
  
  if echo "$LOGS" | grep -q "certificate verify failed"; then
    print_error "发现证书验证失败日志"
    echo "$LOGS" | grep "certificate" | tail -3
  fi
else
  print_error "无法分析日志: 未找到 DP Pod"
fi

# 3. Control Plane Verification
print_header "3. 控制面层验证 (Control Plane Verification)"

# Try to find CP pod based on CP Service name (heuristic)
# Assuming CP deployment has label app=kong-cp or similar, but let's try to guess from service
print_info "3.1 尝试查找 CP Pod..."
# Heuristic: try to find a pod that looks like the CP service name
CP_POD_GUESS=$(kubectl get pods -n "$NAMESPACE" | grep "${CP_SERVICE%-*}" | grep -v "$DP_POD_NAME" | head -1 | awk '{print $1}')

if [ -n "$CP_POD_GUESS" ]; then
  print_info "推测 CP Pod 为: $CP_POD_GUESS"
  CLUSTER_STATUS=$(kubectl exec -it "$CP_POD_GUESS" -n "$NAMESPACE" -- curl -s http://localhost:$CP_ADMIN_PORT/clustering/status 2>/dev/null || echo '{}')
  
  DP_COUNT=$(echo "$CLUSTER_STATUS" | jq -r '.data_planes | length // 0')
  print_info "CP 注册的 DP 节点数: $DP_COUNT"
  
  if [ "$DP_COUNT" -gt 0 ]; then
    if [ -n "$DP_POD_NAME" ]; then
      DP_IP=$(kubectl get pod "$DP_POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null)
      if echo "$CLUSTER_STATUS" | jq -e ".data_planes[] | select(.ip == \"$DP_IP\")" > /dev/null 2>&1; then
        print_success "当前 DP Pod ($DP_IP) 已在 CP 注册"
      else
        print_error "当前 DP Pod ($DP_IP) 未在 CP 注册表中找到"
      fi
    fi
  else
    print_warning "CP 返回的 DP 列表为空 (或者无法连接 CP Admin API)"
  fi
else
  print_warning "无法自动定位 CP Pod，跳过 CP 端验证"
fi

# 4. Network Connectivity
print_header "4. 网络层连通性探测 (Network Connectivity)"

if [ -n "$DP_POD_NAME" ]; then
  print_info "4.1 测试 DP 到 CP 的网络连接 ($CP_SERVICE:$CP_PORT)..."
  
  # Test DNS resolution
  DNS_TEST=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- nslookup "$CP_SERVICE" 2>&1 || echo "DNS_FAILED")
  if echo "$DNS_TEST" | grep -q "DNS_FAILED\|can't resolve"; then
    print_error "DNS 解析失败: $CP_SERVICE"
  else
    print_success "DNS 解析成功"
  fi
  
  # Test TCP connectivity with curl
  print_info "4.2 测试 TCP 连接..."
  # Use the dynamically discovered CP_SERVICE and CP_PORT
  CONN_TEST=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- timeout 5 sh -c "curl -v --max-time 3 https://$CP_SERVICE:$CP_PORT 2>&1" || echo "CONNECTION_FAILED")
  
  if echo "$CONN_TEST" | grep -q "Connected to"; then
    print_success "TCP 连接成功 (网络层通畅)"
  elif echo "$CONN_TEST" | grep -q "SSL certificate problem"; then
    print_warning "TCP 连接成功，但证书验证失败 (网络通，需检查证书)"
  elif echo "$CONN_TEST" | grep -q "Connection timed out\|CONNECTION_FAILED"; then
    print_error "连接超时 (检查防火墙规则/安全组)"
  else
    print_warning "连接测试结果不明确"
    echo "$CONN_TEST" | head -5
  fi
else
  print_error "无法进行网络测试: 未找到 DP Pod"
fi

# 5. Security & Certificate Verification
print_header "5. 安全层与证书验证 (Certificate & Security)"

print_info "5.1 检查 TLS Secret '$SECRET_NAME'..."
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
  print_success "Secret 存在"
  
  # Check expiry
  CERT_EXPIRY=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
  if [ -n "$CERT_EXPIRY" ]; then
    print_info "证书过期时间: $CERT_EXPIRY"
    # Simple check if expired (requires date utils, skipping complex logic for brevity, just showing date)
  fi
else
  print_error "Secret '$SECRET_NAME' 不存在"
fi

if [ -n "$DP_POD_NAME" ]; then
  print_info "5.2 检查 DP Pod 内挂载的证书..."
  # Check env var for cert path if possible, otherwise guess default
  CERT_PATH="/etc/secrets/kong-cluster-cert/"
  MOUNTED_CERT=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- ls -la $CERT_PATH 2>/dev/null || echo "NOT_MOUNTED")
  
  if [ "$MOUNTED_CERT" = "NOT_MOUNTED" ]; then
    print_warning "默认路径 $CERT_PATH 未找到证书"
  else
    print_success "证书已挂载"
  fi
fi

echo -e "\n${GREEN}脚本执行完成!${NC}\n"


```

## `verify-dp-summary.sh`

```bash
#!/bin/bash

# verify-dp-summary.sh
#
# A concise summary status check for Kong Data Plane (DP).
# Builds upon verify-dp-status-gemini.sh but focuses on a high-level dashboard view.
#
# Usage: ./verify-dp-summary.sh [-n namespace] [-l label-selector] [-s secret-name]

set +e # Disable exit on error to ensure summary is printed even if some commands fail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="bass-int-kdp"
LABEL_SELECTOR="app=busybox-app"
SECRET_NAME="lex-tls-secret"
CP_ADMIN_PORT="8001"

# Parse command line arguments
while getopts "n:l:s:h" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    l) LABEL_SELECTOR="$OPTARG" ;;
    s) SECRET_NAME="$OPTARG" ;;
    h)
      echo "Usage: $0 [-n namespace] [-l label-selector] [-s secret-name]"
      echo "  -n: Kubernetes namespace (default: $NAMESPACE)"
      echo "  -l: DP Deployment label selector (default: $LABEL_SELECTOR)"
      echo "  -s: TLS secret name (default: $SECRET_NAME)"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Logging Helpers
log_step() {
    echo -e "${BLUE}>>> $1${NC}"
}
log_info() {
    echo -e "    ${CYAN}•${NC} $1"
}
log_warn() {
    echo -e "    ${YELLOW}⚠${NC} $1"
}
log_err() {
    echo -e "    ${RED}✖${NC} $1"
}
log_success() {
    echo -e "    ${GREEN}✔${NC} $1"
}

# Helper to check command inside pod
check_remote_cmd() {
    local pod=$1
    local cmd=$2
    kubectl exec "$pod" -n "$NAMESPACE" -- which "$cmd" > /dev/null 2>&1
    return $?
}

echo -e "\n${BLUE}Kong Data Plane Verification${NC}"
echo -e "Context: NS=${YELLOW}$NAMESPACE${NC} | Label=${YELLOW}$LABEL_SELECTOR${NC} | Secret=${YELLOW}$SECRET_NAME${NC}\n"

# Initialize Status Variables
STATUS_INFRA="SKIP"
STATUS_NET="SKIP"
STATUS_CP="SKIP"
STATUS_LOGS="SKIP"
STATUS_SEC="SKIP"

DETAIL_INFRA=""
DETAIL_NET=""
DETAIL_CP=""
DETAIL_LOGS=""
DETAIL_SEC=""

# --- 1. Infrastructure Check ---
log_step "1. Checking Infrastructure Layers"
DP_PODS=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
POD_COUNT=$(echo "$DP_PODS" | jq -r '.items | length')

if [ "$POD_COUNT" -gt 0 ]; then
    log_info "Found $POD_COUNT pod(s) with label '$LABEL_SELECTOR'."
    READY_COUNT=$(echo "$DP_PODS" | jq -r '[.items[] | select(.status.containerStatuses[0].ready == true)] | length')
    
    if [ "$READY_COUNT" -eq "$POD_COUNT" ]; then
        STATUS_INFRA="${GREEN}PASS${NC}"
        DETAIL_INFRA="$READY_COUNT/$POD_COUNT Pods Ready"
        log_success "All pods ready ($READY_COUNT/$POD_COUNT)."
    else
        STATUS_INFRA="${RED}FAIL${NC}"
        DETAIL_INFRA="$READY_COUNT/$POD_COUNT Pods Ready"
        log_err "Only $READY_COUNT/$POD_COUNT pods are ready."
    fi
    DP_POD_NAME=$(echo "$DP_PODS" | jq -r '.items[0].metadata.name')
    log_info "Using Pod '$DP_POD_NAME' for diagnostic commands."
else
    STATUS_INFRA="${RED}FAIL${NC}"
    DETAIL_INFRA="No Pods Found"
    DP_POD_NAME=""
    log_err "No pods found matching selector."
fi

# --- Configuration Discovery for CP ---
log_step "Configuration Discovery"
CP_SERVICE="www.baidu.com"
CP_PORT="443"

if [ -n "$DP_POD_NAME" ]; then
    DP_DEPLOYMENT=$(kubectl get deployment -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    CP_ENV_VALUE=$(kubectl get deployment "$DP_DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KONG_CLUSTER_CONTROL_PLANE")].value}' 2>/dev/null || echo "")
    
    if [ -n "$CP_ENV_VALUE" ]; then
        log_info "Found env KONG_CLUSTER_CONTROL_PLANE=$CP_ENV_VALUE"
        CLEAN_VAL=${CP_ENV_VALUE#*://}
        if [[ "$CLEAN_VAL" == *":"* ]]; then
            CP_SERVICE=$(echo "$CLEAN_VAL" | cut -d: -f1)
            #CP_SERVICE="www.baidu.com"
            CP_PORT=$(echo "$CLEAN_VAL" | cut -d: -f2)
            #CP_PORT="443"
        else
            CP_SERVICE="$CLEAN_VAL"
            CP_PORT="8005"
        fi
    else
        log_warn "Env KONG_CLUSTER_CONTROL_PLANE not found, defaulting to $CP_SERVICE:$CP_PORT"
    fi
else
    log_warn "Cannot check env vars (no pod found)."
fi
log_info "Target Control Plane: ${YELLOW}$CP_SERVICE:$CP_PORT${NC}"

# --- 2. Network Connectivity ---
log_step "2. Checking Network Connectivity"
if [ -n "$DP_POD_NAME" ]; then
    # Detect curl or wget
    if check_remote_cmd "$DP_POD_NAME" "curl"; then
        CMD="timeout 5 curl -v --max-time 3 https://$CP_SERVICE:$CP_PORT"
        TOOL="curl"
    elif check_remote_cmd "$DP_POD_NAME" "wget"; then
        CMD="timeout 5 wget --no-check-certificate -T 3 -O - https://$CP_SERVICE:$CP_PORT"
        TOOL="wget"
    else
        CMD=""
        TOOL="none"
    fi

    if [ -n "$CMD" ]; then
        log_info "Testing connectivity using $TOOL..."
        # Capture both stdout and stderr
        CONN_OUTPUT=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- sh -c "$CMD" 2>&1 || echo "CMD_FAILED")
        
        # Simple analysis of output for logging
        if echo "$CONN_OUTPUT" | grep -qE "Connected to|succeed|SSL|200|404"; then
             STATUS_NET="${GREEN}PASS${NC}"
             DETAIL_NET="Connected"
             log_success "Connection successful."
        elif echo "$CONN_OUTPUT" | grep -q "SSL certificate problem"; then
             STATUS_NET="${YELLOW}WARN${NC}"
             DETAIL_NET="SSL Verify Fail"
             log_warn "Connection successful but SSL verification failed."
        else
             STATUS_NET="${RED}FAIL${NC}"
             DETAIL_NET="Connection Failed"
             log_err "Connection failed."
             log_info "Output snippet: $(echo "$CONN_OUTPUT" | tail -n 2)"
        fi
    else
        STATUS_NET="${YELLOW}SKIP${NC}"
        DETAIL_NET="No curl/wget"
        log_warn "Neither 'curl' nor 'wget' found in pod."
    fi
else
    STATUS_NET="${RED}FAIL${NC}"
    DETAIL_NET="No DP Pod"
    log_err "Skipping network check (no pod)."
fi

# --- 3. Control Plane Registration  we can deleted this logic ---
log_step "3. Checking Control Plane Registration"
# Heuristic to find CP pod.
CP_POD_GUESS=$(kubectl get pods -n "$NAMESPACE" -l "app=kong-cp" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$CP_POD_GUESS" ]; then
    # Try fuzzy match if label fails
    CP_POD_GUESS=$(kubectl get pods -n "$NAMESPACE" | grep "kong-cp" | grep -v "$DP_POD_NAME" | head -1 | awk '{print $1}')
fi

if [ -n "$CP_POD_GUESS" ]; then
    log_info "Identified CP Pod: $CP_POD_GUESS"
    CLUSTER_STATUS=$(kubectl exec -it "$CP_POD_GUESS" -n "$NAMESPACE" -- curl -s http://localhost:$CP_ADMIN_PORT/clustering/status 2>/dev/null || echo '{}')
    
    # Check if curl failed (empty json)
    if [ "$CLUSTER_STATUS" == "{}" ] || [ -z "$CLUSTER_STATUS" ]; then
         log_warn "Failed to retrieve clustering status from CP."
         STATUS_CP="${YELLOW}SKIP${NC}"
         DETAIL_CP="CP Status Query Fail"
    else
        DP_COUNT_CP=$(echo "$CLUSTER_STATUS" | jq -r '.data_planes | length // 0')
        log_info "CP reports $DP_COUNT_CP connected Data Plane(s)."

        if [ "$DP_COUNT_CP" -gt 0 ]; then
            if [ -n "$DP_POD_NAME" ]; then
                 DP_IP=$(kubectl get pod "$DP_POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null)
                 # Check IP
                 if echo "$CLUSTER_STATUS" | jq -e ".data_planes[] | select(.ip == \"$DP_IP\")" > /dev/null 2>&1; then
                    STATUS_CP="${GREEN}PASS${NC}"
                    DETAIL_CP="Registered"
                    log_success "DP Pod IP ($DP_IP) found in CP registry."
                 else
                    STATUS_CP="${RED}FAIL${NC}"
                    DETAIL_CP="Not Registered"
                    log_err "DP Pod IP ($DP_IP) NOT found in CP registry."
                 fi
            else
                 STATUS_CP="${YELLOW}WARN${NC}"
                 DETAIL_CP="DPs exist, self unknown"
            fi
        else
            STATUS_CP="${RED}FAIL${NC}"
            DETAIL_CP="No DPs connected"
            log_err "CP registry is empty."
        fi
    fi
else
    STATUS_CP="${YELLOW}SKIP${NC}"
    DETAIL_CP="CP Pod not found (in ns '$NAMESPACE')"
    log_warn "Could not locate Control Plane pod in namespace '$NAMESPACE'. Skipping registration check."
fi

# --- 4. Logs Analysis ---
log_step "4. Logs Analysis"
if [ -n "$DP_POD_NAME" ]; then
    IS_BUSYBOX=0
    if [[ "$DP_POD_NAME" == *"busybox"* ]]; then
        IS_BUSYBOX=1
        log_info "Pod appears to be 'busybox', skipping specific Kong logs check."
    fi
    
    if [ "$IS_BUSYBOX" -eq 1 ]; then
        STATUS_LOGS="${YELLOW}SKIP${NC}"
        DETAIL_LOGS="Skipped (Busybox)"
    else
        LOGS=$(kubectl logs "$DP_POD_NAME" -n "$NAMESPACE" --tail=50 2>/dev/null || echo "")
        log_info "Scanned last 50 lines of logs."
        if echo "$LOGS" | grep -q "control_plane: connected"; then
            STATUS_LOGS="${GREEN}PASS${NC}"
            DETAIL_LOGS="Connected signal found"
            log_success "Found 'control_plane: connected'."
        elif echo "$LOGS" | grep -q "received initial configuration snapshot"; then
            STATUS_LOGS="${GREEN}PASS${NC}"
            DETAIL_LOGS="Config synced"
            log_success "Found 'received initial configuration'."
        elif echo "$LOGS" | grep -q "failed to connect"; then
            STATUS_LOGS="${RED}FAIL${NC}"
            DETAIL_LOGS="Connection errors"
            log_err "Found connection errors in logs."
        else
            STATUS_LOGS="${YELLOW}WARN${NC}"
            DETAIL_LOGS="No clear signal"
            log_warn "No definitive success/failure signals in recent logs."
        fi
    fi
else
    STATUS_LOGS="${RED}FAIL${NC}"
    DETAIL_LOGS="No Logs"
    log_err "No pod to fetch logs from."
fi

# --- 5. Security Check ---
log_step "5. Security Check"
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
    log_info "Secret '$SECRET_NAME' found."
    CERT_EXPIRY=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    
    if [ -n "$CERT_EXPIRY" ]; then
        STATUS_SEC="${GREEN}PASS${NC}"
        DETAIL_SEC="Valid (found)"
        log_success "Certificate valid until: $CERT_EXPIRY"
    else
        STATUS_SEC="${RED}FAIL${NC}"
        DETAIL_SEC="Invalid Cert (parse fail)"
        log_err "Failed to parse certificate date."
    fi
else
    STATUS_SEC="${RED}FAIL${NC}"
    DETAIL_SEC="Secret Missing"
    log_err "Secret '$SECRET_NAME' not found."
fi

# --- Output Summary ---
echo ""
echo "Kong Data Plane Summary Status"
echo "=========================================================="
printf "%-15s | %-15s | %s\n" "CATEGORY" "STATUS" "DETAILS"
echo "----------------+-----------------+-----------------------"
printf "%-15s | %b%-15s%b | %s\n" "Infrastructure" "$STATUS_INFRA" "" "$NC" "$DETAIL_INFRA"
printf "%-15s | %b%-15s%b | %s\n" "Network"        "$STATUS_NET"        "" "$NC" "$DETAIL_NET"
printf "%-15s | %b%-15s%b | %s\n" "Control Plane"  "$STATUS_CP"         "" "$NC" "$DETAIL_CP"
printf "%-15s | %b%-15s%b | %s\n" "Logs"           "$STATUS_LOGS"       "" "$NC" "$DETAIL_LOGS"
printf "%-15s | %b%-15s%b | %s\n" "Security"       "$STATUS_SEC"        "" "$NC" "$DETAIL_SEC"
echo "=========================================================="
echo ""

exit 0

```

## `verify-dp-status-gemini.sh`

```bash
#!/bin/bash

# Kong Data Plane Status Verification Script (Gemini Optimized)
# Usage: ./verify-dp-status-gemini.sh [-n namespace] [-l label-selector] [-s secret-name]
# ./verify-dp-status-gemini.sh -n lex -l app=nginx-deployment
#
# Optimization:
# - Automatically detects CP address from DP Deployment env vars (KONG_CLUSTER_CONTROL_PLANE)
# - Enhanced error handling and reporting

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="aibang-int-kdp"
#LABEL_SELECTOR="app=kong-dp"
# add a labels 
# kubectl label deployment <deployment-name> <label-key>=<label-value> -n <namespace>
# kubectl label deployment busybox-app app=busybox-app -n bass-int-kdp
LABEL_SELECTOR="app=busybox-app"
SECRET_NAME="lex-tls-secret"
CP_ADMIN_PORT="8001"

# Parse command line arguments
while getopts "n:l:s:h" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    l) LABEL_SELECTOR="$OPTARG" ;;
    s) SECRET_NAME="$OPTARG" ;;
    h)
      echo "Usage: $0 [-n namespace] [-l label-selector] [-s secret-name]"
      echo "  -n: Kubernetes namespace (default: $NAMESPACE)"
      echo "  -l: DP Deployment label selector (default: $LABEL_SELECTOR)"
      echo "  -s: TLS secret name (default: $SECRET_NAME)"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Helper functions
print_header() {
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

# Main script
echo -e "${GREEN}Kong Data Plane Status Verification (Optimized)${NC}"
echo -e "Namespace: ${YELLOW}$NAMESPACE${NC}"
echo -e "Label Selector: ${YELLOW}$LABEL_SELECTOR${NC}"

# 0. Dynamic Configuration Discovery
print_header "0. 动态配置发现 (Configuration Discovery)"

print_info "0.1 查找 Kong DP Deployment..."
DP_DEPLOYMENT=$(kubectl get deployment -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$DP_DEPLOYMENT" ]; then
  print_error "未找到带有标签 '$LABEL_SELECTOR' 的 Deployment"
  print_info "请检查 Namespace 或 Label Selector 是否正确"
  exit 1
fi

print_success "找到 Deployment: $DP_DEPLOYMENT"

print_info "0.2 从 Deployment 获取 CP 连接信息..."
# Try to get KONG_CLUSTER_CONTROL_PLANE from env
CP_ENV_VALUE=$(kubectl get deployment "$DP_DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KONG_CLUSTER_CONTROL_PLANE")].value}' 2>/dev/null || echo "")

if [ -z "$CP_ENV_VALUE" ]; then
  print_warning "未在环境变量中找到 KONG_CLUSTER_CONTROL_PLANE"
  print_info "尝试使用默认值 kong-cp:8005"
  CP_SERVICE="kong-cp"
  CP_PORT="8005"
else
  print_success "发现配置 KONG_CLUSTER_CONTROL_PLANE=$CP_ENV_VALUE"
  # Parse host and port
  # Handle cases like "kong-cp:8005", "https://kong-cp:8005", "kong-cp" (default 8005)
  CLEAN_VAL=${CP_ENV_VALUE#*://} # Remove protocol if present
  
  if [[ "$CLEAN_VAL" == *":"* ]]; then
    CP_SERVICE=$(echo "$CLEAN_VAL" | cut -d: -f1)
    CP_PORT=$(echo "$CLEAN_VAL" | cut -d: -f2)
  else
    CP_SERVICE="$CLEAN_VAL"
    CP_PORT="8005" # Default port if not specified
  fi
fi

echo -e "CP Service Host: ${YELLOW}$CP_SERVICE${NC}"
echo -e "CP Service Port: ${YELLOW}$CP_PORT${NC}"


# 1. Infrastructure Layer Check
print_header "1. 基础设施层检查 (Infrastructure Health)"

print_info "1.1 检查 Kong DP Pods 状态..."
DP_PODS=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
POD_COUNT=$(echo "$DP_PODS" | jq -r '.items | length')

if [ "$POD_COUNT" -eq 0 ]; then
  print_error "未找到 Kong DP Pods"
  exit 1
else
  print_success "找到 $POD_COUNT 个 Kong DP Pod(s)"
  echo "$DP_PODS" | jq -r '.items[] | "\(.metadata.name) | Status: \(.status.phase) | Ready: \(.status.containerStatuses[0].ready) | Restarts: \(.status.containerStatuses[0].restartCount) | IP: \(.status.podIP)"'
fi

# Get first pod name for further checks
DP_POD_NAME=$(echo "$DP_PODS" | jq -r '.items[0].metadata.name // empty')

if [ -n "$DP_POD_NAME" ]; then
  print_info "1.2 检查 Pod 事件..."
  EVENTS=$(kubectl describe pod "$DP_POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep -A 10 "Events:" || echo "无法获取事件")
  if echo "$EVENTS" | grep -qE "Error|Failed|BackOff"; then
    print_error "发现异常事件:"
    echo "$EVENTS" | grep -E "Error|Failed|BackOff" | tail -5
  else
    print_success "未发现异常事件"
  fi
fi

# 2. Log Analysis
print_header "2. 日志层分析 (Log Analysis)"

if [ -n "$DP_POD_NAME" ]; then
  print_info "2.1 分析最近 100 行日志..."
  LOGS=$(kubectl logs "$DP_POD_NAME" -n "$NAMESPACE" --tail=100 2>/dev/null || echo "")
  
  if echo "$LOGS" | grep -q "control_plane: connected"; then
    print_success "DP 已成功连接到 CP (control_plane: connected)"
  elif echo "$LOGS" | grep -q "received initial configuration snapshot"; then
    print_success "DP 已接收到初始配置快照 (隐含连接成功)"
  else
    print_warning "未找到明确的连接成功信号 (可能是日志滚动了)"
  fi
  
  if echo "$LOGS" | grep -q "failed to connect to control plane"; then
    print_error "发现连接失败日志"
    echo "$LOGS" | grep "failed to connect" | tail -3
  fi
  
  if echo "$LOGS" | grep -q "certificate verify failed"; then
    print_error "发现证书验证失败日志"
    echo "$LOGS" | grep "certificate" | tail -3
  fi
else
  print_error "无法分析日志: 未找到 DP Pod"
fi

# 3. Control Plane Verification
print_header "3. 控制面层验证 (Control Plane Verification)"

# Try to find CP pod based on CP Service name (heuristic)
# Assuming CP deployment has label app=kong-cp or similar, but let's try to guess from service
print_info "3.1 尝试查找 CP Pod..."
# Heuristic: try to find a pod that looks like the CP service name
CP_POD_GUESS=$(kubectl get pods -n "$NAMESPACE" | grep "${CP_SERVICE%-*}" | grep -v "$DP_POD_NAME" | head -1 | awk '{print $1}')

if [ -n "$CP_POD_GUESS" ]; then
  print_info "推测 CP Pod 为: $CP_POD_GUESS"
  CLUSTER_STATUS=$(kubectl exec -it "$CP_POD_GUESS" -n "$NAMESPACE" -- curl -s http://localhost:$CP_ADMIN_PORT/clustering/status 2>/dev/null || echo '{}')
  
  DP_COUNT=$(echo "$CLUSTER_STATUS" | jq -r '.data_planes | length // 0')
  print_info "CP 注册的 DP 节点数: $DP_COUNT"
  
  if [ "$DP_COUNT" -gt 0 ]; then
    if [ -n "$DP_POD_NAME" ]; then
      DP_IP=$(kubectl get pod "$DP_POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null)
      if echo "$CLUSTER_STATUS" | jq -e ".data_planes[] | select(.ip == \"$DP_IP\")" > /dev/null 2>&1; then
        print_success "当前 DP Pod ($DP_IP) 已在 CP 注册"
      else
        print_error "当前 DP Pod ($DP_IP) 未在 CP 注册表中找到"
      fi
    fi
  else
    print_warning "CP 返回的 DP 列表为空 (或者无法连接 CP Admin API)"
  fi
else
  print_warning "无法自动定位 CP Pod，跳过 CP 端验证"
fi

# 4. Network Connectivity
print_header "4. 网络层连通性探测 (Network Connectivity)"

if [ -n "$DP_POD_NAME" ]; then
  print_info "4.1 测试 DP 到 CP 的网络连接 ($CP_SERVICE:$CP_PORT)..."
  
  # Test DNS resolution
  DNS_TEST=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- nslookup "$CP_SERVICE" 2>&1 || echo "DNS_FAILED")
  if echo "$DNS_TEST" | grep -q "DNS_FAILED\|can't resolve"; then
    print_error "DNS 解析失败: $CP_SERVICE"
  else
    print_success "DNS 解析成功"
  fi
  
  # Test TCP connectivity with curl
  print_info "4.2 测试 TCP 连接..."
  # Use the dynamically discovered CP_SERVICE and CP_PORT
  CONN_TEST=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- timeout 5 sh -c "curl -v --max-time 3 https://$CP_SERVICE:$CP_PORT 2>&1" || echo "CONNECTION_FAILED")
  
  if echo "$CONN_TEST" | grep -q "Connected to"; then
    print_success "TCP 连接成功 (网络层通畅)"
  elif echo "$CONN_TEST" | grep -q "SSL certificate problem"; then
    print_warning "TCP 连接成功，但证书验证失败 (网络通，需检查证书)"
  elif echo "$CONN_TEST" | grep -q "Connection timed out\|CONNECTION_FAILED"; then
    print_error "连接超时 (检查防火墙规则/安全组)"
  else
    print_warning "连接测试结果不明确"
    echo "$CONN_TEST" | head -5
  fi
else
  print_error "无法进行网络测试: 未找到 DP Pod"
fi

# 5. Security & Certificate Verification
print_header "5. 安全层与证书验证 (Certificate & Security)"

print_info "5.1 检查 TLS Secret '$SECRET_NAME'..."
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
  print_success "Secret 存在"
  
  # Check expiry
  CERT_EXPIRY=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
  if [ -n "$CERT_EXPIRY" ]; then
    print_info "证书过期时间: $CERT_EXPIRY"
    # Simple check if expired (requires date utils, skipping complex logic for brevity, just showing date)
  fi
else
  print_error "Secret '$SECRET_NAME' 不存在"
fi

if [ -n "$DP_POD_NAME" ]; then
  print_info "5.2 检查 DP Pod 内挂载的证书..."
  # Check env var for cert path if possible, otherwise guess default
  CERT_PATH="/etc/secrets/kong-cluster-cert/"
  MOUNTED_CERT=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- ls -la $CERT_PATH 2>/dev/null || echo "NOT_MOUNTED")
  
  if [ "$MOUNTED_CERT" = "NOT_MOUNTED" ]; then
    print_warning "默认路径 $CERT_PATH 未找到证书"
  else
    print_success "证书已挂载"
  fi
fi

echo -e "\n${GREEN}脚本执行完成!${NC}\n"

```

## `verify-dp-status.sh`

```bash
#!/bin/bash

# Kong Data Plane Status Verification Script
# Usage: ./verify-dp-status.sh [-n namespace] [-s secret-name] [-c cp-service]

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="aibang-int-kdp"
SECRET_NAME="lex-tls-secret"
LABEL_SELECTOR="app=busybox-app"
CP_SERVICE="kong-cp"
CP_PORT="8005"
CP_ADMIN_PORT="8001"

# Parse command line arguments
while getopts "n:s:c:h" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    s) SECRET_NAME="$OPTARG" ;;
    c) CP_SERVICE="$OPTARG" ;;
    h)
      echo "Usage: $0 [-n namespace] [-s secret-name] [-c cp-service]"
      echo "  -n: Kubernetes namespace (default: aibang-int-kdp)"
      echo "  -s: TLS secret name (default: lex-tls-secret)"
      echo "  -c: Control Plane service name (default: kong-cp)"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Helper functions
print_header() {
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

# Main script
echo -e "${GREEN}Kong Data Plane Status Verification${NC}"
echo -e "Namespace: ${YELLOW}$NAMESPACE${NC}"
echo -e "Secret: ${YELLOW}$SECRET_NAME${NC}"
echo -e "CP Service: ${YELLOW}$CP_SERVICE${NC}"

# 1. Infrastructure Layer Check
print_header "1. 基础设施层检查 (Infrastructure Health)"

print_info "1.1 检查 Kong DP Pods 状态..."
DP_PODS=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
# DP_DEPLOYMENT=$(kubectl get deployment -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
POD_COUNT=$(echo "$DP_PODS" | jq -r '.items | length')

if [ "$POD_COUNT" -eq 0 ]; then
  print_error "未找到 Kong DP Pods (label: $LABEL_SELECTOR)"
  print_info "尝试查找其他可能的 Kong Pods..."
  kubectl get pods -n "$NAMESPACE" | grep -i kong || print_error "未找到任何 Kong 相关 Pods"
else
  print_success "找到 $POD_COUNT 个 Kong DP Pod(s)"
  echo "$DP_PODS" | jq -r '.items[] | "\(.metadata.name) | Status: \(.status.phase) | Ready: \(.status.containerStatuses[0].ready) | Restarts: \(.status.containerStatuses[0].restartCount) | IP: \(.status.podIP)"'
  
  # Check for unhealthy pods
  UNHEALTHY=$(echo "$DP_PODS" | jq -r '.items[] | select(.status.phase != "Running" or .status.containerStatuses[0].ready != true) | .metadata.name')
  if [ -n "$UNHEALTHY" ]; then
    print_warning "发现不健康的 Pods: $UNHEALTHY"
  fi
fi

# Get first pod name for further checks
DP_POD_NAME=$(echo "$DP_PODS" | jq -r '.items[0].metadata.name // empty')

if [ -n "$DP_POD_NAME" ]; then
  print_info "1.2 检查 Pod 事件..."
  EVENTS=$(kubectl describe pod "$DP_POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep -A 10 "Events:" || echo "无法获取事件")
  if echo "$EVENTS" | grep -qE "Error|Failed|BackOff"; then
    print_error "发现异常事件:"
    echo "$EVENTS" | grep -E "Error|Failed|BackOff" | tail -5
  else
    print_success "未发现异常事件"
  fi
  
  print_info "1.3 检查资源使用情况..."
  kubectl top pod "$DP_POD_NAME" -n "$NAMESPACE" 2>/dev/null || print_warning "无法获取资源使用情况 (metrics-server 可能未安装)"
fi

# 2. Log Analysis
print_header "2. 日志层分析 (Log Analysis)"

if [ -n "$DP_POD_NAME" ]; then
  print_info "2.1 分析最近 100 行日志..."
  LOGS=$(kubectl logs "$DP_POD_NAME" -n "$NAMESPACE" --tail=100 2>/dev/null || echo "")
  
  if echo "$LOGS" | grep -q "control_plane: connected"; then
    print_success "DP 已成功连接到 CP (control_plane: connected)"
  else
    print_error "未找到成功连接的日志信号"
  fi
  
  if echo "$LOGS" | grep -q "received initial configuration snapshot"; then
    print_success "DP 已接收到初始配置快照"
  else
    print_warning "未找到配置快照接收日志"
  fi
  
  if echo "$LOGS" | grep -q "failed to connect to control plane"; then
    print_error "发现连接失败日志"
    echo "$LOGS" | grep "failed to connect" | tail -3
  fi
  
  if echo "$LOGS" | grep -q "certificate verify failed"; then
    print_error "发现证书验证失败日志"
    echo "$LOGS" | grep "certificate" | tail -3
  fi
  
  if echo "$LOGS" | grep -q "cluster: reconnecting"; then
    print_warning "DP 正在重连 (连接不稳定)"
  fi
  
  print_info "关键日志摘要 (最近 5 条):"
  echo "$LOGS" | grep -E "control_plane|cluster|certificate|configuration" | tail -5 || print_info "无相关日志"
else
  print_error "无法分析日志: 未找到 DP Pod"
fi

# 3. Control Plane Verification
print_header "3. 控制面层验证 (Control Plane Verification)"

print_info "3.1 查询 CP 集群状态..."
CP_POD=$(kubectl get pods -n "$NAMESPACE" -l app=kong-cp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$CP_POD" ]; then
  print_success "找到 CP Pod: $CP_POD"
  CLUSTER_STATUS=$(kubectl exec -it "$CP_POD" -n "$NAMESPACE" -- curl -s http://localhost:$CP_ADMIN_PORT/clustering/status 2>/dev/null || echo '{}')
  
  DP_COUNT=$(echo "$CLUSTER_STATUS" | jq -r '.data_planes | length // 0')
  print_info "CP 注册的 DP 节点数: $DP_COUNT"
  
  if [ "$DP_COUNT" -gt 0 ]; then
    print_success "CP 集群状态:"
    echo "$CLUSTER_STATUS" | jq -r '.data_planes[] | "  ID: \(.id) | IP: \(.ip) | Status: \(.status) | Last Seen: \(.last_seen)s | Version: \(.version)"'
    
    # Check if our DP pod IP is registered
    if [ -n "$DP_POD_NAME" ]; then
      DP_IP=$(kubectl get pod "$DP_POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null)
      if echo "$CLUSTER_STATUS" | jq -e ".data_planes[] | select(.ip == \"$DP_IP\")" > /dev/null 2>&1; then
        print_success "当前 DP Pod ($DP_IP) 已在 CP 注册"
      else
        print_error "当前 DP Pod ($DP_IP) 未在 CP 注册表中找到"
      fi
    fi
  else
    print_error "CP 未注册任何 DP 节点"
  fi
else
  print_warning "未找到 CP Pod (label: app=kong-cp), 跳过 CP 验证"
fi

# 4. Network Connectivity
print_header "4. 网络层连通性探测 (Network Connectivity)"

if [ -n "$DP_POD_NAME" ]; then
  print_info "4.1 测试 DP 到 CP 的网络连接 ($CP_SERVICE:$CP_PORT)..."
  
  # Test DNS resolution
  DNS_TEST=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- nslookup "$CP_SERVICE" 2>&1 || echo "DNS_FAILED")
  if echo "$DNS_TEST" | grep -q "DNS_FAILED\|can't resolve"; then
    print_error "DNS 解析失败: $CP_SERVICE"
  else
    print_success "DNS 解析成功"
    echo "$DNS_TEST" | grep -E "Address|Name" | head -3
  fi
  
  # Test TCP connectivity with curl
  print_info "4.2 测试 TCP 连接..."
  CONN_TEST=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- timeout 5 sh -c "curl -v --max-time 3 https://$CP_SERVICE:$CP_PORT 2>&1" || echo "CONNECTION_FAILED")
  
  if echo "$CONN_TEST" | grep -q "Connected to"; then
    print_success "TCP 连接成功 (网络层通畅)"
  elif echo "$CONN_TEST" | grep -q "SSL certificate problem"; then
    print_warning "TCP 连接成功，但证书验证失败 (网络通，需检查证书)"
  elif echo "$CONN_TEST" | grep -q "Connection timed out\|CONNECTION_FAILED"; then
    print_error "连接超时 (检查防火墙规则/安全组)"
  elif echo "$CONN_TEST" | grep -q "Could not resolve host"; then
    print_error "无法解析主机名 (DNS 问题)"
  else
    print_warning "连接测试结果不明确"
    echo "$CONN_TEST" | head -5
  fi
else
  print_error "无法进行网络测试: 未找到 DP Pod"
fi

# 5. Security & Certificate Verification
print_header "5. 安全层与证书验证 (Certificate & Security)"

print_info "5.1 检查 TLS Secret 是否存在..."
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
  print_success "Secret '$SECRET_NAME' 存在"
  
  print_info "5.2 验证证书内容..."
  CERT_INFO=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -subject -enddate 2>/dev/null || echo "CERT_ERROR")
  
  if [ "$CERT_INFO" = "CERT_ERROR" ]; then
    print_error "无法读取或解析证书"
  else
    print_success "证书信息:"
    echo "$CERT_INFO" | while IFS= read -r line; do
      if echo "$line" | grep -q "subject="; then
        echo "  Subject: $(echo "$line" | sed 's/subject=//')"
      elif echo "$line" | grep -q "notAfter="; then
        EXPIRY=$(echo "$line" | sed 's/notAfter=//')
        echo "  过期时间: $EXPIRY"
        
        # Check if certificate is expired
        EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y %Z" "$EXPIRY" "+%s" 2>/dev/null || echo "0")
        NOW_EPOCH=$(date "+%s")
        if [ "$EXPIRY_EPOCH" -lt "$NOW_EPOCH" ]; then
          print_error "证书已过期!"
        else
          DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
          if [ "$DAYS_LEFT" -lt 30 ]; then
            print_warning "证书将在 $DAYS_LEFT 天后过期"
          else
            print_success "证书有效 (剩余 $DAYS_LEFT 天)"
          fi
        fi
      fi
    done
  fi
  
  print_info "5.3 检查证书详细信息..."
  kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | openssl x509 -noout -text 2>/dev/null | grep -E "Subject:|Issuer:|Not Before|Not After" || print_warning "无法获取详细证书信息"
  
else
  print_error "Secret '$SECRET_NAME' 不存在"
  print_info "可用的 Secrets:"
  kubectl get secrets -n "$NAMESPACE" | grep -i tls || echo "  未找到 TLS secrets"
fi

if [ -n "$DP_POD_NAME" ]; then
  print_info "5.4 检查 DP Pod 内挂载的证书..."
  MOUNTED_CERT=$(kubectl exec "$DP_POD_NAME" -n "$NAMESPACE" -- ls -la /etc/secrets/kong-cluster-cert/ 2>/dev/null || echo "NOT_MOUNTED")
  
  if [ "$MOUNTED_CERT" = "NOT_MOUNTED" ]; then
    print_warning "证书未挂载到 /etc/secrets/kong-cluster-cert/ (可能使用其他路径)"
  else
    print_success "证书已挂载:"
    echo "$MOUNTED_CERT"
  fi
fi

# Summary
print_header "6. 诊断总结 (Summary)"

echo -e "${BLUE}检查项完成情况:${NC}"
echo "  [1] 基础设施层: Pod 状态、资源、事件"
echo "  [2] 日志层: 连接信号、配置快照、错误日志"
echo "  [3] 控制面层: CP 注册状态验证"
echo "  [4] 网络层: DNS、TCP 连通性测试"
echo "  [5] 安全层: 证书有效性、挂载状态"

print_info "建议: 查看上述输出中的 ❌ 和 ⚠️ 标记，优先解决标记为错误的问题"

echo -e "\n${GREEN}脚本执行完成!${NC}\n"

```

