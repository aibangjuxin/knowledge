

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
    
  
- 当前GLB里提示如下
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

| 后端服务支持的负端端点类型 (NEG) | internal Application LB<br>*(Envoy-based)* | classic Application LB<br>*(Global / GFE-based)* | global external Application LB<br>*(Global / Envoy-based)* |
| :--- | :---: | :---: | :---: |
| 1. **Zone NEG**<br>*(GCE & GKE backends)* | ✅ 支持 | ✅ 支持 | ✅ 支持 |
| 2. **Internet NEG**<br>*(External backends)* | ✅ 支持 | ✅ 支持 | ✅ 支持 |
| 3. **Serverless NEG**<br>*(Cloud Run, App Engine...)* | ✅ 支持 | ✅ 支持 | ✅ 支持 |
| 4. **Hybrid connectivity NEG**<br>*(On-premises / cross-cloud)*| ✅ 支持 | ✅ 支持 | ✅ 支持 |
| 5. **Private service connect NEG**<br>*(PSC backends)* | ✅ **支持** | ❌ **不支持** | ✅ **支持** |
