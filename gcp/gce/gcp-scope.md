# Google Cloud Compute Engine (GCE) Access Scopes (访问范围) 详解

本文件详细介绍 GCP Compute Engine 虚拟机 (VM) 或实例模板 (Instance Template) 中 `--scopes` 参数的具体含义、工作原理、常见别名以及现代云安全下的最佳实践。

---

## 1. 什么是 Access Scopes (访问范围)？

**Access Scopes** 是 Google Cloud 控制 Compute Engine 虚拟机实例访问 Google Cloud API 的**粗粒度 (Coarse-grained) 历史授权机制**。

当您为虚拟机附加一个服务账号 (Service Account) 时，虚拟机内部运行的应用（或 `gcloud` CLI、各种语言的 Cloud Client Libraries）在调用 GCP 服务时，会向虚拟机的元数据服务器 (Metadata Server) 请求 OAuth 2.0 Access Token。
**Access Scopes 决定了该 Token 拥有哪些 OAuth Scope，从而在虚拟机级别对能调用的 API 服务进行初步限制。**

---

## 2. 双重验证机制：Access Scopes 与 IAM Roles 的“交集”关系

虚拟机的实际操作权限，并非单由服务账号的 IAM 角色决定，也非单由 Access Scopes 决定，而是由两者的**交集 (Intersection)** 决定：

$$\text{虚拟机实际有效权限} = \text{服务账号的 IAM Roles 权限} \cap \text{虚拟机实例的 Access Scopes 权限}$$

### 举例说明：
假设您创建了一个虚拟机，绑定了服务账号 `my-vm-sa@my-project.iam.gserviceaccount.com`，并且：

*   **场景 A (Scope 限制了 IAM)**：
    *   **服务账号 IAM 角色**：具有 `roles/storage.admin`（拥有 Cloud Storage 的全部控制权）。
    *   **虚拟机 Access Scopes**：设置为 `https://www.googleapis.com/auth/devstorage.read_only`（只读范围）。
    *   **实际权限**：该虚拟机中的代码**只能读取** GCS 桶，一旦尝试写入或删除文件，就会报错。
*   **场景 B (IAM 限制了 Scope)**：
    *   **服务账号 IAM 角色**：仅具有 `roles/storage.objectViewer`（仅能读取 GCS 桶）。
    *   **虚拟机 Access Scopes**：设置为 `https://www.googleapis.com/auth/cloud-platform`（无任何 Scope 限制）。
    *   **实际权限**：该虚拟机中的代码**仍然只能读取** GCS 桶，因为 IAM 端未授予写权限。
*   **场景 C (交集成功)**：
    *   **服务账号 IAM 角色**：具有 `roles/storage.objectAdmin`（能读写 GCS 桶）。
    *   **虚拟机 Access Scopes**：设置为 `https://www.googleapis.com/auth/cloud-platform`（无限制）。
    *   **实际权限**：虚拟机内的代码可以**正常读写** GCS 桶。

---

## 3. 什么是 `cloud-platform` 范围？

在您的命令中，使用了：
`--scopes=https://www.googleapis.com/auth/cloud-platform` （常简写为 `cloud-platform`）。

*   **含义**：`https://www.googleapis.com/auth/cloud-platform` 称为“全面平台级范围”。它表示**虚拟机不对任何 GCP 服务的 API 进行范围限制**。
*   **作用**：一旦设置了该范围，虚拟机层面的 OAuth 过滤器实际上失效。**所有的访问权限校验完全委托给该 VM 服务账号上绑定的 IAM Role**。
*   **优点**：
    *   权限精细度：IAM Role 提供了极其精细的权限划分（而 Scope 的划分非常粗糙）。
    *   动态更新：修改服务账号的 IAM Role 立即生效，无需重启或重新创建虚拟机；而 Access Scopes 一旦在 VM/模板创建时定死，除非重新创建或停机修改，否则无法变更。

---

## 4. `gcloud` 常用 Scope 缩写别名与 URI 映射

在 `gcloud` CLI 中，您可以使用完整的 URI（如 `https://www.googleapis.com/auth/cloud-platform`），也可以使用别名。

| 别名 (Alias) | 对应完整的 OAuth URI | 描述 |
| :--- | :--- | :--- |
| `cloud-platform` | `https://www.googleapis.com/auth/cloud-platform` | **平台全面权限**。允许调用所有 GCP API，将权限完全交给 IAM 判定。 |
| `compute-ro` | `https://www.googleapis.com/auth/compute.readonly` | 对 Compute Engine 资源只有读权限。 |
| `compute-rw` | `https://www.googleapis.com/auth/compute` | 对 Compute Engine 资源有读写权限。 |
| `storage-ro` | `https://www.googleapis.com/auth/devstorage.read_only` | 对 Cloud Storage 只有读权限。 |
| `storage-rw` | `https://www.googleapis.com/auth/devstorage.read_write` | 对 Cloud Storage 有读写权限。 |
| `storage-full` | `https://www.googleapis.com/auth/devstorage.full_control` | 对 Cloud Storage 拥有全部控制权。 |
| `logging-write` | `https://www.googleapis.com/auth/logging.write` | 允许写入 Cloud Logging 日志。 |
| `monitoring-write`| `https://www.googleapis.com/auth/monitoring.write` | 允许写入 Cloud Monitoring 指标。 |
| `userinfo-email` | `https://www.googleapis.com/auth/userinfo.email` | 允许获取当前身份的 Email 地址。 |

---

## 5. 现代 GCP 安全最佳实践 (Best Practices)

1.  **推荐配置：一律设置 `--scopes=cloud-platform`**：
    *   放弃通过限制 Access Scopes 来控制 VM 权限的做法。将所有 VM 和实例模板的 `--scopes` 统一设为 `cloud-platform`，从而将权限决策点单一化到 IAM 系统中。
2.  **避免使用默认服务账号 (Default Service Account)**：
    *   GCE 默认的服务账号（`[PROJECT_NUMBER]-compute@developer.gserviceaccount.com`）在默认情况下被授予了项目编辑者 (`Editor`) 的高危权限。
    *   **正确做法**：为您创建的每一组 VM 或 MIG（托管实例组）新建一个自定义服务账号（如 `my-app-sa`），并遵循最小权限原则（Least Privilege）仅赋予其运行所需的 IAM Role。
3.  **使用 IAM 授权细粒度资产**：
    *   通过 IAM 条件（Conditions）或对特定 GCS 桶、Secret Manager 密钥、Pub/Sub 主题授予单独的权限，而不是在 VM 范围上做粗粒度的开关。
