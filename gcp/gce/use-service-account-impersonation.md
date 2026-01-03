# Google服务账户模拟

配置了服务账户模拟，

使得主服务账户 service-account-a@project.iam.gserviceaccount.com

能够生成目标服务账户environment-b-rt-sa@project.iam.gserviceaccount.com

的访问令牌，并使用该令牌访问密钥和其他资源。

这种方法可以在不直接授予主服多账户访问叔限的情况下安全的访问和管理GCP资源


Google服务账户模拟

https://cloud.google.com/docs/authentication/use-service-account-impersonation?hl=zh-cn

如何使用 Google 服务账户模拟。

使用 Google 服务账户模拟可以让一个服务账户（模拟账户）获取另一个 Google 账户（被模拟账户）的权限，从而代表被模拟账户执行操作

给我一个具体的例子,比如一个A账户如何获取B账户的权限,从而代表B账户去执行只有B账户拥有的权限?


使用 Google 服务账户模拟的核心步骤是通过 **IAM角色绑定** 和 **模拟请求**，让服务账户 A 能够代表服务账户 B 执行操作。以下是具体步骤和示例实现：


我想实现的一个场景是

B用户有 roles/secretmanager.secretVersionManager

A用户有roles/secretmanager.secretAccessor 但是B用户没有roles/secretmanager.secretVersionManager


要模拟实现 **A 用户使用服务账户 B 的 `roles/secretmanager.secretVersionManager` 权限**，以下是具体步骤：

---
# GCP secret manager 模拟
### 场景说明

- **A 用户**：有 `roles/secretmanager.secretAccessor`（可以读取 Secret）。
- **B 用户**：没有直接的 `roles/secretmanager.secretAccessor`，但有 `roles/secretmanager.secretVersionManager`（可以管理 Secret 版本，如启用、禁用或删除版本）。

目标：A 用户通过模拟 B 来管理 Secret 版本，而不直接授予 A `roles/secretmanager.secretVersionManager`。

---

### 配置步骤

#### 1. 授予 A 模拟 B 的权限
通过 IAM 配置，让 **A** 能模拟 **B**：

```bash
gcloud iam service-accounts add-iam-policy-binding \
  service-account-b@project-id.iam.gserviceaccount.com \
  --member="serviceAccount:service-account-a@project-id.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"
```

**解释**:
- **`roles/iam.serviceAccountTokenCreator`**：允许 A 生成 B 的访问令牌。
- **`service-account-b`** 是被模拟的服务账户。

---

#### 2. 确保 B 用户有管理 Secret 版本的权限
授予 B 用户 `roles/secretmanager.secretVersionManager`：

```bash
gcloud secrets add-iam-policy-binding secret-id \
  --member="serviceAccount:service-account-b@project-id.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretVersionManager"
```

**解释**:
- **`secret-id`**：目标 Secret 的名称。
- B 将有权限管理 Secret 版本。

---

#### 3. 确保 A 用户没有直接的版本管理权限
验证 A 的权限，确保只拥有 `roles/secretmanager.secretAccessor`：

```bash
gcloud secrets add-iam-policy-binding secret-id \
  --member="serviceAccount:service-account-a@project-id.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

---

#### 4. 使用 A 模拟 B 执行操作

##### （1）通过 `gcloud` CLI 模拟
```bash
gcloud auth activate-service-account service-account-a@project-id.iam.gserviceaccount.com --key-file=/path/to/key.json

gcloud auth print-access-token \
  --impersonate-service-account=service-account-b@project-id.iam.gserviceaccount.com | \
xargs -I {} curl -H "Authorization: Bearer {}" \
"https://secretmanager.googleapis.com/v1/projects/project-id/secrets/secret-id/versions/5:setEnabled"
```

- **解释**:
  - `--impersonate-service-account`: 使用 A 模拟 B。
  - API 调用将指定 Secret 版本 5 的状态设置为启用。

##### （2）通过 Python 模拟
以下是使用 Python 的完整示例：

```python
from google.auth.transport.requests import Request
from google.oauth2.service_account import Credentials
from google.auth import impersonated_credentials
from googleapiclient.discovery import build

# 1. 使用服务账户 A 的密钥文件加载初始凭据
service_account_file = "/path/to/service-account-a-key.json"
target_account = "service-account-b@project-id.iam.gserviceaccount.com"

credentials = Credentials.from_service_account_file(
    service_account_file,
    scopes=["https://www.googleapis.com/auth/cloud-platform"]
)

# 2. 模拟服务账户 B
impersonated_creds = impersonated_credentials.Credentials(
    source_credentials=credentials,
    target_principal=target_account,
    target_scopes=["https://www.googleapis.com/auth/cloud-platform"]
)

# 3. 使用模拟的 B 凭据访问 Secret Manager
secret_manager_service = build("secretmanager", "v1", credentials=impersonated_creds)

# 目标 Secret 及版本
secret_name = "projects/project-id/secrets/secret-id/versions/5"

# 设置版本状态为启用
request = secret_manager_service.projects().secrets().versions().patch(
    name=secret_name,
    body={"state": "ENABLED"}
)
response = request.execute()
print("Secret version enabled:", response)
```

---

### 验证配置

1. **确保 B 能管理 Secret 版本**：
   - 独立验证 B 是否具有 `roles/secretmanager.secretVersionManager` 权限。

2. **确保 A 无法直接管理版本**：
   - 尝试用 A 单独调用管理版本 API，应返回权限不足的错误。

3. **通过模拟成功执行操作**：
   - 确认 A 模拟 B 后，可以完成版本管理操作。

---

### 流程图

```mermaid
graph TD
    A[服务账户 A] -->|模拟 B| B[服务账户 B]
    B -->|管理版本| C[Secret Manager]
```

---

通过这种方式，可以实现 **服务账户 A 通过模拟 B 使用 B 的权限**，同时分离职责并确保最小权限原则。


# Buckets 模拟

### 示例场景

- 服务账户 **`service-account-a@project-id.iam.gserviceaccount.com`**（简称 A）希望模拟服务账户 **`service-account-b@project-id.iam.gserviceaccount.com`**（简称 B）。
- 服务账户 B 有权限访问 Google Cloud Storage（GCS），比如列出某个存储桶中的文件。
- 服务账户 A 没有 GCS 访问权限，需要通过模拟 B 来执行这个操作。

---

### 配置步骤

#### 1. 授予服务账户 A 模拟权限
通过 IAM 授予 **`service-account-a`** 对 **`service-account-b`** 的模拟权限：

```bash
gcloud iam service-accounts add-iam-policy-binding \
  service-account-b@project-id.iam.gserviceaccount.com \
  --member="serviceAccount:service-account-a@project-id.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"
```

**解释**:
- **`roles/iam.serviceAccountTokenCreator`**：允许 A 为 B 创建访问令牌，从而模拟 B。
- **`add-iam-policy-binding`**：将权限绑定到被模拟的服务账户（B）。

---

#### 2. 验证服务账户 A 和 B 的权限

- 服务账户 **B** 需要有目标操作权限（例如访问 GCS 的权限）：
  ```bash
  gcloud projects add-iam-policy-binding project-id \
    --member="serviceAccount:service-account-b@project-id.iam.gserviceaccount.com" \
    --role="roles/storage.objectViewer"
  ```

- 服务账户 **A** 仅需要模拟权限。

---

#### 3. 使用服务账户 A 模拟 B 执行操作

在程序中或命令行中模拟服务账户 B 并使用其权限。以下是使用 Python 和 Google Cloud SDK 的示例：

##### （1）通过 `gcloud` CLI 执行
使用服务账户 A 模拟 B 列出 GCS 存储桶中的文件：

```bash
gcloud auth activate-service-account service-account-a@project-id.iam.gserviceaccount.com --key-file=/path/to/key.json

gcloud auth print-access-token \
  --impersonate-service-account=service-account-b@project-id.iam.gserviceaccount.com | \
xargs -I {} curl -H "Authorization: Bearer {}" "https://storage.googleapis.com/storage/v1/b/your-bucket-name/o"
```

##### （2）通过 Python 执行
安装依赖库：

```bash
pip install google-auth google-auth-httplib2 google-api-python-client
```

代码示例：

```python
from google.auth.transport.requests import Request
from google.oauth2.service_account import Credentials
from google.auth import impersonated_credentials
from googleapiclient.discovery import build

# 1. 使用服务账户 A 的密钥文件加载初始凭据
service_account_file = "/path/to/service-account-a-key.json"
target_account = "service-account-b@project-id.iam.gserviceaccount.com"

credentials = Credentials.from_service_account_file(
    service_account_file,
    scopes=["https://www.googleapis.com/auth/cloud-platform"]
)

# 2. 模拟服务账户 B
impersonated_creds = impersonated_credentials.Credentials(
    source_credentials=credentials,
    target_principal=target_account,
    target_scopes=["https://www.googleapis.com/auth/cloud-platform"]
)

# 3. 使用模拟的 B 凭据访问 GCS
storage_service = build("storage", "v1", credentials=impersonated_creds)
bucket_name = "your-bucket-name"

response = storage_service.objects().list(bucket=bucket_name).execute()
print("Objects in bucket:")
for obj in response.get("items", []):
    print(obj["name"])
```

---

### 工作原理
1. **服务账户 A 的模拟权限**：通过 `roles/iam.serviceAccountTokenCreator` 授权，A 可以生成 B 的访问令牌。
2. **服务账户 B 的资源访问权限**：B 必须具备对目标资源的访问权限（例如 `roles/storage.objectViewer`）。
3. **模拟过程**：服务账户 A 使用模拟凭据代表服务账户 B 进行 API 调用。

---

### 流程图

```mermaid
graph TD
    A[服务账户 A] -->|模拟 B| B[服务账户 B]
    B -->|访问权限| C[目标资源: GCS 存储桶]
```

---

通过这种方式，可以安全地实现服务账户模拟，从而分离职责和权限管理，同时最小化直接暴露敏感服务账户（B）的风险。





# Claude

我理解您想要A账户通过服务账户模拟来获取B账户的 Secret Manager 相关权限。让我帮您详细说明这个过程。



```python
# 1. 首先设置服务账户和权限
'''
# 创建服务账户A和B
gcloud iam service-accounts create service-account-a \
    --display-name="Service Account A"

gcloud iam service-accounts create service-account-b \
    --display-name="Service Account B"

# 为服务账户B授予Secret Manager管理员角色
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:service-account-b@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretVersionManager"

# 为服务账户A授予Secret Manager访问者角色
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:service-account-a@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

# 允许A账户模拟B账户
gcloud iam service-accounts add-iam-policy-binding \
    service-account-b@PROJECT_ID.iam.gserviceaccount.com \
    --member="serviceAccount:service-account-a@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountTokenCreator"
'''

# 2. Python代码实现服务账户模拟
from google.cloud import secretmanager
from google.auth import impersonated_credentials
from google.oauth2 import service_account

# 初始化A账户的凭据
base_credentials = service_account.Credentials.from_service_account_file(
    'service-account-a-key.json'
)

# 创建模拟B账户的凭据
target_scopes = ['https://www.googleapis.com/auth/cloud-platform']
target_principal = 'service-account-b@PROJECT_ID.iam.gserviceaccount.com'

impersonated_credentials = impersonated_credentials.Credentials(
    source_credentials=base_credentials,
    target_principal=target_principal,
    target_scopes=target_scopes,
    lifetime=3600  # 模拟凭据的有效期(秒)
)

# 使用模拟凭据创建Secret Manager客户端
client = secretmanager.SecretManagerServiceClient(
    credentials=impersonated_credentials
)

# 现在可以使用B账户的权限执行操作
def create_secret_version(project_id, secret_id, payload):
    """使用B账户的权限创建新的secret版本"""
    parent = client.secret_path(project_id, secret_id)
    
    # 将数据转换为字节
    payload_bytes = payload.encode('UTF-8')
    
    # 创建secret版本
    version = client.add_secret_version(
        request={
            "parent": parent,
            "payload": {"data": payload_bytes},
        }
    )
    
    print(f"Created secret version: {version.name}")

# 使用示例
project_id = "your-project-id"
secret_id = "your-secret-id"
secret_value = "new-secret-value"

create_secret_version(project_id, secret_id, secret_value)

```

让我为您解释这个实现过程的关键步骤：

1. 权限设置：
- 创建了两个服务账户 A 和 B
- 给账户 B 分配了 `roles/secretmanager.secretVersionManager` 角色
- 给账户 A 分配了 `roles/secretmanager.secretAccessor` 角色
- 给账户 A 授予了模拟账户 B 的权限(`roles/iam.serviceAccountTokenCreator`)

2. 代码实现：
- 先使用账户 A 的凭据初始化
- 创建模拟凭据，指定要模拟的目标账户(B)和所需范围
- 使用模拟凭据创建 Secret Manager 客户端
- 通过模拟获得的权限执行 secret 版本管理操作

这样，虽然账户 A 本身只有 secretAccessor 权限，但通过模拟账户 B，它就可以执行 secretVersionManager 的相关操作了。

需要注意的几点：
1. 确保替换代码中的 PROJECT_ID 为您的实际项目 ID
2. 服务账户密钥文件要妥善保管
3. 模拟凭据有效期默认为1小时，可以根据需要调整

您需要我解释任何具体步骤吗？或者您有其他特定的使用场景需求？


是的,我来帮您梳理这个流程,并提供 gcloud 命令行的实现方式。



```mermaid
flowchart TD
    subgraph "第1步: 创建服务账户"
        A[创建服务账户A] --> B[创建服务账户B]
    end
    
    subgraph "第2步: 配置账户权限"
        B --> C[给账户B授予 Secret Manager 管理员角色]
        B --> D[给账户A授予 Secret Manager 访问者角色]
    end
    
    subgraph "第3步: 配置账户模拟权限"
        D --> E[给账户A授予模拟B的权限]
    end
    
    subgraph "第4步: 使用模拟权限"
        E --> F[使用gcloud命令进行模拟]
        E --> G[使用SDK代码进行模拟]
    end

```

下面是使用 gcloud 命令行实现整个流程的具体步骤：

1. 创建服务账户
```bash
# 创建服务账户A
gcloud iam service-accounts create sa-a \
    --description="Service Account A" \
    --display-name="Service Account A"

# 创建服务账户B
gcloud iam service-accounts create sa-b \
    --description="Service Account B" \
    --display-name="Service Account B"
```

2. 配置账户权限
```bash
# 给账户B授予Secret Manager管理员权限
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:sa-b@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretVersionManager"

# 给账户A授予Secret Manager访问者权限
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:sa-a@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
```

3. 配置账户模拟权限
```bash
# 允许账户A模拟账户B
gcloud iam service-accounts add-iam-policy-binding \
    sa-b@PROJECT_ID.iam.gserviceaccount.com \
    --member="serviceAccount:sa-a@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountTokenCreator"
```

4. 使用模拟权限（有两种方式）

方式1: 直接使用 gcloud 命令行模拟
```bash
# 使用账户A模拟账户B执行命令
gcloud auth activate-service-account sa-a@PROJECT_ID.iam.gserviceaccount.com \
    --key-file=sa-a-key.json

gcloud secrets versions add YOUR_SECRET_NAME \
    --impersonate-service-account=sa-b@PROJECT_ID.iam.gserviceaccount.com \
    --data-file=/path/to/file
```

方式2: 使用临时凭证
```bash
# 获取模拟账户B的临时凭证
gcloud auth print-access-token \
    --impersonate-service-account=sa-b@PROJECT_ID.iam.gserviceaccount.com
```

注意事项：
1. 所有命令中的 PROJECT_ID 需要替换为您的实际项目 ID
2. 服务账户名称 (sa-a, sa-b) 可以根据您的需求修改
3. 确保执行命令的用户有足够的权限
4. 建议在测试环境先验证权限配置是否正确

使用 gcloud 命令行和使用代码实现的主要区别是：
- 命令行更适合临时或者一次性的操作
- 代码实现更适合程序化、自动化的场景
- 命令行操作更直观，便于调试和验证
- 代码实现更灵活，可以集成到应用程序中

您想了解哪个部分的更多细节，或者有特定的使用场景需要讨论吗？