# GCP Cloud Run Binary Authorization 镜像签名验证完整指南

## 背景需求

由于 GCP Cloud Run 的 Violation 要求，必须启用 Binary Authorization 来确保只有经过验证的镜像才能部署。本文档详细说明如何配置 Binary Authorization，包括：

- 创建 attestor (attestor-cloud-run) 和 Container Analysis Note (note-cloud-run)
- 生成和配置 PKIX/OpenPGP 公钥
- 非 Cloud Build 环境下的镜像签名流程
- 完整的部署验证流程

## 核心概念

### Binary Authorization 组件

- **Note**: Container Analysis 中的元数据条目，定义签名规范
- **Attestor**: 验证器，关联到 Note，包含用于验证签名的公钥
- **Attestation**: 对特定镜像 digest 的签名证明
- **Policy**: 定义哪些 attestor 的签名是可信的

### 签名时机选择

**重要原则**: 必须以 GAR 中的 Digest 为准签名，因为 Binary Authorization 验证的是最终仓库中的镜像 digest。

## 方案一：使用 Cloud KMS (推荐)

### 1. 创建或使用现有的 KMS 密钥环和签名密钥

#### 选项 A: 使用 Shared 工程中的现有 KMS 密钥 (推荐)

```bash
# 设置 Shared 工程的变量
SHARED_PROJECT_ID="your-shared-project-id"
KMS_LOCATION="global"  # 或者 "us-central1" 等具体区域
KEYRING_NAME="shared-binauthz-keyring"  # 现有密钥环名称
KEY_NAME="shared-attestor-signing-key"   # 现有密钥名称

# 列出现有的密钥环 (确认资源存在)
gcloud kms keyrings list --location=$KMS_LOCATION --project=$SHARED_PROJECT_ID

# 列出密钥环中的密钥
gcloud kms keys list --keyring=$KEYRING_NAME --location=$KMS_LOCATION --project=$SHARED_PROJECT_ID

# 检查密钥详情 (确认是签名密钥)
gcloud kms keys describe $KEY_NAME \
  --keyring=$KEYRING_NAME \
  --location=$KMS_LOCATION \
  --project=$SHARED_PROJECT_ID

# 确保当前项目的服务账号有使用权限
gcloud kms keys add-iam-policy-binding $KEY_NAME \
  --keyring=$KEYRING_NAME \
  --location=$KMS_LOCATION \
  --project=$SHARED_PROJECT_ID \
  --member="serviceAccount:$PROJECT_ID@appspot.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

#### 选项 B: 创建新的 KMS 密钥环和签名密钥

```bash
# 创建密钥环
gcloud kms keyrings create binauthz-keyring \
  --location=global \
  --project=$PROJECT_ID

# 创建非对称签名密钥
gcloud kms keys create attestor-signing-key \
  --location=global \
  --keyring=binauthz-keyring \
  --purpose=asymmetric-signing \
  --default-algorithm=rsa-sign-pkcs1-2048-sha256 \
  --project=$PROJECT_ID
```

### 2. 创建 Container Analysis Note

```bash
# 方法1: 使用 REST API 创建 Note (推荐)
cat > note.json << EOF
{
  "name": "projects/$PROJECT_ID/notes/note-cloud-run",
  "attestationAuthority": {
    "hint": {
      "humanReadableName": "Cloud Run Attestor Note"
    }
  }
}
EOF

curl -X POST \
  "https://containeranalysis.googleapis.com/v1/projects/$PROJECT_ID/notes?noteId=note-cloud-run" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d @note.json

# 方法2: 直接在创建 attestor 时自动创建 note
# (在下一步创建 attestor 时会自动创建对应的 note)

# List all attestors (which will show their associated notes)
gcloud container binauthz attestors list --project=$PROJECT_ID

# Get details of specific attestor (shows the note it uses)
gcloud container binauthz attestors describe attestor-cloud-run --project=$PROJECT_ID


```

### 3. 创建 Attestor 并添加 KMS 公钥

```bash
# 创建 attestor
gcloud container binauthz attestors create attestor-cloud-run \
  --attestation-authority-note=note-cloud-run \
  --attestation-authority-note-project=$PROJECT_ID \
  --project=$PROJECT_ID

# 添加 KMS 公钥到 attestor
# 如果使用 Shared 工程的密钥:
gcloud container binauthz attestors public-keys add \
  --attestor=attestor-cloud-run \
  --keyversion=projects/$SHARED_PROJECT_ID/locations/$KMS_LOCATION/keyRings/$KEYRING_NAME/cryptoKeys/$KEY_NAME/cryptoKeyVersions/1 \
  --project=$PROJECT_ID

# 如果使用当前项目的密钥:
# gcloud container binauthz attestors public-keys add \
#   --attestor=attestor-cloud-run \
#   --keyversion=projects/$PROJECT_ID/locations/global/keyRings/binauthz-keyring/cryptoKeys/attestor-signing-key/cryptoKeyVersions/1 \
#   --project=$PROJECT_ID
```

### 4. 镜像签名流程

```bash
#!/bin/bash

# 设置变量
PROJECT_ID="your-project-id"
REGION="us-central1"
REPO_NAME="your-repo"
IMAGE_NAME="your-app"
IMAGE_TAG="latest"

# 1. 获取 GAR 镜像的 digest
IMAGE_DIGEST=$(gcloud container images describe \
  $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$IMAGE_TAG \
  --format='value(image_summary.digest)')

echo "镜像 Digest: $IMAGE_DIGEST"

# 2. 创建签名 attestation
# 如果使用 Shared 工程的密钥:
gcloud container binauthz attestations create \
  --artifact-url=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME@$IMAGE_DIGEST \
  --attestor=attestor-cloud-run \
  --keyversion=projects/$SHARED_PROJECT_ID/locations/$KMS_LOCATION/keyRings/$KEYRING_NAME/cryptoKeys/$KEY_NAME/cryptoKeyVersions/1 \
  --project=$PROJECT_ID

# 如果使用当前项目的密钥:
# gcloud container binauthz attestations create \
#   --artifact-url=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME@$IMAGE_DIGEST \
#   --attestor=attestor-cloud-run \
#   --keyversion=projects/$PROJECT_ID/locations/global/keyRings/binauthz-keyring/cryptoKeys/attestor-signing-key/cryptoKeyVersions/1 \
#   --project=$PROJECT_ID

echo "签名完成"
```

## 方案二：使用 PKIX 公钥

### 1. 生成 PKIX 密钥对

```bash
# 使用 OpenSSL 生成 RSA 密钥对
openssl genpkey -algorithm RSA -out private-key.pem -pkeyopt rsa_keygen_bits:2048
openssl rsa -pubout -in private-key.pem -out public-key.pem

# 或使用 cosign 生成
cosign generate-key-pair
```

### 2. 创建 Attestor 并添加 PKIX 公钥

```bash
# 创建 attestor
gcloud container binauthz attestors create attestor-cloud-run \
  --attestation-authority-note=note-cloud-run \
  --attestation-authority-note-project=$PROJECT_ID \
  --project=$PROJECT_ID

# 添加 PKIX 公钥
gcloud container binauthz attestors public-keys add \
  --attestor=attestor-cloud-run \
  --pkix-public-key-file=public-key.pem \
  --pkix-public-key-algorithm=rsa-pss-2048-sha256 \
  --project=$PROJECT_ID
```

### 3. 使用私钥签名

```bash
# 使用 cosign 签名
cosign sign --key cosign.key \
  $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME@$IMAGE_DIGEST

# 或手动创建 attestation
gcloud container binauthz attestations create \
  --artifact-url=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME@$IMAGE_DIGEST \
  --attestor=attestor-cloud-run \
  --signature-file=signature.sig \
  --public-key-file=public-key.pem \
  --project=$PROJECT_ID
```

## 方案三：使用 OpenPGP 公钥

### 1. 生成 GPG 密钥对

```bash
# 生成 GPG 密钥
gpg --quick-generate-key "attestor-cloud-run <admin@example.com>" rsa2048 sign 1y

# 导出公钥
gpg --armor --export admin@example.com > public.gpg

# 导出私钥（安全存储）
gpg --armor --export-secret-keys admin@example.com > private.gpg
```

### 2. 添加 OpenPGP 公钥到 Attestor

```bash
# 添加 GPG 公钥
gcloud container binauthz attestors public-keys add \
  --attestor=attestor-cloud-run \
  --pgp-public-key-file=public.gpg \
  --project=$PROJECT_ID
```

### 3. 使用 GPG 签名

```bash
# 获取 GPG 密钥指纹
GPG_FINGERPRINT=$(gpg --with-colons --fingerprint admin@example.com | grep fpr | head -n1 | cut -d: -f10)

# 创建签名
echo "signature content" | gpg --armor --detach-sign --local-user $GPG_FINGERPRINT > signature.pgp

# 创建 attestation
gcloud container binauthz attestations create \
  --artifact-url=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME@$IMAGE_DIGEST \
  --attestor=attestor-cloud-run \
  --pgp-key-fingerprint=$GPG_FINGERPRINT \
  --signature-file=signature.pgp \
  --project=$PROJECT_ID
```

## Binary Authorization 策略配置

### 1. 导出当前策略

```bash
gcloud binauthz policy export > policy.yaml
```

### 2. 配置策略文件

```yaml
# policy.yaml
admissionWhitelistPatterns:
  - namePattern: "gcr.io/google_containers/*"
  - namePattern: "gcr.io/google-containers/*"
  - namePattern: "k8s.gcr.io/*"
  - namePattern: "gke.gcr.io/*"

defaultAdmissionRule:
  evaluationMode: REQUIRE_ATTESTATION
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  requireAttestationsBy:
    - projects/PROJECT_ID/attestors/attestor-cloud-run

clusterAdmissionRules: {}
kubernetesNamespaceAdmissionRules: {}
kubernetesServiceAccountAdmissionRules: {}
istioServiceIdentityAdmissionRules: {}

name: projects/PROJECT_ID/policy
updateTime: "2024-01-01T00:00:00.000000Z"
```

### 3. 应用策略

```bash
gcloud binauthz policy import policy.yaml
```

## CI/CD 集成示例

### GitLab CI 示例

```yaml
# .gitlab-ci.yml
stages:
  - build
  - sign
  - deploy

variables:
  PROJECT_ID: "your-project-id"
  REGION: "us-central1"
  REPO_NAME: "your-repo"
  IMAGE_NAME: "your-app"

build_image:
  stage: build
  script:
    - docker build -t $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$CI_COMMIT_SHA .
    - docker push $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$CI_COMMIT_SHA

sign_image:
  stage: sign
  script:
    - |
      # 获取镜像 digest
      IMAGE_DIGEST=$(gcloud container images describe \
        $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$CI_COMMIT_SHA \
        --format='value(image_summary.digest)')

      # 创建签名
      gcloud container binauthz attestations create \
        --artifact-url=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME@$IMAGE_DIGEST \
        --attestor=attestor-cloud-run \
        --keyversion=projects/$PROJECT_ID/locations/global/keyRings/binauthz-keyring/cryptoKeys/attestor-signing-key/cryptoKeyVersions/1 \
        --project=$PROJECT_ID

deploy_cloud_run:
  stage: deploy
  script:
    - |
      gcloud run deploy $IMAGE_NAME \
        --image=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$CI_COMMIT_SHA \
        --region=$REGION \
        --platform=managed \
        --project=$PROJECT_ID
```

### GitHub Actions 示例

```yaml
# .github/workflows/deploy.yml
name: Build, Sign and Deploy

on:
  push:
    branches: [main]

env:
  PROJECT_ID: your-project-id
  REGION: us-central1
  REPO_NAME: your-repo
  IMAGE_NAME: your-app

jobs:
  build-sign-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - id: "auth"
        uses: "google-github-actions/auth@v1"
        with:
          credentials_json: "${{ secrets.GCP_SA_KEY }}"

      - name: "Set up Cloud SDK"
        uses: "google-github-actions/setup-gcloud@v1"

      - name: "Build and Push Image"
        run: |
          docker build -t $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$GITHUB_SHA .
          docker push $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$GITHUB_SHA

      - name: "Sign Image"
        run: |
          IMAGE_DIGEST=$(gcloud container images describe \
            $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$GITHUB_SHA \
            --format='value(image_summary.digest)')

          gcloud container binauthz attestations create \
            --artifact-url=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME@$IMAGE_DIGEST \
            --attestor=attestor-cloud-run \
            --keyversion=projects/$PROJECT_ID/locations/global/keyRings/binauthz-keyring/cryptoKeys/attestor-signing-key/cryptoKeyVersions/1 \
            --project=$PROJECT_ID

      - name: "Deploy to Cloud Run"
        run: |
          gcloud run deploy $IMAGE_NAME \
            --image=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$GITHUB_SHA \
            --region=$REGION \
            --platform=managed \
            --project=$PROJECT_ID
```

## 验证和故障排查

### 1. 验证 Attestation

```bash
# 列出 attestations
gcloud container binauthz attestations list \
  --attestor=attestor-cloud-run \
  --project=$PROJECT_ID

# 验证特定镜像的签名
gcloud container binauthz attestations list \
  --attestor=attestor-cloud-run \
  --artifact-url=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME@$IMAGE_DIGEST \
  --project=$PROJECT_ID
```

### 2. 测试策略

```bash
# 模拟部署验证
gcloud binauthz policy evaluate \
  --image-url=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME@$IMAGE_DIGEST \
  --project=$PROJECT_ID
```

### 3. 常见问题排查

**问题 1**: 部署时提示 "Image is not attested"

```bash
# 检查是否有对应的 attestation
gcloud container binauthz attestations list --attestor=attestor-cloud-run

# 确认镜像 digest 是否匹配
gcloud container images describe IMAGE_URL --format='value(image_summary.digest)'
```

**问题 2**: 策略配置错误

```bash
# 检查当前策略
gcloud binauthz policy export

# 验证策略语法
gcloud binauthz policy import policy.yaml --dry-run
```

**问题 3**: 密钥权限问题

```bash
# 检查 KMS 密钥权限
gcloud kms keys get-iam-policy attestor-signing-key \
  --keyring=binauthz-keyring \
  --location=global
```

## 最佳实践

### 1. 安全建议

- 使用 Cloud KMS 管理私钥，避免在 CI/CD 中存储私钥文件
- **推荐使用 Shared 工程的 KMS 密钥** - 集中管理，降低成本和复杂度
- 定期轮换签名密钥
- 为不同环境使用不同的 attestor
- 启用 Cloud Audit Logs 监控签名活动

#### 使用 Shared KMS 密钥的优势

- **成本效益**: 避免在每个项目中重复创建 KMS 资源
- **集中管理**: 统一的密钥管理和轮换策略
- **权限控制**: 通过 IAM 精确控制哪些项目可以使用密钥
- **审计追踪**: 集中的密钥使用日志

#### 权限配置要点

```bash
# 为使用 KMS 密钥的项目服务账号授权
gcloud kms keys add-iam-policy-binding $KEY_NAME \
  --keyring=$KEYRING_NAME \
  --location=$KMS_LOCATION \
  --project=$SHARED_PROJECT_ID \
  --member="serviceAccount:$PROJECT_ID@appspot.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"

# 如果使用 Cloud Build，还需要为 Cloud Build 服务账号授权
gcloud kms keys add-iam-policy-binding $KEY_NAME \
  --keyring=$KEYRING_NAME \
  --location=$KMS_LOCATION \
  --project=$SHARED_PROJECT_ID \
  --member="serviceAccount:$PROJECT_NUMBER@cloudbuild.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

### 2. 运维建议

- 在 DRYRUN_AUDIT_LOG_ONLY 模式下测试策略
- 为系统镜像添加白名单规则
- 建立自动化的签名流程
- 监控 Binary Authorization 的拒绝日志

### 3. 性能优化

- 批量签名多个镜像版本
- 缓存镜像 digest 避免重复查询
- 使用并行签名提高 CI/CD 效率

## 总结

本文档提供了三种 Binary Authorization 配置方案：

1. **Cloud KMS** (推荐) - 最安全，无需管理私钥文件
2. **PKIX 公钥** - 灵活性高，支持自定义密钥管理
3. **OpenPGP 公钥** - 兼容 GPG 生态，适合已有 GPG 流程的团队

关键要点：

- 必须对 GAR 中的最终 digest 进行签名
- 策略配置必须使用 ENFORCED_BLOCK_AND_AUDIT_LOG 模式
- CI/CD 流程需要包含：构建 → 推送 → 获取 digest → 签名 → 部署
- 建议使用 Cloud KMS 方案以获得最佳的安全性和可维护性
