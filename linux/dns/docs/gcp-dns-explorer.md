# GCP DNS Explorer — GKE DNS 深度探索与故障排查

> **目标：** 从 GKE Pod 的视角出发，逐层深入理解 DNS 解析的完整路径，解释 DNS Peering 的工作机制，以及排查你在实际环境中遇到的 `aibang.cluster.local` 异常查询和 DNS 超时问题。
>
> **你的环境概要：**
> - VPC1 (Shared VPC)：连接公司内部网络，配置了 Forwarding Zone，将 `aibang.` 等域名转发到公司内部 DNS 服务器
> - VPC2 (Private VPC)：运行 GKE 环境，Pod 使用 VPC DNS 解析器 `169.254.254.254`
> - GKE 使用 Cloud DNS (169.254.254.254)，未使用 kube-dns/CoreDNS 作为主要解析器

---

## 1. 从 Pod 出发 — DNS 解析的真实起点

### 1.1 Pod 内的 /etc/resolv.conf

登录到一个运行的 Pod，你看到的 `/etc/resolv.conf` 大致是：

```
nameserver 10.x.x.x          ← 实际上是 kube-dns/CoreDNS 的 ClusterIP
search <namespace>.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

**关键点：** Pod 本身并不知道 169.254.254.254 的存在。kubelet 在创建 Pod 时注入了这个 resolv.conf。Pod 以为自己是在向 kube-dns 发送查询。

### 1.2 实际数据面 — ndots 搜索路径的完整行为

`ndots:5` 是一个容易被误解的参数。它的含义是：

```
如果查询的 FQDN 中 dots（.）的数量 < 5
  → 先依次追加 search 列表中的搜索域进行查询
  → 全部失败后，才尝试原始查询

如果查询的 FQDN 中 dots（.）的数量 >= 5
  → 直接查询原始 FQDN，不再追加 search 域
```

**实际行为分解（假设你在 default namespace）：**

```bash
# 查询 "api"（1个dot）
# 实际查询顺序：
#   1. api.default.svc.cluster.local
#   2. api.svc.cluster.local
#   3. api.cluster.local
#   4. api  （原始查询）
#   全部失败 → 超时或返回 NXDOMAIN

# 查询 "my-svc"（1个dot，同样行为）
#   → my-svc.default.svc.cluster.local → 失败
#   → my-svc.svc.cluster.local → 失败
#   → my-svc.cluster.local → 失败
#   → my-svc → 失败

# 查询 "api.internal"（2个dots）
#   → api.internal.default.svc.cluster.local → 失败
#   → api.internal.svc.cluster.local → 失败
#   → api.internal.cluster.local → 失败
#   → api.internal → 失败

# 查询 "api.aliyun.cloud.region"（4个dots）
#   → api.aliyun.cloud.region.default.svc.cluster.local → 失败
#   → api.aliyun.cloud.region.svc.cluster.local → 失败
#   → api.aliyun.cloud.region.cluster.local → 失败
#   → api.aliyun.cloud.region → 失败

# 查询 "api.aliyun.cloud.region.aibang"（5个dots，满足 ndots>=5）
#   → 直接查询 api.aliyun.cloud.region.aibang（不追加任何 search）
```

### 1.3 你的实际场景 — ndots 与 aibang 域名

你遇到的查询 `api.aliyun.cloud.region.aibang`：

- 这个 FQDN 有 **5 个 dots**：`api` + `gcp` + `cloud` + `region` + `aibang`
- 由于 ndots=5，刚好满足 `>=5` 的条件
- **理论上应该直接查询原始 FQDN，不会追加 search 路径**

但你看到的实际情况是它在尝试 `aibang.cluster.local` 的解析，这说明：

**可能的原因：kube-dns/CoreDNS 收到了原始查询后，在集群内部找不到对应记录，然后做了递归查询，递归到了错误的路径。**

---

## 2. GKE 中的两条 DNS 路径

GKE 中实际上存在**两套并行的 DNS 路径**：

### 路径 A：kube-dns/CoreDNS 路径（集群内部服务发现）

```
Pod → kube-dns Service (10.x.x.x) → CoreDNS (kube-system namespace)
```

这是 Kubernetes 原生的服务发现机制，处理：
- `<service>.<namespace>.svc.cluster.local`
- `<service>.cluster.local`

### 路径 B：VPC DNS 解析器路径（Cloud DNS）

```
Pod → 169.254.254.254 → Cloud DNS Decision Engine
```

这是 GCP 层面的 DNS，处理：
- DNS Peering
- Forwarding Zone
- Response Policy
- 公网递归查询

**在你的 GKE 环境中，由于 Pod 的 resolv.conf 指向了 kube-dns（10.x.x.x），kube-dns 本身会将无法解析的查询转发到 VPC DNS。**

### 2.1 关键理解：kube-dns 是转发器，不是递归器

kube-dns/CoreDNS（在 GKE 中）**并不是一个完整的递归 DNS 服务器**。它的行为是：

```
收到查询请求
  ↓
检查是否为集群内部域名？（<service>.<ns>.svc.cluster.local）
  → 是：返回服务 ClusterIP 或 Endpoints IP
  → 否：转发到上游 DNS
```

**这个"上游 DNS"在 GKE 中默认就是 169.254.254.254（VPC DNS）。**

所以完整的解析链是：

```
Pod resolv.conf → kube-dns (10.x.x.x)
                      ↓ (无法解析时)
                   VPC DNS (169.254.254.254)
                      ↓ (匹配规则)
                   Forwarding Zone / Peering / 递归
```

---

## 3. 你的 aibang.cluster.local 异常查询 — 根因分析

### 3.1 问题现象

你在查询 `api.aliyun.cloud.region.aibang`，但看到它在尝试解析 `aibang.cluster.local`。

### 3.2 为什么会出现 aibang.cluster.local？

问题出在 **ndots 搜索路径和 kube-dns 的处理逻辑**：

**情况分析：**

当 ndots=5 时，`api.aliyun.cloud.region.aibang` 有 5 个 dots，本应**直接查询原始 FQDN**。但你观察到了 `aibang.cluster.local` 的查询，说明：

1. **Pod 先将查询发给了 kube-dns**
2. **kube-dns 无法解析 `api.aliyun.cloud.region.aibang`**
3. **kube-dns 将查询转发到 VPC DNS**
4. **VPC DNS 也无法解析（或查询方式不对）**
5. **某些组件在错误地追加 search 路径**

**最可能的根因：你的查询被 kube-dns 截获，kube-dns 在内部做了一个错误的 search 追加。**

### 3.3 ndots 配置对 aibang 域名的影响

| ndots 值 | `api.aliyun.cloud.region.aibang` 的行为 |
|---------|--------------------------------------|
| ndots:5 | 直接查询原始 FQDN（5 dots >= 5） |
| ndots:4 | 先追加 search 路径（4 dots < 5） |

**如果你的 ndots 是 4 而不是 5：**

```
查询 api.aliyun.cloud.region.aibang（4 dots）
  → api.aliyun.cloud.region.aibang.default.svc.cluster.local → 失败
  → api.aliyun.cloud.region.aibang.svc.cluster.local → 失败
  → api.aliyun.cloud.region.aibang.cluster.local → 失败  ← 你看到的就是这个！
  → api.aliyun.cloud.region.aibang → 失败
```

**这就是你看到 `aibang.cluster.local` 查询的原因！**

### 3.4 解决方案

**方案 1：提高 ndots 值**

```yaml
# 在 Pod spec 中设置
dnsPolicy: ClusterFirst
dnsConfig:
  nameservers:
    - 169.254.254.254
  searches:
    - <namespace>.svc.cluster.local
    - svc.cluster.local
    - cluster.local
  options:
    - name: ndots
      value: "6"  # 提高到 6，确保 .aibang 结尾的查询直接发送
```

**方案 2：使用完整 FQDN**

在应用代码中，总是使用完整 FQDN：
- `api.aliyun.cloud.region.aibang.` （注意尾部的 `.` 表示绝对 FQDN）

**方案 3：绕过 kube-dns，直接查询 VPC DNS**

修改 Pod 的 dnsPolicy 为 `Default`，让 Pod 直接使用宿主机的 DNS 配置（宿主机的 /etc/resolv.conf 指向 169.254.254.254）：

```yaml
dnsPolicy: Default
```

---

## 4. DNS Peering vs Forwarding Zone — 你的场景中如何工作

### 4.1 你的环境配置

```
VPC2 (Private GKE) ← DNS Peering ← VPC1 (Shared VPC)
                                  ← Forwarding Zone: aibang. → 内部 DNS
```

### 4.2 DNS Peering 的工作原理

DNS Peering 是**拉取**模式：

```
VPC2 的 Cloud DNS
    ↓
收到查询 api.aliyun.cloud.region.aibang
    ↓
检查是否有匹配的 Peering Zone？→ 有：aibang. 指向 VPC1
    ↓
通过 VPC Network Peering 将查询发送到 VPC1 的 Cloud DNS
    ↓
VPC1 的 Cloud DNS 收到查询
    ↓
检查是否有匹配的 Forwarding Zone？→ 有：aibang. → 内部 DNS 服务器
    ↓
内部 DNS 服务器返回解析结果
```

### 4.3 DNS Peering 与 Forwarding Zone 的优先级

在同一个 VPC 内，Cloud DNS 的决策顺序是：

```
Response Policy（最高优先级）
    ↓
DNS Peering
    ↓
Forwarding Zone
    ↓
默认递归（公网查询）
```

**关键点：** 当你在 VPC2 配置了 DNS Peering for `aibang.`，VPC2 会通过 Peering 连接到 VPC1。VPC1 上的 Forwarding Zone 会将查询转发到内部 DNS。

### 4.4 你的 aibang 域名查询流程

```
Pod 查询 api.aliyun.cloud.region.aibang
    ↓
kube-dns (10.x.x.x) 收到查询
    ↓
kube-dns 无法解析 → 转发到 VPC DNS (169.254.254.254)
    ↓
VPC DNS 检查匹配规则：
  1. Response Policy？→ 无
  2. DNS Peering？→ 有！aibang. 匹配 Peering Zone
    ↓
  通过 VPC Peering 发送到 VPC1 的 Cloud DNS
    ↓
  VPC1 的 Cloud DNS 检查：
    3. Forwarding Zone？→ 有！aibang. → 内部 DNS 服务器
      ↓
    内部 DNS 服务器返回解析结果
    ↓
结果沿原路返回到 Pod
```

---

## 5. DNS 超时问题 — 是否需要扩容

### 5.1 你观察到的超时现象

```
查询 100.68.0.10 超时
```

**注意：** `100.68.0.10` 是 kube-dns/CoreDNS 的 ClusterIP，不是 VPC DNS。

### 5.2 超时原因分析

**DNS 超时通常有以下几个原因：**

| 原因 | 表现 | 排查方法 |
|------|------|----------|
| kube-dns/CoreDNS 负载过高 | 解析缓慢或超时 | `kubectl top pods -n kube-system -l k8s-app=kube-dns` |
| 上游 DNS 服务器响应慢 | 转发到 169.254.254.254 超时 | 检查 VPC DNS 的 Forwarding Target |
| 网络路径不通 | 完全超时 | 检查 VPC Firewall Rules 是否允许 UDP/TCP 53 |
| Forwarding Target 不可达 | SERVFAIL | 检查内部 DNS 服务器状态 |
| DNS 查询量超过容量 | 解析缓慢或超时 | 监控 Cloud DNS 查询量 |

### 5.3 扩容判断

**需要扩容 DNS 的典型信号：**

1. **Pod 内观察到的超时**
   ```bash
   # 在 Pod 内执行
   time nslookup api.aliyun.cloud.region.aibang
   # 如果 time 显示 > 2s，说明有延迟
   ```

2. **VPC DNS 层面观察**
   ```bash
   # 在 GKE 节点或 VM 上执行
   dig @169.254.254.254 api.aliyun.cloud.region.aibang
   # 观察 query time
   ```

3. **Cloud DNS 查询日志**
   ```bash
   gcloud logging read \
     'resource.type="dns_query" AND query_name="api.aliyun.cloud.region.aibang."' \
     --limit=50 --order=desc
   ```

**扩容方案：**

1. **启用 Node Local DNS Cache**
   ```bash
   gcloud container clusters update YOUR_CLUSTER \
     --zone=ZONE \
     --enable-node-local-dns-cache
   ```
   这样每个节点都有自己的本地 DNS 缓存，减少对上游 DNS 的压力。

2. **增加 kube-dns/CoreDNS 副本数**
   ```bash
   kubectl scale deployment kube-dns -n kube-system --replicas=3
   ```

3. **优化 ndots 设置**
   减少不必要的 search 路径查询，降低 DNS 负载。

---

## 6. 完整 DNS 解析流程图

```
┌─────────────────────────────────────────────────────────────────┐
│                        Pod 内核                                  │
│  /etc/resolv.conf:                                              │
│    nameserver: 10.x.x.x (kube-dns ClusterIP)                     │
│    search: ns.svc.cluster.local svc.cluster.local cluster.local  │
│    options: ndots:5                                              │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
                   发送 DNS 查询请求
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                   kube-dns/CoreDNS                              │
│  位置：kube-system namespace                                     │
│  功能：集群内部服务发现 + 转发上游                                 │
│                                                                 │
│  收到查询 api.aliyun.cloud.region.aibang                            │
│    ↓                                                            │
│  是集群内部域名？                                                 │
│    → 否：转发到上游 DNS                                          │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
                   kube-dns → VPC DNS
                   转发无法解析的查询
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│              VPC DNS Resolver (169.254.254.254)                  │
│                                                                 │
│  检查匹配顺序：                                                  │
│    1. Response Policy？     → 无                                │
│    2. DNS Peering Zone？   → 有！匹配 aibang.                  │
│    3. Forwarding Zone？     → 检查（在 VPC1 上）                │
│    4. 默认递归？            → 不执行                            │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
                   通过 VPC Peering
                   转发到 VPC1 DNS
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│              VPC1 Cloud DNS (Shared VPC)                        │
│                                                                 │
│  检查匹配：                                                      │
│    1. Response Policy？     → 无                                │
│    2. DNS Peering Zone？   → 无（这里是 Forwarding）           │
│    3. Forwarding Zone？     → 有！匹配 aibang.                  │
│    4. 默认递归？            → 不执行                            │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
                   转发到内部 DNS 服务器
                   (你的公司内部 DNS)
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│              公司内部 DNS 服务器                                  │
│                                                                 │
│  解析 api.aliyun.cloud.region.aibang                               │
│  返回对应 IP 地址                                                │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
                   返回结果到 VPC1 DNS
                             ↓
                   返回结果到 VPC2 DNS
                             ↓
                   返回结果到 kube-dns
                             ↓
                   返回结果到 Pod
```

---

## 7. 你的场景中 aibang.cluster.local 的完整解释

### 7.1 为什么会出现 aibang.cluster.local？

结合你的环境，最可能的原因是：

**ndots 配置问题 + kube-dns 的 search 路径行为**

当你查询 `api.aliyun.cloud.region.aibang`：

1. 如果 ndots=4（而不是 5），这个 FQDN 只有 4 个 dots
2. kube-dns 会先尝试追加 search 路径：
   - `api.aliyun.cloud.region.aibang.default.svc.cluster.local`
   - `api.aliyun.cloud.region.aibang.svc.cluster.local`
   - `api.aliyun.cloud.region.aibang.cluster.local` ← 你看到的查询！
3. 全部失败后，才查询原始 FQDN

### 7.2 验证方法

**检查 Pod 的 ndots 配置：**

```bash
kubectl exec -it <pod-name> -- cat /etc/resolv.conf
# 查看 options ndots 的值
```

**检查实际的 DNS 查询：**

```bash
# 使用 tcpdump 在 Pod 内抓包
kubectl exec -it <pod-name> -- tcpdump -i any -n port 53

# 在另一个终端触发 DNS 查询
kubectl exec -it <pod-name> -- nslookup api.aliyun.cloud.region.aibang
```

**直接在 VPC DNS 层面测试：**

```bash
# 在 GKE 节点或 VM 上
dig @169.254.254.254 api.aliyun.cloud.region.aibang +short
dig @169.254.254.254 api.aliyun.cloud.region.aibang.cluster.local +short
```

### 7.3 根本解决

**如果你的目标是让所有 `.aibang` 结尾的域名走 Shared VPC 的 DNS 解析：**

1. **确保 VPC2 配置了 DNS Peering for `aibang.`**

2. **调整 ndots 值：**
   ```yaml
   # Pod spec
   dnsConfig:
     options:
       - name: ndots
         value: "3"  # 或者更低，让所有 .aibang 查询直接走 FQDN
   ```

3. **或者在应用中使用完整 FQDN：**
   应用代码中使用 `api.aliyun.cloud.region.aibang.`（尾部加点）

---

## 8. 排查命令速查表

### 8.1 Pod 内排查

```bash
# 1. 检查 resolv.conf
kubectl exec -it <pod> -- cat /etc/resolv.conf

# 2. 检查 ndots 值
kubectl exec -it <pod> -- cat /etc/resolv.conf | grep ndots

# 3. 手动 DNS 查询
kubectl exec -it <pod> -- nslookup api.aliyun.cloud.region.aibang
kubectl exec -it <pod> -- nslookup api.aliyun.cloud.region.aibang 169.254.254.254

# 4. 抓包查看实际查询
kubectl exec -it <pod> -- tcpdump -i any -n port 53 -c 20

# 5. 查看 DNS 解析时间
kubectl exec -it <pod> -- sh -c 'time nslookup api.aliyun.cloud.region.aibang'
```

### 8.2 VPC DNS 层面排查

```bash
# 1. 直接查询 VPC DNS
dig @169.254.254.254 api.aliyun.cloud.region.aibang +short
dig @169.254.254.254 api.aliyun.cloud.region.aibang +trace

# 2. 检查 DNS Peering 配置
gcloud dns managed-zones list \
  --filter="dnsName:aibang."

# 3. 检查 zone 详情
gcloud dns managed-zones describe <zone-name> \
  --format="yaml(visibility,peeringConfig,forwardingConfig)"

# 4. 查看 Cloud DNS 查询日志
gcloud logging read \
  'resource.type="dns_query"' \
  --filter='query_name="api.aliyun.cloud.region.aibang."' \
  --limit=20 --order=desc
```

### 8.3 kube-dns/CoreDNS 排查

```bash
# 1. 检查 kube-dns Pod 状态
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 2. 查看 kube-dns 日志
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100

# 3. 检查 kube-dns 配置
kubectl get configmap -n kube-system kube-dns -o yaml

# 4. 扩展 kube-dns 副本数（如果需要）
kubectl scale deployment kube-dns -n kube-system --replicas=3
```

---

## 9. DNS 超时与扩容评估流程

```
DNS 超时问题排查流程：

Step 1: 确认超时位置
  ↓
  Pod 内 nslookup 超时
    → kube-dns 问题？
    → 还是上游 VPC DNS 问题？
  ↓
Step 2: 隔离测试
  kubectl exec -it <pod> -- nslookup api.aliyun.cloud.region.aibang 169.254.254.254
  如果超时消失 → 问题在 kube-dns
  如果仍然超时 → 问题在 VPC DNS 或网络
  ↓
Step 3: 检查 kube-dns 负载
  kubectl top pods -n kube-system -l k8s-app=kube-dns
  CPU/内存是否打满？
  ↓
Step 4: 检查 VPC DNS 日志
  gcloud logging read \
    'resource.type="dns_query" AND latency>"1s"' \
    --limit=50
  ↓
Step 5: 扩容决策
  如果 kube-dns 负载高 → 扩容 kube-dns
  如果 VPC DNS 慢 → 优化 Forwarding Target 或启用 Node Local DNS Cache
```

---

## 10. 相关文件参考

| 文件 | 说明 |
|------|------|
| `gcp-dns-forwarding.md` | Cloud DNS Forwarding Zone 深度解析 |
| `gke-dns-resolution-flow.md` | GKE DNS 解析完整流程 |
| `dns-peerning.md` | DNS Peering 配置与使用 |
| `kube-dns.md` | kube-dns/CoreDNS 配置参考 |
| `cloud-dns.md` | Cloud DNS 通用概述 |

---

## 11. 关键结论

1. **aibang.cluster.local 异常查询的原因：**
   - 最可能是 ndots 配置值偏低（ndots=4），导致查询被追加了 cluster.local search 路径
   - 将 ndots 提高到 5 或更高，或在应用中使用完整 FQDN 可解决

2. **DNS 超时是否需要扩容：**
   - 需要先确认超时发生在哪一层（Pod → kube-dns → VPC DNS → 内部 DNS）
   - 如果是 kube-dns 负载问题，扩容 kube-dns 副本
   - 如果是 VPC DNS 层面慢，启用 Node Local DNS Cache 或优化 Forwarding Target

3. **DNS Peering 工作正常：**
   - 你的配置（VPC2 Peering → VPC1 Forwarding）是正确的
   - 只要 aibang. 的 Peering 和 Forwarding Zone 配置正确，所有 .aibang 域名应该能正确解析

---

*Document version: 1.0.0 — 2026-05-22*
