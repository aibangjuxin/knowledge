# Runtime 层 Header 接收与验证

> 配套文档：[`../README.md`](../README.md)
>
> 覆盖：应用侧如何正确读取 Header、如何打印完整入站 Header、大小写陷阱、
> 如何避免"应用自己改坏 Header"、验证与回归。

---

## 目录

- [1. Runtime 的角色](#1-runtime-的角色)
- [2. 正确读取 Header：Servlet API](#2-正确读取-headerservlet-api)
- [3. 大小写陷阱：最常见的假故障](#3-大小写陷阱最常见的假故障)
- [4. 打印完整入站 Header](#4-打印完整入站-header)
- [5. 应用自己改坏 Header 的三种方式](#5-应用自己改坏-header-的三种方式)
- [6. 验证与回归](#6-验证与回归)
- [7. 非 Java Runtime](#7-非-java-runtime)

---

## 1. Runtime 的角色

在请求流向上，Runtime 是整条链路的**最后一个 upstream**（最末端）。
它的下游是 KongDP，方向相关术语见 [`../README.md` 第 2 节](../README.md#2-术语先行上游与下游)。

Runtime 是链路的**终点**，是唯一能回答"业务到底收到什么"的地方。
它的两个职责：

1. **如实记录**收到的 Header（排查的前提）。
2. **不要自己改坏** Header（否则你会把应用层的 bug 误判成网关的 bug）。

> **排查纪律**：在 Gateway 侧（nginx L7 / Kong）加探针，
> **不要**先在应用里加"临时打印"。原因：
> 应用打印发生在 Filter/Interceptor 链的某个位置，
> 打印出来的值可能**已经被前面的 Filter 改过**，
> 会把"应用层改动"伪装成"网关传错"。**先从链路最上游取证，再往下收口。**

> ⚠️ **另一个方向性的坑**：Runtime 日志里看到的是
> "**Kong → Runtime** 收到"的值，不是"Nginx L7 发出的"值。
> 中间还隔着 Kong 这一跳。**别拿 Runtime 日志反推 L7 发了什么**
> （详见 [`nginx-layer.md` 6.1.2](nginx-layer.md#612-补充别拿-runtime-日志反推-l7-发了什么)）。

---

## 2. 正确读取 Header：Servlet API

### 2.1 Spring Boot

```java
@RestController
public class ProbeController {

    @GetMapping("/debug/headers")
    public Map<String, List<String>> headers(HttpServletRequest request) {
        Map<String, List<String>> out = new LinkedHashMap<>();
        Enumeration<String> names = request.getHeaderNames();
        while (names.hasMoreElements()) {
            String name = names.nextElement();
            out.put(name, Collections.list(request.getHeaders(name)));
        }
        return out;
    }
}
```

`@RequestHeader` 的写法：

```java
// ✅ Spring 内部走 HttpServletRequest.getHeader()，大小写不敏感
@GetMapping("/a")
public String a(@RequestHeader("X-Caep-Src-Useragent") String v) { ... }

// ✅ 允许缺失（排查期强烈建议，避免因为头没了直接 400）
@GetMapping("/b")
public String b(@RequestHeader(value = "X-Caep-Src-Useragent", required = false) String v) { ... }
```

> ⚠️ `required = true`（默认）时，Header 缺失会返回 **400**，
> 这会让"头被删了"和"头被改错了"两种现象都表现为 400，掩盖真实原因。
> **排查期间一律用 `required = false`。**

### 2.2 Servlet 原生

```java
// ✅ 大小写不敏感（Servlet 规范保证）
String v = request.getHeader("X-Caep-Src-Useragent");

// ✅ 要所有同名值
Enumeration<String> all = request.getHeaders("x-caep-src-useragent");
```

---

## 3. 大小写陷阱：最常见的假故障

### 3.1 现象

网关侧日志显示 Header 存在且值正确，但应用报"Header 缺失"。

### 3.2 根因

把 Header 转成了**普通 `HashMap`** 再按 key 取值：

```java
// ❌ 危险：HashMap 的 key 区分大小写
Map<String, String> map = new HashMap<>();
request.getHeaderNames().asIterator().forEachRemaining(name ->
    map.put(name, request.getHeader(name)));

// 下游取不到：
map.get("X-Caep-Src-Useragent")   // → null
map.get("x-caep-src-useragent")   // → ✅ 只有这个能取到
```

### 3.3 正确写法

```java
// ✅ 方案一：用大小写不敏感的容器（Spring 自带）
import org.springframework.util.LinkedCaseInsensitiveMap;
Map<String, String> safe = new LinkedCaseInsensitiveMap<>();

// ✅ 方案二：用 Servlet API 直接取
String v = request.getHeader("X-Caep-Src-Useragent");

// ✅ 方案三：用 HttpHeaders（内部即大小写不敏感）
HttpHeaders headers = new HttpHeaders();
```

### 3.4 与本案例的关系

Kong 会把 Header 名**统一转小写**，所以 Runtime 收到的名字是
`x-caep-src-useragent`。如果应用用 `HashMap` + 精确 key，
就会出现"应用说没有、网关说传了"的**假象**。

> **因此排查第 8 节案例时，第一件事是确认应用侧用的是哪种读取方式。**
> 如果应用用了 `HashMap`，那么"头没了"可能根本不是网关的问题。

---

## 4. 打印完整入站 Header

### 4.1 一次性打印（推荐）

```java
@PostConstruct
void init() {
    // 只在需要时开启，避免长期打印敏感头
    System.setProperty("probe.dumpHeaders", "true");
}

private void dumpHeaders(HttpServletRequest request, String tag) {
    if (!Boolean.parseBoolean(System.getProperty("probe.dumpHeaders"))) return;

    StringBuilder sb = new StringBuilder("[" + tag + "] ");
    Enumeration<String> names = request.getHeaderNames();
    while (names.hasMoreElements()) {
        String name = names.nextElement();
        // 敏感头脱敏
        String value = isSensitive(name) ? "***" : request.getHeader(name);
        sb.append(name).append('=').append(value).append(" | ");
    }
    log.info(sb.toString());
}
```

> **务必脱敏**。`Authorization`、`Cookie`、`X-Api-Key` 等不要原样落日志。
> 长期存在的日志文件里出现凭证，等同于凭证泄露。

### 4.2 用探针头做对比（比打印全部更精准）

链路上的探针头（`X-Dbg-H1-*`、`X-Dbg-H2-*`）本身就会流到应用，
所以应用只需打印这几个头，就能拿到**每一跳的快照**：

```java
@GetMapping("/debug/probe")
public String probe(HttpServletRequest request) {
    StringBuilder sb = new StringBuilder();
    for (String h : List.of(
            "x-dbg-h1-useragent",
            "x-dbg-h1-caepsrcuseragent",
            "x-dbg-h2-caepsrcuseragent")) {
        sb.append(h).append('=').append(request.getHeader(h)).append('\n');
    }
    return sb.toString();
}
```

配合 `curl` 直接拉取，**无需翻日志**：

```bash
curl -s https://api.example.com/debug/probe \
  -H 'user-agent: UA_DIRECT_A' \
  -H 'x-caep-src-useragent: SRC_B' | jq .
```

> 这是**最省事**的收口方式：一个接口直接给出全链证据链。
> 前提是探针已在 L7 / Kong 侧配好。

---

## 5. 应用自己改坏 Header 的三种方式

| 方式 | 现象 | 识别方法 |
|---|---|---|
| **Filter 里 `setHeader`/`addHeader`** | 头值被应用改写 | 搜索 `setHeader\|addHeader\|setRequestProperty` |
| **Interceptor 读后写回** | 头值被"规整"（trim、大小写转换、截断） | 搜索 `getHeader` 后跟 `setHeader` |
| **网关 SDK 主动注入** | 多了 SDK 自己的头，覆盖了同名头 | 搜索 SDK 的 filter/interceptor 注册 |

Spring 里搜索：

```bash
grep -rn "setHeader\|addHeader\|setRequestProperty\|getHeader" \
  --include="*.java" src/ | grep -i "filter\|interceptor"
```

> 若确认是应用自己改的，**这属于业务逻辑问题，不是网关问题**。
> 但要注意：SDK 覆盖同名头，往往是因为**约定没定清楚**。
> 结构性改进是约定"每个 Header 由哪一层负责写"，并在文档中固化。

---

## 6. 验证与回归

### 6.1 单次验证

```bash
curl -sS -D- -o/dev/null https://api.example.com/ \
  -H 'user-agent: UA_DIRECT_A' \
  -H 'x-caep-src-useragent: SRC_B'
```

确认响应正常；再用探针接口确认链路每一跳的值。

### 6.2 回归用例（建议固化为 CI）

```bash
#!/usr/bin/env bash
# 断言：目标 Header 在全链未被改写
set -euo pipefail

URL="${1:?usage: verify-header.sh <url>}"
EXPECT_UA="UA_DIRECT_A"
EXPECT_SRC="SRC_B"

body=$(curl -sS "$URL" \
  -H "user-agent: ${EXPECT_UA}" \
  -H "x-caep-src-useragent: ${EXPECT_SRC}" \
  -H "x-debug-trace: 1")

assert_eq() {
  local key="$1" want="$2" got
  got=$(printf '%s' "$body" | jq -r --arg k "$key" '.[$k] // "MISSING"')
  if [[ "$got" != "$want" ]]; then
    echo "FAIL ${key}: want=${want} got=${got}" >&2
    exit 1
  fi
  echo "OK   ${key} = ${got}"
}

assert_eq "x-caep-src-useragent"        "$EXPECT_SRC"
assert_eq "x-dbg-h1-caepsrcuseragent"   "$EXPECT_SRC"
assert_eq "x-dbg-h2-caepsrcuseragent"   "$EXPECT_SRC"
```

把它挂到 CI 或发布后的 smoke check 里，
**这类"透传被改写"的回归能挡住绝大部分配置漂移事故**。

---

## 7. 非 Java Runtime

| 语言/框架 | 读取方式 | 大小写 |
|---|---|---|
| Go `net/http` | `r.Header.Get("X-Caep-Src-Useragent")` | `Header.Get` 大小写不敏感（内部 canonical 化） |
| Go `r.Header["x-caep-src-useragent"]` | 直接索引 map | **区分大小写**，键是 canonical 形式 |
| Python `FastAPI/Starlette` | `request.headers["x-caep-src-useragent"]` | `Headers` 大小写不敏感 |
| Python `request.environ["HTTP_X_..."]` | WSGI 环境变量 | 键**大写 + 下划线**，与原名不同 |
| Node.js `req.headers` | `req.headers["x-caep-src-useragent"]` | **全小写** |
| Node.js `req.rawHeaders` | 原始数组，保留原大小写 | 需要自己遍历 |

> **Python WSGI 特别提醒**：`environ` 里的键是 `HTTP_X_CAEP_SRC_USERAGENT`，
> 而 `request.headers` 是大小写不敏感的。混用两者容易得出矛盾结论。

---

## 相关文档

- [`../README.md`](../README.md) — 方法论总览
- [`kong-layer.md`](kong-layer.md) — Kong 侧大小写折叠行为
- [`../../docs/debug-header.md`](../../docs/debug-header.md) — Header 丢失类问题的既有排查记录
