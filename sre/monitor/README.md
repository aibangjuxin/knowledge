# Monitor 知识库

## 目录描述
本目录包含系统监控、性能分析、指标收集和告警相关的知识和实践经验。

## 目录结构
```
monitor/
├── docs/                     # Markdown文档
├── gce-disk/                 # GCE磁盘监控相关内容
├── opentelemetry/            # OpenTelemetry监控框架相关内容
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `Capacity-Forecasting.md`: 容量预测相关
- `FailedScheduling.md`: 调度失败监控
- `gce-mig-status.md`: GCE MIG状态监控
- `How-to-manage-monitor-policy.md`: 监控策略管理
- `Mimir.md`: Mimir监控系统相关
- `monitor-base-ai.md`: AI辅助基础监控
- `monitor-memory.md`: 内存监控
- `monitor-proxy.md`: 代理监控
- `monitory-base.md`: 基础监控概念
- `pipeline-status.md`: 流水线状态监控

## 快速检索
- 基础监控: 查看 `docs/` 目录中的 `monitory-base.md`, `monitor-base-ai.md`
- 云监控: 查看 `docs/` 目录中的 `gce-mig-status.md` 及 `gce-disk/` 目录
- 性能监控: 查看 `docs/` 目录中的 `monitor-memory.md`, `Capacity-Forecasting.md`
- 监控框架: 查看 `docs/` 目录中的 `Mimir.md` 及 `opentelemetry/` 目录
- 策略管理: 查看 `docs/` 目录中的 `How-to-manage-monitor-policy.md`
- 流水线监控: 查看 `docs/` 目录中的 `pipeline-status.md`
- 调度监控: 查看 `docs/` 目录中的 `FailedScheduling.md`