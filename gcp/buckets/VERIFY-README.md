# GCS Bucket 验证脚本使用说明

## 概述

`verify-buckets.sh` 是一个用于验证和显示 GCS Bucket 详细配置信息的脚本。

## 使用方法

```bash
# 基本用法（使用当前活动项目）
./verify-buckets.sh -b gs://my-bucket-name

# 指定项目
./verify-buckets.sh -b my-bucket-name -p aibang-projectid-wwww-dev

# 不带 gs:// 前缀
./verify-buckets.sh -b my-bucket-name

# 查看帮助
./verify-buckets.sh -h
```

## 显示信息

脚本会显示以下 12 类详细信息：

### 1. Bucket 基本信息
- Bucket 名称
- 位置（Location）
- 位置类型（Region/Multi-region）
- 存储类别（Storage Class）
- 创建时间
- 更新时间
- Metageneration
- PZS 满足状态

### 2. IAM Policy (访问控制策略)
- 完整的 IAM 策略配置
- 角色绑定（Role Bindings）
- 成员列表（Members）

### 3. Lifecycle (生命周期规则)
- 生命周期规则详情
- 条件配置（Age、Created Before、Storage Class 等）
- 动作类型（Delete、SetStorageClass 等）

### 4. Versioning (版本控制)
- 版本控制启用状态

### 5. CORS (跨域资源共享)
- CORS 规则
- 允许的源（Origin）
- 允许的方法（Method）
- 响应头（Response Headers）
- 最大缓存时间（Max Age）

### 6. Labels (标签)
- 所有标签键值对

### 7. Encryption (加密配置)
- 默认 KMS 密钥
- Event-Based Hold 状态

### 8. Autoclass (自动存储类别)
- Autoclass 启用状态
- 终端存储类别
- 启用时间

### 9. Soft Delete Policy (软删除策略)
- 保留时长（秒和天数）
- 生效时间

### 10. Logging (日志配置)
- 日志 Bucket
- 日志对象前缀

### 11. Public Access Prevention (公共访问防护)
- 公共访问防护状态
- 强制执行或继承状态

### 12. Uniform Bucket-Level Access (统一桶级访问)
- 统一桶级访问启用状态
- 锁定时间

## 输出示例

```bash
$ ./verify-buckets.sh -b gs://pre-env-region-gkeconfigs -p aibang-projectid-wwww-dev

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  GCS Bucket 验证工具
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Bucket 名称: gs://pre-env-region-gkeconfigs
项目 ID: aibang-projectid-wwww-dev

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  检查 Bucket 是否存在
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[SUCCESS] Bucket 存在且可访问

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1. Bucket 基本信息
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[INFO] 获取 bucket 详细配置...

NAME                          LOCATION      LOCATION_TYPE  STORAGE_CLASS  TIME_CREATED         UPDATED
pre-env-region-gkeconfigs     EUROPE-WEST2  region         STANDARD       2021-05-14 01:35:39  2025-05-08 20:11:22

▶ 存储统计
────────────────────────────────────────────────────────────
Metageneration: 790
Satisfies PZS: True

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  2. IAM Policy (访问控制策略)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[INFO] 获取 IAM 策略...

bindings:
- members:
  - serviceAccount:service-123456@gs-project-accounts.iam.gserviceaccount.com
  role: roles/storage.legacyBucketOwner
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  6. Labels (标签)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[INFO] 获取标签...

  enforcer_autoclass: enabled

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  8. Autoclass (自动存储类别)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[INFO] 获取 Autoclass 配置...

[SUCCESS] Autoclass: 已启用
  终端存储类别: ARCHIVE
  启用时间: 2025-05-08T20:11:22.705000+00:00

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  验证完成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[SUCCESS] Bucket gs://pre-env-region-gkeconfigs 的所有配置信息已显示
```

## 特性

- ✅ **彩色输出**: 清晰的分段和状态提示
- ✅ **完整信息**: 显示 12 类详细配置
- ✅ **格式化输出**: 易于阅读的结构化信息
- ✅ **错误处理**: 优雅处理不存在的配置项
- ✅ **灵活使用**: 支持带或不带 gs:// 前缀

## 前置要求

1. **gcloud CLI**: 已安装并配置
2. **认证**: 已通过 `gcloud auth login` 完成身份验证
3. **权限**: 具有以下 IAM 权限:
   - `storage.buckets.get`
   - `storage.buckets.getIamPolicy`

## 相关文件

- [`verify-buckets.sh`](file:///Users/lex/git/knowledge/gcp/buckets/verify-buckets.sh) - 验证脚本
- [`create-buckets.sh`](file:///Users/lex/git/knowledge/gcp/buckets/create-buckets.sh) - 创建脚本
- [`buckets-des.md`](file:///Users/lex/git/knowledge/gcp/buckets/buckets-des.md) - Bucket 配置模板

## 注意事项

> [!TIP]
> - 脚本只显示信息，不会修改任何配置
> - 如果某些配置未设置，会显示相应提示
> - 使用 `jq` 工具解析 JSON 输出，确保已安装
