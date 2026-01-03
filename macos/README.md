# macOS 知识库

## 目录描述
本目录包含macOS操作系统相关的知识、系统监控、网络诊断和实用脚本。

## 目录结构
```
macos/
├── docs/                     # Markdown文档
├── python/                   # Python脚本
├── scripts/                  # Shell脚本
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `btop.md`: Btop系统监控工具
- `dns.md`: DNS相关知识
- `install-fonts.md`: 字体安装指南
- `macOS-monitor-connect.md`: macOS监控连接相关
- `powermetrics.md`: Powermetrics工具使用
- `socat.md`: Socat工具使用
- `swith-bash.md`: 切换bash相关
- `connections_*.jsonl`: 连接监控日志

### python/ - Python脚本
- `a.py`: Python脚本示例
- `dns_tcp_monitor*.py`: DNS监控相关Python脚本
- `tcp_monitor.py`: TCP连接监控
- `monitor.py`: 系统监控Python脚本

### scripts/ - Shell脚本
- `chat.sh`: 聊天相关脚本
- `fix-bash.sh`: 修复bash脚本
- `hugg.sh`: HuggingFace相关脚本
- `monitor_background_shortcut_runner.sh`: 监控后台快捷方式运行器
- `resouce_usage.sh`: 资源使用监控脚本
- `resource.sh`: 资源监控脚本

## 快速检索
- 系统监控: 查看 `docs/` 目录中的 `btop.md`, `powermetrics.md`, `python/` 目录中的 `monitor*.py`
- 网络诊断: 查看 `python/` 目录中的 `dns*.py`, `tcp_monitor.py`, `docs/` 目录中的 `dns.md`, `socat.md`
- 资源监控: 查看 `scripts/` 目录中的 `resource*.sh`
- Shell脚本: 查看 `scripts/` 目录
- Python脚本: 查看 `python/` 目录