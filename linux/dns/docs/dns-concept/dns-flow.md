图一： GKE Pod DNS 查询全路径（三种模式）
- ![1](./gke_pod_dns_three_modes.svg)


图二：Cloud DNS Name Resolution Order（含 GKE cluster-scope）
- ![2](./cloud_dns_resolution_order_gke.svg)


图三：VPC2 Peering → VPC1 Forwarding → 企业 DNS 完整链路
- ![3](./vpc2_peering_vpc1_forwarding_enterprise_dns.svg)


图四：GKE → Cloud DNS → On-prem DNS 完整链路（含 GKE cluster-scope）
- ![4](./ndots_search_path_expansion.svg)