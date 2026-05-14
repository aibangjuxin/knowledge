在Kubernetes（K8s）中，部署策略是确保应用程序在升级或更新期间平稳运行的关键。根据业务需求和应用特性，可以选择合适的部署策略来最小化服务中断和影响。以下是一些常见的Kubernetes部署策略：

1. **重建（Recreate）**：
   - 这种策略会先停止旧版本的所有Pods，然后部署新版本的Pods。
   - 适用于对服务中断不敏感的环境，如开发或测试环境。
   - 由于所有旧版本的Pods会同时停止，因此可能会有短暂的服务不可用。

2. **滚动更新（Rolling Update）**：
   - 默认的部署策略，它会逐个替换旧版本的Pods，逐步部署新版本的Pods。
   - 可以通过`maxSurge`和`maxUnavailable`参数来控制更新过程中的Pods数量和不可用Pods的最大比例。
   - 适用于大多数生产环境，可以保持服务的高可用性。

3. **蓝绿部署（Blue/Green）**：
   - 在这种策略中，新版本（绿色环境）与旧版本（蓝色环境）并行运行。
   - 一旦新版本验证通过，流量会从旧版本切换到新版本。
   - 适用于需要最小化部署风险的场景，但需要更多的资源来维护两个版本的应用。

4. **金丝雀部署（Canary）**：
   - 这种策略是将新版本的Pods逐步引入到集群中，并逐渐增加新版本Pods的比例。
   - 允许在不影响所有用户的情况下测试新版本，并在发现问题时快速回滚。
   - 适用于需要逐步验证新版本性能和稳定性的场景。

5. **A/B测试**：
   - 这是一种基于用户或请求的流量分割策略，可以将新版本的应用暴露给一部分用户或请求。
   - 通常需要额外的工具或服务，如Istio、Linkerd等服务网格工具，或者自定义的负载均衡器。
   - 适用于需要基于用户行为或请求特征进行流量控制的场景。

选择合适的部署策略可以帮助你更好地管理Kubernetes集群中的应用更新，确保服务的稳定性和可靠性。在实际操作中，你可能需要结合具体的业务场景和需求，甚至可能需要结合多种策略来达到最佳效果。


在Kubernetes中，执行滚动更新（Rolling Update）是Deployment资源的一个内置特性，它允许你逐步替换旧版本的Pods，以新版本的Pods来更新Deployment，从而实现零停机更新。以下是关于Kubernetes滚动更新配置的一些关键点和步骤：

### 关键配置参数

1. **maxUnavailable**：
   - 这个参数定义了在更新过程中，可以处于不可用状态的最大Pod数量。它可以是一个绝对数字，或者相对于Deployment期望副本数的百分比。
   - 默认值通常为25%，但如果设置为0，则表示不允许任何Pod在更新期间不可用。

2. **maxSurge**：
   - 这个参数定义了在更新过程中，可以超出期望副本数的最大Pod数量。这有助于确保新Pods能够快速替换旧Pods，即使在资源受限的情况下。
   - 默认值通常也为25%，但如果设置为0，则表示在更新期间不允许创建额外的Pods。

### 配置滚动更新

要配置滚动更新，你需要编辑Deployment的YAML文件，并设置`.spec.strategy.rollingUpdate`部分。以下是一个示例YAML配置：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  replicas: 4
  selector:
    matchLabels:
      app: my-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: "1"
      maxUnavailable: "25%"
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-repo/my-app:latest
        ports:
        - containerPort: 80
```

在这个配置中，`maxSurge`设置为1，意味着在更新过程中，可以有一个额外的Pod创建。`maxUnavailable`设置为"25%"，意味着在任何给定时间点，最多可以有部署副本数的25%处于不可用状态。

### 执行滚动更新

一旦你的Deployment配置好，你可以通过以下命令来更新Deployment中的Pods：

```bash
kubectl set image deployment/my-deployment my-app=my-repo/my-app:new-version
```

或者，如果你使用的是YAML文件来更新：

```bash
kubectl apply -f my-deployment-updated.yaml
```

这里，`my-deployment-updated.yaml`是包含新镜像版本的Deployment配置文件。

### 监控滚动更新状态

你可以使用以下命令来检查滚动更新的状态：

```bash
kubectl rollout status deployment/my-deployment
```

这个命令将显示Deployment的当前更新状态，包括更新是否成功，以及是否需要回滚。

### 回滚更新

如果在滚动更新过程中遇到问题，你可以通过以下命令来回滚到之前的版本：

```bash
kubectl rollout undo deployment/my-deployment
```

这将撤销最近的一次更新，并将Deployment回滚到之前稳定的状态。

通过合理配置滚动更新策略，你可以确保应用程序在更新过程中的高可用性和平滑过渡。


https://www.bluematador.com/blog/kubernetes-deployments-rolling-update-configuration
