# Python Health Check & Env Var Demo

This project simulates a Kubernetes-ready microservice implemented in Python (Flask). 
It demonstrates how to handle Environment Variables, Health Probes, and HTTPS with password-protected keys.

## Features

1.  **Environment Variables**:
    *   `BASE_PATH`: Sets the prefix for all API routes (e.g., `/api/v1`).
    *   `API_NAME`: Sets the service name (simulating `apiName`).
    *   `MINOR_VERSION`: Sets the version (simulating `minorVersion`).
    *   `HTTPS_CERT_PWD`: Password to unlock the SSL private key.

2.  **Health Probes** (under `BASE_PATH`):
    *   `/well-known/liveness`: Returns 200 OK if the process is running.
    *   `/well-known/readiness`: Returns 200 OK if ready to serve.
    *   `/well-known/startup`: Returns 503 until initialization (5s delay) is complete.

3.  **HTTPS**:
    *   Runs on port `8443`.
    *   Requires `cert.pem` and `key.pem`.
    *   Supports encrypted private keys via `HTTPS_CERT_PWD`.

```bash
  已实现的功能：

   1. 环境变量支持：
       * BASE_PATH: 控制 API 路由前缀（例如 /api-name-spring-samples/v2025.11.24）。
       * API_NAME (对应您提到的 name): 返回 API 名称。
       * MINOR_VERSION: 返回版本号。
       * HTTPS_CERT_PWD: 用于解密 HTTPS 私钥。

   2. Health Probes (探针)：
       * livenessProbe: /well-known/liveness
       * readinessProbe: /well-known/readiness
       * startupProbe: /well-known/startup (模拟了 5 秒的启动延迟)。

   3. HTTPS 安全支持：
       * 使用自签名证书运行在 8443 端口。
       * 支持使用密码保护的私钥（通过环境变量解密）。

  项目结构：

   1 python-health-demo/
   2 ├── app.py              # 主程序 (Flask)
   3 ├── Dockerfile          # 容器化构建文件
   4 ├── generate_certs.sh   # 证书生成脚本
   5 ├── requirements.txt    # 依赖库
   6 └── README.md           # 使用说明
```

## Setup & Run Locally

### 1. Prerequisites
*   Python 3.x
*   OpenSSL

### 2. Generate Certificates
Run the helper script to generate `key.pem` and `cert.pem`.
You can optionally set the password via env var.

```bash
export HTTPS_CERT_PWD="mypassword"
./generate_certs.sh
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

### 4. Run the Application

```bash
export BASE_PATH="/api/v1"
export API_NAME="demo-service"
export MINOR_VERSION="2025.01.01"
export HTTPS_CERT_PWD="mypassword"

python app.py
```

### 5. Verify

Visit: `https://localhost:8443/api/v1/info`
(You will need to ignore the self-signed certificate warning)

Check probes:
*   `https://localhost:8443/api/v1/well-known/liveness`
*   `https://localhost:8443/api/v1/well-known/readiness`
*   `https://localhost:8443/api/v1/well-known/startup`

## Run with Docker

1.  **Build**:
```bash
docker pull python:3.9-slim
cd /share/CACHEDEV3_DATA/python-health-demo
docker build -t python-health-demo .
sh-3.2# docker build -t python-health-demo .
[+] Building 12.4s (10/10) FINISHED                                                                                                         docker:default
 => [internal] load build definition from Dockerfile                                                                                                  0.1s
 => => transferring dockerfile: 464B                                                                                                                  0.0s
 => [internal] load metadata for docker.io/library/python:3.9-slim                                                                                    0.0s
 => [internal] load .dockerignore                                                                                                                     0.1s
 => => transferring context: 2B                                                                                                                       0.0s
 => [1/5] FROM docker.io/library/python:3.9-slim                                                                                                      0.2s
 => [internal] load build context                                                                                                                     0.1s
 => => transferring context: 6.28kB                                                                                                                   0.0s
 => [2/5] WORKDIR /app                                                                                                                                0.1s
 => [3/5] COPY requirements.txt .                                                                                                                     0.1s
 => [4/5] RUN pip install --no-cache-dir -r requirements.txt                                                                                         10.3s
 => [5/5] COPY . .                                                                                                                                    0.2s 
 => exporting to image                                                                                                                                1.1s 
 => => exporting layers                                                                                                                               1.1s 
 => => writing image sha256:6e5692a1db3ad42438fef1b0c14251d46659edc51071ee7e8f42df4785865d69                                                          0.0s 
 => => naming to docker.io/library/python-health-demo 
```
- verify the images 
```bash
docker images
sh-3.2# docker images -a
REPOSITORY                                                                                    TAG               IMAGE ID       CREATED         SIZE
python-health-demo                                                                            latest            6e5692a1db3a   2 minutes ago   132MB
```

2.  **Run**:
    ```bash
    docker run -it -p 8443:8443 \
      -e BASE_PATH="/custom/path" \
      -e API_NAME="docker-service" \
      -e HTTPS_CERT_PWD="mypassword" \
      -v $(pwd)/cert.pem:/app/cert.pem \
      -v $(pwd)/key.pem:/app/key.pem \
      python-health-demo
    ```



# Use k8s to run the app

  生成的文件列表：

   1. `secret.yaml`: 定义了 HTTPS_CERT_PWD 密钥。
   2. `deployment-v2025-11-24.yaml`: 
       * MINOR_VERSION: 2025.11.24
       * BASE_PATH: /api-name-spring-samples/v2025.11.24
   3. `deployment-v2025-11-25.yaml`: 
       * MINOR_VERSION: 2025.11.25
       * BASE_PATH: /api-name-spring-samples/v2025.11.25
   4. `service.yaml`: 统一暴露 8443 端口，代理到所有 app: python-health-demo 的 Pod。

## 部署步骤：
###  create a namespace 
- for this demo python-demo
- 应用 Secret (确保您之前生成证书时使用的密码与 secret.yaml 中一致，默认为 "changeit")：
```bash
kubectl apply -f python-health-demo/k8s/secret.yaml -n python-demo
```

- 检查 Secret 是否创建成功：
```bash
k get secret -n python-demo
NAME                        TYPE                                  DATA   AGE
default-token-45cgp         kubernetes.io/service-account-token   3      119m
python-health-demo-secret   Opaque                                1      111m
```

###  apply Deployments

- apply v2025-11-24
```bash
kubectl apply -f python-health-demo/k8s/deployment-v2025-11-24.yaml -n python-demo
```

- apply v2025-11-25
```bash
kubectl apply -f python-health-demo/k8s/deployment-v2025-11-25.yaml -n python-demo
```

###  apply Service
```bash
kubectl apply -f python-health-demo/k8s/service.yaml -n python-demo

 k get svc -n python-demo
NAME                     TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
python-health-demo-svc   ClusterIP   10.43.32.115   <none>        8443/TCP   5m45s
```
### get pod 

```bash
k get pods -n python-demo
NAME                                              READY   STATUS    RESTARTS   AGE
python-health-demo-v2025-11-24-6b4676f9d9-42wnj   1/1     Running   0          9m47s
python-health-demo-v2025-11-25-65d5fd5895-t6gt8   1/1     Running   0          2m42s
```


###  login pod 

 k exec -it python-health-demo-v2025-11-24-6b4676f9d9-42wnj -n python-demo -- /bin/bash
root@python-health-demo-v2025-11-24-6b4676f9d9-42wnj:/app#


- verify the https liveness
- `/api-name-spring-samples/v2025.11.24/well-known/liveness`
**推荐使用 `printf` 方式（最精确）：**
```bash
printf "GET /api-name-spring-samples/v2025.11.24/well-known/liveness HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | openssl s_client -connect localhost:8443 -quiet 2>/dev/null

root@python-health-demo-v2025-11-24-6b4676f9d9-42wnj:/app# printf "GET /api-name-spring-samples/v2025.11.24/well-known/liveness HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | openssl s_client -connect localhost:8443 -quiet 2>/dev/null
HTTP/1.1 200 OK
Server: Werkzeug/3.1.5 Python/3.9.25
Date: Sat, 10 Jan 2026 04:32:31 GMT
Content-Type: application/json
Content-Length: 19
Connection: close

{"status":"ALIVE"}
```
- verify the https readiness
- `/Users/lex/git/knowledge/k8s/scripts/pod_measure_startup_fixed.sh -n python-demo python-health-demo-v2025-11-24-6b4676f9d9-42wnj `

```bash
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
测量 Pod 启动时间: python-health-demo-v2025-11-24-6b4676f9d9-42wnj (命名空间: python-demo)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 步骤 1: 获取 Pod 基本信息
   Pod 创建时间: 2026-01-10T04:14:17Z
   容器启动时间: 2026-01-10T04:14:18Z

📋 步骤 2: 分析就绪探针配置
   就绪探针配置:
{
  "failureThreshold": 3,
  "httpGet": {
    "path": "/api-name-spring-samples/v2025.11.24/well-known/readiness",
    "port": 8443,
    "scheme": "HTTPS"
  },
  "initialDelaySeconds": 5,
  "periodSeconds": 5,
  "successThreshold": 1,
  "timeoutSeconds": 1
}

   提取的探针参数:
   - Scheme: HTTPS
   - Port: 8443
   - Path: /api-name-spring-samples/v2025.11.24/well-known/readiness
   - Initial Delay: 5s
   - Period: 5s
   - Failure Threshold: 3

⏱️  步骤 3: 检查 Pod Ready 状态
   Pod 已处于 Ready 状态
   Ready 时间: 2026-01-10T04:14:27Z

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 最终结果 (Result)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 应用程序启动耗时: 9 秒
   (基于 Kubernetes Ready 状态)

📋 当前探针配置分析:
   - 当前配置允许的最大启动时间: 20 秒
   - 实际启动时间: 9 秒
   ✓ 当前配置足够

💡 建议的优化配置:
   readinessProbe:
     httpGet:
       path: /api-name-spring-samples/v2025.11.24/well-known/readiness
       port: 8443
       scheme: HTTPS
     initialDelaySeconds: 0
     periodSeconds: 5
     failureThreshold: 3

📋 或者使用 startupProbe (推荐):
   startupProbe:
     httpGet:
       path: /api-name-spring-samples/v2025.11.24/well-known/readiness
       port: 8443
       scheme: HTTPS
     initialDelaySeconds: 0
     periodSeconds: 10
     failureThreshold: 3
   readinessProbe:
     httpGet:
       path: /api-name-spring-samples/v2025.11.24/well-known/readiness
       port: 8443
       scheme: HTTPS
     initialDelaySeconds: 0
     periodSeconds: 5
     failureThreshold: 3
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
- verify 
- `/Users/lex/git/knowledge/k8s/custom-liveness/explore-startprobe/get-deploy-health-url.sh -n python-demo python-health-demo-v2025-11-24`

```bash
Probe Type: readinessProbe
Scheme: HTTPS
Port: 8443
Path: /api-name-spring-samples/v2025.11.24/well-known/readiness

Health Check URL:
https://localhost:8443/api-name-spring-samples/v2025.11.24/well-known/readiness

➜  explore-startprobe git:(main) ✗ ./get-deploy-health-url.sh -n python-demo -o openssl python-health-demo-v2025-11-24
# OpenSSL Command:
printf "GET /api-name-spring-samples/v2025.11.24/well-known/readiness HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | openssl s_client -connect localhost:8443 -quiet 2>/dev/null

# With status code extraction:
RESPONSE=$(printf "GET PATH HTTP/1.1\r\nHost: HOST\r\nConnection: close\r\n\r\n" | openssl s_client -connect HOST:PORT -quiet 2>/dev/null)
CODE=$(echo "$RESPONSE" | grep "HTTP/" | awk '{print $2}')
echo "HTTP Status Code: $CODE"

# Actual command:
RESPONSE=$(printf "GET /api-name-spring-samples/v2025.11.24/well-known/readiness HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | openssl s_client -connect localhost:8443 -quiet 2>/dev/null)
CODE=$(echo "$RESPONSE" | grep "HTTP/" | awk '{print $2}')
echo "HTTP Status Code: $CODE"
```
- verify 
```bash
➜  k8s git:(main) ✗ k exec -it python-health-demo-v2025-11-25-65d5fd5895-t6gt8 -n python-demo -- /bin/bash
root@python-health-demo-v2025-11-25-65d5fd5895-t6gt8:/app# printf "GET /api-name-spring-samples/v2025.11.24/well-known/readiness HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | openssl s_client -connect localhost:8443 -quiet 2>/dev/null
HTTP/1.1 404 NOT FOUND
Server: Werkzeug/3.1.5 Python/3.9.25
Date: Sat, 10 Jan 2026 04:47:41 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 207
Connection: close

<!doctype html>
<html lang=en>
<title>404 Not Found</title>
<h1>Not Found</h1>
<p>The requested URL was not found on the server. If you entered the URL manually please check your spelling and try again.</p>
root@python-health-demo-v2025-11-25-65d5fd5895-t6gt8:/app# printf "GET /api-name-spring-samples/v2025.11.25/well-known/readiness HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | openssl s_client -connect localhost:8443 -quiet 2>/dev/null
HTTP/1.1 200 OK
Server: Werkzeug/3.1.5 Python/3.9.25
Date: Sat, 10 Jan 2026 04:47:56 GMT
Content-Type: application/json
Content-Length: 19
Connection: close

{"status":"READY"}
root@python-health-demo-v2025-11-25-65d5fd5895-t6gt8:/app# 
```


- descirbe pod `k describe pod python-health-demo-v2025-11-25-65d5fd5895-t6gt8 -n python-demo`
```bash

    Liveness:       http-get https://:8443/api-name-spring-samples/v2025.11.25/well-known/liveness delay=10s timeout=1s period=10s #success=1 #failure=3
    Readiness:      http-get https://:8443/api-name-spring-samples/v2025.11.25/well-known/readiness delay=5s timeout=1s period=5s #success=1 #failure=3
    Startup:        http-get https://:8443/api-name-spring-samples/v2025.11.25/well-known/startup delay=0s timeout=1s period=2s #success=1 #failure=10

 Normal   Pulled     28m                kubelet            Container image "aibangjuxin/python:python-health-demo" already present on machine
  Normal   Created    28m                kubelet            Created container python-health-demo
  Normal   Started    28m                kubelet            Started container python-health-demo
  Warning  Unhealthy  28m (x3 over 28m)  kubelet            Startup probe failed: HTTP probe failed with statuscode: 50

verify this unhealthy

printf "GET /api-name-spring-samples/v2025.11.25/well-known/startup HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | openssl s_client -connect localhost:8443 -quiet 2>/dev/null

root@python-health-demo-v2025-11-25-65d5fd5895-t6gt8:/app# printf "GET /api-name-spring-samples/v2025.11.25/well-known/startup HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | openssl s_client -connect localhost:8443 -quiet 2>/dev/null
HTTP/1.1 200 OK
Server: Werkzeug/3.1.5 Python/3.9.25
Date: Sat, 10 Jan 2026 04:53:33 GMT
Content-Type: application/json
Content-Length: 21
Connection: close

{"status":"STARTED"}

```

- using network-multitool to verify 
- [network-multitool.yaml](./k8s/network-multitool.yaml)

```bash
kubectl exec -it network-multitool-5595c68fbf-wbctl -n python-demo -- /bin/bash

bash-5.1# unset HTTPS_PROXY
bash-5.1# unset HTTP_PROXY
bash-5.1# curl -v https://10.42.0.163:8443/api-name-spring-samples/v2025.11.24/well-known/readiness
*   Trying 10.42.0.163:8443...
* Connected to 10.42.0.163 (10.42.0.163) port 8443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: none
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (OUT), TLS alert, unknown CA (560):
* SSL certificate problem: self signed certificate
* Closing connection 0
curl: (60) SSL certificate problem: self signed certificate
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
bash-5.1# curl -kv https://10.42.0.163:8443/api-name-spring-samples/v2025.11.24/well-known/readiness
*   Trying 10.42.0.163:8443...
* Connected to 10.42.0.163 (10.42.0.163) port 8443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* successfully set certificate verify locations:
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: none
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN, server did not agree to a protocol
* Server certificate:
*  subject: CN=localhost; O=Demo; C=US
*  start date: Jan 10 02:24:52 2026 GMT
*  expire date: Jan 10 02:24:52 2027 GMT
*  issuer: CN=localhost; O=Demo; C=US
*  SSL certificate verify result: self signed certificate (18), continuing anyway.
> GET /api-name-spring-samples/v2025.11.24/well-known/readiness HTTP/1.1
> Host: 10.42.0.163:8443
> User-Agent: curl/7.79.1
> Accept: */*
> 
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* old SSL session ID is stale, removing
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< Server: Werkzeug/3.1.5 Python/3.9.25
< Date: Sat, 10 Jan 2026 05:05:25 GMT
< Content-Type: application/json
< Content-Length: 19
< Connection: close
< 
{"status":"READY"}
* Closing connection 0
* TLSv1.3 (OUT), TLS alert, close notify (256):
bash-5.1# 



```

# About key 
```bash
  核心逻辑：锁与钥匙

   1. 构建镜像时 (Build Time)：
       * 您的 Dockerfile 中有一行 COPY . .。
       * 这会将您本地目录下的 key.pem（私钥）和 cert.pem（公钥）复制到镜像里。
       * 这个 key.pem 是被加密（上锁）的。
       * 关键点：构建镜像时，Docker 并不关心密码是什么，它只是把“上了锁的文件”搬运进去而已。


   2. 生成证书时 (Pre-Build)：
       * 您运行了 ./generate_certs.sh。
       * 如果您当时没有设置 HTTPS_CERT_PWD 环境变量，脚本默认使用密码 `changeit` 给 key.pem 上锁。

   3. 运行容器时 (Runtime)：
       * Kubernetes 启动 Pod。
       * Pod 读取 secret.yaml 中的 https-cert-pwd。
       * Pod 将这个密码注入环境变量 HTTPS_CERT_PWD。
       * Python 程序 (app.py) 启动，读取这个环境变量作为“钥匙”，尝试去打开镜像里的 key.pem。

  结论

  情况 A：您使用默认设置（最可能的情况）
  如果您在运行 ./generate_certs.sh 时没有通过 export 修改过密码，那么您的私钥密码就是 changeit。
   * 我的 secret.yaml 默认配置也是 changeit。
   * 结果：钥匙匹配，完全正常。

  情况 B：您自定义了密码
  如果您运行脚本时用了 export HTTPS_CERT_PWD="my-super-secret" ./generate_certs.sh：
   * 镜像里的锁是 my-super-secret。
   * 如果 secret.yaml 里还是 changeit。
   * 结果：Pod 启动时会报错（Python ssl 模块解密失败），导致 CrashLoopBackOff。
   * 补救：修改 secret.yaml 里的密码为您自定义的密码，然后 kubectl apply -f ... 即可。

  建议

  您现在可以直接部署。如果 Pod 能够正常变为 Running 状态且没有重启，说明密码是匹配的。

  如果发现 Pod 报错 bad decrypt 或类似 SSL 错误，您只需要：
   1. 修改 python-health-demo/k8s/secret.yaml 中的 https-cert-pwd。
   2. 重新应用 Secret：kubectl apply -f python-health-demo/k8s/secret.yaml。
   3. 重启 Deployment：kubectl rollout restart deployment python-health-demo-v2025-11-24。

  不需要重新构建 Docker 镜像。
```
## re-generate the key and cert
```bash
   1. 生成证书（在 python-health-demo 目录下）：

   1     # 如果你想自定义密码，先 export，否则直接运行使用默认密码 "changeit"
   2     ./generate_certs.sh

   2. 确认文件已存在：
   1     ls -l *.pem
   2     # 应该看到 cert.pem 和 key.pem

   3. 重新构建镜像：

   1     docker build -t python-health-demo:latest .
```


# About images 
- 我最终的解决办法是将我的 image构建好之后推送到公共Docker hub `docker pull aibangjuxin/python:python-health-demo`
- 然后修改deploy 从外部拉取。非常重要的一点是在个这个过程中 ，我修改了我的 K3S的。代理配置。 


```bash
docker run -d \
  --name qnap-k3s-proxy \
  --hostname qnap-k3s-Q21CA01210 \
  --mac-address 02:42:0a:00:03:08 \
  --privileged \
  --restart always \
  --network bridge \
  -p 6443:6443 \
  -p 61000-62000:61000-62000 \
  -e HTTP_PROXY="http://192.168.31.198:7222" \
  -e HTTPS_PROXY="http://192.168.31.198:7222" \
  -e NO_PROXY="localhost,127.0.0.1,10.0.0.0/8" \
  -v /share/CACHEDEV1_DATA/.qpkg/container-station/var/lib/k3s/var/lib/kubelet:/var/lib/kubelet \
  -v /share/CACHEDEV1_DATA/.qpkg/container-station/var/lib/k3s/var/lib/rancher/k3s:/var/lib/rancher/k3s \
  -v /share/CACHEDEV1_DATA/.qpkg/container-station/var/log/container-station/k3s:/var/log \
  -v /share/CACHEDEV1_DATA/.qpkg/container-station/etc/k3s:/etc/k3s \
  -v /share/CACHEDEV1_DATA/.qpkg/container-station/var/lib/k3s/etc/rancher:/etc/rancher \
  -v /share/CACHEDEV1_DATA/.qpkg/container-station/var/lib/k3s/var/lib/cni:/var/lib/cni \
  rancher/k3s:v1.21.1-k3s1 \
  server --config /etc/rancher/config.yaml
```

```bash
✦ 在 NAS 上使用 K3S 部署本地镜像（通过 Docker 构建）时，YAML 配置中有两个关键点需要设置，以确保 K8s 不会尝试从远程仓库（如 Docker
  Hub）拉取镜像，而是直接使用你本地构建的镜像。

  1. YAML 镜像配置建议

  在你的 deployment-v2025-11-24.yaml 和 deployment-v2025-11-25.yaml 中，请确保 containers 部分如下设置：

   1 spec:
   2   containers:
   3   - name: python-health-demo
   4     image: python-health-demo:latest  # 镜像名称保持与 docker images 看到的一致
   5     imagePullPolicy: Never            # 【关键】强制 K8s 只使用本地镜像，绝不尝试从远程拉取
   6     # 或者使用 IfNotPresent，但对于 :latest 标签，K8s 默认会尝试 Always，所以 Never 最稳妥
   7     ports:
   8     - containerPort: 8443
   9 ...

  2. 为什么需要这样设置？

   * 默认行为：在 K8s 中，如果镜像标签是 :latest，默认的 imagePullPolicy 是 Always。这意味着即使本地有镜像，K3S 也会尝试去公共仓库找
     python-health-demo，显然会因为找不到而报错 ImagePullBackOff。
   * 本地优先：设置为 Never 或 IfNotPresent 可以跳过远程检查。

  ---

  3. 【重要】K3S 的特殊性：镜像导入

  由于 K3S 默认使用 `containerd` 作为容器运行时，而你是在 Docker 中构建的镜像，它们两者的镜像存储空间是隔离的。即使 docker images 能看到，K3S
  可能还是看不见。

  如果部署后发现 ErrImageNeverPull 错误，你需要在 NAS 的终端执行以下命令，将镜像从 Docker 导出并导入到 K3S 的 containerd 空间中：

   1 # 将 Docker 镜像保存并直接导入到 K3S 内部存储中
   2 docker save python-health-demo:latest | k3s ctr images import -

  或者，如果你使用的是较新版本的 K3S/K3D，也可以使用：
   1 # 如果你的命令里有这个工具
   2 k3s ctr i import <(docker save python-health-demo:latest)

  总结
   1. YAML 调整：将 imagePullPolicy 设置为 Never。
   2. 同步镜像：执行 docker save ... | k3s ctr images import - 确保 K3S 的 runtime 能识别到这个镜像。
```