# Java 应用认证扫描工具

## 概述

这是一个专门为从 Kong Gateway 迁移到应用自主认证而设计的扫描工具。它可以分析 Java 应用的 JAR 包和配置文件，确保应用包含必要的认证逻辑。

## 功能特性

- **静态代码分析**: 使用 ASM 分析字节码，检测 Spring Security 配置和认证注解
- **配置文件扫描**: 分析 application.yml/properties 中的安全配置
- **CI/CD 集成**: 提供 GitLab CI、Jenkins Pipeline 等集成示例
- **容器化支持**: Docker 镜像和 Kubernetes Job 支持
- **详细报告**: JSON 格式的扫描报告，包含错误、警告和建议

## 快速开始

### 1. 构建扫描器

```bash
mvn clean package
```

### 2. 运行扫描

```bash
# 基本扫描
java -jar target/auth-scanner.jar your-app.jar

# 包含配置文件扫描
java -jar target/auth-scanner.jar your-app.jar --config-path src/main/resources

# 严格模式（所有检查项都必须通过）
java -jar target/auth-scanner.jar your-app.jar --strict

# 输出到文件
java -jar target/auth-scanner.jar your-app.jar --output scan-report.json
```

### 3. 使用 Docker

```bash
# 构建镜像
docker build -t auth-scanner -f docker/Dockerfile .

# 运行扫描
docker run --rm -v $(pwd):/workspace auth-scanner /workspace/your-app.jar
```

## 扫描检查项

### 必需组件
- ✅ Spring Security 配置类
- ✅ 安全相关依赖
- ✅ 认证注解（@PreAuthorize, @Secured 等）

### 可选组件
- JWT 处理器
- OAuth2 配置
- 自定义认证过滤器
- 端点安全配置

### 配置检查
- Spring Security 属性
- JWT 相关配置
- OAuth2 设置

## CI/CD 集成

### GitLab CI

```yaml
auth-scan:
  stage: security-scan
  image: your-registry/auth-scanner:latest
  script:
    - /app/pipeline-integration.sh target/app.jar src/main/resources reports true
  artifacts:
    reports:
      security: reports/auth-scan-report-*.json
```

### Jenkins Pipeline

```groovy
stage('Security Scan') {
    steps {
        sh 'docker run --rm -v $(pwd):/workspace auth-scanner /workspace/target/app.jar'
    }
}
```

## 扫描报告示例

```json
{
  "jarPath": "/path/to/app.jar",
  "passed": true,
  "scanTime": "2025-01-15T10:30:00",
  "jarComponents": [
    {
      "type": "SPRING_SECURITY_CONFIG",
      "name": "com.example.SecurityConfig",
      "found": true,
      "location": "com/example/SecurityConfig.class"
    }
  ],
  "errors": [],
  "warnings": ["未发现 JWT 支持"],
  "recommendations": ["添加 JWT 处理器和相关配置"]
}
```

## 自定义扫描规则

你可以通过修改以下类来自定义扫描规则：

- `JarAnalyzer`: 修改要检测的类和注解
- `ConfigAnalyzer`: 添加新的配置属性检查
- `AuthValidator`: 调整验证逻辑和严格程度

## 最佳实践

1. **在构建阶段集成**: 尽早发现认证逻辑缺失
2. **使用严格模式**: 对生产环境使用严格检查
3. **定期更新规则**: 根据安全要求更新扫描规则
4. **结合其他工具**: 与 SAST、依赖扫描等工具配合使用

## 故障排除

### 常见问题

1. **扫描失败**: 检查 JAR 文件路径和权限
2. **误报**: 调整扫描规则或使用非严格模式
3. **性能问题**: 对大型应用可能需要增加内存

### 调试选项

```bash
# 启用详细日志
java -Dorg.slf4j.simpleLogger.defaultLogLevel=debug -jar auth-scanner.jar app.jar
```

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个工具。

## 许可证

MIT License