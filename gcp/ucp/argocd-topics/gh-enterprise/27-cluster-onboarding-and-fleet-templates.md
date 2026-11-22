# 27 · 集群纳管的模板生成：Makefile 能简化什么

> **直接回答**：「Argo CD 装好之后是长期 control plane，会不断有新集群要纳入管控，
> 需要生成对应的 YAML。**用 Makefile 能不能简化这类场景？这个方向值得考量吗？**」
>
> **一句话结论**
> ★ **值得考量，但收益不在"生成"这一步——那一步仓库里已经做得很好了。**
> 真正的收益在**「fleet（集群清单）视角」**：
> ① **模板生成已存在**（`new-cluster.sh`）→ Makefile 在这里只是**更好记的入口**；
> ② ★ **规模上来后的真问题不是"怎么生成"，而是"怎么对账"**——
> 「Git 里声明的集群」vs「Argo CD 里实际注册的集群」，**当前完全没有任何工具覆盖**；
> ③ ★ **Make 的依赖图 + 模式规则**正好适合"批量改一个字段 / 批量补齐 / 反向生成"这类 fleet 操作。
>
> ⚠️ **但有一条边界必须先划清**：Make 负责**「纳管」**（注册 + 工作负载），
> **不负责 GKE 集群的「生灭」**——后者是 Config Connector 的活（见 [`24 `3–4`](./24-gke-fleet-and-gcp-project-governance.md)）。

---

## 目录

| 章节 | 内容 |
|---|---|
| [`1](#1-现状盘点模板生成已经存在) | 加一个集群要 4 件事，谁负责，进不进 Git |
| [`2](#2-makefile-在这里能加什么) | **4 个增量**（V1 入口 / V2 对账 / V3 批量 / V4 干跑） |
| [`3](#3-什么进-git-什么不进) | **source 与 credential 的切分** |
| [`4](#4-边界纳管-vs-生灭) | ★ Make 不该碰的部分 |
| [`5](#5-值得做与不值得做) | **决策表** |
| [`6](#6-已落地与实测结果) | 本轮新增的东西 + 实测输出 |
| [`7](#7-坑清单) | 10 条 |

---

## 1. 现状盘点：模板生成已经存在

**当前仓库已有的能力**（[`../examples/gitops-layout/`](../examples/gitops-layout/README.md)）：

| # | 加一个集群要做的事 | 谁负责 | 进 Git？ | 幂等吗 |
|---|---|---|---|---|
| ① | 建 `bootstrap/clusters/<name>/cluster.yaml` | `new-cluster.sh` | ✅ **是**（AppSet 的输入） | 目录已存在则拒绝 |
| ② | 建 `components/<component>.yaml` | `enable-component.sh` | ✅ **是** | 同上 |
| ③ | 在 AppProject 的 `destinations` 里加这个集群 | `new-cluster.sh`（用 awk 插入，保留注释与格式） | ✅ **是** | 已存在则跳过 |
| ④ | 注册 Argo CD Cluster Secret（含凭据） | **手工**（脚本只打印命令） | ❌ **否** | — |
| ⑤ | 自检 | `validate-clusters.py` + `appset-simulator.py` | — | — |

> ★ **关键观察**：这 4 件事**已经被自动化了，而且做得不错**——
> 字段只填一次、其它地方自动保持一致、生成完立刻自检、凭据明确不进 Git。
> → **"用 Makefile 简化模板生成"这个诉求，仓库里 80% 已经解决了。**

---

## 2. Makefile 在这里能加什么

### V1 · 统一入口（零成本，收益小）

```bash
# 以前：要记一长串 flag
./new-cluster.sh --name dev-03 --env dev --project acme-platform-dev     --server https://dev-03.k8s.example.com --component nginx --component api

# 现在：变量式，且 help 里能查到
make new-cluster NAME=dev-03 ENV=dev PROJECT=acme-platform-dev \
     SERVER=https://dev-03.k8s.example.com COMPONENTS="nginx api"
make new-cluster DRY_RUN=1 ...      # 只预览，不落盘
```

> 价值不在功能，在**可发现性**：`make help` 就是这个仓库的运维手册。

### V2 · ★★ Fleet 对账（**当前完全空白，价值最高**）

**这是长期 control plane 才出现的问题**（集群从 4 个变成 40 个之后）：

| 症状 | 为什么难发现 |
|---|---|
| **① Git 声明了、Argo CD 没注册** | 该集群的 Application 报 `Unable to connect`，而且**只有跑到那个集群才看得到** |
| **② Argo CD 注册了、Git 没声明** | ★ 有人在控制面里"偷偷"纳管了一个集群——**没走 PR、没走审批、没人知道** |
| **③ 两边都有，但 server URL 写错** | 应用连到"看起来对"的地址，最难查的一类 |

**核查过现有工具**：`validate-clusters.py` 只校验 Git **内部**的一致性
（cluster.yaml ↔ components ↔ AppSet destinations ↔ AppSet 展开）；
`appset-simulator.py` 同样只看 Git 侧。
→ **没有任何工具把 Git 声明和 Argo CD 的实际状态对账过。**

**已实现**：`fleet.py drift`（见 `6），从 Argo CD 命名空间里的
cluster secret（标签 `argocd.argoproj.io/secret-type=cluster`）读出实际注册的集群，
与 `bootstrap/clusters/*/cluster.yaml` 三方比对。

### V3 · 批量操作（等集群变多时再做）

Make 的**依赖图 + 模式规则**天生适合这类：

| 批量需求 | Make 的对应能力 |
|---|---|
| 给所有 dev 集群加一个组件 | 模式规则 + `$(wildcard)` 遍历 |
| 全部集群换 project / region | 单一模板源 + 批量重生成（**改一处，不改 N 处**） |
| 补齐缺失的 cluster.yaml | 幂等 apply：已存在就跳过，不存在才生成 |
| 反向生成（从实际注册反推清单） | `make fleet-drift` 给出差异，人/脚本补齐 |

> ★ 这里的核心价值是**"单一模板源"**：
> 集群的字段如果散落在 N 个 YAML 里，改一次要改 N 处；
> 如果由一个模板生成，改模板 + 重跑即可。
> **但**这与"既存源又存产物"的红线（[`26 `5 R4`](./26-makefile-in-gitops.md)）有张力——
> 正确做法是：**模板进 Git、产物进 Git，但产物由模板生成且受校验**（`fleet.py drift` 就是那个校验）。

### V4 · 干跑是一等公民

| 手段 | 用法 |
|---|---|
| Make 内置 | `make -n new-cluster ...`（打印命令，不执行） |
| 脚本内置 | `DRY_RUN=1`（**真正实现了"打印将要生成的 YAML"**） |

> ★ 模板生成是**写操作**，写操作必须先能"看一眼"。
> 仓库里 `new-cluster.sh --dry-run` 已经做到了"打印生成内容"，Make 只是把它提升为统一入口。

---

## 3. 什么进 Git、什么不进

> **这是这类场景唯一真正要小心的事。**

| 内容 | 进 Git？ | 为什么 |
|---|---|---|
| `bootstrap/clusters/<name>/cluster.yaml` | ✅ | AppSet 的输入；**Git 里的集群事实源** |
| `bootstrap/clusters/<name>/components/*.yaml` | ✅ | 文件的存在 = 该集群启用该组件 |
| AppProject 的 `destinations` | ✅ | 权限边界，必须进 Git 进 review |
| `bootstrap/clusters/_templates/` | ✅ | ★ **模板本身进 Git** → 改模板可批量再生 |
| **Argo CD Cluster Secret** | ❌ | **含凭据** → 只打印命令，手工执行 |
| GitHub App 私钥 / SA token | ❌ | 同上（见 [`24 `7`](./24-gke-fleet-and-gcp-project-governance.md)） |

> ★ **为什么 cluster secret 不能进 Git**：
> 它是**凭据**，而 Git 是**所有有仓库读权限的人都能读**的地方
> （包括 CI、包括 Argo CD 自己的 repo-server）。
> → 仓库里的 `argocdClusterSecret: <name>` **只是一个名字引用**，不是凭据本身。
> 这个切分已经在 `new-cluster.sh` 里做对了，Make **不要改变它**。

---

## 4. 边界：纳管 vs 生灭

| | 含义 | 谁做 | 为什么 |
|---|---|---|---|
| **纳管** | 注册集群 + 往里部署工作负载 | ★ **Make + 脚本**（本节讨论的） | 可逆、低风险、值得自动化 |
| **生灭** | **创建/删除 GKE 集群、Project** | ❌ **不是 Make** → Config Connector / 人工 | **不可逆**（见 [`24 `4`](./24-gke-fleet-and-gcp-project-governance.md)） |

> ⚠️ **一个常见误解**：既然 Argo CD 是 control plane，是不是应该让它"管"集群的创建？
> **不应该。** 理由在 [`24 `4.1`](./24-gke-fleet-and-gcp-project-governance.md)：
> 删除 project 会连带删除其下所有资源；集群重建会丢状态。
> → **Argo CD 管"工作负载的期望状态"；GCP 侧资源的"存在/消失"由人 + CGP 管。**
>
> Make 在这里同样适用：**Make 可以生成"要创建一个集群"的 YAML 草稿供人审阅，
> 但不要让 Make 直接执行"创建集群"。**

---

## 5. 值得做与不值得做

| 想法 | 值不值得 | 理由 |
|---|---|---|
| ★ **Fleet 对账（`fleet.py drift`）** | **★★ 最值得** | 当前完全空白；长期 control plane 的核心健康指标；能发现"控制面里的幽灵集群" |
| **批量操作（批量改字段/批量加组件）** | **★ 值得（等集群变多）** | Make 的依赖图 + 模式规则正好合适；能把"改 N 处"变成"改一处" |
| **统一入口（`make new-cluster`）** | ★ 值得（零成本） | 收益在可发现性，不在功能 |
| **干跑优先（DRY_RUN / `make -n`）** | ★ 值得 | 写操作必须能先看 |
| 用 Make 替换 `new-cluster.sh` | ❌ **不值得** | 脚本已经做得很对；重写只会引入回归 |
| 把 cluster.yaml 改成 Make 渲染（CMP） | ❌ **暂不值得** | 会让人失去"可读的 YAML"；Kustomize/Helm 够用（[`26 `3 P2`](./26-makefile-in-gitops.md)） |
| 用 Make 取代 CR Check 做门禁 | ❌ **不行** | 权威性问题：谁跑谁说了算（[`26 `5 R1`](./26-makefile-in-gitops.md)） |
| 让 Make 直接创建/删除 GKE 集群 | ❌ **不行** | 不可逆操作不该由模板工具触发 |

---

## 6. 已落地与实测结果

### 6.1 本轮新增

| 文件 | 作用 |
|---|---|
| [`examples/gitops-layout/fleet.py`](../examples/gitops-layout/fleet.py) | ★ **新增**：`list`（集群 × 组件矩阵）+ `drift`（Git ↔ Argo CD 对账） |
| [`examples/gitops-layout/Makefile`](../examples/gitops-layout/Makefile) | **扩展**：`new-cluster` / `enable-comp` / `cluster-check` / `fleet-list` / `fleet-drift` 五个目标 |

### 6.2 实测输出

```
$ make fleet-list

集群清单（4 个）
─────────────────────────────────────────────────────────────────────
  集群       api         gatekeeper  gateway     nginx       redis
─────────────────────────────────────────────────────────────────────
  dev-01   ●           ●           ●           ●           ●
  dev-02   ●           ●           ●           ●           ·
  prod-01  ●           ●           ●           ●           ·
  prod-02  ●           ●           ●           ●           ·
─────────────────────────────────────────────────────────────────────
  ● 已启用   · 未启用

环境分布：  dev=2  prod=2
```

```
$ make new-cluster                       # 缺参数
用法: make new-cluster NAME=<cluster> ENV=<dev|stg|prod> PROJECT=<gcp-project> SERVER=<url> [COMPONENTS="a b"]
make: *** [new-cluster] Error 1

$ make new-cluster NAME=dev-99 ENV=dev PROJECT=acme-dev       SERVER=https://dev-99.k8s.example.com COMPONENTS="nginx api" DRY_RUN=1
==> ① 生成 bootstrap/clusters/dev-99/cluster.yaml
    cluster: dev-99
    server: https://dev-99.k8s.example.com
    env: dev
    project: platform-dev
    ...
✓ cluster.yaml
==> ② 生成组件启用清单
==> ③ 把集群加进 AppProject platform-dev 的 destinations
...
（DRY_RUN=1 → 只打印，不落盘；已验证 bootstrap/clusters/ 未被改动）
```

```
$ make fleet-drift                       # 本机没有集群访问权限
⚠ 无法对账：调用 kubectl 失败: ... timed out after 15 seconds
  （没有集群访问权限时这是正常的；Git 侧清单仍然有效）
$ echo $?
0
```

> ★ `fleet-drift` 在**没有集群访问权限时优雅降级**（退出码 0），
> 因为"看不到实际状态"不等于"有差异"。
> 需要它参与门禁时用 `FLEET_STRICT=1 make fleet-drift`（有差异即退出码非 0）。

### 6.3 建议的接入点

| 时机 | 动作 |
|---|---|
| **现在** | 把 `make fleet-list` 放进交接文档；`make fleet-drift` 加进每周巡检（[`08-implementation-playbook.md `10.4`](../08-implementation-playbook.md)） |
| **集群 > 10 个** | 开始做批量操作（V3），并把 `cluster.yaml` 收敛成"模板 + 生成" |
| **接 CR 门禁时** | `make ci` / `make cluster-check` 由 CR Check 调用（[`26 `6 S2`](./26-makefile-in-gitops.md)） |
| **准备生产纳管前** | ★ 跑一次 `make fleet-drift`，确认没有"控制面里的幽灵集群" |

---

## 7. 坑清单

| # | 坑 | 后果 | 规避 |
|---|---|---|---|
| 1 | 把 Cluster Secret 的 YAML 生成进 Git | **凭据泄漏** | 只生成命令，不生成文件（现状已正确） |
| 2 | 让 Make 直接创建/删除 GKE 集群 | 不可逆 | 生灭交给 CGP / 人 |
| 3 | 生成器与产物都进 Git 且**不校验** | 两份真相、慢慢漂移 | `make fleet-drift` 定期对账 |
| 4 | 批量重生成覆盖了人工改动 | 手工修复被冲掉 | 生成前先 `DRY_RUN=1` / `git diff` |
| 5 | 忘了 `.PHONY` | 目标"已存在"被跳过 | 全部目标列进 `.PHONY` |
| 6 | `make new-cluster` 忘了给 SERVER | 生成的清单和实际注册对不上 → drift 报警 | 强制要求 SERVER（已实现） |
| 7 | 组件清单字段与 AppSet 的 flatten 列表不一致 | `missingkey=error` → **整个 AppSet 报错** | `make cluster-check`（已实现） |
| 8 | drift 检查在无权限环境里报"有差异" | 假告警，久了就没人看 | 无权限时退出码 0 并说明（已实现） |
| 9 | 集群命名与环境不一致（`dev-03` vs `prd-01`） | AppProject 归属错乱 | 沿用 `<env>-<后缀` 约定 + 校验 |
| 10 | 把 `make fleet-drift` 的结果当成"事实"直接删集群 | 删错 | drift 只**报告**，处置走 PR |

---

## 关联文档

- 上一级：[`26 Makefile × Argo CD`](./26-makefile-in-gitops.md)（Make 在 GitOps 里的定位与红线）
- GCP 侧治理与护栏：[`24 GKE 纳管与 GCP Project 治理`](./24-gke-fleet-and-gcp-project-governance.md)
- 集群清单与引导层：[`../examples/gitops-layout/bootstrap/clusters/README.md`](../examples/gitops-layout/bootstrap/clusters/README.md)
- 静态检查工具箱：[`../examples/README.md`](../examples/README.md)
- 实施与巡检：[`../08-implementation-playbook.md`](../08-implementation-playbook.md)
