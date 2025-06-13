# Q

About aliyun.cloud armor
GCP Cloud Armor Best Practices

1. Create whitelist access based on API location Path
2. Default Deny All access with rule priority like 2147483647
3. Block specific countries using region_code configuration
4. Configure WAF rules
5. DDOS attack protection rules
6. Rate-based ban configuration (source IP throttling) For example, regarding the first point, our APIs are dynamically added, so we need to focus on priority design

我现在关心这样一个场景.比如 1 的部分也就是 API location Path 如果 priority 高于 Rate-based ban 那么我的规则仅仅命中 API location Path. 因为这个是 Allow.所以不会命中 Rate-based ban ?
另外 Rate-based ban 高于 API location Path 那么仅仅会命中 Rate-Base? 我其实还是要确保正确请求到我的 API location Path.所以如果这么配置只有对于 API location Path 的访问 Trigger 了对应的频率限制,才会在这里 Deny? 我的理解是否正确?
Cloud Armor 规则评估是 短路机制：
建议都是将频率限制放在了 API Path 之后.那么如果 API Path 比如我允许了一些 IP 那么如果这些 IP 有攻击是不是 Cloud Armor 的 Rate-Base 就无法保护了?
我的核心问题这样,比如 Rate-Base 的 priority 我直接设置为 1 那么用户请求到了我的 Cloud Armor,那么如果它没有 Trigger 到频率限制.那么就直接允许了.根本不会有后面基于路径的白名单之类的配置. 我们默认 2147483647 是 Deny ALL

# 任何规则（包括 rate-based ban）一旦匹配成功，评估即终止

核心机制：一旦规则匹配，即停止评估后续规则
无论规则动作是：
• allow 还会继续往下走规则
• deny 但是一般来说 Deny 是真正的终止了
• rate-based ban（即使当前未触发频率限制）
只要匹配表达式成功，Cloud Armor 就不会再向下匹配其他规则。

gcloud compute security-policies rules create 1000 \
 --security-policy=cloud-armor-policy \
 --project=${PROJECT_ID} \
 --description="Allow traffic to /api_name_version1/v1/_" \
 --expression='request.path.matches("/api_name_version1/v1/_") && (inIpRange(origin.ip, "1.2.3.4/24") || inIpRange(origin.ip, "5.6.7.8/24"))'
--action=allow

Error parsing Cloud armor rule matcher expression: expression count of 7 exceed maxinum 0f 5 expressions.

查看 Cloud Armor 规则的文件内容，了解表达式限制和 source-ip-range 的使用情况，以便回答用户关于表达式过多时是否可以使用 source-ip-range 作为替代方案的问题。

## 关于`source-ip-range`的限制

您提到的限制是正确的。Cloud Armor 确实对单条规则中的 IP 地址或 IP 地址范围数量有严格限制：

- 每条规则最多只能包含 10 个 IP 地址或 CIDR 范围
- 这个限制同时适用于基本匹配条件（通过`--src-ip-ranges`标志）和高级规则中的`inIpRange()`函数

## 解决方案

当您需要管理超过 10 个 IP 地址时，有两种主要解决方案：

### 1. 多条规则方法（不推荐用于大量 IP）

可以为同一个路径创建多条具有不同优先级的规则，每条规则包含一部分 IP 地址：

```yaml
# 规则1（优先级100）
- description: "允许特定IP访问路径 - 组1"
  match:
    expr:
      expression: 'request.path.matches("/api_name_version1/v1/*") && (inIpRange(origin.ip, "1.1.1.0/24") || inIpRange(origin.ip, "2.2.2.0/24"))'
  action: allow

# 规则2（优先级101）
- description: "允许特定IP访问路径 - 组2"
  match:
    expr:
      expression: 'request.path.matches("/api_name_version1/v1/*") && (inIpRange(origin.ip, "3.3.3.0/24") || inIpRange(origin.ip, "4.4.4.0/24"))'
  action: allow
```

**缺点**：

- 可扩展性差：IP 数量增长时需要添加更多规则
- 管理复杂：更新 IP 列表时需要修改多条规则
- 规则配额消耗：每个 IP 子集都消耗一条规则配额
- 潜在的优先级冲突风险

### 2. 地址组方法（推荐解决方案）

使用 Cloud Armor 的地址组（Address Groups）功能是管理大量 IP 的最佳实践：

```bash
# 1. 创建地址组
gcloud network-security address-groups create allowed-ips-for-api-path \
  --location=global \
  --type=IPv4 \
  --capacity=1000 \
  --description="允许访问API路径的IP地址列表" \
  --purpose=CLOUD_ARMOR

# 2. 添加IP地址到地址组
gcloud network-security address-groups add-items allowed-ips-for-api-path \
  --location=global \
  --items=192.168.1.0/24,203.0.113.0/24,198.51.100.0/24,... # 可添加多个IP

# 3. 创建使用地址组的规则
gcloud compute security-policies rules create 1000 \
  --security-policy=my-security-policy \
  --description="允许地址组中的IP访问API路径" \
  --action=allow \
  --expression="request.path.startsWith('/api_name_version1/v1') && evaluateAddressGroup('allowed-ips-for-api-path', origin.ip)"
```

**优势**：

- 极高的可扩展性：单个地址组最多可包含 150,000 个 IPv4 地址范围
- 集中管理：在一个地方更新 IP 列表，所有引用该地址组的规则都会自动更新
- 规则清晰度：保持安全策略规则的简洁和易读性
- 规则配额效率：每个路径只需一条规则，无论组内 IP 数量多少

**注意事项**：使用地址组功能需要订阅 Cloud Armor 企业版。

## 结论

对于您的问题，如果表达式太多，使用`source-ip-range`确实是一种方法，但仍然受到 10 个 IP 的限制。当需要管理超过 10 个 IP 地址时，地址组是最佳解决方案，它提供了更好的可扩展性和可管理性。如果您的 IP 数量较少（仅略超过 10 个），可以考虑多规则方法，但随着 IP 数量增长，地址组的优势会越来越明显。

✅ 限制说明

1. 表达式子句数量限制：
   • 每条规则的 逻辑表达式中最多只能包含 5 个子表达式（logical expressions），比如 inIpRange(...)、request.path.matches(...) 都算是一个表达式。
   • 错误信息 expression count of 7 exceed maximum of 5 expressions 就是因为你用了 7 个表达式（1 个 path + 6 个 IP 范围或逻辑子句）。

2. source-ip-ranges 限制：
   • --src-ip-ranges 或 source-ip-ranges 最多只能指定 10 个 CIDR 范围。

⸻

✅ 解决方案建议

你可以根据你的场景选择以下方式简化表达式逻辑：

⸻

✅ 方法 1：将 IP 区段移出 expression，使用 --src-ip-ranges 配合 path filter

gcloud compute security-policies rules create 1000 \
 --security-policy=cloud-armor-policy \
 --project=${PROJECT_ID} \
 --description="Allow traffic to /api_name_version1/v1/_ from known IPs" \
 --src-ip-ranges="1.2.3.4/24,5.6.7.8/24" \
 --expression='request.path.matches("/api_name_version1/v1/_")' \
 --action=allow

✅ 优点：减少 expression 中的 inIpRange()，不会受“表达式最大数量”限制。
⚠️ 注意：--src-ip-ranges 是额外的匹配条件，与 expression 是 AND 关系。

⸻

✅ 方法 2：拆分规则，每条 rule 少于 5 个表达式

如果 IP 太多超过 10 个限制，可以分多条规则来配置：

# 第一个规则

gcloud compute security-policies rules create 1000 \
 --security-policy=cloud-armor-policy \
 --project=${PROJECT_ID} \
 --description="Allow traffic from IP block 1" \
 --expression='request.path.matches("/api_name_version1/v1/\*") && inIpRange(origin.ip, "1.2.3.4/24")' \
 --action=allow

# 第二个规则

gcloud compute security-policies rules create 1001 \
 --security-policy=cloud-armor-policy \
 --project=${PROJECT_ID} \
 --description="Allow traffic from IP block 2" \
 --expression='request.path.matches("/api_name_version1/v1/\*") && inIpRange(origin.ip, "5.6.7.8/24")' \
 --action=allow

⸻

根据您的查询，我理解您希望所有 Cloud Armor 安全策略的动作（例如限制 IP 访问、限制请求速率、启用 WAF 规则）都基于条件 `request.path.matches("/api_name_version1/v1/*")` 来配置，同时对于不匹配此路径的流量，设置一个默认规则允许其通过。以下是针对您的需求，详细的配置步骤和示例。

---

### Cloud Armor 安全策略配置

以下配置将针对路径 `/api_name_version1/v1/*` 应用多种安全措施，并为其他流量设置默认放行规则。

#### 1. 限制 IP 访问（Deny Specific IPs）

- **目的**：阻止来自特定 IP 地址的请求访问 `/api_name_version1/v1/*`。
- **条件**：`request.path.matches("/api_name_version1/v1/*")` 且请求 IP 在指定列表中。
- **动作**：拒绝请求，返回 `403 Forbidden`。
- **配置示例**：
  ```yaml
  - description: Deny specific IPs for /api_name_version1/v1/*
    match:
      expr:
        expression: 'request.path.matches("/api_name_version1/v1/*") && request.ip in ["1.2.3.4", "5.6.7.8"]'
    action: deny(403)
  ```

#### 2. 限制请求速率（Rate Limiting）

- **目的**：限制对 `/api_name_version1/v1/*` 路径的请求速率，防止 DDoS 攻击或滥用。
- **条件**：`request.path.matches("/api_name_version1/v1/*")`。
- **动作**：设置每分钟 100 个请求的阈值，超出时返回 `429 Too Many Requests`。
- **配置示例**：
  ```yaml
  - description: Rate limit for /api_name_version1/v1/*
    match:
      expr:
        expression: 'request.path.matches("/api_name_version1/v1/*")'
    action: throttle
    rateLimitOptions:
      conformAction: allow
      exceedAction: deny(429)
      rateLimitThreshold:
        count: 100
        intervalSec: 60
  ```

#### 3. 启用 WAF 规则（Web Application Firewall）

- **目的**：为 `/api_name_version1/v1/*` 路径启用 WAF 规则，防御 SQL 注入、XSS 等常见 Web 攻击。
- **条件**：`request.path.matches("/api_name_version1/v1/*")` 并触发预配置的 WAF 规则。
- **动作**：拒绝触发 WAF 规则的请求，返回 `403 Forbidden`。
- **配置示例**：
  ```yaml
  - description: WAF for /api_name_version1/v1/*
    match:
      expr:
        expression: 'request.path.matches("/api_name_version1/v1/*") && evaluatePreconfiguredWaf("sqli-v33-stable")'
    action: deny(403)
  ```

#### 4. 默认规则（Default Rule）

- **目的**：对于不匹配 `/api_name_version1/v1/*` 的请求（例如 `/api_name_version2/v1/*` 或其他路径），允许流量通过，不施加任何限制。
- **条件**：所有请求（`true`）。
- **动作**：允许通过。
- **配置示例**：
  ```yaml
  - description: Allow all other traffic
    match:
      expr:
        expression: "true"
    action: allow
  ```

---

### 完整配置示例

以下是将上述规则整合成一个完整的 Cloud Armor 安全策略的 YAML 配置。规则按照优先级从高到低排列（Cloud Armor 按顺序评估规则），默认规则放在最后：

```yaml
apiVersion: compute.googleapis.com/v1
kind: SecurityPolicy
metadata:
  name: example-security-policy
spec:
  rules:
    - description: Deny specific IPs for /api_name_version1/v1/*
      match:
        expr:
          expression: 'request.path.matches("/api_name_version1/v1/*") && request.ip in ["1.2.3.4", "5.6.7.8"]'
      action: deny(403)
    - description: Rate limit for /api_name_version1/v1/*
      match:
        expr:
          expression: 'request.path.matches("/api_name_version1/v1/*")'
      action: throttle
      rateLimitOptions:
        conformAction: allow
        exceedAction: deny(429)
        rateLimitThreshold:
          count: 100
          intervalSec: 60
    - description: WAF for /api_name_version1/v1/*
      match:
        expr:
          expression: 'request.path.matches("/api_name_version1/v1/*") && evaluatePreconfiguredWaf("sqli-v33-stable")'
      action: deny(403)
    - description: Allow all other traffic
      match:
        expr:
          expression: "true"
      action: allow
```

---

### 配置说明

- **规则优先级**：Cloud Armor 会按照规则列表的顺序逐一匹配请求。上述配置中，先检查特定 IP 限制、速率限制和 WAF 规则，最后才应用默认规则。
- **针对性防护**：所有限制措施（IP 限制、速率限制、WAF）都只应用于 `/api_name_version1/v1/*` 路径，其他路径（如 `/api_name_version2/v1/*`）不会受到影响。
- **灵活性**：您可以根据需要调整具体的 IP 列表、速率阈值或 WAF 规则集（例如使用 `"xss-v33-stable"` 来防御 XSS 攻击）。

---

### 验证您的理解

您提到所有动作都基于条件 `request.path.matches("/api_name_version1/v1/*")` 来配置，我的理解是正确的。这种配置确保防护措施仅针对特定 API 路径生效，同时其他流量保持畅通。如果有任何调整或补充需求，请告诉我！
