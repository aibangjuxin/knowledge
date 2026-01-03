# summary 
- same kube-dns deployment
- kube-dns pod annotations added apparmor pod 的annotations多了一部分
- eg.
```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    cni.projectcalico.org/containerID: eb1ff541d1368f6a3b8cb28b4a67f47ee3d653500c278d28a19eb705316309bf
    cni.projectcalico.org/podIP: 192.168.129.104/32
    cni.projectcalico.org/podIPs: 192.168.129.104/32
    components.gke.io/component-name: kubedns
    container.apparmor.security.beta.kubernetes.io/dnsmasq: runtime/default
    container.apparmor.security.beta.kubernetes.io/kubedns: runtime/default
    container.apparmor.security.beta.kubernetes.io/prometheus-to-sd: runtime/default
    container.apparmor.security.beta.kubernetes.io/sidecar: runtime/default
    kubernetes.io/psp: gce.unprivileged-addon
    prometheus.io/port: "10054"
    prometheus.io/scrape: "true"
    scheduler.alpha.kubernetes.io/critical-pod: ""
    seccomp.security.alpha.kubernetes.io/pod: runtime/default
  creationTimestamp: "2023-06-27T09:29:28Z"
```
- 那我如何确认这部分是哪里增加进来的？
- api-versions
```
$ kubectl api-versions | grep admissionregistration
admissionregistration.k8s.io/v1

kubectl get MutatingWebhookConfiguration -A
NAME                                                 WEBHOOKS   AGE
gmp-operator.gmp-system.monitoring.googleapis.com    2          256d
istio-revision-tag-default                           4          136d
istio-sidecar-injector                               1          364d
istio-sidecar-injector-istio-1611                    1          364d
istiod-asm-managed                                   2          136d
pod-ready.config.common-webhooks.networking.gke.io   1          617d
```
- try it edit deployment
- old deployment
```yaml
     32   template:
     33     metadata:
     34       annotations:
     35         components.gke.io/component-name: kubedns
     36         prometheus.io/port: "10054"
     37         prometheus.io/scrape: "true"
     38         scheduler.alpha.kubernetes.io/critical-pod: ""
     39         seccomp.security.alpha.kubernetes.io/pod: runtime/default
     40         apparmor.security.beta.kubernetes.io: "false"
     41       creationTimestamp: null
     42       labels:
     43         k8s-app: kube-dns

     35         components.gke.io/component-name: kubedns
     36         apparmor.security.beta.kubernetes.io/kubedns: unconfined
```
- add securityContext: 
  - 语法错误
```yaml
    108         securityContext:
    109           apparmor.security.beta.kubernetes.io/pod: unconfined
```
- 单独给container增加annotations 
```
     65         image: gke.gcr.io/k8s-dns-kube-dns:1.22.12-gke.0
     66         imagePullPolicy: IfNotPresent
     67         annotations:
     68           container.apparmor.security.beta.kubernetes.io/kubedns: unconfined
```
- psp pod security 
```
kubectl label --overwrite ns $namespace pod-security.kubernetes.io/enforce=baseline
log_def "namespace: $namespace podsecurity label created"
```

- edit pod annotations 
```
[d6666666@8886666666 kube-dns]$ kubectl annotate pod kube-dns-7d44cdb5d5-vtgw6 container.apparmor.security.beta.kubernetes.io/dnsmasq=unconfined -n kube-system
error: --overwrite is false but found the following declared annotation(s): 'container.apparmor.security.beta.kubernetes.io/dnsmasq' already has a value (runtime/default)
[d6666666@8886666666 kube-dns]$ kubectl annotate pod kube-dns-7d44cdb5d5-vtgw6 container.apparmor.security.beta.kubernetes.io/dnsmasq=unconfined -n kube-system --overwrite
The Pod "kube-dns-7d44cdb5d5-vtgw6" is invalid: metadata.annotations[container.apparmor.security.beta.kubernetes.io/dnsmasq]: Forbidden: may not remove or update AppArmor annotations
```
- get gke node info and Version
- kubectl get nodes -o=jsonpath=$'{range .items[*]}{@.metadata.name}: {@.status.nodeInfo.kubeletVersion}\n{end}'
```bash
gke-lex-lex-cluster-36-np-ac8888-67ac-1864b0a0-x3tj: v1.24.12-gke.1000
gke-lex-lex-cluster-36-np-ac8888-67ac-4c9b0362-sgjl: v1.24.12-gke.1000
gke-lex-lex-cluster-36-np-ac8888-67ac-e1281aaf-cgjr: v1.24.12-gke.1000
gke-lex-lex-cluster-36-np-ac8888-67ac-e1281aaf-ksvc: v1.24.12-gke.1000
https://unofficial-kubernetes.readthedocs.io/en/latest/tutorials/clusters/apparmor/
$ kubectl get nodes -o=jsonpath=$'{range .items[*]}{@.metadata.name}: {.status.conditions[?(@.reason=="KubeletReady")].message}\n{end}'
gke-lex-lex-cluster-36-np-ac8888-67ac-1864b0a0-x3tj: kubelet is posting ready status. AppArmor enabled
gke-lex-lex-cluster-36-np-ac8888-67ac-4c9b0362-sgjl: kubelet is posting ready status. AppArmor enabled
gke-lex-lex-cluster-36-np-ac8888-67ac-e1281aaf-cgjr: kubelet is posting ready status. AppArmor enabled
gke-lex-lex-cluster-36-np-ac8888-67ac-e1281aaf-ksvc: kubelet is posting ready status. AppArmor enabled


[d6666666@hkl20111023 ~]$ kubectl get nodes -o=jsonpath=$'{range .items[*]}{@.metadata.name}: {.status.conditions[?(@.reason=="KubeletReady")].message}\n{end}'
gke-dev-hk-cluster-ac3-np-ac8888-2daf-85c7a20a-d0mf: kubelet is posting ready status. AppArmor enabled
gke-dev-hk-cluster-ac3-np-ac8888-2daf-85c7a20a-vqjf: kubelet is posting ready status. AppArmor enabled
gke-dev-hk-cluster-ac3-np-ac8888-2daf-85c7a20a-zm72: kubelet is posting ready status. AppArmor enabled
gke-dev-hk-cluster-ac3-np-ac8888-2daf-d97b7d05-f3nq: kubelet is posting ready status. AppArmor enabled
gke-dev-hk-cluster-ac3-np-ac8888-2daf-d97b7d05-g4hr: kubelet is posting ready status. AppArmor enabled
gke-dev-hk-cluster-ac3-np-ac8888-2daf-d97b7d05-kd2q: kubelet is posting ready status. AppArmor enabled
gke-dev-hk-cluster-ac3-np-ac8888-2daf-fe359d36-4gff: kubelet is posting ready status. AppArmor enabled
```


- get pod annotations 
- kubectl get pod kube-dns-7d44cdb5d5-nzntj -n kube-system -o jsonpath='{.metadata.annotations}'
```json
{"cni.projectcalico.org/containerID":"c961fbe34b0eb7ef9a932e87ba3e15fbe8edfa3a823bc04601b614f9dbab27b6","cni.projectcalico.org/podIP":"192.168.130.204/32","cni.projectcalico.org/podIPs":"192.168.130.204/32","components.gke.io/component-name":"kubedns","container.apparmor.security.beta.kubernetes.io/dnsmasq":"runtime/default","container.apparmor.security.beta.kubernetes.io/kubedns":"runtime/default","container.apparmor.security.beta.kubernetes.io/prometheus-to-sd":"runtime/default","container.apparmor.security.beta.kubernetes.io/sidecar":"runtime/default","kubernetes.io/psp":"gce.unprivileged-addon","prometheus.io/port":"10054","prometheus.io/scrape":"true","scheduler.alpha.kubernetes.io/critical-pod":"","seccomp.security.alpha.kubernetes.io/pod":"runtime/default"}
```
- update annotations 
- 修改注释时收到Forbidden: may not remove or update AppArmor错误，这意味着您没有权限直接修改Pod的AppArmor注释
- kubectl annotate pod kube-dns-7d44cdb5d5-nzntj container.apparmor.security.beta.kubernetes.io/kubedns- -n kube-system
The Pod "kube-dns-7d44cdb5d5-nzntj" is invalid: metadata.annotations[container.apparmor.security.beta.kubernetes.io/kubedns]: Forbidden: may not remove or update AppArmor annotations
- why 
    仅仅在 pod 或 deployment spec 中添加 apparmor.security.beta.kubernetes.io/pod: unconfined 并不一定会完全生效,注入的 apparmor annotation 可能会覆盖此配置。
    这是因为 Kubernetes 中资源的配置优先级顺序为:
    1. PodSecurityPolicy(如果启用)
    2. PodSpec
    3. PodTemplateSpec
    4. DeploymentSpec
    5. Annotations/Labels
    所以如果 PodSecurityPolicy 要求启用 apparmor,仅设置 pod spec 可能无法屏蔽其效果。
    要完全禁用 apparmor annotation,可以:
    1. 确认是否在 GKE 集群上启用了 PodSecurityPolicy。如果启用了,查看其 apparmor 相关规则。
    2. 尝试在 PodSpec、PodTemplateSpec 和 DeploymentSpec 等层级都添加 apparmor.security.beta.kubernetes.io/pod: unconfined 配置。这样可以跳过 annotation 层,达到屏蔽的效果。
    3. 删除 apparmor annotation 本身。但这需要在 GKE 上禁用 PodSecurityPolicy,否则会出现 Forbidden 错误。
    4. 如果 PodSecurityPolicy 无法禁用,可以将其 apparmor 相关规则设置为 privileged 或 unrestricted,从而允许 pod 禁用 apparmor。
    5. 作为最后手段,可以将 kube-dns deployment 迁移到标准 Kubernetes 集群上(禁用 GKE 的 anthos_platform 标签),在集群不强制 apparmor 配置的环境中重新部署。但这会给管理带来一定难度。
    所以,要完全解决 apparmor annotation 带来的问题,最佳方案是:
    1) 确认是否由 PodSecurityPolicy 强制注入;
    2) 尝试在多层级为 pod 配置 apparmor.security.beta.kubernetes.io/pod: unconfined;
    3) 需要的话,调整 PodSecurityPolicy 规则以允许禁用 apparmor;
    4) 作为最后手段,考虑将 deployment 迁移到标准 Kubernetes 集群。
    只有综合采取上述方法,才有可能完全屏蔽 apparmor annotation 的效果。单一方式可能无法完全生效,还需要结合实际环境进行判断和操作
- success 
  - kubectl annotate pod kube-dns-7d44cdb5d5-nzntj container.apparmor.security.beta.kubernetes.io=unconfined -n kube-system
    pod/kube-dns-7d44cdb5d5-nzntj annotated
- compare updated annotation pod 
[d6666666@8886666666 kube-dns]$ kubectl get pod kube-dns-7d44cdb5d5-vtgw6 -n kube-system -o yaml > a
[d6666666@8886666666 kube-dns]$ kubectl annotate pod kube-dns-7d44cdb5d5-vtgw6 container.apparmor.security.beta.kubernetes.io=unconfined -n kube-system
pod/kube-dns-7d44cdb5d5-vtgw6 annotated
[d6666666@8886666666 kube-dns]$ kubectl get pod kube-dns-7d44cdb5d5-vtgw6 -n kube-system -o yaml > b


- 是的,要使用 kubectl 删除 pod 的 annotation,可以使用 kubectl annotate 命令。
具体步骤为:
1. 先检查 pod 当前的 annotation:
bash
kubectl get pod <pod-name> -o jsonpath='{.metadata.annotations}'
这会输出 pod 的所有 annotation 信息。
1. 使用 kubectl annotate 删除指定的 annotation:
bash 
kubectl annotate pod <pod-name> <annotation-key>-
例如要删除 pod 的 apparmor 配置,执行:
bash
kubectl annotate pod <pod-name> container.apparmor.security.beta.kubernetes.io/kubedns- 
1. 再次检查 pod 的 annotation,确认指定的 annotation 已被删除:
bash 
kubectl get pod <pod-name> -o jsonpath='{.metadata.annotations}'
1. pod 的 annotation 更新后,kubelet 会自动重新部署 pod,以应用更改。
所以利用 kubectl annotate 命令,我们可以很容易地删除 pod 上的指定 annotation,实现类似禁用 apparmor 的效果。
另外,kubectl annotate 也支持为资源添加 annotation,格式为:
bash
kubectl annotate <resource> <annotation-key>=<annotation-value>
例如,要为 pod 添加 annotation 来禁用 apparmor,可以执行:
bash
kubectl annotate pod <pod-name> apparmor.security.beta.kubernetes.io=unconfined 
所以 kubectl annotate 既可以添加也可以删除 annotation,是管理 Kubernetes 资源 annotation 的很有用的工具


从你描述的情况来看,这些 apparmor 相关的 annotation 很有可能是由 GKE 自动注入的。
GKE (Google Kubernetes Engine) 会默认为某些系统 pod 启用 apparmor,以提高其安全性。这包括 kube-dns、kube-proxy 等 pod。所以,当在 GKE 上部署 Kubernetes 集群时,这些 pod 会自动获取 apparmor 配置。
要确认 annotation 来源及禁用它们,可以:
1. 检查 GKE 文档,确认它是否会为某些系统 pod 自动启用 apparmor。这可以证实 annotation 的来源。
2. 在 kube-dns pod 的 spec 中添加:
```yaml
securityContext: 
  apparmor.security.beta.kubernetes.io/pod: unconfined
```
这会为 pod 禁用 apparmor,屏蔽 annotation 的效果。
3. 也可以直接在 kube-dns deployment 中的 pod template 中添加上述配置。这会使得所有 kube-dns pod 禁用 apparmor。
4. 检查 kube-dns pod 的事件,很有可能会看到与 apparmor 配置相关的事件,也从侧面证实了 annotation 的自动注入。
5. 如果手动删除 annotation,会出现 Forbidden 的错误,这是因为在 GKE 上,默认会启用 PodSecurityPolicy,限制对 pod 安全配置的更改。
所以,要确定和禁用 kube-dns pod 上的 apparmor annotation,需要:
1) 确认 GKE 会自动为其注入 apparmor 配置;
2) 在 pod 或 deployment 的 spec 中添加 apparmor.security.beta.kubernetes.io/pod: unconfined 以屏蔽 annotation;
3) 理解 GKE 默认会有 PodSecurityPolicy,限制 pod 安全配置的更改,所以手动删除 annotation 会失败。
通过以上步骤,我们可以定位到 annotation 的来源,并采取正确的方法禁用它们



GKE   kube-dns Pod被注入下面这些annotations,那么我如何确认这些annotations是怎么被注入的,我如何来进展这些注入,或者让这些注入不生效.因为仅仅看到我的kube-dns pod有这些annotations但是kube-dns deployment没有问题,,当我手动删除这些 annotations的时候 又提示 Forbidden: may not remove or update AppArmor 下面是注入的信息container.apparmor.security.beta.kubernetes.io/dnsmasq: runtime/default
container.apparmor.security.beta.kubernetes.io/kubedns: runtime/default
container.apparmor.security.beta.kubernetes.io/prometheus-to-sd: runtime/default
container.apparmor.security.beta.kubernetes.io/sidecar: runtime/default

要确认这些注释是如何被注入的，您可以采取以下步骤：

1. 查看您的Kubernetes集群中是否有任何自动化过程或工具正在管理和操作您的kube-dns Pod。这些工具可能会自动向Pod添加注释。例如，如果您使用的是Helm或其他部署工具，它们可能会在部署期间注入这些注释。

2. 检查您的Kubernetes配置文件和部署文件，特别是kube-dns的Deployment文件。确保您没有手动在Deployment文件中指定这些注释。如果您没有在配置文件中找到这些注释，那么很可能是有其他工具或流程在幕后自动注入了它们。

3. 如果您确定没有其他自动化工具或流程在幕后注入这些注释，那么可能是集群中的某个组件或插件在注入这些注释。在这种情况下，您需要查看集群中运行的所有组件和插件，了解它们的功能和配置选项。特别关注与DNS服务和Pod安全性相关的组件。

要解决这些注释的问题或使其不生效，您可以尝试以下方法：

1. 找出注入这些注释的源头并禁用它。这可能需要您仔细检查集群中运行的各个组件和插件，并了解它们的配置和行为。通过禁用特定组件或插件，您可以防止这些注释再次被注入。

2. 如果您确定这些注释是由集群中的某个组件或插件注入的，并且您希望保留该组件或插件的其他功能，但只是想禁用注释，您可以尝试在注释前面添加`!`字符，以使其无效。例如，将`!runtime/default`添加到每个注释的末尾。

3. 如果您无法确定源头或无法禁用注释的注入，您可以尝试使用Kubernetes的准入控制机制（例如，ValidatingAdmissionWebhook）来阻止或修改注释。准入控制允许您在Pod创建或修改之前对其进行自定义验证和操作。

请注意，修改注释可能会对系统的安全性和正确性产生影响，因此在进行任何更改之前，请确保您了解可能的风险并在非生产环境中进行测试。同时，建议您与集群管理员或团队成员合作，以便更好地理解和解决此问题。

当您想要禁用注释时，可以尝试在注释前面添加`!`字符，以使其无效。以下是一个示例：

在注释前面添加`!`字符的示例：
```
container.apparmor.security.beta.kubernetes.io/dnsmasq: !runtime/default
container.apparmor.security.beta.kubernetes.io/kubedns: !runtime/default
container.apparmor.security.beta.kubernetes.io/prometheus-to-sd: !runtime/default
container.apparmor.security.beta.kubernetes.io/sidecar: !runtime/default
```

通过将`!runtime/default`添加到每个注释的末尾，您表达了不使用`runtime/default`这个AppArmor配置。

请注意，这种修改注释的方法仅在特定情况下有效，具体取决于注释的用途和使用方式。确保在进行任何更改之前仔细了解注释的含义，并在非生产环境中进行测试。


这会使用 kubectl annotate 命令删除匹配 app=my-app 标签的资源上的 key1 annotation。
kubectl annotate 命令可以添加、删除资源的 annotation

kubectl annotate -l app=my-app key1-



kubectl delete annotation my-pod key1,key2

You can also use the -l flag to specify a label selector when deleting annotations. For example, to delete the annotation key1 from all pods that have the label app=my-app, you would use the following command:

kubectl delete annotation -l app=my-app key1

`kubectl annotate`命令可以用于添加、删除资源的注释。请允许我为之前的错误造成的困扰道歉。

要添加或删除Pod的注释，您可以使用`kubectl annotate`命令，并通过指定`-`（破折号）来删除注释。以下是示例命令：

添加注释：
```
kubectl annotate pod kube-dns-7d44cdb5d5-nzntj -n kube-system \
  container.apparmor.security.beta.kubernetes.io/kubedns=runtime/default
```

删除注释：
```
kubectl annotate pod kube-dns-7d44cdb5d5-nzntj -n kube-system \
  container.apparmor.security.beta.kubernetes.io/kubedns-
```

请确保使用具有足够权限的用户或服务账户执行此操作。如果您仍然遇到权限问题，请联系您的集群管理员以获取适当的权限。

非常抱歉之前的误导，希望这次能够为您提供正确的解决方案。如有任何进一步的问题，请随时提问。
