# Ambient 与 K8s NetworkPolicy 协同 — 15008 必须显式放行

> **TL;DR**:
> - ambient 模式下,**业务 pod 内 iptables 规则会重定向 TCP 到 ztunnel 端口**(`15008` / `15006` / `15001`)
> - 任何 K8s `NetworkPolicy` **必须显式 allow 15008**,否则 mesh 流量被 CNI 拦截
> - **Kubelet 探针走 link-local `169.254.7.127`**,NetworkPolicy 必须 allow 这个 IP
> - 本场景 dev 集群已有 `02-namespaces/netpol-rule.md`,**迁移前需重审**

---

## 0. 问题背景

> 来源:
> - [Istio Ambient and Kubernetes NetworkPolicy](https://istio.io/latest/docs/ambient/usage/networkpolicy/)
> - [Istio Ztunnel Traffic Redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/)
> - [Istio Maturing Ambient Compatibility Blog](https://istio.io/latest/blog/2024/inpod-traffic-redirection-ambient/)

Istio 在 ambient 下用 **in-pod iptables/netfilter 规则**把 TCP 重定向到 ztunnel 的 3 个端口:

| 端口 | 用途 |
|---|---|
| **15008** | HBONE(mTLS 隧道)— **进出 pod 的所有 mesh 流量都走这个** |
| **15006** | Inbound listener |
| **15001** | Outbound listener |

K8s `NetworkPolicy` 在 **主机网络命名空间**(iptables 层)**之前**生效 — 如果 NP 没 allow 15008,ztunnel 根本收不到流量。

---

## 1. K8s NetworkPolicy 与 ztunnel 协同规则

### 1.1 15008 必须 allow

```yaml
# ❌ 错:只 allow 8080,15008 被挡,mesh 流量进不来
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-restrictive
spec:
  podSelector: {matchLabels: {app: api-a}}
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {team: same-team}}
      ports:
        - protocol: TCP
          port: 8080     # ← 只 allow 业务端口,15008 被挡
```

```yaml
# ✅ 对:必须 allow 业务端口 + 15008(HBONE 隧道端口)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-with-mesh
spec:
  podSelector: {matchLabels: {app: api-a}}
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {team: same-team}}
      ports:
        - protocol: TCP
          port: 8080
        - protocol: TCP
          port: 15008    # ← 必须显式 allow,否则 mesh 流量被挡
```

### 1.2 kubelet 探针走 link-local IP

K8s kubelet 在**节点网络命名空间**发探针,本来不会进 mesh。
ambient 下,istio-cni **SNAT 重写** 探针包的源 IP 为 link-local:

| 协议 | SNAT 后源 IP |
|---|---|
| IPv4 | `169.254.7.127` |
| IPv6 | `fd16:9254:7127:1337:ffff:ffff:ffff:ffff` |

NetworkPolicy **必须 allow 这个 link-local IP**:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-kubelet-probes
spec:
  podSelector: {matchLabels: {app: api-a}}
  ingress:
    - from:
        - ipBlock:
            cidr: 169.254.7.127/32    # ← IPv4 link-local
        - ipBlock:
            cidr: fd16:9254:7127:1337:ffff:ffff:ffff:ffff/128   # IPv6
      ports:
        - protocol: TCP
          port: 8080                  # 探针打业务端口
```

**原理**:ambient 在 pod 网络命名空间里用 iptables 把"来自 link-local 的包"识别为非 mesh 流量,**跳过 ztunnel 重定向**,直接给业务容器。

> 来源原文: "ambient uses the link-local addresses `169.254.7.127` (IPv4) and `fd16:9254:7127:1337:ffff:ffff:ffff:ffff` (IPv6) to identify and correctly allow kubelet health probe packets." — [Istio Ambient NetworkPolicy](https://istio.io/latest/docs/ambient/usage/networkpolicy/)

---

## 2. in-pod iptables 重定向机制(诊断用)

### 2.1 重定向规则(`iptables-save` 输出)

业务 pod 启动后,istio-cni 在 pod netns 插入这些规则:

```text
*mangle
:PREROUTING ACCEPT
:INPUT ACCEPT
:FORWARD ACCEPT
:OUTPUT ACCEPT
:POSTROUTING ACCEPT
:ISTIO_OUTPUT -
:ISTIO_PRERT -
-A PREROUTING -j ISTIO_PRERT
-A OUTPUT -j ISTIO_OUTPUT
-A ISTIO_OUTPUT -m connmark --mark 0x111/0xfff -j CONNMARK --restore-mark
-A ISTIO_PRERT -m mark --mark 0x539/0xfff -j CONNMARK --set-xmark 0x111/0xfff
-A ISTIO_PRERT -s 169.254.7.127/32 -p tcp -m tcp -j ACCEPT     # ← kubelet 探针放行
-A ISTIO_PRERT ! -d 127.0.0.1/32 -i lo -p tcp -j ACCEPT        # ← lo 放行
-A ISTIO_PRERT -p tcp -m tcp --dport 15008 -m mark ! --mark 0x539/0xfff -j TPROXY --on-port 15008 --tproxy-mark 0x111/0xfff   # ← HBONE 重定向
-A ISTIO_PRERT -p tcp -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ISTIO_PRERT ! -d 127.0.0.1/32 -p tcp -m mark ! --mark 0x539/0xfff -j TPROXY --on-port 15006 --tproxy-mark 0x111/0xfff   # ← Inbound 重定向

*nat
:PREROUTING ACCEPT
:INPUT ACCEPT
:OUTPUT ACCEPT
:POSTROUTING ACCEPT
:ISTIO_OUTPUT -
-A OUTPUT -j ISTIO_OUTPUT
-A ISTIO_OUTPUT -d 169.254.7.127/32 -p tcp -m tcp -j ACCEPT    # ← kubelet 探针
-A ISTIO_OUTPUT -p tcp -m mark --mark 0x111/0xfff -j ACCEPT
-A ISTIO_OUTPUT ! -d 127.0.0.1/32 -o lo -j ACCEPT
-A ISTIO_OUTPUT ! -d 127.0.0.1/32 -p tcp -m mark ! --mark 0x539/0xfff -j REDIRECT --to-ports 15001    # ← Outbound REDIRECT 到 15001
```

**关键标记**:
- `mark 0x539/0xfff` = "已认领的 connection"(*conntrack* 的 connmark + 已建立)
- `mark 0x111/0xfff` = "需 TPROXY 到 ztunnel"

### 2.2 实战解读

| 流量类型 | 走哪条规则 | 结果 |
|---|---|---|
| kubelet 探针 → 业务容器:8080 | `ISTIO_PRERT -s 169.254.7.127/32 -j ACCEPT` | **直接放过**,不走 ztunnel |
| lo 接口 (业务容器自身通信) | `! -d 127.0.0.1/32 -i lo -p tcp -j ACCEPT` | **直接放过** |
| 业务容器 → ztunnel-out (HBONE 隧道):15008 | `TPROXY --on-port 15008` | **透明代理**到 ztunnel |
| 业务容器 → 外部 (非 15008) | `REDIRECT --to-ports 15001` | **透明代理**到 ztunnel outbound |
| 已建立的 conntrack 流量 | `RELATED,ESTABLISHED -j ACCEPT` | **直接放过**(性能优化) |

---

## 3. 业务 pod 内的 socket 监听(`ss -ntlp`)

ambient pod 启动后,**业务容器外**还会出现 ztunnel 的 listening socket(在 pod netns 内):

```text
State  Recv-Q Send-Q Local Address:Port  Peer Address:Port Process
LISTEN 0      128        127.0.0.1:15080      0.0.0.0:*    # ztunnel metrics
LISTEN 0      128                *:15006            *:*      # ztunnel inbound
LISTEN 0      128                *:15001            *:*      # ztunnel outbound
LISTEN 0      128                *:15008            *:*      # ztunnel HBONE
```

**业务容器**:仍监听自己的 `:8080`(假设)。
**ztunnel 在 pod netns 内**:监听 15008/15006/15001。

→ **业务容器看到的 `localhost:8080` 仍是自己**,**没有变化**。这是 ambient 与 sidecar 最大的语义差异:应用代码无需任何修改。

---

## 4. 诊断 NetworkPolicy 冲突的 5 步排查

```bash
# Step 1: 看 pod 是否真的进 ambient
kubectl get pod <pod> -n <ns> -o jsonpath='{.metadata.namespace}{" "}{.metadata.labels}'
# 看有无 istio.io/dataplane-mode 注入相关 label(ztunnel 自动加)

# Step 2: 看 ztunnel 日志看是否捕获到 inpod 流量
kubectl logs ds/ztunnel -n istio-system | grep inpod

# Step 3: 看 pod 内 iptables(需 debug pod)
kubectl debug <pod> -it --image docker.io/istio/base --profile=netadmin -n <ns> -- iptables-save

# Step 4: 看 pod 内 socket
kubectl debug <pod> -it -n <ns> --image nicolaka/netshoot -- ss -ntlp

# Step 5: 用 nc/telnet 验证 15008 在 pod 内通
kubectl exec <pod> -n <ns> -- nc -zv localhost 15008
```

最常见错误:NetworkPolicy allow 了业务端口(8080)但**忘了 allow 15008**,表现是"curl localhost:8080 通,但 mesh 流量不通"。

---

## 5. 反向:NetworkPolicy 限制 ambient 流量的能力

| 想做 | 用 NetworkPolicy | 用 AuthorizationPolicy |
|---|---|---|
| 限制某 ns 不能访问某 service | ✅ | ✅(更精细) |
| 限制某 IP 段 | ✅ | ⚠️(只支持 ipBlocks / remoteIpBlocks) |
| 限制某 SPIFFE 身份 | ❌(NetworkPolicy 不知道 SPIFFE) | ✅ |
| 限制 HTTP method/path | ❌ | ✅ |
| 限制 15008 端口 | ✅ | - |
| 限制 kubelet 探针 | ✅(allow link-local IP) | ❌ |

**结论**:NetworkPolicy 是 **L3/L4 防火墙**,AuthorizationPolicy 是 **mesh 内 L7 策略**,两者**互补不替代**。

---

## 6. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **in-pod redirection** | "pod 内 iptables 重定向" | "istio-cni enters the pod's network namespace and establishes network redirection rules, such that packets entering and leaving the pod are intercepted and transparently redirected to the node-local ztunnel proxy instance listening on well-known ports (15008, 15006, 15001)." — [Ztunnel traffic redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/) |
| **15008 (HBONE)** | mTLS 隧道端口 | "HBONE (HTTP-Based Overlay Network Environment) is the HTTP/2 CONNECT-based tunneling protocol used by ztunnel." — Istio docs |
| **TPROXY** | 透明代理到 ztunnel | "Linux TPROXY target redirects packets to a local socket without altering the destination address, allowing transparent proxy interception." — Linux kernel docs |
| **connmark 0x539** | "已认领连接" | ztunnel 写入的标记,表示该连接已被 ztunnel 处理,iptables 不再二次重定向 |

---

## 7. 本场景迁移前必改的 NetworkPolicy 清单

| 原 NetPol | 必须改 | 改法 |
|---|---|---|
| `netpol-team-a-ingress.yaml`(只 allow 8080) | ✅ 必改 | 加 `port: 15008` |
| `netpol-team-b-egress.yaml`(只 allow 业务端口) | ✅ 必改 | 加 `port: 15001`(outbound) |
| `netpol-kubelet-probes`(只 allow kubelet CIDR) | ✅ 必改 | 加 `169.254.7.127/32` |
| 任何 deny-all default policy | ⚠️ 必查 | 确认没 deny 15001/15006/15008 |

> 你现有的 `~/git/gcp/gateway-2.0/k8s-gateway/02-namespaces/netpol-rule.md` 是**命名规范**,不是具体规则 — 没问题,但**实际部署时每条 NetPol 必须按上表调整**。

---

## 8. References

- [Istio Ambient and Kubernetes NetworkPolicy](https://istio.io/latest/docs/ambient/usage/networkpolicy/) — 15008 + link-local 探针
- [Istio Ztunnel Traffic Redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/) — iptables 规则详细说明
- [Istio Maturing Ambient: Compatibility](https://istio.io/latest/blog/2024/inpod-traffic-redirection-ambient/) — in-pod redirection 设计背景
- [Istio Troubleshooting Ambient](https://github.com/istio/istio/wiki/Troubleshooting-Istio-Ambient) — "port 15008 被 NP 挡" 是常见 cause
- [Linux TPROXY](https://www.kernel.org/doc/Documentation/networking/tproxy.txt) — 透明代理底层机制
- 同仓库 `~/git/gcp/gateway-2.0/k8s-gateway/02-namespaces/netpol-rule.md` — 现有命名规范