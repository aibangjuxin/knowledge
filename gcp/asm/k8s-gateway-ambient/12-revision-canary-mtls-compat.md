# 双 Revision Canary 升级 — mTLS 证书兼容性与证书轮换细节

> **TL;DR**:
> - 双 revision 升级时,**SPIFFE 证书仍由 istiod 颁发**,cert-manager 视角下**只有一个 trust domain**
> - 但 **不同 revision 的 istiod 用不同 Service name**(如 `istiod-1-30` vs `istiod-1-31-canary`),**namespace 通过 `istio.io/rev` 选不同 Service**
> - **mTLS 跨 revision 兼容**:同 trust domain 的证书互通,**没有兼容性断点**
> - 真正要小心的:**rotation 期间短暂老证书不可用** 与 **DNS 缓存**

---

## 0. 双 Revision 升级时的证书拓扑

> 来源:
> - [Istio Canary Upgrades](https://istio.io/latest/docs/setup/upgrade/canary/)
> - [Istio Revision Tags](https://istio.io/latest/blog/2021/revision-tags/)
> - [Istio Istiod Certificate Authority](https://istio.io/latest/docs/concepts/security/#pki)

### 0.1 单一 mesh,多 istiod

```
┌─────────────────────────────────────────────────────────────┐
│                       Single Mesh                            │
│                 trust domain: cluster.local                   │
│                  mesh ID: my-mesh                            │
│                                                             │
│  istiod-1-30       istiod-1-31-canary                       │
│  Service: istiod-1-30   Service: istiod-1-31-canary       │
│  (默认 revision "")  (revision "1-31-canary")              │
│  CA: istiod-1-30    CA: istiod-1-31-canary                │
│                                                             │
│  ↓ 同一 trust domain                   │ 同一 trust domain  │
│  SPIFFE: spiffe://cluster.local/ns/X/sa/Y                   │
└─────────────────────────────────────────────────────────────┘
```

**关键事实**:
- 两个 istiod 都用**同一个根 CA**(集群启动时生成,存在 secret `istio-ca-secret` 里)
- 两个 istiod **各自签发** workload 证书
- 两个 istiod 签发的证书 **SPIFFE 兼容**(同一 trust domain = 互通)

### 0.2 workload 选哪个 istiod

```
namespace label: istio.io/rev=1-30         → workload 连 istiod-1-30
namespace label: istio.io/rev=1-31-canary  → workload 连 istiod-1-31-canary
namespace label: (无)                       → workload 连默认 istiod("")
```

**关键发现**:**两个 istiod Service 共存于同一集群,但通过 Service 名区分**。

```bash
# 验证
kubectl get svc -n istio-system -l app=istiod
# NAME                       TYPE        CLUSTER-IP      PORT(S)
# istiod                     ClusterIP   10.96.x.x       15010/TCP,15012/TCP,443/TCP
# istiod-1-31-canary         ClusterIP   10.96.y.y       15010/TCP,15012/TCP,443/TCP
```

---

## 1. mTLS 跨 revision 兼容性矩阵

| 客户端 revision | 服务端 revision | mTLS 结果 |
|---|---|---|
| `""` | `""` | ✅ 互通 |
| `""` | `1-31-canary` | ✅ 互通(同 trust domain) |
| `1-31-canary` | `""` | ✅ 互通 |
| `1-31-canary` | `1-31-canary` | ✅ 互通 |
| `""` | **不同 mesh ID 的集群** | ❌ 不互通 |

**关键**:只要**同一 cluster / 同一 mesh ID**,**任何 revision 组合都能互通**。

---

## 2. 证书轮换期间的行为

### 2.1 istiod 自身证书轮换

istiod 用 X509 证书与其他 istiod 通信、给 workload 签发证书:

| 时间点 | 行为 |
|---|---|
| istiod 启动 | 拉 `istio-ca-secret` 生成自己的 serving cert |
| 默认 24h 后 | istiod serving cert 自动轮换 |
| 工作负载证书 | **每 24h 自动轮换**(由 workload 上的 istio-agent 触发) |

**轮换期间**:
- istiod 短暂用旧 cert + 新 cert 双 serve(SNI 路由,无 downtime)
- workload 短暂同时持有新旧 cert(用于平滑切换)
- **理论上没有 mTLS 中断**

### 2.2 双 revision 时的证书 topology

```
Time T0: 装 canary istiod-1-31-canary
  ↓
  canary istiod 用集群根 CA 签发自己的 serving cert
  ↓
  给 canary ns 的 workload 签发 cert(spiffe://cluster.local/...)
  ↓
  workload cert 的 issuer 字段 = cluster root CA,与老 revision 签发的 cert 同根

Time T1: namespace 切到 revision=1-31-canary
  ↓
  workload 重启,从 canary istiod 拿 cert
  ↓
  **新 cert 的 SPIFFE ID 与老 cert 完全相同**(同 ns/sa)
  ↓
  对端验证 → 同 trust domain → 信任新 cert

Time T2: 退役老 revision
  ↓
  kubectl delete pod 老 istiod
  ↓
  老 revision 签发的 cert 仍存活(TTL 未到)
  ↓
  TTL 到期后老 cert 失效,只剩 canary 签发的新 cert
```

**结论**:**双 revision 期间没有任何 mTLS 兼容性断点**。

---

## 3. 真正会出问题的边界 case

| 边界 case | 现象 | 触发条件 |
|---|---|---|
| **trust domain 改了** | 跨 revision mTLS 失败 | 升级时改了 `meshConfig.trustDomain` |
| **mesh ID 改了** | 跨集群联邦失效 | 升级时改了 `meshConfig.meshId` |
| **证书 TTL 过期** | workload 短暂拿不到新 cert | istiod 重启超过 cert TTL(默认 24h,正常重启不会) |
| **DNS 缓存** | namespace 切 rev 后,旧 istiod endpoint 仍被缓存 | K8s CoreDNS 默认 TTL 30s,可手动 flush |
| **proxy-config 推送延迟** | 新 revision 的 XDS 配置推到 client 延迟 | istiod 重启 + ztunnel/sidecar 重连 |
| **Waypoint 重启导致 in-flight 请求失败** | 业务报 503 | L7 流量 + waypoint 滚动重启 |

**这些边界 case 都不是"双 revision 不兼容",而是"任何升级都会遇到"的常规问题**。

---

## 4. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **Revision** | "istiod 的版本标签" | "A revision is a label applied to istiod (and dependent charts) that namespaces opt into via the `istio.io/rev` label." — [Istio Canary](https://istio.io/latest/docs/setup/upgrade/canary/) |
| **trust domain** | "证书信任域" | "The trust domain is a DNS domain used to authenticate the workload's identity in the SPIFFE format." — [Istio Security](https://istio.io/latest/docs/concepts/security/) |
| **Root CA** | "集群根证书" | "A root certificate authority (CA) is the source of truth for trust in the mesh; it is stored in the `istio-ca-secret` and shared across all istiod revisions." — Istio docs |
| **SPIFFE ID** | "服务身份字符串" | "spiffe://\<trust-domain\>/ns/\<namespace\>/sa/\<service-account\>" — SPIFFE spec |

---

## 5. 双 revision canary 的证书最佳实践

### 5.1 升级前

```bash
# 验证集群根 CA 状态
kubectl get secret istio-ca-secret -n istio-system -o yaml

# 验证 cert TTL 配置
istioctl proxy-config secret <pod-name> -n <ns>
# 看 cert 的 notAfter 字段
```

### 5.2 升级中(本目录 05 文 Step 1-3)

```bash
# 装 canary revision(不替换老 revision)
helm upgrade --install istiod-1-31-canary ... -f values/istiod-1-31.yaml

# 验证双 revision 都在跑
kubectl get pods -n istio-system -l app=istiod
# 预期:istiod-1-30 + istiod-1-31-canary 双 2 副本

# 验证双 revision 的 Service
kubectl get svc -n istio-system -l app=istiod
# 预期:istiod + istiod-1-31-canary

# canary ns 切到新 revision
kubectl label namespace <canary-ns> istio.io/rev=1-31-canary --overwrite
kubectl rollout restart deployment -n <canary-ns>
```

### 5.3 升级中观察(关键)

```bash
# 1. 看证书轮换是否正常(canary ns 的 workload)
istioctl proxy-config secret <canary-pod> -n <canary-ns>
# 看 issuer = 集群 root CA,subject = spiffe://cluster.local/...

# 2. 跨 revision mTLS 互通测试
kubectl exec -n <old-ns> <old-pod> -- curl https://<canary-svc>.<canary-ns>:port
# 预期:成功(同 trust domain)

# 3. 看证书 TTL 是否有差异
istioctl proxy-config secret <canary-pod> -n <canary-ns> -o json | jq '.validationContext.sdsSecretConfig.name'
# 预期:与老 ns 同一 trust bundle

# 4. Prometheus 监控证书轮换
kubectl exec -n istio-system deploy/prometheus -- \
  promtool query instant 'istio_cert_mismatches_count' || true
```

### 5.4 升级后退役老 revision

```bash
# 验证所有 workload 已切到新 revision
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.metadata.namespace != "istio-system") |
  {ns: .metadata.namespace, rev: (.metadata.labels["istio.io/rev"] // "<none>")} |
  "\(.ns)\t\(.rev)"' | sort | uniq -c

# 预期:所有业务 ns 都是 1-31-canary(或更新版)
# 如果还有 ns 是 "<none>"(默认 revision),需要显式标
```

---

## 6. 反向:什么时候**不**用双 revision

| 场景 | 推荐 |
|---|---|
| dev / test 集群 | 单 revision(简单快速) |
| 中小生产 + 接受短暂中断(< 30s) | 单 revision |
| 大型生产 / 关键业务 | 双 revision canary |
| 跨集群 mesh | 双 revision(每个集群独立验证) |
| 集群证书 TTL 配置异常 | **先修证书**,再考虑升级 |

---

## 7. 给本场景的具体建议

dev 集群现状(1.30.3 minimal profile):
- **没有 AuthorizationPolicy / PeerAuthentication**(06 文是知识储备)
- **没有多 revision**(单一 revision="")
- **入口 Gateway**(sidecar)+ **业务 pod**(sidecar)— 都在用同一 istiod

**本场景升级路径**:

```
Phase 0(当前): minimal profile, revision=""
Phase 1: 装 ambient(02 文)
         仍然 revision="", 新装 istio-cni + ztunnel
Phase 2: 业务 ns 迁 ambient(04 文)
Phase 3: **这里**才考虑双 revision 升级 1.30 → 1.31
         用 05 文路径 D
```

**Phase 3 时的注意事项**:
1. 升 istiod 时,**ztunnel 与 istio-cni 也需要跟着升**(用同一 tag,Helm 拆分的好处)
2. **先升 canary**,验证 1-2 周,**再全量**
3. **退役老 revision 前**,确认所有 ns 都有 `istio.io/rev` label
4. **不要跨 trust domain 升** — 1.30 → 1.31 trust domain 不变

---

## 8. References

- [Istio Canary Upgrades](https://istio.io/latest/docs/setup/upgrade/canary/) — 双 revision 安装
- [Istio Revision Tags](https://istio.io/latest/blog/2021/revision-tags/) — revision tag 高级用法
- [Istio Istiod CA](https://istio.io/latest/docs/concepts/security/#pki) — 根 CA 共享
- [Istio Security Concepts](https://istio.io/latest/docs/concepts/security/) — mTLS / SPIFFE 全景
- [SPIFFE Spec](https://github.com/spiffe/spiffe/blob/main/standards/SPIFFE.md) — SPIFFE ID 格式
- [Istio Cert Rotation](https://istio.io/latest/docs/ops/best-practices/security/#rotate-the-istio-root-certificate-and-the-intermediate-certificates) — 证书轮换最佳实践
- 同仓库 `k8s-gateway-ambient/05-upgrade-strategies.md` — 升级流程