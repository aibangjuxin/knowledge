# Vertex AI — IAM / CI/CD / Pipelines / Gotchas

> BYOC 在生产环境需要解决的横切问题：IAM 最小权限、CI/CD 串联、KFP 编排、平台 gotcha。

---

## 1. IAM 最小权限（按角色）

### 1.1 Service Account 设计

| SA | 用途 | 关键权限 |
|---|---|---|
| `vertex-ai-trainer@PROJECT.iam` | 跑 Custom Training Job | GCS read/write on data + model bucket |
| `vertex-ai-predictor@PROJECT.iam` | 跑 Prediction Container | GCS read on model bucket, optional Cloud Logging writer |
| `vertex-ai-pipeline@PROJECT.iam` | 跑 Vertex AI Pipelines | 上述两者 + Vertex AI Pipeline Runner |
| `cloud-build@PROJECT.iam` | Cloud Build 跑 build + deploy | AR writer, Vertex AI Job Creator |

> **永远不要**用 default Compute Engine SA。**永远不要**给 `roles/owner`。

### 1.2 建 SA + 授权

```bash
PROJECT=my-gcp-project

# 建 SA
for sa in trainer predictor pipeline; do
  gcloud iam service-accounts create vertex-ai-${sa} \
    --display-name="Vertex AI ${sa}" \
    --project=${PROJECT}
done

# 给 trainer GCS 权限
TRAINER_SA=vertex-ai-trainer@${PROJECT}.iam.gserviceaccount.com
gsutil iam ch serviceAccount:${TRAINER_SA}:objectViewer gs://${PROJECT}-training-data
gsutil iam ch serviceAccount:${TRAINER_SA}:objectCreator gs://${PROJECT}-model-output

# 给 predictor 只读模型
PRED_SA=vertex-ai-predictor@${PROJECT}.iam.gserviceaccount.com
gsutil iam ch serviceAccount:${PRED_SA}:objectViewer gs://${PROJECT}-models
```

### 1.3 Custom Job / Endpoint 引用 SA

```bash
gcloud ai custom-jobs create ... --service-account=${TRAINER_SA}
gcloud ai endpoints deploy-model ... --service-account=${PRED_SA}
```

---

## 2. Workload Identity（GKE 上的训练）

### 2.1 场景

- Custom Training Job 实际跑在 **Vertex AI 托管的 GKE** 集群
- Job 里的容器要访问 GCS / BigQuery / Secret Manager
- 想用 **K8s SA 联邦到 GCP SA** 的模式（Workload Identity）

### 2.2 模式

```
K8s SA (default in namespace "training") 
  ↓ federated with
GCP SA (vertex-ai-trainer@PROJECT.iam)
  ↓ impersonated by
Container (uses GOOGLE_APPLICATION_CREDENTIALS auto from metadata server)
```

### 2.3 绑定（Vertex AI 内部已经帮你做了一部分）

Vertex AI Custom Job 用的 SA 是你在 spec 里指定的 `service-account`。容器内通过 metadata server 拿到 token，**不需要** Workload Identity binding——Vertex AI 内部已经做了。

> **Workload Identity 主要是当你自己用 GKE 跑 training 时**才需要手动绑。

### 2.4 自建 GKE 训练（不用 Vertex AI 托管）

```bash
PROJECT=my-gcp-project
K8S_SA=training-sa
GCP_SA=vertex-ai-trainer@${PROJECT}.iam.gserviceaccount.com
NAMESPACE=training

# 1. 给 K8s SA 绑 GCP SA
gcloud iam service-accounts add-iam-policy-binding ${GCP_SA} \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT}.svc.id.goog[${NAMESPACE}/${K8S_SA}]"

# 2. 标 K8s SA
kubectl annotate serviceaccount ${K8S_SA} \
  -n ${NAMESPACE} \
  iam.gke.io/gcp-service-account=${GCP_SA}
```

Pod 里的 application 就不用挂 JSON key——自动从 metadata server 拿 token。

---

## 3. VPC Service Controls (VPC-SC)

### 3.1 为什么需要

Vertex AI 默认走公网 endpoint。**敏感项目**需要：
- 训练数据不能离开 GCP trust boundary
- 模型 artifact 不能被外部 project 拉
- Endpoint 拒绝公网访问

### 3.2 配置

```bash
# 建 Access Level（条件：特定 IP / 设备 / user）
gcloud access-context-manager levels create vertex_ai_access \
  --title="Trusted Engineers" \
  --basic-level-spec-condition-ipSubnetworks=10.0.0.0/8 \
  --policy=POLICY_ID

# 建 Perimeter
gcloud access-context-manager perimeters create vertex_perimeter \
  --title="Vertex AI Perimeter" \
  --resources=projects/${PROJECT_NUM} \
  --restricted-services=aiplatform.googleapis.com,artifactregistry.googleapis.com,storage.googleapis.com \
  --access-levels=accessPolicies/POLICY_ID/accessLevels/vertex_ai_access \
  --policy=POLICY_ID
```

### 3.3 训练 + 推理的影响

- **Artifact Registry**：必须用 **同 VPC 的私有 endpoint**（AR 自带）
- **GCS Bucket**：必须用 **同 VPC 私有 endpoint** 或 **VPC-SC protected bucket**
- **Custom Job**：spec 里指定 `--network=projects/PROJECT/global/networks/VPC` + `--enable-web-access=false`（如果还需要公网拉 deps，单独开 Cloud NAT）
- **Endpoint**：用 `--enable-private-service-connect` 部署私有 endpoint

---

## 4. Cloud Build Pipeline

### 4.1 场景

```
GitHub push → Cloud Build trigger
              ↓
         Build image
              ↓
         Push to Artifact Registry
              ↓
         Run smoke test (gcloud ai custom-jobs create --dry-run 验证 spec)
              ↓
         Deploy to staging endpoint
              ↓
         Run integration test
              ↓
         Manual approval → deploy to prod
```

### 4.2 `cloudbuild.yaml`

```yaml
# Build + push + submit training
steps:
  # ── Step 1: build training image ──
  - id: build-train
    name: gcr.io/cloud-builders/docker
    args:
      - buildx
      - build
      - --platform=linux/amd64
      - --tag=${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/trainer:${SHORT_SHA}
      - --cache-from=${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/trainer:buildcache
      - --cache-to=type=registry,ref=${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/trainer:buildcache,mode=max
      - --push
      - -f
      - Dockerfile.train
      - .

  # ── Step 2: build predictor image ──
  - id: build-predict
    name: gcr.io/cloud-builders/docker
    args:
      - buildx
      - build
      - --platform=linux/amd64
      - --tag=${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/predictor:${SHORT_SHA}
      - --push
      - -f
      - Dockerfile.predict
      - .

  # ── Step 3: submit training job ──
  - id: train
    name: gcr.io/google.com/cloudsdktool/cloud-sdk:slim
    entrypoint: gcloud
    args:
      - ai
      - custom-jobs
      - create
      - --region=${_REGION}
      - --display-name=train-${SHORT_SHA}
      - --worker-pool-spec=machine-type=n1-standard-8,accelerator-type=NVIDIA_TESLA_T4,accelerator-count=1,replica-count=1,container-image-uri=${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/trainer:${SHORT_SHA}
      - --service-account=vertex-ai-trainer@${PROJECT_ID}.iam.gserviceaccount.com
      - --async
      - --format=value(name)
    dir: .

  # ── Step 4: wait for training to finish (poll) ──
  - id: wait-train
    name: gcr.io/google.com/cloudsdktool/cloud-sdk:slim
    entrypoint: bash
    args:
      - -c
      - |
        JOB_NAME=$$(cat _train_job_name)
        for i in {1..60}; do
          STATE=$$(gcloud ai custom-jobs describe $$JOB_NAME --region=${_REGION} --format="value(state)")
          echo "Job state: $$STATE"
          if [ "$$STATE" = "JOB_STATE_SUCCEEDED" ]; then exit 0; fi
          if [ "$$STATE" = "JOB_STATE_FAILED" ] || [ "$$STATE" = "JOB_STATE_CANCELLED" ]; then exit 1; fi
          sleep 60
        done
        exit 1

  # ── Step 5: upload model to registry ──
  - id: upload-model
    name: gcr.io/google.com/cloudsdktool/cloud-sdk:slim
    entrypoint: gcloud
    args:
      - ai
      - models
      - upload
      - --region=${_REGION}
      - --display-name=mnist-${SHORT_SHA}
      - --container-image-uri=${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/predictor:${SHORT_SHA}
      - --container-ports=8080
      - --container-health-route=/health
      - --container-predict-route=/predict
      - --artifact-uri=gs://${PROJECT_ID}-model-output/

  # ── Step 6: deploy to staging endpoint (50% traffic) ──
  - id: deploy-staging
    name: gcr.io/google.com/cloudsdktool/cloud-sdk:slim
    entrypoint: bash
    args:
      - -c
      - |
        set -e
        MODEL_ID=$$(gcloud ai models list --region=${_REGION} --filter="displayName=mnist-${SHORT_SHA}" --format="value(name)" | awk -F'/' '{print $$NF}')
        DEPLOYED_ID=$$(gcloud ai endpoints deploy-model ${_ENDPOINT_ID} \
          --region=${_REGION} \
          --model=$$MODEL_ID \
          --display-name=staging-${SHORT_SHA} \
          --machine-type=n1-standard-2 \
          --min-replica-count=0 \
          --max-replica-count=5 \
          --traffic-split=0=50,NEW=50 \
          --format="value(deployedModels[0].id)")
        echo $$DEPLOYED_ID > _staging_deploy_id

  # ── Step 7: integration test ──
  - id: integration-test
    name: gcr.io/cloud-builders/gcloud
    entrypoint: bash
    args:
      - -c
      - |
        set -e
        ENDPOINT_NAME=$$(gcloud ai endpoints describe ${_ENDPOINT_ID} --region=${_REGION} --format="value(name)")
        TOKEN=$$(gcloud auth print-access-token)
        for i in {1..10}; do
          RESPONSE=$$(curl -sS -X POST \
            -H "Authorization: Bearer $$TOKEN" \
            -H "Content-Type: application/json" \
            "https://${_REGION}-aiplatform.googleapis.com/v1/$$ENDPOINT_NAME:predict" \
            -d '{"instances": [[0.1, 0.2, 0.3, 0.4]]}')
          echo "Response: $$RESPONSE"
          if echo "$$RESPONSE" | grep -q "predictions"; then exit 0; fi
          sleep 10
        done
        exit 1

  # ── Step 8: promote to prod (manual approval) ──
  - id: promote-prod
    name: gcr.io/google.com/cloudsdktool/cloud-sdk:slim
    entrypoint: bash
    args:
      - -c
      - |
        # 这里可以接 manual approval，或脚本化灰度
        # 灰度：先 10% → 监控 → 50% → 100%
        DEPLOYED_ID=$$(cat _staging_deploy_id)
        gcloud ai endpoints update ${_ENDPOINT_ID} \
          --region=${_REGION} \
          --traffic-split=0=90,${DEPLOYED_ID}=10
        echo "Deployed to prod at 10% traffic"
        # 监控 OK 后人工/脚本推到 100%

# ── Substitutions ──
substitutions:
  _REGION: us-central1
  _REPO: vertex-ai-images
  _ENDPOINT_ID: 1234567890123456789  # 实际 endpoint ID

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: E2_HIGHCPU_8
  defaultLogsBucketBehavior: REGIONAL_USER_OWNED_BUCKET

timeout: 7200s  # 2h

images:
  - ${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/trainer:${SHORT_SHA}
  - ${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/predictor:${SHORT_SHA}
```

### 4.3 触发器

```bash
# GitHub push trigger
gcloud builds triggers create github \
  --repo-name=my-ml-repo \
  --repo-owner=my-org \
  --branch-pattern="^main$" \
  --build-config=cloudbuild.yaml
```

---

## 5. Vertex AI Pipelines (KFP v2)

### 5.1 场景

把多个步骤串成 DAG：
```
[data prep] → [train] → [evaluate] → [if good: deploy]
```

每个 step 跑在 BYOC container（你定义）/ prebuilt / 组件 marketplace。

### 5.2 最小 pipeline

```python
from kfp import dsl, compiler

@dsl.component(base_image="python:3.11")
def preprocess_op(input_uri: str, output_uri: str):
    import os
    # 下载 + 预处理 + 上传
    os.system(f"gsutil -m cp -r {input_uri}/* /tmp/raw/")
    # ... 业务处理 ...
    os.system(f"gsutil -m cp -r /tmp/processed/* {output_uri}/")

@dsl.component(base_image="python:3.11")
def train_op(
    data_uri: str,
    model_dir: str,
    epochs: int = 10,
):
    from train import main
    # 训练逻辑
    main(epochs=epochs, data_uri=data_uri, model_dir=model_dir)

@dsl.component(base_image="python:3.11", packages_to_install=["google-cloud-aiplatform"])
def deploy_op(model_id: str, endpoint_id: str):
    from google.cloud import aiplatform
    aiplatform.init(project="my-project", location="us-central1")
    endpoint = aiplatform.Endpoint(endpoint_id)
    endpoint.deploy(model=aiplatform.Model(model_id))

@dsl.pipeline(
    name="mnist-training-pipeline",
    description="Train + deploy MNIST classifier",
)
def pipeline(
    data_uri: str = "gs://my-bucket/data/",
    epochs: int = 20,
    endpoint_id: str = "12345",
):
    preprocess_task = preprocess_op(
        input_uri=data_uri,
        output_uri="gs://my-bucket/processed/",
    )

    train_task = train_op(
        data_uri=preprocess_task.outputs["output_uri"],
        model_dir="gs://my-bucket/model/",
        epochs=epochs,
    ).set_cpu_limit("8").set_memory_limit("32G").add_node_selector_constraint(
        "cloud.google.com/gke-accelerator", "NVIDIA_TESLA_T4"
    )

    # 条件：val_accuracy > 0.9 才部署
    with dsl.Condition(train_task.outputs["val_accuracy"] > 0.9):
        deploy_op(
            model_id=train_task.outputs["model_id"],
            endpoint_id=endpoint_id,
        )

# Compile
compiler.Compiler().compile(pipeline_func=pipeline, package_path="pipeline.json")

# Submit
from google.cloud import aiplatform
aiplatform.init(project="my-project", location="us-central1")
job = aiplatform.PipelineJob(
    display_name="mnist-pipeline-run-1",
    template_path="pipeline.json",
    parameter_values={"data_uri": "gs://my-bucket/data/", "epochs": 30},
)
job.run(service_account="vertex-ai-pipeline@my-project.iam.gserviceaccount.com")
```

### 5.3 BYOC component

`@dsl.component(base_image="us-central1-docker.pkg.dev/PROJECT/REPO/trainer:v1")` 直接用 BYOC 镜像。

### 5.4 Pipeline runtime config

```python
# Pipeline root for artifacts
job = aiplatform.PipelineJob(
    template_path="pipeline.json",
    pipeline_root="gs://my-bucket/pipeline-root/",  # artifacts
)
```

---

## 6. 常见 gotchas

### 6.1 镜像相关

| Gotcha | 修复 |
|---|---|
| `ImagePullBackOff` | Artifact Registry 权限没给、image 在不同 region |
| `exec format error` | `--platform linux/amd64` 重新 build（arm64 Mac 默认 build 出 arm64） |
| `No CUDA GPUs available` | 镜像无 nvidia runtime、worker pool spec 没加 accelerator |
| Container 启动慢（cold start > 4 min） | 缩 image（multi-stage、distroless）、减 `AIP_MODEL_DIR` 大小 |

### 6.2 训练相关

| Gotcha | 修复 |
|---|---|
| `AIP_MODEL_DIR not set` | 训练时显式 export 或用 `AIP_MODEL_DIR=/tmp/model` |
| 多机 `torch.distributed init timeout` | worker pool spec 错（chief/worker 比例不对），或网络被 VPC 防火墙拦 |
| HPT 不收敛 | 调 `parallel-trial-count` ≤ max-trial-count / 2；增加 `max-failed-trial-count` |
| Preemption 后 Job 失败 | 用 KFP + Vertex AI Pipeline 编排 + restart policy |
| GPU 节点空闲但 job 不调度 | quota 不够 → 申请 GPU quota |

### 6.3 推理相关

| Gotcha | 修复 |
|---|---|
| Endpoint 一直 `PROVISIONING` | 镜像启动失败，看 logs 排查（HEALTHCHECK 失败最常见） |
| `404 Not Found` on `/predict` | `container-predict-route` 跟代码不匹配 |
| Cold start 30s+ | 镜像 > 2GB → 用 multi-stage + slim base |
| 单 replica QPS 上不去 | `min-replica-count` 提高，或 `--max-replica-count` 调大 |
| GPU 浪费 | model 太简单不该用 GPU；或 `accelerator-count=0` |

### 6.4 IAM / 安全相关

| Gotcha | 修复 |
|---|---|
| `permission denied` on GCS | SA 缺 `objectViewer` / `objectCreator` |
| VPC-SC 拒绝请求 | 把 Vertex AI 加进 perimeter，AR/GCS 配同 VPC 私有 endpoint |
| Endpoint 走公网 | 部署时加 `--network=...` + `--enable-private-service-connect` |
| SA token 过期 | Custom Job 短跑（< 1h）不会过期；长跑考虑 Workload Identity + 短期 token |

### 6.5 平台限制

| 限制 | 值 |
|---|---|
| Custom Job 单任务最长时间 | 7 天（默认 7 天） |
| GPU 类型 | A100 / H100 / T4 / L4 等（按 region 可用性） |
| Endpoint max replica | 取决于 region + quota |
| Custom container image 大小 | 推荐 < 5GB（拉镜像延迟） |
| Vertex AI Model Registry 上限 | 每个 project 默认 100 models |
| Pipeline 步骤上限 | 1000 steps |
| Pipeline 最长 runtime | 7 天 |

---

## 7. 完整 cross-cutting checklist

- [ ] Service Account 最小权限（4 个 SA 分工）
- [ ] GCS bucket 按用途分（data / model / checkpoint / pipeline-root）
- [ ] VPC-SC 配置（如有合规要求）
- [ ] Cloud Build 触发器 + 全流程（build → train → eval → deploy）
- [ ] 监控 + 告警（latency / error / cost / GPU util）
- [ ] A/B 测试流程（traffic-split）
- [ ] 回滚流程（traffic-split 0=100 / undeploy）
- [ ] Cost 监控（GPU hours、Bucket size、Egress）
- [ ] Preemption 容忍（KFP + checkpoint）
- [ ] 文档：架构图、Runbook、Oncall 手册

---

## 相关

- 训练：[`byoc-training.md`](./byoc-training.md)
- 推理：[`byoc-prediction.md`](./byoc-prediction.md)
- 概念：[`../../cloud/docker/byoc/`](../../cloud/docker/byoc/)
- GKE Workload Identity：见 `../gke/` 子目录
- GCS 安全：`../storage/` 子目录
