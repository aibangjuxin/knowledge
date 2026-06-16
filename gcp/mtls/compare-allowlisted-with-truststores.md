# compare-allowlisted-with-truststores — `allowlistedCertificates` 与 `trustStores` 对比

> **勘误说明 (2026-06-16)**: 本文档初版基于推断,部分事实描述不准确,已通过 GCP 官方 API + 实证修正。详细勘误前后对比见各章节内联 `> 勘误:` 块 + 文末 §6 勘误附录。
>
> **核心结论不变**:`allowlistedCertificates` 严格性确实高于 `trustStores`,纯白名单模式是满足需求的最严方案。**但"自建到期监控"的建议**由"不确定"升级为"已实证 + GCP API 明确不含 notAfter 检查"。

---

## 0. TL;DR

**问题**: `allowlistedCertificates` 看起来校验是更严格了,那这个有没有缺点?纯 `allowlistedCertificates`(不配 `trustStores`)是不是就能满足需求?

**直接答案**: **对,纯 `allowlistedCertificates`(不配 `trustStores`)就能满足你的需求**。**前提是**:

1. 客户端数量 ≤ **50** 个(GCP hard limit,每 TrustConfig 最多 50 个 allowlisted cert)
2. 接受"自建 cert 到期监控"(`allowlistedCertificates` **不**主动拒绝过期 cert,**已实证**)
3. 证书轮转走"先 add 新 cert → 再 remove 旧 cert"的两步流程(避免轮转窗口期客户端被全部拒绝)

> **勘误**: 本文档初版说"纯 `allowlistedCertificates` 就能满足你的需求,前提是客户端规模可控、轮转流程规范、过期监控自建"。这是**结论正确**,但**前提 3** 的"过期监控自建"是**已实证的必要项**(不是 optional 风险点)— 详见 §3 §6。

---

## 1. 为什么 `allowlistedCertificates` 严格性更高

```
Nginx 原来做的事:
  CA 链验证 + CN 等于特定值  →  只让"特定身份"的客户端通过

纯 allowlistedCertificates 做的事:
  cert 完整内容(PEM 全文,含公钥 + 序列号 + 签名)精确匹配列表  →  只让"特定证书"的客户端通过

后者比前者更严格:
  CN 是可被多张证书共享的字符串
  cert 全量匹配等价于"这张证书,世界上独一无二的这一张"(隐式 fingerprint pinning)
```

不配置 `trustStores` 意味着:**没有任何 CA 链能让客户端绕过白名单**,唯一的入场方式就是 cert PEM 完整内容在列表里。这是最干净、最收紧的实现。

---

## 2. 纯白名单模式的三个前提

### 2.1 客户端数量必须 ≤ 50

```bash
# 检查当前/计划的客户端证书数量
gcloud certificate-manager trust-configs describe ajbx-mtls-trust-config-global \
  --project=$PROJECT --location=global \
  --format="value(allowlistedCertificates.len())"
```

- 超过 50 张证书时,`allowlistedCertificates` 字段会**拒绝写入**
- 此时必须引入 `trustStores` 或用 HTTP 层 Kong DP fingerprint 校验(见 `tenant-mtls-cn.md` §4.3 路径 C)

### 2.2 证书轮转必须走"先 add 新 cert,再 remove 旧 cert"的两步流程

没有 `trustStores` 做兜底,**轮转期间唯一的"安全网"就是列表本身**。如果直接覆盖列表(先删旧再加新),轮转窗口期内旧客户端会被直接拒绝在 TLS 层(无 HTTP 层重试机会)。

```bash
# ✅ 安全的轮转流程
# 1. 先 add 新 cert (旧 cert 仍在)
gcloud certificate-manager trust-configs update ajbx-mtls-trust-config-global \
  --project=$PROJECT --location=global \
  --add-allowlisted-certificates=$CERT_DIR/client-v2.pem

# 2. 验证新 cert 生效
curl --cert $CERT_DIR/client-v2.pem --key $CERT_DIR/client-v2.key https://...
# 期望 HTTP 200

# 3. 再 clear + add (移除旧 cert)
# ⚠️ 注意: TrustConfig 不支持单 cert delete,只能整体 replace
gcloud certificate-manager trust-configs update ajbx-mtls-trust-config-global \
  --project=$PROJECT --location=global \
  --clear-allowlisted-certificates \
  --add-allowlisted-certificates=$CERT_DIR/client-v2.pem
```

### 2.3 证书过期不会被 GCP 自动感知和拦截 — **已实证**

> **勘误(2026-06-16)**: 初版文档用"取决于 GCP 的具体实现"措辞留了口子,语气暗示"可能不查"。**实证结果**:
>
> - **GCP 官方 API 描述** (`certificatemanager.googleapis.com/$discovery/rest?version=v1`) 原话:
>   > "A certificate matching an allowlisted certificate is always considered valid **as long as the certificate is parseable, proof of private key possession is established, and constraints on the certificate's SAN field are met.**"
>   3 个 valid 条件:**不含 notAfter / 有效期检查**。
>
> - **本次实证 (2026-06-16)**: 把一张已过期 3 年的 cert (notAfter=2023-03-01) 加到 allowlist 里,跑 curl → **`HTTP 200 OK`**,**被接受**。详细步骤见 `test-report-allowlisted-notAfter-check/summary.md`。
>
> **结论**: 纯白名单模式下,**必须自建 cert 到期监控**。这不是"风险提示",是"必要项"。建议在 cert 即将到期前 (e.g., 提前 14 天) 主动 rotate 到新 cert。

#### 对比: `trustStores` 模式会拒绝过期 cert

| 模式 | expired cert 行为 | 实证 |
|---|---|---|
| 纯 `allowlistedCertificates`(无 trustStores) | **接受**(GCP 不查 notAfter) | ✅ 本次实证 `HTTP 200` |
| `trustStores` 模式(有 trustStores,无 allowlist) | 拒绝(chain 验证因 expired 失败) | ✅ `test-report/final-summary.md` Scenario 5 验证 `HTTP 000 (SSL reject)` |
| OR 模式(both 都有,cert **不在** allowlist) | 拒绝(走 chain 验证因 expired 失败) | ✅ `test-report-allowlisted/5-expired` 验证 `HTTP 000` — cert 不在 allowlist → 走 chain 验证 → expired 拒绝 |

> **注**: 第三行 (OR 模式 + cert 不在 allowlist) 走 trustStores chain 验证,所以**也会**因 expired 拒绝。这跟 §2.3 的第一行(纯 allowlist 模式)行为**不同** — 关键区分是 cert 是否在 allowlist 里。

---

## 3. 缺点清单

> **勘误说明 (2026-06-16)**:
> - 缺点六原写"是否仍被接受取决于 GCP 内部实现" — **已实证为会接受**,措辞修正
> - 缺点四"每次 import 是全量替换" — **不准确**: 默认 `--add-allowlisted-certificates` 是 append;只有 `--clear-allowlisted-certificates` + `--add-allowlisted-certificates` 才是 replace

### 缺点一:可扩展性硬上限

```
50 张证书的硬顶 = 50 个客户端身份的硬顶
```

这不是"当前够用就行"的问题,而是**架构选型的天花板**。一旦业务方增多到 50+,你面临的不是"加一行配置",而是要重新引入 `trustStores` 或迁移到 Kong DP fingerprint 校验(路径 C),整个信任模型从"白名单"切回"CA + 补充白名单",安全语义发生质变,等于推倒重做。

### 缺点二:运维耦合 — 证书生命周期绑死在你的基础设施配置上

```
有 CA 链时:
  客户端在自己的 PKI 体系里申请、轮转、吊销证书
  → 你完全不参与,只要 CA 不变

纯白名单时:
  客户端每次换证书 → 必须找你 → 你手动改 Trust Config → import
  → 你成为每一次证书生命周期事件的中间人
```

如果客户端是第三方合作方,这意味着**他们的证书轮转节奏被你的发布窗口卡住**,而不是他们自主决定。这是从"信任一个组织"退化成"信任一份清单",运维负担从 PKI 系统转移到了人。

### 缺点三:没有撤销机制 (CRL/OCSP)

```
trustStores 模式下:
  Chain 验证本身也不天然包含 CRL/OCSP 检查
  ⚠️ 这一点我需要诚实说明:截至目前 GCP Certificate Manager
  的 Trust Config 并不提供客户端证书的实时吊销检查能力

纯白名单模式下:
  唯一的"撤销"手段就是把 cert 从列表里删除并重新 import
  → 撤销延迟 = 你发现异常的时间 + 编辑 YAML 时间 + import 生效时间(1-2分钟)
```

两种模式在吊销能力上**其实是同等弱的**(`trustStores` 也不做实时 CRL/OCSP),但纯白名单模式下,"撤销"这件事**完全依赖人工动作**,没有自动化兜底路径。

### 缺点四:列表编辑的不可见性(出错的修复成本高)

> **勘误(2026-06-16)**: 初版写"每次 import 是全量替换,不是增量 patch" — **不准确**。实际:
> - `--add-allowlisted-certificates=...` 是 **append**(增量添加)
> - `--remove-allowlisted-certificates=...` 是 remove(增量删除,实际 GCP 不支持该 flag,需用 `--clear-allowlisted-certificates` + `--add-allowlisted-certificates` 整体 replace)
> - `--clear-allowlisted-certificates` + `--add-allowlisted-certificates=...` 才是 **replace**
>
> Lex 实际脚本 (`lex-poc-create-consumer-resource-global.sh` §7a) 用的就是 `--add-allowlisted-certificates`,**不是**全量 replace。

实际风险点是:

```
50 张证书的列表是一个整体资源
  → 整体 replace 时漏掉一行 / 复制粘贴出错
  → 不是"新客户端连不上",而是"老客户端突然全部被拒绝"
```

GCP TrustConfig update 没有 dry-run,没有 diff 预览,出错后果是**生产环境 TLS 握手层面的连接拒绝**。排查成本比 HTTP 403 高得多(客户端只会看到 SSL handshake failure,信息量远少于 HTTP 状态码)。

### 缺点五:可读性差,缺乏元数据

```
列表里存的是:
  -----BEGIN CERTIFICATE-----
  MIIDXTCCAkWgAwIBAgIJAJC1...(几十行 base64)
  -----END CERTIFICATE-----

而不是:
  team-a-client (CN=team-a.client.domain.com, expires=2027-03-01)
```

要知道"这一段 PEM 对应哪个客户端、什么时候过期",**必须解码才能看到**,没有原生的标签/备注机制。你需要自己在 Git 仓库里维护一份"PEM ↔ 客户端 ↔ 到期日"的映射表,否则半年后没人记得哪一段对应谁。

### 缺点六:过期 cert 不会自动拒绝(已实证)

> **勘误(2026-06-16)**: 初版用"取决于 GCP 内部实现"措辞,语气不明确。**已实证: GCP 不会主动拒绝过期 cert**。

```
trustStores 模式: chain 验证天然检查 notAfter → expired cert 被 reject
纯白名单模式:    GCP 官方 API 描述不含 notAfter 检查 → expired cert 仍被接受
                 (已实证: 过期 3 年的 cert 在 allowlist 里 → HTTP 200)
```

**业务后果**: 必须**自建到期监控**(e.g., 提前 14 天告警 → 主动 rotate),不能依赖 GCP 平台层面给你兜底。

### 缺点七:无法表达"部分信任"

```
CA 模式可以说:"这个子部门的所有未来证书都信任"
纯白名单只能说:"这 50 张,一张都不能多"
```

如果团队内部还有动态的临时测试客户端、CI/CD 用的短期证书,这种场景在纯白名单模式下**每次都要走人工 onboarding**,无法委托给下级 PKI 自动签发。

---

## 4. 总结对照表

| 维度 | `trustStores` 模式 | 纯 `allowlistedCertificates` |
|------|-----------------|---------------------------|
| 安全粒度 | 较粗(CA 颁发即信任) | 极细(逐证书 PEM 匹配) |
| 扩展上限 | 无上限(只要 CA 信任) | 硬顶 **50** 个 cert/TrustConfig |
| 客户端轮转自主性 | 高(客户端自行处理) | 低(强耦合到你的配置) |
| 列表编辑方式 | append(新 CA 加进去即可) | 默认 append,但单 cert delete 需整体 replace |
| 撤销能力 | 无(无 CRL/OCSP) | 无(只能从列表移除,延迟 1-2min) |
| 过期 cert 处理 | ✅ 自动拒绝(chain 验证失败) | ❌ **不拒绝**(已实证) — **必须自建监控** |
| 可读性 / 可追溯性 | 一般(CA 名字 + PEM) | 差(纯 PEM,需自建映射表) |
| 适合场景 | 客户端多、动态、自主轮转 | 客户端少(≤50)、固定、强管控、能自建监控 |

**结论**: 纯白名单是"更严更窄"的方案,适合你现在客户端数量可控、轮转节奏可预期的阶段。但它把过去由 PKI 承担的灵活性,换成了人工维护的确定性 — 这笔交易值不值,取决于你未来 1-2 年内:
1. 客户端规模是否会突破 50
2. 是否愿意承担证书生命周期管理的运维角色(尤其是**自建到期监控**这个必要项)

---

## 5. 最终配置形态(纯白名单模式)

```yaml
# trust-config-final.yaml
name: ajbx-mtls-trust-config-global
description: "纯白名单模式 - 无 CA 链兜底,仅信任列表中的具体证书"
allowlistedCertificates:
- pemCertificate: |
    -----BEGIN CERTIFICATE-----
    <client-cert-1>
    -----END CERTIFICATE-----
- pemCertificate: |
    -----BEGIN CERTIFICATE-----
    <client-cert-2>
    -----END CERTIFICATE-----
# 无 trustStores 字段 → 纯白名单模式
```

切换到纯白名单模式的命令(`clear-trust-store` + 保留 allowlist):

```bash
gcloud certificate-manager trust-configs update ajbx-mtls-trust-config-global \
  --project=$PROJECT --location=global \
  --clear-trust-store \
  --add-allowlisted-certificates=$CERT_DIR/client-spiffe.pem
```

> **注**: 当前 Lex 部署用的是 **OR 模式**(`trustStores` + `allowlistedCertificates` 同时存在),见 `tenant-mtls-allowlistedCertificates.md` §1.3 OR 关系图。切换到纯白名单是后续可选动作,见 `tenant-mtls-allowlistedCertificates.md` §9 Follow-up 0。

**结论**:**去掉 `trustStores`,只留 `allowlistedCertificates`**,是满足你需求的最简方案,前提是:
- 客户端规模可控(≤50)
- 轮转流程规范(先 add 新 cert,再 remove 旧 cert)
- **过期监控自建(必要项,非可选项 — 已实证)**

---

## 6. 勘误附录 (2026-06-16 集中记录)

| # | 错误/不准确 | 修正 | 证据 |
|---|---|---|---|
| 1 | §3 注意点 3 "是否检查 cert 的 notAfter 字段取决于 GCP 的具体实现" — 语气不明确 | GCP **不**主动检查 notAfter,**会接受过期 cert**(已实证) | GCP 官方 API 描述不含 notAfter;`test-report-allowlisted-notAfter-check/summary.md` 本次实证 expired cert → HTTP 200 |
| 2 | §5 总结表 "误操作影响范围 = 全量 import" | 默认 `--add-allowlisted-certificates` 是 append,**不是**全量 replace;只有 `--clear-allowlisted-certificates` + `--add-allowlisted-certificates` 才是 replace | `lex-poc-create-consumer-resource-global.sh` §7a 用的是 add;GCP gcloud flag 实测 |
| 3 | §5 总结表 "过期 cert 处理" 行标为"无法判断" / "需要自建" 但没明确写"会不会拒绝" | 纯白名单模式**会接受**过期 cert(不会拒绝);`trustStores` 模式**会拒绝** | GCP API 描述 + 本次实证 + `test-report/5-expired` |
| 4 | "直接答案"段说"纯 allowlistedCertificates 就能满足你的需求" — 描述完整但缺 OR 关系警示 | 当前 Lex 部署是 **OR 模式**,需要 `--clear-trust-store` 才能切到严格"纯 allowlist" | `test-report-allowlisted/8-chain-valid-not-allowlisted` 验证 OR 关系 |
| 5 | 缺点三"trustStores 模式 chain 验证本身也不天然包含 CRL/OCSP 检查" — 措辞模糊 | 准确说:**两种模式都不做实时 CRL/OCSP**,GCP Certificate Manager 整体不提供 client cert 吊销检查能力 | GCP TrustConfig + AllowlistedCertificate API 字段描述里都没提 CRL/OCSP |

**未变动项**:
- 核心结论"纯 allowlistedCertificates 就能满足你的需求" — **结论仍然正确**
- "客户端 ≤ 50 上限" — 不变(GCP hard limit)
- "运维耦合" / "可读性差" / "无撤销机制" 等结构性问题 — 不变
- "自建到期监控"建议 — **升级为已实证的"必要项"**(不是 optional 风险点)

---

## 7. 相关文档

- **`tenant-mtls-allowlistedCertificates.md`** — TrustConfig `allowlistedCertificates` 精钉实施记录(含 OR 关系图、轮转流程、cleanup 脚本)
- **`tenant-mtls-cn.md`** — CN 校验探索 + fingerprint 方案分析(为什么 fingerprint 是 CN 的严格超集)
- **`tenant-mtls-setup-global.md`** — mTLS 整体 runbook
- **`test-report-allowlisted/`** — 8 scenario e2e 验证 artifacts(含 OR 关系验证)
- **`test-report-allowlisted-notAfter-check/summary.md`** — **本次新实证**: allowlistedCertificates 不查 notAfter 的对照实验记录
- **`scripts/lex-poc-create-consumer-resource-global.sh`** — 自动化脚本,含 `--allowlisted-cert` 和 `--no-allowlist` flag
- GCP 官方 API reference: `https://certificatemanager.googleapis.com/$discovery/rest?version=v1` (`TrustConfig.allowlistedCertificates` 字段)
- GCP 官方 blog: [Frontend mTLS for External HTTPS LB](https://cloud.google.com/blog/products/networking/frontend-mtls-support-for-external-https-load-balancing)

---

## 8. MiMo 独立验证 (2026-06-16)

> 以下是对本文档的独立交叉验证,逐条核实结论、实证数据和引用来源。

### 验证结论:文档内容正确,可以作为决策依据

### 逐项验证结果

| # | 验证项 | 原文描述 | 实际验证 | 结论 |
|---|---|---|---|---|
| 1 | `allowlistedCertificates` 严格性 > `trustStores` | PEM 全文匹配 ≈ fingerprint pinning;不配 trustStores 时无 CA 链可绕过 | GCP API 确认 valid 条件为 parseable + private key possession + SAN constraints,无 CA chain 依赖 | ✅ |
| 2 | 客户端 ≤ 50 硬上限 | GCP hard limit,每 TrustConfig 最多 50 个 allowlisted cert | 多个 GCP 文档和 API 描述均确认 | ✅ |
| 3 | 纯白名单模式 expired cert 不被拒绝 | 过期 3 年的 cert 在 allowlist → HTTP 200 | `test-report-allowlisted-notAfter-check/summary.md` 确认:expired cert (notAfter=2023-03-01) → HTTP 200 OK | ✅ |
| 4 | GCP API 不含 notAfter 检查 | valid 条件 3 个,不含有效期 | API 原文: "as long as the certificate is parseable, proof of private key possession is established, and constraints on the certificate's SAN field are met" | ✅ |
| 5 | trustStores 模式 expired cert 被拒绝 | `test-report/final-summary.md` Scenario 5 → HTTP 000 | 文件确认:curl exit code 16, SSL/TCP error | ✅ |
| 6 | OR 模式 expired cert 不在 allowlist → 拒绝 | `test-report-allowlisted/5-expired` → HTTP 000 | 文件确认:expired cert 不在 allowlist → 走 chain 验证 → expired → 拒绝 | ✅ |
| 7 | 脚本用 `--add-allowlisted-certificates`(append) | `lex-poc-create-consumer-resource-global.sh` §7a | 第 336-340 行确认:`--add-allowlisted-certificates="$ALLOWLISTED_CERT"` | ✅ |
| 8 | OR 关系验证 | `test-report-allowlisted/8-chain-valid-not-allowlisted` → 200 (OR fall through) | 文件确认:client.pem 不在 allowlist,chain 验证通过,HTTP 200 OK | ✅ |
| 9 | Kong DP fingerprint 作为扩展路径 | `tenant-mtls-cn.md` §4.3 路径 C | 文件确认:fingerprint 是 CN 的严格超集 | ✅ |
| 10 | 两个模式都不做 CRL/OCSP | GCP Certificate Manager 整体不提供 | TrustConfig + AllowlistedCertificate API 字段描述均未提及 CRL/OCSP | ✅ |

### 发现并修正的小问题

1. **引用路径偏差**:原 §2.3 对比表引用 `test-report/5-expired` 目录,实际该目录不存在为独立子目录。已修正为引用 `test-report/final-summary.md` Scenario 5。
2. **表格描述矛盾**:原 §2.3 对比表第三行写"OR 模式(client 在 allowlist) → 接受",但实测是"cert 不在 allowlist → 拒绝"。已修正描述为"cert **不在** allowlist → 拒绝(走 chain 验证因 expired 失败)"。
