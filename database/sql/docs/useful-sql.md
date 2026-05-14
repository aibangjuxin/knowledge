-- 1. COALESCE: 返回列表中第一个非空值
SELECT COALESCE(column1, column2, 'default_value') AS result FROM table_name;

-- 2. NULLIF: 如果两个表达式相等，则返回 NULL，否则返回第一个表达式
SELECT NULLIF(column1, column2) AS result FROM table_name;

-- 3. CASE: 根据条件返回特定值的条件表达式
SELECT
CASE
WHEN condition1 THEN result1
WHEN condition2 THEN result2
ELSE default_result
END AS result
FROM table_name;

-- 4. ROLLUP: 生成小计和总计
SELECT department, SUM(salary)
FROM employees
GROUP BY department WITH ROLLUP;

-- 5. CUBE: 生成一个结果集，表示分组的所有可能组合
SELECT department, job_title, SUM(salary)
FROM employees
GROUP BY department, job_title WITH CUBE;

-- 6. EXISTS: 检查子查询中是否存在行
SELECT \* FROM Employees WHERE EXISTS (SELECT 1 FROM departments WHERE departments.id = employees.department_id);

-- 7. INTERSECT: 返回两个 SELECT 语句的公共记录
SELECT column_name FROM table1
INTERSECT
SELECT column_name FROM table2;

-- 8. EXCEPT: 返回第一个 SELECT 语句中不存在于第二个 SELECT 语句中的记录
SELECT column_name FROM table1
EXCEPT
SELECT column_name FROM table2;

-- 9. OFFSET-FETCH: 用于分页，跳过指定数量的行并返回下一组
SELECT \* FROM table_name ORDER BY column_name OFFSET 10 ROWS FETCH NEXT 5 ROWS ONLY;

-- 10. PIVOT: 将行转换为列以便于分析
SELECT \* FROM (SELECT Year, Quarter, Revenue FROM Sales) AS SourceTable
PIVOT (SUM(Revenue) FOR Quarter IN ([Q1], [Q2], [Q3], [Q4])) AS PivotTable;

-- 11. UNPIVOT: 将列转换为行
SELECT Year, Quarter, Revenue
FROM (SELECT Year, Q1, Q2, Q3, Q4 FROM Sales) AS SourceTable
UNPIVOT (Revenue FOR Quarter IN (Q1, Q2, Q3, Q4)) AS UnpivotedTable;

-- 12. 公共表表达式 (CTE): 可以在 SELECT、INSERT、UPDATE 或 DELETE 语句中引用的临时结果集
WITH CTE AS (
SELECT column1, column2 FROM table_name WHERE condition
)
SELECT \* FROM CTE;

-- 1. COALESCE: Returns the first non-null value in the list
SELECT COALESCE(column1, column2, 'default_value') AS result FROM table_name;

-- 2. NULLIF: Returns NULL if two expressions are equal, otherwise returns the first expression
SELECT NULLIF(column1, column2) AS result FROM table_name;

-- 3. CASE: Conditional expressions that return specific values based on conditions
SELECT
CASE
WHEN condition1 THEN result1
WHEN condition2 THEN result2
ELSE default_result
END AS result
FROM table_name;

-- 4. ROLLUP: Generates subtotals and grand totals
SELECT department, SUM(salary)
FROM employees
GROUP BY department WITH ROLLUP;

-- 5. CUBE: Generates a result set that represents all possible combinations of groupings
SELECT department, job_title, SUM(salary)
FROM employees
GROUP BY department, job_title WITH CUBE;

-- 6. EXISTS: Checks for the existence of rows in a subquery
SELECT \* FROM Employees WHERE EXISTS (SELECT 1 FROM departments WHERE departments.id = employees.department_id);

-- 7. INTERSECT: Returns the common records from two SELECT statements
SELECT column_name FROM table1
INTERSECT
SELECT column_name FROM table2;

-- 8. EXCEPT: Returns the records from the first SELECT statement that are not in the second
SELECT column_name FROM table1
EXCEPT
SELECT column_name FROM table2;

-- 9. OFFSET-FETCH: Used for pagination, skips a specified number of rows and returns the next set
SELECT \* FROM table_name ORDER BY column_name OFFSET 10 ROWS FETCH NEXT 5 ROWS ONLY;

-- 10. PIVOT: Converts rows into columns for easier analysis
SELECT \* FROM (SELECT Year, Quarter, Revenue FROM Sales) AS SourceTable
PIVOT (SUM(Revenue) FOR Quarter IN ([Q1], [Q2], [Q3], [Q4])) AS PivotTable;

-- 11. UNPIVOT: Converts columns into rows
SELECT Year, Quarter, Revenue
FROM (SELECT Year, Q1, Q2, Q3, Q4 FROM Sales) AS SourceTable
UNPIVOT (Revenue FOR Quarter IN (Q1, Q2, Q3, Q4)) AS UnpivotedTable;

-- 12. COMMON TABLE EXPRESSION (CTE): Temporary result set that can be referenced within a SELECT, INSERT, UPDATE, or DELETE statement
WITH CTE AS (
SELECT column1, column2 FROM table_name WHERE condition
)
SELECT \* FROM CTE;
