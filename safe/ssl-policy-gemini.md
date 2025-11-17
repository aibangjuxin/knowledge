# 指南：为 GKE Gateway 配置自定义 SSL Policy 以强制使用 TLS 1.2

本文档根据您的实践经验总结，旨在说明如何为 Google Kubernetes Engine (GKE) Gateway 配置一个自定义的 SSL Policy，以确保所有传入流量都遵循指定的最低 TLS 版本（例如 TLS 1.2），从而修复潜在的安全风险 (violation)。

---

## 核心概念

Google Cloud 允许您创建独立的 **SSL Policy** 资源，在其中定义可接受的 TLS 版本和加密套件。为了将这个云原生的 Policy 应用于 GKE 中的 Kubernetes Gateway 资源，GKE 提供了一个名为 `GCPGatewayPolicy` 的 CRD (Custom Resource Definition)。

`GCPGatewayPolicy` 扮演一个桥梁的角色，它将一个 GCP SSL Policy 关联到一个特定的 Kubernetes Gateway 对象上。

## 操作步骤

整个过程分为两个主要步骤：

### 步骤 1: 在 Google Cloud 中创建 SSL Policy

首先，您需要在 GCP 项目中创建一个 SSL Policy，指定最低 TLS 版本为 1.2。这个操作通常通过 `gcloud` 命令行工具完成。

```bash
# 创建一个名为 my-production-ssl-policy 的 SSL Policy
# --profile MODERN: 使用一组推荐的现代、安全的加密套件
# --min-tls-version 1.2: 设置最低支持的 TLS 版本为 1.2
gcloud compute ssl-policies create my-production-ssl-policy \
    --profile MODERN \
    --min-tls-version 1.2
```

- **`my-production-ssl-policy`**: 这是您在 GCP 中的 SSL Policy 名称，请根据您的命名规范进行修改。
- 这个 Policy 是一个独立于 GKE 的 GCP 资源。

### 步骤 2: 创建并应用 GCPGatewayPolicy Kubernetes 资源

接下来，在您的 GKE 集群中，创建一个 `GCPGatewayPolicy` YAML 文件，将其指向您在步骤 1 中创建的 SSL Policy，并关联到目标 Gateway。

这是您提供的 YAML 示例，经过了具体化处理，使其更易于理解和使用：

**`gcp-gateway-policy.yaml`**
```yaml
apiVersion: networking.gke.io/v1
kind: GCPGatewayPolicy
metadata:
  name: kong-gateway-ssl-policy # 策略对象的名称
  namespace: kong # Gateway 所在的命名空间
spec:
  default:
    # 引用在 GCP 中创建的 SSL Policy 的名称
    sslPolicy: my-production-ssl-policy
  targetRef:
    # 指定此策略要应用到哪个 Gateway 资源上
    group: gateway.networking.k8s.io
    kind: Gateway
    name: kong-gateway-proxy # 目标 Gateway 的名称
```

**关键字段解释:** 

- **`metadata.name` / `metadata.namespace`**: 定义 `GCPGatewayPolicy` 对象本身的位置和名称。
- **`spec.default.sslPolicy`**: **核心字段**。这里填写您在步骤 1 中创建的 GCP SSL Policy 的名称 (`my-production-ssl-policy`)。
- **`spec.targetRef`**: 指定此 `GCPGatewayPolicy` 要附加到哪个 Kubernetes Gateway 资源。请确保 `group`, `kind`, `name` 与您的目标 Gateway 匹配。

最后，使用 `kubectl` 应用此配置：

```bash
kubectl apply -f gcp-gateway-policy.yaml -n kong
```

### 步骤 3: 验证

当您应用 `GCPGatewayPolicy` 后，GKE Gateway 控制器会自动将底层的 Google Cloud 负载均衡器（TargetHttpsProxy）的 SSL Policy 更新为您指定的策略。

您可以通过以下命令来验证：

1.  **查找 GKE 创建的 TargetHttpsProxy:**
    ```bash
    # <GATEWAY_NAME> 是您 Gateway 的名称，例如 kong-gateway-proxy
    gcloud compute target-https-proxies list --filter="name~gke.*-<GATEWAY_NAME>"
    ```

2.  **检查代理上应用的 SSL Policy:**
    ```bash
    # <PROXY_NAME> 是上一步找到的代理全名
    gcloud compute target-https-proxies describe <PROXY_NAME> --format="get(sslPolicy)"
    ```
    如果输出为您 SSL Policy 的完整资源 URL (例如 `.../global/sslPolicies/my-production-ssl-policy`)，则证明配置已成功生效。

## 总结

通过以上步骤，您就成功地为 GKE Gateway 强制实施了 TLS 1.2 的最低版本要求：

1.  **定义标准**: 在 GCP 中创建 `SslPolicy`，设定 TLS 版本和加密套件。
2.  **建立连接**: 在 GKE 中创建 `GCPGatewayPolicy`，通过 `targetRef` 关联到目标 `Gateway`，并通过 `sslPolicy` 字段引用 GCP 的 `SslPolicy`。
3.  **应用生效**: GKE Gateway 控制器自动完成底层负载均衡器的配置更新。

这种方式将基础设施的安全策略（GCP SSL Policy）与应用部署的声明式配置（Kubernetes YAML）优雅地结合在了一起。
