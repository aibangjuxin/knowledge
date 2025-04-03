
- [get-iam-policy](#get-iam-policy)
- [add-iam-policy-binding](#add-iam-policy-binding)
- [iam.serviceAccountKeyAdmin](#iamserviceaccountkeyadmin)
- [列出 my-service-account 服务账号所分配的所有角色：get-iam-policy](#列出-my-service-account-服务账号所分配的所有角色get-iam-policy)
- [kms](#kms)
- [gcloud kms decrypt](#gcloud-kms-decrypt)
- [other](#other)


# get-iam-policy
查询指定 GCP 项目中，指定服务账号（例如：sa@$project）所拥有的 IAM 角色

	1.	gcloud projects get-iam-policy <project_id>:
	•	gcloud：Google Cloud CLI 的命令。
	•	projects get-iam-policy：表示要获取指定 GCP 项目的 IAM 策略。
	•	<project_id>：你要查询的 GCP 项目的 ID

  2.	--flatten="bindings[].members":
	•	--flatten: 将嵌套的 JSON 输出结构展平。
	•	bindings[].members： 指定展开 IAM 策略中 bindings 数组中的 members 字段。 bindings 包含 role 以及其关联的成员。members 则包含了成员的具体信息。此操作后，可以将不同的 members 的信息提取出来，更方便地进行过滤和格式化
	3.	--format="table(bindings.role)":
	•	--format: 指定输出格式。
	•	table(bindings.role)： 表示将输出格式化为表格，只显示 bindings 中的 role 字段。
	4.	--filter="bindings.members:serviceAccount:gcesa":
	•	--filter: 用于过滤输出结果。
	•	bindings.members:serviceAccount:gcesa：表示只显示 bindings 中 members 字段包含特定的服务账号的条目。
	•	serviceAccount: 指定成员的类型是服务账号。


Verify IAM policies:

```bash
gcloud iam service-accounts get-iam-policy \
    aibang-cn-instance-sa@project-dev.iam.gserviceaccount.com
```

```bash
gcloud projects get-iam-policy $project \
  --flatten="bindings[].members" \
  --format="table(bindings.role)" \
  --filter="bindings.members:serviceAccount:cloud-sql-sa@$project.iam.gserviceaccount.com"
```

# add-iam-policy-binding
于为服务账号添加身份和访问管理 (IAM) 策略绑定的命令
gcloud iam service-accounts add-iam-policy-binding SERVICE_ACCOUNT --member=MEMBER --role=ROLE [--condition=CONDITION ...] [GCLOUD_WIDE_FLAG ...]

其中，
- SERVICE_ACCOUNT 是要添加策略绑定的服务账号的名称或 ID。
- --member 参数指定了要将绑定添加到的成员。
  - 成员可以是特定用户、
  - 服务账号、
  - Google 群组或域。
- --role 参数指定了要给成员分配的角色，例如 roles/storage.admin。

以下是一个添加 roles/storage.admin 角色到 my-service-account 服务账号的示例命令：

gcloud iam service-accounts add-iam-policy-binding my-service-account --member=user:example@gmail.com --role=roles/storage.admin

此命令将 roles/storage.admin 角色绑定到 my-service-account 服务账号上，以授予 example@gmail.com 用户对 Cloud Storage 的管理员权限。

命令还支持条件参数，例如 --condition=title:"example"，用于针对特定条件限制策略绑定。例如，以下命令将 roles/storage.objectViewer 角色绑定到 my-service-account 服务账号，并限制访问名为 example-bucket 的存储桶：

gcloud iam service-accounts add-iam-policy-binding my-service-account --member=user:example@gmail.com --role=roles/storage.objectViewer --condition=title:"example-bucket"


gcloud iam service-accounts add-iam-policy-binding my-service-account --member='serviceAccount:' --role=roles/iam.serviceAccountKeyAdmin


# iam.serviceAccountKeyAdmin
 在 GCP 中，roles/iam.serviceAccountKeyAdmin 是一种角色，
 用于授予用户管理服务账号密钥的权限。具体而言，具有 roles/iam.serviceAccountKeyAdmin 角色的用户可以创建、列出、删除和获取服务账号密钥，
 以及将密钥添加到服务账号中
- [ ] 要查询哪些服务账号拥有 roles/iam.serviceAccountKeyAdmin 角色，您可以使用以下命令：
gcloud projects get-iam-policy [PROJECT_ID] --flatten="bindings[].members" --format='table(bindings.members[],bindings.role)' --filter="bindings.role:roles/iam.serviceAccountKeyAdmin"
将 [PROJECT_ID] 替换为您要查询的 GCP 项目的 ID。该命令将返回一个表格，其中包含已分配 roles/iam.serviceAccountKeyAdmin 角色的服务账号的成员名称和角色名称。
请注意，为了运行此命令，您需要具有适当的 GCP IAM 权限，例如 resourcemanager.projects.getIamPolicy 权限。如果您没有这些权限，则可能无法成功运行该命令。
- [ ] 命令会列出拥有该角色的服务账号的邮箱
gcloud iam service-accounts list --format="value(email)" --filter="roles/iam.serviceAccountKeyAdmin"

对列出的每个服务账号获取其角色
gcloud iam service-accounts get-iam-policy [SERVICE_ACCOUNT_EMAIL] --format="table(bindings.role)"

- [ ] gcloud iam service-accounts list
```bash
gcloud iam service-accounts list \
  --filter="roles/iam.serviceAccountKeyAdmin" \
  --project=[PROJECT_ID]

如果您只想查看服务账号的邮箱地址，可以在命令中添加 --format="value(email)" 参数，例如：

gcloud iam service-accounts list \
  --filter="roles/iam.serviceAccountKeyAdmin" \
  --format="value(email)" \
  --project=[PROJECT_ID]

```

- [ ] Google Bard
命令将列出拥有 roles/iam.serviceAccountKeyAdmin 角色的所有服务帐户
gcloud iam roles list --filter="roles/iam.serviceAccountKeyAdmin" --project <project_id>

您还可以使用以下命令查询特定服务帐户是否拥有 roles/iam.serviceAccountKeyAdmin 角色
gcloud iam roles list --filter="roles/iam.serviceAccountKeyAdmin" --member=<service_account_email> --project <project_id>

# 列出 my-service-account 服务账号所分配的所有角色：get-iam-policy 
查看一个Service Account拥有哪些Role,
gcloud iam service-accounts get-iam-policy my-service-account
gcloud iam service-accounts get-iam-policy [SA_NAME]@[PROJECT_ID].iam.gserviceaccount.com
gcloud iam service-accounts get-iam-policy [SERVICE_ACCOUNT_EMAIL] --format="table(bindings.role)"
geloud projects get-iam-policy $project --flatten="bindings [].members" | --format="table(bindings.role)" -filter="bindings.members:serviceAccount:$SA_NAME@$project.com"
这个命令会列出Service Account被赋予的所有Role。

该命令将返回服务账号的 IAM 策略，其中包括指定成员及其所分配角色的绑定。在策略中，角色由名称和描述组成，如 roles/storage.admin 和 Storage Admin。如果服务账号没有分配任何角色，则输出结果为空列表。

如果您只想查看服务账号分配了特定角色的绑定，可以使用 --flatten 和 --format 参数来过滤输出结果。例如，以下命令将只显示 my-service-account 服务账号分配的 roles/storage.admin 角色绑定：


gcloud iam service-accounts get-iam-policy my-service-account --flatten="bindings[].members" --format='table(bindings.role)' --filter='bindings.role:roles/storage.admin'
此命令将返回一个表格，其中只显示 roles/storage.admin 角色。如果服务账号没有分配该角色，则输出结果为空列表。

eg:
$ gcloud iam service-accounts get-iam-policy lex-test-rt-sa@lex-1234567-k8s-dev.iam.gserviceaccount.com
bindings:
- members:
  - group:gcp.lex-1234567-k8s-dev.fix-team-priv@snsyr.com
  - group:gcp.lex-1234567-k8s-dev.fix-team@snsyr.com
  - serviceAccount:lex-test-manage-sa@lex-1234567-k8s-dev.iam.gserviceaccount.com
  role: roles/iam.serviceAccountUser
- members:
  - serviceAccount:lex-1234567-k8s-dev.svc.id.goog[mac-ea/lex-test-ea-sa]
  - serviceAccount:lex-1234567-k8s-dev.svc.id.goog[mac-pa/lex-test-pa-sa]
  role: roles/iam.workloadIdentityUser
etag: BwXdryuzYTU=
version: 1

# kms
- 查看KMS工程下对应我们的工程的一些

+ gcloud kms keys list --keyring=lex-7654321-open-dev --location=global --project fish-888888-kms-dev
+ gcloud kms keys list --keyring=lex-7654321-open-dev --location=us-laker2 --project fish-888888-kms-dev|grep gke
output: 关注下这个名字 lex-us-gke-lexus  
rojects/fish-888888-kms-dev/locations/us-laker2/keyRings/lex-7654321-open-dev/cryptoKeys/lex-us-gke-lexus    ENCRYPT_DECRYPT  GOOGLE_SYMMETRIC_ENCRYPTION  HSM               

eg: 
- keyring 定义了自己的工程
- project 是KMS的独立工程

- 我想要查看我们工程的账户被分配的Role 如下说明我们的账户已经具备cloudkms.cryptoKeyDecrypter cloudkms.cryptoKeyEncrypter 
get-iam-policy
- gcloud kms keys get-iam-policy projects/fish-888888-kms-dev/locations/us-laker2/keyRings/lex-7654321-open-dev/cryptoKeys/lex-us-gke-lexus
  
bindings:
- members:
  - serviceAccount:service-1234567890@container-engine-robot.iam.gserviceaccount.com
  role: roles/cloudkms.cryptoKeyDecrypter
- members:
  - serviceAccount:service-1234567890@container-engine-robot.iam.gserviceaccount.com
  role: roles/cloudkms.cryptoKeyEncrypter
- members:
  - serviceAccount:lex-test-dev@lex-10726045-abcdefg-dev.iam.gserviceaccount.com
  role: roles/cloudkms.cryptoKeyEncrypterDecrypter
etag: BwXWGY5gb5g=
version: 1


☐ 查看对应的版本
+ gcloud kms keys versions list --keyring=lex-7654321-open-dev --location=us-laker2 --key=lex-us-gke-lexus --project=fish-888888-kms-dev
NAME                                                                                                                                 STATE
projects/fish-888888-kms-dev/locations/us-laker2/keyRings/lex-7654321-open-dev/cryptoKeys/lex-us-gke-lexus/cryptoKeyVersions/1  DISABLED
projects/fish-888888-kms-dev/locations/us-laker2/keyRings/lex-7654321-open-dev/cryptoKeys/lex-us-gke-lexus/cryptoKeyVersions/2  DISABLED


☐ 启用对应的版本

gcloud kms keys versions enable 5 --keyring=lex-7654321-open-dev --location=us-laker2 --key=lex-us-gke-lexus --project=fish-888888-kms-dev
gcloud kms keys versions enable 5 --keyring=lex-7654321-open-dev --location=us-laker2 --key=lex-us-gke-lexus --project=fish-888888-kms-dev
ERROR: (gcloud.kms.keys.versions.enable) PERMISSION_DENIED: Permission 'cloudkms.cryptoKeyVersions.update' denied on resource 'projects/fish-888888-kms-dev/locations/us-laker2/keyRings/lex-7654321-open-dev/cryptoKeys/lex-us-gke-lexus/cryptoKeyVersions/5' (or it may not exist).




# gcloud kms decrypt 
- abc.cer.en 加密的文件
- abc.cer 解密的输出文件 
- --key: The name of the Cloud KMS key to be used for decryption. This key must be in the same project as the project ID specified with the --project flag.
- 用于解密的云KMS密钥的名称。此密钥必须与指定的项目ID位于同一项目中
- --keyring: The name of the Cloud KMS key ring where the key is located. This key ring must also be in the same project as the project ID specified with the --project flag.
- 密钥所在的Cloud KMS密钥环的名称。此密钥环还必须与使用--project标志指定的项目ID在同一项目中
gcloud kms decrypt --project ${project_kms} --ciphertext-file=/etc/pki/tls/certs/abc.cer.en --plaintext-file=/etc/pki/tls/certs/abc.cer --key=${key} --keyring=${project_keyring} --location=global

# other
- https://github.com/LeCoupa/awesome-cheatsheets/blob/master/tools/gcp.md

- get container name
kubectl get deployment <deployment-name> -o jsonpath="{.spec.template.spec.containers[*].name}"
