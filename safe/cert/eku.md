# summary 
---

### **1. 变更背景**

- 自 **2025-10-01** 起，**Digicert 公有 TLS 证书将不再包含 Client Authentication EKU**。
    
- 影响：所有依赖 **Client Authentication EKU** 的证书，在更新、续签或重新签发后将无法再支持 mTLS 客户端身份验证。
    

---

### **2. 需要核对的场景**

- **普通 TLS（HTTPS）场景**
    
    - 只需要 Server Authentication EKU。
        
    - 证书续签后不受影响。
        
    - **动作**：无需调整，仅确保更新为最新的 Digicert 证书即可。
        
    
- **mTLS（双向认证）场景**
    
    - 需要 Client Authentication EKU。
        
    - 公有 CA（Digicert）不再提供，需要切换为 **私有 CA 签发客户端证书**。
        
    - **动作**：
        
        - 生成新的客户端证书（由私有 CA 签发）。
            
        - 重新配置应用或 Kong Gateway 以加载新证书。
            
        - 在旧证书过期前完成测试和替换。
            
        
    

---

### **3. 最终结论**

- **普通 TLS 证书**：只需正常续签，保持 Server Authentication EKU 即可。
    
- **mTLS 证书**：必须重新申请（由私有 CA 签发）并替换现有的客户端证书。
    

---
回滚流程
- 
- **场景1: 仅用于服务器端 TLS (HTTPS)**
  - **动作**: 无需任何改动。这类证书只需要 `Server Authentication` EKU。到期后按正常流程更新即可。
- **场景2: 用于 mTLS (客户端认证)**
  - **动作**: 必须使用由 **私有 CA** 签发的 **专用客户端证书**。公有 CA（如 Digicert）签发的证书仅用于服务器端。
  - 替换mTLS的由Digicert签发的证书中包含EKU的就可以了.

# Client Authentication EKU 从公共 TLS 证书中移除

> **摘要**: 本文档旨在通知 Digicert 证书的消费者，自 2025 年 10 月 1 日起，新签发、续期或重新颁发的 TLS 证书将不再包含客户端认证 (Client Authentication) 的扩展密钥用法 (EKU)。

## 变更内容

从 **2025年10月1日** 起，由 Digicert 签发的 TLS 证书将不再包含 **客户端认证 (Client Authentication)** 扩展密钥用法 (EKU)。

### 详细信息

目前，来自公共证书颁发机构（如 Digicert）的外部 TLS 证书通常同时包含 **服务器认证 (Server Authentication)** 和 **客户端认证 (Client Authentication)** 两种 EKU。

自 2025 年 10 月 1 日起，新申请、续期或重新颁发的 Digicert 证书将不再包含客户端认证 EKU。在此日期之前签发的现有证书不受影响，可继续使用直至到期。

---

## 什么是扩展密钥用法 (EKU)?

扩展密钥用法 (Extended Key Usage) 是 X.509 证书中的一个关键扩展字段，用于明确指定证书的预期用途，从而限制其可执行的加密操作。

### 常见 EKU 类型

| EKU 类型 | OID | 描述 | 典型用途 |
| :--- | :--- | :--- | :--- |
| **Server Authentication** | `1.3.6.1.5.5.7.3.1` | TLS Web 服务器认证 | HTTPS 网站服务器 |
| **Client Authentication** | `1.3.6.1.5.5.7.3.2` | TLS Web 客户端认证 | 双向 TLS (mTLS) |
| **Code Signing** | `1.3.6.1.5.5.7.3.3` | 代码签名 | 软件和驱动程序签名 |
| **Email Protection** | `1.3.6.1.5.5.7.3.4` | 邮件保护 | S/MIME 邮件加密 |
| **Time Stamping** | `1.3.6.1.5.5.7.3.8` | 时间戳 | 数字签名时间戳 |

### Server Authentication vs. Client Authentication

- **Server Authentication (服务器认证)**
  - **目的**: 验证服务器的身份。
  - **场景**: 客户端（如浏览器）验证网站服务器的合法性，是标准 HTTPS 的基础。

- **Client Authentication (客户端认证)**
  - **目的**: 验证客户端的身份。
  - **场景**: 用于双向 TLS (mTLS) 认证，常见于 API 访问控制、企业内部服务通信、VPN 和 IoT 设备认证。

### 为什么 Digicert 移除 Client Authentication EKU?

1.  **安全最佳实践**: 遵循“最小权限”原则，证书应仅包含其预期用途。
2.  **合规性要求**: 响应 CA/Browser Forum 基线要求的变化。
3.  **风险降低**: 减少因证书权限过大而被滥用的风险。
4.  **鼓励专用证书**: 提倡为服务器和客户端等不同角色使用专门的证书。

---

## 如何验证证书的 EKU?

### 方法 1: 使用 OpenSSL 命令行

#### 检查本地证书文件

```bash
# 查看证书的所有文本信息，包括 EKU
openssl x509 -in certificate.crt -text -noout

# 仅筛选出 EKU 相关行
openssl x509 -in certificate.crt -text -noout | grep -A 2 "Extended Key Usage"
```

#### 检查在线服务器证书

```bash
# 获取并检查在线证书的 EKU
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null | \
openssl x509 -text -noout | grep -A 2 "Extended Key Usage"
```

### 方法 2: 使用自动化脚本

我们提供了一个便捷的脚本 `check_eku.sh` 来自动检查证书的 EKU 信息。

```bash
# 检查本地证书文件
./check_eku.sh server.crt

# 检查在线证书
./check_eku.sh example.com:443

# 批量检查
./check_eku.sh certs/*.crt

# 启用详细输出
./check_eku.sh -v example.com
```

### 方法 3: 使用浏览器

1.  在浏览器中访问目标网站。
2.  点击地址栏的 **锁** 图标。
3.  选择“证书有效”或“连接是安全的” -> “证书信息”。
4.  切换到 **“详细信息”** 标签页。
5.  找到并选中 **“扩展密钥用法”** (Enhanced Key Usage / Extended Key Usage) 字段查看。

---

## 示例输出解读

### 包含 Client Authentication 的证书

```text
Extended Key Usage:
  ✓ Server Authentication (TLS Web Server)
  ✓ Client Authentication (TLS Web Client)
⚠️  注意: 此证书包含 Client Authentication EKU。
   从2025年10月1日起，Digicert 新证书将不再包含此 EKU。
```

### 仅包含 Server Authentication 的证书

```text
Extended Key Usage:
  ✓ Server Authentication (TLS Web Server)
```

---

## 影响评估与应对措施

### 受影响的场景

1.  **使用双向 TLS (mTLS) 的应用**:
    -   API 网关与微服务之间的通信。
    -   需要对客户端进行强认证的企业内部服务。
    -   IoT 设备与云平台之间的认证。
2.  **依赖客户端证书认证的系统**:
    -   VPN 客户端接入认证。
    -   企业内网访问控制 (NAC)。
    -   高安全级别的应用登录。

### 应对措施

1.  **评估现状**:
    使用 `check_eku.sh` 脚本或 OpenSSL 命令，全面排查现有证书是否包含 `Client Authentication` EKU。
    ```bash
    # 示例：检查指定目录下所有 .crt 证书
    find /path/to/certs -name "*.crt" -exec ./check_eku.sh {} \;
    ```

2.  **制定迁移计划**:
    -   识别所有依赖 `Client Authentication` EKU 的应用和服务。
    -   为这些应用申请 **专用的客户端认证证书**（通常由私有 CA 签发）。
    -   更新应用配置，使其信任新的客户端证书及对应的 CA。

3.  **时间规划**:
    -   **2025年10月1日前**: 现有证书不受影响，可正常续期。
    -   **临近或超过此日期**: 在续期或申请新证书时，必须为需要客户端认证的场景准备独立的证书。

### 替代方案

1.  **专用客户端证书**: 从 **私有 CA** (如 GCP Certificate Authority Service) 或自建 CA 申请专门用于客户端认证的证书。这是最推荐的方案。
2.  **其他认证机制**: 根据应用场景，评估使用 API 密钥、OAuth 2.0、JWT 令牌等认证方式的可行性。

---

## 后续处理核心步骤

核心动作是 **重新申请并替换证书**，具体步骤如下：

### 1. 为什么需要新证书？

- **根本原因**: Digicert 自 2025-10-01 起，不再在公有 TLS 证书中捆绑 `Client Authentication` EKU。
- **直接影响**: 如果您的应用依赖此 EKU 进行 mTLS 认证，现有证书在到期续订后将功能失效，导致认证失败。

### 2. 处理步骤详解

#### 步骤 A: 区分使用场景

	- **场景1: 仅用于服务器端 TLS (HTTPS)**
	  - **动作**: 无需任何改动。这类证书只需要 `Server Authentication` EKU。到期后按正常流程更新即可。
	
	- **场景2: 用于 mTLS (客户端认证)**
	  - **动作**: 必须使用由 **私有 CA** 签发的 **专用客户端证书**。公有 CA（如 Digicert）签发的证书仅用于服务器端。

#### 步骤 B: 申请新证书

1.  **服务器证书 (公有 CA)**:
    -   继续使用 Digicert 等公有 CA 签发。
    -   该证书将只包含 `Server Authentication` EKU。

2.  **客户端证书 (私有 CA)**:
    -   使用 **GCP Certificate Authority Service (CAS)** 或其他企业内部 CA。
    -   签发 **仅包含** `Client Authentication` EKU 的专用证书。

#### 步骤 C: 替换与验证

1.  在服务器（如 Nginx, Kong, GKE Ingress）和客户端配置中，替换为新的证书文件。
2.  重启相关服务。
3.  使用 OpenSSL 验证新证书的 EKU 是否正确。
    ```bash
    # 验证客户端证书
    openssl x509 -in new_client.crt -text -noout | grep -A 1 "Extended Key Usage"
    ```
4.  确认输出中包含 `TLS Web Client Authentication`。

### 3. 推荐做法 (结合云原生环境)

-   在云平台（如 GCP）中：
    -   使用 **证书管理器 (Certificate Manager)** 自动化管理面向公网的 **服务器证书**。
    -   使用 **私有 CA (Private CA)** 服务来签发和管理内部服务所需的 **客户端证书**。
-   **核心思想**: 将证书用途分离，确保服务器和客户端使用独立的、权限最小化的证书，避免未来因 CA 策略变更导致业务中断。

---

## 相关资源

-   [RFC 5280 - Internet X.509 Public Key Infrastructure Certificate](https://tools.ietf.org/html/rfc5280)
-   [CA/Browser Forum Baseline Requirements](https://cabforum.org/baseline-requirements-documents/)
-   [OpenSSL Documentation](https://www.openssl.org/docs/)



# effect 

后续处理的核心步骤就是 **重新申请并替换证书**，但要根据使用场景来细化：

---

### **1. 为什么需要新证书？**

- **Digicert 自 2025-10-01 起不再在公有证书中提供 Client Authentication EKU**。
    
- 如果现有证书依赖该 EKU（用于 mTLS 或客户端认证），在证书更新或重新签发后将不再包含此功能，导致认证失败。
    

---

### **2. 后续处理步骤**

  

#### **步骤 A：区分使用场景**

- **仅用于服务器端 TLS（HTTPS）**
    
    - 只需要 Server Authentication EKU，无需改动。
        
    - 证书到期后按正常流程更新即可。
        
    
- **用于 mTLS（客户端认证）**
    
    - 必须生成新的 **客户端证书**，由 **私有 CA** 或企业 CA 颁发（非公有 CA）。
        
    - 公有证书（如 Digicert）只用于服务器端。
        
    

---

#### **步骤 B：申请新证书**

1. **服务器端证书（公有 CA）**
    
    - 继续使用 Digicert 等公有 CA 签发。
        
    - 不需要 Client Authentication EKU。
        
    
2. **客户端证书（私有 CA）**
    
    - 使用 GCP Certificate Authority Service (CAS) 或自建 CA。
        
    - 签发仅包含 Client Authentication EKU 的证书。
        
    

---

#### **步骤 C：替换与验证**

1. 替换证书文件并重启相关服务（Nginx/Kong/GKE Ingress 等）。
    
2. 使用以下命令验证新证书：
    

```
openssl x509 -in new_client.crt -text -noout | grep -A 1 "Extended Key Usage"
```

2. 确认 EKU 包含：
    

```
TLS Web Client Authentication
```

  

---

### **3. 推荐做法（结合 POP Migration）**

- 在 Federated GCP 中：
    
    - 使用 **Google Certificate Manager** 管理服务器证书。
        
    - 使用 **GCP Private CA** 管理客户端证书。
        
    
- 分离证书用途，避免未来证书更新时引发业务中断。
    

---

要不要我帮你做一个 **后续行动清单 (Markdown 表格)**，包括

- 需要替换的证书清单
    
- 是否需申请新证书
    
- 是否需改造 mTLS 方案
    
    方便你直接贴到文档或项目计划里？
### **EKU (Extended Key Usage) 在证书中的作用**

  

EKU 是 X.509 证书的扩展字段，用于定义该证书可以用于哪些用途，防止证书被滥用。

常见的 EKU 值包括：

- **TLS Web Server Authentication**
    
    证书可用于服务器身份验证（HTTPS/TLS 服务器端）。
    
- **TLS Web Client Authentication**
    
    证书可用于客户端身份验证（mTLS 场景下必须具备）。
    

---

### **在 mTLS 中的证书使用场景**

  

#### **1. 服务器端证书**

- 必须包含：
    
    - TLS Web Server Authentication
        
    
- 用途：
    
    - 证明服务器身份，供客户端验证。
        
    

  

#### **2. 客户端证书**

- 必须包含：
    
    - TLS Web Client Authentication
        
    
- 用途：
    
    - 证明客户端身份，供服务器验证。
        
    

---

### **为什么 EKU 很重要？**

- 在 mTLS 中，证书必须有明确的用途声明，TLS 握手时会检查 EKU。
    
- 如果客户端证书缺少 Client Authentication EKU，服务器可能拒绝连接。
    
- 服务器证书若缺少 Server Authentication EKU，客户端也可能报错。
    

---

### **证书使用示意图**

```
graph TD;
    A[Client 发送证书] --> B[Server 验证证书是否含 Client Authentication EKU];
    B --> C{验证成功?};
    C -->|Yes| D[允许建立 mTLS 连接];
    C -->|No| E[拒绝连接，握手失败];
```

---

### **最佳实践**

- **服务器证书**：由公有 CA（如 Digicert）签发，仅含 Server Authentication EKU。
    
- **客户端证书**：由私有 CA 签发，仅含 Client Authentication EKU。
    
- 分离用途，避免未来公有 CA 移除 Client Authentication EKU 时影响服务。
    

---

是否要我帮你整理一个 **mTLS 证书配置检查清单**，列出哪些证书需要哪些 EKU、如何验证、如何更新？
以下为 **mTLS 证书配置检查清单**，专门针对 **Issued by Digicert** 的证书，帮助识别哪些证书需要更新、如何验证以及后续步骤。

---

### **mTLS 证书配置检查清单**

  

#### **1. 目标**

- 找出所有由 **Digicert 签发** 的证书。
    
- 检查其 **Extended Key Usage (EKU)** 是否包含 TLS Web Client Authentication。
    
- 对包含该 EKU 的证书，提前制定替换计划。
    

---

#### **2. 检查命令**

  

##### **检查远程域名证书**

```
openssl s_client -connect your.domain.com:443 -servername your.domain.com </dev/null 2>/dev/null \
| openssl x509 -text -noout \
| grep -E "Issuer:|Extended Key Usage"
```

输出示例：

```
Issuer: C=US, O=DigiCert Inc, CN=DigiCert TLS RSA SHA256 2020 CA1
X509v3 Extended Key Usage:
    TLS Web Server Authentication, TLS Web Client Authentication
```

##### **检查本地证书文件**

```
openssl x509 -in /path/to/certificate.crt -text -noout \
| grep -E "Issuer:|Extended Key Usage"
```

---

#### **3. 判断规则**

- 如果输出中：
    
    - **Issuer 包含 DigiCert**
        
    - 且 Extended Key Usage 中包含 TLS Web Client Authentication
        
    
- 说明该证书需要替换（在 2025-10-01 前完成）。
    

---

#### **4. 后续行动**

|**证书用途**|**当前 EKU 状态**|**签发方**|**动作**|
|---|---|---|---|
|仅服务器认证|只包含 TLS Web Server Authentication|DigiCert|无需动作|
|mTLS 客户端认证|包含 TLS Web Client Authentication|DigiCert|需替换为私有 CA 签发的新证书|
|混合用途|同时包含 Server 和 Client|DigiCert|分离用途：服务器证书继续用 DigiCert，客户端证书改为私有 CA|

---

#### **5. 建议替换方案**

1. **公有 CA (DigiCert)**：
    
    仅用于服务器证书，包含 Server Authentication EKU。
    
2. **私有 CA (GCP CAS 或内部 CA)**：
    
    用于客户端证书，包含 Client Authentication EKU。
    

---

要不要我帮你写一个 **批量检测脚本**，直接输出一个 **Markdown 表格**，列出：

- 域名或证书路径
    
- Issuer（签发者）
    
- 是否包含 Client Authentication EKU
    
- 是否需要替换
    

  

这样可以直接生成审计报告。需要吗？

---

## 附录：检查脚本 (check_eku.sh)

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

# Check if certificate is issued by DigiCert
check_digicert_issuer() {
    local issuer="$1"
    
    # DigiCert issuer patterns (case insensitive)
    local digicert_patterns=(
        "DigiCert"
        "Symantec"  # DigiCert acquired Symantec CA
        "GeoTrust"  # DigiCert acquired GeoTrust
        "Thawte"    # DigiCert acquired Thawte
        "RapidSSL"  # DigiCert acquired RapidSSL
    )
    
    for pattern in "${digicert_patterns[@]}"; do
        if echo "$issuer" | grep -qi "$pattern"; then
            return 0  # Is DigiCert
        fi
    done
    
    return 1  # Not DigiCert
}

# Parse EKU and check DigiCert impact
parse_eku() {
    local eku_line="$1"
    local verbose="$2"
    local issuer="$3"
    
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
    
    echo ""
    
    # Check if this is a DigiCert certificate
    local is_digicert=false
    if check_digicert_issuer "$issuer"; then
        is_digicert=true
        echo -e "${BLUE}Certificate Authority:${NC} ${YELLOW}DigiCert Family (Affected by EKU change)${NC}"
    else
        echo -e "${BLUE}Certificate Authority:${NC} ${GREEN}Non-DigiCert (Not affected by EKU change)${NC}"
    fi
    
    echo ""
    
    # DigiCert-specific warnings
    if [ "$has_client_auth" = true ] && [ "$is_digicert" = true ]; then
        echo -e "${RED}🚨 CRITICAL: DigiCert certificate with Client Authentication EKU detected!${NC}"
        echo -e "${RED}   Action Required: This certificate will be affected by the October 1st, 2025 change${NC}"
        echo -e "${RED}   Impact: Client Authentication EKU will be removed from new/renewed certificates${NC}"
        echo -e "${YELLOW}   Recommendation: Plan for separate client authentication certificates${NC}"
    elif [ "$has_client_auth" = true ] && [ "$is_digicert" = false ]; then
        echo -e "${YELLOW}⚠️  Info: Non-DigiCert certificate with Client Authentication EKU${NC}"
        echo -e "${YELLOW}   Status: Not affected by DigiCert's October 2025 change${NC}"
        echo -e "${YELLOW}   Note: Check with your CA for their EKU policies${NC}"
    elif [ "$is_digicert" = true ]; then
        echo -e "${GREEN}✅ DigiCert certificate without Client Authentication EKU${NC}"
        echo -e "${GREEN}   Status: Already compliant with post-October 2025 standards${NC}"
    else
        echo -e "${GREEN}✅ Non-DigiCert certificate${NC}"
        echo -e "${GREEN}   Status: Not affected by DigiCert EKU change${NC}"
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
        parse_eku "$eku_info" "$verbose" "$issuer"
    else
        echo -e "${RED}Extended Key Usage information not found${NC}"
        # Still check if it's DigiCert even without EKU
        if check_digicert_issuer "$issuer"; then
            echo -e "${YELLOW}⚠️  DigiCert certificate without visible EKU information${NC}"
        fi
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
        parse_eku "$eku_info" "$verbose" "$issuer"
    else
        echo -e "${RED}Extended Key Usage information not found${NC}"
        # Still check if it's DigiCert even without EKU
        if check_digicert_issuer "$issuer"; then
            echo -e "${YELLOW}⚠️  DigiCert certificate without visible EKU information${NC}"
        fi
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