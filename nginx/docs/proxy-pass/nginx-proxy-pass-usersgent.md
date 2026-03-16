## Nginx proxy_pass默认会重写转发请求的User-Agent头信息

是的,Nginx代理请求时,默认会重写User-Agent头信息。

当Nginx作为代理服务器,转发请求到后端服务器时,它会重写User-Agent头信息,改为:

User-Agent: nginx/1.12.1


这是因为Nginx需要在转发的请求中加入自己的标识,以表示这是一个来自Nginx的代理请求。   

如果不希望Nginx重写User-Agent头信息,可以在代理配置中加入`proxy_set_header User-Agent $http_user_agent;`来保留原始User-Agent头:

nginx
location / {
  proxy_pass http://backend;
  proxy_set_header User-Agent $http_user_agent;  # 保留原始User-Agent
}


这样,后端服务器就能够接收到客户端真实的User-Agent信息。

总结:

- Nginx代理请求时,默认会重写User-Agent头信息
- 通过`proxy_set_header User-Agent $http_user_agent;`可以保留原始User-Agent头信息

如果客户端请求Nginx时指定了User-Agent头信息,那么在Nginx代理到后端服务器时:

- 如果不指定`proxy_set_header User-Agent $http_user_agent;,Nginx还是会重写User-Agent为nginx/1.12.1`
- 如果指定了`proxy_set_header User-Agent $http_user_agent;`,那么后端服务器接收到的User-Agent就是客户端请求时指定的User-Agent

举个例子:

客户端请求Nginx,请求头中User-Agent为:
User-Agent: My Custom Agent


Nginx配置中没有`proxy_set_header User-Agent $http_user_agent;`:

- 客户端请求Nginx时 User-Agent: My Custom Agent
- Nginx转发请求到后端,User-Agent变为:User-Agent: nginx/1.12.1
- 后端服务器接收到的User-Agent是:User-Agent: nginx/1.12.1

Nginx配置中有`proxy_set_header User-Agent $http_user_agent;`:

- 客户端请求Nginx时 User-Agent: My Custom Agent  
- Nginx转发请求到后端,User-Agent保持为:User-Agent: My Custom Agent
- 后端服务器接收到的User-Agent是:User-Agent: My Custom Agent

所以,如果需要让后端服务器接收到客户端的真实User-Agent,需要在Nginx的代理配置中指定`proxy_set_header User-Agent $http_user_agent;`来保留原始User-Agent头信息。

	
