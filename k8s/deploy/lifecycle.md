# Kubernetes Lifecycle Hook

## 概述

Kubernetes 提供了两种生命周期钩子，允许用户在容器启动后和终止前执行自定义逻辑：

- **postStart**：容器主进程启动后立即执行
- **preStop**：容器终止前执行，常用于优雅关闭

## 基础用法

### postStart Hook（容器启动后执行）

```yaml
lifecycle:
  postStart:
    exec:
      command:
        - /bin/bash
        - -c
        - /bin/bash /opt/agent/lockdown.sh
```

### preStop Hook（容器终止前执行）

```yaml
lifecycle:
  preStop:
    exec:
      command:
        - /bin/bash
        - -c
        - /bin/bash /opt/agent/graceful-shutdown.sh
```

### HTTP Get Hook

```yaml
lifecycle:
  postStart:
    httpGet:
      host: <host>        # 可选，默认 Pod IP
      port: 8080
      path: /healthz
```

```yaml
lifecycle:
  preStop:
    httpGet:
      host: 127.0.0.1
      port: 9090
      path: /shutdown
```

## 执行时序

```
容器创建
    │
    ▼
┌─────────────────┐
│  postStart hook │◄── 容器进程启动后立即执行
└────────┬────────┘
         │
         ▼
    容器主进程运行
         │
         ▼
┌─────────────────┐
│  preStop hook   │◄── 收到 SIGTERM 后、执行终止前
└────────┬────────┘
         │
         ▼
    容器主进程收到 SIGTERM
         │
         ▼
    容器被 SIGKILL 终止
```

## 实际应用场景

### 1. 启动时清理（postStart）

```yaml
# 示例：删除遗留的 PID 文件或临时文件
lifecycle:
  postStart:
    exec:
      command:
        - /bin/bash
        - -c
        - |
          rm -f /tmp/*.pid
          rm -f /var/run/*.sock
          chmod 777 /some/path
```

### 2. 注册到服务发现（postStart）

```yaml
# 示例：向 Consul 注册服务实例
lifecycle:
  postStart:
    exec:
      command:
        - /bin/bash
        - -c
        - |
          curl -X PUT http://consul:8500/v1/agent/service/register \
            -d '{"name":"app","address":"$POD_IP","port":8080}'
```

### 3. 预热缓存（postStart）

```yaml
# 示例：应用启动后预加载缓存
lifecycle:
  postStart:
    exec:
      command:
        - /bin/bash
        - -c
        - /scripts/warm-cache.sh
```

### 4. 优雅关闭（preStop）

```yaml
# 示例：等待流量排空后再终止
lifecycle:
  preStop:
    exec:
      command:
        - /bin/bash
        - -c
        - |
          nginx -s quit  # 让 Nginx 等待连接关闭
          sleep 5        # 等待流量排空
```

### 5. 关闭时通知其他服务（preStop）

```yaml
# 示例：从服务发现注销
lifecycle:
  preStop:
    exec:
      command:
        - /bin/bash
        - -c
        - |
          curl -X DELETE http://consul:8500/v1/agent/service/deregister/$HOSTNAME
```

### 6. 生产级健康检查配合（preStop + 就绪探针）

```yaml
spec:
  containers:
  - name: app
    lifecycle:
      preStop:
        exec:
          command: ["/bin/bash", "-c", "sleep 10"]
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
    livenessProbe:
      httpGet:
        path: /health
        port: 8080
```

> **说明**：`preStop` + `sleep` 的组合常用于确保在 Kubernetes 发送 SIGTERM 后，有足够时间让负载均衡器将流量从待终止的 Pod 摘除。

## 关键行为说明

| 特性 | postStart | preStop |
|------|-----------|---------|
| **触发时机** | 容器主进程启动后 | 容器被 SIGTERM 前 |
| **阻塞主进程** | 否（异步执行） | 否（异步执行） |
| **失败处理** | 容器会被 `Failed` 状态并重启 | 只记录失败，终止流程继续 |
| **执行时长** | 计入容器启动时间（影响 liveness） | 计入 `terminationGracePeriodSeconds` |
| **执行次数** | 恰好一次（容器创建时） | 恰好一次（容器终止时） |

### 注意事项

1. **postStart 不阻塞主进程启动**
   - hook 执行期间，容器主进程已经运行
   - 如果 hook 失败，容器会被终止并重启

2. **preStop 会阻塞终止信号**
   - SIGTERM 只在 `preStop` 执行完毕后才发送
   - 总执行时间不能超过 `terminationGracePeriodSeconds`（默认 30s）

3. **hook 失败不影响容器运行**
   - postStart 失败 → 容器 `Failed` → 重启
   - preStop 失败 → 仅记录日志，终止流程继续

4. **超时控制**
   - 默认超时 30 秒（Kubelet 层面限制）
   - 可通过 `terminationGracePeriodSeconds` 调整

## 完整示例

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  terminationGracePeriodSeconds: 60  # 整个终止流程的超时时间
  containers:
  - name: app
    image: my-app:latest
    ports:
    - containerPort: 8080
    lifecycle:
      postStart:
        exec:
          command:
            - /bin/bash
            - -c
            - /scripts/register.sh
      preStop:
        exec:
          command:
            - /bin/bash
            - -c
            - |
              curl -X POST http://localhost:8080/shutdown
              sleep 15
```

## 常见问题排查

### 查看 hook 执行事件

```bash
kubectl describe pod <pod-name>
```

关注 `Events` 部分中的 `Started` / `PreStopHook` 事件。

### hook 未执行的可能原因

1. **容器启动失败**：postStart 不会执行
2. **Pod 被强制删除**：preStop 可能未完成
3. **terminationGracePeriodSeconds 过短**：preStop 被中断

### 调试 hook 脚本

```bash
# 进入容器手动执行
kubectl exec <pod-name> -c <container> -- /bin/bash /opt/agent/lockdown.sh
```

## 最佳实践

1. **preStop + sleep 是标准做法**：确保服务有足够时间从负载均衡器摘除
2. **postStart 保持轻量**：避免执行耗时操作，影响容器启动速度
3. **使用 HTTP Get 而非 Exec**：更易于监控和超时控制
4. **始终设置 terminationGracePeriodSeconds**：确保复杂清理任务能完成
5. **生产环境建议**：postStart 用于注册/初始化，preStop 用于注销/排空

---

## 实战：容器安全加固（lockdown.sh）

### 场景需求

在多租户或不可信用户环境下，需要对容器进行安全加固，防止用户：
- 登录容器执行命令
- 使用危险命令（rm、curl、wget 等）
- 下载或上传文件
- 安装软件包

### lockdown.sh 脚本

```bash
#!/bin/bash
# lockdown.sh — 容器安全加固脚本
# 用途：删除/禁用危险命令，确保容器不可被交互使用

housekeep() {
    # ============================================================
    # 1. 删除 Shell 解释器（防止命令执行）
    # ============================================================
    local shells="/bin/sh /bin/bash /bin/dash /usr/bin/bash /usr/bin/dash"
    for s in $shells; do
        [ -f "$s" ] && rm -f "$s" && echo "[LOCKDOWN] Removed: $s"
    done

    # ============================================================
    # 2. 删除文件操作命令
    # ============================================================
    local file_ops="/bin/rm /bin/cp /bin/mv /bin/mkdir /bin/chmod /bin/chown /bin/touch /bin/ln"
    for f in $file_ops; do
        [ -f "$f" ] && rm -f "$f" && echo "[LOCKDOWN] Removed: $f"
    done

    # ============================================================
    # 3. 删除文件查看命令
    # ============================================================
    local viewers="/bin/cat /bin/ls /bin/head /bin/tail /bin/less /bin/more /bin/strings"
    for v in $viewers; do
        [ -f "$v" ] && rm -f "$v" && echo "[LOCKDOWN] Removed: $v"
    done

    # ============================================================
    # 4. 删除网络工具
    # ============================================================
    local network="/bin/netcat /usr/bin/nc /usr/bin/curl /usr/bin/wget /usr/bin/scp /usr/bin/sftp /usr/bin/ssh /usr/bin/rsync"
    for n in $network; do
        [ -f "$n" ] && rm -f "$n" && echo "[LOCKDOWN] Removed: $n"
    done

    # ============================================================
    # 5. 删除包管理器
    # ============================================================
    local pkg_mgrs="/usr/bin/apt /usr/bin/apt-get /usr/bin/yum /usr/bin/dnf /usr/bin/pacman /usr/bin/apk"
    for p in $pkg_mgrs; do
        [ -f "$p" ] && rm -f "$p" && echo "[LOCKDOWN] Removed: $p"
    done

    # ============================================================
    # 6. 删除文本编辑器
    # ============================================================
    local editors="/bin/vi /bin/vim /bin/nano /usr/bin/vi /usr/bin/vim /usr/bin/nano"
    for e in $editors; do
        [ -f "$e" ] && rm -f "$e" && echo "[LOCKDOWN] Removed: $e"
    done

    # ============================================================
    # 7. 删除 Python/脚本解释器（防止脚本执行）
    # ============================================================
    local interpreters="/usr/bin/python /usr/bin/python2 /usr/bin/python3 /usr/bin/perl /usr/bin/ruby /usr/bin/php /usr/bin/node /usr/bin/npm"
    for i in $interpreters; do
        [ -f "$i" ] && rm -f "$i" && echo "[LOCKDOWN] Removed: $i"
    done

    # ============================================================
    # 8. 删除其他危险工具
    # ============================================================
    local dangerous="/bin/find /usr/bin/strace /usr/bin/ltrace /usr/bin/gdb /usr/bin/readelf /usr/bin/objdump"
    for d in $dangerous; do
        [ -f "$d" ] && rm -f "$d" && echo "[LOCKDOWN] Removed: $d"
    done

    echo "[LOCKDOWN] Housekeeping completed."
}

housekeep
```

### ConfigMap 配置

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: lockdown-script
  namespace: default
data:
  lockdown.sh: |
    #!/bin/bash
    # lockdown.sh — 容器安全加固脚本

    housekeep() {
        # Shell 解释器
        for s in /bin/sh /bin/bash /bin/dash /usr/bin/bash /usr/bin/dash; do
            [ -f "$s" ] && rm -f "$s"
        done

        # 文件操作
        for f in /bin/rm /bin/cp /bin/mv /bin/mkdir /bin/chmod /bin/chown /bin/touch /bin/ln; do
            [ -f "$f" ] && rm -f "$f"
        done

        # 文件查看
        for v in /bin/cat /bin/ls /bin/head /bin/tail /bin/less /bin/more; do
            [ -f "$v" ] && rm -f "$v"
        done

        # 网络工具
        for n in /usr/bin/curl /usr/bin/wget /usr/bin/scp /usr/bin/sftp /usr/bin/ssh /usr/bin/nc; do
            [ -f "$n" ] && rm -f "$n"
        done

        # 包管理器
        for p in /usr/bin/apt /usr/bin/apt-get /usr/bin/yum /usr/bin/dnf /usr/bin/apk; do
            [ -f "$p" ] && rm -f "$p"
        done

        # 解释器
        for i in /usr/bin/python /usr/bin/python3 /usr/bin/perl /usr/bin/ruby /usr/bin/php; do
            [ -f "$i" ] && rm -f "$i"
        done
    }

    housekeep
```

### Deployment 集成示例

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secured-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: secured-app
  template:
    metadata:
      labels:
        app: secured-app
    spec:
      terminationGracePeriodSeconds: 30
      containers:
      - name: app
        image: nginx:1.25
        ports:
        - containerPort: 80
        volumeMounts:
        - name: lockdown-script
          mountPath: /opt/agent
          readOnly: true
        lifecycle:
          postStart:
            exec:
              command:
              - /bin/bash
              - -c
              - chmod +x /opt/agent/lockdown.sh && /bin/bash /opt/agent/lockdown.sh
      volumes:
      - name: lockdown-script
        configMap:
          name: lockdown-script
          defaultMode: 0755
```

### 分层加固策略

| 层级 | 措施 | 说明 |
|------|------|------|
| **命令删除** | rm -f 删除危险二进制 | 不可逆，容器内无法恢复 |
| **只读挂载** | volumeMounts + readOnly | 防止脚本被修改 |
| **禁止登录** | securityContext runAsNonRoot | 容器以非 root 运行 |
| **能力降级** | securityContext capabilities: DROP ALL | 移除所有 Linux capabilities |
| **Seccomp** | securityContext seccompProfile | 限制系统调用 |
| **AppArmor/SELinux** | securityContext | 强制访问控制 |

### 生产级安全配置（完整版）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secured-app
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 10000
        runAsGroup: 10000
        fsGroup: 10000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: app
        image: nginx:1.25
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: lockdown-script
          mountPath: /opt/agent
          readOnly: true
        - name: tmp
          mountPath: /tmp
        lifecycle:
          postStart:
            exec:
              command:
              - /bin/bash
              - -c
              - /bin/bash /opt/agent/lockdown.sh
      volumes:
      - name: lockdown-script
        configMap:
          name: lockdown-script
          defaultMode: 0755
      - name: tmp
        emptyDir:
          medium: Memory
```

### 注意事项

1. **postStart 执行时机**：lockdown.sh 在容器主进程启动后执行，此时主进程已可接受请求
2. **不可逆操作**：rm 删除命令后，容器内无法恢复，适合一次性加固
3. **主进程兼容性**：确保主进程（如 nginx）不需要被删除的命令
4. **调试困难**：加固后无法登录容器调试，建议在测试环境充分验证
5. **精简优先**：根据实际需求删减，不要过度删除导致应用无法运行

---

## ConfigMap 脚本语法详解与常见错误

### YAML 多行字符串语法（关键）

ConfigMap 中嵌入 shell 脚本必须使用 `|`（literal block scalar）语法。以下是正确和错误的对比：

#### ❌ 错误写法 1：使用 `>`（folded block scalar）

```yaml
data:
  lockdown.sh: >
    #!/bin/bash
    housekeep() {
      ...
    }
```

> **问题**：`>` 会将换行符转换为空格，导致 shell 语法错误（语法被压缩成一行）。

#### ❌ 错误写法 2：缩进与 `data` 同级

```yaml
data:
lockdown.sh: |
  #!/bin/bash
  housekeep() {
    ...
  }
```

> **问题**：`lockdown.sh:` 必须在 `data:` 的缩进范围内，且脚本内容必须进一步缩进。

#### ❌ 错误写法 3：脚本内容缩进不足

```yaml
data:
  lockdown.sh: |
#!/bin/bash
housekeep() {
  ...
}
```

> **问题**：脚本内容必须比 `lockdown.sh:` 多至少一个空格/tab 进行缩进。

#### ✅ 正确写法：标准格式

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: lockdown-script
  namespace: default
data:
  lockdown.sh: |
    #!/bin/bash
    housekeep() {
      for s in /bin/sh /bin/bash; do
        [ -f "$s" ] && rm -f "$s"
      done
    }
    housekeep
```

**关键规则**：
- `data:` 下的每个 key（如 `lockdown.sh`）缩进 2 空格
- 脚本内容缩进 4 空格（比 `lockdown.sh` 多 2 空格）
- `|` 保留脚本的换行和缩进格式

### 验证 ConfigMap 脚本内容的正确方法

```bash
# 查看 ConfigMap 解析后的内容（验证语法是否正确）
kubectl get configmap lockdown-script -o yaml

# 提取脚本内容并检查
kubectl get configmap lockdown-script -o jsonpath='{.data.lockdown\.sh}' > /tmp/lockdown.sh

# 在本地验证脚本语法（使用 bash -n 检查语法错误）
bash -n /tmp/lockdown.sh

# 检查脚本行尾是否有 ^M（Windows 换行符）等问题
cat -A /tmp/lockdown.sh
```

### 常见导致容器启动失败的语法错误

#### 1. 缩进混用（空格和 Tab 混用）

```bash
# 检查 ConfigMap 中的缩进是否一致
kubectl get configmap lockdown-script -o jsonpath='{.data.lockdown\.sh}' | cat -A
```

如果看到 `^I`（Tab 字符）混入以空格缩进的脚本，需要统一使用空格。

#### 2. 行尾有隐藏字符

```bash
# 去除行尾空白字符
kubectl get configmap lockdown-script -o jsonpath='{.data.lockdown\.sh}' | sed 's/[[:space:]]*$//' > cleaned.sh
```

#### 3. 函数定义格式问题

```bash
# 函数定义必须符合 shell 语法
housekeep() {        # ✅ 正确：{ 前后有空格
    ...
}

housekeep(){         # ❌ 错误：{ 前无空格，可能导致解析问题
    ...
}
```

#### 4. 管道中命令的缩进问题

```yaml
# ❌ 错误：管道换行后未正确缩进
command:
- /bin/bash
- -c
- |
  echo "start" |
  grep "test"
```

```yaml
# ✅ 正确：管道换行后保持缩进
command:
- /bin/bash
- -c
- |
  echo "start" |
    grep "test"
```

### 完整的验证和调试流程

```bash
# 1. 创建 ConfigMap
kubectl apply -f lockdown-configmap.yaml

# 2. 验证内容（检查缩进和格式）
kubectl get configmap lockdown-script -o yaml | yq e '.data.lockdown.sh' -

# 3. 提取到临时文件验证语法
kubectl get configmap lockdown-script -o jsonpath='{.data.lockdown\.sh}' > /tmp/lockdown.sh
bash -n /tmp/lockdown.sh && echo "Syntax OK" || echo "Syntax Error"

# 4. 在测试 Pod 中验证执行
kubectl run test --image=busybox --restart=Never --overrides='
{
  "spec": {
    "containers": [{
      "name": "test",
      "image": "busybox",
      "command": ["sh", "-c", "cat /opt/agent/lockdown.sh"],
      "volumeMounts": [{"name": "lockdown", "mountPath": "/opt/agent"}]
    }],
    "volumes": [{"name": "lockdown", "configMap": {"name": "lockdown-script"}}]
  }
}' --rm -it
```

### 推荐：分离脚本文件 vs ConfigMap 内联

| 方式 | 适用场景 | 优点 | 缺点 |
|------|----------|------|------|
| **ConfigMap 内联** | 简单脚本（< 50 行） | 单一文件管理 | YAML 格式限制，语法易错 |
| **单独脚本文件** | 复杂脚本（> 50 行） | 独立 IDE 编辑，语法校验方便 | 多文件管理 |
| **GitOps 挂载** | 生产环境 | 版本控制 + 自动校验 | 配置复杂度增加 |

### 生产推荐：将脚本独立存放

```bash
# 1. 脚本文件单独管理
cat > lockdown.sh << 'EOF'
#!/bin/bash
housekeep() {
  for s in /bin/sh /bin/bash /bin/dash; do
    [ -f "$s" ] && rm -f "$s"
  done
}
housekeep
EOF

# 2. 通过 kustomize 或 helm 管理
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
configMapGenerator:
- name: lockdown-script
  files:
  - lockdown.sh
```

### 快速自查清单

- [ ] ConfigMap 使用 `|` 而非 `>`
- [ ] 脚本内容缩进正确（4 空格 vs `data`）
- [ ] `bash -n` 语法检查通过
- [ ] 行尾无 `^M`（Windows 换行）
- [ ] 函数定义 `{` 前有空格
- [ ] `command` 执行路径与 `volumeMounts` mountPath 一致
- [ ] `defaultMode: 0755` 确保脚本可执行