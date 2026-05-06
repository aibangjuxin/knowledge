# K8sHttpsOnly 强制 Ingress 仅允许 HTTPS

## 概述

`K8sHttpsOnly` 强制所有 Kubernetes Ingress 资源必须只允许 HTTPS 流量，拒绝任何明文 HTTP 访问。

这是保护 Web 应用安全的基础策略——即使是内部服务，明文 HTTP 也容易被网络窃听。配合自动化证书（如 cert-manager），可以确保所有流量都加密。

---

## 核心概念

### 这个 Constraint 做什么

```
检查每个 Ingress:
  ├── 必须有 spec.tls 配置
  └── 必须有注解 kubernetes.io/ingress.allow-http: "false"

不满足 → violation
```

### 模板信息

| 属性 | 值 |
|------|-----|
| **ConstraintTemplate Name** | `k8shttpsonly` |
| **Kind** | `K8sHttpsOnly` |
| **版本** | 1.0.2 |
| **来源** | [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general/httpsonly) |

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `tlsOptional` | boolean | 设为 `true` 时，允许没有 TLS 配置的 Ingress（仅要求注解），默认 `false` |

---

## Rego 逻辑解析

```rego
# 主规则: 要求完整的 HTTPS 配置
violation[{"msg": msg}] {
  input.review.object.kind == "Ingress"
  regex.match("^(extensions|networking.k8s.io)/", input.review.object.apiVersion)
  ingress := input.review.object
  not https_complete(ingress)           # 检查 TLS + 注解
  not tls_is_optional                  # 不是可选模式
  msg := sprintf("Ingress should be https. tls configuration and allow-http=false annotation are required for %v", [ingress.metadata.name])
}

# 可选 TLS 模式: 只要求注解
violation[{"msg": msg}] {
  input.review.object.kind == "Ingress"
  ingress := input.review.object
  not annotation_complete(ingress)     # 只检查注解
  tls_is_optional                      # 必须是可选模式
  msg := sprintf("Ingress should be https. The allow-http=false annotation is required for %v", [ingress.metadata.name])
}

# 完整的 HTTPS 配置
https_complete(ingress) = true {
  ingress.spec["tls"]
  count(ingress.spec.tls) > 0
  ingress.metadata.annotations["kubernetes.io/ingress.allow-http"] == "false"
}

# 注解完整性
annotation_complete(ingress) = true {
  ingress.metadata.annotations["kubernetes.io/ingress.allow-http"] == "false"
}
```

---

## 完整 Constraint YAML

### 标准模式（必须 TLS + 注解）

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sHttpsOnly
metadata:
  name: require-https-ingress
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["extensions", "networking.k8s.io"]
      kinds: ["Ingress"]
    excludedNamespaces:
    - ingress-nginx          # ingress controller 自身
    - kube-system
```

### TLS 可选模式（仅要求注解，不强制 TLS）

适用于某些场景下使用外部证书管理，不想让 Gatekeeper 强制 TLS：

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sHttpsOnly
metadata:
  name: require-https-annotation-only
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["networking.k8s.io"]
      kinds: ["Ingress"]
  parameters:
    tlsOptional: true    # TLS 配置可选，但注解必须
```

---

## 应用命令

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sHttpsOnly
metadata:
  name: require-https-ingress
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["networking.k8s.io"]
      kinds: ["Ingress"]
EOF

# 查看
kubectl get k8shttpsonly

# 查看 violations
kubectl get k8shttpsonly require-https-ingress \
  -o jsonpath='{.status.violations}' | jq '.'

# 描述
kubectl describe k8shttpsonly require-https-ingress
```

---

## 测试：触发违规

### 测试 1：完全没有 TLS 配置

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: http-only-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80

# 预期拒绝:
# Ingress should be https. tls configuration and allow-http=false annotation are required for http-only-ingress
```

### 测试 2：有 TLS 但没有注解

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-without-annotation
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  tls:                          # ← 有 TLS
  - hosts:
    - myapp.example.com
    secretName: myapp-tls
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
# 缺少注解 kubernetes.io/ingress.allow-http: "false"
# 触发 violation
```

### 测试 3：完全合规的 Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: compliant-https-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx"
    kubernetes.io/ingress.allow-http: "false"   # ← 必须有这个注解
spec:
  tls:                                             # ← 必须有 TLS
  - hosts:
    - myapp.example.com
    secretName: myapp-tls
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
# ✓ 通过
```

---

## 配合 cert-manager 自动 TLS

`K8sHttpsOnly` 通常与 cert-manager 配合使用，实现自动化 HTTPS：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: "nginx"
    kubernetes.io/ingress.allow-http: "false"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    # cert-manager 自动申请并续期 TLS 证书
spec:
  tls:
  - hosts:
    - myapp.example.com
    secretName: myapp-tls
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

---

## 实际应用场景

### 场景 1：GKE + Google Cloud Load Balancer + HTTPS Policy

在 GKE 上使用 Google Cloud 的 HTTPS LB，可以直接配置 HTTPS Policy（LB 层面强制 HTTPS），但 `K8sHttpsOnly` 提供了应用层保障：

```
两层防护:
1. Google Cloud LB HTTPS Policy → LB 层面拒绝 HTTP
2. K8sHttpsOnly Gatekeeper     → K8s 层强制 TLS + 注解
```

### 场景 2：内部服务也需要 HTTPS

即使在内网，也要强制 HTTPS 防止内部网络窃听：

```yaml
# 内网 ingress.example.internal
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: internal-api
  annotations:
    kubernetes.io/ingress.class: "internal"
    kubernetes.io/ingress.allow-http: "false"
spec:
  tls:
  - hosts:
    - api.internal
    secretName: internal-api-tls
  rules:
  - host: api.internal
    http:
      paths:
      - backend:
          service:
            name: api-svc
            port:
              number: 8080
```

### 场景 3：迁移已有的 HTTP Ingress

对于已有的 HTTP-only Ingress，可以用 dryrun 模式审计：

```yaml
spec:
  enforcementAction: dryrun   # 先不阻止，只记录
```

---

## 常见问题

### Q1: 是否同时支持 `extensions/v1beta1` 和 `networking.k8s.io/v1`？

是的。Rego 中的正则匹配：
```rego
regex.match("^(extensions|networking.k8s.io)/", input.review.object.apiVersion)
```

### Q2: TLS Secret 名称可以不同吗？

可以。Gatekeeper 只检查 `spec.tls` 数组**存在且非空**，不检查具体的 secretName。只要有 TLS 配置即可：

```yaml
spec:
  tls:
  - hosts:
    - a.com
    secretName: secret-a
  - hosts:
    - b.com
    secretName: secret-b    # 多 host 分别配置 → ✓
```

### Q3: 如何只阻止特定 namespace 的 HTTP Ingress？

```yaml
spec:
  match:
    namespaces:
    - production
    - staging
```

---

## 快速命令参考

```bash
# 应用
kubectl apply -f k8shttpsonly.yaml

# 查看
kubectl get k8shttpsonly

# 查看 violations
kubectl get k8shttpsonly <name> \
  -o jsonpath='{.status.violations}' | jq

# 查看某个 namespace 的违规 Ingress
kubectl get k8shttpsonly require-https \
  -o jsonpath='{.status.violations}' \
  | jq '.[] | select(.namespace == "production")'

# 删除
kubectl delete k8shttpsonly <name>
```

---

## 源文件路径

- ConstraintTemplate: `library/general/httpsonly/template.yaml`
- Samples: `library/general/httpsonly/samples/`
