#!/bin/bash

# 检查是否提供了输入文件
if [ $# -ne 1 ]; then
    echo "Usage: $0 <openssl_output_file>"
    exit 1
fi

input_file="$1"

# 函数：提取证书信息
extract_cert_info() {
    local cert="$1"
    echo "$cert" | openssl x509 -noout -text
}

# 读取整个文件内容
content=$(cat "$input_file")

echo "Connection Information:"
echo "$content" | grep -E "New, TLSv|Cipher is" | sed 's/^[[:space:]]*//'

echo -e "\nCertificates:"
# 提取所有证书
certs=$(echo "$content" | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' RS='-----END CERTIFICATE-----' ORS='-----END CERTIFICATE-----\n')

cert_count=0
while read -r cert; do
    if [[ $cert == *"BEGIN CERTIFICATE"* ]]; then
        ((cert_count++))
        echo -e "\nCertificate $cert_count:"
        cert_info=$(extract_cert_info "$cert")
        echo "$cert_info" | grep -E "Subject:|Issuer:|Validity|Public Key Algorithm:" | sed 's/^[[:space:]]*/    /'
    fi
done <<< "$certs"

echo -e "\nServer Parameters:"
echo "$content" | grep "Server Temp Key:" | sed 's/^[[:space:]]*//'

echo -e "\nSSL Session:"
echo "$content" | sed -n '/SSL-Session:/,/---/p' | grep -v -E "^[[:space:]]*$|---" | sed 's/^[[:space:]]*//'

echo -e "\nVerification Result:"
echo "$content" | grep "Verify return code:" | sed 's/^[[:space:]]*//'
