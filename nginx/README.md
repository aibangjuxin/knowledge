# Nginx 知识库

## 目录描述
本目录包含Nginx Web服务器和反向代理相关的知识、配置技巧、性能优化和故障排除方案。

## 目录结构
```
nginx/
├── buffer/                           # 缓冲区配置相关
├── config/                           # 配置文件
├── docs/                             # Markdown文档
├── gce-nginx-l4-enhance/             # GCE Nginx L4增强相关
├── ingress-control/                  # 入口控制相关
├── nginx-logs/                       # Nginx日志相关
├── tools/                            # 工具和资源文件
└── README.md                         # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `nginx-conf.md`: Nginx配置文件详解
- `nginx-feature.md`: Nginx功能特性
- `nginx-110.md`, `nginx-111.md`: Nginx版本相关
- `nginx-enhance.md`, `nginx-enhance-chatgpt-claude.md`: Nginx性能增强
- `nginx-cpu.md`: CPU相关优化
- `nginx-gzip.md`: Gzip压缩配置
- `nginx-size-enhance.md`: 尺寸相关优化
- `nginx-proxy-pass.md`, `nginx-proxy-pass-usersgent.md`: 代理配置
- `nginx-proxy-buffer.md`: 代理缓冲区
- `upstream.md`: Upstream配置
- `L7+L4.md`: 7层和4层负载均衡
- `nginx-mtls.md`: mTLS双向认证
- `nginx-safe.md`: 安全配置
- `ssl_client_certificate_chain.md`: SSL客户端证书链
- `nginx-499-502.md`, `nginx-502.md`: HTTP错误码处理
- `nginx-error.md`: Nginx错误处理
- `nginx-log.md`, `nginx-debug-log-example.md`: 日志配置和调试

### config/ - 配置文件
- YAML配置文件

### tools/ - 工具和资源
- 图片资源

## 快速检索
- Nginx基础: 查看 `docs/` 目录中的 `nginx-conf.md`, `nginx-feature.md`
- 性能优化: 查看 `docs/` 目录中的 `nginx-enhance*.md`, `nginx-size*.md` 文件
- 代理配置: 查看 `docs/` 目录中的 `nginx-proxy*.md` 文件
- 错误处理: 查看 `docs/` 目录中的 `nginx-502.md`, `nginx-499-502.md`, `nginx-error.md`
- 安全配置: 查看 `docs/` 目录中的 `nginx-mtls.md`, `nginx-safe.md`
- 日志管理: 查看 `docs/` 目录中的 `nginx-log.md` 及 `nginx-logs/` 目录
- 配置文件: 查看 `config/` 目录
- 工具资源: 查看 `tools/` 目录