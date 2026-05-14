# Kubernetes (k8s) 知识库

## 目录描述
本目录包含Kubernetes容器编排技术相关的知识、实践经验、解决方案和工具脚本。

## 目录结构
```
k8s/
├── busybox/                    # BusyBox相关工具和配置
├── config/                     # 配置文件
├── custom-liveness/            # 自定义存活探针相关
├── debug-pod/                  # Pod调试相关工具和方法
├── docs/                       # Markdown文档
├── hpa/                        # 水平Pod自动扩缩容相关
├── images/                     # 镜像相关资源
├── k8s-scale/                  # K8s扩缩容相关
├── labels/                     # 标签相关配置
├── lib/                        # K8s相关库文件
├── migrate/                    # 迁移相关工具和说明
├── Mytools/                    # 自定义工具集
├── networkpolicy/              # 网络策略相关
├── pic/                        # 相关图片资源
├── qnap-k8s/                   # QNAP K8s相关配置
├── scripts/                    # Shell脚本
├── src/                        # 源代码文件
├── text/                       # 文本文件
├── vpa/                        # 垂直Pod自动扩缩容相关
├── yaml/                       # YAML配置文件
└── README.md                   # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `pod-lifecycle.md`: Pod生命周期详解
- `container-pod.md`: 容器与Pod关系
- `deployment2.md`, `detail-deployment.md`: Deployment详解
- `replicaset.md`: ReplicaSet相关

### yaml/ - YAML配置文件
- 包含各种Kubernetes资源定义文件

### 自动扩缩容
- `hpa.md`, `hpa-poc-cpu-memory.md`: 水平Pod自动扩缩容 (在docs/目录)
- `vpa/`: 垂直Pod自动扩缩容相关内容
- `pdb.md`, `pdb-core.md`: Pod中断预算 (在docs/目录)

### 网络
- `networkpolicy.md`, `base-networkpolicy.md`: 网络策略 (在docs/目录)
- `ingress.md`: Ingress配置 (在docs/目录)
- `endpoint.md`: 端点相关 (在docs/目录)

### 配置管理
- `configmap.md`, `cm.md`: ConfigMap相关 (在docs/目录)
- `secret-enhance.md`, `k8s-export-secret.md`: Secret相关 (在docs/目录)

### 探针
- `liveness.md`, `readiness.md`: 存活和就绪探针 (在docs/目录)
- `liveless-simple.md`: 简单存活探针示例 (在docs/目录)

## 快速检索
- Pod管理: 查看 `docs/` 目录中的 `pod-*.md` 文件
- 自动扩缩容: 查看 `docs/` 目录中的 `hpa*.md` 文件及 `hpa/` 目录
- 网络策略: 查看 `docs/` 目录中的 `networkpolicy*.md` 文件及 `networkpolicy/` 目录
- 部署策略: 查看 `docs/` 目录中的 `deployment*.md` 和 `strategy.md`
- 调试工具: 查看 `debug-pod/` 目录及 `docs/` 目录中的 `kubectl-event.md`
- 配置文件: 查看 `config/` 和 `yaml/` 目录
- 脚本文件: 查看 `scripts/` 目录
- 文本文件: 查看 `text/` 目录