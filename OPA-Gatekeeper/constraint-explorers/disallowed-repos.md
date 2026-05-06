# K8sDisallowedRepos 禁止特定镜像仓库

## 概述

`K8sDisallowedRepos` 是 `K8sAllowedRepos` 的**反向版本**——不允许从特定镜像仓库拉取镜像。

适用于：阻止已知的恶意镜像源、限制使用企业内部不安全的镜像仓库、或阻止来自特定云厂商的镜像。

> **与 K8sAllowedRepos 的关系**：Allowed 是白名单模式（只允许列表中的），Disallowed 是黑名单模式（只禁止列表中的）。生产环境推荐使用 `K8sAllowedRepos`（白名单），`K8sDisallowedRepos` 仅用于补充特定场景。

---

## 核心概念

### 这个 Constraint 做什么

```
检查每个容器镜像:
  └── 镜像前缀不能在 disallowedRepos 列表中

镜像: docker.io/malicious-app:latest
  ✗ 拒绝 if disallowedRepos 包含 "docker.io/"
  ✓ 通过 if disallowedRepos 不包含 "docker.io/"
```

### 模板信息

| 属性 | 值 |
|------|-----|
| **ConstraintTemplate Name** | `k8sdisallowedrepos` |
| **Kind** | `K8sDisallowedRepos` |
| **版本** | 1.0.0 |
| **来源** | [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general/disallowedrepos) |

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `repos` | array[string] | 禁止的镜像前缀列表 |

---

## Rego 逻辑解析

```rego
package k8sdisallowedrepos

violation[{"msg": msg}] {
  container := input.review.object.spec.containers[_]
  image := container.image
  startswith(image, input.parameters.repos[_])   # 检查是否以禁止前缀开头
  msg := sprintf("container <%v> has an invalid image repo <%v>, disallowed repos are %v",
    [container.name, image, input.parameters.repos])
}

violation[{"msg": msg}] {
  container := input.review.object.spec.initContainers[_]
  image := container.image
  startswith(image, input.parameters.repos[_])
  msg := sprintf("initContainer <%v> has an invalid image repo <%v>, disallowed repos are %v",
    [container.name, image, input.parameters.repos])
}

violation[{"msg": msg}] {
  container := input.review.object.spec.ephemeralContainers[_]
  image := container.image
  startswith(image, input.parameters.repos[_])
  msg := sprintf("ephemeralContainer <%v> has an invalid image repo <%v>, disallowed repos are %v",
    [container.name, image, input.parameters.repos])
}
```

**注意**：这里使用的是 `startswith(image, prefix)` 而不是正则匹配或 `strings.any_prefix_match`。前缀匹配是字面量的字符串开头匹配。

---

## 完整 Constraint YAML

### 禁止 DockerHub 公共镜像

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowedRepos
metadata:
  name: block-dockerhub
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
    - "docker.io/"           # 禁止 DockerHub
    - "gcr.io/google_containers/"   # 禁止旧版 K8s GCR（使用新的 registry.k8s.io）
```

### 禁止所有公共镜像仓库（仅允许私有仓库）

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowedRepos
metadata:
  name: block-all-public-repos
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
    - "docker.io/"            # DockerHub
    - "gcr.io/google_containers/"   # 旧 GCR
    - "k8s.gcr.io/"           # 旧 K8s GCR
    - "quay.io/"              # Quay
    - "ghcr.io/"              # GitHub Container Registry
    - "ecr."                  # AWS ECR（任何区域）
```

### 禁止特定组织/路径

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowedRepos
metadata:
  name: block-untrusted-orgs
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    repos:
    - "gcr.io/untrusted-project/"    # 禁止某个不安全的项目
    - "harbor.company.com/malware/"  # 禁止某个已知的恶意仓库路径
```

### 禁止任何无 tag/digest 的镜像

这实际上不直接是 DisallowedRepos 的职责（那是 `K8sImageSubsequentTag`），但可以通过禁止 `:latest` 来间接实现：

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowedRepos
metadata:
  name: block-untagged-images
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    repos:
    - "myregistry.com/app:"         # 禁止任何以 "name:" 结尾的镜像（latest）
```

> ⚠️ 这种方式不够精确，推荐使用专门的 `K8sImageSubsequentTag` 模板（见下文 FAQ）。

---

## 应用命令

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowedRepos
metadata:
  name: block-dockerhub
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    repos:
    - "docker.io/"
EOF

# 查看
kubectl get k8sdisallowedrepos

# 查看 violations
kubectl get k8sdisallowedrepos block-dockerhub \
  -o jsonpath='{.status.violations}' | jq '.'
```

---

## 测试：触发违规

### 测试 1：使用 DockerHub 镜像

```bash
# 尝试使用 DockerHub 镜像
kubectl run nginx --image=nginx:latest --port=80

# 预期拒绝:
# container <nginx> has an invalid image repo <nginx:latest>, disallowed repos are ["docker.io/"]
```

### 测试 2：使用内部镜像（应该通过）

```bash
# 内部镜像不在禁止列表 → 通过
kubectl run myapp --image=gcr.io/my-project/myapp:v1

# 但如果镜像在 gcr.io/google_containers/ 路径下 → 被拒绝
kubectl run old-app --image=gcr.io/google_containers/pause:3.0
```

---

## 实际应用场景

### 场景 1：迁移到新镜像仓库

企业从旧镜像仓库迁移到新仓库时，可以先用 `DisallowedRepos` 禁止旧仓库，强制开发者迁移：

```yaml
# 第一步：dryrun 审计
spec:
  enforcementAction: dryrun   # 只记录，不阻止

# 第二步：确认无影响后，切换为 deny
spec:
  enforcementAction: deny
```

### 场景 2：禁止有安全漏洞的镜像源

如果某个公共镜像源被发现有供应链攻击：

```yaml
parameters:
  repos:
  - "untrusted-registry.io/"    # 立即禁止该镜像源
```

### 场景 3：Allowed + Disallowed 组合

白名单优先，黑名单补充：

```
K8sAllowedRepos:
  repos: ["gcr.io/my-project/"]
  → 只允许我的项目镜像

K8sDisallowedRepos:
  repos: ["gcr.io/other-compromised-project/"]
  → 额外禁止特定的不安全项目（即使前缀匹配）
```

---

## 常见问题

### Q1: 为什么推荐用 Allowed 而非 Disallowed？

| 模式 | 优点 | 缺点 |
|------|------|------|
| **AllowedRepos**（白名单） | 默认拒绝，安全边界清晰 | 需要维护完整的允许列表 |
| **DisallowedRepos**（黑名单） | 增量配置方便 | 安全边界模糊，可能遗漏 |

**生产环境推荐**：AllowedRepos（白名单），安全边界清晰。

### Q2: 如何禁止 `:latest` 标签的镜像？

使用 `K8sImageSubsequentTag`（如 gatekeeper-library 中存在）或自定义 Rego。标准库中的 `imagesubsequenttag` 模板：

```yaml
# 注意：模板名称可能因版本而异，请确认 gatekeeper-library 版本
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sImageSubsequentTag
metadata:
  name: deny-latest-tag
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    # 不允许 :latest
```

### Q3: `docker.io/` 和 `docker.io/library/` 有什么区别？

- `docker.io/` → 匹配所有 docker.io 下的镜像
- `docker.io/library/` → 只匹配 DockerHub 官方镜像

DockerHub 的非官方镜像实际路径是 `docker.io/<username>/<image>`，所以：
- 禁止 `docker.io/` 会阻止所有 DockerHub 镜像
- 禁止 `docker.io/library/` 只阻止官方镜像

### Q4: DisallowedRepos 和 AllowedRepos 能同时使用吗？

能。但执行逻辑是**各自独立检查**——都通过才允许创建。如果同时启用，确保两者不会冲突：

```
K8sAllowedRepos (repos: ["gcr.io/my-project/"])
  → 只允许 gcr.io/my-project/

K8sDisallowedRepos (repos: ["gcr.io/google_containers/"])
  → 禁止 gcr.io/google_containers/

结果: 只有 gcr.io/my-project/ 可以使用（符合预期）
```

---

## 快速命令参考

```bash
# 应用
kubectl apply -f k8sdisallowedrepos.yaml

# 查看
kubectl get k8sdisallowedrepos

# 查看 violations
kubectl get k8sdisallowedrepos <name> \
  -o jsonpath='{.status.violations}' | jq

# 更新禁止列表
kubectl patch k8sdisallowedrepos block-dockerhub \
  --type=merge \
  -p '{"spec":{"parameters":{"repos":["docker.io/","quay.io/"]}}}'

# 删除
kubectl delete k8sdisallowedrepos <name>
```

---

## 源文件路径

- ConstraintTemplate: `library/general/disallowedrepos/template.yaml`
- Samples: `library/general/disallowedrepos/samples/`
