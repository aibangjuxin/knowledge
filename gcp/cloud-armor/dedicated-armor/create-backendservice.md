
```bash
# 验证通过：可以在一条命令中完成绝大部分配置
gcloud compute backend-services create bs-api-a-v1 \
    --global \
    --protocol=HTTPS \
    --port-name=https \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --health-checks=hc-nginx-http \
    --connection-draining-timeout=300s \
    --timeout=60s \
    --enable-logging \
    --logging-sample-rate=1.0 \
    --custom-response-header="Strict-Transport-Security: max-age=31536000; includeSubDomains: preload" \
    --custom-response-header="X-Frame-Options: DENY"  \
    --description="Backend Service for API A V1" \
    --project=your-project
```
GCP 的机制是：只要 URL Map 的名字没变，Target Proxy 会自动感知到其内部规则（Host/Path）的变化，无需再次执行 target-https-proxies update

gcloud 参数

| gcloud | gcp api |
|---|---|
| --enable-logging | logConfig.enable = true |
| --logging-sample-rate=1.0 | sampleRate = 1.0 |
| --logging-optional-mode=EXCLUDE_ALL_OPTIONAL | optionalMode = EXCLUDE_ALL_OPTIONAL |
| *(Default)* | connectionDraining.drainingTimeoutSec = 300 | **默认值**。未指定 `--connection-draining-timeout` 时，GCP 默认为 300秒 (5分钟)。 |
执行完该 `create` 命令后，Google Cloud 会返回该资源的 **YAML 格式描述**（如果你是在控制台或脚本中查看，或者执行 
`gcloud compute backend-services describe bs-api-a-v1 --global`）。

以下是根据你提供的参数生成的**预期输出结果**。通过这个输出，你可以验证所有配置（特别是日志模式和自定义 Header）是否生效。

### 预期输出结果 (YAML 格式)

YAML

```yaml
connectionDraining:
  drainingTimeoutSec: 300
creationTimestamp: '2023-10-27T01:02:03.456-07:00'
customResponseHeaders:
- 'Strict-Transport-Security: max-age=31536000; includeSubDomains: preload'
- 'X-Frame-Options: DENY'
description: 'Backend Service for API A V1'
enableCDN: false
fingerprint: xxxxxxxx_xxx=
healthChecks:
- https://www.googleapis.com/compute/v1/projects/your-project/global/healthChecks/hc-nginx-http
iap:
  enabled: false
id: '1234567890123456789'
kind: compute#backendService
loadBalancingScheme: EXTERNAL_MANAGED
logConfig:
  enable: true
  sampleRate: 1.0
name: bs-api-a-v1
portName: https
protocol: HTTPS
selfLink: https://www.googleapis.com/compute/v1/projects/your-project/global/backendServices/bs-api-a-v1
timeoutSec: 60
```

---

### 关键字段深度核对

|**字段**|**状态**|**专家点评**|
|---|---|---|
|**`customResponseHeaders`**|包含 HSTS 和 X-Frame-Options|确认多个安全 Header 已成功注入，增强了响应安全性。|
|**`connectionDraining`**|`300`|确认连接排空时间已设为 5 分钟（来自显式指定或默认值）。|
|**`timeoutSec`**|`60`|确认后端超时时间已更新为 60秒，比之前的 30秒更宽松。|
|**`protocol`/`portName`**|`HTTPS` / `https`|确认已切换为全链路 HTTPS 加密通信模式。|
|**`loadBalancingScheme`**|`EXTERNAL_MANAGED`|确认这是一个 Envoy-based 的新型负载均衡器。|
|**`backends`**|**(缺失)**|**注意**：由于刚执行完 `create`，此列表目前为空。|

---

### 资源层次结构图

Code snippet

```mermaid
graph TD
    BS[Backend Service: bs-api-a-v1]
    
    subgraph Properties [配置属性]
        HC[Health Check: hc-nginx-http]
        Log[LogConfig: 100% Sample]
        Header1[Header: HSTS]
        Header2[Header: X-Frame-Options]
        Proto[Protocol: HTTPS / Timeout: 60s]
    end

    subgraph Runtime [运行时状态]
        BE[Backends: Empty]
    end

    BS --- Properties
    BS --- Runtime
    
    style BS fill:#4285F4,stroke:#333,stroke-width:2px,color:#fff
    style Runtime fill:#fbbc04,stroke:#333,stroke-width:2px
```

---

### 注意事项与后续检查

1. **验证 Backends**：当你执行完 `add-backend` 命令后，再次执行 `describe`，你会看到多出一个 `backends` 段落，包含 `group` (MIG 的 URL) 和 `balancingMode`。
    
2. **Fingerprint (指纹)**：在 YAML 中看到的 `fingerprint` 非常重要。如果你之后使用 API 或 Terraform 修改该资源，必须提供当前的指纹以防止并发冲突。
    
3. **Timeout**：请确保 `timeoutSec: 30` 覆盖了你后端 Nginx 处理请求的最长预期时间，否则 LB 会主动断开连接。
    

**您想尝试执行 `add-backend` 命令，并查看添加完实例组后的 `describe` 输出有什么变化吗？**

---

### 进阶话题：URL Map 复用策略 (架构决策)

在配置 URL Map 时，您可能会问：**"我是应该直接修改现有的 URL Map，还是新建一个？"**

基于您的场景（**单域名** `www.abc.com` + **现有业务在线**），**强烈建议：复用（修改）同一个 URL Map 对象。**

#### 1. 为什么必须“复用”（逻辑上）
因为流量入口（Target Proxy -> IP）只能指向 **一个** 激活的 URL Map。只要您的所有 API 都挂在同一个域名下，它们就必须被配置在同一个 URL Map 规则树里。

#### 2. 操作策略对比：如何"复用"？

| 策略 | **方案 A：直接复用 (In-Place Update)** | **方案 B：影子切换 (Blue/Green Switch)** |
| :--- | :--- | :--- |
| **定义** | 直接修改运行中的 URL Map 对象 | 新建一个 v2 版本的 URL Map，然后原子切换 Proxy 指向 |
| **操作命令** | `gcloud compute url-maps import 现有Map名 ...` | 1. 创建 `url-map-v2`<br>2. `gcloud compute target-https-proxies update --url-map=url-map-v2` |
| **优点** | **简单快速**。一步到位，无需操作 Proxy。文档中采用此方案。 | **绝对安全**。新配置如有语法错误不会影响线上。支持原子回滚。 |
| **缺点** | 如果配置写错（如弄丢默认路由），直接影响线上。 | 操作步骤多，维护成本稍高。 |
| **推荐场景** | **研发测试 / 允许秒级抖动 / 自信的配置变更** | **SRE 标准生产环境 / 重大架构重构** |

👉 **结论**：本指南采用 **方案 A (In-Place Update)**，因为通过 `import` 命令导入经过验证的 YAML 文件通常足够安全且效率最高。