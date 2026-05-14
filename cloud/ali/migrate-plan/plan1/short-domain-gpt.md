# Q

```Bash
Aliyun里面的迁移建议和规划 

我需要将运行在aliyun里面的A cluster迁移到aliyun  B cluster 里面去

A cluster ==> Flow 

Ingress controller ==>  A team managed Kong DP ==> SVC ==> RT

Ingress controller ==> SVC ==> RT 

A cluster目前是通过不同的域名来提供服务。申请了泛解析比如

*.team1.dev.aliyun.cloud.cn.aibang ==> 10.72.10.88

api01.team1.dev.aliyun.cloud.cn.aibang ==> 10.72.10.88

api02.team1.dev.aliyun.cloud.cn.aibang ==> 10.72.10.88



B Cluster 完成2个目标

第一个就是把A Cluster里面的资源完全复制到B cluster

Ingress controller ==> A team managed Kong DP ==> SVC ==> RT

Ingress controller ==> SVC ==> RT 

因为更换了工程所以域名会变更为

*.team2.dev.aliyun.cloud.cn.aibang ==> 10.72.11.99

api01.team2.dev.aliyun.cloud.cn.aibang ==> 10.72.11.99

api02.team2.dev.aliyun.cloud.cn.aibang ==> 10.72.11.99



我将使用external name的方式把api01.team1.dev.aliyun.cloud.cn.aibang 请求

跳转到api01.team2.dev.aliyun.cloud.cn.aibang 这个新的Cluster 注意这个长域名变化了



第二个目标 

B Cluster要通过一个短域名dev-01.aliyun.cloud.cn.aibang入口然后通过apiname+paths ==> 来提供服务。比如

https://dev-01.aliyun.cloud.cn.aibang/api01/ ==> 后面提供服务的其实就是第一个目标里的api01.team2.dev.aliyun.cloud.cn.aibang 提供的服务

https://dev-01.aliyun.cloud.cn.aibang/api02/ ==》 后面提供服务的其实就是第一个目标里的

api02.team2.dev.aliyun.cloud.cn.aibang 



其实说白了就是新的长期目标是短域名+ path来访问

那么我要在迁移的过程中，满足我的长期目标，有哪些地方需要注意。比如我需要直接迁移的时候就要修改资源的绑定域名信息，或者多侦听一个name ? 帮我详细分析 并给出解决的方案

```

## Thinking

```bash
下面给出**面向迁移与长期演进（短域名+path）**的详细方案与注意事项，包含阶段化步骤、关键配置示例（Kubernetes / Kong / Nginx）、验证与回退要点，以及 mermaid 流程图。所有代码块与流程图均可直接复制到 .md 文件中使用。



重要结论（快速读）：

1. 先做完整清单发现 → 在 B 集群部署等价运行时（Ingress、Kong DP/RT、Secrets、证书） → 在 B 集群同时支持新 host（team2.*）与短域名 path（dev-01 + /apiXX） → 切换流量（先通过旧集群反代/ExternalName 做灰度）→ 最终修改 DNS 并下线旧集群。

2. ExternalName 可用于让旧集群的 Ingress 将流量转发到 B 集群的 FQDN（短期反代/灰度），但请注意 DNS/TLS/Host header 的细节。 

3. Kong 的 path rewrite / host 保持 与 upstream TLS 验证、以及 DP <-> CP 的认证是常见问题点（需要提前处理证书/PreserveHost/strip-path）。 

4. 推荐使用 Velero / kustomize / helm 等做资源导出与按环境替换（包括 secrets 的安全迁移）。 

5. 如果使用 nginx-ingress，请使用 rewrite annotations 做 path -> upstream 的映射并注意 proxy_set_header/Host。
```

# ChatGPT

下面给出**面向迁移与长期演进（短域名+path）**的详细方案与注意事项，包含阶段化步骤、关键配置示例（Kubernetes / Kong / Nginx）、验证与回退要点，以及 mermaid 流程图。所有代码块与流程图均可直接复制到 .md 文件中使用。

重要结论（快速读）：

1. 先做完整清单发现 → 在 B 集群部署等价运行时（Ingress、Kong DP/RT、Secrets、证书） → 在 B 集群同时支持新 host（team2.\*）与短域名 path（dev-01 + /apiXX） → 切换流量（先通过旧集群反代/ExternalName 做灰度）→ 最终修改 DNS 并下线旧集群。
2. ExternalName 可用于让旧集群的 Ingress 将流量转发到 B 集群的 FQDN（短期反代/灰度），但请注意 DNS/TLS/Host header 的细节。
3. Kong 的 path rewrite / host 保持 与 upstream TLS 验证、以及 DP <-> CP 的认证是常见问题点（需要提前处理证书/PreserveHost/strip-path）。
4. 推荐使用 Velero / kustomize / helm 等做资源导出与按环境替换（包括 secrets 的安全迁移）。
5. 如果使用 nginx-ingress，请使用 rewrite annotations 做 path -> upstream 的映射并注意 proxy_set_header/Host。

6) 迁移前清单（必须项）

请把下面表格当作验收清单，一项不漏。

|                                         |                                                                                                          |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| 项目                                    | 说明 / 需要收集的信息                                                                                    |
| Namespaces                              | 列出 A cluster 中所有相关 namespace                                                                      |
| Deployments / DaemonSets / StatefulSets | 镜像、replica、资源限制、环境变量                                                                        |
| Services                                | Type (ClusterIP/NodePort/LoadBalancer/ExternalName)、端口                                                |
| Ingress / KongIngress / GatewayAPI      | host、paths、annotations、TLS 秘钥引用                                                                   |
| Kong 配置                               | Services / Routes / Upstreams / Targets / Plugins / Consumers / Credentials（是否 DB-backed 或 DB-less） |
| Secrets & TLS certs                     | TLS cert、CA、mTLS client cert、kong cluster cert（DP <-> CP）                                           |
| PersistentVolumes                       | PV 类型（NAS / Disk）、数据是否需要迁移/备份                                                             |
| 外部依赖                                | 外部 DB、S3/GCS、第三方 API IP 白名单                                                                    |
| DNS & TTL                               | 旧域名的解析记录、TTL，是否可临时降低 TTL                                                                |
| LB / 云端 ACL                           | 公网/内网负载均衡规则、白名单、健康检查                                                                  |
| 监控/告警                               | Prometheus scrapes、Grafana 面板、SLO/告警策略                                                           |

2. 高层迁移策略（推荐，两阶段 + 回退）

3) 准备阶段（B 完整准备）

- 在 B 集群按 A 的资源清单部署运行时（Ingress controller、Kong DP、RT、应用）。
- 复制 Secrets/TLS（使用安全通道，尽量使用 KMS/加密/SealedSecrets）。
- 为 B 集群生成/申请 \*.team2.dev... 的 TLS wildcard 证书；同时准备 dev-01 的证书。
- 如果 Kong 是 DB-backed 或 Enterprise（hybrid），决定 DP 的注册方式（使用已有 CP 还是新 CP），并准备 DP 的证书/密钥（Kong CP/DP 的认证模式：pinned cert 或 PKI）。DP 与 CP 之间的认证与证书必须在切换前先处理好（否则 DP 无法从 CP 拉取配置）。

3.

4. 镜像/配置迁移（灰度可并行）

- 使用 velero 或 kubectl + kustomize/helm 将资源从 A 导出并按环境替换 host 域名（A->team2、以及 dev-01 的 path mapping）。Velero 对资源迁移/备份恢复友好（注意 PV 的迁移需额外解决）。

6.

7. 短域名（长期目标）并行支持

- 在 B 上配置短域名 dev-01.aliyun.cloud.cn.aibang 的 Ingress，将 /api01、/api02 等 path 映射到 B 集群内对应的服务（并在 Kong 或 ingress 上做 strip-path / host rewrite）。
- 同时让 B 继续监听 api01.team2... 等完整域名（迁移期间同时对外暴露两种方式，便于回退/验证）。

9.

10. 流量切换（灰度）

- 方法 A（建议）：在 A 上保留一个轻量 Ingress（或使用 A 的 Kong），将 api01.team1... 的流量反代到 B（通过 Kubernetes ExternalName Service 指向 api01.team2...，或直接在 Ingress backend 指向外部 IP）。这样旧域名可不改 DNS 即能把用户流量迁到 B，用于灰度/验证。注意 DNS、SNI、TLS、Host header 的一致性。（ExternalName 的行为是把 service 名解析为 DNS 名；适合短期内集中替换解析）。
- 方法 B：若可以修改 DNS：把 api01.team1... 的 CNAME 指向 api01.team2... 或直接把 A 记录改为 B 的 LB。先在 DNS 将 TTL 调低用于可快速回退。

12.

13. 验证：端到端灰度验证（流量、证书、mTLS、Header、流控、插件策略、日志/metrics）。
14. 最终切换：当确定稳定后，将 DNS 永久指向 B（或短域名入口 dev-01），并拆掉 A 上的临时反代。
15. 下线 A：逐步下线 A 的服务、证书与 LB，确认没有流量后再释放资源。

16) 关键注意点（细节解读）

A.

ExternalName

& 旧集群反代（短期灰度）

- ExternalName 只是 Kubernetes 内部的 DNS 重定向：集群内通过 service.namespace.svc.cluster.local 被解析为该 externalName 所指 DNS 名。适合让旧集群的 Ingress 将流量转到外部 FQDN（例如 api01.team2.dev...）。注意 DNS TTL 与 kube-dns 缓存带来的延迟。
- 如果旧 Ingress 是 Nginx / Kong，都能做反代到外部 upstream（Nginx 用 proxy_pass，Kong 用 ExternalName Service 或在 KIC 中配置 upstream），但需要处理 TLS 验证（上游证书）与 Host header。

B. Path-based 短域名（dev-01）映射到宿主服务（常见坑）

- 若将 https://dev-01/.../api01/... 映射到内部服务 api01.team2...：需要决定 upstream 接收的 Host header 与 path。常见做法：

- 在 Ingress/Kong 上 strip path（把 /api01 删掉）再转发给后端；否则后端需要支持 path 前缀。Kong 默认 strip_path=true 常见。
- 如果后端以 Host 做路由（虚拟主机），则需要确保发给后端的 Host 是后端期望的值（可用 Kong 的 preserve_host 或 request-transformer 插件控制 header）。Kong KIC 提供 konghq.com/preserve-host annotation。若需要强制替换 Host，常见方案是给 route/service 挂载 request-transformer 插件来写 Host header。

-

C. Kong DP（Data Plane）迁移注意

- Kong DP 与 Control Plane 的认证常用两种方式：Pinned certificate 或 PKI（CA-signed）。迁移时如要在 B cluster 重建 DP，需要准备好 DP 使用的证书，并在 CP 中信任（或将新的 DP 证书上载到 CP）。如果忽略这一步，DP 将无法接收配置。

D. TLS / mTLS / 客户端证书

- 若 API 有客户端证书校验（mTLS），迁移后域名改变或 SNI/主机名改变时，客户端的证书 CN/SAN/配置 或 服务端的 trust config 可能需要更新；若使用 CA 签发客户端证书，需把 CA 加到新的 truststore / Kong 的 trust config 中（或在 GLB 层修改）。

E. Stateful 数据（PV / DB）

- 数据（PV、StatefulSet）需单独迁移（Velero + restic，或数据库导出/导入）。不要只迁移资源清单而忽略数据。

4. 实战示例（YAML / 命令片段）

下列示例可直接复制到 .md 文件。示例有：A 集群保留反代（ExternalName）方案、B 集群 short-domain path 映射方案、Kong 插件示例。

4.1 在 A 集群保留一个 ExternalName + Ingress（把旧域名反代到 B）

# service-externalname.yaml

apiVersion: v1

kind: Service

metadata:

name: api01-upstream

namespace: proxy

spec:

type: ExternalName

# 指向新集群上的域名（B 集群的 team2 域名）

externalName: api01.team2.dev.aliyun.cloud.cn.aibang

# ingress-oldcluster-api01.yaml  (Kong Ingress example on A cluster)

apiVersion: networking.k8s.io/v1

kind: Ingress

metadata:

name: api01-proxy

namespace: proxy

annotations:

kubernetes.io/ingress.class: kong

# 若需要把 / 保留给后端请设为 "false"，若需要删掉前缀则设成 "true"

konghq.com/strip-path: "false"

# 上游 TLS 校验（如果希望校验 B 的证书）

konghq.com/tls-verify: "true"

# 若需要指定 CA secret，用下面注解（需在同一 namespace 创建 secret）

# konghq.com/ca-certificates-secrets: "my-ca-secret"

spec:

tls:

- hosts:

- api01.team1.dev.aliyun.cloud.cn.aibang

secretName: api01-team1-tls

rules:

- host: api01.team1.dev.aliyun.cloud.cn.aibang

http:

paths:

- path: /

pathType: Prefix

backend:

service:

name: api01-upstream

port:

number: 443

说明：旧集群的 Ingress 会把请求发到 api01.team2...，并且可以配置上游 TLS 验证、Host header 行为等。这样做的好处：DNS 不变、能平滑灰度、便于回滚。

4.2 在 B 集群上用短域名 dev-01 + path 映射到 api01 服务（Kong）

# ingress-bcluster-dev01-api01.yaml

apiVersion: networking.k8s.io/v1

kind: Ingress

metadata:

name: dev01-api01

namespace: team2

annotations:

kubernetes.io/ingress.class: kong

# 将 /api01 前缀在代理到后端时去掉（通常后端期望根路径）

konghq.com/strip-path: "true"

# 如果后端基于 Host 做路由，且你想把 upstream Host 改为 api01.team2...:

# 一般做法是让 Kong 的 Service 指向 upstream host，或使用 request-transformer 插件（见下）

spec:

tls:

- hosts:

- dev-01.aliyun.cloud.cn.aibang

secretName: dev-01-tls

rules:

- host: dev-01.aliyun.cloud.cn.aibang

http:

paths:

- path: /api01

pathType: Prefix

backend:

service:

name: api01-svc

port:

number: 80

4.3 Kong 插件：在路由转发前设置 Host header（若后端依赖 host）

# kong-plugin-set-host.yaml

apiVersion: configuration.konghq.com/v1

kind: KongPlugin

metadata:

name: set-host-api01

namespace: team2

plugin: request-transformer

config:

add:

headers:

- "Host: api01.team2.dev.aliyun.cloud.cn.aibang"

把这个插件 bind 到对应的 Ingress/Service（依照你使用的 KIC 版本把注解 konghq.com/plugins: set-host-api01 加到 Ingress 上）。

4.4 Nginx Ingress 反代到外部（如果你用 nginx）

apiVersion: networking.k8s.io/v1

kind: Ingress

metadata:

name: api01-nginx-proxy

annotations:

kubernetes.io/ingress.class: nginx

nginx.ingress.kubernetes.io/rewrite-target: /$1

spec:

rules:

- host: api01.team1.dev.aliyun.cloud.cn.aibang

http:

paths:

- path: /(.\*)

pathType: Prefix

backend:

service:

name: api01-upstream  # 这个 service 可以是 ExternalName 指向 api01.team2...

port:

number: 443

Nginx 还需要 proxy_ssl_server_name on; & proxy_set_header Host 等配置以确保 SNI/Host 正确（可用 configmap 或注解调整）。

5. 自动化迁移建议（命令/脚本片段）

- 导出 namespace：

kubectl --context=cluster-a -n team1 get all,ingress,svc,configmap,secret -o yaml > team1-export.yaml

- 使用 yq 替换域名（示例把 team1 -> team2）：

yq eval '... (用 yq 替换 host 字段中的 team1 -> team2) ...' team1-export.yaml > team2-ready.yaml

- 应用到 B：

kubectl --context=cluster-b apply -f team2-ready.yaml

- 推荐把上面步骤放进 CI（使用 kustomize overlays 或 helm values 做环境差异化），并在每次 apply 前做 dry-run。

6. 验证 & 回退检查单

- 验证点（每一项通过才继续）

- DNS 解析是否正确（A 比赛 B）
- TLS 握手是否通过（包括上游验证）
- Kong DP 是否与 CP 成功注册（查看 DP 日志，确认 config 拉取）
- Path strip / Host header 是否按期望（curl 并查看后端接收到的 Host 跟 path）
- 监控指标（错误率、latency、5xx）是否稳定

-
- 回退：

- 若灰度失败：把 A 上的反代恢复为直接指回 A 服务（或把 DNS TTL 回滚并恢复 A LB），此过程应可在低 TTL 下完成。
- 对于 DB/状态数据回退需慎重——如果写操作已在 B 集群产生，回退到 A 可能需要数据回滚。

-

7. 常见问题 FAQ（简短）

- 问：我能直接把 A 的 Ingress host 改为 team2 吗？  
   可以，但若客户端或其他依赖仍在使用 team1 域名，会断开；建议用反代/ExternalName 先灰度后改 DNS。
- 问：Kong DP 需要重新颁发证书吗？  
   若 DP 在新集群使用不同节点/证书，必须在 CP 中注册新证书（pinned 或 CA 信任链）。否则 DP 无法正常接收配置。
- 问：短域名 path -> 后端 host，如何保证后端路由正常？  
   两条路：1）在请求到后端前用 strip-path 去掉前缀；2）用 Kong plugin （request-transformer）或 Service 设置把 Host 设为后端期望值。

8. 简要 mermaid 流程图（迁移 + 长期目标）

graph TD;

Client --> OldDNS_api01[api01.team1.dev.aliyun.cloud.cn.aibang];

Client --> ShortDev[dev-01.aliyun.cloud.cn.aibang];

OldDNS_api01 --> OldIngressA[Old Ingress (A cluster)];

OldIngressA --> ExternalNameA[Service ExternalName -> api01.team2...];

ExternalNameA --> B_LB[B Cluster LoadBalancer 10.72.11.99];

ShortDev --> DevIngressB[Ingress dev-01 on B cluster];

DevIngressB --> PathRouting[/api01 -> api01 service/ namespace team2/];

DevIngressB --> B_LB;

B_LB --> RT_B[Runtime services (RT) in B];

B_LB --> KongDP_B[Kong DP on B];

9. 建议的切换节奏（时间线）

10) Day -7 ~ -3：完成清单、证书与 B 基础设施部署（Ingress、Kong DP/RT）。
11) Day -3 ~ -1：用内部流量做灰度（把非重要流量逐步指向 B），监控。
12) Day 0（切换日）：若 DNS 可改则把 TTL 降低到 60s，切换 DNS 或确认旧 Ingress 反代到 B；密切观测。
13) Day +1 ~ +7：观察稳定后把 DNS 永久指向 B，移除 A 的反代并下线 A。

如果你愿意，我可以马上为你生成 （A）把当前 A 集群中 Ingress/Service 的 host 字段批量替换为 team2 的 kustomize overlay 示例、（B）在 A 集群创建 ExternalName+Ingress 的完整 manifest、或 （C）在 B 集群为 dev-01+path 生成可直接 apply 的 Ingress + KongPlugin 示例（任选其一，或我直接都生成）。请直接告诉我你想要哪个清单，我会把完整 YAML 给出（可直接拷贝到 .md）。

好的 👍 我把你要的三份完整示例都写好，保持 Markdown 源码格式，可以直接复制到 .md 文件里保存或应用到 K8S。分别是：

- (A) kustomize overlay 示例（批量替换 A 集群 host → team2 域名）。
- (B) A 集群的 ExternalName + Ingress 示例（旧域名 → 反代到新集群）。
- (C) B 集群的 dev-01 短域名 + path Ingress + KongPlugin 示例。

(A) 使用 kustomize overlay 替换域名（team1 → team2）

目录结构建议：

manifests/

base/

ingress.yaml

svc.yaml

deployment.yaml

overlays/

team2/

kustomization.yaml

overlays/team2/kustomization.yaml

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

resources:

- ../../base

# 替换所有 Ingress 的 host 域名

patches:

- target:

kind: Ingress

patch: |-

- op: replace

path: /spec/rules/0/host

value: api01.team2.dev.aliyun.cloud.cn.aibang

- op: replace

path: /spec/tls/0/hosts/0

value: api01.team2.dev.aliyun.cloud.cn.aibang

使用时：

kubectl apply -k overlays/team2/

(B) A 集群反代到 B 集群（ExternalName + Ingress）

service-externalname.yaml

apiVersion: v1

kind: Service

metadata:

name: api01-upstream

namespace: proxy

spec:

type: ExternalName

externalName: api01.team2.dev.aliyun.cloud.cn.aibang

ingress-api01-proxy.yaml

apiVersion: networking.k8s.io/v1

kind: Ingress

metadata:

name: api01-proxy

namespace: proxy

annotations:

kubernetes.io/ingress.class: kong

konghq.com/strip-path: "false"

konghq.com/tls-verify: "true"

spec:

tls:

- hosts:

- api01.team1.dev.aliyun.cloud.cn.aibang

secretName: api01-team1-tls

rules:

- host: api01.team1.dev.aliyun.cloud.cn.aibang

http:

paths:

- path: /

pathType: Prefix

backend:

service:

name: api01-upstream

port:

number: 443

(C) B 集群短域名 dev-01 + path Ingress + KongPlugin

ingress-dev01-api01.yaml

apiVersion: networking.k8s.io/v1

kind: Ingress

metadata:

name: dev01-api01

namespace: team2

annotations:

kubernetes.io/ingress.class: kong

konghq.com/strip-path: "true"

konghq.com/plugins: set-host-api01

spec:

tls:

- hosts:

- dev-01.aliyun.cloud.cn.aibang

secretName: dev-01-tls

rules:

- host: dev-01.aliyun.cloud.cn.aibang

http:

paths:

- path: /api01

pathType: Prefix

backend:

service:

name: api01-svc

port:

number: 80

kong-plugin-set-host.yaml

apiVersion: configuration.konghq.com/v1

kind: KongPlugin

metadata:

name: set-host-api01

namespace: team2

plugin: request-transformer

config:

add:

headers:

- "Host: api01.team2.dev.aliyun.cloud.cn.aibang"

部署后，访问：

- https://dev-01.aliyun.cloud.cn.aibang/api01/ → 后端服务 api01-svc
- Kong 会在转发时将 Host header 改成 api01.team2.dev.aliyun.cloud.cn.aibang

要不要我帮你把 这三份示例再整合成一份迁移操作手册（按时间线：先部署 B → 部署短域名 → 配置 A 的 ExternalName 灰度 → 切换 DNS），这样你可以直接按步骤走，不用来回比对？

👌 那我帮你整理一个 完整迁移操作手册，分阶段执行（B 集群资源准备 → 短域名入口 → A 集群反代灰度 → 最终 DNS 切换），结合前面三个示例 (A, B, C)。

以下是 Markdown 源码，可以直接保存成 .md 文档使用。

Aliyun 集群迁移操作手册

背景

- A Cluster

- 已运行生产服务。
- 域名模式：\*.team1.dev.aliyun.cloud.cn.aibang → IP: 10.72.10.88
- 使用 Ingress Controller + 部分 Kong DP。

-
- B Cluster

- 新环境。
- 目标 1：完整复制 A 集群服务，域名模式：\*.team2.dev.aliyun.cloud.cn.aibang → IP: 10.72.11.99。
- 目标 2：提供短域名统一入口：https://dev-01.aliyun.cloud.cn.aibang/{apiname}。

-
- 迁移原则

- 业务不中断。
- 保持旧域名可访问（通过 A → B 反代）。
- 逐步切流量，最终只保留短域名。

-

阶段 1：准备 B 集群资源

1. 在 B 集群中部署应用、Service、Ingress，保持和 A 一致。
2. 使用 kustomize overlay 方式替换域名后再应用，避免手工修改。

示例 overlays/team2/kustomization.yaml：

apiVersion: kustomize.config.k8s.io/v1beta1

kind: Kustomization

resources:

- ../../base

patches:

- target:

kind: Ingress

patch: |-

- op: replace

path: /spec/rules/0/host

value: api01.team2.dev.aliyun.cloud.cn.aibang

- op: replace

path: /spec/tls/0/hosts/0

value: api01.team2.dev.aliyun.cloud.cn.aibang

应用：

kubectl apply -k overlays/team2/

验证：

curl -vk https://api01.team2.dev.aliyun.cloud.cn.aibang

阶段 2：部署短域名入口

1. 在 B 集群配置一个新的 Ingress，绑定 dev-01.aliyun.cloud.cn.aibang。
2. 每个 API 用 /api01、/api02 这样的 path 进行路由。
3. 使用 KongPlugin 改写 Host 头部，保证后端服务正常识别。

示例 ingress-dev01-api01.yaml：

apiVersion: networking.k8s.io/v1

kind: Ingress

metadata:

name: dev01-api01

namespace: team2

annotations:

kubernetes.io/ingress.class: kong

konghq.com/strip-path: "true"

konghq.com/plugins: set-host-api01

spec:

tls:

- hosts:

- dev-01.aliyun.cloud.cn.aibang

secretName: dev-01-tls

rules:

- host: dev-01.aliyun.cloud.cn.aibang

http:

paths:

- path: /api01

pathType: Prefix

backend:

service:

name: api01-svc

port:

number: 80

kong-plugin-set-host.yaml：

apiVersion: configuration.konghq.com/v1

kind: KongPlugin

metadata:

name: set-host-api01

namespace: team2

plugin: request-transformer

config:

add:

headers:

- "Host: api01.team2.dev.aliyun.cloud.cn.aibang"

验证：

curl -vk https://dev-01.aliyun.cloud.cn.aibang/api01/

阶段 3：A 集群反代到 B 集群（灰度迁移）

1. 在 A 集群创建 ExternalName Service，将旧域名请求反代到 B 集群新域名。
2. 配置 Ingress 绑定旧域名，但后端指向 ExternalName Service。

service-externalname.yaml：

apiVersion: v1

kind: Service

metadata:

name: api01-upstream

namespace: proxy

spec:

type: ExternalName

externalName: api01.team2.dev.aliyun.cloud.cn.aibang

ingress-api01-proxy.yaml：

apiVersion: networking.k8s.io/v1

kind: Ingress

metadata:

name: api01-proxy

namespace: proxy

annotations:

kubernetes.io/ingress.class: kong

konghq.com/strip-path: "false"

konghq.com/tls-verify: "true"

spec:

tls:

- hosts:

- api01.team1.dev.aliyun.cloud.cn.aibang

secretName: api01-team1-tls

rules:

- host: api01.team1.dev.aliyun.cloud.cn.aibang

http:

paths:

- path: /

pathType: Prefix

backend:

service:

name: api01-upstream

port:

number: 443

验证：

curl -vk https://api01.team1.dev.aliyun.cloud.cn.aibang

应能看到返回来自 B 集群的服务。

阶段 4：DNS 切换与收尾

1. 在 DNS 服务商更新解析：

- 将 \*.team1.dev.aliyun.cloud.cn.aibang → 10.72.11.99（B 集群入口）。
- 保留一段时间的 A 集群 ExternalName 反代，保证灰度。

3.

4. 对外正式推荐访问方式：

- 短域名 https://dev-01.aliyun.cloud.cn.aibang/{apiname}
- 旧域名逐步废弃。

6.

总结

- 短期目标：保证 A → B 平滑迁移，旧域名可继续访问。
- 长期目标：用户只通过短域名 + path 访问，降低维护成本。
- 操作顺序：

1. 先建 B → 验证 team2 域名。
2. 配置短域名入口 → 验证。
3. 在 A 集群加 ExternalName 反代 → 灰度验证。
4. 最终切换 DNS → 逐步下线旧入口。

-

要不要我帮你把这个流程再画一张 Mermaid 流程图（显示 A 集群请求如何逐步迁移到 B 集群 + 短域名）？
