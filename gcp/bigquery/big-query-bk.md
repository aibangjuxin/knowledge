为了备份 Google BigQuery 数据集，可以使用多种方法。这里我会给出一个完整的备份方案，包括可能涉及的步骤和命令。

### 方案概述

1. **导出数据到Google Cloud Storage (GCS)**
2. **将导出的数据从GCS下载到本地或其他存储**
3. **定期自动化备份**

### 详细步骤

#### 1. 导出数据到Google Cloud Storage (GCS)

首先，我们需要将BigQuery的数据导出到GCS。可以使用BigQuery命令行工具 (`bq`) 或者 BigQuery API 来执行这一步。

**使用bq命令行工具：**

```bash
bq extract --destination_format=CSV 'project_id:dataset.table' gs://your_bucket/backup_filename.csv
```

**使用Python客户端库：**

```python
from google.cloud import bigquery
import datetime

# 创建BigQuery客户端
client = bigquery.Client()

# 设置目标表
project = 'your_project_id'
dataset_id = 'your_dataset_id'
table_id = 'your_table_id'
table_ref = client.dataset(dataset_id).table(table_id)

# 设置导出配置
destination_uri = 'gs://your_bucket/backup_filename.csv'
extract_job = client.extract_table(
    table_ref,
    destination_uri,
    # 可选参数
    location='US'  # 项目位置
)

# 等待作业完成
extract_job.result()
print("导出完成")
```

#### 2. 将导出的数据从GCS下载到本地或其他存储

**使用gsutil命令行工具：**

```bash
gsutil cp gs://your_bucket/backup_filename.csv /local/directory/backup_filename.csv
```

#### 3. 定期自动化备份

为了实现定期备份，可以使用以下方法：

- **使用Cloud Scheduler和Cloud Functions：** 设置一个定时任务触发Cloud Function来执行备份。
- **使用本地脚本和cron jobs：** 本地服务器上的cron job来定期运行备份脚本。

**示例：使用Cloud Scheduler和Cloud Functions**

1. **创建Cloud Function**

```python
import google.auth
from google.cloud import bigquery
from google.cloud import storage

def backup_bigquery_data(event, context):
    credentials, project = google.auth.default()
    client = bigquery.Client(credentials=credentials, project=project)

    dataset_id = 'your_dataset_id'
    table_id = 'your_table_id'
    destination_uri = 'gs://your_bucket/backup_filename_{}.csv'.format(datetime.datetime.now().strftime("%Y%m%d%H%M%S"))

    table_ref = client.dataset(dataset_id).table(table_id)
    extract_job = client.extract_table(table_ref, destination_uri)

    extract_job.result()
    print('Backup completed to {}'.format(destination_uri))
```

2. **部署Cloud Function**

```bash
gcloud functions deploy backup_bigquery_data --runtime python39 --trigger-http --allow-unauthenticated
```

3. **设置Cloud Scheduler**

```bash
gcloud scheduler jobs create http bigquery-backup-job --schedule="0 2 * * *" \
  --uri=https://REGION-PROJECT_ID.cloudfunctions.net/backup_bigquery_data \
  --http-method=GET
```

### 总结

这个备份方案通过导出BigQuery数据到GCS并定期执行自动化备份，确保数据的安全性和可用性。你可以根据具体需求调整脚本和配置。希望这个方案能帮到你！💡