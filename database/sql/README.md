# SQL 知识库

## 目录描述
本目录包含SQL数据库查询语言相关的知识、实践经验、查询优化和数据库管理。

## 目录结构
```
sql/
├── docs/                     # Markdown文档
├── scripts/                  # Shell脚本
├── sqlfiles/                 # SQL查询脚本
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `api-table.md`: API表相关查询
- `bigquery-tables.md`: BigQuery表结构
- `biqquery-sql-cost.md`: BigQuery SQL成本分析
- `bq.md`: BQ命令行工具使用
- `connect-table-query.md`: 表连接查询
- `duckdb*.md`: DuckDB数据库相关
- `join*.md`: JOIN操作相关
- `select.md`: SELECT语句相关
- `union-query.md`: UNION查询
- `useful-sql.md`: 实用SQL语句
- `backup.md`: 数据库备份相关
- `cost.md`: 成本分析相关

### sqlfiles/ - SQL文件
- SQL查询脚本文件

### scripts/ - 脚本
- Shell脚本文件

## 快速检索
- BigQuery: 查看 `docs/` 目录中的 `bigquery*.md`, `bq.md` 文件
- JOIN操作: 查看 `docs/` 目录中的 `join*.md` 文件
- 查询优化: 查看 `docs/` 目录中的 `useful-sql.md`
- 成本分析: 查看 `docs/` 目录中的 `biqquery-sql-cost.md` 和 `cost.md`
- DuckDB: 查看 `docs/` 目录中的 `duckdb*.md` 文件
- SQL脚本: 查看 `sqlfiles/` 目录
- 脚本: 查看 `scripts/` 目录