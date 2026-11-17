#!/bin/bash

# DNS Configuration File
# Source this file to set environment variables

# Default configuration
export DNS_API_BASE_URL="https://domain/api/v1"
export DNS_TOKEN="abcdef"
export DNS_DOMAIN_NAME="aliyun.cloud.cn.aibang"

# Environment-specific configurations
case "${DNS_ENV:-production}" in
    "development")
        export DNS_API_BASE_URL="https://dev-domain/api/v1"
        export DNS_TOKEN="dev-token"
        export DNS_DOMAIN_NAME="dev.aliyun.cloud.cn.aibang"
        ;;
    "staging")
        export DNS_API_BASE_URL="https://staging-domain/api/v1"
        export DNS_TOKEN="staging-token"
        export DNS_DOMAIN_NAME="staging.aliyun.cloud.cn.aibang"
        ;;
    "production")
        # Use default values above
        ;;
esac

echo "DNS Configuration loaded:"
echo "  Environment: ${DNS_ENV:-production}"
echo "  API URL: $DNS_API_BASE_URL"
echo "  Domain: $DNS_DOMAIN_NAME"