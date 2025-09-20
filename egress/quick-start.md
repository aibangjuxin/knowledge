# 快速开始指南

## 1. 前置条件检查

### 1.1 环境要求
```bash
# 检查 GCP 项目和权限
gcloud config get-value project
gcloud auth list

# 检查 GKE 集群连接
kubectl cluster-info
kubectl get nodes

# 检查网络配置
kubectl get svc -A | grep -E "(dns|coredns)"
```

### 1.2 权限要求
- GCE 实例创建权限
- GKE 集群管理权限
- 防火墙规则管理权限
- DNS 配置权限

## 2. 30分钟快速部署

### Step 1: 创建 GCE VM (5分钟)

```bash
# 创建代理 VM
gcloud compute instances create int-proxy-vm \
    --zone=asia-east1-a \
    --machine-type=e2-medium \
    --subnet=default \
    --image-family=ubuntu-2004-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=20GB \
    --tags=proxy-server \
    --metadata=startup-script='#!/bin/bash
apt update
apt install -y squid
systemctl enable squid'

# 配置防火墙
gcloud compute firewall-rules create allow-gke-to-proxy \
    --allow tcp:3128 \
    --source-ranges=10.128.0.0/20 \
    --target-tags=proxy-server
```

### Step 2: 配置 GCE Squid (5分钟)

```bash
# SSH 到 VM
gcloud compute ssh int-proxy-vm --zone=asia-east1-a

# 快速配置 Squid
sudo tee /etc/squid/squid.conf > /dev/null <<EOF
http_port 3128
acl gke_cluster src 10.128.0.0/20
acl microsoft_domains dstdomain .microsoft.com .microsoftonline.com
acl Safe_ports port 80 443
acl CONNECT method CONNECT
http_access deny !Safe_ports
http_access allow gke_cluster microsoft_domains
http_access deny all
access_log /var/log/squid/access.log
EOF

# 重启服务
sudo systemctl restart squid
sudo systemctl status squid

# 退出 VM
exit
```

### Step 3: 部署 GKE Squid (10分钟)

```bash
# 创建 namespace
kubectl create namespace intra-proxy

# 创建 ConfigMap
kubectl create configmap squid-config -n intra-proxy --from-literal=squid.conf='
http_port 3128
acl localnet src 10.0.0.0/8
acl allowed_domains dstdomain .microsoft.com .microsoftonline.com
acl Safe_ports port 80 443
acl CONNECT method CONNECT
http_access deny !Safe_ports
http_access allow localnet allowed_domains
http_access deny all
cache_peer int-proxy.aibang.com parent 3128 0 no-query default
never_direct allow all
access_log /var/log/squid/access.log
'

# 部署 Squid
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: squid-proxy
  namespace: intra-proxy
spec:
  replicas: 1
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
      volumes:
      - name: squid-config
        configMap:
          name: squid-config
---
apiVersion: v1
kind: Service
metadata:
  name: squid-proxy-service
  namespace: intra-proxy
spec:
  selector:
    app: squid-proxy
  ports:
  - port: 3128
    targetPort: 3128
  type: ClusterIP
EOF
```

### Step 4: 配置 DNS 解析 (5分钟)

```bash
# 获取 Service IP
SQUID_SERVICE_IP=$(kubectl get svc squid-proxy-service -n intra-proxy -o jsonpath='{.spec.clusterIP}')
echo "Squid Service IP: $SQUID_SERVICE_IP"

# 配置 CoreDNS (简化版本 - 直接修改 hosts)
kubectl patch configmap coredns -n kube-system --patch='
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        hosts {
           '${SQUID_SERVICE_IP}' microsoft.intra.aibang.local
           fallthrough
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
'

# 重启 CoreDNS
kubectl rollout restart deployment/coredns -n kube-system
```

### Step 5: 快速测试 (5分钟)

```bash
# 创建测试 Pod
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -- sh

# 在 Pod 内测试 (执行以下命令)
# 测试 DNS 解析
nslookup microsoft.intra.aibang.local

# 测试代理连接
curl -x http://microsoft.intra.aibang.local:3128 https://login.microsoft.com -I -v

# 退出测试 Pod
exit
```

## 3. 验证部署

### 3.1 检查各组件状态

```bash
# 检查 GCE VM
gcloud compute instances describe int-proxy-vm --zone=asia-east1-a --format="value(status)"

# 检查 GKE Squid
kubectl get pods -n intra-proxy
kubectl get svc -n intra-proxy

# 检查日志
kubectl logs -n intra-proxy deployment/squid-proxy
```

### 3.2 端到端测试

```bash
# 创建带代理配置的测试应用
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: proxy-test-app
spec:
  containers:
  - name: app
    image: curlimages/curl
    env:
    - name: HTTP_PROXY
      value: "http://microsoft.intra.aibang.local:3128"
    - name: HTTPS_PROXY
      value: "http://microsoft.intra.aibang.local:3128"
    command: ["sleep", "3600"]
EOF

# 测试代理访问
kubectl exec proxy-test-app -- curl https://login.microsoft.com -I
```

## 4. 故障排查快速指南

### 4.1 常见问题

**问题 1: DNS 解析失败**
```bash
# 检查 CoreDNS 配置
kubectl get configmap coredns -n kube-system -o yaml

# 测试 DNS
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup microsoft.intra.aibang.local
```

**问题 2: 代理连接超时**
```bash
# 检查 Squid 服务状态
kubectl get svc -n intra-proxy
kubectl describe svc squid-proxy-service -n intra-proxy

# 检查 Pod 状态
kubectl get pods -n intra-proxy
kubectl logs -n intra-proxy deployment/squid-proxy
```

**问题 3: GCE VM 不可达**
```bash
# 检查防火墙规则
gcloud compute firewall-rules list --filter="name:allow-gke-to-proxy"

# 检查 VM 状态
gcloud compute instances describe int-proxy-vm --zone=asia-east1-a

# 测试网络连通性
kubectl run network-test --image=busybox --rm -it --restart=Never -- telnet int-proxy.aibang.com 3128
```

### 4.2 调试命令

```bash
# 查看 Squid 配置
kubectl exec -n intra-proxy deployment/squid-proxy -- cat /etc/squid/squid.conf

# 查看 Squid 进程
kubectl exec -n intra-proxy deployment/squid-proxy -- ps aux | grep squid

# 查看网络连接
kubectl exec -n intra-proxy deployment/squid-proxy -- netstat -tlnp
```

## 5. 生产环境优化

### 5.1 高可用配置

```bash
# 增加 Squid 副本数
kubectl scale deployment squid-proxy -n intra-proxy --replicas=3

# 配置 Pod 反亲和性
kubectl patch deployment squid-proxy -n intra-proxy --patch='
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - squid-proxy
              topologyKey: kubernetes.io/hostname
'
```

### 5.2 监控配置

```bash
# 添加监控标签
kubectl label namespace intra-proxy monitoring=enabled

# 配置 ServiceMonitor (如果使用 Prometheus Operator)
kubectl apply -f - <<EOF
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
EOF
```

## 6. 清理环境

```bash
# 删除 GKE 资源
kubectl delete namespace intra-proxy

# 恢复 CoreDNS 配置
kubectl patch configmap coredns -n kube-system --patch='{"data":{"Corefile":".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . /etc/resolv.conf {\n       max_concurrent 1000\n    }\n    cache 30\n    loop\n    reload\n    loadbalance\n}"}}'

# 删除 GCE 资源
gcloud compute instances delete int-proxy-vm --zone=asia-east1-a --quiet
gcloud compute firewall-rules delete allow-gke-to-proxy --quiet
```

这个快速开始指南可以让你在 30 分钟内完成基本的代理环境搭建和测试。