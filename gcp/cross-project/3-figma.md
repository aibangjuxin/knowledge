# 跨项目 PSC NEG 方案 Figma / FigJam 视觉化脚本

## 使用目标

这份文档不是技术原理说明，而是给 Figma / FigJam 直接落图用的内容脚本。

适用场景：

- 做架构评审图
- 做跨团队沟通图
- 做实施流程白板
- 做汇报页或方案封面页

建议输出成 3 个主画板：

1. **架构总览图**
2. **实施顺序图**
3. **请求生命周期图**

---

## 视觉风格建议

目标风格：**企业级、云架构、分层清晰、颜色克制、信息密度高但不乱**

### 配色建议

| 类型 | 建议颜色 | 用途 |
| --- | --- | --- |
| Consumer 区域 | `#EAF3FF` | A Project / Shared VPC 区块底色 |
| Producer 区域 | `#EEF8EE` | B Project / Private VPC 区块底色 |
| Google Backbone | `#FFF4E5` | PSC 内部通道 / Google 托管区 |
| 安全能力 | `#FFE8E8` | Cloud Armor / Access Control / Approval |
| 数据面路径 | `#2563EB` | 主流量箭头 |
| 控制面路径 | `#F59E0B` | 审批、权限、配置依赖 |
| 说明文本 | `#4B5563` | 次级说明 |
| 边框 | `#D1D5DB` | 卡片边框 |

### 字体建议

- 标题：`IBM Plex Sans` / `SF Pro Display`
- 正文：`IBM Plex Sans` / `Inter`
- 代码或资源名：`JetBrains Mono`

### 图形规则

- Project / Network 层：用大容器框表示
- 资源节点：用圆角矩形卡片表示
- 安全控制点：用高亮色卡片表示
- 数据面流量：实线箭头
- 控制面 / 审批 / 依赖：虚线箭头
- 强约束：在连线旁标 `Must`
- 可选项：在节点右上角标 `Optional`

---

## 总体画板布局

建议横向排 3 个主画板，适合演示和滚动查看。

```text
[Frame 1 架构总览]   [Frame 2 实施顺序]   [Frame 3 请求生命周期]
```

建议尺寸：

- 每个主画板：`1600 x 900`
- 画板间距：`120`
- 画板标题区高度：`96`
- 内容区左右内边距：`48`

---

## Frame 1：架构总览图

### 画板标题

**标题**

`Cross-Project PSC NEG Architecture`

**副标题**

`A Project 通过 Global HTTPS Load Balancer + PSC NEG 访问 B Project 私有服务`

---

### 分层布局

这一页建议分成 4 层，从左到右排布：

1. External Access
2. Consumer Side
3. Google Managed Connectivity
4. Producer Side

可直接按下面的结构摆放：

```text
Client → DNS → GLB → Cloud Armor → Backend Service → PSC NEG → PSC Backbone → Service Attachment → ILB → Backend
```

---

### 容器 1：External Access

**容器标题**

`External Access`

**容器说明**

`公网入口与域名解析层`

**节点 1**

标题：
`External Client`

正文：
`用户 / 调用方`
`从公网发起 HTTPS 请求`

**节点 2**

标题：
`Public DNS`

正文：
`业务域名解析`
`指向 Global HTTPS LB`

连接线文案：

- Client → DNS：`Resolve API Domain`
- DNS → GLB：`HTTPS 443`

---

### 容器 2：Consumer Side

容器底色建议用 `#EAF3FF`

**容器标题**

`A Project`

**容器副标题**

`Service Project / Shared VPC / PSC Consumer`

#### 节点 1

标题：
`Global HTTPS Load Balancer`

正文：
`公网统一入口`
`TLS Termination`
`支持全局转发`

#### 节点 2

标题：
`Cloud Armor`

正文：
`WAF / IP Allowlist`
`Geo / Rate Limit`
`入口层安全控制`

标签：
`Recommended`

#### 节点 3

标题：
`Backend Service`

正文：
`承接 LB 后端配置`
`挂接 PSC NEG`
`承载后端策略`

#### 节点 4

标题：
`PSC NEG`

正文：
`type: PRIVATE_SERVICE_CONNECT`
`GLB 可引用的 PSC 后端对象`
`指向 Producer Service Attachment`

#### 节点 5

标题：
`Consumer Subnet`

正文：
`普通 Subnet`
`用于分配 PSC 接入 IP`
`不需要 PRIVATE_SERVICE_CONNECT purpose`

标签：
`Must`

连接线文案：

- GLB → Cloud Armor：`Apply Security Policy`
- Cloud Armor → Backend Service：`Forward Allowed Traffic`
- Backend Service → PSC NEG：`Select Backend`
- Consumer Subnet → PSC NEG：`Allocate PSC Endpoint IP`

建议补一条侧边说明：

`Shared VPC 下，A Project 需要对目标 subnet 具备 compute.networkUser 权限`

---

### 容器 3：Google Managed Connectivity

容器底色建议用 `#FFF4E5`

**容器标题**

`Google Internal Backbone`

**容器说明**

`PSC 建立的是服务级私有连接，不是 VPC 网络打通`

**中心节点**

标题：
`Private Service Connect`

正文：
`Service-Level Private Connectivity`
`No VPC Peering Required`
`IP Space Can Overlap`

连接线文案：

- PSC NEG → PSC Backbone：`Private Service Traffic`
- PSC Backbone → Service Attachment：`Forward to Published Service`

建议做 3 个小标签贴纸：

- `No Peering`
- `Service Isolation`
- `Cross Project Supported`

---

### 容器 4：Producer Side

容器底色建议用 `#EEF8EE`

**容器标题**

`B Project`

**容器副标题**

`Producer / Private VPC`

#### 节点 1

标题：
`Service Attachment`

正文：
`Producer 对外发布内部服务`
`控制 Consumer 接入`
`支持 Allowlist / Manual Approval`

标签：
`Core Control Point`

#### 节点 2

标题：
`PSC NAT Subnet`

正文：
`purpose=PRIVATE_SERVICE_CONNECT`
`为 Producer 侧 PSC 转换分配地址`

标签：
`Must`

#### 节点 3

标题：
`Internal Load Balancer`

正文：
`接收来自 PSC 的私有流量`
`分发至后端服务`

#### 节点 4

标题：
`Backend Service`

正文：
`GKE Service`
`Managed Instance Group`
`Virtual Machines`

连接线文案：

- Service Attachment → ILB：`Forward Approved Traffic`
- PSC NAT Subnet → Service Attachment：`Provide NAT Pool`
- ILB → Backend Service：`Load Balance to Workloads`

右侧可补一块风险说明卡：

标题：
`Why Producer Safer`

正文：
`不暴露 Backend IP`
`Consumer 访问的是服务，不是裸 IP`
`Producer 可决定谁能连、何时连`

---

### Frame 1 底部总结条

建议做成横向总结卡，放在底部。

**标题**

`Key Outcome`

**正文**

`公网入口留在 A Project，私有服务留在 B Project；通过 PSC 实现跨 Project 的服务级私有接入，并把访问控制权收回到 Producer 侧。`

---

## Frame 2：实施顺序图

### 画板标题

**标题**

`Implementation Sequence`

**副标题**

`先建 Producer 发布能力，再建 Consumer 接入能力，最后串联公网入口`

---

### 布局方式

建议使用 3 列泳道：

1. `Phase 1 - Producer Preparation`
2. `Phase 2 - Consumer Integration`
3. `Phase 3 - Global Exposure`

每列纵向排卡片，卡片之间用编号箭头连接。

---

### Phase 1 - Producer Preparation

列底色建议：浅绿色

#### 卡片 1

标题：
`Create Internal Load Balancer`

正文：
`先准备可承接流量的 Producer 入口`
`后端可为 GKE / VM / MIG`

编号：
`01`

#### 卡片 2

标题：
`Create PSC NAT Subnet`

正文：
`purpose=PRIVATE_SERVICE_CONNECT`
`这是 Service Attachment 的硬依赖`

编号：
`02`

#### 卡片 3

标题：
`Create Service Attachment`

正文：
`绑定 ILB`
`绑定 NAT Subnet`
`配置 connection-preference`

编号：
`03`

#### 卡片 4

标题：
`Configure Consumer Acceptance`

正文：
`Allowlist Consumer Project`
`或启用 Manual Approval`

编号：
`04`

---

### Phase 2 - Consumer Integration

列底色建议：浅蓝色

#### 卡片 5

标题：
`Select Shared VPC Subnet`

正文：
`选择 A Project 可用的 Consumer Subnet`
`确认 compute.networkUser 权限`

编号：
`05`

#### 卡片 6

标题：
`Create PSC NEG`

正文：
`type=PRIVATE_SERVICE_CONNECT`
`指向 B Project Service Attachment`

编号：
`06`

#### 卡片 7

标题：
`Validate PSC Connection`

正文：
`检查 connectedEndpoints 状态`
`确认是否需要 Producer 手动批准`

编号：
`07`

---

### Phase 3 - Global Exposure

列底色建议：浅橙色

#### 卡片 8

标题：
`Create or Update Backend Service`

正文：
`将 PSC NEG 挂到 GLB Backend Service`

编号：
`08`

#### 卡片 9

标题：
`Bind Cloud Armor`

正文：
`在入口层加 WAF / IP / Geo / Rate Limit`

编号：
`09`

标签：
`Recommended`

#### 卡片 10

标题：
`Create URL Map / HTTPS Proxy / Forwarding Rule`

正文：
`完成 Global HTTPS LB 串联`
`对外提供统一域名入口`

编号：
`10`

#### 卡片 11

标题：
`Run End-to-End Validation`

正文：
`验证公网到私有服务的完整链路`
`验证 Producer 侧访问控制是否生效`

编号：
`11`

---

### Frame 2 辅助信息卡

建议在右侧放 3 张小卡片：

#### 小卡 1

标题：
`Hard Dependencies`

正文：
`PSC NEG 与 Service Attachment 必须同 Region`
`Service Attachment 必须绑定 PSC NAT Subnet`
`GLB 是 Global，PSC NEG 是 Regional`

#### 小卡 2

标题：
`Most Common Failure`

正文：
`Shared VPC 权限不足`
`Producer 未放行 Consumer`
`Consumer / Producer 区域不一致`

#### 小卡 3

标题：
`Deployment Principle`

正文：
`先让 Producer 可发布`
`再让 Consumer 可接入`
`最后再开放公网入口`

---

## Frame 3：请求生命周期图

### 画板标题

**标题**

`Request Lifecycle`

**副标题**

`一次外部请求如何经过 GLB、PSC、Service Attachment、ILB 到达后端`

---

### 布局方式

建议做成纵向编号流程，共 10 步，每一步一个卡片，左侧是步骤编号，右侧是说明。

每一步可使用下面文案：

#### Step 1

标题：
`Client Sends HTTPS Request`

正文：
`外部调用方访问业务域名`

#### Step 2

标题：
`Global HTTPS Load Balancer Receives Traffic`

正文：
`入口层接收请求并终止 TLS`

#### Step 3

标题：
`Cloud Armor Evaluates Policy`

正文：
`执行安全策略`
`过滤不允许的来源或异常请求`

#### Step 4

标题：
`Backend Service Selects PSC NEG`

正文：
`请求被路由到 PSC 类型后端`

#### Step 5

标题：
`PSC NEG Uses Consumer-Side Endpoint IP`

正文：
`命中 Consumer Subnet 中分配的 PSC 接入 IP`

#### Step 6

标题：
`PSC Transfers Traffic Over Google Backbone`

正文：
`通过 Google 内部网络将流量发送到 Producer 发布的服务`

#### Step 7

标题：
`Service Attachment Validates Consumer`

正文：
`Producer 校验该 Consumer 是否被允许访问`

#### Step 8

标题：
`Producer Applies PSC NAT`

正文：
`使用 PSC NAT Subnet 中的地址进行转换`

#### Step 9

标题：
`Internal Load Balancer Forwards to Backend`

正文：
`ILB 将流量送到 GKE / VM / MIG`

#### Step 10

标题：
`Response Returns to Client`

正文：
`响应沿同一逻辑路径返回客户端`

---

### Frame 3 底部强调卡

建议放 4 个横向小卡：

#### 卡 1

标题：
`Traffic Isolation`

正文：
`访问的是服务，不是裸 IP`

#### 卡 2

标题：
`Producer Control`

正文：
`最终放行权在 Service Attachment`

#### 卡 3

标题：
`No Network Mesh`

正文：
`无需 VPC Peering，无需暴露整网路由`

#### 卡 4

标题：
`Better Security Boundary`

正文：
`公网治理在入口层，私网服务保留在 Producer 内部`

---

## FigJam 版简化布局

如果你想先在 FigJam 快速白板化，不做正式设计稿，可以按下面结构：

### 区域 1

标题：
`Problem Today`

内容：
`GLB -> NON_GCP_PRIVATE_IP_PORT NEG -> ILB IP -> Backend`

补 3 个红色问题贴纸：

- `Producer IP 暴露`
- `访问控制弱`
- `服务隔离弱`

### 区域 2

标题：
`Target Design`

内容：
`GLB -> PSC NEG -> Service Attachment -> ILB -> Backend`

补 4 个绿色收益贴纸：

- `Service-Level Access`
- `Producer-Controlled Access`
- `No Backend IP Exposure`
- `Cross-Project Native Pattern`

### 区域 3

标题：
`Implementation Path`

内容：

- `Prepare Producer`
- `Publish Service`
- `Create Consumer PSC NEG`
- `Attach to GLB`
- `Validate End-to-End`

---

## 适合直接贴进图里的短文案

下面这些是适合放在节点里的短句，长度适合卡片 UI。

### 可复用标题

- `External Entry`
- `Consumer Side`
- `Producer Side`
- `Security Boundary`
- `PSC Service Connectivity`
- `Approval Control`
- `Private Service Publishing`
- `Global Entry, Private Backend`

### 可复用说明

- `Traffic enters from public internet`
- `TLS and edge security terminate here`
- `PSC NEG exposes a private service as a GLB backend`
- `Producer publishes service without exposing backend IP`
- `Access is controlled at service attachment level`
- `No VPC peering is required`
- `Consumer and Producer remain network-isolated`
- `PSC NAT subnet is mandatory on producer side`

---

## 适合放在封面页的一句话

`通过 Global HTTPS Load Balancer + PSC NEG + Service Attachment，把跨 Project 访问从“IP 级互通”升级为“服务级私有接入”。`

---

## 交付建议

如果你接下来要真的在 Figma 里画，建议按这个顺序做：

1. 先做 **Frame 1 架构总览**，这张最适合评审和汇报
2. 再做 **Frame 2 实施顺序**，这张适合落地实施和排期
3. 最后做 **Frame 3 请求生命周期**，这张适合解释原理和做知识传递

如果只画一张，优先画 **Frame 1**。


最直接的结论：

**不能把一整段 Markdown 直接丢进 Figma，然后让它自动变成完整架构设计稿。**  
更可行的方式有 3 种，我建议你用第 1 种。

**推荐方式：先用 FigJam 生成结构图**
1. 打开 FigJam，新建一个白板。
2. 不要直接贴整份 Markdown，先把你要生成的那一部分改成“明确指令”。
3. 把这类 prompt 贴给 FigJam AI 或让它生成 flowchart。

你可以直接用这段：

```text
Create a cloud architecture diagram in FigJam.

Topic:
Cross-project PSC NEG architecture on Google Cloud.

Layout:
Use 4 zones from left to right:
1. External Access
2. A Project (Service Project / Shared VPC / PSC Consumer)
3. Google Internal Backbone
4. B Project (Producer / Private VPC)

Main flow:
External Client -> Public DNS -> Global HTTPS Load Balancer -> Cloud Armor -> Backend Service -> PSC NEG -> Private Service Connect -> Service Attachment -> Internal Load Balancer -> Backend Service

Consumer-side notes:
- PSC NEG is the consumer endpoint group
- Consumer subnet is a normal subnet
- It is used to allocate the PSC endpoint IP
- Shared VPC subnet access requires compute.networkUser

Producer-side notes:
- Service Attachment is the main control point
- PSC NAT subnet is required
- NAT subnet purpose is PRIVATE_SERVICE_CONNECT
- Backend can be GKE / VM / MIG

Style:
Use enterprise cloud architecture style, clean containers, rounded cards, labeled arrows, soft blue for consumer, soft green for producer, soft orange for Google backbone.
```

**第二种方式：把 Markdown 先改成 Mermaid，再放进支持 Mermaid 的流程**
你的 [3.md](/Users/lex/git/knowledge/gcp/cross-project/3.md) 里已经有 Mermaid 图了。  
如果你想要“先出图，再进 Figma”，可以这样做：

1. 先把 Mermaid 渲染成图。
2. 导出为 SVG 或 PNG。
3. 拖进 Figma 继续美化。

这种方式适合：
- 先快速确认结构
- 再在 Figma 里做视觉升级

**第三种方式：把 Markdown当作“设计脚本”，手动搭 Figma**
这个方式最稳定，尤其适合你现在这份 [3-figma.md](/Users/lex/git/knowledge/gcp/cross-project/3-figma.md)。

做法是：
1. 在 Figma 新建 3 个 Frame。
2. 按 [3-figma.md](/Users/lex/git/knowledge/gcp/cross-project/3-figma.md) 里的 `Frame 1 / 2 / 3` 结构搭容器。
3. 把每个“节点标题 / 正文 / 连线文案”复制进对应卡片。
4. 再统一套颜色和样式。

**如果你想让 Figma 更“自动”一点，最好的输入不是 Markdown，而是：**
- 一段明确 prompt
- 一份 Mermaid
- 一份拆好的 Frame/Node 清单

你现在手里其实已经有第 3 种最适合自动生成的素材了，就是 [3-figma.md](/Users/lex/git/knowledge/gcp/cross-project/3-figma.md)。

如果你愿意，我下一步可以直接帮你做两件事里的一个：
1. 把 [3-figma.md](/Users/lex/git/knowledge/gcp/cross-project/3-figma.md) 进一步压成一段“可直接贴给 FigJam AI 的英文 prompt”
2. 直接帮你生成一版 Mermaid / FigJam diagram 内容，让你不用自己再改