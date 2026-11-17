#!/bin/bash

# 安全的Cloud Run部署脚本
# 集成镜像分支校验功能

set -e

# 默认配置
DEFAULT_REGION="europe-west2"
DEFAULT_PROJECT="myproject"
MASTER_BRANCH_PREFIX="master"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

function usage() {
    cat << EOF
用法: $0 [选项]

选项:
    -n, --name          服务名称 (必需)
    -i, --image         镜像URL (必需)
    -e, --env           环境 (dev/test/prd) (必需)
    -r, --region        部署区域 (默认: $DEFAULT_REGION)
    -p, --project       GCP项目 (默认: $DEFAULT_PROJECT)
    --skip-validation   跳过分支校验 (仅用于紧急情况)
    -h, --help          显示帮助信息

示例:
    $0 -n my-agent-4 -i europe-west2-docker.pkg.dev/myproject/containers/my-agent:master-v1.0.0 -e prd
EOF
}

function log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
function log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
function log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
function log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            SERVICE_NAME="$2"
            shift 2
            ;;
        -i|--image)
            IMAGE_URL="$2"
            shift 2
            ;;
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT="$2"
            shift 2
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done

# 设置默认值
REGION=${REGION:-$DEFAULT_REGION}
PROJECT=${PROJECT:-$DEFAULT_PROJECT}
SKIP_VALIDATION=${SKIP_VALIDATION:-false}

# 参数校验
function validate_required_params() {
    local missing_params=()
    
    [[ -z "$SERVICE_NAME" ]] && missing_params+=("service name (-n)")
    [[ -z "$IMAGE_URL" ]] && missing_params+=("image URL (-i)")
    [[ -z "$ENVIRONMENT" ]] && missing_params+=("environment (-e)")
    
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        log_error "缺少必需参数: ${missing_params[*]}"
        usage
        exit 1
    fi
}

# 生产环境检查
function is_production_env() {
    local env=$(echo "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')
    [[ "$env" =~ ^(prd|prod|production)$ ]]
}

# 镜像分支校验
function validate_image_branch() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_warn "⚠️  跳过分支校验 (--skip-validation 已启用)"
        return 0
    fi
    
    if ! is_production_env; then
        log_info "非生产环境，跳过分支校验"
        return 0
    fi
    
    log_warn "🔒 生产环境检测，执行严格分支校验..."
    
    # 提取镜像标签
    local image_tag=$(echo "$IMAGE_URL" | sed 's/.*://')
    log_debug "镜像标签: $image_tag"
    
    # 检查是否以master开头
    if [[ "$image_tag" == "$MASTER_BRANCH_PREFIX"* ]]; then
        log_info "✅ 分支校验通过: 镜像来自master分支"
        return 0
    else
        log_error "❌ 分支校验失败!"
        log_error "生产环境只能部署master分支的镜像"
        log_error "当前标签: $image_tag"
        log_error "要求前缀: $MASTER_BRANCH_PREFIX"
        log_error ""
        log_error "如果这是紧急部署，可以使用 --skip-validation 参数"
        return 1
    fi
}

# 构建gcloud命令
function build_deploy_command() {
    local cmd="gcloud run jobs deploy $SERVICE_NAME"
    cmd+=" --image=$IMAGE_URL"
    cmd+=" --region=$REGION"
    cmd+=" --project=$PROJECT"
    
    # 根据环境添加特定配置
    case "$ENVIRONMENT" in
        "prd"|"prod"|"production")
            cmd+=" --vpc-connector=vpc-conn-europe"
            cmd+=" --vpc-egress=all-traffic"
            cmd+=" --max-retries=3"
            cmd+=" --set-env-vars=env=prd,region=uk,version=release_17.0.0"
            cmd+=" --set-secrets=cloud_run_secret=cloud_run_prod:latest"
            cmd+=" --task-timeout=10m"
            cmd+=" --cpu=2"
            cmd+=" --memory=1Gi"
            cmd+=" --key=projects/my-kms-project/locations/europe-west2/keyRings/run/cryptoKeys/HSMrunSharedKey"
            cmd+=" --service-account=prod-mgmt@myproject.iam.gserviceaccount.com"
            ;;
        "test")
            cmd+=" --set-env-vars=env=test,region=uk"
            cmd+=" --cpu=1"
            cmd+=" --memory=512Mi"
            cmd+=" --service-account=test-mgmt@myproject.iam.gserviceaccount.com"
            ;;
        *)
            cmd+=" --set-env-vars=env=dev,region=uk"
            cmd+=" --cpu=0.5"
            cmd+=" --memory=256Mi"
            cmd+=" --service-account=dev-mgmt@myproject.iam.gserviceaccount.com"
            ;;
    esac
    
    echo "$cmd"
}

# 主函数
function main() {
    log_info "🚀 开始Cloud Run安全部署流程"
    log_info "服务名称: $SERVICE_NAME"
    log_info "镜像: $IMAGE_URL"
    log_info "环境: $ENVIRONMENT"
    log_info "区域: $REGION"
    log_info "项目: $PROJECT"
    
    # 参数校验
    validate_required_params
    
    # 分支校验
    if ! validate_image_branch; then
        exit 1
    fi
    
    # 构建部署命令
    local deploy_cmd=$(build_deploy_command)
    
    log_info "📋 即将执行的部署命令:"
    echo "$deploy_cmd"
    echo
    
    # 生产环境需要确认
    if is_production_env; then
        log_warn "⚠️  这是生产环境部署!"
        read -p "确认继续? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "部署已取消"
            exit 0
        fi
    fi
    
    # 执行部署
    log_info "🔄 开始部署..."
    if eval "$deploy_cmd"; then
        log_info "✅ 部署成功完成!"
    else
        log_error "❌ 部署失败!"
        exit 1
    fi
}

main "$@"