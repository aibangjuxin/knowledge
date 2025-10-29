#!/opt/homebrew/bin/bash
# - #!/bin/bash

# GCP Secret Manager 管理脚本
# 需要当前用户拥有 roles/secretmanager.secretVersionManager 权限

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 显示帮助信息
show_help() {
    echo "GCP Secret Manager 管理脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示帮助信息"
    echo "  --grant-access          给Service Account授权访问权限"
    echo "  --add-secret-version    给Secret添加新版本"
    echo "  --list-secrets          列出所有secrets"
    echo "  --show-commands         显示常用命令示例"
    echo ""
}

# 给Service Account授权访问Secret的权限
grant_secret_access() {
    print_info "开始给Service Account授权Secret访问权限..."
    
    read -p "请输入Secret名称: " SECRET_NAME
    read -p "请输入Service Account邮箱 (例: my-sa@project.iam.gserviceaccount.com): " SERVICE_ACCOUNT
    read -p "请输入GCP项目ID: " PROJECT_ID
    
    if [[ -z "$SECRET_NAME" || -z "$SERVICE_ACCOUNT" || -z "$PROJECT_ID" ]]; then
        print_error "所有参数都是必需的"
        return 1
    fi
    
    print_info "执行命令: gcloud secrets add-iam-policy-binding $SECRET_NAME --member=\"serviceAccount:$SERVICE_ACCOUNT\" --role=\"roles/secretmanager.secretAccessor\" --project=$PROJECT_ID"
    
    if gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
        --member="serviceAccount:$SERVICE_ACCOUNT" \
        --role="roles/secretmanager.secretAccessor" \
        --project="$PROJECT_ID"; then
        print_success "成功给Service Account $SERVICE_ACCOUNT 授权访问 Secret $SECRET_NAME"
    else
        print_error "授权失败"
        return 1
    fi
}

# 给Secret添加新版本
add_secret_version() {
    print_info "开始给Secret添加新版本..."
    
    read -p "请输入Secret名称: " SECRET_NAME
    read -p "请输入GCP项目ID: " PROJECT_ID
    echo "请选择输入方式:"
    echo "1) 直接输入值"
    echo "2) 从文件读取"
    read -p "选择 (1/2): " INPUT_METHOD
    
    if [[ -z "$SECRET_NAME" || -z "$PROJECT_ID" ]]; then
        print_error "Secret名称和项目ID是必需的"
        return 1
    fi
    
    case $INPUT_METHOD in
        1)
            read -s -p "请输入Secret值: " SECRET_VALUE
            echo ""
            if [[ -z "$SECRET_VALUE" ]]; then
                print_error "Secret值不能为空"
                return 1
            fi
            
            print_info "执行命令: echo '***' | gcloud secrets versions add $SECRET_NAME --data-file=- --project=$PROJECT_ID"
            
            if echo "$SECRET_VALUE" | gcloud secrets versions add "$SECRET_NAME" \
                --data-file=- \
                --project="$PROJECT_ID"; then
                print_success "成功给Secret $SECRET_NAME 添加新版本"
            else
                print_error "添加新版本失败"
                return 1
            fi
            ;;
        2)
            read -p "请输入文件路径: " FILE_PATH
            if [[ ! -f "$FILE_PATH" ]]; then
                print_error "文件不存在: $FILE_PATH"
                return 1
            fi
            
            print_info "执行命令: gcloud secrets versions add $SECRET_NAME --data-file=$FILE_PATH --project=$PROJECT_ID"
            
            if gcloud secrets versions add "$SECRET_NAME" \
                --data-file="$FILE_PATH" \
                --project="$PROJECT_ID"; then
                print_success "成功给Secret $SECRET_NAME 添加新版本"
            else
                print_error "添加新版本失败"
                return 1
            fi
            ;;
        *)
            print_error "无效选择"
            return 1
            ;;
    esac
}

# 列出所有secrets
list_secrets() {
    read -p "请输入GCP项目ID: " PROJECT_ID
    
    if [[ -z "$PROJECT_ID" ]]; then
        print_error "项目ID是必需的"
        return 1
    fi
    
    print_info "列出项目 $PROJECT_ID 中的所有secrets..."
    
    if gcloud secrets list --project="$PROJECT_ID"; then
        print_success "成功列出所有secrets"
    else
        print_error "列出secrets失败"
        return 1
    fi
}



# 显示常用命令示例
show_commands() {
    print_info "GCP Secret Manager 常用命令示例:"
    echo ""
    echo "1. 给Service Account授权访问Secret:"
    echo "   gcloud secrets add-iam-policy-binding SECRET_NAME \\"
    echo "     --member=\"serviceAccount:SA_EMAIL\" \\"
    echo "     --role=\"roles/secretmanager.secretAccessor\" \\"
    echo "     --project=PROJECT_ID"
    echo ""
    echo "2. 给Secret添加新版本 (从标准输入):"
    echo "   echo -n 'SECRET_VALUE' | gcloud secrets versions add SECRET_NAME \\"
    echo "     --data-file=- \\"
    echo "     --project=PROJECT_ID"
    echo ""
    echo "3. 给Secret添加新版本 (从文件):"
    echo "   gcloud secrets versions add SECRET_NAME \\"
    echo "     --data-file=FILE_PATH \\"
    echo "     --project=PROJECT_ID"
    echo ""
    echo "4. 列出所有secrets:"
    echo "   gcloud secrets list --project=PROJECT_ID"
    echo ""
    echo "5. 查看Secret的IAM策略:"
    echo "   gcloud secrets get-iam-policy SECRET_NAME --project=PROJECT_ID"
    echo ""
    echo "6. 获取Secret的最新版本:"
    echo "   gcloud secrets versions access latest --secret=SECRET_NAME --project=PROJECT_ID"
    echo ""
    echo "7. 创建新的Secret:"
    echo "   gcloud secrets create SECRET_NAME --project=PROJECT_ID"
    echo ""
    echo "8. 删除Secret版本:"
    echo "   gcloud secrets versions destroy VERSION_ID --secret=SECRET_NAME --project=PROJECT_ID"
    echo ""
}

# 主函数
main() {
    case "${1:-}" in
        -h|--help)
            show_help
            ;;
        --grant-access)
            grant_secret_access
            ;;
        --add-secret-version)
            add_secret_version
            ;;
        --list-secrets)
            list_secrets
            ;;
        --show-commands)
            show_commands
            ;;
        "")
            print_info "GCP Secret Manager 管理脚本"
            echo "使用 --help 查看帮助信息"
            echo ""
            echo "快速选择:"
            echo "1) 给Service Account授权"
            echo "2) 给Secret添加新版本"
            echo "3) 列出所有secrets"
            echo "4) 显示常用命令"
            echo "5) 退出"
            read -p "请选择 (1-5): " CHOICE
            
            case $CHOICE in
                1) grant_secret_access ;;
                2) add_secret_version ;;
                3) list_secrets ;;
                4) show_commands ;;
                5) exit 0 ;;
                *) print_error "无效选择" ;;
            esac
            ;;
        *)
            print_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 如果只是显示命令，不需要检查gcloud
if [[ "${1:-}" == "--show-commands" ]]; then
    show_commands
    exit 0
fi

# 检查gcloud是否已安装
if ! command -v gcloud &> /dev/null; then
    print_error "gcloud CLI 未安装，请先安装 Google Cloud SDK"
    print_info "如果只想查看命令示例，请使用: $0 --show-commands"
    exit 1
fi

# 检查是否已登录
if ! gcloud auth list --format="value(account)" 2>/dev/null | head -n1 | grep -q "@"; then
    print_error "请先使用 'gcloud auth login' 登录"
    # temp setting 1
    #exit 1

fi

main "$@"