# POC实施指南

## 准备工作

### 1. 环境检查
```bash
# 检查当前kubectl上下文
kubectl config current-context

# 检查旧集群ingress controller状态
kubectl get pods -n kube-system -l app=nginx-ingress

# 检查目标namespace
kubectl get ns aibang-1111111111-bbdm

# 检查现有ingress配置
kubectl get ingress bbdm -n aibang-1111111111-bbdm -o yaml
```

### 2. 备份原始配置
```bash
# 创建备份目录
mkdir -p ./poc-backup/$(date +%Y%m%d_%H%M%S)

# 备份原始ingress配置
kubectl get ingress bbdm -n aibang-1111111111-bbdm -o yaml > ./poc-backup/$(date +%Y%m%d_%H%M%S)/bbdm-original.yaml

# 备份相关service配置
kubectl get service bbdm-api -n aibang-1111111111-bbdm -o yaml > ./poc-backup/$(date +%Y%m%d_%H%M%S)/bbdm-api-service.yaml
```

## POC配置文件

### 1. ExternalName Service配置
```yaml
# external-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: new-cluster-proxy
  namespace: aibang-1111111111-bbdm
  labels:
    migration: "poc"
    target: "new-cluster"
spec:
  type: ExternalName
  externalName: api-name01.kong.dev.aliyun.intracloud.cn.aibang
  ports:
    - name: http
      port: 80
      targetPort: 80
    - name: https
      port: 443
      targetPort: 443
```

### 2. 更新后的Ingress配置
```yaml
# updated-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bbdm
  namespace: aibang-1111111111-bbdm
  labels:
    app.kubernetes.io/instance: api-name01
  annotations:
    # POC标记
    migration/status: "poc-testing"
    migration/target: "api-name01.kong.dev.aliyun.intracloud.cn.aibang"
    migration/timestamp: "2025-02-09T00:00:00Z"
    
    # 核心代理配置
    nginx.ingress.kubernetes.io/upstream-vhost: "api-name01.kong.dev.aliyun.intracloud.cn.aibang"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    
    # 设置正确的请求头
    nginx.ingress.kubernetes.io/proxy-set-headers: |
      Host api-name01.kong.dev.aliyun.intracloud.cn.aibang
      X-Real-IP $remote_addr
      X-Forwarded-For $proxy_add_x_forwarded_for
      X-Forwarded-Proto $scheme
      X-Original-Host $host
      X-Forwarded-Host $host
    
    # 可选：超时配置
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
spec:
  ingressClassName: nginx
  rules:
    - host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang
      http:
        paths:
          - backend:
              service:
                name: new-cluster-proxy
                port:
                  number: 80
            path: /
            pathType: ImplementationSpecific
    - host: api-name01.01.teamname.dev.aliyun.intracloud.cn.aibang
      http:
        paths:
          - backend:
              service:
                name: new-cluster-proxy
                port:
                  number: 80
            path: /
            pathType: ImplementationSpecific
```

## 执行步骤

### 第一阶段：部署代理配置
```bash
# 1. 创建ExternalName服务
kubectl apply -f external-service.yaml

# 2. 验证服务创建成功
kubectl get service new-cluster-proxy -n aibang-1111111111-bbdm

# 3. 更新Ingress配置
kubectl apply -f updated-ingress.yaml

# 4. 验证配置更新
kubectl get ingress bbdm -n aibang-1111111111-bbdm -o yaml
```

### 第二阶段：验证代理功能
```bash
# 等待配置生效（通常需要30-60秒）
sleep 60

# 测试HTTP请求
curl -v -H "Host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang" \
     http://10.190.192.3/

# 如果有健康检查端点
curl -H "Host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang" \
     http://10.190.192.3/health

# 测试第二个域名
curl -H "Host: api-name01.01.teamname.dev.aliyun.intracloud.cn.aibang" \
     http://10.190.192.3/health
```

### 第三阶段：深度验证
```bash
# 检查nginx配置是否正确生成
kubectl exec -n kube-system $(kubectl get pods -n kube-system -l app=nginx-ingress -o name | head -1) \
  -- cat /etc/nginx/nginx.conf | grep -A 30 "api-name01.teamname"

# 查看ingress controller日志
kubectl logs -n kube-system -l app=nginx-ingress --tail=50

# 检查代理服务的endpoints
kubectl get endpoints new-cluster-proxy -n aibang-1111111111-bbdm
```

## 验证清单

### 基础功能验证
- [ ] ExternalName服务创建成功
- [ ] Ingress配置更新成功  
- [ ] 通过旧域名可以访问服务
- [ ] 响应内容正确

### 高级功能验证
- [ ] HTTP和HTTPS都正常工作
- [ ] 请求头正确传递
- [ ] 错误处理正常（404, 500等）
- [ ] 长连接和流式响应正常

### 性能验证
```bash
# 简单性能测试
time curl -H "Host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang" \
          http://10.190.192.3/health

# 并发测试（如果有ab工具）
ab -n 100 -c 10 -H "Host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang" \
   http://10.190.192.3/health
```

## 问题排查

### 常见问题及解决方案

#### 1. 502 Bad Gateway
```bash
# 检查ExternalName解析
nslookup api-name01.kong.dev.aliyun.intracloud.cn.aibang

# 检查新集群服务是否可达
curl -H "Host: api-name01.kong.dev.aliyun.intracloud.cn.aibang" \
     http://新集群IP/health
```

#### 2. 404 Not Found  
```bash
# 检查ingress配置是否生效
kubectl describe ingress bbdm -n aibang-1111111111-bbdm

# 检查nginx配置重载
kubectl logs -n kube-system -l app=nginx-ingress | grep reload
```

#### 3. SSL/TLS问题
```bash
# 检查证书配置
kubectl get secret -n aibang-1111111111-bbdm | grep tls

# 测试HTTPS
curl -k -H "Host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang" \
     https://10.190.192.3/health
```

## 回滚方案

### 快速回滚
```bash
# 恢复原始配置
kubectl apply -f ./poc-backup/$(ls -t ./poc-backup/ | head -1)/bbdm-original.yaml

# 删除代理服务
kubectl delete service new-cluster-proxy -n aibang-1111111111-bbdm

# 验证回滚成功
kubectl get ingress bbdm -n aibang-1111111111-bbdm -o yaml
```

### 验证回滚
```bash
# 测试原始功能是否恢复
curl -H "Host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang" \
     http://10.190.192.3/health
```

## 成功标准

POC被认为成功需要满足：

1. **功能完整性**: 所有原有功能正常工作
2. **性能可接受**: 响应时间增加不超过100ms  
3. **稳定性良好**: 连续运行1小时无异常
4. **回滚可靠**: 可以在5分钟内完成回滚

满足以上条件后，可以进入下一阶段的脚本开发和批量迁移准备。