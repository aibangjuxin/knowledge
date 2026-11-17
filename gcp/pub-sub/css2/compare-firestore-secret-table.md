# Firestore vs Secret Manager Cost Comparison Table

## 1. Unit Pricing Comparison

| Cost Component | Cloud Firestore (Multi-Region) | Secret Manager |
| :--- | :--- | :--- |
| **Storage / Active Item** | **$0.18** / GB / month | **$0.06** / secret version / location / month |
| **Read / Access Operation** | **$0.06** / 100,000 reads | **$0.03** / 10,000 operations |
| **Write / Management** | **$0.18** / 100,000 writes | **Free** (Management operations) |
| **Free Tier** | 50k reads, 20k writes per day<br>1 GB storage | 6 active versions<br>10k access operations |

> **Note**: Firestore reads are significantly cheaper per unit (approx. **50x cheaper** for raw access count: $0.0000006 vs $0.000003 per op).

---

## 2. Monthly Scenario Cost Analysis

**Scenario Basis**: Storing credentials for Cloud Scheduler jobs.
*   **Active Secrets**: Number of unique team credentials stored.
*   **Monthly Accesses**: Total times scheduler jobs fetch credentials.

| Usage Level | Metrics | Firestore Cost | Secret Manager Cost | Cost Difference |
| :--- | :--- | :--- | :--- | :--- |
| **Low** | **100** Secrets<br>**30k** Accesses/mo | **$0.00**<br>*(Free Tier)* | **$6.09**<br>*($6.00 fixed + $0.09 ops)* | **+$6.09** |
| **Medium** | **500** Secrets<br>**300k** Accesses/mo | **$0.18**<br>*($0.18 ops + ~$0 storage)* | **$30.90**<br>*($30.00 fixed + $0.90 ops)* | **+$30.72** |
| **High** | **1,000** Secrets<br>**1.5M** Accesses/mo | **$0.90**<br>*($0.90 ops + ~$0.10 storage)* | **$64.50**<br>*($60.00 fixed + $4.50 ops)* | **+$63.60** |

---

## 3. Recommendation Summary

| Feature | Firestore | Secret Manager | Decision Guide |
| :--- | :--- | :--- | :--- |
| **Cost Efficiency** | ✅ **Excellent** | ⚠️ Higher | Choose **Firestore** if budget is the main constraint. |
| **Security** | ⚠️ Basic (ACLs) | ✅ **Advanced** | Choose **Secret Manager** for rotation, versioning, and strict IAM. |
| **Performance** | ✅ Low Latency | ✅ Low Latency | Comparable for typical read operations. |
| **Ops Overhead** | ⚠️ Manual Encryption | ✅ Native | **Secret Manager** reduces dev effort for secure handling. |

## 4. References

*   **Google Cloud Firestore Pricing**: [https://cloud.google.com/firestore/pricing](https://cloud.google.com/firestore/pricing)
*   **Google Cloud Secret Manager Pricing**: [https://cloud.google.com/secret-manager/pricing](https://cloud.google.com/secret-manager/pricing)
