在 Google Cloud Platform (GCP) 中，你可以使用以下命令来查看防火墙规则的命中情况：

1. 查看所有防火墙规则的命中计数：
```bash
gcloud compute firewall-rules list --format="table(name,direction,priority,hitCounts.day().sum():label=HITS_IN_LAST_DAY)"
```

2. 查看特定防火墙规则的命中计数：
```bash
gcloud compute firewall-rules describe FIREWALL_RULE_NAME --format="table(name,direction,priority,hitCounts.day().sum():label=HITS_IN_LAST_DAY)"
```

3. 启用防火墙规则的日志记录（如果还没启用）：
```bash
gcloud compute firewall-rules update FIREWALL_RULE_NAME --enable-logging
```

4. 查看最近 7 天的命中统计：
```bash
gcloud compute firewall-rules describe FIREWALL_RULE_NAME \
    --format="table(
        name,
        hitCounts.week().sum():label=HITS_IN_LAST_WEEK,
        hitCounts.day().sum():label=HITS_IN_LAST_DAY
    )"
```

注意事项：
1. 需要先启用防火墙规则的日志记录才能看到命中统计
2. 统计数据可能有几分钟的延迟
3. 可以在 GCP Console 的 VPC 网络 -> 防火墙规则中也能看到图形化的命中统计

如果你想要更详细的日志分析，可以：
1. 在 Cloud Logging 中查看防火墙日志
2. 使用以下命令查看防火墙日志：
```bash
gcloud logging read "resource.type=gce_firewall_rule AND resource.labels.firewall_rule_name=FIREWALL_RULE_NAME" --limit=10
```