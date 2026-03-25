# PSC Firewall Summary

## 1. Goal and Constraints

这份总结文档的目标不是重复 [psc-firewall.md](/Users/lex/git/knowledge/gcp/cross-project/psc-firewall.md) 和 [psc-firewall-qwen.md](/Users/lex/git/knowledge/gcp/cross-project/psc-firewall-qwen.md) 的内容，而是从架构实施角度回答一个更关键的问题：

> 如果我想把这两份文档里的判断真正落地成一个“正确、可验证、可长期维护”的 Cross Project PSC 防火墙逻辑，我应该怎么做？

这次我们只聚焦一件事：

- **PSC Cross Project 通信时，防火墙最佳实践是什么**

---

## 2. 先说结论

如果要把这件事做对，最稳的 V1 逻辑是：

### 推荐 V1

1. **不要把 PSC 本身当成防火墙对象**
   - 不要围着 `PSC endpoint`、`service attachment`、`LB frontend VIP` 去设计规则
2. **先对 Producer service 做类型分类**
   - `Passthrough`
   - `Proxy / Envoy`
3. **再按 backend 实际看到的 source range 设计 Producer ingress 防火墙**
   - `Passthrough` → 放通 `PSC NAT subnet CIDR`
   - `Proxy / Envoy` → 放通 `proxy-only subnet CIDR`
4. **始终单独考虑 health check**
   - 不要把健康检查流量和业务流量混成一类
5. **Consumer 侧只做最小必要 egress 检查**
   - workload 能到 PSC endpoint VIP
   - DNS / Response Policy 正确
   - GKE `NetworkPolicy` / mesh egress 没挡住

### 一句话总结

**最佳实践不是“给 PSC 开洞”，而是“先识别 producer service 类型，再只对 backend 的真实来源地址做最小放通”。**

---

## 3. 对两份文档的架构收敛

这两份文档整体方向是一致的，核心结论可以收敛成下面这几个点：

### 已确认正确的逻辑

1. `PSC endpoint -> service attachment -> LB frontend` 不是你重点开 firewall 的地方
2. 真正的重点是 Producer backend ingress
3. Producer backend 看到的 source 不一定是：
   - Consumer workload IP
   - PSC endpoint IP
   - LB frontend VIP
4. `Passthrough` 和 `Proxy / Envoy` 的 source range 设计不同
5. health check source 必须单独考虑

### 需要你在项目里继续确认的点

1. 你的每一个 Producer service 到底属于哪一类
2. 你的 GKE / Gateway controller 是否自动创建了所需 firewall rule
3. Shared VPC / hierarchical firewall policy / org policy 是否覆盖了你以为已经开放的规则

### 我对两份文档的判断

- [psc-firewall-qwen.md](/Users/lex/git/knowledge/gcp/cross-project/psc-firewall-qwen.md) 更接近“整理过的最终版”
- [psc-firewall.md](/Users/lex/git/knowledge/gcp/cross-project/psc-firewall.md) 更像“探索版 + 你的现场备注”

所以最佳做法不是二选一，而是：

**用 `psc-firewall-qwen.md` 作为主框架，用 `psc-firewall.md` 中你已经补充的 Shared VPC / GKE Gateway 实际关注点做项目化收敛。**

---

## 4. Recommended Architecture Logic (V1)

## 4.1 先分两大类

不要一开始就写防火墙规则。  
先把 Producer service 统一分成两类：

### 类别 A：Passthrough

典型包括：

- Internal passthrough Network Load Balancer
- Internal protocol forwarding
- Port mapping service

设计逻辑：

- Producer backend 放通 `PSC NAT subnet CIDR`
- 如有 health check，再额外放通 health check ranges

### 类别 B：Proxy / Envoy

典型包括：

- Regional internal Application Load Balancer
- Cross-region internal Application Load Balancer
- Regional internal proxy Network Load Balancer
- Secure Web Proxy
- `GKE Gateway (gke-l7-rilb)`

设计逻辑：

- Producer backend 放通 `proxy-only subnet CIDR`
- 如有 health check，再额外放通 health check ranges

---

## 4.2 对你当前场景的直接结论

如果你的 Producer 侧是：

- `GKE internal Gateway`
- `gatewayClassName: gke-l7-rilb`

那它应该直接归类为：

**Proxy / Envoy 类**

所以你的默认防火墙思路应当是：

- 不优先看 `PSC NAT subnet`
- 优先看 `proxy-only subnet CIDR`
- 再补 `health check ranges`

这是你当前 Cross Project PSC + GKE Gateway 场景下最重要的判断。

---

## 5. Best Practice

如果从生产最佳实践角度来做，我建议按下面这套逻辑落地。

## 5.1 最佳实践 1：把“类型识别”变成标准动作

每次新接一个 PSC producer service，不要先手写 firewall rule。  
先做一个统一识别：

1. 看 `service attachment`
2. 看 `targetService`
3. 看 `forwarding rule`
4. 看它是否走 `target proxy / URL map / proxy-only subnet`
5. 决定它属于 `Passthrough` 还是 `Proxy / Envoy`

这一步应该成为你的标准流程，而不是靠经验猜。

## 5.2 最佳实践 2：业务流量和健康检查分开设计

不要把下面这两类流量写成一条混合规则：

- backend 业务流量
- health check 探测流量

推荐分开：

- Rule A: `PSC NAT subnet` 或 `proxy-only subnet` -> app ports
- Rule B: `health check ranges` -> health check port

这样后期排障会容易很多。

## 5.3 最佳实践 3：Consumer 侧只做最小必要放通

Consumer 侧通常不需要复杂化。

只确认：

- workload 能出站访问 PSC endpoint VIP:port
- DNS 能正确解析到 PSC endpoint
- 没有 K8s/mesh 的 egress deny

不要在 Consumer 侧为了 PSC 额外造一套复杂 firewall 体系。

## 5.4 最佳实践 4：优先看“真实 source”，不要看 frontend IP

这是整个问题最容易出错的地方。

你永远应该问：

> backend 实际看到的来源是谁？

而不是：

> 客户端访问的 VIP 是谁？

Frontend VIP 只是入口地址，不等于 backend firewall 应该允许的 source。

## 5.5 最佳实践 5：对 GKE Gateway 场景，先验证自动规则，再补手工规则

对 `gke-l7-rilb` 这种场景，不建议一开始就全部手工管理 firewall。

更合理的顺序是：

1. 先看 controller 自动规则是否已创建
2. 再看是否被 Shared VPC / 权限 / hierarchical policy 影响
3. 最后才补手工规则

这样可以避免你自己和 controller 相互打架。

---

## 6. Implementation Steps

下面是一套更适合你当前项目的实施顺序。

## Step 1: 建一份 Producer service inventory

给每个暴露出去的 Producer service 建一个清单，至少包括：

- service attachment name
- targetService
- forwarding rule
- LB type
- backend service
- backend type
  - GCE VM
  - NEG
  - GKE Gateway / Service
- business ports
- health check ports
- expected source range

这张表是后面所有防火墙治理的基础。

## Step 2: 给每个 Producer service 打标签

建议只打两个标签之一：

- `passthrough`
- `proxy-envoy`

不要再用更模糊的描述。

## Step 3: 为每个 service 输出一套标准规则

### 对 `passthrough`

- 业务规则：
  - source = `PSC NAT subnet CIDR`
  - ports = app ports
- 健康检查规则：
  - source = health check ranges
  - ports = health check ports

### 对 `proxy-envoy`

- 业务规则：
  - source = `proxy-only subnet CIDR`
  - ports = app ports
- 健康检查规则：
  - source = health check ranges
  - ports = health check ports

## Step 4: Consumer 侧只做准入验证

核对：

- PSC endpoint VIP 可达
- DNS / Response Policy 正确
- GKE `NetworkPolicy` / sidecar egress 不拦截

## Step 5: 做一轮端到端验证

建议至少验证：

1. DNS 解析正确
2. TCP connect 到 PSC endpoint 成功
3. 应用请求成功
4. backend 日志中实际看到的 source 与预期一致
5. health check 正常

如果第 4 步和你的预期不一致，说明类型判断错了，或者规则没真正生效。

---

## 7. Validation and Rollback

## Validation

建议每次至少查这几类对象：

```bash
gcloud compute service-attachments describe SERVICE_ATTACHMENT --region REGION
gcloud compute forwarding-rules describe FORWARDING_RULE --region REGION
gcloud compute firewall-rules list
gcloud compute networks subnets list --filter='purpose ~ "MANAGED_PROXY|INTERNAL_HTTPS_LOAD_BALANCER"'
```

如果是 GKE Gateway，再加：

```bash
kubectl get gateway -A
kubectl describe gateway <gateway> -n <namespace>
```

## Rollback

回滚策略建议很简单：

1. 先新增 allow 规则，不先删旧规则
2. 验证新规则生效
3. 再清理旧规则

不要在 PSC 场景里一次性“替换规则”，因为排障时你会很难知道断在哪一层。

---

## 8. Reliability and Cost Optimizations

从长期运维角度，建议你不要把 PSC firewall 管理做成“每次临时记忆型排障”。

更好的做法是：

### 结构性改进

- 把 Producer service inventory 文档化
- 把 `passthrough` / `proxy-envoy` 分类固化下来
- 把 firewall rule 模板参数化
- 把 Shared VPC / proxy-only subnet / PSC NAT subnet 的 CIDR 统一登记

### 长期优化

- 用 Terraform / IaC 管理 firewall rules
- 把 service attachment 到 backend 的关系自动化导出
- 将 GKE Gateway / internal ALB 的自动规则与手工规则边界写清楚

这会比长期靠人肉判断“这个服务是不是应该放通 PSC NAT subnet”可靠得多。

---

## 9. Handoff Checklist

- 每个 Producer service 已确认分类：`passthrough` 或 `proxy-envoy`
- 每个 service 的 source range 已确认
- health check rule 与业务流量 rule 已拆开
- Consumer egress / DNS / K8s policy 已核对
- Shared VPC / hierarchical firewall policy 已核对
- GKE Gateway 场景已确认 controller 自动规则是否存在

---

## 10. Final Recommendation

如果你想把这两份文档里的内容真正落地成一个正确逻辑，我建议你采用下面这套统一标准：

### 统一标准

1. **先分类**
   - `passthrough`
   - `proxy-envoy`
2. **再设计 Producer backend firewall**
   - `passthrough` → `PSC NAT subnet`
   - `proxy-envoy` → `proxy-only subnet`
3. **health check 永远单独考虑**
4. **Consumer 侧只做最小必要校验**
5. **把这套逻辑标准化成 inventory + checklist，而不是每次临时判断**

### 对你当前场景的最佳实践

对于 `Cross Project PSC + GKE Gateway (gke-l7-rilb)`：

- 按 **Proxy / Envoy** 类处理
- 优先核对 **proxy-only subnet CIDR**
- 再核对 **health check ranges**
- 最后再看 Consumer 侧 egress / DNS / K8s policy

---

## 11. One-line Conclusion

**Cross Project PSC 防火墙的最佳实践，不是围着 PSC 组件逐个开洞，而是先把 Producer service 标准化分类为 `passthrough` 或 `proxy-envoy`，再只对 backend 的真实来源地址做最小、独立、可验证的放通。**
