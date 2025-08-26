# Client Authentication Removed From Public TLS Certificates

Notification to consumers of Digicert Certificates

## WHAT IS CHANGING?

From 1st October 2025 TLS certificates issued by Digicert will no longer include the Client Authentication Extended Key Usage (EKU).

## DETAILS

Currently, external TLS certificates from public certificate authorities, such as Digicert, commonly include both the Webserver Authentication EKU and Client Authentication EKU.
From 1st October, Client Authentication EKU will not be present on new, renewed or reissued Digicert certificates.
Digicert certificates issued before 1st October 2025 will not be affected.

## 什么是 Extended Key Usage (EKU)?

Extended Key Usage (扩展密钥用法) 是 X.509 证书中的一个重要扩展字段，用于指定证书的预期用途。它限制了证书可以用于哪些特定的加密操作。

### 常见的 EKU 类型

| EKU 类型                  | OID               | 描述               | 用途             |
| ------------------------- | ----------------- | ------------------ | ---------------- |
| **Server Authentication** | 1.3.6.1.5.5.7.3.1 | TLS Web 服务器认证 | HTTPS 服务器证书 |
| **Client Authentication** | 1.3.6.1.5.5.7.3.2 | TLS Web 客户端认证 | 客户端证书认证   |
| **Code Signing**          | 1.3.6.1.5.5.7.3.3 | 代码签名           | 软件代码签名     |
| **Email Protection**      | 1.3.6.1.5.5.7.3.4 | 邮件保护           | S/MIME 邮件加密  |
| **Time Stamping**         | 1.3.6.1.5.5.7.3.8 | 时间戳             | 数字时间戳服务   |

### Server Authentication vs Client Authentication

- **Server Authentication (服务器认证)**

  - 用于验证服务器身份
  - 标准的 HTTPS 网站证书用途
  - 客户端验证服务器的合法性

- **Client Authentication (客户端认证)**
  - 用于验证客户端身份
  - 双向 TLS (mTLS) 认证
  - API 访问控制和身份验证
  - VPN 客户端认证

### 为什么 Digicert 要移除 Client Authentication EKU?

1. **安全最佳实践**: 证书应该只包含必要的用途，遵循最小权限原则
2. **合规要求**: CA/Browser Forum 基线要求的变化
3. **风险降低**: 减少证书被误用的可能性
4. **专用证书**: 鼓励为不同用途使用专门的证书

## 如何验证证书的 EKU?

### 方法 1: 使用 OpenSSL 命令行

#### 检查本地证书文件

```bash
# 查看证书的所有扩展信息
openssl x509 -in certificate.crt -text -noout

# 只查看EKU信息
openssl x509 -in certificate.crt -text -noout | grep -A 2 "Extended Key Usage"
```

#### 检查在线证书

```bash
# 获取并检查在线证书的EKU
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null | \
openssl x509 -text -noout | grep -A 2 "Extended Key Usage"

# 完整的证书信息
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null | \
openssl x509 -text -noout
```

### 方法 2: 使用自动化脚本

我们提供了一个便捷的脚本 `check_eku.sh` 来自动检查证书的 EKU 信息：

```bash
# 检查本地证书文件
./check_eku.sh server.crt

# 检查在线证书
./check_eku.sh example.com:443
./check_eku.sh api-platform-pprd.business.hsbc.co.uk:443

# 批量检查多个证书
./check_eku.sh certs/*.crt

# 详细输出模式
./check_eku.sh -v example.com

# 调试模式（显示原始OpenSSL输出）
./check_eku.sh -d example.com
```

### 方法 3: 使用浏览器

1. 在浏览器中访问网站
2. 点击地址栏的锁图标
3. 选择"证书"或"证书信息"
4. 查看"扩展"或"详细信息"标签页
5. 找到"增强型密钥用法"或"Extended Key Usage"

## 示例输出解读

### 包含 Client Authentication 的证书

```
Extended Key Usage:
  ✓ Server Authentication (TLS Web Server)
  ✓ Client Authentication (TLS Web Client)
⚠️  注意: 此证书包含Client Authentication EKU
   从2025年10月1日起，Digicert新证书将不再包含此EKU
```

### 仅包含 Server Authentication 的证书

```
Extended Key Usage:
  ✓ Server Authentication (TLS Web Server)
```

## 影响评估和应对措施

### 谁会受到影响?

1. **使用双向 TLS (mTLS) 的应用**

   - API 网关和微服务
   - 企业内部服务通信
   - IoT 设备认证

2. **客户端证书认证场景**
   - VPN 客户端认证
   - 企业网络访问控制
   - 高安全性应用

### 应对措施

1. **评估当前使用情况**

   ```bash
   # 检查所有证书的EKU
   find /path/to/certs -name "*.crt" -exec ./check_eku.sh {} \;
   ```

2. **准备迁移计划**

   - 识别需要 Client Authentication 的应用
   - 申请专用的客户端认证证书
   - 更新应用配置

3. **时间规划**
   - 2025 年 10 月 1 日前：现有证书不受影响
   - 续期时：需要单独申请客户端认证证书
   - 新证书：只包含 Server Authentication EKU

### 替代方案

1. **专用客户端证书**: 申请专门用于客户端认证的证书
2. **私有 CA**: 使用企业内部 CA 签发包含 Client Authentication 的证书
3. **其他认证方式**: 考虑使用 API 密钥、JWT 令牌等替代方案

## 相关资源

- [RFC 5280 - Internet X.509 Public Key Infrastructure Certificate](https://tools.ietf.org/html/rfc5280)
- [CA/Browser Forum Baseline Requirements](https://cabforum.org/baseline-requirements-documents/)
- [OpenSSL Documentation](https://www.openssl.org/docs/)


# script 
```bash
#!/bin/bash

# check_eku.sh - Check Extended Key Usage (EKU) in certificates
# Usage:
#   ./check_eku.sh server.crt
#   ./check_eku.sh your.domain.com:443
#   ./check_eku.sh certs/*.crt
# Note: openssl s_client gets raw certificate data (PEM format), which is Base64-encoded binary data.
# To read specific certificate information (like EKU), you must first parse it with openssl x509 -text into human-readable format.

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Help information
show_help() {
    echo "Usage: $0 [options] <certificate_file_or_domain:port>"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --verbose  Verbose output"
    echo "  -d, --debug    Debug mode (show raw openssl output)"
    echo ""
    echo "Examples:"
    echo "  $0 server.crt                    # Check local certificate file"
    echo "  $0 example.com:443               # Check online certificate"
    echo "  $0 certs/*.crt                   # Batch check certificate files"
    echo ""
}

# Check dependencies
check_dependencies() {
    if ! command -v openssl &> /dev/null; then
        echo -e "${RED}Error: openssl is required but not installed${NC}"
        exit 1
    fi
}

# Parse EKU
parse_eku() {
    local eku_line="$1"
    local verbose="$2"
    
    echo -e "${BLUE}Extended Key Usage:${NC}"
    
    # Check common EKU types
    local has_server_auth=false
    local has_client_auth=false
    local has_code_signing=false
    local has_email_protection=false
    
    if echo "$eku_line" | grep -q "TLS Web Server Authentication\|serverAuth"; then
        echo -e "  ${GREEN}✓ Server Authentication (TLS Web Server)${NC}"
        has_server_auth=true
    fi
    
    if echo "$eku_line" | grep -q "TLS Web Client Authentication\|clientAuth"; then
        echo -e "  ${GREEN}✓ Client Authentication (TLS Web Client)${NC}"
        has_client_auth=true
    fi
    
    if echo "$eku_line" | grep -q "Code Signing\|codeSigning"; then
        echo -e "  ${GREEN}✓ Code Signing${NC}"
        has_code_signing=true
    fi
    
    if echo "$eku_line" | grep -q "E-mail Protection\|emailProtection"; then
        echo -e "  ${GREEN}✓ Email Protection${NC}"
        has_email_protection=true
    fi
    
    # Show raw EKU information (if verbose mode)
    if [ "$verbose" = true ]; then
        echo -e "${YELLOW}Raw EKU Information:${NC}"
        echo "$eku_line" | sed 's/^/  /'
    fi
    
    # Digicert change warning
    if [ "$has_client_auth" = true ]; then
        echo -e "${YELLOW}⚠️  Warning: This certificate contains Client Authentication EKU${NC}"
        echo -e "${YELLOW}   From October 1st, 2025, Digicert new certificates will no longer include this EKU${NC}"
    fi
    
    return 0
}

# Check certificate file
check_cert_file() {
    local cert_file="$1"
    local verbose="$2"
    
    if [ ! -f "$cert_file" ]; then
        echo -e "${RED}Error: File '$cert_file' does not exist${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Checking certificate file: $cert_file${NC}"
    echo "----------------------------------------"
    
    # Get basic certificate information
    local subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//')
    local issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | sed 's/issuer=//')
    local not_after=$(openssl x509 -in "$cert_file" -noout -dates 2>/dev/null | grep notAfter | sed 's/notAfter=//')
    
    echo -e "${BLUE}Subject:${NC} $subject"
    echo -e "${BLUE}Issuer:${NC} $issuer"
    echo -e "${BLUE}Expires:${NC} $not_after"
    echo ""
    
    # Get EKU information
    local eku_info=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A 10 "X509v3 Extended Key Usage" | grep -v "X509v3 Extended Key Usage" | head -1 | xargs)
    
    if [ -n "$eku_info" ]; then
        parse_eku "$eku_info" "$verbose"
    else
        echo -e "${RED}Extended Key Usage information not found${NC}"
    fi
    
    echo ""
}

# Check online certificate
check_online_cert() {
    local target="$1"
    local verbose="$2"
    local debug="$3"
    
    # Parse hostname and port
    local host=$(echo "$target" | cut -d: -f1)
    local port=$(echo "$target" | cut -d: -f2)
    
    if [ "$port" = "$host" ]; then
        port=443
    fi
    
    echo -e "${BLUE}Checking online certificate: $host:$port${NC}"
    echo "----------------------------------------"
    
    # Test connection
    if ! echo | openssl s_client -connect "$host:$port" -servername "$host" >/dev/null 2>&1; then
        echo -e "${RED}Error: Cannot connect to $host:$port${NC}"
        return 1
    fi
    
    # Get certificate information - using more reliable method
    local subject=$(echo | openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//')
    local issuer=$(echo | openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//')
    local not_after=$(echo | openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | grep notAfter | sed 's/notAfter=//')
    
    echo -e "${BLUE}Subject:${NC} $subject"
    echo -e "${BLUE}Issuer:${NC} $issuer"
    echo -e "${BLUE}Expires:${NC} $not_after"
    echo ""
    
    # Get EKU information - using more precise method
    local eku_raw=$(echo | openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -text -noout 2>/dev/null | grep -A 3 "X509v3 Extended Key Usage")
    local eku_info=$(echo "$eku_raw" | grep -v "X509v3 Extended Key Usage" | grep -v "X509v3" | head -1 | xargs)
    
    # Debug mode shows raw output
    if [ "$debug" = true ]; then
        echo -e "${YELLOW}Debug Info - Raw EKU Output:${NC}"
        echo "$eku_raw"
        echo -e "${YELLOW}Debug Info - Full Certificate Text (first 50 lines):${NC}"
        echo | openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -text -noout 2>/dev/null | head -50
        echo ""
    fi
    
    if [ -n "$eku_info" ]; then
        parse_eku "$eku_info" "$verbose"
    else
        echo -e "${RED}Extended Key Usage information not found${NC}"
        if [ "$debug" != true ]; then
            echo -e "${YELLOW}Tip: Use -d option to see debug information${NC}"
        fi
    fi
    
    echo ""
}

# Main function
main() {
    local verbose=false
    local debug=false
    local targets=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -d|--debug)
                debug=true
                shift
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
            *)
                targets+=("$1")
                shift
                ;;
        esac
    done
    
    # Check dependencies
    check_dependencies
    
    # Check if targets are provided
    if [ ${#targets[@]} -eq 0 ]; then
        echo -e "${RED}Error: Please specify certificate file or domain name${NC}"
        show_help
        exit 1
    fi
    
    # Process each target
    for target in "${targets[@]}"; do
        if [[ "$target" == *":"* ]] || [[ "$target" =~ ^[a-zA-Z0-9.-]+$ ]]; then
            # Looks like a domain name
            check_online_cert "$target" "$verbose" "$debug"
        else
            # Looks like a file
            check_cert_file "$target" "$verbose"
        fi
    done
}

# Run main function
main "$@"
```