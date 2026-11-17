# 04 · Quick Start —— infra-gcp 5 分钟跑通

> **本节是 infra-gcp profile 视角的"接到业务方需求后,5 分钟内跑完核心步骤"的脚本化参考**
>
> **架构师 lane 边界**:本节给出 `kubectl` / `gcloud` 命令序列供参考,**不是执行脚本**。实际由 infra-gcp 用专属 SA 执行。

---

## 0. 前置条件(必读)

```bash
# 1. infra-gcp profile 必须有专属 GCP SA(参见 ADR-009-q6a-path-decision.md)
# 路径:/Users/<USER>/.hermes/profiles/infra-gcp/secrets/infra-gcp-sa.json

# 2. SA 必须有以下最小权限:
#    - container.clusters.get
#    - compute.networks.read
#    - container.namespaces.create
#    - container.pods.create / get / list / delete
#    - container.persistentvolumeclaims.create
#    - container.persistentvolumes.create
#    - container.networkpolicies.create
#    - container.secrets.create

# 3. K8s context 必须指向目标 cluster
gcloud container clusters get-credentials <cluster-name> --region <region>
kubectl config current-context
```

---

## 1. 5 分钟 Quick Start(脚本化)

```bash
#!/bin/bash
# infra-gcp 接到业务方需求后跑这套
# 用法: bash 04-quick-start.sh <namespace> <tenant-id> <nas-share-path>

set -euo pipefail

NS="${1:-api-ns}"
TENANT="${2:-tnt-001}"
SHARE_PATH="${3:-//nas.address.aibang/hk/gsd/application}"
PV_NAME="pv-nas-${TENANT}"
PVC_NAME="pvc-nas-app"
SA_NAME="api-nas-consumer-sa"

echo "▶ Step 1: 创建 namespace + SA + Secret"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount "$SA_NAME" -n "$NS" --dry-run=client -o yaml | kubectl apply -f -

# Secret:凭据从环境变量读(infra-gcp profile 自己配,不入 manifest)
kubectl create secret generic smb-secret -n "$NS" \
  --from-literal=username="${SMB_USERNAME:?SMB_USERNAME required}" \
  --from-literal=password="${SMB_PASSWORD:?SMB_PASSWORD required}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "▶ Step 2: 创建 PV"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PV_NAME}
  labels: { tenant: "${TENANT}", storage-type: nas-smb }
spec:
  capacity: { storage: 100Gi }
  accessModes: [ReadOnlyMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  csi:
    driver: smb.csi.k8s.io
    volumeHandle: "nas-${TENANT}#${SHARE_PATH}#"
    volumeAttributes: { source: "${SHARE_PATH}" }
    nodePublishSecretRef: { name: smb-secret, namespace: "${NS}" }
EOF

echo "▶ Step 3: 创建 PVC"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${NS}
  labels: { tenant: "${TENANT}" }
spec:
  volumeName: ${PV_NAME}
  accessModes: [ReadOnlyMany]
  resources: { requests: { storage: 10Gi } }
  storageClassName: ""
EOF

echo "▶ Step 4: 创建 NetworkPolicy"
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-only-nas-pod-egress
  namespace: ${NS}
spec:
  podSelector:
    matchLabels:
      role: nas-consumer
  policyTypes: [Egress]
  egress:
  - to:
    - ipBlock: { cidr: 10.20.0.0/16, except: [10.20.0.0/24] }
    ports: [{ protocol: TCP, port: 445 }]
  - to:
    - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: kube-system } }
    ports: [{ protocol: UDP, port: 53 }]
  - to: []
    ports: [{ protocol: TCP, port: 443 }]
EOF

echo "▶ Step 5: 验证"
kubectl get pv ${PV_NAME}
kubectl get pvc ${PVC_NAME} -n ${NS}
kubectl get networkpolicy -n ${NS}
kubectl get sa ${SA_NAME} -n ${NS}

echo "▶ Step 6: 红线 4 条自检(README §4)"
DEPLOY="${DEPLOY_YAML:-deployment.yaml}"
grep -E "gcs|firestore|bigquery|cloudsql" "$DEPLOY" && echo "❌ R1 触发" || echo "✅ R1 通过"
grep -E "nas.*path|/mnt/nas" "$DEPLOY" && echo "❌ R2 触发" || echo "✅ R2 通过"
grep -E "audit_log.*file_path|audit_log.*file_content" "$DEPLOY" && echo "❌ R3 触发" || echo "✅ R3 通过"
grep -E "configMapRef.*nas|secretRef.*nas" "$DEPLOY" && echo "❌ R4 触发" || echo "✅ R4 通过"

echo "✅ Quick Start 完成。下一步:业务方 apply Deployment,qa-gcp 验证。"
```

---

## 2. 必须先做的准备(5 分钟之前)

```bash
# 1. 确认 SA + cluster context
gcloud auth activate-service-account --key-file=/Users/<USER>/.hermes/profiles/infra-gcp/secrets/infra-gcp-sa.json
gcloud config set project <PROJECT_ID>
gcloud container clusters get-credentials <CLUSTER> --region <REGION>

# 2. 确认 CSI driver 已装
kubectl get pods -n kube-system -l app=csi-smb
# 期望:DaemonSet 跑在每个 Node 上

# 3. 确认 SMB 凭据已准备好(从 IT 拿)
# 期望:有 SMB_USERNAME / SMB_PASSWORD / NAS 路径
```

---

## 3. 完成后必须通知

- 业务方:PV/PVC/NetworkPolicy 已就绪,可以 apply Deployment
- qa-gcp:进入端到端验证流程
- devops-gcp:启动监控规则配置

---

## 4. 常见失败 mode

| 失败 | 原因 | 修复 |
|---|---|---|
| `kubectl apply PV` 报 `Forbidden` | SA 权限不够 | 检查 `container.persistentvolumes.create` 是否在 SA 角色里 |
| `kubectl apply PVC` 报 `no PersistentVolume found` | PV 没创建 / `volumeName` 写错 | `kubectl describe pvc <name>` 看 Pending 原因 |
| `kubectl apply NetworkPolicy` 报 `timed out` | CNI 不支持 NetworkPolicy(GKE 必支持)| 检查 cluster 是否开启 NetworkPolicy |
| `SMB_USERNAME / SMB_PASSWORD` 环境变量未设 | infra-gcp 没配 | 在 profile 的 shell rc 文件里 export |

---

> **作者声明**:本文档只给命令序列参考,**不自动执行**。infra-gcp 实际操作时根据业务方具体参数替换占位符。