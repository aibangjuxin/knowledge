要确定本地证书与客户提供的证书之间的对应关系,我们可以采取以下步骤:

1. 提取证书信息:
   首先,我们需要从本地证书和客户提供的证书中提取关键信息。

   对于本地证书:
   ```bash
   openssl x509 -in /path/to/local_cert.crt -noout -text
   ```

   对于客户提供的证书:
   ```bash
   openssl x509 -in /path/to/customer_cert.crt -noout -text
   ```

2. 比较关键信息:
   我们主要关注以下几个字段:
   - 主题(Subject)
   - 颁发者(Issuer)
   - 序列号(Serial Number)
   - 有效期(Validity)
   - 公钥(Public Key)

3. 创建比较表:
   创建一个表格,列出本地证书和客户证书的关键信息,方便比对。

4. 使用工具比较:
   我们可以使用 `diff` 命令来比较提取出的信息:
   
   ```bash
   diff <(openssl x509 -in local_cert.crt -noout -text) <(openssl x509 -in customer_cert.crt -noout -text)
   ```

5. 检查证书链:
   有时候,证书可能是一个链中的一部分。我们可以检查证书链来确定对应关系:
   
   ```bash
   openssl verify -verbose -CAfile /path/to/ca-bundle.crt /path/to/cert.crt
   ```

6. 比较指纹:
   我们还可以比较证书的指纹:
   
   ```bash
   openssl x509 -noout -fingerprint -sha256 -in cert.crt
   ```

7. 使用脚本自动化:
   如果有很多证书需要比较,我们可以编写一个脚本来自动化这个过程。



```bash
#!/bin/bash

# 函数: 提取证书信息
extract_cert_info() {
    local cert_file=$1
    openssl x509 -in "$cert_file" -noout -subject -issuer -serial -dates -pubkey
}

# 函数: 计算证书指纹
calculate_fingerprint() {
    local cert_file=$1
    openssl x509 -noout -fingerprint -sha256 -in "$cert_file" | cut -d'=' -f2
}

# 主目录
LOCAL_CERT_DIR="/path/to/local/certs"
CUSTOMER_CERT_DIR="/path/to/customer/certs"

# 遍历本地证书
for local_cert in "$LOCAL_CERT_DIR"/*.crt; do
    local_info=$(extract_cert_info "$local_cert")
    local_fingerprint=$(calculate_fingerprint "$local_cert")
    
    # 遍历客户证书
    for customer_cert in "$CUSTOMER_CERT_DIR"/*.crt; do
        customer_info=$(extract_cert_info "$customer_cert")
        customer_fingerprint=$(calculate_fingerprint "$customer_cert")
        
        # 比较信息
        if [ "$local_info" = "$customer_info" ] && [ "$local_fingerprint" = "$customer_fingerprint" ]; then
            echo "匹配找到:"
            echo "本地证书: $local_cert"
            echo "客户证书: $customer_cert"
            echo "----------------------------"
        fi
    done
done

echo "比较完成。"
```

这个脚本会自动比较本地证书和客户提供的证书,找出它们之间的对应关系。使用这个脚本,你可以：

1. 自动遍历所有证书。
2. 提取每个证书的关键信息。
3. 计算每个证书的SHA256指纹。
4. 比较本地证书和客户证书的信息和指纹。
5. 输出匹配的证书对。

使用这个脚本之前,请确保：

1. 修改 `LOCAL_CERT_DIR` 和 `CUSTOMER_CERT_DIR` 变量,指向正确的证书目录。
2. 给脚本执行权限: `chmod +x cert_comparison.sh`
3. 运行脚本: `./cert_comparison.sh`

这个脚本将帮助你快速找出本地证书和客户提供证书之间的对应关系


# reference safe/wget-ssl.md
get the domain ssl 这个是获取完整的证书链
- `openssl s_client -connect public-stg.api.gov.sg:443 -showcerts`

