FROM openjdk:8-jre-alpine

# 设置工作目录
WORKDIR /app

# 复制 JAR 文件
COPY target/maxcompute-health-check-1.0.0.jar app.jar

# 暴露端口
EXPOSE 8080

# 设置 JVM 参数
ENV JAVA_OPTS="-Xmx512m -Xms256m"

# 启动应用
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]