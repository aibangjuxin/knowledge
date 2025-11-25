这是一个关于 Kubernetes 网络策略在 **Routes-based 模式**下（例如某些云提供商的 CNI 插件）如何处理流量的深度分析文件。我将基于源文件中的详细信息，验证其内容的准确性，并提炼出最佳实践方案。

---

## 第一部分：内容准确性验证

基于您提供的文档，关于 Kubernetes NetworkPolicy 在 Routes-based 模式下的流量解析，其核心结论和工作原理描述是**完全准确**的 。

### 核心发现与支持证据

|核心结论|准确性|依据与解释|
|:--|:--|:--|
|**NetworkPolicy 看不到 Service IP**|✅ **准确**|NetworkPolicy 是一个 L3/L4 过滤器，它工作在 `iptables` 的 `FORWARD` 链，即 **DNAT 转换之后**。`kube-proxy` 的 DNAT 转换（将 Service IP:443 转换为 Pod IP:8443）发生在更早的 `PREROUTING` 链中。因此，当网络包到达 NetworkPolicy 进行检查时，Service IP 已经被替换成了目标 Pod IP。|
|**Service IP Egress 规则无效**|✅ **准确**|如果配置了允许访问 Service IP Range 的 Egress 规则（例如 `ipBlock: 100.64.0.0/16`），该规则将**完全无效**。原因是 NetworkPolicy 检查的包头中目标 IP 已经是 Pod IP，不会匹配到 Service IP 的范围。|
|**Pod IP 规则是唯一有效的**|✅ **准确**|恰恰相反，**Pod IP 规则是唯一有效且必须的规则**。因为 NetworkPolicy 只能看到经过 DNAT 转换后的 Pod IP（例如 `100.68.2.30:8443`）。如果没有匹配 Pod IP 的规则，流量将被默认拒绝（在存在默认拒绝策略的情况下）。|
|**`namespaceSelector` 的工作方式**|✅ **准确**|规则配置中的 `namespaceSelector` 不直接匹配 IP 地址。它依赖 CNI 插件（NetworkPolicy 执行者）通过 **Kubernetes API** 查询，将网络包中的 Pod IP 映射回其所属的 Pod 对象，进而确定该 Pod 所属的 Namespace，并检查该 Namespace 的 Label 是否匹配规则。|

---

## 第二部分：最佳实践方案

基于源文件对 NetworkPolicy 工作层级的深入理解，以下是配置 Kubernetes 网络策略的最佳实践方案：

### 1. **配置 NetworkPolicy 规则 (Egress & Ingress)**

由于 NetworkPolicy 只能看到 Pod IP，所有的 Egress 和 Ingress 规则都应基于 **Pod 的元数据（Namespace 或 Label）** 进行配置。

|实践方面|最佳实践方案|依据|
|:--|:--|:--|
|**目标选择 (To/From)**|**强烈推荐使用 `namespaceSelector` 或 `podSelector`** 来指定目标 Pod。这是最符合 Kubernetes 声明式特性的方法。|`namespaceSelector` 会自动通过 K8s API 找到目标 Namespace 的所有 Pod IP，并动态适配 Pod IP 地址的变化。|
|**端口选择**|Egress 规则中的 `port` 必须指定为 **目标 Pod 实际监听的端口**（例如 8443），而不是 Service 定义的端口（例如 443）。|DNAT 转换将 Service 端口（443）也转换成了 Pod 端口（8443），NetworkPolicy 检查的是转换后的端口。|
|**Service IP 范围**|**绝对不要配置** Service IP Range 的 `ipBlock` 规则。|配置 Service IP Range 的规则是无效的，因为 NetworkPolicy 根本看不到 Service IP。|
|**Pod IP 范围**|尽量**避免直接配置整个 Pod CIDR 的 `ipBlock`**（如 `100.64.0.0/14`），因为它权限过大且不区分 Namespace。如果确实需要基于 IP 配置，只有使用 **Pod IP CIDR** 的规则才有效。|即使使用 Pod IP 范围，也不如 `namespaceSelector` 灵活和语义化。|
|**DNS 规则**|任何使用了 Egress 策略的 Namespace 都**必须**包含允许访问 `kube-system` Namespace 中 `kube-dns` Pod 的规则（UDP/TCP 53 端口）。|DNS 解析是所有外部和集群内部通信的基础，必须显式允许。|

**示例（推荐配置）：**

Namespace A 访问 Namespace B 的 Egress 规则（Namespace A Egress）和 Namespace B 允许来自 A 的 Ingress 规则（Namespace B Ingress）应该基于 `namespaceSelector` 配置，并且端口使用 Pod 端口 8443。

### 2. **Routes-based 模式下的外部依赖 (GCP 防火墙)**

在 Routes-based 模式下，流量在离开源节点（Node 1）时已经完成了 DNAT 转换，目标地址是 Pod IP 和 Pod 端口。

- **Routes-based 的独特需求：** NetworkPolicy 只在节点内进行 L3/L4 过滤。对于跨节点的通信，您**必须**在 VPC 网络层（如 GCP 防火墙）配置规则，以允许节点之间的 Pod IP 流量能够通过。
- **防火墙规则：** 外部防火墙规则应允许目标 Pod 端口（例如 `tcp:8443`）的流量，并且源范围可以是整个 Pod IP 范围（如 `100.64.0.0/14`）或 Node IP 范围（如 `192.168.64.0/19`）。

### 3. **验证与调试**

理解 NetworkPolicy 工作的时机对于调试至关重要。

|实践方法|目的|依据|
|:--|:--|:--|
|**`tcpdump` 抓包**|在 `PREROUTING` 链之前抓包（Service IP:443）和 `POSTROUTING` 之后抓包（Pod IP:8443），可以**实际验证 DNAT 转换是否发生**。|观察 NetworkPolicy 检查之前，Service IP 是否已被替换。|
|**`iptables` 规则检查**|查看 `iptables -t nat -L KUBE-SERVICES` 链，可以明确看到 `kube-proxy` 创建的 DNAT 规则。|这进一步证实了 Service IP 规则的逻辑已被 DNAT 规则捕获和替换。|

---

### 总结性比喻

理解 NetworkPolicy 的工作机制，就像您在机场安检：

**Service IP (100.64.5.20:443) 就像您在登机牌上看到的航班号 (Destination)**。 **Pod IP (100.68.2.30:8443) 就像您实际需要进入的登机口编号 (Gate)**。

您最初购买机票（发送网络包）时，用的是航班号。但是在您到达安检口（NetworkPolicy 检查）之前，您已经在值机柜台（`kube-proxy DNAT`）被告知并被重定向到实际的登机口。

**NetworkPolicy 只检查您的安检口编号（Pod IP）**。如果您提交给安检员（NetworkPolicy）的规则只允许您通过“某个航班号”的安检口，而安检员只认“登机口编号”，那么您的流量自然会被拒绝。因此，规则必须基于实际的登机口编号（Pod IP/Namespace Selector）来制定。