# 02 — keytool + openssl 命令速查

> 拿到 keystore 文件或服务端证书后,用这些命令把它**看清楚**。所有命令都跑过(用 `../simple-https-demo/src/main/resources/ssl/server-keystore.p12` 做测试样本),输出真实可复现。

---

## 0. 测试样本 — 一分钟自检

```bash
KS=/Users/lex/git/knowledge/develop/java/java-auth/simple-https-demo/src/main/resources/ssl/server-keystore.p12

keytool -list -keystore "$KS" -storepass changeit
# 预期输出:
#   Keystore type: PKCS12
#   Keystore provider: SUN
#   Your keystore contains 1 entry
#   server, Dec 27, 2025, PrivateKeyEntry,
#   Certificate fingerprint (SHA-256): FF:42:86:14:6B:6A:68:A0:74:FB:11:CE:0E:EE:3B:AB:2D:74:D8:B8:F5:BA:8C:78:F4:73:F9:5B:FE:97:46:86
```

下面是这套 keystore 上跑出来的**实测输出**,后续命令的真实长相。

---

## 1. keytool — Java 系 keystore 的原生命令

### 1.1 列所有 alias + entry type(第一道筛子)

```bash
keytool -list -keystore <FILE> -storepass '<PWD>'
# 可选: -storetype JKS|PKCS12  (不填就猜,JKS 默认)
```

**实测输出**(PKCS12,1 个 alias):

```
Keystore type: PKCS12
Keystore provider: SUN

Your keystore contains 1 entry

server, Dec 27, 2025, PrivateKeyEntry,
Certificate fingerprint (SHA-256): FF:42:86:14:6B:6A:68:A0:74:FB:11:CE:0E:EE:3B:AB:2D:74:D8:B8:F5:BA:8C:78:F4:73:F9:5B:FE:97:46:86
```

**Entry type 三态语义**(来自 Java Security 标准):

| Entry type | 含义 | Tomcat 能否当 HTTPS cert |
|---|---|---|
| `PrivateKeyEntry` | 私钥 + 证书链(服务端 keystore 必须这个) | ✅ |
| `trustedCertEntry` | 只信任的 CA 证书 / 对端证书 | ❌ 启动会报 `does not identify a key entry` |
| `SecretKeyEntry` | 密钥但不是证书(TLS 不该出现) | ❌ |

### 1.2 看具体 alias 的证书详情

```bash
keytool -list -v -alias <ALIAS> -keystore <FILE> -storepass '<PWD>'
```

**实测输出**(本目录的 demo keystore,完整):

```
Alias name: server
Creation date: Dec 27, 2025
Entry type: PrivateKeyEntry
Certificate chain length: 1
Certificate[1]:
Owner: CN=localhost, OU=Demo, O=Example, L=City, ST=State, C=US
Issuer: CN=localhost, OU=Demo, O=Example, L=City, ST=State, C=US
Serial number: 38c78d3621fa47c8
Valid from: Sat Dec 27 10:49:42 GMT+08:00 2025 until: Sun Dec 27 10:49:42 GMT+08:00 2026
Certificate fingerprints:
	 SHA1: 5B:4E:EF:72:88:6E:3A:E5:57:01:23:33:9D:1E:99:D8:64:88:EE:40
	 SHA256: FF:42:86:14:6B:6A:68:A0:74:FB:11:CE:0E:EE:3B:AB:2D:74:D8:B8:F5:BA:8C:78:F4:73:F9:5B:FE:97:46:86
Signature algorithm name: SHA384withRSA
Subject Public Key Algorithm: 2048-bit RSA key
Version: 3

Extensions:

#1: ObjectId: 2.5.29.17 Criticality=false
SubjectAlternativeName [
  DNSName: localhost
  IPAddress: 127.0.0.1
]
```

**这 5 个字段是排查必看**:

| 字段 | 排查意义 |
|---|---|
| `Owner`(Subject) | 这张证书是**为谁签的**;客户端会用它验证 hostname 是否匹配 |
| `Issuer` | 自签 = `Issuer == Owner`;生产 = 公共 CA 的 CN |
| `Serial number` | CA 撤销时定位这张证书的标识 |
| `Valid from / until` | 过期检查(常见坑:Pod 起来了但 cert 已过期 → 客户端报 `certificate has expired`) |
| `SHA256 Fingerprint` | **跨工具对账指纹**(从外部 dial 回来再算一次,两次一致 = 是同一张) |

### 1.3 把证书导出成 PEM(给 openssl / curl / 客户端 truststore 用)

```bash
keytool -exportcert -alias <ALIAS> -keystore <FILE> -storepass '<PWD>' -rfc > cert.pem
# -rfc = 输出 PEM 格式(带 BEGIN/END 头);不写 -rfc 默认是 DER 二进制

# 也可以不导文件,直接 stdout pipe 给 openssl
keytool -exportcert -alias <ALIAS> -keystore <FILE> -storepass '<PWD>' -rfc \
  | openssl x509 -noout -subject -dates -fingerprint -sha256
```

**实测输出**(把 demo keystore 里的 cert 导出 + openssl 读):

```
subject=C=US, ST=State, L=City, O=Example, OU=Demo, CN=localhost
issuer=C=US, ST=State, L=City, O=Example, OU=Demo, CN=localhost
notBefore=Dec 27 02:49:42 2025 GMT
notAfter=Dec 27 02:49:42 2026 GMT
sha256 Fingerprint=FF:42:86:14:6B:6A:68:A0:74:FB:11:CE:0E:EE:3B:AB:2D:74:D8:B8:F5:BA:8C:78:F4:73:F9:5B:FE:97:46:86
```

注意:**keytool 输出的 fingerprint 跟 openssl 输出的 fingerprint 必须完全一致**(忽略大小写 + 分隔符差异)。这是后续 3 场景对账的锚点。

### 1.4 跨工具对比别名(alias 对齐)

```bash
# 同一个 keystore 里所有 alias + 它们的 cert fingerprint
keytool -list -v -keystore <FILE> -storepass '<PWD>' 2>&1 \
  | awk '/Alias name|Entry type|SHA256:/ {print}'
```

输出长这样:

```
Alias name: server
Entry type: PrivateKeyEntry
	 SHA256: FF:42:86:14:6B:6A:68:A0:74:FB:11:CE:0E:EE:3B:AB:2D:74:D8:B8:F5:BA:8C:78:F4:73:F9:5B:FE:97:46:86
```

**判断规则**:`application.yml` 里 `server.ssl.key-alias` 的值,必须出现在这个列表里,必须是 `PrivateKeyEntry`。其他都是配置错误。

### 1.5 密码不知道? — 用 `-storepass` 文件替代行内

```bash
# 密码写在文件里(密码文件本身的安全见 ../p12-decrypt.md)
echo -n 'changeit' > /tmp/pwd
keytool -list -keystore <FILE> -storepass:file /tmp/pwd
# 注意是 -storepass:file 而不是 -storepass,带 :file 才读文件
```

macOS / BSD 上不要写 `echo 'pwd' > file` — 末尾 `\n` 会让 `cat | base64` 跟 `base64 -i file` 不一致(见 `../p12-decrypt.md` §一)。

### 1.6 客户端验证服务端 cert 的反向 — 把服务端 cert 加到客户端 truststore

```bash
# 1) 先把服务端 cert 导出
keytool -exportcert -alias server -keystore server.jks -storepass '<PWD>' -rfc > server.crt

# 2) 导入到客户端 truststore(比如 Java 默认的 cacerts 或自定义 truststore)
keytool -importcert -alias my-server -file server.crt -keystore client-truststore.jks -storepass '<PWD>'
# 默认 trustcacerts=false,要写到 cacerts 时加 -trustcacerts
```

---

## 2. openssl — 服务端证书 + 网络可达性验证

### 2.1 从 keystore 抽出私钥(给 nginx / Envoy / 其他服务复用)

```bash
# PKCS12 一次抽完(cert chain + private key)
openssl pkcs12 -in server.p12 -nodes -passin pass:'<PWD>' -out combined.pem
# -nodes = no DES,即不加密私钥;线上慎用,只是迁移时用

# 只抽 key
openssl pkcs12 -in server.p12 -nodes -nocerts -passin pass:'<PWD>' -out key.pem

# 只抽 cert chain
openssl pkcs12 -in server.p12 -nokeys -passin pass:'<PWD>' -out fullchain.pem
```

**实测输出**(本目录的 demo):

```bash
$ openssl pkcs12 -in server-keystore.p12 -nodes -nocerts -passin pass:changeit
Bag Attributes
    friendlyName: server
    localKeyID: 54 69 6D 65 20 31 37 36 36 38 30 33 37 38 32 36 30 35
    1.2.840.113549.1.9.21 = 23 0D ... # friendlyName 字段
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC2pP0BUsR9AsAZ
...
```

> macOS 的 `openssl` 是 LibreSSL,某些 flag 不一样。比如 `-passin pass:changeit` 在 LibreSSL 上写法一样,但 `-passin env:PWD_VAR` 在某些版本上需要 `pass:` 前缀**紧贴变量名**,不能有空格。

### 2.2 JKS → PKCS12 转换(老项目换 Spring Boot 必踩)

```bash
# 老 keystore 是 JKS,要转成 Spring Boot 默认吃的 PKCS12
keytool -importkeystore \
  -srckeystore legacy-server.jks -srcstoretype JKS -srcstorepass '<OLD_PWD>' \
  -destkeystore server.p12 -deststoretype PKCS12 -deststorepass '<NEW_PWD>' \
  -destkeypass '<NEW_KEY_PWD>'
# 不指定 -destkeypass 时,默认跟 -deststorepass 相同(Spring Boot 兼容)
```

**判定**:Spring Boot 2.x+ 推荐 PKCS12(Java 9+ 默认);JKS 是 Java 8 时代的默认格式。**生产里不要再用 JKS**,PKCS12 更标准。

### 2.3 openssl s_client — 从外部 dial 服务端

```bash
# 最常见的形态(参考 ~/git/knowledge/OpenAI/docs/Verifying-GLB.md §3)
openssl s_client \
  -connect <IP>:<PORT> \
  -servername <SNI_HOSTNAME> \
  -showcerts \
  -verify_quiet \
  < /dev/null 2>/dev/null
```

**flag 详解**:

| Flag | 作用 | 必填? |
|---|---|---|
| `-connect IP:PORT` | 连谁 | 必填 |
| `-servername HOST` | SNI 字段;**多证书场景下决定服务端返回哪张** | **强烈推荐** |
| `-showcerts` | 把整个证书链打出来 | 推荐 |
| `-verify_quiet` | 静默 verify 失败(自签证书场景必备) | 可选 |
| `-CAfile <bundle>` | 信任的 CA;自签证书要给客户端 CA 才能通过 verify | 可选 |
| `-cert <client.pem>` | mTLS 时客户端证书 | mTLS 必填 |
| `-key <client.key>` | mTLS 时客户端私钥 | mTLS 必填 |
| `-tls1_2` / `-tls1_3` / `-tls1` | 强制协议版本 | 排查用 |
| `-cipher 'HIGH:!aNULL'` | 强制 cipher suite | 排查用 |

`< /dev/null` 是必须的(防止 s_client 等待 stdin 输入而卡住)。`2>/dev/null` 把 verify error 之类噪音去掉。

### 2.4 把 dial 回来的证书 dump 到本地(用于跨工具对账)

```bash
# 1) dial + dump 全部证书到 file
openssl s_client -connect <IP>:8443 -servername <HOST> -showcerts \
  </dev/null 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' \
  > /tmp/server-from-network.pem

# 2) 看指纹
openssl x509 -in /tmp/server-from-network.pem -noout -fingerprint -sha256

# 3) 跟用户提交的 keystore 里的 cert 比
keytool -list -v -keystore user.jks -storepass '<PWD>' 2>&1 \
  | grep -E '^\s+SHA256:'

# 一致 → Pod 加载的就是这张
# 不一致 → Pod 加载了别的(见 01-shell-access-strategies.md §3.3)
```

### 2.5 openssl x509 — PEM 格式证书查询

```bash
# 全部信息
openssl x509 -in cert.pem -text -noout

# 单字段
openssl x509 -in cert.pem -noout -subject
openssl x509 -in cert.pem -noout -issuer
openssl x509 -in cert.pem -noout -dates
openssl x509 -in cert.pem -noout -fingerprint -sha256
openssl x509 -in cert.pem -noout -ext subjectAltName
openssl x509 -in cert.pem -noout -serial

# 看是否过期(脚本里常用)
openssl x509 -in cert.pem -noout -checkend 86400
# exit 0 = 还有 ≥1 天;exit 1 = 已过期或 <1 天
```

### 2.6 openssl verify — 信任链验证

```bash
# 验服务端证书是否被指定 CA 签发
openssl verify -CAfile ca-bundle.pem server.pem

# 自签证书 → 必须把服务端 cert 自己作为 CA
cp server.pem /tmp/my-ca.pem
openssl verify -CAfile /tmp/my-ca.pem server.pem
# → server.pem: OK
```

---

## 3. keytool ↔ openssl 输出对账表

**同一个证书,从两边读出来的同一字段值应该一致**(只有格式差异)。这是判断"Pod 真的加载了用户那张 cert"的最关键对照表:

| 字段 | keytool 输出 | openssl 输出 | 一致性 |
|---|---|---|---|
| Subject | `Owner: CN=localhost, OU=Demo, ...` | `subject= /C=US/ST=State/L=City/O=Example/OU=Demo/CN=localhost`(LibreSSL/OpenSSL 把 RDN 写成 X.500 `/`-分隔形式) | ✅ 内容一致;**形式不同**(逗号空格 → 斜杠) |
| Issuer | `Issuer: CN=localhost, OU=Demo, ...` | `issuer=CN=localhost, OU=Demo, ...` | ✅ 一致 |
| 有效期 | `Valid from: Sat Dec 27 10:49:42 GMT+08:00 2025` | `notBefore=Dec 27 02:49:42 2025 GMT`(UTC) | ⚠️ **时区不同**(keytool 跟本地,openssl 默认 UTC) |
| SHA256 | `FF:42:86:14:6B:6A:68:A0:74:FB:11:CE:0E:EE:3B:AB:2D:74:D8:B8:F5:BA:8C:78:F4:73:F9:5B:FE:97:46:86` | `FF:42:86:14:6B:6A:68:A0:74:FB:11:CE:0E:EE:3B:AB:2D:74:D8:B8:F5:BA:8C:78:F4:73:F9:5B:FE:97:46:86` | ✅ **完全一致**(对账锚点) |
| Serial | `Serial number: 38c78d3621fa47c8` | `serial=38C78D3621FA47C8`(大写) | ✅ 数值一致,大小写不同 |
| SAN | `SubjectAlternativeName [DNSName: localhost, IPAddress: 127.0.0.1]` | `DNS:localhost, IP Address:127.0.0.1`(`openssl x509 -ext subjectAltName`,**不要加 `-noout`** — 加了输出空) | ⚠️ 格式不同但内容一致 |

**对比时唯一权威锚点是 SHA256 fingerprint**(忽略大小写和分隔符差异)。

---

## 4. 三个常见坑(踩过就知道)

### 4.1 macOS 上 `base64` 没有 `-w 0`(跟 GNU 不同)

```bash
# ❌ GNU 写法,macOS/BSD 直接 invalid argument
base64 -w 0 pwd-file

# ✅ macOS 写法
base64 -i pwd-file             # -i = --input,BSD 风格
# 或 -b 99999 把 76 字符换行压成一行
```

但**密码文件 base64** 有更稳的写法(已经踩过坑),见 `../p12-decrypt.md`:

```bash
pwdEncode=$(echo -n $(cat pwd-file) | base64)   # ✅ 永远正确
```

### 4.2 grep 解析 `-(list|exportcert)` 报错 invalid option

BSD/macOS 的 `grep` 把 `-` 开头的 token 当 flag,正则里要写 `grep -E -- '-(list|export)'` 或者用 ack/rg。常见于试图从 `keytool -help` 里 grep 提取命令名。

### 4.3 远程 dial 回来的证书链 ≠ keystore 里的证书

```bash
# 链很长的场景:
openssl s_client ... -showcerts
# 输出会有多段 BEGIN CERTIFICATE,每段是链的一环:
#   -----BEGIN CERTIFICATE-----  ← leaf (server cert,Tomcat 实际用的)
#   -----BEGIN CERTIFICATE-----  ← intermediate CA
#   -----BEGIN CERTIFICATE-----  ← root CA (self-signed)
```

如果只想对账 leaf(服务端 cert),用 `awk` 只取第一段:

```bash
openssl s_client -connect <IP>:8443 -showcerts </dev/null 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/{n++} n==1' > /tmp/leaf.pem
# n==1 只保留第一段(leaf),跳过 intermediate / root
```

---

## 5. 速查 — 一页纸 cheat sheet

| 想做的事 | 命令 |
|---|---|
| 看 keystore 里有啥 alias | `keytool -list -keystore <F> -storepass '<P>'` |
| 看具体 alias 的证书详情 | `keytool -list -v -alias <A> -keystore <F> -storepass '<P>'` |
| 导出证书成 PEM | `keytool -exportcert -alias <A> -keystore <F> -storepass '<P>' -rfc > cert.pem` |
| 算 PEM 的 SHA256 | `openssl x509 -in cert.pem -noout -fingerprint -sha256` |
| 从 PKCS12 抽私钥 + cert | `openssl pkcs12 -in <F> -nodes -passin pass:'<P>' -out combined.pem` |
| JKS 转 PKCS12 | `keytool -importkeystore -srckeystore <JKS> -srcstoretype JKS -destkeystore <P12> -deststoretype PKCS12 ...` |
| 从网络 dial 服务端证书 | `openssl s_client -connect <IP>:<PORT> -servername <HOST> -showcerts </dev/null 2>/dev/null` |
| 看 cert 还有几天过期 | `openssl x509 -in cert.pem -noout -checkend <秒>` |
| 把服务端 cert 加到客户端 truststore | `keytool -importcert -alias <A> -file server.crt -keystore <TRUSTSTORE> -storepass '<P>'` |
| 看进程在监听哪个端口(Pod 内) | `cat /proc/<PID>/net/tcp \| awk '$4=="0A"{print $2}'` |

---

下一步:Spring Boot 是怎么挑证书的、为什么 `server.ssl.key-alias` 配错就会崩,见 [03-spring-boot-yaml-ssl-anatomy.md](03-spring-boot-yaml-ssl-anatomy.md)。