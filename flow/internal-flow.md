- [L7-L4-request](./L7-L4-request.md)









流量路径:
用户请求 -> A(7层Nginx) -> B(4层Nginx) -> C(Kong DP) -> D(GKE RT)
流量分层处理：
A组件(7层Nginx)负责API路由和HTTP头部处理
B组件(4层Nginx)负责跨网络的TCP转发
Kong DP处理具体的API网关功能
GKE RT作为最终的服务运行时
我现在需要考虑一个高可用的情况
比如GKE 的deployment RT是2个 Pod .对于这个Deployment
我的我有个SVC提供对应的服务 .GKE 在升级的时候会逐步做替换升级 我配置了Deployment的affinity我会确认2个Pod在不同的Node

```yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1  # 允许最多 1 个 Pod 不可用
      maxSurge: 2  # 允许额外创建 2 个 Pod
```
- 也有readinessProbe的配置
```yaml
readinessProbe:
  failureThreshold: 3
  httpGet:
    path: /health
    port: 8080
    scheme: HTTPS
  periodSeconds: 20
  successThreshold: 1
  timeoutSeconds: 3
```