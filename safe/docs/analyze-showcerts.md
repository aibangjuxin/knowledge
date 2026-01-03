# q
比如我用命令命令行获取了完整的证书链，我想要分析完整的证书链信息。这个这个脚本将帮助你快速找出本地证书和客户提供证书之间的对应关系这个是获取完整的证书链
openssl s_client -connect public-stg.api.gov.sg:443 -showcerts。我想分析这个结果的完整输出
# a
当然,我可以帮你详细解析 `openssl s_client -connect public-stg.api.gov.sg:443 -showcerts` 命令的输出。这个命令会显示完整的 SSL/TLS 连接过程和证书链信息。让我们逐部分分析:

1. SSL/TLS 连接信息:
   首先,你会看到一些关于 SSL/TLS 连接的基本信息,包括:
   - 使用的 OpenSSL 版本
   - 连接的主机和端口
   - SSL/TLS 协议版本
   - 加密套件(Cipher Suite)

2. 证书链:
   接下来是证书链,通常按照以下顺序排列:
   - 服务器证书(叶子证书)
   - 中间证书(可能有多个)
   - 根证书(可能不会显示,因为通常预装在系统中)

   每个证书都会以 "-----BEGIN CERTIFICATE-----" 开始,以 "-----END CERTIFICATE-----" 结束。

3. 证书详细信息:
   对于每个证书,你会看到详细信息,包括:
   - 版本(Version)
   - 序列号(Serial Number)
   - 签名算法(Signature Algorithm)
   - 颁发者(Issuer)
   - 有效期(Validity)
   - 主题(Subject)
   - 主题公钥信息(Subject Public Key Info)
   - X509v3 扩展(如果有)

4. 服务器密钥交换参数:
   如果使用的是需要密钥交换的加密套件(如 DHE 或 ECDHE),你会看到相关参数。

5. SSL 会话参数:
   包括会话 ID, SSL 版本,加密套件,压缩方法等。

6. SSL 握手过程:
   显示完整的 SSL/TLS 握手过程,包括各种握手消息。

7. 验证结果:
   最后会显示证书链的验证结果,包括是否成功验证以及任何警告或错误。

为了更好地分析这个输出,我们可以创建一个脚本来解析和组织这些信息。这个脚本可以帮助你更清晰地理解证书链和连接细节。



```python
import re
import sys
from collections import defaultdict

def parse_openssl_output(output):
    # 解析连接信息
    connection_info = re.search(r'New, TLSv.*?Cipher is.*?', output, re.DOTALL).group(0)
    
    # 解析证书
    certs = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', output, re.DOTALL)
    
    # 解析证书详细信息
    cert_details = defaultdict(list)
    for i, cert in enumerate(certs):
        details = re.findall(r'\s+(\w+):(.*?)(?=\n\s+\w+:|$)', cert, re.DOTALL)
        cert_details[f'Certificate {i+1}'] = dict(details)
    
    # 解析服务器密钥交换参数
    server_params = re.search(r'Server Temp Key:.*?', output)
    server_params = server_params.group(0) if server_params else "Not found"
    
    # 解析 SSL 会话参数
    ssl_session = re.search(r'SSL-Session:.*?---', output, re.DOTALL)
    ssl_session = ssl_session.group(0) if ssl_session else "Not found"
    
    # 解析验证结果
    verify_result = re.search(r'Verify return code:.*?', output)
    verify_result = verify_result.group(0) if verify_result else "Not found"
    
    return {
        'connection_info': connection_info,
        'certificates': cert_details,
        'server_params': server_params,
        'ssl_session': ssl_session,
        'verify_result': verify_result
    }

def print_parsed_info(parsed_info):
    print("Connection Information:")
    print(parsed_info['connection_info'])
    print("\nCertificates:")
    for cert_name, cert_info in parsed_info['certificates'].items():
        print(f"\n{cert_name}:")
        for key, value in cert_info.items():
            print(f"  {key}: {value.strip()}")
    print("\nServer Parameters:")
    print(parsed_info['server_params'])
    print("\nSSL Session:")
    print(parsed_info['ssl_session'])
    print("\nVerification Result:")
    print(parsed_info['verify_result'])

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python script.py <openssl_output_file>")
        sys.exit(1)
    
    with open(sys.argv[1], 'r') as f:
        openssl_output = f.read()
    
    parsed_info = parse_openssl_output(openssl_output)
    print_parsed_info(parsed_info)
```
这个 Python 脚本可以帮助你解析和组织 `openssl s_client` 命令的输出。使用方法如下：

1. 首先,将 `openssl s_client` 的输出保存到一个文件中:
   ```
   openssl s_client -connect public-stg.api.gov.sg:443 -showcerts > output.txt
   ```

2. 然后运行这个 Python 脚本:
   ```
   python openssl_parser.py output.txt
   ```

这个脚本会解析输出并以更结构化的方式显示信息,包括:

1. 连接信息: 显示 SSL/TLS 版本和使用的加密套件。
2. 证书链: 解析每个证书的详细信息。
3. 服务器密钥交换参数: 如果存在的话。
4. SSL 会话参数: 包括会话 ID, SSL 版本等。
5. 验证结果: 显示证书链验证的结果。

这个脚本可以帮助你更容易地理解证书链的结构和各个证书之间的关系。你可以看到每个证书的颁发者(Issuer)和主题(Subject),这有助于理解证书链的层次结构。

例如,你可能会看到类似这样的结构:

1. 服务器证书(叶子证书):
   - Subject: CN=public-stg.api.gov.sg
   - Issuer: CN=Some Intermediate CA

2. 中间证书:
   - Subject: CN=Some Intermediate CA
   - Issuer: CN=Root CA

3. 根证书(如果包含在输出中):
   - Subject: CN=Root CA
   - Issuer: CN=Root CA (自签名)

通过观察这些信息,你可以确定证书链的完整性和每个证书在链中的位置。

# using shell
当然,我们可以使用Shell脚本来实现类似的功能。Shell脚本在处理文本输出方面非常强大,特别适合解析`openssl s_client`的输出。让我为你创建一个Shell脚本版本的解析器。



```bash
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
```

这个Shell脚本提供了类似于之前Python脚本的功能,用于解析`openssl s_client`的输出。以下是使用方法和脚本功能的详细说明：

使用方法：
1. 保存`openssl s_client`的输出到文件：
   ```
   openssl s_client -connect public-stg.api.gov.sg:443 -showcerts > output.txt
   ```

2. 给脚本执行权限：
   ```
   chmod +x openssl_parser.sh
   ```

3. 运行脚本：
   ```
   ./openssl_parser.sh output.txt
   ```

脚本功能：

1. 连接信息：
   显示SSL/TLS版本和使用的加密套件。

2. 证书链：
   解析每个证书的关键信息，包括：
   - 主题（Subject）
   - 颁发者（Issuer）
   - 有效期（Validity）
   - 公钥算法（Public Key Algorithm）

3. 服务器密钥交换参数：
   如果存在，显示临时密钥信息。

4. SSL会话参数：
   显示会话ID、SSL版本等信息。

5. 验证结果：
   显示证书链验证的结果。

这个脚本可以帮助你快速了解证书链的结构和各个证书之间的关系。通过观察每个证书的Subject和Issuer，你可以理解证书链的层次结构。

例如，你可能会看到类似这样的结构：

1. 服务器证书（叶子证书）：
   - Subject: CN=public-stg.api.gov.sg
   - Issuer: CN=Some Intermediate CA

2. 中间证书：
   - Subject: CN=Some Intermediate CA
   - Issuer: CN=Root CA

3. 根证书（如果包含在输出中）：
   - Subject: CN=Root CA
   - Issuer: CN=Root CA （自签名）

这个脚本的优点是它直接使用Shell命令，不需要额外的Python环境，更适合在各种Linux系统上快速使用。


