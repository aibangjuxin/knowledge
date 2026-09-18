# 业务命名空间从 Sidecar 迁移到 Ambient — 步骤与回滚

> **TL;DR**:
> - 迁移本质:**去掉 namespace 上的 `istio-injection=enabled` label,改成 `istio.io/dataplane-mode=ambient`**
> - **业务 pod 必须重启才能去 sidecar** — 这是硬性限制
> - 迁移分阶段:**先 canary ns(非关键业务)→ 验证 1-2 周 → 再迁生产 ns**
> - 回滚 = 改回 label + 重启 pod,数据无丢失
>
> **🚨 重要硬约束**:Istio 1.30 L7 策略 zero-downtime 迁移**不支持**,需维护窗口。详见 `11-l7-zero-downtime-constraint.md`。

---

## 1. 迁移前清单(必读)

> [Istio Ambient](https://istio.io/latest/docs/ambient/) 与 [PeerAuthentication 差异](https://istio.io/latest/docs/ambient/security/) 的硬性要求:

- [ ] ambient 控制面已装(本目录 02 文 ✅)
- [ ] ztunnel DaemonSet 在所有节点 Running
- [ ] istio-cni DaemonSet 在所有节点 Running
- [ ] GatewayClass `istio-waypoint` 已注册
- [ ] **业务 ns 中没有用 `portLevelMtls DISABLE`**(ambient 不支持,详见 §3.2)
- [ ] **业务 ns 的 AuthorizationPolicy 已有 `targetRefs` 版本**或确认不需要(详见 §3.3)
- [ ] 业务 pod 的 readiness probe 没硬编码 `localhost:15020`(ambient 下该端口不再由 sidecar 提供)

---

## 2. 简化 vs 严格定义

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **istio.io/dataplane-mode=ambient** | "加入 ambient" | "Namespaces labeled with `istio.io/dataplane-mode=ambient` opt their workloads into ambient mesh; istio-cni redirects pod traffic to ztunnel instead of injecting sidecars." — [Istio Ambient](https://istio.io/latest/docs/ambient/) |
| **istio-injection=enabled vs ambient** | 互斥 | "A namespace must have exactly one of `istio-injection=enabled` or `istio.io/dataplane-mode=ambient`; setting both is undefined behavior." — Istio 文档隐含语义 |
| **必须重启 pod** | 没法 in-place 切 | "Changing the dataplane mode of a namespace does not affect existing pods; they must be recreated to pick up the new mode." — Istio Ambient docs |
| **业务 Pod 镜像** | 不需要改 | "Ambient mode requires no changes to application container images; only pod scheduling and network interception change." — Istio Ambient docs |

---

## 3. 迁移前的兼容性检查(关键)

### 3.1 业务 pod readiness probe

sidecar 模式下,业务 pod readiness 通常要 probe `15020`(envoy admin port)。
ambient 下该端口**不再由 pod 提供**(由 ztunnel 在节点级暴露)。

```yaml
# ❌ sidecar 模式:probe 走 envoy admin port
readinessProbe:
  httpGet:
    path: /healthz/ready
    port: 15020

# ✅ ambient 模式:probe 直接打业务容器
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
```

### 3.2 `portLevelMtls DISABLE` — ambient 不支持

```yaml
# ❌ 在 ambient ns 下,这个策略不会被执行,但也不会报错(坑!)
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: metrics-plaintext
  namespace: team-a-runtime
spec:
  selector:
    matchLabels:
      app: api-a
  mtls:
    mode: STRICT
  portLevelMtls:
    9090: {mode: DISABLE}   # ← ambient 下无效
```

**解决办法**:
- metrics 端口走**节点级 Prometheus**(DaemonSet)+ NetworkPolicy 锁源 IP
- 或用 **Prometheus 的 serviceMonitor + 节点端口**,不走 mesh

### 3.3 AuthorizationPolicy 的 `selector` 写法

sidecar 模式下用 `selector.matchLabels`,ambient 下推荐改 `targetRefs` 绑 waypoint。
但**不强制** — selector 仍能工作,只是粒度在 pod label 而非 Service / Gateway。

```yaml
# ✅ sidecar 写法(迁移后仍可用,但粒度受限)
spec:
  selector:
    matchLabels:
      app: api-a

# ✅✅ 推荐写法(ambient 友好)
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-a
    # 或绑 waypoint:
    # - kind: Gateway
    #   group: gateway.networking.k8s.io
    #   name: waypoint
```

---

## 4. 迁移步骤(按 ns 粒度)

### Step 1:Canary ns 选择

**原则**:
- 选 **非关键业务 ns**(流量小、影响范围窄、运维熟悉)
- 选 **没用 portLevelMtls DISABLE 的 ns**(§3.2)
- 选 **AuthorizationPolicy 数量少的 ns**(验证完再迁复杂的)

### Step 2:部署 waypoint(本目录 03 文已详)

```bash
kubectl apply -f waypoint-team-canary.yaml
# 或
istioctl waypoint apply -n team-canary --enroll-namespace
```

### Step 3:改 namespace label

```bash
# 1. 改 dataplane-mode
kubectl label namespace team-canary \
  istio.io/dataplane-mode=ambient --overwrite

# 2. enroll 到 waypoint(istioctl waypoint apply 已自动做,手动方式需做)
kubectl label namespace team-canary \
  istio.io/use-waypoint=waypoint --overwrite

# 3. 移除 sidecar 注入(如果之前有)
kubectl label namespace team-canary \
  istio-injection- --overwrite   # 注意是 "istio-injection-"
```

### Step 4:滚动重启业务 pod

```bash
# 方法 1:rollout restart
kubectl rollout restart deployment -n team-canary

# 方法 2:删除 pod 强制重建(K8s Deployment 会自动起新 pod)
kubectl delete pods -n team-canary -l app=<label>

# 方法 3:Scale down → scale up(最稳,适合关键业务)
kubectl scale deployment -n team-canary <deploy-name> --replicas=0
sleep 30
kubectl scale deployment -n team-canary <deploy-name> --replicas=<original>
```

**为何必须重启**:
- sidecar 是在 pod 启动时注入容器,运行时无法移除容器
- dataplane-mode label 只影响**新启动的 pod**
- 已存在 pod 的 iptables 规则指向 15001(envoy inbound),不指向 ztunnel

### Step 5:验证(关键 — 不验证就出事)

```bash
# 1. 业务 pod 没有 sidecar 了
kubectl get pod -n team-canary <pod-name> \
  -o jsonpath='{.spec.containers[*].name}'
# 预期:只有业务容器名(如 "nginx"),没有 "istio-proxy"

# 2. 业务流量通
kubectl exec -n team-canary <pod-a> -- curl -s http://<pod-b>:8080/healthz
# 预期:HTTP 200

# 3. 流量经过 ztunnel
kubectl logs -n istio-system -l app=ztunnel --tail=20
# 应看到 access log,包含 pod-a → pod-b 的连接

# 4. 流量经过 waypoint(如该 ns enroll 了 waypoint)
kubectl logs -n team-canary -l app.kubernetes.io/name=waypoint --tail=20
# 应看到 L7 处理的访问记录

# 5. 证书正常签发
istioctl proxy-config secret <ztunnel-pod-name> -n istio-system
# 预期:看到 SPIFFE 证书

# 6. mTLS 生效(抓包验证)
kubectl exec -n team-canary <pod-a> -- \
  tcpdump -i any -nn port 8080 2>&1 | head -20
# 看到的应该是加密流量,而不是明文 HTTP
```

### Step 6:观察期(1-2 周)

监控指标:
- 业务 pod **内存使用**应**下降**(去掉 envoy 的 ~80Mi)
- **首次连接延迟**应**下降**(去掉 envoy 启动等待)
- **错误率**应**持平或更低**
- ztunnel pod **CPU 使用**应**小幅上升**(承担 L4 转发)

---

## 5. 回滚预案(必备)

> [Istio Ambient docs](https://istio.io/latest/docs/ambient/) 明示:回滚是改 label + 重启,无状态丢失。

### 5.1 快速回滚(5 分钟内)

```bash
# 1. 改回 sidecar 模式
kubectl label namespace team-canary \
  istio.io/dataplane-mode- --overwrite   # 移除 ambient label
kubectl label namespace team-canary \
  istio-injection=enabled --overwrite    # 重新启用 sidecar
kubectl label namespace team-canary \
  istio.io/use-waypoint- --overwrite     # 移除 waypoint enroll

# 2. 滚动重启(让 pod 重新注入 sidecar)
kubectl rollout restart deployment -n team-canary

# 3. 验证
kubectl get pod -n team-canary <pod-name> \
  -o jsonpath='{.spec.containers[*].name}'
# 预期:业务容器 + "istio-proxy"
```

### 5.2 何时必须回滚

| 现象 | 严重度 | 动作 |
|---|---|---|
| 业务 pod 启动失败(端口冲突) | 🟠 中 | 检查 readiness probe,可能硬编码 15020 |
| 流量断(同 ns 内 service-to-service 5xx) | 🔴 高 | 立即回滚,查 ztunnel 日志 |
| mTLS 验证失败(连接 reset) | 🔴 高 | 检查 PeerAuthentication 是否仍用 DISABLE |
| 监控空白(无遥测) | 🟡 低 | 检查 Prometheus 抓取配置 |

### 5.3 完全回滚(卸 ambient 控制面)

如果你想**完全退出 ambient,回到原 minimal**:

```bash
# 1. 业务 ns 全部迁回 sidecar
for ns in $(kubectl get ns -l istio.io/dataplane-mode=ambient -o name); do
  kubectl label "$ns" istio.io/dataplane-mode- istio-injection=enabled
  kubectl rollout restart deployment -n "${ns#namespace/}"
done

# 2. 卸载 ambient 组件(Helm 拆分的好处)
helm uninstall ztunnel -n istio-system
helm uninstall istio-cni -n istio-system
helm uninstall istiod -n istio-system   # 注意:这也会把 minimal 卸了,需重装
helm uninstall istio-base -n istio-system

# 3. 回到原 minimal 脚本
bash ~/git/gcp/gateway-2.0/k8s-gateway/01-platform/install-istio.sh
```

---

## 6. 迁移节奏建议(本场景 dev 集群)

```text
Week 1
└─ 装 ambient 控制面(02 文)
└─ 选 canary ns:建议 team-xxx-canary 或新建 test ns
└─ 部署 waypoint
└─ 切 1 个 ns + 1 个 Deployment

Week 2
└─ 观察期:看指标、看日志
└─ 如果稳定:切第 2 个 ns(同 team)
└─ 修 readiness probe 问题

Week 3
└─ 切完 1 个 team 的所有 ns
└─ 总结经验 + 文档化

Week 4
└─ 切第二个 team(对验证过的流程做微调)
└─ 准备 05 文(升级策略)
```

**不要一次性全切所有 ns** — 即使 ambient 官方说"无损",**现实生产总有边界 case**。

---

## 7. 严格定义 vs 简化解释(关键限定)

| 边界 | 说明 |
|---|---|
| **dataplane-mode label 必须重启 pod 才生效** | "The `istio.io/dataplane-mode` label is checked at pod creation; existing pods are not retroactively changed." — Istio docs |
| **waypoint enroll 也是创建时生效** | "The `istio.io/use-waypoint` label determines waypoint enrollment for pods created in the namespace; existing pods must be recreated." — Istio docs |
| **ambient 和 sidecar 不能同 ns 混用** | "Setting both `istio-injection=enabled` and `istio.io/dataplane-mode=ambient` on the same namespace is undefined behavior." — Istio docs |
| **跨 ns 流量必须双方都 ambient** | "If namespace A is ambient and namespace B is not, traffic from A to B is plain TCP unless namespace B is opted into mesh via injection." — Istio Ambient docs |

---

## 8. References

- [Istio Ambient 总览](https://istio.io/latest/docs/ambient/) — namespace 标签权威说明
- [Istio Ambient Security](https://istio.io/latest/docs/ambient/security/) — PeerAuthentication 在 ambient 的限制(DISABLE 不支持)
- [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/) — waypoint enroll 语义
- [Istio PeerAuthentication 能力矩阵](https://istio.io/latest/docs/reference/config/security/peer_authentication/) — `portLevelMtls` 字段限制
- [Istio AuthorizationPolicy targetRefs](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — targetRefs vs selector(API ≥ 1.22)
- 同仓库 `~/git/knowledge/gcp/asm/gloo/waypoint.md` §7 — waypoint 回滚细节
- 同仓库 `~/git/knowledge/gcp/asm/gloo/gke-ambient-waypoint.md` §6.2-6.3 — 验证 + 回滚策略