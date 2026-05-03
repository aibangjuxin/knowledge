# SSL 知识库

## 目录描述
本目录包含SSL/TLS证书、加密、安全通信和证书管理相关的知识。

## 目录结构
```
ssl/
├── docs/                     # Markdown文档
├── ingress-ssl/              # Ingress SSL配置相关内容
├── scripts/                  # Shell脚本（SSL相关操作）
├── text/                     # 文本文件
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `pem-get-ssl.md`: PEM格式SSL证书相关
- `read-cert.md`: 读取证书相关
- `root.md`: 根证书相关
- `Sans.md`: SAN（Subject Alternative Name）相关
- `ssl-type.md`: SSL类型相关
- `what-ssl.md`: SSL基础概念

### scripts/ - 脚本
- `get-ssl*.sh`: SSL信息获取脚本

### text/ - 文本文件
- `one.txt`: 文本文件
- `output*.txt`: 输出文件

### ingress-ssl/ - Ingress SSL配置
- Ingress SSL配置相关内容

## 快速检索
- 证书获取: 查看 `scripts/` 目录中的 `get-ssl*.sh` 脚本
- 证书类型: 查看 `docs/` 目录中的 `ssl-type.md`
- SAN扩展: 查看 `docs/` 目录中的 `Sans.md`
- Ingress配置: 查看 `ingress-ssl/` 目录
- 基础概念: 查看 `docs/` 目录中的 `what-ssl.md`
- PEM格式: 查看 `docs/` 目录中的 `pem-get-ssl.md`
- 证书读取: 查看 `docs/` 目录中的 `read-cert.md`
- 根证书: 查看 `docs/` 目录中的 `root.md`