我想确保在GKE中，GKE Node升级的时候，我的Deployment，也就是我对应的服务高可用。
我已经采用了如下方法
1 配置了反亲和,确保我的每一个Deployment replicas至少有2个Pod,且2个Pod必须落在不同的Node
2 配置了基于Deployment的strategy
比如
```yaml
strategy:
   rollingUpdate:
       maxsurge: 2
       maxUnavailable: 1
    type: RollingUpdate
```
3 目前没有配置PDB
我现在遇到这样一个问题
假如我运行中的这个Deployment有2个Pod，我们称为old 1 和old 2 
我现在看到old 1收到Stopping container的信号之后，我的集群开始创建一个new pod 1.各种原因这个new Pod 1比如 5分钟才准备就绪，可以接收流量
但是在这期间old 2也接收到了stopping container的信号，开始终止。同时触发创建一个new pod 2 
这样就遇到了一个问题。2个旧的Pod 都终止了的情况下，新的Pod还没有创建出来
就是说没有配置PDB的情况下 2个pod 在不同的node 再滚动更新的过程中启动起来稍慢 那么会存在第一个人pod 关闭之后新的pod 还没能提供服务 他又开始删除第二个pod 只是想确认PDB能解决这个问题

那么我想确认的知道PDB能否解决我的问题。
比如我配置如下
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
spec:
  minAvailable: 1  # 保证至少 1 个 Pod 始终可用
  selector:
    matchLabels:
      app: api-service
```
我看到一些资料，PDB终止宽限期最长为一小时？怎么理解这个宽限期？是针对一个Pod还是所有的pod。如果我环境配置了很多PDB资源？
https://cloud.google.com/kubernetes-engine/docs/how-to/upgrading-a-cluster?hl=zh-cn
注意：在自动或手动升级节点期间，PodDisruptionBudget (PDB) 和 Pod 终止宽限期最长为 1 小时。如果在节点上运行的 Pod 在 1 小时后无法被调度到新节点上，GKE 会无论如何启动升级。即使您将 PDB 配置为始终提供所有副本（通过将 maxUnavailable字段设置为 0 或 0%，或者将 minAvailable 字段设置为 100% 或副本数量），此行为也会适用。在所有这些情况下，GKE 都会在一小时后删除 Pod，以便进行节点删除。如果工作负载需要更灵活且能够安全终止，我们建议使用蓝绿升级，这样可以提供额外过渡时间设置，从而将 PDB 检查延长超过默认的 1 小时。如需详细了解在节点终止期间一般会发生什么情况，请参阅有关 Pod 的主题。
