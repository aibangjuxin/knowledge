# Certificate Truststore Issue 总结

本文档基于以下材料整理：

- [debug-ssl.md](/Users/lex/git/knowledge/ssl/debug-ssl.md)
- [debug-ssl-chatgpt.md](/Users/lex/git/knowledge/ssl/debug-ssl-chatgpt.md)
- [gskit.md](/Users/lex/git/knowledge/ssl/gskit.md)
- [verify-domain-ssl-enhance.sh](/Users/lex/git/knowledge/ssl/verify-domain-ssl-enhance.sh)

目标是把这次问题统一收敛成一个更可复用的结论：

**如果问题可以总结为 `certificate truststore issue`，那么它通常意味着什么、可能的原因有哪些、该怎么排查和解决。**

---

## 1. 结论先行

如果客户端报错可以归类为 `certificate truststore issue`，它的本质通常是：

**客户端在 TLS 握手时，无法把服务端返回的证书链验证到一个自己信任的 CA 根证书。**

这类问题在不同生态里会以不同形式出现：

- OpenSSL 常见表现：
  - `Verify return code: 20 (unable to get local issuer certificate)`
  - `Verify return code: 21 (unable to verify the first certificate)`
- IBM GSKit 常见表现：
  - `GSKit Error: 6000 - Certificate is not signed by a trusted certificate authority.`
  - `gsk_secure_soc_init() failed`

虽然报错文案不同，但根因常常是同一类问题：  
**证书链与 trust store 之间没有完成信任闭环。**

---

## 2. 什么叫 truststore issue

所谓 `certificate truststore issue`，不一定等于“证书坏了”，更准确地说，它表示：

- 服务端出示了证书
- 客户端也收到了证书链
- 但客户端本地的信任库（trust store / CA store / KDB / DCM）无法确认这条链是可信的

所以它既可能是：

- 客户端 trust store 缺证书

也可能是：

- 服务端证书链没配完整
- 客户端使用了错误的 trust store
- 服务端返回的链顺序/内容不对

---

## 3. 最常见的原因

下面这些都是“certificate truststore issue”背后的高频原因。

### 3.1 客户端 trust store 缺少企业 Root CA

这是最常见的原因，尤其在企业内网和私有 PKI 场景下。

典型场景：

- 服务端证书由企业内部 CA 签发
- 客户端机器或运行时环境并不信任这个内部 CA
- 最终无法把 Leaf / Intermediate 追溯到受信任的 Root

常见表现：

- OpenSSL 报 `return code 20`
- GSKit 报 `Error 6000`

### 3.2 客户端 trust store 缺少 Intermediate CA

有些环境不仅要有 Root CA，还需要中间证书链配套完整，否则也会失败。

尤其在一些老旧客户端、IBM 生态、中间件或自定义 trust store 里，这个问题更常见。

### 3.3 服务端没有返回完整证书链

即使客户端 trust store 没问题，如果服务端只返回叶子证书，没有返回 Intermediate CA，也会导致验证失败。

这是一个非常容易被误判成“客户端缺 CA”的问题。

典型表现：

- `CERT_COUNT = 1`
- `Verify return code: 21`

这时根因更偏向服务端配置问题，而不是纯客户端问题。

### 3.4 客户端使用了错误的 trust store

这是很多排查里容易忽略的一点。

你以为客户端在用系统 CA，其实不一定。

典型例子：

- Linux 系统看的是 `/etc/ssl/certs/...`
- Java 用的是 `cacerts`
- Python requests 可能用 `certifi`
- IBM GSKit / WebSphere / MQ / Db2 用的是 `.kdb` 或 `DCM`

所以“我已经把 CA 装到系统里了”并不代表目标客户端真的会用它。

### 3.5 服务端返回了链，但不是客户端信任的那条链

例如：

- 服务端用了错误的 Intermediate
- 证书链顺序不规范
- 返回了不适合该客户端验证路径的链

这类问题看起来“有多段证书”，但仍然会失败。

### 3.6 客户端运行环境太旧

有些老系统或旧版中间件可能：

- 根证书库过旧
- 缺少新的公有 CA
- 只支持特定证书格式或导入方式

这会让“在浏览器正常、在老客户端失败”的情况出现。

### 3.7 证书部署和 trust store 更新不一致

比如：

- 服务端已经切换到新证书
- 客户端还只信任旧 CA

或者：

- 某些机器已经导入新 Root
- 某些机器没有更新

这会导致问题只在部分环境出现。

---

## 4. 在 GSKit / IBM 生态下为什么更容易遇到

根据 [gskit.md](/Users/lex/git/knowledge/ssl/gskit.md) 的结论，`GSKit Error: 6000` 本质上就是 IBM 生态里的“truststore 不信任服务端证书链”。

关键点在于：

- GSKit 并不一定使用 Linux 常规 CA 文件
- IBM i / WebSphere / MQ / Db2 等环境常常使用：
  - `DCM`
  - `.kdb`
  - `gskcmd` / `gsk8abjicmd` / `ikeyman`

所以在 IBM 生态里，哪怕：

- 浏览器能访问
- Linux curl 能通过

也不能证明 GSKit 客户端一定能通过。

因为它们很可能根本不是同一个 trust store。

---

## 5. 如何判断是 truststore issue，而不是别的问题

下面这个判断思路比较稳。

### 5.1 先看错误语义

如果报错明确指向：

- `not signed by a trusted certificate authority`
- `unable to get local issuer certificate`
- `unable to verify the first certificate`

优先把问题归到证书链 / trust store，而不是 TLS 版本、cipher 或网络问题。

### 5.2 再用脚本确认服务端返回了什么

使用 [verify-domain-ssl-enhance.sh](/Users/lex/git/knowledge/ssl/verify-domain-ssl-enhance.sh) 做两件事：

1. 看服务端返回了几段证书
2. 看默认 CA 与指定 CA 下的验证结果

### 5.3 用结果做责任分流

可以按下面这个判断矩阵看：

| 现象 | 更可能的原因 | 处理方向 |
| --- | --- | --- |
| `CERT_COUNT = 0` | 网络 / 端口 / SNI / TLS 接入点问题 | 先查连通性和入口配置 |
| `CERT_COUNT = 1` + `return code 21` | 服务端未返回 Intermediate | 修服务端 fullchain |
| `CERT_COUNT >= 2` + `return code 20` | 客户端 trust store 缺 Root / 上级 CA | 修客户端 trust store |
| 自定义企业 CA 通过，系统 CA 不通过 | 系统 trust store 缺企业 CA | 导入企业 CA 到实际运行环境 |
| 浏览器通过，但 GSKit 失败 | GSKit 使用独立 trust store | 导入 DCM / KDB，而不是只改系统 CA |

---

## 6. 如果最终归因为 truststore issue，解决办法有哪些

这里分服务端和客户端两部分，因为很多时候两边都要确认。

### 6.1 服务端侧解决办法

#### 方法 A：确保服务端返回完整证书链

如果服务端没有返回 Intermediate，那么客户端再怎么配 trust store 也可能失败。

应该确认：

- Nginx / Kong / Ingress / LB 配的是 `fullchain`
- 证书链顺序正确
- 不是只挂了叶子证书

适用场景：

- `CERT_COUNT = 1`
- 或 `return code 21`

#### 方法 B：确认切换的新证书链与客户端信任体系兼容

如果换了新的内部 CA / 新 Intermediate，需要确保客户端端也同步更新。

---

### 6.2 客户端侧解决办法

#### 方法 A：把企业 Root CA 导入客户端实际使用的 trust store

这是最标准、最推荐的做法。

但要注意“导到哪里”：

- Linux / Ubuntu:
  - `/usr/local/share/ca-certificates/`
  - `update-ca-certificates`
- Java:
  - `cacerts`
- Python / requests:
  - 指定 CA bundle 或修正运行时证书路径
- IBM GSKit:
  - `DCM`
  - `.kdb`

#### 方法 B：把 Intermediate CA 一并导入

在某些运行环境里，仅 Root 不一定够，尤其是老系统或独立 trust store 场景。

#### 方法 C：在应用配置里显式指定 CA 文件

比如：

- curl 的 `--cacert`
- 某些 SDK 的 `ca_file`
- 某些中间件的专属证书配置

这适合做验证和短期修复，但长期仍建议统一 trust store 管理。

#### 方法 D：统一通过企业 IT / AD / Jamf / 配置管理下发

如果客户端数量多，不应该靠人工逐台导入。

更好的做法是：

- 企业统一下发内部 Root / Intermediate
- 保持终端和服务器的证书信任一致性

---

## 7. 不推荐但常见的“临时绕过法”

### 跳过证书校验

例如：

- `curl -k`
- 关闭 verify
- GSKit 中的容忍模式（如文档里提到的 `sslTolerate=true`）

这类办法的作用只是：

- 帮你验证“网络和服务本身是不是通的”

它不能作为正式解决方案，因为它等于放弃服务端身份校验，存在 MITM 风险。

所以：

- 可以用于临时调试
- 不适合生产长期使用

---

## 8. 推荐的排查顺序

如果今后再遇到类似问题，我建议按下面顺序走。

### Step 1：确认报错是否真的指向 trust issue

先看错误关键字：

- `trusted certificate authority`
- `local issuer certificate`
- `unable to verify the first certificate`
- `GSKit Error: 6000`

### Step 2：检查服务端返回的链

使用增强脚本看：

- 证书数
- 每段 Subject / Issuer
- Verify return code

### Step 3：对照默认 trust store 和指定企业 CA

如果：

- 默认 CA 失败
- 指定企业 CA 成功

那几乎就能确认是 trust store 缺失问题。

### Step 4：确认目标客户端到底用哪个 trust store

这一步特别重要。

不要只问：

- “机器里有没有证书”

而是要问：

- “这个具体客户端运行时，究竟看的是哪个证书库”

### Step 5：决定修服务端还是修客户端

- 服务端链不完整：先修服务端
- 服务端链完整，但客户端不信任：修客户端 trust store
- 两边都不清楚：先做对照验证，不要拍脑袋

---

## 9. 这次问题如果总结成一句话

如果把这次问题统一总结为 `certificate truststore issue`，最准确的表达应该是：

**客户端在 TLS 握手时无法把服务端证书链锚定到自己信任的 CA 根证书；其根因可能是客户端 trust store 缺少企业 Root / Intermediate CA，也可能是服务端未返回完整证书链，必须通过证书链探测和 trust store 对照验证来分流。**

---

## 10. 最终建议

如果你后续要把这个结论给团队复用，我建议保留下面这几个固定动作：

- [ ] 先用脚本确认服务端返回的是不是完整链
- [ ] 再用系统 CA 和企业 CA 各测一次
- [ ] 明确目标客户端实际使用的是哪个 trust store
- [ ] IBM / GSKit 场景单独看 DCM / KDB，不要只看 Linux 系统证书库
- [ ] 禁止把“跳过证书校验”当长期方案

这样以后再看到类似：

- `GSKit Error 6000`
- `Verify return code 20`
- `unable to verify the first certificate`

你就可以很快把问题收敛到：

**证书链问题？还是 trust store 问题？到底该找网关团队，还是找客户端/平台/IT 团队。**
