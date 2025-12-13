| **GCP-GKE-CTRL-85** | PROT-2 - IT保护性安全技术 | 必须为GKE集群启用容器威胁检测。 | CAEP team | 是 | 是 | 通过Security Command Center (SCC) Premium在组织级别启用。 |

### **合规性说明与验证方法：GKE容器威胁检测**

---
#### **1. “容器威胁检测”是什么？**

**容器威胁检测（Container Threat Detection）** 是 **Google Cloud Security Command Center (SCC) Premium** 提供的一项内置服务。它专门为GKE设计，能够持续监控您的GKE集群，并检测常见的容器运行时攻击和可疑活动，例如：

*   **恶意二进制文件执行**：检测到已知恶意软件的执行。
*   **反向Shell**：检测到从容器内部发起的反向Shell连接。
*   **加密货币挖矿**：检测到与加密货币挖矿相关的活动。

这项功能通常在**组织级别**作为Security Command Center Premium的一部分被激活，其策略会向下继承到组织内的所有项目和GKE集群。

---
#### **2. 如何通过命令行验证容器威胁检测是否已启用？**

您可以通过一系列`gcloud scc`命令来获取证据。您需要您的**组织ID**（Organization ID）或**项目ID**（Project ID）。

**步骤1：确认Security Command Center的激活状态和级别**

首先，确认您的组织已激活Security Command Center Premium。容器威胁检测是Premium级别的功能。

```bash
# 将 YOUR_ORGANIZATION_ID 替换为您的数字组织ID
gcloud scc organizations get-settings YOUR_ORGANIZATION_ID
```

**预期合规输出**：
在输出结果中，寻找 `tier` 字段。如果值为 `PREMIUM`，则说明已满足使用容器威胁检测的前提条件。
```yaml
...
tier: PREMIUM
...
```

**步骤2：检查容器威胁检测服务模块是否已启用**

接下来，直接检查`CONTAINER_THREAT_DETECTION`服务模块的启用状态。

```bash
# 将 YOUR_ORGANIZATION_ID 替换为您的数字组织ID
gcloud scc services get-settings containerThreatDetectionSettings \
  --organization=YOUR_ORGANIZATION_ID
```

**预期合规输出**：
在输出结果中，`moduleEnablementState` 字段的值应为 `ENABLED`。
```yaml
name: organizations/YOUR_ORGANIZATION_ID/services/containerThreatDetection/settings
moduleEnablementState: ENABLED
...
```
如果是在项目级别覆盖了组织设置，您也可以在项目级别检查：
```bash
# 将 YOUR_PROJECT_ID 替换为您的项目ID
gcloud scc services get-settings containerThreatDetectionSettings \
  --project=YOUR_PROJECT_ID
```

**步骤3：列出相关的安全发现（Finding）作为辅助证据**

如果容器威胁检测正在运行，它会在发现威胁时生成“发现”（Finding）。查询这些发现也可以证明该服务正在工作。即使没有发现（这是好事），成功执行命令本身也说明该API是启用的。

```bash
# 将 YOUR_ORGANIZATION_ID 替换为您的组织ID
gcloud scc findings list organizations/YOUR_ORGANIZATION_ID \
  --filter="category=\\"CONTAINER_THREAT_DETECTION\\""
```

**预期输出**：
*   **如果有发现**：命令会列出所有由容器威胁检测生成的安全警告。
*   **如果没有发现**：命令会返回空列表 `[]`。这同样是有效的证据，表明服务已启用并在持续监控，只是尚未发现威胁。

---
#### **3. 相关的官方文档**

以下是关于GKE容器威胁检测的官方文档链接，您可以查阅以获取更详细的信息：

*   **容器威胁检测概述**:
    [https://cloud.google.com/security-command-center/docs/concepts-container-threat-detection-overview](https://cloud.google.com/security-command-center/docs/concepts-container-threat-detection-overview)
*   **启用和停用容器威胁检测**:
    [https://cloud.google.com/security-command-center/docs/how-to-enable-container-threat-detection](https://cloud.google.com/security-command-center/docs/how-to-enable-container-threat-detection)
