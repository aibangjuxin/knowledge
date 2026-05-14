脚本功能

1. 参数验证
   检查参数数量和格式
   验证 deployment 是否存在
   提供清晰的使用说明
2. Pod 选择
   自动获取 deployment 对应的所有 pods
   支持多种标签选择器（app 和 app.kubernetes.io/name）
   交互式选择 pod（如果只有一个则自动选择）
3. 容器选择
   列出选中 pod 中的所有容器
   显示每个容器的镜像信息
   交互式选择目标容器
4. 安全确认
   显示即将执行的操作摘要
   用户确认后才执行

# 基本用法

`./k8s/side.sh deployment-a europe-west2-docker.pkg.dev/project/repo/debug:latest -n namespace`

# 具体示例

`./k8s/side.sh my-app europe-west2-docker.pkg.dev/myproject/containers/curlimages/curl:latest -n production`

```shell
#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 显示使用方法
show_usage() {
    echo "Usage: $0 <deployment-name> <gar-image-path> -n <namespace>"
    echo ""
    echo "Examples:"
    echo "  $0 my-app europe-west2-docker.pkg.dev/project/repo/debug:latest -n default"
    echo "  $0 user-service asia.gcr.io/project/curlimages/curl:latest -n production"
    echo ""
    echo "Parameters:"
    echo "  deployment-name: Name of the deployment to debug"
    echo "  gar-image-path:  Full GAR image path (e.g., region-docker.pkg.dev/project/repo/image:tag)"
    echo "  -n namespace:    Kubernetes namespace"
    exit 1
}

# 检查参数
if [ "$#" -ne 4 ]; then
    echo -e "${RED}Error: Invalid number of arguments${NC}"
    show_usage
fi

DEPLOYMENT_NAME=$1
GAR_IMAGE_PATH=$2
NAMESPACE_FLAG=$3
NAMESPACE=$4

# 验证 -n 参数
if [ "$NAMESPACE_FLAG" != "-n" ]; then
    echo -e "${RED}Error: Third parameter must be '-n'${NC}"
    show_usage
fi

echo -e "${BLUE}=== GKE Ephemeral Container Injection Script ===${NC}"
echo -e "${GREEN}Deployment:${NC} $DEPLOYMENT_NAME"
echo -e "${GREEN}Image:${NC} $GAR_IMAGE_PATH"
echo -e "${GREEN}Namespace:${NC} $NAMESPACE"
echo ""

# 检查 deployment 是否存在
echo -e "${YELLOW}Checking if deployment exists...${NC}"
if ! kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}Error: Deployment '$DEPLOYMENT_NAME' not found in namespace '$NAMESPACE'${NC}"
    exit 1
fi

# 获取 deployment 的 pods
echo -e "${YELLOW}Getting pods for deployment '$DEPLOYMENT_NAME'...${NC}"
# 根据命名规范，如果 deployment 名称以 -deployment 结尾，则 pod 的 app 标签不包含 -deployment 后缀
APP_LABEL="$DEPLOYMENT_NAME"
if [[ "$DEPLOYMENT_NAME" == *-deployment ]]; then
    APP_LABEL="${DEPLOYMENT_NAME%-deployment}"
fi
PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$APP_LABEL" -o jsonpath='{.items[*].metadata.name}')

if [ -z "$PODS" ]; then
    # 尝试其他常见的标签选择器
    PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name="$APP_LABEL" -o jsonpath='{.items[*].metadata.name}')

    # 如果还是找不到，尝试使用原始的 deployment 名称
    if [ -z "$PODS" ]; then
        PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" -o jsonpath='{.items[*].metadata.name}')
    fi
fi

if [ -z "$PODS" ]; then
    echo -e "${RED}Error: No pods found for deployment '$DEPLOYMENT_NAME'${NC}"
    echo -e "${YELLOW}Available deployments in namespace '$NAMESPACE':${NC}"
    kubectl get deployments -n "$NAMESPACE"
    exit 1
fi

# 显示可用的 pods
echo -e "${GREEN}Available pods:${NC}"
POD_ARRAY=($PODS)
for i in "${!POD_ARRAY[@]}"; do
    echo "  $((i+1)). ${POD_ARRAY[i]}"
done

# 选择 pod
if [ ${#POD_ARRAY[@]} -eq 1 ]; then
    SELECTED_POD=${POD_ARRAY[0]}
    echo -e "${GREEN}Auto-selected pod:${NC} $SELECTED_POD"
else
    echo ""
    read -p "Select pod number (1-${#POD_ARRAY[@]}): " POD_CHOICE

    if ! [[ "$POD_CHOICE" =~ ^[0-9]+$ ]] || [ "$POD_CHOICE" -lt 1 ] || [ "$POD_CHOICE" -gt ${#POD_ARRAY[@]} ]; then
        echo -e "${RED}Error: Invalid pod selection${NC}"
        exit 1
    fi

    SELECTED_POD=${POD_ARRAY[$((POD_CHOICE-1))]}
    echo -e "${GREEN}Selected pod:${NC} $SELECTED_POD"
fi

# 获取 pod 中的容器
echo ""
echo -e "${YELLOW}Getting containers in pod '$SELECTED_POD'...${NC}"
CONTAINERS=$(kubectl get pod "$SELECTED_POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}')

if [ -z "$CONTAINERS" ]; then
    echo -e "${RED}Error: No containers found in pod '$SELECTED_POD'${NC}"
    exit 1
fi

# 显示可用的容器
echo -e "${GREEN}Available containers:${NC}"
CONTAINER_ARRAY=($CONTAINERS)
for i in "${!CONTAINER_ARRAY[@]}"; do
    # 获取容器的镜像信息
    CONTAINER_IMAGE=$(kubectl get pod "$SELECTED_POD" -n "$NAMESPACE" -o jsonpath="{.spec.containers[$i].image}")
    echo "  $((i+1)). ${CONTAINER_ARRAY[i]} (image: $CONTAINER_IMAGE)"
done

# 选择目标容器
echo ""
if [ ${#CONTAINER_ARRAY[@]} -eq 1 ]; then
    TARGET_CONTAINER=${CONTAINER_ARRAY[0]}
    echo -e "${GREEN}Auto-selected container:${NC} $TARGET_CONTAINER"
else
    read -p "Select target container number (1-${#CONTAINER_ARRAY[@]}): " CONTAINER_CHOICE

    if ! [[ "$CONTAINER_CHOICE" =~ ^[0-9]+$ ]] || [ "$CONTAINER_CHOICE" -lt 1 ] || [ "$CONTAINER_CHOICE" -gt ${#CONTAINER_ARRAY[@]} ]; then
        echo -e "${RED}Error: Invalid container selection${NC}"
        exit 1
    fi

    TARGET_CONTAINER=${CONTAINER_ARRAY[$((CONTAINER_CHOICE-1))]}
    echo -e "${GREEN}Selected target container:${NC} $TARGET_CONTAINER"
fi

# 确认执行
echo ""
echo -e "${YELLOW}Ready to inject ephemeral container:${NC}"
echo -e "  Pod: ${GREEN}$SELECTED_POD${NC}"
echo -e "  Target Container: ${GREEN}$TARGET_CONTAINER${NC}"
echo -e "  Debug Image: ${GREEN}$GAR_IMAGE_PATH${NC}"
echo -e "  Namespace: ${GREEN}$NAMESPACE${NC}"
echo ""

read -p "Continue? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled${NC}"
    exit 0
fi

# 执行 kubectl debug 命令
echo ""
echo -e "${BLUE}Injecting ephemeral container...${NC}"
echo -e "${YELLOW}Command:${NC} kubectl debug $SELECTED_POD -n $NAMESPACE -it --image=$GAR_IMAGE_PATH --target=$TARGET_CONTAINER"
echo ""

# 检查镜像是否可访问（可选）
echo -e "${YELLOW}Checking image accessibility...${NC}"
if kubectl run temp-check --image="$GAR_IMAGE_PATH" --dry-run=client -o yaml >/dev/null 2>&1; then
    echo -e "${GREEN}Image format appears valid${NC}"
else
    echo -e "${YELLOW}Warning: Image format validation failed, but continuing...${NC}"
fi

echo ""
echo -e "${GREEN}Starting ephemeral container session...${NC}"
echo -e "${YELLOW}Tip: You can now run commands like:${NC}"
echo -e "  curl -H \"Metadata-Flavor: Google\" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
echo -e "  curl http://localhost:8080/health"
echo -e "  wget http://localhost:3000"
echo ""

# 执行实际的 debug 命令
echo "kubectl debug "$SELECTED_POD" -n "$NAMESPACE" -it --image="$GAR_IMAGE_PATH" --target="$TARGET_CONTAINER" -- bash "



echo ""
echo -e "${GREEN}Ephemeral container session ended${NC}"
```

脚本执行流程
验证参数 - 检查 deployment 名称、GAR 镜像路径、命名空间
获取 Pods - 列出 deployment 对应的所有 pods
选择 Pod - 交互式选择或自动选择（单个 pod 时）
列出容器 - 显示选中 pod 中的所有容器及其镜像
选择容器 - 交互式选择目标容器
确认执行 - 显示操作摘要，等待用户确认
注入容器 - 执行 kubectl debug 命令
示例输出

```bash
=== GKE Ephemeral Container Injection Script ===
Deployment: my-app
Image: europe-west2-docker.pkg.dev/project/repo/curl:latest
Namespace: production

Available pods:
  1. my-app-7d4b8c9f5-abc12
  2. my-app-7d4b8c9f5-def34

Select pod number (1-2): 1

Available containers:
  1. main-container (image: my-app:v1.0.0)
  2. sidecar-proxy (image: envoy:v1.20.0)

Select target container number (1-2): 1

Ready to inject ephemeral container:
  Pod: my-app-7d4b8c9f5-abc12
  Target Container: main-container
  Debug Image: europe-west2-docker.pkg.dev/project/repo/curl:latest
  Namespace: production

Continue? (y/N): y

```
