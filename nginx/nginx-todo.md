- Why we need nginx-session-cache
	- **优化建议：**

	- **（最重要）避免再加密**：如果您的 Nginx 实例和后端 API 服务器（`10.98.0.188`）位于一个安全的私有网络中（例如，同一个 VPC 内），强烈建议将 `proxy_pass` 指向后端的 HTTP 端口，而非 HTTPS 端口。这将消除一半的 SSL 计算开销，是提升性能最有效的方法。
	    
	- **启用 SSL 会话缓存**：您的配置中缺少 `ssl_session_cache` 指令。没有它，Nginx 无法有效缓存 SSL 会话，导致更多代价高昂的完整握手。请在 `http` 块中添加此配置 ：  
	    
	    Nginx
	    
	    ```nginx
	    http {
	        #... 其他配置...
	        ssl_session_cache shared:SSL:10m; # 10MB 缓存大约可存储 40,000 个会话
	        ssl_session_timeout 1h;
	        #... 其他配置...
	    }
	    ```
	    
	    `ssl_session_cache` 通过在服务器端缓存会话信息来减少握手开销，而 `ssl_session_tickets`（默认为 on）则是将加密的会话信息存储在客户端 。启用  
	    
	    `ssl_session_cache` 是标准的高性能实践。
	- [ssl_session_cache](./nginx-session-cache.md)