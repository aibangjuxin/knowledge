# summary question
参考这2个链接
https://kubernetes.github.io/ingress-nginx/deploy/#gce-gke
https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml
我在我的GKE环境里面部署了ingress nginx Controller
现在遇到这样一个问题
比如我的control 在ingress-nginx这个namespace里面
我的服务运行在aibang这个namespace
我的aibang namespace 默认network policy
Deny all ingress and deny all egress
所以对于这种情况我发现ingress nginx Controller请求到我的aibang namespace的对应的Pod IP时会超时
我删除所有Network policy之后解决问题.那么我应该如何调整我的这个network policy ?
以便允许我的ingress nginx Controller和我的aibang namespace之间通讯?

为了在你的GKE环境中允许Ingress Nginx Controller与`aibang`命名空间中的Pod进行通信，你需要调整`aibang`命名空间的Network Policy。以下是一个示例配置，允许来自`ingress-nginx`命名空间的流量进入`aibang`命名空间的Pod。

### 配置步骤

1. **创建Network Policy**：在`aibang`命名空间中创建一个Network Policy，允许来自`ingress-nginx`命名空间的流量。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-nginx
  namespace: aibang
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
```

2. **应用Network Policy**：将上述配置保存为`network-policy.yaml`文件，并使用`kubectl`命令应用该配置。

```sh
kubectl apply -f network-policy.yaml
```

### 解释

- `namespaceSelector`：选择来自`ingress-nginx`命名空间的流量。
- `podSelector`：选择所有Pod（空选择器表示所有Pod）。
- `policyTypes`：指定该策略应用于Ingress流量。

### 验证

应用Network Policy后，验证Ingress Nginx Controller是否能够成功访问`aibang`命名空间中的Pod。你可以通过以下步骤进行验证：

1. **检查Pod的状态**：确保所有Pod都处于运行状态。

```sh
kubectl get pods -n aibang
```

2. **测试连接**：通过访问Ingress资源来测试连接是否成功。

```sh
curl http://<your-ingress-url>
```

如果连接成功，说明Network Policy配置正确。

### 参考资料

- [Kubernetes NetworkPolicy 文档](https://cloud.google.com/kubernetes-engine/docs/how-to/network-policy)[5]
- [Ingress Nginx Controller 配置示例](https://spacelift.io/blog/kubernetes-ingress)[2]

通过上述步骤，你应该能够成功配置Network Policy，以允许Ingress Nginx Controller与`aibang`命名空间中的Pod进行通信。

Citations:
[1] https://github.com/kubernetes/kubernetes/issues/112467
[2] https://spacelift.io/blog/kubernetes-ingress
[3] https://cloud.google.com/kubernetes-engine/docs/concepts/ingress
[4] https://stackoverflow.com/questions/73049535/kubernetes-networkpolicy-allow-egress-only-to-internet-and-allow-ingress-only
[5] https://cloud.google.com/kubernetes-engine/docs/how-to/network-policy
[6] https://docs.nginx.com/nginx-ingress-controller/configuration/policy-resource/
[7] https://blog.searce.com/control-ingress-and-egress-traffic-in-google-kubernetes-engine-gke-using-network-policies-e5c25cbdb60c?gi=ec3b7f2ba95f
[8] https://docs.nginx.com/nginx-ingress-controller/configuration/ingress-resources/basic-configuration/
[9] https://github.com/kubernetes/ingress-nginx/issues/8907
[10] https://groups.google.com/g/kubernetes-users/c/JB4wY96aKGk

根据您提供的信息,看起来简单的Network Policy配置可能还不足以解决问题。这里有几个可能需要考虑的方面:

1. 确保Ingress Controller可以访问aibang命名空间:

在aibang命名空间中创建一个允许来自ingress-nginx命名空间的入站流量的Network Policy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-nginx
  namespace: aibang
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
```

2. 允许aibang命名空间的出站流量:

如果您的默认策略是拒绝所有出站流量,需要添加一个允许出站流量的策略:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress
  namespace: aibang
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - {}
```

3. 检查Ingress Controller的配置:

确保Ingress Controller有权限访问aibang命名空间中的服务。检查Ingress资源的配置是否正确指向了aibang命名空间中的服务。

4. 验证kube-proxy和CoreDNS:

确保kube-proxy和CoreDNS正常工作,因为它们对于服务发现和网络通信至关重要。

5. 检查GKE防火墙规则:

在GKE中,还需要检查是否有防火墙规则阻止了流量。

6. 使用网络诊断工具:

在aibang命名空间中部署一个网络诊断Pod,用于测试网络连接:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: network-test
  namespace: aibang
spec:
  containers:
  - name: network-test
    image: nicolaka/netshoot
    command: ["sleep", "3600"]
```

然后使用这个Pod进行网络测试:

```bash
kubectl exec -it network-test -n aibang -- bash
```

在Pod内部,您可以使用ping、telnet、curl等工具来测试网络连接。

7. 检查日志:

检查Ingress Controller的日志,看是否有任何错误或警告信息:

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

8. 考虑使用Cilium Network Policy:

如果标准的Kubernetes Network Policy不够灵活,可以考虑使用Cilium Network Policy,它提供了更强大的网络策略功能。

通过这些步骤,您应该能够找出问题所在并解决Ingress Controller与aibang命名空间之间的通信问题。如果问题仍然存在,可能需要更深入地分析GKE集群的网络配置。

Citations:
[1] https://stackoverflow.com/questions/54827386/how-to-check-if-network-policy-have-been-applied-to-pod
[2] https://kubernetes.io/docs/concepts/services-networking/network-policies/
[3] https://learn.microsoft.com/en-us/azure/aks/use-network-policies
[4] https://www.suse.com/support/kb/doc/?id=000020041
[5] https://serverfault.com/questions/862308/how-do-i-view-logs-for-my-kubernetes-ingress-controller
[6] https://stackoverflow.com/questions/46467929/accessing-nginx-ingress-controller-error-log
[7] https://docs.nginx.com/nginx-ingress-controller/logging-and-monitoring/logging/
[8] https://stackoverflow.com/questions/55496310/how-to-view-access-logs-for-an-application-deployed-in-gke
[9] https://www.digitalocean.com/community/tutorials/how-to-inspect-kubernetes-networking
[10] https://stackoverflow.com/questions/70195191/how-to-check-the-network-connectivity-of-micro-services-within-eks-cli
[11] https://www.suse.com/support/kb/doc/?id=000020954


# claude3

您遇到的是一个常见的 Kubernetes 网络策略问题。在启用严格的网络策略的同时允许 Ingress Controller 访问服务是一个很好的安全实践。让我们来解决这个问题。

首先，您需要创建一个网络策略，允许来自 ingress-nginx 命名空间的流量进入 aibang 命名空间。这里有一个网络策略的例子：



```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-aibang
  namespace: aibang
spec:
  podSelector: {}  # 应用于 aibang 命名空间中的所有 Pod
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80  # 假设您的服务在 80 端口上运行，根据实际情况调整
    - protocol: TCP
      port: 443  # 如果您使用 HTTPS

```

要应用这个策略，将其保存为 YAML 文件（例如 `allow-ingress-to-aibang.yaml`），然后运行：

```
kubectl apply -f allow-ingress-to-aibang.yaml
```

这个策略允许来自 ingress-nginx 命名空间的所有流量进入 aibang 命名空间中的所有 Pod 的 80 和 443 端口。

如果这还不够，您可能还需要考虑以下几点：

1. 确保 ingress-nginx 命名空间有正确的标签：
   ```
   kubectl label namespace ingress-nginx kubernetes.io/metadata.name=ingress-nginx
   ```

2. 如果您的服务使用不同的端口，请在网络策略中相应调整端口。

3. 如果您使用了自定义的 ServiceAccount 来运行 Ingress Controller，您可能需要基于 ServiceAccount 来允许访问：



```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-sa-to-aibang
  namespace: aibang
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
      podSelector:
        matchLabels:
          app.kubernetes.io/name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443

```

4. 确保 aibang 命名空间中的 Pod 有正确的标签，与您的服务选择器匹配。

5. 检查 kube-proxy 是否正常运行，因为它负责处理服务到 Pod 的流量转发。

6. 如果您使用了 CNI 插件（如 Calico），确保它的配置允许跨命名空间通信。

7. 检查 GKE 集群的网络配置，确保没有其他网络策略或防火墙规则阻止了流量。

如果在应用这些更改后仍然遇到问题，您可以尝试以下调试步骤：

1. 使用 `kubectl describe networkpolicy` 检查网络策略是否正确应用。
2. 使用 `kubectl logs` 检查 Ingress Controller 的日志，查看是否有错误消息。
3. 尝试从 ingress-nginx 命名空间中的一个 Pod 直接访问 aibang 命名空间中的服务，以排除 Ingress Controller 本身的问题。

记住，网络策略是累加的，所以您可能需要调整或删除之前的策略，以确保新策略生效。如果您需要进一步的帮助或有任何疑问，请随时告诉我。



您说得对，我为之前的疏忽道歉。您很敏锐地注意到了这一点。让我纠正这个错误，并提供一个正确的、基于 ServiceAccount 的网络策略示例。

您是对的，之前的例子确实没有涉及 ServiceAccount。让我们创建一个真正基于 ServiceAccount 的网络策略：



```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-serviceaccount-to-aibang
  namespace: aibang
spec:
  podSelector: {}  # 应用于 aibang 命名空间中的所有 Pod
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
      podSelector:
        matchLabels:
          app.kubernetes.io/name: ingress-nginx
    - podSelector: {}
      namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: ingress-nginx
          app.kubernetes.io/component: controller
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443

```

这个网络策略做了以下几点：

1. 它允许来自 `ingress-nginx` 命名空间的流量。
2. 它特别允许带有标签 `app.kubernetes.io/name: ingress-nginx` 和 `app.kubernetes.io/component: controller` 的 Pod 的流量。这些标签通常用于标识 Ingress Nginx Controller 的 Pod。

然而，您说得对，这个策略实际上仍然没有直接使用 ServiceAccount。这是因为 Kubernetes 网络策略目前不直接支持基于 ServiceAccount 的规则。

如果您真的需要基于 ServiceAccount 来控制访问，您可能需要考虑使用更高级的网络策略提供者，比如 Cilium。Cilium 支持基于 Kubernetes ServiceAccount 的网络策略。

如果您使用 Cilium，您可以创建类似这样的策略：



```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "allow-ingress-sa-to-aibang"
  namespace: aibang
spec:
  endpointSelector:
    matchLabels:
      {}  # 应用于 aibang 命名空间中的所有 Pod
  ingress:
  - fromEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: ingress-nginx
        k8s:io.kubernetes.pod.namespace: ingress-nginx
    - fromEntities:
      - serviceAccounts
      matchLabels:
        k8s:serviceaccount.name: ingress-nginx-serviceaccount
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      - port: "443"
        protocol: TCP

```

在这个 Cilium 策略中：

1. 我们允许来自 `ingress-nginx` 命名空间的流量。
2. 我们特别允许使用名为 `ingress-nginx-serviceaccount` 的 ServiceAccount 的 Pod 的流量。

请注意，您需要将 `ingress-nginx-serviceaccount` 替换为您的 Ingress Controller 实际使用的 ServiceAccount 名称。

我为之前的混淆表示歉意，并感谢您指出这一点。这让我能够提供更准确和有用的信息。如果您有任何其他问题或需要进一步澄清，请随时告诉我。


# Chatgpt 
为了使Ingress NGINX Controller能够与`aibang`命名空间内的Pods进行通信，需要创建适当的网络策略来允许从`ingress-nginx`命名空间到`aibang`命名空间的流量。以下是一个示例网络策略，允许从`ingress-nginx`命名空间到`aibang`命名空间的Ingress流量：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-nginx
  namespace: aibang
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
```

这个网络策略的作用如下：
- `podSelector: {}`：选择所有Pods。
- `policyTypes: Ingress`：指定这是一个Ingress策略。
- `from`：允许来自`ingress-nginx`命名空间的流量。

### 详细步骤

1. 确保`ingress-nginx`命名空间有适当的标签，例如果没有，添加一个：
    ```sh
    kubectl label namespace ingress-nginx name=ingress-nginx
    ```

2. 创建网络策略文件，内容如上。

3. 应用网络策略：
    ```sh
    kubectl apply -f allow-ingress-nginx.yaml
    ```

### 验证策略

验证网络策略是否生效可以使用以下步骤：

1. 检查网络策略是否已正确创建：
    ```sh
    kubectl get networkpolicy -n aibang
    ```

2. 尝试通过Ingress访问`aibang`命名空间中的服务，确保流量正常。

### 注意事项

- 确保`ingress-nginx`命名空间内的Ingress Controller Pod运行正常，并且能够解析目标服务。
- 如果`aibang`命名空间还有其他策略或限制，可能需要调整这些策略以允许所需的流量。

通过这些配置，你应该能够允许`ingress-nginx`命名空间与`aibang`命名空间内的Pods正常通信。



# ingress-controller with rt 
要解决您在GKE环境中遇到的问题，即ingress-nginx Controller与运行在`aibang`命名空间下的服务通信时遇到的网络策略限制，您需要在`aibang`命名空间中创建一个网络策略来允许特定的流量。

首先，确保您的ingress-nginx Controller运行在默认或专用的命名空间中，并且没有受到严格的网络策略限制。然后，在`aibang`命名空间中创建一个允许从ingress-nginx Controller所在命名空间的特定服务账户访问的网络策略。

以下是一个示例网络策略配置，允许来自`ingress-nginx`命名空间中的所有Pods对`aibang`命名空间中的Pods进行访问：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-nginx
  namespace: aibang
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
```

如果ingress-nginx Controller有特定的服务账户，可以进一步细化策略如下：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-nginx
  namespace: aibang
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    - podSelector:
        matchLabels:
          app: ingress-nginx-controller
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
```

接下来，为了暴露您的服务并使用主机头、路径等特性，您需要创建一个Ingress资源。下面是一个示例Ingress配置，它将不同主机名和路径映射到不同的服务：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: aibang
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: www.example.com
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: my-service-a
            port:
              number: 80
  - host: www.example.org
    http:
      paths:
      - pathType: Prefix
        path: "/path1"
        backend:
          service:
            name: my-service-b
            port:
              number: 80
```

确保在上述Ingress资源中替换`my-service-a`和`my-service-b`为您的实际服务名称，并根据需要调整端口和路径。这样，您就可以在不破坏现有网络策略的情况下，通过ingress-nginx Controller正确地暴露和路由您的服务。


根据您的描述,我们需要调整网络策略以允许Ingress Nginx Controller与aibang命名空间中的服务进行通信。以下是解决方案和一些示例:

1. 调整网络策略:

在aibang命名空间中创建以下网络策略:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller
  namespace: aibang
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP  
      port: 443
```

这个策略允许来自ingress-nginx命名空间的流量访问aibang命名空间中的所有Pod的80和443端口[1]。

2. 创建Ingress资源示例:

以下是一些创建Ingress资源的示例:

通过主机名路由:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress  
metadata:
  name: myapp-ingress
  namespace: aibang
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-service
            port: 
              number: 80
```

通过路径路由:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: aibang
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - http:
      paths:
      - path: /myapp
        pathType: Prefix
        backend:
          service:
            name: myapp-service
            port: 
              number: 80
```

配置HTTPS:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: aibang
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - myapp.example.com
    secretName: myapp-tls-secret
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-service
            port: 
              number: 443
```

请确保创建相应的TLS密钥,并将其存储在名为myapp-tls-secret的Kubernetes Secret中[1]。

通过这些配置,您应该能够允许Ingress Nginx Controller与aibang命名空间中的服务进行通信,并成功暴露您的HTTPS服务。

Sources
[1] Installation Guide ¶ https://kubernetes.github.io/ingress-nginx/deploy/




I'd be happy to help you with that!

**Network Policy Adjustment**

To allow communication between the Ingress Nginx Controller in the `ingress-nginx` namespace and your Pods in the `aibang` namespace, you need to create a Network Policy that allows ingress traffic from the Ingress Nginx Controller to your Pods.

Here's an example Network Policy that you can create in the `aibang` namespace:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-nginx
spec:
  podSelector:
    matchLabels: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/namespace: ingress-nginx
    - ports:
      - 80
  policyTypes:
  - Ingress
```
This Network Policy allows incoming traffic from the `ingress-nginx` namespace on port 80. You can adjust the `podSelector` and `ingress` rules to fit your specific use case.

**Creating an Ingress Resource**

To expose your HTTPS service using an Ingress resource, you can create a YAML file like this:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aibang-ingress
  namespace: aibang
spec:
  rules:
  - host: aibang.example.com
    http:
      paths:
      - path: /
        backend:
          serviceName: aibang-service
          servicePort: 443
  tls:
  - hosts:
    - aibang.example.com
    secretName: aibang-tls
```
This Ingress resource defines a rule that routes traffic from `aibang.example.com` to the `aibang-service` service in the `aibang` namespace on port 443.

**Example: Exposing a Service using Host Header**

Here's an example of how you can expose a service using a host header:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aibang-ingress
  namespace: aibang
spec:
  rules:
  - host: aibang.example.com
    http:
      paths:
      - path: /
        backend:
          serviceName: aibang-service
          servicePort: 443
```
In this example, the Ingress resource routes traffic from `aibang.example.com` to the `aibang-service` service in the `aibang` namespace on port 443.

**Example: Exposing a Service using Path**

Here's an example of how you can expose a service using a path:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aibang-ingress
  namespace: aibang
spec:
  rules:
  - host: example.com
    http:
      paths:
      - path: /aibang
        backend:
          serviceName: aibang-service
          servicePort: 443
```
In this example, the Ingress resource routes traffic from `example.com/aibang` to the `aibang-service` service in the `aibang` namespace on port 443.

I hope this helps! Let me know if you have any further questions. 😊

Here's an example of how to configure an Ingress resource to route traffic based on both host and path:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aibang-ingress
  namespace: aibang
spec:
  rules:
  - host: aibang.example.com
    http:
      paths:
      - path: /api
        backend:
          serviceName: aibang-api-service
          servicePort: 443
      - path: /web
        backend:
          serviceName: aibang-web-service
          servicePort: 443
  - host: dev.aibang.example.com
    http:
      paths:
      - path: /api
        backend:
          serviceName: aibang-dev-api-service
          servicePort: 443
      - path: /web
        backend:
          serviceName: aibang-dev-web-service
          servicePort: 443
```
In this example, the Ingress resource defines two rules:

1. The first rule routes traffic from `aibang.example.com` to two different services based on the path:
	* Traffic to `/api` is routed to the `aibang-api-service` service on port 443.
	* Traffic to `/web` is routed to the `aibang-web-service` service on port 443.
2. The second rule routes traffic from `dev.aibang.example.com` to two different services based on the path:
	* Traffic to `/api` is routed to the `aibang-dev-api-service` service on port 443.
	* Traffic to `/web` is routed to the `aibang-dev-web-service` service on port 443.

This way, you can configure the Ingress resource to route traffic based on both the host header and the path.

