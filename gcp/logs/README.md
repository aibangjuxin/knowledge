# Logs 知识库

## 目录描述
本目录包含日志分析、日志管理、日志聚合和日志处理相关的知识和实践经验。

## 目录结构
```
logs/
├── docs/                     # Markdown文档
├── scripts/                  # Python脚本
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `anaylize-gcp-log.md`: GCP日志分析
- `cross-project-vpc-*.md`: 跨项目VPC日志分析（不同AI工具版本）
- `Fluentd.md`: Fluentd日志收集工具
- `Interconnect-flow.md`: 互连流量相关
- `interconnects.md`: 互连相关日志
- `proxystatus.md`: 代理状态日志
- `vpc-*.md`: VPC相关日志
- `summary-cross.md`: 跨项目日志总结
- `eg-count-log.json`: JSON数据文件

### scripts/ - 脚本
- `count.py`: 日志计数脚本

## 快速检索
- GCP日志: 查看 `docs/` 目录中的 `anaylize-gcp-log.md`
- VPC日志: 查看 `docs/` 目录中的 `vpc-*.md` 文件
- AI分析: 查看 `docs/` 目录中的 `cross-project-vpc-*.md` 系列文件（不同AI工具分析）
- 日志工具: 查看 `docs/` 目录中的 `Fluentd.md`
- 计数统计: 查看 `scripts/` 目录中的 `count.py`