# GKE DNS 解析与 ndots 行为详解

> 基于 `gcp-dns-explorer-gpt5-6.md` 校正，纠正了 `ndots` 计数和查询序列的错误认知。

---

## 1. Pod DNS 查询三跳模式

```
Pod 内 /etc/resolv.conf → nameserver 配置决定第一跳

┌────────────────────────────────────────────────────────┐
│ 169.254.20.10         → NodeLocal DNSCache            │
│ 169.254.169.254       → Cloud DNS for GKE data plane   │
│ 10.x.x.x (ClusterIP)  → kube-dns Service              │
└────────────────────────────────────────────────────────┘
```

**生产排查第一步**：不要假设，用 `kubectl exec -it POD_NAME -- cat /etc/resolv.conf` 确认。

---

## 2. ndots 精确行为规则

**ndots 配置影响的是普通分隔点数量（非尾部 root 点）**：

| 场景 | 查询名 | 普通分隔点 | ndots 配置 | resolver 行为 |
|------|--------|-----------|------------|---------------|
| `*.svc.cluster.local` | `api-svc.team-b.svc.cluster.local` | 4 个 | `ndots:5` | 4 < 5 → **先追加 search path，再查原始名** |
| 外部 Team 域名 | `api-svc.team-b.appdev.aibang` | 3 个 | `ndots:5` | 3 < 5 → **先追加 search path，再查原始名** |
| 绝对 FQDN | `api-svc.team-b.appdev.aibang.` | 3 + root 点 | 任意 | **直接按绝对名字查询，不走 search path** |

**注意**：`api-svc.team-b.appdev.aibang` 只有 **3 个普通分隔点**（api-svc, team-b, appdev, aibang 前三个间隔），不是 5 个。原错误认为 "含 5 个点" 导致判断 `5 >= 5` 先查原始名，实际 `3 < 5` 应先走 search path。

---

## 3. 完整查询序列（以 ndots:5 为例）

```
应用查询：api-svc.team-b.appdev.aibang（3 个普通分隔点，3 < 5）

序列：
1. api-svc.team-b.appdev.aibang.<namespace>.svc.cluster.local  → NXDOMAIN
2. api-svc.team-b.appdev.aibang.svc.cluster.local              → NXDOMAIN
3. api-svc.team-b.appdev.aibang.cluster.local                   → NXDOMAIN
4. api-svc.team-b.appdev.aibang.<project>.internal              → NXDOMAIN
5. api-svc.team-b.appdev.aibang                                 → 最终查询原始名 → 外部 DNS
```

**关键结论**：外部 Team 域名因为 `3 < 5` 会先触发 4 次 search path 拼接（N+1 查询问题），造成不必要的解析延迟。推荐使用 **尾部点 FQDN**（`api-svc.team-b.appdev.aibang.`）跳过 search path。

---

## 4. FQDN 尾部点 vs 非 FQDN 的区别

```
api-svc.team-b.appdev.aibang      → 相对名字，resolver 会追加 search path
api-svc.team-b.appdev.aibang.     → 绝对 FQDN，resolver 直接按原名查询，不走 search

带尾部点的 FQDN 是比 ndots 更直接的表达：
  - 不受 ndots 配置影响
  - 不产生 N+1 查询
  - 适合排查和底层 DNS lookup
```

**生产建议**：
- 企业内部域名、外部域名、跨 VPC 域名：**使用尾部点 FQDN**（如 `api-svc.team-b.appdev.aibang.`）
- HTTP Host、TLS SNI、证书 SAN、Gateway HTTPRoute hostnames：仍使用不带尾部点的服务名（浏览器/客户端会自动处理）
- 如果 URL 中直接写尾部点，必须先验证 Java HTTP client、TLS 证书校验、Gateway Host 匹配是否接受

---

## 5. CoreDNS 转发链（基于参考文档校正）

```
Pod DNS Query
  ↓
CoreDNS（kube-dns Pod）
  ↓
Zone 匹配顺序（从上到下，优先级递减）：

① kubernetes cluster.local     → K8s Service/Pod 权威解析
② svc.cluster.local            → 同上，svc 层级
③ <namespace>.svc.cluster.local → search 路径展开的结果
④ cluster.local                → search 路径展开
⑤ .（根 zone）                 → 所有未知域名转发上游

上游：forward . 10.60.0.2  # GCP 内部 DNS 网关
```

**注意**：`forward . 10.60.0.2` 转发到 GCP 内部 DNS（`35.199.192.0/19` 源地址），不是公网 DNS。所有非 K8s 域名的查询都通过此路径转发到 Cloud DNS。

---

## 6. Split-Horizon DNS 与 Kong Upstream 的坑

```
Pod A 查询：api-svc.team-b.appdev.aibang
  → ndots=5，3 < 5 → 先走 search path（4 次 NXDOMAIN）
  → 第 5 次查询原始名 → CoreDNS 转发到 GCP 内部 DNS
  → Split-horizon DNS 返回：GLB 公网 IP
  → Kong Pod 认为 target 是外部目标
  → 流量出集群：Kong Pod → 公网 → GLB → Pod B
  → 错误！Kong 应该连接集群内部 Pod
```

**正确做法**：Kong upstream 使用 K8s Service 名称（`*.svc.cluster.local`），CoreDNS 直接解析到 ClusterIP，流量不走公网。

---

## 7. DNS 缓存三层

| Layer | 缓存方 | 失效机制 | 问题 |
|-------|--------|---------|------|
| Layer 1 | Pod glibc | Pod 重启前永不失效 | TTL 过期后 IP 指向已不存在 Pod |
| Layer 2 | CoreDNS | K8s Service 变更时主动失效 | Pod IP 变化不主动通知 |
| Layer 3 | Istio Sidecar (Envoy) | EndpointSlice 同步 | Pod 重建后可能路由到旧 Pod |

**解决方案**：应用程序使用 K8s Service 名称，kube-proxy 做负载均衡，EndpointSlice 感知变化后自动更新。

---

## 8. 参考命令

```bash
# 1. 检查 Pod 的 /etc/resolv.conf
kubectl exec -it <pod-name> -n <namespace> -- cat /etc/resolv.conf

# 2. 测试 K8s DNS 解析
kubectl exec -it <pod-name> -n <namespace> -- nslookup api-svc.team-b.svc.cluster.local

# 3. 测试外部域名（观察 search path 行为）
kubectl exec -it <pod-name> -n <namespace> -- nslookup api-svc.team-b.appdev.aibang.

# 4. 检查 CoreDNS ConfigMap
kubectl get configmap coredns -n kube-system -o yaml

# 5. 检查 CoreDNS 日志（查看转发情况）
kubectl logs -n kube-system -l k8s-app=kube-dns -c coredns --tail=100
```

---

## 9. 相关文档

- 完整 DNS 架构指南：`/Users/lex/git/knowledge/linux/dns/docs/external-internal-dns-separation.md`
- 参考基准：`/Users/lex/git/knowledge/linux/dns/docs/gcp-dns-explorer-gpt5-6.md`
- Pod 间证书评估：`/Users/lex/git/knowledge/safe/ssl/docs/claude/pod-cert-replacement-evaluation.md`