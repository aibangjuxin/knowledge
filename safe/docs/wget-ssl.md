- [要获取一个HTTPS网站的证书链，你可以使用以下几种方法：](#要获取一个https网站的证书链你可以使用以下几种方法)
    - [使用 `openssl` 命令行工具](#使用-openssl-命令行工具)
    - [使用 `curl` 工具](#使用-curl-工具)
    - [使用 Web 浏览器](#使用-web-浏览器)
    - [使用在线工具](#使用在线工具)
    - [获取证书链](#获取证书链)
    - [导入证书到Linux系统](#导入证书到linux系统)
    - [证书链中的不同层级](#证书链中的不同层级)
    - [解决证书错误](#解决证书错误)
- [import ssl](#import-ssl)
    - [导入证书链的关键点](#导入证书链的关键点)
    - [实际步骤](#实际步骤)
    - [证书链层级](#证书链层级)
- [keytool -list -keystore](#keytool--list--keystore)
    - [解释 `keytool` 输出的内容](#解释-keytool-输出的内容)
    - [这些信息的意义](#这些信息的意义)
    - [确认首信任的根证书的方法](#确认首信任的根证书的方法)
    - [示例操作](#示例操作)
- [只要确保信任了根证书也就可以了 不需要所有的证书都去信任?不需要确保所有的证书条目必须完全对应](#只要确保信任了根证书也就可以了-不需要所有的证书都去信任不需要确保所有的证书条目必须完全对应)
    - [为什么只需要信任根证书](#为什么只需要信任根证书)
    - [实际操作](#实际操作)
    - [例外情况](#例外情况)

# 要获取一个HTTPS网站的证书链，你可以使用以下几种方法：

### 使用 `openssl` 命令行工具
`openssl` 是一个强大的工具，可以用于处理SSL/TLS和其他加密任务。以下命令可以获取一个网站的证书链：

```bash
openssl s_client -showcerts -connect public-stg.api.gov.sg:443
```

在这个命令中：
- `-showcerts` 参数会显示服务器提供的所有证书（包括中间证书和根证书）。
- `-connect` 参数后跟上服务器地址和端口（HTTPS默认端口是443）。

### 使用 `curl` 工具
`curl` 是一个常用的命令行工具，用于传输数据。你可以使用它来查看证书链信息：

```bash
curl -v --insecure https://public-stg.api.gov.sg/apex/jwt_test/users
```

在这个命令中：
- `-v` 或 `--verbose` 会显示详细的操作，包括证书信息。
- `--insecure` 选项会忽略SSL/TLS证书验证错误（只在需要时使用）。

### 使用 Web 浏览器
大多数现代Web浏览器都允许你查看网站的证书信息，包括证书链：
1. 打开浏览器，访问 `https://public-stg.api.gov.sg/apex/jwt_test/users`。
2. 点击地址栏左侧的锁图标。
3. 查看证书详细信息。通常可以找到服务器证书和中间证书的信息。

### 使用在线工具
有一些在线工具可以帮助你查看网站的证书链。例如：

- **SSL Labs SSL Test**: 输入URL后，可以看到完整的证书链。
- **DigiCert SSL Tools**: 提供详细的证书信息，包括证书链。

这些方法可以帮助你获取目标网站的证书链。使用命令行工具如`openssl`通常是最直接的方法，因为它可以显示完整的证书链和详细的证书信息。

```bash
curl -v --insecure https://public-stg.api.gov.sg/apex/jwt_test/users
 ✔  8940  08:58:30
* Uses proxy env variable https_proxy == 'http://127.0.0.1:59772'
*   Trying 127.0.0.1:59772...
* Connected to 127.0.0.1 (127.0.0.1) port 59772
* CONNECT tunnel: HTTP/1.1 negotiated
* allocate connect buffer
* Establish HTTP proxy tunnel to public-stg.api.gov.sg:443
> CONNECT public-stg.api.gov.sg:443 HTTP/1.1
> Host: public-stg.api.gov.sg:443
> User-Agent: curl/8.7.1
> Proxy-Connection: Keep-Alive
>
< HTTP/1.1 200 Connection established
<
* CONNECT phase completed
* CONNECT tunnel established, response 200
* ALPN: curl offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.2 (IN), TLS handshake, Certificate (11):
* TLSv1.2 (IN), TLS handshake, Server key exchange (12):
* TLSv1.2 (IN), TLS handshake, Server finished (14):
* TLSv1.2 (OUT), TLS handshake, Client key exchange (16):
* TLSv1.2 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.2 (OUT), TLS handshake, Finished (20):
* TLSv1.2 (IN), TLS handshake, Finished (20):
* SSL connection using TLSv1.2 / ECDHE-ECDSA-AES128-GCM-SHA256 / secp256r1 / id-ecPublicKey
* ALPN: server accepted h2
* Server certificate:
*  subject: CN=*.api.gov.sg
*  start date: Jul 22 00:00:00 2024 GMT
*  expire date: Aug 20 23:59:59 2025 GMT
*  issuer: C=US; O=Amazon; CN=Amazon ECDSA 256 M02
*  SSL certificate verify result: unable to get local issuer certificate (20), continuing anyway.
*   Certificate level 0: Public key type EC/prime256v1 (256/128 Bits/secBits), signed using ecdsa-with-SHA256
*   Certificate level 1: Public key type EC/prime256v1 (256/128 Bits/secBits), signed using ecdsa-with-SHA256
*   Certificate level 2: Public key type EC/prime256v1 (256/128 Bits/secBits), signed using sha256WithRSAEncryption
*   Certificate level 3: Public key type RSA (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
* using HTTP/2
* [HTTP/2] [1] OPENED stream for https://public-stg.api.gov.sg/apex/jwt_test/users
* [HTTP/2] [1] [:method: GET]
* [HTTP/2] [1] [:scheme: https]
* [HTTP/2] [1] [:authority: public-stg.api.gov.sg]
* [HTTP/2] [1] [:path: /apex/jwt_test/users]
* [HTTP/2] [1] [user-agent: curl/8.7.1]
* [HTTP/2] [1] [accept: */*]
> GET /apex/jwt_test/users HTTP/2
> Host: public-stg.api.gov.sg
> User-Agent: curl/8.7.1
> Accept: */*
>
* Request completely sent off
< HTTP/2 434
< date: Fri, 26 Jul 2024 00:58:43 GMT
< content-type: application/json
< server:
< x-correlationid: Id-c3f4a26640d65d57c99b7ae5 0
< accept: */*
< host: public-stg.api.gov.sg
< user-agent: curl/8.7.1
< x-amzn-trace-id: Root=1-66a2f4c3-684ce6b00e38c0003083f245
<
{
"code":434,
"transactionID":"Id-c3f4a26640d65d57c99b7ae5"
* Connection #0 to host 127.0.0.1 left intact
}%                                                                          

```

在获取到目标网站的证书链后，你可以将其导入到本地Linux系统中，以便系统可以信任这些证书链中的证书。这通常涉及导入根证书和任何必要的中间证书。以下是详细步骤：

### 获取证书链
使用以下命令获取证书链：

```bash
openssl s_client -showcerts -connect public-stg.api.gov.sg:443 </dev/null 2>/dev/null | openssl x509 -outform PEM > chain.pem

openssl s_client -showcerts -connect public-stg.api.gov.sg:443 </dev/null 2>/dev/null | openssl x509 -outform PEM
 ✔  8941  08:58:43
-----BEGIN CERTIFICATE-----
MIIENzCCA96gAwIBAgIQAxyz8yVw+9NLqzle/DvZ6zAKBggqhkjOPQQDAjA9MQsw
CQYDVQQGEwJVUzEPMA0GA1UEChMGQW1hem9uMR0wGwYDVQQDExRBbWF6b24gRUNE
U0EgMjU2IE0wMjAeFw0yNDA3MjIwMDAwMDBaFw0yNTA4MjAyMzU5NTlaMBcxFTAT
BgNVBAMMDCouYXBpLmdvdi5zZzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABCsI
fZZvAcfTiHjbjK9aWhGDOPljbmnKPzpCA1oc2n9MlI+VSQ6/hl2od1HgMTjHCeQi
wthoifnb95YjLmb3CpKjggLkMIIC4DAfBgNVHSMEGDAWgBS7eJrXaDMynRq7bP2x
NEwB3svQdTAdBgNVHQ4EFgQUk3U3eOmO0uwZkMGdO6dufgErCjowFwYDVR0RBBAw
DoIMKi5hcGkuZ292LnNnMBMGA1UdIAQMMAowCAYGZ4EMAQIBMA4GA1UdDwEB/wQE
AwIDiDAdBgNVHSUEFjAUBggrBgEFBQcDAQYIKwYBBQUHAwIwOwYDVR0fBDQwMjAw
oC6gLIYqaHR0cDovL2NybC5lMm0wMi5hbWF6b250cnVzdC5jb20vZTJtMDIuY3Js
MHUGCCsGAQUFBwEBBGkwZzAtBggrBgEFBQcwAYYhaHR0cDovL29jc3AuZTJtMDIu
YW1hem9udHJ1c3QuY29tMDYGCCsGAQUFBzAChipodHRwOi8vY3J0LmUybTAyLmFt
YXpvbnRydXN0LmNvbS9lMm0wMi5jZXIwDAYDVR0TAQH/BAIwADCCAX0GCisGAQQB
1nkCBAIEggFtBIIBaQFnAHcA3dzKNJXX4RYF55Uy+sef+D0cUN/bADoUEnYKLKy7
yCoAAAGQ2kTuvAAABAMASDBGAiEA7vHX0WYwSev/KCzGeSGmNaMqM4eODowRvvse
h1hxgXwCIQC8NbXKMyWXdSLNo5qvQAXnh2c3PcOJljY0MOgs8t3xcQB1AObSMWNA
d4zBEEEG13G5zsHSQPaWhIb7uocyHf0eN45QAAABkNpE7ogAAAQDAEYwRAIgO1f7
aIremU2ZBzBHPR8rD9u8wToxS4DJSI1zDWOtgVUCIHGoXfxyZ96RKQoM7tUz7h+t
nwHy4C8CEKcp8G73afXRAHUAzPsPaoVxCWX+lZtTzumyfCLphVwNl422qX5UwP5M
DbAAAAGQ2kTvNQAABAMARjBEAiA6tMcxoTD7S6hOqo65N33HJTzlNTolmrqzOLRt
qUlo8AIgA1QDSVV4DDp4oceMn6qdojraHgF8Pbc2qa+ar1N8WqcwCgYIKoZIzj0E
AwIDRwAwRAIgROhiuKXSYr5wv36KqZI7cnWNp2XHZDwAr57D+PMte28CIC1HSiNU
OHOBMHhLAy1qOkuHj1HzO0oQVQMpgapvBuep
-----END CERTIFICATE-----


```

这将会把服务器提供的证书链保存到 `chain.pem` 文件中。

### 导入证书到Linux系统
1. **分割证书链**: 打开 `chain.pem` 文件，你会看到多个 `-----BEGIN CERTIFICATE-----` 到 `-----END CERTIFICATE-----` 的块。这些块分别代表证书链中的每个证书（从服务器证书到根证书）。

2. **识别证书**: 通常，证书链从服务器证书开始，后面是中间证书，最后是根证书。你可以使用以下命令查看每个证书的详细信息，包括其颁发者和使用者：

```bash
   openssl x509 -in <certificate.pem> -text -noout
   cat noout.txt
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number:
            03:1c:b3:f3:25:70:fb:d3:4b:ab:39:5e:fc:3b:d9:eb
        Signature Algorithm: ecdsa-with-SHA256
        Issuer: C=US, O=Amazon, CN=Amazon ECDSA 256 M02
        Validity
            Not Before: Jul 22 00:00:00 2024 GMT
            Not After : Aug 20 23:59:59 2025 GMT
        Subject: CN=*.api.gov.sg
        Subject Public Key Info:
            Public Key Algorithm: id-ecPublicKey
                Public-Key: (256 bit)
                pub:
                    04:2b:08:7d:96:6f:01:c7:d3:88:78:db:8c:af:5a:
                    5a:11:83:38:f9:63:6e:69:ca:3f:3a:42:03:5a:1c:
                    da:7f:4c:94:8f:95:49:0e:bf:86:5d:a8:77:51:e0:
                    31:38:c7:09:e4:22:c2:d8:68:89:f9:db:f7:96:23:
                    2e:66:f7:0a:92
                ASN1 OID: prime256v1
                NIST CURVE: P-256
        X509v3 extensions:
            X509v3 Authority Key Identifier:
                BB:78:9A:D7:68:33:32:9D:1A:BB:6C:FD:B1:34:4C:01:DE:CB:D0:75
            X509v3 Subject Key Identifier:
                93:75:37:78:E9:8E:D2:EC:19:90:C1:9D:3B:A7:6E:7E:01:2B:0A:3A
            X509v3 Subject Alternative Name:
                DNS:*.api.gov.sg
            X509v3 Certificate Policies:
                Policy: 2.23.140.1.2.1
            X509v3 Key Usage: critical
                Digital Signature, Key Agreement
            X509v3 Extended Key Usage:
                TLS Web Server Authentication, TLS Web Client Authentication
            X509v3 CRL Distribution Points:
                Full Name:
                  URI:http://crl.e2m02.amazontrust.com/e2m02.crl
            Authority Information Access:
                OCSP - URI:http://ocsp.e2m02.amazontrust.com
                CA Issuers - URI:http://crt.e2m02.amazontrust.com/e2m02.cer
            X509v3 Basic Constraints: critical
                CA:FALSE
            CT Precertificate SCTs:
                Signed Certificate Timestamp:
                    Version   : v1 (0x0)
                    Log ID    : DD:DC:CA:34:95:D7:E1:16:05:E7:95:32:FA:C7:9F:F8:
                                3D:1C:50:DF:DB:00:3A:14:12:76:0A:2C:AC:BB:C8:2A
                    Timestamp : Jul 22 11:47:49.052 2024 GMT
                    Extensions: none
                    Signature : ecdsa-with-SHA256
                                30:46:02:21:00:EE:F1:D7:D1:66:30:49:EB:FF:28:2C:
                                C6:79:21:A6:35:A3:2A:33:87:8E:0E:8C:11:BE:FB:1E:
                                87:58:71:81:7C:02:21:00:BC:35:B5:CA:33:25:97:75:
                                22:CD:A3:9A:AF:40:05:E7:87:67:37:3D:C3:89:96:36:
                                34:30:E8:2C:F2:DD:F1:71
                Signed Certificate Timestamp:
                    Version   : v1 (0x0)
                    Log ID    : E6:D2:31:63:40:77:8C:C1:10:41:06:D7:71:B9:CE:C1:
                                D2:40:F6:96:84:86:FB:BA:87:32:1D:FD:1E:37:8E:50
                    Timestamp : Jul 22 11:47:49.000 2024 GMT
                    Extensions: none
                    Signature : ecdsa-with-SHA256
                                30:44:02:20:3B:57:FB:68:8A:DE:99:4D:99:07:30:47:
                                3D:1F:2B:0F:DB:BC:C1:3A:31:4B:80:C9:48:8D:73:0D:
                                63:AD:81:55:02:20:71:A8:5D:FC:72:67:DE:91:29:0A:
                                0C:EE:D5:33:EE:1F:AD:9F:01:F2:E0:2F:02:10:A7:29:
                                F0:6E:F7:69:F5:D1
                Signed Certificate Timestamp:
                    Version   : v1 (0x0)
                    Log ID    : CC:FB:0F:6A:85:71:09:65:FE:95:9B:53:CE:E9:B2:7C:
                                22:E9:85:5C:0D:97:8D:B6:A9:7E:54:C0:FE:4C:0D:B0
                    Timestamp : Jul 22 11:47:49.173 2024 GMT
                    Extensions: none
                    Signature : ecdsa-with-SHA256
                                30:44:02:20:3A:B4:C7:31:A1:30:FB:4B:A8:4E:AA:8E:
                                B9:37:7D:C7:25:3C:E5:35:3A:25:9A:BA:B3:38:B4:6D:
                                A9:49:68:F0:02:20:03:54:03:49:55:78:0C:3A:78:A1:
                                C7:8C:9F:AA:9D:A2:3A:DA:1E:01:7C:3D:B7:36:A9:AF:
                                9A:AF:53:7C:5A:A7
    Signature Algorithm: ecdsa-with-SHA256
    Signature Value:
        30:44:02:20:44:e8:62:b8:a5:d2:62:be:70:bf:7e:8a:a9:92:
        3b:72:75:8d:a7:65:c7:64:3c:00:af:9e:c3:f8:f3:2d:7b:6f:
        02:20:2d:47:4a:23:54:38:73:81:30:78:4b:03:2d:6a:3a:4b:
        87:8f:51:f3:3b:4a:10:55:03:29:81:aa:6f:06:e7:a9
```

3. **导入证书**:
   - **根证书**: 如果证书链中包含的根证书不在系统的信任存储中，则需要将它添加到系统的受信任根证书存储。通常将证书放到 `/usr/local/share/ca-certificates/` 目录下，然后使用 `update-ca-certificates` 命令更新系统的证书存储。

   - **中间证书**: 将中间证书放在适当的位置，确保它们可以被应用程序找到。这可能需要配置应用程序使用这些中间证书，或者将它们合并到特定的信任存储中。

例如，假设 `root-cert.pem` 是根证书，`intermediate-cert.pem` 是中间证书，以下步骤将这些证书导入到Ubuntu系统：

```bash
sudo cp root-cert.pem /usr/local/share/ca-certificates/root-cert.crt
sudo update-ca-certificates
```

对于其他发行版，可能需要手动将证书复制到特定目录，并更新系统的证书存储。

### 证书链中的不同层级
你提供的输出中提到的“证书级别”是指证书链中各个证书的顺序和它们的签名类型。这些层级包括：

- **证书级别 0**: 服务器证书，由目标网站提供。
- **证书级别 1**: 中间证书，可能是由中间CA签署的，用于桥接根证书和服务器证书。
- **证书级别 2**: 另一层中间证书。
- **证书级别 3**: 根证书，由根CA颁发。

### 解决证书错误
在证书链中，各级别证书都应该被正确地验证。如果遇到错误如 `unable to get local issuer certificate`，这意味着系统无法验证某个证书的签名，通常是因为缺少正确的中间证书或根证书。

要解决这个问题：
1. **确保所有中间证书和根证书都被导入**。
2. **确认系统的证书存储已更新**，并重新启动相关服务（如网络服务或浏览器）。



# import ssl 

证书链中的层级是不是我不需要关心,我只需要确保命令openssl s_client -showcerts -connect public-stg.api.gov.sg:443 </dev/null 2>/dev/null | openssl x509 -outform PEM > chain.pem
的结果导入到我的请求客户端就可以了

在大多数情况下，确实不需要过多关心证书链中的具体层级。你只需要确保导入完整的证书链，以便你的客户端能够验证目标服务器的身份。这包括所有必要的中间证书和根证书，特别是当这些证书不在你的客户端系统的默认信任存储中时。

### 导入证书链的关键点
1. **完整性**: 确保导入的证书链包含从服务器证书到根证书的所有必要证书。通常，服务器会发送服务器证书和相关的中间证书，但根证书可能需要手动导入。
2. **信任链**: 客户端需要能够信任整个证书链，这意味着你需要导入链中的所有中间证书和根证书。
3. **系统或应用程序信任存储**: 确保导入的证书链在正确的位置，这样系统或特定应用程序才能使用这些证书来验证服务器的身份。

### 实际步骤
- **获取证书链**: 使用`openssl s_client -showcerts -connect public-stg.api.gov.sg:443`命令获取完整的证书链，并将其保存到`chain.pem`文件中。
- **导入到客户端**: 将`chain.pem`文件中的证书导入到客户端的信任存储中。具体操作取决于你的客户端系统或应用程序。

例如：
- 在Linux系统中，你可以将证书文件复制到`/usr/local/share/ca-certificates/`目录，然后运行`update-ca-certificates`来更新信任存储。
- 在Java应用程序中，你可能需要将证书导入到Java的`cacerts`文件中，通常使用`keytool`命令。

### 证书链层级
虽然通常不需要深入理解证书链的每个层级，了解它们还是有帮助的：
- **服务器证书**: 由服务器提供，证明服务器的身份。
- **中间证书**: 由中间CA颁发，用于链接服务器证书和根证书。
- **根证书**: 最上层的证书，由根CA颁发，是信任链的基础。

只要你确保了完整的证书链被正确导入并信任，你的客户端就可以验证目标服务器的SSL/TLS连接。

# keytool -list -keystore 
我没太理解我通过keytool导入到我的java客户端中查看到如下信息
keytool -list -keystore /opt/zulu-jre/lib/security/cacerts
比如amazonrootca1 [jdk] ,May 21,2015 trustedCertEntry 
Certificate fingerprint ****
amazonrootca2
amazonrootca3
amazonrootca4
类似这样的信息是什么意思?其具体代表了什么?


`keytool` 是一个用于管理 Java 密钥库（keystore）和信任库（truststore）的工具。在 Java 环境中，`cacerts` 是一个默认的信任库文件，包含了一系列受信任的根证书。这些根证书用来验证与之建立 SSL/TLS 连接的服务器的身份。

### 解释 `keytool` 输出的内容
当你使用 `keytool -list -keystore /opt/zulu-jre/lib/security/cacerts` 查看 `cacerts` 文件的内容时，你会看到每个受信任的证书条目的信息。这些条目通常包括证书的别名（alias）、创建日期、证书类型以及指纹等信息。

例如：
```
amazonrootca1 [jdk], May 21, 2015, trustedCertEntry,
Certificate fingerprint (SHA1): XX:XX:XX:...
```

**解释这些字段：**
1. **别名 (Alias)**: 
   - `amazonrootca1` 是这个证书在信任库中的别名。这个名称通常描述了证书的用途或颁发者。
   - 别名是唯一的，用于在信任库中标识每个证书。

2. **来源 (Source)**:
   - `[jdk]` 表示这是 Java 发行版自带的证书。JDK（Java Development Kit）包含了一些默认的受信任的根证书。

3. **创建日期**:
   - `May 21, 2015` 表示这个证书条目在信任库中的创建日期，不一定是证书的颁发日期。

4. **条目类型 (Entry Type)**:
   - `trustedCertEntry` 表示这是一个受信任的证书条目。其他类型可能包括 `privateKeyEntry`（用于私钥和对应的证书链）。

5. **证书指纹 (Certificate Fingerprint)**:
   - 这是证书的摘要（hash），用于唯一标识证书。常见的摘要算法包括 SHA-1 和 SHA-256。指纹用于快速比较和验证证书的完整性。

### 这些信息的意义
这些条目表示信任库中包含的所有受信任的根证书。当 Java 应用程序试图与使用 SSL/TLS 的服务器建立连接时，它会检查服务器提供的证书是否由信任库中的任一根证书所信任。如果服务器的证书链能够追溯到信任库中的一个根证书，连接就被认为是安全的。

在你的示例中，`amazonrootca1`, `amazonrootca2`, 等等，表示亚马逊的根证书，这些根证书被你的 Java 信任库所信任。因此，如果你的 Java 应用程序连接到一个由这些根证书签署的服务器，连接就可以被信任。



在信任库（truststore）中，每个证书条目通常代表一个受信任的根证书或中间证书。在 `keytool` 列表中，无法直接看到哪些证书条目是用于哪个域名或服务器的首信任证书，因为信任库中的根证书用于验证多个可能的证书链。

### 确认首信任的根证书的方法
要确认某个域名（或服务器）使用的是哪个根证书，通常需要检查该服务器的证书链，并在信任库中找到匹配的根证书。以下是几种确认方法：

1. **查看服务器的完整证书链**:
   - 使用工具（如 `openssl`）检查目标服务器的证书链，确定链中的根证书。
   - 例如，使用以下命令获取服务器的证书链：
```bash
     openssl s_client -connect example.com:443 -showcerts
     openssl s_client -connect public-stg.api.gov.sg:443 -showcerts
     openssl s_client -connect public-stg.api.gov.sg:443 -showcerts
Connecting to 3.1.111.235
CONNECTED(00000006)
depth=2 C=US, O=Amazon, CN=Amazon Root CA 3
verify return:1
depth=1 C=US, O=Amazon, CN=Amazon ECDSA 256 M02
verify return:1
depth=0 CN=*.api.gov.sg
verify return:1
---
Certificate chain
 0 s:CN=*.api.gov.sg
   i:C=US, O=Amazon, CN=Amazon ECDSA 256 M02
   a:PKEY: id-ecPublicKey, 256 (bit); sigalg: ecdsa-with-SHA256
   v:NotBefore: Jul 22 00:00:00 2024 GMT; NotAfter: Aug 20 23:59:59 2025 GMT
-----BEGIN CERTIFICATE-----
MIIENzCCA96gAwIBAgIQAxyz8yVw+9NLqzle/DvZ6zAKBggqhkjOPQQDAjA9MQsw
CQYDVQQGEwJVUzEPMA0GA1UEChMGQW1hem9uMR0wGwYDVQQDExRBbWF6b24gRUNE
U0EgMjU2IE0wMjAeFw0yNDA3MjIwMDAwMDBaFw0yNTA4MjAyMzU5NTlaMBcxFTAT
BgNVBAMMDCouYXBpLmdvdi5zZzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABCsI
fZZvAcfTiHjbjK9aWhGDOPljbmnKPzpCA1oc2n9MlI+VSQ6/hl2od1HgMTjHCeQi
wthoifnb95YjLmb3CpKjggLkMIIC4DAfBgNVHSMEGDAWgBS7eJrXaDMynRq7bP2x
NEwB3svQdTAdBgNVHQ4EFgQUk3U3eOmO0uwZkMGdO6dufgErCjowFwYDVR0RBBAw
DoIMKi5hcGkuZ292LnNnMBMGA1UdIAQMMAowCAYGZ4EMAQIBMA4GA1UdDwEB/wQE
AwIDiDAdBgNVHSUEFjAUBggrBgEFBQcDAQYIKwYBBQUHAwIwOwYDVR0fBDQwMjAw
oC6gLIYqaHR0cDovL2NybC5lMm0wMi5hbWF6b250cnVzdC5jb20vZTJtMDIuY3Js
MHUGCCsGAQUFBwEBBGkwZzAtBggrBgEFBQcwAYYhaHR0cDovL29jc3AuZTJtMDIu
YW1hem9udHJ1c3QuY29tMDYGCCsGAQUFBzAChipodHRwOi8vY3J0LmUybTAyLmFt
YXpvbnRydXN0LmNvbS9lMm0wMi5jZXIwDAYDVR0TAQH/BAIwADCCAX0GCisGAQQB
1nkCBAIEggFtBIIBaQFnAHcA3dzKNJXX4RYF55Uy+sef+D0cUN/bADoUEnYKLKy7
yCoAAAGQ2kTuvAAABAMASDBGAiEA7vHX0WYwSev/KCzGeSGmNaMqM4eODowRvvse
h1hxgXwCIQC8NbXKMyWXdSLNo5qvQAXnh2c3PcOJljY0MOgs8t3xcQB1AObSMWNA
d4zBEEEG13G5zsHSQPaWhIb7uocyHf0eN45QAAABkNpE7ogAAAQDAEYwRAIgO1f7
aIremU2ZBzBHPR8rD9u8wToxS4DJSI1zDWOtgVUCIHGoXfxyZ96RKQoM7tUz7h+t
nwHy4C8CEKcp8G73afXRAHUAzPsPaoVxCWX+lZtTzumyfCLphVwNl422qX5UwP5M
DbAAAAGQ2kTvNQAABAMARjBEAiA6tMcxoTD7S6hOqo65N33HJTzlNTolmrqzOLRt
qUlo8AIgA1QDSVV4DDp4oceMn6qdojraHgF8Pbc2qa+ar1N8WqcwCgYIKoZIzj0E
AwIDRwAwRAIgROhiuKXSYr5wv36KqZI7cnWNp2XHZDwAr57D+PMte28CIC1HSiNU
OHOBMHhLAy1qOkuHj1HzO0oQVQMpgapvBuep
-----END CERTIFICATE-----
 1 s:C=US, O=Amazon, CN=Amazon ECDSA 256 M02
   i:C=US, O=Amazon, CN=Amazon Root CA 3
   a:PKEY: id-ecPublicKey, 256 (bit); sigalg: ecdsa-with-SHA256
   v:NotBefore: Aug 23 22:33:24 2022 GMT; NotAfter: Aug 23 22:33:24 2030 GMT
-----BEGIN CERTIFICATE-----
MIIC1DCCAnmgAwIBAgITB3MSbeLC+v0sR62IsVZuAYIEbTAKBggqhkjOPQQDAjA5
MQswCQYDVQQGEwJVUzEPMA0GA1UEChMGQW1hem9uMRkwFwYDVQQDExBBbWF6b24g
Um9vdCBDQSAzMB4XDTIyMDgyMzIyMzMyNFoXDTMwMDgyMzIyMzMyNFowPTELMAkG
A1UEBhMCVVMxDzANBgNVBAoTBkFtYXpvbjEdMBsGA1UEAxMUQW1hem9uIEVDRFNB
IDI1NiBNMDIwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAS9vQLD4W/Kg4AnFRl8
x/FUbLqtd5ICYjUijGsytF9hmgb/Dyk+Ebt4cw6rAlGbaiOLapSJKZiZr+UQdh3I
QOr+o4IBWjCCAVYwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYw
HQYDVR0lBBYwFAYIKwYBBQUHAwEGCCsGAQUFBwMCMB0GA1UdDgQWBBS7eJrXaDMy
nRq7bP2xNEwB3svQdTAfBgNVHSMEGDAWgBSrttvXBp43rDCGB5Fwx5zEGbF4wDB7
BggrBgEFBQcBAQRvMG0wLwYIKwYBBQUHMAGGI2h0dHA6Ly9vY3NwLnJvb3RjYTMu
YW1hem9udHJ1c3QuY29tMDoGCCsGAQUFBzAChi5odHRwOi8vY3J0LnJvb3RjYTMu
YW1hem9udHJ1c3QuY29tL3Jvb3RjYTMuY2VyMD8GA1UdHwQ4MDYwNKAyoDCGLmh0
dHA6Ly9jcmwucm9vdGNhMy5hbWF6b250cnVzdC5jb20vcm9vdGNhMy5jcmwwEwYD
VR0gBAwwCjAIBgZngQwBAgEwCgYIKoZIzj0EAwIDSQAwRgIhAKSYEcDcp3kcPMzh
OIYDWZOLu4InPod4fQhRTmc2zBAgAiEAmwdGE4AuNWhw9N8REhf82rJLNm7h9Myg
TsR9Wu0bQYU=
-----END CERTIFICATE-----
 2 s:C=US, O=Amazon, CN=Amazon Root CA 3
   i:C=US, ST=Arizona, L=Scottsdale, O=Starfield Technologies, Inc., CN=Starfield Services Root Certificate Authority - G2
   a:PKEY: id-ecPublicKey, 256 (bit); sigalg: RSA-SHA256
   v:NotBefore: May 25 12:00:00 2015 GMT; NotAfter: Dec 31 01:00:00 2037 GMT
-----BEGIN CERTIFICATE-----
MIIDxzCCAq+gAwIBAgITBn+USjDPzE90tfUwblTTt74KwzANBgkqhkiG9w0BAQsF
ADCBmDELMAkGA1UEBhMCVVMxEDAOBgNVBAgTB0FyaXpvbmExEzARBgNVBAcTClNj
b3R0c2RhbGUxJTAjBgNVBAoTHFN0YXJmaWVsZCBUZWNobm9sb2dpZXMsIEluYy4x
OzA5BgNVBAMTMlN0YXJmaWVsZCBTZXJ2aWNlcyBSb290IENlcnRpZmljYXRlIEF1
dGhvcml0eSAtIEcyMB4XDTE1MDUyNTEyMDAwMFoXDTM3MTIzMTAxMDAwMFowOTEL
MAkGA1UEBhMCVVMxDzANBgNVBAoTBkFtYXpvbjEZMBcGA1UEAxMQQW1hem9uIFJv
b3QgQ0EgMzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABCmXp8ZBf8ANm+gBG1bG
8lKlui2yEujSLtf6ycXYqm0fc4E7O5hrOXwzpcVOho6AF2hiRVd9RFgdszflZwjr
Zt6jggExMIIBLTAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNV
HQ4EFgQUq7bb1waeN6wwhgeRcMecxBmxeMAwHwYDVR0jBBgwFoAUnF8A36oB1zAr
OIiiuG1KnPIRkYMweAYIKwYBBQUHAQEEbDBqMC4GCCsGAQUFBzABhiJodHRwOi8v
b2NzcC5yb290ZzIuYW1hem9udHJ1c3QuY29tMDgGCCsGAQUFBzAChixodHRwOi8v
Y3J0LnJvb3RnMi5hbWF6b250cnVzdC5jb20vcm9vdGcyLmNlcjA9BgNVHR8ENjA0
MDKgMKAuhixodHRwOi8vY3JsLnJvb3RnMi5hbWF6b250cnVzdC5jb20vcm9vdGcy
LmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQELBQADggEBAG5Z+hfC
ycAuzqKJ4ClKK5VZUqjH4jYSzu3UVOLvHzoYk0rIVqFjjBJwa/L5MreP219CIdIX
di3s9at8ZZR+tKsD4T02ZqO/43FQqnSkzF/G+OxYo3malxhuT9j7bNiA9WkCuqVV
bUncQt79aEjDKht7viKQnoybiHB6dtWAXMNObcCviQMqTcoV+sQOpKJMvQanxUk+
fKQLGKlkpu9zKNr2kWdx874JVpYhDCUzW2RX9TtQ04VT6J0xTEew55OJj02jNxHu
Gijg0YLZtWLNWEXkNDkVpZozXbhuTM6GJKhwLn2rmgRgtFTWUDbeq3YE/7NHu+3a
LOL51JEnEI+4hac=
-----END CERTIFICATE-----
 3 s:C=US, ST=Arizona, L=Scottsdale, O=Starfield Technologies, Inc., CN=Starfield Services Root Certificate Authority - G2
   i:C=US, O=Starfield Technologies, Inc., OU=Starfield Class 2 Certification Authority
   a:PKEY: rsaEncryption, 2048 (bit); sigalg: RSA-SHA256
   v:NotBefore: Sep  2 00:00:00 2009 GMT; NotAfter: Jun 28 17:39:16 2034 GMT
-----BEGIN CERTIFICATE-----
MIIEdTCCA12gAwIBAgIJAKcOSkw0grd/MA0GCSqGSIb3DQEBCwUAMGgxCzAJBgNV
BAYTAlVTMSUwIwYDVQQKExxTdGFyZmllbGQgVGVjaG5vbG9naWVzLCBJbmMuMTIw
MAYDVQQLEylTdGFyZmllbGQgQ2xhc3MgMiBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0
eTAeFw0wOTA5MDIwMDAwMDBaFw0zNDA2MjgxNzM5MTZaMIGYMQswCQYDVQQGEwJV
UzEQMA4GA1UECBMHQXJpem9uYTETMBEGA1UEBxMKU2NvdHRzZGFsZTElMCMGA1UE
ChMcU3RhcmZpZWxkIFRlY2hub2xvZ2llcywgSW5jLjE7MDkGA1UEAxMyU3RhcmZp
ZWxkIFNlcnZpY2VzIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IC0gRzIwggEi
MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDVDDrEKvlO4vW+GZdfjohTsR8/
y8+fIBNtKTrID30892t2OGPZNmCom15cAICyL1l/9of5JUOG52kbUpqQ4XHj2C0N
Tm/2yEnZtvMaVq4rtnQU68/7JuMauh2WLmo7WJSJR1b/JaCTcFOD2oR0FMNnngRo
Ot+OQFodSk7PQ5E751bWAHDLUu57fa4657wx+UX2wmDPE1kCK4DMNEffud6QZW0C
zyyRpqbn3oUYSXxmTqM6bam17jQuug0DuDPfR+uxa40l2ZvOgdFFRjKWcIfeAg5J
Q4W2bHO7ZOphQazJ1FTfhy/HIrImzJ9ZVGif/L4qL8RVHHVAYBeFAlU5i38FAgMB
AAGjgfAwge0wDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAYYwHQYDVR0O
BBYEFJxfAN+qAdcwKziIorhtSpzyEZGDMB8GA1UdIwQYMBaAFL9ft9HO3R+G9FtV
rNzXEMIOqYjnME8GCCsGAQUFBwEBBEMwQTAcBggrBgEFBQcwAYYQaHR0cDovL28u
c3MyLnVzLzAhBggrBgEFBQcwAoYVaHR0cDovL3guc3MyLnVzL3guY2VyMCYGA1Ud
HwQfMB0wG6AZoBeGFWh0dHA6Ly9zLnNzMi51cy9yLmNybDARBgNVHSAECjAIMAYG
BFUdIAAwDQYJKoZIhvcNAQELBQADggEBACMd44pXyn3pF3lM8R5V/cxTbj5HD9/G
VfKyBDbtgB9TxF00KGu+x1X8Z+rLP3+QsjPNG1gQggL4+C/1E2DUBc7xgQjB3ad1
l08YuW3e95ORCLp+QCztweq7dp4zBncdDQh/U90bZKuCJ/Fp1U1ervShw3WnWEQt
8jxwmKy6abaVd38PMV4s/KCHOkdp8Hlf9BRUpJVeEXgSYCfOn8J3/yNTd126/+pZ
59vPr5KW7ySaNRB6nJHGDn2Z9j8Z3/VyVOEVqQdZe4O/Ui5GjLIAZHYcSNPYeehu
VsyuLAOQ1xk4meTKCRlb/weWsKh/NEnfVqn3sF/tM+2MR7cwA130A4w=
-----END CERTIFICATE-----
---
Server certificate
subject=CN=*.api.gov.sg
issuer=C=US, O=Amazon, CN=Amazon ECDSA 256 M02
---
No client certificate CA names sent
Peer signing digest: SHA256
Peer signature type: ECDSA
Server Temp Key: ECDH, prime256v1, 256 bits
---
SSL handshake has read 4388 bytes and written 455 bytes
Verification: OK
---
New, TLSv1.2, Cipher is ECDHE-ECDSA-AES128-GCM-SHA256
Server public key is 256 bit
Secure Renegotiation IS supported
Compression: NONE
Expansion: NONE
No ALPN negotiated
SSL-Session:
    Protocol  : TLSv1.2
    Cipher    : ECDHE-ECDSA-AES128-GCM-SHA256
    Session-ID: 186556AAD65F19E98B8CBF892C4C8DB0E3A35C3C8A6665301AE0DC00B2D9139C
    Session-ID-ctx:
    Master-Key: 6BCDCB9A62A758996697456965398764164D88E632E9353F8B52C5B19AD059039712FB94CE05917B1CDBF8BD66D0307E
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 86400 (seconds)
    TLS session ticket:
    0000 - b8 89 fd f4 86 c9 47 01-2b 4f 32 df 65 82 2b 56   ......G.+O2.e.+V
    0010 - 98 84 1d b5 1a 7c fc 3a-a7 6a 98 d9 2a a2 80 53   .....|.:.j..*..S
    0020 - 62 54 9c 97 cb 7d 2f 68-d6 f4 77 f6 e1 12 7b a6   bT...}/h..w...{.
    0030 - 67 3b 87 14 2f 04 77 97-ba fe 88 b8 57 41 94 34   g;../.w.....WA.4
    0040 - ea 44 a6 5d 6a cd d5 5f-01 2b 81 72 da 5e b9 47   .D.]j.._.+.r.^.G
    0050 - 44 fd ae f6 03 24 ba cd-47 03 dc 38 1b c6 b7 69   D....$..G..8...i
    0060 - 73 74 08 a0 13 03 6c 04-0a                        st....l..

    Start Time: 1721956740
    Timeout   : 7200 (sec)
    Verify return code: 0 (ok)
    Extended master secret: yes

```
   - 在输出中找到最上层的根证书。

2. **检查证书指纹**:
   - 从 `openssl` 或其他工具中获取到的根证书的指纹与信任库中的证书条目进行比较。
   - 使用 `keytool -list -v -alias <alias> -keystore <keystore>` 命令查看信任库中某个证书的详细信息，包括指纹。例如：
     ```
     keytool -list -v -alias amazonrootca1 -keystore /opt/zulu-jre/lib/security/cacerts
     ```

3. **验证根证书**:
   - 根据步骤1获取的根证书，查找信任库中相同指纹的条目。指纹（通常是SHA-1或SHA-256）是唯一的，可以唯一确定某个证书。

通过上述步骤，确认某个域名的SSL/TLS连接所使用的根证书是否在你的信任库中。如果该根证书在你的信任库中，则表示该连接是受信任的。

### 示例操作
1. **获取服务器证书链**:
   ```
   openssl s_client -connect example.com:443 -showcerts
   ```

2. **获取根证书指纹**:
   记录最上层证书的指纹（SHA-1或SHA-256）。

3. **在信任库中查找指纹**:
   ```
   keytool -list -v -keystore /opt/zulu-jre/lib/security/cacerts
   ```
   或者：
   ```
   keytool -list -v -alias amazonrootca1 -keystore /opt/zulu-jre/lib/security/cacerts
   ```

通过这些步骤，你可以确定某个域名的连接使用的根证书是否在信任库中，以及哪个证书条目对应于该连接的首信任证书。



# 只要确保信任了根证书也就可以了 不需要所有的证书都去信任?不需要确保所有的证书条目必须完全对应

是的，通常你只需要确保信任链的根证书在你的信任库中就可以了。根证书是信任链的起点，所有的中间证书和服务器证书都需要通过这条链向上追溯到受信任的根证书。因此，根证书的信任是关键。

### 为什么只需要信任根证书
1. **信任链的验证**:
   - 当客户端验证服务器证书时，它会沿着证书链向上检查每个证书的签名，直到找到一个受信任的根证书。
   - 如果根证书是受信任的，且证书链是完整和有效的，那么整个连接就是受信任的。

2. **中间证书的自动信任**:
   - 中间证书通常由服务器在SSL/TLS握手过程中提供，或者可以在需要时从中间CA下载。只要根证书是受信任的，客户端就会信任由其签发的中间证书。

### 实际操作
- **只导入根证书**: 通常，只需要将根证书导入到客户端的信任库中。这些根证书可以从证书颁发机构（CA）的网站获取，或通过其他安全途径获取。
- **不必导入中间证书和服务器证书**: 这些证书通常由服务器在建立连接时提供，客户端只需验证这些证书是否由已信任的根证书签署即可。

### 例外情况
- **某些情况下可能需要手动添加中间证书**:
  - 如果服务器配置不完整，未能提供必要的中间证书，客户端可能会无法验证整个证书链。在这种情况下，可能需要手动导入缺失的中间证书。
  - 一些企业环境中，为了更细粒度的控制或特殊的安全需求，可能会选择信任特定的中间证书而不是所有由根证书签署的证书。

在大多数情况下，只要你的客户端信任根证书，便足以验证从该根证书链到目标服务器的任何连接的安全性。


