在 GKE 中查看 Pub/Sub 和 CronJob 需要分别针对 Google Cloud 的 Pub/Sub 服务和 Kubernetes 的 CronJob 资源进行查询。以下是具体步骤：

查看 Pub/Sub Topics 和 Subscriptions

Pub/Sub 不直接运行在 GKE 上，而是 Google Cloud 提供的独立服务。要查看项目中的所有 Pub/Sub Topics 和 Subscriptions：

使用 gcloud 命令
	1.	查看所有 Pub/Sub Topics：

gcloud pubsub topics list


	2.	查看所有 Subscriptions：

gcloud pubsub subscriptions list


	3.	如果需要按命名过滤（例如，查看和 GKE 有关的）：

gcloud pubsub topics list --filter="name~'gke'"
gcloud pubsub subscriptions list --filter="name~'gke'"



使用 GCP Console
	1.	打开 Pub/Sub 控制台页面.
	2.	查看 Topics 和 Subscriptions 选项卡。

查看 Kubernetes CronJob

Kubernetes 的 CronJob 是一种特定资源类型，可以通过 kubectl 命令查询。

使用 kubectl 命令
	1.	列出所有 Namespaces 的 CronJob：

kubectl get cronjobs --all-namespaces


	2.	查看当前 Namespace 的 CronJob：

kubectl get cronjobs


	3.	查看 CronJob 的详细信息：

kubectl describe cronjob <cronjob-name>


	4.	筛选指定的 CronJob（通过 label、name 等过滤）：

kubectl get cronjobs -l app=gke



使用 Kubernetes Dashboard
	1.	打开 Kubernetes Dashboard。
	2.	导航到 Workloads > CronJobs 以查看和管理 CronJob。

示例输出

Pub/Sub Topics 和 Subscriptions 示例

gcloud pubsub topics list

输出：

NAME	KMS_KEY_NAME	MESSAGE_STORAGE_POLICY	RETENTION_DURATION
my-topic-1		us-central1	7d
my-gke-topic-2		us-east1	10d

CronJob 示例

kubectl get cronjobs

输出：

NAME	SCHEDULE	SUSPEND	ACTIVE	LAST SCHEDULE	AGE
backup-job	0 2 * * *	False	0	2024-12-27	15d
gke-maintenance	30 3 * * 5	False	0	2024-12-20	30d

通过以上步骤即可分别查看 GKE 集群中相关的 Pub/Sub 和 CronJob 资源。如需进一步排查或管理，请提供具体需求！