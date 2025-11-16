在 **GKE** 中，如果你 **不人为挂载任何持久磁盘（PD）或 emptyDir→SSD/HDD**，那么 **容器内部的文件系统（包括 /var/log、/tmp、你的应用日志等）都是写在节点的本地临时磁盘上**。

关键点是：

# **✅** 

# **Docker 容器的“本地磁盘容量” = 节点本地磁盘的可用容量（但受 kubelet 管理限制）**

也就是说：

**容器并没有自己的独立磁盘大小限制，默认使用的是节点的 /var/lib/kubelet 和 /var/lib/docker 所在的本地磁盘空间**。

---

# **🚀** 

# **1. GKE 节点的默认磁盘大小是多少？**

取决于你在创建 node pool 时的配置：

| **GKE 节点类型**         | **默认磁盘类型**        | **默认大小**                     |
| ------------------------ | ----------------------- | -------------------------------- |
| **GCE VM（COS/Ubuntu）** | pd-standard             | **100GB**（大多数节点类型默认）  |
| Autopilot                | Google 管理，无固定数值 | 强制使用 ephemeral storage quota |

👉 **如果你没有特别指定，普通 GKE Standard 节点 = 100GB 本地磁盘可用空间。**

---

# **🚨** 

# **2. 容器可用空间并不等于 100GB**

Kubernetes 会给每个 Pod 强制分配 **ephemeral storage（临时存储）限额**，如果你没有手动设置 ephemeral-storage，则：

- **Standard GKE：** Pod 默认不限制，但会受到 node 总容量与 eviction 管理影响
- **Autopilot GKE：** 每个 Pod **强制**有限额（通常几 GB）

---

# **🧪** 

# **3. 容器的实际存储来自哪里？**

| **写入路径**                 | **实际落盘位置**                                   |
| ---------------------------- | -------------------------------------------------- |
| 容器文件系统（非挂载）       | 节点本地磁盘 /var/lib/kubelet/pods/.../containerfs |
| /var/log（容器内部）         | 仍在节点本地磁盘                                   |
| Docker 日志（stdout/stderr） | /var/log/containers（host 上）                     |
| emptyDir                     | 也是写在节点磁盘                                   |

**所以你的容器写文件 = 写节点本地磁盘。**

---

# **⭐** 

# **4. 实际上容器本地能写多少？**

以你常见的 GKE node 为例：

### **假设节点 100GB：**

- Kubelet 系统保留约 10GB
- OS 保留约 7~10GB
- Docker/Kubelet runtime 占用 5~15GB（随着镜像数量变化）
- 剩余给所有 Pod 的 ephemeral storage：大概 **50~70 GB**

---

# **⚠ 日志放本地会有什么风险？**

### **❌** 

### **风险 1：磁盘被写满 → Pod 会被 Evicted**

Kubelet 有 **eviction policy**，当节点磁盘使用量超过 85-95%（取决于配置），就会：

- 先删除 emptyDir
- 再驱逐（evict）Pod
- 最后可能造成 Node NotReady

### **❌** 

### **风险 2：容器重启后日志丢失**

没有持久化。

---

# **⭐ 最佳建议（强烈推荐）**

如果你的容器在本地写日志，我推荐：

### **✔** 

### **方案 A：把日志输出到 stdout/stderr，让 GKE Logging 管理**

这是 GKE 最推荐的方式。

### **✔** 

### **方案 B：使用 emptyDir + medium=Memory**

适合临时日志或高性能缓存。

### **✔** 

### **方案 C：挂载 GCE Persistent Disk (PD) 存日志（持久化）**

---

# **📌 总结一句话**

> **在 GKE 中，一个不挂载磁盘的容器本地最大可用空间 ≈ 节点本地磁盘剩余空间（通常 50–70GB），不是独立分配的。**

如需，我也能帮你查看：

- 你当前 GKE node 的实际磁盘大小
- Pod ephemeral storage 限额
- 如何配置日志落盘方案

要我继续吗？
