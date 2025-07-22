```bash
#!/bin/bash

# Cloud Run Job 配置迁移脚本 (使用 jq 版本)
# 用于从源环境提取 Cloud Run Job 配置并生成目标环境的部署命令

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
SOURCE_PROJECT=""
TARGET_PROJECT=""
SOURCE_REGION=""
TARGET_REGION=""
JOB_NAME=""
OUTPUT_FILE=""

# 显示帮助信息
show_help() {
    cat << EOF
Cloud Run Job 配置迁移脚本 (jq 版本)

用法: $0 [选项]

选项:
    -s, --source-project PROJECT     源项目 ID
    -t, --target-project PROJECT     目标项目 ID
    -r, --source-region REGION       源区域 (默认: europe-west2)
    -R, --target-region REGION       目标区域 (默认: 与源区域相同)
    -j, --job-name NAME              Cloud Run Job 名称
    -o, --output FILE                输出文件路径 (可选)
    -h, --help                       显示此帮助信息

示例:
    $0 -s source-project -t target-project -j lextest -r europe-west2
    $0 -s source-project -t target-project -j lextest -o deploy-commands.sh

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--source-project)
                SOURCE_PROJECT="$2"
                shift 2
                ;;
            -t|--target-project)
                TARGET_PROJECT="$2"
                shift 2
                ;;
            -r|--source-region)
                SOURCE_REGION="$2"
                shift 2
                ;;
            -R|--target-region)
                TARGET_REGION="$2"
                shift 2
                ;;
            -j|--job-name)
                JOB_NAME="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}错误: 未知参数 $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

# 验证必需参数
validate_args() {
    if [[ -z "$SOURCE_PROJECT" ]]; then
        echo -e "${RED}错误: 必须指定源项目 (-s)${NC}"
        exit 1
    fi
    
    if [[ -z "$TARGET_PROJECT" ]]; then
        echo -e "${RED}错误: 必须指定目标项目 (-t)${NC}"
        exit 1
    fi
    
    if [[ -z "$JOB_NAME" ]]; then
        echo -e "${RED}错误: 必须指定 Job 名称 (-j)${NC}"
        exit 1
    fi
    
    # 设置默认区域
    if [[ -z "$SOURCE_REGION" ]]; then
        SOURCE_REGION="europe-west2"
    fi
    
    if [[ -z "$TARGET_REGION" ]]; then
        TARGET_REGION="$SOURCE_REGION"
    fi
}

# 检查 gcloud 认证和项目访问
check_access() {
    echo -e "${BLUE}检查项目访问权限...${NC}"
    
    # 检查源项目访问
    if ! gcloud projects describe "$SOURCE_PROJECT" >/dev/null 2>&1; then
        echo -e "${RED}错误: 无法访问源项目 $SOURCE_PROJECT${NC}"
        exit 1
    fi
    
    # 检查目标项目访问
    if ! gcloud projects describe "$TARGET_PROJECT" >/dev/null 2>&1; then
        echo -e "${RED}错误: 无法访问目标项目 $TARGET_PROJECT${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 项目访问权限验证通过${NC}"
}

# 提取 Cloud Run Job 配置
extract_job_config() {
    echo -e "${BLUE}从源环境提取 Job 配置...${NC}"
    
    # 检查 Job 是否存在
    if ! gcloud run jobs describe "$JOB_NAME" --region="$SOURCE_REGION" --project="$SOURCE_PROJECT" >/dev/null 2>&1; then
        echo -e "${RED}错误: 在项目 $SOURCE_PROJECT 的区域 $SOURCE_REGION 中找不到 Job: $JOB_NAME${NC}"
        exit 1
    fi
    
    # 获取完整的 Job 配置 (JSON 格式)
    local job_config
    job_config=$(gcloud run jobs describe "$JOB_NAME" \
        --region="$SOURCE_REGION" \
        --project="$SOURCE_PROJECT" \
        --format="json")
    
    echo "$job_config"
}

# 解析环境变量
parse_env_vars() {
    local job_config="$1"
    local env_vars=""
    
    # 提取普通环境变量 (不包含 valueFrom 的)
    local env_list
    env_list=$(echo "$job_config" | jq -r '
        .spec.template.spec.template.spec.containers[0].env[]? 
        | select(.valueFrom == null) 
        | "\(.name)=\(.value)"
    ' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    
    echo "$env_list"
}

# 解析 Secret 环境变量
parse_secret_env_vars() {
    local job_config="$1"
    local secret_vars=""
    
    # 提取 Secret 环境变量
    local secret_list
    secret_list=$(echo "$job_config" | jq -r '
        .spec.template.spec.template.spec.containers[0].env[]? 
        | select(.valueFrom.secretKeyRef != null) 
        | "\(.name)=\(.valueFrom.secretKeyRef.name):\(.valueFrom.secretKeyRef.key)"
    ' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    
    echo "$secret_list"
}

# 解析其他配置参数
parse_job_params() {
    local job_config="$1"
    
    # 提取镜像
    local image
    image=$(echo "$job_config" | jq -r '.spec.template.spec.template.spec.containers[0].image // ""')
    
    # 提取 CPU
    local cpu
    cpu=$(echo "$job_config" | jq -r '.spec.template.spec.template.spec.containers[0].resources.limits.cpu // "1"')
    
    # 提取内存
    local memory
    memory=$(echo "$job_config" | jq -r '.spec.template.spec.template.spec.containers[0].resources.limits.memory // "512Mi"')
    
    # 提取服务账号
    local service_account
    service_account=$(echo "$job_config" | jq -r '.spec.template.spec.template.spec.serviceAccountName // ""')
    
    # 提取标签
    local labels
    labels=$(echo "$job_config" | jq -r '
        .metadata.labels // {} 
        | to_entries 
        | map("\(.key)=\(.value)") 
        | join(",")
    ' 2>/dev/null)
    
    # 提取 VPC 连接器
    local vpc_connector
    vpc_connector=$(echo "$job_config" | jq -r '.spec.template.spec.template.metadata.annotations."run.googleapis.com/vpc-access-connector" // ""')
    
    # 提取 VPC 出口
    local vpc_egress
    vpc_egress=$(echo "$job_config" | jq -r '.spec.template.spec.template.metadata.annotations."run.googleapis.com/vpc-access-egress" // ""')
    
    # 提取二进制授权
    local binary_authorization
    binary_authorization=$(echo "$job_config" | jq -r '.spec.template.spec.template.metadata.annotations."run.googleapis.com/binary-authorization" // ""')
    
    # 提取任务超时
    local task_timeout
    task_timeout=$(echo "$job_config" | jq -r '.spec.template.spec.template.spec.timeoutSeconds // ""')
    
    # 提取任务重试次数
    local task_attempts
    task_attempts=$(echo "$job_config" | jq -r '.spec.template.spec.backoffLimit // ""')
    
    # 提取并行度
    local parallelism
    parallelism=$(echo "$job_config" | jq -r '.spec.template.spec.parallelism // ""')
    
    # 提取任务数量
    local task_count
    task_count=$(echo "$job_config" | jq -r '.spec.template.spec.completions // ""')
    
    echo "IMAGE=$image"
    echo "CPU=$cpu"
    echo "MEMORY=$memory"
    echo "SERVICE_ACCOUNT=$service_account"
    echo "LABELS=$labels"
    echo "VPC_CONNECTOR=$vpc_connector"
    echo "VPC_EGRESS=$vpc_egress"
    echo "BINARY_AUTHORIZATION=$binary_authorization"
    echo "TASK_TIMEOUT=$task_timeout"
    echo "TASK_ATTEMPTS=$task_attempts"
    echo "PARALLELISM=$parallelism"
    echo "TASK_COUNT=$task_count"
}

# 生成部署命令
generate_deploy_command() {
    local job_config="$1"
    
    echo -e "${BLUE}解析配置参数...${NC}"
    
    # 解析各种参数
    local env_vars
    env_vars=$(parse_env_vars "$job_config")
    
    local secret_vars
    secret_vars=$(parse_secret_env_vars "$job_config")
    
    # 解析其他参数
    local params
    params=$(parse_job_params "$job_config")
    
    # 提取各个参数值
    local image cpu memory service_account labels vpc_connector vpc_egress binary_authorization
    local task_timeout task_attempts parallelism task_count
    eval "$params"
    
    # 构建部署命令
    local deploy_cmd="gcloud run jobs create $JOB_NAME"
    
    # 添加基本参数
    if [[ -n "$image" && "$image" != "null" ]]; then
        deploy_cmd="$deploy_cmd --image=$image"
    fi
    
    deploy_cmd="$deploy_cmd --region=$TARGET_REGION"
    deploy_cmd="$deploy_cmd --project=$TARGET_PROJECT"
    
    # 添加资源限制
    if [[ -n "$cpu" && "$cpu" != "null" && "$cpu" != "" ]]; then
        deploy_cmd="$deploy_cmd --cpu=$cpu"
    fi
    
    if [[ -n "$memory" && "$memory" != "null" && "$memory" != "" ]]; then
        deploy_cmd="$deploy_cmd --memory=$memory"
    fi
    
    # 添加环境变量
    if [[ -n "$env_vars" && "$env_vars" != "null" && "$env_vars" != "" ]]; then
        deploy_cmd="$deploy_cmd --set-env-vars=\"$env_vars\""
    fi
    
    # 添加 Secret 环境变量
    if [[ -n "$secret_vars" && "$secret_vars" != "null" && "$secret_vars" != "" ]]; then
        deploy_cmd="$deploy_cmd --set-secrets=\"$secret_vars\""
    fi
    
    # 添加服务账号
    if [[ -n "$service_account" && "$service_account" != "null" && "$service_account" != "" ]]; then
        deploy_cmd="$deploy_cmd --service-account=$service_account"
    fi
    
    # 添加标签
    if [[ -n "$labels" && "$labels" != "null" && "$labels" != "" ]]; then
        deploy_cmd="$deploy_cmd --labels=\"$labels\""
    fi
    
    # 添加 VPC 连接器
    if [[ -n "$vpc_connector" && "$vpc_connector" != "null" && "$vpc_connector" != "" ]]; then
        deploy_cmd="$deploy_cmd --vpc-connector=$vpc_connector"
    fi
    
    # 添加 VPC 出口
    if [[ -n "$vpc_egress" && "$vpc_egress" != "null" && "$vpc_egress" != "" ]]; then
        deploy_cmd="$deploy_cmd --vpc-egress=$vpc_egress"
    fi
    
    # 添加二进制授权
    if [[ -n "$binary_authorization" && "$binary_authorization" != "null" && "$binary_authorization" != "" ]]; then
        deploy_cmd="$deploy_cmd --binary-authorization=$binary_authorization"
    fi
    
    # 添加任务超时
    if [[ -n "$task_timeout" && "$task_timeout" != "null" && "$task_timeout" != "" ]]; then
        deploy_cmd="$deploy_cmd --task-timeout=${task_timeout}s"
    fi
    
    # 添加任务重试次数
    if [[ -n "$task_attempts" && "$task_attempts" != "null" && "$task_attempts" != "" ]]; then
        deploy_cmd="$deploy_cmd --max-retries=$task_attempts"
    fi
    
    # 添加并行度
    if [[ -n "$parallelism" && "$parallelism" != "null" && "$parallelism" != "" && "$parallelism" != "1" ]]; then
        deploy_cmd="$deploy_cmd --parallelism=$parallelism"
    fi
    
    # 添加任务数量
    if [[ -n "$task_count" && "$task_count" != "null" && "$task_count" != "" && "$task_count" != "1" ]]; then
        deploy_cmd="$deploy_cmd --task-count=$task_count"
    fi
    
    echo "$deploy_cmd"
}

# 输出结果
output_result() {
    local deploy_cmd="$1"
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}生成的部署命令:${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}$deploy_cmd${NC}"
    echo ""
    
    if [[ -n "$OUTPUT_FILE" ]]; then
        cat > "$OUTPUT_FILE" << EOF
#!/bin/bash
# Cloud Run Job 部署命令
# 从项目 $SOURCE_PROJECT 迁移到 $TARGET_PROJECT
# Job 名称: $JOB_NAME
# 生成时间: $(date)

set -e

echo "开始部署 Cloud Run Job: $JOB_NAME"
echo "目标项目: $TARGET_PROJECT"
echo "目标区域: $TARGET_REGION"

$deploy_cmd

echo "部署完成!"
EOF
        chmod +x "$OUTPUT_FILE"
        echo -e "${GREEN}✓ 部署脚本已保存到: $OUTPUT_FILE${NC}"
        echo ""
    fi
    
    echo -e "${BLUE}提示: 你可以复制上面的命令直接执行，或者保存到文件中稍后使用${NC}"
    echo ""
}

# 主函数
main() {
    echo -e "${GREEN}Cloud Run Job 配置迁移脚本 (jq 版本)${NC}"
    echo "=============================================="
    
    parse_args "$@"
    validate_args
    check_access
    
    # 检查 jq 工具
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}错误: 需要安装 jq 工具来解析 JSON${NC}"
        echo "安装方法:"
        echo "  macOS: brew install jq"
        echo "  Ubuntu/Debian: sudo apt-get install jq"
        echo "  CentOS/RHEL: sudo yum install jq"
        exit 1
    fi
    
    local job_config
    job_config=$(extract_job_config)
    
    local deploy_cmd
    deploy_cmd=$(generate_deploy_command "$job_config")
    
    output_result "$deploy_cmd"
    
    echo -e "${GREEN}✓ 迁移脚本执行完成${NC}"
}

# 执行主函数
main "$@"


: << EOF 
gcloud run jobs create lextest \
  --image=gcr.io/source-project/my-app:latest \
  --region=europe-west2 \
  --project=target-project \
  --cpu=1 \
  --memory=768Mi \
  --set-env-vars="ENV=production,VERSION=1.2.3,DEBUG=false" \
  --set-secrets="DB_PASSWORD=db-secret:latest,API_KEY=api-secret:1" \
  --service-account=my-service-account@target-project.iam.gserviceaccount.com \
  --vpc-connector=my-connector \
  --vpc-egress=all-traffic \
  --binary-authorization=default \
  --labels="refresh=image,team=backend"
EOF
```
