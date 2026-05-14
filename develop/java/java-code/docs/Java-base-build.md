# Java 基础项目构建文档

本文档旨在说明如何构建和运行一个基础的 Java Spring Boot 项目。

## 1. 项目结构

```bash
.
├── pom.xml
├── .mvn
│   └── wrapper
│       ├── maven-wrapper.jar
│       └── maven-wrapper.properties
├── mvnw
├── mvnw.cmd
└── src
    ├── main
    │   ├── java
    │   │   └── com
    │   │       └── example
    │   │           └── healthcheck
    │   │               ├── HealthCheckApplication.java
    │   │               ├── controller
    │   │               │   └── HealthController.java
    │   │               ├── model
    │   │               │   └── HealthResponse.java
    │   │               └── service
    │   │                   └── HealthService.java
    │   └── resources
    └── test
        └── java
            └── com
                └── example
                    └── healthcheck
```

## 2. 构建项目

此项目使用 Maven 进行构建。为了方便起见，我们提供了 Maven Wrapper，因此您无需在本地安装 Maven。

### Windows

```bash
./mvnw.cmd clean install
```

### macOS / Linux

```bash
./mvnw clean install
```

构建成功后，您将在 `target` 目录下看到一个名为 `health-check-api-1.1.0.jar` 的文件。

## 3. 运行项目

使用以下命令运行项目：

```bash
java -jar target/health-check-api-1.1.0.jar
```
the result 
```bash
java -jar target/health-check-api-1.1.0.jar
🚀 启动健康检查API服务...

  .   ____          _            __ _ _
 /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
 \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
  '  |____| .__|_| |_|_| |_\__, | / / / /
 =========|_|==============|___/=/_/_/_/
 :: Spring Boot ::                (v3.2.0)

2025-08-16T17:39:15.377+08:00  INFO 22224 --- [           main] c.e.healthcheck.HealthCheckApplication   : Starting HealthCheckApplication v1.1.0 using Java 24.0.2 with PID 22224 (/Users/lex/git/knowledge/java-code/target/health-check-api-1.1.0.jar started by lex in /Users/lex/git/knowledge/java-code)
2025-08-16T17:39:15.379+08:00  INFO 22224 --- [           main] c.e.healthcheck.HealthCheckApplication   : No active profile set, falling back to 1 default profile: "default"
WARNING: A restricted method in java.lang.System has been called
WARNING: java.lang.System::load has been called by org.apache.tomcat.jni.Library in an unnamed module (jar:nested:/Users/lex/git/knowledge/java-code/target/health-check-api-1.1.0.jar/!BOOT-INF/lib/tomcat-embed-core-10.1.16.jar!/)
WARNING: Use --enable-native-access=ALL-UNNAMED to avoid a warning for callers in this module
WARNING: Restricted methods will be blocked in a future release unless native access is enabled

2025-08-16T17:39:15.789+08:00  INFO 22224 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat initialized with port 8080 (http)
2025-08-16T17:39:15.793+08:00  INFO 22224 --- [           main] o.apache.catalina.core.StandardService   : Starting service [Tomcat]
2025-08-16T17:39:15.793+08:00  INFO 22224 --- [           main] o.apache.catalina.core.StandardEngine    : Starting Servlet engine: [Apache Tomcat/10.1.16]
2025-08-16T17:39:15.805+08:00  INFO 22224 --- [           main] o.a.c.c.C.[Tomcat].[localhost].[/]       : Initializing Spring embedded WebApplicationContext
2025-08-16T17:39:15.805+08:00  INFO 22224 --- [           main] w.s.c.ServletWebServerApplicationContext : Root WebApplicationContext: initialization completed in 395 ms
2025-08-16T17:39:16.010+08:00  INFO 22224 --- [           main] o.s.b.a.e.web.EndpointLinksResolver      : Exposing 1 endpoint(s) beneath base path '/actuator'
2025-08-16T17:39:16.047+08:00  INFO 22224 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8080 (http) with context path ''
2025-08-16T17:39:16.055+08:00  INFO 22224 --- [           main] c.e.healthcheck.HealthCheckApplication   : Started HealthCheckApplication in 0.824 seconds (process running for 1.061)
✅ 健康检查API服务启动成功！
📍 健康检查地址: http://localhost:8080/api_name_samples/v1.1.0/.well-known/health
2025-08-16T17:39:34.595+08:00  INFO 22224 --- [nio-8080-exec-1] o.a.c.c.C.[Tomcat].[localhost].[/]       : Initializing Spring DispatcherServlet 'dispatcherServlet'
2025-08-16T17:39:34.595+08:00  INFO 22224 --- [nio-8080-exec-1] o.s.web.servlet.DispatcherServlet        : Initializing Servlet 'dispatcherServlet'
2025-08-16T17:39:34.596+08:00  INFO 22224 --- [nio-8080-exec-1] o.s.web.servlet.DispatcherServlet        : Completed initialization in 1 ms
📋 收到健康检查请求 - 2025-08-16T17:39:34.611220
📋 收到健康检查请求 - 2025-08-16T17:40:01.887942
📋 收到健康检查请求 - 2025-08-16T17:40:37.731790
📋 收到健康检查请求 - 2025-08-16T17:41:04.311339
📋 收到健康检查请求 - 2025-08-16T17:41:06.340032
📋 收到健康检查请求 - 2025-08-16T17:41:06.921850
📋 收到健康检查请求 - 2025-08-16T17:41:07.397339
```

服务启动后，您可以访问以下地址进行健康检查：

[http://localhost:8080/api_name_samples/v1.1.0/.well-known/health](http://localhost:8080/api_name_samples/v1.1.0/.well-known/health)

## 4. 测试

要运行项目中的测试，请执行以下命令：

### Windows

```bash
./mvnw.cmd test
```

### macOS / Linux

```bash
./mvnw test
```
the result
```bash
./mvnw test
WARNING: A restricted method in java.lang.System has been called
WARNING: java.lang.System::load has been called by org.fusesource.jansi.internal.JansiLoader in an unnamed module (file:/Users/lex/.m2/wrapper/dists/apache-maven-3.8.4-bin/99c998df/apache-maven-3.8.4/lib/jansi-2.4.0.jar)
WARNING: Use --enable-native-access=ALL-UNNAMED to avoid a warning for callers in this module
WARNING: Restricted methods will be blocked in a future release unless native access is enabled

WARNING: A terminally deprecated method in sun.misc.Unsafe has been called
WARNING: sun.misc.Unsafe::objectFieldOffset has been called by com.google.common.util.concurrent.AbstractFuture$UnsafeAtomicHelper (file:/Users/lex/.m2/wrapper/dists/apache-maven-3.8.4-bin/99c998df/apache-maven-3.8.4/lib/guava-25.1-android.jar)
WARNING: Please consider reporting this to the maintainers of class com.google.common.util.concurrent.AbstractFuture$UnsafeAtomicHelper
WARNING: sun.misc.Unsafe::objectFieldOffset will be removed in a future release
[INFO] Scanning for projects...
[INFO] 
[INFO] --------------------< com.example:health-check-api >--------------------
[INFO] Building health-check-api 1.1.0
[INFO] --------------------------------[ jar ]---------------------------------
[INFO] 
[INFO] --- maven-resources-plugin:3.3.1:resources (default-resources) @ health-check-api ---
[INFO] Copying 0 resource from src/main/resources to target/classes
[INFO] Copying 0 resource from src/main/resources to target/classes
[INFO] 
[INFO] --- maven-compiler-plugin:3.11.0:compile (default-compile) @ health-check-api ---
[INFO] Nothing to compile - all classes are up to date
[INFO] 
[INFO] --- maven-resources-plugin:3.3.1:testResources (default-testResources) @ health-check-api ---
[INFO] skip non existing resourceDirectory /Users/lex/git/knowledge/java-code/src/test/resources
[INFO] 
[INFO] --- maven-compiler-plugin:3.11.0:testCompile (default-testCompile) @ health-check-api ---
[INFO] Nothing to compile - all classes are up to date
[INFO] 
[INFO] --- maven-surefire-plugin:3.1.2:test (default-test) @ health-check-api ---
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  0.354 s
[INFO] Finished at: 2025-08-16T17:42:05+08:00
[INFO] ------------------------------------------------------------------------
```

要在 macOS 系统中访问并使用 Maven 编辑和管理你位于 `java-code` 目录中的 Java 源代码，你需要完成以下步骤。我会逐步讲解每个必要的操作，包括安装 Java 环境、Maven 以及如何配置和使用它们来管理你的代码。

---

### 前提条件
- 你已经在 macOS 系统上有一个目录（如 `java-code`），其中存放了你的 Java 源代码。
- 你希望使用 Maven 来管理依赖、编译和运行你的 Java 项目。

---

### 步骤 1：检查和安装 Java 环境 (JDK)
Maven 需要 Java Development Kit (JDK) 来编译和运行 Java 代码，因此首先需要确保你的 macOS 系统上已安装 JDK。

1. **检查是否已安装 Java**：
   打开 Terminal（终端），输入以下命令：
   ```bash
   java -version
   ```
   - 如果显示类似 `java version "1.8.0_xxx"` 或更高的版本（如 11、17），说明 JDK 已经安装，可以跳到步骤 2。
   - 如果显示类似 `command not found` 或提示安装 Java，说明需要安装 JDK。

2. **安装 JDK**：
   有两种推荐的方式在 macOS 上安装 JDK：
   - **使用 Homebrew（推荐）**：Homebrew 是 macOS 上常用的包管理器，安装和管理软件非常方便。
     1. 如果未安装 Homebrew，先安装它。运行以下命令：
        ```bash
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        ```
     2. 安装 OpenJDK（例如版本 17，长期支持版）：
        ```bash
        brew install openjdk@17
        ```
     3. 安装完成后，设置环境变量以确保系统能找到 JDK。运行以下命令（根据你的 shell 配置文件，可能是 `~/.zshrc` 或 `~/.bash_profile`）：
        ```bash
        echo 'export JAVA_HOME=$(brew --prefix openjdk@17)' >> ~/.zshrc
        source ~/.zshrc
        ```
     4. 验证安装：
        ```bash
        java -version
        ```
        应该会看到类似 `openjdk 17.x.x` 的输出。
   - **手动下载 Oracle JDK**：如果你更喜欢 Oracle 的官方 JDK，可以从 Oracle 官网下载安装包。
     1. 访问 [Oracle JDK 下载页面](https://www.oracle.com/java/technologies/downloads/)，选择适合 macOS 的版本（例如 JDK 17）。
     2. 下载并安装 `.dmg` 文件，按提示完成安装。
     3. 验证安装：
        ```bash
        java -version
        ```

---

### 步骤 2：安装 Maven
Maven 是 Java 项目的构建工具，用于管理依赖、编译和打包代码。

1. **检查是否已安装 Maven**：
   在 Terminal 中运行：
   ```bash
   mvn -version
   ```
   - 如果显示版本信息，说明已安装，可以跳到步骤 3。
   - 如果显示 `command not found`，需要安装 Maven。

2. **安装 Maven**：
   同样推荐使用 Homebrew：
   ```bash
   brew install maven
   ```
   安装完成后，验证：
   ```bash
   mvn -version
   ```
   应该会看到类似 `Apache Maven 3.x.x` 的输出。

   或者，你可以从 [Maven 官方网站](https://maven.apache.org/download.cgi) 下载二进制文件，解压后手动配置环境变量，但 Homebrew 方式更简单。

---

### 步骤 3：初始化 Maven 项目
假设你的 `java-code` 目录中已经有一些 Java 源代码文件，你需要将它转换为一个 Maven 项目，以便使用 Maven 管理。

1. **进入代码目录**：
   在 Terminal 中导航到你的代码目录：
   ```bash
   cd ~/java-code
   ```

2. **创建 Maven 项目结构**（如果目录中没有 Maven 结构）：
   如果 `java-code` 只是一个普通目录，里面只有 `.java` 文件，没有 Maven 标准的项目结构，你需要初始化一个 Maven 项目：
   ```bash
   mvn archetype:generate -DgroupId=com.mycompany.app -DartifactId=my-app -DarchetypeArtifactId=maven-archetype-quickstart -DarchetypeVersion=1.4 -DinteractiveMode=false
   ```
   - `groupId`：你的组织或项目组标识（可以根据需要修改）。
   - `artifactId`：项目名称（可以改为你的项目名，如 `java-code`）。
   - 这会生成一个标准的 Maven 项目结构，包含 `src/main/java` 和 `src/test/java` 目录，以及一个 `pom.xml` 文件。
   - 生成后，进入新生成的目录（例如 `my-app`）：
     ```bash
     cd my-app
     ```

3. **迁移现有代码**（可选）：
   如果你的 `java-code` 目录中已有代码，将你的 `.java` 文件移动到 `src/main/java` 目录下的适当包结构中。例如：
   ```bash
   mkdir -p src/main/java/com/mycompany/app
   mv /path/to/java-code/*.java src/main/java/com/mycompany/app/
   ```
   确保代码文件的包声明（`package` 语句）与目录结构一致。

4. **检查或创建 `pom.xml` 文件**：
   `pom.xml` 是 Maven 的配置文件，用于定义项目依赖和构建规则。如果使用 `archetype:generate` 已生成 `pom.xml`，可以直接编辑它。如果没有，可以手动创建一个基础的 `pom.xml`：
   ```xml
   <project xmlns="http://maven.apache.org/POM/4.0.0"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
       <modelVersion>4.0.0</modelVersion>
       <groupId>com.mycompany.app</groupId>
       <artifactId>my-app</artifactId>
       <version>1.0-SNAPSHOT</version>
       <properties>
           <maven.compiler.source>17</maven.compiler.source>
           <maven.compiler.target>17</maven.compiler.target>
       </properties>
   </project>
   ```
   - 将 `groupId`、`artifactId` 和 `version` 调整为你的项目信息。
   - `maven.compiler.source` 和 `maven.compiler.target` 设置为与你安装的 JDK 版本一致（如 17）。

---

### 步骤 4：使用 Maven 管理项目
现在你的项目已经是标准的 Maven 项目，可以使用 Maven 命令来编译、测试和运行代码。

1. **编译项目**：
   在项目目录下运行：
   ```bash
   mvn compile
   ```
   这会编译 `src/main/java` 中的代码，输出到 `target/classes` 目录。

2. **运行测试**（如果有）：
   ```bash
   mvn test
   ```
   这会运行 `src/test/java` 中的单元测试。

3. **打包项目**：
   ```bash
   mvn package
   ```
   这会将项目打包成 JAR 文件（或其他格式，取决于 `pom.xml` 配置），通常位于 `target/` 目录。

4. **运行代码**：
   如果你的项目有一个主类（包含 `main` 方法），可以在 `pom.xml` 中配置 `exec-maven-plugin`，然后使用以下命令运行：
   ```bash
   mvn exec:java -Dexec.mainClass="com.mycompany.app.App"
   ```
   将 `com.mycompany.app.App` 替换为你的主类完整路径。

5. **添加依赖**（可选）：
   如果你的代码需要外部库（如 JUnit、Apache Commons），编辑 `pom.xml`，在 `<dependencies>` 节点下添加依赖。例如添加 JUnit：
   ```xml
   <dependencies>
       <dependency>
           <groupId>junit</groupId>
           <artifactId>junit</artifactId>
           <version>4.13.2</version>
           <scope>test</scope>
       </dependency>
   </dependencies>
   ```
   然后运行：
   ```bash
   mvn install
   ```
   Maven 会自动下载并管理依赖。

---

### 步骤 5：使用 IDE 增强开发体验（可选）
虽然可以在终端中使用 Maven 命令直接管理项目，但大多数开发者更喜欢使用 IDE（如 IntelliJ IDEA 或 Eclipse）来编辑代码，IDE 通常内置对 Maven 的支持。

1. **安装 IDE**：
   - 下载并安装 IntelliJ IDEA（推荐）或 Eclipse。
   - IntelliJ IDEA 社区版是免费的，适用于大多数 Java 开发需求。

2. **导入 Maven 项目**：
   - 打开 IDE，选择 "Open" 或 "Import Project"。
   - 选择你的项目目录（包含 `pom.xml` 的目录）。
   - IDE 会自动识别 Maven 项目并下载依赖。

3. **编辑代码**：
   - 使用 IDE 的代码补全、调试和重构功能来提升开发效率。
   - 右键点击 `pom.xml` 可以重新同步依赖。

---

### 总结：所需工作
1. **安装 JDK**：使用 Homebrew 安装 OpenJDK 或从 Oracle 下载 JDK，确保 `java -version` 正常工作。
2. **安装 Maven**：使用 Homebrew 安装 Maven，确保 `mvn -version` 正常工作。
3. **初始化 Maven 项目**：将你的 `java-code` 目录转换为 Maven 项目结构，创建或编辑 `pom.xml`。
4. **使用 Maven 命令**：编译、测试和运行代码，添加依赖。
5. **（可选）使用 IDE**：导入项目到 IntelliJ IDEA 或 Eclipse，提升开发体验。

---

### 常见问题解决
- **Maven 命令报错**：如果遇到 `JAVA_HOME not set` 错误，确保设置了正确的 Java 环境变量：
  ```bash
  export JAVA_HOME=$(/usr/libexec/java_home -v 17)
  ```
- **依赖下载失败**：检查网络连接，或者尝试清理 Maven 缓存：
  ```bash
  mvn clean
  ```
- **代码包结构错误**：确保 `.java` 文件中的 `package` 声明与目录结构一致。

如果你有具体的项目细节（如代码结构、依赖需求）或者遇到问题（例如安装错误、Maven 配置问题），请告诉我，我可以提供更针对性的帮助！