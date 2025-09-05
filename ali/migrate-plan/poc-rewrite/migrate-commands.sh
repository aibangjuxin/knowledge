#!/bin/bash

# K8s集群迁移命令集合

set -e

# 配置变量
NAMESPACE="aibang-1111111111-bbdm"
INGRESS_NAME="bbdm"
SERVICE_NAME="new-cluster-proxy"
NEW_HOST="api-name01.kong.dev.aliyun.intracloud.cn.aibang"

echo "=== K8s集群迁移命令 ==="

echo "1. 部署原始Ingress (如果还没有部署):"
echo "kubectl apply -f old-ingress.yaml"
echo ""

echo "2. 创建ExternalName服务:"
echo "kubectl apply -f external-service.yaml"
echo ""

echo "3. 方式A: 直接应用新的Ingress配置:"
echo "kubectl apply -f new-ingress.yaml"
echo ""

echo "4. 方式B: 使用patch命令更新现有Ingress:"
cat << 'EOF'
kubectl patch ingress bbdm -n aibang-1111111111-bbdm --type=merge -p '{
  "metadata": {
    "annotations": {
      "migration/status": "migrated",
      "migration/target": "api-name01.kong.dev.aliyun.intracloud.cn.aibang",
      "migration/timestamp": "'$(date -Iseconds)'",
      "nginx.ingress.kubernetes.io/upstream-vhost": "api-name01.kong.dev.aliyun.intracloud.cn.aibang",
      "nginx.ingress.kubernetes.io/backend-protocol": "HTTP",
      "nginx.ingress.kubernetes.io/proxy-set-headers": "Host api-name01.kong.dev.aliyun.intracloud.cn.aibang\nX-Real-IP $remote_addr\nX-Forwarded-For $proxy_add_x_forwarded_for\nX-Forwarded-Proto $scheme\nX-Original-Host $host"
    }
  },
  "spec": {
    "rules": [
      {
        "host": "api-name01.teamname.dev.aliyun.intracloud.cn.aibang",
        "http": {
          "paths": [
            {
              "path": "/",
              "pathType": "ImplementationSpecific",
              "backend": {
                "service": {
                  "name": "new-cluster-proxy",
                  "port": {
                    "number": 80
                  }
                }
              }
            }
          ]
        }
      },
      {
        "host": "api-name01.01.teamname.dev.aliyun.intracloud.cn.aibang",
        "http": {
          "paths": [
            {
              "path": "/",
              "pathType": "ImplementationSpecific",
              "backend": {
                "service": {
                  "name": "new-cluster-proxy",
                  "port": {
                    "number": 80
                  }
                }
              }
            }
          ]
        }
      }
    ]
  }
}'
EOF
echo ""

echo "5. 验证迁移结果:"
echo "kubectl get ingress bbdm -n aibang-1111111111-bbdm"
echo "kubectl get service new-cluster-proxy -n aibang-1111111111-bbdm"
echo ""

echo "6. 测试代理功能:"
echo "curl -H \"Host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang\" http://10.190.192.3/"
echo ""

echo "7. 回滚命令 (如果需要):"
echo "kubectl apply -f old-ingress.yaml"
echo "kubectl delete service new-cluster-proxy -n aibang-1111111111-bbdm"
echo ""

echo "=== 完整迁移流程 ==="
echo "# 步骤1: 备份原始配置"
echo "kubectl get ingress bbdm -n aibang-1111111111-bbdm -o yaml > backup-ingress.yaml"
echo ""
echo "# 步骤2: 创建代理服务"
echo "kubectl apply -f external-service.yaml"
echo ""
echo "# 步骤3: 更新Ingress (选择方式A或B)"
echo "kubectl apply -f new-ingress.yaml  # 方式A"
echo "# 或者使用上面的patch命令      # 方式B"
echo ""
echo "# 步骤4: 验证功能"
echo "curl -H \"Host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang\" http://10.190.192.3/"