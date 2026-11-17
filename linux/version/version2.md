# summary
我有下面一组数字组合,对应关系如下
<major>-<minor>-<patch>，其中 <major> 是主版本号，<minor> 是次版本号，<patch> 是修订版本号
52-1-21
52-1-22
52-1-23
51-2-20
51-2-19
51-1-20
49-5-22
我的要求是保留最大的2个<major> 的版本
然后对最大的2个版本中,保留其中 一个最大的版本
最终结果是如下
52-1-23
51-2-20

想保留最大的两个major版本，然后在每个major版本中保留一个最大的版本

```bash
#!/bin/bash

# 原始的数字组合列表
versions=("52-1-21" "52-1-22" "52-1-23" "51-2-20" "51-2-19" "51-1-20" "49-5-22")

# 使用正则表达式从每个版本中提取major部分
majors=($(for version in "${versions[@]}"; do
  echo "$version" | cut -d '-' -f 1
done))

# 找到所有不同的major版本，并排序
unique_majors=($(echo "${majors[@]}" | tr ' ' '\n' | sort -u -n -r))

# 初始化计数器
count=0

# 遍历不同的major版本
for major in "${unique_majors[@]}"; do
  # 找到当前major版本下的所有版本
  major_versions=($(for version in "${versions[@]}"; do
    if [[ $version == "$major"* ]]; then
      echo "$version"
    fi
  done | sort -t '-' -k 3 -n -r))

  # 输出当前major版本下的最大版本
  echo "${major_versions[0]}"

  # 增加计数器
  count=$((count+1))

  # 如果已经输出了两个major版本，退出循环
  if [ $count -eq 2 ]; then
    break
  fi
done


```
