# 自签名证书生成脚本

gen.sh 执行后会生成：

| 文件 | 用途 | 部署位置 |
|------|------|---------|
| `ca.crt` | 客户端 --cacert 用 | 客户端机器 |
| `server.crt` | 服务器证书（由 CA 签发） | 服务器 TLS 配置 |
| `server.key` | 服务器私钥 | 服务器 TLS 配置 |

## 部署到 Istio Gateway

```bash
# 创建 Secret（已有则替换）
kubectl create secret tls gateway-tls \
  --cert=server.crt \
  --key=server.key \
  -n istio-system \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 部署到 GKE Gateway

```bash
# 生成 base64
cat server.crt | base64 | tr -d '\n'
cat server.key | base64 | tr -d '\n'

# 写入 Secret
kubectl create secret tls gateway-tls \
  --cert=server.crt \
  --key=server.key \
  -n gateway-system \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 客户端验证

```bash
curl -v --resolve 'test.team-a.appdev.aibang:443:88.88.243.168' \
  --cacert ca.crt \
  'https://test.team-a.appdev.aibang/'
```

## 验证脚本生成的证书

```bash
# 确认 issuer 匹配
openssl x509 -in ca.crt -noout -subject
openssl x509 -in server.crt -noout -issuer
# 两者 issuer 应该一致

# 确认服务器实际证书和本地证书是否配套
echo | openssl s_client -connect 88.88.243.168:443 -servername test.team-a.appdev.aibang 2>/dev/null | openssl x509 -noout -issuer
# 如果和 server.crt 的 issuer 不匹配，需要重新配置服务器
```