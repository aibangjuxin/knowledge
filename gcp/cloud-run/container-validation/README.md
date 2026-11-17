# 容器内部校验解决方案

## 概述

这套解决方案将校验逻辑内置到Docker镜像中，让容器在启动时自动检查运行环境，确保生产环境的安全性。

## 核心特性

- ✅ **自动环境检测**: 通过GCP元数据API自动识别运行环境
- ✅ **分支校验**: 生产环境强制要求master分支构建的镜像
- ✅ **配置校验**: 检查必需的环境变量和安全配置
- ✅ **构建信息追踪**: 在构建时注入Git信息，运行时可追溯
- ✅ **多语言支持**: 提供Shell和Python两种实现
- ✅ **优雅启动**: 校验失败时阻止应用启动，避免安全风险

## 方案对比

| 组件 | 用途 | 适用场景 |
|------|------|----------|
| startup-validator.sh | Shell版校验器 | 通用，适合各种应用 |
| python-validator.py | Python版校验器 | Python应用，功能更丰富 |
| app-entrypoint.sh | 应用入口点 | 需要优雅启动/关闭的应用 |
| Dockerfile | 容器构建配置 | 展示如何集成校验功能 |
| build-with-validation.sh | 构建脚本 | 自动化构建和Git信息注入 |

## 快速开始

### 1. 集成到现有项目

将校验脚本添加到你的Dockerfile中：

```dockerfile
# 复制校验脚本
COPY gcp/cloud-run/container-validation/startup-validator.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup-validator.sh

# 在应用启动前执行校验
RUN echo '#!/bin/bash\n/usr/local/bin/startup-validator.sh && exec "$@"' > /entrypoint.sh && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["your-app-command"]
```

### 2. 构建时注入Git信息

使用提供的构建脚本：

```bash
# 给脚本执行权限
chmod +x gcp/cloud-run/container-validation/build-with-validation.sh

# 构建并推送镜像
./gcp/cloud-run/container-validation/build-with-validation.sh \
  --name my-agent \
  --project myproject \
  --push
```

或者手动构建：

```bash
# 获取Git信息
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
GIT_COMMIT=$(git rev-parse --short HEAD)
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 构建镜像
docker build \
  --build-arg GIT_BRANCH="$GIT_BRANCH" \
  --build-arg GIT_COMMIT="$GIT_COMMIT" \
  --build-arg BUILD_TIME="$BUILD_TIME" \
  --build-arg BUILD_USER="$(whoami)" \
  -t europe-west2-docker.pkg.dev/myproject/containers/my-agent:${GIT_BRANCH}-${GIT_COMMIT} \
  .
```

### 3. 配置环境变量

在Cloud Run部署时设置必要的环境变量：

```bash
gcloud run jobs deploy my-agent-4 \
  --image=europe-west2-docker.pkg.dev/myproject/containers/my-agent:master-abc123 \
  --region=europe-west2 \
  --set-env-vars=PRODUCTION_APPROVED=true,DATABASE_URL=xxx,API_KEY=xxx,SECRET_KEY=xxx \
  --project=myproject-prd
```

## 详细配置

### 环境项目配置

在校验脚本中修改项目列表：

```bash
# startup-validator.sh 中的配置
PRODUCTION_PROJECTS=("myproject-prd" "myproject-prod" "myproject-production")
PRE_PRODUCTION_PROJECTS=("myproject-ppd" "myproject-preprod")
```

### 校验规则自定义

#### 1. 分支校验
```bash
# 修改要求的分支前缀
REQUIRED_BRANCH_PREFIX="master"
```

#### 2. 环境变量校验
```bash
# 添加必需的环境变量
required_env_vars=("DATABASE_URL" "API_KEY" "SECRET_KEY" "CUSTOM_CONFIG")
```

#### 3. 安全配置检查
```bash
# 检查调试模式是否关闭
if [[ "$DEBUG" == "true" ]]; then
    log_error "生产环境不能启用调试模式"
    return 1
fi
```

## Python版本使用

对于Python应用，可以直接在代码中集成：

```python
# 在应用启动时调用
from container_validation.python_validator import ContainerValidator

def main():
    # 执行启动校验
    validator = ContainerValidator()
    if not validator.validate():
        sys.exit(1)
    
    # 启动你的应用
    app.run()

if __name__ == "__main__":
    main()
```

或者作为独立脚本：

```dockerfile
# 在Dockerfile中
RUN python3 /usr/local/bin/python-validator.py && python3 app.py
```

## CI/CD集成

### GitLab CI示例

```yaml
build_with_validation:
  stage: build
  script:
    - ./gcp/cloud-run/container-validation/build-with-validation.sh --name $CI_PROJECT_NAME --push
  variables:
    GIT_BRANCH: $CI_COMMIT_REF_NAME
    GIT_COMMIT: $CI_COMMIT_SHORT_SHA
```

### GitHub Actions示例

```yaml
- name: Build with validation
  run: |
    ./gcp/cloud-run/container-validation/build-with-validation.sh \
      --name ${{ github.event.repository.name }} \
      --push
  env:
    GIT_BRANCH: ${{ github.ref_name }}
    GIT_COMMIT: ${{ github.sha }}
```

## 故障排除

### 常见问题

1. **无法获取项目ID**
```
❌ 无法获取GCP项目ID
```
**解决方案**: 确保容器运行在Cloud Run环境中，或设置`GOOGLE_CLOUD_PROJECT`环境变量

2. **分支校验失败**
```
❌ 生产环境只能部署来自 master 分支的镜像
当前分支: develop
```
**解决方案**: 确保从master分支构建镜像，或检查构建时的Git信息注入

3. **缺少环境变量**
```
❌ 缺少必需的环境变量: DATABASE_URL
```
**解决方案**: 在Cloud Run部署时设置所有必需的环境变量

4. **权限问题**
```
❌ 缺少生产环境批准标识 (PRODUCTION_APPROVED)
```
**解决方案**: 在生产环境部署时设置`PRODUCTION_APPROVED=true`

### 调试模式

启用详细日志输出：

```bash
# 设置环境变量
export VALIDATOR_DEBUG=true

# 或在Dockerfile中
ENV VALIDATOR_DEBUG=true
```

## 安全最佳实践

1. **最小权限原则**: 容器内只包含必要的工具和权限
2. **敏感信息保护**: 使用Secret Manager而不是环境变量存储敏感信息
3. **镜像扫描**: 定期扫描镜像漏洞
4. **审计日志**: 记录所有校验结果和部署操作
5. **回滚机制**: 准备快速回滚方案

## 监控和告警

建议设置以下监控：

1. **校验失败告警**: 当容器因校验失败而启动失败时发送告警
2. **非授权部署检测**: 监控非master分支到生产环境的部署尝试
3. **配置漂移检测**: 监控生产环境配置变更

## 总结

这套容器内部校验方案提供了：

- 🔒 **安全保障**: 防止未授权的镜像部署到生产环境
- 🚀 **自动化**: 无需人工干预，自动执行校验
- 🔍 **可追溯**: 完整的构建和部署信息追踪
- 🛠️ **灵活性**: 支持多种语言和部署方式
- 📊 **可观测**: 详细的日志和错误信息

通过将校验逻辑内置到镜像中，你可以确保无论通过什么方式部署，都会执行一致的安全检查。