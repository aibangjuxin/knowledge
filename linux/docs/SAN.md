Subject Alternative Name (SAN) 是X.509数字证书标准中的一个扩展字段，用于在SSL/TLS证书中提供除主题名（Common Name, CN）之外的其他标识信息。传统的SSL证书仅通过CN来识别服务器或服务的主机名，但随着网络应用的发展和多域名、子域名的广泛使用，单一CN已经无法满足需求。

Subject Alternative Name可以包含：

	1.	DNS名称：例如，除了www.example.com，还可以列出mail.example.com或其他多个与证书相关联的域名或子域名。
	2.	IP地址：直接将证书与特定IP地址关联。
	3.	其他类型的身份标识，如RFC822名称（电子邮件地址）或者统一资源标识符（URI）等。

SAN扩展使得一张证书能够支持多个主机名，这种类型的证书通常被称为通配符证书或多域名证书，极大地提高了证书使用的灵活性和效率。