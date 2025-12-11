- 8
- `The platform does not use CNAME records for tenant users by default, so this control is not applicable`
- 18 Change to Yes
- `Covered by GCP-CD-CTRL-16. Private DNS logging is enforced by the core team at the organization level, ensuring queries are tracked.`

我们已在所有使用 VPC 私有 DNS 的环境中启用 Cloud DNS 的私有 DNS Logging 功能。

通过启用 DNS Query Logging，系统会记录所有由 VPC 内部资源发起的 DNS 查询，并将日志输出到 Cloud Logging。日志进一步可导出到 BigQuery 用于审计分析，也可通过 Cloud Logging Sink 传输到 SIEM 平台作安全监控。

所有 DNS 日志至少保存 400 天，并且访问日志受 IAM 权限控制，仅授权的安全与运维人员可查看。

We have enabled Cloud DNS Private DNS Logging in all environments that use VPC Private DNS.

By enabling DNS Query Logging, the system records all DNS queries initiated by resources within the VPC and exports the logs to Cloud Logging. These logs can be further exported to BigQuery for audit analysis, or to a SIEM platform via Cloud Logging Sinks for security monitoring.

All DNS logs are retained for at least 400 days, and access to the logs is controlled through IAM permissions, ensuring that only authorized security and operations personnel have access.

# gcp

GCP-GKE-CTRL-01 ==> Yes ==> The platform defaults to Workload Identity for users' APIs.

03 ==> The principle of least privilege is ensured through the received regular permission audits, but there is a lack of real - time enforcement policies.
06 ==> The platform restricts the permissions of the default KSA through the built - in RBAC policy.

08 ==> edit to yes ==> because kms for cluster  reference 88
10 --> 集群节点池配置强制开启Shielded GKE Nodes。
gcloud container node-pools describe <NODE_POOL_NAME> \

    --cluster=<CLUSTER_NAME> \

    --region=<REGION>
   shieldedInstanceConfig:
  enableSecureBoot: true
  enableIntegrityMonitoring: true
11 ==> Integrity monitoring must be enabled for the configuration of the cluster node pool.
12 ==> 
# **如何验证集群节点池是否启用了 Secure Boot？**

  

## **方法 1：使用 gcloud（最推荐、最精确）**
gcloud container node-pools describe <NODE_POOL_NAME> \
    --cluster=<CLUSTER_NAME> \
    --region=<REGION>

shieldedInstanceConfig:
  enableSecureBoot: true
  只要 enableSecureBoot: true 就代表 **Security Startup 已启用**。



13 ==> We control the users' deployment templates, so this kind of problem does not exist.

14 ==> The AIBANG cluster has been planned to be in an independent network security zone during deployment.

15 ==> Enable Pod Security Admission (PSA) for the Namespace, set the standard to "baseline", and enforce it in "enforce" mode.
26 ==> GKE审计日志默认启用并被收集GKE audit logs are enabled and collected by default.
GKE audit logs are enabled and collected by default through Cloud Audit Logs. 
We verified this by checking the Cloud Logging “Admin Activity Logs” for the Kubernetes Engine API, which are always enabled and cannot be disabled. The logs are visible in Cloud Logging under the `k8s_cluster` resource type and include all control-plane operations. 

27 ==> Currently, some firewall rules are still based on tags.
36 ==> CI/CD流水线中包含漏洞扫描步骤,我们会基于漏洞规则的验证级别来决定是否部署到生产环境。The CI/CD pipeline includes a vulnerability scanning step. We will decide whether to deploy to the production environment based on the verification level of the vulnerability rules.

40 ==> 依赖应用团队定期更新镜像版本来应用最新的补丁Rely on the application team to regularly update the image version to apply the latest patches.

45 ==> 特权访问控制 | 特权访问必须符合企业PAM标准。 遵循GCS (Google Cloud Security)标准,通过PAM系统进行特权访问

The enterprise PAM standard requires that all privileged access is centrally managed, controlled, and monitored. Privileged users must authenticate through an enterprise PAM solution, with MFA enforcement, session recording, and strict least-privilege controls. Access must be granted on a Just-in-Time basis and requires proper approval. Privileged credentials are automatically rotated and never directly disclosed to users. All privileged actions are fully logged and auditable.


47 ==> The configuration of the cluster node pool is set to force the enabling of auto - repair.

48 ==>  目前生产环境的部署受到CR的保护.但是账户部分应该没有做单独的划分。
Currently, the deployments in the production environment are protected by CR. However, there doesn't seem to be a separate division for accounts.

49 ==> 目前特权用户可以对Secret的读取,需要进行审计和修复。比如ID-gcp
Currently, privileged users can read Secrets, which requires auditing and remediation. For example, ID - gcp.

51 ==> 特权访问控制 | 只有策略管理员必须有权创建准入策略。<br>注意:非策略管理员不得有权创建/更新/删除准入策略 Currently, the deployments in the production environment are protected by CR

52 ==> Users are unable to connect to our GKE cluster to create the corresponding namespaces. Nor do we create the corresponding Deployments in the default namespace ourselves.


53 ==> no ==>The platform does not grant users the permission to create namespaces.
55 ==>  For the node pools of the AIBANG cluster in the production environment, uniformly set them to the stable channel.

58 ==> The templates for user deployments are controlled within the AIBANG Deployment templates. When we use Kubernetes Secrets, they are exposed as files rather than environment variables.

59 ==> The Pod Security Policy (PSA) enforces this configuration.

62 ==> The configuration of the cluster node pool is set to force the enabling of auto - upgrade.
72 ==> The templates for user deployments are controlled within the AIBANG Deployment templates.Therefore, we disabled the Alpha features.

73==> Nodes of the GKE cluster are all located in private subnets and have no external IP addresses. Moreover, access to the GKE Master must be controlled through special nodes.

74 ==> There are cases where some shared namespaces are mapped to multiple GSAs.
77 ==> It relies on the application team and the key management strategy for regular rotation, lacking an automated mandatory rotation mechanism.

78 ==> The node pools of the AIBANG cluster have been configured with encryption keys.
79 ==> This is an admission controller enabled by default in the GKE cluster.
80 ==> The Pod Security Policy (PSA) mandates the configuration of security contexts, such as using non - root users.
82 ==> The Cloud Operations suite of GKE is enabled by default in the cluster.

83 ==> We do not install third - party storage plugins in the GKE cluster, nor do we store user data.
84==> We control user deployments template. For user deployments, SVC must be enabled.
85==> we can receive violation reports regularly.
86 ==>  the GKE cluster has Workload Identity enabled and that the Kubernetes Service Accounts mapped to GCS Fuse CSI volumes use `iam.gke.io/gcp-service-account` annotations rather than static service account keys.
87 ==> The GKE nodes are explicitly configured with dedicated service accounts that have the least privileges.
88 ==> The GKE cluster has enabled application - layer secret encryption, and uses KMS for key management.
89==> In the configuration of GKE backup jobs, the backup of Secrets resources is explicitly excluded.
90==> This is enforced through static analysis and container scanning strategies in the CI/CD pipeline.
91 ==> All confidential information is stored in the GCP Secret Manager and accessed through Workload Identity.
93 ==> Differentiations are made through Deployment templates and tenant resource tags.
94 ==> This kind of binding is prohibited through policy auditing.
95==> The GKE node service accounts are granted only the minimum permissions necessary to run node components.
97 ==> The RBAC permissions in our cluster do not include local users.
98 ==> The Kubelet read-only API port (10255) is disabled by default on all GKE nodes. GKE uses a managed Kubelet configuration that only exposes the secured port (10250)


