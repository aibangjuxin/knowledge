# Kubernetes Pod Debug Scripts

这个目录包含了用于调试Kubernetes Pod的脚本工具。

## 文件说明

- `side.md` - 原始脚本和文档
- `side-optimized.sh` - 优化版本的调试脚本
- `optimization-comparison.md` - 详细的优化对比分析
- `test-script.sh` - 测试脚本
- `README.md` - 本文档

## 快速开始

### 基本使用
```bash
# 使用优化版本脚本
./side-optimized.sh my-app europe-west2-docker.pkg.dev/project/repo/debug:latest -n production
```

### 高级选项
```bash
# 详细输出模式
./side-optimized.sh my-app debug:latest -n production --verbose

# 自动确认模式 (适合自动化)
./side-optimized.sh my-app debug:latest -n production --yes

# 查看帮助
./side-optimized.sh --help
```

## 主要改进

### 🐛 Bug修复
- **关键修复**: 原脚本只显示kubectl debug命令但不执行，现已修复
- 改进了错误处理和边界情况处理

### 🚀 性能优化
- 更智能的Pod查找：直接使用deployment的selector
- 减少不必要的kubectl调用
- 并行验证多项检查

### 🛡️ 安全性增强
- 启用bash严格模式 (`set -euo pipefail`)
- 依赖检查确保kubectl可用
- Kubernetes连接验证
- Pod状态检查和警告

### 🎯 用户体验改进
- 结构化日志输出 (INFO/WARN/ERROR/DEBUG)
- 支持详细模式 (`--verbose`)
- 支持自动确认模式 (`--yes`)
- 更清晰的帮助信息
- 显示Pod状态信息

### 🔧 代码质量
- 模块化函数设计
- 更好的参数解析
- 完善的错误处理
- 代码注释和文档

## 兼容性

优化版本完全向后兼容原脚本的使用方式：
```bash
# 原脚本格式仍然有效
./side-optimized.sh deployment-name image:tag -n namespace
```

## 常用调试镜像

脚本支持多种调试镜像：
- `curlimages/curl:latest` - HTTP调试
- `nicolaka/netshoot:latest` - 网络调试工具集
- `busybox:latest` - 轻量级工具
- `alpine:latest` - 轻量级Linux环境

## 使用场景

1. **应用调试**: 检查应用健康状态、配置等
2. **网络调试**: 测试服务连接、DNS解析等  
3. **性能分析**: 查看进程、内存使用等
4. **故障排查**: 检查日志、文件系统等

## 注意事项

- 需要有效的Kubernetes集群连接
- 需要对目标namespace有适当的权限
- 调试镜像需要能够从集群访问
- ephemeral容器功能需要Kubernetes 1.23+

## 故障排查

如果遇到问题，可以：
1. 使用 `--verbose` 选项查看详细日志
2. 检查kubectl连接: `kubectl cluster-info`
3. 验证权限: `kubectl auth can-i create pods --namespace=<namespace>`
4. 确认deployment存在: `kubectl get deployments -n <namespace>`