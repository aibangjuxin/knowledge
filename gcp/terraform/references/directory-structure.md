# 目录结构 — 详细分解

> 本 doc 是 `gcp/terraform/README.md` 的**细颗粒度补充**。README 给出"看什么",这里
> 解释"为什么这样分 / 每层的 trade-off"。

---

## 1. 三层核心结构

| 层 | 位置 | 内容 | 什么时候编辑 |
|---|---|---|---|
| **Module 层** | `modules/<name>/` | 一个 GCP 资源或一组紧密相关资源的封装,无 `resource` 之外的任何 GCP 状态 | 几乎不动(改了 blast radius 大) |
| **Env 层** | `envs/<env>/<project>/` | 一个具体部署的 entrypoint。`main.tf` 全是 `module {}` 引用 + 变量赋值 | 高频改动 — 新 env、新 project、加资源 |
| **Repository 层** | repo 根目录 | repo 自身配置:版本、lint、CI 触发规则 | 几乎不动 |

**模块化原则的真正威力:** Module 改 1 次 → env 引用自动应用。Env 想加新资源 → 加一个 `module {}` 块,不动 module。

---

## 2. Module 层细节

### 2.1 module 内部 Standard Module Structure

```
modules/<name>/
├── README.md                  # 必写!用法 + 变量清单 + 示例
├── main.tf                    # 主资源定义
├── variables.tf               # input variables(必须全)
├── outputs.tf                 # output values(必须全)
├── versions.tf                # terraform { required_version + required_providers }
├── providers.tf               # (可选)provider 配置 — 不推荐
├── <resource-1>.tf            # (可选)主资源超过 200 行就拆
├── <resource-2>.tf            # (可选)按资源类型拆
├── examples/
│   └── complete/
│       ├── main.tf            # 一个完整 module 调用示例
│       ├── variables.tf
│       └── outputs.tf
└── tests/
    └── <name>_test.go         # (可选)Terratest 集成测试
```

### 2.2 何时拆文件 vs 保持单文件

| 行数 | 推荐 |
|---|---|
| < 200 | 单 `main.tf` 即可 |
| 200-500 | 按资源类型拆: `cluster.tf` / `node_pool.tf` / `iam.tf` |
| > 500 | **拆成 submodule** — `modules/gke/cluster/` `modules/gke/node-pool/` `modules/gke/iam/` |

### 2.3 `versions.tf` 的标准写法

```hcl
# modules/<name>/versions.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0, < 7.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0.0, < 7.0.0"
    }
  }
}
```

**约束版本号(用 `>= x, < y`)而不是钉死 `= x.y.z`** — 给 env 层留升级空间。

### 2.4 `variables.tf` 命名约定

- **所有 variable 必须有 `description`** — Terraform registry / docs 工具靠这个生成文档
- **必填项无 `default`**,可选项有 `default`
- **复杂规则用 `validation` 块** — 错误在 plan 阶段暴露,不是 apply 阶段

```hcl
variable "cluster_name" {
  description = "GKE cluster name. Must be unique within the project/region."
  type        = string

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,38}$", var.cluster_name))
    error_message = "Cluster name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, max 39 chars."
  }
}
```

### 2.5 `outputs.tf` 命名约定

**只输出下游需要的值**,不要把内部 resource 的所有属性都 output。

```hcl
# 好的 outputs
output "cluster_id" {
  description = "GKE cluster ID for downstream modules (e.g., for K8s provider config)"
  value       = google_container_cluster.primary.id
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint (host:port) for kubectl access"
  value       = google_container_cluster.primary.endpoint
  sensitive   = false  # endpoint 公开,非 secret
}

# 坏的 outputs
output "cluster_self_link" {
  description = "internal self link"
  value       = google_container_cluster.primary.self_link
  # 下游几乎不会用,污染 output
}
```

---

## 3. Env 层细节

### 3.1 env 内部完整文件清单

```
envs/<env>/<project>/
├── backend.tf              # 唯一允许写 backend 块的地方
├── providers.tf            # provider "google" / "google-beta" 配置
├── versions.tf             # terraform { required_version + required_providers }
├── main.tf                 # 全部 module {} 引用,无 resource {}
├── variables.tf            # env 级别 variables
├── locals.tf               # env 级别 locals(标签/通用变量)
├── outputs.tf              # env 级别 outputs(可选,用于跨 env 引用)
├── terraform.tfvars        # 实际变量值(可 .gitignore 化,看 §3.4)
└── README.md               # 描述这个 env 是干嘛的 + 怎么 apply
```

### 3.2 `backend.tf` 模板

```hcl
# envs/<env>/<project>/backend.tf
terraform {
  backend "gcs" {
    bucket = "tfstate-${var.env}-${var.project_id_short}-uscentral1"
    prefix = "envs/${var.env}/${var.project_id_short}"
  }
}
```

**bucket 命名约定:** `tfstate-<env>-<project>-<region>`
**prefix 约定:** `envs/<env>/<project>`(对应到目录路径)

### 3.3 `providers.tf` 模板

```hcl
# envs/<env>/<project>/providers.tf
provider "google" {
  project = local.project_id
  region  = local.region
}

provider "google-beta" {
  project = local.project_id
  region  = local.region
}
```

**注意:** `project` / `region` 来自 `local.tf`,不直接来自 `var`,这样所有 module 引用时不需要重复传。

### 3.4 `terraform.tfvars` 跟 secret

**三类配置 + 处理方式:**

| 类型 | 例子 | 处理 |
|---|---|---|
| **公开元数据** | `project_id` / `region` / `cluster_name` | 提交 git |
| **环境相关** | `node_count` / `min_replicas` / `domain_name` | 提交 git(per env 独立) |
| **Secret** | `db_password` / `tls_private_key` / `service_account_key_json` | **绝对不进 git**,用 Secret Manager |

**处理 secret 的标准做法:**

```hcl
# envs/<env>/<project>/main.tf
data "google_secret_manager_secret_version" "db_password" {
  project = local.project_id
  secret  = "db-password"
  version = "latest"
}

module "gke" {
  # ...
  database_password = data.google_secret_manager_secret_version.db_password.secret_data
}
```

**绝对不**用 `TF_VAR_db_password` env var 传递(易泄漏到 CI 日志)。

### 3.5 完整 env 示例

参见 `examples/envs/dev-project-a/` 目录,包含:
- `backend.tf` / `providers.tf` / `main.tf` / `variables.tf` / `locals.tf` / `outputs.tf`

---

## 4. Repository 层细节

### 4.1 根目录必有的 4 个文件

| 文件 | 作用 | 来源 |
|---|---|---|
| `.gitignore` | 排除 `.terraform/` / `*.tfstate*` / `*.tfvars`(带 secret 的) | `templates/repo/.gitignore` |
| `.terraform-version` | 锁 TF 版本(用 tfenv) | `1.5.0` 之类 |
| `.tflint.hcl` | tflint 配置 | `templates/repo/.tflint.hcl` |
| `.pre-commit-config.yaml` | 跑 fmt/validate/tflint/tfsec | `templates/repo/.pre-commit-config.yaml` |

### 4.2 `.gitignore` 标准内容

```gitignore
# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfstate.backup
crash.log
crash.*.log

# tfvars(只 ignore 包含 secret 的那一个;非敏感的用 !common.tfvars 显式提交)
*.tfvars
!*.tfvars.example
!common.tfvars

# OS / IDE
.DS_Store
.idea/
.vscode/
```

### 4.3 `.terraform-version` 跟多版本兼容

- 根目录 `.terraform-version` 用 `tfenv` 锁 TF 版本
- 如果不同 env 需要不同 TF 版本(罕见),**用 `tfenv` 在 env 目录单独指定**,不要在 `versions.tf` 里钉死

### 4.4 `infrastructure-modules/` 跟 `modules/` 的区别

| 层 | 内容 | 复用范围 |
|---|---|---|
| `modules/` | 项目特定,经常改 | 仅本 repo |
| `infrastructure-modules/` | 跨项目共享,极少改 | 多个 terraform repo,可能提到 public registry |

**判断: 改 module 一次会同时影响本 repo 多个 env → `modules/`。改 module 一次会同时影响多个 terraform repo(跨项目) → `infrastructure-modules/`。**

如果只有一个 repo,**可以不要 `infrastructure-modules/`,全部放 `modules/`**。这是渐进式 — 等到第 2 个 repo 出现时再拆。

---

## 5. CI/CD 怎么对接

### 5.1 PR 触发的粒度

```yaml
# .github/workflows/terraform-plan.yml
on:
  pull_request:
    paths:
      - 'envs/**'
      - 'modules/**'
```

**触发矩阵策略:**

| PR 改了什么 | 触发哪些 plan |
|---|---|
| `modules/gke/**` | **所有 env × 所有 project** 的 plan(blast radius 大) |
| `modules/gke/variables.tf` | 同上 — module interface 变 → 所有 caller 都要 plan |
| `envs/dev/project-a/main.tf` | **只** dev/project-a 的 plan |
| `envs/prod/project-b/` | **只** prod/project-b 的 plan |
| `templates/repo/.gitignore` | **不触发** plan(repo 级文件,不影响 TF 行为) |

### 5.2 GitHub Actions matrix 写法

```yaml
strategy:
  matrix:
    target: |
      dev/project-a
      dev/project-b
      staging/project-a
      staging/project-b
      prod/project-a
      prod/project-b
```

**注意:** Matrix 列项**手维护**。等 env 数量 > 20,改用 `find envs -mindepth 2 -maxdepth 2 -type d` 动态生成。

### 5.3 Apply 永远不在 PR 阶段

- PR 阶段:**只 plan**(不 apply)
- Merge 到 main 后:**自动 apply 到 dev/staging**,prod 由 manual approval 触发
- prod apply 可用 GitHub `environment` + required reviewers / Atlantis

---

## 6. 大规模演进的 3 个里程碑

| 阶段 | 标志 | 建议 |
|---|---|---|
| **Stage 1: < 10 env** | 纯 TF + matrix 维护 | **当前最佳** — 不动 |
| **Stage 2: 10-30 env** | Matrix 变长,backend.tf 重复多 | 考虑 Terragrunt(`references/terragrunt-decision.md`) |
| **Stage 3: > 30 env 或多 team** | 需要 RBAC 分工 / 自服务 | Terragrunt + Atlantis + 内部 module registry |

**绝大多数团队**停在 Stage 1 或 Stage 2 — 不要提前做 Stage 3 的事。
