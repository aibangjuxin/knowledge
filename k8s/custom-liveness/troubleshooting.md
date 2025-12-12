# GKE 探针故障排查指南 (Troubleshooting Guide)

当 Pod 因为探针配置不当而无法启动或频繁重启时，请按照本指南进行排查。

## 1. 常见错误现象

### 1.1 Pod 陷入 CrashLoopBackOff

**现象**：
Pod 状态变为 `CrashLoopBackOff`，或者 `Running` 几分钟后又重启。

**排查步骤**：
查看 Pod 的重启原因：
```bash
kubectl describe pod <pod-name>
```

在 Events 部分查找以下关键词：
*   `Liveness probe failed`: **存活探针失败**。这意味着应用运行了一段时间后，健康检查接口超时或返回非 200。
*   `Startup probe failed`: **启动探针失败**。这意味着应用在规定的时间内（`failureThreshold * periodSeconds`）没有完成启动。

### 1.2 Service 访问不通 (Endpoints 为空)

**现象**：
Pod 状态是 `Running`，但是通过 Service 无法访问，查看 Endpoints 为空。

**排查步骤**：
```bash
kubectl describe pod <pod-name>
```
查找：
*   `Readiness probe failed`: **就绪探针失败**。应用虽然活着，但是健康检查接口返回失败，导致流量被切断。

---

## 2. 场景化解决方案

### 场景一：应用启动太慢，StartupProbe 杀死了 Pod

**原因**：应用初始化逻辑（加载 Spring Context、连接数据库、预热缓存）耗时超过了 `startupProbe` 的总配额。

**解决**：
1.  **临时方案**：手动增加 `failureThreshold`。
    ```yaml
    startupProbe:
      periodSeconds: 10
      failureThreshold: 30  # 原来可能是 10，增加到 30 (5分钟)
    ```
2.  **长期方案**：使用 `measure_startup.sh` 测量真实启动时间，并重新计算参数。

### 场景二：LivenessProbe 频繁误杀

**原因**：
*   设置了 `initialDelaySeconds` 但不够长（如果没配 startupProbe）。
*   应用进行 Full GC，导致短时间无响应。
*   健康检查接口依赖了数据库，数据库卡顿导致接口超时。

**解决**：
1.  **配置**：确保 `timeoutSeconds` 不要设置得太激进（建议 3-5秒）。
2.  **代码**：**强烈建议 Liveness 检查不要依赖外部组件**（如数据库）。Liveness 应该只检查“我这个进程还在不在，有没有死锁”。连接数据库失败应该会导致 Readiness 失败（切断流量），而不是 Liveness 失败（重启容器）。

### 场景三：InitContainer 卡住

**现象**：Pod 状态一直是 `Init:0/1`，此时探针不会报错（因为还没开始运行）。

**原因**：
*   `appd-init-service` 复制文件慢，或者 Volume 挂载有问题。
*   网络问题导致镜像拉取失败。

**解决**：
*   查看 Init 容器日志：`kubectl logs <pod-name> -c appd-init-service`。
*   探针配置此时无需调整，因为还没轮到它们工作。

---

## 3. 快速自检清单 (Checklist)

在提交配置前，请检查：

- [ ] **StartupProbe 是否存在？** (推荐必须配置，替代 InitialDelaySeconds)
- [ ] **StartupProbe 时间够不够？** (总时间 > P99 启动时间 * 1.5)
- [ ] **Port 是否正确？** (必须与 containerPort 一致)
- [ ] **Path 是否正确？** (确保 curl 能访问通)
- [ ] **Liveness 依赖是否解耦？** (避免因 DB 抖动导致 Pod 重启)

## 4. 常用调试命令速查

```bash
# 查看上次失败的原因 (Previous logs)
kubectl logs <pod-name> --previous

# 查看当前探针配置
kubectl get pod <pod-name> -o yaml | grep -A 20 "livenessProbe"

# 强制进入容器手动测试 (如果 Pod 还在 Running)
kubectl exec -it <pod-name> -- curl -v http://localhost:8080/health
```
