# Golang 平台配置适配 - 文档索引

## 📚 文档概览

本目录包含 Golang 应用适配平台 ConfigMap 配置的完整解决方案。

## 🎯 快速导航

### 新手入门
1. **[README.md](README.md)** - 项目概述和快速开始
2. **[INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md)** - 集成指南（推荐首先阅读）

### 详细文档
3. **[platform-configmap-adapter.md](platform-configmap-adapter.md)** - 完整的技术方案文档
4. **[JAVA-GOLANG-COMPARISON.md](JAVA-GOLANG-COMPARISON.md)** - Java 与 Golang 对比

### 原有文档
5. **[golang-deploy.md](golang-deploy.md)** - 原始部署文档

## 📁 文件清单

### 核心代码
| 文件 | 说明 | 用途 |
|------|------|------|
| `platform-config-loader.go` | 配置加载器 | 读取平台配置的核心组件 |
| `platform-config-loader_test.go` | 单元测试 | 配置加载器的测试用例 |
| `main.go` | 应用示例 | 完整的应用示例代码 |
| `go.mod` | Go 模块 | 依赖管理 |

### 部署配置
| 文件 | 说明 | 使用场景 |
|------|------|----------|
| `deployment.yaml` | 标准部署配置 | 平台提供 PEM 证书 |
| `deployment-with-initcontainer.yaml` | InitContainer 部署 | 平台只提供 PKCS12 证书 |
| `Dockerfile` | 容器构建 | 构建 Docker 镜像 |

### 工具脚本
| 文件 | 说明 | 用途 |
|------|------|------|
| `convert-cert.sh` | 证书转换脚本 | PKCS12 转 PEM |
| `test-local.sh` | 本地测试脚本 | 本地环境测试 |

### 文档
| 文件 | 说明 | 目标读者 |
|------|------|----------|
| `README.md` | 项目说明 | 所有人 |
| `INTEGRATION-GUIDE.md` | 集成指南 | 应用开发者 |
| `platform-configmap-adapter.md` | 技术方案 | 架构师、平台工程师 |
| `JAVA-GOLANG-COMPARISON.md` | 对比文档 | 决策者、架构师 |
| `INDEX.md` | 本文档 | 所有人 |

## 🚀 使用流程

### 场景 1：新应用开发

```
1. 阅读 INTEGRATION-GUIDE.md
   ↓
2. 复制 platform-config-loader.go 到项目
   ↓
3. 参考 main.go 编写应用代码
   ↓
4. 使用 test-local.sh 本地测试
   ↓
5. 使用 Dockerfile 构建镜像
   ↓
6. 使用 deployment.yaml 部署
```

### 场景 2：现有应用迁移

```
1. 阅读 JAVA-GOLANG-COMPARISON.md 了解差异
   ↓
2. 阅读 INTEGRATION-GUIDE.md 了解步骤
   ↓
3. 集成 platform-config-loader.go
   ↓
4. 修改路由挂载 Context Path
   ↓
5. 处理证书格式（选择方案）
   ↓
6. 测试和部署
```

### 场景 3：平台工程师

```
1. 阅读 platform-configmap-adapter.md 了解完整方案
   ↓
2. 阅读 JAVA-GOLANG-COMPARISON.md 了解对比
   ↓
3. 决定证书提供方式（PEM 或 InitContainer）
   ↓
4. 准备 ConfigMap 和 Secret
   ↓
5. 提供给应用开发团队
```

## 🎓 学习路径

### 初级（应用开发者）
1. ✅ 阅读 README.md
2. ✅ 阅读 INTEGRATION-GUIDE.md
3. ✅ 运行 test-local.sh
4. ✅ 查看 main.go 示例

### 中级（应用架构师）
1. ✅ 完成初级内容
2. ✅ 阅读 platform-configmap-adapter.md
3. ✅ 理解 platform-config-loader.go 实现
4. ✅ 运行单元测试

### 高级（平台工程师）
1. ✅ 完成中级内容
2. ✅ 阅读 JAVA-GOLANG-COMPARISON.md
3. ✅ 评估证书方案
4. ✅ 规划平台改进

## 🔍 常见问题快速查找

| 问题 | 查看文档 | 章节 |
|------|----------|------|
| 如何快速开始？ | INTEGRATION-GUIDE.md | 集成步骤 |
| 配置文件格式？ | platform-configmap-adapter.md | 第 2 节 |
| 证书如何处理？ | platform-configmap-adapter.md | 第 4 节 |
| 与 Java 有何不同？ | JAVA-GOLANG-COMPARISON.md | 全文 |
| 部署配置示例？ | deployment.yaml | - |
| 本地如何测试？ | test-local.sh | - |
| 配置加载原理？ | platform-config-loader.go | 代码注释 |
| 健康检查失败？ | INTEGRATION-GUIDE.md | 故障排查 |

## 📊 方案对比

### 证书处理方案

| 方案 | 优点 | 缺点 | 推荐度 |
|------|------|------|--------|
| **方案 A：平台提供 PEM** | 简单、快速 | 需要平台改造 | ⭐⭐⭐⭐⭐ |
| **方案 B：InitContainer** | 无需平台改造 | 启动稍慢 | ⭐⭐⭐⭐ |
| **方案 C：应用内转换** | 灵活 | 复杂、不推荐 | ⭐⭐ |

### 部署配置选择

| 场景 | 使用文件 | 说明 |
|------|----------|------|
| 平台已提供 PEM 证书 | deployment.yaml | 最简单 |
| 平台只有 PKCS12 证书 | deployment-with-initcontainer.yaml | 自动转换 |
| 本地开发测试 | test-local.sh | 快速验证 |

## 🛠️ 工具使用

### 本地测试
```bash
chmod +x test-local.sh
./test-local.sh
```

### 证书转换
```bash
chmod +x convert-cert.sh
./convert-cert.sh /path/to/cert.p12 password
```

### 单元测试
```bash
go test -v ./...
```

### 构建镜像
```bash
docker build -t your-app:latest .
```

## 📈 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2025-11-30 | 初始版本 |

## 🤝 贡献指南

如需改进文档或代码：
1. 提交 Issue 描述问题
2. 提交 PR 附带说明
3. 联系平台工程团队

## 📞 获取帮助

- **技术问题**：联系平台工程团队
- **文档问题**：提交 Issue
- **紧急支持**：查看团队 Wiki

## 🔗 相关资源

- Gin 框架文档：https://gin-gonic.com/
- Kubernetes 文档：https://kubernetes.io/
- Go 官方文档：https://go.dev/doc/

---

**维护团队**：平台工程团队  
**最后更新**：2025-11-30  
**文档版本**：v1.0
