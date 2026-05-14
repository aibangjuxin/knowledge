Kubernetes（K8S）中的 `cluster_secret` 是一种机密信息，用于对集群中的敏感数据进行加密和解密。它通常被用于存储和保护敏感的 API 密钥、证书、密码等信息。

`cluster_secret` 可以通过 Kubernetes 的 Secret 对象来管理和使用。Secret 对象是 Kubernetes 中一种用于存储和管理敏感信息的资源类型。它可以用来存储二进制数据、字符串等敏感信息，如 TLS 证书、API 密钥等。

下面是一个示例 YAML 文件，用于创建一个名为 `my-secret` 的 Secret 对象，并将其用于 Pod 中的环境变量：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
type: Opaque
data:
  api_key: <base64-encoded-api-key>
  password: <base64-encoded-password>
---
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
  - name: my-container
    image: my-image
    env:
    - name: API_KEY
      valueFrom:
        secretKeyRef:
          name: my-secret
          key: api_key
   - name: PASSWORD
      valueFrom:
        secretKeyRef:
          name: my-secret
          key: password
```

在上面的示例中，`my-secret` 对象包含了两个字段：
`api_key` 和 `password`，
它们都是经过 Base64 编码的敏感信息。
`my-pod` Pod 中的 `my-container` 
容器的环境变量 `API_KEY` 和 `PASSWORD` 都来自于 `my-secret` 对象中对应的字段，并通过 `secretKeyRef` 引用来获取。

需要注意的是，
上面的示例中使用的 `Opaque` 类型的 Secret 对象是最常用的类型，
它可以用于存储任意类型的数据。
Kubernetes 还支持其他类型的 Secret 对象，
如 `kubernetes.io/tls` 类型的 Secret 对象用于存储 TLS 证书等数据。

cluster_secret 在K8S中介绍如下:

# cluster_secret

在Kubernetes中,`Secret`对象让你可以安全地将敏感信息像密码、令牌或密钥等存储在集群内。

`cluster_secret`就是用于整个集群层面的secret,所有`namespace`下的 pods 都可以使用该 secret。

# 用法

创建cluster_secret 的步骤:
1. 使用`kubectl create secret generic`命令创建一个secret对象
2. 使用`--type=Opaque` flag,表示cluster级别的secret
3. 省略`--namespace` flag,这样secret就会作用在整个集群层面

```bash
kubectl create secret generic my-cluster-secret --from-literal=api-key="<value>" --type=Opaque 
```

# 使用

在 pod 中使用 cluster_secret,只需要这样引用secret名称即可:

```yaml
apiVersion: v1
kind: Pod 
metadata:
  name: mypod
spec:
  containers:
  - name: mypod
    image: redis
    env:
      - name: SECRET_KEY 
        valueFrom:
          secretKeyRef:
            name: my-cluster-secret 
            key: api-key
```

所有命名空间下的Pod都可以使用`my-cluster-secret`secret。



