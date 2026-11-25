# Secret Manager 方案探索

> 本目录收录 **Secret Management（密钥/凭据管理）** 方向的方案调研笔记。
> 关注点：方案选型、工具链、SDK、注入方式、轮换与权限模型。

## 场景背景（2026-11-25 澄清）

- Secret 管理方案**不局限于 GCP Secret Manager**；
  GCP 有现成托管服务（IAM + CSI Driver + 各语言 SDK），几乎不用自己写代码。
- 备选路线是**开源 HashiCorp Vault**（自建）。一旦走这条路，
  「**secret 怎么进到应用里**」这一段要自己写：认证 → 拉取 → 渲染 → 注入 → 轮转 → 清理。
- 这段自研逻辑**用 Rust 写**，形态是 **init container / sidecar**；
  `rustc` / `rustup` / `cargo` 就是构建它的工具链（做 POC、交叉编译、出镜像、跑测试）。
- Rust 在 secret 世界里的角色因此明确为：**客户端 / Agent / 加密库 / CLI**。

> 展开见 [vault-rust-init-container-poc.md](vault-rust-init-container-poc.md)。

## 目录

| 文档 | 内容 | 状态 |
|:---|:---|:---|
| [vault-rust-init-container-poc.md](vault-rust-init-container-poc.md) | **主线**：Vault + Rust init container 的 POC 设计（背景、认证方式、Rust 客户端选型、K8s 清单、里程碑、风险） | 设计稿，未实现 |
| [rust-toolchain-and-secret-manager.md](rust-toolchain-and-secret-manager.md) | **rustc / rustup / cargo 到底解决什么问题**，为什么它们会出现在 Secret Manager 讨论里，是否等于「用 Rust 做 Secret 开发（接 Vault）」 | 探索完成，未安装任何新工具 |
| [rust-secret-ecosystem.md](rust-secret-ecosystem.md) | Rust 生态里的 Secret 相关 crates 与项目清单（版本/星标已于 2026-11-25 实测） | 已实测 |

## 相关已有笔记

- GCP 侧的具体操作与权限问题：[gcp/secret-manage/](../../gcp/secret-manage/)
  （含 `secret-todo.md`：secretVersionAdder 权限评估、轮换方案）
- Rust 工具链本身：[develop/rust/](../../develop/rust/)
- 通用安全类笔记：[safe/](../../safe/)

## 阅读顺序建议

1. 先读 [vault-rust-init-container-poc.md](vault-rust-init-container-poc.md) 的「背景」与「客户端选型」两节；
2. 再读 `rust-toolchain-and-secret-manager.md` 的「一句话结论」和「决策表」；
3. 需要给同事看具体可选项时，看 `rust-secret-ecosystem.md`。
