# script
- 1. 这个脚本是是实现了从一个数组中拿到2个最大的major版本
- 2. 删除除2个最大的版本之外的其他版本
- 3. 对1中2个保留的版本可以继续操作
  - 打印2保留的2个版本中每个版本中的最大的
  - 输出不匹配的版本,其实也就是要删除的版本
- 4. 结束

# summary 
这个Shell脚本的目标是从一组Deployment名称中筛选出要保留的部署，并输出需要删除的部署。以下是脚本的主要步骤和逻辑：

1. 定义Deployment名称数组和版本号数组。
2. 使用`awk`命令解析每个Deployment名称，提取版本号，并将其存储在版本号数组中。
3. 对版本号数组进行排序并去重，以获取所有不同的版本号。
4. 遍历版本号数组，打印每个版本号。
5. 找到最大的主版本号。
6. 使用`awk`命令解析Deployment名称，提取主版本号，并比较以找到最大的主版本号。
7. 输出最大的主版本号。
8. 对版本号数组进行逆序排序，以获取前两个最大的版本号。
9. 存储要保留的Deployment名称和需要删除的Deployment名称的数组。
10. 遍历Deployment名称数组，根据特定逻辑筛选要保留的Deployment并将其添加到`keep_deployments`数组中，将其余的Deployment添加到`del_deployments`数组中。
11. 输出要保留的Deployment列表和需要删除的Deployment列表。
12. 遍历要保留的Deployment列表，并将版本号的特定部分提取并存储在新数组`fullversions`中。
13. 创建关联数组`max_versions`，以存储每个主版本号对应的最大版本。
14. 遍历`fullversions`数组，提取主版本号、次版本号和修订版本号，并构建版本字符串进行比较，以找到每个主版本号对应的最大版本。
15. 输出每个主版本号对应的最大版本。
16. 遍历最大版本数组，提取要保留的版本，并存储在`keep_vs`数组中。
17. 输出要保留的版本。
18. 遍历要保留的Deployment列表，检查是否包含要保留的版本，如果不包含，则打印该Deployment名称。

这个脚本的最终目标是确定要保留的Deployment和需要删除的Deployment，并根据一定的版本号逻辑进行筛选。脚本中包含了详细的注释和输出，以帮助理解每个步骤和逻辑。


```bash
#!/usr/local/bin/bash
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
# deployments=$(kubectl get deployments -n spcoe -o jsonpath='{range .items[*]}{.metadata.name} {"\n"}{end}' | grep abc-def-123-abc-gg-jo)
# deployments=$(cat /home/lex/deploy.txt)
# 存储版本号的数组
declare -a versions=()

# 解析Major版本号并存储
for name in "${deployment_names[@]}"; do
  version=$(echo "$name" | awk -F'-' '{print $7}')
  versions+=("$version")
done

# 对主版本排序去重
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
echo "$max_major"
# 按照我后来的逻辑我可不适用这个,直接用$majormax1

# attempt find 前两个最大值
sorted_versions=($(printf "%s\n" "${versions[@]}" | sort -rV))

# 选择前两个最大值
majormax1="${sorted_versions[0]}"
majormax2="${sorted_versions[1]}"

awk 'BEGIN{while (a++<50) s=s "-"; print s,"split",s}'
echo "majormax1 and majormax2"
echo "$majormax1"
echo "$majormax2"

# 存储要保留的 Deployment 名称
declare -a keep_deployments=()

# need delete Deployment 这个是第一次就要删除的一部分
declare -a del_deployments=()

# 根据逻辑筛选要保留的 Deployment
for name in "${deployment_names[@]}"; do
  version=$(echo "$name" | awk -F'-' '{print $7}')
  major=$(echo "$version" | cut -d'-' -f1)
  minor=$(echo "$name" | awk -F'-' '{print $8}')
  path=$(echo "$name" | awk -F'-' '{print $9}')
  # 查提取的主要版本号是否等于$max_major
  if [ "$major" -eq "$majormax1" ] || [ "$major" -eq "$majormax2" ]; then
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


# 其实可以针对保留的这个列表再做判断 保留每个大版本种最大的那一个版本 对于处理之后的结果大于2的时候 进行后续步骤

echo "go on delete"

echo "I will filter keep_deployments"
echo "1 output list"
for deployment in "${keep_deployments[@]}"; do
  echo "$deployment"
done


echo "Only get the version and put it to array"
# 解析版本号并存储
for deployment in "${keep_deployments[@]}"; do
  v=$(echo "$deployment"|awk -F"-" '{print$7"-"$8"-"$9}')
  fullversions+=("$v")
done

# 遍历数组并打印每个版本号
echo "Print all of Version"
for version in "${fullversions[@]}";
    do echo "the full Version: $version"
done

# 创建一个关联数组来存储每个主版本号对应的最大版本
declare -A max_versions
# 输入的关键字列表

#fullversions=("52-1-21" "52-1-22" "52-1-23" "51-2-21" "51-1-21" "51-1-20")

# 遍历关键字列表
for keyword in "${fullversions[@]}"; do
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

# 打印最大版本 其实这个是要保留的版本
for major_version in "${!max_versions[@]}"; do
    echo "最大版本 for 主版本号 $major_version : ${max_versions[$major_version]}"
done


# 打印最大版本 其实这个是要保留的版本 可以把版本单独拿出来
for major_version in "${!max_versions[@]}"; do
    keep_v=$(echo ${max_versions[$major_version]})
    keep_vs+=("$keep_v")
done
awk 'BEGIN{while (a++<50) s=s "-"; print s,"keep version",s}'
echo "Print all of keep_vs"
for kv in "${keep_vs[@]}"; do
    echo "$kv"
done
# 我现在有2个数组
#数组1 ${keep_vs[@]}
#数组2 ${keep_deployments[@]}
#我想要拿数组1里面的数据 去匹配数组2里面数据,如果不包含数据1里的关键字,则打印数据2对应的行,应该如何shell
echo "The next will print delete deloyment"
awk 'BEGIN{while (a++<50) s=s "-"; print s,"will print delete version",s}'

# 遍历数组2中的每个元素
for deployment in "${keep_deployments[@]}"; do
    # 设置标志以指示是否找到匹配
    match_found=false

    # 遍历数组1中的每个关键词
    for keyword in "${keep_vs[@]}"; do
        # 检查当前部署名称是否包含关键词
        if [[ "$deployment" == *"$keyword"* ]]; then
            match_found=true
            break  # 如果找到匹配，退出内部循环
        fi
    done

    # 如果没有找到匹配，则打印当前部署名称
    if [ "$match_found" == false ]; then
        echo "$deployment"
    fi
done
```


# other
```
: << 'END'

-------------------------------------------------- split --------------------------------------------------
majormax1 and majormax2
52
51
-------------------------------------------------- need keep --------------------------------------------------
abc-def-123-abc-gg-Jo-52-1-21
abc-def-123-abc-gg-Jo-52-1-22
abc-def-123-abc-gg-Jo-52-1-23
abc-def-123-abc-gg-Jo-51-2-20
abc-def-123-abc-gg-Jo-51-2-19
abc-def-123-abc-gg-Jo-51-1-20
-------------------------------------------------- need delete --------------------------------------------------
abc-def-123-abc-gg-Jo-49-1-21
bash-5.2$

# 遍历数组 1
for vs in "${keep_vs[@]}"; do
  for v in "${keep_deployments[@]}"; do
    echo $v|grep -v "$vs"
  done
done


最大版本 for 主版本号 52 : 52-1-23
最大版本 for 主版本号 51 : 51-2-20

定义两个数组分别存储所有Deployment名称和解析出的版本号
通过排序、去重得到版本号数组,并打印输出
计算出最大的主版本号,并打印输出
进一步获得两个主版本号最大值,赋值给变量$majormax1和$majormax2
遍历所有Deployment,如果版本主号等于$majormax1或$majormax2,则保留该Deployment
将不保留的Deployment加入待删除数组
输出保留和待删除的两个Deployment列表
从保留列表中进一步提取版本号,并保存到新数组
使用关联数组存储每个主版本号对应的最大版本字符串
打印出每个主版本号的最大版本号
将最大版本号保存到新数组,准备和保留Deployment列表匹配
遍历保留Deployment列表,如果不包含最大版本号,则打印输出,作为最终删除列表
综上,该脚本主要流程是:

解析版本号 -> 计算最大版本 -> 匹配过滤删除版本 -> 输出删除列表



END

```

