# Java Application Log Level Control in Kubernetes Deployments

## Overview

This document explores the best practices for controlling Java application log levels through Kubernetes Deployments, with a focus on setting a default log level (INFO) while allowing users to override it when needed. This addresses the issue of users enabling DEBUG level logging which can cause significant log volume in a shared platform environment.

## Problem Statement

- Current platform lacks predefined user log levels
- Users can enable DEBUG logging causing high log volume
- Need to enforce a default INFO level while allowing overrides
- Solution should be implemented at the Deployment level

## Solution Approaches

### 1. Environment Variable Approach (Recommended)

The most flexible and commonly used approach is to leverage environment variables in the Kubernetes Deployment specification, similar to the concepts described in the reference document about environment variables in Deployments.

#### Implementation Steps:

1. **Define Default Log Level in Deployment**:
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: java-app
   spec:
     template:
       spec:
         containers:
         - name: app-container
           image: your-java-app:latest
           env:
           # Default log level - can be overridden by users
           - name: LOG_LEVEL
             value: "INFO"
           # Pass the log level to the Java application
           - name: JAVA_OPTS
             value: "-Dlogging.level.root=$(LOG_LEVEL)"
   ```

2. **Configure Java Application to Use Environment Variables**:
   
   For Spring Boot applications, you can use:
   - `application.properties` or `application.yml` with placeholders
   - JVM arguments passed through environment variables
   - Logback configuration with variable substitution

3. **Logback Configuration Example**:
   ```xml
   <!-- logback-spring.xml -->
   <configuration>
     <springProperty name="ROOT_LOG_LEVEL" source="LOG_LEVEL" defaultValue="INFO"/>
     <root level="${ROOT_LOG_LEVEL}">
       <appender-ref ref="CONSOLE"/>
     </root>
   </configuration>
   ```

### 2. ConfigMap-Based Approach

For more complex logging configurations:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: log-config
data:
  logback-spring.xml: |
    <configuration>
      <springProperty name="ROOT_LOG_LEVEL" source="LOG_LEVEL" defaultValue="INFO"/>
      <root level="${ROOT_LOG_LEVEL}">
        <appender-ref ref="CONSOLE"/>
      </root>
    </configuration>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-app
spec:
  template:
    spec:
      containers:
      - name: app-container
        image: your-java-app:latest
        env:
        - name: LOG_LEVEL
          value: "INFO"
        volumeMounts:
        - name: log-config
          mountPath: /app/config
      volumes:
      - name: log-config
        configMap:
          name: log-config
```

### 3. Init Container Approach

For advanced scenarios where you need to generate configuration files:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-app
spec:
  template:
    spec:
      initContainers:
      - name: configure-logging
        image: busybox:1.35
        command:
        - sh
        - -c
        - |
          DEFAULT_LEVEL=${LOG_LEVEL:-INFO}
          echo "Creating logback configuration with default level: $DEFAULT_LEVEL"
          cat > /config/logback-spring.xml <<EOF
   <configuration>
     <springProperty name="ROOT_LOG_LEVEL" source="LOG_LEVEL" defaultValue="$DEFAULT_LEVEL"/>
     <root level="\${ROOT_LOG_LEVEL}">
       <appender-ref ref="CONSOLE"/>
     </root>
   </configuration>
   EOF
        env:
        - name: LOG_LEVEL
          value: "INFO"
        volumeMounts:
        - name: config-volume
          mountPath: /config
      containers:
      - name: app-container
        image: your-java-app:latest
        volumeMounts:
        - name: config-volume
          mountPath: /app/config
        env:
        - name: LOG_LEVEL
          value: "INFO"
      volumes:
      - name: config-volume
        emptyDir: {}
```

## Best Practices

### 1. Default Configuration Enforcement

Always set a default log level in the base Deployment template:

```yaml
env:
- name: LOG_LEVEL
  value: "INFO"  # Default value - users can override this
```

### 2. Documentation for Users

Provide clear documentation on how users can override the default:

```markdown
## Logging Configuration

By default, your application runs with INFO level logging. To change this:

1. Add an environment variable to your Deployment:
   ```yaml
   env:
   - name: LOG_LEVEL
     value: "DEBUG"  # Options: TRACE, DEBUG, INFO, WARN, ERROR
   ```

2. The application will automatically adjust its log level based on this variable.
```

### 3. Validation and Monitoring

Consider implementing validation to prevent users from setting excessively verbose log levels:

- Use admission controllers to validate log level values
- Monitor log volume and alert on unusual spikes
- Implement log aggregation quotas

### 4. Framework-Specific Configurations

#### For Spring Boot Applications:
```yaml
# Pass to application via environment
env:
- name: SPRING_PROFILES_ACTIVE
  value: "production"
- name: LOGGING_LEVEL_ROOT
  value: "INFO"
```

#### For Log4j2:
```xml
<!-- log4j2-spring.xml -->
<Configuration status="WARN">
  <Properties>
    <Property name="rootLogLevel">${env:LOG_LEVEL:-INFO}</Property>
  </Properties>
  <Loggers>
    <Root level="${rootLogLevel}">
      <AppenderRef ref="Console"/>
    </Root>
  </Loggers>
</Configuration>
```

## Recommended Implementation Strategy

1. **Start with Environment Variables**: Use the simplest approach first (environment variables) as shown in the reference document
2. **Provide Clear Documentation**: Document how users can override the default
3. **Set Reasonable Limits**: Consider setting upper limits on log verbosity
4. **Monitor Impact**: Track log volume after implementation
5. **Gradual Rollout**: Implement in stages to catch any issues

## Conclusion

The environment variable approach is the most suitable solution for controlling Java application log levels in Kubernetes Deployments. It follows the principles outlined in the reference document about environment variables in Deployments, provides flexibility for users to override defaults, and maintains a sensible default (INFO level) to prevent excessive logging in the platform.

This approach is:
- Simple to implement and maintain
- Flexible for user customization
- Consistent with Kubernetes best practices
- Compatible with various Java logging frameworks