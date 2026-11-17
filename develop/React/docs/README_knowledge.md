# React 知识库

## 目录描述
本目录包含React前端框架相关的知识、项目结构、部署配置和最佳实践。

## 目录结构
```
React/
├── k8s/                     # Kubernetes部署相关配置
├── public/                  # React应用公共资源文件
├── scripts/                 # React相关脚本
├── src/                     # React源代码目录
├── .dockerignore            # Docker忽略文件配置
├── .gitignore               # Git忽略文件配置
├── Dockerfile               # Docker镜像构建文件
├── nginx.conf               # Nginx配置文件
├── package.json             # Node.js包管理文件
├── README.md                # React项目说明文件
└── README_knowledge.md      # 本说明文件
```

## 文件说明
- `package.json`: Node.js项目依赖和脚本配置
- `Dockerfile`: React应用Docker镜像构建配置
- `nginx.conf`: Nginx服务器配置，用于React应用部署
- `k8s/`: Kubernetes部署相关配置文件
- `src/`: React组件和源代码目录

## 快速检索
- 项目配置: 查看 `package.json`
- 部署配置: 查看 `Dockerfile`, `nginx.conf` 及 `k8s/` 目录
- 源代码: 查看 `src/` 目录
- 构建脚本: 查看 `scripts/` 目录