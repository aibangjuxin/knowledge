# K8s集群迁移代理 Dockerfile
# Dockerfile for K8s cluster migration proxy

FROM python:3.11-slim

# 设置工作目录
WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    nginx \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 复制Python依赖文件
COPY requirements.txt .

# 安装Python依赖
RUN pip install --no-cache-dir -r requirements.txt

# 复制源代码
COPY src/ ./src/
COPY config/ ./config/

# 创建必要的目录
RUN mkdir -p /etc/nginx/conf.d /var/log/nginx /etc/nginx/lua

# 复制Nginx基础配置
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# 设置权限
RUN chmod +x src/migration_controller.py

# 创建非root用户
RUN useradd -m -u 1000 migration && \
    chown -R migration:migration /app /etc/nginx /var/log/nginx /var/lib/nginx

# 切换到非root用户
USER migration

# 暴露端口
EXPOSE 80 443 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 启动命令
CMD ["python", "src/migration_controller.py", "run"]