# NetworkPolicy 跨 Namespace 通信 Debug 指南

## 1. 问题背景

NetworkPolicy 是"Kubernetes 网络安全的基石"，但它有一个天然的痛点：**没有内置日志**。当流量被 NetworkPolicy 拒绝时，你无法直接看到"因为哪条规则被拒绝"。

典型的困惑场景：
- Namespace A 的 Pod 要访问 Namespace B 的 Pod
- A 配置了 Egress，B 配置了 Ingress
- 但访问不通，不知道哪边出了问题

## 2. 核心原理：双向生效

NetworkPolicy 是**双向白名单机制**：

```
源 Pod (A) ──Egress──> 目标 Pod (B)
         需 A 有 Egress 规则
         需 B 有 Ingress 规则
         两个条件必须同时满足
```

| 方向 | 需要在哪边配置 | 说明 |
|------|----------------|------|
| A → B | A 有 Egress 到 B，**B 有 Ingress 从 A** | 需要双向确认 |
| B → A | B 有 Egress 到 A，**A 有 Ingress 从 B** | 需要双向确认 |

> **关键**：一旦任意一端声明了 `policyTypes`，该方向默认 deny all。

## 3. Debug 步骤

### 3.1 确认 NetworkPolicy 是否生效

```bash
# 检查 Namespace 是否启用了 NetworkPolicy（某些 CNI 需要显式开启）
kubectl get ns <namespace> -o jsonpath='{.metadata.labels}'

# 确认 NetworkPolicy 已创建
kubectl get networkpolicy -A

# 确认 Pod 被正确的 Policy 选中
kubectl describe pod <pod-name> -n <namespace> | grep -A10 "Annotations"
```

### 3.2 确认 Label Selector 匹配正确

```bash
# 源 namespace 的 label（用于 egress 的 namespaceSelector）
kubectl get ns ns-a --show-labels

# 目标 namespace 的 label（用于 ingress 的 namespaceSelector）
kubectl get ns ns-b --show-labels

# Pod 的 label（用于 podSelector）
kubectl get pods -n ns-a --show-labels
kubectl get pods -n ns-b --show-labels

# 验证 selector 能否匹配到期望的 Pod
kubectl get pods -n ns-a -l "app=your-app" --no-headers
```

### 3.3 最小化测试——临时放行验证

如果无法确认问题在哪，先放行所有流量验证是否是 NetworkPolicy 问题：

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: temp-allow-all
  namespace: <target-ns>
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
EOF
```

- **放行后通了** → 确认是 NetworkPolicy 问题，继续排查规则
- **放行后仍不通** → 可能是 CNI、VPC 防火墙、或应用本身问题

### 3.4 确认端口是否正确（最易忽略的坑）

```bash
# 确认目标 Pod 实际监听的端口（不是 Service port！）
kubectl get pod <target-pod> -n <target-ns> -o jsonpath='{.spec.containers[*].ports[*].containerPort}'

# 查看 Service 定义，确认 targetPort
kubectl get svc <service-name> -n <target-ns> -o yaml | grep -A5 "ports:"
```

**核心要点**：NetworkPolicy 中的 `port` 必须是 `targetPort`（Pod 实际监听端口），不是 Service 暴露的 `port`。

```
Service port: 8443   ← 客户端访问的端口
targetPort:   3000   ← Pod 实际监听（NetworkPolicy 管这里）
```

### 3.5 DNS 放行了么？

Egress 策略常忘加 DNS 规则，导致服务发现失败：

```bash
# 测试 DNS 解析是否正常
kubectl exec -n ns-a <pod> -- nslookup kubernetes.default
```

如果 DNS 不通，流量根本出不去。Egress 策略需要显式放行：

```yaml
egress:
  # 放行 DNS
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    podSelector:
      matchLabels:
        k8s-app: kube-dns
    ports:
      - protocol: UDP
        port: 53
      - protocol: TCP
        port: 53
```

### 3.6 网络层抓包验证

```bash
# 在源 Pod 抓包（确认流量是否发出）
kubectl exec -n ns-a <pod> -- tcpdump -i eth0 -n not port 53

# 在目标 Pod 抓包（确认流量是否到达）
kubectl exec -n ns-b <pod> -- tcpdump -i eth0 -n

# 判断逻辑：
# - 源端发出 + 目标端没收到 → 中间层（NetworkPolicy/CNI）拦截
# - 源端没发出 → 应用层问题或 DNS 解析失败
```

## 4. CNI 特定调试工具

### Calico（如果你用 Calico CNI）

```bash
# 查看特定 Pod 的 Policy 匹配情况
calicoctl policy check <pod-name>.<namespace>

# 查看 Node 上的 active policy
calicoctl policy show --nodename=<node>

# 在 Node 上查看 iptables 规则
iptables -L cali-fwd -n -v | grep <pod-ip>

# 查看 CalicoFelix 日志
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100
```

### Cilium（如果你用 Cilium CNI）

```bash
# 查看 Endpoint 策略
cilium endpoint list
cilium policy get

# 查看流量被拒绝的日志（Hubble）
cilium hubble ui

# 或命令行监控被 drop 的流量
cilium monitor --type drop
```

### GKE（使用 VPC-CNI 或 Dataplane V2）

```bash
# 查看 GKE 防火墙规则
gcloud compute firewall-rules list --filter="kubernetes.io/cluster-name=<cluster-name>"

# 确认 VPC 防火墙没有 block 容器网络
gcloud compute firewall-rules describe <rule-name> --region=<region>

# 查看 iptables 规则（在 Node 上）
gcloud compute ssh <node-name> --zone=<zone>
sudo iptables -L -n -v | grep <pod-ip>
```

## 5. 常见错误模式

### 5.1 只配置了一侧

```
A namespace: 配置了 Egress
B namespace: 没有配置 Ingress（默认 allow）
结果: 应该能通... 但如果 B 有默认 deny，就不通了
```

### 5.2 namespaceSelector label 写错

```yaml
# 常见错误：label key 不对
- namespaceSelector:
    matchLabels:
      name: special-ns    # 可能是 kubernetes.io/metadata.name

# 正确写法（新版 K8s）
- namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: special-ns
```

### 5.3 端口写错

```yaml
# 错误：写了 Service port
ports:
  - protocol: TCP
    port: 8443    # 错了，NetworkPolicy 看不到 Service

# 正确：写 targetPort
ports:
  - protocol: TCP
    port: 3000    # Pod 实际监听端口
```

### 5.4 忘放行 DNS

```yaml
# 错误：只允许访问目标 namespace，但没有 DNS
egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: target-ns

# 正确：同时放行 DNS
egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: target-ns
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    podSelector:
      matchLabels:
        k8s-app: kube-dns
    ports:
      - protocol: UDP
        port: 53
```

## 6. 快速诊断清单

| 检查项 | 命令 | 正常表现 |
|--------|------|----------|
| Namespace label | `kubectl get ns ns-a --show-labels` | 有 `kubernetes.io/metadata.name` |
| Pod label | `kubectl get pods -n ns-a --show-labels` | 有你 selector 用的 label |
| Egress 规则存在 | `kubectl get netpol -n ns-a` | 有针对目标 namespace 的规则 |
| Ingress 规则存在 | `kubectl get netpol -n ns-b` | 有针对源 namespace 的规则 |
| DNS 能解析 | `kubectl exec ns-a <pod> -- nslookup kubernetes.default` | 能解析 |
| 端口匹配 | 检查 NetworkPolicy port vs Pod containerPort | 一致 |
| PolicyManager 开启 | `kubectl describe ns <ns>` | 无限制注释 |

## 7. 推荐实践

### 7.1 平台级默认规则

每次新建 namespace 时，自动注入一个"保留基础访问"的 NetworkPolicy：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-and-metadata
  namespace: <user-namespace>
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
    # 放行 DNS
    - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # 放行 Kubernetes API（用于服务发现）
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            component: apiserver
            provider: kubernetes
      ports:
        - protocol: TCP
          port: 443
```

### 7.2 命名规范

```
NetworkPolicy 命名规范：
<方向>-<源/目标>-<服务名>
示例：
  ingress-allow-kong-to-app
  egress-allow-app-to-redis
  egress-allow-app-to-dns
```

### 7.3 Debug 时临时放行脚本

```bash
#!/bin/bash
# debug-allow-all.sh - 临时放行所有流量，Debug 完毕后删除

NAMESPACE=$1
if [ -z "$NAMESPACE" ]; then
  echo "Usage: $0 <namespace>"
  exit 1
fi

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: temp-allow-all-debug
  namespace: $NAMESPACE
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
EOF

echo "✅ 临时放行已启用"
echo "   Debug 完成后删除: kubectl delete netpol temp-allow-all-debug -n $NAMESPACE"
```

## 8. 总结

| 痛点 | 解决方案 |
|------|----------|
| 没有流量日志 | 逐条检查 label selector + 临时放行验证 |
| 双向规则易漏 | 始终双向确认：Egress + Ingress |
| 端口写错 | 确认 targetPort，不是 Service port |
| DNS 不通 | Egress 规则显式放行 kube-dns |
| 难排查 | 使用 CNI 自带工具（Calicoctl、Cilium CLI） |

**核心原则**：NetworkPolicy debug 靠的是"逐步隔离 + 最小化放行验证"。没有银弹，只有系统性的排除法。