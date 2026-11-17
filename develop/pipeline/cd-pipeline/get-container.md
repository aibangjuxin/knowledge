# 获取 Deployment Container 名称的方法

## 问题分析

需要通过 Shell 命令从 Kubernetes Deployment 中提取容器名称。

## 解决方案

### 方法 1: 使用 jsonpath (推荐)

```bash
# 获取单个 deployment 的所有容器名
kubectl get deployment <deployment-name> -n <namespace> \
  -o jsonpath='{.spec.template.spec.containers[*].name}'

# 示例
kubectl get deployment api-server -n production \
  -o jsonpath='{.spec.template.spec.containers[*].name}'
# 输出: app sidecar nginx
```

### 方法 2: 每行显示一个容器名

```bash
# 使用 jsonpath 配合 range
kubectl get deployment api-server -n production \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}'

# 输出:
# app
# sidecar
# nginx
```

### 方法 3: 获取容器名和镜像

```bash
# 同时显示容器名和镜像
kubectl get deployment api-server -n production \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"="}{.image}{"\n"}{end}'

# 输出:
# app=myapp:v1.0
# sidecar=envoy:1.20
# nginx=nginx:1.25
```

### 方法 4: 使用 go-template

```bash
# 格式化输出
kubectl get deployment api-server -n production \
  -o go-template='{{range .spec.template.spec.containers}}{{.name}}{{"\n"}}{{end}}'
```

### 方法 5: 获取所有 Deployment 的容器信息

```bash
# 列出 namespace 中所有 deployment 的容器
kubectl get deployments -n production \
  -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .spec.template.spec.containers[*]}{.name}{";"}{end}{"\n"}{end}'

# 输出:
# api-server|app;sidecar;
# web-frontend|nginx;
# worker|app;
```

## 实用脚本封装

### 脚本 1: 获取容器名列表

```bash
#!/usr/bin/env bash
# get-containers.sh

set -euo pipefail

NAMESPACE="${1:?Namespace required}"
DEPLOYMENT="${2:?Deployment required}"

# 获取容器名数组
mapfile -t CONTAINERS < <(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}')

if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
    echo "No containers found" >&2
    exit 1
fi

# 输出容器名
for container in "${CONTAINERS[@]}"; do
    echo "$container"
done

# 使用示例:
# ./get-containers.sh production api-server
```

### 脚本 2: 获取容器详细信息

```bash
#!/usr/bin/env bash
# get-container-details.sh

set -euo pipefail

NAMESPACE="${1:?Namespace required}"
DEPLOYMENT="${2:?Deployment required}"

echo "Deployment: $NAMESPACE/$DEPLOYMENT"
echo "----------------------------------------"

# 使用 jq 处理 JSON 输出
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | \
jq -r '.spec.template.spec.containers[] | 
  "Name: \(.name)\nImage: \(.image)\nPorts: \(.ports[]?.containerPort // "N/A")\n---"'

# 输出示例:
# Name: app
# Image: myapp:v1.0
# Ports: 8080
# ---
# Name: sidecar
# Image: envoy:1.20
# Ports: 9901
# ---
```

### 脚本 3: 表格格式输出

```bash
#!/usr/bin/env bash
# list-containers-table.sh

set -euo pipefail

NAMESPACE="${1:?Namespace required}"
DEPLOYMENT="${2:?Deployment required}"

printf "%-20s %-40s %-20s\n" "CONTAINER" "IMAGE" "PORTS"
printf "%-20s %-40s %-20s\n" "---------" "-----" "-----"

kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | \
jq -r '.spec.template.spec.containers[] | 
  [.name, .image, (.ports[]?.containerPort // "N/A" | tostring)] | 
  @tsv' | \
while IFS=$'\t' read -r name image ports; do
    printf "%-20s %-40s %-20s\n" "$name" "$image" "$ports"
done
```

## 在原脚本中的应用

### 集成到验证逻辑

```bash
# 验证 container 是否存在
CONTAINER_NAME="$1"
DEPLOYMENT="$2"
NAMESPACE="$3"

# 获取所有容器名
AVAILABLE_CONTAINERS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[*].name}')

# 检查容器是否存在
if [[ ! " $AVAILABLE_CONTAINERS " =~ " $CONTAINER_NAME " ]]; then
    echo "Error: Container '$CONTAINER_NAME' not found" >&2
    echo "Available containers: $AVAILABLE_CONTAINERS" >&2
    exit 1
fi
```

### 自动检测主容器

```bash
# 如果未指定容器名,自动选择第一个容器
get_primary_container() {
    local deployment="$1"
    local namespace="$2"
    
    kubectl get deployment "$deployment" -n "$namespace" \
        -o jsonpath='{.spec.template.spec.containers[0].name}'
}

# 使用
CONTAINER="${CONTAINER:-$(get_primary_container "$DEPLOYMENT" "$NAMESPACE")}"
echo "Using container: $CONTAINER"
```

## 高级用法

### 获取 InitContainers

```bash
# 获取 init containers
kubectl get deployment api-server -n production \
  -o jsonpath='{range .spec.template.spec.initContainers[*]}{.name}{"\n"}{end}'
```

### 获取容器的资源限制

```bash
# 获取容器资源配置
kubectl get deployment api-server -n production -o json | \
jq -r '.spec.template.spec.containers[] | 
  "Container: \(.name)\n" +
  "CPU Request: \(.resources.requests.cpu // "N/A")\n" +
  "CPU Limit: \(.resources.limits.cpu // "N/A")\n" +
  "Memory Request: \(.resources.requests.memory // "N/A")\n" +
  "Memory Limit: \(.resources.limits.memory // "N/A")\n---"'
```

### 批量获取多个 Deployment

```bash
#!/usr/bin/env bash
# batch-get-containers.sh

NAMESPACE="${1:?Namespace required}"

echo "Fetching all deployments in namespace: $NAMESPACE"
echo

# 获取所有 deployment
DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

for deploy in $DEPLOYMENTS; do
    echo "Deployment: $deploy"
    kubectl get deployment "$deploy" -n "$NAMESPACE" \
        -o jsonpath='{range .spec.template.spec.containers[*]}  - {.name} ({.image}){"\n"}{end}'
    echo
done
```

## 完整的容器验证函数

```bash
#!/usr/bin/env bash
# container-validator.sh

# 验证并获取容器信息
validate_container() {
    local namespace="$1"
    local deployment="$2"
    local container="$3"
    
    # 检查 deployment 是否存在
    if ! kubectl get deployment "$deployment" -n "$namespace" &>/dev/null; then
        echo "Error: Deployment '$deployment' not found in namespace '$namespace'" >&2
        return 1
    fi
    
    # 获取所有容器名
    local containers
    mapfile -t containers < <(kubectl get deployment "$deployment" -n "$namespace" \
        -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}')
    
    # 检查是否有容器
    if [[ ${#containers[@]} -eq 0 ]]; then
        echo "Error: No containers found in deployment '$deployment'" >&2
        return 1
    fi
    
    # 验证指定的容器是否存在
    local found=false
    for c in "${containers[@]}"; do
        if [[ "$c" == "$container" ]]; then
            found=true
            break
        fi
    done
    
    if [[ "$found" == false ]]; then
        echo "Error: Container '$container' not found in deployment '$deployment'" >&2
        echo "Available containers:" >&2
        printf '  - %s\n' "${containers[@]}" >&2
        return 1
    fi
    
    # 获取容器当前镜像
    local current_image
    current_image=$(kubectl get deployment "$deployment" -n "$namespace" \
        -o jsonpath="{.spec.template.spec.containers[?(@.name=='$container')].image}")
    
    echo "Validation passed:"
    echo "  Namespace:      $namespace"
    echo "  Deployment:     $deployment"
    echo "  Container:      $container"
    echo "  Current Image:  $current_image"
    
    return 0
}

# 使用示例
validate_container "production" "api-server" "app"
```

## 性能对比

| 方法 | 速度 | 可读性 | 推荐场景 |
|------|------|--------|----------|
| jsonpath | 快 | 中 | 脚本自动化 |
| go-template | 快 | 低 | 复杂格式化 |
| jq | 中 | 高 | 复杂数据处理 |
| custom-columns | 快 | 高 | 表格展示 |

## 注意事项

### 1. 处理空结果

```bash
# 安全的空值处理
CONTAINERS=$(kubectl get deployment "$DEPLOY" -n "$NS" \
  -o jsonpath='{.spec.template.spec.containers[*].name}' 2>/dev/null)

if [[ -z "$CONTAINERS" ]]; then
    echo "No containers found or deployment does not exist"
    exit 1
fi
```

### 2. 处理特殊字符

```bash
# 容器名可能包含特殊字符,使用数组更安全
mapfile -t CONTAINER_ARRAY < <(kubectl get deployment "$DEPLOY" -n "$NS" \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}')

# 安全遍历
for container in "${CONTAINER_ARRAY[@]}"; do
    echo "Processing: $container"
done
```

### 3. 错误处理

```bash
# 完整的错误处理
get_containers() {
    local deploy="$1"
    local ns="$2"
    
    local output
    if ! output=$(kubectl get deployment "$deploy" -n "$ns" \
        -o jsonpath='{.spec.template.spec.containers[*].name}' 2>&1); then
        echo "Error getting containers: $output" >&2
        return 1
    fi
    
    if [[ -z "$output" ]]; then
        echo "No containers found" >&2
        return 1
    fi
    
    echo "$output"
}
```

这些方法可以灵活地获取 Deployment 的容器信息,根据实际需求选择合适的方式即可。