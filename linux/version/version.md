
- 这个Shell脚本的目标是从一个关键字列表中提取主版本号，次版本号和修订版本号，并创建一个关联数组，以存储每个主版本号对应的最大版本。
# summary

这个Shell脚本的目标是从一个关键字列表中提取主版本号，次版本号和修订版本号，并创建一个关联数组，以存储每个主版本号对应的最大版本。以下是脚本的详细解释：

1. `declare -A max_versions`：这一行创建了一个关联数组`max_versions`，用于存储每个主版本号对应的最大版本。

2. `keywords=("52-1-21" "52-1-22" "52-1-23" "51-2-21" "51-1-21" "51-1-20")`：这一行定义了一个关键字列表`keywords`，其中包含了一组版本号，每个版本号由主版本号、次版本号和修订版本号组成。

3. `for keyword in "${keywords[@]}"; do`：这是一个`for`循环，它会遍历关键字列表`keywords`中的每个关键字。

4. `major_version=$(echo $keyword | awk -F'-' '{print $1}')`：这一行使用`awk`命令从当前关键字中提取主版本号，并将其存储在变量`major_version`中。`-F'-'`指定了字段分隔符为`-`，因此`'{print $1}'`提取了第一个字段，即主版本号。

5. `minor_version=$(echo $keyword | awk -F'-' '{print $2}')`：类似地，这一行提取了次版本号，并将其存储在变量`minor_version`中。

6. `patch_version=$(echo $keyword | awk -F'-' '{print $3}')`：同样，这一行提取了修订版本号，并将其存储在变量`patch_version`中。

7. `version_str="${major_version}-${minor_version}-${patch_version}"`：这一行构建了一个版本字符串`version_str`，将主版本号、次版本号和修订版本号连接起来，用于后续的版本比较。

8. `if [ -z "${max_versions[$major_version]}" ]; then`：这是一个条件语句，检查关联数组`max_versions`中是否已经有该主版本号的最大版本。`-z`用于检查变量是否为空。

这段代码的目的是维护一个关联数组 `max_versions`，以确保每个主版本号对应的最大版本号被正确地记录下来。下面是代码的更详细解释：

8.1. `if [ -z "${max_versions[$major_version]}" ]; then`：这个条件语句首先检查是否已经存在一个最大版本号（以主版本号 `$major_version` 作为索引）。这里使用了 `-z` 条件，它检查一个字符串是否为空。如果 `${max_versions[$major_version]}` 为空，表示还没有记录这个主版本号的最大版本。

8.2. `max_versions[$major_version]=$version_str`：如果条件满足，也就是没有记录这个主版本号的最大版本，那么当前版本号 `$version_str` 就会被设置为该主版本号的最大版本。这一步将初始化该主版本号的最大版本。

8.3. `else`：如果条件不满足，说明已经有了记录这个主版本号的最大版本。

8.4. `if [[ "$version_str" > "${max_versions[$major_version]}" ]]; then`：在这里，脚本会比较当前版本号 `$version_str` 与已记录的最大版本 `${max_versions[$major_version]}`。这个比较是使用双方括号 `[[ ... ]]` 来完成的，它允许进行字符串比较。

8.5. `max_versions[$major_version]=$version_str`：如果当前版本号 `$version_str` 比已记录的最大版本 `${max_versions[$major_version]}` 大，则更新最大版本为当前版本号。这确保了在遍历关键字列表时，只有最大版本会被记录下来。

总结：这段代码负责维护一个记录每个主版本号最大版本的关联数组。它首先检查是否已经有了最大版本，如果没有，就将当前版本作为最大版本记录下来。如果已经有了最大版本，它会比较当前版本与已有的最大版本，将较大的版本作为最大版本。这样，最终你将得到每个主版本号对应的最大版本。

- eg
当你需要使用关联数组中的值时，可以使用`${array[key]}`的语法。这里有一个简单的例子，假设我们有一个关联数组 `fruit_prices`，它存储了不同水果的价格：

```bash
#!/bin/bash

# 创建关联数组
declare -A fruit_prices
fruit_prices["apple"]=0.99
fruit_prices["banana"]=0.25
fruit_prices["cherry"]=1.50

# 检索水果的价格
selected_fruit="banana"
price="${fruit_prices[$selected_fruit]}"

# 打印结果
echo "价格 for $selected_fruit 是 $price"
```

在这个例子中，`${fruit_prices[$selected_fruit]}` 表示从关联数组 `fruit_prices` 中检索出与 `$selected_fruit`（这里是 "banana"）关联的价格。最后，脚本会打印出所选水果的价格。


9. `max_versions[$major_version]=$version_str`：如果该主版本号在关联数组中不存在（即为空），则将当前版本字符串`version_str`存储在`max_versions`中，以表示当前版本是该主版本号的最大版本。

10. `else`：如果关联数组中已经有该主版本号的最大版本，则执行下面的操作。

11. `if [[ "$version_str" > "${max_versions[$major_version]}" ]]; then`：这是另一个条件语句，比较当前版本字符串`version_str`与关联数组中存储的最大版本的字符串。如果当前版本较大，则执行下面的操作。

12. `max_versions[$major_version]=$version_str`：如果当前版本较大，将当前版本字符串存储为该主版本号的最大版本。

13. `done`：结束循环。

14. `for major_version in "${!max_versions[@]}"; do`：这是另一个`for`循环，用于遍历`max_versions`关联数组中的每个主版本号。

15. `echo "最大版本 for 主版本号 $major_version : ${max_versions[$major_version]}"`：在循环内部，打印每个主版本号对应的最大版本。

这个脚本的最终目标是确定每个主版本号对应的最大版本，并将其输出。它逐一遍历关键字列表中的版本号，提取主、次、修订版本号，比较它们，然后将每个主版本号的最大版本存储在关联数组`max_versions`中，并最终打印出来。
```bash
!/usr/local/bin/bash

# 创建一个关联数组来存储每个主版本号对应的最大版本
declare -A max_versions

# 输入的关键字列表
keywords=("52-1-21" "52-1-22" "52-1-23" "51-2-21" "51-1-21" "51-1-20")

# 遍历关键字列表
for keyword in "${keywords[@]}"; do
    # 提取主版本号
    major_version=$(echo $keyword | awk -F'-' '{print $1}')

    # 提取次版本号
    minor_version=$(echo $keyword | awk -F'-' '{print $2}')

    # 提取修订版本号
    patch_version=$(echo $keyword | awk -F'-' '{print $3}')

    # 构建版本字符串，用于比较
    version_str="${major_version}-${minor_version}-${patch_version}"

    # 检查是否已经有最大版本
    if [ -z "${max_versions[$major_version]}" ]; then
        max_versions[$major_version]=$version_str
    else
        # 比较当前版本与最大版本，如果当前版本较大则更新最大版本
        if [[ "$version_str" > "${max_versions[$major_version]}" ]]; then
            max_versions[$major_version]=$version_str
        fi
    fi
done

# 打印最大版本
for major_version in "${!max_versions[@]}"; do
    echo "最大版本 for 主版本号 $major_version : ${max_versions[$major_version]}"
done
```
#

: << 'END'

END
