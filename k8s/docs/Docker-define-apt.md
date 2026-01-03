你可以在 Dockerfile 中使用 RUN 指令替换默认的 apt 源。通常的方法是：
	1.	备份原始的 sources.list（可选）。
	2.	替换 /etc/apt/sources.list 为你想要的源。
	3.	运行 apt-get update 以使更改生效。

下面是一个完整的 Dockerfile 示例，使用了 Ubuntu 作为基础镜像，并替换默认的 apt 源为 mirrors.aliyun.com（你可以更换为其他源）：
```Dockerfile
# 使用最新的 Ubuntu 作为基础镜像
FROM ubuntu:latest

# 设置时区，避免交互式问题
ENV DEBIAN_FRONTEND=noninteractive

# 备份原始的 sources.list 并替换为新的 APT 源
RUN cp /etc/apt/sources.list /etc/apt/sources.list.bak && \
    echo "deb http://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse" > /etc/apt/sources.list && \
    echo "deb http://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb http://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb http://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y curl vim && \
    rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 运行容器时的默认命令
CMD ["/bin/bash"]
```
说明：
	1.	基础镜像：使用 ubuntu:latest，你可以替换为其他版本（如 ubuntu:20.04）。
	2.	环境变量：DEBIAN_FRONTEND=noninteractive 避免 apt 过程中出现交互提示。
	3.	替换 apt 源：
	•	先备份 /etc/apt/sources.list。
	•	用 echo 覆盖 sources.list，并加入多个 deb 源地址（这里使用了阿里云的 Ubuntu 源）。
	4.	更新 apt：
	•	apt-get update 更新软件包索引。
	•	apt-get install -y curl vim 安装 curl 和 vim 作为示例。
	•	清理 /var/lib/apt/lists/* 以减少镜像大小。
	5.	CMD 指令：容器默认启动 /bin/bash，你可以改成其他命令。

这样，每次构建镜像时，都会使用你自定义的 apt 源，而不是默认的 Ubuntu 源。
