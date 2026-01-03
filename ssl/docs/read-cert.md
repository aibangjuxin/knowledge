如果我使用OpenSSL s_client -connect public-stg.api.gov.sg:443 -showcerts > output.txt 导出了这个文件，我想要分析里面的每个证书是什么，比如我能看到每段都有begin 和end 之类的，我能用最简单的openssl命令读取这些信息？我关注这些信息那些是根证书那些事中间之类的


要分析 `output.txt` 文件中的证书，可以使用 OpenSSL 提供的 `x509` 工具来提取和查看每个证书的信息。每个证书都由 `-----BEGIN CERTIFICATE-----` 和 `-----END CERTIFICATE-----` 包围。

你可以按照以下步骤进行分析：

1. **分割证书**：首先，你需要把文件中的每个证书提取出来。可以手动复制每段包含 `BEGIN CERTIFICATE` 和 `END CERTIFICATE` 的部分，也可以用脚本自动处理。

2. **查看证书内容**：使用 `openssl x509` 命令查看每个证书的详细信息。你可以用以下命令来查看证书内容：

   ```bash
   openssl x509 -in <certificate-file> -noout -text
   ```

   其中，`<certificate-file>` 是提取出的每个证书文件的路径。

3. **确定证书类型**：
   - **根证书**（Root CA）：通常是自签名证书，`Issuer` 和 `Subject` 字段相同。
   - **中间证书**（Intermediate CA）：`Issuer` 字段和 `Subject` 字段不同，并且 `Issuer` 字段指向另一个证书。

以下是一个具体的例子来说明如何操作：

```bash
# 提取第一个证书到文件
awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' output.txt > cert1.pem

# 提取第二个证书到文件
awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {if(++n==2) {print $0}}' output.txt > cert2.pem

# 查看第一个证书内容
openssl x509 -in cert1.pem -noout -text

# 查看第二个证书内容
openssl x509 -in cert2.pem -noout -text
```

在查看每个证书的内容时，检查 `Issuer` 和 `Subject` 字段来判断证书类型。

这些命令将帮助你识别哪些是根证书，哪些是中间证书。根证书的`Issuer`和`Subject`通常是相同的，而中间证书的`Issuer`通常会指向上级的CA。
