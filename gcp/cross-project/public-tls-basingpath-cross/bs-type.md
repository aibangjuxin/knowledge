# GCP Backend Service 类型支持报告

> **文档目的**: 配合 `to.md §原地迁移详细实施` + `verify-backend-service-type.sh`,固化现网所有
> Backend Service (BS) 的 `loadBalancingScheme` 类型认知,并明确每种类型对 **PSC NEG** 接入的
> 支持情况。
>
> **权威来源**: <https://docs.cloud.google.com/load-balancing/docs/backend-service>
> (2026-08-09 抓取验证)。
>
> **配套脚本**:
> - `verify-backend-service-type.sh` — 一键扫现网所有 BS 类型 + PSC 兼容性
> - `verify-glb-type.sh` — 同目录的 Forwarding Rule (FR) 视角对应物
>
> **关联文档**: `to.md` §原地迁移详细实施、§方案 A (官方原地迁移)、§方案 B (MIG 反代桥接)

---

## 1. 一句话结论

**GCP Backend Service 的 `loadBalancingScheme` 一共只有 6 种合法取值**。**判定能否挂 PSC NEG 的
唯一公式**:

```
能否直挂 PSC NEG = scheme ∈ { EXTERNAL_MANAGED, INTERNAL_MANAGED }
```

只有这两个 scheme 的 BS 是 **Envoy 数据面** 的代理型 LB,符合 PSC NEG 的后端要求。其他 4 种
(`EXTERNAL` / `EXTERNAL_PASSTHROUGH` / `INTERNAL` / `INTERNAL_SELF_MANAGED`) 在该维度上是
**死路** 或 **不适用**,要走 `to.md §原地迁移详细实施` 才能过渡到 PSC-friendly 体系。

---

## 2. 6 种 scheme 完整对照表

| `loadBalancingScheme` | 对应的 Load Balancer (官方表) | 数据面 | PSC NEG? | 必须做什么 |
|---|---|---|:---:|---|
| **`EXTERNAL_MANAGED`** | • Global external Application Load Balancer<br>• Regional external Application Load Balancer<br>• Cross-region internal Application Load Balancer<br>• Classic proxy Network Load Balancer<br>• Regional external proxy Network Load Balancer<br>• Regional internal proxy Network Load Balancer | Envoy (GFE+Envoy) | ✅ 可挂 | 直接 `add-backend --network-endpoint-group=<PSC_NEG>` |
| **`EXTERNAL`** | • Classic Application Load Balancer (TCP/UDP/HTTPS/HTTP2)<br>• Classic proxy Network Load Balancer (TCP/UDP)<br>• Internal passthrough Network Load Balancer (TCP/UDP) | 旧 GFE | ❌ 不支持 | **走 `to.md §原地迁移详细实施 §1` 6 阶段状态机**:<br>PREPARE → TEST_BY_PERCENTAGE → TEST_ALL_TRAFFIC → EXTERNAL_MANAGED |
| **`EXTERNAL_PASSTHROUGH`** | • Regional external passthrough Network Load Balancer | passthrough (无 BS) | ❌ 不适用 | 不需要迁移 — 它本就没有 BS 概念,后端通过 **target pool** 直接挂 VM |
| **`INTERNAL_MANAGED`** | • Regional internal Application Load Balancer<br>• Global external proxy Network Load Balancer<br>• Cross-region internal proxy Network Load Balancer<br>• Global external passthrough Network Load Balancer | Envoy | ✅ 可挂 (内部) | 同上,只能服务 VPC 内部流量 |
| **`INTERNAL`** | • Cloud Service Mesh (注意:不是 Classic Internal LB) | xDS / Envoy sidecar | ❌ 不适用 | 这是 **服务网格** 专用,BS 跟 PSC NEG 是两条不同的流量路径 |
| **`INTERNAL_SELF_MANAGED`** | • 不在 GCP 官方公开表里 (罕见,常见于 self-managed 部署) | — | ⚠ 不确定 | 人工确认 (基本遇不到) |

> 📌 **关键发现**: 我之前自己写的脚本 `verify-backend-service-type.sh` 第一版漏了
> `EXTERNAL_PASSTHROUGH`,并把 `INTERNAL` 错标成 "Classic Internal LB" — 这是错的。
> 本报告以官方表为准重新分类,脚本同步已 patch 修正。

---

## 3. 协议 (`protocol`) 与 scheme 的绑定关系

BS 的 `protocol` 不是随便填的,它跟 `loadBalancingScheme` **强绑定**,下面是从同份官方文档
整理的合法组合:

| scheme | 合法 protocol |
|---|---|
| `EXTERNAL_MANAGED` | `HTTP`, `HTTPS`, `HTTP2`, `TCP`, `SSL`, `UDP` |
| `EXTERNAL` (Classic) | `HTTP`, `HTTPS`, `HTTP2`, `TCP`, `SSL`, `UDP` (注意:Classic 不允许 `HTTP2` 单独走,通常归 `HTTPS`) |
| `INTERNAL_MANAGED` | `HTTP`, `HTTPS`, `HTTP2`, `TCP`, `SSL`, `UDP` |
| `INTERNAL` (Service Mesh) | `HTTP`, `HTTPS`, `HTTP2`, `TCP`, `SSL`, `gRPC` |
| `EXTERNAL_PASSTHROUGH` | 不适用 (无 BS) |
| `INTERNAL_SELF_MANAGED` | 不在官方表里 |

**实战意义**: 看到 BS 的 `protocol=TCP/UDP` + `scheme=EXTERNAL` 时,基本可以判定是 **Classic
proxy Network LB** (不是 Application LB) — 这个区分决定了它走的 LB 类型,但 **PSC NEG
兼容性结论不变**: ❌ 都要先做原地迁移。

---

## 4. 关键官方原话 — BS ↔ FR 的 scheme 兼容矩阵

**这是 GCP 官方文档 "Restrictions and guidance" 段的第 4 条原话 (直接引用)**:

> **"It is possible to attach `EXTERNAL_MANAGED` backend services to `EXTERNAL` forwarding
> rules. However, `EXTERNAL` backend services cannot be attached to `EXTERNAL_MANAGED`
> forwarding rules."**
>
> — <https://docs.cloud.google.com/load-balancing/docs/backend-service>

中文翻译:

> "可以把 `EXTERNAL_MANAGED` backend service 挂到 `EXTERNAL` forwarding rule 上;
> 但是反过来,`EXTERNAL` backend service 不能挂到 `EXTERNAL_MANAGED` forwarding rule 上。"

**实操含义** (用 ASCII 矩阵表达):

```
                  FR scheme
                EXTERNAL   EXTERNAL_MANAGED
              +----------+------------------+
   EXTERNAL   |    ✅ OK  |    ❌ 不允许       |
BS scheme     +----------+------------------+
   EXTERNAL   |  (Classic | (Classic BS 不能挂 |
   _MANAGED   |   BS 挂到 |  到 GEML FR 上)   |
              |   Classic +------------------+
              |   FR 可行)
```

**对 `to.md §方案 B` 的影响 (重要校正!)**:

我之前在 `to.md` §方案 B 里写的 "**Classic ALB 不能挂 EXTERNAL_MANAGED BS**" 是错的 —
按官方原话 **可以挂**。但**对 PSC NEG 没帮助**,因为 PSC NEG 不只要 BS 是
`EXTERNAL_MANAGED`,还要求关联的 **FR** 也是 `EXTERNAL_MANAGED` (否则 PSC NEG 添加时会
被 GCP 拒)。

所以 `to.md §方案 B` 的核心结论 "**给 apiname3 加反代 MIG + IG backend,挂在 Classic ALB 的
URL Map 上**" 这个方案仍然是**正确的工程答案** (因为我们要的是把 apiname3 走 PSC 跨 project,
Classic ALB 不能直接挂 PSC NEG),只是 **论证里的细节有错**:
- ❌ 之前说法: "BS 跟 FR 的 scheme 必须完全一致" — 错,EXTERNAL_MANAGED BS 可以挂 EXTERNAL FR
- ✅ 正确说法: "**PSC NEG 限定只能挂在 EXTERNAL_MANAGED/INTERNAL_MANAGED BS 上,而且这些
  BS 关联的 FR 也必须是同种 _MANAGED scheme**"

---

## 5. PSC NEG 兼容性 — 决定性判别

### 5.1 一级判别: BS 自己的 scheme

| BS scheme | PSC NEG 能否挂 | 原因 (官方) |
|---|:---:|---|
| `EXTERNAL_MANAGED` | ✅ | Envoy 数据面,所有 NEG 类型都支持 (官方表) |
| `INTERNAL_MANAGED` | ✅ | Envoy 数据面,所有 NEG 类型都支持 (官方表) |
| `EXTERNAL` | ❌ | Classic GFE,不支持 NEG (官方表) |
| `EXTERNAL_PASSTHROUGH` | ❌ | Passthrough NLB 无 BS 概念 |
| `INTERNAL` (Service Mesh) | ❌ | 服务网格有自己的 sidecar 模型,不走 NEG |
| `INTERNAL_SELF_MANAGED` | ⚠ | 罕见,基本不会遇到 |

### 5.2 二级判别 (如果 BS scheme ✅): FR scheme 是否也是 _MANAGED

| BS scheme | FR scheme | PSC NEG 最终能否挂 |
|---|---|:---:|
| `EXTERNAL_MANAGED` | `EXTERNAL_MANAGED` | ✅ |
| `EXTERNAL_MANAGED` | `EXTERNAL` | ❌ (BS 是 Envoy 但 FR 是 Classic,挂 PSC NEG 会被拒) |
| `INTERNAL_MANAGED` | `INTERNAL_MANAGED` | ✅ |
| 其他组合 | — | ❌ |

**这就是为什么 `to.md §原地迁移详细实施` 强调"必须 BS 和 FR 一起迁",并且顺序固定为
"先 BS,后 FR"** — 因为只有 FR 也是 _MANAGED 时,挂在 BS 上的 PSC NEG 才真正能跑通。

---

## 6. 与 `to.md` 三方案的对照

| 方案 | 期望终态 (BS scheme) | 需要做什么 |
|---|---|---|
| **方案 A — 原地迁移** | `EXTERNAL_MANAGED` (所有 BS 全部迁移完后) | 按 `to.md §原地迁移详细实施 §1` 走 6 阶段状态机,然后再切 FR scheme。**结果**: apiname3 可以直接挂 PSC NEG |
| **方案 B — MIG 反代桥接** | `EXTERNAL` (BS 仍是 Classic,符合当前 chain) | 走 `to.md §方案 B 详细实施`,新 BS `bs-caep-apiname3` 的 scheme 仍是 `EXTERNAL`,挂的不是 PSC NEG 而是 IG backend (反代 MIG),由反代 MIG → PSC Endpoint IP 跨 project。**结果**: 绕开 BS scheme 限制,Classic ALB 不动 |
| **方案 C — 新建独立 GEML LB** (不推荐) | `EXTERNAL_MANAGED` | 新 LB + 新 IP + DNS 改 A-record。**结果**: 跟 Lex 的硬约束 "DNS A-record 不能改" 冲突 |

---

## 7. 验证脚本使用指南

`verify-backend-service-type.sh` 已经按本报告修正后的 6 种 scheme 完整覆盖。

### 7.1 人读输出 (默认)

```bash
bash verify-backend-service-type.sh
```

输出形如:

```
════════════════════════════════════════════════════════════════════
 Backend Service type verification for project: <PROJECT>
════════════════════════════════════════════════════════════════════

Backend Services:

  name           scope     protocol  scheme              BS class                       PSC verdict
  bs-caep-...    GLOBAL    HTTPS     EXTERNAL_MANAGED    A: Global external ALB / proxy NLB   ✅ PSC NEG (public)
  bs-caep-...    GLOBAL    HTTP      EXTERNAL            G-ALB: Classic Application LB         ❌ DEAD END — migrate
  ...

════════════════════════════════════════════════════════════════════
 VERDICT for project: <PROJECT>
════════════════════════════════════════════════════════════════════

  Total BS:        N
  Managed (✅):    M  ...
  Classic (❌):    K  ...
  Other   (⚠):     O  ...

❌ CRITICAL: Found Classic Backend Service(s) — PSC NEG NOT SUPPORTED
...
```

### 7.2 退出码语义 (CI / 脚本消费用)

| Exit | 含义 | 下一步 |
|:---:|---|---|
| 0 | 所有 BS 都是 PSC-compatible (`EXTERNAL_MANAGED` / `INTERNAL_MANAGED`) | 直接走 PSC NEG 接入 |
| 1 | 找到 `EXTERNAL` (Classic) BS — PSC NEG 不可行 | 走 `to.md §原地迁移详细实施 §1` |
| 2 | Managed + Classic 混存 — 需人工判断哪条 chain 没迁完 | grep URL Map 定位 |
| 3 | 未找到 BS,或只有 non-PSC-compatible (Internal / Passthrough / Service Mesh) | 检查 project / LB 配置 |
| 4 | 环境问题 (没装 gcloud / jq / token 过期) | 按提示修环境 |

### 7.3 JSON 模式 (给其他脚本消费)

```bash
bash verify-backend-service-type.sh --json | jq '{
  psc_ready: [.backend_services[] | select(.psc_compatibility | startswith("✅"))] | length,
  classic: [.backend_services[] | select(.scheme == "EXTERNAL")] | length,
  names: [.backend_services[].name]
}'
```

返回结构:

```json
{
  "project": "<PROJECT>",
  "timestamp": "2026-08-09T...",
  "total": N,
  "psc_ready_count": M,
  "classic_count": K,
  "other_count": O,
  "backend_services": [
    {
      "name": "bs-...",
      "scope": "GLOBAL|REGIONAL",
      "scheme": "EXTERNAL_MANAGED|EXTERNAL|...",
      "protocol": "HTTPS|HTTP|TCP|...",
      "bs_class": "A: Global external ALB / proxy NLB | ...",
      "psc_compatibility": "✅ PSC NEG supported (public, requires EXTERNAL_MANAGED FR) | ❌ DEAD END ..."
    },
    ...
  ]
}
```

---

## 8. 权威证据 / 最终定型依据

| 来源 | 类型 | 关键引用 |
|---|---|---|
| <https://docs.cloud.google.com/load-balancing/docs/backend-service> | GCP 官方文档 | "Backend service specifications" 表 — 6 种 scheme × 对应 LB 的完整矩阵 |
| 同上 | GCP 官方文档 (Restrictions and guidance §4) | "It is possible to attach EXTERNAL_MANAGED backend services to EXTERNAL forwarding rules. However, EXTERNAL backend services cannot be attached to EXTERNAL_MANAGED forwarding rules." |
| `to.md` §原地迁移详细实施 §1 | 本仓库现有文档 | 6 阶段状态机: PREPARE → TEST_BY_PERCENTAGE → TEST_ALL_TRAFFIC → EXTERNAL_MANAGED,BS 逐个迁移,最后切 FR |
| `verify-glb-type.sh` | 同目录现成脚本 | FR 视角的类型验证 — 跟本脚本配对使用 |
| `verify-backend-service-type.sh` | 本报告配套脚本 (已修正) | BS 视角的类型验证,覆盖本报告全部 6 种 scheme |

---

## 9. 修订历史

| 日期 | 修订人 | 修订内容 |
|---|---|---|
| 2026-08-09 | agent (init) | 初版。从官方文档抓取并整理 6 种 scheme 的完整对照 + PSC NEG 兼容性矩阵;修正 `verify-backend-service-type.sh` 第一版的 2 处错误 (漏 `EXTERNAL_PASSTHROUGH`、`INTERNAL` 错标 Classic Internal LB);校正 `to.md §方案 B` 论证里 "BS 跟 FR scheme 必须完全一致" 的认知错误 |