FROM kalilinux/kali-rolling

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color

# 更新包管理器并安装基础工具
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# 安装安全工具和开发工具
RUN apt-get update && apt-get install -y \
    # 网络安全工具
    nmap \
    nikto \
    sslscan \
    dnsrecon \
    amass \
    john \
    # 网络工具
    inetutils-telnet \
    net-tools \
    dnsutils \
    iputils-ping \
    # 开发工具
    git \
    neovim \
    zsh \
    python3 \
    python3-pip \
    # 系统工具
    htop \
    tree \
    unzip \
    jq \
    && rm -rf /var/lib/apt/lists/*

# 安装 Oh My Zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# 安装 autojump
RUN apt-get update && apt-get install -y autojump && rm -rf /var/lib/apt/lists/*

# 安装 kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# 设置 zsh 为默认 shell
RUN chsh -s /bin/zsh

# 创建工作目录
WORKDIR /workspace

# 设置默认命令
CMD ["/bin/zsh"]