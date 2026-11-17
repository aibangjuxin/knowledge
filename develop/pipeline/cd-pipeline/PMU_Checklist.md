# PMU (Platform Management Unit) 校验 Checklist

此文档供平台管理员 (PMU) 在审核用户 API 上线时使用。

## 1. 自动化校验 (Pipeline)
Pipeline 中已集成 `kubeconform`，会自动检查以下内容：
- [ ] YAML 语法是否正确
- [ ] Kubernetes API Version 是否匹配当前集群版本
- [ ] 必须字段是否缺失

## 2. 人工/策略校验 (Policy)
除了自动化检查，PMU 应关注以下策略合规性：

### 命名规范
- [ ] **Namespace**: 必须与用户名一致 (e.g., `userA`)
- [ ] **Service/Deployment**: 必须与 API 名称一致 (e.g., `api1`)
- [ ] **Labels**: 必须包含 `app: <api-name>`

### 资源配额 (Resource Quota)
- [ ] **Requests/Limits**: 必须设置 CPU 和 Memory 的 requests 和 limits。
- [ ] **合理性**: 
    - Dev 环境建议: CPU < 200m, Memory < 256Mi
    - Prod 环境建议: 根据压测结果设定，避免过度申请。

### Ingress & 网络
- [ ] **Domain**: 必须使用平台统一域名 `*.platform.xxx.com`。
- [ ] **Path**: 路径必须唯一，避免冲突。
- [ ] **TLS**: 生产环境必须开启 TLS。

### 镜像安全
- [ ] **Source**: 镜像必须来自受信任的 Nexus 仓库。
- [ ] **Target**: 部署时必须使用同步到 GAR 的镜像，禁止直接使用外部镜像。

## 3. 常见错误处理
- **Pipeline Failed at Render**: 检查 `templates/` 目录下的 YAML 文件变量 `${VAR}` 是否拼写正确。
- **Pipeline Failed at Validate**: 检查 YAML 缩进或字段拼写。
- **Image Pull Error**: 检查 `sync-image.sh` 是否成功推送镜像到 GAR，或 IAM 权限是否配置正确。
