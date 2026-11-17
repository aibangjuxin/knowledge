# Q

我们知道在GCP的GKE 中有个很重要的东西就是workload identify ,比如我的Pod想要启动,我们会创建一个GKE 的SA,然后把这个GKE SA annotate 到一个 GCP的Service Account.我现在比如Pod本身需要有多个权限,一般怎么处理?比如我这个Pod既要连Cloud SQL,又要连GCP Secret Manage. 还有比如Recaptcha 那么这些IAM的角色和过程是怎样的.涉及命令帮我完善出来 梳理整个流程
其实整个过程可以说就是GKE SA只能Annotate到一个GCP SA,然后让这个GCP的SA去绑定对应的权限或者Role?
另外需要考虑这种情况
如果 GCP SA（如 my-app-gcp-sa@[PROJECT_ID].iam.gserviceaccount.com）需要访问其他 Google Cloud 项目的资源（如 Cloud SQL），还需要额外的跨项目权限配置

# A

我来帮你梳理使用 GKE Workload Identity 配置多个权限的完整流程。

```bash
# 1. 首先创建 GCP Service Account (如果还没有的话)
export PROJECT_ID="your-project-id"
export GCP_SA_NAME="my-app-gcp-sa"

gcloud iam service-accounts create $GCP_SA_NAME \
    --project=$PROJECT_ID \
    --display-name="My Application SA"

# 2. 为 GCP SA 授予需要的权限

# Cloud SQL 访问权限
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$GCP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/cloudsql.client"

# Secret Manager 访问权限
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$GCP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

# reCAPTCHA Enterprise 访问权限
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$GCP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/recaptchaenterprise.agent"

# 3. 创建 Kubernetes Service Account
export K8S_NAMESPACE="my-namespace"
export KSA_NAME="my-app-ksa"

kubectl create namespace $K8S_NAMESPACE
kubectl create serviceaccount $KSA_NAME --namespace $K8S_NAMESPACE

# 4. 配置 IAM 策略绑定，允许 KSA 扮演 GCP SA
gcloud iam service-accounts add-iam-policy-binding \
    $GCP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com \
    --project=$PROJECT_ID \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:$PROJECT_ID.svc.id.goog[$K8S_NAMESPACE/$KSA_NAME]"

# 5. 为 KSA 添加 annotation，关联到 GCP SA
kubectl annotate serviceaccount $KSA_NAME \
    --namespace $K8S_NAMESPACE \
    iam.gke.io/gcp-service-account=$GCP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com
```

# 6. 示例 Pod/Deployment 配置

```yaml
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: $K8S_NAMESPACE
spec:
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: $KSA_NAME  # 使用配置好的 KSA
      containers:
      - name: main
        image: my-app-image:latest
EOF
```

# 7. 跨项目访问配置（如需要）

export OTHER_PROJECT_ID="other-project-id"

# 在目标项目中授予权限

```bash
gcloud projects add-iam-policy-binding $OTHER_PROJECT_ID \
    --member="serviceAccount:$GCP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/cloudsql.client"

```

上面的配置流程主要包含以下几个关键点：

1. **单一 GCP SA，多个权限**

   - 你说得对，一个 KSA 只能 annotate 到一个 GCP SA
   - 解决方案是：给这个 GCP SA 授予所有需要的权限（Cloud SQL、Secret Manager、reCAPTCHA 等）
   - 通过 IAM roles 来管理权限，一个 SA 可以拥有多个 role

2. **权限配置步骤**

   - 创建 GCP SA
   - 为 GCP SA 授予所需的每个权限
   - 创建 Kubernetes SA (KSA)
   - 配置 Workload Identity 绑定
   - 添加 annotation 完成关联

3. **跨项目访问**

   - 需要在目标项目中单独授予权限
   - 使用相同的 GCP SA，但在其他项目中添加相应的 IAM 绑定

4. **最佳实践**
   - 遵循最小权限原则
   - 为不同的应用使用不同的 SA
   - 定期审查权限
   - 使用 IAM 条件来限制访问范围（如需要）

需要注意的是，所有这些权限都是通过同一个 GCP SA 来管理的，这样可以简化配置，但也意味着所有使用这个 KSA 的 Pod 都会继承所有权限。如果需要更细粒度的权限控制，可以考虑为不同的功能模块使用不同的 SA。
