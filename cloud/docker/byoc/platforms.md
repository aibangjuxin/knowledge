# BYOC 平台特例 (Platform-specific Notes)

> 各平台的隐式合约、gotcha、最佳实践。**不**通用规则见 [README.md](./README.md) 和 [best-practices.md](./best-practices.md)。

---

## Vertex AI (GCP)

### Training (Custom Container)

**合约**：
- 容器启动后执行训练入口（你写）
- 多机训练：master 容器需要负责启动 worker（用 `TF_CONFIG` 或 torchrun）
- 退出码 0 = 成功，非 0 = 失败
- 训练数据通过 GCS / PVC 挂载，**不在 image 内**

**Gotcha**：
- GPU 镜像必须包含匹配 CUDA / cuDNN / NCCL 版本
- Vertex AI 注入 `AIP_TRAINING_DATA_URI`、`AIP_CHECKPOINT_DIR` 等环境变量
- Preemptible 节点：训练需要支持 checkpoint + resume（不能假设跑到底）

**模板**：
```dockerfile
FROM nvidia/cuda:12.3.1-cudnn8-runtime-ubuntu22.04

ARG GIT_SHA=unknown
LABEL org.opencontainers.image.revision=$GIT_SHA

ENV PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.10 python3-pip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

COPY . .

ENTRYPOINT ["python3", "train.py"]
```

---

### Prediction (Custom Container)

**合约（必须实现）**：
- 监听 `AIP_HTTP_PORT`（默认 8080）
- `GET /health` → 200 OK（健康检查）
- `POST /predict` → JSON 输入输出（AIP_PREDICT_ROUTE 可改路径）
- `POST /explain`（可选，AIP_EXPLAIN_ROUTE）

**Gotcha**：
- 镜像启动要快（在线服务冷启动敏感）
- 大模型权重**不要** bake 进 image → 用 GCS mount 或在容器启动时下载
- 推理并发：通过 gunicorn / uvicorn workers 调；不要单进程

**最小化实现（FastAPI）**：
```python
import os
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()
MODEL = load_model_at_startup()  # GCS 拉权重

class PredictRequest(BaseModel):
    instances: list

class PredictResponse(BaseModel):
    predictions: list

@app.get(os.environ.get("AIP_HEALTH_ROUTE", "/health"))
def health():
    return {"status": "ok"}

@app.post(os.environ.get("AIP_PREDICT_ROUTE", "/predict"))
def predict(req: PredictRequest):
    preds = [MODEL(x) for x in req.instances]
    return PredictResponse(predictions=preds).model_dump()
```

**启动命令**：
```bash
uvicorn predictor:app --host 0.0.0.0 --port ${AIP_HTTP_PORT:-8080} --workers 2
```

---

## Cloud Run (GCP)

**合约**：
- 必须监听 `$PORT`（平台注入，默认 8080）
- 启动后 4 分钟内接受流量（默认 request timeout）
- HTTP/1.1 或 HTTP/2；gRPC 也支持
- Sigterm → 必须在当前 request 处理完后退出（最长 10s）

**Gotcha**：
- 文件系统是 **ephemeral** — 任何写入 `/tmp` 之外的数据**会丢**
- **冷启动**：image 越大 cold start 越慢；考虑 min-instances
- Concurrency：单 instance 可处理多个并发请求（默认 80，可调）
- CPU 在无流量时可能被 throttled 到 0（不要做 cron in-process）

**反模式**：
- 单 image 跑 web + worker（拆 Cloud Run + Cloud Run Jobs / Pub/Sub push）
- 把 SQLite 文件写进 image 层（写 mount 的 `/tmp` 或外部 DB）

---

## Cloud Run Jobs (GCP)

**合约**：
- 任务跑完退出码 = 成功 / 失败
- 重试策略可配（exit code 触发）
- Task parallelism：`--tasks N` 把同一 image 并行跑 N 次（不同参数）
- 单 task timeout 默认 1h，可调到 24h

**Gotcha**：
- 无 HTTP 监听要求
- 镜像不需要 web server
- 适合 ETL、batch ML、cron-like 任务

**最小化实现**：
```python
import sys

def main():
    # 业务逻辑
    result = do_work()
    if not result.ok:
        sys.exit(1)  # 触发重试
    sys.exit(0)     # 成功

if __name__ == "__main__":
    main()
```

---

## AWS SageMaker

**合约（必须实现）**：
- `GET /ping` → 200 OK（健康检查）
- `POST /invocations` → 推理（content-type 决定输入格式）
- `GET /execution-parameters`（可选，超参 inference）

**Gotcha**：
- SageMaker **注入** `SAGEMAKER_BIND_TO_PORT`（通常 8080）+ `SAGEMAKER_CONTAINER_LOG_LEVEL`
- 旧 SDK 强制 `gunicorn` 配置 — 新 SDK (DJL Serving / BentoML) 放宽
- 多模型 endpoint：容器需要支持 `SAGEMAKER_MULTI_MODEL=true`，动态加载 model

**反模式**：
- 把 model artifacts 烤进 image（用 `/opt/ml/model` 挂载点，平台自动挂）

---

## GitHub Actions

**合约**：
- `container:` directive 指定 image
- Job 在容器内执行；`services:` 起 sidecar 容器
- 容器间用 `localhost:port` 通信（不是 service name）

**Gotcha**：
- GitHub-hosted runner **拉 image 走公网** — 私有 image 用 PAT / GitHub App auth
- Self-hosted runner：image 缓存到本地
- 默认非 root，但 GHA 会以 UID 1001 跑（镜像里这个 user 必须存在）
- 网络：runner → 容器是 host network；容器之间是 bridge network

**示例**：
```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: myregistry/myapp-ci:v1
      env:
        CI: "true"
      options: --user 1001
    steps:
      - uses: actions/checkout@v4
      - run: pytest
```

---

## Cloudflare Containers (Beta)

**合约**：
- Container 在 Cloudflare 边缘节点启动
- 必须有 HTTP listener（任意端口，可在 `wrangler.toml` 配置）
- 持久化用 Durable Objects / R2 / D1（不要写本地 FS）

**Gotcha**：
- 镜像大小限制 ~ 几 GB（具体看 plan）
- 冷启动比 Workers 慢（容器启动 + image 拉取）
- 区域：image 不会自动 replicate 到所有 POP
- 调试：本地用 `wrangler dev` 模拟

---

## AWS Lambda (Container Image)

**合约**：
- 镜像必须实现 Lambda Runtime Interface Emulation（RIE）或内置 Runtime API client
- Handler 路径在 image config 暴露
- 镜像最大 10GB

**Gotcha**：
- Lambda **拉 image 限制 90 秒**（超过 250MB 走 ECR 内部网络）
- 用 `public.ecr.aws/lambda/python:3.12` 作 base，**已带 RIE**
- 冷启动比 zip 大（image 启动 + extract layers）

**最小化模板**：
```dockerfile
FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py ${LAMBDA_TASK_ROOT}
CMD [ "app.handler" ]
```

---

## Databricks Container Services

**用途**：cluster 启动时跑 container 做**环境配置**（不是任务执行）。

**合约**：
- Init script 等价物：在 image 内
- Container 跑完即退出（一次性 init）
- Cluster 上跑的 job/notebook 仍是 Spark 进程

**Gotcha**：
- Databricks Runtime 镜像 + 你的 custom 容器 = base 兼容性
- 不能用 `systemd` — 容器是 init 进程
- 镜像内 **不**持久化数据（cluster 终止 → 容器消失）

---

## Fly.io / Render / Railway (PaaS)

**合约**：
- Dockerfile-driven
- HTTP listener 通常平台自动检测（或 `PORT` env）
- Build 自动触发（Git push → CI → deploy）

**Gotcha**：
- Fly.io：支持 multi-region deploy + 边缘 proxy
- Render：更简单，scaling 行为可预测
- Railway：开发者体验最好，但价格较高
- 共同点：**不**适合 stateful 服务（用托管 DB）

---

## 跨平台决策树

```
新项目：要不要 BYOC？
  │
  ├── 平台 managed runtime 满足需求？
  │   └── ✅ 用 managed，不 BYOC
  │
  ├── 需要自定义 CUDA / 系统包 / 私有 Python 库？
  │   └── ✅ Vertex AI / SageMaker BYOC
  │
  ├── 简单 HTTP API + 标准 runtime？
  │   └── 用 Cloud Run source deploy 或 App Runner
  │
  ├── 批处理 / 一次性 job？
  │   └── Cloud Run Jobs / SageMaker Processing / Vertex AI Custom Job
  │
  └── 边缘 / 低延迟？
      └── Cloudflare Containers / Lambda@Edge（限定使用场景）
```
