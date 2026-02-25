# 超时流程验证与调试指南

## 架构概览

```
Client → A (L7 Nginx) → B (L4 Nginx) → C (Kong DP) → D (GKE Runtime/API Endpoint)
         [300s timeout]   [300s timeout]  [300s timeout]  [应用层超时]
```

**目标：** 验证整个请求链路支持 300 秒（5 分钟）的超时设置。

---

## 1. 快速验证方案

### 方案 1：使用 curl 模拟慢速响应（推荐）

**原理：** 通过 curl 的 `--max-time` 参数验证整个链路的超时行为。

```bash
# 基础测试：验证 300 秒超时是否生效
time curl -v \
  --max-time 310 \
  -H "Host: www.aibang.com" \
  -X GET \
  "https://your-entry-point.com/abc/v1/your-endpoint" \
  -o /dev/null

# 预期结果：
# - 如果后端在 300 秒内响应：请求成功
# - 如果后端超过 300 秒：应该在 ~300 秒时收到超时错误
```

**参数说明：**
- `--max-time 310`：客户端最大等待时间（略大于服务端超时）
- `-v`：详细输出，显示连接和传输过程
- `time`：测量实际执行时间

---

### 方案 2：使用后端模拟延迟端点

**步骤 1：在 D 组件（GKE Runtime）创建测试端点**

如果你的 API 支持，可以创建一个模拟延迟的测试端点：

```python
# Python Flask 示例
from flask import Flask
import time

app = Flask(__name__)

@app.route('/test/delay/<int:seconds>')
def delay_response(seconds):
    """模拟延迟响应"""
    time.sleep(seconds)
    return {
        "status": "success",
        "delayed_seconds": seconds,
        "message": f"Response after {seconds} seconds"
    }

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

**步骤 2：通过完整链路测试**

```bash
# 测试 30 秒延迟（应该成功）
time curl -v \
  -H "Host: www.aibang.com" \
  "https://your-entry-point.com/abc/v1/test/delay/30"

# 测试 180 秒延迟（应该成功）
time curl -v \
  -H "Host: www.aibang.com" \
  "https://your-entry-point.com/abc/v1/test/delay/180"

# 测试 310 秒延迟（应该超时）
time curl -v \
  -H "Host: www.aibang.com" \
  "https://your-entry-point.com/abc/v1/test/delay/310"
```

---

### 方案 3：使用 httpbin.org 的延迟端点（外部测试）

如果可以临时修改 Kong 路由到外部服务：

```bash
# httpbin.org 提供延迟测试端点
# /delay/{n} - 延迟 n 秒后响应（最大 10 秒）

# 测试 10 秒延迟
time curl -v \
  -H "Host: www.aibang.com" \
  "https://your-entry-point.com/abc/v1/delay/10"
```

---

## 2. 分段验证方案

逐个组件验证超时配置，定位问题点。

### 2.1 验证 A 组件（L7 Nginx）

**直接访问 A 组件：**

```bash
# 假设 A 组件的 IP 是 192.168.1.100
time curl -v \
  --max-time 310 \
  -H "Host: www.aibang.com" \
  -X GET \
  "https://192.168.1.100/abc/v1/your-endpoint"

# 检查 Nginx 日志
ssh user@192.168.1.100
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

**验证 Nginx 配置：**

```bash
# 登录 A 组件
ssh user@192.168.1.100

# 检查配置
nginx -T | grep -A 10 "location /abc/v1/"

# 确认超时设置
nginx -T | grep -E "proxy_read_timeout|proxy_connect_timeout|proxy_send_timeout"

# 预期输出：
# proxy_read_timeout 300s;
# proxy_connect_timeout 300s;
# proxy_send_timeout 300s;
```

---

### 2.2 验证 B 组件（L4 Nginx）

**检查 B 组件配置：**

```bash
# 登录 B 组件
ssh user@192.168.0.188

# 检查 Nginx Stream 配置
cat /etc/nginx/nginx.conf | grep -A 10 "listen 8080"

# 确认超时设置
cat /etc/nginx/nginx.conf | grep "proxy_timeout"

# 预期输出：
# proxy_timeout 300s;
```

**验证 TCP 连接：**

```bash
# 从 A 组件测试到 B 组件的连接
telnet 192.168.0.188 8080

# 或使用 nc
nc -zv 192.168.0.188 8080
```

---

### 2.3 验证 C 组件（Kong DP）

**检查 Kong 配置：**

```bash
# 如果 Kong 使用 Helm 部署
kubectl get configmap -n kong-namespace kong-config -o yaml

# 检查 Kong 的超时设置
kubectl exec -it -n kong-namespace <kong-pod-name> -- kong config db_export

# 或通过 Admin API 检查
curl -s http://kong-admin:8001/services/<service-name> | jq '.read_timeout, .write_timeout, .connect_timeout'
```

**验证 Kong 路由：**

```bash
# 列出所有路由
curl -s http://kong-admin:8001/routes | jq '.data[] | {name, paths, service}'

# 检查特定路由的超时设置
curl -s http://kong-admin:8001/routes/<route-id> | jq
```

**Kong 超时配置示例：**

```yaml
# Kong Service 配置
apiVersion: configuration.konghq.com/v1
kind: KongService
metadata:
  name: backend-service
spec:
  protocol: https
  host: backend.example.com
  port: 443
  read_timeout: 300000    # 毫秒
  write_timeout: 300000   # 毫秒
  connect_timeout: 60000  # 毫秒
```

---

### 2.4 验证 D 组件（GKE Runtime）

**检查 Kubernetes Service 和 Pod：**

```bash
# 查看 Service 配置
kubectl get svc -n your-namespace your-service -o yaml

# 查看 Pod 日志
kubectl logs -n your-namespace -l app=your-app --tail=100 -f

# 检查 Pod 的资源限制
kubectl describe pod -n your-namespace <pod-name> | grep -A 5 "Limits\|Requests"
```

**验证应用层超时：**

根据你的应用框架，检查超时配置：

```bash
# 示例：Java Spring Boot
# application.properties 或 application.yml
server.connection-timeout=300000
spring.mvc.async.request-timeout=300000

# 示例：Node.js Express
# server.js
server.timeout = 300000; // 毫秒

# 示例：Python Flask/Gunicorn
# gunicorn.conf.py
timeout = 300
```

---

## 3. 端到端验证脚本

### 3.1 自动化测试脚本

```bash
#!/bin/bash
# timeout-test.sh - 超时流程自动化测试脚本

set -euo pipefail

# 配置
ENTRY_POINT="https://your-entry-point.com"
HOST_HEADER="www.aibang.com"
TEST_PATH="/abc/v1/test/delay"
TIMEOUT_THRESHOLD=300

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# 测试函数
test_timeout() {
    local delay=$1
    local description=$2
    
    log_info "测试: $description (延迟 ${delay}s)"
    
    local start_time=$(date +%s)
    local http_code
    local curl_exit_code
    
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time $((delay + 10)) \
        -H "Host: $HOST_HEADER" \
        "${ENTRY_POINT}${TEST_PATH}/${delay}" \
        2>/dev/null) || curl_exit_code=$?
    
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    
    if [[ ${curl_exit_code:-0} -eq 0 && "$http_code" == "200" ]]; then
        log_info "✓ 成功 - HTTP $http_code, 耗时 ${elapsed}s"
        return 0
    elif [[ ${curl_exit_code:-0} -eq 28 ]]; then
        log_warn "✗ 超时 - 耗时 ${elapsed}s (curl 超时)"
        return 1
    else
        log_error "✗ 失败 - HTTP $http_code, 耗时 ${elapsed}s, 退出码 ${curl_exit_code:-0}"
        return 2
    fi
}

# 主测试流程
main() {
    log_info "开始超时流程验证测试"
    log_info "入口点: $ENTRY_POINT"
    log_info "超时阈值: ${TIMEOUT_THRESHOLD}s"
    echo ""
    
    # 测试 1: 短延迟（应该成功）
    test_timeout 10 "短延迟测试"
    echo ""
    
    # 测试 2: 中等延迟（应该成功）
    test_timeout 60 "中等延迟测试"
    echo ""
    
    # 测试 3: 接近阈值（应该成功）
    test_timeout 180 "接近阈值测试"
    echo ""
    
    # 测试 4: 略低于阈值（应该成功）
    test_timeout 290 "略低于阈值测试"
    echo ""
    
    # 测试 5: 超过阈值（应该超时）
    log_warn "注意: 下一个测试预期会超时"
    test_timeout 310 "超过阈值测试（预期超时）"
    echo ""
    
    log_info "测试完成"
}

main "$@"
```

**使用方法：**

```bash
# 添加执行权限
chmod +x timeout-test.sh

# 运行测试
./timeout-test.sh

# 保存测试结果
./timeout-test.sh | tee timeout-test-results.log
```

---

### 3.2 使用 Apache Bench (ab) 进行压力测试

```bash
# 安装 ab
sudo apt-get install apache2-utils  # Ubuntu/Debian
sudo yum install httpd-tools         # CentOS/RHEL

# 并发测试（10 个并发，总共 100 个请求）
ab -n 100 -c 10 \
   -H "Host: www.aibang.com" \
   -s 310 \
   "https://your-entry-point.com/abc/v1/your-endpoint"

# 参数说明：
# -n 100: 总请求数
# -c 10: 并发数
# -s 310: 超时时间（秒）
```

---

### 3.3 使用 wrk 进行高级压力测试

```bash
# 安装 wrk
git clone https://github.com/wg/wrk.git
cd wrk
make
sudo cp wrk /usr/local/bin/

# 运行测试（持续 30 秒，10 个线程，100 个连接）
wrk -t10 -c100 -d30s \
    -H "Host: www.aibang.com" \
    --timeout 310s \
    "https://your-entry-point.com/abc/v1/your-endpoint"
```

---

## 4. 监控和日志分析

### 4.1 实时监控请求流

**在 A 组件（L7 Nginx）：**

```bash
# 实时查看访问日志
tail -f /var/log/nginx/access.log | grep "/abc/v1/"

# 查看错误日志（关注超时错误）
tail -f /var/log/nginx/error.log | grep -E "timeout|upstream"

# 统计超时错误
grep "upstream timed out" /var/log/nginx/error.log | wc -l
```

**在 B 组件（L4 Nginx）：**

```bash
# 查看 Stream 日志
tail -f /opt/access-in.log

# 检查连接状态
netstat -an | grep 8080 | grep ESTABLISHED | wc -l
```

**在 C 组件（Kong DP）：**

```bash
# 查看 Kong 日志
kubectl logs -n kong-namespace -l app=kong -f

# 查看特定 Pod 的日志
kubectl logs -n kong-namespace <kong-pod-name> -f

# 过滤超时相关日志
kubectl logs -n kong-namespace -l app=kong --tail=1000 | grep -i timeout
```

**在 D 组件（GKE Runtime）：**

```bash
# 查看应用日志
kubectl logs -n your-namespace -l app=your-app -f

# 查看最近的错误
kubectl logs -n your-namespace -l app=your-app --tail=100 | grep -i error

# 查看 Pod 事件
kubectl get events -n your-namespace --sort-by='.lastTimestamp'
```

---

### 4.2 使用 tcpdump 抓包分析

```bash
# 在 A 组件抓包
sudo tcpdump -i any -nn -s0 -w /tmp/a-component.pcap \
    'host 192.168.0.188 and port 8080'

# 在 B 组件抓包
sudo tcpdump -i any -nn -s0 -w /tmp/b-component.pcap \
    'host 10.0.0.5 and port 443'

# 分析抓包文件
tcpdump -r /tmp/a-component.pcap -nn -A | less
```

---

### 4.3 使用 strace 跟踪系统调用

```bash
# 跟踪 Nginx worker 进程
ps aux | grep nginx | grep worker
sudo strace -p <nginx-worker-pid> -f -e trace=network -o /tmp/nginx-strace.log

# 分析 strace 输出
grep -E "connect|sendto|recvfrom|close" /tmp/nginx-strace.log
```

---

## 5. 常见问题排查

### 问题 1：请求在 30 秒时超时

**可能原因：**
- GCP Load Balancer 的默认超时（虽然文档说会忽略，但需要验证）
- 某个组件的超时配置未生效

**排查步骤：**

```bash
# 1. 检查 GCP Backend Service 配置
gcloud compute backend-services describe <backend-service-name> \
    --global \
    --format="value(timeoutSec)"

# 2. 验证 Nginx 配置是否重载
nginx -t && nginx -s reload

# 3. 检查 Nginx 进程是否使用了新配置
ps aux | grep nginx
sudo kill -HUP <nginx-master-pid>
```

---

### 问题 2：请求在 60 秒时超时

**可能原因：**
- Kong 的默认超时（60 秒）
- Kubernetes Service 的默认超时

**排查步骤：**

```bash
# 1. 检查 Kong Service 配置
curl -s http://kong-admin:8001/services/<service-name> | jq

# 2. 更新 Kong Service 超时
curl -X PATCH http://kong-admin:8001/services/<service-name> \
    -d "read_timeout=300000" \
    -d "write_timeout=300000" \
    -d "connect_timeout=60000"

# 3. 验证更新
curl -s http://kong-admin:8001/services/<service-name> | jq '.read_timeout'
```

---

### 问题 3：请求在 300 秒前随机超时

**可能原因：**
- 网络不稳定
- 后端应用崩溃或重启
- 资源不足（CPU/内存）

**排查步骤：**

```bash
# 1. 检查 Pod 重启次数
kubectl get pods -n your-namespace -o wide

# 2. 查看 Pod 资源使用
kubectl top pods -n your-namespace

# 3. 检查节点资源
kubectl top nodes

# 4. 查看 Pod 事件
kubectl describe pod -n your-namespace <pod-name> | grep -A 20 Events
```

---

## 6. 验证清单

使用以下清单确保所有配置正确：

### A 组件（L7 Nginx）验证清单

- [ ] `proxy_read_timeout 300s;` 已配置
- [ ] `proxy_connect_timeout 300s;` 已配置
- [ ] `proxy_send_timeout 300s;` 已配置
- [ ] Nginx 配置已重载（`nginx -s reload`）
- [ ] 错误日志中无超时错误
- [ ] 可以直接访问 A 组件并测试

**验证命令：**
```bash
nginx -T | grep -E "proxy_read_timeout|proxy_connect_timeout|proxy_send_timeout"
```

---

### B 组件（L4 Nginx）验证清单

- [ ] `proxy_timeout 300s;` 已配置（Stream 模块）
- [ ] Nginx 配置已重载
- [ ] TCP 连接正常（`telnet` 或 `nc` 测试）
- [ ] 日志中无连接错误

**验证命令：**
```bash
cat /etc/nginx/nginx.conf | grep "proxy_timeout"
netstat -an | grep 8080
```

---

### C 组件（Kong DP）验证清单

- [ ] Service `read_timeout` 设置为 300000ms
- [ ] Service `write_timeout` 设置为 300000ms
- [ ] Service `connect_timeout` 设置为 60000ms
- [ ] Kong 配置已应用（重启或热更新）
- [ ] 路由配置正确

**验证命令：**
```bash
curl -s http://kong-admin:8001/services/<service-name> | jq '.read_timeout, .write_timeout'
```

---

### D 组件（GKE Runtime）验证清单

- [ ] 应用层超时配置正确（根据框架）
- [ ] Pod 资源充足（CPU/内存）
- [ ] Pod 无频繁重启
- [ ] 应用日志无超时错误
- [ ] Service 和 Ingress 配置正确

**验证命令：**
```bash
kubectl get pods -n your-namespace
kubectl top pods -n your-namespace
kubectl logs -n your-namespace -l app=your-app --tail=50
```

---

## 7. 推荐的测试流程

### 阶段 1：基础连通性测试（5 分钟）

```bash
# 1. 测试短延迟（10 秒）
curl -v -H "Host: www.aibang.com" \
    "https://your-entry-point.com/abc/v1/test/delay/10"

# 2. 检查所有组件日志
# A: tail -f /var/log/nginx/access.log
# B: tail -f /opt/access-in.log
# C: kubectl logs -n kong -l app=kong -f
# D: kubectl logs -n your-ns -l app=your-app -f
```

---

### 阶段 2：中等延迟测试（10 分钟）

```bash
# 测试 60 秒、120 秒、180 秒延迟
for delay in 60 120 180; do
    echo "Testing ${delay}s delay..."
    time curl -v -H "Host: www.aibang.com" \
        "https://your-entry-point.com/abc/v1/test/delay/${delay}"
    echo ""
done
```

---

### 阶段 3：边界测试（15 分钟）

```bash
# 测试接近和超过 300 秒的延迟
for delay in 290 295 300 305 310; do
    echo "Testing ${delay}s delay..."
    time curl -v --max-time 320 \
        -H "Host: www.aibang.com" \
        "https://your-entry-point.com/abc/v1/test/delay/${delay}"
    echo ""
    sleep 5
done
```

---

### 阶段 4：并发压力测试（20 分钟）

```bash
# 使用 ab 进行并发测试
ab -n 50 -c 5 -s 310 \
    -H "Host: www.aibang.com" \
    "https://your-entry-point.com/abc/v1/test/delay/180"
```

---

## 8. 生产环境最佳实践

### 8.1 超时配置建议

| 组件 | 配置项 | 推荐值 | 说明 |
|------|--------|--------|------|
| A (L7 Nginx) | `proxy_read_timeout` | 300s | 读取后端响应超时 |
| A (L7 Nginx) | `proxy_connect_timeout` | 60s | 连接后端超时 |
| A (L7 Nginx) | `proxy_send_timeout` | 300s | 发送请求到后端超时 |
| B (L4 Nginx) | `proxy_timeout` | 300s | TCP 代理超时 |
| C (Kong) | `read_timeout` | 300000ms | 读取上游响应超时 |
| C (Kong) | `write_timeout` | 300000ms | 写入上游请求超时 |
| C (Kong) | `connect_timeout` | 60000ms | 连接上游超时 |
| D (Runtime) | 应用层超时 | 300s | 根据框架配置 |

---

### 8.2 监控告警配置

```yaml
# Prometheus 告警规则示例
groups:
  - name: timeout_alerts
    rules:
      - alert: HighTimeoutRate
        expr: rate(nginx_http_requests_total{status="504"}[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High timeout rate detected"
          description: "Timeout rate is {{ $value }} requests/sec"
      
      - alert: SlowResponseTime
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 200
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "95th percentile response time > 200s"
```

---

### 8.3 日志格式优化

**Nginx 日志格式（包含响应时间）：**

```nginx
log_format detailed '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

access_log /var/log/nginx/access.log detailed;
```

---

## 9. 故障恢复预案

### 场景 1：超时配置未生效

**快速回滚：**

```bash
# A 组件
ssh user@a-component
cd /etc/nginx
cp nginx.conf.backup nginx.conf
nginx -t && nginx -s reload

# C 组件（Kong）
kubectl rollout undo deployment/kong -n kong-namespace
```

---

### 场景 2：大量请求超时

**临时缓解措施：**

```bash
# 1. 增加后端 Pod 副本数
kubectl scale deployment/your-app -n your-namespace --replicas=10

# 2. 启用 HPA（如果未启用）
kubectl autoscale deployment/your-app -n your-namespace \
    --min=3 --max=20 --cpu-percent=70

# 3. 检查并清理僵尸连接
netstat -an | grep TIME_WAIT | wc -l
```

---

## 10. 总结

**关键验证命令（一键复制）：**

```bash
# 快速端到端测试
time curl -v --max-time 310 \
    -H "Host: www.aibang.com" \
    "https://your-entry-point.com/abc/v1/your-endpoint"

# 检查所有组件配置
echo "=== A Component (L7 Nginx) ==="
ssh user@a-component "nginx -T | grep -E 'proxy_read_timeout|proxy_connect_timeout|proxy_send_timeout'"

echo "=== B Component (L4 Nginx) ==="
ssh user@b-component "cat /etc/nginx/nginx.conf | grep proxy_timeout"

echo "=== C Component (Kong) ==="
curl -s http://kong-admin:8001/services/<service-name> | jq '.read_timeout, .write_timeout, .connect_timeout'

echo "=== D Component (GKE Runtime) ==="
kubectl get pods -n your-namespace
kubectl logs -n your-namespace -l app=your-app --tail=20
```

**验证成功标准：**
- ✅ 180 秒延迟请求成功返回
- ✅ 290 秒延迟请求成功返回
- ✅ 310 秒延迟请求在 ~300 秒时超时
- ✅ 所有组件日志无异常错误
- ✅ 并发测试无大量超时

---

## 附录：参考资料

- [Nginx Proxy Module Documentation](http://nginx.org/en/docs/http/ngx_http_proxy_module.html)
- [Nginx Stream Module Documentation](http://nginx.org/en/docs/stream/ngx_stream_proxy_module.html)
- [Kong Service Configuration](https://docs.konghq.com/gateway/latest/admin-api/#service-object)
- [GCP Load Balancer Timeout Behavior](https://cloud.google.com/load-balancing/docs/backend-service#timeout-setting)
- [Kubernetes Service Timeouts](https://kubernetes.io/docs/concepts/services-networking/service/)
