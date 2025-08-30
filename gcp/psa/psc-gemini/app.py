import os
import mysql.connector
import time

# 从环境变量中获取数据库连接信息
db_host = os.getenv("DB_HOST")
db_user = os.getenv("DB_USER")
db_password = os.getenv("DB_PASSWORD")
db_name = os.getenv("DB_NAME", "mysql") # 默认连接到 'mysql' 数据库

def connect_to_db():
    """尝试连接到数据库，如果失败则重试"""
    max_retries = 5
    retry_delay = 10 # seconds
    attempt = 0

    while attempt < max_retries:
        attempt += 1
        print(f"--- Attempting to connect to database (Attempt {attempt}/{max_retries}) ---")
        try:
            print(f"Connecting with: host={db_host}, user={db_user}")
            connection = mysql.connector.connect(
                host=db_host,
                user=db_user,
                password=db_password,
                database=db_name,
                connection_timeout=10
            )

            if connection.is_connected():
                print("\n✅ Successfully connected to the database!\n")
                cursor = connection.cursor()
                cursor.execute("SELECT VERSION();")
                db_version = cursor.fetchone()
                print(f"Database version: {db_version[0]}\n")
                cursor.close()
                connection.close()
                return True # 连接成功

        except mysql.connector.Error as err:
            print(f"\n❌ Connection failed: {err}\n")
            if attempt < max_retries:
                print(f"Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                print("--- Max retries reached. Could not connect to the database. ---")
                return False # 连接失败

if __name__ == "__main__":
    if not all([db_host, db_user, db_password]):
        print("❌ Error: DB_HOST, DB_USER, and DB_PASSWORD environment variables must be set.")
    else:
        if connect_to_db():
            # 在实际应用中，你可以在这里启动你的 web server 或其他业务逻辑
            print("Application would start now. For this demo, we will just exit.")
        else:
            # 退出并让 Kubernetes 根据 restartPolicy 重启 Pod
            exit(1)
