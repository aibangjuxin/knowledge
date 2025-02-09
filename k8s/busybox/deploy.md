~/deploy # kubectl create ns lex                                                                                                                                              admin@NASLEX
namespace/lex created
----------------------
- deployment busybox
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox-deployment
  labels:
    app: busybox
spec:
  replicas: 1
  selector:
    matchLabels:
      app: busybox
  template:
    metadata:
      labels:
        app: busybox
    spec:
      containers:
      - name: busybox
        image: busybox:latest
        imagePullPolicy: Never    # 添加这行，强制使用本地镜像
        command:
        - sleep
        - "3600"
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
```
~/deploy # kubectl apply -f deploy.yaml -n lex                                                                                                                                admin@NASLEX
deployment.apps/busybox-deployment created
--------------------------------------------
~/deploy # kubectl logs -f busybox-deployment-6d897b6dc7-s4gws -n lex                                                                                                         admin@NASLEX
Error from server (BadRequest): container "busybox" in pod "busybox-deployment-6d897b6dc7-s4gws" is waiting to start: ContainerCreating
------------------------------------------------------------


Events:
  Type     Reason     Age                   From               Message
  ----     ------     ----                  ----               -------
  Normal   Scheduled  9m3s                  default-scheduler  Successfully assigned lex/busybox-deployment-6d897b6dc7-s4gws to qnap-k3s-q21ca01210
  Warning  Failed     5m25s (x3 over 8m3s)  kubelet            Failed to pull image "busybox:latest": rpc error: code = Unknown desc = failed to pull and unpack image "docker.io/library/busybox:latest": failed to resolve reference "docker.io/library/busybox:latest": failed to do request: Head "https://registry-1.docker.io/v2/library/busybox/manifests/latest": dial tcp 199.96.59.19:443: i/o timeout
  Normal   Pulling    4m35s (x4 over 9m3s)  kubelet            Pulling image "busybox:latest"
  Warning  Failed     3m35s                 kubelet            Failed to pull image "busybox:latest": rpc error: code = Unknown desc = failed to pull and unpack image "docker.io/library/busybox:latest": failed to resolve reference "docker.io/library/busybox:latest": failed to do request: Head "https://registry-1.docker.io/v2/library/busybox/manifests/latest": dial tcp 69.30.25.21:443: i/o timeout
  Warning  Failed     3m35s (x4 over 8m3s)  kubelet            Error: ErrImagePull
  Normal   BackOff    3m6s (x7 over 8m3s)   kubelet            Back-off pulling image "busybox:latest"
  Warning  Failed     3m6s (x7 over 8m3s)   kubelet            Error: ImagePullBackOff

比如我本地有这个包?
docker images
能看到
~/deploy # docker images|grep busy                                                                                                                                            admin@NASLEX
busybox                              latest          62aedd01bd85   2 years ago     1.24MB


