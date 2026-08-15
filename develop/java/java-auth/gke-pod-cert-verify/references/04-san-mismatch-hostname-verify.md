# 04 — 客户端用域名访问 Pod 时报证书错,但绑 IP 又能通 — SAN 不匹配自检

> **典型现象**:客户端 `curl -v https://apiname.teamname.caep.com:8443/...` 报 `SSL certificate problem`(subjectAltName 不匹配),但改用 `curl https://apiname.teamname.caep.com:8443/... --resolve apiname.teamname.caep.com:8443:<Pod_IP>` 又能通。或者换 `curl -k`(跳过 cert 校验)也通。
>
> **这是最经典的"Pod 自己起的 cert SAN 没覆盖外部访问用的域名"** 的坑。本文按 **"自顶向下复现 → 反向自检 → 根因 → 修法"** 的顺序展开。

---

## 1. 一句话根因

```
客户端期望的 cert:                SAN = [DNS:apiname.teamname.caep.com]
Pod 里 Tomcat 实际用的 cert:       SAN = [DNS:其他名字, IP:127.0.0.1]

→ JSSE / openssl / curl 客户端校验:
  "apiname.teamname.caep.com" 在不在 SAN 里?
  不在 → SSLHandshakeException / curl verify error
```

**为什么绑 IP 又能通?** 因为 `--resolve host:port:IP` + curl 默认会拿 hostname 做 SNI + hostname verification,但服务端 cert 的 SAN 不覆盖这个 hostname → 失败;**而用 `--resolve` 后改 curl `-k` 跳过 hostname verification** 或者**用 openssl `-verify_quiet` 跳过**,cert 本身能正常完成握手 → 看起来"通了"。

**注意**:绑 IP 通 ≠ 实际业务能跑 — 上游 LB / API gateway 在 hostname 上做 routing 时,**SNI 不匹配会直接拒**。这是更隐蔽的失败模式。

---

## 2. 完整自检流程(从客户端到服务端反向追)

### 2.1 客户端视角:看 curl 报的**完整错误**

```bash
curl -v https://apiname.teamname.caep.com:8443/healthz 2>&1 | grep -iE 'ssl|tls|certificate|verify|subject|alt|issuer|expire'
# 典型输出(自签 + SAN 不匹配):
#   * SSL certificate verify result: unable to get local issuer certificate (self signed certificate) (20)
#   * SSL certificate verify result: hostname mismatch (62)
#   * SSL connection using TLS_AES_256_GCM_SHA384 / TLSv1.3
#   *  subject: 'CN=localhost'
#   *  issuer: 'CN=localhost'
#   *  start date: ...
#   *  expire date: ...
```

**curl 的两个独立 verify error**:

| error:num | 含义 | 自签 cert 时是否出现 |
|---|---|---|
| **20** | `unable to get local issuer certificate` | ✅ 出现(自签 cert 的 Issuer = 自己,不在系统 truststore) |
| **62** | `Hostname mismatch`(SAN 不包含访问的 hostname) | ✅ 出现(如果 SAN 不覆盖) |
| 51 | `SSL certificate verify result: CN does not match hostname`(老式 Common Name 校验,现代客户端已废弃,改用 SAN) | 偶尔出现 |
| 60 | `SSL certificate problem: unable to get local issuer certificate`(curl 整体判定) | 自签常见 |

**关键判定**:err 20 + err 62 同时出现,几乎 **100% = Pod 用了自签 cert,SAN 又没覆盖客户端访问的域名**。

### 2.2 客户端视角:对比绑 IP 走

```bash
# 不带 -k,看 --resolve 能不能绕开 verify error
curl -v \
  --resolve apiname.teamname.caep.com:8443:<POD_IP> \
  https://apiname.teamname.caep.com:8443/healthz \
  2>&1 | grep -iE 'ssl|verify|hostname|connection'

# 如果上一步报 hostname mismatch,这条依然报(因为 verify 还是用 hostname)
# 如果用 -k 跳过 verify,无论 hostname 通不通都能连
curl -k \
  --resolve apiname.teamname.caep.com:8443:<POD_IP> \
  https://apiname.teamname.caep.com:8443/healthz
```

**判定**:`--resolve` 不带 `-k` 还报错 → **hostname verify 失败(SAN 问题)**;带 `-k` 能通 → 确认是 hostname verify / SAN 问题,而非 TCP / TLS 协议层问题。

### 2.3 服务端视角:用客户端访问的 hostname 做 SNI 去 dial,看 Pod 实际返回的 cert 是什么

**这是本文档最核心的一条命令**。思路就是:

```
"客户端访问 Pod 时,期望 Pod 用一张 cert 来证明自己。
 我现在从外部模拟这个客户端请求,问 Pod:你给我看的 cert 到底是什么?
 如果这张 cert 跟客户端期望的对得上 → 客户端报错的根因不在服务端 cert。
 如果对不上 → 找到根因了。"
```

**完整命令**:

```bash
openssl s_client \
  -connect <POD_IP>:8443 \
  -servername apiname.teamname.caep.com \
  -showcerts \
  </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -ext subjectAltName -fingerprint -sha256
```

**每一段在干什么 + 换成别的值会怎样**:

| 片段 | 含义 | 换成别的会怎样 |
|---|---|---|
| `openssl s_client` | openssl 的 TLS 客户端工具,**模拟一个 TLS 握手去连服务端** | — |
| `-connect <POD_IP>:8443` | **TCP 层连谁**:`<POD_IP>` 是 Pod 的 IP(从 `kubectl get svc -o jsonpath='{.status.loadBalancer.ingress[*].ip}'` 或 Pod IP 列表拿),`8443` 是 Pod 实际监听的 HTTPS 端口(从 `server.port` / 启动参数 / Service.spec.ports 确认) | ❌ 写成 Service ClusterIP(`10.x.x.x`):可能 ClusterIP 只在集群内可达,从集群外 dial 不通;**必须用 Pod IP 或 ExternalIP** |
| `-servername apiname.teamname.caep.com` | **TLS 层发哪个 SNI**:就是客户端访问时想用的 hostname。这条等价于 JSSE 里 `HttpClient` 用 `URI.create("https://apiname.teamname.caep.com:8443/...")` 时 JSSE 自动发的那个 `extension_server_name` | ❌ 写成 `localhost` / IP / 空:Tomcat 收到一个无关的 SNI,**可能根本收不到 cert**(见 §3 根因 4 SNI routing)或拿到错的 cert,**这条 dial 就没法模拟客户端的真实场景了** |
| `-showcerts` | 把服务端发回的**整个证书链**(leaf + intermediate + root)都打出来 | ❌ 不写:你只能看到 openssl 自动选定的 leaf cert,看不到完整 chain(排查 chain 信任问题时缺中间证书就用得上) |
| `</dev/null` | s_client 默认会等你 stdin 输入完才退出;**`< /dev/null` 是立刻给个 EOF**,避免命令挂死 | ❌ 不写:bash 永远停在这里,看起来像卡住 |
| `2>/dev/null` | 把 openssl 的 verify 报错、自签 cert 的 `verify error:num=18:self signed certificate` 这些噪音丢掉,只留干净输出 | ❌ 不写:报错噪音会污染管道,`openssl x509 -noout` 解析可能挂掉 |
| `\| openssl x509 -noout -subject -issuer -ext subjectAltName -fingerprint -sha256` | **把 s_client 的输出再喂给 openssl x509 解析**:拿到 cert 后只看 Subject / Issuer / SAN / SHA256 fingerprint 这 4 个字段,其他无关信息(版本号、有效期细到毫秒等)丢掉 | ❌ 漏掉 `-ext subjectAltName`:看不到 SAN,本文档主场景就废了;❌ 漏掉 `-fingerprint -sha256`:没法做跨工具对账 |

**实测输出范例**(SAN 不匹配场景):

```
subject=C=US, ST=State, L=City, O=Example, OU=Demo, CN=localhost
issuer=CN=localhost(自签)
X509v3 Subject Alternative Name:
    DNS:localhost, IP Address:127.0.0.1     ← ❌ 没有 apiname.teamname.caep.com
sha256 Fingerprint=FF:42:...
```

**怎么读这份输出**:

| 字段 | 告诉你什么 | 怎么判 |
|---|---|---|
| `subject=...CN=localhost` | 这张 cert 是给 "localhost" 签的 | 如果客户端访问的是 `apiname.teamname.caep.com`,**Subject CN 跟访问的 hostname 都不一样** → 必然 hostname mismatch |
| `issuer=CN=localhost` | Issuer = Subject → **自签 cert** | 不是公共 CA 签的 → 客户端 truststore 不认 → 报 err 20 |
| `X509v3 Subject Alternative Name: DNS:localhost, IP Address:127.0.0.1` | **这张 cert 实际覆盖哪些 hostname / IP** | 在这行里**搜不到** `apiname.teamname.caep.com` → 100% 确认 SAN 不覆盖客户端期望的 hostname → hostname verify 必败 |
| `sha256 Fingerprint=FF:42:...` | 这张 cert 的指纹 | 跟 Pod 内 keystore 的 cert 指纹(`keytool -list -v` 输出的 SHA256)对账 — **一致** = 客户端拿到的就是 Pod 里的 cert;**不一致** = 中间有 LB / Envoy / cert-manager 之类的组件在转发时换了一张 cert |

**判定结论**:`ext subjectAltName` 输出里**找不到** `apiname.teamname.caep.com` → 100% 确认 SAN 不覆盖。**根因就是 Pod 里那张 cert 的 SAN 写错了** — 修法见 §4 修法 3(重签 cert 加进 `-ext SAN=`)。

**反向验证 — 用 SAN 里已有的 hostname 做 SNI,确认服务端"接受"这个 SNI**:

```bash
# 用 cert SAN 里已有的 "localhost" 做 SNI
openssl s_client -connect <POD_IP>:8443 -servername localhost -showcerts \
  </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -fingerprint -sha256
# 拿到 cert → 服务端不拒 SNI,只是 cert 内容跟请求的 hostname 不匹配
# 拿到同一张 cert → 进一步确认服务端只配了一份 cert(没做 SNI routing,见 §3 根因 4)

# 关键对比:两次 dial 的 fingerprint
# 第一次 -servername apiname.teamname.caep.com → fingerprint A
# 第二次 -servername localhost               → fingerprint B
# A == B → 只配了一份 cert,SNI 不影响选 cert(常见)
# A != B → 配了多 cert,SNI routing 真的在工作(罕见,见 §3 根因 4)
```

**最常见的填错方式**(踩过的坑):

| 错填 | 后果 | 怎么改 |
|---|---|---|
| `-connect <Service_ClusterIP>:8443` | ClusterIP 只在集群内可达,集群外 dial 直接 `Connection refused` / timeout | 用 Pod IP(从 `kubectl get pod -o wide` 拿)或 Service 的 `status.loadBalancer.ingress[*].ip`(公网 SLB/ExternalIP) |
| `-servername <Pod_IP>` | IP 当 SNI 发,**客户端 IP verify 时**还是错(JSSE 不会把 IP 当 hostname 验证除非 SAN 里写了 IP 类型) | 用客户端实际访问的 hostname,不是 IP |
| `-connect` 端口写错(8443 写成 443) | `Connection refused` | 看 `kubectl get svc <SVC> -o jsonpath='{.spec.ports[?(@.name=="https")].port}'` 确认 |
| `< /dev/null` 漏写 | bash 卡住不动 | 加回去 |
| `2>/dev/null` 漏写 | 噪音污染 pipe,后续 `openssl x509` 解析失败 | 加回去 |

### 2.4 服务端视角:看 Pod 内 keystore 实际配了什么 SAN

进 Pod(场景 1)/ 从文件读(场景 2)都行,目标是直接看 keystore 里的 cert 的 SAN:

```bash
# 拿到 keystore 文件
kubectl -n <NS> cp <POD>:/app/CertKey/team_a_env_server.jks /tmp/srv.jks

# 看 SAN
keytool -list -v -alias team_a_env_server -keystore /tmp/srv.jks \
  -storepass '<PWD>' 2>&1 \
  | awk '/SubjectAlternativeName/,/^$/' | grep -E 'DNSName|IPAddress'

# 期望看到:
#   DNSName: localhost
#   IPAddress: 127.0.0.1
# 但客户端访问的应该是:
#   DNSName: apiname.teamname.caep.com   ← 缺失!
```

**对照清单**:

| 客户端访问的 URL | Pod 内 cert 的 SAN | 结果 |
|---|---|---|
| `https://apiname.teamname.caep.com:8443/...` | `DNS:apiname.teamname.caep.com` | ✅ OK |
| `https://apiname.teamname.caep.com:8443/...` | `DNS:localhost, IP:127.0.0.1` | ❌ **SAN mismatch → hostname verify 失败** |
| `https://<Pod_IP>:8443/...`(直接 IP) | `IP:127.0.0.1`(SAN 里只有本机 IP) | ⚠️ **curl 会把 IP 当 hostname 验证,SAN 里没这个 IP 也失败** |

---

## 3. 5 种典型根因 + 排查路径

### 根因 1:用户自签 cert 时只写了 `CN=localhost`,SAN 留空或写 localhost

**最常见**。用户在容器里用 keytool 生成自签 cert 时:

```bash
# === 错 ===
keytool -genkeypair -alias server -keystore server.jks \
  -dname "CN=localhost, OU=Demo" \
  -validity 365 -keyalg RSA -keysize 2048 \
  -storetype PKCS12
# 没有 -ext "SAN=..." → 生成的 cert 没有 SAN 扩展,只有 CN=localhost

# === 对(本地开发够用) ===
keytool -genkeypair -alias server -keystore server.jks \
  -dname "CN=localhost, OU=Demo" \
  -ext "SAN=dns:localhost,ip:127.0.0.1" \
  -validity 365 -keyalg RSA -keysize 2048 \
  -storetype PKCS12
# SAN = [DNS:localhost, IP:127.0.0.1],本地 curl -k https://localhost 能过
# 但用 https://apiname.teamname.caep.com 访问 → 还是 mismatch

# === 对(覆盖外部访问域名) ===
keytool -genkeypair -alias server -keystore server.jks \
  -dname "CN=apiname.teamname.caep.com, OU=Demo" \
  -ext "SAN=dns:apiname.teamname.caep.com,dns:localhost,ip:127.0.0.1" \
  -validity 365 -keyalg RSA -keysize 2048 \
  -storetype PKCS12
```

**实测** — 用 `../simple-https-demo/generate-cert.sh` 生成的 cert,看它的 SAN:

```bash
KS=/Users/lex/git/knowledge/develop/java/java-auth/simple-https-demo/src/main/resources/ssl/server-keystore.p12
keytool -list -v -alias server -keystore "$KS" -storepass changeit 2>&1 \
  | grep -A3 SubjectAlternativeName
# 实际输出:
#   SubjectAlternativeName [
#     DNSName: localhost
#     IPAddress: 127.0.0.1
#   ]
# → 跟访问 https://apiname.teamname.caep.com 不匹配,会报 hostname mismatch
```

### 根因 2:用户从生产环境拉了 cert,但生产 cert 是给**别的 host** 签的

```bash
# 用户从公司别的服务借了一份 cert
# 比如 team1.caep.uk 的生产 cert,直接复制到 GKE Pod 里用
# 但客户端期望访问的是 apiname.teamname.caep.com
# → 拿别人的 cert 当自己的 → SAN 不覆盖 → 失败
```

**判定**:对账 §2.3 拿到的 cert Subject / SAN 跟客户端访问的 hostname。

### 根因 3:Pod 内 `/etc/hosts` 劫持了 DNS,Pod 看到的 hostname ≠ 客户端看到的

```bash
# Pod 里 /etc/hosts:
127.0.0.1 apiname.teamname.caep.com   ← Pod 自己起 cert 时用这个 hostname

# 客户端从公网 DNS 解析:
$ nslookup apiname.teamname.caep.com
Server:    8.8.8.8
Address:   <POD_IP>     ← 客户端解析到 Pod IP

# Pod 启动时,自己的 cert 写 CN=apiname.teamname.caep.com / SAN=dns:apiname.teamname.caep.com
# → 客户端拿到的 cert SAN 看起来是对的!
```

这种**罕见但合法** — 客户端用域名访问,SAN 也覆盖域名,verify 能过。**但** Pod 自己只 listen 在 127.0.0.1:8443(`/etc/hosts` 把域名指向 loopback),客户端连 Pod IP 时,Pod 端 Tomcat 可能根据请求的 `Host:` 头 / SNI 选择 cert,具体行为取决于 Tomcat 的 `<Connector>` 配置。

### 根因 4:Tomcat 只配了一个 cert,SNI routing 把"非预期 hostname"的请求拒了

```xml
<!-- server.xml -->
<Connector port="8443" protocol="HTTP/1.1" SSLEnabled="true">
    <SSLHostConfig host="apiname.teamname.caep.com">       <!-- 只接受这个 SNI -->
        <Certificate certificateKeystoreFile="..." />
    </SSLHostConfig>
    <!-- 没配 host="localhost" / host="127.0.0.1" 的 SSLHostConfig -->
</Connector>
```

**行为**:
- 客户端 SNI = `apiname.teamname.caep.com` → Tomcat 找到匹配 SSLHostConfig,返回正确 cert → ✅
- 客户端 SNI = `localhost` 或 **没发 SNI**(IP 直连时) → Tomcat 没找到匹配的 SSLHostConfig → **直接 reset connection** → 客户端看不到 cert,但报错是 `SSL_ERROR_SYSCALL` / `Connection reset by peer`,而不是 `Hostname mismatch`

**判定**:报错是 `Hostname mismatch`(SAN 有但不含访问的 host)还是 `Connection reset`(服务端直接拒)?**两者修法完全不同**。

### 根因 5:平台在 Pod 启动时注入了**平台默认 cert**,覆盖了用户的 cert

```bash
# 用户 application.yml 里写了:
#   server.ssl.key-store: classpath:CertKey/user-team.jks
#   server.ssl.key-alias: user-team

# 但平台 Deployment 模板 args 注入:
#   --server.ssl.key-store=file:/etc/platform/platform-default.jks
#   --server.ssl.key-alias=platform-default
#   (优先级最高,覆盖 user-team 的配置)

# 用户 cert 永远不会被加载 → Pod 用的是平台 cert
# 平台 cert 的 SAN 可能只覆盖 *.platform-internal.com,而不是 apiname.teamname.caep.com
```

**判定**:进 Pod 拿进程启动参数(`/proc/<PID>/cmdline`,见 `01-shell-access-strategies.md` §1.2)或 `kubectl describe pod` 的 `Args:` 字段。

---

## 4. 修法

按"由轻到重" 4 种:

### 修法 1(最快,本地开发用):客户端加 `-k` / `--insecure` 跳过 verify

```bash
curl -k https://apiname.teamname.caep.com:8443/healthz
# 业务层能跑,但
# ⚠️ 不能上生产 — TLS 实际上等于"无加密验证",中间人攻击随便做
```

### 修法 2(开发 / 内网用):把 Pod 的自签 cert 加到客户端 truststore

```bash
# 1) 把 Pod 里的 cert 导出
openssl s_client -connect <POD_IP>:8443 -servername apiname.teamname.caep.com \
  -showcerts </dev/null 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' \
  > /tmp/pod-cert.pem

# 2) 加到客户端 truststore (Java)
keytool -importcert -alias pod-server -file /tmp/pod-cert.pem \
  -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit \
  -trustcacerts -noprompt

# 3) 加到系统 truststore (Linux/macOS curl)
sudo cp /tmp/pod-cert.pem /usr/local/share/ca-certificates/pod-server.crt
sudo update-ca-certificates          # Debian/Ubuntu
sudo update-ca-trust                 # RHEL/Fedora
```

但 hostname verify 还是 fail(因为 cert SAN 不覆盖 hostname),所以**这只是 workaround,不算根治**。

### 修法 3(根治 — 重签 cert):把外部访问域名加进 SAN

```bash
# 1) 在 Pod 内重生成 cert,带正确 SAN
keytool -genkeypair -alias server -keystore server.jks \
  -dname "CN=apiname.teamname.caep.com, OU=Demo" \
  -ext "SAN=dns:apiname.teamname.caep.com,dns:localhost,ip:127.0.0.1" \
  -validity 365 -keyalg RSA -keysize 2048 \
  -storetype PKCS12 -storepass '<PWD>'

# 2) 或者:导入 CA 签发的 cert + 自定义 SAN
#    用 CSR 提交给 CA,CA 用自己的 CA 签发,带完整 SAN
keytool -certreq -alias server -keystore server.jks \
  -file server.csr \
  -ext "SAN=dns:apiname.teamname.caep.com,dns:apiname2.teamname.caep.com"
# 然后 openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  #   -CAcreateserial -out server.crt -days 365 \
  #   -extfile <(printf "subjectAltName=DNS:apiname.teamname.caep.com,DNS:apiname2.teamname.caep.com")

# 3) 重签完后导入到 keystore
keytool -importcert -alias server -keystore server.jks \
  -file server.crt -storepass '<PWD>' -trustcacerts

# 4) Pod 重启加载新 cert
```

### 修法 4(根治 — 走 Public CA 自动化):cert-manager + Let's Encrypt / 企业 CA

```yaml
# Cert-manager 配 ingress / Gateway 自动化签发 + 续期
# SAN 由 cert-manager 自动从 Ingress.spec.tls.hosts / Gateway.spec.listeners.hostname 读取
# 用户不用关心 SAN 怎么写 — cert-manager 会跟 Ingress 同步
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: apiname-teamname-caep-com
spec:
  secretName: apiname-teamname-caep-com-tls
  dnsNames:
    - apiname.teamname.caep.com       # cert-manager 自动把 SAN 写成这个
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
```

---

## 5. Pod 内反向自检 — 一分钟内定位问题

如果客户端报了 cert 错,从**Pod 内部**反向看自己实际配置的 cert:

```bash
# 1) 进 Pod(场景 1)或从文件读 keystore(场景 2)
KS=/app/CertKey/team_a_env_server.jks   # 或 cp 出来的本地路径

# 2) 看 cert 的 Subject + SAN
keytool -list -v -alias team_a_env_server -keystore "$KS" -storepass '<PWD>' 2>&1 \
  | grep -E '^Owner:|^Issuer:|SubjectAlt|DNSName|IPAddress'

# 期望看到:
#   Owner: CN=apiname.teamname.caep.com, OU=Demo        ← Subject CN
#   SubjectAlternativeName [
#     DNSName: apiname.teamname.caep.com                  ← ✅ 客户端访问的域名
#     IPAddress: 127.0.0.1
#   ]

# 如果 Owner CN 跟客户端访问域名对得上但 SAN 缺失 → Subject CN ≠ SAN → 客户端用 SAN 校验 → 失败
# 如果 Owner CN 是 localhost 但客户端访问 apiname.teamname.caep.com → 错位 → 失败

# 3) 对比客户端访问的 hostname 列表
EXPECTED_HOSTS="apiname.teamname.caep.com,localhost"   # 来自客户端调用方的配置
ACTUAL_SAN=$(keytool -list -v -alias team_a_env_server -keystore "$KS" -storepass '<P>' 2>&1 \
  | awk '/SubjectAlternativeName/,/]/' | grep -oE 'DNS:[^,]]*|IP:[^,]]*' | sort -u)
echo "客户端期望的 host:"
echo "$EXPECTED_HOSTS" | tr ',' '\n'
echo "Pod cert 实际 SAN:"
echo "$ACTUAL_SAN"

# 差集 = 缺失的 SAN,加进重签的 -ext 参数里
comm -23 \
  <(echo "$EXPECTED_HOSTS" | tr ',' '\n' | sort) \
  <(echo "$ACTUAL_SAN" | sed 's/^DNS://' | sed 's/^IP://' | sort)
```

---

## 6. Tomcat 服务端"为什么 cert 没覆盖 hostname"的额外细节

### 6.1 Subject CN vs SAN 的现代规则

**RFC 6125 明确规定**:现代客户端(JSSE / OpenSSL / curl)做 hostname verification 时**只看 SAN,不看 Subject CN**。

```bash
# cert 内容:
Owner: CN=apiname.teamname.caep.com
SubjectAlternativeName:
    DNS:other.example.com    ← SAN 不包含 apiname.teamname.caep.com

# 客户端 verify 时:
#   "访问 hostname = apiname.teamname.caep.com"
#   "cert SAN = [other.example.com]"
#   → 不匹配 → SSLHandshakeException
#
# 即使 Subject CN 跟访问 hostname 一字不差,也没用 — RFC 6125 强制用 SAN
```

**旧教训**:很多老教程说"把 hostname 写进 CN 就行",**错的**。必须写进 SAN。

### 6.2 wildcard SAN 的限制

```bash
# 错的期望:
SubjectAlternativeName:
    DNS:*.caep.com    ← wildcard

# 客户端 verify 时:
#   "访问 hostname = apiname.teamname.caep.com"
#   "cert SAN = [*.caep.com]"
#   → *.caep.com 匹配 apiname.teamname.caep.com → ✅ 通过
#
# 但 wildcard 只能匹配一级子域:
#   *.caep.com 能匹配 apiname.caep.com,但不能匹配 deep.apiname.caep.com
#   *.caep.com 也不能匹配 caep.com 本身
#
# 通配符必须匹配整左起一个 label:*.example.com 匹配 a.example.com,不能匹配 example.com
```

### 6.3 IP 在 SAN 里的写法

```bash
# === 错 ===
SubjectAlternativeName:
    DNS:127.0.0.1    ← IP 写成 DNS 类型 → 部分客户端不认

# === 对 ===
SubjectAlternativeName:
    IP:127.0.0.1    ← IP 必须写成 IPAddress 类型(不是 DNS)

# keytool 写法:
keytool -genkeypair -ext "SAN=dns:localhost,ip:127.0.0.1" ...

# openssl 写法:
openssl x509 -req ... -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1")
```

**判定**:直接 `curl https://<Pod_IP>:8443/...` 报 hostname mismatch,但 `curl https://localhost:8443 -k` 不报错(假设 localhost 在 SAN 里)→ 客户端拿 IP 做 hostname verify,SAN 里没写 IP 类型 → 失败。

---

## 7. 速查 — 一页纸诊断流程

```
客户端 curl https://apiname.teamname.caep.com:8443/healthz
  ↓
  报 SSL certificate problem?
  ├─ 是 → 看 err code
  │   ├─ err 20 (unable to get local issuer cert) → 自签 cert
  │   └─ err 62 (hostname mismatch) → SAN 不覆盖 ← 本文档主场景
  │
  └─ 否(比如连接拒绝 / 协议错) → 不是 cert 问题,去看 03 / 走 01 场景 1
  ↓
  从 Pod 内拿 cert 看实际 SAN:
  keytool -list -v -alias <alias> -keystore <file> -storepass <pwd>
  ↓
  客户端期望 host:apiname.teamname.caep.com
  cert SAN 里有没有?  ┌─ 没有 → 重签 cert 加进 -ext SAN=
                     └─ 有    → 但客户端还报错?看 02 验证 chain / 信任链
  ↓
  重启 Pod 加载新 cert → curl 验证

跨平台附注:curl err 20 在 macOS LibreSSL / Linux OpenSSL / Windows Schannel 上
报法略不同,但 "Hostname mismatch" 都是 err 62。判别时只看这个数字即可。
```

---

## 8. 跟现有文档的关联

| 本文小节 | 关联 |
|---|---|
| §2.1 客户端 curl 报错分析 | `01-shell-access-strategies.md` §3(外部 dial 视角) |
| §2.3 openssl s_client 反向取 cert | `02-keytool-openssl-cheatsheet.md` §2.3-2.4(`openssl s_client` 详解) |
| §2.4 / §5 Pod 内 keystore 解析 | `02-keytool-openssl-cheatsheet.md` §1.1-1.2 |
| §3 根因 5(平台覆盖) | `03-spring-boot-yaml-ssl-anatomy.md` §3.2(配置优先级) |
| §4 修法 4(cert-manager) | 引用 `~/git/knowledge/develop/java/java-auth/` 同级 cert 相关文档 |

---

## 9. 验证 — 本文档自己怎么自检

| 验证项 | 方法 | 预期 |
|---|---|---|
| `keytool -list -v` 在本机可用 | `keytool -list -v -keystore ../simple-https-demo/src/main/resources/ssl/server-keystore.p12 -storepass changeit` | 看到 `DNSName: localhost`(确认现有 demo cert SAN 是 localhost,**不** 覆盖外部域名 → 走 `curl https://localhost:8443` 通,`curl https://other.example.com:8443 -k` 也通但不安全) |
| `openssl s_client -servername` SNI 路由 | 用现有 keystore 启动 demo 后,分别 `-servername localhost` 和 `-servername wrong.example.com` dial | 都拿到同一张 cert(因为 Tomcat 只配了一份 cert,SNI routing 未启用) |
| curl err code 数字含义 | `man curl` 搜 "SSL certificate problem" | 确认 err 20 = issuer / err 62 = hostname |

**总结**:本文档是 `01-shell-access-strategies.md` §3.5"只能从外部访问"场景的**专题深挖** — 当外部访问报 cert 错时,**第一件事是看客户端报的具体 err code**。err 62 (Hostname mismatch) + 绑 IP 跳过 -k 又能通 = 100% 是 SAN 没覆盖外部域名,**按 §4 修法 3 重签 cert 加 SAN** 是根治路径。