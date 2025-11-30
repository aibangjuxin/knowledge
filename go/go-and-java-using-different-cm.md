# Java 和 Golang 使用独立 ConfigMap 方案

## 1. 方案概述

### 核心思路

平台维护两个 ConfigMap：
- **Java ConfigMap**：包含 PKCS12 证书配置
- **Golang ConfigMap**：包含 PEM 证书配置

两者配置结构相同，只是证书格式不同，实现多语言统一管理。

### 优势

✅ **无需证书转换** - 各语言使用原生支持的证书格式  
✅ **部署简单** - 无需 InitContainer  
✅ **启动快速** - 无额外转换步骤  
✅ **配置清晰** - 每种语言有明确的配置  
✅ **统一管理** - 平台统一维护证书和配置  
✅ **最小改动** - 应用代码改动最小  

---

## 2. ConfigMap 设计

### 2.1 Java ConfigMap（现有）

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: ${namespace}
  name: mycoat-common-spring-conf
data:
  server-conf.properties: |
    # 强制统一端口
    server.port=8443
    # 强制开启 SSL
    server.ssl.enabled=true
    server.ssl.key-store=/opt/keystore/mycoat-sbrt.p12
    server.ssl.key-store-type=PKCS12
    server.ssl.key-store-password=${KEY_STORE_PWD}
    # 统一 Context Path (Servlet 栈)
    server.servlet.context-path=/${apiName}/v${minorVersion}
    # 统一 Base Path (WebFlux 栈)
    spring.webflux.base-path=/${apiName}/v${minorVersion}
```

### 2.2 Golang ConfigMap（新增）

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: ${namespace}
  name: mycoat-common-golang-conf
data:
  server-conf.properties: |
    # 强制统一端口
    server.port=8443
    # 强制开启 SSL
    server.ssl.enabled=true
    # Golang 使用 PEM 格式证书
    server.ssl.cert-path=/opt/keystore/tls.crt
    server.ssl.key-path=/opt/keystore/tls.key
    # 统一 Context Path
    server.context-path=/${apiName}/v${minorVersion}
```

### 2.3 配置对比

| 配置项 | Java | Golang | 说明 |
|--------|------|--------|------|
| 端口 | `server.port=8443` | `server.port=8443` | 相同 |
| SSL 开关 | `server.ssl.enabled=true` | `server.ssl.enabled=true` | 相同 |
| 证书路径 | `server.ssl.key-store` | `server.ssl.cert-path` | 不同格式 |
| 证书类型 | `PKCS12` | `PEM` | 不同格式 |
| Context Path | `server.servlet.context-path` | `server.context-path` | 简化命名 |

---

## 3. Secret 设计

### 3.1 Java Secret（现有）

```yaml
apiVersion: v1
kind: Secret
metadata:
  namespace: ${namespace}
  name: mycoat-keystore-java
type: Opaque
data:
  mycoat-sbrt.p12: <base64-encoded-pkcs12>
  password: <base64-encoded-password>
```

### 3.2 Golang Secret（新增）

```yaml
apiVersion: v1
kind: Secret
metadata:
  namespace: ${namespace}
  name: mycoat-keystore-golang
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-certificate>
  tls.key: <base64-encoded-private-key>
```

### 3.3 统一 Secret（推荐）

如果想统一管理，可以在一个 Secret 中同时包含两种格式：

```yaml
apiVersion: v1
kind: Secret
metadata:
  namespace: ${namespace}
  name: mycoat-keystore-unified
type: Opaque
data:
  # Java 使用
  mycoat-sbrt.p12: <base64-encoded-pkcs12>
  password: <base64-encoded-password>
  # Golang 使用
  tls.crt: <base64-encoded-certificate>
  tls.key: <base64-encoded-private-key>
```

---

## 4. Golang 配置加载器（简化版）

由于 ConfigMap 已经适配 Golang，配置加载器更简单：

```go
package config

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// PlatformConfig 平台统一配置
type PlatformConfig struct {
	Port        string // 服务端口
	SSLEnabled  bool   // 是否启用 SSL
	CertPath    string // TLS 证书路径
	KeyPath     string // TLS 私钥路径
	ContextPath string // Context Path
}

// LoadPlatformConfig 从平台注入的配置文件加载配置
func LoadPlatformConfig() (*PlatformConfig, error) {
	configPath := os.Getenv("PLATFORM_CONFIG_PATH")
	if configPath == "" {
		configPath = "/opt/config/server-conf.properties"
	}

	props, err := loadProperties(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %w", err)
	}

	cfg := &PlatformConfig{
		Port:        getProperty(props, "server.port", "8443"),
		SSLEnabled:  getProperty(props, "server.ssl.enabled", "true") == "true",
		CertPath:    getProperty(props, "server.ssl.cert-path", "/opt/keystore/tls.crt"),
		KeyPath:     getProperty(props, "server.ssl.key-path", "/opt/keystore/tls.key"),
		ContextPath: getProperty(props, "server.context-path", "/"),
	}

	// 替换环境变量占位符
	cfg.ContextPath = expandEnvVars(cfg.ContextPath)

	return cfg, nil
}

// loadProperties 读取 properties 文件
func loadProperties(path string) (map[string]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	props := make(map[string]string)
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			value := strings.TrimSpace(parts[1])
			props[key] = value
		}
	}

	return props, scanner.Err()
}

// getProperty 获取配置值
func getProperty(props map[string]string, key, defaultValue string) string {
	if value, ok := props[key]; ok {
		return value
	}
	return defaultValue
}

// expandEnvVars 替换环境变量占位符
func expandEnvVars(s string) string {
	result := s
	for {
		start := strings.Index(result, "${")
		if start == -1 {
			break
		}
		end := strings.Index(result[start:], "}")
		if end == -1 {
			break
		}
		end += start
		varName := result[start+2 : end]
		varValue := os.Getenv(varName)
		result = result[:start] + varValue + result[end+1:]
	}
	return result
}

// Validate 验证配置
func (c *PlatformConfig) Validate() error {
	if c.Port == "" {
		return fmt.Errorf("port is required")
	}
	if c.SSLEnabled {
		if c.CertPath == "" {
			return fmt.Errorf("cert path is required when SSL is enabled")
		}
		if c.KeyPath == "" {
			return fmt.Errorf("key path is required when SSL is enabled")
		}
		if _, err := os.Stat(c.CertPath); os.IsNotExist(err) {
			return fmt.Errorf("cert file not found: %s", c.CertPath)
		}
		if _, err := os.Stat(c.KeyPath); os.IsNotExist(err) {
			return fmt.Errorf("key file not found: %s", c.KeyPath)
		}
	}
	return nil
}

// String 返回配置的字符串表示
func (c *PlatformConfig) String() string {
	return fmt.Sprintf(
		"PlatformConfig{Port:%s, SSL:%v, ContextPath:%s, CertPath:%s, KeyPath:%s}",
		c.Port, c.SSLEnabled, c.ContextPath, c.CertPath, c.KeyPath,
	)
}
```

---

## 5. 部署配置

### 5.1 Java Deployment（现有）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-app
  namespace: ${namespace}
spec:
  template:
    spec:
      containers:
      - name: app
        image: java-app:latest
        env:
        - name: KEY_STORE_PWD
          valueFrom:
            secretKeyRef:
              name: mycoat-keystore-unified
              key: password
        - name: apiName
          value: "user-service"
        - name: minorVersion
          value: "1"
        volumeMounts:
        - name: config
          mountPath: /opt/config
          readOnly: true
        - name: keystore
          mountPath: /opt/keystore
          readOnly: true
        ports:
        - containerPort: 8443
      volumes:
      - name: config
        configMap:
          name: mycoat-common-spring-conf  # Java ConfigMap
      - name: keystore
        secret:
          secretName: mycoat-keystore-unified
          items:
          - key: mycoat-sbrt.p12
            path: mycoat-sbrt.p12
```

### 5.2 Golang Deployment（新增）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: golang-app
  namespace: ${namespace}
spec:
  template:
    spec:
      containers:
      - name: app
        image: golang-app:latest
        env:
        - name: apiName
          value: "user-service"
        - name: minorVersion
          value: "1"
        volumeMounts:
        - name: config
          mountPath: /opt/config
          readOnly: true
        - name: keystore
          mountPath: /opt/keystore
          readOnly: true
        ports:
        - containerPort: 8443
        readinessProbe:
          httpGet:
            path: /${apiName}/v${minorVersion}/health
            port: 8443
            scheme: HTTPS
          initialDelaySeconds: 10
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: mycoat-common-golang-conf  # Golang ConfigMap
      - name: keystore
        secret:
          secretName: mycoat-keystore-unified
          items:
          - key: tls.crt
            path: tls.crt
          - key: tls.key
            path: tls.key
```

---

## 6. 平台管理流程

### 6.1 证书生成和管理

```bash
#!/bin/bash
# 平台证书管理脚本

NAMESPACE="your-namespace"
CERT_NAME="mycoat-sbrt"

# 1. 生成证书（如果还没有）
if [ ! -f "${CERT_NAME}.crt" ]; then
    echo "Generating certificate..."
    openssl req -x509 -newkey rsa:4096 \
        -keyout ${CERT_NAME}.key \
        -out ${CERT_NAME}.crt \
        -days 365 -nodes \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=MyCoat/CN=*.example.com"
fi

# 2. 生成 PKCS12 格式（Java 使用）
echo "Creating PKCS12 keystore..."
openssl pkcs12 -export \
    -in ${CERT_NAME}.crt \
    -inkey ${CERT_NAME}.key \
    -out ${CERT_NAME}.p12 \
    -name ${CERT_NAME} \
    -passout pass:${KEY_STORE_PWD}

# 3. 创建统一 Secret
echo "Creating unified secret..."
kubectl create secret generic mycoat-keystore-unified \
    --namespace=${NAMESPACE} \
    --from-file=mycoat-sbrt.p12=${CERT_NAME}.p12 \
    --from-file=tls.crt=${CERT_NAME}.crt \
    --from-file=tls.key=${CERT_NAME}.key \
    --from-literal=password=${KEY_STORE_PWD} \
    --dry-run=client -o yaml | kubectl apply -f -

echo "Certificate setup completed!"
```

### 6.2 ConfigMap 管理

```bash
#!/bin/bash
# 平台 ConfigMap 管理脚本

NAMESPACE="your-namespace"

# 创建 Java ConfigMap
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: ${NAMESPACE}
  name: mycoat-common-spring-conf
data:
  server-conf.properties: |
    server.port=8443
    server.ssl.enabled=true
    server.ssl.key-store=/opt/keystore/mycoat-sbrt.p12
    server.ssl.key-store-type=PKCS12
    server.ssl.key-store-password=\${KEY_STORE_PWD}
    server.servlet.context-path=/\${apiName}/v\${minorVersion}
    spring.webflux.base-path=/\${apiName}/v\${minorVersion}
EOF

# 创建 Golang ConfigMap
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: ${NAMESPACE}
  name: mycoat-common-golang-conf
data:
  server-conf.properties: |
    server.port=8443
    server.ssl.enabled=true
    server.ssl.cert-path=/opt/keystore/tls.crt
    server.ssl.key-path=/opt/keystore/tls.key
    server.context-path=/\${apiName}/v\${minorVersion}
EOF

echo "ConfigMaps created successfully!"
```

---

## 7. 应用开发者使用指南

### 7.1 Golang 应用集成（3 步）

#### 步骤 1：复制配置加载器

```bash
mkdir -p pkg/config
cp golang-config-loader-simple.go pkg/config/platform_config.go
```

#### 步骤 2：修改 main.go

```go
package main

import (
    "log"
    "your-project/pkg/config"
    "github.com/gin-gonic/gin"
)

func main() {
    // 加载平台配置
    cfg, err := config.LoadPlatformConfig()
    if err != nil {
        log.Fatalf("Failed to load config: %v", err)
    }

    if err := cfg.Validate(); err != nil {
        log.Fatalf("Invalid config: %v", err)
    }

    log.Printf("Starting with config: %s", cfg.String())

    r := gin.Default()
    
    // 使用 Context Path
    api := r.Group(cfg.ContextPath)
    {
        api.GET("/health", func(c *gin.Context) {
            c.JSON(200, gin.H{"status": "ok"})
        })
        // 其他路由...
    }

    // 启动服务
    addr := ":" + cfg.Port
    if cfg.SSLEnabled {
        log.Fatal(r.RunTLS(addr, cfg.CertPath, cfg.KeyPath))
    } else {
        log.Fatal(r.Run(addr))
    }
}
```

#### 步骤 3：部署

```bash
# 构建镜像
docker build -t your-registry/golang-app:latest .

# 部署（使用 Golang ConfigMap）
kubectl apply -f deployment-golang.yaml
```

### 7.2 Java 应用（无需改动）

Java 应用继续使用现有配置，无需任何改动。

---

## 8. 方案对比

### 8.1 与 InitContainer 方案对比

| 项目 | 独立 ConfigMap 方案 | InitContainer 方案 |
|------|-------------------|-------------------|
| 证书转换 | ❌ 不需要 | ✅ 需要 |
| 启动速度 | ⚡ 快（~1s） | 🐢 慢（~3-4s） |
| 配置复杂度 | 🟢 简单 | 🟡 中等 |
| 平台维护 | 🟡 两套 ConfigMap | 🟢 一套 ConfigMap |
| 证书管理 | 🟡 两种格式 | 🟢 一种格式 |
| 部署配置 | 🟢 简单 | 🟡 需要 InitContainer |
| 故障排查 | 🟢 容易 | 🟡 稍复杂 |
| **推荐度** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |

### 8.2 优缺点总结

#### 独立 ConfigMap 方案

**优点**：
- ✅ 部署最简单
- ✅ 启动最快速
- ✅ 配置最清晰
- ✅ 故障排查容易
- ✅ 无需额外组件

**缺点**：
- ⚠️ 平台需维护两套 ConfigMap
- ⚠️ 证书需要两种格式
- ⚠️ 配置变更需要同步

**适用场景**：
- 长期方案
- 追求性能和简单性
- 平台有能力统一管理

---

## 9. 平台实施计划

### 9.1 准备阶段（1 周）

**任务**：
1. 创建 Golang ConfigMap 模板
2. 准备证书生成脚本
3. 更新部署文档

**交付物**：
- ✅ ConfigMap YAML 模板
- ✅ 证书管理脚本
- ✅ 开发者文档

### 9.2 试点阶段（2 周）

**任务**：
1. 选择 1-2 个 Golang 应用试点
2. 部署并验证
3. 收集反馈

**成功标准**：
- ✅ 应用成功部署
- ✅ HTTPS 正常工作
- ✅ Context Path 生效
- ✅ 开发者满意度 > 90%

### 9.3 推广阶段（1 个月）

**任务**：
1. 推广到所有 Golang 应用
2. 提供技术支持
3. 优化文档和工具

**成功标准**：
- ✅ 所有 Golang 应用迁移完成
- ✅ 零生产事故
- ✅ 配置统一率 100%

---

## 10. 运维管理

### 10.1 证书轮换

```bash
#!/bin/bash
# 证书轮换脚本

NAMESPACE="your-namespace"

# 1. 生成新证书
./generate-new-cert.sh

# 2. 更新 Secret
kubectl create secret generic mycoat-keystore-unified \
    --namespace=${NAMESPACE} \
    --from-file=mycoat-sbrt.p12=new-cert.p12 \
    --from-file=tls.crt=new-cert.crt \
    --from-file=tls.key=new-cert.key \
    --from-literal=password=${NEW_PWD} \
    --dry-run=client -o yaml | kubectl apply -f -

# 3. 滚动重启应用
kubectl rollout restart deployment -n ${NAMESPACE} -l app=java-app
kubectl rollout restart deployment -n ${NAMESPACE} -l app=golang-app

echo "Certificate rotation completed!"
```

### 10.2 配置更新

```bash
#!/bin/bash
# ConfigMap 更新脚本

NAMESPACE="your-namespace"

# 更新 Java ConfigMap
kubectl apply -f java-configmap.yaml

# 更新 Golang ConfigMap
kubectl apply -f golang-configmap.yaml

# 滚动重启（如果需要）
kubectl rollout restart deployment -n ${NAMESPACE} -l language=java
kubectl rollout restart deployment -n ${NAMESPACE} -l language=golang
```

### 10.3 监控和告警

```yaml
# Prometheus 监控规则
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: configmap-monitoring
spec:
  groups:
  - name: configmap-alerts
    rules:
    - alert: ConfigMapMissing
      expr: |
        kube_configmap_info{configmap=~"mycoat-common-(spring|golang)-conf"} == 0
      for: 5m
      annotations:
        summary: "ConfigMap missing"
        description: "Platform ConfigMap is missing in namespace {{ $labels.namespace }}"
    
    - alert: CertificateExpiring
      expr: |
        (cert_expiry_timestamp - time()) / 86400 < 30
      annotations:
        summary: "Certificate expiring soon"
        description: "Certificate will expire in {{ $value }} days"
```

---

## 11. 常见问题

### Q1: 为什么不用一个 ConfigMap？

**A**: 虽然可以在一个 ConfigMap 中包含两种配置，但分开更清晰：
- 各语言配置独立，互不影响
- 更新时不会误改其他语言配置
- 便于权限管理和审计

### Q2: 证书需要分别管理吗？

**A**: 不需要。推荐使用统一 Secret 包含两种格式，平台统一管理。

### Q3: 如何确保两个 ConfigMap 配置一致？

**A**: 使用脚本或 GitOps 工具统一管理：
```bash
# 使用模板生成
envsubst < configmap-template.yaml | kubectl apply -f -
```

### Q4: 性能有差异吗？

**A**: 独立 ConfigMap 方案性能最优：
- 无证书转换开销
- 启动时间最短
- 资源消耗最小

### Q5: 如何迁移现有应用？

**A**: 渐进式迁移：
1. 创建 Golang ConfigMap
2. 更新应用代码（3 步）
3. 更新 Deployment 配置
4. 灰度发布验证
5. 全量上线

---

## 12. 总结

### 核心优势

1. **最简单** - 无需证书转换，部署配置最简单
2. **最快速** - 启动时间最短，性能最优
3. **最清晰** - 各语言配置独立，易于理解和维护
4. **最可靠** - 无额外组件，故障点最少

### 推荐理由

✅ **适合长期使用** - 架构清晰，易于维护  
✅ **适合大规模** - 性能优秀，资源消耗低  
✅ **适合多语言** - 易于扩展到 Node.js、Python 等  
✅ **适合平台化** - 统一管理，标准化部署  

### 实施建议

1. **短期**：使用独立 ConfigMap 方案快速上线
2. **中期**：优化证书管理流程，实现自动化
3. **长期**：扩展到更多语言，建立统一配置平台

---

**文档版本**：v1.0  
**更新日期**：2025-11-30  
**维护团队**：平台工程团队  
**推荐度**：⭐⭐⭐⭐⭐
