```nginx.conf

user nxadm nxgrp;

worker_processes 1;

  

#error_log logs/error.log;

#error_log logs/error.log notice;

#error_log logs/error.log info;

error_log /appvol/nginx/logs/error.log info;

#pid logs/nginx.pid;

  

events {

    worker_connections 1024;

}

  

stream {

    log_format basic '$remote_addr [$time_local] '

                    '$protocol $status $bytes_sent $bytes_received '

                    "$session_time $ssl_preread_server_name $server_port";

  

    include /etc/nginx/conf.d/*.conf;

}

```

  

conf.d 下

  

```bash

 server {

   listen 8081;

   ssl_preread on;

   proxy_connect_timeout 5s;

   proxy_pass 192.168.64.33:443;

 }

```


以下是针对你当前 **Nginx stream/L4** 配置的两类优化建议：

1. **运行参数（提高并发 & 资源使用率）**
    
2. **“时间”相关（日志时间格式 + 连接/会话超时）**
    

---

## **1 运行参数优化**

|**目的**|**建议项**|**说明**|
|---|---|---|
|提高 CPU 利用率|worker_processes auto;|自动与 CPU 核心数对齐，减少人工修改。|
|提高并发 & 限制资源|worker_rlimit_nofile 65536;events { worker_connections 8192; multi_accept on; use epoll; }|提前调高 ulimit / 文件句柄数，multi_accept + epoll 在 Linux 上更高效。|
|平滑重启|worker_shutdown_timeout 10s;|避免 reload 过程中突然断链。|

> **注意**：worker_rlimit_nofile 需同时在宿主机 ulimit / systemd 中放宽。

---

## **2 时间相关优化**

  

### **2‑1 日志时间戳**

  

本地时间 $time_local 对于跨时区排障并不友好，可改为 **ISO‑8601** 或带微秒精度的 $msec：

```
stream {
    # ISO‑8601（含时区）更通用
    log_format basic '$remote_addr [$time_iso8601] '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time $ssl_preread_server_name $server_port';

    # 若想微秒精度，用 $msec（单位：秒.微秒）
    # log_format basic '$remote_addr [$msec] ...';

    access_log /appvol/nginx/logs/access.log basic flush=1s;
    include /etc/nginx/conf.d/*.conf;
}
```

- flush=1s 可让日志在高并发时批量写盘，低量时最多 1 s 就刷新。
    
- 如果希望直接送到集中日志系统，可替换为 access_log syslog:server=<IP>:514 basic;。
    

  

### **2‑2 连接 / 会话超时**

  

在 **stream** 模块中常用的超时只有两项：

|**指令**|**默认**|**建议值**|**说明**|
|---|---|---|---|
|proxy_connect_timeout|60 s|3‑5 s|后端健康时一般 1‑2 RTT 即握手完成，过长会拖慢失败检测。|
|proxy_timeout|6 h|30‑60 s（或按业务）|_会话空闲_ 超时；默认 6 h 过长，易占用 FD。|

示例：

```
# conf.d/app.stream.conf
server {
    listen 8081;
    ssl_preread on;

    # 连接超时：握手 & 建链
    proxy_connect_timeout 5s;

    # 会话空闲超时：客户端/上游长时间无数据即断开
    proxy_timeout 60s;

    proxy_pass 192.168.64.33:443;
}
```

- > **长连接业务**（WebSocket、HTTP/2 等）可适当调大 proxy_timeout 或用上游 keepalive。
    
- > 若需要区分上下行超时，就只能退回 **HTTP/2 (层7)** 或使用边车代理实现细粒度控制。
    

---

## **3 完整示例**

```
user  nxadm nxgrp;

# 自动匹配 CPU 核心
worker_processes auto;
worker_rlimit_nofile 65536;

error_log  /appvol/nginx/logs/error.log  info;

events {
    worker_connections 8192;
    multi_accept on;
    use epoll;
}

stream {
    log_format basic '$remote_addr [$time_iso8601] '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time $ssl_preread_server_name $server_port';

    access_log /appvol/nginx/logs/access.log basic flush=1s;

    include /etc/nginx/conf.d/*.conf;
}

/etc/nginx/conf.d/app.stream.conf
---------------------------------
server {
    listen 8081;
    ssl_preread on;

    proxy_connect_timeout 5s;
    proxy_timeout 60s;

    proxy_pass 192.168.64.33:443;
}
```

---

### **4 几点补充**

1. **监控**：
    
    - $session_time 仅记录 **会话存活时间**；若需端到端延迟，请在上游（例如 Kong DP / RT）打点并在日志中拼接 trace‑id。
        
    
2. **健康检查**：
    
    - 如果有多个上游，可配合 health_check 模块（商业版或开源替代）动态摘除不健康节点，与 proxy_connect_timeout 协同。
        
    
3. **SSL 透传 / SNI 分流**：
    
    - 你已开启 ssl_preread on;，如需按 SNI 派发到不同 upstream，可额外配置 map $ssl_preread_server_name ...。
        
    

  

这样即可既保持 **时间戳可读性**，又避免 **超时过长导致的 FD 占用**，同时提升整体吞吐。