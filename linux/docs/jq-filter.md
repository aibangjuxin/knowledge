- filter-all-offplatform-apis-deployMigRefs.sh
```bash
#!/bin/bash
# step 1 提取我要的字段
# cat all-offplatform-apis-deployMigRefs.json|jq '{name: .name, assetId: .assetId, majorVersion: .majorVersion, instanceLabel: .instanceLabel, minor_version: .version,deployedMigRefs: .deployedMigRefs}' > filter-all-deployMigrefs.json 
# step 2
# cp filter-all-deployMigrefs.json data.json 
# 定义环境列表
environments=("dev.env" "ad.env")

# 循环遍历每个环境
for env in "${environments[@]}"; do
    # 执行jq命令，并传递环境信息作为参数
    cat data.json | jq -r --arg env "$env" 'select(.deployedMigRefs[$env]) | {env: $env | split(".") | .[0], region: $env | split(".") | .[1], name: .name, assetId: .assetId, majorVersion: .majorVersion, minor_version: .minor_version, segment: .deployedMigRefs[$env].path.segments[1]} | [.env, .region, .name, .assetId, .majorVersion, .minor_version, .segment] | @csv'
done
```

summary:
- 1 分析数据结构,明确自己需要什么样的数据,是要的数据的Key还是Value
  - `cat all-offplatform-apis-deployMigRefs.json|jq '{name: .name, assetId: .assetId, majorVersion: .majorVersion, instanceLabel: .instanceLabel, minor_version: .version,deployedMigRefs: .deployedMigRefs}' > filter-all-deployMigrefs.json`
- 1.1 如果是对应的Value可以直接获取,如果不是,就可能需要重组数据
- 2 然后根据上面1获取的数据来提取自己想要的数据再次转化为 CSV文件


这段输入代码是一个Bash脚本，用于遍历一个名为`environments`的数组，并在每个环境中执行一个特定的命令。这个命令使用`jq`命令和一些动态参数，来提取和处理一些JSON数据。

实现原理：
脚本首先使用`for`循环遍历`environments`数组中的每个环境。然后，它使用`cat`命令和`jq`命令来处理JSON数据。`jq`命令的`-r`选项表示“纯结果”，即不使用引号输出结果。`--arg`选项用于传递环境变量作为参数。

提取和处理JSON数据的步骤如下：
1. 使用`select`函数过滤出在给定环境中部署的`MigRefs`。
2. 使用`.deployedMigRefs[$env]`访问`deployedMigRefs`字典中的键`$env`对应的值。
3. 使用`path.segments[1]`访问`deployedMigRefs`的路径中的segments部分，获取分段信息。
4. 使用`@csv`命令将处理后的数据转换为CSV格式。

用途：
这个脚本主要用于从一系列环境配置中提取和处理部署了`MigRefs`的环境信息。

注意事项：
1. 确保已安装`jq`命令行工具，以便在处理JSON数据时使用。
2. 请确保`data.json`文件已正确格式化，以便`jq`命令能够正确处理。
3. 注意处理分段的顺序和位置，以确保输出符合预期。


# merged csv
比如我有一个a.csv 文件 我想拿这个文件的第二个字段 比如第二个字段是api_name 去匹配b.csv文件中 匹配api_name 的 行 然后将b.csv 的最后一个字段合并到a.csv

你可以使用awk命令来完成这个任务。假设a.csv和b.csv都是逗号分隔的文件，你可以尝试以下命令：

```bash
awk -F ',' 'NR==FNR{a[$2]=$NF; next} $2 in a {print $0","a[$2]}' b.csv a.csv > merged.csv
```
``` bash
这个命令首先读取b.csv文件，将第二个字段作为关键字，最后一个字段作为值存储在数组a中。然后读取a.csv文件，如果第二个字段在数组a中存在，则输出当前行，并附加对应的值。最后将结果输出到merged.csv文件中。

# 创建一个包含 a.csv 中第二个字段（api_name）的临时文件
cut -d, -f2 a.csv > temp_api_names.txt

# 在 b.csv 中过滤与 temp_api_names.txt 中 api_name 匹配的行
awk -F, 'FNR==NR{a[$1]=$NF;next} {print $0,a[$2]}' temp_api_names.txt b.csv > temp_merged.csv

# 将 temp_merged.csv 中的最后一个字段提取到一个临时文件中
cut -d, -fNF temp_merged.csv > temp_last_column.txt

# 将 temp_last_column.txt 合并到 a.csv 中
paste a.csv temp_last_column.txt > merged_a.csv

# 清理临时文件
rm temp_api_names.txt temp_merged.csv temp_last_column.txt
```

好的,我们可以使用 `awk` 命令来实现这个需求。下面是具体的 shell 脚本:

```bash
#!/bin/bash

# 检查文件是否存在
if [ ! -f "a.csv" ] || [ ! -f "b.csv" ]; then
    echo "文件 a.csv 或 b.csv 不存在!"
    exit 1
fi

# 获取 b.csv 的最后一列名称
last_col=$(head -n 1 b.csv | tr ',' '\n' | tail -n 1)

# 创建临时文件
tmp_file=$(mktemp)

# 从 b.csv 中提取 api_name 和最后一列的值
awk -F ',' '{print $2 "," $NF}' b.csv > "$tmp_file"

# 将 a.csv 和临时文件合并
join -t ',' -1 2 -2 1 -o 1.1,1.2,2.2 a.csv "$tmp_file" > merged.csv

# 删除临时文件
rm "$tmp_file"

echo "合并完成,结果保存在 merged.csv 文件中。"
```

解释:

1. 首先,我们检查 `a.csv` 和 `b.csv` 文件是否存在。如果任何一个文件不存在,则输出错误信息并退出脚本。

2. 使用 `head` 和 `tr` 命令从 `b.csv` 文件的第一行获取最后一列的名称,并将其存储在变量 `last_col` 中。

3. 创建一个临时文件,用于存储从 `b.csv` 中提取的 `api_name` 和最后一列的值。我们使用 `mktemp` 命令来创建这个临时文件。

4. 使用 `awk` 命令从 `b.csv` 中提取 `api_name`(第二列)和最后一列的值,并将它们写入临时文件。

5. 使用 `join` 命令将 `a.csv` 和临时文件合并。`-t` 选项指定字段分隔符为逗号,`-1 2` 表示使用 `a.csv` 的第二列进行匹配,`-2 1` 表示使用临时文件的第一列进行匹配,`-o` 选项指定输出格式。最后,合并结果写入 `merged.csv` 文件。

6. 删除临时文件。

7. 输出一条消息,表示合并已完成,结果保存在 `merged.csv` 文件中。

使用方法:

1. 将上述脚本保存为一个文件,例如 `merge_csv.sh`。

2. 在终端中,切换到包含 `a.csv`、`b.csv` 和 `merge_csv.sh` 文件的目录。

3. 运行脚本:

```bash
bash merge_csv.sh
```

4. 脚本执行完成后,将在当前目录下生成一个名为 `merged.csv` 的新文件,其中包含了从 `a.csv` 中获取的所有行,以及从 `b.csv` 中匹配的最后一列的值。

注意:这个脚本假设 `a.csv` 和 `b.csv` 文件的第二列和最后一列分别对应 `api_name` 和要合并的列。如果列名不同,你需要相应地修改脚本中的列索引。


# jq eval
你可以在脚本中使用`eval`命令来执行你要执行的命令。这样就可以避免逐行复制命令。下面是一个示例：

```bash
#!/bin/bash

# 在这里列出你要执行的命令
commands=(
    "ls -l"
    "echo Hello, World!"
    "date"
)

# 执行命令
for cmd in "${commands[@]}"; do
    eval "$cmd"
done
```

在这个示例中，你可以将要执行的命令列在`commands`数组中，然后在脚本中使用`eval`命令来执行这些命令。

当你使用`eval`命令时，它会将传递给它的参数当做一条命令来执行。这意味着它会解释参数中的所有变量、通配符和其他Shell特性，并将它们作为一条完整的命令来执行。下面是一个更详细的解释：

1. **解释参数：**`eval`命令会解释传递给它的参数，并将其作为一条命令执行。这意味着你可以在参数中包含变量、通配符、命令替换等Shell特性。

2. **执行命令：**一旦参数被解释，`eval`会将解释后的结果作为一条命令来执行。这使得你可以在运行时动态地构建和执行命令，而不是在脚本中静态地写死命令。

3. **扩展变量：**`eval`可以扩展变量，因此你可以在参数中使用Shell变量，并在执行时将其替换为其当前值。

4. **处理引号：**`eval`可以处理引号，这意味着你可以在参数中包含引号，并且它们会被正确地解释和处理。

5. **注意安全性：**由于`eval`会执行传递给它的参数，因此要小心使用，特别是在处理来自外部的输入时，以避免安全漏洞。确保只有可信任的内容被传递给`eval`。


理解了你的需求，下面是一个组合了`jq`和`eval`的脚本，用于根据不同的环境变量来过滤结果并将结果追加到文件中：

```bash
#!/bin/bash

# 定义不同环境变量的值
environments=(
    "production"
    "staging"
    "development"
)

# 定义要执行的jq命令
jq_commands=(
    ".[] | select(.environment == \"$1\")"
)

# 要追加结果的文件
output_file="output.txt"

# 清空输出文件
> "$output_file"

# 执行不同环境的过滤操作并追加到输出文件
for env in "${environments[@]}"; do
    echo "Processing environment: $env"
    # 执行jq命令并将结果追加到输出文件
    eval "jq ${jq_commands[0]} input.json >> $output_file"
done

echo "All environments processed successfully."
```

在这个脚本中：

- `environments`数组定义了不同的环境变量的值，你可以根据需要修改或扩展。
- `jq_commands`数组定义了要执行的jq命令，其中使用了`$1`来引用传递给脚本的环境变量。
- `output_file`变量指定了要追加结果的文件。
- 脚本会依次处理不同环境的过滤操作，并将结果追加到输出文件中。

你可以将脚本保存为一个文件，比如`filter_data.sh`，然后执行`chmod +x filter_data.sh`添加可执行权限，最后通过`./filter_data.sh`来运行脚本。



# eval 
```bash
#!/bin/bash

# 在这里列出你要执行的命令
commands=(
    "echo abc"
    "echo def"
    "ls -al"
)
# 执行命令
for cmd in "${commands[@]}"; do
    eval "$cmd"
done
```

这段 Shell 代码的目的是在一个脚本中执行多个命令。它使用了 `bash` 作为脚本解释器，并使用了 `eval` 命令来执行命令字符串。

1. 在脚本的开头，使用了 `#!/bin/bash` 指定使用 BASH 解释器。
2. 接下来，定义了一个名为 `commands` 的数组，其中包含了要执行的命令。这些命令可以是任何用户输入的文本，也可以是其他脚本文件中的命令。
3. 使用 `for` 循环遍历数组中的每个命令，并使用 `eval` 命令执行每个命令。`eval` 命令会解析命令字符串，并将其当作 BASH 代码执行。这使得脚本可以执行多种类型的命令，例如调用其他脚本或命令。
4. 在循环中，`eval` 命令接收两个参数：`"$cmd"` 和 `"${commands[@]}"`。`$cmd` 表示当前循环到的命令，`${commands[@]}` 表示数组中的所有命令。`eval` 命令会将这两个参数拼接成一个 BASH 命令字符串，并执行该命令。

注意：`eval` 命令可能会导致安全风险，因为它可以执行任何输入的命令。在编写脚本时，请确保输入的命令是安全的，避免执行恶意代码。
