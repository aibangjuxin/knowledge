# Cloud Scheduler Service Authentication Enhancement - Droid Analysis Report

## Executive Summary

This document provides a comprehensive analysis and implementation guide for enhancing the Cloud Scheduler Service authentication mechanism, migrating from Firestore-only credential storage to a hybrid model supporting both **Firestore** and **Secret Manager**.

---

## 1. Project Overview

### 1.1 Current State
- Cloud Scheduler Service retrieves Basic Auth credentials from **Firestore**
- Multiple teams share a single Pub/Sub Topic
- ACK-before-process model (at-most-once delivery)
- No centralized secret management or audit trail

### 1.2 Target State
- Dual authentication source: **Secret Manager** (preferred) + **Firestore** (legacy)
- Explicit routing via `authType` field (no implicit fallback)
- Zero-downtime migration with full backward compatibility
- Enhanced security via Workload Identity (keyless access)

---

## 2. Architecture Design

### 2.1 High-Level Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────────────┐
│  Cloud          │     │  Pub/Sub        │     │  Scheduler Service      │
│  Scheduler Job  │────▶│  Topic          │────▶│  (GKE Pod)              │
└─────────────────┘     └─────────────────┘     └───────────┬─────────────┘
                                                            │
                                                ┌───────────▼───────────┐
                                                │  Parse Message        │
                                                │  (Team/Job/AuthType)  │
                                                └───────────┬───────────┘
                                                            │
                              ┌──────────────────┬──────────┴──────────┐
                              │                  │                     │
                   ┌──────────▼──────────┐ ┌─────▼─────┐    ┌──────────▼──────────┐
                   │ authType=           │ │           │    │ authType=           │
                   │ secret_manager      │ │  Cache    │    │ firestore           │
                   └──────────┬──────────┘ │  (LRU)    │    └──────────┬──────────┘
                              │            └─────┬─────┘               │
                   ┌──────────▼──────────┐       │          ┌──────────▼──────────┐
                   │  Secret Manager     │◀──────┘          │  Firestore          │
                   │  (New Teams)        │                  │  (Legacy)           │
                   └──────────┬──────────┘                  └──────────┬──────────┘
                              │                                        │
                              └────────────────┬───────────────────────┘
                                               │
                                    ┌──────────▼──────────┐
                                    │  Build Basic Auth   │
                                    │  HTTP Header        │
                                    └──────────┬──────────┘
                                               │
                                    ┌──────────▼──────────┐
                                    │  Backend API        │
                                    │  Service            │
                                    └─────────────────────┘
```

### 2.2 Security Model (Workload Identity)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          GKE Cluster                                    │
│  ┌───────────────────┐                                                  │
│  │ Scheduler Pod     │                                                  │
│  │                   │                                                  │
│  │ serviceAccount:   │                                                  │
│  │   scheduler-sa    │──────┐                                           │
│  └───────────────────┘      │                                           │
│                             │ Workload Identity Binding                 │
└─────────────────────────────┼───────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          GCP IAM                                        │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Google Service Account: scheduler-gsa                            │  │
│  │                                                                   │  │
│  │  IAM Role: roles/secretmanager.secretAccessor                     │  │
│  │  (Scoped to: scheduler-team-*-basic-auth secrets)                 │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                             │                                           │
│                             ▼                                           │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Secret Manager                                                   │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │  scheduler-team-{teamId}-basic-auth                         │  │  │
│  │  │  Payload: {"username": "api-user", "password": "xxx"}       │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Key Design Decisions

### 3.1 Explicit Routing (No Fallback)

| Scenario | Behavior |
|----------|----------|
| `authType = secret_manager` | Read ONLY from Secret Manager |
| `authType = firestore` | Read ONLY from Firestore |
| `authType` missing (legacy) | Default to Firestore |

**Rationale**: Prevents security bypass and makes debugging deterministic.

### 3.2 Cache Strategy (Critical for Cost & Performance)

| Parameter | Recommendation |
|-----------|----------------|
| Cache Type | In-memory LRU (Guava/Caffeine) |
| TTL | 5-10 minutes |
| Cache Key | `secret_manager:{team_id}` |
| Eviction | Passive expiration |

### 3.3 Cost Analysis

| Scenario | Daily Ops | Monthly Cost |
|----------|-----------|--------------|
| No Cache (QPS=50) | 4,320,000 | ~$390 USD |
| With Cache (99% hit) | 28,800 | ~$2.70 USD |

**Conclusion**: Application-level caching reduces cost by **99%+**.

---

## 4. Firestore Schema Enhancement

### 4.1 Current Schema (Legacy)
```json
{
  "teamId": "team-a",
  "username": "api-user",
  "password": "legacy-password"
}
```

### 4.2 Enhanced Schema
```json
{
  "teamId": "team-a",
  "authType": "secret_manager",
  "secretName": "projects/xxx/secrets/scheduler-team-a-basic-auth",
  "username": "api-user",
  "password": "legacy-password"
}
```

**Backward Compatibility**: Documents without `authType` default to `firestore`.

---

## 5. Secret Manager Specifications

### 5.1 Naming Convention
```
projects/{project-id}/secrets/scheduler-team-{teamId}-basic-auth
```

### 5.2 Secret Payload Format
```json
{
  "username": "api-user",
  "password": "secure-password"
}
```

### 5.3 Quota & Rate Limits
- Default: **30,000 requests/minute** per project
- With caching: Actual usage drops to <1% of quota

---

## 6. Implementation Guide

### 6.1 Code Architecture

```java
// Interface abstraction
public interface CredentialProvider {
    BasicAuthCredential getCredential(String teamId, JobContext ctx);
}

// Implementations
class FirestoreCredentialProvider implements CredentialProvider { ... }
class SecretManagerCredentialProvider implements CredentialProvider { ... }

// Router logic
CredentialProvider provider = switch(authType) {
    case "secret_manager" -> secretManagerProvider;
    default -> firestoreProvider;
};
```

### 6.2 Cache Implementation (Caffeine Example)

```java
Cache<String, BasicAuthCredential> credentialCache = Caffeine.newBuilder()
    .maximumSize(1000)
    .expireAfterWrite(Duration.ofMinutes(5))
    .build();

public BasicAuthCredential getCredential(String teamId) {
    return credentialCache.get(teamId, this::fetchFromSecretManager);
}
```

---

## 7. Observability Requirements

### 7.1 Mandatory Metrics
| Metric Name | Labels | Description |
|-------------|--------|-------------|
| `scheduler_auth_source_count` | `source={sm\|fs}`, `team_id` | Auth source distribution |
| `scheduler_secret_fetch_latency` | `team_id` | SM API latency |
| `scheduler_cache_hit_rate` | - | Cache effectiveness |
| `scheduler_auth_error_total` | `source`, `error_type` | Error tracking |

### 7.2 Log Schema
```json
{
  "level": "INFO",
  "message": "Credential fetched",
  "auth_source": "secret_manager",
  "team_id": "team-a",
  "job_id": "job-123",
  "cache_hit": true
}
```

---

## 8. Implementation Roadmap

| Phase | Tasks | Validation | Owner |
|-------|-------|------------|-------|
| **P1: Infra Ready** | 1. Setup Workload Identity (KSA→GSA)<br>2. Grant `secretmanager.secretAccessor` | `gcloud auth print-access-token` works in Pod | Infra |
| **P2: Code Dev** | 1. Add SM Client SDK<br>2. Implement `CredentialProvider`<br>3. Implement LRU Cache<br>4. Add metrics | Unit tests + local integration tests | Dev |
| **P3: Pilot** | 1. Select 1-2 test teams<br>2. Create secrets via script<br>3. Update Firestore `authType` | Monitor latency, cache hit rate | SRE |
| **P4: Migration** | 1. Batch migrate secrets<br>2. Gradually switch `authType` | No metric anomalies | Platform |

---

## 9. Rollback Strategy

### 9.1 Per-Team Rollback
1. Update Firestore document: `authType = "firestore"`
2. No code deployment required
3. Takes effect on next message processing

### 9.2 Global Rollback
1. Deploy previous service version
2. Or set feature flag to disable SM path

---

## 10. Security Checklist

- [ ] No service account keys in Pods (Workload Identity only)
- [ ] IAM role scoped to specific secret prefix
- [ ] Secret access audit logging enabled
- [ ] No credential values in application logs
- [ ] TLS for all API communications

---

## 11. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| SM API throttling | Auth failures | Implement caching (99% reduction) |
| Secret not found | Job failure | Explicit error handling, no fallback |
| Workload Identity misconfiguration | Service unavailable | Validate in staging first |
| Cache stale data | Using old credentials | TTL 5-10 min acceptable for secret rotation |

---

## 12. Conclusion

This enhancement provides:
- **Security**: Centralized secret management with audit trail
- **Compliance**: Workload Identity eliminates embedded keys
- **Cost Control**: Caching reduces API costs by 99%+
- **Compatibility**: Zero-downtime migration, old users unaffected

The explicit `authType` routing ensures clean separation between legacy and new authentication paths, enabling gradual migration at the team level.

---

## References

- [GCP Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Pub/Sub StreamingPull](https://cloud.google.com/pubsub/docs/pull)
- Source Documents:
  - `css-enhance-summary.md`
  - `css-enhance-plan.md`
  - `css-enhance.md`
