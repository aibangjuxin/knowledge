# Go (Golang) 知识库

## 目录描述
本目录包含Go编程语言相关的知识、实践经验、项目结构和部署方案。

## 目录结构
```
go/
├── src/                     # Go源代码文件
├── config/                  # 配置文件
├── docs/                    # Markdown文档
├── scripts/                 # Shell脚本
├── Dockerfile               # Docker镜像构建文件
├── go.mod, go.sum          # Go模块管理文件
└── README.md                # 本说明文件
```

## 子目录说明 (按功能分类)
### src/ - 源代码
- `main.go`: Go程序主入口文件
- `platform-config-loader.go`: 平台配置加载器
- `golang-config-loader-simple.go`: Go配置加载器简单实现
- `platform-config-loader_test.go`: 配置加载器测试文件

### config/ - 配置文件
- `deployment.yaml`: Kubernetes部署配置
- 其他YAML配置文件

### docs/ - 文档
- `QUICK-START.md`: 快速开始指南
- `PROJECT-STRUCTURE.md`: 项目结构说明
- `INTEGRATION-GUIDE.md`: 集成指南
- `JAVA-GOLANG-COMPARISON.md`: Java与Go语言对比
- `golang-deploy.md`: Go应用部署指南

### scripts/ - 脚本
- `test-local.sh`: 本地测试脚本
- 其他Shell脚本

## 快速检索
- 快速开始: 查看 `docs/` 目录中的 `QUICK-START.md`
- 项目结构: 查看 `docs/` 目录中的 `PROJECT-STRUCTURE.md`
- 部署指南: 查看 `docs/` 目录中的 `golang-deploy.md` 和 `config/` 目录中的部署文件
- 代码实现: 查看 `src/` 目录
- 解决方案对比: 查看 `docs/` 目录中的 `SOLUTION-COMPARISON.md` 和 `JAVA-GOLANG-COMPARISON.md`