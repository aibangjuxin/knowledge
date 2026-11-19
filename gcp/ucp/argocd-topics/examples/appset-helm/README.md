# 示例：ApplicationSet 由 Helm 渲染（CP 仓库 → Tenant 仓库）

> 对应文档：
> - [`../../appset-helm-Rendering.md`](../../appset-helm-Rendering.md) —— 渲染链路
> - [`../../helm-cross-repository.md`](../../helm-cross-repository.md) —— 跨仓库与凭据原理

这个目录是「**ApplicationSet 本身是 Helm chart 的渲染产物**」这条链路的最小可运行样例。

> ⚠️ **重要：`cp-chart/` 和 `tenant-repo/` 是两个独立的 Git 仓库。**
> 本目录只是把两者放在一起方便对照阅读，**不是一个真实仓库里的两个子目录**。
>
> | 目录 | 真实归属 | 谁 push | Argo CD 用谁的凭据读它 |
> |---|---|---|---|
> | `cp-chart/` | **CP Repository**（仓库 A） | 只有平台管理员 | CP 仓库自己的凭据 |
> | `tenant-repo/` | **Tenant Repository**（仓库 B） | 租户 / 平台运维 | **tenant 仓库自己的另一份凭据** |
>
> tenant 仓库**不需要是 public**：只要 Argo CD 里给它的 URL 配了凭据
> （GitHub App / PAT / deploy key）就能读 —— 原理见
> [`../../helm-cross-repository.md`](../../helm-cross-repository.md) §3。

---

## 目录结构

```
appset-helm/                        ← 示例沙盒（不是一个真实仓库！）
├── cp-chart/                       ← ⭐ 这些文件在 CP Repository（仓库 A）
│   ├── Chart.yaml
│   ├── values.yaml                 ←   租户清单（project / 仓库地址都定在这儿）
│   └── templates/
│       ├── _helpers.tpl            ←   「原样转义」helper
│       ├── appproject-tenant.yaml   ←   渲染 AppProject（边界）
│       ├── applicationset-cluster-apps.yaml  ← ⭐ 渲染 ApplicationSet（主线）
│       └── application-cluster-bootstrap.yaml ← mode C：直接渲染 Cluster Application
│
├── tenant-repo/                    ← ⭐ 这些文件在 Tenant Repository（仓库 B，另一个仓库！）
│   ├── clusters/
│   │   ├── dev-01/
│   │   │   ├── cluster.yaml        ←   集群元信息（file generator 读它）
│   │   │   └── values.yaml         ←   该集群的 Helm 覆盖值
│   │   └── prod-01/...
│   └── apps/
│       └── nginx/                  ←   应用 chart（所有集群共用一份）
│           ├── Chart.yaml
│           ├── values.yaml
│           └── templates/
│
└── render-check.sh                 ← 本地验证转义有没有写对
```

---

## 三条命令走一遍

```bash
cd examples/appset-helm

./render-check.sh                                     # ① 验证 Helm 渲染没吃掉 AppSet 模板
helm template platform-cp cp-chart                    # ② 看渲染出来的 ApplicationSet
helm template nginx tenant-repo/apps/nginx \
  -f tenant-repo/clusters/dev-01/values.yaml          # ③ 看应用 chart + 集群 values 的结果
```

`render-check.sh` 检查的是**最容易错的地方**：

| 检查 | 说明 |
|---|---|
| `{{ .app.path.basename }}` 原样保留 | 没转义 → Helm 会把它渲染成空串 |
| `{{ $t.` 没有残留 | chart 自己的变量没渲染干净 |
| 没有 `` {{` `` 残留 | 转义过头（多套一层反引号） |
| `valueFiles` 路径拼写正确 | `../../clusters/{{ .cluster.path.basename }}/values.yaml` |

另外注意 chart 里用的是 **`matrix`** 包裹两个 Git 生成器：
并列写两个生成器**不是**笛卡尔积（controller 会逐个生成器单独跑模板，
另一半变量取不到 → `missingkey=error` 报错）。

---

## 这套样例要表达的三个结论

1. **两层模板引擎会打架** → ApplicationSet 模板必须用 Helm 字符串字面量
   （`` '{{`{{ .x }}`}}' ``）包起来，见
   [`applicationset-cluster-apps.yaml`](./cp-chart/templates/applicationset-cluster-apps.yaml)。
2. **YAML 注释里的 `{{ }}` 也会被 Helm 解析** → 注释里别写裸大括号。
3. **`project` 必须硬编码在 CP 侧** → 租户仓库只提供「集群在哪、应用在哪」，
   不提供「这个 Application 归哪个项目管」。

---

## 落地时还要补的东西（本示例刻意省略）

| 缺什么 | 去哪看 |
|---|---|
| Argo CD 能读 tenant 仓库的凭据（Repository Secret / GitHub App） | [`../../07-repository-githubapp.md`](../../07-repository-githubapp.md) |
| 集群要先在 Argo CD 注册（cluster secret）才收得到 Application | [`../../09-troubleshooting.md`](../../09-troubleshooting.md) |
| AppProject / RBAC 的边界怎么定 | [`../../04-appproject-rbac.md`](../../04-appproject-rbac.md) |
| ApplicationSet 的生成器与模板语法全表 | [`../../05-appset.md`](../../05-appset.md) |
| 跨仓库渲染到底是 Helm 还是 Argo CD 做的 | [`../../helm-cross-repository.md`](../../helm-cross-repository.md) |
