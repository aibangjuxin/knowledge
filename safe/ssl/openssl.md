你可以使用 openssl s_client 命令来测试一个 HTTPS 站点是否可以正常访问，并检查 SSL/TLS 的握手过程。以下是具体的步骤和命令：

基本命令

openssl s_client -connect <域名>:443

参数说明
	•	<域名>：替换为你要测试的 HTTPS 站点的域名，例如 www.example.com。
	•	443：默认的 HTTPS 端口。

示例

测试 https://www.google.com：

openssl s_client -connect www.google.com:443

输出结果

执行命令后，可能会返回以下关键信息：
	1.	SSL/TLS 握手结果：
	•	SSL handshake has read ... 表示握手成功。
	•	如果握手失败，会提示具体的错误原因，例如证书问题或连接被拒绝。
	2.	证书链信息：
	•	会显示服务器返回的证书链（Certificate chain），包括中间证书和根证书。
	3.	证书详情：
	•	Server certificate 显示服务器的证书详细信息，包括 subject 和 issuer。
	4.	连接状态：
	•	如果输出 Verify return code: 0 (ok)，表示证书验证成功，站点可以正常访问。

检查特定主机名的证书

如果目标站点使用 SNI（服务器名称指示）来支持多个域名，你可以指定测试的主机名：

openssl s_client -connect <域名>:443 -servername <域名>

例如：

openssl s_client -connect www.google.com:443 -servername www.google.com

测试结果解释
	•	连接正常：
	•	输出中显示 Verify return code: 0 (ok)，说明站点可以正常访问，证书有效。
	•	常见错误：
	•	Verify return code: 20 (unable to get local issuer certificate)：客户端缺少根证书，可能需要更新 CA 证书。
	•	Verify return code: 21 (unable to verify the first certificate)：服务器未提供完整的证书链。
	•	Connection refused：目标服务器没有监听 HTTPS 请求。

高级用法

检查支持的协议版本（如 TLS 1.2 或 1.3）

指定 TLS 协议版本：

openssl s_client -connect <域名>:443 -tls1_2
openssl s_client -connect <域名>:443 -tls1_3

检查特定的证书信息

使用以下命令查看证书有效期等信息：

openssl s_client -connect <域名>:443 -servername <域名> | openssl x509 -noout -dates

总结

openssl s_client 是一个强大的工具，可以用来测试 HTTPS 站点的连通性、证书有效性和支持的协议。根据上述命令，你可以快速诊断站点是否可以正常访问，以及 SSL/TLS 配置是否正确。
