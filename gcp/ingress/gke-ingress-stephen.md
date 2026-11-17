
# mermaid
```mermaid
graph LR
A[Component-L4] --> |different port| B[GKE-ingress]
B --> |load balancer IP| C[Kong DP]
C --> |cluster IP| D[Kong RT]
```
Nginx-L4、GKE-ingress、Kong DP Service、ingress-service、Kong DP Deployments 和 Kong RT Deployments 之间的关系和数据流向。其中:

Nginx-L4 通过代理端口和 Ingress IP 将流量转发到 GKE-ingress
GKE-ingress 再将流量转发到 ingress-service
ingress-service 将流量分发到 Kong DP Deployments
Kong DP Deployments 与 Kong RT Deployments 相连

另外,Nginx-L4 还直接通过代理端口和负载均衡 IP 将部分流量转发到 Kong DP Service,然后 Kong DP Service 将流量分发到 Kong DP Deployments。


```mermaid
graph LR
A[Nginx-L4]
B[GKE-ingress]
C[Kong DP Service]
D[ingress-service]
F[Kong DP Deployments]
G[Kong RT Deployments]
A-->|proxy_pass port ingress ip|B-->D-->F-->G
A-->|proxy_pass port Using loadbalancer IP|C-->F
```

# about proxy-only-subnet

```
在 Google Cloud Platform (GCP) 中，proxy-only-subnet 是用于 Google Cloud Load Balancer 的一种特殊的子网设置。当您在 GCP 中使用 Google Cloud Load Balancer（特别是 HTTP(S) Load Balancer）时，此类子网被用来承载负载均衡器的前端配置。

proxy-only-subnet 的作用
前端 IP 托管：
在 GCP 中，HTTP(S) Load Balancer 是全局性的，意味着它们不直接关联到任何特定的地区，而是可以跨地区服务。
proxy-only-subnet 是专门用来容纳这些负载均衡器的前端IP地址的。这些子网为 Load Balancer 提供了必要的 IP 地址资源。
网络流量路由：
所有指向负载均衡器的入站流量都会首先被路由到 proxy-only-subnet。然后，负载均衡器根据设置的后端服务和路由规则将流量分发到适当的后端实例（如 GCE 实例或 GKE 容器）。
负载均衡优化：
这些子网帮助负载均衡器优化和管理跨全球的流量，确保用户请求能够被快速且有效地路由到最近的数据中心。
如何配置
proxy-only-subnet 通常是由 Google 自动管理的。当您创建一个全局 HTTP(S) Load Balancer 时，Google Cloud 会自动在内部使用这些子网来配置负载均衡器的前端部分。作为用户，您通常不需要直接操作或修改这些子网。它们是负载均衡架构中隐藏的、自动管理的组件。

结论
proxy-only-subnet 在 GCP 的负载均衡策略中扮演着关键角色，主要用于管理和优化全球的入站互联网流量。这种设置简化了用户的负载均衡配置过程，因为它抽象出了一些底层的网络配置细节，使用户可以更专注于应用级别的负载均衡需求。
```
- dns
`gcloud dns managed-zones list --format='table(dnsName, creationTime:sort=1, name, privateVisibilityConfig.networks.networkUrl.basename(), visibility)'`

- cluster list
```
gcloud container clusters list
NAME             LOCATION    MASTER_VERSION      MASTER_IP   MACHINE_TYPE   NODE_VERSION        NUM_NODES  STATUS
private-cluster  asia-east1  1.28.7-gke.1026000  172.16.0.2  n1-standard-1  1.28.7-gke.1026000  3          RUNNING
```

- get-credentials

`gcloud container clusters get-credentials private-cluster --region asia-east1 --project aibang-hour-115803`
- step
```
 lex@Lexs-MacBook-Pro  ~/shell 
 ✔  6944  18:38:14
gcloud container clusters get-credentials private-cluster --region asia-east1 --project aibang-hour-115803
Fetching cluster endpoint and auth data.
kubeconfig entry generated for private-cluster.
 lex@Lexs-MacBook-Pro  ~/shell 
 ✔  6945  18:38:17
export https_proxy=http://34.80.135.183:3128
 lex@Lexs-MacBook-Pro  ~/shell 
 ✔  6946  18:38:21
kubectl get ns
NAME                 STATUS   AGE
default              Active   7h30m
gke-managed-system   Active   7h29m
gmp-public           Active   7h29m
gmp-system           Active   7h29m
kube-node-lease      Active   7h30m
kube-public          Active   7h30m
kube-system          Active   7h30m
```

- get dep,svc,ingress,pod
```
kubectl get deployment,svc,ingress,pod
NAME                                         CLASS          HOSTS                ADDRESS        PORTS   AGE
ingress.networking.k8s.io/internal-ingress   gce-internal   nginx.internal.com   192.168.64.9   80      7h6m

NAME                         READY   STATUS    RESTARTS   AGE
pod/nginx-7854ff8877-p7mwp   1/1     Running   0          7h7m
pod/nginx-7854ff8877-q2l6l   1/1     Running   0          7h7m
pod/nginx-7854ff8877-sjxrt   1/1     Running   0          7h7m


kubectl describe ingress internal-ingress
Name:             internal-ingress
Labels:           <none>
Namespace:        default
Address:          192.168.64.9
Ingress Class:    gce-internal
Default backend:  <default>
Rules:
  Host                Path  Backends
  ----                ----  --------
  nginx.internal.com
                      /   nginx:8080 (10.236.0.4:80,10.236.1.4:80,10.236.2.17:80)
Annotations:          ingress.kubernetes.io/backends:
                        {"k8s1-bbd9e337-default-nginx-8080-bed4b164":"HEALTHY","k8s1-bbd9e337-kube-system-default-http-backend-80-3a3612ef":"HEALTHY"}
                      ingress.kubernetes.io/forwarding-rule: k8s2-fr-z6k8da7d-default-internal-ingress-eehfyxzd
                      ingress.kubernetes.io/target-proxy: k8s2-tp-z6k8da7d-default-internal-ingress-eehfyxzd
                      ingress.kubernetes.io/url-map: k8s2-um-z6k8da7d-default-internal-ingress-eehfyxzd
                      kubernetes.io/ingress.class: gce-internal
                      kubernetes.io/ingress.regional-static-ip-name: gce-ingress
Events:
  Type    Reason  Age                    From                     Message
  ----    ------  ----                   ----                     -------
  Normal  Sync    9m4s (x50 over 7h12m)  loadbalancer-controller  Scheduled for sync
```
-  `gcloud compute networks subnets list`
```
NAME               REGION                   NETWORK      RANGE            STACK_TYPE  IPV6_ACCESS_TYPE  INTERNAL_IPV6_PREFIX  EXTERNAL_IPV6_PREFIX
default            us-central1              default      10.128.0.0/20    IPV4_ONLY
default            europe-west1             default      10.132.0.0/20    IPV4_ONLY
default            us-west1                 default      10.138.0.0/20    IPV4_ONLY
default            asia-east1               default      10.140.0.0/20    IPV4_ONLY
proxy-only-subnet  asia-east1               gke-network  192.168.1.0/24
subnet             asia-east1               gke-network  192.168.64.0/24  IPV4_ONLY
default            us-east1                 default      10.142.0.0/20    IPV4_ONLY
default            asia-northeast1          default      10.146.0.0/20    IPV4_ONLY
default            asia-southeast1          default      10.148.0.0/20    IPV4_ONLY
default            me-central1              default      10.212.0.0/20    IPV4_ONLY
default            europe-west10            default      10.214.0.0/20    IPV4_ONLY
default            me-central2              default      10.216.0.0/20    IPV4_ONLY
default            africa-south1            default      10.218.0.0/20    IPV4_ONLY
default            us-west8                 default      10.220.0.0/20    IPV4_ONLY

gcloud compute networks subnets describe proxy-only-subnet --region asia-east1
creationTimestamp: '2024-05-02T20:31:17.887-07:00'
fingerprint: 3wjJCB1v_0E=
gatewayAddress: 192.168.1.1
id: '2826265659855987818'
ipCidrRange: 192.168.1.0/24
kind: compute#subnetwork
name: proxy-only-subnet
network: https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/global/networks/gke-network
privateIpGoogleAccess: false
privateIpv6GoogleAccess: DISABLE_GOOGLE_ACCESS
purpose: REGIONAL_MANAGED_PROXY
region: https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/regions/asia-east1
role: ACTIVE
selfLink: https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/regions/asia-east1/subnetworks/proxy-only-subnet
state: READY


gcloud compute networks subnets describe subnet --region asia-east1
creationTimestamp: '2024-05-02T19:58:50.873-07:00'
enableFlowLogs: false
fingerprint: trIpZnKz5Cc=
gatewayAddress: 192.168.64.1
id: '2165101340657314821'
ipCidrRange: 192.168.64.0/24
kind: compute#subnetwork
logConfig:
  aggregationInterval: INTERVAL_5_SEC
  enable: false
  flowSampling: 0.5
  metadata: INCLUDE_ALL_METADATA
name: subnet
network: https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/global/networks/gke-network
privateIpGoogleAccess: false
privateIpv6GoogleAccess: DISABLE_GOOGLE_ACCESS
purpose: PRIVATE
region: https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/regions/asia-east1
secondaryIpRanges:
- ipCidrRange: 10.165.224.0/20
  rangeName: gke-private-cluster-services-9c085749
  reservedInternalRange: https://networkconnectivity.googleapis.com/v1/projects/aibang-hour-115803/locations/global/internalRanges/gke-private-cluster-services-9c085749
- ipCidrRange: 10.236.0.0/14
  rangeName: gke-private-cluster-pods-9c085749
  reservedInternalRange: https://networkconnectivity.googleapis.com/v1/projects/aibang-hour-115803/locations/global/internalRanges/gke-private-cluster-pods-9c085749
selfLink: https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/regions/asia-east1/subnetworks/subnet
stackType: IPV4_ONLY

```
- `kubectl describe svc nginx`
```
kubectl get svc
NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
kubernetes   ClusterIP   10.165.224.1     <none>        443/TCP    7h56m
nginx        ClusterIP   10.165.227.140   <none>        8080/TCP   7h30m


kubectl describe svc nginx
Name:              nginx
Namespace:         default
Labels:            app=nginx
Annotations:       cloud.google.com/neg: {"ingress":true}
                   cloud.google.com/neg-status:
                     {"network_endpoint_groups":{"8080":"k8s1-bbd9e337-default-nginx-8080-bed4b164"},"zones":["asia-east1-a","asia-east1-b","asia-east1-c"]}
Selector:          app=nginx
Type:              ClusterIP
IP Family Policy:  SingleStack
IP Families:       IPv4
IP:                10.165.227.140
IPs:               10.165.227.140
Port:              <unset>  8080/TCP
TargetPort:        80/TCP
Endpoints:         10.236.0.4:80,10.236.1.4:80,10.236.2.17:80
Session Affinity:  None
Events:            <none>
```
- `gcloud container clusters list`
```
NAME             LOCATION    MASTER_VERSION      MASTER_IP   MACHINE_TYPE   NODE_VERSION        NUM_NODES  STATUS
private-cluster  asia-east1  1.28.7-gke.1026000  172.16.0.2  n1-standard-1  1.28.7-gke.1026000  3          RUNNING
```

- describe
```
gcloud container clusters describe private-cluster --region asia-east1 --project aibang-hour-115803
addonsConfig:
  gcePersistentDiskCsiDriverConfig:
    enabled: true
  kubernetesDashboard:
    disabled: true
  networkPolicyConfig:
    disabled: true
autopilot: {}
autoscaling:
  autoscalingProfile: BALANCED
binaryAuthorization: {}
clusterIpv4Cidr: 10.236.0.0/14
createTime: '2024-05-03T03:02:39+00:00'
currentMasterVersion: 1.28.7-gke.1026000
currentNodeCount: 3
currentNodeVersion: 1.28.7-gke.1026000
databaseEncryption:
  state: DECRYPTED
defaultMaxPodsConstraint:
  maxPodsPerNode: '110'
endpoint: 172.16.0.2
enterpriseConfig:
  clusterTier: STANDARD
etag: a7b45cf3-843e-4715-be81-2637c2436e76
id: 9c0857494e604b3ba2efd45e9d430434006f5963f2a44580a7e2b138677e0cf6
initialClusterVersion: 1.28.7-gke.1026000
initialNodeCount: 1
instanceGroupUrls:
- https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/zones/asia-east1-c/instanceGroupManagers/gke-private-cluster-private-cluster-n-9e185159-grp
- https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/zones/asia-east1-a/instanceGroupManagers/gke-private-cluster-private-cluster-n-609dd1e3-grp
- https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/zones/asia-east1-b/instanceGroupManagers/gke-private-cluster-private-cluster-n-98adc73f-grp
ipAllocationPolicy:
  clusterIpv4Cidr: 10.236.0.0/14
  clusterIpv4CidrBlock: 10.236.0.0/14
  clusterSecondaryRangeName: gke-private-cluster-pods-9c085749
  defaultPodIpv4RangeUtilization: 0.0029
  podCidrOverprovisionConfig: {}
  servicesIpv4Cidr: 10.165.224.0/20
  servicesIpv4CidrBlock: 10.165.224.0/20
  servicesSecondaryRangeName: gke-private-cluster-services-9c085749
  stackType: IPV4
  useIpAliases: true
labelFingerprint: a9dc16a7
legacyAbac: {}
location: asia-east1
locations:
- asia-east1-c
- asia-east1-a
- asia-east1-b
loggingConfig:
  componentConfig:
    enableComponents:
    - SYSTEM_COMPONENTS
    - WORKLOADS
loggingService: logging.googleapis.com/kubernetes
maintenancePolicy:
  resourceVersion: e3b0c442
masterAuth:
  clusterCaCertificate: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUVMRENDQXBTZ0F3SUJBZ0lRUGtxTGVhVmRjZHUrUlljeE92RTIxREFOQmdrcWhraUc5dzBCQVFzRkFEQXYKTVMwd0t3WURWUVFERXlRM1pqUTJOemcxTmkwME5tTXpMVFE0WXpRdE9UZ3hZaTAzTXpoaVptTTFPVEk1TVRBdwpJQmNOTWpRd05UQXpNREl3TWpNNVdoZ1BNakExTkRBME1qWXdNekF5TXpsYU1DOHhMVEFyQmdOVkJBTVRKRGRtCk5EWTNPRFUyTFRRMll6TXRORGhqTkMwNU9ERmlMVGN6T0dKbVl6VTVNamt4TURDQ0FhSXdEUVlKS29aSWh2Y04KQVFFQkJRQURnZ0dQQURDQ0FZb0NnZ0dCQUw2emZOOHE0d29jT21XK0dGQUtmZGg5QkEzV3FvYlI3aGh4Q2JDZApKNUlRZVhUczNpVC9jK2FnSjl1dzUwYi9la1pudk4wcW5RVGNvZ1grMXFyYjFSeVM4ZGV3aXRNRHNPOTRjb1V0CkFqS2NaWjkwbTJMbVpTcmlYOG1pRHc5bjRqNHNZNnlwN1pRQkNZN1hkUVQ2b0JnZ2Z2TTM3RVhSb3dETGVzZmwKZHJ3UWk0L1h2ZFdsbUF5cFNZZjFUMnFJWDZ4VnZocWprdHBvY3l1YTRpRzJhL0VpODdGREplMCtEejhGTmNveQpmbi9Ka3M4VTJuOSt5NUF6V2tTRHJWYk9mdG0wVHNyck84bTYyT3U3cDRhbFZEU04wSmcwRjFYQnhPS0haQ2l5Cjh0RFRFM2trcjQ4aytSM1dsY2M4a1lQWDFoV1NIRkFWVmVyT040Qy94Ynp4dUJ1ZUQ3Zm10enl5SnYzZW1VbC8KbG9mVWNiNkQzbmNkaEFjd1BscSs3cW9qUmtyOHhHeEFqYWlCbHc0M0VuNS9SdElVcGNnUzhrUHJ2THRSYllPQgpGSTBYRC9MZUpkWmVqV1Vvdit1SHBUZFNlWDRtRzU3MzdzKzFmcElaOENqM21oSzRWWjN3djVaQmFUQUpyZ00wCnZwbDdobjdoU25iNkZpQzVPK1ZFUXNncnN3SURBUUFCbzBJd1FEQU9CZ05WSFE4QkFmOEVCQU1DQWdRd0R3WUQKVlIwVEFRSC9CQVV3QXdFQi96QWRCZ05WSFE0RUZnUVVhUm1GWS8rV09HZzMzV203YVJIcHh3RWxoWU13RFFZSgpLb1pJaHZjTkFRRUxCUUFEZ2dHQkFBaXFyZDEzTnlDbE1ENXB5NHlzMFhyN2JLeW85VFlSTFZmRElCSlpCelZ1ClRkeG1Ya2hrcTI2OWV6M25MOWpmZkx6UG53SHdhWE5NWGgxTlJwbUFHSmJoRjBabi9ZZ3FKWnZocHVYRE5QRFoKNHFCVjRMVFFtV1pXak5Zb3lGYTFRWVpvNUhaa1BqZEFTclVhQk1tcmgwOFBpS1FDbUN0eXJLeE9VSjFmdC93VgpuaXhCR0ZSYmNxRmFqVjc0UXppekZJVzUyWnUweVczUmpTQVhtcHI1d3k0MmFkNm1jV0szTzM2Y2d4Q01VN1dECjR4M0QxeDNrN0VpOFJDSzNlcE10aDgrUmRKQnp2RXlMQlhIdG9icEpWS2JxMm5YMXgyNjVJNUJEVSttSnNzdzgKSzFQTEFpQlVTc1dremhGbld5ZU8zN3ZTQUJBcTJYSTUwaTUrWm9sUzBVY3BaVGJrcTRwRmliTU5TWUF0T1FERQplRy94MWh1d2x5dDUyZENtZWJvN21lTHhMYU1UbkdjKzQ1aVVaNThYa2VTQnZGelZ6RDNDd2JVaUFTWTBkVkVqCmxaMnJ4UEp0SWc1NXgwM3lsb1Vzb2FXdWxNZTF3WFRwZ3Q1U1lNN3pBMFBIVFpjSEZIYzBwMWtvZnFRRi9xNnYKKzQydEFVcVdNbHhOY2xlRmVvNUxOdz09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K
masterAuthorizedNetworksConfig:
  cidrBlocks:
  - cidrBlock: 10.0.0.0/16
    displayName: any
  enabled: true
monitoringConfig:
  advancedDatapathObservabilityConfig: {}
  componentConfig:
    enableComponents:
    - SYSTEM_COMPONENTS
  managedPrometheusConfig:
    enabled: true
monitoringService: monitoring.googleapis.com/kubernetes
name: private-cluster
network: gke-network
networkConfig:
  defaultSnatStatus: {}
  network: projects/aibang-hour-115803/global/networks/gke-network
  serviceExternalIpsConfig: {}
  subnetwork: projects/aibang-hour-115803/regions/asia-east1/subnetworks/subnet
nodeConfig:
  diskSizeGb: 100
  diskType: pd-balanced
  imageType: COS_CONTAINERD
  machineType: n1-standard-1
  metadata:
    disable-legacy-endpoints: 'true'
  oauthScopes:
  - https://www.googleapis.com/auth/cloud-platform
  serviceAccount: default
  shieldedInstanceConfig:
    enableIntegrityMonitoring: true
  tags:
  - no-external-ip
  windowsNodeConfig: {}
nodePoolDefaults:
  nodeConfigDefaults:
    loggingConfig:
      variantConfig:
        variant: DEFAULT
nodePools:
- config:
    diskSizeGb: 100
    diskType: pd-balanced
    imageType: COS_CONTAINERD
    machineType: n1-standard-1
    metadata:
      disable-legacy-endpoints: 'true'
    oauthScopes:
    - https://www.googleapis.com/auth/cloud-platform
    serviceAccount: default
    shieldedInstanceConfig:
      enableIntegrityMonitoring: true
    tags:
    - no-external-ip
    windowsNodeConfig: {}
  etag: 6f4a72db-c79b-44b3-a485-3c27ced7bbc7
  initialNodeCount: 1
  instanceGroupUrls:
  - https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/zones/asia-east1-c/instanceGroupManagers/gke-private-cluster-private-cluster-n-9e185159-grp
  - https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/zones/asia-east1-a/instanceGroupManagers/gke-private-cluster-private-cluster-n-609dd1e3-grp
  - https://www.googleapis.com/compute/v1/projects/aibang-hour-115803/zones/asia-east1-b/instanceGroupManagers/gke-private-cluster-private-cluster-n-98adc73f-grp
  locations:
  - asia-east1-c
  - asia-east1-a
  - asia-east1-b
  management:
    autoRepair: true
    autoUpgrade: true
  maxPodsConstraint:
    maxPodsPerNode: '110'
  name: private-cluster-node-pool
  networkConfig:
    podIpv4CidrBlock: 10.236.0.0/14
    podIpv4RangeUtilization: 0.0029
    podRange: gke-private-cluster-pods-9c085749
  podIpv4CidrSize: 24
  selfLink: https://container.googleapis.com/v1/projects/aibang-hour-115803/locations/asia-east1/clusters/private-cluster/nodePools/private-cluster-node-pool
  status: RUNNING
  upgradeSettings:
    maxSurge: 1
    strategy: SURGE
  version: 1.28.7-gke.1026000
notificationConfig:
  pubsub: {}
privateClusterConfig:
  enablePrivateEndpoint: true
  enablePrivateNodes: true
  masterIpv4CidrBlock: 172.16.0.0/28
  peeringName: gke-nf7ee3eeff3deeb6d9e9-5535-5db9-peer
  privateEndpoint: 172.16.0.2
  publicEndpoint: 34.80.189.189
releaseChannel:
  channel: REGULAR
securityPostureConfig:
  mode: BASIC
  vulnerabilityMode: VULNERABILITY_MODE_UNSPECIFIED
selfLink: https://container.googleapis.com/v1/projects/aibang-hour-115803/locations/asia-east1/clusters/private-cluster
servicesIpv4Cidr: 10.165.224.0/20
shieldedNodes: {}
status: RUNNING
subnetwork: subnet
zone: asia-east1
```
export https_proxy=http://127.0.0.1:59772 http_proxy=http://127.0.0.1:59772 all_proxy=socks5://127.0.0.1:59772

# ingress
```yaml 
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: internal-ingress
  annotations:
    kubernetes.io/ingress.class: "gce-internal"
    kubernetes.io/ingress.regional-static-ip-name: gce-ingress
  namespace: default
spec:
  rules:
  - host: nginx.internal.com
    http:
      paths:
      - backend:
          service:
            name: nginx
            port:
              number: 8080
        path: /
        pathType: Prefix
``` 
