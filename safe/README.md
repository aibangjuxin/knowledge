# Safe (Security) 知识库

安全相关的知识、安全实践、漏洞修复和安全工具使用。

---

## 目录结构

```
safe/
├── cert/                     # 证书配置 & DigiCert EKU 管理
├── cross-site/               # 跨站安全分析（Cookie/Header/代理/Nginx）
├── cyberflows/               # 安全扫描工具（SAST/DAST/SBOM）
├── cwe/                      # CWE（Common Weakness Enumeration）研究
├── docs/                     # 安全主题文档（WAF/JWT/SSL/GKE/容器等）
├── gcp-safe/                 # GCP 安全配置（KMS/IAM/Workload Identity/SSL Policy）
├── get-token/                # Token 获取脚本
├── how-to-fix-violation/     # 安全违规修复指南
├── responsibilities/          # 团队安全职责（代码覆盖率/依赖管理）
├── scripts/                  # 安全侦察脚本（域名/DNS/指纹）
├── tools/                    # 工具资源（图片等）
├── wiz/                      # Wiz 云安全平台集成
└── README.md
```

---

## 快速检索

| 主题 | 路径 |
|------|------|
| 证书管理 / DigiCert EKU | `cert/` |
| 跨站安全（Cookie/Header/SameSite） | `cross-site/` |
| WAF / Cloud Armor | `docs/waf*.md` |
| JWT 认证 | `docs/jwt*.md` |
| SSL/TLS | `docs/ssl*.md`, `docs/flow-ssl.md` |
| GCP 安全（KMS/IAM/Workload Identity） | `gcp-safe/` |
| 容器安全扫描 | `docs/Periodic-container-scanning.md` |
| CVE / 漏洞修复 | `docs/cve.md`, `how-to-fix-violation/` |
| CWE 研究 | `cwe/` |
| 安全工具（Trivy/Checkmarx/Sonar/Wiz） | `cyberflows/`, `wiz/` |
| 安全脚本 | `scripts/` |

---

## 子目录说明

### `cert/` — 证书相关
- DigiCert EKU 迁移计划与评估指南
- 证书检查脚本：`check_eku.sh`, `digicert_impact_assessment.sh`

### `cross-site/` — 跨站安全分析
- `cross-analysis.md` — 跨站分析综合
- `cross-nginx-header*.md` / `.html` — Nginx Header 安全分析
- `cross-site-cookie-deepseek*.md` / `.html` — Cookie + DeepSeek 跨站研究
- `cross-site-nginx-proxy-flow.*` — 代理流程图
- `samesite-deep-dive.md` — SameSite Cookie 深度解析

### `certs/` — 证书数据文件 ⚠️
- **已 gitignore**，不参与版本控制
- 包含 `.crt` / `.pem` / `.txt` 等实际证书数据

### `cyberflows/` — 安全扫描工具
- SAST: Checkmarx, Sonar, FOSS Explorer
- DAST: Trivy, CageFS
- SBOM 生成与管理

### `cwe/` — CWE 安全研究
- 覆盖 CWE-16（错误页面）、CWE-287（认证）、CWE-319（SSL/TLS）、CWE-523、CWE-550、CWE-650、CWE-798 等
- 含 nginx header 安全违规分析
- CVE-2025-68973 相关研究

### `docs/` — 安全主题文档
| 文件 | 内容 |
|------|------|
| `auth*.md` | 认证方法 |
| `jwt*.md` | JWT 相关 |
| `ssl*.md`, `flow-ssl.md` | SSL/TLS |
| `waf*.md` | WAF 规则与故障排查 |
| `gke-psa.md`, `gke-policy-control.md` | GKE 安全策略 |
| `gcp-safe-api-enhance.md` | GCP API 安全增强 |
| `Periodic-container-scanning*.md` | 容器周期性扫描 |
| `appd-violation.md` | AppDynamics 违规 |
| `encrypted.md`, `encypy-asymmetric.md` | 加密 |
| `cyber-with-cloud-armor.md` | Cloud Armor |

### `gcp-safe/` — GCP 安全配置
- KMS: 密钥管理、加解密、key/keyring 设计
- IAM / Workload Identity
- SSL Policy 配置与 Cipher 优化
- 数据分类与 PSA（Private Service Access）
- 权限验证脚本

### `get-token/` — Token 获取
- OAuth2 / Service Account Token 获取脚本
- 含 `.env.example` 和 `.gitignore`

### `how-to-fix-violation/` — 违规修复
- 检测工具、修复策略、CI/CD 集成、自动修复脚本、快速参考

### `responsibilities/` — 安全职责
- 包依赖安全
- Sonar 代码覆盖率

### `scripts/` — 安全侦察脚本
- `basic_recon.sh`, `domain_intel.sh`, `basic-domain-explorer.sh` — 域名/DNS 指纹

### `wiz/` — Wiz 集成
- Wiz 基础信息、与 Gemini/Grok 的集成、Sbom扫描

---

## 原则

- 所有安全配置必须**可部署/可验证**
- 优先使用 GCP 原生安全能力
- 发现新漏洞/风险时主动补充到对应目录
