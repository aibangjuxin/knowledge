FROM openjdk:11-jre-slim

# 安装必要工具
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# 创建工作目录
WORKDIR /app

# 复制扫描器
COPY target/auth-scanner.jar /app/
COPY scripts/pipeline-integration.sh /app/

# 设置执行权限
RUN chmod +x /app/pipeline-integration.sh

# 创建输出目录
RUN mkdir -p /app/reports

# 设置环境变量
ENV SCANNER_JAR=/app/auth-scanner.jar

# 入口点
ENTRYPOINT ["/app/pipeline-integration.sh"]