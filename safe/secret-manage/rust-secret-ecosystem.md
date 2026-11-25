# Rust 生态里的 Secret 相关清单

**Date:** 2026-11-25
**数据来源:** `cargo search` / `cargo info`（crates.io 实时查询）+ GitHub API（星标数、语言、许可证）。
**状态:** 仅查询，**未安装任何 crate 或工具**。

> 配套阅读：[rust-toolchain-and-secret-manager.md](rust-toolchain-and-secret-manager.md)、
> [vault-rust-init-container-poc.md](vault-rust-init-container-poc.md)（主线 POC 设计）

---

## 一、现成的 Secret Manager / Secret CLI（Rust 实现）

| 项目 | 语言 | ★ | 许可证 | 定位 | 备注 |
|:---|:---|---:|:---|:---|:---|
| [jdx/fnox](https://github.com/jdx/fnox) | Rust | 2420 | MIT | 加密的本地/远程 secret manager | 与 `mise` 同作者，主打声明式配置 + 注入环境变量 |
| [fwdai/rowel](https://github.com/fwdai/rowel) | Rust | 971 | GPL-3.0 | Local-first Secrets Manager | 注意 GPL 许可，商用需评估 |
| [aws/aws-workload-credentials-provider](https://github.com/aws/aws-workload-credentials-provider) | Rust | 709 | — | AWS Secrets Manager Agent（官方重写版） | **AWS 官方维护**，最值得参考的「agent 模式」实现 |
| [PierreBeucher/novops](https://github.com/PierreBeucher/novops) | Rust | 471 | LGPL-3.0 | 跨平台 secret & config manager（开发/CI） | 配置文件 → 环境变量，LGPL 动态链接友好 |
| [dopbase/dopbase](https://github.com/dopbase/dopbase) | Rust | 211 | Apache-2.0 | 单文件自托管 secrets manager | 部署形态极简 |
| [neosmart/securestore-rs](https://github.com/neosmart/securestore-rs) | Rust | 171 | — | 加密的、git 友好的文件型 secret manager | 文件型存储 |
| [woodruffw/kbs2](https://github.com/woodruffw/kbs2) | Rust | 131 | MIT | 基于 `age` 加密的 secret manager | ⚠️ **已归档（archived）**，不建议新采用 |
| [mikeleppane/chamber](https://github.com/mikeleppane/chamber) | Rust | 105 | MIT | 加密存储 + 终端 UI 的 local-first secret manager | AWS SSM 后端 |

### crates.io 上可直接 `cargo install` 的 CLI

| crate | 版本 | 用途 |
|:---|---:|:---|
| `gman` | 0.5.0 | 通用命令行 secret 管理与注入工具（支持 Vault） |
| `secretspec` | 0.21.1 | 声明式的 secret provider 统一接口（cachix 出品） |
| `monosecret` | 0.5.0 | 声明式 secrets，任意环境、任意 provider |
| `ripsecrets` | 0.1.11 | 阻止把 secret key 提交进源码的 CLI |
| `cargo-audit` | 0.23.0 | 审计 `Cargo.lock` 中的已知漏洞（RustSec） |

---

## 二、Secret 相关 Crates（作为库使用）

### 内存安全 / 脱敏（写 secret 代码的必备）

| crate | 版本 | 说明 |
|:---|---:|:---|
| `secrecy` | 0.10.3 | secret 包装类型：防止被意外复制/打日志，drop 时安全擦除（Zeroize） |
| `sanitization` | 2.2.0 | 依赖无关的 `no_std` secret 内存擦除 |
| `redact` | 0.1.11 | 把 secret 排除在日志之外的轻量库 |
| `redactable` | 0.15.2 | struct 级自动脱敏（适合日志中间件） |

### 云厂商 / Vault 客户端

| crate | 版本 | 说明 | 维护方 |
|:---|---:|:---|:---|
| `google-secretmanager1` | 7.0.0+20251209 | GCP Secret Manager 完整客户端 | 代码生成（google-apis-rs），非 google-cloud-rust 官方重点库 |
| `aws-sdk-secretsmanager` | 1.129.0 | AWS Secrets Manager | **AWS 官方**（awslabs/aws-sdk-rust） |
| `azure_security_keyvault_secrets` | 1.1.0-beta.2 | Azure Key Vault Secrets | Microsoft 封装（beta） |
| `hashicorp_vault` | 2.1.1 | HashiCorp Vault API 客户端 | ⚠️ 社区（chrismacnaughton/vault-rs），**非官方**，2022-11 后停更 |
| `hashicorp-keyvault` | 0.1.1 | 简单的 secret CRUD 封装 | 社区 |
| `grow-hashicorp-vault` | 0.2.0 | Grow Codes 出品的 Vault Rust SDK | 社区 |
| `keeper-secrets-manager-core` | 17.4.0 | Keeper Secrets Manager Rust SDK | 厂商 |
| `bitwarden` / `bws` | 2.1.0 | Bitwarden Secrets Manager SDK / CLI | 厂商 |
| `secret-vault` | 3.3.0 | **统一抽象**：GCP + AWS + Azure Key Vault + HashiCorp Vault + K8s + 环境变量 | 社区 |

> `secret-vault` 这个 crate 的定位很贴题：如果我们想写「一个客户端读多个 provider」，
> 它就是现成的抽象层，可以少写很多胶水代码。

### 加密 / 扫描 / 系统集成

| crate | 版本 | 说明 |
|:---|---:|:---|
| `age` | 0.12.1 | 现代加密库（SOPS 的默认后端；CLI 是 `age`/`rage`） |
| `keyring` | 4.2.0 | 跨平台系统钥匙串（macOS Keychain / Linux Secret Service / Windows Credential Manager） |
| `secretscan` | 0.2.5 | 高性能 secret 扫描器（Aho-Corasick + 正则 + 熵值） |
| `secrets_scanner` | 0.2.3 | 同类 secret 扫描库 |
| `secret` | 0.2.0 | Linux libsecret 绑定 |
| `prs-lib` | 0.5.9 | 密码管理器 CLI 库（GPG + git 同步） |
| `kms-rs` 之类云 KMS | — | 查 crate 时用 `cargo search kms` 按需确认 |

---

## 三、Vault 客户端 Rust crate 选型（重点）

写 init container 接 Vault 时，客户端选型直接决定 POC 成败。**实测结论**：

| crate | 版本 | 最后提交 | K8s auth | 其他 auth | 依赖 | 结论 |
|:---|---:|:---|:---|:---|:---|:---|
| **`vault-client-rs`** | 0.8.0 | **2026-08-20** | ✅ | Token / AppRole / Userpass / LDAP / TLS / GitHub / OIDC-JWT / AWS / Azure / GCP / Kerberos / RADIUS | tokio 1, reqwest 0.13, **secrecy 0.10**, zeroize 1, thiserror 2 | ✅ **推荐** |
| `hashicorp_vault` | 2.1.1 | **2022-11-15** | ❌ | AppRole / Token | reqwest 0.11, base64 0.13（老） | ⚠️ 停更 + 缺 K8s auth，排除 |
| `vault_client` | 0.3.2 | 陈旧 | ❌ | 少量 | futures 0.1（老） | ❌ 排除 |
| `galata-vault-client` | 0.1.0 | — | ❌ | 仅请求签名 | — | ❌ 定位不符 |
| 手写 `reqwest` | — | 自己维护 | 自己实现 | 自己实现 | — | 🔧 备选（API 面窄时最省心） |

### 为什么选 `vault-client-rs`

- **作者 michaelklishin 是 HashiCorp 工程师**（Vault / Consul 方向），2026-08 仍在更新 —— 社区背书里最强的一个；
- 依赖里**自带 `secrecy` + `zeroize`**：secret 与 token 在内存里自动擦除，不需要自己包；
- **每个 API handler 是 trait**（`Kv2Operations` / `TransitOperations` / `PkiOperations`…），
  可以换 mock → **POC 阶段无需真 Vault 即可写单测**；
- feature：`blocking`（同步写 init container 够用）、`auto-renew`（token 自动续期）、`tokio-util`；
- `rust-version = 1.94` → 本机 rustc **1.95.0 满足**；
- ⚠️ 1.0 前可能 breaking change；★ 仅 2；依赖 `reqwest 0.13`/`rand 0.10` 较新，注意版本冲突。

> 结论：**POC 直接用 `vault-client-rs`**，但在外面包一层自己的 trait
> （如 `trait SecretProvider`），把 breaking change 的影响收敛在一个文件里。

---

## 四、init container / sidecar 的依赖 crate（实测版本）

| crate | 版本 | 用途 |
|:---|---:|:---|
| `vault-client-rs` | 0.8.0 | Vault 客户端（auth + KV v1/v2 + …） |
| `tokio` | 1.54.1 | 异步运行时 |
| `reqwest` | 0.13.5 | HTTP（vault-client-rs 已依赖） |
| `secrecy` | 0.10.3 | secret 包装类型，drop 时擦除 |
| `zeroize` | 1.x | 内存擦除底层 |
| `minijinja` | 3.1.0 | 模板渲染（替代 Vault Agent 的 Go template），依赖少 |
| `tera` | 1.20.1 | 模板备选（Jinja2 语法） |
| `handlebars` | 6.4.4 | 模板备选（mustache 语法） |
| `notify` | 9.0.0 | 文件事件监听（轮转阶段） |
| `kube` | 5.2.0 | K8s client（可选：回写 K8s Secret / 自定义资源） |
| `serde_yaml_ng` | 0.10.0 | YAML（`serde_yaml` 0.9.34 已 deprecated） |
| `tracing` | 0.1.44 | 结构化日志（**注意不要把 secret 打进日志**） |
| `thiserror` | 2.x | 错误类型 |

---

## 五、Kubernetes 方向的 Rust secret 后端

在 crates.io 上搜 `kubernetes secret` 能看到一批 K8s Secret 后端实现：

- `greentic-secrets-provider-k8s`（1.3.0-research.2）
- `kubevault`（1.1.0）— 把 K8s 集群变成 secret management system
- `neuron-secret-k8s`（0.4.0）
- `zopp-operator`（0.1.1）
- `secretx-k8s`（0.5.1）
- `esh-providers-k8s`（0.1.0）

> 结论：**Rust 侧 K8s secret 生态多为实验/研究级**，生产上 K8s Secret 生态仍以
> External Secrets Operator（Go）、Sealed Secrets（Go）、ESO 的 Rust 化尝试为主。
> 选型时不要只看语言热度。

---

## 六、按场景的选型速查

| 场景 | 优先看 | 理由 |
|:---|:---|:---|
| GCP 环境内部注入 secret | 现有 Java/Go 方案 + `gcp/secret-manage/` | 不需要新造轮子；Rust 客户端 `google-secretmanager1` 非官方重点维护 |
| 多云统一 secret CLI | `fnox` / `novops` / `secret-vault` crate | 已有成品，MIT 优先 |
| **复用 Vault（自建）并自研 init container** | `vault-client-rs`（**不是** `hashicorp_vault`）+ 自己的 trait 抽象 | 见 [POC 设计](vault-rust-init-container-poc.md) |
| K8s secret 注入 sidecar | `aws-workload-credentials-provider` 作参考实现 | AWS 官方 Rust agent，架构最值得抄 |
| 本地开发，避免明文 `.env` | `fnox` / `novops` / `chamber` | 开发者体验最好的切入点 |
| 依赖漏洞治理 | `cargo-audit` + `cargo deny` + `Cargo.lock` 入库 | Rust 生态必备三件套 |

---

## 七、查询命令速查

```bash
cargo search "secret manager" --limit 20
cargo search hashicorp --limit 20
cargo info google-secretmanager1        # 版本 / 许可证 / 仓库 / feature
cargo info hashicorp_vault
cargo info vault-client-rs --verbose        # 看 features 与依赖树

# 查某个 crate 的最后更新时间（判断是否停更）
curl -s https://api.github.com/repos/<owner>/<repo> | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['pushed_at'], d['stargazers_count'])"

# GitHub 侧：按语言+关键词找项目
curl -s 'https://api.github.com/search/repositories?q=secret+manager+language:Rust&sort=stars&per_page=20'
```
