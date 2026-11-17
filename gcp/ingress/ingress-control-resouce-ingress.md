根据你提供的Nginx配置文件和要求，可以使用以下的Ingress配置来发布你的服务。这个配置将强制使用HTTPS，并根据你提供的路径和版本进行相应的路由。

### Ingress配置示例

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aibang-ingress
  namespace: aibang
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$1
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - dev-api.cn.aibang
    secretName: tls-secret # 需要提前创建包含TLS证书的Secret
  rules:
  - host: dev-api.cn.aibang
    http:
      paths:
      - path: /aibang-abc-wde-pa-workflow-proxy/v1/(.*)
        pathType: Prefix
        backend:
          service:
            name: abc-wde-pa-service
            port:
              number: 8001
      - path: /aibang-def-wde-pa-workflow-proxy/v1/(.*)
        pathType: Prefix
        backend:
          service:
            name: def-wde-pa-service
            port:
              number: 8001
```

### 详细说明

1. **强制使用HTTPS**:
   - 使用了`nginx.ingress.kubernetes.io/force-ssl-redirect`注解来强制重定向HTTP到HTTPS。
   - nginx.ingress.kubernetes.io/rewrite-target注解用于在Ingress NGINX Controller中定义URL重写规则
   这个注解的作用是将匹配的路径重写为指定的目标路径，其中$1是一个捕获组，表示从原始路径中提取的部分。

    详细解释
    在Ingress配置中，rewrite-target注解用于将请求的路径重写为新的路径。原理如下：

    路径匹配: 例如，路径/aibang-abc-wde-pa-workflow-proxy/v1/(.*)中，(.*)是一个捕获组，表示任意字符的零或多个匹配。
    捕获组: 在rewrite-target: /$1中，$1表示第一个捕获组的内容。
    示例
    假设有一个请求路径/aibang-abc-wde-pa-workflow-proxy/v1/foo/bar，该路径匹配了/aibang-abc-wde-pa-workflow-proxy/v1/(.*)中的捕获组(.*)，捕获组将提取路径foo/bar。

    原始请求路径: /aibang-abc-wde-pa-workflow-proxy/v1/foo/bar
    捕获组$1的内容: foo/bar
    重写后路径: /$1 => /foo/bar
    因此，rewrite-target: /$1会将原始请求路径/aibang-abc-wde-pa-workflow-proxy/v1/foo/bar重写为/foo/bar，然后将请求发送到后端服务

2. **pathType设置**:
   - `pathType: Prefix`确保路径前缀匹配。

3. **集群对外暴露的域名**:
   - `host: dev-api.cn.aibang`指定了集群对外暴露的域名。

4. **服务路径和版本访问**:
   - `path: /aibang-abc-wde-pa-workflow-proxy/v1/(.*)`和`path: /aibang-def-wde-pa-workflow-proxy/v1/(.*)`分别对应两个服务的路径。

### 前置要求

1. **TLS Secret**:
   - 需要提前创建包含TLS证书的Secret，名称为`tls-secret`。
   - 创建TLS Secret的示例命令：
     ```sh
     kubectl create secret tls tls-secret --cert=/path/to/tls.crt --key=/path/to/tls.key -n aibang
     ```

2. **服务**:
   - 确保服务`abc-wde-pa-service`和`def-wde-pa-service`在`aibang`命名空间内正确运行。

### 示例

创建Ingress资源：

```sh
kubectl apply -f ingress.yaml
```

这样，你的Ingress NGINX Controller将能够根据定义的规则将流量正确路由到你的服务，并强制使用HTTPS。



# for kong gw
为了将所有请求通过Ingress转发到Kong Gateway，然后由Kong Gateway再根据路径进行转发，可以创建一个Ingress规则，将所有请求转发到Kong Gateway的服务。假设Kong Gateway的服务名为`aibang-int-kdp-svc`，监听端口为`8000`，以下是一个示例Ingress配置：

### Ingress配置示例

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kong-ingress
  namespace: aibang
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - dev-api.cn.aibang
    secretName: tls-secret # 需要提前创建包含TLS证书的Secret
  rules:
  - host: dev-api.cn.aibang
    http:
      paths:
      - path: /(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: aibang-int-kdp-svc
            port:
              number: 8000
```

### 详细说明

1. **强制使用HTTPS**:
   - `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"`注解强制HTTP重定向到HTTPS。

2. **路径匹配**:
   - `path: /(.*)`匹配所有路径。
   - path: / 匹配所有路径
   - `pathType: ImplementationSpecific`确保Ingress Controller使用其特定的路径匹配逻辑。

3. **后端服务**:
   - `backend.service.name`设置为`aibang-int-kdp-svc`，这是Kong Gateway的服务名称。
   - `backend.service.port.number`设置为`8000`，这是Kong Gateway的监听端口。

4. **TLS配置**:
   - `tls.secretName`设置为`tls-secret`，这是包含TLS证书的Secret名称。

### 前置要求

1. **TLS Secret**:
   - 需要提前创建包含TLS证书的Secret，名称为`tls-secret`。
   - 创建TLS Secret的示例命令：
     ```sh
     kubectl create secret tls tls-secret --cert=/path/to/tls.crt --key=/path/to/tls.key -n aibang
     ```

2. **Kong Gateway服务**:
   - 确保Kong Gateway的服务`aibang-int-kdp-svc`在`aibang`命名空间内正确运行，并监听端口`8000`。

### 示例

创建Ingress资源：

```sh
kubectl apply -f kong-ingress.yaml
```

### Kong Gateway的配置

Kong Gateway需要根据路径转发请求，这需要在Kong中配置相应的路由规则。例如，你可以使用Kong的Admin API或Kong Ingress Controller配置路由规则。

假设你使用Kong的Admin API，以下是一个示例请求来创建一个路由规则：

```sh
curl -i -X POST http://<KONG_ADMIN_API>:8001/services/ \
  --data name=abc-wde-pa-service \
  --data url='http://abc-wde-pa-service.aibang.svc.cluster.local:8001'

curl -i -X POST http://<KONG_ADMIN_API>:8001/services/abc-wde-pa-service/routes \
  --data 'paths[]=/aibang-abc-wde-pa-workflow-proxy/v1'

curl -i -X POST http://<KONG_ADMIN_API>:8001/services/ \
  --data name=def-wde-pa-service \
  --data url='http://def-wde-pa-service.aibang.svc.cluster.local:8001'

curl -i -X POST http://<KONG_ADMIN_API>:8001/services/def-wde-pa-service/routes \
  --data 'paths[]=/aibang-def-wde-pa-workflow-proxy/v1'
```

通过这种方式，所有请求将首先通过Ingress NGINX转发到Kong Gateway，由Kong Gateway根据路径进行相应的转发。



Based on your requirements, I'll help you create an `ingress.yaml` file that meets your needs.

Here's a sample `ingress.yaml` file that you can use as a starting point:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aibang-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: dev-api.cn.aibang
    http:
      paths:
      - path: /aibang-abc-wde-pa-workflow-proxy/v1
        pathType: Prefix
        backend:
          service:
            name: aibang-abc-wde-pa-workflow-proxy
            port:
              number: 80
      - path: /aibang-def-wde-pa-workflow-proxy/v1
        pathType: Prefix
        backend:
          service:
            name: aibang-def-wde-pa-workflow-proxy
            port:
              number: 80
  tls:
  - hosts:
    - dev-api.cn.aibang
    secretName: aibang-tls-secret
```
Let me explain what each part of this `ingress.yaml` file does:

* `ingressClassName: nginx` specifies that we're using the NGINX Ingress Controller.
* `rules` defines the routing rules for the Ingress resource.
* `host: dev-api.cn.aibang` specifies the domain name that will be used to access the services.
* `http` defines the HTTP routing rules.
* `paths` defines the specific paths that will be routed to the corresponding services.
* `pathType: Prefix` specifies that the path should be treated as a prefix, so that any requests with the same prefix will be routed to the same service.
* `backend` specifies the service and port that will handle the requests for each path.
* `tls` specifies the TLS configuration for the Ingress resource.
* `hosts` specifies the domain name that will be used for TLS termination.
* `secretName` specifies the name of the TLS secret that contains the certificate and private key for the domain.

Note that you'll need to create a TLS secret named `aibang-tls-secret` that contains the certificate and private key for the `dev-api.cn.aibang` domain.

To deploy this Ingress resource, you can use the following command:
```
kubectl apply -f ingress.yaml
```
This will create the Ingress resource and configure the NGINX Ingress Controller to route requests to your services based on the specified paths and domain name
