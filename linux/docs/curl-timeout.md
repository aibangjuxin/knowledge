在使用`curl`命令行工具时，可以通过选项来设置请求的连接超时和返回的响应超时。下面是常用的选项：

### 1. **连接超时 (`--connect-timeout`)**
此选项用于设置`curl`尝试连接到服务器的最大时间。如果超过这个时间仍未建立连接，则`curl`会终止尝试并返回错误。

```bash
curl --connect-timeout <秒数> <URL>
```

例如，要设置连接超时为10秒：

```bash
curl --connect-timeout 10 https://example.com
```

### 2. **总超时时间 (`--max-time`)**
此选项用于设置整个请求和响应过程的最大时间，包括连接时间、数据传输时间等。如果超时，`curl`会停止传输并返回错误。

```bash
curl --max-time <秒数> <URL>
```

例如，要设置整个请求的最大时间为30秒：

```bash
curl --max-time 30 https://example.com
```

### 3. **读取超时 (`--speed-time` and `--speed-limit`)**
这些选项用于设置`curl`在下载数据时的超时条件。例如，可以设置如果速度低于某个阈值超过一定时间，则停止传输。

- `--speed-time <秒数>`: 指定速度低于`--speed-limit`时，允许的最长时间。
- `--speed-limit <字节数>`: 设置速度的最低阈值（字节/秒）。

例如，如果速度低于1000字节/秒超过30秒，`curl`将中断连接：

```bash
curl --speed-time 30 --speed-limit 1000 https://example.com
```

### 示例
假设需要在连接和等待响应时都设置超时，可以结合使用：

```bash
curl --connect-timeout 10 --max-time 60 https://example.com
```

在这个例子中，`curl`将尝试在10秒内建立连接，并在连接成功后允许最多60秒来完成整个请求和响应过程。
