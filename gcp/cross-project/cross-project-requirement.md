用户硬性前提:

用户入口留在 Talent project (Cloud Armor / 域名 / 证书 / 流量入口)
真实服务运行在 Master project
Talent 必须能挂 Cloud Armor policy 做租户隔离
跨项目、跨 VPC

已验证的两条路径(已知基线):

A. NEG LB-to-LB 级联(cross-project-success-two.md):Tenant L7 ILB → ZONAL NEG (NON_GCP_PRIVATE_IP_PORT) → Master ILB → MIG。可行但 LB-to-LB,边缘多。
B. PSC(public-tls-cross-project-implementation.html):Tenant External HTTPS LB → PSC NEG → Master Service Attachment → Master ILB → MIG。Google 推荐模型。


这里需要强调一个概念：对于我的 Service attachment 来说，必须有一个对应的 PSC subject 来承担它。
- [service-attachment-region.md](../psa-psc/service-attachment-region.md)
- 分配 PSC NAT 子网：在 LB 所在的同一 VPC 和 Region 下，必须创建一个用途标记为 --purpose=PRIVATE_SERVICE_CONNECT 的专用子网