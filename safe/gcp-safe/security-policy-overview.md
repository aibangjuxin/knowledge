- [reference](#reference)
  - [detail process](#detail-process)
    - [need todo Testing](#need-todo-testing)
  - [explain chatgpt](#explain-chatgpt)
    - [1. 创建后端服务](#1-创建后端服务)
    - [2. 添加后端实例](#2-添加后端实例)
    - [3. 更新后端服务的安全策略](#3-更新后端服务的安全策略)
    - [4. 创建URL映射](#4-创建url映射)
    - [5. 创建目标HTTPS代理](#5-创建目标https代理)
    - [6. 创建转发规则](#6-创建转发规则)
  - [Claude2](#claude2)
  - [Google Bard](#google-bard)
- [need prepare](#need-prepare)
  - [Detail introduction](#detail-introduction)
# reference
https://cloud.google.com/armor/docs/security-policy-overview
The following diagram illustrates the location of global external Application Load Balancers, classic Application Load Balancers, the Google network, and Google data centers.
https://cloud.google.com/static/armor/images/ip-bl-wl-1.svg
The following diagram illustrates the location of global external Application Load Balancers, classic Application Load Balancers, the Google network, and Google data centers.

## detail process 
- [x] gcloud compute backend-services create lex-test-mycomponent-https-cloud-armor --global --protocol HTTPS --port-name=mycomponentport --health-checks dev-testenv-mycomponent-be-4bd7-tcp-healthcheck --load-balancing-scheme EXTERNAL --timeout=30s --connection-draining-timeout 60s --project aibang-myid-dufu-dev-
- [x] gcloud compute backend-services add-backend lex-test-mycomponent-https-cloud-armor --global --instance-group dev-testenv-mycomponentlextest-mig-30jo --instance-group-zone=asia-east2-a
- [x] gcloud compute backend-services update lex-test-mycomponent-https-cloud-armor --security-policy aibang-myid-dufu-dev-httpsmycomponent-armor-policy --global
- [x] gcloud compute url-maps create dev-testenv-lextest-mycomponent-https --default-service=lex-test-mycomponent-https-cloud-armor --project aibang-myid-dufu-dev
- [x] gcloud compute target-https-proxies create dev-testenv-mycomponent-lextest-https-proxy --ssl-certificates=dev-testenv-glb-fuww-cert-20230323 --global --url-map=dev-testenv-lextest-mycomponent-https --global-url-map --project aibang-myid-dufu-dev
- [x] gcloud compute forwarding-rules create mycomponentlextest --ports=443   --target-https-proxy=dev-testenv-mycomponent-lextest-https-proxy --load-balancing-scheme=EXTERNAL --global

### need todo Testing 
gcloud compute forwarding-rules create mycomponentlextest --ports=443   --target-https-proxy=dev-testenv-mycomponent-lextest-https-proxy --load-balancing-scheme=INTERNAL --global

要将转发规则限制为仅供您内部的 share VPC 网络访问，您可以使用 --network 参数指定您的 share VPC 网络。以下是一个示例：

gcloud compute forwarding-rules create mycomponentlextest --ports=443   --target-https-proxy=dev-testenv-mycomponent-lextest-https-proxy --load-balancing-scheme=INTERNAL --network=my-share-vpc-network --global

如果仅仅凭命令的指定的EXTERNAL或者INTERNAL, 那么看起来我最终forwarding-rules的地址是?  能否成功也是一个问题?这样其实更有利于去理解public IP Addresses

使用了 load-balancing-scheme 设置为 INTERNAL 的转发规则，因此您的 share VPC 网络将获得一个内部 IP 地址


创建的 backend-service 和 target-https-proxy 都是设置为 EXTERNAL 的，因此可以通过互联网访问。如果您将 load-balancing-scheme 设置为 INTERNAL，则转发规则将仅在内部 VPC 网络中可用

gcloud compute forwarding-rules create mycomponentlextest --ports=443  --target-https-proxy=dev-testenv-mycomponent-lextest-https-proxy --load-balancing-scheme=INTERNAL --global

## explain chatgpt

这些命令是使用Google Cloud Platform (GCP)的gcloud命令行工具进行的操作，用于配置和管理负载均衡和HTTPS终端的相关服务。以下是对每个命令的详细解释：

### 1. 创建后端服务
```bash
gcloud compute backend-services create lex-test-mycomponent-https-cloud-armor --global --protocol HTTPS --port-name=mycomponentport --health-checks dev-testenv-mycomponent-be-4bd7-tcp-healthcheck --load-balancing-scheme EXTERNAL --timeout=30s --connection-draining-timeout 60s --project aibang-myid-dufu-dev-

gcloud compute backend-services create ""$backend-services-Name"" \
    --load-balancing-scheme=internal \
    --protocol=tcp \
    --region=$region \
    --health-checks=""$healthname"" \
    --global-health-checks \
    --project=$project \
    --network=$network
```

- `gcloud compute backend-services create`: 这个命令用于创建一个后端服务。
- `lex-test-mycomponent-https-cloud-armor`: 这是服务的名称。
- `--global`: 指定这个服务是全局服务，可以跨多个区域使用。
- `--protocol HTTPS`: 指定使用HTTPS协议。
- `--port-name=mycomponentport`: 指定端口的名称为"mycomponentport"。
- `--health-checks dev-testenv-mycomponent-be-4bd7-tcp-healthcheck`: 指定健康检查的名称，用于确定后端实例的健康状态。
- `--load-balancing-scheme EXTERNAL`: 指定负载均衡方案为EXTERNAL，即通过公网访问。
- `--timeout=30s`: 指定连接的超时时间为30秒。
- `--connection-draining-timeout 60s`: 指定连接排空的超时时间为60秒。
- `--project aibang-myid-dufu-dev-`: 指定项目名称。
- `--network 注意这里可能需要指定网络，否则应该是有一个默认的网络配置,但是应该会有global和internal的区别的时候是否需要选择这个network?
    eg: network=projects/$project/global/networks/aibang-beta-cidmz

### 2. 添加后端实例
```bash
gcloud compute backend-services add-backend lex-test-mycomponent-https-cloud-armor --global --instance-group dev-testenv-mycomponentlextest-mig-30jo --instance-group-zone=asia-east2-a

gcloud compute backend-services add-backend ""$backend-services-Name"" \
    --instance-group-region=$region \
    --instance-group=""$groupName"" \
    --project=$project
```

- `gcloud compute backend-services add-backend`: 这个命令用于将后端实例添加到后端服务。
- `lex-test-mycomponent-https-cloud-armor`: 后端服务的名称。
- `--global`: 指定后端服务是全局服务。
- `--instance-group dev-testenv-mycomponentlextest-mig-30jo`: 指定要添加的后端实例组。
- `--instance-group-zone=asia-east2-a`: 指定后端实例组所在的区域。

### 3. 更新后端服务的安全策略
```bash
gcloud compute backend-services update lex-test-mycomponent-https-cloud-armor --security-policy aibang-myid-dufu-dev-httpsmycomponent-armor-policy --global
```

- `gcloud compute backend-services update`: 这个命令用于更新后端服务的配置。
- `lex-test-mycomponent-https-cloud-armor`: 后端服务的名称。
- `--security-policy aibang-myid-dufu-dev-httpsmycomponent-armor-policy`: 指定安全策略的名称，用于控制访问后端服务的安全规则。
- `--global`: 指定后端服务是全局服务。

### 4. 创建URL映射
```bash
gcloud compute url-maps create dev-testenv-lextest-mycomponent-https --default-service=lex-test-mycomponent-https-cloud-armor --project aibang-myid-dufu-dev
```

- `gcloud compute url-maps create`: 这个命令用于创建一个URL映射。
- `dev-testenv-lextest-mycomponent-https`: 指定URL映射的名称。
- `--default-service=lex-test-mycomponent-https-cloud-armor`: 指定默认的服务，即请求将被路由到的后端服务。
- `--project aibang-myid-dufu-dev`: 指定项目名称。

### 5. 创建目标HTTPS代理
```bash
gcloud compute target-https-proxies create dev-testenv-mycomponent-lextest-https-proxy --ssl-certificates=dev-testenv-glb-fuww-cert-20230323 --global --url-map=dev-testenv-lextest-mycomponent-https --global-url-map --project aibang-myid-dufu-dev
```

- `gcloud compute target-https-proxies create`: 这个命令用于创建目标HTTPS代理。
- `dev-testenv-mycomponent-lextest-https-proxy`: 指定代理的名称。
- `--ssl-certificates=dev-testenv-glb-fuww-cert-20230323`: 指定SSL证书的名称，用于加密HTTPS流量。
- `--global`: 指定代理是全局的，可以在全球范围内使用。
- `--url-map=dev-testenv-lextest-mycomponent-https`: 指定URL映射，用于路由请求。
- `--global-url-map`: 指定URL映射是全局的。
- `--project aibang-myid-dufu-dev`: 指定项目名称。

### 6. 创建转发规则
```bash
gcloud compute forwarding-rules create mycomponentlextest --ports=443 --target-https-proxy=dev-testenv-mycomponent-lextest-https-proxy --load-balancing-scheme=EXTERNAL --global

gcloud compute forwarding-rules create $frName  --project $project \
    --region=$region \
    --load-balancing-scheme=internal \
    --subnet=$subnetwork \
    --ip-protocol=TCP \
    --ports=$ilbPort \
    --backend-service=$backend-services-Name \
    --backend-service-region=$region \
    --service-label=$seviceLabel
```

- `gcloud compute forwarding-rules create`: 这个命令用于创建转发规则。
- `mycomponentlextest`: 指定规则的名称。
- `--ports=443`: 指定端口号为443，用于接收HTTPS流量。
- `--target-https-proxy=dev-testenv-mycomponent-lextest-https-proxy`: 指定目标HTTPS代理，将流量路由到后端服务。
- `--load-balancing-scheme=EXTERNAL`: 指定负载均衡方案为EXTERNAL，即通过公网访问。是否可以internal ==> Direct to my Shared vpc network ?
- `--global`: 指定规则是全局的。
- `subnet` 这里有这个参数其实是可以供选择的？那么我是否可以将创建的规则直接应用到我的shared VPC network ？
这些命令一起配置了一个负载均衡的HTTPS终端，用于处理HTTPS请求并将其路由到后端服务。这个配置允许全球范围内的访问，并提供了安全策略的控制。


## Claude2
好的,我来详细解释一下这6条gcloud命令:

1. 创建一个名为lex-test-mycomponent-https-cloud-armor的全局HTTPS协议的后端服务,指定健康检查和负载均衡方式。

2. 将后端服务lex-test-mycomponent-https-cloud-armor加入一个名为dev-testenv-mycomponentlextest-mig-30jo的托管实例组作为后端主机池,指定其在asia-east2-a区。

3. 更新后端服务lex-test-mycomponent-https-cloud-armor,为其添加安全策略dev-testenv-httpsmycomponent-armor-policy。

4. 创建一个名为dev-testenv-lextest-mycomponent-https的URL映射,默认指向前面创建的后端服务。

5. 创建一个名为dev-testenv-mycomponent-lextest-https-proxy的全局目标HTTPS代理,绑定证书、URL映射。

6. 创建一个名为mycomponentlextest的全局转发规则,端口为443,目标为之前创建的代理,加载均衡方式为外部方式。

这样通过后端服务、URL映射、目标代理和转发规则构建起了一个负载均衡功能,提供了全局的HTTPS访问。请确定我的解释是否准确。如有需要补充的部分请告知。


## Google Bard
以下是您提供的6条命令的详细解释：


gcloud compute backend-services create lex-test-mycomponent-https-cloud-armor --global --protocol HTTPS --port-name=mycomponentport --health-checks dev-testenv-mycomponent-be-4bd7-tcp-healthcheck --load-balancing-scheme EXTERNAL --timeout=30s --connection-draining-timeout 60s --project aibang-myid-dufu-dev-


这条命令用于创建一个名为 `lex-test-mycomponent-https-cloud-armor` 的后端服务。该服务使用 HTTPS 协议，端口名为 `mycomponentport`，健康检查为 `dev-testenv-mycomponent-be-4bd7-tcp-healthcheck`，负载均衡方案为 EXTERNAL，超时时间为 30 秒，连接耗尽超时时间为 60 秒。


gcloud compute backend-services add-backend lex-test-mycomponent-https-cloud-armor --global --instance-group dev-testenv-mycomponentlextest-mig-30jo --instance-group-zone=asia-east2-a


这条命令用于将名为 `dev-testenv-mycomponentlextest-mig-30jo` 的实例组添加到 `lex-test-mycomponent-https-cloud-armor` 后端服务中。该实例组位于 `asia-east2-a` 区域。


gcloud compute backend-services update lex-test-mycomponent-https-cloud-armor --security-policy aibang-myid-dufu-dev-httpsmycomponent-armor-policy --global


这条命令用于将 `aibang-myid-dufu-dev-httpsmycomponent-armor-policy` 安全策略应用到 `lex-test-mycomponent-https-cloud-armor` 后端服务中。


gcloud compute url-maps create dev-testenv-lextest-mycomponent-https --default-service=lex-test-mycomponent-https-cloud-armor --project aibang-myid-dufu-dev


这条命令用于创建一个名为 `dev-testenv-lextest-mycomponent-https` 的 URL 映射。该 URL 映射的默认服务为 `lex-test-mycomponent-https-cloud-armor` 后端服务。


gcloud compute target-https-proxies create dev-testenv-mycomponent-lextest-https-proxy --ssl-certificates=dev-testenv-glb-fuww-cert-20230323 --global --url-map=dev-testenv-lextest-mycomponent-https --global-url-map --project aibang-myid-dufu-dev


这条命令用于创建一个名为 `dev-testenv-mycomponent-lextest-https-proxy` 的目标 HTTPS 代理。该代理使用 `dev-testenv-glb-fuww-cert-20230323` SSL 证书，并将用户流量转发到 `dev-testenv-lextest-mycomponent-https` URL 映射中指定的默认服务。


gcloud compute forwarding-rules create mycomponentlextest --ports=443  --target-https-proxy=dev-testenv-mycomponent-lextest-https-proxy --load-balancing-scheme=EXTERNAL --global


这条命令用于创建一个名为 `mycomponentlextest` 的转发规则。该规则将端口 443 上的流量转发到 `dev-testenv-mycomponent-lextest-https-proxy` 目标 HTTPS 代理中。负载均衡方案为 EXTERNAL，意味着该规则将流量负载均衡到实例组中。

总而言之，这6条命令用于创建一个完整的负载均衡器，用于将用户流量转发到后端服务 `lex-test-mycomponent-https-cloud-armor` 中。该服务使用 HTTPS 协议，并受 `aibang-myid-dufu-dev-httpsmycomponent-armor-policy` 安全策略的保护。




# need prepare 
我想要创建一个GCP工程里面的security policy 也就是cloud armor 。而且这个是基于HTTPS的backend services . 对于我的这个创建要求我需要了解创建的顺序都有哪些？
- 比如instance group
- target-https-proxy
  - URL Map
  - ssl-certificates
- forwarding-rules
- backend-services
- Health check 
## Detail introduction
要创建基于HTTPS的后端服务的安全策略（Cloud Armor）并配置相关资源，你需要按照以下顺序进行创建：

1. 创建实例组（Instance Group）：这是你的后端服务的集合，可以是虚拟机实例组、容器实例组或网络终点组（NEG）。

2. 创建URL映射（URL Map）：URL映射将传入的请求映射到后端服务。你可以定义路径匹配规则、代理规则和重定向规则等。

3. 创建目标HTTPS代理（Target HTTPS Proxy）：目标HTTPS代理终止传入的HTTPS请求，并将其转发到后端服务。

4. 配置SSL证书（SSL Certificates）：如果你的HTTPS代理需要使用SSL/TLS加密，你需要为该代理配置相应的SSL证书。

5. 创建转发规则（Forwarding Rules）：转发规则定义了传入请求的入口点，并指定了目标HTTPS代理。

6. 创建后端服务（Backend Services）：在后端服务中，你可以指定实例组、负载均衡策略、会话保持等配置。

7. 创建健康检查（Health Check）：健康检查用于验证后端服务的可用性和状态。你可以选择HTTP或HTTPS协议进行健康检查。

创建这些资源的顺序可以确保它们之间的依赖关系得到满足。请注意，具体的创建步骤可能因为你的特定要求和GCP控制台的更新而有所变化。在创建这些资源之前，你应该熟悉GCP文档中相关服务的详细配置和选项，以确保你的安全策略能够按预期工作。

当创建GCP工程中的Cloud Armor安全策略时，以下是每个步骤的详细创建命令和参数，以及对每个参数的解释：

1. 创建实例组（Instance Group）：
```
gcloud compute instance-groups managed create INSTANCE_GROUP_NAME \
    --size=SIZE \
    --template=INSTANCE_TEMPLATE
```
- `INSTANCE_GROUP_NAME`：实例组的名称。
- `SIZE`：实例组的大小，即包含的实例数量。
- `INSTANCE_TEMPLATE`：实例组所使用的实例模板。

2. 创建URL映射（URL Map）：
```
gcloud compute url-maps create URL_MAP_NAME \
    --default-service=BACKEND_SERVICE
```
- `URL_MAP_NAME`：URL映射的名称。
- `BACKEND_SERVICE`：默认的后端服务，即转发请求的目标。

3. 创建目标HTTPS代理（Target HTTPS Proxy）：
```
gcloud compute target-https-proxies create TARGET_HTTPS_PROXY_NAME \
    --url-map=URL_MAP_NAME \
    --ssl-certificates=SSL_CERTIFICATE
```
- `TARGET_HTTPS_PROXY_NAME`：目标HTTPS代理的名称。
- `URL_MAP_NAME`：目标HTTPS代理绑定的URL映射。
- `SSL_CERTIFICATE`：用于SSL/TLS加密的SSL证书。

4. 配置SSL证书（SSL Certificates）：
```
gcloud compute ssl-certificates create SSL_CERTIFICATE_NAME \
    --certificate=CERTIFICATE_FILE \
    --private-key=PRIVATE_KEY_FILE
```
- `SSL_CERTIFICATE_NAME`：SSL证书的名称。
- `CERTIFICATE_FILE`：SSL证书文件的路径。
- `PRIVATE_KEY_FILE`：私钥文件的路径。

5. 创建转发规则（Forwarding Rules）：
```
gcloud compute forwarding-rules create FORWARDING_RULE_NAME \
    --target-https-proxy=TARGET_HTTPS_PROXY_NAME \
    --ports=PORT_RANGE
```
- `FORWARDING_RULE_NAME`：转发规则的名称。
- `TARGET_HTTPS_PROXY_NAME`：转发规则绑定的目标HTTPS代理。
- `PORT_RANGE`：转发规则监听的端口范围。

6. 创建后端服务（Backend Services）：
```
gcloud compute backend-services create BACKEND_SERVICE_NAME \
    --protocol=PROTOCOL \
    --health-checks=HEALTH_CHECK_NAME \
    --global
gcloud compute backend-services create BACKEND_SERVICE_NAME \
    --global \
    --protocol HTTPS \
    --port 443 \
    --health-checks HEALTH_CHECK_NAME \
    --load-balancing-scheme INTERNAL_SELF_MANAGED \
    --timeout=60s \
    --connection-draining-timeout 60s

以下是上述命令中各参数的解释和示例：

- `BACKEND_SERVICE_NAME`：您要创建的后端服务的名称。

- `--global`：指定后端服务是全局的，这意味着它可以在多个区域使用。

- `--protocol HTTPS`：指定协议为 HTTPS。

- `--port 443`：指定端口号为 443，这是 HTTPS 默认的端口。

- `--health-checks HEALTH_CHECK_NAME`：指定与后端服务关联的健康检查的名称。您需要事先创建一个健康检查并将其名称替换为 `HEALTH_CHECK_NAME`。

- `--load-balancing-scheme INTERNAL_SELF_MANAGED`：指定负载均衡方案为 INTERNAL_SELF_MANAGED。这适用于内部负载均衡。

- `--timeout=60s`：指定超时时间为 60 秒。

- `--connection-draining-timeout 60s`：指定连接排放超时时间为 60 秒。

请替换 `BACKEND_SERVICE_NAME` 和 `HEALTH_CHECK_NAME` 为您的实际名称。执行此命令后，您将创建一个名为 `BACKEND_SERVICE_NAME` 的 HTTPS 后端服务，该服务将根据配置的健康检查与负载均衡器一起使用。
```
- `BACKEND_SERVICE_NAME`：后端服务的名称。
- `PROTOCOL`：后端服务使用的协议，例如HTTP或HTTPS。
- `HEALTH_CHECK_NAME`：用于健康检查的健康检查器的名称。

7. 创建健康检查（Health Check）：
```
gcloud compute health-checks create HEALTH_CHECK_NAME \
    --protocol=PROTOCOL \
    --port=PORT \
    --request-path=REQUEST_PATH
```
- `HEALTH_CHECK_NAME`：健康检查的名称。
- `PROTOCOL`：健康检查使用的协议，例如HTTP或HTTPS。
- `PORT`：健康检查监听的端口。
- `REQUEST_PATH`：用于健康检查的请求路径。


