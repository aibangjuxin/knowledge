# OPA Gatekeeper 策略分层评估报告

> **文档版本**: 1.0.0
> **更新日期**: 2026-05-07
> **数据来源**: GKE Policy Controller Gallery（55条策略截图）
> **分层模型**: 3层架构（Layer 1 平台全局 / Layer 2 租户级 / Layer 3 命名空间级）

---

## 1. 分层原则

| 层级 | 名称 | 执行方式 | 说明 |
|------|------|----------|------|
| **L1** | 平台全局 | 强制 `deny`，无法被 Namespace 覆盖 | 适用于跨 Namespace 冲突防护、系统资源保护、安全基线 |
| **L2** | 租户可调 | `deny`，团队可在平台边界内调整参数 | 适用于团队差异化需求，参数可定制但不能超越平台上限 |
| **L3** | 命名空间特供 | `dryrun` 或临时 Exemption | 适用于一次性特殊需求，通过 Exception 机制处理，不单独建模板 |

> **注**：所有 55 条策略均落在 L1 或 L2。L3 不需要独立模板 —— 单命名空间需求通过 L2 Constraint 的 `spec.match.namespaces[]` 指定即可满足。

---

## 2. 分层决策矩阵

### 2.1 放入 L1（平台全局）的判断标准

- **跨 Namespace 有全局影响**：同一资源在多个 NS 间冲突（如证书名重复、DNS 名重复）
- **系统资源保护**：涉及 `kube-system` / `kube-public` / 系统组件
- **安全基线不可妥协**：不能因团队需求而降低标准（如 privileged 容器、hostNetwork）
- **审计合规要求**：必须强制执行，不允许dryrun绕过

### 2.2 放入 L2（租户可调）的判断标准

- **策略本身是平台必需的，但参数值因团队而异**
- **平台给出上限/默认值，团队可在范围内调紧**
- **不影响其他 Namespace，不涉及系统资源**
- **策略失败不影响平台安全性，只影响该团队自身服务**

---

## 3. 分层明细表

### L1 — 平台全局（49条）

| 类别 | 策略名称 | 分层理由 |
|------|----------|---------|
| **Certificate / Secret** | `certificate-deny-duplicate-secret-name-in-the-same-namespace` | TLS Secret 名称重复会在同一命名空间内覆盖导致证书失效，属于命名空间内的致命配置错误，必须强制阻止 |
| **Cluster Resource** | `cluster-resource-quota` | 集群全局资源配额跟踪，防止任何单一租户耗尽集群资源，影响全局稳定性 |
| **Container — Deny** | `container-deny-added-caps` | Linux capability 提升是容器逃逸的主要手段，必须强制禁止，是平台安全基线不可妥协 |
| **Container — Deny** | `container-deny-env-var-secrets` | 将 Secret 注入环境变量是凭证泄露的常见途径，强制要求使用 Volume 挂载方式读取 Secret |
| **Container — Deny** | `container-deny-escalation** | 容器特权升级允许获取更高权限，是横向移动的前提，必须在平台层强制阻止 |
| **Container — Deny** | `container-deny-latest-tag` | `:latest` 标签导致镜像版本不确定，无法保证部署可重复性且可能引入未知漏洞 |
| **Container — Deny** | `container-deny-privileged` | 特权容器拥有宿主机 root 权限，可突破容器边界，必须作为平台强制基线 |
| **Container — Deny** | `container-deny-run-as-system-user` | 以系统用户（UID < 10000）运行的容器具有更高风险，违反最小权限原则 |
| **Container — Deny** | `container-deny-without-resource-requests` | 未设置资源 requests 的 Pod 会导致 Kubernetes 调度决策失误，影响节点稳定性 |
| **Container — Deny** | `container-deny-without-runasnonroot` | 未明确声明以非 root 运行的容器存在潜在安全风险，平台强制要求声明式非 root |
| **Container — Deny** | `container-deny-writable-root-filesystem` | 可写的 rootfs 意味着攻击者可修改容器文件系统，持久化攻击载体 |
| **Container — Capabilities** | `container-drop-all-caps` | 平台强制要求容器放弃所有非必要 Linux capabilities，减少攻击面 |
| **Container — Image** | `container-image-pull-policy-always` | 确保每次 Pod 启动都重新拉取镜像，保证漏洞修复及时生效 |
| **Container — Whitelist** | `containers-whitelist-apparmor-profiles` | AppArmor 配置错误可导致安全Profiles被绕过，由平台统一管理确保 Profiles 有效 |
| **Container — Whitelist** | `containers-whitelist-seccomp-profiles` | Seccomp 配置缺失会使容器暴露于未过滤的系统调用，平台强制要求使用已批准的 Profiles |
| **CRD** | `crd-group-blocklist` | 阻止使用平台禁用的 CRD API 组，防止引入未经审批的自定义 API 资源 |
| **Container Signing (CSCS)** | `cscs-deny-attestation-verification-failed` | 未签名或签名验证失败的镜像可能包含恶意代码，是软件供应链安全的核心防线 |
| **Container Signing (CSCS)** | `cscs-deny-attestation-verification-failed-customer` | 客户托管密钥版本，提供更严格的签名验证，适合高安全场景 |
| **DNS** | `deny-duplicate-dns-names` | 同一集群内 Ingress hostname 重复会导致流量路由不确定，必须全局强制 |
| **DNS** | `dns-endpoint-deny-dns-name-prefixes` | 阻止使用平台禁用的 DNS 前缀（如内网解析前缀被外部滥用），属于全局网络安全策略 |
| **DNS** | `dns-endpoint-deny-invalid-records` | 无效 DNS 记录会导致解析失败或被劫持，影响集群内外网络连通性 |
| **DNS** | `dns-endpoint-whitelist-dns-name-suffixes` | 限制可解析的 DNS 后缀，防止 DNS 解析被滥用为数据渗出通道 |
| **Flux** | `deny-flux-conflict` | Flux CD 资源定义冲突会导致集群状态不一致，影响 GitOps 可靠性 |
| **Gateway / Envoy** | `envoy-gateway-deny-custom-gateway-class` | 平台统一管理 GatewayClass，使用非批准的自定义 GatewayClass 会绕过平台网络策略 |
| **Gateway / Envoy** | `gateway-deny-priv-port` | 非管理员权限无法绑定特权端口（< 1024），强行配置会导致部署失败 |
| **Gateway / Envoy** | `gateway-whitelist-ciphersuites` | 弱密码套件会导致 TLS 降级攻击，由平台统一配置确保全站 TLS 安全性一致 |
| **Gateway / Envoy** | `gateway-whitelist-min-protocol-version` | TLS 1.0/1.1 存在已知漏洞，平台强制要求最低 TLS 1.2 保障通信安全 |
| **Gateway / Envoy** | `gateway-whitelist-protocols` | 非 HTTP 协议流量（如 TCP 直通）可能绕过平台安全策略，需要统一管控 |
| **Ingress** | `ingress-deny-host-prefixes` | 阻止使用平台禁止的 Ingress hostname 前缀，防止域名混淆和 DNS 劫持 |
| **Namespace** | `namespace-deny-system-interaction` | 禁止在 kube-system/kube-public 创建资源，防止系统命名空间被误用导致集群故障 |
| **Namespace** | `deny-system-resources-interaction` | 禁止与系统资源交互，确保集群管理组件不被业务负载干扰 |
| **PersistentVolume** | `persistent-volume-deny-duplicate-csi-volume-handle` | 重复的 CSI VolumeHandle 会导致数据覆写或 PV 绑定冲突，影响有状态服务稳定性 |
| **PersistentVolume** | `persistent-volume-deny-system-claimed` | 系统组件使用的 PV 被业务占用会导致系统 Pod 被驱逐，影响集群稳定性 |
| **PersistentVolume** | `persistent-volume-whitelist-csi-driver` | 非白名单 CSI Driver 未经过安全评估，可能存在数据泄露或漏洞 |
| **Pod — Deny** | `pod-deny-blocking-scale-down` | 阻止节点缩容的 Pod（如使用本地存储且无 PDB）会导致节点无法正常腾空 |
| **Pod — Deny** | `pod-deny-host-ipc` | hostIPC 允许容器访问宿主机共享内存，可进行跨容器数据窃取，必须强制禁止 |
| **Pod — Deny** | `pod-deny-host-network` | hostNetwork 使容器能嗅探宿主机上所有网络流量，属于高危隔离突破 |
| **Pod — Deny** | `pod-deny-host-pid` | hostPID 允许容器看到宿主机进程，可能泄露敏感进程信息 |
| **Pod — Deny** | `pod-deny-priority-class` | 无 PriorityClass 的 Pod 在资源紧张时最先被驱逐，影响服务稳定性预期 |
| **Pod — Deny** | `pod-deny-root-fsgroup` | root fsGroup (UID 0) 意味着容器内进程可写属于 root 的文件，存在权限提升风险 |
| **Pod — Whitelist** | `pod-whitelist-volumes` | 某些 Volume 类型（如 hostPath）存在持久化攻击风险，需要平台统一审批 |
| **PriorityClass** | `priority-class-deny-system-interaction` | 禁止 Pod 引用系统 PriorityClass（如 system-*），防止业务负载抢占系统组件资源 |
| **Prometheus** | `prometheus-rule-whitelist-metadata` | PrometheusRule 缺少元数据标签会导致监控指标无法被正确抓取和告警，影响可观测性 |
| **RBAC** | `rbac-deny-modify-labeled-cluster-role-and-binding` | 保护标记的 ClusterRole/ClusterRoleBinding 被修改，防止权限提升攻击 |
| **RBAC** | `role-binding-whitelist-subjects` | 防止非授权的 ServiceAccount/User 被绑定到高权限 Role，需平台审批防止横向移动 |
| **StorageClass** | `storage-class-deny-default-annotations` | 覆盖默认 StorageClass 注解会导致动态 PV 分配行为不一致，影响有状态应用 |
| **StorageClass** | `storage-class-warn-missing-cmek-encryption` | 未使用 CMEK 加密的存储类会违反数据安全合规要求，需平台强制警告 |
| **StorageClass** | `storage-class-whitelist-provisioners` | 非白名单存储 provisioner 未经安全评估，可能存在数据安全或性能问题 |
| **Validation** | `unexpected-admission-webhook-audit` | 检测意外注册的 admission webhooks，防止未经审批的 webhook 劫持集群准入流量 |
| **VolumeSnapshot** | `volume-snapshot-class-whitelist-csi-driver` | 非白名单 CSI Driver 的 VolumeSnapshot 可能存在数据安全风险 |

### L2 — 租户可调（6条）

| 类别 | 策略名称 | 租户调整范围 | 分层理由 |
|------|----------|-------------|---------|
| **Container — Whitelist** | `container-whitelist-image-prefix` | 团队在平台批准仓库列表（如 `docker.io/gcr.io/ghcr.io`）内进一步限制可用的镜像前缀 | 镜像仓库白名单是平台基线（L1 `K8sAllowedRepos` 已强制），但团队可根据需要进一步收窄，仅允许自己团队使用的具体镜像路径 |
| **Container — Deny** | `container-deny-run-as-system-user` | 特定命名空间允许例外（如遗留有状态服务需要以 system 用户运行）| 系统用户运行限制是安全基线，但某些遗留有状态服务（ES/Kafka）官方镜像设计为 system 用户，团队可申请临时 Exception 在 dryrun 模式下运行 |
| **Container — Deny** | `container-deny-without-resource-requests** | 团队可在此基础上要求必须设置 limits（平台仅要求 requests）| 平台只要求 requests 保调度，团队可以进一步要求所有容器必须设置 CPU/memory limits，在团队内强制实施更严格的资源管理 |
| **Container — Deny** | `container-deny-writable-root-filesystem` | 特定工作负载可申请只读根文件系统豁免（如需要临时写入 /tmp 的工具容器）| 只读 rootfs 是安全最佳实践，但某些调试工具或中间件镜像需要写入临时文件，团队可在 dryrun 模式下测试后再决定是否全面推行 |
| **DNS** | `dns-endpoint-deny-dns-name-prefixes` | 平台维护黑名单前缀，团队可在黑名单基础上申请额外前缀加入自己团队的拒绝列表 | DNS 前缀黑名单是平台全局策略，团队可根据自身业务需求（如禁止访问特定的内部域名）申请在团队范围内扩展拒绝列表 |
| **RBAC** | `role-binding-whitelist-subjects` | 平台维护白名单主体类型（如 `User` / `ServiceAccount`），团队可进一步限制允许绑定到特定 Role 的主体范围 | 平台要求白名单主体防止权限滥用，团队可在平台白名单内进一步收窄，如只允许特定 ServiceAccount 绑定某些 Role |

---

## 4. 分层统计

### 4.1 按层级统计

| 层级 | 数量 | 说明 |
|------|:----:|------|
| **L1 平台全局** | 49 | 强制 deny，不可覆盖 |
| **L2 租户可调** | 6 | 平台基础 + 团队定制参数 |
| **L3 命名空间特供** | 0 | 单 NS 需求通过 L2 + namespace selector 实现，无需独立模板 |
| **合计** | **55** | |

### 4.2 L1 按类别分布

| 类别 | L1 数量 | 占比 |
|------|:-------:|-----:|
| Pod — Deny | 6 | 12.2% |
| Container — Deny | 10 | 20.4% |
| Gateway / Envoy | 5 | 10.2% |
| DNS | 3 | 6.1% |
| PersistentVolume | 3 | 6.1% |
| StorageClass | 3 | 6.1% |
| RBAC | 2 | 4.1% |
| Container — Whitelist | 2 | 4.1% |
| Container — Capabilities/Image | 2 | 4.1% |
| Container Signing (CSCS) | 2 | 4.1% |
| Namespace | 2 | 4.1% |
| 其他（Certificate/ClusterResource/CRD/Flux/Ingress/PriorityClass/Prometheus/Validation/VolumeSnapshot）| 9 | 18.4% |

### 4.3 L2 可调策略调整空间

| L2 策略 | 平台默认值 | 团队可调范围 | 调整上限 |
|---------|-----------|------------|---------|
| `container-whitelist-image-prefix` | `[docker.io, gcr.io, ghcr.io]` | 在平台列表内收窄 | 只能减少，不能新增未批准仓库 |
| `container-deny-run-as-system-user` | UID ≥ 10000 | 可申请特定 NS 例外 | 仅 dryrun，不升为 deny |
| `container-deny-without-resource-requests` | 必须有 requests | 可进一步要求必须设 limits | 更严格，可要求所有容器设 limits |
| `container-deny-writable-root-filesystem` | 必须只读 | 可申请豁免特定容器 | 仅 dryrun，不升为 deny |
| `dns-endpoint-deny-dns-name-prefixes` | 平台黑名单前缀 | 可申请额外前缀加入团队拒绝列表 | 只能追加，不能删除平台黑名单 |
| `role-binding-whitelist-subjects` | User / SA / Group 均可 | 可收窄白名单主体类型范围 | 更严格 |

---

## 5. L2 策略实施示例

### 5.1 container-whitelist-image-prefix（团队级收窄）

```yaml
# 平台基线：允许 docker.io / gcr.io / ghcr.io
# team-a 团队：只允许 gcr.io 和 ghcr.io（自建镜像，不允许直接用 docker.io）
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: ContainerWhitelistImagePrefix
metadata:
  name: team-a-image-prefix
  labels:
    tenant.platform.io/team: "team-a"
    policy.platform.io/type: "tenant-specific"
    policy.platform.io/layer: "L2"
spec:
  enforcementAction: deny
  match:
    namespaces:
    - "team-a-dev"
    - "team-a-staging"
    - "team-a-prod"
  parameters:
    prefixes:
    - "gcr.io/"
    - "ghcr.io/"
    - "docker.io/library/"    # 仅允许官方 library 镜像
```

### 5.2 container-deny-without-resource-requests（团队升级为 limits 要求）

```yaml
# 平台基线：要求必须有 resource.requests
# team-b：要求所有容器必须同时设置 limits（在平台基础上的更严格要求）
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: ContainerDenyWithoutResourceRequests
metadata:
  name: team-b-require-limits
  labels:
    tenant.platform.io/team: "team-b"
    policy.platform.io/type: "tenant-specific"
    policy.platform.io/layer: "L2"
spec:
  enforcementAction: deny
  match:
    namespaces:
    - "team-b-prod"    # 仅在 prod 强制，dev 环境宽松
  parameters:
    requireLimits: true    # 平台模板扩展参数，团队额外要求
    cpuRequest: "100m"
    memoryRequest: "256Mi"
```

---

## 6. 分层与 Exception 机制的关系

```
                    Exception 申请
                          │
                          ▼
┌─────────────────────────────────────────────────┐
│            L1 策略（49条）                        │
│  不可通过 Exception 降级为 dryrun                  │
│  仅允许临时调高上限值（如 container-limits: 32C）   │
│  Emergency Exception 最长 72 小时                  │
└─────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────┐
│            L2 策略（6条）                         │
│  可通过 Exception 在指定 NS 以 dryrun 豁免        │
│  需 Team Lead + Platform Lead 双签审批            │
│  最长 90 天，需每 30 天重新评估                    │
└─────────────────────────────────────────────────┘
```

---

## 7. 关键设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| L1 策略是否允许 Exception 降级 | **不允许** | L1 是安全基线，降级会破坏平台统一安全水位 |
| L2 策略是否可升为 L1 强制 | **可以** | 团队若希望更严格执行，可将 L2 策略在团队内以 deny 执行 |
| L3 是否需要独立模板 | **不需要** | 单命名空间需求通过 L2 + `spec.match.namespaces[]` 即可满足 |
| 所有 55 条策略是否必须启用 | **可选** | Platform Team 可根据集群风险评估选择启用子集 |
| L2 调整是否有上限 | **有** | 租户调整只能更严格（L1 基础上收窄），不能放宽平台设定 |

---

## 8. 迁移路径建议

| 阶段 | 策略范围 | 执行方式 | 持续时间 |
|------|---------|----------|---------|
| **Phase 1** | 所有 L1 策略 | `dryrun` 审计 | 30 天 |
| **Phase 2** | L1 安全类（Container/Pod/RBAC） | `deny` | 第 31 天起 |
| **Phase 3** | L1 可靠性/网络类 | `deny` | 第 61 天起 |
| **Phase 4** | L2 策略 | `dryrun` | 同步开始 |
| **Phase 5** | L2 策略 | `deny`（按需） | 团队准备好后 |

> **注意**：所有 L1 策略启用 deny 前，需确认当前集群无违规资源，否则会阻塞已有工作负载。建议先通过 Audit 模式运行 30 天清理存量问题。
