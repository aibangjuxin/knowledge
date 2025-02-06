对于企业内部信任的多域名 PEM 证书，我建议采用以下最佳实践：

1. **按需提取策略**
- 只提取当前应用实际需要访问的域名对应的证书
- 避免存储整个企业信任链，减少不必要的证书存储
- 降低安全风险，遵循最小权限原则

2. **具体操作步骤**

```bash
# 1. 首先查看当前 PEM 包含的所有证书信息
openssl crl2pkcs7 -nocrl -certfile full-cert.pem | openssl pkcs7 -print_certs -text -noout

# 2. 提取特定域名的证书
# 假设要提取 example.internal.com 的证书
openssl x509 -in full-cert.pem -text -noout | grep "Subject:" | grep "example.internal.com"
```

3. **使用 awk 提取指定证书**

```bash
# 创建一个脚本来提取指定域名的证书
#!/bin/bash
DOMAIN="example.internal.com"
awk -v domain="$DOMAIN" '
  /BEGIN CERTIFICATE/,/END CERTIFICATE/ {
    cert = cert $0 ORS
  }
  /END CERTIFICATE/ {
    if (cert ~ domain) {
      print cert
    }
    cert = ""
  }
' full-cert.pem > specific-domain.pem
```

4. **存储到 Secret Manager**

```bash
# 将提取的证书存储到 Secret Manager
gcloud secrets create domain-specific-cert \
    --data-file=specific-domain.pem \
    --labels=domain=example-internal-com
```

这样做的好处是：
1. 减小存储空间，避免超出 Secret Manager 限制
2. 提高安全性，降低证书泄露风险
3. 便于管理和更新，每个域名的证书可以独立维护
4. 符合最小权限原则，应用只能访问它需要的证书

如果后续需要访问其他域名，可以按需从主 PEM 文件中提取对应证书并存储。