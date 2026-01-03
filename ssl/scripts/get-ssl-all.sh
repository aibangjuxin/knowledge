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
    local subject=$(echo "$cert" | openssl x509 -noout -subject 2>/dev/null)
    local issuer=$(echo "$cert" | openssl x509 -noout -issuer 2>/dev/null)
    echo "    Subject: $subject"
    echo "    Issuer: $issuer"
}

echo "Connection Information:"
grep -E "New, TLSv|Cipher is" "$input_file" | sed 's/^[[:space:]]*//'

echo -e "\nCertificates:"
# 使用 awk 提取证书，确保捕获完整的证书内容
awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' "$input_file" | awk '
    /-----BEGIN CERTIFICATE-----/ {
        if (cert != "") {
            print cert
            cert = ""
        }
        cert = $0 "\n"
        next
    }
    /-----END CERTIFICATE-----/ {
        cert = cert $0 "\n"
        print cert
        cert = ""
        next
    }
    { cert = cert $0 "\n" }
    END {
        if (cert != "") print cert
    }
' | while read -r cert; do
    echo -e "\nCertificate:"
    echo "$cert" | sed 's/^/    /'
    extract_cert_info "$cert"
done

echo -e "\nServer Parameters:"
grep "Server Temp Key:" "$input_file" | sed 's/^[[:space:]]*//'

echo -e "\nSSL Session:"
sed -n '/SSL-Session:/,/---/p' "$input_file" | grep -v -E "^[[:space:]]*$|---" | sed 's/^[[:space:]]*//'

echo -e "\nVerification Result:"
grep "Verify return code:" "$input_file" | sed 's/^[[:space:]]*//'
