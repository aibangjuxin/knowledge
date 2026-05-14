#!/bin/bash

# POC验证脚本
# 用于验证K8s集群迁移的反向代理方案

set -e

# 配置变量
OLD_HOST="api-name01.teamname.dev.aliyun.intracloud.cn.aibang"
NEW_HOST="api-name01.kong.dev.aliyun.intracloud.cn.aibang"
NAMESPACE="aibang-1111111111-bbdm"
INGRESS_NAME="bbdm"
INGRESS_IP="10.190.192.3"
SERVICE_NAME="new-cluster-proxy"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

success() {
    log "${GREEN}✓ $1${NC}"
}

error() {
    log "${RED}✗ $1${NC}"
}

warning() {
    log "${YELLOW}⚠ $1${NC}"
}

info() {
    log "${BLUE}ℹ $1${NC}"
}

# 检查依赖
check_dependencies() {
    info "检查依赖工具..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl 未安装"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        error "curl 未安装"  
        exit 1
    fi
    
    success "依赖检查通过"
}

# 检查kubectl连接
check_kubectl_connection() {
    info "检查kubectl连接..."
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "无法连接到kubernetes集群"
        exit 1
    fi
    
    local context=$(kubectl config current-context)
    success "已连接到集群: $context"
}

# 备份原始配置
backup_original_config() {
    info "备份原始配置..."
    
    local backup_dir="./poc-backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份ingress
    kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o yaml > "$backup_dir/ingress-original.yaml"
    
    # 备份相关service（如果存在）
    kubectl get service bbdm-api -n $NAMESPACE -o yaml > "$backup_dir/service-original.yaml" 2>/dev/null || true
    
    success "配置已备份到: $backup_dir"
    echo "$backup_dir" > ./.last-backup-path
}

# 创建ExternalName服务
create_external_service() {
    info "创建ExternalName服务..."
    
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_NAME
  namespace: $NAMESPACE
  labels:
    migration: "poc"
    target: "new-cluster"
spec:
  type: ExternalName
  externalName: $NEW_HOST
  ports:
    - name: http
      port: 80
      targetPort: 80
    - name: https
      port: 443
      targetPort: 443
EOF
    
    success "ExternalName服务创建成功"
}

# 更新Ingress配置
update_ingress_config() {
    info "更新Ingress配置为代理模式..."
    
    # 使用kubectl patch更新配置
    kubectl patch ingress $INGRESS_NAME -n $NAMESPACE --type=merge -p "$(cat << EOF
{
  "metadata": {
    "annotations": {
      "migration/status": "poc-testing",
      "migration/target": "$NEW_HOST",
      "migration/timestamp": "$(date -Iseconds)",
      "nginx.ingress.kubernetes.io/upstream-vhost": "$NEW_HOST",
      "nginx.ingress.kubernetes.io/backend-protocol": "HTTP",
      "nginx.ingress.kubernetes.io/proxy-set-headers": "Host $NEW_HOST\\nX-Real-IP \$remote_addr\\nX-Forwarded-For \$proxy_add_x_forwarded_for\\nX-Forwarded-Proto \$scheme\\nX-Original-Host \$host"
    }
  },
  "spec": {
    "rules": [
      {
        "host": "$OLD_HOST",
        "http": {
          "paths": [
            {
              "path": "/",
              "pathType": "ImplementationSpecific",
              "backend": {
                "service": {
                  "name": "$SERVICE_NAME",
                  "port": {
                    "number": 80
                  }
                }
              }
            }
          ]
        }
      }
    ]
  }
}
EOF
)"
    
    success "Ingress配置更新成功"
}

# 等待配置生效
wait_for_config() {
    info "等待配置生效..."
    sleep 30
    success "等待完成"
}

# 验证代理功能
verify_proxy() {
    info "验证代理功能..."
    
    # 测试HTTP请求
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Host: $OLD_HOST" \
        "http://$INGRESS_IP/" || echo "000")
    
    if [[ $response_code =~ ^[23] ]]; then
        success "HTTP代理测试通过 (状态码: $response_code)"
    else
        error "HTTP代理测试失败 (状态码: $response_code)"
        return 1
    fi
    
    # 测试健康检查端点（如果存在）
    local health_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Host: $OLD_HOST" \
        "http://$INGRESS_IP/health" 2>/dev/null || echo "404")
    
    if [[ $health_code =~ ^[23] ]]; then
        success "健康检查端点代理正常 (状态码: $health_code)"
    else
        warning "健康检查端点不可用或不存在 (状态码: $health_code)"
    fi
}

# 性能测试
performance_test() {
    info "执行简单性能测试..."
    
    local start_time=$(date +%s%N)
    curl -s -H "Host: $OLD_HOST" "http://$INGRESS_IP/" > /dev/null
    local end_time=$(date +%s%N)
    
    local duration=$(( (end_time - start_time) / 1000000 ))
    
    if [[ $duration -lt 1000 ]]; then
        success "HTTP响应时间: ${duration}ms (优秀)"
    elif [[ $duration -lt 2000 ]]; then
        success "HTTP响应时间: ${duration}ms (良好)"
    else
        warning "HTTP响应时间: ${duration}ms (需要关注)"
    fi
}

# 检查nginx配置
check_nginx_config() {
    info "检查nginx配置..."
    
    local nginx_pod=$(kubectl get pods -n kube-system -l app=nginx-ingress -o name | head -1)
    
    if [[ -n $nginx_pod ]]; then
        local config_check=$(kubectl exec -n kube-system $nginx_pod -- \
            cat /etc/nginx/nginx.conf | grep -c "$NEW_HOST" || echo "0")
        
        if [[ $config_check -gt 0 ]]; then
            success "nginx配置包含新目标主机"
        else
            warning "nginx配置中未找到新目标主机"
        fi
    else
        warning "未找到nginx-ingress pod"
    fi
}

# 回滚配置
rollback_config() {
    info "执行回滚..."
    
    if [[ -f ./.last-backup-path ]]; then
        local backup_path=$(cat ./.last-backup-path)
        
        if [[ -f "$backup_path/ingress-original.yaml" ]]; then
            kubectl apply -f "$backup_path/ingress-original.yaml"
            kubectl delete service $SERVICE_NAME -n $NAMESPACE 2>/dev/null || true
            success "回滚完成"
        else
            error "备份文件不存在"
            exit 1
        fi
    else
        error "未找到备份路径"
        exit 1
    fi
}

# 显示状态
show_status() {
    info "当前配置状态:"
    
    echo "Ingress信息:"
    kubectl get ingress $INGRESS_NAME -n $NAMESPACE
    
    echo -e "\n代理服务信息:"
    kubectl get service $SERVICE_NAME -n $NAMESPACE 2>/dev/null || echo "代理服务不存在"
    
    echo -e "\nIngress注解:"
    kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o jsonpath='{.metadata.annotations}' | jq . 2>/dev/null || \
    kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o jsonpath='{.metadata.annotations}'
}

# 使用说明
usage() {
    cat << EOF
POC验证脚本

用法:
  $0 deploy     # 部署POC配置
  $0 test       # 测试代理功能
  $0 rollback   # 回滚到原始配置
  $0 status     # 显示当前状态
  $0 full       # 执行完整的POC流程

示例:
  $0 full       # 推荐：执行完整POC验证
  $0 deploy     # 仅部署配置
  $0 test       # 仅测试功能

EOF
}

# 完整POC流程
full_poc() {
    info "开始完整POC验证流程..."
    
    check_dependencies
    check_kubectl_connection
    backup_original_config
    create_external_service
    update_ingress_config
    wait_for_config
    verify_proxy
    performance_test
    check_nginx_config
    
    success "POC验证完成！"
    warning "如需回滚，请执行: $0 rollback"
}

# 主逻辑
case "${1:-}" in
    "deploy")
        check_dependencies
        check_kubectl_connection
        backup_original_config
        create_external_service
        update_ingress_config
        success "POC配置部署完成"
        ;;
    "test")
        check_dependencies
        wait_for_config
        verify_proxy
        performance_test
        check_nginx_config
        ;;
    "rollback")
        check_dependencies
        check_kubectl_connection
        rollback_config
        ;;
    "status")
        check_dependencies
        show_status
        ;;
    "full")
        full_poc
        ;;
    *)
        usage
        exit 1
        ;;
esac