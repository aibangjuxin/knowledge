# GCS Bucket 批量创建 - 快速参考

## 快速开始

```bash
# 1. 使用默认配置创建单个 bucket
./create-buckets.sh -p aibang-projectid-wwww-dev

# 2. 使用配置文件批量创建
./create-buckets.sh -p aibang-projectid-wwww-dev -c buckets-config.txt
```

## 配置文件格式

```
kms-project == <kms-project> region == <region> project == <project> buckets = <bucket1> <bucket2> ...
```

### 示例

```bash
# 创建多个 bucket (同一区域)
kms-project == abjx-id-kms-dev region == europe-west2 project == aibang-projectid-wwww-dev buckets = gs://cap-lex-eg-gkeconfigs gs://cap-lex-eg-gkeconfigs2

# 创建 bucket (不同区域)
kms-project == abjx-id-kms-dev region == us-central1 project == aibang-projectid-wwww-dev buckets = gs://cap-dev-us-backup
```

## 关键特性

| 特性 | 说明 |
|------|------|
| **批量创建** | 一次命令创建多个 bucket |
| **灵活配置** | 每行可定义不同参数 |
| **幂等性** | 已存在的 bucket 会跳过 |
| **自动配置** | KMS 加密、Autoclass、Soft Delete 等 |
| **统计报告** | 显示成功/已存在/失败数量 |

## 输出统计

```
总 Bucket 数:    2
新创建:          2
已存在:          0
失败:            0
```

## 相关文件

- [`create-buckets.sh`](file:///Users/lex/git/knowledge/gcp/buckets/create-buckets.sh) - 主脚本
- [`buckets-config.txt`](file:///Users/lex/git/knowledge/gcp/buckets/buckets-config.txt) - 配置文件示例
- [`README.md`](file:///Users/lex/git/knowledge/gcp/buckets/README.md) - 完整文档
- [`buckets-des.md`](file:///Users/lex/git/knowledge/gcp/buckets/buckets-des.md) - 原始模板

## 注意事项

> [!IMPORTANT]
> - 只处理 `project` 字段与 `-p` 参数匹配的配置行
> - Bucket 名称可带或不带 `gs://` 前缀
> - 多个 bucket 之间用空格分隔

> [!TIP]
> - 使用 `#` 注释配置文件中的行
> - 先测试单个 bucket，再批量创建
