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

# 验证 curl（-k 自签名 = 用 server.crt 作为 CA，本质一样但显式控制信任对象）
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

## 生成自签名测试证书脚本模板

见 `references/self-signed-cert-gen.md`