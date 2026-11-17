# 03 — 代码层:Spring Boot SSL 是怎么挑证书的

> 你已经按 01、02 看到 Pod 实际在用哪张证书了。这一篇回到代码层,**解释为什么** `application.yml` 里这些字段决定了 Tomcat 用哪个 keystore / 哪个 alias / 哪种格式 — 以及为什么 `team_a_env_server` 那个 alias 不存在会直接让 Pod 启动崩。

---

## 1. 一张图:从 application.yml 到 TLS Server

```
┌────────────────────────────────────────────────────────────────────┐
│  application.yml (JAR 内 / ConfigMap / 环境变量)                   │
│    server:                                                         │
│      port: 8443                                                    │
│      ssl:                                                          │
│        enabled: true                                               │
│        key-store: classpath:CertKey/team_a_env_server.jks          │
│        key-store-password: passwd123445                           │
│        key-alias: team_a_env_server                                │
│        key-store-type: JKS                                         │
└────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼ Spring Boot 启动
┌────────────────────────────────────────────────────────────────────┐
│  SslProperties (org.springframework.boot.autoconfigure.web)        │
│    绑定 server.ssl.* 到 POJO                                        │
└────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│  WebServerFactoryCustomizer (auto-config chain)                    │
│    → TomcatServletWebServerFactory                                 │
│    → TomcatContextCustomizer                                       │
│    → 配置 Connector(protocol="HTTP/1.1")→ 加 SSL → setPort(8443)  │
└────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│  SslConnectorFactory (org.apache.tomcat.util.net)                  │
│    1. 加载 keystore: KeyStore.getInstance("JKS")                   │
│    2. 加载 .load(InputStream, "passwd123445".toCharArray())        │
│    3. 取私钥: keystore.getKey("team_a_env_server", char[])         │
│       ↑ 关键: alias 必须存在,且对应 PrivateKeyEntry                 │
│    4. 拿证书链: keystore.getCertificateChain(alias)                │
│    5. 构造 KeyManagerFactory (SunX509 / PKIX)                      │
│    6. connector.setSSLHostConfig(...) → tomcat 启用 TLS             │
└────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼ 监听 0.0.0.0:8443,等待 TLS ClientHello
┌────────────────────────────────────────────────────────────────────┐
│  Tomcat NIO Endpoint                                               │
│    Client → TLS handshake → 用第 3 步的私钥 + 第 4 步的证书链应答   │
└────────────────────────────────────────────────────────────────────┘
```

**根因复盘**:`Alias name [team_a_env_server] does not identify a key entry` 就是在第 3 步 `keystore.getKey(alias, ...)` 抛 `IllegalArgumentException` — keystore 里**没有这个 alias 的 PrivateKeyEntry**(可能是名字打错,或者这个 alias 是 `trustedCertEntry`)。完整解释见 `../java-application-auth.md` §一。

---

## 2. `application.yml` 每个字段对应到哪一行代码

下面这 6 个字段是排查时**最常出错**的,各自映射到 Spring Boot 源码里的具体入口。

### 2.1 `server.port`

```yaml
server:
  port: 8443
```

- **绑定类**:`ServerProperties.java` 的 `port` 字段(`@ConfigurationProperties("server")`)
- **生效路径**: `TomcatServletWebServerFactory.setPort(8443)`
- **优先级覆盖**(从高到低):
  1. 命令行 `--server.port=8443`
  2. 环境变量 `SERVER_PORT=8443`
  3. `application.yml` / `application-{profile}.yml`
  4. 默认 `8080`

**排查场景**:用户配了 `port: 8080`,平台 Deployment 模板里写了 `args: ["--server.port=8443"]`,实际跑起来是 8443。这是平台方"强制 HTTPS"的常见做法,容易被用户误解。

### 2.2 `server.ssl.enabled`

```yaml
server:
  ssl:
    enabled: true
```

- **绑定类**:`ServerProperties.java` 的 `ssl.enabled`
- **生效路径**:`ServletWebServerFactoryAutoConfiguration` 在 `enabled=true` 时调用 `WebServerFactoryCustomizer` 注入 SSL 配置
- **默认值**:**`false`**(2020 年之前是 `true`,Spring Boot 2.x+ 改了,**这是大量老教程的过时信息**)

**坑**:如果 `enabled: false`,即使你配了 `key-store` 等,Tomcat 也不会启用 HTTPS,**只监听 HTTP**。排查"我配了 keystore 但 curl 还是 HTTP"时第一时间看这个。

### 2.3 `server.ssl.key-store`

```yaml
server:
  ssl:
    key-store: classpath:CertKey/team_a_env_server.jks
```

- **绑定类**:`ServerProperties.Ssl.keyStore`
- **支持的前缀**(按 Spring Boot 3.x):
  - `classpath:` — JAR 内的 resources/
  - `file:` — 绝对路径(或相对当前工作目录)
  - 不带前缀 — 默认按 `file:` 解析
- **解析代码**:`ResourceLoader.getResource("classpath:CertKey/...").getInputStream()`

**支持格式**:`.jks` (JKS) / `.p12` / `.pfx` (PKCS12) / `.pem` (Spring Boot 3.2+ 有限支持,**生产慎用**)

### 2.4 `server.ssl.key-store-password`

```yaml
server:
  ssl:
    key-store-password: passwd123445
```

- **绑定类**:`ServerProperties.Ssl.keyStorePassword`
- **作用**:打开 keystore 的密码(可以是 storepass,也可以是 keypass,Spring Boot 默认当 storepass 用)
- **安全做法**:
  - ❌ 硬编码在 yaml
  - ✅ 放在 Secret / ConfigMap,通过环境变量注入:`KEY_STORE_PASSWORD=${SECRET_KEYSTORE_PASSWORD}`
  - ✅ 配合 Spring Cloud Config + Vault / KMS 动态解密

**坑**:详见 `../p12-decrypt.md` — 密码文件末尾的 `\n`、CRLF、或者 Secret base64 编码里多塞的换行,都会让"密码正确但加载失败"。

### 2.5 `server.ssl.key-alias` ← **报错焦点**

```yaml
server:
  ssl:
    key-alias: team_a_env_server
```

- **绑定类**:`ServerProperties.Ssl.keyAlias`
- **作用**:从 keystore 里**挑一个** PrivateKeyEntry 作为服务端的证书+私钥
- **底层调用**:`keystore.getKey(alias, keyPassword.toCharArray())` + `keystore.getCertificateChain(alias)`

**这是 `Alias name [team_a_env_server] does not identify a key entry` 的直接触发点**。触发条件(三选一即报错):

| 触发条件 | 现象 | 修法 |
|---|---|---|
| alias 不存在 | `getKey` 返回 null | `keytool -list` 看实际 alias,改正 yaml |
| alias 是 `trustedCertEntry` | `getKey` 抛 `UnsupportedOperationException` | 必须用 `PrivateKeyEntry` 类型的 alias |
| alias 是 `SecretKeyEntry` | `getKey` 返回 `SecretKey` 但不是 `PrivateKey`,后续 cast 失败 | 不能用 secret key 当 TLS cert |

**关键事实**:Spring Boot **不会**回退去选 keystore 里第一个 PrivateKeyEntry。alias 配错 = 启动必崩。

### 2.6 `server.ssl.key-store-type`

```yaml
server:
  ssl:
    key-store-type: JKS   # 或 PKCS12
```

- **绑定类**:`ServerProperties.Ssl.keyStoreType`
- **不写时**:`KeyStore.getInstance(defaultType)` — JDK 8 是 `JKS`,JDK 9+ 是 `PKCS12`
- **判定**:用 `file <FILE>` 看实际格式:
  - `Java KeyStore` → JKS
  - `PKCS12 KeyStore` → PKCS12
  - 文件头不是这两种 → 报错

**坑**:`key-store-type: PKCS12` 写成了 `PKCS#12` / `pkcs12` / `P12` 都行(大小写不敏感),但**写成 `JKS` 而文件其实是 PKCS12 会报错**。Spring Boot 看到 type 跟文件实际格式不符,加载失败。

### 2.7 其他常用但容易漏的字段

| 字段 | 作用 | 常见错 |
|---|---|---|
| `key-store-provider` | JCA provider(SUN 默认) | 改了导致 KeyStore.getInstance 报错 |
| `protocol` | TLS / SSL / SSLv3 / TLSv1 / TLSv1.1 / TLSv1.2 / TLSv1.3 | 写成 `SSL` 会被 Spring Boot 3.x 拒绝 |
| `enabled-protocols` | 启用的 TLS 版本列表(`TLSv1.2,TLSv1.3`) | 写错大小写或包含 `SSLv3` 会启动报错 |
| `client-auth` | `none` / `want` / `need`(mTLS) | 跟 LB 侧的 mTLS 策略要对齐 |
| `trust-store` / `trust-store-password` | 服务端验证客户端证书的 truststore | mTLS 必配 |
| `ciphers` | 强制 cipher suite 列表 | 写法见 Tomcat 文档 |

---

## 3. 自定义证书 vs 平台默认证书的优先级

如果平台方的 Deployment 模板已经塞了一份平台证书(`platform-keystore.p12`),用户在自己 JAR 的 `application.yml` 里又写了一份 `team_a_env_server.jks`,**哪份生效?**

### 3.1 三种"默认"路径

```
优先级(从高到低):

  1. 命令行参数     --server.ssl.key-store=...        (平台模板常用)
  2. 环境变量       SERVER_SSL_KEY_STORE=...          (ConfigMap/Secret 注入)
  3. SPRING_APPLICATION_JSON
  4. application-{profile}.yml
  5. application.yml                                  (用户 JAR 内,最低)
  6. 默认值(无 SSL)
```

### 3.2 平台模板的典型"自作主张"

```bash
# 某平台 Deployment 模板片段
args:
  - --server.ssl.enabled=true
  - --server.ssl.key-store=file:/etc/platform/keystore/platform-tls.p12
  - --server.ssl.key-store-password=${PLATFORM_TLS_PWD}
  - --server.ssl.key-alias=platform-server
env:
  - name: SPRING_APPLICATION_JSON
    value: '{"server.ssl.trust-store":"file:/etc/platform/keystore/platform-trust.p12",...}'
```

**结果**:用户 YAML 里写的 `team_a_env_server.jks` **被完全覆盖**,Pod 实际用的是平台那份。

**怎么发现**:看 `kubectl describe pod` 里的 `Args:` 和 `Environment:` 字段(命令 1.2 的 /proc/PID/cmdline 是更权威的运行时真相)。

### 3.3 ConfigMap/Secret 挂载覆盖 JAR 内文件的几种姿势

```yaml
# 1) volumeMount 覆盖整个目录(最狠 — 用户的 CertKey/ 整个被替换)
volumeMounts:
  - name: cert-volume
    mountPath: /app/CertKey   # 直接覆盖 JAR 解压后的路径

# 2) SPRING_APPLICATION_JSON 注入(只能覆盖 yaml 字段)
env:
  - name: SPRING_APPLICATION_JSON
    value: '{"server":{"ssl":{"key-store":"file:/etc/certs/user.jks","key-alias":"user-alias"}}}'

# 3) 命令行参数(最直接)
args: ["--server.ssl.key-store=file:/etc/certs/user.jks", "--server.ssl.key-alias=user-alias"]
```

**对应到 01 §1.2 的排查命令**:`cat /proc/$PID/cmdline` 能看到所有 `-D...` 和 `--server.*=...` 参数,这是**最终生效的配置**,跟 YAML 里写的不一定一样。

---

## 4. 完整的"代码 ↔ 配置"对照速查

| 你在 YAML 里写的 | Spring Boot 绑定类 | 最终 Tomcat 调用 |
|---|---|---|
| `server.port` | `ServerProperties.port` | `TomcatServletWebServerFactory.setPort(int)` |
| `server.ssl.enabled` | `ServerProperties.Ssl.enabled` | `WebServerFactoryCustomizer` 链 |
| `server.ssl.key-store` | `ServerProperties.Ssl.keyStore` | `ResourceLoader.getResource(...).getInputStream()` |
| `server.ssl.key-store-password` | `ServerProperties.Ssl.keyStorePassword` | `KeyStore.load(InputStream, char[])` |
| `server.ssl.key-alias` | `ServerProperties.Ssl.keyAlias` | `KeyStore.getKey(alias, char[])` ← 报错焦点 |
| `server.ssl.key-store-type` | `ServerProperties.Ssl.keyStoreType` | `KeyStore.getInstance(type, provider)` |
| `server.ssl.protocol` | `ServerProperties.Ssl.protocol` | `SSLContext.getInstance(protocol)` |
| `server.ssl.enabled-protocols` | `ServerProperties.Ssl.enabledProtocols` | `SSLEngine.setEnabledProtocols(...)` |
| `server.ssl.client-auth` | `ServerProperties.Ssl.clientAuth` | `SSLHostConfig.setCertificateVerification(...)` |
| `server.ssl.trust-store` | `ServerProperties.Ssl.trustStore` | `TrustManagerFactory.init(keystore)` |

---

## 5. 配套 demo — `../simple-https-demo/` 的代码层

跑 `../simple-https-demo/` 这个最小例子,把上面的映射**真实跑一遍**:

### 5.1 项目结构

```
simple-https-demo/
├── pom.xml                                   # Spring Boot 3.2 + Java 17
├── generate-cert.sh                          # 生成 server-keystore.p12
├── README.md
└── src/main/
    ├── resources/
    │   ├── application.yml                   # ← server.ssl.* 在这
    │   └── ssl/server-keystore.p12           # ← 类路径下的 keystore
    └── java/com/example/demo/
        ├── Application.java                  # @SpringBootApplication
        ├── config/RestClientConfig.java      # 出站 TLS 客户端(truststore)
        └── controller/DemoController.java    # /hello, /fetch
```

### 5.2 application.yml 的关键 4 行

```yaml
server:
  port: 8443
  ssl:
    enabled: true
    key-store: classpath:ssl/server-keystore.p12
    key-alias: server
    key-store-password: changeit
    key-store-type: PKCS12
    protocol: TLS
    enabled-protocols: TLSv1.2,TLSv1.3
```

**对照 §2**:`key-store` 走 `classpath:` 前缀,`key-alias=server` 对应 keystore 里的 `server` alias(在 02 里实测过是 `PrivateKeyEntry`)。

### 5.3 跑一遍验证命令链

```bash
cd ../simple-https-demo

# 1) (可选)重新生成 keystore
./generate-cert.sh
# → 在 src/main/resources/ssl/server-keystore.p12 写了 1 个 PrivateKeyEntry, alias=server

# 2) 启动
mvn spring-boot:run

# 3) 客户端 dial — 拿服务端 cert 指纹
openssl s_client -connect localhost:8443 -servername localhost -showcerts \
  </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -fingerprint -sha256
# 预期(subject 自签 CN=localhost):
# subject=C=US, ST=State, L=City, O=Example, OU=Demo, CN=localhost
# sha256 Fingerprint=FF:42:86:14:6B:6A:68:A0:74:FB:11:CE:0E:EE:3B:AB:2D:74:D8:B8:F5:BA:8C:78:F4:73:F9:5B:FE:97:46:86

# 4) 跟 keystore 里的 cert 比 fingerprint
keytool -list -v -keystore src/main/resources/ssl/server-keystore.p12 \
  -storepass changeit 2>&1 | grep SHA256
# 预期:看到跟步骤 3 完全一致的 FF:42:86:...

# 一致 → ✅ application.yml 里写的 key-store + key-alias,就是 Tomcat 实际用的
```

### 5.4 对照看 `key-alias` 配错会怎样

```bash
# 1) 把 application.yml 里 key-alias 改成不存在的名字
sed -i '' 's/key-alias: server/key-alias: nonexistent/' src/main/resources/application.yml

# 2) 启动
mvn spring-boot:run
# 预期报错(启动失败):
#   Caused by: java.lang.IllegalArgumentException: Alias name [nonexistent] does not identify a key entry
#       at org.apache.tomcat.util.net.SSLUtilBase.getKeyManagers(...)
#       at org.apache.tomcat.util.net.jsse.JSSEUtil.getKeyManagers(...)
#       at org.apache.tomcat.util.net.AbstractJsseEndpoint.createSSLContext(...)
#
# 这就是 ../java-application-auth.md §一里分析的报错,代码层定位在
# TomcatConnectorFactory 调 KeyStore.getKey(alias) 抛异常。

# 3) 改回去
sed -i '' 's/key-alias: nonexistent/key-alias: server/' src/main/resources/application.yml
```

---

## 6. 完整复盘:`team_a_env_server` 报错的代码层路径

把 `../java-application-auth.md` 那个 case 用本文的代码层视角重新过一遍:

```
1. Pod 启动 → Spring Boot main()
2. 读取 application.yml:server.ssl.key-alias=team_a_env_server
3. 走到 TomcatServletWebServerFactory.customize()
4. → SslConnectorFactory.createSSLContext()
5. → KeyStore.getInstance("JKS")                       ← §2.6
6. → keystore.load(stream, "passwd123445".toCharArray()) ← §2.4
7. → keystore.getKey("team_a_env_server", char[])       ← §2.5 触发点
        keystore 里没这个 alias 的 PrivateKeyEntry
        → 抛 java.lang.IllegalArgumentException
8. 异常上抛 → Spring Boot 启动失败 → Pod CrashLoopBackOff
```

**为什么不是"加载错了 keystore"而是"alias 不存在"**:
- 如果 keystore 本身加载失败 → 报错会是 `IOException: keystore was tampered with, or password was incorrect`(在步骤 6)
- 如果 alias 不存在 → 报错是 `IllegalArgumentException: Alias name [xxx] does not identify a key entry`(在步骤 7)

**两种报错对应不同的根因**:
- 步骤 6 报错:密码错 / keystore 损坏 / 文件不存在 → 查密码文件(见 `../p12-decrypt.md`)
- 步骤 7 报错:alias 拼错 / alias 是 trustedCertEntry / keystore 不是用户以为的那个 → 用 `keytool -list -v` 看实际 alias

---

## 7. 引用

| 文件 | 关联 |
|---|---|
| `../java-application-auth.md` | 同一个 `team_a_env_server` 报错的应用层分析 |
| `../p12-decrypt.md` | keystore 密码文件末尾 `\n` 导致加载失败的根因 |
| `../simple-https-demo/` | 本地最小 demo,所有命令可在本机真实跑通 |
| `references/01-shell-access-strategies.md` | 从 Pod 内 / 文件层 / 外部 dial 三个角度取证 |
| `references/02-keytool-openssl-cheatsheet.md` | 命令速查 + 实测输出 |
| `~/git/knowledge/OpenAI/docs/Verifying-GLB.md` | 同源 `openssl s_client` 用法,适合 LB / mTLS 场景 |