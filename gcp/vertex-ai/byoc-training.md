# Vertex AI — Custom Training (BYOC) 端到端

> 自定义容器跑训练任务。覆盖：单/多机、checkpointing、Hyperparameter Tuning、gcloud CLI 部署、Dockerfile 模板。

---

## 1. 快速开始：单节点训练

### 1.1 场景

- 单机 GPU 训练 PyTorch 模型
- 输入数据：GCS `gs://BUCKET/training-data/`
- 输出模型：GCS `gs://BUCKET/model-output/`
- 镜像：Artifact Registry `us-central1-docker.pkg.dev/PROJECT/REPO/trainer:v1`

### 1.2 训练脚本 `train.py`（核心片段）

```python
import os
import argparse
import torch
from torch.utils.data import DataLoader
# 业务 imports ...

def get_env(name, default=None):
    val = os.environ.get(name, default)
    if val is None:
        raise RuntimeError(f"Required env var {name} not set")
    return val

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--batch-size", type=int, default=32)
    args = parser.parse_args()

    # Vertex AI 注入的环境变量
    data_dir = get_env("AIP_TRAINING_DATA_URI")       # gs://.../training-data/
    model_dir = get_env("AIP_MODEL_DIR")              # /tmp/ai-platform-.../model
    # AIP_MODEL_DIR 在容器内是 local 路径（Vertex AI 自动 GCS mount）

    # 下载数据（这里演示用 gsutil；生产可以预 mount）
    os.system(f"gsutil -m cp -r {data_dir}/* /tmp/data/")
    train_dataset = MyDataset("/tmp/data")

    loader = DataLoader(train_dataset, batch_size=args.batch_size, shuffle=True)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = MyModel().to(device)
    opt = torch.optim.Adam(model.parameters(), lr=args.lr)

    for epoch in range(args.epochs):
        for batch in loader:
            batch = {k: v.to(device) for k, v in batch.items()}
            loss = model.train_step(batch, opt)
        print(f"epoch {epoch} loss={loss:.4f}")

    # 保存模型到 AIP_MODEL_DIR（Vertex AI 会同步到 GCS）
    torch.save(model.state_dict(), os.path.join(model_dir, "model.pt"))
    print(f"Saved model to {model_dir}")

if __name__ == "__main__":
    main()
```

### 1.3 训练 Dockerfile `Dockerfile.train`

```dockerfile
# syntax=docker/dockerfile:1.7
ARG PYTHON_VERSION=3.11
ARG CUDA_VERSION=12.3.1

# 用 prebuilt 训练 base 省 CUDA 编译痛苦
FROM nvidia/cuda:${CUDA_VERSION}-cudnn8-runtime-ubuntu22.04 AS runtime

ENV PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} python3-pip \
        ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3 /usr/bin/python

WORKDIR /app

# requirements.txt 必须 pin 版本
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir google-cloud-storage

COPY train.py .

# 非 root
RUN groupadd --system --gid 1001 app \
    && useradd  --system --uid 1001 --gid app --home-dir /home/app --shell /bin/bash app \
    && chown -R app:app /app
USER 1001

# Vertex AI 会注入 --args 列表到 ENTRYPOINT
ENTRYPOINT ["python", "train.py"]
```

### 1.4 构建 + 推送

```bash
# 一次性：建 repo
gcloud artifacts repositories create trainer-images \
  --repository-format=docker \
  --location=us-central1 \
  --description="Vertex AI training images"

# 认证 Docker 到 AR
gcloud auth configure-docker us-central1-docker.pkg.dev

# Build + push
PROJECT=my-gcp-project
IMAGE=us-central1-docker.pkg.dev/${PROJECT}/trainer-images/mnist-trainer:v1
docker buildx build --platform linux/amd64 -f Dockerfile.train -t ${IMAGE} --push .
```

### 1.5 提交 Custom Job

```bash
gcloud ai custom-jobs create \
  --region=us-central1 \
  --display-name=mnist-train-v1 \
  --worker-pool-spec=machine-type=n1-standard-8,accelerator-type=NVIDIA_TESLA_T4,accelerator-count=1,replica-count=1,container-image-uri=${IMAGE},container-args=--epochs=20,--lr=0.001 \
  --args=--epochs=20 \
  --service-account=vertex-ai-trainer@${PROJECT}.iam.gserviceaccount.com \
  --project=${PROJECT}
```

**关键参数**：
- `worker-pool-spec`: 机器类型 + GPU + 副本数
- `container-args`: 传给 ENTRYPOINT 的参数
- `service-account`: Job 用的 SA（需有 GCS read/write 权限）

---

## 2. 多机分布式训练

### 2.1 关键概念

Vertex AI Custom Job 支持多 worker pool + 节点间通信：

- **Chief (master)**: rank 0
- **Workers**: rank 1+
- **Parameter servers** (TF 风格，可选)
- 节点间网络：Vertex AI 自动配置（无需自己开端口）
- 共享存储：所有节点挂载同一 GCS path

### 2.2 入口环境变量

| Env var | 含义 |
|---|---|
| `CLUSTER_SPEC` 或 `TF_CONFIG` | Cluster 信息（JSON），含 chief/worker 角色和地址 |
| `MASTER_ADDR` | Chief 节点地址（PyTorch DDP） |
| `MASTER_PORT` | Chief 端口（PyTorch DDP） |
| `RANK` | 当前节点 rank |
| `WORLD_SIZE` | 总节点数 |
| `LOCAL_RANK` | 本地 GPU rank |

### 2.3 torchrun 启动脚本 `train_distributed.py`

```python
import os
import torch
import torch.distributed as dist

def main():
    dist.init_process_group(backend="nccl")
    rank = dist.get_rank()
    world_size = dist.get_world_size()
    local_rank = int(os.environ["LOCAL_RANK"])
    device = torch.device(f"cuda:{local_rank}")
    torch.cuda.set_device(device)

    model = MyModel().to(device)
    model = torch.nn.parallel.DistributedDataParallel(
        model, device_ids=[local_rank]
    )

    # 数据加载用 DistributedSampler
    from torch.utils.data import DataLoader
    from torch.utils.data.distributed import DistributedSampler
    dataset = MyDataset("/tmp/data")
    sampler = DistributedSampler(dataset, num_replicas=world_size, rank=rank)
    loader = DataLoader(dataset, batch_size=32, sampler=sampler)

    for epoch in range(10):
        sampler.set_epoch(epoch)  # 重要：保证每个 epoch shuffle 不同
        for batch in loader:
            batch = {k: v.to(device) for k, v in batch.items()}
            loss = model.train_step(batch)

        # 只有 chief 保存 checkpoint
        if rank == 0:
            torch.save({
                "epoch": epoch,
                "model_state": model.module.state_dict(),
                "opt_state": opt.state_dict(),
            }, f"/tmp/checkpoints/epoch_{epoch}.pt")
            print(f"[rank 0] saved checkpoint epoch {epoch}")

    dist.destroy_process_group()

if __name__ == "__main__":
    main()
```

### 2.4 torchrun 入口 `entrypoint.sh`

```bash
#!/bin/bash
set -e

# Vertex AI 自动设置这些
echo "WORLD_SIZE=${WORLD_SIZE}"
echo "RANK=${RANK}"
echo "MASTER_ADDR=${MASTER_ADDR}"

exec torchrun \
  --nproc_per_node=${LOCAL_WORLD_SIZE:-1} \
  --nnodes=${WORLD_SIZE} \
  --node_rank=${RANK} \
  --master_addr=${MASTER_ADDR} \
  --master_port=${MASTER_PORT:-29500} \
  /app/train_distributed.py \
  "$@"
```

### 2.5 Dockerfile 调整

```dockerfile
# ... 同 §1.3
# 额外安装 torch + nccl
RUN pip install --no-cache-dir torch==2.3.0+cu121 \
    --index-url https://download.pytorch.org/whl/cu121

# 复制 torchrun entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER 1001
ENTRYPOINT ["/entrypoint.sh"]
```

### 2.6 gcloud 多机提交

```bash
gcloud ai custom-jobs create \
  --region=us-central1 \
  --display-name=mnist-distributed-v1 \
  --worker-pool-spec=machine-type=n1-standard-8,accelerator-type=NVIDIA_TESLA_T4,accelerator-count=1,replica-count=1,container-image-uri=${IMAGE} \
  --worker-pool-spec=machine-type=n1-standard-8,accelerator-type=NVIDIA_TESLA_T4,accelerator-count=1,replica-count=3,container-image-uri=${IMAGE} \
  --service-account=vertex-ai-trainer@${PROJECT}.iam.gserviceaccount.com
```

> 第一个 worker pool 是 **chief**（spec 1 个），第二个是 **workers**（spec 3 个）。共 4 节点（1 chief + 3 workers）。
> 每个 worker pool 可独立配机器类型/GPU。

---

## 3. Checkpoint + Resume（防 Preemption）

> Vertex AI 用 **preemptible GPU** 时（成本降 60-80%），节点会被回收。需要 checkpoint + resume。

### 3.1 关键环境变量

- `AIP_CHECKPOINT_DIR`: Vertex AI 提供的 GCS path，自动挂载到容器 `/gcs/<bucket>/...`
- 定期保存到 `AIP_CHECKPOINT_DIR`，Job 恢复时从最新 checkpoint 续跑

### 3.2 Resume 模式

```python
import os
import glob
import torch

CHECKPOINT_DIR = os.environ.get("AIP_CHECKPOINT_DIR", "/tmp/checkpoints")

def latest_checkpoint():
    if not os.path.exists(CHECKPOINT_DIR):
        return None
    ckpts = sorted(glob.glob(os.path.join(CHECKPOINT_DIR, "*.pt")))
    return ckpts[-1] if ckpts else None

def main():
    start_epoch = 0
    ckpt_path = latest_checkpoint()
    if ckpt_path:
        print(f"Resuming from {ckpt_path}")
        ckpt = torch.load(ckpt_path)
        start_epoch = ckpt["epoch"] + 1
        model.load_state_dict(ckpt["model_state"])
        opt.load_state_dict(ckpt["opt_state"])

    for epoch in range(start_epoch, TOTAL_EPOCHS):
        # ... train ...
        # 每个 epoch 保存
        if rank == 0:
            ckpt_path = os.path.join(CHECKPOINT_DIR, f"epoch_{epoch}.pt")
            torch.save({...}, ckpt_path)
            # 清理旧 ckpt 防止 GCS 满
            old = os.path.join(CHECKPOINT_DIR, f"epoch_{epoch-3}.pt")
            if os.path.exists(old):
                os.remove(old)
```

### 3.3 Vertex AI 自动 resume

- `gcloud ai custom-jobs create --restart-job-on-worker-restart`（**仅 master 重启用**）
- 节点被 preemption 时，**整个 job 会失败**（除非你用 KFP 或外部 orchestrator 重提）
- 真正可靠的 resume：用 **KFP + Custom Job** 编排，KFP 检测到失败自动重提

---

## 4. Hyperparameter Tuning

### 4.1 概念

Vertex AI HyperparameterTuningJob 包装 Custom Job，自动跑 N 次 trial + 贝叶斯优化。

### 4.2 提交

```bash
gcloud ai hp-tuning-jobs create \
  --region=us-central1 \
  --display-name=mnist-hpt-v1 \
  --max-trial-count=20 \
  --parallel-trial-count=4 \
  --max-failed-trial-count=3 \
  --algorithm=BAYESIAN_OPTIMIZATION \
  --custom-job-spec=worker-pool-spec=machine-type=n1-standard-8,accelerator-type=NVIDIA_TESLA_T4,accelerator-count=1,replica-count=1,container-image-uri=${IMAGE} \
  --service-account=vertex-ai-trainer@${PROJECT}.iam.gserviceaccount.com
```

### 4.3 训练脚本报告 metric

```python
import hypertune

hpt = hypertune.HyperTune()

for trial_params in trial_loop():
    # 训练用 trial_params...
    hpt.report_hyperparameter_tuning_metric(
        hyperparameter_metric_tag="val_accuracy",
        metric_value=val_accuracy,
        global_step=epoch,
    )
```

> 训练脚本需要 `pip install hypertune`（Vertex AI prebuilt 容器自带，BYOC 需要自己装）。

---

## 5. 数据 + 模型 GCS 路径

| 类型 | Env var | 容器内路径 | 用途 |
|---|---|---|---|
| 训练数据 | `AIP_TRAINING_DATA_URI` | gs://.../data/ | 读输入 |
| 模型输出 | `AIP_MODEL_DIR` | 本地路径（自动 GCS mount） | 写最终模型 |
| Checkpoint | `AIP_CHECKPOINT_DIR` | 本地路径（自动 GCS mount） | 写中间 ckpt |
| 预处理数据 | 自定义 | `gs://.../preprocessed/` | Feature Store / 中间产物 |

> **重要**：`AIP_MODEL_DIR` 和 `AIP_CHECKPOINT_DIR` 在容器内是 **本地路径**，但 Vertex AI 用 gcsfuse mount 到容器，写入会自动同步到 GCS。**不要**用 `gsutil cp` 拷数据到这些目录——直接写文件即可。

---

## 6. IAM 最小权限

训练 Job 用的 Service Account 至少需要：

```bash
PROJECT=my-gcp-project
SA=vertex-ai-trainer@${PROJECT}.iam.gserviceaccount.com

# 读训练数据
gsutil iam ch serviceAccount:${SA}:objectViewer gs://BUCKET/training-data

# 写模型 + checkpoint
gsutil iam ch serviceAccount:${SA}:objectCreator gs://BUCKET/model-output
gsutil iam ch serviceAccount:${SA}:objectCreator gs://BUCKET/checkpoints
```

更细的（推荐）：用 **Workload Identity** 绑到 GKE SA，由 K8s RBAC 控制。详见 [`byoc-iam-cicd.md`](./byoc-iam-cicd.md)。

---

## 7. 监控 + 调试

### 7.1 看日志

```bash
# 实时日志
gcloud ai custom-jobs stream-logs JOB_ID --region=us-central1

# TensorBoard（Vertex AI Experiments 自动集成）
# 训练时把 tf.summary / tensorboardX 写入 AIP_TENSORBOARD_LOG_DIR
```

### 7.2 常见 error

| Error | 原因 | 修复 |
|---|---|---|
| `AIP_TRAINING_DATA_URI not set` | Job spec 没指定训练数据 URI | `custom-job-spec` 加 `--training-data-uri` |
| `permission denied on GCS` | SA 缺权限 | `gsutil iam ch` 授权 |
| `CUDA out of memory` | batch 太大 | 减小 `--batch-size` |
| `No space left on device` | `/tmp` 满 | checkpoint 定期清理；GCS 路径放外部 |
| `torch.distributed init timeout` | MASTER_PORT 不通 | 检查 worker pool spec |

### 7.3 快速复现：本地跑同一 image

```bash
docker run --rm -it \
  --gpus all \
  -e AIP_TRAINING_DATA_URI=gs://BUCKET/training-data \
  -e AIP_MODEL_DIR=/tmp/model \
  -e AIP_CHECKPOINT_DIR=/tmp/checkpoints \
  -v /tmp/model:/tmp/model \
  -v /tmp/checkpoints:/tmp/checkpoints \
  ${IMAGE} --epochs=2
```

> 缺 Vertex AI 自动注入的 `TF_CONFIG`/`CLUSTER_SPEC`，单机训练可以忽略。

---

## 8. 完整端到端 checklist

- [ ] Artifact Registry repo 建好（`gcloud artifacts repositories create`）
- [ ] Dockerfile 包含所有依赖，`pip install hypertune`（如用 HPT）
- [ ] Image push 到 AR，本地 smoke test 通过
- [ ] Service Account 建好 + 授 GCS 权限
- [ ] 训练脚本尊重 `AIP_TRAINING_DATA_URI` / `AIP_MODEL_DIR` / `AIP_CHECKPOINT_DIR`
- [ ] 多机训练：`entrypoint.sh` 用 `torchrun` + 读 `WORLD_SIZE/RANK/MASTER_ADDR`
- [ ] HPT：脚本 `hpt.report_hyperparameter_tuning_metric`
- [ ] 提交 `gcloud ai custom-jobs create` 或 `hp-tuning-jobs create`
- [ ] 看日志（`stream-logs`）+ TensorBoard 监控
- [ ] 模型输出在 GCS `AIP_MODEL_DIR`（Job 完成后）

---

## 下一步

- 模型训练完 → 走 [Custom Prediction](./byoc-prediction.md) 部署
- 频繁训练 + 部署 → 走 [Cloud Build pipeline](./byoc-iam-cicd.md#cloud-build-pipeline)
- 多步 ML workflow → [Vertex AI Pipelines](./byoc-iam-cicd.md#vertex-ai-pipelines)
