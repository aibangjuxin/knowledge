# Rust 开发环境

**Status:** 工具链已就绪（rustup 官方安装器，非 Homebrew），当前仅 stable-aarch64-apple-darwin。

## 三个核心工具

| 工具 | 角色 | 说明 |
|:---|:---|:---|
| `rustc` | 编译器 | `.rs` → 机器码；类型检查 + 借用检查 + LLVM 优化 |
| `rustup` | 工具链管理器 | 装/切版本、管理 target（交叉编译）、管理组件（clippy/rustfmt/rust-analyzer） |
| `cargo` | 包管理 + 构建 + 测试 | 依赖解析、crates.io 下载、`cargo test`、`Cargo.lock`、`cargo install`、`cargo publish` |

三者是「mvn + java + sdkman」的同构关系。

## 本机现状（2026-11-25 实测）

```text
rustc    1.95.0 (59807616e 2026-04-14)
rustup   1.29.0 (28d1352db 2026-03-05)
cargo    1.95.0 (f2d3ce0bd 2026-03-21)

安装前缀: ~/.cargo/bin, ~/.rustup/toolchains
toolchain: stable-aarch64-apple-darwin (active, default)
target:    aarch64-apple-darwin
component: rustc / rust-std / cargo  (clippy、rustfmt、rust-analyzer 未装)
```

## 常用命令

```bash
# 版本与现状
rustup toolchain list
rustup target list --installed
rustup component list --installed
rustup show

# 项目
cargo new <name>
cargo build --release
cargo test
cargo fmt && cargo clippy -- -D warnings

# 依赖
cargo add <crate>
cargo info <crate>          # 查版本/许可证/仓库
cargo search <kw> --limit N
cargo tree -i <crate>      # 反查依赖
cargo update -p <crate>

# 安装 CLI 工具
cargo install --locked <tool>

# 供应链安全
cargo audit                 # 需 cargo install cargo-audit
cargo deny check            # 需 cargo install cargo-deny（许可证/来源策略）

# 交叉编译（装 target 即可，静态链接另配 musl/cross/zig）
rustup target add x86_64-unknown-linux-gnu
cargo build --release --target x86_64-unknown-linux-gnu
```

## 目录约定

```
develop/rust/
├── README.md       # 本文件
├── Cargo.toml      # workspace 根（若多 crate）
└── src/
```

## 用途：Secret Manager 方案（Vault init container）

本仓库的 Rust 工具链是为了 **Secret Management 方案**准备的：
GCP Secret Manager 有现成托管服务，而**开源 HashiCorp Vault（自建）**需要自研
「secret 怎么进到应用」这段逻辑 —— 形态是 **init container / sidecar**，用 Rust 写。

流程：Rust 写客户端 → `cargo build` → 交叉编译出 Linux 静态二进制 → 打镜像 → K8s init container。

详见：
- [safe/secret-manage/vault-rust-init-container-poc.md](../../safe/secret-manage/vault-rust-init-container-poc.md)（主线 POC 设计）
- [safe/secret-manage/rust-toolchain-and-secret-manager.md](../../safe/secret-manage/rust-toolchain-and-secret-manager.md)（工具链定位）
- [safe/secret-manage/rust-secret-ecosystem.md](../../safe/secret-manage/rust-secret-ecosystem.md)（crate 清单）
