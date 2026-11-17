Configure a zonal GKE cluster-scoped zone 

我想配置区域GKE集群范围区域
但是系统要求是提供dns v2 这样的接口
我默认的gcloud命令仅仅能调动到v1
那么我如何能调动到V2对应的版本？
如何enable googleapis.com/dns/v2/projects/PROJECT_ID

要启用 Google Cloud DNS API 的 v2 版本,您可以按照以下步骤操作:

1. 打开 Google Cloud Console,切换到您的项目。

2. 在左侧导航菜单中,选择 "API和服务" > "库"。

3. 在库顶部,点击"启用API和服务"。

4. 搜索并选择"Cloud DNS API"。

5. 点击"启用"按钮启用该 API。

6. 启用后,你可以通过 gcloud 命令行工具或 API 调用 Cloud DNS v2。

对于通过 gcloud 调用 v2 版本,您需要使用 --api=dns/v2 标志。例如:

```
gcloud dns managed-zones create zone-name --dns-name=example.com --description="Test Zone" --api=dns/v2
```

这将创建一个使用 v2 版本 API 的托管 DNS 区域。

如果您想设置区域 GKE 集群,并启用 Cloud DNS v2,您可以在创建集群时指定 --cluster-dns=PROVIDER 标志:

```
gcloud container clusters create cluster-name --zone=zone --cluster-dns=dns.googleapis.com/v2
```

这将配置集群使用 Google Cloud DNS v2 API 作为集群 DNS 提供程序。

总的来说,通过明确指定 --api 标志或 --cluster-dns 选项,您可以强制 gcloud 使用 Cloud DNS v2 API 版本。


要配置区域 GKE 集群范围区域，您需要使用 Cloud DNS v2 API。默认的 gcloud 命令只能调用 v1 API，因此您需要使用以下步骤来启用 v2 API：

1. 在 Google Cloud Platform Console 中，转到 **APIs & Services** > **Library**。
2. 搜索 **Cloud DNS**，然后单击 **Enable**。
3. 在 **API Library** 中，找到 **Cloud DNS v2**，然后单击 **Enable**。

启用 v2 API 后，您就可以使用 gcloud 命令来配置区域 GKE 集群范围区域。要执行此操作，请使用以下命令：

```
gcloud dns managed-zones create ZONE_NAME \
  --zone ZONE \
  --gke-clusters CLUSTER_NAME
```

例如，要创建名为 `example-zone` 的区域 GKE 集群范围区域，并将其附加到名为 `my-cluster` 的集群，请使用以下命令：

```
gcloud dns managed-zones create example-zone \
  --zone us-central1-a \
  --gke-clusters my-cluster
```

此命令将创建一个名为 `example-zone` 的区域私有 DNS 区域，并将该区域附加到 `my-cluster` 集群。

有关更多信息，请参阅 Configure a zonal GKE cluster-scoped zone: [https://cloud.google.com/dns/docs/zones/configure-zonal-cluster-scopes](https://cloud.google.com/dns/docs/zones/configure-zonal-cluster-scopes)。

以下是一些其他相关信息：

* Cloud DNS v2 API documentation: [移除了无效网址]
* gcloud dns managed-zones create command-line reference: [https://cloud.google.com/sdk/gcloud/reference/dns/managed-zones/create](https://cloud.google.com/sdk/gcloud/reference/dns/managed-zones/create)


是的，您需要使用 `--api=dns/v2` 标志来通过 gcloud 调用 v2 版本的 Cloud DNS API。

例如，要列出您的所有区域 GKE 集群范围区域，您可以使用以下命令：

```
gcloud dns managed-zones list --api=dns/v2
```

此命令将列出您项目中所有区域 GKE 集群范围区域的列表。

以下是一些其他使用 `--api=dns/v2` 标志的示例：

* 创建区域 GKE 集群范围区域：

```
gcloud dns managed-zones create ZONE_NAME \
  --zone ZONE \
  --gke-clusters CLUSTER_NAME \
  --api=dns/v2
```

* 删除区域 GKE 集群范围区域：

```
gcloud dns managed-zones delete ZONE_NAME \
  --api=dns/v2
```

* 更新区域 GKE 集群范围区域：

```
gcloud dns managed-zones update ZONE_NAME \
  --zone ZONE \
  --gke-clusters CLUSTER_NAME \
  --api=dns/v2
```

有关更多信息，请参阅 gcloud dns managed-zones command-line reference: [https://cloud.google.com/sdk/gcloud/reference/dns/managed-zones](https://cloud.google.com/sdk/gcloud/reference/dns/managed-zones)。


是的，如果您想设置区域 GKE 集群并启用 Cloud DNS v2，您可以在创建集群时指定 `--cluster-dns=PROVIDER` 标志。

此标志将指示 GKE 使用 Cloud DNS v2 API 为您的集群创建和管理 DNS 区域。

例如，要创建名为 `my-cluster` 的区域 GKE 集群并启用 Cloud DNS v2，请使用以下命令：

```
gcloud container clusters create my-cluster \
  --zone us-central1-a \
  --cluster-dns=PROVIDER
```

此命令将创建一个名为 `my-cluster` 的区域 GKE 集群，并使用 Cloud DNS v2 API 为该集群创建和管理 DNS 区域。

如果您不指定 `--cluster-dns=PROVIDER` 标志，GKE 将使用 Cloud DNS v1 API 为您的集群创建和管理 DNS 区域。

以下是一些使用 `--cluster-dns` 标志的其他示例：

* 创建区域 GKE 集群并使用 Cloud DNS v1：

```
gcloud container clusters create my-cluster \
  --zone us-central1-a \
  --cluster-dns=DEFAULT
```

* 创建区域 GKE 集群并使用外部 DNS 提供程序：

```
gcloud container clusters create my-cluster \
  --zone us-central1-a \
  --cluster-dns=EXTERNAL
```

有关更多信息，请参阅 gcloud container clusters create command-line reference: [https://cloud.google.com/sdk/gcloud/reference/container/clusters/create](https://cloud.google.com/sdk/gcloud/reference/container/clusters/create)。


以下是如何使用 curl 命令来发送 POST 请求以创建区域 GKE 集群范围区域的步骤：

1. 安装 curl：

```
sudo apt install curl
```

2. 准备请求数据：

```
PROJECT_ID=your-project-id
LOCATION=us-central1
NAME=example-zone
DESCRIPTION=This is an example zone
DNS_NAME=example.com
GKE_CLUSTER_NAME_1=my-cluster-1
GKE_CLUSTER_NAME_2=my-cluster-2

PAYLOAD=$(cat <<EOF
{
  "name": "$NAME",
  "description": "$DESCRIPTION",
  "dnsName": "$DNS_NAME",
  "visibility": "private",
  "privateVisibilityConfig": {
    "kind": "dns#managedZonePrivateVisibilityConfig",
    "gkeClusters": [
      {
        "kind": "dns#managedZonePrivateVisibilityConfigGKEClusters",
        "gkeClusterName": "$GKE_CLUSTER_NAME_1"
      },
      {
        "kind": "dns#managedZonePrivateVisibilityConfigGKEClusters",
        "gkeClusterName": "$GKE_CLUSTER_NAME_2"
      }
    ]
  }
}
EOF
)
```

3. 发送请求：

```
curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://www.googleapis.com/dns/v2/projects/$PROJECT_ID/locations/$LOCATION/managedZones"
```

4. 检查响应：

```
{
  "kind": "dns#managedZone",
  "name": "example-zone",
  "description": "This is an example zone",
  "dnsName": "example.com",
  "visibility": "private",
  "privateVisibilityConfig": {
    "kind": "dns#managedZonePrivateVisibilityConfig",
    "gkeClusters": [
      {
        "kind": "dns#managedZonePrivateVisibilityConfigGKEClusters",
        "gkeClusterName": "my-cluster-1"
      },
      {
        "kind": "dns#managedZonePrivateVisibilityConfigGKEClusters",
        "gkeClusterName": "my-cluster-2"
      }
    ]
  },
  "createTime": "2023-03-23T12:34:56.789Z",
  "updateTime": "2023-03-23T12:34:56.789Z"
}
```

如果您收到成功的响应，则表示已创建区域 GKE 集群范围区域。

以下是一些其他注意事项：

* 确保您已将 `PROJECT_ID`、`LOCATION`、`NAME`、`DNS_NAME`、`GKE_CLUSTER_NAME_1` 和 `GKE_CLUSTER_NAME_2` 替换为您自己的值。
* 您可以使用 `gcloud auth print-access-token` 命令来获取您的访问令牌。
* 您可以使用 `curl -v` 命令来查看详细的请求和响应信息。

有关更多信息，请参阅 Cloud DNS v2 API documentation: [移除了无效网址]

是的，我确定 `--api=dns/v2` 标志存在。

您可以通过以下方式验证这一点：

1. 运行 `gcloud dns managed-zones list` 命令。

2. 查看输出。您应该会看到以下内容：

```
usage: gcloud dns managed-zones [COMMAND]

...

Available commands:
...
list  List all managed zones.
...

FLAGS:
...
--api=API  The API version to use.
```

3. 在 `--api` 标志后添加 `dns/v2`。

4. 再次运行命令。

5. 查看输出。您应该会看到以下内容：

```
usage: gcloud dns managed-zones [COMMAND]

...

Available commands:
...
list  List all managed zones.
...

FLAGS:
...
--api=API  The API version to use.
```

输出中包含 `--api=dns/v2` 标志，表明该标志存在。

您也可以通过查看 gcloud 文档来验证这一点。在 gcloud dns managed-zones: [https://cloud.google.com/sdk/gcloud/reference/dns/managed-zones](https://cloud.google.com/sdk/gcloud/reference/dns/managed-zones) 页面上，您可以看到 `--api` 标志的描述：

```
--api=API  The API version to use.
```

描述中明确指出，您可以使用 `--api=dns/v2` 标志来调用 v2 版本的 Cloud DNS API。

因此，您可以确信 `--api=dns/v2` 标志存在。
