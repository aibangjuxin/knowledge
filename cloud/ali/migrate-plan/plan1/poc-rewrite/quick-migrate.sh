#!/bin/bash

# 一键迁移脚本

set -e

NAMESPACE="aibang-1111111111-bbdm"
INGRESS_NAME="bbdm"

echo "🚀 开始K8s集群迁移..."

# 1. 备份原始配置
echo "📦 备份原始配置..."
kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o yaml > backup-ingress-$(date +%Y%m%d_%H%M%S).yaml
echo "✅ 备份完成"

# 2. 创建ExternalName服务
echo "🔗 创建代理服务..."
kubectl apply -f external-service.yaml
echo "✅ 代理服务创建完成"

# 3. 更新Ingress配置
echo "⚙️  更新Ingress配置..."
kubectl apply -f new-ingress.yaml
echo "✅ Ingress配置更新完成"

# 4. 等待配置生效
echo "⏳ 等待配置生效..."
sleep 30

# 5. 验证迁移结果
echo "🔍 验证迁移结果..."
kubectl get ingress $INGRESS_NAME -n $NAMESPACE
kubectl get service new-cluster-proxy -n $NAMESPACE

echo ""
echo "🎉 迁移完成！"
echo ""
echo "测试命令:"
echo "curl -H \"Host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang\" http://10.190.192.3/"
echo ""
echo "如需回滚，请执行:"
echo "kubectl apply -f backup-ingress-*.yaml"
echo "kubectl delete service new-cluster-proxy -n $NAMESPACE"