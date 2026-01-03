- lex poc Testing 
- svc hpa-svc-simple.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  annotations:
    cloud.google.com/load-balancer-type: "Internal"
  labels:
    app: sprint-lex-hpa-memroy-cpu-1-0-0
  name: sprint-lex-hpa-memroy-cpu-1-0-0-service
  namespace: namespace
spec:
  ports:
    - port: 8443
      protocol: TCP
      targetPort: 443
  selector:
    app: sprint-lex-hpa-memroy-cpu-1-0-0
  type: ClusterIP
```


- deployment hpa-deployment-simple.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: namespace
  name: sprint-lex-hpa-memroy-cpu-1-0-0-deployment
  labels:
    app: sprint-lex-hpa-memroy-cpu-1-0-0
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sprint-lex-hpa-memroy-cpu-1-0-0
  template:
    metadata:
      labels:
        app: sprint-lex-hpa-memroy-cpu-1-0-0
    spec:
      serviceAccountName: env-region-namespace-sa
      automountServiceAccountToken: false
      imagePullSecrets:
      - name: sprint
      containers:
      - image: my-images
        env:
        #- name: https_proxy
        #  value: "192.168.192.51:443"
        imagePullPolicy: Always
        name: docker-container-hello-node
        resources:
          requests:
            memory: "900Mi"
            cpu: "200m"
          limits:
            memory: "1.5Gi"
            cpu: 1
        ports:
         - containerPort: 443
           protocol: TCP
```
- hpa hpa-hpa-simple.yaml
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: sprint-lex-hpa-memroy-cpu-1-0-0-deployment-hpa
  namespace: namespace
spec:
  minReplicas: 1
  maxReplicas: 2
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
    name: sprint-lex-hpa-memroy-cpu-1-0-0-deployment
```
这段配置是用于自动调整Kubernetes集群中应用程序的Pod数量。具体来说，它是用于调整名为`sprint-lex-hpa-memroy-cpu-1-0-0-deployment`的部署式的Pod数量。这个调整是基于CPU和内存的使用率进行的。

1. `apiVersion`：指定配置文件的版本，这里是`autoscaling/v2`。
2. `kind`：指定资源的类型，这里是`HorizontalPodAutoscaler`。
3. `metadata`：包含了资源的名字、命名空间等信息。
   - `name`：资源的名字，这里是`sprint-lex-hpa-memroy-cpu-1-0-0-deployment-hpa`。
   - `namespace`：资源所在的命名空间，这里是`namespace`。
4. `spec`：包含了自动调整Pod数量的具体配置。
   - `minReplicas`：最少保留的Pod数量，这里是1。
   - `maxReplicas`：最多保留的Pod数量，这里是2。
   - `metrics`：用于调整Pod数量的条件。这里有两个条件，一个是CPU的使用率，另一个是内存的使用率。
     - `resource`：资源类型的名字，这里是`cpu`和`memory`。
     - `target`：用于计算使用率的目标值。这里是平均使用率750和50。
       - `averageUtilization`：计算平均使用率，这里是750和50。
       - `type`：用于计算使用率的方法，这里是`Utilization`。
   - `minReplicas`：最少保留的Pod数量，这里是1。
   - `scaleTargetRef`：用于调整Pod数量的引用。这里是`apps/v1`版本的部署式的`sprint-lex-hpa-memroy-cpu-1-0-0-deployment`。
     - `apiVersion`：引用资源的版本，这里是`apps/v1`。
     - `kind`：引用资源类型，这里是`Deployment`。
     - `name`：引用资源的名称，这里是`sprint-lex-hpa-memroy-cpu-1-0-0-deployment`。

# 为了增加两个 initContainers 至该 Deployment 配置，你需要修改 spec.template.spec 部分，包含两个 initContainers 定义，每个对应一个不同的目的。下面是一个例子，说明如何增加这两个 initContainers
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: namespace
  name: sprint-lex-hpa-memroy-cpu-1-0-0-deployment
  labels:
    app: sprint-lex-hpa-memroy-cpu-1-0-0
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sprint-lex-hpa-memroy-cpu-1-0-0
  template:
    metadata:
      labels:
        app: sprint-lex-hpa-memroy-cpu-1-0-0
    spec:
      serviceAccountName: env-region-namespace-sa
      automountServiceAccountToken: false
      imagePullSecrets:
      - name: sprint
      initContainers:
      - name: appdynamics-agent
        image: appdynamics/agent:latest # 使用你的AppDynamics agent镜像
        resources: # 根据你的需求配置资源
          requests:
            memory: "100Mi"
            cpu: "50m"
          limits:
            memory: "200Mi"
            cpu: "100m"
      - name: custom-script-runner
        image: custom-image-with-script # 使用包含你脚本的定制镜像
        command: ["/bin/sh"] # 假设脚本是shell脚本
        args: ["-c", "路径/你的脚本.sh"] # 提供脚本的路径和文件名
        resources: # 根据你的需求配置资源
          requests:
            memory: "50Mi"
            cpu: "20m"
          limits:
            memory: "100Mi"
            cpu: "50m"
      containers:
      - image: my-images
        env:
        - name: https_proxy
          value: "192.168.192.51:443"
        imagePullPolicy: Always
        name: docker-container-hello-node
        resources:
          requests:
            memory: "900Mi"
            cpu: "200m"
          limits:
            memory: "1.5Gi"
            cpu: 1
        ports:
        - containerPort: 443
          protocol: TCP
```
请注意需要根据你的镜像和脚本修改 appdynamics-agent 和 custom-script-runner 的镜像源 (image 字段) 和启动命令。initContainers 会在主容器启动前按顺序运行。每个 initContainer 必须成功完成，接下来的 initContainer 才会开始运行。如果任何 initContainer 失败，Kubernetes 会重启整个 Pod。这会继续直到所有的 initContainer 都成功完成。
你还需要提供正确的脚本和镜像资源，并确保这些资源和配置符合你的实际需求。不要忘记更新资源请求和限制(resources 字段) 来匹配你真正的用例


- init container 
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: namespace
  name: sprint-lex-hpa-memroy-cpu-1-0-0-deployment
  labels:
    app: sprint-lex-hpa-memroy-cpu-1-0-0
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sprint-lex-hpa-memroy-cpu-1-0-0
  template:
    metadata:
      labels:
        app: sprint-lex-hpa-memroy-cpu-1-0-0
    spec:
      serviceAccountName: env-region-namespace-sa
      automountServiceAccountToken: false
      imagePullSecrets:
      - name: sprint
      containers:
      - image: my-images
        env:
        - name: https_proxy
          value: "192.168.192.51:443"
        - name: http_proxy
          value: "192.168.192.51:443"
        - name: no_proxy
          value: ".sprint.com"
        imagePullPolicy: Always
        name: docker-container-hello-node
        resources:
          requests:
            memory: "900Mi"
            cpu: "200m"
          limits:
            memory: "1.5Gi"
            cpu: 1
        ports:
        - containerPort: 443
          protocol: TCP
      initContainers:
      - name: init-container-1
        image: your-init-container-image-1
        env:
        - name: your-env-name-1
          value: your-env-value-1
        volumeMounts:
        - name: your-volume-name-1
          mountPath: /path/to/mount/your-volume-1
      - name: init-container-2
        image: your-init-container-image-2
        env:
        - name: your-env-name-2
          value: your-env-value-2
        volumeMounts:
        - name: your-volume-name-2
          mountPath: /path/to/mount/your-volume-2

```

结合上面Deployment 给我生成对应的kind: Service 的yaml 其type: ClusterIP还有kind: HorizontalPodAutoscaler的对应配置 apiVersion: autoscaling/v2 要求基于内存和CPU 来hpa
```yaml
apiVersion: v1
kind: Service
metadata:
  name: sprint-lex-hpa-service
  namespace: namespace
spec:
  type: ClusterIP
  selector:
    app: sprint-lex-hpa-memroy-cpu-1-0-0
  ports:
  - port: 443
    targetPort: 443
    protocol: TCP
```

将上述YAML存储到文件service.yaml中，然后使用kubectl apply -f service.yaml命令来创建Service。
HorizontalPodAutoscaler配置

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: sprint-lex-hpa
  namespace: namespace
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sprint-lex-hpa-memroy-cpu-1-0-0-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50 # 假设你希望CPU平均利用率为50%
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80 # 假设你希望内存平均利用率为80%
```

在这个配置中，HorizontalPodAutoscaler（HPA）根据CPU和内存的利用率调整Pod的数量。‘scaleTargetRef’指向你想要自动伸缩的Deployment。minReplicas和maxReplicas分别指定了Pod的最小和最大副本数量。
metrics部分包含两个资源类型：cpu和memory。对于CPU和内存的每一个，你都可以指定averageUtilization，表示平均目标使用率（以百分比表示）。Kubernetes将会自动地增加或减少Pod的数量，以保持平均利用率在设定的目标数值。
将上述的YAML保存到文件hpa.yaml中，然后使用kubectl apply -f hpa.yaml命令来创建HorizontalPodAutoscaler。
请根据你的实际情况对目标使用率等参数进行调整。上述数值只是示例，你需要根据你的应用性能和容量规划需求来定制这些参数
