- [tenant-tls-setup-https.md — Producer ILB 二次终结 TLS(全链路 HTTPS 实现)](#tenant-tls-setup-httpsmd--producer-ilb-二次终结-tls全链路-https-实现)
  - [0. TL;DR — 全 HTTPS 链路通了](#0-tldr--全-https-链路通了)
    - [Producer VPC (`ajbx-tenant-vpc`)](#producer-vpc-ajbx-tenant-vpc)
    - [Consumer VPC (`cinternal-vpc1`)](#consumer-vpc-cinternal-vpc1)
    - [e2e curl 输出\*\*:](#e2e-curl-输出)
    - [logs](#logs)
  - [1. 为什么从 HTTP backend 升级到全 HTTPS(用户质疑点)](#1-为什么从-http-backend-升级到全-https用户质疑点)
  - [2. 改动全貌](#2-改动全貌)
    - [2.1 Producer VPC 改动](#21-producer-vpc-改动)
    - [2.2 Consumer VPC 改动](#22-consumer-vpc-改动)
    - [2.3 不动的资源](#23-不动的资源)
  - [3. 详细执行步骤(实际命令 + 输出)](#3-详细执行步骤实际命令--输出)
    - [3.1 上传 ILB 的 SSL cert(Producer VPC, 同一个 TrustAsia cert)](#31-上传-ilb-的-ssl-certproducer-vpc-同一个-trustasia-cert)
    - [3.2 建 HTTPS Health Check(port 443, /healthz)](#32-建-https-health-checkport-443-healthz)
    - [3.3 更新 Backend Service 引用新 HC + 删旧 HC](#33-更新-backend-service-引用新-hc--删旧-hc)
    - [3.4 删 SA(因为引用旧 FR,阻止删)](#34-删-sa因为引用旧-fr阻止删)
    - [3.5 删旧 FR(端口 80,target=HTTP proxy) + 删旧 Target HTTP Proxy](#35-删旧-fr端口-80targethttp-proxy--删旧-target-http-proxy)
    - [3.6 建新 Target HTTPS Proxy](#36-建新-target-https-proxy)
    - [3.7 建新 FR(port 443, target=新 HTTPS proxy)](#37-建新-frport-443-target新-https-proxy)
    - [3.8 重建 SA(引用新 FR)](#38-重建-sa引用新-fr)
    - [3.9 等 producer health check 跑 + 验证](#39-等-producer-health-check-跑--验证)
    - [3.10 Consumer 端:删旧 Backend Service(HTTP),建新(HTTPS)](#310-consumer-端删旧-backend-servicehttp建新https)
    - [3.11 重新 attach Cloud Armor(因为 BS 重建)](#311-重新-attach-cloud-armor因为-bs-重建)
    - [3.12 重建 PSC NEG(delete + create)— 因为 backend service 改 protocol 后,需要重连 SA](#312-重建-psc-negdelete--create-因为-backend-service-改-protocol-后需要重连-sa)
    - [3.13 等 PSC 重连 + SA connected endpoints 1](#313-等-psc-重连--sa-connected-endpoints-1)
  - [4. e2e 验证(全链路 HTTPS)](#4-e2e-验证全链路-https)
  - [5. 完整资源全貌(改后状态)](#5-完整资源全貌改后状态)
    - [5.1 Producer VPC — `ajbx-tenant-vpc`](#51-producer-vpc--ajbx-tenant-vpc)
    - [5.2 Consumer VPC — `cinternal-vpc1`](#52-consumer-vpc--cinternal-vpc1)
    - [5.3 Global 资源](#53-global-资源)
  - [6. 踩过的 4 个新坑(都记到 doc)](#6-踩过的-4-个新坑都记到-doc)
    - [6.1 实际文件名有下划线 — `tenant.taobao.caep.uk_bundle.crt`](#61-实际文件名有下划线--tenanttaobaocaepuk_bundlecrt)
    - [6.2 gcloud CLI `MANAGED` 解析 bug(在 multi-word 值)](#62-gcloud-cli-managed-解析-bug在-multi-word-值)
    - [6.3 `backend-services create --port=443` 不被识别](#63-backend-services-create---port443-不被识别)
    - [6.4 PSC NEG 在 backend service 协议改后需重连](#64-psc-neg-在-backend-service-协议改后需重连)
  - [7. 关于 ILB → MIG 的内部 hop](#7-关于-ilb--mig-的内部-hop)
  - [8. 验证脚本](#8-验证脚本)
  - [Producer backend service health (ILB → MIG, 健康):](#producer-backend-service-health-ilb--mig-健康)
  - [10. References](#10-references)

# tenant-tls-setup-https.md — Producer ILB 二次终结 TLS(全链路 HTTPS 实现)

> **配套文档**:
> - 前置: [`tenant-tls-setup.md`](./tenant-tls-setup.md)(HTTP backend 的初版,记录过程) — **保留作为历史**
> - 总览: [`public-ingress-external-https-lb.md`](./public-ingress-external-https-lb.md)(理论架构)
> - 4 方案对比: [`public-ingress-tenant-project-psc.md`](./public-ingress-tenant-project-psc.md)
> - 用户质疑: [`bs-type.md`](./bs-type.md) — 用户对"为什么 backend service 是 HTTP"的质疑 + 方案二探索
> - cert 文件: [`cert/tenant.taobao.caep.uk_bundle.crt`](./cert/) (TrustAsia DV cert for `tenant.taobao.caep.uk`)
>
> **本新文档**: 用户的方案二(Producer ILB 二次终结 TLS)+ Consumer 端 backend service 改 HTTPS,**让链路每一跳都是 HTTPS**。
> 原 `tenant-tls-setup.md` **保留不动**作为过程记录。

---

## 0. TL;DR — 全 HTTPS 链路通了

| 项 | 之前(HTTP backend) | 现在(全 HTTPS) |
| --- | --- | --- |
| **e2e curl** | `HTTP 200` | **`HTTPS 200`** |
| **External GLB backend service** | `protocol=HTTP` | **`protocol=HTTPS`** ✓ |
| **Producer ILB** | L7 HTTP (port 80) | **L7 HTTPS (port 443)** ✓ |
| **ILB target proxy** | Target HTTP Proxy | **Target HTTPS Proxy** ✓ |
| **ILB cert** | (无, HTTP 不用) | **`ajbx-tenant-vpc-internal-cert` (TrustAsia DV, same as consumer)** ✓ |
| **PSC 隧道** | 通过 | **通过**(新 pscConnectionId: 158673064562262033) |
| **backend MIG** | HTTP 80 + HTTPS 443(双 listener) | **HTTP 80 + HTTPS 443**(不变,MIG 本来就双 serve) |

**完整流量路径**:
```
Internet
  ↓ TLS 1 (TrustAsia cert, SNI=tenant.taobao.caep.uk)
External GLB (EXTERNAL MANAGED, regional, europe-west2)
  ↓ TLS 2 (re-encrypted, TrustAsia cert, SNI=tenant.taobao.caep.uk)
PSC NEG (consumer VPC, cinternal-vpc1) → Cross-VPC PSC tunnel
  ↓ GCP 内部 tunnel
Service Attachment (producer VPC, ajbx-tenant-vpc)
  ↓ TLS 3 (terminated by ILB, TrustAsia cert)
L7 HTTPS ILB (ajbx-tenant-vpc, port 443, target HTTPS proxy)
  ↓ HTTP (terminated TLS, plain HTTP, port 80)
MIG backend (Python HTTP server, 10.0.1.x)
  ↓ 响应反向流回 client
```

### Producer VPC (`ajbx-tenant-vpc`) 
— 完整资源表** (按依赖顺序: 网络 → 计算 → 安全 → LB 链 → cert):

| # | 资源 | 资源名称 | 创建资源的命令 | 状态 | 简单的Description |
| - | --- | --- | --- | --- | --- |
| 1 | VPC | `ajbx-tenant-vpc` | `gcloud compute networks create ajbx-tenant-vpc --project=$PROJECT --subnet-mode=custom` | v1 已建 | custom mode VPC, 隔离的 producer 网络 |
| 2 | Subnet - 普通 | `ajbx-tenant-vpc-europe-west2-abjx-core` | `gcloud compute networks subnets create ajbx-tenant-vpc-europe-west2-abjx-core --project=$PROJECT --network=ajbx-tenant-vpc --region=$REGION --range=10.0.1.0/24 --enable-private-ip-google-access` | v1 已建 | MIG + ILB frontend subnet (10.0.1.0/24) |
| 3 | Subnet - Proxy | `ajbx-tenant-vpc-europe-west2-abjx-proxy` | `gcloud compute networks subnets create ajbx-tenant-vpc-europe-west2-abjx-proxy --project=$PROJECT --network=ajbx-tenant-vpc --region=$REGION --range=10.0.2.0/24 --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE` | v1 已建 | ILB proxy-only subnet (10.0.2.0/24) |
| 4 | Subnet - PSC NAT | `ajbx-tenant-vpc-europe-west2-abjx-psc-nat` | `gcloud compute networks subnets create ajbx-tenant-vpc-europe-west2-abjx-psc-nat --project=$PROJECT --network=ajbx-tenant-vpc --region=$REGION --range=10.0.3.0/24 --purpose=PRIVATE_SERVICE_CONNECT` | v1 已建 | SA 的 SNAT 池 (10.0.3.0/24) |
| 5 | Cloud Router | `ajbx-tenant-vpc-router` | `gcloud compute routers create ajbx-tenant-vpc-router --project=$PROJECT --network=ajbx-tenant-vpc --region=$REGION` | v1 已建 | Cloud NAT 路由 |
| 6 | Cloud NAT | `ajbx-tenant-vpc-nat` | `gcloud compute routers nats create ajbx-tenant-vpc-nat --project=$PROJECT --router=ajbx-tenant-vpc-router --region=$REGION --nat-all-subnet-ip-ranges --auto-allocate-nat-external-ips` | v1 已建 | (备用, 实际 MIG 用 Python 不出网) |
| 7 | Firewall - IAP SSH | `ajbx-tenant-vpc-allow-iap-ssh` | `gcloud compute firewall-rules create ajbx-tenant-vpc-allow-iap-ssh --project=$PROJECT --direction=INGRESS --action=ALLOW --rules=tcp:22 --source-ranges=35.235.240.0/20 --network=ajbx-tenant-vpc --target-tags=tenant-backend` | v1 已建 | IAP SSH 调试 (35.235.240.0/20 是 IAP 段) |
| 8 | Firewall - LB HC | `ajbx-tenant-vpc-allow-lb-hc` | `gcloud compute firewall-rules create ajbx-tenant-vpc-allow-lb-hc --project=$PROJECT --direction=INGRESS --action=ALLOW --rules=tcp:80,tcp:443 --source-ranges=35.191.0.0/16,130.211.0.0/22 --network=ajbx-tenant-vpc --target-tags=http-server,https-server` | v1 已建 | 放行 GCP LB 健康检查来源 (35.191.0.0/16 + 130.211.0.0/22) |
| 9 | Firewall - Internal | `ajbx-tenant-vpc-allow-internal` | `gcloud compute firewall-rules create ajbx-tenant-vpc-allow-internal --project=$PROJECT --direction=INGRESS --action=ALLOW --rules=tcp,udp,icmp --source-ranges=10.0.0.0/8 --network=ajbx-tenant-vpc` | v1 已建 | **关键** — ILB→MIG 内部流量, 没这条 curl 卡 timeout (§3.3 v1 doc) |
| 10 | Firewall - PSC data | `ajbx-tenant-vpc-allow-psc-data` | `gcloud compute firewall-rules create ajbx-tenant-vpc-allow-psc-data --project=$PROJECT --direction=INGRESS --action=ALLOW --rules=tcp:80,tcp:443 --source-ranges=10.0.0.0/8 --network=ajbx-tenant-vpc` | v1 已建 | 兜底, 放行 GCP 内部 IP 段到 backend |
| 11 | Instance Template | `ajbx-tenant-vpc-backend-tmpl` | `gcloud compute instance-templates create ajbx-tenant-vpc-backend-tmpl --project=$PROJECT --machine-type=e2-small --image-family=debian-11 --image-project=debian-cloud --network=ajbx-tenant-vpc --subnet=ajbx-tenant-vpc-europe-west2-abjx-core --region=$REGION --no-address --tags=http-server,https-server,tenant-backend --scopes=https://www.googleapis.com/auth/cloud-platform --metadata-from-file=startup-script=$DOC_DIR/scripts/startup-nginx.sh` | v1 已建 | MIG 模板, startup-script 跑 Python HTTPS server |
| 12 | MIG | `ajbx-tenant-vpc-backend-mig` | `gcloud compute instance-groups managed create ajbx-tenant-vpc-backend-mig --project=$PROJECT --base-instance-name=ajbx-tenant-vpc-backend --template=ajbx-tenant-vpc-backend-tmpl --region=$REGION --size=2 --target-distribution-shape=EVEN` | v1 已建 | 后端池, 2 instances (e2-small, debian-11) |
| 13 | Backend Service | `ajbx-tenant-vpc-internal-bs` | `gcloud compute backend-services create ajbx-tenant-vpc-internal-bs --project=$PROJECT --region=$REGION --load-balancing-scheme=INTERNAL_MANAGED --protocol=HTTP --port-name=http --health-checks=ajbx-tenant-vpc-internal-hc --health-checks-region=$REGION --timeout=30s`  | v1 已建, **v2 update** | producer ILB backend, v1/v2 都用 HTTP 80 跟 MIG 通信 (v2 改了 --health-checks 指向新 HTTPS HC, 见 §3.3) |
| 13-1 | Backend Service | `ajbx-tenant-vpc-internal-bs` | `gcloud compute backend-services create ajbx-tenant-vpc-internal-bs --project=$PROJECT --region=$REGION --load-balancing-scheme=INTERNAL_MANAGED --protocol=HTTPS --port-name=https --health-checks=ajbx-tenant-vpc-internal-https-hc --health-checks-region=$REGION --timeout=30s`  | v1 已建, **v2 update** | producer ILB backend, v1/v2 都用 HTTPS 443 跟 MIG 通信 (v2 改了 --health-checks 指向新 HTTPS HC, 见 §3.3) |
| 14 | URL Map | `ajbx-tenant-vpc-internal-um` | `gcloud compute url-maps create ajbx-tenant-vpc-internal-um --project=$PROJECT --region=$REGION --default-service=ajbx-tenant-vpc-internal-bs` | v1 已建 | 路径路由, default → internal-bs |
| 15 | Internal IP | `ajbx-tenant-vpc-internal-lb-ip` | `gcloud compute addresses create ajbx-tenant-vpc-internal-lb-ip --project=$PROJECT --region=$REGION --subnet=ajbx-tenant-vpc-europe-west2-abjx-core --purpose=GCE_ENDPOINT` | v1 已建 | ILB 内网 IP (10.0.1.4), GCE_ENDPOINT 类型 |
| 16 | Health Check (HTTPS) | `ajbx-tenant-vpc-internal-https-hc` | `gcloud compute health-checks create https ajbx-tenant-vpc-internal-https-hc --project=$PROJECT --region=$REGION --port=443 --request-path=/healthz --check-interval=10s --timeout=5s --healthy-threshold=2 --unhealthy-threshold=3` | **v2 新建** | HTTPS :443 健康检查, 详情 §3.2 |
| 17 | Target HTTPS Proxy | `ajbx-tenant-vpc-internal-https-proxy` | `gcloud compute target-https-proxies create ajbx-tenant-vpc-internal-https-proxy --project=$PROJECT --region=$REGION --url-map=ajbx-tenant-vpc-internal-um --url-map-region=$REGION --ssl-certificates=ajbx-tenant-vpc-internal-cert --ssl-certificates-region=$REGION` | **v2 新建** | ILB HTTPS 终结代理 (引用 cert + 已有 UM), 详情 §3.6 |
| 18 | Forwarding Rule (:443) | `ajbx-tenant-vpc-internal-fr` | `gcloud compute forwarding-rules import ajbx-tenant-vpc-internal-fr --project=$PROJECT --region=$REGION --source=/tmp/fr-spec.yaml` *(YAML 模板见 §3.7，因 gcloud CLI `INTERNAL MANAGED` 解析 bug，必须用 import)* | v2 重建 | port 80→443, target 改 HTTPS proxy (复用已有 IP 10.0.1.4), 详情 §3.7 |
| 19 | Service Attachment | `ajbx-tenant-vpc-internal-sa` | `gcloud compute service-attachments create ajbx-tenant-vpc-internal-sa --project=$PROJECT --region=$REGION --producer-forwarding-rule=ajbx-tenant-vpc-internal-fr --connection-preference=ACCEPT_AUTOMATIC --nat-subnets=ajbx-tenant-vpc-europe-west2-abjx-psc-nat` | v2 重建 | PSC Producer 侧桥接 (引用新 FR), 详情 §3.8 |
| 20 | SSL Certificate (regional) | `ajbx-tenant-vpc-internal-cert` | `gcloud compute ssl-certificates create ajbx-tenant-vpc-internal-cert --project=$PROJECT --region=$REGION --certificate=$CERT_FILE --private-key=$KEY_FILE` | **v2 新建** | Producer ILB 二次终结 TLS 用的 cert, 与 Consumer GLB 同源 TrustAsia DV, 详情 §3.1 |

> **不动的资源**: 上表 #1–15 全部 v1 已建, v2 不重建; **只有 #13 Backend Service 的 `--health-checks` 字段需 update** 指向新 HTTPS HC (见 §3.3)。

### Consumer VPC (`cinternal-vpc1`) 
— 完整资源表** (按依赖顺序: 已有网络 → proxy-only → GLB 链 → 安全 → 关联操作):

| # | 资源 | 资源名称 | 创建资源的命令 | 状态 | 简单的Description |
| - | --- | --- | --- | --- | --- |
| 1 | VPC | `aibang-12345678-ajbx-dev-cinternal-vpc1` | *(环境已有, 不需要命令)* | v1 之前已存在 | Consumer VPC (含 GKE cluster, bastion) |
| 2 | Subnet - 核心 | `cinternal-vpc1-europe-west2-abjx-core` | *(环境已有, 不需要命令)* | v1 之前已存在 | PSC NEG 分配接入 IP 用的 subnet |
| 3 | Subnet - GKE | `cinternal-vpc1-europe-west2-abjx-gke-core-01` | *(环境已有, 不需要命令)* | v1 之前已存在 | 保留, GKE cluster 用, 不动 |
| 4 | Subnet - Proxy | `cinternal-vpc1-europe-west2-abjx-proxy` | `gcloud compute networks subnets create cinternal-vpc1-europe-west2-abjx-proxy --project=$PROJECT --network=aibang-12345678-ajbx-dev-cinternal-vpc1 --region=$REGION --range=192.168.96.0/24 --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE` | v1 已建 | External GLB proxy-only subnet (192.168.96.0/24) |
| 5 | External Static IP | `ajbx-public-glb-ip` | `gcloud compute addresses create ajbx-public-glb-ip --project=$PROJECT --region=$REGION --network-tier=PREMIUM --ip-version=IPV4` | v1 已建 | GLB 入口 IP = 34.105.229.97 (PREMIUM tier) |
| 6 | SSL Certificate | `ajbx-public-cert` | `gcloud compute ssl-certificates create ajbx-public-cert --project=$PROJECT --region=$REGION --certificate=$CERT_FILE --private-key=$KEY_FILE` | v1 已建 | GLB 入口 cert, TrustAsia DV (`tenant.taobao.caep.uk`) |
| 7 | Target HTTPS Proxy | `ajbx-public-proxy` | `gcloud compute target-https-proxies create ajbx-public-proxy --project=$PROJECT --region=$REGION --url-map=ajbx-public-um --url-map-region=$REGION --ssl-certificates=ajbx-public-cert --ssl-certificates-region=$REGION` | v1 已建 | GLB HTTPS 终结代理 (引用 cert + UM) |
| 8 | URL Map | `ajbx-public-um` | `gcloud compute url-maps create ajbx-public-um --project=$PROJECT --region=$REGION --default-service=ajbx-public-bs` | v1 已建 | 路径路由, default → public-bs |
| 9 | Forwarding Rule (:443) | `ajbx-public-fr` | `gcloud compute forwarding-rules create ajbx-public-fr --project=$PROJECT --region=$REGION --load-balancing-scheme=EXTERNAL_MANAGED --target-https-proxy=ajbx-public-proxy --target-https-proxy-region=$REGION --address=ajbx-public-glb-ip --address-region=$REGION --ports=443 --network-tier=PREMIUM --network=aibang-12345678-ajbx-dev-cinternal-vpc1` | v1 已建 | GLB 入口, port 443 (EXTERNAL_MANAGED, PREMIUM) |
| 10 | Cloud Armor (regional) | `ajbx-public-armor` | `gcloud compute security-policies create ajbx-public-armor --project=$PROJECT --region=$REGION --description="Public GLB DDoS + rate limit"` *(完整规则见 tenant-tls-setup.md §7 阶段 E)* | v1 已建 | rate limit 200/min, ban 600s (regional, 必须跟 regional BS 配) |
| 11 | Bastion VM | `dev-lon-bastion-public` | *(环境已有, 不需要命令)* | v1 之前已存在 | IAP SSH 调试入口, 不动 |
| 12 | GKE cluster | `dev-lon-cluster-xxxxxx` | *(环境已有, 不需要命令)* | v1 之前已存在 | 保留, 不动 |
| 13 | Backend Service (HTTPS) | `ajbx-public-bs` | `gcloud compute backend-services import ajbx-public-bs --project=$PROJECT --region=$REGION --source=/tmp/bs-spec.yaml --quiet` *(YAML 模板见 §3.10，因 gcloud CLI `EXTERNAL MANAGED` 解析 bug，必须用 import)* | v2 重建 | External GLB backend, protocol HTTP→HTTPS, port-name http→https, 详情 §3.10 |
| 14 | PSC NEG | `ajbx-public-neg` | `gcloud compute network-endpoint-groups create ajbx-public-neg --project=$PROJECT --region=$REGION --network-endpoint-type=PRIVATE_SERVICE_CONNECT --psc-target-service=projects/$PROJECT/regions/$REGION/serviceAttachments/ajbx-tenant-vpc-internal-sa --subnet=cinternal-vpc1-europe-west2-abjx-core --network=aibang-12345678-ajbx-dev-cinternal-vpc1` | v2 重建 | 跨项目 PSC 桥接, consumer 侧入口, 详情 §3.12 |
| 15 | **Add NEG → BS** (关联操作) | `ajbx-public-bs` ← `ajbx-public-neg` | `gcloud compute backend-services add-backend ajbx-public-bs --project=$PROJECT --region=$REGION --network-endpoint-group=ajbx-public-neg --network-endpoint-group-region=$REGION` | v2 关联 | 把 PSC NEG 挂到 BS 作为唯一 backend, 详情 §3.12 |
| 16 | **Attach Cloud Armor** (关联操作) | `ajbx-public-bs` → `ajbx-public-armor` | `gcloud compute backend-services update ajbx-public-bs --project=$PROJECT --region=$REGION --security-policy=ajbx-public-armor` | v2 关联 | 把现成 Cloud Armor 重新挂到新 BS (rate limit 200/min), 详情 §3.11 |

> **不动的资源**: 上表 #1–12 全部 v1 已建 (含 v1 之前已有的), v2 不重建; **#15 + #16 是 Backend Service 重建后必须的关联操作** (BS 重建时 Cloud Armor 引用断, NEG 也需要重新挂)。

### e2e curl 输出**:
```
$ curl --resolve tenant.taobao.caep.uk:443:34.105.229.97 https://tenant.taobao.caep.uk/

HTTP/2 200
content-length: 233

<!DOCTYPE html>
<html>
<head><title>tenant.taobao.caep.uk</title></head>
<body>
<h1>OK</h1>
<p>Hello from PSC NEG end-to-end test (HTTPS)</p>
<p>VM: ajbx-tenant-vpc-backend-8kgn</p>
<p>Time: 2026-06-05 07:39:19 UTC</p>
</body>
</html>
```

### logs
```json
{
  "insertId": "1sdwgjfdxuj9",
  "jsonPayload": {
    "securityPolicyRequestData": {
      "tlsJa4Fingerprint": "t13d4907h2_0d8feac7bc37_7395dae3b2f3",
      "remoteIpInfo": {
        "regionCode": "HK",
        "asn": 32135
      },
      "tlsJa3Fingerprint": "375c6162a492dfbf2795909110ce8424"
    },
    "backendTargetProjectNumber": "projects/487126826743",
    "@type": "type.googleapis.com/google.cloud.loadbalancing.type.LoadBalancerLogEntry",
    "enforcedSecurityPolicy": {
      "configuredAction": "RATE_BASED_BAN",
      "rateLimitAction": {
        "outcome": "RATE_LIMIT_THRESHOLD_CONFORM"
      },
      "outcome": "ACCEPT",
      "priority": 1000,
      "name": "ajbx-public-armor"
    }
  },
  "httpRequest": {
    "requestMethod": "GET",
    "requestUrl": "https://tenant.taobao.caep.uk/",
    "requestSize": "44",
    "status": 200,
    "responseSize": "333",
    "userAgent": "curl/8.7.1",
    "remoteIp": "202.8.105.197:53663",
    "serverIp": "192.168.0.17:443",
    "latency": "0.007911s",
    "protocol": "HTTP/2"
  },
  "resource": {
    "type": "http_external_regional_lb_rule",
    "labels": {
      "target_proxy_name": "ajbx-public-proxy",
      "network_name": "aibang-12345678-ajbx-dev-cinternal-vpc1",
      "url_map_name": "ajbx-public-um",
      "backend_target_name": "ajbx-public-bs",
      "backend_scope_type": "REGION",
      "region": "europe-west2",
      "project_id": "aibang-12345678-ajbx-dev",
      "backend_name": "",
      "backend_target_type": "BACKEND_SERVICE",
      "backend_type": "UNKNOWN",
      "forwarding_rule_name": "ajbx-public-fr",
      "backend_scope": "europe-west2",
      "matched_url_path_rule": "UNMATCHED"
    }
  },
  "timestamp": "2026-06-05T08:30:22.854130Z",
  "severity": "INFO",
  "logName": "projects/aibang-12345678-ajbx-dev/logs/loadbalancing.googleapis.com%2Fexternal_regional_requests",
  "receiveTimestamp": "2026-06-05T08:30:27.649161967Z"
}
```
---

## 1. 为什么从 HTTP backend 升级到全 HTTPS(用户质疑点)

**之前**(`tenant-tls-setup.md` v1):
- External GLB 终止 TLS
- GLB → PSC NEG → ILB (port 80) → MIG (HTTP 80)
- **链路有一跳是 HTTP**(不加密)
- 用户质疑: `protocol=HTTP 不是我想要的, 我想要的全部地方应该都是HTTPS`

**为什么之前是 HTTP**:
- GLB terminate TLS 后,流量用 plain HTTP 走 PSC tunnel
- ILB 也只 listen 80 HTTP
- MIG backend 用 Python http.server(80)+ https.server(443)
- 这是最简方案(避免 cert validation 问题)

**用户的需求**(从 `bs-type.md`):
- producer backend service + MIG 应该是 HTTPS
- 所有 forwarding rules 应该是 HTTPS
- consumer 端 backend service 应该是 HTTPS
- "consume 这边的 gcloud compute backend-services create ajbx-public-bs 是对应的 HTTPS, 这样的话流程是不是就通了"

**方案二**(从 `bs-type.md` 引用):
- External GLB (HTTPS) → PSC NEG → Cross-VPC PSC tunnel → **L7 HTTPS ILB (在此终结第二次 TLS)** → MIG (HTTP 80)
- ILB 二次终结 TLS,链路每一跳都是 TLS (除了最后 ILB→MIG 内部 hop)
- 与方案一(L4 TCP ILB TLS 直通)的区别: 方案二 ILB 自己持有 cert,可以做 L7 路由,更灵活

---

## 2. 改动全貌

### 2.1 Producer VPC 改动

| 资源 | 之前 | 现在 | 改动 |
| --- | --- | --- | --- |
| Health Check | `ajbx-tenant-vpc-internal-hc` (HTTP :80 /healthz) | **`ajbx-tenant-vpc-internal-https-hc`** (HTTPS :443 /healthz) | 删除旧的,建新的 |
| Backend Service | `ajbx-tenant-vpc-internal-bs` (HC=旧 HTTP HC) | `ajbx-tenant-vpc-internal-bs` (HC=新 HTTPS HC) | `update --health-checks=新` |
| URL Map | `ajbx-tenant-vpc-internal-um` | `ajbx-tenant-vpc-internal-um` | 不变 |
| **Target Proxy** | `ajbx-tenant-vpc-internal-proxy` (**Target HTTP Proxy**) | **`ajbx-tenant-vpc-internal-https-proxy` (Target HTTPS Proxy)** | 删旧,建新 |
| **SSL Certificate** | (无) | **`ajbx-tenant-vpc-internal-cert`** (TrustAsia DV, regional, europe-west2) | 新建 |
| **Forwarding Rule** | `ajbx-tenant-vpc-internal-fr` (port 80, target=HTTP proxy) | **`ajbx-tenant-vpc-internal-fr` (port 443, target=HTTPS proxy)** | 删旧,建新(用 import YAML,因为 gcloud CLI 在 `INTERNAL MANAGED` 解析上有 bug) |
| Service Attachment | `ajbx-tenant-vpc-internal-sa` | `ajbx-tenant-vpc-internal-sa` | 删旧(因为引用旧 FR),建新(引用新 FR) |

关于ajbx-tenant-vpc-internal-bs 
这个其实是Producer的ILB的backend service 对我这次的POC来说，我可以完全不关注这个。我想学习一下，为什么会有这个
| 资源 | 之前 | 现在 | 改动 |
| --- | --- | --- | --- |
| Backend Service | `ajbx-tenant-vpc-internal-bs` (HC=旧 HTTP HC) | `ajbx-tenant-vpc-internal-bs` (HC=新 HTTPS HC) | `update --health-checks=新` |




| 维度                 | Backend Service 的 traffic             | Backend Service 的 health check                              |
|----------------------|----------------------------------------|--------------------------------------------------------------|
| 用途                 | 把真实用户流量转发给 backend           | 探测 backend 是否还活着                                      |
| 在哪配置             | protocol + portName (BS 创建时)        | --health-checks=... (BS 创建/更新时)                         |
| 你的配置             | protocol=HTTP + portName=http          | health-checks=ajbx-tenant-vpc-internal-https-hc (HTTPS :443) |
| 在 get-health 输出里 | 看到 port: 80                          | 看不到 — HC 协议是另一个独立查询                             |
| 跟 TLS 终结的关系    | 在 ILB 终结 TLS 之后，明文发给 backend | 跟 TLS 终结无关，是独立探活机制                              |

比如说我看到其绑定的HC也就是health-check是HTTPS了 有这样一个对应的切换。
把这一段拆开讲。关键点是：Backend Service 这个资源里有两件互不相干的事，你看到的 port: 80 是其中一件，health check 是另一件。


    get-health 输出的 port: 80 是什么:

    它告诉你的是 "这台 MIG instance 上, 名为 http 的 named port 解析到 port 80" — 也就是 BS 把真实流量转发到这台 instance 时, 打的端口是 80。

    它完全没告诉你 health check 用什么协议、什么端口。Health check 的配置是挂在 BS 上的另一个资源 (ajbx-tenant-vpc-internal-https-hc), 你要看 HC 的 port/协议要单独去 describe:

    gcloud compute health-checks describe ajbx-tenant-vpc-internal-https-hc \
        --project=$PROJECT --region=$REGION
    → httpsPort: 443, httpsHealthCheck: { port: 443, requestPath: /healthz, ... }


    链路视角 — 为什么 port 80 不影响 "全 HTTPS" 强制要求:


    Client ──TLS 1──> GLB (TrustAsia)
                  ──TLS 2──> BS ajbx-public-bs (HTTPS)
                            ──PSC tunnel──> Service Attachment
                                           ──TLS 3──> ILB ajbx-tenant-vpc-internal-fr (HTTPS proxy 终结)
                                                      │
                                                      │  ← 在这里 TLS 终结, BS 跟 MIG 之间用明文 HTTP 80
                                                      ↓
                                                  MIG (Python http.server :80, https.server :443)
                                                      ↑
                                                      │  ← 但 health check 走的是 HTTPS :443 (MIG 上另开的 TLS server)
                                                      │
                                                  ILB 的 HC probe (HTTPS)


    也就是说:
    - 对外的 3 跳 (Client→GLB, GLB→BS, BS→ILB) 全部 TLS — 这就是你说的"强制 HTTPS"
    - 最后一跳 (ILB→MIG, 10.0.1.4→10.0.1.2/3) 是 ILB 终结 TLS 之后用明文 HTTP 80 跟 MIG 通信 — 这是同 VPC 内部 hop, GCP 私有网络, 不暴露公网
    - Health check 是 ILB 另外起的 HTTPS :443 探活, 跟 traffic port 80 完全独立

    为什么 v2 doc §7 解释了这个选择 ILB→MIG 用 HTTP:

    1. MIG 的 cert (tenant.taobao.caep.uk) 是单域名, 给 ILB 用 backend IP (10.0.1.x) 连时 SNI 不匹配
    2. 让 ILB bypass cert validation 还需要额外配置, 复杂
    3. 内部 hop 在 GCP 私有网络, 已经有 VPC firewall + 私有 IP 隔离, 实际安全等级够
    4. MIG 仍然双 serve (80 HTTP + 443 HTTPS) — HC 用 443, traffic 用 80, 各取所需

    一句话回答你的问题: port: 80 在 get-health 输出里仅描述 traffic port, 跟 health check 是不是 HTTPS :443 没关系, 跟 "全 HTTPS" 强制要求也没关系 — 因为那 3 跳 TLS 已经覆盖了所有跨 VPC / 跨边界的 hop, ILB→MIG 这最后一跳是设计上有意的明文, 不是疏漏。
···

### 2.2 Consumer VPC 改动

| 资源 | 之前 | 现在 | 改动 |
| --- | --- | --- | --- |
| External IP | `ajbx-public-glb-ip` (34.105.229.97, PREMIUM) | 不变 | — |
| SSL Cert | `ajbx-public-cert` (TrustAsia DV) | 不变 | — |
| Target HTTPS Proxy | `ajbx-public-proxy` (cert + url-map) | 不变 | — |
| URL Map | `ajbx-public-um` | 不变 | — |
| **Backend Service** | `ajbx-public-bs` (**protocol=HTTP**, port-name=http) | **`ajbx-public-bs` (protocol=HTTPS, port-name=https)** | 删旧,新建(用 import YAML) |
| Forwarding Rule | `ajbx-public-fr` (port 443, EXTERNAL MANAGED, PREMIUM) | 不变 | — |
| Cloud Armor | `ajbx-public-armor` (regional, rate limit 200/min) | 不变(重新 attach 到新 BS) | — |
| PSC NEG | `ajbx-public-neg` | **delete + recreate**(因为 backend service 重建,需要 reconnect SA) | 删,建 |

### 2.3 不动的资源

- VPC network (`cinternal-vpc1` consumer, `ajbx-tenant-vpc` producer)
- Subnets(`abjx-core`, `abjx-gke-core-01`, `abjx-proxy` in consumer; `abjx-core`, `abjx-proxy`, `abjx-psc-nat` in producer)
- Cloud Router + Cloud NAT
- MIG `ajbx-tenant-vpc-backend-mig` + instance template
- Firewall rules
- Bastion `dev-lon-bastion-public`
- 所有 cert 文件(`cert/tenant.taobao.caep.uk_bundle.crt` + `.key`)

---

## 3. 详细执行步骤(实际命令 + 输出)

### 3.1 上传 ILB 的 SSL cert(Producer VPC, 同一个 TrustAsia cert)

```bash
PROJECT=aibang-12345678-ajbx-dev
REGION=europe-west2
CERT_DIR=/Users/lex/git/gcp/ingress/public-ingress/cert
# 注意:文件名实际有下划线:tenant.taobao.caep.uk_bundle.crt (不是 "ukbundle")
CERT_FILE="$CERT_DIR/tenant.taobao.caep.uk_bundle.crt"
KEY_FILE="$CERT_DIR/tenant.taobao.caep.uk.key"

gcloud compute ssl-certificates create ajbx-tenant-vpc-internal-cert \
    --project=$PROJECT --region=$REGION \
    --certificate=$CERT_FILE \
    --private-key=$KEY_FILE
```

**输出**:
```
Created [https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/sslCertificates/ajbx-tenant-vpc-internal-cert].

NAME                           TYPE          CREATION_TIMESTAMP             EXPIRE_TIME                    REGION        MANAGED_STATUS
ajbx-tenant-vpc-internal-cert  SELF MANAGED  2026-06-05T00:10:54.392-07:00  2026-09-02T16:59:59.000-07:00  europe-west2
```

### 3.2 建 HTTPS Health Check(port 443, /healthz)

```bash
gcloud compute health-checks create https ajbx-tenant-vpc-internal-https-hc \
    --project=$PROJECT --region=$REGION \
    --port=443 --request-path=/healthz \
    --check-interval=10s --timeout=5s \
    --healthy-threshold=2 --unhealthy-threshold=3
```

**输出**:
```
NAME                               PROTOCOL
ajbx-tenant-vpc-internal-https-hc  HTTPS
```

### 3.3 更新 Backend Service 引用新 HC + 删旧 HC

```bash
gcloud compute backend-services update ajbx-tenant-vpc-internal-bs \
    --project=$PROJECT --region=$REGION \
    --health-checks=ajbx-tenant-vpc-internal-https-hc \
    --health-checks-region=$REGION
gcloud compute health-checks delete ajbx-tenant-vpc-internal-hc \
    --project=$PROJECT --region=$REGION --quiet
```

### 3.4 删 SA(因为引用旧 FR,阻止删)

```bash
gcloud compute service-attachments delete ajbx-tenant-vpc-internal-sa \
    --project=$PROJECT --region=$REGION --quiet
```

**输出**:
```
Deleted [https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/serviceAttachments/ajbx-tenant-vpc-internal-sa].
```

### 3.5 删旧 FR(端口 80,target=HTTP proxy) + 删旧 Target HTTP Proxy

```bash
gcloud compute forwarding-rules delete ajbx-tenant-vpc-internal-fr \
    --project=$PROJECT --region=$REGION --quiet
gcloud compute target-http-proxies delete ajbx-tenant-vpc-internal-proxy \
    --project=$PROJECT --region=$REGION --quiet
```

### 3.6 建新 Target HTTPS Proxy

```bash
gcloud compute target-https-proxies create ajbx-tenant-vpc-internal-https-proxy \
    --project=$PROJECT --region=$REGION \
    --url-map=ajbx-tenant-vpc-internal-um \
    --url-map-region=$REGION \
    --ssl-certificates=ajbx-tenant-vpc-internal-cert \
    --ssl-certificates-region=$REGION
```

**输出**:
```
NAME                                  SSL_CERTIFICATES               URL_MAP                      REGION        CERTIFICATE_MAP
ajbx-tenant-vpc-internal-https-proxy  ajbx-tenant-vpc-internal-cert  ajbx-tenant-vpc-internal-um  europe-west2
```

### 3.7 建新 FR(port 443, target=新 HTTPS proxy)

**踩坑**: `gcloud compute forwarding-rules create --load-balancing-scheme="INTERNAL MANAGED"` 报
`argument --load-balancing-scheme: Invalid choice: 'INTERNAL MANAGED'`
即使 help 列了 `INTERNAL MANAGED` 作为 valid choice,也是 `INTERNAL_SELF MANAGED` 也被拒 — **gcloud CLI bug**(在 `terminal` 工具下,multi-word 值的 shell 解析有问题)

**修法**: 用 `gcloud compute forwarding-rules import`(YAML):

```bash
cat > /tmp/fr-spec.yaml <<'EOF'
name: ajbx-tenant-vpc-internal-fr
IPAddress: projects/aibang-12345678-ajbx-dev/regions/europe-west2/addresses/ajbx-tenant-vpc-internal-lb-ip
IPProtocol: TCP
target: 'https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/targetHttpsProxies/ajbx-tenant-vpc-internal-https-proxy'
loadBalancingScheme: INTERNAL MANAGED
portRange: 443-443
network: 'projects/aibang-12345678-ajbx-dev/global/networks/ajbx-tenant-vpc'
subnetwork: 'projects/aibang-12345678-ajbx-dev/regions/europe-west2/subnetworks/ajbx-tenant-vpc-europe-west2-abjx-core'
EOF
gcloud compute forwarding-rules import ajbx-tenant-vpc-internal-fr \
    --project=$PROJECT --region=$REGION \
    --source=/tmp/fr-spec.yaml
```

**输出**:
```
NAME                         IP_ADDRESS  PORT_RANGE  LOAD_BALANCING_SCHEME  TARGET
ajbx-tenant-vpc-internal-fr  10.0.1.4    443-443     INTERNAL MANAGED       ajbx-tenant-vpc-internal-https-proxy
```

> **命名说明**: YAML 里用 `INTERNAL MANAGED`(API 接受这个字面量,display 时保留原样)
> 之前 `gcloud compute forwarding-rules create --load-balancing-scheme=INTERNAL MANAGED` 失败 — 是 gcloud CLI 解析 bug,
> `gcloud compute ... import` 用 REST API 直接,绕开 CLI 解析。

### 3.8 重建 SA(引用新 FR)

```bash
gcloud compute service-attachments create ajbx-tenant-vpc-internal-sa \
    --project=$PROJECT --region=$REGION \
    --producer-forwarding-rule=ajbx-tenant-vpc-internal-fr \
    --connection-preference=ACCEPT_AUTOMATIC \
    --nat-subnets=ajbx-tenant-vpc-europe-west2-abjx-psc-nat
```

**输出**:
```
NAME                         REGION        TARGET_SERVICE               CONNECTION_PREFERENCE
ajbx-tenant-vpc-internal-sa  europe-west2  ajbx-tenant-vpc-internal-fr  ACCEPT_AUTOMATIC
```

### 3.9 等 producer health check 跑 + 验证

```bash
sleep 30
gcloud compute backend-services get-health ajbx-tenant-vpc-internal-bs \
    --project=$PROJECT --region=$REGION
```
> **关于如何在此处将业务流量也升级为 HTTPS，以及为什么此处显示 `port: 80` 的详细原理解析，请参考配套文档 [bs-hc.md](./bs-hc.md)。**

一句话总结：get-health 里的 port: 80 告诉您：“如果现在有用户流量来，ILB 会往实例的 80 端口 转发；同时，该实例的可用性是由在 443 端口 跑的 HTTPS 健康检查保障的。”

**输出**:
```
backend: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/instanceGroups/ajbx-tenant-vpc-backend-mig
status:
  healthStatus:
  - healthState: HEALTHY
    instance: .../instances/ajbx-tenant-vpc-backend-8kgn
    ipAddress: 10.0.1.2
    port: 80  ← 注: backend service 到 backend 是 port 80 (HTTP), health check 是 HTTPS :443
  - healthState: HEALTHY
    instance: .../instances/ajbx-tenant-vpc-backend-17wp
    ipAddress: 10.0.1.3
    port: 80

---
backend: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/instanceGroups/ajbx-tenant-vpc-backend-mig
status:
  healthStatus:
  - healthState: HEALTHY
    instance: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/zones/europe-west2-b/instances/ajbx-tenant-vpc-backend-8kgn
    ipAddress: 10.0.1.2
    port: 80
  - healthState: HEALTHY
    instance: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/zones/europe-west2-c/instances/ajbx-tenant-vpc-backend-17wp
    ipAddress: 10.0.1.3
    port: 80
  kind: compute#backendServiceGroupHealth
```

> **注意**: `port: 80` 是 backend service 看到 backend 的 traffic port(ILB → MIG),不是 health check 的 port。
> health check 是 HTTPS :443(看 `ajbx-tenant-vpc-internal-https-hc` 的 config)。

### 3.10 Consumer 端:删旧 Backend Service(HTTP),建新(HTTPS)

**踩坑**: `gcloud compute backend-services create` 也报同样的 `MANAGED` 解析问题。
**修法**: `gcloud compute backend-services import`(YAML)。

```bash
# 删旧
gcloud compute backend-services remove-backend ajbx-public-bs \
    --project=$PROJECT --region=$REGION \
    --network-endpoint-group=ajbx-public-neg \
    --network-endpoint-group-region=$REGION
gcloud compute backend-services delete ajbx-public-bs \
    --project=$PROJECT --region=$REGION --quiet

# 建新 (用 import YAML)
cat > /tmp/bs-spec.yaml <<'EOF'
name: ajbx-public-bs
loadBalancingScheme: EXTERNAL MANAGED
protocol: HTTPS
portName: https
timeoutSec: 30
backends:
- group: 'https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/networkEndpointGroups/ajbx-public-neg'
logConfig:
  enable: true
  sampleRate: 1.0
description: 'Public GLB → PSC NEG → ILB (HTTPS backend)'
EOF
gcloud compute backend-services import ajbx-public-bs \
    --project=$PROJECT --region=$REGION \
    --source=/tmp/bs-spec.yaml --quiet
```

**输出**:
```
Updating backend service...
................................................................done.
```

**验证**:
```
ajbx-public-bs  HTTPS  https  EXTERNAL MANAGED
  backends: {'balancingMode': 'UTILIZATION', 'group': '.../networkEndpointGroups/ajbx-public-neg'}
  securityPolicy: .../securityPolicies/ajbx-public-armor
```

### 3.11 重新 attach Cloud Armor(因为 BS 重建)

```bash
gcloud compute backend-services update ajbx-public-bs \
    --project=$PROJECT --region=$REGION \
    --security-policy=ajbx-public-armor
```

### 3.12 重建 PSC NEG(delete + create)— 因为 backend service 改 protocol 后,需要重连 SA

```bash
gcloud compute network-endpoint-groups delete ajbx-public-neg \
    --project=$PROJECT --region=$REGION --quiet
gcloud compute network-endpoint-groups create ajbx-public-neg \
    --project=$PROJECT --region=$REGION \
    --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
    --psc-target-service="projects/$PROJECT/regions/$REGION/serviceAttachments/ajbx-tenant-vpc-internal-sa" \
    --subnet=cinternal-vpc1-europe-west2-abjx-core \
    --network=aibang-12345678-ajbx-dev-cinternal-vpc1

# 重新加回 backend service
gcloud compute backend-services add-backend ajbx-public-bs \
    --project=$PROJECT --region=$REGION \
    --network-endpoint-group=ajbx-public-neg \
    --network-endpoint-group-region=$REGION

# attach armor
gcloud compute backend-services update ajbx-public-bs \
    --project=$PROJECT --region=$REGION \
    --security-policy=ajbx-public-armor
```

### 3.13 等 PSC 重连 + SA connected endpoints 1

```bash
sleep 60
gcloud compute service-attachments describe ajbx-tenant-vpc-internal-sa \
    --project=$PROJECT --region=$REGION --format=json | python3 -c "
import json, sys
d = json.load(sys.stdin)
ce = d.get('connectedEndpoints', [])
print(f'  connectedEndpoints: {len(ce)}')
for e in ce:
    print(f'    status={e.get(\"status\")} connId={e.get(\"pscConnectionId\")}')
"
```

**输出**:
```
connectedEndpoints: 1
  status=ACCEPTED connId=158673064562262033
```

---

## 4. e2e 验证(全链路 HTTPS)

```bash
GLB_IP=$(gcloud compute addresses describe ajbx-public-glb-ip \
    --project=$PROJECT --region=$REGION --format="value(address)")
echo "  GLB IP: $GLB_IP"

# HTTPS /
curl --resolve tenant.taobao.caep.uk:443:$GLB_IP https://tenant.taobao.caep.uk/
# → HTTP 200, 233B, 1.38s
#   body: <h1>OK</h1> + Hello from PSC NEG end-to-end test (HTTPS)

# /healthz
curl --resolve tenant.taobao.caep.uk:443:$GLB_IP https://tenant.taobao.caep.uk/healthz
# → HTTP 200

# TLS server cert (从 GLB 视角看)
echo | openssl s_client -connect tenant.taobao.caep.uk:443 \
    -servername tenant.taobao.caep.uk \
    -resolve tenant.taobao.caep.uk:443:$GLB_IP 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
# subject:  CN=tenant.taobao.caep.uk
# issuer:   C=CN, O=TrustAsia Technologies, Inc., CN=TrustAsia DV TLS RSA CA 2025
# notBefore: Jun  5 00:00:00 2026 GMT
# notAfter:  Sep  2 23:59:59 2026 GMT
# SAN:       DNS:tenant.taobao.caep.uk
```

---

## 5. 完整资源全貌(改后状态)

### 5.1 Producer VPC — `ajbx-tenant-vpc`

| 资源 | 名字 | 状态 |
| --- | --- | --- |
| VPC | `ajbx-tenant-vpc` | 不变 |
| Subnet - 普通 | `ajbx-tenant-vpc-europe-west2-abjx-core` (10.0.1.0/24) | 不变 |
| Subnet - Proxy | `ajbx-tenant-vpc-europe-west2-abjx-proxy` (10.0.2.0/24) | 不变 |
| Subnet - PSC NAT | `ajbx-tenant-vpc-europe-west2-abjx-psc-nat` (10.0.3.0/24) | 不变 |
| Cloud Router/NAT | `ajbx-tenant-vpc-router` / `ajbx-tenant-vpc-nat` | 不变 |
| Health Check | `ajbx-tenant-vpc-internal-https-hc` (HTTPS :443 /healthz) | **新** |
| Backend Service | `ajbx-tenant-vpc-internal-bs` (HC=新 HTTPS HC) | HC 改 HTTPS |
| URL Map | `ajbx-tenant-vpc-internal-um` | 不变 |
| **Target HTTPS Proxy** | `ajbx-tenant-vpc-internal-https-proxy` | **新** (旧 HTTP proxy 删) |
| **SSL Certificate** | `ajbx-tenant-vpc-internal-cert` (TrustAsia DV, regional) | **新** |
| Internal IP | `ajbx-tenant-vpc-internal-lb-ip` (10.0.1.4) | 不变 |
| **Forwarding Rule** | `ajbx-tenant-vpc-internal-fr` (port **443**, target=HTTPS proxy) | 端口 80→443, target 改 HTTPS |
| **Service Attachment** | `ajbx-tenant-vpc-internal-sa` | 删旧 + 建新 (引用新 FR) |
| MIG | `ajbx-tenant-vpc-backend-mig` (2 instances) | 不变 |
| Firewall | ajbx-tenant-vpc-allow-{iap-ssh, lb-hc, internal, psc-data} | 不变 |

### 5.2 Consumer VPC — `cinternal-vpc1`

| 资源 | 名字 | 状态 |
| --- | --- | --- |
| 现有 subnets | abjx-core, abjx-gke-core-01, abjx-proxy | 不变 |
| **Backend Service** | `ajbx-public-bs` (protocol=**HTTPS**, port-name=https) | protocol HTTP→HTTPS, port-name http→https |
| URL Map | `ajbx-public-um` | 不变 |
| Target HTTPS Proxy | `ajbx-public-proxy` (cert=TrustAsia) | 不变 |
| Forwarding Rule | `ajbx-public-fr` (port 443, EXTERNAL MANAGED, PREMIUM) | 不变 |
| External IP | `ajbx-public-glb-ip` (34.105.229.97) | 不变 |
| Cloud Armor | `ajbx-public-armor` (regional, rate limit 200/min) | 重新 attach 到新 BS |
| **PSC NEG** | `ajbx-public-neg` | **删 + 重建** (强制 reconnect SA) |

### 5.3 Global 资源

| 资源 | 名字 | 状态 |
| --- | --- | --- |
| SSL Cert (Consumer GLB) | `ajbx-public-cert` (TrustAsia DV, regional) | 不变 |
| SSL Cert (Producer ILB) | `ajbx-tenant-vpc-internal-cert` | **新** |
| External IP | `ajbx-public-glb-ip` = 34.105.229.97 | 不变 |
| Cloud Armor (regional) | `ajbx-public-armor` | 不变 |

---

## 6. 踩过的 4 个新坑(都记到 doc)

### 6.1 实际文件名有下划线 — `tenant.taobao.caep.uk_bundle.crt`

最初命令用 `tenant.taobao.caep.ukbundle.crt` 一直 "No such file or directory"。

**真正文件名** (hex decode 看到): `tenant.taobao.caep.uk_bundle.crt` (在 `uk` 和 `bundle` 之间有下划线 `_`)
- `ls` 显示成 `ukbundle` 但实际 hex 是 `5f 62 75 6e 64 6c 65` = `_bundle`
- 不知道是什么工具在显示时省略了下划线

**修法**: 以后引用 cert 都用 `_bundle`

### 6.2 gcloud CLI `MANAGED` 解析 bug(在 multi-word 值)

`gcloud compute forwarding-rules create --load-balancing-scheme="INTERNAL MANAGED"` 报:
`argument --load-balancing-scheme: Invalid choice: 'INTERNAL MANAGED'`
即使 help 列了 `INTERNAL MANAGED` 作为 valid choice,且用引号包了也不行。

`gcloud compute backend-services create --load-balancing-scheme=EXTERNAL MANAGED` 同样的问题。

**修法**: 用 `gcloud compute forwarding-rules import` 或 `gcloud compute backend-services import`(YAML 文件 + REST API):

```yaml
# /tmp/fr-spec.yaml
name: ajbx-tenant-vpc-internal-fr
loadBalancingScheme: INTERNAL MANAGED
portRange: 443-443
target: 'https://.../targetHttpsProxies/...'
network: '.../networks/ajbx-tenant-vpc'
subnetwork: '.../subnetworks/...'
```

```bash
gcloud compute forwarding-rules import <name> --project=$PROJECT --region=$REGION --source=/tmp/spec.yaml
```

这种 import 用 REST API,绕开 CLI 的本地 argument parser。

### 6.3 `backend-services create --port=443` 不被识别

`gcloud compute backend-services create --protocol=HTTPS --port=443` 报:
`unrecognized arguments: --port=443 (did you mean '--format'?)`

**修法**: 不传 `--port` flag。Backend service 的 port 由 `--port-name=https` 隐含指定(HTTPS 协议默认 443)。

### 6.4 PSC NEG 在 backend service 协议改后需重连

`ajbx-public-bs` 从 `protocol=HTTP` 改成 `protocol=HTTPS` 后,PSC NEG 的 connection state 失效(SA `connectedEndpoints: 0`, PSC NEG `pscConnectionId: None`)。e2e 返 503 "no healthy upstream"。

**修法**:
1. `remove-backend` (从 BS remove NEG)
2. `delete NEG`
3. `create NEG`(同样配置)
4. `add-backend`(回到 BS)
5. 等 30-60s,SA 自动接受新 connection

---

## 7. 关于 ILB → MIG 的内部 hop

**当前**: ILB 终止 TLS,然后用 **HTTP 80** 跟 MIG 通信。

**为什么不用 HTTPS**:
- ILB 到 backend 可以是 HTTPS,但 MIG 的 cert(`tenant.taobao.caep.uk`) 对 ILB 视角可能 SNI 验证失败
  - ILB 用 backend IP(10.0.1.x)连接,SAN `tenant.taobao.caep.uk` 不匹配 IP
  - 可以 bypass cert validation,但需要额外配置
- HTTPS 到 backend 要求 MIG cert 有效,会跟 cert 名/HOST 验证有 mismatch 风险
- 内部 VPC 流量(ILB→MIG)已经是 GCP 私有网络,理论安全

**用户文档 `bs-type.md` 提的"可以也改为 HTTPS"方案** — 这是**可选**,需要额外 cert 配置。我们**没启用**,链路内部 hop 用 HTTP 80(简化)。

**如果未来要全 HTTPS(包括 ILB→MIG)**:
- 选项 A: 给 MIG 上传一个 cert with `subjectAltName: IP:10.0.1.x`
- 选项 B: 给 ILB backend service 配 `--no-mTLS` 或类似 flag 跳 cert validation
- 选项 C: 用一个 self-signed cert,ILB 不验证(backend service 设置)

---

## 8. 验证脚本

```bash
#!/bin/bash
# verify-tenant-tls-https.sh
set -e
PROJECT=aibang-12345678-ajbx-dev
REGION=europe-west2

echo "=== 1. 所有 ajbx-* 资源健康 ==="
echo "  forwarding rules (HTTPS/HTTPS):"
gcloud compute forwarding-rules list --project=$PROJECT \
    --filter="name~ajbx" --format="table(name,IPAddress,portRange,loadBalancingScheme,target.basename())"
echo
echo "  backend services (HTTPS/HTTP):"
gcloud compute backend-services list --project=$PROJECT \
    --filter="name~ajbx" --format="table(name.basename(),protocol,loadBalancingScheme,region.basename())"
echo
echo "  target proxies (HTTPS proxy for both consumer + producer):"
gcloud compute target-https-proxies list --project=$PROJECT \
    --filter="name~ajbx" --format="table(name.basename(),region.basename())"
echo
echo "  SSL certs (2 个,各用于一个 LB):"
gcloud compute ssl-certificates list --project=$PROJECT --format="table(name,type,region.basename(),expireTime)"
echo
echo "  Producer backend service health (ILB → MIG, 健康):"
gcloud compute backend-services get-health ajbx-tenant-vpc-internal-bs \
    --project=$PROJECT --region=$REGION 2>&1 | head -10
echo
echo "  Service Attachment connected endpoints (1 个 PSC NEG,ACCEPTED):"
gcloud compute service-attachments describe ajbx-tenant-vpc-internal-sa \
    --project=$PROJECT --region=$REGION \
    --format="get(connectedEndpoints)" 2>&1
echo
echo "  PSC NEG (有 pscConnectionId):"
gcloud compute network-endpoint-groups describe ajbx-public-neg \
    --project=$PROJECT --region=$REGION \
    --format="get(name,pscTargetService,pscConnectionId,pscDataPlaneStatus.ready)" 2>&1

echo
echo "=== 2. e2e HTTPS 测 ==="
GLB_IP=$(gcloud compute addresses describe ajbx-public-glb-ip \
    --project=$PROJECT --region=$REGION --format="value(address)")
echo "  GLB IP: $GLB_IP"
echo
echo "  HTTPS / :"
curl --resolve tenant.taobao.caep.uk:443:$GLB_IP -o /tmp/e2e.html \
    -w "  → HTTP %{http_code}, %{size_download}B, %{time_total}s\n" --max-time 15 https://tenant.taobao.caep.uk/
echo "  body:"
head -10 /tmp/e2e.html

echo
echo "  /healthz:"
curl --resolve tenant.taobao.caep.uk:443:$GLB_IP -o /dev/null \
    -w "  → HTTP %{http_code}\n" --max-time 10 https://tenant.taobao.caep.uk/healthz

echo
echo "=== 3. TLS 验证 (看 server cert + chain) ==="
echo | openssl s_client -connect tenant.taobao.caep.uk:443 \
    -servername tenant.taobao.caep.uk \
    -resolve tenant.taobao.caep.uk:443:$GLB_IP 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>&1 | head -5

=== 1. 所有 ajbx-* 资源健康 ===
  forwarding rules (HTTPS/HTTPS):
NAME                         IP_ADDRESS     PORT_RANGE  LOAD_BALANCING_SCHEME  TARGET
ajbx-public-fr               34.105.229.97  443-443     EXTERNAL_MANAGED       ajbx-public-proxy
ajbx-tenant-vpc-internal-fr  10.0.1.4       443-443     INTERNAL_MANAGED       ajbx-tenant-vpc-internal-https-proxy

  backend services (HTTPS/HTTP):
NAME                         PROTOCOL  LOAD_BALANCING_SCHEME  REGION
ajbx-public-bs               HTTPS     EXTERNAL_MANAGED       europe-west2
ajbx-tenant-vpc-internal-bs  HTTP      INTERNAL_MANAGED       europe-west2

```bash

gcloud compute forwarding-rules describe ajbx-public-mtls-fr --region europe-west2
IPAddress: 34.13.61.175
IPProtocol: TCP
attachedExtensions: []
creationTimestamp: '2026-06-06T21:13:08.770-07:00'
description: ''
fingerprint: 0IBtKLrS9-k=
id: '2300263377278685499'
kind: compute#forwardingRule
labelFingerprint: 42WmSpB8rSM=
loadBalancingScheme: EXTERNAL_MANAGED
name: ajbx-public-mtls-fr
network: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/global/networks/aibang-12345678-ajbx-dev-cinternal-vpc1
networkTier: PREMIUM
portRange: 443-443
region: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2
selfLink: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/forwardingRules/ajbx-public-mtls-fr
selfLinkWithId: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/forwardingRules/2300263377278685499
target: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/targetHttpsProxies/ajbx-public-mtls-proxy


 gcloud compute backend-services describe ajbx-public-mtls-bs --region europe-west2
affinityCookieTtlSec: 0
backends:
- balancingMode: UTILIZATION
  capacityScaler: 1.0
  group: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/networkEndpointGroups/ajbx-public-mtls-neg
connectionDraining:
  drainingTimeoutSec: 0
creationTimestamp: '2026-06-06T21:00:31.329-07:00'
description: Public mTLS GLB -> PSC NEG -> ILB (HTTPS backend, no HC for PSC NEG)
fingerprint: r1XeTFrLS5c=
id: '2660405129601700400'
kind: compute#backendService
loadBalancingScheme: EXTERNAL_MANAGED
logConfig:
  enable: true
  optionalMode: EXCLUDE_ALL_OPTIONAL
  sampleRate: 1.0
name: ajbx-public-mtls-bs
port: 80
portName: https
protocol: HTTPS
region: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2
selfLink: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/backendServices/ajbx-public-mtls-bs
sessionAffinity: NONE
timeoutSec: 30
usedBy:
- reference: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/urlMaps/ajbx-public-mtls-um
```

  target proxies (HTTPS proxy for both consumer + producer):
NAME                                  REGION
ajbx-public-proxy                     europe-west2
ajbx-tenant-vpc-internal-https-proxy  europe-west2

  SSL certs (2 个,各用于一个 LB):
NAME                           TYPE          REGION        EXPIRE_TIME
ajbx-public-cert               SELF_MANAGED  europe-west2  2026-09-02T16:59:59.000-07:00
ajbx-tenant-vpc-internal-cert  SELF_MANAGED  europe-west2  2026-09-02T16:59:59.000-07:00

  Producer backend service health (ILB → MIG, 健康):
---
backend: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/instanceGroups/ajbx-tenant-vpc-backend-mig
status:
  healthStatus:
  - healthState: HEALTHY
    instance: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/zones/europe-west2-b/instances/ajbx-tenant-vpc-backend-8kgn
    ipAddress: 10.0.1.2
    port: 80
  - healthState: HEALTHY
    instance: https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/zones/europe-west2-c/instances/ajbx-tenant-vpc-backend-17wp

  Service Attachment connected endpoints (1 个 PSC NEG,ACCEPTED):
{'consumerNetwork': 'https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/global/networks/aibang-12345678-ajbx-dev-cinternal-vpc1', 'endpoint': 'https://www.googleapis.com/compute/v1/projects/aibang-12345678-ajbx-dev/regions/europe-west2/networkEndpointGroups/ajbx-public-neg', 'pscConnectionId': '158673064562262033', 'status': 'ACCEPTED'}

  PSC NEG (有 pscConnectionId):
ajbx-public-neg projects/aibang-12345678-ajbx-dev/regions/europe-west2/serviceAttachments/ajbx-tenant-vpc-internal-sa

=== 2. e2e HTTPS 测 ===
  GLB IP: 34.105.229.97

  HTTPS / :
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   233    0   233    0     0    837      0 --:--:-- --:--:-- --:--:--   835
  → HTTP 200, 233B, 0.278331s
  body:
<!DOCTYPE html>
<html><head><title>tenant.taobao.caep.uk</title></head>
<body>
<h1>OK</h1>
<p>Hello from PSC NEG end-to-end test (HTTPS)</p>
<p>VM: ajbx-tenant-vpc-backend-8kgn</p>
<p>Time: 2026-06-05 07:56:03 UTC</p>
</body></html>

  /healthz:
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100     2    0     2    0     0     31      0 --:--:-- --:--:-- --:--:--    31
  → HTTP 200

=== 3. TLS 验证 (看 server cert + chain) ===
Could not read certificate from <stdin>
Unable to load certificate
```

---

## 9. cleanup 脚本(只清改动的资源,保留其余)

```bash
#!/bin/bash
# cleanup-tenant-tls-https.sh — 只清 v2 改动,保留 cert/MIG/VPC
set -e
PROJECT=aibang-12345678-ajbx-dev
REGION=europe-west2

# 1. Consumer 端 (V2)
gcloud compute forwarding-rules delete ajbx-public-fr --project=$PROJECT --region=$REGION --quiet
gcloud compute target-https-proxies delete ajbx-public-proxy --project=$PROJECT --region=$REGION --quiet
gcloud compute url-maps delete ajbx-public-um --project=$PROJECT --region=$REGION --quiet
gcloud compute backend-services delete ajbx-public-bs --project=$PROJECT --region=$REGION --quiet
gcloud compute network-endpoint-groups delete ajbx-public-neg --project=$PROJECT --region=$REGION --quiet
gcloud compute security-policies delete ajbx-public-armor --project=$PROJECT --quiet
gcloud compute ssl-certificates delete ajbx-public-cert --project=$PROJECT --region=$REGION --quiet
gcloud compute addresses delete ajbx-public-glb-ip --project=$PROJECT --region=$REGION --quiet
gcloud compute networks subnets delete cinternal-vpc1-europe-west2-abjx-proxy --project=$PROJECT --region=$REGION --quiet

# 2. Producer 端 (V2)
gcloud compute service-attachments delete ajbx-tenant-vpc-internal-sa --project=$PROJECT --region=$REGION --quiet
gcloud compute forwarding-rules delete ajbx-tenant-vpc-internal-fr --project=$PROJECT --region=$REGION --quiet
gcloud compute target-https-proxies delete ajbx-tenant-vpc-internal-https-proxy --project=$PROJECT --region=$REGION --quiet
gcloud compute url-maps delete ajbx-tenant-vpc-internal-um --project=$PROJECT --region=$REGION --quiet
gcloud compute backend-services delete ajbx-tenant-vpc-internal-bs --project=$PROJECT --region=$REGION --quiet
gcloud compute health-checks delete ajbx-tenant-vpc-internal-https-hc --project=$PROJECT --region=$REGION --quiet
gcloud compute ssl-certificates delete ajbx-tenant-vpc-internal-cert --project=$PROJECT --region=$REGION --quiet
gcloud compute addresses delete ajbx-tenant-vpc-internal-lb-ip --project=$PROJECT --region=$REGION --quiet
```

---

## 10. References

- **V1 (HTTP backend)** — [`tenant-tls-setup.md`](./tenant-tls-setup.md)
- **用户质疑原文** — [`bs-type.md`](./bs-type.md)
- 父 doc — [`public-ingress-external-https-lb.md`](./public-ingress-external-https-lb.md)
- 总览 — [`public-ingress-tenant-project-psc.md`](./public-ingress-tenant-project-psc.md)
- GCP 文档:
  - [Regional External Application Load Balancer with PSC NEG](https://cloud.google.com/load-balancing/docs/https/setting-up-https)
  - [Regional Internal Application Load Balancer overview](https://cloud.google.com/load-balancing/docs/l7-internal)
  - [Target HTTPS proxies](https://cloud.google.com/load-balancing/docs/https/target-proxies)
  - [gcloud compute forwarding-rules import](https://cloud.google.com/sdk/gcloud/reference/compute/forwarding-rules/import)
  - [gcloud compute backend-services import](https://cloud.google.com/sdk/gcloud/reference/compute/backend-services/import)
