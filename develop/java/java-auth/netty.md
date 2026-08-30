- [Netty 探索笔记 — 抛开漏洞,这东西到底是什么?](#netty-探索笔记--抛开漏洞这东西到底是什么)
  - [§1 一句话定义(从 Netty 官网)](#1-一句话定义从-netty-官网)
  - [§2 Netty 实现的是什么 —— 三大核心组件](#2-netty-实现的是什么--三大核心组件)
    - [2.1 Buffer — 自己的字节容器](#21-buffer--自己的字节容器)
    - [2.2 Channel — 一个比 JDK Socket 更高层的抽象](#22-channel--一个比-jdk-socket-更高层的抽象)
    - [2.3 Event Model — 事件驱动的 pipeline](#23-event-model--事件驱动的-pipeline)
    - [2.4 跟 Nginx / HAProxy 的类比(Linux 管理员视角)](#24-跟-nginx--haproxy-的类比linux-管理员视角)
      - [2.4.1 一句话类比](#241-一句话类比)
      - [2.4.2 类比成立的部分 ✓](#242-类比成立的部分-)
      - [2.4.3 类比**不**成立的部分 ✗(知道边界,避免误解)](#243-类比不成立的部分-知道边界避免误解)
      - [2.4.4 一个临时起的 HTTPS 服务(跟 `python3 -m http.server` 同心智模型)](#244-一个临时起的-https-服务跟-python3--m-httpserver-同心智模型)
  - [§3 Netty 的线程模型 — EventLoop](#3-netty-的线程模型--eventloop)
  - [§4 Netty 在整个 Java 生态里的位置](#4-netty-在整个-java-生态里的位置)
  - [§5 一个最小可跑的 Netty 例子 —— 直观理解](#5-一个最小可跑的-netty-例子--直观理解)
  - [§6 关键设计哲学 —— 为什么 Netty 流行起来](#6-关键设计哲学--为什么-netty-流行起来)
  - [§7 跟 java-auth 主题的相关性](#7-跟-java-auth-主题的相关性)
  - [§8 我自己的探索结论(写给自己的)](#8-我自己的探索结论写给自己的)
  - [Sources](#sources)
    - [Related docs in this repo](#related-docs-in-this-repo)

# Netty 探索笔记 — 抛开漏洞,这东西到底是什么?

> **为什么写这个文档**:在看 `cve-2026-50010-netty-hostname-verification-bypass.md` 的过程中,我意识到自己对 Netty 的认知一直被"漏洞视角"框住——只知道 Netty 的某个具体 bug、某个 CVE。但 Netty 本身是一个独立的、有自己设计哲学的网络框架,值得作为一个**完整对象**来理解。这个文档就是我个人对 Netty 的探索记录。
>
> **配套 ELI5**:把 Netty 解释给一个完全不懂网络的人——见 [`netty-eli5.html`](./netty-eli5.html)
>
> **范围**:这个文档只讲 Netty **本身**——它做什么、怎么实现、它在整个 Java 网络栈里处于什么位置。**不重复**任何 CVE / 安全问题的细节(那些在 `cve-2026-50010-*.md` 和 `fix-spring-boot-3-5-16-remove-netty-overrides.md` 里),只在该 CVE 直接体现 Netty 的某个内部机制时引用。

---

## §1 一句话定义(从 Netty 官网)

> "Netty is an **asynchronous event-driven network application framework** for rapid development of maintainable high performance protocol servers & clients."[1]

翻译一下:**Netty 是一个帮你快速搭建高性能网络应用(同时支持 server 和 client 两种角色)的框架**——它解决的是 Java 标准 NIO API 写起来太啰嗦、性能调优太深、协议实现要重复造轮子这三个问题。

**对 Java 程序员的实际意义**:

- 你要写一个 TCP server 接收几万个客户端连接 → 用 Java 标准 `ServerSocketChannel` + Selector 写,代码量大概 200-400 行,且要自己处理线程模型、内存分配、协议解析。Netty 把这些**全部封装好**,你只需要写"业务逻辑"。
- 你要写一个 HTTP/WebSocket/gRPC/RPC 客户端 → Netty 提供现成的编解码器(`HttpClientCodec`、`WebSocketFrameDecoder` 等),你只需要装配 pipeline。
- 你要在 Linux 上用 epoll、macOS 上用 kqueue 拿原生性能 → Netty 自动根据平台选 native transport,你不用写两套代码。

**核心定位**(对比 Java 标准库):

| 维度 | Java 标准 NIO | Netty |
|------|-------------|-------|
| API 抽象 | 暴露底层 selector / channel / buffer,需要手写状态机 | 暴露 `ChannelHandler` 链 + 事件回调,业务代码只关心 handler |
| 协议实现 | 自己写 | 现成 codec 模块覆盖 HTTP / HTTP/2 / WebSocket / DNS / MQTT / SMTP / Redis / HAProxy |
| 线程模型 | 单 selector 线程 / 需自己 fork 多线程 | 可配置:单线程 / 多线程 / 主从多线程 |
| 内存 | HeapByteBuffer(GC 压力大) | 自家 PooledByteBufAllocator(reduce GC,zero-copy) |
| 平台原生 | NIO selector(JDK 实现)| NIO + epoll(Linux)+ kqueue(macOS/BSD)native transport |
| 异步编程 | Callback / Future / CompletableFuture | ChannelFuture + Listener + 自家 Promise |

---

## §2 Netty 实现的是什么 —— 三大核心组件

Netty 官方文档原话:

> "Netty is composed of three components - **buffer, channel, and event model** - and all advanced features are built on top of the three core components."[1]

这一节把这三个核心拆开讲。

### 2.1 Buffer — 自己的字节容器

Netty **不用 JDK 的 `ByteBuffer`**,而是实现了 `ByteBuf`。为什么:

- **JDK ByteBuffer 的痛点**:`flip()` / `clear()` / `rewind()` 这套状态切换容易出错(忘了 flip 就读不到数据);固定长度(只能 `int`,不能 long);没有引用计数,容易内存泄漏
- **ByteBuf 的改进**:**双指针**(readerIndex + writerIndex,不用 flip)+ **引用计数**(`refCnt()`,0 时自动释放)+ **池化**(`PooledByteBufAllocator` 复用内存块)

这就是为什么 Netty 在高并发下 GC 压力小——**大部分 ByteBuf 是从 pool 里租的,归还即可,不走 GC**。

### 2.2 Channel — 一个比 JDK Socket 更高层的抽象

- JDK 的 `SocketChannel` 是 OS socket 的薄封装,读写 buffer / selector 注册 / 非阻塞标志都要自己管
- Netty 的 `Channel` 是**对 socket 的可扩展封装**——每个 Channel 都挂了一条 `ChannelPipeline`(handler 链)
- 关键 API:`channel.read()` / `channel.write()` / `channel.flush()` / `channel.close()`——这些都返回 `ChannelFuture`,是异步的,你可以加 listener 监听完成事件

**Channel 类型家族**(简化):

```
Channel
├── NioSocketChannel         ← 客户端 TCP 连接
├── NioServerSocketChannel  ← 服务端监听 socket
├── NioDatagramChannel      ← UDP
├── EpollSocketChannel      ← Linux native(性能更好)
├── KQueueSocketChannel     ← macOS native
└── ... 各 transport 的 native 实现
```

业务代码**只跟抽象的 `Channel` 接口打交道**,transport 由 Netty 自动选——这是 Netty 跨平台的核心。

### 2.3 Event Model — 事件驱动的 pipeline

这是 Netty 最巧妙的设计:**ChannelPipeline + ChannelHandler 链**。

```java
// 写一个 EchoServer 的入站 handler(典型例子)
public class EchoServerHandler extends ChannelInboundHandlerAdapter {
    @Override
    public void channelRead(ChannelHandlerContext ctx, Object msg) {
        ctx.write(msg);  // 直接 echo 回去
    }

    @Override
    public void channelReadComplete(ChannelHandlerContext ctx) {
        ctx.flush();    // flush 触发实际写
    }

    @Override
    public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
        cause.printStackTrace();
        ctx.close();
    }
}

// 启动 server
EventLoopGroup boss = new NioEventLoopGroup(1);   // 接收连接
EventLoopGroup worker = new NioEventLoopGroup(); // 处理 IO
ServerBootstrap b = new ServerBootstrap();
b.group(boss, worker)
 .channel(NioServerSocketChannel.class)
 .childHandler(new ChannelInitializer<SocketChannel>() {
     @Override
     public void initChannel(SocketChannel ch) {
         ch.pipeline().addLast(new EchoServerHandler());
     }
 });
b.bind(8080).sync();
```

**事件流向**:

```
入站(inbound,数据从 socket 进来):
  socket bytes → ByteBuf → 解码(inbound handler)→ 业务对象 → 业务 handler
  
出站(outbound,数据要发出去):
  业务对象 → 编码(outbound handler)→ ByteBuf → socket bytes
```

**两个方向都有 handler 链**,且每个 handler 可选 in / out 单向或双向。每个 handler 专注于一件事(解 HTTP 头 / 解 protobuf / 鉴权 / 限流 / 业务),**链式组合**出复杂协议处理。

---

### 2.4 跟 Nginx / HAProxy 的类比(Linux 管理员视角)

> 这一节是给 **Linux 服务管理员 / SRE** 的快速定位——你熟悉的 Nginx 配置项,在 Netty 里都叫什么、怎么对应。如果你不是这个背景,可以跳过。

#### 2.4.1 一句话类比

> **Netty ≈ "把 Nginx / HAProxy 写成了 Java 库,作为依赖嵌进你自己的应用里"——而不是像 Nginx 那样作为独立 daemon 装在系统上。**

Nginx 是 1995 年由 Igor Sysoev 开始写的反向代理 / web server,**Netty 是 2008 年由 Trustin Lee(韩国)开始写的、面向 Java 的同类东西**。Netty 的设计哲学直接借鉴了 Nginx 的事件驱动 + worker 模型——这不是巧合,是同一类问题(高并发 TCP/HTTP 处理)的相同最优解。

HAProxy 比 Nginx 更纯粹的 L4/L7 反向代理定位,所以这个类比的精度:**Nginx ≈ Netty 的 HTTP 部分**(SSL termination + location 路由 + reverse proxy);**HAProxy ≈ Netty 的 TCP 连接池 + 上游负载均衡部分**。两者结合最准。

#### 2.4.2 类比成立的部分 ✓

| Nginx / HAProxy 的能力 | Netty 的对应 |
|------------------------|--------------|
| 高并发 TCP/HTTP 处理(event-driven) | EventLoop + selector |
| master + workers 进程模型 | boss EventLoop + worker EventLoop |
| `ssl_certificate` SSL termination | `SslContextBuilder.forServer().keyManager(...)` |
| `proxy_pass http://upstream` 反代 | Netty `HttpClient` + `ConnectionProvider` pool |
| `location /api {}` 路由块 | `ChannelPipeline.addLast(handler)` |
| `worker_processes auto` | `EventLoopGroup(Runtime.availableProcessors() * 2)` |
| `keepalive_timeout 65` | pipeline 里的 `IdleStateHandler` |
| `proxy_set_header Host $host` | outbound `HttpClient` 的 default headers |
| `gzip on` | pipeline 里的 `HttpContentCompressor` |
| `client_max_body_size 10m` | `HttpObjectAggregator(10 * 1024 * 1024)` |
| `limit_req zone=... burst=20` | 你自己写的限流 handler(塞 pipeline 里) |
| `access_log /var/log/nginx/access.log` | 你自己写的日志 handler(塞 pipeline 里) |
| `upstream backend { ip_hash; }` | `ConnectionProvider` with key-based affinity |
| `proxy_ssl_server_name on` (SNI) | Netty 的 SNI handling(默认就在 `SslHandler` 里)|

#### 2.4.3 类比**不**成立的部分 ✗(知道边界,避免误解)

| 维度 | Nginx | Netty |
|------|-------|-------|
| **部署形式** | 独立 daemon 进程(`nginx`,`haproxy` 系统服务) | Java **库**,`import io.netty...` 嵌进你的 JVM |
| **配置文件** | `nginx.conf` / `haproxy.cfg` | **没有**——你写 Java 代码装配 pipeline |
| **reload** | `nginx -s reload` 热重载 | **没有**——你要重启 JVM 或自己写 reload 逻辑 |
| **HTTP 协议等级** | HTTP-first,其他协议是 addon | **协议无关**(HTTP / WebSocket / gRPC / DNS / MQTT 都是 codec)|
| **worker 隔离** | 进程级(一个 worker 挂了不影响别人) | 线程级(都在一个 JVM 里,一个 handler 抛 OOM 可能整进程挂) |
| **运维工具** | `nginx -t` 测配置 / `nginx -V` 看编译参数 / `stub_status` 看指标 | 无——你要靠 JVM 自己的工具(`jstack` / `jconsole` / Micrometer)|

**最重要的边界**:**Netty 没有配置文件**。Nginx 的所有优势("改个 location 重启一下就行")在 Netty 这里**不存在**——你必须改 Java 代码、重新打包、重启 JVM。所以 Netty **不适合**做"独立网关 daemon",**适合**做"我自己的应用里需要高性能网络通信"的库。

#### 2.4.4 一个临时起的 HTTPS 服务(跟 `python3 -m http.server` 同心智模型)

你提的"临时起一个服务,支持 HTTPS"——在 Linux 管理员心智里,这通常是:

```bash
# 起一个临时 HTTP server(给同事传文件用)
python3 -m http.server 8080

# 起一个临时 HTTPS server(用 openssl + socat)
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 1 -subj '/CN=localhost'
python3 -c "
import http.server, ssl
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain('cert.pem', 'key.pem')
http.server.HTTPServer(('0.0.0.0', 8443), http.server.SimpleHTTPRequestHandler, ssl_context=ctx).serve_forever()
"
```

**用 Netty 做同样的事**(5 分钟搞定,生产可用):

```java
import io.netty.bootstrap.ServerBootstrap;
import io.netty.channel.*;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioServerSocketChannel;
import io.netty.handler.codec.http.*;
import io.netty.handler.ssl.SslContextBuilder;
import io.netty.handler.ssl.SslHandler;

import javax.net.ssl.SSLEngine;
import java.io.File;

public class QuickHttpsServer {
    public static void main(String[] args) throws Exception {
        // 1. SSL context —— 跟 nginx 的 ssl_certificate 一一对应
        io.netty.handler.ssl.SslContext sslCtx = SslContextBuilder.forServer(
            new File("cert.pem"), new File("key.pem")
        ).build();

        EventLoopGroup boss = new NioEventLoopGroup(1);
        EventLoopGroup worker = new NioEventLoopGroup();
        try {
            ServerBootstrap b = new ServerBootstrap();
            b.group(boss, worker)
             .channel(NioServerSocketChannel.class)
             .childHandler(new ChannelInitializer<SocketChannel>() {  // 2. pipeline —— 跟 nginx 的 location{} 块一一对应
                 @Override
                 protected void initChannel(SocketChannel ch) {
                     SSLEngine engine = sslCtx.newEngine(ch.alloc());  // 3. SSL termination —— 跟 nginx 的 SSL termination 一一对应
                     ch.pipeline().addLast(new SslHandler(engine));    //    (放在最前面:SSL 先解,后面的 handler 才看到明文 HTTP)
                     ch.pipeline().addLast(new HttpServerCodec());     //    (HTTP 解析)
                     ch.pipeline().addLast(new HttpObjectAggregator(65536));
                     ch.pipeline().addLast(new SimpleChannelInboundHandler<FullHttpRequest>() {
                         @Override protected void channelRead0(ChannelHandlerContext ctx, FullHttpRequest req) {
                             // 4. 业务逻辑 —— 你写什么都行
                             String body = "hello from netty, you sent: " + req.uri();
                             byte[] bodyBytes = body.getBytes();
                             FullHttpResponse resp = new DefaultFullHttpResponse(
                                 req.protocolVersion(), HttpResponseStatus.OK,
                                 io.netty.buffer.Unpooled.wrappedBuffer(bodyBytes)
                             );
                             resp.headers().set(HttpHeaderNames.CONTENT_TYPE, "text/plain");
                             resp.headers().set(HttpHeaderNames.CONTENT_LENGTH, bodyBytes.length);
                             ctx.writeAndFlush(resp);
                         }
                     });
                 }
             });
            Channel ch = b.bind(8443).sync().channel();   // 5. listen —— 跟 nginx 的 listen 8443 ssl 一一对应
            System.out.println("HTTPS server on https://localhost:8443/  (Ctrl+C to stop)");
            ch.closeFuture().sync();
        } finally { boss.shutdownGracefully(); worker.shutdownGracefully(); }
    }
}
```

```bash
# 跑(需要 netty-all JAR)
javac -cp netty-all-4.1.135.Final.jar QuickHttpsServer.java
java -cp netty-all-4.1.135.Final.jar:. QuickHttpsServer
# → HTTPS server on https://localhost:8443/

# 跟 nginx / haproxy 一样可以从外部验证
curl -k https://localhost:8443/hello
# → hello from netty, you sent: /hello
```

**心智对照**:

| 你熟悉 | Netty 这边 |
|--------|-----------|
| `python3 -m http.server 8080` 一行起 HTTP | 这段 Java 代码 + `java -cp ...` 一行起 HTTPS |
| nginx `listen 8443 ssl` | `b.bind(8443).sync()` |
| nginx `ssl_certificate cert.pem; ssl_certificate_key key.pem` | `SslContextBuilder.forServer(cert.pem, key.pem)` |
| nginx `location / { return 200 "hello"; }` | `channelRead0(...)` 里的 `DefaultFullHttpResponse` |
| nginx `nginx -s reload` | 没有——Ctrl+C 再 `java ...` 重启 |

**核心 takeaway**:**Netty 跟 Nginx / HAProxy 是同类问题的同类解法,只是部署形态从"独立 daemon + 配置文件"变成了"Java 库 + 代码装配 pipeline"**。你熟悉的每一个 Nginx 配置项,在 Netty 这边都是一个 builder 方法或一个 handler 类——名字可能不一样,但心智模型完全一致。

---

## §3 Netty 的线程模型 — EventLoop

**EventLoop = 一个绑定到固定线程的 selector**,专门负责一组 channel 的 IO 事件。这是 Netty 高性能的基石。

```
EventLoopGroup
├── EventLoop #1  (绑 Thread-1)  ← 负责 Channel-A, Channel-B, Channel-C
├── EventLoop #2  (绑 Thread-2)  ← 负责 Channel-D, Channel-E
└── EventLoop #N  (绑 Thread-N)  ← 负责 Channel-F, ...
```

**关键约束**:**一个 channel 整个生命周期里,所有 IO 事件都交给同一个 EventLoop**。意思是:
- **不需要加锁**——同一个 channel 上的 read/write 处理永远在同一线程,没有竞态
- 但**跨 channel 的状态共享要小心**——你不能在 handler 里乱用共享变量,要用 `AttributeKey` 或外部并发结构

**线程模型可选**:

| 模型 | 适用 | 线程数 |
|------|------|-------|
| 单线程 | debug / demo | 1 |
| 多线程(默认) | 多数 server | `2 * CPU` 个 EventLoop |
| 主从(boss + worker) | 高并发 server | boss 1 个(只 accept) + worker `2*CPU` 个 |

**这就是为什么 reactor-netty 在 server-side 有 keep-alive race**(详见 `fix-spring-boot-3-5-16-remove-netty-overrides.md`)——**EventLoop 处理多 channel 的 keep-alive 复用时,不同 EventLoop 之间的状态同步是竞争点**,bug 出在这里。

---

## §4 Netty 在整个 Java 生态里的位置

Netty 是"网络层"的底层框架,**几乎所有现代 Java 网络库都基于它**:

```
┌────────────────────────────────────────────────────────────┐
│ 应用层                                                      │
│   Spring WebFlux (reactive web)        ← 默认 reactor-netty  │
│   gRPC-Java (RPC)                     ← 默认 Netty transport│
│   Apache Dubbo (RPC)                  ← 默认 Netty           │
│   Apache Kafka client                  ← Kafka 3.x 用 Netty  │
│   RocketMQ client                      ← 用 Netty            │
│   Pulsar client                        ← 用 Netty            │
│   Spring Cloud Gateway                 ← 用 Netty            │
│   Vert.x (Eclipse)                    ← 用 Netty            │
│   Cassandra Java driver               ← 用 Netty            │
│   Elasticsearch Java client (旧)       ← 用 Netty            │
├────────────────────────────────────────────────────────────┤
│ 框架层                                                       │
│   reactor-netty                        ← Netty + Reactor 集成 │
│   Play Framework                       ← 用 Netty(早期)      │
│   Finagle (Twitter)                    ← 部分基于 Netty       │
├────────────────────────────────────────────────────────────┤
│ 底层                                                         │
│   Netty                                ← 核心网络框架         │
├────────────────────────────────────────────────────────────┤
│ OS                                                          │
│   epoll (Linux) / kqueue (BSD/macOS) / NIO selector          │
└────────────────────────────────────────────────────────────┘
```

**含义**:**Netty bug 影响的不是"用 Netty 的应用",而是"用 Netty 的所有应用"**——所以一个 Netty CVE(CVE-2026-50010 那种)的影响面非常广。**这也是为什么升 Netty 版本永远走 BOM-managed 路径,不要硬覆盖**(详见 `fix-spring-boot-3-5-16-remove-netty-overrides.md`)。

---

## §5 一个最小可跑的 Netty 例子 —— 直观理解

把 §2.3 的 EchoServer 跑一遍,能帮你看清数据流向:

```bash
# 启动 server
$ java -cp netty-all-4.1.135.Final.jar:. EchoServer
# 控制台输出: EchoServer started, listening on 8080

# 在另一个终端,测试 echo
$ echo "hello netty" | nc localhost 8080
hello netty    ← 原样回显
```

**发生了什么**(对应 §2.3 代码):

1. **boss EventLoop** 接受 TCP 连接(把 socketChannel 注册到 worker EventLoop)
2. **worker EventLoop** 监测到 channel 上有 READ 事件,触发入站 handler 链
3. `channelRead()` 拿到 `ByteBuf`,业务 handler 直接 `ctx.write(msg)` 写回
4. 数据沿出站 handler 链反向走(从尾到头),经过任何 out handler(比如 frame encoder)
5. **worker EventLoop** 监测到 OP_WRITE 事件,把 buffer 真正写到 socket

整个过程**没有任何你手写的线程切换代码**——Netty 用 EventLoop 的 selector 模型把 IO 事件和线程调度全部封装了。

---

## §6 关键设计哲学 —— 为什么 Netty 流行起来

读 Netty 的设计文档和源码,核心哲学反复出现的是这五条:

1. **关注点分离(Separation of Concerns)**:业务逻辑 vs 协议编解码 vs 传输层,handler 链各管一摊
2. **可组合(Composability)**:handler 是独立的、可重用的模块;你要实现 HTTP+TLS+WebSocket,就是 `SslHandler → HttpServerCodec → WebSocketServerProtocolHandler → 业务 handler`
3. **无锁化(Lock-free)**:一个 channel 绑定一个 EventLoop,不需要锁;跨 channel 的共享用 `AttributeKey` 显式管理
4. **零拷贝(Zero-copy)**:ByteBuf 通过 slice / duplicate 共享底层数组,避免重复分配;CompositeByteBuf 把多个 buffer 逻辑合并
5. **平台透明(Transport transparency)**:业务代码只写一次,NIO/epoll/kqueue 三个 transport 由 Netty 自动切换

这五条放在一起,**Netty 解决了 Java NIO 的"难写 + 难调优"两个根本痛点**,所以成了 Java 网络层的事实标准。

---

## §7 跟 java-auth 主题的相关性

| 主题 | 关联 |
|------|------|
| **TLS 客户端行为** | Netty 自己实现了 `SslHandler`,内嵌自家 trust manager 包装类。CVE-2026-50010 是这个包装类的实现 bug——**它是 Netty 作为 client 做 TLS 校验时的核心组件**。理解 §2.1 ByteBuf + §2.3 Pipeline 才能看懂这个 CVE 为啥在 pipeline 里跑。详见 `cve-2026-50010-netty-hostname-verification-bypass.md` |
| **reactor-netty keep-alive race** | server 端 EventLoop 处理 keep-alive 连接复用时的 race。理解 §3 EventLoop 模型才能看懂为啥 EventLoop 间状态同步会成为竞争点。详见 `fix-spring-boot-3-5-16-remove-netty-overrides.md` |
| **cipher suite 协商** | Netty 不直接管 cipher 列表——`SslHandler` 委托给 JDK 的 SSLEngine。这意味着 cipher 协商能力取决于 JRE,**§4 那个握手失败问题跟 Netty 本身无关**。详见 `pod-curl.md` |
| **平台 cipher upgrade 触发 handshake_failure** | 跟 Netty **不沾边**——Netty 调底层 SSLEngine,而 SSLEngine 受 JRE 控制。根因在 JRE,不在 Netty。详见 `pod-curl.md` §2 |

---

## §8 我自己的探索结论(写给自己的)

读完之后,几个**之前没意识到的点**:

1. **Netty 的"网络框架"不是单一职责**——它同时覆盖 buffer / channel / event loop / 多 transport / 协议 codec,是一个**完整网络栈的 Java 实现**。我之前以为它只是个"高性能 socket 库",理解浅了。
2. **Netty bug 影响面之所以大,是因为整个 Java 网络生态都堆在它上面**(gRPC / Dubbo / Kafka / Spring WebFlux / Vert.x)。一个 CVE 修不修,涉及的不只是"用 Netty 的应用",而是这些上层框架的所有用户。
3. **为什么 Spring Boot BOM 必须统一管 Netty 版本**——理解了"Netty 是事实标准"这一点之后,就知道任何 override 都是跟整个 Java 生态作对。
4. **Netty 跟 JDK JSSE 是协作关系,不是替代关系**——Netty 的 TLS 实现是把 JDK 的 `SSLEngine` 包成 handler pipeline。这意味着 cipher 协商、cert 解析这些底层活还是 JRE 做,Netty 只是在上面加了异步 + pipeline 的胶水。
5. **EventLoop 模型是 Netty 性能的根,也是 race condition 的根**——一个 channel 绑一个 EventLoop 消除锁,但跨 channel / 跨 EventLoop 的状态共享是 race 的高发地。`fix-spring-boot-3-5-16-remove-netty-overrides.md` 里那个 keep-alive race 就是 EventLoop 间状态同步踩了坑。

---

## Sources

[1] https://netty.io/ — Netty 官网:定义 + 三大核心组件(Buffer / Channel / Event Model)的原始描述
[2] https://github.com/netty/netty — Netty 项目 GitHub 主仓库:版本号、release、CVE 公告的权威来源

### Related docs in this repo

- `cve-2026-50010-netty-hostname-verification-bypass.md` —— CVE-2026-50010 全文翻译;**这个 CVE 之所以"在 Netty 里发生",是因为 Netty 的 `SslHandler` 自定义 trust manager 包装类(§2.3 pipeline 里跑的 handler)**
- `fix-spring-boot-3-5-16-remove-netty-overrides.md` —— reactor-netty server-side keep-alive race 的修法;**这个 race 之所以"在 Netty 里发生",是因为 EventLoop 模型跨 EventLoop 的状态同步(§3)**
- `pod-curl.md` —— Java app 作 client 调第三方报 `handshake_failure` 的分析;**这个跟 Netty 无关**——Netty 调底层 SSLEngine,而 cipher 协商是 JRE 的责任
- `java-application-auth.md` —— Spring Boot server.ssl vs client.ssl 角色区分(Netty 是 transport 层的实现细节,跟 application 层的 SSL config 是两层)