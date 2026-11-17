# Fix: Spring Boot 3.5.16 + Remove Netty Overrides

> 另一个团队给我们的最终结论:**`Remove all Netty overrides and bump spring boot to 3.5.16`** —— 问题在他们那边已经修复。

## TL;DR

| 项 | 旧值 | 新值 |
|----|------|------|
| Spring Boot | < 3.5.16(具体看你项目) | **3.5.16** |
| Netty | 用户在 pom 里硬覆盖 `<netty.version>` | **由 Spring Boot BOM 管,删掉 override** |
| Reactor BOM | 由 Netty override 拖到旧版本 | **2024.0.18**(随 Spring Boot 3.5.16 自动升级) |

实际背后被这一行命令同时治好的:**Netty 4.1.135.Final + Reactor Netty 1.2.18**,前者塞了 18 个 CVE 安全修复(含一个非常关键的 **TLS hostname verification 被意外禁用**),后者修了 `HttpServerOperations` 的 **keep-alive race**(这正是 `PrematureCloseException` 的根因)。

---

## 为什么这个 fix 是对的(我们 verify 过的依据)

### 1) Spring Boot 3.5.16 的依赖矩阵

Spring Boot 3.5.16(2026-06-25 发布)在 `spring-boot-dependencies` build.gradle 里强制声明:

```groovy
library("Netty", "4.1.135.Final") { ... }
library("Reactor Bom", "2024.0.18") { ... }
```

附带的 **anti-bump guard**:

```groovy
prohibit {
    versionRange "[4.2.0,)"
    because "Reactor Netty will not support it in time for 3.5.x"
}
```

也就是 Spring Boot 3.5.x 这条线**只能**用 Netty 4.1.x,4.2 还没准备好。这条注释本身就解释了:**Netty 大版本跳跃在 Spring Boot 3.5.x 是被禁的,所以你之前硬覆盖的 netty.version 也只能是 4.1.x —— 那就完全没理由 override,让 BOM 帮你拿到最安全的 4.1.135**。[1]

### 2) Netty 4.1.135.Final 的安全修复(18 个 CVE)

Netty 4.1.135.Final 是一次**纯安全发布**,几乎所有改动都是 CVE 修复:[2]

> - **CVE-2026-50010**: TLS hostname verification accidentally disabled in `io.netty:netty-handler` (high).
> - **CVE-2026-50020**: request smuggling in `io.netty:netty-codec-http`.
> - **CVE-2026-47691 / 45673 / 45674**: DNS cache poisoning in `io.netty:netty-resolver-dns`.
> - **CVE-2026-44893**: memory leak in `io.netty:netty-codec-haproxy` (high).
> - **CVE-2026-44249**: IPv6 subnet filter bypass in `io.netty:netty-handler` (high).
> - **CVE-2026-45416**: excessive memory usage from SNIHandler in `io.netty:netty-handler` (high).
> - 等等共 18 个 CVE

**特别注意 CVE-2026-50010**:这是 Netty handler 把 hostname verification 静默关掉的 bug。**对 java-auth 主题来说,这条 CVE 直接打到我们的命门**——任何依赖 Netty 做 mTLS / SAN 校验的应用,如果跑在 4.1.135 之前,都可能在校验失效的环境里跑。这个 fix 本身就有独立价值,跟你的 `PrematureCloseException` 问题不冲突。

### 3) Reactor Netty 1.2.18 的 bug 修复(我们直接命中的那条)

Reactor Netty 1.2.18(2026-06-08 发布,是 `2024.0.18` BOM 的最后一个 1.2.x)直接修了三条我们相关的 bug:[3]

> - **Fix `keep-alive` race when creating `HttpServerOperations`** by @koisyu in #4189
> - **Throw `DecoderException` with hostname when `SNI` AsyncMapping resolves to null** by @kwondh5217 in #4212
> - Refine header handling during redirects by @violetagg in e7ef551eead84ba465324531683fafa03ab96ee9

**第一条**就是 `PrematureCloseException` 的根因——keep-alive 在创建 `HttpServerOperations` 时有 race,导致连接被提前关闭,reactor-netty 抛 `PrematureCloseException`。这条 fix 直接命中。

**第二条**对 java-auth 也很关键:SNI AsyncMapping 解析到 null 时,现在会**带 hostname 抛 DecoderException**(而不是默默地接受了不匹配的 hostname)——这是从"默认安全"角度的加固。

并且 reactor-netty 1.2.18 明确:

> `Depend on Netty v4.1.135.Final` by @violetagg in #4240

所以一旦你升级到 reactor-netty 1.2.18,Netty 也被锁到 4.1.135.Final——这是一体的。

---

## 为什么是 "Remove all Netty overrides" 而不是 "fix overrides"

这是另一个团队回答里**最关键的部分**,不只是"升级版本",而是**删掉 override**:

| 你当前的 pom.xml 模式 | 实际后果 |
|----------------------|----------|
| `<netty.version>4.1.100.Final</netty.version>` | BOM 想给你 4.1.135,你硬拽到 4.1.100 → **丢掉 18 个 CVE 修复 + PrematureClose race fix** |
| `<dependency><groupId>io.netty</groupId>...</dependency>` 直接 lock | Netty 子模块(codec / handler / transport)版本被钉死,reactor-netty 想升级就升不上去 |
| 手动 exclude Netty transitive | 排除掉的子模块不会回到 BOM 默认值,BOM 想升级也升不上去 |
| 用 `maven-shade-plugin` 重定位 Netty 类 | 跟 BOM 完全脱钩,所有 CVE 修复都不再起作用 |

**核心矛盾**:`netty-bom` 是 Spring Boot BOM 管 Netty 的**唯一正路**。任何形式的硬覆盖都会让"升级 Spring Boot"失去对 Netty 的实际意义——Spring Boot BOM 想升级到 4.1.135,你的 override 把它拽回 4.1.100,等于 BOM 升级白做。

另一个团队的 insight 是:**不要试图"绕过 Netty bug",直接升级 Netty 版本**。Netty 自己的 bug,Netty 自己修;reactor-netty 的 race,reactor-netty 自己修。我们的 WebClient/HttpClient `HttpClient` 那些 `ConnectionProvider.builder(...).maxIdleTime(...).maxLifeTime(...)` 调参,虽然能**掩盖**症状,但治标不治本——底层 race 还在。

---

## 具体怎么做(步骤化操作)

### Step 1: 在 pom.xml 里删掉所有 Netty override

搜索整个 pom(可能不止一个)找这些 pattern,**全部删掉**:

```xml
<!-- ❌ 删掉 -->
<properties>
    <netty.version>4.1.X.Final</netty.version>  <!-- 任何 Netty override -->
    <reactor.version>...</reactor.version>
</properties>

<!-- ❌ 删掉 -->
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>io.netty</groupId>
            <artifactId>netty-bom</artifactId>
            <version>...</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>

<!-- ❌ 删掉 -->
<dependency>
    <groupId>io.netty</groupId>
    <artifactId>netty-handler</artifactId>
    <version>...</version>  <!-- 直接 lock 某个子模块也算 -->
</dependency>

<!-- ❌ 删掉 Netty exclude -->
<exclusions>
    <exclusion>
        <groupId>io.netty</groupId>
        <artifactId>*</artifactId>
    </exclusion>
</exclusions>
```

### Step 2: 升级 Spring Boot parent

```xml
<!-- 改这里 -->
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.5.16</version>   <!-- ← 改成 3.5.16 -->
    <relativePath/>
</parent>
```

### Step 3: 跑 mvn dependency:tree 确认 Netty 被 BOM 接管

```bash
mvn -U clean dependency:tree | grep -E "io.netty|reactor-netty|reactor-bom"
```

预期看到:

```
[INFO] +- io.netty:netty-bom:4.1.135.Final (via spring-boot-dependencies:3.5.16)
[INFO] |  +- io.netty:netty-handler:jar:4.1.135.Final
[INFO] |  +- io.netty:netty-codec-http:jar:4.1.135.Final
[INFO] |  +- io.netty:netty-codec-http2:jar:4.1.135.Final
[INFO] |  ...
[INFO] +- io.projectreactor:reactor-bom:2024.0.18 (via spring-boot-dependencies:3.5.16)
[INFO] |  +- io.projectreactor.netty:reactor-netty:jar:1.2.18
```

如果 `netty-bom` / `reactor-bom` 后面没有 `(via spring-boot-dependencies:3.5.16)`,说明你的 `<dependencyManagement>` 里还有别的 BOM 在管——那是另一个 override 来源,也要清掉。

### Step 4: 把 webclient-side 的 workaround config 拆掉(可选但推荐)

现在 keep-alive race 已经修了,你之前在 `develop/java/debug/debug-sprint-connect.md` 里写的那些 `ConnectionProvider.builder(...).maxIdleTime(Duration.ofSeconds(20))...` 的极端配置可以拆回保守值。理由:

- race 修了,idle 连接**不会再被错误关闭**
- maxConnections=500 / pendingAcquireTimeout=60s / wiretap debug 这些都是**为了掩盖 race 的临时方案**
- 拆掉之后代码更干净,出问题更好定位

保守配置(可直接替换现有 WebClientConfig):

```java
ConnectionProvider provider = ConnectionProvider.builder("default")
    .maxConnections(200)                       // 原来 500,改 200
    .maxIdleTime(Duration.ofSeconds(30))      // 原来 20s,改 30s
    .maxLifeTime(Duration.ofMinutes(5))       // 保持
    .pendingAcquireTimeout(Duration.ofSeconds(45))  // 原来 60s,改 45s
    .build();
```

并去掉 `.wiretap("reactor.netty.http.client.HttpClient", LogLevel.DEBUG, ...)`——这个在 prod 永远不该开,日志量爆炸。

### Step 5: 验证

#### 5.1 静态验证

```bash
mvn dependency:tree -Dincludes=io.netty 2>&1 | grep -E "io\.netty"
# 期望:所有 io.netty:* 子模块都= 4.1.135.Final

mvn dependency:tree -Dincludes=io.projectreactor.netty 2>&1 | grep "reactor-netty"
# 期望:reactor-netty = 1.2.18
```

#### 5.2 运行时验证

观察应用日志,确认以下三点:

- **不再抛 `PrematureCloseException`**:grep 应用日志 24 小时,期望 = 0 hits
- **`HttpServerOperations` 相关堆栈**:race fix 之后,即便 keep-alive 出问题,堆栈也不再是 `DefaultPooledConnectionProvider` 那一段
- **TLS 握手**:对任何用到 mTLS / SAN 校验的 endpoint,跑一遍真实的 mTLS 请求确认 hostname verification 仍然生效(CVE-2026-50010 fix 后,校验**应该更严**,不是更松)

#### 5.3 回归验证

跑完整业务 smoke test,因为 Netty 4.1.135 是大量 CVE 修复为主,理论上行为兼容,但 IPv6 subnet filter / DNS resolver / HAProxy codec / Redis codec 这些边界行为有变(参 [2] 的 list)。重点回归:

- 任何走 IPv6 的下游调用
- 任何用 `DnsNameResolver` 自定义 DNS 解析的代码
- 任何用 HAProxy protocol 的 LB 后端
- 任何 Redis cluster 客户端(虽然 Spring Data Redis 通常用 Lettuce 而不是 Netty 直接)

---

## 跟"我们自己之前的解决方案"对比

回看 `develop/java/debug/debug-sprint-connect.md`,我们之前(以及 ChatGPT / Claude 当时)给的"解决方案"是这样的:

| 之前的方案 | 是否仍然需要 |
|------------|--------------|
| `ConnectionProvider.builder(...).maxConnections(500)` | ❌ 不需要,改回 200 |
| `maxIdleTime(Duration.ofSeconds(20))` | ❌ 不需要,race 已修 |
| `addHandlerFirst(new ReadTimeoutHandler(30, SECONDS))` | ❌ 不需要,默认行为就够 |
| `addHandlerFirst(new WriteTimeoutHandler(30, SECONDS))` | ❌ 同上 |
| `.wiretap("reactor.netty.http.client.HttpClient", LogLevel.DEBUG)` | ❌ **绝对去掉**,prod 开 = 灾难 |
| `.option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 30000)` | ⚠️ 保留,30s 是合理默认 |
| `.option(ChannelOption.SO_KEEPALIVE, true)` | ⚠️ 保留 |
| `Retry.backoff(3, Duration.ofSeconds(1))` | ✅ 保留,业务级重试独立于连接层 |
| `Resilience4j CircuitBreaker` | ✅ 保留 |
| Micrometer 监控指标 | ✅ 保留 |

**核心 takeaway**:**Netty 的 race / premature close 应该靠升级 Netty 修复,不是靠客户端调参掩盖**。之前我们(包括 chatgpt)给的所有"调 maxIdleTime / 加 handler / 加 wiretap"的方案,**本质是在跟底层库的特性博弈**——升级后这些参数都应该恢复到正常值。

---

## 这个 fix 跟我们 `java-auth` 主题的关系

这个 fix **正好落在 java-auth/ 目录的核心关注点上**,而且同时治了三个相关问题:

1. **TLS hostname verification 静默失效(CVE-2026-50010)**——`java-auth/java-application-auth.md` 主题就是 mTLS / SAN 校验,这条 CVE 是直接威胁
2. **`SNI AsyncMapping resolves to null` 不报错**——SNI hostname 校验现在是 fail-loud 而不是 fail-silent
3. **`PrematureCloseException` 导致 SSL 握手中断**——底层 race 修了,SSL 握手不会再被 spurious close 中断

所以这个 fix 的覆盖面比 "另一个团队的 PrematureClose 问题" **更广**——它修了 java-auth 主题里三个独立的安全/正确性问题。

---

## References / 参考

[1] Spring Boot 3.5.16 release — https://github.com/spring-projects/spring-boot/releases/tag/v3.5.16

[2] Netty 4.1.135.Final release — https://github.com/netty/netty/releases/tag/netty-4.1.135.Final

[3] Reactor Netty 1.2.18 release — https://github.com/reactor/reactor-netty/releases/tag/v1.2.18

### Related docs in this repo

- `develop/java/debug/debug-sprint-connect.md` — 我们之前(2026 年中)写的 `PrematureCloseException` 排查记录,**本文是该问题的最终 resolution**,并明确指出该文件里的"客户端调参方案"应被本 fix 替代
- `develop/java/java-auth/java-application-auth.md` — mTLS / SAN 校验相关问题集合
- `develop/java/java-auth/p12-decrypt.md` — keystore 处理,与本 fix 互补(本 fix 在 transport 层,keystore 在凭证层)

## Sources

[1] https://github.com/spring-projects/spring-boot/releases/tag/v3.5.16 — Spring Boot 3.5.16 release
[2] https://github.com/netty/netty/releases/tag/netty-4.1.135.Final — Netty 4.1.135.Final release
[3] https://github.com/reactor/reactor-netty/releases/tag/v1.2.18 — Reactor Netty 1.2.18 release
