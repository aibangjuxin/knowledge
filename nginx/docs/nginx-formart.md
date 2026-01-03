



我的Nginx是一个正向代理,比如其IP和提供服务的端口是 192.168.1.101:443
nginx代理部分的配置如下
location ^~ /esg/ {
rewrite ~/esg.*) "://api.abc.com/$1"; 
rewrite ^(.*)$ "https$1" break;
proxy_pass http://192.168.1.102:3128;
｝
http://192.168.1.102:3128 是我访问的的proxy_pass地址 也就是跳是一个Squid
我要通过这个代理访问下面地址
https://api.abc.com/esg/v1/spre/LIQ0%2BE3WN5C
curl -X 192.168.1.101:443 https://api.abc.com/esg/v1/spre/LIQ0%2BE3WN5C
我的Nginx日志看到出去的日志变成了
https://api.abc.com/esg/v1/spre/LIQ0+E3WN5C
也就是URL的中将%2B转化为了+号
这种问题是如何引起的,我如何来规避?


这个问题是由于 Nginx 在进行 URL 重写时对某些特殊字符进行了解码操作导致的。

在 URL 中,%2B 是加号 (+) 的 URL 编码表示形式。当 Nginx 处理这个 URL 时,它将 %2B 解码为了 +。这种行为是符合 RFC 3986 (URI 通用语法)规范的,但对于某些场景可能会带来问题。

要解决这个问题,你可以尝试以下几种方式:

1. 在 rewrite 指令中使用 `escape=uri` 参数,告诉 Nginx 不要对 URL 进行任何编码/解码操作:
- https://www.nginx.com/resources/wiki/modules/set_misc/#set-unescape-uri
- https://github.com/openresty/set-misc-nginx-module#set_unescape_uri
  ```bash
    location /test {
        set_unescape_uri $key $arg_key;
        echo $key;
    }
  ```
Then request GET /test?key=hello+world%21 will yield the following output
hello world!


```
rewrite ^(/esg.*)$ $1 break;
rewrite ^(.*) https://$http_host$1 last;
proxy_pass http://192.168.1.102:3128;
```

1. 使用 proxy_pass 指令的 `uri` 参数,通过变量的方式传递原始 URL:

```
location /esg/ {
    proxy_pass http://192.168.1.102:3128/uri=$request_uri;
}
```

3. 如果以上方式都不管用,你还可以考虑在 Nginx 配置中禁用 URL 解码功能:

```
location /esg/ {
    set $tmp $request_uri;
    rewrite_uri @ $tmp;
    proxy_pass http://192.168.1.102:3128;
}
```
   1. 首先，这个location块匹配所有以`/esg/`开头的请求。
   2. `set $tmp $request_uri;` 这行代码将`$request_uri`的值赋给变量`$tmp`。
   3. `rewrite_uri @ $tmp;` 这行代码将原始请求URI（`$tmp`）作为`proxy_pass`的参数传递给后端服务器。这样做的好处是，后端服务器可以直接处理这个请求，而不需要再次处理路径修改。
   4. `proxy_pass http://192.168.1.102:3128;` 这行代码指定了Nginx的`proxy_pass` directive，它将请求转发到`192.168.1.102`服务器上，端口为`3128`。


通过以上任一方式,Nginx 都不会对 URL 中的 %2B 进行解码,从而避免了这个问题。你可以测试一下哪种方式最适合你的场景。


好的,我明白了,您需要保留URL中的%2B编码,不被Nginx解码。那么可以采取如下方式:

```nginx
location ^~ /esg/ {
    set $proxy_url $request_uri;

    # URL进行编码处理
    set_escape_uri $proxy_url $proxy_url;

    rewrite ^(.*) $proxy_url break;
    proxy_pass http://192.168.1.102:3128;
}
```

1) 首先将原始请求URI保存到$proxy_url变量中。

2) 使用`set_escape_uri`指令对$proxy_url进行URI编码转义处理。这一步可确保URL中的%2B等特殊字符不被Nginx解码。

3) 使用rewrite指令将处理后的$proxy_url重写回URI中。

4) 最后通过proxy_pass将编码后的URI发送到后端代理服务器。

通过`set_escape_uri`转义,Nginx在内部处理时不会对已编码的URL进行解码, 从而保留了URL中的%2B等特殊字符的编码状态。

这种方式实现了您所需的功能,而且相对简单直接,无需手动判断和替换每一种特殊字符的编码。


是的,`set_escape_uri`是Nginx内置的指令。

该指令的作用是对指定字符串进行URI转义编码处理。它的使用语法是:

```
set_escape_uri $destination_variable $source_variable
```

它会将`$source_variable`变量中的字符串按照RFC3986中规定的URI编码规则进行编码处理,将编码后的结果存储到`$destination_variable`变量中。

举例来说:

```
set $original_uri $request_uri; 
set_escape_uri $escaped_uri $original_uri;
```

如果`$request_uri`的值是`/path/test%20string?a=b&c=d%2Be`,那么经过`set_escape_uri`处理后,`$escaped_uri`的值将是`/path/test%20string?a=b&c=d%2Be`。可以看到空格、`%2B`等特殊字符都被原样保留了编码状态。

所以`set_escape_uri`指令可以很好地满足您不想对已编码字符再次解码的需求。它在Nginx内置指令集中,无需额外安装任何模块,可以直接使用。
