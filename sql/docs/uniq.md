在SQL中，`UNION` 操作符用于合并两个或多个 `SELECT` 语句的结果集，生成一个统一的结果集。使用 `UNION` 时，请注意以下几点：

1. **选择列表**：使用 `UNION` 的所有 `SELECT` 语句必须具有相同的列数，并且相应的列也必须具有兼容的数据类型。

2. **列顺序**：列的顺序在每个 `SELECT` 语句中可以不同，但列的数据类型必须兼容。

3. **列名**：默认情况下，`UNION` 操作符不会重复列名。结果集中的列名是第一个 `SELECT` 语句的列名。

4. **排序**：`UNION` 默认不会对结果集进行排序。如果你需要排序结果，可以使用 `ORDER BY` 子句，但必须将其放在 `UNION` 操作符之后。

5. **去重**：`UNION` 操作符会自动去除重复的行。如果你想要包含重复行，可以使用 `UNION ALL`。

6. **NULL 值**：`UNION` 操作符会将 `NULL` 值视为不同的值。

下面是一个 `UNION` 的基本示例：

```sql
SELECT column1, column2 FROM table1
UNION
SELECT column1, column2 FROM table2;
```

这个示例将从 `table1` 和 `table2` 中选择 `column1` 和 `column2`，并将结果合并为一个结果集，自动去除重复的行。

如果你想要包含重复的行，可以使用 `UNION ALL`：

```sql
SELECT column1, column2 FROM table1
UNION ALL
SELECT column1, column2 FROM table2;
```

此外，如果你需要对结果集进行排序，可以添加 `ORDER BY` 子句：

```sql
SELECT column1, column2 FROM table1
UNION
SELECT column1, column2 FROM table2
ORDER BY column1;
```

这将合并两个表的结果，并按照 `column1` 的值进行排序。记住，`ORDER BY` 只能出现在最后一个 `SELECT` 语句之后。