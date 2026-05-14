- dns peering verify

```bash
gcloud dns managed-zones list --format='[box](dnsName, creationTime:sort=1, name, privateVisibilityConfig.networks.networkUrl.basename(),description)'

   # 获取所有 DNS zone 并过滤出 peering zone
   peering_zones=$(gcloud dns managed-zones list --format='csv(name,privateVisibilityConfig.networks.networkUrl.basename())' | awk -F',' '$2 != ""' | cut -d',' -f1)

   # 显示结果
   echo "Peering DNS Zones in $environment:"
   echo "$peering_zones"

   # 获取期望的peering zone列表（这里需要您提供一个方法来获取或定义这个列表）
   expected_zones="zone1 zone2 zone3 zone4 zone5"

   # 验证所有期望的zone是否都存在
   for zone in $expected_zones; do
     if echo "$peering_zones" | grep -q "$zone"; then
       echo "✅ $zone found"
     else
       echo "❌ $zone not found"
     fi
   done


gcloud dns managed-zones list --format='csv[no-heading](dnsName, creationTime, name, privateVisibilityConfig.networks.networkUrl.basename(),description)'




#!/bin/bash

# Usage: ./dns-peering.sh -e ENVIRONMENT
# ENVIRONMENT is the GCP environment like lex-eg, prod-us, etc.

# 定义要检查的新 DNS Peering zones
PEERING_ZONES=("peering-zone1" "peering-zone2" "peering-zone3" "peering-zone4" "peering-zone5")

# 解析输入参数
while getopts "e:" opt; do
  case $opt in
    e)
      ENVIRONMENT=$OPTARG
      ;;
    \?)
      echo "无效的选项: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# 检查是否提供了环境参数
if [ -z "$ENVIRONMENT" ]; then
  echo "请指定环境，例如：-e lex-eg"
  exit 1
fi

# 切换到指定环境
echo "切换到环境: $ENVIRONMENT"
gcloud config set project "$ENVIRONMENT"

# 获取所有 DNS zones 并过滤 DNS Peering zones
echo "获取并过滤 DNS Peering zones..."
EXISTING_ZONES=$(gcloud dns managed-zones list --format='value(name)' | grep -i 'peering')

if [ -z "$EXISTING_ZONES" ]; then
  echo "未找到任何 DNS Peering zones。"
  exit 1
fi

echo "现有的 DNS Peering zones:"
echo "$EXISTING_ZONES"

# 验证所有新的 Peering zones 是否已经添加
echo "验证新添加的 Peering zones..."
for zone in "${PEERING_ZONES[@]}"; do
    if echo "$EXISTING_ZONES" | grep -q "$zone"; then
        echo "Peering zone '$zone' 已经存在。"
    else
        echo "Peering zone '$zone' 尚未添加。"
    fi
done

```

```

```

bolt.new

```bash
#!/bin/bash

# 切换到指定环境
./dns-peering.sh -e lex-eg

# 获取所有 DNS zone 并过滤出 peering zone
gcloud dns managed-zones list --format='table(dnsName,creationTime,name,privateVisibilityConfig.networks.networkUrl.basename(),description)' | grep peering > peering_zones.txt

# 显示结果
echo "DNS Peering Zones:"
cat peering_zones.txt

# 可选：验证新增的 DNS peering zone
# 假设您有一个名为 expected_zones.txt 的文件，包含所有预期的 DNS peering zone
if [ -f expected_zones.txt ]; then
    echo "Verifying new DNS peering zones..."
    while read -r zone; do
        if grep -q "$zone" peering_zones.txt; then
            echo "✅ $zone found"
        else
            echo "❌ $zone not found"
        fi
    done < expected_zones.txt
else
    echo "No expected_zones.txt file found for verification."
fi
```
