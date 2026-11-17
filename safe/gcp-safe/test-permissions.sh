#!/bin/bash

################################################################################
# KMS 权限测试脚本
# 用于测试 describe vs list 命令的权限要求
################################################################################

set -euo pipefail

echo "=========================================="
echo "KMS 权限测试：describe vs list"
echo "=========================================="
echo ""

# 检查参数
if [[ $# -lt 4 ]]; then
    echo "使用方法: $0 KMS_PROJECT LOCATION KEYRING CRYPTO_KEY"
    echo ""
    echo "示例:"
    echo "  $0 my-kms-project global my-keyring my-key"
    exit 1
fi

KMS_PROJECT="$1"
LOCATION="$2"
KEYRING="$3"
CRYPTO_KEY="$4"

echo "测试配置:"
echo "  KMS 项目: $KMS_PROJECT"
echo "  位置: $LOCATION"
echo "  Keyring: $KEYRING"
echo "  CryptoKey: $CRYPTO_KEY"
echo ""

# ============================================================================
# 测试 Keyring 访问
# ============================================================================
echo "1. 测试 Keyring 访问方法"
echo "----------------------------------------"

# 方法 1: describe (需要 cloudkms.keyRings.get 权限)
echo "方法 1: gcloud kms keyrings describe"
if gcloud kms keyrings describe "$KEYRING" \
    --project="$KMS_PROJECT" \
    --location="$LOCATION" \
    --format=json &> /dev/null; then
    echo "  ✓ describe 成功 (有 cloudkms.keyRings.get 权限)"
else
    echo "  ✗ describe 失败 (缺少 cloudkms.keyRings.get 权限)"
fi
echo ""

# 方法 2: list (需要 cloudkms.keyRings.list 权限)
echo "方法 2: gcloud kms keyrings list"
keyring_list=$(gcloud kms keyrings list \
    --project="$KMS_PROJECT" \
    --location="$LOCATION" \
    --filter="name:$KEYRING" \
    --format=json 2>&1 || echo "[]")

keyring_count=$(echo "$keyring_list" | jq '. | length' 2>/dev/null || echo "0")

if [[ "$keyring_count" -gt 0 ]]; then
    echo "  ✓ list 成功 (有 cloudkms.keyRings.list 权限)"
    echo "  找到 Keyring: $(echo "$keyring_list" | jq -r '.[0].name')"
else
    echo "  ✗ list 失败或未找到 (缺少 cloudkms.keyRings.list 权限或 Keyring 不存在)"
fi
echo ""

# ============================================================================
# 测试 CryptoKey 访问
# ============================================================================
echo "2. 测试 CryptoKey 访问方法"
echo "----------------------------------------"

# 方法 1: describe (需要 cloudkms.cryptoKeys.get 权限)
echo "方法 1: gcloud kms keys describe"
if key_info=$(gcloud kms keys describe "$CRYPTO_KEY" \
    --project="$KMS_PROJECT" \
    --keyring="$KEYRING" \
    --location="$LOCATION" \
    --format=json 2>&1); then
    echo "  ✓ describe 成功 (有 cloudkms.cryptoKeys.get 权限)"
    key_purpose=$(echo "$key_info" | jq -r '.purpose // "unknown"')
    key_state=$(echo "$key_info" | jq -r '.primary.state // "unknown"')
    echo "  密钥用途: $key_purpose"
    echo "  密钥状态: $key_state"
else
    echo "  ✗ describe 失败 (缺少 cloudkms.cryptoKeys.get 权限)"
fi
echo ""

# 方法 2: list (需要 cloudkms.cryptoKeys.list 权限)
echo "方法 2: gcloud kms keys list"
key_list=$(gcloud kms keys list \
    --project="$KMS_PROJECT" \
    --keyring="$KEYRING" \
    --location="$LOCATION" \
    --filter="name:$CRYPTO_KEY" \
    --format=json 2>&1 || echo "[]")

key_count=$(echo "$key_list" | jq '. | length' 2>/dev/null || echo "0")

if [[ "$key_count" -gt 0 ]]; then
    echo "  ✓ list 成功 (有 cloudkms.cryptoKeys.list 权限)"
    echo "  找到 CryptoKey: $(echo "$key_list" | jq -r '.[0].name')"
    key_purpose=$(echo "$key_list" | jq -r '.[0].purpose // "unknown"')
    key_state=$(echo "$key_list" | jq -r '.[0].primary.state // "unknown"')
    echo "  密钥用途: $key_purpose"
    echo "  密钥状态: $key_state"
else
    echo "  ✗ list 失败或未找到 (缺少 cloudkms.cryptoKeys.list 权限或 Key 不存在)"
fi
echo ""

# ============================================================================
# 测试 IAM 策略访问
# ============================================================================
echo "3. 测试 IAM 策略访问"
echo "----------------------------------------"

echo "gcloud kms keys get-iam-policy"
if iam_policy=$(gcloud kms keys get-iam-policy "$CRYPTO_KEY" \
    --project="$KMS_PROJECT" \
    --keyring="$KEYRING" \
    --location="$LOCATION" \
    --format=json 2>&1); then
    echo "  ✓ get-iam-policy 成功 (有 cloudkms.cryptoKeys.getIamPolicy 权限)"
    bindings_count=$(echo "$iam_policy" | jq '.bindings | length // 0')
    echo "  IAM 绑定数量: $bindings_count"
else
    echo "  ✗ get-iam-policy 失败 (缺少 cloudkms.cryptoKeys.getIamPolicy 权限)"
fi
echo ""

# ============================================================================
# 总结
# ============================================================================
echo "=========================================="
echo "总结"
echo "=========================================="
echo ""
echo "权限对比:"
echo ""
echo "describe 方法需要的权限:"
echo "  - cloudkms.keyRings.get"
echo "  - cloudkms.cryptoKeys.get"
echo ""
echo "list 方法需要的权限:"
echo "  - cloudkms.keyRings.list"
echo "  - cloudkms.cryptoKeys.list"
echo ""
echo "建议:"
echo "  - 如果只有 list 权限，使用 list 方法（脚本已优化）"
echo "  - 如果有 get 权限，describe 方法可以获取更详细的信息"
echo "  - list 方法更适合最小权限原则"
echo ""
echo "当前脚本使用: list 方法 (v2.0.1+)"
