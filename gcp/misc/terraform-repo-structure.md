# Terraform GCP 多环境仓库 — 目录结构最佳实践

> 一句话:用 **`monorepo` + `envs/ + modules/` + `infrastructure-modules/`(可选共享库)**
> 的分层结构。一个仓库管理多个 GCP 工程(每个工程可能多个 env:dev/staging/prod),
> `envs/<env>/<project>/` 里只放**调 module 的 entrypoint**(`main.tf` 几乎都是 module
> 引用),`modules/<resource>/` 里写**可复用**的资源定义。这样加新 env 不用改 module,
> 改 module 不影响已有 env。

---

## 0. 为什么不是其他 layout

我先把你可能会考虑的 4 种 layout 摆出来,排除 3 个,留下 1 个。

| Layout | 例子 | 适合 | 不适合你 |
|---|---|---|---|
| **A. 一 repo 一 env** | `terraform-prd/`, `terraform-dev/` 各一个 repo | 团队极小 / 1 个 env | 共享 module 改动要 N 个 repo 同步,灾难 |
| **B. 一 repo 一 service** | `terraform-gke/`, `terraform-lb/` 各一个 repo | 大组织 / service mesh 严格隔离 | 你的 env 跨服务,**GKE 跟 LB 经常要共享 VPC/subnet/SA** — 拆不开 |
| **C. Monorepo 扁平** | 所有 .tf 放根目录 | 1 个 env + 5 个 resource | 加 env 就要复制全目录 |
| **D. Monorepo 分层** | `envs/ + modules/ + (可选) infrastructure-modules/` | **多 env + 多 service + 共享 module** | 早期(1 个 env / 3 个 resource)有点 over-engineered |

**你描述的就是 D** — 这是 HashiCorp **Standard Module Structure**(模块内布局)
+ Google Cloud 的 **`terraform-example-foundation`**(多 env 落地变体)+ Terragrunt
**DRY 原则** 的混合体。也是社区最常用的"多 GCP 工程 / 多 env"标准答案。

---

## 1. 顶层目录骨架(15 秒看完)

```
terraform-gcp-platform/                # 一个 repo,管 N 个 GCP 工程 × M 个 env
├── README.md                          # 用法总览:clone → cd envs/dev/... → terraform init
├── .gitignore                         # 忽略 .terraform/、*.tfstate、*.tfstate.backup
├── .terraform-version                 # 锁 Terraform 版本
├── .tflint.hcl                        # 静态检查
├── .pre-commit-config.yaml            # terraform fmt / validate / tflint / tfsec
│
├── modules/                           # 【项目内私有模块】项目特定的封装
│   ├── project-bootstrap/             # 创建 GCP project + 启用 API + billing 绑定
│   ├── network/                       # VPC + subnets + firewall + NAT
│   ├── gke/                           # GKE 集群 + node pool + SA + Workload Identity
│   ├── glb-public/                    # External HTTPS GLB + cert-manager cert
│   ├── ilb-internal/                  # Internal LB + health check + NEG
│   ├── cloud-armor/                   # Security policy + rules
│   ├── cert-manager/                  # Certificate + Map + TrustConfig
│   ├── dns/                           # Cloud DNS records + DNSSEC
│   ├── sa/                            # Service Accounts + Workload Identity 绑定
│   ├── secret/                        # Secret Manager + versions + IAM
│   ├── cloud-run/                     # Cloud Run service + IAM + custom domain
│   ├── storage/                       # GCS bucket + lifecycle + IAM
│   ├── pubsub/                        # Pub/Sub topic + subscription + DLQ
│   ├── monitoring/                    # Alert policy + notification channel + dashboard
│   ├── cicd/                          # Cloud Build trigger + Artifact Registry
│   └── nginx-squid/                   # 你的特殊组件:Nginx + Squid deployment
│
├── infrastructure-modules/            # 【可选】跨项目复用的库(提到 public repo / 内部 registry)
│   ├── networking/                    # 通用 VPC module(每个 GCP 工程用同一份)
│   ├── iam/                           # 通用 IAM + SA patterns
│   ├── gke-base/                      # 通用 GKE baseline(每个团队用同一份)
│   └── ...
│
├── envs/                              # 【真正的部署入口】每个文件夹 = 1 个 GCP 工程 × 1 个 env
│   ├── dev/
│   │   ├── project-a/                 # 工程 a 的 dev env
│   │   ├── project-b/
│   │   └── project-c/
│   ├── staging/
│   │   ├── project-a/
│   │   ├── project-b/
│   │   └── project-c/
│   └── prod/
│       ├── project-a/
│       ├── project-b/
│       └── project-c/
│
├── examples/                          # 【可选】完整可跑 sample(给新人 onboarding)
│   ├── complete-stack/                # 一个 project 包含 GKE + LB + Nginx + Squid
│   └── ...
│
├── tests/                             # 【可选】Terratest 集成测试
│   ├── gke_test.go
│   ├── lb_test.go
│   └── ...
│
├── scripts/                           # 【可选】辅助脚本
│   ├── init-backend.sh                # 一次性创建 GCS bucket + 给 SA 授权
│   ├── tf-plan-all.sh                 # 遍历 envs/*/*/ 跑 plan
│   └── ...
│
└── docs/                              # 【可选】架构图 / decision records
    ├── architecture.md
    └── adr/
        ├── 0001-use-terraform.md
        ├── 0002-why-not-terragrunt.md
        └── ...
```

**核心原则:** **`envs/<env>/<project>/main.tf` 几乎不含 `resource {}` 块,全是 `module {}` 引用 + `provider {}` + `data {}`**。所有 resource 定义都在 `modules/<resource>/` 里。

---

## 2. 为什么 `envs/<env>/<project>/` 要这么深

你可能觉得"dev/project-a 直接写 dev-project-a 不行吗" — 试过就知道问题:

- **同名工程多 env 共享 module** → 必须能"工程"维度切,不能"env+project"切(否则 staging-project-a 跟 prod-project-a 找不到对应 module 版本)
- **CI 自动化 plan/apply 路径稳定** → 路径不变意味着 PR label / apply.sh 不用改
- **blast-radius 控制** → 改一个工程只 trigger 一个 path 的 CI

3 层是 HashiCorp 在 `terraform-example-foundation` 用的标准(env / business-unit / env-name),你的简化版(env / project)刚好对齐。

---

## 3. `modules/<resource>/` 的标准内部结构

每个 module 内部**严格遵循 HashiCorp Standard Module Structure**,因为这是社区共识,别人一接手就懂:

```
modules/gke/
├── README.md                          # 必写!用法 + 变量清单 + 示例
├── main.tf                            # 主资源定义(GKE cluster + node pool)
├── variables.tf                       # input variables
├── outputs.tf                         # output values
├── versions.tf                        # terraform { required_version / required_providers }
├── providers.tf                       # provider 配置(可选,见 §4)
├── network.tf                         # 可选:把 network 相关拆出来(子 module 模式)
├── service-account.tf                 # 可选:SA 相关
├── iam.tf                             # 可选:IAM bindings
├── examples/
│   └── complete/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── tests/
    └── gke_test.go                    # Terratest
```

**单文件 vs 多文件分拆原则:**
- **< 200 行** → 1 个 `main.tf` 就够
- **200-500 行** → 按资源类型拆(`network.tf` / `iam.tf` / `cluster.tf`)
- **> 500 行** → **拆成 submodule**(再下钻一层 `modules/gke/cluster/` `modules/gke/node-pool/`)

---

## 4. 三个非显然的"坑位"先标记

### 4.1 `provider` 放哪

**两种风格,选一种不要混用:**

| 风格 | 优点 | 缺点 |
|---|---|---|
| **集中式** — `provider "google"` 只在 env 里出现,module 里不写 | 同一份 module 可被多个 project / region 复用 | module 单元测试时需要 mock provider |
| **module 内** — module 里也写 `terraform { required_providers { google = { ... } } }` | module 自包含,可单测 | env 跟 module 都重复声明 |

**推荐:** module 里只写 `versions.tf`(`required_providers`,但**不**写 `provider "google"` 块),`provider "google" {}` 块在 env 里集中配置。

### 4.2 `backend` 放哪

**严格:** `backend "gcs" {}` 块**只在 env 里写**(`envs/dev/project-a/backend.tf`)。module 里**绝不**写 backend。

```
envs/dev/project-a/
├── backend.tf           # 唯一的 terraform { backend "gcs" { bucket = ... } }
├── main.tf              # module "gke" { source = "../../../modules/gke" }
├── variables.tf
├── outputs.tf
├── versions.tf
├── providers.tf         # provider "google" { project = "..." region = "..." }
└── terraform.tfvars     # 实际值(可 .gitignore 化,看 §4.4)
```

**backend bucket 命名约定:**

```
tfstate-<env>-<project>-<short-region>
```

例:`tfstate-dev-project-a-uscentral1`,`tfstate-prod-project-a-global`。

### 4.3 `terraform.tfvars` 跟 secret 怎么管

- **非敏感配置**(`project_id` / `region` / `cluster_name`)→ 提交 git
- **敏感配置**(`db_password` / `tls_private_key` / `service_account_key_json`)→ **绝对不进 git**,来源:
  - **首选:** GCP Secret Manager,TF 用 `data "google_secret_manager_secret_version"` 读
  - **CI:** GitHub Actions / GitLab CI 走 Workload Identity Federation 拿短期 token
  - **本地:** `terraform.tfvars` 加进 `.gitignore`,本地手写,或者用 `TF_VAR_xxx` env var 注入

**永远不**把 `*.tfvars` 整体 gitignore — 只 ignore 包含 secret 的那一个(或用 `*.tfvars` + 显式 `!common.tfvars` 提交非敏感)。

### 4.4 State file 锁 / 协作

GCS backend 自带 object-level lock,无需额外配置。规则:
- **永远不**手 `terraform state pull/push` — 走 GCS
- **永远不**编辑 `*.tfstate` JSON
- **state mv / state rm** 是合法操作,但**要 review**
- **state 漂移检测**:`terraform plan` 是最简单的 drift detection,CI 跑 plan 比对

---

## 5. 一个 env 单元的完整 sample

`envs/dev/project-a/`(GKE + GLB + Nginx + Squid 的 dev env):

```hcl
# envs/dev/project-a/backend.tf
terraform {
  backend "gcs" {
    bucket = "tfstate-dev-project-a-uscentral1"
    prefix = "envs/dev/project-a"
  }
}

# envs/dev/project-a/providers.tf
provider "google" {
  project = local.project_id
  region  = local.region
}

provider "google-beta" {
  project = local.project_id
  region  = local.region
}

# envs/dev/project-a/variables.tf
variable "cluster_name" {
  type    = string
  default = "dev-cluster-a"
}

variable "node_count" {
  type    = number
  default = 2
}

# envs/dev/project-a/locals.tf
locals {
  project_id = "aibang-dev-project-a"
  region     = "us-central1"
  env        = "dev"
  common_labels = {
    env        = local.env
    project    = "project-a"
    managed_by = "terraform"
    repo       = "terraform-gcp-platform"
  }
}

# envs/dev/project-a/main.tf
module "project_bootstrap" {
  source     = "../../../modules/project-bootstrap"
  project_id = local.project_id
  apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "certificatemanager.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
  ]
  labels = local.common_labels
}

module "network" {
  source     = "../../../modules/network"
  project_id = module.project_bootstrap.project_id
  region     = local.region
  vpc_name   = "dev-project-a-vpc"
  subnets = {
    gke     = { cidr = "10.10.0.0/20",  purpose = "GKE" }
    proxy   = { cidr = "10.10.16.0/24", purpose = "REGIONAL_MANAGED_PROXY" }
    backend = { cidr = "10.10.32.0/20", purpose = "GCE" }
  }
}

module "gke" {
  source            = "../../../modules/gke"
  project_id        = module.project_bootstrap.project_id
  cluster_name      = var.cluster_name
  region            = local.region
  network           = module.network.vpc_self_link
  subnetwork        = module.network.subnets["gke"].self_link
  node_count        = var.node_count
  release_channel   = "REGULAR"
  enable_workload_identity = true
  labels            = local.common_labels
}

module "glb_public" {
  source      = "../../../modules/glb-public"
  project_id  = module.project_bootstrap.project_id
  region      = local.region
  domains     = ["api-dev.project-a.example.com"]
  backend_service_backends = [
    { name = module.nginx.backend_service_name }
  ]
  cert_manager_certificate = module.cert_manager.certificate_id
}

module "cert_manager" {
  source     = "../../../modules/cert-manager"
  project_id = module.project_bootstrap.project_id
  domains    = ["api-dev.project-a.example.com"]
}

module "nginx" {
  source           = "../../../modules/nginx-squid"
  component        = "nginx"
  project_id       = module.project_bootstrap.project_id
  gke_cluster      = module.gke.cluster_id
  namespace        = "nginx"
  backend_servers  = ["http://squid.nginx.svc.cluster.local:3128"]
  config = {
    "proxy.conf" = file("${path.module}/configs/nginx-proxy.conf")
  }
}

module "squid" {
  source      = "../../../modules/nginx-squid"
  component   = "squid"
  project_id  = module.project_bootstrap.project_id
  gke_cluster = module.gke.cluster_id
  namespace   = "squid"
  config = {
    "squid.conf" = file("${path.module}/configs/squid.conf")
  }
}

# envs/dev/project-a/outputs.tf
output "cluster_endpoint" {
  value = module.gke.cluster_endpoint
}

output "glb_ip" {
  value = module.glb_public.global_ip
}
```

**注意:** `main.tf` 里**没有**任何 `resource "google_*" {}` 块 — 全是 `module {}`。这就是 D 模式的力量。

---

## 6. `modules/` 内部示例(简版)

`modules/gke/main.tf`(你自己写时填具体值):

```hcl
# modules/gke/main.tf — 伪代码示意
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region

  network    = var.network
  subnetwork = var.subnetwork

  release_channel {
    channel = var.release_channel
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  resource_labels = var.labels
  # ... 完整字段参考 google_container_cluster docs
}

resource "google_container_node_pool" "primary" {
  name     = "${var.cluster_name}-np"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.primary.name

  node_config {
    machine_type = var.node_machine_type
    # ... 完整字段
  }

  autoscaling {
    min_node_count = var.node_min_count
    max_node_count = var.node_max_count
  }
}
```

`modules/gke/variables.tf`:

```hcl
variable "project_id" {
  type        = string
  description = "GCP project ID hosting the cluster"
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "network" {
  type        = string
  description = "VPC self-link"
}

variable "subnetwork" {
  type        = string
  description = "Subnetwork self-link"
}

variable "node_machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "node_min_count" { type = number, default = 1 }
variable "node_max_count" { type = number, default = 5 }
variable "node_count"     { type = number, default = 1 }

variable "release_channel" {
  type    = string
  default = "REGULAR"
  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, or STABLE"
  }
}

variable "enable_workload_identity" {
  type    = bool
  default = true
}

variable "labels" {
  type    = map(string)
  default = {}
}
```

---

## 7. 你的常见组件对位到 module 命名

| 你提的组件 | 推荐的 module 名 | 用途 |
|---|---|---|
| GKE | `modules/gke/` | GKE cluster + node pool + Workload Identity |
| Nginx | `modules/nginx/` (或合并到 `modules/nginx-squid/`) | GKE 上的 Nginx Deployment + Service |
| Squid | `modules/squid/` (或同上) | GKE 上的 Squid Deployment + Service |
| GLB | `modules/glb-public/` | External HTTPS LB + URL Map + Backend Service + Cert |
| ILB | `modules/ilb-internal/` | Internal TCP/UDP LB + NEG + Health Check |
| Cert | `modules/cert-manager/` | Certificate + Map + TrustConfig |
| VPC/Subnet | `modules/network/` | VPC + subnets + firewall + Cloud NAT |
| Cloud Armor | `modules/cloud-armor/` | Security policy + rules |
| SA / IAM | `modules/iam/` | Service Account + Workload Identity binding |
| Secret | `modules/secret/` | Secret Manager + versions + IAM |
| Bucket | `modules/storage/` | GCS bucket + lifecycle + IAM |
| DNS | `modules/dns/` | Cloud DNS record sets + DNSSEC |
| 监控 | `modules/monitoring/` | Alert policy + Dashboard + Notification channel |
| CI/CD | `modules/cicd/` | Cloud Build trigger + Artifact Registry |

**建议合并:** `modules/nginx-squid/` 单 module 内部用 `var.component` 切换("nginx" / "squid"),通过子目录 `modules/nginx-squid/templates/{nginx,squid}/` 放不同 Deployment 模板,比拆成 2 个 module 简洁。

---

## 8. CI/CD 怎么对接这个布局

```yaml
# .github/workflows/terraform-plan.yml
name: terraform plan
on:
  pull_request:
    paths:
      - 'envs/**'
      - 'modules/**'

jobs:
  plan:
    strategy:
      matrix:
        target: |
          dev/project-a
          dev/project-b
          staging/project-a
          staging/project-b
          prod/project-a
          prod/project-b
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.9.0
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
          service_account: terraform-ci@aibang-tf-ci.iam.gserviceaccount.com
      - run: |
          cd envs/${{ matrix.target }}
          terraform init -backend=false
          terraform plan -out=tfplan
          terraform show -no-color tfplan > plan.txt
      - uses: actions/upload-artifact@v4
        with:
          name: plan-${{ matrix.target }}
          path: envs/${{ matrix.target }}/plan.txt
```

**关键点:**
- **PR 改 `modules/`** → 触发**所有 env** 的 plan(看 blast radius)
- **PR 改 `envs/dev/project-a/`** → 只触发 dev/project-a 的 plan
- **apply 永远不在 PR 阶段** — merge 到 main 后由单独的 apply workflow 处理(可加 manual approval)

---

## 9. 工具链清单

| 工具 | 作用 | 必装 |
|---|---|---|
| `terraform` (>= 1.5) | 主工具 | ✅ |
| `tflint` | Lint(命名 / 类型 / deprecated) | ✅ |
| `tfsec` / `trivy` | 安全扫描(public bucket / 公开 IAM) | ✅ |
| `checkov` | 安全 + 合规 | 推荐 |
| `terraform-docs` | 自动生成 module README | 推荐 |
| `pre-commit` | 跑 fmt/validate/tflint/tfsec 钩子 | ✅ |
| `terragrunt` | DRY wrapper(可选,见 §10) | 视情况 |
| `atlantis` | PR 自动化 plan/apply | 大团队 |

`.pre-commit-config.yaml` 最小集:

```yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.92.1
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
      - id: terraform_tfsec
      - id: terraform_docs
```

---

## 10. 进阶:要不要用 Terragrunt

**短答:** 你的规模(几十个 GCP 工程 × 几个 env)用 **纯 Terraform** 就够,**不要** Terragrunt。

Terragrunt 解决的是"几十个 env × 几十个 stack"时的 DRY 问题(避免 `backend.tf` 在 50 个目录里复制 50 遍)。它的代价:
- 多一层抽象,新人上手成本
- 调试 `terragrunt plan` 比 `terraform plan` 难
- HCL 是受限子集,有些 TF 1.5+ 特性不支持

**什么时候该用:** 你有 **> 20 个 env** 或 **> 50 个 project** 时再考虑。届时它是正确的 — 现在不是。

---

## 11. 实际落地的 5 步走(你开始动手时)

1. **建 repo** — `git init terraform-gcp-platform`,复制本 doc 的骨架
2. **初始化 backend** — `bash scripts/init-backend.sh` 一次性建 `tfstate-*` GCS bucket + IAM
3. **写 `modules/project-bootstrap/`** — 第一个 module,所有 env 都用
4. **写 `modules/network/`** — 第二个 module,VPC + subnets + firewall
5. **写第一个 env** — `envs/dev/project-a/` 串起 project-bootstrap + network + gke,先 apply 一次
6. **再扩展** — 加 GKE + GLB + Nginx + Squid,每个对应一个 module

每个 module 写完跑一遍 `terraform-docs`,把 README.md 自动填好。

---

## 12. 参考资料

- HashiCorp Standard Module Structure: https://developer.hashicorp.com/terraform/language/modules/develop
- GCP terraform-example-foundation(GCP 团队多 env 标准): https://github.com/terraform-google-modules/terraform-example-foundation
- terraform-google-modules 社区 modules: https://github.com/terraform-google-modules
- Terragrunt 决策指南: https://terragrunt.gruntwork.io/docs/getting-started/quick-start/
- pre-commit-terraform: https://github.com/antonbabenko/pre-commit-terraform
- Google Cloud Architect Guide: Multi-Environment Terraform

---

## 附录:本 doc 的限制

- **未触及**的具体决策:state encryption with CMEK、Cross-project 共享 VPC 怎么处理、Packer / Image Builder 怎么放。这些都有"标准做法",但属于**第二层**设计 — 你的第一层(目录结构)先按本 doc 来,后续遇到再问。
- **不替代**具体的 resource 文档(`google_container_cluster` / `google_compute_url_map` 的每个字段):本 doc 讲的是**结构**,**不是**逐字段文档。
- **没有 sample state file / sample backend config** — 这些根据你选的 backend(GCS / S3 / Terraform Cloud)差异很大,本 doc 只固定"backend 块**只在 env 里有**"这条规则。
