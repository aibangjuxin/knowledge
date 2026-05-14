# Node.js 知识库

## 目录描述
本目录包含Node.js运行时环境相关的知识、项目实践、部署方案和最佳实践。

## 目录结构
```
node/
├── src/                     # JavaScript源代码文件
├── config/                  # 配置文件
├── docs/                    # Markdown文档
├── scripts/                 # Shell脚本
├── .gitignore               # Git忽略文件配置
├── Dockerfile               # Docker镜像构建文件
├── package.json             # Node.js包管理文件
└── README.md                # 本说明文件
```

## 子目录说明 (按功能分类)
### src/ - 源代码
- `server.js`: Node.js服务器主文件
- `platform-config-loader.js`: 平台配置加载器
- `platform-config-loader.test.js`: 配置加载器测试文件

### config/ - 配置文件
- `deployment-nodejs-separate-cm.yaml`: Kubernetes部署配置
- 其他YAML配置文件

### docs/ - 文档
- `QUICK-START.md`: 快速开始指南
- `node-https.md`: Node.js HTTPS配置相关
- `SOLUTION-COMPARISON.md`: 解决方案对比分析
- 其他Markdown文档

### scripts/ - 脚本
- `cert-management.sh`: 证书管理脚本
- `configmap-management.sh`: ConfigMap管理脚本
- `test-local.sh`: 本地测试脚本

## 快速检索
- 快速开始: 查看 `docs/` 目录中的 `QUICK-START.md`
- HTTPS配置: 查看 `docs/` 目录中的 `node-https.md`
- 部署方案: 查看 `config/` 目录中的部署文件和 `Dockerfile`
- 代码实现: 查看 `src/` 目录
- 解决方案: 查看 `docs/` 目录中的 `SOLUTION-COMPARISON.md`