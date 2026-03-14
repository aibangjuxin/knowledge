# 使用官方 Python 镜像作为基础
FROM python:3.9-slim

# 设置工作目录
WORKDIR /app

# 安装依赖
# 我们将 mysql-connector-python 库的版本固定，以确保构建的可重复性
RUN pip install mysql-connector-python==8.0.29

# 将应用代码复制到容器中
COPY app.py .

# 设置容器启动时执行的命令
CMD ["python", "-u", "app.py"]
