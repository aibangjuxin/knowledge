| **GCP-GKE-CTRL-47** | PROT-2 - IT保护性安全技术 | 必须创建启用自动修复的节点池。<br>**注意:** 此控制仅适用于标准GKE产品。使用Autopilot时,默认启用自动修复。更多详细信息可在此处找到。 | CAEP team | 是 | 是 | 集群节点池配置强制开启自动修复。 |

### **验证方法：如何证明已启用自动修复**

要验证您的GKE节点池是否配置了自动修复功能，您可以使用`gcloud`命令行工具来检查节点池的`management.autoRepair`状态。

**步骤1：列出项目中的所有GKE集群及其位置**

首先，您需要知道您的GKE集群名称及其所在的区域或可用区。

```bash
gcloud container clusters list --format="table(name, location)"
```

**预期输出示例:**

```
NAME              LOCATION
my-gke-cluster    asia-southeast1-a
another-cluster   us-central1
```

**步骤2：检查特定集群中所有节点池的自动修复状态**

确定集群名称和位置后，您可以检查该集群中所有节点池的自动修复状态。

```bash
# 替换 YOUR_CLUSTER_NAME 为您的集群名称
# 替换 YOUR_CLUSTER_LOCATION 为您的集群区域或可用区 (例如：asia-southeast1-a 或 us-central1)
gcloud container node-pools list \
  --cluster YOUR_CLUSTER_NAME \
  --location YOUR_CLUSTER_LOCATION \
  --format="table(name, management.autoRepair)"
```

**合规性预期输出示例:**

要符合合规要求，`AUTO_REPAIR`列的所有值都应为 `True`。

```
NAME              AUTO_REPAIR
default-pool      True
app-node-pool     True
batch-node-pool   True
```

**步骤3：检查特定节点池的详细自动修复状态（可选）**

如果您需要查看某个特定节点池的详细信息，包括自动修复状态，可以使用`describe`命令。

```bash
# 替换 YOUR_NODE_POOL_NAME 为您的节点池名称
# 替换 YOUR_CLUSTER_NAME 为您的集群名称
# 替换 YOUR_CLUSTER_LOCATION 为您的集群区域或可用区
gcloud container node-pools describe YOUR_NODE_POOL_NAME \
  --cluster YOUR_CLUSTER_NAME \
  --location YOUR_CLUSTER_LOCATION \
  --format="yaml(name, management.autoRepair)"
```

**合规性预期输出示例:**

```yaml
name: app-node-pool
management:
  autoRepair: true
```

如果`autoRepair`的值为`true`，则表示该节点池已启用自动修复功能，符合`GCP-GKE-CTRL-47`的要求。如果为`false`，则说明该节点池不符合合规要求，需要进行修改。