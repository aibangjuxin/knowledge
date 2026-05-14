# Pipeline 知识库

## 目录描述
本目录包含CI/CD流水线相关的知识、配置、最佳实践和工具集成。

## 目录结构
```
pipeline/
├── cd-pipeline/              # CD流水线相关内容
├── docs/                     # Markdown文档
├── release-dashboard/        # 发布仪表板相关内容
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `copy-pipeline.md`: 流水线复制相关
- `housekeep-sms.md`: 微服务整理相关
- `insert-json.md`: JSON插入相关
- `master-branch.md`: 主分支相关
- `oidc.md`: OIDC集成相关
- `osapath.md`: OSA路径相关
- `pipeline-flow.md`: 流水线流程相关
- `pipeline-layer.md`: 流水线层级相关
- `sonar.md`: Sonar集成相关
- `stash.md`: Stash相关
- `trigger-pipeline*.md`: 流水线触发相关
- `js.html`: JavaScript相关HTML文件
- `data2.json`: JSON数据文件

## 快速检索
- 流水线流程: 查看 `docs/` 目录中的 `pipeline-flow.md`
- 流水线触发: 查看 `docs/` 目录中的 `trigger-pipeline*.md`
- OIDC集成: 查看 `docs/` 目录中的 `oidc.md`
- Sonar集成: 查看 `docs/` 目录中的 `sonar.md`
- 主分支: 查看 `docs/` 目录中的 `master-branch.md`
- 流水线复制: 查看 `docs/` 目录中的 `copy-pipeline.md`
- CD流水线: 查看 `cd-pipeline/` 目录
- 发布仪表板: 查看 `release-dashboard/` 目录