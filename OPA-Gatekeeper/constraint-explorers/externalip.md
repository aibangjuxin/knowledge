# K8sExternalIPs 限制 Service 外部 IP

## 概述

`K8sExternalIPs` 用于**限制 Service 的 `externalIPs` 字段**，只允许特定的 IP 地址列表。

`externalIPs` 是 Kubernetes Service 的一个字段，允许将任意 IP 绑定到 Service（通常用于让集群外的 IP 通过节点端口访问服务）。这个字段如果被滥用，会造成安全风险——任何人只要能创建 Service，就能把任意 IP"绑定"到集群。

---

## 核心概念

### 这个 Constraint 做什么

```
用户尝试创建 Service:
apiVersion: v1
kind: Service
spec:
  type: ClusterIP
  externalIPs:
  - 1.2.3.4     ← 检查这个 IP 是否在 allowedIPs 列表中
  - 5.6.7.8

如果 1.2.3.4 或 5.6.7.8 不在允许列表 → violation
```

### 模板信息

| 属性 | 值 |
|------|-----|
| **ConstraintTemplate Name** | `k8sexternalips` |
| **Kind** | `K8sExternalIPs` |
| **版本** | 1.0.0 |
| **来源** | [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general/externalip) |

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `allowedIPs` | array[string] | 允许的外部 IP 列表（CIDR 格式或精确 IP） |

---

## Rego 逻辑解析

```rego
package k8sexternalips

violation[{"msg": msg}] {
  input.review.kind.kind == "Service"
  input.review.kind.group == ""
  allowedIPs := {ip | ip := input.parameters.allowedIPs[_]}
  externalIPs := {ip | ip := input.review.object.spec.externalIPs[_]}
  forbiddenIPs := externalIPs - allowedIPs
  count(forbiddenIPs) > 0
  msg := sprintf("service has forbidden external IPs: %v", [forbiddenIPs])
}
```

解读：
1. 从 `input.parameters.allowedIPs` 构建允许 IP 集合
2. 从 `input.review.object.spec.externalIPs` 构建当前 Service 的 externalIPs 集合
3. `forbiddenIPs := externalIPs - allowedIPs` 差集运算，找出不在允许列表中的 IP
4. 如果差集不为空 → violation

**注意**：`allowedIPs[_]` 中的 `_` 是 Rego 的内置变量，表示"任意索引"，用于遍历数组。

---

## 完整 Constraint YAML

### 允许特定 IP 列表

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sExternalIPs
metadata:
  name: restrict-external-ips
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
    excludedNamespaces:
    - kube-system
    - ingress-nginx
  parameters:
    allowedIPs:
    - "10.0.0.0/8"           # 内网 IP 段
    - "192.168.0.0/16"       # VPC IP 段
    - "8.8.8.8"              # 特定白名单 IP
```

### 完全禁止所有 externalIPs

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sExternalIPs
metadata:
  name: deny-all-external-ips
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
  parameters:
    allowedIPs: []           # 空列表 = 完全禁止
```

### 允许特定云厂商 IP 段

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sExternalIPs
metadata:
  name: allow-gcp-ip-ranges
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
  parameters:
    allowedIPs:
    - "10.128.0.0/9"         # GKE 节点 IP 范围
    - "35.191.0.0/16"        # GCP 负载均衡 IP
    - "130.211.0.0/22"       # GCP 负载均衡 IP
```

---

## 应用命令

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sExternalIPs
metadata:
  name: restrict-external-ips
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
  parameters:
    allowedIPs:
    - "10.0.0.0/8"
    - "192.168.0.0/16"
EOF

# 查看
kubectl get k8sexternalips

# 查看 violations
kubectl get k8sexternalips restrict-external-ips \
  -o jsonpath='{.status.violations}' | jq '.'
```

---

## 测试：触发违规

### 测试 1：使用不在允许列表的 IP

```bash
kubectl create ns externalip-test

# 创建 Service，使用未授权的 externalIP
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: bad-external-ip-svc
  namespace: externalip-test
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
  externalIPs:
  - 1.2.3.4    # 不在 allowedIPs 列表中 → 触发 violation
EOF

# 预期拒绝:
# service has forbidden external IPs: {"1.2.3.4"}
```

### 测试 2：使用允许的 IP（应该通过）

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: good-external-ip-svc
  namespace: externalip-test
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
  externalIPs:
  - 10.0.50.100   # 在允许的 10.0.0.0/8 范围内 → 通过
EOF
```

---

## 实际应用场景

### 场景 1：防止 DNS 欺骗

攻击者可以创建一个 Service 并设置 `externalIPs` 指向一个可信 IP（如内网 DNS 服务器 10.0.0.53），然后通过 DNS 欺骗将流量劫持到恶意服务器。

```
攻击流程:
1. 攻击者创建 Service，设置 externalIPs: ["10.0.0.53"]
2. 集群内应用认为 10.0.0.53 是可信 DNS
3. 攻击者在自己的 Pod 中监听 10.0.0.53，回复恶意 DNS 响应
4. 用户流量被劫持

K8sExternalIPs 阻止: 只允许授信的 IP 出现在 externalIPs 中
```

### 场景 2：网络分区管理

在多租户环境中，不同 namespace 的 Service 只能绑定特定网段的 externalIPs：

```yaml
# namespace: prod 只能使用内网 IP
namespace: prod
  allowedIPs: ["10.0.0.0/8"]

# namespace: dmz 可以使用 DMZ 网段
namespace: dmz
  allowedIPs: ["10.1.0.0/16"]
```

### 场景 3：配合 Ingress 的限制

某些遗留系统可能需要通过 externalIPs 直接访问，可以通过白名单控制：

```yaml
parameters:
  allowedIPs:
  - "10.0.0.0/8"           # 内网访问
  - "35.191.0.0/16"        # GCP LB
  - "130.211.0.0/22"       # GCP LB
  # 完全禁止公网 IP
```

---

## 局限性

### 不支持 CIDR 范围匹配

当前模板的 Rego 使用**精确匹配**：

```rego
allowedIPs := {ip | ip := input.parameters.allowedIPs[_]}
```

这意味着：
- `allowedIPs: ["10.0.0.0/8"]` → **只匹配字面量** `"10.0.0.0/8"`，而不是 10.0.0.0/8 段内的所有 IP

如果需要真正的 CIDR 范围检查，需要修改 Rego：

```rego
# 自定义: 支持 CIDR 范围检查
import future.keywords.contains
import future.keywords.if

violation contains msg {
  some i
  ip := input.review.object.spec.externalIPs[i]
  not is_ip_in_allowed_ranges(ip, input.parameters.allowedIPs)
  msg := sprintf("external IP %v not in allowed ranges", [ip])
}

is_ip_in_allowed_ranges(ip, allowedIPs) if {
  # 检查 IP 是否在 allowedIPs 的某个 CIDR 内
  # 需要额外库支持
}
```

### 不支持按 namespace 差异化配置

同一个 Constraint 无法对不同 namespace 设置不同的 `allowedIPs`。需要通过多个 Constraint 或自定义 Rego 实现。

---

## 快速命令参考

```bash
# 应用
kubectl apply -f k8sexternalips.yaml

# 查看
kubectl get k8sexternalips

# 查看 violations
kubectl get k8sexternalips <name> \
  -o jsonpath='{.status.violations}' | jq

# 更新允许的 IP 列表
kubectl patch k8sexternalips restrict-external-ips \
  --type=merge \
  -p '{"spec":{"parameters":{"allowedIPs":["10.0.0.0/8","172.16.0.0/12"]}}}'

# 删除
kubectl delete k8sexternalips <name>
```

---

## 与其他 Constraint 的配合

| 配合使用 | 效果 |
|---------|------|
| `K8sBlockLoadBalancer` + `K8sBlockNodePort` + `K8sExternalIPs` | 三层防护：阻止 LoadBalancer、NodePort 和非法 externalIPs |
| `K8sRequiredLabels` | 要求所有 Service 必须有标签（owner、team 等），便于追踪谁创建了有 externalIPs 的 Service |

---

## 源文件路径

- ConstraintTemplate: `library/general/externalip/template.yaml`
- Samples: `library/general/externalip/samples/`
