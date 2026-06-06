# K8s Gateway + ListenerSet 多租户平台安装管线

> 配套：`k8s-gateway-listener-tenant-api`（tenant 上线 4-YAML 最小集）
> 实测集群：GKE `dev-lon-cluster-xxxxxx` @ europe-west2, 3 × e2-medium, Istio 1.30 minimal, K8s Gateway API v1.5.1
> 实测日期：2026-06-03，43 分钟完成，0 业务中断

---

## 1. 架构背景：什么属于 platform 阶段

```
Platform 团队（你管）                              Tenant 团队（不归你管）
─────────────────────                              ─────────────────────
00-prereqs/  skopeo, GAR repo, node SA IAM         Service
01-platform/ K8s Gateway API CRDs, Istio install   Deployment
02-namespaces/ 3 个平台 NS                         HTTPRoute
03-gateway/ 共享 Gateway (ILB)                     DestinationRule
04-secrets/  团队 wildcard cert (跨 NS 复制)
05-listenerset/ 团队 ListenerSet (per-tenant)
06-runtime/ 样例后端（nginx HTTPS 443）
07-verify/   E2E curl 验证脚本
```

**与 `k8s-gateway-listener-tenant-api` 的边界**：
- 本子主题 = "platform 阶段"，从 0 到 1
- `k8s-gateway-listener-tenant-api` = "tenant 阶段"，假设 platform 已就绪
- 交接点：本子主题最后创建 `abjx-listenerset-int/<TEAM>-listenerset`，tenant 阶段的 HTTPRoute `parentRef` 引用它

---

## 2. 7 阶段管线（强顺序约束）

### 2.1 00-prereqs — 镜像搬运（最易出错）

```bash
# 0.1 装 skopeo (bastion 无 docker，用 skopeo copy 替代 docker push)
sudo apt-get install -y skopeo

# 0.2 创建 GAR repo (用 gcloud 创建，不走 terraform)
gcloud artifacts repositories create containers \
  --repository-format=docker --location=europe-west2

# 0.3 配置 docker auth helper (用这个，不要用 --dest-creds user:pass)
gcloud auth configure-docker europe-west2-docker.pkg.dev

# 0.4 推 2 个 Istio 镜像
skopeo copy --src-tls-verify=true \
  docker://docker.io/istio/pilot:1.30.0-distroless \
  docker://europe-west2-docker.pkg.dev/PROJECT/containers/pilot:1.30.0-distroless
skopeo copy --src-tls-verify=true \
  docker://docker.io/istio/proxyv2:1.30.0-distroless \
  docker://europe-west2-docker.pkg.dev/PROJECT/containers/proxyv2:1.30.0-distroless

# 0.5 节点 SA 加 GAR reader 权限 (即使开了 Workload Identity 也需要)
gcloud projects add-iam-policy-binding PROJECT \
  --member="serviceAccount:NODE_SA@PROJECT.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"
```

### 2.2 01-platform — K8s Gateway API + Istio 装

```bash
# 1.1 K8s Gateway API CRDs v1.5.1 (ListenerSet GA 在此版本)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

# 1.2 Istio 1.30 minimal (only istiod, NO CNI, NO ingress gateway)
istioctl install -y --set profile=minimal \
  --set components.cni.enabled=false \
  --set values.global.platform=gke \
  --set values.global.imagePullPolicy=Always \
  --set values.pilot.image=europe-west2-docker.pkg.dev/PROJECT/containers/pilot:1.30.0-distroless \
  --set values.global.proxy.image=europe-west2-docker.pkg.dev/PROJECT/containers/proxyv2:1.30.0-distroless \
  --set values.pilot.resources.requests.cpu=100m \
  --set values.pilot.resources.requests.memory=512Mi \
  --set values.pilot.resources.limits.cpu=500m
```

### 2.3 02-namespaces — 3 个平台 NS

```yaml
# platform-namespaces.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: abjx-gw-int           # 共享 Gateway (ILB)
  labels:
    gateway.abjx.com/platform: "true"
---
apiVersion: v1
kind: Namespace
metadata:
  name: abjx-listenerset-int  # 所有团队的 ListenerSet
  labels:
    gateway.abjx.com/listener-enabled: "true"  # Gateway.allowedListeners selector
---
apiVersion: v1
kind: Namespace
metadata:
  name: 110139-int            # 样例 tenant runtime (eimId 命名风格)
```

### 2.4 03-gateway — 共享 Gateway (ILB)

```yaml
# abjx-gw-int.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: abjx-gw-int
  namespace: abjx-gw-int
spec:
  gatewayClassName: istio
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      allowedListeners:           # ⭐ 关键: 授权哪些 NS 可以挂 ListenerSet
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway.abjx.com/listener-enabled: "true"
      tls:
        mode: Terminate
        certificateRefs:
          - name: abjx-lex-eg-secret-team1-tls
            namespace: abjx-listenerset-int  # 跨 NS 引用 OK (Gateway API 设计如此)
  addresses:
    - type: Value
      value: 192.168.64.44       # 预分配的 ILB IP (从 subnet 留出)
```

### 2.5 04-secrets — 团队 wildcard cert（跨 NS 复制模式）

```bash
# 5.1 自签 wildcard cert (dev only, prod 用 cert-manager)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout abjx-lex-eg-secret-team1-tls.key \
  -out abjx-lex-eg-secret-team1-tls.crt \
  -subj "/CN=*.team1.appdev.aibang" \
  -addext "subjectAltName=DNS:*.team1.appdev.aibang,DNS:team1.appdev.aibang"

# 5.2 在 ListenerSet NS 创建 Secret
kubectl create secret tls abjx-lex-eg-secret-team1-tls \
  --cert=abjx-lex-eg-secret-team1-tls.crt \
  --key=abjx-lex-eg-secret-team1-tls.key \
  -n abjx-listenerset-int

# 5.3 ⭐ 跨 NS 复制 Secret (Pod mount secret 在 tenant NS, 但 Secret 不能跨 NS 引用)
kubectl get secret abjx-lex-eg-secret-team1-tls -n abjx-listenerset-int -o json \
  | jq '.metadata.namespace = "110139-int"' \
  | kubectl apply -f -
```

### 2.6 05-listenerset — 团队 ListenerSet

```yaml
# team1-listenerset.yaml
apiVersion: gateway.networking.k8s.io/v1     # ⭐ v1 (GA), 不是 v1beta1
kind: ListenerSet
metadata:
  name: team1-listenerset
  namespace: abjx-listenerset-int
spec:
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      hostname: app.team1.appdev.aibang
      tls:
        mode: Terminate
        certificateRefs:
          - name: abjx-lex-eg-secret-team1-tls
            namespace: abjx-listenerset-int
      allowedRoutes:                           # ⭐ 关键: 授权哪些 NS 可以挂 HTTPRoute
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: abjx-int
```

### 2.7 06-runtime — 样例后端（E2E TLS 链路）

```yaml
# deployment.yaml - nginx HTTPS 443 (自签 cert 与 Gateway cert 一致)
apiVersion: apps/v1
kind: Deployment
metadata: {name: app, namespace: 110139-int}
spec:
  replicas: 2
  selector: {matchLabels: {app: app}}
  template:
    metadata: {labels: {app: app, gateway-access: abjx-int}}  # ⭐ ListenerSet selector
    spec:
      containers:
        - name: app
          image: nginxinc/nginx-unprivileged:1.27-alpine
          ports: [{containerPort: 443}]
          volumeMounts:
            - {name: cert, mountPath: /etc/nginx/certs, readOnly: true}
            - {name: conf, mountPath: /etc/nginx/conf.d, readOnly: true}
          # ⭐ 注意: 容器是 1024 以下端口非 root, 用 unprivileged 镜像
```

```yaml
# service.yaml - HTTPS 443 (不是 80/8080)
apiVersion: v1
kind: Service
metadata: {name: app, namespace: 110139-int}
spec:
  selector: {app: app}
  ports:
    - {name: https, port: 443, targetPort: 443, appProtocol: HTTPS}
```

```yaml
# destinationrule.yaml - DR SIMPLE + skip-verify (自签 cert 后端)
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata: {name: app-dr, namespace: 110139-int}
spec:
  host: app.110139-int.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE                              # 不是 ISTIO_MUTUAL (那是 mesh mTLS)
      insecureSkipVerify: true                  # 自签 cert 必须 skip (prod 用真实 CA + SIMPLE)
```

```yaml
# httproute.yaml - parentRef 必须是 ListenerSet (不是 Gateway)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: app-route, namespace: 110139-int}
spec:
  parentRefs:
    - {group: gateway.networking.k8s.io, kind: ListenerSet,
       name: team1-listenerset, namespace: abjx-listenerset-int,
       sectionName: https}                      # ⭐ ListenerSet 的 listener.name
  hostnames: ["app.team1.appdev.aibang"]
  rules:
    - matches: [{path: {type: PathPrefix, value: /}}]
      backendRefs: [{name: app, port: 443, weight: 1}]   # Service port 443
```

### 2.8 07-verify — E2E curl

```bash
GATEWAY_IP=192.168.64.44
curl -k -v --max-time 10 \
  --resolve "app.team1.appdev.aibang:443:${GATEWAY_IP}" \
  "https://app.team1.appdev.aibang/healthz"
# 期望: HTTP/2 200, server: istio-envoy, x-envoy-upstream-service-time: <50ms
```

---

## 3. 9 项 Pitfall 速查表

| # | Pitfall | 症状 | 修复 |
|---|---------|------|------|
| 1 | `gcloud get-credentials` 用公网 endpoint | `connection refused` 或 `unauthorized` | bastion NAT IP 不在 masterAuthorizedNetworks 白名单，改 `gcloud get-credentials --internal-ip` 走私网 endpoint |
| 2 | 卸载 managed CSM 时**先**删 CRD | 30s 内 CRD 被 Google fleet controller 重建 | 必须先 `gcloud container hub mesh disable`，**再** `kubectl delete crd` |
| 3 | 卸载 ASM 后 gateway deployment `image: auto` ErrImagePull | pod 一直 ImagePullBackOff | **正常中间态**，sidecar injector 退出后会清；继续后续步骤即可 |
| 4 | `skopeo copy --dest-creds user:pass` 推 GAR | 403 Forbidden | 用 `gcloud auth configure-docker europe-west2-docker.pkg.dev` credential helper |
| 5 | 节点 SA 缺 GAR reader 角色 | pod ImagePullBackOff | `gcloud projects add-iam-policy-binding --role=roles/artifactregistry.reader --member=serviceAccount:NODE_SA` |
| 6 | e2-medium (940m allocatable CPU) 装 500m×2 istiod | istiod Pending 5+ 分钟，资源不足 | 降为 100m req/500m limit（`--set values.pilot.resources.requests.cpu=100m`） |
| 7 | ListenerSet apiVersion 写 v1beta1 | apply 失败 `no matches for kind "ListenerSet"` | v1.5.1 standard-install.yaml 中是 `v1`（GA） |
| 8 | Secret 只在 ListenerSet NS 创建，Pod 报 `secret not found` | pod 一直 `ContainerCreating` FailedMount | Secret 是 namespace-scoped，**必须**复制到 tenant NS：`kubectl get secret -o json \| jq '.metadata.namespace = "<tenant-ns>"' \| kubectl apply -f -` |
| 9 | DR 用 `mode: DISABLE` 或 `ISTIO_MUTUAL` | 后端 plaintext 暴露 OR 后端报 handshake error | 自签 cert 用 `SIMPLE` + `insecureSkipVerify: true`；prod 真实 CA 用 `SIMPLE` + `caCertificates` |

---

## 4. Bastion → Cluster 网络路径

**问题**：GKE 集群 masterAuthorizedNetworksConfig 白名单通常只允许公司办公网 + bastion 私网 IP。bastion 的 NAT IP（公网）**不在**白名单，所以从本地 `gcloud` 直接连集群公网 endpoint 失败。

**方案 A**（推荐，零配置）：`gcloud get-credentials --internal-ip`
```bash
gcloud container clusters get-credentials CLUSTER \
  --region=europe-west2 --project=PROJECT \
  --internal-ip   # ⭐ 走私网 endpoint (192.168.224.2)
```
需要 `masterGlobalAccessConfig.enabled=true`（GKE 集群级配置），跨 region 都可达。

**方案 B**：从 bastion 转发 SSH tunnel（不推荐，复杂且慢）

---

## 5. GAR 镜像搬运管线

```
docker.io (公网)
  ↓ skopeo copy (bastion 出公网)
  ↓
europe-west2-docker.pkg.dev/PROJECT/containers/  (GAR, 私网)
  ↓ kube image pull (节点 SA IAM)
  ↓
Pod
```

**为什么用 skopeo 不用 docker push**：
- bastion 是 GCE e2-micro，没装 docker daemon
- skopeo 是个 binary，不需要 daemon，开箱即用
- `--src-tls-verify=true` 验证源 registry TLS

**为什么 GAR 不直接 docker.io pull**：
- 节点出公网带宽受 NAT 限制，且 K8s 拉镜像走节点 SA
- 节点 SA → GAR 是 VPC 私网，比 docker.io 快 10x
- GAR 走 GCS 持久化，重启节点不丢缓存

---

## 6. 跨 NS Secret 复制模式（重要经验）

**问题**：K8s Gateway API 设计上允许 Gateway / ListenerSet 跨 NS 引用 Secret（`certificateRefs[].namespace` 字段），但 **Pod 挂载 Secret 是 namespace-scoped**。所以即使 Gateway 在 NS-A 看到 Secret，Pod 在 NS-B 还是看不到。

**ReferenceGrant 不能解决**：ReferenceGrant 只授权 Service ref、HTTPRoute ref、TLS 证书 ref 的**跨 NS 引用**，不影响 Pod volume mount。

**workaround（dev）**：
```bash
kubectl get secret SECRET -n NS-A -o json \
  | jq 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.selfLink, .metadata.managedFields)' \
  | jq '.metadata.namespace = "NS-B"' \
  | kubectl apply -f -
```

**workaround（prod 推荐）**：
- cert-manager + ClusterIssuer，每个 NS 一个 Certificate
- 或者 external-secrets-operator，从 Vault/GSM 同步到所有 NS
- 或者用 `reflector` CRD 自动 mirror Secrets across NS

**当前实现的妥协**：手工 `kubectl get | jq | apply` 复制到 tenant NS。生产前必须替换。

---

## 7. 3 NS 布局 vs 旧 2 NS 布局

**旧 2 NS 布局**（`k8s-gateway-listener-tenant-api` 假设的）：
```
kgateway-system/         ← Gateway (shared)
team1-gateway/           ← ListenerSet + HTTPRoute
team1-runtime/           ← Service + Deployment
```

**新 3 NS 布局**（本子主题实现的，更适合生产）：
```
abjx-gw-int/             ← Gateway (shared)        [NS 1]
abjx-listenerset-int/    ← ListenerSet + Secret    [NS 2]
110139-int/              ← HTTPRoute + Service + Deployment [NS 3]
```

**为什么分 3 个而不是 2 个**：
- **安全边界更清晰**：平台 Gateway 管理员（管 abjx-gw-int）、ListenerSet 所有者（管 abjx-listenerset-int）、租户（管 110139-int）三者权限分离
- **RBAC 更细**：平台管理员只需 abjx-gw-int 写权限，不需碰 tenant NS
- **多 ListenerSet 共享 NS**：abjx-listenerset-int 可容纳 team1/team2/.../teamN 所有团队的 ListenerSet，Gateway `allowedListeners: Selector` 通过 label 选
- **不破坏 tenant 隔离**：tenant NS（eimId 风格如 110139-int）只放本租户的 workload

**迁移路径**：
- 已有 2 NS 部署的集群，可以保留旧 NS，**新增** 3 NS 并行运行
- ListenerSet `parentRef` 引用同一个 Gateway，没有冲突
- 灰度迁移：一个团队一个团队切

---

## 8. 验证流程（5 层）

```bash
# 1. 资源就绪 (30s)
kubectl get gateway,httproute,svc,deploy,pods -A
# Gateway: Programmed=True, addresses=[192.168.64.44]
# ListenerSet: Programmed=True, acceptedListeners=1
# HTTPRoute: status.parents[].conditions[Accepted]=True

# 2. Pod 容器内能 mount Secret
kubectl exec -n 110139-int deploy/app -- ls /etc/nginx/certs/
# 应看到 tls.crt tls.key

# 3. 集群内连通 (绕过 Gateway)
kubectl exec -n 110139-int deploy/app -- curl -k https://localhost/healthz
# 200 OK

# 4. Gateway 链路探查
./k8s-gateway-fqdn-minimax.sh app.team1.appdev.aibang 110139-int --validate
# 期望 5 段链路全部解析成功

# 5. 外部 HTTPS 流量
curl -k -v --resolve "app.team1.appdev.aibang:443:192.168.64.44" \
  "https://app.team1.appdev.aibang/healthz"
# HTTP/2 200, x-envoy-upstream-service-time: <50ms
```

---

## 9. 反模式

| 反模式 | 后果 |
|--------|------|
| 用公网 endpoint `gcloud get-credentials` (无 `--internal-ip`) | bastion NAT IP 不在白名单，认证失败 |
| 卸载 ASM 不先 `gcloud container hub mesh disable` | CRD 30s 内被 Google controller 重建，必须重做 |
| 推 GAR 用 `--dest-creds` 或明文密码 | 403 拒绝；GAR 必须用 google credential helper |
| 节点 SA 不加 `artifactregistry.reader` | pod ImagePullBackOff（即使开了 Workload Identity） |
| e2-medium 装 500m×2 istiod | 节点 CPU 装不下，istiod Pending |
| ListenerSet apiVersion 写 v1beta1 | apply 失败（v1.5.1 是 v1 GA） |
| Secret 只在 ListenerSet NS 创建 | pod FailedMount `secret not found` |
| DR 用 ISTIO_MUTUAL 配自签 cert | 后端 handshake error（自签 cert 没有 mesh CA 签发） |
| DR 用 DISABLE | 后端 plaintext 暴露，不符合 E2E TLS 要求 |
| 一次性 apply 完不查 `status.parents` | 5/7 常见错配静默通过 |
| 平台阶段写完不交付给 tenant 阶段 | 业务永远起不来，团队会问"platform 装好了我什么时候能上" |
