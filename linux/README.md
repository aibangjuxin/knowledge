# Linux 知识库

## 目录描述
本目录包含Linux操作系统相关的知识、实践经验、命令技巧和系统管理解决方案。

## 目录结构
```
linux/
├── config/                   # 配置文件
├── docs/                     # Markdown文档
├── linux-os-optimize/        # Linux系统优化相关内容
├── neovim/                   # NeoVim编辑器相关配置和技巧
├── scripts/                  # Shell脚本
├── tools/                    # 工具和资源文件
├── version/                  # 版本管理相关内容
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `cgroup.md`, `Linux-control-group-v2.md`: 控制组相关
- `anacrontab.md`: Anacron定时任务
- `user-add.md`: 用户管理
- `Linux-start-services.md`: Linux服务启动
- `limit.md`: 系统限制设置

### 网络相关 (在docs/目录)
- `http-*.md`: HTTP协议相关知识
- `curl-*.md`: Curl工具使用技巧
- `nc.md`: Netcat工具使用
- `route.md`: 路由配置
- `mtu.md`, `tcp-large-send-offload.md`: 网络参数优化

### 文件和文本处理 (在docs/目录)
- `diff.md`: Diff命令使用
- `replace*.md`: 文本替换技巧
- `csv-format-to-markdown.md`: CSV格式转换
- `jq*.md`: JQ工具处理JSON

### 性能和安全 (在docs/目录)
- `linux-performance.md`: Linux性能优化
- `mtls.md`, `tls.md`, `ssl.md`: 安全协议相关
- `SAN.md`: SAN证书相关

### 开发工具 (在docs/目录)
- `nvim*.md`: NeoVim编辑器相关
- `git.md`: Git在Linux下的使用

### scripts/ - 脚本
- Shell脚本文件

### tools/ - 工具和资源
- 图片和压缩文件

## 快速检索
- 系统优化: 查看 `docs/` 目录中的 `linux-performance.md` 和 `linux-os-optimize/` 目录
- 网络调试: 查看 `docs/` 目录中的 `curl-*.md` 和 `http-*.md` 文件
- 文本处理: 查看 `docs/` 目录中的 `jq*.md`, `replace*.md` 等文件
- 安全协议: 查看 `docs/` 目录中的 `tls.md`, `mtls.md`, `ssl.md` 文件
- 编辑器: 查看 `docs/` 目录中的 `nvim*.md` 文件及 `neovim/` 目录
- 脚本: 查看 `scripts/` 目录
- 工具资源: 查看 `tools/` 目录