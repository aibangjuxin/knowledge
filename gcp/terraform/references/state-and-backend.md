# State / Backend / Secret 管理

> 本 doc 讲三件最容易出错的事:GCS backend 配置 / state 文件的协作 / secret 怎么
> 传递到 TF。这三件错了成本极高(损坏 state = 资源泄漏 / 误删;secret 泄漏 = 安全事故),
> 必须**用纪律 + 工具** 强制约束。

---

## 1. 三件事的硬规则

| 主题 | 硬规则 |
|---|---|
| Backend 块 | **只**在 `envs/<region>/<project>/backend.tf` 写,其他任何 .tf 都不许 |
| State 文件 | **永远不**手编辑 / `terraform state pull/push` / 复制粘贴 |
| Secret | **绝对不**进 git / `*.tfvars` / 注释 / 文档(就算 base64 也不行) |
| State 加密 | **CMEK + 90 天轮换**(2025 GCP 推荐做法,见 §2.1) |

违反任何一条 → 灾难。下面解释为什么 + 怎么做。

---

## 2. GCS Backend

### 2.1 一次性初始化(在第一个 env 之前)

```bash
# scripts/init-backend.sh
PROJECT_TF_STATE="aibang-tfstate"   # 专门存 state 的 project(跟业务 project 分开)
REGION="us-central1"
KEYRING="tfstate-keyring"
KEY="tfstate-key"

# 1. 建 KMS keyring + key (CMEK for state bucket)
gcloud kms keyrings create "$KEYRING" \
    --project="$PROJECT_TF_STATE" --location="$REGION"
gcloud kms keys create "$KEY" \
    --project="$PROJECT_TF_STATE" --location="$REGION" \
    --keyring="$KEYRING" --purpose=encryption \
    --rotation-period=7776000s   # 90 天(terraform-example-foundation 默认)
gcloud kms keys add-iam-policy-binding "$KEY" \
    --project="$PROJECT_TF_STATE" --location="$REGION" \
    --keyring="$KEYRING" \
    --member="serviceAccount:service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"

BUCKETS=(
  "tfstate-dev-project-a"
  "tfstate-dev-project-b"
  "tfstate-staging-project-a"
  "tfstate-staging-project-b"
  "tfstate-prod-project-a"
  "tfstate-prod-project-b"
)

for BUCKET in "${BUCKETS[@]}"; do
  gsutil mb -p "$PROJECT_TF_STATE" -l "$REGION" "gs://${BUCKET}"
  # 强制 bucket 私有 + 版本化(rollback 用)
  gsutil iam ch allUsers:objectViewer "gs://${BUCKET}" 2>/dev/null || true  # 撤销公开
  gsutil versioning set on "gs://${BUCKET}"
  # 启用 object-level lock(必须,否则多 apply 并行会损坏 state)
  gsutil retention set default 30d "gs://${BUCKET}"
  # 强制 uniform bucket-level access(防止 accidental ACL)
  gsutil uniformbucketlevelaccess set on "gs://${BUCKET}"
  # ★ CMEK 加密 — terraform-example-foundation 默认做法
  gsutil kms encryption -k \
      "projects/${PROJECT_TF_STATE}/locations/${REGION}/keyRings/${KEYRING}/cryptoKeys/${KEY}" \
      "gs://${BUCKET}"
done

# 给 Terraform CI SA 写权限
TF_CI_SA="terraform-ci@aibang-tfstate.iam.gserviceaccount.com"
for BUCKET in "${BUCKETS[@]}"; do
  gsutil iam ch "serviceAccount:${TF_CI_SA}:objectAdmin" "gs://${BUCKET}"
done
```

**关键点:**
- **State bucket 单独 project** — 跟业务 project 分开,业务 project 删了 state 还在
- **Versioning 必开** — state 损坏了能回滚
- **Uniform bucket-level access** — 防止 IAM 错配
- **CMEK + 90 天轮换** — 2025 GCP 推荐做法(`terraform-example-foundation` v6.x 默认)
- **CI SA 授权** — 不能给"allUsers" / "allAuthenticatedUsers" 任何权限

### 2.2 在 env 里使用

```hcl
# envs/<region>/<project>/backend.tf
terraform {
  backend "gcs" {
    bucket = "tfstate-${var.env}-${var.project_id_short}-uscentral1"
    prefix = "envs/${var.region}/${var.project_id_short}"
  }
}
```

### 2.3 State 命名规则(确定 state 路径不冲突)

| env | project | bucket | prefix |
|---|---|---|---|
| dev | project-a | `tfstate-dev-project-a` | `envs/dev/project-a` |
| prod | project-a | `tfstate-prod-project-a` | `envs/prod/project-a` |
| dev | project-b | `tfstate-dev-project-b` | `envs/dev/project-b` |

**bucket 跟 prefix 都能避免冲突** — 两个 dev/project-a 不会撞到 prod/project-a。

---

## 3. State Lock

GCS backend 自带 **object-level locking**:对 `default.tfstate` 写入时会**自动加 lock**,其他进程看到 lock 立即 fail。

### 3.1 强制的几件事

- **永远不**手 `terraform state pull/push` — 走 GCS 一致性
- **永远不**编辑 `*.tfstate` JSON(可能破坏 lock)
- **`terraform force-unlock` 是最后手段** — 99% 情况是前一个 `terraform apply` 异常退出,等几分钟会自动释放;只在 CI 异常中断 / lock 卡住时用,使用后**必须**审计

### 3.2 CI 并发保护

GitHub Actions 用 `concurrency: group` 避免同一 env 并发 apply:

```yaml
concurrency:
  group: tf-${{ matrix.target }}
  cancel-in-progress: false
```

意思是:同一 env/project 的两个 PR 谁先到谁跑,后到的 cancel(但 plan 不 cancel,只 cancel apply)。

---

## 4. Secret 管理(最易出错)

### 4.1 三种方式 + 推荐度

| 方式 | 推荐度 | 说明 |
|---|---|---|
| **GCP Secret Manager + `data` source** | ✅ 强推荐 | Secret 存 SM,TF 用 `data` 读,自动注入 |
| **Env var `TF_VAR_xxx`** | ⚠️ 谨慎 | 易泄漏到 CI 日志;只用于完全无 secret 的 case |
| **`terraform.tfvars` 写死** | ❌ 严禁 | 一旦 commit,secret 进 git history,`git filter-branch` 都难清干净 |

### 4.2 Secret Manager 标准用法

```hcl
# envs/prod/project-a/main.tf

# 1. 读取 secret
data "google_secret_manager_secret_version" "db_password" {
  project = local.project_id
  secret  = "prod-db-password"
  version = "latest"   # 或显式 "1" / "2" 锁版本
}

# 2. 传递给 module
module "gke_app" {
  source     = "../../../modules/gke-app"
  # ...
  db_password = data.google_secret_manager_secret_version.db_password.secret_data
  # .secret_data 拿到的是实际值,会进 TF state
}
```

### 4.3 State 里会看到 secret — 必须保护 state 文件

**`data.google_secret_manager_secret_version.xxx.secret_data` 会进 state。** 这意味着:
- State file(`gs://tfstate-prod-.../default.tfstate`)**包含明文 secret**
- **泄露 state ≈ 泄露 secret**

**强制措施:**
- **state bucket 强制 IAM** — 只有 terraform-ci SA + on-call SRE 能读
- **state file 加密** — 启用 Customer-Managed Encryption Key(CMEK)
- **SRE 拿到 state 后** — 不能贴到 issue / 邮件 / Slack

### 4.4 完整流程(给新人)

```
1. SA / SRE 在 Secret Manager 创建 secret(prod-db-password)
2. 首次手动 put version 1
3. CI / env 引用 data "google_secret_manager_secret_version"
4. App 部署后,SA 通过 Workload Identity 拿 secret(用 Secret Manager API,不走 TF)
5. Secret 轮换时:SM 创建新 version → TF plan 改 version → apply → app 重启读新 value
```

**TF 不应该"管" secret 的轮换** — 那是 Secret Manager + 应用的活,不是 TF 的活。

### 4.5 常见误用:把 secret 写 module 变量

```hcl
# 错误 ❌
module "gke_app" {
  source      = "../../../modules/gke-app"
  db_password = "my-secret-password"   # 硬编码!
}

# 错误 ❌
module "gke_app" {
  source      = "../../../modules/gke-app"
  db_password = var.db_password        # 来自 *.tfvars
}

# 正确 ✅
module "gke_app" {
  source      = "../../../modules/gke-app"
  db_password = data.google_secret_manager_secret_version.db_password.secret_data
}
```

---

## 5. State Drift 检测

### 5.1 什么是 drift

"代码说有这个资源,但实际 GCP 已经被某人手改了 / 删了" — TF 下次 plan 会显示出来。

### 5.2 检测方法

- **CI 跑 plan**(没有 PR 也跑)→ drift 自然出现
- **Cloud Asset Inventory + drift detection**(企业级,量大时用)
- **`terraform plan -detailed-exitcode`** → `2` 表示有 drift,CI 报警

### 5.3 处理 drift

| Drift 类型 | 处理 |
|---|---|
| 配置漂移(某人手改了 console) | `terraform apply` 让 TF 重新对齐 |
| 资源被删(某人手删) | `terraform apply` 重建;或者 `terraform state rm` 把 state 里的引用删掉 |
| 资源被 replace | 接受漂移 / 改代码 / 沟通 |

**drift 不一定是坏事** — 应急时手改 console 合理,但事后必须 apply 让代码跟现实对齐。

---

## 6. 灾难恢复

| 场景 | 恢复方式 |
|---|---|
| State 损坏 | `gsutil versioning set on` 后,从 GCS 下载旧 version 恢复 |
| Bucket 误删 | bucket 软删 30 天,联系 GCP support 恢复(workspace 升级账户) |
| 多人 lock 卡死 | `terraform force-unlock <lock-id>`(慎用,审计) |
| Secret 泄漏 | **立即**在 SM 创建新 version + rotate + 检查 git history 是否有 |
| `terraform.tfstate` 进了 git | **立刻**从 history 清(`bfg` / `git filter-repo`),并轮换所有 secret |
