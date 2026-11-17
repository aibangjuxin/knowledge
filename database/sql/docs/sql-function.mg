以下为您介绍一些常见的 SQL 函数及其使用方法：

1. SUM() 函数：用于计算指定列的总和。
示例：SELECT SUM(sales) FROM orders;  （计算 sales 列的总和）

2. AVG() 函数：用于计算指定列的平均值。
示例：SELECT AVG(price) FROM products;  （计算 price 列的平均值）

3. COUNT() 函数：用于计算行数。
示例：

• SELECT COUNT(*) FROM customers;  （计算表中的总行数）

• SELECT COUNT(customer_id) FROM customers;  （计算 customer_id 列不为 NULL 的行数）

4. MIN() 函数：用于获取指定列的最小值。
示例：SELECT MIN(age) FROM employees;  （获取 age 列的最小值）

5. MAX() 函数：用于获取指定列的最大值。
示例：SELECT MAX(salary) FROM staff;  （获取 salary 列的最大值）

6. DATE() 函数：用于从日期/时间表达式中提取日期部分。

示例：SELECT DATE(order_date) FROM orders;  （从 order_date 列中提取日期部分）

7. YEAR() 函数：用于从日期/时间表达式中提取年份。
示例：SELECT YEAR(birthdate) FROM users;  （从 birthdate 列中提取年份）

8. MONTH() 函数：用于从日期/时间表达式中提取月份。
示例：SELECT MONTH(hire_date) FROM employees;  （从 hire_date 列中提取月份）

9. UPPER() 函数：将字符串转换为大写。
示例：SELECT UPPER(name) FROM customers;  （将 name 列的值转换为大写）

10. LOWER() 函数：将字符串转换为小写。
示例：SELECT LOWER(email) FROM users;  （将 email 列的值转换为小写）

这只是一小部分常见的 SQL 函数，不同的数据库系统可能会有一些特定的函数和细微的语法差异。您使用的是哪种具体的数据库（如 MySQL、Oracle、SQL Server 等）呢？

在 Google BigQuery 中，常见的函数包括但不限于以下这些：

1. DATE_SUB() 函数：用于从日期中减去指定的时间间隔。
示例：SELECT DATE_SUB(current_date, INTERVAL 7 DAY)  （返回当前日期减去 7 天的结果）

2. FORMAT_DATE() 函数：用于按照指定的格式格式化日期。
示例：SELECT FORMAT_DATE('%Y-%m-%d', current_date)  （以 '年-月-日' 的格式显示当前日期）

3. STRING_AGG() 函数：用于将字符串列的值连接成一个字符串。
示例：SELECT STRING_AGG(name, ', ') FROM users  （将 name 列的值用逗号和空格连接起来）

4. COALESCE() 函数：返回参数列表中的第一个非空值。
示例：SELECT COALESCE(null, 5, null)  （返回 5）

5. SAFE_DIVIDE() 函数：安全地执行除法运算，如果除数为 0，则返回 NULL 而不是报错。
示例：SELECT SAFE_DIVIDE(10, 0)  （返回 NULL ）

您可以查阅 Google BigQuery 的官方文档以获取更详细和全面的函数信息及使用示例。


在 Google BigQuery 中，窗口函数是非常强大和有用的工具。以下为您介绍一些常见的窗口函数及其高级用法：

1. ROW_NUMBER() 函数：为结果集中的每一行分配一个唯一的连续整数编号。
示例：SELECT id, name, ROW_NUMBER() OVER (ORDER BY salary DESC) AS row_num FROM employees;  （按照工资降序排列并为每行分配编号）

2. RANK() 函数：与 ROW_NUMBER() 类似，但如果存在相同的值，会为这些相同的值分配相同的排名，并且排名可能不连续。
示例：SELECT id, name, RANK() OVER (ORDER BY salary DESC) AS rank_num FROM employees;

3. DENSE_RANK() 函数：与 RANK() 类似，但排名是连续的，不会有间隔。
示例：SELECT id, name, DENSE_RANK() OVER (ORDER BY salary DESC) AS dense_rank_num FROM employees;

4. LAG(col, offset, default_value) 函数：用于访问当前行之前指定偏移量的行中的值。
示例：SELECT id, name, salary, LAG(salary, 1, 0) OVER (ORDER BY id) AS prev_salary FROM employees;  （获取每行上一行的工资，如果上一行不存在则返回 0 ）

5. LEAD(col, offset, default_value) 函数：用于访问当前行之后指定偏移量的行中的值。
示例：SELECT id, name, salary, LEAD(salary, 1, 0) OVER (ORDER BY id) AS next_salary FROM employees;  （获取每行下一行的工资，如果下一行不存在则返回 0 ）

6. SUM(col) OVER (PARTITION BY col1 ORDER BY col2) 函数：按照指定的分区和排序规则进行累计求和。
示例：SELECT id, department, salary, SUM(salary) OVER (PARTITION BY department ORDER BY id) AS cumulative_salary FROM employees;  （按照部门分区，对工资进行累计求和）

这些只是窗口函数的一些基本示例，您可以根据具体的业务需求和数据特点灵活运用，以实现更复杂的数据处理和分析。











