# Gateway-namespace 跨 namespace 网络策略配置分析

假如说在我的环境里面有空 Kong gateway或者 GKE的 gateway两种 gateway的形式存在。

- the flow is 
konggateway Namespace==> Runtime-namespace ==> Pod
gkegateway Namespace==> Runtime-namespace ==> Pod

我有这样一种场景可能我这个 runtime-namespace是公用的 ，也就是说我既能接受Kong gateway的流量也能接收 GKE gateway的流量。
那么对于我的默认的GKE里面的 namespace之间都是默认是 Deny All的 NetworkPolicy。

那么我需要配置NetworkPolicy 最佳的实验方案应该是什么样或者说基于这一块有什么安全性的考核和考量?
- 几个背景 
  - 我的环境是在 Routes-based 模式下
  - GKE Gateway API 不能通过 podSelector 限制 Route，只能基于 Namespace
  - 其实我核心考虑的是因为我公用了runtime-namespace，我担心这个 runtime-namespace下面这些 pod之间的安全性。和一些合规的控制。 

首先满足安全合规的情况下帮我制定网络规则的建议比如说我的deployment应该打什么样的标签 Pod应该做对应选择标签来区分我这种应用场景 ?