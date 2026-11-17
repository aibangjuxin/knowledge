# GKE 上的 Job Runner（任务执行）概念入门

> 面向对象：刚接触 GKE / Kubernetes 的同学
> 目标：搞清楚 "jobRunner" 到底指什么、在 GKE 上长什么样、该用哪个

---

## 1. 一句话定义

**Job Runner = 在集群里跑"有始有终"的一次性任务**。

和 Deployment（长期运行的常驻服务）最大的区别是：Job 跑完就结束，不需要一直占着 Pod。

典型例子：跑一次数据迁移、执行一次备份、生成一份报表、跑一次安全扫描、跑一个批处理 ETL。

---

## 2. 先澄清："jobRunner" 其实是个歧义词

在 GCP 语境下，你听到的 "job runner" 通常是下面三种之一。先分清楚，后面就不会走弯路。

| # | 含义 | 属于哪一层 | 触发方式 | 典型场景 |
|---|------|-----------|---------|---------|
| A | **Kubernetes Job / CronJob**（原生批处理） | K8s 内置资源 | 手动 `kubectl create` 或被别的控制器创建 | 迁移、备份、报表、批量 ETL |
| B | **Cloud Deploy 的 post-deployment verification Job** | GCP 交付流水线 | 每次发布 / 回滚自动执行 | "发布后跑个冒烟测试，失败就判定发布失败" |
| C | **GitOps 模式下由 Git 声明的 Job** | GitOps 控制面 | Git 提交后由 Argo CD / Config Sync 同步 | 声明式地"订阅"一个定时任务 |

> **GKE 平台视角的提醒**
>
> 在一个受管控的生产 GKE 集群里，直接让用户随手 `kubectl create job` 通常是不被鼓励的：
>
> - 没有审计记录（谁在什么集群跑了什么任务）
> - 没有统一的资源配额与并发控制（一个大 Job 能把节点池打满）
> - Job 是**非幂等**的：把 Job 直接写进 Git 让 Argo CD 反复 sync，容易出现"已存在"卡住或被重复触发
>
> 所以正规做法是把 Job 的**触发权**收到控制面（Cloud Deploy、Cloud Scheduler + Cloud Run jobs、GKE Enterprise 的 GitOps 流水线），让集群内的 Job 只负责"执行"。

---

## 3. 核心概念（只看这几个就够）

### 3.1 Job

一次性任务，跑完 Pod 变 `Completed`；达到 `backoffLimit` 仍然失败就变 `Failed`。

关键字段：

| 字段 | 含义 | 小白理解 |
|------|------|---------|
| `completions` | 要成功完成几个 Pod | "我需要 3 个分片都跑完" |
| `parallelism` | 最多同时跑几个 Pod | "一次最多开 5 个并行" |
| `backoffLimit` | 失败几次后放弃 | "重试 3 次还不行就认输" |
| `ttlSecondsAfterFinished` | 完成后多久自动清理 | "跑完 1 小时后自动删掉 Pod，避免堆积" |
| `activeDeadlineSeconds` | 最长运行时间 | "最多跑 2 小时，超时杀掉" |

### 3.2 CronJob

按时间表重复创建 Job 的资源。

- `schedule`：cron 表达式
- `concurrencyPolicy`：上一轮没跑完时怎么办 —— `Forbid`（不并发）/ `Allow`（允许并发）/ `Replace`（替换旧的）

### 3.3 和 Deployment 的区别（最重要的对比）

| | Deployment | Job / CronJob |
|---|-----------|---------------|
| 生命周期 | 无限期运行 | 跑完即结束 |
| 副本语义 | 副本数由 HPA 动态调 | 完成后保留结果 / 日志，不保留 Pod |
| 幂等性 | 幂等（反复 apply 无副作用） | **非幂等**（重复执行 = 重复副作用） |
| 扩缩容 | HPA / VPA | `parallelism` 手动或由批处理控制器（如 Kueue）管理 |
| 典型用途 | API 服务、Worker 常驻进程 | 迁移、备份、报表、CI 任务 |

---

## 4. 在 GKE 上长什么样

GKE 托管的是 Kubernetes 控制面，所以 Job / CronJob 属于**原生能力**，不需要额外安装任何组件。
你真正要关心的是"谁来创建它"和"它跑在哪个节点池"。

### 4.1 最小示例

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: data-migration-20261026
  namespace: data-platform
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never          # Job 必须用 Never 或 OnFailure
      serviceAccountName: data-migration-sa
      containers:
        - name: migrate
          image: gcr.io/my-project/data-migration:1.4.2
          args: ["--batch-date", "2026-10-26"]
          resources:
            requests: { cpu: "500m", memory: "1Gi" }
            limits:   { cpu: "2",    memory: "4Gi" }
```

```bash
# 创建 + 查看
kubectl -n data-platform apply -f job.yaml
kubectl -n data-platform get jobs
kubectl -n data-platform logs job/data-migration-20261026

# CronJob：不等整点，手动触发一次
kubectl -n data-platform create job --from=cronjob/daily-report manual-$(date +%s)
```

### 4.2 生产上要关心的三件事（简单版）

1. **放哪个节点池** —— 批处理建议单独节点池 + 独立 Service Account，避免拖垮业务 Pod。
2. **能不能访问 GCP** —— 用 **Workload Identity**（GKE 原生最佳实践）让 Pod 以一个 GSA 身份访问 BigQuery / GCS / Cloud SQL，不要下发 Service Account JSON key。
3. **配额与公平性** —— 大 Job 会抢占节点。多团队共用集群时引入 **Kueue**（批处理调度器）做队列与配额，比裸用 Job 稳妥得多。

---

## 5. GCP 原生替代方案对比

| 需求 | K8s Job/CronJob | Cloud Run Jobs | Cloud Scheduler + Cloud Run | GKE Batch (JobSet) |
|------|-----------------|----------------|------------------------------|--------------------|
| 运行位置 | GKE 集群内 | Google 托管 | Google 托管 | GKE 集群内 |
| 需要自管集群吗 | 需要 | 不需要 | 不需要 | 需要 |
| 长时 / 高性能计算 | 强（可自定义资源） | 弱（CPU / 内存上限固定） | 弱 | 强（多 Pod 协同 + Gang 调度） |
| 定时触发 | CronJob | 靠 Cloud Scheduler 调 API | 内置 | CronJob / Kueue |
| 运维负担 | 中（自己管节点池） | 低 | 低 | 中高 |
| 适合 | 需要访问集群内服务 / 自定义算力 | 普通脚本、HTTP 任务 | 定时 API 调用 | 大规模并行作业 |

---

## 6. 该用哪个：决策表

| 你的场景 | 推荐做法 |
|---------|---------|
| 运维脚本（偶尔手动跑一次） | Cloud Run Jobs 或 GKE Job，按需 |
| 每天 / 每小时定时跑一个脚本 | Cloud Scheduler → Cloud Run Job（最省心）；必须在集群内才用 CronJob |
| 迁移 / 一次性重任务，要 GPU 或 StatefulSet | GKE Job + 专用节点池 |
| 发布后自动验证（冒烟测试） | **Cloud Deploy 的 post-deployment verification Job** |
| 多团队批量作业，要配额和排队 | GKE Job + **Kueue** + JobSet |
| 想把任务也纳管进 GitOps | 用 Argo CD 的 **Hook**（PostSync）跑 Job，而不是把 Job 本体 sync 进去 |

---

## 7. 什么时候**不要**用 Job

- 需要长期在线、随时接收请求 → 用 **Deployment / Service**
- 只是想跑一个 HTTP 接口（不是批处理）→ Cloud Run **Service**
- 任务之间有复杂依赖 DAG → 考虑 **Cloud Workflows** 或 **Argo Workflows**，而不是堆 CronJob
- 需要真正的弹性（不用时不占资源）→ Cloud Run Jobs / Knative（见 `knative-on-gke.md`）

---

## 8. 小结

| 记住这几点 | 内容 |
|-----------|------|
| 定位 | Job 是一次性任务，Deployment 是常驻服务 |
| GKE 支持 | 原生支持，无需安装组件 |
| 最容易踩的坑 | **非幂等** —— 不能简单地反复 apply；要用 `ttlSecondsAfterFinished` 清理；要设 `parallelism` 和资源 limit |
| 权限 | 用 Workload Identity 绑定 GSA，别下发 key 文件 |
| 平台化关键 | 把"触发权"收到 Cloud Deploy / Cloud Scheduler / GitOps 流水线，不要让业务直接建 Job |

**复杂度评估**：简单（原生 Job/CronJob）→ 中等（+ Kueue / Workload Identity）→ 高级 / 企业级（多集群批处理平台 + 统一配额审计）

---

## 9. 参考链接

- Kubernetes Job：https://kubernetes.io/docs/concepts/workloads/controllers/job/
- Kubernetes CronJob：https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/
- Cloud Deploy 发布后验证 Job：https://cloud.google.com/deploy/docs/verify
- Cloud Deploy IAM 角色 `roles/clouddeploy.jobRunner`：https://cloud.google.com/iam/docs/roles-permissions/clouddeploy.jobRunner
- Cloud Run Jobs：https://cloud.google.com/run/docs/create-jobs
- GKE Workload Identity：https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity
- Kueue：https://cloud.google.com/kubernetes-engine/docs/concepts/kueue
