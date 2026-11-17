```bash
#!/bin/bash

# ==============================================================================
# Script Name: verify-another-proj-sa.sh
# Description: Verifies what roles/permissions a Service Account from another
#              project (Project B) has been granted in your current project (Project A).
#
# Usage:       ./verify-another-proj-sa.sh <sa-email> [--project <project-a-id>]
#
# Examples:
#   ./verify-another-proj-sa.sh dev-us-app-sa@projectb.iam.gserviceaccount.com
#   ./verify-another-proj-sa.sh dev-us-app-sa@projectb.iam.gserviceaccount.com --project my-project-a
#
# Scenario:
#   You are in Project A. You granted a SA from Project B some roles in Project A.
#   This script shows exactly what that foreign SA can do in YOUR project.
# ==============================================================================

set -euo pipefail

# --- Color Definitions ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Function: Usage ---
show_usage() {
    echo -e "${BLUE}Usage:${NC} $0 <sa-email> [--project <your-project-id>]"
    echo -e "${BLUE}Example:${NC} $0 dev-us-app-sa@projectb.iam.gserviceaccount.com"
    echo -e "${BLUE}Example:${NC} $0 dev-us-app-sa@projectb.iam.gserviceaccount.com --project my-project-a"
    echo ""
    echo "If --project is not specified, the current gcloud project is used as Project A."
    exit 1
}

# --- Parse Arguments ---
SA_EMAIL=""
LOCAL_PROJECT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --project)
            LOCAL_PROJECT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            if [[ -z "$SA_EMAIL" ]]; then
                SA_EMAIL="$1"
            else
                echo -e "${RED}Error: Unexpected argument '$1'.${NC}"
                show_usage
            fi
            shift
            ;;
    esac
done

[[ -z "$SA_EMAIL" ]] && show_usage

# --- Basic Validation ---
if [[ ! "$SA_EMAIL" =~ ^[^@]+@[^.]+\.iam\.gserviceaccount\.com$ ]]; then
    echo -e "${RED}Error: Invalid Service Account email format.${NC}"
    show_usage
fi

# --- Extract Info ---
SA_NAME=$(echo "$SA_EMAIL" | cut -d'@' -f1)
SA_HOME_PROJECT=$(echo "$SA_EMAIL" | cut -d'@' -f2 | cut -d'.' -f1)

if [[ -z "$LOCAL_PROJECT" ]]; then
    LOCAL_PROJECT=$(gcloud config get-value project 2>/dev/null)
fi

if [[ -z "$LOCAL_PROJECT" ]]; then
    echo -e "${RED}Error: No project specified and no default gcloud project set.${NC}"
    show_usage
fi

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}   Cross-Project SA Permission Verification Tool      ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo -e "${GREEN}Foreign SA:${NC}       $SA_EMAIL"
echo -e "${GREEN}SA Home Project:${NC}  $SA_HOME_PROJECT"
echo -e "${CYAN}Your Project:${NC}     $LOCAL_PROJECT"
echo ""

if [[ "$SA_HOME_PROJECT" == "$LOCAL_PROJECT" ]]; then
    echo -e "${YELLOW}⚠️  Note: The SA belongs to the SAME project. Use verify-gce-sa.sh for local SA checks.${NC}"
    echo ""
fi

# --- 1. Check if the SA exists in its home project ---
echo -e "${YELLOW}[1/5] Verifying SA exists in its home project '$SA_HOME_PROJECT'...${NC}"
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$SA_HOME_PROJECT" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Service Account exists in project '$SA_HOME_PROJECT'.${NC}"
else
    echo -e "${RED}❌ Cannot verify SA in project '$SA_HOME_PROJECT' (no access or SA does not exist).${NC}"
    echo -e "${YELLOW}   Continuing anyway — you may still have bindings referencing this SA.${NC}"
fi

# --- 2. Check project-level IAM roles in YOUR project ---
echo -e "\n${YELLOW}[2/5] Checking project-level IAM roles in YOUR project '$LOCAL_PROJECT'...${NC}"
ROLES=$(gcloud projects get-iam-policy "$LOCAL_PROJECT" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:$SA_EMAIL" \
    --format="table(bindings.role)" 2>/dev/null | tail -n +2)

if [[ -z "$ROLES" ]]; then
    echo -e "${YELLOW}⚠️  No direct project-level roles found for this SA in '$LOCAL_PROJECT'.${NC}"
else
    echo -e "${GREEN}✅ Roles granted to '$SA_NAME' in project '$LOCAL_PROJECT':${NC}"
    echo "$ROLES" | sed 's/^/  - /'
fi

# --- 3. Check IAM conditions (if any) ---
echo -e "\n${YELLOW}[3/5] Checking for conditional IAM bindings...${NC}"
COND_BINDINGS=$(gcloud projects get-iam-policy "$LOCAL_PROJECT" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:$SA_EMAIL AND bindings.condition:*" \
    --format="table(bindings.role, bindings.condition.title, bindings.condition.expression)" 2>/dev/null | tail -n +2)

if [[ -z "$COND_BINDINGS" ]]; then
    echo -e "${GREEN}✅ No conditional bindings found (all grants are unconditional).${NC}"
else
    echo -e "${CYAN}📋 Conditional IAM bindings:${NC}"
    echo "$COND_BINDINGS"
fi

# --- 4. Expand permissions for each role ---
echo -e "\n${YELLOW}[4/5] Expanding permissions for each granted role...${NC}"
if [[ -n "$ROLES" ]]; then
    while IFS= read -r role; do
        [[ -z "$role" ]] && continue
        echo -e "\n  ${CYAN}📦 Role: ${role}${NC}"

        PERMS=$(gcloud iam roles describe "$role" --format="value(includedPermissions)" 2>/dev/null | tr ';' '\n' | head -20)

        if [[ -z "$PERMS" ]]; then
            echo -e "    ${YELLOW}(Unable to expand — may be a custom role or access denied)${NC}"
        else
            PERM_COUNT=$(gcloud iam roles describe "$role" --format="value(includedPermissions)" 2>/dev/null | tr ';' '\n' | wc -l | tr -d ' ')
            echo -e "    ${GREEN}Total permissions: ${PERM_COUNT}${NC}"
            echo "$PERMS" | sed 's/^/    - /'
            if [[ "$PERM_COUNT" -gt 20 ]]; then
                echo -e "    ${YELLOW}... (showing first 20 of $PERM_COUNT)${NC}"
            fi
        fi
    done <<< "$ROLES"
else
    echo -e "${YELLOW}  (No roles to expand — SA has no project-level grants.)${NC}"
fi

# --- 5. Check resource-level bindings (common resources) ---
echo -e "\n${YELLOW}[5/5] Checking common resource-level bindings...${NC}"

# 5a. Check if this SA can act as any local SA (serviceAccountUser / serviceAccountTokenCreator)
echo -e "  ${CYAN}Checking serviceAccount-level bindings...${NC}"
LOCAL_SAS=$(gcloud iam service-accounts list --project="$LOCAL_PROJECT" --format="value(email)" 2>/dev/null)

SA_LEVEL_FOUND=false
while IFS= read -r local_sa; do
    [[ -z "$local_sa" ]] && continue
    SA_POLICY=$(gcloud iam service-accounts get-iam-policy "$local_sa" \
        --project="$LOCAL_PROJECT" \
        --flatten="bindings[].members" \
        --filter="bindings.members:serviceAccount:$SA_EMAIL" \
        --format="table(bindings.role)" 2>/dev/null | tail -n +2)

    if [[ -n "$SA_POLICY" ]]; then
        SA_LEVEL_FOUND=true
        echo -e "  ${GREEN}✅ On SA '${local_sa}':${NC}"
        echo "$SA_POLICY" | sed 's/^/     - /'
    fi
done <<< "$LOCAL_SAS"

if [[ "$SA_LEVEL_FOUND" == "false" ]]; then
    echo -e "  ${GREEN}✅ No service-account-level bindings found (no impersonation grants).${NC}"
fi

# --- Summary ---
echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}   Summary                                            ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo -e "${GREEN}Foreign SA:${NC}       $SA_EMAIL"
echo -e "${GREEN}SA Home Project:${NC}  $SA_HOME_PROJECT"
echo -e "${CYAN}Your Project:${NC}     $LOCAL_PROJECT"
echo ""

if [[ -n "$ROLES" ]]; then
    ROLE_COUNT=$(echo "$ROLES" | wc -l | tr -d ' ')
    echo -e "${GREEN}📊 Total project-level roles: ${ROLE_COUNT}${NC}"
    echo "$ROLES" | sed 's/^/  - /'
else
    echo -e "${YELLOW}📊 No project-level roles granted.${NC}"
fi

echo ""
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}   Verification Complete!                              ${NC}"
echo -e "${BLUE}======================================================${NC}"



local 
#!/bin/bash

# ------------------------------------------------------
# GCP Service Account Permission Verifier
# 功能：检查一个指定的Service Account在当前运行环境 (Project A) 中拥有哪些IAM角色。
# 注意：脚本必须在具备读取 IAM Policy 的权限的机器上运行，并且已配置 gcloud CLI。
# ------------------------------------------------------

# 检查参数数量
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <SERVICE_ACCOUNT_EMAIL>"
    echo ""
    echo "Example:"
    echo "  $0 dev-us-app-sa@projectb.iam.gserviceaccount.com"
    exit 1
fi

# --- 输入参数处理 ---
TARGET_SA="$1"

# 检查 gcloud 是否可用
if ! command -v gcloud &> /dev/null
then
    echo "🚨 Error: The 'gcloud' CLI command could not be found. Please ensure the Google Cloud SDK is installed and initialized."
    exit 1
fi

# 获取当前项目 ID (这是权限的检查范围，即 Project A)
CURRENT_PROJECT=$(gcloud config get-value project)

if [ -z "$CURRENT_PROJECT" ]; then
    echo "🚨 Error: Could not determine the current GCP project. Please run 'gcloud config set project YOUR_PROJECT_ID' first."
    exit 1
fi


# --- 主逻辑 ---
echo "================================================================"
echo "🔍 Starting Permission Audit..."
echo "  Target Service Account: $TARGET_SA"
echo "  Audit Scope (Project A): $CURRENT_PROJECT"
echo "----------------------------------------------------------------"

# 格式化输出的头部信息
echo -e "\n✅ Found Permissions for '$TARGET_SA' in Project '$CURRENT_PROJECT':\n"

# 核心逻辑：使用 gcloud projects get-iam-policy 读取整个项目的 IAM 策略，
# 并只筛选出包含目标 SA 的绑定（Bindings）。
POLICY_OUTPUT=$(gcloud projects get-iam-policy "${CURRENT_PROJECT}" \
    --format=json --quiet)

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to retrieve the IAM policy for project '$CURRENT_PROJECT'."
    echo "   Please ensure that the authenticated user has 'resourcemanager.projects.getIamPolicy' permission on this project."
    exit 1
fi

# 初始化一个标志位，用于追踪是否找到了权限
FOUND_PERMISSIONS=0

# 使用 jq 工具解析 JSON (jq 是处理JSON的最佳工具)
if command -v jq &> /dev/null; then
    echo "Using 'jq' for reliable JSON parsing..."
    
    # 遍历 policy 中的每一个 bindings 对象
    gcloud projects get-iam-policy "${CURRENT_PROJECT}" --format=json | jq -r \
        '.bindings[] | select(.members[] | test("accounts/.*'+${TARGET_SA}'")) | "\(.role)\t\(\(.members | join(", ")))"' | while IFS=$'\t' read -r ROLE MEMBERS; do
        
            echo "  🛡️ Role Granted: $ROLE"
            echo "    * Assigned to: ${MEMBERS}"
            FOUND_PERMISSIONS=1
        done

else
    # 如果没有安装 jq，则提供警告并退出
    echo ""
    echo "⚠️ WARNING: The 'jq' utility is required for reliable JSON parsing."
    echo "   Please install it (e.g., sudo apt-get install jq or brew install jq)."
    exit 1
fi


# --- 结果总结 ---
if [ "$FOUND_PERMISSIONS" -eq 0 ]; then
    echo ""
    echo "----------------------------------------------------------------"
    echo "✨ SUCCESS: The Service Account '$TARGET_SA' currently does not appear to have any direct, explicit roles granted on Project '$CURRENT_PROJECT'."
    echo "(Note: It might inherit permissions through Google Workspace or other indirect means.)"
else
    echo ""
    echo "================================================================"
    echo "✅ Audit Complete. The Service Account '$TARGET_SA' has been confirmed to hold the roles listed above in Project '$CURRENT_PROJECT'."
fi


```