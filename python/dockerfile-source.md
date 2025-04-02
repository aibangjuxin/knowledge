我有一个Docker file 
1 Using from Ubuntu 20.04
2 比如里面默认的源 不能使用了 我需要
1 替换源 Sed apt source to nexusnew 
2 and add a define source  比如也可以走这个源更新
给我一个这样的dockfile 

如果你想在 Dockerfile 中 手动添加一个特定的 APT 源，用于安装 Python（或其他特定软件包），可以按照以下方式操作：

1. 获取 Nexus APT 仓库地址

在 Nexus 私有仓库中，APT 源通常如下格式：

http://nexusnew/repository/ubuntu

如果你的 Python 包存储在 专用 APT 仓库，比如：

http://nexusnew/repository/python-apt

那么你需要创建一个额外的 sources.list 进行配置。

⸻

2. 在 Dockerfile 中添加额外的 APT 源

假设你的 Nexus 服务器托管了 Python APT 源，我们可以手动创建 /etc/apt/sources.list.d/python.list 来指向它。
```Dockerfile
# 使用 Ubuntu 20.04 作为基础镜像
FROM ubuntu:20.04

# 设置非交互模式，防止 tzdata 配置交互
ENV DEBIAN_FRONTEND=noninteractive

# 备份默认的 sources.list，并替换为 nexusnew
RUN mv /etc/apt/sources.list /etc/apt/sources.list.bak && \
    echo "deb http://nexusnew/repository/ubuntu focal main restricted universe multiverse" > /etc/apt/sources.list && \
    echo "deb http://nexusnew/repository/ubuntu focal-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb http://nexusnew/repository/ubuntu focal-security main restricted universe multiverse" >> /etc/apt/sources.list && \
    \
    # 添加 Python 相关的 APT 源
    echo "deb [trusted=yes] http://nexusnew/repository/python-apt focal main" > /etc/apt/sources.list.d/python.list && \
    \
    # 更新 APT 并安装 Python
    apt-get update && \
    apt-get install -y python3 python3-pip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 设置默认 shell
CMD ["/bin/bash"]
```


⸻

3. 说明
	•	/etc/apt/sources.list.d/python.list
	•	这个文件专门指向 Python 的 APT 仓库。
	•	trusted=yes 允许 APT 信任这个源（如果 Nexus 没有 GPG 签名）。
	•	这样 apt-get install python3 时就会从 Nexus 下载 Python 相关的软件包，而不是官方源。
	•	apt-get update
	•	让 APT 识别新的源，并获取 Python 包的信息。
	•	apt-get install -y python3 python3-pip
	•	安装 Python3 和 pip，如果 Nexus 上有这个包，会从 Nexus 下载，否则会报错。

⸻

4. 如果 Nexus 需要 GPG 密钥

如果 Nexus 仓库有 GPG 签名，你需要先获取密钥：

RUN curl -fsSL http://nexusnew/repository/python-apt/KEY.gpg | apt-key add -

然后在 python.list 中去掉 [trusted=yes]，改为：

deb http://nexusnew/repository/python-apt focal main

这样，APT 就会使用 Nexus 作为 Python 包的 APT 源，并保持安全性。

⸻

5. 如果 Nexus 是 HTTP 而不是 HTTPS

Ubuntu 20.04 默认禁用了 HTTP APT 源，如果 Nexus 只支持 HTTP，你可能需要：

RUN apt-get install -y apt-transport-http

这样 APT 就能正确使用 http://nexusnew/... 作为 APT 源。

⸻

6. 验证 Nexus APT 源是否可用

在 Docker 容器里执行：

apt-cache policy python3

如果输出：

  Installed: (none)
  Candidate: 3.x.x
  Version table:
     3.x.x 500
        500 http://nexusnew/repository/python-apt focal/main amd64 Packages

说明 APT 已正确解析 Nexus APT 源，你可以正常安装 Python 了。

⸻

这样，你的 Dockerfile 就可以在 Nexus 内部 APT 仓库中安装 Python，同时保留 Ubuntu 官方源作为备用。


是的，如果你已经手动下载了 Python 的 .deb 包，那么你可以直接在 Dockerfile 中使用 dpkg -i 安装，或者通过 apt install 来解决依赖问题。以下是完整的 Dockerfile 参考：

⸻

方法 1：直接使用 dpkg -i 安装 DEB 包

如果你 只 有 python3.deb，并且它的依赖项已经满足，你可以这样安装：
```Dockerfile
# 使用 Ubuntu 20.04 作为基础镜像
FROM ubuntu:20.04

# 设置非交互模式，防止 tzdata 配置交互
ENV DEBIAN_FRONTEND=noninteractive

# 复制 Python deb 包到镜像
COPY python3.deb /tmp/python3.deb

# 安装依赖项，并手动安装 Python deb 包
RUN apt-get update && \
    apt-get install -y dpkg && \
    dpkg -i /tmp/python3.deb && \
    rm -rf /var/lib/apt/lists/* /tmp/python3.deb

# 设置默认 shell
CMD ["/bin/bash"]
```
说明
	•	COPY python3.deb /tmp/python3.deb
	•	将 python3.deb 拷贝到镜像内 /tmp 目录
	•	dpkg -i /tmp/python3.deb
	•	使用 dpkg 手动安装 python3
	•	缺点：如果 python3.deb 依赖其他 .deb 包，它不会自动安装，会报错。

⸻

方法 2：使用 apt install ./package.deb 自动解决依赖

如果 python3.deb 需要额外的依赖项（如 libpython3.8），可以这样写：
```Dockerfile
# 使用 Ubuntu 20.04 作为基础镜像
FROM ubuntu:20.04

# 设置非交互模式，防止 tzdata 配置交互
ENV DEBIAN_FRONTEND=noninteractive

# 复制 Python deb 包到镜像
COPY python3.deb /tmp/python3.deb

# 安装 APT 依赖，并自动安装 .deb 包及其依赖项
RUN apt-get update && \
    apt-get install -y ./tmp/python3.deb && \
    rm -rf /var/lib/apt/lists/* /tmp/python3.deb

# 设置默认 shell
CMD ["/bin/bash"]
```
说明
	•	apt install -y ./tmp/python3.deb
	•	自动解决依赖，比 dpkg -i 更安全
	•	适用于 .deb 包有依赖时，APT 会自动从官方或自定义的源下载缺失的依赖包

⸻

方法 3：如果有多个 .deb 包

如果 Python 及其依赖项都是 .deb 文件，比如：

python3.deb
libpython3.8.deb
pip.deb

可以一次性安装所有包：
```Dockerfile
# 使用 Ubuntu 20.04 作为基础镜像
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# 复制所有 deb 包到容器
COPY python3.deb libpython3.8.deb pip.deb /tmp/

# 先更新 APT，并一次性安装所有 deb 包
RUN apt-get update && \
    apt install -y /tmp/*.deb && \
    rm -rf /var/lib/apt/lists/* /tmp/*.deb

CMD ["/bin/bash"]
```
适用场景
	•	你已经下载了 Python 及其依赖项
	•	你不想使用 apt 官方源

这样，Docker 直接从本地 .deb 安装，不需要外部依赖。

⸻

结论

| 方案 | 适用场景 | 是否解决依赖 | 使用的命令 |
|------|----------|--------------|------------|
| 方法 1 (dpkg -i) | 仅有 .deb，无依赖 | ❌ 需要手动解决 | dpkg -i python3.deb |
| 方法 2 (apt install ./package.deb) | 需要解决 .deb 依赖 | ✅ 自动安装依赖 | apt install -y ./python3.deb |
| 方法 3 (apt install /tmp/*.deb) | 有多个 .deb，不依赖 APT 源 | ✅ 一次性安装 | apt install -y /tmp/*.deb |

如果你的 .deb 包来自 Nexus，可以：
	1.	先手动 wget 下载 .deb
	2.	再使用 Dockerfile 安装

例如：

RUN wget -O /tmp/python3.deb http://nexusnew/repository/python/python3.deb && \
    apt install -y /tmp/python3.deb && \
    rm -rf /tmp/python3.deb

这样，你就能在没有公网 APT 访问的情况下，完全通过 .deb 安装 Python 🎯