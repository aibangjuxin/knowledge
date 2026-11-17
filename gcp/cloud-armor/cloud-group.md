# 利用 Cloud Armor 地址组管理大规模 IP 地址列表的最佳实践

## 1. 引言

在云环境中，有效管理网络安全策略，特别是针对大量 IP 地址的访问控制，对企业至关重要。用户在使用 Google Cloud Armor 时，可能会遇到因尝试在单一规则内或通过创建大量规则来匹配过多 IP 地址而导致的“规则表达式数量超限”的错误。Cloud Armor 中  `source-ip-range`  字段在基础匹配模式下，每个规则限制为 10 个 IP 地址或 IP 地址范围  。对于需要管理成百上千甚至数万个 IP 地址的企业用户而言，这显然是不够的。

本文旨在为遇到此类限制的 Cloud Armor 企业版用户提供一个全面的解决方案：**地址组 (Address Groups)**。地址组允许用户创建和管理大规模的 IP 地址列表，并将其高效地应用于 Cloud Armor 安全策略中，从而克服上述限制，实现更灵活和可扩展的 IP 地址管理。本报告将详细阐述地址组的工作原理、实施步骤、最佳实践以及相关的企业版功能。

## 2. 理解 Cloud Armor 规则限制

Cloud Armor 安全策略的规则由匹配条件和操作组成  。为了确保系统性能和公平性，Google Cloud 对这些规则的复杂性和数量设定了配额和限制  。

- **基础匹配条件中的 IP 地址限制**：当使用基础匹配条件（通过  `gcloud`  命令行的  `--src-ip-ranges`  标志定义）时，每个规则中可指定的 IP 地址或 IP 地址范围数量上限为 10 个  。这是导致用户在处理大量 IP 时遇到困难的直接原因。
- **高级匹配条件（自定义表达式）的限制**：对于使用自定义表达式（通过  `--expression`  标志定义）的高级匹配条件，也存在限制  ：
  - 每个自定义表达式中子表达式的数量上限为 5 个  。
  - 每个子表达式的字符数上限为 1024 个  。
  - 整个自定义表达式的总字符数上限为 2048 个  。

如果尝试通过构建复杂的表达式（例如，使用多个  `inIpRange()`  函数和逻辑运算符  `||`连接）来容纳大量 IP 地址，很容易超出这些字符数或子表达式数量的限制。同样，如果为每小组 IP 地址（例如每 10 个）创建一个新规则，则可能很快达到项目级别的安全策略规则总数配额  。这些限制共同构成了用户遇到的“规则表达式数量超限”问题的根源。

## 3. Cloud Armor 企业版与地址组

地址组是 Google Cloud Armor 的一项强大功能，专为需要管理大规模 IP 列表的用户设计。**使用地址组的一个关键前提是，用户的项目必须订阅 Cloud Armor 企业版 (Cloud Armor Enterprise, 此前称为 Managed Protection Plus)** 。

Cloud Armor 企业版不仅提供了地址组功能，还包含一系列高级安全特性，例如  ：

- **第三方命名的 IP 地址列表**：允许引用由第三方提供商（如 Fastly, Cloudflare, Imperva）维护的 IP 地址列表  。
- **Google 威胁情报 (Threat Intelligence)**：基于 Google 的威胁情报数据增强防护能力。
- **自适应保护 (Adaptive Protection)**：利用机器学习模型帮助防护第七层 DDoS 攻击。
- **高级网络 DDoS 防护**：为直通式网络负载均衡器、协议转发和虚拟机的公共 IP 地址提供增强的 DDoS 防护。
- **DDoS 账单保护和 DDoS 响应支持** (通常针对年度订阅用户)。

对于希望利用地址组来有效管理大量 IP 地址的企业用户，确保其项目已注册到 Cloud Armor 企业版是首要步骤。

## 4. 利用地址组实施 IP 地址管理

地址组允许用户将多个 IP 地址和 IP 地址范围（CIDR 格式）组合成一个命名的逻辑单元，该单元随后可以在 Cloud Armor 安全策略规则中被引用  。这极大地简化了大规模 IP 列表的管理。

### A. 创建地址组

创建地址组时，必须指定其名称、位置（对于 Cloud Armor，通常是  `global`）、描述、容量 (capacity)、类型 (IPv4 或 IPv6) 以及用途 (purpose) 。

- **容量 (Capacity)**：地址组的容量定义了它可以包含的 IP 地址或范围的最大数量。一旦设定，容量不可更改  。当地址组的
  `purpose`  设置为  `CLOUD_ARMOR`  时，其容量可以远超默认值。例如，IPv4 地址组的最大容量可达 150,000 个条目，IPv6 地址组可达 50,000 个条目  。如果
  `purpose`  未专门设置为  `CLOUD_ARMOR` (例如，设置为  `DEFAULT`  用于 Cloud NGFW 防火墙策略)，则最大容量通常限制为 1,000 个条目  。因此，为 Cloud Armor 创建地址组时，明确指定
  `purpose`  为  `CLOUD_ARMOR`  或  `DEFAULT,CLOUD_ARMOR`  是获取更大容量的关键  。
- **类型 (Type)**：指定地址组是用于 IPv4 地址还是 IPv6 地址。一个地址组不能同时包含两种类型的地址  。
- **用途 (Purpose)**：必须设置为  `CLOUD_ARMOR`  或包含  `CLOUD_ARMOR` (如  `DEFAULT,CLOUD_ARMOR`)，以便与 Cloud Armor 安全策略配合使用并获得相应的容量扩展  。

**使用  `gcloud`  创建地址组的示例命令：**

创建一个名为  `my-blocked-ips-ipv4`  的全球 IPv4 地址组，容量为 50,000，专用于 Cloud Armor：

```
gcloud network-security address-groups create my-blocked-ips-ipv4 \
    --location global \
    --description "List of IPv4 IPs to be blocked by Cloud Armor" \
    --capacity 50000 \
    --type IPv4 \
    --project YOUR_PROJECT_ID \
    --purpose CLOUD_ARMOR
```

在执行此操作前，需要确保已启用 Network Security API (`networksecurity.googleapis.com`) 。

### B. 填充和管理地址组条目

创建地址组后，可以向其中添加或移除 IP 地址及范围。

- **添加条目**：使用  `gcloud network-security address-groups add-items`命令。可以一次添加多个以逗号分隔的 IP 地址或 CIDR 范围  。需要注意的是，单个 API 命令（如
  `add-items`）可更改的地址数量也存在上限，例如 IPv4 最多可一次性添加 50,000 个 IP 地址范围  。
  ```
  gcloud network-security address-groups add-items my-blocked-ips-ipv4 \
      --items "192.0.2.1,198.51.100.0/24,203.0.113.5" \
      --location global \
      --project YOUR_PROJECT_ID
  ```
- **移除条目**：使用  `gcloud network-security address-groups remove-items`  命令  。
  ```
  gcloud network-security address-groups remove-items my-blocked-ips-ipv4 \
      --items "203.0.113.5" \
      --location global \
      --project YOUR_PROJECT_ID
  ```
- **列出条目**：使用  `gcloud network-security address-groups list-items GROUP_NAME --location global --project YOUR_PROJECT_ID`。
- **描述地址组**：查看地址组的当前配置和条目，使用  `gcloud network-security address-groups describe GROUP_NAME --location global --project YOUR_PROJECT_ID`。

### C. 将地址组集成到 Cloud Armor 规则中

地址组通过 Cloud Armor 自定义规则语言 (CEL) 中的  `evaluateAddressGroup()`  函数在安全策略规则的表达式中使用  。

- **核心机制**：`evaluateAddressGroup('ADDRESS_GROUP_NAME_OR_FULL_PATH', origin.ip)`。
  - 第一个参数是地址组的名称（如果地址组与安全策略在同一个项目中）或其完整资源路径 (例如  `projects/PROJECT_ID/locations/global/addressGroups/GROUP_NAME`)。文档示例通常使用短名称  。
  - 第二个参数通常是  `origin.ip`（请求的源 IP 地址）或  `origin.user_ip`（如果需要匹配通过代理传递的原始客户端 IP，详见最佳实践部分）。
- **示例  `gcloud compute security-policies rules create`  命令**： 创建一个优先级为 1000 的规则，在名为  `my-cloud-armor-policy`  的安全策略中，拒绝来自  `my-blocked-ips-ipv4`  地址组中所有 IP 的流量，并返回 403 错误：
  ```
  gcloud compute security-policies rules create 1000 \
      --security-policy my-cloud-armor-policy \
      --expression "evaluateAddressGroup('my-blocked-ips-ipv4', origin.ip)" \
      --action "deny(403)" \
      --description "Block traffic from IPs in the my-blocked-ips-ipv4 address group" \
      --project YOUR_PROJECT_ID
  ```

通过这种方式，一个规则就可以有效地管理和匹配地址组中包含的大量 IP 地址，彻底解决了  `source-ip-range`  的 10 个 IP 限制问题。更重要的是，`evaluateAddressGroup()`  作为 CEL 的一部分，可以与其他 CEL 函数和属性（如  `request.path.matches()`、`request.headers['header-name'].contains()`  等）通过逻辑运算符（`&&`、`||`、`!`）组合使用  。这意味着地址组不仅能用于简单的基于 IP 的允许/拒绝，还能成为更复杂、多层面安全规则的一个组成部分，例如：“如果请求路径匹配

`/admin/.*` **并且**  源 IP 地址在  `trusted-admin-ips`  地址组中，则允许访问”。这种灵活性极大地增强了地址组的实用性。

**表 1：地址组和规则管理的关键  `gcloud`  命令**

| 操作                              | `gcloud`  命令片段                                                                                                                                                     | 关键参数/说明                                                                     |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| 创建地址组                        | `gcloud network-security address-groups create GROUP_NAME...`                                                                                                          | `--location global`, `--capacity`, `--type`, `--purpose CLOUD_ARMOR`, `--project` |
| 向地址组添加 IP                   | `gcloud network-security address-groups add-items GROUP_NAME --items IP1,IP2/CIDR,...`                                                                                 | `--location global`, `--project`                                                  |
| 从地址组移除 IP                   | `gcloud network-security address-groups remove-items GROUP_NAME --items IP1,IP2/CIDR,...`                                                                              | `--location global`, `--project`                                                  |
| 列出地址组中的 IP                 | `gcloud network-security address-groups list-items GROUP_NAME...`                                                                                                      | `--location global`, `--project`                                                  |
| 删除地址组                        | `gcloud network-security address-groups delete GROUP_NAME...`                                                                                                          | `--location global`, `--project`                                                  |
| 创建使用地址组的 Cloud Armor 规则 | `gcloud compute security-policies rules create PRIORITY --security-policy POLICY_NAME --expression "evaluateAddressGroup('GROUP_NAME', origin.ip)" --action ACTION...` | `--description`, `--project`                                                      |

## 5. 企业部署的最佳实践

在企业环境中有效利用地址组，不仅仅是技术实现，更需要将其融入更广泛的安全运营和治理流程中。

- **容量规划**：在创建地址组时，应预估未来的 IP 列表增长，设定充足的容量，因为容量一旦设定便无法更改  。同时，仍需关注项目整体的安全策略和规则配额  。
- **命名约定**：为地址组建立清晰、一致且具有描述性的命名规范（例如，`ag-global-allow-office-ipv4`，`ag-global-deny-known-malicious-ipv6`）。地址组名称长度为 1-63 个字符，仅包含字母数字字符，且不能以数字开头  。
- **生命周期管理与自动化**：
  - 定期审查和更新地址组内的 IP 列表，过时的 IP 可能导致安全漏洞或误报。
  - 对于非常庞大或动态变化的列表（例如，来自威胁情报源的 IP），应考虑使用  `gcloud`  命令行工具编写脚本或利用基础设施即代码 (IaC) 工具（如 Terraform）来自动化地址组的更新。Terraform 支持  `google_compute_security_policy`  资源  ，并且可以通过网络安全提供商管理地址组。
- **安全策略设计**：
  - 使用适当的优先级逻辑地组织规则  。数字越小，优先级越高。
  - 为地址组本身及其引用的 Cloud Armor 规则添加描述，便于理解和维护。
  - 如前所述，利用 CEL 的强大功能，将地址组匹配与其他请求属性（如特定路径、请求头）结合，实现更精细化的访问控制。
- **监控与日志记录**：
  - 确保为相关的 Cloud Armor 安全策略启用了日志记录。
  - 监控日志，以验证使用地址组的规则是否按预期工作，并识别异常流量模式。边缘安全策略的日志可以捕获 IP 过滤等控制措施的证据  。
- **`origin.ip`  与  `origin.user_ip`  的选择**：
  - 这是一个常见的混淆点，尤其是在流量经过上游代理或负载均衡器（如 CDN）的企业环境中。`origin.ip`  始终是直接连接到 Google 网络边缘的 IP 地址，这可能是上游代理的 IP 。
  - 要根据真实的客户端 IP 地址进行匹配，应在  `evaluateAddressGroup()`  函数中使用  `origin.user_ip`，例如  `evaluateAddressGroup('GROUP_NAME', origin.user_ip)`。
  - **至关重要的一点是**：为了使  `origin.user_ip`  能正确反映原始客户端 IP，必须在安全策略中配置  `userIpRequestHeaders`  字段，以指定包含真实客户端 IP 的请求头（例如  `X-Forwarded-For`）。如果未配置该字段，或者指定的请求头不存在、无效，
    `origin.user_ip`  将默认回退到与  `origin.ip`  相同的值。
- **IAM 权限精细化**：
  - 遵循最小权限原则。诸如  `compute.networkAdmin` (授予  `networksecurity.addressGroups.*`  权限) 这样的角色权限范围较广  。如果 IP 列表内容的管理团队与地址组的创建/删除团队分离，可以考虑创建自定义 IAM 角色，仅授予必要的权限，例如
    `networksecurity.addressGroups.get`、`networksecurity.addressGroups.list`  和  `networksecurity.addressGroups.updateItems`（如果存在这样的精细化权限或通过组合权限实现）。

将这些实践融入日常运营，可确保地址组不仅解决眼前的技术难题，更能成为企业云安全架构中一个稳健、可扩展且易于治理的组成部分。

## 6. 替代/补充方案：命名的 IP 地址列表 (简述)

虽然地址组是解决用户管理自定义大规模 IP 列表的核心方案，但 Cloud Armor 企业版还提供了另一项与 IP 列表相关的功能：**命名的 IP 地址列表 (Named IP Address Lists)**。

- **与用户管理的地址组的区别**：
  - 命名的 IP 地址列表是由 Google 或第三方提供商（如 Cloudflare、Fastly、Imperva）预定义和维护的 IP 地址集合  。用户不能修改这些列表的内容。
  - 地址组则是由用户自行创建、填充和管理的列表。
- **使用场景**：
  - 主要用于利用第三方维护的威胁情报源（例如，已知的恶意软件分发网络、扫描器、Tor 出口节点）或 CDN 提供商的 IP 地址列表  。
- **引用方式**：
  - 在 Cloud Armor 规则表达式中使用  `evaluatePreconfiguredExpr('EXPRESSION_SET_NAME')`  函数进行引用  。例如，
    `evaluatePreconfiguredExpr('sourceiplist-cloudflare')`  用于匹配来自 Cloudflare 的 IP 地址。
  - 可以通过  `gcloud compute security-policies list-preconfigured-expression-sets --filter="id:sourceiplist"`查看可用的预配置表达式集  。
- **前提条件**：通常也需要 Cloud Armor 企业版 (Managed Protection Plus) 。

命名的 IP 地址列表和用户自定义的地址组是互补的。企业可以结合使用两者：例如，使用命名的 IP 地址列表来阻止来自已知 Tor 出口节点的流量，同时使用自定义的地址组来允许特定合作伙伴的 IP 地址访问或阻止企业自行识别的恶意 IP。对于已订阅 Cloud Armor 企业版的用户，这两种工具共同提供了更全面的 IP 地址管理能力。

## 7. 结论与战略建议

对于在 Cloud Armor 中因需要匹配大量 IP 地址而遇到“规则表达式数量超限”错误的企业用户，**地址组 (Address Groups)**  是明确且强大的解决方案。它通过将大规模 IP 列表的管理从单个规则表达式中分离出来，实现了前所未有的可扩展性和灵活性。

采用地址组的关键优势包括：

- **大规模可扩展性**：支持远超传统规则限制的 IP 条目数量。
- **集中化管理**：IP 列表作为独立资源进行维护，易于更新和审计。
- **提高运营效率**：简化安全策略配置，减少因 IP 列表变更导致的大量规则修改。
- **降低配置错误风险**：集中管理减少了在多个规则中手动输入 IP 的可能性。
- **可重用性**：同一地址组可以被多个安全策略或规则引用。
- **与高级规则逻辑集成**：通过 CEL 表达式，可将地址组匹配与其他请求属性结合，实现复杂的访问控制逻辑。

**战略建议如下：**

1. **积极采用地址组**：对于所有涉及大量 IP 地址的允许/拒绝列表需求，强烈建议迁移到使用地址组进行管理。
2. **实施最佳实践**：认真规划地址组的容量，建立清晰的命名约定，实施 IP 列表的生命周期管理（包括自动化更新机制），并遵循 IAM 最小权限原则。
3. **探索命名的 IP 地址列表**：如果企业有利用第三方威胁情报或管理 CDN 提供商 IP 的需求，应评估并利用命名的 IP 地址列表作为补充工具。
4. **主动审查现有策略**：对现有的 Cloud Armor 安全策略进行审查，识别可以通过地址组进行整合和简化的机会，以提升整体安全策略的可管理性和效率。

综上所述，引入和有效利用地址组不仅是对当前技术限制的战术性修复，更是对企业云安全态势的战略性增强。它使得企业能够更敏捷、更有效地应对动态的网络环境，并构建更具弹性和可扩展性的网络访问控制体系。
