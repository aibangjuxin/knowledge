# DuckDB 使用指南


```sql
D .show
        echo: off
     headers: on
        mode: duckbox
   nullvalue: "NULL"
      output: stdout
colseparator: "|"
rowseparator: "\n"
       width: 
    filename: :memory:
D 
D 
D .open project.aibang_api_data
D .dtabases
Error: unknown command or invalid arguments:  "dtabases". Enter ".help" for help
D .databases
project: project.aibang_api_data
D CREATE TABLE emid_tier (
      eimId STRING,
      tier STRING
  )
  
  ;
D INSERT INTO emid_tier (eimId, tier) VALUES
      ('12345678901234567890123456789012', 'P1'),
      ('23456789012345678901234567890123', 'P2'),
      ('34567890123456789012345678901234', 'P3');
D 
D select * from emid_tier;
┌──────────────────────────────────┬─────────┐
│              eimId               │  tier   │
│             varchar              │ varchar │
├──────────────────────────────────┼─────────┤
│ 12345678901234567890123456789012 │ P1      │
│ 23456789012345678901234567890123 │ P2      │
│ 34567890123456789012345678901234 │ P3      │
└──────────────────────────────────┴─────────┘
D .tables
emid_tier
```

## 创建和连接数据库

1. **创建并连接到持久化数据库**
```sql
-- 在 DuckDB CLI 中使用 .open 命令创建/连接数据库
.open mydb.db

D .open project.aibang_api_data.db
用了DuckDB的默认内存模式（:memory:），这种模式下数据库在会话结束后会丢失。要实现数据持久化，
你需要在创建数据库时指定一个文件路径，比如使用`.open my_database.db` 命令创建一个持久化的数据库文件。这样即使重启主机，数据也会保存在这个.duckdb文件中

duckdb project.aibang_api_data.duckdb
v1.2.1 8e52ec4395
Enter ".help" for usage hints.
D .databases
project: project.aibang_api_data.duckdb
D CREATE TABLE emid_tier (
      eimId STRING,
      tier STRING
  );
D 
D 
D INSERT INTO emid_tier (eimId, tier) VALUES
      ('12345678901234567890123456789012', 'P1'),
      ('23456789012345678901234567890123', 'P2'),
      ('34567890123456789012345678901234', 'P3');
D .quit
duckdb project.aibang_api_data.duckdb
v1.2.1 8e52ec4395
Enter ".help" for usage hints.
D .databases
project: project.aibang_api_data.duckdb
D .tables
emid_tier
D select * from emid_tier where eimId like '12%';
┌──────────────────────────────────┬─────────┐
│              eimId               │  tier   │
│             varchar              │ varchar │
├──────────────────────────────────┼─────────┤
│ 12345678901234567890123456789012 │ P1      │
└──────────────────────────────────┴─────────┘

```

2. **查看当前数据库信息**
```sql
.databases

D .databases
project: project.aibang_api_data
```

## 创建表和管理数据

1. **创建表**
```sql
-- 创建一个简单的用户表
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
- create a table 
CREATE TABLE emid_tier (
    eimId STRING,
    tier STRING
);

-- 创建一个带有外键约束的订单表
CREATE TABLE orders (
    order_id INTEGER PRIMARY KEY,
    user_id INTEGER,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2),
    FOREIGN KEY (user_id) REFERENCES users(id)
);
```

2. **插入数据**
```sql
-- 插入单条数据
INSERT INTO users (id, username, email)
VALUES (1, 'john_doe', 'john@example.com');

-- 插入多条数据
INSERT INTO users (id, username, email) VALUES
    (2, 'jane_doe', 'jane@example.com'),
    (3, 'bob_smith', 'bob@example.com');
```

-- insert data into emid_tier

```sql
INSERT INTO emid_tier (eimId, tier) VALUES
    ('12345678901234567890123456789012', 'P1'),
    ('23456789012345678901234567890123', 'P2'),
    ('34567890123456789012345678901234', 'P3');
```

3. **查询数据**
```sql
-- 查询所有用户
SELECT * FROM users;

select * from emid_tier where eimId = '12345678901234567890123456789012';
select * from emid_tier where eimId like '%12';
这个是以12结尾的eimId
如果是查询以12开头的eimId，那么就是
select * from emid_tier where eimId like '12%';


-- 条件查询
SELECT username, email
FROM users
WHERE id > 1;
```

## 常用数据类型

- INTEGER：整数类型
- BIGINT：大整数类型
- DECIMAL(p,s)：定点数，p 是总位数，s 是小数位数
- VARCHAR(n)：变长字符串，n 是最大长度
- BOOLEAN：布尔类型
- DATE：日期类型
- TIMESTAMP：时间戳类型
- DOUBLE：双精度浮点数

## 常用约束

- PRIMARY KEY：主键约束
- FOREIGN KEY：外键约束
- UNIQUE：唯一约束
- NOT NULL：非空约束
- DEFAULT：默认值约束
- CHECK：检查约束

## 实用命令

```sql
-- 查看所有表
.tables

-- 查看表结构
.schema table_name

-- 导入 CSV 文件
.import 'data.csv' table_name

-- 导出查询结果到 CSV
.mode csv
.output result.csv
SELECT * FROM table_name;
.output stdout
```

## 索引管理

```sql
-- 创建索引
CREATE INDEX idx_username ON users(username);

-- 删除索引
DROP INDEX idx_username;
```

## 事务处理

```sql
-- 开始事务
BEGIN TRANSACTION;

-- 执行操作
INSERT INTO users (id, username) VALUES (4, 'alice');
UPDATE users SET email = 'alice@example.com' WHERE id = 4;

-- 提交事务
COMMIT;

-- 回滚事务
-- ROLLBACK;
```

## 如何从macOS命令行连接我这个数据库?

如果你已经在 macOS 上安装了 DuckDB，可以使用命令行直接连接并执行 SQL 查询。

⸻

方法 1：使用命令行直接连接 DuckDB

1. 确保 DuckDB 已安装

brew install duckdb

或者，如果你使用 pip 安装：

pip install duckdb

2. 进入 DuckDB 交互模式

duckdb

你应该会看到类似这样的提示：

DuckDB 0.9.2 (c) 2018-2024 DuckDB Foundation
Enter ".help" for usage hints.

然后可以直接执行 SQL 语句：

CREATE TABLE users (id INTEGER, name STRING);
INSERT INTO users VALUES (1, 'Alice'), (2, 'Bob');
SELECT * FROM users;



⸻

方法 2：连接到 DuckDB 本地数据库文件

默认情况下，DuckDB 使用 内存模式，所有数据在会话结束后丢失。如果你想要持久存储数据，可以连接到一个 DuckDB 数据库文件。

1. 创建或连接到 DuckDB 数据库文件

duckdb my_database.duckdb

你会进入 DuckDB 交互模式：

D file:my_database.duckdb

然后你可以运行 SQL 语句：

CREATE TABLE employees (id INTEGER, name STRING, salary FLOAT);
INSERT INTO employees VALUES (1, 'Alice', 50000), (2, 'Bob', 60000);
SELECT * FROM employees;



⸻

方法 3：从命令行直接执行 SQL

你也可以在 macOS 终端直接执行 SQL 查询，而不进入交互模式：

duckdb my_database.duckdb "SELECT 'Hello, DuckDB!' AS message;"

输出：

┌────────────────┐
│    message     │
├────────────────┤
│ Hello, DuckDB! │
└────────────────┘



⸻

方法 4：使用 Python 连接 DuckDB

如果你更喜欢用 Python 进行查询，可以这样：

pip install duckdb pandas

然后运行：

import duckdb

# 连接到 DuckDB 文件
conn = duckdb.connect("my_database.duckdb")

# 执行 SQL 查询
conn.execute("CREATE TABLE IF NOT EXISTS users (id INTEGER, name STRING)")
conn.execute("INSERT INTO users VALUES (1, 'Alice'), (2, 'Bob')")
result = conn.execute("SELECT * FROM users").fetchall()

# 输出结果
for row in result:
    print(row)

# 关闭连接
conn.close()



⸻

总结

方法	适用场景	例子
交互模式	手动输入 SQL	duckdb
连接数据库文件	持久化存储数据	duckdb my_database.duckdb
直接执行 SQL	在终端执行 SQL	duckdb my_database.duckdb "SELECT * FROM users;"
Python 连接	代码操作 DuckDB	duckdb.connect("my_database.duckdb")

如果你只是想测试 SQL，推荐 方法 1（交互模式）。
如果你想长期存储数据，推荐 方法 2（数据库文件）。
如果你要自动化查询，可以用 方法 3（命令行 SQL） 或 方法 4（Python）。


