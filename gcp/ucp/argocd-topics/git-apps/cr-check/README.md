# CR Check · Go 实现

> **这是自研 GitHub App（CR Check）的可运行代码。**
>
> **需求**：部署到 **PRD 环境**的每一个 PR，必须携带一个**变更单（CR）编号**；
> 该 CR 必须在内部 **CR 管理平台**上处于**可执行（Implement / Approved）状态**；
> 且合并必须落在 **Maintenance Window（维护窗口）**内。
> 不满足 → **PR 合不了**。

---

## 0. 30 秒跑起来

```bash
cd git-apps/cr-check

# 1) 起服务（mock 模式：内置假 CR 平台 + 日志型 check writer + 同步判定）
make run
# 或：go run ./cmd/server -config config/policy.yaml -mode mock -addr :8080 -sync-eval
 go run ./cmd/server -config config/policy.yaml -mode mock -addr :8080 -sync-eval
{"time":"2026-11-07T19:46:48.179248+08:00","level":"INFO","msg":"启动 CR Check","mode":"mock","addr":":8080","check":"cr/prod-validation","managed_branches":["release/prd","release/prod"],"sync_eval":true,"github_configured":false,"cr_platform_configured":false}
{"time":"2026-11-07T19:46:48.17983+08:00","level":"INFO","msg":"mock 模式：使用内置假 CR 平台","crs":6}
{"time":"2026-11-07T19:46:48.180309+08:00","level":"INFO","msg":"定时重扫已启动","interval":300000000000}
{"time":"2026-11-07T19:46:48.180412+08:00","level":"INFO","msg":"HTTP 服务已启动","addr":":8080","index":"http://localhost:8080/"}
{"time":"2026-11-07T19:47:29.359812+08:00","level":"INFO","msg":"开始判定","pr":"acme/platform#42","base":"release/prd","sha":"a1b2c3d4e5f6789012345678901234567890abcdef","source":"webhook"}
{"time":"2026-11-07T19:47:29.359876+08:00","level":"INFO","msg":"check run written","owner":"acme","repo":"platform","sha":"a1b2c3d4e5f6789012345678901234567890abcdef","name":"cr/prod-validation","status":"in_progress","conclusion":"in_progress"}
{"time":"2026-11-07T19:47:29.359917+08:00","level":"INFO","msg":"check run written","owner":"acme","repo":"platform","sha":"a1b2c3d4e5f6789012345678901234567890abcdef","name":"cr/prod-validation","status":"completed","conclusion":"failure"}
{"time":"2026-11-07T19:47:29.359925+08:00","level":"INFO","msg":"audit","kind":"evaluation","repo":"acme/platform","pr":42,"sha":"a1b2c3d4e5f6789012345678901234567890abcdef","cr":"1234","conclusion":"failure","failed_rules":["R6w"],"system_error":false,"source":"webhook"}
{"time":"2026-11-07T19:48:14.991748+08:00","level":"INFO","msg":"开始判定","pr":"acme/platform#42","base":"release/prd","sha":"a1b2c3d4e5f6789012345678901234567890abcdef","source":"webhook"}
{"time":"2026-11-07T19:48:14.99182+08:00","level":"INFO","msg":"check run written","owner":"acme","repo":"platform","sha":"a1b2c3d4e5f6789012345678901234567890abcdef","name":"cr/prod-validation","status":"in_progress","conclusion":"in_progress"}

# 2) 另开一个终端，发一个测试请求
./scripts/send-test-event.sh

./scripts/send-test-event.sh
→ POST http://localhost:8080/github/webhook  (CR=1234, base=release/prd, delivery=demo-1234-1794052049335218000)

{
  "action": "opened",
  "base_ref": "release/prd",
  "conclusion": "failure",
  "cr_number": "1234",
  "delivery_id": "demo-1234-1794052049335218000",
  "env": "prd",
  "event": "pull_request",
  "failed_rules": [
    "R6w"
  ],
  "head_sha": "a1b2c3d4e5f6789012345678901234567890abcdef",
  "ok": false,
  "pr": 42,
  "repo": "acme/platform",
  "rules": [
    {
      "id": "R1",
      "passed": true,
      "message": "解析到变更单号：1234（来自 label:cr/1234）"
    },
    {
      "id": "R1a",
      "passed": true,
      "message": "变更单号唯一"
    },
    {
      "id": "R2",
      "passed": true,
      "message": "变更单 1234 存在"
    },
    {
      "id": "R3",
      "passed": true,
      "message": "变更单 1234 状态为 `implement`（可执行）"
    },
    {
      "id": "R4",
      "passed": true,
      "message": "审批充分：bob, carol"
    },
    {
      "id": "R5",
      "passed": true,
      "message": "目标环境匹配：`prd`"
    },
    {
      "id": "R6",
      "passed": true,
      "message": "变更单 1234 在有效期内（有效期至 2035-12-31T23:59:59+08:00）"
    },
    {
      "id": "R6w",
      "passed": false,
      "message": "当前不在维护窗口内（窗口：Mon,Tue,Wed,Thu,Fri 02:00-04:00 (Asia/Shanghai)，当前 2026-11-07 19:47:29 CST）"
    },
    {
      "id": "R7",
      "passed": true,
      "message": "变更单 1234 未被其他 PR 占用"
    }
  ],
  "status": "evaluated",
  "summary": "### ❌ 变更单校验未通过\n\n- **变更单**：`1234`\n- **目标环境**：`prd`\n- **判定时刻**：`2026-11-07T19:47:29+08:00`\n\n| 规则 | 结果 | 说明 |\n|---|---|---|\n| `R1` | ✅ | 解析到变更单号：1234（来自 label:cr/1234） |\n| `R1a` | ✅ | 变更单号唯一 |\n| `R2` | ✅ | 变更单 1234 存在 |\n| `R3` | ✅ | 变更单 1234 状态为 `implement`（可执行） |\n| `R4` | ✅ | 审批充分：bob, carol |\n| `R5` | ✅ | 目标环境匹配：`prd` |\n| `R6` | ✅ | 变更单 1234 在有效期内（有效期至 2035-12-31T23:59:59+08:00） |\n| `R6w` | ❌ | 当前不在维护窗口内（窗口：Mon,Tue,Wed,Thu,Fri 02:00-04:00 (Asia/Shanghai)，当前 2026-11-07 19:47:29 CST） |\n| `R7` | ✅ | 变更单 1234 未被其他 PR 占用 |\n\n> 本版本未实现的规则：R5b 变更内容一致性, R8 紧急通道 break-glass, R12 部署侧可追溯\n\n**请修正上述 ❌ 项后重新 push，check 会自动重跑。**\n",
  "system_error": false
}
```

期望输出（截断）：

```json
{
  "status": "evaluated",
  "conclusion": "success",
  "cr_number": "1234",
  "env": "prd",
  "failed_rules": [],
  "rules": [
    { "id": "R1",  "passed": true, "message": "解析到变更单号：1234（来自 label:cr/1234）" },
    { "id": "R1a", "passed": true, "message": "变更单号唯一" },
    { "id": "R2",  "passed": true, "message": "变更单 1234 存在" },
    { "id": "R3",  "passed": true, "message": "变更单 1234 状态为 `implement`（可执行）" },
    { "id": "R4",  "passed": true, "message": "审批充分：bob, carol" },
    { "id": "R5",  "passed": true, "message": "目标环境匹配：`prd`" },
    { "id": "R6",  "passed": true, "message": "变更单 1234 在有效期内" },
    { "id": "R6w", "passed": true, "message": "当前在维护窗口内：Mon,Tue,Wed,Thu,Fri 02:00-04:00" },
    { "id": "R7",  "passed": true, "message": "变更单 1234 未被其他 PR 占用" }
  ]
}
```

> ⚠️ **默认的真实时间是 19:xx，会被 R6w（维护窗口 02:00–04:00）拦下** —— 这是**正确行为**。
> 想看到全绿，用固定时间启动：
>
> ```bash
> go run ./cmd/server -config config/policy.yaml -mode mock -addr :8080 -sync-eval \
>   -now "2025-01-06T03:00:00+08:00"
> ```

---

## 1. 目录结构

```
cr-check/
├── cmd/server/main.go              # 入口：组装依赖、路由、优雅退出
├── internal/
│   ├── config/                     # policy.yaml 加载 + 校验 + 环境变量覆盖
│   ├── webhook/                    # ★ 入站：验签 → 幂等 → 分发 → ACK
│   │   ├── handler.go
│   │   └── signature.go
│   ├── rules/                      # ★ 判定引擎（业务核心）
│   │   ├── engine.go               #   collect-all 规则编排
│   │   ├── extract.go              #   解析唯一 CR 号
│   │   └── window.go               #   Maintenance Window 判定
│   ├── crplatform/                 # CR 管理平台客户端（HTTP + mock）
│   ├── check/                      # 写 Check Run（GitHub / 日志两种实现）
│   ├── gh/                         # installation client 工厂（ghinstallation）
│   ├── queue/                      # 幂等去重（内存 / Redis）+ 异步队列
│   ├── recheck/                    # ★ 定时重扫重评（兜底）
│   ├── audit/                      # 审计留痕
│   └── observability/              # Prometheus 指标
├── config/policy.yaml              # ★ 规则数据（改这里不用发版）
├── deploy/                         # K8s 清单（Deployment/Service/Ingress/ConfigMap/PDB）
├── testdata/pr-event.json          # 测试用的 webhook payload
├── scripts/send-test-event.sh      # 发送测试请求
├── Dockerfile
└── Makefile
```

---

## 2. 端点

| 端点 | 方法 | 用途 |
|---|---|---|
| `/github/webhook` | POST | **GitHub 事件入口** |
| `/healthz` | GET | 存活探针 |
| `/readyz` | GET | 就绪探针（含"能拿到 installation token"） |
| `/metrics` | GET | Prometheus 指标 |
| `/internal/policy` | GET | 生效配置（脱敏） |
| `/internal/last-check` | GET | 最近一次 check 写入 |
| `/internal/audit` | GET | 最近 50 条审计 |
| `/internal/registry` | GET | 已登记的受管 PR |
| `/internal/recheck` | POST | 立即触发一次定时重扫 |
| `/mock/cr/{number}` | GET | 内置假 CR 平台（仅 mock 模式） |

---

## 3. 本地验证手册

### 3.1 启动

```bash
# A. 默认（真实时间 → 会被维护窗口拦下）
make run

# B. 固定时间落在维护窗口内（推荐用于演示"全绿"）
go run ./cmd/server -config config/policy.yaml -mode mock -addr :8080 -sync-eval \
  -now "2025-01-06T03:00:00+08:00"

# C. 带 webhook secret（验证 HMAC 验签）
WEBHOOK_SECRET=topsecret go run ./cmd/server -config config/policy.yaml -mode mock \
  -addr :8080 -sync-eval -now "2025-01-06T03:00:00+08:00"
```

### 3.2 发测试请求

```bash
# 默认：CR 1234（Implement / 2 审批 / env=prd / 长期有效）→ 全绿
./scripts/send-test-event.sh 1234

# Draft 状态 → R3 + R4 不通过
./scripts/send-test-event.sh 5678

# 目标环境是 prod，但 PR 打到 prd 分支 → R5 不通过
./scripts/send-test-event.sh 1111

# 只有 1 位审批 → R4 不通过
./scripts/send-test-event.sh 2222

# 变更单已过期 → R6 不通过
./scripts/send-test-event.sh 3333

# CR 平台故障 → 系统异常 → fail-closed（结论 failure，绝不 success）
./scripts/send-test-event.sh 9999

# 非受管分支 → 直接忽略，不产生 check
./scripts/send-test-event.sh 1234 feature/x

# 带签名（服务端配了 WEBHOOK_SECRET 时）
SECRET=topsecret ./scripts/send-test-event.sh 1234
```

### 3.3 用 curl 手工构造

```bash
BODY=$(cat testdata/pr-event.json)

curl -s -X POST http://localhost:8080/github/webhook \
  -H 'X-GitHub-Event: pull_request' \
  -H "X-GitHub-Delivery: $(uuidgen)" \
  -H 'Content-Type: application/json' \
  --data-binary "$BODY" | jq
```

### 3.4 验证幂等

```bash
ID="dup-$(date +%s)"
for i in 1 2; do
  curl -s -X POST http://localhost:8080/github/webhook \
    -H 'X-GitHub-Event: pull_request' -H "X-GitHub-Delivery: $ID" \
    -H 'Content-Type: application/json' --data-binary "$BODY" | jq -r .status
done
# → evaluated
# → duplicate     ★ 同一个 delivery id 不会被处理两次
```

### 3.5 观察内部状态

```bash
curl -s http://localhost:8080/internal/last-check  | jq      # 最近一次 check 写入

➜  cr-check git:(main) ✗ curl -s http://localhost:8080/internal/last-check  | jq
{
  "ref": {
    "Owner": "acme",
    "Repo": "platform",
    "SHA": "a1b2c3d4e5f6789012345678901234567890abcdef",
    "Name": "cr/prod-validation"
  },
  "status": "completed",
  "conclusion": "failure",
  "title": "变更单校验结果",
  "summary": "### ❌ 变更单校验未通过\n\n- **变更单**：`5678`\n- **目标环境**：`prd`\n- **判定时刻**：`2026-11-07T19:49:55+08:00`\n\n| 规则 | 结果 | 说明 |\n|---|---|---|\n| `R1` | ✅ | 解析到变更单号：5678（来自 label:cr/5678） |\n| `R1a` | ✅ | 变更单号唯一 |\n| `R2` | ✅ | 变更单 5678 存在 |\n| `R3` | ❌ | 变更单 5678 当前状态为 `draft`，需要 approved / implement |\n| `R4` | ❌ | 变更单 5678 的审批人只有 1 位（bob），需要至少 2 位 |\n| `R5` | ✅ | 目标环境匹配：`prd` |\n| `R6` | ✅ | 变更单 5678 在有效期内（有效期至 2035-12-31T23:59:59+08:00） |\n| `R6w` | ❌ | 当前不在维护窗口内（窗口：Mon,Tue,Wed,Thu,Fri 02:00-04:00 (Asia/Shanghai)，当前 2026-11-07 19:49:55 CST） |\n| `R7` | ✅ | 变更单 5678 未被其他 PR 占用 |\n\n> 本版本未实现的规则：R5b 变更内容一致性, R8 紧急通道 break-glass, R12 部署侧可追溯\n\n**请修正上述 ❌ 项后重新 push，check 会自动重跑。**\n",
  "rules": [
    {
      "id": "R1",
      "passed": true,
      "message": "解析到变更单号：5678（来自 label:cr/5678）"
    },
    {
      "id": "R1a",
      "passed": true,
      "message": "变更单号唯一"
    },
    {
      "id": "R2",
      "passed": true,
      "message": "变更单 5678 存在"
    },
    {
      "id": "R3",
      "passed": false,
      "message": "变更单 5678 当前状态为 `draft`，需要 approved / implement"
    },
    {
      "id": "R4",
      "passed": false,
      "message": "变更单 5678 的审批人只有 1 位（bob），需要至少 2 位"
    },
    {
      "id": "R5",
      "passed": true,
      "message": "目标环境匹配：`prd`"
    },
    {
      "id": "R6",
      "passed": true,
      "message": "变更单 5678 在有效期内（有效期至 2035-12-31T23:59:59+08:00）"
    },
    {
      "id": "R6w",
      "passed": false,
      "message": "当前不在维护窗口内（窗口：Mon,Tue,Wed,Thu,Fri 02:00-04:00 (Asia/Shanghai)，当前 2026-11-07 19:49:55 CST）"
    },
    {
      "id": "R7",
      "passed": true,
      "message": "变更单 5678 未被其他 PR 占用"
    }
  ],
  "at": "2026-11-07T19:49:55.281192+08:00"
}

curl -s http://localhost:8080/internal/audit      | jq      # 审计流水
curl -s http://localhost:8080/internal/registry   | jq      # 已登记的受管 PR
curl -s -X POST http://localhost:8080/internal/recheck | jq  # 立即重扫
curl -s http://localhost:8080/metrics | grep cr_check        # 指标
curl -s http://localhost:8080/mock/cr/1234 | jq              # 看 mock CR 数据

➜  cr-check git:(main) ✗ curl -s http://localhost:8080/internal/last-check  | jq
{
  "ref": {
    "Owner": "acme",
    "Repo": "platform",
    "SHA": "a1b2c3d4e5f6789012345678901234567890abcdef",
    "Name": "cr/prod-validation"
  },
  "status": "completed",
  "conclusion": "failure",
  "title": "变更单校验结果",
  "summary": "### ❌ 变更单校验未通过\n\n- **变更单**：`5678`\n- **目标环境**：`prd`\n- **判定时刻**：`2026-11-07T19:49:55+08:00`\n\n| 规则 | 结果 | 说明 |\n|---|---|---|\n| `R1` | ✅ | 解析到变更单号：5678（来自 label:cr/5678） |\n| `R1a` | ✅ | 变更单号唯一 |\n| `R2` | ✅ | 变更单 5678 存在 |\n| `R3` | ❌ | 变更单 5678 当前状态为 `draft`，需要 approved / implement |\n| `R4` | ❌ | 变更单 5678 的审批人只有 1 位（bob），需要至少 2 位 |\n| `R5` | ✅ | 目标环境匹配：`prd` |\n| `R6` | ✅ | 变更单 5678 在有效期内（有效期至 2035-12-31T23:59:59+08:00） |\n| `R6w` | ❌ | 当前不在维护窗口内（窗口：Mon,Tue,Wed,Thu,Fri 02:00-04:00 (Asia/Shanghai)，当前 2026-11-07 19:49:55 CST） |\n| `R7` | ✅ | 变更单 5678 未被其他 PR 占用 |\n\n> 本版本未实现的规则：R5b 变更内容一致性, R8 紧急通道 break-glass, R12 部署侧可追溯\n\n**请修正上述 ❌ 项后重新 push，check 会自动重跑。**\n",
  "rules": [
    {
      "id": "R1",
      "passed": true,
      "message": "解析到变更单号：5678（来自 label:cr/5678）"
    },
    {
      "id": "R1a",
      "passed": true,
      "message": "变更单号唯一"
    },
    {
      "id": "R2",
      "passed": true,
      "message": "变更单 5678 存在"
    },
    {
      "id": "R3",
      "passed": false,
      "message": "变更单 5678 当前状态为 `draft`，需要 approved / implement"
    },
    {
      "id": "R4",
      "passed": false,
      "message": "变更单 5678 的审批人只有 1 位（bob），需要至少 2 位"
    },
    {
      "id": "R5",
      "passed": true,
      "message": "目标环境匹配：`prd`"
    },
    {
      "id": "R6",
      "passed": true,
      "message": "变更单 5678 在有效期内（有效期至 2035-12-31T23:59:59+08:00）"
    },
    {
      "id": "R6w",
      "passed": false,
      "message": "当前不在维护窗口内（窗口：Mon,Tue,Wed,Thu,Fri 02:00-04:00 (Asia/Shanghai)，当前 2026-11-07 19:49:55 CST）"
    },
    {
      "id": "R7",
      "passed": true,
      "message": "变更单 5678 未被其他 PR 占用"
    }
  ],
  "at": "2026-11-07T19:49:55.281192+08:00"
}
➜  cr-check git:(main) ✗ curl -s http://localhost:8080/mock/cr/1234 | jq
{
  "number": "1234",
  "status": "implement",
  "requester": "alice",
  "approvers": [
    {
      "approver": "bob",
      "decidedAt": "2026-11-07T19:46:48.179793+08:00",
      "decision": "approve"
    },
    {
      "approver": "carol",
      "decidedAt": "2026-11-07T19:46:48.179794+08:00",
      "decision": "approve"
    }
  ],
  "targetEnv": "prd",
  "validFrom": "2020-01-01T00:00:00+08:00",
  "validTo": "2035-12-31T23:59:59+08:00",
  "artifacts": null,
  "url": "https://cr.example.com/cr/1234"
}

```

---

## 4. 判定规则

| ID | 规则 | 不通过的提示 |
|---|---|---|
| **R0b** | base 分支必须命中 `managedBranches` | 非目标分支**直接忽略**（不产生 check） |
| **R1** | PR 必须携带 CR 号 | "PR 未携带变更单号（需要 label `cr/<编号>`…）" |
| **R1a** | 必须且只能有**一个** CR 号 | "解析出多个变更单号 …" / "不同载体给出了不同的变更单号 …" |
| **R2** | CR 在平台上存在 | "变更单 1234 在 CR 管理平台上不存在" |
| **R3** | CR 状态可执行（`approved` / `implement`） | "变更单 1234 当前状态为 `draft`，需要 approved / implement" |
| **R4** | 审批充分（≥N 位、非提单人、在白名单） | "审批人只有 1 位（bob），需要至少 2 位" |
| **R5** | 目标环境与分支一致 | "变更单 1111 的目标环境是 `prod`，但本 PR 的目标分支 `release/prd` 对应 `prd`" |
| **R6** | CR 有效期覆盖当前时刻 | "变更单 3333 已过期（有效期至 …）" |
| **R6w** | 当前在 Maintenance Window 内 | "当前不在维护窗口内（窗口：…）" |
| **R7** | CR 未被其他 PR 占用 | "变更单 1234 已被 acme/platform#99 占用" |

> ★ **collect-all**：一次把所有不满足的规则都列出来，而不是只报第一个。
> 开发者改完再提交又撞上下一个，体验极差。

### 4.1 两条"必须 fail-closed"的铁律

```
① CR 平台不可用（超时 / 5xx / 解析失败）→ 结论 = failure（系统异常）
   ★ 绝不写 success；也绝不写 neutral / skipped
     （GitHub 把 skipped / neutral 当作"通过" → 写了等于开门）

② CR 平台出现没映射过的状态 → 规范化成 unknown → 不在白名单 → 不通过
   ★ 未知状态永远按"不通过"处理
```

---

## 5. 配置（`config/policy.yaml`）

**分层原则**：

```
规则数据（阈值 / 名单 / 映射表 / 窗口）→ policy.yaml
    改这里走 PR + Argo CD sync，分钟级生效，不用发版

判定逻辑（怎么算"审批充分"）→ Go 代码
    改这里要 CI + 发版
```

关键项：

| 配置 | 说明 |
|---|---|
| `checkName` | **必须与分支保护里 required status check 逐字符一致** |
| `managedBranches` | 受管 basebranch（PRD 分支要在这里） |
| `branchEnvMap` | 分支 → 环境（`prd` / `prod` / `dev`） |
| `cr.allowedExecutableStatuses` | 可执行状态白名单（`approved` / `implement`） |
| `cr.statusAliases` | 平台状态字符串 → 规范化状态（**平台新增状态必须同步这里**） |
| `cr.minApprovals` | 最少审批人数 |
| `cr.allowedApprovers` | 审批人白名单（生产应换成平台的组信息） |
| `windows` | Maintenance Window（`[start, end)` 左闭右开；`start > end` = 跨零点） |
| `server.syncEval` | **生产必须 false**（先 ACK 再异步，避免超过 GitHub 的 10 秒投递预算） |
| `server.recheckIntervalSeconds` | 定时重扫间隔（兜底） |

### 5.1 环境变量覆盖（敏感项绝不进 Git）

| 变量 | 覆盖 |
|---|---|
| `WEBHOOK_SECRET` | `webhook.secret` |
| `GITHUB_APP_ID` | `github.appId` |
| `GITHUB_APP_INSTALLATION_ID` | `github.installationId` |
| `GITHUB_APP_PRIVATE_KEY_PATH` | `github.privateKeyPath` |
| `GITHUB_API_URL` | `github.apiURL`（GitHub Enterprise 用） |
| `CR_PLATFORM_URL` / `CR_PLATFORM_TOKEN` | CR 平台地址与令牌 |
| `ADDR` | 监听地址 |

---

## 6. 部署到 GKE

```bash
# 1) 静态 IP（Webhook URL 不能变）
gcloud compute addresses create cr-check-ip --region=asia-east1

# 2) 密钥 → Secret Manager → External Secrets → K8s Secret
#    （私钥、webhook secret、CR 平台 token 全部不进 Git）

# 3) Argo CD Application 指向本仓库的 deploy/ 目录
#    建议 targetRevision 用 tag 或 commit SHA（不用 main）

# 4) DNS：cr-check.example.com → 静态 IP
# 5) TLS：Google 托管证书（Certificate Manager）或 cert-manager
```

**GitHub App 后台填什么**：

| 字段 | 值 |
|---|---|
| Webhook URL | `https://cr-check.example.com/github/webhook` |
| Webhook secret | 与 K8s Secret 里的 `WEBHOOK_SECRET` 一致 |
| Permissions | `Metadata: Read` + `Pull requests: Read` + `Checks: Write`（**绝不给 `Contents: Write`**） |
| Subscribe to events | `Pull request` |
| Install → Repositories | `Only select repositories`（最小权限） |

**分支保护**：

```
required status checks = cr/prod-validation   ← 与 config.checkName 逐字符一致
来源 App = CR Check                          ← 防同名 check 伪造
```

---

## 7. 开发命令

```bash
make help        # 看所有命令
make run         # 本地起服务（mock）
make test        # 跑测试（-race + 覆盖率）
make lint        # golangci-lint
make fmt         # gofmt + goimports
make build       # 编译到 bin/
make docker      # 构建镜像
```

---

## 8. 本版本**没有**实现的

诚实列出（`Outcome.Skipped` 里也会写进 check 输出）：

| 规则 | 说明 |
|---|---|
| **R5b** 变更内容一致性 | 比对 CR 声明的 artifact 与 PR 实际改动 —— 需要 CR 平台提供"预期变更清单"字段 |
| **R8** 紧急通道 break-glass | 需要 `emergency/*` label + 事后审计流程 |
| **R12** 部署侧可追溯 | 由 commit trailer + Argo CD 侧的 PreSync Hook 完成，不在本服务内 |
| **Merge Queue** | `merge_group` 事件已订阅但未处理（成熟期再做） |
| **多 installation** | 目前只用一个 installation id（多 Org 场景要改） |
| **Redis 幂等/队列** | 代码已备好 `queue.RedisStore`，但 `main.go` 目前固定用内存实现（生产要换成 Redis） |

---

## 9. 相关文档

| 主题 | 文档 |
|---|---|
| **设计与实现评估**（包结构、接口、里程碑、工作量、风险表） | [`../13-cr-check-go-design.md`](../13-cr-check-go-design.md) |
| 自研 GitHub App 可行性评估 + 规则表 R0–R13a | [`../Develop-git-apps.md`](../Develop-git-apps.md) |
| Webhook 与后端服务（代码怎么跑起来 / Webhook URL 是什么） | [`../webhook-and-backend-service.md`](../webhook-and-backend-service.md) |
| 外部交互模型：pull → push 的契约变化 | [`../12-webhook-push-vs-pull.md`](../12-webhook-push-vs-pull.md) |
| GitHub App 概念 / 三层门禁 | [`../11-github-app-concepts.md`](../11-github-app-concepts.md) |
| 专题索引 | [`../README.md`](../README.md) |
