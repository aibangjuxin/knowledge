- [GKE Compliance Guide](#gke-compliance-guide)
  - [Certificate Management](#certificate-management)
    - [GKE-TEP-CERT-0001: Certificates should not use the same secret name in the same namespace](#gke-tep-cert-0001-certificates-should-not-use-the-same-secret-name-in-the-same-namespace)
  - [Container Security](#container-security)
    - [GKE-TEP-CON-0001: Containers must not add capabilities](#gke-tep-con-0001-containers-must-not-add-capabilities)
    - [GKE-TEP-CON-0002: Containers must not allow for privilege escalation](#gke-tep-con-0002-containers-must-not-allow-for-privilege-escalation)
    - [GKE-TEP-CON-0003: Images must not use the latest tag](#gke-tep-con-0003-images-must-not-use-the-latest-tag)
    - [GKE-TEP-CON-0004: Containers must not run as privileged](#gke-tep-con-0004-containers-must-not-run-as-privileged)
    - [GKE-TEP-CON-0005: Containers must define cpu and memory requests](#gke-tep-con-0005-containers-must-define-cpu-and-memory-requests)
    - [GKE-TEP-CON-0006: Containers must run as non-root](#gke-tep-con-0006-containers-must-run-as-non-root)
    - [GKE-TEP-CON-0007: Images must have a whitelisted prefix](#gke-tep-con-0007-images-must-have-a-whitelisted-prefix)
    - [GKE-TEP-CON-0008: Containers must drop all capabilities](#gke-tep-con-0008-containers-must-drop-all-capabilities)
    - [GKE-TEP-CON-0008: Containers must use a whitelisted AppArmor profile](#gke-tep-con-0008-containers-must-use-a-whitelisted-apparmor-profile)
    - [GKE-TEP-CON-0009: Containers must use a readonly root filesystem](#gke-tep-con-0009-containers-must-use-a-readonly-root-filesystem)
    - [GKE-TEP-CON-0010: Containers must use a whitelisted seccomp profile](#gke-tep-con-0010-containers-must-use-a-whitelisted-seccomp-profile)
    - [GKE-TEP-CON-0011: Containers must use imagePullPolicy Always](#gke-tep-con-0011-containers-must-use-imagepullpolicy-always)
    - [GKE-TEP-CON-0012: Containers must not consume Secrets as environment variables](#gke-tep-con-0012-containers-must-not-consume-secrets-as-environment-variables)
    - [GKE-TEP-CON-0013: Customer containers must not run as the system user](#gke-tep-con-0013-customer-containers-must-not-run-as-the-system-user)
  - [Custom Resource Definitions (CRDs)](#custom-resource-definitions-crds)
    - [GKE-TEP-CRD-0001: Prevent customers from managing CustomResourceDefinitions with groups used by the system](#gke-tep-crd-0001-prevent-customers-from-managing-customresourcedefinitions-with-groups-used-by-the-system)
  - [Resource Quotas](#resource-quotas)
    - [GKE-TEP-CRQ-0001: Enforces a quota limit for the total number of resources across all Namespaces](#gke-tep-crq-0001-enforces-a-quota-limit-for-the-total-number-of-resources-across-all-namespaces)
  - [Image Security \& Attestation](#image-security--attestation)
    - [GKE-TEP-CSCS-0001: Platform images must have required attestations](#gke-tep-cscs-0001-platform-images-must-have-required-attestations)
    - [GKE-TEP-CSCS-0002: Customer images must have required attestations](#gke-tep-cscs-0002-customer-images-must-have-required-attestations)
  - [DNS Security](#dns-security)
    - [GKE-TEP-DNS-0001: DNSEndpoints, Services and Gateways must use unique DNS names](#gke-tep-dns-0001-dnsendpoints-services-and-gateways-must-use-unique-dns-names)
    - [GKE-TEP-DNS-0002: DNSEndpoint and Service DNS names must have a whitelisted suffix](#gke-tep-dns-0002-dnsendpoint-and-service-dns-names-must-have-a-whitelisted-suffix)
    - [GKE-TEP-DNS-0003: DNSEndpoint and Service cannot use DNS names reserved for system use](#gke-tep-dns-0003-dnsendpoint-and-service-cannot-use-dns-names-reserved-for-system-use)
    - [GKE-TEP-DNS-0004: DNSEndpoints must only contain valid records](#gke-tep-dns-0004-dnsendpoints-must-only-contain-valid-records)
  - [Gateway and Ingress](#gateway-and-ingress)
    - [GKE-TEP-GATEWAY-0001: Gateway must use whitelisted minProtocolVersion](#gke-tep-gateway-0001-gateway-must-use-whitelisted-minprotocolversion)
    - [GKE-TEP-GATEWAY-0002: Gateway must use whitelisted ciphersuites](#gke-tep-gateway-0002-gateway-must-use-whitelisted-ciphersuites)
    - [GKE-TEP-GATEWAY-0003: Gateway must use a port above 1024](#gke-tep-gateway-0003-gateway-must-use-a-port-above-1024)
    - [GKE-TEP-GATEWAY-0004: Gateway must use whitelisted protocols](#gke-tep-gateway-0004-gateway-must-use-whitelisted-protocols)
    - [GKE-TEP-ING-0004: Ingress resources cannot use hosts reserved for system use](#gke-tep-ing-0004-ingress-resources-cannot-use-hosts-reserved-for-system-use)
  - [Namespaces](#namespaces)
    - [GKE-TEP-NSP-0002: System Namespaces and namespaced resources in system Namespaces should not be managed by customers](#gke-tep-nsp-0002-system-namespaces-and-namespaced-resources-in-system-namespaces-should-not-be-managed-by-customers)
  - [Pod Security](#pod-security)
    - [GKE-TEP-POD-0001: Pods must not use host network namespace](#gke-tep-pod-0001-pods-must-not-use-host-network-namespace)
    - [GKE-TEP-POD-0002: Pods must not use host PID namespace](#gke-tep-pod-0002-pods-must-not-use-host-pid-namespace)
    - [GKE-TEP-POD-0003: Pods must not use host IPC namespace](#gke-tep-pod-0003-pods-must-not-use-host-ipc-namespace)
    - [GKE-TEP-POD-0005: Pods must not use denied PriorityClass](#gke-tep-pod-0005-pods-must-not-use-denied-priorityclass)
    - [GKE-TEP-POD-0006: Pods must use whitelisted volumes](#gke-tep-pod-0006-pods-must-use-whitelisted-volumes)
    - [GKE-TEP-POD-0007: Pods must not use root fsGroup](#gke-tep-pod-0007-pods-must-not-use-root-fsgroup)
    - [GKE-TEP-POD-0008: Pods that block cluster scale down should be avoided](#gke-tep-pod-0008-pods-that-block-cluster-scale-down-should-be-avoided)
  - [Priority Class](#priority-class)
    - [GKE-TEP-PRIC-0001: Customer should not have interaction with system priority class](#gke-tep-pric-0001-customer-should-not-have-interaction-with-system-priority-class)
  - [Monitoring \& Alerting](#monitoring--alerting)
    - [GKE-TEP-PR-0001: PrometheusRule rules that trigger the aibang Alert API must specify valid metadata](#gke-tep-pr-0001-prometheusrule-rules-that-trigger-the-aibang-alert-api-must-specify-valid-metadata)
  - [Storage](#storage)
    - [GKE-TEP-PV-0001: PersistentVolumes must use a whitelisted CSI driver](#gke-tep-pv-0001-persistentvolumes-must-use-a-whitelisted-csi-driver)
    - [GKE-TEP-PV-0003: PersistentVolumes must use a unique CSI volume handle](#gke-tep-pv-0003-persistentvolumes-must-use-a-unique-csi-volume-handle)
    - [GKE-TEP-PV-0004: PersistentVolumes must not have claimRef to System Namespace](#gke-tep-pv-0004-persistentvolumes-must-not-have-claimref-to-system-namespace)
  - [RBAC](#rbac)
    - [GKE-TEP-RBAC-0001: ClusterRoleBindings and RoleBindings created by customers must contain customer subjects](#gke-tep-rbac-0001-clusterrolebindings-and-rolebindings-created-by-customers-must-contain-customer-subjects)
    - [GKE-TEP-RBAC-0002: Flux should not update a cluster-level resource if there is already one with the same name](#gke-tep-rbac-0002-flux-should-not-update-a-cluster-level-resource-if-there-is-already-one-with-the-same-name)
    - [GKE-TEP-RBAC-0003: Project team should not create, update or delete any ClusterRole and ClusterRoleBinding](#gke-tep-rbac-0003-project-team-should-not-create-update-or-delete-any-clusterrole-and-clusterrolebinding)
  - [Storage Class](#storage-class)
    - [GKE-TEP-SC-0002: StorageClass must not use 'is-default-class' annotation](#gke-tep-sc-0002-storageclass-must-not-use-is-default-class-annotation)
    - [GKE-TEP-SC-0003: StorageClasses must use an allowed dynamic volume provisioner](#gke-tep-sc-0003-storageclasses-must-use-an-allowed-dynamic-volume-provisioner)
    - [GKE-TEP-SC-0004: StorageClasses do not have CMEK encrypt](#gke-tep-sc-0004-storageclasses-do-not-have-cmek-encrypt)
  - [System Resources](#system-resources)
    - [GKE-TEP-SRI-0001: System StorageClass and ClusterIssuer should not be managed by customers](#gke-tep-sri-0001-system-storageclass-and-clusterissuer-should-not-be-managed-by-customers)
  - [Volume Snapshots](#volume-snapshots)
    - [GKE-TEP-VSC-0001: VolumeSnapshotClasses must use a whitelisted CSI driver](#gke-tep-vsc-0001-volumesnapshotclasses-must-use-a-whitelisted-csi-driver)
  - [Webhooks](#webhooks)
    - [GKE-TEP-WEBH-0001: Unexpected admission webhook configuration](#gke-tep-webh-0001-unexpected-admission-webhook-configuration)

# GKE Compliance Guide

This document provides a detailed explanation of GKE security and compliance controls, with examples and best practices for each.

## Certificate Management

### GKE-TEP-CERT-0001: Certificates should not use the same secret name in the same namespace

*   **Description**: This rule prevents multiple `Certificate` resources within the same Kubernetes namespace from referencing the same `Secret` name in their `spec.secretName` field. Each certificate should store its resulting TLS key pair in a unique secret to avoid overwrites and conflicts, which could lead to service disruptions if one certificate rotation overwrites another's valid secret.
*   **Violation Example (YAML)**:
    ```yaml
    # certificate-1.yaml
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: my-app-cert-1
      namespace: production
    spec:
      secretName: my-tls-secret # Violation: Same secretName
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
      secretName: my-tls-secret # Violation: Same secretName
      dnsNames:
      - my-other-app.example.com
      issuerRef:
        name: letsencrypt-prod
        kind: ClusterIssuer
    ```
*   **Best Practice (YAML)**:
    ```yaml
    # certificate-1.yaml
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: my-app-cert-1
      namespace: production
    spec:
      secretName: my-app-tls-secret # Best Practice: Unique secretName
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
      secretName: my-other-app-tls-secret # Best Practice: Unique secretName
      dnsNames:
      - my-other-app.example.com
      issuerRef:
        name: letsencrypt-prod
        kind: ClusterIssuer
    ```
*   **Control/Enforcement**: This can be enforced using a policy engine like OPA Gatekeeper or Kyverno. A validation policy would check all `Certificate` resources and ensure that for any given namespace, the `spec.secretName` values are unique across all certificates.
*   **Verification**: Use the following command to check for duplicate secret names in certificates within a specific namespace:
    ```bash
    kubectl get certificates -n <namespace> -o json | jq -r '.items[] | select(.spec.secretName) | .metadata.name + " -> " + .spec.secretName' | sort | uniq -d
    ```
    This command will list any duplicate secret names used by certificates in the specified namespace.

---


## Container Security

### GKE-TEP-CON-0001: Containers must not add capabilities

*   **Description**: The `securityContext.capabilities.add` field in a container's definition should be empty or not defined. Adding Linux capabilities can grant a container privileges that are typically reserved for the root user, increasing the security risk if the container is compromised. Following the principle of least privilege, containers should not be granted capabilities they do not require.
*   **Violation Example (YAML)**:
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
            add: ["NET_ADMIN", "SYS_TIME"] # Violation: Adding capabilities
    ```
*   **Best Practice (YAML)**:
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
            drop: ["ALL"] # Best Practice: Drop all capabilities, and only add specific capabilities if absolutely necessary
    ```
*   **Control/Enforcement**: Use a Pod Security Policy (PSP - deprecated) or a modern equivalent like OPA Gatekeeper, Kyverno, or GKE's Pod Security Admission Controller. The policy should forbid any value in `securityContext.capabilities.add`.
*   **Verification**: Use the following command to check for containers that add capabilities:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.capabilities.add) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) is adding capabilities: \(.securityContext.capabilities.add[])"'
    ```

### GKE-TEP-CON-0002: Containers must not allow for privilege escalation

*   **Description**: The `securityContext.allowPrivilegeEscalation` field should be set to `false`. This prevents a container from gaining more privileges than its parent process. For example, a process with `setuid` or `setgid` binaries could escalate privileges, which is a significant security risk.
*   **Violation Example (YAML)**:
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
          allowPrivilegeEscalation: true # Violation: Allows privilege escalation
    ```
*   **Best Practice (YAML)**:
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
          allowPrivilegeEscalation: false # Best Practice: Disallow privilege escalation
    ```
*   **Control/Enforcement**: This is a baseline policy in the Pod Security Admission controller (PSA). It can also be enforced with OPA Gatekeeper or Kyverno by creating a policy that requires `securityContext.allowPrivilegeEscalation` to be `false`.
*   **Verification**: Use the following command to check for containers that allow privilege escalation:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.allowPrivilegeEscalation == true) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) allows privilege escalation"'
    ```

### GKE-TEP-CON-0003: Images must not use the latest tag

*   **Description**: Container images should be defined with a specific version tag or a digest. Using the `:latest` tag is discouraged because it can lead to unpredictable behavior and makes it difficult to track which version of an image is running. This can complicate rollbacks and security auditing.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-latest-tag
    spec:
      containers:
      - name: main-container
        image: nginx:latest # Violation: Using latest tag
    ```
*   **Best Practice (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-specific-tag
    spec:
      containers:
      - name: main-container
        image: nginx:1.21.6 # Best Practice: Use a specific version tag
    # --- OR ---
    # spec:
    #   containers:
    #   - name: main-container
    #     image: nginx@sha256:2f2974912acde9413149af97825206192931484556e3b50c4e1def6c65293678 # Best Practice: Use a digest
    ```
*   **Control/Enforcement**: Use an admission controller like OPA Gatekeeper or Kyverno to create a policy that rejects any container image that uses the `:latest` tag or does not include a digest.
*   **Verification**: Use the following command to check for containers using the `:latest` tag:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.image | endswith(":latest")) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) uses latest tag: \(.image)"'
    ```

### GKE-TEP-CON-0004: Containers must not run as privileged

*   **Description**: The `securityContext.privileged` field must be set to `false`. Privileged containers have access to all devices on the host and can bypass many security mechanisms. Running containers as privileged is a major security risk and should be avoided unless absolutely necessary.
*   **Violation Example (YAML)**:
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
          privileged: true # Violation: Container is running as privileged
    ```
*   **Best Practice (YAML)**:
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
          privileged: false # Best Practice: Container does not run as privileged
    ```
*   **Control/Enforcement**: This is a baseline policy in the Pod Security Admission controller (PSA). OPA Gatekeeper or Kyverno can also be used to enforce a policy that requires `securityContext.privileged` to be `false`.
*   **Verification**: Use the following command to check for privileged containers:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.privileged == true) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) is privileged"'
    ```

### GKE-TEP-CON-0005: Containers must define cpu and memory requests

*   **Description**: All containers should have CPU and memory `requests` defined in their `resources` block. Setting resource requests allows the Kubernetes scheduler to make intelligent decisions about where to place pods, preventing resource contention and ensuring that the application has the resources it needs to run reliably. It is also a best practice to set `limits` to prevent a single container from consuming all available resources on a node.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-no-requests
    spec:
      containers:
      - name: main-container
        image: nginx
        # Violation: No resource requests or limits defined
    ```
*   **Best Practice (YAML)**:
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
*   **Control/Enforcement**: This can be enforced using `LimitRange` objects in Kubernetes, which can set default resource requests for containers in a namespace. For more stringent control, OPA Gatekeeper or Kyverno can be used to create a policy that requires all containers to have `resources.requests` for `cpu` and `memory` explicitly defined.
*   **Verification**: Use the following command to check for containers without CPU and memory requests:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select((.resources.requests.cpu == null) or (.resources.requests.memory == null)) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) is missing CPU or memory requests"'
    ```

### GKE-TEP-CON-0006: Containers must run as non-root

*   **Description**: The `securityContext.runAsNonRoot` field should be set to `true`, and a specific `runAsUser` should be defined. Running containers as a non-root user is a critical security best practice. If an attacker gains control of a container running as root, they could potentially have root access to the underlying host.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-running-as-root
    spec:
      containers:
      - name: main-container
        image: nginx
        # Violation: The container may run as root by default
    ```
*   **Best Practice (YAML)**:
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
          runAsNonRoot: true # Best Practice: Enforce non-root user
    ```
*   **Control/Enforcement**: This is a baseline policy in the Pod Security Admission controller (PSA). OPA Gatekeeper and Kyverno can also enforce this by requiring `securityContext.runAsNonRoot` to be `true` and optionally requiring `runAsUser` to be within a specific range.
*   **Verification**: Use the following command to check for containers running as root (or without runAsNonRoot specified):
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.runAsNonRoot == false or .securityContext.runAsUser == 0 or (.securityContext.runAsNonRoot == null and .securityContext.runAsUser == null)) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) is running as root or without runAsNonRoot specified"'
    ```

### GKE-TEP-CON-0007: Images must have a whitelisted prefix

*   **Description**: Container images should only be pulled from approved, trusted registries. This is typically enforced by requiring all image paths to start with a whitelisted prefix (e.g., `gcr.io/my-project/`). This prevents the use of untrusted or un-scanned images from public repositories like Docker Hub, reducing the risk of running vulnerable or malicious code.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-untrusted-image
    spec:
      containers:
      - name: main-container
        image: random-user/malicious-image:1.0 # Violation: Image from a non-whitelisted registry
    ```
*   **Best Practice (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-trusted-image
    spec:
      containers:
      - name: main-container
        image: gcr.io/my-project/my-app:1.2.3 # Best Practice: Image from a whitelisted registry
    ```
*   **Control/Enforcement**: Use an admission controller like OPA Gatekeeper or Kyverno to validate the `image` field of all containers. The policy should match the image name against a list of approved registry prefixes.
*   **Verification**: Use the following command to check for containers with images that don't match a whitelisted prefix (replace `gcr.io/my-project/` with your actual whitelist):
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.image | startswith("gcr.io/my-project/") | not) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) uses non-whitelisted image: \(.image)"'
    ```

### GKE-TEP-CON-0008: Containers must drop all capabilities

*   **Description**: The `securityContext.capabilities.drop` field should be set to `["ALL"]`. Linux capabilities grant specific privileges to processes. By default, containers are granted a set of capabilities. To adhere to the principle of least privilege, all default capabilities should be dropped, and only the specific capabilities required by the application should be added back if necessary.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-default-caps
    spec:
      containers:
      - name: main-container
        image: nginx
        # Violation: Default capabilities are not dropped
    ```
*   **Best Practice (YAML)**:
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
            drop: ["ALL"] # Best Practice: Drop all capabilities
            # Add back only what is needed, e.g., NET_BIND_SERVICE to bind to ports < 1024
            # add: ["NET_BIND_SERVICE"]
    ```
*   **Control/Enforcement**: This can be enforced with OPA Gatekeeper or Kyverno by creating a policy that requires `securityContext.capabilities.drop` to contain the value `ALL`.
*   **Verification**: Use the following command to check for containers that don't drop all capabilities:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.capabilities.drop == null or (.securityContext.capabilities.drop | index("ALL") | not)) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) does not drop all capabilities"'
    ```

### GKE-TEP-CON-0008: Containers must use a whitelisted AppArmor profile

*   **Description**: AppArmor is a Linux security module that can restrict a program's capabilities. If AppArmor is enabled on your GKE nodes, you should apply an AppArmor profile to your containers to further sandbox them. The profile should be one of a set of whitelisted profiles, typically `runtime/default` or a custom profile designed for the application.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-apparmor
      # Violation: No AppArmor profile is specified
    spec:
      containers:
      - name: main-container
        image: nginx
    ```
*   **Best Practice (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-apparmor
      annotations:
        container.apparmor.security.beta.kubernetes.io/main-container: runtime/default # Best Practice
    spec:
      containers:
      - name: main-container
        image: nginx
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that checks for the presence and value of the AppArmor annotation on pods. The policy should ensure the annotation is present and its value is one of the whitelisted profiles.
*   **Verification**: Use the following command to check for pods without AppArmor profiles or with non-whitelisted profiles:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.metadata.annotations == null or (.metadata.annotations | has("container.apparmor.security.beta.kubernetes.io/") | not) or (.metadata.annotations | to_entries[] | select(.key | startswith("container.apparmor.security.beta.kubernetes.io/")) | .value | . == "unconfined" or startswith("localhost/"))) | "\(.metadata.name) in namespace \(.metadata.namespace) does not use a whitelisted AppArmor profile"'
    ```

### GKE-TEP-CON-0009: Containers must use a readonly root filesystem

*   **Description**: The `securityContext.readOnlyRootFilesystem` field should be set to `true`. This prevents a container from writing to its root filesystem, which can mitigate a variety of attacks. If the application needs to write data, it should use a dedicated volume mount (`tmpfs` for temporary data or a persistent volume for durable data).
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-writable-rootfs
    spec:
      containers:
      - name: main-container
        image: nginx
        # Violation: root filesystem is writable by default
    ```
*   **Best Practice (YAML)**:
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
          readOnlyRootFilesystem: true # Best Practice
        volumeMounts:
        - name: tmp-data
          mountPath: /var/cache/nginx
      volumes:
      - name: tmp-data
        emptyDir: {}
    ```
*   **Control/Enforcement**: This is a baseline policy in the Pod Security Admission controller (PSA). It can also be enforced with OPA Gatekeeper or Kyverno by requiring `securityContext.readOnlyRootFilesystem` to be `true`.
*   **Verification**: Use the following command to check for containers with writable root filesystems:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.readOnlyRootFilesystem != true) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) has a writable root filesystem"'
    ```

### GKE-TEP-CON-0010: Containers must use a whitelisted seccomp profile

*   **Description**: Seccomp (secure computing mode) is a Linux kernel feature that restricts the system calls an application can make. GKE nodes run with a default seccomp profile. Applying a seccomp profile to your containers, such as the `RuntimeDefault` profile, is a strong security practice.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-seccomp
    spec:
      containers:
      - name: main-container
        image: nginx
      # Violation: No seccomp profile is specified
    ```
*   **Best Practice (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-seccomp
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault # Best Practice
      containers:
      - name: main-container
        image: nginx
    ```
*   **Control/Enforcement**: This is a baseline policy in the Pod Security Admission controller (PSA). OPA Gatekeeper or Kyverno can be used to enforce a policy that requires `securityContext.seccompProfile.type` to be `RuntimeDefault` or another whitelisted profile.
*   **Verification**: Use the following command to check for containers without a whitelisted seccomp profile:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.seccompProfile == null or (.securityContext.seccompProfile.type != "RuntimeDefault" and .securityContext.seccompProfile.type != "Localhost")) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) does not use a whitelisted seccomp profile"'
    ```

### GKE-TEP-CON-0011: Containers must use imagePullPolicy Always

*   **Description**: The `imagePullPolicy` for a container should be set to `Always`. This ensures that the kubelet pulls the image on every pod startup, which guarantees that you are running the intended version and that any security updates to the image are applied. It also helps to verify that the image is still available in the registry.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-default-pull-policy
    spec:
      containers:
      - name: main-container
        image: nginx:1.21.6
        imagePullPolicy: IfNotPresent # Violation (or omitted, which can default to IfNotPresent)
    ```
*   **Best Practice (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-always-pull-policy
    spec:
      containers:
      - name: main-container
        image: nginx:1.21.6
        imagePullPolicy: Always # Best Practice
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that requires `imagePullPolicy` to be set to `Always`.
*   **Verification**: Use the following command to check for containers that don't use imagePullPolicy Always:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.imagePullPolicy == null or .imagePullPolicy == "IfNotPresent" or .imagePullPolicy == "Never") | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) does not use imagePullPolicy Always: \(.imagePullPolicy // "default to IfNotPresent")"'
    ```

### GKE-TEP-CON-0012: Containers must not consume Secrets as environment variables

*   **Description**: Secrets should be mounted as files into a container rather than being exposed as environment variables. Environment variables can be accidentally exposed through logs, shell history, or other means. Mounting secrets as in-memory `tmpfs` volumes is the most secure method.
*   **Violation Example (YAML)**:
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
              key: password # Violation
    ```
*   **Best Practice (YAML)**:
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
*   **Control/Enforcement**: OPA Gatekeeper or Kyverno can be used to create a policy that forbids the use of `env.valueFrom.secretKeyRef`.
*   **Verification**: Use the following command to check for containers that consume secrets as environment variables:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.env[]? | select(.valueFrom.secretKeyRef)) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) consumes secrets as environment variables"'
    ```

### GKE-TEP-CON-0013: Customer containers must not run as the system user

*   **Description**: Containers should not run with user ID (UID) 0 (root) or other low-numbered UIDs that are typically reserved for system accounts. A high UID (e.g., above 1000) should be used.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-running-as-system-user
    spec:
      securityContext:
        runAsUser: 0 # Violation
      containers:
      - name: main-container
        image: my-app
    ```
*   **Best Practice (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-running-as-non-system-user
    spec:
      securityContext:
        runAsUser: 1001 # Best Practice
        runAsGroup: 3001
      containers:
      - name: main-container
        image: my-app
    ```
*   **Control/Enforcement**: This can be enforced with OPA Gatekeeper or Kyverno by creating a policy that requires `securityContext.runAsUser` to be above a certain threshold (e.g., > 1000).
*   **Verification**: Use the following command to check for containers running as root or with low UIDs:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[].spec.containers[] | select(.securityContext.runAsUser == null or .securityContext.runAsUser <= 1000) | "\(.name) in pod \(.metadata.name) in namespace \(.metadata.namespace) runs with low UID: \(.securityContext.runAsUser // "not specified, defaults to image user")"'
    ```
---
## Custom Resource Definitions (CRDs)

### GKE-TEP-CRD-0001: Prevent customers from managing CustomResourceDefinitions with groups used by the system

*   **Description**: This rule prevents non-admin users from creating, updating, or deleting CustomResourceDefinitions (CRDs) that belong to system-level API groups (e.g., `*.k8s.io`, `*.istio.io`). Allowing modification of system CRDs could lead to cluster instability or security vulnerabilities.
*   **Violation Example**: A user without cluster-admin rights attempting to patch a CRD in a protected API group.
    ```bash
    kubectl patch crd gateways.networking.istio.io --type merge -p '{"spec":{"group":"my-rogue-group"}}'
    ```
*   **Best Practice**: Only cluster administrators should have RBAC permissions to manage CRDs. Application teams should not be granted `create`, `update`, or `delete` permissions on the `customresourcedefinitions` resource.
*   **Control/Enforcement**: Use Kubernetes RBAC to restrict permissions on CRDs. OPA Gatekeeper can also be used to create a policy that denies changes to CRDs based on the user's identity and the CRD's API group.
*   **Verification**: Use the following command to list all CRDs and verify which ones might belong to protected system groups:
    ```bash
    kubectl get crds -o json | jq -r '.items[] | select(.spec.group | test("k8s.io$|istio.io$|kiali.io$")) | "\(.metadata.name) belongs to system group: \(.spec.group)"'
    ```

---
## Resource Quotas

### GKE-TEP-CRQ-0001: Enforces a quota limit for the total number of resources across all Namespaces

*   **Description**: This rule enforces a cluster-wide resource quota. `ResourceQuota` objects are namespaced, but a policy can be implemented to limit the total number of resources (like Pods, Services, etc.) that can be created across the entire cluster. This prevents any single tenant or team from consuming an excessive amount of cluster resources.
*   **Violation Example**: A user creates a new namespace and deploys a large number of pods, exceeding the intended total limit for the cluster.
*   **Best Practice**: Define a `ResourceQuota` for each namespace to limit resources at a granular level. For cluster-wide limits, a custom controller or an admission webhook with OPA Gatekeeper can be used to track resource consumption across namespaces and enforce a total limit.
    ```yaml
    # Example of a per-namespace quota
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
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that fetches all resources of a certain kind across all namespaces and denies the creation of a new resource if the total count exceeds a predefined limit.
*   **Verification**: Use the following command to check resource quota usage across all namespaces:
    ```bash
    kubectl get resourcequotas --all-namespaces -o json | jq -r '.items[] | "\(.metadata.namespace):\(.metadata.name) - \(.status.hard // {} | to_entries[] | "\(.key)=\(.value)")"'
    ```

---
## Image Security & Attestation

### GKE-TEP-CSCS-0001: Platform images must have required attestations

*   **Description**: This rule ensures that all container images used for core platform components have been successfully scanned and attested by a trusted authority before being deployed. This is typically done using a system like Google's Binary Authorization.
*   **Violation Example**: An administrator attempts to deploy a new version of the Ingress controller using an image that has not been attested by the security team.
*   **Best Practice**: Enable Binary Authorization on your GKE cluster and configure a policy that requires attestations from a specific project and attestor for all images matching a certain pattern (e.g., `gcr.io/platform-project/*`).
*   **Control/Enforcement**: Enforced directly by Google's Binary Authorization service. The admission controller will block any pod that uses an image without the required attestations.
*   **Verification**: Use the following command to check Binary Authorization policies:
    ```bash
    gcloud container binauthz policy export
    ```

### GKE-TEP-CSCS-0002: Customer images must have required attestations

*   **Description**: Similar to the platform image rule, this control requires that all application images deployed by users have the necessary security attestations. This typically means the image has passed vulnerability scanning, code analysis, and other quality gates.
*   **Violation Example**: A developer tries to deploy an application using an image that was built locally and pushed to the registry but was never scanned for vulnerabilities, and thus lacks the "vulnerability-scan-passed" attestation.
*   **Best Practice**: Integrate automated scanning and attestation into your CI/CD pipeline. For example, after a successful build, the image is pushed to Artifact Registry, scanned for vulnerabilities, and if it passes, an attestor signs the image.
*   **Control/Enforcement**: Enforced by Google's Binary Authorization. The policy would be configured to require attestations for all customer-owned image repositories.
*   **Verification**: Use the following command to check if pods are using images with required attestations:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.containers[]) | "\(.metadata.name) in namespace \(.metadata.namespace) uses image: \(.spec.containers[].image)"'
    ```

---
## DNS Security

### GKE-TEP-DNS-0001: DNSEndpoints, Services and Gateways must use unique DNS names

*   **Description**: This rule prevents multiple resources from claiming the same DNS hostname, which would cause traffic routing conflicts. For example, two different Istio `Gateway` resources cannot specify the same host.
*   **Violation Example (YAML)**:
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
        - "my-app.example.com" # Violation

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
        - "my-app.example.com" # Violation
    ```
*   **Best Practice**: Ensure that each DNS name is unique across all relevant resources. Use clear naming conventions and central management for DNS to avoid conflicts.
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that caches the hostnames used by `Services`, `Gateways`, and `DNSEndpoints` and denies the creation of a new resource if its hostname is already in use.
*   **Verification**: Use the following command to check for duplicate DNS names across services, gateways, and DNSEndpoints:
    ```bash
    # Check services
    kubectl get services --all-namespaces -o json | jq -r '.items[] | select(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname") | "\(.metadata.namespace):\(.metadata.name) -> \(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname")"'
    # Check Istio Gateways
    kubectl get gateways.networking.istio.io --all-namespaces -o json | jq -r '.items[].spec.servers[].hosts[]? | "\(.metadata.namespace):\(.metadata.name) -> \(.)"'
    # Check DNSEndpoints
    kubectl get dnsendpoints.externaldns.k8s.io --all-namespaces -o json | jq -r '.items[].spec.endpoints[].dnsName? | "\(.metadata.namespace):\(.metadata.name) -> \(.)"'
    ```

### GKE-TEP-DNS-0002: DNSEndpoint and Service DNS names must have a whitelisted suffix

*   **Description**: This rule requires that all DNS names created for services have an approved domain suffix (e.g., `.prod.gcp.example.com`). This prevents teams from creating arbitrary public DNS names and ensures they are all managed under the organization's proper domain structure.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: my-service
      annotations:
        external-dns.alpha.kubernetes.io/hostname: my-app.random-domain.com # Violation
    ```
*   **Best Practice**: Configure services to use a whitelisted domain suffix.
    ```yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: my-service
      annotations:
        external-dns.alpha.kubernetes.io/hostname: my-app.prod.gcp.example.com # Best Practice
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that validates the `external-dns.alpha.kubernetes.io/hostname` annotation (or other relevant fields) against a list of allowed suffixes.
*   **Verification**: Use the following command to check for DNS names that don't have whitelisted suffixes (replace `.example.com` with your actual domain):
    ```bash
    kubectl get services --all-namespaces -o json | jq -r '.items[] | select(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname") | select(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname" | endswith(".example.com") | not) | "\(.metadata.namespace):\(.metadata.name) has non-whitelisted DNS: \(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname")"'
    ```

### GKE-TEP-DNS-0003: DNSEndpoint and Service cannot use DNS names reserved for system use

*   **Description**: This rule prevents application teams from using DNS names that are reserved for the Kubernetes control plane or other system components (e.g., `kubernetes.default.svc.cluster.local`).
*   **Violation Example**: A user tries to create a service that would conflict with an internal system DNS name.
*   **Best Practice**: Educate users on reserved DNS names. The control should block any attempts to use them.
*   **Control/Enforcement**: OPA Gatekeeper or Kyverno can be used to create a policy that denies any resource that attempts to use a hostname from a blocklist of reserved names.
*   **Verification**: Use the following command to check for services using reserved DNS names (replace with your actual reserved names):
    ```bash
    kubectl get services --all-namespaces -o json | jq -r '.items[] | select(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname") | select(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname" | test("kubernetes.default|svc.cluster.local")) | "\(.metadata.namespace):\(.metadata.name) uses reserved DNS: \(.metadata.annotations."external-dns.alpha.kubernetes.io/hostname")"'
    ```

### GKE-TEP-DNS-0004: DNSEndpoints must only contain valid records

*   **Description**: This rule ensures that `DNSEndpoint` custom resources contain valid and well-formed DNS records. This might include checks for valid record types (A, CNAME, etc.), properly formatted targets, and reasonable TTLs.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: externaldns.k8s.io/v1alpha1
    kind: DNSEndpoint
    metadata:
      name: my-dns-endpoint
    spec:
      endpoints:
      - dnsName: my-app.example.com
        recordType: "INVALID" # Violation
        targets:
        - "1.2.3.4"
    ```
*   **Best Practice**: Ensure that all `DNSEndpoint` resources are created with valid record types and targets according to DNS specifications.
*   **Control/Enforcement**: Use the validating webhook that comes with ExternalDNS, or create a custom policy with OPA Gatekeeper or Kyverno to validate the fields within `DNSEndpoint` resources.
*   **Verification**: Use the following command to check for DNSEndpoints with invalid record types:
    ```bash
    kubectl get dnsendpoints.externaldns.k8s.io --all-namespaces -o json | jq -r '.items[].spec.endpoints[] | select(.recordType and (.recordType | test("INVALID|^$"))) | "\(.metadata.namespace):\(.metadata.name) has invalid DNS record type: \(.recordType)"'
    ```
---
## Gateway and Ingress

### GKE-TEP-GATEWAY-0001: Gateway must use whitelisted minProtocolVersion

*   **Description**: This rule enforces the use of strong, modern TLS versions for Ingress traffic. Istio `Gateway` resources should be configured with a minimum TLS protocol version of `TLSv1_2` or higher to protect against known vulnerabilities in older protocols like SSLv3 and TLS 1.0/1.1.
*   **Violation Example (YAML)**:
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
          minProtocolVersion: TLSv1_1 # Violation
        hosts:
        - my-app.example.com
    ```
*   **Best Practice**:
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
          minProtocolVersion: TLSv1_2 # Best Practice
        hosts:
        - my-app.example.com
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that denies `Gateway` resources where `tls.minProtocolVersion` is not set to an approved value.
*   **Verification**: Use the following command to check for Gateways using non-approved TLS protocol versions:
    ```bash
    kubectl get gateways.networking.istio.io --all-namespaces -o json | jq -r '.items[].spec.servers[] | select(.tls and (.tls.minProtocolVersion | test("TLSv1_0|SSL|TLSv1_1"))) | "\(.metadata.namespace):\(.metadata.name) uses non-approved TLS version: \(.tls.minProtocolVersion)"'
    ```

### GKE-TEP-GATEWAY-0002: Gateway must use whitelisted ciphersuites

*   **Description**: To enhance TLS security, this rule requires Istio `Gateway` resources to use a specific list of strong cipher suites. This prevents the use of weak or compromised ciphers that could be exploited by attackers.
*   **Violation Example (YAML)**:
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
          cipherSuites: # Violation: Contains weak ciphers
          - "ECDHE-RSA-WITH-3DES-EDE-CBC-SHA"
    ```
*   **Best Practice**: Specify a list of strong, recommended cipher suites.
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
          cipherSuites: # Best Practice
          - "ECDHE-ECDSA-AES256-GCM-SHA384"
          - "ECDHE-RSA-AES256-GCM-SHA384"
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that validates the `tls.cipherSuites` list against an approved set of ciphers.
*   **Verification**: Use the following command to check for Gateways using non-approved cipher suites (replace with your actual approved ciphers):
    ```bash
    kubectl get gateways.networking.istio.io --all-namespaces -o json | jq -r '.items[].spec.servers[] | select(.tls.cipherSuites) | .tls.cipherSuites[] | select(test("3DES|RC4|MD5")) | "\(.metadata.namespace):\(.metadata.name) uses weak cipher suite: \(.)"'
    ```

### GKE-TEP-GATEWAY-0003: Gateway must use a port above 1024

*   **Description**: This rule is specific to environments where the gateway process does not run as root. It requires that `Gateway` resources listen on non-privileged ports (greater than 1024). This is a defense-in-depth measure.
*   **Violation Example (YAML)**:
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
          number: 80 # Violation (if gateway process is non-root)
          name: http
          protocol: HTTP
        hosts:
        - my-app.example.com
    ```
*   **Best Practice**: Configure the gateway to listen on a non-privileged port. In practice, the Istio ingress gateway service is often mapped from a privileged port (e.g., 443) on the load balancer to a non-privileged port on the pod.
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
          number: 8080 # Best Practice
          name: http
          protocol: HTTP
        hosts:
        - my-app.example.com
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that denies `Gateway` resources with ports less than or equal to 1024.
*   **Verification**: Use the following command to check for Gateways using privileged ports (1024 or below):
    ```bash
    kubectl get gateways.networking.istio.io --all-namespaces -o json | jq -r '.items[].spec.servers[] | select(.port.number <= 1024) | "\(.metadata.namespace):\(.metadata.name) uses privileged port: \(.port.number)"'
    ```

### GKE-TEP-GATEWAY-0004: Gateway must use whitelisted protocols

*   **Description**: This rule ensures that `Gateway` resources only use approved protocols. Typically, this means allowing `HTTP`, `HTTPS`, and `GRPC`, while disallowing others unless explicitly approved.
*   **Violation Example (YAML)**:
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
          protocol: MONGO # Violation
        hosts:
        - my-app.example.com
    ```
*   **Best Practice**: Only use standard, well-understood protocols like HTTPS.
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
          protocol: HTTPS # Best Practice
        hosts:
        - my-app.example.com
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that validates the `servers.port.protocol` field against a list of allowed values.
*   **Verification**: Use the following command to check for Gateways using non-approved protocols (only allowing HTTP, HTTPS, and GRPC):
    ```bash
    kubectl get gateways.networking.istio.io --all-namespaces -o json | jq -r '.items[].spec.servers[] | select(.port.protocol | test("HTTP|HTTPS|GRPC") | not) | "\(.metadata.namespace):\(.metadata.name) uses non-approved protocol: \(.port.protocol)"'
    ```

### GKE-TEP-ING-0004: Ingress resources cannot use hosts reserved for system use

*   **Description**: This is similar to the DNS rule for services, but applied to Kubernetes `Ingress` resources. It prevents users from creating Ingress rules for hostnames that are reserved for system use.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: my-ingress
    spec:
      rules:
      - host: "kubernetes.default" # Violation
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
*   **Best Practice**: Application Ingress resources should only use hostnames that are explicitly allocated to them.
*   **Control/Enforcement**: OPA Gatekeeper or Kyverno can be used to create a policy that denies any `Ingress` that attempts to use a hostname from a blocklist of reserved names.
*   **Verification**: Use the following command to check for Ingress resources using reserved hostnames:
    ```bash
    kubectl get ingress --all-namespaces -o json | jq -r '.items[].spec.rules[] | select(.host | test("kubernetes.default|svc.cluster.local")) | "\(.metadata.namespace):\(.metadata.name) uses reserved hostname: \(.host)"'
    ```

---
## Namespaces

### GKE-TEP-NSP-0002: System Namespaces and namespaced resources in system Namespaces should not be managed by customers

*   **Description**: This rule prevents non-admin users from creating, modifying, or deleting resources in system-critical namespaces like `kube-system`, `kube-public`, `gke-system`, and `istio-system`. Modifying resources in these namespaces can compromise the stability and security of the entire cluster.
*   **Violation Example**: A user with overly broad permissions tries to delete a service in `kube-system`.
    ```bash
    kubectl delete service -n kube-system kube-dns
    ```
*   **Best Practice**: Use Kubernetes RBAC to enforce strict access control on system namespaces. By default, only cluster administrators should have write access.
*   **Control/Enforcement**: Enforced primarily through RBAC. OPA Gatekeeper can add another layer of defense by creating a policy that denies all non-admin users from making any changes to resources in protected namespaces.
*   **Verification**: Use the following command to list resources in system namespaces that might be managed by customers (non-system accounts):
    ```bash
    kubectl get all -n kube-system -o json | jq -r '.items[] | "\(.metadata.namespace):\(.metadata.name) - type: \(.kind)"'
    kubectl get all -n kube-public -o json | jq -r '.items[] | "\(.metadata.namespace):\(.metadata.name) - type: \(.kind)"'
    kubectl get all -n gke-system -o json | jq -r '.items[] | "\(.metadata.namespace):\(.metadata.name) - type: \(.kind)"'
    ```
---
## Pod Security

### GKE-TEP-POD-0001: Pods must not use host network namespace

*   **Description**: Pods should not be configured with `hostNetwork: true`. This setting gives the pod direct access to the node's network interface, bypassing all network policies and allowing it to potentially intercept traffic or interact with services on the node's loopback interface.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-host-network
    spec:
      hostNetwork: true # Violation
      containers:
      - name: main-container
        image: nginx
    ```
*   **Best Practice**: Always leave `hostNetwork` as `false` (or omit it, as `false` is the default).
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-host-network
    spec:
      hostNetwork: false # Best Practice
      containers:
      - name: main-container
        image: nginx
    ```
*   **Control/Enforcement**: This is a baseline policy in the Pod Security Admission controller (PSA). It can also be enforced with OPA Gatekeeper or Kyverno by creating a policy that requires `spec.hostNetwork` to be `false`.
*   **Verification**: Use the following command to check for pods using host network:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.hostNetwork == true) | "\(.metadata.namespace):\(.metadata.name) uses host network"'
    ```

### GKE-TEP-POD-0002: Pods must not use host PID namespace

*   **Description**: Pods should not be configured with `hostPID: true`. This would allow processes inside the pod to see all other processes running on the node, breaking process isolation and potentially exposing sensitive information.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-host-pid
    spec:
      hostPID: true # Violation
      containers:
      - name: main-container
        image: nginx
    ```
*   **Best Practice**: Always leave `hostPID` as `false` (or omit it, as `false` is the default).
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-host-pid
    spec:
      hostPID: false # Best Practice
      containers:
      - name: main-container
        image: nginx
    ```
*   **Control/Enforcement**: This is a baseline policy in the Pod Security Admission controller (PSA). It can also be enforced with OPA Gatekeeper or Kyverno by creating a policy that requires `spec.hostPID` to be `false`.
*   **Verification**: Use the following command to check for pods using host PID:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.hostPID == true) | "\(.metadata.namespace):\(.metadata.name) uses host PID"'
    ```

### GKE-TEP-POD-0003: Pods must not use host IPC namespace

*   **Description**: Pods should not be configured with `hostIPC: true`. This allows the pod to share the host's inter-process communication (IPC) namespace, which could allow it to interfere with other processes on the host.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-host-ipc
    spec:
      hostIPC: true # Violation
      containers:
      - name: main-container
        image: nginx
    ```
*   **Best Practice**: Always leave `hostIPC` as `false` (or omit it, as `false` is the default).
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-without-host-ipc
    spec:
      hostIPC: false # Best Practice
      containers:
      - name: main-container
        image: nginx
    ```
*   **Control/Enforcement**: This is a baseline policy in the Pod Security Admission controller (PSA). It can also be enforced with OPA Gatekeeper or Kyverno by creating a policy that requires `spec.hostIPC` to be `false`.
*   **Verification**: Use the following command to check for pods using host IPC:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.hostIPC == true) | "\(.metadata.namespace):\(.metadata.name) uses host IPC"'
    ```

### GKE-TEP-POD-0005: Pods must not use denied PriorityClass

*   **Description**: This rule prevents pods from using a `PriorityClass` that has been disallowed. `PriorityClass` can be used to control pod scheduling and preemption. Certain high-priority classes might be reserved for system-critical workloads, and this rule ensures that application pods do not use them.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-denied-priority
    spec:
      priorityClassName: system-cluster-critical # Violation
      containers:
      - name: main-container
        image: nginx
    ```
*   **Best Practice**: Use a `PriorityClass` that is appropriate for the workload's importance and has been approved for use.
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that validates the `spec.priorityClassName` against a list of allowed (or denied) priority classes.
*   **Verification**: Use the following command to check for pods using specific denied PriorityClasses (replace with your actual denied classes):
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.priorityClassName | test("system-cluster-critical|system-node-critical")) | "\(.metadata.namespace):\(.metadata.name) uses denied PriorityClass: \(.spec.priorityClassName)"'
    ```

### GKE-TEP-POD-0006: Pods must use whitelisted volumes

*   **Description**: Pods should only be allowed to mount specific, whitelisted volume types. For example, you might want to allow `configMap`, `secret`, `emptyDir`, and `persistentVolumeClaim`, but disallow `hostPath`, as it can be used to access the underlying node's filesystem.
*   **Violation Example (YAML)**:
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
        hostPath: # Violation
          path: /
          type: Directory
    ```
*   **Best Practice**: Only use volume types that are necessary and secure, such as `persistentVolumeClaim`.
*   **Control/Enforcement**: This is a baseline policy in the Pod Security Admission controller (PSA), which restricts volume types. OPA Gatekeeper or Kyverno can be used to create a more specific policy that validates all entries in the `spec.volumes` list against an allowed set of volume types.
*   **Verification**: Use the following command to check for pods using non-whitelisted volume types like hostPath:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | .spec.volumes[] | select(.hostPath) | "\(.metadata.namespace):\(.metadata.name) uses hostPath volume: \(.name)"'
    ```

### GKE-TEP-POD-0007: Pods must not use root fsGroup

*   **Description**: The `securityContext.fsGroup` should not be set to 0 (the root group). The `fsGroup` is a special supplemental group that is applied to all containers in a pod and owns any volumes mounted into the pod. Using `fsGroup: 0` can grant unnecessary root-level permissions to volumes.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-root-fsgroup
    spec:
      securityContext:
        fsGroup: 0 # Violation
      containers:
      - name: main-container
        image: nginx
    ```
*   **Best Practice**: If `fsGroup` is needed, use a non-zero value.
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-with-non-root-fsgroup
    spec:
      securityContext:
        fsGroup: 1001 # Best Practice
      containers:
      - name: main-container
        image: nginx
    ```
*   **Control/Enforcement**: OPA Gatekeeper or Kyverno can create a policy to ensure `spec.securityContext.fsGroup` is not `0`.
*   **Verification**: Use the following command to check for pods using root fsGroup:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.spec.securityContext.fsGroup == 0) | "\(.metadata.namespace):\(.metadata.name) uses root fsGroup"'
    ```

### GKE-TEP-POD-0008: Pods that block cluster scale down should be avoided

*   **Description**: Pods can be configured in a way that prevents the cluster autoscaler from removing their node, even if the node is underutilized. This is typically caused by restrictive `PodDisruptionBudgets` (PDBs) or by pods with local storage that cannot be migrated.
*   **Violation Example**: A pod with the annotation `cluster-autoscaler.kubernetes.io/safe-to-evict: "false"` will block scale-down.
    ```yaml
    apiVersion: v1
    kind: Pod
    metadata:
      name: pod-blocking-scaledown
      annotations:
        cluster-autoscaler.kubernetes.io/safe-to-evict: "false" # Violation (unless intended)
    spec:
      containers:
      - name: main-container
        image: nginx
    ```
*   **Best Practice**: Avoid using the `safe-to-evict: "false"` annotation unless absolutely necessary. Configure `PodDisruptionBudgets` to allow for at least one replica to be taken down at any time. Design applications to be stateless or to gracefully handle pod termination and rescheduling.
*   **Control/Enforcement**: OPA Gatekeeper or Kyverno can be used to create a policy that flags or denies pods with the `safe-to-evict: "false"` annotation. Regular monitoring of cluster autoscaler logs can also help identify problematic pods.
*   **Verification**: Use the following command to check for pods that block cluster scale down:
    ```bash
    kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.metadata.annotations."cluster-autoscaler.kubernetes.io/safe-to-evict" == "false") | "\(.metadata.namespace):\(.metadata.name) blocks scale down"'
    ```
---
## Priority Class

### GKE-TEP-PRIC-0001: Customer should not have interaction with system priority class

*   **Description**: This rule prevents non-admin users from creating, deleting, or updating `PriorityClass` resources that are designated for system use (e.g., `system-cluster-critical`). These are critical for the stable operation of the cluster, and modification could lead to instability.
*   **Violation Example**: A user attempts to delete a system-level priority class.
    ```bash
    kubectl delete priorityclass system-node-critical
    ```
*   **Best Practice**: Use RBAC to restrict `create`, `update`, and `delete` permissions on `PriorityClass` resources to cluster administrators only.
*   **Control/Enforcement**: Enforced primarily through RBAC. OPA Gatekeeper can be used to further restrict modifications to resources with specific names.
*   **Verification**: Use the following command to list system priority classes:
    ```bash
    kubectl get priorityclass -o json | jq -r '.items[] | select(.metadata.name | test("system-")) | "\(.metadata.name) has value \(.value)"'
    ```

---
## Monitoring & Alerting

### GKE-TEP-PR-0001: PrometheusRule rules that trigger the aibang Alert API must specify valid metadata

*   **Description**: This is a very specific rule, likely for an internal system. It requires that any `PrometheusRule` that is configured to send alerts to a specific API (named "aibang Alert API") must include a specific set of valid metadata as annotations or labels. This ensures that alerts are correctly routed, processed, and displayed by the downstream alerting system.
*   **Violation Example (YAML)**:
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
            # Violation: Missing required metadata for the aibang Alert API
            summary: "High API error rate detected"
    ```
*   **Best Practice**: Include all required metadata in the `annotations` section of the rule.
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
            aibang.alert.routing-key: "team-alpha" # Best Practice: Include required metadata
            aibang.alert.runbook-url: "https://wiki.example.com/runbooks/high-error-rate"
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that checks `PrometheusRule` resources. If a rule is configured to target the specific API, the policy will validate that the required annotations are present and well-formed.
*   **Verification**: Use the following command to check for PrometheusRules that might trigger the aibang Alert API without required metadata:
    ```bash
    kubectl get prometheusrules --all-namespaces -o json | jq -r '.items[] | select(.spec.groups[].rules[] | select(.annotations | has("summary"))) | "\(.metadata.namespace):\(.metadata.name) has rules with annotations"'
    ```

---
## Storage

### GKE-TEP-PV-0001: PersistentVolumes must use a whitelisted CSI driver

*   **Description**: This rule ensures that `PersistentVolume` (PV) resources are provisioned using an approved Container Storage Interface (CSI) driver. This prevents the use of insecure or unsupported storage backends.
*   **Violation Example (YAML)**:
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
        driver: "untrusted.csi.driver.example.com" # Violation
        volumeHandle: "vol-12345"
    ```
*   **Best Practice**: Use a sanctioned CSI driver, such as the GKE PD CSI Driver.
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
        driver: "pd.csi.storage.gke.io" # Best Practice
        volumeHandle: "projects/my-gcp-project/zones/us-central1-a/disks/my-disk"
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that validates the `spec.csi.driver` field against a whitelist of approved drivers.
*   **Verification**: Use the following command to check for PersistentVolumes using non-whitelisted CSI drivers (replace with your actual approved drivers):
    ```bash
    kubectl get pv -o json | jq -r '.items[] | select(.spec.csi and (.spec.csi.driver | test("pd.csi.storage.gke.io") | not)) | "\(.metadata.name) uses non-approved CSI driver: \(.spec.csi.driver)"'
    ```

### GKE-TEP-PV-0003: PersistentVolumes must use a unique CSI volume handle

*   **Description**: This rule ensures that no two `PersistentVolume` resources point to the same underlying storage volume. A unique `volumeHandle` for each PV prevents conflicts and data corruption that could occur if multiple PVs were trying to manage the same disk.
*   **Violation Example**: Two PVs are created that reference the same GCE Persistent Disk.
*   **Best Practice**: Each `PersistentVolume` must have a `volumeHandle` that is unique within the cluster. When using dynamic provisioning with `StorageClass`, this is handled automatically.
*   **Control/Enforcement**: OPA Gatekeeper or a custom admission controller can be used to cache the `volumeHandle` of all existing PVs and deny the creation of a new PV if its handle is already in use.
*   **Verification**: Use the following command to check for duplicate volume handles in PersistentVolumes:
    ```bash
    kubectl get pv -o json | jq -r '.items[] | select(.spec.csi) | .spec.csi.volumeHandle' | sort | uniq -d
    ```

### GKE-TEP-PV-0004: PersistentVolumes must not have claimRef to System Namespace

*   **Description**: This rule prevents a `PersistentVolume` from being bound to a `PersistentVolumeClaim` in a system namespace (e.g., `kube-system`). This is to protect system-level storage from being used or modified by regular users.
*   **Violation Example (YAML)**:
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
        namespace: "kube-system" # Violation
        name: "my-claim"
      csi:
        driver: "pd.csi.storage.gke.io"
        volumeHandle: "vol-12345"
    ```
*   **Best Practice**: `PersistentVolume` resources should only be bound to claims in application namespaces.
*   **Control/Enforcement**: OPA Gatekeeper or Kyverno can create a policy to check the `spec.claimRef.namespace` field and deny it if it's in a blocklist of system namespaces.
*   **Verification**: Use the following command to check for PersistentVolumes with claimRef to system namespaces:
    ```bash
    kubectl get pv -o json | jq -r '.items[] | select(.spec.claimRef and (.spec.claimRef.namespace | test("kube-system|kube-public|gke-system"))) | "\(.metadata.name) has claimRef to system namespace: \(.spec.claimRef.namespace)"'
    ```

---
## RBAC

### GKE-TEP-RBAC-0001: ClusterRoleBindings and RoleBindings created by customers must contain customer subjects

*   **Description**: This rule ensures that when users create `RoleBindings` or `ClusterRoleBindings`, the `subjects` (the users, groups, or service accounts being granted the role) are valid and belong to the customer's organization, not system accounts. This prevents privilege escalation by binding a powerful role to an unintended subject.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: my-role-binding
      namespace: my-app
    subjects:
    - kind: ServiceAccount
      name: kube-system # Violation: binding to a service account in another namespace
      namespace: kube-system
    roleRef:
      kind: Role
      name: my-role
      apiGroup: rbac.authorization.k8s.io
    ```
*   **Best Practice**: Bind roles only to subjects within the same namespace or to known, trusted identities.
*   **Control/Enforcement**: OPA Gatekeeper or Kyverno can be used to inspect the `subjects` of new bindings and validate them against a set of rules (e.g., subject must not be in a system namespace, subject must match a certain naming convention).
*   **Verification**: Use the following command to check for RoleBindings/ClusterRoleBindings with subjects from system namespaces:
    ```bash
    kubectl get rolebindings,clusterrolebindings --all-namespaces -o json | jq -r '.items[] | .subjects[]? | select(.namespace | test("kube-system|kube-public|gke-system")) | "\(.name) in \(.kind) \(.metadata.name) has subject from system namespace: \(.namespace)"'
    ```

### GKE-TEP-RBAC-0002: Flux should not update a cluster-level resource if there is already one with the same name

*   **Description**: This is a specific rule for GitOps workflows using Flux. It prevents Flux from overwriting an existing cluster-level resource (like a `ClusterRole`) if one with the same name already exists but is not managed by Flux. This is a safety measure to prevent the GitOps tool from accidentally taking over or modifying critical, manually-created resources.
*   **Violation Example**: A `ClusterRole` named `pod-reader` is created manually. A developer then commits a different `ClusterRole` with the same name to the Git repository that Flux is monitoring. Flux would attempt to apply its version, overwriting the manual one.
*   **Best Practice**: Use distinct naming conventions for resources managed by Flux. Before adding a new cluster-level resource to Git, check if a resource with that name already exists in the cluster.
*   **Control/Enforcement**: This is often a configuration setting within Flux itself (`--keep-existing-resources`). It can also be enforced by an OPA Gatekeeper policy that checks if a resource of the same name and kind already exists and is not owned by Flux.
*   **Verification**: Use the following command to check for cluster-level resources that might conflict:
    ```bash
    kubectl get clusterroles,clusterrolebindings -o json | jq -r '.items[] | select(.metadata.ownerReferences == null or (.metadata.ownerReferences[]? | .name | startswith("flux") | not)) | "\(.kind)/\(.metadata.name) is not owned by Flux"'
    ```

### GKE-TEP-RBAC-0003: Project team should not create, update or delete any ClusterRole and ClusterRoleBinding

*   **Description**: This rule enforces the principle of least privilege by preventing application teams from managing cluster-wide RBAC. `ClusterRole` and `ClusterRoleBinding` grant permissions across the entire cluster, and their management should be reserved for cluster administrators.
*   **Violation Example**: A developer with excessive permissions creates a `ClusterRoleBinding` that grants their service account `cluster-admin` rights.
*   **Best Practice**: Use Kubernetes RBAC to deny `create`, `update`, and `delete` permissions on `clusterroles` and `clusterrolebindings` for all non-administrator users and groups.
*   **Control/Enforcement**: Enforced primarily through Kubernetes RBAC.
*   **Verification**: Use the following command to list all ClusterRoles and ClusterRoleBindings to verify which ones exist:
    ```bash
    kubectl get clusterroles,clusterrolebindings -o json | jq -r '.items[] | "\(.kind)/\(.metadata.name)"'
    ```

---
## Storage Class

### GKE-TEP-SC-0002: StorageClass must not use 'is-default-class' annotation

*   **Description**: This rule prevents users from creating a new `StorageClass` and setting it as the default for the cluster. The default storage class should be a carefully considered choice made by the cluster administrators.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: my-sc
      annotations:
        storageclass.kubernetes.io/is-default-class: "true" # Violation
    provisioner: kubernetes.io/gce-pd
    parameters:
      type: pd-standard
    ```
*   **Best Practice**: Only cluster administrators should manage the default storage class.
*   **Control/Enforcement**: OPA Gatekeeper or Kyverno can create a policy to deny any `StorageClass` that contains the `storageclass.kubernetes.io/is-default-class: "true"` annotation if the user is not a cluster admin.
*   **Verification**: Use the following command to check for StorageClasses marked as default:
    ```bash
    kubectl get storageclasses -o json | jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true") | "\(.metadata.name) is set as default StorageClass"'
    ```

### GKE-TEP-SC-0003: StorageClasses must use an allowed dynamic volume provisioner

*   **Description**: This rule ensures that `StorageClass` resources are configured to use an approved storage provisioner. This prevents the use of unsupported or insecure storage systems.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: my-sc
    provisioner: "untrusted.provisioner.example.com" # Violation
    ```
*   **Best Practice**: Use a sanctioned provisioner like `pd.csi.storage.gke.io`.
    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: my-sc
    provisioner: "pd.csi.storage.gke.io" # Best Practice
    parameters:
      type: pd-standard
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to create a policy that validates the `provisioner` field against a whitelist of approved provisioners.
*   **Verification**: Use the following command to check for StorageClasses using non-approved provisioners (replace with your actual approved provisioners):
    ```bash
    kubectl get storageclasses -o json | jq -r '.items[] | select(.provisioner | test("pd.csi.storage.gke.io") | not) | "\(.metadata.name) uses non-approved provisioner: \(.provisioner)"'
    ```

### GKE-TEP-SC-0004: StorageClasses do not have CMEK encrypt

*   **Description**: This seems to be a specific check, likely ensuring that storage classes are *not* configured with a specific Customer-Managed Encryption Key (CMEK), or perhaps that they *are*. Assuming the former, it might be a rule to prevent teams from creating unencrypted storage or storage encrypted with the wrong key.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: my-sc
    provisioner: pd.csi.storage.gke.io
    parameters:
      type: pd-standard
      # Violation: Missing the required CMEK key parameter
    ```
*   **Best Practice**: If encryption with CMEK is required, the `StorageClass` must specify the correct key.
    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: my-sc
    provisioner: pd.csi.storage.gke.io
    parameters:
      type: pd-standard
      disk-encryption-kms-key: "projects/my-project/locations/us-central1/keyRings/my-keyring/cryptoKeys/my-key" # Best Practice
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to validate the `parameters` of a `StorageClass` and ensure the CMEK key parameter is present and correct if required.
*   **Verification**: Use the following command to check for StorageClasses without CMEK encryption parameters:
    ```bash
    kubectl get storageclasses -o json | jq -r '.items[] | select(.parameters | has("disk-encryption-kms-key") | not) | "\(.metadata.name) does not specify CMEK encryption"'
    ```

---
## System Resources

### GKE-TEP-SRI-0001: System StorageClass and ClusterIssuer should not be managed by customers

*   **Description**: This rule prevents non-admin users from modifying or deleting critical, cluster-wide resources like the default `StorageClass` or a global `ClusterIssuer` for cert-manager.
*   **Violation Example**: A user with excessive permissions deletes the default `StorageClass`.
    ```bash
    kubectl delete storageclass standard
    ```
*   **Best Practice**: Use RBAC to restrict `update` and `delete` permissions on these specific, named resources to cluster administrators.
*   **Control/Enforcement**: This can be enforced with RBAC by targeting `resourceNames` in a `Role` or `ClusterRole`. OPA Gatekeeper can also be used to deny changes to specific resources by name.
*   **Verification**: Use the following command to check for critical system resources:
    ```bash
    kubectl get storageclasses -o json | jq -r '.items[] | select(.metadata.name == "standard" or .metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true") | "\(.metadata.name) is a default/critical storage class"'
    kubectl get clusterissuers.cert-manager.io -o json | jq -r '.items[] | select(.metadata.name | test("default|system")) | "\(.metadata.name) is a system ClusterIssuer"'
    ```

---
## Volume Snapshots

### GKE-TEP-VSC-0001: VolumeSnapshotClasses must use a whitelisted CSI driver

*   **Description**: Similar to the `StorageClass` rule, this ensures that `VolumeSnapshotClass` resources are configured to use an approved CSI driver that supports snapshotting.
*   **Violation Example (YAML)**:
    ```yaml
    apiVersion: snapshot.storage.k8s.io/v1
    kind: VolumeSnapshotClass
    metadata:
      name: my-vsc
    driver: "untrusted.csi.driver.example.com" # Violation
    deletionPolicy: Delete
    ```
*   **Best Practice**: Use a sanctioned CSI driver that supports snapshots, like `pd.csi.storage.gke.io`.
    ```yaml
    apiVersion: snapshot.storage.k8s.io/v1
    kind: VolumeSnapshotClass
    metadata:
      name: my-vsc
    driver: "pd.csi.storage.gke.io" # Best Practice
    deletionPolicy: Delete
    ```
*   **Control/Enforcement**: Use OPA Gatekeeper or Kyverno to validate the `driver` field against a whitelist of approved CSI snapshotters.
*   **Verification**: Use the following command to check for VolumeSnapshotClasses using non-approved drivers (replace with your actual approved drivers):
    ```bash
    kubectl get volumesnapshotclasses -o json | jq -r '.items[] | select(.driver | test("pd.csi.storage.gke.io") | not) | "\(.metadata.name) uses non-approved snapshot driver: \(.driver)"'
    ```

---
## Webhooks

### GKE-TEP-WEBH-0001: Unexpected admission webhook configuration

*   **Description**: This rule acts as a safeguard against unauthorized or misconfigured admission webhooks. `MutatingWebhookConfiguration` and `ValidatingWebhookConfiguration` can intercept requests to the Kubernetes API, and a malicious webhook could compromise the cluster. This rule would check new or modified webhooks against a set of criteria (e.g., the service must be in a specific namespace, use a trusted certificate, etc.).
*   **Violation Example**: A user creates a `ValidatingWebhookConfiguration` that points to a service running in their own namespace, allowing them to intercept and potentially deny legitimate requests.
*   **Best Practice**: The creation and management of admission webhooks should be a highly privileged operation restricted to cluster administrators. All webhook configurations should be audited.
*   **Control/Enforcement**: This is a meta-control. A very high-level admin would need to monitor the creation of new webhook configurations. OPA Gatekeeper can be used to enforce policies *about* the webhooks themselves, such as requiring them to point to services with specific labels or in specific namespaces.
*   **Verification**: Use the following command to list all MutatingWebhookConfigurations and ValidatingWebhookConfigurations:
    ```bash
    kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations -o json | jq -r '.items[] | "\(.kind)/\(.metadata.name) - service: \(.webhooks[].clientConfig.service.namespace)/\(.webhooks[].clientConfig.service.name)"'
    ```