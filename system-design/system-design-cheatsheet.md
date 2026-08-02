# System Design Cheatsheet

> High-level guide to design scalable, reliable, and maintainable systems.
>
> Source: infographic by **@e_opore** (saved as `sy.jpeg`).

---

## 1. Fundamentals

| # | Pillar | Definition |
|---|---|---|
| 1.1 | **Scalability** | System's ability to handle growth by adding resources. |
| 1.2 | **Reliability** | System works correctly even in failures. |
| 1.3 | **Availability** | System is up and running when needed. |
| 1.4 | **Maintainability** | Easy to update, fix and improve the system. |
| 1.5 | **Performance** | System responds fast and handles load efficiently. |

---

## 2. CAP Theorem

A Venn diagram with three circles:

- **Consistency** — All nodes see the same data at the same time.
- **Availability** — System remains available at all times.
- **Partition Tolerance** — System works even if network partitions occur.

> **You can only guarantee two out of the three.**

---

## 3. PACELC

- If **P**artition (P) occurs, choose **A**vailability (A) over **C**onsistency (C).
- Else (E), choose **L**atency (L) over **C**onsistency (C).

---

## 4. Load Balancing

- Distributes incoming traffic across multiple servers.
- **Types:** Round Robin, Least Connections, IP Hash, Least Response Time.
- Improves reliability and scalability.

---

## 5. Scaling Strategies

| Strategy | Definition |
|---|---|
| **Vertical Scaling (Scale Up)** | Add more power to a single server. |
| **Horizontal Scaling (Scale Out)** | Add more servers behind a load balancer. |
| **Auto Scaling** | Automatically add / remove servers based on traffic. |

---

## 6. Caching

- Reduces load and improves response time by storing frequently used data.
- **Types:** Browser Cache, CDN Cache, Application Cache, Database Cache.
- **Tools:** Redis, Memcached.

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

### Replication
- Master-Slave or Leader-Follower model.
- Improves read availability and fault tolerance.

---

## 8. System Architecture Patterns

| Pattern | Description |
|---|---|
| **Monolithic** | Single codebase & deployment. Simple but hard to scale. |
| **Microservices** | Small independent services. Scalable and maintainable. |
| **SOA (Service-Oriented Architecture)** | Services communicate via enterprise service bus. |
| **Event-Driven Architecture** | Components communicate via events (async). |

---

## 9. Common Components

| Component | Description | Tools |
|---|---|---|
| **API Gateway** | Single entry point for all client requests. Handles routing, auth, rate limiting. | — |
| **Service Discovery** | Finds available service instances. | Eureka, Consul, Zookeeper |
| **Message Queue** | Enables async communication. | Kafka, RabbitMQ, SQS |
| **CDN (Content Delivery Network)** | Delivers content from edge locations. | Cloudflare, Akamai, AWS CloudFront |
| **Blob / Object Storage** | Stores large files and media. | S3, GCS, Azure Blob Storage |

---

## 10. Design Process

A six-step workflow:

1. **Understand Requirements** — Clarify functional & non-functional requirements.
2. **Define Goals & Constraints** — Identify scale, latency, availability, consistency, budget.
3. **High-Level Design** — Design major components and their interactions.
4. **Detailed Design** — Design each component and data models.
5. **Capacity Estimation** — Estimate storage, bandwidth, QPS, and resources.
6. **Trade-offs & Alternatives** — Evaluate and document trade-offs.

---

## 11. Estimation Cheatsheet

### Powers of 10 (data size)

| Unit | Bytes |
|---|---|
| 1 KB | 10³ |
| 1 MB | 10⁶ |
| 1 GB | 10⁹ |
| 1 TB | 10¹² |

### Powers of 10 (user count)

| Users | Approximate |
|---|---|
| 1 000 | 10³ |
| 1 Million | 10⁶ |
| 1 Billion | 10⁹ |

### Key formulas

- **Bandwidth** = Data Transfer / Time
- **Storage** = Data Size × Replication Factor
- **QPS** = Requests per Second

---

## 12. Consistency Models

| Model | Behavior |
|---|---|
| **Strong Consistency** | All reads return the latest write. High availability may be impacted. |
| **Eventual Consistency** | Data will be consistent over time. High availability and partition tolerant. |
| **Weak Consistency** | Some reads may return stale data. High availability. |

---

## 13. Failure Handling

| Pattern | Description |
|---|---|
| **Retry** | Retry failed requests with backoff. |
| **Timeout** | Fail fast if a service takes too long. |
| **Circuit Breaker** | Stop calls to failing service temporarily. |
| **Fallback** | Provide alternative response when primary fails. |

---

## 14. Monitoring & Observability

| Pillar | Purpose |
|---|---|
| **Logging** | Collect logs for debugging. |
| **Metrics** | Collect metrics (CPU, Memory, QPS). |
| **Tracing** | Trace requests across services. |
| **Alerts** | Alert on error rates, latency, etc. |

---

## 15. Common Trade-offs

| Left | vs. | Right |
|---|---|---|
| Consistency | vs. | Availability |
| Performance | vs. | Cost |
| Scalability | vs. | Complexity |
| Reliability | vs. | Latency |

---

## Closing Quote

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
