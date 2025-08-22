# Nginx 金丝雀部署配置详解

created a comprehensive canary deployment configuration document that addresses your specific requirements. Here are the key highlights:

🎯 Key Features Addressed:
📁 Modular Configuration Structure:

Organized /etc/nginx/conf.d/ with user-specific subdirectories
Each API gets its own .conf file
Shared configurations for common logic
Easy to manage hundreds of APIs
🔄 Flexible Canary Control:

Some APIs can have canary deployment enabled
Others can remain as simple stable-only configurations
Per-API traffic percentage control
Multiple canary strategies (user-based, time-based, geo-based)
🛠️ Management Tools:

Shell scripts for creating new API configurations
Automated canary percentage updates
Configuration testing and reloading
Real-time monitoring and reporting
📋 Configuration Examples:
Canary-enabled API - Full traffic splitting logic
Regular API - Simple stable-only routing
Complex canary strategy - Time and geography-based routing
🔧 Practical Usage:
# Create canary-enabled API for user1
./nginx-canary-manager.sh create user1 api_payment true

# Create regular API for user2  
./nginx-canary-manager.sh create user2 api_profile false

# Update canary traffic to 20%
./nginx-canary-manager.sh update-percentage "api_payment" 20

# Monitor live canary traffic
./canary-monitor.sh monitor
The document provides a production-ready solution that scales to hundreds of APIs while maintaining clean separation between users and flexible canary deployment strategies. Each API configuration is self-contained but leverages shared logic for consistency and maintainability.

## 1. 概述

本文档详细说明如何在Nginx中实现灵活的金丝雀部署配置，支持：
- 多用户、多API的独立配置管理
- 部分API启用金丝雀，部分API不启用
- 配置文件模块化管理
- 动态流量分配策略

## 2. 目录结构设计

```
/etc/nginx/
├── nginx.conf                 # 主配置文件
├── conf.d/                   # API配置目录
│   ├── user1/               # 用户1的API配置
│   │   ├── api_name1.conf   # 启用金丝雀的API
│   │   ├── api_name2.conf   # 普通API
│   │   └── api_name3.conf   # 启用金丝雀的API
│   ├── user2/               # 用户2的API配置
│   │   ├── api_service1.conf
│   │   └── api_service2.conf
│   └── shared/              # 共享配置
│       ├── upstream_stable.conf
│       ├── upstream_canary.conf
│       └── canary_logic.conf
├── includes/                # 通用包含文件
│   ├── proxy_headers.conf   # 通用代理头配置
│   ├── ssl_settings.conf    # SSL配置
│   └── logging.conf         # 日志配置
└── maps/                    # 映射配置
    ├── canary_users.conf    # 金丝雀用户映射
    └── api_backends.conf    # API后端映射
```

## 3. 主配置文件 (nginx.conf)

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log info;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # 日志格式
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                   '$status $body_bytes_sent "$http_referer" '
                   '"$http_user_agent" "$http_x_forwarded_for" '
                   'backend="$upstream_addr" response_time="$upstream_response_time" '
                   'canary="$canary_version"';

    access_log /var/log/nginx/access.log main;

    # 基础设置
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    # 代理缓冲设置
    proxy_buffer_size 32k;
    proxy_buffers 4 128k;
    proxy_busy_buffers_size 256k;
    large_client_header_buffers 4 32k;

    # 包含映射配置
    include /etc/nginx/maps/*.conf;
    
    # 包含共享上游配置
    include /etc/nginx/conf.d/shared/*.conf;

    # 主服务器配置
    server {
        listen 80;
        server_name www.aibang.com;
        
        # 健康检查
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        # 包含所有用户的API配置
        include /etc/nginx/conf.d/*/*.conf;
        
        # 默认location
        location / {
            return 404 "API not found";
        }
    }
}
```

## 4. 映射配置文件

### 4.1 金丝雀用户映射 (maps/canary_users.conf)

```nginx
# 定义哪些用户ID或特征启用金丝雀
map $http_x_user_id $is_canary_user {
    default 0;
    ~*canary 1;           # 用户ID包含canary
    ~*test 1;             # 用户ID包含test
    "user123" 1;          # 特定用户ID
    "user456" 1;          # 特定用户ID
}

# 基于请求头的金丝雀标识
map $http_x_canary_flag $force_canary {
    default 0;
    "true" 1;
    "1" 1;
    "enable" 1;
}

# 基于Cookie的金丝雀标识
map $cookie_canary $cookie_canary_flag {
    default 0;
    "true" 1;
    "1" 1;
}
```

### 4.2 API后端映射 (maps/api_backends.conf)

```nginx
# 为每个API定义是否启用金丝雀
map $uri $api_canary_enabled {
    default 0;
    ~/api_name1_version/v1/ 1;    # 启用金丝雀
    ~/api_name3_version/v1/ 1;    # 启用金丝雀
    ~/user2/api_service1/ 1;      # 启用金丝雀
}

# 定义每个API的流量分配比例
map $uri $canary_percentage {
    default 0;
    ~/api_name1_version/v1/ 10;   # 10%流量到金丝雀
    ~/api_name3_version/v1/ 20;   # 20%流量到金丝雀
    ~/user2/api_service1/ 5;      # 5%流量到金丝雀
}
```

## 5. 共享配置文件

### 5.1 上游服务器配置 (conf.d/shared/upstream_stable.conf)

```nginx
# 稳定版上游服务器
upstream gke_gateway_stable {
    server 192.168.64.33:443 weight=1 max_fails=3 fail_timeout=30s;
    server 192.168.64.35:443 weight=1 max_fails=3 fail_timeout=30s backup;
    
    # 健康检查
    keepalive 32;
    keepalive_requests 100;
    keepalive_timeout 60s;
}

# 为不同用户或服务定义专用稳定版上游
upstream user1_stable {
    server 192.168.64.33:443;
}

upstream user2_stable {
    server 192.168.64.37:443;
}
```

### 5.2 金丝雀上游配置 (conf.d/shared/upstream_canary.conf)

```nginx
# 金丝雀版上游服务器
upstream gke_gateway_canary {
    server 192.168.64.34:443 weight=1 max_fails=3 fail_timeout=30s;
    server 192.168.64.36:443 weight=1 max_fails=3 fail_timeout=30s backup;
    
    keepalive 32;
    keepalive_requests 100;
    keepalive_timeout 60s;
}

# 为不同用户定义专用金丝雀上游
upstream user1_canary {
    server 192.168.64.34:443;
}

upstream user2_canary {
    server 192.168.64.38:443;
}
```

### 5.3 金丝雀逻辑配置 (conf.d/shared/canary_logic.conf)

```nginx
# 综合金丝雀决策逻辑
map "$api_canary_enabled:$is_canary_user:$force_canary:$cookie_canary_flag" $should_use_canary {
    default 0;
    
    # API启用金丝雀 + 强制金丝雀标识
    "1:0:1:0" 1;    # 通过header强制
    "1:0:0:1" 1;    # 通过cookie强制
    "1:1:0:0" 1;    # 金丝雀用户
    "1:1:1:0" 1;    # 金丝雀用户 + header
    "1:1:0:1" 1;    # 金丝雀用户 + cookie
}

# 基于百分比的随机分流（用于A/B测试）
split_clients "$remote_addr$request_id$uri" $random_canary {
    5%   canary_5;     # 5%的API使用
    10%  canary_10;    # 10%的API使用
    20%  canary_20;    # 20%的API使用
    *    stable;       # 其余使用稳定版
}

# 最终后端选择逻辑
map "$should_use_canary:$canary_percentage:$random_canary" $final_backend {
    default "stable";
    
    # 强制金丝雀的情况
    "1:5:stable" "canary";
    "1:5:canary_5" "canary";
    "1:10:stable" "canary";
    "1:10:canary_10" "canary";
    "1:20:stable" "canary";
    "1:20:canary_20" "canary";
    
    # 随机分流的情况（当API启用金丝雀但用户不是金丝雀用户时）
    "0:5:canary_5" "canary";
    "0:10:canary_10" "canary";
    "0:20:canary_20" "canary";
}

# 设置版本标识变量
map $final_backend $canary_version {
    default "stable";
    "canary" "canary";
}
```

## 6. 用户API配置示例

### 6.1 启用金丝雀的API (conf.d/user1/api_name1.conf)

```nginx
# User1 - API Name1 (启用金丝雀部署)
location /api_name1_version/v1/ {
    # 设置当前API的上下文
    set $current_api "api_name1";
    set $current_user "user1";
    
    # 根据金丝雀逻辑选择后端
    set $backend_choice $final_backend;
    
    # 动态选择上游服务器
    if ($backend_choice = "canary") {
        proxy_pass https://user1_canary;
    }
    if ($backend_choice = "stable") {
        proxy_pass https://user1_stable;
    }
    
    # 包含通用代理配置
    include /etc/nginx/includes/proxy_headers.conf;
    
    # 添加金丝雀标识头
    proxy_set_header X-Canary-Version $canary_version;
    proxy_set_header X-API-Name $current_api;
    proxy_set_header X-User-Context $current_user;
    
    # 超时设置
    proxy_connect_timeout 5s;
    proxy_send_timeout 10s;
    proxy_read_timeout 30s;
    
    # 添加响应头用于调试
    add_header X-Backend-Used $upstream_addr always;
    add_header X-Canary-Decision $backend_choice always;
    
    # 访问日志（可选，用于分析）
    access_log /var/log/nginx/api_name1_access.log main;
}
```

### 6.2 普通API配置 (conf.d/user1/api_name2.conf)

```nginx
# User1 - API Name2 (不启用金丝雀部署)
location /api_name2_version/v1/ {
    # 直接使用稳定版
    proxy_pass https://user1_stable;
    
    # 包含通用代理配置
    include /etc/nginx/includes/proxy_headers.conf;
    
    # 标识为稳定版
    proxy_set_header X-Canary-Version "stable";
    proxy_set_header X-API-Name "api_name2";
    proxy_set_header X-User-Context "user1";
    
    # 超时设置
    proxy_connect_timeout 5s;
    proxy_send_timeout 10s;
    proxy_read_timeout 30s;
    
    add_header X-Backend-Used $upstream_addr always;
    add_header X-Canary-Decision "disabled" always;
}
```

### 6.3 复杂金丝雀策略API (conf.d/user1/api_name3.conf)

```nginx
# User1 - API Name3 (复杂金丝雀策略)
location /api_name3_version/v1/ {
    set $current_api "api_name3";
    set $current_user "user1";
    
    # 特殊的金丝雀逻辑：基于时间段
    set $time_based_canary 0;
    if ($time_iso8601 ~ "T(09|10|11|14|15|16)") {
        set $time_based_canary 1;  # 工作时间启用金丝雀
    }
    
    # 基于地理位置的金丝雀（假设通过header传递）
    set $geo_canary 0;
    if ($http_x_user_region ~ "(us-west|eu-central)") {
        set $geo_canary 1;
    }
    
    # 综合决策
    set $complex_canary_decision "stable";
    if ($should_use_canary = "1") {
        set $complex_canary_decision "canary";
    }
    if ($time_based_canary = "1") {
        set $complex_canary_decision "canary";
    }
    if ($geo_canary = "1") {
        set $complex_canary_decision "canary";
    }
    
    # 路由到相应后端
    if ($complex_canary_decision = "canary") {
        proxy_pass https://user1_canary;
    }
    if ($complex_canary_decision = "stable") {
        proxy_pass https://user1_stable;
    }
    
    include /etc/nginx/includes/proxy_headers.conf;
    
    proxy_set_header X-Canary-Version $complex_canary_decision;
    proxy_set_header X-API-Name $current_api;
    proxy_set_header X-User-Context $current_user;
    proxy_set_header X-Time-Based-Canary $time_based_canary;
    proxy_set_header X-Geo-Based-Canary $geo_canary;
    
    add_header X-Backend-Used $upstream_addr always;
    add_header X-Canary-Decision $complex_canary_decision always;
    
    # 专用日志文件
    access_log /var/log/nginx/api_name3_canary.log main;
}
```

## 7. 通用包含文件

### 7.1 代理头配置 (includes/proxy_headers.conf)

```nginx
# 通用代理头设置
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Request-ID $request_id;

# 保持连接
proxy_http_version 1.1;
proxy_set_header Connection "";

# 缓冲设置
proxy_buffering on;
proxy_buffer_size 32k;
proxy_buffers 8 32k;
```

## 8. 管理和监控

### 8.1 配置管理脚本

```bash
#!/bin/bash
# nginx-canary-manager.sh

NGINX_CONF_DIR="/etc/nginx"
CONF_D_DIR="$NGINX_CONF_DIR/conf.d"

# 创建新用户的API配置
create_user_api() {
    local user=$1
    local api_name=$2
    local enable_canary=${3:-false}
    
    mkdir -p "$CONF_D_DIR/$user"
    
    if [ "$enable_canary" = "true" ]; then
        cat > "$CONF_D_DIR/$user/${api_name}.conf" << EOF
# $user - $api_name (金丝雀启用)
location /${api_name}/ {
    set \$current_api "$api_name";
    set \$current_user "$user";
    set \$backend_choice \$final_backend;
    
    if (\$backend_choice = "canary") {
        proxy_pass https://${user}_canary;
    }
    if (\$backend_choice = "stable") {
        proxy_pass https://${user}_stable;
    }
    
    include /etc/nginx/includes/proxy_headers.conf;
    proxy_set_header X-Canary-Version \$canary_version;
    proxy_set_header X-API-Name \$current_api;
    proxy_set_header X-User-Context \$current_user;
    
    add_header X-Backend-Used \$upstream_addr always;
    add_header X-Canary-Decision \$backend_choice always;
}
EOF
    else
        cat > "$CONF_D_DIR/$user/${api_name}.conf" << EOF
# $user - $api_name (普通配置)
location /${api_name}/ {
    proxy_pass https://${user}_stable;
    
    include /etc/nginx/includes/proxy_headers.conf;
    proxy_set_header X-Canary-Version "stable";
    proxy_set_header X-API-Name "$api_name";
    proxy_set_header X-User-Context "$user";
    
    add_header X-Backend-Used \$upstream_addr always;
    add_header X-Canary-Decision "disabled" always;
}
EOF
    fi
    
    echo "Created API configuration: $user/$api_name (canary: $enable_canary)"
}

# 更新金丝雀比例
update_canary_percentage() {
    local api_path=$1
    local percentage=$2
    
    sed -i "s|~${api_path} [0-9]*;|~${api_path} ${percentage};|" \
        "$NGINX_CONF_DIR/maps/api_backends.conf"
    
    echo "Updated canary percentage for $api_path to $percentage%"
}

# 测试配置
test_config() {
    nginx -t
    if [ $? -eq 0 ]; then
        echo "Nginx configuration test passed"
        return 0
    else
        echo "Nginx configuration test failed"
        return 1
    fi
}

# 重载配置
reload_nginx() {
    if test_config; then
        nginx -s reload
        echo "Nginx reloaded successfully"
    else
        echo "Configuration test failed, not reloading"
        return 1
    fi
}

# 主函数
case "$1" in
    create)
        create_user_api "$2" "$3" "$4"
        ;;
    update-percentage)
        update_canary_percentage "$2" "$3"
        ;;
    test)
        test_config
        ;;
    reload)
        reload_nginx
        ;;
    *)
        echo "Usage: $0 {create|update-percentage|test|reload}"
        echo "  create <user> <api_name> [true|false]"
        echo "  update-percentage <api_path> <percentage>"
        echo "  test"
        echo "  reload"
        exit 1
        ;;
esac
```

### 8.2 监控脚本

```bash
#!/bin/bash
# canary-monitor.sh

LOG_FILE="/var/log/nginx/access.log"
REPORT_FILE="/tmp/canary_report.txt"

# 生成金丝雀流量报告
generate_report() {
    local time_range=${1:-"1 hour ago"}
    
    echo "=== Canary Deployment Report ===" > $REPORT_FILE
    echo "Time Range: $time_range" >> $REPORT_FILE
    echo "Generated: $(date)" >> $REPORT_FILE
    echo "" >> $REPORT_FILE
    
    # 按API统计流量分布
    echo "=== Traffic Distribution by API ===" >> $REPORT_FILE
    awk -v since="$time_range" '
    BEGIN { 
        stable_count = 0; canary_count = 0; 
        split("", api_stable); split("", api_canary);
    }
    /canary="stable"/ { 
        stable_count++; 
        match($0, /X-API-Name ([^ ]+)/, arr); 
        if (arr[1]) api_stable[arr[1]]++;
    }
    /canary="canary"/ { 
        canary_count++; 
        match($0, /X-API-Name ([^ ]+)/, arr); 
        if (arr[1]) api_canary[arr[1]]++;
    }
    END {
        total = stable_count + canary_count;
        if (total > 0) {
            printf "Total Requests: %d\n", total;
            printf "Stable: %d (%.1f%%)\n", stable_count, (stable_count/total)*100;
            printf "Canary: %d (%.1f%%)\n", canary_count, (canary_count/total)*100;
            print "\nPer API Breakdown:";
            for (api in api_stable) {
                api_total = api_stable[api] + api_canary[api];
                printf "%s: Stable=%d, Canary=%d, Total=%d\n", 
                       api, api_stable[api], api_canary[api], api_total;
            }
        }
    }' $LOG_FILE >> $REPORT_FILE
    
    echo "" >> $REPORT_FILE
    
    # 错误率统计
    echo "=== Error Rate Analysis ===" >> $REPORT_FILE
    awk '
    /canary="stable"/ && /status [45][0-9][0-9]/ { stable_errors++ }
    /canary="stable"/ { stable_total++ }
    /canary="canary"/ && /status [45][0-9][0-9]/ { canary_errors++ }
    /canary="canary"/ { canary_total++ }
    END {
        if (stable_total > 0) {
            printf "Stable Error Rate: %.2f%% (%d/%d)\n", 
                   (stable_errors/stable_total)*100, stable_errors, stable_total;
        }
        if (canary_total > 0) {
            printf "Canary Error Rate: %.2f%% (%d/%d)\n", 
                   (canary_errors/canary_total)*100, canary_errors, canary_total;
        }
    }' $LOG_FILE >> $REPORT_FILE
    
    cat $REPORT_FILE
}

# 实时监控
monitor_live() {
    echo "Starting live canary monitoring (Ctrl+C to stop)..."
    tail -f $LOG_FILE | while read line; do
        if echo "$line" | grep -q 'canary="canary"'; then
            timestamp=$(echo "$line" | awk '{print $4}' | tr -d '[')
            api=$(echo "$line" | grep -o 'X-API-Name [^ ]*' | cut -d' ' -f2)
            status=$(echo "$line" | awk '{print $9}')
            echo "[$timestamp] CANARY: $api - Status: $status"
        fi
    done
}

case "$1" in
    report)
        generate_report "$2"
        ;;
    monitor)
        monitor_live
        ;;
    *)
        echo "Usage: $0 {report|monitor}"
        echo "  report [time_range]  - Generate traffic report"
        echo "  monitor             - Live monitoring"
        exit 1
        ;;
esac
```

## 9. 使用示例

### 9.1 创建新的API配置

```bash
# 为user1创建启用金丝雀的API
./nginx-canary-manager.sh create user1 api_payment true

# 为user2创建普通API
./nginx-canary-manager.sh create user2 api_profile false

# 测试配置
./nginx-canary-manager.sh test

# 重载Nginx
./nginx-canary-manager.sh reload
```

### 9.2 调整金丝雀流量

```bash
# 将api_payment的金丝雀流量调整为20%
./nginx-canary-manager.sh update-percentage "api_payment" 20

# 重载配置
./nginx-canary-manager.sh reload
```

### 9.3 监控和分析

```bash
# 生成过去1小时的报告
./canary-monitor.sh report "1 hour ago"

# 实时监控金丝雀流量
./canary-monitor.sh monitor
```

## 10. 最佳实践

### 10.1 配置管理
- 使用版本控制管理所有配置文件
- 为每个环境（开发、测试、生产）维护独立的配置
- 定期备份配置文件

### 10.2 监控和告警
- 设置金丝雀版本的错误率告警
- 监控响应时间差异
- 建立自动回滚机制

### 10.3 发布流程
- 从1%开始逐步增加金丝雀流量
- 在每个阶段进行充分的监控和验证
- 建立明确的回滚标准和流程

这个配置方案提供了高度的灵活性，支持数百个API的独立管理，每个API都可以有自己的金丝雀策略。通过模块化的配置文件组织，可以轻松地添加新API、调整流量分配，并进行有效的监控和管理。