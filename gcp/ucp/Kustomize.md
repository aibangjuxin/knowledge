# Kustomize × Argo CD

> **本文定位**：Kustomize 是什么、解决什么问题，以及它**如何嵌入 Argo CD 的渲染—对比—同步链路**。
> 面向本仓库基线：**Argo CD v3.5.6**（`install.yaml` 中 `quay.io/argoproj/argocd:v3.5.6`，见 `install.yaml:32094`）。
> 上游源码定位固定在 `v3.5.6` tag；凡是版本相关结论都对照了本仓库 `install.yaml` 的实际内容。

---

## 0. 一句话结论

**Kustomize 是纯 YAML 的"组装与变形"引擎**——把若干 YAML 资源按声明式规则合成为一份最终 manifest；
**Argo CD 内置了 Kustomize 二进制**，在 `argocd-repo-server` 里执行 `kustomize build`，
把渲染结果与集群 live state 做 diff，再决定同步。

分工非常干净：

| | Kustomize | Argo CD |
|---|---|---|
| 做什么 | 生成目标 YAML | 拉 Git、渲染、对比 live state、同步、健康评估 |
| 不做什么 | **不碰集群**（不读、不写、不 apply） | 不做模板渲染（那是 Kustomize/Helm/Jsonnet 的事） |
| 产物 | stdout 上的 manifest 文本 | 集群里被管理的资源状态 |

所以 "Kustomize + Argo CD" 的正确心智模型是：
**Kustomize 是 Argo CD 的"编译器前端"，Argo CD 是"编译器后端 + 部署器"**。
Kustomize 没有控制器、没有 webhook、没有 reconcile 循环；把它的输出丢进集群，它什么都不会发生。

---

## 1. Kustomize 解决什么问题

### 1.1 核心痛点：同一套资源，N 个环境

没有 Kustomize 时，多环境只有三条路：

1. **复制粘贴 N 份 YAML** —— 改一个字段要改 N 处，漂移不可避免（本仓库 `argocd-admin-guide.md` §6.3 把"晋级 = 复制 YAML"明确列为反模式）。
2. **Helm + values** —— 强大，但引入模板引擎，values 里的逻辑需要 Go 模板能力，渲染结果不再是"可读的 YAML"。
3. **Kustomize overlay** —— base 定义"这个服务长什么样"，overlay 只声明"这个环境差在哪"。

```yaml
# base/kustomization.yaml —— 只有一份，所有环境共用
resources:
  - deployment.yaml
  - service.yaml
```

```yaml
# envs/prod/kustomization.yaml —— 只写差异
resources:
  - ../../base
namePrefix: prod-
namespace: my-app
replicas:
  - name: my-app
    count: 5
images:
  - my-app=gcr.io/my-repo/my-app:1.4.2
```

### 1.2 为什么是 Kustomize 而不是别的

| 维度 | Kustomize | Helm | Jsonnet |
|---|---|---|---|
| 模板能力 | 无（纯 YAML 变换） | Go template + sprig | Jsonnet 语言 |
| 渲染结果 | 仍是普通 YAML，可直接 review/diff | 仍是 YAML，但 values 里可以有逻辑 | YAML，但需要 Jsonnet 工具链 |
| 运行时依赖 | `kustomize` 二进制 | `helm` 二进制 | `jsonnet` 二进制 |
| 组合模型 | base/overlay + patches + components | chart + values + templates | Jsonnet 表达式 |
| 对 Argo CD | **原生内置**（repo-server 自带） | 原生内置 | 原生内置 |

三者 Argo CD 都原生支持，选择取决于**团队熟悉度**和**差异化复杂度**：

- 差异只是"镜像 tag / 副本数 / 命名空间 / 少量字段覆盖" → **Kustomize 最省事**，YAML diff 可读。
- 差异是"条件分支 + 循环生成资源" → Helm 或 Jsonnet 更强。
- 本仓库 `argocd-topics/00-architecture-no-crossplane.md` 的 **D3 决策**已经把两者并列为"Argo CD 原生渲染能力，Argo CD 之外无额外运行时依赖"——Kustomize 正是这条决策在 Kustomize 侧的落点。

### 1.3 Kustomize 的能力边界（必须知道的）

- **不做条件逻辑**：没有 `if`、没有变量插值（`vars`/`replacements` 也只是字符串替换，不是表达式求值）。
- **不做跨仓库的组合**（远程 base 可以，但要 `--load_restrictor` 放开，见 §8.2）。
- **不改写你的 Git 仓库**（这点在 Argo CD 场景下尤其重要，见 §3.3）。

---

## 2. 核心概念速览

### 2.1 `kustomization.yaml`

Kustomize 的入口文件。Argo CD 识别时接受三个文件名（源码 `util/kustomize/kustomize.go:77`）：

```go
var KustomizationNames = []string{"kustomization.yaml", "kustomization.yml", "Kustomization"}
```

常用字段：

| 字段 | 作用 | 备注 |
|---|---|---|
| `resources` | 引用其它 YAML 资源/目录/远程 base | 目录引用 = base/overlay 组合 |
| `components` | 引用可复用的"资源 + patch"包 | Kustomize ≥ v3.7.0；比 overlay 更轻量 |
| `patches` / `patchesStrategicMerge` / `patchesJson6902` | 对目标资源做修改 | 本质是 JSON Patch / strategic merge |
| `configMapGenerator` / `secretGenerator` | 从文件/literal 生成 CM/Secret | 生成物带 hash 后缀（`cfg-abc123`） |
| `namespace` | 给所有资源设置 namespace | 优先级高于 `spec.destination.namespace`（见 §8.4） |
| `namePrefix` / `nameSuffix` | 资源名前后缀 | **只改名字，不改 label/selector** |
| `commonLabels` / `commonAnnotations` | 给所有资源打标 | `commonLabels` **会写进 selector**（见 §8.3） |
| `images` | 镜像覆盖 | `name=newName:tag` 格式 |
| `replicas` | 副本数覆盖 | 目标必须是 Deployment/StatefulSet 名 |
| `replacements` | 跨资源字段复制 | Kustomize v5 特性 |
| `helmCharts` | 在 Kustomize 里渲染 Helm chart | **需要 `--enable-helm`**，见 §8.7 |

### 2.2 base / overlay 的正确姿势

```
infra/                          # 单一 Git 仓库
├── apps/
│   └── my-app/                 # 应用定义（与环境无关）
│       ├── base/               # base：资源的"本体"
│       │   ├── kustomization.yaml
│       │   ├── deployment.yaml
│       │   └── service.yaml
│       └── components/         # 可选：跨应用复用的组件
└── environments/
    ├── dev/
    │   └── kustomization.yaml  # overlay：只写差异
    ├── staging/
    └── prod/
```

**原则：应用定义与环境分离**（`apps/` 与 `environments/` 分开），
同一个应用通过 overlay 渲染出不同环境，避免"复制粘贴 N 份 YAML"——
这条原则在本仓库 `argocd-admin-guide.md` §6.2 已经写明，本仓库的推荐目录结构与之完全一致。

---

## 3. Argo CD 侧：Kustomize 是怎么被用起来的

这一节是本文的核心：**Argo CD 对 Kustomize 的支持，是分成四层实现的**，
源码定位全部来自 `argoproj/argo-cd` 的 `v3.5.6` tag。

### 3.1 第一层：识别源类型（Source Type Detection）

Argo CD 不会"猜"，它有明确的探测逻辑，入口在
`util/app/discovery/discovery.go`：

```go
// discovery.go —— Discover() 遍历 appPath 下的文件
if strings.HasSuffix(base, "Chart.yaml") && IsManifestGenerationEnabled(Helm, ...) {
    apps[dir] = string(v1alpha1.ApplicationSourceTypeHelm)
}
if kustomize.IsKustomization(base) && IsManifestGenerationEnabled(Kustomize, ...) {
    apps[dir] = string(v1alpha1.ApplicationSourceTypeKustomize)
}
```

判定顺序与含义：

1. **先看 CMP 插件**：`DetectConfigManagementPlugin` 成功 → 类型是 `Plugin`（自定义配置管理工具优先于内置引擎）。
2. **显式声明优先**：`ApplicationSource.ExplicitType()`（`pkg/apis/application/v1alpha1/types.go`）——只要在 `spec.source` 里填了 `kustomize: {}`（哪怕是空对象），类型就锁定为 Kustomize，不再探测。
   顺带一条硬规则：**同时填多个类型（`helm` + `kustomize`）会直接报错**，不是二选一。
3. **否则按目录内容探测**：出现 `kustomization.yaml` / `kustomization.yml` / `Kustomization` → Kustomize；出现 `Chart.yaml` → Helm；都没有 → `Directory`（裸 YAML 目录）。
4. **可被关掉**：`argocd-cm` 里 `kustomize.enable: "false"` 会让 Kustomize 不参与探测，
   对应 Application 退化为 `Directory` 类型。

> **落地含义**：只要 `spec.source.path` 指向的目录里有 `kustomization.yaml`，
> 你**不写** `spec.source.kustomize` 也能被正确识别；写了 `kustomize: {}` 只是显式锁定 + 挂载覆盖项。

### 3.2 第二层：渲染（repo-server 里的 `kustomize build`）

入口 `reposerver/repository/repository.go`：

```go
case v1alpha1.ApplicationSourceTypeKustomize:
    kustomizeBinary, err = settings.GetKustomizeBinaryPath(q.KustomizeOptions, *q.ApplicationSource)
    ...
    k := kustomize.NewKustomizeApp(repoRoot, appPath, q.Repo.GetGitCreds(gitCredsStore), repoURL,
                                   kustomizeBinary, q.Repo.Proxy, q.Repo.NoProxy)
    targetObjs, _, commands, err = k.Build(q.ApplicationSource.Kustomize, q.KustomizeOptions, env,
        &kustomize.BuildOpts{
            KubeVersion: kubeVersion,
            APIVersions: q.ApplicationSource.GetAPIVersionsOrDefault(q.ApiVersions),
        })
```

链路的实际形状：

```
repo-server
  ├─ git checkout 到临时目录（repoRoot / appPath）
  ├─ 按需执行 `kustomize edit set ...`（改的是临时 checkout，不是你的 Git 仓库）
  ├─ 执行 `kustomize build <appPath> [buildOptions]`   ← cwd = repoRoot
  └─ kube.SplitYAML() 拆成 unstructured 对象 → 作为 target state
```

源码里两个值得记住的细节：

- `cmd.Dir = k.repoRoot`，而 `kustomize build` 的参数是**相对仓库根的 appPath**。
  换句话说，**Kustomize 的"根"始终是仓库根**，不是 `spec.source.path` 目录——
  这决定了 `resources: ../../base` 这类跨目录引用是否受 load restrictor 限制（§8.2）。
- `parseKustomizeBuildOptions()` 会把 `argocd-cm` 里的 build options 拼到 `build` 后面：
  ```go
  buildOptsParams := append([]string{"build", k.path}, strings.Fields(buildOptions)...)
  if buildOpts != nil && !getSemverSafe(ctx, k).LessThan(semver.MustParse("v5.3.0")) && isHelmEnabled(buildOptions) {
      // 追加 --helm-kube-version / --helm-api-versions
  }
  ```

### 3.3 第三层：Application 级覆盖（`spec.source.kustomize`）

这是 Argo CD 独有的能力：**在 Application spec 里直接覆盖 Kustomize 参数**。
实现方式很有意思——它不是在内存里改 AST，而是**在临时 checkout 里调用 `kustomize edit` 命令**：

```go
// util/kustomize/kustomize.go —— Build() 内部
if opts.NamePrefix != "" {
    cmd := exec.CommandContext(ctx, k.getBinaryPath(), "edit", "set", "nameprefix", "--", opts.NamePrefix)
    cmd.Dir = k.path
    ...
}
if len(opts.Images) > 0 {
    args := []string{"edit", "set", "image"}
    for _, image := range opts.Images { args = append(args, envSubstitutedImage) }
    ...
}
if len(opts.Replicas) > 0 {
    args := []string{"edit", "set", "replicas"}   // my-app=3
    ...
}
```

对应关系：

| `spec.source.kustomize` 字段 | 实现动作 |
|---|---|
| `namePrefix` / `nameSuffix` | `kustomize edit set nameprefix/namesuffix` |
| `images` | `kustomize edit set image` |
| `replicas` | `kustomize edit set replicas` |
| `commonLabels` | `kustomize edit add label [--force] [--without-selector] [--include-templates]` |
| `commonAnnotations` | `kustomize edit add annotation [--force]` |
| `namespace` | `kustomize edit set namespace` |
| `components` | `kustomize edit add component`（需 Kustomize ≥ v3.7.0，否则直接报错） |
| `patches` | **不走 CLI**，直接改写 `kustomization.yaml` 的 `patches` 字段 |

关于 `patches` 的改写，源码注释写得很清楚：

> `kustomization.yaml updated with patches. There is no 'kustomize edit' command for adding patches.
> In order to generate the manifests in your local environment, you will need to copy the patches
> into kustomization.yaml manually.`

**两个必须记住的推论：**

1. **这些改动只发生在 repo-server 的临时 checkout 里，Git 仓库不受影响。**
   Argo CD 不会把你的 `kustomization.yaml` 提交回去，也不会让工作区变脏。
2. **Application 里写的 patch，本地 `kustomize build` 是看不到的**——
   因为它没有被写回你的仓库。这直接导致了 §8.1 的经典困惑。

### 3.4 第四层：对比与同步（diff / sync）

Kustomize 只负责产出 target state，剩下全是 Argo CD 的活：

- `argocd app manifests <app>` —— 拿渲染结果（本地排查渲染问题的第一入口）。
- `argocd app diff <app>` —— target state vs live state。
  官方语义：*"Perform a diff against the target and live state"*，退出码 `1` 表示有 diff、`0` 表示无 diff、`2` 为通用错误。
- 差异归一化与噪声抑制：`argocd-cm` 的 `resource.customizations.*`、
  Application 的 `spec.ignoreDifferences`（本仓库 `argocd-topics/09-troubleshooting.md` §6.1 有专门说明）。
- 同步：`spec.syncPolicy.automated` + `syncOptions`。

> **Kustomize 影响的只有"target state 长什么样"**。
> 一旦渲染完成，Kustomize 就退场了——diff、prune、健康评估全部发生在 Argo CD 侧。

---

## 4. `spec.source.kustomize` 字段全表

下表字段**逐个对照本仓库 `install.yaml` 里 Application CRD 的 schema**（`install.yaml:1249-1380`）
以及上游 `pkg/apis/application/v1alpha1/types.go`，不是凭记忆写的。

| 字段 | 类型 | 作用 | 备注 |
|---|---|---|---|
| `namePrefix` | string | 资源名前缀 | 覆盖 kustomization.yaml 里的同名值 |
| `nameSuffix` | string | 资源名后缀 | 同上 |
| `images` | []KustomizeImage | 镜像覆盖 | `my-app=gcr.io/x/y:1.0`；支持 `${ARGOCD_APP_REVISION}` 变量替换 |
| `replicas` | [] | 副本数覆盖 | `{name, count}`；count 是 int 或字符串 |
| `commonLabels` | map[string]string | 全局 label | 会写进 selector，慎用 |
| `commonAnnotations` | map[string]string | 全局 annotation | 不会写进 selector |
| `forceCommonLabels` | bool | 强制覆盖已有 label | 不加 `force` 时是"没有才加" |
| `forceCommonAnnotations` | bool | 强制覆盖已有 annotation | 同上 |
| `commonAnnotationsEnvsubst` | bool | 对 annotation 值做变量替换 | 可用 `${ARGOCD_APP_NAME}` 等 |
| `labelWithoutSelector` | bool | label 不写进 selector | 规避 selector 变更 |
| `labelIncludeTemplates` | bool | label 也写进 pod template | 常与上一条搭配 |
| `namespace` | string | 渲染时设置 namespace | 优先级高于 `spec.destination.namespace` |
| `patches` | [] | 直接给 Kustomize 的 patch | 结构见下 |
| `components` | []string | 引入 component 目录 | 需 Kustomize ≥ v3.7.0 |
| `ignoreMissingComponents` | bool | 忽略本地不存在的 component | 组件由其它系统生成时的开关 |
| `apiVersions` | []string | 传给 Helm 的 api-versions | 仅在启用 helm 时生效 |
| `kubeVersion` | string | 传给 Helm 的 kube-version | 仅在启用 helm 时生效 |
| `version` | string | 指定 Kustomize 版本 | 必须在 `argocd-cm` 里注册（§5.3） |

`patches` 的结构（`install.yaml:2127-2157`）：

```yaml
kustomize:
  patches:
    - patch: |                      # 内联 patch 内容
        - op: replace
          path: /spec/replicas
          value: 3
      target:                        # 目标选择器
        group: apps
        version: v1
        kind: Deployment
        name: my-app
    - path: ./patches/sidecar.yaml  # 或引用文件
      target:
        kind: Deployment
        labelSelector: "app=my-app"
    - patch: |
        - op: add
          path: /metadata/labels/tier
          value: backend
      options:
        allowNameChange: true
```

`target` 支持 `group/version/kind/name/namespace/labelSelector/annotationSelector`；
`options` 支持 `allowNameChange`、`allowKindChange`。

---

## 5. 版本与 buildOptions 的三层概念

Kustomize 相关有**三个独立的版本层**，混在一起是排查问题的常见原因：

### 5.1 层一：Kustomize 自身版本

**Argo CD v3.5.6 内置 Kustomize v5.8.1**，证据链：

- `hack/tool-versions.sh`：`kustomize5_version=5.8.1`
- `hack/installers/install-kustomize.sh`：`KUSTOMIZE_VERSION=${KUSTOMIZE_VERSION:-$kustomize5_version}`
- `Dockerfile`：`INSTALL_PATH=/usr/local/bin ./install.sh kustomize` → `COPY --from=builder /usr/local/bin/kustomize /usr/local/bin/kustomize`

即：repo-server 容器里的 `kustomize` 可执行文件就是 v5.8.1。

### 5.2 层二：`argocd-cm` 里注册的版本与 buildOptions

上游 `docs/operator-manual/argocd-cm.yaml`（v3.5.6）列出的键：

| 键 | 作用 | 状态 |
|---|---|---|
| `kustomize.enable` | `"true"/"false"`，关掉后 Kustomize 不参与探测 | 有效 |
| `kustomize.buildOptions` | 默认版本的 `kustomize build` 附加参数 | 有效 |
| `kustomize.buildOptions.<version>` | 指定版本的附加参数 | 有效 |
| `kustomize.path.<version>` | 注册额外 Kustomize 二进制路径 | 有效（推荐） |
| `kustomize.version.<version>` | 同上（旧写法） | **已废弃** |

**本仓库现状**：`install.yaml` 里 `argocd-cm` 的 `data` 只有 `resource.customizations.*` 和 `resource.exclusions`
（`install.yaml:31497-31598`），**没有任何 `kustomize.*` 键**——
也就是说当前部署跑的是纯默认行为：无额外 build options、无注册版本、只用内置 v5.8.1。

上游读取逻辑（`util/settings/settings.go`）：

```go
// extract build options for the default version
if options, ok := argoCDCM.Data[kustomizeBuildOptionsKey]; ok { settings.BuildOptions = options }

// extract version and build options from kustomize.buildOptions.<version>
if strings.HasPrefix(k, kustomizeBuildOptionsKey) && k != kustomizeBuildOptionsKey { ... }

// extract version and path from kustomize.path.<version>
if strings.HasPrefix(k, kustomizePathPrefixKey) { ... }
```

### 5.3 层三：Application 声明的版本

`spec.source.kustomize.version` 必须**在 `argocd-cm` 里注册过**，否则渲染直接失败：

```go
// util/settings/settings.go —— GetKustomizeBinaryPath()
if source.Kustomize != nil && source.Kustomize.Version != "" {
    for _, ver := range ks.Versions {
        if ver.Name == source.Kustomize.Version { return ver.Path, nil }
    }
    return "", KustomizeVersionNotRegisteredError{Version: source.Kustomize.Version}
}
```

典型错误：`kustomize version ... is not registered`。

### 5.4 本地渲染与集群渲染的一致性

本机 `kubectl v1.37.1` 内嵌的 Kustomize 版本是 **v5.8.1**（`kubectl version --client` 输出 `kustomizeVersion: v5.8.1`），
与 Argo CD v3.5.6 内置版本**完全一致**——这是做本地预演的有利条件。

但仍有两个不等价点，必须记住：

1. `argocd-cm` 的 `kustomize.buildOptions` 在本地不会自动生效，需要手动带上同样的 flag。
2. `kubectl kustomize` 没有 `kustomize edit` 子命令，
   **无法本地复现 Application 级覆盖**（`namePrefix`/`images`/`patches` 等），
   除非把这些覆盖显式写进 Git 里的 overlay —— 这也是本文推荐的做法（§6.3）。

---

## 6. 在本仓库落地

### 6.1 已有材料

| 材料 | 位置 | 与 Kustomize 的关系 |
|---|---|---|
| Application 示例 | `examples/argocd-application/04-kustomize.yaml` | 本仓库唯一的 Kustomize Application 范例 |
| 示例说明 | `examples/argocd-application/README.md` | "环境差异用 overlay，不复制 YAML" |
| Application 字段表 | `argocd-application-guide.md` L123 | `kustomize.*` 字段归类 |
| Application 示例（正文） | `argocd-application-guide.md` 例 4 | `namePrefix` + `namespace` 表达环境差异 |
| 推荐目录布局 | `argocd-admin-guide.md` §6.2 | `gitops/` + `apps/` + `environments/` + `shared/kustomize/` |
| D3 架构决策 | `argocd-topics/00-architecture-no-crossplane.md` | "组合/环境差异用 Helm values / Kustomize overlay" |
| ApplicationSet + Git generator | `argocd-topics/05-appset.md` | **目录里必须有 `kustomization.yaml`（或 `Chart.yaml`）** |
| 渲染失败排查 | `argocd-topics/09-troubleshooting.md` §0/§2 | `argocd app manifests` + repo-server 日志 |

### 6.2 现有示例解剖

`examples/argocd-application/04-kustomize.yaml`：

```yaml
spec:
  source:
    repoURL: git@github.com:YOUR_ORG/infra.git
    targetRevision: main
    path: envs/dev
    kustomize:
      namePrefix: dev-
      images:
        - my-app=gcr.io/my-repo/my-app:0.1
      replicas:
        - name: my-app
          count: 2
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app-dev
```

几个要点：

- `path: envs/dev` 指向 overlay 目录，overlay 内部 `resources: ../../base` 引用 base。
- `namePrefix: dev-` 让 dev 环境的资源名带前缀，**同一份 base 可以同时跑在 dev/prod 而不冲突**。
  这是 Kustomize 在 GitOps 里最实用的一个能力：多环境共享同一集群/同一 namespace 时，用前缀而不是复制 YAML。
- `images` / `replicas` 放在 Application 里，等价于把差异"外挂"到 Application，
  好处是同一个 overlay 目录可以被多个 Application 复用；代价是**本地看不到这些覆盖**（§8.1）。
- `destination.namespace` 与 `kustomize.namespace` 的优先级见 §8.4。

### 6.3 推荐：把环境差异写进 Git，Application 只做"寻址"

`examples/argocd-application/04-kustomize.yaml` 现在把差异放在 Application spec 里。
**更推荐**把差异写进 overlay，Application 只负责指路：

```yaml
# environments/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../apps/my-app/base
namePrefix: dev-
namespace: my-app-dev
replicas:
  - name: my-app
    count: 2
images:
  - my-app=gcr.io/my-repo/my-app:0.1
```

```yaml
# Application —— 只写寻址信息
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:YOUR_ORG/infra.git
    targetRevision: main
    path: environments/dev      # ← overlay 路径
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app-dev
  syncPolicy:
    automated:
      enabled: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

理由（按重要性排序）：

1. **本地可复现**：`kubectl kustomize environments/dev` 的输出 == Argo CD 渲染结果，PR 里能直接贴 diff。
2. **Git 是唯一事实源**：符合本仓库"晋级 = 改 Git 提交"的原则（`argocd-admin-guide.md` §6.3）。
3. **Application 保持幂等**：`Application` 对象变成纯声明，改它不会造成"配置漂移在集群外"。

**Application 级覆盖仍然有用**，但只建议用在两类场景：
- 同一 overlay 目录被多个 Application 复用（如同一份 base 部署到两个集群，靠 `namePrefix` 区分）。
- 需要在 UI 上临时调整副本数/镜像做灰度。

---

## 7. 与 ApplicationSet 配合

ApplicationSet 的 **Git directory generator** 与 Kustomize 是天然搭配：

- generator 扫描仓库目录，**目录里存在 `kustomization.yaml`（或 `Chart.yaml`）才会被识别为应用**
  （本仓库 `argocd-topics/05-appset.md` §排障表明确写了这条："路径 glob 不对 / 目录里没有 kustomization.yaml"）。
- 每个目录生成一个 Application，`path` 指向该目录 → 每个目录就是一个独立 overlay。

本仓库 `argocd-topics/examples/applicationset-matrix.yaml` 注释里给出的仓库结构正是：

```
apps/
  api/
    kustomization.yaml
  web/
    kustomization.yaml
```

**组合起来就是"矩阵式多环境部署"**：

```
environments/
  dev/    kustomization.yaml   → resources: ../../apps/api/base, namePrefix: dev-
  prod/   kustomization.yaml   → resources: ../../apps/api/base, namePrefix: prod-
```

generator 用 `path: environments/*` 出两个 Application，`{{.path.basename}}` 直接注入到
`namePrefix` / `namespace` 里——**环境差异仍然由 Kustomize 表达，ApplicationSet 只负责"发现 + 实例化"**，
职责不重叠。这是本仓库 `D3` 决策在 ApplicationSet 层面的落地方式。

---

## 8. 常见坑（逐条给出机制与解法）

### 8.1 坑一：Application 里写的 patch，本地 build 看不到

**现象**：`spec.source.kustomize.patches` 生效了（集群里资源变了），但本地 `kubectl kustomize` 渲染结果没有这段 patch。

**机制**：Argo CD 通过改写临时 checkout 里的 `kustomization.yaml` 来注入 patch（§3.3 源码注释原话：
*"In order to generate the manifests in your local environment, you will need to copy the patches into kustomization.yaml manually."*）。
你的 Git 仓库不会被改写。

**解法**：把 patch 写进 Git 里的 overlay（§6.3），或接受"本地复现需要手工同步 patch"。

### 8.2 坑二：load restrictor 与 flag 拼写

**现象 A**：overlay 引用了仓库根之外的文件时报
`security; file '...' is not in or below '...'`。

**机制**：Kustomize 默认 `--load-restrictor LoadRestrictionsRootOnly`，禁止加载 kustomization 根目录之外的文件。
在 Argo CD 里，"根"是**仓库根**（§3.2：`cmd.Dir = k.repoRoot`），
所以 `resources: ../../base`（目录引用）通常没问题，但 `configMapGenerator.files: ../../secret.txt`（文件引用）会被拦。

**解法**：在 `argocd-cm` 里放开：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  kustomize.buildOptions: --load-restrictor LoadRestrictionsNone
```

**现象 B（拼写陷阱）**：上游文档里同时存在两种写法：

- `docs/operator-manual/argocd-cm.yaml` 示例写的是 `--load_restrictor none`（Kustomize v3 时代的写法）；
- `docs/user-guide/kustomize.md` 写的是 `--load-restrictor LoadRestrictionsNone`（v5 写法）。

**Kustomize v5.8.1 只认后者的值**。实测（kustomize v5.8.1）：

```
$ kubectl kustomize . --load_restrictor none
error: illegal flag value --load-restrictor none; legal values: [LoadRestrictionsRootOnly LoadRestrictionsNone]
```

即：flag 名两种拼法都接受（`_` 会被规整成 `-`），但 **`none` 不是合法值**，必须写 `LoadRestrictionsNone`。
照抄 `argocd-cm.yaml` 示例里的 `--load_restrictor none` 会让所有 Kustomize 应用渲染失败。

### 8.3 坑三：`commonLabels` 改动了 selector

**现象**：更新时报 `Deployment.apps "x" is invalid: spec.selector: Invalid value: field is immutable`。

**机制**：`commonLabels` 会写进 `spec.selector.matchLabels`（`commonAnnotations` 不会）。
Deployment/StatefulSet 的 selector 创建后不可变。

**解法**：
- 用 `commonAnnotations` 代替 `commonLabels`；
- 或 `labelWithoutSelector: true`（label 不进 selector），必要时配 `labelIncludeTemplates: true`；
- 或把 label 直接写进 base 的 Deployment 里，只在 overlay 里加 annotation。

> 实测（kustomize v5.8.1）：`commonLabels: {team: platform}` 会同时写入
> `metadata.labels`、`spec.selector.matchLabels` 和 `spec.template.metadata.labels`——
> selector 被改动，是 Deployment 更新报 immutable 的直接原因。
>
> 附带一个版本注意：Kustomize v5 起 `commonLabels` 字段本身已废弃
> （渲染时会打印 `Warning: 'commonLabels' is deprecated. Please use 'labels' instead.`），
> 新写法是 `labels: [{pairs: {...}, includeSelectors: true}]`。
> 但 Argo CD 的 `spec.source.kustomize.commonLabels` 走的是 `kustomize edit add label` CLI，
> 不受该废弃影响。

### 8.4 坑四：namespace 设置了两次

**机制**：`spec.destination.namespace` **只在 manifest 缺少 namespace 时补上**，且它用 `kubectl` 改写，
会漏掉某些字段（典型：`ClusterRoleBinding` 的 `subjects[0].namespace`，报
`ClusterRoleBinding.rbac.authorization.k8s.io "x" is invalid: subjects[0].namespace: Required value.`）。
而 `spec.source.kustomize.namespace` 是让 **Kustomize 自己**设置 namespace 字段。

**优先级**：两者都设时，**以 `spec.source.kustomize.namespace` 为准**。

**解法**：涉及 RBAC / CRD 这类 namespace 字段容易被 kubectl 漏掉的资源，用 `spec.source.kustomize.namespace`。

### 8.5 坑五：`components` 报错 "require kustomize v3.7.0 and above"

**机制**：`util/kustomize/kustomize.go` 里显式检查版本：

```go
if getSemverSafe(ctx, k).LessThan(semver.MustParse("v3.7.0")) {
    return nil, nil, nil, errors.New("kustomize components require kustomize v3.7.0 and above")
}
```

**解法**：用内置版本（v5.8.1，≥ v3.7.0）即可；若 Application 指定了注册的老版本，需升级版本或去掉 `components`。

### 8.6 坑六：`kustomize version ... is not registered`

**机制**：`spec.source.kustomize.version` 指向的版本没在 `argocd-cm` 里注册（§5.3）。

**解法**：在 `argocd-cm` 注册二进制路径与该版本的 build options：

```yaml
data:
  kustomize.path.v5.4.3: /custom-tools/kustomize_5_4_3
  kustomize.buildOptions.v5.4.3: --load-restrictor LoadRestrictionsNone
```

（注册了二进制还不够，需要自己把二进制放进 repo-server 容器。）

### 8.7 坑七：Kustomize 里渲染 Helm chart 失败

**机制**：`helmCharts` 需要 `--enable-helm`，而**这个 flag 不在 Application spec 的可配置范围里**，
只能在 `argocd-cm` 全局开启（会作用于所有 Kustomize 应用）。

**解法**（上游给出的两条）：
- 在 `argocd-cm` 里设 `kustomize.buildOptions: --enable-helm`；
- 或改用 Config Management Plugin 定制渲染流程。

### 8.8 坑八：改 `namePrefix` 导致资源重建

**现象**：把 `namePrefix` 从 `dev-` 改成 `dev2-` 后，旧资源被删、新资源被建，数据全部丢失。

**机制**：`namePrefix` 改的是**资源名**（`metadata.name`），K8s 里 name 变了就是另一个对象。
Argo CD 按名字做 prune，就会把旧的删掉。

**解法**：不要用 namePrefix 做"版本切换"；namePrefix 应当在环境创建时就固定。

### 8.9 坑九：本地 build 通过、集群渲染失败

**排查顺序**（本仓库 `argocd-topics/09-troubleshooting.md` §0 的通用顺序同样适用）：

```bash
# 1. 看渲染结果（Argo CD 视角）
argocd app manifests my-app-dev

# 2. 看 diff
argocd app diff my-app-dev

# 3. 看 repo-server 日志（渲染错误在这里）
kubectl -n argocd logs deploy/argocd-repo-server --tail=200 | grep -i kustomize

# 4. 本地对照（版本与 Argo CD 内置一致：v5.8.1）
kubectl kustomize environments/dev
```

**常见根因排序**：`argocd-cm` 的 buildOptions 本地没带 → 本地能过集群不能过；
overlay 引用了集群上不存在/不可见的文件 → load restrictor；
`spec.source.path` 写错 → 渲染出的资源集与预期不符。

### 8.10 坑十：ApplicationSet 不生成 Application

**现象**：Git generator 一个 Application 都没生成。

**机制**：**目录里必须有 `kustomization.yaml`（或 `Chart.yaml`）**，否则该目录不被识别为应用目录
（本仓库 `argocd-topics/05-appset.md` 排障表明确列出）。

**解法**：确认 `directories.path` 的 glob 能匹配到目标目录，且目录内有 `kustomization.yaml`。

---

## 9. 排障命令速查

| 目的 | 命令 |
|---|---|
| 拿 Argo CD 渲染结果 | `argocd app manifests <app>` |
| 渲染 vs live state 差异 | `argocd app diff <app>`（退出码 1=有 diff，0=无 diff，2=错误） |
| 本地渲染（与内置同版本） | `kubectl kustomize <overlay-dir>` |
| 带与集群一致的 build options | `kubectl kustomize <dir> --load-restrictor LoadRestrictionsNone` |
| 看 Application 实际配置 | `argocd app get <app> -o yaml` |
| 看渲染错误 | `kubectl -n argocd logs deploy/argocd-repo-server --tail=200` |
| 看 ApplicationSet 状态 | `argocd appset list <appset>` |
| 改 Application 的 Kustomize 覆盖 | `argocd app set <app> --kustomize-image ... --kustomize-replica ... --nameprefix ...` |

> `argocd app set` 支持的 Kustomize 相关 flag（v3.5.6）：
> `--kustomize-image`、`--kustomize-replica`、`--kustomize-common-label`、`--kustomize-common-annotation`、
> `--kustomize-force-common-label`、`--kustomize-force-common-annotation`、
> `--kustomize-label-without-selector`、`--kustomize-label-include-templates`、
> `--kustomize-namespace`、`--kustomize-version`、`--kustomize-kube-version`、`--kustomize-api-versions`、
> `--ignore-missing-components`、`--nameprefix`。

---

## 10. 一页速记

1. **Kustomize 不碰集群**，它是 Argo CD 的渲染器；Argo CD v3.5.6 内置 Kustomize **v5.8.1**。
2. **识别**：目录里有 `kustomization.yaml` / `kustomization.yml` / `Kustomization` → Kustomize 类型；
   `spec.source.kustomize` 非空则显式锁定；`helm` + `kustomize` 同填会报错。
3. **渲染**：`kustomize build <appPath>`，cwd 是**仓库根**；Application 级覆盖通过 `kustomize edit set ...`
   在**临时 checkout** 上执行，**不会改你的 Git 仓库**。
4. **diff/sync 与 Kustomize 无关**：那完全是 Argo CD 的活。
5. **推荐做法**：环境差异写进 Git 的 overlay，Application 只写寻址信息——本地可复现、Git 单一事实源。
6. **三个版本层**：Kustomize 自身版本（v5.8.1）、`argocd-cm` 注册的版本与 buildOptions、Application 声明的版本（必须已注册）。
7. **buildOptions 拼写**：Kustomize v5 用 `--load-restrictor LoadRestrictionsNone`；
   `--load_restrictor none` 在 v5.8.1 上直接报 `illegal flag value`。
8. **本仓库现状**：`install.yaml` 的 `argocd-cm` 未配置任何 `kustomize.*` 键，跑的是纯默认行为。

---

## 附录：本文结论的证据位置

| 结论 | 证据 |
|---|---|
| Argo CD v3.5.6 | `install.yaml:32094`（`quay.io/argoproj/argocd:v3.5.6`） |
| 内置 Kustomize v5.8.1 | 上游 `v3.5.6`：`hack/tool-versions.sh`、`hack/installers/install-kustomize.sh`、`Dockerfile` |
| kustomization 文件名三选一 | 上游 `util/kustomize/kustomize.go:77` `KustomizationNames` |
| 源类型探测逻辑 | 上游 `util/app/discovery/discovery.go` `Discover()` / `AppType()` |
| 显式类型与冲突报错 | 上游 `pkg/apis/application/v1alpha1/types.go` `ExplicitType()` |
| 渲染主路径 | 上游 `reposerver/repository/repository.go` `ApplicationSourceTypeKustomize` 分支 |
| `kustomize edit` 实现覆盖 | 上游 `util/kustomize/kustomize.go` `Build()` |
| patch 注入方式与本地不可见 | 上游 `util/kustomize/kustomize.go` `Build()` 内注释 |
| components 版本门槛 v3.7.0 | 上游 `util/kustomize/kustomize.go` `Build()` |
| 版本注册与未注册报错 | 上游 `util/settings/settings.go` `GetKustomizeBinaryPath()` / `GetKustomizeSettings()` |
| buildOptions 解析 | 上游 `util/kustomize/kustomize.go` `parseKustomizeBuildOptions()` |
| `argocd-cm` 可配置键 | 上游 `docs/operator-manual/argocd-cm.yaml`（v3.5.6） |
| `--enable-helm` 限制 | 上游 `docs/user-guide/kustomize.md`（v3.5.6） |
| namespace 优先级 | 上游 `docs/user-guide/kustomize.md`（v3.5.6） |
| `spec.source.kustomize` 字段集 | 本仓库 `install.yaml:1249-1380`（Application CRD schema） |
| 本仓库 `argocd-cm` 无 kustomize 配置 | 本仓库 `install.yaml:31497-31598` |
| 本机 Kustomize 版本 v5.8.1 | `kubectl version --client` → `kustomizeVersion: v5.8.1` |
| load restrictor 实测行为与 flag 取值 | 本机 kustomize v5.8.1 实跑（含 `illegal flag value` 复现） |

> 上游源码基线：`argoproj/argo-cd` tag `v3.5.6`。
> 本仓库未配置 `kustomize.*` 的 `argocd-cm` 项，本文所有"默认行为"结论均以此为准；
> 若后续在 `argocd-cm` 增加 `kustomize.buildOptions`，§8.2 / §8.9 需重新核对。
