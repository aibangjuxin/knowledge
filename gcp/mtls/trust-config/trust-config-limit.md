直接回答

- 研究表明，Google Trust Config 最多可配置 200 个证书，包括信任锚和中间证书。

背景

Google Trust Config 是 Google Cloud Certificate Manager 的一部分，用于支持多证书信任的场景。它允许在单个信任配置中包含多个证书，以满足互信 TLS 认证的需求。

证书上限

根据最新的 Google Cloud 文档，信任配置中的证书总数（包括信任锚和中间证书）限制为 200 个。这意味着您在一个信任配置中最多可以添加 200 个证书。

- 支持的细节：文档明确指出，信任配置包含一个信任存储，而信任存储可以有多个信任锚和中间证书，总数不超过 200。
- 相关限制：另外，允许列表中的证书最多可达 500 个，但这与信任配置的证书上限是分开的。

有关更多详细信息，请参考 [Google Cloud Certificate Manager 配额和限制](https://cloud.google.com/certificate-manager/docs/quotas)。

  

调查报告

引言

本文旨在探讨 Google Trust Config 在 Google Cloud Certificate Manager 中的证书配置上限，特别是其支持多证书信任的能力。我们将基于最新的官方文档和相关资源，详细分析信任配置中证书的数量限制，并提供全面的背景信息，以帮助用户更好地理解这一功能。

Google Trust Config 的概述

Google Trust Config 是 Google Cloud Certificate Manager 的一部分，专门用于管理公钥基础设施（PKI）配置，特别是在互信 TLS（mTLS）认证场景中。它允许用户定义信任锚（trust anchors）和中间证书（intermediate certificates），以验证客户端或服务器的证书链。

- 多证书支持：文档明确指出，信任配置支持通过多个 pemCertificate 字段实例来添加多个信任锚和中间证书，这表明它设计为处理多个证书。
- 使用场景：这种功能通常用于需要复杂证书链验证的场景，例如企业内部网络或高安全性的 API 通信。

证书上限的详细分析

在研究过程中，我们查阅了 Google Cloud 的官方文档，特别是 [Manage trust configs | Certificate Manager | Google Cloud](https://cloud.google.com/certificate-manager/docs/trust-configs) 和 [Quotas and limits | Certificate Manager | Google Cloud](https://cloud.google.com/certificate-manager/docs/quotas)。以下是关键发现：

- 总证书数量：根据 [Quotas and limits | Certificate Manager | Google Cloud](https://cloud.google.com/certificate-manager/docs/quotas)，信任配置中的证书总数（包括信任锚和中间证书）限制为 200。这是文档中明确规定的配额。
- 信任存储结构：每个信任配置包含一个信任存储（trust store），而信任存储可以封装一个信任锚和多个中间证书。文档中提到，中间证书的数量上限为 100，但总计与信任锚的组合不能超过 200。
- 允许列表的额外限制：除了信任配置的证书，文档还提到允许列表（allowlist）中的证书最多可达 500 个，但这与信任配置的 200 个证书上限是独立的。

以下是相关配额的详细表格：

|   |   |   |
|---|---|---|
|项目|限制|备注|
|信任配置中的证书总数（信任锚 + 中间证书）|200|包括所有证书类型|
|信任存储数量每信任配置|1|每个信任配置只有一个信任存储|
|中间证书数量|100|单独的上限，但总计受 200 的限制|
|允许列表中的证书数量|500|与信任配置证书上限分开|
|名称约束数量|10|适用于证书的名称约束|
|具有相同 Subject 和 Subject Public Key 的中间证书|10|防止重复证书链的限制|
|证书链深度|10|证书链的最大深度|
|中间证书链构建评估次数|100|用于链构建的中间证书评估上限|
|证书的密钥大小|RSA: 2048-4096 位，ECDSA: P-256 或 P-384 曲线|证书生成时的密钥算法要求|

相关背景信息

在搜索过程中，我们还发现了其他与证书管理相关的配额和限制，例如：

- 在 [SSL certificates overview | Load Balancing | Google Cloud](https://cloud.google.com/load-balancing/docs/ssl-certificates)，提到负载均衡器目标代理最多可以引用 100 个 Certificate Manager 证书，但这与信任配置的上下文不同，主要是针对 SSL 证书的管理。
- [Quotas and limits | Certificate Authority Service | Google Cloud](https://cloud.google.com/certificate-authority-service/quotas) 提供了证书颁发服务（CA Service）的配额信息，但主要关注证书颁发请求的速率和吊销证书的数量，与信任配置的证书上限无关。

结论与建议

基于上述分析，Google Trust Config 的证书配置上限为 200 个，包括信任锚和中间证书。这一限制确保了信任配置在处理复杂证书链时的可管理性和性能。用户在配置时应注意总数的限制，并根据需要利用允许列表的额外容量（最多 500 个证书）来扩展功能。

对于需要更多证书的场景，建议查看 [Google Cloud Certificate Manager 文档](https://cloud.google.com/certificate-manager/docs/)，了解是否可以通过多个信任配置来满足需求。此外，定期检查文档更新，因为配额可能会根据 Google Cloud 的政策调整。

关键引用

- [Manage trust configs | Certificate Manager | Google Cloud](https://cloud.google.com/certificate-manager/docs/trust-configs)
- [Quotas and limits | Certificate Manager | Google Cloud](https://cloud.google.com/certificate-manager/docs/quotas)
- [SSL certificates overview | Load Balancing | Google Cloud](https://cloud.google.com/load-balancing/docs/ssl-certificates)
- [Quotas and limits | Certificate Authority Service | Google Cloud](https://cloud.google.com/certificate-authority-service/quotas)