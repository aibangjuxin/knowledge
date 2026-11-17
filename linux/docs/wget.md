
要使用 `wget` 替换 `curl -kv` 访问一个站点的命令，可以参考以下 `wget` 命令：

```bash
wget --no-check-certificate --verbose https://example.com
```

### 参数说明：
- `--no-check-certificate`：类似于 `curl` 中的 `-k` 选项，这个参数告诉 `wget` 忽略证书检查，不验证 SSL 证书。
- `--verbose`：类似于 `curl` 中的 `-v` 选项，它会输出详细的请求和响应过程。

这样你就可以使用 `wget` 达到与 `curl -kv` 类似的效果。



这个错误提示 **`TLS error from peer(alert code 80)`** 通常表示在进行 TLS 握手时发生了内部错误，可能与服务器的 TLS 配置、证书问题，或 `wget` 的版本和支持的加密协议有关。

以下是一些可以尝试的解决方案：

1. **升级 `wget` 版本**：
   - 确保你正在使用最新版本的 `wget`，因为较老的版本可能不支持某些 TLS 协议或加密套件。

2. **指定 TLS 版本**：
   - 你可以尝试使用 `--secure-protocol` 选项指定一个兼容的 TLS 版本，比如 TLSv1、TLSv1_1、TLSv1_2 或 TLSv1_3：

     ```bash
     wget --no-check-certificate --secure-protocol=TLSv1_2 --verbose https://example.com
     ```

3. **禁用 SNI（Server Name Indication）**：
   - 如果服务器不支持 SNI 或处理 SNI 时出现问题，可以尝试禁用 SNI：

     ```bash
     wget --no-check-certificate --no-sni --verbose https://example.com
     ```

4. **使用 `openssl` 或 `gnutls-cli` 工具进行排查**：
   - 如果以上方法无法解决问题，可以使用 `openssl s_client` 或 `gnutls-cli` 工具来检查与服务器的 TLS 连接，看是否能获得更详细的错误信息。

   ```bash
   openssl s_client -connect example.com:443 -tls1_2
   ```

   这条命令会输出详细的握手过程，你可以检查是否有特定的 TLS 版本或加密套件不兼容的问题。

如果以上方法仍然无法解决问题，可能需要进一步检查服务器端的配置或联系服务器管理员解决 TLS 错误。



要使用 `wget` 访问某个站点并指定客户端证书，你可以使用以下命令：

```bash
wget --certificate=/path/to/client.crt --private-key=/path/to/client.key --ca-certificate=/path/to/ca.crt https://example.com
```

### 参数说明：
- `--certificate=/path/to/client.crt`：指定客户端证书文件的路径（通常是 `.crt` 或 `.pem` 格式）。
- `--private-key=/path/to/client.key`：指定与客户端证书匹配的私钥文件路径（通常是 `.key` 格式）。
- `--ca-certificate=/path/to/ca.crt`：指定CA证书路径，用于验证服务器的证书。如果服务器使用的是自签名证书或你有特定的CA证书，使用此选项。

### 示例命令：
假设你有以下文件：
- `client.crt`：客户端证书
- `client.key`：客户端证书对应的私钥
- `ca.crt`：根CA证书

那么命令会是：

```bash
wget --certificate=client.crt --private-key=client.key --ca-certificate=ca.crt https://example.com
```

### 注意事项：
- 确保证书和私钥文件的权限正确，`wget` 进程有权限读取这些文件。
- 如果不需要验证服务器证书，可以省略 `--ca-certificate` 或使用 `--no-check-certificate` 选项来忽略证书验证：

  ```bash
  wget --certificate=client.crt --private-key=client.key --no-check-certificate https://example.com
  ```

这样，`wget` 就可以使用指定的客户端证书进行 HTTPS 访问。
