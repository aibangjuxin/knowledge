FROM python:3.11-slim

# 设置工作目录
WORKDING /app

# 复制应用文件
COPY requirements.txt .
COPY main.py .

# 创建证书目录
RUN mkdir -p /etc/ssl/certs

# 安装依赖
RUN pip install --no-cache-dir -r requirements.txt

# 暴露端口
EXPOSE 8443

# 启动应用
CMD ["python", "main.py"]