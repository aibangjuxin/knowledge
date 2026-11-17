- reference
- [docker-proxy](docker-proxy.md)



```bash
/share/CACHEDEV1_DATA/.qpkg/container-station/etc/systemd/system/docker.service.d/
sh-3.2# cd /share/CACHEDEV1_DATA/.qpkg/container-station/etc/systemd/system/docker.service.d/
sh-3.2# ls
http-proxy.conf
sh-3.2# cat http-proxy.conf 
[Service]
Environment="HTTP_PROXY=http://192.168.31.198:7222"
Environment="HTTPS_PROXY=http://192.168.31.198:7222"
Environment="NO_PROXY=localhost,127.0.0.1"
sh-3.2# su
```

- if proxy not work, the error is next

```bash
sh-3.2# docker pull praqma/network-multitool
Using default tag: latest
Error response from daemon: Get "https://registry-1.docker.io/v2/": proxyconnect tcp: dial tcp 192.168.31.198:7222: connect: connection refused
```

- veify my proxy setting 

```bash
sh-3.2# docker pull praqma/network-multitool
Using default tag: latest
latest: Pulling from praqma/network-multitool
5758d4e389a3: Pull complete 
89d2c42e021e: Pull complete 
c56ef2f6b498: Pull complete 
fb4370a69dda: Pull complete 
003f3d74368c: Pull complete 
cd3def2cca55: Pull complete 
ba5a2b2d204e: Pull complete 
Digest: sha256:97b15098bb72df10f7c4e177b9c0e2435ec459f16e79ab7ae2ed3f1eb0e79d19
Status: Downloaded newer image for praqma/network-multitool:latest
docker.io/praqma/network-multitool:latest
```

# nas enable local registry

# # 在NAS上执行：启动本地私有仓库，端口用5000（可自定义），数据持久化到NAS的目录（比如/mnt/nas-disk/docker-registry）
```bash
docker run -d \
  --name local-registry \
  --restart=always \  # 开机自启，保证仓库一直运行
  -p 5000:5000 \
  -v /mnt/nas-disk/docker-registry:/var/lib/registry \  # 把仓库数据存到NAS磁盘（替换成你NAS的实际目录）
  registry:2
```

# 在NAS上执行：启动本地私有仓库，端口用5000（可自定义），数据持久化到NAS的目录（比如/mnt/nas-disk/docker-registry）

/share/CACHEDEV3_DATA/docker-registry

```bash
docker run -d \
  --name local-registry \
  --restart=always \
  -p 5000:5000 \
  -v /share/CACHEDEV3_DATA/docker-registry:/var/lib/registry \
  registry:2

sh-3.2# docker run -d \
>   --name local-registry \
>   --restart=always \
>   -p 5000:5000 \
>   -v /share/CACHEDEV3_DATA/docker-registry:/var/lib/registry \
>   registry:2
Unable to find image 'registry:2' locally
2: Pulling from library/registry
44cf07d57ee4: Pull complete 
bbbdd6c6894b: Pull complete 
8e82f80af0de: Pull complete 
3493bf46cdec: Pull complete 
6d464ea18732: Pull complete 
Digest: sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373
Status: Downloaded newer image for registry:2
5b6b8ca82005f3039bb05a4b5aa674c51cf69b5345a800205086aa7e9dd7b34d
```
---
```bash
sh-3.2#   -p 5000:5000 \
>   -v /share/CACHEDEV3_DATA/docker-registry:/var/lib/registry 
sh: -p: command not found
sh-3.2#   registry:2
sh-3.2# docker run -d \
>   --name local-registry \
>   --restart=always \
>   -p 5000:5000 \
>   -v /share/CACHEDEV3_DATA/docker-registry:/var/lib/registry \
>   registry:2
Unable to find image 'registry:2' locally
2: Pulling from library/registry
44cf07d57ee4: Pull complete 
bbbdd6c6894b: Pull complete 
8e82f80af0de: Pull complete 
3493bf46cdec: Pull complete 
6d464ea18732: Pull complete 
Digest: sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373
Status: Downloaded newer image for registry:2
5b6b8ca82005f3039bb05a4b5aa674c51cf69b5345a800205086aa7e9dd7b34d
sh-3.2# curl http://192.168.31.188:5000/v2/_catalog
```
- `docker ps` ==〉 K3S 并不是直接装在 NAS 系统里，而是以容器化方式rancher/k3s:v1.21.1-k3s1容器，名称qnap-k3s）运行的
```bash 
sh-3.2# docker ps -a
CONTAINER ID   IMAGE                                           COMMAND                  CREATED              STATUS                       PORTS                                                                    NAMES
5b6b8ca82005   registry:2                                      "/entrypoint.sh /etc…"   About a minute ago   Up About a minute            0.0.0.0:5000->5000/tcp                                                   local-registry
1213af7b16dc   rancher/k3s:v1.21.1-k3s1                        "/bin/k3s server --c…"   5 weeks ago          Up 2 weeks                   0.0.0.0:6443->6443/tcp, 0.0.0.0:61000-62000->61000-62000/tcp             qnap-k3s

sh-3.2# curl http://localhost:5000/v2/_catalog -v     
* Host localhost:5000 was resolved.
* IPv6: ::1
* IPv4: 127.0.0.1
*   Trying [::1]:5000...
* connect to ::1 port 5000 from ::1 port 47578 failed: Connection refused
*   Trying 127.0.0.1:5000...
* Connected to localhost (127.0.0.1) port 5000
> GET /v2/_catalog HTTP/1.1
> Host: localhost:5000
> User-Agent: curl/8.5.0
> Accept: */*
> 
< HTTP/1.1 200 OK
< Content-Type: application/json; charset=utf-8
< Docker-Distribution-Api-Version: registry/2.0
< X-Content-Type-Options: nosniff
< Date: Sat, 10 Jan 2026 02:54:56 GMT
< Content-Length: 20
< 
{"repositories":[]}
* Connection #0 to host localhost left intact

```
- verify local registry
```bash
# 访问仓库的健康检查接口（NAS_IP是你的NAS局域网IP，比如192.168.1.100）
curl http://<NAS_IP>:5000/v2/_catalog
# 正常返回：{"repositories":[]}（表示仓库是空的）

curl http://192.168.31.88:5000/v2/_catalog
```
- add tags to local registry
```bash
docker tag python-health-demo:latest 192.168.31.88:5000/python-health-demo:latest
```
- push to local registry
```bash
docker push 192.168.31.88:5000/python-health-demo:latest
```
---
```bash
sh-3.2# docker push 192.168.31.88:5000/python-health-demo:latest
The push refers to repository [192.168.31.88:5000/python-health-demo]
1afdb6b7f0f3: Pushed 
7000473976e0: Pushed 
c4324dc588c9: Pushed 
a7139ad7b07b: Pushed 
c8f6b54339a8: Pushed 
298992e09a03: Pushed 
4f237755fbae: Pushed 
d7c97cb6f1fe: Pushed 
latest: digest: sha256:cc0db251e80e1400caeb720fbe2257eb4de1d08d2f69c6fd6f55e79ab508a30d size: 1991
```

 192.168.31.88:5000/python-health-demo:latest


 - edit ymal 

```bash
Events:
  Type     Reason     Age                      From               Message
  ----     ------     ----                     ----               -------
  Normal   Scheduled  21s                      default-scheduler  Successfully assigned python-demo/python-health-demo-v2025-11-24-76c77b4c48-sxr4c to qnap-k3s-q21ca01210
  Normal   Pulling    7s (x2 over 21s)         kubelet            Pulling image "192.168.31.88:5000/python-health-demo:latest"
  Warning  Failed     7s (x2 over 21s)         kubelet            Failed to pull image "192.168.31.88:5000/python-health-demo:latest": rpc error: code = Unknown desc = failed to pull and unpack image "192.168.31.88:5000/python-health-demo:latest": failed to resolve reference "192.168.31.88:5000/python-health-demo:latest": failed to do request: Head "https://192.168.31.88:5000/v2/python-health-demo/manifests/latest": http: server gave HTTP response to HTTPS client
  Warning  Failed     7s (x2 over 21s)         kubelet            Error: ErrImagePull
  Normal   BackOff    <invalid> (x2 over 21s)  kubelet            Back-off pulling image "192.168.31.88:5000/python-health-demo:latest"
  Warning  Failed     <invalid> (x2 over 21s)  kubelet            Error: ImagePullBackOff
```


# push to docker hub 

docker tag python-health-demo:latest aibangjuxin/python:python-health-demo


```bash
sh-3.2# docker tag python-health-demo:latest aibangjuxin/python:python-health-demo
sh-3.2# docker push aibangjuxin/python:python-health-demo
The push refers to repository [docker.io/aibangjuxin/python]
1afdb6b7f0f3: Pushed 
7000473976e0: Pushed 
c4324dc588c9: Pushed 
a7139ad7b07b: Pushed 
c8f6b54339a8: Mounted from library/python 
298992e09a03: Mounted from library/python 
4f237755fbae: Mounted from library/python 
d7c97cb6f1fe: Mounted from library/python 
python-health-demo: digest: sha256:414ef90cf85d265ac50a64813088968bf60c6cd7cd0c10e3dfa59b3608dd4fbf size: 1991
```