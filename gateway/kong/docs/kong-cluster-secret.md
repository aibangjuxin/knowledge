## Kong 的角色

Kong 有两种主要角色:

- **控制平面 (Control Plane)**: 包含 Kong Manager 和 Kong Developer 仪表板。这是管理 Kong 配置和访问控制的界面。

- **数据平面 (Data Plane)**: 这是 Kong 的核心。它包括 Kong Server 以及存储配置(如数据库)。数据平面处理所有入局请求,执行配置中的规则,然后将请求转发到上游服务。

## 证书

Kong 使用几种类型的证书:

- **cluster_ca_cert**:  cette是 Kong 集群中的 CA 证书。它用于在 Kong 节点之间建立 SSL 连接。

- **cluster_cert**: 此证书用于在 Kong 代理节点之间建立 SSL 连接。它由上面提到的 CA 证书签名。

- **cluster_cert_key**: 此密钥与上面的 cluster_cert 证书配对使用。

这些证书允许 Kong 节点之间建立相互的 SSL 连接,以在集群内安全地通信。

除此之外,您还可以为 Kong 配置附加的证书,例如用于 HTTPS 侦听器或 mTLS 身份验证的证书。但 cluster_ca_cert、`cluster_cert` 和 cluster_cert_key 是 Kong 集群自身使用的核心证书。