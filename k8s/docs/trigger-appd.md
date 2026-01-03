# summary
使用Pod的亲和性（Affinity）和反亲和性（Anti-Affinity）来确保每个Node上只运行一个Pod
- 1. get node number . and the node number is the replicas number.
- 2. create a deployment with replicas number.
- 3. kubectl apply -f deploymen.yaml
- 4. wait the deployment is running.
- 5. get the pod name. using kubectl get pods -o wide. and output the node name.
- 6. delete the deployment.


```bash
#!/bin/bash

# Step 1: Get node number (replicas number)
replicas=$(kubectl get nodes --no-headers | wc -l)

# Step 2: Create a deployment with replicas number
cat <<EOF > temp-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-deployment
spec:
  replicas: $replicas
  selector:
    matchLabels:
      app: your-app
  template:
    metadata:
      labels:
        app: your-app
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - your-app
            topologyKey: "kubernetes.io/hostname"
      #nodeSelector:
      #  your-node-label-key: your-node-label-value
      initContainers:
        - name: appd-init-service
          image: docker.io/appdynamics/java-agent:20.8.0 
          imagePullPolicy: Always
          command: ["sh", "-c", "cp -r /opt/appdynamics/. /opt/appdynamics-java"]
      containers:
        - name: your-container
          image: your-image
EOF

# Step 3: Apply the deployment
kubectl apply -f temp-deployment.yaml

# Step 4: Wait for the deployment to be running
kubectl wait --for=condition=available deployment/your-deployment

# Step 5: Get the pod name and output the node name
# 1 pod_name应该是所有的namespace去获取的
# 2 node_name的时候,我就需要知道每个Pod运行在哪些Node上面
# pod_name=$(kubectl get pods -l app=your-app -A -o jsonpath='{.items[0].metadata.name}')
# node_name=$(kubectl get pod $pod_name -o jsonpath='{.spec.nodeName}')
# kubectl get pod demo-deployment-6f78d67d9c-6bp4f -o jsonpath='{.spec.nodeName}' -n lex
# echo "Pod Name: $pod_name"
# echo "Node Name: $node_name"

# Step 5: Get the pod names and output the node names for all namespaces
pod_names=$(kubectl get pods --all-namespaces -l app=your-app -o jsonpath='{range .items[*]}{.metadata.namespace}:{.metadata.name}{"\n"}{end}')

# Loop through each pod to get its node name
while IFS= read -r pod; do
  namespace=$(echo $pod | cut -d: -f1)
  pod_name=$(echo $pod | cut -d: -f2)
  
  node_name=$(kubectl get pod $pod_name -n $namespace -o jsonpath='{.spec.nodeName}')
  
  echo "Pod Name: $pod_name (Namespace: $namespace)"
  echo "Node Name: $node_name"
  echo "--------------------"
done <<< "$pod_names"


# Step 6: Delete the deployment
kubectl delete deployment your-deployment

# Cleanup: Remove the temporary deployment file
rm temp-deployment.yaml
```
- simple deployment 
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-deployment
spec:
  replicas: 8
  selector:
    matchLabels:
      app: your-app
  template:
    metadata:
      labels:
        app: your-app
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - your-app
            topologyKey: "kubernetes.io/hostname"
      initContainers:
        - name: appd-init-service
          image: docker.io/appdynamics/java-agent:20.8.0 
          imagePullPolicy: Always
          command: ["sh", "-c", "cp -r /opt/appdynamics/. /opt/appdynamics-java"]
      containers:
        - name: your-container
          image: your-image

```
- about affinity 
https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#affinity-and-anti
```yaml
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - your-app
            topologyKey: "kubernetes.io/hostname"
```

这段YAML描述了一个部署的亲和性配置，其中包含 podAntiAffinity 规则。在这个例子中，Pod不应该在它们的整个生命周期中被调度到同一节点上。以下是对于这段YAML的解释：

1. `affinity`: 定义部署的亲和性配置。
2. `podAntiAffinity`: 定义反亲和性规则。
3. `requiredDuringSchedulingIgnoredDuringExecution`: 强制调度规则，并在执行过程中忽略。在这个例子中，Pod不应该在它们的整个生命周期中被调度到同一节点上。
4. `labelSelector`: 匹配Pod上的"app"标签。
5. `topologyKey`: 指定用于反亲和性调度的节点标签。在这个例子中，节点标签是 "kubernetes.io/hostname"。

# 


# pod Trigger 
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: emb-aibang-ky-test-sb
  namespace: ns-lex
spec:
  initContainers:
    - name: appd-init-service
      image: "docker.io/appdynamics/java-agent:20.6.0"
      imagePullPolicy: Always
      command: ["sh", "-c", "cp -r /opt/appdynamics/. /opt/appdynamics-java"]
  containers:
    - name: nginx
      image: nginx
      imagePullPolicy: IfNotPresent
  nodeSelector:
    kubernetes.io/hostname: gke-lex-cluster-abcde-default-pool-867d2426-508
```



- appd
  - https://docs.appdynamics.com/appd/22.x/22.6/en/application-monitoring/install-app-server-agents/container-installation-options/instrument-kubernetes-applications-manually/use-init-containers-to-instrument-applications
```yaml
kind: Deployment
spec:
  containers:
  - name: java-app
    image: myrepo/java-app:v1
    volumeMounts:
    - mountPath: /opt/appdynamics
      name: appd-agent-repo
  initContainers:
  - command:
    - cp
    - -r
    - /opt/appdynamics/.
    - /opt/temp
    name: appd-agent
	image: docker.io/appdynamics/java-agent:20.8.0
    volumeMounts:
    - mountPath: /opt/temp
      name: appd-agent-repo
  volumes:
    - name: appd-agent-repo
      emptyDir: {}
```

- 将Pod调度到某个特定的节点
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: aibang-lex-cap-test-sb
  namespace: ns-lex
spec:
  initContainers:
    - name: appd-init-service
      image: docker.io/appdynamics/java-agent:20.8.0 
      imagePullPolicy: Always
      command: ["sh", "-c", "cp -r /opt/appdynamics/. /opt/appdynamics-java"]
  containers:
    - name: nginx
      image: nginx
      imagePullPolicy: IfNotPresent
  nodeSelector:
    kubernetes.io/hostname: gke-lex--cluster-143-np-11234da
```
- eg
- 如果你想使用 `nodeSelector` 将Pod调度到特定的节点，你可以在Deployment的模板中添加 `nodeSelector` 部分。以下是包含了 `nodeSelector` 的完整YAML配置：
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-deployment
spec:
  replicas: 8
  selector:
    matchLabels:
      app: your-app
  template:
    metadata:
      labels:
        app: your-app
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - your-app
            topologyKey: "kubernetes.io/hostname"
      nodeSelector:
        your-node-label-key: your-node-label-value
      initContainers:
        - name: appd-init-service
          image: docker.io/appdynamics/java-agent:20.8.0 
          imagePullPolicy: Always
          command: ["sh", "-c", "cp -r /opt/appdynamics/. /opt/appdynamics-java"]
      containers:
        - name: your-container
          image: your-image
```

在上述配置中，我添加了 `nodeSelector` 部分，你需要替换其中的 `your-node-label-key` 和 `your-node-label-value` 为你希望匹配的节点标签的键和值。这样配置将确保Pod只会被调度到具有指定标签的节点上。

