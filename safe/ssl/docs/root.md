您提出了一个非常好的问题，涉及到了数字证书体系的核心概念。让我详细解释一下根证书的概念，以及为什么一些公司选择维护自己的根证书。

1. 根证书的定义：
根证书（Root Certificate）是公钥基础设施（PKI）中最顶层的证书。它是自签名的，也就是说，它由自己签发和认证。根证书是信任链的起点，用于签发其他证书。

2. 根证书的作用：
- 作为信任的锚点（Trust Anchor）
- 用于签发中间证书或直接签发终端实体证书
- 验证其他证书的有效性

3. 公共根证书：
通常，我们的设备和操作系统预装了一些知名的、被广泛信任的根证书，如 DigiCert、Verisign 等机构的根证书。这些根证书被用来验证我们日常访问的大多数网站的证书。

4. 企业自定义根证书：
确实，安全性要求较高的公司常常会选择维护自己的根证书。这种做法被称为建立私有 PKI（Private Public Key Infrastructure）。

5. 为什么公司要维护自己的根证书：
   a. 增强安全控制：公司可以完全控制证书的签发和撤销过程。
   b. 成本效益：对于大型组织，长期来看可能比购买商业证书更经济。
   c. 自定义策略：可以根据公司特定需求制定证书策略。
   d. 隐私保护：避免依赖外部机构，减少信息泄露风险。
   e. 内部系统专用：特别适用于不需要被公众访问的内部系统。

6. 实施自定义根证书的注意事项：
   a. 需要高度的安全措施来保护根证书私钥。
   b. 要在所有需要使用的设备和系统中安装根证书。
   c. 需要建立完整的证书管理流程，包括签发、更新、撤销等。
   d. 可能需要专门的人员和资源来管理 PKI 系统。

7. 自定义根证书的应用场景：
   - 企业内部网络和应用
   - VPN 和远程访问系统
   - 内部邮件服务器
   - 代码签名
   - 物联网设备管理

8. 潜在的挑战：
   - 在外部系统或公共网络中使用自定义根证书可能会导致信任问题。
   - 需要确保根证书不被滥用，避免成为安全隐患。

总结：
维护自己的根证书确实是一种提高安全性和控制力的方法，特别适合对安全性要求较高的组织。但这也需要大量的专业知识和资源投入。对于大多数公共服务，仍然建议使用受信任的公共证书颁发机构（CA）的证书，因为这些证书在各种客户端设备上都能得到广泛认可。

如果您考虑为您的组织实施自定义根证书，我建议您仔细评估需求和风险，可能还需要咨询安全专家的意见。如果您想了解更多关于如何实施或管理自定义根证书的具体步骤，我很乐意提供更多信息。​​​​​​​​​​​​​​​​


# 企业证书和公共证书的一些辨别 

确实，企业证书和公共根证书可能会有一些重叠，尤其是在大型组织中。分析和比较这些证书是一个重要的安全实践。我会提供一个使用 shell 脚本来比较两个证书的方法。

首先，让我解释一下证书的结构和比较的关键点：

1. 证书结构：
   - 版本号
   - 序列号
   - 签名算法
   - 颁发者
   - 有效期
   - 主题
   - 公钥信息
   - 扩展信息

2. 比较的关键点：
   - 颁发者（Issuer）
   - 主题（Subject）
   - 公钥
   - 有效期
   - 扩展信息

现在，我们来创建一个 shell 脚本来比较两个证书：



```bash
#!/bin/bash

# 检查输入参数
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <certificate1> <certificate2>"
    exit 1
fi

cert1="$1"
cert2="$2"

# 函数：提取证书信息
extract_info() {
    local cert="$1"
    local field="$2"
    openssl x509 -in "$cert" -noout -$field 2>/dev/null
}

# 比较函数
compare_field() {
    local field="$1"
    local value1=$(extract_info "$cert1" "$field")
    local value2=$(extract_info "$cert2" "$field")
    
    if [ "$value1" = "$value2" ]; then
        echo "$field: 相同"
    else
        echo "$field: 不同"
        echo "  证书1: $value1"
        echo "  证书2: $value2"
    fi
}

# 主要比较逻辑
echo "比较证书: $cert1 和 $cert2"
echo "----------------------------------------"

compare_field "subject"
compare_field "issuer"
compare_field "startdate"
compare_field "enddate"
compare_field "pubkey"

# 比较扩展信息
extensions1=$(openssl x509 -in "$cert1" -noout -text | grep -A100 "X509v3 extensions:" | grep "X509v3")
extensions2=$(openssl x509 -in "$cert2" -noout -text | grep -A100 "X509v3 extensions:" | grep "X509v3")

if [ "$extensions1" = "$extensions2" ]; then
    echo "扩展信息: 相同"
else
    echo "扩展信息: 不同"
    echo "  证书1 扩展:"
    echo "$extensions1"
    echo "  证书2 扩展:"
    echo "$extensions2"
fi

# 比较指纹
echo "----------------------------------------"
echo "SHA1 指纹比较:"
openssl x509 -noout -fingerprint -sha1 -in "$cert1"
openssl x509 -noout -fingerprint -sha1 -in "$cert2"

```

这个脚本会比较两个证书的以下方面：
1. 主题（Subject）
2. 颁发者（Issuer）
3. 有效期起始日期
4. 有效期结束日期
5. 公钥
6. 扩展信息
7. SHA1 指纹

使用方法：
1. 将脚本保存为 `compare_certs.sh`
2. 给脚本添加执行权限：`chmod +x compare_certs.sh`
3. 运行脚本：`./compare_certs.sh certificate1.pem certificate2.pem`

这个脚本将帮助您快速识别两个证书之间的异同。对于相同的字段，它会显示"相同"；对于不同的字段，它会显示两个证书的具体值。

一些注意事项：
1. 这个脚本假设证书是 PEM 格式的。如果您的证书是其他格式，可能需要先转换。
2. 脚本使用 openssl 命令，确保您的系统已安装 openssl。
3. 对于更复杂的比较（如特定的扩展字段），可能需要进一步改进脚本。

使用这个脚本，您可以快速了解企业证书和公共根证书的异同。如果发现重要字段（如颁发者或主题）相同，那么这两个证书可能有重叠或关联。


# Mac request baidu 

```bash
$ curl -v https://www.baidu.com
* Host www.baidu.com:443 was resolved.
* IPv6: (none)
* IPv4: 183.2.172.42, 183.2.172.185
*   Trying 183.2.172.42:443...
* Connected to www.baidu.com (183.2.172.42) port 443
* ALPN: curl offers h2,http/1.1
* (304) (OUT), TLS handshake, Client hello (1):
*  CAfile: /etc/ssl/cert.pem
*  CApath: none
* (304) (IN), TLS handshake, Server hello (2):
* TLSv1.2 (IN), TLS handshake, Certificate (11):
* TLSv1.2 (IN), TLS handshake, Server key exchange (12):
* TLSv1.2 (IN), TLS handshake, Server finished (14):
* TLSv1.2 (OUT), TLS handshake, Client key exchange (16):
* TLSv1.2 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.2 (OUT), TLS handshake, Finished (20):
* TLSv1.2 (IN), TLS change cipher, Change cipher spec (1):
* TLSv1.2 (IN), TLS handshake, Finished (20):
* SSL connection using TLSv1.2 / ECDHE-RSA-AES128-GCM-SHA256 / [blank] / UNDEF
* ALPN: server accepted http/1.1
* Server certificate:
*  subject: C=CN; ST=beijing; L=beijing; O=Beijing Baidu Netcom Science Technology Co., Ltd; CN=baidu.com
*  start date: Jul  8 01:41:02 2024 GMT
*  expire date: Aug  9 01:41:01 2025 GMT
*  subjectAltName: host "www.baidu.com" matched cert's "*.baidu.com"
*  issuer: C=BE; O=GlobalSign nv-sa; CN=GlobalSign RSA OV SSL CA 2018
*  SSL certificate verify ok.
* using HTTP/1.x
> GET / HTTP/1.1
> Host: www.baidu.com
> User-Agent: curl/8.6.0
> Accept: */*
>
< HTTP/1.1 200 OK
< Accept-Ranges: bytes
< Cache-Control: private, no-cache, no-store, proxy-revalidate, no-transform
< Connection: keep-alive
< Content-Length: 2443
< Content-Type: text/html
< Date: Fri, 09 Aug 2024 12:37:45 GMT
< Etag: "58860401-98b"
< Last-Modified: Mon, 23 Jan 2017 13:24:17 GMT
< Pragma: no-cache
< Server: bfe/1.0.8.18
< Set-Cookie: BDORZ=27315; max-age=86400; domain=.baidu.com; path=/
<
<!DOCTYPE html>
<!--STATUS OK--><html> <head><meta http-equiv=content-type content=text/html;charset=utf-8><meta http-equiv=X-UA-Compatible content=IE=Edge><meta content=always name=referrer><link rel=stylesheet type=text/css href=https://ss1.bdstatic.com/5eN1bjq8AAUYm2zgoY3K/r/www/cache/bdorz/baidu.min.css><title>百度一下，你就知道</title></head> <body link=#0000cc> <div id=wrapper> <div id=head> <div class=head_wrapper> <div class=s_form> <div class=s_form_wrapper> <div id=lg> <img hidefocus=true src=//www.baidu.com/img/bd_logo1.png width=270 height=129> </div> <form id=form name=f action=//www.baidu.com/s class=fm> <input type=hidden name=bdorz_come value=1> <input type=hidden name=ie value=utf-8> <input type=hidden name=f value=8> <input type=hidden name=rsv_bp value=1> <input type=hidden name=rsv_idx value=1> <input type=hidden name=tn value=baidu><span class="bg s_ipt_wr"><input id=kw name=wd class=s_ipt value maxlength=255 autocomplete=off autofocus=autofocus></span><span class="bg s_btn_wr"><input type=submit id=su value=百度一下 class="bg s_btn" autofocus></span> </form> </div> </div> <div id=u1> <a href=http://news.baidu.com name=tj_trnews class=mnav>新闻</a> <a href=https://www.hao123.com name=tj_trhao123 class=mnav>hao123</a> <a href=http://map.baidu.com name=tj_trmap class=mnav>地图</a> <a href=http://v.baidu.com name=tj_trvideo class=mnav>视频</a> <a href=http://tieba.baidu.com name=tj_trtieba class=mnav>贴吧</a> <noscript> <a href=http://www.baidu.com/bdorz/login.gif?login&amp;tpl=mn&amp;u=http%3A%2F%2Fwww.baidu.com%2f%3fbdorz_come%3d1 name=tj_login class=lb>登录</a> </noscript> <script>document.write('<a href="http://www.baidu.com/bdorz/login.gif?login&tpl=mn&u='+ encodeURIComponent(window.location.href+ (window.location.search === "" ? "?" : "&")+ "bdorz_come=1")+ '" name="tj_login" class="lb">登录</a>');
                </script> <a href=//www.baidu.com/more/ name=tj_briicon class=bri style="display: block;">更多产品</a> </div> </div> </div> <div id=ftCon> <div id=ftConw> <p id=lh> <a href=http://home.baidu.com>关于百度</a> <a href=http://ir.baidu.com>About Baidu</a> </p> <p id=cp>&copy;2017&nbsp;Baidu&nbsp;<a href=http://www.baidu.com/duty/>使用百度前必读</a>&nbsp; <a href=http://jianyi.baidu.com/ class=cp-feedback>意见反馈</a>&nbsp;京ICP证030173号&nbsp; <img src=//www.baidu.com/img/gs.gif> </p> </div> </div> </div> </body> </html>
* Connection #0 to host www.baidu.com left intact
```