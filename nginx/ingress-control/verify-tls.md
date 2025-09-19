证书 Secret 即使能 kubectl get 出来，也可能内容有问题（比如 key 对不上 cert，或者证书链不完整）。你可以按下面几个步骤逐步验证：

---

## **1. 导出 Secret 并解码**

```
# 查看 Secret 基本信息
kubectl get secret aibang-cert-secret -n aibang-api -o yaml

# 导出证书和私钥
kubectl get secret aibang-cert-secret -n aibang-api -o jsonpath='{.data.tls\.crt}' | base64 -d > tls.crt
kubectl get secret aibang-cert-secret -n aibang-api -o jsonpath='{.data.tls\.key}' | base64 -d > tls.key
```

---

## **2. 校验证书和私钥是否匹配**

```
# 提取公钥并比较
openssl x509 -in tls.crt -noout -modulus | openssl md5
openssl rsa  -in tls.key -noout -modulus | openssl md5
```

两者输出的 MD5 必须一致，否则证书和私钥不匹配。

---

## **3. 检查证书基本信息**

```
# 查看证书详细信息
openssl x509 -in tls.crt -noout -text
```

重点检查：

- **Subject CN / SAN** 是否包含你的域名（比如 api.example.com）
    
- **Issuer** 是否来自受信 CA
    
- **Validity** 确认时间范围是否还有效
    

---

## **4. 检查证书链完整性（如果有中间证书）**

  

有些 CA 会给你 **leaf cert** + **intermediate cert**，你必须把它们拼在一起放入 tls.crt：

```
cat leaf.crt intermediate.crt > tls.crt
```

然后再生成 Secret。否则浏览器可能报“不受信任”。

---

## **5. （可选）本地模拟验证**

  

你可以用 openssl 启一个临时 TLS 服务来确认证书是否能正常加载：

```
openssl s_server -key tls.key -cert tls.crt -accept 8443
```

然后另一个终端请求：

```
openssl s_client -connect localhost:8443 -servername api.example.com
```

可以看到证书链和域名校验是否正常。

---

## **6. 验证 Secret 类型**

```
kubectl get secret aibang-cert-secret -n aibang-api -o jsonpath='{.type}'
```

必须输出：

```
kubernetes.io/tls
```

---

✅ 通过以上检查，你就能确认 tls.crt / tls.key 是否匹配、是否包含正确域名、是否完整链路。

---

要不要我帮你写一个 **一键脚本**，比如 check-tls-secret.sh，直接传入 Secret 名和 namespace，就能自动跑完这些检查？

```bash
#!/bin/bash
# 用法: ./check-tls-secret.sh <secret-name> <namespace>

set -e

SECRET_NAME=$1
NAMESPACE=$2

if [ -z "$SECRET_NAME" ] || [ -z "$NAMESPACE" ]; then
  echo "用法: $0 <secret-name> <namespace>"
  exit 1
fi

echo "🔍 检查 Secret: $SECRET_NAME (namespace: $NAMESPACE)"
echo "------------------------------------------------------"

# 1. 确认 Secret 类型
SECRET_TYPE=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.type}')
if [ "$SECRET_TYPE" != "kubernetes.io/tls" ]; then
  echo "❌ Secret 类型错误: $SECRET_TYPE (必须是 kubernetes.io/tls)"
  exit 1
else
  echo "✅ Secret 类型正确: $SECRET_TYPE"
fi

# 2. 导出证书和私钥
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/tls.crt
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/tls.key

# 3. 校验证书和私钥是否匹配
CRT_MD5=$(openssl x509 -in /tmp/tls.crt -noout -modulus | openssl md5)
KEY_MD5=$(openssl rsa -in /tmp/tls.key -noout -modulus | openssl md5)

if [ "$CRT_MD5" != "$KEY_MD5" ]; then
  echo "❌ 证书和私钥不匹配"
  echo "CRT: $CRT_MD5"
  echo "KEY: $KEY_MD5"
  exit 1
else
  echo "✅ 证书和私钥匹配"
fi

# 4. 显示证书基本信息
echo "------------------------------------------------------"
echo "📜 证书信息:"
openssl x509 -in /tmp/tls.crt -noout -subject -issuer -dates -ext subjectAltName || true

# 5. 检查是否包含中间证书
CHAIN_COUNT=$(grep -c "END CERTIFICATE" /tmp/tls.crt)
if [ "$CHAIN_COUNT" -gt 1 ]; then
  echo "✅ 证书链完整, 包含 $CHAIN_COUNT 个证书"
else
  echo "⚠️ 证书链可能不完整, 仅检测到 1 个证书"
  echo "   如果使用的是 CA 签发的证书, 请确认已包含中间证书"
fi

echo "------------------------------------------------------"
echo "🔎 检查完成"
```