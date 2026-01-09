# GKE Gateway 版本切换实时验证指南

本指南提供了一个简单的脚本，用于在执行 `HTTPRoute` 原子更新（或权重切换）时，实时观察流量从“旧版本后端”平滑迁移到“新版本后端”的过程。

---

## 1. 验证目标

- **监控地址**: `https://env-region.aliyun.cloud.uk.aibang/api-name-sprint-samples/v2025/.well-known/healthcheck`
- **验证目的**: 通过不间断的请求，验证在 `kubectl apply` 更新路由配置时，连接是否中断，以及后端是否如预期般切换到了新版本。

---

## 2. 实时监控脚本 (Shell)

将以下代码保存为 `verify-switch.sh` 并运行。该脚本会每隔 0.5 秒发送一次请求，并打印当前的响应内容。

```bash
#!/bin/bash

# 配置目标 URL
URL="https://env-region.aliyun.cloud.uk.aibang/api-name-sprint-samples/v2025/.well-known/healthcheck"

echo "开始监控流量切换..."
echo "URL: $URL"
echo "按 [CTRL+C] 停止监控。"
echo "--------------------------------------------------------"
echo "TIMESTAMP            | STATUS | RESPONSE BODY"
echo "--------------------------------------------------------"

while true; do
  # 获取当前时间戳
  TS=$(date +"%Y-%m-%d %H:%M:%S")
  
  # 发送 curl 请求
  # -s: 静默模式
  # -k: 忽略证书（如果需要）
  # -w: 捕捉 HTTP 状态码
  # -o: 捕捉响应体
  RESPONSE=$(curl -sk -w " %{http_code}" "$URL")
  
  # 分离状态码和响应内容
  HTTP_STATUS=$(echo "$RESPONSE" | awk '{print $NF}')
  BODY=$(echo "$RESPONSE" | sed "s/ $HTTP_STATUS$//")

  # 打印输出
  printf "%s |  %s   | %s\n" "$TS" "$HTTP_STATUS" "$BODY"

  # 设置轮询间隔 (0.5秒)
  sleep 0.5
done
```

---

## 3. 预期验证过程

### 步骤 A：启动监控
在终端打开一个窗口，运行上述脚本。你会看到流量稳定指向旧版本（例如 `v2025.11.23`）：

```text
2026-01-09 09:40:01 |  200   | {"version": "v2025.11.23", "status": "UP"}
2026-01-09 09:40:02 |  200   | {"version": "v2025.11.23", "status": "UP"}
```

### 步骤 B：执行版本切换
在**另一个**终端窗口，执行你的部署/更新命令：
```bash
kubectl apply -f httproute-v2025-new.yaml
```

### 步骤 C：观察输出变化
在第一个窗口中，你会观察到以下变化：
1. **连接持续性**: 确认在切换瞬间没有出现 `000` 或 `503` 错误。
2. **内容跳转**: 响应体中的版本号从 `11.23` 变更为 `11.24`。

```text
2026-01-09 09:40:10 |  200   | {"version": "v2025.11.23", "status": "UP"}
2026-01-09 09:40:11 |  200   | {"version": "v2025.11.24", "status": "UP"}  <-- 切换完成
2026-01-09 09:40:12 |  200   | {"version": "v2025.11.24", "status": "UP"}
```

---

## 4. 关键指标解读

- **200 OK**: 表示网关和后端均正常工作。
- **Status 持续显示 200**: 证明了“高可用”和“零停机”。即使配置在变更，GFE (Google Front End) 也会确保连接的连续性。
- **Response Body 的即时变化**: 证明了 `replacePrefixMatch` 和 `backendRefs` 的原子更新已成功生效，且路由已经正确导向了新的 Service。
