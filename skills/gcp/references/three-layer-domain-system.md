# 三层域名体系与证书匹配

> 2026-05-29 确认的准确信息，用于统一文档中的域名命名。

---

## 三层域名体系

| 层级 | 域名示例 | 性质 | 管理方 | A 记录指向 | 证书 |
|------|---------|------|--------|-----------|------|
| **L1** | `*.team.appdev.aibang` | 外部域名 | Cloud DNS（团队） | GLB 公网 IP（静态） | 公共 CA / 私有 CA（手动） |
| **L2** | `*.aliyun.cloud.region.local` | 内部自建域名（Cloud DNS Zone） | Cloud DNS（平台团队） | GLB 公网 IP 或 Internal LB IP（静态） | 私有 CA，SDS 内存级分发 |
| **L3** | `*.svc.cluster.local` | K8s 内置域名 | Kubernetes CoreDNS | ClusterIP / Pod IP（动态） | K8s CA / Mesh CA 自动签发 |

---

## 关键区分

### L2 vs L3 的本质区别

```
L2: *.aliyun.cloud.region.local
  - Cloud DNS 中的一个 Zone（平台团队自建）
  - 不是 K8s 内置的
  - 解析需要 CoreDNS forwarding → Cloud DNS（多一跳）
  - 用途：GCLB/Nginx TLS 终止的 SNI 识别

L3: *.svc.cluster.local
  - Kubernetes 内置的
  - CoreDNS kubernetes plugin 直接权威解析（不走 forward）
  - 用途：Pod ↔ Pod 之间的服务发现和 mTLS 通信
```

**注意**：`*.aliyun.cloud.region.local` 和 `*.svc.cluster.local` 是两个完全不同的命名空间，历史上曾被混用为同一个概念（`*.aliyun.cloud.region.local`），现已严格区分。

---

## 证书与域名匹配

```
*.team.appdev.aibang          L1 外部域名    → 公共 CA/私有 CA（手动，K8s Secret 落盘）
dev-abjx.aliyun.cloud.region.*   L2 内部自建    → 私有 CA，Istiod SDS 自动签发（不落盘）
*.aliyun.cloud.region.local       L2 内部自建    → 同上，用于 GCLB/Nginx TLS 终止
*.svc.cluster.local           L3 K8s 内置    → K8s CA/Mesh CA，Istiod SDS 自动签发（Pod 间 mTLS）
```

---

## 常见错误

1. **Kong upstream 使用 L1/L2 域名** → 流量绕行公网，mTLS 中断
2. **Cloud DNS Zone A 记录指向 Pod IP** → Pod 重建后记录失效
3. **Pod 内代码使用 L2 域名调用内部服务** → 多一跳 DNS 解析延迟

---

## 关联文档

- 三层域名架构完整文档：`/Users/lex/git/knowledge/linux/dns/docs/three-layer-domain-architecture.md`
- DNS 架构原始文档（已修正）：`/Users/lex/git/knowledge/linux/dns/docs/external-internal-dns-separation.md`