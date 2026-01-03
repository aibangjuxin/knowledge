# hey: GKE 环境下的 HTTP 负载测试工具

`hey` 是一个非常流行、轻量级的 HTTP 负载测试工具，是用 Go 语言编写的。可以把它看作是现代版的 Apache Bench (ab)，但它的输出更直观，参数也更人性化。

针对你在 GKE 环境下的需求，以下是关于 `hey` 的详细资料、镜像来源以及实用的操作文档。

## 1. 镜像来源与获取

虽然 `hey` 是开源软件，但官方作者并没有维护一个“官方”Docker 镜像。社区中最常用、最稳定的是由 `williamyeh` 构建的版本。

*   **镜像名称**: `williamyeh/hey`
*   **Docker Hub 地址**: https://hub.docker.com/r/williamyeh/hey
*   **特点**: 极小（基于 Alpine Linux，仅几 MB），非常适合在 Kubernetes 中作为临时 Pod 快速拉起。

## 2. 核心参数速查表 (Cheat Sheet)

在使用 `kubectl run` 启动它之前，你需要了解以下几个核心参数，这对评估资源消耗至关重要：

| 参数 | 全称 | 作用 | 适用场景 |
|---|---|---|---|
| `-z` | Duration | 压测时长 (如 5m, 30s)。 | 推荐。用于观察内存/CPU在一段时间内的稳定性。 |
| `-n` | Number | 请求总数 (如 10000)。 | 用于测试完成特定数量请求后的最终资源状态。 |
| `-c` | Concurrency | 并发连接数。默认为 50。 | 模拟多少个用户同时在用。测试 AppD 时建议设为 10-50。 |
| `-q` | QPS Limit | 每秒请求速率限制 (Rate Limit)。 | 防止把服务打挂，保持平稳的流量输入。 |
| `-m` | Method | HTTP 方法 (GET, POST, PUT 等)。 | 默认是 GET。测 API 通常要改 POST。 |
| `-d` | Data | HTTP Body 数据。 | 发送 JSON 等内容。 |
| `-H` | Header | 自定义 Header。 | 比如 Content-Type: application/json。 |
| `-t` | Timeout | 超时时间。 | 默认为 20秒。 |

> **注意**： `-z` (按时间跑) 和 `-n` (按次数跑) 通常二选一。

## 3. 在 Kubernetes (GKE) 中的实战用法

你可以直接复制以下命令在你的 GKE 终端运行。

### 场景 A：简单的 GET 请求（保持 2 分钟压力）

这是最基础的用法，用于让 CPU 和内存动起来。

```bash
kubectl run hey-test --rm -i --tty \
  --image=williamyeh/hey \
  --restart=Never \
  -- \
  -z 2m \
  -c 20 \
  http://<你的ServiceIP>:<端口>/<API路径>
```

### 场景 B：发送 POST 请求 (带 JSON 数据)

如果你的 API 是业务接口，通常需要 POST 数据。这更能触发 Java 应用的实际业务逻辑，从而让 AppD 采集到更有意义的 Transaction 数据。

```bash
# 假设你的 API 需要这样的 JSON: {"userId": "123", "action": "login"}
kubectl run hey-post-test --rm -i --tty \
  --image=williamyeh/hey \
  --restart=Never \
  -- \
  -m POST \
  -H "Content-Type: application/json" \
  -d '{"userId": "123", "action": "login"}' \
  -z 2m \
  -c 10 \
  http://<你的ServiceIP>:<端口>/api/login
```

## 4. 结果解读

当 `hey` 运行结束后，它会输出一份摘要。除了关注 GKE 的资源监控外，你也可以看看这份报告，它能侧面反映 AppD 对性能的影响。

### 输出示例解读：

```
Summary:
  Total:	2.0005 secs
  Slowest:	0.1569 secs
  Fastest:	0.0054 secs
  Average:	0.0193 secs   <-- 关注这个：平均响应时间
  Requests/sec:	2498.34   <-- 关注这个：吞吐量 (RPS)

Response time histogram:  <-- 响应时间分布图
  0.005 [1]	|
  0.021 [4832]	|■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.036 [152]	|■
  ...
```

*   **比较点**： 如果带 AppD 的 Pod 平均响应时间是 20ms，而不带 AppD 的是 18ms，说明 AppD 的性能损耗极小，可以忽略不计。

## 5. 官方文档与源码

如果你想深入了解所有参数，可以访问 GitHub 仓库：

*   **GitHub 源码库**: https://github.com/rakyll/hey
    (注：原作者 `rakyll` 是 Google 的工程师，这个工具非常可靠)

### Next Step

考虑到你的 API 可能需要认证 (Authentication) 才能访问（比如 Header 里需要带 Token），直接跑上面的命令可能会返回 `401 Unauthorized`。

你需要我告诉你如何通过 `hey` 发送带有 Bearer Token 或 Cookie 的请求吗？

---

是的，完全可以，而且这是企业级环境中最标准的操作流程。这通常被称为“镜像搬运”或“镜像同步”。

因为你的 GKE 环境处于内网或受限环境（无法直接访问 Docker Hub），你需要把你本地电脑当作一个中转站。

以下是详细的操作步骤，教你如何把 `hey` 的镜像从 Docker Hub 搬运到你们公司的 Google Artifact Registry (GAR)。

## 准备工作

在你的本地电脑上，你需要确保：

*   Docker Desktop 已经安装并运行。
*   `gcloud CLI` (Google Cloud SDK) 已经安装，并且你已经登录了对应的 GCP 项目 (`gcloud auth login`)。
*   确认你有向 GAR 推送镜像的权限（通常是 `Artifact Registry Writer` 角色）。

## 操作步骤：四步走

假设你的 GCP 信息如下（请在执行时替换为你自己的真实信息）：

*   **GCP 区域 (Region)**: `asia-northeast1` (比如东京)
*   **项目 ID (Project ID)**: `my-company-project`
*   **GAR 仓库名 (Repo Name)**: `my-tools` (需要先在 GAR 里创建这个 Docker 仓库)

### 第一步：在本地拉取镜像

为了保证兼容性（防止你的电脑是 Mac M1/M2 而服务器是 Linux x86），建议强制指定平台拉取：

```bash
# 拉取 linux/amd64 架构的镜像，确保在 GKE 服务器上能跑
docker pull --platform linux/amd64 williamyeh/hey
```

### 第二步：配置 Docker 认证

你需要让本地的 Docker 知道如何跟 Google 的仓库对话。运行以下命令（每个 Region 只需要运行一次）：

```bash
# 这里的 asia-northeast1 需要换成你 GAR 所在的区域
gcloud auth configure-docker asia-northeast1-docker.pkg.dev
```

### 第三步：重新打标签 (Retag)

你需要把镜像的名字从“Docker Hub 格式”改成“GCP GAR 格式”。

*   **源镜像**: `williamyeh/hey`
*   **目标格式**: `[区域]-docker.pkg.dev/[项目ID]/[仓库名]/[镜像名]:[版本]`

```bash
# 请替换下面的变量
docker tag williamyeh/hey:latest asia-northeast1-docker.pkg.dev/my-company-project/my-tools/hey:latest
```

### 第四步：推送到 GAR (Push)

将打好标签的镜像上传到你们公司的私有仓库。

```bash
docker push asia-northeast1-docker.pkg.dev/my-company-project/my-tools/hey:latest
```

## 如何在 GKE 中使用新镜像？

一旦上传成功，你在 GKE 里的 `kubectl run` 命令就可以使用内网地址了，这样就不会被公司的防火墙拦截。

### 新的压测命令：

```bash
# 注意 --image 参数的变化
kubectl run hey-test --rm -i --tty \
  --image=asia-northeast1-docker.pkg.dev/my-company-project/my-tools/hey:latest \
  --restart=Never \
  -- \
  -z 2m \
  -c 10 \
  http://<你的应用IP>:8080/api/test
```

### 💡 两个重要的提示

*   **关于镜像架构 (Architecture)**：
    如果你的本地电脑是 Apple Silicon (M1/M2/M3) 芯片，务必在第一步使用 `--platform linux/amd64`。否则你默认拉下来的是 ARM 架构镜像，推送到 GKE（通常是 x86/amd 64 架构）上运行时会报错 `Exec format error`。
*   **GAR 仓库必须存在**：
    如果你的 GCP 项目里还没有用来放工具的 Docker 仓库，你需要先创建一个。
    *   可以在 GCP Console 界面创建。
    *   或者用命令行：
        ```bash
        gcloud artifacts repositories create my-tools \
          --repository-format=docker \
          --location=asia-northeast1 \
          --description="Docker repository for testing tools"
        ```

### Next Step

如果在推送过程中遇到 `permission denied` 或者 `403` 错误，通常是 `gcloud` 的认证配置问题。如果你遇到了，请告诉我，我会给你排错步骤。或者，你想知道如何确认你的 GKE 集群是否有权限拉取这个 GAR 里的镜像吗？（因为有时候 GKE 的 Service Account 也需要授权）。

---

这是一个非常棒的情况！既然你已经在 Docker Desktop 的图形界面里成功下载了镜像（或者你手里有一个镜像文件包），那么最难的一步（从外网获取资源）你已经解决了。

现在的核心任务是：把这个“本地的镜像”贴上你们公司的标签，然后上传到 GAR。

不论你是通过 Docker Desktop 的搜索栏下载的，还是导入了一个文件，流程都是通用的。请按照以下步骤操作：

## 第一步：找到并确认本地镜像

首先，我们需要在命令行里确认 Docker 已经识别到了这个镜像，并拿到它的 Image ID。

*   打开你的终端（Terminal / PowerShell / CMD）。
*   输入以下命令查看本地所有镜像：
    ```bash
    docker images
    ```

*   **寻找目标**： 在列表中找到 `williamyeh/hey`。
    *   如果你看到它，记下它的 `IMAGE ID`（通常是一串字符，如 `a1b2c3d4e5...`）。
    *   **注意**： 如果你是通过文件包（如 `.tar`）下载的，还没导入，你需要先运行 `docker load -i <你的文件名.tar>`，然后再运行 `docker images` 确认。

## 第二步：给镜像“改名”（打标签/Retag）

Docker 的逻辑是：镜像的名字决定了它要去哪里。现在它的名字是“Docker Hub 格式”，我们要把它改成“GCP GAR 格式”。

假设你的 `Image ID` 是 `a1b2c3d4e5`（请替换为你实际查到的 ID）。

```bash
# 语法：docker tag [Image ID] [目标GAR地址]

# 示例（请替换为你的真实项目信息）：
docker tag a1b2c3d4e5 asia-northeast1-docker.pkg.dev/my-company-project/my-tools/hey:latest
```

*   **解释**： 这行命令并没有复制镜像，只是给同一个镜像 ID 贴了一个新标签（Alias）。现在你再运行 `docker images`，你会发现同一个 ID 对应了两个名字。

## 第三步：推送到 GAR (Push)

现在名字改好了，可以直接推送到公司的仓库。

*   **确保认证**（如果之前没做过）：
    ```bash
    gcloud auth configure-docker asia-northeast1-docker.pkg.dev
    ```

*   **执行推送**：
    ```bash
    docker push asia-northeast1-docker.pkg.dev/my-company-project/my-tools/hey:latest
    ```

## ⚠️ 至关重要的检查：架构问题 (Architecture)

这里有一个极易踩坑的点，特别是如果你使用的是 Mac (M1/M2/M3 芯片) 的电脑。

### 风险：

Docker Desktop 图形界面下载时，默认会下载适配你本机电脑芯片的版本。

*   如果你是 Apple Silicon (M1/M2)，它会下载 `linux/arm64` 架构的镜像。
*   但是！你的 GKE 服务器大概率是 `linux/amd64` (x86) 架构的。
*   **后果**： 推送上去后，Pod 启动时会报错 `Exec format error`，无法运行。

### 如何补救？

如果你的电脑是 M1/M2 Mac，而你通过 GUI 下载了镜像：

*   **检查架构**：
    ```bash
    docker inspect a1b2c3d4e5 | grep Architecture
    ```

    如果显示 `"Architecture": "arm64"`，那么这个镜像不能直接传给 GKE 用。
*   **解决方案**：
    既然你的命令行 `docker pull` 走不通，你可以在 Docker Desktop 的搜索栏里尝试寻找是否有标记为 `amd64` 的 Tag（通常很难直观看到）。
    更稳妥的办法（利用 Docker Desktop 的特性）：
    即便 `docker pull` 可能会超时，但你可以尝试配置 Docker Desktop 的 Daemon 设置，或者使用以下“曲线救国”命令（有时候 CLI 的代理配置比 GUI 更好控制）：
    如果实在只能用 Docker Desktop GUI 下载且你是 M1/M2 电脑，你可能需要找一台 Windows (Intel/AMD CPU) 或 Intel Mac 的同事电脑，让他帮忙下载并导出给你，或者确认 GKE 节点是否支持 ARM。
    (注：如果你本身就是 Windows 电脑或者 Intel 芯片的 Mac，请忽略此警告，直接推送即可！)

### 总结流程

*   `docker images` -> 找到 `Image ID`。
*   `docker tag <Image ID> <GAR地址>` -> 改名。
*   `docker push <GAR地址>` -> 上传。

```bash
hey --help
Usage: hey [options...] <url>

Options:
  -n  Number of requests to run. Default is 200.
  -c  Number of workers to run concurrently. Total number of requests cannot
      be smaller than the concurrency level. Default is 50.
  -q  Rate limit, in queries per second (QPS) per worker. Default is no rate limit.
  -z  Duration of application to send requests. When duration is reached,
      application stops and exits. If duration is specified, n is ignored.
      Examples: -z 10s -z 3m.
  -o  Output type. If none provided, a summary is printed.
      "csv" is the only supported alternative. Dumps the response
      metrics in comma-separated values format.

  -m  HTTP method, one of GET, POST, PUT, DELETE, HEAD, OPTIONS.
  -H  Custom HTTP header. You can specify as many as needed by repeating the flag.
      For example, -H "Accept: text/html" -H "Content-Type: application/xml" .
  -t  Timeout for each request in seconds. Default is 20, use 0 for infinite.
  -A  HTTP Accept header.
  -d  HTTP request body.
  -D  HTTP request body from file. For example, /home/user/file.txt or ./file.txt.
  -T  Content-type, defaults to "text/html".
  -a  Basic authentication, username:password.
  -x  HTTP Proxy address as host:port.
  -h2 Enable HTTP/2.

  -host HTTP Host header.

  -disable-compression  Disable compression.
  -disable-keepalive    Disable keep-alive, prevents re-use of TCP
                        connections between different HTTP requests.
  -disable-redirects    Disable following of HTTP redirects
  -cpus                 Number of used cpu cores.
                        (default for current machine is 10 cores)
➜  knowledge git:(main) ✗
```
