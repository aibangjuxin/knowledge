# To explorer

- 方案 A(推荐,中长期):官方支持的"原地迁移"
Google 提供官方的 Classic → GLOBAL_EXTERNAL_MANAGED 原地迁移流程,不是"重建一套新 LB",而是把现有 forwarding rule/backend service 的 scheme 从 EXTERNAL 逐步(可按流量百分比灰度)切到 EXTERNAL_MANAGED, 按特定顺序迁移资源以确保不中断:先迁移 backend service,再将 forwarding rule 的 scheme 从 EXTERNAL 改为 EXTERNAL_MANAGED 完成迁移。关键优势:

IP 不变,不需要改 DNS A 记录
可以先 TEST_BY_PERCENTAGE 灰度验证,确认无误再切 100%
90 天内如有问题可以按顺序回滚到 Classic scheme,风险可控
迁移完成后,apiname1/2 的行为不受影响(GEML 完全兼容原有 path/host 路由),而 apiname3 就可以正常挂 PSC NEG 了。


- 当前文档所有的配置给下面这个，都是另外一个迁移计划 创建出来之后进行对应的 DNS 迁移。当然上面那个计划是 原地迁移，原地迁移我还没有进行探索


# migration-classic-lb-to-glb-external-managed-lb.md — Classic ALB → Global external ALB 迁移 + 新增 PSC-NEG API 的完整计划

> **场景**:Lex 现网在 A 工程(Tenant project)有一份 **Classic Application Load Balancer**(FR `loadBalancingScheme=EXTERNAL`,Premium Tier global),接住 `https://www.caep.uk` 公网域名,域名 A-record 已绑固定 IP。计划分 3 件事:
> 1. **新建** 一份 **Global external Application Load Balancer**(`loadBalancingScheme=EXTERNAL_MANAGED --global`,对应 Org Policy 白名单 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` — Lex 现网已拿到该白名单,见 `public-tls-ingress/Summarize-current-implementation.md` §3),**新分配一个公网 IP**
> 2. **迁移** 现网 `apiname1` / `apiname2` 两个 API 到新 GLB,**逻辑不变** — 它们继续走 A 工程本地的 Backend Service + Cloud Armor(目标:零停机 + 业务零感知)
> 3. **新增** `apiname3` API 走新 GLB 上的独立 BS + 独立 Cloud Armor,通过 PSC NEG 跨 project 到 Master B 工程(沿用 `class-application-loadbalancer-cross-project.md` §1 方案 1 的 side door 模式,但因为新 GLB 已经是 EXTERNAL_MANAGED,所以**不需要 side door**,直接走 baseing-path-cross-project.md §3 的标准路径)
>
> **关键节点**:**DNS 切换** = 唯一对外可见的操作,前置阶段全部跑完且流量验证通过才做。
>
> **目标文档**:你**先读完所有可逆性 + 风险**,再决定要不要按本方案走。本方案给出了 7 个阶段的命令骨架 + 回滚步骤,但**不**直接给一个能 `bash` 跑的脚本(脚本模式见 `online-consume.sh` 风格,如果需要我可以再独立写一个 `migration-classic-glb.sh`)。

---

## 0. 原始问题(Lex 原话 verbatim,未经 paraphrase)

> 参考这个文档 `/Users/lex/git/gcp/ingress/public-tls-basingpath-cross/class-application-loadbalancer-cross-project.md` 我们现在需要做一个 Migration 的迁移计划
> 具体的计划类型是这样的,先创建一个新的 GLB [`GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`],或者说申请一个新的 IP,到时候直接做流量的切换
> 在这个新的 GLB 上面,我们要确保原来的 API 能够正常运行,也就是说原来要保证原来的 API 的逻辑不变,它所有的 BS 和 Cloud Armor 还是在这个自己的独立工程上面
> 比如说对一个新的 API 我们要做一个独立的处理,比如说这个 API 的名字我们命名为 APIname3 如果是这个对应的 API 请求过来的时候,我需要让它走 PSC Cross Project 的方式访问到我的另外一个工程,我定义为 Master Project
> 比如 `www.caep.uk/apiname3` 也就是说,我原来的 api name1 和 api name2 都是指向我原来本地工程,也就是 tenant project 的 bs 上面,这个 bs 就是一个对应的后端
> 只有我新来的 API,比如说 API name3,才给它创建一个独立的 BS,这个 BS 就是为了 using psc cross project 来使用的
> 帮我制定一个迁移计划,包括具体执行步骤和需要做的调整,确保整个过程平滑
> 我提供一个大概思路:申请新的 GLB 后,比如它有一个 IP 地址,我需要把所有 旧的 apiname1 apiname2 都迁移到这个新 IP 上正常运行,然后把新 APIname3 也做了对应的 PSC 并做对应测试。等所有服务稳定确认可运行时,只需做一次 DNS 切换即可
> 我现在需要你帮我提供一个详细的设计方案,确保都是可行的,然后给出对应的实施步骤,可能需要设计的一些创建的命令等等
> 然后你帮我生成一个对应的文档,放在这个 `/Users/lex/git/gcp/ingress/public-tls-basingpath-cross` 目录下面,命名为 `migration-classic-lb-to-glb-external-managed-lb`

### 0.1 隐性约束(从原话反推)

| # | 约束 | 推导依据 |
|---|------|----------|
| 1 | **现网是 Classic ALB**(`loadBalancingScheme=EXTERNAL`),要迁到 **Global external ALB**(`loadBalancingScheme=EXTERNAL_MANAGED --global`) | Lex 原话明确;符合 `class-application-loadbalancer-cross-project.md` 的前提 |
| 2 | **必须新申请 IP,旧 IP 不能复用** | "先创建一个新的 GLB [`GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`],或者说申请一个新的 IP" |
| 3 | **DNS 切换是唯一对外可见操作** | "只需做一次 DNS 切换即可" |
| 4 | **apiname1 / apiname2 业务逻辑零变化** | "原来要保证原来的 API 的逻辑不变" |
| 5 | **apiname1 / apiname2 的 BS + Cloud Armor 必须在 A 工程**(不挪到 Master B) | "它所有的 BS 和 Cloud Armor 还是在这个自己的独立工程上面" |
| 6 | **apiname3 走 PSC 到 Master B** | "让它走 PSC Cross Project 的方式访问到我的另外一个工程" |
| 7 | **apiname3 的 BS + Cloud Armor 在 A 工程**(因为 PSC NEG 消费端必须在 A) | 沿用 class-appl-doc §1 约束:"Cloud Armor 必须绑在 A 工程的 BS 上" |
| 8 | **全过程可回滚** | "确保整个过程平滑" |

### 0.2 一句话核心结论

> **可行性**:**完全可行**。**7 个阶段 + 1 次 DNS 切换**即可完成。每阶段都有独立回滚点,DNS 切换是**唯一不可逆**但延迟成本极低(< TTL)的步骤。
>
> **核心架构变化**:
> - 旧 Classic ALB FR (`loadBalancingScheme=EXTERNAL`) → **保留不动**(作为 rollback fallback,最后清理阶段才删)
> - 新建 Global external ALB FR (`loadBalancingScheme=EXTERNAL_MANAGED --global`)→ **承载所有流量**
> - 旧 Classic ALB 的 BS / Cloud Armor → **直接迁移到新 GLB 下面**(可以新建 BS,也可以把 BS detach 后重新 attach 到新 URL Map)
> - apiname3 新增独立的 BS + Cloud Armor + PSC NEG,挂在**新** GLB 的 URL Map 上
>
> **回滚总策略**:**任何阶段发现问题,只要 DNS 还指向旧 IP**,整个迁移可以立即回滚到 100% 旧 LB 状态。

---

## 1. 总体架构图(迁移完成后)

```
┌────────────────────────────────────────────────────────────────────────┐
│ INTERNET                                                               │
│   curl https://www.caep.uk/apiname1/...   (迁移后走新 GLB)            │
│   curl https://www.caep.uk/apiname2/...   (迁移后走新 GLB)            │
│   curl https://www.caep.uk/apiname3/...   (新增,走 PSC 到 Master B)   │
└─────────────┬──────────────────────────────────────────────────────────┘
              │ DNS A-record
              │  阶段 0-6: 仍指向 OLD_IP (Classic ALB FR)
              │  阶段 7 (DNS 切换后): 指向 NEW_IP (Global external ALB FR)
              ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PROJECT A (Tenant, www.caep.uk 已 A-record → DNS 当前 IP)            │
│                                                                        │
│ ┌────────────────────────┐      ┌──────────────────────────────────┐  │
│ │ OLD: Classic ALB       │      │ NEW: Global external ALB (★ 新建)│  │
│ │ loadBalancingScheme=   │      │ loadBalancingScheme=             │  │
│ │   EXTERNAL (Premium,   │      │   EXTERNAL_MANAGED --global      │  │
│ │   global)              │      │                                  │  │
│ │ ★ 阶段 0-6 承载流量    │      │ IP = NEW_IP (★ 新分配)          │  │
│ │ ★ 阶段 7 后保留空转    │      │ Cert = *.caep.uk (复用旧 cert)   │  │
│ │ ★ 阶段 8 删除          │      │ Target HTTPS Proxy (新建)       │  │
│ └────────────────────────┘      └──────────┬───────────────────────┘  │
│                                             ▼                          │
│                       ┌──────────────────────────────────────┐         │
│                       │ NEW URL Map (caep-migration-um)      │         │
│                       │   hostRules: [www.caep.uk]           │         │
│                       │   pathRules:                         │         │
│                       │     /apiname1/*  → bs-apiname1-new   │         │
│                       │     /apiname2/*  → bs-apiname2-new   │         │
│                       │     /apiname3/*  → bs-apiname3-new   │         │
│                       │     default      → bs-default-new   │         │
│                       └──────────┬───────────────────────────┘         │
│                                  ▼                                      │
│   ┌────────────────────┬────────────────────┬──────────────────────┐  │
│   │ bs-apiname1-new    │ bs-apiname2-new    │ bs-apiname3-new      │  │
│   │ (从旧 BS 迁移过来) │ (从旧 BS 迁移过来) │ (★ 新建)             │  │
│   │ loadBalancingScheme│ loadBalancingScheme│ loadBalancingScheme= │  │
│   │ = EXTERNAL         │ = EXTERNAL         │ EXTERNAL_MANAGED ★★★ │  │
│   │ (★ 跟旧 BS 同 type)│ (★ 跟旧 BS 同 type)│ (★ Global GLB 新要求)│  │
│   │ backends: zonal    │ backends: zonal    │ backends: PSC NEG    │  │
│   │   NEG / instance   │   NEG / instance   │   caep-apiname3-neg  │  │
│   │   group (本工程 MIG)│  group (本工程 MIG)│   (→ Master B SA)    │  │
│   │ Cloud Armor:       │ Cloud Armor:       │ Cloud Armor:         │  │
│   │   policy-apiname1  │   policy-apiname2  │   policy-apiname3 ★  │  │
│   └────────────────────┴────────────────────┴──────────────────────┘  │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ PSC NEG caep-apiname3-neg
                                  │ (阶段 4 创建,阶段 5 测试)
                                  ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PROJECT B (Master)                                                     │
│   Service Attachment caep-master-sa-3                                   │
│   → L7 Internal ALB (apiname3 专属)→ MIG nginx → K8s Gateway → svc   │
│   (apiname1/apiname2 在 B 侧无任何资源,完全本地处理)                   │
└────────────────────────────────────────────────────────────────────────┘
```

**关键识别**:
- ✅ **apiname1 / apiname2 的 BS type 不需要换**(继续 EXTERNAL,本工程 backend)
- ✅ **apiname3 的 BS 必须用 EXTERNAL_MANAGED**(因为要挂 PSC NEG,baseing-path-cross-project.md §2.2 强制要求)
- ✅ **3 个 BS 在新 GLB 下可以共存,互不干扰**
- ✅ **旧 Classic ALB 全程保留到阶段 8,作为 rollback 锚点**

---

## 2. 迁移阶段总览(7 阶段 + 1 次 DNS 切换)

| 阶段 | 操作 | 对外可见? | 可回滚? | 估计时长 | 是否阻塞下一阶段? |
|------|------|----------|----------|---------|------------------|
| **0** | Pre-flight: 工具/权限/IAM/Subnet 资源检查 | ❌ | ✅ N/A | 10 min | ❌ |
| **1** | 新建 Global external ALB 资源(IP + cert 副本 + FR + Proxy + URL Map + default BS) | ❌ | ✅ 全删 | 30 min | ❌(不切流量) |
| **2** | apiname1 / apiname2 迁移到新 GLB(URL Map path rule + 新 BS 或迁移旧 BS) | ❌(还没切 DNS) | ✅ 移除 path rule | 45 min | ❌ |
| **3** | apiname3 准备:Master B 建 SA + ILB + MIG nginx(独立 apiname3 路径) | ❌ | ✅ 删 B 侧资源 | 60+ min | ❌ |
| **4** | apiname3 PSC NEG + EXTERNAL_MANAGED BS + Cloud Armor 创建(A 工程内) | ❌ | ✅ 删 A 工程新增 | 20 min | ❌ |
| **5** | 端到端测试:走 OLD IP(apiname1/2) + 走 NEW IP(apiname1/2/3) | ❌(DNS 没切) | ✅ 旧 LB 仍承载 | 30 min | ❌ |
| **6** | 灰度切换:Hosts override / 内部用户切换测试 | ⚠ 仅内部用户 | ✅ Hosts revert | 1-7 天 | ❌ |
| **7** | **DNS 切换**:`www.caep.uk` A-record 从 OLD_IP → NEW_IP | ✅ **对外可见** | ⚠ 切回(< TTL) | < 1 min 操作 + TTL 等待 | ❌(切换即生效) |
| **8** | 清理:旧 Classic ALB 删除(可保留 N 天作为保险) | ❌ | ✅ 旧资源仍可恢复(soft delete) | 15 min | ❌ |

**最关键的时间预估**:
- 阶段 0-5 = **2-3 小时**(纯操作,无等待)
- 阶段 6 = **1-7 天**(观察期,**可压缩**但风险大)
- 阶段 7 = **< 1 min**(改 DNS)+ DNS TTL 等待(典型 300s,但 Lex 现网 DNS TTL 决定)
- 阶段 8 = **15 min**(可选)

**总迁移时长**:**1-7 天**(主要是阶段 6 观察期)。

---

## 3. 详细阶段实施步骤

### 阶段 0:Pre-flight 检查(10 min)

**目标**:确认所有前置条件满足,工具齐全,任何缺口都先补。

#### 0.1 检查清单

```bash
# 1. gcloud / jq / curl 都装了
for cmd in gcloud jq curl; do
  command -v $cmd >/dev/null 2>&1 || echo "❌ $cmd missing"
done

# 2. A 工程当前 project + Org Policy 白名单
gcloud config get-value project
gcloud resource-manager org-policies list \
  --project=$(gcloud config get-value project 2>/dev/null) \
  --filter="constraint:constraints/compute.restrictLoadBalancingCreation" \
  --format="get(constraint,listPolicy)"

# 期望包含:
#   GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS = ALLOWED  (← Lex 已有,见 Summarize §3)

# 3. 现网 Classic ALB FR 的 loadBalancingScheme = EXTERNAL(确认是 Classic)
gcloud compute forwarding-rules describe <OLD_FR_NAME> \
  --project=$PROJECT --global \
  --format="get(loadBalancingScheme,IPAddress,target)"

# 4. 现有 Backend Service / Cloud Armor 数量(迁移对象)
gcloud compute backend-services list --project=$PROJECT --format="table(name,loadBalancingScheme,protocol)"
gcloud compute security-policies list --project=$PROJECT --format="table(name)"

# 5. 确认 Master B 工程的 Service Attachment URI(从 B owner 拿)
# 项目 ID / region / SA name 三件套
B_SA_URI="projects/<B_PROJECT>/regions/<REGION>/serviceAttachments/<SA_NAME>"

# 6. A 工程有可用 VPC + 普通 subnet(给 PSC NEG 用)
gcloud compute networks subnets list --project=$PROJECT --filter="region:$REGION" \
  --format="table(name,region,ipCidrRange)"

# 7. 验证 cert 副本可访问(A 工程 cert 必须能复用)
ls -la $CERT_DIR/<caep-uk-cert>.crt $CERT_DIR/<caep-uk-cert>.key
```

#### 0.2 必备资源(项目级常量)

```bash
# 建议在脚本顶部声明(后续每个阶段引用)
PROJECT=<A_PROJECT_ID>
REGION=<同 B SA 的 region,例如 europe-west2>
NETWORK=<A 工程现有 VPC 名>
SUBNET=<A 工程现有 subnet 名(给 PSC NEG 用)>

# 新资源命名前缀(沿用 online-consume.sh 风格,但加 -v2 / -new 标识)
PREFIX="caep-mig"   # 跟现网 lex-poc / lex-demo 风格一致

# 新 GLB IP / 资源命名
NEW_GLB_IP="${PREFIX}-public-glb-ip"
NEW_CERT="${PREFIX}-public-cert"
NEW_PROXY="${PREFIX}-public-proxy"
NEW_UM="${PREFIX}-public-um"
NEW_FR="${PREFIX}-public-fr"
NEW_ARMOR="${PREFIX}-public-armor"

# apiname3 专属命名(独立 BS / Cloud Armor / PSC NEG)
NEW_BS_APINAME3="${PREFIX}-apiname3-bs"
NEW_ARMOR_APINAME3="${PREFIX}-apiname3-armor"
NEW_NEG_APINAME3="${PREFIX}-apiname3-neg"

# 旧 GLB 资源引用(用于迁移 + 阶段 8 清理)
OLD_FR=<旧 Classic ALB FR name>
OLD_UM=<旧 URL Map name>
OLD_BS_APINAME1=<旧 apiname1 BS name>
OLD_BS_APINAME2=<旧 apiname2 BS name>
OLD_ARMOR_APINAME1=<旧 apiname1 Cloud Armor>
OLD_ARMOR_APINAME2=<旧 apiname2 Cloud Armor>
OLD_IP=<旧 GLB 公网 IP,fr describe 拿>
```

#### 0.3 阶段 0 回滚:N/A(纯检查,无可回滚动作)

---

### 阶段 1:新建 Global external ALB 资源(30 min)

**目标**:把新 GLB 的骨架立起来,带 default BS,**不**配置 path rule,**不**挂 PSC NEG,**不**动旧 LB。

#### 1.1 新建资源序列

```bash
# Step 1.1: 新建公网 IP (★ 阶段 7 DNS 切换的目标)
gcloud compute addresses create $NEW_GLB_IP \
  --project=$PROJECT --global \
  --ip-version=IPV4 \
  --description="NEW Global external ALB IP for caep.uk migration"

NEW_IP=$(gcloud compute addresses describe $NEW_GLB_IP \
  --project=$PROJECT --global --format="value(address)")
echo "★ NEW_IP = $NEW_IP   (阶段 7 DNS 切换用)"

# Step 1.2: 上传 cert(复用 A 工程旧 cert,DV cert 可被任意多 GLB 实例引用,SAN 已含 *.caep.uk)
gcloud compute ssl-certificates create $NEW_CERT \
  --project=$PROJECT --global \
  --certificate=$CERT_DIR/<caep-uk-cert>.crt \
  --private-key=$CERT_DIR/<caep-uk-cert>.key \
  --description="NEW Global external ALB cert for caep.uk (same PEM as Classic ALB)"

# Step 1.3: 新建 default BS(EXTERNAL_MANAGED,★ Global GLB 的强制要求)
# 这个 default BS 临时挂一个 dummy MIG,阶段 2 才会真正被 apiname1/2/3 的 path rule 覆盖
gcloud compute backend-services create ${PREFIX}-public-default-bs \
  --project=$PROJECT --global \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTPS \
  --description="Default BS for NEW Global external ALB"

# Step 1.4: 新建 dummy MIG(仅供 default BS health check 通过)
gcloud compute instance-templates create ${PREFIX}-default-tmpl \
  --project=$PROJECT --machine-type=e2-micro \
  --image-family=debian-11 --image-project=debian-cloud \
  --network=$NETWORK --subnet=$SUBNET \
  --no-address \
  --tags=http-server,${PREFIX}-default \
  --description="Dummy MIG for default BS health check"

gcloud compute instance-groups managed create ${PREFIX}-default-mig \
  --project=$PROJECT --base-instance-name=${PREFIX}-default \
  --template=${PREFIX}-default-tmpl --size=1 --region=$REGION

gcloud compute backend-services add-backend ${PREFIX}-public-default-bs \
  --project=$PROJECT --global \
  --instance-group=${PREFIX}-default-mig \
  --instance-group-region=$REGION \
  --balancing-mode=UTILIZATION --capacity-scaler=1.0

# Step 1.5: 新建 URL Map (default → default BS,后续阶段加 path rule)
gcloud compute url-maps create $NEW_UM \
  --project=$PROJECT --global \
  --default-service=${PREFIX}-public-default-bs \
  --description="NEW URL Map for caep.uk migration"

# Step 1.6: 新建 Target HTTPS Proxy
gcloud compute target-https-proxies create $NEW_PROXY \
  --project=$PROJECT --global \
  --url-map=$NEW_UM \
  --ssl-certificates=$NEW_CERT \
  --description="NEW Target HTTPS Proxy for Global external ALB"

# Step 1.7: 新建 Forwarding Rule (★ 关键:scheme=EXTERNAL_MANAGED --global)
gcloud compute forwarding-rules create $NEW_FR \
  --project=$PROJECT --global \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --address=$NEW_GLB_IP \
  --target-https-proxy=$NEW_PROXY \
  --ports=443 \
  --network-tier=PREMIUM \
  --description="NEW Global external ALB FR for caep.uk migration"
```

#### 1.2 阶段 1 验证

```bash
# 1. 全部资源就绪
gcloud compute forwarding-rules describe $NEW_FR --global --project=$PROJECT \
  --format="get(loadBalancingScheme,IPAddress,target)"
# 期望:scheme=EXTERNAL_MANAGED, IP=$NEW_IP

# 2. 走 NEW_IP curl,期望命中 default BS 的 dummy MIG(404 或 default 页面)
curl -sk -o /dev/null -w "%{http_code}\n" \
  --resolve www.caep.uk:443:$NEW_IP https://www.caep.uk/

# 3. DNS 还指向 OLD_IP,所以公网 curl 仍然走旧 GLB,流量未变
curl -sk -o /dev/null -w "%{http_code}\n" https://www.caep.uk/apiname1/healthz
# 期望:仍返回旧 BS 的真实业务响应
```

#### 1.3 阶段 1 回滚(整段)

```bash
# 阶段 1 创建的所有资源都可以直接删,不影响旧 LB
gcloud compute forwarding-rules delete $NEW_FR --global --project=$PROJECT --quiet
gcloud compute target-https-proxies delete $NEW_PROXY --global --project=$PROJECT --quiet
gcloud compute url-maps delete $NEW_UM --global --project=$PROJECT --quiet
gcloud compute backend-services delete ${PREFIX}-public-default-bs --global --project=$PROJECT --quiet
gcloud compute instance-groups managed delete ${PREFIX}-default-mig --region=$REGION --project=$PROJECT --quiet
gcloud compute instance-templates delete ${PREFIX}-default-tmpl --project=$PROJECT --quiet
gcloud compute ssl-certificates delete $NEW_CERT --global --project=$PROJECT --quiet
gcloud compute addresses delete $NEW_GLB_IP --global --project=$PROJECT --quiet
```

---

### 阶段 2:apiname1 / apiname2 迁移到新 GLB(45 min)

**目标**:把 apiname1 / apiname2 的流量路径从"旧 Classic ALB FR → 旧 BS"改成"新 Global ALB FR → 新 BS(EXTERNAL_MANAGED)+ 同样的 backend"。两条关键路径任选其一。

#### 2.1 路径选择:**新建 BS vs 迁移旧 BS**

| 方案 | 操作 | 优点 | 缺点 |
|------|------|------|------|
| **A. 新建 EXTERNAL_MANAGED BS**(推荐) | 在 A 工程新建 2 个 EXTERNAL_MANAGED BS,backends 指向跟旧 BS 一样的 instance group / NEG;然后 detach 旧 BS 的 backend,detach 旧 Cloud Armor | 全新 BS,无历史包袱;阶段 5 测试更干净 | 多 2 个 BS 资源 |
| B. 迁移旧 BS | 把旧 BS detach 旧 Cloud Armor,改 `loadBalancingScheme` 为 `EXTERNAL_MANAGED`,重新 attach Cloud Armor | 资源数量少 | 改 scheme 可能需要 recreate(部分 gcloud API 不允许 in-place edit);Cloud Armor 重新 attach 有短暂失效 |

**本方案选 A**(新建 BS)。

#### 2.2 方案 A 操作序列

> **🎯 意图澄清(必读)**:`bs-apiname1-new` / `bs-apiname2-new` 这 2 个新建的 BS,**不是**为了让请求"换一台 MIG",也**不是**复制一份 backend pool。它们的真实目的是:
>
> - **GLB 层换个壳**:旧 Classic ALB 的 BS type 是 `EXTERNAL`,**不能**挂到新 Global external ALB 的 EXTERNAL_MANAGED FR 上(R3 side door 反向不兼容),所以必须**新建一个 EXTERNAL_MANAGED BS** 来适配新 GLB
> - **backend pool 一行不动**:新 BS 的 backends 字段 = 旧 BS 的 backends 字段 = **同一个** instance group / zonal NEG / hybrid NEG。**MIG 数量、VM 实例、nginx 配置、API 业务逻辑,全部 0 改动**。Lex 现网服务的实例、流量、监控指标都不变
> - **Cloud Armor policy 复用**:新 BS 直接 `security-policy=$OLD_ARMOR_APINAME1`,引用的是**同一个** Cloud Armor policy 资源,policy rule / rate limit / WAF 配置 0 改动
>
> → **请求链路变化只在 LB 控制面(FR / Proxy / URL Map / BS)**,**数据面 backend pool(MIG / VM / 应用)完全不动**。DNS 切换后请求走"新 GLB FR → 新 BS → 同一个 MIG",响应跟旧 GLB 完全一致。这就是"业务零感知"的物理基础。

```bash
# Step 2.1: 新建 apiname1 的 EXTERNAL_MANAGED BS
gcloud compute backend-services create ${PREFIX}-apiname1-bs \
  --project=$PROJECT --global \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTPS \
  --description="Migrated apiname1 BS on new Global external ALB"

# Step 2.2: 把旧 apiname1 BS 的 backend 复制到新 BS
# 先查旧 BS 的 backends
gcloud compute backend-services describe $OLD_BS_APINAME1 --global --project=$PROJECT \
  --format="json" | jq '.backends'

# 然后 add-backend 到新 BS(保持原 instance group / NEG 不变)
# 示例(假设旧 backend 是 zonal MIG):
gcloud compute backend-services add-backend ${PREFIX}-apiname1-bs \
  --project=$PROJECT --global \
  --instance-group=<从旧 BS describe 拿到的 instance group URL> \
  --instance-group-region=$REGION \
  --balancing-mode=UTILIZATION --capacity-scaler=1.0

# 重复 Step 2.1-2.2 给 apiname2
# ...

# Step 2.3: 给 2 个新 BS 各自绑原 Cloud Armor
gcloud compute backend-services update ${PREFIX}-apiname1-bs \
  --project=$PROJECT --global \
  --security-policy=$OLD_ARMOR_APINAME1

gcloud compute backend-services update ${PREFIX}-apiname2-bs \
  --project=$PROJECT --global \
  --security-policy=$OLD_ARMOR_APINAME2

# Step 2.4: URL Map 加 path rule,把 apiname1/apiname2 指向新 BS
gcloud compute url-maps add-path-matcher $NEW_UM \
  --project=$PROJECT \
  --path-matcher-name=caep-api-matcher \
  --default-service=${PREFIX}-public-default-bs \
  --new-hosts=www.caep.uk \
  --path-rules="/apiname1/*=${PREFIX}-apiname1-bs,/apiname2/*=${PREFIX}-apiname2-bs"
```

#### 2.3 阶段 2 验证

```bash
# 1. 走 NEW_IP 命中 apiname1/apiname2 的真实后端
curl -sk --resolve www.caep.uk:443:$NEW_IP \
  -o /dev/null -w "%{http_code}\n" https://www.caep.uk/apiname1/healthz
# 期望:200,返回真实业务响应(跟旧 IP 一样)

# 2. 走 OLD_IP 仍命中旧 BS(流量未切)
curl -sk -o /dev/null -w "%{http_code}\n" https://www.caep.uk/apiname1/healthz
# 期望:200,跟 NEW_IP 一致(因为 backend 都是同一个 instance group)

# 3. LB log 确认新 GLB 的 path rule 命中
gcloud logging read 'jsonPayload.urlMapName="'$NEW_UM'"' \
  --project=$PROJECT --limit=5 --format='json' \
  | jq '.[] | {path: .jsonPayload.requestUrl, backend: .jsonPayload.backendTargetName}'
# 期望:看到 apiname1 → ${PREFIX}-apiname1-bs
```

#### 2.4 阶段 2 回滚

```bash
# 移除 path rule,恢复 default
gcloud compute url-maps remove-path-matcher $NEW_UM \
  --project=$PROJECT --path-matcher-name=caep-api-matcher

# 删除新建的 2 个 BS(无副作用,因为旧 LB 没引用它们)
gcloud compute backend-services delete ${PREFIX}-apiname1-bs --global --project=$PROJECT --quiet
gcloud compute backend-services delete ${PREFIX}-apiname2-bs --global --project=$PROJECT --quiet
```

**DNS 仍指向 OLD_IP,所以对外不可见;apiname1/apiname2 仍走旧 GLB。**

---

### 阶段 3:Master B 侧 apiname3 入口准备(60+ min)

**目标**:B 侧搭好接收 `apiname3` 的链路(SA + ILB + MIG nginx + K8s Gateway)。这部分是**基础架构**,完整 5 方案见 `public-fqdn-explorer.md`。

#### 3.1 简版:复用 baseing-path-cross-project.md §4 + public-fqdn-explorer.md §3

Lex 本次只新增 apiname3,所以 B 侧**不必拆 SA**(Lex 之前 baseing-path 文档默认 1 SA + B 侧 nginx 二次分流;若已有 SA 可以直接复用)。

**新增资源**(B 工程内):

```bash
# 在 B 工程操作(或请 B owner 跑)
B_PROJECT=<B_PROJECT_ID>
B_REGION=$REGION

# 1. Service Attachment(若还没有)
# 完整命令见 baseing-path-cross-project.md §4.1 #1

# 2. Producer NAT subnet
gcloud compute networks subnets create caep-master-nat-subnet \
  --project=$B_PROJECT --region=$B_REGION \
  --network=<B VPC> --range=10.10.0.0/24 \
  --purpose=PRIVATE_SERVICE_CONNECT --role=ACTIVE

# 3. L7 Internal Application LB(apiname3 专属)
gcloud compute backend-services create caep-apiname3-bs \
  --project=$B_PROJECT --region=$B_REGION \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --protocol=HTTPS \
  --description="B-side ILB BS for apiname3"

# 4. MIG (apiname3 专属 nginx)
# instance template 拉 nginx.conf,nginx 监听 /apiname3/ 转发到 K8s Gateway
# 详见 public-fqdn-explorer.md §3.5

# 5. URL Map + ILB forwarding rule
gcloud compute url-maps create caep-apiname3-ilb-um \
  --project=$B_PROJECT --region=$B_REGION \
  --default-service=caep-apiname3-bs

gcloud compute target-https-proxies create caep-apiname3-ilb-proxy \
  --project=$B_PROJECT --region=$B_REGION \
  --url-map=caep-apiname3-ilb-um \
  --ssl-certificates=<B 侧 cert>

gcloud compute forwarding-rules create caep-apiname3-ilb-fr \
  --project=$B_PROJECT --region=$B_REGION \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --target-https-proxy=caep-apiname3-ilb-proxy \
  --subnet=<B subnet> --ip-address=10.x.x.x --ports=443

# 6. Service Attachment 把 ILB 暴露出去
gcloud compute service-attachments create caep-master-sa-3 \
  --project=$B_PROJECT --region=$B_REGION \
  --producer-forwarding-rule=caep-apiname3-ilb-fr \
  --nat-subnets=caep-master-nat-subnet \
  --connection-preference=ACCEPT_AUTOMATIC \
  --consumer-accept-list="<A 工程 project number>=10"

# ★ 关键输出 — 阶段 4 创建 PSC NEG 用
B_SA_URI="projects/$B_PROJECT/regions/$B_REGION/serviceAttachments/caep-master-sa-3"
echo "★ B_SA_URI = $B_SA_URI"
```

#### 3.2 阶段 3 验证(从 B 侧 VM 直接 curl ILB)

```bash
# 在 B 工程内任意 VM(同 VPC)
curl -sk -o /dev/null -w "%{http_code}\n" \
  https://10.x.x.x/apiname3/healthz
# 期望:200,业务响应

# 检查 SA 状态
gcloud compute service-attachments describe caep-master-sa-3 \
  --project=$B_PROJECT --region=$B_REGION --format="get(connectionPreference,connectedEndpoints)"
```

#### 3.3 阶段 3 回滚

```bash
# B 侧所有 apiname3 资源逆向删除(同 baseing-path-cross-project.md §7 删除顺序)
gcloud compute service-attachments delete caep-master-sa-3 --region=$B_REGION --project=$B_PROJECT --quiet
gcloud compute forwarding-rules delete caep-apiname3-ilb-fr --region=$B_REGION --project=$B_PROJECT --quiet
gcloud compute target-https-proxies delete caep-apiname3-ilb-proxy --region=$B_REGION --project=$B_PROJECT --quiet
gcloud compute url-maps delete caep-apiname3-ilb-um --region=$B_REGION --project=$B_PROJECT --quiet
gcloud compute backend-services delete caep-apiname3-bs --region=$B_REGION --project=$B_PROJECT --quiet
gcloud compute instance-groups managed delete caep-apiname3-mig --region=$B_REGION --project=$B_PROJECT --quiet
gcloud compute instance-templates delete caep-apiname3-tmpl --project=$B_PROJECT --quiet
gcloud compute networks subnets delete caep-master-nat-subnet --region=$B_REGION --project=$B_PROJECT --quiet
```

---

### 阶段 4:apiname3 PSC NEG + BS + Cloud Armor(A 工程内,20 min)

**目标**:在 A 工程新建 apiname3 专属 BS(EXTERNAL_MANAGED)+ Cloud Armor + PSC NEG,指向 B 侧阶段 3 建的 SA。

#### 4.1 操作序列

```bash
# Step 4.1: 建独立 Cloud Armor policy(apiname3)
gcloud compute security-policies create $NEW_ARMOR_APINAME3 \
  --project=$PROJECT \
  --description="apiname3 dedicated Cloud Armor policy"

gcloud compute security-policies rules create 1000 \
  --project=$PROJECT --security-policy=$NEW_ARMOR_APINAME3 \
  --expression="true" --action=rate-based-ban \
  --rate-limit-threshold-count=200 \
  --rate-limit-threshold-interval-sec=60 --ban-duration-sec=600

# Step 4.2: 建 PSC NEG(指向 B SA)
gcloud compute network-endpoint-groups create $NEW_NEG_APINAME3 \
  --project=$PROJECT --region=$REGION \
  --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
  --psc-target-service=$B_SA_URI \
  --network=$NETWORK \
  --subnet=$SUBNET \
  --description="PSC NEG bridging to B master SA-3 for apiname3"

# Step 4.3: 建 EXTERNAL_MANAGED BS(apiname3 专属)
gcloud compute backend-services create $NEW_BS_APINAME3 \
  --project=$PROJECT --global \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTPS \
  --description="apiname3 BS (EXTERNAL_MANAGED) on new Global external ALB"

# Step 4.4: add-backend 把 PSC NEG 挂到 BS(★ 必须 UTILIZATION,不加 max-*)
gcloud compute backend-services add-backend $NEW_BS_APINAME3 \
  --project=$PROJECT --global \
  --network-endpoint-group=$NEW_NEG_APINAME3 \
  --network-endpoint-group-region=$REGION \
  --balancing-mode=UTILIZATION --capacity-scaler=1.0

# Step 4.5: 绑 Cloud Armor
gcloud compute backend-services update $NEW_BS_APINAME3 \
  --project=$PROJECT --global \
  --security-policy=$NEW_ARMOR_APINAME3

# Step 4.6: URL Map 加 apiname3 path rule
gcloud compute url-maps add-path-matcher $NEW_UM \
  --project=$PROJECT \
  --path-matcher-name=caep-api-matcher \
  --default-service=${PREFIX}-public-default-bs \
  --new-hosts=www.caep.uk \
  --path-rules="/apiname1/*=${PREFIX}-apiname1-bs,/apiname2/*=${PREFIX}-apiname2-bs,/apiname3/*=${NEW_BS_APINAME3}"

# Step 4.7: B 侧 approve PSC NEG 连接(若 SA 是 ACCEPT_MANUAL)
# 通常阶段 3 已设 ACCEPT_AUTOMATIC,跳过
```

#### 4.2 阶段 4 验证

```bash
# 1. PSC NEG 状态(应 ACCEPTED)
gcloud compute network-endpoint-groups describe $NEW_NEG_APINAME3 \
  --project=$PROJECT --region=$REGION --format="get(pscConnectionId,networkEndpointType)"

# 2. B 侧 SA 收到连接
gcloud compute service-attachments describe caep-master-sa-3 \
  --project=$B_PROJECT --region=$REGION \
  --format="json" | jq '.connectedEndpoints'
# 期望:看到 A 工程的 PSC NEG ACCEPTED

# 3. 走 NEW_IP 命中 apiname3(跨 project → B 侧)
curl -sk --resolve www.caep.uk:443:$NEW_IP \
  -o /dev/null -w "%{http_code}\n" https://www.caep.uk/apiname3/healthz
# 期望:200,响应来自 B 侧 MIG nginx
```

#### 4.3 阶段 4 回滚

```bash
# URL Map 移除 apiname3 path rule
gcloud compute url-maps remove-path-matcher $NEW_UM \
  --project=$PROJECT --path-matcher-name=caep-api-matcher

# 删除 A 工程新增的 apiname3 资源
gcloud compute backend-services delete $NEW_BS_APINAME3 --global --project=$PROJECT --quiet
gcloud compute network-endpoint-groups delete $NEW_NEG_APINAME3 --region=$REGION --project=$PROJECT --quiet
gcloud compute security-policies delete $NEW_ARMOR_APINAME3 --project=$PROJECT --quiet
```

---

### 阶段 5:端到端测试(30 min)

**目标**:从内部测试环境走 NEW_IP 验证 3 个 API 全部正常,**DNS 还没切**,公网用户完全无感。

#### 5.1 测试矩阵

| 测试 | 命令 | 期望 | 实际 |
|------|------|------|------|
| apiname1 走 NEW_IP | `curl -sk --resolve www.caep.uk:443:$NEW_IP https://www.caep.uk/apiname1/healthz` | 200,业务响应 | |
| apiname2 走 NEW_IP | `curl -sk --resolve www.caep.uk:443:$NEW_IP https://www.caep.uk/apiname2/healthz` | 200,业务响应 | |
| apiname3 走 NEW_IP | `curl -sk --resolve www.caep.uk:443:$NEW_IP https://www.caep.uk/apiname3/healthz` | 200,B 侧业务响应 | |
| apiname1 走 OLD_IP(回归测试) | `curl -sk https://www.caep.uk/apiname1/healthz` | 200,跟 NEW_IP 一致 | |
| apiname2 走 OLD_IP | `curl -sk https://www.caep.uk/apiname2/healthz` | 200,跟 NEW_IP 一致 | |
| default path 走 NEW_IP | `curl -sk --resolve www.caep.uk:443:$NEW_IP https://www.caep.uk/something-unknown` | 404 或 default 页面 | |
| 跨 project header | `curl -skI --resolve www.caep.uk:443:$NEW_IP https://www.caep.uk/apiname3/healthz` | 含 X-Forwarded-For / Via: 1.1 google | |

#### 5.2 LB log 验证(确认新 GLB 真实承载)

```bash
# 新 GLB 日志
gcloud logging read 'jsonPayload.urlMapName="'$NEW_UM'"' \
  --project=$PROJECT --limit=20 \
  --format='json' \
  | jq '.[] | {ts: .timestamp, path: .jsonPayload.requestUrl, backend: .jsonPayload.backendTargetName, status: .jsonPayload.statusDetails}'

# 旧 GLB 日志(确认仍是旧 BS 在响应)
gcloud logging read 'jsonPayload.urlMapName="'$OLD_UM'"' \
  --project=$PROJECT --limit=20 --format='json' \
  | jq '.[] | {ts: .timestamp, path: .jsonPayload.requestUrl, backend: .jsonPayload.backendTargetName}'
```

#### 5.3 阶段 5 通过判定

- ✓ 所有 7 个测试都返回期望值
- ✓ apiname3 走的 backend 是 B 侧 MIG nginx(LB log 里看到 backendTargetName 是 B 侧 BS)
- ✓ apiname1/2 走的 backend 跟旧 GLB 的 LB log 一致(说明 backend 没变)

**如果不通过**:回到对应阶段重做,或按阶段回滚到只剩阶段 1 完成的最小状态。

---

### 阶段 6:灰度切换(1-7 天)

**目标**:让**一部分内部用户**先用 NEW_IP 体验,公网 DNS 仍指向 OLD_IP,出问题随时切回。

#### 6.1 灰度 3 种方式

| 方式 | 适用 | 操作 | 回滚 |
|------|------|------|------|
| **A. Hosts file override(最简单)** | 内部员工 / 运维 | 通知 5-10 个内部用户改 `/etc/hosts`(或公司内部 DNS),`www.caep.uk` → NEW_IP | 改回 |
| **B. 内部 DNS split-brain** | 公司有内部 DNS | 在内网 DNS 加 `www.caep.uk.internal` → NEW_IP,公网 DNS 不变 | 删内网记录 |
| **C. Cloud Armor 灰度** | 高级用户 | 给新 GLB 的 apiname1/2/3 path rule 加 Cloud Armor conditional,只允许特定 IP(如公司出口 IP)访问 | 删规则 |

**推荐 A**:最简单,出问题影响面小,内部用户测 1-3 天就能确认稳定性。

#### 6.2 灰度观察期检查清单

- [ ] apiname1 业务正常(对比旧 LB 响应)
- [ ] apiname2 业务正常
- [ ] apiname3 业务正常(★ 新 API,重点观察)
- [ ] latency:apiname3 P99 跟旧 LB 的 apiname1/2 P99 接近(< 2x)
- [ ] error rate:新 GLB 5xx < 0.1%
- [ ] Cloud Armor 命中数:`policy-apiname1/2/3` 跟旧 LB 的同名 policy 接近
- [ ] B 侧 ILB 健康检查全部 PASS
- [ ] B 侧 MIG nginx access log 正常

#### 6.3 阶段 6 通过判定

观察期内**零 P0/P1 故障** → 进入阶段 7。

---

### 阶段 7:DNS 切换(★ 唯一对外可见的操作)

**目标**:把 `www.caep.uk` 的 A-record 从 OLD_IP 改为 NEW_IP。**操作 < 1 分钟,DNS TTL 决定生效速度**。

#### 7.1 切换前确认(必做)

```bash
# 1. 确认 NEW_IP 已稳定(跑满 1-7 天)
# 2. 确认所有监控/告警都接到新 GLB 的资源上
# 3. 跟业务方同步切换时间窗口(建议低峰期)
# 4. B owner 在场待命(万一 apiname3 出问题)
```

#### 7.2 切换操作

```bash
# ★ 关键命令 — 根据你实际 DNS 服务商
# Cloud DNS 示例:
gcloud dns record-sets update www.caep.uk \
  --zone=<zone-name> \
  --type=A \
  --ttl=300 \
  --rrdatas=$NEW_IP

# 切换瞬间的 sanity check(本地 dig)
dig +short www.caep.uk A
# 期望:返回 NEW_IP

# 立即验证(此时全球递归 DNS 还在 TTL 缓存)
curl -sk https://www.caep.uk/apiname1/healthz
# 期望:HTTP 200(可能部分客户端还是旧 IP 直到 TTL 过期)
```

#### 7.3 DNS 切换后的窗口(关键监控期)

| 时间点 | 应监控的指标 | 期望 |
|--------|-------------|------|
| T+0s(切换瞬间) | DNS 解析返回 NEW_IP | ✓ |
| T+300s(DNS TTL) | 全球客户端全部用 NEW_IP | ✓ |
| T+5min | apiname1/2/3 5xx 率 | < 0.1% |
| T+15min | apiname3 跨 project latency P99 | < 500ms |
| T+1h | Cloud Armor 命中数 = 切换前 × (DNS 流量比) | ✓ |
| T+24h | 零 P0/P1 投诉 | ✓ |

#### 7.4 阶段 7 回滚(若必须)

```bash
# 把 A-record 切回 OLD_IP
gcloud dns record-sets update www.caep.uk \
  --zone=<zone-name> \
  --type=A \
  --ttl=300 \
  --rrdatas=$OLD_IP

# 等待 DNS TTL 过期(< 5 min for TTL=300s),全球回滚完成
```

**回滚条件**:
- P0/P1 故障持续 > 15 min
- apiname3 跨 project 完全不通(说明 B 侧 / PSC 配置有根本问题)
- 数据丢失或安全事件

**回滚影响**:D NS TTL 决定,通常 < 5 min 全网回滚完毕。旧 LB 仍在跑(阶段 8 还没删),流量无缝回到旧路径。

---

### 阶段 8:清理旧 Classic ALB(可选,15 min)

**目标**:删除旧 Classic ALB 资源,**建议保留 7-14 天再删**作为保险。

#### 8.1 清理序列

```bash
# 顺序:FR → Proxy → UM → BS → Cloud Armor → MIG / NEG → cert / IP
# (同 lex-poc-housekeep-consumer-resource.sh 的删除顺序)

# 1. Forwarding Rule(最外层)
gcloud compute forwarding-rules delete $OLD_FR --global --project=$PROJECT --quiet

# 2. Target HTTPS Proxy
gcloud compute target-https-proxies delete <OLD_PROXY> --global --project=$PROJECT --quiet

# 3. URL Map
gcloud compute url-maps delete $OLD_UM --global --project=$PROJECT --quiet

# 4. Backend Services
gcloud compute backend-services delete $OLD_BS_APINAME1 --global --project=$PROJECT --quiet
gcloud compute backend-services delete $OLD_BS_APINAME2 --global --project=$PROJECT --quiet

# 5. Cloud Armor (迁移后通常保留为新 BS 的 policy,所以这一步要看实际是否复用)
# 若复用:$OLD_ARMOR_APINAME1/2 仍被新 BS 引用,不能删
# 若新建:可删

# 6. cert(若不再被新 LB 引用,可删)
# gcloud compute ssl-certificates delete <OLD_CERT> --global --project=$PROJECT --quiet

# 7. 公网 IP
gcloud compute addresses delete <OLD_IP_NAME> --global --project=$PROJECT --quiet
```

#### 8.2 阶段 8 不可逆警告

- ⚠️ 删除资源 **soft delete** 通常 7 天内可恢复
- ⚠️ cert 删除**永久不可逆**(必须在删除前确认有备份 / 已迁移到新 LB)
- ⚠️ 公网 IP 一旦释放,可能分配给别人;**如果以后想回滚,旧 IP 拿不回来**

**建议**:阶段 7 切换后保留旧 LB **至少 7 天**,再决定阶段 8。

---

## 4. 完整资源清单(2 套 LB + 跨 project)

### 4.1 新 Global external ALB 资源(11 类)

| # | 资源 | 类型 | scope | 数量 | 备注 |
|---|------|------|-------|------|------|
| 1 | Static IP `$NEW_GLB_IP` | global | 1 | ★ 阶段 7 DNS 切换目标 |
| 2 | SSL cert `$NEW_CERT` | global | 1 | 复用 A 工程 cert 的副本 |
| 3 | Default BS `${PREFIX}-public-default-bs` | global | 1 | EXTERNAL_MANAGED,挂 dummy MIG |
| 4 | Dummy MIG `${PREFIX}-default-mig` + template | zonal | 1+1 | 仅供 default BS health check |
| 5 | URL Map `$NEW_UM` | global | 1 | 3 path rule + default |
| 6 | Target HTTPS Proxy `$NEW_PROXY` | global | 1 | |
| 7 | Forwarding Rule `$NEW_FR` | global | 1 | EXTERNAL_MANAGED --global |
| 8 | BS `${PREFIX}-apiname1-bs` | global | 1 | EXTERNAL_MANAGED,从旧 BS 迁移 backends |
| 9 | BS `${PREFIX}-apiname2-bs` | global | 1 | EXTERNAL_MANAGED |
| 10 | BS `$NEW_BS_APINAME3` | global | 1 | EXTERNAL_MANAGED,挂 PSC NEG |
| 11 | Cloud Armor `$NEW_ARMOR_APINAME3` | global | 1 | apiname1/2 复用旧 Cloud Armor |
| 12 | PSC NEG `$NEW_NEG_APINAME3` | regional | 1 | 指向 B SA |

### 4.2 跨 project PSC 链路(8 类,B 侧)

跟 baseing-path-cross-project.md §4.1 一样的 8 类资源,**但只服务 apiname3**(独立 SA-3 + 独立 ILB)。

### 4.3 旧 Classic ALB 资源(7 类,阶段 8 才删)

| # | 资源 | 类型 | 处理 |
|---|------|------|------|
| 1 | 旧 Static IP `$OLD_IP` | global | 阶段 8 删(或保留) |
| 2 | 旧 SSL cert | global | 阶段 8 删(若已迁 cert 引用) |
| 3 | 旧 Target HTTPS Proxy | global | 阶段 8 删 |
| 4 | 旧 URL Map | global | 阶段 8 删 |
| 5 | 旧 BS (apiname1/apiname2) | global | 阶段 8 删(已 detach) |
| 6 | 旧 Cloud Armor | global | 阶段 8 删(若已迁移到新 BS) |
| 7 | 旧 Forwarding Rule `$OLD_FR` | global | 阶段 8 删 |

---

## 5. 严格说法 vs 简化说法对照

| 简化说法 | 严格说法 | 文档应使用的措辞 |
|---------|---------|----------------|
| "迁移 LB" | **新建一个** Global external ALB,旧 Classic ALB 保留到阶段 8 才删 | "在阶段 7 之前,旧 LB 仍是 fallback;阶段 8 才删旧 LB" |
| "切换 DNS" | DNS TTL 决定生效时间,全球递归 DNS 缓存过期前仍可能有客户端走旧 IP | "DNS 切换是渐进的,TTL=300s 通常 < 5 min 全网生效" |
| "apiname3 走 PSC" | apiname3 的 **BS 在 A 工程**(EXTERNAL_MANAGED),BS 挂 PSC NEG → 跨 project 到 B 侧 SA → B 侧 ILB → B 侧 MIG | "PSC 是 A 工程 BS 的 backend 类型,不是 A 工程 LB 的 backend 类型" |
| "把 Cloud Armor 迁过去" | **复用** 旧 Cloud Armor policy,不新建;只需 update BS 把 security-policy 字段指向 | "Cloud Armor policy 本身不动,只是 BS 引用关系变了" |
| "回滚就是把 DNS 切回去" | 旧 LB 必须在阶段 7 之前**保持运行**,且原 URL Map / BS 仍可服务;否则 DNS 切回会 404 | "回滚前提:旧 LB 完整保留,URL Map / BS / Cloud Armor 都没拆" |
| "阶段 8 是清理" | 阶段 8 是**不可逆**操作(soft delete 后 7 天内可恢复,但 IP 不能复用) | "阶段 8 必须等阶段 7 稳定运行 7-14 天后再做" |
| "BS type 必须换 EXTERNAL_MANAGED" | **apiname1/2 的 BS**:可继续 EXTERNAL(挂本工程 backend);**apiname3 的 BS**:必须 EXTERNAL_MANAGED(挂 PSC NEG) | "BS type 由 backend 类型决定:本工程 backend → EXTERNAL OK;跨 project PSC NEG → 必须 EXTERNAL_MANAGED" |
| "旧 Classic ALB 不能挂 PSC NEG" | 旧 Classic ALB 的 EXTERNAL BS **不能**直接挂 PSC NEG,但**可挂 EXTERNAL_MANAGED BS**(side door),EXTERNAL_MANAGED BS 又能挂 PSC NEG | "旧 Classic ALB 通过 side door 也能跑 PSC NEG(详见 class-application-loadbalancer-cross-project.md §1);本方案不依赖 side door,因为新 GLB 已经是 EXTERNAL_MANAGED" |

---

## 6. 风险矩阵与缓解

| # | 风险 | 概率 | 影响 | 缓解 |
|---|------|------|------|------|
| 1 | **DNS 切换后 apiname3 跨 project 故障**(B 侧 SA 未 approve / PSC NEG 状态错) | 中 | 高(P0) | 阶段 4-5 严格走完;阶段 7 在场监控;30 min 内回滚 |
| 2 | **DNS 切换后 latency 飙升**(B 侧网络路径有问题) | 低 | 中 | 阶段 6 灰度期监测 P99;提前 baseline |
| 3 | **旧 LB 误删 / 误改** | 低 | 高 | 阶段 7 之前**禁止**对旧 LB 做任何改动;阶段 8 才删 |
| 4 | **Cloud Armor policy 误绑**(绑到错误 BS) | 低 | 中 | 阶段 2 验证 + 阶段 5 复测;每个 BS 单独 `describe` 确认 securityPolicy 字段 |
| 5 | **cert 不匹配**(新 LB 的 cert SAN 不含 www.caep.uk) | 低 | 高(P0) | 阶段 1 验证 cert 副本;阶段 5 `openssl s_client` 确认 |
| 6 | **Dummy MIG 在 default path 上给用户暴露** | 低 | 低 | 阶段 7 之前 default path 几乎没人走(因为 apiname1/2/3 都被 path rule 命中);阶段 7 后立即被切走 |
| 7 | **Org Policy 没 GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS 白名单** | 低(已拿到) | P0(创建失败) | 阶段 0 必须验证 |
| 8 | **PSC NEG 数据面状态 None**(初次连接慢) | 中 | 中 | 阶段 4 等 5-10 min 让数据面就绪;阶段 5 复测 |
| 9 | **URL Map path rule longest-prefix 误命中**(`/apiname12` 命中 `/apiname1`) | 低 | 中 | path rule 用 `/apiname1/*`(末尾星号 + 斜杠);阶段 5 复测 |
| 10 | **阶段 8 公网 IP 释放后无法拿回** | 中(若回滚需要) | 高 | 阶段 8 前确保 DNS 切到 NEW_IP 已 > 7 天;或者保留旧 IP(Strategy B,$7/月) |

---

## 7. 端到端验证 checklist(阶段 5 + 阶段 7 各跑一次)

### 7.1 资源就绪验证

- [ ] 旧 LB 资源全部存在且正常(`gcloud compute forwarding-rules describe $OLD_FR --global --format=...`)
- [ ] 新 LB 资源全部存在且正常(11 类)
- [ ] B 侧 SA 状态 ACCEPTED
- [ ] A 侧 PSC NEG `pscConnectionId` 非空
- [ ] 3 个 BS 各自 health check PASS
- [ ] 3 个 Cloud Armor policy 各自 binding 到对应 BS

### 7.2 流量验证

- [ ] 走 OLD_IP:apiname1/2 返回 200 + 业务响应(回归)
- [ ] 走 NEW_IP:apiname1/2 返回 200 + 业务响应(阶段 5 新测)
- [ ] 走 NEW_IP:apiname3 返回 200 + **B 侧**业务响应(★ 关键)
- [ ] 走 NEW_IP:default path 返回 default BS 响应
- [ ] LB log 确认 3 个 path rule 各自命中正确 BS

### 7.3 DNS 切换后(阶段 7 专有)

- [ ] `dig +short www.caep.uk A` 返回 NEW_IP
- [ ] 全球递归 DNS 在 TTL 内切到 NEW_IP
- [ ] 公网 curl `https://www.caep.uk/apiname1` 返回 200
- [ ] 公网 curl `https://www.caep.uk/apiname3` 返回 200(★ 验证 B 侧)
- [ ] Cloud Armor 命中数正常
- [ ] latency P99 < 500ms

---

## 8. 推荐方案(最终定型)

> **本方案的最终定型依据**:Google 官方 Global external ALB 是 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` 白名单唯一支持的公网 L7 LB(Lex 已拿到该白名单,见 `Summarize-current-implementation.md` §3);PSC NEG + EXTERNAL_MANAGED BS 的 side door(已在 `baseing-path-cross-project.md` §2.2 + `class-application-loadbalancer-cross-project.md` §1 验证);DNS 切换是渐进过程(TTL 决定)。

**7 阶段 + 1 次 DNS 切换**:
1. 阶段 0:Pre-flight ✓
2. 阶段 1:新建 Global external ALB 骨架(IP + cert + default BS + URL Map + Proxy + FR)✓
3. 阶段 2:apiname1/2 迁移(新建 BS,复用 backend + Cloud Armor)✓
4. 阶段 3:Master B 侧 apiname3 入口(SA + ILB + MIG nginx + K8s Gateway)✓
5. 阶段 4:apiname3 A 工程 BS + Cloud Armor + PSC NEG ✓
6. 阶段 5:端到端测试 ✓
7. 阶段 6:灰度切换 1-7 天 ✓
8. 阶段 7:**DNS 切换**(`www.caep.uk` A-record → NEW_IP) ✓
9. 阶段 8:清理旧 LB(等 7-14 天再删)

**关键约束满足**:
- ① 旧 LB 不动直到阶段 8 ✓
- ② 新 LB 满足 Org Policy 白名单 ✓
- ③ apiname1/2 业务逻辑零变化(同 backend + 同 Cloud Armor)✓
- ④ apiname1/2/3 BS 都在 A 工程(独立 Cloud Armor 绑定)✓
- ⑤ apiname3 跨 project PSC NEG 到 Master B ✓
- ⑥ 全过程可回滚(任何阶段,只要 DNS 还指向 OLD_IP,100% 旧 LB 状态)✓
- ⑦ DNS 切换是唯一对外可见操作(< TTL 全网生效)✓

---

## 9. 引用与延伸阅读

### 9.1 同目录姊妹文档

- **`/Users/lex/git/gcp/ingress/public-tls-basingpath-cross/baseing-path-cross-project.md`** — Global/Regional external ALB 场景的完整 7 步 install + nginx.conf + K8s HTTPRoute(本方案 B 侧全引用此 doc)
- **`/Users/lex/git/gcp/ingress/public-tls-basingpath-cross/class-application-loadbalancer-cross-project.md`** — Classic ALB side door 模式(本方案不依赖,因为新 GLB 已是 EXTERNAL_MANAGED)
- **`/Users/lex/git/gcp/ingress/public-tls-basingpath-cross/verify-glb-type.sh`** — 验证现网 LB type(对应阶段 0)

### 9.2 A 工程现网参考

- **`/Users/lex/git/gcp/ingress/public-tls-ingress/Summarize-current-implementation.md`** §3 — Org Policy 白名单 + `online-consume.sh` 是 Lex 现网跑通的 Global GLB 链路,本方案的命令风格沿用此脚本
- **`/Users/lex/git/gcp/ingress/public-tls-ingress/scripts/online-consume.sh`** — 现网 Global GLB install 脚本模板(命令风格 + 命名规则 + 幂等检查的参考)
- **`/Users/lex/git/gcp/ingress/public-tls-ingress/scripts/lex-poc-housekeep-consumer-resource.sh`** — 旧资源删除顺序参考(本方案阶段 8)
- **`/Users/lex/git/gcp/ingress/public-tls-ingress/PSC-support.md`** §2 — GCP LB × PSC 兼容矩阵

### 9.3 B 侧 Master 工程

- **`/Users/lex/git/knowledge/cloud/k8s/k8s-gateway/public-fqdn-explorer.md`** — Master B 工程 5 方案 + nginx.conf + MIG template(1146 行,本方案 B 侧全引用此 doc)

### 9.4 权威证据 / 来源日期

| # | 官方来源 URL | 验证日期 | 关键原话 |
|---|---|---|---|
| R1 | `https://docs.cloud.google.com/vpc/docs/private-service-connect-backends` | 2026-08-07 | "Global backend services that access published services can be associated with multiple Private Service Connect NEGs"(Global BS + PSC NEG 多 backend 规则) |
| R2 | `https://docs.cloud.google.com/vpc/docs/private-service-connect-compatibility` | 2026-08-07 | "Global external Application Load Balancer ... HTTP HTTPS HTTP2 IPv4"(Global external ALB 支持 PSC NEG 消费端) |
| R3 | `https://cloud.google.com/compute/docs/load-balancing/http/` | 2026-08-07 | "It is possible to attach EXTERNAL_MANAGED backend services to EXTERNAL forwarding rules."(Classic ALB side door,本方案不依赖但知识储备) |
| R4 | `https://cloud.google.com/load-balancing/docs/https` | 2026-08-07 | "For regional external Application Load Balancers only, a proxy-only subnet is used..."(Global external ALB **不需要** proxy-only subnet) |
| R5 | `https://cloud.google.com/armor/docs/cloud-armor-security-policies` | 2026-08-07 | "Cloud Armor security policies can be attached only to backend services."(BS 1:1 绑 Cloud Armor) |
| R6 | `https://cloud.google.com/load-balancing/docs/url-map` | 2026-08-07 | "A URL map is a set of rules for routing incoming HTTP(S) requests to specific backend services or backend buckets."(URL Map path rule 标准用法) |