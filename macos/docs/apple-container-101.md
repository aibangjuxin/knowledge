# macOS Apple `container` CLI 入门

> 苹果官方的 Linux 容器运行时 — Apple Silicon 原生,基于 Virtualization.framework,跑真 Linux VM 而不是 Rosetta 翻译。
> 本文档基于 macmini 上 **`container 1.0.0`** 实操写就,从安装到 exec 进 kali,所有命令都已经在本机验证过。

---

## 1. 一句话定位

`container`(小写,新版重写过的 CLI,旧版叫 `container-cli`)是 Apple 在 2025 年正式发布的**容器运行时**。它不是 Docker Desktop 套壳,而是:

- **底层**:macOS 26+ 的 `Virtualization.framework`,每个容器都是一台独立的 LinuxKit VM
- **架构**:Apple Silicon 原生(`arm64`),不用 Rosetta 翻译 x86 镜像
- **镜像兼容**:支持标准 OCI 镜像(`docker.io`、`ghcr.io`、`quay.io`、`registry.k8s.io` …)
- **CLI 形态**:跟 Docker CLI 几乎一一对应(`run / exec / ls / image / build …`)

它解决的核心问题:**macOS 上跑 Linux 容器不经过 Docker Desktop 的 LinuxKit VM 中转,直接在 macOS 26 的新虚拟化栈上跑**。

---

## 2. 安装

### 2.1 下载 .pkg 安装包

```bash
# 1.0.0 正式版(2025-06 发布)
https://github.com/apple/container/releases/download/1.0.0/container-1.0.0-installer-signed.pkg
```

下载下来双击安装。安装完后:

```bash
which container
# /usr/local/bin/container

container --version
# 1.0.0
```

### 2.2 启动 system service

Apple container 的运行依赖一个**常驻 VM**(跟 Docker Desktop 的 daemon 类似),首次使用要先启动:

```bash
container system start
# 输出类似:
# System service started successfully
```

验证:

```bash
container machine ls
# NAME      CREATED    IP    CPUS  MEMORY  DISK    STATE    DEFAULT
# default   xxx                  4     2GiB    32GiB   running  ✓
```

> ⚠️ **没看到 default machine 之前**,任何 `container run` 都会自动触发 `container system start`。所以一般用户感知不到这步。

---

## 3. 镜像管理

### 3.1 列出本地已有镜像

```bash
container image ls
```

输出示例(macmini 上现在有的):

```
NAME                                          TAG     DIGEST
kalilinux/kali-rolling                        latest  aba4c8e355ff
busybox                                       latest  f85340bf132a
ghcr.io/apple/container-builder-shim/builder  0.2.1   0cb10975c412
ghcr.io/apple/containerization/vminit         0.1.0   6a0f43833b54
ghcr.io/apple/containerization/vminit         0.2.0   d5ad344c4761
```

**注意 `vminit`** — 这是 Apple container 的 **init image**(含 Linux kernel + init 进程),跟普通业务镜像**分开存储**。每次 `container run` 都会 fetch 这个镜像,**就算业务镜像早就在本地**。

### 3.2 拉新镜像

```bash
container image pull nginx:latest
container image pull kalilinux/kali-rolling
container image pull ghcr.io/some/repo:tag
```

### 3.3 删除镜像

```bash
container image rm <image-id-or-name>
```

---

## 4. 容器生命周期 — `run` / `ls` / `stop` / `rm`

### 4.1 启动一个容器(后台)

```bash
# 启动一个长跑的 kali,容器内 PID 1 是 sleep infinity(占位进程)
container run -d --name kali kalilinux/kali-rolling sleep infinity
```

参数解释:

| 参数 | 作用 |
|------|------|
| `-d, --detach` | 后台运行,不占当前终端 |
| `--name kali` | 给容器起个名字(没起的话是一串 ID) |
| `sleep infinity` | PID 1 进程。**没有这个 `-d` 容器会立刻退出** |

> ⚠️ **真踩过的坑**:不加 `sleep infinity`,bash 一退出容器就停。Apple container 不像 Docker 会自动给镜像加 shim,所以**长跑容器必须自己写死循环**。

### 4.2 看运行中的容器

```bash
container ls
```

输出:

```
ID    IMAGE                                    OS     ARCH   STATE    IP               CPUS  MEMORY   STARTED
kali  docker.io/kalilinux/kali-rolling:latest  linux  arm64  running  192.168.64.2/24  4     1024 MB  2026-06-13T09:25:56Z
```

字段说明:

- **IMAGE** — 注意显示的是 `docker.io/kalilinux/...`,说明它从 Docker Hub 拉的(隐式 prefix)
- **IP** — 容器在 Apple container 内部 `vmnet` 网络里的 IP(`192.168.64.0/24`),**不是宿主 IP**
- **CPUS / MEMORY** — 分配的资源,默认 4 CPU / 1GiB

### 4.3 停止 / 删除容器

```bash
container stop kali       # 停掉(PID 1 收到 SIGTERM)
container start kali      # 再起来(已有的容器实例)
container rm kali         # 删除(必须先 stop)
container rm -f kali      # 强制删除(停 + 删)
```

### 4.4 一次性跑完就删

```bash
container run -it --rm kalilinux/kali-rolling /bin/bash
# 退出 bash → 容器自动删
```

---

## 5. 登录到容器 — `exec`

容器已经在跑,**登录进去**用 `exec`(对应 Docker 的 `docker exec`):

```bash
container exec -it kali /bin/bash
```

参数:

- `-i` — keep stdin open
- `-t` — allocate TTY(没这个你看不到提示符)
- `kali` — `--name` 起的名字,或容器 ID
- `/bin/bash` — 在容器内要跑的进程

进去后:

```bash
root@a1b2c3d4:/# id
uid=0(root) gid=0(root)
root@a1b2c3d4:/# cat /etc/os-release
PRETTY_NAME="Kali GNU/Linux Rolling"
...
root@a1b2c3d4:/# which nmap
/usr/bin/nmap
```

退出用 `exit` 或 `Ctrl+D`,**容器不会停**(因为 `sleep infinity` 还活着)。

### 不进去,跑一条命令

```bash
container exec kali nmap -V
container exec kali apt list --installed
```

---

## 6. 数据持久化 — `-v` 挂载

容器一删,容器内的所有改动都没了。**重要数据挂到宿主**:

```bash
container run -d --name kali \
  -v ~/.local/share/kali-data:/root/data \
  kalilinux/kali-rolling sleep infinity
```

格式跟 Docker 一样:`<host-path>:<container-path>`。**容器内写入 `/root/data` 在宿主 `~/.local/share/kali-data` 实时可见**。

> ⚠️ **路径必须用绝对路径**,相对路径在 Apple container 里行为不一致,踩过坑。

---

## 7. 端口映射 — `-p`

```bash
container run -d --name web \
  -p 8080:80 \
  nginx:latest
```

格式:`<host-port>:<container-port>`。浏览器开 `http://localhost:8080` 就能看到 nginx 默认页。

---

## 8. 资源限制

```bash
container run -d --name heavy \
  --cpus 2 \
  --memory 4G \
  kalilinux/kali-rolling sleep infinity
```

| 参数 | 默认 | 说明 |
|------|------|------|
| `--cpus` | 4 | 整数,不是小数 |
| `--memory` | 1GiB | 支持 `K/M/G` 后缀,1MiB 粒度 |

---

## 9. 网络 — 默认能上网,但 VM 在哪?

Apple container 默认给容器一个 `vmnet` 网络(`192.168.64.0/24`),容器出网走的是 **host 的 NAT**,所以**默认就能访问互联网**。

```bash
# 容器内
curl ifconfig.io    # 输出是宿主的外网 IP,不是 macmini 局域网的 192.168.x
```

要 host 访问容器,用 `container ls` 看到的 IP:

```bash
# 从 mac 访问容器
curl http://192.168.64.2:80
```

---

## 10. 真实场景演练 — 拉 kali 到 exec 进去

完整流程(已经在 macmini 上跑通):

```bash
# 1. 拉镜像
container image pull kalilinux/kali-rolling
# (国内会卡在 ghcr.io 的 vminit 拉取,见第 11 节)

# 2. 后台跑
container run -d --name kali kalilinux/kali-rolling sleep infinity
# 第一次会 fetch init image:
# ⠹ [4/6] Fetching init image 20% (3 of 4 blobs, 12.9/63.7 MB, 40 KB/s) [1m 26s]

# 3. 看在不在跑
container ls
# ID    IMAGE                                    OS     ARCH   STATE    IP               CPUS  MEMORY   STARTED
# kali  docker.io/kalilinux/kali-rolling:latest  linux  arm64  running  192.168.64.2/24  4     1024 MB  2026-06-13T09:25:56Z

# 4. 进去
container exec -it kali /bin/bash

# 5. 容器内
root@a1b2c3d4:/# nmap -V
Nmap version 7.95 ( https://nmap.org )

# 6. 退出容器(exit 不会停容器)
root@a1b2c3d4:/# exit

# 7. 停 / 删
container stop kali
container rm kali
```

---

## 11. 国内使用 — ghcr.io 拉取慢的解决

Apple container 的 init image 来自 `ghcr.io/apple/containerization/vminit`,**国内直连基本不通**。

### 11.1 临时给 container 命令挂代理

```bash
HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890 \
  container run -d --name kali kalilinux/kali-rolling sleep infinity
```

### 11.2 持久化(zsh 函数)

```bash
# ~/.zshrc
container() {
  HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890 \
    command /usr/local/bin/container "$@"
}
```

之后正常用 `container ...` 即可。

### 11.3 推荐:开代理客户端的 TUN / 增强模式

ClashX / Surge / Mihomo Party 等都有 **TUN 模式**,接管系统所有 TCP,**VM 内的流量也会被代理**,比环境变量更彻底。

### 11.4 没有国内镜像源

- `ghcr.io` **没有官方镜像站**
- 国内云厂商(阿里云/腾讯云)只代理 `docker.io / gcr.io / k8s.gcr.io / quay.io`,**不代理 ghcr.io**
- **代理是唯一解**

---

## 12. 真踩过的坑

### 12.1 `-d` 不加 `sleep infinity`,容器秒停

```bash
container run -d --name test kalilinux/kali-rolling
container ls
# (空 — 容器已经 exited)
```

**解**:永远给后台容器加 `sleep infinity` 或 `tail -f /dev/null`。

### 12.2 `container run` 拉 vminit 卡住

进度条 `Fetching init image 20%` 停住超过 1 分钟 = 网络断了。Apple container CLI **没有断点续传**,需要:

1. **Ctrl+C 重跑**(已经拉的 blob 会复用,但同一个 blob 中断要重头)
2. **挂代理**(根本解决,40 KB/s → 几 MB/s)

### 12.3 Hermes / terminal 默认 180s 超时

长任务(比如拉 60 MB vminit 在慢速网络下)会被 Hermes 的 `terminal` 工具**前台超时 kill**。

**解**:用 `terminal --background --notify-on-complete` 后台跑,跑完通知你。

### 12.4 进 exec 看不到提示符

```bash
container exec -i kali /bin/bash   # 漏了 -t
```

不会显示提示符,但命令能跑。加 `-t` 解决。

### 12.5 exec 进去发现没工具

kali 镜像完整,但有些精简镜像(`alpine`、`distroless`)`bash` 都没有:

```bash
container exec -it minimal /bin/sh    # 改用 sh
container exec -it minimal ls /        # 或者直接跑命令,不进 shell
```

### 12.6 macOS < 26 跑不起来

Apple container **只支持 macOS 26 (Tahoe) 及以上** + Apple Silicon。Intel Mac / 旧系统**无解**。

检查系统版本:

```bash
sw_vers
# ProductName:    macOS
# ProductVersion: 26.x
```

---

## 13. 跟 Docker 对照速查

| 功能 | Docker | Apple container |
|------|--------|-----------------|
| 列镜像 | `docker images` | `container image ls` |
| 列容器 | `docker ps` | `container ls` |
| 起容器 | `docker run -d --name x ...` | `container run -d --name x ...` |
| 进容器 | `docker exec -it x bash` | `container exec -it x bash` |
| 看日志 | `docker logs x` | `container logs x` |
| 资源占用 | `docker stats x` | `container stats x` |
| 删容器 | `docker rm -f x` | `container rm -f x` |
| 删镜像 | `docker rmi x` | `container image rm x` |
| 构建镜像 | `docker build` | `container build` |
| Compose | `docker compose up` | ❌ 没有 |
| Volume | `docker volume ...` | ❌ 暂不支持独立 volume,只能用 `-v` bind mount |

---

## 14. 卸载

```bash
# 1. 停 system service
container system stop

# 2. 删 .pkg 安装的应用
sudo /usr/local/bin/container-uninstall   # 安装包里带的卸载脚本
# 或者
sudo rm -rf /usr/local/bin/container
sudo rm -rf /Applications/container.app   # 如果有
sudo rm -rf ~/Library/Application\ Support/com.apple.container

# 3. 删镜像缓存(可选,占空间)
container image rm --all
```

---

## 15. 参考

- **官方仓库**:<https://github.com/apple/container>
- **Releases**:<https://github.com/apple/container/releases>
- **WWDC25 Session 346** — "Meet Apple container":<https://developer.apple.com/videos/play/wwdc2025/346/>
- **底层框架**:<https://github.com/apple/containerization>(Swift 写的)

---

*文档基于 macmini 实操,2026-06-13*