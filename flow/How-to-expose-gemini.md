**

# 在GCP中隔离VPC间通过虚拟机实例暴露内部服务的方案分析

## 一、引言

在Google Cloud Platform (GCP)环境中，企业常常出于安全、管理或组织结构的原因，将不同的服务部署在逻辑隔离的虚拟私有云 (VPC) 网络中。一种常见的场景是，核心应用服务（例如Nginx服务）部署在一个内部VPC中，该VPC与共享VPC (Shared VPC) 网络隔离，而共享VPC中的主机需要访问这些内部服务。由于网络隔离，直接访问是不可能的。本报告旨在分析并详细说明，当共享VPC与内部VPC网络隔离时，如何仅通过虚拟机实例（以下简称VM）作为中介，将内部VPC的服务暴露给共享VPC网络中的主机访问。我们将首先从网络层面分析可行方案，包括基于iptables的NAT、基于静态路由的路由器以及基于反向代理的VM，然后详细阐述Nginx和Squid作为反向代理时的具体配置方法，并探讨相关的安全考量。

## 二、网络层面可行性分析

在GCP中，利用具有多个网络接口控制器 (NIC) 的VM实例，可以桥接两个隔离的VPC网络。这种VM通常配置至少两个NIC，一个连接到共享VPC（例如nic0），另一个连接到内部VPC（例如nic1）。所有通过VM暴露内部服务的方案都依赖于以下GCP网络和VM操作系统层面的核心配置：

- 双NIC虚拟机创建 (Dual-NIC VM Creation):
    

- 创建一个Compute Engine VM实例。
    
- 在创建过程中，配置至少两个网络接口。nic0连接到共享VPC的一个子网，nic1连接到内部VPC的一个子网 。
    
- 确保这两个子网的IP地址范围不重叠，以避免路由冲突 。
    
- 通常，这些VM不需要外部IP地址，除非特定方案（如直接从互联网访问代理）需要。
    

- IP转发 (IP Forwarding):
    

- 对于需要VM作为路由器或NAT网关的方案，必须在该VM上启用IP转发功能 (canIpForward=true) 。此设置允许VM转发并非以其自身IP地址为目标的数据包。
    
- 启用IP转发从根本上改变了VM的行为，使其从一个端点转变为一个中转设备。当IP转发启用时，GCP默认丢弃目标非VM自身IP的数据包的行为会被修改，以允许转发数据包 。这使得GCP防火墙规则以及VM操作系统层面的防火墙（如iptables的FORWARD链规则）在控制哪些流量允许通过方面承担了更大的责任。安全态势从“默认为此VM阻止，除非明确允许”转变为“如果规则允许，则允许中转”。
    

- GCP防火墙规则 (GCP Firewall Rules):
    

- 必须在共享VPC和内部VPC中配置防火墙规则，以允许预期的流量通过中介VM。
    
- 共享VPC防火墙规则：
    

- Ingress规则：允许来自共享VPC客户端的流量到达中介VM的nic0。目标端口取决于所选方案（例如，NAT暴露的端口，或Nginx/Squid监听的端口80/443）。
    
- Egress规则：通常，默认的允许所有出站流量规则即可，但如果有限制性出站规则，则需确保允许到中介VM nic0的流量。
    

- 内部VPC防火墙规则：
    

- Ingress规则：允许来自中介VM的nic1的流量到达内部目标服务（例如Nginx服务）的IP和端口。源IP应为中介VM nic1的IP地址。
    
- Egress规则：允许来自内部目标服务的响应流量返回到中介VM的nic1。目标IP应为中介VM nic1的IP地址。
    

- GCP防火墙是状态化的，这意味着如果一个连接在一个方向上被允许，则匹配此连接的返回流量也会被允许 。
    

- GCP静态路由 (GCP Static Routes):
    

- 静态路由用于引导流量通过中介VM。
    
- 共享VPC中的路由： 需要创建一条静态路由，其目标是内部VPC中服务的（真实或NAT后的）IP地址或地址范围，下一跳 (next-hop) 指向中介VM在共享VPC中的nic0的IP地址 。
    
- 内部VPC中的路由： 可能需要创建静态路由，以确保来自内部服务的响应流量能够正确返回到中介VM的nic1，特别是当中介VM执行SNAT时，或者当共享VPC的客户端IP范围无法通过默认路由到达时。目标可以是共享VPC的客户端IP范围，下一跳指向中介VM在内部VPC中的nic1的IP地址 。
    

以下是三种主要的网络层面实现方案：

### 方案一：基于iptables的NAT网关 (VM as NAT Gateway with iptables)

- 原理 (Principle):
    

- 中介VM启用IP转发，并使用Linux内核的iptables功能执行网络地址转换（NAT）。
    
- DNAT (Destination NAT): 对于从共享VPC到达nic0的入站连接，iptables将目标IP和端口（VM nic0的IP和暴露端口）修改为内部VPC中实际服务的IP和端口。
    
- SNAT (Source NAT) / MASQUERADE: 对于从内部服务返回的响应流量，或者由VM转发出去的流量，iptables将源IP（内部服务的IP）修改为VM nic0的IP（如果目标是共享VPC客户端）或nic1的IP（如果需要，但不常见于此场景）。通常使用MASQUERADE，它会自动使用出站接口的IP地址。
    

- 操作系统配置 (OS Configuration on VM):
    

- 启用IP转发：sudo sysctl -w net.ipv4.ip_forward=1，并使其持久化 。
    
- 配置iptables规则：
    

- PREROUTING链 (nat表) 进行DNAT ：
  ```bash  
    # 示例：将到达VM nic0_ip:exposed_port 的流量转发到 internal_service_ip:service_port  
    # 假设 nic0 连接共享VPC，其接口名为 eth0；nic1 连接内部VPC，其接口名为 eth1  
    # <nic0_interface_name> 通常是 eth0, <nic0_ip> 是其IP  
    # <internal_service_ip> 是内部服务的IP, <service_port> 是内部服务端口  
    # <exposed_port> 是在共享VPC暴露的端口  
    sudo iptables -t nat -A PREROUTING -i <nic0_interface_name> -p tcp --dport <exposed_port> -j DNAT --to-destination <internal_service_ip>:<service_port>  
   ```
      
    
- POSTROUTING链 (nat表) 进行SNAT/MASQUERADE ：
    ```bash  
    # 示例：对源自 internal_service_ip_or_subnet 且从 nic0_interface_name 出去的流量进行伪装  
    sudo iptables -t nat -A POSTROUTING -s <internal_service_ip_or_subnet> -o <nic0_interface_name> -j MASQUERADE  
    # 或者，更通用的做法是，对所有从 nic1 转发到 nic0 的流量进行伪装  
    # 这确保了从内部VPC到共享VPC的流量看起来源自NAT VM的nic0  
    sudo iptables -t nat -A POSTROUTING -o <nic0_interface_name> -j MASQUERADE  
    ```
      
    
- FORWARD链 (filter表) 允许转发相关流量 ：  
    ```bash
    # 允许从内部VPC (nic1) 到共享VPC (nic0) 的新连接和已建立连接的流量
    # 允许从共享VPC (nic0) 到内部服务 (nic1) 的新连接和已建立连接的流量  
    sudo iptables -A FORWARD -i <nic0_interface_name> -o <nic1_interface_name> -p tcp --dport <service_port> -d <internal_service_ip> -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT  
    # 允许从内部服务 (nic1) 到共享VPC (nic0) 的已建立连接的返回流量  
    sudo iptables -A FORWARD -i <nic1_interface_name> -o <nic0_interface_name> -s <internal_service_ip> -p tcp --sport <service_port> -m state --state ESTABLISHED,RELATED -j ACCEPT  
    ```
      
    

- 持久化iptables规则 (例如，使用iptables-persistent工具) 。
    

- GCP路由配置 (GCP Routing Configuration):
    

- 共享VPC: 创建静态路由，目标为内部服务对外暴露的“虚拟”IP（即NAT VM nic0的IP），下一跳为NAT VM实例的nic0 。客户端将流量发送到NAT VM nic0的IP和exposed_port。
    
- 内部VPC: 创建静态路由，目标为共享VPC中客户端的IP范围（或0.0.0.0/0如果NAT VM需要响应任何来源，但这通常由MASQUERADE处理，主要确保返回路径正确），下一跳为NAT VM实例的nic1。这确保了内部服务响应的流量能到达NAT VM进行SNAT处理后发回客户端 。
    

- GCP防火墙规则 (GCP Firewall Rules):
    

- 共享VPC:
    

- Ingress: 允许来自共享VPC客户端的TCP流量到达NAT VM nic0的exposed_port。源可以是共享VPC内的特定IP范围或标签。
    

- 内部VPC:
    

- Ingress: 允许来自NAT VM nic1的TCP流量到达内部目标服务的IP和service_port。源应为NAT VM nic1的IP。
    
- Egress: 允许来自内部目标服务的响应TCP流量到达NAT VM nic1。目标为NAT VM nic1的IP。
    

### 方案二：基于虚拟机的静态路由 (VM as a Router)

- 原理 (Principle):
    

- 中介VM启用IP转发，作为纯粹的路由器在两个VPC之间转发数据包，不执行NAT。客户端直接使用内部服务的真实IP地址进行通信。
    
- 此方案依赖GCP的路由机制将去往对方VPC的流量导向该中介VM，VM再根据其操作系统内的路由表（通常由GCP通过DHCP Option 121设置的默认路由或手动配置的策略路由）将流量从一个NIC转发到另一个NIC。
    

- GCP网络配置 (GCP Network Configuration):
    

- VM创建：双NIC，必须启用IP转发 。
    

- 操作系统路由配置 (OS Routing on VM):
    

- 确保VM的操作系统路由表配置正确，能够将来自nic0（共享VPC）的数据包正确转发到nic1（内部VPC），反之亦然。在Linux系统中，可以使用/etc/iproute2/rt_tables文件以及ip rule和ip route命令配置策略路由，以处理多NIC环境下的复杂路由需求 。如果GCP静态路由配置得当，VM的默认路由行为可能已足够，但对于确保流量从正确的接口出去，策略路由可能更可靠。
    

- GCP路由配置 (GCP Routing Configuration):
    

- 共享VPC: 创建静态路由，目标为内部VPC中目标服务的IP地址或其所在子网的CIDR范围，下一跳为中介VM实例的nic0 IP地址。
    
- 内部VPC: 创建静态路由，目标为共享VPC中需要访问内部服务的客户端IP地址或其所在子网的CIDR范围，下一跳为中介VM实例的nic1 IP地址。
    

- GCP防火墙规则 (GCP Firewall Rules):
    

- 共享VPC:
    

- Ingress: 允许来自共享VPC客户端的流量到达中介VM nic0，其最终目标是内部服务的真实IP和端口。
    
- Egress (to VM): 允许从共享VPC客户端发往内部服务真实IP的流量，下一跳是中介VM。
    

- 内部VPC:
    

- Ingress (from VM): 允许来自中介VM nic1的流量（源IP为共享VPC客户端真实IP）到达内部目标服务的真实IP和端口。
    
- Egress: 允许来自内部目标服务的响应流量（目标IP为共享VPC客户端真实IP）到达中介VM nic1。
    

- 重要: 由于没有NAT，防火墙规则需要允许内部服务的真实IP和端口，并且源IP是客户端的真实IP。
    

### 方案三：虚拟机作为反向代理 (VM as a Reverse Proxy - Nginx/Squid)

- 原理 (Principle):
    

- 中介VM上运行Nginx或Squid等反向代理软件。共享VPC中的客户端连接到VM在共享VPC中的nic0上监听的代理服务端口（如80/443）。
    
- 代理软件终止客户端连接，然后代表客户端（使用VM nic1的IP作为源IP）向内部VPC中的目标服务（如Nginx服务）发起新的连接 。
    
- 此方案在应用层（L7）操作，可以提供SSL终止、负载均衡、内容缓存、URL重写、请求/响应头修改等高级功能。
    

- GCP网络配置 (GCP Network Configuration):
    

- VM创建：双NIC。通常不需要为VM启用IP转发功能，因为代理软件自身处理连接的建立和转发，而不是操作系统内核层面进行IP包转发 。
    

- GCP路由配置 (GCP Routing Configuration):
    

- 共享VPC: 客户端直接访问中介VM nic0的IP地址和代理监听端口。如果使用域名访问服务，则DNS记录应解析到中介VM nic0的IP地址。通常不需要为共享VPC配置额外的静态路由，除非中介VM与客户端不在同一子网且两者之间没有默认路由可达。
    
- 内部VPC: 中介VM的nic1需要能够路由到内部目标服务。如果内部服务与中介VM的nic1在同一子网，则本地子网路由即可满足。如果不在同一子网，内部VPC需要有到达该服务所在子网的路由（通常也是本地子网路由或通过其他方式已配置的路由）。
    

- GCP防火墙规则 (GCP Firewall Rules):
    

- 共享VPC:
    

- Ingress: 允许来自共享VPC客户端的TCP流量到达代理VM nic0的代理监听端口 (例如，TCP 80或443)。
    

- 内部VPC:
    

- Ingress: 允许来自代理VM nic1的TCP流量到达内部目标服务的IP和端口。源IP应为代理VM nic1的IP。
    
- Egress: 允许来自内部目标服务的响应TCP流量返回到代理VM nic1。目标IP为代理VM nic1的IP。
    

任何基于VM的解决方案的成功都高度依赖于VM NIC配置、GCP层面的路由（静态路由）、涉及的两个VPC的GCP防火墙规则以及VM上的操作系统级配置（如IP转发、iptables、代理软件）之间的正确协同。任何一个环节的配置失误都可能导致连接失败。

对于反向代理解决方案，虽然GCP路由可能更简单（客户端目标是代理的IP），但DNS解析变得至关重要。共享VPC中的客户端需要将服务 FQDN 解析为代理VM nic0的IP地址。这可能涉及到配置对共享VPC可见的Cloud DNS私有区域。值得注意的是，GCP VM的内部主机名默认解析到nic0的IP地址 。如果客户端从不同的VPC（即使通过代理可路由）使用此内部主机名，并且nic0不在发出查询的实例的VPC网络中，则DNS查询可能会失败。这强调了需要一个周密的DNS策略，确保域名能解析到代理的正确且可访问的IP。

所有基于VM的解决方案都提供了比某些完全托管的GCP服务更细致的流量控制和安全策略定制能力。然而，这种控制是以增加配置复杂性和对VM及其操作系统和运行软件的持续管理责任为代价的 。

## 三、Nginx反向代理详细配置

Nginx是一款高性能的HTTP和反向代理服务器，常用于暴露、保护和扩展Web应用程序。

- Nginx安装 (Nginx Installation):
    

- 在中介VM上，根据其Linux发行版安装Nginx。例如，在Debian/Ubuntu系统上，执行：  
    sudo apt update && sudo apt install nginx -y  
      
    

- 基础网络考量 (Basic Network Considerations):
    

- 确认Nginx配置为监听连接共享VPC的nic0的IP地址（或0.0.0.0如果VM上没有其他Web服务冲突）。
    
- 确保VM的nic1（连接内部VPC）具有到内部目标Nginx服务的网络连通性。
    

- Nginx核心配置 (nginx.conf, 通常位于/etc/nginx/nginx.conf或通过/etc/nginx/sites-available/中的配置文件导入):
    

- http块基础设置 (Basic http block settings): 通常包含一些全局设置，如：  
```nginx.conf
    http {  
        sendfile on;  
        tcp_nopush on;  
        tcp_nodelay on;  
        keepalive_timeout 65;  
        types_hash_max_size 2048;  
        include /etc/nginx/mime.types;  
        default_type application/octet-stream;  
      
        # Logging Settings  
        access_log /var/log/nginx/access.log;  
        error_log /var/log/nginx/error.log;  
      
        # Gzip Settings  
        gzip on;  
        #... other http block settings...  
        include /etc/nginx/conf.d/*.conf;  
        include /etc/nginx/sites-enabled/*;  
    }  
```
    
- server块配置 (Configuring the server block): 在/etc/nginx/sites-available/中创建一个新的配置文件（例如 internal-service-proxy.conf），然后在/etc/nginx/sites-enabled/中创建符号链接。
  ```nginx.conf  
    server {  
        # 监听nic0的IP地址和端口，例如监听在nic0的IP <nic0_ip> 的80端口  
        listen <nic0_ip>:80;  
        # 或者监听所有接口的80端口，如果nic0是主要接口且没有冲突  
        # listen 80;  
      
        # 客户端用于访问此服务的域名或代理IP  
        server_name your.service.example.com;  
      
        #... location块和其他server配置...  
    }  
  ```
    若要监听HTTPS流量，则使用 listen <nic0_ip>:443 ssl; 并配置SSL证书。
    
- location块配置 (Configuring location blocks):  

    ```nginx.conf
    location / { # 匹配所有请求路径  
        # proxy_pass 指令用于将请求转发到后端服务器  
        # <internal_nginx_service_ip> 是内部VPC中目标Nginx服务的私有IP  
        # <internal_service_port> 是内部Nginx服务监听的端口  
        proxy_pass http://<internal_nginx_service_ip>:<internal_service_port>; # [span_52](start_span)[span_52](end_span)[span_54](start_span)[span_54](end_span)  
      
        # proxy_set_header 指令用于修改或添加请求头  
        proxy_set_header Host $host; # 将原始请求的Host头传递给后端 [span_53](start_span)[span_53](end_span)[span_55](start_span)[span_55](end_span)  
        # $host变量包含原始请求中的Host头，或者如果Host头不存在，则为server_name  
        # proxy_set_header Host $http_host; # $http_host 总是原始请求中的Host头  
      
        proxy_set_header X-Real-IP $remote_addr; # 传递客户端的真实IP地址 [span_48](start_span)[span_48](end_span)  
        # $remote_addr 是直接连接到Nginx的客户端IP  
      
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; # 附加客户端IP到X-Forwarded-For列表 [span_56](start_span)[span_56](end_span)  
        # $proxy_add_x_forwarded_for 会将 $remote_addr 追加到可能已存在的 X-Forwarded-For 头  
      
        proxy_set_header X-Forwarded-Proto $scheme; # 传递原始请求的协议 (http或https)  
        # 这对于后端应用判断客户端原始连接是否为HTTPS非常重要，尤其当SSL在Nginx上终止时  
      
        # 其他可选的proxy指令  
        # proxy_connect_timeout 60s;  
        # proxy_send_timeout 60s;  
        # proxy_read_timeout 60s;  
        # proxy_buffering on;  
        # proxy_buffers 32 4k;  
    }  
    ```
    关于proxy_pass指令后的URI：如果proxy_pass的值包含URI（例如 http://backend/path/），则请求URI中匹配location的部分将被替换。如果proxy_pass的值不包含URI（例如 http://backend;），则完整的原始请求URI将传递给后端（可能会被修改）。
    
- proxy_bind指令 (Using proxy_bind - Critical for Multi-NIC): 在多NIC环境中，为了确保Nginx使用正确的源IP地址（即nic1的IP）与后端内部服务通信，应使用
- proxy_bind指令。  
  ```nginx.conf
    location / {  
        #... 其他proxy_pass和proxy_set_header指令...  
        proxy_bind <nic1_ip>; # <nic1_ip> 是VM连接到内部VPC的NIC的IP地址  
    }  
  ```
    若不使用proxy_bind，操作系统可能会根据其路由表选择默认出接口（可能是nic0）的IP作为源IP，这会导致内部VPC的防火墙规则不匹配或路由问题。proxy_bind强制Nginx从指定的nic1_ip发起对后端服务的连接，这对于流量的正确路由和内部VPC防火墙策略的执行至关重要。
    
- SSL/TLS终止配置 (SSL/TLS Termination - Recommended): 在Nginx代理上终止SSL/TLS连接是一种常见的安全实践，可以减轻后端服务的负担。  
```nginx.conf
    server {  
        listen <nic0_ip>:443 ssl http2; # 监听HTTPS和HTTP/2  
        server_name your.service.example.com;  
      
        ssl_certificate /etc/nginx/ssl/your.service.example.com.fullchain.pem;  
        ssl_certificate_key /etc/nginx/ssl/your.service.example.com.privkey.pem;  
      
        # 推荐的SSL/TLS安全设置  
        ssl_protocols TLSv1.2 TLSv1.3;  
        ssl_prefer_server_ciphers off;  
        ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';  
        ssl_session_timeout 1d;  
        ssl_session_cache shared:SSL:10m; # 10MB共享缓存  
        ssl_session_tickets off;  
        # HSTS (可选, 强制浏览器使用HTTPS)  
        # add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";  
      
        location / {  
            proxy_pass http://<internal_nginx_service_ip>:<internal_service_port>; # 后端可以是HTTP  
            proxy_set_header Host $host;  
            proxy_set_header X-Real-IP $remote_addr;  
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;  
            proxy_set_header X-Forwarded-Proto $scheme; # $scheme 将为 'https'  
            proxy_bind <nic1_ip>;  
        }  
    }  
```      
    

- 完整配置示例与说明 (Complete Configuration Example and Explanation): 假设:
    

- 中介VM nic0 IP (共享VPC): 10.100.0.10
    
- 中介VM nic1 IP (内部VPC): 10.200.0.10
    
- 内部Nginx服务IP (内部VPC): 192.168.1.5，端口 8080
    
- 对外服务域名: app.example.com (解析到 10.100.0.10)
    

配置文件 (/etc/nginx/sites-available/app-proxy.conf):
```nginx.conf
server {  
    listen 10.100.0.10:443 ssl http2;  
    server_name app.example.com;  
  
    ssl_certificate /etc/nginx/ssl/app.example.com.fullchain.pem;  
    ssl_certificate_key /etc/nginx/ssl/app.example.com.privkey.pem;  
  
    # Strong SSL security  
    ssl_protocols TLSv1.2 TLSv1.3;  
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';  
    ssl_prefer_server_ciphers off;  
    ssl_session_cache shared:SSL:50m;  
    ssl_session_timeout 1d;  
    ssl_session_tickets off;  
  
    # Security Headers  
    add_header X-Frame-Options "SAMEORIGIN" always;  
    add_header X-XSS-Protection "1; mode=block" always;  
    add_header X-Content-Type-Options "nosniff" always;  
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;  
    # add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline';" always; # Adjust CSP as needed  
    # add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;  
  
  
    location / {  
        proxy_pass http://192.168.1.5:8080;  
        proxy_set_header Host $host;  
        proxy_set_header X-Real-IP $remote_addr;  
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;  
        proxy_set_header X-Forwarded-Proto $scheme;  
        proxy_set_header X-Forwarded-Host $server_name;  
        proxy_set_header X-Forwarded-Port $server_port;  
  
        proxy_bind 10.200.0.10; # Crucial: Use nic1's IP for outgoing connection  
  
        proxy_http_version 1.1;  
        proxy_set_header Upgrade $http_upgrade;  
        proxy_set_header Connection "keep-alive"; # For persistent connections to backend  
  
        proxy_connect_timeout 60s;  
        proxy_send_timeout 90s;  
        proxy_read_timeout 90s;  
        proxy_buffering on;  
        proxy_buffer_size 16k;  
        proxy_buffers 4 32k;  
        proxy_busy_buffers_size 64k;  
        proxy_temp_file_write_size 64k;  
    }  
  
    # Optional: Custom error pages  
    # error_page 500 502 503 504 /50x.html;  
    # location = /50x.html {  
    #     root /usr/share/nginx/html;  
    # }  
}  
```
创建符号链接: 
`sudo ln -s /etc/nginx/sites-available/app-proxy.conf /etc/nginx/sites-enabled/`
 测试配置并重载Nginx: 
`sudo nginx -t && sudo systemctl reload nginx`

- GCP防火墙规则回顾 (GCP Firewall Rules Recap):
    

- 共享VPC: Ingress允许来自客户端的TCP 443流量到Nginx VM nic0 (10.100.0.10)。
    
- 内部VPC: Ingress允许来自Nginx VM nic1 (10.200.0.10)的TCP 8080流量到内部服务 (192.168.1.5)。Egress允许已建立的连接从内部服务响应回Nginx VM nic1。
    

Nginx作为反向代理，其核心价值在于它是一个应用层网关，能够理解HTTP/S流量，从而实现更智能的路由、请求/响应修改以及SSL终止等安全功能 。这与L3/L4层面的NAT或纯路由有着本质区别。在将原始客户端IP地址传递给后端服务方面，proxy_set_header X-Real-IP $remote_addr; 和 proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; 指令至关重要。后端Nginx服务（在内部VPC中）也必须配置为信任并读取这些头部（例如，使用Nginx的http_realip_module模块，并配置set_real_ip_from指向代理VM nic1的IP地址）。

## 四、Squid反向代理详细配置

Squid是一款功能丰富的代理服务器，常用于正向代理和反向代理（Web服务器加速）。

- Squid安装 (Squid Installation):
    

- 在中介VM上安装Squid。例如，在Debian/Ubuntu系统上：  
    sudo apt update && sudo apt install squid -y  
      
    

- 基础网络考量 (Basic Network Considerations):
    

- 与Nginx类似，Squid应配置为监听连接共享VPC的nic0的IP地址和端口，并通过nic1（连接内部VPC）连接到后端服务。
    

- Squid核心配置 (squid.conf, 通常位于/etc/squid/squid.conf):
    

- http_port 配置 (Configuring http_port for Accelerator Mode): Squid通过accel模式作为反向代理。  
```bash
    # <nic0_ip> 是VM在共享VPC中nic0的IP地址  
    # <port> 是Squid监听的端口，例如80  
    # defaultsite 指定了当Host头不匹配任何cache_peer域名时，默认的后端服务器  
    # <internal_service_domain_or_ip> 是内部服务的域名或IP  
    http_port <nic0_ip>:<port> accel defaultsite=<internal_service_domain_or_ip> no-vhost  
    no-vhost通常用于单个后端站点，对于Squid 3.2+版本适用 。如果需要基于域名的虚拟主机，则使用vhost。
```    
- cache_peer 配置 (Configuring cache_peer for Backend Service): 定义后端（源）服务器。  
  ```bash
    # <internal_service_ip> 是内部VPC中目标Nginx服务的IP  
    # <internal_service_port> 是其监听端口  
    # 'parent' 表示这是一个后端服务器  
    # '0' 是ICP/HTCP端口（0表示禁用）  
    # 'no-query' 表示不发送ICP查询  
    # 'originserver' 表明这是内容的源服务器  
    # 'name=myBackendService' 为此peer指定一个名称，用于ACL  
    cache_peer <internal_service_ip> parent <internal_service_port> 0 no-query originserver name=myBackendService  
   ```   
    
- 访问控制列表 (ACLs - Access Control Lists): ACL用于控制哪些请求被允许通过并转发到后端。  
  ```bash
    # 定义一个ACL，匹配发往内部服务域名的请求  
    acl internal_service_requests dstdomain <internal_service_domain_or_ip>  
    # 或者，如果直接使用IP匹配  
    # acl internal_service_requests dst <internal_service_ip>  
      
    # 允许匹配上述ACL的请求访问  
    http_access allow internal_service_requests  
      
    # 允许名为myBackendService的cache_peer处理匹配ACL的请求  
    cache_peer_access myBackendService allow internal_service_requests  
      
    # 拒绝所有其他http_access请求，防止Squid成为开放的正向代理  
    http_access deny all  
    # 拒绝myBackendService处理所有其他请求 (作为补充，http_access deny all应已阻止)  
    cache_peer_access myBackendService deny all  
    这些访问控制规则（尤其是http_access deny all）应放在配置文件的顶部，以优先生效，避免标准正向代理规则干扰反向代理功能 。
    ```
- 客户端IP传递 (Client IP Forwarding):
    

- Squid默认会添加或更新X-Forwarded-For头部，包含客户端IP。
    
- 确保forwarded_for on (这是默认设置)。
    
- 后端Nginx服务需要配置为信任并使用此头部来获取真实的客户端IP。
    

- 绑定出站连接到特定接口 (tcp_outgoing_address - Critical for Multi-NIC): 为了确保Squid在连接后端服务时使用nic1的IP地址作为源IP，需要配置tcp_outgoing_address。  
    # <nic1_ip> 是VM连接到内部VPC的NIC的IP地址  
    # internal_service_requests 是之前定义的ACL名称  
    tcp_outgoing_address <nic1_ip> internal_service_requests  
    此指令至关重要，它指示Squid在为匹配internal_service_requests ACL的请求连接到cache_peer时，使用<nic1_ip>作为出站连接的源IP地址。没有此配置，Squid可能会使用操作系统的默认出站IP（可能是nic0的IP），导致内部VPC的路由或防火墙问题。
    

- 完整配置示例与说明 (Complete Configuration Example and Explanation): 假设:
    

- 中介VM nic0 IP (共享VPC): 10.100.0.10，监听端口 80
    
- 中介VM nic1 IP (内部VPC): 10.200.0.10
    
- 内部Nginx服务IP (内部VPC): 192.168.1.5，端口 8080
    
- 对外服务域名: app.example.com (DNS解析到 10.100.0.10)
    

配置文件 (/etc/squid/squid.conf):
```squid.conf
# Squid监听共享VPC nic0的IP和80端口，作为app.example.com的反向代理  
http_port 10.100.0.10:80 accel defaultsite=app.example.com no-vhost  
  
# 定义后端Nginx服务  
cache_peer 192.168.1.5 parent 8080 0 no-query originserver name=myInternalNginx  
  
# ACL匹配发往app.example.com的请求  
acl app_requests dstdomain app.example.com  
  
# 强制Squid使用nic1的IP (10.200.0.10) 连接后端  
tcp_outgoing_address 10.200.0.10 app_requests  
  
# 允许访问匹配的请求  
http_access allow app_requests  
cache_peer_access myInternalNginx allow app_requests  
  
# 拒绝所有其他请求  
http_access deny all  
cache_peer_access myInternalNginx deny all # 确保不转发其他请求到此后端  
  
# 开启X-Forwarded-For头部 (默认即为on)  
forwarded_for on  
  
# 可选：定义缓存目录和内存大小 (如果需要缓存功能)  
# cache_dir ufs /var/spool/squid 5000 16 256  # 5GB缓存, 16个一级目录, 256个二级目录  
# cache_mem 512 MB  
  
# 定义一个可见的主机名 (用于错误页面等)  
visible_hostname squid-proxy.example.com  
  
# 其他Squid配置 (例如日志格式、刷新模式等)  
#...  
```
配置完成后，需要重启Squid服务: 
`sudo systemctl restart squid`

- GCP防火墙规则回顾 (GCP Firewall Rules Recap):
    

- 与Nginx方案类似：共享VPC允许Ingress TCP 80流量到Squid VM nic0 (10.100.0.10)。内部VPC允许Ingress TCP 8080流量从Squid VM nic1 (10.200.0.10)到内部服务 (192.168.1.5)，并允许相应的Egress响应流量。
    

尽管Squid可以作为反向代理，但其历史优势和主要设计通常围绕Web内容缓存，以提高性能并减少后端服务器负载 。与Nginx的proxy_bind类似，Squid的tcp_outgoing_address <nic1_ip> <acl_name>指令对于确保到后端源服务器的连接源自VM的nic1 IP地址至关重要。若无此指令，Squid可能使用操作系统的默认出站IP（可能是nic0_ip），导致内部VPC中的路由失败或防火墙阻止。此指令将源IP选择与特定的ACL匹配请求相关联，提供了细粒度的控制。

对于不以复杂缓存为主要需求的简单HTTP/S反向代理场景，Nginx的配置通常被认为比Squid更直接和现代化。Squid的配置及其丰富的ACL和指令集，对于简单任务可能显得更为冗长 。选择哪种工具可能取决于团队现有的专业知识或特定的缓存需求。

## 五、安全考量

无论选择哪种VM中介方案，都必须仔细考虑安全 implications。

- GCP防火墙最佳实践 (GCP Firewall Best Practices):
    

- 最小权限原则: 严格遵循最小权限原则，仅允许必要的协议、端口和源/目标IP范围。GCP防火墙默认拒绝所有入站流量，允许所有出站流量，应根据需要创建明确的允许规则 。
    
- 针对性规则: 为中介VM的每个NIC（nic0和nic1）创建具体的防火墙规则。
    

- nic0 (共享VPC接口): Ingress规则应限制源IP为共享VPC中合法的客户端范围或特定网络标签，目标端口为VM暴露的服务端口（例如，代理的80/443，或NAT的暴露端口）。
    
- nic1 (内部VPC接口): Egress规则应允许nic1_ip访问内部目标服务的特定IP和端口。Ingress规则应允许来自内部服务的响应流量到达nic1_ip。
    

- 使用网络标签或服务账户: 尽可能使用网络标签或服务账户来限定防火墙规则的应用范围，使其仅作用于特定的VM实例（如中介VM、客户端VM、后端服务VM），而不是整个网络 。
    
- 日志记录: 为关键的防火墙规则启用日志记录功能，以便进行安全审计和故障排查 。
    
- 状态化检查: 理解GCP防火墙是状态化的，这意味着一旦允许出向连接，相应的返回流量将自动被允许，无需额外配置返回流量的入站规则 。
    

- 虚拟机操作系统加固 (VM Operating System Hardening):
    

- 最小化安装: 在中介VM上仅安装运行所选方案所必需的软件包，减少潜在攻击面。
    
- 定期更新与补丁: 及时更新操作系统及所有已安装软件（如Nginx、Squid、iptables等）的安全补丁。
    
- 禁用不必要的服务: 关闭VM上所有非必需的系统服务和网络端口。
    
- 主机防火墙 (Host-based Firewall - e.g., iptables/ufw):
    

- 除了GCP防火墙外，还应在VM操作系统层面配置防火墙（如iptables或ufw），作为纵深防御的一部分。这对于启用了IP转发的VM（NAT网关或路由器）尤其重要。
    
- 对于NAT/路由器VM，iptables的FORWARD链规则至关重要，必须精确控制允许转发的流量类型和方向。
    
- 对于代理VM，iptables的INPUT链规则用于保护代理服务本身免受未授权访问。
    

- SSH访问安全: 采用基于密钥的SSH身份验证，禁用密码认证。将SSH访问限制在可信的源IP地址（例如，通过堡垒机或GCP的IAP TCP转发）。考虑使用OS Login进行更集中的SSH访问管理 。建议在VM实例元数据中启用“阻止项目范围的SSH密钥”，并确保“允许连接到串行端口”未被启用，除非绝对必要 。
    

- IAM最小权限原则 (IAM Least Privilege for VM Service Account):
    

- 为中介VM分配一个专用的服务账户 (Service Account)。
    
- 授予此服务账户完成其任务所需的最小权限。例如，如果VM需要向Cloud Logging写入日志或向Cloud Monitoring发送指标，则仅授予这些特定权限。通常，网络中介VM不应拥有广泛的项目级角色（如Editor或Owner）。
    
- 避免使用具有广泛权限的默认Compute Engine服务账户 。
    

- 日志记录与监控 (Logging and Monitoring):
    

- Nginx/Squid日志: 配置代理软件（Nginx或Squid）记录详细的访问日志和错误日志。考虑将这些日志导出到Cloud Logging进行集中分析和存储。
    
- VPC流日志 (VPC Flow Logs): 为共享VPC和内部VPC中的相关子网启用VPC流日志，以获取网络流量的详细可见性，有助于故障排查和安全事件分析 。
    
- Cloud Monitoring: 使用Cloud Monitoring监控中介VM的性能指标（如CPU利用率、内存使用、网络吞吐量）。如果使用监控代理，还可以收集Nginx或Squid的特定应用指标。
    

对于充当NAT网关或路由器的VM（启用了IP转发），其安全模型比简单的端点VM更为复杂。纵深防御变得至关重要。这意味着不能仅依赖GCP防火墙规则，还必须细致配置操作系统级防火墙（如iptables的FORWARD链）并对操作系统本身进行加固。这是因为一旦GCP防火墙允许流量到达VM，VM的操作系统就负责正确、安全地转发这些流量。如果操作系统被入侵或配置不当（例如，过于宽松的iptables FORWARD规则），即使GCP对VM的入站规则有所限制，也可能导致VPC之间的未授权访问或数据泄露。

使用VM作为网络设备（NAT、路由器、代理）将比使用GCP托管服务承担更多的用户责任，包括操作系统的补丁管理、软件配置、安全加固以及对VM本身的详细监控 。中介VM服务账户的安全性也不容忽视。如果VM上的服务账户权限过高（例如，拥有修改防火墙规则或路由的权限），一旦VM本身被攻破，攻击者可能利用这些权限来更改GCP资源或访问其他服务。因此，网络中介VM的服务账户应严格遵循最小权限原则，理想情况下不应具有修改网络基础设施的权限，仅保留操作所需的基本权限（如写入日志和指标）。

## 六、方案比较与建议

为了清晰地对比上述基于VM的方案，下表总结了它们在关键特性上的差异：

表1：虚拟机方案对比：NAT网关 vs. 静态路由 vs. Nginx反向代理 vs. Squid反向代理

|特性/标准 (Feature/Criterion)|基于iptables的NAT网关 (VM-based NAT - iptables)|基于静态路由的路由器 (VM-based Static Routing)|Nginx反向代理 (Nginx Reverse Proxy)|Squid反向代理 (Squid Reverse Proxy)|
|---|---|---|---|---|
|实现复杂度 (Implementation Complexity)|高 (iptables, OS路由, GCP路由/防火墙)|中 (OS路由, GCP路由/防火墙, IP转发)|中 (Nginx配置, GCP防火墙)|中高 (Squid配置, ACLs, GCP防火墙)|
|性能开销 (Performance Overhead)|中 (iptables处理, VM转发)|低-中 (VM转发)|低-中 (Nginx处理, SSL开销)|中 (Squid处理, 缓存查找, SSL开销)|
|安全性 (Security)|中 (依赖iptables规则严谨性, IP层隔离)|低 (内部IP暴露, 依赖防火墙规则)|高 (应用层代理, 隐藏后端, SSL终止)|高 (应用层代理, 隐藏后端, 强大ACLs)|
|可扩展性 (Scalability)|VM实例组 + 内部负载均衡器 (ILB)|VM实例组 + ILB|VM实例组 + ILB|VM实例组 + ILB|
|可维护性 (Maintainability)|高 (OS, iptables, 软件)|中 (OS, 软件)|中 (OS, Nginx, 软件)|中 (OS, Squid, 软件)|
|成本 (Cost)|VM实例, 网络流量|VM实例, 网络流量|VM实例, 网络流量|VM实例, 网络流量|
|客户端透明度 (Client Transparency)|部分透明 (IP/端口可能改变)|完全透明 (访问真实内部IP)|不透明 (访问代理IP/端口)|不透明 (访问代理IP/端口)|
|协议支持 (Protocol Support)|TCP, UDP, 其他IP协议|TCP, UDP, 其他IP协议|HTTP, HTTPS, (TCP/UDP流)|HTTP, HTTPS, FTP|
|服务暴露粒度 (Service Exposure Granularity)|IP:Port|IP:Port|URL路径, 域名|URL路径, 域名|
|客户端IP保留 (Client IP Preservation to Backend)|复杂 (SNAT例外或特定iptables标记)|自动 (无NAT)|标准 (X-Forwarded-For等头部)|标准 (X-Forwarded-For等头部)|
|适用场景 (Use Cases)|通用TCP/UDP服务暴露,需IP隔离|需最高透明度且能严格控制网络的场景 (不推荐)|Web服务, API网关, SSL终止, 负载均衡|Web服务, 缓存加速, 内容过滤|

- 详细分析与推荐 (Detailed Analysis and Recommendations):
    

- 基于iptables的NAT网关:
    

- 优点：对上层协议通用（支持TCP、UDP及其他IP协议），可以提供一定程度的IP地址隔离。
    
- 缺点：iptables规则配置复杂且容易出错，性能瓶颈可能出现在单个VM上。客户端真实IP的保留需要复杂的SNAT例外或特定的iptables标记/连接跟踪配置。其安全性高度依赖于iptables规则的严谨程度和正确性。
    

- 基于静态路由的路由器:
    

- 优点：对客户端最为透明，因为客户端直接使用内部服务的真实IP地址进行通信（通过路由引导）。协议通用性好。
    
- 缺点：安全性最低，因为内部网络结构和服务的真实IP地址通过路由直接暴露给了共享VPC。防火墙规则必须极其精确和严格。此方案对VPC间的IP地址重叠问题非常敏感，一旦发生重叠则无法工作。通常不推荐此方案，除非有非常特殊的理由并且能够承担相应的安全风险。
    

- Nginx反向代理:
    

- 优点：提供应用层（L7）控制，如SSL/TLS终止、基于URL路径的路由、请求/响应头修改等。能够有效隐藏后端服务的拓扑结构，安全性较高。易于集成Web应用防火墙 (WAF)。客户端IP保留机制成熟（通过HTTP头部）。
    
- 缺点：主要适用于HTTP/S协议（尽管Nginx也支持TCP/UDP流代理，但功能相对HTTP代理较少）。Nginx软件本身也需要进行配置、维护和更新。
    

- Squid反向代理:
    

- 优点：强大的Web内容缓存功能，显著提升重复请求的响应速度并降低后端负载。同样提供L7控制和灵活的访问控制列表 (ACLs) 。
    
- 缺点：对于非缓存场景，其配置可能比Nginx更为复杂。其主要优势在于缓存，如果核心需求不是缓存，Nginx可能是更轻量级的选择。
    

- 针对不同需求的推荐 (Recommendations based on different needs):
    

- 若需暴露多种TCP/UDP服务（非HTTP/S），且希望实现一定程度的IP隔离和端口映射，可以考虑基于iptables的NAT网关方案。但需注意其配置复杂性和对客户端IP保留的挑战。
    
- 若主要目标是暴露HTTP/S类型的Web服务或API，强烈推荐使用Nginx反向代理。它在安全性、功能丰富性（SSL终止、路径路由、头部处理）和易用性之间取得了良好平衡。
    
- 如果暴露的HTTP/S服务具有大量静态或可缓存内容，并且希望通过缓存加速访问、减少后端压力，则Squid反向代理是更合适的选择。
    
- 基于静态路由的路由器方案因其固有的安全风险，通常不建议用于生产环境，除非有不可替代的透明性需求且已实施了极其严格的补充安全措施。
    

选择哪种方案并非仅仅是技术实施细节，而是一个影响安全态势、运维开销和应用架构的战略决策。值得注意的是，本报告主要讨论单个VM的实现。在生产环境中，为了保证高可用性 (HA) 和可扩展性，通常需要将中介VM（无论是NAT、路由器还是代理）部署在托管实例组 (MIG) 中，并配合内部负载均衡器 (ILB) 来分发流量和实现故障切换 。这会进一步增加系统的复杂性，但对于关键业务是必不可少的。

## 七、结论

- 关键发现总结 (Summary of Key Findings):
    

- 通过配置多NIC虚拟机，确实可以在隔离的GCP VPC网络之间安全有效地暴露内部服务。
    
- 基于iptables的NAT网关方案提供了协议通用性，但配置复杂且对客户端IP保留处理不便。
    
- 基于静态路由的VM路由器方案透明度最高，但安全风险也最大，直接暴露了内部网络细节。
    
- Nginx反向代理方案在暴露HTTP/S服务方面表现出色，提供了应用层控制、SSL终止和较好的安全性。
    
- Squid反向代理方案在Nginx的基础上，额外提供了强大的缓存功能，适用于内容分发和加速场景。
    

- 最佳实践回顾 (Recap of Best Practices):
    

- 成功的部署高度依赖于细致的网络规划，包括IP地址方案、避免重叠。
    
- 严格配置GCP防火墙规则，遵循最小权限原则，针对每个NIC和预期流量精确定义规则。
    
- 对中介VM进行操作系统层面的安全加固，包括最小化安装、定期更新、配置主机防火墙。
    
- 为VM的服务账户应用IAM最小权限原则，限制其对GCP资源的访问能力。
    
- 实施全面的日志记录和监控策略，覆盖VPC流日志、防火墙规则日志、代理/系统日志和性能指标。
    

- 最终建议 (Final Recommendations):
    

- 对于大多数Web服务和API的暴露场景，Nginx反向代理通常是首选方案。它在安全性、灵活性和功能丰富性之间提供了最佳平衡，特别是其SSL终止、基于路径的路由和修改HTTP头部的能力，非常适合现代应用架构。
    
- 如果主要需求是缓存静态内容以加速访问，Squid反向代理则更具优势。
    
- 只有在确实需要暴露非HTTP/S的TCP/UDP服务，并且能够接受其复杂性和潜在安全挑战时，才应考虑基于iptables的NAT网关。
    
- 应极力避免使用基于静态路由的VM路由器方案来直接暴露内部服务，除非有充分的理由且已部署了强大的补偿性安全控制。
    
- 最终决策应基于对具体业务需求、安全策略、团队运维能力以及对各种方案优缺点的全面理解。对于生产环境，还应进一步考虑所选方案的高可用性和可扩展性设计。
    

#### Works cited

| 序号 | 标题 | 链接 |
|------|------|------|
| 1 | Virtual Private Cloud (VPC) overview | [Google Cloud](https://cloud.google.com/vpc/docs/overview) |
| 2 | How to setup network connectivity between VPCs in Google Cloud | [Xebia](https://xebia.com/blog/how-to-setup-network-connectivity-between-vpcs-in-google-cloud/) |
| 3 | Multiple network interfaces - VPC | [Google Cloud](https://cloud.google.com/vpc/docs/multiple-interfaces-concepts) |
| 4 | Configure routing for an additional network interface - VPC | [Google Cloud](https://cloud.google.com/vpc/docs/configure-routing-additional-interface) |
| 5 | Quickstart: Set up Google Cloud to work with your Bare Metal | [Google Cloud](https://cloud.google.com/bare-metal/docs/bms-setup) |
| 6 | GCP VM instances have IP Forwarding enabled | [Prisma Cloud Documentation](https://docs.prismacloud.io/en/enterprise-edition/policy-reference/google-cloud-policies/google-cloud-networking-policies/bc-gcp-networking-12) |
| 7 | VPC firewall rules - Cloud NGFW | [Google Cloud](https://cloud.google.com/firewall/docs/firewalls) |
| 8 | Static routes - VPC | [Google Cloud](https://cloud.google.com/vpc/docs/static-routes) |
| 9 | Routes - VPC | [Google Cloud](https://cloud.google.com/vpc/docs/routes) |
| 10 | How to DNAT to GCE instance in subnetwork (port forwarding)? | [Google Groups](https://groups.google.com/g/gce-discussion/c/tmov7lFwyTg) |
| 11 | Forwarding Ports with Iptables in Linux: A How-To Guide | [CloudSigma](https://blog.cloudsigma.com/forwarding-ports-with-iptables-in-linux-a-how-to-guide/) |
| 12 | Using Masquerading with Iptables for Network Address Translation (NAT) | [GeeksforGeeks](https://www.geeksforgeeks.org/using-masquerading-with-iptables-for-network-address-translation-nat/) |
| 13 | Use VPC firewall rules - Cloud NGFW | [Google Cloud](https://cloud.google.com/firewall/docs/using-firewalls) |
| 14 | GCP Firewall rule allows all traffic on MySQL DB port (3306) | [Prisma Cloud Documentation](https://docs.prismacloud.io/en/enterprise-edition/policy-reference/google-cloud-policies/google-cloud-networking-policies/ensure-gcp-firewall-rule-does-not-allows-all-traffic-on-mysql-port-3306) |
| 15 | GCP Firewall rule allows all traffic on RDP port (3389) | [Prisma Cloud Documentation](https://docs.prismacloud.io/en/enterprise-edition/policy-reference/google-cloud-policies/google-cloud-networking-policies/bc-gcp-networking-2) |
| 16 | NGINX Reverse Proxy | [NGINX Documentation](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/) |
| 17 | Squid Configuration | [Squid Support - ViSolve](https://www.visolve.com/squid/whitepapers/reverseproxy.html) |
| 18 | How to create a VM with multiple network interfaces in Google Cloud | [YouTube](https://www.youtube.com/watch?v=iq2lPkev3NA) |
| 19 | Securely connecting to VM instances - Compute Engine | [Google Cloud](https://cloud.google.com/solutions/connecting-securely) |
| 20 | Configuring a Basic Reverse Proxy (Website Accelerator) | [Squid Wiki](https://wiki.squid-cache.org/ConfigExamples/Reverse/BasicAccelerator) |
| 21 | How to proxy requests to an internal server using nginx? | [Server Fault](https://serverfault.com/questions/366423/how-to-proxy-requests-to-an-internal-server-using-nginx) |
| 22 | Exploring GCP With Terraform: VPCs, Firewall Rules And VMs | [DevCube](https://rnemet.dev/posts/gcp/gcp_tf_vpc/) |
| 23 | 24 Google Cloud Platform (GCP) security best practices | [Sysdig](https://sysdig.com/learn-cloud-native/24-google-cloud-platform-gcp-security-best-practices/) |
| 24 | Google Cloud Security best practices | [NordLayer](https://nordlayer.com/blog/google-cloud-security-best-practices/) |

**