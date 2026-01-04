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