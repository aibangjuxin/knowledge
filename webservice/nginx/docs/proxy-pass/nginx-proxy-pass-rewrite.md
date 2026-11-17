
- [Requirement](#requirement)
- [Solution 1](#solution-1)
  - [生产级维护方案：多域名与无规律 URL 映射](#生产级维护方案多域名与无规律-url-映射)
    - [1. 推荐的目录组织结构](#1-推荐的目录组织结构)
    - [2. 映射表文件配置 (Maps)](#2-映射表文件配置-maps)
    - [3. 主站点配置文件关系 (Server Blocks)](#3-主站点配置文件关系-server-blocks)
    - [4. 该方案的优势](#4-该方案的优势)
- [Solution 2](#solution-2)
  - [方案二：基于 Nginx location 正则 + rewrite 的路由方案](#方案二基于-nginx-location-正则--rewrite-的路由方案)
    - [1. 方案对比](#1-方案对比)
    - [2. 适用场景](#2-适用场景)
    - [3. 配置文件示例](#3-配置文件示例)
      - [3.1 目录结构](#31-目录结构)
      - [3.2 lex 域名配置（使用正则捕获）](#32-lex-域名配置使用正则捕获)
      - [3.3 hub 域名配置](#33-hub-域名配置)
    - [4. 高级用法：基于条件的动态路由](#4-高级用法基于条件的动态路由)
    - [5. 方案选择指南](#5-方案选择指南)
    - [6. 注意事项](#6-注意事项)

# Requirement

- reference

```nginx
service {
    listen 443;
    server_name lex-long-fqdn.projectID.env.aliyun.cloud.region.aibang;
    location / {
        proxy_pass https://our-intra-gkegateway.internal:443;
        proxy_set_header Host ppd01-ajbx.short.fqdn.aibang;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

目前proxy_pass 后面是一个 GKE Gateway的httpRoute 我会针对Host ppd01-ajbx.short.fqdn.aibang 去匹配 ,这里有一个把长域名变成短域名的逻辑

比如说我有一个列表是维护的这种URL关系

比如说

<https://lex-long-fqdn.projectID.env.aliyun.cloud.region.aibang> -> 后端收到 <https://ppd01-ajbx.short.fqdn.aibang/lex-long-fqdn>
<https://lex-long-fqdn.projectID.env.aliyun.cloud.region.aibang/abc> -> 后端收到 <https://ppd01-ajbx.short.fqdn.aibang/lex-long-fqdn/abc>

| long-url                                                      | short-url                                      |
| ------------------------------------------------------------- | ---------------------------------------------- |
| lex-long-fqdn.projectID.env.aliyun.cloud.region.aibang/       | ppd01-ajbx.short.fqdn.aibang/lex-long-fqdn     |
| lex-long-fqdn.projectID.env.aliyun.cloud.region.aibang/abc    | ppd01-ajbx.short.fqdn.aibang/lex-long-fqdn/abc |
| lex-long-fqdn.projectID.env.aliyun.cloud.region.aibang/create | ppd01-ajbx.short.fqdn.aibang/create/v1         |
| hub-fqdn.projectID.env.aliyun.cloud.region.aibang/hub-api     | ppd01-ajbx.short.fqdn.aibang/hub-api/v1        |
| hub-fqdn.projectID.env.aliyun.cloud.region.aibang/hub-client  | ppd01-ajbx.short.fqdn.aibang/hub-client/v1     |
| hub-fqdn.projectID.env.aliyun.cloud.region.aibang/hub-server  | ppd01-ajbx.short.fqdn.aibang/hub-server/v1     |

---

# Solution 1

## 生产级维护方案：多域名与无规律 URL 映射

当涉及多个域名且每个域名都有大量无规律的路径映射时，建议采用 **“Map 查找表 + include 模块化”** 的方式。

> 说明：你在 Requirement 里写的是 `service { ... }`，真实 Nginx 配置应为 `server { ... }`。

### 1. 推荐的目录组织结构

建议将映射逻辑与站点配置分离：

```text
/etc/nginx/
  ├── nginx.conf
  └── conf.d/
      ├── maps/               # 专门存放路径映射表
      │    ├── lex_uri_map.conf
      │    └── hub_uri_map.conf
      ├── snippets/           # 复用的公共片段（headers/timeout 等）
      │    └── proxy_common.conf
      └── hosts/              # 站点 Server 配置
           ├── lex_host.conf
           └── hub_host.conf
```

### 2. 映射表文件配置 (Maps)

利用 `map $key $target` 建立查找关系。这里我们用 `$uri` 做 key（不包含 query string），并在 `proxy_pass` 里通过 `$is_args$args` 统一保留 query string。

**文件：`/etc/nginx/conf.d/maps/lex_uri_map.conf`**

```nginx
map $uri $lex_target_path {
    # 默认逻辑：常规路径透传并加上 /lex-long-fqdn 前缀
    # 例：/abc -> /lex-long-fqdn/abc
    default        /lex-long-fqdn$uri;

    # 例：/ -> /lex-long-fqdn
    /              /lex-long-fqdn;

    # 特殊无规律映射
    /create        /create/v1;
}
```

**文件：`/etc/nginx/conf.d/maps/hub_uri_map.conf`**

```nginx
map $uri $hub_target_path {
    # 默认逻辑：常规路径保持不变
    default        $uri;

    # hub 专有映射
    /hub-api       /hub-api/v1;
    /hub-client    /hub-client/v1;
    /hub-server    /hub-server/v1;
}
```

**文件：`/etc/nginx/conf.d/snippets/proxy_common.conf`**

```nginx
# 生产常用：保留 client 信息，便于网关/后端审计与路由
proxy_set_header Host              ppd01-ajbx.short.fqdn.aibang;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host  $host;
proxy_set_header X-Forwarded-Port  $server_port;

# 生产常用：上游 HTTPS 与连接复用（按需调整）
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_ssl_server_name on;
```

### 3. 主站点配置文件关系 (Server Blocks)

**文件：`/etc/nginx/conf.d/hosts/lex_host.conf`**

```nginx
# 引入该域名专用的 map
include /etc/nginx/conf.d/maps/lex_uri_map.conf;

server {
    listen 443;
    server_name lex-long-fqdn.projectID.env.aliyun.cloud.region.aibang;

    location / {
        include /etc/nginx/conf.d/snippets/proxy_common.conf;

        # 关键点：
        # 1) proxy_pass 后拼接 $lex_target_path，使上游收到“重写后的 path”
        # 2) 用 $is_args$args 保留 query string（避免 map+rewrite 时把参数丢掉/处理不一致）
        proxy_pass https://our-intra-gkegateway.internal:443$lex_target_path$is_args$args;
    }
}
```

**文件：`/etc/nginx/conf.d/hosts/hub_host.conf`**

```nginx
# 引入该域名专用的 map
include /etc/nginx/conf.d/maps/hub_uri_map.conf;

server {
    listen 443;
    server_name hub-fqdn.projectID.env.aliyun.cloud.region.aibang;

    location / {
        include /etc/nginx/conf.d/snippets/proxy_common.conf;
        proxy_pass https://our-intra-gkegateway.internal:443$hub_target_path$is_args$args;
    }
}
```

### 4. 该方案的优势

1. **隔离性**：`lex` 和 `hub` 的映射关系分文件维护，变量名（`$lex_target_path`）也不重合，修改其中一个不会影响另一个。
2. **易于维护**：
    - **Excel/脚本同步**：如果产品或开发提供了一份 URL 对应列表，可以用简单的 Python/Shell 脚本直接扫描列表并生成相应的 `.conf` 映射文件。
    - **热加载**：新增映射关系后，只需 `nginx -s reload`，无需重启。
3. **性能线性**：Nginx 的 `map` 指令基于 Hash 查找，即使您一个域名下有几千个映射关系，查找速度也几乎是瞬时的（O(1) 复杂度）。
4. **干净的 Server 块**：主配置文件里不再有成排的 `location` 或 `if` 逻辑，所有的"脏活"都在映射表里完成。

---

# Solution 2

## 方案二：基于 Nginx location 正则 + rewrite 的路由方案

当需要更细粒度的路由控制、或需要根据请求特征（URL、Query String、Header）进行动态路由时，可以使用 **正则 location + rewrite** 组合方式。该方案与 Solution 1 的 `map` 方式互补，适用不同场景。

> 结论：Solution 2 在规则“有明显规律”时可用，但不适合承载大量无规律映射（维护成本高，且容易出现 `if`/正则边界问题）。

### 1. 方案对比

| 维度       | Solution 1 (map)      | Solution 2 (location + rewrite) |
| ---------- | --------------------- | ------------------------------- |
| 匹配方式   | Hash 查找             | 正则匹配                        |
| 路由灵活性 | 静态映射表            | 动态规则（正则捕获）            |
| 适用场景   | 固定路径映射          | 有规律的模式匹配                |
| 配置复杂度 | 中（需维护 map 文件） | 中（需理解正则）                |
| 性能       | O(1)                  | 略低于 map（正则引擎开销）      |

### 2. 适用场景

- URL 路径有明确规律，可用正则捕获
- 需要根据 `query string` 进行路由
- 需要根据请求 `method` 区分处理
- 路由规则需要条件判断（如包含某个关键词）

### 3. 配置文件示例

#### 3.1 目录结构

```text
/etc/nginx/
  ├── nginx.conf
  └── conf.d/
      ├── rewrite/
      │    ├── lex_rewrite.rules
      │    └── hub_rewrite.rules
      ├── snippets/
      │    └── proxy_common.conf
      └── hosts/
           ├── lex_host.conf
           └── hub_host.conf
```

#### 3.2 lex 域名配置（使用正则捕获）

**文件：`/etc/nginx/conf.d/hosts/lex_host.conf`**

```nginx
server {
    listen 443;
    server_name lex-long-fqdn.projectID.env.aliyun.cloud.region.aibang;

    # 引入 rewrite 规则文件
    include /etc/nginx/conf.d/rewrite/lex_rewrite.rules;

    location / {
        # 默认：追加 lex-long-fqdn 前缀
        rewrite ^/(.*)$ /lex-long-fqdn/$1 break;
        
        include /etc/nginx/conf.d/snippets/proxy_common.conf;
        proxy_pass https://our-intra-gkegateway.internal:443;
    }
}
```

**文件：`/etc/nginx/conf.d/rewrite/lex_rewrite.rules`**

```nginx
# 精确匹配 /create -> /create/v1
location = /create {
    rewrite ^ /create/v1 break;
    proxy_pass https://our-intra-gkegateway.internal:443;
    include /etc/nginx/conf.d/snippets/proxy_common.conf;
}

# 精确匹配 /update -> /update/v1
location = /update {
    rewrite ^ /update/v1 break;
    proxy_pass https://our-intra-gkegateway.internal:443;
    include /etc/nginx/conf.d/snippets/proxy_common.conf;
}

# 精确匹配 /delete -> /delete/v1
location = /delete {
    rewrite ^ /delete/v1 break;
    proxy_pass https://our-intra-gkegateway.internal:443;
    include /etc/nginx/conf.d/snippets/proxy_common.conf;
}

# 正则匹配：以 /api 开头且包含 version 参数的请求
# 示例: /api/users?version=v2 -> /api/v2/users
location ~ ^/api(?<path>/.*)$ {
    if ($arg_version) {
        # 注意：这里不要用结尾的 '?'，否则会清空 query string
        rewrite ^ /api/$arg_version$path break;
    }
    proxy_pass https://our-intra-gkegateway.internal:443;
    include /etc/nginx/conf.d/snippets/proxy_common.conf;
}
```

#### 3.3 hub 域名配置

**文件：`/etc/nginx/conf.d/hosts/hub_host.conf`**

```nginx
server {
    listen 443;
    server_name hub-fqdn.projectID.env.aliyun.cloud.region.aibang;

    # hub-api -> /hub-api/v1
    location = /hub-api {
        rewrite ^ /hub-api/v1 break;
        proxy_pass https://our-intra-gkegateway.internal:443;
        include /etc/nginx/conf.d/snippets/proxy_common.conf;
    }

    # hub-client -> /hub-client/v1
    location = /hub-client {
        rewrite ^ /hub-client/v1 break;
        proxy_pass https://our-intra-gkegateway.internal:443;
        include /etc/nginx/conf.d/snippets/proxy_common.conf;
    }

    # hub-server -> /hub-server/v1
    location = /hub-server {
        rewrite ^ /hub-server/v1 break;
        proxy_pass https://our-intra-gkegateway.internal:443;
        include /etc/nginx/conf.d/snippets/proxy_common.conf;
    }

    # 默认路径透传
    location / {
        proxy_pass https://our-intra-gkegateway.internal:443;
        include /etc/nginx/conf.d/snippets/proxy_common.conf;
    }
}
```


### 4. 高级用法：基于条件的动态路由

如果需要根据请求的 **Query String**、**Header** 或 **Method** 进行路由：

```nginx
# 建议：尽量避免在 location 里用 if 做复杂逻辑，优先用 map 把条件“变成变量”
# 示例: /api/users?version=v2 -> /api/v2/users（保留其他 query string）
map $arg_version $api_version {
    # 注意：map 只能放在 http 级别（nginx.conf 的 http {}，或被 http include 的 conf 文件）
    default  v1;
    ~^v\d+$  $arg_version;
}

location ~ ^/api(?<path>/.*)$ {
    rewrite ^ /api/$api_version$path break;
    proxy_pass https://our-intra-gkegateway.internal:443;
    include /etc/nginx/conf.d/snippets/proxy_common.conf;
}

# 分版本的 location
location ~ ^/api/v(?<ver>\d+)(?<rest>/.*)$ {
    set $target_path /api$rest;
    
    # v1 版本走特定的 backend
    if ($ver = "1") {
        set $target_path /legacy$rest;
    }
    
    rewrite ^ $target_path break;
    proxy_pass https://our-intra-gkegateway.internal:443;
    include /etc/nginx/conf.d/snippets/proxy_common.conf;
}
```

### 5. 方案选择指南

| 场景                       | 推荐方案                        |
| -------------------------- | ------------------------------- |
| 路径映射固定，变更少       | Solution 1 (map)                |
| 路径有规律，可用正则捕获   | Solution 2 (location + rewrite) |
| 需要根据 query string 路由 | Solution 2                      |
| 需要根据 header 路由       | Solution 2 + `if` 判断          |
| 映射关系数千条，性能敏感   | Solution 1                      |
| 需要调试方便，可读性强     | Solution 2（rewrite 逻辑直观）  |

### 6. 注意事项

1. **location 匹配优先级**：`=` > `^~` > `~` > `/`
2. **rewrite vs location**：rewrite 在 location 内执行，适合做路径重写；location 用于路由分发
3. **if 陷阱**：Nginx 的 `if` 建议仅与 `rewrite` 配合使用，避免复杂业务逻辑
4. **性能**：大量正则 location 会增加匹配耗时，建议控制在 50 个以内
5. **测试**：使用 `nginx -T` 查看完整配置，用 `curl` 测试各路径
