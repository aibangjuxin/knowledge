# Shell Scripts Collection

Generated on: 2025-09-20 10:08:33
Directory: /Users/lex/git/knowledge/ssl/ingress-ssl

## `check-tls-secret.sh`

```bash
#!/bin/bash

# TLS Secret Validation Script
# Usage: ./check-tls-secret.sh <secret-name> <namespace>

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

print_header() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
  print_status "$GREEN" "✓ $1"
}

print_error() {
  print_status "$RED" "✗ $1"
}

print_warning() {
  print_status "$YELLOW" "⚠ $1"
}

print_info() {
  print_status "$BLUE" "ℹ $1"
}

# Check if required tools are installed
check_dependencies() {
  local missing_tools=()

  if ! command -v kubectl &>/dev/null; then
    missing_tools+=("kubectl")
  fi

  if ! command -v openssl &>/dev/null; then
    missing_tools+=("openssl")
  fi

  if [ ${#missing_tools[@]} -ne 0 ]; then
    print_error "Missing required tools: ${missing_tools[*]}"
    exit 1
  fi
}

# Function to validate input parameters
validate_input() {
  if [ $# -ne 2 ]; then
    echo "Usage: $0 <secret-name> <namespace>"
    echo "Example: $0 my-tls-secret default"
    exit 1
  fi

  SECRET_NAME="$1"
  NAMESPACE="$2"

  if [ -z "$SECRET_NAME" ] || [ -z "$NAMESPACE" ]; then
    print_error "Secret name and namespace cannot be empty"
    exit 1
  fi
}

# Function to check if secret exists and get its type
check_secret_exists() {
  print_header "Checking Secret Existence and Type"

  if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    print_error "Secret '$SECRET_NAME' not found in namespace '$NAMESPACE'"
    exit 1
  fi

  print_success "Secret '$SECRET_NAME' exists in namespace '$NAMESPACE'"

  # Get secret type
  SECRET_TYPE=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.type}')

  if [ "$SECRET_TYPE" = "kubernetes.io/tls" ]; then
    print_success "Secret type is correct: $SECRET_TYPE"
  else
    print_error "Invalid secret type: $SECRET_TYPE (expected: kubernetes.io/tls)"
    exit 1
  fi
}

# Function to export certificate and key from secret
export_tls_files() {
  print_header "Exporting TLS Files"

  # Create temporary directory
  TEMP_DIR=$(mktemp -d)
  TLS_CRT_FILE="$TEMP_DIR/tls.crt"
  TLS_KEY_FILE="$TEMP_DIR/tls.key"

  # Export certificate
  if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d >"$TLS_CRT_FILE" 2>/dev/null; then
    print_success "Certificate exported to: $TLS_CRT_FILE"
  else
    print_error "Failed to export tls.crt from secret"
    cleanup_and_exit 1
  fi

  # Export private key
  if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.key}' | base64 -d >"$TLS_KEY_FILE" 2>/dev/null; then
    print_success "Private key exported to: $TLS_KEY_FILE"
  else
    print_error "Failed to export tls.key from secret"
    cleanup_and_exit 1
  fi

  # Check if files are not empty
  if [ ! -s "$TLS_CRT_FILE" ]; then
    print_error "Certificate file is empty"
    cleanup_and_exit 1
  fi

  if [ ! -s "$TLS_KEY_FILE" ]; then
    print_error "Private key file is empty"
    cleanup_and_exit 1
  fi
}

# Function to validate certificate and key consistency
validate_cert_key_match() {
  print_header "Validating Certificate and Key Consistency"

  # Get certificate modulus
  CERT_MODULUS=$(openssl x509 -noout -modulus -in "$TLS_CRT_FILE" 2>/dev/null | openssl md5)
  if [ $? -ne 0 ]; then
    print_error "Failed to extract certificate modulus"
    cleanup_and_exit 1
  fi

  # Get private key modulus
  KEY_MODULUS=$(openssl rsa -noout -modulus -in "$TLS_KEY_FILE" 2>/dev/null | openssl md5)
  if [ $? -ne 0 ]; then
    print_error "Failed to extract private key modulus"
    cleanup_and_exit 1
  fi

  # Compare moduli
  if [ "$CERT_MODULUS" = "$KEY_MODULUS" ]; then
    print_success "Certificate and private key match"
  else
    print_error "Certificate and private key do not match"
    print_info "Certificate modulus: $CERT_MODULUS"
    print_info "Private key modulus: $KEY_MODULUS"
    cleanup_and_exit 1
  fi
}

# Function to display certificate information
display_cert_info() {
  print_header "Certificate Information"

  # Basic certificate info
  print_info "Certificate Details:"
  openssl x509 -in "$TLS_CRT_FILE" -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:|IP Address:)" | while read line; do
    echo "  $line"
  done

  # Subject and Issuer
  SUBJECT=$(openssl x509 -noout -subject -in "$TLS_CRT_FILE" | sed 's/subject=//')
  ISSUER=$(openssl x509 -noout -issuer -in "$TLS_CRT_FILE" | sed 's/issuer=//')

  echo ""
  print_info "Subject: $SUBJECT"
  print_info "Issuer: $ISSUER"

  # Validity period
  NOT_BEFORE=$(openssl x509 -noout -startdate -in "$TLS_CRT_FILE" | cut -d= -f2)
  NOT_AFTER=$(openssl x509 -noout -enddate -in "$TLS_CRT_FILE" | cut -d= -f2)

  echo ""
  print_info "Valid From: $NOT_BEFORE"
  print_info "Valid Until: $NOT_AFTER"

  # Check if certificate is expired
  if openssl x509 -checkend 0 -noout -in "$TLS_CRT_FILE" >/dev/null; then
    print_success "Certificate is currently valid"
  else
    print_error "Certificate has expired"
  fi

  # Check if certificate expires soon (30 days)
  if openssl x509 -checkend 2592000 -noout -in "$TLS_CRT_FILE" >/dev/null; then
    print_success "Certificate is not expiring within 30 days"
  else
    print_warning "Certificate expires within 30 days"
  fi

  # Extract Subject Alternative Names
  echo ""
  print_info "Subject Alternative Names:"
  SAN=$(openssl x509 -noout -text -in "$TLS_CRT_FILE" | grep -A 1 "Subject Alternative Name" | tail -n 1 | sed 's/^ *//')
  if [ -n "$SAN" ]; then
    echo "  $SAN"
  else
    print_warning "No Subject Alternative Names found"
  fi
}

# Function to check certificate chain
check_cert_chain() {
  print_header "Certificate Chain Analysis"

  # Count certificates in the file
  CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$TLS_CRT_FILE")

  print_info "Number of certificates in chain: $CERT_COUNT"

  if [ "$CERT_COUNT" -eq 1 ]; then
    print_warning "Only one certificate found (no intermediate certificates)"
  else
    print_success "Certificate chain contains $CERT_COUNT certificates"

    # Extract and display each certificate in the chain
    awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$TLS_CRT_FILE" |
      awk -v RS="-----END CERTIFICATE-----" -v ORS="-----END CERTIFICATE-----\n" '{
            if (NF) {
                print $0
                print ""
            }
        }' | while IFS= read -r cert_block; do
      if [ -n "$cert_block" ]; then
        echo "$cert_block" | openssl x509 -noout -subject -issuer 2>/dev/null | while read line; do
          echo "  $line"
        done
        echo ""
      fi
    done
  fi

  # Verify certificate chain
  if openssl verify -CAfile "$TLS_CRT_FILE" "$TLS_CRT_FILE" &>/dev/null; then
    print_success "Certificate chain verification passed"
  else
    print_warning "Certificate chain verification failed (this might be normal if intermediate CAs are not included)"
  fi
}

# Function to generate summary table
generate_summary() {
  print_header "Validation Summary"

  echo "| Check | Status | Details |"
  echo "|-------|--------|---------|"
  echo "| Secret Exists | ✓ Pass | Found in namespace $NAMESPACE |"
  echo "| Secret Type | ✓ Pass | kubernetes.io/tls |"
  echo "| Cert/Key Match | ✓ Pass | Modulus validation successful |"
  echo "| Certificate Validity | $(if openssl x509 -checkend 0 -noout -in "$TLS_CRT_FILE" >/dev/null; then echo "✓ Pass"; else echo "✗ Fail"; fi) | $(if openssl x509 -checkend 0 -noout -in "$TLS_CRT_FILE" >/dev/null; then echo "Currently valid"; else echo "Expired"; fi) |"
  echo "| Certificate Chain | $(if [ "$CERT_COUNT" -gt 1 ]; then echo "✓ Pass"; else echo "⚠ Warning"; fi) | $CERT_COUNT certificate(s) in chain |"
}

# Cleanup function
cleanup_and_exit() {
  local exit_code=${1:-0}
  if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
    print_info "Temporary files cleaned up"
  fi
  exit $exit_code
}

# Trap to ensure cleanup on script exit
trap 'cleanup_and_exit' EXIT INT TERM

# Main execution
main() {
  print_header "TLS Secret Validation Tool"
  print_info "Checking TLS secret: $SECRET_NAME in namespace: $NAMESPACE"

  check_dependencies
  check_secret_exists
  export_tls_files
  validate_cert_key_match
  display_cert_info
  check_cert_chain
  generate_summary

  print_success "TLS secret validation completed successfully"
}

# Script entry point
validate_input "$@"
main

```

## `create-tls-secret.sh`

```bash
#!/bin/bash

# 创建 TLS Secret 到 K8s 脚本
# Usage: ./create-tls-secret.sh <secret-name> <namespace> <cert-file> <key-file>

set -euo pipefail

SECRET_NAME=${1:-"my-tls-secret"}
NAMESPACE=${2:-"default"}
CERT_FILE=${3:-"tls.crt"}
KEY_FILE=${4:-"tls.key"}

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# 检查文件是否存在
if [ ! -f "$CERT_FILE" ]; then
    print_error "证书文件不存在: $CERT_FILE"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    print_error "私钥文件不存在: $KEY_FILE"
    exit 1
fi

print_info "准备创建 TLS Secret: $SECRET_NAME"
print_info "目标 Namespace: $NAMESPACE"
print_info "证书文件: $CERT_FILE"
print_info "私钥文件: $KEY_FILE"

# 创建 namespace（如果不存在）
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_info "创建 namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
    print_success "Namespace '$NAMESPACE' 已创建"
else
    print_info "Namespace '$NAMESPACE' 已存在"
fi

# 编码证书和密钥文件
CERT_BASE64=$(base64 -w 0 "$CERT_FILE")
KEY_BASE64=$(base64 -w 0 "$KEY_FILE")

# 生成 YAML 文件
cat > tls-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
type: kubernetes.io/tls
data:
  tls.crt: $CERT_BASE64
  tls.key: $KEY_BASE64
EOF

print_success "YAML 文件已生成: tls-secret.yaml"

# 应用到集群
if kubectl apply -f tls-secret.yaml; then
    print_success "TLS Secret '$SECRET_NAME' 已创建到 namespace '$NAMESPACE'"
else
    print_error "创建 TLS Secret 失败"
    exit 1
fi

# 验证创建结果
echo ""
print_info "验证创建结果:"
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE"

echo ""
print_info "Secret 详细信息:"
kubectl describe secret "$SECRET_NAME" -n "$NAMESPACE"

# 清理临时 YAML 文件
rm -f tls-secret.yaml
print_info "临时文件已清理"
```

## `generate-cert-chain.sh`

```bash
#!/bin/bash

# 生成包含中间证书的证书链
# Usage: ./generate-cert-chain.sh [domain]

set -euo pipefail

DOMAIN=${1:-"example.com"}
CERT_DIR="./cert-chain"

mkdir -p "$CERT_DIR"

echo "生成包含中间证书的证书链..."

# 1. 生成根CA私钥和证书
openssl genrsa -out "$CERT_DIR/ca.key" 4096
openssl req -new -x509 -days 3650 -key "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt" \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Root CA/CN=Root CA"

echo "✓ 根CA证书已生成"

# 2. 生成中间CA私钥和CSR
openssl genrsa -out "$CERT_DIR/intermediate.key" 2048
openssl req -new -key "$CERT_DIR/intermediate.key" -out "$CERT_DIR/intermediate.csr" \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Intermediate CA/CN=Intermediate CA"

# 3. 用根CA签发中间CA证书
openssl x509 -req -in "$CERT_DIR/intermediate.csr" -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" -CAcreateserial -out "$CERT_DIR/intermediate.crt" -days 1825

echo "✓ 中间CA证书已生成"

# 4. 生成服务器私钥和CSR
openssl genrsa -out "$CERT_DIR/tls.key" 2048
openssl req -new -key "$CERT_DIR/tls.key" -out "$CERT_DIR/server.csr" \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Test Server/CN=$DOMAIN"

# 5. 用中间CA签发服务器证书
cat > "$CERT_DIR/server.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = *.$DOMAIN
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

openssl x509 -req -in "$CERT_DIR/server.csr" -CA "$CERT_DIR/intermediate.crt" \
    -CAkey "$CERT_DIR/intermediate.key" -CAcreateserial -out "$CERT_DIR/server.crt" \
    -days 365 -extensions v3_req -extfile "$CERT_DIR/server.conf"

echo "✓ 服务器证书已生成"

# 6. 创建完整的证书链文件
cat "$CERT_DIR/server.crt" "$CERT_DIR/intermediate.crt" "$CERT_DIR/ca.crt" > "$CERT_DIR/tls.crt"

echo "✓ 证书链已创建: $CERT_DIR/tls.crt"
echo "✓ 私钥文件: $CERT_DIR/tls.key"

# 显示证书链信息
echo ""
echo "证书链包含的证书:"
grep -c "BEGIN CERTIFICATE" "$CERT_DIR/tls.crt"

# 清理临时文件
rm -f "$CERT_DIR"/*.csr "$CERT_DIR"/*.conf "$CERT_DIR"/*.srl "$CERT_DIR/server.crt"
```

## `generate-self-signed-cert.sh`

```bash
#!/bin/bash

# 自签名证书生成脚本
# Usage: ./generate-self-signed-cert.sh [domain-name]

set -euo pipefail

# 默认域名
DOMAIN=${1:-"example.com"}
CERT_DIR="./certs"
KEY_FILE="$CERT_DIR/tls.key"
CERT_FILE="$CERT_DIR/tls.crt"

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 创建证书目录
mkdir -p "$CERT_DIR"

print_info "生成自签名证书用于域名: $DOMAIN"

# 生成私钥
openssl genrsa -out "$KEY_FILE" 2048
print_success "私钥已生成: $KEY_FILE"

# 生成自签名证书
openssl req -new -x509 -key "$KEY_FILE" -out "$CERT_FILE" -days 365 \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Test Organization/OU=IT Department/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,DNS:*.$DOMAIN,DNS:localhost,IP:127.0.0.1"

print_success "证书已生成: $CERT_FILE"

# 显示证书信息
echo ""
print_info "证书信息:"
openssl x509 -in "$CERT_FILE" -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:|IP Address:)"

echo ""
print_info "文件位置:"
echo "  私钥: $(realpath $KEY_FILE)"
echo "  证书: $(realpath $CERT_FILE)"


```bash
# 一行命令生成证书
mkdir -p certs && cd certs && \
openssl req -x509 -newkey rsa:2048 -keyout tls.key -out tls.crt -days 365 -nodes \
    -subj "/C=UK/ST=London/L=London/O=AiBang/CN=api01.gcp.uk.aibang.com" \
    -addext "subjectAltName=DNS:api01.gcp.uk.aibang.com,DNS:*.gcp.uk.aibang.com,DNS:localhost" && \
echo "证书生成完成:" && ls -la tls.*
```
```

