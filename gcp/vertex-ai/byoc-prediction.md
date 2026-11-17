# Vertex AI — Custom Prediction (BYOC) 端到端

> 自定义容器跑在线推理。覆盖：FastAPI 推理服务器、模型加载、autoscaling、A/B 测试、gcloud 部署。

---

## 1. 平台合约（必看）

Vertex AI Custom Prediction **强制**实现：

| 要求 | 详情 |
|---|---|
| **HTTP listener** | 监听 `AIP_HTTP_PORT`（默认 8080） |
| **`GET <AIP_HEALTH_ROUTE>`** | 默认 `/health`，返回 200 |
| **`POST <AIP_PREDICT_ROUTE>`** | 默认 `/predict`，JSON 输入输出 |
| **`POST <AIP_EXPLAIN_ROUTE>`**（可选） | 默认 `/explain`，特征归因 |
| **Model artifact 自动 mount** | `AIP_STORAGE_URI` 指向 GCS，容器内 `AIP_MODEL_DIR` |
| **Cold start < 平台 timeout** | 默认 4 分钟 request timeout |

> 缺 `/health` 端点 → 端点永远不健康，流量不来。

---

## 2. 最小可用：FastAPI 推理服务器

### 2.1 `predictor.py`

```python
import os
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import torch

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("predictor")

# ─── Pydantic schemas ───────────────────────────────────
class PredictRequest(BaseModel):
    instances: list  # 客户端发的 JSON: {"instances": [...]}
    parameters: dict | None = None

class PredictResponse(BaseModel):
    predictions: list
    model_version: str = os.environ.get("MODEL_VERSION", "v1")

# ─── Model loading at startup ──────────────────────────
MODEL = None
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

def load_model():
    """Vertex AI mounts AIP_STORAGE_URI to AIP_MODEL_DIR at container start.
    Load once at startup, not per request."""
    model_dir = os.environ["AIP_MODEL_DIR"]  # /tmp/ai-platform-.../model
    log.info(f"Loading model from {model_dir} on {DEVICE}")

    model = MyModel()
    state_dict = torch.load(os.path.join(model_dir, "model.pt"), map_location=DEVICE)
    model.load_state_dict(state_dict)
    model.eval()
    model.to(DEVICE)
    log.info("Model loaded")
    return model

@asynccontextmanager
async def lifespan(app: FastAPI):
    global MODEL
    MODEL = load_model()
    yield

app = FastAPI(lifespan=lifespan)

# ─── Health endpoint (required) ─────────────────────────
@app.get(os.environ.get("AIP_HEALTH_ROUTE", "/health"))
def health():
    if MODEL is None:
        raise HTTPException(503, "Model not loaded")
    return {"status": "ok"}

# ─── Predict endpoint (required) ────────────────────────
@app.post(os.environ.get("AIP_PREDICT_ROUTE", "/predict"))
def predict(req: PredictRequest):
    if MODEL is None:
        raise HTTPException(503, "Model not loaded")
    try:
        inputs = torch.tensor(req.instances, dtype=torch.float32).to(DEVICE)
        with torch.no_grad():
            outputs = MODEL(inputs).cpu().tolist()
        return PredictResponse(predictions=outputs).model_dump()
    except Exception as e:
        log.exception("Predict failed")
        raise HTTPException(500, str(e))

# ─── Explain endpoint (optional) ────────────────────────
@app.post(os.environ.get("AIP_EXPLAIN_ROUTE", "/explain"))
def explain(req: PredictRequest):
    # 用 SHAP / integrated gradients 等
    if MODEL is None:
        raise HTTPException(503, "Model not loaded")
    try:
        explanations = []
        for inst in req.instances:
            x = torch.tensor(inst, dtype=torch.float32).to(DEVICE)
            attr = compute_attribution(MODEL, x)
            explanations.append(attr.cpu().tolist())
        return {"explanations": explanations, "model_version": "v1"}
    except Exception as e:
        log.exception("Explain failed")
        raise HTTPException(500, str(e))
```

### 2.2 启动脚本 `entrypoint_predict.sh`

```bash
#!/bin/bash
set -e

# 读 AIP_HTTP_PORT（Vertex AI 注入，默认 8080）
PORT=${AIP_HTTP_PORT:-8080}

# 多 worker（CPU 服务 2-4 worker，GPU 服务 1 worker per GPU）
WORKERS=${PREDICT_WORKERS:-2}

exec gunicorn predictor:app \
  --workers ${WORKERS} \
  --worker-class uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:${PORT} \
  --timeout 60 \
  --graceful-timeout 30 \
  --access-logfile - \
  --error-logfile -
```

### 2.3 Prediction Dockerfile `Dockerfile.predict`

```dockerfile
# syntax=docker/dockerfile:1.7
ARG PYTHON_VERSION=3.11

FROM python:${PYTHON_VERSION}-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# tini for PID 1 signal forwarding
RUN apt-get update && apt-get install -y --no-install-recommends \
        tini curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1001 app \
    && useradd  --system --uid 1001 --gid app --home-dir /home/app --shell /bin/bash app

WORKDIR /app

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

COPY predictor.py entrypoint_predict.sh ./
RUN chmod +x entrypoint_predict.sh \
    && chown -R app:app /app

USER 1001

EXPOSE 8080

# Vertex AI health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD curl -fsS "http://localhost:${AIP_HTTP_PORT:-8080}/health" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint_predict.sh"]
```

**requirements.txt**:
```
fastapi==0.115.0
uvicorn[standard]==0.30.6
gunicorn==23.0.0
torch==2.3.0
pydantic==2.9.2
```

---

## 3. 构建 + 上传模型 + 部署

### 3.1 Build + push 镜像

```bash
PROJECT=my-gcp-project
REGION=us-central1
REPO=predictor-images
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/mnist-predictor:v1"

gcloud artifacts repositories create ${REPO} \
  --repository-format=docker --location=${REGION} || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev

docker buildx build --platform linux/amd64 -f Dockerfile.predict -t ${IMAGE} --push .
```

### 3.2 上传模型

> 模型 artifact 可以是任何目录结构（最常见：`model.pt` + `config.json` + tokenizer/）

```bash
# 模型已经在 GCS
MODEL_ARTIFACT=gs://${PROJECT}-models/mnist/v1/

# 上传到 Vertex AI Model Registry
gcloud ai models upload \
  --region=${REGION} \
  --display-name=mnist-predictor-v1 \
  --container-image-uri=${IMAGE} \
  --container-ports=8080 \
  --container-health-route=/health \
  --container-predict-route=/predict \
  --container-explain-route=/explain \
  --container-env-vars=MODEL_VERSION=v1,PREDICT_WORKERS=2 \
  --artifact-uri=${MODEL_ARTIFACT} \
  --project=${PROJECT}
```

**关键参数**：
- `container-image-uri`: 你的 BYOC 镜像
- `container-ports`: 必须 = `AIP_HTTP_PORT`（默认 8080）
- `container-health-route`: 跟 `AIP_HEALTH_ROUTE` 一致
- `container-predict-route`: 跟 `AIP_PREDICT_ROUTE` 一致
- `artifact-uri`: 模型 GCS 路径，Vertex AI 自动 mount 到 `AIP_MODEL_DIR`

### 3.3 创建 endpoint + 部署

```bash
# 建 endpoint
ENDPOINT_ID=$(gcloud ai endpoints create \
  --region=${REGION} \
  --display-name=mnist-endpoint \
  --project=${PROJECT} \
  --format="value(name)" | awk -F'/' '{print $NF}')

# 拿 MODEL_ID
MODEL_ID=$(gcloud ai models list \
  --region=${REGION} \
  --filter="displayName=mnist-predictor-v1" \
  --format="value(name)" | awk -F'/' '{print $NF}')

# 部署 model 到 endpoint
gcloud ai endpoints deploy-model ${ENDPOINT_ID} \
  --region=${REGION} \
  --model=${MODEL_ID} \
  --display-name=mnist-v1 \
  --machine-type=n1-standard-2 \
  --min-replica-count=1 \
  --max-replica-count=10 \
  --accelerator-type=NVIDIA_TESLA_T4,accelerator-count=0 \
  --traffic-split=0=100 \
  --service-account=vertex-ai-predictor@${PROJECT}.iam.gserviceaccount.com
```

> 第一次 `accelerator-count=0` 测无 GPU 路径，确认 OK 再加 GPU。

---

## 4. 调用 endpoint

```bash
ENDPOINT_NAME=$(gcloud ai endpoints describe ${ENDPOINT_ID} \
  --region=${REGION} --format="value(name)")

curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  https://${REGION}-aiplatform.googleapis.com/v1/${ENDPOINT_NAME}:predict \
  -d '{
    "instances": [
      [0.1, 0.2, 0.3, ...],
      [0.4, 0.5, 0.6, ...]
    ]
  }'
```

---

## 5. Autoscaling + 性能调优

### 5.1 副本策略

| 参数 | 建议值 | 理由 |
|---|---|---|
| `min-replica-count` | 1-2 | 防冷启动；高峰期需要 |
| `max-replica-count` | 业务峰值 / 单 replica QPS | 避免无限扩展 |
| `machine-type` | CPU 密集 → `n2-highmem` / GPU 推理 → T4/L4 | 按模型选 |
| `accelerator-type` | 大模型（>1B 参数）才用 GPU | 小模型 GPU 不划算 |

### 5.2 冷启动优化

- **Container image 越小越好**：pull 快
- **Model artifact 不要大**（>5GB 用 streaming load）
- **Warm up request**：deploy 后手动发一次请求让模型 load

### 5.3 Concurrency（单 replica 并发）

默认 1（serial processing）。CPU 服务可调高：

```bash
gcloud ai endpoints deploy-model ${ENDPOINT_ID} \
  ... \
  --max-replica-count=10
# 默认每个 request 一个 worker process
# CPU bound 服务调 PREDICT_WORKERS=4
```

GPU 服务一般保持 default（单 GPU per replica）。

---

## 6. A/B 测试 + 流量分配

部署多个 model 版本到同一 endpoint，按比例分流：

```bash
# 部署 v2（同一 IMAGE 不同 artifact）
gcloud ai endpoints deploy-model ${ENDPOINT_ID} \
  --model=${MODEL_V2_ID} \
  --display-name=mnist-v2 \
  --machine-type=n1-standard-2 \
  --min-replica-count=0 \
  --max-replica-count=10 \
  --traffic-split=0=70,1=30  # 70% v1, 30% v2
```

调比例不影响部署：

```bash
gcloud ai endpoints update ${ENDPOINT_ID} \
  --region=${REGION} \
  --traffic-split=0=30,1=70  # 切到 v2
```

> 流量 = 0 的版本会自动 scale 到 0，**省钱**。v2 稳定后把 v1 undeploy。

---

## 7. Batch Prediction（批量推理）

> 适合离线对大 batch 数据推理，结果写 GCS。

```bash
gcloud ai batch-prediction-jobs create \
  --region=${REGION} \
  --display-name=mnist-batch-2024-q1 \
  --model=${MODEL_ID} \
  --input-format=jsonl \
  --input-uris=gs://BUCKET/batch-input/ \
  --output-uris=gs://BUCKET/batch-output/ \
  --machine-type=n1-standard-8 \
  --instances-format=jsonl \
  --predictions-format=jsonl \
  --max-replica-count=20
```

**输入格式**（JSONL）：
```json
{"instances": [0.1, 0.2, 0.3, ...]}
{"instances": [0.4, 0.5, 0.6, ...]}
```

**输出**（GCS `gs://BUCKET/batch-output/prediction-*.jsonl`）：
```json
{"instance": [0.1, 0.2, 0.3, ...], "prediction": [0.8, 0.1, 0.05, 0.05]}
```

> Batch 推理的 BYOC 容器合约和 Online 一样（`/predict`），但不会接受 HTTP 请求——Vertex AI 内部直接调用。

---

## 8. 模型版本管理

### 8.1 版本策略

```
artifact URI:
  gs://models/mnist/v1/   ← 老模型
  gs://models/mnist/v2/   ← 新模型

Vertex AI Model Registry:
  models/mnist-v1   ← 旧 entry，artifact_uri=gs://models/mnist/v1/
  models/mnist-v2   ← 新 entry，artifact_uri=gs://models/mnist/v2/
```

每次训练完 → 上传新 Model entry → deploy 到 endpoint → 灰度切流量。

### 8.2 回滚

```bash
# 100% 切回 v1
gcloud ai endpoints update ${ENDPOINT_ID} \
  --traffic-split=0=100

# 或 undeploy v2
gcloud ai endpoints undeploy-model ${ENDPOINT_ID} \
  --deployed-model-id=${DEPLOYED_MODEL_V2_ID} \
  --region=${REGION}
```

回滚 < 30 秒生效。

---

## 9. 监控

### 9.1 关键 metric

| Metric | 含义 | 告警阈值 |
|---|---|---|
| `prediction/online/response_count` | 请求数 | — |
| `prediction/online/prediction_latency` | p95/p99 延迟 | p99 > SLA |
| `prediction/online/cpu_utilization` | CPU | > 80% |
| `prediction/online/accelerator_duty_cycle` | GPU 利用率 | < 30% 浪费 |
| `prediction/online/error_count` | 错误数 | > 1% |
| `replica_count` | 当前副本数 | = max → scale 触顶 |

### 9.2 自定义 metric

```python
from google.cloud import monitoring_v3

def report_custom_metric(value, metric_type="custom/queue_depth"):
    client = monitoring_v3.MetricServiceClient()
    project_name = f"projects/{PROJECT_ID}"
    series = monitoring_v3.TimeSeries()
    series.metric.type = f"custom.googleapis.com/{metric_type}"
    series.resource.type = "aiplatform.googleapis.com/Endpoint"
    # ... 填充 resource labels ...
    point = monitoring_v3.Point()
    point.value.double_value = value
    series.points = [point]
    client.create_time_series(name=project_name, time_series=[series])
```

---

## 10. 安全 / IAM

### 10.1 Endpoint 访问控制

```bash
# Public endpoint
gcloud ai endpoints create ... --enable-logging

# Private endpoint（不暴露公网）
gcloud ai endpoints create ... \
  --network=projects/${PROJECT}/global/networks/my-vpc \
  --enable-private-service-connect
```

### 10.2 客户端鉴权

Vertex AI endpoint 默认走 OAuth2 鉴权（`gcloud auth print-access-token`）。

生产场景：
- **API Gateway + IAP**：统一入口，加 quota / API key
- **直接用 IAM**：每个客户端用 SA 调用

### 10.3 VPC-SC

把 Vertex AI 包在 VPC Service Perimeter 内：

```bash
gcloud access-context-manager perimeters create vertex_ai_perimeter \
  --title="Vertex AI Perimeter" \
  --resources=projects/${PROJECT} \
  --restricted-services=aiplatform.googleapis.com,artifactregistry.googleapis.com,storage.googleapis.com
```

> 详细 IAM / Workload Identity / VPC-SC 模式见 [`byoc-iam-cicd.md`](./byoc-iam-cicd.md)。

---

## 11. 完整 checklist

- [ ] Dockerfile 监听 `AIP_HTTP_PORT`，`HEALTHCHECK` 指向 `/health`
- [ ] FastAPI/gunicorn 配置 worker 数、timeout
- [ ] 模型在 `AIP_MODEL_DIR`（= `AIP_STORAGE_URI` GCS mount）
- [ ] 镜像 push 到 Artifact Registry（**同 region**）
- [ ] `gcloud ai models upload` 配对 `container-image-uri` + `artifact-uri`
- [ ] Endpoint 创建，model deploy 配 `min/max-replica-count`
- [ ] `/health` 返回 200（看 logs 确认）
- [ ] 调 `:predict` 接口 smoke test
- [ ] Autoscaling 实测（高峰期看 replica_count）
- [ ] 监控 + 告警配齐（p99 latency、error rate）
- [ ] A/B 测试流程跑通（新模型灰度 → 100% → undeploy 旧）
- [ ] 回滚路径明确（traffic-split 或 undeploy）

---

## 下一步

- 训练 → 部署串联：见 [Cloud Build pipeline](./byoc-iam-cicd.md#cloud-build-pipeline)
- 多步 ML：见 [Vertex AI Pipelines](./byoc-iam-cicd.md#vertex-ai-pipelines)
- IAM / 安全 / VPC-SC：见 [byoc-iam-cicd.md](./byoc-iam-cicd.md)
