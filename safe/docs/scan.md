# Apple Container + Kali Linux 安全扫描环境搭建指南

## 完整实现步骤梳理

### 项目目标

在 macOS 上使用 Apple Container 技术运行 Kali Linux 容器，搭建安全扫描环境

### 1. 环境准备

- **工具**：Apple Container (macOS 原生容器技术)
- **镜像**：Kali Linux Rolling (docker.io/kalilinux/kali-rolling:latest)
- **架构**：ARM64 (Apple Silicon)

### 2. 完整操作流程

#### 步骤 1：启动容器服务

```bash
container system start
```

#### 步骤 2：镜像管理

```bash
# 查看现有镜像
container images ls

# 拉取Kali Linux镜像
container images pull docker.io/kalilinux/kali-rolling:latest

# 确认镜像下载成功
container images ls
```

#### 步骤 3：创建并运行容器

```bash
# 创建后台运行的容器
container run -d --name myscan docker.io/kalilinux/kali-rolling:latest

# 启动容器
container start myscan

# 查看容器状态
container ls -a
```

#### 步骤 4：交互式访问容器

```bash
# 创建交互式容器
container run --name myscanbash -it docker.io/kalilinux/kali-rolling:latest bash
```

#### 步骤 5：配置 Kali Linux 环境

**A. 更换软件源（提升下载速度）**

```bash
echo "deb https://mirrors.aliyun.com/kali kali-rolling main non-free contrib" > /etc/apt/sources.list
echo "deb-src https://mirrors.aliyun.com/kali kali-rolling main non-free contrib" >> /etc/apt/sources.list
```

**B. 导入 GPG 密钥**

```bash
# 方式1（传统）
curl -sSL https://archive.kali.org/archive-key.asc | apt-key add -

# 方式2（推荐）
curl -sSL https://archive.kali.org/archive-key.asc | gpg --dearmor > /usr/share/keyrings/kali-archive-keyring.gpg
```

#### 步骤 6：解决 SSL 证书问题

**临时解决方案（快速但不安全）**

```bash
apt-get -o Acquire::https::Verify-Peer=false -o Acquire::https::Verify-Host=false update
apt-get -o Acquire::https::Verify-Peer=false -o Acquire::https::Verify-Host=false install nmap
```

**推荐解决方案（安全）**

```bash
apt-get update --allow-unauthenticated
apt-get install --reinstall ca-certificates
```

#### 步骤 7：后续使用

```bash
# 重新进入已存在的容器
container start myscanbash
container exec -it myscanbash bash
```

### 3. 关键特性

#### 持久化

- 容器内安装的软件包会持久保存
- 只要不删除容器，环境配置永久有效

#### 网络配置

- 容器自动分配 IP 地址（如 192.168.64.17）
- 支持网络扫描和渗透测试工具

#### 架构兼容

- 原生支持 Apple Silicon (ARM64)
- 无需虚拟化开销

### 4. 安全注意事项

#### SSL 证书处理

- **临时方案**：忽略 SSL 校验（仅测试环境）
- **推荐方案**：修复 CA 证书
- **风险提醒**：忽略 SSL 校验可能遭受中间人攻击

#### 最佳实践

- 使用官方或可信镜像源
- 定期更新容器镜像
- 在受信任网络环境下操作

### 5. 实际应用场景

- **安全扫描**：使用 nmap 等工具进行网络扫描
- **渗透测试**：完整的 Kali Linux 工具集
- **安全研究**：隔离的测试环境
- **学习实践**：安全技术学习平台

---

## 参考资源

https://github.com/apple/container

https://hub.docker.com/r/kalilinux/kali-rolling

https://github.com/apple/container/blob/main/docs/tutorial.md
1 Start the services that container uses:
container system start
2 manage images
container images ls
container images pull docker.io/kalilinux/kali-rolling:latest
3 container images ls
NAME TAG DIGEST
docker.io/kalilinux/kali-rolling latest aba4c8e355ff7fd2d7fea6bc...
docker.io/library/busybox latest f85340bf132ae937d2c2a763...
ghcr.io/apple/containerization/vminit 0.1.0 6a0f43833b546829ec3d99d1...
4 container run -d --name myscan docker.io/kalilinux/kali-rolling:latest
container run -d --name myscan docker.io/kalilinux/kali-rolling:latest
myscan

5 container start myscan
myscan

container ls -a
ID IMAGE OS ARCH STATE ADDR
myscan docker.io/kalilinux/kali-rolling:latest linux arm64 stopped  
buildkit ghcr.io/apple/container-builder-shim/builder:0.2.1 linux arm64 stopped  
7d1b3299-a112-4faf-a270-a47be06e9d74 docker.io/library/busybox:latest linux arm64 stopped

6 Login success
container run --name myscanbash -it docker.io/kalilinux/kali-rolling:latest bash
┌──(root㉿myscanbash)-[/]  
└─# How to install package
echo "deb https://mirrors.aliyun.com/kali kali-rolling main non-free contrib" > /etc/apt/sources.list
echo "deb-src https://mirrors.aliyun.com/kali kali-rolling main non-free contrib" >> /etc/apt/sources.list

7 container ls

container ls
ID IMAGE OS ARCH STATE ADDR
myscanbash docker.io/kalilinux/kali-rolling:latest linux arm64 running 192.168.64.1

8 next login
· 只要你不删除 ‎`myscanbash` 容器，里面的环境和安装的包会一直保留
container start myscanbash
container exec -it myscanbash bash

container start myscanbash
myscanbash  
container ls
ID IMAGE OS ARCH STATE ADDR
myscanbash docker.io/kalilinux/kali-rolling:latest linux arm64 running 192.168.64.17

container exec -it myscanbash bash

success
修改默认源:
echo "deb https://mirrors.aliyun.com/kali kali-rolling main non-free contrib" > /etc/apt/sources.list
echo "deb-src https://mirrors.aliyun.com/kali kali-rolling main non-free contrib" >> /etc/apt/sources.list

# 使用 curl 导入 Kali 官方 GPG 密钥（确保包验证通过）

curl -sSL https://archive.kali.org/archive-key.asc | apt-key add -

# 使用 curl 导入 Kali 官方 GPG 密钥（新方式）

    curl -sSL https://archive.kali.org/archive-key.asc | gpg --dearmor > /usr/share/keyrings/kali-archive-keyring.gpg

└─# apt-get update
Hit:1 https://mirrors.aliyun.com/kali kali-rolling InRelease
Reading package lists... Done
N: Repository 'Kali Linux' changed its 'non-free component' value from 'non-free' to 'non-free non-free-firmware'
N: More information about this can be found online at: https://www.kali.org/blog/non-free-firmware-transition/

Kali（Debian/Ubuntu）系的 apt-get 默认会校验证书，遇到 SSL 证书错误时会报错。你可以通过以下方法临时忽略 SSL 校验：

1. 临时忽略 SSL 校验 这个可以成功

在 apt-get 命令后加上 ‎⁠-o Acquire::https::Verify-Peer=false -o Acquire::https::Verify-Host=false⁠：apt-get -o Acquire::https::Verify-Peer=false -o Acquire::https::Verify-Host=false update
┌──(root㉿myscanbash)-[/bin]
└─# apt-get -o Acquire::https::Verify-Peer=false -o Acquire::https::Verify-Host=false install nmap

2. 永久配置（不推荐，降低安全性）

编辑 ‎⁠/etc/apt/apt.conf.d/99insecure⁠，添加：Acquire::https::Verify-Peer "false";
Acquire::https::Verify-Host "false";

⚠️ 注意

- 忽略 SSL 校验会降低安全性，容易被中间人攻击。仅建议在受信任的网络和临时环境下使用。
- 更推荐换用官方或可信的镜像源，或修复容器内的 CA 证书（如 apt-get install –reinstall ca-certificates）。

3. 修复 CA 证书（推荐）

有时是容器内缺少 CA 证书导致，可以先尝试：apt-get update --allow-unauthenticated
apt-get install --reinstall ca-certificates

然后再正常 update。

如需进一步帮助，请贴出完整的 apt-get update 命令和输出。
