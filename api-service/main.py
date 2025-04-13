from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from google.cloud import bigquery
import uvicorn
import ssl

app = FastAPI()

# 定义数据模型
class Item(BaseModel):
    name: str
    age: int

# 创建BigQuery客户端
client = bigquery.Client()

# 健康检查接口
@app.get("/v1/.well-known/health")
async def health_check():
    return {"status": "healthy"}

# 数据收集接口
@app.post("/api/v1/collection")
async def create_item(item: Item):
    try:
        # 准备数据插入BigQuery
        table_id = "your-project.your_dataset.collection_table"
        rows_to_insert = [{
            "name": item.name,
            "age": item.age
        }]

        # 插入数据到BigQuery
        errors = client.insert_rows_json(table_id, rows_to_insert)
        if errors == []:
            return {"status": "success", "message": "Data inserted successfully"}
        else:
            raise HTTPException(status_code=500, detail=f"Error inserting data: {errors}")

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    # 配置SSL上下文
    ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ssl_context.load_cert_chain(
        certfile="/etc/ssl/certs/tls.crt",
        keyfile="/etc/ssl/certs/tls.key"
    )
    
    # 启动服务器
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8443,
        ssl_certfile="/etc/ssl/certs/tls.crt",
        ssl_keyfile="/etc/ssl/certs/tls.key"
    )