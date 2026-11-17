# GCP Secret Manager 事件通知实现最优缓存策略

## 概述

本文档探讨了如何利用 GCP Secret Manager 事件通知来为 Cloud Scheduler 服务认证实现最优的缓存策略。与依赖基于时间的缓存过期不同，我们可以使用事件驱动的通知仅在机密信息实际发生变化时使缓存的机密失效，从而提高性能和安全性。

## 当前挑战

现有方法包括：
- 每次调度程序调用时从 Secret Manager 获取机密
- 使用基于时间的缓存（例如 5-10 分钟）来减少 API 调用
- 如果在缓存过期前更新了机密，可能会出现过期数据
- 当机密未更改时仍产生不必要的 API 调用

## 解决方案：使用 Secret Manager 通知的事件驱动缓存

### Secret Manager 通知的工作原理

GCP Secret Manager 与 Pub/Sub 集成，为机密和机密版本的更改提供事件通知。配置后，每当操作修改机密时，Secret Manager 会自动将消息发布到指定的 Pub/Sub 主题。

### 触发通知的事件

- `SECRET_CREATE`：创建新机密
- `SECRET_UPDATE`：更新机密
- `SECRET_DELETE`：删除机密
- `SECRET_VERSION_ADD`：添加新机密版本
- `SECRET_VERSION_ENABLE`：启用机密版本
- `SECRET_VERSION_DISABLE`：禁用机密版本
- `SECRET_VERSION_DESTROY`：销毁机密版本
- `SECRET_VERSION_DESTROY_SCHEDULED`：计划销毁
- `SECRET_ROTATE`：触发机密轮换
- `TOPIC_CONFIGURED`：配置主题时的测试消息

### 架构

```
┌─────────────────┐    发布    ┌──────────────────┐    消费    ┌─────────────────┐
│ Secret Manager  │ ────────▶ │ Pub/Sub 主题     │ ────────▶ │ 调度器缓存      │
│ (带主题)        │            │ (通知)           │            │ (内存中)        │
└─────────────────┘            └──────────────────┘            └─────────────────┘
       │                                │                                │
       │ 更新机密                       │                                │ 使缓存失效
       │ ──────────────────────────────┼───────────────────────────────▶│ 当收到通知
       │                                │                                │ 时使缓存条目
```

### 实施策略

1. **设置 Pub/Sub 主题**:
   ```bash
   gcloud pubsub topics create css-secret-notifications-topic
   ```

2. **配置 Secret Manager 服务代理**:
   ```bash
   gcloud beta services identity create \
       --service "secretmanager.googleapis.com" \
       --project "PROJECT_ID"
   ```

3. **授予 Pub/Sub 发布者角色**:
   ```bash
   gcloud projects add-iam-policy-binding PROJECT_ID \
       --member="serviceAccount:service-PROJECT_NUMBER@gcp-sa-secretmanager.iam.gserviceaccount.com" \
       --role="roles/pubsub.publisher"
   ```

4. **配置带通知主题的机密**:
   ```bash
   gcloud secrets create scheduler-team-TEAM_ID-basic-auth --topics css-secret-notifications-topic
   ```

5. **创建通知订阅**:
   ```bash
   gcloud pubsub subscriptions create css-secret-notifications-sub \
     --topic css-secret-notifications-topic
   ```

### 事件驱动的缓存管理

#### 缓存结构
- 以团队 ID 为键的内存缓存
- 每个条目包含：机密值、最后更新时间戳、版本
- 缓存条目永不自动过期（无限 TTL）

#### 缓存失效逻辑
1. **在机密更新事件时**：使特定团队的缓存条目失效
2. **在机密删除事件时**：删除团队的缓存条目并标记为无效
3. **在机密版本事件时**：更新缓存元数据中的版本信息

#### 事件处理
```python
def process_secret_notification(pubsub_message):
    """处理来自 Secret Manager 通知的 Pub/Sub 消息"""
    attributes = pubsub_message.attributes
    event_type = attributes.get('eventType')
    secret_id = attributes.get('secretId')

    # 从机密名称中提取团队 ID (例如 projects/.../secrets/scheduler-team-{teamId}-basic-auth)
    team_id = extract_team_id_from_secret_name(secret_id)

    if event_type in ['SECRET_UPDATE', 'SECRET_VERSION_ADD', 'SECRET_VERSION_ENABLE']:
        # 使此团队的缓存失效
        invalidate_cache_entry(team_id)
    elif event_type == 'SECRET_DELETE':
        # 删除缓存条目并标记为需要刷新
        remove_cache_entry(team_id)
```

### 事件驱动方法的优势

1. **最优性能**:
   - 缓存的机密在实际更改前保持有效
   - 消除对未更改机密的不必要 API 调用
   - 减少未更改机密的延迟（纯内存访问）

2. **改进的安全性**:
   - 机密更改时立即使缓存失效
   - 轮换后缓存中没有过期凭据
   - 对安全事件的实时响应

3. **成本效益**:
   - 显著减少 Secret Manager API 调用
   - 仅在更改后实际需要时获取
   - 降低运营成本

4. **可靠性**:
   - 事件驱动的通知通过 Pub/Sub 可靠地传递
   - Pub/Sub 中的内置重试机制
   - 无需轮询

### 实施注意事项

#### 错误处理
- 优雅地处理 Pub/Sub 订阅失败
- 如果通知失败则回退到基于时间的过期
- 为无法传递的消息实现死信队列

#### 缓存预热
- 在服务启动时用现有机密预填充缓存
- 为新团队实现延迟加载
- 处理通知和首次访问之间的竞争条件

#### 监控
- 跟踪通知处理延迟
- 监控缓存命中/未命中率
- 对通知传递失败发出警报

### 迁移策略

1. **第 1 阶段**：在现有基于时间的缓存旁边实施通知基础设施
2. **第 2 阶段**：逐渐转向事件驱动的失效
3. **第 3 阶段**：完全移除基于时间的过期

### 示例实现

```java
@Component
public class SecretManagerCache {

    private final Map<String, CachedSecret> cache = new ConcurrentHashMap<>();
    private final SecretManagerServiceClient client;

    // 处理来自 Pub/Sub 的通知
    public void handleNotification(PubsubMessage message) {
        Map<String, String> attributes = message.getAttributes();
        String eventType = attributes.get("eventType");
        String secretId = attributes.get("secretId");

        String teamId = extractTeamId(secretId);

        switch (eventType) {
            case "SECRET_UPDATE":
            case "SECRET_VERSION_ADD":
            case "SECRET_VERSION_ENABLE":
                cache.remove(teamId);
                break;
            case "SECRET_DELETE":
                cache.remove(teamId);
                break;
        }
    }

    public String getSecret(String teamId) {
        CachedSecret cached = cache.get(teamId);
        if (cached != null) {
            return cached.getValue();
        }

        // 缓存未命中 - 从 Secret Manager 获取
        String secretValue = fetchFromSecretManager(teamId);
        cache.put(teamId, new CachedSecret(secretValue, Instant.now()));
        return secretValue;
    }
}
```

## 结论

使用 GCP Secret Manager 事件通知为 Cloud Scheduler 服务中的机密缓存提供了最优解决方案。这种方法确保在机密更改时立即使其失效，同时对未更改的机密保持最大缓存效率。与基于时间的缓存策略相比，事件驱动模型提供了更好的性能、安全性和成本效益。

此解决方案直接解决了仅在机密实际更改时（例如由于密码过期或手动更新）而不是在固定时间表上获取机密的要求，使其成为 Cloud Scheduler 服务认证增强的理想选择。

## 参考资料

1. Google Cloud Secret Manager 文档 - 事件通知: https://docs.cloud.google.com/secret-manager/docs/event-notifications
2. Stack Overflow - Google Cloud Secret Manager PubSub 通知: https://stackoverflow.com/questions/71435534/google-cloud-secret-manager-notifications-on-pubsub
3. Hoop.dev 博客 - 让 GCP Secret Manager 与 Google Pub/Sub 协同工作的最简单方法: https://hoop.dev/blog/the-simplest-way-to-make-gcp-secret-manager-google-pub-sub-work-like-it-should/
4. HashiCorp Terraform Provider Google Issue #9548 - Secret Manager Secret 发布到 Cloud Pub/Sub: https://github.com/hashicorp/terraform-provider-google/issues/9548