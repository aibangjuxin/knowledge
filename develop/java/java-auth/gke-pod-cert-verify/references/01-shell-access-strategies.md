# 01 — GKE Pod 证书验证:3 种访问权限场景的实战策略

> 同一个问题「Pod 里的 Java 应用实际用了哪张证书」,按你**能拿到的访问权限**分成 3 个场景。每个场景的命令按"由强证据到弱证据"排序,执行到能定结论即可停。

---

## 场景 1:能 `kubectl exec` 进 Pod

**这是最强证据链**。你能直接看到进程状态、加载的文件、监听的端口。

### 1.1 确认你能 exec + 找到目标容器

```bash
# 多容器 Pod(InitContainer / sidecar),先看有几个容器
kubectl -n <NAMESPACE> get pod <POD_NAME> -o jsonpath='{.spec.containers[*].name}'

# exec 进去,指定容器名
kubectl -n <NAMESPACE> exec -it <POD_NAME> -c <CONTAINER_NAME> -- /bin/sh
```

如果 shell 不进来(常见:镜像用的是 `distroless` / `scratch` / `ubi-minimal` 不带 shell),见 §1.6 的 fallback。

### 1.2 在 Pod 内 — 拿到 Java 进程的真实启动参数

Pod 内的 `ps` 经常被精简镜像裁掉,优先用 `/proc`:

```bash
# 1) 找到 java 进程的 PID(可能有多个,选 main class)
ls /proc/ | grep -E '^[0-9]+$' | while read pid; do
  if [ -r /proc/$pid/comm ] && grep -q java /proc/$pid/comm 2>/dev/null; then
    echo "PID=$pid CMD=$(cat /proc/$pid/cmdline | tr '\0' ' ')"
  fi
done

# 2) 更精确 - 看 main class / JAR 名
PID=<your-java-pid>
cat /proc/$PID/cmdline | tr '\0' '\n'
# 通常能看到: java -Djavax.net.ssl.keyStore=... -jar app.jar
```

**重点关注这些 JVM 启动参数**:

| 参数 | 含义 |
|---|---|
| `-Djavax.net.ssl.keyStore=<path>` | 全局 keystore(Spring Boot 一般不用这个) |
| `-Djavax.net.ssl.keyStorePassword=<pwd>` | 上面那个 keystore 的密码 |
| `-Dserver.port=<port>` | 启动端口(可能跟 YAML 不一致 — 平台可能 override) |
| `--server.port=<port>` | Spring Boot 风格的命令行参数,优先级**最高** |
| `--server.ssl.key-store=<path>` | **Spring Boot 的 keystore 路径,最高优先级** |
| `--server.ssl.enabled=true` | 启用 HTTPS |

**关键规则**:**命令行参数(`--server.port=8443`)会覆盖 `application.yml` 里的 `server.port`**。如果平台 Deployment 模板在启动脚本里注入了 `--server.port=8443`,即使你的 JAR 里写的是 8080,实际启用的还是 8443。这是排查"我配了 8080 但服务监听了 8443"的根因。

### 1.3 在 Pod 内 — 拿到 keystore 文件并校验

```bash
# 1) 找 keystore 文件(常见路径)
find / -name '*.jks' -o -name '*.p12' -o -name '*.pfx' 2>/dev/null
# 也可能在 classpath 里 — 通过 jar 工具拆开看

# 2) 如果在 JAR 内(最常见 — 用户自定证书打成 JAR 的 resources/)
#    解到 /tmp 再 inspect
unzip -p /app/app.jar BOOT-INF/classes/CertKey/team_a_env_server.jks > /tmp/server.jks

# 3) 检查文件是否存在 + 大小
ls -la /tmp/server.jks
# 0 字节 = 文件被打包丢了 / Secret 没挂上
# 非 0 但 keytool 报密码错 = 密码文件被改写(见 ../p12-decrypt.md)

# 4) 用 keytool 看证书(命令详解见 02-keytool-openssl-cheatsheet.md)
keytool -list -v -keystore /tmp/server.jks -storepass '<PWD>' 2>&1 | less
```

### 1.4 在 Pod 内 — 确认进程实际监听的端口

```bash
# ss 或 netstat(精简镜像经常没装)
ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null

# 看 java 进程开了哪些 TCP 端口
ls -la /proc/$PID/fd/ 2>/dev/null | grep socket | head
# 或者
cat /proc/$PID/net/tcp | awk '$4 == "0A" {print $2}' | sort -u
# 状态 0A = LISTEN, 第 2 列是 local address (hex IP:port)
# 例如:00000000:21BB = 0.0.0.0:8443(0x21BB = 8635 → 不是 8443! 0x21BB = 0x21BB; 8443 = 0x20FB)
```

**8443 的 hex = 0x20FB,8080 的 hex = 0x1F90,443 的 hex = 0x01BB**。Pod 里 quick 验法:

```bash
# 在 Pod 内自连 8443(走 Pod 自己的 loopback),用 openssl 看 cert
openssl s_client -connect localhost:8443 -servername localhost -showcerts 2>/dev/null < /dev/null \
  | openssl x509 -noout -subject -issuer -fingerprint -sha256
```

这条命令即使 Pod 不通外网也能跑。**这是从 Pod 内部拿证书指纹最直接的方法**。

### 1.5 在 Pod 内 — 看进程的环境变量 + 配置加载顺序

```bash
# Spring Boot 配置的来源优先级(高→低):
# 1. 命令行参数 --server.ssl.key-store=...
# 2. SPRING_APPLICATION_JSON 环境变量
# 3. application-{profile}.yml
# 4. application.yml
# 5. 默认值
cat /proc/$PID/environ | tr '\0' '\n' | grep -iE 'spring|ssl|key_store'
```

如果环境变量里有 `SPRING_SSL_BUNDLE_JKS_CLIENT_KEYSTORE_LOCATION` 之类,**环境的优先级高于 JAR 里的 application.yml**,即使你改了 JAR 里的文件,实际加载的还是 ConfigMap/Secret 注入的值。

### 1.6 distroless / 无 shell 容器的 fallback

很多 GKE 镜像(Google 官方 `java-distroless`、`gcr.io/distroless/java`)只带一个 `java` binary,**没有 `/bin/sh`**。这种 Pod 你 `kubectl exec` 进去会立刻退出。

**绕开方法** — 用 `kubectl debug` 起一个临时 sidecar:

```bash
kubectl -n <NS> debug <POD> \
  --image=busybox:1.36 \
  --target=<CONTAINER_WITH_NO_SHELL> \
  --share-processes \
  -- bash
```

进 debug sidecar 后:

```bash
# 看目标容器的进程
ps auxf | grep -A2 java

# 看目标容器的文件系统(共享 PID namespace)
ls /proc/1/root  # 1 是目标容器 main process

# 直接 cat 目标容器的 keystore(通过 /proc/<pid>/root 桥接)
keytool -list -v \
  -keystore /proc/$(pgrep -f app.jar)/root/app/CertKey/team_a_env_server.jks \
  -storepass 'passwd123445'
```

如果连 debug sidecar 都没权限 / 镜像不支持(节点 OS 不兼容 busybox),退到场景 2。

---

## 场景 2:不能 exec,但能拿到 keystore 文件

适用:平台有 RBAC 限制 `pods/exec` / Pod 用了 distroless + 不允许 debug / 你只有 CI 产物的 read 权限。

### 2.1 keystore 在哪几种地方能拿到

| 来源 | 怎么拿 | 注意事项 |
|---|---|---|
| **用户提交的 JAR 内部** | `unzip -p app.jar BOOT-INF/classes/CertKey/<name>.jks > /tmp/srv.jks` | JAR 是 Spring Boot fat jar,路径是 `BOOT-INF/classes/` |
| **ConfigMap / Secret 挂载** | 直接 `cat /etc/ssl/certs/<name>.jks` 或 mount 路径 | Secret 默认 base64,**确认 mount 方式**(volumeMount vs env) |
| **PersistentVolume / CSI** | `kubectl get pvc` → 找到对应 Pod 的挂载路径 | 多 Pod 共享 PV 时注意并发读写 |
| **Container Registry 镜像 layer** | `docker pull` / `crane export` / `skopeo copy` | 适合镜像里带了 keystore 的场景 |
| **Git / S3 / 制品库** | 用户上传路径 | 看提交记录 |

### 2.2 拿到文件后立即做的 3 件事

```bash
# 1) 大小 + 类型
ls -la server.jks
file server.jks
# JKS = "Java KeyStore" / PKCS12 = "PKCS12 KeyStore"

# 2) 别名列表(快速看里面有啥)
keytool -list -keystore server.jks -storepass '<PWD>'
# 输出示例:
#   Keystore type: PKCS12
#   Keystore provider: SUN
#   Your keystore contains 1 entry
#   team_a_env_server, Dec 27, 2025, PrivateKeyEntry,     ← 这才是服务端的私钥
#   root_ca, Mar  3, 2024, trustedCertEntry,              ← 这是信任的 CA

# 3) 证书详情
keytool -list -v -alias <ALIAS> -keystore server.jks -storepass '<PWD>' 2>&1 | less
```

### 2.3 关键判定:它是 PrivateKeyEntry 还是 trustedCertEntry?

这是 `../java-application-auth.md` 里 `Alias name [team_a_env_server] does not identify a key entry` 报错的**直接判定方法**:

```
keytool -list -v 输出里这一行:
  Entry type: PrivateKeyEntry           ← ✅ 服务端私钥(可以被 Tomcat 当成 HTTPS cert)
  Entry type: trustedCertEntry          ← ❌ 只是受信任的 CA 证书(Tomcat 启动会失败)
  Entry type: SecretKeyEntry            ← ❌ 密钥但不是证书(罕见,Tomcat 不接受)
```

**判定定理**:`server.ssl.key-alias` 必须指向一个 `PrivateKeyEntry`,否则 Pod 启动必崩 `IllegalArgumentException: Alias name ... does not identify a key entry`。

---

## 场景 3:只能从外部访问(看不到 Pod 内部)

适用:平台方隔离很严 / 你只能 ping Service / Ingress / NodePort。

### 3.1 从集群外部 dial 进去 — openssl s_client

**这是从外部拿服务端证书的唯一标准方法**,跟 GLB 的 mTLS 验证同源(参考 `~/git/knowledge/OpenAI/docs/Verifying-GLB.md`):

```bash
# 1) 拿到 Service 的 ExternalIP / NodePort
kubectl get svc <SVC> -n <NS> \
  -o jsonpath='{.status.loadBalancer.ingress[*].ip}{" "}{.spec.ports[*].nodePort}{"\n"}'

# 2) openssl 直接连 + 拿证书指纹 + Subject
openssl s_client \
  -connect <EXTERNAL_IP>:8443 \
  -servername <SNI_HOSTNAME> \
  -showcerts \
  -verify_quiet \
  < /dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
```

**`openssl s_client` 的关键 flag**(详见 `~/git/knowledge/OpenAI/docs/Verifying-GLB.md` §3):

| Flag | 必填? | 作用 |
|---|---|---|
| `-connect IP:PORT` | 必填 | 连谁 |
| `-servername HOST` | **强烈推荐** | SNI;不填时,如果一个 IP 后面挂了多证书,可能拿到默认那张而非你预期那张 |
| `-showcerts` | 推荐 | 把整个证书链都打出来,便于看 CA 是否签发 |
| `-verify_quiet` | 可选 | 静默 verify 错误(自签证书场景必备,否则 verify 直接失败) |
| `-tls1_2` / `-tls1_3` | 可选 | 强制协议版本(用于排查"我只想要 TLSv1.3 但服务端返回了 TLSv1.2") |
| `-CAfile <ca-bundle>` | 可选 | 信任的服务端 CA(自签证书场景必备,否则 verify 直接失败) |

#### SNI 从哪来 — Java 应用自己怎么决定 `-servername`

**重要前提**:`openssl s_client -servername <HOST>` 是**外部探测**用的。**Java 应用自身作为客户端连服务端时,也会发 SNI** —— 这个 SNI 是 JSSE(Java Secure Socket Extension)在 TLS ClientHello 里自动塞的。所以你的"Java 应用"既可能是 **HTTPS Server**(回答外部客户端的 SNI),也可能是 **HTTPS Client**(主动发 SNI 给上游),甚至两者都是。

##### 包 1:代码层 — JSSE 的 SNI 来自哪里

Java 的 SNI 行为由 `javax.net.ssl.SSLParameters` 控制,**默认从 `InetSocketAddress.getHostString()` 拿 host**(就是 JDK 自己解析的 hostname,不是 IP),塞进 TLS ClientHello 的 `extension_server_name` 字段。

```java
// === 模式 A:JDBC / HttpClient 用 URI — SNI 自动 = URI 里的 host ===
HttpClient client = HttpClient.newBuilder()
    .build();
HttpRequest req = HttpRequest.newBuilder()
    .uri(URI.create("https://team1.caep.uk:8443/api/users"))   // ← SNI = "team1.caep.uk"
    .build();

// === 模式 B:SSLSocket 显式 connect — SNI = 你传的 host ===
SSLSocketFactory factory = (SSLSocketFactory) SSLSocketFactory.getDefault();
SSLSocket socket = (SSLSocket) factory.createSocket("10.72.1.50", 8443);
// 关键:createSocket(InetAddress, port) → SNI 是 null(IP 不算 SNI)
socket.getSslSession().getCipherSuite();   // 此时握手还没发 SNI
// 想加 SNI 必须走 SSLParameters:
SSLParameters params = socket.getSSLParameters();
params.setServerNames(List.of(new SNIHostName("team1.caep.uk")));   // ← 这里手动塞
socket.setSSLParameters(params);
socket.startHandshake();   // 这才把 SNI 发出去
```

**判定**:
- 如果用户用 `URI.create("https://host:port/path")` → **SNI = URI 的 host**
- 如果用 `InetSocketAddress(host, port)` 创建 socket → **SNI = host 字符串**(可能跟 IP 不一样)
- 如果直接 `createSocket(InetAddress, port)` → **SNI = null**(很多老 MySQL JDBC 驱动这么干)

**Tomcat 服务端怎么处理收到的 SNI**(SNIHostName extension 在 TLS ServerHello 之前到达):
- 默认 `Tomcat 9+` 支持 SNI — 根据收到的 SNI 找对应的 `SSLHostConfig`(每个 `<SSLHostConfig host="...">` 可以绑不同证书)
- **如果用户在 `server.xml` / Spring Boot 只配了一个 cert**(绝大多数场景),服务端**忽略 SNI,统一用那份 cert** — 那你 `openssl s_client -servername <随便什么>` 拿到的都是同一张
- **如果用户在 Spring Boot 配了多证书**(少见,但 `spring.ssl.bundle` + SNI routing 可能做),那 `-servername` 必须匹配才能拿到预期的 cert

##### 包 2:应用层 — 用户 JAR 里 3 种最常见的 SNI 来源

| 模式 | 用户代码里长什么样 | 实际 SNI | 你怎么查 |
|---|---|---|---|
| **写死常量** | `URI.create("https://openam.abj.uk:8443/...")`(见 `../java-application-auth.md` §一) | "openam.abj.uk" | `unzip -p app.jar .../application.yml \| grep -i url` |
| **从配置读** | `openam.url: https://url:8443/...` 写进 yaml,代码里 `@Value` 注入 URI | yaml 里的 host | 同上 |
| **从请求 Host 头动态读** | 用户做了一个反向代理 / API gateway,SNI 来自入站请求的 Host | 不可预测 | 看 inbound LB 的 Host 规则 |

**最常见的坑**:`openam.url: https://url:8443/...`(见 `../java-application-auth.md`)— **`url` 是占位符,没替换**。Pod 启动时 Java 把 `url` 当成 hostname 发 SNI 给"url"(DNS 解析失败),TLS 握手直接挂。这种情况你从 Pod 日志里看 `UnknownHostException: url` 就能定位。

##### 包 3:排查层 — 反推 Java 应用实际用的 SNI

**从外部反向 dial**(用 `openssl s_client` 模拟 JSSE):

```bash
# 1) 用 application.yml / ConfigMap 里的 URL 提取 host
SNI=$(kubectl -n <NS> get cm <CM> -o jsonpath='{.data.application\.yaml}' \
      | grep -oE 'https://[^:/]+' | head -1 | sed 's|https://||')
echo "Suspected SNI: $SNI"

# 2) 用这个 SNI dial,看服务端是不是真按这个 SNI 路由 cert
openssl s_client -connect <IP>:8443 -servername "$SNI" -showcerts \
  </dev/null 2>/dev/null | openssl x509 -noout -subject -fingerprint -sha256

# 3) 对比:不传 SNI 拿到的 cert
openssl s_client -connect <IP>:8443 -showcerts \
  </dev/null 2>/dev/null | openssl x509 -noout -subject -fingerprint -sha256

# 两张 cert 不一样 → 服务端真的做了 SNI routing
# 两张 cert 一样   → 服务端忽略 SNI(只看 IP:PORT),任何 -servername 都拿同一张
```

**从 Pod 内部主动抓包**(最强证据 — 真的能看到 ClientHello 里的 SNI 扩展):

```bash
# 进 Pod 后(场景 1),如果容器里有 tcpdump / tshark
tcpdump -i any -nn -s 0 -w /tmp/cap.pcap 'tcp port 8443 and (tcp[((tcp[12]>>4)*4)+9+0] > 22)'
# 然后在本机用 wireshark 打开,过滤 tls.handshake.extensions_server_name

# 没有 tcpdump?用 strace 间接看(只支持 OpenJDK 的 SSL 写路径)
strace -f -e trace=write -p <JAVA_PID> 2>&1 | grep -A2 "write.*:443" | head
# 太吵,基本不可用 — 优先 tcpdump
```

**从 Java 应用日志反推**(很多 JSSE 实现把 SNI 打 INFO/WARN):

```bash
# 1) 找应用日志里的 SSL / handshake 关键字
kubectl -n <NS> logs <POD> --tail=500 | grep -iE 'sni|server_name|hostname|peer|principal'

# 2) JDK 的 -Djavax.net.debug=ssl:handshake 会打印完整 ClientHello/ServerHello
#    如果用户 Pod 启动脚本带了这条,直接 grep 'server_name' 就能拿到 SNI
kubectl -n <NS> logs <POD> --tail=2000 | grep -i 'extension_server_name\|server_name extension'
# 输出示例:
#   *** ClientHello, TLSv1.3 (Random, Session ID, Cipher Suites, Extensions)
#   Extension server_name, server_name: [host_name: team1.caep.uk]   ← 这就是 SNI
```

**判定定理**:`extension server_name` 字段出现哪个 host,Java 客户端连服务端时发的就是哪个。**这个 host 必须匹配服务端 cert 的 SAN**(否则客户端报 `SSLHandshakeException: No subject alternative DNS name matching ...`)。所以 `openssl s_client -servername` 跟 Java 客户端用同一个 host,才能复现"Java 客户端能连上 / 连不上"的现象。

#### §3.1.1 双角色场景 — Server 收的 SNI 跟 Client 发的 SNI 不一致时,代码层要注意什么

**前提回顾**:你的 Java 应用**同时是 HTTPS Server 和 HTTPS Client**,两个方向的 SNI 是**两个独立事件**:

```
方向 1 (Server):外部 client → TLS ClientHello[server_name: 外部 host] → 你的 Tomcat
                                                       ↓
                                  多个 SSLHostConfig → 按 SNI 选 cert
                                  单 cert 配置    → 忽略 SNI,统一用同一张

方向 2 (Client):你 → TLS ClientHello[server_name: 上游 host] → 上游服务
                                                       ↓
                                  上游 cert 的 SAN 必须包含这个 host(否则客户端报 SSLHandshakeException)
```

**最关键的点:两个方向共用同一张 cert 的 SAN 字段**。两个 host 不一致时,cert 必须**同时覆盖两个 host**(多 SAN),或者为两个方向**分别签 cert**。

**典型真实场景**(引用 `../java-application-auth.md` §一 的 case):

```
方向 1:外部 OpenAM 客户端用 https://team1.caep.uk:8443/... 访问你的 Pod
       → 你 Tomcat 收到的 SNI = "team1.caep.uk"
       → 你的 cert 的 SAN 必须包含 "team1.caep.uk"

方向 2:你的 Pod 用 openam.url=https://openam.abj.uk:8443/... 访问 OpenAM
       → 你发的 ClientHello 里的 SNI = "openam.abj.uk"
       → 上游 OpenAM 的 cert 的 SAN 必须包含 "openam.abj.uk"(否则 SSLHandshakeException)
```

**两边 host 不同 → 你需要 cert 的 SAN 同时包含 "team1.caep.uk" 和 "openam.abj.uk",或者为两个方向各签一张 cert。**

##### 注意事项 1:`application.yml` 的 Server / Client 配置**不能共用同一个 keystore**

`server.ssl.*` 只管 Server 侧配置;Client 侧的 keystore/truststore 是另一组配置:

```yaml
# === Server 角色(你的 Pod 被外部访问)— server.ssl.* ===
server:
  port: 8443
  ssl:
    enabled: true
    key-store: classpath:CertKey/team_a_env_server.jks     # 服务端 keystore
    key-store-password: ${SVR_KEYSTORE_PWD}
    key-alias: team_a_env_server                            # ← PrivateKeyEntry
    key-store-type: JKS
    client-auth: none                                       # 单向 TLS

# === Client 角色(你的 Pod 访问上游)— 独立 ssl bundle ===
spring:
  ssl:
    bundle:
      jks:
        client:
          keystore:                                         # 你作为客户端的 keystore
            location: classpath:CertKey/team_a_env_client.jks
            password: ${CLIENT_KEYSTORE_PWD}
          truststore:                                       # 信任上游 OpenAM 的 CA
            location: classpath:CertKey/team_a_env_client_reduced_v1.jks
            password: ${TRUSTSTORE_PWD}
```

**关键**:Server 用 `team_a_env_server.jks`(必须是 PrivateKeyEntry,Tomcat 才能拿来做服务端 cert);Client 用 `team_a_env_client.jks` + `team_a_env_client_reduced_v1.jks`(trustedCertEntry 类型,只信任上游 CA)。**两个 keystore 别混用**——这就是 `../java-application-auth.md` §一 那个 `Alias name [team_a_env_server] does not identify a key entry` 报错的根因之一:用户把 client 的 keystore 误塞给 server.ssl.key-store。

##### 注意事项 2:Client 侧的 SNI = `URI.create()` 里的 host,**跟你自己的服务名无关**

JSSE(Java Secure Socket Extension)默认从 `URI.create()` 抽 host 塞进 ClientHello 的 `extension_server_name` 字段:

```java
// ❌ 用你的服务名当上游 host(常见错误)
URI upstream = URI.create("https://team_a_env_server:8443/...");
// JSSE 把 "team_a_env_server" 发成 SNI
// 上游 cert SAN 不包含这个名字 → SSLHandshakeException: No subject alternative DNS name matching team_a_env_server

// ✅ 用上游服务的真实 hostname
URI upstream = URI.create("https://openam.abj.uk:8443/...");
// SNI = "openam.abj.uk",跟上游 cert SAN 对齐

// ❌❌ 占位符没替换(来自 ../java-application-auth.md 真实 case)
URI upstream = URI.create("https://url:8443/...");
// JSSE 发 SNI = "url",DNS 解析直接挂
// Pod 日志:java.net.UnknownHostException: url
```

**判定**:Pod 日志里只要出现 `UnknownHostException` 或 `SSLHandshakeException: No subject alternative DNS name matching`,**100% 是 Client 侧的 SNI / cert SAN 对不齐** —— 跟 Server 侧无关,别去查 `application.yml` 的 `server.ssl.*`。

##### 注意事项 3:如果想用**一张 cert 同时覆盖两个方向** —— 必须是多 SAN 的 cert

```bash
# === 错:一张 cert 只覆盖一个 host ===
# SAN = [DNS:team1.caep.uk]
# ✅ 服务端方向(外部访问我)能用
# ❌ Client 方向(我访问 openam.abj.uk)报 SSLHandshakeException

# === 对:签发时把两个 host 都列进 SAN ===
keytool -certreq -alias team_a_env_server -keystore team_a_env_server.jks \
    -file team_a_env_server.csr \
    -ext SAN=dns:team1.caep.uk,dns:openam.abj.uk
# 生成的 cert:
#   X509v3 Subject Alternative Name:
#       DNS:team1.caep.uk, DNS:openam.abj.uk
```

**这样一张 cert 既能回答外部 SNI "team1.caep.uk",也能作为 Client 访问 openam.abj.uk**(因为客户端校验服务端 cert 时,SAN 覆盖了目标 host)。

##### 最容易踩的 3 个坑(基于 `../java-application-auth.md` 那个 case)

| 坑 | 现象 | 修法 |
|---|---|---|
| **两个方向共用 `key-store`** | 启动崩 `Alias name [team_a_env_server] does not identify a key entry`(server.jks 里只有 PrivateKeyEntry,没 trustedCertEntry 给 truststore 用) | Client 侧用独立 `spring.ssl.bundle.jks.client.keystore`,别复用 server 的 |
| **Client URI 写成 https://url:8443/... 占位符没替换** | Pod 启动 OK,首次访问上游时报 `UnknownHostException: url` | 全 repo grep `https://url` / `https://localhost:8443` 等占位符;CI 加 lint |
| **cert SAN 只写了 "team1.caep.uk" 没写 "openam.abj.uk"** | 服务端方向 OK,Client 访问 OpenAM 时 SSL 握手失败 | 重签 cert 把两个 host 都加进 SAN;或 OpenAM 侧加 cert 到它的 truststore |

##### 验证 — 1 分钟自检双方向 SNI 配置

```bash
KS=/path/to/team_a_env_server.jks

# 1) 服务端 cert 的 SAN 是否覆盖"外部访问你的 host"
keytool -list -v -alias team_a_env_server -keystore "$KS" -storepass '<P>' 2>&1 \
  | grep -A2 'SubjectAlternativeName' | grep -E 'DNS:|IPAddress:'
# 必须看到 DNSName: team1.caep.uk(你的外部访问地址)

# 2) Client URI 实际发给上游的 host(从 yaml 提取)
kubectl -n <NS> exec <POD> -- cat /app/application.yml 2>/dev/null \
  | grep -oE 'https://[^:/]+:[0-9]+' | sort -u
# 输出示例:
#   https://team1.caep.uk:8443       ← Server 端地址(被外部访问)
#   https://openam.abj.uk:8443       ← Client 端地址(主动访问上游)

# 3) 上游 cert 的 SAN 是否覆盖 Client URI 里的 host
openssl s_client -connect openam.abj.uk:8443 -servername openam.abj.uk \
  </dev/null 2>/dev/null \
  | openssl x509 -noout -ext subjectAltName
# 必须包含 DNS:openam.abj.uk

# 4) Pod 日志扫 SSL 异常
kubectl -n <NS> logs <POD> --tail=1000 \
  | grep -iE 'SSLHandshakeException|UnknownHostException|No subject alternative|hostname'
# 任何一行 → 方向 2(Client 侧)配置有错,跟 server.ssl.* 无关
```

##### 一句话总结

**Server 收的 SNI**(决定 Tomcat 选哪张 cert / 验证外部客户端用的 host)和 **Client 发的 SNI**(JSSE 从 `URI.create(...)` 里抽出的 host)是**两个独立事件**,但**共用同一张 cert 的 SAN**。两个 host 不一致时,代码层要做 3 件事:

1. `server.ssl.*`(server)跟 `spring.ssl.bundle.jks.client.*`(client)**分开配置,别共用 keystore**
2. Client URI 用上游真实 hostname,**别留 `https://url:8443/...` 这种占位符**
3. 签 cert 时把两个 host 都列进 SAN,**或为两个方向各签一张 cert**

### 3.2 把证书 dump 下来做指纹比对

```bash
# 把服务端返回的证书 dump 到本地文件
openssl s_client -connect <IP>:8443 -servername <HOST> -showcerts \
  </dev/null 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' \
  > /tmp/server-cert.pem

# 看 fingerprint
openssl x509 -in /tmp/server-cert.pem -noout -fingerprint -sha256

# 跟用户提交的 keystore 里的 cert 比 fingerprint
# (从 keystore 拿 fingerprint 见 02-keytool-openssl-cheatsheet.md §3)
keytool -list -v -keystore user-submitted.jks -storepass '<PWD>' \
  | grep -A1 'SHA256:'
```

**判定定理**:两端 SHA256 fingerprint 完全一致 → Pod 加载的就是用户提交的 keystore(没有"平台偷偷替换"或"加载到了错的文件")。不一致 → 立刻往里查,见 §3.3。

### 3.3 fingerprint 不一致的 3 种典型根因

| 现象 | 根因 | 排查方向 |
|---|---|---|
| 一致 | Pod 正确加载了用户 keystore | ✅ 收工 |
| 完全不一致 | Pod 加载的是**别的文件**(平台默认 / ConfigMap 注入 / JAR 里另一个 keystore) | 看 JVM 启动参数 + ConfigMap 内容 |
| 接近但最后几位不同 | **CRLF / BOM / 编码问题**,JKS 里的 cert 跟用户源文件不等价 | 见 `~/git/knowledge/skill/gcp/references/cert-format-preflight.md`(要查的话) |
| 客户端报 `unknown ca` | Pod 用了自签证书,客户端 truststore 不认 | 把服务端证书加到客户端 truststore |

### 3.4 从外部验证协议版本

```bash
# 看实际协商的 TLS 版本(看 "Protocol" 行)
openssl s_client -connect <IP>:8443 -servername <HOST> -verify_quiet \
  </dev/null 2>/dev/null | grep -E 'Protocol|Cipher'
# Protocol  : TLSv1.3
# Cipher    : TLS_AES_256_GCM_SHA384
```

如果想看服务端支持的全部协议(主动探测):

```bash
# 用 nmap(可能没装,用 openssl 凑合)
for v in tls1 tls1_1 tls1_2 tls1_3; do
  echo "=== $v ==="
  echo | openssl s_client -connect <IP>:8443 -servername <HOST> -$v 2>/dev/null | grep -E 'Protocol|Cipher|alert'
done
# TLSv1 / TLSv1.1 通常 "alert handshake failure" → 服务端已禁用
```

### 3.5 局限:看不到 Pod 内部时的天花板

从外部 dial 能确认的:
- ✅ 服务端确实在跑 HTTPS(不是 HTTP 在 8443 假装)
- ✅ 证书指纹 + Subject + Issuer + 有效期
- ✅ 协商的 TLS 版本 + Cipher
- ✅ 是否要求 client cert(mTLS)

看不到的:
- ❌ 证书从哪个文件加载(你只能假设,除非 fingerprint 对得上用户提交的)
- ❌ JVM 启动参数 + 是否被 ConfigMap override
- ❌ keystore 里的 alias 是否跟 `server.ssl.key-alias` 对齐

**所以场景 3 的结论只是"间接证据",必须配合场景 1 或场景 2 才能定根因**。

---

## 汇总:3 场景证据强度对比

| | 场景 1:exec | 场景 2:文件 | 场景 3:外部 |
|---|---|---|---|
| 能确认进程在听 HTTPS | ✅ ss/netstat | ❌ | ✅ openssl dial |
| 能拿到证书指纹 | ✅ keytool 本地读 | ✅ keytool 本地读 | ✅ openssl dump |
| 能看到 JVM 启动参数 | ✅ /proc/PID/cmdline | ❌ | ❌ |
| 能验证 alias → PrivateKeyEntry | ✅ keytool | ✅ keytool | ❌(看不到 keystore 内部) |
| 适用平台隔离最严的情况 | ❌ 需要 exec 权限 | ⚠️ 取决于你能不能拿文件 | ✅ 只看得到 Service |

**最优策略**:能 exec 就走场景 1 的全部 1.1-1.5,一锤定音;不行就场景 2 拿 keystore;都不行才场景 3,但场景 3 必须配 fingerprint 比对。

下一步命令细节见 [02-keytool-openssl-cheatsheet.md](02-keytool-openssl-cheatsheet.md);代码层(Spring Boot 怎么挑证书)见 [03-spring-boot-yaml-ssl-anatomy.md](03-spring-boot-yaml-ssl-anatomy.md)。