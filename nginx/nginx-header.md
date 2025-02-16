- [user case](#user-case)
    - [Squid 代理：](#squid-代理)
    - [Nginx 代理：](#nginx-代理)
    - [总结](#总结)
    - [如果在Kubernetes集群内部实现文件上传,还可以在Ingress Controller层面配置最大文件大小限制。](#如果在kubernetes集群内部实现文件上传还可以在ingress-controller层面配置最大文件大小限制)
- [client\_max\_body\_size](#client_max_body_size)
- [large\_client\_header\_buffers](#large_client_header_buffers)
- [client\_header\_buffer\_size](#client_header_buffer_size)
- [Testing](#testing)
- [client\_max\_body\_size](#client_max_body_size-1)
- [large\_client\_header\_buffers](#large_client_header_buffers-1)
- [client\_header\_buffer\_size](#client_header_buffer_size-1)
- [Testing](#testing-1)


# user case
- 如果我的GKE环境中Pod是通过我GCE的Squid或者Nginx作为代理来出去上传数据，那么我文件上传大小的限制可能会在Squid或者Nginx的那些地方设置?

在 GKE 环境中，如果你的 Pod 通过 GCE 中的 Squid 或 Nginx 代理出去上传数据，文件上传大小的限制可能会在 Squid 或 Nginx 的配置中进行设置。

### Squid 代理：

在 Squid 中，文件上传大小的限制通常由以下参数进行控制：

1. **client_request_buffer_max_size:**
   - **定义：** 用于设置 Squid 接受客户端请求的最大缓冲区大小。
   - **设置位置：** Squid 配置文件中，可能是 `squid.conf`。
   - **示例：** `client_request_buffer_max_size 50 MB;` 表示 Squid 将接受最大为 50 兆字节（MB）的客户端请求缓冲区大小。
2. 在 Squid 中，可以通过设置 **maximum_file_size** 参数来限制文件上传大小。
3. maximum_file_size 100m;
注意：Squid 的配置可能因版本而异，因此请查阅相应版本的文档以确认参数的确切名称和用法。

### Nginx 代理：

在 Nginx 中，文件上传大小的限制通常由以下参数进行控制：

1. **client_max_body_size:**
   - **定义：** 用于设置 Nginx 接受客户端请求的最大主体大小。
   - **设置位置：** Nginx 配置文件中，通常在 `nginx.conf` 或站点配置文件中。
   - **示例：** `client_max_body_size 20m;` 表示 Nginx 将接受最大为 20 兆字节（MB）的请求主体。
2. 在 Nginx 中，可以通过设置 **client_max_body_size** 参数来限制文件上传大小。
3. client_max_body_size 100m;


### 总结 

确保在 Squid 或 Nginx 的配置文件中将这些参数设置为你期望的上传文件大小。这样可以确保代理服务器允许足够大的请求主体或缓冲区，以处理你的文件上传。同样，具体的配置可能因版本而异，建议查阅相应版本的文档以确认准确的配置方法。


### 如果在Kubernetes集群内部实现文件上传,还可以在Ingress Controller层面配置最大文件大小限制。
- 例如Nginx Ingress Controller就有client-max-body-size这个配置选项。


# client_max_body_size
https://nginx.org/en/docs/http/ngx_http_core_module.html#client_header_timeout

Syntax:	client_max_body_size size;
Default:	
client_max_body_size 1m;
Context:	http, server, location
Sets the maximum allowed size of the client request body. If the size in a request exceeds the configured value, the 413 (Request Entity Too Large) error is returned to the client. Please be aware that browsers cannot correctly display this error. Setting size to 0 disables checking of client request body size.


client_max_body_size:控制客户端请求主体的最大大小。如果请求主体大于此值,nginx将返回413 Request Entity Too Large错误
这个指令设置了客户端允许发送的最大请求体大小。如果请求的大小超过这个值，Nginx会返回一个"413 Request Entity Too Large"的错误。默认值是1m。例如，client_max_body_size 8m;将允许最大8MB的请求体。

This configuration sets the maximum size of a client's request body that Nginx will accept. The default value is 2048kB. If the request body size exceeds this limit, Nginx will return a 413 (Request Entity Too Large) status code.



# large_client_header_buffers
- nginx.conf
   ```bash
    http {
      include       mime.types;
      default_type  application/octet-stream;
      #increase proxy buffer size
      proxy_buffer_size 32k;
      proxy_buffers 4 128k;
      proxy_busy_buffers_size 256k;
      #increase the header size to 32K
      large_client_header_buffers  4 32k;
    ```
- About client_max_header_size
定义读取大请求头时使用的缓冲区个数和大小。多个缓冲区可以更快地读取大请求头

这个指令在nginx 1.19.7 版本之后就已经废弃了，官方文档也有说明³。这个指令是用来限制HPACK解压后的整个请求头部列表的最大大小的³。现在应该使用large_client_header_buffers 这个指令来代替²³。这个指令是用来设置客户端请求头部的最大数量和每个缓冲区的大小的¹。如果你想了解更多关于这两个指令的用法，你可以参考以下链接¹²³
这个指令来代替²³。这个指令是用来设置客户端请求头部的最大数量和每个缓冲区的大小的
- reference: 
Source: Conversation with Bing, 9/14/2023
(1) Module ngx_http_v2_module - nginx. https://nginx.org/en/docs/http/ngx_http_v2_module.html.
(2) Some obsolete warnings logged #7261 - GitHub. kubernetes/ingress-nginx#7261.
(3) Maximum on HTTP header values? - Stack Overflow. https://stackoverflow.com/questions/686217/maximum-on-http-header-values.
(4) undefined. https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx.
(5) undefined. https://github.com/kubernetes/ingress-nginx/tree/master/charts/ingress-nginx.
- eg:
```
Syntax:	large_client_header_buffers number size;
Default:	
large_client_header_buffers 4 8k;  large_client_header_buffers  4 32k;
Context:	http, server
Sets the maximum number and size of buffers used for reading large client request header.
A request line cannot exceed the size of one buffer, or the 414 (Request-URI Too Large) error is returned to the client.
A request header field cannot exceed the size of one buffer as well, or the 400 (Bad Request) error is returned to the client.
Buffers are allocated only on demand. By default, the buffer size is equal to 8K bytes
If after the end of request processing a connection is transitioned into the keep-alive state, these buffers are released.
设置用于读取大型客户端请求标头的缓冲区的最大数量和大小。 请求行不能超过一个缓冲区的大小，
否则会向客户端返回 414（Request-URI Too Large）错误。 请求头字段也不能超过一个缓冲区的大小，
否则会向客户端返回 400（Bad Request）错误。 缓冲区仅按需分配。 默认情况下，缓冲区大小等于 8K 字节。
如果请求处理结束后连接转换为保持活动状态，则释放这些缓冲区。
```

- summary

large_client_header_buffers 指令会将请求头缓存在内存中，如果请求头超过了任何一个缓冲区的大小，Nginx 将会分多次读取请求头。

因此，如果请求头超过了 large_client_header_buffers 指令配置的值，Nginx 将不会返回 414 Request-URI Too Large 错误，而是会继续读取请求头。

该配置表示 Nginx 将会使用 4 个缓冲区来缓存请求头，每个缓冲区的大小为 4k。如果请求头超过了 4k * 4 = 16k，Nginx 将会分多次读取请求头。



# client_body_buffer_size
读取请求主体时使用的缓冲区大小。根据请求主体的平均大小进行调整,可以优化性能
这个指令设置了在内存中读取请求体的缓冲区大小。如果请求体大于这个缓冲区的大小，Nginx会将其写入到磁盘的临时文件中。例如，client_body_buffer_size 128k;设置了128KB的缓冲区大小
- eg
```bash
https://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_buffer_size

Sets buffer size for reading client request body. In case the request body is larger than the buffer, 
the whole body or only its part is written to a temporary file. By default, buffer size is equal to two memory pages. 
This is 8K on x86, other 32-bit platforms, and x86-64. It is usually 16K on other 64-bit platforms.
```

如果设置的 client_body_buffer_size 大于客户端请求正文的大小，则整个请求正文都将存储在缓冲区中。但是，如果请求正文大于缓冲区的大小，nginx就会把多余的数据写入临时文件。

需要注意的是，client_body_buffer_size指令只影响客户端请求正文的缓冲，而不影响响应的缓冲

# client_header_buffer_size
读取请求头时使用的缓冲区大小。根据请求头的平均大小进行调整,可以优化性能
Syntax:	client_header_buffer_size size;
Default:	
client_header_buffer_size 1k;
Context:	http, server
Sets buffer size for reading client request header. For most requests, a buffer of 1K bytes is enough. However, 
if a request includes long cookies, or comes from a WAP client, it may not fit into 1K. 
If a request line or a request header field does not fit into this buffer then larger buffers, 
configured by the large_client_header_buffers directive, are allocated.



# Testing
```bash
## 发送一个大小为100MB的请求主体
curl -X POST -d @100MB.file http://localhost/upload

## 设置请求头的大小为16KB 
curl -H "Large: $(perl -e 'print "a"x16384') http://localhost/
使用perl在运行时生成一个约16KB大小的大请求头large_header,然后在curl命令中使用-H参数将这个头部附加到请求中

## 设置请求主体的最大大小为1MB
curl --limit-rate 1M -T file.txt http://localhost/upload


使用curl工具模拟发送大头部POST请求的方法很好,我来补充一下具体的命令示例:

# 生成一个大约16KB的请求头 
large_header=$(perl -e 'print "X-Large: " . "a" x 16384')

# 使用curl发送POST请求,头部包含刚刚生成的large_header
curl -H "$large_header" -X POST http://example.com/api/post
```

- 直接用Shell脚本来生成大请求头并通过curl发送,无需借助其他语言如Perl。下面是使用Shell实现的示例:
```
# 生成16KB大小的请求头
large_header=$(printf 'X-Large: %0.s' {1..2048}) 

# 发送POST请求,带有我们构造的大请求头
curl -H "$large_header" -X POST http://example.com/api/post
这里我们使用printf命令可以轻松生成自定义大小的字符串,作为请求头的值。

然后在curl命令中通过-H参数传递这个大请求头。

这样就避免了使用其他语言来生成大字符串的复杂性。利用Shell自身的字符串处理功能就可以实现构造大请求头并测试。


用curl工具来模拟发送包含大请求体(body)的HTTP请求


具体的命令示例:

# 生成一个100MB大小的大文件big.bin
dd if=/dev/urandom of=big.bin bs=100M count=1

# 用curl发送POST请求,请求体来自刚生成的大文件
curl -T big.bin http://example.com/upload
首先我们使用dd命令生成一个100MB的大文件big.bin。

然后在curl命令中使用-T参数指定这个大文件作为请求体发送出去。


使用curl工具模拟发送大请求体(large body)的POST请求的示例:

# 生成一个10MB大小的大文件large_file.bin
dd if=/dev/urandom of=large_file.bin bs=10M count=1

# 使用curl发送POST请求,请求体来自上面生成的大文件
curl -T large_file.bin -H "Content-Type: application/octet-stream" http://example.com/upload
这里我们首先用dd命令生成一个10MB大小的大文件large_file.bin。

然后使用curl的-T参数指定这个文件作为POST请求的请求体发送出去。

同时设置Content-Type头表明是二进制 octet stream类型。

如果example.com服务器对请求体大小有限制,比如最大10MB,那么就会返回类似"413 Entity Too Large"的错误信息。

通过这种方式,我们可以定制不同大小的请求体文件来测试服务器处理请求的能力。

```

# client_max_body_size
https://nginx.org/en/docs/http/ngx_http_core_module.html#client_header_timeout

Syntax:	client_max_body_size size;
Default:	
client_max_body_size 1m;
Context:	http, server, location
Sets the maximum allowed size of the client request body. If the size in a request exceeds the configured value, the 413 (Request Entity Too Large) error is returned to the client. Please be aware that browsers cannot correctly display this error. Setting size to 0 disables checking of client request body size.


client_max_body_size:控制客户端请求主体的最大大小。如果请求主体大于此值,nginx将返回413 Request Entity Too Large错误
这个指令设置了客户端允许发送的最大请求体大小。如果请求的大小超过这个值，Nginx会返回一个"413 Request Entity Too Large"的错误。默认值是1m。例如，client_max_body_size 8m;将允许最大8MB的请求体。

This configuration sets the maximum size of a client's request body that Nginx will accept. The default value is 2048kB. If the request body size exceeds this limit, Nginx will return a 413 (Request Entity Too Large) status code.



# large_client_header_buffers
- nginx.conf
   ```bash
    http {
      include       mime.types;
      default_type  application/octet-stream;
      #increase proxy buffer size
      proxy_buffer_size 32k;
      proxy_buffers 4 128k;
      proxy_busy_buffers_size 256k;
      #increase the header size to 32K
      large_client_header_buffers  4 32k;
    ```
- About client_max_header_size
定义读取大请求头时使用的缓冲区个数和大小。多个缓冲区可以更快地读取大请求头

这个指令在nginx 1.19.7 版本之后就已经废弃了，官方文档也有说明³。这个指令是用来限制HPACK解压后的整个请求头部列表的最大大小的³。现在应该使用large_client_header_buffers 这个指令来代替²³。这个指令是用来设置客户端请求头部的最大数量和每个缓冲区的大小的¹。如果你想了解更多关于这两个指令的用法，你可以参考以下链接¹²³
这个指令来代替²³。这个指令是用来设置客户端请求头部的最大数量和每个缓冲区的大小的
- reference: 
Source: Conversation with Bing, 9/14/2023
(1) Module ngx_http_v2_module - nginx. https://nginx.org/en/docs/http/ngx_http_v2_module.html.
(2) Some obsolete warnings logged #7261 - GitHub. kubernetes/ingress-nginx#7261.
(3) Maximum on HTTP header values? - Stack Overflow. https://stackoverflow.com/questions/686217/maximum-on-http-header-values.
(4) undefined. https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx.
(5) undefined. https://github.com/kubernetes/ingress-nginx/tree/master/charts/ingress-nginx.
- eg:
```
Syntax:	large_client_header_buffers number size;
Default:	
large_client_header_buffers 4 8k;  large_client_header_buffers  4 32k;
Context:	http, server
Sets the maximum number and size of buffers used for reading large client request header.
A request line cannot exceed the size of one buffer, or the 414 (Request-URI Too Large) error is returned to the client.
A request header field cannot exceed the size of one buffer as well, or the 400 (Bad Request) error is returned to the client.
Buffers are allocated only on demand. By default, the buffer size is equal to 8K bytes
If after the end of request processing a connection is transitioned into the keep-alive state, these buffers are released.
设置用于读取大型客户端请求标头的缓冲区的最大数量和大小。 请求行不能超过一个缓冲区的大小，
否则会向客户端返回 414（Request-URI Too Large）错误。 请求头字段也不能超过一个缓冲区的大小，
否则会向客户端返回 400（Bad Request）错误。 缓冲区仅按需分配。 默认情况下，缓冲区大小等于 8K 字节。
如果请求处理结束后连接转换为保持活动状态，则释放这些缓冲区。
```

- summary

large_client_header_buffers 指令会将请求头缓存在内存中，如果请求头超过了任何一个缓冲区的大小，Nginx 将会分多次读取请求头。

因此，如果请求头超过了 large_client_header_buffers 指令配置的值，Nginx 将不会返回 414 Request-URI Too Large 错误，而是会继续读取请求头。

该配置表示 Nginx 将会使用 4 个缓冲区来缓存请求头，每个缓冲区的大小为 4k。如果请求头超过了 4k * 4 = 16k，Nginx 将会分多次读取请求头。



# client_body_buffer_size
读取请求主体时使用的缓冲区大小。根据请求主体的平均大小进行调整,可以优化性能
这个指令设置了在内存中读取请求体的缓冲区大小。如果请求体大于这个缓冲区的大小，Nginx会将其写入到磁盘的临时文件中。例如，client_body_buffer_size 128k;设置了128KB的缓冲区大小
- eg
```bash
https://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_buffer_size

Sets buffer size for reading client request body. In case the request body is larger than the buffer, 
the whole body or only its part is written to a temporary file. By default, buffer size is equal to two memory pages. 
This is 8K on x86, other 32-bit platforms, and x86-64. It is usually 16K on other 64-bit platforms.
```

如果设置的 client_body_buffer_size 大于客户端请求正文的大小，则整个请求正文都将存储在缓冲区中。但是，如果请求正文大于缓冲区的大小，nginx就会把多余的数据写入临时文件。

需要注意的是，client_body_buffer_size指令只影响客户端请求正文的缓冲，而不影响响应的缓冲

# client_header_buffer_size
读取请求头时使用的缓冲区大小。根据请求头的平均大小进行调整,可以优化性能
Syntax:	client_header_buffer_size size;
Default:	
client_header_buffer_size 1k;
Context:	http, server
Sets buffer size for reading client request header. For most requests, a buffer of 1K bytes is enough. However, 
if a request includes long cookies, or comes from a WAP client, it may not fit into 1K. 
If a request line or a request header field does not fit into this buffer then larger buffers, 
configured by the large_client_header_buffers directive, are allocated.



# Testing
```bash
## 发送一个大小为100MB的请求主体
curl -X POST -d @100MB.file http://localhost/upload

## 设置请求头的大小为16KB 
curl -H "Large: $(perl -e 'print "a"x16384') http://localhost/
使用perl在运行时生成一个约16KB大小的大请求头large_header,然后在curl命令中使用-H参数将这个头部附加到请求中

## 设置请求主体的最大大小为1MB
curl --limit-rate 1M -T file.txt http://localhost/upload


使用curl工具模拟发送大头部POST请求的方法很好,我来补充一下具体的命令示例:

# 生成一个大约16KB的请求头 
large_header=$(perl -e 'print "X-Large: " . "a" x 16384')

# 使用curl发送POST请求,头部包含刚刚生成的large_header
curl -H "$large_header" -X POST http://example.com/api/post
```

- 直接用Shell脚本来生成大请求头并通过curl发送,无需借助其他语言如Perl。下面是使用Shell实现的示例:
```
# 生成16KB大小的请求头
large_header=$(printf 'X-Large: %0.s' {1..2048}) 

# 发送POST请求,带有我们构造的大请求头
curl -H "$large_header" -X POST http://example.com/api/post
这里我们使用printf命令可以轻松生成自定义大小的字符串,作为请求头的值。

然后在curl命令中通过-H参数传递这个大请求头。

这样就避免了使用其他语言来生成大字符串的复杂性。利用Shell自身的字符串处理功能就可以实现构造大请求头并测试。


用curl工具来模拟发送包含大请求体(body)的HTTP请求


具体的命令示例:

# 生成一个100MB大小的大文件big.bin
dd if=/dev/urandom of=big.bin bs=100M count=1

# 用curl发送POST请求,请求体来自刚生成的大文件
curl -T big.bin http://example.com/upload
首先我们使用dd命令生成一个100MB的大文件big.bin。

然后在curl命令中使用-T参数指定这个大文件作为请求体发送出去。


使用curl工具模拟发送大请求体(large body)的POST请求的示例:

# 生成一个10MB大小的大文件large_file.bin
dd if=/dev/urandom of=large_file.bin bs=10M count=1

# 使用curl发送POST请求,请求体来自上面生成的大文件
curl -T large_file.bin -H "Content-Type: application/octet-stream" http://example.com/upload
这里我们首先用dd命令生成一个10MB大小的大文件large_file.bin。

然后使用curl的-T参数指定这个文件作为POST请求的请求体发送出去。

同时设置Content-Type头表明是二进制 octet stream类型。

如果example.com服务器对请求体大小有限制,比如最大10MB,那么就会返回类似"413 Entity Too Large"的错误信息。

通过这种方式,我们可以定制不同大小的请求体文件来测试服务器处理请求的能力。

```
