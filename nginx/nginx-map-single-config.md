- [1. 主配置文件 (`nginx.conf`)](#1-主配置文件-nginxconf)
- [2. IP白名单配置文件 (`geo.txt`)](#2-ip白名单配置文件-geotxt)
- [3. 客户端证书公用名称映射配置文件 (`dev-sgpoet-client.domain.aibang.conf`)](#3-客户端证书公用名称映射配置文件-dev-sgpoet-clientdomainaibangconf)
- [特定URL路径的配置 (`/etc/nginx/conf.d/urlpath-v1.conf`)](#特定url路径的配置-etcnginxconfdurlpath-v1conf)
- [第一段：`map $ssl_client_s_dn $ssl_client_s_dn_cn`](#第一段map-ssl_client_s_dn-ssl_client_s_dn_cn)
- [第二段：`geo $proxy_protocol_addr $urlpath-v1`](#第二段geo-proxy_protocol_addr-urlpath-v1)
- [第三段：`map $ssl_client_s_dn_cn $urlpath-v1-CN`](#第三段map-ssl_client_s_dn_cn-urlpath-v1-cn)
1. **客户端证书验证**：通过检查 SSL 客户端证书的公用名称（CN），以确保只有具有有效证书的客户端可以访问服务。这是通过在 `$ssl_client_s_dn`（客户端证书的主题名称）和 `$ssl_client_s_dn_cn`（从证书中提取的CN）之间使用 `map` 指令实现的。

2. **IP白名单验证**：使用 `geo` 指令基于客户端的 IP 地址进行验证，只有在白名单中的 IP 地址才被允许访问。

3. **访问控制**：通过结合客户端证书的公用名称和来源 IP 地址的验证，来决定是否允许访问。如果客户端不在IP白名单中，或者其证书的CN不在允许的列表中，Nginx 将返回错误状态码（406或409），从而拒绝访问。

4. **请求转发**：对于通过验证的请求，Nginx 将重写请求的 URL 并将其代理转发到内部服务器地址（如 `http://internal:3128`）。

这种配置在保护敏感服务时非常有用，因为它确保了只有经过严格验证的客户端才能访问这些服务，从而提供了双重的安全措施：证书验证和源IP验证。此外，这种配置支持将安全规则集中管理，便于维护和更新。

根据您的需求，我们将创建三个配置文件：
1. `nginx.conf`：主配置文件。
2. `geo.txt`：独立的IP白名单配置文件。
3. `dev-sgpoet-client.domain.aibang.conf`：独立的客户端证书公用名称映射配置文件。

在 `nginx.conf` 主配置文件中，我们使用 `include` 指令来包含其他配置文件。这样做可以更好地组织和维护配置，使其更模块化。

### 1. 主配置文件 (`nginx.conf`)

```nginx
http {
    # 主配置文件中已存在的映射
    map $ssl_client_s_dn $ssl_client_s_dn_cn {
        default "";
        ~(^|,)CN=(?<CN>[^,]+) $CN;
    }

    # 包含其他配置文件
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/geo.txt;
    include /etc/nginx/dev-sgpoet-client.domain.aibang.conf;

    # 服务器配置
    server {
        listen 80;
        listen 443 ssl;
        # 其他通用配置
        # ...
        
        # 特定URL路径的配置
        include /etc/nginx/conf.d/urlpath-v1.conf;
    }
}
```

### 2. IP白名单配置文件 (`geo.txt`)

```nginx
# IP白名单配置
geo $proxy_protocol_addr $urlpath-v1 {                                                                                                             
    default 0;
    119.112.80.0/20 1; ## AIBANG Global External IP Range
    27.110.72.0/21 1; ## AIBANG Global External IP Range
    # 更多允许的IP地址或CIDR
}
```

### 3. 客户端证书公用名称映射配置文件 (`dev-sgpoet-client.domain.aibang.conf`)

```nginx
# 客户端证书公用名称映射配置
map $ssl_client_s_dn_cn $urlpath-v1-CN {                                                                                                             
    default 0;
    dev-sgpoet-client.domain.aibang 1; # 允许特定客户端证书
    # 更多允许的客户端证书公用名称
}
```

### 特定URL路径的配置 (`/etc/nginx/conf.d/urlpath-v1.conf`)

```nginx
location /urlpath/v1/ {
  sendfile        on;
  tcp_nopush      on;
  client_max_body_size 5M; # 限制上传文件大小

  if ($ssl_client_verify != SUCCESS) {
    return 403; # SSL证书验证不成功时返回403
  }

  # 客户端证书公用名称验证
  if ($urlpath-v1-CN = 0 ) {
    return 406; # 不允许的客户端证书公用名称返回406
  }

  # IP白名单验证
  if ($urlpath-v1 = 0 ) {
    return 409; # 不在IP白名单内返回409
  } 

  rewrite ^(.*)$ "://dev.domain.aibang$1";
  rewrite ^(.*)$ "https$1" break;
  proxy_pass http://internal:3128; # 内部代理配置
}
```

**配置说明：**

- `nginx.conf` 是Nginx的主配置文件，用于定义全局设置，并通过 `include` 指令包含其他配置文件。
- `geo.txt` 配置文件定义了一个 `geo` 指令块，它根据客户端的IP地址设置 `$urlpath-v1` 变量。如果客户端IP不在指定的范围内，则变量值为0，否则为1。
- `dev-sgpoet-client.domain.aibang.conf` 定义了一个 `map` 指令块，用于将SSL客户端证书的公用名称映射到 `$urlpath-v1-CN` 变量。如果证书公用名称不匹配，则变量值为0。
- `/etc/nginx/conf.d/urlpath-v1.conf` 是针对特定URL路径 `/urlpath/v1/`的配置。在这里，我们进行SSL客户端验证和IP白名单验证，并根据验证结果决定是否允许访问。
请根据您的实际环境更新上述配置文件中的IP地址、CIDR和证书公用名称，并确保文件路径与您的Nginx环境一致。此外，您需要确保 ssl_client_verify 和 ssl_client_s_dn_cn 等变量在您的Nginx版本中可用。

当然，我将为您详细解释每一段 `map` 指令的配置：

### 第一段：`map $ssl_client_s_dn $ssl_client_s_dn_cn`

```nginx
map $ssl_client_s_dn $ssl_client_s_dn_cn {
    default "";
    ~(^|,)CN=(?<CN>[^,]+) $CN;
}
```

**解释：**
- 这段配置定义了一个变量 `$ssl_client_s_dn_cn`，它基于另一个变量 `$ssl_client_s_dn` 的值来设定。
- `$ssl_client_s_dn` 通常包含SSL客户端证书的主题名称，即客户端证书中定义的 `subjectDN` 字段。
- 这段 `map` 块使用正则表达式来匹配 `$ssl_client_s_dn` 中的公用名称（Common Name，简称CN）。正则表达式 `~(^|,)CN=(?<CN>[^,]+)` 查找以CN=开始的字符串，并捕获等号后面的内容到一个命名捕获组 `CN`。
- 如果找到匹配的CN，`$ssl_client_s_dn_cn` 将被设定为该CN值；如果没有找到，`$ssl_client_s_dn_cn` 默认为空字符串（`""`）。

### 第二段：`geo $proxy_protocol_addr $urlpath-v1`

```nginx
geo $proxy_protocol_addr $urlpath-v1 {                                                                                                             
    default 0;
    119.112.80.0/20 1; ## AIBANG Global External IP Range
    27.110.72.0/21 1; ## AIBANG Global External IP Range
    # 更多允许的IP地址或CIDR
}
```

**解释：**
- `geo` 指令块用于基于客户端IP地址设定一个新变量 `$urlpath-v1`。
- `$proxy_protocol_addr` 是一个内置变量，它包含客户端的IP地址，通常在使用了PROXY协议的连接中可用。
- 如果客户端IP地址位于指定的CIDR范围内，则 `$urlpath-v1` 被设定为 `1`，表示允许访问。
- 如果客户端IP不在任何指定的范围内，`$urlpath-v1` 的默认值是 `0`，表示访问被拒绝。

### 第三段：`map $ssl_client_s_dn_cn $urlpath-v1-CN`

```nginx
map $ssl_client_s_dn_cn $urlpath-v1-CN {                                                                                                             
    default 0;
    dev-sgpoet-client.domain.aibang 1; # 允许特定客户端证书
    # 更多允许的客户端证书公用名称
}
```

**解释：**
- 这是另一个 `map` 指令块，它创建了一个新变量 `$urlpath-v1-CN` 来基于客户端证书的公用名称进行映射。
- `$ssl_client_s_dn_cn` 变量（之前通过第一段 `map` 配置设置）包含了从客户端SSL证书中提取的公用名称。
- 如果 `$ssl_client_s_dn_cn` 的值匹配 `map` 块中定义的任何公用名称，则 `$urlpath-v1-CN` 被设定为 `1`，表示允许访问。
- 如果没有找到匹配项，`$urlpath-v1-CN` 的默认值是 `0`，表示访问被拒绝。

这些 `map` 指令块为后续的访问控制提供基础，允许nginx在处理请求时根据客户端的IP地址和SSL证书的公用名称来做出决策。