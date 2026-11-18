# Artifact Registry Cleanup Policy 评估报告

> **评估对象**：Artifact Registry（AR）仓库上的 **Cleanup policy**（控制台路径：*Artifact Registry → Repositories → 选择仓库 → Edit Repository → Cleanup policies*）。
> **文档定位**：一份「能直接拿去改配置 + 能直接拿去评审风险」的评估稿，覆盖参数模型、调整方式、删除时间逻辑、以及"镜像还在被使用"的风险判定。
> **事实来源**：AR v1 API schema（discovery revision `20261107`）、官方文档 *Configure cleanup policies* / *Cleanup policy overview* / *Quotas and limits*（2026-11-17 更新）、`gcloud` SDK 源码 `command_lib/artifacts/cleanup_policy_util.py`。
> **本报告的边界**：撰写环境对目标项目 **没有 Artifact Registry 读取权限**（`artifactregistry.googleapis.com` 返回 `CONSUMER_INVALID`），因此**未对线上仓库做实测**。所有结论来自官方 schema/文档 + 本地脚本推演（脚本见 `scripts/cleanup-policy-audit.sh`，附离线 fixture 自测通过）。**第 3 节给了 6 步补齐线上数据的操作，拿到权限后跑一遍即可把本报告从"通用评估"升级为"针对该仓库的评估"。**

---

## 0. TL;DR（结论先行）

| # | 结论 | 影响 |
|:--|:--|:--|
| 1 | Cleanup policy **不是独立资源**，是 `Repository.cleanupPolicies` 这个 map 字段；`set-cleanup-policies` 用 `updateMask=cleanup_policies`，**整表替换** | 只写一条策略文件 = **把其它策略全删掉**（连带它们保护的镜像一起进入删除队列） |
| 2 | 命中规则：同一条策略内各条件 **AND**；数组内 **任一前缀命中即算命中** | `tagPrefixes` 写宽一个字符就可能多删一大批 |
| 3 | 多条 DELETE 同时命中 → **保留期最短者胜出**；KEEP 命中 → 一律保留 | 新增一条激进的 DELETE 策略 = 全局保留期被缩短，**极易踩坑** |
| 4 | `olderThan` 从 **版本在仓库中的 createTime** 起算；后台作业周期执行，**变更约 1 天内生效** | 实际删除时间 ≈ `createTime + olderThan + (0~1 天)`；`olderThan=0d` 也不是立刻删 |
| 5 | 删除版本 **不会** 立刻杀死运行中的 Pod（节点已缓存 layer），但会在**扩容/重启/滚动更新/回滚**时炸 `ImagePullBackOff` | 风险是**延迟爆发**的，不会当场报警 |
| 6 | tag 会被"移动"：tag 一旦改指向新 digest，旧 digest 立刻变成 `UNTAGGED` | 预发布 tag 被 `latest` 覆盖后，旧镜像当天就进入 untagged 清理队列 |
| 7 | **非 Docker 格式（npm/maven/python/apt/yum/go…）没有 tag**，一律视为 `UNTAGGED` | 对这类仓库用 `tagState=ANY/UNTAGGED` 的 DELETE ≈ "按年龄删一切版本"，npm/maven 的 `versionName` 也不在保护范围内 |
| 8 | `dockerConfig.immutableTags=true` 时 **tagged 版本不会被删** | 策略看起来生效了，实际只清了 untagged —— 容易误判 |
| 9 | 清理策略导致的删除**计入 delete 配额**，且有**每仓库每天删除数上限** | 大批量清理会撞配额，被截断后残留 |
| 10 | 删除**不可逆**；底层 layer **每日**才回收 | 存储费用下降有 1 天+ 延迟；误删无法回滚 |

---

## 1. 对象模型：它到底是什么、在哪一层

### 1.1 层级

```
projects/<project>/locations/<location>/repositories/<repository>     ← Repository（唯一有 cleanup policy 的资源）
   └── cleanupPolicies : map<string, CleanupPolicy>                    ← key = 用户自定义的策略 ID
```

* AR v1 API **没有** `cleanupPolicies.get/list/create` 这类独立方法；一切读写都走 **Repository 的 update**（PATCH）。
* CLI 对应的三个包装命令（GA）：

| 命令 | 作用 | 底层 |
|:--|:--|:--|
| `gcloud artifacts repositories list-cleanup-policies REPO` | 列出策略（JSON，可直接当策略文件回灌） | GET repository |
| `gcloud artifacts repositories set-cleanup-policies REPO --policy=FILE` | **全量**设置策略 | PATCH `updateMask=cleanup_policies` |
| `gcloud artifacts repositories delete-cleanup-policies REPO --policynames=a,b` | 删除指定策略 | PATCH（先读后写，整资源更新） |

### 1.2 三种策略类型（互相独立，不能混用）

| 类型 | API 形态 | 作用 | 注意 |
|:--|:--|:--|:--|
| **Conditional delete** | `action=DELETE` + `condition` | 命中即删 | 必须有 `name` + `action` + **至少一个** condition |
| **Conditional keep** | `action=KEEP` + `condition` | 命中即豁免删除 | keep **本身不删任何东西**，想删必须有配套 delete |
| **Keep most recent versions** | `action=KEEP` + `mostRecentVersions` | 每个包保留最近 N 个版本 | 与 `condition` 是 **union**，同一策略里**不能同时出现** |

> 官方原文：*"A keep policy only exempts matching artifacts from deletion; it doesn't delete artifacts."*
> **KEEP 优先级高于 DELETE**：同一版本同时命中 delete 和 keep → **保留**。

### 1.3 适用范围

* ✅ `STANDARD_REPOSITORY`、`REMOTE_REPOSITORY`
* ❌ `VIRTUAL_REPOSITORY`、AOSS 仓库、以及"项目级"策略
* 单仓库策略数上限：**10 条**
* 单仓库每天清理删除数上限：官方两处口径不一致（*Quotas and limits* 写 **300,000**；*Cleanup policy overview* 写 **600,000**）→ **以账号所在区域的 quota 页面为准**，清理前先核对。

---

## 2. 参数全表（支持哪些参数 / 怎么调）

### 2.1 三层参数

**第一层：Repository 级开关**

| API 字段 | 策略文件 | 控制台 | Terraform | 说明 |
|:--|:--|:--|:--|:--|
| `cleanupPolicies` | 文件整体 | Cleanup policies 区域 | `cleanup_policies {}` | 策略集合，key = 策略 ID（仓库内唯一，<128 字符） |
| `cleanupPolicyDryRun` | `--dry-run` / `--no-dry-run` | `Dry run` / `Delete artifacts` 单选 | `cleanup_policy_dry_run` | **true = 只演练不删**（仓库级总闸） |

**第二层：CleanupPolicy**

| API 字段 | 策略文件 | Terraform | 取值 | 说明 |
|:--|:--|:--|:--|:--|
| `id` | `name` | `id` | string | 策略 ID |
| `action` | `action.type` | `action` | `DELETE` / `KEEP`（策略文件里官方示例写作 `"Delete"` / `"Keep"`） | 动作 |
| `condition` | `condition` | `condition {}` | — | 条件（与 `mostRecentVersions` 二选一） |
| `mostRecentVersions` | `mostRecentVersions` | `most_recent_versions {}` | — | 保留最近 N 个（仅 KEEP） |

**第三层：条件字段（CleanupPolicyCondition）**

| 字段 | Terraform | 取值 | 语义 | 风险提示 |
|:--|:--|:--|:--|:--|
| `tagState` | `tag_state` | `TAGGED` / `UNTAGGED` / `ANY`（默认 `ANY`） | 按"版本当前是否被 tag 引用"筛选 | 非 Docker 格式**恒为 UNTAGGED** |
| `tagPrefixes[]` | `tag_prefixes` | 字符串数组 | tag 前缀，**任一命中** | **必须**同时 `tagState=TAGGED`，否则条件永远不成立（静默不删） |
| `versionNamePrefixes[]` | `version_name_prefixes` | 字符串数组 | 版本名前缀，任一命中 | Docker 里版本名是 `sha256:...`（几乎用不上）；npm/maven 里是 `1.2.3`（很好用） |
| `packageNamePrefixes[]` | `package_name_prefixes` | 字符串数组 | 包名前缀，任一命中 | Docker 里是镜像名；**前缀匹配不是精确匹配**（`web` 会命中 `webapp`） |
| `olderThan` | `older_than` | duration（`30d`/`12h`/`90s`；API 内部为秒） | 版本年龄 ≥ 该值 → 命中 | **这是"保留期"的语义，不是"立即删除"** |
| `newerThan` | `newer_than` | duration | 版本年龄 ≤ 该值 → 命中 | 与 `olderThan` 同时用 = 只删"中间窗口"内的版本，**极易误用** |
| — | — | `versionAge` | 旧版策略文件里出现过的字段名（CLI 会把它的值折算成秒）；当前 API schema 未列出该字段 | 新配置统一用 `olderThan`，不要依赖它 |

**Keep most recent versions 子字段**

| 字段 | Terraform | 说明 |
|:--|:--|:--|
| `packageNamePrefixes[]` | `package_name_prefixes` | 限定作用范围；**省略 = 全仓库每个包都算** |
| `keepCount` | `keep_count` | 每个包保留的最近版本数 |

> ⚠️ 官方 Caution 原文（Conditional keep 与 most-recent 两节都有）：
> *"If packageNamePrefixes is specified, Artifact Registry will only keep the most recent versions of packages matching the specified package prefixes."*
> 也就是说 **keep 策略里写 `packageNamePrefixes` 会把保留范围收窄成"这些包的最近版本"**，而不是"这些包的全部版本"。这是很容易与预期不符的一条，建议 keep 策略优先用 `tagPrefixes` / `versionNamePrefixes` 表达意图。

### 2.2 匹配语义（务必记住的四条）

1. **同一条策略内：所有给出的条件必须同时满足（AND）。**
2. **同一条件内的数组：任一元素前缀命中即可（OR）。**
3. **多条 DELETE 同时命中同一版本 → 保留期最短的那条生效。**
   官方示例：策略1 = `tagPrefixes=commit-*` + `olderThan=24h`；策略2 = `tagState=TAGGED` + `olderThan=7d`。
   一个 `commit-1234` 标签的镜像同时命中两条 → **24 小时后删**。
   👉 **推论：新增一条"看起来只影响某类 tag"的 DELETE 策略，可能把全局保留期从 7 天砍到 1 天。**
4. **KEEP 命中 → 保留**，无论 DELETE 有几条命中。

另外：多条策略时按顺序应用，但 **KEEP 命中即终止删除**（官方例子：150 天、`default` 标签、`2.0.6` 版本的镜像，虽然命中两条 delete，但因为命中 keep（版本前缀 `2.0.6`）而被保留）。

### 2.3 如何调整（三种落地方式）

**① 控制台（适合手工探索）**
`Repositories → 选中仓库 → Edit Repository → Cleanup policies`：
选 `Dry run` 或 `Delete artifacts` → `Add a cleanup policy` → 填 Name / Policy type / Tag state / Tag prefixes / Version prefixes / Package prefixes / Older than / Newer than → `Update`。

**② gcloud CLI（适合脚本化）**

```bash
# 0) 备份当前策略（list 输出可直接当策略文件回灌）
gcloud artifacts repositories list-cleanup-policies example-repo \
  --project=example-project --location=us-central1 > policies.json

# 1) 编辑 policies.json（数组，每项：name / action.type / condition|mostRecentVersions）

# 2) 演练：先开 dry run
gcloud artifacts repositories set-cleanup-policies example-repo \
  --project=example-project --location=us-central1 \
  --policy=policies.json --dry-run

# 3) 真实生效（务必显式带 --no-dry-run）
gcloud artifacts repositories set-cleanup-policies example-repo \
  --project=example-project --location=us-central1 \
  --policy=policies.json --no-dry-run

# 4) 删除单条策略
gcloud artifacts repositories delete-cleanup-policies example-repo \
  --policynames=delete-untagged \
  --project=example-project --location=us-central1
```

> 🚨 **两个 CLI 陷阱（已从 SDK 源码 `cleanup_policy_util.py` + 命令 YAML 确认）**
> 1. **整表替换**：`set-cleanup-policies` 的 `updateMask=cleanup_policies`，**只写 1 条策略文件 = 其它策略全部消失**。它们原本保护的镜像会立刻失去豁免。→ 永远"先 list 导出 → 改 → 全量 set"。
> 2. **`--dry-run` / `--no-dry-run` 与 `--policy` 相互独立**：只传 `--policy` 时，dry-run 开关**保持原值不变**。
>    - 仓库当前是 dry run → 你以为"应用了策略"，其实仍不会删（相对安全）。
>    - 仓库当前是真实模式 → 你只是加了一条策略，**约 1 天后后台作业就会开始删**（危险）。
>    → **每次变更都显式写 `--dry-run` 或 `--no-dry-run`**。

**③ Terraform（适合 IaC 化，推荐用于多仓库统一治理）**

```hcl
resource "google_artifact_registry_repository" "example_repo" {
  location      = "us-central1"
  repository_id = "example-repo"
  format        = "DOCKER"

  cleanup_policy_dry_run = true          # 先演练，验证通过再改 false

  cleanup_policies {
    id     = "delete-untagged-old"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "14d"
    }
  }

  cleanup_policies {
    id     = "keep-release"
    action = "KEEP"
    condition {
      tag_state    = "TAGGED"
      tag_prefixes = ["release-"]
    }
  }

  cleanup_policies {
    id     = "keep-last-10"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
}
```

* 走 IaC 的额外好处：策略变更进 Git、走 code review、多仓库策略不会漂移。
* 注意 Terraform 的 `cleanup_policy_dry_run` 是**布尔字面量**，可以做成 `var.enable_cleanup ? false : true` 这样的开关。

**④ 直接 REST（应急/排障）**

```bash
curl -X PATCH \
  "https://artifactregistry.googleapis.com/v1/projects/example-project/locations/us-central1/repositories/example-repo?updateMask=cleanupPolicies,cleanupPolicyDryRun" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{"cleanupPolicies":{...},"cleanupPolicyDryRun":true}'
```

---

## 3. 运行评估（可执行）

### 3.1 六步评估流程

| 步 | 动作 | 命令 | 产出 |
|:--|:--|:--|:--|
| 1 | 读仓库与策略现状 | `gcloud artifacts repositories describe REPO --format=json` | `cleanupPolicies` / `cleanupPolicyDryRun` / `dockerConfig.immutableTags` / `format` / `sizeBytes` |
| 2 | 导出策略快照（可回灌） | `gcloud artifacts repositories list-cleanup-policies REPO` | 策略数组 |
| 3 | 盘点版本清单 | `gcloud artifacts packages list` + `gcloud artifacts versions list` | 每个版本的 `createTime` / `updateTime` / tag |
| 4 | **离线推演命中集** | `scripts/cleanup-policy-audit.sh` | 「谁会被删、何时删、是否仍被引用」 |
| 5 | **官方 dry run** | `set-cleanup-policies --dry-run` + 审计日志 | 平台侧真实待删清单 |
| 6 | 与使用方交叉比对 | 脚本 `--kube-context` / Cloud Run / IaC 源码 | 「删了会出事」清单 |

> 第 4 步的推演脚本**复刻了官方语义**（tagState / 前缀任一命中 / AND 组合 / keep 优先 / most-recent 计数 / oldest-retention 胜出），用来在**不开启 dry run** 的前提下先看一遍影响面；第 5 步是平台侧权威结果，两者应当对齐（差异出现时以平台为准，并回头核对语义实现）。

### 3.2 脚本用法

```bash
# 只看策略与推演结果
gcp/artifact-registry/scripts/cleanup-policy-audit.sh \
  --project example-project --location us-central1 --repository example-repo

# 加上 GKE 交叉比对（标出"删了仍被引用"的版本）
gcp/artifact-registry/scripts/cleanup-policy-audit.sh \
  --project example-project --location us-central1 --repository example-repo \
  --kube-context my-cluster --json
```

输出示例（离线 fixture 自测结果）：

```
生效策略 (4 条，仓库上限 10):
  - [DELETE] delete-untagged     tagState=UNTAGGED olderThan=604800s
  - [DELETE] delete-prerelease  tagState=TAGGED tagPrefixes=alpha olderThan=2592000s
  - [KEEP]    keep-release      tagState=TAGGED tagPrefixes=release packageNamePrefixes=webapp
  - [KEEP]    keep-recent       mostRecentVersions.keepCount=2 mrv.packageNamePrefixes=webapp
版本总数: 5   会被删除: 2   因 keep 策略保留: 2

PACKAGE   VERSION          AGE(d)  TAGS      命中策略 / 引用
api       sha256:eeee5555  109.4   -         delete-untagged  ⚠ 仍被引用: spec:Deployment/prod webapp
webapp    sha256:bbbb2222  48.4    alpha-0.  delete-prerelease
```

### 3.3 dry run 与审计日志（平台侧权威结果）

开启 dry run（仓库级）后，AR 后台作业会以 `validateOnly=true` 发起 `BatchDeleteVersions`，**不会真正删除**。

```bash
# 开启 dry run
gcloud artifacts repositories set-cleanup-policies example-repo \
  --project=example-project --location=us-central1 \
  --policy=policies.json --dry-run

# 等待 ≥ 1 天（后台作业周期），然后查审计日志
gcloud logging read \
  'protoPayload.serviceName="artifactregistry.googleapis.com"
   AND protoPayload.request.parent="projects/example-project/locations/us-central1/repositories/example-repo/packages/-"
   AND protoPayload.request.validateOnly=true' \
  --resource-names="projects/example-project" \
  --project=example-project \
  --format="table(protoPayload.requestMetadata.callerSuppliedUserAgent, protoPayload.request.names)"
```

> ⚠️ 审计日志要能看到这条，**必须显式开启 Artifact Registry 的 DATA_WRITE 数据访问日志**（默认不开）。
> 没开 → dry run 什么也查不到 → 会误以为"dry run 没删东西 = 策略没命中"。

真实删除（关闭 dry run）后，同样的日志查询去掉 `validateOnly=true` 条件即可看到真实删除记录，执行者是 AR 服务账号 `service-<PROJECT_NUMBER>@gcp-sa-artifactregistry.iam.gserviceaccount.com`（该 Service Agent 默认自带 `artifactregistry.versions.delete`）。

### 3.4 需要的权限

| 目的 | 权限 |
|:--|:--|
| 读仓库/策略/版本 | `artifactregistry.repositories.get/list`、`artifactregistry.versions.list` |
| 改策略 | `artifactregistry.repositories.update`（如 `roles/artifactregistry.admin`） |
| 触发删除 | `artifactregistry.versions.delete`（由 AR Service Agent 持有） |

---

## 4. 删除时间逻辑专项分析

### 4.1 时间基准

* `olderThan` / `newerThan` 都基于 **`Version.createTime`（版本在本仓库被创建的时间）**，不是"镜像构建时间"，也不是"最后一次 push 时间"。
* `Version.updateTime` 会在重新打 tag / 更新 metadata 时刷新，但 **cleanup policy 不看 updateTime**。
  → 推论（建议用 dry run 验证）：**给一个老镜像重新打上新 tag，并不会让它"变年轻"**，它仍处于原有保留期之外，UNTAGGED 规则随时可删。唯一的例外是：该版本因为重新打 tag 变成 TAGGED，且有 keep 策略保护。

### 4.2 实际删除时间

```
最早可删时间 = createTime + olderThan
实际删除时间 = 最早可删时间 + Δ(0 ~ 约 1 天)     ← 后台作业周期 + 策略变更生效延迟
```

* "策略变更约 1 天内生效"、"dry run / active run 由周期后台作业执行"（官方原文）。
* 所以：
  * `olderThan=0d` **不是**立即删，仍要等作业跑一轮。
  * 想"今晚就清掉"，必须按 **`olderThan + 1~2 天`** 来做容量与影响面预期。
  * 反过来，**回滚策略也不是立刻止血**：已经被删的版本不可恢复，只能靠策略提前用 KEEP 兜住。

### 4.3 会导致"意外提前删除"的六类场景

| # | 场景 | 机制 | 后果 |
|:--|:--|:--|:--|
| 1 | 新增了一条 DELETE 策略 | 多条 DELETE 命中 → **最短保留期胜出** | 全局保留期被悄悄缩短 |
| 2 | `set-cleanup-policies` 只写了一部分策略 | 整表替换，未列出的策略消失 | 原豁免失效 → 大批版本进入删除队列 |
| 3 | tag 被移动（`latest` 指向新 digest） | 旧 digest 立刻变 `UNTAGGED` | 预发布镜像当天进入清理范围 |
| 4 | 对 **npm/maven/python** 等无 tag 格式用了 `tagState=ANY/UNTAGGED` | 这些格式恒为 UNTAGGED | 等价于"按年龄删全部版本"，`versionName` 需另配 keep |
| 5 | `olderThan` 与 `newerThan` 同时使用 | 变成"只删中间窗口" | 与直觉（"删旧的留新的"）完全相反 |
| 6 | 从 gcr.io 迁移过来的仓库 | 迁移后 `createTime` = **拷贝到 AR 的日期**，不是原始上传日期 | 老镜像看起来"很新"→ 短期安全；但一旦被删，无法按原始上传时间复算/申诉 |

### 4.4 Docker manifest 的二阶效应

* AR **不会**删除被"父 manifest"引用的子镜像；
* 但**父 manifest 被删之后**，相关子镜像会在**下一次**清理作业中被删。
  → 一次清理会**分两波**产生影响，第一波看 dry run 日志，第二波才显现，做容量/影响评估时要把这一波算进去。

### 4.5 删除 ≠ 立刻释放存储

删除版本不会立即删除底层 layer；**未被引用的 layer 每日回收**。
→ 存储/费用下降有 **1 天以上延迟**，不要用"第二天账单"判断策略是否生效。

---

## 5. 风险与依赖评估

### 5.1 关键问题：镜像"是否正在被使用"？

#### 结论

> **删除 AR 里的一个版本，不会让正在运行的 Pod 立刻挂掉，但会让"未来任何一次需要拉取该镜像"的操作失败。**
> 容器启动时已经把镜像内容解引用到具体 digest 并落到节点本地，AR 侧的删除不影响已运行容器。
> **风险是延迟爆发的**，典型触发点：

| 触发场景 | 现象 | 严重度 |
|:--|:--|:--|
| 节点扩容 / 新节点加入 | 新 Pod `ErrImagePull` | 高 |
| 节点重启 / 升级 / 重建 / 磁盘回收 | 全量 Pod 重启后拉不到镜像 → `ImagePullBackOff` | **极高** |
| Pod 被驱逐 / OOM / 节点掉电后重建 | 同上 | 高 |
| 滚动更新 / 回滚到旧 tag | 回滚失败（老 digest 已不存在） | 高 |
| CI 重建时拉 base image / 复现构建 | 构建失败 | 中 |
| 一次性批量清理命中大量在用镜像 | 大面积 `ImagePullBackOff`，可能牵连非 AR 依赖的副本 | 极高 |

> GKE **节点镜像本身**来自 GKE 专用仓库，**不受 AR cleanup policy 影响**；受影响的是用户工作负载镜像。

#### 判定方法（必须按 **digest** 比对，不能按 tag）

* tag 是可移动的：Deployment 里写 `:v1.0`，实际可能是任意 digest；而 AR 侧同 tag 已指向新 digest。
  → 正确做法：把工作负载引用的 tag **解析成 digest**，再和 AR 里将被删除的版本 digest 比对。
* 采集面：

| 来源 | 命令 | 字段 |
|:--|:--|:--|
| GKE 工作负载（期望态） | `kubectl get deploy,sts,ds,rs,job,cronjob -A -o json` | `spec.template.spec.containers[].image`、`initContainers[].image` |
| GKE 运行中 Pod（实际态） | `kubectl get pods -A -o json` | `status.containerStatuses[].image` 与 `.imageID`（`...@sha256:...`） |
| Cloud Run | `gcloud run services list --format=json` | `spec.template.spec.containers[].image`、各 revision |
| GCE / MIG | `gcloud compute instances list`、`instance-groups describe` | 启动脚本 / 镜像字段 |
| IaC / GitOps 源码 | `rg 'docker.pkg.dev' **/*.yaml **/*.tf` | 硬编码的 tag/digest |
| CI | `rg 'docker.pkg.dev' .gitlab-ci.yml .github/` | 构建依赖的 base image |

  ⚠️ 只查 **spec** 不够：**Pod 实际运行的 `imageID` 才是"此刻真正被依赖的 digest"**。回滚过的 Deployment、spec 与 status 不一致的 Pod，只有 status 才看得到。
  ⚠️ 也不要漏掉 **initContainer / sidecar / Job / CronJob / HPA 触发的模板**。

* 脚本 `cleanup-policy-audit.sh --kube-context <ctx>` 已实现上述 GKE 采集 + digest 解析 + 比对，输出中会标 `⚠ 仍被引用`。

#### 判定结论模板（填进评审记录）

```
被删版本集合：__ 个版本，分布在 __ 个 package
其中仍被 GKE 工作负载引用：__ 个（列出 Deployment/StatefulSet 名）
其中仍被 Cloud Run 引用：__ 个
其中被 IaC / CI 源码引用但当前未部署：__ 个
结论：☐ 可直接执行  ☐ 需先加 KEEP 策略  ☐ 需先下线引用方
```

### 5.2 其它风险清单

| # | 风险 | 触发条件 | 影响 | 缓解 |
|:--|:--|:--|:--|:--|
| R1 | **策略整表替换** | `set-cleanup-policies` 未包含全部策略 | 其它保护性策略消失 | 导出→修改→全量回灌；策略入 Git |
| R2 | **最短保留期胜出** | 新增激进 DELETE | 全局保留期缩短 | 变更前跑推演脚本；评审时对比"最短 olderThan" |
| R3 | **无 tag 格式被误删** | npm/maven/python 仓库用了 `UNTAGGED`/`ANY` | 版本被批量删除 | 用 `versionNamePrefixes` + `mostRecentVersions` 保护；按格式分别建策略 |
| R4 | **immutable tags 使策略部分失效** | `dockerConfig.immutableTags=true` | tagged 版本删不掉，untagged 照删 | 评估时先看这个字段（脚本已输出） |
| R5 | **不可逆** | 误删 | 无法回滚 | KEEP 兜底 + dry run + 分批放量 |
| R6 | **延迟爆发** | 节点重启/扩容/回滚 | 批量 `ImagePullBackOff` | 关键镜像加 KEEP；保留最近 N 个 |
| R7 | **配额/上限截断** | 清理删除计入 delete 配额；每仓库每天有上限 | 清理未清完、残留 | 分批；核对 quota 页面实际数值 |
| R8 | **删除配额占用** | 大量删除与正常发布抢占配额 | `versions.delete` 被限流 | 避开发布窗口 |
| R9 | **费用下降延迟** | layer 每日回收 | 账单没降 | 预期按 +1 天计 |
| R10 | **审计缺失** | 未开 DATA_WRITE 日志 | 无法追溯谁在什么时候删了什么 | 变更前先开审计日志 |
| R11 | **合规/可重现性** | 删掉历史构建产物 | 无法复现历史构建 / SBOM 断链 | 合规要求的版本永久 KEEP |
| R12 | **扫描结果丢失** | 版本被删 | Artifact Analysis 漏洞状态随之消失 | 需要长期留存的镜像加 KEEP |
| R13 | **父子 manifest 二阶删除** | 父 manifest 被删 | 下一轮才删子镜像 | 评估时预留第二轮影响 |
| R14 | **CI 断链** | CI 依赖的 base image 被删 | 构建失败 | CI 依赖清单纳入检查 |
| R15 | **跨仓库复制断链** | 目标仓库的镜像被删但源仓库还在 | 灾备/迁移副本失效 | 灾备仓库独立策略 |
| R16 | **策略漂移** | 多项目/多 region 手工维护 | 各仓库保留期不一致、审计困难 | Terraform 统一管理 |
| R17 | **变更窗口竞态** | 策略刚更新，后台作业正在跑 | 本轮按旧策略、下轮按新策略 | 变更避开作业周期；重要变更先 dry run 观察 ≥1 天 |
| R18 | **tag 移动连带** | `latest` 被覆盖 | 旧 digest 立刻 UNTAGGED | 发布流程避免复用 tag（用不可变 tag + digest） |
| R19 | **删除操作由 Service Agent 发起** | 策略写错 | 权限面天然具备删除能力 | 严格控制 `repositories.update` 权限 |

### 5.3 风险矩阵

| | 影响小 | 影响中 | 影响大 |
|:--|:--|:--|:--|
| **发生概率高** | R4 R9 R16 | R2 R3 R17 | R1 R5 |
| **发生概率低** | R10 R12 | R7 R8 R14 R15 | R5 R6 R11 R13 R19 |

**必须在上线前关闭的**：R1、R2、R3、R5、R6、R10。

---

## 6. 推荐的策略模板（按格式区分）

### 6.1 Docker 仓库（典型三段式）

```json
[
  {
    "name": "keep-release",
    "action": { "type": "Keep" },
    "condition": { "tagState": "tagged", "tagPrefixes": ["release-", "stable-"] }
  },
  {
    "name": "keep-last-10",
    "action": { "type": "Keep" },
    "mostRecentVersions": { "keepCount": 10 }
  },
  {
    "name": "delete-untagged",
    "action": { "type": "Delete" },
    "condition": { "tagState": "untagged", "olderThan": "14d" }
  },
  {
    "name": "delete-prerelease",
    "action": { "type": "Delete" },
    "condition": { "tagState": "tagged", "tagPrefixes": ["alpha-", "beta-", "dev-"], "olderThan": "30d" }
  }
]
```

* 生产仓库：`olderThan` 建议 ≥ 30d；开发/测试仓库可放宽到 3~7d。
* `keep-last-10` 作为兜底：KEEP 优先级高于 DELETE，策略顺序不影响最终结果，但把它写在最后便于人工阅读。
* **不要**给生产仓库配 `tagState=ANY` 的 DELETE。

### 6.2 npm / maven / python 等无 tag 格式

```json
[
  {
    "name": "keep-latest-versions",
    "action": { "type": "Keep" },
    "mostRecentVersions": { "keepCount": 20 }
  },
  {
    "name": "keep-pinned-versions",
    "action": { "type": "Keep" },
    "condition": { "versionNamePrefixes": ["1.2.", "2.0."] }
  },
  {
    "name": "delete-old",
    "action": { "type": "Delete" },
    "condition": { "olderThan": "90d" }
  }
]
```

> 这些格式没有 tag，`tagState` 一律视为 untagged：**保留策略必须靠 `versionNamePrefixes` / `mostRecentVersions`**，否则会把线上正在用的版本全部删掉。

---

## 7. Runbook

### 7.1 上线一条新策略

```
① list-cleanup-policies 导出 → 存 policies.json（进 Git）
② 改 policies.json（新增/修改一条）
③ cleanup-policy-audit.sh 推演 → 看命中集 + ⚠ 仍被引用
④ set-cleanup-policies --policy=policies.json --dry-run      ← 显式 dry run
⑤ 等 ≥1 天 → 查审计日志 validateOnly=true → 核对待删清单与推演是否一致
⑥ 人工确认无关键镜像 → set-cleanup-policies --policy=policies.json --no-dry-run
⑦ 再等 1~2 天 → 查真实删除审计日志；观察 GKE 事件（ImagePullBackOff）、告警
⑧ 观察一个业务周期后再决定是否收紧 olderThan
```

### 7.2 变更 / 回滚

* **变更**：永远走"导出 → 改 → 全量 set"，不要手写只含一条策略的文件。
* **回滚**：把 Git 里上一版 `policies.json` 全量 set 回去，并**显式** `--dry-run`（先止血）再决定是否 `--no-dry-run`。
* **已删版本无法恢复**：唯一补救是把 CI/GitOps 里的镜像重新构建并 push（内容由构建过程决定，不保证与原 digest 一致）。

### 7.3 例行巡检

| 频率 | 动作 |
|:--|:--|
| 每周 | 跑 `cleanup-policy-audit.sh`，看命中量与"仍被引用"清单 |
| 每月 | 核对 `sizeBytes` 与账单，确认清理确实降本；核对 quota 使用量 |
| 每季度 | 复核策略与实际部署镜像的差异（新的服务上线后，KEEP 范围是否已覆盖） |

---

## 8. 附录

### 8.1 字段速查（API ↔ 策略文件 ↔ Terraform）

| API | 策略文件 | Terraform | 控制台 |
|:--|:--|:--|:--|
| `cleanupPolicies{id,action,condition,mostRecentVersions}` | `[{name, action:{type}, condition, mostRecentVersions}]` | `cleanup_policies { id, action, condition{}, most_recent_versions{} }` | Cleanup policies 列表 |
| `cleanupPolicyDryRun` | `--dry-run` / `--no-dry-run` | `cleanup_policy_dry_run` | Dry run / Delete artifacts |
| `condition.tagState` | `condition.tagState`（`tagged`/`untagged`/`any`） | `tag_state`（`TAGGED`/`UNTAGGED`/`ANY`） | Tag state |
| `condition.tagPrefixes` | `condition.tagPrefixes` | `tag_prefixes` | Tag prefixes |
| `condition.versionNamePrefixes` | `condition.versionNamePrefixes` | `version_name_prefixes` | Version prefixes |
| `condition.packageNamePrefixes` | `condition.packageNamePrefixes` | `package_name_prefixes` | Package prefixes |
| `condition.olderThan` / `newerThan` | `condition.olderThan` / `newerThan`（`30d`） | `older_than` / `newer_than` | Older than / Newer than |
| `mostRecentVersions.keepCount` | `mostRecentVersions.keepCount` | `keep_count` | Keep count |
| `mostRecentVersions.packageNamePrefixes` | `mostRecentVersions.packageNamePrefixes` | `package_name_prefixes` | Package prefixes |
| `dockerConfig.immutableTags` | — | `docker_config { immutable_tags }` | Immutable tags |

### 8.2 命令速查

```bash
# 看现状
gcloud artifacts repositories describe example-repo --project=example-project --location=us-central1
gcloud artifacts repositories list-cleanup-policies example-repo --project=example-project --location=us-central1

# 版本盘点
gcloud artifacts packages list --repository=example-repo --project=example-project --location=us-central1
gcloud artifacts versions list --package=example-app --repository=example-repo \
  --project=example-project --location=us-central1 --format="json(name,createTime,updateTime,relatedTags)"

# 审计日志（dry run / 真实删除）
gcloud logging read 'protoPayload.serviceName="artifactregistry.googleapis.com"
  AND protoPayload.request.parent="projects/example-project/locations/us-central1/repositories/example-repo/packages/-"' \
  --project=example-project --resource-names=projects/example-project --format=json
```

### 8.3 已知限制汇总

| 项 | 值 | 来源 |
|:--|:--|:--|
| 单仓库策略数 | 10 | Cleanup policy overview / Quotas |
| 单仓库每天清理删除数 | 300,000（Quotas 页）/ 600,000（Overview 页，**口径冲突，以 quota 页为准**） | 官方文档 |
| delete 请求配额 | 18,000 次/分钟/区域，清理删除计入 | Quotas |
| 策略生效延迟 | 约 1 天（后台周期作业） | 官方文档 |
| 不可变 tag | 开启后 tagged 版本不可被清理策略删除 | 官方文档 |
| 仓库类型 | 仅 standard / remote 可配置 | 官方文档 |

### 8.4 参考

* Configure cleanup policies — https://cloud.google.com/artifact-registry/docs/repositories/cleanup-policy
* Cleanup policy overview — https://cloud.google.com/artifact-registry/docs/repositories/cleanup-policy-overview
* Quotas and limits — https://cloud.google.com/artifact-registry/quotas
* REST 参考（Repository / CleanupPolicy） — https://cloud.google.com/artifact-registry/docs/reference/rest/v1/projects.locations.repositories
* Terraform `google_artifact_registry_repository` — https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository
* 本地脚本 — `gcp/artifact-registry/scripts/cleanup-policy-audit.sh`
