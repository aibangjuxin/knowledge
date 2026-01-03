# Safe (Security) 知识库

## 目录描述
本目录包含安全相关的知识、安全实践、漏洞修复和安全工具使用。

## 目录结构
```
safe/
├── cert/                     # 证书相关文件和配置
├── certs/                    # 证书文件
├── cwe/                      # CWE（Common Weakness Enumeration）相关内容
├── cyberflows/               # 网络安全流程相关内容
├── docs/                     # Markdown文档
├── gcp-safe/                 # GCP安全相关内容
├── how-to-fix-violation/     # 违规修复指南
├── scripts/                  # Shell脚本
├── tools/                    # 工具和资源文件
├── wiz/                      # Wiz安全工具相关内容
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `api_security_tips.md`: API安全提示
- `appd-violation.md`: AppDynamics违规相关
- `auth*.md`: 认证相关
- `cve.md`: CVE漏洞相关
- `cyber*.md`: 网络安全相关
- `Encrypted.md`: 加密相关
- `jwt*.md`: JWT相关
- `ssl*.md`: SSL相关
- `waf*.md`: WAF相关

### certs/ - 证书文件
- 证书相关文件（.crt, .pem, .key等）

### scripts/ - 脚本
- Shell脚本文件

### tools/ - 工具和资源
- 图片文件等资源

### cert/ - 证书相关配置
- 证书相关配置和管理

### 安全工具
- `wiz/`: Wiz安全扫描工具相关内容
- `cwe/`: CWE安全弱点枚举相关内容

### 云安全
- `gcp-safe/`: GCP安全配置
- `cyber-with-cloud-armor.md`: 云防护相关 (在docs/目录)
- `gke-policy-control.md`: GKE策略控制 (在docs/目录)

### 漏洞和修复
- `how-to-fix-violation/`: 违规修复指南
- `cve.md`: CVE漏洞信息 (在docs/目录)
- `appd-violation.md`: AppDynamics违规处理 (在docs/目录)

### Web应用安全
- `waf*.md`: WAF（Web应用防火墙）相关 (在docs/目录)
- `api_security_tips.md`: API安全最佳实践 (在docs/目录)

## 快速检索
- 认证: 查看 `docs/` 目录中的 `auth*.md`, `jwt*.md` 文件
- 证书: 查看 `cert/` 目录及 `docs/` 目录中的 `analyze-showcerts.md`
- SSL/TLS: 查看 `docs/` 目录中的 `ssl*.md` 文件
- WAF: 查看 `docs/` 目录中的 `waf*.md` 文件
- GCP安全: 查看 `gcp-safe/` 目录
- 漏洞修复: 查看 `how-to-fix-violation/` 目录
- 容器安全: 查看 `docs/` 目录中的 `Periodic-container-scanning.md`
- 脚本: 查看 `scripts/` 目录
- 证书文件: 查看 `certs/` 目录