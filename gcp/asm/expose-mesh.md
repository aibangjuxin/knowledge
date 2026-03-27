
if we want to expose istio-ingress outside gke add this annotation to service, haven't applied that since i have no idea if we need that for new proxies:

```yaml
kind: Service
metadata:
 name: istio-ingressgateway
 annotations:
 cloud.google.com/load-balancer-type: Internal

```