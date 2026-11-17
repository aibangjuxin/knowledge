# 容器启动校验器配置指南

## 概述

提供了三种版本的启动校验器，支持不同的配置方式：

1. **startup-validator.sh** - 基础版本，支持模式匹配
2. **startup-validator-v2.sh** - 增强版本，支持配置文件和环境变量
3. **startup-validator-v3.sh** - 高级版本，支持JSON配置

## 配置方式对比

### 方式1: 命名约定模式匹配

最简单的方式，基于项目名称的模式匹配：

```bash
# 在脚本中直接配置
PRODUCTION_PATTERNS=("*-prd" "*-prod" "*-production")
PRE_PRODUCTION_PATTERNS=("*-ppd" "*-preprod" "*-staging")
DEVELOPMENT_PATTERNS=("*-dev" "*-test" "*-sandbox")
```

**优点：**
- 简单直接，无需额外配置文件
- 适合标准化命名的组织

**缺点：**
- 修改需要重新构建镜像
- 不够灵活

### 方式2: 环境变量配置

通过环境变量覆盖默认配置：

```bash
# 强制指定环境类型
export FORCE_ENVIRONMENT_TYPE="production"

# 自定义分支要求
export REQUIRED_PRODUCTION_BRANCH="main"

# 配置文件路径
export VALIDATOR_CONFIG_FILE="/custom/path/validator.conf"
```

**优点：**
- 运行时配置，无需重建镜像
- 支持CI/CD流水线动态配置

### 方式3: 配置文件

使用 `.conf` 或 `.json` 配置文件：

```bash
# Shell配置文件
source /app/config/validator.conf

# JSON配置文件（需要jq）
jq -r '.environments[].type' /app/config/validator.json
```

**优点：**
- 集中管理配置
- 支持复杂的校验规则
- 版本控制友好

### 方式4: GCP项目标签

利用GCP项目的标签来标识环境：

```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:SERVICE_ACCOUNT" \
    --role="roles/browser"

# 设置项目标签
gcloud projects update PROJECT_ID \
    --update-labels environment=production
```

**优点：**
- 与GCP原生集成
- 集中管理，不依赖代码

**缺点：**
- 需要额外的IAM权限
- 依赖网络连接

## 推荐配置策略

### 小型项目
使用**方式1**（模式匹配）+ **方式2**（环境变量）：

```dockerfile
# Dockerfile
COPY startup-validator.sh /app/
ENV REQUIRED_PRODUCTION_BRANCH=main
```

### 中型项目
使用**方式2**（环境变量）+ **方式3**（配置文件）：

```yaml
# docker-compose.yml 或 Cloud Run配置
environment:
  - VALIDATOR_CONFIG_FILE=/app/config/validator.conf
  - FORCE_ENVIRONMENT_TYPE=${ENVIRONMENT_TYPE}
```

### 大型企业项目
使用**方式3**（JSON配置）+ **方式4**（GCP标签）：

```json
{
  "environments": [
    {
      "type": "production",
      "projects": ["company-app-prod-us", "company-app-prod-eu"],
      "patterns": ["*-prod-*"],
      "validation": {
        "required_branch": "main",
        "requires_approval": true,
        "required_env_vars": ["DATABASE_URL", "API_KEY"]
      }
    }
  ]
}
```

## 使用示例

### 基本使用

```dockerfile
# Dockerfile
FROM node:18-alpine
COPY startup-validator.sh /app/
RUN chmod +x /app/startup-validator.sh

# 在应用启动前执行校验
ENTRYPOINT ["/app/startup-validator.sh", "&&", "node", "app.js"]
```

### 高级配置

```dockerfile
# Dockerfile
FROM node:18-alpine
RUN apk add --no-cache jq curl

COPY startup-validator-v3.sh /app/
COPY validator.json /app/config/
RUN chmod +x /app/startup-validator-v3.sh

ENV VALIDATOR_CONFIG_FILE=/app/config/validator.json
ENTRYPOINT ["/app/startup-validator-v3.sh", "&&", "node", "app.js"]
```

### CI/CD集成

```yaml
# .github/workflows/deploy.yml
- name: Deploy to Cloud Run
  env:
    FORCE_ENVIRONMENT_TYPE: ${{ github.ref == 'refs/heads/main' && 'production' || 'development' }}
    REQUIRED_PRODUCTION_BRANCH: main
    PRODUCTION_APPROVED: ${{ github.event_name == 'release' && 'true' || '' }}
  run: |
    gcloud run deploy my-service \
      --image gcr.io/project/image:tag \
      --set-env-vars FORCE_ENVIRONMENT_TYPE=$FORCE_ENVIRONMENT_TYPE
```

## 最佳实践

1. **分层配置**：结合多种方式，环境变量覆盖配置文件
2. **安全优先**：生产环境使用最严格的校验
3. **可观测性**：记录所有校验决策和结果
4. **测试覆盖**：为不同环境类型编写测试用例
5. **文档同步**：保持配置文档与实际配置同步

## 故障排除

### 常见问题

1. **无法获取项目ID**
   - 检查Cloud Run元数据服务
   - 确认GOOGLE_CLOUD_PROJECT环境变量

2. **环境类型识别错误**
   - 检查项目命名是否符合模式
   - 验证配置文件格式
   - 确认GCP项目标签

3. **校验失败**
   - 检查分支名称
   - 确认必需的环境变量
   - 验证审批标识

### 调试模式

```bash
# 启用调试日志
export DEBUG_MODE=true

# 跳过校验（仅用于调试）
export SKIP_VALIDATION=true

# 强制环境类型
export FORCE_ENVIRONMENT_TYPE=development
```