需求是这样的, 重启GKE里面的pod
- 1 deployment数量是通过hpa来控制的,但是因为不能调整RS的数值,可能会改 UID
- 2 只能通过kubectl scale deployment --replicas 来调整Pod的数量
- 3 需要确定新启动的Pod能够正常工作,或者说health check 正常之后,删除掉原来的旧的Pod .可以根据创建时间来删除
对于以上需求,有什么好的实现方式或者过滤规则,来确保最小话的不中断服务?

- summary
  - HPA 的最小和最大副本数量将与 Deployment 的副本数量相同，这意味着 HPA 将不再调整副本数量
  - scale 到3 的同时修改hpa 的 minReplicas maxReplicas 为相同值,比如3  
  - 一连串状态检测之后着手删除旧的Pod
    - 因为只要是这里删除就会产生中断
    - 不做任何调整的情况下直接删除旧的Pod
    - 这时候会依赖于scale的数量进行拉去新的Pod 以满足 足量的Pod运行
  - 再次修改hpa 的 minReplicas maxReplicas为原始的值,那么scale会自动收缩,此时收缩的这些Pod能够保证是最新的Pod
  - 需要注意replicaSets的值的改变，这个历史记录里面会有很多。参考文章末尾有举例。
  - 仅仅通过kubectl scale deployment命令来调整Pod的数量不会造成replicaSets的UID的改变。
- 

要实现您描述的需求，您可以采取以下步骤：

1. 使用`kubectl scale deployment`命令调整Pod的数量：根据您的需求，使用该命令增加或减少Deployment的副本数量。例如，如果您希望将副本数量增加到3个，可以运行以下命令：`kubectl scale deployment <deployment-name> --replicas=3`。

2. 确认新启动的Pod正常工作：等待新的Pod完成启动并通过健康检查后，可以使用以下命令获取Pod的状态：`kubectl get pods`。检查每个Pod的状态是否为"Running"，并且它们的容器处于"Ready"状态。这可以确保新的Pod已经成功启动并且就绪。

3. 删除旧的Pod：您可以使用以下命令来删除旧的Pod：`kubectl delete pod <pod-name>`。为了按照创建时间来删除Pod，您可以使用`kubectl get pods --sort-by=.metadata.creationTimestamp`命令获取按照创建时间排序的Pod列表，然后选择删除旧的Pod。

可以使用以下命令获取按创建时间排序的 Pod 列表,并选择性删除比较旧的 Pod:
- 获取所有 Pod 的列表,并按照创建时间排序:
- Testing at my Mac 
```
kubectl scale deployment busybox-app --replicas=4 -n lex-ext-kdp
deployment.apps/busybox-app scaled
kubectl get pods --sort-by=.metadata.creationTimestamp -n lex-ext-kdp
NAME                          READY   STATUS              RESTARTS   AGE
busybox-app-cd9f68c69-6p8x4   1/1     Running             0          3m53s
busybox-app-cd9f68c69-s255b   1/1     Running             0          79s
busybox-app-cd9f68c69-x2hzr   0/1     Running             0          18s
busybox-app-cd9f68c69-5l2mk   0/1     ContainerCreating   0          5s
默认排序
kubectl get pods -n lex-ext-kdp
NAME                          READY   STATUS    RESTARTS   AGE
busybox-app-cd9f68c69-5l2mk   1/1     Running   0          66s
busybox-app-cd9f68c69-6p8x4   1/1     Running   0          4m54s
busybox-app-cd9f68c69-s255b   1/1     Running   0          2m20s
busybox-app-cd9f68c69-x2hzr   1/1     Running   0          79s

```
```bash
kubectl get pods --sort-by=.metadata.creationTimestamp
输出示例:
NAME                     READY   STATUS    RESTARTS   AGE
pod1                     1/1     Running   0          1m
pod2                     1/1     Running   0          2m 
pod3                     1/1     Running   0          3m
```
- 查看你想要删除的那些较旧 Pod 的名称:
```bash
kubectl get pods --sort-by=.metadata.creationTimestamp
```
- 删除指定的较旧 Pod:
```bash
kubectl delete pod pod1 pod2 
```
- 再次查看 Pod 列表,可以看到那些较旧的 Pod 已被删除:
```bash 
kubectl get pods --sort-by=.metadata.creationTimestamp
输出示例:
NAME                     READY   STATUS    RESTARTS   AGE  
pod3                     1/1     Running   0          4m  
```
- shell
```
#!/bin/bash

NAMESPACE="lex-ext-kdp"
DEPLOYMENT="busybox-app"
MAX_PODS=3

# 获取Pod的数量
pod_count=$(kubectl get pods -n $NAMESPACE --selector=app=$DEPLOYMENT --no-headers | wc -l)

# 如果Pod的数量大于3，则删除旧的Pod
if [ "$pod_count" -gt "$MAX_PODS" ]; then
  pods_to_delete=$((pod_count - MAX_PODS))
  echo "Deleting $pods_to_delete old pod(s)..."

  # 获取按创建时间排序的Pod列表，并删除旧的Pod
  pods=$(kubectl get pods -n $NAMESPACE --selector=app=$DEPLOYMENT --sort-by=.metadata.creationTimestamp --no-headers | head -n $pods_to_delete | awk '{print $1}')
  for pod in $pods; do
    kubectl delete pod $pod -n $NAMESPACE
  done

  echo "Old pod(s) deleted."
else
  echo "No old pods to delete."
fi
```

要临时禁止 HPA（Horizontal Pod Autoscaler）的调度，您可以更新相关的 HPA 对象，将其副本数量的最小和最大值设置为与当前 Deployment 的副本数量相同。这样，HPA 将不会再调整副本数量。

以下是一种可能的方法来禁止 HPA 的调度：

1. 查找与 Deployment 关联的 HPA 对象：

```shell
kubectl get hpa -n lex-ext-kdp
```

2. 获取与您的 Deployment 相关联的 HPA 的名称，然后更新它们：

```shell
kubectl edit hpa <hpa-name> -n lex-ext-kdp
```

3. 在编辑器中，将 `spec.minReplicas` 和 `spec.maxReplicas` 的值设置为 Deployment 的当前副本数量。这将阻止 HPA 调整副本数量：

```yaml
spec:
  minReplicas: 4 # 设置为与 Deployment 的副本数量相同
  maxReplicas: 4 # 设置为与 Deployment 的副本数量相同
```

4. 保存并关闭编辑器。

现在，HPA 的最小和最大副本数量将与 Deployment 的副本数量相同，这意味着 HPA 将不再调整副本数量。

请注意，这是一种临时禁止 HPA 调度的方法。如果您希望再次启用 HPA，请将 `spec.minReplicas` 和 `spec.maxReplicas` 的值恢复为适当的范围，并保存更新的 HPA 对象。


- 上面这种临时禁止HPA的方式会改变deployment的UID?
```
- 上述临时禁止 HPA 调度的方式不会改变 Deployment 的 UID。Deployment 的 UID 是在创建 Deployment 时分配的唯一标识符，它代表 Deployment 的身份和版本。
临时禁止 HPA 调度的操作涉及的是更新 HPA 对象的配置，而不是 Deployment 对象本身。更新 HPA 对象的配置不会影响 Deployment 的 UID 或其他相关标识符。
因此，您可以放心使用上述方法来临时禁止 HPA 的调度，而不会对 Deployment 的 UUID 产生影响。 Deployment 的 UUID 仍将保持不变，并且您可以随时将 HPA 的配置恢复为原始设置，以便再次启用 HPA 调度。
```
当对 HorizontalPodAutoscaler (HPA) 进行修改时,HPA 的 UID 不会改变。

HPA 的 UID 是由 Kubernetes 在创建 HPA 时生成的,用于唯一标识这个 HPA 对象。无论之后 HPA 有何修改,这个 UID 都会保持不变。

例如,我们创建一个 HPA:

``` bash
kubectl autoscale deployment nginx-deployment --cpu-percent=50 --min=2 --max=10
``` 

输出:
horizontalpodautoscaler.autoscaling/nginx-deployment scaled


看一下这个 HPA 的详细信息:
``` bash
kubectl get hpa nginx-deployment -o yaml
``` 

输出中会包含这个 HPA 的 UID,例如:

``` yaml
apiVersion: autoscaling/v2beta2 
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-deployment
  namespace: default
  ...
  uid: d3b4a7ac-f9d4-11e9-8eb2-42010a8a0064
``` 

此时这个 HPA 的 UID 是 d3b4a7ac-f9d4-11e9-8eb2-42010a8a0064。

现在我们修改这个 HPA,将 --cpu-percent 修改为 70%:

``` bash
kubectl autoscale deployment nginx-deployment --cpu-percent=70 --min=2 --max=10
``` 

再查看 HPA 的 YAML 信息:
``` yaml
apiVersion: autoscaling/v2beta2 
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-deployment
  namespace: default
  ...
  uid: d3b4a7ac-f9d4-11e9-8eb2-42010a8a0064  # UID 保持不变
``` 

可以看到,尽管我们修改了 HPA 的配置,但 HPA 的 UID 仍然保持为 d3b4a7ac-f9d4-11e9-8eb2-42010a8a0064。

所以,总结来说:Kubernetes 生成的 HPA UID 在 HPA 的生命周期中保持不变,无论 HPA 有何修改。HPA UID 用于唯一标识一个 HPA 对象。

## 如果直接修改 Deployment,是不会导致与其关联的 HPA 的 UID 发生变化的。

- HPA 的 UID 是在创建 HPA 时确定的,用于唯一标识这个 HPA 对象。此后,无论 Deployment 还是 HPA 本身发生任何修改,这个 UID 都不会改变。

例如,我们有一个 Deployment 和一个关联的 HPA:

Deployment:
``` yaml
apiVersion: apps/v1 
kind: Deployment
metadata:
  name: nginx-deployment
  ...
spec:
  replicas: 3
``` 

HPA:
``` yaml
apiVersion: autoscaling/v2beta2 
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-deployment
  namespace: default
  uid: d3b4a7ac-f9d4-11e9-8eb2-42010a8a0064 
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-deployment
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
``` 

此时,HPA 的 UID 是 d3b4a7ac-f9d4-11e9-8eb2-42010a8a0064。

现在我们直接编辑 Deployment,将 replicas 从 3 个修改为 5 个:

``` yaml
apiVersion: apps/v1  
kind: Deployment
metadata:
  name: nginx-deployment
  ... 
spec:
  replicas: 5   # 修改 replicas 
``` 

然后查看 HPA 的 YAML,可以看到:

``` yaml
apiVersion: autoscaling/v2beta2 
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-deployment
  namespace: default
  uid: d3b4a7ac-f9d4-11e9-8eb2-42010a8a0064   # UID 未变
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-deployment
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50
``` 

HPA 的 UID 仍然保持不变。

所以,总结来说:直接修改 Deployment 不会引起其关联 HPA 的 UID 变化。HPA 的 UID 在创建后会保持不变,不受 Deployment 或 HPA 自身修改的影响。

但如果删除并重建 Deployment,则会导致关联的 HPA 丢失,新建的 Deployment 需要 创建一个新的 HPA 对象。这种情况下,新的 HPA 的 UID 自然就会发生变化。

重建 Deployment 的常见方式有:

1. 删除 Deployment,然后重新创建:

``` bash
kubectl delete deployment nginx-deployment
kubectl create deployment nginx-deployment --image=nginx
``` 

这种方式会完全删除原有的 Deployment,并创建一个新的 Deployment,关联的 HPA 对象也会丢失,需要重新创建一个新的 HPA。新 HPA 的 UID 会发生变化。

2. 修改 Deployment 的 .spec.template 字段:

``` yaml
apiVersion: apps/v1  
kind: Deployment
metadata:
  name: nginx-deployment
  ... 
spec:
  replicas: 5 
  template:   # 修改模板
    spec:
      containers:
      - name: nginx
        image: nginx:1.17.1   # 镜像版本变化
``` 

这种修改模板的方式也会导致 HPA 丢失,需要重新创建 HPA。新 HPA 的 UID 会变化。

3. 修改 Deployment 其他与 Pod 模板无关的字段,例如:

- .spec.replicas
- .spec.strategy.type
- .spec.progressDeadlineSeconds
- spec.revisionHistoryLimit
- ...

这些修改不会导致 HPA 丢失,HPA 的 UID 也保持不变。

所以,总结来说:

- 删除或修改 Deployment 的 .spec.template 模板字段,都会导致关联的 HPA 对象丢失,需要重新创建 HPA,这时 HPA 的 UID 会发生变化。

- 修改 Deployment 其他与 .spec.template 无关的字段,不会影响关联的 HPA,HPA 的 UID 保持不变。

- 直接修改 Deployment 的 .spec.replicas 也不会导致 HPA UID 的变化,这是因为 HPA 的目标是维持一个期望的 Pod 副本比例,而不是绝对的副本数值。

所以如果要重新创建与 Deployment 关联的 HPA,建议先删除原有的 HPA,然后再修改或重建 Deployment,最后再创建一个新的 HPA 对象。这可以避免 UID 变化导致的一些潜在问题。

- 如果这些 Pod 是由某个控制器(如 Deployment)创建的,控制器会感知到 Pod 的删除,并重新创建 Pod 以达到期望的 Pod 副本数。
所以,以上命令可以很方便地获取 Kubernetes 集群中的 Pod 列表并按创建时间排序,这样我们就可以很轻松地选择删除一些创建时间较早的 Pod。但如果 Pod 是由 Deployment 等控制器创建的,删除 Pod 后,控制器会重新创建 Pod,所以这种情况下删除旧 Pod 的效果不太明显

需要注意的是，删除旧的Pod可能会导致服务中断，因为这些Pod可能还在处理请求。如果您需要确保服务不中断，可以使用逐个替换（rolling update）策略来更新Deployment。逐个替换会逐步替换旧的Pod，以确保在替换过程中仍有足够的Pod来处理流量。

以下是一个使用逐个替换策略的示例命令：
但是这个会改变hpa里面的

```shell
kubectl scale deployment <deployment-name> --replicas=3
kubectl rollout status deployment/<deployment-name> # 等待新Pod就绪
kubectl delete pod <pod-name> # 逐个删除旧Pod，确保新Pod可用
```

通过使用逐个替换策略，您可以确保在Pod替换的过程中保持服务的可用性，避免中断现有流量。



当Deployment缩容到0个Pod时,其服务将不可用,这会导致中断。所以更准确的描述应该是:

1. kubectl delete pod <pod-name>: 这会先删除旧的Pod,然后kubernetes会重新创建一个新的Pod来替代它。这种方式会中断Pod的服务。 

2. kubectl rollout restart deployment <deploy-name>: 这种方式会在删除旧Pod后立即创建新的Pod,可以最大限度减少中断。

3. kubectl edit pod <pod-name>: 这个命令可以编辑Pod的定义,我们可以将pod.spec.containers[*].image设置为当前的镜像版本号。保存后,Kubernetes会重新启动Pod以加载新的镜像。这种方式可以实现零中断重启Pod。

4. kubectl scale deployment <deploy-name> --replicas=0; kubectl scale deployment <deploy-name> --replicas=1: 这两个命令先将Deployment缩容到0个Pod,然后再扩容回1个Pod。这种方式虽然删除了旧的Pod,但由于缩容到0个Pod导致了服务中断,所以不能算作零中断重启。

Kubectl scale 如果是驱逐一个Pod 而且想要驱逐指定的Pod比如比较老的那个 有没有特定的参数或者办法

是的,如果我们想要对Deployment进行缩容并驱逐指定的Pod,Kubernetes提供了一些机制来实现:

1. 使用kubectl scale deployment <deploy-name> --replicas=n --selector="creationTimestamp=<timestamp>"。这个命令会根据Pod的creationTimestamp选择器来驱逐creationTimestamp最早的Pod。所以我们可以选择驱逐较老的Pod。

在Kubernetes中，`kubectl scale`命令不支持根据Pod的creationTimestamp来选择驱逐的Pod。`kubectl scale`命令主要用于调整部署或副本集的副本数量，而不是直接选择要驱逐的Pod。

要根据Pod的creationTimestamp选择并驱逐较老的Pod，你可以使用以下命令组合：
但是这个需要判断删除那一个?

```bash
kubectl get pods --sort-by=.metadata.creationTimestamp -l <label-selector> -o jsonpath='{range .items[0]}{.metadata.name}{end}' | xargs kubectl delete pod
```

在上述命令中，你需要将`<label-selector>`替换为适当的标签选择器，以筛选要驱逐的Pod。该命令会获取具有指定标签的所有Pod，并按照creationTimestamp进行排序。然后，它将选择最早创建的Pod的名称，并使用`kubectl delete pod`命令进行驱逐。

请记住，在实际使用时，你需要根据你的环境和需求进行适当的修改
2. 在Deployment的podTemplatespec中为Pod添加annotaion或label,例如"version":"1"。然后使用kubectl scale deployment <deploy-name> --replicas=n --selector="version != 1"来驱逐version不是1的Pod。这种方式我们可以为不同版本的Pod添加不通的annotaion或label来选择性驱逐。
3. 直接编辑需要缩容的Deployment,在spec下添加spec.selector.matchLabels对Pod进行分类选择。例如:
```yaml
selector:
  matchLabels:
    version: "1"
```  
然后使用kubectl scale deployment <deploy-name> --replicas=n --selector="!version"来驱逐非version为1的Pod。
4. 使用kubectl get pods -l <label>=<value> -o jsonpath='{.items[*].metadata.name}'获取需要驱逐的Pod名称列表。
5. 然后使用kubectl delete pod <pod1> <pod2>...逐个删除Pod。这种方式可以精确选择需要删除的Pod。
6. 编辑需要缩容的Deployment的.spec.template.spec.affinity属性为Pod配置亲和性(Affinity)规则,使新的Pod驱逐老的Pod。例如设置podAntiAffinity为老Pod的拓片(topologyKey)。

所以总的来说,Kubernetes提供了标签选择器(Selector)、注解(Annotation)、API编辑和Affinity等多种手段来实现选择性缩容和驱逐指定的Pod。让我们可以更加精细和可控的管理Deployment中的Pod。

希望这些信息能够帮助您!如果您有任何其他问题,也请随时提出。


对于直接使用`kubectl scale`命令来根据时间戳驱逐指定的Pod，是没有特定的参数或选项的。`kubectl scale`命令主要用于调整部署（Deployment）或副本集（ReplicaSet）的副本数量，并不提供直接根据时间戳来驱逐Pod的功能。

如果你想根据时间戳驱逐Pod，可以使用其他Kubernetes命令和工具结合筛选、排序和删除操作来实现目标。例如，你可以使用`kubectl get pods`命令获取Pod列表，并使用`kubectl delete pod`命令删除特定的Pod。

以下是一个示例命令，用于获取具有特定标签的Pod列表，并根据时间戳选择最旧的Pod进行驱逐：

```bash
kubectl get pods -l <label-selector> --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[0].metadata.name}' | xargs kubectl delete pod
```

请替换`<label-selector>`为适当的标签选择器来筛选要驱逐的Pod。该命令将获取具有指定标签的所有Pod，并按照创建时间戳进行排序。然后，它将选择最旧的Pod的名称，并使用`kubectl delete pod`命令进行驱逐。

请注意，上述命令是一个示例，实际使用时需要根据你的环境和需求进行适当的修改。

The command you provided is correct. It will scale the Deployment with the name `<deploy-name>` to `n` replicas, and only evict Pods that were created before the timestamp `<timestamp>`.

For example, if you want to scale the Deployment `myapp` to 2 replicas, and only evict Pods that were created before the timestamp `2023-06-27T21:57:09Z`, you would use the following command:

```
kubectl scale deployment myapp --replicas=2 --selector="creationTimestamp<2023-06-27T21:57:09Z"
```

This command will evict all Pods in the Deployment that were created before the timestamp `2023-06-27T21:57:09Z`, and then scale the Deployment up to 2 replicas.

Here is a breakdown of the command:

* kubectl scale: This is the command used to scale a Deployment.
* deployment: This is the type of Kubernetes resource that you want to scale.
* myapp: This is the name of the Deployment you want to scale.
* --replicas 2: This is the number of replicas you want to scale the Deployment to.
* --selector="creationTimestamp<2023-06-27T21:57:09Z": This is the selector that specifies the Pods to evict. The selector matches Pods that were created before the timestamp `2023-06-27T21:57:09Z`.

I hope this helps! Let me know if you have any other questions.

如果要根据GKE Pod的age来过滤并删除Pod,可以采取如下步骤:

1. 使用kubectl get pods -o json | jq '.items[] | {"name": .metadata.name, "age": .metadata.creationTimestamp}'命令获取所有Pod的name和creationTimestamp。creationTimestamp是Pod的创建时间,我们可以与当前时间比较来计算Pod的age。

2. 从上一步的输出中过滤出age超过我们设置阈值的Pod。例如设定阈值为1天,过滤命令可以是:

bash
kubectl get pods -o json | 
jq '.items[] | {"name": .metadata.name, "age": .metadata.creationTimestamp} | 
select(.age < "2020-01-01T00:00:00Z")'


这会过滤出creationTimestamp早于2020-01-01的Pod。

3. 获取过滤后的Pod名称列表,命令是:

bash 
kubectl get pods -o json |  
jq '.items[] | {"name": .metadata.name, "age": .metadata.creationTimestamp} |  
select(.age < "2020-01-01T00:00:00Z") | .name'


4. 使用kubectl delete pod <pod-name1> <pod-name2>...删除获取到的Pod名称列表中的Pod。

所以总的来说,主要步骤是:

1) 获取所有Pod的name和creationTimestamp;

2) 设定age阈值,并使用jq过滤器过滤出超过阈值的Pod;

3) 提取过滤后的Pod的name列表; 

4) 使用kubectl delete pod ...删除列表中的Pod。

这个方法可以很方便的基于age过滤和删除Kubernetes中的Pod。如果您对jq过滤器不太熟悉,也可以使用其他语言如Python来实现过滤逻辑。主要思路是获取Pod的创建时间,计算其与当前时间的差值,这样就可以判断Pod的age是否超过我们的设置阈值。

希望这个方法能够帮助您!如果您有任何其他问题,也请随时提出。

要获取具有特定标签的Pod列表,并根据时间戳选择最旧的Pod驱逐,可以采取以下步骤:
1. 使用kubectl get pods -l <label-key>=<label-value> -o json命令获取具有指定标签的所有Pod信息。
例如,要获取标签app=nginx的所有Pod,命令是:
bash
kubectl get pods -l app=nginx -o json
2. 从上一步的输出中,使用jq提取每个Pod的名称和创建时间creationTimestamp。过滤命令是:
bash
kubectl get pods -l app=nginx -o json | 
jq '{name: .metadata.name, timestamp: .metadata.creationTimestamp}'
3. 获取过滤结果中的最早的creationTimestamp,命令是:
```bash
kubectl get pods -l app=nginx -o json | 
jq '{name: .metadata.name, timestamp: .metadata.creationTimestamp} | 
sort_by(.timestamp) | first' 
```
sort_by(.timestamp)会对结果排序,first会选择第一个元素,也就是timestamp最早的Pod。
4. 获取最早的Pod的名称,命令是:
```bash
kubectl get pods -l app=nginx -o json |
jq '{name: .metadata.name, timestamp: .metadata.creationTimestamp} | 
sort_by(.timestamp) | first | .name'
```
5. 使用kubectl delete pod <pod-name>命令删除获取到的最早Pod的名称。

以上步骤可以实现:

1) 根据标签获取指定Pod列表;

2) 提取每个Pod的名称和创建时间;

3) 对结果排序并获取创建时间最早的Pod;

4) 获取最早Pod的名称;  

5) 删除最早的Pod。

这是一个可以基于时间戳选择最旧Pod并驱逐的简单示例。如果您对jq过滤器不太熟悉,也可以使用其他语言如Python来实现该逻辑。主要思路是获取Pod列表并从中选出创建时间最早的Pod进行删除。

希望这个示例能够帮助您!如果您有任何其他问题,也请随时提出。


# roolout 
To rollout a new deployment in Kubernetes, you have a few options:

1. Replace the existing deployment:
This will terminate all existing pods and recreate them with the new config:

kubectl rollout restart deployment/<deployment-name>


2. Rolling update:
This will update pods one by one, ensuring availability during the rollout:

kubectl rollout restart deployment/<deployment-name> --current-replicas=2 --replicas=4


This will scale the deployment to 4 replicas, then update 2 pods at a time until all are running the new config.

3. Rolling replace:
This will replace the pods one by one, in the same way as a rolling update:

kubectl replace --force -f <new-deployment.yaml>


4. Update the deployment config:
Edit the deployment yaml locally, then apply the new config:

kubectl apply -f <new-deployment.yaml> 


Kubernetes will compare the new config and rollout the changes.

The safest and easiest option is generally a rolling replace or update. This ensures:

- Availability - New pods are started before old ones are terminated
- Rolling - The rollout happens incrementally to reduce impact
- Config Atomic - The new config is applied fully and atomically

Hope this helps! Let me know if you have any other questions.
``` bash
[lex-mac]$ kubectl get deployment -n lex-namespace|grep lex
mac-lex-hap-memroy-cpu                          1/1     1            1           38d
[lex-mac]$ kubectl rollout restart deployment/mac-lex-hap-memroy-cpu -n lex-namespace
deployment.apps/mac-lex-hap-memroy-cpu restarted
[lex-mac]$ kubectl get rs -n lex-namespace|grep lex
mac-lex-hap-memroy-cpu-5bbdd6dd55                          0         0         0       12m
mac-lex-hap-memroy-cpu-6f89c6b56c                          0         0         0       38d
mac-lex-hap-memroy-cpu-7d4b675585                          0         0         0       27d
mac-lex-hap-memroy-cpu-7f4f64f6d6                          1         1         1       12s
[lex-mac]$ kubectl get pod -n lex-namespace|grep lex
mac-lex-hap-memroy-cpu-6f89c6b56c-wqdhm                        1/1     Terminating        0                7m56s
mac-lex-hap-memroy-cpu-7f4f64f6d6-znjwd                        1/1     Running            0                23s


$ kubectl get replicaSets mac-lex-hap-memroy-cpu-7f4f64f6d6 -n lex-namespace -o jsonpath='{.metadata.uid}'
093d3479-8f24-4131-abbb-e0f6a3131b5a
``` 

以下是调试 Pod 重启问题以及核对 Deployment 状况的常用步骤和示例：
	1.	检查 Pod 状态
首先列出所有 Pod，确认目标 Pod 的状态和重启次数：

kubectl get pods -n <namespace>

观察输出中的 RESTARTS 列，如果某个 Pod 重启次数较多（如 CrashLoopBackOff），则需进一步调查。

	2.	查看 Pod 详细信息
使用 kubectl describe 命令查看 Pod 的详细状态和事件，关注 Container 的退出状态、错误信息和事件记录：

kubectl describe pod <pod-name> -n <namespace>

在输出中，注意以下信息：
	•	Events：检查是否有 OOMKilled、Probe 失败等记录。
	•	Container Statuses：查看 Last State 信息，了解容器上一次退出的原因。

	3.	检查容器日志
查看当前容器日志，以便确认异常原因：

kubectl logs <pod-name> -n <namespace>

如果容器重启较频繁，可查看上一个容器的日志来获得更多线索：

kubectl logs <pod-name> -n <namespace> --previous


	4.	核查 Deployment 状况
查看 Deployment 的详细描述，确认配置是否正确，同时注意 Deployment 事件中的错误提示：

kubectl describe deployment <deployment-name> -n <namespace>

核查内容包括：
	•	副本数（Replicas）是否满足预期。
	•	镜像版本、资源配置（requests/limits）是否合理。
	•	是否有滚动更新失败或探针配置错误的记录。

	5.	检查探针配置
如果 Pod 配置了 liveness/readiness 探针，确认其配置是否合理。错误的探针配置可能导致容器频繁重启。
	6.	核查资源配置
检查 Deployment 或 Pod 中的资源请求和限制，防止因资源不足（例如内存溢出）导致 OOMKilled。
	7.	检查依赖服务和网络
如果应用依赖外部服务（例如数据库、API 等），请确保这些服务可用且网络连通性正常。网络故障或依赖服务异常也可能引起应用异常退出。

下面给出一个简单的 Mermaid 流程图，总结调试流程：
```mermaid
graph TD;
    A[列出Pod] --> B[describe Pod];
    B --> C[查看事件与Container状态];
    C --> D[检查当前日志];
    D --> E[检查previous日志];
    E --> F[分析错误原因];
    F --> G[describe Deployment];
    G --> H[检查探针配置];
    H --> I[检查资源配置];
    I --> J[确认依赖服务与网络状态];
```
通过以上步骤，你可以逐步定位 Pod 重启的原因，并针对性地修复 Deployment 配置或应用代码问题。

