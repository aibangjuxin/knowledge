我现在做的事情是要做 k8s 集群的迁移
假设我现在有一个旧的集群在这个旧的 k8s 集群里面 我安装 了 ingress controller 在 Kube-system 这个命名空间下 然后我对应的服务会在其他的，比如说另外一个 name space 里面 然后后面跟对应的 deployment services

我现在新建了一个集群，然后的目的就是把运行在旧集群所有的资源迁移到新的集群
我现在希望访问到旧集群 Ingress Controller 上面的请求，能够通过一种配置跳转到我新的集群里面。因为我们这边做了 DNS 的限制，我不能在旧集群的 DNS 的名字上面做更多的工作，比如说做 CNAME 的解析或者 A NAME 的重新指向。

旧集群对应的 DNS
然后 teamname.dev.aliyun.intracloud.cn.aibang 下的
_.teamname.dev.aliyun.intracloud.cn.aibang
api-name01.teamname.dev.aliyun.intracloud.cn.aibang. ==> A OR cname ==> api-name01.kong.dev.aliyun.intracloud.cn.aibang. 现在这个无法实现
这样能实现访问旧域名==>到我们的新创建工程的域名
_.teamname.dev.aliyun.intracloud.cn.aibang. ==> 这个是我旧的 Cluster 可以申请到的 DNS
\*.kong.dev.aliyun.intracloud.cn.aibang. ==> 这个是我的新的 cluter 可以申请到的 DNS

所以说我的用户请求的时候，我希望仍然是访问到旧的集群的 Ingress Controller 上面。然后呢，我有没有办法在旧集群这边发布一个对应的配置？比如说再发布一个 Nginx， 或者修改现在对应的 ingress controller 配置 ，然后把对应的域名转换到我新的 cluster 配置上面，或者说我在新旧的集群上面做一些 rewrite 或者 forward 来实现我的目的。

这个是我的旧集群里面一个 API 域名服务的的典型配置

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bbdm
  namespace: aibang-1111111111-bbdm
  creationTimestamp: "2025-06-03T13:47:19Z"
  generation: 1
  labels:
    app.kubernetes.io/instance: api-name01
  managedFields:
    - apiVersion: networking.k8s.io/v1
      fieldsType: FieldsV1
      fieldsV1:
        f:metadata:
          f:annotations:
            f:kubectl.kubernetes.io/last-applied-configuration: 0
          f:labels:
            f:app.kubernetes.io/instance: 0
        f:spec:
          f:rules: {}
      manager: argocd-controller
      operation: Update
      time: "2025-06-03T13:47:19Z"
    - apiVersion: networking.k8s.io/v1
      fieldsType: FieldsV1
      fieldsV1:
        f:status:
          f:loadBalancer:
          f:ingress: {}
      manager: nginx-ingress-controller
      operation: Update
      subresource: status
      time: "2025-06-03T13:47:38Z"
spec:
  ingressClassName: nginx
  rules:
    - host: api-name01.teamname.dev.aliyun.intracloud.cn.aibang
      http:
        paths:
          - backend:
              service:
                name: bbdm-api
                port:
                  number: 8078
            path: /
            pathType: ImplementationSpecific
    - host: api-name01.01.teamname.dev.aliyun.intracloud.cn.aibang
      http:
        paths:
          - backend:
              service:
                name: bbdm-api
                port:
                  number: 8078
            path: /
            pathType: ImplementationSpecific
status:
  loadBalancer:
    ingress:
      - ip: 10.190.192.3
```

我希望仍然是访问到旧的集群的 Ingress Controller 上面。然后呢，我有没有办法在旧集群这边发布一个对应的配置？比如说再发布一个 Nginx， 或者修改现在对应的 ingress controller 配置 ，然后把对应的域名转换到我新的 cluster 配置上面，或者说我在新旧的集群上面做一些 rewrite 或者 forward 来实现我的目的。也就是说我想改造旧的集群里面的配置,或者说做哪些工作能让服务平滑的迁移到我的新集群里面.我如果创建了新集群,那么新集群里面也只能配置自己集群对应的域名.

下面是我初步的一个想法,帮我确认
**反向代理的方式**，那核心思路就是：  
**旧集群的 Ingress Controller / Nginx 接收到请求后，把请求转发到新集群的 Ingress 域名（或者服务）**。
