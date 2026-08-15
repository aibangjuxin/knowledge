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
| `-verify_quiet` | 可选 | 静默 verify 错误(自签证书场景下你不想看到 verify error 干扰阅读) |
| `-tls1_2` / `-tls1_3` | 可选 | 强制协议版本(用于排查"我只想要 TLSv1.3 但服务端返回了 TLSv1.2") |
| `-CAfile <ca-bundle>` | 可选 | 信任的服务端 CA(自签证书场景必备,否则 verify 直接失败) |

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