# sigs · Kubernetes SIGs 生态地图，以及我们能借鉴什么

> **副标题**：`kubernetes-sigs` 这个 GitHub 组织有 210 个公开仓库、17 万 star。
> 它不是一个"产品集合"，而是 **Kubernetes 社区里所有"没进核心仓库、但已成事实标准"的项目的落地处**。
> 我们在做 GitOps + CR Check 门禁的���候，**该抄的是它的设计范式，不是它的项目清单**。
>
> **取材方式**：直接读 GitHub API 的真实数据（仓库清单、topics、license、star、
> `kubernetes/community` 的 `sigs.yaml`、各仓库 README 原文），
> 不是靠印象。**数据快照时间：2026-11-10**。
>
> **一句话结论**
> **sigs 值得学的不是"用哪个项目"，而是"它怎么把一个 Kubernetes 生态项目做成事实标准"**——
> 结论有三条：① **声明式 API + 独立 provider**（Cluster API / Gateway API / CSI）
> 是扩展 K8s 的通用套路；② **"先有 conformance，再有生态"**（Gateway API、Prow）
> 让互操作有客观标准；③ **状态外置 + 单一聚合判定**（Prow 的 label + tide context）
> 是门禁类系统唯一可抄的模型。详见 §4。

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-tldr) | TL;DR |
| [§1](#1-sigs-是什么组织结构长什么样) | SIGs 是什么：组织结构长什么样 |
| [§2](#2-生态地图按-sig-分组210-个仓库) | ★ 生态地图：按 SIG 分组（210 个仓库） |
| [§3](#3-八个能力域sigs-到底能做什么) | ★ 八个能力域：sigs 到底能做什么 |
| [§4](#4--值得借鉴的-8-个设计) | ★ **值得借鉴的 8 个设计**（逐条：现象 → 证据 → 为什么 → 怎么抄） |
| [§5](#5-值得警惕--不要盲目抄的地方) | 值得警惕 / 不要盲目抄的地方 |
| [§6](#6-映射到我们的行动清单) | 映射到我们的行动清单（P1 / P2 / P3） |
| [§7](#7-附录-a证据速查) | 附录 A：证据速查 |
| [§8](#8-附录-b复现命令) | 附录 B：复现命令 |
| [§9](#9-相关文档) | 相关文档 |

---

## 0. TL;DR

1. **`kubernetes-sigs` 是"社区 SIG 的代码托管处"，不是"某个人或某个团队的产品线"。**
   仓库按 **SIG（Special Interest Group）** 归属，每个 SIG 有 charter（章程）、
   会议、chair、tech lead、以及一份 `sigs.yaml` 声明"我下面有哪些仓库"。
   实测 `kubernetes/community` 的 `sigs.yaml` 里，`sig-api-machinery` 挂 15 个 subproject、
   `sig-apps` 挂 9 个 —— 但这些 subproject 横跨 `kubernetes` / `kubernetes-client` /
   `kubernetes-sigs` 三个组织，其中落在 `kubernetes-sigs` 的分别是 16 个和 10 个仓库。

2. **210 个公开仓库，17.17 万 star，语言压倒性是 Go（169/210）。**
   Top 5：kubespray(18826)、kind(15605)、kustomize(12197)、kubebuilder(9361)、external-dns(9147)。

3. **★ 三大"元模式"**（详见 §4）：
   - **声明式 API + provider 拆分**——Cluster API / Gateway API / CSI / external-dns 都用同一招：
     **核心 API 与厂商实现分离**，第三方只实现接口。
   - **先定 conformance，再长生态**——Gateway API 有 conformance 报告制度，
     CSI 有 conformance 测试套件。**没有客观互操作标准，生态就会烂。**
   - **状态外置 + 单一聚合判定**——Prow 把"为什么不能合并"拆成 `do-not-merge/*` label
     + 一个 `tide` context。这正是我们的 CR Check 最该抄的一层（§4.8）。

4. **我们的 CR Check 已经在 Prow 那条线上走过一次**（[`prow-pulls.md`](./prow-pulls.md) 拆了 13 个设计）。
   本文**不重复**那 13 条，只补 sigs 里**其它仓库**提供的、
   我们还没看过的设计（§4.1 – §4.7），并补上 Prow 的定位（§4.8）。

5. **可以直接用的现成件**（不用自己写）：`kubectl-validate`（服务端同源的本地校验）、
   `crdify`（CRD 破坏性变更检测）、`kube-api-linter`（API 规范 linter）、
   `cli-utils`（带 inventory 的 apply/prune）—— 前两个在 §3 域 2，后两个在 §3 域 6。

---

## 1. SIGs 是什么：组织结构长什么样

### 1.1 三层结构

```
kubernetes/community            ← SIG 的"元数据"仓库
  ├── sigs.yaml                 ← 全局 SIG 注册表（dir / name / mission_statement / chairs / meetings）
  ├── sig-<name>/
  │   ├── charter.md            ← 章程：这个 SIG 负责什么、不负责什么
  │   └── README.md             ← 会议时间、Slack、邮件列表
  └── sig-<name>/sigs.yaml      ← 部分 SIG 自带：本 SIG 名下有哪些仓库

kubernetes-sigs/                ← 代码托管处（210 个公开仓库）
  └── <project>/
      ├── OWNERS                ← 谁能 approve（approvers / emeritus_approvers）
      ├── go.mod                ← module sigs.k8s.io/<project>
      ├── README.md
      └── ...

sigs.k8s.io/<project>           ← 文档站（约定，不是强制）
```

### 1.2 仓库怎么知道自己属于哪个 SIG

实测有**两套机制，且不完全一致**——这是踩坑点：

| 机制 | 来源 | 覆盖情况 | 可信度 |
|---|---|---|---|
| **GitHub topic** `k8s-sig-<name>` | 仓库自己打的标签 | 210 个仓库里 **72 个没打任何 `k8s-sig-*` 标签** | 覆盖不全 |
| **`sigs.yaml` 的 `subprojects`** | community 仓库里人工维护 | 只有 4 个 SIG 有列表：`sig-api-machinery`(15 个 subproject / 16 个 sigs 仓库)、`sig-apps`(9 / 10)、`sig-architecture`(1 / 1)、`sig-windows`(6 / 7) | 权威但不全 |

**实测差异**（同一批仓库，两个来源对不上）：

| 仓库 | topic 说 | sigs.yaml 说 | 事实 |
|---|---|---|---|
| `crdify` | ❌ 无 `k8s-sig-*` | ✅ sig-api-machinery | 以 sigs.yaml 为准 |
| `kube-api-linter` | ❌ 无 `k8s-sig-*` | ✅ sig-api-machinery | 以 sigs.yaml 为准 |
| `agent-sandbox` / `lws` / `jobset` | ❌ 无 | ✅ sig-apps | 以 sigs.yaml 为准 |
| `headlamp` | ✅ k8s-sig-architecture | ✅ sig-architecture | 一致 |
| `apisnoop` / `depstat` | ✅ k8s-sig-architecture | ❌ 未列 | topic 更全 |
| `apisnoop` / `depstat` | ✅ k8s-sig-architecture | ❌ 未列 | topic 更全 |

> ★ **结论**：**topic 用来做粗筛，sigs.yaml 用来做定论。**
> 两者不一致时以 `sigs.yaml` 为准——它是 community 仓库里人工维护的注册表。

### 1.3 三条硬约定（所有 sigs 仓库都一样）

| 约定 | 实测证据 |
|---|---|
| **Go module 路径 = `sigs.k8s.io/<repo>`** | `controller-runtime` / `kueue` / `cluster-api` / `gateway-api` / `crdify` / `kube-api-linter` / `cli-utils` / `descheduler` 全部是。**例外**：`kubebuilder` 是 `sigs.k8s.io/kubebuilder/v4`（带 major），`kro` 用 `github.com/kubernetes-sigs/kro`（未迁移） |
| **文档站 = `<repo>.sigs.k8s.io`** | 210 个仓库里 **51 个填了 homepage**，其中 **32 个**用这个域名（`kind` / `kueue` / `cluster-api` / `gateway-api` / `image-builder` / `jobset` / `lws` / `agent-sandbox` / `mcp-lifecycle-operator` …）。另有 5 个用 `kubernetes-sigs.github.io/*` |
| **License = Apache-2.0** | 全量 210 个仓库：**207 个 Apache-2.0**；例外 3 个 —— `lwkd`(CC-BY-4.0，文档站)、`yaml` / `json`（GitHub 未识别到 license 文件） |

### 1.4 组织级基建（`.github` 仓库）

`kubernetes-sigs/.github` 只放 **org 级默认的 community-health 文件**（目前是 `SECURITY.md`）。
其余模板在 `kubernetes/kubernetes-template-project`，README 明确列了**每个项目必须有**的文件：

```
README.md              项目目标、sponsoring sig、社区联系方式
OWNERS                 项目 lead 列为 approvers
CONTRIBUTING.md        如何贡献
code-of-conduct.md     未修改的副本
LICENSE                代码 = Apache 2.0 / 文档 = Creative Commons 4.0，且不得有自定义内容
SECURITY_CONTACTS      PSIRT 联络点，必须遵守 Embargo Policy
```

> ★ **这套"最小合规文件集"就是 K8s 生态的准入门槛**。
> 我们做内部平台时，如果希望外部团队能自己接进来，同样要先把
> `README / OWNERS / CONTRIBUTING / LICENSE / SECURITY_CONTACTS` 这五件套标准化。

---

## 2. 生态地图：按 SIG 分组（210 个仓库）

按 `k8s-sig-*` topic 粗筛 + `sigs.yaml` 校正后。star 为 2026-11-10 快照。

| SIG | 仓库数 | 代表项目（star） | 它负责什么 |
|---|---|---|---|
| **sig-cluster-lifecycle** | 15 | kubespray(18826)、cluster-api(4348)、cluster-api-provider-aws(730)、image-builder(551)、cluster-api-provider-gcp(232)、cluster-api-operator(291) | 集群的**声明式生命周期**：建集群、升版本、管 addon |
| **sig-api-machinery** | 16 | kubebuilder(9361)、controller-runtime(2989)、controller-tools(867)、apiserver-builder-alpha(823)、structured-merge-diff(137)、kube-api-linter(142)、crdify(46) | **写扩展 API 的工具链**：脚手架、controller 库、CRD 校验 |
| **sig-apps** | 10 | agent-sandbox(4564)、lws(905)、application(523)、jobset(347)、mcp-lifecycle-operator(54) | **工作负载形态**：AI agent、分布式训练、多模板 Job |
| **sig-network** | 11 | external-dns(9147)、gateway-api(3044)、gateway-api-inference-extension(801)、network-policy-api(94) | **服务暴露与网络策略**：下一代 Ingress、网络策略 API |
| **sig-cli** | 5 | kustomize(12197)、krew(7049)、krew-index(705)、cli-utils(180) | **kubectl 生态**：配置定制、插件分发、批量 apply |
| **sig-testing** | 7 | kind(15605)、e2e-framework(670)、kubetest2(409)、prow(333)、boskos(156)、testgrid(8) | **测试与 CI**：本地集群、E2E 框架、CI 系统、测试看板 |
| **sig-scheduling** | 7 | descheduler(5569)、kwok(3220)、kueue(3147)、scheduler-plugins(1330)、kube-scheduler-simulator(1105) | **调度与配额**：抢占、队列、模拟、插件 |
| **sig-instrumentation** | 8 | metrics-server(6774)、prometheus-adapter(2093)、custom-metrics-apiserver(531) | **指标与自定义指标 API**（HPA/VPA 的数据源） |
| **sig-storage** | 7 | nfs-subdir-external-provisioner(3053)、sig-storage-local-static-provisioner(1211)、sig-storage-lib-external-provisioner(586) | **存储供应**：CSI 之前的 provisioner 体系 |
| **sig-node** | 5 | cri-tools(2025)、node-feature-discovery(1090)、security-profiles-operator(882) | **节点侧**：CRI、硬件发现、安全配置 |
| **sig-release** | 7 | zeitgeist(206)、promo-tools(176)、downloadkubernetes(127)、release-notes(64) | **发布工程**：依赖检查、制品晋级、发布说明 |
| **sig-multicluster** | 4 | mcs-api(262)、cluster-inventory-api(97)、work-api(75)、about-api(38) | **多集群**：跨集群服务、集群清单 |
| **sig-auth** | 4 | secrets-store-csi-driver(1567)、secrets-store-sync-controller(60) | **密钥与身份** |
| **sig-windows** | 7 | sig-windows-tools(134)、sig-windows-dev-tools(80)、windows-testing(43)、windows-gmsa(35) | **Windows 支持** |
| **sig-architecture** | 3 | headlamp(7593)、apisnoop(95)、depstat(37) | **架构约束与依赖治理** |
| **sig-security** | 1 | cve-feed-osv(15) | **安全流程** |
| **云厂商（sig-aws/gcp/azure/ibmcloud/vmware）** | 12 | aws-load-balancer-controller(4343)、aws-iam-authenticator(2337)、aws-ebs-csi-driver(1138)、aws-efs-csi-driver(805) | **云厂商实现**（证明 provider 模式可行） |
| **sig-docs / ui / scalability / contribex / infra** | 10 | contributor-playground(295)、inference-perf(272)、reference-docs(129)、dashboard-metrics-scraper(91)、maintainers(10) | 文档、UI、压测、社区基建 |

> ★ 仓库数合计 **175 次归属**（部分仓库同属多个 SIG），**覆盖 147 个仓库**；
> 剩下 **63 个仓库在两套机制里都没有归属**（多为早期/实验性项目）。

**无 `k8s-sig-*` topic 但值得关注**（72 个无 topic 仓库里的重点）：

| 仓库 | star | 是什么 | 真实归属 |
|---|---|---|---|
| `karpenter` | 2272 | 云原生节点自动伸缩（★ 注意：内容与 `aws/karpenter-core` **完全一致**，是同源的镜像/迁出） | 无 topic 标注；实为 sig-autoscaling 方向 |
| `kubernetes-mixin` | 2493 | Grafana dashboard + Prometheus 告警的 Jsonnet 集合 | 无 topic 标注；实为 sig-instrumentation 方向 |
| `headlamp` | 7593 | 厂商中立的 K8s Web UI，插件化 | ★ `sigs.yaml` 归 sig-architecture |
| `ingress2gateway` | 1057 | **Ingress → Gateway API 迁移工具** | 无 topic 标注；实为 sig-network 方向 |
| `kubectl-validate` | 278 | **与服务端同源的本地校验** | 无 topic 标注；实为 sig-cli 方向 |
| `bom` | 477 | SPDX SBOM 生成 | 无 topic 标注；实为 sig-release 方向 |
| `multicluster-runtime` | 318 | 多集群 controller 库 | 无 topic 标注；实为 sig-multicluster 方向 |
| `cluster-api-addon-provider-helm` | 187 | 用 Helm 管理集群 addon | 无 topic 标注；实为 sig-cluster-lifecycle 方向 |
| `kube-api-linter` | 142 | API 规范 linter（golangci-lint 插件） | ★ `sigs.yaml` 归 sig-api-machinery |
| `kube-scheduler-wasm-extension` | 128 | 用 Wasm 扩展调度器 | ★ topic `k8s-sig-scheduling` |
| `crdify` | 46 | **CRD 破坏性变更检测** | ★ `sigs.yaml` 归 sig-api-machinery |

---

## 3. 八个能力域：sigs 到底能做什么

把 210 个仓库按**能力**（而不是按 SIG）重排，能看出 sigs 覆盖了 K8s 平台的哪些面。

### 域 1 · 集群生命周期（建 / 升 / 管）

| 项目 | 能做什么 | 关键事实 |
|---|---|---|
| **cluster-api** | 用 K8s 风格的声明式 API 管理集群的创建、配置、升级 | README 原文："providing declarative APIs and tooling to simplify provisioning, upgrading, and operating multiple Kubernetes clusters"。**bootstrap/control-plane provider（kubeadm 内置）与 infrastructure provider 分离** |
| **cluster-api-provider-{aws,gcp,azure,vsphere,openstack,ibmcloud,digitalocean,cloudstack,kubevirt,kubemark}** | 各云实现 | **10 个 provider 证明"核心 API + 厂商实现"这个模式可行** |
| **cluster-api-operator** | 声明式管理 CAPI provider 本身（升级、配置） | README 原文："empower cluster administrators to handle the lifecycle of Cluster API providers within a management cluster using a declarative approach... automate workflows with **GitOps**" |
| **cluster-api-addon-provider-helm** (CAAPH) | 用 Helm chart 管理集群 addon | 基于 Cluster API Add-on Orchestration Proposal |
| **image-builder** | 构建多 provider × 多 OS 的节点镜像 | 有完整的 provider/OS 矩阵（ami/azure/gce/qemu/raw…）；💙 = 有 CI 测试覆盖 |
| **kubespray** | Ansible 部署生产集群 | 18826 star，全 org 第一。支持 AWS/GCE/Azure/OpenStack/vSphere/OCI/Baremetal |
| **kind** | Docker 跑本地 K8s 集群 | 15605 star。**每个 node 用 kubeadm 引导** |
| **cloud-provider-kind** | 给 kind 补上 LoadBalancer 能力 | 513 star。**用本地集群测云依赖功能的通用招法** |

### 域 2 · API 与 Controller 开发（写扩展）

| 项目 | 能做什么 | 关键事实 |
|---|---|---|
| **kubebuilder** | 用 CRD 构建 K8s API 的脚手架 | README 原文："Similar to web development frameworks such as *Ruby on Rails* and *SpringBoot*"。**构建在 controller-runtime + controller-tools 之上** |
| **controller-runtime** | 写 controller 的 Go 库 | **零主版本**（"We stick to a zero major version"），**每个 K8s minor 发一个 minor**，minor 之间允许 breaking change |
| **controller-tools** | controller 的 codegen / CRD 生成 | 同 controller-runtime 的版本策略 |
| **apiserver-builder-alpha** / **apiserver-runtime** | 聚合 API Server（非 CRD） | ★ apiserver-runtime README 明确写："**Alpha with no commitments from its maintainers**"、"may change drastically or be **cancelled with little or no public notice**" |
| **kro** | `ResourceGraphDefinition` —— 把一组资源 + 依赖关系打包成一个 CR | 3090 star，**SIG Cloud Provider** 下 |
| **kube-api-linter** | 按 API Conventions 检查 API 类型 | 142 star。**golangci-lint 插件形态** |
| **crdify** | 比对两个 CRD，找破坏性变更 | 支持 `kube://` / `file://` / `git://{ref}?path=` 三种源 |
| **kube-storage-version-migrator** | 把 etcd 里的数据迁移到最新存储版本 | 对应 KEP-0030 |
| **structured-merge-diff** | **server-side apply 的实现** | 字段所有权（fieldset）模型："which fields each manager is currently managing" |

### 域 3 · 网络与服务暴露

| 项目 | 能做什么 | 关键事实 |
|---|---|---|
| **gateway-api** | Ingress 的下一代（Gateway / HTTPRoute / GRPCRoute / TLSRoute / TCPRoute / UDPRoute / ReferenceGrant / BackendTLSPolicy） | v1.6.1 起 **v1 GA 资源清单**。**有 conformance 报告制度**（conformance/reports/） |
| **ingress2gateway** | 把 Ingress + 厂商 CRD 转成 Gateway API | **provider → IR → emitter 三段式**：providers 读 Ingress 生成中间表示，emitters 产出 Gateway API 资源。已支持 apisix/cilium/ingress-nginx/istio/gce/kong/nginx/openapi/traefik。★ **"不复制 annotation"是显式设计决定** |
| **external-dns** | 让 K8s 里的 Service/Ingress 驱动外部 DNS 记录 | ★ **不是 DNS server，而是"配置别人的 DNS provider"** —— 与 CSI 同构的 provider 模式 |
| **network-policy-api** | NetworkPolicy v1 之后的网络策略 API（含 ClusterNetworkPolicy） | GA 的是 `NetworkPolicy v1`；CNP 仍是 experimental |
| **kube-network-policies** | NetworkPolicy 的参考实现 | 支持传统 NP 与 CNP 两种 |
| **gwctl** | 管理和理解 Gateway API 资源的 CLI | 135 star |

### 域 4 · 调度、配额与弹性

| 项目 | 能做什么 | 关键事实 |
|---|---|---|
| **kueue** | K8s 原生作业队列：配额、公平共享、层级配额、gang 调度 | ★ **AdmissionCheck 机制**：外部组件可以参与 workload 的准入决策，状态机 `Pending / Ready / Retry / Rejected`。**这是 sigs 里最接近"外部门禁"的模型** |
| **descheduler** | 把 pod 从不合适的节点驱逐 | **不负责补调度**，依赖默认 scheduler |
| **kwok** | 不装 kubelet 模拟上千节点 | 3220 star，**做控制面压测的标准工具** |
| **kube-scheduler-simulator** | 离线模拟调度器，输出"哪个 plugin 对哪个 node 做了什么决策" | ★ 解决"没有特权就看不到调度细节"的问题 |
| **scheduler-plugins** | out-of-tree 调度插件 | "plugins that are exercised in **large companies**" |
| **kube-scheduler-wasm-extension** | 用 Wasm 扩展调度器 | 内嵌 wazero 运行时，**避免每次升级都要重新编译 Go 插件** |
| **cluster-autoscaler** | 节点自动伸缩的 provider-agnostic 核心逻辑 | README 明确："**parts of this repo are still WIP**"，核心逻辑仍在拆分中 |
| **karpenter** | 直接从 unschedulable pod 反推节点规格并创建 | **provider 与 core 分离**：core 在 sigs，各云 provider 在各自组织 |

### 域 5 · 指标、可观测与容量

| 项目 | 能做什么 |
|---|---|
| **metrics-server** | 资源指标（CPU/内存），HPA/VPA 的数据源 |
| **prometheus-adapter** | 实现 `custom.metrics.k8s.io`，把 Prometheus 指标喂给 HPA |
| **custom-metrics-apiserver** | 自定义指标 API 的框架 |
| **kubernetes-mixin** | **Grafana dashboard + Prometheus 告警的 Jsonnet 集合**（2493 star） |
| **usage-metrics-collector** | 高保真容量/用量指标采集（1s 间隔采样、采集时聚合） |
| **resource-state-metrics** | 把自定义资源的**状态**变成 metrics（`ResourceMetricsMonitor` CRD） |
| **logtools** | 日志调用相关工具 |

### 域 6 · CI/CD、测试与发布

| 项目 | 能做什么 | 关键事实 |
|---|---|---|
| **prow** | K8s 社区的 CI/CD 系统 | ★ 已在 [`prow-pulls.md`](./prow-pulls.md) 详拆。333 star，但**它定义的是范式不是代码** |
| **testgrid** | 测试结果看板（前端在 sigs，后端在 GoogleCloudPlatform/testgrid） | ★ **"看板"和"计算"分离** —— 这是它能独立演化的原因 |
| **e2e-framework** | 用 Go 原生 `go test` 写 E2E | 670 star |
| **kubetest2** | E2E 测试的启动/执行框架 | 409 star |
| **boskos** | CI 资源管理与租借 | 156 star。**大规模 CI 的资源池化** |
| **hydrophone** | 轻量 conformance 测试运行器 | 127 star |
| **kubectl-validate** | **本地校验原生类型与 CRD，尽量与服务端对齐** | ★ README 原文："written by Kubernetes apiserver authors **using the same code as the server-side**"。`kubectl validate ./file.yaml`，支持 `--version 1.27`、`--local-crds`、`--output json` |
| **cli-utils** | 批量 apply/prune，带 inventory 对象 | ★ README 原文："The project has evolved to encompass a broader scope, including CLI use and **server-side use in GitOps controllers**"。用 label 标记归属被认为有"significant downsides"（见 §4.4） |
| **zeitgeist** | 语言无关的外部依赖检查器 | 206 star |
| **depstat** | Go module 依赖图分析（stats/list/graph/cycles/why） | 37 star |
| **bom** | SPDX SBOM 生成（识别 400+ SPDX license） | 477 star |
| **promo-tools** | 制品晋级工具（promotion） | 176 star |
| **release-notes** | 发布说明生成 | 64 star |

### 域 7 · 存储与密钥

| 项目 | 能做什么 |
|---|---|
| **secrets-store-csi-driver** | 把外部密钥库（Vault、云 KMS 等）的 secret 挂进 pod（SIG Auth） |
| **secrets-store-sync-controller** | 把外部 secret **同步**成 K8s Secret（与上者互补：CSI 是挂载，同步是物化） |
| **nfs-subdir-external-provisioner** / **sig-storage-lib-external-provisioner** | 动态供应（CSI 之前的 provisioner 体系） |
| **container-object-storage-interface** (COSI) | 容器对象存储接口（bucket 语义） |
| **aws-ebs-csi-driver** / **aws-efs-csi-driver** / **gcp-compute-persistent-disk-csi-driver** 等 | 各云 CSI 实现 |

### 域 8 · 工作负载形态与多集群（2024 之后的新增面）

| 项目 | 能做什么 | 关键事实 |
|---|---|---|
| **agent-sandbox** | 声明式管理隔离的、有状态、单例的 workload（AI agent 运行时 / RL） | ★ 4564 star，**SIG Apps**。核心 CRD 是 `Sandbox` |
| **jobset** | 把一组 Job 作为一个单元管理（HPC / 分布式训练） | 347 star。多模板 job、自动 headless service |
| **lws** | LeaderWorkerSet / DisaggregatedSet —— 多机推理的 API | 905 star，与 llm-d 协同设计 |
| **mcp-lifecycle-operator** | 声明式部署/管理/滚动发布 **MCP Server** | ★ **v1beta1**，明确标注 "APIs and behavior may change" |
| **multicluster-runtime** | 用 controller-runtime 跨动态集群群 reconcile | "**no fork, no go mod replace**" —— 对上游 controller-runtime 的干净扩展 |
| **mcs-api** | 多集群服务 API（KEP-1645） | 262 star |
| **cluster-inventory-api** | 集群清单与放置决策（ClusterProfile API） | 97 star |
| **kube-agentic-networking** | agent 之间的通信治理与授权 | 122 star，**新**：目标是"Agent A can communicate with Tool B"这种**用户目标导向**的 API，而非协议导向 |
| **ai-gateway** / **ai-conformance** | AI Gateway 工作组提案 + AI 一致性测试 | 107 / 54 star |
| **dra-driver-* / dranet / dra-example-driver** | Dynamic Resource Allocation（GPU/设备）的 driver | DRA 是 node 资源分配的新模型 |

---

## 4. ★ 值得借鉴的 8 个设计

> §4.8 是 Prow 的定位（已在 [`prow-pulls.md`](./prow-pulls.md) 详拆 13 条，此处只做索引，不重复）。
> §4.1 – §4.7 是 **sigs 其它仓库** 提供的、我们还没看过的设计。

---

### 4.1 ★ 核心 API 与厂商实现彻底分离（Cluster API / Gateway API / CSI / external-dns）

**现象**

四套完全不同的技术栈，用了**同一个架构**：

| 项目 | 核心 | 厂商实现 |
|---|---|---|
| Cluster API | `sigs.k8s.io/cluster-api` 定义 `Cluster` / `Machine` / `MachineDeployment` | `cluster-api-provider-{aws,gcp,azure,vsphere,...}` |
| Gateway API | `sigs.k8s.io/gateway-api` 定义 `Gateway` / `HTTPRoute` | 各家 Ingress Controller / Gateway 实现 |
| CSI | Kubernetes 内置 `CSIDriver` / `CSINode` 对象 | `aws-ebs-csi-driver` / `gce-pd-csi-driver` / `azurefile-csi-driver`… |
| external-dns | `sigs.k8s.io/external-dns` 核心 | provider 插件（Route53 / Cloud DNS / …） |

**external-dns 的 README 把这个关系说得最清楚**：

> "Unlike KubeDNS, however, it's not a DNS server itself, but merely **configures other DNS providers** accordingly"

**为什么好**

1. **核心不背厂商债**。`cluster-api` 本身不需要知道什么是 EC2；`gateway-api` 不需要知道什么是 nginx。
2. **第三方能独立迭代**。厂商实现可以按自己的节奏发版，不用等核心。
3. **★ 对我们最直接的价值**：**CR Check 的"规则引擎"和"规则来源"应该分开**。
   `internal/rules/` 是引擎，CR 平台 / GitHub / 维护窗口是**规则来源**。
   现在如果规则散落在引擎里，每接一个新平台就要改引擎 —— 这正是要避免的。

**怎么抄**

```go
// 规则引擎只认"评估上下文"，不认具体平台
type Context interface {
    // 从 PR 上取 CR 号
    ExtractChangeRequestRefs() ([]string, error)
    // 从 CR 平台取 CR 状态
    FetchChangeRequestState(refs []string) (map[string]CRState, error)
    // 取当前时间（可注入，便于测试维护窗口）
    Now() time.Time
}
// 平台实现放在 internal/crplatform/ 各自文件里
```

**★ 证据**：`kubernetes-sigs/external-dns` README、`kubernetes-sigs/cluster-api` README 的 Providers 段。

---

### 4.2 ★ 先有 conformance 制度，再长生态（Gateway API / CSI / Gateway API conformance reports）

**现象**

Gateway API 有一套完整的**一致性认证制度**：

- `gateway-api/conformance/` 存放 conformance 测试套件
- `gateway-api/conformance/reports/README.md` 规定**提交报告的规则**
- 第三方实现跑通测试后**提交报告到仓库里**，任何人可查

CSI 也一样：Kubernetes 仓库里有 `test/e2e/storage` 的 CSI 一致性测试，各驱动实现必须通过。

**为什么好**

1. **★ 互操作有客观标准**。"我的 Gateway 实现兼容吗"不再靠口头承诺，靠一份可查的报告。
2. **★ 生态不烂**。没有 conformance 时，各实现各写各的，最后用户要写 N 份 YAML 才能用一个能力。
3. **文档即契约**。报告进仓库 = 变更可见、可 review、可回滚。

**怎么抄（对应我们的 CR Check）**

我们目前的 CR Check 是"我们自己的一个 App"，没有第三方。
但**如果我们要让别的团队的 GitHub 仓库也用我们的门禁**，就必须有类似 conformance 的东西：

| 层次 | 对应物 | 交付物 |
|---|---|---|
| API 契约 | CR 号的**识别规则**（`cr/1234` / `[CR-1234]`） | 一份可执行的 conformance 用例集 |
| 行为契约 | 每个判定维度的**期望输出**（通过/失败时分别应产生什么 label、什么 check description） | 一组 golden test |
| 集成契约 | App 安装后，仓库上需要配什么（branch protection / ruleset） | 一份 `verify-*.sh` 式的自检脚本 |

> 参考本目录已有的做法：[`git-apps/16-ruleset-install-runbook.md`](./git-apps/16-ruleset-install-runbook.md)
> 就是"安装 Runbook"这一层。**再往上一层就是 conformance**。

**★ 证据**：`gateway-api` README 的 "Gateway API conformance" 段 +
`gateway-api/conformance/reports/README.md`。

---

### 4.3 ★ Kueue 的 AdmissionCheck —— 外部系统参与准入决策的完整状态机

**现象**

Kueue 的 `AdmissionCheck` 是 sigs 里**最接近"外部门禁"的模型**。一个外部 controller
（`controllerName` 指定）可以决定 workload 能不能被 admit。状态机是**四态**：

| 状态 | 含义 | 官方文档语义 |
|---|---|---|
| `Pending` | 检查还没做 / 还没结束 | 未定 |
| `Ready` | 通过 | 可 admit |
| `Retry` | 暂时过不了，会退避重试 | "the check cannot pass at the moment, it will back off and retry" |
| `Rejected` | 短期内不会过，不值得重试 | "the check will not pass in the near future. It is not worth to retry" |

**关键行为**（官方文档逐条）：

- 配额预留完成后，Kueue **并发**跑该 ClusterQueue 上配置的所有 AdmissionCheck
- **所有** check 都 `Ready` 才 admit
- 某个 check 进入 `Retry`：
  - 已 Admitted 的 workload **会被 evict**
  - 配额会被**释放**
  - 发出 `EvictedDueToAdmissionCheck` 事件
- 某个 check 进入 `Rejected`：
  - workload 被**停用**（`workload.Spec.Active = False`）
  - 已 Admitted 的会 evict（reason = `Deactivated`）
  - 配额释放，发出 `AdmissionCheckRejected` 事件
- 如果 AdmissionCheck 对象不存在，或它的 controller 没有把 check 标为 `Active`
  → **ClusterQueue 被标记为 Inactive**

**★ 为什么这个模型值得抄**

它把 prow-pulls.md 里"合并门"的一个模糊概念，拆成了**两个正交的状态**：

```
"没通过"  →  Retry      →  可重试，暂不放行，但不代表永久否决
"没通过"  →  Rejected   →  明确否决，不需要再试
```

我们的 CR Check 现在的结论只有 pass/fail。**缺的就是这个中间态**：

| 我们的场景 | 对应状态 | 说明 |
|---|---|---|
| CR 平台 API 超时 / 5xx | `Retry` | 基础设施问题，**不该否决这次合并**，应退避重试 |
| CR 号不存在 | `Rejected` | 明确否决，重试也没用 |
| CR 存在但不在维护窗口内 | `Retry` | 窗口会开，值得等 |
| CR 已被撤销 | `Rejected` | 明确否决 |

**★ 再抄一条：check controller 不活跃 → 门禁整体停用（fail-open）**

Kueue 的选择是：**AdmissionCheck 的 controller 没标 Active，整个 ClusterQueue 标 Inactive**。
这是**显式的 fail-open**，但前提是**它有独立的、可见的状态位**。
对比我们 CR Check 现在的行为：进程挂了 → check 挂着不动 → GitHub 侧表现为"未完成"（fail-closed）。

> ★ **两种策略都成立，但必须显式选一个并写进文档。**
> 我们的 `how-to-atomic-idempotency.md` 明确选了 **fail-closed**（`in_progress` 不算通过）。
> 那就要照 Kueue 的反面做：**"我挂了就挡住"必须让用户看得见**，
> 而不是让 PR 静默卡住。

**★ 证据**：[`kueue.sigs.k8s.io/docs/concepts/admission_check/`](https://kueue.sigs.k8s.io/docs/concepts/admission_check/)（状态定义、evict 行为、Inactive 规则均为原文）。

---

### 4.4 ★ cli-utils 的 inventory —— "这次 apply 了什么"要显式存一份，而不是靠 label 猜

**现象**

`kubectl apply --prune` 用 **label** 标记"哪些对象属于这次 apply"，
cli-utils 的 README 直言这是错的：

> "The current implementation of `kubectl apply --prune` uses labels to identify the set of previously applied objects in the prune set calculation. **But the use of labels has significant downsides.** The current implementation of `kubectl apply --prune` is alpha, and **it is improbable that it will graduate to beta.**"

cli-utils 的做法：**把"上次 applied 的对象集合"存成一个 inventory 对象，apply 到集群里。**

它还定义了**三档归属策略**（`pkg/inventory/policy.go` 源码注释）：

```go
PolicyMustMatch        // 不允许与其他 inventory 或无主对象重叠
PolicyAdoptIfNoInventory // 允许接管"不属于任何 inventory"的对象
PolicyAdoptAll         // 允许接管任何对象
```

判定依据是**对象上的 `owning-inventory` annotation** 与 package 里的 inventory-id 比较。

**为什么好**

1. **★ 状态外置，且外置到一个有明确 schema 的对象里**。不是散落在 label 上，
   而是"一个可以被 `kubectl get -o yaml` 读出来、被 diff、被 review 的清单"。
2. **★ 归属语义显式化**。三档 policy 把"冲突了怎么办"从隐含变成配置。
3. **可回滚**：删掉 inventory 对象 = 放弃管理这批对象。

**★ 怎么抄（这条直接命中我们的痛点）**

`prow-pulls.md` §1.2 说 Prow 把状态放在 **label** 上（`do-not-merge/*`、`approved`、`lgtm`），
而 `how-to-atomic-idempotency.md` §7 指出我们 `recheck.Registry` 是**进程内内存**。

**中间路线是 cli-utils 的 inventory**：

```
不用 label（会散、会撞、会被别的工具用掉）
不用内存（进程重启就丢）
用 GitHub 上的一个可读对象存"我们管过什么"
```

对我们的 CR Check 具体说：除了 label 落盘，还可以**在 PR 上留一条带 META 的评论**
（prow-pulls.md §2.11 已经建议了 `<!-- META={...} -->`），
把"这个 PR 我们判定过什么、基于哪个 tree_sha、什么时候判的"存成**一份显式清单**。

**★ 证据**：`kubernetes-sigs/cli-utils` README 的 "Pruning" 段 + `pkg/inventory/policy.go` 源码注释。

---

### 4.5 ★ structured-merge-diff —— 字段所有权模型："谁在管这个字段"

**现象**

`structured-merge-diff` 是 **server-side apply 的实现**。它的 README 用"多 manager"模型解释：

> "We model resources in a control plane as having multiple 'managers'. Each manager is typically trying to manage only one aspect of a resource... To do this, we explicitly track (using the **fieldset** data structure) **which fields each manager is currently managing**."

两种写法的语义被明确区分：

| 写法 | 语义 |
|---|---|
| `PUT` / `PATCH` | "让这个对象**完全等于** X" |
| `APPLY` | "我管的字段应该等于 X，**别的字段我不管**" |

> "Any time a manager begins managing some new field, that field is removed from all other managers."

**为什么好**

1. **★ 多方共存不互相打架**。Argo CD 管 `spec.template`，HPA 管 `spec.replicas`，
   两者用 server-side apply 不会互相覆盖 —— 因为**字段所有权是显式跟踪的**。
2. **"我只声明我管的字段"是一个可组合的契约**。
3. **冲突可检测**：两个 manager 抢同一个字段 → SSA 报冲突，而不是静默 last-write-wins。

**★ 怎么抄**

我们的 Argo CD GitOps 已经在用 SSA。但这条对 **CR Check** 也有用：

> **每个判定维度应该是"一个 manager"，而不是"一个全局规则"。**
> 如果 CR 号规则和窗口规则都写 `spec.status`，就会互相覆盖。
> 按 SSA 的模型：**每个维度一个独立的 status 字段**（SSA 的 fieldset 机制会自动处理），
> 这样"CR 号无效"和"不在窗口内"才能**同时存在、分别展示**。

这正好补上 prow-pulls.md §2.1 的诉求：
"把三个维度的失败原因收集起来"—— 但更好的做法不是收集成一段文字，
而是**让它们在数据结构上就互不覆盖**。

**★ 证据**：`kubernetes-sigs/structured-merge-diff` README（fieldset / PUT-PATCH vs APPLY 段）。

---

### 4.6 ★ kubectl-validate —— 与服务端同源，而不是"看起来像"

**现象**

`kubectl-validate` 的 README 把自己的差异化优势说得很直白：

> "kubectl-validate is written by Kubernetes apiserver authors **using the same code as the server-side**. This allows kubectl-validate to give the **most accurate error messages** and support the Kubernetes-specific validations often ignored by other tools."

它**诚实地写出了自己的短板**：

> "For CRDs, users should expect a first-class experience **likely identical to how the server treats CRDs**. For Native Types, the OpenAPI definitions are a **best-effort replication of the handwritten validation rules** conducted by the apiserver."

**★ 为什么这个"诚实"比功能本身更值得学**

`kubectl-validate` 有一段专门讲"我知道我的 native types 校验不如 CRD 准"。
一个工具主动声明自己的**精度边界**，用户才知道什么时候能信它。

**★ 怎么抄**

我们的 CR Check 的失败信息要**标注结论来源和精度**：

```
❌ CR Check 未通过
[CR 引用无效]
  来源：CR 平台 API（返回 404，确定无效）
  置信度：确定
...
[CR 状态未就绪]
  来源：CR 平台 API 快照（快照时间 2026-11-10T06:29:11Z，可能已过期）
  置信度：快照，可能滞后
```

这和 prow-pulls.md §2.9 要求的"依据版本"是一回事，但更进一层：
**不只标版本，还要标"这个结论有多可靠"**。

**★ 证据**：`kubernetes-sigs/kubectl-validate` README 的 "Comparison With Other Tools" 与 "Drawbacks" 段。

---

### 4.7 ★ 时间线版本化 —— 文档站的版本选择器 = "读哪一版"

**现象**

多个 sigs 项目的文档站提供**版本切换**，且 README 里明确警告：

- `descheduler`："If you are using a published release of Descheduler (such as `registry.k8s.io/descheduler/descheduler:v0.37.0`), **follow the documentation in that version's release branch**"
- `node-feature-discovery`："**Using a release?** Read the docs for your version, not this branch. The `master` branch reflects work in progress and may not match your deployment."
- `kustomize`：README 里直接给出 **kubectl 内嵌 kustomize 版本的对照表**
  （v1.14 → v2.0.3 … v1.27 → v5.0.1）

**★ 为什么好**

"上游文档"和"你部署的版本"**经常不是一回事**。
主动给出版本对照表，等于把"你可能踩坑"这件事**前置**了。

**★ 怎么抄**

我们这套文档同样有版本问题（Argo CD 版本、kubectl 版本、K8s 版本）。
**每篇文档顶部都应该有一行"本文事实对应的版本"**。
本目录已有先例 —— [`10-argo-workflows-evaluation.md`](./10-argo-workflows-evaluation.md)
开头就写了 "**Argo Workflows v4.1**（`v4.1.6`, 2026-10-22 发布）"。

**★ kustomize 的版本对照表** 尤其值得抄进
[`00-architecture-no-crossplane.md`](./00-architecture-no-crossplane.md) 或
Kustomize 相关文档 —— 因为 Argo CD 内嵌的 kustomize 版本和本机装的版本可能不同，
而 `kubectl version --client` 会打印 `Kustomize Version`。

**★ 证据**：`descheduler` / `node-feature-discovery` README 的版本警告段；`kustomize` README 的 kubectl 版本对照表。

---

### 4.8 ★ Prow 的定位（索引，不重复）

**详见 [`prow-pulls.md`](./prow-pulls.md)**，那里逐条拆了 13 个设计。本文档只补三件事：

| # | 补充点 |
|---|---|
| 1 | **Prow 在 sigs 里的位置**：`k8s-sig-testing` 下，333 star，但**它定的是范式**。它证明"K8s 社区可以用 2016 年的设计跑 10 年"—— 因为状态在 GitHub 上，不在内存里 |
| 2 | **Prow 和其它 sigs 项目是配套的**：`testgrid`（看板）+ `prow`（CI）+ `boskos`（资源池）+ `kind`（测试集群）+ `e2e-framework`（测试框架）= 一整套。**Prow 只负责"发信号"，信号怎么展示、怎么消费是分开的** |
| 3 | **Prow 的下一个形态**：仓库里有 `prow/cmd/` 下多个组件（hook / tide / deck / peribolos），**hook 负责"写状态"，tide 负责"读状态做决策"** —— 这个读写分离是 prow-pulls.md §1.1 已点出的，sigs 层面的组织方式是：**hook 是插件，tide 是消费者，两者只通过 GitHub 上可见的 label/status 通信** |

> ★ **一个值得注意的规模信号**：`prow` 只有 333 star，`testgrid` 只有 8 star，
> 但两者组合支撑了整个 Kubernetes 社区的 CI。**star 数和生态影响力在这里完全不成正比。**

---

## 5. 值得警惕 / 不要盲目抄的地方

| # | sigs 的做法 | 为什么不能直接抄 | 我们该怎么做 |
|---|---|---|---|
| 1 | **API 用 `sigs.k8s.io/<repo>` 命名空间** | 这是 K8s 社区的特权（域名 + Go module 保留域）。我们没有资格申请 | 用自己的路径。**但要抄"每个组件有自己的稳定标识"这个意图** |
| 2 | **Apache-2.0 单一 license** | 我们的交付物是企业内部系统 | 按实际需要。但**"许可证文件不含自定义内容"这种规定性**可以抄成我们的准入 checklist |
| 3 | **有 provider 拆分（core / vendor）** | 我们只有一个平台（GKE + Argo CD），拆 provider 是过度设计 | **只在真的会有第二实现时才拆**。现在预留接口即可，不要先造框架 |
| 4 | **大量项目处于 alpha/beta** | `apiserver-runtime` 明确写 "may be cancelled with little or no public notice"；`mcp-lifecycle-operator` 是 v1beta1 | **引入前先查 release 状态**，别拿 alpha 当依赖 |
| 5 | **部分仓库维护停滞** | `resource-state-metrics` README 顶部："The project is slowing down development until more maintainers are recruited"；`cluster-autoscaler`："parts of this repo are still WIP" | ★ **看 `pushed_at` 和 README 顶部的免责声明**，别只看 star |
| 6 | **star 高的项目未必是 sigs 核心** | `karpenter` 在 sigs 里，但内容与 `aws/karpenter-core` 完全一致（同一 created_at / pushed_at / size）—— **是同源镜像** | 引用时用**真正的主仓库**。抄代码前先确认上游在哪 |
| 7 | **`kubernetes-mixin` 是从 `kubernetes-monitoring/kubernetes-mixin` 转过来的** | 说明 sigs 里的项目**会搬家** | 别把"在 sigs 里"当成"永久稳定" |
| 8 | **conformance 制度需要庞大社区才能运转** | 我们没有那个社区规模 | 只在**我们要开放给别人用**时才做 conformance 那一层；内部自用时用 golden test 就够 |
| 9 | **Kueue 的 fail-open（controller 不活跃 → Inactive）** | 我们的门禁选了 fail-closed | ★ **选 fail-closed，但把"我挂了"显式暴露**（见 §4.3） |
| 10 | **sigs 项目的共性是"云原生基础设施"** | 我们的核心场景是**发布治理**（CR 变更单），不是调度/存储 | 抄**设计范式**（provider 分离、conformance、状态外置），不抄**项目选型** |

---

## 6. 映射到我们的行动清单

> 按"性价比"排序。**P1 = 立刻能做，收益大；P2 = 需要设计；P3 = 锦上添花。**

### P1 —— 立刻做

| # | 行动 | 抄自 | 对应我们的哪个文件 |
|---|---|---|---|
| 1 | **CR Check 结论引入四态**：`Pass / Retry / Rejected / Unknown`，把"平台超时"和"CR 无效"分开 | §4.3 Kueue AdmissionCheck | `internal/rules/engine.go`、`internal/check/writer.go` |
| 2 | **失败信息标注"来源 + 置信度 + 快照时间"** | §4.6 kubectl-validate | `internal/rules/` 的输出构造 |
| 3 | **每个判定维度一个独立字段**（SSA fieldset 思路），让"CR 无效"和"不在窗口内"能同时存在 | §4.5 structured-merge-diff | `internal/rules/` 的 verdict 结构 |
| 4 | **规则引擎与规则来源分离**（引擎只认 `Context` 接口，平台实现各自独立） | §4.1 provider 分离 | `internal/rules/`、`internal/crplatform/` |
| 5 | **状态外置到 PR 上的显式清单**（META 注释 + inventory 式清单），不再依赖进程内存 | §4.4 cli-utils inventory | `internal/recheck/recheck.go`、`internal/check/writer.go` |
| 6 | **把 `kubectl-validate` 纳入 CI**，对我们要提交的 CRD / manifest 做服务端同源校验 | §4.6 kubectl-validate | CI workflow |

### P2 —— 需要设计

| # | 行动 | 抄自 | 说明 |
|---|---|---|---|
| 7 | **文档顶部标注事实对应版本**（Argo CD / kubectl / K8s / CR Check） | §4.7 版本化 | 全套文档统一 |
| 8 | **kustomize 版本对照表**进 Kustomize 相关文档 | §4.7 kustomize README | `kubectl version --client` 会打印 `Kustomize Version` |
| 9 | **CR 号识别规则的 conformance 用例集**（golden test） | §4.2 conformance | `internal/rules/extract_test.go` |
| 10 | **明确"我挂了"的可观测路径**（fail-closed 但要可见） | §4.3 Kueue 的反面 | `internal/observability/metrics.go` |
| 11 | **引入 CRD 破坏性变更检测**（`crdify`）到 CI | §3 域 2 | 我们自己产的 CRD |

### P3 —— 锦上添花

| # | 行动 | 抄自 |
|---|---|---|
| 12 | 标准化"最小合规文件集"（README / OWNERS / CONTRIBUTING / LICENSE / SECURITY_CONTACTS） | §1.4 template-project |
| 13 | 引入 `kube-api-linter` 检查我们对外的 API 类型 | §3 域 2 |
| 14 | 用 `kubernetes-mixin` 的 Jsonnet 思路管理我们的 Grafana dashboard / 告警 | §3 域 5 |
| 15 | 评估 `bom`（SBOM）进入我们的制品流程 | §3 域 6 |
| 16 | 评估 `external-dns` 替代手写 DNS 记录同步 | §3 域 3 |

### 与现有文档的联动

```
prow-pulls.md（§2.1–§2.14）   ← 13 个门禁设计（label / tide / tree hash / override）
          │
          │  本文补充：sigs 其它仓库提供的 7 个设计
          │  · §4.1 provider 分离（规则引擎 vs 规则来源）
          │  · §4.2 conformance 制度
          │  · §4.3 Kueue AdmissionCheck 四态   ← 补 Prow 的 pass/fail 二元
          │  · §4.4 cli-utils inventory          ← 补 label 之外的第三条路
          │  · §4.5 SSA 字段所有权
          │  · §4.6 kubectl-validate 同源校验 + 精度声明
          │  · §4.7 文档版本化
          ▼
how-to-atomic-idempotency.md   ← 幂等/原子性/去重/重扫
          │
          │  §4.4 补充：inventory = 状态外置的第三条路（内存 / label / inventory）
          │  §4.5 补充：字段所有权 = 判定维度互不覆盖
          ▼
ucp/argocd-topics/              ← 全套文档的版本标注统一（§4.7）
```

---

## 7. 附录 A：证据速查

| 证据 | 位置 | 证明了什么 |
|---|---|---|
| 210 个公开仓库 / 17.17 万 star / 4762 followers / 创建于 2018-01-31 | `https://github.com/kubernetes-sigs` | org 规模 |
| 仓库清单 + topics + license + star + pushed_at | `gh api orgs/kubernetes-sigs/repos?per_page=100 --paginate` | §2 全表 |
| 语言分布：Go 169 / Shell 8 / Python 6 / TypeScript 3 / C 2 | 同上（`.language` 字段） | "Go 为主" |
| 2 个 archived：`dashboard-metrics-scraper`、`wg-serving` | 同上（`.archived`） | 部分项目已停 |
| 32/51 填了 homepage 的仓库用 `*.sigs.k8s.io` | 同上（`.homepage`） | 文档站命名约定 |
| License 全量分布：207 Apache-2.0 / 1 CC-BY-4.0(`lwkd`) / 2 未识别(`yaml`,`json`) | 同上（`.license.spdx_id`） | 单一 license（3 个例外） |
| SIG 注册表（dir / name / mission_statement / chairs / meetings） | `kubernetes/community` → `sigs.yaml` | §1.1 组织结构 |
| `sig-api-machinery` 15 个 subproject（跨 3 个组织，含 16 个 sigs 仓库）、`sig-apps` 9 个（含 10 个 sigs 仓库） | 同上 `sigs.yaml` 的 `subprojects:` | §1.2 归属权威源 |
| 各 SIG 的 charter 与 mission | `kubernetes/community` → `sig-<name>/charter.md` | §1.1 |
| AdmissionCheck 四态 + evict 行为 + Inactive 规则 | `kueue.sigs.k8s.io/docs/concepts/admission_check/` | §4.3 |
| 三档 inventory policy（MustMatch / AdoptIfNoInventory / AdoptAll） | `cli-utils/pkg/inventory/policy.go` 源码注释 | §4.4 |
| "kubectl apply --prune 用 label 有重大缺点，是 alpha，不会毕业" | `cli-utils` README "Pruning" 段 | §4.4 |
| fieldset / PUT-PATCH vs APPLY 语义 | `structured-merge-diff` README | §4.5 |
| "written by apiserver authors using the same code as the server-side" + Drawbacks 段 | `kubectl-validate` README | §4.6 |
| kubectl 内嵌 kustomize 版本对照表 | `kustomize` README | §4.7 |
| "follow the documentation in that version's release branch" | `descheduler` README | §4.7 |
| "Read the docs for your version, not this branch" | `node-feature-discovery` README | §4.7 |
| "not a DNS server itself, but merely configures other DNS providers" | `external-dns` README | §4.1 |
| "Cluster API ... declarative APIs and tooling to simplify provisioning, upgrading, and operating" | `cluster-api` README | §4.1 |
| conformance 报告制度 | `gateway-api/conformance/reports/README.md` + README "Gateway API conformance" 段 | §4.2 |
| 每个项目必需的文件清单 | `kubernetes-sigs/multi-network` README（引 template-project） | §1.4 |
| `apiserver-runtime` 是 Alpha、可能被取消 | `apiserver-runtime` README | §5 #4 |
| `resource-state-metrics` 维护放缓 | `resource-state-metrics` README 首行 | §5 #5 |
| `cluster-autoscaler` 仍在拆分中 | `cluster-autoscaler` README "WARNING" | §5 #5 |
| `kubernetes-sigs/karpenter` 与 `aws/karpenter-core` 元数据完全相同 | `gh api repos/<both>` 的 `created_at`/`pushed_at`/`size` | §5 #6 |
| `kubernetes-mixin` 从 `kubernetes-monitoring/kubernetes-mixin` 转入 | `kubernetes-mixin` README 首段 | §5 #7 |
| `mcp-lifecycle-operator` 是 v1beta1 | 其 README 的 Note | §5 #4 |
| `kro` 用 `github.com/kubernetes-sigs/kro` 而非 `sigs.k8s.io/kro` | `gh api repos/kubernetes-sigs/kro/contents/go.mod` | §1.3 例外 |

---

## 8. 附录 B：复现命令

```bash
# ① 全量仓库清单（210 行 TSV：name/stars/forks/lang/license/archived/pushed_at/homepage/topics）
gh api 'orgs/kubernetes-sigs/repos?per_page=100' --paginate \
  --jq '.[] | [.name, .stargazers_count, .forks_count, (.language // "-"),
                 (.license.spdx_id // "-"), .archived, .pushed_at,
                 (.homepage // "-"), ((.topics // []) | join(","))] | @tsv'

# ② 按 star 排序看 Top 30
gh api 'orgs/kubernetes-sigs/repos?per_page=100' --paginate \
  --jq '.[] | [.stargazers_count, .name, (.description // "")] | @tsv' \
  | sort -rn | head -30

# ③ 语言分布
gh api 'orgs/kubernetes-sigs/repos?per_page=100' --paginate \
  --jq '.[].language // "none"' | sort | uniq -c | sort -rn

# ④ 哪些仓库带 k8s-sig-* topic（= SIG 粗筛）
gh api 'orgs/kubernetes-sigs/repos?per_page=100' --paginate \
  --jq '.[] | select([.topics[]? | select(startswith("k8s-sig-"))] | length > 0)
         | .name + " -> " + ([.topics[] | select(startswith("k8s-sig-"))] | join(","))'

# ⑤ 权威 SIG→repo 映射（community 仓库的 sigs.yaml）
gh api repos/kubernetes/community/contents/sigs.yaml --jq .content | base64 -d \
  | grep -A400 'subprojects:' | grep -E 'name:|raw.githubusercontent'

# ⑥ 各 SIG 的 charter（拿 scope 的权威来源）
for s in sig-cluster-lifecycle sig-network sig-api-machinery sig-testing sig-cli \
         sig-scheduling sig-cloud-provider sig-node sig-multicluster; do
  echo "--- $s ---"
  gh api "repos/kubernetes/community/contents/$s/charter.md" --jq .content 2>/dev/null | base64 -d | head -40
done

# ⑦ 单个项目的 README 原文
gh api repos/kubernetes-sigs/<repo>/readme --jq .content | base64 -d

# ⑧ 模块路径约定
for r in controller-runtime kubebuilder kueue kro crdify cli-utils; do
  echo "--- $r ---"
  gh api "repos/kubernetes-sigs/$r/contents/go.mod" --jq .content | base64 -d | head -1
done

# ⑨ ★ Kueue AdmissionCheck 状态机（§4.3 的权威来源）
#   https://kueue.sigs.k8s.io/docs/concepts/admission_check/

# ⑩ ★ cli-utils 的三档 inventory policy 源码注释（§4.4）
gh api repos/kubernetes-sigs/cli-utils/contents/pkg/inventory/policy.go --jq .content | base64 -d \
  | sed -n '1,80p'

# ⑪ 停更/停滞信号：最近推送时间 + README 首行
gh api repos/kubernetes-sigs/resource-state-metrics/readme --jq .content | base64 -d | head -3

# ⑫ karpenter 主仓库确认（§5 #6）
gh api repos/kubernetes-sigs/karpenter --jq '{created_at,pushed_at,size,fork}'
gh api repos/aws/karpenter-core    --jq '{created_at,pushed_at,size,fork}'
```

---

## 9. 相关文档

| 文档 | 关系 |
|---|---|
| [`prow-pulls.md`](./prow-pulls.md) | ★ **本文的主线文档**——Prow 的 PR 管理机制拆解（13 个设计）。本文 §4.8 是它的索引，§4.1–§4.7 是它的补充 |
| [`how-to-atomic-idempotency.md`](./how-to-atomic-idempotency.md) | 幂等/原子性/去重/重扫 —— 本文 §4.4（inventory）、§4.5（字段所有权）补充了它的"状态外置"与"维度互不覆盖" |
| [`how-to-using-git-apps.md`](./how-to-using-git-apps.md) | 装好 App 之后仓库侧要做什么 —— 本文 §4.2（conformance）的下一层 |
| [`install-git-apps.md`](./install-git-apps.md) | Org 级 vs 仓库级 vs 分支 |
| [`git-apps/14-rulesets-and-gitapp-gate.md`](./git-apps/14-rulesets-and-gitapp-gate.md) | 门禁侧：check 怎么变成"必须通过" |
| [`git-apps/16-ruleset-install-runbook.md`](./git-apps/16-ruleset-install-runbook.md) | JSON 怎么装到 GitHub 上 —— 本文 §4.2 提到的"下一层 conformance"的现状 |
| [`git-apps/cr-check/`](./git-apps/cr-check/) | Go 实现 —— §6 行动清单的对象 |
| [`10-argo-workflows-evaluation.md`](./10-argo-workflows-evaluation.md) | 版本标注的先例（§4.7 提到的写法） |
| [`README.md`](./README.md) | 本目录文档索引 |
