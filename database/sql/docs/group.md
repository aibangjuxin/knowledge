由于我无法直接创建或输出文档，但我可以在这里提供一个关于`GROUP BY`详细用法和示例的文本，您可以将其复制并粘贴到您选择的文档编辑器中，然后保存为所需的文档格式。

---

# GROUP BY 子句的详细用法及示例

`GROUP BY`子句是SQL语言中用于结合聚合函数（如SUM, COUNT, AVG等）对结果集进行分组的一种机制。它可以按照一个或多个列的值对数据集进行分组，以便对每个组执行特定的计算。

## 基本用法

`GROUP BY`子句的基本语法如下：

```sql
SELECT column1, aggregate_function(column2)
FROM table_name
GROUP BY column1;
```

这里，`column1`是用于分组的列，`aggregate_function(column2)`是在每个分组上执行的聚合函数。

## 单列分组

#### 示例 1：计算销售数量

假设有一个`sales`表，包含`product_id`和`quantity`两列，要计算每种产品的销售数量：

```sql
SELECT product_id, COUNT(quantity) AS total_quantity
FROM sales
GROUP BY product_id;
```

## 多列分组

#### 示例 2：按地区和产品分类销售

如果`sales`表还包含`region`列，并且你想按地区和产品分类来查看销售情况：

```sql
SELECT region, product_id, SUM(quantity) AS total_sales
FROM sales
GROUP BY region, product_id;
```

## 带有条件的分组

#### 示例 3：筛选特定条件下的分组

如果你只想看到销售额超过一定数额的分组：

```sql
SELECT region, product_id, SUM(quantity) AS total_sales
FROM sales
GROUP BY region, product_id
HAVING SUM(quantity) > 100;
```

## 排序分组结果

#### 示例 4：按销售额降序排列

如果你想对上面的结果按销售额降序排列：

```sql
SELECT region, product_id, SUM(quantity) AS total_sales
FROM sales
GROUP BY region, product_id
HAVING SUM(quantity) > 100
ORDER BY total_sales DESC;
```

## 使用`ROLLUP`进行分组

#### 示例 5：使用`ROLLUP`获取多层次的汇总

如果你想要获取按年份和月份分组的销售数据，并且同时获取年份总和和月份总和：

```sql
SELECT YEAR(sale_date) AS sale_year, MONTH(sale_date) AS sale_month, SUM(quantity) AS total_sales
FROM sales
GROUP BY ROLLUP(YEAR(sale_date), MONTH(sale_date));
```

## 注意事项

- `GROUP BY`子句中的列必须在`SELECT`语句中出现，除非它们是通过聚合函数引用的。
- 如果`SELECT`语句中包含了非聚合列，而这些列没有在`GROUP BY`子句中列出，那么执行查询时会出现错误。
- `GROUP BY`子句可以与`HAVING`子句结合使用，以便在分组后对数据进行条件过滤。

---

请将上述内容复制到您的文档编辑器中，并根据需要进行格式调整和保存。如果您需要进一步的帮助，请告诉我。