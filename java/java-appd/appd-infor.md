docker pull appdynamics/java-agent:25.10.0.37406

<https://hub.docker.com/r/appdynamics/java-agent>

1. With Init Containers (Kubernetes/OpenShift)
   For container orchestration platforms like Kubernetes or OpenShift, an init container is an excellent way to stage the agent files. The init container runs to completion before your main application container starts, copying the necessary files.

Example Kubernetes Snippet:

---

initContainers:
```yaml
- name: appd-agent
  image: appdynamics/java-agent:latest
  command: - cp - -r - /opt/appdynamics/. - /opt/appdynamics-java
  volumeMounts: - name: appd-agent-repo
  mountPath: /opt/appdynamics-java
  containers:
- name: my-java-app
  image: my-java-app-image:latest
  volumeMounts: - name: appd-agent-repo
  mountPath: /opt/appdynamics-java
  env: - name: JAVA_TOOL_OPTIONS
  value: -javaagent:/opt/appdynamics-java/javaagent.jar
  volumes:
- name: appd-agent-repo
  emptyDir: {}
```
2. As a Builder in Multi-Stage Docker Builds
   For standard Docker builds, you can leverage multi-stage builds to copy the agent files efficiently without increasing the size of your final application image.

Example Dockerfile for your Application:
```Dockerfile
# Stage 1: Get the Agent

FROM appdynamics/java-agent:latest AS appd-agent

# Stage 2: Build your application

FROM openjdk:17-jdk-slim # Your app's base image

# Copy agent from Stage 1

COPY --from=appd-agent /opt/appdynamics /opt/appdynamics

# Enable the agent

ENV JAVA_TOOL_OPTIONS="-javaagent:/opt/appdynamics/javaagent.jar"

# Add your application

WORKDIR /app
COPY target/my-java-app.jar /app/my-java-app.jar
CMD ["java", "-jar", "my-java-app.jar"]
```
By following these methods, you can effectively integrate the AppDynamics Java Agent into your containerized Java applications while adhering to the recommended best practices for this specific Docker image.
