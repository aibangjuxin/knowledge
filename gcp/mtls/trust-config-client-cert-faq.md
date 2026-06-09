# Trust Config + Client Cert 轮换 — FAQ

> 面向: **CAEP / 公共入口 mTLS** 场景下,运维/平台工程师在 GCP GLB + Certificate Manager + Trust Config 上做"用户换发 client cert"工作时的常见疑问。

## TL;DR

| 问题 | 答案 |
|---|---|
| 用户上传**新 client cert**到自己的客户端,旧的还能用吗? | ✅ **能**,只要 cert 还在有效期内、未被吊销、用同一对 Root + Intermediate 签发 |
| Trust Config 需要**同步更新**才能让新 cert 通过吗? | ❌ **不需要**。Trust Config 只看 CA 链,不看单个 client cert |
| 新旧 cert 会**同时能用**吗? | ✅ **会**,Trust Config 的链验证逻辑跟 OpenSSL `openssl verify -CAfile` 完全一致 — 信任锚不变,新 cert 就跟旧 cert 等价 |
| 那 Trust Config 在哪些情况下需要改? | ① 切换到**新的 Root CA** ② **轮换 Intermediate CA** ③ 吊销某个 CA ④ 加新用户的 CA(不同 Root) |

---

## 1. 问题原文

> "for CAEP public ingress mTLS client cert validation in Trust Config, user uploaded new client cert, when user use old and new client cert to trigger API call, both are worked, because only Root CA and Intermediate CA will be process the validation, and no change for the 2 parts for new and old client cert, right?"

**答案: 是的,完全正确。**

---

## 2. Trust Config 验证 client cert 的标准 5 步链验证

引用 `gcp/mtls/compare-ca-intermediate.md` 末尾的 5 步流程:

> 1. 它会检查该客户端证书的 Issuer。
> 2. 如果 Issuer 是 `DigiCert EV RSA CA G2` (即 `a.pem` 的 Subject),负载均衡器会查找 `a.pem` (Intermediate CA 证书) 来验证客户端证书的签名。
> 3. 然后,负载均衡器会检查 `a.pem` 的 Issuer,发现是 `D G R G2`。
> 4. 最后,负载均衡器会查找 `b.pem` (Root CA 证书 / Trust Anchor) 来验证 `a.pem` 的签名。
> 5. 由于 `b.pem` 在 Trust Anchor 中被明确信任,并且整个链条上的签名都有效,因此客户端证书被视为有效。

这 5 步就是 **OpenSSL / nginx / Envoy / Java JSSE / 任何 X.509 实现的**标准链验证算法,RFC 5280 §6。GCP 没发明新东西。

### Trust Config 在验证中**实际使用的 3 个字段**

```text
client cert  ──被验证──>  Intermediate CA  ──被验证──>  Root CA
   ↑                          ↑                              ↑
   │                          │                              │
   ├── Issuer (DN)            ├── Issuer (DN)                └── Trust Anchor
   ├── AKI (Authority         └── AKI (= 上面 Root 的 SKI)     (硬编码信任,
   │    Key ID =                                                    永远不变)
   │    Intermediate CA 的
   │    SKI)
   │
   └── 公钥(验证签名)
```

**换发新 client cert 时,这 3 个字段的变化:**

| 字段 | 旧 cert | 新 cert | Trust Config 需要变? |
|---|---|---|---|
| client cert 的 Subject (谁) | `CN=user01, ...` | `CN=user01, ...` | ❌ 不变 |
| client cert 的 Issuer (谁签的) | `CN=Intermediate CA` | `CN=Intermediate CA` | ❌ 不变 |
| client cert 的 AKI (指向 Intermediate) | = Intermediate 的 SKI | = Intermediate 的 SKI | ❌ 不变 |
| Intermediate CA 的 cert | 不变 | 不变 | ❌ 不变 |
| Root CA 的 cert | 不变 | 不变 | ❌ 不变 |
| **client cert 的 Serial** | `0x1A2B3C...` | `0x4D5E6F...` | ❌ **不影响验证** |
| **client cert 的公钥** | `A1B2...` | `C3D4...` | ❌ **不影响验证** |
| **client cert 的私钥签名** | 用户 A 旧私钥签 | 用户 A 新私钥签 | ❌ **不影响验证** |
| **client cert 的 Validity** | 旧时间段 | 新时间段 | ❌ **只要新 cert 没过期就行** |

**结论: Trust Config 在"用户换发 client cert"事件中,什么都不用做。**

---

## 3. Trust Config 真正需要更新的 4 种场景

| 场景 | Trust Config 动作 | 对**已签发** client cert 的影响 |
|---|---|---|
| ① 切到**新 Root CA** | 替换 Trust Anchor | 旧 cert 立即全失效;新 cert 才能过 |
| ② 轮换 **Intermediate CA** | 增/换 intermediateCas | 旧 cert 失效(只被旧 Intermediate 签);新 cert 走新 Intermediate |
| ③ **吊销**某个 CA | 移除(链断裂) | 该 CA 签的所有 cert 全失效 |
| ④ **新增**完全不相关的 CA(新用户/新业务线) | 追加 Trust Anchor / IntermediateCas | 旧 cert 不受影响;新 CA 签发的 cert 通过新链验证 |

**注意: 场景 ② "轮换 Intermediate CA" 是最常见的"批量 client cert 失效"诱因。** 实施时通常**双 Intermediate 并行**(旧 + 新),给客户端一个过渡期。

---

## 4. 隐式 cert 链深度限制

引用 `gcp/mtls/SSLVerifyDepth.md` 的关键发现:

> 目前 GCP 默认的 TLS 组件(如 GCLB 或 Gateway)**支持的最大证书链长度为约 10**,这个类似 ssl_verify_depth 的系统限制是硬编码的。

实际工程含义:

- **典型 3 层链** `Client → Intermediate → Root` = 深度 2 → 远在限制内
- **多 Intermediate 链** `Client → Sub-Intermediate → Intermediate → Root` = 深度 3 → 仍然 OK
- 如果你的 CA 体系层数 ≥ 5,就要小心了
- 限制是**硬编码的,目前没有 flag 调整** — 跟 nginx `ssl_verify_depth 2;` 不同

---

## 5. 额外考虑: Trust Config 的 allow/deny 列表(可选,不影响本题)

GCP Trust Config 还能附加**实例级别**的 allow/deny:

```bash
# 限制只允许某些 cert instance 通过
gcloud certificate-manager trust-configs update my-trust-config \
  --allowlisted-certificates=cert-id-1,cert-id-2
```

**这套机制跟"链验证"是两件事**:

| 机制 | 看什么 | 决定什么 |
|---|---|---|
| **链验证** (默认) | 证书能不能追到 Trust Anchor | 链上所有 cert **都能**通过(只要是同 CA 签的) |
| **allow/deny 列表** (可选) | 某个 cert 的 instance ID 是不是在白名单 | **只** 白名单里的 cert 能通过 |

**本题的"换发新 cert"是否受 allow/deny 影响**:

- 如果你**没启用** allow/deny 列表 → 跟原答案一致,**新旧 cert 都能过**
- 如果你**启用了** allow/deny 列表 → 必须**同时**把新 cert 的 instance ID 加进白名单,否则新 cert 过不去
- 后者的情况跟"换 Root/Intermediate CA"无关,纯粹是**应用层**策略

**生产环境 90% 不会启用** allow/deny(等于把 mTLS 退化成静态白名单,失去 CA 的扩展性)。

---

## 6. 工程化建议: Trust Config 的变更管理

引用 `gcp/mtls/onboarding-verify.md` 给出的多用户 Trust Config 最佳实践(已隐含支持"换 cert"场景):

### 6.1 必备 3 件套

1. **GCS Bucket 存 Trust Config snapshot** — 每次 update 前 export
2. **元数据 YAML 跟踪每个 cert 的 fingerprint + user_id + CN 映射** — 冲突检测基础
3. **每次 update 后自动 smoke test** — `curl --cert` 模拟真实调用

### 6.2 "换 cert" 时的健康检查

```bash
# 1. 导出当前 Trust Config 看 Root + Intermediate 是否仍在那里
gcloud certificate-manager trust-configs export my-trust-config \
  --location=global \
  --destination=/tmp/tc-current.yaml

grep -E "BEGIN CERT|END CERT" /tmp/tc-current.yaml | wc -l
# 应该 >= 2 (至少 1 个 Root + 1 个 Intermediate)

# 2. 用 旧 cert 模拟调用 (应该 200)
curl -v --cert old.crt --key old.key --cacert root.crt https://api.example.com/healthz

# 3. 用 新 cert 模拟调用 (应该 200)
curl -v --cert new.crt --key new.key --cacert root.crt https://api.example.com/healthz

# 4. 用一个**不存在的 CA 签的** cert 调 (应该 403/alert)
curl -v --cert untrusted.crt --key untrusted.key https://api.example.com/healthz
```

### 6.3 跨 cert 兼容性的硬指标

| 检查项 | 命令 | 期望 |
|---|---|---|
| 旧 cert 还在有效期内? | `openssl x509 -in old.crt -noout -dates` | `notAfter` > 今天 |
| 新 cert 还在有效期内? | `openssl x509 -in new.crt -noout -dates` | `notAfter` > 今天 |
| 旧 cert 没被吊销? | `openssl x509 -in old.crt -noout -text \| grep -i crl` | (看 OCSP URL 是否可达) |
| 新 cert 没被吊销? | 同上 | 同上 |
| 旧 cert 的 AKI = Intermediate 的 SKI? | `openssl x509 -in old.crt -noout -text \| grep -A1 "Authority Key"` | hex 必须匹配 |
| 新 cert 的 AKI = Intermediate 的 SKI? | 同上 | 同上 |

---

## 7. 总结

| 你的问题 | 答案 |
|---|---|
| "新旧 client cert 都能过 Trust Config 验证吗?" | ✅ **能** — 假设 4 个条件:① 同一对 Root + Intermediate ② 都未过期 ③ 都未吊销 ④ 没启用 cert-instance 白名单 |
| "Trust Config 需要为这件事改吗?" | ❌ **不需要** — Trust Config 只管 CA,不管 client cert |
| "这种信任链验证是 GCP 特有的吗?" | ❌ **不是** — 这是 X.509 标准链验证 (RFC 5280 §6),所有 TLS 实现的通用行为 |
| "什么时候 Trust Config 才必须改?" | 切 Root / 换 Intermediate / 吊销 CA / 加新 CA 这 4 种场景 |

---

## 8. 参考你 `gcp/mtls/` 目录下的相关文档

| 文档 | 用处 |
|---|---|
| `Glb-Client-Authentication.md` | Trust Config + Server TLS Policy 的官方配置流程 + Mermaid 流程图 |
| `compare-ca-intermediate.md` | Root vs Intermediate 的 issuer/subject 关系解读,5 步链验证 |
| `SSLVerifyDepth.md` | GCP 隐式 cert 链深度限制(~10 层) |
| `onboarding-verify.md` | 多用户 Trust Config 的版本控制 / rollback / fingerprint 校验 |
| `gcp-certificate-manager.md` | Trust Config + Trust Store + Server TLS Policy 的 gcloud 实操命令 |
| `glb-verify-curl.md` | 用 curl 模拟 mTLS 调用做端到端验证 |

## 9. 外部参考

- **RFC 5280 §6 — Certification Path Validation**: https://datatracker.ietf.org/doc/html/rfc5280#section-6
- **RFC 5246 §7.4.6 — TLS 1.2 Client Certificate Validation**: https://datatracker.ietf.org/doc/html/rfc5246#section-7.4.6
- **GCP Trust Config Overview**: https://cloud.google.com/certificate-manager/docs/trust-config
- **GCP Server TLS Policy**: https://cloud.google.com/load-balancing/docs/server-tls-policies
