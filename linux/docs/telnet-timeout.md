# Telnet 空闲连接超时测试指南

## 1. 测试目的

使用 telnet 测试 TCP 空闲连接的超时行为，验证不同组件的超时配置。
所以说，我理解上面的这个测试主要模拟的是一个空闲超时（TCP idle timeout），并不是我真正的 HTTP 请求超时时间。

---

## 2. 测试原理

### 2.1 Telnet 测试的本质

**Telnet 空闲连接测试：**
```
客户端 (telnet) → 目标服务器
    ↓
    建立 TCP 连接
    ↓
    不发送任何数据（空闲）
    ↓
    等待连接被关闭
    ↓
    记录超时时间
```

**关键点：**
- Telnet 建立 TCP 连接后不发送应用层数据
- 模拟"连接空闲"场景
- 触发中间组件的空闲超时机制

---

### 2.2 测试的有效性和局限性

#### ✅ 有效性

**可以测试的超时：**
1. **TCP 空闲超时** - 中间代理/负载均衡器的空闲连接超时
2. **TCP Keepalive** - 系统级 TCP 保活机制
3. **防火墙超时** - 防火墙的连接跟踪超时

**适用场景：**
- 测试 L4 代理的 `proxy_timeout`
- 测试 GCP Load Balancer 的空闲超时
- 测试 GKE Gateway 的空闲超时
- 测试防火墙规则

---

#### ❌ 局限性

**无法测试的超时：**
1. **HTTP 请求超时** - 需要实际的 HTTP 请求
2. **应用层超时** - 需要应用层协议交互
3. **读/写超时** - 需要数据传输

**不适用场景：**
- 测试 L7 代理的 `proxy_read_timeout`（需要 HTTP 请求）
- 测试应用层的请求处理超时（需要完整请求）
- 测试数据传输超时（需要实际数据流）

---

### 2.3 Telnet vs 实际 HTTP 请求

| 测试方法 | 测试内容 | 适用场景 | 局限性 |
|----------|----------|----------|--------|
| **Telnet 空闲** | TCP 空闲超时 | L4 代理、LB 空闲超时 | 不测试应用层 |
| **HTTP 请求** | 完整请求链路 | 端到端超时验证 | 无法隔离 TCP 层 |
| **curl --max-time** | 总请求超时 | 客户端超时验证 | 包含所有环节 |
| **长时间 API** | 实际业务超时 | 生产环境验证 | 依赖后端处理 |

---

## 3. 实际测试结果分析

### 3.1 测试场景

**测试环境：**
```bash
# 测试 1：GKE Gateway
time telnet 192.168.65.65 443
# 结果：15 秒后断开

# 测试 2：GCP Load Balancer
time telnet 192.168.65.87 443
# 结果：60 秒后断开
```

---

### 3.2 结果分析

#### 场景 1：GKE Gateway (15 秒超时)

**架构：**
```
telnet → GKE Gateway (192.168.65.65:443)
         ↓
         GKE Gateway 检测到空闲连接
         ↓
         15 秒后关闭连接
```

**可能的原因：**

1. **GKE Gateway 默认空闲超时**
   - GKE Gateway 基于 Envoy 代理
   - Envoy 默认空闲超时：15 秒
   - 配置位置：Gateway 或 HTTPRoute

2. **GCP Cloud Load Balancer 配置**
   - GKE Gateway 后端使用 GCP LB
   - 可能配置了较短的空闲超时

3. **TCP Keepalive 探测**
   - 15 秒可能是 TCP Keepalive 探测间隔
   - 连接未响应探测而被关闭

---

#### 场景 2：GCP Load Balancer (60 秒超时)

**架构：**
```
telnet → GCP Load Balancer (192.168.65.87:443)
         ↓
         GCP LB 检测到空闲连接
         ↓
         60 秒后关闭连接
```

**可能的原因：**

1. **GCP Load Balancer 默认超时**
   - 内部 TCP/UDP Load Balancer：默认无超时
   - 外部 TCP Proxy Load Balancer：默认 600 秒
   - 可能配置了 60 秒超时

2. **Backend Service 配置**
   - `timeoutSec: 60` 在 Backend Service 中配置
   - 虽然文档说 TCP LB 忽略此值，但可能影响空闲超时

3. **防火墙或 NAT 超时**
   - GCP 防火墙默认连接跟踪超时：60 秒（空闲）
   - Cloud NAT 默认超时：60 秒

---

### 3.3 超时来源判断

#### 判断流程图

```
Telnet 连接超时
    ↓
    检查超时时间
    ↓
    ├─ 15 秒 → 可能是 GKE Gateway/Envoy
    ├─ 30 秒 → 可能是防火墙规则
    ├─ 60 秒 → 可能是 GCP LB 或防火墙
    ├─ 300 秒 → 可能是自定义配置
    └─ 600 秒 → 可能是默认配置
```

---

## 4. 深度验证方法

### 4.1 验证 GKE Gateway 超时配置

```bash
# 1. 检查 Gateway 配置
kubectl get gateway -n gateway-namespace my-gateway -o yaml

# 2. 检查 HTTPRoute 配置
kubectl get httproute -n gateway-namespace api-route -o yaml | \
    grep -A 10 "timeouts"

# 3. 检查 GCPBackendPolicy
kubectl get gcpbackendpolicy -n gateway-namespace -o yaml | \
    grep -E "timeoutSec|idleTimeoutSec"

# 4. 查看 Envoy 配置（如果可以访问）
kubectl exec -n gateway-namespace <gateway-pod> -- \
    curl -s localhost:15000/config_dump | \
    jq '.configs[] | select(.["@type"] | contains("Cluster")) | .dynamic_active_clusters[].cluster.common_http_protocol_options.idle_timeout'
```

---

### 4.2 验证 GCP Load Balancer 超时配置

```bash
# 1. 列出所有 Backend Services
gcloud compute backend-services list

# 2. 查看具体的超时配置
gcloud compute backend-services describe <backend-service-name> \
    --global \
    --format="yaml(timeoutSec,connectionDraining.drainingTimeoutSec)"

# 3. 查看 Forwarding Rule
gcloud compute forwarding-rules describe <forwarding-rule-name> \
    --global \
    --format="yaml"

# 4. 检查防火墙规则
gcloud compute firewall-rules list --filter="name~<your-firewall>"
```

---

### 4.3 使用 tcpdump 分析断开原因

```bash
# 在测试主机上抓包
sudo tcpdump -i any -nn -s0 -w /tmp/telnet-test.pcap \
    'host 192.168.65.65 and port 443'

# 在另一个终端执行 telnet
time telnet 192.168.65.65 443

# 等待连接断开后，分析抓包
tcpdump -r /tmp/telnet-test.pcap -nn -A

# 查找关键信息：
# - FIN 包：正常关闭
# - RST 包：强制关闭（通常是超时）
# - 最后一个包的时间戳：确认超时时间
```

**分析示例：**

```
# 连接建立
14:00:00.000 IP 10.0.0.1.12345 > 192.168.65.65.443: Flags [S], seq 1
14:00:00.001 IP 192.168.65.65.443 > 10.0.0.1.12345: Flags [S.], seq 1, ack 2
14:00:00.001 IP 10.0.0.1.12345 > 192.168.65.65.443: Flags [.], ack 1

# 空闲期间（无数据包）
...

# 连接关闭（15 秒后）
14:00:15.000 IP 192.168.65.65.443 > 10.0.0.1.12345: Flags [F.], seq 1, ack 2
14:00:15.001 IP 10.0.0.1.12345 > 192.168.65.65.443: Flags [.], ack 2

# 结论：服务端主动发送 FIN，15 秒空闲超时
```

---

## 5. 完整测试脚本

### 5.1 自动化测试脚本

```bash
#!/bin/bash
# telnet-timeout-test.sh - 自动化 Telnet 超时测试

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测试目标
declare -A TARGETS=(
    ["GKE Gateway"]="192.168.65.65:443"
    ["GCP Load Balancer"]="192.168.65.87:443"
)

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# 测试单个目标
test_target() {
    local name="$1"
    local target="$2"
    local host="${target%:*}"
    local port="${target#*:}"
    
    log_info "测试: $name ($target)"
    
    # 检查连通性
    if ! nc -zv "$host" "$port" &>/dev/null; then
        log_error "无法连接到 $target"
        return 1
    fi
    
    log_info "连接成功，开始空闲超时测试..."
    
    # 使用 timeout 命令限制最大等待时间（10 分钟）
    local start_time=$(date +%s)
    
    # 使用 expect 自动化 telnet（如果可用）
    if command -v expect &>/dev/null; then
        expect <<EOF &>/dev/null
set timeout 600
spawn telnet $host $port
expect {
    "Connected" {
        send "\r"
        expect {
            "Connection closed" {
                exit 0
            }
            timeout {
                exit 1
            }
        }
    }
    timeout {
        exit 2
    }
}
EOF
        local exit_code=$?
    else
        # 使用 nc 替代（保持连接但不发送数据）
        timeout 600 nc "$host" "$port" </dev/null &>/dev/null
        local exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    
    if [[ $exit_code -eq 124 ]]; then
        log_warn "超时未断开（> 600 秒）"
    else
        log_info "连接在 ${elapsed} 秒后断开"
        
        # 分析超时时间
        if [[ $elapsed -le 20 ]]; then
            echo -e "${YELLOW}  → 可能是 GKE Gateway/Envoy 默认超时 (15s)${NC}"
        elif [[ $elapsed -le 40 ]]; then
            echo -e "${YELLOW}  → 可能是防火墙规则超时 (30s)${NC}"
        elif [[ $elapsed -le 70 ]]; then
            echo -e "${YELLOW}  → 可能是 GCP LB 或防火墙超时 (60s)${NC}"
        elif [[ $elapsed -le 320 ]]; then
            echo -e "${GREEN}  → 可能是自定义配置 (~300s)${NC}"
        else
            echo -e "${GREEN}  → 可能是默认配置 (600s)${NC}"
        fi
    fi
    
    echo ""
}

# 主函数
main() {
    log_info "开始 Telnet 空闲超时测试"
    echo ""
    
    for name in "${!TARGETS[@]}"; do
        test_target "$name" "${TARGETS[$name]}"
    done
    
    log_info "测试完成"
}

main "$@"
```

**使用方法：**

```bash
chmod +x telnet-timeout-test.sh
./telnet-timeout-test.sh
```

---

### 5.2 手动测试步骤

```bash
# 1. 测试 GKE Gateway
echo "测试 GKE Gateway..."
START=$(date +%s)
telnet 192.168.65.65 443
# 等待连接断开（不要输入任何内容）
END=$(date +%s)
echo "超时时间: $((END - START)) 秒"

# 2. 测试 GCP Load Balancer
echo "测试 GCP Load Balancer..."
START=$(date +%s)
telnet 192.168.65.87 443
# 等待连接断开
END=$(date +%s)
echo "超时时间: $((END - START)) 秒"

# 3. 对比结果
echo "GKE Gateway: 15 秒"
echo "GCP LB: 60 秒"
echo "差异: 45 秒"
```

---

## 6. 超时差异的影响分析

### 6.1 对实际业务的影响

#### 场景 1：短连接 API（< 5 秒）

**影响：** ✅ 无影响
- 请求在 5 秒内完成
- 远小于 15 秒和 60 秒超时
- 不会触发空闲超时

---

#### 场景 2：长连接 API（35 秒）

**影响：** ⚠️ 可能有影响

**如果经过 GKE Gateway (15 秒超时)：**
```
T+0s   : 请求开始
T+0.5s : 请求发送完成
T+0.5s - T+35s : 等待响应（连接空闲）
         ↓
         问题：如果 15 秒内没有任何数据传输
         ↓
         GKE Gateway 可能关闭连接
         ↓
         但实际上：
         - HTTP 请求已发送（有数据）
         - 不是完全空闲
         - 可能不会触发 15 秒超时
```

**关键点：**
- Telnet 测试是"完全空闲"（无任何数据）
- 实际 HTTP 请求有数据传输（请求头、请求体）
- 15 秒超时可能不会影响实际请求

---

#### 场景 3：WebSocket 长连接

**影响：** ❌ 有影响

**如果经过 GKE Gateway (15 秒超时)：**
```
WebSocket 连接建立
    ↓
    长时间无数据传输（> 15 秒）
    ↓
    GKE Gateway 关闭连接
    ↓
    WebSocket 断开
```

**解决方案：**
- 配置 WebSocket Ping/Pong（心跳）
- 增加 GKE Gateway 空闲超时
- 使用应用层心跳

---

### 6.2 配置建议

#### 针对 GKE Gateway (15 秒超时)

**如果需要支持长时间空闲连接：**

```yaml
# 方案 1：通过 GCPBackendPolicy 配置
apiVersion: networking.gke.io/v1
kind: GCPBackendPolicy
metadata:
  name: kong-backend-policy
  namespace: gateway-namespace
spec:
  default:
    timeoutSec: 310  # 请求超时
    # 注意：GCPBackendPolicy 可能不支持 idleTimeout
  targetRef:
    group: ""
    kind: Service
    name: kong-proxy
```

**方案 2：通过 HTTPRoute 配置（如果支持）**

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: api-route
spec:
  rules:
    - backendRefs:
        - name: kong-proxy
          port: 8000
      timeouts:
        request: 310s
        # 注意：标准 Gateway API 可能不支持 idle timeout
```

**方案 3：应用层心跳（推荐）**

```python
# 在应用中实现心跳机制
import time
import threading

def send_keepalive(connection):
    while True:
        time.sleep(10)  # 每 10 秒发送一次
        connection.send(b'\x00')  # 发送空字节保持连接

# 在建立连接后启动心跳线程
threading.Thread(target=send_keepalive, args=(conn,), daemon=True).start()
```

---

#### 针对 GCP Load Balancer (60 秒超时)

**如果需要更长的空闲超时：**

```bash
# 检查当前配置
gcloud compute backend-services describe <backend-service-name> \
    --global \
    --format="value(timeoutSec)"

# 注意：对于 TCP Load Balancer，timeoutSec 可能不影响空闲超时
# 60 秒超时可能来自防火墙或 NAT 配置

# 检查防火墙规则
gcloud compute firewall-rules list --format="table(name,allowed,sourceRanges)"

# 如果是 Cloud NAT，检查 NAT 配置
gcloud compute routers nats describe <nat-name> \
    --router=<router-name> \
    --region=<region>
```

---

## 7. 最佳实践建议

### 7.1 测试建议

**使用 Telnet 测试时：**
1. ✅ 用于测试 TCP 空闲超时
2. ✅ 用于验证防火墙规则
3. ✅ 用于对比不同组件的超时
4. ❌ 不要用于测试 HTTP 请求超时
5. ❌ 不要用于测试应用层超时

**推荐的测试组合：**
```bash
# 1. Telnet 测试（TCP 空闲超时）
time telnet <target> 443

# 2. curl 测试（HTTP 请求超时）
time curl --max-time 320 -X POST <url>

# 3. 实际业务测试（端到端验证）
# 使用实际的 API 请求测试
```

---

### 7.2 配置建议

**超时配置优先级：**

1. **应用层超时** (最高优先级)
   - Runtime 应用配置：300s
   - 控制实际业务逻辑超时

2. **L7 代理超时**
   - Kong read_timeout: 300s
   - A 组件 proxy_read_timeout: 300s
   - 控制 HTTP 请求超时

3. **L4 代理超时**
   - B 组件 proxy_timeout: 310s
   - 控制 TCP 数据传输超时

4. **负载均衡器超时**
   - GKE Gateway: 310s (通过 GCPBackendPolicy)
   - GCP LB: 310s (通过 Backend Service)
   - 控制基础设施层超时

5. **TCP 空闲超时** (最低优先级)
   - 通常不需要特别配置
   - 依赖默认值即可
   - 如需长连接，使用应用层心跳

---

### 7.3 监控建议

```bash
# 1. 监控连接断开原因
kubectl logs -n gateway-namespace -l app=gateway | \
    grep -E "connection closed|timeout|reset"

# 2. 监控连接持续时间
# 在 Prometheus 中查询
histogram_quantile(0.95, 
  rate(connection_duration_seconds_bucket[5m])
)

# 3. 告警配置
# 如果连接频繁在 15 秒或 60 秒断开，可能需要调整配置
```

---

## 8. 总结

### 8.1 关键发现

**Telnet 测试结果：**
- GKE Gateway: 15 秒空闲超时
- GCP Load Balancer: 60 秒空闲超时

**测试有效性：**
- ✅ 可以测试 TCP 空闲超时
- ✅ 可以对比不同组件的超时行为
- ❌ 不能测试 HTTP 请求超时
- ❌ 不能测试应用层超时

**对实际业务的影响：**
- 短连接 API (< 5s): 无影响
- 长连接 API (35s): 可能无影响（有数据传输）
- WebSocket: 可能有影响（需要心跳）

---

### 8.2 推荐配置

**完整超时配置链路：**

| 组件 | 配置项 | 推荐值 | 说明 |
|------|--------|--------|------|
| 客户端 | timeout | 310s | 总请求超时 |
| A (L7 Nginx) | proxy_read_timeout | 300s | HTTP 读取超时 |
| B (L4 Nginx) | proxy_timeout | 310s | TCP 传输超时 |
| GKE Gateway | timeoutSec | 310 | 请求超时 |
| GKE Gateway | idle timeout | 默认 15s | TCP 空闲超时 |
| GCP LB | timeoutSec | 310 | 请求超时 |
| GCP LB | idle timeout | 默认 60s | TCP 空闲超时 |
| Kong | read_timeout | 300000ms | HTTP 读取超时 |
| Runtime | app timeout | 300s | 应用层超时 |

---

### 8.3 验证清单

- [ ] 使用 telnet 测试 TCP 空闲超时
- [ ] 使用 curl 测试 HTTP 请求超时
- [ ] 使用实际 API 测试端到端超时
- [ ] 检查 GKE Gateway 配置
- [ ] 检查 GCP Load Balancer 配置
- [ ] 验证所有组件的超时配置一致性
- [ ] 监控连接断开原因和频率

---

**关键要点：**
- Telnet 测试的是 TCP 空闲超时，不是 HTTP 请求超时
- 15 秒和 60 秒的差异来自不同组件的空闲超时配置
- 对于有数据传输的 HTTP 请求，空闲超时通常不会触发
- 建议使用多种测试方法组合验证超时配置

---

**文档版本：** v1.0  
**最后更新：** 2026-02-25  
**相关文档：** debug-timeout-flow.md

