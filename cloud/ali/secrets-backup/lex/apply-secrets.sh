#!/bin/bash
# 应用导出的 secrets 到目标集群
set -e

NAMESPACE="${1:-}"
if [ -z "$NAMESPACE" ]; then
    echo "用法: $0 <target-namespace>"
    exit 1
fi

# 确保目标 namespace 存在
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 应用所有 secret YAML 文件
for yaml_file in *.yaml; do
    if [ -f "$yaml_file" ]; then
        echo "应用: $yaml_file"
        kubectl apply -f "$yaml_file" -n "$NAMESPACE"
    fi
done

echo "所有 secrets 已成功应用到 namespace: $NAMESPACE"
