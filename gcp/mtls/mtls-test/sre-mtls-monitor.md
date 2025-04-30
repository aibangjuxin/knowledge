# SRE Monitoring Strategy for TCP MTLS to HTTPS MTLS GLB Migration

When migrating from TCP MTLS to HTTPS MTLS GLB, once the deployment is complete, you need a comprehensive monitoring and alerting strategy to help SRE teams detect configuration errors, certificate expiration, service unavailability, and other issues early.

⸻

✅ Core Monitoring Recommendations (By Component)

1. Certificate Manager / Trust Config
   • Certificate Expiration Monitoring (Critical):
   • Monitor all deployed SSL certificates and CA root certificates referenced by TrustConfig for upcoming expiration.
   • Set up alerts 30 days, 15 days, and 7 days before expiration.
   • TrustConfig Reference Validation Monitoring:
   • Check if TrustConfig references any deleted or "invalid" status CAs.
   • Certificate Binding Status Monitoring:
   • Monitor if any GLB backend or HTTPS listener is in error state due to unsuccessful certificate binding.

⸻

2. GLB / Backend Service
   • HTTPS 5xx Error Rate Monitoring:
   • If backend services return a large number of 502/503/504 errors, it may be due to Nginx failure or MTLS handshake issues.
   • Set up baseline alerts (e.g., error rate > 5%).
   • TLS Handshake Failure Statistics (from Load Balancer):
   • Check GCP Load Balancer metrics such as handshake_failure, client_certificate_required, etc.
   • Implement using Cloud Logging / Cloud Monitoring metrics.

⸻

3. Nginx and components MIG verify
   1. nginx
      • Configuration Hot Reload Failure Monitoring:
      • Monitor Nginx reload logs for keywords like "invalid config", "failed to reload", "SSL error", etc.
      • Implement using promtail + Loki or Fluentd + GKE Stackdriver Logging.
      • Certificate Loading Failure:
      • Nginx will report errors for certificate path or permission issues, monitor error logs.
      • MTLS Verification Failure Log Count:
      • Custom metric to count logs with messages like "peer did not return a certificate".
   2. components MIG verify Steps:
      1. Verify that the instance template includes the correct startup scripts, certificates, and Nginx configuration.
      2. Use gcloud compute instance-groups list-instances to confirm the MIG is running the expected number of healthy instances.
      3. Simulate load (e.g., using ab, wrk, or locust) to trigger auto-scaling.
      4. Monitor whether new instances are automatically created and successfully register as healthy.
      5. Simulate instance failure (e.g., shutdown or high CPU) and confirm that MIG replaces or scales down appropriately.
      6. Check Stackdriver Monitoring/Cloud Monitoring for autoscaling logs, health checks, and error alerts.

⸻

4. Cloud Armor
   • Rule Matching Monitoring:
   • If Cloud Armor is enabled, monitor for legitimate requests being incorrectly blocked.
   • Observe if rule hit frequency is abnormal (sudden increase or no hits at all).

⸻

5. End-to-End Health and Availability
   • Black Box Testing (Synthetic Check):
   • Use curl or custom probes to simulate clients, make MTLS API calls, and continuously check availability.
   • Implement using Cloud Scheduler + Cloud Function.
   • SLO / Availability Metrics:
   • Define SLOs, such as "99.9% of HTTPS requests successful", and set up error budget alerts with Cloud Monitoring.

⸻

🔁 Recommended Automated Checks (Daily / Hourly)
• gcloud certificate-manager certificates list → Automatically check certificate expiration
• gcloud certificate-manager trust-configs describe → Verify trust chain integrity
• nginx -t to automatically validate configuration file validity (integrated with CI/CD pipeline)
• Check Nginx logs for keywords like "SSL: certificate verify failed"

⸻

These monitoring items can help SRE teams quickly identify issues in the HTTPS MTLS chain and provide early warnings to prevent service disruptions.

⸻

当我们从 TCP MTLS 到 HTTPS MTLS GLB 的迁移，一旦完成发布，你确实需要一套监控与预警策略，以便 SRE 可以及早发现配置错误、证书过期、服务不可用等问题。

⸻

✅ 核心监控建议（按组件分类）

1. Certificate Manager / Trust Config
   • 证书有效期监控（关键）：
   • 监控所有已部署的 SSL 证书、TrustConfig 所引用的 CA 根证书是否即将过期。
   • 设置提前 30 天、15 天、7 天预警。
   • TrustConfig 引用失效监控：
   • 检查 TrustConfig 是否引用了已被删除或状态为"invalid"的 CA。
   • 证书绑定状态监控：
   • 监控是否有 GLB backend 或 HTTPS listener 因证书未绑定成功而处于错误状态。

⸻

2. GLB / Backend Service
   • HTTPS 5xx 错误率监控：
   • 若后端服务返回大量 502 / 503 / 504，可能是由于 Nginx 失败或 MTLS 握手异常。
   • 可以设置基线（如错误率 > 5%）报警。
   • TLS 握手失败统计（来自 Load Balancer）：
   • 查看 GCP Load Balancer 的 handshake_failure、client_certificate_required 等指标。
   • 可以用 Cloud Logging / Cloud Monitoring metrics 实现。

⸻

3. Nginx
   • 配置热加载失败监控：
   • 监控 Nginx reload 时日志中是否包含 invalid config, failed to reload, SSL error 等关键字。
   • 使用 promtail + Loki 或 Fluentd + GKE Stackdriver Logging 可实现。
   • 证书加载失败：
   • 如证书路径、权限异常等，Nginx 会报错，需监控 error log。
   • MTLS 验证失败日志计数：
   • 自定义 metric 统计类似 peer did not return a certificate 日志计数。

⸻

4. Cloud Armor
   • 规则匹配情况监控：
   • 若启用了 Cloud Armor，监控是否误拦合法请求。
   • 观察规则命中频率是否异常（如突增或完全没有命中）。

⸻

5. instance group 和 instance 状态检查

6. 全链路健康与可用性
   • 黑盒探测（Synthetic Check）：
   • 用 curl 或自定义探测器模拟客户端，通过 MTLS 调用接口，持续检查是否可用。
   • 可以结合 Cloud Scheduler + Cloud Function 实现。
   • SLO / 可用性指标：
   • 定义 SLO，例如"99.9% 的 HTTPS 请求成功"，并配合 Cloud Monitoring 设置 error budget 报警。

⸻

🔁 建议的自动化检查（每日 / 每小时）
• gcloud certificate-manager certificates list → 自动检查证书有效期
• gcloud certificate-manager trust-configs describe → 检查 trust 链完整性
• nginx -t 自动验证配置文件合法性（结合 CI/CD pipeline）
• Nginx 日志中是否有 SSL: certificate verify failed 等关键字

⸻

这些监控项可以帮助 SRE 快速定位 HTTPS MTLS 链路上的问题，同时也能提供预警信息避免中断。
