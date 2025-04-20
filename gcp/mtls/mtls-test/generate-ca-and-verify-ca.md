- [generate-self-singned-cert.sh](./generate-self-singned-cert.sh)
- [generate-self-signed-cert_lmstudio.sh](./generate-self-signed-cert_lmstudio.sh)
- [get_cert_fingerprint_chatgpt.sh](./get_cert_fingerprint_chatgpt.sh)
```bash
#!/opt/homebrew/bin/bash

# Function: Display usage instructions for the script
show_usage() {
  echo "Usage: $0 <root_certificate_path> <intermediate_certificate_path>"
  echo "Example: $0 root.pem intermediate.pem"
  exit 1
}

# Function: Check if required commands are available
check_dependencies() {
  if ! command -v openssl &>/dev/null; then
    echo "Error: OpenSSL is not installed or not in PATH"
    exit 1
  fi
}

# Function: Get certificate type by checking basicConstraints and CA
get_cert_type() {
  local cert_file=$1
  # Fetch basic constraints and check CA status in one call
  local cert_info=$(openssl x509 -in "$cert_file" -noout -text)

  if echo "$cert_info" | grep -q "CA:TRUE"; then
    if echo "$cert_info" | grep -q "pathlen"; then
      echo "Intermediate Certificate"
    else
      echo "Root Certificate"
    fi
  else
    echo "End-Entity Certificate"
  fi
}

# Function: Calculate and display certificate details
get_certificate_info() {
  local cert_file=$1

  # Check if certificate file exists
  if [ ! -f "$cert_file" ]; then
    echo "Error: Certificate file '$cert_file' does not exist"
    exit 1
  fi

  # Validate PEM format and get certificate details
  if ! openssl x509 -in "$cert_file" -noout 2>/dev/null; then
    echo "Error: '$cert_file' is not a valid PEM format certificate"
    exit 1
  fi

  # Determine certificate type
  local cert_type=$(get_cert_type "$cert_file")

  # Get certificate details in a single call
  local fingerprint=$(openssl x509 -in "$cert_file" -noout -fingerprint -sha256 | cut -d'=' -f2)
  local subject=$(openssl x509 -in "$cert_file" -noout -subject | sed 's/subject= //')
  local expiry=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d'=' -f2)

  # Output in YAML format
  echo "Certificate Type: $cert_type"
  echo "Fingerprint: SHA256:$fingerprint"
  echo "Subject: $subject"
  echo "Expires: $expiry"
  echo "---"
}

# Main script execution
main() {
  # Check dependencies
  check_dependencies

  # Validate arguments
  if [ $# -ne 2 ]; then
    show_usage
  fi

  echo "Certificate Information Report"
  echo "Generated on: $(date)"
  echo "---"

  # Process both certificates
  for cert in "$1" "$2"; do
    get_certificate_info "$cert"
  done
}

# Execute main function
main "$@"
```
- ./generate-self-signed-cert_lmstudio.sh
```bash
#!/bin/bash

set -e

# 设置证书有效期和默认信息
CERT_DURATION=3650
COUNTRY="CN"
ORGANIZATION="Test Organization"
CITY="Test City"
EMAIL="test@example.com"

# 定义文件名
ROOT_KEY="root.key"
ROOT_CERT="root.crt"
INTERMEDIATE_KEY="intermediate.key"
INTERMEDIATE_CSR="intermediate.csr"
INTERMEDIATE_CERT="intermediate.crt"

# 检查是否安装了 OpenSSL
if ! command -v openssl &> /dev/null; then
  echo "错误: OpenSSL 未找到，请先安装 OpenSSL。"
  exit 1
fi

echo "开始生成证书..."

# 生成根证书私钥和证书
echo "生成根证书私钥..."
openssl genrsa -out "$ROOT_KEY" 2048

echo "生成根证书..."
openssl req -x509 -new -nodes -key "$ROOT_KEY" \
  -sha256 -days "$CERT_DURATION" \
  -out "$ROOT_CERT" \
  -subj "/C=$COUNTRY/O=$ORGANIZATION/L=$CITY/CN=Root CA/emailAddress=$EMAIL"

# 生成中间证书私钥
echo "生成中间证书私钥..."
openssl genrsa -out "$INTERMEDIATE_KEY" 2048

# 生成中间证书CSR
echo "生成中间证书CSR..."
openssl req -new -key "$INTERMEDIATE_KEY" \
  -out "$INTERMEDIATE_CSR" \
  -subj "/C=$COUNTRY/O=$ORGANIZATION/L=$CITY/CN=Intermediate CA/emailAddress=$EMAIL"

# 使用根证书签发中间证书
echo "使用根证书签发中间证书..."
openssl x509 -req -in "$INTERMEDIATE_CSR" \
  -CA "$ROOT_CERT" -CAkey "$ROOT_KEY" \
  -CAcreateserial -out "$INTERMEDIATE_CERT" \
  -days "$CERT_DURATION" -sha256 \
  -extfile <(printf "\nbasicConstraints=critical,CA:true,pathlen:0\nkeyUsage=critical,digitalSignature,cRLSign,keyCertSign\n")

echo ""
echo "证书生成完成:"
echo "  根证书: $ROOT_CERT"
echo "  根证书私钥: $ROOT_KEY"
echo "  中间证书: $INTERMEDIATE_CERT"
echo "  中间证书私钥: $INTERMEDIATE_KEY"
echo "  中间证书CSR: $INTERMEDIATE_CSR"

echo ""
echo "注意：这些证书仅用于测试和开发目的。在生产环境中，请使用可信CA签发的证书。"

exit 0
```
