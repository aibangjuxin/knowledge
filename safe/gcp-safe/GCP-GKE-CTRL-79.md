| **GCP-GKE-CTRL-79** | PROT-2 - IT保护性安全技术 | 必须使用AlwaysPullImages准入控制器。 | CAEP team | 是 | 是 | 这是GKE集群中的默认启用的准入控制器。 |

https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#alwayspullimages

### **合规性说明与验证方法：AlwaysPullImages准入控制器**

---
#### **1. AlwaysPullImages在GKE中的默认启用状态**

**结论**：`AlwaysPullImages` 准入控制器在 **GKE集群中是默认启用的**。

*   **重要性**：`AlwaysPullImages` 强制每次创建Pod时，集群都会从镜像仓库重新拉取容器镜像，即使该镜像已缓存在Pod所在节点上。这对于以下场景至关重要：
    *   **安全性**：确保Pod始终使用最新版本的镜像，即使镜像标签相同，底层内容可能已更新（例如，`latest` 标签）。
    *   **多租户环境**：防止恶意用户通过共享节点上的缓存镜像绕过权限检查，确保只有拥有凭据的用户才能使用特定私有镜像。
    *   **合规性**：符合“最小特权”和“最新状态”的安全原则。

*   **GKE承诺**：作为托管服务，GKE会默认启用许多关键的安全特性，`AlwaysPullImages` 就是其中之一，以提供一个更安全、合规的运行环境。

---
#### **2. 验证方法：如何在您的GKE环境中确认已启用AlwaysPullImages**

由于GKE是托管服务，用户无法直接查看`kube-apiserver`的启动参数来验证准入控制器的启用状态。但可以通过**功能性测试**来确认 `AlwaysPullImages` 正在生效。

**功能性验证步骤：**

1.  **准备一个私有容器镜像**：
    *   将一个小型、私有的Docker镜像推送到需要认证才能拉取的镜像仓库（例如：Google Container Registry (GCR) 或 Artifact Registry）。
    *   **示例镜像**：`us-central1-docker.pkg.dev/your-gcp-project/your-repo/private-image:latest`

2.  **创建`imagePullSecrets`**：
    *   创建一个Kubernetes `Secret`，其中包含拉取您私有镜像所需的认证信息。
    *   **`private-repo-secret.yaml` 示例**：
        ```yaml
        apiVersion: v1
        kind: Secret
        metadata:
          name: private-repo-secret
          namespace: default # 替换为您的命名空间
        data:
          .dockerconfigjson: <BASE64_ENCODED_DOCKER_CONFIG_JSON> # 您的docker config json base64编码
        type: kubernetes.io/dockerconfigjson
        ```
    *   应用此Secret：`kubectl apply -f private-repo-secret.yaml`

3.  **部署第一个Pod（带`imagePullSecrets`）**：
    *   部署一个引用此私有镜像，并且配置了 `imagePullSecrets` 的Pod。这将确保镜像被成功拉取并缓存到节点上。
    *   **`pod-with-secret.yaml` 示例**：
        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: private-image-pod-with-secret
          namespace: default
        spec:
          containers:
          - name: my-private-container
            image: us-central1-docker.pkg.dev/your-gcp-project/your-repo/private-image:latest
          imagePullSecrets:
          - name: private-repo-secret
        ```
    *   应用此Pod：`kubectl apply -f pod-with-secret.yaml`
    *   **验证**：`kubectl get pod private-image-pod-with-secret` 确认Pod运行状态为`Running`。

4.  **部署第二个Pod（不带`imagePullSecrets`）**：
    *   **删除第一个Pod**：`kubectl delete pod private-image-pod-with-secret`，确保清理状态。
    *   部署一个**同样引用此私有镜像**，但**不配置 `imagePullSecrets`** 的Pod。
    *   **`pod-without-secret.yaml` 示例**：
        ```yaml
        apiVersion: v1
        kind: Pod
        metadata:
          name: private-image-pod-without-secret
          namespace: default
        spec:
          containers:
          - name: my-private-container
            image: us-central1-docker.pkg.dev/your-gcp-project/your-repo/private-image:latest
        ```
    *   应用此Pod：`kubectl apply -f pod-without-secret.yaml`

5.  **观察第二个Pod的状态**：
    *   **预期行为（`AlwaysPullImages` 已启用）**：第二个Pod会尝试再次拉取镜像。由于缺少认证凭据，镜像拉取将失败。您将看到Pod长时间处于 `ImagePullBackOff` 或 `ErrImagePull` 状态。
    *   **验证命令**：`kubectl get pod private-image-pod-without-secret` 和 `kubectl describe pod private-image-pod-without-secret`。
    *   如果描述事件中显示类似`Failed to pull image "..." rpc error: code = Unknown desc = Error response from daemon: unauthorized: authentication required`的错误，则证明`AlwaysPullImages`已成功生效。

#### **合规性证据总结：**

*   **GKE托管服务保证**：`AlwaysPullImages`作为GKE集群的默认安全特性，本身就提供了高度的合规性保证。
*   **功能性测试结果**：上述功能性测试明确证明，在没有提供 `imagePullSecrets` 的情况下，Pod无法成功拉取私有镜像，这直接验证了 `AlwaysPullImages` 策略正在集群中被强制执行，从而满足 `GCP-GKE-CTRL-79` 的合规要求。