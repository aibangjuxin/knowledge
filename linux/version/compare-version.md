- sort 
``` bash
#!/bin/bash

# 存储 Deployment 名称的数组
declare -a deployment_names=(
  "abc-def-123-abc-gg-Jo-52-1-21"
  "abc-def-123-abc-gg-Jo-49-1-21"
  "abc-def-123-abc-gg-Jo-52-1-22"
  "abc-def-123-abc-gg-Jo-52-1-23"
  "abc-def-123-abc-gg-Jo-51-2-20"
  "abc-def-123-abc-gg-Jo-51-2-19"
  "abc-def-123-abc-gg-Jo-51-1-20"
)

# 存储版本号的数组
declare -a versions=()

# 解析版本号并存储
for name in "${deployment_names[@]}"; do
  version=$(echo "$name" | awk -F'-' '{print $7}')
  versions+=("$version")
done

# 对版本排序去重
versions=($(echo "${versions[@]}"|tr ' ' '\n'|sort -u|tr '\n' ' '))

# 遍历数组并打印每个版本号
echo "Print all of Version"
for version in "${versions[@]}";
    do echo "Version: $version"
done

# 找到最大的 Major 版本
max_major=0

for version in "${versions[@]}"; do
  major=$(echo "$version" | cut -d'-' -f1)
  if [ "$major" -gt "$max_major" ]; then
    max_major="$major"
  fi
done
echo "Print The max_major Version"
echo $max_major

# attempt find 前两个最大值
sorted_versions=($(printf "%s\n" "${versions[@]}" | sort -rV))

# 选择前两个最大值
majormax1="${sorted_versions[0]}"
majormax2="${sorted_versions[1]}"

awk 'BEGIN{while (a++<50) s=s "-"; print s,"split",s}'
echo "majormax1 and majormax2"
echo $majormax1
echo $majormax2

# 存储要保留的 Deployment 名称
declare -a keep_deployments=()

# need delete Deployment
declare -a del_deployments=()

# 根据逻辑筛选要保留的 Deployment
for name in "${deployment_names[@]}"; do
  version=$(echo "$name" | awk -F'-' '{print $7}')
  major=$(echo "$version" | cut -d'-' -f1)
  minor=$(echo "$version" | cut -d'-' -f2)
  # 查提取的主要版本号是否等于$max_major
  if [ "$major" -eq "$max_major" ] || [ "$major" -eq "$majormax2" ]; then
    # 在最大的 Major 版本下保留 2 个小版本,我分析应该是等于最大的都保留了
    # 如果主要版本号等于 `$max_major`，则将当前的 `name` 添加到名为 `keep_deployments` 的数组中，表示要保留这个 `Deployment`
    keep_deployments+=("$name")
    # 一个条件语句的另一个分支，用于检查 `keep_deployments` 数组中的元素数量是否小于 2。如果满足条件，则执行下面的操作
    # 这个其实不是我想要的，我其实关注的版本的大小，而不是数量的问题
    #elif [ "${#keep_deployments[@]}" -lt 2 ]; then
    # 保留其他 Major 版本下的 2 个小版本
    #keep_deployments+=("$name")
    else
      del_deployments+=("$name")
  fi
done



# 输出保留的 Deployment 列表："
awk 'BEGIN{while (a++<50) s=s "-"; print s,"need keep",s}'
for deployment in "${keep_deployments[@]}"; do
  echo "$deployment"
done

awk 'BEGIN{while (a++<50) s=s "-"; print s,"need delete",s}'
# output need delete deployment
for deployment in "${del_deployments[@]}"; do
  echo "$deployment"
done




abc-def-123-abc-gg-jo-2-0-0-deployment
abc-def-123-abc-gg-jo-3-0-0-deployment
abc-def-123-abc-gg-jo-5-0-1-deployment
abc-def-123-abc-gg-jo-5-0-2-deployment
abc-def-123-abc-gg-jo-5-0-3-deployment


#!/bin/bash
# Get all Deployment names

#deployments=$(kubectl get deployments -n spcoe -o jsonpath='{range .items[*]}{.metadata.name} {"\n"}{end}' | grep abc-def-123-abc-gg-jo)
deployments=$(cat /home/lex/deploy.txt)

# Extract the major version numbers from the Deployment names
major_versions=$(echo "$deployments" | awk -F'[-]' '{print $7}' | sort -u)
awk 'BEGIN{while (a++<50) s=s "-"; print s,"split",s}'
echo major_versions
echo $major_versions
# 排序数组
sorted_versions=($(printf "%s\n" "${major_versions[@]}" | sort -rV))
# 选择前两个最大值
majormax1="${sorted_versions[0]}"
majormax2="${sorted_versions[1]}"

awk 'BEGIN{while (a++<50) s=s "-"; print s,"split",s}'
echo "majormax1 and majormax2"
echo $majormax1
echo $majormax2

awk 'BEGIN{while (a++<50) s=s "-"; print s,"split",s}'
# Determine the number of major versions
num_major_versions=$(echo "$major_versions" | wc -l)
echo num_major_versions
echo $num_major_versions

awk 'BEGIN{while (a++<50) s=s "-"; print s,"split",s}'
# Determine the retain policy based on the number of major versions
if [ $num_major_versions -eq 1 ]; then
  # Single major version, retain the last two minor versions
  retain_policy="keep 2 minor versions"
  keep_policy=("$majormax1")
elif [ $num_major_versions -gt 1 ]; then
  # Multiple major versions, retain the last two major versions
  retain_policy=" keep 2 major versions"
  keep_policy=("$majormax1" "$majormax2")
  # My example should Retain major_versions 3 and 5 how to define retain_policy
fi

echo "Retain policy"
echo $retain_policy

echo "keep_policy"
echo "${keep_policy[0]}" # 5
echo "${keep_policy[1]}" # 3

awk 'BEGIN{while (a++<50) s=s "-"; print s,"split",s}'
# Delete all Deployments that do not match the retain policy
for deployment in $deployments; do
  major=$(echo "$deployment" | awk -F'[-]' '{print $7}')
  minor=$(echo "$deployment" | awk -F'[-]' '{print $8}')
  path=$(echo "$deployment" | awk -F'[-]' '{print $9}')
  if [ $major == ${keep_policy[0]} ] || [ $major == ${keep_policy[1]} ]; then
    echo -e "$major == "${keep_policy[0]}" OR $major == "${keep_policy[1]}"\n"
    echo "need keep $deployment"
  else
    echo -e "need delete this one\n"
    echo -e "need delete $deployment\n"
  fi
done

: <<'END'


echo "---------------------------"
# Delete all Deployments that do not match the retain policy
for deployment in $deployments; do
  # Extract the major and minor versions from the Deployment name
  major=$(echo "$deployment" | awk -F'[-]' '{print $7}')
  minor=$(echo "$deployment" | awk -F'[-]' '{print $8}')
  path=$(echo "$deployment" | awk -F'[-]' '{print $9}')
  echo $major
  echo $minor
  echo $path
  # Check if the Deployment matches the retain policy
  if ! echo "{$keep_policy[0]}" | grep -q "$major"; then
    echo "loop "${keep_policy[0]}""
    # Delete the Deployment
    # kubectl delete deployment "$deployment"
    echo "$deployment"
  fi
done

END
``` 


想要保留最大的 Major 版本下的 2 个小版本，
如果只有一个大版本，则保留该大版本下的 2 个小版本，
然后删除其他的 Deployment。
Shell 脚本来实现这个逻辑：

# 执行命令并将输出结果添加到数组中
#deployment_names+=("$(your_command)")

# 示例：将 ls 命令的输出结果添加到数组中
deployment_names+=("$(ls)")

for name in "${deployment_names[@]}"; do
  version=$(echo "$name" )
  versions+=("$version")
done

echo $version



```bash
#!/bin/bash

# 存储 Deployment 名称的数组
declare -a deployment_names=(
  "abc-def-123-abc-gg-Jo-51-2-20"
  "abc-def-123-abc-gg-Jo-52-1-21"
  "abc-def-123-abc-gg-Jo-51-2-19"
  "abc-def-123-abc-gg-Jo-51-1-20"
)

# 存储版本号的数组
declare -a versions=()

# 解析版本号并存储
for name in "${deployment_names[@]}"; do
  version=$(echo "$name" | awk -F'-' '{print $7}')
  versions+=("$version")
done

# 找到最大的 Major 版本
max_major=0

for version in "${versions[@]}"; do
  major=$(echo "$version" | cut -d'-' -f1)
  if [ "$major" -gt "$max_major" ]; then
    max_major="$major"
  fi
done

# 存储要保留的 Deployment 名称
declare -a keep_deployments=()

# 根据逻辑筛选要保留的 Deployment
for name in "${deployment_names[@]}"; do
  version=$(echo "$name" | awk -F'-' '{print $7}')
  major=$(echo "$version" | cut -d'-' -f1)
  minor=$(echo "$version" | cut -d'-' -f2)

  if [ "$major" -eq "$max_major" ]; then
    # 在最大的 Major 版本下保留 2 个小版本
    keep_deployments+=("$name")
  elif [ "${#keep_deployments[@]}" -lt 2 ]; then
    # 保留其他 Major 版本下的 2 个小版本
    keep_deployments+=("$name")
  fi
done

# 输出要保留的 Deployment
echo "要保留的 Deployment 列表："
for deployment in "${keep_deployments[@]}"; do
  echo "$deployment"
done

# 在这里执行删除操作，删除不在 keep_deployments 中的 Deployment
# 例如：kubectl delete deployment 不在 keep_deployments 中的 Deployment
```

这个脚本会解析版本号，并根据你的逻辑筛选要保留的 Deployment 名称。最后，你可以根据输出的要保留的 Deployment 列表执行相应的删除操作（注释部分）。请确保在实际操作中小心谨慎，以避免误删 Deployment。


要保留的 Deployment 列表：
abc-def-123-abc-gg-Jo-51-2-20
abc-def-123-abc-gg-Jo-52-1-21
``` 
这段代码是一个 Bash 脚本片段，用于迭代一个名为 `deployment_names` 的数组，并从每个元素中提取一个版本号，然后将这些版本号存储在名为 `versions` 的数组中。让我详细解释一下：

1. `for name in "${deployment_names[@]}"; do`: 这是一个 for 循环，用于迭代名为 `deployment_names` 的数组中的每个元素，并将每个元素赋值给变量 `name`。

2. `version=$(echo "$name" | awk -F'-' '{print $7}')`: 这一行的目的是从变量 `name` 中提取版本号。让我分解它：
   - `echo "$name"`: 这将输出当前循环中的 `name` 变量的值。
   - `|`: 这是管道符号，它将前一个命令的输出传递给下一个命令。
   - `awk -F'-' '{print $7}'`: 这使用了 `awk` 命令来处理输入的字符串，其中 `-F'-'` 指定了字段分隔符为连字符 `-`。然后，`'{print $7}'` 用于打印第7个字段，即版本号。这假设字符串中使用连字符分隔符，并且版本号位于第7个字段。

3. `versions+=("$version")`: 这一行将提取到的版本号存储在名为 `versions` 的数组中。`+=` 意味着将新的版本号追加到数组的末尾。

所以，循环将遍历 `deployment_names` 数组中的每个元素，提取版本号，并将这些版本号存储在 `versions` 数组中。最终，`versions` 数组将包含所有提取到的版本号。


这段代码是一个 Bash 脚本片段，用于根据一些逻辑筛选要保留的 `Deployment`。我将逐行解释它：

1. `for name in "${deployment_names[@]}"; do`: 这是一个 for 循环，用于迭代名为 `deployment_names` 的数组中的每个元素，并将每个元素赋值给变量 `name`。`"${deployment_names[@]}"` 表示展开数组，以便循环可以访问数组中的每个元素。

2. `version=$(echo "$name" | awk -F'-' '{print $7}')`: 这一行从变量 `name` 中提取版本号，并将其存储在变量 `version` 中。解释如下：
   - `echo "$name"`: 这将输出当前循环中的 `name` 变量的值。
   - `|`: 这是管道符号，它将前一个命令的输出传递给下一个命令。
   - `awk -F'-' '{print $7}'`: 这使用了 `awk` 命令来处理输入的字符串，其中 `-F'-'` 指定了字段分隔符为连字符 `-`。然后，`'{print $7}'` 用于打印第7个字段，即版本号。这假设字符串中使用连字符分隔符，并且版本号位于第7个字段。

3. `major=$(echo "$version" | cut -d'-' -f1)`: 这一行从版本号中提取主要版本号（Major Version），并将其存储在变量 `major` 中。解释如下：
   - `echo "$version"`: 这将输出当前循环中的 `version` 变量的值。
   - `|`: 管道符号，将前一个命令的输出传递给下一个命令。
   - `cut -d'-' -f1`: 这使用了 `cut` 命令来处理输入的字符串，其中 `-d'-'` 指定了字段分隔符为连字符 `-`，而 `-f1` 表示提取第一个字段，即主要版本号。

4. `minor=$(echo "$version" | cut -d'-' -f2)`: 类似于前一行，这一行从版本号中提取次要版本号（Minor Version），并将其存储在变量 `minor` 中。

5. `if [ "$major" -eq "$max_major" ]; then`: 这是一个条件语句，用于检查提取的主要版本号是否等于 `$max_major`。如果相等，则执行下面的操作。

6. `keep_deployments+=("$name")`: 如果主要版本号等于 `$max_major`，则将当前的 `name` 添加到名为 `keep_deployments` 的数组中，表示要保留这个 `Deployment`。

7. `elif [ "${#keep_deployments[@]}" -lt 2 ]; then`: 这是一个条件语句的另一个分支，用于检查 `keep_deployments` 数组中的元素数量是否小于 2。如果满足条件，则执行下面的操作。

8. `keep_deployments+=("$name")`: 如果条件满足，将当前的 `name` 添加到 `keep_deployments` 数组中，表示要保留这个 `Deployment`。

整个循环将根据主要版本号和数组长度来筛选要保留的 `Deployment`。具体规则是：在最大的主要版本号下保留 2 个小版本，而其他主要版本号下也保留 2 个小版本。
``` 

- 假设你已经有了版本号数组 versions
- 遍历数组并打印每个版本号
```bash
for version in "${versions[@]}"; do
  echo "Version: $version"
done
``` 



# google bard
您可以使用以下 shell 脚本来实现您的要求：

```shell
#!/bin/bash

# 获取 deployment 列表
deployments=$(kubectl get deployments --sort=metadata.name | awk '{print $1}')

# 获取所有 deployment 的主版本号
majors=$(echo $deployments | awk '{split($0, a, "-"); print a[2]}' | sort -u)

# 判断主版本数量
num_majors=$(echo $majors | wc -l)

# 遍历 deployment 列表
for deployment in $deployments; do
  # 获取 deployment 的主版本号
  major=$(echo $deployment | cut -d'-' -f2)

  # 判断是否需要保留
  if [ $num_majors -eq 1 ]; then
    # 单主版本
    if [ $major -gt $(echo $majors | head -2 | tail -1) ]; then
      # 保留
      echo "保留 deployment: $deployment"
    else
      # 删除
      echo "删除 deployment: $deployment"
      kubectl delete deployment $deployment
    fi
  else
    # 多主版本
    if [ $major -ge $(echo $majors | head -2 | tail -1) ]; then
      # 保留
      echo "保留 deployment: $deployment"
    else
      # 删除
      echo "删除 deployment: $deployment"
      kubectl delete deployment $deployment
    fi
  fi
done
```

该脚本首先获取 deployment 列表，然后获取所有 deployment 的主版本号。然后，脚本判断主版本数量。如果主版本数量为 1，则脚本将保留该主版本下的前两个次版本。如果主版本数量大于 1，则脚本将保留最大的两个主版本。最后，脚本遍历 deployment 列表，并根据保留策略进行删除。

以下是该脚本的示例输出：

```
保留 deployment: abc-def-hij-abc-gg-Jo-52-1-21
保留 deployment: abc-def-hij-abc-gg-Jo-51-2-20
删除 deployment: abc-def-hij-abc-gg-Jo-51-2-19
删除 deployment: abc-def-hij-abc-gg-Jo-51-1-20
```

您可以根据自己的需要修改该脚本。例如，您可以修改脚本，以保留指定数量的 deployment。

以下是修改脚本的示例：

```shell
#!/bin/bash

# 获取 deployment 列表
deployments=$(kubectl get deployments --sort=metadata.name | awk '{print $1}')

# 获取所有 deployment 的主版本号
majors=$(echo $deployments | awk '{split($0, a, "-"); print a[2]}' | sort -u)

# 判断主版本数量
num_majors=$(echo $majors | wc -l)

# 遍历 deployment 列表
for deployment in $deployments; do
  # 获取 deployment 的主版本号
  major=$(echo $deployment | cut -d'-' -f2)

  # 判断是否需要保留
  if [ $num_majors -eq 1 ]; then
    # 单主版本
    if [ $major -gt $(echo $majors | head -$(($num_to_keep - 1)) | tail -1) ]; then
      # 保留
      echo "保留 deployment: $deployment"
    else
      # 删除
      echo "删除 deployment: $deployment"
      kubectl delete deployment $deployment
    fi
  else
    # 多主版本
    if [ $major -ge $(echo $majors | head -$(($num_to_keep - 1)) | tail -1) ]; then
      # 保留
      echo "保留 deployment: $deployment"
    else
      # 删除
      echo "删除 deployment: $deployment"
      kubectl delete deployment $deployment
    fi
  fi
done
```

该脚本将保留指定数量的 deployment。例如，如果您将 num_to_keep 设置为 2，则脚本将保留两个最新的 deployment。


# claude
您提供的场景我理解了,这里是根据您描述的逻辑,使用shell脚本实现版本清理:

```bash
#!/bin/bash

deployments=$(kubectl get deploy -o name)

# 提取所有版本号
declare -A versions
for deploy in $deployments; do
  major=$(echo $deploy | awk -F- '{print $5}')
  versions[$major]=""
done

# 判断主版本数量
major_list=$(echo "${!versions[@]}" | tr ' ' '\n' | sort -n)
major_num=$(echo "$major_list" | wc -l)

if [ $major_num -eq 1 ]; then
  # 单主版本情况
  latest_minor=$(kubectl get deploy -o jsonpath="{..image}" | cut -d- -f6 | sort -n | tail -n2 | head -n1)

  for deploy in $deployments; do
    minor=$(echo $deploy | awk -F- '{print $6}')
    if [ "$minor" != "$latest_minor" ]; then
      kubectl delete deploy $deploy
    fi
  done

else
  # 多主版本情况
  latest_majors=$(echo "$major_list" | sort -n | tail -n2)

  for deploy in $deployments; do
    major=$(echo $deploy | awk -F- '{print $5}')
    if [[ ! "$major" =~ $latest_majors ]]; then
      kubectl delete deploy $deploy
    fi
  done
fi
```

主要逻辑:

1. 提取所有版本的主版本号
2. 根据主版本数量判断保留策略
3. 单主版本保留最大的两个次版本
4. 多主版本保留最大的两个主版本
5. 删除不符合条件的版本

请您测试并提出修改意见。感谢您提供具体的场景说明,让我可以对shell 编程有更深入的练习。

# calude100k
#!/bin/bash

# 获取所有Deployment名称
deployments=($(kubectl get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'))

# 提取主版本号
major_versions=($(echo "${deployments[*]}" | tr ' ' '\n' | cut -d'-' -f3 | sort -u))

# 如果只有一个主版本
if [ ${#major_versions[*]} -eq 1 ]; then
  major=${major_versions[0]}

  # 获取该主版本下的Deployment
  deps=($(echo "${deployments[*]}" | grep "$major" | sort -r))

  # 保留前两个版本
  keep=${deps[0]}
  keep=${deps[1]}

  # 删除其他版本
  kubectl delete deploy "${deps[@]}"

  exit
fi

# 多个主版本,保留最大的两个版本
keep=("${major_versions[0]}" "${major_versions[1]}")

# 循环Deployment,删除不符合条件的
for d in ${deployments[*]}; do

  major=${d/-*-*-*/}

  if ! [[ " $keep " =~ " $major " ]]; then
    kubectl delete deploy "$d"
  fi

done

主要步骤:

获取所有Deployment名称
提取主版本号
根据主版本数量判断策略
单版保留前两个次版本
多版保留最大两个主版本
删除不符合条件的Deployment

Sure! Here's an example shell script that implements the logic you described:
```bash
#!/bin/bash

# Get all Deployment names
deployments=$(kubectl get deployments --all-namespaces -o jsonpath='{.items[*].metadata.name}')

# Extract the major version numbers from the Deployment names
major_versions=$(echo "$deployments" | awk '{print $NF}' | sort -u)

# Determine the number of major versions
num_major_versions=$(echo "$major_versions" | wc -l)

# Determine the retain policy based on the number of major versions
if [ $num_major_versions -eq 1 ]; then
  # Single major version, retain the last two minor versions
  retain_policy="last 2 minor versions"
elif [ $num_major_versions -gt 1 ]; then
  # Multiple major versions, retain the last two major versions
  retain_policy="last 2 major versions"
fi

# Delete all Deployments that do not match the retain policy
for deployment in $deployments; do
  # Extract the major and minor versions from the Deployment name
  major=$(echo "$deployment" | awk '{print $NF}' | sed 's/-.*//')
  minor=$(echo "$deployment" | awk '{print $NF}' | sed 's/.*-//')

  # Check if the Deployment matches the retain policy
  if ! echo "$retain_policy" | grep -q "$major-$minor"; then
    # Delete the Deployment
    kubectl delete deployment "$deployment"
  fi
done
```
Let me explain how the script works:

1. First, we use `kubectl get deployments --all-namespaces` to get a list of all Deployments in all namespaces. We then use `jsonpath` to extract just the names of the Deployments.
2. Next, we use `awk` to extract the major version numbers from the Deployment names. We use `$NF` to get the last field of each line, which contains the major version number. We then use `sort -u` to remove duplicates and sort the list.
3. We determine the number of major versions using `wc -l`.
4. Based on the number of major versions, we determine the retain policy. If there is only one major version, we retain the last two minor versions. If there are multiple major versions, we retain the last two major versions.
5. We loop through each Deployment and extract the major and minor versions from the Deployment name using `awk` and `sed`. We then check if the Deployment matches the retain policy using `grep`. If it does not match, we delete the Deployment using `kubectl delete deployment`.

Note that this script assumes that the Deployment names have the format `abc-def-hij-abc-gg-Jo-51-2-20`, with the major and minor versions separated by hyphens. If your Deployment names have a different format, you may need to modify the script accordingly.

以下是根据您提供的要求编写的 Bash 脚本来清理 Kubernetes Deployment：

```bash
#!/bin/bash

# Get all Deployment names
deployments=$(kubectl get deployments --all-namespaces -o jsonpath='{.items[*].metadata.name}')

# Extract the major version numbers from the Deployment names
major_versions=$(echo "$deployments" | awk -F'[-]' '{print $(NF-2)}' | sort -u)

# Determine the number of major versions
num_major_versions=$(echo "$major_versions" | wc -l)

# Determine the retain policy based on the number of major versions
if [ $num_major_versions -eq 1 ]; then
  # Single major version, retain the last two minor versions
  retain_policy="last 2 minor versions"
elif [ $num_major_versions -gt 1 ]; then
  # Multiple major versions, retain the last two major versions
  retain_policy="last 2 major versions"
fi

# Delete all Deployments that do not match the retain policy
for deployment in $deployments; do
  # Extract the major and minor versions from the Deployment name
  major=$(echo "$deployment" | awk -F'[-]' '{print $(NF-2)}')
  minor=$(echo "$deployment" | awk -F'[-]' '{print $(NF-1)}')

  # Check if the Deployment matches the retain policy
  if ! echo "$retain_policy" | grep -q "$major-$minor"; then
    # Delete the Deployment
    kubectl delete deployment "$deployment"
  fi
done
```

这段代码是用来检查 Deployment 是否符合保留策略，并根据结果来决定是否删除 Deployment。

让我们逐行解释这段代码的含义：

1. `if ! echo "$retain_policy" | grep -q "$major-$minor"; then`: 这是一个 if 语句，用于检查 Deployment 是否符合保留策略。`$retain_policy` 是保留策略，`$major-$minor` 是当前 Deployment 的主要版本号和次要版本号的组合。`echo "$retain_policy" | grep -q "$major-$minor"` 的作用是在 `$retain_policy` 中搜索 `$major-$minor`，如果找到匹配项，则返回成功（0），否则返回失败（非0）。`!` 是逻辑非运算符，表示取反。因此，`! echo "$retain_policy" | grep -q "$major-$minor"` 的含义是如果 `$retain_policy` 中没有找到 `$major-$minor`，即 Deployment 不符合保留策略，那么执行下面的代码块。

2. `kubectl delete deployment "$deployment"`: 这行代码使用 `kubectl delete` 命令删除不符合保留策略的 Deployment。`"$deployment"` 是当前迭代的 Deployment 名称，通过将其作为参数传递给 `kubectl delete deployment` 命令，可以删除该 Deployment。

因此，如果 Deployment 的主要版本号和次要版本号与保留策略不匹配，那么该 Deployment 将被删除。

请确保已正确设置 Kubernetes 环境，并具有足够的权限来执行 `kubectl` 命令和删除部署。这个脚本会获取所有 Deployment 的名称，并根据您的要求确定保留策略。然后，它会删除不符合保留策略的 Deployment。

请注意，这个脚本假设 Deployment 名称的格式是 `abc-def-hij-abc-gg-Jo-<major>-<minor>-<patch>`，其中 `<major>` 是主版本号，`<minor>` 是次版本号，`<patch>` 是修订版本号。如果您的实际 Deployment 名称格式不同，请适当修改脚本中的正则表达式来提取主版本号和次版本号。

```bash 
#!/bin/bash

# 获取 deployment 列表
deployments=$(kubectl get deployments --sort=metadata.name | awk '{print $1}')

# 获取所有 deployment 的主版本号
majors=$(echo $deployments | awk '{split($0, a, "-"); print a[2]}' | sort -u)

# 判断主版本数量
num_majors=$(echo $majors | wc -l)

# 遍历 deployment 列表
for deployment in $deployments; do
  # 获取 deployment 的主版本号
  major=$(echo $deployment | cut -d'-' -f2)

  # 判断是否需要保留
  if [ $num_majors -eq 1 ]; then
    # 单主版本
    if [ $major -gt $(echo $majors | head -2 | tail -1) ]; then
      # 保留
      echo "保留 deployment: $deployment"
    else
      # 删除
      echo "删除 deployment: $deployment"
      kubectl delete deployment $deployment
    fi
  else
    # 多主版本
    if [ $major -ge $(echo $majors | head -2 | tail -1) ]; then
      # 保留
      echo "保留 deployment: $deployment"
    else
      # 删除
      echo "删除 deployment: $deployment"
      kubectl delete deployment $deployment
    fi
  fi
done
```
