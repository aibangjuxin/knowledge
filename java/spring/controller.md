# 理解 Spring Boot Controller：为 Kubernetes 健康检查创建 HTTP 端点

本文档旨在为不熟悉 Java 或 Spring Boot 的技术人员（如运维、SRE）解释一个核心概念：**Controller**。并提供一个标准的健康检查（Health Check）代码范例，以解决 Kubernetes Probe 因找不到对应 URL 而失败的问题。

## 问题背景

在 GKE/Kubernetes 中，我们通常会为应用配置健康检查（Liveness/Readiness Probes），例如，让 Kubelet 定期请求一个特定的 URL `http://<pod-ip>:<port>/.well-known/health`。

如果应用代码中没有处理 `/.well-known/health` 这个路径的逻辑，Kubernetes 的请求就会收到 `404 Not Found` 错误，最终导致 Pod 被判定为不健康并被不断重启。

**解决方案**：在 Java Spring Boot 应用中添加一个 `Controller` 来响应该路径的请求。

---

## 什么是 Controller？

你可以把 `Controller` 想象成一个**交通警察**或**前台接待员**。它的唯一职责就是：

1.  **监听特定的 URL 地址**（例如 `/.well-known/health`）。
2.  当一个 HTTP 请求到达这个地址时，**触发指定的 Java 代码**（一个方法）。
3.  将代码的执行结果**返回给请求方**（例如，返回一个表示“服务正常”的 JSON）。

在 Spring Boot 中，我们通过编写一个 Java 类并使用特殊的“注解”（Annotations，以 `@` 开头）来定义一个 Controller。

### 关键注解 (Annotations)

| 注解 | 作用 |
| :--- | :--- |
| `@RestController` | 声明这个 Java 类是一个专门处理 HTTP 请求并直接返回数据的控制器。 |
| `@GetMapping("/path")` | 将一个方法映射到 HTTP GET 请求的指定路径上。这是最常用的注解之一。 |
| `@PostMapping("/path")`| 将一个方法映射到 HTTP POST 请求的指定路径上。 |

---

## 范例：创建一个标准的健康检查 Controller

假设 Kubernetes 的 Probe 配置要求应用必须在 `/.well-known/health` 路径上返回一个 `200 OK` 响应。我们可以创建一个 `WellKnownController.java` 文件来实现这个需求。

### 代码示例

这是一个完整、可直接使用的 Java 代码文件。

**文件名:** `WellKnownController.java`

```java
package com.example.app.controllers; // 包名根据你的项目结构调整

import java.util.Collections;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 这个 Controller 专门用于处理 Kubernetes 的健康检查请求。
 * @RestController 注解告诉 Spring 这是一个处理 Web 请求的组件。
 */
@RestController
public class WellKnownController {

    /**
     * @GetMapping 注解将这个方法绑定到 HTTP GET "/.well-known/health" 路径。
     * 当 Kubernetes 访问这个 URL 时，下面的代码将被执行。
     * @return 返回一个 HTTP 200 OK 响应，内容为 JSON 格式的 {"status":"UP"}。
     */
    @GetMapping("/.well-known/health")
    public ResponseEntity<Map<String, String>> getHealthStatus() {
        // Collections.singletonMap 是一个快速创建只有一个键值对的 Map 的方法。
        Map<String, String> responseBody = Collections.singletonMap("status", "UP");
        
        // ResponseEntity.ok() 会创建一个状态码为 200 的 HTTP 响应。
        // Spring Boot 会自动将 Map 对象转换为 JSON 字符串。
        return ResponseEntity.ok(responseBody);
    }
}
```

### 代码如何工作？

1.  **`@RestController`**：Spring 在启动时扫描代码，发现这个注解，就知道 `WellKnownController` 类是用来处理 HTTP 请求的。
2.  **`@GetMapping("/.well-known/health")`**：Spring 继续扫描，发现这个注解，于是将 `getHealthStatus()` 方法与 `GET /.well-known/health` 这个具体的请求路径绑定起来。
3.  **执行流程**：
    *   Kubernetes 发送 `GET` 请求到 `http://<pod-ip>:<port>/.well-known/health`。
    *   Spring Boot 应用接收到请求，根据路径找到了 `getHealthStatus()` 方法。
    *   方法执行，创建一个包含 `{"status":"UP"}` 的 Map。
    *   `ResponseEntity.ok()` 将这个 Map 包装成一个 HTTP `200 OK` 响应，并自动将其序列化为 JSON 格式的响应体。
    *   Kubernetes 收到 `200 OK` 响应，认为 Pod 是健康的。

### 文件应该放在哪里？

在标准的 Java 项目结构中，这个文件通常放在 `src/main/java` 下的一个 `controllers` 子包中，例如：

```
src
└── main
    └── java
        └── com
            └── example
                └── app
                    ├── Application.java      (主启动类)
                    └── controllers
                        └── WellKnownController.java (我们的文件)
```

通过添加这个简单的 Controller，你的 Java 应用就具备了响应 Kubernetes 健康检查的能力，从而确保了部署的稳定性和可靠性。

---

## 问题排查：@RequestMapping 使用属性占位符导致启动失败

### 问题描述

当在 `MainController` 的 `@RequestMapping` 注解中使用属性占位符（如 `@RequestMapping("$(abjx.rest.base-path)")` ）时，Spring Boot 应用启动失败。删除该注解行后，API 正常启动。

### 根本原因分析

#### 1. **属性占位符语法错误**

在 Spring Boot 中，属性占位符应该使用 `${...}` 语法，而非 `$(...)`。

```java
// ❌ 错误：使用了错误的占位符语法
@RequestMapping("$(abjx.rest.base-path)")
public class MainController { ... }

// ✅ 正确：使用正确的 Spring 占位符语法
@RequestMapping("${abjx.rest.base-path}")
public class MainController { ... }
```

#### 2. **属性未定义**

Even with correct syntax，如果配置文件中未定义 `abjx.rest.base-path` 属性，Spring 启动时可能会失败（取决于配置和 Spring 版本）。

#### 3. **类级别 @RequestMapping 的作用**

类级别的 `@RequestMapping` 会为该类中的所有方法作为前缀。例如：

```java
@RestController
@RequestMapping("/api/v1")
public class MainController {
    @GetMapping("/users")
    public ResponseEntity<?> getUsers() { ... }  // 实际路径：/api/v1/users
}
```

### 解决方案

#### 方案 1：修正属性占位符语法

确保在 `application.properties` 或 `application.yml` 中定义了该属性：

**application.properties:**
```properties
abjx.rest.base-path=/api/v1
```

**MainController.java:**
```java
@RestController
@RequestMapping("${abjx.rest.base-path}")
public class MainController {
    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> getHealth() {
        return ResponseEntity.ok(Collections.singletonMap("status", "UP"));
    }
}
```

#### 方案 2：使用环境变量

如果属性来自环境变量或系统属性，可以使用带默认值的占位符：

```java
@RequestMapping("${abjx.rest.base-path:/api}")
public class MainController { ... }
```

这样即使属性未定义，也会使用默认值 `/api`。

#### 方案 3：在方法级别定义路径

如果不需要类级别的前缀，可以在具体方法上定义路由：

```java
@RestController
public class MainController {
    @GetMapping("${abjx.rest.base-path}/health")
    public ResponseEntity<Map<String, String>> getHealth() {
        return ResponseEntity.ok(Collections.singletonMap("status", "UP"));
    }
}
```

### 调试技巧

1. **检查应用日志**：查看 Spring 启动失败的具体错误信息，通常会显示属性解析失败或占位符不匹配的错误。

2. **验证配置文件**：确保 `application.properties` 或 `application.yml` 包含所需的属性定义。

3. **使用 Spring Boot Actuator**：添加依赖查看当前所有配置：
   ```xml
   <dependency>
       <groupId>org.springframework.boot</groupId>
       <artifactId>spring-boot-starter-actuator</artifactId>
   </dependency>
   ```
   访问 `http://localhost:8080/actuator/configprops` 查看所有属性。

4. **临时禁用占位符**：为了快速验证，可以使用硬编码的路径，确认 Controller 本身没有其他问题：
   ```java
   @RequestMapping("/api/v1")
   public class MainController { ... }
   ```
