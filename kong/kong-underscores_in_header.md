对于Kong DP来说有个参数
undersores_in_headers on 或者Off这个什么意思?

- we can find the config at . Default setting on 
- /kong_proxy/nginx-kong.conf ==> on 

- nginx.conf setting ==> on 

记得Nginx里有个`underscores_in_headers`指令，它控制是否允许在请求头中使用下划线。默认情况下，这个参数是off，也就是Nginx会丢弃带有下划线的头字段。这可能是因为下划线在某些代理环境中不被支持，或者容易和连字符混淆，导致安全问题。

所以，当Kong的`underscores_in_headers`设为off时，任何带有下划线的请求头在到达Kong时会被自动忽略，这可能影响依赖于这些头的应用，比如认证头的Authorization_Bearer，如果带下划线就会被丢弃。而设为on的话，Kong就会保留这些头，确保后端服务能接收到。

用户可能是在使用Kong时遇到了头信息丢失的问题，特别是在使用自定义头或者某些第三方服务要求的头时，需要确认是否因为下划线导致的问题。这时候开启这个参数可以解决。另外，用户可能需要了解这个设置的安全考虑，比如防止头注入攻击，但权衡之后还是需要开启的话，就需要在配置中调整。

还需要注意，Kong的不同版本是否有变化，以及这个参数在配置文件中的具体位置，通常是在nginx的配置部分。此外，提醒用户如果开启后，可能还需要注意其他中间件或后端服务是否处理带下划线的头，避免出现不一致的情况。

在 Kong DP（数据平面）中，`underscores_in_headers` 是一个与请求头（HTTP Headers）处理相关的配置参数，它控制 **是否允许在 HTTP 头名称中使用下划线（`_`）**。其行为如下：

在Kong的微服务组件DP中，“underscores_in_headers on”或“off”是一个配置参数，用于控制日志中的下划线模式。具体来说：

underscores_in_headers on：启用下划线模式，使得日志条目使用下划线分隔符（_），这有助于提高日志的可读性和快速浏览。

underscores_in_headers off：关闭下划线模式，日志条目不再包含下划线，适用于需要更简洁或特定于某些工具的日志格式。

这个参数可以帮助用户根据需求调整Kong DP的日志输出方式，确保日志既符合性能要求，又便于后续的分析和理解。

---

### **`on` 或 `off` 的含义**
1. **`underscores_in_headers on`**  
   - 允许 HTTP 请求头名称中包含下划线（例如 `X_Custom_Header`）。  
   - Kong 会原样接收并转发这些带有下划线的头字段到上游服务（后端服务）。  
   - 这是 **非默认** 行为，需要显式配置。

2. **`underscores_in_headers off`**  
   - **默认值**。  
   - 如果请求头名称中包含下划线，Kong 会直接丢弃这些头字段，不会将它们传递给上游服务。  
   - 这种设计是为了避免潜在的安全风险（如某些代理或中间件对下划线的处理不一致导致漏洞）。

---

### **为什么需要这个参数？**
- **兼容性与安全性**：  
  HTTP 规范未明确禁止头名称中的下划线，但某些旧版代理或工具（如 Nginx，默认禁用下划线）可能不支持。Kong 基于 Nginx 的行为，默认遵循这一规则。  
  - 如果后端服务需要接收带下划线的头字段（例如某些遗留系统或第三方 API），需显式设置 `on`。
  - 如果不需要，保持默认的 `off` 可减少潜在风险（如 HTTP 头注入攻击）。

---

### **典型场景**
- **场景 1**：  
  你的上游服务要求使用 `X_Auth_Token` 这样的头字段，但请求到达上游时发现该头丢失。  
  **解决方案**：将 `underscores_in_headers` 设为 `on`。

- **场景 2**：  
  出于安全策略，需要过滤掉所有非标准头（如 `X_Internal_Debug`）。  
  **解决方案**：保持默认的 `off`。

---

### **如何配置？**
在 Kong 的配置文件中（如 `kong.conf` 或通过环境变量）设置：  
```bash
# 开启下划线支持
underscores_in_headers = on
```
或通过环境变量：  
```bash
KONG_UNDERSCORES_IN_HEADERS=on
```

---

### **注意事项**
- 如果设置为 `on`，需确保后端服务能正确处理带下划线的头字段。
- 某些插件或中间件可能对头名称有额外限制（例如 Prometheus 插件要求使用连字符 `-`）。

希望这能帮你理清这个参数的作用！如果有具体使用场景，可以进一步讨论。


要确认 Kong 是否启用了 `underscores_in_headers` 参数，可以通过以下几种方法检查：

---

### **方法 1：直接查看 Kong 配置文件**
Kong 的配置通常保存在 `kong.conf` 或 `kong.yml` 中。  
1. 找到你的 Kong 配置文件路径（默认位置可能是 `/etc/kong/kong.conf`）。  
2. 查看文件中是否有以下配置项：  
   ```bash
   # 如果显式设置为 on 或 off
   underscores_in_headers = on
   ```
   - 如果文件中没有这一行，表示使用默认值 `off`。

---

### **方法 2：通过环境变量检查**
如果通过环境变量配置 Kong，可以检查以下变量：  
```bash
# 查看当前环境变量
env | grep KONG_UNDERSCORES_IN_HEADERS

# 输出示例（若设置过）：
KONG_UNDERSCORES_IN_HEADERS=on
```
- 如果无输出，表示未设置，使用默认值 `off`。

---

### **方法 3：通过 Admin API 查询**
Kong 的 Admin API（默认端口 `8001`）可以查询当前运行配置：  
1. 调用 Admin API 的 `/` 根端点：  
   ```bash
   curl -s http://localhost:8001
   ```
2. 在返回的 JSON 结果中搜索 `underscores_in_headers`：  
   ```json
   {
     "configuration": {
       "underscores_in_headers": true,
       ...
     }
   }
   ```
   - `true` 表示 `on`，`false` 表示 `off`。

---

### **方法 4：检查 Nginx 生成的配置文件**
Kong 基于 Nginx，最终配置会生成到 Nginx 的配置文件中。  
1. 找到生成的 Nginx 配置文件（默认路径可能是 `/usr/local/kong/nginx.conf`）。  
2. 搜索 `underscores_in_headers`：  
   ```nginx
   http {
       underscores_in_headers on;
       ...
   }
   ```
   - 如果存在 `on` 或 `off`，即为当前配置。

---

### **方法 5：通过请求测试**
直接发送一个带下划线的请求头，观察是否被 Kong 转发到上游服务：  
1. 向 Kong 代理端口（如 `8000`）发送请求：  
   ```bash
   curl -H "X_Test_Header: hello" http://localhost:8000/your-route
   ```
2. 检查上游服务是否收到 `X_Test_Header`：  
   - 如果收到，表示 `underscores_in_headers` 为 `on`。
   - 如果未收到，表示 `off`（默认值）。

---

### **总结**
| 方法       | 适用场景                          | 关键命令/操作                          |
|------------|---------------------------------|--------------------------------------|
| 配置文件    | 直接访问服务器且有配置文件权限     | `grep underscores_in_headers kong.conf` |
| 环境变量    | 容器化部署或环境变量配置           | `env \| grep KONG_UNDERSCORES_IN_HEADERS` |
| Admin API   | 远程查询运行中的 Kong 实例        | `curl http://localhost:8001`         |
| 测试请求    | 快速验证实际行为                  | 发送带 `X_Custom_Header` 的请求       |

---

### **注意事项**
- 如果修改了配置，需重启 Kong 服务生效：  
  ```bash
  kong restart
  ```
- 如果通过 Kubernetes 或 Docker 部署，需检查部署描述文件（如 Helm Values 或 Docker 环境变量）。