# K8sAllowedRepos 限制容器镜像仓库

## 概述

`K8sAllowedRepos` 强制所有容器镜像必须来自**指定的仓库前缀列表**，从源头控制镜像供应链安全。

这是零信任安全的关键一环——只允许从受信任的镜像仓库拉取镜像，阻止从公网未知仓库（如 DockerHub 私人镜像）或恶意仓库引入镜像。

---

## 核心概念

### 这个 Constraint 做什么

```
检查每个容器 (containers, initContainers, ephemeralContainers):
  └── 镜像前缀必须在 allowedRepos 列表中

镜像: gcr.io/my-project/nginx:1.21
  ✓ 通过 if allowedRepos 包含 "gcr.io/my-project/"
  ✗ 拒绝 if 只允许 "gcr.io/my-project/" 但镜像是 "docker.io/nginx"
```

### 模板信息

| 属性 | 值 |
|------|-----|
| **ConstraintTemplate Name** | `k8sallowedrepos` |
| **Kind** | `K8sAllowedRepos` |
| **版本** | 1.0.2 |
| **来源** | [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general/allowedrepos) |

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `repos` | array[string] | 允许的镜像前缀列表（支持字符串前缀匹配） |

---

## Rego 核心逻辑

```rego
package k8sallowedrepos

violation[{"msg": msg}] {
  container := input.review.object.spec.containers[_]
  not strings.any_prefix_match(container.image, input.parameters.repos)
  msg := sprintf("container <%v> has an invalid image repo <%v>, allowed repos are %v",
    [container.name, container.image, input.parameters.repos])
}

violation[{"msg": msg}] {
  container := input.review.object.spec.initContainers[_]
  not strings.any_prefix_match(container.image, input.parameters.repos)
  msg := sprintf("initContainer <%v> has an invalid image repo <%v>, allowed repos are %v",
    [container.name, container.image, input.parameters.repos])
}

violation[{"msg": msg}] {
  container := input.review.object.spec.ephemeralContainers[_]
  not strings.any_prefix_match(container.image, input.parameters.repos)
  msg := sprintf("ephemeralContainer <%v> has an invalid image repo <%v>, allowed repos are %v",
    [container.name, container.image, input.parameters.repos])
}
```

关键函数：`strings.any_prefix_match(image, allowed_prefixes)` — 检查镜像是否以列表中任意一个前缀开头。

---

## 完整 Constraint YAML

### 仅允许私有 GCR 仓库

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: allow-only-gcr
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
  parameters:
    repos:
    - "gcr.io/my-project/"         # 项目 GCR
    - "gcr.io/my-project-subteam/"  # 子团队 GCR
```

### 允许多个云厂商 + 内部仓库

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: allow-multi-registry
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
  parameters:
    repos:
    - "gcr.io/"                     # GCP GCR（所有项目）
    - "us.gcr.io/"                  # GCP US 区域
    - "eu.gcr.io/"                  # GCP EU 区域
    - "asia.gcr.io/"               # GCP Asia 区域
    - "k8s.gcr.io/"               # Kubernetes 官方 GCR
    - "registry.k8s.io/"           # 新的 K8s 镜像仓库
    - "docker.io/library/"         # 官方 DockerHub 基础镜像（需要 /library/）
```

### 生产环境：严格限制

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: prod-allow-only-internal
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    - istio-system
    - cert-manager
  parameters:
    repos:
    - "gcr.io/prod-images/"         # 生产镜像
    - "gcr.io/prod-shared/"         # 共享基础镜像
    - "registry.k8s.io/"           # K8s 系统组件必须用这个
```

---

## 应用命令

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: allow-only-gcr
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    repos:
    - "gcr.io/my-project/"
EOF

# 查看
kubectl get k8sallowedrepos

# 查看 violations
kubectl get k8sallowedrepos allow-only-gcr \
  -o jsonpath='{.status.violations}' | jq '.'
```

---

## 测试：触发违规

### 测试 1：使用 DockerHub 镜像

```bash
# 尝试使用 DockerHub 公共镜像
kubectl run nginx --image=nginx:latest --port=80

# 预期拒绝:
# container <nginx> has an invalid image repo <nginx:latest>, allowed repos are ["gcr.io/my-project/"]
```

### 测试 2：使用允许的仓库

```bash
# 推送镜像到允许的仓库
docker tag nginx:latest gcr.io/my-project/nginx:v1
docker push gcr.io/my-project/nginx:v1

# 现在可以运行
kubectl run nginx --image=gcr.io/my-project/nginx:v1 --port=80
```

### 测试 3：镜像带 tag 和 digest

```bash
# 带 tag 的镜像
kubectl run app --image=gcr.io/my-project/app:v1.2.3
# ✓ 通过

# 带 SHA digest 的镜像
kubectl run app --image=gcr.io/my-project/app@sha256:abc123...
# ✓ 通过（前缀匹配 gcr.io/my-project/）
```

---

## 实际应用场景

### 场景 1：防止供应链攻击

攻击者可能通过以下方式引入恶意镜像：
- 开发者不小心拉取了带有恶意软件的公共镜像
- CI/CD 流水线被攻击，推送了恶意镜像

```
AllowedRepos 策略:
  repos: ["gcr.io/my-project/"]
  
→ 即使 CI/CD 被攻破，恶意镜像也无法部署
   因为恶意镜像不在允许列表中
```

### 场景 2：强制使用 VPC 网络镜像

在 GKE 中，通过 VPC-native 集群和私有 GCR，可以确保镜像只能通过 VPC 网络拉取：

```yaml
parameters:
  repos:
  - "gcr.io/my-project/"           # 私有 GCR
  - "pkg.dev/"                     # Artifact Registry（支持 VPC-SC）
```

### 场景 3：多环境差异化

```
dev:  AllowedRepos (repos: ["gcr.io/dev/", "docker.io/library/"])
      → 允许 DockerHub 基础镜像快速开发

prod: AllowedRepos (repos: ["gcr.io/prod/", "gcr.io/shared/"])
      → 只允许生产认证镜像
```

---

## 常见问题

### Q1: 如何允许 `nginx` 官方镜像（DockerHub）？

DockerHub 的官方镜像路径是 `docker.io/library/nginx`，因此需要在 `repos` 中添加 `docker.io/library/`：

```yaml
parameters:
  repos:
  - "docker.io/library/"    # DockerHub 官方镜像
  - "gcr.io/my-project/"    # 私有仓库
```

### Q2: `gcr.io/my-project` 和 `gcr.io/my-project/` 有什么区别？

- `gcr.io/my-project` → 匹配 `gcr.io/my-project` 开头的镜像（包括子路径）
- `gcr.io/my-project/` → 更精确，只匹配 `gcr.io/my-project/` 开头的镜像

**建议加 `/`**：否则 `gcr.io/my-project-attacker` 也会匹配。

### Q3: K8s 基础组件（pause 容器）会被阻止吗？

是的。Gatekeeper 检查所有 containers，包括 `gcr.io/google_containers/pause` 等系统容器。

**解决方案**：在 `excludedNamespaces` 中排除 `kube-system`：

```yaml
match:
  excludedNamespaces:
  - kube-system
  - gatekeeper-system
```

### Q4: CI/CD 流水线镜像构建受影响吗？

不受影响。Gatekeeper 只在 **Pod 创建时** 检查镜像仓库。CI/CD 构建镜像时不会触发 Gatekeeper 校验（没有 Pod 创建）。

---

## 与其他 Constraint 的配合

| 配合使用 | 效果 |
|---------|------|
| `K8sAllowedRepos` + `K8sContainerLimits` | 镜像来源安全 + 资源限制 |
| `K8sAllowedRepos` + `K8sRequiredLabels` | 镜像来源安全 + 标签管理 |
| `K8sAllowedRepos` + 镜像扫描 (Container Analysis) | 镜像来源安全 + 漏洞扫描 |

---

## 快速命令参考

```bash
# 应用
kubectl apply -f k8sallowedrepos.yaml

# 查看
kubectl get k8sallowedrepos

# 查看 violations
kubectl get k8sallowedrepos <name> \
  -o jsonpath='{.status.violations}' | jq

# 更新允许的仓库
kubectl patch k8sallowedrepos allow-only-gcr \
  --type=merge \
  -p '{"spec":{"parameters":{"repos":["gcr.io/my-project/","gcr.io/new-project/"]}}}'

# 删除
kubectl delete k8sallowedrepos <name>
```

---

## 源文件路径

- ConstraintTemplate: `library/general/allowedrepos/template.yaml`
- Samples: `library/general/allowedrepos/samples/`
