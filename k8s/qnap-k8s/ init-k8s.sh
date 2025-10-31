#!/bin/bash
set -e

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

# 检查 QNAP 环境
check_qnap_environment() {
    # 加载环境变量
    if [[ -f /opt/k8s/k8s-env.sh ]]; then
        source /opt/k8s/k8s-env.sh
    fi
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装或未在 PATH 中"
        print_info "请先运行 ./install-k8s-deps.sh 或在 App Center 安装 Container Station"
        exit 1
    fi
    
    # 检查 Docker 服务状态
    if ! docker info &>/dev/null; then
        print_error "Docker 服务未运行"
        print_info "尝试启动 Docker 服务..."
        if [[ -f /opt/docker/start-docker.sh ]]; then
            /opt/docker/start-docker.sh
            sleep 5
        fi
        
        if ! docker info &>/dev/null; then
            print_error "无法启动 Docker 服务"
            exit 1
        fi
    fi
    
    # 检查 kubeadm
    if ! command -v kubeadm &> /dev/null; then
        print_error "kubeadm 未安装，请先运行 ./install-k8s-deps.sh"
        exit 1
    fi
    
    print_success "QNAP 环境检查通过"
}

check_qnap_environment

print_info "开始初始化 Kubernetes 集群..."

# 检测网络环境并选择镜像源
detect_and_setup_image_sources() {
    print_info "检测网络环境并配置镜像源..."
    
    # 测试网络环境
    if curl -s --connect-timeout 5 https://www.google.com > /dev/null 2>&1; then
        print_info "检测到国外网络环境"
        USE_CHINA_MIRROR=false
    else
        print_info "检测到国内网络环境"
        USE_CHINA_MIRROR=true
    fi
    
    # 用户选择
    echo ""
    echo "请选择 Kubernetes 镜像源："
    echo "1) 自动检测 (当前: $([ "$USE_CHINA_MIRROR" = true ] && echo "国内源" || echo "国外源"))"
    echo "2) 国内镜像源 (阿里云、DaoCloud)"
    echo "3) 官方镜像源 (registry.k8s.io)"
    read -p "请选择 (1-3，默认1): " IMAGE_CHOICE
    
    case ${IMAGE_CHOICE:-1} in
        2)
            USE_CHINA_MIRROR=true
            ;;
        3)
            USE_CHINA_MIRROR=false
            ;;
        *)
            # 使用自动检测结果
            ;;
    esac
    
    # 设置镜像源
    if [ "$USE_CHINA_MIRROR" = true ]; then
        PRIMARY_IMAGE_REPO="registry.aliyuncs.com/google_containers"
        BACKUP_IMAGE_REPO="daocloud.io/google_containers"
        KUBEADM_IMAGE_REPO="registry.aliyuncs.com/google_containers"
        FLANNEL_IMAGE_REPO="registry.cn-hangzhou.aliyuncs.com/google_containers"
        print_success "使用国内镜像源"
    else
        PRIMARY_IMAGE_REPO="registry.k8s.io"
        BACKUP_IMAGE_REPO="k8s.gcr.io"
        KUBEADM_IMAGE_REPO="registry.k8s.io"
        FLANNEL_IMAGE_REPO="docker.io/flannel"
        print_success "使用官方镜像源"
    fi
}

K8S_VERSION="v1.26.0"
detect_and_setup_image_sources

print_info "拉取 Kubernetes 镜像..."

# 手动拉取所有必要镜像（国内源）
images=(
    "kube-apiserver:${K8S_VERSION}"
    "kube-controller-manager:${K8S_VERSION}"
    "kube-scheduler:${K8S_VERSION}"
    "kube-proxy:${K8S_VERSION}"
    "pause:3.9"
    "etcd:3.5.6-0"
    "coredns:v1.9.3"
)

for image in "${images[@]}"; do
    print_info "拉取镜像: ${image}"
    
    # 尝试主要镜像源
    if docker pull ${PRIMARY_IMAGE_REPO}/${image}; then
        print_success "从主要源拉取成功: ${PRIMARY_IMAGE_REPO}/${image}"
    elif docker pull ${BACKUP_IMAGE_REPO}/${image}; then
        print_success "从备用源拉取成功: ${BACKUP_IMAGE_REPO}/${image}"
    else
        print_error "镜像拉取失败: ${image}"
        
        # 如果是国内环境，尝试更多备用源
        if [ "$USE_CHINA_MIRROR" = true ]; then
            local additional_repos=(
                "registry.cn-hangzhou.aliyuncs.com/google_containers"
                "uhub.service.ucloud.cn/google_containers"
            )
            
            local pulled=false
            for repo in "${additional_repos[@]}"; do
                print_info "尝试额外源: ${repo}/${image}"
                if docker pull ${repo}/${image}; then
                    print_success "从额外源拉取成功: ${repo}/${image}"
                    pulled=true
                    break
                fi
            done
            
            if [ "$pulled" = false ]; then
                print_error "所有镜像源都失败，请检查网络连接"
                exit 1
            fi
        else
            print_error "镜像拉取失败，请检查网络连接"
            exit 1
        fi
    fi
done

print_info "为镜像打标签..."

# 为镜像打标签（符合kubeadm默认的registry.k8s.io格式）
tag_image() {
    local source_image=$1
    local target_tag=$2
    
    # 尝试从各个可能的源获取镜像ID
    local image_id=""
    local possible_repos=(
        "${PRIMARY_IMAGE_REPO}"
        "${BACKUP_IMAGE_REPO}"
    )
    
    # 如果是国内环境，添加更多可能的源
    if [ "$USE_CHINA_MIRROR" = true ]; then
        possible_repos+=(
            "registry.cn-hangzhou.aliyuncs.com/google_containers"
            "uhub.service.ucloud.cn/google_containers"
        )
    fi
    
    for repo in "${possible_repos[@]}"; do
        image_id=$(docker images -q ${repo}/${source_image} 2>/dev/null)
        if [[ -n "$image_id" ]]; then
            break
        fi
    done
    
    if [[ -n "$image_id" ]]; then
        docker tag $image_id $target_tag
        print_success "标签创建成功: $target_tag"
    else
        print_error "找不到镜像: $source_image"
        return 1
    fi
}

# 创建标签映射
tag_image "kube-apiserver:${K8S_VERSION}" "registry.k8s.io/kube-apiserver:${K8S_VERSION}"
tag_image "kube-controller-manager:${K8S_VERSION}" "registry.k8s.io/kube-controller-manager:${K8S_VERSION}"
tag_image "kube-scheduler:${K8S_VERSION}" "registry.k8s.io/kube-scheduler:${K8S_VERSION}"
tag_image "kube-proxy:${K8S_VERSION}" "registry.k8s.io/kube-proxy:${K8S_VERSION}"
tag_image "pause:3.9" "registry.k8s.io/pause:3.9"
tag_image "etcd:3.5.6-0" "registry.k8s.io/etcd:3.5.6-0"
tag_image "coredns:v1.9.3" "registry.k8s.io/coredns/coredns:v1.9.3"

# 同时创建旧格式标签以兼容
tag_image "kube-apiserver:${K8S_VERSION}" "k8s.gcr.io/kube-apiserver:${K8S_VERSION}"
tag_image "kube-controller-manager:${K8S_VERSION}" "k8s.gcr.io/kube-controller-manager:${K8S_VERSION}"
tag_image "kube-scheduler:${K8S_VERSION}" "k8s.gcr.io/kube-scheduler:${K8S_VERSION}"
tag_image "kube-proxy:${K8S_VERSION}" "k8s.gcr.io/kube-proxy:${K8S_VERSION}"
tag_image "pause:3.9" "k8s.gcr.io/pause:3.9"
tag_image "etcd:3.5.6-0" "k8s.gcr.io/etcd:3.5.6-0"
tag_image "coredns:v1.9.3" "k8s.gcr.io/coredns/coredns:v1.9.3"

print_info "创建 kubeadm 配置文件..."

# 创建kubeadm配置文件
cat > /tmp/kubeadm-config.yaml << EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: $(hostname -I | awk '{print $1}')
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/dockershim.sock
  kubeletExtraArgs:
    fail-swap-on: "false"
    cgroup-driver: cgroupfs
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: ${K8S_VERSION}
imageRepository: ${KUBEADM_IMAGE_REPO}
controlPlaneEndpoint: $(hostname -I | awk '{print $1}'):6443
networking:
  serviceSubnet: 10.96.0.0/12
  podSubnet: 10.244.0.0/16
  dnsDomain: cluster.local
etcd:
  local:
    dataDir: /var/lib/etcd
apiServer:
  timeoutForControlPlane: 4m0s
controllerManager: {}
scheduler: {}
dns:
  type: CoreDNS
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: cgroupfs
failSwapOn: false
containerLogMaxSize: "100Mi"
containerLogMaxFiles: 5
EOF

print_info "初始化 Kubernetes 控制平面..."

# 初始化控制平面
if kubeadm init --config=/tmp/kubeadm-config.yaml --ignore-preflight-errors=SystemVerification,NumCPU,Mem; then
    print_success "Kubernetes 控制平面初始化成功"
else
    print_error "Kubernetes 控制平面初始化失败"
    exit 1
fi

print_info "配置 kubectl..."

# 复制配置文件
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# 如果是普通用户运行sudo，也为普通用户配置
if [[ -n "$SUDO_USER" ]]; then
    sudo -u $SUDO_USER mkdir -p /home/$SUDO_USER/.kube
    cp /etc/kubernetes/admin.conf /home/$SUDO_USER/.kube/config
    chown $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.kube/config
fi

print_info "安装网络插件 (Flannel)..."

# 安装网络插件 (Flannel)
install_flannel_network() {
    print_info "安装 Flannel 网络插件..."
    
    local flannel_yaml_url=""
    local flannel_image=""
    local flannel_cni_image=""
    
    if [ "$USE_CHINA_MIRROR" = true ]; then
        # 国内环境使用国内镜像和CDN
        flannel_yaml_url="https://cdn.jsdelivr.net/gh/flannel-io/flannel@v0.20.2/Documentation/kube-flannel.yml"
        flannel_image="${FLANNEL_IMAGE_REPO}/flannel:v0.20.2"
        flannel_cni_image="${FLANNEL_IMAGE_REPO}/flannel-cni-plugin:v1.1.2"
        
        print_info "使用国内镜像源安装 Flannel"
        print_info "Flannel 镜像: $flannel_image"
        print_info "CNI 插件镜像: $flannel_cni_image"
        
        # 预先拉取镜像
        docker pull $flannel_image || print_warning "Flannel 镜像拉取失败"
        docker pull $flannel_cni_image || print_warning "Flannel CNI 镜像拉取失败"
        
        # 下载并修改 YAML
        if curl -sSL "$flannel_yaml_url" | \
           sed "s|docker.io/flannel/flannel:.*|${flannel_image}|g" | \
           sed "s|docker.io/flannel/flannel-cni-plugin:.*|${flannel_cni_image}|g" | \
           kubectl apply -f -; then
            print_success "Flannel 网络插件安装成功 (国内源)"
            return 0
        fi
    else
        # 国外环境使用官方源
        flannel_yaml_url="https://raw.githubusercontent.com/flannel-io/flannel/v0.20.2/Documentation/kube-flannel.yml"
        
        print_info "使用官方源安装 Flannel"
        if kubectl apply -f "$flannel_yaml_url"; then
            print_success "Flannel 网络插件安装成功 (官方源)"
            return 0
        fi
    fi
    
    # 备用方案
    print_warning "主要安装方式失败，尝试备用方案..."
    local backup_urls=(
        "https://cdn.jsdelivr.net/gh/flannel-io/flannel@v0.20.2/Documentation/kube-flannel.yml"
        "https://raw.githubusercontent.com/flannel-io/flannel/v0.20.2/Documentation/kube-flannel.yml"
    )
    
    for url in "${backup_urls[@]}"; do
        print_info "尝试备用地址: $url"
        if kubectl apply -f "$url"; then
            print_success "Flannel 网络插件安装成功 (备用源)"
            return 0
        fi
    done
    
    print_error "Flannel 网络插件安装失败"
    return 1
}

install_flannel_network

print_info "配置单节点集群..."

# 允许单节点调度（移除污点）
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
kubectl taint nodes --all node-role.kubernetes.io/master- 2>/dev/null || true

print_info "等待所有 Pod 就绪..."

# 等待所有系统Pod就绪
timeout=300
elapsed=0
while [[ $elapsed -lt $timeout ]]; do
    if kubectl get pods -n kube-system --no-headers | grep -v Running | grep -v Completed | wc -l | grep -q "^0$"; then
        print_success "所有系统 Pod 已就绪"
        break
    fi
    print_info "等待 Pod 启动... ($elapsed/$timeout 秒)"
    sleep 10
    elapsed=$((elapsed + 10))
done

print_success "Kubernetes 集群初始化完成！"
print_info "使用以下命令检查集群状态:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo ""
print_info "加入工作节点的命令:"
kubeadm token create --print-join-command

# 清理临时文件
rm -f /tmp/kubeadm-config.yaml