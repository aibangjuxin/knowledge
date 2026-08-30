# GKE Pod — 验证 Java 应用实际启用的 HTTPS 证书

> **一句话**: GKE 里跑着一个 Java 应用,你不知道它**到底有没有启用 HTTPS**、**用的哪张证书**、**证书是从哪个 keystore 加载的**。本文按你能拿到多少访问权限,给出 3 个递进场景的验证方法,以及**代码层** Spring Boot 是怎么挑证书的。

## 适用场景

- Java 应用部署在 GKE Pod 里,`server.port: 8443`(或 8080/443 配 SSL)
- 你怀疑: 启动参数里写了 `ssl.enabled=true` 但实际没生效 / 用了 platform 默认证书而非用户自定义证书 / 加载的 keystore 跟用户提交的不一致
- 经典报错: `Alias name [xxx] does not identify a key entry`(见 `../java-application-auth.md`)

## TL;DR — 30 秒决策表

| 你的访问权限 | 第一步做什么 | 引用 |
|---|---|---|
| 能 `kubectl exec` 进 Pod | 看进程实际加载的 keystore + 启动参数 | [01: 能 exec 进 Pod](references/01-shell-access-strategies.md#场景-1-能-kubectl-exec-进-pod) |
| 不能 exec,但有 keystore 文件(JAR / ConfigMap / PV) | 用 `keytool`/`openssl` 离线解析 | [02: 能拿到 keystore 文件](references/01-shell-access-strategies.md#场景-2-不能-exec-但能拿到-keystore-文件) |
| 只能看到 Service 暴露的端口 | 从外部 dial 端口,验证书指纹 | [03: 只能从外部访问](references/01-shell-access-strategies.md#场景-3-只能从外部访问-看不到-pod-内部) |
| 想搞清楚代码层到底是怎么挑证书的 | 看 `application.yml` 的 `server.ssl.*` + Java 代码 | [03: Spring Boot SSL 加载机制](references/03-spring-boot-yaml-ssl-anatomy.md) |
| 客户端用域名访问 Pod 时报 `err 62` / hostname mismatch;绑 IP 通 | 看 Pod cert 的 SAN 跟客户端访问域名对不对得上 | [04: SAN 不匹配自检](references/04-san-mismatch-hostname-verify.md) |
| **Java 应用出站调第三方 HTTPS 报 `handshake_failure`**(入站 8443 没事) | 看 JRE cipher 列表 ∩ 第三方 enabled cipher 列表 | [05: 出站 cipher 协商失败](references/05-outbound-https-cipher-mismatch.md) |

## 详细目录

1. **[01 — shell 访问策略与 3 场景实战](references/01-shell-access-strategies.md)**
   - 场景 1: 能 `kubectl exec`(最强证据)
   - 场景 2: 不能 exec,但能拿到 keystore 文件(JAR / ConfigMap / Secret / PV)
   - 场景 3: 只能从外部访问 — 从 Service/NodePort dial 进去

2. **[02 — keytool + openssl 命令速查](references/02-keytool-openssl-cheatsheet.md)**
   - JKS / PKCS12 / PEM 三种格式的 inspect / dump / 转换
   - 拿到证书后该看的 5 个字段:Subject / Issuer / SAN / Validity / Fingerprint
   - 怎么把 `keytool` 的输出对齐 `openssl s_client` 的输出

3. **[03 — 代码层:Spring Boot SSL 是怎么挑证书的](references/03-spring-boot-yaml-ssl-anatomy.md)**
   - `server.ssl.key-store` / `key-alias` / `key-store-type` 各自的作用
   - 证书加载的代码路径:`TomcatServletWebServerFactory` → `SslConnectorFactory`
   - 自定义证书 vs Platform 默认证书的优先级
   - 跟 `../java-application-auth.md` 里 `team_a_env_server` 报错的根因复盘

4. **[04 — 客户端用域名访问 Pod 时报证书错,但绑 IP 又能通 — SAN 不匹配自检](references/04-san-mismatch-hostname-verify.md)**
   - 入站方向(客户端 → Pod)的 hostname 校验失败
   - 跟 CVE-2026-50010 的精确区分(报 err 62 = 校验在工作 ≠ CVE)

5. **[05 — Java 应用调第三方 HTTPS 报 `handshake_failure` — cipher 协商失败(出站方向)](references/05-outbound-https-cipher-mismatch.md)** *(2026-08-30 新增)*
   - **方向**:出站(Java 应用作为 TLS Client 调第三方),跟前 4 篇(入站 Server 角色)**反方向**
   - **现象**:Java 应用作 Server(8443)正常,但作 Client 出站调第三方时 `SSLHandshakeException: handshake_failure`
   - **根因**:Java JRE 默认 cipher 列表 ∩ 第三方 enabled cipher 列表 = ∅(第三方按 II1711 等升级了安全配置)
   - **修法**:升 JRE 到 8u401+ / 11+ / 17+,或装 JCE Unlimited Strength,或代码显式 `setEnabledCipherSuites(...)`
   - **常见误判**:跟 CVE-2026-50010 无关、跟 reactor-netty race 无关 —— 升 Netty / Spring Boot 治不了本次问题

## 同目录相关资源

- [`../java-application-auth.md`](../java-application-auth.md) — Spring Boot YAML SSL 双角色 + 报错分析
- [`../p12-decrypt.md`](../p12-decrypt.md) — `.p12.pwd` 文件末尾换行符导致 `Decryption failed` 的坑
- [`../simple-https-demo/`](../simple-https-demo/) — 一个最小的 Spring Boot HTTPS demo,带 `server-keystore.p12`,可以直接照着命令跑一遍本文所有验证步骤

## 验证 — 怎么证明这份文档自己是对的

| 验证项 | 方法 | 预期 |
|---|---|---|
| `keytool` 命令在本机可用 | `keytool -help` | JDK 已安装 |
| `openssl s_client` 可用 | `openssl version` | OpenSSL 已安装(macOS 自带) |
| `simple-https-demo/` 的 keystore 真的存在 | `keytool -list -v -keystore ../simple-https-demo/src/main/resources/ssl/server-keystore.p12 -storepass changeit` | 看到 `Alias name: server` + 1 个 `PrivateKeyEntry` |
| 文档里所有命令都能在本机 demo 复现 | 跑 `cd ../simple-https-demo && ./generate-cert.sh && mvn spring-boot:run` | 8443 端口监听,`curl -k https://localhost:8443/hello` 返回 200 |