日志涉及 **GKE Pod 调度失败（FailedScheduling）** 的典型场景。下面我帮你系统分析问题的成因与解决方案。

---

## **🧩 一、问题分析**

  

从日志关键信息来看：

```
Warning  FailedScheduling
default-scheduler 0/60 nodes are available: 
54 Insufficient memory, 
6 node(s) didn't match pod anti-affinity rules.
preemption: 0/60 nodes are available: 60 No preemption victims found for incoming pod.
Normal NotTriggerScaleUp cluster-autoscaler
Pod didn't trigger scale-up: max node group size reached
```

我们可以拆解出以下几个核心问题：

|**问题点**|**描述**|**根因**|
|---|---|---|
|**Insufficient memory (内存不足)**|54 个节点可用内存不足|Pod 请求的资源超出节点可分配资源|
|**Pod anti-affinity 不匹配**|6 个节点不符合反亲和性（anti-affinity）规则|Pod 被限制不能与特定 Pod 同节点运行|
|**No preemption victims found**|没有找到可被“驱逐”的低优先级 Pod|调度器无法通过抢占解决资源不足|
|**NotTriggerScaleUp**|自动扩容未触发|GKE Cluster Autoscaler 已达到最大节点数上限 (max node group size reached)|

---

## **⚙️ 二、问题本质**

  

简化后可以理解为：

  

> **Pod 想调度上去，但当前集群所有节点要么内存不够，要么被亲和性规则排除了。Autoscaler 也无法再扩容节点，所以 Pod 被卡在 Pending 状态。**

---

## **🧭 三、解决方案**

  

你可以从以下四个方向排查与解决：

  

### **1️⃣** 

### **检查并调整 Pod 资源请求**

  

先查看 Deployment/StatefulSet 的 YAML：

```
kubectl get deploy <your-deploy> -o yaml
```

重点关注：

```
resources:
  requests:
    memory: "2Gi"
    cpu: "1"
```

**优化建议：**

- 确认请求值（requests）是否过高。
    
- 若应用实际占用较低，可下调 requests.memory。
    
- 使用 kubectl top pod + kubectl top node 观察真实使用量。
    

---

### **2️⃣** 

### **检查 Pod 反亲和性规则 (anti-affinity)**

  

查看调度约束：

```
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

**优化建议：**

- 如果反亲和规则过于严格（requiredDuringSchedulingIgnoredDuringExecution），
    
    可改为软性约束：
    

```
preferredDuringSchedulingIgnoredDuringExecution
```

-   
    
- 或者放宽 topologyKey（如 zone 而不是 hostname）。
    

---

### **3️⃣** 

### **确认 Cluster Autoscaler 配置**

  

检查自动扩容状态：

```
gcloud container clusters describe <cluster-name> \
  --region <region> \
  --format="value(autoscaling)"
```

日志中提到：

  

> max node group size reached

  

说明你已触及自动扩容上限。

  

**解决方案：**

- 提高上限：
    

```
gcloud container clusters update <cluster-name> \
  --enable-autoscaling \
  --min-nodes=3 \
  --max-nodes=10 \
  --node-pool=<pool-name>
```

-   
    
- 或手动扩容节点：
    

```
gcloud container clusters resize <cluster-name> \
  --node-pool <pool-name> \
  --num-nodes <新数量>
```

  

---

### **4️⃣** 

### **验证调度情况**

  

你可以使用以下命令检查哪些节点满足调度条件：

```
kubectl describe pod <pending-pod-name>
```

重点关注：

- Events 部分的 0/60 nodes are available
    
- 每个节点失败的原因（如内存不足、taint、不匹配等）
    

---

## **🔍 四、流程图示意**

```
graph TD
    A[Pod 创建] --> B[Scheduler 调度]
    B --> C{节点资源是否足够?}
    C -- 否 --> D[Insufficient memory]
    C -- 是 --> E{Anti-affinity 匹配?}
    E -- 否 --> F[节点排除]
    E -- 是 --> G{Autoscaler 可扩容?}
    G -- 否 --> H[Max node group reached -> Pending]
    G -- 是 --> I[触发节点扩容 -> Pod 调度成功]
```

---

## **🧠 五、最佳实践建议**

|**场景**|**建议**|
|---|---|
|资源不足频繁|使用 HPA + Cluster Autoscaler 动态伸缩|
|亲和性规则复杂|合理使用 preferred 而非 required|
|调度等待时间长|启用调度日志或使用 kubectl describe pod 进行调度诊断|
|容量规划|定期分析 kubectl top node 数据，评估 node pool 配额|

---

是否希望我帮你生成一段示例 YAML，对比 “严格 anti-affinity” 和 “宽松 anti-affinity” 两种写法？这样你可以直观看出差别。