# 05 — Java 应用调第三方 HTTPS 报 `handshake_failure` — cipher 协商失败(出站方向)

> **典型现象**:Java 应用作为 Pod 部署,**自己作 TLS Server(8443)正常接收请求**,但**作为 TLS Client 出站调第三方 HTTPS**(如 `https://<IP>/email-with-attachment-path`)时日志报 `SSLHandshakeException: (handshake_failure) Received fatal alert: handshake_failure`,**根本到不了 HTTP 层**。第三方按安全规范(II1711 之类)关掉老 cipher、只允许 ECDHE/GCM/CBC-SHA256+,而 Java 应用那一侧 JRE 默认 cipher 列表跟第三方 enabled list **交集 = ∅**。**这是出站方向的 TLS 协议层失败,跟入站方向的 cert / SAN 问题(见 01-04)完全不沾边**。

> **方向**:出站(Client 角色)。跟前 4 篇(Server 角色)的根本区别见 §6 方向区分表。

---

## 1. 一句话根因

```
Java 应用作 TLS Client,发 ClientHello 给第三方 server
        ↓
ClientHello 里带的 cipher 列表 = JRE 默认 cipher 列表
        ↓
第三方 server 按 II1711 等安全策略关掉了老 cipher,
只允许 ECDHE/GCM/CBC-SHA256+(典型 8 条)
        ↓
JRE 默认 cipher 列表 ∩ 第三方 enabled cipher 列表 = ∅
        ↓
server 立刻回 Alert: handshake_failure,握手挂掉
```

**为什么"Server 模式没事,Client 模式就挂"?**

- Server 模式:Java 应用被动提供 cert 让外部 client 选 cipher —— **cipher 选择权在 client**,只要 server cert 能跟 client 选的 cipher 配合,server 不需要主动出栈
- Client 模式:Java 应用主动发 ClientHello 报自己的 cipher 列表 —— **cipher 列表是 client 的 JRE 默认值**,**不受 `server.ssl.*` 配置影响**(`server.ssl.*` 只管入站)

---

## 2. 跟其他 TLS 失败的精确区分(反向判别)

TLS 报错五花八门,看到 `handshake_failure` / `SSLHandshakeException` / `Cert mismatch` 时第一步是**精确分层定位**,因为不同层的 fix 路径完全不同:

| 报错字符串 / 现象 | TLS 协议层 | 根因 | Fix 路径 | 见本文档 |
|------------|---------|------|---------|---------|
| `SSLHandshakeException: handshake_failure` | 协议层(cipher 协商) | Java client cipher 列表 ∩ server enabled list = ∅ | **JRE / JCE 升级** | **✅ 本文(05)** |
| `SSLHandshakeException: PKIX path ... unable to find valid certification path` | 协议层(cert chain) | Server cert 的 CA 不在 client truststore | 加 CA 到 truststore | 不是 |
| `SSLHandshakeException: HTTPS hostname wrong` / `err 62` / `Hostname mismatch` | 应用层(hostname verify) | Server cert SAN 没覆盖 client 访问的 hostname | 重签 cert + 加 `-ext SAN=...` | [04](04-san-mismatch-hostname-verify.md) |
| (无报错,默默通过,但客户端处于 MitM 风险) | 应用层(hostname verify **被静默关掉**) | CVE-2026-50010:Netty client trust manager 包装类 bug | **升 Netty 4.1.135.Final / 4.2.15.Final** | 不是(见 `../cve-2026-50010-netty-hostname-verification-bypass.md`) |
| `PrematureCloseException` / `Connection reset` | 连接复用层(server 端 race) | reactor-netty `HttpServerOperations` keep-alive race | **升 reactor-netty 1.2.18 + Netty 4.1.135** | 不是(见 `../fix-spring-boot-3-5-16-remove-netty-overrides.md`) |
| `IOException: I/O error on POST request` + `404 NOT_FOUND` | 出站后应用层 | URL 错 / 后端路由错 | 看 HTTP code | 不是 |

**关键判别句**:**报错 = 你看到 TLS 校验在工作 = 不是 CVE-2026-50010**(CVE 是"校验**静默失效**");**报错 `handshake_failure` = 不是 hostname 校验,不是 Netty race,是 cipher 协商**。

---

## 3. 第三方安全升级触发的典型场景(2026 II1711 类)

### 3.1 第三方升级清单(用户报告里的)

```
Disabled protocols: SSLV2, SSLv3, TLSv1.0, TLSv1.1
Enabled protocol:   TLSv1.2
Disabled ciphers:   TLS_RSA_WITH_AES_256_CBC_SHA   ← 老 CBC 不带 SHA256
                    TLS_RSA_WITH_AES_128_CBC_SHA   ← 老 CBC 不带 SHA256
                    SSL_RSA_WITH_3DES_EDE_CBC_SHA  ← 3DES
Enabled ciphers:    8 条 ECDHE/GCM/CBC-SHA256+(见下表)
```

### 3.2 第三方 enabled 的 8 条 cipher vs Java JRE 支持情况

| 第三方 enabled cipher | Java 标准名 | JDK 8 默认开? | JCE Unlimited 影响 |
|---------------------|-----------|---------------|---------------------|
| `TLS_RSA_WITH_AES_128_CBC_SHA256` | 同名 | ✅ JDK 8u161+ | 不需要 |
| `TLS_RSA_WITH_AES_256_CBC_SHA256` | 同名 | ✅ JDK 8u161+ | **需要**(256-bit 受限) |
| `TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256` | 同名 | ✅ JDK 7+ | 不需要 |
| `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256` | 同名 | ✅ JDK 8u161+ | 不需要 |
| `TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384` | 同名 | ✅ JDK 7+ | **需要** |
| `TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384` | 同名 | ✅ JDK 8u161+ | **需要** |
| `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`   | 同名 | ✅ JDK 8u161+ | 不需要 |
| `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`   | 同名 | ✅ JDK 8u161+ | **需要** |

**第三方那句"Does the JRE support the cipher AES256-SHA?"的反向 hint**:`AES256-SHA = TLS_RSA_WITH_AES_256_CBC_SHA`,这条 cipher **在第三方禁用列表里**,不在启用列表里。第三方在问:"你们 client 还有没有协商这条 cipher 的能力?"——答案是"有",但这条 cipher **已经在第三方禁用列表里**,协商必然失败。

### 3.3 5 种典型 JRE × enabled list 交集场景

| 场景 | JRE 情况 | 跟第三方 enabled list 交集 | 结果 |
|------|---------|---------------------------|------|
| **A. 老 JRE**(JDK 8u60 之前 / JDK 7)| 只支持老 cipher(RSA+AES-CBC-SHA,**无** SHA256)| **0 条** | handshake_failure |
| **B. JDK 8u161+,但 JCE Unlimited 没装** | 256-bit cipher 灰掉,只剩 128-bit GCM/CBC-SHA256 | **2 条**(128-bit 那两条) | 大概率能通;若 server cert 是 ECDSA-signed 则还要 ECDHE_ECDSA 那条 |
| **C. JDK 8u161+,JCE 装了,但 client 默认禁用 ECDHE**(罕见配置) | 只有 RSA+AES-CBC-SHA256 两条 | **2 条** | 大概率能通,但握手走 RSA 密钥交换(无 PFS) |
| **D. 现代 JDK 11/17,默认配置** | 全部 ECDHE + GCM/CBC-SHA256 都有 | **全部 8 条** | ✅ 正常握手 |
| **E. client 显式 setEnabledCipherSuites(...)** | 锁死在某条 cipher | 0 或 1 条 | 看业务代码 |

**最常见的是 A 和 B**——用户的描述("我们没改过代码,问题突然出来")强烈指向这两个:
- **A**:第三方升级了 server 端安全配置(II1711),**触发**了原本"双方都凑合能通"的旧 cipher 协商失败
- **B**:JCE Unlimited Strength 没装,256-bit cipher 在 client 端不可用,导致 server 选 cipher 时发现 client 没能力

---

## 4. 完整自检流程(5 分钟定位)

### 4.1 Step 1:看 Java 应用当前版本(报告回写需要的最少事实集)

```bash
# 1.1 看 JRE 版本
kubectl exec -it <POD> -- java -version 2>&1
# 期望看到:JDK 8uXXX / JDK 11.0.X / JDK 17.X.X

# 1.2 看 Spring Boot 版本(从镜像里挖)
kubectl exec -it <POD> -- bash -c \
  'find /app -name "*.jar" -exec unzip -p {} META-INF/MANIFEST.MF \; 2>/dev/null \
   | grep -E "Spring-Boot-Version|Start-Class" | sort -u'
# 或查构建时记录的 pom 文件 / CI artifact 标签

# 1.3 看 JCE Unlimited Strength 是否安装
kubectl exec -it <POD> -- bash -c \
  'java -cp $JAVA_HOME/lib/security 2>&1; \
   ls -la $JAVA_HOME/jre/lib/security/ 2>/dev/null \
     || ls -la $JAVA_HOME/lib/security/'
# 看 US_export_policy.jar / local_policy.jar 的修改日期是否是 JDK 安装时的(JCE 默认)
# 或启动参数是否带 -Djava.security.properties=...
```

**报告需要的最少事实集**(用户回报告时缺一个就推不动):
- JRE/JDK 版本
- Spring Boot 版本
- 出站调用用的 HTTP 客户端(`HttpURLConnection` / `RestTemplate` / `WebClient` / `Apache HttpClient` / `OkHttp` 中哪一个)
- JCE Unlimited Strength 是否安装

### 4.2 Step 2:确认出站调用用的 HTTP 客户端(决定修法路径)

```bash
# 2.1 从应用镜像里挖 HTTP 客户端依赖
kubectl exec -it <POD> -- bash -c \
  'find /app -name "*.jar" -exec sh -c \
    "unzip -l {} 2>/dev/null | grep -E \
      \"org/springframework/web/client/RestTemplate|\
       reactor/netty/http/client/HttpClient|\
       org/apache/http/impl/client/CloseableHttpClient|\
       okhttp3/OkHttpClient|\
       javax/net/ssl/HttpsURLConnection\"" \; \
   | sort -u | head -20'
# 看到什么 = 出站用什么 HTTP 库
# 这是修法选择的决定项(见 §5)

# 2.2 如果是 WebClient(Reactor Netty 客户端路径),检查是否受 CVE-2026-50010 影响
kubectl exec -it <POD> -- bash -c \
  'find /app -name "*.jar" -exec sh -c \
    "unzip -p {} META-INF/MANIFEST.MF 2>/dev/null | grep -E \"Bundle-Version|Implementation-Version\"" \; \
   | grep -iE "netty|reactor" | head -10'
# 看到 io.netty:netty-handler < 4.1.135.Final → 受 CVE-2026-50010 影响(独立问题,见 ../cve-2026-50010-netty-hostname-verification-bypass.md)
```

### 4.3 Step 3:启用 SSL debug 看握手细节(强推,2 分钟出真相)

**重启 Java 应用加 `-Djavax.net.debug=ssl,handshake`**,重现调用,看 stdout:

```
*** ClientHello, TLSv1.2
Cipher Suites: [
  TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
  TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
  TLS_RSA_WITH_AES_256_CBC_SHA256,
  TLS_RSA_WITH_AES_128_CBC_SHA256,
  TLS_RSA_WITH_AES_256_CBC_SHA,       ← 老 CBC,无 SHA256
  TLS_RSA_WITH_AES_128_CBC_SHA,       ← 老 CBC,无 SHA256
  ...                                  ← 你 JRE 支持的全部
]
...(no ServerHello)                  ← 没有!server 直接回 alert:handshake_failure
Received fatal alert: handshake_failure
```

**两种结局判别**:

| 结局 | 现象 | 含义 | 下一步 |
|------|------|------|--------|
| **结局 1** | ServerHello 之后才挂(server 选了一条 cipher,后续失败) | cert chain 问题或 hostname mismatch(跟 CVE-2026-50010 可能相关)| 走 §[02](02-keytool-openssl-cheatsheet.md) 验 cert chain / 走 [04](04-san-mismatch-hostname-verify.md) 验 hostname |
| **结局 2** | ClientHello 之后立刻挂(no ServerHello,server 立刻回 alert) | **典型 cipher 不匹配** — 本文主场景 | 走 §5 修法 |

### 4.4 Step 4:用 openssl 反向 probe 第三方(从 Pod 出口 dial)

```bash
# 在 Pod 内,或从 Pod 出口 dial 第三方
kubectl exec -it <POD> -- bash -c '
echo "" | openssl s_client \
  -connect <THIRD_PARTY_IP>:443 \
  -servername <THIRD_PARTY_SNI_IF_ANY> \
  -tls1_2 \
  -cipher "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:RSA-AES128-CBC-SHA256:RSA-AES256-CBC-SHA256" \
  </dev/null 2>&1 | grep -E "Cipher\s+:|verify return|handshake failure"'

# 把第三方 enabled 的全部 8 条 cipher 写进 -cipher,看 server 实际选哪条
#   - 如果能选出来(例:ECDHE-RSA-AES128-GCM-SHA256)
#     → 第三方端没问题,问题在 Java client 的 JRE 不支持这条
#   - 如果 openssl 都协商不出来
#     → 第三方 server 又改了策略,要重新要 enabled list
```

---

## 5. 修法(由轻到重 4 种,按业务约束选)

| 修法 | 治本次 handshake_failure? | 顺便治 CVE-2026-50010? | 顺便治 PrematureClose race? |
|------|-------------------------|---------------------|-------------------------|
| **A. 升 JRE 到 JDK 8u401+ / 11+ / 17+** | ✅ | ❌(JSSE 不沾 CVE) | ❌ |
| **B. 装 JCE Unlimited Strength** | ✅(只 256-bit 缺失时) | ❌ | ❌ |
| **C. 代码显式 setEnabledCipherSuites(...)** | ✅ | ❌ | ❌ |
| D. 升 Spring Boot 3.5.16 + 删 Netty override | ❌ | ✅ | ✅ |

**重要**:**不要**为了本次握手失败去升 Spring Boot 3.5.16 / Netty 4.1.135——那个修的是另一个独立问题。修本次问题只用 A 或 B 或 C。

### 5.1 修法 A:升 JRE(根治,推荐)

| JRE 状态 | 第三方 enabled list | 默认交集 | 修法 |
|---------|-------------------|---------|------|
| **JDK 8u60 及以下** | 8 条 | **0 条** | 升级到 **JDK 8u401+(8 系列最新版)** |
| **JDK 8u161 ~ JDK 8u201**(没装 JCE Unlimited)| 8 条 | 2 条(只 128-bit) | 装 JCE Unlimited Strength |
| **JDK 8u291+ / JDK 11.0.11+ / JDK 17+** | 8 条 | 8 条 | ✅ 不需要改任何代码 |

**注意**:升 JRE **不一定要升 Spring Boot**。Spring Boot 2.x / 1.x 都能在 JDK 17 上跑(有方法废弃 warning 需要清),但**比升 Spring Boot 3.5.16 改动小得多**。

### 5.2 修法 B:装 JCE Unlimited Strength(5 分钟,不动 JRE 大版本)

JDK 8u161 之后默认装 unlimited,如果是 8u60~8u151 区间需要补装:

```bash
# 方法 1:替换 $JAVA_HOME/jre/lib/security/ 下的两个 jar(从 Oracle/Java 官网下载对应版本的 JCE)
#   local_policy.jar
#   US_export_policy.jar

# 方法 2:启动参数强制 unlimited(不动 jar)
kubectl set env deployment/<DEPLOYMENT> \
  JAVA_OPTS="-Djava.security.properties==/path/to/custom.java.security"
# custom.java.security 里写:
#   crypto.policy=unlimited
```

### 5.3 修法 C:代码侧显式指定 cipher(可控性最高,但有副作用)

**HttpURLConnection / HttpsURLConnection**:

```java
URL url = new URL("https://<IP>/email-with-attachment-path");
HttpsURLConnection conn = (HttpsURLConnection) url.openConnection();
conn.setEnabledCipherSuites(new String[] {
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_RSA_WITH_AES_128_CBC_SHA256",
    "TLS_RSA_WITH_AES_256_CBC_SHA256"
});
```

**Spring WebClient(Reactor Netty)**:

```java
import io.netty.handler.ssl.SslContextBuilder;
import io.netty.handler.ssl.SslProvider;

SslContext sslContext = SslContextBuilder.forClient()
    .sslProvider(SslProvider.JDK)  // 用 JDK SSL stack(关键,不要用 OpenSSL provider)
    .ciphers(Arrays.asList(
        "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
        "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
        "TLS_RSA_WITH_AES_128_CBC_SHA256",
        "TLS_RSA_WITH_AES_256_CBC_SHA256"
    ))
    .build();
```

⚠️ **副作用**:硬编码 cipher 列表会让应用在第三方再次升级 cipher 策略时再挂一次。**建议只在过渡期用**。

---

## 6. 方向区分表(出站 Client vs 入站 Server)

| 维度 | 入站(Server)| 出站(Client)| 本文主场景 |
|------|-----------|-----------|----------|
| **TLS 角色** | Java 应用被动提供 cert 让外部 client 选 cipher | Java 应用主动发 ClientHello 报自己的 cipher 列表 | 出站 |
| **配置入口** | `server.ssl.*`(Spring Boot YAML)| 取决于 HTTP 客户端:<br>- `HttpURLConnection`:JRE 默认 cipher 列表<br>- `WebClient`:Netty `SslContext`<br>- `Apache HttpClient`:`SSLConnectionSocketFactory` | - |
| **Pod 内报错线程名** | `https-jsse-nio-8443-exec-N`(Tomcat connector worker)| 同一个线程名也可能是(因为出站调用在 server worker 线程里发起)| 本文里日志报 `https-jsse-nio-8443-exec-5` 是 server 线程在调第三方 |
| **JDK / JSSE 影响** | Server 不需要 outbound cipher | **Client 完全由 JRE 默认 cipher 列表决定** | ✅ |
| **CVE-2026-50010 影响** | 不沾(server 端不校验 client hostname) | **沾**(Netty client hostname verify 静默关)| ❌ 但常被误关联 |
| **第三方升级触发** | 不触发(server 不主动出栈)| **触发**(client cipher 列表跟 server enabled list 交集可能变 ∅)| ✅ |
| **修复责任在谁** | 平台提供的 server.ssl.* 配置 + 用户提供的 cert | **用户**(JRE / 代码 / HTTP 客户端库)| ✅ |

**重要判别**:**出站调第三方 → 修复责任在用户**(平台提供的是 server.ssl.* 入站配置,不沾出站)。平台侧可加护栏(InitContainer 校验 JRE cipher 能力、监控告警),但**根因修复责任在用户自己**。

---

## 7. 跟 CVE-2026-50010 / `fix-spring-boot-3-5-16-remove-netty-overrides.md` 的精确区分

用户最容易踩的坑:看到 `handshake_failure` + Java 应用 + Netty 在 dep tree 里,就误以为是 CVE-2026-50010 或 reactor-netty race。**两个都是错的**——这次的根因是 JRE cipher 列表,跟 CVE 完全无关。

| 维度 | 本文(cipher mismatch)| CVE-2026-50010 | reactor-netty race |
|------|------------------|----------------|---------------------|
| **报错?** | ✅ `handshake_failure` | ❌ 静默通过 | ✅ `PrematureCloseException` |
| **协议层** | TLS 协议层(cipher 协商)| TLS 应用层(hostname 校验)| 连接复用层(server 端 race)|
| **何时触发** | 第三方升级 cipher 策略后 | 用了 plain `X509TrustManager` + 旧 Netty | server keep-alive 连接复用 |
| **跟 Netty 有关?** | **不必然**(出站用 JDK HttpURLConnection 就不沾 Netty)| **是**(Netty 自定义 trust manager 路径)| **是**(reactor-netty server) |
| **修法** | 升 JRE / 装 JCE Unlimited / 代码显式 cipher | **升 Netty 4.1.135.Final / 4.2.15.Final** | **升 reactor-netty 1.2.18 + Netty 4.1.135** |
| **修复后证书校验更严还是更松?** | N/A(cipher 层,跟校验无关)| 更严(hostname verify 不再被静默关掉) | N/A(连接层)|

**常见被误关联**:
- "我们跟踪这个问题时发现跟 CVE 有关"—— 平台正在做 Spring Boot 3.5.16 升级时,用户报问题过来被自动打上 CVE 标签
- "API 自己跑没事,API 主动调第三方就挂"—— 听起来像 CVE 描述的"client 端 hostname 校验问题",实际是 cipher 层
- "重新部署 Netty 看看"—— **升 Netty 治不了本次问题**,只会浪费时间

---

## 8. 给用户的"一句话回应"(可直接转用户,中英双语)

### 中文版

> 你看到的 `handshake_failure` 是 **Java 应用作为 TLS Client 跟第三方 server cipher 协商失败**,**不是** CVE-2026-50010(那是 hostname 校验被静默关掉,**不会**报 handshake_failure),**也不是** reactor-netty keep-alive race 那个问题(那是 server 端)。
>
> 直接原因是第三方按 II1711 升级了安全配置(关老 cipher、只允许 ECDHE/GCM/CBC-SHA256+),**触发了原本"双方都凑合能通"的旧 cipher 协商失败**——Java 应用那一侧的 **JRE cipher 列表跟第三方 enabled cipher 列表的交集变成 ∅**。很可能是 JRE 版本太老(8u60 以下)或 JCE Unlimited Strength 没装。
>
> 在给我们回报告之前,请先确认以下信息:(1) 当前运行的 Java Application 版本(JRE/JDK 版本 + Spring Boot 版本 + 出站调用用的 HTTP 客户端);(2) JCE Unlimited Strength 是否安装。如果可以,登录到 Java 终端,**用 OpenSSL 命令做一次 debug**(参考 §4.4 的 `openssl s_client -cipher ...` 命令),看反馈结果。
>
> 从职责分工来讲,**这是用户 Client 代码里的问题,跟平台本身没有关系**——平台提供的是入站 TLS Server 配置(`server.ssl.*`),出站调第三方是 Java 应用自己引入的 HTTP 客户端 + 自己运行时 JRE 的 cipher 列表,平台既不持有这段代码,也不控制这个 JRE cipher 列表。**需要用户从代码端(JRE 升级 / HTTP 客户端配置)来修复这个问题**。

### English Version

> The `handshake_failure` you are seeing is a **cipher suite negotiation failure between your Java application (acting as TLS Client) and the third-party server** — it is **NOT** CVE-2026-50010 (which silently disables hostname verification and **does not** produce a `handshake_failure`), and it is **NOT** the reactor-netty keep-alive race either (which is a server-side bug).
>
> The root cause is the third-party's II1711 security upgrade (disabling legacy ciphers, allowing only ECDHE/GCM/CBC-SHA256+), which **broke the previously-working-but-barely cipher negotiation** — the intersection between your Java application's JRE cipher list and the third-party's enabled cipher list is now **∅**. Most likely your JRE is too old (8u60 or earlier) or JCE Unlimited Strength is not installed.
>
> Before replying with a report, please confirm: (1) the **currently running Java Application version** (JRE/JDK version + Spring Boot version + outbound HTTP client in use); (2) whether **JCE Unlimited Strength is installed**. If possible, log into the Java terminal and **run an OpenSSL probe** (see §4.4's `openssl s_client -cipher ...` command), then share the response.
>
> From a responsibility perspective, **this is a problem in the user's client-side code, not in the platform itself** — the platform provides inbound TLS Server configuration (`server.ssl.*`), but the outbound call to the third-party is initiated by the Java application's own code, using **the HTTP client it pulls in + the cipher list from its own runtime JRE**. The platform neither owns this code nor controls this JRE cipher list. **The user must fix this from the code side** (JRE upgrade / HTTP client configuration).

---

## 9. 同目录相关资源

- [01 — shell 访问策略与 3 场景实战](01-shell-access-strategies.md) — Server-side cert/SAN 排查的 3 个递进场景
- [02 — keytool + openssl 命令速查](02-keytool-openssl-cheatsheet.md) — cert / keystore 解析命令
- [03 — 代码层:Spring Boot SSL 是怎么挑证书的](03-spring-boot-yaml-ssl-anatomy.md) — `server.ssl.*` 配置机制
- [04 — SAN 不匹配自检](04-san-mismatch-hostname-verify.md) — 入站方向 hostname 校验失败(本文是出站方向,反方向)
- [`../fix-spring-boot-3-5-16-remove-netty-overrides.md`](../fix-spring-boot-3-5-16-remove-netty-overrides.md) — reactor-netty race + CVE-2026-50010 修复(本文无关,但常被误关联)
- [`../cve-2026-50010-netty-hostname-verification-bypass.md`](../cve-2026-50010-netty-hostname-verification-bypass.md) — CVE-2026-50010 全文(本文无关,但用户常误以为相关)
- [`../gke-pod-cert-vs-cve-2026-50010-diagnosis.md`](../gke-pod-cert-vs-cve-2026-50010-diagnosis.md) — Kong DP → Pod 链路上的 cert / hostname 问题(本文无关)
- [`../java-application-auth.md`](../java-application-auth.md) — Spring Boot server.ssl vs client.ssl 角色区分(互补)
- [`../pod-curl.md`](../pod-curl.md) — 本主题的 Case ID test_nik1 原始报告 + 完整深度分析(本文是该案例的精炼版)|

---

## 验证 — 怎么证明这份文档自己是对的

| 验证项 | 方法 | 预期 |
|---|---|---|
| §3.2 cipher 表里 JCE Unlimited 影响判断 | 查 Oracle 官方文档 `https://docs.oracle.com/javase/8/docs/technotes/guides/security/SunProviders.html` 的 `SunJCE` / `AlgorithmParameters` 章节 | 256-bit cipher 受 `crypto.policy` 限制,见原文 |
| §4.3 两种结局判别 | 在本地用 JDK 8u60 + 一个只支持 SHA(无 SHA256)的 server 复现 `handshake_failure`,启 `-Djavax.net.debug=ssl,handshake` 看 ClientHello → no ServerHello → alert 链路 | 看到 ClientHello 后立即 alert,无 ServerHello |
| §4.4 openssl 反向 probe | 用 `openssl s_client -cipher "ECDHE-RSA-AES256-GCM-SHA384:..."` 试不同 cipher 列表,看 server 选哪条 | server 选第一个 client 支持且 server enabled 的 cipher |
| §5 修法对比 | 升 JRE 11 → 跑 §4.3 复现命令 → 应通 | 全部 enabled list 8 条 cipher 都协商成功 |
| §6 方向区分 | 一个 Java 应用同时跑 server.ssl.* 入站 + HTTP 客户端出站,改一处只影响一边 | 验证 server.ssl.* 不影响出站 cipher 列表 |