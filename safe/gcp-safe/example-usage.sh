#!/bin/bash

# GCP KMS 验证脚本使用示例

# ============================================================================
# 示例 1: 基础验证（推荐用于日常检查）
# ============================================================================
echo "示例 1: 基础验证"
./verify-kms-enhanced.sh \
  --kms-project aibang-project-id-kms-env \
  --business-project aibang-1234567-ajx01-env \
  --keyring aibang-1234567-ajx01-env \
  --key env01-uk-core-ajx \
  --location global \
  --service-accounts "ajx-env-uk-kbp-sa@aibang-1234567-ajx01-env.iam.gserviceaccount.com,env01-uk-kdp-sa@aibang-1234567-ajx01-env.iam.gserviceaccount.com,env01-uk-rt-sa@aibang-1234567-ajx01-env.iam.gserviceaccount.com"

# ============================================================================
# 示例 2: 详细模式（用于故障排查）
# ============================================================================
echo -e "\n\n示例 2: 详细模式"
./verify-kms-enhanced.sh \
  --kms-project aibang-project-id-kms-env \
  --business-project aibang-1234567-ajx01-env \
  --keyring aibang-1234567-ajx01-env \
  --key env01-uk-core-ajx \
  --location global \
  --service-accounts "env01-uk-encrypt-sa@aibang-1234567-ajx01-env.iam.gserviceaccount.com" \
  --verbose

# ============================================================================
# 示例 3: JSON 输出（用于 CI/CD 集成）
# ============================================================================
echo -e "\n\n示例 3: JSON 输出"
./verify-kms-enhanced.sh \
  --kms-project aibang-project-id-kms-env \
  --business-project aibang-1234567-ajx01-env \
  --keyring aibang-1234567-ajx01-env \
  --key env01-uk-core-ajx \
  --location global \
  --service-accounts "env01-uk-encrypt-sa@aibang-1234567-ajx01-env.iam.gserviceaccount.com" \
  --output-format json

# ============================================================================
# 示例 4: 完整测试（仅测试环境使用）
# ============================================================================
echo -e "\n\n示例 4: 完整功能测试"
./verify-kms-enhanced.sh \
  --kms-project aibang-project-id-kms-env \
  --business-project aibang-1234567-ajx01-env \
  --keyring aibang-1234567-ajx01-env \
  --key env01-uk-core-ajx \
  --location global \
  --service-accounts "env01-uk-encrypt-sa@aibang-1234567-ajx01-env.iam.gserviceaccount.com" \
  --test-encrypt \
  --test-decrypt \
  --verbose

# ============================================================================
# 示例 5: 跳过轮换检查（某些密钥不需要轮换）
# ============================================================================
echo -e "\n\n示例 5: 跳过轮换检查"
./verify-kms-enhanced.sh \
  --kms-project aibang-project-id-kms-env \
  --business-project aibang-1234567-ajx01-env \
  --keyring aibang-1234567-ajx01-env \
  --key env01-uk-core-ajx \
  --location global \
  --service-accounts "env01-uk-encrypt-sa@aibang-1234567-ajx01-env.iam.gserviceaccount.com" \
  --skip-rotation-check
