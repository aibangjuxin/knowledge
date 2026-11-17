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
