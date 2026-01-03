非常好，这类需求在容量评估和资源预算中非常实用。下面给出一个可直接在任何 `kubectl` 环境中运行的 Shell 脚本，它会：

- 遍历所有命名空间下的 **Deployment**
    
- 统计每个 Deployment 的 `CPU` 与 `Memory` 的 **requests**
    
- 自动汇总成表格
    
- 最后计算出所有 Deployment 的 **总 CPU 与总内存请求值**
    

---

## ✅ 脚本：`k8s-resource-summary.sh`

```bash
#!/bin/bash
# ----------------------------------------------------------
# Script: k8s-resource-summary.sh
# Description: Summarize all Deployments' CPU & Memory requests
# ----------------------------------------------------------

set -e

echo "🔍 Collecting resource requests for all Deployments..."

# 输出表头
printf "%-30s %-20s %-15s %-15s\n" "NAMESPACE" "DEPLOYMENT" "CPU(REQ)" "MEMORY(REQ)"
echo "-------------------------------------------------------------------------------------------"

# 累计变量
total_cpu_m=0
total_mem_mi=0

# 获取所有 namespace + deployment
for ns in $(kubectl get ns --no-headers -o custom-columns=":metadata.name"); do
  for deploy in $(kubectl -n "$ns" get deploy --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true); do

    # 提取 CPU 和 Memory request（取第一个 container 的值）
    cpu=$(kubectl -n "$ns" get deploy "$deploy" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "")
    mem=$(kubectl -n "$ns" get deploy "$deploy" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "")

    # 输出单项
    printf "%-30s %-20s %-15s %-15s\n" "$ns" "$deploy" "${cpu:-N/A}" "${mem:-N/A}"

    # ---- CPU 转换为 m (millicores)
    if [[ -n "$cpu" ]]; then
      if [[ "$cpu" == *m ]]; then
        cpu_m=${cpu%m}
      else
        cpu_m=$(echo "$cpu * 1000" | bc)
      fi
      total_cpu_m=$(echo "$total_cpu_m + $cpu_m" | bc)
    fi

    # ---- Memory 转换为 Mi
    if [[ -n "$mem" ]]; then
      if [[ "$mem" == *Gi ]]; then
        mem_mi=$(echo "${mem%Gi} * 1024" | bc)
      elif [[ "$mem" == *Mi ]]; then
        mem_mi=${mem%Mi}
      else
        mem_mi=0
      fi
      total_mem_mi=$(echo "$total_mem_mi + $mem_mi" | bc)
    fi

  done
done

echo "-------------------------------------------------------------------------------------------"
echo "💡 TOTAL CPU REQUEST: ${total_cpu_m}m"
echo "💡 TOTAL MEMORY REQUEST: ${total_mem_mi}Mi"
echo "✅ Done."
```

---

## 🧪 使用方法

1. 保存脚本：
    
    ```bash
    nano k8s-resource-summary.sh
    ```
    
    粘贴上方代码后保存。
    
2. 赋予执行权限：
    
    ```bash
    chmod +x k8s-resource-summary.sh
    ```
    
3. 运行：
    
    ```bash
    ./k8s-resource-summary.sh
    ```
    

输出示例：

```
NAMESPACE                      DEPLOYMENT           CPU(REQ)        MEMORY(REQ)
default                        api-server           500m            512Mi
default                        frontend             300m            256Mi
kube-system                    metrics-server       100m            200Mi
-------------------------------------------------------------------------------------------
💡 TOTAL CPU REQUEST: 900m
💡 TOTAL MEMORY REQUEST: 968Mi
✅ Done.
```

---

## 💡 说明

- 若某个 Deployment 没设置 request，脚本显示为 `N/A`。
    
- 默认只读取每个 Deployment 的**第一个容器**（常见场景足够）。
    
    > 如果你的 Pod 内含多个容器，可改成累加：
    > 
    > ```bash
    > -o jsonpath='{range .spec.template.spec.containers[*]}{.resources.requests.cpu}{" "}{end}'
    > ```
    
- 使用 `bc` 进行单位换算，确保支持小数。
    

---

是否希望我帮你改成支持 **limits**（即 CPU/Memory 限制值）同时统计？这样你能比较 request 与 limit 的比例。