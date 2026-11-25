# HashiCorp Vault + Rust init container —— POC 方案设计

**Date:** 2026-11-25
**Status:** 设计稿。**未实现、未安装任何新工具**，文中所有版本号均为 crates.io / GitHub 实时查询结果。
**关联:** [rust-toolchain-and-secret-manager.md](rust-toolchain-and-secret-manager.md)（工具链定位）、[rust-secret-ecosystem.md](rust-secret-ecosystem.md)（生态清单）

---

## 一、背景：为什么会出现 rustc / rustup / cargo

Secret 管理方案**不局限于 GCP Secret Manager**。两条路线的差别决定了「要不要自己写代码」：

| 维度 | GCP Secret Manager | HashiCorp Vault（自建开源） |
|:---|:---|:---|
| 服务端 | GCP 全托管 | **自己部署**：HA、unseal、升级、备份、审计设备、容量 |
| 权限模型 | GCP IAM（Service Account + 预定义角色） | 自己写 Policy + 角色绑定 |
| 认证 | Workload Identity / SA token | 自己选：Kubernetes auth / AppRole / 云 IAM 联合 |
| 客户端 | `gcloud`、各语言 SDK、**现成的 K8s CSI Driver** | `vault` CLI、**官方 Vault Agent（Go）**，或**自研客户端** |
| 注入到应用 | CSI Driver 挂载 / SDK 读环境变量 / 官方 sidecar 模式 | Vault Agent template，或**自研 init container** |
| 「自研胶水逻辑」量 | 几乎为零 | **大量** ← 这就是 Rust 的用武之地 |

**关键推论：**

> 选 GCP Secret Manager → 几乎不用写 Rust。
> 选自建 Vault → 「secret 怎么进到应用里」这一段要自己写：
> **认证 → 拉取 → 渲染 → 注入 → 轮转 → 清理**。
>
> 这段逻辑用什么语言写 → **Rust**；
> 而 `rustc` / `rustup` / `cargo` 就是**构建这段逻辑的工具链**，
> 用它们做 POC、做交叉编译、出容器镜像、跑测试。

所以「Secret Manager 讨论里出现 Rust 工具链」的真实含义是：
**「我们打算自建 secret 注入逻辑，用 Rust 写，做成 init container。」**

---

## 二、目标形态：init container / sidecar / 应用内 SDK

| 形态 | 工作方式 | 优点 | 缺点 |
|:---|:---|:---|:---|
| **init container**（推荐先做） | 启动前拉 secret 写进共享 volume，跑完退出，应用容器再启动 | 应用**零改动**；顺序天然保证；secret 不进环境变量 | 是**启动时快照**，不支持运行期轮转；应用重启要重拉 |
| **sidecar** | 常驻，拉 secret + 监听变更写文件 | 支持**运行期轮转** | 多一个常驻容器，吃资源；应用需支持重读文件 |
| 应用内 SDK | 应用自己调 Vault API | 最小延迟、最灵活 | 每个应用都要改代码、都要引入 Vault 依赖；权限扩散到所有应用 |

**建议路径**：POC 先做 **init container**（价值最直接、风险最低），轮转能力放到 **sidecar 模式**作为第二阶段。

---

## 三、Vault 侧认证方式选型

| 方式 | 机制 | K8s 适配度 | 评价 |
|:---|:---|:---|:---|
| **Kubernetes auth** | 用 pod 的 SA JWT 登录 → Vault 按 role 签发 token | **天然适配**，无需预置任何 secret | ✅ **K8s 场景首选** |
| AppRole | `role_id` + `secret_id` 换 token | `secret_id` 要先塞进 K8s Secret → 鸡生蛋问题 | ⚠️ 需预置，且 `secret_id` 本身就是 secret |
| 静态 Token | 直接把 token 写进 K8s Secret | 简单 | ❌ token 生命周期/吊销难管，泄露面大 |
| 云 IAM 联合（GCP/AWS） | 用实例/工作负载身份换 token | 依赖云侧配置 | 备选，与 GCP 场景重复 |

### Kubernetes auth 的 K8s 侧要求

1. pod 需要 **projected serviceAccountToken**（`audience` 设为 Vault 的 audience）；
2. Vault 侧建 role，绑定 **SA 名 + namespace + policy**；
3. 登录接口：`POST /v1/auth/kubernetes/login`，body `{ "role": "<role>", "jwt": "<SA JWT>" }`。

> POC 里 `jwt` 来自 `/var/run/secrets/kubernetes.io/serviceaccount/token`（projected volume），
> 天然短期有效，比静态 token 安全得多。

---

## 四、Rust Vault 客户端选型（实测结果）

| crate | 版本 | 最后更新 | Kubernetes auth | 结论 |
|:---|---:|:---|:---|:---|
| **`vault-client-rs`** | 0.8.0 | 2026-08-20 | ✅ **支持** | ✅ **推荐** |
| `hashicorp_vault`（vault-rs） | 2.1.1 | **2022-11-15** | ❌ 仅 AppRole / Token | ⚠️ 已停更 4 年，不适合主线 |
| `vault_client`（Metaswitch） | 0.3.2 | 陈旧（futures 0.1 时代） | ❌ | ❌ 排除 |
| 手写 `reqwest` 调 REST | — | 自己维护 | 自己实现 | 🔧 备选：API 面窄时反而最省心 |

### `vault-client-rs` 细节（推荐理由）

- **作者 michaelklishin 是 HashiCorp 工程师**（Vault/Consul 方向），2026-08 仍在更新 —— 与 `hashicorp_vault` 的停更形成鲜明对比
- API 覆盖面：KV v1/v2、Transit、PKI、Database、SSH、Identity、TOTP、Cubbyhole，
  以及 sys 系列（seal/unseal、mounts、policies、leases、audit、Raft、rekey、namespaces、quotas）
- **认证方式全**：Token、AppRole、Userpass、LDAP、**Kubernetes**、TLS cert、GitHub、OIDC/JWT、AWS、Azure、GCP、Kerberos、RADIUS
- feature：`blocking`（同步）、`auto-renew`（token 自动续期）、`tokio-util`
- **依赖已内置 `secrecy` 0.10 + `zeroize` 1** —— secret 内存自动擦除，和我们「secret 不该留在堆里」的要求天然吻合
- **每个 API handler 实现 trait**（`Kv2Operations`、`TransitOperations`…），可替换 mock → **POC 阶段不需要真 Vault 也能写单测**
- `rust-version = 1.94` → 本机 **1.95.0 满足要求** ✅
- ⚠️ 风险：项目年轻，**1.0 前可能有 breaking change**；GitHub ★ 仅 2（关注度低，非官方背书）
- ⚠️ 依赖 `reqwest 0.13` / `rand 0.10` / `base64 0.22` 均为较新版本，老项目里容易出现版本冲突

---

## 五、依赖清单（crates.io 实测版本）

| crate | 版本 | 用途 |
|:---|---:|:---|
| `vault-client-rs` | 0.8.0 | Vault HTTP API 客户端（auth + KV + …） |
| `tokio` | 1.54.1 | 异步运行时 |
| `reqwest` | 0.13.5 | HTTP（vault-client-rs 已依赖） |
| `secrecy` | 0.10.3 | secret 包装类型，drop 时擦除 |
| `zeroize` | 1.x | 内存擦除底层 |
| `serde` / `serde_json` | 1.x | 序列化（Vault 响应、配置） |
| `minijinja` | 3.1.0 | **模板渲染**（Rust 版，替代 Vault Agent 的 Go template）；依赖少 |
| `tera` | 1.20.1 | 模板备选（Jinja2 语法） |
| `handlebars` | 6.4.4 | 模板备选（mustache 语法） |
| `notify` | 9.0.0 | 文件事件监听（轮转阶段） |
| `kube` | 5.2.0 | K8s client（可选：把 secret 回写成 K8s Secret / 自定义资源） |
| `serde_yaml_ng` | 0.10.0 | YAML（注意 `serde_yaml` 0.9.34 已 deprecated） |
| `tracing` | 0.1.44 | 结构化日志（**绝不能把 secret 打进日志**） |
| `thiserror` | 2.x | 错误类型 |

---

## 六、POC 架构（init container 版）

```text
Pod (namespace: example-namespace)
│
├─ initContainer: secret-init            # Rust 静态二进制
│   1. 读 projected SA JWT  /var/run/secrets/kubernetes.io/serviceaccount/token
│   2. POST {VAULT_ADDR}/v1/auth/kubernetes/login  {role, jwt}   → client token
│   3. GET  {VAULT_ADDR}/v1/{mount}/data/{path}   (X-Vault-Token) → secret
│   4. minijinja 渲染模板 → 写 /shared/secrets/<key>（0600）
│   5. 可选：写 /shared/.secrets-ready 作为「应用可启动」标记
│   6. 退出（token 在内存中随进程销毁而擦除）
│
└─ container: example-app
    └─ 读取 /shared/secrets/<key>（不用改代码）
```

### K8s 清单要点

```yaml
volumes:
  - name: vault-jwt
    projected:
      sources:
        - serviceAccountToken:
            path: token
            audience: vault            # 与 Vault 侧 role 的 audience 一致
  - name: shared-secrets
    emptyDir: {}                       # 或 medium: Memory（tmpfs，secret 不落盘）

initContainers:
  - name: secret-init
    image: registry.example-project/secret-init:0.1.0   # Rust 静态二进制
    env:
      - name: VAULT_ADDR
        value: https://vault.example-namespace.svc:8200
      - name: VAULT_ROLE
        value: example-app-role
      - name: SECRET_MOUNT
        value: example-app-secrets
    volumeMounts:
      - { name: vault-jwt,       mountPath: /var/run/secrets/kubernetes.io/serviceaccount, readOnly: true }
      - { name: shared-secrets,  mountPath: /shared/secrets }
    securityContext:
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities: { drop: ["ALL"] }
    resources:
      requests: { cpu: 10m, memory: 32Mi }
      limits:   { memory: 64Mi }
```

要点：

- **SA token 用 projected volume + 限定 audience**，不要用默认自动挂载的宽权限 token；
- **文件权限 0600**，应用容器通过 `fsGroup` 或固定 uid 读取；
- **`emptyDir.medium: Memory`**（tmpfs）：secret 不落盘到节点磁盘；
- `readOnlyRootFilesystem: true` + `drop ALL`：Rust 单二进制不需要写任何东西到 root fs；
- 资源 limit 可以压得很低 —— **这是 Rust 相对 Go 的实际收益点**（无 GC、冷启动快、RSS 小）。

---

## 七、为什么不直接用官方 Vault Agent？

官方 **Vault Agent**（Go）已经能做 auth + template + auto-auth + caching + renewal，
很多场景**它就是正确答案**。Rust 方案的价值不在于「替代它」，而在于：

1. **多 provider 抽象**（⭐ 核心论点）
   我们真正想要的是一个「**多云 secret init container**」：
   - Vault（自建、开源）
   - GCP Secret Manager
   - 未来的 AWS Secrets Manager / Azure Key Vault
   用一个 Rust trait 抽象出去，K8s 侧只换配置不换镜像。
   单靠 Vault Agent 做不到这一点。

2. **定制自由**：多 secret 合并、特殊编码（base64/加密）、与我们的 K8s 资源/配置模型配合。

3. **供应链可控**：一个自建静态二进制，SBOM、漏洞扫描、可复现构建都能自己管。

4. **镜像更小 / 资源更省**：init container 每 pod 跑一次，Go agent 镜像动辄几十 MB。

> 决策建议：**POC 阶段两条路都试**
> - 路线 1：Vault Agent（Go）做基线 —— 半小时能跑通，先验证「Vault + K8s」这条路本身通不通；
> - 路线 2：Rust init container —— 验证「多 provider 抽象」是否真的值得自研。
> 只有当路线 2 的多云收益被确认后，才值得投入工程量。

---

## 八、POC 里程碑

| 里程碑 | 内容 | 产出 |
|:---|:---|:---|
| **M0** 本地打通 | 本地起 `vault server -dev`，Rust CLI 走通 login → read → 打印（脱敏） | 一个能跑的 cargo 项目 |
| **M1** K8s 打通 | init container 拉 secret 写 emptyDir，example-app 能读到 | 一份完整 K8s manifest |
| **M2** 轮转 | 改 sidecar 模式 + `notify`/定时刷新；应用支持重读文件 | 轮转 POC |
| **M3** 多 provider | 抽象 `SecretProvider` trait，统一 GCP Secret Manager + Vault | 统一客户端 |
| **M4** 加固 | 失败重试与退避、audit log、Prometheus 指标、`cargo audit` 进 CI、交叉编译进 CI | 可上线候选 |

> M0 就能回答最关键的问题：**Rust 侧的 Vault 客户端够不够用**（尤其是 Kubernetes auth 与 token 续期）。

---

## 九、风险清单

| 风险 | 说明 | 缓解 |
|:---|:---|:---|
| `vault-client-rs` 成熟度 | 1.0 前 breaking change；★ 2，无官方背书 | 锁版本 `=0.8.0`；抽象自己的 trait 包一层，换库只改实现 |
| 社区 crate 停更（`hashicorp_vault`） | 2022 年至今没更新，且**不支持 K8s auth** | 已排除；不要在 POC 里踩坑 |
| 自己造 Vault 客户端的诱惑 | 「反正 API 很简单，直接 reqwest 写」 | POC 可行，但要把 auth 轮转、lease、错误码都覆盖；优先用现成库 |
| Secret 进日志 | `tracing`/`Debug` 打印 token | 用 `secrecy` 的 `SecretString`；CI 加 grep 规则查 `tracing::info!` 里是否带 secret |
| SA token 泄露面 | projected token 若被写进日志/镜像 | 限定 audience + 短 TTL；不落盘 |
| 供应链 | crates.io 单一 registry | `Cargo.lock` 入库 + `cargo audit`(RustSec) + `cargo deny` 许可证策略 |
| 跨编译产物不可复现 | macOS 编的 Linux 二进制 ≠ CI 编的 | 统一在 CI 用官方 `rust:1.95` 镜像构建 |
| 自建 Vault 本身的运维成本 | unseal、HA、升级、审计 | 与「用 GCP Secret Manager」的成本对比要写进选型报告 |

---

## 十、下一步（均不涉及安装）

1. **先跑路线 1（Vault Agent）**：验证 Vault + K8s 这条路本身，别一上来就自研；
2. 确定 POC 范围 = **M0**（本地 `vault server -dev` + Rust CLI）；
3. 确定是否要出 Linux 二进制 → 决定是否 `rustup target add x86_64-unknown-linux-gnu`；
4. 决定客户端策略：先用 `vault-client-rs`，若 API 不够再降级为手写 `reqwest`；
5. 把「自建 Vault vs 继续用 GCP Secret Manager」的**总成本对比**（含运维人力）写进选型结论 —— 这是整个讨论的落点。

---

## 参考

- 工具链定位与本机现状：[rust-toolchain-and-secret-manager.md](rust-toolchain-and-secret-manager.md)
- Rust secret 生态清单：[rust-secret-ecosystem.md](rust-secret-ecosystem.md)
- Rust 工具链速查：[develop/rust/README.md](../../develop/rust/README.md)
- GCP Secret Manager 侧已有笔记：[gcp/secret-manage/](../../gcp/secret-manage/)
