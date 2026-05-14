# Firestore 知识库

## 目录描述
本目录包含Google Cloud Firestore数据库相关的知识、数据操作、迁移和最佳实践。

## 目录结构
```
firestore/
├── docs/                     # Markdown文档
├── scripts/                  # Shell脚本
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `firestore.md`: Firestore基础和高级功能
- `firestore-compare.md`: Firestore与其他数据库对比
- `firestore-export-to-bigquery.md`: Firestore导出到BigQuery
- `merged-scripts.md`: 合并的Firestore脚本
- `tenant-design.md`: 租户设计相关
- `tenant.md`: 租户相关功能

### scripts/ - 脚本
- `firestore-get-collection*.sh`: 获取Firestore集合的脚本（不同AI工具版本）

## 快速检索
- Firestore基础: 查看 `docs/` 目录中的 `firestore.md`
- 数据导出: 查看 `docs/` 目录中的 `firestore-export-to-bigquery.md`
- 集合操作: 查看 `scripts/` 目录中的 `firestore-get-collection*.sh` 脚本
- 数据库对比: 查看 `docs/` 目录中的 `firestore-compare.md`
- 租户设计: 查看 `docs/` 目录中的 `tenant-design.md`
- 脚本: 查看 `scripts/` 目录