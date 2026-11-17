# optional/ — 应用层 HTTPS(可选,默认不 apply)

## 这个目录解决什么问题

主 PoC(00~08)里,**东西向加密由 ambient 的 ztunnel 自动完成(mesh mTLS)**,
应用层跑的是明文 HTTP —— 这是**推荐路径**,零证书运维。

本目录是**备选路径**:当合规明确要求「**应用自己终结 TLS**」时才启用。

## ⚠️ 启用前必须知道的代价

| 维度 | 主 PoC(mesh mTLS) | 本目录(应用层 HTTPS) |
|---|---|---|
| 证书运维 | ✅ 零(istio 自动签发/轮转) | ❌ 自己管签发、轮转、过期告警 |
| waypoint L7 版本路由 | ✅ 生效 | ❌ **失效**(ztunnel passthrough,waypoint 解不开明文) |
| waypoint L7 AuthZ | ✅ 生效 | ❌ 失效(只剩 L4 级身份判定) |
| 调用方改动 | ❌ 不用改 | ✅ 要挂 CA、改 base URL 为 https |
| 版本路由怎么保住 | HTTPRoute header 匹配 | **退化为应用内自己判断版本** |

> 一句话:**启用应用层 TLS = 用「waypoint 的 L7 能力」换「应用自己管证书」。**
> 如果 L7 版本路由是刚需,不要走这条路。

## 启用顺序

1. 确认集群已装 cert-manager(含 ca-injector):

```bash
kubectl get pods -n cert-manager
```

2. 先在**测试集群**做 go/no-go 验证:

```bash
kubectl apply -f app-tls-cert-manager.yaml
kubectl wait --for=condition=Ready certificate/lex-api2-tls -n ba000000-lex-intra-call --timeout=120s
# 核对 SAN
kubectl get secret lex-api2-tls -n ba000000-lex-intra-call -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -ext subjectAltName
```

3. 改被调方:nginx 改 `listen 8443 ssl`,挂载 `lex-api2-tls`,Service 端口改 443 → 8443,
   `appProtocol` 改成 `https`。
4. 改调用方:`BASE_URL` 改成 `https://...`,并挂载 CA(`SSL_CERT_FILE` / `javax.net.ssl.trustStore`)。
5. **重新验证版本路由是否还生效** —— 这是 go/no-go 的判定点:

```bash
bash ../09-verify.sh
```

   若 §6 的 `x-api-version: 2.0.0` 不再返回 v2 → 说明 L7 已失效,按上面的表做决策。

## 不建议的做法

- ❌ cert-manager 的 `google-cas-issuer` / `gcp-public-certificates-issuer`:
  处于 **maintenance mode**(只收 bug 修复),内部场景建议自建 CA。
- ❌ GKE 内建 Certificate Manager:适合对外域名,不适合 `.svc.cluster.local` 内部名。
- ❌ 自签证书 SAN 只写 ClusterIP / Pod IP:ClusterIP 会漂移,必然过期。
