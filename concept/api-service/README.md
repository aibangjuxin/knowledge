# API Service 知识库

## 目录描述
本目录包含API服务设计、实现、部署和流式传输相关的知识和实践经验。

## 目录结构
```
api-service/
├── config/                   # 配置文件
├── docs/                     # Markdown文档
├── scripts/                  # Python脚本
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `api*.md`: API相关文档
- `Architecture-Stream-API.md`: 流式API架构
- `EAPI-PAPI-SAPI.md`: API分类相关
- `SSE.md`: Server-Sent Events相关
- `Stream-Events-apis.md`: 流式事件API
- `api-wechat.html`: 微信API相关HTML文档

### scripts/ - 脚本
- `main.py`: 主程序入口

### config/ - 配置文件
- `deployment.yaml`: Kubernetes部署配置
- `Dockerfile`: Docker镜像构建文件
- `requirements.txt`: Python依赖文件

## 快速检索
- API设计: 查看 `docs/` 目录中的 `api*.md` 文件
- 流式API: 查看 `docs/` 目录中的 `SSE.md`, `Stream-Events-apis.md`, `Architecture-Stream-API.md`
- 部署配置: 查看 `config/` 目录中的 `deployment.yaml` 和 `Dockerfile`
- 代码实现: 查看 `scripts/` 目录中的 `main.py`
- 依赖管理: 查看 `config/` 目录中的 `requirements.txt`