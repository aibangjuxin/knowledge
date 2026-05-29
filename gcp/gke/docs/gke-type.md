- reference
/Users/lex/git/knowledge/gcp/asm/no-mtls/gateways-type.md


# 命令1：查看GatewayClass资源
kubectl get gatewayclass
```bash
NAME                                        CONTROLLER                                      ACCEPTED   AGE
gke-l7-global-external-managed              networking.gke.io/gateway                       True       212d
gke-l7-gxlb                                 networking.gke.io/gateway                       True       212d
gke-l7-regional-external-managed            networking.gke.io/gateway                       True       212d
gke-l7-rilb                                 networking.gke.io/gateway                       True       212d
gke-passthrough-lb-external-managed         networking.gke.io/persistent-ip-controller      True       212d
gke-passthrough-lb-internal-managed         networking.gke.io/persistent-ip-controller      True       212d
gke-persistent-regional-external-managed    networking.gke.io/persistent-ip-controller      True       212d
gke-persistent-regional-internal-managed    networking.gke.io/persistent-ip-controller      True       212d
istio                                       istio.io/gateway-controller                     True       4h10m
istio-remote                                istio.io/unmanaged-gateway                      True       4h10m
```
# 命令2：过滤所有包含"gateway"关键词的CRD
kubectl get crd | grep gateway
```bash
backendtlspolicies.gateway.networking.k8s.io                        2026-05-29T02:38:00Z
gatewayclasses.gateway.networking.k8s.io                            2025-10-29T02:11:25Z
gateways.gateway.networking.k8s.io                                  2025-10-29T02:11:24Z
gateways.networking.istio.io                                        2026-05-29T02:11:12Z
gcpgatewaypolicies.networking.gke.io                                2025-10-29T02:11:23Z
grpcroutes.gateway.networking.k8s.io                                2026-05-29T02:38:00Z
httproutes.gateway.networking.k8s.io                                2025-10-29T02:11:25Z
listenersets.gateway.networking.k8s.io                              2026-05-29T02:38:00Z
referencegrants.gateway.networking.k8s.io                          2025-10-29T02:11:27Z
tcproutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
tlsroutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
udproutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
xbackendtrafficpolicies.gateway.networking.x-k8s.io                 2026-05-29T02:38:01Z
xmeshes.gateway.networking.x-k8s.io                                2026-05-29T02:38:01Z
```
# 命令3：过滤所有创建时间为2026-05-29的CRD
kubectl get crd | grep 2026-05-29
```bash
authorizationpolicies.security.istio.io                             2026-05-29T02:11:13Z
autoscalingmetrics.autoscaling.gke.io                               2026-05-29T03:50:50Z
backendtlspolicies.gateway.networking.k8s.io                        2026-05-29T02:38:00Z
capacitybuffers.autoscaling.x-k8s.io                                2026-05-29T03:36:16Z
destinationrules.networking.istio.io                               2026-05-29T02:11:12Z
envoyfilters.networking.istio.io                                   2026-05-29T02:11:12Z
gateways.networking.istio.io                                        2026-05-29T02:11:12Z
gcpedgeextensions.networking.gke.io                                2026-05-29T03:50:05Z
gcphhttpfilters.networking.gke.io                                   2026-05-29T03:50:05Z
gcpinferencepoolimports.networking.gke.io                          2026-05-29T03:36:22Z
grpcroutes.gateway.networking.k8s.io                                2026-05-29T02:38:00Z
inferencepools.inference.networking.k8s.io                          2026-05-29T03:36:21Z
listenersets.gateway.networking.k8s.io                              2026-05-29T02:38:00Z
peerauthentications.security.istio.io                               2026-05-29T02:11:14Z
proxyconfigs.networking.istio.io                                   2026-05-29T02:11:12Z
requestauthentications.security.istio.io                           2026-05-29T02:11:14Z
serviceentries.networking.istio.io                                 2026-05-29T02:11:13Z
sidecars.networking.istio.io                                        2026-05-29T02:11:13Z
tcproutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
telemetries.telemetry.istio.io                                      2026-05-29T02:11:14Z
tlsroutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
trafficextensions.extensions.istio.io                              2026-05-29T02:11:12Z
udproutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
virtualservices.networking.istio.io                                2026-05-29T02:11:13Z
wasmplugins.extensions.istio.io                                     2026-05-29T02:11:12Z
workloadentries.networking.istio.io                                 2026-05-29T02:11:13Z
workloadgroups.networking.istio.io                                 2026-05-29T02:11:13Z
xbackendtrafficpolicies.gateway.networking.x-k8s.io                 2026-05-29T02:38:01Z
xmeshes.gateway.networking.x-k8s.io                                2026-05-29T02:38:01Z
```
需要我帮你把这些CRD按K8s Gateway API、Istio、GKE三个类别做个分类整理吗？这样能更清晰地看出哪些资源属于哪个组件。
//git pu


排版后的完整内容
# 命令1：过滤 2026-05-29 创建且包含 gateway 的 CRD
kubectl get crd | grep 2026-05-29 | grep gateway
```bash
backendtlspolicies.gateway.networking.k8s.io                        2026-05-29T02:38:00Z
gateways.networking.istio.io                                        2026-05-29T02:11:12Z
grpcroutes.gateway.networking.k8s.io                                2026-05-29T02:38:00Z
listenersets.gateway.networking.k8s.io                              2026-05-29T02:38:00Z
tcproutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
tlsroutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
udproutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
xbackendtrafficpolicies.gateway.networking.x-k8s.io                 2026-05-29T02:38:01Z
xmeshes.gateway.networking.x-k8s.io                                2026-05-29T02:38:01Z
```
# 命令2：过滤所有属于 gateway.networking.k8s.io 组的 CRD

kubectl get crd | grep gateway.networking.k8s.io
```bash
backendtlspolicies.gateway.networking.k8s.io                        2026-05-29T02:38:00Z
gatewayclasses.gateway.networking.k8s.io                            2025-10-29T02:11:25Z
gateways.gateway.networking.k8s.io                                  2025-10-29T02:11:24Z
grpcroutes.gateway.networking.k8s.io                                2026-05-29T02:38:00Z
httproutes.gateway.networking.k8s.io                                2025-10-29T02:11:25Z
listenersets.gateway.networking.k8s.io                              2026-05-29T02:38:00Z
referencegrants.gateway.networking.k8s.io                          2025-10-29T02:11:27Z
tcproutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
tlsroutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
udproutes.gateway.networking.k8s.io                                2026-05-29T02:38:01Z
```
