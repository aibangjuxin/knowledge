# 01 — KubeOps 是什么(含同名项目消歧)

> 调研时间:2026-10-25。GitHub 上以 `kubeops` 命名的仓库有 40+ 个,Star 数从 375 到 0 不等,
> 含义横跨"Operator SDK""桌面客户端""集群安装器""运维平台"四类。
> **先确认对象,再谈原理**,否则很容易把完全不相干的项目混为一谈。

---

## 1. 结论先行

| 问题 | 答案 |
|---|---|
| 权威的 `KubeOps` 是哪个? | `dotnet/dotnet-operator-sdk` —— **.NET 版 Kubernetes Operator SDK**,375★,Apache-2.0,由 .NET Foundation 支持,官方文档站 <https://dotnet.github.io/dotnet-operator-sdk/> |
| 它是干什么的? | 让 .NET 团队用 C# 写 **Kubernetes Operator**:定义 CRD、监听自定义资源、用代码把期望状态收敛成集群里的实际资源 |
| 它是"部署工具"吗? | **不是**。它不构建镜像、不读 Git、不做 CI。它只做一件事:**在集群内持续调谐(reconcile)** |
| 它等价于什么? | .NET 生态的 **kubebuilder**(官方原话:"Strongly inspired by kubebuilder") |
| 和 Argo CD / Flux 的关系? | 互补,不是替代。Argo CD / Flux 管"Git → YAML 同步",KubeOps 管"自定义资源 → 一组 K8s 资源的编排逻辑" |

官方 README 原文定义:

> **KubeOps** is a Kubernetes Operator SDK designed for .NET developers. It allows you to leverage your
> C# skills and the rich .NET ecosystem to build powerful Kubernetes controllers that automate the
> management of complex applications.

---

## 2. 同名项目消歧表

搜 "kubeops" 之前先对一下这张表,别选错对象。

| 项目 | 语言 | Star | 它是什么 | 与本目录主线的关系 |
|---|---|---|---|---|
| **`dotnet/dotnet-operator-sdk`** | C# | 375 | **.NET Operator SDK**,KubeOps 品牌的正主 | ✅ 本目录主线 |
| `kubeop/k8s` | Jinja/Shell | 244 | 用二进制一键装生产级高可用 K8s 集群(kubeop.com) | ❌ 集群**安装**工具,不是部署工具 |
| `trustspirit/kubeops` | TypeScript/Electron | 2 | K8s **桌面客户端**(看 Pod、查日志、管负载) | ❌ GUI 客户端 |
| `xuqil/KubeOps` | JavaScript | 12 | 基于 K8s 的**运维平台**(国内项目,带 Vue 前端) | ❌ 运维管理平台 |
| `yansongwel/kubeops` | Go | 1 | 企业级 K8s 统一管理平台(AI 巡检 + DevOps/CI-CD) | ❌ 平台型产品 |
| `rahulyadavsudo/KubeOps` | TypeScript | 0 | Kubernetes 部署流水线与可观测性平台 | ❌ 平台型产品 |
| `kubeopsai/k8s-telemetry-mcp` | Python | — | **KubeOpsAI**:只读的可观测性 MCP Server + AWS 事故重建 Agent | ❌ 只读,**不做部署** |
| `gitkube/gitkube`(原仓库已 404,GitCode 有镜像) | Go | — | **git push 直接构建并部署到 K8s**,SSH 公钥认证 + RBAC + 多租户 | ⚠️ 范式参考,见 [04 交付范式](04-delivery-paradigms.md) 第 4 节 |

> **特别提醒**:很多人搜 "kubeops" 会先撞上 `kubeopsai`——它是 2026 年的新项目,做 AI 驱动的 K8s 事故重建,
> 23 个工具**全部只读**,明确不写任何集群资源。它和本目录讲的 Operator 交付链路**不是一回事**。

---

## 3. KubeOps 到底在解决什么问题

### 3.1 没有 Operator 时的问题

假设你要在 K8s 里部署一个"有状态应用",它需要:Deployment + Service + ConfigMap + HPA + PVC + 迁移 Job,
而且不同环境副本数/域名/密钥都不一样。

不用 Operator 时,你能想到的办法都各有硬伤:

| 办法 | 问题 |
|---|---|
| Helm Chart | 能渲染出 YAML,但**渲染完就结束**,后续状态漂移(有人手动改了 Deployment)没人管 |
| CI 里 `kubectl apply` | 流水线是"事件驱动一次",不持续;而且 CI 侧必须持有生产 kubeconfig,凭据暴露面大 |
| 手写一堆 YAML | 重复、难维护、没状态反馈 |

### 3.2 Operator 的答案

Operator 的思路来自 Kubernetes 自身的控制面(Deployment controller、StatefulSet controller 都是 Operator):

> **把运维知识写成代码,并让它常驻运行,持续把实际状态拉回期望状态。**

于是"部署一个有状态应用"变成:提交一个 **CR**(Custom Resource,比如 `V1DemoEntity`),
Operator 看到它,创建/更新对应的 5 个 K8s 资源,并把结果写回 CR 的 `status`。

三大特性:

1. **声明式**:CR 里写期望(3 副本、镜像 `v2.4.1`),Operator 保证实际状态向它靠拢
2. **持续性**:不是跑一次就结束,而是永远在循环,改了也会被纠正回来(self-heal)
3. **可组合**:CR 可以是别人 CR 的输入,一个 Operator 的输出可以是另一个 Operator 的输入

---

## 4. 核心概念速览

| 概念 | 说明 | KubeOps 里的对应物 |
|---|---|---|
| **CRD**(CustomResourceDefinition) | 扩展 K8s API,声明一种新的资源类型 | 用 C# class + `[KubernetesEntity]` 属性声明,自动转成 CRD YAML |
| **CR**(Custom Resource) | CRD 的一个实例,就是"期望状态"的载体 | 你的 C# entity 对象 |
| **Controller** | 监听 CR 并执行调谐逻辑的类 | 实现 `IEntityController<TEntity>` |
| **Reconcile** | 比对期望与实际,有差异就修正 | `ReconcileAsync()` |
| **Finalizer** | CR 被删除前先执行清理逻辑,保证不留下垃圾资源 | 实现 `IEntityFinalizer<TEntity>` |
| **Webhook** | CR 写入时 Admission 校验/变更;多版本 CRD 之间转换 | ASP.NET Core 集成,内置支持 |
| **Leader Election** | 多副本时只让一个实例干活 | 内置 `LeaderElectionType.Single` |

---

## 5. 十个包分别干什么

KubeOps 是模块化的,只装你需要的:

| 包 | 职责 |
|---|---|
| `KubeOps.Abstractions` | 核心接口与属性(`[KubernetesEntity]` 等),必装 |
| `KubeOps.Operator` | **运行时引擎**:监听、排队、并发控制、调谐调度、finalizer 生命周期 |
| `KubeOps.Operator.Web` | 把 Operator 接入 ASP.NET Core,用于暴露 Admission / Conversion Webhook |
| `KubeOps.KubernetesClient` | 基于官方 `KubernetesClient` 的增强客户端,封装常用操作 |
| `KubeOps.Generator` | Roslyn 源码生成器,自动生成 CRD / Controller / RBAC 样板代码 |
| `KubeOps.Transpiler` | 把 .NET 类型定义转成 K8s YAML(CRD、RBAC) |
| `KubeOps.Cli` | `kubeops` 命令行工具:脚手架、生成 CRD/RBAC、安装卸载 |
| `KubeOps.Templates` | `dotnet new operator` 项目模板 |
| `KubeOps.Asppire` / `KubeOps.Aspire.Hosting` | .NET Aspire 集成,把 Operator 作为 AppHost 资源编排 |

---

## 6. 什么时候**不**该用 KubeOps

别把它当银弹,以下情况用 GitOps 或现成工具更划算:

- **只是想把 YAML 同步到集群** → Argo CD / Flux 更简单,别写 Operator
- **只是要 CI 跑一次 apply** → GitHub Actions + kubectl 就够
- **没有 .NET 技术栈** → Go 用 kubebuilder,Java 用 java-operator-sdk
- **需求是"平台化交付几十种应用模板"** → 那不是 Operator SDK 的定位,用交付平台(Backstage 等)

---

## 参考

- 官方文档:<https://dotnet.github.io/dotnet-operator-sdk/>
- 源码与示例:<https://github.com/dotnet/dotnet-operator-sdk>
- Introduction(Reconciliation Loop 原文):<https://dotnet.github.io/dotnet-operator-sdk/docs/operator/>
- Kubernetes Operator 概念:<https://kubernetes.io/docs/concepts/extend-kubernetes/operator/>
