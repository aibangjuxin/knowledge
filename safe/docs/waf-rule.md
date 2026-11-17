"owasp-crs-v030301-id942420-sqli" 是一个 Web 应用防火墙 (WAF) 规则，属于 OWASP CRS (OWASP Core Rule Set) 规则集。具体来说，它是用于检测 SQL 注入 (SQLi) 攻击的规则。

### 规则详细信息

#### OWASP CRS 版本
- 版本: v3.0.3

#### 规则 ID
- ID: 942420

#### 规则名称
- Detects classic SQL injection probings 1/2

### 规则功能
这个规则主要用于检测经典的 SQL 注入探测行为。SQL 注入是一种通过操纵 SQL 查询来访问或破坏数据库的攻击方法。该规则通过匹配特定的模式和行为来识别潜在的 SQL 注入攻击。

### 规则逻辑
具体来说，规则 `942420` 会检查以下内容：
1. 常见的 SQL 关键字，例如 `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `UNION`, `DROP`, `--`（SQL 注释符号）等。
2. 常见的 SQL 注入 payload，例如 `' OR 1=1 --`，`'; DROP TABLE users; --` 等。
3. 特定的 SQL 注入特征，例如单引号、双引号、分号、等号等组合使用。

### 规则实现
规则的实现通常会通过正则表达式或特定的匹配模式来检测 SQL 注入行为。例如：

```yaml
SecRule ARGS "@rx (?i:(select|union|insert|update|delete|drop|--|;|'))" \
    "id:942420,\
    phase:2,\
    block,\
    capture,\
    t:none,\
    msg:'Detects classic SQL injection probings 1/2',\
    logdata:'Matched Data: %{TX.0} found within %{MATCHED_VAR_NAME}: %{MATCHED_VAR}',\
    severity:'CRITICAL',\
    tag:'application-multi',\
    tag:'language-multi',\
    tag:'platform-multi',\
    tag:'attack-sqli',\
    tag:'paranoia-level/1',\
    tag:'OWASP_CRS/WEB_ATTACK/SQL_INJECTION',\
    setvar:'tx.msg=%{rule.msg}',\
    setvar:tx.sql_injection_score=+%{tx.critical_anomaly_score},\
    setvar:tx.anomaly_score=+%{tx.critical_anomaly_score},\
    setvar:'tx.%{rule.id}-OWASP_CRS/WEB_ATTACK/SQL_INJECTION-%{matched_var_name}=%{tx.0}'"
```

### 解释
- `SecRule ARGS "@rx (?i:(select|union|insert|update|delete|drop|--|;|'))"`: 该部分定义了规则检测的条件，即在请求参数中匹配不区分大小写的 SQL 关键字和特征。
- `id:942420`: 规则的唯一标识符。
- `phase:2`: 规则运行的阶段，这里是在请求处理的第 2 阶段。
- `block`: 当规则匹配时，阻止请求。
- `capture`: 捕获匹配的数据。
- `t:none`: 不对输入数据进行任何转换。
- `msg:'Detects classic SQL injection probings 1/2'`: 规则匹配时的消息。
- `logdata:'Matched Data: %{TX.0} found within %{MATCHED_VAR_NAME}: %{MATCHED_VAR}'`: 记录匹配的数据和变量。
- `severity:'CRITICAL'`: 规则的严重级别。
- `tag:'application-multi'`, `tag:'language-multi'`, `tag:'platform-multi'`, `tag:'attack-sqli'`, `tag:'paranoia-level/1'`, `tag:'OWASP_CRS/WEB_ATTACK/SQL_INJECTION'`: 为规则打上标签，便于分类和管理。
- `setvar:'tx.msg=%{rule.msg}'`: 设置事务变量以包含规则消息。
- `setvar:tx.sql_injection_score=+%{tx.critical_anomaly_score}`, `setvar:tx.anomaly_score=+%{tx.critical_anomaly_score}`: 更新 SQL 注入得分和总体异常得分。

### 示例
假设有一个输入参数包含如下内容：
```sql
' OR '1'='1
```
这个规则将识别这种模式并标记为潜在的 SQL 注入攻击，从而阻止请求。

### 总结
规则 "owasp-crs-v030301-id942420-sqli" 是用于检测 SQL 注入攻击的一部分，通过匹配 SQL 关键字和注入特征来保护 Web 应用免受 SQL 注入攻击。如果匹配到相应的模式，该规则将阻止请求并记录相关信息。