# jev-egress-explorer.md — 用 Jev (TypeSafe System One) 做 Public Egress 策略判定

> **作者**: architect-gcp Bot
> **日期**: 2026-10-02
> **配对图**: [`case-lex-public-egress.html`](./case-lex-public-egress.html) — case-lex 双轨 Egress 治理架构
> **上游依据**: [`base-lex-ServiceEntry.md`](./base-lex-ServiceEntry.md) — ServiceEntry + 双轨 Egress 治理(v2)
> **TypeSafe 依据**: [docs.typesafe.ai](https://docs.typesafe.ai/llms.txt) — System One / Jev / Choice / Score / Noul
> **定位**: 探索文档 + 可执行 payload 设计。**未部署,未调用过 API**(见 §10 局限声明)

---

## 0. TL;DR

### 0.1 一句话结论

> **Jev explorer 不生成配置,它只做一件代码做不了的事:判定一行日志里的那个域名,
> 属于哪条政策轨道、需不需要开口、开多大口子。**
> 判定结果落到 YAML 的活儿,仍然由确定性代码做。

### 0.2 核心判断(4 条)

**1. 这个场景有真实的语义缺口,不是硬套 AI。**
`base-lex-ServiceEntry.md` §6.3.1 明确指出:白名单起点应该是"从现有 GKE Squid
`access.log` 统计真实被访问的域名"。但统计出来的是 `CONNECT login.microsoftonline.com:443`
这样的行 —— **"这个域名要不要进白名单" 是个语义判断**(是 M365 认证?是 CDN 埋点?是
失控子域?),`awk | sort | uniq` 做不了。这是 programmable common sense 的典型位置。

**2. 绝大多数判定其实不需要模型。**
NP-3 的 CIDR 语义是**纯计算**,本机 `ipaddress` 实算即可(§3.1)。
把这类计算塞进模型,是把可靠的代码换成概率输出 —— **方向反了**。
正确形态是:**代码先筛掉能算的,只把剩下的语义模糊项送进 Jev**。

**3. 六个问题一次问完,不要串行。**
System One 的问题**互相独立、并行求值、看不见彼此的答案**(docs: "Questions are
evaluated independently and in parallel. One primitive's result does not become hidden
context that changes another primitive's result.")。所以六个判据应该一次 `system_one()`
调用发出,而不是"先判定轨道,再判定要不要开口"的六次往返。

**4. 最贵的一个问题,也是最不该由它决定的一个:绕行风险。**
`bypasses_waypoint` / `bypass_susceptibility` 判的是**配置**而不是文本语义。
它们的价值是**在 CI 里当回归闸门**(把 `base-lex-ServiceEntry.md` §11.3 第 6 步
"waypoint 挂掉时不应静默放行"那条安全断言自动化),**不是**在生产里当运行时判据。
见 §8.2。

### 0.3 成本量级(按 docs 的 $42/Mtok input,output 免费)

| 场景 | 调用数 | input token | 成本 | 1200 rpm 下最短耗时 |
|---|---|---|---|---|
| 单域名判定(1 domain,6 问题) | 1 | ~1,400 | **$0.000059** | 瞬时 |
| 单域名日常复评(每天 1 次,30 天) | 30 | ~42,000 | **$0.0018** | — |
| 全量 300 域名(flat) | 300 | ~420,000 | **$0.018** | ~15 s(串行) |
| 全量 3,000 域名(flat) | 3,000 | ~4,200,000 | **$0.176** | ~150 s |
| **CI 闸门(每次 PR,完整 state)** | 1 | ~2,600 | **$0.00011** | 瞬时 |

> ⚠️ 上表 token 数是**按 payload 结构估算的**(state ~520 + questions ~880,
> 单问题 CI 版 state ~1,400 + questions ~2,600),**不是实测**。见 §10.2。
> 结论对 3–4 倍的估算误差不敏感 —— 成本本身不是这个方案的约束点。

---

## 1. 为什么这个场景需要一个 Jev explorer

### 1.1 从架构图读出的判定缺口

配对图里轨道 B 的完整链路是:

```
业务 Pod ─①出向 TCP→ 节点 ztunnel ─④HBONE:15008→ Egress Waypoint ─⑤公网:443→ 公网 SaaS
                    │                      │
                    └③轨道A直通L3→ GCP 路由引擎  └ L7 判定 ← AuthorizationPolicy(ns + hosts)
                                             ← use-waypoint ← ServiceEntry(单域名白名单)
```

图里 **AuthorizationPolicy 那条虚线标的是「L7 判定」,绑的是 `to.operation.hosts`**。
`hosts` 列表里每一个域名,都必须有人回答:**"这个域名该进来吗?"**

- 轨道 A 的答案在 `base-lex-ServiceEntry.md` §2.1 已经确定:"能 L3 走通就默认不控"。
- 轨道 B 的答案**目前是空的** —— 图上 `ServiceEntry / 单域名白名单` 是一个组件,
  不是一份清单。§11.1 的文件清单里写的是 `11-serviceentry-microsoft-login.yaml`:
  **一个域名,猜的**。

> **Jev explorer 要补的就是这个空**:把 §6.3.1 方法 2 那条命令吐出的行,
> 变成一份有依据、可复现、可审计的 `hosts` 清单。

### 1.2 这个判断的输入长什么样

现有 GKE Squid 的 access.log(`base-lex-ServiceEntry.md` §2.2.1 第 3 步):

```
CONNECT login.microsoftonline.com:443 200 2913 TCP_MISS/200 0.001 1234 1234 - CONNECT/200 -
```

这一行里:

| 字段 | 代码能判吗 | Jev 能判吗 |
|---|---|---|
| `CONNECT` / 端口 `443` | ✅ 正则 | — |
| 目标域名 | ✅ 正则 | — |
| **这域名是不是 M365 认证必需项?** | ❌ | ✅ |
| **这是 CDN 埋点 / 遥测 / 广告,还是业务依赖?** | ❌ | ✅ |
| **该走 `*.microsoftonline.com` 还是精确单域名?** | ❌ 部分 | ✅ |
| **这域名该放行还是拒绝?** | ❌ | ✅ |
| 目标 IP 落不落在 128/2 | ✅ `ipaddress` 实算 | — |

> 右下角那一行留给代码。**这是 §3 存在的全部理由。**

### 1.3 三个不该交给 Jev 的判断(先说清楚,后面反复用)

| # | 事情 | 为什么不该给 Jev |
|---|---|---|
| ① | CIDR 包含 / 排除计算 | 纯确定性算术,`ipaddress` 库已实算;模型只会引入概率误差 |
| ② | 5 条硬约束(见 §8.1) | 来自 Istio 能力边界文档,是**事实**不是判断;模型不知道你们跑 1.30.3 |
| ③ | YAML 生成与 apply | 副作用和执行留在代码 —— docs: "Keep control flow, deterministic rules, and side effects in code." |

---

## 2. 配对图的反向覆盖 —— 判定记录落在哪里

按"覆盖双向"的要求,正向链路之外必须回答:**这条白名单是谁批准���的?**

```
Squid access.log ─┐
ztunnel 审计日志  ─┼→ Jev 六问 ─→ 判定记录(append-only)─┬→ 人工复核队列
Istio 现状 dump  ─┘                                       ├→ ServiceEntry YAML 片段
                                                        └→ 改动的 diff
```

判定记录(建议结构,§6.3 展开)是这张图里现在**唯一缺失的资产**。
配对图的四张卡片里,"强制出口的安全基石"那张讲的是 NetPol 兜底,
但**没有一张讲"白名单里每一条的来历"**。

> 这是本篇相对配对图新增的一层:**审计维度**。
> 图管"流量怎么走",Jev explorer 管"为什么允许它走",两者是互补的坐标系。

---

## 3. 第一层:代码已经能判定的部分(不进模型)

### 3.1 NP-3 CIDR 实算(本机 `ipaddress`,非估算)

`02-network-policies.yaml` NP-3 的两条 allow 规则:

```yaml
- to: [{ ipBlock: { cidr: 128.0.0.0/2, except: [10.0.0.0/8, 172.16.0.0/12,
        192.168.0.0/16, 169.254.0.0/16, 127.0.0.0/8, 224.0.0.0/4,
        0.0.0.0/8, 100.64.0.0/10] } }]
- to: [{ ipBlock: { cidr: 10.0.0.0/8, except: [172.16.0.0/12,
        192.168.0.0/16, 169.254.0.0/16] } }]
```

**规则 1 实算结果**(Python `ipaddress.address_exclude` 逐条 carve):

| 项 | 值 |
|---|---|
| 基数段 | `128.0.0.0/2` = `128.0.0.0` – `191.255.255.255` |
| carve 后剩余网段数 | **19** |
| 覆盖地址数 | 1,072,627,712 |
| 占 IPv4 比例 | **24.9741%** |

**规则 2 实算结果**:`except` 里三条(`172.16/12`、`192.168/16`、`169.254/16`)都不在
`10.0.0.0/8` 内,carve 后**原样保留**,仍覆盖 16,777,216 个地址(100% of 10/8)。

**逐个目标 IP 的判定**:

| 目标 | 属 128/2? | 属 10/8? | NP-3 判定 | 轨道 |
|---|---|---|---|---|
| `128.171.1.10`(on-prem DRN / SCC) | ✅ | — | **ALLOW** | A |
| `10.72.5.9`(NHF SNAT 段) | — | ✅ | **ALLOW** | A |
| `10.68.1.20`(GKE Squid ClusterIP 段) | — | ✅ | **ALLOW** | A |
| `20.190.159.4`(`login.microsoftonline.com`) | ❌ | ❌ | **DENY** | B |
| `13.107.42.14`(`graph.microsoft.com`) | ❌ | ❌ | **DENY** | B |
| `110.242.68.66`(百度) | ❌ | ❌ | **DENY** | B |
| `121.14.77.221`(搜狐) | ❌ | ❌ | **DENY** | B |
| `1.1.1.1` | ❌ | ❌ | **DENY** | B |

> ✅ **这张表就是配对图卡片「轨道 B — L7 域名级管控」第 2 条的实证**:
> "公网 SaaS 网段不在 128/2 内,已被 NP-1 + NP-3 天然 DENY —— deny 基线现在就在执行"。
>
> ✅ 同时确认配对图卡片「轨道 A」第 1 条:`128.171.x` 落进 128/2 是**设计意图**,
> 而 §3.1 的实算证明它确实被放行。**两条卡片说法都成立。**

### 3.2 代码预筛器的职责划分

```
Squid access.log 行
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│ 第 0 层 · 正则 + ipaddress(纯代码,零模型调用)                 │
│   · 抽出 host:port                                          │
│   · dig/解析出 IP,跑 §3.1 的 carve                         │
│   · 命中 128/2 或 10/8 → 标 track_a_l3,**直接放行,不发请求**   │
│   · 非 443/80 → 标 reject(裸 TCP,无 L7 执法点)              │
│   · 剩余 → 进第 1 层                                        │
└─────────────────────────────────────────────────────────────┘
      │
      ▼  (只把语义模糊的送进 Jev)
```

> **收益是量化的**:`.corp` / `128.x` / `10.x` 这类内部目标占比通常过半。
> 它们一次模型调用都不花。若某日 3,000 个 CONNECT 目标里有 1,200 个落在 128/2,
> 实际模型调用量直接降到 1,800(见 §7.3 的实测口径)。

---

## 4. 第二层:Jev 的六个问题

### 4.1 问题集全貌

| # | 问题 ID | 类型 | 回答什么 | 谁消费答案 |
|---|---|---|---|---|
| 1 | `egress_track` | **Choice**(4 选 1) | 属于哪条轨道 | 代码分支:轨道 A 直接跳过,轨道 B 进白名单流程 |
| 2 | `needs_domain_allowlist` | **Noul** | 需不需要 L7 开口 | 决定是否生成 ServiceEntry |
| 3 | `saas_cdn_ip_dependency` | **Noul** | 钉 ipBlock 是否不可持续 | **只做重排序信号,不做授权**(§6.4) |
| 4 | `bypasses_waypoint` | **Noul** | 是否存在不经 waypoint 的路径 | CI 闸门 + 生成前的安全前置检查 |
| 5 | `squid_acl_survives_mesh` | **Noul** | Squid ACL 入 mesh 后是否还成立 | 决定 Squid 是否需 `dataplane-mode: none` |
| 6 | `bypass_susceptibility` | **Score**(4 级) | 若照此配置上线,静默绕行风险多大 | 门禁;≥某级时阻断 PR |

### 4.2 选型理由(以及为什么不选另外两个)

docs 的选型原则(primitives 页):*Noul = 干净的 yes/no;Score = 有序程度;
Choice = 有限集合里选一个;Level 之间没有中间态就别用 Score,改用 Choice 或拆成 Noul。*

| 问题 | 选型 | 理由 |
|---|---|---|
| `egress_track` | **Choice** | 四个互斥类别,无序。`reject` 就是 docs 说的 **no-match outcome** —— 没有合法业务需求时必须有一个出口,否则模型只能勉强在三个里挑一个 |
| `needs_domain_allowlist` | **Noul** | 是"要不要开口"的二值判断。⚠️ docs 明确警告:**Noul ≈ 0.5 是"yes/no 各半",不是"中等强度"**。代码必须做三路分派,不能 `>= 0.5` 就当 yes |
| `saas_cdn_ip_dependency` | **Noul** | 是"会 / 不会"的事实判断,不是程度 |
| `bypasses_waypoint` | **Noul** | 二值。注意这是**配置事实**,配了结构化的 `policy` 字段和 `focus` 提示才问得准 |
| `squid_acl_survives_mesh` | **Noul** | **投机问题** —— 大部分候选根本没走 Squid。docs 的 speculative fan-out 明确支持:"State each speculative premise explicitly; code consumes the applicable answers."指令里已写明前提 |
| `bypass_susceptibility` | **Score** | 这是**唯一**真正沿有序程度变化的问题:"无绕行 / 绕行但 fail-closed / 绕行且静默成功 / 当前实际未执法" —— 严重度是递进的,Choice 表达不了这个顺序 |

> **关于 Score 级别的写法**:docs 强调 *"Levels must describe concrete situations and stand
> on their own"*。所以每级都写成"什么配置长什么样",不是"风险高/中/低"。
> 最高级甚至直接写死可观测的信号(`deny 基线已移除`、`无 SE 无 AuthZ`),
> 让它可以被 grep 审计。

### 4.3 完整 payload

**state**(每个候选域名一份):

```json
{
  "candidate": {
    "domain": "login.microsoftonline.com",
    "destination_cidr": "20.190.159.4/32",
    "observed_port": 443,
    "code_class": "public_saas_deny_by_np3",
    "source": {
      "log": "gke-squid-access.log",
      "hit_count_30d": 18423,
      "first_seen": "2026-08-14",
      "last_seen": "2026-10-01"
    },
    "path_notes": "业务 pod -> ztunnel -> egress waypoint (待建) -> public"
  },
  "observations": {
    "resolved_ips": ["20.190.159.4", "20.190.160.4", "20.190.162.4", "20.190.163.4"],
    "ip_prefix_diversity": "4 distinct /24s, observed to rotate between resolutions",
    "sample_connect_lines": [
      "CONNECT login.microsoftonline.com:443 200 2913 TCP_MISS/200",
      "CONNECT login.microsoftonline.com:443 200 1180 TCP_MISS/200"
    ],
    "proxy_path": "current: Cloud DNS alias -> GKE Squid:3128 -> GCE VM Squid -> public",
    "acl_dependencies": ["src IP in localnet", "dst domain in allowed_domains", "port 443 in Safe_ports"]
  },
  "policy": {
    "company_egress_policy": "Two tracks. Track A (internal DRN / corporate-routed public range): if it can leave at L3, do not control it at L7; the office egress already audits it. Track B (public SaaS): must traverse the egress waypoint and be allowed per domain at L7.",
    "networkpolicy_baseline": "NP-1 default-deny-all + NP-3 (128.0.0.0/2 except [...], plus 10.0.0.0/8) are in force. Public SaaS is not covered, so direct pod-to-public egress is denied today.",
    "net3_cidrs": ["128.0.0.0/2", "10.0.0.0/8"],
    "mesh": "istio 1.30.3-distroless (Standard), ambient mode, namespace ba000000-lex-int"
  }
}
```

**questions**(一次调用全部发出,完整 JSON 见 §13.2):

```text  (结构示意,`...` 与 `{...}` 是占位符 —— 可复制的完整 JSON 见 §13.2)
{
  "egress_track":         { "type": "choice", "criteria": { "track_a_l3": "...", "track_b_l7": "...", "reject": "..." } },
  "needs_domain_allowlist": { "type": "noul",  "criteria": { "true": {...}, "false": {...} } },
  "saas_cdn_ip_dependency": { "type": "noul",  "criteria": { "true": {...}, "false": {...} } },
  "bypasses_waypoint":      { "type": "noul",  "criteria": { "true": {...}, "false": {...} } },
  "squid_acl_survives_mesh":{ "type": "noul",  "criteria": { "true": {...}, "false": {...} } },
  "bypass_susceptibility":  { "type": "score", "criteria": [ {...}, {...}, {...}, {...} ] }
}
```

> 六个问题的 `instructions` / `criteria` **完整 JSON 全文**(JSON 语法已校验)见 **§13 附录**。

---

## 5. 组合:代码拥有工作流

docs 的核心立场:*"build a normal software workflow and insert System One only where AI is
needed"*,*"Keep control flow, deterministic rules, and side effects in code."*

### 5.1 判定 → 动作的映射(阈值在代码里)

```python
# ---- thresholds live in code, tunable without re-running inference ----
TRACK_OK      = 0.70     # egress_track / track_b_l7
NUL_YES       = 0.75     # needs_domain_allowlist, bypasses_waypoint(反义)
NUL_NO        = 0.25
SCORE_BLOCK   = 2.40     # bypass_susceptibility >= this -> block
CHOICE_CONF   = 0.60     # below -> human review, regardless of which option won

def decide(ans, code_class):
    track = ans["egress_track"]
    if track.confidence < CHOICE_CONF:
        return "queue_human_review", f"low confidence {track.confidence:.2f}"

    if code_class == "track_a_l3":
        return "no_l7_policy", "already allowed at L3, audited at office egress"

    if track.choice == "track_a_l3":
        return "no_l7_policy", "model agrees with the CIDR pre-filter"

    if track.choice == "reject":
        return "deny", "no legitimate business need"

    if track.choice == "track_b_l7":
        if ans["squid_acl_survives_mesh"].noul >= NUL_YES:
            squid = "dataplane-mode: none"      # otherwise ACL silently mis-evaluates
        else:
            squid = "none"
        # NOTE: saas_cdn_ip_dependency is NOT consulted here -- see 6.4
        return "emit_serviceentry", {
            "host": ans["_candidate_domain"],
            "sniff_protocol": "TLS" if observed_port == 443 else "HTTP",
            "squid_ns_label": squid,
            "authz_hosts": [real_domain],        # NOT the Cloud DNS alias
        }

    return "queue_human_review", "split_needed"
```

### 5.2 三路分派,不是二值阈值

docs 反复强调这一点。`needs_domain_allowlist` 的处理:

```python
p = ans["needs_domain_allowlist"].noul
if p >= 0.75:   open_hole()        # 明确要开口
elif p <= 0.25: keep_closed()      # 明确不用
else:            queue_human_review()   # ★ 中间值是人,不是任一分支
```

> ⚠️ **不要写 `if noul > 0.5: allow`**。那等于把 0.51 读成"是",把 0.49 读成"否",
> 而模型说的是"两者差不多可能"。安全策略里这是最糟的一种读法。

### 5.3 一次调用,六路消费

因为六个问题并行且互相不可见,返回后**同时**可用:

```python
r = client.system_one(model="jev-latest", state=state, questions=QUESTIONS)
a = r.answers
# 六个值一起进决策函数,不是六次 if-else 串行
```

> 复用性提示:docs 指出改权重、改展示过滤,**不需要重跑推理**,只要证据和问题含义没变。
> → 6.2 的判定记录可以离线重算轨迹,不必重新花钱调用。

---

## 6. 判定记录与可审计性

### 6.1 为什么必须有记录

配对图卡片「强制出口的安全基石」讲的是 NetPol 兜底。但 6 个月后没人能回答:
**"为什么 `login.microsoftonline.com` 在白名单里,而 `telemetry.example.net` 不在?"**
→ 每条判定必须留下原始答案。

### 6.2 记录结构(append-only)

```json
{
  "schema": "jev-egress-decision/v1",
  "decided_at": "2026-10-02T12:00:00+08:00",
  "model": "jev-1.13.0",
  "note": "model field in the response is the versioned ID that actually answered",
  "state_sha256": "…",
  "question_set_sha256": "…",
  "candidate": { "domain": "login.microsoftonline.com", "port": 443 },
  "answers": {
    "egress_track": {
      "choice": "track_b_l7",
      "probabilities": { "track_a_l3": 0.01, "track_b_l7": 0.97, "reject": 0.02 },
      "confidence": 0.95
    },
    "needs_domain_allowlist":     { "noul": 0.93 },
    "saas_cdn_ip_dependency":     { "noul": 0.89 },
    "bypasses_waypoint":          { "noul": 0.08 },
    "squid_acl_survives_mesh":    { "noul": 0.94 },
    "bypass_susceptibility": {
      "score": 0.21,
      "legend": { "0": "No bypass path...", "1": "...", "2": "...", "3": "..." },
      "probabilities": { "0": 0.79, "1": 0.16, "2": 0.04, "3": 0.01 },
      "confidence": 0.68
    }
  },
  "disposition": "emit_serviceentry",
  "code_version": "explorer@v1",
  "reviewer": "unreviewed"
}
```

> ⚠️ 上面的概率分布是**格式示例,不是实测输出**。真实数值必须由 API 返回后落库。
> 这也是 docs 的要求:*"log which model produced each result"*(response 的 `model` 字段
> 是**版本化 ID**,不是你发的 alias —— 阈值调好后应 pin 住这个 ID)。

### 6.3 审计视图(纯代码,不重跑推理)

```
$ jq -r 'select(.answers.egress_track.choice=="track_b_l7")
         | [.candidate.domain, .answers.bypass_susceptibility.score, .reviewer] | @tsv' decisions.ndjson
login.microsoftonline.com  0.21  unreviewed
graph.microsoft.com        0.34  lex-2026-10-02
```

改阈值重新看全表 → 不花一分钱。

### 6.4 ★ `saas_cdn_ip_dependency` 只做重排序,不做授权

这是一个**有意的设计约束**,值得单独说:

- 如果判定为 `true`(CDN / 不可持续)→ **提高** 该域名的复核优先级,不降低。
- **绝不能**反向:不能因为判定为 `false`("前缀看起来稳定")就自动生成
  `ipBlock` 放行。Jev 在这个问题上判错,后果是**几周后 egress 静默中断**
  (CDN 换段,NetPol 不再放行),而且极难定位。
- 所以本方案里,`NetPol` 的公网规则**始终**由 `base-lex-ServiceEntry.md` §6.3.1
  策略 ② 决定:NetPol 只管端口级边界,域名白名单交给 `AuthorizationPolicy`。

> **Jev 重排优先级,代码做处置。** 这是本方案最重要的一条纪律。

---

## 7. 预算与吞吐

### 7.1 两层调用结构

```
Tier 1 · 批量分诊(1 个 Choice,整批 50 个候选)
   目的:剔除同质批次,只把"混合批次"拆开
   state: 50 个候选的紧凑摘要(域名 + code_class + 命中数)
   → 4 选 1:promote_to_panel / keep_l3_unaudited_by_istio / reject_outright / split_needed

Tier 2 · 单域名六问(§4.3)
   只对 promote_to_panel 的候选跑
```

`split_needed` 这个选项是 Tier 1 存在的唯一理由:一批 50 个域名里如果混了
`track_a_l3` 和 `track_b_l7`,模型会明确要求拆分,而不是把两者概率摊平。

### 7.2 单价与额度(来源:docs/Models)

| 项 | 值 |
|---|---|
| 当前模型 | `jev-1.13.0`(`jev-latest` → 同;`jev-preview` 亦同,暂无 preview) |
| 价格 | **$42 / Mtok input**;**output 免费** |
| 速率限制 | 250,000 tok/s · **1,200 req/min** |
| 超限 | `429`(SDK 默认指数退避,并遵守 `retry-after`);`529` 同理 |

> ⚠️ docs 明确警告速率限制在动态调整,表内数值随时可能变。
> → **不要把 1,200 rpm 写进任何 SLA**,按突发处理。

### 7.3 成本对比(估算口径,见 §10.2)

以 3,000 个候选、每候选 state ~520 tok、六问 ~880 tok 为例:

| 方案 | 调用数 | input token | 成本 | 最短耗时(1200 rpm) |
|---|---|---|---|---|
| Flat(全部走 Tier 2) | 3,000 | 4,200,000 | **$0.176** | 150 s |
| Hybrid(Tier1 批量 + 仅 35% 进 Tier 2) | 60 + 1,050 | 1,620,000 | **$0.068** | ~47 s |
| **节省** | | | **61%** | |

**延迟视角**(docs: 多数查询约 100 ms):

```
300 域名串行        = 300 × 0.1s = 30.0 s
300 域名 20 并发    = (300/20) × 0.1s = 1.5 s
```

> 并发是安全的:请求之间无共享状态,docs 也未要求顺序。
> 唯一硬约束是 1,200 req/min —— 20 并发 × 3 req/s = 3,600 rpm,**会超限**。
> → 生产侧并发上限应设为 **≤ 15**,留一半余量。

### 7.4 CI 闸门的成本

单次 PR 检查 = **1 次调用 ≈ 2,600 tok ≈ $0.00011**。
即使每天 50 个 PR 跑全部 egress 检查:

```
50 × $0.00011 = $0.0055 / 天 ≈ $0.17 / 月
```

**成本不构成任何约束。** 这也是为什么 CI 闸门是最该先做的一步(§8.2)。

---

## 8. ★ 边界:Jev 不能做什么

### 8.1 5 条硬约束 —— 模型不知道的事

以下全部来自 `base-lex-ServiceEntry.md`,是**版本相关的能力事实**,不是判断。
Jev 没有 1.30.3 的知识,也不该靠 prompt 注入这些:

| # | 硬约束 | 出处 |
|---|---|---|
| ① | `use-waypoint` 单独**不保证**经过 waypoint;waypoint 不可用时 ztunnel passthrough 直连 | Istio docs §"Require traffic to traverse the waypoint" |
| ② | 官方 `require-waypoint` 用 workload `selector`,对 ServiceEntry 目标**不适用**(外部服务无 workload) | 同上 |
| ③ | ztunnel 无法执行 L7 策略;L7 属性被 targetRefs 到 ztunnel 时 **fail-safe 成 DENY** | Istio L4 policy docs |
| ④ | `exportTo` 在 ambient **被忽略**;`outboundTrafficPolicy: REGISTRY_ONLY` ztunnel **不读** | Solo 1.30.x migrate-sidecar |
| ⑤ | ztunnel / waypoint **不支持 wildcard hosts**;`DYNAMIC_DNS` 仅 ambient + `MESH_EXTERNAL` + waypoint | ServiceEntry reference NOTE 3 |

> **这 5 条要由代码在生成 YAML 前硬校验**,不是问模型。
> 例:生成器见到 `hosts: ["*.foo.com"]` → 直接报错退出,不发起调用。

### 8.2 `bypass_susceptibility` 的正确用法

它的天然位置是 **`base-lex-ServiceEntry.md` §11.3 第 6 步的安全断言自动化**:

```bash
kubectl scale deploy/egress-waypoint -n istio-egress --replicas=0
sleep 20
kubectl exec -n ba000000-lex-int deploy/app -- \
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 https://microsoft.intra.aibang.local/
# PASS: 000 / 超时(deny 基线生效,无 passthrough)
# FAIL: 200  → ⚠️ 有人把 NP-3 改成 0.0.0.0/0 了
```

这条断言**本来就要跑**,Jev 的增量是:**把断言结果 + 相关配置 dump 作为 state,
让模型判定"这次 diff 是不是引入了静默绕行"**,并让 `bypass_susceptibility ≥ 2.40`
阻断 PR。

> ⚠️ **不要在生产运行时依赖它**。它是静态配置审查,不是运行时检测。
> docs 的原则在这里完全适用:*"Typed output guarantees the interface, not truth."*

### 8.3 三个已知的误判风险

| # | 风险 | 表现 | 缓解 |
|---|---|---|---|
| ① | 把 CDN 误判为"稳定前缀" | §6.4 说的几周后静默断流 | 该答案不参与授权,只排优先级 |
| ② | `squid_acl_survives_mesh` 投机问题被过度解读 | 无 Squid 路径的候选也返回高值 | 指令已写明前提;代码只在 `proxy_path` 非空时消费 |
| ③ | 域名白名单被诱导放宽 | 一次 `reject` 判成 `track_b_l7` | `reject` 单独成一档;低置信一律转人工(§5.1) |

> docs 的定力条款:*"Treat cookbook thresholds and demo results as examples to evaluate,
> not universal rules or permanent model limitations."* 上表三个阈值
> (0.70 / 0.75 / 2.40) **全是我按 docs 举例量级给的初值,必须在你们自己的数据上校准**。

---

## 9. 落地路径

```
Phase A · 零风险,不需要模型(1 天)
  ├─ 跑 §3.1 的 carve 脚本,把结论固化成 CI 断言
  │   "NP-3 未被改成 0.0.0.0/0"  ← 直接对应 R2
  └─ 跑 §6.3.1 方法 2,统计真实域名清单(输出一个 .ndjson)

Phase B · 只读影子(1~2 周)                        ← ★ 先做这个
  ├─ 配好 TYPESAFE_API_KEY,单域名串行,每天一次
  ├─ 只写 decisions.ndjson,**不生成任何 YAML**
  ├─ 人工逐条复核,把误判记进 docs
  └─ 校准 §8.3 的三个阈值

Phase C · 生成但不 apply
  ├─ 判定记录 → ServiceEntry 片段,进 review PR
  └─ 硬校验 §8.1 的 5 条约束(违规直接 exit 1)

Phase D · CI 闸门
  └─ egress diff → 1 次 Jev 调用 → 阻断静默绕行
```

> ⚠️ **Phase 0 仍是 `base-lex-ServiceEntry.md` §13.3 的四项前置**,Jev 不替代其中任何一项 ——
> 尤其是"从 Squid access.log 统计真实域名清单"。**Jev 消费那份清单,不产出它。**

---

## 10. ⚠️ 局限与未验证项(诚实标注)

### 10.1 本篇没有调用过 TypeSafe API

**本机无 `TYPESAFE_API_KEY`,`typesafe_sdk` 也未安装**(已核实)。
因此:

- §6.2 的概率分布是**格式示例**,数值非实测;
- §0.3 / §7.3 的 token 数是**按 payload 结构估算**,非实测;
- §8.3 的三个阈值**未在真实数据上校准**。

本文交付的是**设计与可复制 payload**,不是推理结果。

### 10.2 拿到 key 后应当做的第一件事(校准清单)

| # | 测什么 | 怎么看 |
|---|---|---|
| 1 | 真实 token 数 | 响应里的 `usage.input_tokens` —— 校准 §0.3 全表 |
| 2 | `egress_track` 判别力 | 抽 30 个已知轨道的域名,看 `track_a_l3` / `track_b_l7` 是否分得开 |
| 3 | 跑 3 次看稳定性 | docs 提到自洽性(Consistency)cookbook;同一 state 重复跑,看 `probabilities` 抖动 |
| 4 | `confidence` 分布 | 你们的场景里它落在哪个区间?0.60 这个 CHOICE_CONF 初值是否合理 |
| 5 | Score 级别是否重叠 | 看 `probabilities` 是不是老压在两级之间 —— 压着就说明级别定义还不够具体,回去改 `criteria` |

### 10.3 其他未验证项

| 项 | 为什么没验 | 怎么验 |
|---|---|---|
| 轨道 A / B 的分界在 `128.171.x` 附近是否清晰 | 依赖公司段实际分配 | 拿公司申请的公网段清单核对 |
| 一个 state 里放多少候选不降质 | 未测批量语义稀释 | Phase B 逐步加大批量,对比单条结果 |
| 审计记录的保留期与合规要求 | 未知公司规范 | 问安全/合规 |

---

## 11. 权威证据

### 11.1 TypeSafe(本篇方法论来源)

| 主题 | 链接 | 关键原话 / 依据 |
|---|---|---|
| 文档索引 | [llms.txt](https://docs.typesafe.ai/llms.txt) | 全部页面入口 |
| System One 编程模型 | [concepts/system-one](https://docs.typesafe.ai/concepts/system-one.md) | "It returns typed decisions and probabilities rather than generated text.";*"Most queries complete in about 100 ms."* |
| 三种 primitive | [primitives](https://docs.typesafe.ai/primitives.md) | Choice / Score / Noul 的返回字段与选型;*"A Noul value of 0.5 means the model gives yes and no equal probability. It does not mean the candidate has a medium skill level."* |
| Noul 三路分派 | [primitives/noul](https://docs.typesafe.ai/primitives/noul.md) | *"Values in the middle can go to a person rather than either code path."*;"There is no separate `confidence` value for a Noul." |
| Score 级别写法 | [primitives/score](https://docs.typesafe.ai/primitives/score.md) | 结构化 `examples` 可把 confidence 从 0.35 提到 0.96;*"If there is no in-between at all... use a Choice instead, or split the question into several Nouls."* |
| Confidence | [confidence](https://docs.typesafe.ai/confidence.md) | Choice 公式 `(count × peak − 1)/(count − 1)`;Score 基于 MAD;*"This describes the model's answer, not a guarantee that the answer is correct."* |
| Confidence 分级路由 | [patterns/confidence-routing](https://docs.typesafe.ai/patterns/confidence-routing.md) | 0.6 兜底转人工;低风险 0.6 够,高风险 >0.85 —— §5.1 阈值按此量级给初值 |
| state 结构 | [concepts/state](https://docs.typesafe.ai/concepts/state.md) | 命名 JSON 字段;反引号路径引用 |
| API 契约 | [api](https://docs.typesafe.ai/api.md) | `POST /v1/systemone`;`state` / `model` / `questions`;Choice 上限 255 选项、Score 2–10 级;`401/422/429/529` |
| 模型与价格 | [models](https://docs.typesafe.ai/models.md) | `jev-1.13.0`;**$42/Mtok input,output 免费**;250k tok/s · 1,200 rpm;响应 `model` 字段是版本化 ID |
| 组合原则 | [concepts/how-to-build-with-system-one](https://docs.typesafe.ai/concepts/how-to-build-with-system-one.md) | *"Keep control flow, deterministic rules, and side effects in code."*;*"Changing a weight or display filter need not rerun inference"* |

### 11.2 Istio / Solo(硬约束来源,经 `base-lex-ServiceEntry.md` §14 二次引用)

| 主题 | 链接 | 关键原话 |
|---|---|---|
| ServiceEntry reference | [istio.io](https://istio.io/latest/docs/reference/config/networking/service-entry/) | "**NOTE 3: Ztunnel and Waypoint proxies do not support wildcard hosts.**";"exportTo ... will read it at `*`";`DYNAMIC_DNS` 仅 ambient + MESH_EXTERNAL + waypoint |
| waypoint 强制经过 | [ambient/usage/waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/#require-waypoint) | "**on its own it does not guarantee that this happens**";解法用 workload selector 而非 targetRef |
| L4 策略 fail-safe | [ambient/usage/l4-policy](https://istio.io/latest/docs/ambient/usage/l4-policy/) | "**If a policy with rules matching L7 attributes ... it will fail safe by becoming a `DENY` policy.**" |
| ambient egress gateway | [ambient/usage/egress-gateway](https://istio.io/latest/docs/ambient/usage/egress-gateway/) | "**a waypoint proxy naturally acts as an egress gateway**";waypoint 不可用时"does not prevent direct paths" |
| sidecar → ambient 迁移 | [Solo 1.30.x](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/migrate-sidecar/) | "**In an ambient mesh, ztunnel does not read `outboundTrafficPolicy`.**";"**In ambient mode, `exportTo` is ignored.**" |
| 外部 HTTPS 代理 | [istio.io tasks](https://istio.io/latest/docs/tasks/traffic-management/egress/http-proxy/) | "**Define a TCP (not HTTP!) Service Entry for the HTTPS proxy.**";"you must not create service entries for the external services you access through the external proxy" |

### 11.3 本仓库

| 文档 | 本篇引用的内容 |
|---|---|
| [`case-lex-public-egress.html`](./case-lex-public-egress.html) | 四张卡片的两轨策略 / Squid 演进 / 强制出口基石;轨道边界与 17 条连接 |
| [`base-lex-ServiceEntry.md`](./base-lex-ServiceEntry.md) | §2.1 两轨策略、§2.2.1 CONNECT 流程、§6.3.1 域名统计与 CDN 不可持续、§8.1 五条硬约束、§10.3 NP-3 即防线、§11.3 第 6 步安全断言、§13.3 Phase 0-4 |
| [`02-network-policies.yaml`](./02-network-policies.yaml) | NP-1 / NP-3 的 CIDR 与 `except` 原文(§3.1 实算输入) |
| [`03-mesh-security.yaml`](./03-mesh-security.yaml) | PA STRICT + 2 AuthZ 的方向性 |
| `.archify/architecture-case-lex-public-egress-20261002-124434/candidate.json` | 组件 / 边界 / 连接 / 卡片的结构化原文 |
| **本地实证** | `128.0.0.0/2` carve → 19 段 / 24.9741%;`10.0.0.0/8` carve → 无变化;7 个目标 IP 逐个判定(§3.1 表) |
| **成本算术** | Python 按 $42/Mtok × 估算 token → §0.3 / §7.3 全表 |

---

## 12. 阈值来源 —— 这三个数为什么是这些值

| 阈值 | 初值 | 依据 | 何时该调 |
|---|---|---|---|
| `CHOICE_CONF` | 0.60 | confidence-routing 页的兜底转人工示例值 | Phase B 复核发现漏判 → 升;发现大量无谓人工 → 降 |
| `TRACK_OK` | 0.70 | 比兜底值高,轨道判定错了代价大 | 混淆 track_a/track_b 多 → 升到 0.80 |
| `NUL_YES` / `NUL_NO` | 0.75 / 0.25 | 安全域保守,中间 50% 留给人工 | 人工队列太长 → 收窄到 0.80/0.20 |
| `SCORE_BLOCK` | 2.40 | 4 级 Score 上的 ~60 分位 | 若 2 级(绕行且静默成功)出现即应阻断 → 降到 2.0 |

> **改阈值不需要重跑推理** —— docs: 改权重 / 展示过滤在证据与问题含义不变时无需重跑。
> 所以上面这张表可以反复调,只花第一次的钱。

---

## 13. 附录 —— 完整 payload(可复制,JSON 语法已校验)

> 三块内容:① 单域名的 `state`;② Tier 2 六问的 `questions`;③ Tier 1 批量分诊的 `questions`。
> 全部按 docs 的 API 契约编写(`POST /v1/systemone`,顶层 `state` / `model` / `questions`)。
> 三个 `questions` 块在生成时用 `json.loads` 校验过语法。
> ⚠️ **未调用过 API** —— 字段语义与返回结构已按 docs 逐项对齐,实际响应需你们验证。

### 13.1 `state` —— 单个候选域名

```json
{
  "candidate": {
    "domain": "login.microsoftonline.com",
    "destination_cidr": "20.190.159.4/32",
    "observed_port": 443,
    "code_class": "public_saas_deny_by_np3",
    "source": {
      "log": "gke-squid-access.log",
      "hit_count_30d": 18423,
      "first_seen": "2026-08-14",
      "last_seen": "2026-10-01"
    },
    "path_notes": "业务 pod -> ztunnel -> egress waypoint (待建) -> public"
  },
  "observations": {
    "resolved_ips": [
      "20.190.159.4",
      "20.190.160.4",
      "20.190.162.4",
      "20.190.163.4"
    ],
    "ip_prefix_diversity": "4 distinct /24s, observed to rotate between resolutions",
    "sample_connect_lines": [
      "CONNECT login.microsoftonline.com:443 200 2913 TCP_MISS/200",
      "CONNECT login.microsoftonline.com:443 200 1180 TCP_MISS/200"
    ],
    "proxy_path": "current: Cloud DNS alias -> GKE Squid:3128 -> GCE VM Squid -> public",
    "acl_dependencies": [
      "src IP in localnet",
      "dst domain in allowed_domains",
      "port 443 in Safe_ports"
    ]
  },
  "policy": {
    "company_egress_policy": "Two tracks. Track A (internal DRN / corporate-routed public range): if it can leave at L3, do not control it at L7; the office egress already audits it. Track B (public SaaS): must traverse the egress waypoint and be allowed per domain at L7.",
    "networkpolicy_baseline": "NP-1 default-deny-all + NP-3 (128.0.0.0/2 except [...], plus 10.0.0.0/8) are in force. Public SaaS is not covered, so direct pod-to-public egress is denied today.",
    "net3_cidrs": [
      "128.0.0.0/2",
      "10.0.0.0/8"
    ],
    "mesh": "istio 1.30.3-distroless (Standard), ambient mode, namespace ba000000-lex-int"
  }
}
```
### 13.2 `questions` —— Tier 2 单域名六问(核心)

```json
{
  "egress_track": {
    "type": "choice",
    "instructions": {
      "question": "Which egress track does this destination belong to under the company two-track egress policy?",
      "inspect": [
        "`candidate.domain`",
        "`candidate.destination_cidr`",
        "`candidate.code_class`",
        "`observations`"
      ],
      "policy": {
        "track_a": "Internal DRN / corporate-routed public range / office egress. Default NOT controlled at L7; already audited at the office egress.",
        "track_b": "Genuine public SaaS (Microsoft, M365, Baidu, Sohu, third-party APIs). MUST traverse the egress waypoint and be allowed per domain at L7.",
        "reject": "No legitimate business need, or the destination cannot be governed by domain at L7 (raw TCP with no SNI, or a CDN-only IP that must be pinned)."
      }
    },
    "criteria": {
      "track_a_l3": "The destination IP is inside the corporate-routed range already open at L3 (NP-3 128.0.0.0/2 minus its except list, or 10.0.0.0/8), and the caller is an internal workload.",
      "track_b_l7": "A named public SaaS host that needs a ServiceEntry plus an AuthorizationPolicy hosts allowlist on the egress waypoint.",
      "reject": "Unknown, unexplained, non-SaaS (telemetry, ads, tracking, pastebin, raw TCP), or a domain that no legitimate workload in this namespace should reach."
    }
  },
  "needs_domain_allowlist": {
    "type": "noul",
    "instructions": {
      "question": "Does reaching this destination require a domain-level L7 allowlist rather than an IP range?",
      "inspect": [
        "`candidate.domain`",
        "`observations.sample_connect_lines`"
      ],
      "focus": "Answer yes when the gateway layer must read SNI or Host to decide. Answer no when the destination is already fully decided at L3 by the corporate route."
    },
    "criteria": {
      "true": {
        "what": "SNI or Host header is required to identify and allow this destination.",
        "not_for": "Destinations already reachable and audited at L3 without L7 inspection."
      },
      "false": {
        "what": "L3 reachability plus existing office-side auditing is sufficient; no L7 allowlist needed."
      }
    }
  },
  "saas_cdn_ip_dependency": {
    "type": "noul",
    "instructions": {
      "question": "Would pinning this destination to a NetworkPolicy ipBlock create an unsustainable IP-maintenance dependency?",
      "inspect": [
        "`candidate.domain`",
        "`observations.resolved_ips`",
        "`observations.ip_prefix_diversity`"
      ],
      "focus": "Judge whether the resolved addresses look like a CDN or anycast front end whose prefixes change over time."
    },
    "criteria": {
      "true": {
        "what": "Many prefixes across several /24s or larger, typical of a CDN or anycast SaaS edge; an ipBlock allowlist would need constant maintenance.",
        "examples": [
          "login.microsoftonline.com",
          "graph.microsoft.com"
        ]
      },
      "false": {
        "what": "A small, stable set of prefixes, typical of a self-hosted or fixed-origin service.",
        "examples": [
          "an on-prem service behind a static VIP"
        ]
      }
    }
  },
  "bypasses_waypoint": {
    "type": "noul",
    "instructions": {
      "question": "Does this configuration or traffic path allow the request to reach the public internet without traversing the egress waypoint?",
      "inspect": [
        "`candidate.path_notes`",
        "`policy.networkpolicy_baseline`",
        "`policy.net3_cidrs`"
      ],
      "focus": "Look for any path that is not gated by the NP-1 + NP-3 deny baseline: direct pod-to-public-IP egress, a namespace not labeled for ambient, or a workload opted out with dataplane-mode none."
    },
    "criteria": {
      "true": {
        "what": "A path exists that reaches the destination outside waypoint L7 evaluation, so waypoint policy can be skipped."
      },
      "false": {
        "what": "Every path to this destination is forced through the waypoint, or is denied outright when the waypoint is unavailable."
      }
    }
  },
  "squid_acl_survives_mesh": {
    "type": "noul",
    "instructions": {
      "question": "If this traffic currently traverses a Squid forward proxy, would that proxy's source-IP-based ACL still be correct after the traffic is captured into the ambient mesh?",
      "inspect": [
        "`observations.proxy_path`",
        "`observations.acl_dependencies`"
      ],
      "focus": "Speculative: answer it even when no proxy is in the path, so one request covers the whole batch. HTTP CONNECT carries no X-Forwarded-For, so a src-IP ACL cannot be reconstructed after ztunnel forwarding."
    },
    "criteria": {
      "true": {
        "what": "The ACL depends on the original client source IP, which ztunnel forwarding changes and CONNECT does not carry; the ACL would silently mis-evaluate."
      },
      "false": {
        "what": "The ACL is expressed in terms that survive mesh capture, such as the destination domain and port only."
      }
    }
  },
  "bypass_susceptibility": {
    "type": "score",
    "instructions": {
      "question": "How likely is this egress configuration to silently permit a policy bypass if it were shipped as designed?",
      "inspect": [
        "`candidate`",
        "`observations`",
        "`policy`"
      ],
      "focus": "Judge the configuration, not the intent. Silent permission is worse than an explicit failure."
    },
    "criteria": [
      {
        "what": "No bypass path. Forced through the waypoint, denied when it is unavailable, and every allow is explicit.",
        "signals": [
          "NetPol deny baseline intact",
          "AuthZ on the ServiceEntry",
          "no dataplane-mode none workload in the path"
        ]
      },
      {
        "what": "A bypass path exists but it fails closed or is loudly observable.",
        "signals": [
          "bypass yields a connection error",
          "bypass is covered by a second control such as a GCE VM proxy ACL"
        ]
      },
      {
        "what": "A bypass path exists and would succeed silently, with no second control.",
        "signals": [
          "NetPol widened to 0.0.0.0/0",
          "workload not enrolled in ambient",
          "raw TCP service with no L7 enforcement point"
        ]
      },
      {
        "what": "The current configuration is effectively unenforced for this destination.",
        "signals": [
          "deny baseline already removed",
          "no ServiceEntry and no AuthZ",
          "traffic observed leaving without a waypoint in the path"
        ]
      }
    ]
  }
}
```
### 13.3 `questions` —— Tier 1 批量分诊(单 Choice)

```json
{
  "bucket_for_batch": {
    "type": "choice",
    "instructions": {
      "question": "Which single bucket best describes every candidate in `candidates`?",
      "inspect": [
        "`candidates`",
        "`policy`"
      ],
      "focus": "All candidates in this batch share one disposition. Code already resolved the L3 CIDR class; judge only the semantic disposition."
    },
    "criteria": {
      "promote_to_panel": "All candidates are genuine named public SaaS that need a per-domain L7 allowlist; run the full per-domain panel on each.",
      "keep_l3_unaudited_by_istio": "All candidates are internal or corporate-routed and already audited at the office egress; do not add L7 policy.",
      "reject_outright": "All candidates are non-SaaS or have no legitimate business need; do not add an allowlist entry.",
      "split_needed": "The batch mixes dispositions; split it and re-run triage per subgroup."
    }
  }
}
```
### 13.4 cURL 最小可跑片段

```bash
export TYPESAFE_API_KEY=...        # ★ 凭据只在服务端,勿入库

cat > request.json <<'JSON'
{ "model": "jev-latest", "state": <粘贴 13.1 的 state>, "questions": <粘贴 13.2 的 questions> }
JSON

curl -sS https://api.typesafe.ai/v1/systemone \
  -H "Authorization: Bearer $TYPESAFE_API_KEY" \
  -H "Content-Type: application/json" \
  --data @request.json | jq '.answers, .usage'
```

### 13.5 Python 骨架(消费六路答案)

```python
import os, json
from typesafe_sdk import TypeSafeClient

QUESTIONS = json.load(open("questions_tier2.json"))
state     = json.load(open("state.json"))

with TypeSafeClient() as client:
    r = client.system_one(model="jev-latest", state=state, questions=QUESTIONS)

a = r.answers
print("model        :", r.model)                      # 版本化 ID,不是 alias
print("input tokens :", r.usage.input_tokens)         # ★ 用于校准 §0.3 / §7.3
print("track        :", a["egress_track"].choice,
      f"conf={a['egress_track'].confidence:.2f}")
print("need L7 hole :", a["needs_domain_allowlist"].noul)
print("cdn-ip risk  :", a["saas_cdn_ip_dependency"].noul, "  # 仅排优先级,不做授权")
print("bypasses wp  :", a["bypasses_waypoint"].noul)
print("squid acl ok :", a["squid_acl_survives_mesh"].noul)
print("bypass score :", a["bypass_susceptibility"].score,
      f"conf={a['bypass_susceptibility'].confidence:.2f}")

# 三路分派,不是二值阈值
p = a["needs_domain_allowlist"].noul
disposition = "open_hole" if p >= 0.75 else ("keep_closed" if p <= 0.25 else "human")

# append-only 判定记录
with open("decisions.ndjson", "a") as fh:
    fh.write(json.dumps({
        "schema": "jev-egress-decision/v1", "model": r.model,
        "state_sha256": state_sha256, "question_set_sha256": question_set_sha256,
        "candidate": {"domain": state["candidate"]["domain"],
                      "port": state["candidate"]["observed_port"]},
        "answers": {k: vars(v) if not isinstance(v, dict) else v
                    for k, v in a.items()},
        "disposition": disposition, "code_version": "explorer@v1",
        "reviewer": "unreviewed",
    }, ensure_ascii=False) + "\n")
```

### 13.6 硬约束的代码前置校验(§8.1)

```python
import sys, re, json

def hard_check(sev: dict, gen: dict) -> None:
    """生成 YAML 之前的确定性校验。不通过就 exit 1,不要发起模型调用。"""
    errs = []
    # ①③ ServiceEntry / HTTPRoute 硬约束
    for h in gen.get("hosts", []):
        if h.startswith("*.") and h != "*":                      # ⑤
            errs.append(f"wildcard host {h!r} unsupported by ztunnel/waypoint")
    if gen.get("export_to") is not None:                          # ④
        errs.append("exportTo is ignored in ambient; use AuthorizationPolicy instead")
    if gen.get("outbound_traffic_policy") == "REGISTRY_ONLY":     # ④
        errs.append("ztunnel does not read outboundTrafficPolicy")
    # ③ L7 属性不得 targetRefs 到 ztunnel —— selector/targetRef 指向 workload
    for p in gen.get("authz_policies", []):
        if p.get("type") == "noul":
            continue
        if not p.get("targetRefs") and p.get("has_l7_attributes"):
            errs.append(f"policy {p.get('name')}: L7 attrs need a targetRefs L7 "
                        f"enforcement point, else ztunnel fails safe to DENY")
    # ② require-waypoint 依赖 workload selector,对 SE 目标不适用
    if gen.get("require_waypoint_via_targetref"):
        errs.append("require-waypoint needs a workload selector, "
                    "not a targetRef (no workload exists for an external service)")
    if errs:
        print("HARD CONSTRAINT VIOLATION:", file=sys.stderr)
        for e in errs:
            print("  -", e, file=sys.stderr)
        sys.exit(1)
```


---

*Generated by architect-gcp Bot —— 探索文档,未部署。*
*配对图:`case-lex-public-egress.html`(archify 3.0.1,showcase,9/9 校验通过)。*
*⚠️ 本机无 TypeSafe 凭据,**未调用过 API**;所有概率分布为格式示例,所有 token 数为结构估算。*
*§3.1 的 CIDR 结论由 Python `ipaddress` 实算得出,非估算。*
*所有 Istio 行为断言经 `base-lex-ServiceEntry.md` §14 的引用链二次核对。*
*本篇不修改 `case-lex/` 下任何现有文件。*
