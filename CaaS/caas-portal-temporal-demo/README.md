# CaaS Portal Temporal Demo

> 一个**真正能跑**的最小可执行件:把 `caas-portal.md` 里那套审批流变成 `docker compose up` 起来可看的链路。
>
> **包含**: FastAPI 提交入口 → Temporal workflow 编排审批 → "K8S 端 Controller" mock(stub)接收 → 一页式 Web UI 看状态流转。
>
> **不包含**: 真实 GCP/AWS/ACK 接入(那是 CaaS Controller 的活,本 demo 只演示编排层)。
>
> 读这个 demo 前,先看 `../caas-portal.md` §二(审批流设计)。

---

## 一、 它展示了什么

```
┌─────────────────┐    POST /api/v1/requests     ┌──────────────────┐
│ Browser UI      │ ──────────────────────────► │ FastAPI (api/)   │
│ (frontend/)     │                              └──────────────────┘
│                 │                                          │
│                 │                              kick off   ▼
│                 │                              ┌────────────────────────────────────┐
│                 │                              │ Temporal workflow                  │
│                 │ ◄──── SSE status feed ───── │ (workflow/cluster_request.py)       │
│                 │                              │                                    │
└─────────────────┘                              │ 1. validate_compliance_and_cost    │
                                                │ 2. approval(team_leader)            │
                                                │ 3. approval(pm)             [prod]  │
                                                │ 4. approval(security_lead)  [pci]   │
                                                │ 5. approval(platform_sre)           │
                                                │ 6. trigger_k8s_apply               │
                                                └────────────────────────────────────┘
                                                                  │
                                                                  ▼
                                                      ┌──────────────────────────┐
                                                      │ K8S stub (k8s_stub/)     │
                                                      │ - POST /apply endpoint   │
                                                      │ - record 请求 + 状态      │
                                                      │ - 模拟 Terraform 长时间   │
                                                      └──────────────────────────┘
```

对应到 `caas-portal.md` §二 那张 sequenceDiagram,**本 demo 是它的一个真实可跑实现(把人工审批替换为"直接点头"的 webhook 模拟)**。

---

## 二、目录结构

```
caas-portal-temporal-demo/
├── README.md                ← 你正在读
├── pyproject.toml           ← pip install -e . 装依赖
├── docker-compose.yml       ← 一键起:Temporal + FastAPI + Stub + Worker + Postgres
├── .env.example             ← 环境变量模板
├── api/                     ← FastAPI 后端
│   ├── main.py              ← /api/v1/requests, /api/v1/requests/{id}, /status/{id}
│   ├── models.py            ← Pydantic ClusterRequestSpec
│   └── sse.py               ← Server-Sent Events 状态流
├── workflow/                ← Temporal workflow + worker
│   ├── cluster_request.py   ← 审批流状态机
│   ├── activities.py        ← 调用 K8S stub、validate 等
│   └── worker.py            ← Temporal worker 入口
├── k8s_stub/                ← 模拟 CaaS Controller(纯 FastAPI 子服务)
│   └── main.py              ← /apply /status /delete 三个端点
├── frontend/                ← 极简 HTML + JS(不引入框架)
│   └── index.html           ← 表单 + 状态可视化
├── tests/
│   └── test_workflow.py     ← 用 Temporal 的 testing harness 跑状态机
└── docs/
    └── walkthrough.md       ← 端到端走一遍:从启动到看到集群 Ready
```

---

## 三、5 分钟跑通

```bash
cd caas-portal-temporal-demo
cp .env.example .env

# 启动全部 4 个服务(Temporal 后端 + Postgres + FastAPI + Worker + K8S stub + nginx)
docker compose up -d --build

# 打开浏览器
open http://localhost:8080

# 浏览器里填表单,提交。SSE 会推送状态变化。
# 看到 "Ready" 表示完整链路跑通。
```

> **不在 docker 里怎么办**(本地 macOS 用户):
> ```bash
> python -m venv .venv && source .venv/bin/activate
> pip install -e .
> # 启动顺序:
> #   1) docker compose up postgres temporal temporal-ui -d
> #   2) uvicorn api.main:app --reload --port 8000
> #   3) python workflow/worker.py
> #   4) uvicorn k8s_stub.main:app --reload --port 8010
> #   5) cd frontend && python -m http.server 8080
> ```

---

## 四、 配置项(`.env`)

| 变量                            | 默认                 | 含义                                       |
| ----------------------------- | ------------------ | ---------------------------------------- |
| `TEMPORAL_ADDRESS`            | `temporal:7233`    | Temporal gRPC endpoint                   |
| `TEMPORAL_NAMESPACE`          | `default`          | Temporal namespace                       |
| `K8S_STUB_URL`                | `http://k8s_stub:8010` | demo 内置 K8S stub 地址                |
| `API_PORT`                    | `8000`             | FastAPI 端口                              |
| `WORKER_PORT`                 | `8001`             | Temporal worker 健康检查端口                  |
| `ENABLE_AUTO_APPROVAL`        | `true`             | demo 模式:跳过真人审批,自动点头(可一眼看完整链路) |
| `APPROVAL_DELAY_SECONDS`      | `1.5`              | 模拟真人审批等待时间(实演示可以调短)         |

---

## 五、限速说明

- 这是**演示编排层**,不是真实 CaaS Controller。
- 真实 CaaS 需要你把 `k8s_stub` 替换为真实 GKE/EKS/ACK Adapter(`caas-providers.md` §三)
- 真实审批要走 IM(飞书/Slack)而非 API 自动点头,见 `caas-portal.md` §二

---

## 六、扩展方向(下一步可接)

| 已有 stub       | 接真实世界的步骤                                                          |
| -------------- | -------------------------------------------------------------- |
| K8S stub       | 把 `/apply` 端点内部实现换为 Terraform / Cluster API(参见 `caas-cluster-api.md`) |
| 审批 workflow   | 在每个 `request_human_approval` Activity 里对接飞书/Slack webhook,真实拉人审批 |
| 状态可视化         | 接 React/Vue 框架;接 Portal 登录(OIDC)                              |
| FinOps 估算      | 在 validate_compliance_and_cost 活动里加 cost estimator(见 `caas-finops.md` §五) |
