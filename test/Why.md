# 服务迁移中CNAME切换后证书报错问题分析

## 背景
- 旧工程的K8S服务迁移到新工程
- 使用CNAME将用户请求从旧域名切换到新工程
- 目标：保持用户原入口地址不变
- 问题：切换域名后服务无法访问，出现证书报错

## 可能原因分析

### 1. 证书域名不匹配（最常见）
**问题描述：**
- 新工程的SSL/TLS证书中的域名（CN或SAN）与用户访问的域名不匹配
- CNAME只是DNS层面的别名，不会改变HTTP请求中的Host头

**具体场景：**
```
用户访问: old-service.company.com (CNAME -> new-service.company.com)
新服务证书: *.new-service.company.com 或 new-service.company.com
请求Host头: old-service.company.com
结果: 证书域名不匹配，浏览器/客户端报错
```

**解决方案：**
- 在新服务的证书中添加旧域名到SAN（Subject Alternative Name）列表
- 使用通配符证书覆盖两个域名
- 配置Ingress/LoadBalancer支持多域名证书

### 2. SNI（Server Name Indication）配置问题
**问题描述：**
- 现代HTTPS连接使用SNI在TLS握手时指定目标主机名
- 如果新服务的负载均衡器或Ingress Controller的SNI配置不正确

**具体场景：**
- 客户端通过SNI发送 `old-service.company.com`
- 新服务只配置了 `new-service.company.com` 的证书
- TLS握手失败

**解决方案：**
- 在Ingress或LoadBalancer中配置多个host规则
- 确保两个域名都有对应的证书配置

### 3. 证书链不完整
**问题描述：**
- 新服务的证书链配置不完整，缺少中间证书
- 某些客户端无法验证证书的信任链

**解决方案：**
- 确保证书配置包含完整的证书链（服务器证书 + 中间证书）
- 使用 `openssl s_client` 验证证书链完整性

### 4. 证书过期或未生效
**问题描述：**
- 新服务使用的证书已过期或尚未到生效时间
- 迁移过程中证书更新不及时

**解决方案：**
- 检查证书的有效期（NotBefore 和 NotAfter）
- 使用自动化证书管理工具（如cert-manager）

### 5. Ingress/Service配置问题
**问题描述：**
- K8S Ingress资源中未配置旧域名
- TLS secret未正确关联到Ingress

**具体场景：**
```yaml
# 错误配置示例
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: new-service
spec:
  tls:
  - hosts:
    - new-service.company.com  # 只配置了新域名
    secretName: new-service-tls
  rules:
  - host: new-service.company.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: new-service
            port:
              number: 80
```

**解决方案：**
```yaml
# 正确配置示例
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: new-service
spec:
  tls:
  - hosts:
    - new-service.company.com
    - old-service.company.com  # 添加旧域名
    secretName: new-service-tls  # 确保证书包含两个域名
  rules:
  - host: new-service.company.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: new-service
            port:
              number: 80
  - host: old-service.company.com  # 添加旧域名规则
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: new-service
            port:
              number: 80
```

### 6. 负载均衡器SSL终止配置
**问题描述：**
- 如果使用云服务商的负载均衡器（如AWS ALB、GCP Load Balancer）
- SSL终止在负载均衡器层，但证书配置不包含旧域名

**解决方案：**
- 在负载均衡器中添加旧域名的证书
- 或配置证书支持多域名

### 7. CNAME传播延迟与证书缓存
**问题描述：**
- DNS CNAME记录尚未完全传播
- 客户端或中间代理缓存了旧的证书信息

**解决方案：**
- 等待DNS TTL过期，确保CNAME记录全局生效
- 清除客户端SSL/TLS会话缓存
- 检查CDN或反向代理的证书缓存

### 8. 证书颁发机构（CA）信任问题
**问题描述：**
- 新服务使用的证书由不受信任的CA签发
- 自签名证书或内部CA证书未在客户端安装

**解决方案：**
- 使用公认的CA（如Let's Encrypt、DigiCert）
- 如果使用内部CA，确保客户端信任该CA

### 9. 协议版本不兼容
**问题描述：**
- 新服务只支持较新的TLS版本（如TLS 1.3）
- 旧客户端只支持TLS 1.0/1.1

**解决方案：**
- 配置新服务支持向后兼容的TLS版本
- 平衡安全性和兼容性需求

### 10. 防火墙或安全组规则
**问题描述：**
- 新工程的网络安全规则未正确配置
- HTTPS端口（443）未开放或限制了来源

**解决方案：**
- 检查K8S NetworkPolicy、云安全组、防火墙规则
- 确保443端口对外开放

## 排查步骤

### 1. 验证DNS解析
```bash
# 检查CNAME记录
dig old-service.company.com CNAME
nslookup old-service.company.com

# 验证最终解析的IP
dig old-service.company.com A
```

### 2. 检查证书信息
```bash
# 查看服务器证书
openssl s_client -connect old-service.company.com:443 -servername old-service.company.com

# 检查证书域名
echo | openssl s_client -connect old-service.company.com:443 -servername old-service.company.com 2>/dev/null | openssl x509 -noout -text | grep -A1 "Subject Alternative Name"

# 检查证书有效期
echo | openssl s_client -connect old-service.company.com:443 -servername old-service.company.com 2>/dev/null | openssl x509 -noout -dates
```

### 3. 测试不同域名访问
```bash
# 直接访问新域名
curl -v https://new-service.company.com

# 通过旧域名访问
curl -v https://old-service.company.com

# 强制使用特定Host头
curl -v https://new-service.company.com -H "Host: old-service.company.com"
```

### 4. 检查K8S配置
```bash
# 查看Ingress配置
kubectl get ingress -n <namespace> -o yaml

# 查看TLS Secret
kubectl get secret <secret-name> -n <namespace> -o yaml

# 查看证书内容
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text
```

### 5. 查看日志
```bash
# Ingress Controller日志
kubectl logs -n ingress-nginx <ingress-controller-pod>

# 应用服务日志
kubectl logs -n <namespace> <pod-name>
```

## 最佳实践建议

1. **提前准备证书**
   - 在迁移前准备包含新旧域名的证书
   - 使用通配符证书或多域名证书

2. **灰度切换**
   - 先小范围测试CNAME切换
   - 使用加权DNS或流量分割逐步迁移

3. **监控告警**
   - 配置SSL证书过期监控
   - 设置证书域名匹配检查

4. **文档记录**
   - 记录所有域名和证书的对应关系
   - 维护迁移检查清单

5. **回滚方案**
   - 保留旧服务一段时间
   - 准备快速回滚DNS的方案

## 总结

CNAME切换后证书报错最常见的原因是**证书域名不匹配**。由于CNAME只是DNS层面的别名，客户端仍然使用原域名发起HTTPS请求，因此新服务的证书必须包含旧域名。建议优先检查：

1. 新服务证书的SAN列表是否包含旧域名
2. Ingress配置是否同时配置了新旧域名
3. 使用 `openssl s_client` 和 `curl -v` 进行详细排查

解决此问题的核心是确保新服务能够为旧域名提供有效的SSL证书。
