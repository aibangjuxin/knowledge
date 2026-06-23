# Terragrunt 升级决策

> **TL;DR:现阶段(几 env × 几 project)不要用 Terragrunt。** 等到 **> 20 个 env** 或 **> 50 个
> project** 时再考虑。本 doc 解释为什么 + 升级的 trigger。

---

## 1. Terragrunt 是什么

Gruntwork 公司做的 **Terraform wrapper**:
- HCL 是受限子集(只支持 TF 的子集)
- 提供 `include { path = "../terragrunt.hcl" }` 模式,让多个 stack 共享 `remote_state` / `provider` / `inputs`
- 提供 `run-all` 跑多个 stack
- 提供 `before_hook` / `after_hook` / `dependency` block 等 TF 没有的功能

**核心价值:** "DRY" — 50 个 env 不需要复制 50 份 `backend.tf`。

---

## 2. 什么时候**不**该用 Terragrunt

| 你的状态 | 推荐 |
|---|---|
| < 10 个 env | ❌ 纯 TF,不要 Terragrunt |
| 10-20 个 env | ⚠️ 视情况(见 §3) |
| > 20 个 env | ✅ Terragrunt 收益显现 |
| 单一 team / 单一 repo | ❌ Terragrunt 抽象层没价值 |

**为什么 < 10 env 不用:**
- 50 份 `backend.tf` 复制成本 < Terragrunt 抽象层的心智成本
- 调试 `terragrunt plan` 错误比 `terraform plan` 难
- 新人上手快(纯 TF 资源多 / Terragrunt 资源少)
- 一些 TF 1.5+ 特性 Terragrunt 短期不支持

---

## 3. 什么时候该考虑升级

升级到 Terragrunt 的**精确 trigger**:

| Trigger | 说明 |
|---|---|
| **你开始复制 backend.tf** | 第 2 次复制的时候评估;第 5 次复制就该升级 |
| **module 改动要触发 N 个 env plan,CI matrix 长到难以维护** | Terragrunt 的 `run-all` 比 GitHub matrix 优雅 |
| **你需要在多个 env 共享一个 `terraform_remote_state` 数据源** | 跨 env 引用资源(比如 dev 的 VPC 给 dev 的 GKE 用,但 prod VPC 给 prod 单独隔离) |
| **你的 team > 3 人,且经常要新加 env** | 抽象层降低 oncost |
| **你需要 6+ 个不同账号 / 凭证切换** | Terragrunt 的 `iam_role_arn` 比 TF 方便 |

**更简单的判断:** "我每次新加 env 都要复制粘贴 5+ 个 boilerplate 文件" → 是时候了。

---

## 4. Terragrunt 的 layout 对比

### 4.1 纯 TF(本仓库当前方案)

```
envs/dev/project-a/
├── backend.tf
├── providers.tf
├── main.tf
├── variables.tf
├── locals.tf
└── outputs.tf
```

`backend.tf` 每次复制都得手改 `bucket` / `prefix`。`providers.tf` 每次都得手改 `project`。

### 4.2 Terragrunt 改造后

```
envs/
├── terragrunt.hcl                     # 全局配置(remote_state / provider / input defaults)
├── _envcommon/                        # env 级别公共 input
│   ├── dev.hcl
│   ├── staging.hcl
│   └── prod.hcl
├── dev/
│   └── project-a/
│       └── terragrunt.hcl             # 只剩 project 特定 input
└── ...
```

`backend.tf` 没了 — `terragrunt.hcl` 的 `remote_state { ... }` 配置自动应用;`providers.tf` 没了 — Terragrunt 自动 generate。

### 4.3 真正"消灭 boilerplate"的关键 Terragrunt 特性

```hcl
# envs/terragrunt.hcl(全局)
remote_state {
  backend = "gcs"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    project  = "aibang-tfstate"
    location = "us-central1"
    bucket   = "tfstate-${path_relative_to_include()}"  # ← 自动从路径推 bucket
    prefix   = path_relative_to_include()
  }
}

generate "provider" {
  path      = "provider_google.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOT
provider "google" {
  project = "${local.project_id}"
  region  = "${local.region}"
}
EOT
}
```

效果:**新加 env 只需要写一个 `terragrunt.hcl`**,backend / provider 自动生成。

---

## 5. 升级路径(分阶段)

不要一天内全切,分 4 阶段:

| 阶段 | 工作量 | 内容 |
|---|---|---|
| **Phase 1** | 1 天 | 装 `terragrunt` + 写一个 `terragrunt.hcl` 试一个 env(用 `terragrunt plan` 验证等价) |
| **Phase 2** | 1 周 | 把所有 dev env 迁到 Terragrunt(可以跑但 backend.tf 还在) |
| **Phase 3** | 1 周 | 删 `backend.tf`,验证 `terragrunt plan` 仍然成功 |
| **Phase 4** | 持续 | staging / prod 跟进;删所有 `backend.tf` / `providers.tf` |

**回滚:** Phase 2/3 时随时能回滚到 `terraform plan`(`terragrunt` 调用 `terraform` 子进程,降级简单)。

---

## 6. Terragrunt 的代价(要清楚)

| 代价 | 影响 |
|---|---|
| 调试更难 | `terragrunt plan` 错误信息有时不指向真实 .tf 位置 |
| HCL 受限 | TF 1.5+ 的某些新特性(比如 `moved` block)早期不支持,后追版本 |
| 团队学习成本 | 新人要先学 Terragrunt 再学 TF |
| 文档少 | 比 TF 少一个数量级 |
| 单点故障 | `terragrunt` 工具本身是开源项目,不是 GCP SLA 范围 |

**结论:加 Terragrunt 是"未来收益",不是"现在收益"。** 不要为了用而用。

---

## 7. 替代方案(如果就是嫌 boilerplate 多)

如果你的痛点是 "新加 env 要复制 5 个文件",除了 Terragrunt 还有:

| 替代 | 优点 | 缺点 |
|---|---|---|
| **Shell script 生成 env 骨架** | 简单,debug 容易 | 不会自动同步(比如加新 module,要重跑) |
| **Makefile / Taskfile** | 显式,可控 | 不解决"env 内部 boilerplate" |
| **Copy-paste + 自动化 PR** | 一次写好永远用 | 难维护 |
| **Terraform Stacks (新功能,2024+ GA)** | HashiCorp 官方 DRY 方案 | 非常新,生产案例少 |

**短答:** 真要 DRY,优先 **Terragrunt**(成熟)或等 **Terraform Stacks**(未来)。其他方案都是 workaround。

---

## 8. 决策树

```
你现在 N 个 env?
├─ N < 10  → 用纯 TF,不要 Terragrunt
├─ 10 <= N < 20  → 看你烦不烦 boilerplate
│     ├─ 烦  → Terragrunt(评估 1 天,试 1 个 env)
│     └─ 不烦 → 纯 TF
└─ N >= 20  → Terragrunt(必备)
       │
       └─ 还要多 team 协作 + 复杂 IAM?
              ├─ 是  → Terragrunt + Atlantis
              └─ 否  → Terragrunt 就够
```

**当下来看:** 你说"管理很多 GCP 工程",但即使 30 个 project × 3 个 env = 90 个 stack,真正每天操作的< 10 个(剩下的 read-only / 已稳定)。**90 个 stack 听上去吓人,实际工作量不一定到 Terragrunt 阈值**。先纯 TF,等真痛了再升级。
