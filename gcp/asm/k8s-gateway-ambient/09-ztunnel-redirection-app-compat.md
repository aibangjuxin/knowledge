# Ambient 下 ztunnel 拦截机制 — 应用代码兼容性全表

> **TL;DR**:
> - ambient 用 **in-pod iptables 重定向 + TPROXY** 把 TCP 转到 ztunnel(15008/15006/15001)
> - **应用代码无需任何修改** — `localhost:<业务端口>` 仍是业务容器
> - 但有几个**应用感知不到的边界 case**:`localhost` 走 lo 不经 mesh、`127.0.0.1` 监听冲突、UDP 部分支持
> - **业务代码兼容性:完全 OK**,但**诊断方式不同**(从看 pod 内 iptables 改为看 ztunnel 日志)

---

## 0. 拦截机制详解

> 来源:
> - [Ztunnel traffic redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/)
> - [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/)
> - [Maturing Istio Ambient Compatibility Blog](https://istio.io/latest/blog/2024/inpod-traffic-redirection-ambient/)

### 0.1 三个端口的分工

```
业务容器 (app:8080)
   │
   │ ← lo 接口 (本地回环)
   │ → 任何非 lo TCP 出口
   │ → 任何进入 pod 的 TCP
   │
   ▼  in-pod iptables (mangle + nat table)
   │
   ├─→ 15008 (HBONE)   进出 pod 的 mesh 流量,mTLS 隧道
   ├─→ 15006 (Inbound)  ztunnel 接 inbound,解密后转给业务容器
   └─→ 15001 (Outbound) ztunnel 接 outbound,加密后转发到目标 ztunnel
```

**关键**:**业务容器的 socket 表(`ss -ntlp`)看不到 15008/15006/15001** — 这3 个端口的 socket 在 ztunnel 进程空间里,通过 Linux network namespace 共享让 pod 内可见。

### 0.2 TPROXY vs REDIRECT 区别

| 机制 | 用途 | 行为 |
|---|---|---|
| **TPROXY**(mangle table) | Inbound + HBONE 隧道 | **不改目的 IP**,透明代理;业务容器以为是原始对端 |
| **REDIRECT**(nat table) | Outbound | **改目的端口**为 15001(原本去 `target:80` 改成去 `localhost:15001`);业务容器以为是 `localhost` 出去的 |

---

## 1. 应用代码兼容性矩阵

| 场景 | sidecar 模式 | ambient 模式 | 行为差异 |
|---|---|---|---|
| **TCP 监听端口**(e.g. `:8080`) | 业务容器直接 listen | 业务容器直接 listen | **无差异** ✅ |
| **TCP 连接 localhost:port** | 走 lo 接口,绕过 iptables | **走 lo 接口,在 iptables 里显式 ACCEPT** | **无差异** ✅ |
| **TCP 连接 127.0.0.1:port** | 同 lo | 同 lo | **无差异** ✅ |
| **TCP 连接 pod IP:port**(同节点) | envoy 拦截 → 转 ztunnel | ztunnel 拦截(本节点) | **无差异** ✅ |
| **TCP 连接 pod IP:port**(跨节点) | envoy → ztunnel → 远端 ztunnel → 远端 envoy → 业务 | ztunnel → 远端 ztunnel → 业务 | **少一跳**(无 envoy) |
| **UDP** | envoy 支持(部分) | ztunnel 部分支持 | **行为差异需验证** ⚠️ |
| **Unix domain socket** | 走 lo,不影响 | 走 lo,**ACCEPT 规则保护** | **无差异** ✅ |
| **业务容器 listen :15008 等 mesh 端口** | 端口冲突,启动失败 | **端口已被 ztunnel 占,启动失败** | **有差异**(但都不允许) ❌ |
| **业务容器 listen :15090 / 15021**(envoy admin) | 由 envoy 占 | **由 ztunnel 占(15080)** | **有差异**,应用不应 listen 这些端口 |

---

## 2. 边界 case 详解

### 2.1 `localhost` / `lo` 接口 — 永远不进 mesh

ambient 的 iptables 显式放过 lo 接口:
```text
-A ISTIO_PRERT ! -d 127.0.0.1/32 -i lo -p tcp -j ACCEPT    # 业务 lo 通信
-A ISTIO_OUTPUT ! -d 127.0.0.1/32 -o lo -j ACCEPT          # 业务 lo 通信
```

**含义**:
- 业务 A 容器 `curl localhost:6380`(同 pod Redis sidecar)→ **不经 ztunnel**
- 业务代码连接 `localhost:xxx` 与 sidecar 模式完全一致

⚠️ **业务容器内有多个容器且互相通信的场景**(本来 sidecar 模式下 sidecar 与 app 通信),ambient 下需重新设计 — 因为 ambient **没有 sidecar**,业务容器只能与"同 pod 内其他容器"通过 lo 通信。

### 2.2 端口冲突:业务容器不要 listen 15001/15006/15008/15080

| 端口 | sidecar | ambient |
|---|---|---|
| 15001(envoy outbound) | envoy 占 | **ztunnel 占** |
| 15006(envoy inbound) | envoy 占 | **ztunnel 占** |
| 15008(HBONE) | N/A | **ztunnel 占** |
| 15080(envoy admin) | envoy 占 | **ztunnel 占** |

**实务**:业务代码永远不需要 listen 这些端口。但**调试时**(比如 `nc -l 15001`)会失败,可作诊断信号。

### 2.3 UDP 支持差异(1.30 状态)

> 来源:[Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/)

| 协议 | sidecar (envoy) | ambient (ztunnel) |
|---|---|---|
| TCP | ✅ 全支持 | ✅ 全支持 |
| UDP | ✅ 大部分(需明确协议) | ⚠️ **部分支持** — DNS 强制 capture,其他 UDP 流量**默认不进 mesh** |
| HTTP/2 cleartext | ✅ | ✅(经 HBONE 隧道) |
| HTTP/3 / QUIC | ✅ 部分 | ❌ 不支持 |
| gRPC | ✅ | ✅ |

**对你的影响**:
- DNS 查询 → ambient 默认强制 capture(`ambient.dnsCapture: true`),**DNS 走 ztunnel**
- 其他 UDP 流量(如自定义 UDP 服务、QUIC)→ 不进 mesh = **没有 mTLS,没有策略**
- 业务用 UDP = 必须验证 ambient 是否 capture,否则 traffic 是明文

### 2.4 DNS capture 细节

```
业务容器 (app)
   │ resolve api-service.ns.svc.cluster.local
   ▼
in-pod iptables: UDP:53 → 15053 (ztunnel DNS proxy)
   │
   ▼
ztunnel 处理:
   1. 看是 mesh 内域名 → 走 mDNS 解析或 cluster domain 直连
   2. 解析结果包含 IP,IP 是 cluster 内 → 走 HBONE
   3. 解析结果包含 IP,IP 是 external → 走 egress(zb × tunnel 到 egress ztunnel)
```

**业务代码无感**:还是 `getaddrinfo()` → 返回 IP。**DNS 抓取透明完成**。

---

## 3. conntrack / iptables 规模问题(集群上限)

### 3.1 担忧点

> "ztunnel + iptables 重定向 + conntrack 表 → 集群规模上限?"

| 规模 | 风险 |
|---|---|
| < 100 pod / 节点 | 🟢 几乎无影响 |
| 100-500 pod / 节点 | 🟡 conntrack 表增长,需要监控 |
| > 1000 pod / 节点 | 🟠 **可能**成为瓶颈 |

### 3.2 iptables rule count

每 pod 启动时,istio-cni 插入 ~12-20 条 iptables 规则:
- mangle table: ~10 条
- nat table: ~5 条

GKE 节点默认 conntrack 表大小:
- 通常 262144 (~256K) entries
- 每 pod ~5-10 active connections(平均)
- **1000 pod / 节点 ≈ 5-10K connections**,远低于 conntrack 上限

### 3.3 kube-proxy 关系

> 这是关键问题:**ztunnel 的 iptables 与 kube-proxy 的 iptables 谁先生效?**

| 顺序 | 行为 |
|---|---|
| kube-proxy 先 → ztunnel 后 | ztunnel 在 kube-proxy 后插入规则,**优先级不影响** — ztunnel 用 `iptables -m mark` 跳过 kube-proxy 已处理连接 |
| ztunnel 先 → kube-proxy 后 | 同上 |

Istio 1.21+ 用 **in-pod netns 隔离**:ztunnel 的规则只插在**pod netns 内**,**不影响主机 netns 上的 kube-proxy 规则**。

**结论**:**ztunnel 与 kube-proxy 完全独立**,不会互相干扰。

---

## 4. 应用代码兼容性自查清单

| 自查项 | 期望值 | 验证方法 |
|---|---|---|
| **业务容器 listen 端口** | 不应是 15001/15006/15008/15080 | `kubectl exec <pod> -- ss -ntlp` |
| **业务用 UDP**(非 DNS) | 不能依赖 mesh 加密 | 看业务代码 |
| **业务用 QUIC / HTTP/3** | 不被 mesh 支持 | 看业务代码 |
| **业务访问 localhost:其他容器端口** | 正常走 lo | curl 测试 |
| **业务访问集群外域名** | 走 egress ztunnel,需 egressgateway | `kubectl exec <pod> -- curl https://example.com` |
| **业务用 Unix domain socket 通信** | 不进 mesh,正常 | 看业务代码 |

---

## 5. 诊断:从"看 envoy 日志"改成"看 ztunnel 日志"

| 场景 | sidecar 诊断 | ambient 诊断 |
|---|---|---|
| 连接超时 | 看业务 pod envoy 日志 | 看 ztunnel 日志(`kubectl logs ds/ztunnel`) |
| mTLS 失败 | 看业务 pod envoy TLS 错误 | 看 ztunnel 日志 `tls error` 关键字 |
| 路由失败 | 看业务 pod envoy route 404 | 看 waypoint 日志(如有 L7) |
| 流量拦截验证 | `iptables-save` 看业务 pod envoy chains | `iptables-save` 看 ISTIO_PRERT/ISTIO_OUTPUT chains |

**关键诊断命令**:

```bash
# 1. ztunnel inpod 日志(关键)
kubectl logs ds/ztunnel -n istio-system | grep inpod

# 2. 业务 pod 内 iptables
kubectl debug <pod> -it --image docker.io/istio/base --profile=netadmin \
  -n <ns> -- iptables-save | grep -E "ISTIO|15008|15001"

# 3. 业务 pod 内 socket(ztunnel 注入的端口)
kubectl debug <pod> -it -n <ns> --image nicolaka/netshoot -- ss -ntlp

# 4. 验证 mesh 流量是否被加密
kubectl exec <pod> -- tcpdump -i any -nn port 8080   # 看到的应是密文

# 5. 看 ztunnel 是否真的"认领"了该 pod
kubectl logs ds/ztunnel -n istio-system | grep <pod-uid>
```

---

## 6. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **in-pod iptables** | "pod 内 iptables 规则" | "istio-cni enters the pod's network namespace and establishes network redirection rules inside the pod network namespace" — [Ztunnel traffic redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/) |
| **TPROXY** | "透明代理,不改 IP" | "Linux TPROXY target redirects packets to a local socket without altering the destination address" — Linux kernel |
| **REDIRECT** | "改目的端口为本地端口" | "iptables REDIRECT target rewrites the destination to a local port (NAT)" — iptables manpage |
| **DNS capture** | "DNS 走 ztunnel" | "When ambient.dnsCapture is enabled, istio-cni redirects DNS lookups from pods to ztunnel for resolution through the mesh." — Istio cni chart values |
| **connmark 0x539** | "已认领连接" | ztunnel writes this mark for connections it has assumed; iptables uses it to skip already-handled connections |

---

## 7. 反向:什么时候别用 ambient

| 场景 | 推荐 |
|---|---|
| 业务用 QUIC / HTTP/3 | sidecar |
| 业务用大量 UDP 协议 | sidecar |
| 业务 listen 端口与 15001/15006/15008/15080 冲突 | 重构代码 |
| 业务同 pod 内多容器需要 sidecar-to-sidecar 通信 | 重构(应用不可行) |
| 集群规模 > 1000 pod / 节点 | sidecar + 谨慎测试 ambient(暂无大规模生产案例) |

---

## 8. References

- [Ztunnel traffic redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/) — iptables 规则权威说明
- [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/) — UDP / TCP / DNS 支持矩阵
- [Maturing Istio Ambient: Compatibility](https://istio.io/latest/blog/2024/inpod-traffic-redirection-ambient/) — in-pod redirection 设计
- [Istio Troubleshooting Ambient](https://github.com/istio/istio/wiki/Troubleshooting-Istio-Ambient) — 实战诊断清单
- [Linux TPROXY](https://www.kernel.org/doc/Documentation/networking/tproxy.txt) — 透明代理机制