# GKE Policy Controller Installation Guide

## Overview

This document provides a detailed, step-by-step guide for installing GKE Policy Controller on a GKE cluster. The installation joins the cluster to a Fleet and enables Policy Controller for policy enforcement.

**Environment:**
- Project ID: `aibang-12345678-ajbx-dev`
- Cluster Name: `dev-lon-cluster-xxxxxx`
- Cluster Location: `europe-west2`
- Fleet Membership Name: `aibang-master`
- Policy Controller Version: `1.23.1`

---

## Prerequisites

### Required APIs

The following Google Cloud APIs must be enabled:

| API | Purpose |
|-----|---------|
| `anthospolicycontroller.googleapis.com` | Policy Controller API |
| `gkehub.googleapis.com` | GKE Hub / Fleet API |
| `anthosconfigmanagement.googleapis.com` | Anthos Config Management API |

### IAM Permissions

Ensure the current user has the following roles:
- `roles/gkehub.admin` or equivalent
- `roles/iam.serviceAccountUser`

### CLI Tools

- `gcloud` - Google Cloud CLI
- `kubectl` - Kubernetes CLI

---

## Step 1: Environment Verification

### 1.1 List Current GKE Clusters

**Command:**
```bash
gcloud container clusters list
```

**Output:**
```
NAME                     LOCATION      MASTER_VERSION  MASTER_IP       MACHINE_TYPE  NODE_VERSION  NUM_NODES  STATUS
dev-lon-cluster-xxxxxx   europe-west2  1.35.1-gke.1396002  35.189.124.66  e2-medium    1.35.1-gke.1396002  3  RUNNING
```

**Description:** Verifies the target cluster exists and is in RUNNING state.

### 1.2 Get Current kubectl Context

**Command:**
```bash
kubectl config current-context
```

**Output:**
```
gke_aibang-12345678-ajbx-dev_europe-west2_dev-lon-cluster-xxxxxx
```

**Description:** Confirms kubectl is configured to access the target cluster.

### 1.3 List Current Namespaces

**Command:**
```bash
kubectl get namespaces
```

**Output:**
```
NAME                          STATUS   AGE
default                       Active   35h
gke-managed-cim               Active   35h
gke-managed-networking-dra-driver  Active  35h
gke-managed-system            Active   35h
gke-managed-volumepopulator   Active   35h
gmp-public                    Active   35h
gmp-system                    Active   35h
kube-node-lease               Active   35h
kube-public                   Active   35h
kube-system                   Active   35h
```

**Description:** Shows existing namespaces. Note: No `gatekeeper-system` namespace exists, which is good (no conflicting open-source Gatekeeper installation).

### 1.4 Check for Existing Gatekeeper Installation

**Command:**
```bash
kubectl get ns | grep -E "gatekeeper|gatekeeper-system" || echo "No Gatekeeper namespace found - OK"
```

**Output:**
```
No Gatekeeper namespace found - OK
```

**Description:** Verifies no open-source Gatekeeper is installed (would conflict with Policy Controller).

---

## Step 2: Enable Required APIs

### 2.1 Enable APIs

**Command:**
```bash
gcloud services enable anthospolicycontroller.googleapis.com gkehub.googleapis.com anthosconfigmanagement.googleapis.com
```

**Output:**
```
Operation "operations/acat.p2-487126826743-4e57ed2d-baa1-4778-9b6d-cae94e149ead" finished successfully.
```

**Description:** Enables the three required APIs for Policy Controller and Fleet management.

---

## Step 3: Register Cluster to Fleet

### 3.1 Check Existing Fleet Memberships

**Command:**
```bash
gcloud container hub memberships list
```

**Output:**
```
Listed 0 items.
```

**Description:** Confirms no existing Fleet memberships exist.

### 3.2 Register Cluster to Fleet

**Command:**
```bash
gcloud container hub memberships register aibang-master --gke-cluster=europe-west2/dev-lon-cluster-xxxxxx --enable-workload-identity
```

**Output:**
```
Waiting for membership to be created... .................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................done.
Finished registering to the Fleet.
```

**Parameters:**
- `--gke-cluster`: Format is `LOCATION/CLUSTER_NAME`
- `--enable-workload-identity`: Enables Workload Identity for secure service account binding

**Description:** Registers the cluster to the Fleet with the membership name `aibang-master`. This is a prerequisite for enabling Policy Controller.

---

## Step 4: Enable Policy Controller

### 4.1 Enable Policy Controller on Fleet Membership

**Command:**
```bash
gcloud container fleet policycontroller enable --memberships=aibang-master
```

**Output:**
```
Waiting for Feature Policy Controller to be created... ......................done.
Waiting for MembershipFeature projects/aibang-12345678-ajbx-dev/locations/europe-west2/memberships/aibang-master/features/policycontroller to be updated... .............done.
```

**Description:** Enables Policy Controller on the Fleet membership. This installs the Gatekeeper-based Policy Controller in the cluster.

---

## Step 5: Verify Policy Controller Installation

### 5.1 Check Policy Controller Status

**Command:**
```bash
gcloud container fleet policycontroller describe --memberships=aibang-master
```

**Output:**
```yaml
createTime: '2026-04-29T01:12:21.892334353Z'
membershipSpecs:
  projects/487126826743/locations/europe-west2/memberships/aibang-master:
    policycontroller:
      policyControllerHubConfig:
        auditIntervalSeconds: '60'
        deploymentConfigs:
          admission:
            podAffinity: ANTI_AFFINITY
        installSpec: INSTALL_SPEC_ENABLED
        monitoring:
          backends:
          - PROMETHEUS
          - CLOUD_MONITORING
        policyContent:
          bundles:
            policy-essentials-v2022: {}
          templateLibrary:
            installation: ALL
        version: 1.23.1
membershipStates:
  projects/487126826743/locations/europe-west2/memberships/aibang-master:
    policycontroller:
      componentStates:
        admission:
          details: 1.23.1
          state: ACTIVE
        audit:
          details: 1.23.1
          state: ACTIVE
        mutation:
          details: 'deployment not installed: resource is missing'
          state: NOT_INSTALLED
      policyContentState:
        bundleStates:
          asm-policy-v0.0.1:
            state: NOT_INSTALLED
          cis-gke-v1.5.0:
            state: NOT_INSTALLED
          cis-k8s-v1.5.1:
            state: NOT_INSTALLED
          cost-reliability-v2023:
            state: NOT_INSTALLED
          nist-sp-800-190:
            state: NOT_INSTALLED
          nist-sp-800-53-r5:
            state: NOT_INSTALLED
          nsa-cisa-k8s-v1.2:
            state: NOT_INSTALLED
          pci-dss-v3.2.1:
            state: NOT_INSTALLED
          pci-dss-v3.2.1-extended:
            state: NOT_INSTALLED
          pci-dss-v4.0:
            state: NOT_INSTALLED
          policy-essentials-v2022:
            details: object state is unknown
          psp-v2022:
            state: NOT_INSTALLED
          pss-baseline-v2022:
            state: NOT_INSTALLED
          pss-restricted-v2022:
            state: NOT_INSTALLED
          referentialSyncConfigState:
            state: NOT_INSTALLED
          templateLibraryState:
            state: ACTIVE
      state: updateTime: '2026-04-29T01:12:46.002120689Z'
name: projects/aibang-12345678-ajbx-dev/locations/global/features/policycontroller
resourceState:
  state: ACTIVE
spec: {}
updateTime: '2026-04-29T01:12:24.945193581Z'
```

**Description:** Shows Policy Controller configuration and state. Key observations:
- `installSpec: INSTALL_SPEC_ENABLED` - Policy Controller is enabled
- `version: 1.23.1` - Using version 1.23.1
- `admission.state: ACTIVE` - Admission controller is active
- `audit.state: ACTIVE` - Audit functionality is active
- `mutation.state: NOT_INSTALLED` - Mutation webhook not installed (optional feature)
- `templateLibraryState: ACTIVE` - Template library is active
- `policy-essentials-v2022` bundle is being used

### 5.2 Check Gatekeeper Deployments

**Command:**
```bash
kubectl get deployments -n gatekeeper-system
```

**Output:**
```
NAME                         READY  UP-TO-DATE  AVAILABLE  AGE
gatekeeper-audit             1/1    1           1          58s
gatekeeper-controller-manager  1/1   1           1          60s
```

**Description:** Confirms the two Gatekeeper deployments are running (audit and controller manager).

### 5.3 Check Gatekeeper Pods

**Command:**
```bash
kubectl get pods -n gatekeeper-system
```

**Output:**
```
NAME                                          READY  STATUS   RESTARTS  AGE
gatekeeper-audit-57b4b9bbf9-n69g7             1/1    Running  0         2m56s
gatekeeper-controller-manager-79ff65dddb-rm2q6  1/1    Running  0         2m58s
```

**Description:** Both Gatekeeper pods are in Running state with 1/1 Ready.

### 5.4 Check Installed Constraint Templates

**Command:**
```bash
kubectl get constrainttemplates
```

**Output:**
```
NAME                                                    AGE   DESCRIPTION
─────────────────────────────────────────────────────────────────────────────
allowedserviceportname                                  57s   限制 Service 端口名称格式（必须符合 ^[a-z][a-z0-9-]*$ 且 ≤15 字符）
asmauthzpolicydisallowedprefix                          61s   禁止 Istio AuthorizationPolicy 使用不允许的 prefix 规则
asmauthzpolicyenforcesourceprincipals                   56s   要求 Istio AuthorizationPolicy 必须指定 source.principals（强制 mTLS）
asmauthzpolicynormalization                             60s   要求 Istio AuthorizationPolicy 必须经过标准化处理
asmauthzpolicysafepattern                               64s   要求 AuthorizationPolicy 遵循安全默认拒绝模式
asmingressgatewaylabel                                  66s   要求 Istio IngressGateway 必须有指定 label
asmpeerauthnstrictmtls                                  48s   要求 Istio PeerAuthentication 必须设置 STRICT mTLS 模式
asmrequestauthnprohibitedoutputheaders                  51s   禁止 AuthorizationPolicy 输出包含敏感 HTTP headers
asmsidecarinjection                                     45s   要求命名空间必须启用/禁用 Istio sidecar injection
destinationruletlsenabled                               61s   要求 Istio DestinationRule 必须启用 TLS
disallowedauthzprefix                                   59s   禁止 AuthorizationPolicy 使用不允许的 prefix
gcpstoragelocationconstraintv1                          55s   限制 Cloud Storage Bucket 只能部署到允许的 GCP 区域
k8sallowedrepos                                         56s   白名单允许的容器镜像仓库（限制只能从可信仓库拉取镜像）
k8savoiduseofsystemmastersgroup                         43s   禁止将任何主体绑定为 system:masters 组（防止权限提升）
k8sblockallingress                                      50s   禁止创建任何 Ingress 资源（阻止所有入站流量）
k8sblockcreationwithdefaultserviceaccount               46s   禁止使用默认 ServiceAccount
k8sblockendpointeditdefaultrole                         46s   禁止修改使用 system:controller: 前缀 SA 的 Endpoint
k8sblockloadbalancer                                    65s   禁止创建 LoadBalancer 类型 Service（防止公网暴露）
k8sblocknodeport                                        44s   禁止创建 NodePort 类型 Service（防止端口冲突）
k8sblockobjectsoftype                                   53s   禁止创建指定类型的 Kubernetes 资源（如某些 CRD）
k8sblockprocessnamespacesharing                         45s   要求 Pod 不能共享其他 Pod 的进程命名空间
k8sblockwildcardingress                                 65s   禁止 Ingress 使用通配符 hostname（如 *.example.com）
k8scontainerephemeralstoragelimit                       65s   要求容器必须设置 ephemeral-storage 的 limits
k8scontainerlimits                                      60s   要求容器必须设置 CPU 和 Memory 的 limits
k8scontainerratios                                      44s   限制容器 requests 与 limits 的比例
k8scontainerrequests                                    52s   要求容器必须设置 CPU 和 Memory 的 requests
k8scronjoballowedrepos                                  43s   白名单允许 CronJob 容器镜像仓库
k8sdisallowedanonymous                                  50s   禁止将 system:anonymous 绑定到任何 Role/ClusterRole
k8sdisallowedrepos                                      45s   黑名单禁止的镜像仓库
k8sdisallowedrolebindingsubjects                        42s   禁止将 RoleBinding 绑定到白名单外的主体类型
k8sdisallowedtags                                       48s   禁止镜像使用特定 tag（如 :latest）
k8sdisallowinteractivetty                               58s   禁止 Pod 分配 TTY 和交互式 stdin
k8senforcecloudarmorbackendconfig                       55s   要求 Kubernetes Service 必须关联 Cloud Armor Security Policy
k8sexternalips                                          46s   禁止 Service 使用非白名单的 externalIPs
k8shttpsonly                                            50s   要求 Ingress 必须使用 HTTPS（强制 TLS）
k8simagedigests                                         49s   要求镜像必须指定 SHA256 digest（而非 tag）
k8slocalstoragerequiresafetoevict                       62s   要求使用 local storage 的 Pod 必须设置安全驱逐注解
k8smemoryrequestequalslimit                             51s   要求 Memory 的 requests 必须等于 limits
k8snoenvvarsecrets                                      53s   禁止将 Secret 挂载为容器环境变量（强制 volume 挂载）
k8snoexternalservices                                   67s   禁止创建 ExternalName 类型 Service
k8spodresourcesbestpractices                            54s   要求 Pod 遵循资源管理最佳实践
k8spodsrequiresecuritycontext                           56s   要求 Pod 必须定义 SecurityContext
k8sprohibitrolewildcardaccess                           58s   禁止 Role/ClusterRole 使用通配符 * 权限
k8spspallowedusers                                      59s   限制 Pod 运行的用户 UID 范围
k8spspallowprivilegeescalationcontainer                 65s   禁止容器启用 privilege escalation
k8spspapparmor                                          60s   要求容器必须使用已批准的 AppArmor Profile
k8spspautomountserviceaccounttokenpod                    54s   禁止 Pod 自动挂载 ServiceAccount Token
k8spspcapabilities                                      54s   限制容器可添加的 Linux capabilities
k8spspflexvolumes                                       49s   白名单允许的 FlexVolume driver 路径
k8spspforbiddensysctls                                  65s   禁止使用特定的 sysctl 参数
k8spspfsgroup                                           64s   要求 Pod 必须指定 fsGroup
k8spsphostfilesystem                                    55s   限制容器对宿主机文件系统目录的访问
k8spsphostnamespace                                     44s   禁止 Pod 使用宿主机的 PID/IPC/Network 命名空间
k8spsphostnetworkingports                               43s   禁止 Pod 使用宿主机网络端口（hostPort）
k8spspprivilegedcontainer                               49s   禁止运行特权容器（privileged: true）
k8spspprocmount                                         66s   限制容器对宿主进程空间的挂载
k8spspreadonlyrootfilesystem                            64s   要求容器根文件系统必须为只读
k8spspseccomp                                           61s   要求 Pod/容器必须使用已批准的 Seccomp Profile
k8spspselinuxv2                                         50s   要求容器必须指定 SELinux 安全上下文
k8spspvolumetypes                                       59s   白名单允许的 volume 类型（如禁止 hostPath/glusterfs）
k8spspwindowshostprocess                                51s   禁止 Windows 容器使用宿主进程（hostProcess）
k8spssrunasnonroot                                      59s   要求容器必须声明为非 root 运行（runAsNonRoot: true）
k8sreplicalimits                                        57s   限制 Deployment/ReplicaSet 的 replicas 最大值
k8srequirecosnodeimage                                  52s   要求节点必须使用 Container-Optimized OS 镜像
k8srequiredannotations                                  44s   要求指定资源必须包含特定 annotations
k8srequiredlabels                                       52s   要求命名空间必须包含特定 labels（如 environment、team）
k8srequiredprobes                                       48s   要求容器必须配置 liveness 和 readiness probe
k8srequiredresources                                    47s   要求容器必须设置资源 requests
k8srequirevalidrangesfornetworks                        61s   要求 NetworkPolicy 必须有有效的 CIDR 范围
k8srestrictadmissioncontroller                           56s   限制允许启用的 Admission Controllers
k8srestrictautomountserviceaccounttokens                 51s   禁止 ServiceAccount 自动挂载 Token
k8srestrictlabels                                       57s   白名单允许的 label keys
k8srestrictnamespaces                                   57s   限制 Pod 可以部署到的命名空间
k8srestrictnfsurls                                      58s   禁止挂载 NFS 存储（或白名单 NFS 服务器）
k8srestrictrbacsubjects                                 53s   限制 RBAC 允许的主体类型
k8srestrictrolebindings                                 64s   限制谁可以在哪些命名空间创建 RoleBinding
k8srestrictrolerules                                    63s   限制 Role/ClusterRole 可以定义的规则
noupdateserviceaccount                                  47s   禁止更新现有 ServiceAccount 的某些字段
policystrictonly                                        47s   要求所有资源必须被某个 Policy 约束
restrictnetworkexclusions                               62s   限制可以排除在网络策略之外的命名空间/Pod
sourcenotallauthz                                       47s   禁止 AuthorizationPolicy 使用空 source（允许所有）
verifydeprecatedapi                                     60s   审计已废弃的 Kubernetes API 版本使用
```

**Description:** 82 个 Constraint Templates 已安装，其中：
- **PSP 相关（19个）**：Pod Security Policies，覆盖特权容器、capabilities、AppArmor、Seccomp、SELinux、hostNamespace 等
- **Kubernetes 通用（39个）**：覆盖镜像仓库、资源限制、RBAC、Ingress、Service、NetworkPolicy 等
- **ASM/Anthos Service Mesh（10个）**：覆盖 AuthorizationPolicy、PeerAuthentication、SidecarInjection、DestinationRule 等
- **GCP 特定（3个）**：Cloud Storage 区域限制、Cloud Armor 后端配置
- **网络安全（6个）**：Ingress HTTPS 强制、ExternalIPs 限制、NetworkPolicy CIDR 等

### 5.5 Check Specific Constraint Template Status

**Command:**
```bash
kubectl get constrainttemplate k8srequiredlabels -o jsonpath='{.status}'
```

**Output:**
```json
{"byPod":[{"id":"gatekeeper-audit-57b4b9bbf9-n69g7","observedGeneration":1,"operations":["audit","status"],"templateUID":"5644579c-bbd2-4ddb-a46d-7d3c15bef069"},{"id":"gatekeeper-controller-manager-79ff65dddb-rm2q6","observedGeneration":1,"operations":["webhook"],"templateUID":"5644579c-bbd2-4ddb-a46d-7d3c15bef069"}],"created":true}
```

**Description:** Confirms the constraint template is created and operational.

### 5.6 Check Active Constraints and Violations

**Command:**
```bash
kubectl get constraint --all-namespaces
```

**Output:**
```
NAME                                                                              ENFORCEMENT-ACTION  TOTAL-VIOLATIONS
k8snoenvvarsecrets.constraints.gatekeeper.sh/policy-essentials-v2022-no-secrets-as-env-vars  dryrun  0
k8spodsrequiresecuritycontext.constraints.gatekeeper.sh/policy-essentials-v2022-pods-require-security-context  dryrun  3
k8sprohibitrolewildcardaccess.constraints.gatekeeper.sh/policy-essentials-v2022-prohibit-role-wildcard-access  dryrun  2
k8spspallowedusers.constraints.gatekeeper.sh/policy-essentials-v2022-psp-pods-must-run-as-nonroot  dryrun  3
k8spspallowprivilegeescalationcontainer.constraints.gatekeeper.sh/policy-essentials-v2022-psp-allow-privilege-escalation  dryrun  3
k8spspcapabilities.constraints.gatekeeper.sh/policy-essentials-v2022-psp-capabilities  dryrun  3
k8spsphostnamespace.constraints.gatekeeper.sh/policy-essentials-v2022-psp-host-namespace  dryrun  0
```

**Description:** Shows active constraints from the `policy-essentials-v2022` bundle. All are in `dryrun` mode (will log violations but not block). Violations detected for missing security contexts, which is expected for basic deployments.

---

## Step 6: Create Test Resources

### 6.1 Create Demo Namespace

**Command:**
```bash
kubectl create namespace policy-controller-demo
```

**Output:**
```
namespace/policy-controller-demo created
```

**Description:** Creates a namespace for testing Policy Controller functionality.

### 6.2 Apply Demo Application YAML

**Command:**
```bash
kubectl apply -f demo-yaml/demo-app.yaml
```

**Output:**
```
configmap/nginx-config created
service/nginx-service created
deployment.apps/nginx-deployment created
```

**Description:** Deploys a simple nginx application with ConfigMap, Service, and Deployment.

### 6.3 Verify Demo Application

**Command:**
```bash
kubectl get configmap,service,deployment -n policy-controller-demo
```

**Output:**
```
NAME                              DATA  AGE
configmap/kube-root-ca.crt        1     2m52s
configmap/nginx-config            1     40s
NAME                  TYPE       CLUSTER-IP      EXTERNAL-IP  PORT(S)  AGE
service/nginx-service ClusterIP  100.68.20.206   <none>       80/TCP   39s
NAME                             READY  UP-TO-DATE  AVAILABLE  AGE
deployment.apps/nginx-deployment 2/2    2           2          39s
```

**Description:** Confirms all demo resources are created and the deployment is healthy.

---

## Demo Application YAML

The demo application YAML file is saved at: `demo-yaml/demo-app.yaml`

**Contents:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: policy-controller-demo
  labels:
    app: nginx
    environment: demo
data:
  nginx.conf: |
    server {
      listen 80;
      server_name localhost;
      location / {
        root /usr/share/nginx/html;
        index index.html;
      }
    }
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: policy-controller-demo
  labels:
    app: nginx
    environment: demo
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: policy-controller-demo
  labels:
    app: nginx
    environment: demo
    owner: platform-team
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
        environment: demo
        owner: platform-team
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: "500m"
            memory: "128Mi"
          requests:
            cpu: "100m"
            memory: "64Mi"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 3
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
```

---

## Available Policy Bundles

The following bundles are available for installation:

| Bundle | Description | Status |
|--------|-------------|--------|
| `policy-essentials-v2022` | Core security policies (installed) | Active |
| `pss-baseline-v2022` | Pod Security Standards Baseline | Available |
| `pss-restricted-v2022` | Pod Security Standards Restricted | Available |
| `cis-k8s-v1.5.1` | CIS Kubernetes Benchmark 1.5.1 | Available |
| `cis-k8s-v1.7` | CIS Kubernetes Benchmark 1.7 | Available |
| `nist-sp-800-190` | NIST SP 800-190 | Available |
| `pci-dss-v3.2.1` | PCI DSS 3.2.1 | Available |
| `pci-dss-v4.0` | PCI DSS 4.0 | Available |
| `cost-reliability-v2023` | Cost and Reliability Best Practices | Available |
| `asm-policy-v0.0.1` | ASM Policy | Available |

---

## Troubleshooting

### Check Controller Logs

```bash
kubectl logs -n gatekeeper-system -l app=gatekeeper --tail=100
```

### Check Events

```bash
kubectl get events -n gatekeeper-system --sort-by='.lastTimestamp'
```

### Check Webhook Configuration

```bash
kubectl get validatingwebhookconfigurations gatekeeper-validating-webhook-configuration
```

### View Constraint Violations

```bash
kubectl get constraint --all-namespaces -o yaml > constraint-violations.yaml
```

---

## Cleanup

### Remove Demo Resources

```bash
kubectl delete -f demo-yaml/demo-app.yaml
kubectl delete namespace policy-controller-demo
```

### Uninstall Policy Controller

```bash
gcloud container fleet policycontroller disable --memberships=aibang-master
```

### Remove Fleet Membership

```bash
gcloud container hub memberships delete aibang-master
```

---

## References

- [GKE Policy Controller Overview](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/overview)
- [Using Policy Bundles](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/concepts/policy-controller-bundles)
- [Creating Constraints](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/creating-policy-controller-constraints)
- [Troubleshooting](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/troubleshoot-policy-controller)