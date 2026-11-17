# OB 知识库

## 目录描述
本目录包含OB（可能是Oracle或其他系统）相关的知识、公共出口配置和Squid代理配置。

## 目录结构
```
ob/
├── config/                   # 配置文件
├── docs/                     # Markdown文档
├── egress-dynamic/           # 动态出口配置相关内容
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `egress-summary.md`: 出口配置摘要
- `ob-public-egress*.md`: OB公共出口配置文档（包含不同AI工具版本）
- `squid-conf.md`: Squid代理配置相关

### config/ - 配置文件
- `public_egress_config.yaml`: 公共出口配置文件
- `squid-conf-complete.conf`: 完整的Squid配置文件

### egress-dynamic/ - 动态出口配置
- 动态出口配置相关内容

## 快速检索
- 公共出口配置: 查看 `docs/` 目录中的 `ob-public-egress*.md` 文件
- Squid配置: 查看 `docs/` 目录中的 `squid-conf.md` 和 `config/` 目录中的 `squid-conf-complete.conf`
- 出口摘要: 查看 `docs/` 目录中的 `egress-summary.md`
- 配置文件: 查看 `config/` 目录
- 动态配置: 查看 `egress-dynamic/` 目录