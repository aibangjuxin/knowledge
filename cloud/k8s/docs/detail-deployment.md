
```
# summary 
如何理解deployment的一些字段
- deployment name
```
[lex-mac]$ kubectl get deployment -n lex-namespace|grep lex
mac-lex-hap-memroy-cpu                          1/1     1            1           38d
[lex-mac]$ kubectl rollout restart deployment/mac-lex-hap-memroy-cpu -n lex-namespace
deployment.apps/mac-lex-hap-memroy-cpu restarted
```
- get rs replicaSets
```
[lex-mac]$ kubectl get rs -n lex-namespace|grep lex
mac-lex-hap-memroy-cpu-5bbdd6dd55                          0         0         0       12m
mac-lex-hap-memroy-cpu-6f89c6b56c                          0         0         0       38d
mac-lex-hap-memroy-cpu-7d4b675585                          0         0         0       27d
mac-lex-hap-memroy-cpu-7f4f64f6d6                          1         1         1       12s
[lex-mac]$ kubectl get pod -n lex-namespace|grep lex
mac-lex-hap-memroy-cpu-6f89c6b56c-wqdhm                        1/1     Terminating        0                7m56s
mac-lex-hap-memroy-cpu-7f4f64f6d6-znjwd                        1/1     Running            0                23s
```
- get replicaSets uid
$ kubectl get replicaSets mac-lex-hap-memroy-cpu-7f4f64f6d6 -n lex-namespace -o jsonpath='{.metadata.uid}'
093d3479-8f24-4131-abbb-e0f6a3131b5a

- hpa-yaml
```yaml
$ cat ./topo/podautoscaler/hpa-test.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: sprint-lex-hap-memroy-cpu-hpa
  namespace: teamsnamespace
spec:
  minReplicas: 1
  maxReplicas: 4
  metrics:
  - resource:

      name: cpu
      target:
        averageUtilization: 750
        type: Utilization
    type: Resource
  - resource:
      name: memory
      target:
        averageUtilization: 50
        type: Utilization
    type: Resource
  minReplicas: 1
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sprint-lex-hap-memroy-cpu

apiVersion: autoscaling/v2 # 指定使用的Kubernetes Autoscaling API版本为autoscaling/v2
kind: HorizontalPodAutoscaler # 表示这是一个HorizontalPodAutoscaler对象，用于自动调整Pod的副本数
metadata:
  name: sprint-lex-hap-memroy-cpu-hpa # 定义HPA的名称为sprint-lex-hap-memroy-cpu-hpa
  namespace: teamsnamespace # 指定HPA所属的命名空间为teamsnamespace
spec:
  minReplicas: 1 # HPA允许的最小副本数为1
  maxReplicas: 4 # HPA允许的最大副本数为4
  metrics:
  - type: Resource # 指定指标类型为资源指标
    resource:
      name: cpu # 资源指标的名称为CPU
      target:
        type: Utilization # 指定目标类型为利用率
        averageUtilization: 750 # 目标平均CPU利用率为750%
  - type: Resource # 指定指标类型为资源指标
    resource:
      name: memory # 资源指标的名称为内存
      target:
        type: Utilization # 指定目标类型为利用率
        averageUtilization: 50 # 目标平均内存利用率为50%
  scaleTargetRef:
    apiVersion: apps/v1 # 目标对象的API版本为apps/v1
    kind: Deployment # 目标对象的类型为Deployment
    name: sprint-lex-hap-memroy-cpu # 目标对象的名称为sprint-lex-hap-memroy-cpu
**Explanation of Deploy Configuration:**
```markdown
**Explanation of Deploy Configuration:**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: sprint-lex-hap-memroy-cpu-hpa
  namespace: teamsnamespace
spec:
  minReplicas: 1
  maxReplicas: 4
  metrics:
  - resource:
      name: cpu
      target:
        averageUtilization: 750
        type: Utilization
    type: Resource
  - resource:
      name: memory
      target:
        averageUtilization: 50
        type: Utilization
    type: Resource
  minReplicas: 1
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sprint-lex-hap-memroy-cpu
```

- **apiVersion:** Specifies the version of the API being used (autoscaling/v2).

- **kind:** Defines the type of resource being created (HorizontalPodAutoscaler).

- **metadata:** Contains information about the resource, such as its name and namespace.

- **name:** The name of the HorizontalPodAutoscaler resource (sprint-lex-hap-memroy-cpu-hpa).

- **namespace:** Specifies the namespace in which the resource should be created (teamsnamespace).

- **spec:** Describes the desired state of the HorizontalPodAutoscaler.

  - **minReplicas:** Minimum number of replicas that should be maintained (1).

  - **maxReplicas:** Maximum number of replicas that the autoscaler can scale up to (4).

  - **metrics:** Specifies the metrics used for autoscaling.

    - **resource:** Indicates the type of metric being used.

      - **name:** The name of the resource being measured (cpu or memory).

      - **target:** Specifies the target value for the metric.

        - **averageUtilization:** The target utilization percentage.

        - **type:** Indicates the type of target utilization (Utilization).

      - **type:** Indicates the type of metric (Resource).

  - **scaleTargetRef:** Specifies the target resource for scaling (Deployment).

    - **apiVersion:** The API version of the target resource (apps/v1).

    - **kind:** The kind of the target resource (Deployment).

    - **name:** The name of the target Deployment (sprint-lex-hap-memroy-cpu).
```

```
- deployment labels
```
$ kubectl get deployment -n teamsnamespace --show-labels|grep lex
sprint-lex-hap-memroy-cpu                          1/1     1            1           2m     194f867a2=enabled,app=nginx,type=pa
```
- deployment pod labels
```

 kubectl get pod -n teamsnamespace --show-labels|grep lex
sprint-lex-hap-memroy-cpu-7fd6d9f55b-lzvz5                        1/1     Running            0                81s    194f867a2=enabled,app=nginx,pod-template-hash=7fd6d9f55b,team=lex,type=pa
```
- attempt patch deployment
kubectl patch deployment sprint-lex-hap-memroy-cpu --patch '{"spec": {"selector": {"matchLabels": {"194f867a2": "enabled"}}}}' -n teamsnamespace
- Detail explain
```
kind: Deployment # 表示这是一个Deployment对象，用于定义应用程序的部署
metadata:
  namespace: teamsnamespace # 指定部署所在的命名空间为teamsnamespace
  name: sprint-lex-hap-memroy-cpu # 指定部署的名称为sprint-lex-hap-memroy-cpu
  labels:
    194f867a2: enabled # 定义部署的标签，标签名为194f867a2，值为enabled
    app: nginx # 定义部署的应用标签，标签名为app，值为nginx
    type: pa # 定义部署的类型标签，标签名为type，值为pa
spec:
  replicas: 2 # 定义部署的副本数为2，即同时运行的Pod实例数量为2
  selector: # 定义标签选择器，用于选择要管理的Pod
    matchLabels:
      194f867a2: enabled # 标签选择器的条件，要求Pod的标签中必须包含194f867a2=enabled
      team: lex # 标签选择器的条件，要求Pod的标签中必须包含team=lex
  template: # 定义创建Pod的模板
    metadata:
      labels:
        194f867a2: enabled # Pod的标签，标签名为194f867a2，值为enabled
        app: nginx # Pod的标签，标签名为app，值为nginx
        type: pa # Pod的标签，标签名为type，值为pa
        team: lex # Pod的标签，标签名为team，值为lex
    spec: # 定义Pod的规范
      serviceAccountName: lex-teamsnamespace-sa # 指定Pod使用的Service Account名称为lex-teamsnamespace-sa
      automountServiceAccountToken: false # 禁用自动挂载Service Account Token
      imagePullSecrets: # 定义从私有容器镜像仓库拉取镜像所需的认证信息
      - name: sprint # 私有镜像仓库的认证信息名称为sprint
      containers: # 定义Pod中的容器
      - image: eu.gcr.io/company/lex-api-podsdata-collector:1.0.1 # 容器的镜像地址
        env: # 定义容器的环境变量
        #- name: https_proxy
        #  value: "192.168.192.51:443"
        imagePullPolicy: Always # 定义容器镜像拉取策略为始终拉取
        name: docker-container-hello-node # 容器的名称为docker-container-hello-node
        resources: # 定义容器的资源限制和请求
          requests: # 定义容器的资源请求
            memory: "900Mi" # 定义内存请求为900Mi
            cpu: "200m" # 定义CPU请求为200m
            ephemeral-storage: "2Gi" # 定义临时存


apiVersion: apps/v1 # 指定了使用的Kubernetes API版本
kind: Deployment #表示这是一个Deployment对象
metadata: # 包含有关Deployment的元数据，如命名空间、名称和标签。
  namespace: teamsnamespace # 指定了部署所属的命名空间
  name: sprint-lex-hap-memroy-cpu # 定义了Deployment的名称。
  labels: # 配置了一些标签来标识Deployment，其中194f867a2: enabled是一个标签，而app: nginx和type: pa是其他用于分类和识别Deployment的标签。
    194f867a2: enabled # 这里定义的是deployment的标签
    app: nginx
    type: pa
spec:
  replicas: 2 #副本(replicas) 指定了Deployment的副本数，即在集群中运行的Pod的数量
  selector: #设置标签选择器，用于选择与其匹配的Pod
    matchLabels: # 通过标签选择器，选择具有相应标签的Pod，这里使用了194f867a2: enabled和team: lex两个标签作为选择条件。
      194f867a2: enabled  # 这里定义的标签必须要在template==>  metadata ==> labels 定义 标签选择器,用于选择Pod
      team: lex
  template: #定义了要创建的Pod的模板。
    metadata: # 包含了Pod的元数据，包括标签等
      labels: # 设置了Pod的标签，其中包括了194f867a2: enabled、app: nginx、type: pa和team: lex等标签，这些标签与前面的选择器匹配。
        194f867a2: enabled # 这里其实是Pod的标签 Pod模板的标签
        app: nginx
        type: pa
        team: lex # 这里必须定义了 上面selector上面那个地方才能调用 
    spec: # 定义了创建Pod的规范。
      serviceAccountName: lex-teamsnamespace-sa #: 指定了Pod要使用的服务账号的名称。
      automountServiceAccountToken: false # 禁止Pod自动挂载服务账号的令牌
      imagePullSecrets: # 设置镜像拉取的密钥 这里使用了名为sprint的密钥
      - name: sprint
      containers: # 定义了Pod中的容器
      - image: eu.gcr.io/company/lex-api-podsdata-collector:1.0.1 # 设置了容器使用的镜像
        env: 可选的环境变量配置，这里是注释掉的示例
        #- name: https_proxy
        #  value: "192.168.192.51:443"
        imagePullPolicy: Always #  配置了容器的镜像拉取策略为始终拉取最新的镜像。
        name: docker-container-hello-node # 定义了容器的名称。
        resources: # 配置了容器的资源请求和限制。
          requests: # 定义了容器的资源请求，包括内存、CPU和临时存储的要求。
            memory: "900Mi"
            cpu: "200m"
            ephemeral-storage: "2Gi"
          limits:
            memory: "1.5Gi"
            cpu: 1
            ephemeral-storage: "4Gi"
        ports:
         - containerPort: 443
           protocol: TCP
      volumes:
        - name: ephemeral
          emptyDir:
            sizeLimit: 1000M
```
- kubectl patch 
```
[lex-mac]$ kubectl patch deployment sprint-lex-hap-memroy-cpu --patch '{"spec": {"selector": {"matchLabels": {"194f867a2": "enabled"}}}}' -n teamsnamespace
deployment.apps/sprint-lex-hap-memroy-cpu patched (no change)
[lex-mac]$ kubectl patch deployment sprint-lex-hap-memroy-cpu --patch '{"spec": {"selector": {"matchLabels": {"team": "lex"}}}}' -n teamsnamespace
deployment.apps/sprint-lex-hap-memroy-cpu patched (no change)
[lex-mac]$ kubectl patch deployment sprint-lex-hap-memroy-cpu --patch '{"spec": {"selector": {"matchLabels": {"team": "lex2"}}}}' -n teamsnamespace
The Deployment "sprint-lex-hap-memroy-cpu" is invalid:
* spec.template.metadata.labels: Invalid value: map[string]string{"194f867a2":"enabled", "app":"nginx", "team":"lex", "type":"pa"}: `selector` does not match template `labels`
* spec.selector: Invalid value: v1.LabelSelector{MatchLabels:map[string]string{"194f867a2":"enabled", "team":"lex2"}, MatchExpressions:[]v1.LabelSelectorRequirement(nil)}: field is immutable
这个报错 是 selector` does not match template `labels` 表面的命令是是针对的selector 看样子是针对的spec.template.metadata.labels ?
```
- 对应关系能找到 也是OK的 但是好像更新都不行 随意改值没什么用 ?对于有些字段来说确实如此
```
kubectl patch deployment sprint-lex-hap-memroy-cpu --patch '{"spec": {"selector": {"matchLabels": {"team": "lex"}}}}' -n teamsnamespace OK 
kubectl patch deployment sprint-lex-hap-memroy-cpu --patch '{"spec": {"template": {"metadata": {"labels": {"team": "lex"}}}}}' -n teamsnamespace OK 
deployment.apps/sprint-lex-hap-memroy-cpu patched (no change)

kubectl patch deployment patch-demo --patch '{"spec": {"template": {"spec": {"containers": [{"name": "patch-demo-ctr-2","image": "redis"}]}}}}'

kubectl patch deployment sprint-lex-hap-memroy-cpu --patch '{"spec": {"template": {"metadata": {"team": "lex2"}}}}' -n teamsnamespace


kubectl patch deployment sprint-lex-hap-memroy-cpu --patch '{"spec": {"template": {"matchLabels": {"team": "lex2"}}}}' -n teamsnamespace


kubectl get hpa sprint-lex-hap-memroy-cpu-hpa -n teamsnamespace
NAME                            REFERENCE                              TARGETS           MINPODS   MAXPODS   REPLICAS   AGE
sprint-lex-hap-memroy-cpu-hpa   Deployment/sprint-lex-hap-memroy-cpu   5%/50%, 1%/750%   1         4         1          39d
```

```
