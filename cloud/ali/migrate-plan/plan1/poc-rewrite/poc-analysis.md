# K8s集群迁移POC可行性分析

## 需求背景总结

### 现状
- **旧集群**: 使用 `*.teamname.dev.aliyun.intracloud.cn.aibang` 域名
- **新集群**: 使用 `*.kong.dev.aliyun.intracloud.cn.aibang` 域名  
- **限制**: 无法修改DNS解析，不能做CNAME或A记录重定向
- **目标**: 用户继续访问旧域名，但请求要转发到新集群

### 核心思路验证
你的反向代理思路是**完全正确**的，这是最适合你场景的解决方案：
```
用户请求 -> 旧集群Ingress -> 反向代理 -> 新集群服务
```

## POC方案设计

### 方案1: 修改现有Ingress配置 (推荐)
利用nginx-ingress的upstream-vhost功能实现代理转发

**优点**: 
- 配置简单，无需额外资源
- 利用现有基础设施
- 切换和回滚都很方便

**缺点**: 
- 依赖nginx-ingress特定功能
- 配置相对固化

### 方案2: 独立Nginx代理服务
在旧集群部署独立的Nginx代理

**优点**: 
- 更灵活的配置控制
- 不依赖特定ingress实现
- 可以做更复杂的路由逻辑

**缺点**: 
- 需要额外的资源和维护
- 配置相对复杂

## 最简POC实现 (方案1)

### 步骤1: 准备新集群服务
确保新集群的服务已经部署并可通过新域名访问：
```bash
# 验证新集群服务可用性
curl -H "Host: api-name01.kong.dev.aliyun.intracloud.cn.aibang" \
     http://新集群IP/health
```

### 步骤2: 在旧集群创建ExternalName Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: new-cluster-proxy
  namespace: aibang-1111111111-bbdm
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

### 步骤3: 修改现有Ingress配置
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bbdm
  namespace: aibang-1111111111-bbdm
  annotations:
    # 关键配置：指定upstream的真实host
    nginx.ingress.kubernetes.io/upstream-vhost: "api-name01.kong.dev.aliyun.intracloud.cn.aibang"
    # 设置正确的Host头
    nginx.ingress.kubernetes.io/proxy-set-headers: |
      Host api-name01.kong.dev.aliyun.intracloud.cn.aibang
      X-Real-IP $remote_addr
      X-Forwarded-For $proxy_add_x_forwarded_for
      X-Forwarded-Proto $scheme
      X-Original-Host $host
spec:
  ingressClassName: nginx
  rules:
    - host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang
      http:
        paths:
          - backend:
              service:
                name: new-cluster-proxy  # 指向新创建的ExternalName服务
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

## POC验证步骤

### 1. 环境准备
```bash
# 确保kubectl连接到旧集群
kubectl config current-context

# 备份原始配置
kubectl get ingress bbdm -n aibang-1111111111-bbdm -o yaml > bbdm-original-backup.yaml
```

### 2. 部署代理配置
```bash
# 创建ExternalName服务
kubectl apply -f external-service.yaml

# 更新Ingress配置
kubectl apply -f updated-ingress.yaml
```

### 3. 验证代理效果
```bash
# 等待配置生效
sleep 30

# 测试代理是否工作
curl -v -H "Host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang" \
     http://10.190.192.3/health

# 检查nginx配置是否正确
kubectl exec -n kube-system $(kubectl get pods -n kube-system -l app=nginx-ingress -o name | head -1) \
  -- cat /etc/nginx/nginx.conf | grep -A 20 "api-name01.teamname"
```

### 4. 回滚方案
如果出现问题，立即回滚：
```bash
kubectl apply -f bbdm-original-backup.yaml
kubectl delete service new-cluster-proxy -n aibang-1111111111-bbdm
```

## 风险评估

### 高风险
- **SSL证书问题**: 新集群必须有对应域名的SSL证书
- **会话保持**: 如果应用依赖session sticky，需要额外配置

### 中风险  
- **性能影响**: 增加一层代理会有轻微延迟
- **健康检查**: 需要确保upstream健康检查正常

### 低风险
- **配置复杂度**: nginx-ingress的配置相对简单
- **回滚能力**: 可以快速回滚到原始配置

## 成功标准

### 功能验证
- [ ] 通过旧域名可以正常访问服务
- [ ] 请求正确转发到新集群
- [ ] 响应内容与直接访问新集群一致
- [ ] SSL/TLS正常工作

### 性能验证  
- [ ] 响应时间增加不超过50ms
- [ ] 并发处理能力无明显下降
- [ ] 错误率保持在原有水平

### 运维验证
- [ ] 可以快速回滚到原始配置
- [ ] 日志和监控正常工作
- [ ] 健康检查机制有效

## 下一步计划

1. **POC验证** (1-2天)
   - 在测试环境验证基本功能
   - 确认配置的正确性

2. **脚本开发** (2-3天)  
   - 开发自动化迁移脚本
   - 支持批量操作和回滚

3. **生产部署** (按需)
   - 灰度迁移策略
   - 监控和告警配置

这个POC方案风险可控，实现简单，你觉得可以开始验证吗？