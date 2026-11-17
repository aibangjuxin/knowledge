# OpenShift 入门 — Red Hat 的企业级 Kubernetes 平台

> **TL;DR**:
> - **OpenShift 是 Red Hat 的企业级 Kubernetes 发行版**(distribution),不是 K8s 替代品。它把 K8s(内核)+ 平台工具(发行层)+ 企业支持(商业层)三件套打包,类似 Red Hat 把 Linux 内核 + RHEL 发行层打包的关系
> - **对你(GKE / K8s 重度用户)的核心价值**:**自带一整套 GKE / GKE Enterprise 要花钱才能用上的能力** — Service Mesh / GitOps / CI/CD / 镜像仓库 / Operator Lifecycle / 多集群管理 / 容器安全,**全部由 Red Hat 集成 + 测试 + 商业支持**
> - **怎么接入你的生产环境**:从最便宜的"沙盒"(Developer Sandbox / OpenShift Kubernetes Engine)入手,逐步升级到 Container Platform / Dedicated / Platform Plus,**不需要"all in"重写迁移**

---

## 0. 文档定位

> **本场景假设**(Lex 自己):
> - 你已经在用 **GKE / 自建 K8s** 跑生产业务(已熟悉 Deployment / Service / Namespace)
> - 你想了解 **OpenShift 是什么 / 能干什么 / 能不能用在你的生产环境**
> - 你不想"全面替换 K8s",而是想知道"OpenShift 哪些能力是我现在 GKE 上缺的 / 可以补强的"

> **本文不是**:
> - ❌ OpenShift 安装手册(那是 `openshift-install` 几十页的内容)
> - ❌ OpenShift vs GKE 性能 benchmark(本文只对比定位)
> - ❌ OpenShift AI 教程(那是另一个文档)

> **来源引用**(全部官方原文,带 URL + 抓取日期):
> - [Red Hat — OpenShift and Kubernetes: What's the difference?](https://www.redhat.com/en/blog/openshift-and-kubernetes-whats-difference) — Kubernetes 内核 vs 发行层的关系 — **抓取日期:2026-09-20**
> - [Red Hat — OpenShift 产品总览](https://www.redhat.com/en/technologies/cloud-computing/openshift) — 产品 SKU 全景 — **抓取日期:2026-09-20**
> - [Red Hat — OpenShift Service Mesh](https://www.redhat.com/en/technologies/cloud-computing/openshift/what-is-openshift-service-mesh) — 基于 Istio + Envoy + Kiali — **抓取日期:2026-09-20**
> - [Red Hat — OpenShift Dedicated](https://www.redhat.com/en/technologies/cloud-computing/openshift/dedicated) — Google Cloud 上的托管 OpenShift — **抓取日期:2026-09-20**
> - [Red Hat — OpenShift AI](https://www.redhat.com/en/products/ai/openshift-ai) — AI/ML 平台(Pytorch + Kubeflow + MLflow + vLLM)— **抓取日期:2026-09-20**
> - [Red Hat — OpenShift Container Platform Architecture 4.21](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html-single/architecture/architecture) — 权威架构文档(章节级引用)

---

## 1. OpenShift 是什么?(一句话回答 + 4 层模型)

### 1.1 一句话回答

> **OpenShift = Red Hat 打包的"企业级 Kubernetes 发行版" + 一整套围绕 K8s 的集成平台工具(Operator、Service Mesh、镜像仓库、CI/CD、Serverless、监控、日志、安全) + Red Hat 商业支持。**

Red Hat 官方的精确说法:

> "The team behind OpenShift has been proud to produce a distribution of Kubernetes focused on the experience of developers who have the need to develop the next generation of cloud native applications. [...] Much like CoreOS and CentOS contain different sets of tooling, catering to different users, so it is the same with Kubernetes distributions."
> — [Red Hat — OpenShift and Kubernetes: What's the difference?](https://www.redhat.com/en/blog/openshift-and-kubernetes-whats-difference) (Brian 'Redbeard' Harrington, 2019)

### 1.2 4 层心智模型 — 像 Linux 内核与发行版

```
┌────────────────────────────────────────────────────────────┐
│ Layer 4: Red Hat OpenShift Container Platform              │  ← 商业产品(RHEL 等价物)
│         "整合、测试、企业支持"                              │
├────────────────────────────────────────────────────────────┤
│ Layer 3: OpenShift 平台工具集                                              │  ← 围绕 K8s 的全套工具
│         Operators / Service Mesh / Quay / Pipelines /     │
│         GitOps / Monitoring / Logging / Security          │
├────────────────────────────────────────────────────────────┤
│ Layer 2: OKD(原 Origin) — 社区开源项目                                  │  ← K8s 发行版
│         "K8s + 平台工具的打包组合"                          │
├────────────────────────────────────────────────────────────┤
│ Layer 1: Kubernetes(上游 CNCF 项目)                                   │  ← 内核
│         "容器编排的'内核'"                                  │
└────────────────────────────────────────────────────────────┘
```

**和 Linux 的类比**(Red Hat 自己的原话):

> "**Kubernetes is the 'kernel'** [...] It is the same Kubernetes in the various Kubernetes distributions, albeit with varying degrees of patches to support the layer Kubernetes sits directly atop. **The Linux distributions that each flavor of Kubernetes is running its workloads on.**"
> — [Red Hat — OpenShift and Kubernetes: What's the difference?](https://www.redhat.com/en/blog/openshift-and-kubernetes-whats-difference)

| Linux 概念 | K8s 对应物 | OpenShift 对应物 |
|---|---|---|
| Linux Kernel | Kubernetes | — |
| Fedora / CentOS / RHEL | OKD(社区) / OpenShift | **Red Hat OpenShift Container Platform** |
| 包管理(rpm/dnf)| Helm | **Helm + Operator Lifecycle Manager(OLM)** |
| Systemd | kubelet | **CRI-O + systemd 集成的 kubelet** |
| `dnf install` | `kubectl apply` | **`oc apply`(兼容 K8s,加 oc-only 特性)** |

### 1.3 OpenShift 不是"K8s 替代品"

**反直觉点**:OpenShift **100% 运行 Kubernetes**(上游 K8s 代码 + 自己打的 patch)。你之前学过的 `kubectl` / `Deployment` / `Service` / `Ingress` / `NetworkPolicy` 在 OpenShift 上**完全通用**。

OpenShift 多出来的是:
- **Operator 生命周期**(OLM):打包、版本管理、自动升级 K8s 内部组件
- **OC 命令**:Red Hat 自己的 CLI(`oc` = `kubectl` 超集,**100% 兼容 kubectl 命令**)
- **集成测试 + 商业支持**:Red Hat 帮你测了组件兼容性,出问题打电话就有支持

---

## 2. OpenShift 能干什么?(产品 SKU 全景)

> 来源:[Red Hat — OpenShift 产品总览](https://www.redhat.com/en/technologies/cloud-computing/openshift) (2026-09-20 抓取)

OpenShift 产品分两类:**Cloud services(托管)** 和 **Self-managed(自管)**,加 **Services & add-ons**。

### 2.1 Cloud Services(完全托管)

| SKU | 谁运维 | 在哪跑 | 适合 |
|---|---|---|---|
| **Red Hat OpenShift Service on AWS (ROSA)** | Red Hat + AWS 联合 | AWS | AWS 上的生产工作负载 |
| **Microsoft Azure Red Hat OpenShift (ARO)** | Red Hat + MS 联合 | Azure | Azure 上的生产工作负载 |
| **Red Hat OpenShift Dedicated** ⭐ | Red Hat 单独 | **Google Cloud / AWS** | GCP 上的生产工作负载(对你最相关!)|
| **Red Hat OpenShift on IBM Cloud** | Red Hat + IBM 联合 | IBM Cloud | IBM Cloud 上的工作负载 |

**对你(已经在 GKE 上跑业务)的相关性**:**OpenShift Dedicated** 直接跑在 GCP,**你可以在同一 GCP 项目里同时跑 GKE + OpenShift Dedicated**,两边用 IAM / VPC 互通。详见 §3.2。

### 2.2 Self-managed Editions(自管)

| SKU | 是什么 | 适合 |
|---|---|---|
| **Red Hat OpenShift Container Platform (OCP)** ⭐ | 完整功能企业级 K8s 发行版 | 数据中心 / 私有云 / 任意云上的核心生产 |
| **Red Hat OpenShift Platform Plus** | OCP + **Advanced Cluster Management** + **Advanced Cluster Security** + **Quay** | 多集群管理 + 安全合规要求高的企业 |
| **Red Hat OpenShift Kubernetes Engine** | "只 K8s 引擎" 的精简版 | 想要 K8s + Red Hat 支持,但不需要完整平台工具 |
| **Red Hat OpenShift Virtualization Engine** | 只做 VM 虚拟化(KubeVirt 集成)| VM 迁移 / 混合 VM+容器 |

### 2.3 Services & Add-ons(围绕平台的可选附加)

> 来源:[Red Hat — OpenShift 总览](https://www.redhat.com/en/technologies/cloud-computing/openshift) (2026-09-20 抓取)

| 服务 | 类比(GCP 上你已经在用的) | 干嘛的 |
|---|---|---|
| **Red Hat OpenShift AI** ⭐ | Vertex AI / SageMaker | MLOps / GenAIOps / AgentOps 平台,集成 PyTorch / Kubeflow / MLflow / vLLM |
| **Red Hat OpenShift Lightspeed** | Gemini Code Assist / Copilot for GKE | K8s + OpenShift 的 AI 助手(自然语言运维)|
| **Red Hat OpenShift Virtualization** | GKE 暂未直接对应 | 把 VM 跑在 K8s 上(KubeVirt)|
| **Red Hat Quay** | Artifact Registry | 容器镜像私有仓库(企业级)|
| **Red Hat Advanced Cluster Management for Kubernetes (ACM)** | GKE Enterprise / Fleet | **多集群管理**(跨云 / 跨 region / 跨 K8s 集群)|
| **Red Hat Advanced Cluster Security for Kubernetes (ACS)** | Google Cloud Armor + Container Security | **容器安全**(镜像扫描 / 漏洞检测 / 运行时防护)|
| **Red Hat Advanced Developer Suite** | — | 开发者工具集(IDE 插件 / 调试 / 测试)|
| **Red Hat OpenShift Service Mesh** ⭐ | Istio on GKE / ASM | Service Mesh(Istio + Envoy + Kiali) |
| **Red Hat OpenShift Serverless** | Cloud Run / Knative on GKE | Knative Serving(基于请求的自动扩缩容)|
| **Red Hat OpenShift GitOps** | Config Sync / ArgoCD | GitOps(ArgoCD 集成) |
| **Red Hat OpenShift Observability** | Cloud Operations / Prometheus + Grafana | 监控 + 日志 + 链路追踪 |

---

## 3. 对你的场景能帮到什么?(GKE 用户视角)

> **起点假设**:你已经在用 GKE(或自建 K8s)跑业务,熟悉 Deployment / Service / Ingress / NetworkPolicy / HPA 等基础。

### 3.1 OpenShift 能补强 / 替代的 GKE 能力矩阵

| 能力 | 你现在 GKE 怎么实现 | OpenShift 提供什么 | 价值 |
|---|---|---|---|
| **多集群管理** | GKE Enterprise + Fleet / Anthos Config Management | **OpenShift Advanced Cluster Management (ACM)** | 统一管理 GKE / EKS / AKS / 自建 K8s |
| **Service Mesh** | ASM(付费) / 自己装 Istio | **OpenShift Service Mesh**(内置 Istio + Kiali) | 节省 Istio 运维成本 |
| **GitOps** | Config Sync / ArgoCD 自己装 | **OpenShift GitOps**(内置 ArgoCD) | 集成 + 测试 + 支持 |
| **容器安全** | Artifact Registry 漏洞扫描 + Binary Authorization | **OpenShift ACS + Quay 集成** | 企业级安全合规(SOC2 / PCI) |
| **AI / ML 平台** | Vertex AI / 自建 Kubeflow | **OpenShift AI**(内置 Kubeflow + MLflow + vLLM) | 开源,可在 GKE 旁边跑 |
| **Serverless** | Cloud Run / Knative on GKE | **OpenShift Serverless**(内置 Knative) | on-prem / 私有云场景 |
| **Operator 生态** | 自己装 Operator Lifecycle Manager | **OLM 内置 + OpenShift OperatorHub** | 250+ Red Hat 验证的 Operator |
| **CI/CD** | Cloud Build / Tekton 自己装 | **OpenShift Pipelines**(内置 Tekton) | 与 OpenShift 集成 |
| **镜像仓库** | Artifact Registry | **Red Hat Quay**(私有仓库) | 漏洞扫描 + 签名 + 异地复制 |

### 3.2 接入方式一(推荐):**OpenShift Dedicated on GCP**

> 来源:[Red Hat — OpenShift Dedicated](https://www.redhat.com/en/technologies/cloud-computing/openshift/dedicated) (2026-09-20 抓取)

```
┌──────────────────────────────────────────┐
│ GCP Project (e.g. lex-uk-prd-001)        │
│                                           │
│  ┌─────────────┐      ┌────────────────┐  │
│  │ GKE Cluster │      │ OpenShift      │  │
│  │ (existing)  │      │ Dedicated      │  │
│  │             │      │ Cluster        │  │
│  │ - workload  │      │                │  │
│  │ - data svc  │ ◄────┤ - Service Mesh │  │
│  │             │ VPC  │ - GitOps       │  │
│  │             │ Peer │ - ACS / Quay   │  │
│  └─────────────┘      │ - OpenShift AI │  │
│                       └────────────────┘  │
│                                           │
│  共享: VPC / Subnet / IAM / Cloud NAT     │
└──────────────────────────────────────────┘
```

**优势**:
- **同一个 GCP 项目**同时跑 GKE + OpenShift Dedicated(都用同一个 VPC / IAM)
- **共享网络**:VPC Peering 或 Subnet 共享,两边 pod IP 可达
- **共享 IAM**:Workload Identity / GCP Service Account 跨 GKE / OpenShift 互通
- **消费 GCP 已有服务**:Cloud SQL / GCS / BigQuery / Pub-Sub 直接接 OpenShift 上的 pod

**Red Hat 官方原话**:
> "OpenShift Dedicated lets you take advantage of native Google Cloud services, supports a flexible billing model, and can be purchased with your existing cloud committed spend discounts."
> — [Red Hat — OpenShift Dedicated](https://www.redhat.com/en/technologies/cloud-computing/openshift/dedicated)

**对你(已经在 GCP 上花了很多钱)的意义 — 可以用现有 GCP committed spend discount 抵扣 OpenShift Dedicated 订阅费用!**

### 3.3 接入方式二(进阶):**OpenShift Container Platform 私有部署**

```
┌──────────────────────────────────────────┐
│ 你的数据中心 / 私有云 / 任意云 IaaS       │
│                                           │
│  ┌──────────────────────────────┐        │
│  │ OpenShift Container Platform │        │
│  │ (自己装,自己管)              │        │
│  │                              │        │
│  │ - bare metal / VMware / KVM  │        │
│  │ - RHEL / RHCOS 操作系统       │        │
│  │ - 完全离线的 on-prem         │        │
│  └──────────────────────────────┘        │
└──────────────────────────────────────────┘
```

**适合**:
- 数据合规要求**所有数据不能离开自己的机房**(金融 / 政府 / 医疗)
- 已经有数据中心 + 运维团队(装 + 升级 + 监控都需要懂 K8s 的工程师)
- 想用 OpenShift 工具但不想依赖云厂商

**对你**(目前主要用 GCP)— **意义不大**,除非你有 on-prem 业务。

### 3.4 接入方式三(尝鲜):**Developer Sandbox / OKE**

| 入口 | 是什么 | 适合 |
|---|---|---|
| **Red Hat Developer Sandbox** ⭐ | 免费(Red Hat Developer 账号) | **个人尝鲜 / 学 OpenShift** — 立即可用,~30 天有效 |
| **OpenShift Kubernetes Engine(OKE)** | "只 K8s 引擎" 的精简版(免费支持) | 想要 K8s + Red Hat 支持,**但不想花全套 Container Platform 的钱** |
| **OpenShift Container Platform trial** | 60 天完整版试用 | **POC / 评估** — 完整功能 |
| **OpenShift Dedicated trial** | GCP 上的托管试用 | **直接在 GCP 上试** |

**推荐路径**:**Developer Sandbox → OpenShift Dedicated trial → 评估是否值得付费生产**

---

## 4. OpenShift 的"独门绝活"(GKE 上要么没 / 要么要自己装)

### 4.1 Operator 生态 + OperatorHub

> OpenShift 自带 **OperatorHub**(类似 K8s 的 app store),有 **250+ Red Hat 验证的 Operator**(MongoDB / Kafka / Redis / PostgreSQL / Spark / GitLab / Jenkins / ArgoCD 等)。

**对比 GKE**:GKE 上有 Google Cloud Marketplace,但 Operator 数量和验证深度不如 OpenShift OperatorHub。

**Operator Lifecycle Manager (OLM)** 是 OpenShift 的 Operator 管理器,类似:
- 自动升级 Operator
- 跨集群同步 Operator
- Operator 依赖管理

### 4.2 OpenShift Service Mesh(Istio 集成)

> 来源:[Red Hat — OpenShift Service Mesh](https://www.redhat.com/en/technologies/cloud-computing/openshift/what-is-openshift-service-mesh) (2026-09-20 抓取)

> "Red Hat® OpenShift® Service Mesh offers a uniform way to connect, manage, observe, and provide security for microservices-based applications. [...] **OpenShift Service Mesh is based on the open source Istio, Envoy, and Kiali projects.** It supports the Istioctl command line utility for diagnostics and management of the control plane and data plane, along with the Kiali and OpenShift Service Mesh Console dashboards."

**关键差异 vs 你已经在用的 GKE + ASM / Istio**:
- ✅ OpenShift Service Mesh **和 OpenShift 的身份认证深度集成**(OpenShift OAuth)
- ✅ Kiali + 自带控制台,**一键启停 Service Mesh**
- ✅ 集成 cert-manager、Connectivity Link、OpenShift Observability
- ✅ mTLS 默认开启 + 零信任安全模型

**对你的价值**:如果你已经在 GKE 上用 Istio,迁移到 OpenShift Service Mesh 可以**减少自维护的 yaml + Operator 升级负担**。

### 4.3 OpenShift GitOps(内置 ArgoCD)

> **OpenShift GitOps = ArgoCD 在 OpenShift 上的"集成版"** — 由 Red Hat 验证、升级、安全扫描。

**对比 GKE**:GKE 上要装 ArgoCD 自己配,Config Sync 是另一个选择。OpenShift 直接给你"集成 + 测试 + 支持"的版本。

### 4.4 OpenShift AI(MLOps / GenAIOps / AgentOps)

> 来源:[Red Hat — OpenShift AI](https://www.redhat.com/en/products/ai/openshift-ai) (2026-09-20 抓取)

> "Red Hat® OpenShift® AI combines comprehensive MLOps, GenAIOps, and AgentOps capabilities to accelerate the deployment of agentic AI applications into production. **With open source tools like PyTorch, Kubeflow, MLflow, and vLLM**, teams can experiment, serve, and deliver AI models and applications at scale."

**能力清单**:
- **Agentic AI**(用 MLflow 做端到端追踪)
- **vLLM**(高效 LLM 推理,降本 + 稳定延迟)
- **MCP servers**(Model Context Protocol,统一管外部 tool 访问)
- **Private AI**(on-premise / 离线模式,数据不出机房)
- **Models-as-a-Service**(内部提供模型 API,不依赖外部供应商)
- **llm-d**(开源 LLM 优化框架)
- **AI hub**(第三方模型性能验证)
- **Gen AI studio**(原型设计)

**对你(假设你用 mmx CLI / 调 OpenAI API)的价值**:
- 如果你的 **AI 推理服务要部署在 on-prem**(数据合规)— OpenShift AI 是少数能"on-prem 跑完整 vLLM + MLflow"的方案
- 如果你想**避免 lock-in**(OpenAI / Anthropic API)— OpenShift AI 提供"私有模型 API 网关"

### 4.5 Advanced Cluster Management (ACM)

> **多集群 + 多云管理**,跨 GKE / EKS / AKS / 自建 K8s / OpenShift 集群统一管。

**对你的价值**:如果你的 GKE 集群有 3 个 region,又有自建 K8s 做边缘,ACM 可以**统一管 K8s 资源 / 策略 / 应用分发**。

### 4.6 Advanced Cluster Security (ACS)

> **容器安全平台**,做镜像漏洞扫描 / 准入控制 / 运行时检测 / 合规报告。

**对比 GKE**:
- GKE 有 Container Security / Binary Authorization,但**没有 OpenShift ACS 那么细粒度**(e.g. 按 process 黑白名单 / 按 syscall 阻断)
- ACS 还包含 **compliance operator**(PCI-DSS / SOC2 / HIPAA 自动出报告)

---

## 5. 反向:什么时候**不要**用 OpenShift

| 场景 | 推荐 | 原因 |
|---|---|---|
| **已经在 GKE 上稳定运行 / 不想动** | 保持 GKE | OpenShift 迁移成本不低,除非有明显收益 |
| **只要 K8s + 不想花钱** | GKE Standard / 自建 K8s | OpenShift 是付费产品 |
| **只需要 Service Mesh / GitOps** | GKE + 自己装 Istio / ArgoCD | OpenShift Platform Plus 价值需要全套平台才能体现 |
| **新创业公司 / 小团队** | GKE Autopilot / EKS Auto Mode | OpenShift 复杂度大,小团队吃不消 |
| **已有 Red Hat 订阅 + 想整合** | OpenShift | **这时候 OpenShift 是最优解** — 现有投资延伸 |
| **多云管理 + 安全合规** | OpenShift Platform Plus | **ACM + ACS 是 GKE Enterprise 替代** |

---

## 6. 接入你生产环境的 3 步路径

### Step 1(本周):尝鲜 — Developer Sandbox

```bash
# 1. 注册 Red Hat Developer 账号
open https://developers.redhat.com/registration

# 2. 启动 Developer Sandbox(免费,~30 天)
# 浏览器界面里点 "Launch Sandbox" → 自动给你一个 OpenShift 集群 + Web console

# 3. 下载 oc CLI
brew install openshift-cli   # macOS
# 或直接到 https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/

# 4. 登录集群(浏览器里复制 login command)
oc login --token=sha256~... --server=https://...

# 5. 创建第一个项目
oc new-project my-test-app

# 6. 部署示例应用(用 OpenShift 自带的 Source-to-Image / S2I)
oc new-app nodejs~https://github.com/sclorg/nodejs-ex.git
oc expose svc/nodejs-ex

# 7. 在浏览器 console 看结果
# (会拿到一个 *.apps.sandboxNNNN.openshiftapps.com 的 URL)
```

**这一步目的**:**熟悉 oc CLI / OpenShift console / OperatorHub**,不写一行 K8s 代码也能跑通应用。

### Step 2(2 周内):评估 — OpenShift Dedicated on GCP trial

```bash
# 1. 申请 OpenShift Dedicated 试用(60 天)
#    https://www.redhat.com/en/technologies/cloud-computing/openshift/dedicated/trial

# 2. 在你的 GCP 项目里创建 OpenShift Dedicated 集群
#    (Red Hat console 操作,选 GCP 作为云)
#    选 region、机器规格、节点数

# 3. 拿到 kubeconfig 后,从你的本地 kubectl / oc 直接接
oc login --token=sha256~... --server=https://api.xxxxx.openshiftapps.com

# 4. 在 OpenShift Dedicated 上部署一个应用
oc new-app --name=test-app \
  --image=your-registry/your-image:tag

# 5. 测试和现有 GKE 集群的网络互通
#    OpenShift Dedicated 默认和你 GCP 项目同 VPC(子网共享)
#    从 GKE pod curl OpenShift pod IP,验证可达

# 6. 评估 OpenShift Service Mesh / GitOps / OperatorHub 是否值得长期用
```

**这一步目的**:**在真实 GCP 环境下验证 OpenShift 与 GKE 共存**,跑几个 OpenShift 独有的特性(Operator / Service Mesh)。

### Step 3(决定后):生产部署

| 决策 | 选这个 |
|---|---|
| **纯 GCP + 想要 OpenShift 平台工具** | **OpenShift Dedicated**(订阅费,但和 GCP 集成最自然)|
| **多云 + 多集群管理** | **OpenShift Platform Plus + ACM** |
| **私有化 / 数据不出本地** | **OpenShift Container Platform 自管**(自己买 RHEL 主机)|
| **只要 K8s 引擎 + Red Hat 支持** | **OpenShift Kubernetes Engine** |

---

## 7. 跟同仓库其他文档的关系

| 文档 | 关系 |
|---|---|
| `cloud/k8s/docs/cronjob.md` / `deployment2.md` 等 | OpenShift 100% 兼容这些 K8s 概念 — 你学的 K8s 基础全部适用 |
| `cloud/k8s/k8s-gateway/` | K8s Gateway API 也是 OpenShift 支持的标准(OpenShift 4.12+ 内置 Istio 支持 Gateway API)|
| `gcp/asm/` | OpenShift Service Mesh 跟你已经在用的 GKE ASM **底层都是 Istio**,迁移 YAML 大多兼容 |
| `gcp/gcp-cloud-build/` | OpenShift Pipelines 跟你已经在用的 Cloud Build 都是 Tekton 家族 |
| `safe/docs/` | OpenShift 跟你的"安全合规"目标天然契合(ACS + SOC2 合规) |

---

## 8. 严格定义 vs 简化解释(关键限定)

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **OpenShift** | "Red Hat 的 K8s" | "Red Hat's enterprise-grade Kubernetes distribution that bundles Kubernetes with a curated set of platform tooling (Operators, Service Mesh, GitOps, Pipelines, Quay, monitoring) plus commercial support, tested and integrated by Red Hat." |
| **OpenShift vs Kubernetes** | "差不多的东西" | "Kubernetes is the upstream CNCF project (kernel-equivalent); OpenShift is one distribution built on it (Fedora/RHEL-equivalent); both run the same workload manifests." — Red Hat official |
| **OCP(Container Platform)** | "OpenShift 主产品" | "Red Hat OpenShift Container Platform — the on-prem / self-managed edition of OpenShift, requires subscription." |
| **ARO / ROSA** | "Azure / AWS 上托管的 OpenShift" | "Azure Red Hat OpenShift / Red Hat OpenShift Service on AWS — jointly managed and supported offerings in Azure and AWS." |
| **OpenShift Dedicated** | "GCP 上的 OpenShift" | "Red Hat OpenShift Dedicated — fully managed OpenShift running on AWS or Google Cloud, fully managed by Red Hat." |
| **OC CLI** | "跟 kubectl 类似" | "`oc` is Red Hat's CLI; it's 100% compatible with `kubectl` and adds OpenShift-specific commands (oc new-app, oc new-project, oc rsh). All kubectl commands work in oc." |
| **OperatorHub** | "K8s app store" | "OperatorHub.io is a registry of Kubernetes Operators curated by Red Hat and the community; on OpenShift, it is pre-installed and integrated with OLM." |
| **OLM(Operator Lifecycle Manager)** | "管 Operator 的" | "OLM is a Kubernetes controller that manages Operator lifecycle (install, upgrade, dependency graph, RBAC) for both cluster-wide and namespace-scoped Operators." — Kubernetes documentation |

---

## 9. References(权威证据 + 来源日期)

### 9.1 Red Hat 官方(主源)

- [Red Hat — OpenShift and Kubernetes: What's the difference?](https://www.redhat.com/en/blog/openshift-and-kubernetes-whats-difference) — 概念入门,K8s 内核 vs 发行层 — **来源日期:2019-02-05 官方博客(2026-09-20 抓取)**
- [Red Hat — OpenShift 产品总览](https://www.redhat.com/en/technologies/cloud-computing/openshift) — 产品 SKU 全景 — **来源日期:2026-09-20 抓取**
- [Red Hat — OpenShift Service Mesh](https://www.redhat.com/en/technologies/cloud-computing/openshift/what-is-openshift-service-mesh) — 基于 Istio / Envoy / Kiali — **来源日期:2026-09-20 抓取**
- [Red Hat — OpenShift Dedicated](https://www.redhat.com/en/technologies/cloud-computing/openshift/dedicated) — Google Cloud 上的托管 OpenShift — **来源日期:2026-09-20 抓取**
- [Red Hat — OpenShift AI](https://www.redhat.com/en/products/ai/openshift-ai) — MLOps / GenAIOps 平台 — **来源日期:2026-09-20 抓取**

### 9.2 Red Hat 官方文档(权威)

- [Red Hat — OpenShift Container Platform Architecture 4.21](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html-single/architecture/architecture) — 权威架构文档
- [Red Hat — OpenShift Container Platform 4.20 Architecture](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/architecture/architecture) — 上一版本架构(对比用)
- [Red Hat — OpenShift AI Cloud Service 1 Installing](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_cloud_service/1/html/installing_and_uninstalling_openshift_ai_cloud_service/installing-and-deploying-openshift-ai_install) — OpenShift AI 安装手册
- [OKD Project on GitHub](https://github.com/openshift/okd) — OpenShift 社区版开源项目

### 9.3 知识背景(可选)

- [CNCF — Kubernetes 官方](https://kubernetes.io/) — OpenShift 的内核
- [Istio Project](https://istio.io/) — OpenShift Service Mesh 的内核
- [ArgoCD](https://argo-cd.readthedocs.io/) — OpenShift GitOps 的内核
- [Tekton](https://tekton.dev/) — OpenShift Pipelines 的内核
- [Kubeflow](https://www.kubeflow.org/) — OpenShift AI 的 ML 内核

---

## 10. 反向引用与下一步

**反向引用**:本文是 **GKE / K8s 用户视角的 OpenShift 入门**,聚焦"你已有的 K8s 经验如何迁移 / 扩展到 OpenShift"。它和同仓库 K8s 概念文档是**正交关系** — K8s 概念是基础,OpenShift 是上层包装。

**下一步可选项**(若 Lex 需要):
1. **OperatorHub 实战清单**:你最常用的 Operator(Kafka / Redis / PostgreSQL / MongoDB)怎么装到 OpenShift
2. **OpenShift ↔ GKE Service Mesh 迁移指南**:把 ASM 上的 AuthorizationPolicy 迁到 OpenShift Service Mesh 的 SmtpPolicy
3. **OpenShift Dedicated on GCP 安装 runbook**:在你自己的 GCP 项目里跑通 OpenShift Dedicated
4. **OpenShift AI 入门**:Vertex AI 上的工作负载怎么迁到 OpenShift AI(用 vLLM 自托管推理)