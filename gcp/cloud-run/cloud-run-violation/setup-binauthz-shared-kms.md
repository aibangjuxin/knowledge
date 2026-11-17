- get project 
```bash
#!/bin/bash

# Binary Authorization 配置脚本 - 使用 Shared 工程 KMS 密钥
# 作者: Kiro AI Assistant
# 用途: 交互式配置 Binary Authorization attestor 使用现有的 Shared KMS 密钥

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

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# 检查必要的工具
check_prerequisites() {
    print_header "检查前置条件"
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI 未安装，请先安装 Google Cloud SDK"
        exit 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "请先运行 'gcloud auth login' 进行身份验证"
        exit 1
    fi
    
    print_success "前置条件检查通过"
}

# 获取当前项目信息
get_current_project() {
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$CURRENT_PROJECT" ]; then
        print_error "未设置默认项目，请运行 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    print_info "当前项目: $CURRENT_PROJECT"
}

# 配置基本参数
configure_basic_params() {
    print_header "配置基本参数"
    
    # Shared 工程 ID
    echo -n "请输入 Shared 工程 ID (例如: shared-security-project): "
    read SHARED_PROJECT_ID
    
    if [ -z "$SHARED_PROJECT_ID" ]; then
        print_error "Shared 工程 ID 不能为空"
        exit 1
    fi
    
    # 验证 Shared 工程是否存在
    if ! gcloud projects describe "$SHARED_PROJECT_ID" &>/dev/null; then
        print_error "无法访问项目 $SHARED_PROJECT_ID，请检查项目 ID 和权限"
        exit 1
    fi
    
    print_success "Shared 工程验证通过: $SHARED_PROJECT_ID"
    
    # KMS 位置
    echo -n "请输入 KMS 位置 (默认: global): "
    read KMS_LOCATION
    KMS_LOCATION=${KMS_LOCATION:-global}
    
    # Attestor 名称
    echo -n "请输入 Attestor 名称 (默认: attestor-cloud-run): "
    read ATTESTOR_NAME
    ATTESTOR_NAME=${ATTESTOR_NAME:-attestor-cloud-run}
    
    # Note 名称
    echo -n "请输入 Container Analysis Note 名称 (默认: note-cloud-run): "
    read NOTE_NAME
    NOTE_NAME=${NOTE_NAME:-note-cloud-run}
    
    print_info "配置参数:"
    print_info "  当前项目: $CURRENT_PROJECT"
    print_info "  Shared 工程: $SHARED_PROJECT_ID"
    print_info "  KMS 位置: $KMS_LOCATION"
    print_info "  Attestor 名称: $ATTESTOR_NAME"
    print_info "  Note 名称: $NOTE_NAME"
}

# 列出并选择密钥环
select_keyring() {
    print_header "选择 KMS 密钥环"
    
    print_info "正在获取 $SHARED_PROJECT_ID 项目中的密钥环列表..."
    
    # 获取密钥环列表
    KEYRINGS=$(gcloud kms keyrings list --location=$KMS_LOCATION --project=$SHARED_PROJECT_ID --format="value(name)" 2>/dev/null)
    
    if [ -z "$KEYRINGS" ]; then
        print_error "在项目 $SHARED_PROJECT_ID 的位置 $KMS_LOCATION 中未找到密钥环"
        exit 1
    fi
    
    echo "可用的密钥环:"
    echo "$KEYRINGS" | while read keyring; do
        keyring_name=$(basename "$keyring")
        echo "  - $keyring_name"
    done
    
    echo
    echo -n "请输入要使用的密钥环名称: "
    read KEYRING_NAME
    
    if [ -z "$KEYRING_NAME" ]; then
        print_error "密钥环名称不能为空"
        exit 1
    fi
    
    # 验证密钥环是否存在
    if ! gcloud kms keyrings describe "$KEYRING_NAME" --location=$KMS_LOCATION --project=$SHARED_PROJECT_ID &>/dev/null; then
        print_error "密钥环 $KEYRING_NAME 不存在"
        exit 1
    fi
    
    print_success "选择的密钥环: $KEYRING_NAME"
}

# 列出并选择密钥
select_key() {
    print_header "选择 KMS 密钥"
    
    print_info "正在获取密钥环 $KEYRING_NAME 中的密钥列表..."
    
    # 获取密钥列表
    KEYS=$(gcloud kms keys list --keyring=$KEYRING_NAME --location=$KMS_LOCATION --project=$SHARED_PROJECT_ID --format="value(name)" 2>/dev/null)
    
    if [ -z "$KEYS" ]; then
        print_error "在密钥环 $KEYRING_NAME 中未找到密钥"
        exit 1
    fi
    
    echo "可用的密钥:"
    echo "$KEYS" | while read key; do
        key_name=$(basename "$key")
        # 获取密钥详情
        key_info=$(gcloud kms keys describe "$key_name" --keyring=$KEYRING_NAME --location=$KMS_LOCATION --project=$SHARED_PROJECT_ID --format="value(purpose,versionTemplate.algorithm)" 2>/dev/null)
        echo "  - $key_name ($key_info)"
    done
    
    echo
    echo -n "请输入要使用的密钥名称: "
    read KEY_NAME
    
    if [ -z "$KEY_NAME" ]; then
        print_error "密钥名称不能为空"
        exit 1
    fi
    
    # 验证密钥是否存在
    if ! gcloud kms keys describe "$KEY_NAME" --keyring=$KEYRING_NAME --location=$KMS_LOCATION --project=$SHARED_PROJECT_ID &>/dev/null; then
        print_error "密钥 $KEY_NAME 不存在"
        exit 1
    fi
    
    # 检查密钥用途
    KEY_PURPOSE=$(gcloud kms keys describe "$KEY_NAME" --keyring=$KEYRING_NAME --location=$KMS_LOCATION --project=$SHARED_PROJECT_ID --format="value(purpose)" 2>/dev/null)
    
    if [ "$KEY_PURPOSE" != "ASYMMETRIC_SIGN" ]; then
        print_warning "警告: 密钥 $KEY_NAME 的用途是 $KEY_PURPOSE，不是 ASYMMETRIC_SIGN"
        echo -n "是否继续? (y/N): "
        read continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            print_info "操作已取消"
            exit 0
        fi
    fi
    
    print_success "选择的密钥: $KEY_NAME (用途: $KEY_PURPOSE)"
}

# 配置权限
configure_permissions() {
    print_header "配置 KMS 密钥权限"
    
    print_info "为当前项目的默认服务账号配置 KMS 密钥使用权限..."
    
    # 获取项目编号
    PROJECT_NUMBER=$(gcloud projects describe $CURRENT_PROJECT --format="value(projectNumber)")
    
    # 为默认服务账号授权
    print_info "为服务账号 $CURRENT_PROJECT@appspot.gserviceaccount.com 授权..."
    gcloud kms keys add-iam-policy-binding $KEY_NAME \
        --keyring=$KEYRING_NAME \
        --location=$KMS_LOCATION \
        --project=$SHARED_PROJECT_ID \
        --member="serviceAccount:$CURRENT_PROJECT@appspot.gserviceaccount.com" \
        --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
        --quiet
    
    # 询问是否为 Cloud Build 服务账号授权
    echo -n "是否需要为 Cloud Build 服务账号授权? (y/N): "
    read cloudbuild_choice
    if [[ "$cloudbuild_choice" =~ ^[Yy]$ ]]; then
        print_info "为 Cloud Build 服务账号 $PROJECT_NUMBER@cloudbuild.gserviceaccount.com 授权..."
        gcloud kms keys add-iam-policy-binding $KEY_NAME \
            --keyring=$KEYRING_NAME \
            --location=$KMS_LOCATION \
            --project=$SHARED_PROJECT_ID \
            --member="serviceAccount:$PROJECT_NUMBER@cloudbuild.gserviceaccount.com" \
            --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
            --quiet
    fi
    
    print_success "权限配置完成"
}

# 创建 Container Analysis Note
create_note() {
    print_header "创建 Container Analysis Note"
    
    # 检查 Note 是否已存在
    if gcloud container analysis notes describe $NOTE_NAME --project=$CURRENT_PROJECT &>/dev/null; then
        print_warning "Note $NOTE_NAME 已存在，跳过创建"
        return
    fi
    
    print_info "创建 Container Analysis Note: $NOTE_NAME"
    
    # 创建临时 JSON 文件
    NOTE_JSON=$(mktemp)
    cat > "$NOTE_JSON" << EOF
{
  "name": "projects/$CURRENT_PROJECT/notes/$NOTE_NAME",
  "attestationAuthority": {
    "hint": {
      "humanReadableName": "Binary Authorization Attestor Note for $CURRENT_PROJECT"
    }
  }
}
EOF
    
    # 使用 REST API 创建 Note
    curl -s -X POST \
        "https://containeranalysis.googleapis.com/v1/projects/$CURRENT_PROJECT/notes?noteId=$NOTE_NAME" \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d @"$NOTE_JSON" > /dev/null
    
    rm "$NOTE_JSON"
    
    # 验证创建是否成功
    if gcloud container analysis notes describe $NOTE_NAME --project=$CURRENT_PROJECT &>/dev/null; then
        print_success "Container Analysis Note 创建成功"
    else
        print_error "Container Analysis Note 创建失败"
        exit 1
    fi
}

# 创建 Attestor
create_attestor() {
    print_header "创建 Binary Authorization Attestor"
    
    # 检查 Attestor 是否已存在
    if gcloud container binauthz attestors describe $ATTESTOR_NAME --project=$CURRENT_PROJECT &>/dev/null; then
        print_warning "Attestor $ATTESTOR_NAME 已存在"
        echo -n "是否要删除并重新创建? (y/N): "
        read recreate_choice
        if [[ "$recreate_choice" =~ ^[Yy]$ ]]; then
            print_info "删除现有 Attestor..."
            gcloud container binauthz attestors delete $ATTESTOR_NAME --project=$CURRENT_PROJECT --quiet
        else
            print_info "跳过 Attestor 创建"
            return
        fi
    fi
    
    print_info "创建 Attestor: $ATTESTOR_NAME"
    gcloud container binauthz attestors create $ATTESTOR_NAME \
        --attestation-authority-note=$NOTE_NAME \
        --attestation-authority-note-project=$CURRENT_PROJECT \
        --project=$CURRENT_PROJECT \
        --quiet
    
    print_success "Attestor 创建成功"
}

# 添加 KMS 公钥到 Attestor
add_kms_key_to_attestor() {
    print_header "添加 KMS 公钥到 Attestor"
    
    # 构建密钥版本路径
    KEY_VERSION_PATH="projects/$SHARED_PROJECT_ID/locations/$KMS_LOCATION/keyRings/$KEYRING_NAME/cryptoKeys/$KEY_NAME/cryptoKeyVersions/1"
    
    print_info "添加 KMS 公钥到 Attestor..."
    print_info "密钥路径: $KEY_VERSION_PATH"
    
    gcloud container binauthz attestors public-keys add \
        --attestor=$ATTESTOR_NAME \
        --keyversion=$KEY_VERSION_PATH \
        --project=$CURRENT_PROJECT \
        --quiet
    
    print_success "KMS 公钥添加成功"
}

# 验证配置
verify_configuration() {
    print_header "验证配置"
    
    print_info "验证 Attestor 配置..."
    gcloud container binauthz attestors describe $ATTESTOR_NAME --project=$CURRENT_PROJECT
    
    print_info "验证 Container Analysis Note..."
    gcloud container analysis notes describe $NOTE_NAME --project=$CURRENT_PROJECT
    
    print_success "配置验证完成"
}

# 生成使用示例
generate_usage_example() {
    print_header "使用示例"
    
    cat << EOF
配置完成！以下是使用示例:

1. 镜像签名脚本:
   export SHARED_PROJECT_ID="$SHARED_PROJECT_ID"
   export KMS_LOCATION="$KMS_LOCATION"
   export KEYRING_NAME="$KEYRING_NAME"
   export KEY_NAME="$KEY_NAME"
   export PROJECT_ID="$CURRENT_PROJECT"
   export ATTESTOR_NAME="$ATTESTOR_NAME"

2. 签名命令:
   # 获取镜像 digest
   IMAGE_DIGEST=\$(gcloud container images describe \\
     REGION-docker.pkg.dev/\$PROJECT_ID/REPO_NAME/IMAGE_NAME:TAG \\
     --format='value(image_summary.digest)')

   # 创建签名
   gcloud container binauthz attestations create \\
     --artifact-url=REGION-docker.pkg.dev/\$PROJECT_ID/REPO_NAME/IMAGE_NAME@\$IMAGE_DIGEST \\
     --attestor=\$ATTESTOR_NAME \\
     --keyversion=projects/\$SHARED_PROJECT_ID/locations/\$KMS_LOCATION/keyRings/\$KEYRING_NAME/cryptoKeys/\$KEY_NAME/cryptoKeyVersions/1 \\
     --project=\$PROJECT_ID

3. 验证签名:
   gcloud container binauthz attestations list \\
     --attestor=\$ATTESTOR_NAME \\
     --project=\$PROJECT_ID

EOF
}

# 主函数
main() {
    print_header "Binary Authorization 配置工具 - 使用 Shared KMS 密钥"
    
    check_prerequisites
    get_current_project
    configure_basic_params
    select_keyring
    select_key
    configure_permissions
    create_note
    create_attestor
    add_kms_key_to_attestor
    verify_configuration
    generate_usage_example
    
    print_success "所有配置完成！"
}

# 执行主函数
main "$@"
```