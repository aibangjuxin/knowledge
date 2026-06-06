---
name: gcp-tls-troubleshooting
description: TLS/HTTPS 证书验证排障指南。当 curl -k 可通但去掉 -k 后 SSL certificate problem 时使用，涵盖自签名证书排查、CA 锚点选择、证书链匹配逻辑。
---

# TLS/HTTPS 证书验证排障

## 症状

`curl -k` 可以访问，但去掉 `-k` 后：
```
SSL certificate problem: self signed certificate
curl: (60) SSL certificate problem: self signed certificate
```

## 排查流程

### Step 1: 提取服务器实际返回的证书

```bash
echo | openssl s_client -connect <HOST>:<PORT> -servername <SNI> 2>/dev/null | openssl x509 -noout -subject -issuer
```

### Step 2: 判断证书类型

| 条件 | 类型 | 说明 |
|------|------|------|
| `subject == issuer` | 自签名证书 | 服务器自己当 CA，自己签自己 |
| `subject != issuer` | CA 签发的证书 | 有一个中间 CA 或根 CA 在上面 |

### Step 3: 比对本地 CA 和服务器 issuer

```bash
# 本地已知 CA 的 issuer
openssl x509 -in /path/to/local-ca.crt -noout -issuer

# 服务器实际证书的 issuer（来自 Step 1）
```

**匹配结果判断**：
- **issuer 匹配** → 服务器用的是这个 CA 签的证书 → `curl --cacert /path/to/local-ca.crt` 即可
- **issuer 不匹配** → 服务器用的是另一个证书链 → 必须用服务器自己的证书作为 CA 锚点

### Step 4: 用服务器证书作为 CA 锚点（适用于自签名或链不匹配场景）

```bash
# 提取服务器证书保存为 CA 信任锚
echo | openssl s_client -connect <HOST>:<PORT> -servername <SNI> 2>/dev/null | openssl x509 -outform PEM > server.crt

# 验证 curl
curl -v --resolve '<HOST>:<PORT>:<IP>' \
  --cacert server.crt \
  'https://<HOST>/'
```

## 根本原因

`--cacert` 需要加载**签发服务器证书的 CA**：
- 如果服务器用 CA-A 签的 cert，就必须用 CA-A 的公钥证书作为 `--cacert`
- 不能用同一条链上其他的 CA（如中间 CA 或根 CA）来验证
- 如果服务器用自签名 cert，则该 cert 本身就是 CA（自己签自己）

## 自签名证书场景说明

服务器返回：`subject=CN=*.example.com, issuer=CN=*.example.com`（自签名）

自签名 cert = cert 本身的公钥同时充当 CA 的角色，所以：
- `curl --cacert server.crt`（用服务器自己的 cert 作为 CA）等价于 `curl -k`（信任该证书）
- 区别在于：显式指定比 `-k` 更安全，因为你知道自己在信任谁

## 常用诊断命令

```bash
# 完整握手信息
openssl s_client -connect <HOST>:<PORT> -servername <SNI> -state -debug

# 只看证书链
openssl s_client -connect <HOST>:<PORT> -servername <SNI> 2>/dev/null | openssl x509 -noout -subject -issuer

# 验证证书链是否合法
openssl s_client -connect <HOST>:<PORT> -servername <SNI> -CAfile ca.crt 2>&1 | grep -E "Verify|error"

# 提取服务器公钥证书
echo | openssl s_client -connect <HOST>:<PORT> -servername <SNI> 2>/dev/null | openssl x509 -outform PEM > server.crt
```

## 证书场景速查

| 场景 | 客户端 --cacert 加载什么 |
|------|------------------------|
| 服务器用 CA-A 签的 cert | 加载 CA-A 的公钥证书 |
| 服务器用中间 CA 签的 | 加载中间 CA 的公钥（需包含完整链） |
| 服务器用自签名 cert | 用该 server cert 本身作为 --cacert |

---

## 关键教训：本 session 实际踩到的坑

**服务器证书和本地证书必须是同一套 CA 体系。**

```
服务器实际证书:  subject=CN=*.team-a.appdev.aibang, issuer=CN=*.team-a.appdev.aibang (自签名)
gen.sh 生成本地: subject=CN=*.team-a.appdev.aibang, issuer=CN=Self-Signed CA (CA 签的)
验证结果: ❌ SSL certificate problem — issuer 不匹配
```

| 场景 | 服务器实际证书 | 本地证书 | 验证结果 |
|------|--------------|---------|---------|
| 同一 CA 签发 | issuer=CN=CA-Name | ca.crt 的 subject=CN=CA-Name | ✅ verify ok |
| 自签名 | subject=issuer（同一个 cert） | 用 server.crt 作为 --cacert | ✅ verify ok |
| CA 不匹配 | issuer=CN=CA-A | 只有 CA-B.crt | ❌ SSL certificate problem |

**核心原则：服务器用哪把钥匙签的证书，客户端就必须用对应的 CA 证书去验证。签发链必须一致。**

排错第一步永远是比较 issuer：
```bash
echo | openssl s_client -connect <HOST>:443 -servername <SNI> 2>/dev/null | openssl x509 -noout -subject -issuer
openssl x509 -in local-ca.crt -noout -subject -issuer
```
## 生成自签名测试证书链（示例）

```bash
#!/bin/bash
OUT_DIR="$(cd "$(dirname "$0")" && pwd)"
CA_CN="Self-Signed CA"
SERVER_CN="*.team-a.appdev.aibang"

# 1. 生成 CA（自签）
openssl genrsa -out "$OUT_DIR/ca.key" 2048
openssl req -x509 -new -nodes -key "$OUT_DIR/ca.key" \
  -sha256 -days 365 \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=Aibang/OU=Gateway/CN=$CA_CN" \
  -out "$OUT_DIR/ca.crt"

# 2. 生成 Server 私钥和 CSR
openssl genrsa -out "$OUT_DIR/server.key" 2048
openssl req -new -key "$OUT_DIR/server.key" \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=Aibang/OU=Gateway/CN=$SERVER_CN" \
  -out "$OUT_DIR/server.csr"

# 3. 用 CA 签发 Server 证书
cat > "$OUT_DIR/server_ext.cnf" <<'EOF'
[v3_ext]
subjectAltName = @alt_names
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = *.team-a.appdev.aibang
DNS.2 = team-a.appdev.aibang
EOF

openssl x509 -req -in "$OUT_DIR/server.csr" \
  -CA "$OUT_DIR/ca.crt" -CAkey "$OUT_DIR/ca.key" \
  -CAcreateserial \
  -days 365 -sha256 \
  -extfile "$OUT_DIR/server_ext.cnf" -extensions v3_ext \
  -out "$OUT_DIR/server.crt"

rm -f "$OUT_DIR/server.csr" "$OUT_DIR/server_ext.cnf"

# 验证
openssl x509 -in "$OUT_DIR/ca.crt" -noout -subject -issuer
openssl x509 -in "$OUT_DIR/server.crt" -noout -subject -issuer
```