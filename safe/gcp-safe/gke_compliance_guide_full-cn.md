- [GKE 合规指南](#gke-合规指南)
  - [证书管理](#证书管理)
    - [GKE-TEP-CERT-0001：证书不应在同一命名空间中使用相同的密钥名称](#gke-tep-cert-0001-证书不应在同一命名空间中使用相同的密钥名称)
  - [容器安全](#容器安全)
    - [GKE-TEP-CON-0001：容器不得添加功能](#gke-tep-con-0001-容器不得添加功能)
    - [GKE-TEP-CON-0002：容器不得允许权限提升](#gke-tep-con-0002-容器不得允许权限提升)
    - [GKE-TEP-CON-0003：镜像不得使用 latest 标签](#gke-tep-con-0003-镜像不得使用-latest-标签)
    - [GKE-TEP-CON-0004：容器不得以特权模式运行](#gke-tep-con-0004-容器不得以特权模式运行)
    - [GKE-TEP-CON-0005：容器必须定义 CPU 和内存请求](#gke-tep-con-0005-容器必须定义-cpu-和内存请求)
    - [GKE-TEP-CON-0006：容器必须以非 root 用户运行](#gke-tep-con-0006-容器必须以非-root-用户运行)
    - [GKE-TEP-CON-0007：镜像必须具有白名单前缀](#gke-tep-con-0007-镜像必须具有白名单前缀)
    - [GKE-TEP-CON-0008：容器必须删除所有功能](#gke-tep-con-0008-容器必须删除所有功能)
    - [GKE-TEP-CON-0008：容器必须使用白名单 AppArmor 配置文件](#gke-tep-con-0008-容器必须使用白名单-apparmor-配置文件)
    - [GKE-TEP-CON-0009：容器必须使用只读根文件系统](#gke-tep-con-0009-容器必须使用只读根文件系统)
    - [GKE-TEP-CON-0010：容器必须使用白名单 seccomp 配置文件](#gke-tep-con-0010-容器必须使用白名单-seccomp-配置文件)
    - [GKE-TEP-CON-0011：容器必须使用 imagePullPolicy Always](#gke-tep-con-0011-容器必须使用-imagepullpolicy-always)
    - [GKE-TEP-CON-0012：容器不得将 Secret 作为环境变量使用](#gke-tep-con-0012-容器不得将-secret-作为环境变量使用)
    - [GKE-TEP-CON-0013：客户容器不得以系统用户身份运行](#gke-tep-con-0013-客户容器不得以系统用户身份运行)
  - [自定义资源定义 (CRDs)](#自定义资源定义-crds)
    - [GKE-TEP-CRD-0001：防止客户管理使用系统组的自定义资源定义](#gke-tep-crd-0001-防止客户管理使用系统组的自定义资源定义)
  - [资源配额](#资源配额)
    - [GKE-TEP-CRQ-0001：对跨所有命名空间的资源总数执行配额限制](#gke-tep-crq-0001-对跨所有命名空间的资源总数执行配额限制)
  - [镜像安全与证明](#镜像安全与证明)
    - [GKE-TEP-CSCS-0001：平台镜像必须具有必需的证明](#gke-tep-cscs-0001-平台镜像必须具有必需的证明)
    - [GKE-TEP-CSCS-0002：客户镜像必须具有必需的证明](#gke-tep-cscs-0002-客户镜像必须具有必需的证明)
  - [DNS 安全](#dns-安全)
    - [GKE-TEP-DNS-0001：DNSEndpoints、Services 和 Gateways 必须使用唯一 DNS 名称](#gke-tep-dns-0001-dnsendpoints-services-和-gateways-必须使用唯一-dns-名称)
    - [GKE-TEP-DNS-0002：DNSEndpoint 和 Service DNS 名称必须具有白名单后缀](#gke-tep-dns-0002-dnsendpoint-和-service-dns-名称必须具有白名单后缀)
    - [GKE-TEP-DNS-0003：DNSEndpoint 和 Service 不得使用为系统保留的 DNS 名称](#gke-tep-dns-0003-dnsendpoint-和-service-不得使用为系统保留的-dns-名称)
    - [GKE-TEP-DNS-0004：DNSEndpoints 必须仅包含有效记录](#gke-tep-dns-0004-dnsendpoints-必须仅包含有效记录)
  - [网关和 Ingress](#网关和-ingress)
    - [GKE-TEP-GATEWAY-0001：Gateway 必须使用白名单 minProtocolVersion](#gke-tep-gateway-0001-gateway-必须使用白名单-minprotocolversion)
    - [GKE-TEP-GATEWAY-0002：Gateway 必须使用白名单密码套件](#gke-tep-gateway-0002-gateway-必须使用白名单密码套件)
    - [GKE-TEP-GATEWAY-0003：Gateway 必须使用 1024 以上的端口](#gke-tep-gateway-0003-gateway-必须使用-1024-以上的端口)
    - [GKE-TEP-GATEWAY-0004：Gateway 必须使用白名单协议](#gke-tep-gateway-0004-gateway-必须使用白名单协议)
    - [GKE-TEP-ING-0004：Ingress 资源不能使用为系统保留的主机](#gke-tep-ing-0004-ingress-资源不能使用为系统保留的主机)
  - [命名空间](#命名空间)
    - [GKE-TEP-NSP-0002：系统命名空间和系统命名空间中的命名空间资源不应由客户管理](#gke-tep-nsp-0002-系统命名空间和系统命名空间中的命名空间资源不应由客户管理)
  - [Pod 安全](#pod-安全)
    - [GKE-TEP-POD-0001：Pods 不得使用主机网络命名空间](#gke-tep-pod-0001-pods-不得使用主机网络命名空间)
    - [GKE-TEP-POD-0002：Pods 不得使用主机 PID 命名空间](#gke-tep-pod-0002-pods-不得使用主机-pid-命名空间)
    - [GKE-TEP-POD-0003：Pods 不得使用主机 IPC 命名空间](#gke-tep-pod-0003-pods-不得使用主机-ipc-命名空间)
    - [GKE-TEP-POD-0005：Pods 不得使用被拒绝的 PriorityClass](#gke-tep-pod-0005-pods-不得使用被拒绝的-priorityclass)
    - [GKE-TEP-POD-0006：Pods 必须使用白名单卷](#gke-tep-pod-0006-pods-必须使用白名单卷)
    - [GKE-TEP-POD-0007：Pods 不得使用 root fsGroup](#gke-tep-pod-0007-pods-不得使用-root-fsgroup)
    - [GKE-TEP-POD-0008：应避免阻止集群缩放的 Pods](#gke-tep-pod-0008-应避免阻止集群缩放的-pods)
  - [优先级类](#优先级类)
    - [GKE-TEP-PRIC-0001：客户不应与系统优先级类交互](#gke-tep-pric-0001-客户不应与系统优先级类交互)
  - [监控与告警](#监控与告警)
    - [GKE-TEP-PR-0001：触发 aibang 告警 API 的 PrometheusRule 规则必须指定有效元数据](#gke-tep-pr-0001-触发-aibang-告警-api-的-prometheusrule-规则必须指定有效元数据)
  - [存储](#存储)
    - [GKE-TEP-PV-0001：PersistentVolumes 必须使用白名单 CSI 驱动程序](#gke-tep-pv-0001-persistentvolumes-必须使用白名单-csi-驱动程序)
    - [GKE-TEP-PV-0003：PersistentVolumes 必须使用唯一的 CSI 卷句柄](#gke-tep-pv-0003-persistentvolumes-必须使用唯一的-csi-卷句柄)
    - [GKE-TEP-PV-0004：PersistentVolumes 不得有对系统命名空间的 claimRef](#gke-tep-pv-0004-persistentvolumes-不得有对系统命名空间的-claimref)
  - [RBAC](#rbac)
    - [GKE-TEP-RBAC-0001：客户创建的 ClusterRoleBindings 和 RoleBindings 必须包含客户主体](#gke-tep-rbac-0001-客户创建的-clusterrolebindings-和-rolebindings-必须包含客户主体)
    - [GKE-TEP-RBAC-0002：如果已存在同名的集群级资源，Flux 不应更新该资源](#gke-tep-rbac-0002-如果已存在同名的集群级资源-flux-不应更新该资源)
    - [GKE-TEP-RBAC-0003：项目团队不应创建、更新或删除任何 ClusterRole 和 ClusterRoleBinding](#gke-tep-rbac-0003-项目团队不应创建更新或删除任何-clusterrole-和-clusterrolebinding)
  - [存储类](#存储类)
    - [GKE-TEP-SC-0002：StorageClass 不得使用 'is-default-class' 注解](#gke-tep-sc-0002-storageclass-不得使用-is-default-class-注解)
    - [GKE-TEP-SC-0003：StorageClasses 必须使用允许的动态卷供应程序](#gke-tep-sc-0003-storageclasses-必须使用允许的动态卷供应程序)
    - [GKE-TEP-SC-0004：StorageClasses 没有 CMEK 加密](#gke-tep-sc-0004-storageclasses-没有-cmek-加密)
  - [系统资源](#系统资源)
    - [GKE-TEP-SRI-0001：系统 StorageClass 和 ClusterIssuer 不应由客户管理](#gke-tep-sri-0001-系统-storageclass-和-clusterissuer-不应由客户管理)
  - [卷快照](#卷快照)
    - [GKE-TEP-VSC-0001：VolumeSnapshotClasses 必须使用白名单 CSI 驱动程序](#gke-tep-vsc-0001-volumesnapshotclasses-必须使用白名单-csi-驱动程序)
  - [Webhooks](#webhooks)
    - [GKE-TEP-WEBH-0001：意外的准入 webhook 配置](#gke-tep-webh-0001-意外的准入-webhook-配置)

# GKE 合规指南

本文档提供了 GKE 安全和合规控制的详细说明，包含每个控制的示例和最佳实践。

## 证书管理

### GKE-TEP-CERT-0001：证书不应在同一命名空间中使用相同的密钥名称

*   **描述**: 此规则防止同一 Kubernetes 命名空间中的多个 `Certificate` 资源引用其 `spec.secretName` 字段中的相同 `Secret` 名称。每个证书应将其生成的 TLS 密钥对存储在唯一密钥中，以避免覆盖和冲突，如果一个证书轮换覆盖了另一个有效证书的密钥，可能导致服务中断。
*   **违规示例 (YAML)**:
    ```yaml
    # certificate-1.yaml
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: my-app-cert-1
      namespace: production
    spec:
      secretName: my-tls-secret # 违规: 相同的 secretName
      dnsNames:
      - my-app.example.com
      issuerRef:
        name: letsencrypt-prod
        kind: ClusterIssuer

    # certificate-2.yaml
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: my-app-cert-2
      namespace: production
    spec:
      secretName: my-tls-secret # 违规: 相同的 secretName
      dnsNames:
      - my-other-app.example.com
      issuerRef:
        name: letsencrypt-prod
        kind: ClusterIssuer
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    # certificate-1.yaml
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: my-app-cert-1
      namespace: production
    spec:
      secretName: my-app-tls-secret # 最佳实践: 唯一的 secretName
      dnsNames:
      - my-app.example.com
      issuerRef:
        name: letsencrypt-prod
        kind: ClusterIssuer

    # certificate-2.yaml
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: my-app-cert-2
      namespace: production
    spec:
      secretName: my-other-app-tls-secret # 最佳实践: 唯一的 secretName
      dnsNames:
      - my-other-app.example.com
      issuerRef:
        name: letsencrypt-prod
        kind: ClusterIssuer
    ```
*   **控制/执行**: 这可以使用 OPA Gatekeeper 或 Kyverno 等策略引擎来执行。验证策略将检查所有 `Certificate` 资源，并确保对于任何给定的命名空间，`spec.secretName` 值在所有证书中都是唯一的。
*   **验证**: 使用以下命令检查特定命名空间中证书的重复密钥名称:
    ```bash
    kubectl get certificates -n <namespace> -o json | jq -r '.items[] | select(.spec.secretName) | .metadata.name + " -> " + .spec.secretName' | sort | uniq -d
    ```
    此命令将列出指定命名空间中证书使用的任何重复密钥名称。

---


## 容器安全

### GKE-TEP-CON-0001：容器不得添加功能

*   **描述**: 容器定义中的 `securityContext.capabilities.add` 字段应为空或未定义。添加 Linux 功能可以授予容器通常保留给 root 用户的特权，如果容器被入侵，会增加安全风险。遵循最小权限原则，不应授予容器不需要的功能。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-added-caps
    spec:
      containers:
      - name: main-container
        image: nginx
        securityContext:
          capabilities:
            add: ["NET_ADMIN", "SYS_TIME"] # 违规: 添加功能
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-added-caps
    spec:
      containers:
      - name: main-container
        image: nginx
        securityContext:
          capabilities:
            drop: ["ALL"] # 最佳实践: 删除所有功能，仅在绝对必要时添加特定功能
    ```
*   **控制/执行**: 使用 Pod 安全策略 (PSP - 已弃用) 或现代等效项，如 OPA Gatekeeper、Kyverno 或 GKE 的 Pod 安全准入控制器。策略应禁止 `securityContext.capabilities.add` 中的任何值。
*   **验证**: 使用以下命令检查添加功能的容器:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.capabilities.add) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) is adding capabilities: \(.securityContext.capabilities.add[])"'
    ```

### GKE-TEP-CON-0002：容器不得允许权限提升

*   **描述**: `securityContext.allowPrivilegeEscalation` 字段应设置为 `false`。这可以防止容器获得比其父进程更多的权限。例如，具有 `setuid` 或 `setgid` 二进制文件的进程可能会提升权限，这是重大安全风险。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-privilege-escalation
    spec:
      containers:
      - name: main-container
        image: nginx
        securityContext:
          allowPrivilegeEscalation: true # 违规: 允许权限提升
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-privilege-escalation
    spec:
      containers:
      - name: main-container
        image: nginx
        securityContext:
          allowPrivilegeEscalation: false # 最佳实践: 禁止权限提升
    ```
*   **控制/执行**: 这是 Pod 安全准入控制器 (PSA) 中的基本策略。也可以使用 OPA Gatekeeper 或 Kyverno 创建要求 `securityContext.allowPrivilegeEscalation` 为 `false` 的策略。
*   **验证**: 使用以下命令检查允许权限提升的容器:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.allowPrivilegeEscalation == true) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) allows privilege escalation"'
    ```

### GKE-TEP-CON-0003：镜像不得使用 latest 标签

*   **描述**: 容器镜像应使用特定版本标签或摘要进行定义。不建议使用 `:latest` 标签，因为它可能导致不可预测的行为，并且难以跟踪正在运行的镜像版本。这会使回滚和安全审核变得复杂。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-latest-tag
    spec:
      containers:
      - name: main-container
        image: nginx:latest # 违规: 使用 latest 标签
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-specific-tag
    spec:
      containers:
      - name: main-container
        image: nginx:1.21.6 # 最佳实践: 使用特定版本标签
    # --- OR ---
    # spec:
    #   containers:
    #   - name: main-container
    #     image: nginx@sha256:2f2974912acde9413149af97825206192931484556e3b50c4e1def6c65293678 # 最佳实践: 使用摘要
    ```
*   **控制/执行**: 使用准入控制器如 OPA Gatekeeper 或 Kyverno 创建拒绝使用 `:latest` 标签或不包含摘要的任何容器镜像的策略。
*   **验证**: 使用以下命令检查使用 `:latest` 标签的容器:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.image | endswith(":latest")) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) uses latest tag: \(.image)"'
    ```

### GKE-TEP-CON-0004：容器不得以特权模式运行

*   **描述**: `securityContext.privileged` 字段必须设置为 `false`。特权容器可以访问主机上的所有设备并可以绕过许多安全机制。以特权模式运行容器是重大安全风险，除非绝对必要，否则应避免。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: privileged-pod
    spec:
      containers:
      - name: main-container
        image: nginx
        securityContext:
          privileged: true # 违规: 容器以特权模式运行
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: non-privileged-pod
    spec:
      containers:
      - name: main-container
        image: nginx
        securityContext:
          privileged: false # 最佳实践: 容器不以特权模式运行
    ```
*   **控制/执行**: 这是 Pod 安全准入控制器 (PSA) 中的基本策略。OPA Gatekeeper 或 Kyverno 也可用于执行需要 `securityContext.privileged` 为 `false` 的策略。
*   **验证**: 使用以下命令检查特权容器:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.privileged == true) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) is privileged"'
    ```

### GKE-TEP-CON-0005：容器必须定义 CPU 和内存请求

*   **描述**: 所有容器都应在 `resources` 块中定义 CPU 和内存 `requests`。设置资源请求允许 Kubernetes 调度器就 Pod 放置位置做出智能决策，防止资源争用并确保应用程序拥有可靠运行所需的资源。同样建议设置 `limits` 以防止单个容器消耗节点上的所有可用资源。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-no-requests
    spec:
      containers:
      - name: main-container
        image: nginx
        # 违规: 未定义资源请求或限制
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-requests
    spec:
      containers:
      - name: main-container
        image: nginx
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
    ```
*   **控制/执行**: 这可以使用 Kubernetes 中的 `LimitRange` 对象来执行，它可以为命名空间中的容器设置默认资源请求。对于更严格的控制，可以使用 OPA Gatekeeper 或 Kyverno 创建要求所有容器显式定义 `cpu` 和 `memory` 的 `resources.requests` 的策略。
*   **验证**: 使用以下命令检查没有 CPU 和内存请求的容器:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select((.resources.requests.cpu == null) or (.resources.requests.memory == null)) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) is missing CPU or memory requests"'
    ```

### GKE-TEP-CON-0006：容器必须以非 root 用户运行

*   **描述**: `securityContext.runAsNonRoot` 字段应设置为 `true`，并应定义特定的 `runAsUser`。以非 root 用户运行容器是关键的安全最佳实践。如果攻击者获得了以 root 身份运行的容器的控制权，他们可能会拥有对底层主机的 root 访问权限。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-running-as-root
    spec:
      containers:
      - name: main-container
        image: nginx
        # 违规: 容器可能默认以 root 身份运行
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-running-as-non-root
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 3000
        fsGroup: 2000
      containers:
      - name: main-container
        image: nginx
        securityContext:
          runAsNonRoot: true # 最佳实践: 强制非 root 用户
    ```
*   **控制/执行**: 这是 Pod 安全准入控制器 (PSA) 中的基本策略。OPA Gatekeeper 和 Kyverno 也可以通过要求 `securityContext.runAsNonRoot` 为 `true` 并可选地要求 `runAsUser` 在特定范围内来执行此策略。
*   **验证**: 使用以下命令检查以 root 身份运行的容器 (或未指定 runAsNonRoot):
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.runAsNonRoot == false or .securityContext.runAsUser == 0 or (.securityContext.runAsNonRoot == null and .securityContext.runAsUser == null)) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) is running as root or without runAsNonRoot specified"'
    ```

### GKE-TEP-CON-0007：镜像必须具有白名单前缀

*   **描述**: 容器镜像应仅从已批准的可信存储库中拉取。这通常通过要求所有镜像路径以白名单前缀 (例如 `gcr.io/my-project/`) 开头来执行。这可以防止使用来自 Docker Hub 等公共存储库的不可信或未经扫描的镜像，降低运行易受攻击或恶意代码的风险。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-untrusted-image
    spec:
      containers:
      - name: main-container
        image: random-user/malicious-image:1.0 # 违规: 来自非白名单存储库的镜像
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-trusted-image
    spec:
      containers:
      - name: main-container
        image: gcr.io/my-project/my-app:1.2.3 # 最佳实践: 来自白名单存储库的镜像
    ```
*   **控制/执行**: 使用准入控制器如 OPA Gatekeeper 或 Kyverno 验证所有容器的 `image` 字段。策略应将镜像名称与已批准存储库前缀列表进行匹配。
*   **验证**: 使用以下命令检查不匹配白名单前缀的容器镜像 (将 `gcr.io/my-project/` 替换为实际的白名单):
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.image | startswith("gcr.io/my-project/") | not) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) uses non-whitelisted image: \(.image)"'
    ```

### GKE-TEP-CON-0008：容器必须删除所有功能

*   **描述**: `securityContext.capabilities.drop` 字段应设置为 `["ALL"]`。Linux 功能授予进程特定权限。默认情况下，容器被授予一组功能。为遵循最小权限原则，应删除所有默认功能，仅在必要时将应用程序所需的具体功能添加回来。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-default-caps
    spec:
      containers:
      - name: main-container
        image: nginx
        # 违规: 默认功能未删除
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-dropped-caps
    spec:
      containers:
      - name: main-container
        image: nginx
        securityContext:
          capabilities:
            drop: ["ALL"] # 最佳实践: 删除所有功能
            # 仅添加所需功能，例如 NET_BIND_SERVICE 用于绑定到 < 1024 的端口
            # add: ["NET_BIND_SERVICE"]
    ```
*   **控制/执行**: 这可以通过 OPA Gatekeeper 或 Kyverno 创建要求 `securityContext.capabilities.drop` 包含值 `ALL` 的策略来执行。
*   **验证**: 使用以下命令检查未删除所有功能的容器:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.capabilities.drop == null or (.securityContext.capabilities.drop | index("ALL") | not)) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) does not drop all capabilities"'
    ```

### GKE-TEP-CON-0008：容器必须使用白名单 AppArmor 配置文件

*   **描述**: AppArmor 是一个 Linux 安全模块，可以限制程序的功能。如果在 GKE 节点上启用 AppArmor，应将 AppArmor 配置文件应用于容器以进一步沙盒化它们。配置文件应是白名单配置文件集之一，通常是 `runtime/default` 或为应用程序设计的自定义配置文件。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-apparmor
      # 违规: 未指定 AppArmor 配置文件
    spec:
      containers:
      - name: main-container
        image: nginx
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-apparmor
      annotations:
        container.apparmor.security.beta.kubernetes.io/main-container: runtime/default # 最佳实践
    spec:
      containers:
      - name: main-container
        image: nginx
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建检查 Pod 上 AppArmor 注解存在和值的策略。策略应确保注解存在且其值是白名单配置文件之一。
*   **验证**: 使用以下命令检查没有 AppArmor 配置文件或使用非白名单配置文件的 Pod:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.metadata.annotations == null or (.metadata.annotations | has("container.apparmor.security.beta.kubernetes.io/") | not) or (.metadata.annotations | to_entries[] | select(.key | startswith("container.apparmor.security.beta.kubernetes.io/")) | .value | . == "unconfined" or startswith("localhost/"))) | "\(.metadata.name) in namespace \(.metadata.namespace) does not use a whitelisted AppArmor profile"'
    ```

### GKE-TEP-CON-0009：容器必须使用只读根文件系统

*   **描述**: `securityContext.readOnlyRootFilesystem` 字段应设置为 `true`。这可以防止容器写入其根文件系统，从而缓解各种攻击。如果应用程序需要写入数据，应使用专用卷挂载 (`tmpfs` 用于临时数据或持久卷用于持久数据)。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-writable-rootfs
    spec:
      containers:
      - name: main-container
        image: nginx
        # 违规: 根文件系统默认可写
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-readonly-rootfs
    spec:
      containers:
      - name: main-container
        image: nginx
        securityContext:
          readOnlyRootFilesystem: true # 最佳实践
        volumeMounts:
        - name: tmp-data
          mountPath: /var/cache/nginx
      volumes:
      - name: tmp-data
        emptyDir: {}
    ```
*   **控制/执行**: 这是 Pod 安全准入控制器 (PSA) 中的基本策略。也可以使用 OPA Gatekeeper 或 Kyverno 要求 `securityContext.readOnlyRootFilesystem` 为 `true` 来执行此策略。
*   **验证**: 使用以下命令检查根文件系统可写的容器:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.readOnlyRootFilesystem != true) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) has a writable root filesystem"'
    ```

### GKE-TEP-CON-0010：容器必须使用白名单 seccomp 配置文件

*   **描述**: Seccomp (安全计算模式) 是一个 Linux 内核功能，限制应用程序可以进行的系统调用。GKE 节点使用默认 seccomp 配置文件运行。将 seccomp 配置文件应用于容器，例如 `RuntimeDefault` 配置文件，是强有力的安全实践。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-seccomp
    spec:
      containers:
      - name: main-container
        image: nginx
      # 违规: 未指定 seccomp 配置文件
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-seccomp
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault # 最佳实践
      containers:
      - name: main-container
        image: nginx
    ```
*   **控制/执行**: 这是 Pod 安全准入控制器 (PSA) 中的基本策略。OPA Gatekeeper 或 Kyverno 可用于执行要求 `securityContext.seccompProfile.type` 为 `RuntimeDefault` 或其他白名单配置文件的策略。

*   **验证**: 使用以下命令检查没有使用白名单 seccomp 配置文件的容器:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.seccompProfile == null or (.securityContext.seccompProfile.type != "RuntimeDefault" and .securityContext.seccompProfile.type != "Localhost")) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) does not use a whitelisted seccomp profile"'
    ```

### GKE-TEP-CON-0011：容器必须使用 imagePullPolicy Always

*   **描述**: 容器的 `imagePullPolicy` 应设置为 `Always`。这确保 kubelet 在每次 Pod 启动时都拉取镜像，这保证了您运行的是预期版本，并且应用了任何安全更新。它还有助于验证镜像在存储库中是否仍然可用。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-default-pull-policy
    spec:
      containers:
      - name: main-container
        image: nginx:1.21.6
        imagePullPolicy: IfNotPresent # 违规 (或省略，默认为 IfNotPresent)
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-always-pull-policy
    spec:
      containers:
      - name: main-container
        image: nginx:1.21.6
        imagePullPolicy: Always # 最佳实践
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建要求 `imagePullPolicy` 设置为 `Always` 的策略。
*   **验证**: 使用以下命令检查未使用 imagePullPolicy Always 的容器:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.imagePullPolicy == null or .imagePullPolicy == "IfNotPresent" or .imagePullPolicy == "Never") | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) does not use imagePullPolicy Always: \(.imagePullPolicy // "default to IfNotPresent")"'
    ```

### GKE-TEP-CON-0012：容器不得将 Secret 作为环境变量使用

*   **描述**: 应将 Secret 挂载为容器中的文件，而不是作为环境变量公开。环境变量可能通过日志、shell 历史记录或其他方式意外暴露。将 Secret 挂载为内存 `tmpfs` 卷是最安全的方法。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-secret-as-env
    spec:
      containers:
      - name: main-container
        image: my-app
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password # 违规
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-secret-as-volume
    spec:
      containers:
      - name: main-container
        image: my-app
        volumeMounts:
        - name: db-creds-volume
          mountPath: "/etc/secrets"
          readOnly: true
      volumes:
      - name: db-creds-volume
        secret:
          secretName: db-credentials
    ```
*   **控制/执行**: OPA Gatekeeper 或 Kyverno 可用于创建禁止使用 `env.valueFrom.secretKeyRef` 的策略。
*   **验证**: 使用以下命令检查将 Secret 作为环境变量使用的容器:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.env[]? | select(.valueFrom.secretKeyRef)) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) consumes secrets as environment variables"'
    ```

### GKE-TEP-CON-0013：客户容器不得以系统用户身份运行

*   **描述**: 容器不应使用用户 ID (UID) 0 (root) 或通常保留给系统账户的其他低编号 UID 运行。应使用高 UID (例如，高于 1000)。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-running-as-system-user
    spec:
      securityContext:
        runAsUser: 0 # 违规
      containers:
      - name: main-container
        image: my-app
    ```
*   **最佳实践 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-running-as-non-system-user
    spec:
      securityContext:
        runAsUser: 1001 # 最佳实践
        runAsGroup: 3001
      containers:
      - name: main-container
        image: my-app
    ```
*   **控制/执行**: 这可以通过 OPA Gatekeeper 或 Kyverno 创建要求 `securityContext.runAsUser` 高于某个阈值 (例如，> 1000) 的策略来执行。
*   **验证**: 使用以下命令检查以 root 或低 UID 运行的容器:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.runAsUser == null or .securityContext.runAsUser <= 1000) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) runs with low UID: \(.securityContext.runAsUser // "not specified, defaults to image user")"'
    ```
---
## 自定义资源定义 (CRDs)

### GKE-TEP-CRD-0001：防止客户管理使用系统组的自定义资源定义

*   **描述**: 此规则防止非管理员用户创建、更新或删除属于系统级 API 组 (例如 `*.k8s.io`、`*.istio.io`) 的自定义资源定义 (CRD)。允许修改系统 CRD 可能导致集群不稳定或安全漏洞。
*   **违规示例**: 没有集群管理员权限的用户尝试修补受保护 API 组中的 CRD。
    ```bash
    kubectl patch crd gateways.networking.istio.io --type merge -p '{"spec":{"group":"my-rogue-group"}}'
    ```
*   **最佳实践**: 只有集群管理员应具有管理 CRD 的 RBAC 权限。应用程序团队不应被授予对 `customresourcedefinitions` 资源的 `create`、`update` 或 `delete` 权限。
*   **控制/执行**: 使用 Kubernetes RBAC 限制对 CRD 的权限。OPA Gatekeeper 还可用于创建基于用户身份和 CRD 的 API 组拒绝对 CRD 进行更改的策略。
*   **验证**: 使用以下命令列出所有 CRD 并验证哪些可能属于受保护的系统组:
    ```bash
    kubectl get crds -o json | jq -r '.items[] | select(.spec.group | test("k8s.io$|istio.io$|kiali.io$")) | "\(.metadata.name) belongs to system group: \(.spec.group)"'
    ```

---
## 资源配额

### GKE-TEP-CRQ-0001：对跨所有命名空间的资源总数执行配额限制

*   **描述**: 此规则执行集群范围的资源配额。`ResourceQuota` 对象是命名空间的，但可以实现策略以限制整个集群中可创建的资源 (如 Pod、服务等) 的总数。这可防止任何单个租户或团队消耗过多的集群资源。
*   **违规示例**: 用户创建新命名空间并部署大量 Pod，超出集群的预期总限制。
*   **最佳实践**: 为每个命名空间定义 `ResourceQuota` 以在粒度级别限制资源。对于集群范围的限制，可以使用自定义控制器或具有 OPA Gatekeeper 的准入 webhook 来跨命名空间跟踪资源消耗并执行总限制。
    ```yaml
    # 命名空间配额的示例
    apiVersion: v1
    kind: ResourceQuota
    metadata:
      name: namespace-quota
      namespace: team-a
    spec:
      hard:
        pods: "10"
        services: "5"
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建获取所有命名空间中某种资源的策略，如果新资源的总数超过预定义限制则拒绝创建新资源。
*   **验证**: 使用以下命令检查跨所有命名空间的资源配额使用情况:
    ```bash
    kubectl get resourcequotas --all-namespaces -o json | jq -r '.items[] | "\(.metadata.namespace):\(.metadata.name) - \(.status.hard // {} | to_entries[] | "\(.key)=\(.value)")"'
    ```

---
## 镜像安全与证明

### GKE-TEP-CSCS-0001：平台镜像必须具有必需的证明

*   **描述**: 此规则确保用于核心平台组件的所有容器镜像在部署前都已通过受信任的机构成功扫描和证明。这通常使用 Google 的二进制授权等系统完成。
*   **违规示例**: 管理员尝试使用未经安全团队证明的镜像部署 Ingress 控制器的新版本。
*   **最佳实践**: 在 GKE 集群上启用二进制授权并配置策略，要求所有匹配特定模式 (例如 `gcr.io/platform-project/*`) 的镜像具有来自特定项目和证明者的证明。
*   **控制/执行**: 由 Google 的二进制授权服务直接执行。准入控制器将阻止使用没有所需证明的镜像的任何 Pod。

*   **验证**: 使用以下命令检查二进制授权策略:
    ```bash
    gcloud container binauthz policy export
    ```

### GKE-TEP-CSCS-0002：客户镜像必须具有必需的证明

*   **描述**: 与平台镜像规则类似，此控制要求所有由用户部署的应用程序镜像具有必要的安全证明。这通常意味着镜像已通过漏洞扫描、代码分析和其他质量网关。
*   **违规示例**: 开发人员尝试使用在本地构建并推送到存储库但从未扫描漏洞的镜像部署应用程序，因此缺少 "vulnerability-scan-passed" 证明。
*   **最佳实践**: 将自动扫描和证明集成到 CI/CD 管道中。例如，成功构建后，镜像被推送到 Artifact Registry，扫描漏洞，如果通过，则证明者签署镜像。
*   **控制/执行**: 由 Google 的二进制授权执行。策略将配置为要求所有客户拥有的镜像存储库都具有证明。
*   **验证**: 使用以下命令检查 Pod 是否使用具有所需证明的镜像:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.containers[]) | "\(.metadata.name) in namespace \(.metadata.namespace) uses image: \(.spec.containers[].image)"'
    ```

---
## DNS 安全

### GKE-TEP-DNS-0001：DNSEndpoints、Services 和 Gateways 必须使用唯一 DNS 名称

*   **描述**: 此规则防止多个资源声明相同的 DNS 主机名，这将导致流量路由冲突。例如，两个不同的 Istio `Gateway` 资源不能指定相同的主机。
*   **违规示例 (YAML)**:
    ```yaml
    # gateway-1.yaml
    apiVersion: networking.istio.io/v1alpha3
    kind: Gateway
    metadata:
      name: gateway-one
    spec:
      selector:
        istio: ingressgateway
      servers:
      - port:
          number: 80
        hosts:
        - "my-app.example.com" # 违规

    # gateway-2.yaml
    apiVersion: networking.istio.io/v1alpha3
    kind: Gateway
    metadata:
      name: gateway-two
    spec:
      selector:
        istio: ingressgateway
      servers:
      - port:
          number: 80
        hosts:
        - "my-app.example.com" # 违规
    ```
*   **最佳实践**: 确保每个 DNS 名称在所有相关资源中都是唯一的。使用清晰的命名约定和 DNS 的集中管理以避免冲突。
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建缓存 `Services`、`Gateways` 和 `DNSEndpoints` 使用的主机名的策略，如果新资源的主机名已在使用则拒绝创建。
*   **验证**: 使用以下命令检查服务、网关和 DNSEndpoints 中的重复 DNS 名称:
    ```bash
    # 检查服务
    kubectl get services --all-namespaces -o json | jq -r '.items[] | select(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname") | "\(.metadata.namespace):\(.metadata.name) -> \(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname")"'
    # 检查 Istio 网关
    kubectl get gateways.networking.istio.io --all-namespaces -o json | jq -r '.items[].spec.servers[].hosts[]? | "\(.metadata.namespace):\(.metadata.name) -> \(.)"'
    # 检查 DNSEndpoints
    kubectl get dnsendpoints.externaldns.k8s.io --all-namespaces -o json | jq -r '.items[].spec.endpoints[].dnsName? | "\(.metadata.namespace):\(.metadata.name) -> \(.)"'
    ```

### GKE-TEP-DNS-0002：DNSEndpoint 和 Service DNS 名称必须具有白名单后缀

*   **描述**: 此规则要求为服务创建的所有 DNS 名称都具有已批准的域后缀 (例如 `.prod.gcp.example.com`)。这可防止团队创建任意公共 DNS 名称，并确保它们都在组织的适当域结构下进行管理。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: my-service
      annotations:
        external-dns.alpha.kubernetes.io/hostname: my-app.random-domain.com # 违规
    ```
*   **最佳实践**: 配置服务使用白名单域后缀。
    ```yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: my-service
      annotations:
        external-dns.alpha.kubernetes.io/hostname: my-app.prod.gcp.example.com # 最佳实践
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建针对允许后缀列表验证 `external-dns.alpha.kubernetes.io/hostname` 注解 (或其他相关字段) 的策略。
*   **验证**: 使用以下命令检查不具有白名单后缀的 DNS 名称 (将 `.example.com` 替换为实际域):
    ```bash
    kubectl get services --all-namespaces -o json | jq -r '.items[] | select(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname") | select(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname" | endswith(".example.com") | not) | "\(.metadata.namespace):\(.metadata.name) has non-whitelisted DNS: \(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname")"'
    ```

### GKE-TEP-DNS-0003：DNSEndpoint 和 Service 不得使用为系统保留的 DNS 名称

*   **描述**: 此规则防止应用程序团队使用为 Kubernetes 控制平面或其他系统组件保留的 DNS 名称 (例如，`kubernetes.default.svc.cluster.local`)。
*   **违规示例**: 用户尝试创建将与内部系统 DNS 名称冲突的服务。
*   **最佳实践**: 向用户教育保留的 DNS 名称。控制应阻止任何尝试使用保留名称的尝试。
*   **控制/执行**: OPA Gatekeeper 或 Kyverno 可用于创建拒绝任何尝试使用保留名称列表中主机名的资源的策略。
*   **验证**: 使用以下命令检查使用保留 DNS 名称的服务 (替换为实际保留名称):
    ```bash
    kubectl get services --all-namespaces -o json | jq -r '.items[] | select(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname") | select(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname" | test("kubernetes.default|svc.cluster.local")) | "\(.metadata.namespace):\(.metadata.name) uses reserved DNS: \(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname")"'
    ```

### GKE-TEP-DNS-0004：DNSEndpoints 必须仅包含有效记录

*   **描述**: 此规则确保 `DNSEndpoint` 自定义资源包含格式正确的有效 DNS 记录。这可能包括对有效记录类型 (A、CNAME 等)、格式正确的目标和合理 TTL 的检查。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: externaldns.k8s.io/v1alpha1
    kind: DNSEndpoint
    metadata:
      name: my-dns-endpoint
    spec:
      endpoints:
      - dnsName: my-app.example.com
        recordType: "INVALID" # 违规
        targets:
        - "1.2.3.4"
    ```
*   **最佳实践**: 确保所有 `DNSEndpoint` 资源都使用符合 DNS 规范的有效记录类型和目标创建。
*   **控制/执行**: 使用 ExternalDNS 附带的验证 webhook，或使用 OPA Gatekeeper 或 Kyverno 创建自定义策略来验证 `DNSEndpoint` 资源中的字段。
*   **验证**: 使用以下命令检查具有无效记录类型的 DNSEndpoints:
    ```bash
    kubectl get dnsendpoints.externaldns.k8s.io --all-namespaces -o json | jq -r '.items[].spec.endpoints[] | select(.recordType and (.recordType | test("INVALID|^$"))) | "\(.metadata.namespace):\(.metadata.name) has invalid DNS record type: \(.recordType)"'
    ```
---
## 网关和 Ingress

### GKE-TEP-GATEWAY-0001：Gateway 必须使用白名单 minProtocolVersion

*   **描述**: 此规则强制对 Ingress 流量使用强大、现代的 TLS 版本。Istio `Gateway` 资源应配置为最小 TLS 协议版本 `TLSv1_2` 或更高版本，以保护免受 SSLv3 和 TLS 1.0/1.1 等旧协议中的已知漏洞。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: networking.istio.io/v1alpha3
    kind: Gateway
    metadata:
      name: my-gateway
    spec:
      selector:
        istio: ingressgateway
      servers:
      - port:
          number: 443
          name: https
          protocol: HTTPS
        tls:
          mode: SIMPLE
          credentialName: my-tls-cert
          minProtocolVersion: TLSv1_1 # 违规
        hosts:
        - my-app.example.com
    ```
*   **最佳实践**:
    ```yaml
    apiVersion: networking.istio.io/v1alpha3
    kind: Gateway
    metadata:
      name: my-gateway
    spec:
      selector:
        istio: ingressgateway
      servers:
      - port:
          number: 443
          name: https
          protocol: HTTPS
        tls:
          mode: SIMPLE
          credentialName: my-tls-cert
          minProtocolVersion: TLSv1_2 # 最佳实践
        hosts:
        - my-app.example.com
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建拒绝 `tls.minProtocolVersion` 未设置为已批准值的 `Gateway` 资源的策略。
*   **验证**: 使用以下命令检查使用非批准 TLS 协议版本的网关:
    ```bash
    kubectl get gateways.networking.istio.io --all-namespaces -o json | jq -r '.items[].spec.servers[] | select(.tls and (.tls.minProtocolVersion | test("TLSv1_0|SSL|TLSv1_1"))) | "\(.metadata.namespace):\(.metadata.name) uses non-approved TLS version: \(.tls.minProtocolVersion)"'
    ```

### GKE-TEP-GATEWAY-0002：Gateway 必须使用白名单密码套件

*   **描述**: 为增强 TLS 安全性，此规则要求 Istio `Gateway` 资源使用特定的强密码套件列表。这可防止使用可能被攻击者利用的弱或受损密码。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: networking.istio.io/v1alpha3
    kind: Gateway
    metadata:
      name: my-gateway
    spec:
      selector:
        istio: ingressgateway
      servers:
      - port:
          number: 443
        hosts:
        - my-app.example.com
        tls:
          mode: SIMPLE
          credentialName: my-tls-cert
          cipherSuites: # 违规: 包含弱密码
          - "ECDHE-RSA-WITH-3DES-EDE-CBC-SHA"
    ```
*   **最佳实践**: 指定强的推荐密码套件列表。
    ```yaml
    apiVersion: networking.istio.io/v1alpha3
    kind: Gateway
    metadata:
      name: my-gateway
    spec:
      selector:
        istio: ingressgateway
      servers:
      - port:
          number: 443
        hosts:
        - my-app.example.com
        tls:
          mode: SIMPLE
          credentialName: my-tls-cert
          cipherSuites: # 最佳实践
          - "ECDHE-ECDSA-AES256-GCM-SHA384"
          - "ECDHE-RSA-AES256-GCM-SHA384"
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建针对已批准密码套件集验证 `tls.cipherSuites` 列表的策略。
*   **验证**: 使用以下命令检查使用非批准密码套件的网关 (替换为实际批准的密码):
    ```bash
    kubectl get gateways.networking.istio.io --all-namespaces -o json | jq -r '.items[].spec.servers[] | select(.tls.cipherSuites) | .tls.cipherSuites[] | select(test("3DES|RC4|MD5")) | "\(.metadata.namespace):\(.metadata.name) uses weak cipher suite: \(.)"'
    ```

### GKE-TEP-GATEWAY-0003：Gateway 必须使用 1024 以上的端口

*   **描述**: 此规则特定于网关进程不以 root 身份运行的环境。它要求 `Gateway` 资源侦听非特权端口 (大于 1024)。这是一种纵深防御措施。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: networking.istio.io/v1alpha3
    kind: Gateway
    metadata:
      name: my-gateway
    spec:
      selector:
        istio: ingressgateway
      servers:
      - port:
          number: 80 # 违规 (如果网关进程为非 root)
          name: http
          protocol: HTTP
        hosts:
        - my-app.example.com
    ```
*   **最佳实践**: 配置网关侦听非特权端口。在实践中，Istio 入口网关服务通常从负载均衡器上的特权端口 (例如，443) 映射到 Pod 上的非特权端口。
    ```yaml
    apiVersion: networking.istio.io/v1alpha3
    kind: Gateway
    metadata:
      name: my-gateway
    spec:
      selector:
        istio: ingressgateway
      servers:
      - port:
          number: 8080 # 最佳实践
          name: http
          protocol: HTTP
        hosts:
        - my-app.example.com
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建拒绝端口小于或等于 1024 的 `Gateway` 资源的策略。
*   **验证**: 使用以下命令检查使用特权端口 (1024 或以下) 的网关:
    ```bash
    kubectl get gateways.networking.istio.io --all-namespaces -o json | jq -r '.items[].spec.servers[] | select(.port.number <= 1024) | "\(.metadata.namespace):\(.metadata.name) uses privileged port: \(.port.number)"'
    ```

### GKE-TEP-GATEWAY-0004：Gateway 必须使用白名单协议

*   **描述**: 此规则确保 `Gateway` 资源仅使用已批准的协议。通常，这意味着允许 `HTTP`、`HTTPS` 和 `GRPC`，而拒绝其他协议，除非明确批准。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: networking.istio.io/v1alpha3
    kind: Gateway
    metadata:
      name: my-gateway
    spec:
      selector:
        istio: ingressgateway
      servers:
      - port:
          number: 9000
          name: custom-protocol
          protocol: MONGO # 违规
        hosts:
        - my-app.example.com
    ```
*   **最佳实践**: 仅使用标准、易理解的协议如 HTTPS。
    ```yaml
    apiVersion: networking.istio.io/v1alpha3
    kind: Gateway
    metadata:
      name: my-gateway
    spec:
      selector:
        istio: ingressgateway
      servers:
      - port:
          number: 443
          name: https
          protocol: HTTPS # 最佳实践
        hosts:
        - my-app.example.com
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建针对允许值列表验证 `servers.port.protocol` 字段的策略。
*   **验证**: 使用以下命令检查使用非批准协议的网关 (仅允许 HTTP、HTTPS 和 GRPC):
    ```bash
    kubectl get gateways.networking.istio.io --all-namespaces -o json | jq -r '.items[].spec.servers[] | select(.port.protocol | test("HTTP|HTTPS|GRPC") | not) | "\(.metadata.namespace):\(.metadata.name) uses non-approved protocol: \(.port.protocol)"'
    ```

### GKE-TEP-ING-0004：Ingress 资源不能使用为系统保留的主机

*   **描述**: 这类似于服务的 DNS 规则，但应用于 Kubernetes `Ingress` 资源。它防止用户为为系统保留的主机名创建 Ingress 规则。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: my-ingress
    spec:
      rules:
      - host: "kubernetes.default" # 违规
        http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 80
    ```
*   **最佳实践**: 应用程序 Ingress 资源应仅使用明确分配给它们的主机名。
*   **控制/执行**: OPA Gatekeeper 或 Kyverno 可用于创建拒绝任何尝试使用保留名称列表中主机名的 `Ingress` 的策略。
*   **验证**: 使用以下命令检查使用保留主机名的 Ingress 资源:
    ```bash
    kubectl get ingress --all-namespaces -o json | jq -r '.items[].spec.rules[] | select(.host | test("kubernetes.default|svc.cluster.local")) | "\(.metadata.namespace):\(.metadata.name) uses reserved hostname: \(.host)"'
    ```

---
## 命名空间

### GKE-TEP-NSP-0002：系统命名空间和系统命名空间中的命名空间资源不应由客户管理

*   **描述**: 此规则防止非管理员用户在系统关键命名空间如 `kube-system`、`kube-public`、`gke-system` 和 `istio-system` 中创建、修改或删除资源。修改这些命名空间中的资源可能会损害整个集群的稳定性和安全性。
*   **违规示例**: 具有过于宽泛权限的用户尝试删除 `kube-system` 中的服务。
    ```bash
    kubectl delete service -n kube-system kube-dns
    ```
*   **最佳实践**: 使用 Kubernetes RBAC 对系统命名空间强制执行严格的访问控制。默认情况下，只有集群管理员应具有写入权限。
*   **控制/执行**: 主要通过 RBAC 执行。OPA Gatekeeper 可以通过创建拒绝所有非管理员用户对受保护命名空间中资源进行任何更改的策略来添加另一层防御。
*   **验证**: 使用以下命令列出系统命名空间中可能由客户 (非系统账户) 管理的资源:
    ```bash
    kubectl get all -n kube-system -o json | jq -r '.items[] | "\(.metadata.namespace):\(.metadata.name) - type: \(.kind)"'
    kubectl get all -n kube-public -o json | jq -r '.items[] | "\(.metadata.namespace):\(.metadata.name) - type: \(.kind)"'
    kubectl get all -n gke-system -o json | jq -r '.items[] | "\(.metadata.namespace):\(.metadata.name) - type: \(.kind)"'
    ```
---
## Pod 安全

### GKE-TEP-POD-0001：Pods 不得使用主机网络命名空间

*   **描述**: Pods 不应配置为 `hostNetwork: true`。此设置使 Pod 直接访问节点的网络接口，绕过所有网络策略，并可能拦截流量或与节点上的回环接口服务交互。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-host-network
    spec:
      hostNetwork: true # 违规
      containers:
      - name: main-container
        image: nginx
    ```
*   **最佳实践**: 始终将 `hostNetwork` 保留为 `false` (或省略它，因为 `false` 是默认值)。
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-host-network
    spec:
      hostNetwork: false # 最佳实践
      containers:
      - name: main-container
        image: nginx
    ```
*   **控制/执行**: 这是 Pod 安全准入控制器 (PSA) 中的基本策略。也可以使用 OPA Gatekeeper 或 Kyverno 创建要求 `spec.hostNetwork` 为 `false` 的策略。
*   **验证**: 使用以下命令检查使用主机网络的 Pod:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.hostNetwork == true) | "\(.metadata.namespace):\(.metadata.name) uses host network"'
    ```

### GKE-TEP-POD-0002：Pods 不得使用主机 PID 命名空间

*   **描述**: Pods 不应配置为 `hostPID: true`。这将允许 Pod 内的进程查看节点上运行的所有其他进程，破坏进程隔离并可能暴露敏感信息。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-host-pid
    spec:
      hostPID: true # 违规
      containers:
      - name: main-container
        image: nginx
    ```
*   **最佳实践**: 始终将 `hostPID` 保留为 `false` (或省略它，因为 `false` 是默认值)。
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-host-pid
    spec:
      hostPID: false # 最佳实践
      containers:
      - name: main-container
        image: nginx
    ```
*   **控制/执行**: 这是 Pod 安全准入控制器 (PSA) 中的基本策略。也可以使用 OPA Gatekeeper 或 Kyverno 创建要求 `spec.hostPID` 为 `false` 的策略。
*   **验证**: 使用以下命令检查使用主机 PID 的 Pod:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.hostPID == true) | "\(.metadata.namespace):\(.metadata.name) uses host PID"'
    ```

### GKE-TEP-POD-0003：Pods 不得使用主机 IPC 命名空间

*   **描述**: Pods 不应配置为 `hostIPC: true`。这允许 Pod 共享主机的进程间通信 (IPC) 命名空间，这可能允许它干扰主机上的其他进程。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-host-ipc
    spec:
      hostIPC: true # 违规
      containers:
      - name: main-container
        image: nginx
    ```
*   **最佳实践**: 始终将 `hostIPC` 保留为 `false` (或省略它，因为 `false` 是默认值)。
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-host-ipc
    spec:
      hostIPC: false # 最佳实践
      containers:
      - name: main-container
        image: nginx
    ```
*   **控制/执行**: 这是 Pod 安全准入控制器 (PSA) 中的基本策略。也可以使用 OPA Gatekeeper 或 Kyverno 创建要求 `spec.hostIPC` 为 `false` 的策略。
*   **验证**: 使用以下命令检查使用主机 IPC 的 Pod:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.hostIPC == true) | "\(.metadata.namespace):\(.metadata.name) uses host IPC"'
    ```

### GKE-TEP-POD-0005：Pods 不得使用被拒绝的 PriorityClass

*   **描述**: 此规则防止 Pod 使用被拒绝的 `PriorityClass`。`PriorityClass` 可用于控制 Pod 调度和抢占。某些高优先级类可能保留用于系统关键工作负载，此规则确保应用程序 Pod 不使用它们。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-denied-priority
    spec:
      priorityClassName: system-cluster-critical # 违规
      containers:
      - name: main-container
        image: nginx
    ```
*   **最佳实践**: 使用适合工作负载重要性并已获批准使用的 `PriorityClass`。
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建针对允许 (或拒绝) 优先级类列表验证 `spec.priorityClassName` 的策略。
*   **验证**: 使用以下命令检查使用特定拒绝的 PriorityClass 的 Pod (替换为实际拒绝的类):
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.priorityClassName | test("system-cluster-critical|system-node-critical")) | "\(.metadata.namespace):\(.metadata.name) uses denied PriorityClass: \(.spec.priorityClassName)"'
    ```

### GKE-TEP-POD-0006：Pods 必须使用白名单卷

*   **描述**: Pods 应仅被允许挂载特定的白名单卷类型。例如，您可能希望允许 `configMap`、`secret`、`emptyDir` 和 `persistentVolumeClaim`，但拒绝 `hostPath`，因为它可用于访问底层节点的文件系统。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-hostpath-volume
    spec:
      containers:
      - name: main-container
        image: nginx
        volumeMounts:
        - name: evil-volume
          mountPath: /host-fs
      volumes:
      - name: evil-volume
        hostPath: # 违规
          path: /
          type: Directory
    ```
*   **最佳实践**: 仅使用必要且安全的卷类型，如 `persistentVolumeClaim`。
*   **控制/执行**: 这是 Pod 安全准入控制器 (PSA) 中的基本策略，限制卷类型。OPA Gatekeeper 或 Kyverno 可用于创建更具体的策略，验证 `spec.volumes` 列表中的所有条目是否针对允许的卷类型集。
*   **验证**: 使用以下命令检查使用非白名单卷类型如 hostPath 的 Pod:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | .spec.volumes[] | select(.hostPath) | "\(.metadata.namespace):\(.metadata.name) uses hostPath volume: \(.name)"'
    ```

### GKE-TEP-POD-0007：Pods 不得使用 root fsGroup

*   **描述**: `securityContext.fsGroup` 不应设置为 0 (root 组)。`fsGroup` 是一个特殊补充组，应用于 Pod 中的所有容器并拥有挂载到 Pod 中的任何卷。使用 `fsGroup: 0` 可能向卷授予不必要的 root 级权限。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-root-fsgroup
    spec:
      securityContext:
        fsGroup: 0 # 违规
      containers:
      - name: main-container
        image: nginx
    ```
*   **最佳实践**: 如果需要 `fsGroup`，请使用非零值。
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-non-root-fsgroup
    spec:
      securityContext:
        fsGroup: 1001 # 最佳实践
      containers:
      - name: main-container
        image: nginx
    ```
*   **控制/执行**: OPA Gatekeeper 或 Kyverno 可创建确保 `spec.securityContext.fsGroup` 不是 `0` 的策略。
*   **验证**: 使用以下命令检查使用 root fsGroup 的 Pod:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.securityContext.fsGroup == 0) | "\(.metadata.namespace):\(.metadata.name) uses root fsGroup"'
    ```

### GKE-TEP-POD-0008：应避免阻止集群缩放的 Pods

*   **描述**: Pods 可以配置为阻止集群自动缩放器删除其节点，即使该节点利用率较低。这通常由限制性 `PodDisruptionBudgets` (PDB) 或无法迁移的带有本地存储的 Pod 引起。
*   **违规示例**: 具有注解 `cluster-autoscaler.kubernetes.io/safe-to-evict: "false"` 的 Pod 将阻止缩放。
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-blocking-scaledown
      annotations:
        cluster-autoscaler.kubernetes.io/safe-to-evict: "false" # 违规 (除非有意)
    spec:
      containers:
      - name: main-container
        image: nginx
    ```
*   **最佳实践**: 避免在非绝对必要时使用 `safe-to-evict: "false"` 注解。配置 `PodDisruptionBudgets` 以允许在任何时间关闭至少一个副本。设计应用程序为无状态或能够优雅处理 Pod 终止和重新调度。
*   **控制/执行**: OPA Gatekeeper 或 Kyverno 可用于创建标记或拒绝具有 `safe-to-evict: "false"` 注解的 Pod 的策略。定期监控集群自动缩放器日志也可以帮助识别问题 Pod。
*   **验证**: 使用以下命令检查阻止集群缩放的 Pod:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.metadata.annotations."cluster-autoscaler.kubernetes.io/safe-to-evict" == "false") | "\(.metadata.namespace):\(.metadata.name) blocks scale down"'
    ```
---
## 优先级类

### GKE-TEP-PRIC-0001：客户不应与系统优先级类交互

*   **描述**: 此规则防止非管理员用户创建、删除或更新为系统使用而设计的 `PriorityClass` 资源 (例如，`system-cluster-critical`)。这些对于集群的稳定运行至关重要，修改可能导致不稳定。
*   **违规示例**: 用户尝试删除系统级优先级类。
    ```bash
    kubectl delete priorityclass system-node-critical
    ```
*   **最佳实践**: 使用 RBAC 限制集群管理员对 `PriorityClass` 资源的 `create`、`update` 和 `delete` 权限。
*   **控制/执行**: 主要通过 RBAC 执行。OPA Gatekeeper 可用于进一步限制对具有特定名称的资源的修改。
*   **验证**: 使用以下命令列出系统优先级类:
    ```bash
    kubectl get priorityclass -o json | jq -r '.items[] | select(.metadata.name | test("system-")) | "\(.metadata.name) has value \(.value)"'
    ```

---
## 监控与告警

### GKE-TEP-PR-0001：触发 aibang 告警 API 的 PrometheusRule 规则必须指定有效元数据

*   **描述**: 这是一个非常具体的规则，可能用于内部系统。它要求配置为向特定 API (名为 "aibang 告警 API") 发送告警的任何 `PrometheusRule` 都必须包含作为注解或标签的特定有效元数据集。这确保告警被正确路由、处理和显示在下游告警系统中。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
      name: my-alert-rule
    spec:
      groups:
      - name: my-alerts
        rules:
        - alert: HighErrorRate
          expr: job:request_latency_seconds:mean5m > 0.5
          for: 10m
          labels:
            severity: critical
          annotations:
            # 违规: 缺少 aibang 告警 API 的必需元数据
            summary: "High API error rate detected"
    ```
*   **最佳实践**: 在规则的 `annotations` 部分包含所有必需的元数据。
    ```yaml
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
      name: my-alert-rule
    spec:
      groups:
      - name: my-alerts
        rules:
        - alert: HighErrorRate
          expr: job:request_latency_seconds:mean5m > 0.5
          for: 10m
          labels:
            severity: critical
          annotations:
            summary: "High API error rate detected"
            aibang.alert.routing-key: "team-alpha" # 最佳实践: 包含必需的元数据
            aibang.alert.runbook-url: "https://wiki.example.com/runbooks/high-error-rate"
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建检查 `PrometheusRule` 资源的策略。如果规则配置为针对特定 API，策略将验证必需的注解是否存在且格式正确。
*   **验证**: 使用以下命令检查可能在没有必需元数据的情况下触发 aibang 告警 API 的 PrometheusRules:
    ```bash
    kubectl get prometheusrules --all-namespaces -o json | jq -r '.items[] | select(.spec.groups[].rules[] | select(.annotations | has("summary"))) | "\(.metadata.namespace):\(.metadata.name) has rules with annotations"'
    ```

---
## 存储

### GKE-TEP-PV-0001：PersistentVolumes 必须使用白名单 CSI 驱动程序

*   **描述**: 此规则确保 `PersistentVolume` (PV) 资源使用已批准的容器存储接口 (CSI) 驱动程序进行配置。这可防止使用不安全或不支持的存储后端。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: PersistentVolume
    metadata:
      name: my-pv
    spec:
      capacity:
        storage: 5Gi
      accessModes:
        - ReadWriteOnce
      csi:
        driver: "untrusted.csi.driver.example.com" # 违规
        volumeHandle: "vol-12345"
    ```
*   **最佳实践**: 使用规范的 CSI 驱动程序，如 GKE PD CSI 驱动程序。
    ```yaml
    apiVersion: v1
    kind: PersistentVolume
    metadata:
      name: my-pv
    spec:
      capacity:
        storage: 5Gi
      accessModes:
        - ReadWriteOnce
      csi:
        driver: "pd.csi.storage.gke.io" # 最佳实践
        volumeHandle: "projects/my-gcp-project/zones/us-central1-a/disks/my-disk"
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建针对已批准驱动程序白名单验证 `spec.csi.driver` 字段的策略。
*   **验证**: 使用以下命令检查使用非白名单 CSI 驱动程序的 PersistentVolumes (替换为实际批准的驱动程序):
    ```bash
    kubectl get pv -o json | jq -r '.items[] | select(.spec.csi and (.spec.csi.driver | test("pd.csi.storage.gke.io") | not)) | "\(.metadata.name) uses non-approved CSI driver: \(.spec.csi.driver)"'
    ```

### GKE-TEP-PV-0003：PersistentVolumes 必须使用唯一的 CSI 卷句柄

*   **描述**: 此规则确保没有两个 `PersistentVolume` 资源指向相同的底层存储卷。每个 PV 的唯一 `volumeHandle` 可防止冲突和数据损坏，如果多个 PV 尝试管理同一磁盘可能会发生这种情况。
*   **违规示例**: 创建了两个引用同一 GCE 持久磁盘的 PV。
*   **最佳实践**: 每个 `PersistentVolume` 必须在集群内具有唯一的 `volumeHandle`。使用 `StorageClass` 的动态供应时，这会自动处理。
*   **控制/执行**: OPA Gatekeeper 或自定义准入控制器可用于缓存所有现有 PV 的 `volumeHandle`，如果新 PV 的句柄已在使用则拒绝其创建。
*   **验证**: 使用以下命令检查 PersistentVolumes 中的重复卷句柄:
    ```bash
    kubectl get pv -o json | jq -r '.items[] | select(.spec.csi) | .spec.csi.volumeHandle' | sort | uniq -d
    ```

### GKE-TEP-PV-0004：PersistentVolumes 不得有对系统命名空间的 claimRef

*   **描述**: 此规则防止 `PersistentVolume` 绑定到系统命名空间 (例如 `kube-system`) 中的 `PersistentVolumeClaim`。这是为了保护系统级存储不被常规用户使用或修改。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: v1
    kind: PersistentVolume
    metadata:
      name: my-pv
    spec:
      capacity:
        storage: 5Gi
      accessModes:
        - ReadWriteOnce
      claimRef:
        namespace: "kube-system" # 违规
        name: "my-claim"
      csi:
        driver: "pd.csi.storage.gke.io"
        volumeHandle: "vol-12345"
    ```
*   **最佳实践**: `PersistentVolume` 资源应仅绑定到应用程序命名空间中的声明。
*   **控制/执行**: OPA Gatekeeper 或 Kyverno 可创建检查 `spec.claimRef.namespace` 字段的策略，如果它在系统命名空间的阻止列表中则拒绝它。
*   **验证**: 使用以下命令检查 claimRef 到系统命名空间的 PersistentVolumes:
    ```bash
    kubectl get pv -o json | jq -r '.items[] | select(.spec.claimRef and (.spec.claimRef.namespace | test("kube-system|kube-public|gke-system"))) | "\(.metadata.name) has claimRef to system namespace: \(.spec.claimRef.namespace)"'
    ```

---
## RBAC

### GKE-TEP-RBAC-0001：客户创建的 ClusterRoleBindings 和 RoleBindings 必须包含客户主体

*   **描述**: 此规则确保用户创建 `RoleBindings` 或 `ClusterRoleBindings` 时，`subjects` (被授予角色的用户、组或服务账户) 是有效的，并属于客户的组织，而不是系统账户。这可防止通过将强大角色绑定到意外主体来提升权限。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: my-role-binding
      namespace: my-app
    subjects:
    - kind: ServiceAccount
      name: kube-system # 违规: 绑定到另一个命名空间中的服务账户
      namespace: kube-system
    roleRef:
      kind: Role
      name: my-role
      apiGroup: rbac.authorization.k8s.io
    ```
*   **最佳实践**: 仅将角色绑定到相同命名空间中的主体或已知的受信任身份。
*   **控制/执行**: OPA Gatekeeper 或 Kyverno 可用于检查新绑定的 `subjects` 并针对一组规则进行验证 (例如，主体不得在系统命名空间中，主体必须匹配某些命名约定)。
*   **验证**: 使用以下命令检查具有来自系统命名空间主体的 RoleBindings/ClusterRoleBindings:
    ```bash
    kubectl get rolebindings,clusterrolebindings --all-namespaces -o json | jq -r '.items[] | .subjects[]? | select(.namespace | test("kube-system|kube-public|gke-system")) | "\(.name) in \(.kind) \(.metadata.name) has subject from system namespace: \(.namespace)"'
    ```

### GKE-TEP-RBAC-0002：如果已存在同名的集群级资源，Flux 不应更新该资源

*   **描述**: 这是针对使用 Flux 的 GitOps 工作流程的特定规则。它防止 Flux 覆盖已存在但不由 Flux 管理的同名集群级资源 (如 `ClusterRole`)。这是一种安全措施，防止 GitOps 工具意外接管或修改关键的手动创建资源。
*   **违规示例**: 手动创建名为 `pod-reader` 的 `ClusterRole`。然后开发人员将具有相同名称的不同 `ClusterRole` 提交到 Flux 监控的 Git 存储库。Flux 将尝试应用其版本，覆盖手动创建的版本。
*   **最佳实践**: 为 Flux 管理的资源使用不同的命名约定。在将新的集群级资源添加到 Git 之前，请检查集群中是否已存在同名资源。
*   **控制/执行**: 这通常是 Flux 本身的配置设置 (`--keep-existing-resources`)。也可以通过 OPA Gatekeeper 策略强制执行，该策略检查是否存在同名同类型的资源且不由 Flux 拥有。
*   **验证**: 使用以下命令检查可能导致冲突的集群级资源:
    ```bash
    kubectl get clusterroles,clusterrolebindings -o json | jq -r '.items[] | select(.metadata.ownerReferences == null or (.metadata.ownerReferences[]? | .name | startswith("flux") | not)) | "\(.kind)/\(.metadata.name) is not owned by Flux"'
    ```

### GKE-TEP-RBAC-0003：项目团队不应创建、更新或删除任何 ClusterRole 和 ClusterRoleBinding

*   **描述**: 此规则通过防止应用程序团队管理集群范围的 RBAC 来执行最小权限原则。`ClusterRole` 和 `ClusterRoleBinding` 在整个集群范围内授予权限，其管理应保留给集群管理员。
*   **违规示例**: 具有过度权限的开发人员创建 `ClusterRoleBinding`，将 `cluster-admin` 权限授予其服务账户。
*   **最佳实践**: 使用 Kubernetes RBAC 拒绝所有非管理员用户和组对 `clusterroles` 和 `clusterrolebindings` 的 `create`、`update` 和 `delete` 权限。
*   **控制/执行**: 主要通过 Kubernetes RBAC 强制执行。
*   **验证**: 使用以下命令列出所有 ClusterRoles 和 ClusterRoleBindings 以验证存在哪些:
    ```bash
    kubectl get clusterroles,clusterrolebindings -o json | jq -r '.items[] | "\(.kind)/\(.metadata.name)"'
    ```

---
## 存储类

### GKE-TEP-SC-0002：StorageClass 不得使用 'is-default-class' 注解

*   **描述**: 此规则防止用户创建新的 `StorageClass` 并将其设置为集群的默认值。默认存储类应是集群管理员仔细考虑的选择。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: my-sc
      annotations:
        storageclass.kubernetes.io/is-default-class: "true" # 违规
    provisioner: kubernetes.io/gce-pd
    parameters:
      type: pd-standard
    ```
*   **最佳实践**: 仅集群管理员应管理默认存储类。
*   **控制/执行**: OPA Gatekeeper 或 Kyverno 可创建拒绝任何包含 `storageclass.kubernetes.io/is-default-class: "true"` 注解的 `StorageClass` 的策略 (如果用户不是集群管理员)。
*   **验证**: 使用以下命令检查标记为默认的 StorageClasses:
    ```bash
    kubectl get storageclasses -o json | jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true") | "\(.metadata.name) is set as default StorageClass"'
    ```

### GKE-TEP-SC-0003：StorageClasses 必须使用允许的动态卷供应程序

*   **描述**: 此规则确保 `StorageClass` 资源配置为使用已批准的存储供应程序。这可防止使用不支持或不安全的存储系统。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: my-sc
    provisioner: "untrusted.provisioner.example.com" # 违规
    ```
*   **最佳实践**: 使用规范供应程序如 `pd.csi.storage.gke.io`。
    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: my-sc
    provisioner: "pd.csi.storage.gke.io" # 最佳实践
    parameters:
      type: pd-standard
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 创建针对已批准供应程序白名单验证 `provisioner` 字段的策略。
*   **验证**: 使用以下命令检查使用非批准供应程序的 StorageClasses (替换为实际批准的供应程序):
    ```bash
    kubectl get storageclasses -o json | jq -r '.items[] | select(.provisioner | test("pd.csi.storage.gke.io") | not) | "\(.metadata.name) uses non-approved provisioner: \(.provisioner)"'
    ```

### GKE-TEP-SC-0004：StorageClasses 没有 CMEK 加密

*   **描述**: 这似乎是一个特定检查，可能确保存储类*不*配置特定客户管理的加密密钥 (CMEK)，或者也许它们*是*。假设前者，这可能是防止团队创建未加密存储或使用错误密钥加密的存储的规则。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: my-sc
    provisioner: pd.csi.storage.gke.io
    parameters:
      type: pd-standard
      # 违规: 缺少所需的 CMEK 密钥参数
    ```
*   **最佳实践**: 如果需要 CMEK 加密，`StorageClass` 必须指定正确的密钥。
    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: my-sc
    provisioner: pd.csi.storage.gke.io
    parameters:
      type: pd-standard
      disk-encryption-kms-key: "projects/my-project/locations/us-central1/keyRings/my-keyring/cryptoKeys/my-key" # 最佳实践
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 验证 `StorageClass` 的 `parameters` 并确保所需 CMEK 密钥参数存在且正确 (如果需要)。
*   **验证**: 使用以下命令检查没有 CMEK 加密参数的 StorageClasses:
    ```bash
    kubectl get storageclasses -o json | jq -r '.items[] | select(.parameters | has("disk-encryption-kms-key") | not) | "\(.metadata.name) does not specify CMEK encryption"'
    ```

---
## 系统资源

### GKE-TEP-SRI-0001：系统 StorageClass 和 ClusterIssuer 不应由客户管理

*   **描述**: 此规则防止非管理员用户修改或删除关键的集群范围资源，如默认 `StorageClass` 或用于 cert-manager 的全局 `ClusterIssuer`。
*   **违规示例**: 具有过度权限的用户删除默认 `StorageClass`。
    ```bash
    kubectl delete storageclass standard
    ```
*   **最佳实践**: 使用 RBAC 限制对这些特定命名资源的 `update` 和 `delete` 权限仅给集群管理员。
*   **控制/执行**: 这可以通过 RBAC 针对 `Role` 或 `ClusterRole` 中的 `resourceNames` 来执行。OPA Gatekeeper 也可用于拒绝对特定资源按名称的更改。
*   **验证**: 使用以下命令检查关键系统资源:
    ```bash
    kubectl get storageclasses -o json | jq -r '.items[] | select(.metadata.name == "standard" or .metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true") | "\(.metadata.name) is a default/critical storage class"'
    kubectl get clusterissuers.cert-manager.io -o json | jq -r '.items[] | select(.metadata.name | test("default|system")) | "\(.metadata.name) is a system ClusterIssuer"'
    ```

---
## 卷快照

### GKE-TEP-VSC-0001：VolumeSnapshotClasses 必须使用白名单 CSI 驱动程序

*   **描述**: 与 `StorageClass` 规则类似，这确保 `VolumeSnapshotClass` 资源配置为使用支持快照的已批准 CSI 驱动程序。
*   **违规示例 (YAML)**:
    ```yaml
    apiVersion: snapshot.storage.k8s.io/v1
    kind: VolumeSnapshotClass
    metadata:
      name: my-vsc
    driver: "untrusted.csi.driver.example.com" # 违规
    deletionPolicy: Delete
    ```
*   **最佳实践**: 使用支持快照的规范 CSI 驱动程序，如 `pd.csi.storage.gke.io`。
    ```yaml
    apiVersion: snapshot.storage.k8s.io/v1
    kind: VolumeSnapshotClass
    metadata:
      name: my-vsc
    driver: "pd.csi.storage.gke.io" # 最佳实践
    deletionPolicy: Delete
    ```
*   **控制/执行**: 使用 OPA Gatekeeper 或 Kyverno 针对已批准 CSI 快照程序白名单验证 `driver` 字段。
*   **验证**: 使用以下命令检查使用非批准驱动程序的 VolumeSnapshotClasses (替换为实际批准的驱动程序):
    ```bash
    kubectl get volumesnapshotclasses -o json | jq -r '.items[] | select(.driver | test("pd.csi.storage.gke.io") | not) | "\(.metadata.name) uses non-approved snapshot driver: \(.driver)"'
    ```

---
## Webhooks

### GKE-TEP-WEBH-0001：意外的准入 webhook 配置

*   **描述**: 此规则作为防范未经授权或配置错误的准入 webhook 的保障。`MutatingWebhookConfiguration` 和 `ValidatingWebhookConfiguration` 可以拦截对 Kubernetes API 的请求，恶意 webhook 可能危及集群。此规则将针对一组标准检查新的或修改的 webhook (例如，服务必须在特定命名空间中，使用可信证书等)。
*   **违规示例**: 用户创建 `ValidatingWebhookConfiguration`，指向其自己命名空间中运行的服务，允许他们拦截并可能拒绝合法请求。
*   **最佳实践**: Webhook 的创建和管理应是高度特权的操作，仅限于集群管理员。应审核所有 webhook 配置。
*   **控制/执行**: 这是一种元控制。需要非常高级的管理员来监控新的 webhook 配置的创建。OPA Gatekeeper 可用于强制执行关于 webhook 本身的策略，例如要求它们指向具有特定标签或在特定命名空间中的服务。
*   **验证**: 使用以下命令列出所有 MutatingWebhookConfigurations 和 ValidatingWebhookConfigurations:
    ```bash
    kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations -o json | jq -r '.items[] | "\(.kind)/\(.metadata.name) - service: \(.webhooks[].clientConfig.service.namespace)/\(.webhooks[].clientConfig.service.name)"'
    ```