# Istio 架构下应用端口自定义评估报告 (Evaluation-istio-http)

## 1. Goal and Constraints (目标与约束)

*   **目标**: 允许业务开发者在使用平台发布应用时，自定义业务容器监听的 HTTP 端口（当前平台硬编码为 `8443`），以符合各大应用框架原本的习惯约定，提升研发体验。
*   **约束**: 
    *   在改变应用暴露端口的同时，必须保证 Istio 网格流量管理的正确性。
    *   外部到网关、网关到 Pod 的 mTLS 安全加密通道（`PeerAuthentication STRICT`）及其相关的 L4 (`NetworkPolicy`)、L7 (`AuthorizationPolicy`) 拦截策略必须能基于新端口动态生效。

## 2. Recommended Architecture (V1) (推荐架构)

**结论评估：非常合理且符合云原生十二要素最佳实践。**

允许用户自定义应用内部通信端口不仅是合理的，还是成熟 PaaS 平台（如 Google Cloud Run、Heroku）的标配。平台应采取**“应用监听环境变量 + 平台通过模板动态渲染网关策略”**的机制，而不是强制所有容器必须使用同一个硬编码端口。

**核心架构调整原则：**
1. **注入约定**: 平台向应用 Pod 固定注入 `PORT` 等环境变量。应用代码需承诺监听该环境变量中的端口（即应用代码自适应平台传参）。
2. **流量形态界定**: 明确应用监听的这部分流量必须为**明文 HTTP**。一切 HTTPS/TLS 加密依然交由外的 Gateway 和 Pod 旁路的 Envoy Sidecar 负责。
3. **架构适配**: 平台侧的 IaC（基础设施即代码，如 Helm、Kustomize）接收这个自定义端口，并按需动态生成所有与其关联的网络及安全配置文件（Service, AP, NP, VS）。

## 3. Trade-offs and Alternatives (权衡与替代方案)

| 方案 | 优点 | 缺点 | 适用阶段 |
| :--- | :--- | :--- | :--- |
| **强制硬编码统一端口（当前 8443）** | 平台管控简单，运维排障时具备直觉性判断（一眼知道全流量汇聚于 8443）。配置模板完全静态，无维护成本。 | 开发者体验欠佳。遗留系统迁移或者使用开源框架（如 Spring Boot 的 8080，Node的 3000）往往需要改代码或强行改 Dockerfile，摩擦力大。 | 平台建设早期 (MVP) |
| **暴露端口自定义能力 (推荐)** | 完全符合业务习惯，做到真正的“框架无关、镜像即插即用”，有利于业务侧接纳平台。 | 存在少数边缘配置风险（如用了内置保留端口）；平台需实现更复杂的参数渲染逻辑。 | 生产级标准 PaaS 平台 |

## 4. Implementation Steps (实施步骤)

这是一项**中等复杂度 (Moderate)** 的重构，需确保整条流量链条上的资源端口映射均参数化。

**步骤 1：模板参数开放 (Helm / 平台变量)**
在你的平台流水线或 Helm Chart 中暴露出一个控制变量（例如 `appPort`），并在 `Deployment` 中注入给容器：
```yaml
# 在 Deployment 模板中
env:
  - name: PORT
    value: "{{ .Values.appPort }}"
```

**步骤 2：约束自定义端口的黑白名单**
为了防止冲突与安全问题，平台需要在 CI 卡点 / Admission Webhook 拦截一些高风险端口。
*   **不建议使用的特权端口**：`< 1024` (如 `80`, `443` 等)。
*   **严禁使用的 Istio 保留端口**：`15000` (Envoy admin), `15001`/`15006` (Inbound/Outbound 接管), `15020`/`15021` (健康检查), `15012`, `15443` 等。

**步骤 3：重构所有涉及流量控制的资源模板**
所有声明了原有 `8443` 的资源都必须同步被模板化渲染：

1. **Service**
```yaml
ports:
- name: http-web # 必须带上 http- 前缀，让 Istio 自动识别 L7 协议
  port: 80 # Service 对外公开的端口
  targetPort: {{ .Values.appPort }} # <--- 指向自定义业务端口
```

2. **VirtualService (由 Gateway 转发进来时)**
```yaml
route:
- destination:
    host: target-service
    port:
      number: 80 # 此处可以是指向 Service port，或者直接指向 targetPort
```

3. **AuthorizationPolicy (鉴权许可规则)**
```yaml
rules:
- from:
  - source:
      principals: ["cluster.local/ns/istio-ingressgateway-int/sa/istio-ingressgateway-int-sa"]
  to:
  - operation:
      ports: ["{{ .Values.appPort }}"]  # <--- 重要：AP 基于 target 端口拦截
```

4. **NetworkPolicy (L4 物理放行)**
```yaml
ingress:
- from:
  # ... Gateway namespace selector
  ports:
  - protocol: TCP
    port: {{ .Values.appPort }} # <--- 重要：K8s 网络插件仅放行真实业务端口
```

## 5. Validation and Rollback (验证与回滚)

*   **部署前验证**：提交一组自定义为 `3000` 的测试应用套件，审查所有由流水线生成的 YAML 内容是否正确替换了 `3000`，且 Service 的端口声明名称前缀有 `http-`。
*   **联通性验证**：发送外部 HTTPS 请求并返回 `200` HTTP 状态码。登录该 Pod 查看 envoy 的 access log 确认流量确属 mTLS 并在目标侧转化为明文。
*   **防护策略验证**：开一个不带证书的测试 Pod `curl` 业务服务的 `3000` 端口，验证是否如期被 NetworkPolicy 或 PeerAuthentication 阻断。
*   **回滚策略**：在平台 UI 或 Helm 的 `values.yaml` 中设置 `appPort: 8443` 作为 Fallback 缺省值，一旦出问题能保证平滑回滚到现有状态。

## 6. Reliability and Cost Optimizations (可靠性与可用性调优)

*   **平台配置的防御性编程**：不要过于信任业务用户的输入。用户填了字母怎么办？填了 0 怎么办？在 Helm 端或控制器代码应当强制验证类型为 `Int`，且 `Range` 在合理区间内。
*   **Service Name 强规范**：确保每个 Service 声明的每个 port name 形如 `http-xxx`、`grpc-xxx`。对于自定义端口应用，一旦未正确声明协议嗅探可能会失败，最终导致 mTLS 失效或 L7 Metric（监控大盘数据）丢失。

## 7. Handoff Checklist

*   [ ] CI/CD 引擎修改（Helm / Manifest 渲染工具增加端口参数透传支持）
*   [ ] 整理平台保留端口列表，配置防御阻断策略 (CI卡点)
*   [ ] 推送平台指南更新供业务方周知：“为更好的接入平台，请使用平台下发的 `$PORT` 作为应用服务监听端口”
