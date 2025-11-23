本质需求了：**你想在本地 Mac 上通过 docker CLI 操作并使用位于远程 NAS（路径 `/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker`）上的镜像**。下面给出可行方案、命令和注意事项——从最稳妥到备选方案，按步骤执行即可。

# 要点结论（快速答案）

- 最稳妥且推荐的做法是：**把 NAS 上的 `docker` 二进制放到远程系统的标准 PATH（例如 `/usr/local/bin/docker`）或建立符号链接**，然后用 Docker 的 SSH 方式把本地 CLI 绑定到远程 daemon：  
    `DOCKER_HOST=ssh://admin@192.168.31.88` 或 使用 docker context。
    
- 这样你可以在本地直接运行 `docker --context=mynas images`、`docker --context=mynas push ...`、也可以把远端镜像流式拉到本地 `docker save | docker load`。
    

---

## 原因简述（为什么需要修改）

你之前看到的错误：

```
ssh ... docker system dial-stdio
sh: docker: command not found
```

说明 Docker CLI 用的是 SSH 协议：它会在远端以非交互 shell 直接执行 `docker`。**因此远端必须能直接在 PATH 中找到并执行 `docker`**，否则会报 `command not found`。把二进制放在标准 PATH（或做 symlink）是最直接的修复。

---

# 推荐步骤（按顺序做）

## 1) 在 NAS（远程主机）上放一个可被非交互 shell 找到的 `docker` 可执行文件

SSH 登录到 NAS（以 `admin` 为例）：

```bash
ssh admin@192.168.31.88
```

检查二进制路径：

```bash
ls -l /share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker
```

创建一个全局可用的符号链接（需要 sudo 权限）：

```bash
# 在远端执行
sudo ln -sf /share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker /usr/local/bin/docker
sudo chmod +x /usr/local/bin/docker
```

（如果 `/usr/local/bin` 不可写，可选择 `/usr/bin`，但优先 `/usr/local/bin`。）

验证（在远端）：

```bash
/usr/local/bin/docker --version
which docker   # 应该返回 /usr/local/bin/docker
```

> 备注：如果你没有 sudo 权限，可以把 `docker` 放到远端用户的 home 下的 `bin` 并确保该目录在非交互 SSH 的 PATH（但很多系统非交互 shell 不加载 `~/.profile`，所以 symlink 到标准路径通常是最可靠的）。

---

## 2) 在本地用 Docker 的 SSH host 或 docker context 连接远端

推荐使用 docker context（更方便切换）：

创建 context（只需做一次）：

```bash
docker context create nas-remote --description "NAS via SSH" --docker "host=ssh://admin@192.168.31.88"
```

切换到该 context（临时或永久）：

```bash
# 临时使用 context 执行命令
docker --context nas-remote ps -a
docker --context nas-remote images

# 或把这个 context 设为默认
docker context use nas-remote
docker ps -a       # 现在会针对远端
```

如果你更喜欢环境变量（不推荐长期用），可以：

```bash
export DOCKER_HOST=ssh://admin@192.168.31.88
docker images
```

---

## 3) 在远端上查看镜像／推镜像／拉镜像

列远端镜像：

```bash
docker --context nas-remote images
```

直接在远端（通过 context）把镜像推到 Docker Hub（若远端已登录 Docker Hub）：

```bash
# 在本地向远端 daemon 进行 login（会在远端 daemon 存储凭据）
docker --context nas-remote login

# 然后 push（镜像名须以你的 hub 用户名开头）
docker --context nas-remote push youruser/yourrepo:tag
```

如果你想把远端镜像拉到本地然后再 push（或备份）：

```bash
# 从远端导出镜像并在本地载入（数据直接流），适合网络带宽允许
docker --context nas-remote save remote-image:tag | docker load
# 现在本地就有该镜像了：docker images
```

反之，从本地把镜像传给远端（例如要让远端 push）：

```bash
docker save local-image:tag | docker --context nas-remote load
# 然后在远端 context 下 tag & push
docker --context nas-remote tag local-image:tag youruser/repo:tag
docker --context nas-remote push youruser/repo:tag
```

---

# 备选方案（如果无法在远端创建 symlink / 没有 sudo）

### A. 修改远端的 SSH 配置以确保非交互 shell 有 PATH（不稳定）

你可以把 `export PATH=/share/CACHEDEV1_DATA/.qpkg/container-station/bin:$PATH` 放进远端用户的 `~/.profile` 或 `~/.ssh/environment`，并在 `/etc/ssh/sshd_config` 中允许 `PermitUserEnvironment yes` ——但这通常需要管理员权限且配置复杂，不如 symlink 稳妥。

### B. 暴露远端 Docker daemon 的 TCP 端口（不推荐，除非用 TLS）

可以在远端启用 Docker daemon 的 TCP 监听（例如 `tcp://0.0.0.0:2376`），并用 TLS 认证连接。但这是比较复杂且带安全风险的做法，不推荐在家用 NAS/不受管环境直接开启。

---

# 常见问题答疑

- Q: 我只想在本地用 `docker` 命令，不想每次写 `--context`？  
    A: 可以 `docker context use nas-remote` 把 context 设为默认，或在 `~/.bashrc`/`~/.zshrc` 里 `export DOCKER_HOST=ssh://admin@192.168.31.88`（不过 context 更优雅）。
    
- Q: 远端 push 到 Docker Hub 会使用哪里的凭据？  
    A: 当你对远端 daemon 执行 `docker --context nas-remote login` 时，凭据会保存在远端 daemon 的凭据存储（通常在远端文件系统）。如果想用本地凭据把远端镜像拉下来再本地 push，可用 `save | docker load`。
    
- Q: 我没有 sudo 权限，怎么办？  
    A: 尝试把 `docker` 二进制复制到你的 home 的 `~/bin` 并确认该目录在 PATH 中对非交互 SSH 有效（很多系统默认不可用）。如果不可行，请联系 NAS 管理员创建 symlink 或安装 docker properly。
    

---

# 最后给你一份快速指令清单（你可直接拷贝执行）

1. 在本地先测试远端有没有 docker 在 PATH（会失败）：
    

```bash
docker --context nas-remote version
# 如果报 "sh: docker: command not found"，继续下列步骤
```

2. 在远端创建 symlink（在本地执行 SSH 命令）：
    

```bash
ssh admin@192.168.31.88 "sudo ln -sf /share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker /usr/local/bin/docker && sudo chmod +x /usr/local/bin/docker && /usr/local/bin/docker --version"
```

3. 在本地创建并使用 docker context：
    

```bash
docker context create nas-remote --docker "host=ssh://admin@192.168.31.88"
docker --context nas-remote images
```

4. 把远端镜像直接推到 Docker Hub（在本地执行，实际会在远端 daemon 执行）：
    

```bash
docker --context nas-remote login
docker --context nas-remote push youruser/yourrepo:tag
```

5. 或把远端镜像拉回本地：
    

```bash
docker --context nas-remote save remote-image:tag | docker load
docker images   # 本地现在会出现该镜像
```

---

如果你愿意，我可以直接给出适合你当前网络/权限的**一步一步可执行脚本**（例如：尝试创建 symlink，若失败打印错误并提示下一步），或者你把 `ssh admin@192.168.31.88 'echo $PATH; ls -l /usr/local/bin/docker'` 的输出贴上来，我可以基于真实输出给出精确命令。要我直接生成脚本吗？