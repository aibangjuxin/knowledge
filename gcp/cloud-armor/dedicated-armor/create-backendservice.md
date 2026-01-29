
```bash
# 验证通过：可以在一条命令中完成绝大部分配置
gcloud compute backend-services create bs-api-a-v1 \
    --global \
    --protocol=HTTP \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --health-checks=hc-nginx-http \
    --timeout=30s \
    --enable-logging \
    --logging-sample-rate=1.0 \
    --logging-optional-mode=exclude-all-optional \
    --custom-response-header="X-API-Name: api-a-v1" \
    --no-iap
```

gcloud 参数

| gcloud | gcp api |
|---|---|
| --enable-logging | logConfig.enable = true |
| --logging-sample-rate=1.0 | sampleRate = 1.0 |
| --logging-optional-mode=EXCLUDE_ALL_OPTIONAL | optionalMode = EXCLUDE_ALL_OPTIONAL |
