# KubeOps — 概念、工作原理与 GitHub push → K8s 交付链路

> **一句话结论**:`KubeOps` 是微软 /.NET Foundation 维护的 **.NET 版 Kubernetes Operator SDK**(`dotnet/dotnet-operator-sdk`)。
> 它不是一个"部署工具",而是一套**让在集群内运行的 Operator 持续把实际状态收敛到期望状态**的框架。
> 你看到的"GitHub push → 触发 Worker → 把服务部署到 K8s"这个场景,正是 Operator 驱动交付范式的标准形态:
> **CI Worker 负责产出新制品并更新期望状态,集群内的 Operator(也就是那个"跟着走"的 Worker)负责把期望状态落到 K8s。**

> ⚠️ **同名消歧必读**:`kubeops` 这个名字在 GitHub 上有 40+ 个同名仓库,含义完全不同。
> 本目录以权威的 [.NET KubeOps](https://github.com/dotnet/dotnet-operator-sdk) 为主线,
> 其余同名项目在 [docs/01-what-is-kubeops.md](docs/01-what-is-kubeops.md) 中单独列表说明,避免以后搜错对象。

---

## 目录

| 文档 | 内容 | 适合谁 |
|---|---|---|
| [01-what-is-kubeops.md](docs/01-what-is-kubeops.md) | KubeOps 是什么 + 同名项目消歧表 + 与 kubebuilder / Operator SDK 的关系 | 第一次接触,想确认"我说的对不对" |
| [02-how-it-works.md](docs/02-how-it-works.md) | 工作原理:Reconcile Loop、事件管线(Event Pipeline)、五大构件、并发与去重策略 | 想搞懂"它到底怎么跑起来的" |
| [03-github-push-to-k8s-flow.md](docs/03-github-push-to-k8s-flow.md) | **你描述的那个场景**:GitHub push → Worker follow 流 → K8s 部署的完整链路 | 想把概念落到自己的交付链路上 |
| [04-delivery-paradigms.md](docs/04-delivery-paradigms.md) | 四种交付范式对比(CI 推 / GitOps 拉 / Operator 驱动 / git push 直部署)+ 选型决策树 | 做技术选型、要写 ADR |
| [05-hands-on.md](docs/05-hands-on.md) | 最小可运行示例:CRD + Controller + CLI + RBAC + GitHub Actions 交付 | 要动手写一个 Operator |

---

## 速查卡

| 维度 | 事实 |
|---|---|
| 项目 | [dotnet/dotnet-operator-sdk](https://github.com/dotnet/dotnet-operator-sdk)(375★,Apache-2.0,.NET Foundation 支持) |
| 定位 | .NET 版 Kubernetes Operator SDK,官方说明"Strongly inspired by kubebuilder" |
| 运行环境 | .NET 8 / 9 / 10(构建期包 netstandard2.0) |
| 核心接口 | `IEntityController<TEntity>`(调谐)、`IEntityFinalizer<TEntity>`(清理) |
| 代码生成 | Roslyn Source Generator + `kubeops` CLI(`generate` / `install` / `uninstall`) |
| 附加能力 | Admission/Conversion Webhook(ASP.NET Core 集成)、Leader Election、OpenTelemetry 指标、.NET Aspire 集成 |
| 适用语言栈 | .NET / C# 团队;Go 生态对应 kubebuilder、Java 对应 java-operator-sdk |
| 不解决什么 | 不负责 CI 构建镜像、不负责 Git 同步(那是 Argo CD / Flux 的活) |

---

## 那个场景,一句话串起来

```
git push ──► CI Worker(构建镜像 / 更新期望状态)──► K8s API
                                                     │
                                          ┌──────────▼──────────┐
                                          │  KubeOps Operator   │  ← 集群内的"Worker"
                                          │  watch → queue →    │     持续 follow 资源变化
                                          │  reconcile → apply  │
                                          └──────────┬──────────┘
                                                     ▼
                                          Deployment / Service / HPA
                                                     ▼
                                            新 Pod 滚动上线
```

三条**互相独立**的职责线,别混在一起看:

| 角色 | 干什么 | 谁干的 |
|---|---|---|
| **CI Worker** | 编译、测试、打镜像、推镜像仓库 | GitHub Actions / Tekton / Argo Workflows 的 runner |
| **期望状态载体** | 声明"这个服务该长什么样" | CR(KubeOps Operator 模式)或 Git 里的 YAML(GitOps 模式) |
| **执行者(Worker)** | 把期望状态变成集群里的实际对象 | 集群内的 KubeOps Operator,或 Argo CD / Flux |

详细拆解见 [docs/03-github-push-to-k8s-flow.md](docs/03-github-push-to-k8s-flow.md)。

---

## 三条必须记住的规则

1. **Operator 不是"跑一次"的脚本,是永不退出的循环。**
   `Observe → Compare → Act → Repeat`,期望状态和实际状态不一致就改,一致就等下一个事件。

2. **写 status 不会再次触发自己。**
   KubeOps 默认按 `metadata.generation` 变化去重,status / label / annotation 的写入被过滤掉,
   所以你可以放心地在 controller 里回写状态。

3. **删除清理必须用 Finalizer,不能用 `DeletedAsync`。**
   官方明确标注 `DeletedAsync` 是"仅通知性"的、异步执行、**不保证清理完成**;
   同名对象被删后重建时,新旧两次调谐可能并行,清理逻辑必须幂等。

---

## 权威依据

- 官方文档站:<https://dotnet.github.io/dotnet-operator-sdk/>
- 源码:<https://github.com/dotnet/dotnet-operator-sdk>
- Controller / 事件管线原文:<https://dotnet.github.io/dotnet-operator-sdk/docs/operator/building-blocks/controllers>
- 部署原文:<https://dotnet.github.io/dotnet-operator-sdk/docs/operator/deployment/>
- CLI:<https://github.com/dotnet/dotnet-operator-sdk/blob/main/src/KubeOps.Cli/README.md>
- Kubernetes Operator 概念:<https://kubernetes.io/docs/concepts/extend-kubernetes/operator/>
