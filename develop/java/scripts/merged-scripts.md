# Shell Scripts Collection

Generated on: 2026-01-05 09:07:42
Directory: /Users/lex/git/knowledge/java/scripts

## `debug-pod.sh`

```bash
#!/bin/bash

set -euo pipefail

usage() { 
  cat << EOF
Usage: $0 -t <target-image> [-s <sidecar-image>] [-n <namespace>]
  -t: Target GAR image (required), e.g., asia-docker.pkg.dev/PROJECT/REPO/java-application:latest
  -s: Sidecar debug image, default: praqma/network-multitool:latest
  -n: Kubernetes namespace, auto-detect current or default: default
  -h: Show this help
EOF
  exit 1
}

# Defaults
SIDECAR_IMAGE="praqma/network-multitool:latest"
NAMESPACE="default"
TARGET_IMAGE=""

# Parse args
while getopts t:s:n:h opt; do
  case \$opt in
    t) TARGET_IMAGE="\$OPTARG" ;;
    s) SIDECAR_IMAGE="\$OPTARG" ;;
    n) NAMESPACE="\$OPTARG" ;;
    h) usage ;;
    \\?) usage ;;
  esac
done

if [ -z "\$TARGET_IMAGE" ]; then
  echo "Error: -t target image is required"
  usage
fi

# Auto-detect namespace if 'default' and kubectl ready
if [ "\$NAMESPACE" = "default" ]; then
  CURRENT_NS=\$(kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}' 2>/dev/null || echo "")
  [ -n "\$CURRENT_NS" ] && NAMESPACE="\$CURRENT_NS"
fi

# Sanitize names
IMAGE_NAME=\$(basename "\${TARGET_IMAGE%:*}")
IMAGE_NAME=\${IMAGE_NAME//[^a-zA-Z0-9-]/-}
DEPLOY_NAME="debug-\$IMAGE_NAME"
YAML_FILE="debug-deploy-\$IMAGE_NAME.yaml"

echo "=== Java Pod Debug Script ==="
echo "Namespace: \$NAMESPACE"
echo "Target Image: \$TARGET_IMAGE"
echo "Sidecar Image: \$SIDECAR_IMAGE"
echo "Deploy Name: \$DEPLOY_NAME"
echo ""

# Generate YAML
cat > "\$YAML_FILE" << YAML_EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: \$DEPLOY_NAME
  namespace: \$NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: \$DEPLOY_NAME
  template:
    metadata:
      labels:
        app: \$DEPLOY_NAME
    spec:
      containers:
      - name: app
        image: \$TARGET_IMAGE
        command: ["/bin/sh", "-c"]
        args: ["sleep 36000"]
        # Add volumeMounts/resources/securityContext if needed
YAML_EOF

echo "Generated YAML: \$YAML_FILE"
echo "Applying..."
kubectl apply -f "\$YAML_FILE" -n "\$NAMESPACE"

echo "Waiting for Deployment rollout (120s timeout)..."
if ! kubectl rollout status deployment/\$DEPLOY_NAME -n "\$NAMESPACE" --timeout=120s; then
  echo "Rollout failed, check: kubectl describe pod -l app=\$DEPLOY_NAME -n \$NAMESPACE"
  exit 1
fi

POD_NAME=\$(kubectl get pods -n "\$NAMESPACE" -l app="\$DEPLOY_NAME" --no-headers -o custom-columns=NAME:.metadata.name | head -1)

echo ""
echo "✅ SUCCESS: Debug Pod is Running!"
echo "Pod Name: \$POD_NAME"
echo ""
echo "🚀 DEBUG COMMAND:"
echo "kubectl debug -it \$POD_NAME -n \$NAMESPACE --image=\$SIDECAR_IMAGE --target=app -- sh"
echo ""
echo "📂 INSIDE DEBUG SHELL:"
echo "  cd /proc/1/root/opt/apps/"
echo "  ls -lah *.jar"
echo "  sha256sum *.jar"
echo "  unzip -l *.jar | grep -i 'spring-boot\\|snakeyaml'"
echo "  unzip -p *.jar META-INF/MANIFEST.MF"
echo ""
echo "🧹 CLEANUP:"
echo "  kubectl delete deployment \$DEPLOY_NAME -n \$NAMESPACE"
echo "  rm \$YAML_FILE"
echo ""
echo "💡 See @java/debug-java-pod.md for full guide.
```

## `debug-java-pod.sh`

```bash
#!/opt/homebrew/bin/bash

################################################################################
# Script Name: debug-java-pod.sh
# Description: 自动创建带 Sidecar 的调试 Deployment 用于分析无法启动的 Java 应用镜像
# Author: Platform SRE Team
# Version: 1.0.0
# Usage: ./debug-java-pod.sh -s <SIDECAR_IMAGE> -t <TARGET_IMAGE> [OPTIONS]
################################################################################

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认值
NAMESPACE="default"
DEPLOYMENT_NAME="java-debug-$(date +%s)"
MOUNT_PATH="/opt/apps"
SIDECAR_IMAGE=""
TARGET_IMAGE=""
DRY_RUN=false
AUTO_EXEC=false
CLEANUP=false

################################################################################
# 函数定义
################################################################################

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示使用说明
usage() {
    cat << EOF
使用说明: $0 -s <SIDECAR_IMAGE> -t <TARGET_IMAGE> [OPTIONS]

必需参数:
    -s, --sidecar IMAGE     Sidecar 调试工具镜像 (如 praqma/network-multitool:latest)
    -t, --target IMAGE      待调试的目标 Java 应用镜像

可选参数:
    -n, --namespace NS      Kubernetes 命名空间 (默认: default)
    -d, --deployment NAME   Deployment 名称 (默认: java-debug-<timestamp>)
    -m, --mount PATH        应用挂载路径 (默认: /opt/apps)
    -e, --exec              创建后自动 exec 进入 Sidecar 容器
    -c, --cleanup           清理之前创建的同名 Deployment
    --dry-run               仅生成 YAML 不实际部署
    -h, --help              显示此帮助信息

示例:
    # 基本用法
    $0 -s asia-docker.pkg.dev/PROJECT/REPO/network-multitool:latest \\
       -t asia-docker.pkg.dev/PROJECT/REPO/java-application:latest

    # 指定命名空间并自动进入容器
    $0 -s praqma/network-multitool:latest \\
       -t my-java-app:v1.0.0 \\
       -n production \\
       -e

    # 仅生成 YAML 文件
    $0 -s nicolaka/netshoot:latest \\
       -t my-app:latest \\
       --dry-run

EOF
    exit 1
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--sidecar)
                SIDECAR_IMAGE="$2"
                shift 2
                ;;
            -t|--target)
                TARGET_IMAGE="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -d|--deployment)
                DEPLOYMENT_NAME="$2"
                shift 2
                ;;
            -m|--mount)
                MOUNT_PATH="$2"
                shift 2
                ;;
            -e|--exec)
                AUTO_EXEC=true
                shift
                ;;
            -c|--cleanup)
                CLEANUP=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                print_error "未知参数: $1"
                usage
                ;;
        esac
    done

    # 验证必需参数
    if [[ -z "$SIDECAR_IMAGE" ]] || [[ -z "$TARGET_IMAGE" ]]; then
        print_error "缺少必需参数"
        usage
    fi
}

# 检查依赖
check_dependencies() {
    print_info "检查依赖工具..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl 未安装或不在 PATH 中"
        exit 1
    fi
    
    print_success "依赖检查通过"
}

# 验证 kubectl 连接
check_kubectl_connection() {
    print_info "验证 Kubernetes 集群连接..."
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "无法连接到 Kubernetes 集群"
        exit 1
    fi
    
    print_success "集群连接正常"
}

# 验证命名空间
check_namespace() {
    print_info "检查命名空间: $NAMESPACE"
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_warning "命名空间 $NAMESPACE 不存在"
        read -p "是否创建命名空间? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl create namespace "$NAMESPACE"
            print_success "命名空间已创建"
        else
            print_error "操作已取消"
            exit 1
        fi
    fi
}

# 清理旧的 Deployment
cleanup_old_deployment() {
    if [[ "$CLEANUP" == true ]]; then
        print_info "检查是否存在旧的 Deployment: $DEPLOYMENT_NAME"
        
        if kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" &> /dev/null; then
            print_warning "发现已存在的 Deployment,正在删除..."
            kubectl delete deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" --wait=true
            print_success "旧 Deployment 已删除"
        fi
    fi
}

# 生成 Deployment YAML
generate_deployment_yaml() {
    local yaml_file="/tmp/${DEPLOYMENT_NAME}.yaml"
    
    print_info "生成 Deployment YAML: $yaml_file" >&2
    
    cat > "$yaml_file" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: java-debug
    purpose: troubleshooting
    created-by: debug-java-pod-script
  annotations:
    description: "Debug deployment for Java application troubleshooting"
    target-image: "${TARGET_IMAGE}"
    sidecar-image: "${SIDECAR_IMAGE}"
    created-at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: java-debug
      deployment: ${DEPLOYMENT_NAME}
  template:
    metadata:
      labels:
        app: java-debug
        deployment: ${DEPLOYMENT_NAME}
    spec:
      volumes:
        - name: app-volume
          emptyDir: {}
      
      containers:
        # 主容器: 待调试的 Java 应用
        - name: target-app
          image: ${TARGET_IMAGE}
          imagePullPolicy: Always
          #imagePullPolicy: Never
          # 覆盖启动命令,防止应用启动失败
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo "========================================";
              echo "Target Container: Debug Mode";
              echo "Image: ${TARGET_IMAGE}";
              echo "Mount Path: ${MOUNT_PATH}";
              echo "========================================";
              echo "Container will sleep for 10 hours...";
              sleep 36000
          volumeMounts:
            - name: app-volume
              mountPath: ${MOUNT_PATH}
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          env:
            - name: DEBUG_MODE
              value: "true"
        
        # Sidecar 容器: 调试工具
        - name: debug-sidecar
          image: ${SIDECAR_IMAGE}
          imagePullPolicy: Always
          #imagePullPolicy: Never
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo "========================================";
              echo "Debug Sidecar: Ready";
              echo "Image: ${SIDECAR_IMAGE}";
              echo "Shared Volume: ${MOUNT_PATH}";
              echo "========================================";
              echo "Available tools:";
              command -v unzip && echo "  ✓ unzip" || echo "  ✗ unzip";
              command -v curl && echo "  ✓ curl" || echo "  ✗ curl";
              command -v wget && echo "  ✓ wget" || echo "  ✗ wget";
              command -v nc && echo "  ✓ nc" || echo "  ✗ nc";
              command -v dig && echo "  ✓ dig" || echo "  ✗ dig";
              command -v jq && echo "  ✓ jq" || echo "  ✗ jq";
              command -v java && echo "  ✓ java" || echo "  ✗ java";
              echo "========================================";
              echo "Sidecar will sleep for 10 hours...";
              sleep 36000
          volumeMounts:
            - name: app-volume
              mountPath: ${MOUNT_PATH}
          resources:
            requests:
              memory: "128Mi"
              cpu: "50m"
            limits:
              memory: "256Mi"
              cpu: "200m"
          env:
            - name: TARGET_IMAGE
              value: "${TARGET_IMAGE}"
            - name: MOUNT_PATH
              value: "${MOUNT_PATH}"
      
      restartPolicy: Always
EOF

    echo "$yaml_file"
}

# 部署 Deployment
deploy_deployment() {
    local yaml_file="$1"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "Dry-run 模式: 仅显示 YAML 内容" >&2
        echo "" >&2
        cat "$yaml_file"
        echo "" >&2
        print_info "YAML 文件已保存至: $yaml_file" >&2
        return
    fi
    
    print_info "部署 Deployment: $DEPLOYMENT_NAME"
    
    if kubectl apply -f "$yaml_file"; then
        print_success "Deployment 已创建"
    else
        print_error "Deployment 创建失败"
        exit 1
    fi
}

# 等待 Pod 就绪
wait_for_pod() {
    if [[ "$DRY_RUN" == true ]]; then
        return
    fi
    
    print_info "等待 Pod 就绪..."
    
    local max_wait=120
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local pod_status=$(kubectl get pods -n "$NAMESPACE" \
            -l "deployment=${DEPLOYMENT_NAME}" \
            -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
        
        if [[ "$pod_status" == "Running" ]]; then
            print_success "Pod 已就绪"
            return
        fi
        
        echo -n "."
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    echo ""
    print_error "Pod 启动超时"
    print_info "请检查 Pod 状态: kubectl get pods -n $NAMESPACE -l deployment=${DEPLOYMENT_NAME}"
    exit 1
}

# 显示 Pod 信息
show_pod_info() {
    if [[ "$DRY_RUN" == true ]]; then
        return
    fi
    
    local pod_name=$(kubectl get pods -n "$NAMESPACE" \
        -l "deployment=${DEPLOYMENT_NAME}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$pod_name" ]]; then
        print_error "未找到 Pod"
        return
    fi
    
    echo ""
    print_info "=========================================="
    print_success "调试环境已就绪!"
    print_info "=========================================="
    echo ""
    echo "  Namespace:   $NAMESPACE"
    echo "  Deployment:  $DEPLOYMENT_NAME"
    echo "  Pod:         $pod_name"
    echo "  Target:      $TARGET_IMAGE"
    echo "  Sidecar:     $SIDECAR_IMAGE"
    echo "  Mount Path:  $MOUNT_PATH"
    echo ""
    print_info "=========================================="
    echo ""
    
    # 显示容器状态
    print_info "容器状态:"
    kubectl get pod "$pod_name" -n "$NAMESPACE" \
        -o jsonpath='{range .status.containerStatuses[*]}{.name}{"\t"}{.state}{"\n"}{end}' | \
        awk '{print "  - " $0}'
    echo ""
    
    # 显示常用命令
    print_info "常用命令:"
    echo ""
    echo "  # 进入 Sidecar 容器"
    echo "  kubectl exec -it $pod_name -n $NAMESPACE -c debug-sidecar -- /bin/sh"
    echo ""
    echo "  # 查看目标容器日志"
    echo "  kubectl logs $pod_name -n $NAMESPACE -c target-app"
    echo ""
    echo "  # 查看 Sidecar 日志"
    echo "  kubectl logs $pod_name -n $NAMESPACE -c debug-sidecar"
    echo ""
    echo "  # 检查 JAR 包"
    echo "  kubectl exec -it $pod_name -n $NAMESPACE -c debug-sidecar -- ls -lh $MOUNT_PATH"
    echo ""
    echo "  # 删除调试 Deployment"
    echo "  kubectl delete deployment $DEPLOYMENT_NAME -n $NAMESPACE"
    echo ""
}

# 自动进入 Sidecar
auto_exec_sidecar() {
    if [[ "$AUTO_EXEC" == false ]] || [[ "$DRY_RUN" == true ]]; then
        return
    fi
    
    local pod_name=$(kubectl get pods -n "$NAMESPACE" \
        -l "deployment=${DEPLOYMENT_NAME}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$pod_name" ]]; then
        print_error "未找到 Pod,无法自动 exec"
        return
    fi
    
    print_info "自动进入 Sidecar 容器..."
    echo ""
    
    kubectl exec -it "$pod_name" -n "$NAMESPACE" -c debug-sidecar -- /bin/sh
}

################################################################################
# 主流程
################################################################################

main() {
    print_info "=========================================="
    print_info "Java Pod Debug Script v1.0.0"
    print_info "=========================================="
    echo ""
    
    # 解析参数
    parse_args "$@"
    
    # 检查依赖
    check_dependencies
    check_kubectl_connection
    check_namespace
    
    # 清理旧资源
    cleanup_old_deployment
    
    # 生成并部署
    local yaml_file=$(generate_deployment_yaml)
    deploy_deployment "$yaml_file"
    
    # 等待就绪
    wait_for_pod
    
    # 显示信息
    show_pod_info
    
    # 自动进入容器
    auto_exec_sidecar
    
    print_success "脚本执行完成"
}

# 执行主流程
main "$@"

```

## `test-dry-run.sh`

```bash
#!/bin/bash
# Simulate the dry-run output
echo "[INFO] ==========================================" >&2
echo "[INFO] Java Pod Debug Script v1.0.0" >&2
echo "[INFO] ==========================================" >&2
echo "" >&2
echo "[INFO] 检查依赖工具..." >&2
echo "[SUCCESS] 依赖检查通过" >&2
echo "[WARNING] Dry-run 模式: 仅显示 YAML 内容" >&2
echo "" >&2

# This is the YAML output (to stdout)
cat << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-debug-1234567890
  namespace: lex
  labels:
    app: java-debug
    purpose: troubleshooting
spec:
  replicas: 1
  selector:
    matchLabels:
      app: java-debug
  template:
    metadata:
      labels:
        app: java-debug
    spec:
      containers:
        - name: target-app
          image: target_image
        - name: debug-sidecar
          image: sidecar_image
EOF

echo "" >&2
echo "[INFO] YAML 文件已保存至: /tmp/java-debug-1234567890.yaml" >&2

```

