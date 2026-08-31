# 04 · Quick Start —— infra-gcp 5 分钟跑通

> **本节是 infra-gcp profile 视角的"接到业务方需求后,5 分钟内跑完核心步骤"的脚本化参考**
>
> **架构师 lane 边界**:本节给出 `kubectl` / `gcloud` 命令序列供参考,**不是执行脚本**。实际由 infra-gcp 用专属 SA 执行。

---

## 0. 前置条件(必读)

```bash
# 1. infra-gcp profile 必须有专属 GCP SA(参见 ADR-009 §13)
# 路径:/Users/${USER}/.hermes/profiles/infra-gcp/secrets/infra-gcp-sa.json

# 2. SA 必须有以下最小权限:
#    - container.clusters.get
#    - compute.networks.read
#    - container.namespaces.create
#    - container.pods.create / get / list / delete
#    - container.serviceaccounts.create
#    - container.secrets.create
#    - iam.serviceAccounts.getIamPolicy
#    - storage.buckets.create / getIamPolicy / setIamPolicy
#    - resourcemanager.projects.getIamPolicy  (跨 project 验证)

# 3. K8s context 必须指向目标 cluster
gcloud container clusters get-credentials <cluster-name> --region <region>
kubectl config current-context

# 4. GKE cluster 必须启用 Workload Identity Federation
gcloud container clusters describe <cluster-name> --region <region> \
  --format="value(workloadIdentityConfig.workloadPool)"
# 期望返回:PROJECT_ID.svc.id.goog
```

---

## 1. 5 分钟 Quick Start(脚本化)

```bash
#!/bin/bash
# infra-gcp 接到业务方需求后跑这套
# 用法: bash 04-quick-start.sh <namespace> <tenant-id> <bucket-name> <object-prefix>

set -euo pipefail

NS="${1:-api-ns}"
TENANT="${2:-tnt-001}"
BUCKET="${3:-user-data}"
PREFIX="${4:-api-data}"
GKE_PROJECT="master-project"
BUCKET_PROJECT="user-bucket-project"
SA_NAME="api-bucket-writer"

echo "▶ Step 1: 创建 namespace + KSA(在 master-project)"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount "$SA_NAME" -n "$NS" --dry-run=client -o yaml | kubectl apply -f -

echo "▶ Step 2: 绑 WIF annotation(关键!)"
kubectl annotate serviceaccount "$SA_NAME" -n "$NS" \
  iam.gke.io/gcp-service-account="${SA_NAME}@${GKE_PROJECT}.iam.gserviceaccount.com" \
  --overwrite

echo "▶ Step 3: 创建 Bucket(在 user-bucket-project)"
gsutil mb -p "$BUCKET_PROJECT" -c STANDARD -l asia-northeast1 \
  -b on "gs://${BUCKET}"

echo "▶ Step 4: 配 IAM policy(允许 KSA 写指定 prefix)"
cat > /tmp/bucket-iam-policy.json <<EOF
{
  "bindings": [
    {
      "role": "roles/storage.objectCreator",
      "members": [
        "serviceAccount:${GKE_PROJECT}.svc.id.goog[${NS}/${SA_NAME}]"
      ],
      "condition": {
        "title": "${NS}-prefix-only",
        "description": "只允许写 ${PREFIX}/ 前缀",
        "expression": "resource.name.startsWith('projects/_/buckets/${BUCKET}/objects/${PREFIX}/')"
      }
    }
  ]
}
EOF

gcloud storage buckets set-iam-policy "gs://${BUCKET}" /tmp/bucket-iam-policy.json

echo "▶ Step 5: 验证"
kubectl get sa "$SA_NAME" -n "$NS" -o yaml | grep -E "name|annotations"
gcloud storage buckets get-iam-policy "gs://${BUCKET}"

echo "▶ Step 6: 4 红线自检(README §4)"
DEPLOY="${DEPLOY_YAML:-deployment.yaml}"
echo "R1 Bucket 写 = 档 1 红线(业务方必走 PM 审批)"
grep -E "object.*path|gs://" "$DEPLOY" && echo "⚠ R2 触发 - 检查命中" || echo "✅ R2 通过"
grep -E "audit_log.*file_path|audit_log.*file_content" "$DEPLOY" && echo "❌ R3 触发" || echo "✅ R3 通过"
grep -E "configMapRef.*bucket|secretRef.*bucket" "$DEPLOY" && echo "❌ R4 触发" || echo "✅ R4 通过"

echo "✅ Quick Start 完成。下一步:业务方 apply Deployment,qa-gcp 验证。"
```

---

## 2. 必须先做的准备(5 分钟之前)

```bash
# 1. 确认 SA + cluster context
gcloud auth activate-service-account --key-file=/Users/${USER}/.hermes/profiles/infra-gcp/secrets/infra-gcp-sa.json
gcloud config set project master-project
gcloud container clusters get-credentials <CLUSTER> --region <REGION>

# 2. 确认 WIF 已启用
gcloud container clusters describe <CLUSTER> --region <REGION> \
  --format="value(workloadIdentityConfig.workloadPool)"

# 3. 确认跨 project IAM 权限
gcloud projects get-iam-policy user-bucket-project \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/storage.admin"
```

---

## 3. 完成后必须通知

- 业务方:KSA / WIF / IAM policy 已就绪,可以 apply Deployment
- qa-gcp:进入端到端验证流程
- devops-gcp:启动 Cloud Audit Logs → BigQuery 监控规则

---

## 4. 常见失败 mode

| 失败 | 原因 | 修复 |
|---|---|---|
| `kubectl annotate sa` 报 `Forbidden` | cluster 未启用 WIF | `gcloud container clusters update --workload-pool=PROJECT.svc.id.goog` |
| `gcloud storage buckets set-iam-policy` 报 `Forbidden` | SA 缺 storage.admin in user-bucket-project | GCP admin 授权 `roles/storage.admin` 给 infra-gcp SA in user-bucket-project |
| Pod 启动后 SDK 报 `Permission denied` | KSA principal 拼错 | 确认 `PROJECT.svc.id.goog[NS/SA_NAME]` 格式 |
| 写 object 报 `ConditionNotMet` | prefix 不匹配 | 检查 application 写的 prefix 与 IAM condition 一致 |
| Cloud Audit Logs 无 record | Data Access 默认关闭 | `gcloud projects set-iam-policy` 显式启用 DATA_READ / DATA_WRITE |

---

> **作者声明**:本文档只给命令序列参考,**不自动执行**。infra-gcp 实际操作时根据业务方具体参数替换占位符。