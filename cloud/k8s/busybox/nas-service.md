```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  labels:
    app: nginx-deployment
spec:
  type: ClusterIP
  ports:
    - port: 80          # Service 暴露的端口
      targetPort: 80    # Pod 的目标端口
      protocol: TCP
      name: http
  selector:
    app: nginx-deployment  # 与 Deployment 中的 Pod labels 匹配
```

kubectl apply -f service.yaml -n lex                               admin@NASLEX
service/nginx-service created

```bash
~/deploy # kubectl get svc -n lex                                             admin@NASLEX
NAME            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
nginx-service   ClusterIP   10.43.89.132   <none>        80/TCP    13s

~/deploy # kubectl get endpoints -n lex                                       admin@NASLEX
NAME            ENDPOINTS                                               AGE
nginx-service   10.42.0.61:80,10.42.0.62:80,10.42.0.63:80 + 1 more...   26s
------------------------------------------------------------

~/deploy # kubectl describe endpoints nginx-service  -n lex                   admin@NASLEX
Name:         nginx-service
Namespace:    lex
Labels:       app=nginx-deployment
Annotations:  endpoints.kubernetes.io/last-change-trigger-time: 2025-02-15T02:24:45Z
Subsets:
  Addresses:          10.42.0.61,10.42.0.62,10.42.0.63,10.42.0.64
  NotReadyAddresses:  <none>
  Ports:
    Name  Port  Protocol
    ----  ----  --------
    http  80    TCP

Events:  <none>
```
- edit servce 
```bash
kubectl apply -f service.yaml -n lex                               admin@NASLEX
service/nginx-service created
```
- yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  labels:
    app: nginx-deployment
spec:
  type: NodePort       # 将 ClusterIP 改为 NodePort
  ports:
    - port: 80        # 集群内部访问端口
      targetPort: 80  # Pod 端口
      nodePort: 61001 # 节点端口(可选，不指定会随机分配30000-32767)
      protocol: TCP
      name: http
  selector:
    app: nginx-deployment
```


```bash
------------------------------------------------------------
~/deploy # kubectl get endpoints -n lex                                       admin@NASLEX
NAME            ENDPOINTS                                               AGE
nginx-service   10.42.0.61:80,10.42.0.62:80,10.42.0.63:80 + 1 more...   49s
------------------------------------------------------------
~/deploy # kubectl get svc -n lex                                             admin@NASLEX
NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
nginx-service   NodePort   10.43.110.221   <none>        80:61001/TCP   57s
------------------------------------------------------------
```
- curl
```bash
~/deploy # curl -I http://localhost:61001                                     admin@NASLEX
HTTP/1.1 200 OK
Server: nginx/1.25.5
Date: Sat, 15 Feb 2025 02:32:42 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Tue, 16 Apr 2024 14:29:59 GMT
Connection: keep-alive
ETag: "661e8b67-267"
Accept-Ranges: bytes
```

curl -I http://192.168.31.88:61001
HTTP/1.1 200 OK
Server: nginx/1.25.5
Date: Sat, 15 Feb 2025 02:33:41 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Tue, 16 Apr 2024 14:29:59 GMT
Connection: keep-alive
ETag: "661e8b67-267"
Accept-Ranges: bytes