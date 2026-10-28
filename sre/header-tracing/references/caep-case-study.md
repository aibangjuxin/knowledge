# 案例复盘：`x-caep-src-useragent` 被 `user-agent` 覆盖

> 配套文档：[`../README.md`](../README.md)
>
> 本文档针对具体现象做完整推理，**不预设结论**，
> 结论由第 5 节的取证步骤实际确定。

---

## 目录

- [1. 现象记录](#1-现象记录)
- [2. 关键推理：被改的到底是哪一个头](#2-关键推理被改的到底是哪一个头)
- [3. 候选机制排序](#3-候选机制排序)
- [4. 现象判别表](#4-现象判别表)
- [5. 取证步骤（按顺序执行）](#5-取证步骤按顺序执行)
- [5.7 建议的执行顺序（按成本从低到高）](#57-建议的执行顺序按成本从低到高)
- [6. 修复方案](#6-修复方案)
- [7. 结构性改进：防止同类问题复发](#7-结构性改进防止同类问题复发)
- [8. 对原始排查思路的点评](#8-对原始排查思路的点评)

---

## 1. 现象记录

链路：`Client → nginx L7 → nginx L4(stream) → Kong DP → Runtime`

| # | 位置 | `user-agent` | `x-caep-src-useragent` |
|---|---|---|---|
| 1 | Client 发出 | `UA_DIRECT_A` | `SRC_B` |
| 2 | Runtime 收到（异常） | `UA_DIRECT_A` | **`UA_DIRECT_A`** |

原始疑问：*"发送的请求头似乎被一个默认的覆盖了"*。

---

## 2. 关键推理：被改的到底是哪一个头

这一步决定了整个排查方向，**必须先做对**。

### 2.1 逐个比对

| Header | Client 值 | Runtime 值 | 结论 |
|---|---|---|---|
| `user-agent` | `UA_DIRECT_A` | `UA_DIRECT_A` | ✅ **未变**，不是受害者 |
| `x-caep-src-useragent` | `SRC_B` | `UA_DIRECT_A` | ❌ **被改写**，这是受害者 |

### 2.2 三个必须纠正的直觉

**纠正一：不是"user-agent 被覆盖了"。**
`user-agent` 全程一致，它既不是受害者，也不是凶手。

**纠正二：不是"被一个默认值覆盖"。**
如果是被某个写死的默认值覆盖，新值会是那个常量。
但这里新值是 `UA_DIRECT_A` —— **恰好等于同一个请求里另一个 Header 的值**。
这说明凶手做的是一次**"拷贝"动作**，不是"设常量"。

**纠正三：不在 L4。**
L4 是 `stream` 字节管道，不解析 HTTP。若 L4 实为 `http` 块，
需重新确认（见 `nginx-layer.md` 第 1 节）。

### 2.3 收敛结论

> **某一跳显式执行了"把 `$http_user_agent` 的值写入 `x-caep-src-useragent`"的动作。**
>
> 在 nginx 侧对应 `proxy_set_header X-Caep-Src-Useragent $http_user_agent;`
> 在 Kong 侧对应 `replace.headers` 里的
> `"x-caep-src-useragent:$(headers['user-agent'])"`。

**这类"值等于另一个 Header"的特征，通常把嫌疑从几十条配置收敛到一两行。**

---

## 3. 候选机制排序

| 排名 | 候选 | 层 | 机制 | 备注 |
|---|---|---|---|---|
| **1** | `proxy_set_header X-Caep-Src-Useragent $http_user_agent;` | nginx L7 | A 替换 | **最可能**：写法上"很自然"，像是想保留 UA 却写错了变量 |
| **2** | `map` + `proxy_set_header` 组合 | nginx L7 | F 模板 | `map` 的 `default` 分支取了 `$http_user_agent` |
| **3** | `request-transformer` → `replace.headers` 用 `$(headers['user-agent'])` | Kong | A/F | 客户端已发过该头，**只有 `replace` 能改到** |
| **4** | `request-transformer` → `append.headers` | Kong | C 重复 | 会产生逗号拼接，与现象不符 |
| **5** | `key-auth` 的 `hide_credentials: true` | Kong | B 删除 | 现象应是"头消失"而非"值被换"，**与现象不符** |
| **6** | 客户端自身 SDK 覆盖了该头 | Client | — | 若 Client 实际发出的就是 `UA_DIRECT_A`，则链路无罪 |

> **第 6 条不能跳过。** 必须先用 `curl -v` 或抓包确认
> **客户端真正发出的** `x-caep-src-useragent` 是 `SRC_B`。
> 如果客户端 SDK 自己改写了它，那这是客户端 bug，与网关无关。
> 注意 `SRC_B`/`UA_DIRECT_A` 这种命名**强烈暗示是人工构造的测试值**，
> 需确认测试工具没有替换它们。

---

## 4. 现象判别表

跑完取证后，用这张表定性：

| 实际观察到的现象 | 结论 | 对应机制 |
|---|---|---|
| `x-caep-src-useragent` = `UA_DIRECT_A`（等于另一个头） | 存在显式拷贝 | A / F |
| `x-caep-src-useragent` **消失** | 被删除，或名字含下划线被丢弃 | B |
| `x-caep-src-useragent` = `SRC_B, SRC_B` | 重复头 | C |
| `x-caep-src-useragent` = `SRC`（被截断） | 头部体积超限 → 但通常表现为 400 | E |
| `x-caep-src-useragent` = `SRC_B`（**正常**） | 问题在应用侧（大小写/HashMap） | 见 `runtime-layer.md` |
| `x-caep-src-useragent` = `UA_DIRECT_A` 且 `user-agent` 也变了 | 两处都坏 | 查是否有全局 map/rewrite |

---

## 5. 取证步骤（按顺序执行）

> 原则：**每一步都产出可写进结论的事实**，不做无产出的探查。

### Step 1 — 确认客户端真正发出的值（10 秒）

```bash
curl -sS -v -o/dev/null https://api.example.com/ \
  -H 'user-agent: UA_DIRECT_A' \
  -H 'x-caep-src-useragent: SRC_B' 2>&1 | grep -iE "^> (user-agent|x-caep-src-useragent)"
```

- 若输出是 `SRC_B` → 客户端正常，继续 Step 2。
- 若输出已经是 `UA_DIRECT_A` → **客户端就是凶手**，转第 6 节讨论。

### Step 2 — 排除 L4（10 秒）

在 L4 主机上：

```bash
nginx -T 2>/dev/null | grep -nE "^\s*(stream|http)\s*\{"
```

- 出现 `stream {` → L4 不可能改 Header，**排除**。
- 只有 `http {` → L4 参与排查，把它加入嫌疑层。

### Step 3 — L7 全量搜索（30 秒）

```bash
# 一次 grep 覆盖所有可能的改写点（最有效的一步）
nginx -T 2>/dev/null | grep -n -iE \
  'caep|user.agent|proxy_set_header|more_set|underscores_in_headers|ignore_invalid_headers|proxy_pass_request_headers'

# 再翻原始文件（含未生效的、被注释的）
# 注意：连字符与下划线两种命名写法都要搜
grep -rn -iE "caep|useragent|user_agent" /etc/nginx/
grep -rn "proxy_set_header" /etc/nginx/ | grep -v "^\s*#"
```

命中后**逐条判断**：这条 `proxy_set_header` 的**目标头名**是不是
`x-caep-src-useragent`，**取值**是不是 `$http_user_agent` / 含 `$http_user_agent` 的 `map`。

> 同时检查 `map` 块：
> ```bash
> nginx -T 2>/dev/null | grep -n -A8 "map .*user_agent\|map .*caep"
> ```

### Step 4 — Kong 侧搜索（30 秒）

```bash
# 全局插件
curl -s http://127.0.0.1:8001/plugins | jq -r '.data[] | "\(.name): \(.config|tostring)"' \
  | grep -iE "caep|useragent"

# 显式搜本案关键词
curl -s http://127.0.0.1:8001/plugins \
  | jq -r '.data[] | select((.config|tostring)|test("caep|useragent|user-agent";"i"))
        | "\(.name): \(.config|tostring)"'

# route / service 级插件（容易漏）
curl -s http://127.0.0.1:8001/routes   | jq '.data[] | select(.plugins) | {name, plugins}'
curl -s http://127.0.0.1:8001/services | jq '.data[] | select(.plugins) | {name, plugins}'
```

**重点看 `request-transformer` 的 `replace.headers`**：
出现 `x-caep-src-useragent` 且值是 `$(headers['user-agent'])` → **凶手确认**。

### Step 5 — 打开 debug 日志确认渲染值（可选但推荐）

```bash
curl -s -X PATCH http://127.0.0.1:8001/logging --data "config.log_level=debug"
# 发一次请求
curl -s http://127.0.0.1:8001/logging | tail -50 | grep -i "request-transformer"
curl -s -X PATCH http://127.0.0.1:8001/logging --data "config.log_level=info"
```

Kong debug 日志会直接打印：
```text
[request-transformer] template `$(headers['user-agent'])` rendered to `UA_DIRECT_A`
```
**这一行就是结案证据。**

### Step 6 — 用探针补齐证据链（确认无第二处改写）

在 L7 与 Kong 加上第 6 节的探针，再看 Runtime 收到的三个值：

```text
Runtime 收到:
  x-dbg-h1-caepsrcuseragent = SRC_B        ← L7 收到时还是对的
  x-dbg-h2-caepsrcuseragent = SRC_B        ← Kong 收到时还是对的
  x-caep-src-useragent      = UA_DIRECT_A  ← 但最终值是错的
```

- 若 H1/H2 都是 `SRC_B` 而最终值是 `UA_DIRECT_A`：
  凶手在 **Kong 之后** → 即 **Runtime 自身**（Filter/Interceptor 改的）。
  → 转 `runtime-layer.md` 第 5 节。
- 若 H2 已经是 `UA_DIRECT_A`：凶手在 **Kong**（含 Kong 插件）。
- 若 H1 已经是 `UA_DIRECT_A`：凶手在 **L7 或更上游**。

---

## 5.7 建议的执行顺序（按成本从低到高）

大多数情况在第 1 步就能结案，不要一上来就改配置抓包：

| 顺序 | 动作 | 成本 | 能解决什么 |
|---|---|---|---|
| **1** | 对 L7 / Kong / Runtime **全链路 grep** `caep` + `proxy_set_header` | 几分钟 | 覆盖 80% 的情况，直接看到那行覆盖规则 |
| **2** | 确认 L4 是不是 `stream` | 10 秒 | 排除一个层 |
| **3** | 确认客户端真正发出的值（`curl -v`） | 10 秒 | 排除"客户端自己改的" |
| **4** | 二分：直连 Runtime → 直连 Kong → 直连 L4 | 十几分钟 | 定位到具体某一跳 |
| **5** | 装探针（`--generate`），一次请求拿全链证据 | 半小时 | 证据链固化，可复现 |
| **6** | 抓包 / nginx debug 日志 | 较重 | 区分重复头、截断等疑难情况 |

> 顺序的意义：**先做便宜的排除，再做昂贵的取证。**
> 第 1 步找到那行配置时，后面的步骤其实都不需要了。

---

## 6. 修复方案

### 方案 A — 停止覆盖（推荐）

若 `x-caep-src-useragent` 的语义是"**客户端自声明的来源 UA**"，
那么任何用 `user-agent` 覆盖它的写法都是**语义错误**，应当直接移除。

```nginx
# ❌ 删除这行
# proxy_set_header X-Caep-Src-Useragent $http_user_agent;

# ✅ 改为显式透传
proxy_set_header X-Caep-Src-Useragent $http_x_caep_src_useragent;
```

Kong 侧：删除 `request-transformer` 里对应的 `replace.headers` 条目。

> 显式写出来比"不写"更好：
> 显式声明了"这一层不碰它"，防止未来某次配置合并把它带回来。

### 方案 B — 换用新头名

若平台确实需要"**平台观测到的 UA**"这个信息，
**不要复用客户端可控的头名**。

```nginx
proxy_set_header X-Caep-Observed-UserAgent $http_user_agent;
```

> **安全理由**：`x-caep-src-useragent` 由客户端提供，
> 客户端可以任意伪造。若下游把它用于**审计、计费、风控**，
> 而平台又用 `user-agent` 覆盖它 —— 这等于让**最终值不可信**。
> 反过来，用平台自己写入的新头名，下游就能区分
> "**客户端声明的**" 与 "**平台观测到的**"，两者各自可信度不同。

### 方案 C — 显式优先级（两者语义都要保留）

```nginx
map $http_x_caep_src_useragent $caep_src_useragent_final {
    default  $http_x_caep_src_useragent;   # 客户端声明了 → 用声明的
    ""       $http_user_agent;             # 没声明 → 退化为 UA
}
# ...
proxy_set_header X-Caep-Src-Useragent $caep_src_useragent_final;
```

Kong 侧无法用 `map`，但可用 `request-transformer` 的
`replace` + 模板近似实现（模板无法做"为空则取另一个"的完整条件），
所以方案 C **在 Kong 侧实现成本高**，优先在 nginx L7 落地。

### 方案对比

| 方案 | 语义正确性 | 实现成本 | 下游兼容 | 安全 | 推荐 |
|---|---|---|---|---|---|
| **A 停止覆盖** | ✅ | 低 | 无影响 | ✅ | ⭐⭐⭐ |
| **B 换新头名** | ✅ | 低 | **需下游同步改** | ⭐⭐⭐ 最清晰 | ⭐⭐ |
| **C 显式优先级** | ✅ | 中 | 无影响 | ✅ | ⭐⭐ |

### 6.4 改动前的安全动作

```bash
# Kong：改插件前先导出当前配置做备份
curl -s http://<kong-admin>:8001/config > kong-backup.json

# nginx：改完先验证语法，再 reload（不要直接 restart）
nginx -t && nginx -s reload
```

> GitOps 环境（Argo CD / Flux）下，Admin API 的临时改动会被下一次同步覆盖。
> 排查用的临时插件请单独命名并记录，**正式修复要落到 Git 里的声明式配置**。

---

## 7. 结构性改进：防止同类问题复发

单点修复只解决这一次。**结构性改进**才是长期答案。

### 7.1 确立 Header 所有权

为每个 Header 明确"**唯一写入方**"，并写进团队约定：

| Header | 写入方 | 其他层的行为 |
|---|---|---|
| `user-agent` | Client | 透传，不改写 |
| `x-caep-src-useragent` | Client（自声明） | **全部层透传，禁止改写** |
| `x-caep-observed-useragent` | nginx L7 | 其他层透传 |
| `x-forwarded-*` | 各层追加 | Kong 不可用 request-transformer 改写 |

> 规则一句话：**"客户端可控的头，任何网关层都不得改写；
> 平台自己产生的头，用平台专属前缀。"**

### 7.2 CI 回归护栏

用 `runtime-layer.md` 第 6.2 节的脚本，把"关键 Header 全链未被改写"
固化为 CI 检查。配置漂移（尤其是 GitOps 覆盖）会被立刻挡住。

### 7.3 配置评审检查项

- [ ] 新增/修改 `proxy_set_header` 时，是否改写了客户端可控的头？
- [ ] 新增 `location` 时，是否完整复制了上层的 `proxy_set_header` / `add_header`？
- [ ] Kong 插件的 `replace.headers` 里是否包含客户端可控的头？
- [ ] `key-auth` 等认证插件的 `hide_credentials` 是否显式设为 `false`？

---

## 8. 对原始排查思路的点评

原始思路里提出的配置片段：

```nginx
add_header X-Debug-User-Agent $http_user_agent always;
add_header X-Debug-X-CAEP $http_x_caep_src_useragent always;
proxy_set header X-Debug-User-Agent $http_x_caep_src_useragent;
proxy_set header X-Debug-Forwarded-Src $http_x_caep_src_useragent;
```

### 8.1 方向正确的部分 ✅

- **用 `$http_*` 变量把观察到的值"导出"**：这是正确的思路，
  nginx 确实没有"我发出的头"的观测手段（见 `nginx-layer.md` 第 6 节）。
- **加 `always`**：正确，避免非 2xx 看不到。

### 8.2 需要修正的部分 ⚠️

| 问题 | 说明 |
|---|---|
| `proxy_set header` 拼写 | 正确指令是 `proxy_set_header`（无空格）。写成 `proxy_set header` 会被 nginx 判为**未知指令**，配置直接加载失败 |
| `add_header` vs `proxy_set_header` 混用 | `add_header` 加的是**响应头**（客户端可见）；`proxy_set_header` 加的是**请求头**（上游可见）。两者观测**不同方向** |
| 两处用了 `X-Debug-User-Agent` | **响应头**与**请求头**同名，客户端会看到一个"来源不明"的头，混淆观测 |
| `X-Debug-User-Agent` 的值取自 `x_caep_src_useragent` | **语义错位**。头名说 UA，值却是另一个头的内容 → 看日志的人必然误判（见 `../README.md` 第 6.2 节） |
| 所有跳用同一个头名 | 下一跳会**覆盖**上一跳的章，前面所有证据丢失 → 必须带跳号（`X-Dbg-H1-*` / `X-Dbg-H2-*`） |
| `X-Debug-Forwarded-Src` 与上一行取值相同 | 两者取值一样，第二个头**没有提供任何新信息** |

### 8.3 修正后的版本

```nginx
# 请求方向：加在 L7，与业务 proxy_set_header 同层
proxy_set_header X-Dbg-H1-UserAgent       $http_user_agent;
proxy_set_header X-Dbg-H1-CaepSrcUserAgent $http_x_caep_src_useragent;

# 响应方向：加在需要观测响应的一跳，注意 always
add_header X-Dbg-R1-UpstreamUserAgent $upstream_http_user_agent always;
add_header X-Dbg-R1-SentUserAgent     $sent_http_user_agent always;
```

对比原版，每一行都**对应一个明确的观测面**，且**跳号唯一**，
不会互相覆盖。

---

## 相关文档

- [`../README.md`](../README.md) — 方法论总览与五步法
- [`nginx-layer.md`](nginx-layer.md) — nginx 侧指令语义与继承陷阱
- [`kong-layer.md`](kong-layer.md) — Kong 插件语义与排查命令
- [`runtime-layer.md`](runtime-layer.md) — 应用侧读取与验证
- [`../scripts/header-trace.sh`](../scripts/header-trace.sh) — 逐跳对比脚本
