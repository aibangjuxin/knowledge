下面给你 **最准确 + 可操作** 的方法来验证：

**“GKE Audit Logs（审计日志）是否默认启用并被收集”**

---

# **✅ GKE 审计日志包括哪些内容？**

  

GKE 的审计日志实际上来自 **Cloud Audit Logs**，包含：

|**日志类型**|**内容**|
|---|---|
|**Admin Activity Logs（默认强制启用）**|所有控制面操作，例如创建 Pod、修改 Node Pool|
|**Data Access Logs（可选）**|访问 Kubernetes API 的请求（读取/写入）|

⚠️ **Admin Activity Logs 一定启用，无法关闭。**

⚠️ Data Access Logs 需手动开启，但某些 GKE 功能会自动启用部分类型。

  

所以问卷中的 “GKE audit logs are enabled by default” 指的是：

  

> **Admin Activity Logs 默认强制开启，并自动收集。**

---

# **🔍 如何确认你的 GKE 集群的审计日志已启用？**

  

## **方法 1：在 Cloud Logging 中搜索（最直观）**

  

### **1. 打开 Cloud Logging → Logs Explorer**

  

### **2. 在 Query 中填：**

```
resource.type="k8s_cluster"
logName:"activity"
```

如果有结果，例如：

```
k8s.io/cluster/api?operation=create
k8s.io/cluster/nodePools?operation=update
```

说明你的 **GKE Admin Activity Logs 已默认收集**。

---

# **方法 2：通过 gcloud 检查集群是否开启 Data Access Logs**

  

（Admin Activity Logs 不需要检查，因为它**永远开启**）

```
gcloud container clusters describe <CLUSTER_NAME> \
    --region <REGION> \
    --format="yaml"
```

查找：

```
loggingService: logging.googleapis.com/kubernetes
loggingConfig:
  enableComponents:
  - APISERVER
  - CONTROLLER_MANAGER
  - SCHEDULER
```

如果这些组件启用，就表示 Kubernetes API Server 日志已被采集。

---

# **方法 3：检查项目级审计日志设置（最正式的验证）**

  

路径：

```
GCP Console → IAM & Admin → Audit Logs
```

查看：

- **Container Kubernetes Engine API**
    
    - Admin Read Logs → ON（强制开启）
        
    - Admin Write Logs → ON（强制开启）
        
    - Data Access（可选） → 若你开启了会显示启用
        
    

  

只要 Admin Logs 显示启用（通常无法关），就说明：

  

✔️ **GKE 审计日志已自动收集**

---

# **📝 合规问卷推荐回答（英文）**

```
GKE audit logs are enabled and collected by default through Cloud Audit Logs. 
We verified this by checking the Cloud Logging “Admin Activity Logs” for the Kubernetes Engine API, which are always enabled and cannot be disabled. The logs are visible in Cloud Logging under the `k8s_cluster` resource type and include all control-plane operations. 
```

如需，我可以帮你生成更详细的回答（适用于金管会、ISO、SOC2 等审计）。