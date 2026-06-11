# Minimal Platform Adaptation Strategy (Mini-Change)

## 1. 背景与问题 (Background)

作为一个API平台，我们面临着多租户/多用户场景下的服务标准不统一问题。特别是在**健康检查 (Health Check)** 方面，不同用户的应用表现出极大的差异性：

*   **路径不统一**：有的使用 `/health`，有的使用 `/readyz` 或 `/live`。
*   **缺失健康检查**：部分用户应用根本没有暴露 HTTP 健康检查接口。
*   **协议差异**：HTTP vs HTTPS 混用。

为了解决这些问题，同时保持平台改动的最小化 (Minimal Change)，我们需要制定一套临时且强制的适配策略。

## 2. 核心策略 (Core Strategy)

我们采取 **"强制配置注入 (Mandatory Configuration Injection)"** 的策略。

不要求用户修改代码，而是在部署阶段，通过在用户的 Namespace 中强制注入标准化的配置，来统一服务的行为。

### 2.1 目标 (Objectives)
1.  **统一入口**：强制所有接入平台的服务启动在统一端口。
2.  **统一路径**：强制规范化 Context Path，便于网关路由和管理。
3.  **安全合规**：强制开启 SSL。
4.  **规避健康检查混乱**：通过统一端口和协议，平台可以至少实施 TCP 级别的统一检查，或者利用 Spring Boot 的默认行为（如果适用）来标准化管理端点。

## 3. 实施方案 (Implementation)

### 3.1 强制配置规范
在用户的每个 Namespace 中，强制下发并挂载以下 ConfigMap。

*   **端口**：`8443` (HTTPS)
*   **SSL**：启用，使用统一的 Keystore。
*   **Context Path**：`/${apiName}/v${minorVersion}` (同时覆盖 Servlet 和 WebFlux)。

### 3.2 配置详情 (Configuration Detail)

以下是必须注入的 ConfigMap 定义：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: ${namespace}
  name: mycoat-common-sprint-conf
data:
  server-conf.properties: |
    # 强制统一端口
    server.port=8443
    
    # 强制开启 SSL
    server.ssl.enabled=true
    server.ssl.key-store=/opt/keystore/mycoat-sbrt.p12
    server.ssl.key-store-type=PKCS12
    server.ssl.key-store-password=${KEY_STORE_PWD}
    
    # 统一 Context Path (Servlet 栈 — Spring MVC / Web on Servlet 容器)
    server.servlet.context-path=/${apiName}/v${minorVersion}

    # 统一 Base Path (WebFlux 栈 — Spring WebFlux on Netty/Undertow)
    spring.webflux.base-path=/${apiName}/v${minorVersion}
```

### 3.3 健康检查规范（与 Context Path 注入对齐）

**核心约束**：K8s kubelet 的 `httpGet.path` 是**绝对路径**，**不会**被应用的 `server.servlet.context-path` / `spring.webflux.base-path` 改写。因此：

```
❌ httpGet.path: /actuator/health
   → 实际请求 GET /actuator/health
   → Spring 在 context-path=/${apiName}/v${minorVersion} 下看到 404
   → 探针失败 → 容器被 kill → 启动崩溃循环

✅ httpGet.path: /${apiName}/v${minorVersion}/actuator/health
   → 实际请求 GET /${apiName}/v${minorVersion}/actuator/health
   → Spring context-path 正确匹配 → 200
   → 探针通过
```

**双层探针（推荐）**：

```yaml
# === A. TCP 兜底（兼容用户未提供 HTTP 健康端点的场景）===
readinessProbe:
  tcpSocket: { port: 8443 }
  periodSeconds: 10
  failureThreshold: 3
  timeoutSeconds: 3

livenessProbe:
  tcpSocket: { port: 8443 }
  periodSeconds: 20
  failureThreshold: 3
  timeoutSeconds: 3

startupProbe:
  tcpSocket: { port: 8443 }
  periodSeconds: 10
  failureThreshold: 30   # 启动期 ≈5 分钟宽容窗口

# === B. 业务级探针（必填 — 与 context-path 注入对齐）===
# 原因：TCP 通过 ≠ Spring 容器就绪 ≠ context-path 已生效 ≠ 业务健康
startupProbe:                       # 启动期宽容窗口
  httpGet:
    scheme: HTTPS
    path: /${apiName}/v${minorVersion}/actuator/health
    port: 8443
  periodSeconds: 10
  failureThreshold: 30
  timeoutSeconds: 3

readinessProbe:                     # 失败时从 Service endpoints 摘除
  httpGet:
    scheme: HTTPS
    path: /${apiName}/v${minorVersion}/actuator/health
    port: 8443
  periodSeconds: 10
  failureThreshold: 3
  timeoutSeconds: 3

livenessProbe:                      # 失败时 kill 容器（保持轻量，不查 DB）
  httpGet:
    scheme: HTTPS
    path: /${apiName}/v${minorVersion}/actuator/health
    port: 8443
  periodSeconds: 20
  failureThreshold: 3
  timeoutSeconds: 3
```

**给用户的话术**：
> 你的 API 探活真实路径 = `/${apiName}/v${minorVersion}/<你的探活端点>`，已被平台注入到 K8s `startupProbe` / `livenessProbe` / `readinessProbe`，**你不需要自己写**。如需自定义探活端点（如 `/livez` / `/readyz`），请在接入申请中说明，平台会同步更新 probe path。

详细评估见 `cloud/k8s/docs/context-path.md`。

## 4. 平台适配收益 (Benefits)

1.  **降低接入成本**：用户无需修改代码中的端口或路径配置，由平台统一接管。
2.  **简化健康检查**：虽然用户内部健康检查逻辑可能不同，但统一了端口 `8443` 后，平台可以配置统一的 TCP Socket 探针作为兜底，或者在统一的 Context Path 下尝试探测标准端点。
3.  **标准化路由**：网关层可以基于 `${apiName}/v${minorVersion}` 规则自动生成路由，无需逐个配置。

## 5. 后续规划 (Next Steps)
*   该策略为"最小化改动"的临时策略。
*   长期方案应推动用户应用接入标准的 Actuator 或 Sidecar 模式以提供统一的 HTTP 健康检查接口。

---

## 6. Secret + ConfigMap 协同管理（Java / Python 多语言示例）

> **2026-06 修订**：Secret 只存**凭据/证书**（敏感数据），ConfigMap 只存**配置文件**（非敏感）。每个资源**单一职责**，命名也按职责区分。Deployment 同时引用两者。

### 6.1 设计原则（单一职责）

| 资源 | 职责 | 存什么 | 不应存什么 |
|---|---|---|---|
| **Secret** | 凭据 / 证书 | Keystore 文件本体、Keystore 密码、DB 凭据、JWT secret、API Token | ❌ 任何明文配置文件（即使里面包含密码引用 `${KEY_STORE_PWD}`，配置本身也不该进 Secret） |
| **ConfigMap** | 配置文件 / 平台规范 | `springboot.conf`、`gunicorn.conf`、`api-name`、`minor-version`、`log-level` | ❌ 任何敏感凭据（密码、token、证书） |
| **Deployment** | 资源编排 | 镜像、副本数、probe、envFrom + volumeMounts 同时挂载 Secret 和 ConfigMap | ❌ 任何配置内容（只引用资源名） |

**命名对齐**：

| 资源类型 | 命名约定 |
|---|---|
| Secret | `abjx-{env}-{region}-secret-{ns}-server-conf`（只放凭据/证书） |
| ConfigMap | `abjx-{env}-{region}-cm-{ns}-server-conf`（只放配置文件，**`cm` 段显式标识**） |
| ConfigMap（平台规范） | `abjx-{env}-{region}-cm-{ns}-platform-spec`（api-name / minor-version / log-level） |

> 与 `context-path.md` §4.3 平台架构对齐：Secret = 数据面敏感存储；ConfigMap = 控制面 + 配置面。

### 6.2 Secret 模板（**只存凭据 / 证书**）

```yaml
apiVersion: v1
kind: Secret
metadata:
  namespace: {{ .Values.team.namespace }}
  name: abjx-{{ .Values.env }}-{{ .Values.region }}-secret-{{ .Values.team.namespace }}-server-conf
  labels:
    app.kubernetes.io/managed-by: platform
    platform.io/config-type: credentials
type: Opaque
stringData:
  # ── SSL 凭据（敏感）──
  KEY_STORE_PWD: "changeit-please-from-vault"   # 实际值从 Vault/SM 注入
  TRUST_STORE_PWD: "changeit-please-from-vault"

  # ── 数据库 / 下游凭据（敏感，按需）──
  DB_PASSWORD: "from-secret-manager"
  REDIS_PASSWORD: "from-secret-manager"

  # ── JWT / API 凭据（敏感）──
  JWT_SECRET: "from-secret-manager"

# Binary data 段（keystore 文件本体，base64 编码）
data:
  keystore.p12: <base64-encoded-p12-content>
  truststore.p12: <base64-encoded-p12-content>
```

> **关键约束**：Secret 里**没有** `springboot.conf` / `gunicorn.conf` 这种配置文件 key。所有配置文件一律进 ConfigMap。

### 6.3 ConfigMap 模板 — 框架配置（`springboot.conf` / `gunicorn.conf`）

**注意**：下面的 ConfigMap 包含**两份**框架配置文件作为不同 key（一份 Java 一份 Python），由 Deployment 按镜像语言挂载对应的那份：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: {{ .Values.team.namespace }}
  name: abjx-{{ .Values.env }}-{{ .Values.region }}-cm-{{ .Values.team.namespace }}-server-conf
  labels:
    app.kubernetes.io/managed-by: platform
    platform.io/config-type: server-conf
data:
  # ── Java Spring Boot 配置文件（非敏感）──
  springboot.conf: |
    # 端口
    server.port=8443

    # SSL — 密码从环境变量 KEY_STORE_PWD 读取（配置和密码来源分离）
    server.ssl.enabled=true
    server.ssl.key-store=/opt/keystore/mycoat-sbrt.p12
    server.ssl.key-store-type=PKCS12
    server.ssl.key-store-password=${KEY_STORE_PWD}
    server.ssl.trust-store=/opt/keystore/mycoat-trust.p12
    server.ssl.trust-store-password=${TRUST_STORE_PWD}

    # Context Path (Servlet 栈 — Spring MVC / Web on Servlet 容器)
    server.servlet.context-path=/${apiName}/v${minorVersion}

    # Base Path (WebFlux 栈 — Spring WebFlux on Netty/Undertow)
    spring.webflux.base-path=/${apiName}/v${minorVersion}

    # 日志
    logging.level.root=INFO
    logging.pattern.console=%d{ISO8601} %-5level [%thread] %logger{36} - %msg%n

  # ── Python Gunicorn 配置文件（非敏感）──
  gunicorn.conf: |
    # 端口（与 Java 一致，方便平台统一探针）
    bind = "0.0.0.0:8443"

    # Worker 模型
    workers = ${GUNICORN_WORKERS:-2}
    worker_class = "uvicorn.workers.UvicornWorker"   # FastAPI / Starlette
    timeout = 60
    graceful_timeout = 30
    keepalive = 5

    # SSL — 证书走 Secret volume 挂载
    keyfile = "/opt/keystore/mycoat-sbrt.pem"
    certfile = "/opt/keystore/mycoat-sbrt.crt"
    ssl_version = 5   # TLS 1.3 (gunicorn 21+)

    # 日志
    accesslog = "-"
    errorlog = "-"
    access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(L)s'

    # 性能
    preload_app = True
    max_requests = 1000
    max_requests_jitter = 50
```

### 6.4 ConfigMap 模板 — 平台规范

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: {{ .Values.team.namespace }}
  name: abjx-{{ .Values.env }}-{{ .Values.region }}-cm-{{ .Values.team.namespace }}-platform-spec
  labels:
    app.kubernetes.io/managed-by: platform
    platform.io/config-type: platform-spec
data:
  api-name: ${apiName}
  minor-version: ${minorVersion}
  log-level: INFO
  metrics-enabled: "true"
  tracing-enabled: "true"
```

### 6.5 Deployment 挂载示例（Java / Spring Boot）

**核心**：Deployment 同时引用 ① Secret（密码 + 证书文件）② ConfigMap（springboot.conf + 平台规范），各取所需。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${apiName}
  namespace: {{ .Values.team.namespace }}
spec:
  template:
    spec:
      containers:
        - name: app
          image: ${apiName}:${minorVersion}
          ports:
            - containerPort: 8443

          # ── A. Secret 注入：所有 stringData key 自动成为环境变量 ──
          # 拿到的：KEY_STORE_PWD / TRUST_STORE_PWD / DB_PASSWORD / JWT_SECRET ...
          envFrom:
            - secretRef:
                name: abjx-{{ .Values.env }}-{{ .Values.region }}-secret-{{ .Values.team.namespace }}-server-conf

          # ── B. ConfigMap 注入：api-name / minor-version 作为环境变量 ──
          env:
            - name: API_NAME
              valueFrom:
                configMapKeyRef:
                  name: abjx-{{ .Values.env }}-{{ .Values.region }}-cm-{{ .Values.team.namespace }}-platform-spec
                  key: api-name
            - name: MINOR_VERSION
              valueFrom:
                configMapKeyRef:
                  name: abjx-{{ .Values.env }}-{{ .Values.region }}-cm-{{ .Values.team.namespace }}-platform-spec
                  key: minor-version

          # ── C. 挂载卷：证书从 Secret，配置从 ConfigMap ──
          volumeMounts:
            - name: keystore-vol                          # 证书文件（来自 Secret 的 data: 段）
              mountPath: /opt/keystore
              readOnly: true
            - name: spring-conf                           # 框架配置（来自 ConfigMap）
              mountPath: /etc/spring/conf
              readOnly: true

          # ── D. 启动参数：指向 ConfigMap 挂载的目录 ──
          args:
            - "--spring.config.additional-location=file:/etc/spring/conf/"

          # ── E. 业务级 probe（与 context-path 注入对齐）──
          startupProbe:
            httpGet:
              scheme: HTTPS
              path: /${apiName}/v${minorVersion}/actuator/health
              port: 8443
            periodSeconds: 10
            failureThreshold: 30
            timeoutSeconds: 3
          readinessProbe:
            httpGet:
              scheme: HTTPS
              path: /${apiName}/v${minorVersion}/actuator/health
              port: 8443
            periodSeconds: 10
            failureThreshold: 3
            timeoutSeconds: 3
          livenessProbe:
            httpGet:
              scheme: HTTPS
              path: /${apiName}/v${minorVersion}/actuator/health
              port: 8443
            periodSeconds: 20
            failureThreshold: 3
            timeoutSeconds: 3

      # ── F. 资源声明：每个 volume 明确数据来源 ──
      volumes:
        - name: keystore-vol                             # 证书：来自 Secret
          secret:
            secretName: abjx-{{ .Values.env }}-{{ .Values.region }}-secret-{{ .Values.team.namespace }}-server-conf
            items:
              - key: keystore.p12
                path: mycoat-sbrt.p12
              - key: truststore.p12
                path: mycoat-trust.p12
        - name: spring-conf                              # 配置：来自 ConfigMap
          configMap:
            name: abjx-{{ .Values.env }}-{{ .Values.region }}-cm-{{ .Values.team.namespace }}-server-conf
            items:
              - key: springboot.conf
                path: springboot.conf
```

### 6.6 Deployment 挂载示例（Python / Gunicorn + FastAPI）

**与 Java 部署的唯一差异**：`volumes[].configMap.items` 取 `gunicorn.conf` 而不是 `springboot.conf`；`command` 指向 gunicorn。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${apiName}
  namespace: {{ .Values.team.namespace }}
spec:
  template:
    spec:
      containers:
        - name: app
          image: ${apiName}:${minorVersion}
          ports:
            - containerPort: 8443

          envFrom:
            - secretRef:
                name: abjx-{{ .Values.env }}-{{ .Values.region }}-secret-{{ .Values.team.namespace }}-server-conf
          env:
            - name: API_NAME
              valueFrom:
                configMapKeyRef:
                  name: abjx-{{ .Values.env }}-{{ .Values.region }}-cm-{{ .Values.team.namespace }}-platform-spec
                  key: api-name
            - name: MINOR_VERSION
              valueFrom:
                configMapKeyRef:
                  name: abjx-{{ .Values.env }}-{{ .Values.region }}-cm-{{ .Values.team.namespace }}-platform-spec
                  key: minor-version

          volumeMounts:
            - name: cert-vol
              mountPath: /opt/keystore
              readOnly: true
            - name: gunicorn-conf
              mountPath: /etc/gunicorn
              readOnly: true

          # ── 启动 gunicorn，指向 ConfigMap 挂载的配置文件 ──
          command: ["gunicorn"]
          args:
            - "-c"
            - "/etc/gunicorn/gunicorn.conf"
            - "main:app"

          startupProbe:
            httpGet:
              scheme: HTTPS
              path: /${apiName}/v${minorVersion}/health
              port: 8443
            periodSeconds: 10
            failureThreshold: 30
            timeoutSeconds: 3
          readinessProbe:
            httpGet:
              scheme: HTTPS
              path: /${apiName}/v${minorVersion}/health
              port: 8443
            periodSeconds: 10
            failureThreshold: 3
            timeoutSeconds: 3
          livenessProbe:
            httpGet:
              scheme: HTTPS
              path: /${apiName}/v${minorVersion}/health
              port: 8443
            periodSeconds: 20
            failureThreshold: 3
            timeoutSeconds: 3

      volumes:
        - name: cert-vol
          secret:
            secretName: abjx-{{ .Values.env }}-{{ .Values.region }}-secret-{{ .Values.team.namespace }}-server-conf
            items:
              - key: keystore.p12
                path: mycoat-sbrt.p12
              - key: truststore.p12
                path: mycoat-trust.p12
        - name: gunicorn-conf                              # ← 与 Java 唯一差异：取 gunicorn.conf
          configMap:
            name: abjx-{{ .Values.env }}-{{ .Values.region }}-cm-{{ .Values.team.namespace }}-server-conf
            items:
              - key: gunicorn.conf
                path: gunicorn.conf
```

### 6.7 关键设计决策（单一职责原则）

| 决策 | 理由 |
|---|---|
| **Secret 只存凭据 / 证书，ConfigMap 只存配置** | **单一职责**：资源类型对应数据敏感度，便于审计 / RBAC 差异化配置。Secret 改一个密码不应该触发 Pod 重启外的操作；ConfigMap 改一个 log-level 不应该走 secret 拉取链路 |
| **Java/Python 配置文件放在同一个 ConfigMap 的不同 key** | 与上一版"放在 Secret"相比，**改为 ConfigMap** 后这是合理选择——它们都是非敏感配置；同一个 ConfigMap 让 Java 团队和 Python 团队都从同一个资源读，互不干扰 |
| **Keystore 文件本体用 Secret 的 `data:` 段（二进制）** | 证书/keystore 是 binary，ConfigMap 不适合（utf-8 限制 + 体积大），但配置文件（properties/conf）是文本，ConfigMap 才是正确位置 |
| **平台规范走独立 ConfigMap（与框架配置分离）** | `api-name` / `minor-version` / `log-level` 等是平台控制面，更新频率与框架配置不同；分离后可独立滚动 |
| **`envFrom.secretRef` 自动注入所有 stringData key** | 减少重复 `env:` 定义；新增凭据无需改 Deployment |
| **`env.configMapKeyRef` 显式引用平台规范** | 与 `envFrom` 区别对待：只挑需要的字段，避免把框架配置当成环境变量误暴露 |
| **probe path 直接用 `${apiName}/v${minorVersion}/actuator/health`** | `${apiName}` 和 `${minorVersion}` 是 Helm 模板变量，在 helm install 时已渲染为字面量；K8s 不会再次解析 `${}`，避免循环引用 |

### 6.7.1 「Secret 改密码 vs ConfigMap 改 log-level」— 详细影响分析

> 上一节「单一职责」那一行写得太简略，这里**专门展开**讲 K8s 在「资源变更 → Pod 实际行为」这条链路上的真实机制。

#### 6.7.1.1 关键机制：K8s 资源更新 ≠ Pod 立刻变化

K8s 资源（Secret / ConfigMap）更新后，**不会**直接通知 Pod。传播机制有两条独立的路径：

| 传播路径 | 适用场景 | 触发方式 | 延迟 |
|---|---|---|---|
| **Volume mount**（文件路径） | `volumes[].secret` / `volumes[].configMap` | kubelet 周期性 sync（默认 60s-120s）发现新 hash → 重建 Projected Volume → 软链接切换 | 60-120s |
| **env / envFrom**（环境变量） | `env.valueFrom.secretKeyRef` / `envFrom.secretRef` | **完全不刷新** — env 在容器启动时注入一次，写进进程 env；K8s 不会主动更新已运行容器的 env | ∞（必须重启） |

> ⚠️ 这就是为什么"改 Secret 触发不触发 Pod 重启"的答案**不唯一**——取决于你的 Deployment 用的是 **Volume mount** 还是 **env 注入**。

#### 6.7.1.2 我们这套架构里，两种资源的影响矩阵

| 资源变更 | 涉及 K8s 资源 | Pod 侧影响 | 用户感知 | 触发 Pod 重启？ | 触发 Deployment 滚动？ |
|---|---|---|---|---|---|
| 改 `KEY_STORE_PWD`（Secret.stringData） | Secret | **volumes 不受影响**（密码不是文件）；**envFrom 也不刷新**（env 启动时已注入） | **进程内的旧密码仍生效**，新密码不生效 | ❌ 否 | ❌ 否 |
| 改 `keystore.p12`（Secret.data） | Secret | **volumes 会被 kubelet sync 检测到** → 容器内 `/opt/keystore/mycoat-sbrt.p12` 文件内容更新（`..data` 软链接切换） | 文件已更新，但 **JVM 已加载的 SSL context 不会自动重载** | ❌ 否（仅文件更新） | ❌ 否（不会滚动） |
| 改 `springboot.conf`（ConfigMap.data） | ConfigMap `cm-server-conf` | **volumes 同步更新** → `/etc/spring/conf/springboot.conf` 文件更新 | **文件已更新，但 Spring Boot 默认不会热加载外部 properties**（除非配 `spring.config.location` + `spring.cloud.config` 之类） | ❌ 否（仅文件更新） | ❌ 否（不会滚动） |
| 改 `log-level`（ConfigMap.data） | ConfigMap `cm-platform-spec` | **env 不刷新**（envFrom/configMapKeyRef 都是启动时注入） | 进程内旧值仍生效 | ❌ 否 | ❌ 否 |
| 改 `api-name`（ConfigMap.data） | ConfigMap `cm-platform-spec` | 同上，env 不刷新 | 进程内旧值仍生效 | ❌ 否 | ❌ 否 |

> **核心结论**：在这个架构下，**改 Secret / ConfigMap 都不会自动触发 Pod 重启或 Deployment 滚动**。这正是"单一职责"的好处 ——**平台控制面是受控变更，不是被动抖动**。

#### 6.7.1.3 那怎么让变更真正生效？

按"操作成本从低到高"排列：

| 生效方式 | 操作 | 适用场景 | 影响范围 |
|---|---|---|---|
| **进程热重载** | 应用监听文件变化 / SIGHUP（如 `nginx -s reload`、Java `spring-cloud-bus`、Python Gunicorn `SIGHUP`） | 配置文件非破坏性变更（log-level、调参） | 仅当前 Pod 内进程，不影响其他 Pod |
| **手动 rollout** | `kubectl rollout restart deployment/${apiName}` | 任何 Secret/ConfigMap 变更（最通用的兜底） | 该 Deployment 所有 Pod 滚动重启 |
| **Reloader Controller** | 安装 `stakater/reloader` 之类，自动监听 ConfigMap/Secret 变化 → 触发 `kubectl patch` rollout annotation | 高频变更的平台规范（log-level、feature flag） | 该 Deployment 所有 Pod 滚动重启 |
| **Operator / 自定义控制器** | 自研 CRD + Controller 监听变更 | 复杂场景（多 Deployment 联动、灰度发布） | 全部相关 Pod |

#### 6.7.1.4 具体场景演绎（用户视角）

**场景 A：用户改了 DB 密码**

```
1. 用户执行：kubectl edit secret abjx-...-secret-...-server-conf
2. 修改字段：DB_PASSWORD: "new-password"
3. K8s 行为：
   - 旧 Secret 对象被替换为新对象
   - 所有引用该 Secret 的 Pod：envFrom 注入的 DB_PASSWORD 仍是旧值（env 启动时注入）
   - volumes 不涉及（密码不是文件）
4. Pod 实际行为：
   - 进程内 DB 连接池仍持有旧凭据
   - 应用代码不会自动重新读环境变量
5. 用户感知：新密码"没生效"
6. 正确做法：
   - 用户主动执行 kubectl rollout restart deployment/${apiName}
   - 或者 Reloader Controller 自动触发
7. 滚动完成后：新 Pod 启动 → 读新 DB_PASSWORD → 业务生效
```

**场景 B：用户改了 log-level**

```
1. 用户执行：kubectl edit configmap abjx-...-cm-...-platform-spec
2. 修改字段：log-level: DEBUG
3. K8s 行为：
   - 旧 ConfigMap 被替换
   - 所有引用 Pod：env.configMapKeyRef 注入的 LOG_LEVEL 仍是旧值
4. Pod 实际行为：
   - 进程内 logging level 仍是 INFO
5. 用户感知：log-level "没生效"
6. 正确做法：
   - 如果应用支持文件热加载（如 Spring Boot `spring.config.location` + actuator refresh）：
     可以等 kubelet 60-120s 同步文件 + 应用监听 reload 事件
   - 否则：kubectl rollout restart
```

**场景 C：用户换了 SSL 证书（rotate keystore.p12）**

```
1. 平台 CI/CD 触发：更新 Secret.data.keystore.p12
2. K8s 行为：
   - kubelet 检测到 Secret hash 变化（默认 60s 内）
   - 重建 Projected Volume
   - 容器内 /opt/keystore/mycoat-sbrt.p12 软链接切换到新内容
3. Pod 实际行为：
   - 文件已更新 ✅
   - JVM SSL context 已加载旧证书到内存，不会自动卸载旧证书
4. 用户感知：连接仍是旧证书（可能直接被客户端报错"certificate unknown"）
5. 正确做法：
   - 关键操作！证书 rotate 必须 kubectl rollout restart
   - 平台应在更新证书的 CI/CD 流水线里自动追加 rollout annotation 触发滚动
```

#### 6.7.1.5 为什么「混合存」是反模式

如果当时按"混合存"（springboot.conf 在 Secret 里）的写法：

| 用户的操作 | 在"混合存"架构下 | 在"单一职责"架构下 |
|---|---|---|
| 改一个 log-level | **要碰 Secret**（因为 springboot.conf 在 Secret 里）→ 触发**凭据审计** → RBAC 路径复杂 → 合规审查受阻 | **只碰 ConfigMap** → 凭据审计零干扰 |
| 改一个 DB 密码 | **只动 Secret 的一行** → 但 Secret 变更可能让 Reloader 误判 → 整 Deployment 滚动 | Secret 变更**不影响 ConfigMap 挂载的 springboot.conf** → 滚动只针对必要的 Deployment |
| 加一个 feature flag | 要碰 Secret → 敏感数据污染 | **只碰 ConfigMap** → 合规清晰 |
| 合规审计（PCI-DSS / 等保） | 审计范围包含框架配置文件 → 噪音大 | 审计范围 = Secret 内容 → 信噪比高 |

**这就是"单一职责"的真正价值**：**让合规边界和变更频率自然解耦**。凭据变更走 Secret 审计链路，配置变更走 ConfigMap 操作链路，**两者互不污染**。

#### 6.7.1.6 一句话总结

> **改 Secret / ConfigMap 不会自动重启 Pod；K8s 只更新容器内的挂载文件 + 启动时注入的 env（且 env 永不刷新）。要让变更真正生效，必须**主动触发滚动**（手动 `rollout restart` / Reloader / CI 流水线注入 rollout annotation）。单一职责的价值是**让凭据变更和配置变更走不同的审计 / 触发链路，平台对两类的滚动策略可以差异化配置**（例如：凭据变更 → 全量滚动；log-level → 灰度滚动；feature flag → 单 Pod 滚动）。

### 6.8 资源依赖图

```
                    ┌─────────────────────────────────────────────┐
                    │  Helm values (env / region / team.namespace) │
                    └────────┬──────────────────────┬────────────┘
                             │                      │
                             ▼                      ▼
       ┌─────────────────────────────────┐   ┌──────────────────────────────┐
       │  Secret                         │   │  ConfigMap (×2)              │
       │  abjx-{env}-{region}-secret-    │   │  ─ cm-server-conf           │
       │       {ns}-server-conf          │   │     ├─ springboot.conf       │
       │  ─ stringData: 凭据             │   │     └─ gunicorn.conf         │
       │  ─ data: keystore.p12 / trust.p12│   │  ─ cm-platform-spec          │
       └────────┬────────────────────────┘   │     ├─ api-name              │
                │                             │     ├─ minor-version         │
                │ envFrom + volumeMounts      │     ├─ log-level             │
                │                             │     └─ ...                    │
                ▼                             └──────┬───────────────────────┘
       ┌─────────────────────────────────────────┐  │
       │  Deployment                             │◄─┘
       │  ─ image: ${apiName}:${minorVersion}    │ volumeMounts (configMap)
       │  ─ envFrom.secretRef → KEY_STORE_PWD ...│
       │  ─ env.configMapKeyRef → API_NAME ...   │
       │  ─ volumeMounts:                        │
       │     ├─ /opt/keystore ← Secret (证书)    │
       │     └─ /etc/spring/conf ← ConfigMap     │
       │  ─ probe path: /${apiName}/v${minorVersion}/actuator/health │
       └─────────────────────────────────────────┘
```

### 6.9 Java `springboot.conf` 与 Python `gunicorn.conf` 的关键差异

| 配置维度 | Java Spring Boot | Python Gunicorn | 平台约束 |
|---|---|---|---|
| **端口** | `server.port=8443` | `bind = "0.0.0.0:8443"` | ✅ 必须一致 |
| **HTTPS** | `server.ssl.*`（JVM 体系） | `certfile` / `keyfile`（OpenSSL 体系） | ✅ 同一 keystore，但要按框架转格式 |
| **Context Path** | `server.servlet.context-path` / `spring.webflux.base-path` | WSGI middleware（`root_path` 参数） | ✅ 都用 `/${apiName}/v${minorVersion}` |
| **健康端点路径** | `/actuator/health`（Actuator） | `/health`（用户自实现） | ✅ 真实路径都已由平台计算 |
| **Worker 模型** | 嵌入式 Tomcat/Reactor Netty | 独立 Gunicorn worker process | ⚠️ 平台建议 `workers` 走 HPA，不写死 |
| **配置加载方式** | `--spring.config.additional-location` | `-c /etc/gunicorn/gunicorn.conf` | ✅ ConfigMap 挂载的目录路径一致 |
