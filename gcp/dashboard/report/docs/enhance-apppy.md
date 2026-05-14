# Q
我现在有这样一个问题，我有一个app.py的Python的脚本。
大概步骤如下：
1 定义表结构模式
2 从GCS加载数据到对应的Bigquery
大概的问题是如果我加载数据到Bigquery有2个办法一个是
WriteDisposition.Write_TRUNCATE 或者APPEND
如果是TRUNCATE我想打印load多个表的时候，比如直接走*gke_pod_data.json效率会提升插入表的效率。但是会缺失一些日志，比如我还想看到都load进去了那些数据

如果我走APPEND的方式，那么我需要考虑在循环的过程中逐个追加数据进去，但是首先要清理一次Bigquery的表
好处是这样可以打印每个日志
缺点是可能会引起Bigquery的Limit问题。因为每个都循环插入会引起google.api_core.exception.forbidden:403 Exceeded rate limits: too many table update operations for this table.

那么关于这个app.py有什么好的解决办法？或者解决方案
我要考虑日志和考虑执行的效率还不要Trigger这个limit的告警

# A
针对你的需求，有几种优化方案可以考虑，既能提升效率，又能避免触发BigQuery的限制，同时也能记录每次加载的日志。

### 1. **批量插入 + 日志记录**
   - **批量插入**：可以考虑将多个数据文件合并为一个文件或批量处理数据，以减少插入次数，从而降低触发BigQuery限制的风险。
   - **日志记录**：在进行批量插入后，可以通过查询BigQuery表的记录数或其他标识字段，来确认哪些数据已成功加载，并记录这些信息到日志中。

### 2. **分区表（Partitioned Tables）**
   - **分区表的好处**：将数据加载到分区表中，可以有效地将数据按时间或其他字段进行分割，这样即使使用`APPEND`方式，也能减少每次插入的数据量，从而减少触发限制的可能性。
   - **日志记录**：你可以在每个分区插入完成后，查询分区的数据量，并将结果写入日志。

### 3. **结合TRUNCATE和APPEND**
   - **预处理步骤**：首先使用`TRUNCATE`方式清空目标表，然后再使用`APPEND`方式逐步插入数据。这可以确保表的清理是一次性的，避免在循环中反复操作，减少触发限制的风险。
   - **日志记录**：在每次插入后，检查表的状态并记录相应的日志。

### 4. **使用BigQuery的批量加载功能**
   - **Job配置**：BigQuery提供的批量加载功能可以让你将多个数据文件以更高效的方式加载到表中。通过配置`Job`选项，可以确保在加载数据的同时记录详细的加载日志。
   - **日志记录**：可以通过捕获每个`Job`的输出结果，来跟踪数据加载情况，并记录到日志文件中。

### 5. **重试逻辑 + 限速**
   - **重试机制**：在你的脚本中实现一个简单的重试机制，当检测到`403 Exceeded rate limits`异常时，脚本可以等待一段时间后再进行下一次操作，以避免持续触发限制。
   - **限速机制**：通过在脚本中加入限速逻辑，控制每秒的表更新次数，降低触发限制的风险。

### 代码示例：
```python
from google.cloud import bigquery
import time

def load_data_to_bigquery(client, dataset_id, table_id, source_uri, write_disposition):
    table_ref = client.dataset(dataset_id).table(table_id)
    job_config = bigquery.LoadJobConfig()
    job_config.source_format = bigquery.SourceFormat.NEWLINE_DELIMITED_JSON
    job_config.write_disposition = write_disposition
    
    load_job = client.load_table_from_uri(
        source_uri,
        table_ref,
        job_config=job_config,
    )

    try:
        load_job.result()  # Wait for the job to complete.
        print(f"Loaded {load_job.output_rows} rows into {dataset_id}:{table_id}.")
    except google.api_core.exceptions.GoogleAPICallError as e:
        print(f"Error loading data: {e}")
        if "Exceeded rate limits" in str(e):
            print("Rate limit exceeded, retrying after 60 seconds...")
            time.sleep(60)
            load_data_to_bigquery(client, dataset_id, table_id, source_uri, write_disposition)

# Initialize BigQuery client
client = bigquery.Client()

# Example usage
load_data_to_bigquery(client, 'your_dataset_id', 'your_table_id', 'gs://your_bucket/gke_pod_data.json', bigquery.WriteDisposition.WRITE_APPEND)
```

### 总结
可以结合批量加载、分区表、重试机制和限速等方式，既提高数据加载效率，又确保日志记录的完整性，避免触发BigQuery的限制。

你可以根据自己的具体需求选择和调整这些方法。

考虑到您的需求和问题,我提供以下建议:

1. **使用批量写入方式**:
   - 使用 `client.insert_rows_json` 方法,将多个JSON文件的数据合并为一个大列表,然后一次性写入到BigQuery表中。
   - 这种方式可以减少API调用次数,提高效率,同时也可以避免触发写入限制。
   - 您可以设置一个合理的批量大小,例如每1000条记录或每1MB数据作为一个批次进行写入。

2. **使用流式写入方式**:
   - 利用 `client.create_stream` 方法创建一个流式写入器。
   - 通过流式写入器的 `insert_data` 方法逐条写入数据。
   - 这种方式可以实时查看写入情况,但可能会受到吞吐量限制。
   - 您可以设置一个合理的写入速率,例如每秒写入1000条记录。

3. **使用WriteDisposition.WRITE_APPEND模式**:
   - 在写入之前,先使用 `client.delete_table` 方法删除原表。
   - 然后使用 `client.load_table_from_json` 方法,将JSON文件数据写入新表,设置 `write_disposition=BigQueryWriteDisposition.WRITE_APPEND`。
   - 这种方式可以保留原有数据,同时也可以打印写入日志。
   - 注意,如果数据量较大,删除和重建表的操作可能会比较耗时。

4. **使用分区表**:
   - 如果您的数据是按天或其他时间维度分割的,可以考虑使用分区表。
   - 在写入数据时,指定分区维度,数据会自动写入对应的分区。
   - 这种方式可以避免全表扫描,提高查询效率。同时也不会触发写入限制。

5. **优化日志输出**:
   - 在批量写入或流式写入时,可以每隔一段时间(例如每1000条记录)输出一次日志,而不是每条记录都输出。
   - 这样可以减少不必要的日志输出,提高效率。

综上所述,建议您先尝试使用批量写入或流式写入的方式,结合适当的日志输出频率。如果情况允许,也可以考虑使用分区表。同时,您需要根据数据量和写入频率,适当调整批量大小或写入速率,以避免触发写入限制。

# client.insert_rows_json
当然,我会详细介绍如何使用 `client.insert_rows_json` 方法将多个 JSON 文件合并后一次性写入到 BigQuery 表中。

首先,我们需要从 Google Cloud Storage 获取所有 JSON 文件的路径。以下代码可以帮助您获取指定前缀的所有文件路径:

```python
from google.cloud import storage

def get_json_file_paths(bucket_name, prefix):
    """
    获取 Google Cloud Storage 桶中指定前缀的所有 JSON 文件路径
    """
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob_list = list(bucket.list_blobs(prefix=prefix))
    file_paths = [f"gs://{bucket_name}/{blob.name}" for blob in blob_list if blob.name.endswith(".json")]
    return file_paths
```

接下来,我们需要从这些 JSON 文件中读取数据,并将它们合并为一个大列表。以下代码可以帮助您完成这个任务:

```python
from google.cloud import bigquery

def load_json_data(file_paths):
    """
    从 JSON 文件路径中读取数据,并合并为一个列表
    """
    json_data = []
    for file_path in file_paths:
        with open(file_path, "r") as f:
            json_data.extend(json.load(f))
    return json_data
```

最后,我们可以使用 `client.insert_rows_json` 方法将合并后的数据一次性写入到 BigQuery 表中。以下代码展示了如何完成这个操作:

```python
from google.cloud import bigquery

def load_data_to_bigquery(json_data, dataset_id, table_id):
    """
    将 JSON 数据写入到 BigQuery 表中
    """
    client = bigquery.Client()
    table_ref = client.dataset(dataset_id).table(table_id)
    table = client.get_table(table_ref)
    errors = client.insert_rows_json(json_data, table)
    if not errors:
        print(f"Data inserted successfully into {table_id}")
    else:
        print(f"Encountered errors while inserting data: {errors}")
```

把这些代码片段组合起来,您可以按照以下步骤操作:

1. 使用 `get_json_file_paths` 函数获取 Google Cloud Storage 桶中所有 JSON 文件的路径。
2. 使用 `load_json_data` 函数从这些文件路径中读取数据,并将它们合并为一个列表。
3. 使用 `load_data_to_bigquery` 函数将合并后的数据一次性写入到 BigQuery 表中。

下面是一个完整的示例代码:

```python
bucket_name = "your-bucket-name"
prefix = "path/to/json/files/"
dataset_id = "your-dataset-id"
table_id = "your-table-id"

# 获取 JSON 文件路径
file_paths = get_json_file_paths(bucket_name, prefix)

# 从 JSON 文件中读取数据并合并
json_data = load_json_data(file_paths)

# 将数据写入到 BigQuery 表中
load_data_to_bigquery(json_data, dataset_id, table_id)
```

使用这种方式,您可以一次性将多个 JSON 文件的数据合并并写入到 BigQuery 表中,从而提高写入效率并避免触发写入限制。同时,您也可以根据需要调整批量大小,以获得最佳性能。


