# PSC NEG 完整需求清单 — 跨 project + L7 managed LB 必备条件

> **本节是"在跨 project 场景下,要成功创建并使用 PSC NEG,必须满足的所有前置条件"的完整 checklist**。
>
> **架构师 lane 边界**:本文档只做需求清单 + 边界标注,**不实施任何 provision / apply / gcloud / terraform**。infra-gcp 跑完验收清单后回执架构师。
>
> **状态**:Reference · Date: 2026-09-04 · Author: **architect-gcp** · Reviewers: **infra-gcp** / 业务方 / **qa-gcp**
>
> **核心问题**:
> 1. 在 GCP 上创建并使用 PSC NEG 跨 project,**必须满足哪些前置条件**?
> 2. 这些条件**谁负责、什么时候建、怎么验证**?
> 3. **业务方被坑过的点**(Org Policy / API enable / network attachment)如何避免?
>
> **配套文档**:
> - 上游概念:[`why-using-global-external-managed-http-https.md`](./why-using-global-external-managed-http-https.md) — 为什么这个 LB scheme
> - 概念澄清:[`../../psa-psc/psc-concept.md` §4.5](../../psa-psc/psc-concept.md) — PSC NEG 本质
> - 已实现架构:[`public-tls-cross-project-implementation.html`](./public-tls-cross-project-implementation.html)
> - 实施记录:[`tenant-tls-setup-https.md`](./tenant-tls-setup-https.md) — 业务方生产实施

---

## 0. 一句话总结

> **PSC NEG 跨 project 工作的"5 道闸门"**:
> 1. ✅ LB Scheme = `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`(公网 + Global + L7 + Managed)
> 2. ✅ Org Policy 显式放行 EXTERNAL 系 LB(默认只放行 INTERNAL)
> 3. ✅ GCP APIs 全部 enable(8+ 个 API)
> 4. ✅ Producer 端 Service Attachment 配 ACCEPT_MANUAL + consumer allowlist
> 5. ✅ Producer Backend Service 协议对齐(协议版本 / port / 健康检查)
>
> **5 道闸门任意一道未通过,PSC NEG 跨 project 就 fail**。

---

## 1. PSC NEG 的本质(回到 §4.5.1 一句话定义)

> **PSC NEG = 一个 NEG (Network Endpoint Group)**,类型 `PRIVATE_SERVICE_CONNECT`
>
> 必须挂在 Load Balancer 后面,作为 LB 的 backend
> 然后通过 LB 的 VIP 访问 Producer

→ **PSC NEG 不是独立资源**——它**依附于 LB**,所以**所有前置条件本质都是"LB 跟跨 project 工作的前置条件"**。

---

## 2. 5 道闸门完整清单

### 2.1 闸门 1:Load Balancing Scheme 必须是 MANAGED 系列

**约束**:
- ✅ `EXTERNAL_MANAGED`(regional 或 global)
- ✅ `INTERNAL_MANAGED` 系列**不支持** PSC NEG 作为 backend
- ❌ 经典 `EXTERNAL` 系**不支持** NEG 作为 backend

**业务方方案**:
- 业务方架构 = `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`(详见 [`why-using-global-external-managed-http-https.md`](./why-using-global-external-managed-http-https.md))

**负责方**:架构师(已确定 scheme)+ infra-gcp(创建 LB 时严格使用此 scheme)

**验收命令**(infra-gcp 跑):
```bash
# 验证 Backend Service 配的是 MANAGED scheme
gcloud compute backend-services describe <BS_NAME> \
  --global \
  --format="value(loadBalancingScheme)"
# 期望:EXTERNAL_MANAGED

# 验证 URL Map 引用的 Backend Service 协议
gcloud compute url-maps describe <URL_MAP_NAME> \
  --global \
  --format="value(defaultService)"
```

**失败判定**:如果返回 `EXTERNAL` 或 `INTERNAL`,PSC NEG 创建会失败 / 警告。

---

### 2.2 闸门 2:Org Policy 显式放行 EXTERNAL 系 LB(最常见阻塞)

**约束**:
- GCP 组织级 Org Policy `compute.loadBalancing.allowedLoadBalancingScheme` **默认只放行 `INTERNAL`**
- 创建 `EXTERNAL_MANAGED` LB 会被**组织策略拒绝**

**业务方踩过的坑**(从 `tenant-tls-setup-https.md`):
> "这条 LB 链默认被组织级 Org Policy 限制:`compute.loadBalancing.allowedLoadBalancingScheme` 只放行 `INTERNAL`,`EXTERNAL` 全系被拒。"

**负责方**:
- **业务方 / Security**:申请 Org Policy 扩展(1-3 工作日)
- **架构师**:提供申请模板(见 [`why-using-global-external-managed-http-https.md` §9](./why-using-global-external-managed-http-https.md))
- **infra-gcp**:在 LB 创建**之前**验证 Org Policy 已扩展

**Org Policy 申请模板**:
```yaml
# 给 Security / Org Policy Owner
apiVersion: cloudresourcemanager.cnrm.cloud.google.com/v1beta1
kind: Project
metadata:
  annotations:
    compute.loadBalancing.allowedLoadBalancingScheme:
      - INTERNAL
      - INTERNAL_MANAGED
      - EXTERNAL_MANAGED
      # 显式列出(推荐)
      - GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS
```

**验收命令**(infra-gcp 跑):
```bash
# 列出项目级 Org Policy
gcloud org-policies list --project=<PROJECT_ID>

# 检查 compute.loadBalancing.allowedLoadBalancingScheme
gcloud org-policies describe \
  compute.loadBalancing.allowedLoadBalancingScheme \
  --project=<PROJECT_ID>
# 期望:EXTERNAL_MANAGED / GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS 都在允许列表

# 如果未生效,infra-gcp 不能盲目推进 LB 创建(避免 401 / 403 错误)
```

**失败判定**:Org Policy 未扩展 → `gcloud compute backend-services create` 报 `Organization Policy constraint constraints/compute.loadBalancing.allowedLoadBalancingScheme violated`。

---

### 2.3 闸门 3:GCP APIs 全部 enable(8+ 个)

**约束**:Consumer + Producer 两端**必须 enable 以下 APIs**:

| API | Consumer (Talent) | Producer (Master) | 作用 |
|---|---|---|---|
| `compute.googleapis.com` | ✅ | ✅ | Backend Service / URL Map / LB |
| `container.googleapis.com` | ✅ | ✅ | GKE 集群 |
| `servicenetworking.googleapis.com` | ✅ | ✅ | Private Service Connect 底层 |
| `dns.googleapis.com` | ✅ | ✅ | 内部 DNS 解析 |
| `cloudresourcemanager.googleapis.com` | ✅ | ✅ | 项目 IAM / Org Policy |
| `iam.googleapis.com` | ✅ | ✅ | Service Account |
| `monitoring.googleapis.com` | ✅ | ✅ | Health Check + 监控 |
| `logging.googleapis.com` | ✅ | ✅ | Audit log |
| `certificatemanager.googleapis.com` | ✅ | ⚠️ | 公网 cert 管理 |

**负责方**:
- **infra-gcp** 负责两端 enable
- **业务方**:不需要直接管

**验收命令**(infra-gcp 跑):
```bash
# Consumer 端 enable
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  servicenetworking.googleapis.com \
  dns.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  certificatemanager.googleapis.com \
  --project=<CONSUMER_PROJECT_ID>

# Producer 端 enable
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  servicenetworking.googleapis.com \
  dns.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  --project=<PRODUCER_PROJECT_ID>
```

**失败判定**:API 未 enable → `API not enabled on project` 错误。

---

### 2.4 闸门 4:Producer 端 Service Attachment 配 ACCEPT_MANUAL + consumer allowlist

**约束**:
- Producer 端的 **Service Attachment** 必须:
  - `connectionPreference = ACCEPT_MANUAL`(手动审批连接)
  - `consumerAcceptLists` 包含 Consumer 项目的 project number 和 `10`(限额)
  - 或 `ACCEPT_AUTOMATIC`(自动接受所有 Consumer,**不推荐,缺安全控制**)

**负责方**:
- **infra-gcp** 在 Producer 端配
- **架构师**确认 connectionPreference 选 `ACCEPT_MANUAL`(业务方生产环境)

**YAML 模板**:
```yaml
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeServiceAttachment
metadata:
  name: producer-svc-att
  namespace: producer
spec:
  location: us-east4
  description: "Service Attachment for cross-project API"
  enableProxyProtocol: false
  connectionPreference: ACCEPT_MANUAL  # ← 手动审批
  natSubnets:
    - projects/<PRODUCER_PROJECT_ID>/regions/us-east4/subnetworks/psc-nat-subnet
  targetService: projects/<PRODUCER_PROJECT_ID>/regions/us-east4/forwardingRules/producer-ilb-fr
  consumerAcceptLists:
    - projectNumberOrId: "<CONSUMER_PROJECT_NUMBER>"
      connectionLimit: 10
```

**验收命令**(infra-gcp 跑):
```bash
# 验证 Service Attachment 状态
gcloud compute service-attachments describe <SA_NAME> \
  --region=<REGION> \
  --project=<PRODUCER_PROJECT_ID> \
  --format="value(connectionPreference,consumerAcceptLists)"

# 期望:connectionPreference = ACCEPT_MANUAL
# consumerAcceptLists 包含 Consumer project

# 查看已接受的 endpoint(等 Consumer 连接)
gcloud compute service-attachments list --project=<PRODUCER_PROJECT_ID> --format="value(name,connectedEndpoints)"
```

**失败判定**:
- `connectionPreference = ACCEPT_AUTOMATIC` → 业务方生产环境禁用
- consumer project 未在 allowlist → PSC NEG 创建失败
- 连接数超 limit → Consumer 无法再连接

---

### 2.5 闸门 5:Producer Backend Service 协议对齐

**约束**(最容易踩的坑):

| 维度 | Consumer Backend Service | Producer Backend Service | 必须对齐 |
|---|---|---|---|
| **protocol** | HTTPS(portName=https)| TCP / HTTP / HTTPS | ⚠️ 协议不同 → 流量不通 |
| **port** | 443 (HTTPS)| 443 (TCP)| ✅ 同 |
| **健康检查** | HTTPS / TCP | HTTPS / TCP / HTTP | ⚠️ HC 类型要对齐 |
| **Backend 协议** | HTTPS (LB 到 PSC NEG)| 看 Producer 端具体后端 | ⚠️ L7 跟 L4 不能混 |

**业务方踩过的坑**(从 `tenant-tls-setup-https.md` §3.12):
> "重建 PSC NEG(delete + create)— 因为 backend service 改 protocol 后,需要重连 SA"

→ **改 protocol 必须重建 PSC NEG**,否则连接还在老协议上。

**负责方**:
- **架构师**确定协议(本架构 = 全 HTTPS)
- **infra-gcp** 按协议建 Backend Service / Health Check / PSC NEG

**验收命令**(infra-gcp 跑):
```bash
# Consumer Backend Service 协议
gcloud compute backend-services describe <CONSUMER_BS> \
  --global \
  --format="value(protocol,portName,healthChecks)"

# Producer Backend Service 协议
gcloud compute backend-services describe <PRODUCER_BS> \
  --region=<REGION> \
  --project=<PRODUCER_PROJECT_ID> \
  --format="value(protocol,healthChecks)"

# Health Check 协议
gcloud compute health-checks describe <HC_NAME> \
  --format="value(type,port)"
```

**失败判定**:
- Consumer 端 `protocol=HTTPS` 但 Producer 端 `protocol=TCP` → 流量不通
- Health Check 类型错配 → backend 一直 unhealthy

---

## 3. 架构师完整 checklist(给 infra-gcp / qa-gcp)

### 3.1 Pre-provision checklist(LB 创建前必查)

| # | 闸门 | 验证命令 / 文件 | 期望值 | 负责方 |
|---|---|---|---|---|
| 1 | LB Scheme | `gcloud compute backend-services describe ... --format="value(loadBalancingScheme)"` | `EXTERNAL_MANAGED` | 架构师 + infra-gcp |
| 2 | Org Policy | `gcloud org-policies describe compute.loadBalancing.allowedLoadBalancingScheme` | 包含 `EXTERNAL_MANAGED` / `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` | 业务方 + Security |
| 3 | APIs (Consumer)| `gcloud services list --enabled --project=<CONSUMER_PROJECT_ID>` | 含 9 个核心 API | infra-gcp |
| 3 | APIs (Producer)| `gcloud services list --enabled --project=<PRODUCER_PROJECT_ID>` | 含 8 个核心 API | infra-gcp |
| 4 | Service Attachment | `gcloud compute service-attachments describe <SA> ...` | `connectionPreference=ACCEPT_MANUAL` + consumer allowlist 包含 Consumer | infra-gcp |
| 5 | Backend Service 协议 | `gcloud compute backend-services describe ... --format="value(protocol,healthChecks)"` | Consumer HTTPS / Producer 协议对齐 | infra-gcp |
| 5 | Health Check | `gcloud compute health-checks describe ... --format="value(type,port)"` | 类型对齐 + port 一致 | infra-gcp |

### 3.2 Post-provision checklist(LB 创建后必跑)

| # | 验证项 | 命令 | 期望值 |
|---|---|---|---|
| 1 | PSC NEG 状态 | `gcloud compute network-endpoint-groups describe <PSC_NEG> ...` | `networkEndpointType=PRIVATE_SERVICE_CONNECT` + `pscTargetService` 指向 Producer Service Attachment |
| 2 | Service Attachment connected endpoints | `gcloud compute service-attachments list ... --format="value(name,connectedEndpoints)"` | `connectedEndpoints >= 1` |
| 3 | Cloud Armor attached | `gcloud compute backend-services describe <BS> --format="value(securityPolicy)"` | 配 Cloud Armor policy |
| 4 | 公网 cert 绑定 | `gcloud compute ssl-certificates describe <CERT> --format="value(managed.status)"` | status=ACTIVE |
| 5 | URL Map default backend | `gcloud compute url-maps describe <URL_MAP> --format="value(defaultService,hostRules,pathMatchers)"` | default → PSC NEG-backed Backend Service |
| 6 | End-to-end curl | `curl -v https://www.aibang.com/healthz` | 200 OK + 公网 cert 正确 |

### 3.3 Smoke test checklist(端到端验证)

| # | 测试 | 命令 | 期望 |
|---|---|---|---|
| 1 | 公网访问 (HTTP)| `curl -v http://www.aibang.com/healthz` | 301 / 308 → https |
| 2 | 公网访问 (HTTPS)| `curl -v https://www.aibang.com/healthz` | 200 OK + cert 正确 |
| 3 | Cloud Armor | 故意发恶意 UA,期望 403 | `curl -A 'sqlmap' https://www.aibang.com/test` → 403 |
| 4 | PSC NEG backend 健康 | `gcloud compute backend-services get-health <BS>` | healthStatus=HEALTHY |
| 5 | Health Check 实际可达 | `gcloud compute health-checks describe <HC>` | status=HEALTHY |
| 6 | Audit log 存在 | `gcloud logging read "resource.type=http_load_balancer" --limit=10` | 有访问记录 |

---

## 4. 业务方已踩过的坑(架构师标注)

| # | 坑 | 解决 | 出处 |
|---|---|---|---|
| 1 | **Org Policy 默认拒绝 EXTERNAL 系 LB** | 业务方申请 Org Policy 扩展 | `tenant-tls-setup-https.md` |
| 2 | **Producer Backend Service 协议不对齐** | 重建 PSC NEG(delete + create) | `tenant-tls-setup-https.md` §3.12 |
| 3 | **MIG 后端一开始只支持 HTTP** | 升级到 HTTPS backend + python https.server | `tenant-tls-setup-https.md` §1 |
| 4 | **Service Attachment ACCEPT_AUTOMATIC** 缺安全 | 改 ACCEPT_MANUAL + consumer allowlist | `psc-concept.md` §4.5 |
| 5 | **PSC NEG 跟 ServiceAttachment 通信需重连 SA** | 改 protocol 后删 SA → 删 FR → 删 Target Proxy → 重建 | `tenant-tls-setup-https.md` §3.4-3.8 |
| 6 | **跨 project 安全组 / firewall 阻断** | Consumer PSC NEG 自动管理 producer 防火墙 + ServiceAttachment accept list 控制 | `psc-concept.md` §3 |
| 7 | **Producer MIG / Instance Group 无 backend** | MIG 必须有 running instance + health check pass | `tenant-tls-setup-https.md` §3.9 |

---

## 5. 5 道闸门 vs 4 个上游文档(架构师 mapping)

| 闸门 | 上游概念文档 | 业务方实施文档 | 架构师分析文档 |
|---|---|---|---|
| 1. LB Scheme | `psc-concept.md` §4.5 | `tenant-tls-setup-https.md` | `why-using-global-external-managed-http-https.md` |
| 2. Org Policy | (无)| `tenant-tls-setup-https.md` Org Policy 警告 | `why-using-global-external-managed-http-https.md` §9 |
| 3. APIs enable | `psc-concept.md` §1 | `tenant-tls-setup-https.md` | (本节补充) |
| 4. Service Attachment | `psc-concept.md` §4 | `tenant-tls-setup-https.md` §5.1 | (本节补充) |
| 5. Backend Service 协议 | `psc-concept.md` §4.4 | `tenant-tls-setup-https.md` §1 | (本节补充) |

---

## 6. 决策树:PSC NEG 跨 project 工作的必要条件

```
PSC NEG 跨 project 创建成功?
│
├─ 闸门 1: LB Scheme = GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS?
│   ├─ ❌ 否 → 改 scheme(架构师决定)
│   └─ ✅ 是
│       │
│       ├─ 闸门 2: Org Policy 放行 EXTERNAL 系?
│       │   ├─ ❌ 否 → 业务方申请 Org Policy 扩展(1-3 工作日)
│       │   └─ ✅ 是
│       │       │
│       │       ├─ 闸门 3: APIs enable(9 个)?
│       │       │   ├─ ❌ 否 → infra-gcp enable
│       │       │   └─ ✅ 是
│       │       │       │
│       │       │       ├─ 闸门 4: Service Attachment ACCEPT_MANUAL + consumer allowlist?
│       │       │       │   ├─ ❌ 否 → infra-gcp 改 Service Attachment 配置
│       │       │       │   └─ ✅ 是
│       │       │       │       │
│       │       │       │       └─ 闸门 5: Backend Service 协议对齐(Consumer / Producer / HC)?
│       │       │       │           ├─ ❌ 否 → 重建 PSC NEG(协议变更后必须)
│       │       │       │           └─ ✅ 是
│       │       │       │               │
│       │       │       │               └─► ✅ PSC NEG 跨 project 工作
```

---

## 7. 业务方应当检查清单(自检)

| # | 自检项 | 如何验证 | 如果失败 |
|---|---|---|---|
| 1 | Org Policy 已扩展到 EXTERNAL 系 | 联系 Security 确认 | 阻塞,先申请 |
| 2 | Backend Service 用 HTTPS 协议(不是 TCP)| `gcloud compute backend-services describe ... --format="value(protocol)"` | infra-gcp 重建 |
| 3 | Health Check 协议跟 Backend Service 对齐 | `gcloud compute health-checks describe ...` | infra-gcp 重建 |
| 4 | Cloud Armor attached | `gcloud compute backend-services describe ... --format="value(securityPolicy)"` | infra-gcp 配 |
| 5 | 公网 cert 正确绑定 | `gcloud compute ssl-certificates describe ...` | 用 cert-manager 或 Google Certificate Manager |
| 6 | Service Attachment consumer allowlist | `gcloud compute service-attachments describe ...` | infra-gcp 加 Consumer project |
| 7 | Producer MIG / IG 有 running backend | `gcloud compute instance-groups managed list-instances <MIG>` | infra-gcp 启动 |

---

## 8. infra-gcp 必跑的回执模板(架构师给)

```markdown
## infra-gcp 验证回执 (YYYY-MM-DD)

### Pre-provision(5 道闸门)

| 闸门 | 结果 | 证据 |
|---|---|---|
| 1. LB Scheme | [✅ / ❌] | [gcloud 输出] |
| 2. Org Policy | [✅ / ❌ / ⏳ pending] | [gcloud org-policies describe 输出] |
| 3. APIs enable | [✅ / ❌] | [gcloud services list 输出] |
| 4. Service Attachment | [✅ / ❌] | [gcloud service-attachments describe 输出] |
| 5. Backend Service 协议 | [✅ / ❌] | [gcloud backend-services describe 输出] |

### Post-provision

| 项 | 结果 | 证据 |
|---|---|---|
| PSC NEG 状态 | [✅ / ❌] | [...] |
| connected endpoints | [≥1 / 0] | [...] |
| Cloud Armor | [✅ / ❌] | [...] |
| 公网 cert | [✅ / ❌] | [...] |
| URL Map | [✅ / ❌] | [...] |

### Smoke test

| 测试 | 结果 |
|---|---|
| HTTP → HTTPS 重定向 | [✅ / ❌] |
| HTTPS 公网访问 | [✅ / ❌] |
| Cloud Armor 拦截 | [✅ / ❌] |
| PSC NEG 健康 | [✅ / ❌] |
| Audit log | [✅ / ❌] |

### 假设差异(如有)

- ...

### 风险提示(如有)

- ...

### 决策

- 全 ✅ → 等业务方 / 决策者拍板 ADR-012 → 我开始 provision ADR-012 实施细节
- 任一 ❌ → 立即升级,等闸门修复后重试
```

---

## 9. 架构师反思(为什么这份 checklist 必要)

**为什么业务方需要这份清单**:

1. **PSC NEG 不是原子操作**——它是 5 道闸门联合约束的结果,任意一道失败都阻塞
2. **业务方历史踩坑**——Org Policy / 协议不对齐 / Service Attachment 配错,这些坑已经踩过
3. **架构师不接"事后改"的活**——infra-gcp 必须按 checklist 跑完才能 provision
4. **架构师 lane 边界**——架构师只能给清单,**不能跑命令验证**

**为什么 infra-gcp 必须按 checklist 跑**:

- ✅ **避免重复踩坑**——5 道闸门每个都是已知坑
- ✅ **统一回执格式**——架构师能高效 review infra-gcp 的回执
- ✅ **可追溯**——后续 ADR-012 / ADR-013 实施时,这份 checklist 是 baseline

---

## 10. 架构师 lane 边界声明

- ✅ 生成 `psc-neg-requirements.md`(本节文档,10 节)
- ✅ 5 道闸门清单 + 完整 checklist + 决策树 + 业务方自检表
- ✅ 引用业务方上游文档(`tenant-tls-setup-https.md` Org Policy 警告 + 协议升级记录)
- ✅ 引用 GCP 官方文档(5 道闸门对应官方约束)
- ✅ 提供 infra-gcp 必跑的回执模板(§8)
- ❌ **不实施任何 provision / apply / gcloud / terraform**
- ❌ **不创建 LB / Backend Service / PSC NEG / Service Attachment**
- ❌ **不持有 GCP 凭证**

---

## 11. 文档维护

- **作者**:**architect-gcp**(架构师,设计 lane)
- **Reviewers**:**infra-gcp** / 业务方 / **qa-gcp**
- **配套文档**:
  - 上游概念:[`why-using-global-external-managed-http-https.md`](./why-using-global-external-managed-http-https.md) — 为什么这个 LB scheme
  - 概念澄清:[`../../psa-psc/psc-concept.md` §4.5](../../psa-psc/psc-concept.md) — PSC NEG 本质
  - 已实现架构:[`public-tls-cross-project-implementation.html`](./public-tls-cross-project-implementation.html)
  - 实施记录:[`tenant-tls-setup-https.md`](./tenant-tls-setup-https.md) — 业务方生产实施
- **状态**:Reference(架构师仅作参考,infra-gcp 按 §3 checklist 跑)

---

<!-- cite: https://cloud.google.com/load-balancing/docs/https — GCP External Application LB overview(支持 NEG 包括 PSC NEG)|
<!-- cite: https://cloud.google.com/compute/docs/load-balancing/http/backend-service — Backend Service 协议约束(HTTPS / portName=https)|
<!-- cite: https://cloud.google.com/vpc/docs/private-service-connect — Private Service Connect 官方文档(Service Attachment / consumer allowlist)|
<!-- cite: https://cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints — Org Policy 约束(allowedLoadBalancingScheme)|
<!-- cite: ./tenant-tls-setup-https.md Org Policy 警告 — 业务方已踩 Org Policy 阻塞 -->
<!-- cite: ./tenant-tls-setup-https.md §3.12 — 业务方重建 PSC NEG(协议变更后必须)|
<!-- cite: ./why-using-global-external-managed-http-https.md §9 — Org Policy 申请模板 -->
