# create-claude.sh 使用文档

本文档详细介绍了 `create-claude.sh` 脚本的功能、用法以及其内部的核心逻辑，特别是针对 DNS 记录导入导出的特殊处理。

## 1. 脚本概述

`create-claude.sh` 是一个用于迁移 GCP Cloud DNS Private Zone 的工具。它旨在将现有的 `private-access` Zone 中的记录迁移到一个新的、环境特定的 Private Zone 中（例如 `dev-cn-private-access`），同时保持原有的网络绑定配置。

### 主要特性
- **多网络绑定支持**：正确处理并恢复 Zone 绑定的多个 VPC 网络。
- **高性能批量导入**：使用 BIND 文件格式和 `import` 命令，比逐条创建快数倍。
- **智能冲突处理**：自动过滤系统生成的 NS/SOA 记录，防止导入冲突。
- **安全机制**：在创建新 Zone 失败时自动尝试恢复源 Zone 的网络绑定。

## 2. 核心逻辑详解

脚本在“导出”和“导入”之间并不是简单的文件复制，而是包含了关键的数据处理逻辑，以确保迁移的成功和数据的准确性。

### 2.1 导出 (Export)
脚本首先从源 Zone 导出所有 DNS 记录。
- **格式**: **BIND Zone File** (RFC 1035)
- **命令**: `gcloud dns record-sets export --zone-file-format`
- **原因**: BIND 格式是 DNS 的标准格式，`gcloud` 原生支持，且比 JSON/YAML 更易于进行文本处理。

### 2.2 过滤与预处理 (Filtering)
这是脚本最关键的一步。直接导入导出的文件会失败，因为新创建的 Zone 会自动由 GCP 分配默认的 `SOA` (Start of Authority) 和 `NS` (Name Server) 记录。

脚本在导入前会使用 `awk` 对 BIND 文件进行处理，生成一个**过滤后的临时文件**：
1.  **移除 SOA 记录**: 丢弃所有 `SOA` 类型的记录，保留新 Zone 自动生成的 SOA。
2.  **移除 Root NS 记录**: 丢弃 Zone 根域名（例如 `example.com.`）的 `NS` 记录。
    *   *注意*: 子域名的 NS 记录（即委派，如 `sub.example.com.` 的 NS）会被**保留**，因为这些是用户自定义的配置。
3.  **保留其他记录**: 所有的 A, CNAME, TXT, MX 等用户数据均原样保留。

### 2.3 批量导入 (Bulk Import)
使用过滤后的文件进行导入。
- **命令**: `gcloud dns record-sets import --zone-file-format --delete-all-existing`
- **--delete-all-existing**: 这个参数看起来很危险，但实际上它是为了确保“原本为空”的新 Zone 能够接受导入。
    - 它**不会**删除 GCP 托管的系统记录（默认的 NS/SOA）。
    - 它**会**清除任何用户创建的记录（虽然新 Zone 本来就是空的，但这保证了操作的幂等性）。
- **优势**: 相比循环调用 `gcloud ... create`，这种方式在一次 API 调用中完成所有记录的提交，极大地减少了耗时和限流风险。

### 2.4 多网络绑定 (Network Binding)
脚本能够识别源 Zone 绑定的多个 VPC 网络（例如同时绑定了 `dev` 和 `prod` 网络）。
- **逻辑**: 获取所有网络 URL -> 构建逗号分隔的列表 -> 使用 `--networks=url1,url2` 参数创建 Zone。
- **修复**: 解决了之前版本使用多个 `--networks` 参数导致只有最后一个生效的问题。

## 3. 使用方法

### 命令行参数

```bash
./create-claude.sh -e ENVIRONMENT [选项]
```

| 参数 | 说明 | 必需 | 示例 |
| :--- | :--- | :--- | :--- |
| `-e` | 环境标识符 (定义在脚本的 `env_info` 数组中) | 是 | `-e dev-cn` |
| `-s` | 源 Zone 名称 (默认为 `private-access`) | 否 | `-s my-custom-zone` |

### 示例

**1. 迁移到 dev-cn 环境**
```bash
./create-claude.sh -e dev-cn
```

**2. 从自定义 Zone 迁移**
```bash
./create-claude.sh -e lex-in -s old-private-zone
```

## 4. 验证与排错

脚本在执行完成后会自动进行以下验证：
1.  **记录数量对比**: 比较源文件和目标 Zone 的记录总数。
2.  **内容差异对比**: 如果数量一致，进一步对比记录内容的差异（忽略 NS/SOA）。
3.  **日志**:
    - 导出文件: `/tmp/{zone}-records-{timestamp}.txt` (BIND 格式)
    - 导入过滤文件: `/tmp/{zone}-import-{timestamp}.txt` (过滤后的 BIND 文件)
    - 失败日志: `/tmp/{zone}-failed-{timestamp}.log` (如果有)

如果遇到问题，可以检查 `/tmp/` 目录下的这些中间文件来排查过滤逻辑是否符合预期。
