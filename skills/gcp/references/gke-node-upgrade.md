# GKE Node Upgrade — 技术细节

## 升级命令结构

```
gcloud container clusters upgrade CLUSTER \
  --region=REGION \
  --project=PROJECT \
  --cluster-version=TARGET_VERSION \
  --node-pool=POOLNAME \
  --async \
  --quiet
```

**`--node-pool` 是位置参数（positional argument）**，不是 `--node-pool=NAME` 那种传统 flag。

| 写法 | 正确性 |
|------|--------|
| `--node-pool=default-pool` | ✅ 可以（bash 把 `=` 后的值当作参数值） |
| `--node-pool default-pool` | ✅ 可以（空格分隔位置参数） |

### 获取 Operation ID

```bash
op_id=$(gcloud container clusters upgrade CLUSTER \
  --region=REGION \
  --project=PROJECT \
  --cluster-version=TARGET_VERSION \
  --node-pool=POOLNAME \
  --async \
  --quiet \
  --format='value(operation.name)')
#                                         ↑ 必须用单引号，不能用双引号
```

## `set -u` + 字符串比较陷阱（macOS bash 3.2）

macOS 内置 bash 3.2，在 `set -u`（`set -uo pipefail`）环境下，`[[ "$var" == "$TARGET" ]]` 当 `var == TARGET` 时会触发 **"unbound variable"** 错误。

### 问题代码（错误）

```bash
set -uo pipefail
current_node_version=$(get_version)
TARGET_VERSION="1.35.3-gke.1389002"

if [[ "$current_node_version" == "$TARGET_VERSION" ]]; then
  echo "already at target"
  exit 0
fi
# 当 current_node_version == TARGET_VERSION 时，
# bash 在计算 `==` 右侧表达式时引用 $TARGET_VERSION，
# 触发了 set -u 的"未定义变量"检查
```

### 正确解法：Early Exit Pattern

```bash
set -uo pipefail
current_node_version=$(get_version)
TARGET_VERSION="1.35.3-gke.1389002"

# 先比较，再赋值给后续变量 — early exit 在变量被引用之前
[[ "$current_node_version" == "$TARGET_VERSION" ]] && exit 0

# 后续可以安全使用 $TARGET_VERSION
echo "Upgrading to $TARGET_VERSION ..."
```

核心原则：**不要在字符串比较的右侧引用一个已经被 `set -u` 标记为"需检查"的变量**。用 `&& exit 0` 提前退出，避免变量在比较之后还被后续代码引用。

### 函数封装版本

```bash
version_needs_upgrade() {
  local current="$1" target="$2"
  [[ "$current" == "$target" ]] && return 3  # 已在目标版本
  return 0
}

if ! version_needs_upgrade "$current_node_version" "$TARGET_VERSION"; then
  echo "Upgrading..."
fi
```

## `gcloud --format=value(...)` 语法错误

在 bash 脚本中（尤其是 here-doc 或 `set -uo pipefail` 环境），`--format=value(status)` 的圆括号 `(` 会干扰 bash 的 here-document 解析或管道链，导致 "unexpected token" 语法错误。

### 错误写法

```bash
# 会触发语法错误
op_id=$(gcloud container clusters upgrade ... \
  --format=value(operation.name)')
```

### 正确写法

```bash
# 必须用单引号包裹整个 format 字符串
op_id=$(gcloud container clusters upgrade ... \
  --format='value(operation.name)')
```

同理：`--format='value(name)'` / `--format='value(status)'` / `--format='json)'` 都要用单引号。

## Surge Upgrade 配置

```bash
gcloud container clusters upgrade CLUSTER \
  --region=REGION \
  --project=PROJECT \
  --cluster-version=TARGET_VERSION \
  --node-pool=POOLNAME \
  --surge=1 \
  --max-unavailable=0 \
  --async --quiet
```

- `surge=1`：同时只有 1 个新节点被创建
- `max-unavailable=0`：零容忍不可用，Pod 受 PDB 保护时不会强制驱逐
- 实际效果：每次替换 1 个节点，零中断（对有 PDB 保护的 Service）

## 版本约束

| 约束 | 说明 |
|------|------|
| Node version ≤ Master version | 硬性约束，Node 不能超过 Master |
| 升级顺序 | Master → Node（必须先升级 Master） |
| 跳过逻辑 | current == target → exit 0（不弹确认） |

## 快速参考

```bash
# 1. 检查当前版本
gcloud container clusters describe CLUSTER --region=REGION --project=PROJECT \
  --format='value(currentMasterVersion,currentNodeVersion)'

# 2. 预检（版本是否一致、Master 是否已升级）
current_master=$(gcloud ... --format='value(currentMasterVersion)')
current_node=$(gcloud ... --format='value(currentNodeVersion)')
[[ "$current_node" == "$current_master" ]] && echo "already synced"

# 3. 升级 Node Pool
gcloud container clusters upgrade CLUSTER \
  --region=REGION \
  --project=PROJECT \
  --cluster-version=TARGET_VERSION \
  --node-pool=POOLNAME \
  --surge=1 --max-unavailable=0 \
  --async --quiet

# 4. 等待 Operation 完成（后台轮询）
# gcloud operations wait 不支持 --timeout，改用后台进程轮询
```