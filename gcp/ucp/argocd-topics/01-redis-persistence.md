# 01 · Redis 与持久化

> 本文档回答一个被反复问的问题：**Argo CD 的 Redis 要不要挂盘？**
> 答案不是简单的"要"或"不要"，而是**先分清楚你说的 Redis 是哪一个**。

---

## 1. 先分清三类 Redis

这是本文档最重要的一节。三者名字都叫 Redis，但性质完全不同。

| # | Redis | 归属 | 当前状态 | 需要持久化吗 |
|---|---|---|---|---|
| **A** | Argo CD 内部 Redis | `ucp/install.yaml` 的 `argocd-redis` | 单实例 Deployment，**无任何 volume**，显式关闭 RDB+AOF | **不需要**（见 §4） |
| **B** | Argo CD HA 的 Redis | 官方 `manifests/ha/base/redis-ha` | 3 master + 3 sentinel + HAProxy | **不需要**（官方默认也不开，见 §5） |
| **C** | 业务 Redis | 你自己的 YAML 部署在 GKE 上的实例 | 由你决定 | **要**（除非它明确是纯缓存，见 §6） |

> 本文后续提到的 "Argo CD 的 Redis" 一律指 A 或 B。
> 你说的"现在仅仅是通过 Yaml 的资源部署在 GKE 里边 没有持久化"指的是 **C**。

---

## 2. 清单事实：`argocd-redis` 不是 `emptyDir`

**这一点需要纠正一个常见误解。**

原始印象："默认应该是 emptyDir"。实际核对本仓库 `install.yaml` 的结果：

```yaml
# install.yaml:32441 起，argocd-redis Deployment
kind: Deployment
metadata:
  name: argocd-redis
spec:
  template:
    spec:
      containers:
      - args:
        - --save
        - ""
        - --appendonly
        - "no"
        - --requirepass $(REDIS_PASSWORD)
        image: public.ecr.aws/docker/library/redis:8.2.3-alpine
        name: redis
        ports:
        - containerPort: 6379
        securityContext:
          readOnlyRootFilesystem: true
      initContainers:
      - command:
        - argocd
        - admin
        - redis-initial-password
        name: secret-init
```

**关键事实（三条，缺一不可）：**

1. **没有 `volumes` 段**。整个 Deployment 里找不到任何 `volumes` / `volumeMounts`。
   → 它比 `emptyDir` 更"干净"：连临时目录都没给。
2. **`readOnlyRootFilesystem: true`**。容器根文件系统只读，Redis 想落盘也没地方落。
3. **启动参数显式关闭持久化**：
   - `--save ""` → 关闭 RDB 快照
   - `--appendonly no` → 关闭 AOF 追加日志

> 加上这两条参数，Redis 即使能写磁盘也不会写。
> **结论：当前 `argocd-redis` 是完全无持久化的有状态缓存。Pod 重建 → 数据全丢。**

### 2.1 那 `emptyDir` 在哪？

`install.yaml` 里确实有 `emptyDir`，但它们属于**其他组件**：

| 行号 | 所属 workload | emptyDir 用途 |
|---|---|---|
| 32141, 32143 | `argocd-applicationset-controller` (Deployment) | 临时工作目录 |
| 32287, 32289 | `argocd-dex-server` (Deployment) | 临时工作目录 |
| 32900, 32902, 32904, 32924, 32926 | `argocd-repo-server` (Deployment) | gpg-keyring / tmp / helm-working-dir 等 |
| 33386, 33388 | `argocd-server` (Deployment) | tmp |
| 33842, 33844 | `argocd-application-controller` (StatefulSet) | tmp |

共 13 处。复核命令：

```bash
grep -n 'emptyDir' install.yaml
```

**这些是"临时工作区"，不是"数据存储"。** 它们的语义是"进程重启可以丢"，
和 Redis 的持久化完全是两回事。

---

## 3. Argo CD 的 Redis 里到底存了什么

理解这个才能判断"丢了要紧吗"。

| 内容 | 是否在 Redis | 丢了会怎样 |
|---|---|---|
| Argo CD 集群 Secret（目标集群凭据） | ❌ 不在 | — |
| Repository Secret（仓库凭据） | ❌ 不在 | — |
| Application / AppProject / ApplicationSet 定义 | ❌ 不在（存 K8s CRD） | — |
| **Argo CD 内部组件间通信的会话状态** | ✅ 在 | 需重新登录 |
| **应用健康状态缓存 / 资源树缓存** | ✅ 在 | 重新计算，稍慢 |
| **集群缓存（资源版本、发现结果）** | ✅ 在 | 重新拉取，稍慢 |
| **操作状态 / 同步历史（部分）** | ✅ 在 | 历史丢失 |
| **RBAC 缓存** | ✅ 在 | 重新加载策略 |

**结论：Redis 里全是"可重建的缓存和会话"，没有一个是 source of truth。**
源数据在 **Git + Kubernetes CRD + Kubernetes Secret** 三处。

---

## 4. Argo CD 内部 Redis：为什么**不该**加 PVC

### 4.1 官方立场

Argo CD 官方对 Redis 的定位是 **cache / state store**，官方文档在讨论 HA 时
明确说 Redis 里的数据可以在 Pod 重建后从其他来源重新获取。

### 4.2 加 PVC 的三个实际危害

| 危害 | 说明 |
|---|---|
| **滚动更新卡死** | Deployment 滚动更新时，新 Pod 要挂同一个 PVC。若 StorageClass 是 `ReadWriteOnce`（GKE `standard-rwo` 即如此），新 Pod 调度到别的节点就挂不上 → `Multi-Attach` 错误 → 更新卡住 |
| **制造伪需求** | 一旦 Redis 有盘，运维就会开始"备份 Redis"。但备份出来的东西，重新拉一遍 Git 就能得到，还可能是不一致的状态快照 |
| **与官方 HA 混用** | 官方 HA 拓扑是 3 master + 3 sentinel（Sentinel 模式本身就要求数据可丢失、可复制）。给单实例挂盘和这套拓扑是两套完全不同的架构，不能混 |

### 4.3 官方 HA chart 也不开持久化

上游 `manifests/ha/base/redis-ha/chart/values.yaml` 的实际内容：

```yaml
auth: true
existingSecret: argocd-redis
persistentVolume:
  enabled: false          # ← 默认不开
redis:
  config:
    save: '""'            # ← 同样关闭 RDB
  image:
    tag: 8.10.3-alpine
sentinel:
  image:
    tag: 8.10.3-alpine
haproxy:
  enabled: true
  image:
    tag: 3.0.8-alpine
```

**官方 HA 实现同样默认不持久化。** 这说明"Redis 持久化"在 Argo CD 语境下
从来不是需求。

> 如果你确实需要 Redis HA 拓扑下不丢缓存（例如减少大规模重建时的 API Server 压力），
> 可以开 `persistentVolume.enabled: true`，但要清楚：
> - 这是**性能优化**，不是**数据可靠性需求**
> - Sentinel 拓扑 + PVC 的组合需要仔细规划（每个 master 一个独立 PVC）
> - 官方不推荐，也不提供默认配置

---

## 5. Argo CD HA 的 Redis 方案

### 5.1 官方拓扑

```
                    ┌──────────────┐
                    │   HAProxy    │  ← 唯一稳定入口 (Service: argocd-redis)
                    │  :6379 / :6380│
                    └──────┬───────┘
            ┌──────────────┼──────────────┐
            │              │              │
      ┌─────▼─────┐  ┌─────▼─────┐  ┌─────▼─────┐
      │  redis    │  │  redis    │  │  redis    │   3 × master
      │  node-0   │  │  node-1   │  │  node-2   │
      └─────┬─────┘  └─────┬─────┘  └─────┬─────┘
            │              │              │
      ┌─────▼─────┐  ┌─────▼─────┐  ┌─────▼─────┐
      │ sentinel  │  │ sentinel  │  │ sentinel  │   3 × sentinel
      └───────────┘  └───────────┘  └───────────┘
```

（以上为官方 chart 展开后的逻辑拓扑，实际由 `spotahome/redis-ha` chart 渲染。）

### 5.2 三条硬约束

**约束 1：只能三个。**
上游 HA 文档原文：

> `argocd-redis` is pre-configured with the understanding of only three total redis servers/sentinels.

sentinel 数量写死在 3，**不能随意扩缩到 5 个**。需要更多容量只能加内存或改
`sentinel` 配置并自己验证。

**约束 2：dex-server 用内存库，多副本数据可能不一致。**
上游 HA 文档明确警告 `argocd-dex-server` 使用内存数据库，
两个以上实例可能有数据不一致。**默认保持 1 副本。**

**约束 3：`argocd-server` 副本数与 `ARGOCD_API_SERVER_REPLICAS` 必须同步。**
见 [`02-ha.md`](./02-ha.md) §3。

### 5.3 部署 HA 的命令

```bash
# 上游 HA 清单（含 redis-ha、server、repo-server、controller 多副本）
kubectl create namespace argocd
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/ha/install.yaml

# 或用官方 helm chart
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set global.domain=argocd.example.com \
  --set controller.replicas=3 \
  --set server.replicas=3 \
  --set repoServer.replicas=3
```

---

## 6. 业务 Redis（你 YAML 部署的那个）：持久化方案

**这一节与你最初的问题直接对应。**

当前状态：业务 Redis 通过 YAML 部署在 GKE 上，没有持久化。

### 6.1 先回答"要不要持久化"

| Redis 里存的东西 | 结论 |
|---|---|
| 会话 / 队列 / 任务状态 | **必须持久化**。丢了 = 丢业务数据 |
| 缓存 / 限流计数 / 计算结果 | **可以不持久化**，但要写清楚丢失语义 |
| 分布式锁 | **必须持久化**（用 AOF `appendfsync everysec`） |

> **判定方法**：问自己"Redis 全量丢失后，系统是降级运行还是丢数据？"
> 降级 → 可不持久化；丢数据 → 必须持久化。

### 6.2 方案 A：StatefulSet + PVC（推荐，GKE 原生）

**为什么必须从 Deployment 改成 StatefulSet：**

GKE 的 `standard-rwo`（= `pd-balanced`）是 **ReadWriteOnce**：
一个 PVC 在同一时刻只能被一个节点上的一个 Pod 挂载。
Deployment 的 Pod 是无序、随机名、可以多副本同时存在 → 必然冲突。
StatefulSet 提供**稳定身份 + 每 Pod 独立 PVC**（`volumeClaimTemplates`），
这才是 RWO 存储的正确用法。

完整示例见 [`examples/redis-statefulset-pvc.yaml`](./examples/redis-statefulset-pvc.yaml)。

核心要点：

```yaml
kind: StatefulSet
spec:
  serviceName: redis
  replicas: 3
  selector:
    matchLabels: { app: redis }
  template:
    spec:
      containers:
      - name: redis
        image: public.ecr.aws/docker/library/redis:8.2.3-alpine
        args:
        - --appendonly
        - "yes"                      # ① 开 AOF
        - --appendfsync
        - everysec                   # ② 每次 fsync，最多丢 1 秒
        - --requirepass $(REDIS_PASSWORD)
        ports: [{ containerPort: 6379 }]
        readinessProbe:               # ③ 就绪探针必须指向真实 ping
          exec:
            command: ["redis-cli", "-a", "$(REDIS_PASSWORD)", "ping"]
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          exec:
            command: ["redis-cli", "-a", "$(REDIS_PASSWORD)", "ping"]
          initialDelaySeconds: 30
          periodSeconds: 15
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:                # ④ 每副本独立 PVC
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      storageClassName: standard-rwo   # ⑤ 必须实查你的集群
      resources:
        requests:
          storage: 20Gi
```

**关于 Redis 集群模式**：上面是单机 Redis 跑 3 副本（主从/哨兵需自行配置）。
如果需要真正的分片集群，用 **Memorystore for Redis Cluster**（见 6.4），
或者用 Helm 的 `bitnami/redis` chart（自带 sentinel / cluster topology）。

### 6.3 方案 A 的迁移步骤（不停服）

```bash
# 1) 记录当前状态
kubectl get deploy redis -o yaml > /tmp/redis-deploy-backup.yaml
kubectl get svc redis -o yaml > /tmp/redis-svc-backup.yaml

# 2) 先以 replicas=1 建 StatefulSet（避免多副本抢 RWO）
kubectl apply -f examples/redis-statefulset-pvc.yaml
kubectl -n <ns> rollout status statefulset/redis --timeout=5m

# 3) 验证：确认 PVC 已绑定、数据可写
kubectl -n <ns> get pvc
kubectl -n <ns> exec redis-0 -- redis-cli -a "$REDIS_PASSWORD" set k v
kubectl -n <ns> exec redis-0 -- redis-cli -a "$REDIS_PASSWORD" get k

# 4) 删掉旧 Deployment（Service 名保持一致）
kubectl -n <ns> delete deploy redis

# 5) 扩容
kubectl -n <ns> scale statefulset/redis --replicas=3
```

**回滚**：第 4 步之前都可回滚。执行
`kubectl -n <ns> delete statefulset/redis` 后重新
`kubectl apply -f /tmp/redis-deploy-backup.yaml`。
注意 StatefulSet 删除默认保留 PVC（`persistentVolumeClaimRetentionPolicy`），
需手动清理。

### 6.4 方案 B：Memorystore for Redis Cluster（GKE 托管）

如果不想自己运维 Redis，GKE 上的官方托管选项：

| 项 | 说明 |
|---|---|
| 产品 | Memorystore for Redis Cluster |
| 持久化 | **AOF 或 RDB，二选一，不能同时开**（官方限制） |
| 网络 | **Private Service Connect / Service Connect**（Cluster 版） |
| 接入 GKE | 见官方 `configure-gke-cluster` 文档 |
| 何时选它 | 需要托管运维、自动 failover、分片扩容、多可用区 |

对比：

| 维度 | StatefulSet + PVC | Memorystore Cluster |
|---|---|---|
| 运维成本 | 高（自己管 failover、升级、备份） | 低（Google 管） |
| 成本 | 磁盘 + 节点成本 | 按节点/容量计费 |
| 网络可达 | VPC 内直连，暴露为 Service | PSC / Service Connect |
| 持久化粒度 | 自己控制（AOF/RDB） | AOF 或 RDB（二选一） |
| 适合 | 中小规模、有特殊配置需求 | 生产级、多集群、高可用 |

**Memorystore for Redis（单机版）** 的网络是 **VPC peering**，
与 Cluster 版的 PSC/Service Connect 不同，别混淆。

官方文档入口：

- Memorystore for Redis Cluster 总览
  `https://cloud.google.com/memorystore/docs/cluster/memorystore-for-redis-cluster-overview`
- 网络 `https://cloud.google.com/memorystore/docs/cluster/networking`
- 持久化 `https://cloud.google.com/memorystore/docs/cluster/persistence-overview`
- HA 与副本 `https://cloud.google.com/memorystore/docs/cluster/ha-and-replicas`
- 接入 GKE `https://cloud.google.com/memorystore/docs/cluster/configure-gke-cluster`

> ⚠️ 本轮因文档站访问受限，上述页面通过代理文本缓存核对，
> 关键结论（AOF/RDB 二选一、Cluster 走 PSC/Service Connect）已确认。
> 实施前请直接打开上述 URL 复核最新表述。

---

## 7. 决策速查

| 场景 | 决定 | 理由 |
|---|---|---|
| Argo CD 内部 Redis 要不要 PVC？ | **不要** | 官方立场；加了有滚动更新卡死风险；制造伪备份需求 |
| Argo CD HA 的 Redis 要不要 PVC？ | **不要**（官方默认 `false`） | Sentinel 拓扑本就允许数据重建 |
| 业务 Redis 存业务数据？ | **要** → StatefulSet + PVC | RWO 存储的正确用法 |
| 业务 Redis 纯缓存？ | 可不持久化，但要**记录丢失语义** | 至少写清"重建后回源逻辑" |
| 业务 Redis 要托管？ | Memorystore for Redis Cluster | AOF 或 RDB 二选一 |
| 给 `argocd-redis` 挂 PVC？ | **绝对不要** | 与官方 HA 拓扑冲突，且滚动更新会卡死 |

---

## 8. 验证命令

```bash
# ① 确认 Argo CD 的 Redis 确实无 volume（清单层面）
kubectl -n argocd get deploy argocd-redis -o jsonpath='{.spec.template.spec.volumes}' ; echo
kubectl -n argocd get deploy argocd-redis -o jsonpath='{.spec.template.spec.containers[0].args}'; echo

# ② 确认 Redis 运行时也没落盘
kubectl -n argocd exec deploy/argocd-redis -- sh -c 'ls -la /data 2>&1; redis-cli -a "$REDIS_PASSWORD" INFO persistence | grep -E "rdb_|aof_"'

# ③ 业务 Redis（StatefulSet 方案）验证
kubectl -n <ns> get pvc                    # 应为 Bound
kubectl -n <ns> get statefulset redis
kubectl -n <ns> exec redis-0 -- redis-cli -a "$REDIS_PASSWORD" INFO persistence | grep -E "aof_enabled|rdb_last_save_time"

# ④ 重启后数据是否还在
kubectl -n <ns> delete pod redis-0
kubectl -n <ns> wait --for=condition=ready pod/redis-0 --timeout=180s
kubectl -n <ns> exec redis-0 -- redis-cli -a "$REDIS_PASSWORD" GET <你的key>
```

---

## 9. 排障

| 现象 | 根因 | 处理 |
|---|---|---|
| `argocd-redis` Pod 重启后所有用户掉线 | Redis 无持久化（设计如此） | 预期行为，让用户重新登录 |
| `argocd-repo-server` 报 `Multi-Attach error for volume` | 给 Redis 挂了 RWO PVC + 滚动更新 | 摘掉 PVC，改用官方 HA 拓扑 |
| 业务 Redis Pod 一直 `Pending` | PVC 未绑定 / StorageClass 不存在 | `kubectl get sc`；用 `WaitForFirstConsumer` 模式 + 确认节点池区域 |
| StatefulSet 第 2 个 Pod `Pending`，第 1 个正常 | RWO 只能单挂载，且 `volumeClaimTemplates` 未生效 | 确认 `volumeClaimTemplates` 在 `spec` 下（不是 `template` 下） |
| `appendfsync` 导致写入变慢 | 每次 fsync 落盘 | 改 `everysec`（默认推荐），或 `no`（最多丢 30s） |
| 数据写进去但 `GET` 读不到 | 连的不是同一个 Pod / Service 未指向 StatefulSet | 确认 `serviceName` 与 StatefulSet `serviceName` 一致 |
