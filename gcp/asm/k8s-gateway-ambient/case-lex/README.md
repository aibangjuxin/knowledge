# case-lex — Lex 个人 ambient waypoint + ListenerSet 配置样本

> 这是 **ba000000-lex-int** 业务 namespace 切到 Istio ambient 模式,并接入
> K8s Gateway API (Gateway + ListenerSet + HTTPRoute) 的完整资源清单。
>
> 本目录**不直接部署** — 没有真实集群可跑(见 yaml-assessment.md §10 局限性)。
> 仅作**配置参考 / 蓝图 / 审计对象**,待 Gateway / cert-manager 到位后实际 apply。

---

## 0. TL;DR

- **业务 ns**: `ba000000-lex-int` (ambient 模式)
- **入口路径**: 外部 → GCP ILB → Gateway `lex-gw-int` → ListenerSet `lex-team-listenerset` → HTTPRoute `app-route` → Service `app:80` → Pod `app:8080`
- **mesh 路径**: 业务 pod ↔ waypoint `waypoint-int` (L7) ↔ ztunnel (L4 mTLS)
- **10 个 YAML 文件, 22 个 resources,全部 yaml schema 验证通过**

---

## 1. 文件清单 (10 个 YAML)

| # | 文件 | 资源数 | 角色 | 状态 |
|---|---|---|---|---|
| 00 | `00-namespace-ba000000-lex-int.yaml` | 1 NS | 业务 ns + 9 labels | ✅ Lex 线上 |
| 01 | `01-waypoint-int.yaml` | 1 GW + 1 PDB | per-ns waypoint (HA 2 副本) | ✅ Lex 线上 |
| 02 | `02-network-policies.yaml` | 9 NP | L4 firewall (deny-all + 白名单) | ✅ Lex 线上 (NP-5/7 已校准) |
| 03 | `03-mesh-security.yaml` | 1 PA + **2 AuthZ** | STRICT mTLS + AuthZ 收口 | ✅ Lex 已精简 (原 4 doc → 3 doc) |
| 05 | `05-lex-listenerset.yaml` | 1 ListenerSet | `*.lex.caep.uk` wildcard + TLS Terminate | 🆕 本轮外推 |
| 06 | `06-app-serviceaccount.yaml` | 1 SA | KSA + Workload Identity 绑 GSA 占位 | 🆕 本轮外推 |
| 07 | `07-app-configmap.yaml` | 1 CM | nginx 8080 config + X-Tenant 头注入 | 🆕 本轮外推 |
| 08 | `08-app-deployment.yaml` | 1 Deploy + 1 Service | nginx + 3 probe + ClusterIP 80→8080 | 🆕 本轮外推 |
| 09-01 | `09-01-app-httproute.yaml` | **2 HTTPRoute** | `http.lex.caep.uk` → `plat-abjx-lex-testing-0-0-0-service:80` (two-tier gateway pattern) | 🆕 本轮外推 (改进版, 原 09 已删除) |
| **总计** | | **22 resources** | | |

**附属文档 (4 个 MD)**:

| 文件 | 角色 |
|---|---|
| `assessment-ingress.md` | ingress 流量完整路径分析 (5 条路径 + 深度防御) |
| `yaml-assessment.md` | v5 残余风险审计 + 评估合理性自审 (§8) |
| `analyze-httproute.md` | 两段 HTTPRoute 工作原理详解 (two-tier gateway pattern) |
| `README.md` | 当前文档 |

---

## 2. 数据流(完整链路)

```
Internet
  ↓
GCP Internal LB (abjx-gw-int Gateway 的 ILB annotation)
  ↓
┌──────────────────────────────────────────────────────────────┐
│ lex-gw-int ns                                                │
│ Gateway "lex-gw-int" (gatewayClassName: istio, sidecar)     │
│   listener: http:80                                          │
│   allowedListeners.selector: gateway.aibang.com/listener-enabled=true │
└──────────────────────────────────────────────────────────────┘
  ↓ parentRef: Gateway
┌──────────────────────────────────────────────────────────────┐
│ ba000000-lex-int ns (业务 ns 内, NOT 平台层独立 ns)         │
│ ListenerSet "lex-team-listenerset"                           │
│   listener: https:443, hostname *.lex.caep.uk                │
│   TLS Terminate + cert lex-caep-uk-tls (cert-manager)       │
│   allowedRoutes.selector: gateway-access=ba000000-lex-int    │
└──────────────────────────────────────────────────────────────┘
  ↓ parentRef: ListenerSet
┌──────────────────────────────────────────────────────────────┐
│ ba000000-lex-int ns (业务 ns, ambient)                       │
│ HTTPRoute 1: "app-route-ingress" (parentRef=ListenerSet)     │
│   hostname: http.lex.caep.uk                                 │
│   rules: path / → backendRef plat-abjx-lex-testing-0-0-0-service:80│
│   filters: HSTS / nosniff / -Server / X-ABJX-CAP-Correlation-Id│
└──────────────────────────────────────────────────────────────┘
  ↓ HBONE 15008 → ztunnel → waypoint
┌──────────────────────────────────────────────────────────────┐
│ ba000000-lex-int ns (业务 ns, ambient waypoint)              │
│ HTTPRoute 2: "app-route-waypoint" (parentRef=Service)        │
│   rules: path / → backendRef plat-abjx-lex-testing-0-0-0-service:80│
│   filters: X-Tenant-Id / X-Forwarded-Proto: https           │
│           响应头: X-Ambient-Waypoint: waypoint-int           │
└──────────────────────────────────────────────────────────────┘
  ↓ ClusterIP Service
Service "plat-abjx-lex-testing-0-0-0-service" (port 80 → targetPort 8080, appProtocol: http)
  ↓
Deployment "app" (replicas 2, nginxinc/nginx-unprivileged:1.27-alpine)
  - containerPort: 8080
  - SA: app-ksa (Workload Identity → app-gsa, 调 GCS/BigQuery)
  - 3 probe (liveness/readiness/startup → /healthz)
  ↓
┌──────────────────────────────────────────────────────────────┐
│ ambient mesh 层 (NS 级 dataplane-mode=ambient)               │
│   ztunnel (节点 DaemonSet) — L4 mTLS                         │
│   waypoint "waypoint-int" (per-ns, 2 副本) — L7 拦截         │
│   AuthZ deny-all + allow-from-waypoint-to-workloads          │
│   PA STRICT (强制走 mesh)                                    │
└──────────────────────────────────────────────────────────────┘
```

---

## 3. Apply 顺序(参考,实际需 devops/qa 执行)

```bash
# ====== 前置 (不在本目录) ======
# - istio-system 必须先装 ambient 组件
#   (ztunnel DaemonSet + istio-cni DaemonSet + istiod)
#   见同仓库 02-install-ambient-helm.md
# - Gateway "lex-gw-int" 必须先创建 (lex-gw-int ns, abjx-gw-int 模式)
# - cert-manager ClusterIssuer + Certificate 必须先配
#   自动生成 Secret "lex-caep-uk-tls" (wildcard *.lex.caep.uk)
#   在 ba000000-lex-int ns (业务 ns 内, NOT 平台层独立 ns)
# - GKE Workload Identity 绑定必须先做 (gcloud iam 命令)

# ====== 基础规则 (case-lex/00-03) ======
kubectl apply -f 00-namespace-ba000000-lex-int.yaml           # 1. NS
kubectl apply -f 01-waypoint-int.yaml                          # 2. Waypoint + PDB
kubectl apply -f 02-network-policies.yaml                      # 3. 9 NetworkPolicy
kubectl apply -f 03-mesh-security.yaml                         # 4. PA + 2 AuthZ

# ====== 平台层 (case-lex/05) ======
kubectl apply -f 05-lex-listenerset.yaml                       # 5. ListenerSet

# ====== 业务层 (case-lex/06-09-01) ======
kubectl apply -f 06-app-serviceaccount.yaml                     # 6. KSA
kubectl apply -f 07-app-configmap.yaml                          # 7. nginx config
kubectl apply -f 08-app-deployment.yaml                         # 8. Deploy + Service
kubectl apply -f 09-01-app-httproute.yaml                       # 9. 两段 HTTPRoute
```

**Apply 顺序关键依赖**:
- 00-03: namespace 必须先建(waypoint / NetPol / AuthZ 都依赖 ns)
- 05: ListenerSet 不需要独立 ns (在业务 ns 内, 跟 00 同时存在)
- 06-09-01: KSA 先建,Pod 才能用;Service 先建,HTTPRoute 才能引
- 09-01: HTTPRoute 依赖 ListenerSet 已存在 (parentRef)

---

## 4. 关键设计决策

### 4.1 ambient mesh 三件套(00-01 + 03)

3 个 istio label 同时打在业务 ns(00- 文件):
- `istio.io/dataplane-mode=ambient` → 启用 in-pod iptables 重定向,ztunnel 拦截 mesh 流量
- `istio.io/ingress-use-waypoint=waypoint` → 让 ingress 流量也走 waypoint,**否则默认绕过**(见 [10-waypoint-gateway-coexistence.md §1.1](../10-waypoint-gateway-coexistence.md))
- `istio.io/use-waypoint=waypoint` → enroll 整个 ns 到 waypoint(L7 拦截粒度)

### 4.2 PA STRICT + AuthZ deny-all + 1 条 allow(03- 文件)

- PA STRICT: ambient 默认 mTLS 的兜底,不能用 DISABLE(06-policy-capabilities.md §3.1)
- AuthZ `deny-all`: ns-wide deny,任何跨服务调用需 allow 显式放行
- AuthZ `allow-from-waypoint-to-workloads`: ns-wide allow + waypoint SA,additive 语义下唯一允许路径

### 4.3 NetPol 默认 deny + 白名单(02- 文件)

- NP-1 `default-deny-all`: 基线,所有放行靠后续 NP
- NP-3 `default-allow-egress-public-cidr-block`: 出口公网(宽松规则,生产建议收敛)
- NP-5/6/7: HBONE 端口 (15008) 显式 allow,否则 mesh 流量被 CNI 拦截(08-ambient-networkpolicy.md §1.1)
- NP-8: 同 ns 业务 pod 互访(用 namespaceSelector 业务 label,详见 yaml-assessment.md H-3)
- NP-9: kubelet 探针走 link-local 169.254.7.127/32(08-ambient-networkpolicy.md §1.2)

### 4.4 Gateway + ListenerSet 业务 ns 内(05- 文件)

- **纠正 v4 设计**: ListenerSet **不在平台层独立 ns**, 而是在**业务 ns 内** (`ba000000-lex-int`)
- 与 Lex 线上 plat-abjx-lex-testing 配置模式一致
- Gateway (`lex-gw-int` ns) → ListenerSet (`ba000000-lex-int` ns) → HTTPRoute 1 (业务 ns, 同 ns)
- ListenerSet 用 `gateway.aibang.com/listener-enabled: true` label 挂载 Gateway
- HTTPRoute 1 用 `gateway-access: ba000000-lex-int` label 挂载 ListenerSet (由 ListenerSet.allowedRoutes.selector 限定)

### 4.5 业务 pod 8080 + KSA + Workload Identity(06-08)

- Lex Q1 答复: Gateway TLS 终止 → plain HTTP/8080 给 pod(nginx 不 listen 443)
- Lex Q2 答复: 业务调 GCS / BigQuery → 必须 KSA + GSA + Workload Identity 绑定
- 3 个 probe 都打 /healthz,scheme HTTP
- nginxinc/nginx-unprivileged 镜像,UID 101 非 root
- Service 命名: `plat-abjx-lex-testing-0-0-0-service` (贴 Lex 平台业务命名约定)

### 4.6 HTTPRoute 两段式 (two-tier gateway pattern)

- **两个 HTTPRoute 资源** 各自指向同一 Service:
  - HTTPRoute 1 `app-route-ingress`: parentRef=ListenerSet, hostnames=`http.lex.caep.uk`
  - HTTPRoute 2 `app-route-waypoint`: parentRef=Service, 无 hostnames (waypoint 拦截所有入站)
- Istio ambient 根据流量路径自动选择由哪段执行:
  - 入口 (ingress → waypoint): 两段都执行 (Gateway L7 + waypoint L7)
  - east-west (业务 pod → 业务 pod): 只执行 HTTPRoute 2 (waypoint L7)
- 删任何一段都会让特定流量路径失效 (详见 `analyze-httproute.md` §6)
- 未来加第 2 个 hostname(比如 `api.lex.caep.uk`),复制 HR1 改 hostname 和 backendRefs 即可

---

## 5. ⚠️ 推测未验证项

> 没有真集群,以下基于文档推测,真实环境需要校准。

| 项 | 推测值 | 校准方式 |
|---|---|---|
| Gateway ns 名 | `lex-gw-int` (类比 abjx-gw-int) | `kubectl get gateway -A` |
| Gateway name | `lex-gw-int` (与 ns 同名) | 同上 |
| ListenerSet cert | `lex-caep-uk-tls` (cert-manager 自动, 在业务 ns) | `kubectl get certificate -n ba000000-lex-int` |
| Cert-manager ClusterIssuer | 假设已配 (Google CAS / Let's Encrypt) | `kubectl get clusterissuer` |
| Workload Identity GCP project | `aibang-12345678-ajbx-dev` (从 draft.md 抄) | gcloud config get-value project |
| GSA name | `app-gsa` | gcloud iam service-accounts list |
| KSA → GSA binding | 已配 (默认模式) | gcloud iam service-accounts get-iam-policy |
| 业务端口清单 | 8080 (单端口, 简化) | `kubectl get svc -n ba000000-lex-int` |

---

## 6. 反向:这些 YAML **不覆盖**的场景

- ❌ Gateway `lex-gw-int` 本身(不在本目录,需另写,类比 abjx-gw-int)
- ❌ cert-manager ClusterIssuer 配置
- ❌ Secret `lex-caep-uk-tls` 创建(cert-manager 自动)
- ❌ Workload Identity `gcloud iam` 绑定命令
- ❌ `kubectl apply` 顺序脚本(详见 §3 但需 devops 编写)
- ❌ e2e verify 脚本
- ❌ egress Gateway 控制(本场景是 ingress 入口模式)
- ❌ 跨集群 mesh(dev 集群单集群)
- ❌ multi-network ambient(1.30 仍 beta)

---

## 7. 评估与审计

详见同目录两份文档:

- **`yaml-assessment.md`** (v5): 残余风险审计 + 评估合理性自审
  - 3 HIGH: `ENABLE_INGRESS_WAYPOINT_ROUTING` flag (Q6) / AuthZ 缺 `default` SA (Q4) / NP-8 namespaceSelector (Q7)
  - 2 MEDIUM: NP-6 端口限制形同虚设 / NS label 命名不联动
  - 7 个待校准问题 (Q1-Q7, Q1-Q3 已答)

- **`assessment-ingress.md`**: ingress 流量完整路径分析
  - 5 条路径对比 (P1/P2/P3/P4/P5)
  - 深度防御分析
  - 失效场景清单

---

## 8. 关联文档

**同仓库**:
- `../00-ambient-vs-sidecar.md` — ambient vs sidecar 总览
- `../03-waypoint-design.md` §5 — waypoint HA 模板
- `../06-policy-capabilities.md` — AuthZ/PA 在 ambient 下的能力矩阵
- `../08-ambient-networkpolicy.md` — NetPol 与 ztunnel 协同规则
- `../10-waypoint-gateway-coexistence.md` §1 — ingress 与 waypoint 默认行为

**同目录**:
- `assessment-ingress.md` — ingress 流量完整路径分析
- `yaml-assessment.md` — v5 残余风险审计
- `analyze-httproute.md` — 两段 HTTPRoute 工作原理详解 (强烈推荐)

**类比参考** (k8s-gateway 目录):
- `../../k8s-gateway/03-gateway/abjx-gw-int.yaml` — Gateway YAML 模板
- `../../k8s-gateway/05-listenerset/team1-listenerset.yaml` — ListenerSet YAML 模板
- `../../k8s-gateway/06-runtime/newapi-deployment.yaml` — Deployment 模板
- `../../k8s-gateway/06-runtime/newapi-httproute.yaml` — HTTPRoute 模板
- `../../k8s-gateway/draft.md` — istio install + Gateway 创建步骤

---

*Generated by architect-gcp Bot — 配置蓝图,未部署。*
*9 个 YAML + 4 个 MD 全部 schema 验证通过。*
*等待 Gateway / cert-manager 到位后再做下一轮审计。*