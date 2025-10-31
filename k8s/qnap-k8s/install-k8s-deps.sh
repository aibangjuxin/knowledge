#!/bin/bash
# 不要使用 set -e，因为 QNAP 系统可能有一些非标准的配置文件
# set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
if [[ $EUID -ne 0 ]]; then
   print_error "此脚本需要root权限运行"
   exit 1
fi

print_info "开始安装 Kubernetes 依赖 (QNAP 版本)..."

# 检测 QNAP 系统
detect_qnap_system() {
    local is_qnap=false
    local qnap_info=""
    
    # 方法1: 检查 qpkg 命令
    if command -v qpkg &> /dev/null; then
        is_qnap=true
        qnap_info="通过 qpkg 命令检测"
    fi
    
    # 方法2: 检查 QNAP 特有文件
    if [[ -f /etc/platform.conf ]]; then
        # 安全地读取平台信息，避免执行
        if grep -q "Platform" /etc/platform.conf 2>/dev/null; then
            local platform_name=$(grep "Platform" /etc/platform.conf | cut -d'=' -f2 | tr -d '"' | head -1)
            is_qnap=true
            qnap_info="平台: $platform_name"
        fi
    fi
    
    # 方法3: 检查其他 QNAP 特征
    if [[ -d /share/CACHEDEV1_DATA ]] || [[ -d /share/homes ]] || [[ -f /etc/qnap_platform.conf ]]; then
        is_qnap=true
        if [[ -z "$qnap_info" ]]; then
            qnap_info="通过文件系统结构检测"
        fi
    fi
    
    # 方法4: 检查进程
    if pgrep -f "qnap" > /dev/null 2>&1; then
        is_qnap=true
        if [[ -z "$qnap_info" ]]; then
            qnap_info="通过系统进程检测"
        fi
    fi
    
    if [[ "$is_qnap" = true ]]; then
        print_success "检测到 QNAP 系统 ($qnap_info)"
        return 0
    else
        print_warning "未检测到 QNAP 系统，将使用通用安装方式"
        return 1
    fi
}

# 获取系统架构
get_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "arm"
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
}

ARCH=$(get_arch)
print_info "系统架构: $ARCH"

# 检测网络环境和选择镜像源
detect_network_environment() {
    print_info "检测网络环境..."
    
    # 多重网络检测
    local network_tests=(
        "https://www.google.com"
        "https://github.com"
        "https://registry.k8s.io"
    )
    
    local can_access_global=false
    for url in "${network_tests[@]}"; do
        if curl -s --connect-timeout 3 --max-time 5 "$url" > /dev/null 2>&1; then
            can_access_global=true
            print_info "可以访问: $url"
            break
        else
            print_info "无法访问: $url"
        fi
    done
    
    if [[ "$can_access_global" = true ]]; then
        print_info "检测到国外网络环境或网络畅通"
        USE_CHINA_MIRROR=false
    else
        print_info "检测到国内网络环境或网络受限"
        USE_CHINA_MIRROR=true
    fi
    
    # 用户可以手动选择
    echo ""
    echo "请选择下载源："
    echo "1) 自动检测 (当前: $([ "$USE_CHINA_MIRROR" = true ] && echo "国内源" || echo "国外源"))"
    echo "2) 强制使用国内镜像源 (推荐国内用户)"
    echo "3) 使用官方源 (国外用户)"
    echo "4) 跳过选择，直接使用当前检测结果"
    read -t 30 -p "请选择 (1-4，30秒后自动选择1): " MIRROR_CHOICE
    
    # 如果超时或没有输入，默认为1
    MIRROR_CHOICE=${MIRROR_CHOICE:-1}
    
    case $MIRROR_CHOICE in
        2)
            USE_CHINA_MIRROR=true
            print_info "已选择国内镜像源"
            ;;
        3)
            USE_CHINA_MIRROR=false
            print_info "已选择官方源"
            ;;
        4)
            print_info "跳过选择，使用检测结果: $([ "$USE_CHINA_MIRROR" = true ] && echo "国内源" || echo "官方源")"
            ;;
        *)
            print_info "使用自动检测结果: $([ "$USE_CHINA_MIRROR" = true ] && echo "国内源" || echo "官方源")"
            ;;
    esac
}

# 设置镜像源 URL
setup_mirror_urls() {
    if [ "$USE_CHINA_MIRROR" = true ]; then
        # 国内镜像源
        DOCKER_DOWNLOAD_URL="https://mirrors.aliyun.com/docker-ce/linux/static/stable"
        K8S_DOWNLOAD_URL="https://kubernetes.oss-cn-hangzhou.aliyuncs.com"
        DOCKER_REGISTRY_MIRRORS='[
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://registry.cn-hangzhou.aliyuncs.com"
  ]'
        print_info "使用国内镜像源"
    else
        # 官方源
        DOCKER_DOWNLOAD_URL="https://download.docker.com/linux/static/stable"
        K8S_DOWNLOAD_URL="https://dl.k8s.io"
        DOCKER_REGISTRY_MIRRORS='[
    "https://registry-1.docker.io"
  ]'
        print_info "使用官方源"
    fi
}

detect_network_environment
setup_mirror_urls

# 安装 Docker (QNAP 版本)
install_docker_qnap() {
    print_info "检查 Docker 安装状态..."
    
    if command -v docker &> /dev/null; then
        print_success "Docker 已安装"
        docker --version
        return 0
    fi
    
    print_info "在 QNAP 上安装 Docker..."
    
    # 检查是否可以通过 Container Station 安装
    if command -v qpkg &> /dev/null; then
        print_info "尝试通过 QPKG 安装 Container Station..."
        # 注意：用户需要手动在 App Center 安装 Container Station
        print_warning "请在 QNAP App Center 中安装 'Container Station' 应用"
        print_warning "安装完成后，Docker 将自动可用"
        return 1
    fi
    
    # 手动安装 Docker (适用于支持的 QNAP 型号)
    print_info "尝试手动安装 Docker..."
    
    # 创建安装目录
    mkdir -p /opt/docker/bin
    
    # 下载 Docker 二进制文件
    DOCKER_VERSION="20.10.21"
    DOCKER_URL="${DOCKER_DOWNLOAD_URL}/${ARCH}/docker-${DOCKER_VERSION}.tgz"
    
    print_info "下载 Docker ${DOCKER_VERSION} for ${ARCH}..."
    print_info "下载地址: $DOCKER_URL"
    
    if curl -fsSL "$DOCKER_URL" -o /tmp/docker.tgz; then
        tar -xzf /tmp/docker.tgz -C /tmp
        cp /tmp/docker/* /opt/docker/bin/
        chmod +x /opt/docker/bin/*
        
        # 创建符号链接
        ln -sf /opt/docker/bin/docker /usr/local/bin/docker
        ln -sf /opt/docker/bin/dockerd /usr/local/bin/dockerd
        
        # 清理临时文件
        rm -rf /tmp/docker /tmp/docker.tgz
        
        print_success "Docker 二进制文件安装完成"
    else
        print_error "Docker 下载失败"
        return 1
    fi
    
    # 创建 Docker 服务配置
    create_docker_service
}

# 创建 Docker 服务
create_docker_service() {
    print_info "配置 Docker 服务..."
    
    # 创建 Docker 配置目录
    mkdir -p /etc/docker
    
    # 配置 Docker daemon
    cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": ${DOCKER_REGISTRY_MIRRORS},
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "data-root": "/share/docker"
}
EOF
    
    # 创建数据目录
    mkdir -p /share/docker
    
    # 创建启动脚本
    cat > /opt/docker/start-docker.sh << 'EOF'
#!/bin/bash
# 启动 Docker daemon
export PATH="/opt/docker/bin:$PATH"

# 检查是否已运行
if pgrep dockerd > /dev/null; then
    echo "Docker daemon 已在运行"
    exit 0
fi

# 启动 dockerd
nohup dockerd \
    --config-file=/etc/docker/daemon.json \
    --pidfile=/var/run/docker.pid \
    > /var/log/docker.log 2>&1 &

# 等待启动
sleep 5

if pgrep dockerd > /dev/null; then
    echo "Docker daemon 启动成功"
else
    echo "Docker daemon 启动失败"
    exit 1
fi
EOF
    
    chmod +x /opt/docker/start-docker.sh
    
    # 启动 Docker
    /opt/docker/start-docker.sh
    
    print_success "Docker 服务配置完成"
}

# 安装 Kubernetes 工具 (QNAP 版本)
install_k8s_tools_qnap() {
    print_info "安装 kubeadm, kubelet, kubectl..."
    
    if command -v kubeadm &> /dev/null; then
        print_success "Kubernetes 工具已安装"
        kubeadm version
        return 0
    fi
    
    # 创建安装目录
    mkdir -p /opt/k8s/bin
    
    # Kubernetes 版本
    K8S_VERSION="v1.26.0"
    
    # 下载 Kubernetes 二进制文件
    print_info "下载 Kubernetes ${K8S_VERSION} 二进制文件..."
    
    local base_url="${K8S_DOWNLOAD_URL}/${K8S_VERSION}/bin/linux/${ARCH}"
    local tools=("kubeadm" "kubelet" "kubectl")
    
    print_info "下载源: $base_url"
    
    for tool in "${tools[@]}"; do
        print_info "下载 ${tool}..."
        local download_url="${base_url}/${tool}"
        
        # 如果是国内源，尝试多个备用地址
        if [ "$USE_CHINA_MIRROR" = true ]; then
            local backup_urls=(
                "https://kubernetes.oss-cn-hangzhou.aliyuncs.com/${K8S_VERSION}/bin/linux/${ARCH}/${tool}"
                "https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/${ARCH}/${tool}"
                "https://dl.k8s.io/${K8S_VERSION}/bin/linux/${ARCH}/${tool}"
            )
            
            local success=false
            for url in "${backup_urls[@]}"; do
                print_info "尝试下载: $url"
                if curl -fsSL "$url" -o "/opt/k8s/bin/${tool}"; then
                    chmod +x "/opt/k8s/bin/${tool}"
                    ln -sf "/opt/k8s/bin/${tool}" "/usr/local/bin/${tool}"
                    print_success "${tool} 下载完成"
                    success=true
                    break
                else
                    print_warning "下载失败，尝试下一个源..."
                fi
            done
            
            if [ "$success" = false ]; then
                print_error "${tool} 所有源都下载失败"
                return 1
            fi
        else
            # 官方源直接下载
            if curl -fsSL "$download_url" -o "/opt/k8s/bin/${tool}"; then
                chmod +x "/opt/k8s/bin/${tool}"
                ln -sf "/opt/k8s/bin/${tool}" "/usr/local/bin/${tool}"
                print_success "${tool} 下载完成"
            else
                print_error "${tool} 下载失败"
                return 1
            fi
        fi
    done
    
    # 创建 kubelet 服务配置
    create_kubelet_service
    
    print_success "Kubernetes 工具安装完成"
}

# 创建 kubelet 服务
create_kubelet_service() {
    print_info "配置 kubelet 服务..."
    
    # 创建 kubelet 配置目录
    mkdir -p /etc/kubernetes
    mkdir -p /var/lib/kubelet
    mkdir -p /etc/systemd/system/kubelet.service.d
    
    # 创建 kubelet 启动脚本
    cat > /opt/k8s/start-kubelet.sh << 'EOF'
#!/bin/bash
# 启动 kubelet
export PATH="/opt/k8s/bin:$PATH"

# 检查是否已运行
if pgrep kubelet > /dev/null; then
    echo "kubelet 已在运行"
    exit 0
fi

# 启动 kubelet
nohup kubelet \
    --config=/var/lib/kubelet/config.yaml \
    --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf \
    --kubeconfig=/etc/kubernetes/kubelet.conf \
    --container-runtime=remote \
    --container-runtime-endpoint=unix:///var/run/dockershim.sock \
    --fail-swap-on=false \
    > /var/log/kubelet.log 2>&1 &

echo "kubelet 启动完成"
EOF
    
    chmod +x /opt/k8s/start-kubelet.sh
    
    print_success "kubelet 服务配置完成"
}

# 系统配置 (QNAP 版本)
configure_system_qnap() {
    print_info "配置 QNAP 系统参数..."
    
    local config_success=true
    
    # 关闭 swap (如果存在)
    if swapon --show 2>/dev/null | grep -q swap; then
        print_info "关闭 swap..."
        if swapoff -a 2>/dev/null; then
            print_success "swap 已关闭"
        else
            print_warning "关闭 swap 失败，但继续"
            config_success=false
        fi
    else
        print_info "系统未启用 swap"
    fi
    
    # 加载内核模块
    print_info "加载必要的内核模块..."
    if modprobe overlay 2>/dev/null; then
        print_success "overlay 模块加载成功"
    else
        print_warning "overlay 模块加载失败，可能影响容器存储"
        config_success=false
    fi
    
    if modprobe br_netfilter 2>/dev/null; then
        print_success "br_netfilter 模块加载成功"
    else
        print_warning "br_netfilter 模块加载失败，可能影响网络功能"
        config_success=false
    fi
    
    # 设置内核参数
    print_info "配置内核参数..."
    
    # 创建 sysctl 配置目录
    if mkdir -p /etc/sysctl.d 2>/dev/null; then
        # 创建配置文件
        if cat > /etc/sysctl.d/99-k8s.conf << 'EOF'
# Kubernetes 网络配置
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1

# 容器网络优化
net.netfilter.nf_conntrack_max = 1000000
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 8096
EOF
        then
            print_success "内核参数配置文件创建成功"
            
            # 应用配置
            if sysctl -p /etc/sysctl.d/99-k8s.conf >/dev/null 2>&1; then
                print_success "内核参数应用成功"
            else
                print_warning "部分内核参数设置失败，但继续"
                config_success=false
            fi
        else
            print_warning "内核参数配置文件创建失败"
            config_success=false
        fi
    else
        print_warning "无法创建 sysctl 配置目录"
        config_success=false
    fi
    
    # 创建必要的目录
    print_info "创建必要的目录..."
    local dirs=("/var/lib/etcd" "/etc/kubernetes/pki" "/var/log/pods" "/share/k8s-data")
    
    for dir in "${dirs[@]}"; do
        if mkdir -p "$dir" 2>/dev/null; then
            chmod 755 "$dir" 2>/dev/null || print_warning "设置 $dir 权限失败"
            print_success "目录创建成功: $dir"
        else
            print_warning "目录创建失败: $dir"
            config_success=false
        fi
    done
    
    if [[ "$config_success" = true ]]; then
        print_success "QNAP 系统配置完成"
        return 0
    else
        print_warning "QNAP 系统配置完成，但有部分警告"
        return 1
    fi
}

# 检查系统兼容性
check_qnap_compatibility() {
    print_info "检查 QNAP 系统兼容性..."
    
    # 检查内核版本
    local kernel_version=$(uname -r)
    print_info "内核版本: $kernel_version"
    
    # 检查 cgroup 支持
    if [[ -d /sys/fs/cgroup ]]; then
        print_success "cgroup 支持正常"
    else
        print_warning "cgroup 支持可能有问题"
    fi
    
    # 检查网络命名空间支持
    if ip netns list &>/dev/null; then
        print_success "网络命名空间支持正常"
    else
        print_warning "网络命名空间支持可能有问题"
    fi
    
    # 检查存储空间
    local available_space=$(df /share 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    if [[ $available_space -gt 10485760 ]]; then  # 10GB in KB
        print_success "存储空间充足 ($(($available_space/1024/1024))GB 可用)"
    else
        print_warning "存储空间可能不足，建议至少 10GB 可用空间"
    fi
    
    print_success "兼容性检查完成"
}

# 主安装流程 (QNAP 版本)
main() {
    print_info "开始在 QNAP 上安装 Kubernetes 环境..."
    
    # 检测 QNAP 系统 (不强制要求成功)
    if detect_qnap_system; then
        print_success "QNAP 系统检测成功"
    else
        print_warning "QNAP 系统检测失败，继续使用通用安装方式"
    fi
    
    # 检查兼容性 (不强制要求成功)
    if check_qnap_compatibility; then
        print_success "兼容性检查通过"
    else
        print_warning "兼容性检查有警告，但继续安装"
    fi
    
    # 安装基础工具 (如果需要)
    install_basic_tools || print_warning "基础工具安装有问题，但继续"
    
    # 系统配置
    if configure_system_qnap; then
        print_success "系统配置完成"
    else
        print_warning "系统配置有问题，但继续安装"
    fi
    
    # 安装 Docker (QNAP 主要使用 Docker)
    print_info "在 QNAP 上安装 Docker..."
    if install_docker_qnap; then
        print_success "Docker 安装成功"
    else
        print_error "Docker 安装失败"
        print_info "请尝试以下解决方案："
        echo "  1. 在 QNAP App Center 中安装 'Container Station'"
        echo "  2. 重启 QNAP 系统后重试"
        echo "  3. 检查网络连接"
        return 1
    fi
    
    # 安装 Kubernetes 工具
    if install_k8s_tools_qnap; then
        print_success "Kubernetes 工具安装成功"
    else
        print_error "Kubernetes 工具安装失败"
        print_info "请检查网络连接或手动下载"
        return 1
    fi
    
    # 创建启动脚本
    if create_startup_scripts; then
        print_success "启动脚本创建成功"
    else
        print_warning "启动脚本创建有问题"
    fi
    
    print_success "QNAP Kubernetes 依赖安装完成！"
    print_info "重要提示："
    echo "  1. 如果遇到问题，请运行 './test-qnap-detection.sh' 进行诊断"
    echo "  2. 运行 'source /etc/profile' 或重新登录以更新 PATH"
    echo "  3. 运行 './init-k8s.sh' 来初始化集群"
    echo ""
    print_info "验证安装："
    echo "  docker --version"
    echo "  kubeadm version"
    echo "  kubectl version --client"
    echo ""
    print_info "如果验证失败，请检查 PATH 环境变量："
    echo "  export PATH=\"/opt/k8s/bin:/opt/docker/bin:\$PATH\""
}

# 安装基础工具
install_basic_tools() {
    print_info "检查基础工具..."
    
    # 检查 curl
    if ! command -v curl &> /dev/null; then
        print_warning "curl 未安装，尝试安装..."
        if command -v opkg &> /dev/null; then
            opkg update && opkg install curl
        else
            print_error "无法安装 curl，请手动安装"
        fi
    fi
    
    # 检查其他必要工具
    local tools=("wget" "tar" "gzip")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_warning "$tool 未找到，可能影响安装"
        fi
    done
}

# 创建启动脚本
create_startup_scripts() {
    print_info "创建 QNAP 启动脚本..."
    
    # 创建主启动脚本
    cat > /opt/k8s/start-k8s-services.sh << 'EOF'
#!/bin/bash
# QNAP Kubernetes 服务启动脚本

echo "启动 Kubernetes 服务..."

# 启动 Docker
if [[ -f /opt/docker/start-docker.sh ]]; then
    /opt/docker/start-docker.sh
fi

# 等待 Docker 启动
sleep 10

# 检查 Docker 状态
if ! docker info &>/dev/null; then
    echo "错误: Docker 未正常启动"
    exit 1
fi

echo "Docker 服务正常"

# 设置环境变量
export PATH="/opt/k8s/bin:/opt/docker/bin:$PATH"

echo "Kubernetes 服务启动完成"
echo "使用 'kubectl version --client' 验证安装"
EOF
    
    chmod +x /opt/k8s/start-k8s-services.sh
    
    # 创建环境配置文件
    cat > /opt/k8s/k8s-env.sh << 'EOF'
#!/bin/bash
# Kubernetes 环境配置

export PATH="/opt/k8s/bin:/opt/docker/bin:$PATH"
export KUBECONFIG="$HOME/.kube/config"

# 别名
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'

echo "Kubernetes 环境已加载"
EOF
    
    chmod +x /opt/k8s/k8s-env.sh
    
    # 添加到 profile
    if ! grep -q "/opt/k8s/k8s-env.sh" /etc/profile 2>/dev/null; then
        echo "source /opt/k8s/k8s-env.sh" >> /etc/profile
    fi
    
    print_success "启动脚本创建完成"
}

main "$@"