#!/bin/bash
#
# gcp-logging-quick-setup.sh - GCP 日志成本优化快速设置脚本
#
# 此脚本提供了快速设置 GCP 日志成本优化的交互式界面
# 支持多环境配置和一键部署
#
# 使用方法:
# ./gcp-logging-quick-setup.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${PURPLE}$1${NC}"
}

# 显示欢迎信息
show_welcome() {
    clear
    log_header "========================================"
    log_header "    GCP 日志成本优化快速设置工具"
    log_header "========================================"
    echo ""
    echo "此工具将帮助您："
    echo "1. 审计当前日志配置"
    echo "2. 设置成本优化策略"
    echo "3. 部署 Terraform 配置"
    echo "4. 生成监控和告警"
    echo ""
}

# 检查必要工具
check_tools() {
    log_info "检查必要工具..."
    
    local missing_tools=()
    
    if ! command -v gcloud &> /dev/null; then
        missing_tools+=("gcloud")
    fi
    
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "缺少必要工具: ${missing_tools[*]}"
        echo ""
        echo "请安装缺少的工具后重新运行此脚本"
        echo ""
        echo "安装指南:"
        echo "- gcloud: https://cloud.google.com/sdk/docs/install"
        echo "- terraform: https://learn.hashicorp.com/tutorials/terraform/install-cli"
        echo "- python3: https://www.python.org/downloads/"
        exit 1
    fi
    
    log_success "所有必要工具已安装"
}

# 获取项目信息
get_project_info() {
    echo ""
    log_info "配置项目信息..."
    
    # 获取当前项目
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [ -n "$current_project" ]; then
        echo "当前活动项目: $current_project"
        read -p "是否使用当前项目? (y/n): " use_current
        if [[ $use_current =~ ^[Yy]$ ]]; then
            PROJECT_ID="$current_project"
        fi
    fi
    
    if [ -z "$PROJECT_ID" ]; then
        read -p "请输入 GCP 项目 ID: " PROJECT_ID
    fi
    
    # 验证项目访问权限
    if ! gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
        log_error "无法访问项目 $PROJECT_ID，请检查权限"
        exit 1
    fi
    
    log_success "项目配置完成: $PROJECT_ID"
}

# 选择环境类型
select_environment() {
    echo ""
    log_info "选择环境类型..."
    
    echo "请选择环境类型:"
    echo "1) 开发环境 (dev) - 7天保留，ERROR+级别，激进成本优化"
    echo "2) 测试环境 (test) - 14天保留，WARNING+级别，中等成本优化"
    echo "3) 预生产环境 (staging) - 30天保留，INFO+级别，保守成本优化"
    echo "4) 生产环境 (prod) - 90天保留，INFO+级别，最小成本优化"
    
    while true; do
        read -p "请选择 (1-4): " env_choice
        case $env_choice in
            1) ENVIRONMENT="dev"; break;;
            2) ENVIRONMENT="test"; break;;
            3) ENVIRONMENT="staging"; break;;
            4) ENVIRONMENT="prod"; break;;
            *) echo "请输入有效选项 (1-4)";;
        esac
    done
    
    log_success "环境类型: $ENVIRONMENT"
}

# 配置优化选项
configure_optimization() {
    echo ""
    log_info "配置优化选项..."
    
    # GCS 归档
    read -p "是否启用 GCS 归档? (y/n): " enable_archive
    if [[ $enable_archive =~ ^[Yy]$ ]]; then
        ENABLE_GCS_ARCHIVE="true"
    else
        ENABLE_GCS_ARCHIVE="false"
    fi
    
    # 成本优化过滤器
    read -p "是否启用成本优化过滤器? (y/n): " enable_filters
    if [[ $enable_filters =~ ^[Yy]$ ]]; then
        ENABLE_FILTERS="true"
    else
        ENABLE_FILTERS="false"
    fi
    
    log_success "优化选项配置完成"
}

# 运行审计
run_audit() {
    echo ""
    log_info "运行日志配置审计..."
    
    if [ -f "./gcp-logging-audit-script.sh" ]; then
        ./gcp-logging-audit-script.sh "$PROJECT_ID"
    else
        log_warning "审计脚本不存在，跳过审计步骤"
    fi
}

# 部署 Terraform 配置
deploy_terraform() {
    echo ""
    log_info "部署 Terraform 配置..."
    
    if [ ! -f "./gcp-logging-terraform-module.tf" ]; then
        log_error "Terraform 模块文件不存在"
        return 1
    fi
    
    # 创建 terraform.tfvars 文件
    cat > terraform.tfvars << EOF
project_id = "$PROJECT_ID"
environment = "$ENVIRONMENT"
enable_gcs_archive = $ENABLE_GCS_ARCHIVE
enable_cost_optimization_filters = $ENABLE_FILTERS
EOF
    
    log_info "初始化 Terraform..."
    terraform init
    
    log_info "规划部署..."
    terraform plan
    
    echo ""
    read -p "是否继续部署? (y/n): " deploy_confirm
    if [[ $deploy_confirm =~ ^[Yy]$ ]]; then
        log_info "开始部署..."
        terraform apply -auto-approve
        log_success "Terraform 部署完成"
    else
        log_info "跳过部署"
    fi
}

# 运行成本分析
run_cost_analysis() {
    echo ""
    log_info "运行成本分析..."
    
    if [ ! -f "./gcp-logging-cost-analysis.py" ]; then
        log_warning "成本分析脚本不存在，跳过分析步骤"
        return
    fi
    
    # 检查 Python 依赖
    log_info "检查 Python 依赖..."
    if ! python3 -c "import google.cloud.logging, pandas, matplotlib" 2>/dev/null; then
        log_warning "缺少 Python 依赖，尝试安装..."
        pip3 install google-cloud-logging google-cloud-monitoring pandas matplotlib
    fi
    
    # 运行分析
    log_info "开始成本分析..."
    python3 gcp-logging-cost-analysis.py "$PROJECT_ID" --days 30 --output-dir ./reports/
    
    log_success "成本分析完成，报告保存在 ./reports/ 目录"
}

# 生成配置摘要
generate_summary() {
    echo ""
    log_header "========================================"
    log_header "           配置摘要"
    log_header "========================================"
    
    echo "项目 ID: $PROJECT_ID"
    echo "环境类型: $ENVIRONMENT"
    echo "GCS 归档: $ENABLE_GCS_ARCHIVE"
    echo "成本优化过滤器: $ENABLE_FILTERS"
    echo ""
    
    # 预期成本节省
    case $ENVIRONMENT in
        "dev")
            echo "预期成本节省: 70-80%"
            echo "保留策略: 7天"
            echo "日志级别: ERROR+"
            ;;
        "test")
            echo "预期成本节省: 60-70%"
            echo "保留策略: 14天"
            echo "日志级别: WARNING+"
            ;;
        "staging")
            echo "预期成本节省: 30-40%"
            echo "保留策略: 30天"
            echo "日志级别: INFO+"
            ;;
        "prod")
            echo "预期成本节省: 20-30%"
            echo "保留策略: 90天"
            echo "日志级别: INFO+"
            ;;
    esac
    
    echo ""
    log_header "========================================"
}

# 显示后续步骤
show_next_steps() {
    echo ""
    log_info "后续步骤建议:"
    echo ""
    echo "1. 监控成本变化:"
    echo "   - 查看 GCP 控制台的计费报告"
    echo "   - 使用生成的监控指标"
    echo ""
    echo "2. 定期审查:"
    echo "   - 每月运行成本分析脚本"
    echo "   - 根据需要调整过滤器"
    echo ""
    echo "3. 扩展到其他项目:"
    echo "   - 使用相同配置部署到其他环境"
    echo "   - 根据项目特点调整参数"
    echo ""
    echo "4. 持续优化:"
    echo "   - 监控日志量变化"
    echo "   - 根据业务需求调整策略"
    echo ""
}

# 主菜单
show_menu() {
    while true; do
        echo ""
        log_header "========================================"
        log_header "           主菜单"
        log_header "========================================"
        echo "1) 完整设置流程（推荐）"
        echo "2) 仅运行审计"
        echo "3) 仅部署 Terraform"
        echo "4) 仅运行成本分析"
        echo "5) 显示配置摘要"
        echo "6) 退出"
        echo ""
        
        read -p "请选择操作 (1-6): " menu_choice
        
        case $menu_choice in
            1)
                get_project_info
                select_environment
                configure_optimization
                run_audit
                deploy_terraform
                run_cost_analysis
                generate_summary
                show_next_steps
                break
                ;;
            2)
                get_project_info
                run_audit
                ;;
            3)
                get_project_info
                select_environment
                configure_optimization
                deploy_terraform
                ;;
            4)
                get_project_info
                run_cost_analysis
                ;;
            5)
                if [ -n "$PROJECT_ID" ]; then
                    generate_summary
                else
                    log_warning "请先配置项目信息"
                fi
                ;;
            6)
                log_info "退出程序"
                exit 0
                ;;
            *)
                log_error "请输入有效选项 (1-6)"
                ;;
        esac
    done
}

# 主函数
main() {
    show_welcome
    check_tools
    show_menu
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi