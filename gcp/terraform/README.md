# Terraform GCP 仓库结构 — 最佳实践

> 适用于:**多 GCP 工程 × 多 env(典型的 dev/staging/prod)× 多服务组件(GKE/GLB/Nginx/Squid 等)** 的
> Terraform 仓库结构设计。如果你只有 1 个 project + 1 个 env + 5 个 resource,这个 layout
> 略重 — 但加第 2 个 env 那天,你会感谢今天多花的 30 分钟。

> **核心推荐 layout(摘要 — 完整图见 §1):**
> - **1 个 monorepo** 管所有 env
> - **`envs/<region>/<project>/`** 是部署入口(里面**只有 module 引用**,不写 resource)
> - **`modules/<resource>/`** 是可复用资源定义
> - **`resourceset/<region>/<project>.yaml`** 是**已部署项目的 canonical 模板**,通过 introspect 脚本反向生成
> - **`templates/`** 给你直接 copy 的样板(env / module / repo 三个 level)
> - **`examples/`** 完整可跑 sample,新人 onboarding 用
> - **`references/`** 关键决策的 detail(backend / state / Terragrunt 升级时机 / 2025 最佳实践验证)
> - **`scripts/`** 工具:introspect(从 GCP 项目反向导出 YAML)、apply(从 YAML 渲染 envs + 跑 TF)、validate(校验 YAML schema)

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
│   ├── project-bootstrap/               # 建 project + 启用 API + billing(可选包 project-factory v18.x)
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
├── envs/                                # 部署入口(每个文件夹 = 1 region × 1 project)
│   ├── europe-west2/
│   │   ├── aibang-uk-prd-001/           # 生成自 resourceset/uk/aibang-uk-prd-001.yaml
│   │   └── aibang-uk-dev-001/
│   ├── asia-east2/
│   │   └── aibang-hk-prd-001/           # 生成自 resourceset/hk/aibang-hk-prd-001.yaml
│   └── us-central1/
│       └── aibang-us-stg-001/
│
├── resourceset/                         # ★ 已部署项目的 canonical 模板(YAML)
│   ├── SCHEMA.md                        # 字段定义 + 验证规则
│   ├── TEMPLATE.yaml                    # 新项目空白模板(copied, then edited)
│   ├── europe-west2/
│   │   └── aibang-uk-prd-001.yaml       # 从真实 GCP 项目 introspect 得到
│   └── asia-east2/
│       └── aibang-hk-prd-001.yaml
│
├── templates/                           # 直接 copy 的样板
│   ├── env/                             # 一个新 env 单元的 6 个 .tf 文件
│   ├── module/                          # 一个新 module 的 5 个 .tf 文件
│   └── repo/                            # 仓库级配置文件(.gitignore 等)
│
├── examples/                            # 完整可跑 sample
│   └── envs/dev-project-a/              # 一份"标准 dev env"完整实例
│
├── scripts/                             # ★ 工具脚本
│   ├── introspect-project.sh            # 从 GCP 项目反向导出 resourceset/*.yaml
│   ├── apply-from-resourceset.sh        # 从 resourceset/*.yaml 渲染 envs/ + 跑 TF
│   ├── validate-resourceset.py          # 校验 YAML 符合 SCHEMA.md
│   ├── init-backend.sh                  # 一次性建 tfstate-* GCS bucket
│   └── tf-plan-all.sh                   # 遍历 envs/*/*/ 跑 plan
│
├── references/                          # 关键决策 detail(独立成文)
│   ├── directory-structure.md           # 目录结构细节(本 README 的 §3 详细版)
│   ├── state-and-backend.md             # GCS backend / state lock / secret / CMEK
│   ├── terragrunt-decision.md           # 何时升级到 Terragrunt
│   └── 2025-best-practices-validation.md  # 2025/2026 联网验证 + 来源
│
└── docs/                                # (可选)架构图 / ADR
    ├── architecture.md
    └── adr/
        ├── 0001-use-terraform.md
        ├── 0002-why-not-terragrunt.md
        └── ...
```

**关键不变量:**
1. `envs/<region>/<project>/main.tf` **几乎不含 `resource {}` 块**,全是 `module {}` 引用
2. **`backend "gcs" {}` 块只在 env 里写**,module 里**绝不**写 backend
3. **`provider "google" {}` 在 env 里集中配置**,module 里只写 `required_providers`(不写 provider 块)
4. **每个 module 都有 README.md** + `variables.tf` + `outputs.tf` + `versions.tf`
5. **`resourceset/**/*.yaml` 跟 `envs/<region>/<project>/` 一一对应** — 每个 env 都从一个 YAML 模板生成

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
| CI 怎么跑? | **PR 改 `modules/` → 触发所有 env plan** | `references/directory-structure.md §5` |
| 2025/2026 趋势? | v1 layout 仍然 best-practice;仅 CMEK 90 天轮换 + project-factory v18.x 是新推荐 | `references/2025-best-practices-validation.md` |
| 怎么从已有项目导出? | **`scripts/introspect-project.sh <project_id> <region>`** | §8 |

---

## 3. 为什么是这个 layout(其他 layout 的问题)

| Layout | 不选的理由 |
|---|---|
| **一 repo 一 env** (`terraform-prd/`, `terraform-dev/`) | 共享 module 改动要 N 个 repo 同步 — 灾难 |
| **一 repo 一 service** (`terraform-gke/`, `terraform-lb/`) | GKE 跟 LB 经常要共享 VPC/Subnet/SA — 拆不开 |
| **Monorepo 扁平**(全在根) | 加 env 就要复制全目录,Module 复用难 |
| **Monorepo 分层**(`envs/ + modules/ + resourceset/`)← **本方案** | 灵活但需要纪律;**加 30 分钟换长期省时间** |
| **Terragrunt wrapper** | 见 `references/terragrunt-decision.md` — 现阶段过度设计 |
| **cloudposse Atmos + terraform-yaml-stack-config** | 见 `references/2025-best-practices-validation.md §5` — 备选 YAML→TF 桥,但需要外部依赖 |

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
# (可选: 用 terraform-google-modules/project-factory v18.x 作为底层,本仓库只包 wrapper)

# 4. 写第一个 env — 通过 resourceset YAML 渲染,而不是手写
cp ../knowledge/gcp/terraform/resourceset/uk/aibang-uk-prd-001.yaml \
   resourceset/europe-west2/my-new-project.yaml
$EDITOR resourceset/europe-west2/my-new-project.yaml  # 改 project_id / region / CIDR
bash scripts/apply-from-resourceset.sh resourceset/europe-west2/my-new-project.yaml --plan-only

# 5. 跑通(确认 plan 没问题后)
bash scripts/apply-from-resourceset.sh resourceset/europe-west2/my-new-project.yaml
```

**第 3-5 步的每一步完成后都跑一次 `terraform-docs modules/<name>/` 自动生成 README**

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
| GCS backend / state lock / secret 管理 / CMEK | `references/state-and-backend.md` |
| 要不要 Terragrunt | `references/terragrunt-decision.md` |
| 2025/2026 联网验证 + 跟 v1 layout 的差异 | `references/2025-best-practices-validation.md` |
| 一个 env 长什么样(完整 .tf) | `templates/env/` + `examples/envs/dev-project-a/` |
| 一个 module 长什么样(完整 .tf) | `templates/module/` |
| 仓库初始化文件(.gitignore / tflint 等) | `templates/repo/` |
| 单个 module README 怎么写 | `templates/module/README.md` |
| ResourceSet YAML schema / 字段 / 验证规则 | `resourceset/SCHEMA.md` |
| 怎么从 GCP 项目反向导出 YAML | `scripts/introspect-project.sh` + §8 |
| 怎么从 YAML 渲染 env + 跑 TF | `scripts/apply-from-resourceset.sh` + §8 |

---

## 7. 参考资料

- HashiCorp Standard Module Structure: <https://developer.hashicorp.com/terraform/language/modules/develop>
- GCP `terraform-example-foundation`(多 env 黄金标准): <https://github.com/terraform-google-modules/terraform-example-foundation>
- terraform-google-modules 社区 modules: <https://github.com/terraform-google-modules>
- terraform-google-project-factory v18.x(项目创建 module): <https://github.com/terraform-google-modules/terraform-google-project-factory>
- pre-commit-terraform: <https://github.com/antonbabenko/pre-commit-terraform>
- Terragrunt 决策指南: <https://terragrunt.gruntwork.io/docs/getting-started/quick-start/>
- cloudposse/terraform-yaml-stack-config(YAML→TF 桥): <https://github.com/cloudposse/terraform-yaml-stack-config>
- Atmos(YAML 编排): <https://atmos.tools/>

---

## 8. ResourceSet 工作流(YAML 驱动 Terraform)

> 这是本仓库的**核心工作流**:已部署的 GCP 项目 = YAML 模板,新项目 = copy + 改值 + apply。

### 8.1 反向:从已有项目导出 YAML(introspect)

```bash
# 先认证
gcloud auth login

# 跑 introspect(会自动读 project / VPC / subnets / GKE,生成 resourceset/<region>/<project>.yaml)
bash scripts/introspect-project.sh aibang-uk-prd-001 europe-west2

# 自动校验 schema
# → Wrote resourceset/europe-west2/aibang-uk-prd-001.yaml
# → OK:   resourceset/europe-west2/aibang-uk-prd-001.yaml
```

(introspect 脚本会在最后自动跑 `scripts/validate-resourceset.py` 校验输出。**任何时候你手改
resourceset YAML 后,都该手动跑一次**:
`python3 scripts/validate-resourceset.py resourceset/<region>/<project>.yaml`。)

**为什么用 `gcloud` 而不是 terraformer?** terraformer 已于 **2026-03-16 archived**(`README`: "This project is no longer maintained and is deprecated")。CDKTF 也已于 2025-12-10 sunset。本仓库的 introspect 脚本是**纯 gcloud + Python**,零外部依赖,长期可维护。

### 8.2 正向:从 YAML 渲染 env + apply

```bash
# 1. 复制一个现有 resourceset YAML 作为新项目模板
cp resourceset/europe-west2/aibang-uk-prd-001.yaml \
   resourceset/europe-west2/my-new-project.yaml

# 2. 改关键字段
$EDITOR resourceset/europe-west2/my-new-project.yaml
#   - metadata.project_id / metadata.region
#   - project.id / project.name
#   - network.vpc_cidr / network.subnets (确保不跟现有冲突)
#   - gke.cluster_name / gke.master_ipv4_cidr / gke.pod_ipv4_cidr
#   - backend.bucket / backend.prefix

# 3. Dry-run:看 plan
bash scripts/apply-from-resourceset.sh resourceset/europe-west2/my-new-project.yaml --plan-only

# 4. 真 apply(需要 confirm;或加 --auto-approve 给 CI)
bash scripts/apply-from-resourceset.sh resourceset/europe-west2/my-new-project.yaml
```

脚本做的事(详见 `scripts/apply-from-resourceset.sh`):
1. 校验 YAML 符合 `SCHEMA.md`(否则 exit 1)
2. 渲染 `envs/<region>/<project>/{backend.tf,providers.tf,versions.tf,main.tf,variables.tf,locals.tf,terraform.tfvars}`
3. 跑 `terraform init -input=false`
4. 跑 `terraform plan -input=false -out=tfplan`(始终)
5. 除非 `--plan-only`,确认后跑 `terraform apply tfplan`

### 8.3 YAML 跟 Terraform variable 的对位

`resourceset/SCHEMA.md §10` 是**单一真相源**:每个 YAML 字段对应一个 `var.<name>`,由 `apply-from-resourceset.sh` 渲染成 `terraform.tfvars`。**改 YAML schema 时,同步改这里 + scripts/apply-from-resourceset.sh + main.tf 的 module 引用**。

### 8.4 当 YAML 跟实际 GCP 不一致(drift 检测)

```bash
# 1. 在现有项目上重跑 introspect,生成"最新" YAML
bash scripts/introspect-project.sh aibang-uk-prd-001 europe-west2 --out /tmp/current.yaml

# 2. Diff 对比 git 里版本
diff -u resourceset/europe-west2/aibang-uk-prd-001.yaml /tmp/current.yaml

# 3. 如果有差异,review 后 commit
mv /tmp/current.yaml resourceset/europe-west2/aibang-uk-prd-001.yaml
git commit -am "chore(resourceset): sync aibang-uk-prd-001 with actual state"
```

这样 `resourceset/` 同时是:**新项目的模板** + **现有项目的 ground truth**。