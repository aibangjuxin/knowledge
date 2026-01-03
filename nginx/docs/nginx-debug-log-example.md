# Nginx Debug日志配置示例

本文档提供了在Nginx中配置日志以在info级别获取debug信息的详细示例。

## 1. 基础配置结构

以下是一个完整的nginx.conf配置示例，展示了如何通过不同方式获取debug信息：

```nginx
user  nginx;
worker_processes  auto;

# 全局错误日志配置
error_log  /var/log/nginx/error.log info;

events {
    worker_connections  1024;
}

http {
    # 导入njs模块（用于获取证书信息）
    js_import utils from /etc/nginx/njs/http.js;
    js_set $sse_client_s_dn_cn utils.subjectcn;

    # 定义一个map来标记需要debug日志的请求
    map $http_x_debug $enable_debug {
        default 0;
        "true"  1;
    }

    # 定义一个富有信息量的日志格式
    log_format detailed_json escape=json '{
        "time_local": "$time_local",
        "remote_addr": "$remote_addr",
        "request_id": "$request_id",
        "request_method": "$request_method",
        "request_uri": "$request_uri",
        "status": $status,
        "request_time": $request_time,
        "upstream_response_time": "$upstream_response_time",
        "http_x_cloud_trace_context": "$http_x_cloud_trace_context",
        "client_cn": "$sse_client_s_dn_cn",
        "ssl_protocol": "$ssl_protocol",
        "ssl_cipher": "$ssl_cipher",
        "http_user_agent": "$http_user_agent",
        "http_x_forwarded_for": "$http_x_forwarded_for",
        "upstream_addr": "$upstream_addr",
        "upstream_status": "$upstream_status",
        "request_body": "$request_body",
        "http_referer": "$http_referer",
        "debug_connection": "$enable_debug"
    }';

    # 默认访问日志配置
    access_log /var/log/nginx/access.log detailed_json;

    server {
        listen 443 ssl;
        server_name example.com;

        # SSL配置
        ssl_certificate /etc/nginx/ssl/server.crt;
        ssl_certificate_key /etc/nginx/ssl/server.key;
        ssl_client_certificate /etc/nginx/ssl/ca.crt;
        ssl_verify_client on;

        # 针对特定location的debug日志配置
        location /api/ {
            # 使用条件判断来启用debug日志
            if ($enable_debug) {
                error_log /var/log/nginx/error-debug.log debug;
            }

            # 记录详细的请求信息到access日志
            access_log /var/log/nginx/access-detailed.log detailed_json;

            # 代理配置
            proxy_pass http://backend;
            
            # 传递跟踪信息
            proxy_set_header X-Cloud-Trace-Context $http_x_cloud_trace_context;
            proxy_set_header X-Client-CN $sse_client_s_dn_cn;

            # 启用debug级别的代理错误日志
            proxy_intercept_errors on;
            proxy_next_upstream_tries 3;
            proxy_next_upstream_timeout 10s;

            # 记录上游响应头
            add_header X-Debug-Info $upstream_http_x_debug_info always;
        }

        # 健康检查endpoint的特殊日志配置
        location /health {
            access_log off;
            return 200 "healthy\n";
        }
    }
}
```

## 2. 关键配置说明

### 2.1 条件化Debug日志

通过设置HTTP请求头来动态启用debug日志：
```nginx
map $http_x_debug $enable_debug {
    default 0;
    "true"  1;
}
```

当客户端发送`X-Debug: true`请求头时，将启用详细的debug日志。

### 2.2 自定义日志格式

使用JSON格式记录详细信息：
```nginx
log_format detailed_json escape=json '{
    "time_local": "$time_local",
    "request_id": "$request_id",
    ...
}';
```

这样可以在普通access日志中包含debug级别的信息。

### 2.3 特定Location的Debug配置

针对特定API路径启用更详细的日志：
```nginx
location /api/ {
    if ($enable_debug) {
        error_log /var/log/nginx/error-debug.log debug;
    }
    access_log /var/log/nginx/access-detailed.log detailed_json;
}
```

## 3. 使用方法

### 3.1 启用Debug日志

发送请求时添加debug头：
```bash
curl -H "X-Debug: true" https://example.com/api/endpoint
```

### 3.2 查看日志

查看详细的access日志：
```bash
tail -f /var/log/nginx/access-detailed.log | jq '.'
```

查看debug级别的error日志：
```bash
tail -f /var/log/nginx/error-debug.log
```

## 4. 最佳实践

1. **选择性启用**：使用条件判断来启用debug日志，避免全局开启debug级别
2. **结构化日志**：使用JSON格式便于解析和分析
3. **关键信息记录**：在access日志中包含关键的debug信息
4. **健康检查排除**：对健康检查等频繁访问的endpoint关闭详细日志
5. **上下文关联**：记录请求ID和跟踪ID以关联不同组件的日志

## 5. 注意事项

1. Debug日志会显著增加日志量，建议在生产环境谨慎使用
2. 定期轮转日志文件以管理磁盘空间
3. 确保日志中不包含敏感信息
4. 考虑使用logrotate管理日志文件