以下是关于Google Kubernetes Engine (GKE)中Workload Identity的总结:

## Workload Identity概述

Workload Identity是GKE中推荐的一种安全访问Google Cloud服务的方式。它允许在GKE集群中运行的工作负载以安全和可管理的方式访问Google Cloud服务[1][4]。

## Workload Identity的作用

1. **提高安全性**:
   - 消除了管理服务账号密钥的开销和安全风险[4]。
   - 使用短期凭证,有效期仅几小时,大大减少了凭证被滥用的风险[4]。

2. **简化身份管理**:
   - 建立Kubernetes服务账号(KSA)和Google服务账号(GSA)之间的关系[3]。
   - 允许GKE工作负载模拟预定义的Google Cloud IAM服务账号[2]。

3. **实现最小权限原则**:
   - 为集群中的每个应用程序分配不同的、细粒度的身份和授权[1][4]。
   - 比使用GKE节点的服务账号更符合最小权限原则[4]。

4. **简化配置**:
   - 无需手动配置或使用不太安全的方法(如服务账号密钥文件)[1]。

5. **自动化凭证管理**:
   - Google负责管理凭证,减轻了管理服务账号密钥的负担[4]。

## 工作原理

1. 在启用Workload Identity的集群中,每个工作负载都可以使用Kubernetes服务账号来模拟Google服务账号[2]。

2. GKE为集群创建一个固定的workload identity pool,格式为`PROJECT_ID.svc.id.goog`[1]。

3. GKE元数据服务器拦截凭证请求,与Kubernetes API服务器和Security Token Service交互,为工作负载提供短期的联合访问令牌[1]。

总之,Workload Identity为GKE工作负载提供了一种更安全、更灵活、更易管理的方式来访问Google Cloud服务,同时遵循最小权限原则,提高了整体安全性。

Sources
[1] About Workload Identity Federation for GKE - Google Cloud https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity
[2] Google Kubernetes Engine (GKE) Workload Identity - Cloud Babble https://www.cloudbabble.co.uk/2023-02-17-GKE-Workload-Identity/
[3] Workload Identity for GKE: Analyzing common misconfiguration - DoiT https://www.doit.com/workload-identity-for-gke-analyzing-common-misconfiguration/
[4] GKE Workload Identity - ScaleSec https://scalesec.com/blog/gke-workload-identity/
[5] What is GKE workload identity? - Debricked https://debricked.com/blog/what-is-gke-workload-identity/




GKE (Google Kubernetes Engine) 是 Google 提供的托管 Kubernetes 服务。在 GKE 集群中,有一些默认的服务帐户(Service Accounts,简称 SA)会被创建和使用。

GCP SA (Google Cloud Platform Service Account) 是在 GCP 项目级别创建和管理的服务帐户,通常用于运行 GCP 服务或应用程序,并被授予特定的角色和权限。

GKE SA 则是在 GKE 集群内部创建和使用的服务帐户。它们主要有以下作用:

1. 身份认证和授权
   Kubernetes 使用 GKE SA 对集群内的工作负载(如 Pod)进行身份认证和授权。每个 Pod 都会关联一个 GKE SA,用于访问 Kubernetes API 或其他集群资源。

2. 集群资源访问控制
   通过将适当的 Kubernetes RBAC 角色绑定到 GKE SA 上,可以控制工作负载对集群资源的访问权限。

3. 外部服务访问
   GKE SA 也可以被用于访问 GCP 服务或其他外部服务,比如对象存储、云 SQL 等。可以将 GCP IAM 角色授予 GKE SA,从而获得相应的权限。

4. 机密管理
   Kubernetes 通过将机密(如密码、API 密钥等)绑定到 GKE SA 上,为集群工作负载提供安全的机密管理。

因此,GKE SA 主要在 Kubernetes 集群内部使用,提供身份认证、授权和访问控制功能。而 GCP SA 通常用于在 GCP 项目级别管理和授权资源访问权限。两者结合使用可实现端到端的安全管理。


GCP的Workload Identity的主要作用是提供一种安全且高效的方式来管理Google Cloud Platform（GCP）中应用程序的身份验证和授权。具体来说，它允许在GCP的Kubernetes环境（如GKE集群）中的工作负载，例如Pods，使用Google的IAM（Identity and Access Management）服务帐号进行身份验证，而无需创建和轮换静态的API密钥。

以下是Workload Identity的几个关键作用：

1. **简化身份验证**:
   - Workload Identity允许Kubernetes服务帐号充当IAM服务帐号，这意味着Pods可以自动获得访问Google Cloud API的能力，而不需要手动创建和维护API密钥。

2. **减少安全风险**:
   - 由于不再需要生成和分发静态API密钥，Workload Identity显著降低了密钥被盗用或泄露的风险。这也简化了密钥管理，因为不再需要定期轮换密钥。

3. **提供细粒度的访问控制**:
   - 通过Workload Identity，可以为每个应用或服务分配不同的IAM角色和权限，从而实现更精细的访问控制。这有助于实施最小权限原则，确保每个工作负载只能访问其执行所需资源。

4. **支持外部身份提供者**:
   - Workload Identity还支持与外部身份提供者（IdP）集成，允许使用外部身份验证来颁发访问令牌。这为跨云和混合云环境提供了更灵活的身份验证解决方案。

5. **提高效率和可扩展性**:
   - 由于Workload Identity是基于角色的访问控制（RBAC）的扩展，它允许开发者和管理员更高效地管理大规模环境中的访问权限。

总之，GCP的Workload Identity是一个强大的工具，它通过提供一种安全、灵活且易于管理的方式来验证和授权GCP中的工作负载，从而帮助用户更好地保护和控制对云资源的访问。


Workload Identity in Google Kubernetes Engine (GKE) is a feature that allows individual pods to use a service account to authenticate to Google Cloud APIs. It is a modern way to provision keys for pods running on GKE and provides a secure way for workloads to access Google Cloud resources.

The primary purpose of Workload Identity is to enhance the security of your cloud deployment by providing distinct, fine-grained identities and authorization for each application in your clusters. It replaces the need to use Metadata concealment, which protects sensitive metadata by Workload Identity Federation for GKE.

When you enable Workload Identity Federation for GKE on a clusters, GKE creates a fixed workload identity pool for the clusters's Google Cloud project, registers the GKE clusters as an identity provider in the workload identity pool, and deploys the GKE metadata server on every node. This allows IAM to understand and trust Kubernetes credentials.

To provide access with Workload Identity Federation for GKE, you create an IAM allow policy that grants access on a specific Google Cloud resource to a principal that corresponds to your application's identity. For example, you could give read permissions on a Cloud Storage bucket to all Pods that use the database-reader Kubernetes ServiceAccount.

In your IAM policy, you refer to a Kubernetes resource by using an IAM principal identifier to select the resource. This identifier has the following syntax: PREFIX://iam.googleapis.com/projects/1234567890/locations/global/workloadIdentityPools/example-project.svc.id.goog/

To use Workload Identity Federation for GKE from your code, you authenticate to Google Cloud services from your code using the same process as authenticating using the Compute Engine default service account. When you use Workload Identity Federation for GKE, your requests to the instance metadata server are routed to the GKE metadata server.

Workload Identity Federation for GKE allows GKE to assert Kubernetes service account identities that can be authenticated and authorized to access Google Cloud resources. It is a recommended way for your workloads running on GKE to securely authenticate to supported Google Cloud APIs.

In summary, Workload Identity in GKE is a powerful feature that provides secure and fine-grained access control for workloads running on GKE to Google Cloud resources. It is a modern way to provision keys for pods and enhances the security of your cloud deployment.

Citations:
[1] https://www.ibm.com/docs/el/aix/7.1?topic=tuning-tcp-large-send-offload
[2] https://www.googlecloudcommunity.com/gc/Google-Kubernetes-Engine-GKE/Unable-to-authenticate-to-Artifact-Registry-using-Workload/m-p/698807
[3] https://debricked.com/blog/what-is-gke-workload-identity/
[4] https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity
[5] https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity



Google Kubernetes Engine (GKE) 中的工作负载身份功能允许各个 Pod 使用服务帐号对 Google Cloud API 进行身份验证。这是为 GKE 上运行的 Pod 提供密钥的一种现代方式，并为工作负载访问 Google Cloud 资源提供了一种安全的方式。

工作负载身份的主要目的是通过为集群中的每个应用程序提供独特的、细粒度的身份和授权来增强云部署的安全性。它取代了使用元数据隐藏的需要，元数据隐藏通过 Workload Identity Federation for GKE 保护敏感元数据。

当您在集群上启用 GKE 的工作负载联合身份验证时，GKE 会为集群的 Google Cloud 项目创建固定工作负载身份池，将 GKE 集群注册为工作负载身份池中的身份提供商，并在每个节点上部署 GKE 元数据服务器。这使得 IAM 能够理解并信任 Kubernetes 凭证。

要通过 Workload Identity Federation for GKE 提供访问权限，您需要创建一个 IAM 允许政策，将特定 GCP 资源的访问权限授予与您的应用程序身份对应的委托人。例如，您可以向使用数据库读取器 Kubernetes ServiceAccount 的所有 Pod 授予对 Cloud Storage 存储桶的读取权限。

在您的 IAM 策略中，您可以通过使用 IAM 委托人标识符来选择资源来引用 Kubernetes 资源。此标识符具有以下语法： PREFIX://iam.googleapis.com/projects/1234567890/locations/global/workloadIdentityPools/example-project.svc.id.goog/

要从您的代码使用 Workload Identity Federation for GKE，您需要从您的代码向 Google Cloud 服务进行身份验证，其流程与使用 Compute Engine 默认服务帐号进行身份验证的流程相同。当您使用 Workload Identity Federation for GKE 时，您对实例元数据服务器的请求将被路由到 GKE 元数据服务器。

GKE 的工作负载身份联合允许 GKE 断言 Kubernetes 服务帐号身份，这些身份可以经过身份验证和授权以访问 GCP 资源。对于在 GKE 上运行的工作负载来说，建议使用这种方法来安全地向受支持的 Google Cloud API 进行身份验证。

总之，GKE 中的工作负载身份是一项强大的功能，可为 GKE 上运行的工作负载提供对 Google Cloud 资源的安全且细粒度的访问控制。这是一种为 Pod 提供密钥的现代方法，可增强云部署的安全性。



GKE 的工作负载身份 (Workload Identity) 是一种机制,允许 Kubernetes 工作负载 (如 Pod) 直接使用 Google Cloud 服务帐户的身份和权限,而无需管理和分发私有密钥。它提供了以下主要优势:

1. **简化服务帐户管理**
   在没有工作负载身份的情况下,您需要手动创建密钥并将其安全地分发和轮换到每个 Pod 中。使用工作负载身份,您可以将 Kubernetes 服务帐户关联到 GCP 服务帐户,从而避免直接处理密钥。

2. **提高安全性**
   使用工作负载身份时,不再需要将敏感凭据存储在容器映像或机密中。这降低了凭据暴露和滥用的风险。

3. **访问控制**
   通过工作负载身份,您可以为特定的 Kubernetes 服务帐户授予访问 GCP 资源的权限,从而实现细粒度的访问控制。

4. **审计跟踪**
   工作负载身份允许所有活动都由 GCP 审计跟踪记录,提高了可审计性和合规性。

你提到的情况是正确的,即使没有为 Kubernetes 服务帐户配置工作负载身份,Pod 仍然可以启动和运行。但是,如果 Pod 需要访问 GCP 服务 (如 Cloud Storage、Pub/Sub 等),而没有配置工作负载身份,则必须以其他方式提供凭据,例如在 Pod 中存储服务帐户密钥。

因此,工作负载身份不是 Pod 启动和运行的硬性要求,但它为您提供了一种安全、方便的方式来管理 GCP 服务帐户凭据,并向工作负载授予访问 GCP 资源的权限。如果您的应用程序需要访问 GCP 服务,并且希望简化凭据管理和提高安全性,那么配置工作负载身份就是一个很好的选择



在 GCP 工程中，您可以通过以下两种方式来获取哪些 GCP 服务账户具有 `iam.workloadIdentityUser` 权限：

**方法一：使用 IAM Policy Analyzer**

1. 访问 IAM Policy Analyzer: [https://cloud.google.com/policy-intelligence/docs/policy-analyzer-overview](https://cloud.google.com/policy-intelligence/docs/policy-analyzer-overview)。
2. 选择您的 GCP 工程。
3. 在 **Policy** 选项卡中，输入以下政策规则：

```
roles/iam.workloadIdentityUser
```

4. 点击 **Analyze** 按钮。

IAM Policy Analyzer 将列出所有具有 `iam.workloadIdentityUser` 权限的 GCP 服务账户。

**方法二：使用 gcloud 命令行工具**

1. 安装并配置 gcloud 命令行工具。
2. 使用以下命令列出所有具有 `iam.workloadIdentityUser` 权限的 GCP 服务账户：

```
gcloud projects get-iam-policy project-id --format json | jq '.bindings[].role == "roles/iam.workloadIdentityUser" | .[] | .members[]'
```

其中，`project-id` 是您的 GCP 工程 ID。

以下是一些额外的提示：

* 您可以使用 `--filter` 标志来缩小搜索范围。例如，要列出具有 `iam.workloadIdentityUser` 权限且名称以 `service-account-` 开头的服务账户，可以使用以下命令：

```
gcloud projects get-iam-policy project-id --filter 'name~^service-account-' --format json | jq '.bindings[].role == "roles/iam.workloadIdentityUser" | .[] | .members[]'
```

* 您可以使用 `--only-policies` 标志来仅列出与 IAM 政策相关的结果。


You are correct that the `iam.workloadIdentityUser` role is not a predefined IAM role, and therefore it cannot be queried using the methods described in my previous response. The `iam.workloadIdentityUser` role is a custom role that is specifically designed for use with Workload Identity.

To query for service accounts that have the `iam.workloadIdentityUser` role, you can use the following method:

**Method 1: Use the gcloud SDK**

1. Install and configure the gcloud SDK.
2. Use the following command to list all service accounts in your project that have the `iam.workloadIdentityUser` role:

```bash
gcloud projects list-iam-bindings project-id \
  --role="roles/iam.workloadIdentityUser" \
  --format="json" | jq '.bindings[].members[]'
```

This command will print a JSON array of service account names.

**Method 2: Use the IAM API**

1. Make an authenticated request to the IAM API using the following method:

```
GET https://iam.googleapis.com/v1/projects/{project-id}/policies
```

Replace `{project-id}` with your project ID.

2. Parse the JSON response and look for bindings that have the following structure:

```json
{
  "role": "roles/iam.workloadIdentityUser",
  "members": [
    "serviceAccount:{project-id}.svc.id.goog[{namespace}/{service-account-name}]"
  ]
}
```

The `{namespace}/{service-account-name}` value is the name of the Kubernetes service account that is bound to the service account.

**Additional notes:**

* You can use the `--filter` flag to narrow down the search results. For example, to list service accounts that have the `iam.workloadIdentityUser` role and are located in the `default` namespace, you can use the following command:

```bash
gcloud projects list-iam-bindings project-id \
  --role="roles/iam.workloadIdentityUser" \
  --filter="resource=projects/project-id/namespaces/default" \
  --format="json" | jq '.bindings[].members[]'
```

* You can use the `--only-policies` flag to only list results that are related to IAM policies.

I hope this helps!


有几种方法可以获取哪些Google Cloud服务帐户具有`iam.workloadIdentityUser`权限:

1. **使用gcloud命令行工具**

您可以使用`gcloud`命令列出项目中所有服务帐户及其权限。以下命令将列出项目ID为`your-project-id`的项目中所有服务帐户及其权限:

```
gcloud projects get-iam-policy your-project-id \
  --flatten="bindings[].members" \
  --format='table(bindings.role)' \
  --filter="bindings.members:serviceAccount"

gcloud projects get-iam-policy your-project-id \
  --flatten="bindings[].members" \
  --format='table(bindings.role,bindings.members)' \
  --filter="bindings.members:serviceAccount"

```

在输出结果中,查找具有`roles/iam.workloadIdentityUser`角色的服务帐户。

2. **通过GCP控制台**

在GCP控制台中,进入IAM & Admin -> IAM页面,您可以查看项目级别和特定资源级别的权限绑定情况。在成员列中,过滤"服务账号"类型即可看到所有服务帐户,并查看其权限。

3. **使用Google Cloud APIs**

您可以使用Cloud Resource Manager API的`projects.getIamPolicy`方法来检索项目的IAM策略,包括绑定的服务帐户及其权限。具体做法可以参考官方文档。

4. **使用第三方工具**

一些第三方开源工具如forseti-security也能够扫描GCP项目并生成包含服务帐户权限的报告。

需要注意的是,`iam.workloadIdentityUser`权限是运行工作负载时使用工作负载身份识别所需的最低权限。拥有此权限的服务帐户数量应尽量控制在必要的范围内,以降低安全风险。
