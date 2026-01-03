

when I using curl command curl a url 
curl -v https://www.abc.com

I got this error:

* Trying 192.168.1.1...
* Connected to www.abc.com (192.168.1.1) port 443 (#0)
* schannel: disabled automatic use of client certificate
* schannel: next InitializeSecurityContext failed: CRYPT_E_REVOKED (0x80092010) - The certificate is revoked
* Closing connection 0
* schannel: shutting down SSL/TLS connection with www.abc.com port 443
curl: (35) schannel: next InitializeSecurityContext failed: CRYPT_E_REVOKED (0x80092010) - The certificate is revoked

这个情况仅仅在我的git bash中出现.这个curl 版本是8.1.2，在Chrome中可以正常访问。但是edge浏览器也会出现这个错误。
那么我如何解决或者修复这个问题?
这个情况是因为curl的版本么?我在Linux主机Curl也没有问题.Linux上的curl版本是7.29.0。



这个问题可能是由于 Windows 中的 Schannel 库与 SSL/TLS 证书之间的某种冲突或配置问题引起的。通常，这种问题可能会因为证书被吊销（revoked）而发生，正如错误消息中所述。

有几种方法可以尝试解决或修复这个问题：

1. **更新 Curl 版本**：考虑更新 Curl 到最新版本，因为新版本可能包含了修复或改进的功能。你可以访问 Curl 的官方网站或在 Git for Windows 中查看是否有可用的更新版本。

2. **检查证书有效性**：确保你的系统上的证书是有效的。你可以尝试手动更新或重新安装证书。

3. **检查操作系统设置**：有时候，操作系统的配置可能会导致此类问题。确保 Windows 操作系统的时间和日期设置正确，并检查是否存在任何网络代理或防火墙设置可能干扰了 SSL/TLS 连接。

4. **尝试不同的 SSL/TLS 库**：Curl 可以使用不同的 SSL/TLS 库进行编译。在 Git for Windows 中，默认使用的是 Schannel 库。你可以尝试使用其他库，如 OpenSSL，来查看是否能够解决问题。

5. **检查 Curl 配置**：检查 Curl 的配置文件，看看是否有任何不当的配置可能导致了这个问题。

6. **使用 Linux 主机的 Curl**：如果在 Linux 主机上 Curl 没有问题，你可以尝试使用 WSL (Windows Subsystem for Linux) 或者在 Windows 上安装一个虚拟机来运行 Linux，并使用 Linux 主机的 Curl 进行访问。

在解决问题时，最好是逐步尝试这些方法，以确定哪一个方法适用于你的情况。

The error you are encountering, "curl: (35) schannel: next InitializeSecurityContext failed: CRYPT_E_REVOKED (0x80092010) - The certificate is revoked", indicates that the certificate for the website [https://abc.com/](https://abc.com/) has been revoked. This means that the certificate is no longer considered to be trustworthy, and curl is refusing to connect to the website as a result.

There are a few possible reasons why this might be happening:

* **The certificate has been revoked by the issuing Certificate Authority (CA).** This could be because the certificate was issued fraudulently, or because it has been compromised.
* **The certificate has expired.** This is the most likely reason in this case, as you are only seeing the error in Git Bash and Edge, but not in Chrome. Chrome may have its own certificate store that is up-to-date, while Git Bash and Edge are using an outdated certificate store.

There are a few things you can do to try to fix the problem:

* **Update your certificate store.** This can be done by following the instructions for your specific operating system.
* **Use the `--insecure` option with curl.** This will tell curl to ignore the certificate revocation check and connect to the website anyway. However, this is not a secure solution and should only be used as a last resort.
* **Use a different browser.** Chrome is more likely to have an up-to-date certificate store than Git Bash or Edge.

In this case, the issue is most likely due to the different versions of curl and the certificate stores being used. The curl version 8.1.2 in Git Bash is likely using an outdated certificate store, while the curl version 7.29.0 on the Linux host and Chrome are using more up-to-date certificate stores.

To resolve this issue, you can try the following solutions:

* **Update the certificate store in Git Bash:**

  1. Download the latest certificate bundle from [https://curl.se/docs/sslcerts.html](https://curl.se/docs/sslcerts.html).
  2. Extract the downloaded bundle to a location that Git Bash can access.
  3. Set the `CURL_CA_BUNDLE` environment variable to point to the extracted bundle. For example, if you extracted the bundle to `/path/to/ca-bundle.crt`, you would set the environment variable as follows:

```
export CURL_CA_BUNDLE=/path/to/ca-bundle.crt
```

* **Use the `--insecure` option with curl:**

  This will tell curl to ignore the certificate revocation check and connect to the website anyway. However, this is not a secure solution and should only be used as a last resort.

```
curl --insecure https://www.abc.com
```

* **Use a different browser:**

  Chrome is more likely to have an up-to-date certificate store than Git Bash or Edge. You can try using Chrome to access the website.

It is important to note that using the `--insecure` option is not a secure solution and should only be used as a last resort. If you must use this option, you should only do so for testing purposes or for accessing websites that you know are trustworthy.

I hope this helps!




这个问题似乎与证书相关。根据您提供的错误信息 "CRYPT_E_REVOKED (0x80092010) - The certificate is revoked"，表明您的系统无法验证访问的网站的 SSL 证书有效性。

这可能有以下几个原因:

1. **证书吊销列表(CRL)过期或未正确更新**

   Windows 系统使用操作系统内置的证书吊销列表来检查证书的有效性。如果这个列表过期或未正确更新,就可能导致合法的证书被误判为已吊销。

2. **时间不同步**

   证书的有效期通常与时间相关,如果系统时间不准确,可能会导致证书验证失败。

3. **代理或防火墙干扰**

   如果您使用代理或防火墙,可能会影响 SSL 证书的验证过程。

4. **curl 版本差异**

   不同版本的 curl 使用的证书存储库可能不同,导致验证结果有差异。

解决方案:

1. **更新证书吊销列表**

   您可以尝试手动更新 Windows 操作系统的证书吊销列表。在命令提示符下运行 `certutil -urlcache` 命令。

2. **同步系统时间**

   确保您的系统时间准确无误,可手动同步或启用自动同步。

3. **禁用代理/防火墙**

   如果您使用代理或防火墙,可以尝试临时禁用它们,看是否可以解决问题。

4. **升级 curl**

   您也可以尝试升级 Git Bash 中的 curl 到最新版本,看是否可以解决问题。

如果以上方法都无法解决,您还可以尝试在 curl 命令中添加 `-k` 或 `--insecure` 选项,强制 curl 接受任何 SSL 证书。但这种做法不安全,生产环境中不建议使用。


既然您的 Chrome 浏览器可以正常访问该网站,但 Edge 浏览器和 Git Bash 中的 curl 都无法访问并出现相同的证书吊销错误,这表明该问题可能不是证书本身的问题,而更有可能是 Windows 操作系统或应用程序本身的证书存储或验证机制出现了问题。

您可以尝试以下解决方法:

1. **清除 SSL 状态**

   在命令提示符下运行以下命令,清除 Windows 的 SSL 缓存和状态:

   ```
   certutil -urlcache * delete
   ```

2. **重新安装受信任的根证书**

   有时候重新安装操作系统受信任的根证书可以解决此类问题。您可以从可信的来源下载根证书,然后双击该证书文件,选择"安装证书"将其导入"受信任的根证书颁发机构"存储区。

3. **更新 Windows 根证书程序**

   Microsoft 会定期发布更新,用于更新 Windows 操作系统的受信任根证书列表。请确保您的系统已经安装了最新的根证书更新。

4. **检查组策略设置**

   如果您的系统使用了组策略,可能会影响证书信任设置。您可以检查组策略编辑器中的相关设置,确保没有禁用任何证书信任的选项。

5. **检查防病毒软件或其他安全软件**

   某些防病毒或安全软件可能会干扰 SSL/TLS 证书的验证过程,请尝试临时禁用这些软件,看是否可以解决问题。

6. **升级 Edge 或 Git Bash 中的 curl**

   作为最后的尝试,您可以尝试升级 Edge 浏览器或 Git Bash 中的 curl 到最新版本,看是否可以解决问题。

如果以上方法都无法解决,您可能需要联系 Microsoft 支持人员寻求进一步的帮助。

您可以使用 `certutil` 命令删除 Windows 操作系统中所有的 SSL 缓存。具体步骤如下:

1. 打开命令提示符或 PowerShell (以管理员权限运行)

2. 执行以下命令:

```
certutil -urlcache * delete
```

该命令的含义是:
- `certutil`: Windows 证书实用程序
- `-urlcache`: 指定要操作的是 URL 缓存
- `*`: 通配符,表示操作所有缓存条目
- `delete`: 指定要执行的操作为删除

执行该命令后,所有缓存的 SSL 证书、证书吊销列表等都将被清除。

3. 等待命令执行完成,直到出现 "已成功删除 URL 资源"的消息。

4. 关闭命令提示符窗口。

清除 SSL 缓存后,您的系统将在下次尝试连接 SSL 网站时重新下载并缓存所需的证书和吊销列表。这有助于解决由于旧缓存导致的 SSL 证书问题。

需要注意的是,清除缓存可能会导致短暂的性能下降,因为系统需要重新获取所需的数据。但从长远来看,维护最新的 SSL 缓存对于确保连接安全性是非常重要的。




您遇到的问题与 Git Bash 中的 cURL 版本可能不兼容或配置不当有关。这个问题表明，当您尝试通过 Git Bash 使用 cURL 访问 `https://www.abc.com` 时，SSL/TLS 安全证书被认为是撤销的。这通常是因为证书确实被撤销，或者您的系统中的证书撤销列表（CRL）没有正确更新。

### 解决步骤

1. **更新 cURL 版本**：
   您可以尝试更新 Git Bash 中的 cURL 到最新版本。Windows 10 和 Windows 11 自带的 cURL 版本可能不是最新的，因此从官方网站下载并安装最新版本可能有助于解决问题[2][5][6]。

2. **检查系统日期和时间**：
   确保您的系统日期和时间是准确的。证书验证过程中会检查证书的有效期，如果系统时间不正确，可能会导致证书验证失败。

3. **手动安装证书**：
   如果问题仍然存在，您可能需要手动安装或更新 SSL/TLS 证书。这可以通过导入一个新的、有效的证书到您的系统来完成。

4. **使用其他工具验证**：
   使用浏览器或其他工具（如 Postman）尝试访问相同的 URL，看看是否能成功连接。这可以帮助确认问题是否仅限于 Git Bash 中的 cURL。

5. **禁用 SSL/TLS 证书验证**：
   作为临时解决方案，您可以在 cURL 命令中添加 `-k` 或 `--insecure` 参数来禁用证书验证，例如：
   ```bash
   curl -k https://www.abc.com
   ```
   请注意，这种方法会降低安全性，因为它不会验证服务器的 SSL/TLS 证书。

6. **检查 Edge 浏览器设置**：
   由于您提到 Edge 浏览器也出现了类似的问题，可能需要检查 Edge 的安全设置或更新其版本。

### 结论

这个问题不太可能仅仅由于 cURL 的版本引起，更可能是与 SSL/TLS 证书管理或系统配置相关的问题。按照上述步骤操作后，应该能够解决或确定问题的根源。如果问题依旧存在，可能需要进一步检查网络配置或与系统管理员联系以解决证书问题。

Citations:
[1] https://www.abc.com
[2] https://curl.se/windows/
[3] https://superuser.com/questions/1308241/checking-and-upgrade-curl-version-on-windows-server-2008r2
[4] https://learn.microsoft.com/en-us/answers/questions/1186328/update-curl-7-88-1-windows-server
[5] https://everything.curl.dev/install/windows/index.html
[6] https://tibbsforge.com/how-to-update-curl-exe/
[7] https://stackoverflow.com/questions/9507353/how-do-i-install-and-use-curl-on-windows
[8] https://www.reddit.com/r/sysadmin/comments/11dhuty/does_windows_server_actually_need_curl_theres_a/
[9] https://github.com/curl/curl/issues/11353
[10] https://curl.se/windows/microsoft.html
[11] https://forum.manjaro.org/t/curl-8-1-0-1-is-not-working-with-github/141785
[12] https://forum.storj.io/t/getting-certificate-error-while-using-curl-for-the-satellites-list/21397
[13] https://snyk.io/blog/how-to-update-curl/
[14] https://stackoverflow.com/questions/54938026/curl-unknown-error-0x80092012-the-revocation-function-was-unable-to-check-r
[15] https://stackoverflow.com/questions/76441479/windows-call-api-with-curl-with-certificates
[16] https://github.com/curl/curl/issues/4436
[17] https://talk.plesk.com/threads/error-could-not-get-mozilla-tls-config-curl-error-77.372049/
[18] https://learn.microsoft.com/en-us/answers/questions/590539/curl-%2835%29-schannel-next-initializesecuritycontext
[19] https://curl.se/changes.html
[20] https://discuss.elastic.co/t/curl-request-not-working-with-ca-certificate-on-windows/299566



您已经使用 OpenSSL 验证了服务器证书，并且证书没有过期。这意味着证书的有效期是正确的，但是证书链的完整性和证书的颁发者可能仍然需要检查。

在验证证书链时，OpenSSL 会检查证书链的完整性和证书的颁发者。证书链的完整性是指证书链中每个证书的签名都来自前一个证书的私钥。如果证书链不完整，OpenSSL 将无法验证证书的有效性。

在您使用 OpenSSL 验证证书时，您可以使用以下命令来检查证书链的完整性和证书的颁发者：

```bash
openssl verify -CAfile ROOT_CERT USER_CERT
```

其中，`ROOT_CERT` 是证书链的根证书，`USER_CERT` 是您想要验证的证书。

如果证书链不完整，您可能需要检查证书链的构建过程，确保每个证书的签名来自前一个证书的私钥。如果证书链已经正确构建，您可能需要检查证书的颁发者是否正确。

在验证证书的颁发者时，您可以使用以下命令来检查证书的颁发者：

```bash
openssl x509 -in USER_CERT -noout -subject -issuer
```

其中，`USER_CERT` 是您想要验证的证书。`subject` 是证书的主题，`issuer` 是证书的颁发者。

如果证书的颁发者不正确，您可能需要检查证书的颁发过程，确保证书的颁发者是正确的。

总之，您已经验证了证书的有效期，但是证书链的完整性和证书的颁发者仍然需要检查。

Citations:
[1] https://www.junmajinlong.com/linux/openssl_ca/index.html
[2] https://developer.aliyun.com/article/495008
[3] https://www.dell.com/support/kbdoc/zh-cn/000211907/%E5%B8%B8%E8%A7%84%E8%BF%87%E7%A8%8B%E5%A6%82%E4%BD%95%E9%AA%8C%E8%AF%81%E5%92%8C%E8%BD%AC%E6%8D%A2-ssl-%E8%AF%81%E4%B9%A6
[4] https://www.volcengine.com/theme/1123435-S-7-1
[5] https://www.volcengine.com/theme/7670989-O-7-1
[6] https://blog.csdn.net/huakai_sun/article/details/81812169
[7] https://www.cnblogs.com/coding-my-life/p/13910569.html
[8] https://blog.csdn.net/u012986012/article/details/106064998
[9] https://www.ssldragon.com/zh/blog/check-certificate-openssl-linux/
[10] https://help.aliyun.com/zh/ssl-certificate/support/the-certificate-chain-is-incomplete
[11] https://juejin.cn/s/openssl%E9%AA%8C%E8%AF%81%E8%AF%81%E4%B9%A6%E6%9C%89%E6%95%88%E6%80%A7
[12] https://juejin.cn/s/openssl%E8%AF%81%E4%B9%A6%E9%93%BE%E9%AA%8C%E8%AF%81
[13] https://www.cnblogs.com/real-bert/p/14744300.html
[14] https://blog.csdn.net/weixin_42636055/article/details/125223572
[15] https://www.volcengine.com/theme/1120777-S-7-1
[16] https://www.alibabacloud.com/help/zh/anti-ddos/how-to-handle-the-mismatch-between-a-certificate-and-its-private-key
[17] https://blog.csdn.net/Htojk/article/details/137122718
[18] https://m.aliyun.com/sswd/13553513-1.html
[19] https://www.volcengine.com/theme/9790169-R-7-1
[20] https://www.volcengine.com/theme/7552112-S-7-1


