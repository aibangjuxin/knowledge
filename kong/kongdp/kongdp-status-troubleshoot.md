# Kong Data Plane (DP) Status Troubleshooting Guide

此文档旨在帮助你深入分析 Kong Data Plane (DP) 的运行状态，特别是验证 DP 是否成功连接到 Control Plane (CP)，以及在连接失败时如何进行多维度的排查。

## 核心诊断流程概览

我们将从以下五个维度进行深度探测：

1.  **基础设施层 (Infrastructure)**: Pod 状态、资源与事件
2.  **日志层 (Logs)**: 关键日志信号分析
3.  **控制面层 (Control Plane)**: 从 CP 视角验证节点注册状态 (Source of Truth)
4.  **网络层 (Network)**: 连通性与端口测试
5.  **安全层 (Security)**: 证书与 mTLS 验证

---

## 1. 基础设施层检查 (Infrastructure Health)

首先确保 DP 作为一个 Kubernetes Pod 是健康的。

### 1.1 检查 Pod 状态与重启次数
```bash
kubectl get pods -n kong -l app=kong-dp -o wide
```
*   **关注点**:
    *   `STATUS`: 必须是 `Running`。
    *   `READY`: 必须是 `1/1` (或 `2/2` 如果有 sidecar)。如果不 Ready，流量不会转发进来，但 DP 可能已经连上 CP。
    *   `RESTARTS`: 如果频繁重启，通常是配置错误（如证书缺失）或资源不足（OOM）。

### 1.2 查看 Pod 事件
如果 Pod 启动失败，查看 Events 是最直接的线索：
```bash
kubectl describe pod <kong-dp-pod-name> -n kong
```
*   **关注点**: `Events` 部分，寻找 `MountVolume.SetUp failed` (Secret 挂载失败) 或 `BackOff` (容器启动崩溃) 等错误。

### 1.3 检查资源水位
确认 DP 没有因为 CPU/Memory 限制而被限流或 Kill：
```bash
kubectl top pod <kong-dp-pod-name> -n kong
```

---

## 2. 日志层分析 (Log Analysis)

日志是判断 DP 与 CP 连接状态的最直接证据。

### 2.1 实时查看日志
```bash
kubectl logs -f <kong-dp-pod-name> -n kong
```

### 2.2 关键日志信号 (Key Signals)

| 状态 | 关键日志关键词 | 含义 |
| :--- | :--- | :--- |
| **✅ 成功** | `control_plane: connected` | DP 已成功与 CP 建立连接 |
| **✅ 成功** | `received initial configuration snapshot` | DP 已从 CP 拉取到配置 |
| **❌ 失败** | `failed to connect to control plane` | 网络不通或端口被阻断 |
| **❌ 失败** | `certificate verify failed` | 证书校验失败 (mTLS 问题) |
| **❌ 失败** | `waiting for configuration` (一直卡住) | 连接可能建立了，但 CP 未下发配置 |
| **⚠️ 重连** | `cluster: reconnecting` | 连接不稳定，正在重试 |

---

## 3. 控制面层验证 (Control Plane Verification)

**这是判断 DP 是否在线的“唯一真理 (Source of Truth)”。** 即使 DP 日志说它连上了，也要在 CP 端确认。

### 3.1 查询 CP 集群状态 API
你需要访问 CP 的 Admin API (通常是端口 `8001`)。

**方法 A: 如果你可以直接访问 CP Admin API**
```bash
curl -s http://<kong-cp-admin-url>:8001/clustering/status | jq .
```

**方法 B: 通过 kubectl exec 进入 CP Pod 查询 (推荐)**
```bash
kubectl exec -it <kong-cp-pod-name> -n kong -- curl -s http://localhost:8001/clustering/status
```

### 3.2 分析输出结果
输出是一个 JSON，包含所有已连接的 DP 节点列表：
```json
{
  "data_planes": [
    {
      "id": "7d6bbf0b-b3e7-4cb5-b66f",
      "ip": "10.20.0.15",  <-- 确认这是你 DP Pod 的 IP
      "status": "healthy", <-- 必须是 healthy
      "last_seen": 5,      <-- 距上次心跳的秒数，应该很小
      "version": "3.4.0",
      "sync_status": "normal"
    }
  ]
}
```
*   **判定**: 如果列表中找不到你的 DP Pod IP，或者状态不是 `healthy`，说明连接有问题。

---

## 4. 网络层连通性探测 (Network Connectivity)

如果日志提示连接失败，需要验证网络路径。DP 需要访问 CP 的 `cluster` 端口 (默认 **8005**)。

### 4.1 进入 DP 容器进行探测
```bash
kubectl exec -it <kong-dp-pod-name> -n kong -- sh
```

### 4.2 测试 TCP 连接 (Telnet/NC)
如果容器内有 `nc` 或 `telnet`：
```bash
nc -zv <kong-cp-service-name> 8005
# 或者
telnet <kong-cp-service-name> 8005
```

### 4.3 使用 cURL 测试 (最通用)
即使没有 `nc`，通常也有 `curl`。虽然 8005 是自定义协议，但可以用 curl 测试 TCP 握手：
```bash
curl -v https://<kong-cp-service-name>:8005
```
*   **预期结果**:
    *   `Connected to ...` : 网络层是通的。
    *   `SSL certificate problem` : 网络通，但证书有问题。
    *   `Connection timed out` : 网络不通，检查防火墙/安全组 (GCP Firewall Rules)。
    *   `Could not resolve host` : DNS 问题，检查 Service Name 拼写或 CoreDNS。

---

## 5. 安全层与证书验证 (Certificate & Security)

Kong CP/DP 默认使用 mTLS (双向认证)。这是最容易出错的地方。

### 5.1 检查 DP 挂载的证书
DP 必须挂载 `cluster-cert` 和 `cluster-key`。
```bash
# 在 DP 容器内执行
ls -l /etc/secrets/kong-cluster-cert/
```

### 5.2 验证证书内容 (Subject & Expiry)
查看证书的 `Common Name (CN)` 是否与 CP 期望的一致，且证书未过期。

**在本地或容器内运行:**
```bash
# 假设你已将 Secret 导出或在容器内
openssl x509 -in /etc/secrets/kong-cluster-cert/tls.crt -noout -text | grep -E "Subject:|Not After"
```
*   **Subject**: 必须包含 CP 允许的 CN (通常在 CP 的 `KONG_CLUSTER_MTLS` 配置中指定，默认可能是 `kong_clustering`)。
*   **Not After**: 确保证书没有过期。

### 5.3 检查 Secret 来源
如果你是用 Helm 安装的，检查 `values.yaml` 中的证书配置是否正确指向了生成的 Secret。

```bash
kubectl get secret <your-cluster-cert-secret> -n kong -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject
```

---

## 6. 总结排查清单 (Troubleshooting Checklist)

| 检查项 | 命令/动作 | 预期结果 |
| :--- | :--- | :--- |
| **1. Pod 状态** | `kubectl get pod` | `Running` & `Ready` |
| **2. 关键日志** | `kubectl logs` | 包含 `control_plane: connected` |
| **3. CP 注册表** | `curl .../clustering/status` | 包含 DP IP 且状态 `healthy` |
| **4. 网络连通** | `curl -v cp-host:8005` | `Connected` (TCP 握手成功) |
| **5. 证书有效性** | `openssl x509 ...` | CN 匹配且未过期 |

通过以上步骤，你可以全面地定位 Kong DP 无法连接 CP 的根因，无论是网络隔离、配置错误还是证书问题。
