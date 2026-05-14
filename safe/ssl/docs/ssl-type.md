在查看证书内容时，你可以使用 `openssl x509 -in <certificate-file> -noout -text` 命令来获取详细信息。以下是如何根据 `Issuer` 和 `Subject` 字段判断证书类型的具体示例。

### 示例证书内容

假设你有两个证书文件：`cert1.pem` 和 `cert2.pem`。

#### 证书 1（可能是根证书）

```bash
openssl x509 -in cert1.pem -noout -text
```

输出的部分内容可能如下：

```
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:
            01:23:45:67:89:ab:cd:ef:01:23:45:67:89:ab:cd:ef
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=US, O=Example Organization, OU=Example Unit, CN=Example Root CA
        Validity
            Not Before: Jan  1 00:00:00 2022 GMT
            Not After : Jan  1 00:00:00 2032 GMT
        Subject: C=US, O=Example Organization, OU=Example Unit, CN=Example Root CA
        ...
```

#### 证书 2（可能是中间证书）

```bash
openssl x509 -in cert2.pem -noout -text
```

输出的部分内容可能如下：

```
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:
            12:34:56:78:90:ab:cd:ef:12:34:56:78:90:ab:cd:ef
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=US, O=Example Organization, OU=Example Unit, CN=Example Root CA
        Validity
            Not Before: Feb  1 00:00:00 2022 GMT
            Not After : Feb  1 00:00:00 2032 GMT
        Subject: C=US, O=Example Organization, OU=Example Unit, CN=Example Intermediate CA
        ...
```

### 分析

1. **根证书**（Root CA）：
   - `Issuer` 和 `Subject` 字段相同。这表示证书是自签名的，即由自己签发给自己。
   - 上述 `cert1.pem` 的例子中，`Issuer` 和 `Subject` 都是 `C=US, O=Example Organization, OU=Example Unit, CN=Example Root CA`。

2. **中间证书**（Intermediate CA）：
   - `Issuer` 和 `Subject` 字段不同。这表示该证书由另一个 CA 签发，而非自签名。
   - 上述 `cert2.pem` 的例子中，`Issuer` 是 `Example Root CA`，而 `Subject` 是 `Example Intermediate CA`。

通过这些信息，你可以判断出 `cert1.pem` 是根证书，而 `cert2.pem` 是由根证书签发的中间证书。
