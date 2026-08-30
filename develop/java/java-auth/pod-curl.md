# Pod 出站调用第三方 HTTPS 报 `handshake_failure` — 深度分析 + 修法

> **场景**:Java 应用作为 **TLS Client** 调第三方 HTTPS 接口(`https://<IP>/email-with-attachment-path`)时,日志报 `Received fatal alert: handshake_failure`,但 Java 应用本身作为 TLS Server(8443)接收请求**没有问题**。  
> **用户原始疑问**:这个问题是不是跟 `fix-spring-boot-3-5-16-remove-netty-overrides.md` 里那个 Netty race / CVE-2026-50010 是一回事?  
> **结论先行**:**不是一回事**。那个文档修的是 **(1)** reactor-netty 1.2.17 的 `PrematureCloseException` keep-alive race(纯连接层 bug),**(2)** CVE-2026-50010(Netty 客户端 hostname verification 被静默关掉,**不会**报 handshake_failure —— 反而是**不报错**地通过校验)。  
> **这次的握手失败是第三条独立链路**:Java 应用作为 **TLS 客户端** 跟第三方 server 之间的 **cipher suite 协商失败**——第三方按安全规范关掉了老 cipher、只允许 ECDHE/GCM/CBC-SHA256+,而 Java 应用那一侧(老 JRE / 默认 cipher 列表)**没跟第三方交集**。这是协议层握手,跟连接层 race / hostname 校验层 bug 都不沾边。

---

## §0 原始问题(完整保留,不动一个字)

> We're facing an issue at our Audit Letter application. Could you please look into it?
> We haven't made any changes recently. We're not seeing any direct dependency defined in the pom.xml. Spring Boot 3.5.16 requires Java 17 or later. Currently, we can't update Spring Boot to 3.5.16 as it would require many changes and additional testing.
>
> Case ID: test_nik1
>
> GCP log (textPayload):
> ```
> 14182d06-feel-49ba-9c69-08b0bed8cb74 ERROR https-jsse-nio-8443-exec-5 c.h.d.c.s.i.MainServiceImpl - Exception: I/0 error on POST request for "https://<IP_ADDRESS>/email-with-attachment-path"; (handshake_failure)
> Received fatal alert: handshake_failure; nested exception is javax.net.ssl.SSLHandshakeException: (handshake_failure) Received fatal alert:
> handshake_failure
> ```
>
> Also seeing: `404 NOT_FOUND`
>
> The third-party team suggested checking the following:
>
> - Does the JRE used by the application support the cipher AES256-SHA?
> - Is the application deployed on WAS?
>
> They also confirmed changes on the third-party as part of Security changes (II1711):
>
> - Disabled protocols: SSLV2, SSLv3, TLSv1.0, TLSv1.1
> - Enabled protocol: TLSv1.2
> - Disabled cipher suites:
>   - `TLS_RSA_WITH_AES_256_CBC_SHA`
>   - `TLS_RSA_WITH_AES_128_CBC_SHA`
>   - `SSL_RSA_WITH_3DES_EDE_CBC_SHA`
> - Enabled cipher suites:
>   - `TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256`
>   - `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256`
>   - `TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384`
>   - `TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384`
>   - `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`
>   - `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`
>   - `TLS_RSA_WITH_AES_128_CBC_SHA256`
>   - `TLS_RSA_WITH_AES_256_CBC_SHA256`

---

## §1 你的理解是对的——精确说"是什么场景在失败"

线程名 `https-jsse-nio-8443-exec-5` 是 **server-side Tomcat connector**(端口 8443 的 HTTPS 入站连接器)的 worker 线程。这个线程在处理**外部打到 8443 的入站请求**时,业务逻辑走到 `MainServiceImpl` 里**主动向外**发起 POST 到 `https://<IP_ADDRESS>/email-with-attachment-path`。**这次出站调用是 TLS Client 角色**——出站失败抛 `SSLHandshakeException: (handshake_failure)`。

**关键判别**:

| 角色 | 端口 | 状态 |
|------|------|------|
| Java 应用作为 **TLS Server**(接收外部请求) | 8443 | ✅ 正常 |
| Java 应用作为 **TLS Client**(主动调第三方) | 出站 | ❌ **handshake_failure** |

**所以你理解"作为 Client 去请求第三方的时候,第三方返回 JSON 报错"是对的**——只不过细节精确一下:**不是第三方"返回 JSON 报错"**,而是**握手阶段 TLS alert `handshake_failure`**,根本还没到 HTTP 层——更不会有 JSON body。**`404 NOT_FOUND` 是另一次独立请求**的报错(可能跟这个无关),别混在一起读。

---

## §2 为什么不是 CVE-2026-50010?(反向判别)

CVE-2026-50010 的原始行为是:

> "Netty silently bypasses TLS hostname verification when custom plain X509TrustManagers are used, exposing clients to unauthenticated Man-in-the-Middle (MitM) traffic interception."[1]

关键词:

- **"silently bypasses"** —— 静默跳过 hostname check,**不会抛 SSLHandshakeException**
- 触发条件:Netty 客户端用了 **plain `X509TrustManager`**(而不是 `X509ExtendedTrustManager`)
- 影响面:**Netty 客户端**做 mTLS / SAN 校验时,**hostname 校验被静默关掉**

你看到的是 `handshake_failure` —— **握手直接挂了**——这跟 CVE-2026-50010 的"**静默通过**"行为是**反过来的**。

| 维度 | 你看到的现象 | CVE-2026-50010 的行为 |
|------|------------|---------------------|
| **报错?** | ✅ 报 `handshake_failure` | ❌ 静默通过,**看不到**任何错误 |
| **作用层** | TLS 协议层(cipher 协商) | TLS 应用层(hostname verification) |
| **谁是 Netty?** | 出站 client 路径**可能是** JDK JSSE(看具体用的 HTTP 库) | 必须是 Netty 自定义 trust manager |
| **改 Netty 版本能修?** | ❌ 不行,Netty 自己没 bug | ✅ 升 Netty 4.1.135.Final / 4.2.15.Final |

**一句话判别**:你看到的报错是**握手阶段的 cipher 协商**,CVE-2026-50010 是**握手完成后**的 hostname 校验。两层完全不沾边。

那"我们最初跟踪时发现跟 CVE 有关系"是怎么来的?——平台这边当时在做 Spring Boot 3.5.16 升级(`fix-spring-boot-3-5-16-remove-netty-overrides.md`),用户报问题过来时**正赶上** Netty 升级窗口期,所以"被挂上 CVE 关联"的标签。**但实质是两个独立问题**。

---

## §3 为什么也不是 `fix-spring-boot-3-5-16-remove-netty-overrides.md` 的那个 race?

那个文档修的两件事:

1. **reactor-netty `HttpServerOperations` keep-alive race**——server 端在 keep-alive 连接复用时,新进来的请求会被 spurious close 掉,抛 `PrematureCloseException`。这是**server-side reactor-netty 内部的连接复用 bug**,Netty 自己修,4.1.135.Final + reactor-netty 1.2.18 已经修了。2. **CVE-2026-50010**(见 §2)

而你这次的 `handshake_failure`:

- **不是 server 端 keep-alive race**(那是 server 侧)
- **不是 hostname 校验**(那是 application 层)
- **是 cipher 协商**——client hello 发出去,server hello + server certificate 阶段 client 这边发现**没有跟 server 重叠的 cipher suite**,主动(或被动)发 `handshake_failure` alert

**修法路径完全不重叠**。升 Spring Boot 3.5.16 / Netty 4.1.135 / Reactor Netty 1.2.18 **解决不了**这次的 cipher mismatch。

---

## §4 真正的根因:第三方 cipher 列表 vs Java client 默认 cipher 列表的交集

### 4.1 第三方 server 只允许的 cipher 集合(从用户报告里提的)

```
TLSv1.2 only; 关闭 SSLv3 / TLSv1.0 / TLSv1.1;
关掉:RSA+AES-CBC-SHA(老 CBC,不带 SHA256) + 3DES;
只开:ECDHE+AES(GCM/CBC-SHA256+)+ RSA+AES-CBC-SHA256(注意是 SHA256,不是 SHA)
```

关键 cipher 名解释:

| 第三方要的 cipher 名 | Java 里的标准名 | JRE 8 默认开? |
|--------------------|---------------|----------------|
| `TLS_RSA_WITH_AES_256_CBC_SHA`     | `TLS_RSA_WITH_AES_256_CBC_SHA`     | ✅ 旧 cipher,默认开 |
| `TLS_RSA_WITH_AES_128_CBC_SHA`     | `TLS_RSA_WITH_AES_128_CBC_SHA`     | ✅ 旧 cipher,默认开 |
| `TLS_RSA_WITH_AES_128_CBC_SHA256`  | `TLS_RSA_WITH_AES_128_CBC_SHA256`  | ✅ JDK 8u161+ 默认开 |
| `TLS_RSA_WITH_AES_256_CBC_SHA256`  | `TLS_RSA_WITH_AES_256_CBC_SHA256`  | ⚠️ JDK 8u161+ 默认开,但**需要 JCE unlimited strength** |
| `TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256` | 同名 | ✅ JDK 7+ 默认开 |
| `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256` | 同名 | ✅ JDK 8u161+ 默认开 |
| `TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384` | 同名 | ⚠️ 需要 JCE unlimited |
| `TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384` | 同名 | ⚠️ 需要 JCE unlimited |
| `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`   | 同名 | ✅ JDK 8u161+ 默认开 |
| `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`   | 同名 | ⚠️ 需要 JCE unlimited |

第三方问 "**Does the JRE support the cipher AES256-SHA?**" 是个反向 hint:
- `AES256-SHA` 在 Java 标准名里就是 `TLS_RSA_WITH_AES_256_CBC_SHA`
- 这条 cipher 在第三方 server 的**禁用**清单里,不在**启用**清单里
- 第三方在问:"你们 client 还有没有协商这条 cipher 的能力?"——答案是"有",但这条 cipher **已经在第三方禁用列表里**,所以协商必然失败

### 4.2 真正协商失败的几种典型场景

| 场景 | Java client 侧情况 | 跟第三方交集 | 结果 |
|------|-------------------|------------|------|
| **A. 老 JRE(JDK 8u60 之前 / JDK 7)** | 只支持老 cipher(RSA+AES-CBC-SHA,无 SHA256)| **0 条** | handshake_failure |
| **B. JDK 8u161+,但 JCE Unlimited Strength 没装** | 256-bit cipher 灰掉,只剩 128-bit GCM/CBC-SHA256 | **2 条**(128-bit 那两条)| 第三方愿意接受应该能成;若 server cert 是 ECDSA-signed 则还要 ECDHE_ECDSA 那条 |
| **C. JDK 8u161+,JCE 装了,但 client 默认禁用 ECDHE**(罕见配置)| 只有 RSA+AES-CBC-SHA256 两条 | **2 条** | 大概率能成,但握手走 RSA 密钥交换(无 PFS) |
| **D. 现代 JDK 11/17,默认配置** | 全部 ECDHE + GCM/CBC-SHA256 都有 | **全部 8 条** | 正常握手 |
| **E. client 显式 setEnabledCipherSuites(...)** | 锁死在某条 cipher | 0 或 1 条 | 看业务代码 |

**最常见的是 A 和 B**——用户的描述("我们没改过代码,问题突然出来")强烈指向这两个:
- A:第三方升级了 server 端安全配置(II1711),**触发**了原本"双方都凑合能通"的旧 cipher 协商失败
- B:JCE Unlimited Strength 没装,256-bit cipher 在 client 端不可用,导致 server 选 cipher 时发现 client 没能力

### 4.3 为什么"API 本身运行没问题,但 API 自己去请求第三方时报错"——精确解读

- "API 本身运行没问题"= Java 应用作 **TLS Server**(8443)接收请求时,**server 端不需要 outbound cipher**——server 是被动提供 cipher 列表让客户端选,只要 client 选中的 cipher server 支持就行。第三方来的 client(浏览器、curl、内部系统)都是现代的,**server 不需要自己出栈**协商,所以不报错。
- "API 自己请求第三方报错"= Java 应用作 **TLS Client** 时,**client 端需要 outbound cipher**——Java 把自己支持的 cipher 列表(client hello 里的 `CipherSuites` 字段)发给第三方 server,server 在自己的**允许列表**里挑。如果**两者交集 = ∅**,server 直接 `handshake_failure`。

**所以"API 自己跑没事,API 主动调第三方就挂" = client 角色特有的问题,跟 server 配置无关。**

#### 协议层精确定位(交叉引用)

> 这一节只从 **Java / JRE 配置** 的角度说"cipher 不匹配导致 handshake_failure"。**协议层(RFC)的精确行为** ——server 是怎么发现自己 cipher 列表为空、fatal alert 是怎么发出去的、为什么 ServerHello 完全没出现 —— 在 `safe/ssl/docs/tls-handshake-explained.md` §2.5 "What if ServerHello never comes? (the failure path)" 里有逐字 RFC 引用 + 失败路径 ASCII 图 + 7-byte TLS Alert record 的诊断细节。**两篇是同一现象的两层视角**:本文件负责"Java 怎么修",那个文件负责"协议为什么这样"。

---

## §5 三种客户端 HTTP 库对应的 cipher 控制路径

虽然线程名 `https-jsse-nio-8443` 显示 **server-side** 用的 Tomcat JSSE-NIO connector,**client-side 用什么 HTTP 库**决定了出站 cipher 怎么控制:

### 5.1 `HttpURLConnection` / JDK 默认 HTTP Client

```java
URL url = new URL("https://<IP>/email-with-attachment-path");
HttpURLConnection conn = (HttpURLConnection) url.openConnection();
```

- cipher 列表由 **JRE 默认 cipher suite 顺序** 控制
- 受 `-Dhttps.cipherSuites=...` 系统属性 / `https.cipherSuites` security property / `setEnabledCipherSuites()` 调用影响
- **不**经过 Netty

### 5.2 Spring `RestTemplate`(默认 `SimpleClientHttpRequestFactory`)

```java
RestTemplate rt = new RestTemplate();  // 默认走 HttpURLConnection
```

- 同 5.1,跟 Netty 无关
- 如果换成 `HttpComponentsClientHttpRequestFactory`(Apache HttpClient)或 `OkHttp3ClientHttpRequestFactory`,则由那些库控制

### 5.3 Spring `WebClient`(Reactor Netty)

```java
WebClient client = WebClient.builder().build();  // 默认 Reactor Netty HttpClient
```

- cipher 由 **Netty `SslContext`** 控制
- 默认配置是 JDK 的 cipher 列表 + Netty 的 SslContext 包装
- 这条路径**才会**踩 CVE-2026-50010(Netty hostname verify bypass)

### 5.4 Apache HttpClient / OkHttp / 自研 client

各自有自己的 SSL context 配置,不经过 Netty,**也不经过 JDK 默认 JSSE**

**先确认 Java 应用出站调用用的是 5.1 / 5.2 / 5.3 / 5.4 中的哪一种**——这个直接决定修法路径。

---

## §6 5 分钟定位:确认到底用的哪个 client / JRE 是否支持

### 6.1 静态定位(在 Pod 里)

```bash
# 1. 看 JRE 版本
java -version 2>&1
# 期望看到:JDK 8uXYZ / JDK 11.0.XYZ / JDK 17.XYZ

# 2. 看 JCE Unlimited Strength 是否安装(影响 256-bit cipher)
ls $JAVA_HOME/jre/lib/security/ 2>/dev/null || ls $JAVA_HOME/lib/security/
# 看有没有 US_export_policy.jar + local_policy.jar(JCE 替换标记);
# 或者直接看是否启动参数里有 -Djava.security.properties=...

# 3. 看默认 cipher 列表(Java 8+)
java -Djava.security.properties==/dev/null \
  -cp $(find $JAVA_HOME/lib -name "jsse.jar" 2>/dev/null) \
  com.sun.net.ssl.checker 2>&1 | head -5   # 工具不一定在,跳过即可

# 4. 用 openssl 看 JRE 实际 client hello(需要从 Pod 出口 dial 第三方)
# 但这要起一个 Java 小程序,见 §6.3
```

### 6.2 启用 SSL debug 看握手细节(强推,5 分钟出真相)

在 Java 启动参数加:

```
-Djavax.net.debug=ssl,handshake
```

**重启应用** → 重现调用 → 在 stdout/stderr 里能看到:

```
*** ClientHello, TLSv1.2
Cipher Suites: [TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384, TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
                TLS_RSA_WITH_AES_256_CBC_SHA256, TLS_RSA_WITH_AES_128_CBC_SHA256,
                TLS_RSA_WITH_AES_256_CBC_SHA, TLS_RSA_WITH_AES_128_CBC_SHA, ...]   ← 你 JRE 支持的全部
...
*** ServerHello, TLSv1.2
Cipher Suite: TLS_RSA_WITH_AES_256_CBC_SHA   ← 第三方 server 选了一条
... 但实际你会在 ServerHello 之后看到:
Received fatal alert: handshake_failure
```

**两种典型结局**:

```
结局 1 — ServerHello 之后才挂:
  ServerHello 选了某条 cipher,但后续证书链校验或 key exchange 失败
  → 通常是 cert chain 问题或 hostname mismatch(跟 CVE-2026-50010 相关)
```

```
结局 2 — ClientHello 之后立刻挂(更常见于 cipher 不匹配):
  *** ClientHello, TLSv1.2
  Cipher Suites: [<你的 JRE 支持的全部>]
  (no ServerHello)            ← 没有!server 直接回 alert:handshake_failure
  Received fatal alert: handshake_failure
  → 经典 cipher 不匹配场景
```

**只看结局 2 的 client cipher suite 是否包含第三方 enabled list 任意一条**:
- 如果 0 交集 → JRE 太老,或 JCE 没装
- 如果有交集但还失败 → 看是不是 client 顺序里被禁了(SSL 黑名单),或 server 实际又限制了别的

### 6.3 用 openssl s_client 反向探测第三方支持(从 Pod 内或外部)

```bash
# 从 Pod 出口 dial 第三方,openssl 给一份 client hello,看 server 选哪条 cipher
echo "" | openssl s_client \
  -connect <IP_ADDRESS>:443 \
  -servername <THIRD_PARTY_SNI_IF_ANY> \
  -tls1_2 \
  -cipher "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:..." \
  </dev/null 2>&1 | grep -E "Cipher\s+:|verify return"

# 把第三方 enabled 的所有 cipher 写进 -cipher,看 server 是否能选
# 如果 openssl 都协商不出来,Java 也不可能协商出来
```

如果 openssl 能选出来(比如选 `ECDHE-RSA-AES128-GCM-SHA256`),Java 应该也能——除非 JRE 不支持 GCM。

---

## §7 修法(由轻到重 4 种,按业务约束选)

### 修法 A:升级 JRE(根治,推荐)

第三方用的是 TLSv1.2 + 现代 ECDHE cipher set,**任何 JDK 8u161+(2018-01 发布)+ / JDK 11+ 都默认支持**。如果你们应用在老 JRE(JDK 8u60 以下 / JDK 7),升 JRE 是最干净的修法:

| JRE 状态 | 第三方 enabled list | 默认交集 | 修法 |
|---------|-------------------|---------|------|
| **JDK 8u60 及以下** | 8 条 | 0 条(老 JRE 默认 cipher 不含 SHA256)| **升级到 JDK 8u401+(8 系列最新版)** |
| **JDK 8u161 ~ JDK 8u201**(没装 JCE Unlimited)| 8 条 | 2 条(只 128-bit GCM/CBC-SHA256)| 装 JCE Unlimited Strength,256-bit cipher 解锁 |
| **JDK 8u291+ / JDK 11.0.11+ / JDK 17+** | 8 条 | 8 条 | ✅ 不需要改任何代码 |
| **JDK 11/17,默认配置** | 8 条 | 8 条 | ✅ 不需要改任何代码 |

**注意**:升级 JRE 不一定要升 Spring Boot——Spring Boot 3.5.16 要 Java 17+,但 Spring Boot 2.x / 1.x 都能在 JDK 17 上跑。如果业务上 Spring Boot 不能升,**JRE 可以单独升**(虽然有方法废弃 warning 需要清,但比升 Spring Boot 改动小)。

### 修法 B:装 JCE Unlimited Strength(5 分钟,不动 JRE 大版本)

如果你们 lock 在某个老 JRE 但能打补丁:

```bash
# JDK 8
# 1. 下载对应版本的 JCE(8u161 之后已默认装在 JDK 里,不需要再装;这步针对 8u60~8u151 区间)
# 2. 直接验证是否已有 unlimited:
java -cp $(find $JAVA_HOME -name "sunjce_provider.jar") \
  -Djava.security.properties==$JAVA_HOME/jre/lib/security/java.security 2>&1 \
  | grep "crypto.policy"
# 输出 unlimited → 已装
# 输出 limited → 需要替换 local_policy.jar / US_export_policy.jar
```

或者在启动参数直接强制 unlimited:

```
-Djava.security.properties==/path/to/custom.java.security
# custom.java.security 里写:
# crypto.policy=unlimited
```

### 修法 C:代码侧显式指定 cipher(可控性最高,但有副作用)

如果不想动 JRE,在 HTTP client 初始化处显式设:

**HttpURLConnection / HttpsURLConnection**:

```java
URL url = new URL("https://<IP>/email-with-attachment-path");
HttpsURLConnection conn = (HttpsURLConnection) url.openConnection();
// 跟第三方 enabled list 对齐,加 SHA256 变体
conn.setEnabledCipherSuites(new String[] {
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_RSA_WITH_AES_128_CBC_SHA256",
    "TLS_RSA_WITH_AES_256_CBC_SHA256"
});
```

**Spring RestTemplate**(基于 HttpURLConnection):

```java
HttpClient httpClient = HttpClient.newBuilder()
    .sslContext(SSLContext.getInstance("TLSv1.2"))  // 强制 TLSv1.2
    .build();
```

**Spring WebClient**(Reactor Netty):

```java
import io.netty.handler.ssl.SslContextBuilder;
import io.netty.handler.ssl.SslProvider;

SslContext sslContext = SslContextBuilder.forClient()
    .sslProvider(SslProvider.JDK)  // 用 JDK 的 SSL stack,不是 OpenSSL
    .ciphers(Arrays.asList(
        "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
        "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
        "TLS_RSA_WITH_AES_128_CBC_SHA256",
        "TLS_RSA_WITH_AES_256_CBC_SHA256"
    ))
    .build();

HttpClient httpClient = HttpClient.create()
    .secure(spec -> spec.sslContext(sslContext));

WebClient client = WebClient.builder().clientConnector(
    new ReactorClientHttpConnector(httpClient)
).build();
```

⚠️ **副作用**:硬编码 cipher 列表会让应用在第三方再次升级 cipher 策略时再挂一次。**建议只在过渡期用**。

### 修法 D:HTTP 客户端库升级(如果用的是 Netty 客户端,顺便治 CVE-2026-50010)

如果 Java 应用出站用的是 `WebClient` / Reactor Netty HttpClient,那升 Netty 确实**顺便**修了 CVE-2026-50010;但**这次 handshake_failure 不需要 Netty 升级**——只要 JRE 跟第三方 enabled list 有交集就行。Netty 升级路径详见 `fix-spring-boot-3-5-16-remove-netty-overrides.md`。

**对照总结**:

| 修法 | 治本次 handshake_failure? | 顺便治 CVE-2026-50010? | 顺便治 PrematureClose race? |
|------|-------------------------|---------------------|-------------------------|
| **A. 升级 JRE** | ✅ | ❌(JSSE 不受 CVE 影响)| ❌ |
| **B. 装 JCE Unlimited** | ✅(只 256-bit 缺失时)| ❌ | ❌ |
| **C. 代码显式 cipher** | ✅ | ❌ | ❌ |
| **D. 升 Spring Boot 3.5.16 + 删 Netty override** | ❌(这次靠 JRE,不是 Netty) | ✅ | ✅ |

**结论**:**修法 A 或 B 治本次问题**;修法 D 治**别的两个问题**,需要单独执行,不要混为一谈。

---

## §8 平台侧(JK / Deployment 模板)可加的护栏

既然这个问题反复出现(每次第三方升级安全配置都可能触发),平台模板里建议加:

### 8.1 InitContainer 校验 JRE 默认 cipher 是否覆盖现代 TLSv1.2 集合

```yaml
initContainers:
  - name: jre-tls-check
    image: eclipse-temurin:17-jre
    command:
      - /bin/sh
      - -c
      - |
        java -version
        # 跑个最小 SSL probe,确认 JRE 支持 ECDHE-RSA-AES256-GCM-SHA384
        # 如果不支持,JRE 太老,init container 退出码 1,Pod 不会起来
```

(具体 probe 代码可以收成平台 init image,这里只示意)

### 8.2 在用户部署文档里加"出站 HTTPS 受限的常见原因"章节

告诉用户:

1. 第三方升级安全策略时,**老 JRE(8u60 以下 / 7 / 6)会 handshake_failure**——升 JRE 是 root cause
2. 不要用 `setEnabledCipherSuites(...)` 写死 cipher 列表到代码里——第三方再次升级会再挂
3. 如果一定要兼容老 cipher 列表,跟第三方对齐后**记入 deployment note**,作为已知约束

### 8.3 平台监控告警:outbound HTTPS handshake_failure 计数

第三方升级的当天,平台所有用户的出站调用可能集中失败。如果平台有 outbound HTTP 调用 metric(成功率 / 错误码分布),告警阈值调低一点,可以早发现。

---

## §9 给用户的完整回应(中英双语)

> 这一节是**可以直接转给用户/贴在工单上**的完整回应——包含定性、报告前需要确认的事实、Debug 步骤、以及职责说明。所有四个要点都会在 §9.1(中文)和 §9.2(English)分别给出。

---

### §9.1 中文版

#### 一句话定性

> 你看到的 `handshake_failure` 是 **Java 应用作为 TLS Client 跟第三方 server cipher 协商失败**,**不是** CVE-2026-50010(那是 hostname 校验被静默关掉,**不会**报 handshake_failure),**也不是** reactor-netty keep-alive race 那个问题(那是 server 端)。
>
> 直接原因是第三方按 II1711 升级了安全配置(关老 cipher、只允许 ECDHE/GCM/CBC-SHA256+),**触发了原本"双方都凑合能通"的旧 cipher 协商失败**——Java 应用那一侧的 **JRE cipher 列表跟第三方 enabled cipher 列表的交集变成 ∅**。很可能是 JRE 版本太老(8u60 以下)或 JCE Unlimited Strength 没装。

#### 报告前需要确认的事实

在给我们回报告之前,请先确认以下信息(这些是定位根因的最小事实集,缺一个就推不动):

1. **当前运行的 Java Application 版本**——具体说:
   - **JRE/JDK 版本**:在 Pod 内跑 `java -version 2>&1`,确认是 8uXXX / 11.0.X / 17.X.X
   - **Spring Boot 版本**:`pom.xml` 里 `spring-boot-starter-parent` 的版本号(影响是否走 Netty 客户端路径)
   - **出站调用用的 HTTP 客户端**:`HttpURLConnection` / `RestTemplate`(默认 HttpURLConnection)/ `WebClient`(Reactor Netty)/ `Apache HttpClient` / `OkHttp` 中的哪一个——这个直接决定修法路径,看 §5

2. **JCE Unlimited Strength 是否安装**——影响 256-bit cipher 是否可用(看 §4 场景 B)

#### Debug 步骤(如果可以登录 Java 终端)

如果你们能登录到 Java 应用所在的 Pod / 容器,**用 OpenSSL 命令做一次 debug**,看反馈:

```bash
# 在 Pod 内,或从 Pod 出口 dial 第三方 server
echo "" | openssl s_client \
  -connect <IP_ADDRESS>:443 \
  -servername <THIRD_PARTY_SNI_IF_ANY> \
  -tls1_2 \
  -cipher "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:RSA-AES128-CBC-SHA256:RSA-AES256-CBC-SHA256" \
  </dev/null 2>&1 | grep -E "Cipher\s+:|verify return|handshake failure"

# 把第三方 enabled list 的全部 cipher 写进 -cipher,看 server 实际选哪条:
#   - 如果能选出来(例如 ECDHE-RSA-AES128-GCM-SHA256)→ 第三方端没问题,
#     问题在你们 Java client 的 JRE 不支持这条
#   - 如果 openssl 都协商不出来 → 第三方 server 又改了策略,
#     需要重新要第三方的 enabled list
```

#### 修法(按业务约束选)

- **优先**:升 JRE 到 **JDK 8u401+ / 11+ / 17+**——默认就支持全部 enabled list,这是根治
- **备选**:装 JCE Unlimited Strength——只解决 256-bit cipher 不可用(如果你们 lock 在老 JRE 不能升大版本)
- **过渡期**:代码里显式 `setEnabledCipherSuites(...)` 写到跟第三方 enabled list 对齐——但这只是过渡方案,第三方再升级会再挂
- **不要**为了这个问题去升 Spring Boot 3.5.16 / Netty 4.1.135——那个修的是另一个独立问题(详见 §2 §3)

#### 职责说明(重要)

> **从职责分工来讲,这是用户 Client 代码里的问题,跟平台本身没有关系。**
>
> 平台这边提供的 Deployment 模板 / Ingress / TLS server 配置(`server.ssl.*` 那块)都是 Java 应用作 **TLS Server** 角色的配置——这一层没问题,所以 Pod 启动正常、入站 8443 接收请求正常。
>
> 出站调第三方是 Java 应用自己代码里发起的 outbound HTTPS 调用,**这一段用的是 Java 应用自己引入的 HTTP 客户端 + 自己运行时 JRE 的 cipher 列表**——平台既不持有这段代码,也不控制这个 JRE cipher 列表。
>
> 所以**需要用户从代码端(JRE 升级 / HTTP 客户端配置)来修复这个问题**——平台侧可加的护栏在 §8(InitContainer 校验 JRE cipher 能力、监控告警等),但**根因修复责任在用户自己**。

---

### §9.2 English Version

#### One-line summary

> The `handshake_failure` you are seeing is a **cipher suite negotiation failure between your Java application (acting as TLS Client) and the third-party server** — it is **NOT** CVE-2026-50010 (which silently disables hostname verification and **does not** produce a `handshake_failure`), and it is **NOT** the reactor-netty keep-alive race either (which is a server-side bug).
>
> The root cause is the third-party's II1711 security upgrade (disabling legacy ciphers, allowing only ECDHE/GCM/CBC-SHA256+), which **broke the previously-working-but-barely cipher negotiation** — the intersection between your Java application's JRE cipher list and the third-party's enabled cipher list is now **∅**. Most likely your JRE is too old (8u60 or earlier) or JCE Unlimited Strength is not installed.

#### Facts to confirm before reporting back

Before you reply with a report, please confirm the following minimum facts (we cannot proceed without them):

1. **Currently running Java Application version** — specifically:
   - **JRE/JDK version**: run `java -version 2>&1` inside the Pod, confirm whether it's 8uXXX / 11.0.X / 17.X.X
   - **Spring Boot version**: the `spring-boot-starter-parent` version in your `pom.xml` (determines whether the outbound path goes through Netty)
   - **Outbound HTTP client in use**: which of `HttpURLConnection` / `RestTemplate` (default HttpURLConnection) / `WebClient` (Reactor Netty) / `Apache HttpClient` / `OkHttp` — this directly decides which remediation applies (see §5)

2. **Whether JCE Unlimited Strength is installed** — affects whether 256-bit ciphers are available (see §4 scenario B)

#### Debug steps (if you can log into the Java terminal)

If you can log into the Pod / container where the Java application runs, **run an OpenSSL probe** and check the response:

```bash
# Inside the Pod, or dialing the third-party from the Pod's egress
echo "" | openssl s_client \
  -connect <IP_ADDRESS>:443 \
  -servername <THIRD_PARTY_SNI_IF_ANY> \
  -tls1_2 \
  -cipher "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:RSA-AES128-CBC-SHA256:RSA-AES256-CBC-SHA256" \
  </dev/null 2>&1 | grep -E "Cipher\s+:|verify return|handshake failure"

# Put all ciphers from the third-party's enabled list into -cipher and see which one
# the server actually picks:
#   - If it picks one (e.g. ECDHE-RSA-AES128-GCM-SHA256) → the third-party server is fine,
#     the problem is your Java client's JRE doesn't support it
#   - If even openssl cannot negotiate → the third-party has changed their policy again,
#     you need to re-request the enabled list from them
```

#### Remediation (pick by business constraint)

- **Preferred**: upgrade JRE to **JDK 8u401+ / 11+ / 17+** — defaults to supporting the entire enabled list, this is the root fix
- **Alternative**: install JCE Unlimited Strength — only solves the 256-bit cipher unavailability (if you are locked on an older JRE and cannot do a major upgrade)
- **Transition period**: explicitly call `setEnabledCipherSuites(...)` in code, aligned with the third-party's enabled list — but this is only a transitional solution; it will break again the next time the third-party upgrades
- **Do NOT** upgrade Spring Boot 3.5.16 / Netty 4.1.135 for this issue — those fix a different, independent problem (see §2 and §3)

#### Responsibility split (important)

> **From a responsibility perspective, this is a problem in the user's client-side code, not in the platform itself.**
>
> The platform-provided Deployment templates / Ingress / TLS server configuration (`server.ssl.*` block) are all configuration for the Java application acting as a **TLS Server** — that layer is fine, which is why the Pod starts up normally and the inbound 8443 listener works.
>
> The outbound call to the third-party is initiated by the Java application's own code, using **the HTTP client it pulls in + the cipher list from its own runtime JRE** — the platform neither owns this code nor controls this JRE cipher list.
>
> Therefore **the user must fix this from the code side** (JRE upgrade / HTTP client configuration) — platform-side guardrails are listed in §8 (InitContainer that validates JRE cipher capability, monitoring/alerting, etc.), but **the root cause remediation responsibility sits with the user**.

---

## §10 这个 fix 跟 java-auth 主题其他文档的关系

| 文档 | 修的层 | 触发现象 | 跟本次问题关系 |
|------|--------|---------|--------------|
| `fix-spring-boot-3-5-16-remove-netty-overrides.md` | reactor-netty server keep-alive race + Netty 4.1.135 CVE 修复 | server 端 `PrematureCloseException` + CVE-2026-50010 | **无关**(那个是 server race 和 hostname 校验) |
| `cve-2026-50010-netty-hostname-verification-bypass.md` | Netty client hostname verification bypass | 不报错,被静默 MitM | **无关**(那是 hostname 校验,这是 cipher 协商)|
| `gke-pod-cert-vs-cve-2026-50010-diagnosis.md` | 区分 Kong DP → Pod 链路上的 cert / hostname 问题 | Kong DP 报错 hostname mismatch | **无关**(那是 server 端 cert SAN 缺失)|
| **`pod-curl.md`(本文件)** | **Java client → 第三方 server 的 cipher 协商** | **`handshake_failure`,不协商到 cipher** | **✅ 本次问题** |
| `java-application-auth.md` | Spring Boot YAML 的 server.ssl / client ssl 角色区分 | `Alias does not identify a key entry` | 互补(本文件是 client 侧运行时问题,java-application-auth 是 server 侧启动期问题)|

---

## §11 关键 takeaway

1. **`handshake_failure` ≠ `hostname mismatch` ≠ `PrematureCloseException`** —— TLS 协议栈报错有很多层,精确层定位决定修法路径
2. **Java 应用作 client 的 cipher 列表 = JRE 默认 + 代码 setEnabledCipherSuites 覆盖** —— 出站调用受 JRE 影响,**跟 server.ssl.* 配置完全无关**(那个只管 server 侧入站)
3. **第三方安全升级 = client cipher 必须升级** —— 任何时候第三方升级 TLS 配置,所有老 JRE 客户端会同时挂;**JRE 升级是 client 侧 TLS 兼容性问题的 root fix,不要试图在代码里写死 cipher 列表绕**
4. **CVE-2026-50010 是 hostname 层漏洞,跟 cipher 层完全不沾边** —— 别因为它们都是"Netty TLS"就误判为同一类问题

---

## Sources

[1] https://cvereports.com/reports/CVE-2026-50010 — CVE-2026-50010 - Netty TLS Hostname Verification Bypass(本文 §2 反向判别 CVE 的引用)

### Related docs in this repo

- `develop/java/java-auth/fix-spring-boot-3-5-16-remove-netty-overrides.md` —— reactor-netty server keep-alive race + CVE-2026-50010 的修法(本次问题无关)
- `develop/java/java-auth/cve-2026-50010-netty-hostname-verification-bypass.md` —— CVE-2026-50010 全文中文翻译(本次问题无关)
- `develop/java/java-auth/gke-pod-cert-vs-cve-2026-50010-diagnosis.md` —— Kong DP → Pod 链路上 cert SAN 不匹配排查(本次问题无关)
- `develop/java/java-auth/java-application-auth.md` —— Spring Boot server.ssl vs client.ssl 角色区分(互补)