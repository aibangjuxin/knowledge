# ASM Solo Ambient Mesh 安装与验证

> **本文档定位**:在全新 GKE 集群上**从零**部署 Solo Ambient Mesh 的最小可运行流程。
> 环境已经按 background.md 的旧模式在跑吗?**不需要**,本文档就是为探索新架构而设,起点是空集群。

---

## 0. 前置清单 (Lab 集群跑一遍)

| 项 | 要求 | 备注 |
|---|---|---|
| GKE 版本 | 1.28+ (推荐 1.30 / 1.31) | Solo 1.30.2-solo-fips 对齐 upstream Istio 1.30.2,**强制 K8s ≥ 1.28** |
| 节点端口 | 15008 / 15021 / 15090 放行 | HBONE(节点间 mTLS 隧道) + Envoy stats;**NetworkPolicy 默认 deny 时会断** |
| Pod 数量 | gateway / ztunnel 各 ≥ 1 | Lab 集群最小 3 节点即可 |
| Workload Identity | `true`(强烈建议) | `ztunnel` Pod 能正常拉取 GCR 镜像 |
| Solo `istioctl` 二进制 | 1.30.2-solo-fips | `istioctl` version 必须显示 `1.30.2-solo-fips` |

> ⚠️ 已知坑:GKE Dataplane V2 ≠ Istio CNI;Istio CNI 必须独立装,会跟 Cilium/Calico 共存(GKE Dataplane V2 即 eBPF 的实现)但会触发**双重 iptables 抓取**。建议 Lab 用 GKE Standard + Dataplane V1,或预先把 eBPF 关掉。

---

## 1. 安装流程(全量共 4 步)

### 1.1 准备工具

```bash
# 下载 Solo Distribution 1.30.2-solo-fips
curl -L https://github.com/solo-io/solo-distro/releases/download/1.30.2-solo-fips/solo-distro-1.30.2-solo-fips-linux-amd64.tar.gz \
  -o /tmp/solo.tar.gz
tar -xzf /tmp/solo.tar.gz -C /tmp/
sudo mv /tmp/istioctl /usr/local/bin/istioctl-solo
# 或直接 alias:`istioctl-solo --version` 应该打印 1.30.2-solo-fips

# 装 Gateway API CRD(v1.5.1,Ambient 必需)
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  kubectl apply --server-side \
    -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml
```

### 1.2 应用 Ambient 控制面

```bash
# 这是 Istio 官方权威的 ambient 一行安装(Lab 默认即可)
/usr/local/bin/istioctl-solo install \
  --set profile=ambient \
  --set hub=gcr.io/istio-release \
  --set tag=1.30.2-solo-fips \
  --skip-confirmation \
  -y
```

或者用我们仓库预制的 YAML:

```bash
kubectl apply -f ../yamls/00-istiooperator.yaml
```

### 1.3 创建三个命名空间 + 打 ambient 标签

```bash
kubectl apply -f ../yamls/01-namespace-ambient-label.yaml

# 验证(Lab 第一关:必须 L3 ns 看到 ambient 标签)
kubectl get ns tenant-runtime --show-labels
# 期望输出含 `istio.io/dataplane-mode=ambient`
```

### 1.4 平台侧:Gateway + ListenerSet

```bash
kubectl apply -f ../yamls/02-gateway-agentgateway.yaml

# 验证(listener 必须 Programmed=True)
kubectl get gateway -n abjx-gw-int
kubectl get listenerset -n abjx-listenerset-int
```

### 1.5 租户侧:HTTPRoute + Service/Deployment + PeerAuthentication

```bash
kubectl apply -f ../yamls/03-httproute.yaml
kubectl apply -f ../yamls/04-service-deployment.yaml
kubectl apply -f ../yamls/05-peer-authentication.yaml

# 验证
kubectl get httproute -n tenant-runtime
kubectl get svc,deploy -n tenant-runtime
kubectl get peerauthentication -n tenant-runtime
```

---

## 2. 控制面组件清单(Ambient 必有)

| 资源 | Namespace | 谁管的 | 数量 | 关键作用 |
|---|---|---|---|---|
| `ztunnel` DaemonSet | `istio-system` (默认) / 实际可能 `ztunnel-system` | 安装 | 每节点 1 份 | HBONE 抓包,节点级 mTLS 加密(SPIFFE) |
| `istio-cni-node` DaemonSet | `kube-system` | 安装 | 每节点 1 份 | 接管 pod 的 iptables 流量,ambient 模式只创建初始 redirect |
| `istiod` Deployment | `istio-system` | 安装 | 单实例/HPA | xDS 配置中心,证书签发 |
| AgentGateway(本探索选) | `abjx-gw-int` | 平台 | 受 listener 控制 | L7 TLS 终结 / 流量分发(传统 sidecar 形态) |

> 后文 `solo-architecture.html` 给了一张完整组件图。

---

## 3. 验证清单(Lab e2e 自检)

> 全部以"跑通 = 看到正确行为"为标准,而不是"看到资源对象存在"。

### 3.1 控制面健康

```bash
# 1) 每个节点都有 ztunnel
kubectl get pods -n istio-system -l app=ztunnel -o wide

# 2) CNI 节点代理生效
kubectl get pods -n kube-system -l k8s-app=istio-cni-node -o wide

# 3) istiod 与 xDS 通信(自查,xDS status 不是 error)
istioctl-solo proxy-status 2>/dev/null || true
```

### 3.2 mTLS 是否真正起作用

```bash
# 进入租户 Pod shell,手动测 mTLS
kubectl exec -n tenant-runtime deploy/tenant-app -c tenant-app -- \
  sh -c 'echo "==== 验证 ztunnel HBONE ===="; \
  netstat -an | grep -E ":15008" | head -5'
# 期望:看到连接到 127.0.0.1:15008(本机 ztunnel)而**不是**直接到 service IP

# 验证 mTLS SPIFFE 身份
kubectl exec -n tenant-runtime deploy/tenant-app -c tenant-app -- \
  sh -c 'echo "==== 验证 mesh 内自动 mTLS ===="; \
  curl -sv http://tenant-app-svc.tenant-runtime.svc.cluster.local:80 | head -20'
# 期望:200 OK,**网络层透明加密**,应用层代码完全无感
```

### 3.3 Gateway / HTTPRoute / ListenerSet 链路

```bash
# 4) ListenerSet 必须 Programmed
kubectl get listenerset -n abjx-listenerset-int -o jsonpath='{.items[*].status.conditions[?(@.type=="Programmed")].status}'

# 5) HTTPRoute 必须 Accepted(不是 404,而是真的能被路由)
kubectl get httproute -n tenant-runtime app1.teamlevel.caep.uk \
  -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].status}'
# 期望:true

# 6) e2e:从集群外(或者 kubectl port-forward 到 gateway)打真实域名
kubectl port-forward -n abjx-gw-int svc/istio-ingressgateway 8443:443 &
HOST=app1.teamlevel.caep.uk
curl -k --resolve "$HOST:8443:127.0.0.1" "https://$HOST:8443/" -I
# 期望:HTTP/2 200
```

---

## 4. 卸载 (Lab tear-down)

```bash
# 1) 卸 istio 控制面
/usr/local/bin/istioctl-solo uninstall --purge -y

# 2) 删 lab 资源
kubectl delete -f ../yamls/05-peer-authentication.yaml
kubectl delete -f ../yamls/04-service-deployment.yaml
kubectl delete -f ../yamls/03-httproute.yaml
kubectl delete -f ../yamls/02-gateway-agentgateway.yaml
kubectl delete -f ../yamls/01-namespace-ambient-label.yaml

# 3) 删 ns
kubectl delete namespace istio-system tenant-runtime abjx-gw-int abjx-listenerset-int --ignore-not-found
kubectl delete -n kube-system ds istio-cni-node --ignore-not-found
```

---

## 5. 资源变化总览(对照 background.md)

| 资源 | 老(Sidecar) | 新(Ambient) | 差异说明 |
|---|---|---|---|
| Gateway | `gatewayClassName: istio` 同 | **同** | Gateway pod 内部仍然是 envoy sidecar 形态(因为需要 TLS 终结) |
| ListenerSet | TLS 终结于 ListenerSet | **同** | 不变 |
| HTTPRoute | parentRef → ListenerSet | **同** | 不变 |
| DR(DestinationRule) | **必加**(`trafficPolicy.connectionPool` + `tls.mode=ISTIO_MUTUAL`) | **删** | ztunnel 自动给 mesh 内流量加 mTLS,DR.tls 失效且会反向制造冲突 |
| Service port | `80/443 + targetPort` | `80 + targetPort 8080(http)` | Pod 不再 listen 443 |
| Pod spec | `tls.volumeMount` + skip-verify | **无** | 应用代码层面完全不感知 mTLS |
| Sidecar `istio-proxy` 容器 | 每个 Pod 注入一份 | **不注入** | ztunnel 节点 DaemonSet 取代 sidecar |
| Namespace label | `istio-injection=enabled` | `istio.io/dataplane-mode=ambient` | 替换 |
| 节点端口 | 15090(envoy stats)| **+15008(HBONE)** | 节点间加密 |
| 新组件 | — | **ztunnel DaemonSet** | 节点级 mTLS 网关 |
| 新组件 | — | **istio-cni-node DaemonSet** | 接管 pod 流量 |

---

## 6. 权威证据

| 断言 | 来源 |
|---|---|
| `istioctl install --set profile=ambient` 是官方安装姿势 | [Istio Ambient Install (istioctl)](https://istio.io/latest/docs/ambient/install/istioctl/) |
| Gateway API v1.5.1 experimental-install.yaml 是 Ambient 安装的前置依赖 | [Istio Ambient Install](https://istio.io/latest/docs/ambient/install/) |
| Namespace 标签 `istio.io/dataplane-mode=ambient` 是 Ambient 开启粒度 | [Istio Ambient — Add workloads to the mesh](https://istio.io/latest/docs/ambient/user-guides/add-workloads/) |
| HBONE 协议运行在 TCP 15008 端口,ztunnel 提供节点级 mTLS | [Istio Ambient Architecture — HBONE](https://istio.io/latest/docs/ambient/architecture/hbone/) |
| Ambient 下 DestinationRule 的 `trafficPolicy.tls` 配置不再生效(由 ztunnel 取代) | [Istio Ambient — Use Layer 4 security policy](https://istio.io/latest/docs/ambient/user-guides/waypoint/) |
| Solo.io Distribution 是 upstream Istio 的加固镜像,版本号独立编号(`x.y.z-solo-fips`) | Solo.io 官方 distrib 页(solo.io/distro) |
