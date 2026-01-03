# Minimal Platform Adaptation Strategy (Mini-Change)

## 1. 背景与问题 (Background)

作为一个API平台，我们面临着多租户/多用户场景下的服务标准不统一问题。特别是在**健康检查 (Health Check)** 方面，不同用户的应用表现出极大的差异性：

*   **路径不统一**：有的使用 `/health`，有的使用 `/readyz` 或 `/live`。
*   **缺失健康检查**：部分用户应用根本没有暴露 HTTP 健康检查接口。
*   **协议差异**：HTTP vs HTTPS 混用。

为了解决这些问题，同时保持平台改动的最小化 (Minimal Change)，我们需要制定一套临时且强制的适配策略。

## 2. 核心策略 (Core Strategy)

我们采取 **"强制配置注入 (Mandatory Configuration Injection)"** 的策略。

不要求用户修改代码，而是在部署阶段，通过在用户的 Namespace 中强制注入标准化的配置，来统一服务的行为。

### 2.1 目标 (Objectives)
1.  **统一入口**：强制所有接入平台的服务启动在统一端口。
2.  **统一路径**：强制规范化 Context Path，便于网关路由和管理。
3.  **安全合规**：强制开启 SSL。
4.  **规避健康检查混乱**：通过统一端口和协议，平台可以至少实施 TCP 级别的统一检查，或者利用 Spring Boot 的默认行为（如果适用）来标准化管理端点。

## 3. 实施方案 (Implementation)

### 3.1 强制配置规范
在用户的每个 Namespace 中，强制下发并挂载以下 ConfigMap。

*   **端口**：`8443` (HTTPS)
*   **SSL**：启用，使用统一的 Keystore。
*   **Context Path**：`/${apiName}/v${minorVersion}` (同时覆盖 Servlet 和 WebFlux)。

### 3.2 配置详情 (Configuration Detail)

以下是必须注入的 ConfigMap 定义：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: ${namespace}
  name: mycoat-common-sprint-conf
data:
  server-conf.properties: |
    # 强制统一端口
    server.port=8443
    
    # 强制开启 SSL
    server.ssl.enabled=true
    server.ssl.key-store=/opt/keystore/mycoat-sbrt.p12
    server.ssl.key-store-type=PKCS12
    server.ssl.key-store-password=${KEY_STORE_PWD}
    
    # 统一 Context Path (Servlet 栈)
    server.servlet.context-path=/${apiName}/v${minorVersion}
    
    # 统一 Base Path (WebFlux 栈)
    sprint.webflux.base-path=/${apiName}/v${minorVersion}
```

## 4. 平台适配收益 (Benefits)

1.  **降低接入成本**：用户无需修改代码中的端口或路径配置，由平台统一接管。
2.  **简化健康检查**：虽然用户内部健康检查逻辑可能不同，但统一了端口 `8443` 后，平台可以配置统一的 TCP Socket 探针作为兜底，或者在统一的 Context Path 下尝试探测标准端点。
3.  **标准化路由**：网关层可以基于 `${apiName}/v${minorVersion}` 规则自动生成路由，无需逐个配置。

## 5. 后续规划 (Next Steps)
*   该策略为"最小化改动"的临时策略。
*   长期方案应推动用户应用接入标准的 Actuator 或 Sidecar 模式以提供统一的 HTTP 健康检查接口。
