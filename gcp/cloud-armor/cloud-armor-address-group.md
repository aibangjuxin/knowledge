# 使用地址组实现 GCP Cloud Armor 的可扩展 IP 管理

## 概述

本文档提供了使用 Google Cloud Armor 地址组（Address Groups）功能来管理大量 IP 地址的详细步骤，特别适用于需要为特定路径配置 IP 访问控制且 IP 数量较多的场景。地址组是 Cloud Armor 企业版提供的功能，可以有效解决单条规则中 IP 地址数量限制（最多10个）的问题。

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