# Cloud Run 镜像分支校验指南

## 概述

为了确保生产环境的安全性和稳定性，我们实施了镜像分支校验机制。该机制确保只有来自master分支的镜像才能部署到生产环境。

## 解决方案对比

| 方案 | 适用场景 | 优点 | 缺点 |
|------|----------|------|------|
| Shell脚本校验 | 手动部署、简单CI/CD | 灵活、易于定制 | 需要手动集成 |
| GitLab CI/CD | 使用GitLab的团队 | 自动化程度高、集成度好 | 依赖GitLab |
| Cloud Build | 使用GCP原生工具 | 与GCP深度集成 | 学习成本较高 |
| 增强部署脚本 | 需要交互式部署 | 用户友好、安全确认 | 不适合完全自动化 |

## 方案1: 独立校验脚本

### 使用方法
```bash
# 给脚本执行权限
chmod +x gcp/cloud-run/image-branch-validation.sh

# 校验示例
./gcp/cloud-run/image-branch-validation.sh prd "europe-west2-docker.pkg.dev/myproject/containers/my-agent:master-abc123"
```

### 集成到现有脚本
```bash
# 在部署前调用校验
if ! ./image-branch-validation.sh "$ENVIRONMENT" "$IMAGE_URL"; then
    echo "分支校验失败，停止部署"
    exit 1
fi

# 继续原有的gcloud run jobs deploy命令
gcloud run jobs deploy my-agent-4 --image="$IMAGE_URL" ...
```

## 方案2: 增强部署脚本

### 使用方法
```bash
# 给脚本执行权限
chmod +x gcp/cloud-run/secure-cloud-run-deploy.sh

# 开发环境部署
./secure-cloud-run-deploy.sh -n my-agent-4 -i europe-west2-docker.pkg.dev/myproject/containers/my-agent:dev-abc123 -e dev

# 生产环境部署 (会自动校验分支)
./secure-cloud-run-deploy.sh -n my-agent-4 -i europe-west2-docker.pkg.dev/myproject/containers/my-agent:master-abc123 -e prd

# 紧急情况跳过校验 (不推荐)
./secure-cloud-run-deploy.sh -n my-agent-4 -i europe-west2-docker.pkg.dev/myproject/containers/my-agent:hotfix-abc123 -e prd --skip-validation
```

## 方案3: GitLab CI/CD集成

### 设置步骤

1. **将配置添加到.gitlab-ci.yml**
```yaml
include:
  - local: 'gcp/cloud-run/gitlab-ci-branch-validation.yml'
```

2. **设置GitLab变量**
- `GCP_SERVICE_KEY`: GCP服务账号密钥 (Base64编码)
- `PROJECT_ID`: GCP项目ID

3. **分支策略**
- `develop` → 自动部署到开发环境
- `master` → 手动部署到测试/生产环境
- `feature/*` → 仅构建，不部署

### 部署流程
```
代码提交 → 构建镜像 → 分支校验 → 环境部署
```

## 方案4: Cloud Build集成

### 设置步骤

1. **创建Cloud Build触发器**
```bash
gcloud builds triggers create github \
  --repo-name=your-repo \
  --repo-owner=your-org \
  --branch-pattern="^(master|develop|feature/.*)$" \
  --build-config=gcp/cloud-run/cloudbuild-branch-validation.yaml \
  --substitutions=_DEPLOY_ENV=prd
```

2. **为不同环境创建不同触发器**
```bash
# 开发环境触发器
gcloud builds triggers create github \
  --repo-name=your-repo \
  --repo-owner=your-org \
  --branch-pattern="^develop$" \
  --build-config=gcp/cloud-run/cloudbuild-branch-validation.yaml \
  --substitutions=_DEPLOY_ENV=dev

# 生产环境触发器 (仅master分支)
gcloud builds triggers create github \
  --repo-name=your-repo \
  --repo-owner=your-org \
  --branch-pattern="^master$" \
  --build-config=gcp/cloud-run/cloudbuild-branch-validation.yaml \
  --substitutions=_DEPLOY_ENV=prd
```

## 镜像标签规范

为了支持分支校验，建议采用以下镜像标签规范：

```
格式: {branch}-{commit_sha}
示例:
- master-a1b2c3d4    ✅ 生产环境允许
- develop-e5f6g7h8   ❌ 生产环境拒绝
- feature-xyz-i9j0k1 ❌ 生产环境拒绝
- hotfix-abc-l2m3n4  ❌ 生产环境拒绝 (除非使用--skip-validation)
```

## 安全最佳实践

1. **权限控制**
   - 生产环境部署权限仅授予特定人员
   - 使用不同的服务账号用于不同环境

2. **审计日志**
   - 所有部署操作都会记录在Cloud Logging中
   - 定期审查部署日志

3. **紧急处理**
   - 紧急情况可使用`--skip-validation`参数
   - 但需要在事后补充正规流程

4. **监控告警**
   - 设置生产环境部署告警
   - 监控非master分支的部署尝试

## 故障排除

### 常见错误

1. **分支校验失败**
```
❌ 校验失败: 生产环境只能部署来自 master 分支的镜像
当前镜像标签: develop-abc123
要求分支前缀: master
```
**解决方案**: 确保从master分支构建镜像

2. **镜像标签格式错误**
```
❌ 错误: 生产环境镜像标签必须以master开头!
当前标签: latest
```
**解决方案**: 使用规范的标签格式 `master-{commit_sha}`

3. **权限不足**
```
ERROR: (gcloud.run.jobs.deploy) User does not have permission to access service
```
**解决方案**: 检查服务账号权限配置

## 总结

选择合适的方案取决于你的具体需求：

- **快速实施**: 使用方案1的独立校验脚本
- **用户友好**: 使用方案2的增强部署脚本  
- **GitLab用户**: 使用方案3的CI/CD集成
- **GCP原生**: 使用方案4的Cloud Build集成

所有方案都能有效防止非master分支的镜像部署到生产环境，提高系统安全性。