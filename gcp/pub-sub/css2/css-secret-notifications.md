# GCP Secret Manager Event Notifications for Optimal Caching Strategy

## Overview

This document explores how GCP Secret Manager event notifications can be leveraged to implement an optimal caching strategy for Cloud Scheduler Service authentication. Instead of relying on time-based cache expiration, we can use event-driven notifications to invalidate cached secrets only when they actually change, improving both performance and security.

## Current Challenge

The existing approach involves:
- Fetching secrets from Secret Manager on each scheduler invocation
- Using time-based caching (e.g., 5-10 minutes) to reduce API calls
- Potential stale data if secrets are updated before cache expiration
- Unnecessary API calls when secrets haven't changed

## Solution: Event-Driven Caching with Secret Manager Notifications

### How Secret Manager Notifications Work

GCP Secret Manager integrates with Pub/Sub to provide event notifications for changes to secrets and secret versions. When configured, Secret Manager automatically publishes messages to specified Pub/Sub topics whenever operations modify secrets.

### Events That Trigger Notifications

- `SECRET_CREATE`: New secret created
- `SECRET_UPDATE`: Secret updated
- `SECRET_DELETE`: Secret deleted
- `SECRET_VERSION_ADD`: New secret version added
- `SECRET_VERSION_ENABLE`: Secret version enabled
- `SECRET_VERSION_DISABLE`: Secret version disabled
- `SECRET_VERSION_DESTROY`: Secret version destroyed
- `SECRET_VERSION_DESTROY_SCHEDULED`: Destruction scheduled
- `SECRET_ROTATE`: Secret rotation triggered
- `TOPIC_CONFIGURED`: Test message when topics are configured

### Architecture

```
┌─────────────────┐    Publishes    ┌──────────────────┐    Consumes    ┌─────────────────┐
│ Secret Manager  │ ──────────────▶ │ Pub/Sub Topic    │ ────────────▶ │ Scheduler Cache │
│ (with topics)   │                 │ (notifications)  │                │ (in-memory)     │
└─────────────────┘                 └──────────────────┘                └─────────────────┘
       │                                    │                                    │
       │ Updates secret                     │                                    │ Invalidate cache
       │ ───────────────────────────────────┼─────────────────────────────────▶│ entry when
       │                                    │                                    │ notification
       │                                    │                                    │ received
```

### Implementation Strategy

1. **Setup Pub/Sub Topic**:
   ```bash
   gcloud pubsub topics create css-secret-notifications-topic
   ```

2. **Configure Secret Manager Service Agent**:
   ```bash
   gcloud beta services identity create \
       --service "secretmanager.googleapis.com" \
       --project "PROJECT_ID"
   ```

3. **Grant Pub/Sub Publisher Role**:
   ```bash
   gcloud projects add-iam-policy-binding PROJECT_ID \
       --member="serviceAccount:service-PROJECT_NUMBER@gcp-sa-secretmanager.iam.gserviceaccount.com" \
       --role="roles/pubsub.publisher"
   ```

4. **Configure Secrets with Notification Topics**:
   ```bash
   gcloud secrets create scheduler-team-TEAM_ID-basic-auth --topics css-secret-notifications-topic
   ```

5. **Create Subscription for Notifications**:
   ```bash
   gcloud pubsub subscriptions create css-secret-notifications-sub \
     --topic css-secret-notifications-topic
   ```

### Event-Driven Cache Management

#### Cache Structure
- In-memory cache with team ID as key
- Each entry contains: secret value, last updated timestamp, version
- Cache entries never expire automatically (infinite TTL)

#### Cache Invalidation Logic
1. **On Secret Update Events**: Invalidate specific team's cache entry
2. **On Secret Delete Events**: Remove team's cache entry and mark as invalid
3. **On Secret Version Events**: Update version info in cache metadata

#### Event Processing
```python
def process_secret_notification(pubsub_message):
    """Process Pub/Sub message from Secret Manager notifications"""
    attributes = pubsub_message.attributes
    event_type = attributes.get('eventType')
    secret_id = attributes.get('secretId')
    
    # Extract team ID from secret name (e.g., projects/.../secrets/scheduler-team-{teamId}-basic-auth)
    team_id = extract_team_id_from_secret_name(secret_id)
    
    if event_type in ['SECRET_UPDATE', 'SECRET_VERSION_ADD', 'SECRET_VERSION_ENABLE']:
        # Invalidate cache for this team
        invalidate_cache_entry(team_id)
    elif event_type == 'SECRET_DELETE':
        # Remove cache entry and mark as needing refresh
        remove_cache_entry(team_id)
```

### Benefits of Event-Driven Approach

1. **Optimal Performance**:
   - Cached secrets remain valid until actually changed
   - Eliminates unnecessary API calls for unchanged secrets
   - Reduces latency for unchanged secrets (pure in-memory access)

2. **Improved Security**:
   - Immediate cache invalidation when secrets change
   - No stale credentials in cache after rotation
   - Real-time response to security events

3. **Cost Efficiency**:
   - Significantly reduced Secret Manager API calls
   - Only fetch when actually needed after changes
   - Lower operational costs

4. **Reliability**:
   - Event-driven notifications are delivered reliably via Pub/Sub
   - Built-in retry mechanisms in Pub/Sub
   - No polling required

### Implementation Considerations

#### Error Handling
- Handle Pub/Sub subscription failures gracefully
- Fallback to time-based expiration if notifications fail
- Implement dead letter queue for undeliverable messages

#### Cache Warming
- Pre-populate cache with existing secrets on service startup
- Implement lazy loading for new teams
- Handle race conditions between notification and first access

#### Monitoring
- Track notification processing latency
- Monitor cache hit/miss ratios
- Alert on notification delivery failures

### Migration Strategy

1. **Phase 1**: Implement notification infrastructure alongside existing time-based cache
2. **Phase 2**: Gradually shift to event-driven invalidation
3. **Phase 3**: Remove time-based expiration completely

### Sample Implementation

```java
@Component
public class SecretManagerCache {
    
    private final Map<String, CachedSecret> cache = new ConcurrentHashMap<>();
    private final SecretManagerServiceClient client;
    
    // Process notifications from Pub/Sub
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
        
        // Cache miss - fetch from Secret Manager
        String secretValue = fetchFromSecretManager(teamId);
        cache.put(teamId, new CachedSecret(secretValue, Instant.now()));
        return secretValue;
    }
}
```

## Conclusion

Using GCP Secret Manager event notifications provides an optimal solution for caching secrets in the Cloud Scheduler Service. This approach ensures that cached secrets are invalidated immediately when they change while maintaining maximum cache efficiency for unchanged secrets. The event-driven model provides better performance, security, and cost efficiency compared to time-based caching strategies.

This solution directly addresses the requirement to fetch secrets only when they have actually changed (e.g., due to password expiration or manual updates) rather than on a fixed schedule, making it ideal for the Cloud Scheduler Service authentication enhancement.

## References

1. Google Cloud Secret Manager Documentation - Event Notifications: https://docs.cloud.google.com/secret-manager/docs/event-notifications
2. Stack Overflow - Google Cloud Secret Manager Notifications on PubSub: https://stackoverflow.com/questions/71435534/google-cloud-secret-manager-notifications-on-pubsub
3. Hoop.dev Blog - The Simplest Way to Make GCP Secret Manager Google Pub/Sub Work Like It Should: https://hoop.dev/blog/the-simplest-way-to-make-gcp-secret-manager-google-pub-sub-work-like-it-should/
4. HashiCorp Terraform Provider Google Issue #9548 - Secret Manager Secret publishing to Cloud Pub/Sub: https://github.com/hashicorp/terraform-provider-google/issues/9548