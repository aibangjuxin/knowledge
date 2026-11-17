# `examples/envs/dev-project-a/` — 完整 dev env 例子

> 这个目录展示一个 **真实的、可直接参考的** dev env 长什么样。
> 对比 `templates/env/`(样板,留了 `CHANGEME`),这里填了具体值。

## 包含什么

- `backend.tf` — GCS backend,具体 bucket 名
- `providers.tf` — provider 用 local 变量
- `versions.tf` — TF + provider 版本约束
- `main.tf` — 8 个 module 引用:bootstrap / network / gke / cert-manager / glb-public / nginx-squid / monitoring / secret
- `variables.tf` — env 级别 variables
- `locals.tf` — env 级别 locals(含完整 common_labels)
- `outputs.tf` — 跨 stack 引用用的 outputs

## 怎么用

```bash
# 1. copy 到你的实际 envs/
cp -r examples/envs/dev-project-a envs/dev/your-project

# 2. 改 backend.tf 的 bucket / prefix
$EDITOR envs/dev/your-project/backend.tf

# 3. 改 locals.tf 的 project_id / region / env
$EDITOR envs/dev/your-project/locals.tf

# 4. 改 main.tf 适配你的项目需要的 module 组合
$EDITOR envs/dev/your-project/main.tf

# 5. init + plan + apply
cd envs/dev/your-project
terraform init
terraform plan
terraform apply
```
