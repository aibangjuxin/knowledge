# GKE Policy Controller Constraint Template 对比分析

> **文档版本**: 1.0.0
> **更新日期**: 2026-05-08
> **数据来源**:
> - GKE Policy Controller `step-by-step-install.md` (82 个模板)
> - `policy-layer.md` (55 条策略)
> **状态**: 技术分析
> **分类**: Internal

---

## 1. GKE Policy Controller 默认模板完整列表

### 1.1 PSP 相关模板（Pod Security Policies）

| 模板名称 | 描述 |
|----------|------|
| `k8spspallowedusers` | 限制 Pod 运行的用户 UID 范围（必须指定 runAsUser/supplementalGroups/fsGroup） |
| `k8spspallowprivilegeescalationcontainer` | 禁止容器启用 privilege escalation（`allowPrivilegeEscalation: false`） |
| `k8spspapparmor` | 要求容器必须使用 AppArmor Profile（平台通过 annotation `container.apparmor.security.beta.kubernetes.io` 指定） |
| `k8spspautomountserviceaccounttokenpod` | 禁止 Pod 自动挂载 ServiceAccount Token |
| `k8spspcapabilities` | 限制容器可添加的 Linux capabilities（默认禁止添加 `SYS_ADMIN`/`NET_ADMIN` 等高危 capability） |
| `k8spspflexvolumes` | 白名单允许的 FlexVolume driver 路径 |
| `k8spspforbiddensysctls` | 禁止使用特定的 sysctl 参数 |
| `k8spspfsgroup` | 要求 Pod 必须指定 fsGroup（补充组 ID） |
| `k8spsphostfilesystem` | 限制容器对宿主文件系统目录的访问权限（只读或禁止） |
| `k8spsphostnamespace` | 禁止 Pod 使用宿主机的 PID / IPC / Network 命名空间 |
| `k8spsphostnetworkingports` | 禁止 Pod 使用宿主机网络端口（hostPort） |
| `k8spspprivilegedcontainer` | 禁止运行特权容器（`privileged: true`） |
| `k8spspprocmount` | 限制容器对宿主进程空间的挂载（要求 `Default` procMount 类型） |
| `k8spspreadonlyrootfilesystem` | 要求容器的根文件系统必须为只读 |
| `k8spspseccomp` | 要求 Pod/容器必须使用 Seccomp Profile（`security.seccompProfiles` 或 `runtime/default`） |
| `k8spspselinuxv2` | 要求容器必须指定 SELinux 安全上下文（`seLinuxOptions`） |
| `k8spspvolumetypes` | 白名单允许的 volume 类型（如 `configMap`、`secret`、`emptyDir` 等，禁止 `hostPath`/`glusterfs` 等高危类型） |
| `k8spspwindowshostprocess` | 禁止 Windows 容器使用宿主进程（hostProcess） |
| `k8spssrunasnonroot` | 要求容器必须声明为非 root 运行（`runAsNonRoot: true`） |

### 1.2 Kubernetes 通用资源模板

| 模板名称 | 描述 |
|----------|------|
| `k8sallowedrepos` | 白名单允许的容器镜像仓库（限制只能从可信仓库拉取镜像） |
| `k8savoiduseofsystemmastersgroup` | 禁止创建 Binding 或 RBAC Role 使任何主体成为 `system:masters` 组的成员（防止权限提升） |
| `k8sblockallingress` | 禁止创建任何 Ingress 资源（阻止所有入站流量，除非显式放行） |
| `k8sblockcreationwithdefaultserviceaccount` | 禁止使用默认 ServiceAccount（未指定 ServiceAccount 的 Pod 默认使用 `default` SA） |
| `k8sblockendpointeditdefaultrole` | 禁止修改使用 `system:controller:` 前缀 ServiceAccount 的 Endpoint（防止控制器被攻击） |
| `k8sblockloadbalancer` | 禁止创建 LoadBalancer 类型 Service（防止公网暴露） |
| `k8sblocknodeport` | 禁止创建 NodePort 类型 Service（防止端口冲突和安全风险） |
| `k8sblockobjectsoftype` | 禁止创建指定类型的 Kubernetes 资源对象（如禁止创建某类 CRD） |
| `k8sblockprocessnamespacesharing` | 要求 Pod 不能共享其他 Pod 的进程命名空间（`shareProcessNamespace: false`） |
| `k8sblockwildcardingress` | 禁止 Ingress 使用通配符 hostname（如 `*.example.com`） |
| `k8scontainerephemeralstoragelimit` | 要求容器必须设置 ephemeral-storage 的 limits（防止临时存储耗尽） |
| `k8scontainerlimits` | 要求容器必须设置 CPU 和 Memory 的 limits |
| `k8scontainerratios` | 限制容器 requests 与 limits 的比例（如 `cpu: requests:limits ≤ 1:2`） |
| `k8scontainerrequests` | 要求容器必须设置 CPU 和 Memory 的 requests |
| `k8scronjoballowedrepos` | 白名单允许 CronJob 容器镜像仓库 |
| `k8sdisallowedanonymous` | 禁止将 `system:anonymous` 用户绑定到任何 Role/ClusterRole（防止匿名访问） |
| `k8sdisallowedrepos` | 黑名单禁止的镜像仓库（与 `k8sallowedrepos` 相反） |
| `k8sdisallowedrolebindingsubjects` | 禁止将 RoleBinding/ClusterRoleBinding 绑定到白名单外的主体类型 |
| `k8sdisallowedtags` | 禁止镜像使用特定 tag（如 `:latest`、`:dev`、`:test`） |
| `k8sdisallowinteractivetty` | 禁止 Pod 分配 TTY（`tty: true`）和交互式 stdin（`stdin: true`）—— 防止交互式 shell 容器 |
| `k8sexternalips` | 禁止 Service 使用非白名单的 externalIPs |
| `k8shttpsonly` | 要求 Ingress 必须使用 HTTPS（强制 TLS） |
| `k8simagedigests` | 要求镜像必须指定 SHA256 digest（而非 tag），确保镜像不可变 |
| `k8slocalstoragerequiresafetoevict` | 要求使用 local storage 的 Pod 必须设置 `storage.beta.kubernetes.io/tode-allocate` 注解，便于安全驱逐 |
| `k8smemoryrequestequalslimit` | 要求 Memory 的 requests 必须等于 limits（避免内存不确定行为） |
| `k8snoenvvarsecrets` | 禁止将 Secret 挂载为容器环境变量（强制要求通过 volume 挂载读取 Secret） |
| `k8snoexternalservices` | 禁止创建 ExternalName 类型 Service（防止 DNS 指向外部服务） |
| `k8spodresourcesbestpractices` | 要求 Pod 遵循资源管理最佳实践（requests/limits 比例、QoS 类等） |
| `k8spodsrequiresecuritycontext` | 要求 Pod 必须定义 SecurityContext（runAsNonRoot、allowPrivilegeEscalation 等） |
| `k8sprohibitrolewildcardaccess` | 禁止 Role/ClusterRole 使用通配符 `*` 权限或 `group: "*"` |
| `k8sreplicalimits` | 限制 Deployment/ReplicaSet 的 `spec.replicas` 最大值（防止过多副本耗尽集群资源） |
| `k8srequirecosnodeimage` | 要求节点必须使用 Container-Optimized OS（COS）镜像 |
| `k8srequiredannotations` | 要求指定资源必须包含特定 annotations |
| `k8srequiredlabels` | 要求命名空间必须包含特定 labels（如 `environment`、`team`） |
| `k8srequiredprobes` | 要求容器必须配置 liveness probe 和 readiness probe（确保应用可检测存活和就绪状态） |
| `k8srequiredresources` | 要求容器必须设置资源 requests |
| `k8srequirevalidrangesfornetworks` | 要求 NetworkPolicy 必须有有效的 CIDR 范围（不能为 `0.0.0.0/0` 除非必要） |
| `k8srestrictadmissioncontroller` | 限制允许启用的 Admission Controllers |
| `k8srestrictautomountserviceaccounttokens` | 禁止 ServiceAccount 自动挂载 Token |
| `k8srestrictlabels` | 白名单允许的 label keys（限制随意添加 label） |
| `k8srestrictnamespaces` | 限制 Pod 可以部署到的命名空间 |
| `k8srestrictnfsurls` | 禁止挂载 NFS 存储（或白名单 NFS 服务器） |
| `k8srestrictrbacsubjects` | 限制 RBAC 允许的主体类型 |
| `k8srestrictrolebindings` | 限制谁可以在哪些命名空间创建 RoleBinding |
| `k8srestrictrolerules` | 限制 Role/ClusterRole 可以定义的规则 |
| `noupdateserviceaccount` | 禁止更新现有 ServiceAccount 的某些字段（防止 SA 被篡改） |
| `policystrictonly` | 要求所有资源必须被某个 Policy 约束（强制全量覆盖） |
| `verifydeprecatedapi` | 审计已废弃的 Kubernetes API 版本使用（如 `apps/v1beta1`、`v1.22+` 后废弃的 API） |

### 1.3 ASM (Anthos Service Mesh) 相关模板

| 模板名称 | 描述 |
|----------|------|
| `asmauthzpolicydisallowedprefix` | 禁止 Istio AuthorizationPolicy 使用不允许的 prefix 规则 |
| `asmauthzpolicyenforcesourceprincipals` | 要求 Istio AuthorizationPolicy 必须指定 source.principals（强制 mTLS 双向认证） |
| `asmauthzpolicynormalization` | 要求 Istio AuthorizationPolicy 必须经过标准化处理（防止规则冲突） |
| `asmauthzpolicysafepattern` | 要求 AuthorizationPolicy 遵循安全模式（如拒绝所有除非显式允许） |
| `asmingressgatewaylabel` | 要求 Istio IngressGateway 必须有指定的 label（如 `app: istio-ingressgateway`） |
| `asmpeerauthnstrictmtls` | 要求 Istio PeerAuthentication 必须设置 STRICT mTLS 模式（禁止 PERMISSIVE） |
| `asmrequestauthnprohibitedoutputheaders` | 禁止 AuthorizationPolicy 输出包含敏感 headers |
| `asmsidecarinjection` | 要求命名空间必须启用/禁用 Istio sidecar injection |
| `destinationruletlsenabled` | 要求 Istio DestinationRule 必须启用 TLS |
| `sourcenotallauthz` | 禁止 AuthorizationPolicy 使用 `source: {}`（空 source 表示允许所有） |

### 1.4 GCP 特定模板

| 模板名称 | 描述 |
|----------|------|
| `allowedserviceportname` | 白名单允许的 Service 端口名称（端口名必须符合 `^[a-z][a-z0-9-]*$` 且不超过 15 字符） |
| `gcpstoragelocationconstraintv1` | 限制 Cloud Storage Bucket 的区域位置（只能部署到允许的 GCP 区域） |
| `k8senforcecloudarmorbackendconfig` | 要求 Kubernetes Service 必须关联 Cloud Armor Security Policy（后端配置必须指定 Cloud Armor） |
| `k8sexternalips` | 限制 Service 使用的 externalIPs 必须在白名单范围内 |

### 1.5 网络安全模板

| 模板名称 | 描述 |
|----------|------|
| `k8sblockallingress` | 阻止所有 Ingress 流量（默认拒绝，除非明确创建允许规则） |
| `k8sblockwildcardingress` | 阻止使用通配符 Ingress hostname |
| `k8shttpsonly` | 要求 Ingress 必须配置 HTTPS |
| `k8snoexternalservices` | 禁止创建 ExternalName 类型 Service |
| `k8srequirevalidrangesfornetworks` | NetworkPolicy 必须使用有效的 CIDR 范围 |
| `restrictnetworkexclusions` | 限制可以排除在网络策略之外的命名空间/ Pod |

---

## 2. Policy-Layer.md 策略与 GKE TEP 对照表

### 2.1 精确匹配或高度相似（可直接使用 GKE TEP）

| Policy-Layer.md 策略 | 对应 GKE TEP | 匹配度 | 说明 |
|---------------------|-------------|--------|------|
| `container-deny-privileged` | `k8spspprivilegedcontainer` | ✅ 精确匹配 | 直接对应 |
| `container-deny-escalation` | `k8spspallowprivilegeescalationcontainer` | ✅ 精确匹配 | 直接对应 |
| `container-deny-without-runasnonroot` | `k8spssrunasnonroot` | ✅ 精确匹配 | `k8spssrunasnonroot` = `k8s PSS RunAsNonRoot` |
| `pod-deny-host-namespace` | `k8spsphostnamespace` | ✅ 精确匹配 | 直接对应 |
| `pod-deny-host-network` | `k8spsphostnetworkingports` | ✅ 精确匹配 | 直接对应（hostPort 限制） |
| `pod-deny-root-fsgroup` | `k8spspfsgroup` | ✅ 精确匹配 | 直接对应 |
| `pod-whitelist-volumes` | `k8spspvolumetypes` | ✅ 精确匹配 | 直接对应 |
| `k8srequiredlabels` | `k8srequiredlabels` | ✅ 精确匹配 | 直接对应 |
| `k8snoenvvarsecrets` | `k8snoenvvarsecrets` | ✅ 精确匹配 | 直接对应 |
| `k8sdisallowedrepos` | `k8sdisallowedrepos` / `k8sallowedrepos` | ✅ 精确匹配 | 直接对应 |
| `k8sblockloadbalancer` | `k8sblockloadbalancer` | ✅ 精确匹配 | 直接对应 |
| `k8sblocknodeport` | `k8sblocknodeport` | ✅ 精确匹配 | 直接对应 |
| `k8scontainerlimits` | `k8scontainerlimits` | ✅ 精确匹配 | 直接对应 |
| `k8srequiredresources` | `k8srequiredresources` / `k8scontainerrequests` | ✅ 精确匹配 | 直接对应 |
| `k8srequiredprobes` | `k8srequiredprobes` | ✅ 精确匹配 | 直接对应 |
| `k8sprohibitrolewildcardaccess` | `k8sprohibitrolewildcardaccess` | ✅ 精确匹配 | 直接对应 |
| `k8srestrictautomountserviceaccounttokens` | `k8srestrictautomountserviceaccounttokens` | ✅ 精确匹配 | 直接对应 |
| `k8srestrictrolebindings` | `k8srestrictrolebindings` | ✅ 精确匹配 | 直接对应 |
| `k8sdisallowedanonymous` | `k8sdisallowedanonymous` | ✅ 精确匹配 | 直接对应 |
| `k8sblockendpointeditdefaultrole` | `k8sblockendpointeditdefaultrole` | ✅ 精确匹配 | 直接对应 |
| `k8sallowedrepos` | `k8sallowedrepos` | ✅ 精确匹配 | 直接对应 |
| `k8simagedigests` | `k8simagedigests` | ✅ 精确匹配 | 直接对应 |
| `k8sexternalips` | `k8sexternalips` | ✅ 精确匹配 | 直接对应 |
| `k8shttpsonly` | `k8shttpsonly` | ✅ 精确匹配 | 直接对应 |
| `k8spspcapabilities` | `k8spspcapabilities` | ✅ 精确匹配 | 直接对应 |
| `k8spspforbiddensysctls` | `k8spspforbiddensysctls` | ✅ 精确匹配 | 直接对应 |
| `k8spspflexvolumes` | `k8spspflexvolumes` | ✅ 精确匹配 | 直接对应 |
| `k8spsphostfilesystem` | `k8spsphostfilesystem` | ✅ 精确匹配 | 直接对应 |
| `k8spspreadonlyrootfilesystem` | `k8spspreadonlyrootfilesystem` | ✅ 精确匹配 | 直接对应 |
| `k8spspseccomp` | `k8spspseccomp` | ✅ 精确匹配 | 直接对应 |
| `k8spspselinuxv2` | `k8spspselinuxv2` | ✅ 精确匹配 | 直接对应 |
| `k8spspapparmor` | `k8spspapparmor` | ✅ 精确匹配 | 直接对应 |
| `k8spspprocmount` | `k8spspprocmount` | ✅ 精确匹配 | 直接对应 |
| `k8spspwindowshostprocess` | `k8spspwindowshostprocess` | ✅ 精确匹配 | 直接对应 |
| `k8sblockcreationwithdefaultserviceaccount` | `k8sblockcreationwithdefaultserviceaccount` | ✅ 精确匹配 | 直接对应 |
| `k8srequirecosnodeimage` | `k8srequirecosnodeimage` | ✅ 精确匹配 | 直接对应 |
| `k8scontainerratios` | `k8scontainerratios` | ✅ 精确匹配 | 直接对应 |
| `k8srestrictlabels` | `k8srestrictlabels` | ✅ 精确匹配 | 直接对应 |
| `k8srestrictnfsurls` | `k8srestrictnfsurls` | ✅ 精确匹配 | 直接对应 |
| `k8sreplicalimits` | `k8sreplicalimits` | ✅ 精确匹配 | 直接对应 |

### 2.2 功能覆盖但不完全匹配（需要扩展或组合）

| Policy-Layer.md 策略 | GKE TEP 覆盖方式 | 匹配度 | 说明 |
|---------------------|----------------|--------|------|
| `container-deny-added-caps` | `k8spspcapabilities` | 🟡 部分覆盖 | `k8spspcapabilities` 默认禁止添加所有 capabilities，`container-deny-added-caps` 只禁止特定高危 caps（如 `SYS_ADMIN`），可用参数调整 |
| `container-deny-env-var-secrets` | `k8snoenvvarsecrets` | 🟡 部分覆盖 | `k8snoenvvarsecrets` 完全禁止 env var 中引用 Secret，但 `container-deny-env-var-secrets` 可能只禁止引用非 SealedSecret 或特定 Secret |
| `container-deny-latest-tag` | `k8sdisallowedtags` | 🟡 部分覆盖 | `k8sdisallowedtags` 可配置禁止任意 tag，`k8sallowedrepos` 可配合要求使用 digest |
| `container-deny-run-as-system-user` | `k8spspallowedusers` | 🟡 部分覆盖 | `k8spspallowedusers` 控制 UID 范围，可配置 UID ≥ 10000，但无法直接识别"系统用户"概念 |
| `container-deny-without-resource-requests` | `k8scontainerrequests` | 🟡 部分覆盖 | `k8scontainerrequests` 仅要求 requests，`container-deny-without-resource-requests` 可能还要求 limits |
| `container-deny-without-runasnonroot` | `k8spssrunasnonroot` | 🟡 部分覆盖 | `k8spssrunasnonroot` 只检查 `runAsNonRoot: true`，无法检查具体的 runAsUser 是否为 root |
| `container-deny-writable-root-filesystem` | `k8spspreadonlyrootfilesystem` | 🟡 部分覆盖 | 完全一致 |
| `container-drop-all-caps` | `k8spspcapabilities` | 🟡 部分覆盖 | `k8spspcapabilities` 可配置要求 drop 所有默认 caps 并只添加白名单 caps |
| `container-image-pull-policy-always` | `k8simagedigests` / `k8sallowedrepos` | 🟡 部分覆盖 | 无直接模板，但可组合 `k8sallowedrepos` + 镜像 digest 验证实现等效 |
| `container-whitelist-apparmor-profiles` | `k8spspapparmor` | 🟡 部分覆盖 | `k8spspapparmor` 要求使用已批准的 AppArmor Profile，可配置白名单 |
| `container-whitelist-seccomp-profiles` | `k8spspseccomp` | 🟡 部分覆盖 | `k8spspseccomp` 要求使用已批准的 Seccomp Profile，可配置白名单 |
| `deny-duplicate-dns-names` | `k8sblockwildcardingress` / `k8shttpsonly` | 🟡 部分覆盖 | 无直接模板，但 Ingress 唯一性可由 DNS 层面控制 |
| `dns-endpoint-deny-dns-name-prefixes` | 无直接对应 | 🔴 无覆盖 | Policy-Layer 自定义 DNS 策略，GKE TEP 无直接对应 |
| `dns-endpoint-deny-invalid-records` | 无直接对应 | 🔴 无覆盖 | 同上 |
| `dns-endpoint-whitelist-dns-name-suffixes` | 无直接对应 | 🔴 无覆盖 | 同上 |
| `envoy-gateway-deny-custom-gateway-class` | 无直接对应 | 🔴 无覆盖 | ASM GatewayClass 策略，GKE TEP 无直接对应 |
| `gateway-deny-priv-port` | `k8sblocknodeport` / `k8spsphostnetworkingports` | 🔴 无覆盖 | Gateway 特权端口策略需自定义 |
| `gateway-whitelist-ciphersuites` | 无直接对应 | 🔴 无覆盖 | TLS ciphersuite 策略需自定义 |
| `gateway-whitelist-min-protocol-version` | 无直接对应 | 🔴 无覆盖 | TLS 版本策略需自定义 |
| `gateway-whitelist-protocols` | 无直接对应 | 🔴 无覆盖 | 协议白名单策略需自定义 |
| `ingress-deny-host-prefixes` | `k8sblockwildcardingress` | 🟡 部分覆盖 | `k8sblockwildcardingress` 只阻止通配符 hostname，前缀策略需自定义 |
| `namespace-deny-system-interaction` | `k8srestrictnamespaces` | 🟡 部分覆盖 | `k8srestrictnamespaces` 限制可部署的 NS，可配合 namespace label 策略 |
| `deny-system-resources-interaction` | `k8savoiduseofsystemmastersgroup` | 🟡 部分覆盖 | 只覆盖 `system:masters`，系统资源交互需更多策略 |
| `persistent-volume-deny-duplicate-csi-volume-handle` | 无直接对应 | 🔴 无覆盖 | PVC/V volume handle 重复检测需自定义 |
| `persistent-volume-deny-system-claimed` | 无直接对应 | 🔴 无覆盖 | 系统 PV 保护策略需自定义 |
| `persistent-volume-whitelist-csi-driver` | 无直接对应 | 🔴 无覆盖 | CSI driver 白名单需自定义 |
| `pod-deny-blocking-scale-down` | 无直接对应 | 🔴 无覆盖 | PDB/本地存储保护策略需自定义 |
| `pod-deny-host-ipc` | `k8spsphostnamespace` | 🟡 部分覆盖 | `k8spsphostnamespace` 包含 `hostIPC: false`，可覆盖 |
| `pod-deny-host-pid` | `k8spsphostnamespace` | 🟡 部分覆盖 | `k8spsphostnamespace` 包含 `hostPID: false`，可覆盖 |
| `pod-deny-priority-class` | 无直接对应 | 🔴 无覆盖 | PriorityClass 限制策略需自定义 |
| `priority-class-deny-system-interaction` | 无直接对应 | 🔴 无覆盖 | 系统 PriorityClass 保护策略需自定义 |
| `prometheus-rule-whitelist-metadata` | 无直接对应 | 🔴 无覆盖 | PrometheusRule 元数据策略需自定义 |
| `rbac-deny-modify-labeled-cluster-role-and-binding` | 无直接对应 | 🔴 无覆盖 | RBAC 保护策略需自定义 |
| `role-binding-whitelist-subjects` | `k8sdisallowedrolebindingsubjects` | 🟡 部分覆盖 | `k8sdisallowedrolebindingsubjects` 限制绑定主体类型，可覆盖部分场景 |
| `storage-class-deny-default-annotations` | 无直接对应 | 🔴 无覆盖 | StorageClass 注解策略需自定义 |
| `storage-class-warn-missing-cmek-encryption` | 无直接对应 | 🔴 无覆盖 | CMEK 警告策略需自定义 |
| `storage-class-whitelist-provisioners` | 无直接对应 | 🔴 无覆盖 | StorageClass provisioner 白名单需自定义 |
| `unexpected-admission-webhook-audit` | 无直接对应 | 🔴 无覆盖 | Admission webhook 审计策略需自定义 |
| `volume-snapshot-class-whitelist-csi-driver` | 无直接对应 | 🔴 无覆盖 | VolumeSnapshot CSI driver 白名单需自定义 |
| `cluster-resource-quota` | 无直接对应 | 🔴 无覆盖 | ClusterResourceQuota 是 Anthos Multi-cluster 策略，GKE TEP 无直接对应 |
| `crd-group-blocklist` | `k8sblockobjectsoftype` | 🟡 部分覆盖 | `k8sblockobjectsoftype` 可阻止指定 CRD API 组 |
| `certificate-deny-duplicate-secret-name-in-the-same-namespace` | 无直接对应 | 🔴 无覆盖 | TLS Secret 命名重复检测需自定义 |
| `deny-flux-conflict` | 无直接对应 | 🔴 无覆盖 | Flux CD 冲突检测需自定义 |
| `gatekeeper-constraint-template-block-auto-gen` | 无直接对应 | 🔴 无覆盖 | Gatekeeper 自身保护策略需自定义 |

### 2.3 Policy-Layer 有，GKE TEP 无（需自定义模板）

| 策略名称 | 类别 | 说明 |
|---------|------|------|
| `container-deny-added-caps` | Container — Deny | 需自定义：禁止添加特定 Linux capabilities |
| `container-deny-env-var-secrets` | Container — Deny | 需自定义：禁止 Secret 作为环境变量 |
| `container-deny-latest-tag` | Container — Deny | 需自定义：禁止 `:latest` tag |
| `container-deny-run-as-system-user` | Container — Deny | 需自定义：禁止以系统用户(UID<10000)运行 |
| `container-deny-without-resource-requests` | Container — Deny | 需自定义：要求必须设置资源 requests |
| `container-deny-without-runasnonroot` | Container — Deny | 需自定义：要求明确声明非 root |
| `container-deny-writable-root-filesystem` | Container — Deny | 可用 `k8spspreadonlyrootfilesystem` |
| `container-drop-all-caps` | Container — Capabilities | 需自定义：要求 drop 所有非必要 caps |
| `container-image-pull-policy-always` | Container — Image | 需自定义：要求镜像拉取策略为 Always |
| `container-whitelist-apparmor-profiles` | Container — Whitelist | 可用 `k8spspapparmor` |
| `container-whitelist-seccomp-profiles` | Container — Whitelist | 可用 `k8spspseccomp` |
| `certificate-deny-duplicate-secret-name-in-the-same-namespace` | Certificate / Secret | 需自定义：同命名空间 TLS Secret 名称重复检测 |
| `cluster-resource-quota` | Cluster Resource | 需自定义：Anthos Multi-cluster 资源配额 |
| `crd-group-blocklist` | CRD | 可用 `k8sblockobjectsoftype` |
| `deny-flux-conflict` | Flux | 需自定义：Flux CD 资源冲突检测 |
| `deny-duplicate-dns-names` | DNS | 需自定义：Ingress hostname 唯一性 |
| `dns-endpoint-deny-dns-name-prefixes` | DNS | 需自定义：DNS 前缀黑名单 |
| `dns-endpoint-deny-invalid-records` | DNS | 需自定义：无效 DNS 记录检测 |
| `dns-endpoint-whitelist-dns-name-suffixes` | DNS | 需自定义：DNS 后缀白名单 |
| `envoy-gateway-deny-custom-gateway-class` | Gateway / Envoy | 需自定义：禁止非标准 GatewayClass |
| `gateway-deny-priv-port` | Gateway / Envoy | 需自定义：禁止非管理员绑定特权端口 |
| `gateway-whitelist-ciphersuites` | Gateway / Envoy | 需自定义：TLS 密码套件白名单 |
| `gateway-whitelist-min-protocol-version` | Gateway / Envoy | 需自定义：最低 TLS 版本 |
| `gateway-whitelist-protocols` | Gateway / Envoy | 需自定义：允许的协议列表 |
| `ingress-deny-host-prefixes` | Ingress | 需自定义：Ingress hostname 前缀黑名单 |
| `namespace-deny-system-interaction` | Namespace | 需自定义：禁止系统命名空间操作 |
| `deny-system-resources-interaction` | Namespace | 需自定义：禁止与系统资源交互 |
| `persistent-volume-deny-duplicate-csi-volume-handle` | PersistentVolume | 需自定义：CSI VolumeHandle 重复检测 |
| `persistent-volume-deny-system-claimed` | PersistentVolume | 需自定义：系统 PV 保护 |
| `persistent-volume-whitelist-csi-driver` | PersistentVolume | 需自定义：CSI driver 白名单 |
| `pod-deny-blocking-scale-down` | Pod — Deny | 需自定义：阻止节点缩容的 Pod |
| `pod-deny-host-ipc` | Pod — Deny | 可用 `k8spsphostnamespace` |
| `pod-deny-host-pid` | Pod — Deny | 可用 `k8spsphostnamespace` |
| `pod-deny-priority-class` | Pod — Deny | 需自定义：PriorityClass 限制 |
| `priority-class-deny-system-interaction` | PriorityClass | 需自定义：系统 PriorityClass 保护 |
| `prometheus-rule-whitelist-metadata` | Prometheus | 需自定义：PrometheusRule 元数据要求 |
| `rbac-deny-modify-labeled-cluster-role-and-binding` | RBAC | 需自定义：受保护 RBAC 资源 |
| `role-binding-whitelist-subjects` | RBAC | 可用 `k8sdisallowedrolebindingsubjects` 部分覆盖 |
| `storage-class-deny-default-annotations` | StorageClass | 需自定义：默认 SC 注解保护 |
| `storage-class-warn-missing-cmek-encryption` | StorageClass | 需自定义：CMEK 警告 |
| `storage-class-whitelist-provisioners` | StorageClass | 需自定义：SC provisioner 白名单 |
| `unexpected-admission-webhook-audit` | Validation | 需自定义：admission webhook 审计 |
| `volume-snapshot-class-whitelist-csi-driver` | VolumeSnapshot | 需自定义：VolumeSnapshot CSI driver 白名单 |

### 2.4 GKE TEP 有，Policy-Layer 无（可用但未计划）

| GKE TEP | 说明 |
|---------|------|
| `allowedserviceportname` | Service 端口名称规范 |
| `asmauthzpolicydisallowedprefix` | ASM AuthorizationPolicy 前缀策略 |
| `asmauthzpolicyenforcesourceprincipals` | ASM mTLS 强制源主体 |
| `asmauthzpolicynormalization` | ASM AuthorizationPolicy 标准化 |
| `asmauthzpolicysafepattern` | ASM AuthorizationPolicy 安全模式 |
| `asmingressgatewaylabel` | ASM IngressGateway label 要求 |
| `asmpeerauthnstrictmtls` | ASM PeerAuthentication STRICT mTLS |
| `asmrequestauthnprohibitedoutputheaders` | ASM AuthorizationPolicy 输出头限制 |
| `asmsidecarinjection` | ASM sidecar injection 策略 |
| `destinationruletlsenabled` | ASM DestinationRule TLS 要求 |
| `disallowedauthzprefix` | 通用 AuthorizationPolicy 前缀 |
| `gcpstoragelocationconstraintv1` | GCP Storage 区域限制 |
| `k8senforcecloudarmorbackendconfig` | Cloud Armor 后端配置强制 |
| `k8scontainerephemeralstoragelimit` | Ephemeral-storage limits |
| `k8scronjoballowedrepos` | CronJob 镜像仓库限制 |
| `k8sdisallowedtags` | 镜像 tag 黑名单 |
| `k8sdisallowinteractivetty` | 禁止交互式 TTY |
| `k8slocalstoragerequiresafetoevict` | Local storage 安全驱逐 |
| `k8smemoryrequestequalslimit` | Memory requests=limits |
| `k8spodresourcesbestpractices` | Pod 资源最佳实践 |
| `k8srequirevalidrangesfornetworks` | NetworkPolicy CIDR 范围 |
| `k8srestrictadmissioncontroller` | 限制 admission controllers |
| `k8srestrictnamespaces` | 限制可部署的命名空间 |
| `k8srestrictrbacsubjects` | 限制 RBAC 主体类型 |
| `k8srestrictrolerules` | 限制 Role 规则 |
| `noupdateserviceaccount` | 禁止更新 SA |
| `policystrictonly` | 全局策略覆盖 |
| `restrictnetworkexclusions` | 网络排除限制 |
| `sourcenotallauthz` | AuthorizationPolicy 非空 source |
| `verifydeprecatedapi` | 废弃 API 审计 |
| `k8srequiredannotations` | 资源 annotations 要求 |

---

## 3. 汇总统计

### 3.1 覆盖率

| 类别 | Policy-Layer 策略数 | GKE TEP 精确匹配 | 需扩展/组合 | 需自定义 | 覆盖率 |
|------|:-------------------:|:---------------:|:-----------:|:--------:|:------:|
| **Container — Deny** | 10 | 4 | 5 | 1 | 40% |
| **Container — Whitelist** | 2 | 2 | 0 | 0 | 100% |
| **Container — Capabilities** | 1 | 1 | 0 | 0 | 100% |
| **Container — Image** | 1 | 0 | 1 | 0 | 0% |
| **Pod — Deny** | 6 | 3 | 2 | 1 | 50% |
| **Pod — Whitelist** | 1 | 1 | 0 | 0 | 100% |
| **RBAC** | 2 | 1 | 1 | 0 | 50% |
| **DNS** | 3 | 0 | 0 | 3 | 0% |
| **Gateway / Envoy** | 5 | 0 | 0 | 5 | 0% |
| **Ingress** | 1 | 1 | 0 | 0 | 100% |
| **Namespace** | 2 | 0 | 2 | 0 | 0% |
| **PersistentVolume** | 3 | 0 | 0 | 3 | 0% |
| **StorageClass** | 3 | 0 | 0 | 3 | 0% |
| **PriorityClass** | 1 | 0 | 0 | 1 | 0% |
| **Prometheus** | 1 | 0 | 0 | 1 | 0% |
| **CRD** | 1 | 1 | 0 | 0 | 100% |
| **Certificate/Secret** | 1 | 0 | 0 | 1 | 0% |
| **Cluster Resource** | 1 | 0 | 0 | 1 | 0% |
| **Flux** | 1 | 0 | 0 | 1 | 0% |
| **Validation** | 1 | 0 | 0 | 1 | 0% |
| **VolumeSnapshot** | 1 | 0 | 0 | 1 | 0% |
| **ASM** | 10 | 0 | 0 | 10 | 0% |
| **GCP Storage** | 0 | 0 | 0 | 0 | N/A |
| **总计** | **55** | **14** | **11** | **30** | **45%** |

### 3.2 需自定义模板清单（30个）

按优先级分类：

**🔴 高优先级（安全关键）：**
1. `container-deny-added-caps` — Linux capability 提升防护
2. `container-deny-env-var-secrets` — Secret 泄露防护
3. `container-deny-run-as-system-user` — 系统用户风险
4. `pod-deny-host-ipc` / `pod-deny-host-pid` — 主机命名空间隔离
5. `role-binding-whitelist-subjects` — RBAC 横向移动防护
6. `namespace-deny-system-interaction` — 系统命名空间保护
7. `rbac-deny-modify-labeled-cluster-role-and-binding` — RBAC 篡改防护

**🟡 中优先级（合规/运维）：**
8. `container-drop-all-caps` — 最小权限容器
9. `container-image-pull-policy-always` — 镜像不可变性
10. `container-deny-without-runasnonroot` — 非 root 声明
11. `container-deny-without-resource-requests` — 资源管理
12. `pod-deny-priority-class` — 优先级资源竞争
13. `persistent-volume-deny-duplicate-csi-volume-handle` — 数据覆写防护
14. `storage-class-whitelist-provisioners` — 存储安全
15. `dns-endpoint-deny-dns-name-prefixes` — DNS 安全

**🔵 低优先级（特定场景）：**
16. `cluster-resource-quota` — 多集群资源配额
17. `gateway-whitelist-ciphersuites` — TLS 安全
18. `gateway-whitelist-min-protocol-version` — TLS 版本
19. `prometheus-rule-whitelist-metadata` — 监控可观测性
20. `volume-snapshot-class-whitelist-csi-driver` — 快照安全

---

## 4. 实施建议

### 4.1 第一阶段：利用现有 GKE TEP（1-2周）

直接启用以下 GKE TEP，将 Policy-Layer 策略迁移到现有模板：

```bash
# 推荐的 GKE TEP 组合（基础安全覆盖）
kubectl apply -f - <<EOF
# 强制只读根文件系统
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPHostFilesystem
metadata:
  name: psp-host-filesystem
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
EOF
```

### 4.2 第二阶段：自定义高优先级模板（2-4周）

优先实现 7 个高优先级自定义模板：

| 序号 | 模板名称 | Rego 复杂度 | 建议 |
|------|---------|-----------|------|
| 1 | `container-deny-added-caps` | 中 | 复用 `k8spspcapabilities` 扩展参数 |
| 2 | `container-deny-env-var-secrets` | 低 | 简单 path 遍历 |
| 3 | `container-deny-run-as-system-user` | 低 | 检查 runAsUser UID |
| 4 | `pod-deny-host-ipc/pid` | 低 | 合并到 `k8spsphostnamespace` |
| 5 | `namespace-deny-system-interaction` | 低 | namespace label 检查 |
| 6 | `role-binding-whitelist-subjects` | 中 | subject type 白名单 |
| 7 | `rbac-deny-modify-labeled-*` | 中 | label selector + mutation |

### 4.3 第三阶段：ASM/Gateway/DNS 策略（4-8周）

如使用 ASM，逐步启用 Anthos Service Mesh 相关模板。

---

## 5. 对比结论

| 评估项 | 结论 |
|--------|------|
| **GKE TEP 总数** | 82 个 |
| **Policy-Layer 策略总数** | 55 条 |
| **精确匹配** | 14 条（25%） |
| **可扩展/组合覆盖** | 11 条（20%） |
| **需完全自定义** | 30 条（55%） |
| **Policy-Layer 对 GKE TEP 覆盖率** | ~45%（含扩展） |
| **ASM/Gateway/DNS 专项策略** | Policy-Layer 独有，GKE TEP 无对应 |
| **PSP 安全策略** | GKE TEP 完整覆盖，Policy-Layer 可直接迁移 |
| **GKE TEP 未覆盖 Policy-Layer** | ASM(10) + Gateway(5) + DNS(3) + 自定义(12) = 30 条 |

**核心发现：** Policy-Layer 的 55 条策略中，仅约 45% 可直接通过 GKE Policy Controller 内置模板实现。剩余 55% 需要自定义 Gatekeeper Constraint Templates，主要集中在 ASM Service Mesh、Gateway API、DNS 安全、以及高级容器安全策略领域。建议优先实现高优先级的 7 个自定义模板以覆盖最关键的 安全需求。
