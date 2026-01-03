```bash
set 
登录 QNAP 管理后台（QTS），进入**控制面板** → **网络与文件服务** → **网络** → **TCP/IP**

为了防止每次启动的时候都要拉取最新的配置。 把所有的 deploy里面的配置直接修改成。 imagePullPolicy: IfNotPresent
这样的好处就是如果我本地存在这个景象 ，那么就不需要再次拉取 而且我可以直接走我的本地的 Docker 的代理来拿去对应的文件。 

docke ps -a
CONTAINER ID   IMAGE                                           COMMAND                  CREATED              STATUS                           PORTS                                                                    NAMES
1213af7b16dc   rancher/k3s:v1.21.1-k3s1                        "/bin/k3s server --c…"   About a minute ago   Created

Docker logs 1213af7b16dc
[~] # docker logs 1213af7b16dc
time="2025-11-30T05:05:21.887568529Z" level=info msg="Starting k3s v1.21.1+k3s1 (75dba57f)"
time="2025-11-30T05:05:21.890891560Z" level=info msg="Cluster bootstrap already complete"
time="2025-11-30T05:05:22.043174157Z" level=info msg="certificate CN=kube-apiserver signed by CN=k3s-server-ca@1655005412: notBefore=2022-06-12 03:43:32 +0000 UTC notAfter=2026-11-30 05:05:22 +0000 UTC"
time="2025-11-30T05:05:22.072854240Z" level=info msg="certificate CN=etcd-server signed by CN=etcd-server-ca@1655005412: notBefore=2022-06-12 03:43:32 +0000 UTC notAfter=2026-11-30 05:05:22 +0000 UTC"
time="2025-11-30T05:05:22.100806349Z" level=info msg="certificate CN=etcd-peer signed by CN=etcd-peer-ca@1655005412: notBefore=2022-06-12 03:43:32 +0000 UTC notAfter=2026-11-30 05:05:22 +0000 UTC"
time="2025-11-30T05:05:22.107573159Z" level=info msg="certificate CN=k3s,O=k3s signed by CN=k3s-server-ca@1655005412: notBefore=2022-06-12 03:43:32 +0000 UTC notAfter=2026-11-30 05:05:22 +0000 UTC"
time="2025-11-30T05:05:22.112298798Z" level=info msg="Active TLS secret  (ver=) (count 8): map[listener.cattle.io/cn-10.0.3.8:10.0.3.8 listener.cattle.io/cn-10.43.0.1:10.43.0.1 listener.cattle.io/cn-127.0.0.1:127.0.0.1 listener.cattle.io/cn-192.168.31.88:192.168.31.88 listener.cattle.io/cn-kubernetes:kubernetes listener.cattle.io/cn-kubernetes.default:kubernetes.default listener.cattle.io/cn-kubernetes.default.svc.cluster.local:kubernetes.default.svc.cluster.local listener.cattle.io/cn-localhost:localhost listener.cattle.io/fingerprint:SHA1=2C8A6351669AEAF679301581C1B6A752953ADE5B]"
time="2025-11-30T05:05:22.151809830Z" level=info msg="Configuring sqlite3 database connection pooling: maxIdleConns=2, maxOpenConns=0, connMaxLifetime=0s"
time="2025-11-30T05:05:22.156417902Z" level=info msg="Configuring database table schema and indexes, this may take a moment..."
time="2025-11-30T05:05:22.157183771Z" level=info msg="Database tables and indexes are up to date"
time="2025-11-30T05:05:22.206575746Z" level=info msg="Kine listening on unix://kine.sock"
time="2025-11-30T05:05:22.219587474Z" level=info msg="Running kube-apiserver --advertise-port=6443 --allow-privileged=true --anonymous-auth=false --api-audiences=https://kubernetes.default.svc.cluster.local,k3s --authorization-mode=Node,RBAC --bind-address=127.0.0.1 --cert-dir=/var/lib/rancher/k3s/server/tls/temporary-certs --client-ca-file=/var/lib/rancher/k3s/server/tls/client-ca.crt --enable-admission-plugins=NodeRestriction --etcd-servers=unix://kine.sock --insecure-port=0 --kubelet-certificate-authority=/var/lib/rancher/k3s/server/tls/server-ca.crt --kubelet-client-certificate=/var/lib/rancher/k3s/server/tls/client-kube-apiserver.crt --kubelet-client-key=/var/lib/rancher/k3s/server/tls/client-kube-apiserver.key --profiling=false --proxy-client-cert-file=/var/lib/rancher/k3s/server/tls/client-auth-proxy.crt --proxy-client-key-file=/var/lib/rancher/k3s/server/tls/client-auth-proxy.key --requestheader-allowed-names=system:auth-proxy --requestheader-client-ca-file=/var/lib/rancher/k3s/server/tls/request-header-ca.crt --requestheader-extra-headers-prefix=X-Remote-Extra- --requestheader-group-headers=X-Remote-Group --requestheader-username-headers=X-Remote-User --secure-port=6444 --service-account-issuer=https://kubernetes.default.svc.cluster.local --service-account-key-file=/var/lib/rancher/k3s/server/tls/service.key --service-account-signing-key-file=/var/lib/rancher/k3s/server/tls/service.key --service-cluster-ip-range=10.43.0.0/16 --service-node-port-range=61000-62000 --storage-backend=etcd3 --tls-cert-file=/var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt --tls-private-key-file=/var/lib/rancher/k3s/server/tls/serving-kube-apiserver.key"
Flag --insecure-port has been deprecated, This flag has no effect now and will be removed in v1.24.
I1130 05:05:22.240962       1 server.go:656] external host was not specified, using 10.0.3.8
I1130 05:05:22.249400       1 server.go:195] Version: v1.21.1+k3s1
I1130 05:05:22.320349       1 plugins.go:158] Loaded 12 mutating admission controller(s) successfully in the following order: NamespaceLifecycle,LimitRanger,ServiceAccount,NodeRestriction,TaintNodesByCondition,Priority,DefaultTolerationSeconds,DefaultStorageClass,StorageObjectInUseProtection,RuntimeClass,DefaultIngressClass,MutatingAdmissionWebhook.
I1130 05:05:22.327763       1 shared_informer.go:240] Waiting for caches to sync for node_authorizer
I1130 05:05:22.327849       1 plugins.go:161] Loaded 10 validating admission controller(s) successfully in the following order: LimitRanger,ServiceAccount,Priority,PersistentVolumeClaimResize,RuntimeClass,CertificateApproval,CertificateSigning,CertificateSubjectRestriction,ValidatingAdmissionWebhook,ResourceQuota.
I1130 05:05:22.338794       1 plugins.go:158] Loaded 12 mutating admission controller(s) successfully in the following order: NamespaceLifecycle,LimitRanger,ServiceAccount,NodeRestriction,TaintNodesByCondition,Priority,DefaultTolerationSeconds,DefaultStorageClass,StorageObjectInUseProtection,RuntimeClass,DefaultIngressClass,MutatingAdmissionWebhook.
I1130 05:05:22.352400       1 plugins.go:161] Loaded 10 validating admission controller(s) successfully in the following order: LimitRanger,ServiceAccount,Priority,PersistentVolumeClaimResize,RuntimeClass,CertificateApproval,CertificateSigning,CertificateSubjectRestriction,ValidatingAdmissionWebhook,ResourceQuota.
I1130 05:05:22.813235       1 instance.go:283] Using reconciler: lease
I1130 05:05:23.283747       1 trace.go:205] Trace[37883267]: "List etcd3" key:/apiextensions.k8s.io/customresourcedefinitions,resourceVersion:,resourceVersionMatch:,limit:10000,continue: (30-Nov-2025 05:05:22.411) (total time: 871ms):
Trace[37883267]: [871.755732ms] [871.755732ms] END
I1130 05:05:23.845956       1 trace.go:205] Trace[1822654668]: "List etcd3" key:/secrets,resourceVersion:,resourceVersionMatch:,limit:10000,continue: (30-Nov-2025 05:05:23.199) (total time: 646ms):
Trace[1822654668]: [646.271554ms] [646.271554ms] END
I1130 05:05:23.905461       1 trace.go:205] Trace[118042265]: "List etcd3" key:/apiextensions.k8s.io/customresourcedefinitions,resourceVersion:,resourceVersionMatch:,limit:10000,continue: (30-Nov-2025 05:05:22.373) (total time: 1531ms):
Trace[118042265]: [1.531499394s] [1.531499394s] END
I1130 05:05:23.947177       1 rest.go:130] the default service ipfamily for this cluster is: IPv4




time="2025-11-30T05:07:16.351450223Z" level=info msg="Running kube-apiserver --advertise-port=6443 --allow-privileged=true --anonymous-auth=false --api-audiences=https://kubernetes.default.svc.cluster.local,k3s --authorization-mode=Node,RBAC --bind-address=127.0.0.1 --cert-dir=/var/lib/rancher/k3s/server/tls/temporary-certs --client-ca-file=/var/lib/rancher/k3s/server/tls/client-ca.crt --enable-admission-plugins=NodeRestriction --etcd-servers=unix://kine.sock --insecure-port=0 --kubelet-certificate-authority=/var/lib/rancher/k3s/server/tls/server-ca.crt --kubelet-client-certificate=/var/lib/rancher/k3s/server/tls/client-kube-apiserver.crt --kubelet-client-key=/var/lib/rancher/k3s/server/tls/client-kube-apiserver.key --profiling=false --proxy-client-cert-file=/var/lib/rancher/k3s/server/tls/client-auth-proxy.crt --proxy-client-key-file=/var/lib/rancher/k3s/server/tls/client-auth-proxy.key --requestheader-allowed-names=system:auth-proxy --requestheader-client-ca-file=/var/lib/rancher/k3s/server/tls/request-header-ca.crt --requestheader-extra-headers-prefix=X-Remote-Extra- --requestheader-group-headers=X-Remote-Group --requestheader-username-headers=X-Remote-User --secure-port=6444 --service-account-issuer=https://kubernetes.default.svc.cluster.local --service-account-key-file=/var/lib/rancher/k3s/server/tls/service.key --service-account-signing-key-file=/var/lib/rancher/k3s/server/tls/service.key --service-cluster-ip-range=10.43.0.0/16 --service-node-port-range=61000-62000 --storage-backend=etcd3 --tls-cert-file=/var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt --tls-private-key-file=/var/lib/rancher/k3s/server/tls/serving-kube-apiserver.key

[~] # docker ps -a
CONTAINER ID   IMAGE                                           COMMAND                  CREATED             STATUS                           PORTS                                                                    NAMES
1213af7b16dc   rancher/k3s:v1.21.1-k3s1                        "/bin/k3s server --c…"   4 minutes ago       Up About a minute                0.0.0.0:6443->6443/tcp, 0.0.0.0:61000-62000->61000-62000/tcp
```


all images 
```bash
➜  ~ kubectl get deploy -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.template.spec.containers[*].image}{"\n"}{end}'
lex-ext-kdp     app     nginx
lex-ext-kdp     demo-deployment nginx:latest
bass-int-kdp    busybox-app     busybox:latest
lex-ext-kdp     busybox-app     busybox:latest
bass-int-kdp    abj-ccom-gcp-wcas-ukal-wrapper-papi-1-0-15-deployment   busybox:latest
kubernetes-dashboard    kubernetes-dashboard    kubernetesui/dashboard:v2.2.0
lex     complex-web-app nginx:latest redis:7-alpine prom/node-exporter:latest
default squid-proxy-with-health-check   squid:latest python:3.9-slim
cert-manager    cert-manager-cainjector quay.io/jetstack/cert-manager-cainjector:v1.11.0
cert-manager    cert-manager    quay.io/jetstack/cert-manager-controller:v1.11.0
kube-system     local-path-provisioner  rancher/local-path-provisioner:v0.0.19
kube-system     coredns rancher/coredns-coredns:1.8.3
kubernetes-dashboard    dashboard-metrics-scraper       kubernetesui/metrics-scraper:v1.0.6
kube-system     metrics-server  rancher/metrics-server:v0.3.6
cert-manager    cert-manager-webhook    quay.io/jetstack/cert-manager-webhook:v1.11.0
lex     nginx-deployment        nginx:latest
ingress-nginx   ingress-nginx-controller        swr.cn-north-4.myhuaweicloud.com/ddn-k8s/registry.k8s.io/ingress-nginx/controller:v1.13.2
```

pull images
```bash
[~] # docker images -a|grep squid
[~] # kubectl edit deployment squid-proxy-with-health-check  -n default
Edit cancelled, no changes made.
[~] # docker pull squid:latest
Error response from daemon: pull access denied for squid, repository does not exist or may require 'docker login': denied: requested access to the resource is denied
[~] # docker login
Log in with your Docker ID or email address to push and pull images from Docker Hub. If you don't have a Docker ID, head over to https://hub.docker.com/ to create one.
You can log in with your password or a Personal Access Token (PAT). Using a limited-scope PAT grants better security and is required for organizations using SSO. Learn more at https://docs.docker.com/go/access-tokens/

Username: my
Password:
WARNING! Your password will be stored unencrypted in /share/CACHEDEV1_DATA/.qpkg/container-station/homes/admin/.docker/config.json.
Configure a credential helper to remove this warning. See
https://docs.docker.com/engine/reference/commandline/login/#credential-stores

Login Succeeded
[~] # docker pull squid:latest
Error response from daemon: pull access denied for squid, repository does not exist or may require 'docker login': denied: requested access to the resource is denied
[~] # docker pull ubuntu/squid:4.10-20.04_beta
4.10-20.04_beta: Pulling from ubuntu/squid
087395764bcf: Pull complete
a24cee7a0f22: Pull complete
c68c13277209: Pull complete
Digest: sha256:df4a60ef617add9e86fec9061df03bd5627325596f96b39a199f83aad81f4152
Status: Downloaded newer image for ubuntu/squid:4.10-20.04_beta
docker.io/ubuntu/squid:4.10-20.04_beta


[~] # docker tag  ubuntu/squid:4.10-20.04_beta squid:latest
```