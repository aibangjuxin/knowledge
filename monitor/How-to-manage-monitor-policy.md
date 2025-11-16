- [ ] gcloud alpha monitoring policies

-  通过 gcloud CLI 配置
```bash
cat > squid-disk-alert-policy.yaml <<'EOF'
displayName: "Squid Proxy MIG - Disk Usage Alert"
documentation:
  content: "磁盘使用率超过 85%，请参考 gce-disk-analyze.md 执行 MIG Recreate 操作"
  mimeType: "text/markdown"

conditions:
  - displayName: "Disk usage above 85% for 5 minutes"
    conditionThreshold:
      filter: |
        resource.type = "gce_instance"
        AND resource.labels.instance_group = "YOUR_MIG_NAME"
        AND metric.type = "agent.googleapis.com/disk/percent_used"
      comparison: COMPARISON_GT
      thresholdValue: 85
      duration: 300s
      aggregations:
        - alignmentPeriod: 60s
          perSeriesAligner: ALIGN_MEAN

notificationChannels:
  - projects/YOUR_PROJECT_ID/notificationChannels/YOUR_CHANNEL_ID

alertStrategy:
  autoClose: 604800s  # 7 天后自动关闭
  notificationRateLimit:
    period: 3600s  # 每小时最多发送一次通知
EOF
```