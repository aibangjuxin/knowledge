# Terraform GCP 仓库结构 — 最佳实践

> 适用于:**多 GCP 工程 × 多 env(典型的 dev/staging/prod)× 多服务组件(GKE/GLB/Nginx/Squid 等)** 的
> Terraform 仓库结构设计。如果你只有 1 个 project + 1 个 env + 5 个 resource,这个 layout
> 略重 — 但加第 2 个 env 那天,你会感谢今天多花的 30 分钟。
>
> **核心推荐 layout(摘要 — 完整图见 §1):**
> - **1 个 monorepo** 管所有 env
> - **`envs/<env>/<project>/`** 是部署入口(里面**只有 module 引用**,不写 resource)
> - **`modules/<resource>/`** 是可复用资源定义
> - **`templates/`** 给你直接 copy 的样板(env / module / repo 三个 level)
> - **`examples/`** 完整可跑 sample,新人 onboarding 用
> - **`references/`** 关键决策的 detail(backend / state / Terragrunt 升级时机)

---

## 1. 完整目录树(速览)

```
terraform-gcp-platform/                  # 1 repo 管 N 个 GCP 工程 × M 个 env
├── README.md                            # 你正在看
├── .gitignore                           # 见 templates/repo/.gitignore
├── .terraform-version                   # 锁 TF 版本
├── .tflint.hcl                          # 静态检查(见 templates/repo/)
├── .pre-commit-config.yaml              # 跑 fmt/validate/tflint/tfsec
│
├── modules/                             # 项目内私有 module(可复用)
│   ├── project-bootstrap/               # 建 project + 启用 API + billing
│   ├── network/                         # VPC + subnets + firewall + NAT
│   ├── gke/                             # GKE cluster + node pool + Workload Identity
│   ├── glb-public/                      # External HTTPS LB
│   ├── ilb-internal/                    # Internal TCP/UDP LB
│   ├── cert-manager/                    # Certificate + Map + TrustConfig
│   ├── cloud-armor/                     # Security policy + rules
│   ├── nginx-squid/                     # Nginx / Squid GKE Deployment
│   ├── iam/                             # Service Account + Workload Identity
│   ├── secret/                          # Secret Manager + versions
│   ├── storage/                         # GCS bucket + lifecycle + IAM
│   ├── dns/                             # Cloud DNS records
│   ├── monitoring/                      # Alert + Dashboard
│   └── cicd/                            # Cloud Build + Artifact Registry
│
├── infrastructure-modules/              # (可选)跨项目复用的 module 库
│   ├── networking/                      # 通用 VPC
│   ├── iam/                             # 通用 IAM patterns
│   └── gke-base/                        # 通用 GKE baseline
│
├── envs/                                # 部署入口(每个文件夹 = 1 env × 1 project)
│   ├── dev/
│   │   ├── project-a/
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
├── templates/                           # 直接 copy 的样板
│   ├── env/                             # 一个新 env 单元的 6 个 .tf 文件
│   ├── module/                          # 一个新 module 的 5 个 .tf 文件
│   └── repo/                            # 仓库级配置文件(.gitignore 等)
│
├── examples/                            # 完整可跑 sample
│   └── envs/dev-project-a/              # 一份"标准 dev env"完整实例
│
├── references/                          # 关键决策 detail(独立成文)
│   ├── directory-structure.md           # 目录结构细节(本 README 的 §3 详细版)
│   ├── state-and-backend.md             # GCS backend / state lock / secret 管理
│   └── terragrunt-decision.md           # 何时升级到 Terragrunt
│
├── scripts/                             # 辅助脚本
│   ├── init-backend.sh                  # 一次性建 tfstate-* GCS bucket
│   ├── tf-plan-all.sh                   # 遍历 envs/*/*/ 跑 plan
│   └── ...
│
└── docs/                                # (可选)架构图 / ADR
    ├── architecture.md
    └── adr/
        ├── 0001-use-terraform.md
        ├── 0002-why-not-terragrunt.md
        └── ...
```

**关键不变量:**
1. `envs/<env>/<project>/main.tf` **几乎不含 `resource {}` 块**,全是 `module {}` 引用
2. **`backend "gcs" {}` 块只在 env 里写**,module 里**绝不**写 backend
3. **`provider "google" {}` 在 env 里集中配置**,module 里只写 `required_providers`(不写 provider 块)
4. **每个 module 都有 README.md** + `variables.tf` + `outputs.tf` + `versions.tf`

---

## 2. 关键决策一览(详细见 references/)

| 问题 | 答案 | 详见 |
|---|---|---|
| 一个 repo 还是多个? | **1 个 monorepo**(多 env 共享 module) | §3 |
| 怎么分层? | `envs/ + modules/ + (可选) infrastructure-modules/` | §3 / `references/directory-structure.md` |
| `resource` 放哪? | **module 里**,env 里只 `module` 引用 | §3 |
| `backend` 放哪? | **env 里**(每个 env 一份 `backend.tf`) | `references/state-and-backend.md` |
| `provider` 放哪? | **env 里集中**,module 里只 `required_providers` | §4 |
| secret 怎么传? | **Secret Manager + data source**,永不进 git | `references/state-and-backend.md §4` |
| State 锁? | **GCS backend 自带 object-lock**,无需额外 | `references/state-and-backend.md §3` |
| 要 Terragrunt 吗? | **现阶段不要** — < 20 env 用纯 TF | `references/terragrunt-decision.md` |
| CI 怎么跑? | **PR 改 `modules/` → 触发所有 env plan** | `references/directory-structure.md §6` |

---

## 3. 为什么是这个 layout(其他 layout 的问题)

| Layout | 不选的理由 |
|---|---|
| **一 repo 一 env** (`terraform-prd/`, `terraform-dev/`) | 共享 module 改动要 N 个 repo 同步 — 灾难 |
| **一 repo 一 service** (`terraform-gke/`, `terraform-lb/`) | GKE 跟 LB 经常要共享 VPC/Subnet/SA — 拆不开 |
| **Monorepo 扁平**(全在根) | 加 env 就要复制全目录,Module 复用难 |
| **Monorepo 分层**(`envs/ + modules/`)← **本方案** | 灵活但需要纪律;**加 30 分钟换长期省时间** |
| **Terragrunt wrapper** | 见 `references/terragrunt-decision.md` — 现阶段过度设计 |

**这是 HashiCorp Standard Module Structure + Google `terraform-example-foundation` + Terragrunt DRY 原则**的混合体,社区最常用的"多 GCP 工程 / 多 env"标准答案。

---

## 4. 落地 5 步

```bash
# 1. 仓库初始化
git init terraform-gcp-platform && cd terraform-gcp-platform
cp ../knowledge/gcp/terraform/templates/repo/.gitignore .
cp ../knowledge/gcp/terraform/templates/repo/.terraform-version .
cp ../knowledge/gcp/terraform/templates/repo/.tflint.hcl .
cp ../knowledge/gcp/terraform/templates/repo/.pre-commit-config.yaml .
pre-commit install

# 2. 初始化 GCS backend(一次性,见 scripts/init-backend.sh)
bash scripts/init-backend.sh

# 3. 写第一个 module
cp -r ../knowledge/gcp/terraform/templates/module modules/project-bootstrap
# 在 modules/project-bootstrap/main.tf 填具体 resource

# 4. 写第一个 env
cp -r ../knowledge/gcp/terraform/templates/env envs/dev/project-a
# 在 envs/dev/project-a/main.tf 引用 modules/project-bootstrap 等
# 在 envs/dev/project-a/terraform.tfvars 填具体值

# 5. 跑通
cd envs/dev/project-a
terraform init
terraform plan
terraform apply
```

**第 3-5 步的每一步完成后都跑一次 `terraform-docs modules/<name>/` 自动生成 README**。

---

## 5. 你的常见组件对位 module 名

| 你提的组件 | module 名 | 备注 |
|---|---|---|
| GKE | `modules/gke/` | cluster + node pool + Workload Identity |
| Nginx | `modules/nginx-squid/`(var.component = "nginx") | 合并 module,内部分支 |
| Squid | `modules/nginx-squid/`(var.component = "squid") | 同上,Deployment 模板不同 |
| GLB(Public HTTPS) | `modules/glb-public/` | target-https-proxy + url-map + cert |
| ILB(Internal TCP/UDP) | `modules/ilb-internal/` | forwarding-rule + backend + health-check |
| Cert | `modules/cert-manager/` | Certificate + Map + TrustConfig |
| VPC/Subnet | `modules/network/` | VPC + subnets + firewall + NAT |
| Cloud Armor | `modules/cloud-armor/` | security-policy + rules |
| SA / IAM | `modules/iam/` | service account + Workload Identity |
| Secret | `modules/secret/` | Secret Manager + versions |
| Bucket | `modules/storage/` | GCS bucket + lifecycle |
| DNS | `modules/dns/` | Cloud DNS records + DNSSEC |
| 监控 | `modules/monitoring/` | alert + dashboard |
| CI/CD | `modules/cicd/` | Cloud Build + Artifact Registry |

**为什么 nginx + squid 合一个 module:**
- 都是 GKE 上的 Deployment + Service
- 共享 RBAC / namespace / 镜像仓库
- 差异只在 Deployment template 跟 ConfigMap,内部分支比拆 2 module 简洁

---

## 6. 文档导航

| 你想知道什么 | 看哪里 |
|---|---|
| 完整目录树 + 每层职责 | `references/directory-structure.md` |
| GCS backend / state lock / secret 管理 | `references/state-and-backend.md` |
| 要不要 Terragrunt | `references/terragrunt-decision.md` |
| 一个 env 长什么样(完整 .tf) | `templates/env/` + `examples/envs/dev-project-a/` |
| 一个 module 长什么样(完整 .tf) | `templates/module/` |
| 仓库初始化文件(.gitignore / tflint 等) | `templates/repo/` |
| 单个 module README 怎么写 | `templates/module/README.md` |

---

## 7. 参考资料

- HashiCorp Standard Module Structure: <https://developer.hashicorp.com/terraform/language/modules/develop>
- GCP `terraform-example-foundation`(多 env 黄金标准): <https://github.com/terraform-google-modules/terraform-example-foundation>
- terraform-google-modules 社区 modules: <https://github.com/terraform-google-modules>
- pre-commit-terraform: <https://github.com/antonbabenko/pre-commit-terraform>
- Terragrunt 决策指南: <https://terragrunt.gruntwork.io/docs/getting-started/quick-start/>
