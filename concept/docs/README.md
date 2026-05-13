# Concept 知识库

## 目录描述

本目录包含各种技术概念、理论基础和规范相关的知识。

## 目录结构

```
concept/
├── rfc.md                         # RFC 文档相关概念
├── model-driven-thinking.md        # 从命令驱动到模型驱动（核心方法论）
└── README.md                       # 本说明文件
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `rfc.md` | RFC（Request for Comments）文档相关的概念和标准 |
| `model-driven-thinking.md` | 云平台资源创建的方法论：先模型后命令，思考优于实现 |

## 核心思想

```
Concept → Resource Model → Dependencies → Command
```

在云平台（GCP / Kubernetes / Linux）中创建资源时，正确的方式是：

1. **先理解概念** — 这个资源是什么？解决什么问题？
2. **再理解资源模型** — API Object 的必选/可选/只读字段
3. **再分析依赖关系** — 哪些资源必须先存在？
4. **最后才是命令** — 当前三步清晰后，命令只是翻译

> 思考比实现更重要。方法对了，事半功倍。

## 快速检索

- 技术标准：查看 `rfc.md`
- 工程思维：查看 `model-driven-thinking.md`
