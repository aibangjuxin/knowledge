# GKE Nginx 出口代理（Egress Proxy）清单

对应文档：[`../docs/nginx-l4-user-case.md`](../docs/nginx-l4-user-case.md)

> **场景**：集群内的其他 Pod 通过这个 Nginx 反向代理访问外部网络。
> Nginx 收到请求后做一轮"流转"（身份透传 / 凭证注入 / 限流 / 审计），
> 再把请求转给"另外一个服务"，由那个服务带领请求最终出网。

## 拓扑

```text
┌──────────────────────────────────────────────────────────────────┐
│  namespace: app-workload                                        │
│                                                                  │
│  业务 Pod ──HTTP──▶ nginx-egress-proxy:8082                     │
│  (NetworkPolicy: 只允许访问代理 + DNS，其余出站全断)              │
└───────────────────────────┬──────────────────────────────────────┘
                            │  ClusterIP（Pod 间，不经公网）
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│  namespace: platform-net                                         │
│                                                                  │
│  nginx-egress-proxy ──HTTP──▶ egress-partner-client:8080        │
│  （不允许直接出网）                 │                            │
│                                    ▼                            │
│                              外部 API（由 Cloud NAT 出网）         │
└──────────────────────────────────────────────────────────────────┘
```

| 文件 | 作用 |
|---|---|
| `00-namespace.yaml` | `platform-net`（代理组件）+ `app-workload`（示例业务 ns） |
| `10-configmap-nginx.yaml` | nginx 主配置：L7 出口代理（8082）+ L4 stream（8080）+ 健康检查（8081） |
| `20-deployment-nginx.yaml` | nginx Deployment：3 副本、非 root、只读根文件系统、滚动更新、跨可用区打散 |
| `25-partner-service.yaml` | "中间服务"示例：持有第三方凭证并最终出网（Python 标准库最小实现） |
| `30-service.yaml` | nginx Service：**ClusterIP**，暴露 8082 / 8080 / 8081 |
| `40-networkpolicy.yaml` | 五条策略：两个 ns 各一条 default-deny + 只放行代理 + 代理只放行中间服务 + 中间服务才可出网 |
| `50-pdb-hpa.yaml` | PDB（minAvailable 2）+ HPA（CPU 60%，3~10 副本） |
| `examples/secret.example.yaml` | 凭证模板（生产请用 External Secrets 同步） |
| `examples/test-client.yaml` | 验证 Pod：经代理访问 + 直连被拦截 |

## 前置条件

1. **集群启用 NetworkPolicy（Dataplane V2）**

   ```bash
   gcloud container clusters describe CLUSTER --zone ZONE \
     --format="value(networkConfig.datapathProvider)"   # 期望 NETWORK_POLICY
   ```

   > 启用后 container-native load balancing 会关闭，受影响的对外 Service
   > 需加 `cloud.google.com/neg: '{"ingress": true}'` 注解。

2. **集群有出网能力**（私有节点池必须配 Cloud NAT）

   ```bash
   gcloud compute routers create egress-router \
     --network=VPC_NAME --region=REGION
   gcloud compute routers nats create egress-nat \
     --router=egress-router --region=REGION \
     --auto-allocate-nat-external-ips \
     --nat-all-subnet-ip-ranges \
     --enable-endpoint-independent-mapping
   ```

   > ⚠️ `--nat-all-subnet-ip-ranges` 必须包含 **Pod 次级 IP 范围**，
   > 否则 Pod 出网会失败。自定义范围时用
   > `--nat-custom-subnet-ip-ranges=SUBNET:ALL`。
   > `--enable-endpoint-independent-mapping` 与动态端口分配 / NAT Rules 互斥。

3. **镜像里带 stream 动态模块**

   ```bash
   kubectl run tmp-check --rm -it --restart=Never --image=nginxinc/nginx-unprivileged:stable-alpine \
     -- ls -l /etc/nginx/modules/ngx_stream_module.so
   ```

   若不存在，删掉 `nginx.conf` 第一行的 `load_module` 和整个 `stream` 块（只用模式 B）。

## 部署

```bash
cd webservice/nginx/gke-egress-proxy

# 1. 命名空间
kubectl apply -f 00-namespace.yaml

# 2. 凭证（先把 REPLACE_ 换成真实值；生产用 External Secrets）
kubectl apply -f examples/secret.example.yaml

# 3. 配置 + 工作负载
kubectl apply -f 10-configmap-nginx.yaml
kubectl apply -f 20-deployment-nginx.yaml
kubectl apply -f 25-partner-service.yaml
kubectl apply -f 30-service.yaml

# 4. 网络策略（先在预发验证，再上生产）
kubectl apply -f 40-networkpolicy.yaml

# 5. 可用性与弹性
kubectl apply -f 50-pdb-hpa.yaml
```

> 改 `nginx.conf` 用 `subPath` 挂载，**不会热更新**，需要滚动重启：
>
> ```bash
> kubectl rollout restart deployment/nginx-egress-proxy -n platform-net
> ```

## 验证

```bash
# ① 代理是否全部就绪
kubectl rollout status deploy/nginx-egress-proxy -n platform-net
kubectl get pods -n platform-net -o wide

# ② 配置语法检查（进容器验）
kubectl exec -n platform-net deploy/nginx-egress-proxy -c nginx -- nginx -t

# ③ 跑验证 Pod：经代理访问 + 直连被拦截
kubectl apply -f examples/test-client.yaml
kubectl logs -n app-workload egress-test-client

# ④ 确认出口 IP 是 Cloud NAT 的静态 IP，而不是 Pod IP
#    注意：必须在【允许出网的命名空间】跑。default ns 没有策略所以可以；
#    platform-net 有 default-deny，临时 Pod 反而会被拦住。
kubectl run egress-ip-check -n default --rm -it --restart=Never --image=curlimages/curl:8.11.1 -- \
  sh -c 'curl -s https://api.ipify.org; echo'

# ⑤ 确认审计日志（访问日志走 stdout）
kubectl logs -n platform-net deploy/nginx-egress-proxy -c nginx --tail=50 | grep "/proxy"
```

期望结果：

| 检查项 | 期望 |
|---|---|
| ② `nginx -t` | `syntax is ok` / `test is successful` |
| ③ 经代理访问 | 换成真实 `TARGET_URL` 后返回 200 + 上游内容；仍是占位域名时返回 502 属预期 |
| ③ 直连外网 | 超时 / Connection refused（不是正常返回） |
| ④ 出口 IP | 等于你预留的 Cloud NAT 静态 IP |

## 回滚

```bash
# 最快：撤掉网络策略，恢复直连（代价是"只能走代理"的管控失效）
kubectl delete -f 40-networkpolicy.yaml

# 回滚配置与工作负载
kubectl rollout undo deployment/nginx-egress-proxy -n platform-net
kubectl rollout undo deployment/egress-partner-client -n platform-net

# 彻底下线
kubectl delete -f 50-pdb-hpa.yaml -f 30-service.yaml -f 25-partner-service.yaml \
  -f 20-deployment-nginx.yaml -f 10-configmap-nginx.yaml
```

## 需要改成你自己业务的地方

| 位置 | 改什么 |
|---|---|
| `10-configmap-nginx.yaml` → `set $target_host` | 中间服务的 Service 名 |
| `10-configmap-nginx.yaml` → `map $ssl_preread_server_name` | 你的外部 API 域名（SNI → upstream） |
| `25-partner-service.yaml` → `TARGET_URL` | 第三方 API 的真实地址 |
| `25-partner-service.yaml` → `server.py` | 换成你真实的中间服务实现 |
| `40-networkpolicy.yaml` → `namespace: app-workload` | 换成你真实的业务命名空间 |
| `40-networkpolicy.yaml` → `except` 列表 | 如果外部 API 在对等 VPC 私有网段，要把该网段从 `except` 里去掉 |
| `40-networkpolicy.yaml` → `0.0.0.0/0` | 可加 `ports` 收紧到 443 |

## 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| nginx CrashLoopBackOff，日志报 `unknown directive "stream"` | 镜像没带 stream 模块 | 删 `load_module` 行与 `stream` 块；或换 `nginx:alpine` |
| nginx 启动失败，提示无法写临时目录 | 只读根文件系统 | 确认 `/tmp` 挂了 emptyDir（清单里已配） |
| 502，日志 `no resolver defined` | 变量型 upstream 缺 resolver | 确认 `resolver` 指向 `kube-dns.kube-system.svc.cluster.local` |
| 间歇性 502 | default-deny 把 DNS 掐了 | 放行 kube-dns 的 53 端口（TCP + UDP） |
| 调用方超时但代理正常 | 目标域名解析慢 | 调大 `resolver_timeout`；确认 Pod 能解析外网域名 |
| 出口 IP 不是预期值 | 走了默认 NAT 网关 | 用预留静态 IP（`MANUAL_ONLY`）并检查 NAT 配置 |
| 直连外网没被拦 | 集群未启用 Dataplane V2 | 确认 `networkPolicyConfig.enabled=true` |

## 相关文档

- [`../docs/nginx-l4-user-case.md`](../docs/nginx-l4-user-case.md) — 完整方案、选型、原理、验证、排障
- [`../docs/nginx-l4-stream-explorer.md`](../docs/nginx-l4-stream-explorer.md) — L4 / `ssl_preread` 能力全景
