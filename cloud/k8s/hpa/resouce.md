# deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-deployment
  namespace: lex-ext-kdp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: demo-container
        image: nginx:latest
        resources:
          limits:
            cpu: "750m"
            memory: 200Mi
          requests:
            cpu: "500m"
            memory: 150Mi
```
# svc
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: lex-ext-kdp
spec:
  selector:
    app: my-app
  ports:
  - name: http
    port: 80
    targetPort: 80
  type: ClusterIP
```
# hpa
```yaml
apiVersion: autoscaling/v1
kind: HorizontalPodAutoscaler
metadata:
  name: demo-hpa
  namespace: lex-ext-kdp
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: demo-deployment
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 90
```
# get Detail
```bash
kubectl get rs -n lex-ext-kdp|grep demo
demo-deployment-6f78d67d9c   3         3         3       11m
 lex@Lexs-MacBook-Pro  ~/shell/k8s/hpa 
 ✔  5026  19:32:40
kubectl get hpa -n lex-ext-kdp|grep demo
demo-hpa   Deployment/demo-deployment   0%/90%    3         10        3          8m23s
 lex@Lexs-MacBook-Pro  ~/shell/k8s/hpa 
 ✔  5027  19:32:48
kubectl get deploy -n lex-ext-kdp|grep demo
demo-deployment   3/3     3            3           12m
 lex@Lexs-MacBook-Pro  ~/shell/k8s/hpa 
 ✔  5028  19:32:58
kubectl get svc -n lex-ext-kdp|grep demo
 lex@Lexs-MacBook-Pro  ~/shell/k8s/hpa 
 0|1 ↵  5029  19:33:09
kubectl get svc -n lex-ext-kdp
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
my-service   ClusterIP   10.43.179.130   <none>        80/TCP    7m30s
```
