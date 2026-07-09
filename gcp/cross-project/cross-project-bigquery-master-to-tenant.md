# 跨项目 BigQuery 联邦:Master 项目 GKE → Tenant 项目 BigQuery

> **TL;DR**
>
> **场景**:Pod 在 master 项目的 GKE 里,通过 Workload Identity Federation 拿到一个 GSA 身份,然后用这个身份去查 tenant 项目里 BigQuery dataset 的数据。**master 项目自己没有任何 BigQuery dataset**(它是应用/服务层),数据全在 tenant(数据/分析层)。
>
> **本质是两个独立 IAM 边界要打通**(不是"加一个网桥"那么简单):
>
> 1. **auth-side**:Workload Identity Federation 让 master 项目里的 KSA → master 项目里的 GSA(身份链);
> 2. **resource-side**:tenant 项目那边的 BQ dataset 必须**显式**承认这个 GSA 的身份(授权链)。
>
> **方案不止一种**。本文罗列 **6 种可行/不推荐方案**,并给出选型矩阵 + 验证脚本。**最终方案决策必须考虑查询模式**(联邦 SQL vs batch export vs client-side copy)、**数据量级**、**租户契约**(tenant 是否允许 data egress)。

---

## 1. 为什么这篇文档要存在?

姊妹文章 [`../pub-sub/cross-project-pub-sub-debug-sa.md`](../pub-sub/cross-project-pub-sub-debug-sa.md) 处理的是 cross-project **Pub/Sub**(异步消息),本文处理的是 cross-project **BigQuery**(数据查询/导出)—— **IAM 拓扑、token 链、SA 绑定位置完全不一样**, 不能复用。

跨项目 BigQuery 比 Pub/Sub **复杂得多**,因为它有三套独立的 IAM 边界:

```
           ┌───────────────────────┐         ┌───────────────────────┐
           │ Master Project        │         │ Tenant Project         │
           │ (应用 / 服务层)        │         │ (数据 / 分析层)         │
           ├───────────────────────┤         ├───────────────────────┤
           │  GKE cluster          │         │  BigQuery dataset A    │
           │  ├─ KSA: app-ksa      │         │  BigQuery dataset B    │
           │  │  (ns=app)          │         │  GCS bucket (audit)    │
           │  └─ GSA: app-gsa@M    │         │                       │
           │     (master 创建)      │         │  IAM boundary here ───┼─→ 你要打通的边界
           │                       │         │                       │
           │  (master 自己无 BQ)    │         │                       │
           └───────────────────────┘         └───────────────────────┘
                 ↑                                     ↑
                 │                                     │
         Workload Identity Federation           资源-side IAM
         (auth-side 链路)                      (resource-side 链)
```

三套 IAM 边界:

1. **KSA 必须在 master 项目的 GKE 集群里能说话**(WI 链路)
2. **master 项目的 GSA 必须能 impersonate**(WI binding)
3. **tenant 项目的 BigQuery dataset/IAM 必须认识这个 GSA**(auth/role grant)

任何一处漏了,PBI 里就显示 `403 Permission denied` / `accessDenied` / `BigQuery Service ... has not been used in project ... or it does not have the required IAM permissions`。本文一次性把这三个边界讲清楚 + 怎么验证。

---

## 2. 三视角:同一事实的不同切面

下文用三种视角描述同一场景,**先选你舒服的入口**:

- **§3 抽象视角**:从"BigQuery 跨项目授权模型"出发(KSA→GSA → BigQuery Access Control)
- **§4 朴素视角**:从"gcloud / yaml 一行行怎么写"出发(可直接 copy-paste 的命令栈)
- **§5 严格视角**:**完整 6 方案** 的 trade-off 矩阵 + 选型决策树

**(§6 给"我就要一行结论"的人:六方案速选表 + 默认建议)**

---

## 3. 抽象视角:BigQuery 跨项目授权有三条独立可配 IAM 链

### 3.1 BigQuery 的鉴权抽象

BigQuery 鉴权是 **两层 IAM + 一个 dataset-level 强制 allowlist**:

```
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 1:Project-level IAM                                          │
│   - 给 GSA / User / Group / Domain 绑 project 级角色:               │
│     • bigquery.dataViewer (读 dataset)                              │
│     • bigquery.dataEditor (读写 dataset)                            │
│     • bigquery.jobUser (运行 query)                                 │
│     • bigquery.user (= dataViewer + jobUser)                       │
│   - 角色约束:**用户必须有 project 级 IAM + dataset 级 IAM 中至少一个│
│     才允许 query**(BigQuery Access Control Layer 2 强制覆盖)        │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 2:Dataset-level IAM(每个 dataset 单独一份)                  │
│   - 同 Layer 1 的角色,但只授予这个 dataset                       │
│   - 不要 dataset-level access → 即便有 project-level 也无法 query│
│   - 上限:**数据集 ACL 不能给出超出 project-level 的权限**         │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 3(可选):Authorized Datasets / Authorized Views / Auth Routines│
│   - 一个 dataset 的 access array 里声明              "允许           │
│     别的 project 来 query" → 解决"dataset-level 不能引 dataset     │
│     以外的资源"的限制                                                  │
│   - 关键命令:`bq update --source <file>` 把 "access" 字段 patch    │
│     `{ "dataset": { "dataset": { "project_id": "TENANT",          │
│     "dataset_id": "AUTH_DATASET" }, "target_types": "VIEWS" } }`  │
│   - 参考:https://cloud.google.com/bigquery/docs/authorized-datasets│
└──────────────────────────────────────────────────────────────────────┘
```

**为什么需要 Layer 3?**
因为在没有 Layer 3 的情况下,跨项目 query 必须用**完整 project-qualified table reference**(`tenant-project.analytics.events`),但**所有 IAM 边界仍要在 dataset 级判定** —— 这意味着:

- 你要 query `tenant.analytics.events` → tenant IAM 让 GSA 读这个 dataset
- 但如果你想 query `tenant.analytics.events JOIN master.lookup.users`,**仍然只看 tenant-side** —— 跨 project JOIN 的数据可见性 **完全受控于每边的 dataset IAM**
- Authorized Datasets/Layer 3 是为了**让 master project 里的 authorized view / routine 反过来访问 tenant dataset**,专门用于"把 tenant 数据小心露出给 master view/v proc"场景

**我们的 master→tenant 简单场景不需要 Layer 3**(只需要 Layer 1+2 在 tenant 端给 GSA 授权)。Layer 3 在 §5 方案里列出来作为"需要让 tenant 数据包装成 master-side view 时的工具"。

### 3.2 Workload Identity Federation 那条链

> 摘自 Google 官方文档(<https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity>):
>
> When you enable Workload Identity Federation for GKE, the GKE metadata server intercepts the token request and asks the Kubernetes API server for a Kubernetes ServiceAccount token that identifies the requesting workload. This credential is a JSON web token (JWT) that's signed by the API server. The GKE metadata server uses Security Token Service to exchange the JWT for a short-lived federated access token that **identifies the workload as a Google Cloud service account that the Pod is configured to impersonate**.

也就是说:

```
Pod 内部
  ↓ code: client.DefaultAccessToken()  (Google 官方 client library 都默认这样)
  ↓
  → GET metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token
  ↓ GKE metadata-server (in VM)
  ↓ 拦截 + 拿 KSA 的 signed JWT
  ↓ 用 STS exchange → federated token
  ↓ 自动 impersonate = KSA annotation 上的 GSA
  ↓
  → 返回 GCP access token (1 小时有效)
  ↓
Pod 用这个 token access bigquery.googleapis.com → tenant 项目 IAM 验证 → BQ dataset 验证 → 返回数据
```

**关键事实:**

1. KSA → GSA 是 **一对一 impersonate**(多个 KSA 要不同 GSA,就用不同 annotation)
2. **GSA 必须在 master 项目里创建**(不要试图在 tenant 项目创建 GSA 跨项目使用 —— WI 链路不允许)
3. **GSA 需要拿到 IAM role** 才能调 BQ —— **这条 role grant 既可以在 master 项目打,也可以在 tenant 项目打**
4. token 是 **短时**(1 小时 client library 默认 cache)
5. IAM 边界跟网络 **解耦**:即使你的 GKE 不在 master 项目的 VPC 里、即使 tenant 的 BQ dataset 在另一个 region,**只要 GSA 在 tenant 项目里有 role,就能 query**(当然有 VPC Service Control 时另说,见 §5.6)

---

## 4. 朴素视角:命令栈拆解 + yaml 模板

### 4.1 三阶段工作流(每一阶段都有自己的 IAM 验证)

```
阶段 0 │ 命名 + 命名空间预定义
       │ ↓
阶段 1 │ master 项目开 Workload Identity Federation for GKE
       │ (cluster-level 开关,新建 cluster 时默认开)
       │ ↓
阶段 2 │ master 项目创建 GSA,绑到 GSA 上 KSA namespace 上的 Workload Identity User role
       │ (auth-side 链)
       │ ↓
阶段 3 │ tenant 项目把 master 的 GSA 添加到目标 dataset 的 IAM
       │ (resource-side 链)
       │ ↓
阶段 4 │ Pod 端验证(query 真实 dataset)
```

下面用 **PLACEHOLDER 替换** 把整个栈写出来,任何环境直接 `sed -i 's/PLACEHOLDER/real-value/g` 即可跑。

```bash
# ============================================================
# 全局占位符(替换成你环境的实际值)
# ============================================================
export MASTER_PROJECT="master-project-prod"      # 你的 master 项目 ID
export TENANT_PROJECT="tenant-project-data"      # 你的 tenant 项目 ID

export MASTER_REGION="europe-west2"              # GKE region
export GKE_CLUSTER="app-cluster"                 # GKE cluster
export K8S_NAMESPACE="app"
export KSA_NAME="app-ksa"

export GSA_NAME="master-bq-reader"               # master 项目里的 GSA
export GSA_EMAIL="${GSA_NAME}@${MASTER_PROJECT}.iam.gserviceaccount.com"

export BQ_DATASET="analytics"                    # tenant 项目里的 dataset
export BQ_READ_ROLE="roles/bigquery.dataViewer"  # 或 bigquery.user 看场景

# ============================================================
# 阶段 1(只在首次 / 新 cluster): 启用 GKE WI Federation
# ============================================================
gcloud container clusters update "$GKE_CLUSTER" \
  --region="$MASTER_REGION" \
  --workload-pool="${MASTER_PROJECT}.svc.id.goog"

# 新建 cluster 默认带这个,但要 confirm:
gcloud container clusters describe "$GKE_CLUSTER" --region="$MASTER_REGION" \
  --format="value(workloadIdentityConfig.workloadPool)"
# 期望输出:master-project-prod.svc.id.goog

# ============================================================
# 阶段 2:master 项目内 GSA + WI binding
# ============================================================
# 2.1 创建 GSA
gcloud iam service-accounts create "$GSA_NAME" \
  --project="$MASTER_PROJECT" \
  --description="BQ reader from master GKE → tenant BQ"

# 2.2 允许 KSA (ns + sa name) impersonate 这个 GSA
#     canonical format:
#     serviceAccount:<master_project>.svc.id.goog[<namespace>/<ksa>]
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
  --project="$MASTER_PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${MASTER_PROJECT}.svc.id.goog[${K8S_NAMESPACE}/${KSA_NAME}]"

# 2.3 (可选) 给 master 项目的 GSA 一个 master 内的最低 role
#     让 client library 能调 bq.googleapis.com 的 "get current IAM policy"
#     不影响 tenant 端 BQ 访问。
#     通常不需要 —— 但生产调试时给个 roles/bigquery.jobUser 不亏:
#     gcloud projects add-iam-policy-binding "$MASTER_PROJECT" \
#       --member="serviceAccount:${GSA_EMAIL}" \
#       --role="roles/bigquery.jobUser"

# ============================================================
# 阶段 3:tenant 项目把 GSA 加到目标 BQ dataset
# ============================================================
# 3.1 让 GSA 在 tenant project IAM 上看到 project-level 角色(可读 dataset 列表)
#     注意:BQ 的"看到 dataset"权限不是项目级,而是 dataset 级 +
#     bigquery.datasets.list (project 级)
#     必须至少给 dataset-level,这里给一个最小的 project 级,以便 list:
gcloud projects add-iam-policy-binding "$TENANT_PROJECT" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="roles/bigquery.metadataViewer"

# 3.2 给 GSA 在目标 dataset 上 + 数据角色 + job 用户角色
gcloud bigquery datasets add-iam-policy-binding "$BQ_DATASET" \
  --project="$TENANT_PROJECT" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="$BQ_READ_ROLE"

gcloud bigquery datasets add-iam-policy-binding "$BQ_DATASET" \
  --project="$TENANT_PROJECT" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="roles/bigquery.jobUser"

# 3.3 (可选) 如果 POD 不只查这个 dataset,给多个 dataset 加,或者项目级 bigquery.user

# ============================================================
# 阶段 4:K8s 端 KSA annotation
# ============================================================
# 4.1 给 KSA 加注解,绑定 GSA
kubectl annotate serviceaccount "$KSA_NAME" -n "$K8S_NAMESPACE" \
  iam.gke.io/gcp-service-account="$GSA_EMAIL"

# 4.2 (在 GKE 1.24+ 推荐) 同时打 workload identity 标签 namespace:
kubectl label namespace "$K8S_NAMESPACE" \
  iam.gke.io/workload-identity=true

# ============================================================
# 阶段 5:验证(可选但强烈推荐)
# ============================================================
# 5.1 拿到一个 GKE shell + verify 身份链
kubectl exec -n "$K8S_NAMESPACE" deploy/your-app -- \
  gcloud auth print-access-token --impersonate-service-account "$GSA_EMAIL"
#    ↑ 这一步在 Pod 里跑必须预先装 gcloud,生产里少见。
#    生产环境推荐用 Go/Python client 验证,见 §4.2

# 5.2 用 BIGQUERY 客户端跑一条 query
kubectl exec -n "$K8S_NAMESPACE" deploy/your-app -- \
  bq query --project_id="$TENANT_PROJECT" \
  --use_legacy_sql=false \
  "SELECT COUNT(*) FROM \`${TENANT_PROJECT}.${BQ_DATASET}.__TABLES__\`"
```

### 4.2 Pod 端验证:用 client library 跟 BigQuery 通话

> 假设你能在 container 跑命令。Go / Python client library 都默认走 ADC(Application Default Credentials)→ GKE metadata-server → 自动拿到 GSA。

#### Go

```go
import (
    "context"
    "fmt"
    "cloud.google.com/go/bigquery"
    "google.golang.org/api/iterator"
)

func pingTenantBQ(ctx context.Context) (int64, error) {
    // ADC 用 GKE metadata-server 链到 KSA → GSA
    client, err := bigquery.NewClient(ctx, "tenant-project-data")
    if err != nil { return 0, fmt.Errorf("client: %w", err) }
    defer client.Close()

    q := client.Query("SELECT COUNT(*) AS n FROM `tenant-project-data.analytics.__TABLES__`")
    it, err := q.Read(ctx)
    if err != nil { return 0, fmt.Errorf("read: %w", err) }

    var row struct{ N int64 }
    if err := it.Next(&row); err != nil && err != iterator.Done {
        return 0, fmt.Errorf("scan: %w", err)
    }
    return row.N, nil
}
```

#### Python

```python
from google.cloud import bigquery

def ping_tenant_bq() -> int:
    client = bigquery.Client(project="tenant-project-data")  # 自动 ADC
    q = "SELECT COUNT(*) AS n FROM `tenant-project-data.analytics.__TABLES__`"
    rows = list(client.query(q).result())
    return rows[0]["n"]
```

> **注意**:Python `Client(project=...)` 设的是"这个客户端的默认 project"——**仅用于生成请求默认 URL,不影响 IAM 验证**。**IAM 验证永远是看 token 所标识的 GSA 在 tenant 项目里有没有 dataset 权限**。

---

## 5. 严格视角:6 种方案 + 选型决策树

### 5.1 方案对比矩阵

下面是 master→tenant BigQuery 访问这个问题的**完整解决方案集**:

| 方案 | 一句话 | 跨项目 IAM 边界数 | 网络边界 | 复杂度 | **租户契约影响** | **数据出 tenant** |
|------|--------|--------------|---------|-------|------|------|
| 1️⃣ WI + tenant-side IAM 联邦 | KSA→GSA→BQ dataset IAM | 2 (WI + BQ IAM) | Google 内部 RPC,无额外网络 | 低 | tenant dataset IAM 加 GSA 即可 | tenant 数据只在 query 时被 GSA 拉到 master 端 |
| 2️⃣ WI + Authorized Dataset(target_types=VIEWS) | master-side view 反向包入 tenant 数据 | 3 (+master view IAM) | 同 1 | 中 | tenant 加 Authorized entry → master-side view 能 query **仅 view** | tenant 数据**始终在 tenant**,只在 view 里被选走字段 |
| 3️⃣ service account key JSON(不推荐) | 把 SA key 文件 mount 到 pod,直连 tenant BQ | 2 (BQ IAM + key) | 同 1 | 低 | tenant IAM 加 GSA | ⚠️ 长时 key(一年过期)→ 安全噩梦 |
| 4️⃣ GCS 中转 + BQ export | tenant BQ → GCS → master 从 GCS 拉 | 3 (BQ IAM + Storage IAM + WI) | 走 gs:// | 高 | tenant 加 BQ export + Storage IAM | 数据存 GCS,**公开存储**,安全弱 |
| 5️⃣ BigQuery Omni / 跨 region bq transfer | BQ 自家服务跨 project 自动迁移 | 1 (BQ IAM) | BQ 服务链 | 中 | tenant 设源、master 设目标 | 数据在 BQ 服务边界内迁移,**不出 GCP** |
| 6️⃣ Private Google Access + tenant 自家 VPC endpoint | 把 BQ API 走 private endpoint | 4 (+VPC + Private DNS) | VPC service control | 高 | VPC-SC 保护 + tenant IAM | **强制所有访问走 VPC**——需要在 master 的 GKE node VPC 配 |

### 5.2 决策树

```
你的需求是什么?
  │
  ├── 单条 / 轻量 query,master pod 直接拉数据
  │     → 方案 1 ✅ 默认推荐
  │
  ├── master-side 分析代码需要"读 tenant 某些聚合后的字段"但不直接 SELECT *
  │     → 方案 2 ✅ Authorized Dataset + master-side view
  │
  ├── 出于某些限制不能用 GKE WI(传统集群 / 迁移期)
  │     → 方案 3(临时)+ 迁移期升级方案 1
  │
  ├── 批量把 tenant 全表批量 export 到 master
  │     → 方案 4(GCS 中转)/ 方案 5(BQ transfer)
  │
  ├── 有严格监管要求,tenant 数据不能"流露"到 master endpoint
  │     → 方案 2(数据永远在 tenant) / 方案 5(BQ 服务侧迁移)
  │
  └── VPC-SC / 网络隔离要求强制所有 GCP API 走 private endpoint
        → 方案 6 + 方案 1(后端仍走 IAM,但 surface 走 private)
```

### 5.3 各方案细节

#### 方案 1:WI + tenant-side IAM 联邦(默认推荐)

**链路**:Pod (KSA) → GKE metadata-server → STS exchange → impersonate master GSA → tenant BQ IAM verify → dataset IAM verify → 返回数据

```bash
# 必要 IAM:
# 1) master project: roles/iam.workloadIdentityUser on GSA ← KSA(ns/sa)
# 2) tenant project: roles/bigquery.dataViewer + roles/bigquery.jobUser on dataset
```

**优点**:
- 最小依赖(只要 GKE WI + 两条 IAM)
- token 短时 + 自动 rotating,无 key 泄露风险
- 任何 Google 官方 client library 自动适用(Go / Python / Node / Java)

**缺点**:
- 跨 project 不允许**跨账号**查询(只能从 master 项目的 GSA 视角 → tenant dataset IAM 单向)
- 如果要 SET 临时结果 / temp table,需要 `bigquery.user` 角色

**适用 90% 场景**。

#### 方案 2:Authorized Dataset(用于"master-side view 包装 tenant 字段")

> 摘自 <https://cloud.google.com/bigquery/docs/authorized-datasets>:
>
> Authorized datasets allow you to share access to specific datasets with a view in another project. **You can grant cross-project access to your dataset without sharing data-set-wide IAM permissions with the other project.**

```bash
# 1. 在 master 项目创建一个 dataset "shared_view_dataset"
# 2. 在 shared_view_dataset 上创建一个 view: master_view_01
# 3. view 内部 SQL 引用 tenant dataset:
#    SELECT date_trunc(date, day) AS day, COUNT(*) AS c
#    FROM `tenant-project.analytics.events`
#    GROUP BY 1
# 4. tenant 这边把 master view 加进 tenant BQ dataset access list:
TENANT_DATASET="analytics"
MASTER_PROJECT="master-project-prod"
MASTER_VIEW_DATASET="shared_view_dataset"
MASTER_VIEW_ID="master_view_01"

# 把 tenant dataset access entry patch 进一个文件,然后 bq update --source
jq '.access += [{
  "view": {
    "projectId": "'"$MASTER_PROJECT"'",
    "datasetId": "'"$MASTER_VIEW_DATASET"'",
    "viewId":    "'"$MASTER_VIEW_ID"'"
  }
}]' <(bq show --format=prettyjson "$TENANT_PROJECT:$TENANT_DATASET") > /tmp/auth.json

bq update --source /tmp/auth.json "$TENANT_PROJECT:$TENANT_DATASET"
```

**优点**:
- tenant 数据**始终在 tenant**,master view 仅 select 想要的字段 → 数据治理 / 隐私契约友好
- tenant 不需要给 GSA 在 master 项目临时 IAM(只有 master view 自己有读写)
- 大数据量 JOIN 时 master 这边不存全表

**缺点**:
- 需要 maintain master view
- master 项目的 GSA 仍要用方案 1 的 WI setup(因为 view 依然要走 GKE metadata-server),所以是"方案 1 + Authorized Dataset" 的组合

**适用**:tenant 数据需要严格管控 → master 项目只能看聚合结果 → 数据契约 / 合规场景。

#### 方案 3:service account key JSON(不推荐,迁移期备胎)

```bash
# master 项目生成 key(JSON file)→ kubectl secret mount to pod
gcloud iam service-accounts keys create /tmp/master-bq-reader.json \
  --iam-account="$GSA_EMAIL"

kubectl create secret generic gsa-key -n "$K8S_NAMESPACE" \
  --from-file=key.json=/tmp/master-bq-reader.json

# Pod spec
# volumes:
#  - name: gsa-key
#     secret:
#       secretName: gsa-key
# containers:
#  - name: app
#     volumeMounts:
#      - name: gsa-key
#         mountPath: /var/run/secrets/gsa
#         readOnly: true
#     env:
#      - name: GOOGLE_APPLICATION_CREDENTIALS
#         value: /var/run/secrets/gsa/key.json
```

**优点**:
- 任何环境都跑(GKE / GCE / on-prem 都行)

**缺点**:
- ⚠️ **key 长期有效**,泄露后 tenant IAM 直接接管所有 dataset
- ❌ **没有自动 rotate**,要靠日历/SecOps 提醒换 key
- ❌ 必须用 `roles/iam.serviceAccountTokenCreator` 才能让 WI 优势消失
- ❌ 任何 pod 看到了 secret 都等于有完整 GSA 身份

**别用**。**只在 GKE WI 启用前的过渡期用,立刻迁到方案 1。**

#### 方案 4:GCS 中转 + BigQuery export

**思路**:tenant 把 BQ dataset → export GCS(权限:BQ + Storage),master 从 GCS 拉 GCS(权限:Storage)。

```bash
# tenant 项目:export BQ table to GCS
SOURCE_TABLE="tenant-project-prod.analytics.events_20260601"
GCS_BUCKET="tenant-archive-eu"

bq extract --project_id="$TENANT_PROJECT" \
    "$SOURCE_TABLE" \
    "gs://$GCS_BUCKET/$YEAR/$MONTH/$DAY/events_*.parquet"

# master 项目这边:用 Google Cloud Storage transfer 拉过来(或 gsutil)
gsutil cp -m "gs://${GCS_BUCKET}/${YEAR}/..."  "gs://master-archive-eu/..."
```

**优点**:
- 绕开所有 BQ IAM 复杂性,直接用 GCS IAM(两套都给就行)
- batch 性能好,大表 export 成本低

**缺点**:
- 数据要写真实一份到 GCS,**两套 IAM 都要正确**,一不小心就走漏
- 实时性差:export 是 batch / event-driven,**不是 query time fresh**
- 中转的 parquet / Avro 是 tenant 数据快照,**有 PII / 数据驻留 challenge**

**适用**:**离线 ETL 场景**(每晚 T+1 同步 dashboard / SCD)。

#### 方案 5:BigQuery Omni / 跨 region BQ transfer service

```bash
# BigQuery Data Transfer Service
bq mk --transfer_config \
  --project_id="$MASTER_PROJECT" \
  --data_source_id="cross_region_copy" \
  --target_dataset="master_warehouse" \
  --display_name="tenant-bq-backup" \
  --params='{"source_dataset_id":"'$BQ_DATASET'","source_project_id":"'$TENANT_PROJECT'"}'
```

**优点**:
- 全 BQ 服务侧,**数据不出 BQ 服务区边界**
- 自动 schedule + 错误 retry + audit
- 不需要 GCS / IAM 多套

**缺点**:
- **transfer 是 batch + schedule**,不是 query time
- BQ Omni 仅限跨 cloud provider(AWS / Azure)的有限 region

**适用**:master 项目要做"tenant data 的集中 warehouse",定期回灌到 master 项目。

#### 方案 6:Private Google Access + tenant 自家 VPC endpoint

**思路**:所有 master 项目 → BigQuery 的 API 调用**强制走 master project 的 VPC**,然后通过 Private Service Connect / VPC Service Controls 接入 tenant 的 BQ。

```yaml
# node pool 加 Private Google Access (默认 enabled 是 false)
# 1. master project: Master Shared VPC
# 2. master project: Service Networking → tenant project via Private Service Access
# 3. master project: 在 Master VPC 上创建 restricted.googleapis.com (PSA + Private DNS)
# 4. tenant project: BigQuery service endpoint → tenant VPC SA IP range

# K8s 部署的 pod 用 bq REST API 时,会通过 metadata-server → restricted IP:
# 169.254.169.254 → k8s API server JWT → STS → GSA impersonate
# → bq.googleapis.com (走 restricted.googleapis.com, master VPC 内)
# → private endpoint tenant (PSI / PSC) → tenant BQ API
```

**优点**:
- 网络完全受控(数据走 Master VPC IP,不直接 internet)
- 配合 VPC-SC(注意:master 和 tenant VPC-SC 不同,需要在 IAM allowlist 互表)
- 防御性最强,适合金融 / 医疗

**缺点**:
- **复杂度爆炸**:VPC + PSC + VPC-SC + 双向 allowlist
- 一处配置错就 query 失联
- **性能**:走 internal IP(RTT 跨 VPC 略增,通常 <5ms 仍 OK)

**适用**:**金融 / 医疗 / 严格合规场景**。**默认不要碰**。

### 5.4 方案选型三角

```
                   ┌──────────────────────────────┐
                   │   Operational Complexity      │
                   │   (部署 + 监控难度)            │
                   └──────────────────────────────┘
                                ▲
                                │
                                │
              ◄─────────────────┼─────────────────►
                Real-time                                       Batch
             (query time 数据)                          (T+1 同步)
                                │
                                │           Simple
                                │           (just IAM)
                                │
                   ┌──────────────────────────────┐
                   │  Tenant Data Sovereignty  ⭐   │
                   │  (数据可否出 tenant 边界)        │
                   └──────────────────────────────┘
```

- **右上角"高复杂度 + Real-time + 强 sovereignty"**:方案 2(Authorized Dataset)
- **右下角"中等 + Batch + 受限"**:方案 4(GCS) / 方案 5(BQ Transfer)
- **左上角"低 + Real-time"**:方案 1(WI + IAM) ← 默认
- **左下角"低 + Batch + 不限"**:方案 1 + cron export(也是方案 4 简化)
- **中上"高 + Real-time"**:方案 6(VPC-SC)

### 5.5 默认方案 + 备胎决策

**默认走方案 1 + 方案 2 组合**:

- 日常 query:方案 1(WI + tenant dataset IAM)
- 给 master 项目 data-scientist 用 view:方案 2(Authorized view)

**什么时候选方案 4/5**(batch):当且仅当**有 ETL 需求**(数据要 landing 到 master warehouse / SCD / dashboard cache),并且**实时性不是首要**。

**什么时候选方案 6**: 你的运维流程(现有 onboarding / SecOps 标准)已经全面强制 VPC-SC,否则别碰。

### 5.6 几个容易踩的坑(每个方案都有)

#### 坑 1:only `bigquery.dataViewer`,没 `bigquery.jobUser`

**症状**:query 出现 `Permission denied while running BigQuery job`

**原因**:BQ 是 "data role + job role" 双角色机制。**光有 `dataViewer` 你能看 existing table,跑不了 query**。

**修法**:两个都绑。详见 <https://cloud.google.com/bigquery/docs/access-control>。

#### 坑 2:`roles/iam.workloadIdentityUser` 绑错地方

**症状**:Pod 拿到的是 KSA token,但 bq.googleapis.com 收到 401

**原因**:Workload Identity User 必须绑在 **GSA 资源的 IAM policy**(不是 project-level):

```bash
# ✅ 正确:
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
  --project="$MASTER_PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${MASTER_PROJECT}.svc.id.goog[ns/sa]"

# ❌ 错误:
gcloud projects add-iam-policy-binding "$MASTER_PROJECT" \
  --member="serviceAccount:${MASTER_PROJECT}.svc.id.goog[ns/sa]" \
  --role="roles/iam.workloadIdentityUser"
```

#### 坑 3:tenant-side dataset IAM 加在 project IAM 而非 dataset IAM

**症状**:`bigquery.datasets.list` 能跑,但 `SELECT * FROM ...` 报 Permission denied

**原因**:**BQ 的真实 ACL 边界在 dataset 一级**,project IAM 只是辅助。**必须**用:

```bash
# ✅ dataset-level IAM
gcloud bigquery datasets add-iam-policy-binding "$BQ_DATASET" ...

# ❌ 只在 project-level 给 dataViewer
gcloud projects add-iam-policy-binding "$TENANT_PROJECT" \
  --role="roles/bigquery.dataViewer" ...
# (这个可以让 GSA 看到 metadata,但 query 还是要 dataset-level)
```

#### 坑 4:Authorized Dataset 里 master view 没必要的 IAM

**症状**:`bq show tenant.analytics` 看 access list 里有 master view, 但 master view 跑 query 报 403

**原因**:**Authorized Dataset 只让 master view 看到数据集**;**master view 自己**还得有 access token 去访问 tenant 数据(还是方案 1 的 GSA + dataset-level IAM)。

#### 坑 5:跨 region BigQuery 的 API endpoint

**症状**:master → tenant dataset 跨 region,query 偶发 timeout

**原因**:BQ 在某些 region 用的是 `eu-bigquery.googleapis.com` 而不是 global endpoint。client library 默认会选 endpoint,**如果 IAM 或 VPC-SC 没允许跨 region,可能偶尔失败**。

**修法**:在 master 项目允许 master GSA 通过 VPC-SC Perimeter,或者用 client library 显式设 `client.WithEndpoint(...)`。

#### 坑 6:VPC-SC 在 master ↔ tenant 边界没互表

**症状**:**所有 query 报 VPC_PERIMETER_DENIED**

**原因**:master perimeter 和 tenant perimeter 没互相加 access levels。

**修法**:

- master perimeter 加 access level:tenant service identities of GSA
- tenant perimeter 加 access level:master GSA 的 workload identity principal
- 见 §13 引用 §VPC Service Controls 文档

#### 坑 7:用 `gcloud auth application-default login` 在本地

**症状**:**本地**能 query,**部署到 GKE 后**失败

**原因**:local ADC 通常是 user cred,不是 GSA。生产 pod 应该走 metadata-server,确保 client library **不读** `GOOGLE_APPLICATION_CREDENTIALS` 环境变量。

**修法**:**别 set `GOOGLE_APPLICATION_CREDENTIALS` in production**;GKE metadata-server 自动接管。

---

## 6. 一句话选型指南

**默认**:方案 1(WI + tenant-side IAM 联邦)。
**数据契约强**:方案 2(Authorized Dataset)。
**Batch / ETL**:方案 4(GCS) 或 方案 5(BQ transfer)。
**金融 / 医疗**:方案 6(VPC-SC + private endpoint)。
**不要用**:方案 3(SA key)。

| 你想要 | 走 |
|--------|----|
| "master pod 能 SELECT 几个特定字段" | 方案 1 + dataset IAM |
| "master pod 能看到聚合后的指标" | 方案 2(Authorized Dataset) |
| "dashboard 需要每日 tenant BQ 数据全量" | 方案 4(GCS)+ `bq extract` cron |
| "立即在 master BQ warehouse 里 dashboard 用" | 方案 5(BQ Transfer) |
| "tenant 数据永远不出 tenant,但 master view 能看到字段" | 方案 2 + 严格 SQL 控 SELECT 列表 |
| "VPC-SC / 网络隔离是强制要求" | 方案 6(VPC-SC + private) |

---

## 7. 决策流程图

```
      Master 项目 GKE Pod 查询 Tenant BigQuery
                       │
                       ▼
        ┌────────────────────────────────────┐
        │  GKE cluster 已启用 WI Federation? │
        └────────────────────────────────────┘
                       │
              ┌────────┴─────────┐
              │ 否                                │ 是
              ▼                                  ▼
    ┌─────────────────┐         (↓↓↓ 跳到 IAM 验证 ↓↓↓)
    │ 先开 WI           │
    │ gcloud container │
    │ clusters update  │
    │ --workload-pool  │
    └─────────────────┘
                       ▼
    ┌────────────────────────────────────────┐
    │ 阶段 A:master GKE master GSA 创建了吗? │
    └────────────────────────────────────────┘
                       │
              ┌────────┴─────────┐
              │ 否                                  │ 是
              ▼                                    ▼
       (跳过)                              (继续)
                       ▼
    ┌──────────────────────────────────────────────────────────┐
    │ 阶段 B:GSA 上绑了 Workload Identity User (KSA)?        │
    │ gcloud iam service-accounts add-iam-policy-binding       │
    │   --role=roles/iam.workloadIdentityUser                  │
    │   --member="serviceAccount:<MASTER>.svc.id.goog[NS/SA]"  │
    └──────────────────────────────────────────────────────────┘
                       │
                       ▼
    ┌──────────────────────────────────────────────────────────┐
    │ 阶段 C:tenant 项目给 GSA 数据 + job 角色?        │
    │ gcloud bigquery datasets add-iam-policy-binding          │
    │   --role=roles/bigquery.dataViewer  (再绑一次 dataEditor 按需)│
    │   --role=roles/bigquery.jobUser                          │
    │   --member="serviceAccount:<GSA_EMAIL>"                  │
    └──────────────────────────────────────────────────────────┘
                       │
                       ▼
    ┌──────────────────────────────────────────────────────────┐
    │ 阶段 D:K8s KSA annotation:                               │
    │   iam.gke.io/gcp-service-account=<GSA_EMAIL>             │
    │ namespace label:                                         │
    │   iam.gke.io/workload-identity=true                      │
    └──────────────────────────────────────────────────────────┘
                       │
                       ▼
    ┌──────────────────────────────────────────────────────────┐
    │ 阶段 E:Pod 里跑真实 query(Go / Python 客户端)            │
    │   SELECT COUNT(*) FROM `<TENANT>.<DS>.__TABLES__`        │
    │                                                           │
    │  ✅ 正常返回 → 完成                                       │
    │  ❌ 403 / Permission denied → 看 §5.6 坑 1-3              │
    │  ❌ 401 / token 报错 → 看 §5.6 坑 2                       │
    │  ❌ VPC_PERIMETER_DENIED → 看 §5.6 坑 6                   │
    └──────────────────────────────────────────────────────────┘
```

---

## 8. 验证脚本(可粘贴直接跑)

```bash
#!/usr/bin/env bash
# verify-cross-project-bq.sh
# 用法: ./verify-cross-project-bq.sh
# 依赖: gcloud (auth OK),kubectl,kube 上下文已切到 master GKE cluster,
#       jq,bq client(可选,用于 §4 验证)
set -euo pipefail

# === 必填 ===
MASTER_PROJECT="${MASTER_PROJECT:-master-project-prod}"
TENANT_PROJECT="${TENANT_PROJECT:-tenant-project-data}"
GKE_CLUSTER="${GKE_CLUSTER:-app-cluster}"
MASTER_REGION="${MASTER_REGION:-europe-west2}"
GSA_NAME="${GSA_NAME:-master-bq-reader}"
GSA_EMAIL="${GSA_NAME}@${MASTER_PROJECT}.iam.gserviceaccount.com"
K8S_NAMESPACE="${K8S_NAMESPACE:-app}"
KSA_NAME="${KSA_NAME:-app-ksa}"
BQ_DATASET="${BQ_DATASET:-analytics}"

echo "==> 1. WI Federation 启用?"
WORKLOAD_POOL=$(gcloud container clusters describe "$GKE_CLUSTER" \
  --region="$MASTER_REGION" --format="value(workloadIdentityConfig.workloadPool)")
[[ -n "$WORKLOAD_POOL" ]] \
  && echo "  ✅ workload pool: $WORKLOAD_POOL" \
  || { echo "  ❌ WI 不可用"; exit 1; }

echo "==> 2. master GSA + WI binding 存在?"
GSA_EXISTS=$(gcloud iam service-accounts describe "$GSA_EMAIL" \
  --project="$MASTER_PROJECT" 2>/dev/null && echo OK)
[[ "$GSA_EXISTS" == "OK" ]] || { echo "  ❌ GSA $GSA_EMAIL 不存在"; exit 1; }

WI_BINDING=$(gcloud iam service-accounts get-iam-policy "$GSA_EMAIL" \
  --project="$MASTER_PROJECT" --format=json | \
  jq -e --arg member "serviceAccount:${MASTER_PROJECT}.svc.id.goog[${K8S_NAMESPACE}/${KSA_NAME}]" \
    '.bindings[] | select(.role=="roles/iam.workloadIdentityUser") | .members[] | select(.==$member)')
[[ -n "$WI_BINDING" ]] \
  && echo "  ✅ KSA → GSA binding" \
  || { echo "  ❌ KSA 没绑到 GSA"; exit 1; }

echo "==> 3. tenant-side dataset IAM 给 GSA?"
DATA_ROLE=$(gcloud bigquery datasets get-iam-policy "$BQ_DATASET" \
  --project="$TENANT_PROJECT" --format=json | \
  jq -e --arg m "$GSA_EMAIL" \
    '.bindings[] | select(.role=="roles/bigquery.dataViewer") | .members[] | select(.==$m)')
[[ -n "$DATA_ROLE" ]] \
  && echo "  ✅ bigquery.dataViewer on dataset" \
  || { echo "  ❌ dataset-level dataViewer 缺失"; exit 1; }

JOB_ROLE=$(gcloud bigquery datasets get-iam-policy "$BQ_DATASET" \
  --project="$TENANT_PROJECT" --format=json | \
  jq -e --arg m "$GSA_EMAIL" \
    '.bindings[] | select(.role=="roles/bigquery.jobUser") | .members[] | select(.==$m)')
[[ -n "$JOB_ROLE" ]] \
  && echo "  ✅ bigquery.jobUser on dataset" \
  || echo "  ⚠️  bigquery.jobUser 缺失,query 跑不动但 SELECT existing table 可用"

echo "==> 4. K8s KSA annotation 存在?"
ANNO=$(kubectl get serviceaccount -n "$K8S_NAMESPACE" "$KSA_NAME" \
  -o jsonpath='{.metadata.annotations."iam\.gke\.io/gcp-service-account"}' 2>/dev/null || echo "")
[[ "$ANNO" == "$GSA_EMAIL" ]] \
  && echo "  ✅ KSA annotation → $GSA_EMAIL" \
  || { echo "  ❌ KSA annotation 是 '$ANNO',不是 '$GSA_EMAIL'"; exit 1; }

echo ""
echo "✅ 静态 IAM 链全部就绪"
echo ""
echo "==> 5. (可选) 真实 query 验证"
echo "    跑一段 Go/Python 代码或 bq 工具:"
echo "      bq query --project_id=$TENANT_PROJECT \\"
echo "        --use_legacy_sql=false \\"
echo "        'SELECT COUNT(*) FROM \`${TENANT_PROJECT}.${BQ_DATASET}.__TABLES__\`'"
```

把脚本里所有 `export` 替换为真实值,直接跑。如果 §5.6 坑 1-7 任何一个让你卡住,失败时会打在步骤 3-5。

---

## 9. 反方向:从 tenant BigQuery 反向授权 master pod(架构对称性)

> Lex 偏好"架构双方向覆盖",所以本节是 sibling section,不是正反主客换位。

### 9.1 目标

让 **tenant 的 BI / 数据团队** 反过来直接 query master 项目的 BQ 数据(假设 master 项目**最终也会**开始用 BQ)。这只在 master 项目发展出 BQ 后才有意义,目前 master 是"application layer no BQ",但**架构上要预留方向**。

### 9.2 走法对称

- 反向也走 **WI Federation** 或 **service account key / impersonation**
- **tenant 项目** 创建 GSA
- **master 项目** 大方 grant dataset IAM(`bigquery.dataViewer`)给 tenant 的 GSA
- **tenant project 里的服务或工具**(如 Looker / Dataform)用这个 GSA 直连 master BQ

```bash
# 反向场景:t GSA 在 tenant 项目,被 master dataset 接纳
TENANT_GSA="tenant-bq-reader@tenant-project-data.iam.gserviceaccount.com"
MASTER_PROJECT="master-project-prod"
MASTER_DATASET="app_event_logs"

gcloud bigquery datasets add-iam-policy-binding "$MASTER_DATASET" \
  --project="$MASTER_PROJECT" \
  --member="serviceAccount:$TENANT_GSA" \
  --role="roles/bigquery.dataViewer"
```

### 9.3 反方向跟正方向的关键差异

| 维度 | 正(master→tenant)| 反(tenant→master)|
|------|--------|--------|
| 跨项目 IAM grant 位置 | **tenant 的 dataset IAM** | **master 的 dataset IAM** |
| WI 链路在哪个项目 | master 必须开 WI Federation,t GSA 在 tenant | tenant 必须开 WI Federation(假设 tenant 有 GKE)|
| 联邦身份流向 | master→tenant | tenant→master |
| 网络防火墙 | 通常 Google 内部 RPC 直通,无问题 | 同 |
| 主要风险 | tenant 数据被 master pod 偷走 | master 的数据被 tenant BI 偷走 |

**架构原则**:**IAM 的 grant 永远在"持有数据的项目"**,不在"消费数据的项目"。本文的正方向里 IAM grant 在 tenant,反方向里 IAM grant 在 master —— **grant 跟数据的"所有者"绑死**。

---

## 10. 跨文章引用

| 主题 | 文章 |
|------|------|
| Workload Identity Federation for GKE 入门 | `../gke/workload-identify.md` |
| 跨项目 IAM / SA 调试 | `../pub-sub/cross-project-pub-sub-debug-sa.md`(同族姊妹篇:跨项目身份链路) |
| 跨项目 VPC / Network | `../cross-project/cross-domain-fqdn.md` / `cross-mig.md` |
| BigQuery 单项目实践 | `../bigquery/bigquery-base-practice.md` |
| BigQuery 单项目创建/插入 | `../bigquery/create-table-schema.md` / `bigquery-how-to-insert-update.md` |
| VPC Service Controls 跨项目 boundary | (本目录其他文档) |
| GCS 中转(BQ export 配套) | `../storage/cloud-bak.md` |
| 跨项目 cost/billing | `../cost/cross-project-public-tls-mtls-billing.md` |

---

## 11. 一句话原则

> 📌 **Cross-project BigQuery 联邦的核心不是网络,而是两条 IAM 链**
> (WI Federation auth-side + dataset IAM resource-side)。
>
> 想打通 cross-project BQ → 先验证 **GSA 是否在 data project 里被显式 grant dataset IAM**,**WI binding 在哪一项目**都无所谓。
>
> 想避免错配 → 用 §8 的 verify 脚本一次性检查 5 个静态点,
> 然后用 **真 query 在 pod 里跑** 验整个链路 token。

---

## 12. 关键 IAM 角色速查

```
roles/iam.workloadIdentityUser       ← KSA → GSA 授权(master 项目里)
roles/bigquery.dataViewer            ← BQ dataset 读
roles/bigquery.dataEditor            ← BQ dataset 写
roles/bigquery.metadataViewer        ← BQ project metadata(可选,用于列出 dataset)
roles/bigquery.jobUser               ← BQ 跑 job(发 query)
roles/bigquery.user                  ← = dataViewer + jobUser
roles/bigquery.admin                 ← 全集
roles/bigquery.datasetCreate         ← 建 dataset
roles/iam.serviceAccountTokenCreator ← KSA 拿 GSA token(impersonate)
```

**最小可用组合**:

- `iam.workloadIdentityUser` (在 GSA 上的 IAM binding)
- `bigquery.dataViewer` + `bigquery.jobUser` (在 tenant dataset 上的 IAM binding)

---

## 13. 引用来源 / 权威证据

> 本节是最终定型依据。所有"该怎么配"的语句都至少一个 Google Cloud 官方文档 anchor 支撑。

### 13.1 Workload Identity Federation for GKE

- 📘 **Google Cloud — About Workload Identity Federation for GKE**:<https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity>
  - 本文 §3.2 直接引用:
    > "The GKE metadata server intercepts the token request and asks the Kubernetes API server for a Kubernetes ServiceAccount token that identifies the requesting workload. … The GKE metadata server uses Security Token Service to exchange the JWT for a short-lived federated access token that **identifies the workload as a Google Cloud service account that the Pod is configured to impersonate**."
  - 关键 anchor 原文:
    > `principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/SERVICEACCOUNT`
  - 这是 KSA→GSA impersonate 的**主身份 form**,debug 时用 `gcloud iam service-accounts describe` 比对 PROJECT_NUMBER 经常能定位 mismatch。

### 13.2 BigQuery Access Control

- 📘 **BigQuery — Authorized datasets**:<https://cloud.google.com/bigquery/docs/authorized-datasets>
  - 核心 anchor:
    > "Authorized datasets allow you to share access to specific datasets with a view in another project. You can grant cross-project access to your dataset without sharing data-set-wide IAM permissions with the other project."
  - JSON access list 格式(§5.3 方案 2):
    ```json
    { "dataset": { "project_id": "TENANT", "dataset_id": "AUTH_DATASET" }, "target_types": "VIEWS" }
    ```
  - 命令:`bq update --source <FILE>` 把 access array patch 进 dataset metadata
- 📘 **BigQuery — Control access with IAM**:<https://cloud.google.com/bigquery/docs/access-control>
  - 关键事实:**dataset-level IAM 是必须的**,project-level 仅起辅助
  - 角色清单:`bigquery.dataViewer` / `dataEditor` / `jobUser` / `user` / `admin`

### 13.3 GSA IAM roles(for WI binding)

- 📘 **IAM — roles/iam.workloadIdentityUser**:
  - 这是绑定 GSA → KSA 的 role,只能绑在 **GSA 资源**(不是 project 上)
- 📘 **IAM — roles/iam.serviceAccountTokenCreator**:
  - For impersonation 场景,排除直接绑这个,改用 workloadIdentityUser

### 13.4 VPC Service Controls

- 📘 **VPC Service Controls**: <https://cloud.google.com/vpc-service-controls/docs/overview>
  - 本文 §5.6 坑 6 的修法依赖此文档:跨项目 access level 互表

### 13.5 BigQuery Data Transfer Service(方案 5)

- 📘 **BigQuery Data Transfer Service**:<https://cloud.google.com/bigquery/docs/dts-introduction>
  - 跨 project / cross-cloud 用的官方 batch 工具

### 13.6 与本仓库既有文档的交叉

| 本文档概念 | 既有文档 |
|------|--------|
| Workload Identity Federation | `gcp/gke/workload-identify.md`(同主题,但**未**覆盖跨项目 BQ) |
| cross-project 通用模式 | `gcp/pub-sub/cross-project-pub-sub-debug-sa.md`(cross-project 同族姊妹篇) |
| BQ 跨项目 ACL 实战 | `gcp/dashboard/report/docs/cross-pro-groq.md`(覆盖了**BQ↔BQ** join,本篇覆盖了 **GKE→BQ** 身份流,两篇互补) |

> 注:`cross-pro-groq.md` 名字里"groq"应该是 typo,但是其内容确实是 BigQuery **跨 project SQL join**(dev/prod)场景。本篇聚焦 GKE pod auth flow,两者不重叠。

---

## 14. 未验证 / 探索期假设

(以下"事实"未在这次 explore 中验证,留给你 prod 落地时独立 verify,或在第二个探索会话中专项确认)

- [ ] **Anthropic / OpenAI 风格注释**:本文写到方案的 `roles/...` 默认是 2026-07 Google IAM reference 的最新版本。建议在落地时用 `gcloud iam roles describe roles/bigquery.dataViewer` 实时确认 role permission set 没变。
- [ ] **tenant-side VPC-SC perimeter 的强制要求**:假设 tenant 项目**没开 VPC-SC**,那么本文所有 IAM grant 都生效。**如果 tenant 项目已开 VPC-SC,需要外加 perimeter access level 双向配置**(§5.6 坑 6)。
- [ ] **master 项目如果以后也开始用 BQ**:本篇只覆盖 master 是"application layer"的假设。**等 master 项目也开始用 BQ 后,反方向见 §9**,两边 IAM grant 要分别维护。
- [ ] **跨 region BQ access**:本文默认 master GKE region + tenant BQ region 同区域或可互通。**跨 region + VPC-SC + cross-region perimeter** 是另一个独立专题,需要单独 explore。
- [ ] **service-identity principal 在跨 perimeter 的形式**:claim format 跟 §13.1 引用的 `principal://iam.googleapis.com/...` 是否一致 across boundaries,需要专门 verify。
- [ ] **用 transfer service 跑 BQ Omni** 详细 SLA:本篇假设用户拥有 BQ Omni enable,具体 enable 路径未提及。

---

✅ 全文完毕。如果某个方案 §5 的命令栈跑不通 / 哪个坑 §5.6 中的"修法"没解决你问题,告诉我具体错误信息 + 你环境的 cluster GSA/dataset 配置,可以针对性 patch / 加补充章节。
