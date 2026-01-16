# 使用地址组实现 GCP Cloud Armor 的可扩展 IP 管理

## 概述

本文档提供了使用 Google Cloud Armor 地址组（Address Groups）功能来管理大量 IP 地址的详细步骤，特别适用于需要为特定路径配置 IP 访问控制且 IP 数量较多的场景。地址组是 Cloud Armor 企业版提供的功能，可以有效解决单条规则中 IP 地址数量限制（最多 10 个）的问题。

## 前提条件

- Google Cloud 项目已启用 Cloud Armor 企业版
- 已启用网络安全 API (`networksecurity.googleapis.com`)
- 具有适当权限的账号（至少需要 `compute.securityAdmin` 角色）
- 安装并配置了 Google Cloud CLI (`gcloud`)

## 地址组的优势

相比于使用多条独立规则管理 IP 列表，地址组提供以下优势：

- **可扩展性**：单个地址组最多可包含 150,000 个 IPv4 地址范围或 50,000 个 IPv6 地址范围
- **集中管理**：在一个地方更新 IP 列表，所有引用该地址组的规则都会自动更新
- **可复用性**：同一个地址组可以在不同安全策略的多条规则中使用
- **清晰度和可读性**：规则表达式更加简洁明了

## 详细步骤

### 1. 创建地址组

#### 使用 Google Cloud 控制台

1. 打开 [Google Cloud 控制台](https://console.cloud.google.com/)
2. 导航至 **网络安全 > 地址组**
3. 点击 **创建地址组**
4. 填写以下信息：
    - **名称**：为地址组指定一个描述性名称（例如 `allowed-ips-for-admin-path`）
    - **范围**：选择 **全局**（适用于 Cloud Armor 后端安全策略）
    - **类型**：选择 IPv4 或 IPv6
    - **用途**：选择 **CLOUD_ARMOR** 或 **DEFAULT,CLOUD_ARMOR**
    - **容量**：根据需要设置（例如，对于 IPv4，可以设置为 1000）
5. 点击 **创建**

#### 使用 gcloud 命令行

```bash
# 创建地址组
gcloud network-security address-groups create allowed-ips-for-admin-path \
  --location=global \
  --type=IPv4 \
  --capacity=1000 \
  --description="允许访问管理路径的 IP 地址列表" \
  --purpose=CLOUD_ARMOR
```

### 2. 向地址组添加 IP 地址

#### 使用 Google Cloud 控制台

1. 在地址组列表中，点击刚创建的地址组
2. 点击 **编辑**
3. 在 **IP 地址** 部分，点击 **添加项目**
4. 输入 IP 地址或 CIDR 范围（例如 `192.168.1.0/24`）
5. 继续添加所有需要的 IP 地址
6. 点击 **保存**

#### 使用 gcloud 命令行

```bash
# 添加单个 IP 地址
gcloud network-security address-groups add-items allowed-ips-for-admin-path \
  --location=global \
  --items=192.168.1.1/32

# 添加多个 IP 地址或 CIDR 范围
gcloud network-security address-groups add-items allowed-ips-for-admin-path \
  --location=global \
  --items=192.168.1.0/24,203.0.113.0/24,198.51.100.0/24
```

### 3. 在 Cloud Armor 安全策略中使用地址组

#### 创建新的安全策略

```bash
# 创建安全策略
gcloud compute security-policies create my-security-policy \
  --description="使用地址组的安全策略"
```

#### 创建使用地址组的规则

```bash
# 创建允许特定路径访问的规则
gcloud compute security-policies rules create 1000 \
  --security-policy=my-security-policy \
  --description="允许地址组中的 IP 访问管理路径" \
  --action=allow \
  --expression="request.path.startsWith('/admin') && evaluateAddressGroup('allowed-ips-for-admin-path', origin.ip)"

# 创建拒绝其他访问该路径的规则（优先级较低）
gcloud compute security-policies rules create 2000 \
  --security-policy=my-security-policy \
  --description="拒绝其他 IP 访问管理路径" \
  --action=deny(403) \
  --expression="request.path.startsWith('/admin')"
```

### 4. 将安全策略应用到后端服务

```bash
# 将安全策略应用到后端服务
gcloud compute backend-services update my-backend-service \
  --security-policy=my-security-policy \
  --global
```

## 管理地址组

### 查看地址组详情

```bash
# 查看地址组详情
gcloud network-security address-groups describe allowed-ips-for-admin-path \
  --location=global

# 列出地址组中的 IP 地址
gcloud network-security address-groups list-items allowed-ips-for-admin-path \
  --location=global
```

### 更新地址组

```bash
# 从地址组中移除 IP 地址
gcloud network-security address-groups remove-items allowed-ips-for-admin-path \
  --location=global \
  --items=192.168.1.1/32

# 更新地址组容量
gcloud network-security address-groups update allowed-ips-for-admin-path \
  --location=global \
  --capacity=2000
```

### 删除地址组

```bash
# 删除地址组（确保先从所有安全策略中移除引用）
gcloud network-security address-groups delete allowed-ips-for-admin-path \
  --location=global
```

## 处理复杂路径匹配

对于需要更复杂路径匹配的场景，可以使用 Cloud Armor 的高级表达式：

```bash
# 精确路径匹配
gcloud compute security-policies rules create 1000 \
  --security-policy=my-security-policy \
  --expression="request.path == '/exact/path' && evaluateAddressGroup('allowed-ips-for-exact-path', origin.ip)" \
  --action=allow

# 前缀匹配
gcloud compute security-policies rules create 1100 \
  --security-policy=my-security-policy \
  --expression="request.path.startsWith('/api/v1') && evaluateAddressGroup('allowed-ips-for-api-v1', origin.ip)" \
  --action=allow

# 正则表达式匹配
gcloud compute security-policies rules create 1200 \
  --security-policy=my-security-policy \
  --expression="request.path.matches('/users/[0-9]+/profile') && evaluateAddressGroup('allowed-ips-for-user-profiles', origin.ip)" \
  --action=allow
```

## 最佳实践

### 规则优先级管理

- 为规则分配优先级时，预留足够的间隔（例如，间隔 100）以便将来插入新规则
- 将功能相似的规则通过优先级段进行分组（例如，所有与 `/admin` 相关的规则可以位于 1000-1999 范围）

### 地址组命名和组织

- 使用描述性名称，包含用途和路径信息（例如 `allowed-ips-for-admin-path`）
- 为不同的路径或功能创建单独的地址组，即使它们包含相同的 IP 地址
- 在地址组描述中添加详细信息，如创建原因、负责团队等

### 测试和部署

- 在应用新规则前，使用 Cloud Armor 的预览模式进行测试
- 定期审查和更新地址组内容，移除不再需要的 IP 地址
- 记录所有地址组和规则的变更，包括添加/移除 IP 的原因

### 监控和审计

- 设置日志记录和监控，以便跟踪规则匹配情况
- 定期审查安全策略的有效性，确保规则按预期工作

## 故障排除

### 常见问题

1. **规则不匹配**：检查规则优先级、表达式语法和地址组引用
2. **地址组更新未生效**：地址组更新可能需要几分钟才能在全球范围内生效
3. **超出配额限制**：检查项目的地址组配额和容量限制

### 错误消息解析

- **"Invalid value for field 'resource.match.expr.expression'"**：检查表达式语法，确保正确引用地址组
- **"The expression has too many subexpressions (maximum 5)"**：简化表达式或拆分为多个规则
- **"Address group not found"**：确保地址组名称正确且位于全局范围

## 结论

使用 Cloud Armor 地址组是管理大量 IP 地址的最佳实践，特别是在需要为特定路径配置 IP 访问控制的场景。相比于使用多条独立规则，地址组提供了更好的可扩展性、可管理性和可维护性。虽然需要 Cloud Armor 企业版，但对于有复杂安全需求的组织来说，这是一项值得的投资。

## 参考资料

- [Cloud Armor 文档 - 使用地址组](https://cloud.google.com/armor/docs/address-groups)
- [Cloud Armor 配额和限制](https://cloud.google.com/armor/quotas)
- [Cloud Armor 高级规则语言参考](https://cloud.google.com/armor/docs/rules-language-reference)

下面按**可操作、可验证**的方式说明，如何判断 **Cloud Armor 是 Standard 还是 Enterprise**，以及**是否支持 Address Group（地址组）**。

---

## **一、问题分析**

你关心的核心有两点：

1. **当前 GCP 工程中 Cloud Armor 使用的是 Standard 还是 Enterprise**
2. **现有 / 可用的规则是否支持 Address Group（地址组）**

这两点本质都不是“开关式配置”，而是通过 **功能是否可用 + 规则能力** 来反向判断。

---

## **二、如何判断 Cloud Armor 版本（Standard vs Enterprise）**

### **结论先行（重要）**

> **Cloud Armor 没有一个字段直接显示 “Standard / Enterprise”**

> 版本是通过 **是否使用了 Enterprise-only 功能** 来体现的。

---

### **2.1 标准判断逻辑（最推荐）**

| **能力**                            | **Standard** | **Enterprise** |
| ----------------------------------- | ------------ | -------------- |
| 基础 IP allow / deny                | ✅           | ✅             |
| 基础 L7 自定义规则                  | ✅           | ✅             |
| **Address Group（IP 地址组）**      | ❌           | ✅             |
| **Adaptive Protection**             | ❌           | ✅             |
| **Bot Management**                  | ❌           | ✅             |
| **Preconfigured WAF（高级规则集）** | ❌           | ✅             |
| **reCAPTCHA 集成**                  | ❌           | ✅             |

👉 **只要你在用其中任意一个 Enterprise 功能，说明该项目已启用 Enterprise**

---

## **三、如何检查是否支持 Address Group（关键）**

### **3.1 直接检查：是否能创建 Address Group**

```
gcloud compute security-policies address-groups list
```

#### **结果解读**

- ✅ **能正常返回列表 / 为空列表**
    - 说明 **Cloud Armor Enterprise 已启用**
- ❌ 报错类似：

```
ERROR: (gcloud.compute.security-policies.address-groups.list)
This feature requires Cloud Armor Enterprise
```

- -   说明 **当前是 Standard**

---

### **3.2 创建 Address Group（最强确认方式）**

```
gcloud compute security-policies address-groups create test-ip-group \
  --description="test address group" \
  --items=1.1.1.1/32 \
  --region=global
```

- 成功 👉 **Enterprise**
- 被拒 👉 **Standard**

---

## **四、现有 Cloud Armor 规则是否在使用 Address Group**

### **4.1 查看 Security Policy 规则**

```
gcloud compute security-policies rules list \
  --security-policy YOUR_POLICY_NAME
```

重点查看 match 字段：

#### **使用 Address Group 的规则示例**

```
match:
  expr:
    expression: "inIpRange(origin.ip, 'addressGroups/my-ip-group')"
```

- 出现 addressGroups/xxx
    👉 **一定是 Enterprise**

---

## **五、从 Console 页面确认（辅助）**

路径：

```
Cloud Console
→ Network Security
→ Cloud Armor
→ Address Groups
```

- **能看到 Address Groups 菜单**
    - Enterprise
- **看不到该菜单**
    - Standard

---

## **六、推荐的判断流程（最佳实践）**

```
graph TD
    A["开始"] --> B["尝试列出 Address Groups"]
    B -->|"成功"| C["确认 Enterprise"]
    B -->|"失败"| D["Standard"]
    C --> E["检查规则是否引用 Address Group"]
    D --> F["仅支持基础 IP / L7 规则"]
```

---

## **七、注意事项（非常重要）**

1. **不是所有工程默认都有 Enterprise**

    - Enterprise 是 **计费能力级别**，不是 IAM 权限问题

2. **规则能创建 ≠ 已实际使用**

    - 有些项目开了 Enterprise，但规则还停留在 Standard 用法

3. **Address Group 只能用于 L7（HTTP(S) LB）**

    - TCP/UDP LB 不支持 Cloud Armor

---

## **八、一句话总结（给你对外解释用）**

> Cloud Armor 没有显式版本标识，是否为 Enterprise 取决于是否使用了高级功能。

> 只要项目支持 Address Group、Adaptive Protection 或高级 WAF 规则，就可以确认该项目启用了 Cloud Armor Enterprise。

如果你愿意，我可以帮你：

- **直接 review 一份现有 Security Policy**
- **设计从 Standard → Enterprise 的规则演进方案**
- **给用户一套“为什么要用 Address Group”的平台级解释文案**

# 高级规则集

下面我**只围绕 Preconfigured WAF（高级规则集）如何作为判断依据**来讲，给你一套**“看到就能判断是不是 Enterprise”**的标准。

---

## **一、问题分析**

你现在的思路是正确的：

> **如果我已经在 Cloud Armor 里看到了某些规则，哪些可以明确判断为 Preconfigured WAF（Enterprise-only）？**

关键点在于：

**Preconfigured WAF 有非常明确、可识别的“规则家族特征”**，不是泛泛的 L7 表达式。

---

## **二、什么才算 Preconfigured WAF（高级规则集）**

### **核心判定标准（最重要）**

> **凡是 match.expr 中引用了 evaluatePreconfiguredWaf() 或 Google 官方 WAF rule set 的规则，一定是 Enterprise**

---

## **三、最典型的 Preconfigured WAF 规则特征**

### **3.1** 

### **evaluatePreconfiguredWaf()**

### **（100% Enterprise）**

这是最明确、不可误判的特征。

#### **示例（真实常见）**

```
match:
  expr:
    expression: "evaluatePreconfiguredWaf('xss-v33-stable')"
```

```
match:
  expr:
    expression: "evaluatePreconfiguredWaf('sqli-v33-stable')"
```

```
match:
  expr:
    expression: "evaluatePreconfiguredWaf('lfi-v33-stable')"
```

👉 **只要出现 evaluatePreconfiguredWaf()**

- 不可能是 Standard
- 必然是 **Cloud Armor Enterprise**

---

## **四、常见的 Preconfigured WAF 规则集名称（速查表）**

| **攻击类型**    | **规则集示例**             | **是否 Enterprise** |
| --------------- | -------------------------- | ------------------- |
| SQL 注入        | sqli-v33-stable            | ✅                  |
| XSS             | xss-v33-stable             | ✅                  |
| LFI             | lfi-v33-stable             | ✅                  |
| RFI             | rfi-v33-stable             | ✅                  |
| RCE             | rce-v33-stable             | ✅                  |
| Scanner / Probe | scannerv33-stable          | ✅                  |
| PHP 攻击        | php-v33-stable             | ✅                  |
| 协议违规        | protocolattack-v33-stable  | ✅                  |
| 会话固定        | sessionfixation-v33-stable | ✅                  |

> 只要是这种 _-v33-stable / _-v33-canary 形式

> 👉 **100% 是 Preconfigured WAF**

---

## **五、容易混淆但「不是」Preconfigured WAF 的规则**

### **5.1 自定义 L7 表达式（不是 Enterprise）**

```
expression: "request.path.matches('/admin.*')"
```

```
expression: "origin.ip in ['1.1.1.1/32']"
```

```
expression: "request.headers['user-agent'].contains('curl')"
```

❌ 这些 **全部是 Standard 就能做的**

---

### **5.2 rate-based rules（不是 Enterprise 判断依据）**

```
rateLimitOptions:
  rateLimitThreshold:
    count: 100
    intervalSec: 60
```

- Rate limiting ≠ Preconfigured WAF
- Standard 也支持基础 rate limit

---

## **六、如何在现有工程里快速排查（实操）**

### **6.1 一条命令直接 grep**

```
gcloud compute security-policies rules list \
  --security-policy YOUR_POLICY_NAME \
  --format="yaml" | grep evaluatePreconfiguredWaf
```

- 有输出 👉 **Enterprise**
- 无输出 👉 还不能下结论（可能没用高级规则）

---

### **6.2 全量查看并人工确认**

```
gcloud compute security-policies rules list \
  --security-policy YOUR_POLICY_NAME \
  --format="yaml"
```

重点看：

- evaluatePreconfiguredWaf
- \*-v33-stable
- \*-v33-canary

---

## **七、判定流程图（给团队/用户解释用）**

```
graph TD
    A["查看 Cloud Armor 规则"] --> B["是否存在 evaluatePreconfiguredWaf"]
    B -->|"是"| C["Cloud Armor Enterprise"]
    B -->|"否"| D["仅使用 Standard 能力"]
    C --> E["规则集: sqli/xss/lfi 等"]
    D --> F["IP/Path/Header 自定义规则"]
```

---

## **八、给你一个“对外一句话说明”（非常实用）**

> Cloud Armor 的 Preconfigured WAF 是 Enterprise 能力，只要规则中出现 evaluatePreconfiguredWaf() 或 Google 官方的 _-v33-_ WAF 规则集，即可确认该工程已启用 Cloud Armor Enterprise。

---

## **九、如果你下一步要做的事情**

我可以继续帮你：

- **帮你 review 一份现有 Security Policy（逐条标注 Standard / Enterprise）**
- **设计一套从“只用 IP 规则”升级到“Preconfigured WAF + Address Group”的平台标准模板**
- **给用户解释为什么不能在 Standard 里用这些规则（成本 & 能力边界）**

你可以直接贴一条你们现在的规则出来，我帮你判定。
