https://www.squid-cache.org/Doc/config/adaptation_send_client_ip/
If enabled, Squid shares HTTP client IP information with adaptation
	services. For ICAP, Squid adds the X-Client-IP header to ICAP requests.
	For eCAP, Squid sets the libecap::metaClientIp transaction option.

	See also: adaptation_uses_indirect_client

如果启用，Squid 会与适配服务共享 HTTP 客户端 IP 信息。对于 ICAP，Squid 会向 ICAP 请求添加 X-Client-IP 头部。对于 eCAP，Squid 会设置 libecap::metaClientIp 事务选项。另请参见：adaptation_uses_indirect_client


