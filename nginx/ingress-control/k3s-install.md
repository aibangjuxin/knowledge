https://raw.githubusercontent.com/kubernetes/ingress-nginx/refs/heads/main/deploy/static/provider/cloud/deploy.yaml


```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/refs/heads/main/deploy/static/provider/cloud/deploy.yaml
namespace/ingress-nginx created
serviceaccount/ingress-nginx created
serviceaccount/ingress-nginx-admission created
role.rbac.authorization.k8s.io/ingress-nginx created
role.rbac.authorization.k8s.io/ingress-nginx-admission created
clusterrole.rbac.authorization.k8s.io/ingress-nginx created
clusterrole.rbac.authorization.k8s.io/ingress-nginx-admission created
rolebinding.rbac.authorization.k8s.io/ingress-nginx created
rolebinding.rbac.authorization.k8s.io/ingress-nginx-admission created
clusterrolebinding.rbac.authorization.k8s.io/ingress-nginx created
clusterrolebinding.rbac.authorization.k8s.io/ingress-nginx-admission created
configmap/ingress-nginx-controller created
service/ingress-nginx-controller created
service/ingress-nginx-controller-admission created
deployment.apps/ingress-nginx-controller created
job.batch/ingress-nginx-admission-create created
job.batch/ingress-nginx-admission-patch created
ingressclass.networking.k8s.io/nginx created
validatingwebhookconfiguration.admissionregistration.k8s.io/ingress-nginx-admission created
```

will created ns ingress-nginx 
```bash
kubectl  get deployment,svc -n ingress-nginx
NAME                                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/ingress-nginx-controller   0/1     1            0           69s

NAME                                         TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
service/ingress-nginx-controller             LoadBalancer   10.43.112.85    <pending>     80:61837/TCP,443:61471/TCP   69s
service/ingress-nginx-controller-admission   ClusterIP      10.43.229.130   <none>        443/TCP                      69s


kubectl  describe svc ingress-nginx-controller -n ingress-nginx
Name:                     ingress-nginx-controller
Namespace:                ingress-nginx
Labels:                   app.kubernetes.io/component=controller
                          app.kubernetes.io/instance=ingress-nginx
                          app.kubernetes.io/name=ingress-nginx
                          app.kubernetes.io/part-of=ingress-nginx
                          app.kubernetes.io/version=1.13.2
Annotations:              <none>
Selector:                 app.kubernetes.io/component=controller,app.kubernetes.io/instance=ingress-nginx,app.kubernetes.io/name=ingress-nginx
Type:                     LoadBalancer
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.43.112.85
IPs:                      10.43.112.85
Port:                     http  80/TCP
TargetPort:               http/TCP
NodePort:                 http  61837/TCP
Endpoints:                
Port:                     https  443/TCP
TargetPort:               https/TCP
NodePort:                 https  61471/TCP
Endpoints:                
Session Affinity:         None
External Traffic Policy:  Local
HealthCheck NodePort:     61500
Events:                   <none>

```

sh-3.2# docker pull registry.k8s.io/ingress-nginx/controller:v1.13.2@sha256:1f7eaeb01933e719c8a9f4acd8181e555e582330c7d50f24484fb64d2ba9b2ef
Error response from daemon: Get "https://us-south1-docker.pkg.dev/v2/k8s-artifacts-prod/images/ingress-nginx/controller/manifests/sha256:1f7eaeb01933e719c8a9f4acd8181e555e582330c7d50f24484fb64d2ba9b2ef": dial tcp [2404:6800:4008:c15::52]:443: i/o timeout

Using cn 

```
sh-3.2# docker pull swr.cn-north-4.myhuaweicloud.com/ddn-k8s/registry.k8s.io/ingress-nginx/controller:v1.13.2
v1.13.2: Pulling from ddn-k8s/registry.k8s.io/ingress-nginx/controller
9824c27679d3: Pull complete 
d44309a0b764: Pull complete 
b25bd6379dd4: Pull complete 
7ade52710318: Pull complete 
c143cf4725f8: Pull complete 
5711bbb92cda: Pull complete 
4f4fb700ef54: Pull complete 
78d7bac905bc: Pull complete 
d29fa5b0e5e2: Pull complete 
00d7fdc125fd: Pull complete 
9c0a1d8de43f: Pull complete 
13ee25061d00: Pull complete 
df90de614061: Pull complete 
28236ff56f2f: Pull complete 
888ce456b643: Pull complete 
Digest: sha256:4af6c47c72438b0f06c98a78d425dc7cd3ecdfccc6925437f60dc53e8975feba
Status: Downloaded newer image for swr.cn-north-4.myhuaweicloud.com/ddn-k8s/registry.k8s.io/ingress-nginx/controller:v1.13.2
swr.cn-north-4.myhuaweicloud.com/ddn-k8s/registry.k8s.io/ingress-nginx/controller:v1.13.2
sh-3.2# 


```
edit yaml using 
`swr.cn-north-4.myhuaweicloud.com/ddn-k8s/registry.k8s.io/ingress-nginx/controller:v1.13.2`


edit svc 
kubectl edit svc ingress-nginx-controller -n ingress-nginx
Change Service Type to NodePort

fix images issue
```
看起来你只改了 Controller 的镜像，但 admission 相关的 Job 还在用官方仓库的 kube-webhook-certgen 镜像。ingress-nginx 的安装清单里通常有两个一次性 Job：

- ingress-nginx-admission-create
- ingress-nginx-admission-patch  
    它们的容器镜像默认是 registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.2（有时还带 @sha256:digest）。你需要把这两处也改成国内镜像，否则 Pod 仍会去拉取官方镜像。

  

给你两种场景的处理方式：

  

一、如果你是用官方 deploy.yaml 直接 kubectl apply

1. 一次性把 certgen 镜像替换为华为源

- 同时去掉可能存在的 @sha256:… 摘要（因为镜像换了仓库，原摘要不匹配）。
- macOS：  
    sed -i ‘’ ‘s#registry.k8s.io/ingress-nginx/kube-webhook-certgen#swr.cn-north-4.myhuaweicloud.com/ddn-k8s/registry.k8s.io/ingress-nginx/kube-webhook-certgen#g’ deploy.yaml  
    sed -i ‘’ ‘s/@sha256:[0-9a-f]{64}//g’ deploy.yaml
- Linux：  
    sed -i ‘s#registry.k8s.io/ingress-nginx/kube-webhook-certgen#swr.cn-north-4.myhuaweicloud.com/ddn-k8s/registry.k8s.io/ingress-nginx/kube-webhook-certgen#g’ deploy.yaml  
    sed -i ‘s/@sha256:[0-9a-f]{64}//g’ deploy.yaml

1. 删除已存在的一次性 Job（Job 不会因 apply 自动重跑）  
    kubectl -n ingress-nginx delete job ingress-nginx-admission-create ingress-nginx-admission-patch
2. 重新应用清单  
    kubectl apply -f deploy.yaml
3. 验证镜像已指向国内源  
    kubectl -n ingress-nginx get job ingress-nginx-admission-create -o jsonpath=’{.spec.template.spec.containers[0].image}’; echo  
    kubectl -n ingress-nginx get job ingress-nginx-admission-patch -o jsonpath=’{.spec.template.spec.containers[0].image}’; echo

  

二、如果你是用 Helm 安装/升级  
需要同时覆盖 controller 和 admission certgen 的仓库与 tag：  
helm upgrade –install ingress-nginx ingress-nginx/ingress-nginx  
-n ingress-nginx –create-namespace  
–set controller.image.repository=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/registry.k8s.io/ingress-nginx/controller  
–set controller.image.tag=v1.13.2  
–set controller.admissionWebhooks.patch.image.repository=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/registry.k8s.io/ingress-nginx/kube-webhook-certgen  
–set controller.admissionWebhooks.patch.image.tag=v1.6.2  
–set controller.admissionWebhooks.image.repository=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/registry.k8s.io/ingress-nginx/kube-webhook-certgen  
–set controller.admissionWebhooks.image.tag=v1.6.2

  

注意事项

- 事件里出现的镜像引用带 @sha256:… 时，一定要在清单里去掉该摘要，或换成国内镜像对应的摘要，否则 kubelet 会按完整引用拉取原仓库。
- 除了 Deployment 里的 controller 镜像，务必同时替换 Job（admission-create/admission-patch）里的 kube-webhook-certgen 镜像。
- 如果集群用的是 containerd/k3s，节点仍需能访问华为源的域名；确认没有额外的代理/防火墙拦截。

  

需要我帮你检查当前 deploy.yaml 里 Job 的片段具体应该怎么改，可以把相关片段贴出来。也可以发我 helm values，我帮你写完整的覆盖参数。




kubectl -n ingress-nginx delete job ingress-nginx-admission-create ingress-nginx-admission-patch

kubectl -n ingress-nginx delete secret ingress-nginx-admission
kubectl apply -f deploy.yaml

```

# 检查服务状态
kubectl get svc ingress-nginx-controller -n ingress-nginx

# 检查所有 pods
kubectl get pods -n ingress-nginx

# 检查 ingress controller 日志确认它正常启动
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller






# Reference 

To set up an Ingress Controller in Kubernetes (k8s) or K3s, follow these steps:

  

**1. Choose an Ingress Controller**

  

Popular options:

- **NGINX Ingress Controller** (most common)
- **Traefik** (default in K3s)
- **HAProxy**
- **Contour**
- **Istio** (if using service mesh)

  

**2. Install the Ingress Controller**

  

**A. On Standard Kubernetes (k8s) with NGINX**kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml

  

- This deploys the NGINX Ingress Controller in the ‎⁠ingress-nginx⁠ namespace.

  

**B. On K3s**

- **Traefik is installed by default** in K3s as the Ingress Controller.
- To use NGINX instead, **disable Traefik** and install NGINX:# Disable Traefik when installing K3s

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -

  

# Install NGINX Ingress Controller

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml

  

**3. Verify the Ingress Controller is Running**kubectl get pods -n ingress-nginx

  

- You should see pods like ‎⁠ingress-nginx-controller-xxxx⁠.

  

**4. Create an Ingress Resource**

  

Example (‎⁠ingress.yaml⁠):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-service
            port:
              number: 80
```

  

Apply it:kubectl apply -f ingress.yaml

  

**5. Access Your Service**

- **Edit your** ‎⁠/etc/hosts⁠ to point ‎⁠myapp.local⁠ to your cluster’s IP (for local testing).
- For cloud clusters, configure DNS to point to the Ingress Controller’s external IP.

  

**6. Check Ingress**kubectl get ingress

  

- Shows the assigned address and status.

  

**7. Troubleshooting**

- Check logs:kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

  

- Ensure your service is reachable from the Ingress Controller.

  

**Summary**

- **K8s:** Install NGINX Ingress Controller (or other).
- **K3s:** Traefik is default, but you can install NGINX.
- Create Ingress resources to route traffic.
- Map DNS or ‎⁠/etc/hosts⁠ for access.

  

Let me know if you want a specific example for your use case, or if you need help with annotations, TLS, or advanced routing!