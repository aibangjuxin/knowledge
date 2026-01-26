# 基于 GCP GLB 的 API 级 Cloud Armor 隔离实施方案（可直接落地）

> 目标一句话回顾
> **不改 Nginx / 不改应用，通过 URL Map + 多 Backend Service + 独立 Cloud Armor Policy，实现 API 级安全策略隔离**

---

## 0. 前置假设与前提条件（非常重要）

### 0.1 现有架构假设

```text
Client
  ↓
GCP HTTPS Global Load Balancer
  ↓
URL Map
  ↓
Backend Service（当前只有一个）
  ↓
Nginx MIG
  ↓
后端服务
```

### 0.2 已存在资源（你大概率已经有）

| 资源 | 状态 |
|---|---|
| HTTPS GLB | ✅ |
| Nginx Instance Template | ✅ |
| Nginx MIG | ✅ |
| Health Check | ✅ |
| 默认 Backend Service | ✅ |
| 默认 URL Map | ✅ |

⚠️ 本方案 不删除 现有资源，只是 新增并逐步迁移

---

## 1. 设计拆分策略（先设计，再动手）

### 1.1 API 与策略映射示例

| API Path | Backend Service | Cloud Armor |
|---|---|---|
| /api-a-v1/* | bs-api-a-v1 | policy-api-a-v1 |
| /api-b-v1/* | bs-api-b-v1 | policy-api-b-v1 |
| 其他 | bs-default | policy-default |

---

## 2. 第一步：创建 Cloud Armor Policy（每个 API 一个）

Cloud Armor Policy 是最先创建的对象

### 2.1 创建 policy（示例：API A）

```bash
gcloud compute security-policies create policy-api-a-v1 \
  --description="Cloud Armor policy for api-a v1"
```

### 2.2 添加示例规则（按需调整）

**示例 1：IP Allowlist**

```bash
gcloud compute security-policies rules create 1000 \
  --security-policy=policy-api-a-v1 \
  --expression="inIpRange(origin.ip, '1.2.3.0/24')" \
  --action=allow
```

**示例 2：默认拒绝**

```bash
gcloud compute security-policies rules create 2147483647 \
  --security-policy=policy-api-a-v1 \
  --action=deny-403
```

📌 **建议规则顺序**
- 1000~5000：Allow / Rate Limit
- 最后：默认 deny

---

## 3. 第二步：创建新的 Backend Service（核心步骤）

**关键点：**
👉 多个 Backend Service 可以指向同一个 MIG

### 3.1 创建 Backend Service（API A）

```bash
gcloud compute backend-services create bs-api-a-v1 \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=nginx-health-check \
  --global
```

### 3.2 将 Nginx MIG 绑定到 Backend Service

```bash
gcloud compute backend-services add-backend bs-api-a-v1 \
  --instance-group=nginx-mig \
  --instance-group-zone=asia-northeast1-a \
  --global
```

⚠️ MIG 可以被 多个 Backend Service 同时引用

---

## 4. 第三步：将 Cloud Armor Policy 绑定到 Backend Service

```bash
gcloud compute backend-services update bs-api-a-v1 \
  --security-policy=policy-api-a-v1 \
  --global
```

### 4.1 验证绑定关系

```bash
gcloud compute backend-services describe bs-api-a-v1 --global
```

确认字段：

```
securityPolicy: policy-api-a-v1
```

---

## 5. 第四步：更新 URL Map（Path → Backend Service）

这是唯一会影响流量走向的步骤

### 5.1 查看当前 URL Map

```bash
gcloud compute url-maps describe your-url-map
```

### 5.2 新增 Path Matcher（推荐方式）

```bash
gcloud compute url-maps add-path-matcher your-url-map \
  --path-matcher-name=api-splitter \
  --default-service=bs-default \
  --path-rules="/api-a-v1/*=bs-api-a-v1,/api-b-v1/*=bs-api-b-v1"
```

如果 path-matcher 已存在，使用 edit 方式修改：

```bash
gcloud compute url-maps edit your-url-map
```

---

## 6. 请求执行顺序（再次确认你"真的生效了"）

1. Client 请求 /api-a-v1/xxx
2. GLB URL Map 匹配 path
3. 请求命中 bs-api-a-v1
4. Cloud Armor policy-api-a-v1 执行
5. 请求转发至 Nginx MIG
6. Nginx 正常处理（无感知）

---

## 7. 验证与回滚策略（生产必备）

### 7.1 验证方式

```bash
curl -I https://www.abc.com/api-a-v1/health
```

- 命中 allow → 200
- 命中 deny → 403（来自 Cloud Armor）

### 7.2 Cloud Armor 日志验证

```
Logging → Cloud Armor
resource.type="http_load_balancer"
jsonPayload.enforcedSecurityPolicy.name="policy-api-a-v1"
```

---

### 7.3 回滚方式（极其简单）

URL Map path → 改回原 backend service

- 无需改 Nginx
- 无需改 MIG
- 无需改应用

---

## 8. 推荐实施顺序（生产经验）

1. ✅ 创建 Cloud Armor Policy（不绑定）
2. ✅ 创建 Backend Service + 绑定 MIG
3. ✅ 绑定 Armor Policy
4. ✅ URL Map 新增 path（灰度 API）
5. ✅ 验证
6. ✅ 逐个 API 迁移

---

## 9. 常见误区（请务必避开）

| 误区 | 说明 |
|---|---|
| 一个 Backend Service 绑多个 Policy | ❌ 不支持 |
| Cloud Armor 能看 Host | ❌ 只能靠 URL Map |
| 改 Nginx 才能生效 | ❌ 完全不需要 |
| 先改 URL Map 再做 Policy | ❌ 风险大 |

---

## 10. 一句话总结（实施版）

先创建独立 Cloud Armor Policy → 再创建多个指向同一 MIG 的 Backend Service → 将 Policy 绑定到 Backend Service → 最后通过 URL Map 按 API Path 分流，即可实现 API 级安全策略隔离，且对 Nginx 零侵入。

---

## 11. 下一步我可以继续帮你

- 输出 Terraform / Deployment Manager 模板
- 设计 API / Policy 生命周期（创建 / 下线）
- 帮你评估 哪些 API 必须独立 Policy
- 结合你们的 Kong 架构做安全分层图

你下一步是 准备在测试环境先跑一条 API，还是 直接规划生产迁移顺序？