### 提取的信息

命令的功能是从一个 JSON 文件中筛选出特定的项。以下是该命令的分解：

1. **命令格式**:
   ```bash
   cat aibang_apis.json | jq '.[] | select(.name | contains("lex-pa-ri-py-samples"))'
   ```

2. **命令分析**:
   - `cat aibang_apis.json`: 读取名为 `aibang_apis.json` 的文件内容。
   - `| jq`: 使用 `jq` 工具处理 JSON 数据。
   - `'.[] | select(...)'`: 遍历 JSON 数组中的每个对象。
   - `select(.name | contains("lex-pa-ri-py-samples"))`: 筛选出名称 (`name`) 包含指定字符串 `lex-pa-ri-py-samples` 的对象。

### 需要注意的事项

- **JSON 文件格式**: 确保 `aibang_apis.json` 文件格式正确，并是一个有效的 JSON 文件。
- **jq 工具**: 确保安装了 `jq` 工具，以运行此命令。
- **数据处理**: 筛选出的结果会显示所有匹配条件的对象，需确保结果符合预期。
- **字符串匹配**: 可以根据需要更改 `contains` 中的字符串，以匹配其他名称。

### 示例输出

该命令的输出将是所有 `name` 字段中包含 `lex-pa-ri-py-samples` 的 JSON 对象。



- get container name
kubectl get deployment <deployment-name> -o jsonpath="{.spec.template.spec.containers[*].name}"
