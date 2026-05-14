```table-of-contents
```
下面从 **平台适配、Kong 上游为 HTTPS 的要求、Node.js 如何复用 Java 证书配置、以及 context-path 的最佳实践** 四个角度给你做系统说明，并给出可直接使用的 Node.js 配置模板（包括 HTTPS、自定义 context-path、证书加载方式）。

---

# **1. 问题分析**

你当前平台已经做到：

- **平台强制注入 SSL 证书与端口（8443）**
- **平台强制注入 context-path**（例如：/${apiName}/v${minorVersion}）
- **所有上游服务（无论是 Java / Node.js / Go / Python）最终都必须以 HTTPS+FQDN:8443 暴露给 Kong DP**

Java Spring Boot 已通过 ConfigMap 注入以下字段实现：

```configmap
server.port=8443
server.ssl.enabled=true
server.ssl.key-store=/opt/keystore/mycoat-sbrt.p12
server.ssl.key-store-type=PKCS12
server.ssl.key-store-password=${KEY_STORE_PWD}
server.servlet.context-path=/${apiName}/v${minorVersion}
spring.webflux.base-path=/${apiName}/v${minorVersion}
```

现在的问题是：

> **如果用户交付的是 Node.js 服务，如何在不大量改动代码的情况下，也能自动复用 SSL 配置、统一监听 8443、统一 context-path？**

---

# **2. 平台统一规范：Node.js 的适配要求**

为支持你的平台从 Java 扩展到 Node.js，只需要让 Node.js 服务满足 3 个点：

| **要求**                               | **目的**            | **Node.js 实现方式**                        |
| -------------------------------------- | ------------------- | ------------------------------------------- |
| **1. 必须监听 HTTPS 8443**             | 与 Kong DP 上游一致 | 使用 https.createServer({ key, cert }, app) |
| **2. 必须复用平台注入的证书**          | 保持统一 TLS 信任链 | 使用同一份 p12 → pem 方式加载               |
| **3. 必须接受平台强制的 context-path** | 确保路由结构一致    | Express: app.use(basePath, router)          |

你需要的平台最小适配方式：

➡ **平台只负责把 SSL 文件挂载进去 + 注入环境变量 {apiName}, {minorVersion}, {KEY_STORE_PWD}**

➡ **Node.js 框架只需加载这些环境变量即可**

**无需修改用户代码核心业务逻辑。**

---

# **3. Node.js 如何复用 Java 的 PKCS12 证书**

Node.js 原生 HTTPS server **不支持直接加载 p12**，所以你需要做两件事：

### **✔ 方案 A（推荐）：启动时自动把 P12 转换成 PEM**

平台启动容器时执行：

```
openssl pkcs12 -in /opt/keystore/mycoat-sbrt.p12 \
  -nocerts -nodes -passin pass:${KEY_STORE_PWD} -out /opt/keystore/key.pem

openssl pkcs12 -in /opt/keystore/mycoat-sbrt.p12 \
  -clcerts -nokeys -passin pass:${KEY_STORE_PWD} -out /opt/keystore/cert.pem
```

转换后的文件：

```
/opt/keystore/key.pem
/opt/keystore/cert.pem
```

Node.js HTTPS Server 可以直接加载。

---

# **4. Node.js 适配平台 context-path 的最佳模板（可直接用）**

下面是最符合你平台结构的 Node.js Express 示例：

```
const fs = require("fs");
const https = require("https");
const express = require("express");

// 平台强制注入的环境变量
const apiName = process.env.apiName;
const minorVersion = process.env.minorVersion;
const basePath = `/${apiName}/v${minorVersion}`;

const app = express();

// 业务路由全部在 router 中
const router = express.Router();

router.get("/hello", (req, res) => {
  res.json({ message: "Hello from Node.js API" });
});

// 挂载到平台强制 context-path
app.use(basePath, router);

// 加载平台强制证书
const key = fs.readFileSync("/opt/keystore/key.pem");
const cert = fs.readFileSync("/opt/keystore/cert.pem");

// 启动 HTTPS 8443
https.createServer({ key, cert }, app).listen(8443, () => {
  console.log(`Server running at https://localhost:8443${basePath}`);
});
```

---

# **5. Node.js 版本的 Kubernetes Deployment YAML 参考（含 platform adapter）**

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-node-api
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: app
          image: demo-node-api:latest
          env:
            - name: apiName
              valueFrom:
                configMapKeyRef:
                  name: mycoat-common-sprint-conf
                  key: apiName
            - name: minorVersion
              valueFrom:
                configMapKeyRef:
                  name: mycoat-common-sprint-conf
                  key: minorVersion
            - name: KEY_STORE_PWD
              valueFrom:
                secretKeyRef:
                  name: keystore-secret
                  key: password
          volumeMounts:
            - name: keystore
              mountPath: /opt/keystore
      volumes:
        - name: keystore
          secret:
            secretName: keystore-p12-secret
```

---

# **6. 健康检查 Node.js 版本（复用你的 TCP Probe）**

```
readinessProbe:
  tcpSocket:
    port: 8443
  periodSeconds: 10
  failureThreshold: 3
  timeoutSeconds: 3

livenessProbe:
  tcpSocket:
    port: 8443
  periodSeconds: 20
  failureThreshold: 3
  timeoutSeconds: 3

startupProbe:
  tcpSocket:
    port: 8443
  periodSeconds: 10
  failureThreshold: 30
```

这样 Node.js 服务 **无需实现 HTTP 健康检查**，完全与你的策略兼容。

---

# **7. 平台最小化改动总结（重点）**

| **需求**          | **Java**       | **Node.js**  | **平台需要做的事（最小化）**    |
| ----------------- | -------------- | ------------ | ------------------------------- |
| 强制 HTTPS 8443   | 内置支持       | 需要加载 PEM | **挂载相同证书 + 注入转换脚本** |
| 强制 context-path | ConfigMap 注入 | 环境变量注入 | **保持相同的键和值结构**        |
| Kong 上游 HTTPS   | 100% OK        | 100% OK      | **保持固定的 8443 监听策略**    |
| 健康检查          | TCP Probe      | TCP Probe    | **无需更改代码**                |

最终你得到的效果是：

### **✔ 所有语言（Java / Node.js / Go / Python）**

### **✔ 都可以零业务改动适配平台**

### **✔ 所有流量都是 FQDN + HTTPS + 8443**

### **✔ Kong DP 一侧不需要额外判断逻辑**

### **✔ 上游健康检查统一用 TCP Probe**

### **✔ context-path 完全由平台统一控制**

---

如果你需要，我可以进一步为你生成：

✅ 平台统一平台适配规范文档（可发团队）

✅ 平台强制 context-path 的标准说明（Java/Node.js 双版本）

✅ Node.js “最小改动”模版工程

✅ Mermaid 平台架构图补充 Node.js 路由阶段

你要我继续扩展哪部分？
