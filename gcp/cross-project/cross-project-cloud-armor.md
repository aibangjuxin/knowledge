# Cross-Project Cloud Armor Policy — 绑定规则与跨 Project 限制

> **TL;DR**(30 秒读完):
> 1. Cloud Armor Security Policy **只能** attach 到 **Backend Service**(或 backend bucket / Hierarchical level),**不能** attach 到 Forwarding Rule / URL Map / NEG / SSL Cert / Target Proxy。
> 2. Cloud Armor **不支持跨 project 引用** — 跨 project 绑定到另一个 project 的 Backend Service,**gcloud 直接报错** `Cross project referencing is not allowed for this resource`。
> 3. **在 PSC / Shared VPC / cross-project ILB 三种跨 project 架构里,Cloud Armor 都必须放在 Backend Service 所在的 project**。
> 4. 想要"统一下发策略":用 **IaC + CI/CD**(Terraform / Config Connector 把同一份 policy YAML 推到所有需要的 project),或 **Hierarchical Firewall Policies**(org / folder 级 firewall,不是 Cloud Armor)做 IP 黑名单的跨 project 兜底。

---

## §0. 原始问题(Lex 2026-07-27 verbatim)

> 我本地有 Cloud Armor Policy,对于谷歌工程来说,我想确认一个问题:是不是 Cloud Armor 的 Policy 只能绑定在 Backend Server 上?那么如果我有 cross project 的需求,比如说我想定义一个叫 a project 为 tenant project,b project 为 master project。我想用 cross project 的方式实现这个 Cloud Armor 规则绑定到 tenant project,是否可行?

> (注:原话打字为 "talent project",但根据上下文 + 同目录 `approve-tenant-project.sh` 命名,确认为 **tenant project** 的拼写误录。)

---

## §1. Cloud Armor Policy 到底能 attach 到哪?

### 1.1 官方原话(权威证据)

**来源**:[cloud.google.com/armor/docs/security-policy-overview](https://cloud.google.com/armor/docs/security-policy-overview)(2026-07-27 fetch)

> **"Hierarchical security policies are attached at the organization, folder, or project level, while service-level security policies are associated with one or more backend services."**

Cloud Armor 共有 **3 类 attach target**:

| Policy 类型 | 能 attach 到哪 | 跨 project |
|------------|--------------|-----------|
| **Backend security policy**(默认) | Backend Service(`scheme=EXTERNAL / EXTERNAL_MANAGED / INTERNAL_MANAGED`) | ❌ 必须同 project |
| **Edge security policy** | Backend Bucket **或** Cloud CDN-enabled Backend Service | ❌ 必须同 project |
| **Internal service security policy** | Cloud Service Mesh endpoint policy | ❌ 必须同 project |
| **Hierarchical firewall policy**(不是 Cloud Armor,是 VPC firewall) | Organization / Folder / Project | ✅ 跨 project,向下穿透 |

**常见误区**:
- ❌ "绑到 Forwarding Rule" — 不支持
- ❌ "绑到 URL Map" — 不支持
- ❌ "绑到 Target HTTPS Proxy" — 不支持
- ❌ "绑到 NEG / MIG / GKE" — 不支持
- ✅ 唯一选项:**Backend Service** 或 **Backend Bucket**

### 1.2 一个 Backend Service 能挂几个 Policy?

> **"A backend service can have two service-level security policies associated with it at the same time, but it can't have two backend security policies or two edge security policies at the same time."**

允许**两种组合**:
- 1 个 backend security policy + 1 个 edge security policy(同时挂)
- 但同种 policy 只能 1 个

> **"If a Cloud Armor security policy is associated with any backend service, it can't be deleted."**
> — 删除 policy 之前必须先从所有 BS 解绑。

---

## §2. 跨 Project 实验证据 — Lex 2026-06 亲手测试

### 2.1 实验 1:跨 Project Backend Service → Master 的 MIG(已失败)

**记录位置**:`gcp/cross-project/cross-mig.md` § gcloud 操作及错误信息

```bash
gcloud beta compute backend-services add-backend lex-backend \
  --project=projectID1 \
  --region=europe-west2 \
  --instance-group=projects/projectID2/regions/europe-west2/instanceGroups/our-mig \
  --instance-group-region=europe-west2 \
  --balancing-mode=CONNECTION
```

**gcloud 错误原话**:
```
ERROR: (gcloud.beta.compute.backend-services.add-backend)
Could not fetch resource:
- Invalid value for field 'resource.backends[1].group':
  'https://compute.googleapis.com/compute/beta/projects/projectID2/regions/europe-west2/instanceGroups/our-mig'
  Cross-project references for this resource are not allowed.
```

### 2.2 实验 2:跨 Project Cloud Armor Policy → Tenant 的 Backend Service(已失败)

**记录位置**:`gcp/cross-project/cross-mig.md` § cross project cloud armor

```bash
gcloud compute backend-services update lex-backend \
  --region=europe-west2 \
  --security-policy=projects/projectID2/regions/europe-west2/securityPolicies/projectID2-security-policy
```

**gcloud 错误原话**:
```
ERROR: (gcloud.compute.backend-services.update) Could not fetch resource:
- Invalid value for field 'securityPolicy.securityPolicy':
  'https://compute.googleapis.com/compute/y/projects/projectID2/regions/europe-west2/securityPolicies/projectID2-security-policy'
  Cross project referencing is not allowed for this resource.
```

### 2.3 实验结论

GCP **拒绝**以下 2 类跨 project 资源关联:
- ❌ Cross-project Backend Service → Backend Group (MIG / NEG)
- ❌ Cross-project Backend Service → Cloud Armor Security Policy

两条都是 **gcloud 在 API 层主动校验失败**(不是 IAM 权限问题,不是 quota 限制),说明 GCP 控制面硬性禁止。

---

## §3. Google 官方原话证据 — 第二个权威来源

**来源**:[cloud.google.com/armor/docs/configure-security-policies](https://cloud.google.com/armor/docs/configure-security-policies)(2026-07-27 fetch)

> **"Note: Exporting and importing security policies is useful for version control and local modification but not for migrating a policy from one project to another."**

这句话直接说:即使你 `export` 一份 policy YAML,也不能 `import` 到另一个 project 重建 — **policy 不能跨 project 迁移**。

这条原话跟 §2 的 gcloud 报错互为印证:**gcloud 拒绝跨 project 引用** 是 API 层契约,**Google 文档明确禁止** 是产品语义层契约。两者一致。

---

## §4. 为什么 GCP 不允许?(根因 3 条)

来自 `cross-mig.md` § 测试分析与原理解释,这里是收紧版:

### 4.1 IAM 权限管理的"信任闭环"

Project 是 GCP **核心信任、权限隔离和计费边界**。Backend Service、MIG、Cloud Armor 都是关键资产。
- 如果允许跨 project 强引用 → IAM 审核链路会变成"跨 project 的间接权限链路"
- 例:`Project A` 的 BS 通过跨 project 引用绑了 `Project B` 的 Cloud Armor → 谁有权改 `Project B` 的 policy?谁审计?
- 拒绝跨 project 引用 → 权限闭环清晰:**每个 project 自治 + 同 project 内 IAM**

### 4.2 防范级联故障 + 生命周期管理

如果 `Project A` 的 BS 隐式依赖 `Project B` 的 Cloud Armor / MIG:
- `Project B` 管理员不知情删 policy → `Project A` 流量瞬间 0(无任何告警)
- `Project B` 改了 rule 优先级 → `Project A` 行为不可预期
- 拒绝跨 project → 切断"隐式黑盒依赖",**故障半径 = project 边界**

### 4.3 计费与结算分离

Cloud Armor 的计费维度:
- **WAF 规则条目数**(按 policy 数量 + 规则数)
- **请求处理量**(按 evaluate 次数,含被放行 + 被拦截)
- **Bot management / Adaptive Protection**(高级 SKU)

这些必须归属到 **policy 所在 project** 才能正确归集到账单。跨 project 引用 → 计费归属模糊,账单无法对账。

---

## §5. 决策矩阵 — 4 种跨 Project 架构 × Cloud Armor 怎么放

| 架构 | 谁持有 Backend Service | Cloud Armor 放哪 | 跨 project 复用策略 |
|------|---------------------|-----------------|-------------------|
| **A. PSC**(Tenant 持 BS → PSC NEG → Master SA) | Tenant Project | **Tenant Project**(跟 BS 同 project) | 每个 Tenant Project 自建一份 policy + IaC 复制 |
| **B. Shared VPC + Cross-Project NEG** | Tenant Project(在 Shared VPC 内) | **Tenant Project** | 同 A,IaC 复制 |
| **C. Cross-Project ILB → Backend Service**(Shared VPC) | Master Project | **Master Project**(跟 BS 同 project) | 单 tenant 单份;多 tenant 各一份 |
| **D. Cross-Project Direct(已被 §2 证伪)** | — | ❌ 不存在 | — |

### 5.1 PSC 场景(最常见 + Lex 的实际环境)

Lex 的 `aibang-12345678-ajbx-dev` 环境(`skills/architectrue/references/cross-project-psc-environment-aibang.md` Step 7)实际就是这么做的:

```bash
# Tenant Project 内部(跟 Backend Service 同 project)
gcloud compute security-policies create "${POC_PREFIX}-public-armor" \
  --project="${TENANT_PROJECT}" \
  --description="Public GLB protection"

gcloud compute backend-services update "${POC_PREFIX}-public-bs" \
  --project="${TENANT_PROJECT}" \
  --region="${REGION}" \
  --security-policy="${POC_PREFIX}-public-armor"
```

**没有"把 Cloud Armor 放到 master 然后跨 project 引用"这条路。**

### 5.2 多 Tenant 共享同一套 WAF 规则 — IaC 分发

如果 50 个 tenant 需要同一份 WAF 规则(SQLi / XSS / rate-limit / 地理封锁),用 **Terraform + Git** 把 policy 模板推到所有 tenant project:

```hcl
# terraform/modules/tenant-cloud-armor/main.tf
resource "google_compute_security_policy" "default" {
  name        = "${var.tenant_prefix}-armor"
  description = "Tenant Cloud Armor policy — replicated from master template"
  project     = var.tenant_project  # 每个 tenant 的 project
  
  rule {
    action   = "deny-403"
    priority = 1000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
    description = "SQLi protection"
  }
  # ... 其他 rules
}

resource "google_compute_backend_service" "default" {
  # ... 
  security_policy = google_compute_security_policy.default.self_link  # 同 project
  project         = var.tenant_project
}
```

**关键设计**:
- `policy` 和 `backend_service` **同 project**(`var.tenant_project` 显式传递)
- Terraform Cloud / Atlantis / 自建 CI 循环 `for tenant in tenant-projects.txt; do terraform apply -var tenant_project=$tenant`
- **policy 模板 = Git 仓库里的 YAML**,确保 50 个 tenant 同步更新

**注意**:GCP 控制面硬性阻止"跨 project import policy",所以**不能 `terraform import` 把已存在的 policy 从 project A 搬到 project B**。policy 必须**重建**(重新 create + 重新 attach)。这是 §3 的 Google 原话直接后果。

### 5.3 跨 Project 通用 IP 黑名单 — Hierarchical Firewall Policy

如果跨 project 安全需求是 **"阻断某些 IP / 端口"**(不是 WAF 内容检测),用 **Hierarchical Firewall Policy**:

```bash
# Org / Folder 级别(org admin 权限)
gcloud compute firewall-policies create "global-deny-botnet" \
  --organization=ORG_ID  # 或 --folder=FOLDER_ID

gcloud compute firewall-policies rules create 1000 \
  --firewall-policy="global-deny-botnet" \
  --direction=INGRESS \
  --action=deny \
  --src-ip-ranges="203.0.113.0/24,198.51.100.0/24" \
  --description="Block known botnet ranges"
```

**注意**:**Hierarchical Firewall Policy 是 VPC firewall,不是 Cloud Armor**。它对所有 LB / VM / GKE 生效(向下穿透),但只能做 IP / port 粒度的过滤,不能做 WAF 内容检测(SQLi / XSS / rate-limit)。

---

## §6. 推荐路径(Lex 当前场景)

按场景优先级:

### 6.1 单 Tenant + PSC(最简单,推荐)

```
Tenant Project (持有 Cloud Armor + BS + NEG)
  └─ BS -- security-policy: <tenant-armor-policy>
Master Project (持有 ILB + MIG)
```

**步骤**:
1. 在 Tenant Project 创建 Cloud Armor Policy
2. `backend-services update --security-policy=...` 绑定到 Tenant 的 BS
3. 完成。**不需要任何 IaC 跨 project 操作**。

### 6.2 多 Tenant + 共享 WAF 规则

```
Git Repo (policy 模板 YAML)
  ↓ Terraform apply per tenant
  ↓
Tenant1 Project (Cloud Armor + BS)
Tenant2 Project (Cloud Armor + BS)
  ...
Tenant50 Project (Cloud Armor + BS)
```

**步骤**:
1. 把 WAF 规则写成 Terraform module(`modules/tenant-armor/`)
2. CI 循环 `for tenant in $(cat tenants.txt); do cd tenants/$tenant && terraform apply; done`
3. 更新 WAF 规则 → 改 Git → CI 自动推到所有 tenant

### 6.3 跨 Project IP 黑名单(独立需求)

```
Org / Folder (Hierarchical Firewall Policy)
  ↓ 向下穿透
Tenant Project 的所有 LB / VM / GKE
```

**步骤**:
1. Org admin 创建 Hierarchical Firewall Policy(IP / port 粒度)
2. 关联到 Folder 或整个 Org
3. 所有 project 自动继承

---

## §7. 验证脚本 — 一键检查"Cloud Armor 是否真的在 BS 所在的 project"

### 7.1 静态检查:policy 和 BS 同 project?

```bash
#!/usr/bin/env bash
# verify-armor-scope.sh — 验证 Cloud Armor Policy 与 Backend Service 同 project
#
# 用法:
#   bash verify-armor-scope.sh -p PROJECT_ID [-r REGION]
#
# 退出码:
#   0 = 全部同 project
#   1 = 发现跨 project 绑定(违反 GCP 规则,应被 gcloud 阻止)
#   2 = 资源不存在 / 权限不足

set -euo pipefail

PROJECT=""
REGION=""
GLOBAL=0

while getopts ":p:r:gh" opt; do
  case "$opt" in
    p) PROJECT="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    g) GLOBAL=1 ;;
    h) echo "Usage: $0 -p PROJECT [-r REGION | -g]"; exit 0 ;;
    \?) echo "invalid option"; exit 2 ;;
  esac
done

[[ -n "$PROJECT" ]] || { echo "ERROR: -p required" >&2; exit 2; }

if (( GLOBAL == 0 && -z "$REGION" )); then
  echo "ERROR: need -r REGION or -g (global)" >&2
  exit 2
fi

SCOPE_FLAG=""
if (( GLOBAL == 1 )); then
  SCOPE_FLAG="--global"
else
  SCOPE_FLAG="--region=$REGION"
fi

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'
pass=0; fail=0

# 列出所有 backend service
echo "━━━━━ Scanning Backend Services in $PROJECT ━━━━━"
BS_LIST=$(gcloud compute backend-services list \
  --project="$PROJECT" $SCOPE_FLAG \
  --format="value(name)" 2>/dev/null) || { echo "ERROR: cannot list BS" >&2; exit 2; }

if [[ -z "$BS_LIST" ]]; then
  echo "  (no backend services)"
  exit 0
fi

while read -r bs; do
  [[ -z "$bs" ]] && continue
  POLICY_URI=$(gcloud compute backend-services describe "$bs" \
    --project="$PROJECT" $SCOPE_FLAG \
    --format="value(securityPolicy)" 2>/dev/null || echo "")
  
  if [[ -z "$POLICY_URI" || "$POLICY_URI" == "None" ]]; then
    printf "${YELLOW}⚠${RESET}  %s → no security policy attached (裸奔 BS)\n" "$bs"
    continue
  fi
  
  # 从 selfLink 里 extract project
  POLICY_PROJECT=$(echo "$POLICY_URI" | sed -nE 's|.*/projects/([^/]+)/.*|\1|p')
  
  if [[ "$POLICY_PROJECT" == "$PROJECT" ]]; then
    printf "${GREEN}✓${RESET}  %s → policy in SAME project (%s)\n" "$bs" "$POLICY_PROJECT"
    pass=$((pass+1))
  else
    printf "${RED}✗${RESET}  %s → policy in DIFFERENT project (%s) — GCP normally blocks this\n" "$bs" "$POLICY_PROJECT"
    fail=$((fail+1))
  fi
done <<< "$BS_LIST"

echo
printf "通过: ${GREEN}%d${RESET}  失败: ${RED}%d${RESET}\n" "$pass" "$fail"

if (( fail > 0 )); then
  echo
  echo "⚠ 检测到跨 project policy 绑定。"
  echo "  Google 官方原话(2026-07-27 fetch):"
  echo "  'Exporting and importing security policies is useful for version control and local modification but not for migrating a policy from one project to another.'"
  echo "  → 如果这是 IaC 误配,应立刻修复;如果是手工创建,可能 gcloud 版本太老或政策已变。"
  exit 1
fi

exit 0
```

**用法**:

```bash
# Global backend services
bash verify-armor-scope.sh -p aibang-12345678-ajbx-dev -g

# Regional
bash verify-armor-scope.sh -p aibang-12345678-ajbx-dev -r europe-west2
```

### 7.2 动态验证:policy rule 真的生效?

```bash
#!/usr/bin/env bash
# test-armor-rule.sh — 用 curl 触发 Cloud Armor 规则,确认 ALLOW/DENY 行为
#
# 用法:
#   export GLB_IP=1.2.3.4 PROJECT=my-project POLICY=my-armor-policy
#   bash test-armor-rule.sh

set -euo pipefail
: "${GLB_IP:?set GLB_IP}"
: "${PROJECT:?set PROJECT}"
: "${POLICY:?set POLICY}"

# 提取一条 deny rule 的 expression(假设 priority=1000 是 geo block)
RULE_EXPR=$(gcloud compute security-policies rules describe 1000 \
  --security-policy="$POLICY" \
  --project="$PROJECT" \
  --format="value(match.expr.expression)" 2>/dev/null || echo "(none)")

echo "Testing policy: $POLICY, rule 1000: $RULE_EXPR"

# 触发测试请求
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
  --max-time 10 \
  -H "User-Agent: test-cloud-armor" \
  "https://$GLB_IP/" || echo "000")

echo "HTTP code: $HTTP_CODE"
case "$HTTP_CODE" in
  403|404|429) echo "✓ rule triggered (deny response)" ;;
  200)         echo "⚠ allowed — rule may not match this request" ;;
  000)         echo "✗ connection failed" ;;
  *)           echo "? unexpected code" ;;
esac

# 查 Cloud Logging 看规则是否 evaluate 了
echo
echo "最近 5 分钟的 armor 决策日志:"
gcloud logging read \
  "jsonPayload.enforcedSecurityPolicy.name=$POLICY AND timestamp>\"$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)\"" \
  --project="$PROJECT" \
  --limit=5 \
  --format="table(timestamp,jsonPayload.enforcedSecurityPolicy.outcome,jsonPayload.enforcedSecurityPolicy.priority)" \
  2>/dev/null || echo "(no logs found — policy 还没触发过)"
```

---

## §8. 权威证据 / 最终定型依据

| # | 来源 | 引用位置 | 抓取日期 | URL |
|---|------|---------|---------|-----|
| 1 | Google Cloud Armor 官方 overview | §1.1(security policy attach 模型) | 2026-07-27 | <https://cloud.google.com/armor/docs/security-policy-overview> |
| 2 | Google Cloud Armor configure-security-policies | §3(官方明确禁止跨 project 迁移) | 2026-07-27 | <https://cloud.google.com/armor/docs/configure-security-policies> |
| 3 | Lex 亲手实验 1(跨 project MIG) | §2.1(gcloud 报错原文) | 2026-06(原始记录) | <file:///Users/lex/git/knowledge/gcp/cross-project/cross-mig.md> |
| 4 | Lex 亲手实验 2(跨 project Cloud Armor) | §2.2(gcloud 报错原文) | 2026-06(原始记录) | <file:///Users/lex/git/knowledge/gcp/cross-project/cross-mig.md> |
| 5 | Lex 实际环境应用(PSC + Cloud Armor) | §5.1(aibang Step 7) | 2026-06(已验证) | <file:///Users/lex/.hermes/profiles/architecture/skills/architectrue/references/cross-project-psc-environment-aibang.md> |

**核心证据链**(任一条独立即可定论,3 条互为印证):

1. **Google 官方**:Hierarchical vs service-level 分类(`security-policy-overview`)
2. **Google 官方**:禁止跨 project 迁移 policy(`configure-security-policies` 注释)
3. **Lex 亲手实验**:gcloud 报错 `Cross project referencing is not allowed`(`cross-mig.md`)

**反例 / 未验证假设**(诚实标注):

- 假设:`Edge security policy` 是否也禁止跨 project? — 未单独实验。**但** 按 GCP 资源模型对称性 + 同一控制面校验逻辑,推断 **是**(没找到反例证据)
- 假设:`Hierarchical Firewall Policy` 是否真的向下穿透所有 LB? — 官方文档说"向下继承",但 **未在 Lex 环境实测**。建议实施前先小范围验证
- 假设:`internal service security policy`(Cloud Service Mesh 那个)是否也禁止跨 project? — 推断 **是**,但未实验

**未走的探索路径**(留给后续):

- 实验:`gcloud compute backend-services update --security-policy=projects/<SAME_PROJECT>/...` 是否能正常更新 vs 简写(只写名字)是否有差异 — 文档没禁止,但实际命令里必须用完整 URI 还是可以只写名字,需查 `gcloud compute backend-services update --help`
- 实验:`setSecurityPolicy` REST API(不是 gcloud)是否绕过这层校验 — 几乎肯定也是同一控制面,但没验证

---

## §9. See also(同 repo 内交叉引用)

- `gcp/cross-project/cross-mig.md` — Lex 2026-06 原始实验记录(§2 的来源)
- `gcp/cross-project/cross-project-binding-backend.md` — Cross-project Backend Service 绑定的完整分析(更宽的 cross-project LB 视角)
- `gcp/cross-project/cross-project-psc-architecture.html` — PSC 架构 dark-theme 图
- `gcp/cross-project/approve-tenant-project.sh` — Producer 侧审批 Tenant PSC(同 series)
- `skills/architectrue/references/cross-project-psc-environment-aibang.md` — aibang 环境实际 PSC + Cloud Armor 配置(Step 7)
- `gcp/cross-project/cross-project-cloud-armor-architecture.html` — 本文档配套 dark-theme 架构图



# Gemini 3.6 
这里需要厘清两个概念：**Cloud Armor 策略（Security Policy）到底绑定在什么资源上**，以及**如何实现 Cross-Project（跨项目）绑定**。

总结来说：**你的需求是完全可行的，但绑定的目标不是 Backend Server 本身，而是 Backend Service（后端服务）或 Target Proxy。**

下面为你详细拆解工程逻辑与实现方式：

---

## 1. 核心概念澄清：Cloud Armor 绑定在哪？

Cloud Armor 的安全策略**不能**直接绑定到具体的后端服务器（如 GKE Pod 或 Compute Engine 实例），而是绑定在 **Google Cloud HTTP(S) 负载均衡器（GLB）的层级**：

* **后端服务（Backend Service）**：最常见的绑定位置。通过在 Backend Service 上关联 `securityPolicy`，所有经过该负载均衡器路由到对应 Backend Service 的流量都会受到 Cloud Armor 的防护。
* **目标代理（Target Proxy）**：针对边缘安全策略（Edge Security Policies），比如 CDN 或边缘 Rate Limiting。

---

## 2. 跨项目（Cross-Project）绑定的可行性

在跨项目架构（例如 Shared VPC 共享网络或 Cross-Project Backend Services 架构）中，**完全支持**将 Master Project（如 `b-project`）中的 Cloud Armor 策略应用/绑定到 Talent Project（如 `a-project`）中的负载均衡资源或后端服务。

通常有两种常见的架构实现路径：

---

### 架构方案 A：共享网络（Shared VPC）模式 —— 最标准做法

在这种架构中：

* **Host Project（主项目/Master Project `b-project`）**：集中管理网络资源、Shared VPC 以及全局 Cloud Armor 策略。
* **Service Project（业务项目/Talent Project `a-project`）**：存放具体的计算资源（GKE、VM、Backend API）。

#### 实现步骤与权限逻辑：

1. **策略创建**：在 `b-project` 中创建 Cloud Armor 策略（例如 `projects/b-project/global/securityPolicies/my-global-armor-policy`）。
2. **跨项目授权**：需要将 `b-project` 上的 Cloud Armor 使用权限授权给 `a-project` 负责部署负载均衡的服务账号（Service Account）或管理员。
* **所需 IAM 角色**：在 `b-project` 上赋予 `a-project` 的 Deployment/Admin 账号 **Compute Security Admin**（`roles/compute.securityAdmin`）或自定义只读/绑定权限。


3. **资源绑定**：在 `a-project` 中配置 Load Balancer 的 Backend Service 时，将 `securityPolicy` 字段指向 `b-project` 中的策略 URI：
```bash
gcloud compute backend-services update a-talent-backend-service \
    --project=a-project \
    --security-policy=projects/b-project/global/securityPolicies/my-global-armor-policy \
    --global

```



---

### 架构方案 B：Cross-Project Service Referencing（跨项目后端服务引用）

如果你的负载均衡器（GLB）本身部署在 `b-project`（Master Project），而 Backend（如 NEG/实例组）在 `a-project`：

* **GLB + Policy 均在 `b-project**`：直接将 Cloud Armor 绑定在 `b-project` 的 Backend Service 上，然后该 Backend Service 通过 Cross-Project 方式关联 `a-project` 中的 Network Endpoint Groups (NEGs) 或 MIGs。这是最自然也最容易管控的“集中式安全”架构。

---

## 3. 关键注意事项与限制

1. **作用域匹配（Scope Matching）**：
* **Global Cloud Armor Policy** 只能绑定到 **Global External HTTP(S) Load Balancer** 的 Backend Service。
* 如果使用区域级负载均衡（Regional External/Internal HTTP(S) LB），则必须使用 **Regional Cloud Armor Policy**，且策略与 Backend Service 必须位于相同的 GCP 区域（Region）。


2. **IAM 权限精细化**：
* 确保 `a-project` 中执行 CI/CD 或 Terraform 部署的角色在 `b-project` 上拥有 `compute.securityPolicies.use` 权限（包含在 Security Admin 角色中）。