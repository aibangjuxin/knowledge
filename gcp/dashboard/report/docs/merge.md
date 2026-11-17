在Google Looker Studio中，合并相同字段的记录并不是直接支持的功能。不过，你可以通过以下步骤来实现类似的效果：

1. **数据源预处理**：在导入到Looker Studio之前对数据进行预处理，合并相同的时间字段。可以使用Google Sheets、Excel或编写脚本进行处理。

2. **在Google Sheets中合并数据**：
   - 使用Google Sheets（或Excel）将数据导入到一个表格中。
   - 使用以下Google Sheets函数来处理数据：
     - `UNIQUE(range)`：提取唯一值。
     - `ARRAYFORMULA()`：应用数组公式。
     - `JOIN()`：连接字符串。
     - `FILTER()`：过滤数据。

   示例：
   ```plaintext
   A列：日期
   B列：其他字段
   ```

   在新的表格中使用公式：
   ```plaintext
   =UNIQUE(A2:A)
   ```
   然后使用`FILTER`和`JOIN`来合并其他字段：

   ```plaintext
   =ARRAYFORMULA(JOIN(", ", FILTER(B2:B, A2:A = D2)))
   ```

   其中`D2`是唯一日期。

3. **将处理好的数据导入Looker Studio**：
   - 在Google Sheets中处理完数据后，将其作为数据源导入到Looker Studio。
   - 使用新的数据源创建报表。

4. **使用Looker Studio的分组和聚合功能**：
   - 在Looker Studio中，可以使用“维度”和“指标”来进行分组和聚合显示。
   - 选择时间字段作为维度，并对其他字段进行相应的聚合。

### 示例

假设你的原始数据如下：
| 日期       | 数据 |
|------------|------|
| 2024-07-01 | A    |
| 2024-07-01 | B    |
| 2024-07-01 | C    |
| 2024-07-02 | D    |
| 2024-07-02 | E    |

在Google Sheets中进行预处理：
| 日期       | 数据   |
|------------|--------|
| 2024-07-01 | A, B, C |
| 2024-07-02 | D, E   |

将处理好的数据导入Looker Studio，然后使用日期作为维度，数据作为指标进行展示。

通过这种方式，你可以在Looker Studio中实现合并相同字段的效果。