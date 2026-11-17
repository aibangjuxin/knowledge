# Java 依赖问题排查清单

## 快速判断：是用户问题还是平台问题？

### 决策树

```
错误发生在哪个阶段？
│
├─ Maven compile/package 阶段
│  └─ 用户责任（CI 构建配置）
│     - pom.xml 依赖配置
│     - settings.xml 仓库配置
│     - 网络/Nexus 访问
│
├─ Dockerfile COPY 阶段
│  ├─ JAR 不存在 → 用户责任（Maven 构建失败）
│  └─ COPY 路径错误 → 平台责任
│
└─ 容器运行时
   ├─ ClassNotFoundException → 检查依赖 scope
   └─ 系统库缺失 → 平台责任
```

## 用户层面问题排查清单

### ✅ 依赖配置检查

- [ ] pom.xml 中是否声明了该依赖？
  ```bash
  grep -i "wiremock" pom.xml
  ```

- [ ] 依赖 scope 是否正确？
  ```xml
  <!-- 如果在 src/main 中使用，不能是 test -->
  <scope>compile</scope>  <!-- 或移除 scope -->
  ```

- [ ] 依赖版本是否明确？
  ```xml
  <version>2.35.0</version>  <!-- 避免使用 LATEST -->
  ```

- [ ] 是否存在版本冲突？
  ```bash
  mvn dependency:tree -Dverbose | grep -i "omitted for conflict"
  ```

### ✅ 环境对比检查

- [ ] Maven 版本一致？
  ```bash
  # 本地
  mvn -v
  # CI（在 Pipeline 中）
  mvn -v
  ```

- [ ] JDK 版本一致？
  ```bash
  java -version
  ```

- [ ] settings.xml 配置存在且正确？
  ```bash
  # 本地
  cat ~/.m2/settings.xml
  # CI
  cat $HOME/.m2/settings.xml
  mvn help:effective-settings
  ```

- [ ] 网络连接正常？
  ```bash
  curl -I "https://repo1.maven.org/maven2/"
  curl -I "https://your-nexus.com/repository/maven-public/"
  ```

### ✅ 仓库配置检查

- [ ] Nexus 仓库可访问？
  ```bash
  curl -I "https://your-nexus.com/repository/maven-public/"
  ```

- [ ] Nexus 中存在该依赖？
  ```bash
  curl -I "https://your-nexus.com/repository/maven-public/com/github/tomakehurst/wiremock-jre8/2.35.0/wiremock-jre8-2.35.0.jar"
  ```

- [ ] 认证信息正确？
  ```xml
  <servers>
    <server>
      <id>nexus</id>
      <username>${env.NEXUS_USER}</username>
      <password>${env.NEXUS_PASSWORD}</password>
    </server>
  </servers>
  ```

- [ ] 代理配置正确？
  ```xml
  <proxies>
    <proxy>
      <active>true</active>
      <protocol>https</protocol>
      <host>proxy.company.com</host>
      <port>8080</port>
    </proxy>
  </proxies>
  ```

### ✅ CI 环境检查

- [ ] settings.xml 正确加载？
  ```bash
  mvn help:effective-settings
  ```

- [ ] 环境变量配置正确？
  ```bash
  env | grep -i maven
  ```

- [ ] 缓存策略合理？
  ```yaml
  cache:
    paths:
      - .m2/repository/
  ```

- [ ] 依赖树完整？
  ```bash
  mvn dependency:tree | grep -i wiremock
  ```

### ✅ 调试验证

- [ ] 使用 -X 查看详细日志
  ```bash
  mvn clean package -X 2>&1 | tee build.log
  ```

- [ ] 查看依赖树
  ```bash
  mvn dependency:tree -Dverbose
  ```

- [ ] 查看实际配置
  ```bash
  mvn help:effective-settings
  mvn help:effective-pom
  ```

- [ ] 手动下载依赖验证网络
  ```bash
  mvn dependency:get -Dartifact=com.github.tomakehurst:wiremock-jre8:2.35.0
  ```

## 平台层面问题排查清单

### ✅ Dockerfile 检查

- [ ] 基础镜像正确？
  ```dockerfile
  FROM openjdk:11-jre-slim  # 版本固定
  ```

- [ ] COPY 路径正确？
  ```dockerfile
  COPY target/*.jar /opt/apps/app.jar
  ```

- [ ] 运行时环境完整？
  ```dockerfile
  # JRE 版本与编译版本兼容
  ```

### ✅ 运行时检查

- [ ] 容器启动命令正确？
  ```dockerfile
  ENTRYPOINT ["java", "-jar", "/opt/apps/app.jar"]
  ```

- [ ] 系统依赖完整？
  ```bash
  # 检查容器内系统库
  ldd /usr/bin/java
  ```

## 常见错误模式

### 错误 1: package does not exist

**判定：** 用户层面问题

**原因：**
- pom.xml 缺少依赖声明
- 依赖 scope 错误
- settings.xml 配置问题

**解决：**
```xml
<dependency>
    <groupId>com.github.tomakehurst</groupId>
    <artifactId>wiremock-jre8</artifactId>
    <version>2.35.0</version>
    <scope>compile</scope>
</dependency>
```

### 错误 2: Could not transfer artifact

**判定：** 用户层面问题

**原因：**
- 网络无法访问仓库
- Nexus 认证失败
- 代理配置错误

**解决：**
```xml
<!-- settings.xml -->
<mirrors>
    <mirror>
        <id>nexus</id>
        <mirrorOf>*</mirrorOf>
        <url>https://your-nexus.com/repository/maven-public/</url>
    </mirror>
</mirrors>
```

### 错误 3: COPY failed: no source files

**判定：** 用户层面问题（Maven 构建失败）

**原因：**
- Maven 构建未成功
- JAR 输出路径不是 target/

**解决：**
- 检查 Maven 构建日志
- 确认 JAR 生成位置

### 错误 4: ClassNotFoundException (运行时)

**判定：** 用户层面问题

**原因：**
- 依赖 scope=test，但运行时需要
- 依赖未打包到 JAR

**解决：**
```xml
<!-- 修改 scope -->
<dependency>
    <groupId>com.github.tomakehurst</groupId>
    <artifactId>wiremock-jre8</artifactId>
    <version>2.35.0</version>
    <scope>compile</scope>  <!-- 不是 test -->
</dependency>
```

## 快速诊断命令

### 一键诊断脚本

```bash
#!/bin/bash
# quick-diagnose.sh

echo "=== 快速诊断 ==="

echo -e "\n1. Maven 版本"
mvn -v | head -1

echo -e "\n2. Java 版本"
java -version 2>&1 | head -1

echo -e "\n3. Settings 配置"
[ -f ~/.m2/settings.xml ] && echo "✓ settings.xml 存在" || echo "✗ settings.xml 不存在"

echo -e "\n4. WireMock 依赖"
grep -i "wiremock" pom.xml && echo "✓ 找到依赖声明" || echo "✗ 未找到依赖声明"

echo -e "\n5. 依赖树"
mvn dependency:tree | grep -i wiremock || echo "✗ 依赖树中无 WireMock"

echo -e "\n6. 网络连通性"
curl -s -o /dev/null -w "Maven Central: %{http_code}\n" "https://repo1.maven.org/maven2/"

echo -e "\n=== 建议 ==="
echo "如果依赖声明不存在，请在 pom.xml 中添加"
echo "如果网络不通，请检查 settings.xml 配置"
```

## 责任边界速查表

| 错误信息 | 发生阶段 | 责任方 | 解决方向 |
|---------|---------|--------|---------|
| `package does not exist` | Maven compile | 用户 | 检查 pom.xml |
| `Could not transfer artifact` | Maven download | 用户 | 检查 settings.xml |
| `COPY failed` | Dockerfile | 用户/平台 | 检查 JAR 是否生成 |
| `ClassNotFoundException` | 运行时 | 用户 | 检查依赖 scope |
| `UnsatisfiedLinkError` | 运行时 | 平台 | 检查系统库 |
| `java: command not found` | 运行时 | 平台 | 检查基础镜像 |

## 用户沟通话术

### 场景 1：编译错误

```
您好，

错误 "package does not exist" 发生在 Maven 编译阶段，这是在平台 Dockerfile 介入之前。

这是用户层面的依赖配置问题，请检查：
1. pom.xml 中是否声明了该依赖
2. CI 环境的 settings.xml 配置
3. 依赖 scope 是否正确

参考文档：[链接]
```

### 场景 2：之前可用现在失败

```
您好，

"之前可用现在失败"通常是因为：
1. 传递依赖版本变化
2. Parent POM 更新
3. CI 缓存被清理

建议：
1. 显式声明依赖（不依赖传递引入）
2. 固定依赖版本
3. 运行 mvn dependency:tree 对比差异

参考文档：[链接]
```

### 场景 3：本地正常 CI 失败

```
您好，

"本地正常 CI 失败"通常是环境差异导致：
1. Maven/JDK 版本不同
2. settings.xml 配置不同
3. 网络访问权限不同

建议：
1. 对比本地和 CI 的 mvn -v 输出
2. 对比 mvn help:effective-settings
3. 在 CI 中运行 mvn clean package -X 查看详细日志

参考文档：[链接]
```

## 预防措施

### 最佳实践

1. **显式声明所有依赖**
   ```xml
   <!-- 不要依赖传递引入 -->
   <dependency>
       <groupId>com.github.tomakehurst</groupId>
       <artifactId>wiremock-jre8</artifactId>
       <version>2.35.0</version>
   </dependency>
   ```

2. **固定依赖版本**
   ```xml
   <!-- 避免使用 LATEST 或范围版本 -->
   <version>2.35.0</version>
   ```

3. **使用 dependencyManagement**
   ```xml
   <dependencyManagement>
       <dependencies>
           <!-- 统一管理版本 -->
       </dependencies>
   </dependencyManagement>
   ```

4. **配置 CI settings.xml**
   ```yaml
   before_script:
     - cp ci/settings.xml ~/.m2/settings.xml
   ```

5. **启用依赖缓存**
   ```yaml
   cache:
     paths:
       - .m2/repository/
   ```

6. **固定基础镜像版本**
   ```dockerfile
   FROM maven:3.9.8-eclipse-temurin-17
   # 不要使用 latest
   ```

## 参考资源

- [Maven 依赖机制](https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html)
- [Maven Settings 参考](https://maven.apache.org/settings.html)
- [WireMock 文档](http://wiremock.org/)
- [平台 CI/CD 文档](https://docs.platform.com/)
