# K8s 镜像替换脚本使用说明

## 功能特性

- 🔍 自动搜索匹配的 deployments 和容器
- 🎯 支持指定命名空间或搜索所有命名空间
- 📋 交互式选择要更新的 deployments
- ✅ 支持批量选择（序号范围、逗号分隔、全选）
- 🔄 自动等待 rollout 完成
- 🎨 彩色输出，清晰易读
- 🛡️ 安全确认机制

## 使用方法

### 基本用法

```bash
# 搜索所有命名空间中匹配的 deployments
./k8s-image-replace.sh -i myapp:v1.2.3

# 指定命名空间搜索
./k8s-image-replace.sh -i registry.io/myorg/myapp:v2.0.0 -n production
```

### 参数说明

- `-i, --image`: 目标镜像（必需）
- `-n, --namespace`: 指定命名空间（可选，默认搜索所有命名空间）
- `-h, --help`: 显示帮助信息

## 使用流程

1. **执行脚本**：提供目标镜像名称
2. **查看匹配结果**：脚本会列出所有匹配的 deployments
3. **选择要更新的项目**：
   - 输入序号：`1,3,5` 或 `1-3`
   - 输入 `all` 选择全部
   - 输入 `q` 退出
4. **确认执行**：检查更新列表后确认
5. **等待完成**：脚本会自动等待 rollout 完成

## 示例输出

```
[INFO] 目标镜像: myapp:v1.2.3
[INFO] 镜像名称: myapp
[INFO] 镜像标签: v1.2.3
[INFO] 搜索所有命名空间

[SUCCESS] 找到 2 个匹配的 deployment(s):

序号 命名空间             Deployment                     容器                 当前镜像
---- --------             ----------                     ----                 --------
1    default              myapp-frontend                 myapp                myapp:v1.2.2
2    production           myapp-api                      api-container        myapp:v1.2.1

请选择要更新的 deployment:
  输入序号 (例如: 1,3,5 或 1-3)
  输入 'all' 选择全部
  输入 'q' 退出

请选择: all

[INFO] 将要执行以下更新操作:
  default/myapp-frontend (myapp): myapp:v1.2.2 -> myapp:v1.2.3
  production/myapp-api (api-container): myapp:v1.2.1 -> myapp:v1.2.3

确认执行? (y/N): y

[INFO] 开始执行镜像更新...
[INFO] 更新 default/myapp-frontend 中的容器 myapp...
[SUCCESS] ✓ default/myapp-frontend 更新成功
[INFO] 等待 default/myapp-frontend rollout 完成...
[SUCCESS] ✓ default/myapp-frontend rollout 完成

[SUCCESS] 镜像更新操作完成!
```

## 注意事项

1. **权限要求**：需要对目标命名空间的 deployments 有更新权限
2. **镜像匹配**：支持部分匹配，会匹配包含指定镜像名称的所有容器
3. **回滚**：如果更新失败，脚本会提示回滚命令
4. **超时设置**：rollout 等待时间为 5 分钟，可根据需要调整

## 安全特性

- ✅ 执行前显示详细的更新计划
- ✅ 需要用户确认才会执行
- ✅ 自动检查 kubectl 连接
- ✅ 提供回滚建议
- ✅ 彩色输出区分不同状态

## 故障排除

### 常见问题

1. **kubectl 未找到**
   ```bash
   # 确保 kubectl 已安装并在 PATH 中
   which kubectl
   ```

2. **无法连接集群**
   ```bash
   # 检查 kubeconfig
   kubectl cluster-info
   ```

3. **权限不足**
   ```bash
   # 检查权限
   kubectl auth can-i update deployments -n <namespace>
   ```

4. **rollout 失败**
   ```bash
   # 手动回滚
   kubectl rollout undo deployment/<deployment-name> -n <namespace>
   ```