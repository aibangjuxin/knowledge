如果你希望在 Kubernetes 中的 Deployment 启动时不使用 Istio 代理，你可以通过在 Deployment 的 Pod 模板中添加注释来实现。这个注释告诉 Istio 不要自动注入 Istio 代理。

在你的 Deployment YAML 文件中，可以添加以下注释：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  template:
    metadata:
      annotations:
        sidecar.istio.io/inject: "false" # 关闭 Istio 代理注入
    spec:
      containers:
      - name: my-container
        image: my-image
        # ... 其他容器配置 ...
```

在上述示例中，我们在 Pod 模板的 `metadata` 下添加了一个注释 `sidecar.istio.io/inject: "false"`，这告诉 Istio 不要自动注入 Istio 代理到这个 Pod 中。这将确保该容器在启动时不使用 Istio 代理。

请确保将上述注释添加到你的 Deployment YAML 文件中，并根据你的实际需要进行配置。这样，你的容器将在启动时不使用 Istio。

在使用 Istio 代理的情况下，确保 Liveness 和 Readiness 探针能够正确配置是很重要的。

当你使用 Istio 时，Istio 代理（sidecar）会截取容器的所有网络流量，包括 Liveness 和 Readiness 探针的流量。因此，确保这些探针能够正确访问是关键的。

一般来说，你需要确保以下事项：

1. **Liveness 探针**：如果你的容器定义了 Liveness 探针，确保 Istio 代理的 Envoy 配置允许访问该探针的路径。通常，默认情况下，Istio 应该允许访问 `/healthz` 路径，但你需要确保你的 Liveness 探针在此路径上提供响应。如果你的 Liveness 探针使用不同的路径，你需要相应地配置 Istio。

2. **Readiness 探针**：类似于 Liveness 探针，确保 Istio 代理的 Envoy 配置允许访问 Readiness 探针的路径。通常，默认情况下，Istio 应该允许访问 `/healthz/ready` 路径。确保你的 Readiness 探针在此路径上提供响应。

如果你的 Liveness 和 Readiness 探针没有特殊配置，通常只需确保 Istio 代理允许访问默认路径，即 `/healthz` 和 `/healthz/ready`，即可正常工作。

但如果你有特殊需求或自定义的探针路径，确保你的 Istio 配置与之匹配，以确保 Liveness 和 Readiness 探针能够正确工作。此外，还需要确保容器内的服务实际上在这些路径上提供正确的健康检查响应。
