# 使用示例

## 场景 1: 基本 Spring Boot 应用扫描

### 应用结构
```
my-app/
├── src/main/java/
│   ├── SecurityConfig.java
│   └── UserController.java
├── src/main/resources/
│   └── application.yml
└── target/
    └── my-app-1.0.jar
```

### 扫描命令
```bash
# 基本扫描
java -jar auth-scanner.jar target/my-app-1.0.jar

# 包含配置扫描
java -jar auth-scanner.jar target/my-app-1.0.jar --config-path src/main/resources

# 输出详细报告
java -jar auth-scanner.jar target/my-app-1.0.jar \
  --config-path src/main/resources \
  --output security-report.json \
  --strict
```

### 预期结果
```json
{
  "jarPath": "target/my-app-1.0.jar",
  "passed": true,
  "jarComponents": [
    {
      "type": "SPRING_SECURITY_CONFIG",
      "name": "com.example.SecurityConfig",
      "found": true,
      "location": "com/example/SecurityConfig.class"
    },
    {
      "type": "AUTH_ANNOTATION",
      "name": "com.example.UserController",
      "found": true,
      "description": "包含安全注解: @PreAuthorize"
    }
  ]
}
```

## 场景 2: 微服务架构批量扫描

### 目录结构
```
microservices/
├── user-service/target/user-service.jar
├── order-service/target/order-service.jar
├── payment-service/target/payment-service.jar
└── scan-all.sh
```

### 批量扫描脚本
```bash
#!/bin/bash
# scan-all.sh

SERVICES=("user-service" "order-service" "payment-service")
SCANNER_JAR="auth-scanner.jar"
REPORT_DIR="security-reports"

mkdir -p $REPORT_DIR

for service in "${SERVICES[@]}"; do
    echo "扫描 $service..."
    
    JAR_FILE="$service/target/$service.jar"
    CONFIG_PATH="$service/src/main/resources"
    REPORT_FILE="$REPORT_DIR/$service-security-report.json"
    
    if [ -f "$JAR_FILE" ]; then
        java -jar $SCANNER_JAR "$JAR_FILE" \
            --config-path "$CONFIG_PATH" \
            --output "$REPORT_FILE" \
            --strict
        
        if [ $? -eq 0 ]; then
            echo "✅ $service 扫描通过"
        else
            echo "❌ $service 扫描失败"
            exit 1
        fi
    else
        echo "⚠️  未找到 $service 的 JAR 文件"
    fi
done

echo "所有服务扫描完成，报告保存在 $REPORT_DIR/"
```

## 场景 3: Docker 容器中扫描

### Dockerfile
```dockerfile
FROM openjdk:11-jre-slim

WORKDIR /app
COPY target/my-app.jar .
COPY src/main/resources ./config

# 运行时扫描
RUN java -jar auth-scanner.jar my-app.jar --config-path config --strict
```

### Docker Compose 集成
```yaml
version: '3.8'
services:
  app-scanner:
    image: auth-scanner:latest
    volumes:
      - ./target:/workspace/target
      - ./src/main/resources:/workspace/config
      - ./reports:/workspace/reports
    command: >
      /app/pipeline-integration.sh 
      /workspace/target/app.jar 
      /workspace/config 
      /workspace/reports 
      true
    
  app:
    image: my-app:latest
    depends_on:
      - app-scanner
    ports:
      - "8080:8080"
```

## 场景 4: 集成到 Maven 构建

### pom.xml 配置
```xml
<plugin>
    <groupId>org.codehaus.mojo</groupId>
    <artifactId>exec-maven-plugin</artifactId>
    <version>3.1.0</version>
    <executions>
        <execution>
            <id>security-scan</id>
            <phase>verify</phase>
            <goals>
                <goal>exec</goal>
            </goals>
            <configuration>
                <executable>java</executable>
                <arguments>
                    <argument>-jar</argument>
                    <argument>${project.basedir}/tools/auth-scanner.jar</argument>
                    <argument>${project.build.directory}/${project.build.finalName}.jar</argument>
                    <argument>--config-path</argument>
                    <argument>src/main/resources</argument>
                    <argument>--output</argument>
                    <argument>${project.build.directory}/security-report.json</argument>
                    <argument>--strict</argument>
                </arguments>
            </configuration>
        </execution>
    </executions>
</plugin>
```

### 运行构建
```bash
mvn clean package verify
```

## 场景 5: Gradle 集成

### build.gradle 配置
```gradle
task securityScan(type: Exec) {
    dependsOn 'bootJar'
    
    commandLine 'java', '-jar', 
                'tools/auth-scanner.jar',
                "${buildDir}/libs/${project.name}-${version}.jar",
                '--config-path', 'src/main/resources',
                '--output', "${buildDir}/reports/security-report.json",
                '--strict'
    
    doLast {
        println "安全扫描完成，报告: ${buildDir}/reports/security-report.json"
    }
}

check.dependsOn securityScan
```

## 场景 6: 持续集成中的条件扫描

### 基于分支的扫描策略
```bash
#!/bin/bash
# conditional-scan.sh

BRANCH=$(git rev-parse --abbrev-ref HEAD)
STRICT_MODE="false"

# 主分支使用严格模式
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    STRICT_MODE="true"
    echo "主分支检测，启用严格模式"
fi

# 执行扫描
java -jar auth-scanner.jar target/app.jar \
    --config-path src/main/resources \
    --output "reports/scan-$BRANCH-$(date +%Y%m%d).json" \
    $([ "$STRICT_MODE" = "true" ] && echo "--strict")
```

## 场景 7: 扫描结果分析和报告

### 生成 HTML 报告
```bash
#!/bin/bash
# generate-html-report.sh

JSON_REPORT="security-report.json"
HTML_REPORT="security-report.html"

cat > $HTML_REPORT << EOF
<!DOCTYPE html>
<html>
<head>
    <title>安全扫描报告</title>
    <style>
        .passed { color: green; }
        .failed { color: red; }
        .warning { color: orange; }
    </style>
</head>
<body>
    <h1>Java 应用安全扫描报告</h1>
EOF

# 使用 jq 解析 JSON 并生成 HTML
jq -r '
    "<h2>扫描结果: " + (if .passed then "<span class=\"passed\">通过</span>" else "<span class=\"failed\">失败</span>" end) + "</h2>",
    "<p>扫描时间: " + .scanTime + "</p>",
    "<p>JAR 文件: " + .jarPath + "</p>",
    "<h3>发现的认证组件:</h3><ul>",
    (.jarComponents[] | "<li>" + .type + ": " + .name + " (" + (if .found then "✅" else "❌" end) + ")</li>"),
    "</ul>",
    (if (.errors | length) > 0 then "<h3 class=\"failed\">错误:</h3><ul>" + (.errors[] | "<li>" + . + "</li>") + "</ul>" else "" end),
    (if (.warnings | length) > 0 then "<h3 class=\"warning\">警告:</h3><ul>" + (.warnings[] | "<li>" + . + "</li>") + "</ul>" else "" end),
    (if (.recommendations | length) > 0 then "<h3>建议:</h3><ul>" + (.recommendations[] | "<li>" + . + "</li>") + "</ul>" else "" end)
' $JSON_REPORT >> $HTML_REPORT

echo "</body></html>" >> $HTML_REPORT
echo "HTML 报告生成完成: $HTML_REPORT"
```

## 场景 8: 自动化修复建议

### 基于扫描结果的自动修复
```bash
#!/bin/bash
# auto-fix-suggestions.sh

REPORT_FILE="security-report.json"

# 检查是否缺少 Spring Security 配置
if jq -e '.errors[] | select(contains("Spring Security"))' $REPORT_FILE > /dev/null; then
    echo "检测到缺少 Spring Security 配置，生成模板..."
    
    cat > src/main/java/SecurityConfig.java << 'EOF'
@Configuration
@EnableWebSecurity
public class SecurityConfig {
    
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http.authorizeHttpRequests(authz -> authz
                .requestMatchers("/public/**").permitAll()
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(OAuth2ResourceServerConfigurer::jwt);
        return http.build();
    }
}
EOF
    
    echo "SecurityConfig.java 模板已生成"
fi

# 检查是否缺少认证注解
if jq -e '.warnings[] | select(contains("认证注解"))' $REPORT_FILE > /dev/null; then
    echo "建议在 Controller 方法上添加认证注解，例如："
    echo "@PreAuthorize(\"hasRole('USER')\")"
    echo "@Secured(\"ROLE_ADMIN\")"
fi
```

这些使用示例涵盖了从简单的单应用扫描到复杂的企业级 CI/CD 集成场景，可以根据你的具体需求选择合适的方案。