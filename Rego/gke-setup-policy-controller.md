# GKE Policy Controller 完整安装与配置指南

## 1. 概述

GKE Policy Controller 是 Google Cloud 原生的策略管理解决方案，基于 OPA Gatekeeper 实现，为 Kubernetes 集群提供策略即代码（Policy as Code）能力。

**核心功能**：
- 合规性检查（安全、监管、业务规则）
- 审计与强制执行
- 预置 100+ 策略模板库

---

## 2. 前置条件

### 2.1 环境要求

| 要求 | 说明 |
|------|------|
| **Google Cloud CLI** | 已安装并初始化 `gcloud`、`kubectl`、`nomos` 命令 |
| **Kubernetes 版本** | 1.14.x 或更高（推荐 1.26+） |
| **集群类型** | GKE Standard 或 Autopilot（非 Config Controller 创建的集群） |
| **GKE 附加集群** | AKS 集群不能有 Azure Policy add-on，不能有 `control-plane` label 的命名空间 |

### 2.2 依赖检查

```bash
# 1. 确认 gcloud 版本（最新）
gcloud components update

# 2. 确认 kubectl 可用
kubectl version --client

# 3. 确认集群访问
gcloud container clusters list

# 4. 确认未安装开源 Gatekeeper（会冲突）
kubectl get namespaces | grep gatekeeper-system && \
  echo "WARNING: OpenSource Gatekeeper detected. Uninstall first!" || \
  echo "OK: No Gatekeeper installed"
```

### 2.3 启用 API

```bash
# 启用 Policy Controller API
gcloud services enable anthospolicycontroller.googleapis.com
```

### 2.4 IAM 权限

确保当前用户具有以下角色：
- `roles/gkehub.admin` 或等效权限
- `roles/iam.serviceAccountUser`

### 2.5 集群注册（Fleet）

如果使用 `gcloud` 命令配置，需要先将集群注册到 Fleet：

```bash
# 注册集群到 Fleet
gcloud container hub memberships register <MEMBERSHIP_NAME> \
  --gke-cluster=<CLUSTER_LOCATION>/<CLUSTER_NAME> \
  --enable-workload-identity
```

---

## 3. 安装方式

### 3.1 通过 Google Cloud Console 安装

#### 安装步骤

1. **进入 Policy 页面**
   ```
   Google Cloud Console → Kubernetes Engine → Policy (Posture Management)
   访问地址: https://console.cloud.google.com/kubernetes/policy_controller
   ```

2. **配置 Policy Controller**
   - 点击 **add Configure Policy Controller**
   - 可选：点击 **Customize fleet settings** 自定义配置

3. **配置项说明**

   | 配置项 | 说明 | 推荐值 |
   |--------|------|--------|
   | **Enable mutation webhook** | 启用资源变更是功能（不兼容 Autopilot） | 按需启用 |
   | **Audit interval** | 两次审计间隔（秒） | 300 |
   | **Exemptible namespaces** | 豁免的命名空间 | `kube-system`, `kube-public`, `gatekeeper-system` |
   | **Enable referential constraints** | 允许约束模板引用其他对象 | 建议启用 |
   | **Version** | Policy Controller 版本 | 最新稳定版 |

4. **应用 Policy Bundles（可选）**

   | Bundle | 用途 |
   |--------|------|
   | `cis-k8s-v1.5.1` | CIS Kubernetes Benchmark 1.5 |
   | `cis-k8s-v1.7` | CIS Kubernetes Benchmark 1.7 |
   | `pss-baseline-v2022` | Pod Security Standards Baseline |
   | `pss-restricted-v2022` | Pod Security Standards Restricted |
   | `cost-and-reliability-v2023` | 成本与可靠性最佳实践 |

5. **确认安装**
   - 点击 **Save changes** → **Configure** → **Confirm**
   - 等待状态显示 **Installed** ✓

#### 同步到 Fleet 默认配置

安装完成后，可将默认设置同步到其他集群：

1. 进入 **Settings** tab
2. 点击 **Sync to fleet settings**
3. 选择要同步的集群
4. 点击 **Sync to fleet settings**

---

### 3.2 通过 gcloud CLI 安装

#### 基础安装

```bash
# 启用 Policy Controller（单集群）
gcloud container fleet policycontroller enable \
  --memberships=<MEMBERSHIP_NAME>
```

#### 高级配置（fleet-default.yaml）

创建配置文件 `fleet-default.yaml`：

```yaml
policyControllerHubConfig:
  installSpec: INSTALL_SPEC_ENABLED  # 必填，启用安装

  # 可选：资源限制
  # deploymentConfigs:
  #   admission:
  #     containerResources:
  #       limits:
  #         cpu: "1000m"
  #         memory: "8Gi"
  #       requests:
  #         cpu: "500m"
  #         memory: "4Gi"

  # 可选：安装策略包
  # policyContent:
  #   bundles:
  #     cis-k8s-v1.5.1:
  #       exemptedNamespaces:
  #         - "kube-system"
  #     pss-baseline-v2022: {}

  # 可选：豁免命名空间
  # exemptableNamespaces:
  #   - "kube-system"
  #   - "gatekeeper-system"

  # 可选：启用引用约束
  # referentialRulesEnabled: true

  # 可选：调整审计间隔（秒）
  # auditIntervalSeconds: 300

  # 可选：记录所有拒绝和 dry-run 失败
  # logDeniesEnabled: true

  # 可选：启用 mutation
  # mutationEnabled: true

  # 可选：约束违规数量限制
  # constraintViolationLimit: 20
```

#### 应用配置

```bash
# 启用并应用默认配置
gcloud container fleet policycontroller enable \
  --fleet-default-member-config=fleet-default.yaml
```

#### 验证配置

```bash
# 查看 Policy Controller 状态
gcloud container fleet policycontroller describe

# 期望输出包含: state: ACTIVE
```

#### 升级版本

```bash
gcloud container fleet policycontroller update \
  --version=<VERSION> \
  --memberships=<MEMBERSHIP_NAME>
```

#### 卸载

```bash
gcloud container fleet policycontroller disable \
  --memberships=<MEMBERSHIP_NAME>
```

---

### 3.3 通过 Terraform 安装

```hcl
resource "google_gke_hub_feature" "policycontroller" {
  name = "policycontroller"
  location = "global"
  project = data.google_project.default.project_id

  fleet_default_member_config {
    policycontroller {
      policy_controller_hub_config {
        install_spec = "INSTALL_SPEC_ENABLED"

        policy_content {
          bundles {
            bundle = "pss-baseline-v2022"
          }
          template_library {
            installation = "ALL"
          }
        }
      }
    }
  }
}
```

---

## 4. 安装后验证

### 4.1 验证 Controller 状态

```bash
# 检查 Controller Manager 部署
kubectl get deployments -n gatekeeper-system

# 期望输出: gatekeeper-controller-manager 显示 Running

# 查看 Pod 状态
kubectl get pods -n gatekeeper-system

# 期望: 所有 Pod 状态为 Running 或 Completed
```

### 4.2 验证 ConstraintTemplate 库

```bash
# 查看已安装的约束模板
kubectl get constrainttemplates

# 期望: 看到 100+ 模板，包括 k8sallowedrepos, k8scontainerlimits 等
```

### 4.3 验证特定模板

```bash
# 检查单个模板状态
kubectl get constrainttemplate k8scontainerlimits -o jsonpath='{.status}'

# 期望: {"created": true, "kind": "ConstraintTemplate"}
```

### 4.4 gcloud CLI 验证

```bash
gcloud container fleet policycontroller describe \
  --memberships=<MEMBERSHIP_NAME>

# 期望: membershipStates.<MEMBERSHIP_NAME>.policycontroller.state: ACTIVE
```

---

## 5. 详细配置

### 5.1 豁免命名空间

系统命名空间建议豁免，避免影响集群组件：

```yaml
# 推荐豁免的命名空间
exemptableNamespaces:
  - kube-system
  - kube-public
  - kube-node-lease
  - gatekeeper-system
  - config-management-system
  - anthos-config-management
  - gke-policy-controller-system
```

### 5.2 常用 Policy Bundle 组合

| 场景 | 推荐 Bundle |
|------|-------------|
| **安全基线** | `cis-k8s-v1.5.1` |
| **Pod 安全** | `pss-baseline-v2022` + `pss-restricted-v2022` |
| **成本优化** | `cost-and-reliability-v2023` |
| **合规要求** | `nist-sp-800-190`, `pci-dss-v4` |
| **全面安全** | 全部 bundle |

### 5.3 Mutation 配置

启用后，Policy Controller 会自动修改资源使其符合策略：

```bash
# 启用 mutation（安装时）
# 在 Console 中勾选 "Enable mutation webhook"

# 或通过 gcloud（需重新配置）
gcloud container fleet policycontroller enable \
  --fleet-default-member-config=<CONFIG_FILE>
```

```yaml
# fleet-default.yaml 中的 mutation 配置
policyControllerHubConfig:
  installSpec: INSTALL_SPEC_ENABLED
  mutationEnabled: true
```

**注意**: Mutation 不兼容 GKE Autopilot 集群。

### 5.4 引用约束（Referential Constraints）

允许约束模板引用集群中的其他对象进行跨资源验证：

```yaml
# 例如：验证 Service 只引用已存在的 Pod
policyControllerHubConfig:
  referentialRulesEnabled: true
```

---

## 6. 常用 Constraint 示例

### 6.1 强制资源限制

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: must-have-limits
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    auditVersion: "v1beta1"
    enforcementAction: "deny"
    excludeNamespaces: ["kube-system", "gatekeeper-system"]
    ranges:
      - max:
          cpu: "2"
          memory: "4Gi"
        min:
          cpu: "50m"
          memory: "64Mi"
```

### 6.2 强制标签

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-common-labels
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
  parameters:
    labels:
      - key: "app"
      - key: "environment"
      - key: "owner"
```

### 6.3 禁止特权容器

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPPrivilegedContainer
metadata:
  name: no-privileged-containers
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces: ["kube-system"]
```

---

## 7. 监控与审计

### 7.1 查看策略状态（Console）

1. 进入 **Policy** 页面
2. 查看 **Compliance** tab
3. 按集群、约束类型筛选

### 7.2 查看违规详情

```bash
# 查看所有约束的违规情况
kubectl get constraint --all-namespaces

# 查看特定约束的违规
kubectl describe k8scontainerlimits.must-have-limits

# 查看 Gatekeeper 日志
kubectl logs -n gatekeeper-system -l app=gatekeeper --tail=100
```

### 7.3 导出审计报告

```bash
# 导出所有违规
kubectl get constraint --all-namespaces -o yaml > constraint-violations.yaml

# 使用 nomos 导出审计报告（需安装 anthos-cli）
nomos audit
```

### 7.4 指标导出

Policy Controller 默认尝试导出指标到 Prometheus 和 Cloud Monitoring：

```bash
# 查看指标端点
kubectl get svc -n gatekeeper-system

# 期望: gatekeeper-metrics 服务存在
```

---

## 8. 故障排查

### 8.1 Controller 未正常启动

```bash
# 查看 Controller Manager 日志
kubectl logs -n gatekeeper-system -l control-plane=controller-manager --tail=200

# 查看事件
kubectl get events -n gatekeeper-system --sort-by='.lastTimestamp'
```

### 8.2 Webhook 连接失败

```bash
# 检查 webhook 配置
kubectl get validatingwebhookconfigurations gatekeeper-validating-webhook-configuration

# 检查 MutationWebhook 配置（如果启用）
kubectl get mutatingwebhookconfigurations gatekeeper-mutating-webhook-configuration
```

### 8.3 约束模板未创建

```bash
# 检查模板状态
kubectl get constrainttemplates | grep -E "ERROR|false"

# 查看模板详情
kubectl describe constrainttemplate <TEMPLATE_NAME>
```

### 8.4 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `webhook failed to open` | Controller 未运行 | 等待 Controller 就绪 |
| `constraint template not found` | 模板未同步 | 检查 `constrainttemplates` CRD |
| `namespace not exempted` | 豁免配置错误 | 更新 `exemptableNamespaces` |
| `mutation conflict` | Autopilot 不支持 mutation | 禁用 mutation 或不用 Autopilot |

---

## 9. 版本管理

### 9.1 查看当前版本

```bash
kubectl get deployments -n gatekeeper-system gatekeeper-controller-manager \
  -o="jsonpath={.spec.template.spec.containers[0].image}"

# 输出格式: .../gatekeeper:VERSION-GIT_TAG.BUILD_NUMBER
# 例如: gcr.io/config-management-release/gatekeeper:anthos1.3.2-480baac.g0
```

### 9.2 升级策略

1. 阅读 release notes 了解变更
2. 在测试集群验证新版本
3. 通过 Console 或 gcloud 升级

---

## 10. 卸载 Policy Controller

### Console 卸载

1. 进入 **Policy** → **Settings** tab
2. 点击集群的 **Edit** 按钮
3. 展开 **About Policy Controller**
4. 选择 **Uninstall Policy Controller**
5. 确认卸载

### gcloud 卸载

```bash
gcloud container fleet policycontroller disable \
  --memberships=<MEMBERSHIP_NAME>
```

---

## 11. 下一步

- [Policy Controller 概述](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/overview)
- [使用 Policy Bundles](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/concepts/policy-controller-bundles)
- [创建 Constraint](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/creating-policy-controller-constraints)
- [编写自定义 Constraint Template](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/write-custom-constraint-templates)
- [故障排查](https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/troubleshoot-policy-controller)