当然可以，下面是一个英文版的内部分享 Story，围绕 Resilience Uplift 主题，总结你今年在平台层面上的关键改进工作。内容重点突出架构增强、故障容忍、服务保护、流量控制和安全强化：

⸻


## 🌟 2025 Platform Resilience Uplift - Internal Engineering Story

### Background

In 2025, our platform team set a clear goal: **improve the resilience, availability, and operational robustness of our cloud-native API platform**. Over the past few months, we've executed a series of architectural and infrastructure improvements to strengthen our services and prepare for scale and unpredictable failures.

This is a summary of key initiatives we delivered in the **resilience uplift effort**, especially in GKE and GCP environments.

---

### Key Improvements

#### 🧠 Smarter Pod Scheduling with Affinity & Anti-Affinity

We introduced **pod affinity and anti-affinity rules** to control workload distribution across nodes and zones. This prevents noisy neighbor effects and ensures our critical services aren't colocated, reducing blast radius during node failures.

- Enabled **zone-level spreading** to improve multi-zone redundancy.
- Applied **anti-affinity for key workloads** (e.g., gateway, runtime services) to avoid cascading failure.

#### ⛑️ Safer Upgrades with PodDisruptionBudgets (PDB)

To ensure **zero-downtime rolling updates**, especially during GKE upgrades and maintenance windows, we standardized the use of **PodDisruptionBudgets** across services.

- Prevented **simultaneous eviction of all pods**.
- Reduced **incidents caused by aggressive scaling or maintenance events**.

#### 🌐 GKE Gateway Migration + Traffic Control

We completed a successful **migration to GKE Gateway API**, unlocking better control over HTTP(S) routing and traffic splitting:

- Implemented **HTTPRoute-based canary rollouts** and **blue-green strategies**.
- Enabled **per-path routing**, making multi-tenant support simpler.
- Introduced **weighted traffic control** to route percentage-based traffic for gradual releases.

#### 🛡️ Security Hardening with Cloud Armor

To enhance protection against L7 attacks and bad bots, we fully **integrated Google Cloud Armor** with our external HTTP(S) Load Balancer.

- Deployed **pre-configured WAF rules** (e.g., SQLi/XSS).
- Implemented **custom allow/deny IP lists** for trusted zones.
- Enabled **per-path security policies** for sensitive endpoints.

#### 🔐 End-to-End MTLS with Google Certificate Manager

Security and client authentication were a major focus. We introduced **HTTPS-based mTLS at the global load balancer layer**:

- Used **Google Certificate Manager** and **TrustConfig** to manage multiple client CA certs.
- Built a **centralized onboarding and fingerprint validation flow** using GCS + JSON definitions.
- Ensured **TLS termination at the edge**, while maintaining **client identity verification** with backend forwarding headers.

#### 📊 Resilience Validation & Monitoring

- Applied **stress testing and fault injection** on Gateway and Runtime pods.
- Integrated **load spike simulation** to validate PDB, readinessProbe, and HPA behaviors.
- Improved **BigQuery + Looker dashboards** to analyze error rates, disruptions, and retries across environments.

---

### Results

| Metric                     | Before Uplift     | After Uplift       |
|---------------------------|-------------------|--------------------|
| Zero-downtime upgrades    | Inconsistent       | Achieved via PDB   |
| External attack tolerance | Partial WAF rules | Full Armor + mTLS  |
| Canary rollout capability | Limited            | HTTPRoute-enabled  |
| Zone-level resilience     | Minimal            | Affinity-aware     |

---

### Next Steps

Looking forward to H2 2025, we plan to continue building on this foundation by:

- Introducing **auto fallback routing** across clusters.
- Enhancing **Service Mesh (e.g., Istio or Anthos Service Mesh)** observability.
- Implementing **automatic policy testing pipelines** for Armor and Gateway.

---

### Thank Y
