
# Query CSV Match
- your-csv-file.csv only contains the API names with their major versions.
    - e.g. api_name_with_major_version = "com.example.api:1.0"
    - load this CSV file into BigQuery as a table named "my_tmp_api_name_table"
    ```bash
    Testing OK 
    bq load --source_format=CSV --skip_leading_rows=1 \
      your-project-id:your-dataset-id.my_tmp_api_name_table \
      your-csv-file.csv

    1. 将 CSV 文件上传到 Google Cloud Storage：确保您的 CSV 文件已经上传到 Google Cloud Storage 中，例如上传到 gs://your-bucket/your-csv-file.csv。
    2. 使用 bq load 命令：打开终端并执行以下命令将数据加载到 my_tmp_api_name_table 表中。

    示例命令

    bq load --source_format=CSV \
    'your-project-id.my_tmp_api_name_table' \
    'gs://your-bucket/your-csv-file.csv' \
    schema_file.json

    参数说明

    • --source_format=CSV：指定源文件格式为 CSV。
    • your-project-id.my_tmp_api_name_table：将 your-project-id 替换为您的实际项目 ID。my_tmp_api_name_table 是您想要加载数据的目标表名。
    • gs://your-bucket/your-csv-file.csv：将 your-bucket 替换为您存储 CSV 文件的桶名称，your-csv-file.csv 是您的 CSV 文件名。
    • schema_file.json：可选项，指定一个包含表 schema（结构）的 JSON 文件。如果您不提供 schema，BigQuery 将根据 CSV 文件的内容自动推断。


    ```
- your_project_id.your_dataset_table contains the API names with their digests, team names, and other metadata.

```shell 
#!/bin/bash
# This script reads a CSV file and matches the values with a SQL query

PROJECT_ID="your-project-id"
DATASET_TABLE="your-dataset-table"
OUTPUT_FILE="output.csv"
# Read the CSV file the values to match line by line
CSV_FILE="your-csv-file.csv"
# Create an empty output file
> $OUTPUT_FILE
while IFS= read -r api_name_with_major_version; do
  # Remove any leading or trailing whitespace
  # echo "Query for $api_name_with_major_version"

  # do the SQL query to match the API name with the major version
  bq query \
    --use_legacy_sql=false "
    SELECT
      DISTINCT
      aibangOrg,
      teamName,
      api_name_with_major_version
      FROM
      \`$PROJECT_ID.$DATASET_TABLE\`
    WHERE
      api_name_with_major_version = '$api_name_with_major_version'
      " >> $OUTPUT_FILE
done < "$CSV_FILE"
```

上面脚本的作用是读取一个CSV文件，逐行读取值，并与SQL查询匹配。
脚本中，需要指定项目ID、数据集表名、CSV文件名。
脚本的核心部分是while循环，读取CSV文件中的每一行，并将其作为SQL查询的WHERE条件。
但是这个效率有些地低，因为每次查询都需要向BigQuery发出请求。如果我把这个CSV文件中的API名称和版本号都存入一个表，然后在BigQuery中建立索引，就可以直接从表中查询。
现在假设我的那个表名字是my_tmp_api_name_table，我拿这个表中的API名称和版本去匹配查询Bigquery中的your-dataset-table,提取出这个API对应的aibangOrg、teamName信息。

我真实的目的是我的my_tmp_api_name_table表缺少字段aibang.org和teamName，我需要拿my_tmp_api_name_table中的api_name_with_major_version信息去匹配your-dataset-table中的信息拿到aibang.org和teamName。然后把这2个信息
更新到my_tmp_api_name_table中。现在假设我直接在bigquery页面去查询了 我已经存在这2个表,想要查询出对应的数据就行 给我对应的SQL

# script join query to update aibangOrg and teamName in my_tmp_api_name_table
为了提高您脚本的效率，您可以在 BigQuery 中直接执行连接查询，而不是逐行查询 CSV 文件的每个 API 名称和版本。这样可以减少与 BigQuery 的交互次数，提高查询速度。以下是一个改进的 Bash 脚本，它一次性从 my_tmp_api_name_table 中提取 API 名称和版本，并与 your-dataset-table 进行连接查询以更新 my_tmp_api_name_table 表中的 aibangOrg 和 teamName 字段。
```shell
#!/bin/bash

PROJECT_ID="your-project-id"
DATASET_TABLE="your-dataset-table"
TMP_API_TABLE="my_tmp_api_name_table"

# 创建更新语句，使用JOIN连接两个表
bq query \
  --use_legacy_sql=false "
  UPDATE
    \`$PROJECT_ID.$TMP_API_TABLE\` AS tmp
  SET
    tmp.aibangOrg = src.aibangOrg,
    tmp.teamName = src.teamName
  FROM (
    SELECT
      api_name_with_major_version,
      aibangOrg,
      teamName
    FROM
      \`$PROJECT_ID.$DATASET_TABLE\`
  ) AS src
  WHERE
    tmp.api_name_with_major_version = src.api_name_with_major_version
  " 

echo "Update completed for aibangOrg and teamName in $TMP_API_TABLE."
```
脚本解释

1. 变量定义：
	• PROJECT_ID、DATASET_TABLE 和 TMP_API_TABLE 分别为您的项目 ID、数据集表名和临时 API 表的名称。
2. 更新查询：
	• 使用 UPDATE 语句来更新 my_tmp_api_name_table 表中的 aibangOrg 和 teamName 字段。
	• 使用 JOIN 将来自 your-dataset-table 表的数据与 my_tmp_api_name_table 中的 api_name_with_major_version 字段匹配。
3. 执行查询：
	• 使用 bq query 命令执行查询并更新表。
4. 完成消息：
	• 在更新完成后，输出一条消息，表明操作已成功完成。

优势

• 这种方法只需一次查询即可更新所有数据，避免了多个 API 调用，提高了效率。
• 通过使用 SQL 连接，您可以确保在表之间一致性和准确性。

注意事项

• 确保在运行此脚本之前，您拥有适当的权限来更新 my_tmp_api_name_table 表及访问 your-dataset-table。
• 在生产环境中执行更新查询之前，请先在测试环境中进行验证，以确保没有不期望的影响。
# BigQuery 连接查询
如果您希望在 BigQuery 页面直接查询并获取 my_tmp_api_name_table 表与 your-dataset-table 表之间的对应数据，可以使用以下 SQL 查询。这段查询会从 your-dataset-table 中提取与 my_tmp_api_name_table 中的 API 名称和版本相匹配的 aibangOrg 和 teamName 信息。
```sql
-- 方法2：直接连接查询 Testing OK 
-- need notice my_tmp_api_name_table need have a api_name_with_major_version OR using `API Name` 
SELECT
  DISTINCT
  tmp.api_name_with_major_version,
  src.aibangOrg,
  src.teamName
FROM
  `your-project-id.my_tmp_api_name_table` AS tmp
LEFT JOIN
  `your-project-id.your-dataset-table` AS src
ON
  tmp.api_name_with_major_version = src.api_name_with_major_version
```
查询解释

1. SELECT 子句：
	• 我们选择 my_tmp_api_name_table 中的 api_name_with_major_version，以及从 your-dataset-table 中提取的 aibangOrg 和 teamName 字段。
2. FROM 子句：
	• 指定查询的主要表，my_tmp_api_name_table。
3. LEFT JOIN 子句：
	• 进行左连接（LEFT JOIN）将 your-dataset-table 与 my_tmp_api_name_table 连接，匹配 api_name_with_major_version 字段。这意味着即使在 your-dataset-table 中找不到匹配项，my_tmp_api_name_table 的所有条目依然会被返回，对于没有匹配的 aibangOrg 和 teamName 则会返回 NULL。
4. ON 子句：
	• 指定连接条件，即匹配两个表中的 api_name_with_major_version 字段。
- last success sql reference
```sql
SELECT
  DISTINCT
-- 因为我想要展示我原表的所有字段，所以下面是*，
  tmp.*,
  src.aibangOrg,
  src.teamName
FROM
  `your-project-id.my_tmp_api_name_table` AS tmp
LEFT JOIN
  `your-project-id.your-dataset-table` AS src
ON
-- 我要求原表里面的条件api_name_with_major_version = src 其实SRC叫做目的表更合适
  tmp.api_name_with_major_version = src.api_name_with_major_version
```
- last success sql reference -- edit 
```sql
SELECT
  DISTINCT
  tmp.*,
  dst.aibangOrg,
  dst.teamName
FROM
  `your-project-id.my_tmp_api_name_table` AS tmp
LEFT JOIN
  `your-project-id.your-dataset-table` AS dst
ON
  tmp.api_name_with_major_version = dst.api_name_with_major_version
```
这个SQL查询的主要目的是从两个表 your-project-id.my_tmp_api_name_table (tmp 别名) 和 your-project-id.your-dataset-table (dst 别名) 中提取数据，并进行左连接（LEFT JOIN）。

解释每个部分：
```bash
SELECT DISTINCT:
这表示查询结果需要去重，避免返回重复的行。
tmp.*:
选择 tmp 表中的所有列。
src.aibangOrg 和 src.teamName:
从查询中推测，这里可能是需要将某些列从别名 src 引入，但在这个SQL中，src 并没有定义。可能是手误，正确的列应该来自 dst 表，因此可以改为 dst.aibangOrg 和 dst.teamName。
FROM your-project-id.my_tmp_api_name_table AS tmp:
指定查询的主表是 my_tmp_api_name_table，并给它一个别名 tmp，方便后续引用。
LEFT JOIN:
将 tmp 表和 dst 表进行左连接。LEFT JOIN 的含义是，即使右边的 dst 表没有匹配的行，也会返回 tmp 表的所有行。
ON tmp.api_name_with_major_version = dst.api_name_with_major_version:
连接条件，表示 tmp 表的 api_name_with_major_version 列要和 dst 表的 api_name_with_major_version 列匹配。
输出结果：
查询返回 tmp 表的所有列以及 dst 表中的 aibangOrg 和 teamName 列。
如果 tmp.api_name_with_major_version 和 dst.api_name_with_major_version 之间有匹配的记录，则会从 dst 表获取 aibangOrg 和 teamName 的值。如果没有匹配，返回 tmp 表的数据，且 dst 表中的列将会是 NULL。
因为使用了 DISTINCT，所以如果有重复的行，将会自动去除。
```
```
执行步骤

1. 登录到 BigQuery 控制台。
2. 打开 SQL 查询编辑器。
3. 将上述 SQL 查询粘贴到编辑器中。
4. 确保将 your-project-id 替换为您的实际项目 ID。
5. 点击执行查询按钮。

这样您就可以获得 my_tmp_api_name_table 中的 API 名称和版本及其对应的 aibangOrg 和 teamName 信息。

# Claude 

```sql 
#方法1：使用CTE去重
WITH deduplicated_dataset AS (
  SELECT DISTINCT
    aibangOrg,
    teamName,
    api_name_with_major_version
  FROM
    `your-project-id.your_dataset_table`
)

SELECT
  t.api_name_with_major_version,
  d.aibangOrg,
  d.teamName
FROM
  `your-project-id.your_dataset.my_tmp_api_name_table` t
LEFT JOIN
  deduplicated_dataset d
ON
  t.api_name_with_major_version = d.api_name_with_major_version
```

# compare the two methods

这个查询与之前提供的查询在逻辑上是等价的。让我为您解释一下这个查询的细节：

查询结构：这是一个标准的LEFT JOIN操作，它将会保留my_tmp_api_name_table中的所有记录，无论是否在your-dataset-table中找到匹配项。
表别名：查询使用了AS tmp和AS src来为两个表分配别名，这使得查询更加清晰和易读。
连接条件：ON子句tmp.api_name_with_major_version = src.api_name_with_major_version确保了基于API名称和主要版本号的正确匹配。
选择的字段：查询选择了临时表中的api_name_with_major_version，以及主表中的aibangOrg和teamName字段，这正是您所需要的信息。

这个查询的主要区别在于它没有使用Common Table Expression (CTE) 来预先去重。这意味着：

如果your-dataset-table中存在重复的api_name_with_major_version记录，这个查询可能会返回重复的结果。
但是，如果your-dataset-table中的api_name_with_major_version是唯一的，或者如果重复记录的aibangOrg和teamName都相同，那么这个查询和之前的查询将产生相同的结果。
这个查询可能会比使用CTE的版本执行得更快，因为它避免了额外的去重步骤。

总的来说，这个查询是有效的，并且在大多数情况下都能正确工作。但是，如果您的数据中可能存在重复，并且这些重复可能导致不一致的结果，那么使用CTE来去重的方法可能更安全。
您可以根据您对数据的了解，以及对性能和结果一致性的需求，来选择使用哪种方法。如果您不确定，可以尝试运行两种查询，并比较它们的结果和性能。




更好的方法是使用BigQuery的内置函数REGEXP_EXTRACT()，可以直接从CSV文件中提取出API名称和版本号，然后直接在BigQuery中进行匹配。

下面是修改后的脚本：
```shell
#!/bin/bash
# This script reads a CSV file and matches the values with a SQL query

PROJECT_ID="your-project-id"
DATASET_TABLE="your-dataset-table"
# Read the CSV file the values to match line by line
CSV_FILE="your-csv-file.csv"
while IFS= read -r api_name_with_major_version; do
  # Remove any leading or trailing whitespace
  api_name=$(echo "$api_name_with_major_version" | awk -F'-' '{print $1}')
  major_version=$(echo "$api_name_with_major_version" | awk -F'-' '{print $2}')
  # echo "Query for $api_name_with_major_version"

  # do the SQL query to match the API name with the major version
  bq query \
    --use_legacy_sql=false "
    SELECT
      DISTINCT
      aibangOrg,
      teamName,
      api_name_with_major_version
      FROM
      \`$PROJECT_ID.$DATASET_TABLE\`
    WHERE
      REGEXP_EXTRACT(api_name_with_major_version, r'^\w+-v\d+$') = '$api_name-v$major_version'
      "
done < "$CSV_FILE"

```
这个脚本的核心部分是使用awk命令从CSV文件中提取出API名称和版本号，然后使用REGEXP_EXTRACT()函数进行匹配。
REGEXP_EXTRACT()函数可以直接从字符串中提取出符合正则表达式的子串，并返回匹配的结果。

这样，脚本的效率可以得到大幅提升。



