# 实施指南

## 1. 实施步骤概览

### 阶段 1: 基础设施准备
1. 创建 GCE VM 作为二级代理
2. 配置网络和防火墙规则
3. 安装和配置 VM 上的 Squid

### 阶段 2: GKE 集群配置
1. 创建 intra-proxy namespace
2. 部署 GKE 内部 Squid
3. 配置 DNS 解析

### 阶段 3: 应用集成
1. 配置 API Pod 的代理设置
2. 测试连通性
3. 监控和调优

## 2. 详细实施步骤

### 2.1 GCE VM 准备

#### 创建 VM 实例
```bash
# 创建 GCE VM
gcloud compute instances create int-proxy-vm \
    --zone=asia-east1-a \
    --machine-type=e2-medium \
    --subnet=default \
    --network-tier=PREMIUM \
    --maintenance-policy=MIGRATE \
    --image-family=ubuntu-2004-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=20GB \
    --boot-disk-type=pd-standard \
    --tags=proxy-server
```

#### 配置防火墙规则
```bash
# 允许来自 GKE 集群的连接
gcloud compute firewall-rules create allow-gke-to-proxy \
    --allow tcp:3128 \
    --source-ranges=10.128.0.0/20 \
    --target-tags=proxy-server \
    --description="Allow GKE cluster to access proxy"

# 允许 VM 访问外网 (如果需要)
gcloud compute firewall-rules create allow-proxy-egress \
    --direction=EGRESS \
    --action=ALLOW \
    --rules=tcp:80,tcp:443 \
    --target-tags=proxy-server
```

#### 安装和配置 Squid
```bash
# SSH 到 VM
gcloud compute ssh int-proxy-vm --zone=asia-east1-a

# 安装 Squid
sudo apt update
sudo apt install -y squid

# 备份原配置
sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.backup

# 应用新配置 (使用前面提供的 GCE VM 配置)
sudo vim /etc/squid/squid.conf

# 启动服务
sudo systemctl enable squid
sudo systemctl start squid
sudo systemctl status squid
```

### 2.2 GKE 集群配置

#### 创建 Namespace
```yaml
# intra-proxy-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: intra-proxy
  labels:
    name: intra-proxy
```

#### Squid ConfigMap
```yaml
# squid-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: squid-config
  namespace: intra-proxy
data:
  squid.conf: |
    # 这里放入前面提供的 GKE Squid 配置内容
    http_port 3128
    coredump_dir /var/spool/squid
    
    cache_mem 256 MB
    maximum_object_size_in_memory 512 KB
    cache_dir ufs /var/spool/squid 1000 16 256
    
    access_log /var/log/squid/access.log squid
    cache_log /var/log/squid/cache.log
    
    acl localnet src 10.0.0.0/8
    acl localnet src 172.16.0.0/12
    acl localnet src 192.168.0.0/16
    
    acl allowed_domains dstdomain .microsoft.com
    acl allowed_domains dstdomain .microsoftonline.com
    acl allowed_domains dstdomain .azure.com
    acl allowed_domains dstdomain login.microsoft.com
    
    acl Safe_ports port 80
    acl Safe_ports port 443
    acl CONNECT method CONNECT
    
    http_access deny !Safe_ports
    http_access deny CONNECT !allowed_domains
    http_access allow localnet allowed_domains
    http_access deny all
    
    cache_peer int-proxy.aibang.com parent 3128 0 no-query default
    never_direct allow all
    
    forwarded_for on
    via on
```

#### Squid Deployment
```yaml
# squid-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: squid-proxy
  namespace: intra-proxy
spec:
  replicas: 2
  selector:
    matchLabels:
      app: squid-proxy
  template:
    metadata:
      labels:
        app: squid-proxy
    spec:
      containers:
      - name: squid
        image: ubuntu/squid:latest
        ports:
        - containerPort: 3128
        volumeMounts:
        - name: squid-config
          mountPath: /etc/squid/squid.conf
          subPath: squid.conf
        - name: squid-cache
          mountPath: /var/spool/squid
        - name: squid-logs
          mountPath: /var/log/squid
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          tcpSocket:
            port: 3128
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          tcpSocket:
            port: 3128
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: squid-config
        configMap:
          name: squid-config
      - name: squid-cache
        emptyDir: {}
      - name: squid-logs
        emptyDir: {}
```

#### Squid Service
```yaml
# squid-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: squid-proxy-service
  namespace: intra-proxy
spec:
  selector:
    app: squid-proxy
  ports:
  - protocol: TCP
    port: 3128
    targetPort: 3128
  type: ClusterIP
```

### 2.3 DNS 配置

#### CoreDNS 自定义配置
```yaml
# coredns-custom.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  proxy.server: |
    microsoft.intra.aibang.local:53 {
        errors
        cache 30
        forward . /etc/resolv.conf
        rewrite name microsoft.intra.aibang.local squid-proxy-service.intra-proxy.svc.cluster.local
    }
```

### 2.4 应用配置示例

#### API Pod 环境变量配置
```yaml
# api-deployment.yaml (示例)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-service
spec:
  template:
    spec:
      containers:
      - name: api
        image: your-api-image
        env:
        - name: HTTP_PROXY
          value: "http://microsoft.intra.aibang.local:3128"
        - name: HTTPS_PROXY
          value: "http://microsoft.intra.aibang.local:3128"
        - name: NO_PROXY
          value: "localhost,127.0.0.1,.cluster.local,.svc"
```

## 3. 测试和验证

### 3.1 基础连通性测试
```bash
# 在 API Pod 中测试
kubectl exec -it <api-pod> -- bash

# 测试代理连接
curl -x http://microsoft.intra.aibang.local:3128 https://login.microsoft.com -v

# 测试环境变量
curl https://login.microsoft.com -v
```

### 3.2 日志验证
```bash
# 查看 GKE Squid 日志
kubectl logs -n intra-proxy deployment/squid-proxy

# 查看 GCE VM Squid 日志
gcloud compute ssh int-proxy-vm --zone=asia-east1-a
sudo tail -f /var/log/squid/access.log
```

## 4. 监控和运维

### 4.1 监控指标
- Squid 连接数
- 请求成功率
- 响应时间
- 缓存命中率
- 错误日志

### 4.2 告警配置
```yaml
# squid-monitoring.yaml
apiVersion: v1
kind: Service
metadata:
  name: squid-metrics
  namespace: intra-proxy
  labels:
    app: squid-proxy
spec:
  ports:
  - name: metrics
    port: 9301
    targetPort: 9301
  selector:
    app: squid-proxy
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: squid-proxy
  namespace: intra-proxy
spec:
  selector:
    matchLabels:
      app: squid-proxy
  endpoints:
  - port: metrics
```

## 5. 故障排查

### 5.1 常见问题
1. **连接超时**: 检查防火墙规则和网络连通性
2. **DNS 解析失败**: 验证 CoreDNS 配置
3. **代理拒绝连接**: 检查 Squid ACL 配置
4. **HTTPS 证书问题**: 配置 SSL bump 或使用 CONNECT 方法

### 5.2 调试命令
```bash
# 检查 Squid 状态
squidclient -h localhost cache_object://localhost/info

# 检查 ACL
squidclient -h localhost cache_object://localhost/config

# 测试特定 URL
squidclient -h localhost -p 3128 https://login.microsoft.com
```