# GCE Service Account 信息查询脚本

## 问题分析

需要创建一个 Shell 脚本来实现以下功能：

1. 从 JSON 文件读取 Service Account 名称
2. 激活该 Service Account
3. 打印账户信息
4. 查询该账户在当前项目中的 IAM 角色
5. 检查是否配置了 Workload Identity

## 解决方案

### 完整脚本

```bash
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 错误处理
set -e
trap 'echo -e "${RED}错误: 脚本执行失败于第 $LINENO 行${NC}"' ERR

# 检查必需的工具
check_requirements() {
    local tools=("gcloud" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "${RED}错误: 未找到 $tool 命令，请先安装${NC}"
            exit 1
        fi
    done
}

# 读取 JSON 文件中的 Service Account
read_sa_from_json() {
    local json_file=$1
    
    if [[ ! -f "$json_file" ]]; then
        echo -e "${RED}错误: JSON 文件不存在: $json_file${NC}"
        exit 1
    fi
    
    # 从 JSON 中提取 client_email 字段
    local sa_email=$(jq -r '.client_email // .service_account // .email // empty' "$json_file")
    
    if [[ -z "$sa_email" || "$sa_email" == "null" ]]; then
        echo -e "${RED}错误: 无法从 JSON 文件中提取 Service Account 邮箱${NC}"
        echo -e "${YELLOW}请确认 JSON 文件包含以下字段之一: client_email, service_account, email${NC}"
        exit 1
    fi
    
    echo "$sa_email"
}

# 激活 Service Account
activate_service_account() {
    local json_file=$1
    
    echo -e "${GREEN}=== 激活 Service Account ===${NC}"
    gcloud auth activate-service-account --key-file="$json_file"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Service Account 激活成功${NC}"
    else
        echo -e "${RED}✗ Service Account 激活失败${NC}"
        exit 1
    fi
}

# 打印账户信息
print_account_info() {
    local sa_email=$1
    
    echo -e "\n${GREEN}=== Service Account 基本信息 ===${NC}"
    echo -e "邮箱: ${YELLOW}$sa_email${NC}"
    
    # 提取项目 ID
    local project_id=$(echo "$sa_email" | grep -oP '(?<=@)[^.]+(?=\.iam)')
    if [[ -z "$project_id" ]]; then
        project_id=$(gcloud config get-value project 2>/dev/null)
    fi
    echo -e "项目 ID: ${YELLOW}$project_id${NC}"
    
    # 获取当前激活的账户
    echo -e "\n当前激活的账户列表:"
    gcloud auth list
}

# 获取项目级别的 IAM 角色
get_project_iam_roles() {
    local sa_email=$1
    local project_id=$2
    
    echo -e "\n${GREEN}=== 项目级别 IAM 角色 ===${NC}"
    echo -e "查询项目: ${YELLOW}$project_id${NC}"
    
    # 获取项目 IAM 策略并过滤该 SA 的角色
    local roles=$(gcloud projects get-iam-policy "$project_id" \
        --flatten="bindings[].members" \
        --filter="bindings.members:serviceAccount:$sa_email" \
        --format="table(bindings.role)")
    
    if [[ -z "$roles" || "$roles" == *"Listed 0 items"* ]]; then
        echo -e "${YELLOW}⚠ 该 Service Account 在项目级别没有分配任何角色${NC}"
    else
        echo "$roles"
    fi
}

# 获取完整的 IAM 策略
get_full_iam_policy() {
    local sa_email=$1
    local project_id=$2
    
    echo -e "\n${GREEN}=== 完整 IAM 策略绑定 ===${NC}"
    
    gcloud projects get-iam-policy "$project_id" \
        --flatten="bindings[].members" \
        --filter="bindings.members:serviceAccount:$sa_email" \
        --format="json" | jq -r '.[] | "角色: \(.role)\n条件: \(.condition // "无条件")\n"'
}

# 检查 Workload Identity 配置
check_workload_identity() {
    local sa_email=$1
    local project_id=$2
    
    echo -e "\n${GREEN}=== Workload Identity 配置检查 ===${NC}"
    
    # 提取 SA 名称
    local sa_name=$(echo "$sa_email" | cut -d'@' -f1)
    
    # 检查 SA 的 IAM 策略绑定
    echo -e "检查 Service Account 的 IAM 策略绑定..."
    local wi_bindings=$(gcloud iam service-accounts get-iam-policy "$sa_email" \
        --format="json" 2>/dev/null | jq -r '.bindings[]? | select(.role == "roles/iam.workloadIdentityUser") | .members[]?')
    
    if [[ -z "$wi_bindings" ]]; then
        echo -e "${YELLOW}⚠ 未配置 Workload Identity 绑定${NC}"
        echo -e "${YELLOW}提示: 如需配置 Workload Identity，请使用以下命令:${NC}"
        echo -e "gcloud iam service-accounts add-iam-policy-binding $sa_email \\"
        echo -e "  --role roles/iam.workloadIdentityUser \\"
        echo -e "  --member \"serviceAccount:PROJECT_ID.svc.id.goog[NAMESPACE/KSA_NAME]\""
    else
        echo -e "${GREEN}✓ 已配置 Workload Identity${NC}"
        echo -e "\n绑定的 Kubernetes Service Account:"
        echo "$wi_bindings" | while read -r member; do
            if [[ "$member" == serviceAccount:* ]]; then
                local k8s_sa=$(echo "$member" | sed 's/serviceAccount:[^[]*\[//;s/\]//')
                echo -e "  - ${YELLOW}$k8s_sa${NC}"
            fi
        done
    fi
    
    # 检查是否有 workloadIdentityUser 角色
    echo -e "\n检查项目中的 Workload Identity 相关角色..."
    gcloud projects get-iam-policy "$project_id" \
        --flatten="bindings[].members" \
        --filter="bindings.members:serviceAccount:$sa_email AND bindings.role:workloadIdentity" \
        --format="table(bindings.role)" 2>/dev/null || echo -e "${YELLOW}无相关角色${NC}"
}

# 生成摘要报告
generate_summary() {
    local sa_email=$1
    local project_id=$2
    
    echo -e "\n${GREEN}=== 摘要报告 ===${NC}"
    echo -e "Service Account: ${YELLOW}$sa_email${NC}"
    echo -e "项目: ${YELLOW}$project_id${NC}"
    echo -e "报告时间: ${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
}

# 主函数
main() {
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}  GCE Service Account 信息查询工具  ${NC}"
    echo -e "${GREEN}=====================================${NC}\n"
    
    # 检查参数
    if [[ $# -lt 1 ]]; then
        echo -e "${RED}用法: $0 <service-account-key.json> [project-id]${NC}"
        echo -e "\n示例:"
        echo -e "  $0 sa-key.json"
        echo -e "  $0 sa-key.json my-project-id"
        exit 1
    fi
    
    local json_file=$1
    local project_id=${2:-""}
    
    # 检查必需工具
    check_requirements
    
    # 读取 SA 邮箱
    local sa_email=$(read_sa_from_json "$json_file")
    echo -e "检测到 Service Account: ${YELLOW}$sa_email${NC}\n"
    
    # 激活 Service Account
    activate_service_account "$json_file"
    
    # 如果未提供项目 ID，尝试从 SA 邮箱提取
    if [[ -z "$project_id" ]]; then
        project_id=$(echo "$sa_email" | grep -oP '(?<=@)[^.]+(?=\.iam)')
        if [[ -z "$project_id" ]]; then
            project_id=$(jq -r '.project_id' "$json_file")
        fi
    fi
    
    if [[ -z "$project_id" || "$project_id" == "null" ]]; then
        echo -e "${RED}错误: 无法确定项目 ID${NC}"
        exit 1
    fi
    
    # 设置当前项目
    gcloud config set project "$project_id" &>/dev/null
    
    # 打印账户信息
    print_account_info "$sa_email"
    
    # 获取 IAM 角色
    get_project_iam_roles "$sa_email" "$project_id"
    
    # 获取完整 IAM 策略
    get_full_iam_policy "$sa_email" "$project_id"
    
    # 检查 Workload Identity
    check_workload_identity "$sa_email" "$project_id"
    
    # 生成摘要
    generate_summary "$sa_email" "$project_id"
    
    echo -e "\n${GREEN}✓ 查询完成${NC}"
}

# 执行主函数
main "$@"
```

## 使用说明

### 基本用法

```bash
# 赋予执行权限
chmod +x check_sa_info.sh

# 执行脚本（自动检测项目）
./check_sa_info.sh service-account-key.json

# 指定项目 ID
./check_sa_info.sh service-account-key.json my-project-id
```

### JSON 文件格式要求

脚本支持以下 JSON 格式：

```json
{
  "type": "service_account",
  "project_id": "my-project",
  "private_key_id": "key-id",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...",
  "client_email": "sa-name@project.iam.gserviceaccount.com",
  "client_id": "123456789",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
```

## 执行流程图

```mermaid
graph TD
    A[开始] --> B[检查必需工具]
    B --> C[读取 JSON 文件]
    C --> D[提取 SA 邮箱]
    D --> E[激活 Service Account]
    E --> F[确定项目 ID]
    F --> G[打印账户信息]
    G --> H[查询项目 IAM 角色]
    H --> I[获取完整 IAM 策略]
    I --> J[检查 Workload Identity]
    J --> K{是否有 WI 绑定?}
    K -->|是| L[显示绑定的 K8S SA]
    K -->|否| M[显示配置提示]
    L --> N[生成摘要报告]
    M --> N
    N --> O[结束]
```

## 输出示例

脚本执行后会显示类似以下内容：

```
=====================================
  GCE Service Account 信息查询工具  
=====================================

检测到 Service Account: my-sa@my-project.iam.gserviceaccount.com

=== 激活 Service Account ===
✓ Service Account 激活成功

=== Service Account 基本信息 ===
邮箱: my-sa@my-project.iam.gserviceaccount.com
项目 ID: my-project

=== 项目级别 IAM 角色 ===
ROLE
roles/container.developer
roles/storage.objectViewer

=== Workload Identity 配置检查 ===
✓ 已配置 Workload Identity

绑定的 Kubernetes Service Account:
  - default/my-ksa

=== 摘要报告 ===
Service Account: my-sa@my-project.iam.gserviceaccount.com
项目: my-project
报告时间: 2025-10-29 10:30:00

✓ 查询完成
```

## 注意事项

### 前置要求

- 确保已安装 `gcloud` CLI 工具
- 确保已安装 `jq` 命令行 JSON 处理器
- Service Account JSON 密钥文件必须有效

### 权限要求

执行此脚本需要以下权限：

- `iam.serviceAccounts.getIamPolicy` - 查询 SA 的 IAM 策略
- `resourcemanager.projects.getIamPolicy` - 查询项目的 IAM 策略
- 或具有 `roles/viewer` 及以上角色

### 安全建议

- JSON 密钥文件包含敏感信息，使用后建议删除或妥善保管
- 建议使用 `chmod 600` 限制密钥文件权限
- 生产环境中考虑使用 Workload Identity 替代密钥文件

### 故障排除

```bash
# 如果遇到认证问题
gcloud auth list
gcloud config list

# 检查项目权限
gcloud projects get-iam-policy PROJECT_ID

# 验证 SA 是否存在
gcloud iam service-accounts list --project=PROJECT_ID

# 检查 jq 是否安装
which jq || sudo apt-get install jq  # Debian/Ubuntu
which jq || brew install jq          # macOS
```