#!/bin/bash

# 带校验功能的Docker构建脚本
# 在构建时注入Git信息，支持容器内校验

set -e

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

function log_info() { echo -e "${GREEN}[BUILD]${NC} $1"; }
function log_warn() { echo -e "${YELLOW}[BUILD]${NC} $1"; }
function log_error() { echo -e "${RED}[BUILD]${NC} $1"; }
function log_debug() { echo -e "${BLUE}[BUILD]${NC} $1"; }

# 默认配置
DEFAULT_IMAGE_NAME="my-agent"
DEFAULT_REGISTRY="europe-west2-docker.pkg.dev"
DEFAULT_PROJECT="myproject"
DEFAULT_REPOSITORY="containers"

function usage() {
    cat << EOF
用法: $0 [选项]

选项:
    -n, --name          镜像名称 (默认: $DEFAULT_IMAGE_NAME)
    -r, --registry      镜像仓库地址 (默认: $DEFAULT_REGISTRY)
    -p, --project       GCP项目 (默认: $DEFAULT_PROJECT)
    --repository        Artifact Registry仓库 (默认: $DEFAULT_REPOSITORY)
    --push              构建后推送镜像
    --no-cache          不使用构建缓存
    -h, --help          显示帮助信息

示例:
    $0 --name my-agent --push
    $0 --name my-agent --project myproject-prd --push
EOF
}

# 解析命令行参数
IMAGE_NAME="$DEFAULT_IMAGE_NAME"
REGISTRY="$DEFAULT_REGISTRY"
PROJECT="$DEFAULT_PROJECT"
REPOSITORY="$DEFAULT_REPOSITORY"
PUSH_IMAGE=false
NO_CACHE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT="$2"
            shift 2
            ;;
        --repository)
            REPOSITORY="$2"
            shift 2
            ;;
        --push)
            PUSH_IMAGE=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
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

# 获取Git信息
function get_git_info() {
    local git_branch=""
    local git_commit=""
    
    # 获取分支名
    if git rev-parse --git-dir > /dev/null 2>&1; then
        git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    else
        log_warn "不在Git仓库中，使用默认值"
        git_branch="unknown"
        git_commit="unknown"
    fi
    
    # 如果是CI环境，尝试从环境变量获取
    if [[ "$git_branch" == "HEAD" ]] || [[ -n "$CI" ]]; then
        # GitLab CI
        if [[ -n "$CI_COMMIT_REF_NAME" ]]; then
            git_branch="$CI_COMMIT_REF_NAME"
            git_commit="$CI_COMMIT_SHORT_SHA"
        # GitHub Actions
        elif [[ -n "$GITHUB_REF_NAME" ]]; then
            git_branch="$GITHUB_REF_NAME"
            git_commit="$GITHUB_SHA"
            git_commit="${git_commit:0:8}"  # 取前8位
        # Cloud Build
        elif [[ -n "$BRANCH_NAME" ]]; then
            git_branch="$BRANCH_NAME"
            git_commit="$SHORT_SHA"
        fi
    fi
    
    echo "$git_branch" "$git_commit"
}

# 构建镜像
function build_image() {
    local git_info=($(get_git_info))
    local git_branch="${git_info[0]}"
    local git_commit="${git_info[1]}"
    local build_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local build_user=$(whoami)
    
    # 生成镜像标签
    local image_tag="${git_branch}-${git_commit}"
    local full_image_url="${REGISTRY}/${PROJECT}/${REPOSITORY}/${IMAGE_NAME}:${image_tag}"
    
    log_info "🏗️  开始构建镜像..."
    log_info "镜像名称: $IMAGE_NAME"
    log_info "完整URL: $full_image_url"
    log_info "Git分支: $git_branch"
    log_info "Git提交: $git_commit"
    log_info "构建时间: $build_time"
    log_info "构建用户: $build_user"
    
    # 构建Docker命令
    local docker_cmd="docker build"
    
    # 添加构建参数
    docker_cmd+=" --build-arg GIT_BRANCH='$git_branch'"
    docker_cmd+=" --build-arg GIT_COMMIT='$git_commit'"
    docker_cmd+=" --build-arg BUILD_TIME='$build_time'"
    docker_cmd+=" --build-arg BUILD_USER='$build_user'"
    
    # 添加标签
    docker_cmd+=" -t '$full_image_url'"
    docker_cmd+=" -t '${REGISTRY}/${PROJECT}/${REPOSITORY}/${IMAGE_NAME}:latest'"
    
    # 添加其他选项
    if [[ "$NO_CACHE" == "true" ]]; then
        docker_cmd+=" --no-cache"
    fi
    
    docker_cmd+=" ."
    
    log_debug "执行命令: $docker_cmd"
    
    # 执行构建
    if eval "$docker_cmd"; then
        log_info "✅ 镜像构建成功"
        echo "$full_image_url" > .last-built-image
    else
        log_error "❌ 镜像构建失败"
        return 1
    fi
    
    # 推送镜像
    if [[ "$PUSH_IMAGE" == "true" ]]; then
        log_info "📤 推送镜像到仓库..."
        
        # 配置Docker认证
        if ! docker push "$full_image_url"; then
            log_error "❌ 镜像推送失败"
            log_error "请确保已正确配置Docker认证:"
            log_error "gcloud auth configure-docker $REGISTRY"
            return 1
        fi
        
        # 也推送latest标签
        if ! docker push "${REGISTRY}/${PROJECT}/${REPOSITORY}/${IMAGE_NAME}:latest"; then
            log_warn "⚠️  latest标签推送失败"
        fi
        
        log_info "✅ 镜像推送成功"
    fi
    
    return 0
}

# 验证构建环境
function validate_build_environment() {
    log_info "🔍 验证构建环境..."
    
    # 检查Docker
    if ! command -v docker >/dev/null 2>&1; then
        log_error "❌ Docker未安装或不在PATH中"
        return 1
    fi
    
    # 检查Docker守护进程
    if ! docker info >/dev/null 2>&1; then
        log_error "❌ Docker守护进程未运行"
        return 1
    fi
    
    # 检查Dockerfile
    if [[ ! -f "Dockerfile" ]]; then
        log_error "❌ 当前目录中未找到Dockerfile"
        return 1
    fi
    
    log_info "✅ 构建环境验证通过"
    return 0
}

# 主函数
function main() {
    log_info "🚀 开始带校验功能的镜像构建..."
    
    # 验证构建环境
    if ! validate_build_environment; then
        exit 1
    fi
    
    # 构建镜像
    if ! build_image; then
        exit 1
    fi
    
    log_info "🎉 构建流程完成!"
    
    # 显示使用说明
    if [[ -f ".last-built-image" ]]; then
        local built_image=$(cat .last-built-image)
        log_info "📋 构建的镜像: $built_image"
        log_info "💡 部署命令示例:"
        echo "gcloud run jobs deploy my-agent-4 \\"
        echo "  --image=$built_image \\"
        echo "  --region=europe-west2 \\"
        echo "  --project=$PROJECT"
    fi
}

main "$@"