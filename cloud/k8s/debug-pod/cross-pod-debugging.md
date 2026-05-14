- [GKE Pod 跨 Pod 调试指南](#gke-pod-跨-pod-调试指南)
  - [跨 Pod 调试方法](#跨-pod-调试方法)
    - [方法 1: 利用 Pod B 调试 Pod A](#方法-1-利用-pod-b-调试-pod-a)
    - [方法 2: 通过服务名访问](#方法-2-通过服务名访问)
  - [调试策略推荐](#调试策略推荐)
    - [1. **首选：Ephemeral 容器**（如果 GKE 集群支持）](#1-首选ephemeral-容器如果-gke-集群支持)
    - [2. **次选：利用 Pod B 作为调试代理**](#2-次选利用-pod-b-作为调试代理)
    - [3. **备选：Sidecar 模式**（如果需要长期调试）](#3-备选sidecar-模式如果需要长期调试)
  - [实际调试示例](#实际调试示例)
    - [场景 1：调试 Pod A 的健康检查端点](#场景-1调试-pod-a-的健康检查端点)
    - [场景 2：调试 Pod A 的 GCP 元数据服务访问](#场景-2调试-pod-a-的-gcp-元数据服务访问)
      - [方法 1: 使用 Ephemeral 容器（推荐）](#方法-1-使用-ephemeral-容器推荐)
      - [方法 2: 使用 Pod A 的原生工具](#方法-2-使用-pod-a-的原生工具)
      - [方法 3: 通过应用程序间接调试](#方法-3-通过应用程序间接调试)
    - [网络连通性测试](#网络连通性测试)
  - [端口冲突问题解答](#端口冲突问题解答)
    - [使用 kubectl debug 时的端口冲突](#使用-kubectl-debug-时的端口冲突)
      - [关键点：](#关键点)
      - [避免潜在问题的建议：](#避免潜在问题的建议)
  - [注意事项](#注意事项)
  - [总结](#总结)

# GKE Pod 跨 Pod 调试指南

如果 Pod A 中没有 curl 命令，而同一命名空间下的 Pod B 中有 curl 命令，我想利用 Pod B 中的 curl 来调试 Pod A 的问题。这种跨 Pod 调试的方式是可行的，主要依赖于 Kubernetes 的网络模型和 kubectl 工具提供的功能。

## 跨 Pod 调试方法

### 方法 1: 利用 Pod B 调试 Pod A

最直接的方法是使用 Pod B 中的 curl 来访问 Pod A 的服务：

```bash
# 获取 Pod A 的 IP 地址
POD_A_IP=$(kubectl get pod pod-a -n <namespace> -o jsonpath='{.status.podIP}')

# 使用 Pod B 的 curl 访问 Pod A
kubectl exec -it pod-b -n <namespace> -- curl http://${POD_A_IP}:8080

# 或者直接执行单次命令
kubectl exec pod-b -n <namespace> -- curl http://pod-a-service:8080
```

### 方法 2: 通过服务名访问

如果 Pod A 有对应的 Service，可以通过服务名访问：

```bash
kubectl exec -it pod-b -n <namespace> -- curl http://pod-a-service:8080
```

## 调试策略推荐

针对 GKE 环境中 Pod A 没有 `curl` 需要调试的场景，以下是推荐策略：

### 1. **首选：Ephemeral 容器**（如果 GKE 集群支持）

使用 `kubectl debug` 快速注入临时容器，直接在 Pod A 的网络环境中调试：

```bash
# 注入临时调试容器
kubectl debug pod-a -n <namespace> -it --image=busybox --target=main-container

# 在调试容器中测试 Pod A 的服务
wget http://localhost:8080
```

**优势**：
- 简单、无侵入、退出后自动销毁
- 共享 Pod A 的网络命名空间，可以直接访问 localhost

### 2. **次选：利用 Pod B 作为调试代理**

如果无法修改 Pod A 且集群不支持 ephemeral 容器：

```bash
# 获取 Pod A 的详细信息
kubectl describe pod pod-a -n <namespace>

# 使用 Pod B 的工具访问 Pod A
kubectl exec -it pod-b -n <namespace> -- curl http://pod-a-ip:8080

# 测试网络连通性
kubectl exec pod-b -n <namespace> -- ping pod-a-ip
```

**优势**：
- 快捷，无需修改任何配置
- 适合快速验证网络连通性和服务可用性

### 3. **备选：Sidecar 模式**（如果需要长期调试）

添加一个调试容器到 Pod A，共享网络：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-a-with-debug
  namespace: <namespace>
spec:
  containers:
  - name: main-container
    image: original-image
  - name: debug-sidecar
    image: curlimages/curl
    command: ["/bin/sh", "-c", "sleep 3600"]
```

**优势**：
- 适合需要多次调试的场景
- 调试容器与主容器共享网络和存储

## 实际调试示例

### 场景 1：调试 Pod A 的健康检查端点

```bash
# 方法1: 使用 Pod B
kubectl exec pod-b -n <namespace> -- curl -v http://pod-a-service:8080/health

# 方法2: 使用 ephemeral 容器
kubectl debug pod-a -n <namespace> -it --image=curlimages/curl
# 在调试容器中执行
curl -v http://localhost:8080/health

# 方法3: 检查 Pod A 的日志
kubectl logs pod-a -n <namespace> -f
```

### 场景 2：调试 Pod A 的 GCP 元数据服务访问

**重要**：Pod B 无法直接访问 Pod A 的元数据服务，因为元数据服务是 Pod 级别的。

#### 方法 1: 使用 Ephemeral 容器（推荐）

```bash
# 注入带有 curl 的临时容器到 Pod A
kubectl debug pod-a -n <namespace> -it --image=curlimages/curl --target=main-container

# 在临时容器中执行元数据查询
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token

# 获取服务账户信息
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email

# 获取项目信息
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/project/project-id
```

#### 方法 2: 使用 Pod A 的原生工具

```bash
# 检查 Pod A 中的可用工具
kubectl exec pod-a -n <namespace> -- which wget
kubectl exec pod-a -n <namespace> -- which nc

# 如果有 wget
kubectl exec pod-a -n <namespace> -- \
  wget --header="Metadata-Flavor: Google" \
  -O - \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token

# 如果有 nc (netcat)，手动构造 HTTP 请求
kubectl exec pod-a -n <namespace> -- /bin/sh -c '
echo -e "GET /computeMetadata/v1/instance/service-accounts/default/token HTTP/1.1\r\nHost: metadata.google.internal\r\nMetadata-Flavor: Google\r\n\r\n" | nc metadata.google.internal 80
'
```

#### 方法 3: 通过应用程序间接调试

```bash
# 检查环境变量
kubectl exec pod-a -n <namespace> -- env | grep -i google
kubectl exec pod-a -n <namespace> -- env | grep -i gcp

# 检查服务账户挂载
kubectl exec pod-a -n <namespace> -- ls -la /var/run/secrets/kubernetes.io/serviceaccount/

# 查看应用程序日志中的认证信息
kubectl logs pod-a -n <namespace> | grep -i "auth\|token\|credential"
```

### 网络连通性测试

```bash
# 测试 DNS 解析
kubectl exec pod-b -n <namespace> -- nslookup pod-a-service

# 测试端口连通性
kubectl exec pod-b -n <namespace> -- telnet pod-a-service 8080

# 检查网络策略
kubectl get networkpolicy -n <namespace>
```

## 端口冲突问题解答

### 使用 kubectl debug 时的端口冲突

当使用 `kubectl debug pod-a -n <namespace> -it --image=busybox --target=main-container` 时：

**结论**：在大多数情况下，ephemeral 容器与目标容器的端口冲突不会直接影响目标容器的服务。

#### 关键点：

1. **网络共享**：ephemeral 容器与目标容器共享相同的网络命名空间
2. **busybox 行为**：`busybox` 镜像默认不会启动任何监听端口的服务
3. **交互模式**：`-it` 参数会启动交互式 shell，而不是默认服务
4. **端口优先级**：目标容器已占用的端口，ephemeral 容器无法抢占

#### 避免潜在问题的建议：

```bash
# 1. 使用轻量级镜像
kubectl debug pod-a -n <namespace> -it --image=busybox

# 2. 强制启动 shell（避免默认服务）
kubectl debug pod-a -n <namespace> -it --image=nginx -- sh

# 3. 检查端口占用
# 在调试容器中执行
netstat -tuln

# 4. 直接访问目标容器服务
curl http://localhost:8080
```

## 注意事项

1. **权限要求**：确保有足够的 RBAC 权限执行 `kubectl exec` 和 `kubectl debug`
2. **网络策略**：检查是否有 NetworkPolicy 限制 Pod 间通信
3. **服务发现**：优先使用服务名而不是 Pod IP，因为 Pod IP 可能会变化
4. **资源限制**：注意调试容器的资源消耗，避免影响主容器性能

## 总结

这种跨 Pod 调试方式在 GKE 环境中非常实用，特别是在微服务架构中进行服务间通信的故障排查。通过合理选择调试方法，可以有效解决 Pod 缺少调试工具的问题，同时避免对生产服务造成影响。