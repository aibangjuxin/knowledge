# Kali Linux 安全工具容器

基于 [kalilinux/kali-rolling](https://hub.docker.com/r/kalilinux/kali-rolling) 构建的个人安全测试工具容器。

## 功能特性

- 🔧 预装常用安全测试工具
- 🐚 配置优化的 Zsh 环境
- ☸️ 集成 Kubernetes 工具
- 🚀 一键环境初始化脚本
- 🌐 代理配置支持

## 快速开始

### 1. 构建容器

```bash
docker build -t my-kali-tools .
```

### 2. 运行容器

```bash
# 挂载配置目录并运行
docker run -it --rm \
  -v $(pwd):/workspace \
  -v ~/.kube:/root/.kube:ro \
  --name kali-tools \
  my-kali-tools
```

### 3. 初始化环境

容器启动后执行：

```bash
/workspace/init.sh
```

## 预装工具

### 网络安全工具
- `nmap` - 网络扫描工具
- `nikto` - Web 漏洞扫描器
- `sslscan` - SSL/TLS 配置扫描
- `dnsrecon` - DNS 侦察工具
- `amass` - 子域名发现工具
- `john` - 密码破解工具

### 网络工具
- `inetutils-telnet` - Telnet 客户端
- `net-tools` - 网络配置工具

### 开发工具
- `git` - 版本控制
- `neovim` - 文本编辑器
- `zsh` + `oh-my-zsh` - 增强 Shell
- `kubectl` - Kubernetes 命令行工具
- `tree`

### 便利工具
- `autojump` - 智能目录跳转

## 配置文件

### 核心文件
- `Dockerfile` - 容器构建文件
- `init.sh` - 环境初始化脚本
- `.zshrc` - Zsh 配置文件
- `aliases.sh` - 命令别名配置
- `run-container.sh` - 容器启动脚本

### 挂载配置文件
- `mount-config-template.sh` - 挂载配置模板
- `example-custom.sh` - 自定义配置示例
- `example-.zshrc.custom` - 自定义 .zshrc 示例

## 挂载配置系统

### 概述
容器支持通过挂载目录 `/opt/share` 来加载个人配置，实现环境的持久化和个性化。

### 使用方法

#### 1. 使用启动脚本（推荐）
```bash
# 给脚本执行权限
chmod +x run-container.sh

# 启动容器（自动创建配置目录）
./run-container.sh
```

#### 2. 手动启动
```bash
# 创建宿主机配置目录
mkdir -p ./host-config

# 复制配置模板
cp mount-config-template.sh ./host-config/mount-config.sh
cp example-custom.sh ./host-config/custom.sh
cp example-.zshrc.custom ./host-config/.zshrc.custom

# 启动容器
docker run -it --rm \
  -v $(pwd):/workspace \
  -v $(pwd)/host-config:/opt/share \
  -v ~/.kube:/root/.kube:ro \
  --name kali-tools \
  my-kali-tools
```

### 配置文件说明

#### `/opt/share/mount-config.sh`
主配置文件，容器启动时自动执行：
- 代理设置
- Git 用户配置
- 环境变量设置
- 目录链接创建

#### `/opt/share/custom.sh`
个人自定义配置：
- 个人别名
- 自定义函数
- 环境变量
- 启动脚本

#### `/opt/share/.zshrc.custom`
个人 .zshrc 配置：
- 提示符自定义
- 插件配置
- 个人别名扩展

### 目录结构
```
host-config/
├── mount-config.sh      # 主配置文件
├── custom.sh           # 个人自定义配置
├── .zshrc.custom       # 个人 .zshrc 配置
├── .ssh/               # SSH 密钥（可选）
├── .kube/              # Kubernetes 配置（可选）
├── tools/              # 个人工具
├── scripts/            # 个人脚本
├── projects/           # 项目目录
├── notes/              # 笔记目录
├── wordlists/          # 字典文件
└── backups/            # 备份目录
```

## 使用说明

### 代理配置

如需使用代理，可在初始化脚本中配置：

```bash
export ALL_PROXY="socks5://192.168.31.198:7221"
```

### 快捷命令

- `j <目录>` - 使用 autojump 快速跳转目录
- `k` - kubectl 命令别名

### Kubernetes 配置

容器会自动挂载宿主机的 `~/.kube` 配置，确保 kubectl 可以正常访问集群。 

# gcloud 
```bash
Linux 
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-452.0.1-linux-x86_64.tar.gz
tar -xvf google-cloud-sdk-452.0.1-linux-x86_64.tar.gz
~/google-cloud-sdk/install.sh

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/root/google-cloud-sdk/path.zsh.inc' ]; then . '/root/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/root/google-cloud-sdk/completion.zsh.inc' ]; then . '/root/google-cloud-sdk/completion.zsh.inc'; fi


➜  ~ gcloud --version
Google Cloud SDK 452.0.1
bq 2.0.98
bundled-python3-unix 3.9.17
core 2023.10.25
gcloud-crc32c 1.0.0
gsutil 5.27

gcloud components list
gcloud components install kubectl
➜  ~ gcloud components install kubectl


Your current Google Cloud CLI version is: 452.0.1
Installing components from version: 452.0.1

┌─────────────────────────────────────────────┐
│     These components will be installed.     │
├────────────────────────┬─────────┬──────────┤
│          Name          │ Version │   Size   │
├────────────────────────┼─────────┼──────────┤
│ gke-gcloud-auth-plugin │   0.5.6 │  7.9 MiB │
│ kubectl                │  1.27.5 │ 98.0 MiB │
│ kubectl                │  1.27.5 │  < 1 MiB │
└────────────────────────┴─────────┴──────────┘

For the latest full release notes, please visit:
  https://cloud.google.com/sdk/release_notes

Do you want to continue (Y/n)?  Y

╔════════════════════════════════════════════════════════════╗
╠═ Creating update staging area                             ═╣
╠════════════════════════════════════════════════════════════╣
╠═ Installing: gke-gcloud-auth-plugin                       ═╣
╠════════════════════════════════════════════════════════════╣
╠═ Installing: gke-gcloud-auth-plugin                       ═╣
╠════════════════════════════════════════════════════════════╣
╠═ Installing: kubectl                                      ═╣
╠════════════════════════════════════════════════════════════╣
╠═ Installing: kubectl                                      ═╣
╠════════════════════════════════════════════════════════════╣
╠═ Creating backup and activating new installation          ═╣
╚════════════════════════════════════════════════════════════╝
Performing post processing steps...done.                                                                                                                  

Update done!

WARNING:   There are other instances of Google Cloud tools on your system PATH.
  Please remove the following to avoid confusion or accidental invocation:

  /usr/local/bin/kubectl


if [ -f '/opt/share/cumtom.sh' ] ; then
	echo "load the custom.sh"
	source /opt/share/cumtom.sh
	echo "loading finished"
fi


custom.sh
alias push='cd /Users/lex/git/knowledge && bash -x git.sh'

Using the KUBECONFIG environment variable in a zsh (or any shell) environment is a powerful way to manage access to multiple Kubernetes (K8s) clusters. By setting KUBECONFIG, you can specify a custom configuration file for kubectl to interact with different clusters without overwriting your default ~/.kube/config file. This is particularly useful when working with multiple K8s clusters (like different GKE clusters or clusters from other providers).

mkdir -p ~/.kube/config
export KUBECONFIG=~/.kube/config/aliyun.
export KUBECONFIG=~/.kube/config/cluster1-config:~/.kube/config/cluster2-config
kubectl config view --flatten > ~/.kube/merged-config

alias cluster1="export KUBECONFIG=~/kubeconfigs/cluster1-config"
alias cluster2="export KUBECONFIG=~/kubeconfigs/cluster2-config"
```
# save my images 
`# docker commit a41f7cff55a9 kalilinux/kali-rolling:jumpbox`

~ # docker images                                                                                                                             admin@NASLEX
REPOSITORY                                                                                    TAG             IMAGE ID       CREATED          SIZE
kalilinux/kali-rolling                                                                        jumpbox         7162d7d3033c   53 seconds ago   6.43GB


docker tag kalilinux/kali-rolling:jumpbox aibangjuxin/kali-jumpbox:jumpbox

~ # docker images                                                                                                                             admin@NASLEX
REPOSITORY                                                                                    TAG             IMAGE ID       CREATED          SIZE
aibangjuxin/kali-jumpbox                                                                      jumpbox         7162d7d3033c   10 minutes ago   6.43GB
kalilinux/kali-rolling                                                                        jumpbox         7162d7d3033c   10 minutes ago   6.43GB

------------------------------------------------------------
~ # export DOCKER_DEBUG=true                                                                                                                  admin@NASLEX
------------------------------------------------------------
~ # docker push aibangjuxin/kali-jumpbox:jumpbox                                                                                              admin@NASLEX
The push refers to repository [docker.io/aibangjuxin/kali-jumpbox]