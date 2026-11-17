# SSL / TLS

SSL/TLS 证书与安全协议知识库。

## 目录结构

```
ssl/
├── docs/                  # SSL 文档（6 文件）
├── ingress-ssl/           # Ingress SSL 配置
├── scripts/               # 脚本
└── text/                  # 文本资料
```

## 根目录残留文件

OpenSSL-curl.md, README.md, certificate-truststore.md, compare-san-sni.md, cross-project-fqdn-best-practices.md, current-fqdn-status.md, debug-ssl-chatgpt.md, debug-ssl.md, gcp-glb-ssl-certificate-update.md, gskit.md, merged-scripts.md, openssl.md, verify-baidu.md, verify-domain-ssl-enhance.sh, verify-domain-ssl.sh, verify-fqdn.sh, verify-url-cert.sh, why-san.md

## 主要脚本

| 脚本 | 用途 |
|---|---|
| `verify-fqdn.sh` | FQDN 解析 + 多 DNS 解析器比对 + TLS 证书分析 |
| `verify-url-cert.sh` | 按 URL 检查 TLS 证书与加密强度（CWE-326 基线）：密钥长度、签名算法、协议版本、密码套件、DH 参数、有效期、主机名校验 |
