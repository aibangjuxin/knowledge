在 Nginx 中启用和配置 Gzip 压缩可以显著减少传输数据量，从而提高页面加载速度。以下是详细的配置步骤和解释：

Nginx Gzip 配置步骤
	1.	打开 Nginx 配置文件
通常位于 /etc/nginx/nginx.conf 或站点配置目录 /etc/nginx/conf.d/your-site.conf。

sudo nano /etc/nginx/nginx.conf


	2.	配置 Gzip 参数
在 http 或 server 块中，添加或修改以下配置：

http {
    gzip on;                          # 开启 gzip 压缩
    gzip_comp_level 5;                # 压缩级别（范围 1-9，推荐 5）
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript; 
                                       # 压缩的 MIME 类型
    gzip_min_length 1024;             # 设置最小压缩长度（仅压缩大于 1KB 的响应）
    gzip_vary on;                     # 为代理服务提供 gzip 支持（设置 `Vary: Accept-Encoding` 头）
    gzip_proxied any;                 # 为代理服务启用 gzip（如反向代理）
    gzip_disable "msie6";             # 禁用对旧版 IE6 的 gzip 支持
}


	3.	重启 Nginx
保存配置文件后，重启 Nginx 使配置生效：

sudo nginx -t    # 测试配置文件是否正确
sudo systemctl restart nginx

关键参数说明

参数	作用
gzip on	开启 Gzip 压缩功能。
gzip_comp_level	设置压缩级别，范围 1（最快但压缩率低）到 9（最慢但压缩率高）。推荐值为 5。
gzip_types	指定要压缩的内容类型（MIME 类型），如 HTML、CSS、JavaScript 等。
gzip_min_length	设置最小压缩长度（字节）。小于此值的内容不会被压缩，避免对小文件压缩造成开销。
gzip_vary	设置 Vary: Accept-Encoding 响应头，便于代理服务器根据客户端支持的编码类型缓存内容。
gzip_proxied	为代理请求启用 Gzip。any 表示为所有代理请求启用 Gzip。
gzip_disable	针对特定用户代理禁用 Gzip（如旧版浏览器）。

验证 Gzip 是否启用
	1.	使用 curl 验证：

curl -H "Accept-Encoding: gzip" -I http://your-domain.com

检查响应头中是否有 Content-Encoding: gzip。

	2.	使用浏览器开发者工具：
	•	打开开发者工具。
	•	访问网站，查看 Network 标签。
	•	检查某个资源的响应头，确认是否包含 Content-Encoding: gzip。

注意事项
	•	确保客户端支持 Gzip（绝大多数现代浏览器都支持）。
	•	不建议压缩已经压缩过的内容（如 .jpg、.png、.zip 文件）。
	•	如果站点是 HTTPS，可能需要额外配置以避免 BREACH 攻击（可参考 Brotli 替代方案）。

如需更高效的压缩，可以考虑在 Gzip 基础上启用 Brotli 压缩：

brotli on;
brotli_comp_level 6;
brotli_types text/plain text/css application/javascript application/json application/xml+rss text/javascript;
