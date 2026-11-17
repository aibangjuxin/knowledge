# Bug 修复说明：`((COUNTER++))` 在 `set -e` 模式下的问题

## 问题描述

脚本在"检查前置条件"后立即退出，即使所有命令都成功执行。

## 根本原因

### Bash 算术运算的退出码行为

在 Bash 中，`((expression))` 的退出码取决于表达式的结果：
- 如果表达式结果为 **非零**，退出码为 **0** (成功)
- 如果表达式结果为 **零**，退出码为 **1** (失败)

### 问题演示

```bash
#!/bin/bash
set -e  # 任何命令返回非零退出码就退出

COUNTER=0
((COUNTER++))  # 后置递增返回递增前的值 (0)
               # 0 在算术上下文中为假
               # 退出码为 1
               # set -e 导致脚本退出！

echo "这行永远不会执行"
```

### 实际测试

```bash
$ COUNTER=0
$ ((COUNTER++))
$ echo $?
1                    # 退出码为 1！

$ echo $COUNTER
1                    # 但值确实递增了
```

## 为什么会这样？

`((COUNTER++))` 使用**后置递增**：
1. 先返回当前值 (0)
2. 然后递增变量 (变成 1)
3. 返回值 0 在算术上下文中为假
4. 退出码为 1

在 `set -euo pipefail` 模式下：
- `-e`: 遇到退出码非零的命令就退出
- `((COUNTER++))` 返回退出码 1
- 脚本立即退出

## 解决方案

### 方案 1: 使用算术展开（推荐）

```bash
# ✅ 安全：总是返回退出码 0
COUNTER=$((COUNTER + 1))
```

### 方案 2: 使用前置递增

```bash
# ✅ 安全：前置递增返回递增后的值 (非零)
((++COUNTER))
```

### 方案 3: 添加 || true

```bash
# ✅ 安全：但不优雅
((COUNTER++)) || true
```

### 方案 4: 使用 : 命令

```bash
# ✅ 安全：: 命令总是成功
: $((COUNTER++))
```

### 方案 5: 使用 let

```bash
# ✅ 安全：但需要 || true
let COUNTER++ || true
```

## 我们的修复

将所有的：
```bash
((TOTAL_CHECKS++))
((PASSED_CHECKS++))
((WARNING_CHECKS++))
((FAILED_CHECKS++))
```

改为：
```bash
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
PASSED_CHECKS=$((PASSED_CHECKS + 1))
WARNING_CHECKS=$((WARNING_CHECKS + 1))
FAILED_CHECKS=$((FAILED_CHECKS + 1))
```

## 为什么选择这个方案？

1. **清晰明确** - 意图一目了然
2. **总是成功** - 不会因为退出码导致脚本退出
3. **可移植性好** - 在所有 Bash 版本中都能正常工作
4. **不需要特殊处理** - 不需要 `|| true` 这样的 workaround

## 其他受影响的场景

这个问题不仅影响计数器，还会影响其他算术运算：

```bash
set -e

# ❌ 危险
if ((value)); then
    echo "非零"
fi
# 如果 value 为 0，脚本会退出！

# ✅ 安全
if [[ $value -ne 0 ]]; then
    echo "非零"
fi
```

## 最佳实践

在使用 `set -e` 的脚本中：

1. **避免使用 `((expression))` 作为独立语句**
2. **使用 `variable=$((expression))` 进行算术运算**
3. **在条件判断中使用 `[[ ]]` 而不是 `(( ))`**
4. **如果必须使用 `(( ))`，添加 `|| true`**

## 参考

- Bash Manual: Arithmetic Evaluation
- ShellCheck: SC2219 (Instead of 'let expr', prefer (( expr )))
- Google Shell Style Guide: Arithmetic

## 测试

运行测试脚本验证行为：

```bash
./test-arithmetic.sh
```

这会演示不同递增方式在 `set -e` 模式下的行为。
