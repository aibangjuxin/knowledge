# Namespace & Ingress 标准化策略

为了保证多用户环境的隔离性与稳定性，所有接入 CD Pipeline 的应用必须遵循以下策略。

## 1. Namespace 策略

### 命名规则
- Namespace 名称严格对应 **用户名 (User ID)**。
- 格式: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` (DNS-1123 label 规范)

### 自动创建与管理
- CD Pipeline 会在部署前检查 Namespace 是否存在。
- 如果不存在，Pipeline 会自动创建 Namespace。
- **禁止** 用户手动删除或修改 Namespace 的元数据。

### 资源隔离
- 每个 Namespace 将默认绑定 `ResourceQuota` 和 `LimitRange` (未来规划)，防止资源滥用。

## 2. Ingress 策略

### 域名规范
- 所有 API 统一使用平台子域名。
- 格式: `<user>.<platform-domain>` 或 `<api>.<user>.<platform-domain>`
- 示例: `userA.platform.example.com`

### Annotation 强制
Ingress 必须包含以下 Annotation 以确保使用正确的 Ingress Controller：
```yaml
annotations:
  kubernetes.io/ingress.class: "gce"
```

### 路径规范
- 推荐使用 Prefix 匹配模式。
- 避免使用根路径 `/` 除非是该域名下的唯一应用。

## 3. 镜像管理策略

### 镜像流转
1. **Build**: 用户在 CI 阶段构建镜像并推送到 Nexus。
2. **Sync**: CD Pipeline 触发 `sync-image.sh` 将镜像从 Nexus 拉取并推送到 Google Artifact Registry (GAR)。
3. **Deploy**: GKE Deployment **必须** 引用 GAR 中的镜像地址。

### 权限控制
- GKE 节点通过 Workload Identity 获得拉取 GAR 镜像的权限。
- 禁止 GKE 直接配置 Nexus 的 ImagePullSecrets (安全性考量)。
