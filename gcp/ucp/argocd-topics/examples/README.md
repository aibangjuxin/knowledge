# examples/ · 可复制示例 ＋ 静态检查工具箱

> 这个目录有两层东西：
>
> ① **可复制的配置片段** —— 直接 `kubectl apply` 就能用的 YAML；
> ② **静态检查工具箱** —— 把文档里的最佳实践变成**能跑的检查**，
> 在提交前就把错误抓出来，不用等 Argo CD 同步失败才发现。
>
> ⭐ **入口**：[`gitops-layout/ci-check.sh`](./gitops-layout/ci-check.sh) ——
> 一条命令跑完全部检查。

---

## 目录

- [1. 工具箱总览](#1-工具箱总览)
- [2. 怎么用](#2-怎么用)
- [3. 每个工具细看](#3-每个工具细看)
- [4. 脚手架：加集群 / 加组件](#4-脚手架：加集群--加组件)
- [5. 配置片段清单](#5-配置片段清单)
- [6. 共享库：yamlmin](#6-共享库：yamlmin)
- [7. 写新检查的约定](#7-写新检查的约定)

---

## 1. 工具箱总览

| 工具 | 位置 | 连集群？ | 查什么 |
|---|---|---|---|
| `ci-check.sh` | [`gitops-layout/`](./gitops-layout/ci-check.sh) | ❌ | **总入口**：把下面所有静态检查串起来 |
| `validate-examples.py` | [本目录](./validate-examples.py) | ❌ | 配置片段的**危险默认值**（RBAC / Dex / HA / Repository / Redis） |
| `check-doc-links.py` | [本目录](./check-doc-links.py) | ❌ | Markdown 里的相对链接和**锚点** |
| `validate-clusters.py` | [`gitops-layout/`](./gitops-layout/validate-clusters.py) | ❌ | 集群清单字段漂移 |
| `appset-simulator.py` | [`gitops-layout/`](./gitops-layout/appset-simulator.py) | ❌ | 精确渲染 AppSet → Application 并**交叉校验** |
| `render-check.py` | [`gitops-layout/`](./gitops-layout/render-check.py) | ❌ | 每个 overlay 能不能 build、产物对不对 |
| `preview-appset.py` | [`gitops-layout/`](./gitops-layout/preview-appset.py) | ❌ | 展开矩阵（人看的视图） |
| `new-cluster.sh` | [`gitops-layout/`](./gitops-layout/new-cluster.sh) | ❌ | **写入**：新增集群的脚手架 |
| `enable-component.sh` | [`gitops-layout/`](./gitops-layout/enable-component.sh) | ❌ | **写入**：给集群开关组件 |
| `demo.sh` | [`gitops-layout/`](./gitops-layout/demo.sh) | ✅ | 端到端 Demo（建集群→装 Argo CD→同步） |
| `argocd-health.sh` | [本目录](./argocd-health.sh) | ✅ | **运行时**体检（纯只读） |

> **离线 vs 运行时**：左边 9 个工具**不需要**集群和 Argo CD，
> 纯靠 Git 里的文件就能跑 → 可以直接进 CI 的 PR 检查。
> 只有 `argocd-health.sh` 和 `demo.sh` 需要真实环境。

---

## 2. 怎么用

### 提交前（本地）

```bash
cd examples/gitops-layout
./ci-check.sh                 # 全跑
./ci-check.sh --quick         # 跳过需要 kubectl 的部分（没装 kubectl 时）
./ci-check.sh --fix-hints     # 失败时打印「怎么修」
```

### CI（PR 检查）

```yaml
# .github/workflows/checks.yaml
name: checks
on: [pull_request]
jobs:
  static:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.11' }
      - name: 静态检查
        run: ./examples/gitops-layout/ci-check.sh
      # 需要 kubectl 就装一个
      - uses: azure/setup-kubectl@v4
      - run: ./examples/gitops-layout/ci-check.sh
```

> CI 里**不需要**装 PyYAML —— 所有工具用 [`lib/yamlmin.py`](./lib/yamlmin.py)
> 这个零依赖的解析器。

### 只看某个工具

```bash
python3 validate-examples.py --path examples/
python3 check-doc-links.py --path argocd-topics/
python3 gitops-layout/validate-clusters.py
python3 gitops-layout/appset-simulator.py --verbose
python3 gitops-layout/render-check.py --only nginx
```

---

## 3. 每个工具细看

### 3.1 `validate-examples.py` —— 配置片段体检

校验 [`examples/`](.) 根目录那 7 个"配置类"YAML。**它们最容易抄错，因为
kubectl 不会帮你兜底**。

抓得到：

| 症状 | 后果 |
|---|---|
| `argocd-rbac-cm` 的 `scopes` 少了 `groups` | 所有 `g, 组名, 角色` 规则**永不生效**（组映射静默失效） |
| `policy.default: role:readonly` | 所有已认证用户可读**全部** Application |
| `policy.csv` 某行字段数不对 | 整条规则被忽略 |
| HA 里 `server.replicas=3` 但 `ARGOCD_API_SERVER_REPLICAS=1` | 登录被限流误拒（上游 #11387） |
| `dex.replicas > 1` | dex 用内存存储，多副本登录态不一致 |
| Dex `bindPW` 是明文 | 密码进 Git |
| Dex 缺 `insecureEnableGroups` / `groupSearch` | LDAP 组进不了 token → RBAC 全废 |
| Repository Secret 缺 `argocd.argoproj.io/secret-type` label | Argo CD **根本不认**这个 Secret |
| Secret 里有明文 password / token | 凭据泄露 |
| AppProject 的 `roles[].policies` 主体名不对 | 该项目角色规则不生效 |
| AppSet 的 `template.spec.project` 没写 / 写成 `default` | 生成的 Application 落在**最宽松**的项目 |
| AppSet 的 `syncPolicy.automated.prune` 是模板字符串 | API server 以 `must be of type boolean` 拒掉 |

### 3.2 `check-doc-links.py` —— 文档链接体检

- 相对链接指向的文件是否存在
- **锚点**（`#标题`）在目标文件里是否存在（按 GitHub 的 slug 规则计算）
- 代码块里引用的脚本路径是否存在

> 修过 14 个真实的断锚点（含 `Develop-git-apps.md` 和
> `webhook-and-backend-service.md` 目录里的）。

### 3.3 `validate-clusters.py` —— 集群清单体检

见 [`gitops-layout/README.md`](./gitops-layout/README.md)。

### 3.4 `appset-simulator.py` —— 精确模拟 + 交叉校验

`preview-appset.py` 只列矩阵；这个脚本**真的把 Go template 渲染出来**，
拿到每个 Application 的完整 spec，然后拿去对账：

- Application **重名**（两个 AppSet 生成同一个名字 → Argo CD 里互相覆盖）
- `project` 不存在 → `project not found`
- `destination` 不被 AppProject 允许 → `not match any of the allowed destinations`
- `source.path` 渲染出来在磁盘上不存在 → 同步失败
- 模板变量没人生成 → `missingkey=error` 让**整个 AppSet** 报错
- prod 命名空间却开着 `selfHeal` → 半夜自动改线上

```bash
python3 gitops-layout/appset-simulator.py            # 矩阵 + 校验
python3 gitops-layout/appset-simulator.py --verbose  # 再打印每个 Application 的完整 spec
python3 gitops-layout/appset-simulator.py --json     # 机器可读（给 CI 用）
```

### 3.5 `render-check.py` —— 渲染产物体检

把每个 overlay 都 `kubectl kustomize` 一遍，然后检查**渲染出来的东西**：

- 渲染失败（路径写错 / **父子嵌套导致 cycle detected**）
- Deployment 的 `selector` 与 pod 模板 labels 对不上 → **K8s 直接拒绝创建**
- Service 的 selector 匹配不到任何工作负载 → 服务没有后端
- 镜像没固定 tag / 用了 `latest`
- 缺 `resources.requests` / `limits`
- 缺 `readinessProbe` / `livenessProbe`
- 资源里硬编码了 namespace（与目标 namespace 不符）
- prod 环境 `replicas < 2`
- StatefulSet 没有 `volumeClaimTemplates` → 重启即丢数据

规则级别和已知例外写在
[`render-check.policy.yaml`](./gitops-layout/render-check.policy.yaml)。

**渲染结果对比**（PR 评审神器）：

```bash
python3 gitops-layout/render-check.py --save /tmp/before
# ...改代码...
python3 gitops-layout/render-check.py --compare /tmp/before
# → 直接看到「哪些 overlay 的渲染产物变了、变了什么」
```

---

## 4. 脚手架：加集群 / 加组件

```bash
cd examples/gitops-layout

# 新增集群：建目录 + 写清单 + 加 AppProject destination + 提示怎么注册 Cluster Secret
./new-cluster.sh --name dev-03 --env dev \
    --project acme-platform-dev \
    --region asia-east1 \
    --server https://dev-03.k8s.example.com \
    --component nginx --component api --component gatekeeper

# 给已有集群开关组件（集群级组件会自动复制一份每集群的 overlay）
./enable-component.sh --cluster dev-01 --component redis
./enable-component.sh --cluster dev-01 --component redis --disable
```

两个脚本都会在最后自动跑 `validate-clusters.py` 自检。

> ⚠️ **Cluster Secret 不会被脚本创建**（里面有凭据，不该进 Git）——
> 脚本会打印出需要你手动执行的那几条命令。

---

## 5. 配置片段清单

| 文件 | 用途 | 关键点 |
|---|---|---|
| [`dex-ldap-config.yaml`](./dex-ldap-config.yaml) | Dex + LDAP 完整配置 | `insecureEnableGroups: true` + `scopes` 必须同时有 |
| [`argocd-rbac-cm.yaml`](./argocd-rbac-cm.yaml) | 组 → 角色映射 | `scopes` 必须含 `groups`；`policy.default` 不能被 deny 收回 |
| [`appproject-multi-env.yaml`](./appproject-multi-env.yaml) | 多环境项目边界 | 收紧 `default` 是破坏性操作 |
| [`applicationset-matrix.yaml`](./applicationset-matrix.yaml) | 批量分发（Matrix/List/Merge） | `template.spec.project` 必须显式写 |
| [`argocd-repositories-githubapp.yaml`](./argocd-repositories-githubapp.yaml) | Repository Secret | 目标分支**不在这里** |
| [`redis-statefulset-pvc.yaml`](./redis-statefulset-pvc.yaml) | 业务 Redis 持久化改造 | 这是**业务** Redis，不是 Argo CD 内部 Redis |
| [`ha-values-override.yaml`](./ha-values-override.yaml) | HA 升级 values | `ARGOCD_API_SERVER_REPLICAS` 必须与副本数一致 |
| [`gitops-layout/`](./gitops-layout/) | **完整 GitOps 仓库骨架** | `bootstrap/` 里的非资源清单必须用 `kustomization.yaml` 排除 |

---

## 6. 共享库：`yamlmin`

[`lib/yamlmin.py`](./lib/yamlmin.py) —— **零依赖**的 YAML 子集解析器。

**为什么不用 PyYAML**：很多 CI 镜像 / 精简容器里装不了三方包；
而这套工具需要解析嵌套结构（ConfigMap 里嵌的整段 YAML、AppProject 的列表项…），
按行 grep 是做不到的。

**支持**：块映射、块序列（序列项与 key 同缩进也行）、序列项内联映射、
块标量 `|`/`>`、flow 集合 `{a: 1}`/`[1,2]`、引号标量、bool/int/float/null、
注释剥离、多文档。

**不支持**（故意）：锚点/别名、复杂键、标签、多行 flow 集合 —— 出现了会抛
`YamlError` 而不是猜。

**质量保证**：在 `examples/` 下全部 70 个 YAML 上，与 PyYAML 做过**逐字段对账**，
结果 0 差异。

```python
import sys; sys.path.insert(0, "examples/lib")
from yamlmin import load_all_files, flatten, select_equal

docs = load_all_files("path/to.yaml")   # 多文档
params = flatten(doc, ["cluster", "env"])  # Argo CD git generator 的 flatten 语义
ok = select_equal(doc, 'env == "prod"')     # 简易 JMESPath
```

---

## 7. 写新检查的约定

想再加一个检查时，照着现有工具的写法来：

1. **放在合适的目录** —— 检查 `examples/` 根目录的放这里；检查 `gitops-layout/`
   的放 `gitops-layout/`。
2. **零依赖** —— 用 `lib/yamlmin.py` 解析 YAML，不要 import 其它三方包。
3. **纯只读** —— 检查类脚本**绝不**修改文件、不连集群、不 apply 任何东西。
   要改文件的（脚手架）单独命名，并在 `--help` 里写清楚。
4. **退出码** —— 0 = 通过，1 = 有错误。非 0 才阻塞 CI。
5. **能指名道姓** —— 报错要说清「哪个文件、哪个字段、为什么错、怎么改」，
   而不是「格式错误」。
6. **可调级别** —— 用策略文件（`*.policy.yaml`）控制 error / warn / info，
   并支持「已知例外」白名单。
7. **挂到 `ci-check.sh`** —— 新工具要能在 CI 里被跑起来。
8. **写个负例测一下** —— 造一个坏文件，确认工具真的会报错。
