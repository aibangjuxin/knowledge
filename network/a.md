
```bash
$ curl -v recaptchaenterprise.googleapis.com:443 -x my.squid.proxy.aibang:3128
* Trying 192.168.1.133:3128...
* Connected to my.squid.proxy.aibang (192.168.1.133) port 3128 (#0)
> GET http://recaptchaenterprise.googleapis.com:443/ HТТР/1.1
> Host: recaptchaenterprise.googleapis.com: 443
> User-Agent: curl/8.1.2
› Accept: */*
> Proxy-Connection: Keep-Alive
>
< НTTP/1.1 502 Bad Gateway
< Server: squid/4.15
< Mime-Version: 1.0
< Date: Wed, 12 Feb 2025 09:59:59 GMT
Content-Type: text/html;charset=utf-8
‹ Content-Length: 3597
X-Squid-Error: ERR_ZERO_SIZE_OBJECT o
< Vary: Accept-Language < Content-Language: en
< X-Cache: MISS from proxy-instance < X-Cache-Lookup: MISS from proxy-instance: 3128
‹ Via: 1.1 proxy-instance (squid/4.15)
< Connection: keep-alive
```
---
```bash
$ curl -v https://recaptchaenterprise.googleapis.com:443 -x my.squid.proxy.aibang:3128
* Trying 192.168.1.133:3128...
* Connected to my.squid.proxy.aibang (192.168.1.133) port 3128 (#0)
* CONNECT tunnel: HTTP/1.1 negotiated
* allocate connect buffer
* Establish HTTP proxy tunnel to recaptchaenterprise.googleapis.com:443
> CONNECT recaptchaenterprise.googleapis.com:443 HTTP/1.1
> Host: recaptchaenterprise.googleapis.com:443
> User-Agent: curl/8.1.2
> Proxy-Connection: Keep-Alive
>

< HTTP/1.1 200 Connection established
<
* CONNECT phase completed
* CONNECT tunnel established, response 200
* schannel: disabled automatic use of client certificate
* using HTTP/1.x
> GET / HTTP/1.1
> Host: recaptchaenterprise.googleapis.com
> User-Agent: curl/8.1.2
> Accept: */*
>

< HTTP/1.1 404 Not Found
< Date: Wed, 12 Feb 2025 10:28:17 GMT
< Content-Type: text/html; charset=UTF-8
< Server: scaffolding on HTTPServer2
< Content-Length: 1561
< X-XSS-Protection: 0
< X-Frame-Options: SAMEORIGIN
< X-Content-Type-Options: nosniff
<
```

