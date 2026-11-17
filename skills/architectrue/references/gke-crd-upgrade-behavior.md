# GKE CRD 升级保留行为 — Session Explorer

**会话时间**: 2026-05-29  
**用户**: Lex — GCP Infra Engineer  
**主题**: GKE 集群升级后 CRD 和 CR 实例是否保留

---

## 结论

| 资源类型 | GKE 升级后是否保留 |
|---------|-----------------|
| 用户自行 `kubectl apply` 的 CRD | ✅ 保留 |
| CRD 对应的 CR 实例 | ✅ 保留 |
| GKE 内置 CRD（Gateway API 标准 CRD） | ✅ 保留 |
| Istio CRD（GKE 升级不升级 Istio 版本） | ✅ 保留 |
| Istio CRD（同时升级 Istio 版本） | ⚠️ 可能有 schema 变更 |

**核心机制**: CRD 定义和 CR 实例存储在 etcd 中。GKE 升级是控制平面组件原地替换，不清空 etcd，不重置 CRD 定义。

---

## ListenerSet 专项发现

- `listenersets.gateway.networking.k8s.io` 创建时间 `2026-05-29T02:38:00Z`
- 同时间段批量创建的还有 `backendtlspolicies`、`grpcroutes`、`tcproutes`、`tlsroutes`、`udproutes`、`xbackendtrafficpolicies`、`xmeshes` — 时间高度一致（02:38:00 ~ 02:38:01），说明这批 CRD 是通过同一组件/操作批量安装的
- ListenerSet CRD 由 GKE Gateway Controller 管理 CR 实例，CRD 定义本身不由 Controller 管理
- `+kubebuilder:storageversion` 注解表明这是该资源的存储版本，由 API Server 直接持久化到 etcd

### 手动创建 vs 自动安装无区别

无论哪种创建方式，CRD + CR 实例都在 etcd 中，GKE 升级不影响。唯一的"风险"是控制平面升级期间（分钟级）API Server 不可用，所有资源都无法访问——这是预期行为，不是数据丢失。

---

## 验证命令

```bash
# 备份所有 CRD 定义
kubectl get crd -o yaml > crd-backup-$(date +%Y%m%d).yaml

# 升级前记录 ListenerSet CR 实例
kubectl get listenerset -A -o yaml > /tmp/listenersets-before-$(date +%Y%m%d).yaml

# 升级后验证
kubectl get crd listenersets.gateway.networking.k8s.io
kubectl get listenerset -A
diff /tmp/listenersets-before-*.yaml <(kubectl get listenerset -A -o yaml)
```

---

## 关键误解澄清

1. **GKE 升级会重新安装 CRD** — ❌ 错误。CRD 在 etcd 中，不在 GKE 二进制文件中
2. **CRD 需要随 GKE 版本迁移** — ❌ 错误。CRD 是 K8s API 扩展，与 GKE 版本无绑定
3. **删除 GKE add-on 会删除 CRD** — ⚠️ 部分正确。删除 addon 后 CRD 从 API Server 注销，但 etcd 数据仍在；重新安装后 CR 实例恢复可访问

---

## 相关 CRD 列表（来源分类）

### Kubernetes Gateway API 原生
```
gatewayclasses.gateway.networking.k8s.io   (2025-10-29)
gateways.gateway.networking.k8s.io           (2025-10-29)
httproutes.gateway.networking.k8s.io         (2025-10-29)
grpcroutes.gateway.networking.k8s.io         (2026-05-29)
tcproutes.gateway.networking.k8s.io          (2026-05-29)
tlsroutes.gateway.networking.k8s.io          (2026-05-29)
udproutes.gateway.networking.k8s.io          (2026-05-29)
backendtlspolicies.gateway.networking.k8s.io (2026-05-29)
referencegrants.gateway.networking.k8s.io    (2025-10-29)
listenersets.gateway.networking.k8s.io      (2026-05-29)
```

### GKE Platform
```
gcpgatewaypolicies.networking.gke.io    (2025-10-29)
gcpedgeextensions.networking.gke.io      (2026-05-29)
gcphhttpfilters.networking.gke.io       (2026-05-29)
gcpinferencepoolimports.netike.io      (2026-05-29)
inferencepools.inference.networking.k8s.io (2026-05-29)
autoscalingmetrics.autoscaling.gke.io    (2026-05-29)
capacitybuffers.autoscaling.x-k8s.io      (2026-05-29)
```

### Istio（istiod 管理）
```
gateways.networking.istio.io              (2026-05-29)
virtualservices.networking.istio.io        (2026-05-29)
destinationrules.networking.istio.io       (2026-05-29)
authorizationpolicies.security.istio.io  (2026-05-29)
peerauthentications.security.istio.io    (2026-05-29)
requestauthentications.security.istio.io (2026-05-29)
telemetries.telemetry.istio.io            (2026-05-29)
serviceentries.networking.istio.io        (2026-05-29)
sidecars.networking.istio.io               (2026-05-29)
envoyfilters.networking.istio.io          (2026-05-29)
workloadentries.networking.istio.io       (2026-05-29)
workloadgroups.networking.istio.io       (2026-05-29)
proxyconfigs.networking.istio.io          (2026-05-29)
trafficextensions.extensions.istio.io    (2026-05-29)
wasmplugins.extensions.istio.io           (2026-05-29)
```

---

## 参考文档

- `gcp/gke/docs/gke-type.md` — CRD 清单原始记录
- `gcp/gke/docs/explorer-gke-type.md` — 探索文档完整版（含 ListenerSet 专项章节）