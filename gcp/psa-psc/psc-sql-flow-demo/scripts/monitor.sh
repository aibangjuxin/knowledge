#!/bin/bash

# 监控脚本 - 实时监控应用状态

set -e

# 加载环境变量
source "$(dirname "$0")/../setup/env-vars.sh"

echo "📊 PSC 演示应用监控面板"
echo "================================"

# 检查依赖
if ! command -v watch &> /dev/null; then
    echo "❌ 需要安装 watch 命令"
    echo "macOS: brew install watch"
    echo "Ubuntu: sudo apt-get install procps"
    exit 1
fi

# 监控函数
monitor_pods() {
    echo "📦 Pod 状态:"
    kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o wide
    echo ""
}

monitor_services() {
    echo "🔗 服务状态:"
    kubectl get svc -n ${NAMESPACE}
    echo ""
}

monitor_hpa() {
    echo "📈 自动扩缩容状态:"
    kubectl get hpa -n ${NAMESPACE} 2>/dev/null || echo "HPA 未配置"
    echo ""
}

monitor_endpoints() {
    echo "🎯 端点状态:"
    kubectl get endpoints -n ${NAMESPACE}
    echo ""
}

monitor_events() {
    echo "📋 最近事件:"
    kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | tail -5
    echo ""
}

monitor_logs() {
    echo "📝 最近日志:"
    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ ! -z "$POD_NAME" ]; then
        kubectl logs ${POD_NAME} -n ${NAMESPACE} --tail=5 2>/dev/null || echo "无法获取日志"
    else
        echo "没有运行的 Pod"
    fi
    echo ""
}

monitor_database_stats() {
    echo "🗄️  数据库连接统计:"
    POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ ! -z "$POD_NAME" ]; then
        kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- http://localhost:8080/api/v1/db-stats 2>/dev/null | \
        python3 -m json.tool 2>/dev/null | head -10 || echo "无法获取数据库统计"
    else
        echo "没有运行的 Pod"
    fi
    echo ""
}

# 主监控函数
show_dashboard() {
    clear
    echo "📊 PSC 演示应用监控面板 - $(date)"
    echo "================================"
    echo "项目: ${CONSUMER_PROJECT_ID}"
    echo "集群: ${GKE_CLUSTER_NAME}"
    echo "命名空间: ${NAMESPACE}"
    echo "应用: ${APP_NAME}"
    echo "================================"
    echo ""
    
    monitor_pods
    monitor_services
    monitor_hpa
    monitor_endpoints
    monitor_events
    monitor_logs
    monitor_database_stats
    
    echo "按 Ctrl+C 退出监控"
}

# 交互式菜单
show_menu() {
    echo "📊 PSC 演示监控工具"
    echo "==================="
    echo "1. 实时监控面板"
    echo "2. 查看 Pod 详情"
    echo "3. 查看服务详情"
    echo "4. 查看应用日志"
    echo "5. 查看事件"
    echo "6. 测试应用健康状态"
    echo "7. 查看数据库连接统计"
    echo "8. 端口转发到本地"
    echo "9. 进入 Pod Shell"
    echo "0. 退出"
    echo ""
    read -p "请选择操作 (0-9): " choice
}

# 处理菜单选择
handle_choice() {
    case $choice in
        1)
            echo "启动实时监控面板..."
            watch -n 2 "$(declare -f show_dashboard); show_dashboard"
            ;;
        2)
            kubectl describe pods -n ${NAMESPACE} -l app=${APP_NAME}
            ;;
        3)
            kubectl describe svc -n ${NAMESPACE}
            ;;
        4)
            POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}')
            if [ ! -z "$POD_NAME" ]; then
                kubectl logs -f ${POD_NAME} -n ${NAMESPACE}
            else
                echo "没有运行的 Pod"
            fi
            ;;
        5)
            kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp'
            ;;
        6)
            POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}')
            if [ ! -z "$POD_NAME" ]; then
                echo "测试健康检查端点..."
                kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- http://localhost:8080/health | python3 -m json.tool
                echo ""
                echo "测试就绪检查端点..."
                kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- http://localhost:8080/ready | python3 -m json.tool
            else
                echo "没有运行的 Pod"
            fi
            ;;
        7)
            POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}')
            if [ ! -z "$POD_NAME" ]; then
                kubectl exec ${POD_NAME} -n ${NAMESPACE} -- wget -qO- http://localhost:8080/api/v1/db-stats | python3 -m json.tool
            else
                echo "没有运行的 Pod"
            fi
            ;;
        8)
            echo "启动端口转发到本地 8080 端口..."
            echo "访问 http://localhost:8080 来测试应用"
            kubectl port-forward svc/db-app-service 8080:80 -n ${NAMESPACE}
            ;;
        9)
            POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} -o jsonpath='{.items[0].metadata.name}')
            if [ ! -z "$POD_NAME" ]; then
                echo "进入 Pod: ${POD_NAME}"
                kubectl exec -it ${POD_NAME} -n ${NAMESPACE} -- /bin/sh
            else
                echo "没有运行的 Pod"
            fi
            ;;
        0)
            echo "退出监控工具"
            exit 0
            ;;
        *)
            echo "无效选择，请重试"
            ;;
    esac
}

# 主循环
main() {
    # 检查集群连接
    if ! kubectl cluster-info &>/dev/null; then
        echo "❌ 无法连接到 Kubernetes 集群"
        echo "请确保已正确配置 kubectl"
        exit 1
    fi
    
    # 检查命名空间
    if ! kubectl get namespace ${NAMESPACE} &>/dev/null; then
        echo "❌ 命名空间 ${NAMESPACE} 不存在"
        echo "请先运行部署脚本"
        exit 1
    fi
    
    while true; do
        show_menu
        handle_choice
        echo ""
        read -p "按 Enter 继续..."
        clear
    done
}

# 如果直接运行脚本，显示菜单
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi