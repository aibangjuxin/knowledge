The **GKE Policy Controller** is a Kubernetes-native tool provided by Google Cloud that helps you **enforce governance and security policies** across your GKE clusters using **Open Policy Agent (OPA) Gatekeeper**.

  

它的核心作用是：

  

> **“Prevent misconfigurations and enforce compliance by rejecting or auditing Kubernetes resources that don’t meet policy rules.”**

---

## **🧩** 

## **核心概念概览**

|**名称**|**说明**|
|---|---|
|**Policy Controller**|GKE 中预装的 OPA Gatekeeper，用于强制执行策略规则|
|**Constraint Template**|自定义策略类型的定义（类似“策略类型”），使用 Rego 语言|
|**Constraint**|策略实例（即“具体规则”），使用某个 Template 定义|
|**Violation**|Pod、Service、Namespace 等对象违反策略时的报告或拒绝行为|

---

## **✅** 

## **典型用途**

|**用途类别**|**示例**|
|---|---|
|**安全控制**|阻止使用默认 ServiceAccount、禁止启用 hostPath 或特权容器|
|**命名标准**|要求 Namespace/Pod 命名必须符合某种正则格式|
|**资源配额限制**|要求每个 Pod 设置 CPU/Memory 的 request/limit|
|**访问控制约束**|限制某些 namespace 只能使用指定的 ingressClass|
|**镜像来源限制**|禁止使用非组织内私有仓库的镜像|

---

## **⚙️** 

## **工作原理**

```
graph TD;
    A[Kubernetes API Server] --> B[Policy Controller Webhook];
    B --> C[Constraint Templates];
    B --> D[Constraints];
    C & D --> E[Evaluate AdmissionRequest];
    E --> F[Allow or Reject the Resource];
```

---

## **📦 在 GKE 中如何启用**

```
# 启用 Anthos Config Management（包含 Policy Controller）
gcloud container hub config-management enable

# 部署 Policy Controller（推荐用 YAML 或 GitOps）
gcloud container hub config-management apply \
  --membership=CLUSTER_NAME \
  --config=./config-management.yaml
```

Policy Controller 是 Anthos Config Management 的一部分，但在 GKE 中 **无需购买 Anthos 授权也可以免费使用**。

---

## **📘 示例：限制只允许特定镜像仓库**

```
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: only-allow-my-registry
spec:
  enforcementAction: deny
  parameters:
    repos:
      - "gcr.io/my-org/"
      - "asia-docker.pkg.dev/my-org/"
```

---

## **📎 官方文档参考**

- [Policy Controller Overview – Google Cloud](https://cloud.google.com/kubernetes-engine/docs/concepts/policy-controller-overview)
    
- [OPA Gatekeeper project](https://open-policy-agent.github.io/gatekeeper/)
    

---

是否需要我生成一份适合你们 GKE 平台的基础策略集合（YAML）或一份 GKE Policy Controller 安装流程？