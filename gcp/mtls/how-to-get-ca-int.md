要在 macOS 上获取 root.pem 和 intermediate.pem 文件进行模拟测试，通常有两种方式： 1. 从证书颁发机构 (CA) 获取证书：你可以从公共 CA（例如 Let’s Encrypt、DigiCert 等）获取根证书和中间证书。 2. 生成自签名证书：你可以使用 OpenSSL 在本地生成根证书和中间证书。

# method 1

从证书颁发机构 (CA) 获取根证书和中间证书的过程通常涉及以下几个步骤。以 Let’s Encrypt 和 DigiCert 为例：

### **1.** 

### **从 Let’s Encrypt 获取根证书和中间证书**

Let’s Encrypt 提供免费的证书，且其证书链由根证书和中间证书组成。Let’s Encrypt 的根证书是 **ISRG Root X1**，中间证书是 **R3**。

#### **获取根证书：**

你可以从 Let’s Encrypt 官网获取其根证书。访问以下链接：

- **ISRG Root X1 证书**: [ISRG Root X1](https://letsencrypt.org/certs/isrgrootx1.pem)

你可以直接下载 isrgrootx1.pem 文件。

#### **获取中间证书：**

Let’s Encrypt 的中间证书是 **R3**，可以通过以下链接获取：

- **Let’s Encrypt R3 中间证书**: [R3 证书](https://letsencrypt.org/certs/lets-encrypt-r3.pem)

直接下载 lets-encrypt-r3.pem 文件。

### **2.** 

### **从 DigiCert 获取根证书和中间证书**

DigiCert 作为一个商业 CA，提供多个证书链，根证书和中间证书可以通过其官网获取。

#### **获取根证书：**

DigiCert 根证书可以通过以下链接获得：

- **DigiCert Global Root CA**: [DigiCert Global Root CA](https://www.digicert.com/CACerts/DigiCertGlobalRootCA.crt)

你可以直接下载 DigiCertGlobalRootCA.crt 文件。

#### **获取中间证书：**

DigiCert 还提供多个中间证书。例如，如果你使用 DigiCert 提供的标准 SSL 证书，它通常会包含以下中间证书之一：

- **DigiCert Intermediate CA**: [DigiCert Intermediate CA](https://www.digicert.com/CACerts/DigiCertSHA2HighAssuranceServerCA.crt)

下载 DigiCertSHA2HighAssuranceServerCA.crt 文件。

### **3.** 

### **使用证书链**

一旦你从 CA 下载了根证书和中间证书，你可以根据需求将它们组合到一起，形成完整的证书链。

例如，在使用 **Let’s Encrypt** 时，通常需要将根证书和中间证书组合在一起供服务器使用（例如，Nginx、Apache）。

### **4.** 

### **如何在 macOS 上下载证书**

你可以直接通过浏览器下载这些证书文件，或者使用 curl 命令从命令行下载它们。例如：

```
# 下载 Let's Encrypt 的 ISRG Root X1 证书
curl -o isrgrootx1.pem https://letsencrypt.org/certs/isrgrootx1.pem

# 下载 Let's Encrypt 的 R3 中间证书
curl -o lets-encrypt-r3.pem https://letsencrypt.org/certs/lets-encrypt-r3.pem
```

或者通过浏览器直接访问上述链接，点击右键选择 “保存为” 下载证书。

### **总结**

- **Let’s Encrypt** 和 **DigiCert** 都提供了公开下载其根证书和中间证书的方式。
- 根证书用于验证证书链的信任起点，而中间证书则用于建立与根证书之间的信任链。
- 在大多数情况下，从这些公共 CA 获取根证书和中间证书非常简单，只需要下载并组合即可。

如果你使用其他 CA，获取方式类似，通常可以通过该 CA 的官方网站找到证书链文件的下载链接。

# method 2

要在 macOS 上获取 root.pem 和 intermediate.pem 文件进行模拟测试，通常有两种方式：

1. **从证书颁发机构 (CA) 获取证书**：你可以从公共 CA（例如 Let’s Encrypt、DigiCert 等）获取根证书和中间证书。
2. **生成自签名证书**：你可以使用 OpenSSL 在本地生成根证书和中间证书。

下面是使用 OpenSSL 生成自签名根证书和中间证书的步骤。

### **1. 安装 OpenSSL**

首先确保你已经安装了 OpenSSL。你可以通过 Homebrew 安装它：

```
brew install openssl
```

### **2. 创建根证书（**

### **root.pem**

### **）**

在创建根证书之前，需要生成一个私钥。

```
# 生成根证书的私钥
openssl genpkey -algorithm RSA -out root-key.pem -aes256

# 创建根证书的自签名证书
openssl req -key root-key.pem -new -x509 -out root.pem -days 3650 -subj "/C=US/ST=California/L=San Francisco/O=Test Root CA/CN=Test Root CA"
```

这会生成 root.pem 文件，并且在 root-key.pem 文件中存储根证书的私钥。

### **3. 创建中间证书（**

### **intermediate.pem**

### **）**

接下来，生成中间证书和它的私钥。

```
# 创建中间证书的私钥
openssl genpkey -algorithm RSA -out intermediate-key.pem -aes256

# 创建中间证书的签署请求
openssl req -key intermediate-key.pem -new -out intermediate.csr -subj "/C=US/ST=California/L=San Francisco/O=Test Intermediate CA/CN=Test Intermediate CA"

# 使用根证书签署中间证书
openssl x509 -req -in intermediate.csr -CA root.pem -CAkey root-key.pem -CAcreateserial -out intermediate.pem -days 3650
```

这会生成 intermediate.pem 文件，并且使用 root.pem 作为根证书签署它。

### **4. 检查生成的证书**

你可以使用以下命令查看生成的证书内容：

```
openssl x509 -in root.pem -text -noout
openssl x509 -in intermediate.pem -text -noout
```

### **5. 测试证书链**

你可以通过以下命令验证中间证书是否正确链接到根证书：

```
openssl verify -CAfile root.pem intermediate.pem
```

如果一切正常，返回结果应该是 intermediate.pem: OK。

现在，你可以使用 root.pem 和 intermediate.pem 文件进行模拟测试了。

当然可以，下面是一个用于在本地生成 **自签名 TLS 证书和私钥** 的 Bash 脚本，适用于测试 mTLS、Server TLS Policy 和 Client Authentication 等场景。

---

### **📄 脚本名称：**

### **generate-self-signed-cert.sh**

```
#!/bin/bash

set -e

# 默认参数
CERT_DIR="./certs"
DAYS_VALID=365
COMMON_NAME="localhost"

# 创建目录
mkdir -p "${CERT_DIR}"

echo "📁 生成证书目录: ${CERT_DIR}"

# 生成私钥 (2048 位)
openssl genrsa -out "${CERT_DIR}/server.key" 2048
echo "🔐 私钥生成完成: ${CERT_DIR}/server.key"

# 生成自签名证书请求 (CSR)
openssl req -new -key "${CERT_DIR}/server.key" -subj "/CN=${COMMON_NAME}" -out "${CERT_DIR}/server.csr"
echo "📄 证书请求生成完成: ${CERT_DIR}/server.csr"

# 生成自签名证书（有效期默认 365 天）
openssl x509 -req -in "${CERT_DIR}/server.csr" -signkey "${CERT_DIR}/server.key" -days "${DAYS_VALID}" -out "${CERT_DIR}/server.crt"
echo "✅ 自签名证书生成完成: ${CERT_DIR}/server.crt"

# 可选：生成 PEM 格式组合文件（方便某些服务如 nginx 使用）
cat "${CERT_DIR}/server.crt" "${CERT_DIR}/server.key" > "${CERT_DIR}/server.pem"
echo "🔗 PEM 文件生成完成: ${CERT_DIR}/server.pem"

echo ""
echo "📦 所有文件已生成:"
ls -l "${CERT_DIR}"

echo ""
echo "✅ 自签名证书生成完毕，可用于本地测试"
```

---

### **✅ 生成结果目录结构（默认是** 

### **./certs/**

### **）：**

| **文件名** | **说明**                       |
| ---------- | ------------------------------ |
| server.key | 私钥                           |
| server.csr | 证书签名请求（中间文件）       |
| server.crt | 自签名证书                     |
| server.pem | 合并后的 PEM 证书（crt + key） |

---

### **📌 使用方式：**

```
chmod +x generate-self-signed-cert.sh
./generate-self-signed-cert.sh
```

你也可以加参数以后扩展，比如支持输入 SAN（Subject Alternative Name），我可以帮你加。

是否需要我再帮你加上客户端证书（mTLS）那部分？比如生成 CA、客户端私钥和证书等？
