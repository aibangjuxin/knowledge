# DR 演练 Runbook：GKE(europe-west2) + PSC → Cloud SQL(europe-west1)

> 配套文档：[README.md](README.md)（方案评估与基础设施清单）
>
> 目标：验证 `europe-west2` 的 APP 能在 `europe-west1` 的 Cloud SQL 不可用时，把数据库流量切到 DR 副本，并恢复写入。

---

## 0. 角色与前提

| 角色 | 说明 |
|------|------|
| DR 负责人 | 决策 + 执行 DB 切换 |
| 运维 | 执行 APP 切流、监控指标 |
| 应用负责人 | 确认应用排空/重连行为正常 |

**执行前 checklist**（全部 ✅ 才能开始）：

- [ ] Endpoint B `pscConnectionStatus = ACCEPTED`
- [ ] `allowPscGlobalAccess = true`（Endpoint B）
- [ ] 从 `europe-west2` 的 Pod 内 `nc -zv <Endpoint B IP> 3306` 通
- [ ] DR 实例 `replication state = Running`
- [ ] `replication lag` ≤ 演练可接受阈值（建议 ≤ 5s）
- [ ] 应用已发布"切 Endpoint"能力（配置化 + 排空 + 重连）
- [ ] 回切路径已确认（`switchover` / 重新配复制 / 重跑本 runbook）
- [ ] 已通知业务方演练窗口
- [ ] 已记录当前基线指标（QPS、错误率、P99 延迟、DB 连接数）

---

## 1. T+0：基线快照

```bash
export PRODUCER_PROJECT_ID=your-db-project
export CONSUMER_PROJECT_ID=your-app-project
export REGION_A=europe-west2
export REGION_B=europe-west1
export SQL_A=sql-primary-euw2
export SQL_B=sql-dr-euw1
export EP_B_NAME=sql-psc-ep-b
```

```bash
# 主库与 DR 副本状态
gcloud sql instances describe ${SQL_A} --project=${PRODUCER_PROJECT_ID} \
  --format="table(name,region,state,instanceType,replicationType)"

gcloud sql instances describe ${SQL_B} --project=${PRODUCER_PROJECT_ID} \
  --format="table(name,region,state,instanceType,masterInstanceName,masterInstanceType)"

# 复制延迟（秒）
gcloud monitoring time-series list \
  --project=${PRODUCER_PROJECT_ID} \
  --filter='metric.type="cloudsql.googleapis.com/database/replication/replication_lag" AND resource.labels.database_id="${SQL_B}"' \
  --format="table(points[0].value)"
```

> 📌 记录 `replication lag` 峰值 = **本次演练可能丢失的数据窗口**。

---

## 2. T+5min：提升 DR 副本为可写主库

### 2.1 变体 A1（cross-region replica，推荐）

```bash
# 提升为独立可写实例
gcloud sql instances promote-replica ${SQL_B} \
  --project=${PRODUCER_PROJECT_ID}
```

等 `state = RUNNABLE`，然后确认它已可写：

```bash
# 从 europe-west2 的 Pod 内验证（写测试）
kubectl exec -it <app-pod> -n app -- \
  mysql -h <Endpoint B IP> -P 3306 -u <app_user> -p'<pwd>' \
  -e "CREATE TEMPORARY TABLE dr_probe(id INT PRIMARY KEY, ts TIMESTAMP); \
      INSERT INTO dr_probe VALUES (1, NOW()); SELECT * FROM dr_probe; DROP TABLE dr_probe;"
```

> ⚠️ `promote-replica` 之后，**原 Primary (SQL A) 不会自动变成 replica**。回切要用 §5 的方式处理。

### 2.2 变体 B（Enterprise Plus advanced DR）

如果 SQL B 是**指定 DR 副本**（designated DR replica）：

```bash
# 执行 replica failover（会强制终止主库上的连接）
gcloud sql instances failover ${SQL_A} \
  --project=${PRODUCER_PROJECT_ID}
```

或做**计划内演练用 switchover**（更安全，可回切）：

```bash
gcloud sql instances switchover ${SQL_B} \
  --project=${PRODUCER_PROJECT_ID}
```

> 💡 优先用 `switchover` 做演练：无数据丢失、可一键回切。`failover` 留给真实故障。

---

## 3. T+10min：APP 切流

### 3.1 摘流（停止接新请求）

```bash
# 方式 1：把 Pod 从 Service 的 endpoints 里摘掉（保留进程便于观察）
kubectl label pod <app-pod> -n app app-version=v2 --overwrite   # 改 selector 版本
# 或
kubectl scale deploy/<app-deploy> -n app --replicas=0
```

### 3.2 排空连接池

- 等待 in-flight 请求结束（建议 ≤ 30s）
- 应用侧触发连接池重建（重连到 Endpoint B）
- 若是 Auth Proxy sidecar：改 `--ip_address` 参数后滚动重启

### 3.3 切换 DB 目标

**方式 A：ConfigMap 热更新**

```bash
kubectl create configmap app-db-config -n app \
  --from-literal=DB_HOST=<Endpoint B IP> \
  --from-literal=DB_PORT=3306 \
  --dry-run=client -o yaml | kubectl apply -f -
# 应用 watch 到变更后重建连接池
```

**方式 B：滚动重启**

```bash
kubectl rollout restart deploy/<app-deploy> -n app
kubectl rollout status deploy/<app-deploy> -n app --timeout=300s
```

**方式 C：DNS 切换（方案 B write endpoint DNS 时无需此步）**

```bash
# 改私有 zone 的 A 记录指向 Endpoint B
gcloud dns record-sets update <db.prod.internal.> \
  --zone=<private-zone> --type=A --ttl=30 \
  --rrdatas=<Endpoint B IP>
```

> ⚠️ DNS 方式**不会**自动断开已有连接 → 必须配合 §3.2。

### 3.4 恢复流量

```bash
kubectl scale deploy/<app-deploy> -n app --replicas=<original>
# 确认 readiness 全部就绪
kubectl get pods -n app
```

---

## 4. T+15min：验证

```bash
# 1. 应用健康
kubectl get deploy <app-deploy> -n app
kubectl logs -n app deploy/<app-deploy> --tail=100 | grep -iE "error|read.only|refused"

# 2. 写入验证（关键：确认 DR 库可写）
kubectl exec -it <app-pod> -n app -- \
  mysql -h <Endpoint B IP> -P 3306 -u <app_user> -p'<pwd>' \
  -e "SELECT @@global.read_only; SELECT NOW();"

# 3. 确认流量确实打在 DR 库
gcloud sql instances describe ${SQL_B} --project=${PRODUCER_PROJECT_ID} \
  --format="value(state)"          # RUNNABLE
gcloud monitoring time-series list \
  --project=${PRODUCER_PROJECT_ID} \
  --filter='metric.type="cloudsql.googleapis.com/database/network/connections" AND resource.labels.database_id="${SQL_B}"' \
  --format="table(points[0].value)"

# 4. 端点连通性 & 状态
gcloud compute forwarding-rules describe ${EP_B_NAME} \
  --project=${CONSUMER_PROJECT_ID} --region=${REGION_B} \
  --format="get(pscConnectionStatus,allowPscGlobalAccess,IPAddress)"
```

**验收标准**：

| 指标 | 通过标准 |
|------|---------|
| 写操作 | 全部成功，无 `read-only` 错误 |
| 错误率 | 回到演练前基线（切换窗口内的瞬时错误 ≤ 1 分钟） |
| P99 延迟 | 相对基线上升在预期内（跨区 +10~20ms） |
| DB 连接数 | 稳定在连接池上限内 |
| 数据一致性 | 应用侧写入的数据能读回；对比演练开始前的 checksum（抽样） |

---

## 5. 回切

### 5.1 Enterprise Plus advanced DR（有 switchover 能力）

```bash
gcloud sql instances switchover ${SQL_A} \
  --project=${PRODUCER_PROJECT_ID}
# 然后把 APP 切回 Endpoint A
```

### 5.2 变体 A1（promote 过，原 Primary 已不是 replica）

```bash
# 1. 把原 Primary 重新配成新主的 replica
gcloud sql instances create ${SQL_A} --project=${PRODUCER_PROJECT_ID} \
  --region=${REGION_A} --master-instance-name=${SQL_B} --database-version=MYSQL_8_0 ...
# 或用 gcloud sql instances patch / 现有工具重建复制关系

# 2. 等待复制追平
# 3. promote-replica ${SQL_A}  （或继续保留为 replica，下次演练再切）
# 4. APP 切回 Endpoint A
```

> ⚠️ A1 变体回切成本较高 → **建议生产环境改用 Enterprise Plus advanced DR**（`switchover` 秒级回切、零数据丢失）。

---

## 6. 演练后收尾

- [ ] 确认 APP 已回到日常目标（Endpoint A / write endpoint DNS）
- [ ] 观察 30 分钟：错误率、P99、DB 连接数、复制 lag
- [ ] 检查 DR 副本是否需要重建（promote 后它已经是独立主库，不能直接"变回"副本）
- [ ] 记录本次演练的 RTO / RPO：
  - **RTO**：从故障判定到 APP 写恢复的时间
  - **RPO**：`replication lag` 峰值（数据丢失窗口）
- [ ] 更新本文档的实际耗时，补进演练记录表

---

## 7. 故障兜底分支

| 现象 | 可能原因 | 处理 |
|------|---------|------|
| Endpoint B 连不上 | `--allow-psc-global-access` 没开 / 防火墙没放行 / NetworkPolicy 没放行 | 逐项核对 §0 checklist |
| `pscConnectionStatus = PENDING` | DR 实例的 `allowedConsumerProjects` 没加 APP 项目 | `gcloud sql instances patch ${SQL_B} --allowed-psc-projects=${CONSUMER_PROJECT_ID}` |
| 连上了但报 access denied | MySQL 用户带主机限制 | 改成 `'user'@'%'` 并 `FLUSH PRIVILEGES` |
| 写操作报 read-only | DR 副本还没 promote / promote 没生效 | 检查 `state`；等 promote 完成 |
| 切换后延迟飙升 | 跨区流量 + 连接池频繁重建 | 检查是否在重建风暴；检查 P99 与 TCP 重传 |
| 部分请求还打到老库 | DNS TTL / 连接池未排空 | 强制排空 + 确认 TTL 已过 |

---

## 8. 演练记录表

| 演练日期 | 场景 | RTO | RPO(lag) | 切换方式 | 问题 | 改进项 |
|---------|------|-----|----------|---------|------|--------|
| | europe-west2 DB 不可用 | | | ConfigMap / DNS / switchover | | |
