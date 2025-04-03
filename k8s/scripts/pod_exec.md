```bash
#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查参数
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 -n <namespace> <deployment-name> [command]"
    echo "Example:"
    echo "  $0 -n default my-deployment              # 进入交互式shell"
    echo "  $0 -n default my-deployment /usr/bin/pip freeze  # 执行指定命令"
    exit 1
fi

# 解析参数
while getopts "n:" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG";;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND-1))
DEPLOYMENT=$1
COMMAND=${@:2}

echo -e "${BLUE}在命名空间 ${NAMESPACE} 中查找 Deployment: ${DEPLOYMENT} 的第一个 Pod${NC}\n"

# 获取第一个 pod
POD=$(kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT} --no-headers -o custom-columns=":metadata.name" | head -n 1)

if [ -z "$POD" ]; then
    echo -e "${YELLOW}错误: 在命名空间 ${NAMESPACE} 中未找到 Deployment ${DEPLOYMENT} 的 Pod${NC}"
    exit 1
fi

echo -e "${GREEN}已找到 Pod: ${POD}${NC}"

# 如果没有提供命令，则进入交互式shell，否则执行指定命令
if [ -z "$COMMAND" ]; then
    echo -e "${BLUE}正在进入 Pod 的交互式 shell...${NC}"
    kubectl exec -it ${POD} -n ${NAMESPACE} -- sh -c "(bash || ash || sh)"
else
    echo -e "${BLUE}正在执行命令: ${COMMAND}${NC}"
    kubectl exec ${POD} -n ${NAMESPACE} -- $COMMAND
fi
```