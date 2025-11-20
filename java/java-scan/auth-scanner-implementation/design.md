# Java API 认证合规扫描器设计方案

## 1. 核心问题分析

用户需要在 **CI (构建)** 之后，**CD (部署)** 之前，对生成的 JAR 包进行认证合规性检查。
核心约束是：**不能启动用户的 API 应用**。

因此，必须采用 **静态应用程序安全测试 (SAST)** 的方法，直接分析编译后的字节码 (Bytecode)，而不是通过发送 HTTP 请求的动态测试 (DAST)。

## 2. 扫描流程设计

我们将扫描步骤插入到 CI/CD 流水线的 "Build" 和 "Deploy" 之间。

### 推荐流水线 (Pipeline)

1.  **Build Stage (CI)**:
    *   编译代码
    *   运行单元测试
    *   打包生成 `app.jar`
2.  **Scan Stage (New)**:
    *   **执行 Auth Scanner**: `java -jar auth-scanner.jar --target ./target/app.jar`
    *   **输入**: 上一步生成的 `app.jar`
    *   **动作**: 扫描器加载 `app.jar`，使用 ASM 解析 Class 文件，检查认证注解和配置。
    *   **输出**: 生成 `scan-report.json`。
    *   **判定**: 如果发现高危合规问题（如公开接口未加锁），返回非零退出码，**阻断流程**。
3.  **Package/Deploy Stage (CD)**:
    *   (仅当 Scan Stage 通过时执行)
    *   构建 Docker 镜像
    *   部署到 Kubernetes/环境

此流程完全满足 "不启动用户 API" 的要求，且能拿到详细报告。

## 3. 扫描器技术架构

### 3.1 核心技术
*   **ASM / Javassist**: 用于读取 JAR 包中的 `.class` 文件，无需 JVM 加载类（避免执行静态代码块）。
*   **Spring 框架元数据分析**: 识别 `@RestController`, `@GetMapping`, `@PreAuthorize` 等注解。

### 3.2 检查规则 (Rules)

扫描器将执行以下检查：

1.  **全局安全配置检查**:
    *   是否存在 `@EnableWebSecurity` 或继承 `WebSecurityConfigurerAdapter` (旧版) / 定义 `SecurityFilterChain` Bean (新版)。
    *   如果完全没有安全配置，视为 **高危**。

2.  **端点安全检查**:
    *   扫描所有 `@RestController` 和 `@Controller`。
    *   遍历所有映射方法 (`@RequestMapping`, `@GetMapping` 等)。
    *   **合规标准**:
        *   方法或类上必须有认证注解: `@PreAuthorize`, `@Secured`, `@RolesAllowed`。
        *   或者，存在自定义的 `@Public` / `@Anonymous` 注解（明确标记为公开）。
    *   **违规**: 既没有认证注解，也没有明确的公开标记。

### 3.3 报告格式

JSON 格式，便于 CI 工具解析：

```json
{
  "status": "FAILED",
  "scan_time": "2023-10-27T10:00:00Z",
  "issues": [
    {
      "severity": "HIGH",
      "class": "com.example.UserController",
      "method": "getUserById",
      "message": "API endpoint /users/{id} has no authentication annotation."
    }
  ]
}
```

## 4. 目录结构

我们将开发一个独立的扫描工具 `auth-scanner`。

```
auth-scanner-implementation/
├── pom.xml                 # Maven 依赖 (ASM, Commons-IO)
├── src/main/java/
│   └── com/aibang/scanner/
│       ├── Main.java       # 入口
│       ├── core/           # 核心分析逻辑
│       │   ├── JarScanner.java
│       │   └── ClassAnalyzer.java
│       └── model/          # 报告模型
└── README.md
```

## 5. 实施计划

1.  创建 Maven 项目结构。
2.  引入 `org.ow2.asm:asm` 依赖。
3.  实现 `JarScanner`: 解压并遍历 JAR。
4.  实现 `ClassAnalyzer`: 解析类和方法上的注解。
5.  编写 Main 函数处理命令行参数。
