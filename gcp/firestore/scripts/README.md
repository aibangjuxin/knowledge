# Firestore 脚本工具集

## 脚本概览

### 1. `firestore-get-collection.sh`
获取整个 collection 的所有文档并保存为 JSON 文件。

**功能特点:**
- 支持分页获取
- 支持代理配置
- 彩色日志输出
- 自动获取 token

**使用示例:**
```bash
./firestore-get-collection.sh -c capteams -P my-project
```

---

### 2. `firestore-get-specific-fields.sh` ⭐ 新增
精准查询特定 collection 下某些文档的指定字段值，直接打印结果。

**功能特点:**
- ✅ 支持配置文件或脚本内数组定义查询
- ✅ 支持嵌套字段路径 (例如: `env.region.abc`)
- ✅ 直接打印 JSON 结果，无需重定向
- ✅ 快速验证数据是否写入 Firestore
- ✅ 彩色输出，易于识别结果
- ✅ 批量查询多个 collection/document/field

**使用场景:**
适合快速检索和验证数据，无需下载整个 collection。

#### 使用方法 1: 配置文件模式

1. 创建配置文件 `queries.txt`:
```
capteams:team001:env.region.abc
users:user123:settings.notification.email
configs:config001:database.connection.host
```

2. 运行脚本:
```bash
./firestore-get-specific-fields.sh -f queries.txt -P my-project
```

#### 使用方法 2: 编辑脚本内数组

1. 编辑脚本中的 `QUERY_LIST` 数组:
```bash
declare -a QUERY_LIST=(
    "capteams:team001:env.region.abc"
    "users:user123:settings.notification.email"
    "configs:config001:database.connection.host"
)
```

2. 运行脚本:
```bash
./firestore-get-specific-fields.sh -P my-project
```

#### 字段路径格式说明

Firestore 文档结构示例:
```json
{
  "name": "projects/my-project/databases/(default)/documents/capteams/team001",
  "fields": {
    "env": {
      "mapValue": {
        "fields": {
          "region": {
            "mapValue": {
              "fields": {
                "abc": {
                  "stringValue": "us-central1"
                }
              }
            }
          }
        }
      }
    }
  }
}
```

要获取 `env.region.abc` 的值，配置为:
```
capteams:team001:env.region.abc
```

脚本会自动解析嵌套结构并返回:
```
us-central1
```

#### 完整参数说明

```bash
./firestore-get-specific-fields.sh [选项]

选项:
  -f config_file  配置文件路径
  -p proxy        HTTP 代理 (例如: proxy.example.com:3128)
  -t token        Access token (省略则自动获取)
  -P project_id   GCP Project ID (省略则使用当前 gcloud project)
  -h              显示帮助
```

#### 输出示例

```
[INFO] Project ID  : my-project
[INFO] 查询条目数  : 3

[INFO] 开始查询 Firestore 数据...

[INFO] [1/3] 查询: capteams/team001 -> env.region.abc
[RESULT] 字段值:
"us-central1"

[INFO] [2/3] 查询: users/user123 -> settings.notification.email
[RESULT] 字段值:
"user@example.com"

[INFO] [3/3] 查询: configs/config001 -> database.connection.host
[RESULT] 字段值:
"db.example.com"

[INFO] ======================================
[INFO] 查询完成
[INFO] 总查询数: 3
[INFO] 成功: 3
[INFO] 失败/警告: 0
[INFO] ======================================
```

---

## 环境要求

### 必需工具
- `bash` (>= 4.0)
- `curl`
- `jq`
- `gcloud` (可选，用于自动获取 token 和 project ID)

### 安装依赖

**macOS:**
```bash
brew install jq
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt-get install jq
```

---

## 认证配置

### 方法 1: 使用 gcloud (推荐)
```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### 方法 2: 手动提供 token
```bash
TOKEN=$(gcloud auth print-access-token)
./firestore-get-specific-fields.sh -t $TOKEN -P my-project -f queries.txt
```

---

## 代理配置

如果需要通过代理访问 Firestore API:
```bash
./firestore-get-specific-fields.sh -f queries.txt -p proxy.example.com:3128
```

---

## 故障排查

### 1. 权限错误
**错误信息:**
```
API 错误: The caller does not have permission
```

**解决方法:**
确保使用的 Service Account 或用户账号有以下权限:
```
roles/datastore.viewer
```
或
```
roles/datastore.user
```

### 2. 字段不存在
**输出:**
```
[WARN] 字段 'env.region.abc' 不存在或为空
```

**解决方法:**
- 检查字段路径是否正确
- 验证文档中是否确实存在该字段
- 使用 `firestore-get-collection.sh` 下载完整文档查看结构

### 3. jq 命令未找到
**错误信息:**
```
[ERROR] 需要 jq 但未安装。
```

**解决方法:**
```bash
# macOS
brew install jq

# Linux
sudo apt-get install jq
```

---

## 最佳实践

### 1. 批量查询优化
当需要查询大量字段时，使用配置文件模式:
```bash
# 创建配置文件
cat > my-queries.txt <<EOF
collection1:doc1:field.path.1
collection1:doc2:field.path.2
collection2:doc3:field.path.3
EOF

# 执行查询
./firestore-get-specific-fields.sh -f my-queries.txt
```

### 2. 结果重定向
虽然脚本设计为直接打印，但也可以重定向保存:
```bash
./firestore-get-specific-fields.sh -f queries.txt > results.txt 2>&1
```

### 3. 集成到 CI/CD
```bash
#!/bin/bash
# 验证数据写入脚本
./firestore-get-specific-fields.sh -f validation-queries.txt -P $GCP_PROJECT

if [ $? -eq 0 ]; then
    echo "数据验证通过"
else
    echo "数据验证失败"
    exit 1
fi
```

---

## 比较: 两种脚本的使用场景

| 场景 | 使用脚本 |
|------|---------|
| 下载整个 collection 做分析 | `firestore-get-collection.sh` |
| 快速验证某个字段是否写入 | `firestore-get-specific-fields.sh` ⭐ |
| 批量检查多个文档的特定字段 | `firestore-get-specific-fields.sh` ⭐ |
| 导出数据到文件 | `firestore-get-collection.sh` |
| 调试和验证数据 | `firestore-get-specific-fields.sh` ⭐ |

---

## 许可证

MIT License
