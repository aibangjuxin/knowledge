# 07 · 跨仓库渲染的原理

> **先回答那个问题**：
> 「ApplicationSet / Application 跨 Git 仓库取内容」这个能力，
> **是 Helm 带来的吗？**
>
> **不是。** Helm 完全不知道 Git 的存在。
> 跨仓库是 **Argo CD 在调用 Helm 之前替它做完的事**：
> Argo CD 把多个仓库各自 checkout 到临时目录，把跨仓库的值文件解析成**绝对路径**，
> 然后把这个路径交给 `helm template --values /abs/path/values.yaml`。
> Helm 全程只知道「我读了这个文件」，不知道这个文件来自哪个 Git 仓库、哪个 commit。
>
> **那「CP 仓库没有权限读 tenant 仓库」怎么办？**
> 问错了主体 —— 见 [§3 凭据模型](#3-跨仓库的前提argo-cd-的凭据模型repository-cr)：
> **权限属于 Argo CD（repo-server），不属于仓库。**
> tenant 仓库**不需要是 public**，但 Argo CD 必须给它配一份凭据。
>
> **心智模型一句话**（详见 [§1.2](#12-心智模型argo-cd-是-broker谁和谁交互)）：
> **Git 仓库只是被读取的数据源；`argocd` 命名空间才是控制面（状态 + 凭据 + 边界）；
> 仓库之间没有直接交互，它们的"关系"只是一串由 Argo CD 解析的指针。**

配套文档：
[`appset-helm-Rendering.md`](./appset-helm-Rendering.md)（CP 仓库 → Tenant 仓库那条链路）

---

## 0. 先纠正一个误解：那**两个目录**不是同一个仓库

在 [`examples/appset-helm/`](./examples/appset-helm/) 里，我把两个仓库**并排放**在同一个目录下来方便对照阅读：

```
examples/appset-helm/                 ← ⚠️ 这只是「示例沙盒」，不是一个真实仓库
├── cp-chart/                         ← 🔵 这些文件在 **CP Repository**（仓库 A）
│   ├── Chart.yaml
│   ├── values.yaml                   ←    租户清单（repoURL / project 定在这儿）
│   └── templates/
│       ├── _helpers.tpl
│       ├── appproject-tenant.yaml
│       ├── applicationset-cluster-apps.yaml
│       └── application-cluster-bootstrap.yaml
│
└── tenant-repo/                      ← 🟢 这些文件在 **Tenant Repository**（仓库 B）
    ├── clusters/
    │   ├── dev-01/{cluster.yaml,values.yaml}
    │   └── prod-01/{cluster.yaml,values.yaml}
    └── apps/nginx/{Chart.yaml,values.yaml,templates/}
```

**真实部署里它们是两个独立的 Git 仓库**（可能是同一个 GitLab 组织的两个 project、
也可能是两个不同的 GitHub 组织）。

| | 仓库 A（CP Repository） | 仓库 B（Tenant Repository） |
|---|---|---|
| 谁 push | 只有平台管理员 | 租户 / 平台运维 |
| 内容 | CP 的 chart、租户清单、AppProject、RBAC | 集群清单、应用 chart、每集群 values |
| Argo CD 怎么读 | 用 **A 自己的凭据** | 用 **B 自己的凭据**（另一份） |

> 💡 所以「跨仓库」在实现上非常朴素：
> **Argo CD 手里有两把钥匙（A 的、B 的），分别去开两个仓库。**
> 仓库 A 里的那个 `repoURL: https://.../tenant-cluster.git` 只是**一个字符串**，
> 它本身不携带任何权限 —— 权限在 Argo CD 的凭据里。

---

## 1. 能力归属表与心智模型

### 1.1 能力归属表

| 能力 | 谁实现 | 跨的是什么 | 关键语法 |
|---|---|---|---|
| **ApplicationSet 生成器读另一个仓库** | Argo CD（AppSet controller + repo-server） | **参数**（集群清单、变量） | `generators[].git.repoURL` |
| **Application 的值文件来自另一个仓库** | Argo CD（repo-server，多源） | **值文件**（Helm values） | `spec.sources[].ref` + `valueFiles: [$values/...]` |
| **Application 的清单来自多个仓库** | Argo CD（多源） | **清单** | `spec.sources[]` |
| **谁能读哪个仓库** | **Argo CD 的 Repository CR / Secret** | **凭据** | `Repository` CR（`spec.url` + `spec.project`） |
| **Helm chart 依赖来自别的 chart 仓库** | **Helm 原生**（Argo CD 代跑 `helm dependency build`） | 依赖 chart | `Chart.yaml` 的 `dependencies` |
| **一个 chart 引用同仓库其它目录的文件** | Helm 原生 | 文件 | `.Files.Get` / 相对路径 `--values` |

**一句话记法：**

> Helm 的世界观 = **一个目录 + 一堆本地文件路径**。
> 所有的「仓库」概念（clone、revision、多仓合并、跨仓取值）
> 都是 Argo CD 在外面包的一层。

### 1.2 心智模型：Argo CD 是 broker（谁和谁交互）

> **你的理解是对的**，可以更精确成一句话：
>
> **Git 仓库是被读取的数据源；`argocd` 命名空间是控制面（状态 + 凭据 + 边界）；
> Argo CD 从仓库拉取、在集群里比对并下发。**
> **仓库之间没有任何直接交互** —— 它们之间的"关系"只是一串由 Argo CD 解析的指针。

**四层结构：**

| 层 | 在哪 | 内容 | 谁写 |
|---|---|---|---|
| **数据层** | Git 仓库（CP / Tenant） | chart、清单、values | 人（走 PR） |
| **控制面** | `argocd` 命名空间里的 CR | Application / ApplicationSet / AppProject | Argo CD（从 Git 渲染出来） |
| **凭据层** | `argocd` 命名空间里的 Secret | Repository 凭据、cluster secret | 人（一次性配置） |
| **执行层** | repo-server / application controller | 拉取、渲染、比对、下发 | Argo CD |

**「关系」是怎么落地的：**

```
CP 仓库的 chart 里写 repoURL: tenant-repo.git
        │  ① 这只是一个「指针字符串」
        ▼
Helm 渲染 → ApplicationSet CR 写入 argocd 命名空间   ← ② 关系在这里被「物化」
        ▼
Argo CD 读到 CR 里的指针 → 用【自己的凭据】去 clone     ← ③ 权限在这里生效
```

所以「CP ↔ Tenant 的对应关系」有**两份**：

| 形态 | 位置 | 性质 |
|---|---|---|
| 声明式 | CP 仓库里的字符串（chart values） | 意图 |
| 物化态 | `argocd` 命名空间里的 CR | **实际被执行的东西** |

### 1.3 谁主动、谁被动

| 方向 | 交互 | 说明 |
|---|---|---|
| Argo CD → 仓库 | **拉**（clone / 读文件 / 渲染） | 主路径。仓库不会主动找 Argo CD |
| Argo CD → 目标集群 | **推**（apply / prune） | 主路径 |
| 仓库 → Argo CD | **webhook**（可选） | 只是「提醒缓存失效、尽快重新拉」，不是数据通道 |
| Argo CD → 仓库 | 默认**不写** | 唯一例外：Helm values write-back（要靠 notifications 模板显式开启） |

> 📌 **所以「CP 仓库和 Tenant 仓库都是和 Argo CD 交互」这句话完全正确。**
> 仓库对 Argo CD 而言只是「可被读取的内容 + 可被渲染的模板」，
> 它不持有任何 Argo CD 的权限。

### 1.4 这个模型直接推导出安全结论

| 事实 | 推出的结论 |
|---|---|
| CP 仓库的内容会被 Argo CD **渲染成控制面对象** | CP 仓库 ≈ **控制面的一部分**，不是普通数据仓库 |
| Argo CD 手里握着所有仓库的钥匙 | 能 push CP 仓库 = **能在 Argo CD 里创建任意 Application** = admin 权限 |
| 集群里的 CR 是从 Git **派生产物** | `kubectl edit` 会被同步回去（Git 是唯一真相；是否自动回滚取决于 `syncPolicy.automated.selfHeal`） |
| 凭据在 `argocd` 命名空间 | 谁能访问那个命名空间 = 谁能读所有仓库 → 命名空间要严格 RBAC |

---

## 2. Helm 侧的事实：它到底知道什么

`helm template` 的全部输入：

```
helm template <chart目录> \
    --values  /abs/path/a.yaml \
    --values  /abs/path/b.yaml \
    --set     key=value
```

Helm 在这件事上的认知边界：

| Helm 知道 | Helm 不知道 |
|---|---|
| chart 目录的**本地路径** | Git / branch / commit / tag |
| `--values` 的**本地路径**（绝对或相对 chart 目录） | 这个文件来自哪个仓库、谁写的、是不是可信的 |
| `--set` 的键值 | K8s、Argo CD、Application、AppProject |
| chart 目录内的 `.Files.Get` | chart 目录外的文件（除非用 `--values` 显式给绝对路径） |

**推论：**

1. 「跨仓库取 values」在 Helm 层面**就是「读一个本地文件」**，
   没有比这更神奇的地方。
2. **仓库边界、路径穿越、凭据、缓存失效** —— 这些 Helm 一个都不管，
   全是 Argo CD 在外面加的。
   所以跨仓库做错了（比如引用了不该引用的仓库），
   **责任在 Argo CD 的配置，不在 Helm**。

> 📌 这也是为什么「Helm 官方文档里从没提过跨仓库」——
> 因为在 Helm 的世界里根本没有「仓库」这个概念。

---

## 3. 跨仓库的前提：Argo CD 的凭据模型（Repository CR）

> **这一章回答你的核心疑问**：
> 「CP 的仓库没有权限读 tenant 仓库，它怎么完成任务？
> 难道 tenant 仓库必须是 public？」

### 3.1 凭据只存在于 Argo CD 里，不在仓库里

Argo CD 访问 Git 用的是 **Repository CR / Repository Secret**（放在 `argocd` 命名空间，
或项目自己的命名空间）。Git 服务端只认 **Argo CD 那一份身份**，与「谁在引用这个仓库」无关。

```
   CP Repository (仓库 A)              Argo CD                   Tenant Repository (仓库 B)
   ┌────────────────────┐        ┌────────────────────┐        ┌────────────────────┐
   │ chart 里写着:      │        │  Repository CR:    │        │                    │
   │ repoURL:           │───────►│   url: tenant-repo │───────►│  用 Argo CD 的     │
   │  ".../tenant.git"  │  只是  │   project: tenant-a│  凭据  │  身份做认证         │
   │ （一个字符串指针） │  指针  │   + 凭据(GitHubApp/ │  访问  │                    │
   └────────────────────┘        │     PAT/SSH key)   │        └────────────────────┘
                                  └────────────────────┘
                                         ↑
                                  CP Repository 的凭据是**另一条** Repository CR
```

**所以：**

- ❌ 「CP 仓库有没有权限读 tenant 仓库」—— 这个问题问错了主体；
  仓库之间没有「读权限」这回事，Git 不提供这种授权。
- ✅ 「**Argo CD 有没有 tenant 仓库的凭据**」—— 这才是决定性的问题。
- ✅ tenant 仓库**可以是私有的**；public 只是「不配凭据时的匿名 fallback 能成的特例」。

### 3.2 凭据是怎么被找到的（源码）

```go
// util/db/repository_secrets.go
func (s *secretsRepositoryBackend) getRepositorySecret(repoURL, project string, allowFallback bool) (*corev1.Secret, error) {
    for _, secret := range secrets {
        if !git.SameURL(string(secret.Data["url"]), repoURL) {   // ① 按 URL 匹配（不是按名字）
            continue
        }
        projectSecret := string(secret.Data["project"])
        if project == projectSecret {                            // ② 同 project 的精确匹配优先
            return secret, nil
        }
        if projectSecret == "" && allowFallback {                // ③ 全局凭据兜底
            foundSecret = secret
        }
    }
    return nil, status.Errorf(codes.NotFound, "repository %q not found", ...)
}
```

**三条规则：**

| # | 规则 | 含义 |
|---|---|---|
| ① | **按仓库 URL 匹配** | 凭据绑在**被访问的仓库**上，不是绑在「引用它的那个仓库」上 |
| ② | **project 作用域优先** | `secret.data.project == 使用者的 project` 的凭据优先命中 |
| ③ | **全局凭据兜底** | `project` 为空（全局）的凭据，任何 project 都能用 |

> 💡 **推论**：CP chart 里写 `repoURL: tenant-repo.git`，
> 用的是 **tenant 仓库自己的凭据**。
> CP 仓库的凭据只用来读 CP 仓库自己。两者互不相干。

### 3.3 没有凭据会怎样？→ **匿名 clone**（这才是 public 的用武之地）

```go
// util/db/repository.go
func (db *db) getRepository(ctx, repoURL, project string) (*v1alpha1.Repository, error) {
    exists, _ := secretsBackend.RepositoryExists(ctx, repoURL, project, true)
    if exists {
        return secretsBackend.GetRepository(ctx, repoURL, project)   // 有凭据 → 用凭据
    }
    return &v1alpha1.Repository{Repo: repoURL}, nil                   // ⚠️ 没凭据 → 空凭据 = 匿名
}
```

**没配凭据时，Argo CD 会以匿名身份去 clone**：

| 目标仓库 | 匿名 clone 的结果 |
|---|---|
| **public** 仓库 | ✅ 能成（这就是「public 就行」的情形） |
| **private** 仓库 | ❌ `authentication failed` / `could not read Username` / `repository not found` |

**直接回答你的问题：**

> 你的 tenant 仓库**不需要是 public**。
> 你需要做的是：**在 Argo CD 里给这个仓库 URL 配一份凭据**
> （GitHub App / PAT / SSH deploy key / TLS 客户端证书）。

### 3.4 三条跨仓库路径各需要什么凭据

| 路径 | 谁去 clone | 用哪个 project 去匹配凭据 | 需要的凭据 |
|---|---|---|---|
| **CP chart 本身** | repo-server | CP 那个 Application 的 `spec.project` | CP 仓库的 Repository 凭据 |
| **AppSet 生成器**（读 tenant 仓库） | repo-server（Git API） | AppSet 的 `template.spec.project` | **tenant 仓库的 Repository 凭据**（独立的一份） |
| **Application 的 source**（读 tenant 仓库） | repo-server | Application 的 `spec.project` | 同上（**同一个 URL → 同一份凭据**） |
| **多源 ref 源** | repo-server | 同上 | 每个 ref 源各自的凭据 |

**一张表记住：**

> 凭据是**按仓库 URL** 配的。
> 需要读 N 个仓库 = 需要 N 份凭据（可以是同一个 GitHub App 覆盖多个仓库）。

### 3.5 完整时序（含凭据查找）

```
AppSet controller              Argo CD (argocd-server/repo-server)         Git
     │                                │                                    │
     │ ① 生成器要读 tenant 仓库        │                                    │
     │   repoURL=..., revision=main   │                                    │
     ├───────────────────────────────►│                                    │
     │                                │ ② 按 URL 找凭据                      │
     │                                │    Repository CR / Secret            │
     │                                │    （project 优先 → 全局兜底）         │
     │                                │ ③ 没找到 → 空凭据（匿名）              │
     │                                │    找到 → 带上 token/SSH key          │
     │                                │ ④ clone（凭据在这里生效）               │
     │                                ├───────────────────────────────────►│
     │                                │◄───────────────────────────────────┤
     │ ⑤ 拿到目录/文件内容              │                                    │
     │◄───────────────────────────────┤                                    │
     │ ⑥ 平铺成参数 → 渲染模板 → 生成 Application                            │
```

**注意第 ② 步**：凭据查找发生在 **Argo CD 内部**，
既不看 CP 仓库的内容，也不看 tenant 仓库的内容。
**chart 里写什么 URL，只是决定了「去开哪把钥匙」。**

### 3.6 凭据类型与选型

| 类型 | 适用场景 | 说明 |
|---|---|---|
| **GitHub App**（推荐） | GitHub | 一份凭据覆盖多个仓库；**可按仓库单独授权**；见 [`07-repository-githubapp.md`](./07-repository-githubapp.md) |
| **PAT / username+password** | 通用 | 粗粒度，注意 scope 只给只读 |
| **SSH deploy key** | 自建 Git | Argo CD 存 PEM 私钥 |
| **TLS 客户端证书** | 内部 Git | |
| **无（匿名）** | public 仓库 | ⚠️ 生产慎用：任何人能 push chart 就能让 Argo CD 去拉任意 public 仓库 |

### 3.7 project-scoped 凭据 + 「模板化 project」的坑

**Repository CR 的 `spec.project` 字段**（源码注释）：

> Reference between project and repository that allows it to be automatically
> added as an item inside SourceRepos project entity.

即：给某个项目配了 project-scoped 的 Repository，
这个仓库会**自动出现在该 AppProject 的 `sourceRepos`** 里（省得手动维护）。

**但有一个硬约束**（上游 `Generators-Git.md` 原文）：

> You must only use "non-scoped" repositories for ApplicationSets with a
> templated `project` field.

**原因**：`project` 被模板化时，生成器在查凭据的那一刻**还不知道最终会落到哪个 project**，
所以只能依赖**全局凭据**。

| 场景 | 该用什么凭据 |
|---|---|
| `project` 硬编码（推荐） | project-scoped 凭据（最小权限，按租户隔离） |
| `project` 模板化 | **只能**用全局凭据（安全边界退化成「全局凭据对应的所有仓库」） |

### 3.8 报错对照

| 报错 | 含义 | 处理 |
|---|---|---|
| `repository "https://..." not found` | Argo CD **没有这个 URL 的凭据** → 退化成匿名 → 私有库必失败 | 给这个仓库配 Repository 凭据 |
| `could not read Username` / `authentication failed` | 有凭据但不对（token 过期 / scope 不够 / 仓库名错） | 换凭据；确认 PAT 有读权限 |
| `error in GetRepository: unable to get repository "..."` | 同上 | 同上 |
| `Failed to generate application for param ...` | 生成器读仓库失败（凭据/网络/revision 不存在） | 看 AppSet controller 日志里的底层错误 |
| `source referenced "values", but no source has a 'ref' field defined` | `$values` 前缀没有对应 ref 源 | 加 `ref: values` |
| 集群里能拉、租户拉不到 | 该租户的 project-scoped 凭据没配 | 检查 Repository CR 的 `spec.project` |

---

## 4. Argo CD 的两条跨仓库路径

### 4.1 路径一：ApplicationSet 生成器读另一个仓库（**你那套 CP → Tenant 就是这条**）

**要解决的问题**：ApplicationSet 需要知道「有哪些集群 / 哪些应用」，
而这些信息在**另一个 Git 仓库**里。

**实现链路（源码）**：

```
applicationset/generators/git.go
  └─ g.repos.GetFiles(ctx, repoURL, revision, project, pattern, ...)
       ↓  gRPC
applicationset/services/repo_service.go
  └─ argoCDService.GetFiles / GetDirectories
       ├─ getRepository(repoURL, project)   ← ★ 按 URL 找凭据（§3.2）
       └─ repo-server: GetGitFiles / GetGitDirectories
            ↓
reposerver/repository/repository.go
  └─ Service.GetGitFiles()  ← 用仓库凭据 clone/读取指定 revision 的文件
```

**时序图**：

```
AppSet controller            repo-server              Git (Tenant Repo)
     │                            │                          │
     │ GetGitFiles(repoURL=tenant, │                          │
     │   revision=main, pattern=   │                          │
     │   clusters/*/cluster.yaml)  │                          │
     ├───────────────────────────► │                          │
     │                            │ 找凭据（按 URL+project）    │
     │                            │ clone + 读文件           │
     │                            ├─────────────────────────►│
     │                            │◄─────────────────────────┤
     │  map[file] = 内容           │                          │
     │◄───────────────────────────┤                          │
     │                            │                          │
     │ 把 YAML 平铺成参数：                                   │
     │   .server / .namespace / .cluster.path.basename        │
     │                            │                          │
     │ 用参数渲染 spec.template → 生成 Application            │
```

**关键点：**

| 问题 | 答案 |
|---|---|
| 生成器读的仓库需要单独配凭据吗？ | **需要**。它是另一个 Repository（可以是 project-scoped） |
| 生成器读的仓库和 Application 的 `source.repoURL` 是同一个吗？ | **完全独立**。两者可以是两个仓库，各读各的 |
| 生成器需要把仓库 clone 到本地吗？ | 不一定。目录列举和文件读取是 repo-server 的 Git API 操作（按 revision 读取），不是完整工作区 |
| 谁决定「参数可信」？ | 你。`project` 模板化时，**生成器仓库的写权限就是权限边界**（见 [`05-appset.md`](./05-appset.md) §5.2） |

> 📌 **这条路和 Helm 一点关系都没有**：
> Helm 还没被调用，ApplicationSet controller 已经在跨仓库取参数了。
> 你在 CP chart 里写的 `{{ .app.path.basename }}`，
> 它的值是 **AppSet controller 从另一个仓库读来的**。

### 4.2 路径二：多源 values（值文件跨仓库）

**要解决的问题**：chart 在仓库 A，但每个集群的 values 在仓库 B。

**声明方式**：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx
spec:
  project: tenant-a
  destination:
    server: https://example-dev-01.k8s.example.internal
    namespace: platform
  sources:                      # ← 注意是 sources（复数），有 sources 时 source 字段被忽略
    - repoURL: https://github.com/example/app-repo.git
      path: apps/nginx
      targetRevision: main
    - repoURL: https://github.com/example/tenant-cluster.git
      targetRevision: main
      ref: values                # ← 这个 ref 声明了 $values 前缀
```

然后在**第一个源**（有 chart/path 的那个）的 helm 配置里引用：

```yaml
    - repoURL: https://github.com/example/app-repo.git
      path: apps/nginx
      targetRevision: main
      helm:
        valueFiles:
          - $values/clusters/dev-01/values.yaml    # ← $values 指向第二个源
```

**实现链路（源码）**：

```
reposerver/repository/repository.go
  │
  ├─ resolveReferencedSources()
  │    └─ 对每个带 ref 的源：解析自己的 revision（独立 commitSHA）
  │       → checkout 到各自的临时目录（gitRepoPaths）
  │       → 记录 repoRefs[normalizedURL] = {revision, commitSHA, key: refVar}
  │
  ├─ getResolvedValueFiles()
  │    └─ 逐个 valueFile：
  │        if strings.HasPrefix(valueFile, "$")   → getResolvedRefValueFile()
  │             └─ refVar = "$" 后面的第一段（如 values）
  │             └─ 路径相对「被引用仓库的根」解析，并禁止越界
  │        else                                    → ResolveValueFilePathOrUrl(appPath, repoRoot, ...)
  │             └─ 相对 source.path 解析，禁止越出主源仓库根
  │
  └─ helmTemplate()
       └─ helm template . --values <上面解析出来的绝对路径> ...
```

**时序图**：

```
repo-server                          Helm
   │  ① checkout 主源 (app-repo)         │
   │  ② checkout ref 源 (tenant-repo)    │
   │     ← 两个独立的临时目录，各自的 commitSHA
   │
   │  ③ 解析 valueFiles:
   │     "$values/clusters/dev-01/values.yaml"
   │        → /tmp/…/tenant-repo-<sha>/clusters/dev-01/values.yaml
   │
   ├─ ④ helm template . --values /tmp/…/tenant-repo-<sha>/clusters/dev-01/values.yaml
   │                                        │
   │                                        ├─ 读文件 → 合并进 values
   │                                        ├─ 渲染 templates/
   │◄───────────────────────────────────────┤
   │  ⑤ 拿到渲染结果（Helm 全程不知道这是 Git 文件）
```

**关键点：**

| 问题 | 答案 |
|---|---|
| Helm 需要支持跨仓库吗？ | **不需要**。它收到的是绝对路径 |
| 两个源各自会渲染吗？ | 会。每个源各自生成清单，最后**合并**；同名资源**后者覆盖前者**（上游会打 `RepeatedResourceWarning`） |
| `ref` 源会自己产生 K8s 资源吗？ | 只有设了 `path` 才会。**只设 `ref` 不设 `path`** → 该源只提供值文件，不产生清单（源码注释：*"not generating manifests as path and chart fields are empty"*） |
| ref 源能是 Helm chart 吗？ | **不能**。源码明确报错：*"source has a 'chart' field defined, but Helm charts are not yet supported for 'ref' sources"* |
| 缓存怎么失效？ | 缓存键里带**每个 ref 源的 commitSHA**（`refSourceCommitSHAs`）→ 被引用仓库一变，渲染结果就重算 |
| 同一个仓库能引用不同 revision 吗？ | 不能。源码报错：*"cannot reference a different revision of the same repository"* |
| ref 源需要凭据吗？ | **需要** —— 每个源按自己的 URL 找凭据（§3.4） |

### 4.3 容易混淆的第三种：Helm chart 依赖（Helm 原生能力）

```yaml
# Chart.yaml
dependencies:
  - name: redis
    version: 18.x.x
    repository: https://charts.bitnami.com/bitnami
```

这**是** Helm 的能力：Argo CD 在渲染前代跑 `helm dependency build`
（源码：`util/helm/helm.go` → `DependencyBuild()`），
把依赖下载到 chart 的 `charts/` 子目录，之后 `helm template` 就能正常渲染。

但注意：

- 这是从 **chart 仓库**（HTTP/OCI）拉，不是 Git 仓库；
- 依赖被**下载进本地目录**，之后它就和「同仓库的文件」没区别了；
- 依赖版本写死在 `Chart.yaml`（或 `Chart.lock`）里 → **更新依赖需要改仓库**。

---

## 5. `$` 前缀：Argo CD 的语法，不是 Helm 的

```go
// reposerver/repository/repository.go
func getReferencedSourceName(rawValueFile string) string {
    if !strings.HasPrefix(rawValueFile, "$") {
        return ""
    }
    return strings.Split(rawValueFile, "/")[0]
}
```

**规则（上游原文）：**

> the `$values` variable can only be used at the beginning of the value file path
> and that its path is always relative to the root of the referenced source.

即：

| valueFiles 写法 | 解析成 |
|---|---|
| `values.yaml` | 相对 `source.path`（主源），不得越出主源仓库根 |
| `../../clusters/dev-01/values.yaml` | 同上，**允许**（还在主源仓库根内） |
| `$values/clusters/dev-01/values.yaml` | 相对**被引用源**的仓库根，不得越出该仓库根 |
| `$values/../etc/passwd` | ❌ 被拦：*"resolved to outside repository root"* |

> ⚠️ **`$` 和 `{{ }}` 是两套完全不同的东西。**
> `$values` 是「**跨源引用**」前缀；
> `{{ }}` 是「模板表达式」。
> `${{.x}}` 这种写法**没有任何转义含义**，详见
> [`appset-helm-Rendering.md`](./appset-helm-Rendering.md) §1.1。

---

## 6. 边界与限制速查（都有源码依据）

| 限制 | 出处 / 报错原文 |
|---|---|
| 值文件不得越出所属仓库根 | `util/io/path/resolved.go` → *"file '%s' resolved to outside repository root"* |
| 软链接不得指向仓库外 | repo-server 的 out-of-bounds symlink 检查（`AllowOutOfBoundsSymlinks` 关闭时） |
| ref 源不能是 chart / OCI | *"Helm charts are not yet supported for 'ref' sources"* |
| 同一仓库不能引用两个不同 revision | *"cannot reference a different revision of the same repository"* |
| ref 源没有 `path` → 不产生清单 | *"not generating manifests as path and chart fields are empty"* |
| 多源同名资源后者覆盖前者 | 上游 `RepeatedResourceWarning` |
| 多源别滥用 | 上游原话：*"If you find yourself using more than 2-3 items in the sources array then you are almost certainly abusing this feature"* |
| **没有凭据 → 匿名 clone（私有库必失败）** | `util/db/repository.go` → `return &v1alpha1.Repository{Repo: repoURL}, nil` |
| **凭据按 URL 匹配，project 优先、全局兜底** | `util/db/repository_secrets.go` → `getRepositorySecret()` |
| **模板化 project 时只能用全局凭据** | 上游：*"only use non-scoped repositories"* |
| 生成器仓库需要自己的凭据 | AppSet controller → `getRepository(repoURL, project)` 找不到就报错 |
| `project` 模板化时不能用 scoped repo | 上游 Security 文档 |

---

## 7. 你那套 CP → Tenant 的完整链路（跨仓库视角）

把三条路径叠在一起看：

```
①  CP Repository（chart）                    ← Argo CD repo-server: helm template
    │  渲染出 ApplicationSet CR
    ▼
②  ApplicationSet CR
    │  生成器读 Tenant Repository 的集群清单      ← AppSet controller → repo-server 的 Git API
    │  （凭据：tenant 仓库自己的那一份，§3.4）
    ▼
③  Application（每集群 × 每应用一个）
    │  source.repoURL = Tenant Repository
    │  source.helm.valueFiles = ../../clusters/<cluster>/values.yaml
    │  （同一个仓库内 → 用相对路径，不需要多源）
    ▼
④  repo-server: helm template（第三次模板引擎）
    ▼
   目标集群
```

**注意第 ② 步和第 ① 步的"跨仓库"是两种不同的跨：**

| | 第 ① 步 | 第 ② 步 | 第 ③/④ 步 |
|---|---|---|---|
| 跨的是什么 | 仓库 A 的 chart → 渲染到仓库 B 的清单 | 仓库 B 的清单 → 参数 | 仓库 B 内部（相对路径） |
| 谁实现 | Argo CD（Helm 只渲染目录） | Argo CD AppSet controller | Argo CD repo-server |
| Helm 参与吗 | ✅（只渲染第 ① 步的 chart） | ❌ | ✅（渲染目标 chart） |
| 需要谁的凭据 | A 的 | **B 的** | B 的 |

> 💡 **所以「CP 仓库里的 chart 渲染出读 Tenant 仓库的 ApplicationSet」这件事，
> 本质上是 Argo CD 的「AppSet 跨仓库取参数」+「Helm 在单目录内渲染」两件事的组合，
> Helm 自己一行跨仓库的代码都没有。**

### 7.1 权限视角：谁能写哪个仓库 → 能干什么

| 能写哪个 | 能造成什么 | **做不到**什么 |
|---|---|---|
| **CP 仓库** | 让 Argo CD 用**它有凭据的任意仓库**去 clone；创建任意 Application、任意 AppProject | 读**没有配凭据**的仓库；改动 Argo CD 自己的凭据 |
| **Tenant 仓库** | 决定集群清单、values（镜像 / 命令 / 参数 / env）→ 等价于**代码执行** | 改不了 `project`、改不了 AppProject / RBAC |
| **Argo CD 里的 Repository 凭据** | 决定 Argo CD 能读哪些仓库（**这是最关键的一环**） | — |

### 7.2 ⚠️ 混淆代理（confused deputy）风险

CP 仓库的 chart 里可以写**任意 `repoURL`**。如果 Argo CD 为很多仓库配了凭据
（例如一个 GitHub App 装在 50 个仓库上），那么：

> **能 push CP 仓库的人** → 让 Argo CD 去 clone 那 50 个仓库中的任意一个
> → 把内容渲染进目标集群的 ConfigMap / Secret 里
> → **等于把私有仓库的数据搬到了他能访问的地方**。

**这条链路完全不需要任何"越权"操作 —— 每一步在 Argo CD 眼里都是合法的。**

**缓解手段（按有效性排序）：**

1. **每个租户一个 project-scoped Repository CR**
   → 租户的凭据只在租户 project 里可见，CP 仓库里写别的 repoURL 也拿不到凭据；
2. **AppProject 的 `sourceRepos` 白名单 + `destinations` 限制**
   → 即使凭据能取到，也不允许投递到不该去的集群/命名空间；
3. **`project` 在 CP 侧硬编码**，租户改不了归属；
4. **CP 仓库写权限只给管理员**（上游：只有 admin 能建/改 ApplicationSet）；
5. **GitHub App 只授权必要的仓库**，别图省事装到整个 org；
6. **审计**：repo-server 的 clone 记录 + Argo CD audit log
   → 定期看「谁在什么时候让 Argo CD 拉了哪个仓库」。

---

## 8. 该用哪种「跨仓库」

| 你的需求 | 用什么 | 复杂度 |
|---|---|---|
| 集群清单在另一个仓库 | AppSet `git` 生成器 | 低 |
| chart 在 A、每集群 values 在 B | 多源 `ref` + `$values/...` | 中 |
| 同一个仓库里，chart 和 values 分开放 | `valueFiles` 相对路径 `../../` | **最低（推荐先用这个）** |
| 第三方 chart + 自己的 values | 多源（chart 源 + values 源） | 中 |
| chart 依赖别的 chart | `Chart.yaml` `dependencies` | 低 |

**决策顺序建议：**

1. 先试**同仓库相对路径**（`../../`）—— 它没有额外凭据、没有缓存失效问题、
   没有「谁覆盖谁」的顺序问题；
2. 确实需要跨仓库时，优先用 **AppSet 生成器**（参数跨仓库），
   因为它**不涉及把值文件喂给 Helm**，语义更干净；
3. 最后才用**多源 `ref`**（值文件跨仓库）——
   它引入了「多源合并」「同名覆盖」「ref 源缓存」这些额外语义。

---

## 9. 安全含义

**跨仓库 = 信任边界扩大。**

| 跨法 | 风险 | 缓解 |
|---|---|---|
| 生成器读另一个仓库 | 该仓库能决定**生成哪些 Application、装到哪个集群** | `project` 硬编码 + AppProject `sourceRepos` 白名单 + 仓库写权限收紧 |
| 值文件来自另一个仓库 | 该仓库能决定**镜像、启动参数、env、volume** → 等价于**代码执行** | 只允许可信仓库做 ref 源；`sourceRepos` 要包含它；对 values 做 schema 校验 |
| Helm chart 依赖外部 chart 仓库 | 依赖被投毒 | 锁 `Chart.lock` + 私有 chart 仓库 + 镜像扫描 |
| CP 仓库的 chart 渲染 AppSet | 能创建任意 Application；混淆代理（§7.2） | CP 仓库只给管理员；project-scoped 凭据；见 [`appset-helm-Rendering.md`](./appset-helm-Rendering.md) §8 |

**额外注意：**

- 被引用仓库的凭据是**独立**的 Repository secret；
- 用 `project`-scoped repo 时，AppProject 的 `sourceRepos` 必须同时包含
  主源和所有 ref 源，否则取不到值文件；
- **`project` 模板化 ⇒ 只能用全局凭据**（§3.7）—— 这是权限边界最大的退化点，
  能硬编码就硬编码。

---

## 10. 凭据配置清单（落地时照着做）

| 仓库 | 需要凭据？ | 建议类型 | 作用域 |
|---|---|---|---|
| CP Repository | ✅ | GitHub App（只授权这个仓库） | 全局或 `platform-cp` project |
| Tenant Repository（每租户一个） | ✅ **（私有库必须）** | GitHub App（按租户授权）或 deploy key | **project-scoped（`spec.project: tenant-a`）** |
| 目标集群（cluster secret） | ✅ | 见 [`04-appproject-rbac.md`](./04-appproject-rbac.md) | — |

```bash
# 检查 Argo CD 认不认识这个仓库（认不出来 = 会走匿名 → 私有库必失败）
kubectl -n argocd get repositories
kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=repository

# 在 UI 上最直观：Settings → Repositories，应该能看到每个 URL + 它的 project 作用域
```

---

## 11. 本地怎么复现

**多源 values 在本地没有等价物**（本地只有一个目录），
但可以这样验证边界：

```bash
# ① 主源 chart + 同仓库相对路径的值文件（本地能完全复现）
helm template nginx app-repo/apps/nginx \
  -f app-repo/clusters/dev-01/values.yaml

# ② 模拟「跨仓库取值」：把另一个目录的值文件用绝对路径喂进去
helm template nginx app-repo/apps/nginx \
  -f /tmp/tenant-repo/clusters/dev-01/values.yaml
#    ↑ 和 Argo CD 内部做的事一样：Helm 只收到一个本地绝对路径
```

> 💡 **这就是为什么「跨仓库」在本地不好调试**：
> Argo CD 的行为等价于上面第 ② 条 —— 把值文件解析成绝对路径再喂给 Helm。
> 本地排查时，把「另一个仓库」拉到本地任意目录，用绝对路径喂进去即可复现。
>
> ⚠️ 但**凭据问题本地复现不了** —— 那是 Argo CD 的事，
> 本地 `helm template` 根本不需要 Git 认证。

---

## 12. 排障

| 现象 | 根因 | 处理 |
|---|---|---|
| `repository "https://..." not found` | Argo CD 没有这个 URL 的凭据 → 匿名 → 私有库失败 | 配 Repository 凭据（§3.3） |
| `could not read Username` / `authentication failed` | 凭据不对（过期/scope 不够/仓库名错） | 换凭据 |
| 生成器报 `error in GetRepository` | 生成器仓库没配凭据 / 被 project scope 挡住 | 配 Repository 凭据；`project` 模板化时用全局凭据 |
| `file 'xxx' resolved to outside repository root` | 值文件路径越出了所属仓库根 | `$values/...` 的路径相对被引用仓库根；普通路径相对 `source.path` |
| `source referenced "values", but no source has a 'ref' field defined` | `$values` 前缀没有对应的 `ref` 源 | 在 `spec.sources` 里加 `ref: values` |
| `source referenced "values", which is not one of the available sources` | `ref` 名和 `$` 后的名字不一致 | `$values` ↔ `ref: values` 必须一致 |
| `source has a 'chart' field defined, but Helm charts are not yet supported for 'ref' sources` | ref 源里写了 `chart` | ref 源只能放文件（values / 清单） |
| `cannot reference a different revision of the same repository` | 同一个仓库被引用了两次且 revision 不同 | 统一 revision |
| 值文件改动没生效 | 渲染缓存 | `argocd app get <app> --refresh`；确认 ref 源的 commitSHA 变了 |
| 生成器能读，但 Application 没生成 | 模板里的变量名和生成器产出的对不上 | `missingkey=error` + 核对参数名（file generator 的字段是**平铺**的） |
| 多源同名资源互相覆盖 | 多源的合并语义：后者赢 | 看 `RepeatedResourceWarning`；调整 sources 顺序或改资源名 |
| 本地能渲染，集群里不行 | 本地只有一份 checkout，集群里是「多目录 + 跨源」 | 按 §11 用绝对路径复现；查 repo-server 日志 |
| 租户说「我的仓库 Argo CD 读不到」 | 大概率是**没给这个 URL 配凭据**，不是权限问题 | §3.3 + §10 清单 |

---

## 13. 关联文档

| 主题 | 文档 |
|---|---|
| CP 仓库 → Tenant 仓库的完整渲染链路 | [`appset-helm-Rendering.md`](./appset-helm-Rendering.md) |
| ApplicationSet 生成器与模板语法 | [`05-appset.md`](./05-appset.md) |
| AppProject / RBAC 边界 | [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| Repository 凭据（GitHub App / scoped repo） | [`07-repository-githubapp.md`](./07-repository-githubapp.md) |
| Helm 参数化与多源（上游） | [Argo CD 官方文档](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/) |
| 上游 Helm 文档（values / 参数优先级） | [Argo CD 官方文档](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/) |
| 上游 Repository CR 文档 | [Argo CD 官方文档](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/) |
