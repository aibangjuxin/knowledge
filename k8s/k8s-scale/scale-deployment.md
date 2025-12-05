你现在的情况总结一下：

- **同一个 namespace 里有一些 Deployment 会卡在 pending / crashlooping / 无法正常启动；**
    
- **但这些 Deployment 仍然占用大量资源（CPU/Memory requests），导致其他 API 无法调度；**
    
- 你想**写脚本自动找出这些“异常 Deploy”并处理（比如 scale down 或删除）。**
    

  

下面我给你一个成熟可用的方案，包括思路 + 可直接使用的脚本。

---

# **✅** 

# **最佳解决方案：自动发现“异常 Deployment”并清理/缩容**

  

通过 kubectl + jq + bash，你可以写一个 job 或 cronjob 自动执行：

  

## **一、判定哪些 Deployment 是“异常”的？**

  

你可以依据以下任意条件：

  

### **1. Pod 长时间 Pending**

  

表示资源不够，deployment 却一直卡着占位。

```
kubectl get pods -n <ns> \
  --field-selector=status.phase=Pending
```

### **2. Pod CrashLoopBackOff 或 CreateContainerConfigError**

  

这种也建议清理：

```
kubectl get pods -n <ns> | grep -E "CrashLoopBackOff|CreateContainerConfigError"
```

### **3. Deployment 所需资源过大（例如单个副本就 2C / 4Gi）**

  

你可以过滤 requests 超过阈值的 Deploy：

```
kubectl get deploy -n <ns> -o json | jq '
  .items[] | 
  {name: .metadata.name, 
   cpu: .spec.template.spec.containers[0].resources.requests.cpu,
   mem: .spec.template.spec.containers[0].resources.requests.memory}
'
```

---

# **二、**

# **实用脚本（检测异常 → 自动 scale 为 0）**

  

你可以把下面脚本保存为 cleanup-bad-deploys.sh：

```
#!/bin/bash

NAMESPACE=$1
CPU_THRESHOLD="1000m"   # 1 core
MEM_THRESHOLD="2Gi"

echo "Scanning namespace: $NAMESPACE"

# 找到异常 pod (Pending / CrashLoopBackOff)
BAD_PODS=$(kubectl get pods -n $NAMESPACE --no-headers | \
           grep -E "Pending|CrashLoopBackOff|CreateContainerConfigError" | \
           awk '{print $1}')

for POD in $BAD_PODS; do
  DEPLOY=$(kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.metadata.ownerReferences[0].name}')
  if [ -n "$DEPLOY" ]; then
    echo "⚠️  Scaling down abnormal deployment: $DEPLOY"
    kubectl scale deploy/$DEPLOY -n $NAMESPACE --replicas=0
  fi
done
```

---

# **三、附加功能：**

# **限制资源超大的 Deployment（自动 scale down）**

  

如果你也想自动清理“资源超大”的 Deploy，可以加入这一段：

```
# 检查资源超标的 deployments
kubectl get deploy -n $NAMESPACE -o json | jq -r \
  ".items[] | select(.spec.template.spec.containers[0].resources.requests.cpu != null) |
   select(.spec.template.spec.containers[0].resources.requests.cpu > \"$CPU_THRESHOLD\") |
   .metadata.name" | while read DEPLOY; do
  echo "⚠️  Deployment $DEPLOY exceeds CPU threshold, scaling down..."
  kubectl scale deploy/$DEPLOY -n $NAMESPACE --replicas=0
done
```

---

# **四、推荐实际做法：放进 CronJob 自动执行**

  

写个 K8s CronJob：

```
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup-bad-deploys
  namespace: <ns>
spec:
  schedule: "*/5 * * * *"   # 每 5 分钟扫描一次
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleaner
            image: bitnami/kubectl
            command: ["/bin/bash", "-c", "/scripts/cleanup-bad-deploys.sh"]
            volumeMounts:
            - name: script
              mountPath: /scripts
          restartPolicy: OnFailure
          volumes:
          - name: script
            configMap:
              name: cleanup-script
```

---

# **如果你愿意，我可以为你：**

  

✅ **完全生成你需要的脚本（根据你的规则）**

✅ **帮你设计自动清理策略（安全版 / 强制版）**

✅ **生成可部署到 GCP GKE 的 CronJob YAML**

  

只需要告诉我：

1. 你的 namespace 名称？
    
2. 你希望“异常行为”的判断依据是什么？（Pending / CrashLoop / 超资源 / 启动超时？）
    
3. 遇到异常想做什么？**scale 0 / delete / 通知？**
    

  

我可以帮你写成可直接投入生产的 version。