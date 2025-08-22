# Nginx `split_clients` 模块详解

`split_clients` 是 Nginx 提供的一个核心模块,用于根据请求的某个变量的哈希值,将客户端请求按预设的百分比分配到不同的结果。这在实现A/B测试、金丝雀发布或简单的流量分发时非常有用。

## 1. 核心概念

`split_clients` 模块的工作原理是基于一个输入字符串的哈希值进行流量分配。它会计算输入字符串的MD5哈希值,然后根据这个哈希值与预设的百分比范围进行匹配,从而将请求分配到不同的结果值。

**简单来说:**

*   你提供一个输入 (例如,用户的IP地址、User-Agent、请求ID等)。
*   Nginx 对这个输入进行哈希计算。
*   根据哈希结果,Nginx 将请求按你设定的百分比分配给不同的“桶” (即不同的变量值)。
*   这个“桶”的变量值可以用于 `proxy_pass` 到不同的后端服务器组,或者用于其他逻辑判断。

## 2. 免费/付费/开源

**`split_clients` 模块是 Nginx 的一个标准核心模块。**

*   **开源**: 它是 Nginx 开源版本的一部分,完全免费使用。
*   **内置**: 无需额外安装或编译,它在 Nginx 的默认构建中就已经包含。
*   **通用**: 无论您使用的是 Nginx 开源版还是 Nginx Plus (商业版),`split_clients` 功能都可用。

## 3. 如何使用

`split_clients` 模块通常在 `http` 块中配置,它会创建一个新的变量,这个变量的值会根据流量分配规则而变化。

### 语法

```nginx
split_clients string $variable {
    percent%    value1;
    percent%    value2;
    ...
    *           valueN; # 剩余的流量
}
```

### 参数解释

*   `string`: 用于计算哈希值的输入字符串。通常是请求相关的变量,例如:
    *   `$remote_addr`: 客户端IP地址 (可以用于实现基于IP的粘性分配)。
    *   `$http_user_agent`: 用户的浏览器信息。
    *   `$request_id`: Nginx为每个请求生成的唯一ID (非常适合随机且均匀的分配)。
    *   `$cookie_name`: 某个Cookie的值 (用于A/B测试,确保用户始终看到同一版本)。
    *   为了更好的随机性和粘性,通常会组合多个变量,例如 `"$remote_addr$request_id"`。
*   `$variable`: `split_clients` 模块输出的新变量的名称。你将在 `location` 块中使用这个变量。
*   `percent% value`: 定义了流量分配的规则。`percent%` 是一个百分比 (例如 `10%`),`value` 是当哈希值落入这个百分比范围时 `$variable` 将被赋予的值。
*   `* valueN`: 捕获所有未被前面百分比规则匹配的剩余流量。这是必须的,作为默认值。

## 4. 示例：金丝雀发布

假设您有一个API `/api_name1/v1/`,现在想将10%的流量发送到新版本 (canary),其余90%发送到稳定版本 (stable)。

```nginx
http {
    # ... 其他http块配置 ...

    # 1. 定义稳定版和金丝雀版的后端服务器组
    upstream api_name1_stable {
        server 192.168.64.33:443; # 稳定版GKE Gateway/Service IP
    }

    upstream api_name1_canary {
        server 192.168.64.34:443; # 金丝雀版GKE Gateway/Service IP
    }

    # 2. 使用split_clients 定义流量分割规则
    # 这里使用远程IP和请求ID的组合作为哈希源,以确保同一用户的请求尽可能地保持一致性
    split_clients "$remote_addr$request_id" $api_name1_backend {
        10%     api_name1_canary; # 10% 的流量将使 $api_name1_backend 变量的值为 'api_name1_canary'
        *       api_name1_stable; # 剩余的 90% 流量将使 $api_name1_backend 变量的值为 'api_name1_stable'
    }

    server {
        listen 443 ssl;
        server_name your.domain.com;
        # ... 其他server块配置 ...

        location /api_name1_version/v1/ {
            # 3. 使用 $api_name1_backend 变量来动态地 proxy_pass 到不同的上游组
            proxy_pass https://$api_name1_backend; 
            proxy_set_header Host your.domain.com;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            # ... 其他proxy设置 ...
        }

        # ... 其他location块 ...
    }
}
```

**解释:**

*   当一个请求到达 `/api_name1_version/v1/` 时,
*   `split_clients` 会根据 `$remote_addr` 和 `$request_id` 的组合计算一个哈希值。
*   如果哈希值落在前10%的范围内,那么 `$api_name1_backend` 变量的值就会被设置为 `api_name1_canary`。
*   否则, `$api_name1_backend` 的值会被设置为 `api_name1_stable`。
*   `proxy_pass https://$api_name1_backend;` 会根据 `$api_name1_backend` 的值,将请求转发到 `api_name1_canary` 或 `api_name1_stable` 这两个 `upstream` 定义的后端服务器组。

## 5. 注意事项

*   **哈希源的选择**: 选择一个合适的哈希源至关重要。如果你希望同一用户始终访问同一版本 (粘性),可以使用 `$remote_addr` 或 `$cookie_session_id`。如果你希望完全随机分配,可以使用 `$request_id`。
*   **百分比精度**: `split_clients` 的百分比是基于哈希值范围的,因此在极低流量的情况下,实际分配可能不会严格符合百分比,但在高流量下会非常接近。
*   **配置位置**: `split_clients` 只能在 `http` 块中定义。

## 6. 总结

`split_clients` 是 Nginx 提供的一个强大、灵活且免费开源的流量分发工具。它使得在Nginx层面实现复杂的流量路由策略 (如A/B测试和金丝雀发布) 变得简单高效。理解并善用它,将大大提升您的服务发布和测试能力。