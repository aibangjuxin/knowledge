# QNAP Kubernetes 部署脚本

专为 QNAP NAS 设计的 Kubernetes 集群部署脚本，解决了 QNAP 系统特有的问题和国内网络环境的镜像拉取问题。

## 🏠 QNAP 系统特点

QNAP NAS 运行基于 Linux 的 QTS 系统，具有以下特点：
- 没有标准的包管理器（如 apt-get、yum）
- 使用 `opkg` 或需要手动安装二进制文件
- 通常通过 Container Station 应用提供 Docker 支持
- 系统资源相对有限

## 🚀 快速开始

### 前置要求
- QNAP NAS 设备（支持 x86_64 或 ARM 架构）
- QTS 4.4+ 系统版本
- 至少 4GB RAM 和 20GB 可用存储空间
- SSH 访问权限

### 1. 准备 QNAP 系统
```bash
# SSH 登录到 QNAP
ssh admin@your-qnap-ip

# 切换到 root 用户
sudo -i
```

### 2. 安装依赖
```bash
# 下载脚本到 QNAP
cd /share/homes/admin  # 或其他持久化目录

# 运行依赖安装脚本 (会自动检测网络环境)
./install-k8s-deps.sh

# 脚本会提示选择镜像源：
# 1) 自动检测 (推荐)
# 2) 强制使用国内镜像源 
# 3) 使用官方源
```

### 3. 初始化集群
```bash
# 加载环境变量
source /opt/k8s/k8s-env.sh

# 初始化 Kubernetes 集群 (同样会检测网络环境)
./init-k8s.sh

# 脚本会提示选择镜像源：
# 1) 自动检测 (推荐)
# 2) 国内镜像源 (阿里云、DaoCloud)
# 3) 官方镜像源 (registry.k8s.io)
```

## 📋 脚本说明

### install-k8s-deps.sh (QNAP 专用版本)
- 检测 QNAP 系统类型和架构
- 手动下载并安装 Docker 二进制文件（如果 Container Station 不可用）
- 下载 Kubernetes 工具二进制文件（kubeadm, kubelet, kubectl）
- 配置 QNAP 系统参数和内核模块
- 创建适合 QNAP 的服务启动脚本
- 使用国内镜像源加速下载

### init-k8s.sh (QNAP 优化版本)
- 检查 QNAP 环境和 Docker 服务状态
- 从国内镜像源拉取 Kubernetes 镜像
- 创建适合 QNAP 的 kubeadm 配置（使用 cgroupfs 而非 systemd）
- 初始化 Kubernetes 控制平面
- 安装 Flannel 网络插件（使用国内镜像）
- 配置单节点集群（移除污点）

## 🔧 QNAP 专用优化

### 解决的 QNAP 特有问题
1. **无包管理器**：直接下载二进制文件安装
2. **Container Station 集成**：优先使用 QNAP 官方 Docker 支持
3. **系统限制**：适配 QNAP 的 cgroup 和内核配置
4. **存储路径**：使用 `/share` 目录存储持久化数据
5. **镜像拉取超时**：使用阿里云和 daocloud 镜像源

### QNAP 技术特点
- 自动检测 QNAP 系统架构（x86_64/ARM）
- 兼容 Container Station 和手动 Docker 安装
- 使用 cgroupfs 而非 systemd（适合 QNAP 系统）
- 创建 QNAP 专用的服务启动脚本
- 完整的错误处理和兼容性检查
- 支持单节点集群部署（适合 NAS 环境）

### Container Station 集成
如果你的 QNAP 已安装 Container Station：
1. Docker 将自动可用
2. 脚本会检测并使用现有 Docker 服务
3. 无需手动安装 Docker 二进制文件

## 🌐 智能镜像源选择

脚本会自动检测网络环境并选择最适合的镜像源：

### 国内环境镜像源
**Kubernetes 工具下载**
- 主源：`https://kubernetes.oss-cn-hangzhou.aliyuncs.com`
- 备源：`https://dl.k8s.io` (官方源)

**Docker 下载**
- 主源：`https://mirrors.aliyun.com/docker-ce`
- 备源：`https://download.docker.com` (官方源)

**Kubernetes 镜像**
- 主源：`registry.aliyuncs.com/google_containers`
- 备源：`daocloud.io/google_containers`
- 额外源：`registry.cn-hangzhou.aliyuncs.com/google_containers`

**网络插件镜像**
- Flannel：`registry.cn-hangzhou.aliyuncs.com/google_containers`

**Docker 镜像加速**
- 阿里云：`https://registry.cn-hangzhou.aliyuncs.com`
- 中科大：`https://docker.mirrors.ustc.edu.cn`
- 网易：`https://hub-mirror.c.163.com`
- 百度：`https://mirror.baidubce.com`

### 国外环境镜像源
**官方源**
- Kubernetes：`https://dl.k8s.io`
- Docker：`https://download.docker.com`
- 镜像：`registry.k8s.io`

### 手动选择
脚本运行时会提供选择界面：
```
请选择下载源：
1) 自动检测 (当前: 国内源)
2) 强制使用国内镜像源 (推荐国内用户)
3) 使用官方源 (国外用户)
```

## 📊 QNAP 系统要求

### 支持的 QNAP 型号
- **x86_64 架构**：TS-x51, TS-x53, TS-x73, TS-x80, TS-x82 等
- **ARM 架构**：TS-x28, TS-x31, TS-x32, TS-x35 等（性能有限）

### 最低配置
- **CPU**: 2 核心 Intel/AMD x86_64 或 ARM Cortex-A15+
- **内存**: 4GB RAM（QNAP 系统本身占用较多内存）
- **存储**: 20GB 可用空间（建议使用 SSD）
- **系统**: QTS 4.4+ 或 QuTS hero

### 推荐配置
- **CPU**: 4 核心 Intel x86_64
- **内存**: 8GB+ RAM
- **存储**: 50GB+ 可用空间
- **网络**: 千兆网络连接
- **Container Station**: 已安装（推荐）

### 性能注意事项
- ARM 架构 QNAP 性能有限，仅适合轻量级工作负载
- 建议在 x86_64 架构的中高端 QNAP 上部署
- 确保有足够的内存，避免 OOM 问题

## 🔍 验证安装

### 检查集群状态
```bash
kubectl get nodes
kubectl get pods -A
```

### 预期输出
```bash
# 节点状态
NAME     STATUS   ROLES           AGE   VERSION
master   Ready    control-plane   5m    v1.26.0

# Pod 状态（所有 Pod 应为 Running 状态）
NAMESPACE     NAME                             READY   STATUS    RESTARTS
kube-system   coredns-xxx                      1/1     Running   0
kube-system   etcd-master                      1/1     Running   0
kube-system   kube-apiserver-master            1/1     Running   0
kube-system   kube-controller-manager-master   1/1     Running   0
kube-system   kube-flannel-ds-xxx              1/1     Running   0
kube-system   kube-proxy-xxx                   1/1     Running   0
kube-system   kube-scheduler-master            1/1     Running   0
```

## 🛠️ QNAP 故障排除

### QNAP 特有问题

1. **Container Station 未安装**
   ```bash
   # 检查 Container Station 状态
   qpkg_service status container-station
   
   # 如果未安装，请在 App Center 中安装 Container Station
   # 或使用脚本手动安装 Docker
   ```

2. **Docker 服务未启动**
   ```bash
   # 检查 Docker 状态
   docker info
   
   # 手动启动 Docker（如果使用脚本安装）
   /opt/docker/start-docker.sh
   
   # 或重启 Container Station
   qpkg_service restart container-station
   ```

3. **权限问题**
   ```bash
   # 确保以 root 用户运行
   sudo -i
   
   # 检查文件权限
   ls -la /opt/k8s/bin/
   chmod +x /opt/k8s/bin/*
   ```

4. **内存不足**
   ```bash
   # 检查内存使用
   free -h
   
   # 检查 QNAP 系统进程
   top
   
   # 如果内存不足，考虑：
   # - 关闭不必要的 QNAP 应用
   # - 增加虚拟内存（不推荐）
   # - 升级 RAM
   ```

5. **网络问题**
   ```bash
   # 检查网络接口
   ip addr show
   
   # 检查路由
   ip route show
   
   # 测试网络连通性
   ping 8.8.8.8
   curl -I https://registry.aliyuncs.com
   ```

### 常见 Kubernetes 问题

1. **镜像拉取失败**
   ```bash
   # 手动拉取镜像
   docker pull registry.aliyuncs.com/google_containers/kube-apiserver:v1.26.0
   
   # 检查镜像加速器配置
   cat /etc/docker/daemon.json
   ```

2. **Pod 启动失败**
   ```bash
   # 查看 Pod 日志
   kubectl logs -n kube-system <pod-name>
   
   # 查看 Pod 详情
   kubectl describe pod -n kube-system <pod-name>
   
   # 检查节点状态
   kubectl describe node
   ```

3. **kubelet 问题**
   ```bash
   # QNAP 上 kubelet 通常作为进程运行，不是 systemd 服务
   ps aux | grep kubelet
   
   # 查看 kubelet 日志
   tail -f /var/log/kubelet.log
   
   # 手动重启 kubelet
   pkill kubelet
   /opt/k8s/start-kubelet.sh
   ```

### 重置集群
```bash
# 完全重置集群
kubeadm reset -f
rm -rf ~/.kube/
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
```

## 📝 QNAP 注意事项

### 重要提醒
1. **权限要求**：必须以 root 用户运行所有脚本
2. **持久化存储**：脚本安装在 `/opt` 目录，重启后仍然有效
3. **Container Station**：推荐先安装 Container Station 再运行脚本
4. **网络要求**：确保 QNAP 能访问国内镜像源
5. **资源监控**：定期检查内存和存储使用情况

### QNAP 系统限制
1. **systemd 支持有限**：使用自定义启动脚本而非 systemd 服务
2. **cgroup 配置**：使用 cgroupfs 而非 systemd cgroup driver
3. **存储路径**：数据存储在 `/share` 目录以确保持久化
4. **防火墙**：QNAP 防火墙可能需要配置 Kubernetes 端口
5. **自动启动**：需要手动配置开机自启动脚本

### 性能优化建议
1. **关闭不必要的 QNAP 应用**以释放内存
2. **使用 SSD 存储**提高 I/O 性能
3. **配置适当的资源限制**避免影响 NAS 基本功能
4. **定期清理容器镜像**释放存储空间
5. **监控系统资源**使用避免过载

### 备份和恢复
```bash
# 备份 Kubernetes 配置
tar -czf k8s-backup.tar.gz /etc/kubernetes /opt/k8s ~/.kube

# 恢复配置（如果需要）
tar -xzf k8s-backup.tar.gz -C /
```

## 🔗 相关链接

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [kubeadm 安装指南](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Flannel 网络插件](https://github.com/flannel-io/flannel)
- [阿里云容器镜像服务](https://cr.console.aliyun.com/)

## 📄 许可证

MIT License