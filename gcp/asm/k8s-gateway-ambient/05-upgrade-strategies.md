# Istio 升级策略 — 单 revision vs 双 revision canary,Helm vs istioctl

> **TL;DR**:
> - 单 revision 升版 = **istiod 滚动重启期间新路由配置短暂不生效**,已建连接不断(已观察)
> - **双 revision canary** = 新 revision 与老 revision 并存,namespace label 切流验证,**零中断**
> - Helm `helm upgrade -i` = 单 revision 原地滚;要双 revision 必须**手动起不同 release name + revision label**
> - `istioctl upgrade` = 单 revision 升级,简化命令但失去 Helm 拆分优势
> - **本场景推荐**:Helm 拆分 + 双 revision canary(02 文基础上扩展)

---

## 1. 问题的本质:为什么"升 istio 版本"会痛

istiod 是 **整个 mesh 配置的大脑**,所有 sidecar / ztunnel / waypoint 都从 istiod 拉配置。
**istiod 重启 = 配置分发的"心跳"短暂中断**:

| 影响 | 持续时间 | 严重度 |
|---|---|---|
| 已建立的 mTLS 连接 | 不断(K8s endpoint 不变) | 🟢 |
| 新建连接的路由配置 | 几秒到十几秒不更新 | 🟡 |
| 新建连接的 mTLS 证书轮换 | 短暂拿不到新证书 | 🟡 |
| 控制面推送失败重试 | 指数退避,可能分钟级 | 🟠 |

**单 revision 滚动升级**:
```text
旧 istiod (1.30.3)
   ↓ kubectl rollout restart / helm upgrade
新 istiod (1.31.0)
   ↓ 期间
   ├─ 新 pod 启动
   ├─ 老 pod 终止
   └─ 中间有几秒控制面 1 副本在跑(配置分发能力下降)
```

**双 revision canary**:
```text
旧 istiod-1-30 (revision="1-30")  ← 老 ns 还连它
   +
新 istiod-1-31-canary (revision="1-31-canary")  ← canary ns 连它
   ↓ 验证后
旧 istiod 卸载 + 全部 ns 切到 revision="1-31"
```

---

## 2. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **revision label** | "标识哪个 istiod" | "A revision is a label applied to istiod (and dependent charts) that namespaces opt into via the `istio.io/rev` label; multiple revisions may coexist in one cluster." — [Istio Install with revisions](https://istio.io/latest/docs/setup/install/multicluster/multi-primary/#customize-the-control-plane) |
| **defaultRevision** | "无 revision label 的 istiod" | "When a control plane is installed without a revision label, it is the default and serves namespaces without `istio.io/rev`." — Istio docs |
| **istio.io/rev** | "ns 选哪个 istiod" | "Namespaces labeled with `istio.io/rev=<revision>` are configured by the control plane with matching revision; unlabelled namespaces use the default." — Istio docs |
| **canary upgrade** | "新旧并存,逐步切" | "A canary upgrade installs a new revision alongside the current one, validates it with select namespaces, then retires the old revision." — [Istio Upgrade](https://istio.io/latest/docs/setup/install/upgrade/) |
| **in-place upgrade** | "直接升" | "An in-place upgrade replaces the existing control plane in a single operation; downtime is bounded by the rolling restart window." — Istio docs |

---

## 3. 5 种升级路径全表

| 路径 | 工具 | 是否拆分 release | 是否双 revision | 中断窗口 | 推荐度 |
|---|---|---|---|---|---|
| **A. istioctl 全原地升** | `istioctl upgrade` | ❌ | ❌ | 几秒到十几秒 | ⭐ 简单场景 |
| **B. Helm 单 release 原地升** | `helm upgrade -i istiod --reuse-values --set tag=1.31.0` | ❌ | ❌ | 几秒到十几秒 | ⭐⭐ |
| **C. Helm 双 release 不同 name 同 tag** | `helm install istiod-v1` + `helm install istiod-v2` | ✅ | ❌(同名 namespace label 冲突) | 几秒 | ⚠️ 不推荐 |
| **D. Helm 双 release 不同 revision label** | 同 C,但加 `--set revision=1-31` | ✅ | ✅ | **零** | ⭐⭐⭐ **本场景推荐** |
| **E. istioctl 双 revision** | `istioctl install --revision 1-31-canary` | ❌ | ✅ | **零** | ⭐⭐ 但失去 Helm 拆分 |

---

## 4. 路径 A:`istioctl upgrade`(最简,但失去拆分)

```bash
# 检查当前版本能升到哪里
istioctl upgrade --filename <你的 install manifest 或生成的 yaml>

# 直接升(等同 istioctl install,但带迁移检查)
istioctl upgrade \
  --set profile=ambient \
  --set hub=${HUB} \
  --set tag=1.31.0-distroless \
  --skip-confirmation
```

**优点**:一条命令完事
**缺点**:
- 失去 02 文的 Helm 拆分优势
- 单 revision 升,**无 canary 灰度**
- 升级期间配置分发能力下降

---

## 5. 路径 B:Helm 单 release 原地升(简单可控)

```bash
# 在 02 文基础上,改 tag 后原地升
helm upgrade istiod \
  oci://gcr.io/istio-release/charts/istiod \
  --namespace istio-system \
  --reuse-values \
  --set tag=1.31.0-distroless \
  --version 1.31.0
```

`--reuse-values` = 保留 02 文 values 文件的所有字段,只覆盖 `--set` 指定的。
**rolling strategy** 由 chart 内置(默认 25% maxUnavailable + maxSurge)。

**中断窗口**:单 revision 滚动重启,**几秒到十几秒**。

---

## 6. 路径 D:Helm 双 revision canary(**本场景推荐**)

> 这是 02 文拆分安装的**自然扩展**——同一 chart,装两份,revision label 区分。

### Step 1:安装新 revision(不替换老 revision)

```bash
# 老 istiod 仍在跑(revision = "",因为 defaultRevision="" 在 base.yaml)
# 现在装新 revision 并列存在

# 准备 values/istiod-1-31.yaml(从 02 文 values/istiod.yaml 复制)
# 关键差异:
cat values/istiod-1-31.yaml
```

```yaml
# values/istiod-1-31.yaml
global:
  hub: europe-west2-docker.pkg.dev/aibang-12345678-ajbx-dev/containers
  tag: 1.31.0-distroless       # ← 新版镜像
  platform: gke

# revision 命名 — 必须显式设
revision: "1-31"               # ← 关键:命名新 revision

pilot:
  cni:
    enabled: true
    namespace: istio-system
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi
  autoscaleMin: 2
  autoscaleMax: 3
  replicaCount: 2

meshConfig:
  accessLogFile: /dev/stdout
```

```bash
# 安装新 revision
helm upgrade --install istiod-1-31 \
  oci://gcr.io/istio-release/charts/istiod \
  --namespace istio-system \
  --version 1.31.0 \
  -f ~/git/gcp/gateway-2.0/k8s-gateway-ambient/values/istiod-1-31.yaml
```

### Step 2:验证双 revision 并存

```bash
kubectl get pods -n istio-system -l app=istiod
# 预期:
# istiod-xxxx               1/1     Running   0   ...    ← 老 revision=""
# istiod-1-31-yyyy          1/1     Running   0   ...    ← 新 revision="1-31"

kubectl get pods -n istio-system -l app=istiod \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.istio\.io/rev}{"\n"}{end}'
# 老 pod:空(无 rev label)
# 新 pod:1-31
```

### Step 3:Canary ns 切到新 revision

```bash
# 选一个 canary ns(已在 ambient 模式下)
kubectl label namespace team-canary \
  istio.io/rev=1-31 --overwrite

# ⚠️ 必须重启 pod 才能感知新 rev
kubectl rollout restart deployment -n team-canary

# 验证 canary ns 的 pod 连的是新 istiod
istioctl proxy-config endpoint <pod-name>.<rev>.team-canary
# 应显示新 revision 的 istiod endpoint
```

### Step 4:观察期(关键 — 1-2 周)

监控 canary ns 的:
- 业务错误率(应不上升)
- 配置推送延迟(应不显著上升)
- 内存/CPU(应不显著上升)
- 控制面日志(应无新警告)

### Step 5:全量切流

```bash
# 所有 ns 加 rev label
for ns in $(kubectl get ns -l istio.io/dataplane-mode=ambient -o name | cut -d/ -f2); do
  kubectl label "$ns" istio.io/rev=1-31 --overwrite
done

# 全部重启(逐 ns 滚动)
for ns in $(kubectl get ns -l istio.io/dataplane-mode=ambient -o name | cut -d/ -f2); do
  kubectl rollout restart deployment -n "$ns"
  sleep 60    # 给每 ns 一些观察时间,避免全量雪崩
done
```

### Step 6:退役老 revision

```bash
# 验证所有业务 pod 已连新 istiod
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.metadata.namespace != "istio-system") |
  {ns: .metadata.namespace, rev: (.metadata.labels["istio.io/rev"] // "<none>")} |
  "\(.ns)\t\(.rev)"' | sort | uniq -c | sort -rn
# 预期:所有业务 ns 都是 1-31

# 卸载老 istiod
helm uninstall istiod -n istio-system   # 这卸的是原 "" revision
```

### Step 7:清理 defaultRevision(可选)

如果以后不想再回默认 revision:

```bash
# base.yaml 改 defaultRevision
# values/base.yaml
defaultRevision: "1-31"      # 让"无 label 的 ns"也走新 revision

# 升级 base
helm upgrade istio-base oci://gcr.io/istio-release/charts/base \
  --namespace istio-system \
  -f values/base.yaml
```

---

## 7. 中断窗口对比

| 路径 | 控制面重启 | 业务连接 | 业务 pod 重启 |
|---|---|---|---|
| A. istioctl upgrade | 必须 | 不中断 | 不需要 |
| B. Helm 原地升 | 必须 | 不中断 | 不需要 |
| D. 双 revision canary | **零** | 不中断 | 只在切流 ns 重启 |

> 注意:不论哪种路径,**业务 pod 都不需要因 istiod 升级而重启**。只有切 revision label 时才需要重启 pod。

---

## 8. Helm 拆分带来的额外优势

02 文已经把 istio-base / istiod / cni / ztunnel 拆成 4 个独立 release,
升级时也可以**分别升**:

```bash
# 只升 ztunnel(比如 1.31 修了 ztunnel CVE,istiod 不动)
helm upgrade ztunnel oci://gcr.io/istio-release/charts/ztunnel \
  --namespace istio-system \
  --reuse-values \
  --set tag=1.31.0-distroless \
  --version 1.31.0
```

**业务影响 = 零**(ztunnel 滚动重启不影响业务 pod 长连接)。
**这是 Helm 拆分 vs istioctl install 的本质区别**。

---

## 9. 路径 E:`istioctl install --revision`(混合方案)

如果你 02 文选了 Helm,但升级时想用 istioctl:

```bash
# 安装新 revision 的 istiod
istioctl install --revision 1-31 \
  --set profile=ambient \
  --set hub=${HUB} \
  --set tag=1.31.0-distroless \
  --skip-confirmation
```

**优点**:不用单独维护 Helm values
**缺点**:
- istioctl 装的 istiod 与 Helm 装的 istio-base/istio-cni/ztunnel **管理工具不一致**
- 后续维护要判断"哪些 release 是 istioctl 装的,哪些是 Helm 装的"——**混乱来源**

**本场景不推荐**。一旦选 Helm,就贯彻 Helm。

---

## 10. 反向:什么时候**不**用双 revision

| 场景 | 推荐 |
|---|---|
| dev / test 集群 | 单 revision 原地升(路径 B),简单快速 |
| 中小生产(< 20 ns) | 单 revision 也可接受(中断 10s 内) |
| 大型生产 / 关键业务 | 双 revision canary(路径 D) |
| 多集群 mesh | **必须**双 revision(每个集群独立验证) |

---

## 11. 严格定义 vs 简化解释(关键限定)

| 限定 | 说明 |
|---|---|
| **同一 revision 不能有多个 istiod release** | "A revision name must be unique within the cluster; two istiod installations with the same `revision` label will conflict on Service selection." — Istio docs |
| **rev label 与 namespace label 必须匹配** | "A namespace with `istio.io/rev=X` is configured by istiod with `revision=X`; if no such istiod exists, the namespace is unmanaged." — Istio docs |
| **defaultRevision 切换不立即影响现 ns** | "Setting defaultRevision changes the default for new namespaces and unlabelled namespaces; namespaces with explicit `istio.io/rev` are unaffected." — Istio docs |
| **退役老 revision 前必须确认无 pod 引用** | "Before uninstalling an old revision, verify no pods have `istio.io/rev=<old>`; otherwise they become unmanaged." — Istio docs |

---

## 12. 本场景推荐:Helm 拆分 + 双 revision canary

```text
阶段 1 — ambient 跑通(02-04 文)
├─ Helm 拆 4 个 release
├─ 业务 ns 全部迁 ambient
└─ 不动 revision

阶段 2 — 升版验证(本篇 路径 D)
├─ 装新 revision "1-31-canary"
├─ canary ns 切到 1-31-canary,观察 1-2 周
├─ 全量切流
└─ 退役老 revision

阶段 3 — 持续运转
├─ 每季度升版都走阶段 2
└─ defaultRevision 保持最新,无 rev label 的 ns 也走新版本
```

---

## 13. References

- [Istio 升级官方指南](https://istio.io/latest/docs/setup/install/upgrade/) — canary upgrade 流程
- [Istio Helm 安装](https://istio.io/latest/docs/setup/install/helm/) — revision 字段说明
- [Istio ControlPlaneRevision](https://istio.io/latest/docs/setup/install/multicluster/multi-primary/#customize-the-control-plane) — 多控制面共存
- [Istio 多版本 mesh](https://istio.io/latest/docs/setup/install/multicluster/multi-primary/) — 多集群 + revision
- [Solo blog: Canary Upgrade](https://www.solo.io/blog/canary-upgrades-for-istio-control-planes/) — Solo 视角(canary 流程细节)
- 同仓库 `~/git/knowledge/gcp/asm/gloo/gke-ambient-waypoint-single.md` §5 — 已有 Gloo 视角的安装(本篇扩展为升级流程)