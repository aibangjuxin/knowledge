- nginx-deployment.yaml
```bash
kubectl apply -f nginx-deployment.yaml -n lex                      admin@NASLEX
deployment.apps/nginx-deployment created
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx-deployment
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # 更新过程中最多可以比原先设置多出的 Pod 数量
      maxUnavailable: 1  # 更新过程中最多允许多少个 Pod 处于无法提供服务的状态
  selector:
    matchLabels:
      app: nginx-deployment
  template:
    metadata:
      labels:
        app: nginx-deployment
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        imagePullPolicy: Never    # 强制使用本地镜像
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            scheme: HTTP
            path: /
            port: 80  # 请替换为实际端口号
          periodSeconds: 20
          failureThreshold: 3
          timeoutSeconds: 3
        livenessProbe:
          httpGet:
            scheme: HTTP
            path: /
            port: 80  # 请替换为实际端口号
          periodSeconds: 20
          failureThreshold: 3
          timeoutSeconds: 3
        startupProbe:
          httpGet:
            scheme: HTTP
            path: /
            port: 80  # 请替换为实际端口号
          periodSeconds: 10
          failureThreshold: 30
```

- verify my nginx 
```bash
root@nginx-deployment-5f65f66f6d-8bqh9:/etc/nginx/conf.d# pwd
/etc/nginx/conf.d
root@nginx-deployment-5f65f66f6d-8bqh9:/etc/nginx/conf.d# /sbin/nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```