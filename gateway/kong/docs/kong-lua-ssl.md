### 配置段落

```yaml
lua_ssl_trusted_certificate: /etc/secrets/namespace-cp-cert-secret/tls.crt,/etc/secrets/namespace-redis-secret/redis_ca.pem,system
lua_ssl_verify_depth: 2
```

### 功能说明

#### `lua_ssl_trusted_certificate`
- **作用**: 该配置项用于指定Lua代码在处理SSL/TLS通信时信任的CA证书路径。它可以包含多个证书文件路径，通过逗号分隔，同时还可以使用 `system` 关键字来信任系统默认的CA证书。
- **配置解析**:
  - `/etc/secrets/namespace-cp-cert-secret/tls.crt`: 指向控制平面相关的证书文件，通常用于验证来自控制平面的SSL连接。
  - `/etc/secrets/namespace-redis-secret/redis_ca.pem`: 指向Redis服务相关的CA证书文件，通常用于验证与Redis服务的SSL连接。
  - `system`: 指定信任系统默认的CA证书集合，这个值确保 Kong 的 Lua 代码在验证SSL连接时可以使用系统内置的可信根证书。

#### `lua_ssl_verify_depth`
- **作用**: 该配置项指定了SSL证书链的最大验证深度。值为2意味着在验证证书时，Kong会检查到第二级（通常是根CA和中间CA）来确认证书的有效性。

### 详细解读

- **SSL/TLS 证书链验证**: 
  - 在SSL/TLS通信中，服务器会提供一个证书链，通常包含服务器证书和中间CA证书。客户端需要验证这个链的每一级，直到找到一个被信任的根CA。
  - `lua_ssl_trusted_certificate` 提供了多个CA证书路径，以便 Kong 可以根据这些证书来验证通信中使用的证书是否可信。

- **多重证书信任**:
  - 在这种配置下，Kong会同时信任多个CA证书，并且这些证书可能来自不同的源，如你提到的控制平面和Redis。这样配置的目的通常是为了支持多种不同类型的SSL/TLS连接。

- **系统证书的作用**:
  - `system` 值的添加意味着不仅使用你指定的CA证书文件，还会使用操作系统中默认的信任链，这样可以增加灵活性。

通过这种配置，你可以确保Kong的数据平面在与不同的外部服务或控制平面进行SSL/TLS通信时，会根据正确的CA证书进行验证，从而保证通信的安全性。


下面是一个包含 `lua_ssl_trusted_certificate` 和 `lua_ssl_verify_depth` 配置的完整 `values.yaml` 文件示例，这是一个Kong Helm Chart的默认配置文件的简化版本。

```yaml
# Default values for Kong's Helm Chart

replicaCount: 1

image:
  repository: kong
  tag: 3.0
  pullPolicy: IfNotPresent

ingressController:
  enabled: true
  installCRDs: true

service:
  type: LoadBalancer
  port: 80

env:
  database: "off"
  role: "data_plane"
  cluster_cert: /etc/secrets/namespace-cp-cert-secret/tls.crt
  cluster_cert_key: /etc/secrets/namespace-cp-cert-secret/tls.key
  lua_ssl_trusted_certificate: /etc/secrets/namespace-cp-cert-secret/tls.crt,/etc/secrets/namespace-redis-secret/redis_ca.pem,system
  lua_ssl_verify_depth: 2

resources:
  limits:
    cpu: 500m
    memory: 256Mi
  requests:
    cpu: 250m
    memory: 128Mi

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

nodeSelector: {}

tolerations: []

affinity: {}

volumes:
  - name: cp-cert-secret
    secret:
      secretName: namespace-cp-cert-secret
  - name: redis-ca-secret
    secret:
      secretName: namespace-redis-secret

volumeMounts:
  - name: cp-cert-secret
    mountPath: /etc/secrets/namespace-cp-cert-secret
  - name: redis-ca-secret
    mountPath: /etc/secrets/namespace-redis-secret

rbac:
  create: true

serviceAccount:
  create: true
```

### 配置说明：
- **`env:` 部分**: 配置Kong的环境变量，其中包括了`lua_ssl_trusted_certificate`和`lua_ssl_verify_depth`的设置。这些配置会影响Kong的运行时行为，尤其是在处理SSL/TLS连接时的证书验证。
  
- **`volumes:` 和 `volumeMounts:` 部分**: 定义了将Kubernetes中的Secret挂载到容器内的路径，从而提供所需的证书文件。

- **`image:` 和 `replicaCount:` 等其他配置**: 设置Kong的镜像版本、实例数量等，这些是Kong Helm Chart的基本配置。

这个文件是一个简化版本，可以根据需要添加更多的配置。`lua_ssl_trusted_certificate` 和 `lua_ssl_verify_depth` 是Kong中用于SSL/TLS配置的关键部分，确保你的服务能够正确验证通信对方的身份。
