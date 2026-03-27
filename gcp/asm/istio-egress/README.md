# istioyaml

这个目录保留的是一套 **relay 型上游代理假设** 下的 Istio egress 示例清单。

它 **不适用于当前实际的 `Squid explicit forward proxy:3128` 场景**，原因是：

- 这些 YAML 把 `3128` 当作普通上游端口来路由
- 但 `Squid` 默认需要显式代理语义
- 对 `HTTPS` 通常需要 `HTTP CONNECT`
- 对 `HTTP` 通常需要标准 forward proxy request

所以这套清单可以用于：

- 复盘控制面拆解
- 讨论 `ServiceEntry / Gateway / VirtualService / DestinationRule / AuthorizationPolicy / NetworkPolicy` 各自职责
- 对比 relay 型出口和 Squid explicit proxy 的差异

这套清单不应该直接用于：

- 当前 Squid 出口的生产 apply

如果后续要把这条链路真正落到 Squid，通常需要额外补：

- `EnvoyFilter` 或自定义 egress gateway 配置
- 让 egress gateway 能对 Squid 发 `CONNECT`
- 必要时重新设计 `SaaS2` 的 mTLS origination 链路
