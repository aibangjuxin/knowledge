# Housekeep ImagePullSecrets

## 1. 背景与问题

在 Kubernetes 集群中，为了拉取私有仓库（Private Registry）的镜像，必须在每个 Namespace 下创建对应的 `Secret`（类型为 `kubernetes.io/dockerconfigjson`），并在 ServiceAccount 中引用该 Secret。

**核心痛点**：
*   **重复劳动**：每创建一个新的 Namespace，都需要手动创建 Secret。
*   **维护困难**：如果镜像仓库密码/Token 变更，需要轮询所有 Namespace 更新 Secret。
*   **用户体验差**：用户部署应用时经常忘记配置 `imagePullSecrets`，导致 `ImagePullBackOff` 错误。

**目标**：
*   **短期**：实现 `imagePullSecrets` 的自动化分发与挂载，消除手动操作。
*   **长期**："隐形"化该资源。即对于平台使用者来说，无需感知 `imagePullSecrets` 的存在，Namespace 创建即自动就绪。

## 2. 实践方法 (Practice Method)

为了达成“长期不需要手动管理该资源”的目标，推荐引入 **Secret 自动分发控制器**。这里以 `imagepullsecret-patcher` 为例进行实践。

### 核心原理

通过在集群中部署一个控制器，监听 Namespace 和 Secret 的变化：
1.  **自动分发**：当检测到新 Namespace 创建时，自动将源 Secret（Source Secret）克隆到该 Namespace。
2.  **自动注入**：自动修改该 Namespace 下的默认 ServiceAccount，将克隆的 Secret 加入 `imagePullSecrets` 列表。

```mermaid
graph TD;
    A[管理员维护 Source Secret] -->|更新| B(imagepullsecret-patcher);
    C[新建/现有 Namespace] -->|触发事件| B;
    B -->|1. 复制| D[Namespace 下生成 Secret];
    D -->|2. Patch| E[Default ServiceAccount];
    E -->|3. 自动生效| F[Pod 默认拥有拉取权限];
```

### 实施步骤

#### 步骤 1: 准备源 Secret (Source Secret)

在管理员纳管的空间（如 `kube-system`）创建全局唯一的凭证 Secret。

```bash
# 假设已有 docker login 的 config.json
kubectl create secret docker-registry regcred \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson \
  -n kube-system
```

#### 步骤 2: 部署自动化控制器

应用 `imagepullsecret-patcher` 或类似工具。以下为 GitOps 友好的部署清单示例：

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: imagepullsecret-patcher
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: imagepullsecret-patcher
rules:
- apiGroups: [""]
  resources: ["secrets", "namespaces", "serviceaccounts"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: imagepullsecret-patcher
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: imagepullsecret-patcher
subjects:
- kind: ServiceAccount
  name: imagepullsecret-patcher
  namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: imagepullsecret-patcher
  namespace: kube-system
data:
  config.yaml: |
    source:
      secret:
        name: regcred           # 指向步骤1创建的 secret
        namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: imagepullsecret-patcher
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: imagepullsecret-patcher
  template:
    metadata:
      labels:
        app: imagepullsecret-patcher
    spec:
      serviceAccountName: imagepullsecret-patcher
      containers:
      - name: imagepullsecret-patcher
        image: titansoft/imagepullsecret-patcher:latest
        imagePullPolicy: IfNotPresent
        volumeMounts:
        - name: config
          mountPath: /config
      volumes:
      - name: config
        configMap:
          name: imagepullsecret-patcher
```

#### 步骤 3: 验证

创建一个新的测试 Namespace，无需做任何额外配置，直接检查：

```bash
# 1. 创建 namespace
kubectl create ns test-auto-pull

# 2. 检查 Secret 是否自动生成
kubectl get secret regcred -n test-auto-pull

# 3. 检查 ServiceAccount 是否被 Patch
kubectl get sa default -n test-auto-pull -o yaml
# 输出应包含:
# imagePullSecrets:
# - name: regcred
```

## 3. 长期策略 (Long Term Strategy)

虽然上述方法解决了“手动创建”的问题，但 `imagePullSecrets` 资源本身仍然存在于每个 Namespace 中。如果希望在更底层的层面解决认证问题（即完全不需要 Kubernetes Secret），可以考虑以下方案（取决于基础设施）：

1.  **节点级认证 (Node-Level Cloud Credential)**:
    *   在使用 GKE (Google Kubernetes Engine) 或 EKS (Amazon EKS) 等托管服务时，可以通过节点绑定的 IAM 角色赋予拉取私有镜像仓库（如 GCR/GAR, ECR）的权限。
    *   **优点**：完全不需要在 K8s 层处理 ImagePullSecrets。
    *   **缺点**：仅适用于云厂商自己的镜像仓库，且权限粒度较粗（节点上所有 Pod 都有权限）。

2.  **Kubelet Credential Provider**:
    *   配置 Kubelet 动态获取凭证。
    *   这通常是集群运维/基础设施层面的配置，对应用开发者透明。

**结论**：
对于通用场景和混合云环境，**Secret 自动分发控制器（Practice Method）** 是目前最灵活、兼容性最好的方案，它成功屏蔽了手动管理的复杂性，实现了“逻辑上的”免维护。
