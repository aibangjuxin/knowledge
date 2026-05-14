# Verify kube-dns working 

# summary

- deployment 的 pod template 中的 containers 也可以添加 annotations。
一个 deployment 的 pod template 部分示例如下:
```yaml
template: 
  metadata:
    annotations:
      deployment.annotations: "true" 
  spec:
    containers:
    - name: nginx
      image: nginx
      ports:
      - containerPort: 80
      annotations:
        container.annotations: "true"  # 添加到 container 中
```
可以看到,我们可以同时为:
- pod template 添加 annotations,键为 deployment.annotations
- container 添加 annotations,键为 container.annotations
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example-pod
spec:
  containers:
    - name: container1
      image: nginx
      annotations:
        container.annotations:
          key1: value1
          key2: value2
    - name: container2
      image: busybox
      annotations:
        container.annotations:
          key3: value3


apiVersion: apps/v1
kind: Deployment 
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx 
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        annotations:
          container.apparmor.security.beta.kubernetes.io/nginx: localhost/nginx-apparmor   # 为 nginx 容器添加 apparmor 注解
          example.com/hello: world  # 自定义的注解键
          example.com/version: 1.0.0   # 容器版本注解
在这个例子中,我们为 deployment 的 nginx 容器添加了以下 annotations:
1. container.apparmor.security.beta.kubernetes.io/nginx: 为容器指定 AppArmor 配置,以增强其安全性。
2. example.com/hello: 一个自定义的 annotation,键为 example.com/hello`,值为 world`。
3. example.com/version: 指定容器的版本号为 1.0.0。
添加这些 annotation 后,每当 deployment 重新创建 pod 时,新创建的 nginx 容器都会包含这些 annotations。
然后,这些 annotation 可以被用于:
- container.apparmor.security.beta.kubernetes.io/nginx 会被 Kubernetes 使用以应用 AppArmor 配置到容器。
- example.com/hello 和 example.com/version 只是自定义的元数据,可以被我们自己的控制器等组件使用,辅助管理容器。
- 也可以在 kubectl describe pod 等地方看到这些 annotation,了解容器的配置信息。
所以这个例子展示了如何给 deployment 的容器添加不同类型的 annotation:
- Kubernetes 本身使用的 annotation,如 apparmor 配置
- 自定义的 annotation,作为元数据或被其他组件使用
```
这些 annotations 会应用到 deployment 创建的所有 pod 和 container 上。
添加到 container 的 annotations 的一些用途:
1. 增加元数据。可以为容器添加描述、版本信息等元数据。
2. Sidecar 注入。一些 sidecar 注入器(例如 Istio)会在 container annotations 中注明被注入的 sidecar 信息。
3. 配置 secretly。一些 secret 可以以 annotations 的形式挂载到 container,被其使用。
4. 定义运行时类。container 的 runtimeClass 可以以 annotation 的形式指定。
5. 自动伸缩。一些容器自动伸缩的实现会根据 container annotations 中的配置进行对应。
6. 资源配额。在 container annotations 中可以定义容器的资源限制以用于资源配额控制。
7. 安全控制。一些安全机制(如 AppArmor)会根据 container annotations 中的配置应用安全配置。
等等。
所以,给 deployment 的 containers 添加 annotations 有以下好处:
1) 可以为容器添加更丰富的元数据,辅助获取容器上下文信息。
2) 启用一些依赖 annotation 配置的 Kubernetes 特性,如 sidecar 注入、secret 挂载等。 
3) 被一些控制器、自动伸缩组件等用作配置信息来管理容器。
4) 开启一些安全特性如 AppArmor 或 seccomp 等来增强容器安全。
通过理解 annotations 的各种用途,我们可以给 deployment 的容器添加更丰富的配置和元数据,实现更强大的管理或增强其安全性。所以 container annotations 是扩展和增强容器功能的一种简单而有效的方式



- kubectl proxy 
- 在 GKE 集群中使用 kubectl proxy,需要:
1. 确保使用的 kubectl 工具已经正确配置了集群的访问信息。这通常意味着:
- kubectl 是在 GKE 集群创建过程中安装的
- 或者,你手动配置了 kubectl config set-context 指向 GKE 集群
2. 启动 proxy。在有集群访问权限的主机上执行:
bash
kubectl proxy
此时,kubectl proxy 会:
- 读取 kubectl 的配置,获取连接到 GKE 集群的访问信息
- 基于该信息,使用 Kubernetes API server 的代理协议和服务账号授权,建立到 API server 的连接 
- 启动一个本地代理,将请求转发到 API server
- 所有通过 http://localhost:8001 发出的请求都会被代理到 Kubernetes API server
3. 通过 http://localhost:8001 访问 API 和服务。例如在浏览器中打开:
- http://localhost:8001/api/v1/pods 查看 pod 列表
- http://localhost:8001/api/v1/services/kubernetes-dashboard/proxy 访问 Dashboard 服务 
- 等等
4. 关闭 proxy。在 proxy 启动的终端输入 Ctrl+C 即可关闭。
所以在 GKE 中使用 kubectl proxy,主要涉及:
1) 确保 kubectl 工具已配置正确的集群访问信息
2) 直接运行 kubectl proxy 命令启动本地代理
3) 通过 http://localhost:8001 访问 Kubernetes API 和服务
4) Ctrl+C 关闭 proxy
实际上,对于使用者来说,kubectl proxy 的工作原理和定义都是透明的。我们只需要简单的启动和关闭命令,即可方便地访问集群资源,这也是该命令的优点所在。
但同时也需要注意,由于绕过了 API server 的授权机制,使用 proxy 仍需谨慎,避免在公网环境中使用或暴露敏感数据接口
如果在 GKE 集群中 pod 无法访问 kube-dns,有几种方法可以验证 kube-dns 是否正常工作:
1. 检查 kube-dns pod 自身的状态:
bash
kubectl get pod -n kube-system -l k8s-app=kube-dns
查看 kube-dns pod 是否都在 Running 和 Ready 状态。如果不是,可以检查其事件和日志以确定故障原因。
2. 访问 kube-dns 服务:
bash 
kubectl run -it --rm --restart=Never dns-tester --env="HOST=KubeDNS" --image=appropriate/dns-utils -- dig kubernetes.default.svc.cluster.local

Server:    10.0.0.10
Address 1: 10.0.0.10 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes.default.svc.cluster.local
Address 1: 10.0.0.1
如果无法解析,可能是 kube-proxy 或 kube-dns 自身的问题。
3. 检查 kube-dns 服务的 endpoints:
bash
kubectl get endpoints kube-dns -n kube-system 
查看 kube-dns 服务的后端 pod 列表是否正确。如果 endpoint 不存在或不正确,可能是 kube-proxy 或 kube-dns 访问不到的问题。
4. 在 pod 中执行 nslookup 命令:
bash
kubectl run -it --rm --restart=Never dns-tester  --image=appropriate/dns-utils -- nslookup kubernetes.default

Server:    10.0.0.10
Address 1: 10.0.0.10 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes.default
Address 1: 10.0.0.1
如果无法解析,同样可能是 kube-dns 或 kube-proxy 的问题。
5. 使用 kubectl proxy 访问 kube-dns 接口:
kubectl proxy
然后在浏览器中访问 http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes.default:dns/proxy/
如果返回 A 记录,说明 kube-dns 仍可工作。
以上方法可以从不同角度验证 kube-dns 的工作状态。如果均失败,则需要进一步排查 kube-dns 或 kube-proxy 组件本身的问题。


要验证GKE中的kube-dns是否正常工作，您可以执行以下步骤：
在 kube-dns 这样的核心 Pod 中，通常无法直接使用 `kubectl exec -it` 命令进行交互式执行。

要验证 kube-dns 的正常工作，可以尝试以下方法：

1. 检查 kube-dns Pod 的状态：
   ```
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   ```
   确保 kube-dns Pod 的状态为 "Running"，并且没有任何错误或异常。

2. 使用 `kubectl logs` 命令查看 kube-dns Pod 的日志：
   ```
   kubectl logs -n kube-system <kube-dns-pod-name>
   ```
   将 `<kube-dns-pod-name>` 替换为 kube-dns Pod 的名称。查看日志以检查是否存在任何错误或异常情况。

3. 在其他 Pod 中执行 DNS 查询以验证 kube-dns 的解析功能：
   ```
   kubectl run -it --rm --restart=Never --image=busybox:1.33 dns-test -- nslookup <domain-name>
   ```
   将 `<domain-name>` 替换为您想要解析的域名。这将在一个临时的 Busybox 容器中执行 DNS 查询，以验证 kube-dns 是否能够成功解析域名。

请注意，由于 kube-dns 是核心组件，通常不允许直接在其中执行 `kubectl exec` 命令进行交互式执行。如果您需要与其他 Pod 进行交互，请选择运行其他 Pod 进行测试，并在该 Pod 中执行相关命令。

再次对之前的错误回答表示抱歉。希望这次提供的信息对您有所帮助。如有任何其他问题，请随时提问。

- tcpdump pod 
要验证 Pod 之间的网络通信是否正常，类似于主机之间的抓包，您可以尝试以下方法：

1. 在源 Pod 中执行网络抓包：您可以在源 Pod 中执行网络抓包工具（如 tcpdump 或 Wireshark），捕获该 Pod 发出的流量，并查看流量是否到达目标 Pod。以下是一个示例命令：
   ```
   kubectl exec -it <source-pod-name> -- tcpdump -i any -w capture.pcap
   ```
   将 `<source-pod-name>` 替换为源 Pod 的名称。该命令将在源 Pod 中启动 tcpdump，并将网络流量捕获到名为 `capture.pcap` 的文件中。您可以稍后将该文件下载到本地，并使用 Wireshark 等工具进行分析。

2. 在目标 Pod 中执行网络抓包：您还可以在目标 Pod 中执行相同的网络抓包命令，以捕获到达目标 Pod 的流量。这将帮助您确认源 Pod 发出的流量是否成功到达目标 Pod。

3. 使用网络诊断工具：Kubernetes 提供了一些网络诊断工具，可以帮助您验证 Pod 之间的网络通信。例如，您可以使用 `kubectl exec` 命令在源 Pod 中执行 `wget` 或 `curl` 命令，向目标 Pod 发起 HTTP 请求，并查看响应。这可以帮助您确认源 Pod 是否能够与目标 Pod 正常通信。

请注意，使用网络抓包工具或进行网络诊断可能会对集群性能产生一定影响。因此，请在需要时进行有限的抓包操作，并在测试完成后删除相关工具和文件。

同时，还建议检查网络策略（Network Policies）是否适当配置，并确保没有其他网络层面的限制阻止了 Pod 之间的通信。

最后，对于生产环境中的网络问题，建议与您的网络团队或集群管理员合作，以确保正确的网络配置和故障排除。



几个步骤可以验证GKE中的kube-dns是否工作正常:
要验证Google Cloud Platform (GCP) 中 Google Kubernetes Engine (GKE) 中的 kube-dns 是否正常工作，可以执行以下步骤：

确认 kube-dns 是否正在运行。在 GKE 中，kube-dns 通常作为一个 Kubernetes Deployment 运行，可以使用以下命令检查其运行状态：
- deployment
```bash
kubectl get deployments --namespace=kube-system
```
如果 kube-dns 的 Deployment 状态为“Running”且副本数符合预期，则 kube-dns 正在运行。
确认 kube-dns 是否正在监听 Kubernetes 集群中的 DNS 请求。在 GKE 中，kube-dns 通常作为一个 Kubernetes Service 运行，可以使用以下命令检查其服务状态：
- services
```bash
kubectl get services --namespace=kube-system
```
- login pod execute nslookup
如果 kube-dns 的服务状态为“ClusterIP”，并且它在端口 53 上侦听，则 kube-dns 正在监听 DNS 请求。
在 Kubernetes Pod 中测试 DNS 解析。您可以在一个正在运行的 Kubernetes Pod 中执行以下命令来测试 DNS 解析：
kubectl exec <pod-name> -- nslookup <service-name>
```
在此命令中，`<pod-name>` 是正在运行的 Pod 的名称，`<service-name>` 是要解析的服务的名称。如果该服务的 IP 地址成功解析，则 kube-dns 正常工作。

在 Kubernetes 集群中测试 DNS 解析。您可以在 Kubernetes 集群中的任何 Pod 中执行以下命令来测试 DNS 解析：

kubectl run -it --rm --restart=Never busybox --image=busybox:1.28 -- nslookup <service-name>
```
在此命令中，`<service-name>` 是要解析的服务的名称。如果该服务的 IP 地址成功解析，则 kube-dns 正常工作。


kubectl exec kube-dns-7d44cdb5d5-fclcn -n kube-system -- nslookup cp.domain


首先查看kube-dns Pod是否已成功启动:
kubectl get pods -n kube-system -l k8s-app=kube-dns

如果kube-dns Pod的状态都是Running,说明kube-dns已经启动。

接下来使用一个测试Pod查看域名解析是否正常:

curl -kv https://dev
apiVersion: v1
kind: Pod 
metadata:
  name: dns-test  
  namespace: default
spec:
  containers:
  - name: dnsutils   
    image: gcr.io/kubernetes-e2e-test-images/dnsutils:1.3      
    command:
      - sleep
      - "3600"  
    imagePullPolicy: IfNotPresent


部署该Pod,然后进入Pod执行 nslookup 和 dig 命令测试域名解析。

最后,部署一个使用域名访问Service的应用,验证Service能否被发现。

https://console.cloud.google.com/gcr/images/kubernetes-e2e-test-images/GLOBAL/dnsutils:1.3/details?tab=vulnz
docker pull gcr.io/kubernetes-e2e-test-images/dnsutils:1.3

docker pull gcr.io/kubernetes-e2e-test-images/dnsutils:1.3

https://console.cloud.google.com/gcr/images/kubernetes-e2e-test-images/global


Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  36s                default-scheduler  Successfully assigned default/dns-test to gke-pdev-hk-cluster-36-np-36ba96-67ac-e1281aaf-cgjr
  Normal   Pulling    22s (x2 over 35s)  kubelet            Pulling image "gcr.io/kubernetes-e2e-test-images/dnsutils:1.3"
  Warning  Failed     21s (x2 over 35s)  kubelet            Failed to pull image "gcr.io/kubernetes-e2e-test-images/dnsutils:1.3": rpc error: code = Unknown desc = failed to pull and unpack image "gcr.io/kubernetes-e2e-test-images/dnsutils:1.3": failed to resolve reference "gcr.io/kubernetes-e2e-test-images/dnsutils:1.3": failed to authorize: failed to fetch oauth token: unexpected status: 403 Forbidden
  Warning  Failed     21s (x2 over 35s)  kubelet            Error: ErrImagePull
  Normal   BackOff    10s (x3 over 35s)  kubelet            Back-off pulling image "gcr.io/kubernetes-e2e-test-images/dnsutils:1.3"


部署该Pod,然后进入Pod执行 nslookup 和 dig 命令测试域名解析。

最后,部署一个使用域名访问Service的应用,验证Service能否被发现。
如果上面这些测试都可以通过,说明kube-dns已经正常工作,可以为Pod提供DNS服务和服务发现功能。

除此之外,还可以检查相关Pod的Events和Logs,定位任何potencial的问题。

总的来说,最关键的还是验证Pod是否可以正常通过kube-dns来访问Service。如果可以,则说明一切正常


kubectl deployment.yaml的时候指定DNS？

在 Kubernetes 中，您可以通过在 Deployment YAML 文件中指定 Pod 的 dnsConfig 来配置 Pod 的 DNS 配置。您可以在 Deployment YAML 文件中添加以下内容来指定 Pod 的 DNS 配置：
spec:
  template:
    spec:
      dnsConfig:
        nameservers:
          - <nameserver-1>
          - <nameserver-2>
        searches:
          - <search-domain-1>
          - <search-domain-2>

在这个 YAML 文件中，nameservers 字段指定 DNS 服务器的 IP 地址列表，searches 字段指定 DNS 搜索域的列表。您可以将这些字段添加到您的 Deployment YAML 文件中，例如：

apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      dnsConfig:
        nameservers:
        - 8.8.8.8
        searches:
        - mydomain.com
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80


在上面的例子中，我们指定了一个 DNS 服务器地址为 8.8.8.8，搜索域为 mydomain.com。这将覆盖 Pod 中默认的 DNS 配置。

一旦您将 dnsConfig 字段添加到您的 Deployment YAML 文件中，您可以使用 kubectl apply 命令来应用更改，并更新 Pod 的 DNS 配置。例如：
kubectl apply -f deployment.yaml

请注意，您需要在 Pod 所在的节点上配置正确的 DNS 服务器和搜索域，以便 Pod 能够正确解析域名
```
