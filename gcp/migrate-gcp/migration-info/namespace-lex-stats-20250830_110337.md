# Kubernetes命名空间统计报告

**命名空间:** lex  
**集群:** default  
**生成时间:** Sat Aug 30 11:03:38 CST 2025  

---

## 1. 容器镜像统计

### 镜像使用次数统计
| 使用次数 | 镜像 |
|---------|------|
| 4 | rancher/klipper-lb:v0.2.0 |
| 2 | nginx:latest |
| 1 | redis:7-alpine |
| 1 | prom/node-exporter:latest |
| 1 | busybox:latest |

### 镜像仓库分布
| 使用次数 | 仓库 |
|---------|------|
| 1 | redis:7-alpine |
| 1 | rancher |
| 1 | prom |
| 1 | nginx:latest |
| 1 | busybox:latest |

**唯一镜像总数:**        5

## 2. 健康探针统计

### Liveness 探针类型分布
| 使用次数 | 探针类型 |
|---------|----------|
| 3 | httpGet |
| 1 | tcpSocket |

### Readiness 探针类型分布
| 使用次数 | 探针类型 |
|---------|----------|
| 3 | httpGet |
| 1 | exec |

### Startup 探针类型分布
| 使用次数 | 探针类型 |
|---------|----------|
| 2 | httpGet |

## 3. Service Account统计

### Service Account使用频率
| 使用次数 | Service Account |
|---------|-----------------|
| 3 | default |
| 1 | web-service-account |

## 4. 容器端口统计

### 端口使用分布
| 使用次数 | 端口 | 协议 |
|---------|------|------|
| 2 | 9100 | TCP |
| 2 | 80 | TCP |
| 2 | 6379 | TCP |
| 2 | 443 | TCP |

## 5. Service类型统计

### Service类型分布
| 使用次数 | Service类型 |
|---------|-------------|
| 1 | NodePort |
| 1 | LoadBalancer |
| 1 | ClusterIP |

### Service端口分布
| 使用次数 | 端口 |
|---------|------|
| 3 | 80 |
| 1 | 9100 |
| 1 | 6379 |
| 1 | 443 |

## 6. 资源需求统计

### CPU 请求分布
| 使用次数 | CPU 请求 |
|---------|------------|
| 3 | 100m |
| 1 | 50m |
| 1 | 25m |

### 内存 请求分布
| 使用次数 | 内存 请求 |
|---------|------------|
| 3 | 64Mi |
| 1 | 32Mi |
| 1 | 128Mi |

### CPU 限制分布
| 使用次数 | CPU 限制 |
|---------|------------|
| 3 | 200m |
| 1 | 50m |
| 1 | 100m |

### 内存 限制分布
| 使用次数 | 内存 限制 |
|---------|------------|
| 3 | 128Mi |
| 1 | 64Mi |
| 1 | 256Mi |

## 7. 存储卷类型统计

### 卷类型分布
| 使用次数 | 卷类型 |
|---------|--------|
| 2 | persistentVolumeClaim |
| 2 | hostPath |
| 2 | emptyDir |
| 2 | configMap |

## 8. 迁移关键信息

### 节点选择器和亲和性配置
| 工作负载 | 节点选择器 | 亲和性配置 |
|---------|-----------|------------|
| Deployment/complex-web-app | {"kubernetes.io/os":"linux","node-type":"web-tier"} | 是 |

### 容忍度配置
| 工作负载 | 容忍度数量 |
|---------|-----------|
| Deployment/complex-web-app | 1 |
| DaemonSet/svclb-complex-web-app-service | 3 |

### 持久卷声明 (PVC)
| PVC名称 | 存储类 | 访问模式 | 大小 |
|---------|--------|----------|------|
| static-content-pvc | standard | ReadWriteOnce | 5Gi |
| redis-data-pvc | fast-ssd | ReadWriteOnce | 2Gi |

### 安全上下文配置
| 工作负载 | 特权模式 | 用户ID | 组ID |
|---------|----------|--------|------|
| Deployment/nginx-deployment | false | 未设置 | 未设置 |
| Deployment/busybox-deployment | false | 未设置 | 未设置 |
| Deployment/complex-web-app | false | 1000 | 未设置 |
| DaemonSet/svclb-complex-web-app-service | false | 未设置 | 未设置 |

## 9. 迁移检查清单

### 必须检查的项目:

- [ ] **容器镜像访问权限** - 确保目标集群能够拉取所有镜像
- [ ] **存储类兼容性** - 验证目标集群是否有相同的存储类
- [ ] **网络策略** - 检查目标集群的网络策略配置
- [ ] **Service Account权限** - 确保RBAC配置在目标集群中正确
- [ ] **节点标签和污点** - 验证节点选择器和容忍度配置
- [ ] **外部依赖** - 检查是否有外部服务依赖需要重新配置
- [ ] **ConfigMap和Secret** - 确保配置数据正确迁移
- [ ] **持久化数据** - 规划PV数据迁移策略
- [ ] **Ingress控制器** - 确保目标集群有兼容的Ingress控制器
- [ ] **监控和日志** - 重新配置监控和日志收集

### 还需要检查的资源类型:

- **NetworkPolicies** - 网络安全策略
- **PodDisruptionBudgets** - Pod中断预算
- **ResourceQuotas** - 资源配额
- **LimitRanges** - 资源限制范围
- **CRDs和Custom Resources** - 自定义资源定义
- **Webhooks** - Admission webhooks和其他webhook配置

