# Sectigo 与 Java truststore (cacerts) 检查

> 一句话:Sectigo 是全球最大的商业 CA 之一(2018 年由 Comodo CA 改名而来)。Java 自带的
> `cacerts` 文件就是 JVM 信任的根证书库,只要里面包含 Sectigo 的根证书,你用 Java 访问
> 由 Sectigo 签发的 HTTPS 站点就不会报 `PKIX path building failed`。

---

## 1. 什么是 Sectigo

**Sectigo**(原名 Comodo CA)是全球市场份额最大的商业证书颁发机构(CA)之一。

| 维度 | 内容 |
|---|---|
| 前身 | **Comodo CA**(成立于 1998 年) |
| 改名时间 | **2018 年 1 月**,Comodo CA 集团重组成 Sectigo Limited |
| 业务 | SSL/TLS 证书(EV / OV / DV)、代码签名、邮件(S/MIME)、IoT 设备证书 |
| 规模 | 截至 2024 年,累计签发超过 **1 亿**张数字证书,在 Web 公共信任 CA 中市场占有率第一 |
| 浏览器信任 | Mozilla / Apple / Google / Microsoft 根证书计划全部内置 Sectigo 根 |
| 旗下子 CA | **USERTrust** 系列(原 Comodo 子品牌)也是 Sectigo 在运营 |

为什么你会经常在 SSL 链里看到它:
- **便宜且自动化的 DV 证书**(Let's Encrypt 之外最常见的选择)
- 大量中小网站、API、邮件服务器使用 Sectigo DV
- **CertCentral / Sectigo API** 是企业批量签发的主要入口

证书链里典型长相(用 `openssl s_client -showcerts` 抓 HTTPS):

```
[服务器证书]  Issuer: Sectigo RSA Domain Validation Secure Server CA
                └─ 中间 CA:  Sectigo RSA Domain Validation Secure Server CA
                   └─ 根 CA:   USERTrust RSA Certification Authority  (或 Sectigo 自己的根)
                      └─ 顶级根: AAA Certificate Services  (老的 Comodo 根,2010 年前签发的还在用)
```

---

## 2. Java cacerts 是什么

Java 程序访问 HTTPS / TLS 时,真正做"证书是否可信"判断的,是 JVM 启动时加载的一个
**JKS 格式 keystore 文件**,路径在 JDK 的 `$JAVA_HOME/lib/security/cacerts`。

- 默认密码:**`changeit`**(历史遗留,所有 JDK 都一样)
- 默认包含 **~100 张** 主流 CA 根证书(Mozilla / Apple / Microsoft / 各 OS 根证书计划的子集)
- **谁来更新它**:Oracle / Adoptium / Homebrew / Microsoft 等 JDK 厂商在每次 JDK
  小版本升级时同步更新 cacerts(本机 JDK 26.0.1 的 cacerts 时间戳是 2026-03-10)
- Java 9+ 支持 `-cacerts` 快捷选项,直接指向默认文件,不用写完整路径

**重要: cacerts 是 JDK 全局共享的。** 一个 Java 进程不传 `-Djavax.net.ssl.trustStore=...`
时,都用 `JAVA_HOME/lib/security/cacerts`。在 Docker / CI / IDE 里要分清"我用的是哪个
JDK 的 cacerts"。

---

## 3. 怎么检查你的 JDK 是否信任 Sectigo

### 3.1 一次性命令(检查当前 Java 默认 truststore)

```bash
# 找到当前 java 对应的 cacerts
JAVA_HOME=$(java -XshowSettings:properties -version 2>&1 | awk -F= '/java.home/ {gsub(/^[ \t]+/, "", $2); print $2}')
CACERTS="$JAVA_HOME/lib/security/cacerts"
echo "cacerts: $CACERTS"

# 用 keytool 列所有证书,grep Sectigo / Comodo / USERTrust / AddTrust
keytool -list -cacerts -storepass changeit 2>/dev/null \
  | grep -iE "sectigo|comodo|usertrust|addtrust"
```

### 3.2 检查单个根证书(以 `sectigotlsroote46` 为例)

```bash
keytool -list -cacerts -storepass changeit -alias sectigotlsroote46 -v
```

输出会包含 `Owner:` `Issuer:` `Valid from:` 到 `Valid until:` 的完整 cert 详情。

### 3.3 一键脚本(通用,放进 `~/.hermes/scripts/`)

```bash
#!/bin/bash
# check-sectigo-trust.sh - 检查当前 Java 是否信任 Sectigo 证书家族
set -e
JAVA_HOME=$(java -XshowSettings:properties -version 2>&1 | awk -F= '/java.home/ {gsub(/^[ \t]+/, "", $2); print $2}')
CACERTS="$JAVA_HOME/lib/security/cacerts"

if [[ ! -f "$CACERTS" ]]; then
  echo "ERROR: cacerts not found at $CACERTS"
  exit 1
fi

echo "JDK:    $JAVA_HOME"
echo "cacerts: $CACERTS"
echo "Total trusted certs: $(keytool -list -cacerts -storepass changeit 2>/dev/null | grep -c 'trustedCertEntry')"
echo
echo "=== Sectigo / Comodo / USERTrust family ==="
FOUND=$(keytool -list -cacerts -storepass changeit 2>/dev/null \
  | grep -iE "sectigo|comodo|usertrust|addtrust" || true)

if [[ -n "$FOUND" ]]; then
  echo "$FOUND"
  echo
  echo "✅ YES - This JDK trusts Sectigo."
else
  echo "❌ NO Sectigo root in cacerts."
  echo "Fix: update JDK (preferred) or import Sectigo roots manually:"
  echo "  curl -O https://crt.sectigo.com/SectigoPublicServerAuthenticationRootE46.pem"
  echo "  keytool -importcert -cacerts -storepass changeit \\"
  echo "    -alias sectigotlsroote46 -file SectigoPublicServerAuthenticationRootE46.pem"
fi


#!/bin/bash
# check-sectigo-trust.sh - Verify if the current Java keystore trusts Sectigo/Comodo roots
set -e

# 1. Locate JAVA_HOME accurately
JAVA_HOME=$(java -XshowSettings:properties -version 2>&1 | awk -F= '/java.home/ {gsub(/^[ \t]+/, "", $2); print $2}')

# 2. Support both modern (JDK 9+) and legacy layout paths for cacerts
if [[ -f "$JAVA_HOME/lib/security/cacerts" ]]; then
  CACERTS="$JAVA_HOME/lib/security/cacerts"
elif [[ -f "$JAVA_HOME/conf/security/cacerts" ]]; then
  CACERTS="$JAVA_HOME/conf/security/cacerts"
else
  echo "ERROR: cacerts not found under $JAVA_HOME"
  exit 1
fi

echo "JDK:     $JAVA_HOME"
echo "cacerts: $CACERTS"

TOTAL_CERTS=$(keytool -list -cacerts -storepass changeit 2>/dev/null | grep -c 'trustedCertEntry' || true)
echo "Total trusted certs: $TOTAL_CERTS"
echo
echo "=== Searching Sectigo / Comodo / USERTrust roots ==="

# Crucial Fix: Use '-v' to print the full Distinguished Name (DN) instead of just the alias.
# This prevents false negatives where the alias doesn't contain the string but the owner does.
FOUND_DETAILS=$(keytool -list -v -cacerts -storepass changeit 2>/dev/null \
  | grep -iE "Owner:|Issuer:|Alias" \
  | grep -iB1 -A1 -E "sectigo|comodo|usertrust|addtrust" || true)

if [[ -n "$FOUND_DETAILS" ]]; then
  echo "$FOUND_DETAILS" | grep -v "^--"
  echo
  echo "✅ YES - This JDK explicitly trusts the Sectigo/Comodo family."
else
  echo "❌ NO Sectigo root found in cacerts."
  echo "----------------------------------------------------"
  echo "Fix: Update your JDK (preferred) or manually import the missing root:"
  echo "  curl -sO https://crt.sectigo.com/SectigoPublicServerAuthenticationRootE46.pem"
  echo "  sudo keytool -importcert -cacerts -storepass changeit -noprompt \\"
  echo "    -alias sectigotlsroote46 -file SectigoPublicServerAuthenticationRootE46.pem"
fi
```

运行:
```bash
chmod +x check-sectigo-trust.sh
./check-sectigo-trust.sh
```

---

## 4. 本机实测结果(2026-06-23, JDK 26.0.1 Homebrew)

```
JDK:     /opt/homebrew/Cellar/openjdk/26.0.1/libexec/openjdk.jdk/Contents/Home
cacerts: /opt/homebrew/Cellar/openjdk/26.0.1/libexec/openjdk.jdk/Contents/Home/lib/security/cacerts
Total trusted certs: 109

=== Sectigo / Comodo / USERTrust family ===
addtrustexternalca [jdk]
addtrustqualifiedca [jdk]
comodoaaaca [jdk]
comodoeccca [jdk]
comodorsaca [jdk]
sectigocodesignroote46 [jdk]
sectigocodesignrootr46 [jdk]
sectigotlsroote46 [jdk]
sectigotlsrootr46 [jdk]
usertrusteccca [jdk]
usertrustrsaca [jdk]

✅ 结论:当前 JDK (Homebrew openjdk 26.0.1) 已信任 Sectigo。
   11 张 Sectigo / Comodo / USERTrust / AddTrust 根证书全部在内置 cacerts 中。
```

---

## 5. 如果检查结果是"不信任",怎么修

按推荐度从高到低:

### 5.1 升级 JDK(推荐)

JDK 8u292+ / 11.0.11+ / 17+ / 21+ 的 cacerts 都内置 Sectigo 根。**升级 JDK 是最干净的做法**,
证书过期 / 撤销 / 新 CA 都会自动同步。

### 5.2 单独更新 cacerts(保留 JDK 主版本)

从 Adoptium / Azul / Oracle 官方下载**最新的 cacerts 文件**,覆盖到 `$JAVA_HOME/lib/security/cacerts`
(覆盖前备份)。

### 5.3 手动 import 单张根证书(只针对某个特定 CA)

```bash
# 下载 Sectigo 根(E46 是 2023+ 主流 ECC 根,R46 是 RSA 根)
curl -O https://crt.sectigo.com/SectigoPublicServerAuthenticationRootE46.pem

# import 到系统 cacerts
keytool -importcert -cacerts -storepass changeit \
  -alias sectigotlsroote46 \
  -file SectigoPublicServerAuthenticationRootE46.pem
```

### 5.4 应用级 truststore(不影响全局)

如果只是想让自己写的某个 Java 程序信任 Sectigo,而不想改系统 cacerts,启动时指定:

```bash
java -Djavax.net.ssl.trustStore=/path/to/my-truststore.jks \
     -Djavax.net.ssl.trustStorePassword=changeit \
     -jar myapp.jar
```

---

## 6. 关联问题快速诊断

| 报错 | 真因 | 修复 |
|---|---|---|
| `PKIX path building failed: unable to find valid certification path to requested target` | 目标服务器 cert 的 root 不在 cacerts | 升级 JDK 或 import 对应根 |
| `java.security.cert.CertPathValidatorException: validity check failed` | 证书过期 / 服务器时钟不对 | `date` 看系统时间;或升级 cacerts 让 root 新一些 |
| `SSLHandshakeException: No appropriate protocol` | TLS 版本不匹配(不是 cert 问题) | 升级 JDK 8 / 启用 TLSv1.2+ |
| `sun.security.provider.certpath.SunCertPathBuilderException: issuer is not trusted` | 中间 CA 不在 cacerts(罕见,JDK 应该有) | 同 §5.1 / 5.3 |

诊断时第一动作:**先抓服务端 cert 看 issuer**,再回头查 truststore,而不是先猜客户端 truststore。

```bash
# 看服务端 cert 的 issuer 是什么
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null \
  | openssl x509 -noout -issuer -subject
```

---

## 7. 参考链接

- Sectigo 官网: https://www.sectigo.com/
- Sectigo 根证书下载: https://sectigo.com/knowledge-root
- OpenJDK cacerts 源仓库: https://github.com/openjdk/jdk/blob/master/src/java.base/share/lib/security/cacerts
- Adoptium cacerts 更新记录: https://github.com/adoptium/containers/blob/main/11/jdk/ubi/standard/hotspot/normal/eceprod/apt/usr/lib/jvm/temurin-11-jdk/lib/security/cacerts
