# 🚀 高效 Kubernetes 管理：Kubectl 核心命令与进阶技巧


---

## 1. 监控与资源管理 (Resource & Performance)

### 1.1 找出吃内存/CPU 的“资源大户”
```bash
# 按内存使用量排序 Pod
kubectl top pods --all-namespaces --sort-by=memory

# 按 CPU 使用量排序 Pod
kubectl top pods --all-namespaces --sort-by=cpu

# 查看节点的资源消耗
kubectl top nodes
```
> **解析**：生产环境排查节点 OOM (Out Of Memory) 风险或 CPU 暴涨的最佳方式。

---

## 2. 集群与事件观测 (Cluster & Observability)

### 2.1 追踪集群事件时间线 (已修复语法)
```bash
# 按时间倒序查看当前命名空间的事件
kubectl get events --sort-by='.metadata.creationTimestamp'

# 查看所有命名空间的事件，排查全网异常
kubectl get events -A --sort-by='.metadata.creationTimestamp'
```
> **解析**：排查 `CrashLoopBackOff` 或 `ImagePullBackOff` 的第一手资料。这里的值必须用单引号 `'.metadata.creationTimestamp'` 包围。

### 2.2 存储排障：查看持久化卷
```bash
kubectl get pv,pvc -n <namespace>
```
> **解析**：快速列出所有的持久卷 (PV) 和持久卷声明 (PVC)，查看它们的 `Bound` 状态以诊断挂载失败问题。

### 2.3 查看 ConfigMap 及 Secret 内容
```bash
kubectl get configmap myconfig -n <namespace> -o yaml
```
> **解析**：以 YAML 格式提取配置，方便审查现有的配置内容。

---

## 3. 工作负载与发布管理 (Workloads & Deployments)

### 3.1 ⚡ 快速滚动更新 (Rolling Update)
```bash
kubectl set image deployment/myapp myapp-container=nginx:1.21.0 -n <namespace>
```
> **解析**：直接替换镜像触发滚动更新，而无需手动去编辑整个 YAML。适合 CI/CD 管道流水线集成。

### 3.2 ⭐️ 监控与回滚发布状态
```bash
# 实时监控发布进度
kubectl rollout status deployment/myapp

# 查看发布历史版本
kubectl rollout history deployment/myapp

# 一键回滚到上一个版本 (救火神技)
kubectl rollout undo deployment/myapp
```

---

## 4. 节点调度与维护 (Node Management & Scheduling)

### 4.1 节点打标签 (Label)
```bash
kubectl label node <node-name> env=production
```
> **解析**：给节点打上特定标签，配合 Pod 的 `nodeSelector` 或 `nodeAffinity` 进行精确的调度控制。

### 4.2 节点污点 (Taint) - 隔离负载
```bash
# 添加污点，防止常规 Pod 调度上来
kubectl taint nodes <node-name> key=value:NoSchedule

# 移除污点 (末尾加个减号)
kubectl taint nodes <node-name> key=value:NoSchedule-
```
> **解析**：非常关键的命令。常用于把特定的节点预留给特殊的任务（比如只允许 GPU 任务运行）。

### 4.3 节点维护 (优雅驱逐 Pod)
```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force
```
> **解析**：准备重启、升级 Node 节点前的必备操作。它会安全地通知 Pod 退出，并将它们调度到别的节点。

---

## 5. 安全与权限 (Security & RBAC)

### 5.1 快速生成密码 Secret
```bash
kubectl create secret generic mysecret --from-literal=password='SuperSecret123!' -n <namespace>
```
> **解析**：直接在命令行生成密文，避免手动把明文通过 `base64` 编码然后再写进长长的 YAML。

### 5.2 ⭐️ RBAC 权限测试 (神器)
```bash
# 检查自己是否有权限新建 Pod
kubectl auth can-i create pods

# 模拟某个 ServiceAccount 的视角检查权限
kubectl auth can-i delete deployments --as=system:serviceaccount:default:my-sa
```
> **解析**：当你遇到 `Forbidden` 或者 CI/CD 流水线毫无头绪的报错时，使用这个命令能瞬间诊断出是不是 ServiceAccount 的 Role 绑定出了错。

---

## 6. 🔥 进阶排障工具箱 (Advanced Troubleshooting) (扩展推荐)

这部分为您新添加了高级排查场景绝对用得上的命令：

### 6.1 获取某个节点上的所有 Pod
```bash
kubectl get pods --field-selector spec.nodeName=<node-name> -A
```
> **解析**：当某个 Node 出现网络故障或 I/O 异常时，用它迅速列出上面的“受害者”。

### 6.2 在极简镜像中进行网络/代码排障 (Ephemeral Containers)
```bash
kubectl debug -it <pod-name> --image=busybox:1.28 --target=<container-name>
```
> **解析**：现在很多生产环境的镜像都是 Distroless（没有 shell、没有 curl, ping）。使用 `debug` 命令，Kubernetes 会往这个运行中的 Pod 旁边塞一个带工具箱的“临时容器”，而且**两者共享网络空间**！

### 6.3 本地流量转发测试 (无需 Ingress)
```bash
kubectl port-forward svc/my-database 5432:5432 -n <namespace>
```
> **解析**：在没有配置把内网数据库/中间件暴露出来（如无 LoadBalancer/Ingress）的情况下，通过隧道安全地从你的个人电脑连接集群内部服务。

### 6.4 告别 Google：获取结构说明
```bash
kubectl explain deployment.spec.template.spec.containers
```
> **解析**：不知道 YAML 某个字段该怎么拼写？直接用 `explain`，这是 Kubernetes 内置的活生生的文档。