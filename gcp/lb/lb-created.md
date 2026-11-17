GCP 中创建一个类型为网络代理(network proxy)、访问类型为外部(external)、协议为 TCP 的负载均衡器,可以使用的详细命令
应该先创建健康检查，然后创建后端服务，然后将后端实例组添加到后端服务，最后创建转发规则并将其绑定到后端服务。


应该先创建健康检查，然后创建后端服务，然后将后端实例组添加到后端服务，最后创建转发规则并将其绑定到后端服务


你说的没错，应该先创建健康检查，然后创建后端服务，然后将后端实例组添加到后端服务，最后创建转发规则并将其绑定到后端服务。
以下是创建类型为网络代理、访问类型为外部、协议为 TCP 的负载均衡器的详细步骤：
1. 创建健康检查。
gcloud compute health-checks create my-health-check \
  --type=TCP \
  --port=80 \
  --timeout=5s \
  --interval=10s \
  --healthy-threshold=2 \
  --unhealthy-threshold=2
2. 创建后端服务。
gcloud compute backend-services create my-backend-service \
  --protocol=TCP \
  --port=80 \
  --health-checks=my-health-check
3. 将后端实例组添加到后端服务。
gcloud compute backend-services add-backend my-backend-service \
  --instance-group=my-instance-group \
  --instance-count=3
4. 创建转发规则并将其绑定到后端服务。
gcloud compute forwarding-rules create my-forwarding-rule \
  --load-balancer=my-load-balancer \
  --protocol=TCP \
  --port-range=80-80 \
  --target-pool=my-target-pool
我希望这对你有帮助。


Here are the steps to create a TCP load balancer with type network proxy and access type external in GCP:

1. Create a health check:

```
gcloud compute health-checks create tcp my-health-check --port 80
```

2. Create a backend service: 

```
gcloud compute backend-services create my-backend-service --protocol TCP --health-checks my-health-check  
```

3. Add backend instances to the backend service:

```
gcloud compute backend-services add-backend my-backend-service --instance-group my-instance-group --instance-group-zone us-central1-a
```

4. Create a global forwarding rule: 

```
gcloud compute forwarding-rules create my-forwarding-rule --load-balancing-scheme external --ports 80 --global --target-service my-backend-service
```

This will create a global TCP load balancer with a health check on port 80, a backend service, an instance group as the backend, and a global forwarding rule to route traffic to the backend service.

The --global flag makes it an external load balancer. Omitting that flag would create an internal load balancer.




在GCP中使用gcloud命令行工具创建一个类型为网络代理(network proxy)、访问类型为外部(external)、协议为TCP的负载均衡器，需要按照以下步骤进行。您提到的步骤是正确的，我们将按照这个顺序进行创建。

1. 创建健康检查：
```bash
gcloud compute health-checks create tcp <HEALTH_CHECK_NAME> \
    --port=<HEALTH_CHECK_PORT> \
    --global
```
请将 `<HEALTH_CHECK_NAME>` 替换为您希望为健康检查指定的名称， `<HEALTH_CHECK_PORT>` 替换为您希望用于健康检查的端口号。

2. 创建后端服务：
```bash
gcloud compute backend-services create <BACKEND_SERVICE_NAME> \
    --protocol=TCP \
    --health-checks=<HEALTH_CHECK_NAME> \
    --global
```
请将 `<BACKEND_SERVICE_NAME>` 替换为您希望为后端服务指定的名称。

3. 将后端实例组添加到后端服务：
```bash
gcloud compute backend-services add-backend <BACKEND_SERVICE_NAME> \
    --instance-group=<INSTANCE_GROUP_NAME> \
    --instance-group-zone=<INSTANCE_GROUP_ZONE> \
    --global
```
请将 `<INSTANCE_GROUP_NAME>` 替换为您希望添加到后端服务的实例组的名称， `<INSTANCE_GROUP_ZONE>` 替换为实例组所在的区域。

4. 创建转发规则并将其绑定到后端服务：
```bash
gcloud compute forwarding-rules create <FORWARDING_RULE_NAME> \
    --load-balancing-scheme=EXTERNAL \
    --network-tier=PREMIUM \
    --address=<EXTERNAL_IP_ADDRESS> \
    --ports=<PORT_RANGE> \
    --backend-service=<BACKEND_SERVICE_NAME> \
    --global
```
请将 `<FORWARDING_RULE_NAME>` 替换为您希望为转发规则指定的名称， `<EXTERNAL_IP_ADDRESS>` 替换为外部IP地址， `<PORT_RANGE>` 替换为您希望公开的端口范围，`<BACKEND_SERVICE_NAME>` 替换为前面创建的后端服务名称。

完成这些步骤后，您应该成功地在GCP中创建了一个类型为网络代理、访问类型为外部、协议为TCP的负载均衡器。请注意，某些步骤可能需要一些时间来完成，特别是在后端实例组添加到后端服务后，负载均衡器需要时间来确认这些实例组的健康状态。

