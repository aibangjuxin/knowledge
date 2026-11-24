# System Design Cheatsheet

> High-level guide to design scalable, reliable, and maintainable systems.
>
> Source: infographic by **@e_opore** (saved as `sy.jpeg`).
> This version keeps the original 15 sections and expands them with the
> practical details an interview or a design review usually asks for.
>
> 中文版：[system-design-cheatsheet-cn.md](system-design-cheatsheet-cn.md)

---

## Table of Contents

1. [Fundamentals](#1-fundamentals)
2. [CAP Theorem](#2-cap-theorem)
3. [PACELC](#3-pacelc)
4. [Load Balancing](#4-load-balancing)
5. [Scaling Strategies](#5-scaling-strategies)
6. [Caching](#6-caching)
7. [Databases](#7-databases)
8. [System Architecture Patterns](#8-system-architecture-patterns)
9. [Common Components](#9-common-components)
10. [Design Process](#10-design-process)
11. [Estimation Cheatsheet](#11-estimation-cheatsheet)
12. [Consistency Models](#12-consistency-models)
13. [Failure Handling](#13-failure-handling)
14. [Monitoring & Observability](#14-monitoring--observability)
15. [Common Trade-offs](#15-common-trade-offs)
16. [Rate Limiting & Backpressure](#16-rate-limiting--backpressure)
17. [Deployment & Release Strategies](#17-deployment--release-strategies)
18. [High Availability & Disaster Recovery](#18-high-availability--disaster-recovery)
19. [Security & API Basics](#19-security--api-basics)
20. [Interview Checklist](#20-interview-checklist)
21. [Closing Quote & Tips](#closing-quote--tips)
22. [Glossary](#glossary)

---

## 1. Fundamentals

| # | Pillar | Definition |
|---|---|---|
| 1.1 | **Scalability** | System's ability to handle growth by adding resources. |
| 1.2 | **Reliability** | System works correctly even in failures. |
| 1.3 | **Availability** | System is up and running when needed. |
| 1.4 | **Maintainability** | Easy to update, fix and improve the system. |
| 1.5 | **Performance** | System responds fast and handles load efficiently. |

**Scaling law of 3** (a rough heuristic, not a rule):

> Every 3x increase in traffic requires about 2x more resources,
> because a constant fraction of the traffic is always the "long tail"
> that does not scale linearly with the head.

---

## 2. CAP Theorem

A Venn diagram with three circles:

- **Consistency** — All nodes see the same data at the same time.
- **Availability** — System remains available at all times.
- **Partition Tolerance** — System works even if network partitions occur.

> **You can only guarantee two out of the three.**

**Practical reading (the version that survives design review):**

| Situation | You get | You give up | Typical choice |
|---|---|---|---|
| Partition happens | **CP** or **AP** — one must be sacrificed | The other one | Per-operation: reads can be AP, writes can be CP |
| No partition | **CA** is fine | Nothing | Consistency is free (until a partition shows up) |

Most production systems are **CP for writes, AP for reads**: the write path
needs linearizability, the read path can serve a slightly stale replica to
stay fast and available.

---

## 3. PACELC

- If **P**artition (P) occurs, choose **A**vailability (A) over **C**onsistency (C).
- Else (E), choose **L**atency (L) over **C**onsistency (C).

PACELC = CAP + "when there is no partition, still trade consistency for latency."
This is why read replicas and CDNs exist: they lower latency (and cost)
at the price of stale reads.

---

## 4. Load Balancing

- Distributes incoming traffic across multiple servers.
- **Types:** Round Robin, Least Connections, IP Hash, Least Response Time.
- Improves reliability and scalability.

### Algorithm cheat sheet

| Algorithm | How it picks | Best for | Watch out for |
|---|---|---|---|
| **Round Robin** | Rotates in order | Homogeneous servers, even load | Hot spots on slow nodes |
| **Weighted Round Robin** | Rotates with weights | Mixed instance types | Needs manual tuning |
| **Least Connections** | Fewest active connections | Long-lived / variable-cost requests | Ignores per-node CPU |
| **IP Hash** | Hash of client IP | Session stickiness | Unbalanced with few clients |
| **Least Response Time** | Lowest latency node | Heterogeneous / multi-region | Needs accurate metrics |
| **Consistent Hashing** | Hash ring, virtual nodes | Cache clusters, partitioned state | Rebalancing on node change |
| **Power of Two Choices** | Random pick of 2, pick the better | General purpose, great balance | Needs per-node stats |

### L4 vs L7

| | **L4 (Transport)** | **L7 (Application)** |
|---|---|---|
| Sees | TCP/UDP connections | HTTP headers, paths, body |
| Routing | IP + port only | Host, path, cookie, header |
| Can do TLS termination | No (needs passthrough) | Yes |
| Overhead | Minimal | Higher (parse, buffer) |
| Use when | TCP/UDP, gRPC passthrough, QUIC | HTTP APIs, caching, rate limits |

### Health checks

- **Liveness** — is the process alive? Failing it means *restart* the pod.
  Never depend on downstream services here, or a dependency outage restarts
  your whole fleet.
- **Readiness** — can it serve traffic right now? Failing it means *remove
  from the load balancer*, do not restart.
- **Startup** — slow-starting app; keeps the LB away until the app is warm.

---

## 5. Scaling Strategies

| Strategy | Definition |
|---|---|
| **Vertical Scaling (Scale Up)** | Add more power to a single server. |
| **Horizontal Scaling (Scale Out)** | Add more servers behind a load balancer. |
| **Auto Scaling** | Automatically add / remove servers based on traffic. |

**Scale up vs scale out**

| | Scale Up | Scale Out |
|---|---|---|
| Limit | Physical ceiling of one machine | Depends on the software design |
| Cost curve | Exponential (2x perf >> 2x price) | Linear-ish, pay for what you use |
| Failure impact | Whole instance goes down | One of many nodes fails |
| Complexity | Simple | Needs LB, state, coordination |
| Best for | Databases, stateful legacy systems | Stateless services, read-heavy workloads |

**Statelessness is the prerequisite.** Move session/state to Redis, the DB,
or object storage, then any pod can serve any request and horizontal scaling
becomes trivial.

---

## 6. Caching

- Reduces load and improves response time by storing frequently used data.
- **Types:** Browser Cache, CDN Cache, Application Cache, Database Cache.
- **Tools:** Redis, Memcached.

### Cache layers

| Layer | Lives in | Typical TTL | Invalidated by |
|---|---|---|---|
| Browser / local | User device | Minutes–days | User, CDN headers |
| CDN / edge | PoP | Hours–days | Purge API, origin version |
| Application (in-process) | App heap | Seconds–minutes | Code deploy, TTL |
| Distributed (Redis) | Cluster | Seconds–hours | TTL, explicit delete |
| Query / row cache | DB engine | Seconds | Writes |

### Cache strategies (read path)

| Strategy | How it works | Miss cost | Notes |
|---|---|---|---|
| **Cache-aside** (lazy loading) | Read cache -> miss -> read DB -> fill cache | +1 DB read | Most common; needs TTL |
| **Read-through** | Cache fetches from DB on miss itself | +1 DB read | Library-managed |
| **Write-through** | Write DB *and* cache together | Slower writes | Cache never stale |
| **Write-around** | Write DB only; cache fills on next read | +1 DB read | For rarely-read data |
| **Write-behind / write-back** | Write cache, flush to DB later | Risk of data loss | Needs durable log |

### Eviction & sizing

- **LRU** — evict least recently used. Good default.
- **LFU** — evict least frequently used. Good for skewed hot data.
- **TTL** — expire by time. The only real protection against stale data.
- **Random / ARC / 2Q** — alternatives when access patterns are unusual.

> Rule of thumb: keep the cache working set ~70–80% of the cache size so
> eviction happens on cold data, not on hot data.

### The four hard problems

1. **Cache stampede (thundering herd)** — hot key expires, 10k requests hit
   the DB at once. Fix: single-flight / request coalescing, jittered TTL,
   stale-while-revalidate, proactive warm-up.
2. **Cache penetration** — requests for keys that never exist. Fix:
   negative caching (cache the "not found"), bloom filter, input validation.
3. **Cache avalanche** — many keys expire together. Fix: TTL jitter
   (+/-10–20%), pre-warm at deploy time, background refresh.
4. **Cache invalidation** — "one of the two hard problems in CS". Fix:
   versioned keys, event-driven invalidation (CDC), short TTL as a backstop.

---

## 7. Databases

### SQL Databases
- Structured data, ACID compliance.
- **Examples:** MySQL, PostgreSQL.

### NoSQL Databases
- Flexible schema, high scalability.
- **Types:**
  - **Key-Value:** Redis, DynamoDB
  - **Document:** MongoDB
  - **Column:** Cassandra, HBase
  - **Graph:** Neo4j

### Sharding
- Split data across multiple DB instances.
- Improves write / read scalability.

**Partition strategies**

| Strategy | How keys are assigned | Pros | Cons |
|---|---|---|---|
| **Hash** | hash(key) % N | Even distribution | Range scans impossible; resharding is hard |
| **Range** | key range | Range queries natural | Hot spots on the newest range |
| **Directory** | lookup table | Flexible, per-key control | Extra lookup hop, directory becomes a SPOF risk |
| **Time-based** | by time bucket | Easy expiry/rollover | Writes concentrated in the newest bucket |

**Sharding pitfalls:** uneven shard sizes, cross-shard joins, scatter-gather
fan-out, resharding a live dataset, and per-shard connection pools.

### Replication
- Master-Slave or Leader-Follower model.
- Improves read availability and fault tolerance.

| Concern | Option |
|---|---|
| Read scaling | Read replicas (async = may lag, sync = costs write latency) |
| HA failover | Automatic failover with leader election (etcd / Raft) |
| Write scaling | Leader write is the bottleneck -> shard it |

### Storage engines

| | **B-Tree** (MySQL InnoDB, PostgreSQL) | **LSM-Tree** (RocksDB, Cassandra, LevelDB) |
|---|---|---|
| Writes | In-place page update, random IO | Append to memtable + WAL, then compaction |
| Read | Fast point/range read | Fast if in memtable, slower after compaction |
| Write amplification | Low | High (compaction) |
| Read amplification | Low | Medium |
| Best for | Read-heavy, general OLTP | Write-heavy, high ingest rate |

### Other scaling levers

- **Read/write split** — replicas for reads, primary for writes.
- **Denormalization** — trade write cost for read speed.
- **CQRS** — separate read and write models (read model in a search DB).
- **Archiving / tiering** — move cold data to cheaper storage (S3 + Athena).

---

## 8. System Architecture Patterns

| Pattern | Description |
|---|---|
| **Monolithic** | Single codebase & deployment. Simple but hard to scale. |
| **Microservices** | Small independent services. Scalable and maintainable. |
| **SOA (Service-Oriented Architecture)** | Services communicate via enterprise service bus. |
| **Event-Driven Architecture** | Components communicate via events (async). |

**Sync vs async calls**

| | Synchronous (REST/gRPC) | Asynchronous (queue/event) |
|---|---|---|
| Coupling | Caller waits, knows the callee | Loose coupling, no knowledge of consumers |
| Failure mode | Caller blocked / times out | Messages buffered, retried |
| Latency | Adds to the user request path | Removed from the request path |
| Consistency | Easier to reason about | Eventual, needs idempotency |
| Use for | Reads needing an immediate answer | Writes, spikes, fan-out, slow work |

**Service boundaries:** split by **business capability** (bounded context),
not by technical layer ("all controllers in one service"). Team ownership
maps to services; a service that two teams fight over is split in the wrong place.

---

## 9. Common Components

| Component | Description | Tools |
|---|---|---|
| **API Gateway** | Single entry point for all client requests. Handles routing, auth, rate limiting. | — |
| **Service Discovery** | Finds available service instances. | Eureka, Consul, Zookeeper |
| **Message Queue** | Enables async communication. | Kafka, RabbitMQ, SQS |
| **CDN (Content Delivery Network)** | Delivers content from edge locations. | Cloudflare, Akamai, AWS CloudFront |
| **Blob / Object Storage** | Stores large files and media. | S3, GCS, Azure Blob Storage |

**More components you will be asked about**

| Component | Description | Tools |
|---|---|---|
| **Reverse Proxy / Ingress** | Terminates TLS, routes by host/path, does redirects | Nginx, Envoy, GKE Ingress |
| **Config / Feature Flags** | Dynamic config rollout without redeploy | Consul, etcd, LaunchDarkly, Unleash |
| **Distributed Lock** | Mutual exclusion across nodes | Redis SET NX, ZooKeeper, Chubby |
| **Idempotency Store** | Deduplicates retries of the same request | Redis with TTL, DynamoDB conditional write |
| **Search / Index** | Full-text + faceted search | Elasticsearch, OpenSearch, Spanner |
| **Data Warehouse / Lake** | OLAP analytics over historical data | BigQuery, Snowflake, Iceberg |
| **Secret Manager** | Stores and rotates credentials | Vault, Secret Manager, KMS |
| **Job Scheduler** | Cron-like and DAG orchestration | Airflow, Cloud Scheduler, Temporal |

---

## 10. Design Process

A six-step workflow:

1. **Understand Requirements** — Clarify functional & non-functional requirements.
2. **Define Goals & Constraints** — Identify scale, latency, availability, consistency, budget.
3. **High-Level Design** — Design major components and their interactions.
4. **Detailed Design** — Design each component and data models.
5. **Capacity Estimation** — Estimate storage, bandwidth, QPS, and resources.
6. **Trade-offs & Alternatives** — Evaluate and document trade-offs.

### The questions that actually decide the design

| Question | Typical default if unanswered |
|---|---|
| Read-heavy or write-heavy? | Assume read-heavy (10:1) |
| Peak vs average traffic ratio? | Assume 3–10x peak |
| Is it multi-tenant? | Single tenant, add a tenant_id column later |
| Strict consistency needed? | Eventual, with read-your-writes for the session |
| Is it global? | Single region + CDN, unless the business says otherwise |
| Budget / cost ceiling? | Optimize for latency, then cut cost with caching & autoscaling |
| Compliance (PII, audit)? | Encrypt at rest + in transit, audit log, retention policy |

### High-level design sketch

```text
Client
  |
  v
CDN ---> Static assets
  |
  v
API Gateway  (TLS, auth, rate limit, routing)
  |
  +---> Service A  ---> Redis (cache)
  |        |
  |        +---> Message Queue ---> Worker ---> DB / Blob Storage
  |
  +---> Service B  ---> SQL Primary ---> Read Replica
```

---

## 11. Estimation Cheatsheet

### Powers of 10 (data size)

| Unit | Bytes (approx.) | Bytes (binary, exact) |
|---|---|---|
| 1 KB | 10^3 = 1 000 | 2^10 = 1 024 |
| 1 MB | 10^6 = 1 000 000 | 2^20 = 1 048 576 |
| 1 GB | 10^9 = 1 000 000 000 | 2^30 = 1 073 741 824 |
| 1 TB | 10^12 = 1 000 000 000 000 | 2^40 = 1 099 511 627 776 |

> Interview convention: use 10^n for quick math and 2^n when the question is
> about actual storage (a "1 MB file" is usually 1 048 576 bytes on disk).

### Powers of 10 (user count)

| Users | Approximate |
|---|---|
| 1 000 | 10^3 |
| 1 Million | 10^6 |
| 1 Billion | 10^9 |

### Latency numbers (round numbers, same ballpark as "Latency Numbers Every Programmer Should Know")

| Operation | Time |
|---|---|
| L1 cache read | ~0.5 ns |
| L2 cache read | ~3 ns |
| Main memory read | ~100 ns |
| SSD random read | ~50–100 us |
| Disk random read (SSD) | ~150 us |
| Same-datacenter TCP round trip | ~0.5 ms |
| Same-continent round trip | ~30–50 ms |
| Cross-continent round trip | ~150–200 ms |

> Memory-speed vs network-speed gap is the single most important number in
> system design: moving bytes over the network costs ~10^6x a memory access.

### Key formulas

- **Bandwidth** = Data Transfer / Time
- **Storage** = Data Size x Replication Factor
- **QPS** = Requests per Second

### Worked example

> *Design a URL shortener for 100 M new URLs per month, 100 M reads/day.*

1. **Write QPS** = 100 M / 30 days / 86 400 s ~= **40 writes/s** -> tiny.
   A single modern Postgres is enough for writes.
2. **Read QPS** = 100 M / 86 400 s ~= **1 150 reads/s** (~1.2 k).
   With a 10x peak factor -> ~12 k reads/s.
3. **Storage** = 100 M URLs x ~500 B (incl. metadata) ~= **50 GB/year**.
   With 3x replication ~= 150 GB. Fits easily on one volume for years.
4. **Key-value lookup** — the read path is a single GET by key, so a KV store
   or an index on the primary is the answer. No sharding needed.
5. **Cache** — the top 20% of links likely carry most traffic -> Redis or
   in-process LRU takes the read load off the DB.
6. **Redirect latency target** = 1 DNS + 1 TCP/TLS + 1 lookup ~= **< 100 ms**;
   keep the hot path in memory and pre-generate the short code.

---

## 12. Consistency Models

| Model | Behavior |
|---|---|
| **Strong Consistency** | All reads return the latest write. High availability may be impacted. |
| **Eventual Consistency** | Data will be consistent over time. High availability and partition tolerant. |
| **Weak Consistency** | Some reads may return stale data. High availability. |

### Stronger variants (useful vocabulary)

| Model | Guarantee |
|---|---|
| **Linearizable** | Reads/writes behave as if on a single copy, real-time order |
| **Sequential** | All nodes see operations in the same order (may be stale) |
| **Causal** | Causally related operations are seen in order |
| **Read-your-writes** | You always see your own writes (session stickiness / version token) |
| **Monotonic reads** | You never go back in time while reading |

---

## 13. Failure Handling

| Pattern | Description |
|---|---|
| **Retry** | Retry failed requests with backoff. |
| **Timeout** | Fail fast if a service takes too long. |
| **Circuit Breaker** | Stop calls to failing service temporarily. |
| **Fallback** | Provide alternative response when primary fails. |

### Retries in detail

- **Exponential backoff** — delay = base x 2^attempt.
- **Jitter** — add randomness, otherwise every client retries in lockstep
  ("thundering herd" on recovery). Full jitter is the best simple variant.
- **Retry budget** — cap retries as a % of total requests (e.g. 10%) so a
  retry storm cannot take down the whole system.
- **Only retry idempotent operations** — or make them idempotent (see below).
- **Retry amplification** — 3 layers each retrying 3 times = 27x the load.
  Set a global policy and propagate the deadline.

### Idempotency

| Technique | How |
|---|---|
| **Idempotency key** | Client sends a unique key; server stores the result for a TTL and returns it on replay |
| **Conditional write** | `INSERT ... ON CONFLICT`, `UPDATE ... WHERE version = n` |
| **Dedup key** | Unique index on a business key; duplicates are rejected |
| **Natural idempotency** | `SET key = value` instead of `key = key + 1` |

### Degradation ladder (when things break)

1. **Cache hit** — serve stale data (stale-while-revalidate).
2. **Fallback / default response** — serve a degraded but valid answer.
3. **Load shedding** — reject a share of traffic deliberately to protect the core.
4. **Circuit breaker open** — stop calling the broken dependency entirely.
5. **Fail fast** — return an error, do not hang.

> Availability is a budget: every dependency you call can fail. Prefer fewer,
> faster, more reliable dependencies.

---

## 14. Monitoring & Observability

| Pillar | Purpose |
|---|---|
| **Logging** | Collect logs for debugging. |
| **Metrics** | Collect metrics (CPU, Memory, QPS). |
| **Tracing** | Trace requests across services. |
| **Alerts** | Alert on error rates, latency, etc. |

### Metric frameworks

| Framework | Metrics | Use for |
|---|---|---|
| **RED** | Rate, Errors, Duration | Every request-serving service |
| **USE** | Utilisation, Saturation, Errors | Every resource (CPU, disk, network) |
| **Four Golden Signals** | Latency, Traffic, Errors, Saturation | Service-level dashboards |

### SLI / SLO / SLA / error budget

| Term | Meaning |
|---|---|
| **SLI** | The measured number (e.g. "99.9% of requests < 200 ms") |
| **SLO** | The target for that SLI |
| **SLA** | The contractual promise to the customer (usually less strict) |
| **Error budget** | 1 - SLO. The amount of unreliability you are allowed to spend |

> If the error budget is exhausted, freeze features and spend the time on
> reliability. This is the cheapest operational policy you will ever write.

### Logging & tracing practice

- **Structured logs** (JSON) with `request_id` / `trace_id` on every line.
- **Three pillars**: logs (detail), metrics (trend), traces (where).
- **Sampling**: keep 100% of errors, sample the happy path (1–10%).
- **Cardinality**: label metrics with bounded dimensions only — unbounded
  labels (user_id) will blow up your metrics backend.
- **Alert on symptoms, not causes**: page on "error rate > 2%", not on
  "CPU > 80%".

---

## 15. Common Trade-offs

| Left | vs. | Right |
|---|---|---|
| Consistency | vs. | Availability |
| Performance | vs. | Cost |
| Scalability | vs. | Complexity |
| Reliability | vs. | Latency |

### More trade-offs worth naming out loud

| Left | vs. | Right |
|---|---|---|
| Latency | vs. | Throughput |
| Fresh data | vs. | Cheaper reads |
| Strong consistency | vs. | Write availability |
| Coupling | vs. | Failure isolation |
| Batch writes | vs. | Freshness |
| Over-fetching | vs. | Extra network round trip |
| Premature optimization | vs. | Engineering cost |
| Multi-region active-active | vs. | Complexity and cost |

---

## 16. Rate Limiting & Backpressure

### Algorithms

| Algorithm | Behaviour | Burst | Use when |
|---|---|---|---|
| **Fixed window** | Counter reset every N seconds | Allowed at boundary | Simple, leaky at edges |
| **Sliding window log** | Keep timestamps of every request | Exact | Low volume, precise |
| **Sliding window counter** | Weighted previous + current window | Smooth | General purpose |
| **Token bucket** | Tokens refill at a rate, cost per request | Yes, up to bucket size | APIs, burst-tolerant |
| **Leaky bucket** | Requests drain at a fixed rate | No | Smooths traffic, e.g. to a DB |
| **Concurrency limit** | Limit in-flight requests | No | Protect a scarce resource |

### Where to enforce it

- **Edge / CDN** — protect the whole origin from floods.
- **API Gateway** — per user, per key, per route.
- **Service level** — protect *yourself* from a misbehaving internal caller.
- **Downstream dependency** — keep your QPS below what the DB can take.

### Backpressure

Backpressure = the system telling the producer to slow down when the
consumer cannot keep up. Mechanisms:

| Mechanism | How |
|---|---|
| **Bounded queue** | Reject (or block) when full — the simplest backpressure |
| **Load shedding** | Serve the top X% of traffic by priority, drop the rest |
| **Adaptive concurrency** | Limit in-flight requests to keep latency at target |
| **Credit / quota system** | Consumer grants credits, producer spends them |
| **Async buffer** | Buffer in Kafka/Pub-Sub and let the consumer catch up |

> An unbounded queue is not backpressure — it is a memory leak with extra steps.
> Always bound the queue and decide what happens when it is full.

---

## 17. Deployment & Release Strategies

| Strategy | How | Rollback | Use when |
|---|---|---|---|
| **Rolling update** | Replace instances gradually | Fast (roll forward/back) | Stateless services |
| **Blue-Green** | Two identical environments, switch traffic | Instant (switch back) | Big releases, DB changes need care |
| **Canary** | Small % of traffic -> new version | Instant (stop the canary) | High-traffic services |
| **Recreate** | Stop all, then start new | Downtime | Dev / batch jobs |
| **Feature flag** | Code is deployed but dark | Flip the flag | Decoupling deploy from release |

### Zero-downtime database changes

| Change | Safe pattern |
|---|---|
| Add column | Expand: add nullable column -> backfill -> dual write -> switch reads |
| Rename column | Add new column, dual write, migrate readers, drop old later |
| Drop column | Stop using it -> wait one deploy cycle -> drop it |
| Add index | Online/concurrent index build, not a blocking CREATE INDEX |
| Change type | New column + backfill + cutover (no in-place type change) |

> **Expand / migrate / contract** is the universal three-phase pattern.
> Never mix a schema change and a code change in the same deploy.

---

## 18. High Availability & Disaster Recovery

| Term | Meaning |
|---|---|
| **SLO** | Target availability, e.g. 99.9% ("three nines") |
| **Uptime budget** | Allowed downtime per period |
| **RTO** | Recovery Time Objective — how long to restore service |
| **RPO** | Recovery Point Objective — how much data loss is acceptable |
| **Failover** | Switch traffic to another region / cluster |
| **Multi-AZ** | Same region, different zones — cheap, common default |
| **Multi-region** | Different regions — survives a regional outage |

| Availability | Downtime/year | Downtime/day |
|---|---|---|
| 99% | 3.65 days | 14.4 min |
| 99.9% | 8.77 hours | 86.4 s |
| 99.95% | 4.38 hours | 43.2 s |
| 99.99% | 52.6 minutes | 8.64 s |
| 99.999% | 5.26 minutes | 0.86 s |

**Design levers**

- **Active-passive** — standby waits; failover is slow, cost is low.
- **Active-active** — both serve; failover is fast, conflict resolution is hard.
- **Multi-region reads** — serve reads locally, replicate writes to a home region.
- **Backups != replication** — a replicated mistake is replicated too.
  Test restores, and keep an immutable/offline backup copy.
- **Game days** — practice the failover; an untested DR plan is a rumour.

---

## 19. Security & API Basics

| Area | Baseline |
|---|---|
| **Transport** | TLS everywhere; TLS 1.2+ (1.3 preferred); HSTS |
| **AuthN** | OAuth2 / OIDC for users, short-lived JWT or session cookies |
| **AuthZ** | Check permissions per request; deny by default; RBAC/ABAC |
| **Secrets** | Never in code or images; secret manager + rotation |
| **Encryption** | At rest (KMS-managed keys) and in transit |
| **Input validation** | Allow-list, parameterized queries, size limits |
| **Rate limiting / WAF** | Per identity, not just per IP |
| **Audit** | Log who did what, when, from where (immutable sink) |
| **PII** | Minimize, encrypt, define retention and deletion |

### API versioning & compatibility

| Change | Compatible? |
|---|---|
| Add an optional field | Yes |
| Add a new endpoint | Yes |
| Widen a type (int -> string is **no**) | Depends |
| Remove / rename a field | No — version or deprecate first |
| Change default behaviour | No |
| Change error codes / status codes | No (clients depend on them) |

Versioning options: URL path (`/v1/...`), header, or "expand/contract" with
parallel versions running side by side. Announce a deprecation date and
instrument usage so you can retire old versions with data.

---

## 20. Interview Checklist

Before you start drawing boxes, be ready to answer:

- [ ] What are the functional requirements, and what is explicitly out of scope?
- [ ] How many users, and how many requests per user per day?
- [ ] Read/write ratio, and peak-to-average ratio?
- [ ] What are the latency targets (p50 / p99) and the availability target?
- [ ] Does it need to be strongly consistent, or is eventual OK?
- [ ] Is it global or single region? Is it multi-tenant?
- [ ] What is the growth expectation in 12 months?
- [ ] What is the budget, and what is the cost driver?
- [ ] What are the compliance / data-residency constraints?
- [ ] What is the failure domain you are most worried about?

And during the design:

- [ ] Draw the high-level diagram and describe one request end to end.
- [ ] Show the write path and the read path separately.
- [ ] Identify the bottleneck and the scaling limit ("this design breaks at 50 k QPS because ...").
- [ ] Show the data model (entities, keys, cardinality).
- [ ] Explain the failure modes: what happens when a dependency is down?
- [ ] State the trade-offs you made and what you would change with more budget.

---

## Closing Quote & Tips

> **Good system design is about trade-offs and making the right decision for the right context.**
>
> — *Happy Designing!*

---

## Tips (footer)

| Tip | Detail |
|---|---|
| 💡 | Start simple, scale only when needed. |
| 📈 | Measure, don't guess. Use data! |
| 📄 | Document assumptions and decisions. |
| 🚀 | Keep learning and stay curious. |

---

## Glossary

| Term | Meaning |
|---|---|
| **ACID** | Atomicity, Consistency, Isolation, Durability — SQL transaction guarantees |
| **ADR** | Architecture Decision Record — a short doc capturing one decision |
| **Backpressure** | Signal from consumer to producer to slow down |
| **Blue-Green** | Two parallel environments, switch traffic between them |
| **Canary** | Small percentage of traffic on a new version |
| **Cold start** | First request after scale-from-zero: slow due to uninitialized caches/JIT |
| **Consistent hashing** | Hash ring placement so only ~1/N of keys move on node change |
| **CQRS** | Command Query Responsibility Segregation — separate write and read models |
| **Eventual consistency** | Replicas converge over time without coordination |
| **Failover** | Automatic switch to a standby system |
| **Fan-out** | One request fanning out to many downstream calls |
| **Idempotency** | Repeating a request has the same effect as doing it once |
| **Idempotency key** | Client-generated token that makes a retry safe |
| **Linearizability** | Operations appear to take effect instantaneously at one point in time |
| **Load shedding** | Deliberately dropping requests to protect the system |
| **N+1 queries** | One query plus one per result row — a classic performance killer |
| **OpenTelemetry** | Vendor-neutral standard for traces and metrics |
| **Partition tolerance** | System keeps working despite network partitions |
| **p99 latency** | The 99th percentile of response times |
| **Read-your-writes** | User sees their own write immediately after making it |
| **RPO / RTO** | Recovery Point Objective / Recovery Time Objective |
| **Sharding** | Splitting data across multiple database instances |
| **SLO / SLI** | Service Level Objective / Indicator |
| **Sticky session** | Forcing a user's requests to the same instance |
| **Throughput** | Completed operations per unit of time |
| **Token bucket** | Rate limiter allowing bursts up to a bucket size |
| **Zero-downtime deployment** | Releasing a new version without interrupting service |
