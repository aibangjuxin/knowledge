# Docker 知识库

## 目录描述
本目录包含Docker容器化技术相关的知识、实践经验和解决方案。

## 目录结构
```
docker/
├── docs/                     # Markdown文档
├── multistage-builds/        # 多阶段构建相关内容
├── scripts/                  # Shell脚本
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `Dockeffile-user-pass-violation.md`: Dockerfile用户密码违规相关
- `Docker-annotations.md`: Docker注解相关知识
- `docker-image-lifecycle.md`: Docker镜像生命周期
- `Docker-prune.md`: Docker清理相关
- `docker-python.md`: Docker与Python相关
- `docker-sepcial.md`: Docker特殊用法
- `docker-utf8.md`: Docker UTF-8编码相关
- `java-version.md`: Java版本相关
- `mac-Docker-nas.md`: Mac Docker与NAS相关
- `merged-scripts.md`: 合并脚本相关
- `network-multitool.md`: 网络多工具相关
- `utf-8.md`: UTF-8编码相关

### scripts/ - 脚本
- `debug-java-pod.sh`: 调试Java Pod的脚本

## 快速检索
- Docker镜像构建: 查看 `multistage-builds/` 目录及相关构建文档
- Docker网络: 查看 `docs/` 目录中的 `network-multitool.md`
- Docker优化: 查看 `docs/` 目录中的 `Docker-prune.md`
- 特殊配置: 查看 `docs/` 目录中的 `Docker-annotations.md`
- 脚本: 查看 `scripts/` 目录