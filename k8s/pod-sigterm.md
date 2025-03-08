#  sigterm 信号的时间
GKE  node 在做升级的时候肯定是逐个替换 然后会做对应的排水 比如我的一个deployment 有两个Pod 且他们都运行在不同的node 。 我的Pod需要收到一个终止信号。 我能不能获取到的收到这个信号的时间

# summary 

- filter 
```bash
resouce.labels.pod_name="api-service-pa-health-monitor-0-0-2"
Stopping container 
```


# claude 

根据你提到的关键字 "Stopping container"，我来帮你获取 Pod 终止信号的时间。以下是具体方法：

1. 使用 GCP Cloud Logging 查询（推荐方法）：
```bash
# 查询包含 Stopping container 的日志
gcloud logging read 'resource.type="k8s_container" AND textPayload:"Stopping container"' \
--project=YOUR_PROJECT_ID \
--format='table(timestamp,resource.labels.pod_name,textPayload)'
```

2. 使用 kubectl 命令查看事件：
```bash
# 查看所有包含 Stopping container 的事件
kubectl get events --sort-by='.lastTimestamp' | grep "Stopping container"

# 如果知道具体的 Pod 名称，可以使用
kubectl get events --field-selector involvedObject.name=YOUR_POD_NAME --sort-by='.lastTimestamp'
```

3. 直接从 kubelet 日志查找：
```bash
# 在节点上执行
journalctl -u kubelet | grep "Stopping container"
```

4. 使用标准化的日志查询格式：
```bash
# 更精确的 GCP logging 查询
gcloud logging read '
resource.type="k8s_container" AND
jsonPayload.message:"Stopping container" AND
resource.labels.pod_name:"your-pod-name"
' --format='table(timestamp,jsonPayload.message)'
```

建议：
1. 优先使用 GCP Cloud Logging，因为它保留时间更长，查询更方便
2. 记得替换查询中的 YOUR_PROJECT_ID 和 your-pod-name
3. 可以加上时间范围限制，比如添加 `--freshness=1h` 只查看最近一小时的日志

这样你就能看到 Pod 收到终止信号的具体时间戳了。




关于 Kubernetes Pod 收到终止信号（SIGTERM）的时间获取问题，这里为你梳理一个完整的解决方案：

---

### 核心机制解析
当 GKE 节点升级触发 Pod 迁移时，**准确获取 SIGTERM 时间的四个层级**：

#### 1. **节点排空（Drain）触发时机** *(控制平面层)*
- **触发条件**：GKE 节点升级时会自动执行 `kubectl drain <node>`
- **关键日志位置**：
  ```bash
  # 查看节点事件时间戳（精确到秒）
  kubectl describe node <node-name> | grep -A 10 "Events:"
  ```
  ```log
  Events:
    Type    Reason      Age   From            Message
    ----    ------      ----  ----            -------
    Normal  Drain       117s  cluster-manager  Draining node for upgrade
    Normal  Terminating 113s  kubelet         Stopping container api-service
  ```

#### 2. **Pod 删除事件时间** *(Pod 生命周期层)*
- **查看精确时间**：
  ```bash
  # 获取 Pod 事件时间（ISO8601 格式）
  kubectl get pod <pod-name> -o jsonpath='{.metadata.creationTimestamp}' && \
  kubectl get events --field-selector involvedObject.name=<pod-name> --sort-by=.metadata.creationTimestamp
  ```
  ```log
  LAST SEEN   TYPE     REASON      OBJECT          MESSAGE
  5s          Normal   Killing    pod/api-pod-xyz  Stopping container api-service
  3s          Normal   PreStop    pod/api-pod-xyz  Executing preStop hook
  ```

#### 3. **应用接收 SIGTERM 的时间** *(应用层)*
通过代码捕获信号并记录时间戳：

```python
# Python 示例（其他语言逻辑类似）
import signal
import datetime
import logging

logging.basicConfig(filename='/var/log/app_termination.log', level=logging.INFO)

def handle_sigterm(signum, frame):
    timestamp = datetime.datetime.utcnow().isoformat() + "Z"
    logging.info(f"[SIGTERM Received] {timestamp}")
    # 这里添加清理逻辑
    raise SystemExit()

signal.signal(signal.SIGTERM, handle_sigterm)
```

#### 4. **PreStop Hook 执行时间** *(容器层)*
在 PreStop Hook 中记录时间：
```yaml
# deployment.yaml 片段
lifecycle:
  preStop:
    exec:
      command:
        - sh
        - -c
        - 'date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/prestop_time.log; sleep 20'
```

---

### 时间轴可视化
```
[事件流]（假设节点升级从 14:00:00 开始）

14:00:00 | GKE 开始排空 Node-A
14:00:02 | kubelet 发送 SIGTERM 到 Pod (记录于 kubelet 日志)
14:00:02.100 | 应用代码捕获 SIGTERM (应用日志时间)
14:00:02.200 | PreStop Hook 启动 (容器内时间)
14:00:22.200 | PreStop 完成 → 强制终止（若未完成）
```

---

### 精准时间获取方案

#### 方案 1：应用层主动记录
```python
# 增强型日志记录
import time

def handle_sigterm(signum, frame):
    # 获取高精度时间戳（Unix 时间戳 + 毫秒）
    timestamp = time.time_ns() // 1_000_000  # 毫秒级
    logging.info(f"SIGTERM at {timestamp} (epoch ms)")
    # 同步写入磁盘
    with open('/var/log/sigterm.log', 'a') as f:
        f.write(f"{timestamp}\n")
    # 执行清理...
```

#### 方案 2：Sidecar 监控容器
```yaml
# 注入监控 sidecar
containers:
- name: sigterm-monitor
  image: busybox
  command: ["sh", "-c"]
  args:
    - "while true; do
         if [ -f /sigterm/signal.log ]; then
           echo 'SIGTERM detected at $(date -u +'%Y-%m-%dT%H:%M:%S.%NZ')' >> /var/log/sigterm.log;
           exit 0;
         fi;
         sleep 0.1;
       done"
  volumeMounts:
    - name: sigterm-volume
      mountPath: /sigterm

- name: main-app
  # 主容器配置...
  lifecycle:
    preStop:
      exec:
        command: ["sh", "-c", "touch /sigterm/signal.log; sleep 20"]
  volumeMounts:
    - name: sigterm-volume
      mountPath: /sigterm
```

#### 方案 3：Kubernetes 审计日志
启用 GKE 审计日志（需配置）：
```bash
# 查看 API Server 审计日志中的 Pod 删除事件
gcloud logging read 'resource.type="k8s_pod" AND protoPayload.methodName="delete"' \
  --format json \
  --project <your-project-id>
```