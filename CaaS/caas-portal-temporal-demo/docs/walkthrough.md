# 端到端走一遍(从 docker compose up 到看见集群 Ready)

> 目的是:让你 5 分钟内真正验证 CaaS Portal 编排层跑通。
> 读完这个你能验证:`caas-portal.md` §二 那张 sequenceDiagram 的"提交 → 审批 → K8S 创建 → 合规基线注入 → Ready"全链路。

---

## 步骤 1 — 启

```bash
cd /Users/lex/git/gcp/CaaS/caas-portal-temporal-demo

cp .env.example .env

docker compose up -d --build
```

等约 30 秒让 Temporal 启动(它要先 schema migration)。

```bash
docker compose ps
# 应该看到 7 个服务都 Up:
#   postgres   Up
#   temporal   Up (healthy)
#   temporal-ui   Up
#   api        Up
#   worker     Up
#   k8s_stub   Up
#   nginx      Up
```

---

## 步骤 2 — 验证 Temporal 在工作

打开 `http://localhost:8081` (Temporal UI),你应该看到一个"temporal" namespace,目前没有 workflows。无所谓。

打开 `http://localhost:8080` (CaaS Portal 前端),你应该看到一个 dark-themed 表单 + 右侧"Live status" 显示"No request submitted yet."

---

## 步骤 3 — 提交第一个 ClusterRequest

表单默认值就是合法的:

- name: `bbuk-team-a-prod`
- cloudProvider: `gcp`
- region: `asia-east1`
- tier: `standard` (⚠️ C3 修复后已锁定,UI 上不可选)
- environment: `prod`
- versionStrategy: channel `STABLE` / eolNoticeDays `60`(C9 修复)
- network: `private`
- frameworks: 默认勾了 `baseline` (不能取消,这是硬约束)
- teams: `team-a,team-b`

点 **Submit ClusterRequest**。

你应该立刻看到:
1. 右上角浮出绿色提示 "Workflow started: caas-bbuk-team-a-prod-xxxxxx, Estimated monthly cost: $...".
2. 右侧状态条从 `pending` 开始逐一推进。
3. 浏览器会同时打开 SSE 流,每状态变化都实时推送。

---

## 步骤 4 — 看 Temporal 视角

点回 `http://localhost:8081`,刷新。你会看到 `ClusterRequestWorkflow` 跑着,events timeline 显示:

- `WorkflowExecutionStarted`
- 连续一串 `ActivityTaskScheduled` / `ActivityTaskCompleted`(validate, request_approval × 3, apply_to_k8s_stub, apply_policy_baseline)
- `WorkflowExecutionCompleted`

---

## 步骤 5 — 等它跑完

每个 stage 跑的实际耗时:

| Stage                            | 实耗时      |
| -------------------------------- | -------- |
| 校验                              | 0.5s     |
| team_leader 审批(auto)            | 1.5s     |
| (pm 跳过,以为 demo 没暴露 tier)     | 0s       |
| (security 跳过,无 pci-dss)      | 0s       |
| platform_sre 审批(auto)          | 1.5s     |
| K8S stub 模拟 Terraform         | 3-6s     |
| 政策基线注入                          | 1s       |
| **总耗时**                         | **~10s** |

最后你会看到右侧状态条全部变绿,出现绿色 banner:"Cluster is **Ready**"。整个 workflow 时长 ~10s。

---

## 步骤 6 — 在 K8S stub 看到"集群"

```bash
# 拿状态(还能查到 cluster_id)
curl -s http://localhost:8000/api/v1/requests/bbuk-team-a-prod/status | jq .

# 看到 cluster_id 之后去看 K8S stub 内部状态
curl -s http://localhost:8010/status/caas-gcp-asia-east1-xxxxxxxx | jq .
```

---

## 步骤 7 — 试试失败路径

**a) 提交一个校验就会失败的请求**(production + EOL 紧急 exclusion,2026-10-05 C9 修复后):

> ⚠️ **本节原为"Autopilot + public 网络"**。C3 修复后 `tier` 已锁死 `standard`,
> Autopilot 相关校验全部不可达 —— 原例程已失效。
> 现改为演示 **C9 的生产侧规则**(这条在 Standard 下依然成立):

- name: `bbuk-team-a-bad`
- environment: `prod`
- version_strategy.allow_eol_emergency_exclusion: `true`

提交,观察:`VALIDATING` 直接变 `failed`。这是 C9 CEL 规则的实战验证
(参考 `gke-caas.md` CRD 的 `x-kubernetes-validations`)。

> **想验证原 Autopilot 规则?** 已不能 —— 这正是 C3 修复想要的效果。
> 见 `tests/test_models.py::test_clusterrequest_spec_rejects_autopilot`:
> autopilot 现在在模型层就被拒绝,进不到 workflow。

**b) 在 K8S stub 侧模拟失败**:

```bash
# 改 .env 设失败率 100%,重启 k8s_stub
echo "K8S_STUB_FAILURE_RATE=1.0" >> .env
docker compose restart k8s_stub

# 再提交一个 name=bbuk-team-a-bad-cluster 的请求
# 等到 K8S_PROVISIONING 阶段会变 failed,workflow 状态变 failed
```

---

## 步骤 8 — 试试 PCI 路径(触发现实中 Security lead 介入)

回到前端表单:
- 勾上 `pci-dss` framework
- 其它保持默认

提交。你会看到 **多了 `approval_security_lead` 这一节**,前台看是绿色(因为 demo 自动点头),**实际上这里就是 `caas-portal.md` §二 那个表格里"P1 业务线 - Security lead 介入"的真实位置**。

---

## 步骤 9 — 让它变"真实可生产"的差别

如果你想接真实 IM 审批(而不是自动点头):

1. 把 `.env` 里 `ENABLE_AUTO_APPROVAL=false`
2. 重启 worker: `docker compose restart worker`
3. 现在每次 `request_human_approval` 会卡住等待
4. 实现 `<pending_message>` + `signal("manual_decision")` —— 飞书/Slack webhook 收到用户的 approve/reject 后调用 `POST /api/v1/approvals/{name}/{stage}` 把信号送回去

具体代码改动位置在 `workflow/cluster_request.py` §"Manual decision signal" 注释里(目前是简化版,生产需要补 Signal 方法)。

---

## 步骤 10 — 把它替换为真实 CaaS Controller

把 `k8s_stub` 换为真实云接入:

| 当前 stub / Activity                       | 接真实世界                                |
| ---------------------------------------- | ----------------------------------- |
| `apply_to_k8s_stub` → POST `/apply`     | 调 Terraform Apply / CAPI Apply       |
| `_APPLIES` 内存字典                         | K8S 中真实 `ClusterRequest` CRD(`gke-caas.md`) |
| `request_human_approval` (demo 自动点头)   | 飞书/Slack webhook + 真人点同意        |
| `apply_policy_baseline` (sleep 1s)       | 调 ClusterResourceSet / Kyverno API |

每次替换都只动一个文件,workflow 不动 —— 这是编排层不动 I/O 的典型好处(参见 `caas-portal.md` §二)。
