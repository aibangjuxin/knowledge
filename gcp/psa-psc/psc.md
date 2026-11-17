- [Conditions](#conditions)
- [command](#command)
- [ask](#ask)
- [Process](#process)
  - [about gcloud compute network-endpoint-groups](#about-gcloud-compute-network-endpoint-groups)

# Conditions
- 实现VPC之间的互访，您需要在VPC1和VPC2中创建两个具有相同IP地址范围的PSC网络
  - PSC网络是一个私有网络，它没有自己的网关。PSC网络中的虚拟机只能通过PSC网络的IP地址来访问其他网络
  - eg:
    - 您可以在VPC1中创建一个名为 psc-network-1 的PSC网络，IP地址范围为 10.0.0.0/16。
    - 您可以在VPC2中创建一个名为 psc-network-2 的PSC网络，IP地址范围也为 10.0.0.0/16。
- 还需要确保VPC1和VPC2的IP地址范围不重叠
- eg: summary
```
在VPC1和VPC2中创建两个具有相同IP地址范围的PSC网络。
例如，您可以在VPC1中创建一个名为 psc-network-1 的PSC网络，IP地址范围为 10.0.0.0/16。
您可以在VPC2中创建一个名为 psc-network-2 的PSC网络，IP地址范围也为 10.0.0.0/16。
比如VPC1 IP地址范围为 192.168.1.0/24
比如VPC2 IP地址范围为 192.168.2.0/24
```

- 在VPC1中创建PSC网络：
```bash
gcloud compute networks create psc-network-1 \
--project=my-project \
--subnet-mode=custom \
--ip-range=10.0.0.0/16
```

- 在VPC2中创建PSC网络：
```bash
gcloud compute networks create psc-network-2 \
--project=my-project \
--subnet-mode=custom \
--ip-range=10.0.0.0/16
```
- 您可以使用以下命令获取 PSC 网关的 IP 地址：
```bash
gcloud compute networks describe psc-network-1 \
  --project=my-project \
  --flatten=true
```


- 创建路由的命令：

- 在VPC1中创建路由：
```bash
gcloud compute routes create route-to-vpc2 \
--project=my-project \
--destination-range=192.168.2.0/24 \
--next-hop-address=10.0.0.2 \
--next-hop-type=PSC
```

- 在VPC2中创建路由：
```bash
gcloud compute routes create route-to-vpc1 \
--project=my-project \
--destination-range=192.168.1.0/24 \
--next-hop-address=10.0.0.2 \
--next-hop-type=PSC
```

请注意，您需要将 my-project 替换为您自己的项目ID。

您还需要确保在每个VPC中创建的PSC网络具有相同的IP地址范围。

您还需要确保VPC1和VPC2的IP地址范围不重叠。

完成这些设置后，VPC1中的虚拟机就可以访问VPC2中的服务网络，VPC2中的虚拟机也可以访问VPC1中的服务网络

在VPC1和VPC2中创建PSC网络以及相应的路由的命令如下：

在VPC1中创建PSC网络和路由：

```bash
gcloud compute networks create psc-network-1 \
    --project=my-project \
    --subnet-mode=custom \
    --ip-range=10.0.0.0/16

gcloud compute routes create route-to-vpc2 \
    --project=my-project \
    --network=psc-network-1 \
    --destination-range=192.168.2.0/24 \
    --next-hop-address=10.0.0.2 \
    --next-hop-type=PSC
```

在VPC2中创建PSC网络和路由：

```bash
gcloud compute networks create psc-network-2 \
    --project=my-project \
    --subnet-mode=custom \
    --ip-range=10.0.0.0/16

gcloud compute routes create route-to-vpc1 \
    --project=my-project \
    --network=psc-network-2 \
    --destination-range=192.168.1.0/24 \
    --next-hop-address=10.0.0.2 \
    --next-hop-type=PSC
```

请注意，上述命令中的 `--next-hop-address=10.0.0.2` 是一个示例，您需要将其替换为实际的PSC地址。确保在两个VPC中设置正确的PSC地址，以便路由正常工作。

实际的 PSC 地址是 PSC 网关的 IP 地址。PSC 网关是连接两个 VPC 的虚拟设备。

您可以使用以下命令获取 PSC 网关的 IP 地址：

```
gcloud compute networks describe psc-network-1 \
  --project=my-project \
  --flatten=true
```

该命令将显示 PSC 网络的详细信息，包括网关的 IP 地址。

在上述示例中，PSC 网关的 IP 地址为 `10.0.0.2`。因此，您需要将 `-next-hop-address` 参数设置为 `10.0.0.2`，以便两个 VPC 可以相互通信。

如果您的 PSC 有一个具体的范围，则您需要将 `-next-hop-address` 参数设置为该范围中的任意一个 IP 地址。例如，如果您的 PSC 范围为 `10.0.0.0/24`，则您可以将 `-next-hop-address` 参数设置为 `10.0.0.1` 或 `10.0.0.2`。

以下是使用 PSC 范围的示例：

```
gcloud compute routes create route-to-vpc2 \
  --project=my-project \
  --network=psc-network-1 \
  --destination-range=192.168.2.0/24 \
  --next-hop-address=10.0.0.1 \
  --next-hop-type=PSC
```

该命令将创建一个路由，将 VPC1 中的所有流量转发到 PSC 网关 `10.0.0.1`。这些流量将被 PSC 网关转发到 VPC2。

请注意，在使用 PSC 范围时，您需要确保 PSC 网关位于该范围内。


对于 `--next-hop-address` 参数，您需要设置为您在每个VPC中用作PSC的实际地址。通常，PSC（Peer/Service Controller）的地址应该是特定子网中的某个IP地址。

如果您的PSC应该是一个IP地址范围，而不是单个地址，您可能需要指定一个具体的IP地址，例如子网的第一个可用IP。您可以使用以下步骤来获取每个VPC中PSC的地址：

1. 登录到相应的Google Cloud Console。
2. 转到相应的VPC网络。
3. 查找用作PSC的子网。
4. 获取该子网的第一个可用IP地址，通常是 x.x.x.2。

例如，在VPC1中：

```bash
gcloud compute networks subnets describe subnet-1 \
    --project=my-project \
    --region=your-region
```

在输出中，找到 `firstUsableIp` 字段，该字段显示子网的第一个可用IP地址。将此IP地址用作VPC1中PSC的地址。

在VPC2中执行相似的步骤，将子网的第一个可用IP地址用作VPC2中PSC的地址。

然后，将这些实际的PSC地址替换到相应的路由命令中的 `--next-hop-address` 参数中。


# command 
- gcloud compute networks peerings list

- [x] gcloud compute endpoints services create 
# ask 
想要使用**私有服务连接（PSC）**在Google Cloud中连接不同的GKE集群。PSC是一种网络功能，可以让消费者在其VPC网络内部私密地访问托管服务，同时也可以让托管服务提供者在其自己的VPC网络中提供私密连接给消费者。使用PSC，消费者可以使用自己的内部IP地址访问服务，而不需要离开其VPC网络或使用外部IP地址。流量完全保留在Google Cloud内部¹。
要使用PSC在Google Cloud中连接不同的GKE集群，您需要完成以下步骤：
1. 在两个不同的项目中创建两个VPC网络，分别作为服务提供者和服务消费者。您可以使用gcloud compute networks create命令创建VPC网络²。
2. 在每个VPC网络中创建一个GKE集群。您可以使用gcloud container clusters create命令创建GKE集群³。
3. 在服务提供者的GKE集群中部署一个应用，并使用内部负载均衡器将其暴露给VPC网络。您可以使用kubectl apply命令部署应用，并使用service.beta.kubernetes.io/load-balancer-type: "Internal"注解创建内部负载均衡
4. 在服务提供者的VPC网络中创建一个服务附件，将内部负载均衡器的IP地址与PSC绑定。您可以使用gcloud compute service-attachments create命令创建服务附件。
   1. https://cloud.google.com/sdk/gcloud/reference/compute/service-attachments/create
      1. gcloud compute service-attachments create命令创建服务附件
         1. cloud compute service-attachments create --network-endpoint-group <service-attachment> --network <vpc-network> --network-endpoint-ip-addresses <internal-ip-address>
         2. 例如：gcloud compute service-attachments create --network-endpoint-group my-service-attachment --network my-vpc-network --network-endpoint-ip-addresses 10.128.0.100
      2. 使用gcloud compute service-attachments describe命令查看服务附件的状态
      3. 使用gcloud compute service-attachments list命令查看服务附件列表
         1. gcloud compute service-attachments list
5. 在服务消费者的VPC网络中创建一个端点，指定服务附件的ID和一个内部IP地址
      1. gcloud services enable privateconnect.googleapis.com 
    * 创建服务消费者的VPC网络中的端点
      * 在服务消费者的VPC网络中创建端点
        * 使用 gcloud compute addresses 命令
        * gcloud compute forwarding-rules 命令
          1. **获取服务附件的IP地址**：
             首先，使用以下命令获取服务附件的IP地址。请替换`SERVICE-ATTACHMENT-NAME`为您之前创建的服务附件的名称。
             ```bash
             SERVICE_ATTACHMENT_IP=$(gcloud compute service-attachments describe SERVICE-ATTACHMENT-NAME --global --format="value(address)")
             ```
          2. **创建端点**：
             使用以下命令创建服务消费者的VPC网络中的端点。请替换`ENDPOINT-NAME`为端点的名称，`SERVICE-ATTACHMENT-IP`为上一步获取的服务附件的IP地址。
             ```bash
             gcloud compute addresses create ENDPOINT-NAME --global --addresses=$SERVICE_ATTACHMENT_IP
             ```
             - `ENDPOINT-NAME`: 指定端点的名称。
          3. **创建端口转发规则**：
             使用以下命令创建端口转发规则：
             ```bash
             gcloud compute forwarding-rules create FORWARDING-RULE-NAME \
               --ip-protocol TCP \
               --ports=80 \
               --target-pool=TARGET-POOL-NAME \
               --load-balancing-scheme INTERNAL \
               --region=REGION
             ```
             - `FORWARDING-RULE-NAME`: 指定端口转发规则的名称。
             - `TARGET-POOL-NAME`: 指定 GKE 集群中的目标池的名称。
             - `REGION`: GKE 集群所在的地区。
          4. **验证端口转发规则的创建**：
             使用以下命令验证端口转发规则的创建状态：
             ```bash
             gcloud compute forwarding-rules describe FORWARDING-RULE-NAME --region=REGION
             ```
6. 在VPC1中创建一条路由：在VPC2中创建一条路由：?
   1. vpc1 create route 
    ```bash
        gcloud compute routes create route-to-vpc2 \
        --project=my-project \
        --destination-range=10.1.0.0/16 \
        --next-hop-address=10.0.0.2 \
        --next-hop-type=PSC
    ```
    2. vpc2 create route 
    ```bash
    gcloud compute routes create route-to-vpc1 \
    --project=my-project \
    --destination-range=10.0.0.0/16 \
    --next-hop-address=10.1.0.2 \
    --next-hop-type=PSC
    ```
    3. About Route 
    ```
    路由值是用来告诉虚拟机如何将数据包路由到其他网络的。路由值通常包括以下几个部分：

    目标地址范围：这是你要路由到哪个网络的IP地址范围。
    下一跳地址：这是路由器将数据包发送到的下一个IP地址。
    下一跳类型：这是路由器使用哪种方式将数据包发送到下一跳地址。
    在您提供的示例中，路由值如下：

    在VPC1中创建的路由：

    目标地址范围：10.1.0.0/16
    下一跳地址：10.0.0.2
    下一跳类型：PSC
    在VPC2中创建的路由：

    目标地址范围：10.0.0.0/16
    下一跳地址：10.1.0.2
    下一跳类型：PSC
    这些路由值的要求如下：

    目标地址范围必须是你要路由到的网络的IP地址范围。
    下一跳地址必须是路由器能够访问的IP地址。
    下一跳类型必须是路由器支持的类型。
    在您的示例中，目标地址范围是VPC2的IP地址范围，下一跳地址是PSC网络的IP地址，下一跳类型是PSC。

    这是因为您使用PSC网络将VPC1和VPC2连接起来，所以您需要使用PSC作为下一跳类型。

    请注意，您需要确保在每个VPC中创建的PSC网络具有相同的IP地址范围。

    您还需要确保VPC1和VPC2的IP地址范围不重叠。
    ```

请确保替换命令中的占位符为实际的配置。这样就完成了在服务消费者的VPC网络中创建端点和端口转发规则的步骤。如果有任何问题或需要进一步的帮助，请随时告诉我。  


      ```bash
      gcloud compute addresses create ENDPOINT-IP --global
      ```
    * 创建 Compute Engine 网络端点组
        * gcloud compute network-endpoint-groups create
        * https://cloud.google.com/sdk/gcloud/reference/compute/network-endpoint-groups/create
1. 在服务消费者的GKE集群中部署一个应用，使用端点的IP地址作为目标地址访问服务提供者的应用。您可以使用kubectl apply命令部署应用，并使用kubectl exec命令测试连接。
2. gcloud compute endpoints no exist 

# Process
1. Create two VPC networks in two different projects using the `gcloud compute networks create` command.
2. Create two GKE clusters in the two VPC networks using the `gcloud container clusters create` command.
3. Deploy an application in the service provider's GKE cluster and expose it using an internal load balancer. You can use the `kubectl apply` command to deploy the application and use the `service.beta.kubernetes.io/load-balancer-type:
4. Create a service attachment in the service provider's VPC network and bind the internal load balancer's IP address to the PSC. You can use the `gcloud compute service-attachments create` command to create the service attachment.
    4.1 
5. Create an endpoint in the service consumer's VPC network and specify the service attachment's ID and an internal IP address. You can use the `gcloud compute network-endpoint-groups` command to create the endpoint.
    5.1 gcloud compute network-endpoint-groups read and manipulate Compute Engine network endpoint groups 读取和操作计算引擎
        网络端点组




## about gcloud compute network-endpoint-groups 

命令 `gcloud compute network-endpoint-groups` 用于管理 Google Cloud 中的网络端点组 (NEG)。NEG 是一种配置对象，它指定一组后端端点或服务。使用 NEG，Google Cloud 负载均衡器可以为虚拟机 (VM) 实例组、无服务器工作负载和容器化工作负载提供服务。

该命令的具体用途取决于您使用它的选项。例如，您可以使用该命令来：

* 创建 NEG
* 列出 NEG
* 更新 NEG
* 删除 NEG

以下是一些示例：

```
# 创建一个 NEG
gcloud compute network-endpoint-groups create my-neg --network my-vpc --target-ports 80,443

# 列出所有 NEG
gcloud compute network-endpoint-groups list

# 更新一个 NEG 的目标端点
gcloud compute network-endpoint-groups update my-neg --target-instances my-instance-1,my-instance-2

# 删除一个 NEG
gcloud compute network-endpoint-groups delete my-neg
```

有关 `gcloud compute network-endpoint-groups` 命令的更多信息，请参阅 Google Cloud 文档: [https://cloud.google.com/sdk/gcloud/reference/compute/network-endpoint-groups](https://cloud.google.com/sdk/gcloud/reference/compute/network-endpoint-groups)。

