# OPA 报告定时生成与 GitHub Pages 发布（CronJob 方案）

> 目标：每月在 GKE 集群内自动跑一次 OPA/Gatekeeper 巡检 → 渲染成单文件静态 HTML →
> 推送到公司内部 GitHub 仓库的 `gh-pages` 分支 → 由 GitHub Pages 直接对外提供访问。

复杂度评估：**Moderate**（单个 CronJob + 1 个 RBAC 身份 + 1 个 GitHub Secret，无常驻服务、无 Ingress、无外部 DB）。

---

## 1. 边界与前置假设

| 项 | 结论 |
|---|---|
| 采集逻辑 | 复用你**已经跑通**的采集/HTML 渲染流程，本方案只负责「调度 + 凭证 + 推送 + 幂等」 |
| 运行形态 | 一次性 Job 语义（跑完即终止），不是常驻 Deployment |
| 触发周期 | 每月一次，cron 表达式 `0 3 1 * *`（每月 1 日 03:00，**按 kube-controller-manager 时区，UTC**） |
| 产物 | 单个自包含 `index.html`（CSS/JS 内联），因为 GitHub Pages 静态托管不做构建 |
| 网络 | 集群节点需要出网到 `github.com:443`；私有集群无外部 IP 时需 Cloud NAT 或集群代理 |
| 鉴权 | 集群内用 **KSA（ServiceAccount）+ RBAC**；GitHub 侧用 **Secret 里的 token** |

**刻意不做**：不做常驻 Deployment、不做 Argo/GitOps 托管、不做多集群聚合、不引入额外中间件。

---

## 2. 整体链路

```
kube-controller-manager
        │  cron: 0 3 1 * *
        ▼
   CronJob (batch/v1)
        │  创建 Job Pod
        ▼
   Pod: collector-image
        ├─(1) 用 in-cluster SA token 调 K8s API，采集 Gatekeeper 数据
        ├─(2) 渲染单文件 index.html
        ├─(3) 用 GitHub token 读 gh-pages 上现有文件 → 内容一致则跳过
        └─(4) 不一致 → commit + push 到 gh-pages
        │  Job 完成 → Pod 退出 → TTL 回收
        ▼
   GitHub Pages（Source: gh-pages / root）→ 浏览器直接访问
```

失败处理：`backoffLimit: 1`，不刷屏；失败信息保留在 `kubectl get events` 与 CronJob 状态里，下月自然重跑。

---

## 3. 组件与凭证设计

### 3.1 三种身份，别搞混

| 身份 | 作用 | 需要什么权限 |
|---|---|---|
| **KSA**（Kubernetes ServiceAccount，`opa-report`） | Pod 内调 K8s API 采集数据 | ClusterRole：只读 gatekeeper/pods/events 等（见 3.2） |
| **GSA**（GCP ServiceAccount，可选） | 从私有 AR / GCS 拉镜像、读对象 | `roles/artifactregistry.reader`；Workload Identity 绑定 |
| **GitHub Token** | push 到 `gh-pages` | Secret，**Fine-grained PAT**（repo → Contents: RW）或 GitHub App token |

关键点：**KSA 不需要任何 GCP IAM 角色**，只要它带的 RBAC 够读资源即可。你说的「能 get 一些对应的东西」= ClusterRole 只读 + ClusterRoleBinding 绑到 KSA，三段 YAML 就够了。

### 3.2 采集需要的最小 RBAC

你的采集脚本要拿到的东西 → 对应 API group：

| 采集内容 | API group / resource | 动词 |
|---|---|---|
| 策略模板 `constrainttemplates` | `gatekeeper.sh` / `constrainttemplates` | list, get, watch |
| 策略实例 `constraints` | `gatekeeper.sh` / `constraints` | list, get, watch |
| 违规统计（status / events） | `core` / `events` | list, get |
| 工作负载元信息 | `core` / `pods`、`apps` / `deployments` | list, get |
| 集群拓扑 | `core` / `nodes`、`core` / `namespaces` | list, get |
| Webhook 健康 | `admissionregistration.k8s.io` / `validatingwebhookconfigurations` | list, get |
| 豁免命名空间配置 | `core` / `configmaps` | list, get |

给 **ClusterRole**（要跨命名空间扫全集群），但**全部只读**；不要写权限，不要给 `secrets`。

### 3.3 Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: opa-report-github
  namespace: opa-report
type: Opaque
stringData:
  GITHUB_TOKEN: "github_pat_xxxx"          # Fine-grained PAT, Contents: Read and write
  GITHUB_REPO: "org/internal-opa-report"    # owner/repo
  GITHUB_BRANCH: "gh-pages"
```

建议：token 只授权这一个 repo、设 90 天过期并接提醒；仓库开 2FA；`gh-pages` 分支不要开保护规则（否则 push 被拒，需走 PR 或临时放开）。

### 3.4 镜像与依赖

采集器镜像（建议 `python:3.12-slim` 基础）：

```dockerfile
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      jq git ca-certificates && rm -rf /var/lib/apt/lists/*
COPY collector.py render.py /app/
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
ENTRYPOINT ["python3","/app/collector.py"]
```

两条路线，二选一：

- **A（推荐，纯 Python）**：`pip install kubernetes`，用 `kubernetes.client` + `config.load_incluster_config()` 读集群，HTML 用 `jinja2` 渲染，GitHub 用 `requests` 调 REST API。**不装 kubectl / gcloud**，镜像小、无版本耦合。
- **B（复用现有 bash 脚本）**：镜像里额外装 `kubectl` + `jq`，脚本用 in-cluster 凭证运行。`kubectl` 在 Pod 内会自动使用 SA token（`/var/run/secrets/kubernetes.io/serviceaccount`），所以 `gcloud container clusters get-credentials` 那段**要删掉**，改成从 ConfigMap 注入 `project/cluster/region`。

若你的内部 JAR/image 在私有仓库：GKE 节点需能访问 Artifact Registry，**KSA 要绑 GSA + Workload Identity**（`iam.gke.io/gcp-sa-binding` 注解），否则拉镜像 403。这与采集权限是两件事。

---

## 4. 关键实现清单

### 4.1 CronJob 关键字段

| 字段 | 值 | 原因 |
|---|---|---|
| `schedule` | `"0 3 1 * *"` | 每月 1 日 03:00 |
| `timeZone` | `"Asia/Shanghai"`（K8s ≥1.27 支持） | 显式指定，免默认 UTC 差 8 小时；集群版本低就自己换算 |
| `concurrencyPolicy` | `Forbid` | 上个月没跑完时不叠加 |
| `startingDeadlineSeconds` | `3600` | 错过调度窗口 1 小时内仍补跑 |
| `successfulJobsHistoryLimit` / `failedJobsHistoryLimit` | `3` / `3` | 够看日志，不留垃圾 |
| `ttlSecondsAfterFinished` | `86400` | Job/Pod 一天后自动清理 |
| `restartPolicy` | `Never` | 一次性任务 |
| `backoffLimit` | `1` | 失败最多重试 1 次 |
| `activeDeadlineSeconds` | `1800` | 30 分钟不完成即杀掉，避免挂死 |

### 4.2 GitHub 推送要做的 3 件事

1. **幂等**：先用 token `GET repos/{owner}/{repo}/contents/{path}?ref=gh-pages` 取现有文件 `sha`，与新内容 sha 比；一致就**跳过提交**（否则每月一个空 commit，Pages 还白跑一次部署）。
2. **只更新目标文件**：用 `PUT` 覆盖 `index.html`（+ 可选 `report.json`），不要删仓库里其他文件。
3. **失败可诊断**：把 HTTP 状态码和 response body 打到 stderr 并 `exit 1`（K8s 只看得到 exit code，日志要自证）。

用 `git push` 也行，但要做 token 拼接、空 clone 分支初始化等处理；REST API 状态更少，**推荐 `requests` 调 GitHub Contents API**。

### 4.3 渲染输出

- 单文件 `index.html`，CSS/JS 全内联，**不引用外部 CDN**（内网访问不到，且 Pages 缓存策略差）。
- 报告时间戳会破坏「内容一致就跳过」→ 建议把时间戳放在页脚且**不参与比较**，或时间戳只写进 `report.json`。
- 若要保留历史：结果存 `history/YYYY-MM/index.html`，Pages 根 `index.html` 作入口。注意 PAT 需对 `history/` 目录也有 Contents 写权限。

---

## 5. 完整 YAML

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: opa-report
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: opa-report
  namespace: opa-report
  annotations:
    # 可选：Workload Identity（仅当镜像在私有 AR 或需访问 GCS 时保留）
    iam.gke.io/gcp-sa-binding: opa-report-gsa@PROJECT_ID.iam.gserviceaccount.com
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: opa-report-reader
rules:
  - apiGroups: ["gatekeeper.sh"]
    resources: ["constrainttemplates", "constraints"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps", "namespaces", "nodes", "events"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets"]
    verbs: ["get", "list"]
  - apiGroups: ["admissionregistration.k8s.io"]
    resources: ["validatingwebhookconfigurations", "mutatingwebhookconfigurations"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: opa-report-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: opa-report-reader
subjects:
  - kind: ServiceAccount
    name: opa-report
    namespace: opa-report
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: opa-report-config
  namespace: opa-report
data:
  CLUSTER_NAME: "your-cluster"
  PROJECT_ID: "your-project"
  GATEKEEPER_NS: "gatekeeper-system"
  AUDIT_TAIL: "50"
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: opa-report-publish
  namespace: opa-report
spec:
  schedule: "0 3 1 * *"
  timeZone: "Asia/Shanghai"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 3600
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 1
      ttlSecondsAfterFinished: 86400
      activeDeadlineSeconds: 1800
      template:
        spec:
          restartPolicy: Never
          serviceAccountName: opa-report
          containers:
            - name: collector
              image: REGION-docker.pkg.dev/PROJECT_ID/opa/collector:latest
              imagePullPolicy: IfNotPresent
              envFrom:
                - configMapRef:
                    name: opa-report-config
                - secretRef:
                    name: opa-report-github
              env:
                - name: RUN_MODE
                  value: "collect-render-push"
                - name: PYTHONDONTWRITEBYTECODE
                  value: "1"
              resources:
                requests: { cpu: "200m", memory: "256Mi" }
                limits:   { cpu: "1",    memory: "1Gi" }
              securityContext:
                runAsNonRoot: true
                runAsUser: 65532
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities: { drop: ["ALL"] }
              volumeMounts:
                - name: work
                  mountPath: /work
                - name: tmp
                  mountPath: /tmp
          volumes:
            - name: work
              emptyDir: {}
            - name: tmp
              emptyDir: {}
```

> `readOnlyRootFilesystem: true` 时 Python 写 `.pyc`/缓存会报错，所以额外挂了 `/tmp`，并设 `PYTHONDONTWRITEBYTECODE=1`。

---

## 6. 发布与验证

### 6.1 GitHub 仓库一次性配置

1. 建仓库（或用现有仓库），新建分支 `gh-pages`。
2. `Settings → Pages → Build and deployment → Source = Deploy from a branch`，选 `gh-pages` / `/ (root)`。
3. PAT 权限：Fine-grained 只授权这一个仓库，Contents: Read and write。

### 6.2 首次手工跑通（不要等下个月）

```bash
kubectl -n opa-report create job --from=cronjob/opa-report-publish opa-report-manual-$(date +%s)
kubectl -n opa-report logs -f job/opa-report-manual-<ts>
kubectl -n opa-report get job -o wide
kubectl -n opa-report describe job <name> | tail -30   # 失败时看 Events
```

验收清单：

- [ ] Job `COMPLETE`，退出码 0
- [ ] `gh-pages` 分支出现 `index.html`，Pages URL 可打开
- [ ] 第二次手工跑：无新 commit（幂等生效）
- [ ] 故意改坏 token：Job 失败，日志有明确 HTTP 错误，且**没有**污染分支

### 6.3 常见故障速查

| 现象 | 原因 | 处理 |
|---|---|---|
| `403` 读 `gatekeeper.sh` | RBAC 缺，或集群没装 Gatekeeper CRD（Policy Controller 与开源 Gatekeeper CRD 不完全等价） | 补 RBAC；确认 ConstraintTemplate CRD 存在 |
| event 里取不到违规明细 | Event 聚合/保留期限制 | 改读 `status` 字段；或调小 `audit-tail` |
| push 401/403 | PAT 过期、缺 `contents:write`、SSO 未授权 | 换 token 或改用 GitHub App |
| push 403 `protected branch` | `gh-pages` 开了保护 | 取消保护或走 PR 流程 |
| Pod 卡到超时 | 节点出网不通 github.com | 私有集群配 Cloud NAT；或设 `HTTPS_PROXY` env |
| 每月都产生空 commit | 报告内时间戳参与比较 | 见 4.3 |

---

## 7. 加固建议（按优先级）

1. **token 生命周期**：Fine-grained PAT 设 90 天过期 + 外部提醒；更稳的做法是 GitHub App（密钥自动轮换）。
2. **历史归档**：报告落 `history/YYYY-MM/`，Pages 根做索引页。
3. **失败告警**：在 Pod 里挂通知逻辑不是好选择；用 Cloud Monitoring / 外部轮询 CronJob 状态告警。
4. **产物可审计**：对 `index.html` 做 sha256 并写入同目录 `report.json`。

---

## 8. 后续可扩展方向（暂不实施）

- 多集群聚合：每个集群一份 CronJob + 汇总仓库，或用 OPA exporter。
- 从「每月巡检」升级为「策略漂移检测」：对比相邻两期 Constraint/ConstraintTemplate 差异生成 diff 报告。
- 把违规数作为 metric 上报 Cloud Monitoring，配 Alert Policy。
