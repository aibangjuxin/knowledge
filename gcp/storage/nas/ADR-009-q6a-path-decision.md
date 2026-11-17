# ADR-009 · Q6-a 验证路径决策对比

> **本文档是 ADR-009 的派生决策辅助文档** —— 不重复 ADR-009 主 ADR 内容,只在 Q6-a(底层打通方式)这一具体验证点的路径选择上做对比分析,供决策者拍板。
>
> **架构师 lane 边界声明**:本文档**只做分析与文档化**,**不实施任何 provision / apply 命令**,**不替决策者拍板**,**不写 SA、不跑 gcloud、不动 cluster**。决策权在 <DECISION_MAKER> 手里。

---

## 0. TL;DR

| 方案 | 时间成本 | 风险 | 长期价值 | 架构师评级 |
|---|---|---|---|---|
| **(b) profile 专属 SA JSON key** | 首次 30 分钟,后续 0 | 低(SA 可独立 rotate / 删除) | ⭐⭐⭐ | ✅ **推荐** |
| (d) 借用 <DECISION_MAKER> OAuth 临时跑 | 5 分钟刷 token,后续每次都要刷 | ⚠ 中(token 过期、audit log 污染) | ⭐ | ⚠ 仅临时 |
| (e) <DECISION_MAKER> 本机跑命令,贴输出 | 15-30 分钟(<DECISION_MAKER> 自己) | ⚠ 中(agent 无身份,后续问题复发) | ❌ 无 | ⚠ 一次性 |

**架构师建议**:走 **(b)**,理由见 §1.4。**(d)** 和 **(e)** 仅作为"等不及 (b) 的临时方案"。

---

## 1. 三条路径详细对比

### 1.1 方案 (b) — infra-gcp profile 专属 SA JSON key ⭐ 推荐

#### 实施步骤

```bash
# Step 1: <DECISION_MAKER> 在自己本机(非沙盒)创建 SA
gcloud iam service-accounts create infra-gcp-sa \
  --project=<PROJECT_ID> \
  --description="infra-gcp profile 专用 SA,Q6-a 验证 + ADR-010 实施"

# Step 2: 最小权限绑定(只读,够 Q6-a 5 条命令)
PROJECT=<PROJECT_ID>
SA=infra-gcp-sa@${PROJECT}.iam.gserviceaccount.com

for ROLE in roles/compute.networkViewer roles/compute.viewer; do
  gcloud projects add-iam-policy-binding ${PROJECT} \
    --member="serviceAccount:${SA}" \
    --role="${ROLE}"
done

# Step 3: 创建 JSON key
gcloud iam service-accounts keys create ~/infra-gcp-sa.json \
  --iam-account=${SA}

# Step 4: <DECISION_MAKER> 手动 copy 到 infra-gcp profile 目录
cp ~/infra-gcp-sa.json /Users/${USER}/.hermes/profiles/infra-gcp/secrets/
chmod 600 /Users/${USER}/.hermes/profiles/infra-gcp/secrets/infra-gcp-sa.json

# Step 5: infra-gcp 后续用它(脚本已就绪)
bash /Users/${USER}/.hermes/profiles/infra-gcp/scripts/activate-gcp-sa.sh
```

#### 时间成本

| 步骤 | 耗时 | 谁来做 |
|---|---|---|
| Step 1 创建 SA | 30 秒 | <DECISION_MAKER> |
| Step 2 绑权限 | 1 分钟 | <DECISION_MAKER> |
| Step 3 创建 key | 10 秒 | <DECISION_MAKER> |
| Step 4 copy 到 profile | 30 秒(手动) | <DECISION_MAKER> |
| Step 5 激活 | 5 秒 | infra-gcp 自动 |
| **总耗时** | **~3 分钟(<DECISION_MAKER> 实际操作)+ 1 分钟(infra-gcp 自动化)** | — |

#### 风险

| 风险 | 等级 | 缓解 |
|---|---|---|
| JSON key 通过 chat/git 泄漏 | ⚠ 中 | 手动 copy,**不经过任何共享通道** |
| SA 权限过大 | 低 | 只给 `compute.networkViewer` + `compute.viewer` read-only |
| SA 长期不过期 | 低 | 90 天 rotate 一次(`gcloud iam service-accounts keys create` + 旧的 `delete`) |
| <DECISION_MAKER> 忘记 revoke SA | 低 | 跑完 Q6-a 后可保留(ADR-010 实施也用),不用 revoke |
| 沙盒能否读 sa.json | 极低 | infra-gcp 已确认 secrets/ 目录 700 权限,可读 |

#### 长期价值

- ✅ ADR-009 后续验证(Q6-d / G3 / G6)都用同一 SA
- ✅ ADR-010 实施阶段(创建 PV/PVC/NetworkPolicy/PodSecurity/Secret)可扩展权限后继续用
- ✅ 后续 ADR-011 / ADR-012 等 NAS 相关工作可复用
- ✅ audit log 独立 trace:`protoPayload.authenticationInfo.principalEmail=infra-gcp-sa@...`,**不污染 <DECISION_MAKER> 本人操作记录**

#### 适用场景

- 长期方案,符合 SOUL.md "no shared credentials" 边界
- 适合**所有后续 NAS / 存储 / 网络相关 ADR**
- <DECISION_MAKER> 希望 agent team 长期可持续运作(不只是这一次)

---

### 1.2 方案 (d) — 借用 <DECISION_MAKER> OAuth 临时跑 ⚠ 临时

#### 实施步骤

```bash
# Step 1: <DECISION_MAKER> 在自己本机刷 token(浏览器交互)
gcloud auth login
# 浏览器走完 OAuth flow

# Step 2: 切换到过期账户(或 <DECISION_MAKER> 的常用账户)
gcloud config set account <YOUR_USER_ACCOUNT>@<YOUR_DOMAIN>

# Step 3: infra-gcp "借用" 真人 OAuth token
# (实际是沙盒里读 <DECISION_MAKER> 的 ~/.config/gcloud/ 已有 token)

# Step 4: 跑 Q6-a 5 条命令
gcloud compute interconnects list
gcloud compute interconnect-attachments list
gcloud compute networks peerings list
gcloud compute vpn-tunnels list
gcloud compute routers list

# Step 5: 把输出发回 architect-gcp 评审
```

#### 时间成本

| 步骤 | 耗时 | 谁来做 |
|---|---|---|
| Step 1 刷 token | 5 分钟(浏览器交互) | <DECISION_MAKER> |
| Step 2 切换账户 | 10 秒 | <DECISION_MAKER> |
| Step 3 infra-gcp 读取 | 5 秒 | infra-gcp 自动 |
| Step 4 跑 Q6-a | 1 分钟 | infra-gcp 自动 |
| Step 5 发回执 | 5 分钟 | infra-gcp |
| **总耗时** | **~12 分钟(<DECISION_MAKER> 5 分钟 + infra-gcp 7 分钟)** | — |
| **每次 token 过期后** | 重新跑 Step 1(5 分钟) | — |

#### 风险

| 风险 | 等级 | 缓解 |
|---|---|---|
| 真人 token 再次过期(2 个月后) | ⚠ 中 | 写日历提醒;或转 (b) |
| infra-gcp 误用 <DECISION_MAKER> 身份做范围外操作 | ⚠ 高 | 范围靠 <DECISION_MAKER> 自律,无技术限制 |
| audit log 污染:<DECISION_MAKER> 账号下出现 infra-gcp 操作 | ⚠ 中 | Q6-a 是 read-only,问题不大;若扩展到写权限会变成 compliance 问题 |
| 多人共用 真人账户(实际不会) | N/A | — |

#### 长期价值

- ❌ 无(临时方案,token 过期又要重来)
- ❌ 不符合 SOUL.md "no shared credentials" 边界(infra-gcp 借用真人身份 = 共享)
- ❌ audit log 无法区分 <DECISION_MAKER> 本人 vs infra-gcp 操作

#### 适用场景

- 应急(等不及 (b) 的 30 分钟)
- Q6-a 是 read-only,误用风险较低
- <DECISION_MAKER> 不打算长期让 agent team 运作(一次性项目)

---

### 1.3 方案 (e) — <DECISION_MAKER> 本机跑命令,贴输出 ⚠ 一次性

#### 实施步骤

```bash
# Step 1: <DECISION_MAKER> 在自己本机跑 5 条 Q6-a 命令
gcloud compute interconnects list
gcloud compute interconnect-attachments list
gcloud compute networks peerings list
gcloud compute vpn-tunnels list
gcloud compute routers list

# Step 2: 把输出贴回 chat / 文档
# → architect-gcp 评审
# → infra-gcp 不用动
```

#### 时间成本

| 步骤 | 耗时 | 谁来做 |
|---|---|---|
| Step 1 跑命令 | 5 分钟 | <DECISION_MAKER> |
| Step 2 贴输出 | 5 分钟 | <DECISION_MAKER> |
| **总耗时** | **~10 分钟** | — |
| **ADR-010 实施时** | 重新配 SA 或再贴输出 | — |

#### 风险

| 风险 | 等级 | 缓解 |
|---|---|---|
| <DECISION_MAKER> 误把敏感信息贴出来 | ⚠ 中 | 输出前手动 review,删除敏感字段 |
| ADR-010 实施时问题复发(agent 仍无身份) | ⚠ 高 | 提前转 (b) |
| infra-gcp 完全被绕过 | N/A | 此次绕过,下次还得绕过 |

#### 长期价值

- ❌ 无(一次性,问题没解决)
- ❌ infra-gcp 没有任何身份基础设施
- ❌ 下一个 ADR(Q6-d / G3 / G6)还得再走一遍

#### 适用场景

- 极应急(Q6-a 急需结论,且 (b)/(d) 都走不通)
- <DECISION_MAKER> 决定**完全不让 infra-gcp 拥有 GCP 身份**(只让 architect-gcp 评审,不让 agent 执行)
- ⚠ **不推荐** —— 这等于把 infra-gcp 降级成"只读 advisor"

---

## 2. 决策矩阵(综合评分)

| 维度 | 权重 | (b) SA | (d) 借 token | (e) 本机跑 |
|---|---|---|---|---|
| **时间成本** | 25% | 3 分钟 ✅ | 12 分钟 ⚠ | 10 分钟 ⚠ |
| **符合 SOUL.md 边界** | 25% | ✅ 完全符合 | ⚠ 借用真人身份 | N/A(绕过) |
| **长期可复用** | 20% | ⭐⭐⭐ | ⭐ | ❌ |
| **audit log 干净** | 15% | ✅ SA 独立 trace | ⚠ 污染 真人账户 | ✅ <DECISION_MAKER>操作 |
| **安全性(JSON key)** | 10% | ⚠ 中(需手工保密) | ✅ 不产生新凭证 | ✅ 不产生新凭证 |
| **ADR-010 实施过渡** | 5% | ✅ 直接扩展权限 | ⚠ 仍要再配 | ❌ 仍要再配 |
| **加权总分** | 100% | **90/100** | **52/100** | **30/100** |

---

## 3. 关键判断点

### 3.1 架构师为什么强烈推荐 (b)

1. **架构师 lane 不下场操作 GCP** —— 但 (b) 让 **infra-gcp** 用**自己的 SA** 操作,**架构师仍然 0 操作**
2. **SOUL.md "no shared credentials"** —— (b) 是唯一完全符合的方案;(d) 借用 = 共享
3. **长期可持续** —— ADR-009 后续 4 个治理问题(Q6-d / G3 / G6 / 实施阶段)都能复用同一 SA
4. **audit log 干净** —— SA 独立 trace,不污染 <DECISION_MAKER>的 audit 记录
5. **30 分钟一次配齐** —— 比 (d) 频繁刷 token 长期省时间

### 3.2 (d) 的真正问题

不是"5 分钟刷 token 麻烦",而是:

- infra-gcp 借用 <DECISION_MAKER> 身份 = **agent 没有独立身份** = 违反 4-Bot team 设计
- audit log 无法区分"是 <DECISION_MAKER> 操作还是 infra-gcp 操作"
- ADR-010 实施阶段需要写权限时,(d) 路线直接撞墙(<DECISION_MAKER> 不会把真人 owner 权限给 infra-gcp 用)

### 3.3 (e) 的真正问题

不是"10 分钟跑命令",而是:

- 这次跑完,下一次呢?
- infra-gcp profile **完全没有身份基础设施**,等于这个 profile 是"只读 advisor"
- 与"infra-gcp = 实施 lane"的 4-Bot 设计**冲突**

---

## 4. 推荐实施顺序(如果选 b)

```text
1. <DECISION_MAKER> 在自己本机跑 Step 1-3 (创建 SA + 绑权限 + 生成 key)
2. <DECISION_MAKER> 手动 copy sa.json 到 /Users/<DECISION_MAKER>/.hermes/profiles/infra-gcp/secrets/
3. <DECISION_MAKER> 确认 secrets/ 目录权限 700,sa.json 权限 600
4. <DECISION_MAKER> 在 chat / Bot Chat 频道告诉 infra-gcp:"SA 已就绪,跑 activate-gcp-sa.sh"
5. infra-gcp 跑 activate 脚本(5 秒)
6. infra-gcp 跑 Q6-a 5 条命令
7. infra-gcp 按回执模板发 architect-gcp
8. architect-gcp 评审 → 生成 ADR-010
9. ADR-010 实施阶段(后续):扩展 SA 权限(roles/compute.securityAdmin / container.admin 等)
```

---

## 5. 给 <DECISION_MAKER> 的最终建议

> **走 (b)**。
>
> 30 分钟一次配齐,后续所有 ADR 都能复用。短期看似比 (d) 慢 25 分钟,长期看**节省 <DECISION_MAKER> 大量时间**(token 不会再过期,audit log 不会再污染,ADR-010 实施不会撞墙)。
>
> 如果 <DECISION_MAKER> 现在时间紧、Q6-a 等不到 30 分钟,**临时走 (d) 5 分钟跑 Q6-a 拿结论**,然后**事后补做 (b)**(在 ADR-010 实施前完成 SA 配置,转长期方案)。

---

## 6. 架构师重申边界

| 架构师能做 | 架构师不做 |
|---|---|
| ✅ 评审 SA 权限设计(最小权限) | ❌ 创建 SA |
| ✅ 评审 Q6-a 5 条命令选得对不对 | ❌ 跑 gcloud |
| ✅ 评审 Q6-a 回执结论 | ❌ 持有任何 GCP 凭证 |
| ✅ 生成 ADR-010(假设验证后) | ❌ 配 SA / bind role / 写 sa.json |
| ✅ 维护 ADR-009 / 决策树 / 本文档 | ❌ 替 <DECISION_MAKER> 拍板选 b/d/e |

---

> **作者声明**:本文档只做分析 + 文档化,不实施。任何 provision / apply / 凭证创建操作由 <DECISION_MAKER> 在自己本机(非沙盒)执行。
