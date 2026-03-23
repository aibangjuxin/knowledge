

- internal && https
- internal ilb && Load balancer type is Application && access type is internal 
  - regional internal Application Load Balancer
  - support create backend service type 
    - 1. Zone network endpoint group ==> GCE && GKE backends
    - 2. Internet network endpoint group ==>  External backends
    - 3. Private service connect network endpoint group ==> PSC backends
    - 4. Serverless network endpoint group ==> Cloud Run, App Engine, Cloud Functions backends
    - 5. Hybrid connectivity network endpoint group (Zonal) ==> Backends that are on-premises or on-other clouds via private connectivity

- external && https 
- glb && load balancer type is Application(Classic) && Access type is Extenal
  - classic Application Load Balancer 
  - support create backend service type 
    - 1. Zone network endpoint group ==> GCE && GKE backends
    - 2. Internet network endpoint group ==>  External backends
    - 3. Serverless network endpoint group ==> Cloud Run, App Engine, Cloud Functions backends
    - 4. Hybrid connectivity network endpoint group (Zonal) ==> Backends that are on-premises or on-other clouds via private connectivity
    
  
- 当前GLB里提示如下 reminder
```bash
Migrate from Classic to Global external
Application Load Balancers
Get access to the newest features by migrating from classic to the
global external load balancer. To migrate, you'll switch your backend
services and forwarding rules from the EXTERNAL to the
EXTERNAL_MANAGED load balancing scheme. This step-wise
migration process lets you gradually shift traffic from the classic to
the global load balancing infrastructure.
```

## 背景与问题分析

### 问题核心
你在 **Internal Application Load Balancer** 里面能够看到创建 `Private service connect network endpoint group (PSC backends)` 的选项，但在你的外部 GLB (Global Load Balancer) 中却没有找到这个选项，且界面上出现了提示从 Classic 版本迁移的警告。

### 背景解析
GCP 外部应用层负载均衡器 (Application Load Balancer) 目前同时存在**两代架构**：
1. **Classic Application Load Balancer（经典版）**：基于较早的 Google Front End (GFE) 架构，主要为基于 HTTP/HTTPS 的外部通信而设计，负载均衡方案 (Load Balancing Scheme) 为 `EXTERNAL`。这个架构**不支持**基于 Private Service Connect (PSC) NEG 的后端服务。
2. **Global external Application Load Balancer（全局新版）**：基于新一代的 Envoy 代理架构，负载均衡方案为 `EXTERNAL_MANAGED`。新的 Envoy 架构带来了高级流控、Service Extensions 服务扩展以及 PSC NEG 配置的支持等众多现代特性。

与之对应，**Internal Application Load Balancer** 同样使用基于 Envoy 代理的架构版本，因此天生支持 PSC NEG 后端，能够安全地打通并使用私有方式访问托管服务。

### 结论
你的外部 GLB 之所以没有 **Private service connect network endpoint group** 选项，是因为当前使用的是 **Classic 版本的外部负载均衡器**。按照控制台提示：如果希望使用 PSC NEG 或者其他 Envoy 组件带来的高级流量管理与安全控制等最新特性，你需要将你的 Classic ALB **迁移至 Global external Application Load Balancer**（即把 Backend Services 等从 `EXTERNAL` 切换为 `EXTERNAL_MANAGED` 体系结构）。

## 各类型 Application Load Balancer 后端支持对比

基于提供的信息与架构差异，LB 对后端服务类型的支持情况补充对比如下表：

| 后端服务支持的负端端点类型 (NEG)                                | internal Application LB<br>*(Envoy-based)* | classic Application LB<br>*(Global / GFE-based)* | global external Application LB<br>*(Global / Envoy-based)* |
| :-------------------------------------------------------------- | :----------------------------------------: | :----------------------------------------------: | :--------------------------------------------------------: |
| 1. **Zone NEG**<br>*(GCE & GKE backends)*                       |                   ✅ 支持                   |                      ✅ 支持                      |                           ✅ 支持                           |
| 2. **Internet NEG**<br>*(External backends)*                    |                   ✅ 支持                   |                      ✅ 支持                      |                           ✅ 支持                           |
| 3. **Serverless NEG**<br>*(Cloud Run, App Engine...)*           |                   ✅ 支持                   |                      ✅ 支持                      |                           ✅ 支持                           |
| 4. **Hybrid connectivity NEG**<br>*(On-premises / cross-cloud)* |                   ✅ 支持                   |                      ✅ 支持                      |                           ✅ 支持                           |
| 5. **Private service connect NEG**<br>*(PSC backends)*          |                 ✅ **支持**                 |                   ❌ **不支持**                   |                         ✅ **支持**                         |


# current status
- classic Application LB (Global / GFE-based) ==> no support PSC NEG
  -  所以如果仅仅修改现存的 GLB 无法完成这个测试
- 我们需要使用 global external Application LB (Global / GFE-based) ==> support PSC NEG 来完成对应的测试
  - but we need to let's org policy allow create this type of LB
  - `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS is not allowed`
- PSC Attachment 只支持 Regional
```
⚠️ 核心限制：
Service Attachment → 只有 Regional 概念
PSC NEG (Consumer 侧) → 也是 Regional 的
GLB → Global，但其 Backend NEG 是 Regional
```
- Producer 侧需要开启 allowGlobalAccess
  - 1.  需要分析如果是 Forwarding Rule,那么如何开启 allowGlobalAccess
  - 2.  如果是 GKE Gateway,那么如何开启 allowGlobalAccess
  - 3.  如果是 Cloud Service Mesh,那么如何开启 allowGlobalAccess
-

- `Can we create a GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS GLB?`
```bash
Message:
We are testing a PSC NEG-based architecture.  
Our current classic Application Load Balancer does not support PSC NEG, so modifying the existing GLB is not enough for this test.

We need to create a `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` Global external Application Load Balancer, but it appears this is currently blocked by Org Policy:
`GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS is not allowed`

Could you please confirm:
1. Whether our project/folder is allowed to create this LB type
2. If not, whether you can enable/allow it for our testing scope
3. If there is a preferred approved path or exception process
```
- `Are we allowed to create a Regional external Application Load Balancer, and if proxy-only subnet migration is required, what would be the impact?`
```bash
Create regional external Application Load Balancer
In order to proceed with this region and VPC network, the purpose of your proxy-only subnet needs to be migrated from
"INTERNAL_HTTPS_LOAD_BALANCER"


We are evaluating whether a Regional external Application Load Balancer can be used for this test.
During creation, the console indicates that, for the current region and VPC, the proxy-only subnet purpose would need to be migrated from INTERNAL_HTTPS_LOAD_BALANCER before we can proceed.

Could you please help confirm:

Whether we are allowed to create a Regional external Application Load Balancer
If creation is allowed, for the current region / VPC:
Whether the proxy-only subnet purpose migration is mandatory
What impact this migration could have on existing load balancers, live traffic, or other resources using that subnet
Whether there is a recommended and safe implementation path or standard process
We would like to confirm these prerequisites before deciding whether to proceed with the Regional external ALB option.
```

# create error anaylze
```bash
Create load balancer "glb-external"
my-project-one
Invalid value for field'resource.backends［O］'：'｛"group"： "projects/
my-project-one/regions/europe-west2/
networkEndpointGroups/abjx-lex-p...
Global L7 Private Service Connect consumers require the Private
Service Connect producer load balancer to have AllowGlobalAccess
enabled

Constraint constraints/
compute.restrictLoadBalancerCreationForTypes violated for
projects/my-project. Forwarding Rule projects/
my-project/global/forwardingRules/glb-front of
type GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS is not allowed.
```

## 创建报错原因分析

这个报错实际上包含了两个独立问题，而且这两个问题都属于创建 **Global external Application Load Balancer + PSC NEG backend** 时的硬性前提校验。

### 1. PSC producer 侧没有开启 `AllowGlobalAccess`
- 比如我选择创建LB的时候选择全部一个默认项的时候提示这个错误
报错关键字如下：

```bash
Global L7 Private Service Connect consumers require the Private
Service Connect producer load balancer to have AllowGlobalAccess
enabled
```

#### 原因说明

当前正在创建的是 **Global external Application Load Balancer**，后端类型是 **Private Service Connect NEG**。  
这种模式下，GLB 是 **PSC consumer**，而对端发布服务的一侧是 **PSC producer**。

对于 Global L7 来说，PSC producer 对应的负载均衡器必须开启 **AllowGlobalAccess**，否则 GCP 会认为 producer 仅具备区域访问能力，不能满足全局 L7 入口接入要求，因此 backend 校验直接失败。

#### 常见对应场景

通常 producer 侧会是下面几种之一：

- regional internal Application Load Balancer
- 通过 service attachment 暴露出来的内部服务
- 作为 PSC producer 的内部转发规则

如果这些对象后面的 forwarding rule 没有开启 `AllowGlobalAccess`，就会出现这条报错。

#### 这条报错的本质

这不是 consumer 侧 backend service 字段写错了，而是 **PSC 对端服务的可达性边界不满足 global external ALB 的要求**。

#### 处理建议

先到 **producer 项目** 检查对应 forwarding rule：

```bash
gcloud compute forwarding-rules describe FORWARDING_RULE_NAME \
  --region=REGION \
  --project=PRODUCER_PROJECT
```

重点确认：

- 该 forwarding rule 是否为 PSC producer 实际使用的入口
- 是否已启用 `allowGlobalAccess`

如果没启用，需要在 **producer 侧** 修正；只修改 consumer 侧 GLB 配置无法解决。

---

### 2. Organization Policy 禁止创建 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`

报错关键字如下：

```bash
Constraint constraints/compute.restrictLoadBalancerCreationForTypes violated
...
type GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS is not allowed.
```

#### 原因说明

这个错误说明当前项目继承到了组织策略约束：

`constraints/compute.restrictLoadBalancerCreationForTypes`

并且该策略明确 **不允许创建**：

- `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`

而新版 **Global external Application Load Balancer** 底层使用的正是这一类型的 forwarding rule。  
因此即使 PSC producer 已经开启 `AllowGlobalAccess`，只要组织策略不放行，这个 LB 仍然无法创建成功。

#### 这条报错的本质

这是 **组织治理限制**，不是普通配置错误。  
也就是说问题不在某个 backend、URL map、target proxy 的参数细节，而在于该项目从组织层就被禁止创建这类 LB。

#### 处理建议

检查项目当前生效的 Org Policy：

```bash
gcloud resource-manager org-policies describe \
  constraints/compute.restrictLoadBalancerCreationForTypes \
  --project=my-project
```

重点确认允许列表中是否包含：

- `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`

如果没有，需要平台管理员或组织管理员处理，常见方式有三种：

- 放开该 LB 类型，允许项目创建新版 Global external ALB
- 维持限制不变，那么这个项目里就不能落地该方案
- 改成组织策略允许的 LB 形态，重新设计入口架构

---

## 综合结论

这次创建失败并不是单点故障，而是 **两个前置条件同时卡住**：

1. **PSC producer 侧没有开启 `AllowGlobalAccess`**
2. **项目的 Org Policy 不允许创建 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`**

这意味着该问题同时涉及：

- **架构可达性约束**
- **组织治理约束**

任意一个不满足，Global external ALB + PSC NEG 方案都无法创建成功。

## 推荐排查顺序

为了减少无效排查，建议按下面顺序处理：

1. 先确认项目是否被允许创建 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`
2. 如果组织策略不允许，先找管理员放开，否则后续 PSC 调整都没有意义
3. 组织策略放开后，再检查 PSC producer 侧是否启用了 `AllowGlobalAccess`
4. 两项都满足后，再重新创建 Global external ALB 和 PSC NEG backend

## 适合沉淀为实施前置条件的结论

如果目标是使用：

- **Global external Application Load Balancer**
- **Private Service Connect NEG backend**

那么必须同时满足以下前置条件：

- **前提 1**：Organization Policy 允许 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`
- **前提 2**：PSC producer 对应的负载均衡器已开启 `AllowGlobalAccess`

只满足其中一个，方案仍然无法落地。

## forwarding rule 如何开启 `AllowGlobalAccess`

这一节重点回答：**PSC producer 侧的 forwarding rule 应该怎么开启 `AllowGlobalAccess`**。

### 先说结论

如果 PSC producer 后面挂的是 **regional internal Application Load Balancer**，那么 `AllowGlobalAccess` 是配置在它的 **frontend forwarding rule** 上的。

官方文档给出的做法是：

- **新建一个** 开启了 `AllowGlobalAccess` 的 forwarding rule
- 然后把流量切换到新的 frontend
- 最后删除旧的 forwarding rule

也就是说，对这个场景不要默认理解成“直接修改原有 forwarding rule 开关”。

### 为什么不是直接修改旧 forwarding rule

GCP 官方在 regional internal Application Load Balancer 的文档里明确说明：

- 不能直接修改现有 regional forwarding rule 来开启 global access
- 如果要启用 global access，需要新建一个 forwarding rule
- 如果后续要关闭 global access，同样需要再创建一个新的 regional-only forwarding rule

这意味着 `AllowGlobalAccess` 对这个场景本质上属于 **frontend forwarding rule 的创建属性**，不是一个建议你在线原地切换的普通参数。

### 适用范围

这里说的开启方式，适用于 producer 侧是以下这类入口时：

- **Regional internal Application Load Balancer**
- forwarding rule 类型为 **regional**
- load balancing scheme 为 `INTERNAL_MANAGED`

如果你的 producer 不是这个类型，而是别的 PSC producer 形态，那么要再按具体资源类型确认。

## 推荐实施方式

### 方案 A：新建一个开启全局访问的新 forwarding rule

这是最稳妥、也最符合官方文档的方法。

#### HTTP 示例

```bash
gcloud compute forwarding-rules create ilb-fr-global-access \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --network=VPC_NETWORK \
  --subnet=SUBNET_NAME \
  --address=ILB_IP_ADDRESS \
  --ports=80 \
  --region=REGION \
  --target-http-proxy=TARGET_HTTP_PROXY_NAME \
  --target-http-proxy-region=REGION \
  --allow-global-access
```

#### HTTPS 示例

```bash
gcloud compute forwarding-rules create ilb-fr-global-access \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --network=VPC_NETWORK \
  --subnet=SUBNET_NAME \
  --address=ILB_IP_ADDRESS \
  --ports=443 \
  --region=REGION \
  --target-https-proxy=TARGET_HTTPS_PROXY_NAME \
  --target-https-proxy-region=REGION \
  --allow-global-access

--allow-global-access
If True, then clients from all regions can access this internal forwarding rule. This can only be specified for forwarding rules with the LOAD_BALANCING_SCHEME set to INTERNAL or INTERNAL_MANAGED. For forwarding rules of type INTERNAL, the target must be either a backend service or a target instance.
如果为True，则所有地区的客户端都可以访问此内部转发规则。这只能为负载均衡方案（LOAD_BALANCING_SCHEME）设置为INTERNAL或INTERNAL_MANAGED的转发规则指定。对于类型为INTERNAL的转发规则，目标必须是后端服务或目标实例。
--allow-psc-global-access
If specified, clients from all regions can access this Private Service Connect forwarding rule. This can only be specified if the forwarding rule's target is a service attachment (--target-service-attachment).
如果指定，所有地区的客户端都可以访问此Private Service Connect转发规则。只有当转发规则的目标是服务附件（--target-service-attachment）时，才能进行此指定。


```

### 参数说明

- `--load-balancing-scheme=INTERNAL_MANAGED`
  - 表示这是 internal Application Load Balancer 的 forwarding rule
- `--target-http-proxy` 或 `--target-https-proxy`
  - 指向 producer ILB 现有的 target proxy
- `--allow-global-access`
  - 开启全局访问能力，这是本次最关键的参数
- `--address`
  - 建议使用静态内网 IP，便于切换和排障

### 一个很重要的实施限制

如果你希望 **沿用同一个 VIP** 给多个 forwarding rule 复用，IP 地址通常需要在创建时使用：

```bash
--purpose=SHARED_LOADBALANCER_VIP
```

否则你在切换 frontend 时，可能无法复用同一个地址，只能新建一个新的内网 VIP。

这对 PSC producer 很重要，因为如果 service attachment 或上游依赖绑定了固定入口地址，你需要提前确认是否允许换 VIP。

## 推荐变更步骤

为了更贴近生产环境，建议按下面顺序做：

1. 先识别 producer ILB 当前实际使用的 forwarding rule、target proxy、VIP、端口、region
2. 确认当前内网地址是否支持 `SHARED_LOADBALANCER_VIP`
3. 创建一个新的、带 `--allow-global-access` 的 forwarding rule
4. 校验新 forwarding rule 的 `allowGlobalAccess` 是否为 `True`
5. 验证 PSC consumer 或跨区域客户端是否可以正常访问
6. 确认业务无异常后，再删除旧 forwarding rule

## 如何校验是否已开启成功

创建完成后，可以这样检查：

```bash
gcloud compute forwarding-rules describe ilb-fr-global-access \
  --region=REGION \
  --format="get(name,region,IPAddress,IPProtocol,allowGlobalAccess)"
```

如果开启成功，输出中应看到：

```bash
True
```

更完整地看原始字段也可以：

```bash
gcloud compute forwarding-rules describe ilb-fr-global-access \
  --region=REGION
```

重点看：

- `loadBalancingScheme: INTERNAL_MANAGED`
- `allowGlobalAccess: true`
- `target` 是否指向预期的 target proxy

## 回滚方式

如果开启后发现不符合预期，建议这样回滚：

1. 保留旧 forwarding rule，不要先删
2. 先用新 forwarding rule 做验证
3. 如果验证失败，直接继续使用旧 forwarding rule
4. 删除新建的 global access forwarding rule

如果你已经删除旧 rule，那么回滚方式就是：

- 重新创建一个 **不带** `--allow-global-access` 的 forwarding rule

## 对当前问题的直接映射

你前面的报错里提到：

```bash
Global L7 Private Service Connect consumers require the Private
Service Connect producer load balancer to have AllowGlobalAccess
enabled
```

把这条报错翻译成实施动作，就是：

- 去 **PSC producer 所在项目**
- 找到 producer 对应的 **regional internal Application Load Balancer forwarding rule**
- 按上面的方式创建一个带 `--allow-global-access` 的新 frontend forwarding rule
- 再重新让 PSC consumer 侧接入

## 文档级结论

对 **regional internal Application Load Balancer** 类型的 PSC producer 来说，开启 `AllowGlobalAccess` 的推荐方法不是修改旧 forwarding rule，而是：

1. 创建一个新的 forwarding rule
2. 创建时加上 `--allow-global-access`
3. 校验 `allowGlobalAccess: true`
4. 验证无误后替换旧 forwarding rule

---

# 错误分析：Proxy-Only Subnet 迁移报错

```bash
Create regional external Application Load Balancer
In order to proceed with this region and VPC network, the purpose of your proxy-only subnet needs to be migrated from
"INTERNAL_HTTPS_LOAD_BALANCER"
```

## 背景与原因分析

### 1. 什么是 Proxy-only Subnet
GCP 基于 Envoy 的新一代负载均衡器（包含 **区域内部应用负载均衡器 Regional Internal ALB** 和 **区域外部应用负载均衡器 Regional External ALB**）需要一个**专用代理子网 (Proxy-only subnet)** 来容纳其底层的 Envoy 代理实例。每个 VPC 在各个对应的 Region 只需要且只能有一个被激活使用的代理子网。

### 2. 这个报错产生的历史原因
早期时候，Envoy 架构主要是 Internal ALB 在独占使用。如果您在较早的时候就在该 Region 和 VPC 内创建过代理子网，GCP 会自动将其资源用途 (Purpose) 固定为 `INTERNAL_HTTPS_LOAD_BALANCER`。

随后，GCP 推出了同样基于 Envoy 的 Regional External ALB。为了让这内、外部两种负载均衡器能共享并复用同一个代理子网池，GCP 将该子网的用途进行了一次架构级别的重命名扩展，将其称作 `REGIONAL_MANAGED_PROXY`（区域托管代理）。

因此，当您现在尝试在这个区域内创建一个**新的区域级外部负载均衡器 (Regional External ALB)** 时，系统检测到该 Region 的代理子网带有的标签还是旧名字（它标明自己只能给内部LB用），GCP 为了安全防范触发了这一校验错误，并要求您显式地进行用途声明变更。

### 3. 本质说明
这**完全不是一个网络或者配额故障**，只是 GCP 底层基础设施迭代演进过程中的一次**兼容性升级强制确认**。

## 解决方案

解决方案非常快捷，只需要更新已存在代理子网的 `purpose` 为最新形态即可：

### 命令行解决 (推荐)

通过 `gcloud` 命令更新已有子网的用途：

```bash
gcloud compute networks subnets update PROXY_ONLY_SUBNET_NAME \
    --region=REGION_NAME \
    --purpose=REGIONAL_MANAGED_PROXY
```
*(注意：请将 `PROXY_ONLY_SUBNET_NAME` 替换为何报该错涉及的子网实际名称，并将 `REGION_NAME` 换为目标 Region)*

### UI 控制台解决路径
1. 进入 GCP 控制台，导航至 **VPC Network (VPC 网络) -> Subnets (子网)**。
2. 找到此 Region 的 Proxy-only 子网，点击进入详情页。
3. 点击顶部的 **EDIT (修改)**，在用途/目的 (Purpose) 或者页面警告横幅中，会引导您将其修改/迁移至 `REGIONAL_MANAGED_PROXY`。保存即可。

## 注意事项与影响
* **业务零中断**：进行这个升级对该 Region 已有的正在运转的 Internal ALB 完全透明，**不会影响或中断**任何现有连接中的内网业务。
* **共存支持**：升级后的代理子网同时能够服务该区域内现存的所有包含内、外部的新一代 Envoy LB 需求。
* **变更单向性**：这个属单向升级操作，迁移至 `REGIONAL_MANAGED_PROXY` 后不可以再降级退回到 `INTERNAL_HTTPS_LOAD_BALANCER`（由于新名字包含旧的全部业务功能，本身也无任何回退的必要）。
