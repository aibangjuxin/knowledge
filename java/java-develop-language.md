# Java Application Development Methods: Identifying Spring Boot, Tomcat, and JAR Applications

This document explains how to identify which method your Java application is using - whether it's Spring Boot, Tomcat, or running as a standalone JAR. Understanding these differences is crucial for proper deployment, configuration, and troubleshooting.

## 1. Identifying Spring Boot Applications

Spring Boot is a popular framework that simplifies Java application development by providing auto-configuration and embedded servers.

### Key Indicators of Spring Boot Applications:

#### File Structure
- Look for a "fat JAR" (executable JAR with all dependencies)
- Contains `BOOT-INF/` directory structure:
  ```
  your-app.jar/
  ├── META-INF/
  ├── BOOT-INF/
  │   ├── classes/           # Your business code
  │   └── lib/               # All dependencies
  └── org.springframework.boot.loader.JarLauncher
  ```

#### Manifest File Content
Check the `META-INF/MANIFEST.MF` file inside the JAR:
```bash
unzip -p your-app.jar META-INF/MANIFEST.MF
```
Look for entries like:
- `Spring-Boot-Version: 2.7.10`
- `Main-Class: org.springframework.boot.loader.PropertiesLauncher`
- `Start-Class: com.example.YourMainApplication`

#### Command Line Execution
Spring Boot applications are typically run with:
```bash
java -jar your-app.jar
```

#### Dependencies
Look for Spring Boot dependencies in your `pom.xml` or `build.gradle`:
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter</artifactId>
</dependency>
```

#### Configuration Files
Common Spring Boot configuration files:
- `application.properties`
- `application.yml`
- Located in `BOOT-INF/classes/` inside the JAR

## 2. Identifying Tomcat Applications

Apache Tomcat is a servlet container that can run Java web applications. Applications can be deployed as WAR files or run with embedded Tomcat.

### Traditional Tomcat Deployments:
#### WAR Files
- Applications packaged as `.war` files
- Deployed to Tomcat's `webapps/` directory
- Tomcat extracts and runs the application

#### Embedded Tomcat
Many Spring Boot applications use embedded Tomcat:
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
</dependency>
```
This includes Tomcat as a dependency within the application.

### Identifying Tomcat Usage:
#### Process Information
Check running Java processes for Tomcat indicators:
```bash
ps aux | grep java
# Look for Tomcat-related class names
```

#### Thread Names
Tomcat threads typically have names like:
- `http-nio-8080-exec-*`
- `ContainerBackgroundProcessor[StandardEngine[Catalina]]`
- `Tomcat-startStop-*`

#### Log Messages
Tomcat applications often log messages indicating Tomcat startup:
```
INFO org.apache.catalina.core.StandardService.startInternal Starting service [Catalina]
INFO org.apache.catalina.core.StandardEngine.startInternal Starting Servlet Engine
```

#### Dependencies
In `pom.xml`, look for:
```xml
<dependency>
    <groupId>org.apache.tomcat.embed</groupId>
    <artifactId>tomcat-embed-core</artifactId>
</dependency>
```

## 3. Identifying Standalone JAR Applications

Standalone JAR applications are traditional Java applications that don't use Spring Boot or servlet containers.

### Characteristics of Standalone JARs:
#### Structure
- Typically smaller than fat JARs
- May have external dependencies in a `lib/` directory
- Main class defined in `META-INF/MANIFEST.MF`

#### Manifest File
Look for:
```
Main-Class: com.example.MainClass
Class-Path: lib/dependency1.jar lib/dependency2.jar
```

#### Execution
Often run with explicit classpath:
```bash
java -cp "lib/*:." com.example.MainClass
# or
java -jar app.jar -cp "lib/*"
```

#### Dependencies
Dependencies are typically separate JAR files in a `lib` directory, not bundled in the main JAR.

## 4. Practical Identification Commands

### For Any JAR File:
```bash
# List contents of JAR
jar tf your-app.jar
unzip -l your-app.jar

# Check manifest
jar xf your-app.jar META-INF/MANIFEST.MF
cat META-INF/MANIFEST.MF

# Look for Spring Boot indicators
unzip -l your-app.jar | grep -i spring
unzip -l your-app.jar | grep BOOT-INF

# Look for Tomcat indicators
unzip -l your-app.jar | grep -i tomcat
unzip -l your-app.jar | grep catalina
```

### For Running Applications:
```bash
# Check Java process arguments
jps -v | grep -i java

# Check loaded classes
jcmd <pid> VM.class_hierarchy | grep -i tomcat
jcmd <pid> VM.class_hierarchy | grep -i spring

# Check system properties
jcmd <pid> VM.system_properties
```

### Docker Container Inspection:
```bash
# If running in Docker/Kubernetes
kubectl exec -it <pod-name> -- ls -la /app/
kubectl exec -it <pod-name> -- ps aux | grep java
kubectl exec -it <pod-name> -- cat /app/application.properties
```

## 5. Azul Zulu Java Runtime Specifics

When running on Azul Zulu Java Runtime (as mentioned in your query):

### Verification Commands:
```bash
# Check Java version and vendor
java -version

# Inside container
kubectl exec -it <pod-name> -- java -version
```

Azul Zulu is compatible with all three application types (Spring Boot, Tomcat, standalone JARs). The runtime doesn't affect how you identify the application type, but it may have specific performance characteristics and JVM options.

## 6. Quick Decision Tree

Use this decision tree to quickly identify your application type:

1. **Can you run `java -jar your-app.jar` directly?**
   - Yes → Likely Spring Boot (fat JAR) or standalone executable JAR
   - No → Probably WAR for traditional Tomcat deployment

2. **Does the JAR contain a `BOOT-INF/` directory?**
   - Yes → Definitely Spring Boot application
   - No → Could be standalone JAR or traditional web app

3. **Are there Spring-related dependencies in the JAR?**
   - Yes → Likely Spring Boot application
   - No → Could be Tomcat or standalone application

4. **Does the application listen on HTTP ports by default?**
   - Yes → Likely Spring Boot with embedded Tomcat/Jetty/Undertow or standalone web app
   - No → Possibly a background service or command-line application

## 7. Common Scenarios

### Scenario 1: Spring Boot with Embedded Tomcat
- Uses Spring Boot framework
- Includes embedded Tomcat server
- Runs as `java -jar app.jar`
- Contains both Spring Boot and Tomcat indicators

### Scenario 2: Pure Spring Boot with Jetty
- Uses Spring Boot framework
- Includes embedded Jetty server instead of Tomcat
- Configure with exclusions in dependencies:
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
    <exclusions>
        <exclusion>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-tomcat</artifactId>
        </exclusion>
    </exclusions>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-jetty</artifactId>
</dependency>
```

### Scenario 3: Traditional WAR on External Tomcat
- Deployed to external Tomcat server
- No embedded server in application
- Managed by external Tomcat container

## Conclusion

Identifying your Java application type is essential for proper configuration, debugging, and optimization. The methods described above will help you determine whether your application uses Spring Boot, Tomcat, or runs as a standalone JAR. Remember that many modern applications combine approaches, such as Spring Boot applications with embedded Tomcat servers.