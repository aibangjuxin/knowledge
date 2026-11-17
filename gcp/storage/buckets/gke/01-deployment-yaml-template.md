# 01 · Deployment YAML 完整模板(跨 project 访问 Bucket)

> **本节是业务方视角的"怎么写 Deployment 跨 project 写 Bucket"的完整参考**
>
> **架构师 lane 边界**:本文档**只生成 YAML 模板 + 字段注释**,**不执行 apply**。实际 `kubectl apply` 由 infra-gcp 用专属 SA 执行。

---

## 1. 最简模板(业务方可直接套用)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-with-bucket           # ← 业务方命名
  namespace: api-ns              # ← 业务方指定 namespace
  labels:
    app: api
    role: bucket-writer          # ← 必须有这个 label,审计用
    tenant: tnt-001             # ← 业务方 tenant ID
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
      role: bucket-writer
  template:
    metadata:
      labels:
        app: api
        role: bucket-writer
        tenant: tnt-001
    spec:
      # 关键:KSA 名字(infra-gcp 创建 KSA + 绑 WIF annotation)
      serviceAccountName: api-bucket-writer
      containers:
      - name: api
        image: <业务方镜像:tag>      # ← 业务方填
        ports:
        - containerPort: 8080
        env:
        - name: BUCKET_NAME
          value: gs://user-data      # ← user-bucket-project 的 bucket
        - name: OBJECT_PREFIX
          value: api-data/           # ← 与 IAM condition 对齐
        # ⚠ 红线 2:不要 hardcode user data / object name / file path
        # ⚠ 红线 2:应用代码不能写 logger.info(f"uploaded {object_name}")
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
```

**关键**:Pod spec 里**完全不需要**:
- ❌ `GOOGLE_APPLICATION_CREDENTIALS` 环境变量
- ❌ SA key 挂 Secret
- ❌ 任何 IAM policy 引用

业务方只需要写 `serviceAccountName` + 镜像 + 业务参数。

---

## 2. 字段注释

| 字段 | 值 | 为什么 |
|---|---|---|
| `metadata.labels.role: bucket-writer` | **必须有** | 审计 + 4 红线 CI 检查 |
| `metadata.labels.tenant: tnt-XXX` | 业务方指定 | BigQuery 归因 |
| `spec.replicas: 1` | **默认 1** | 多副本 = 多 Pod 共享 KSA 写 Bucket,横向访问面变大 |
| `spec.template.spec.serviceAccountName: api-bucket-writer` | **关键** | infra-gcp 创建这个 KSA 并绑 WIF annotation |
| `env.BUCKET_NAME` | **完整 gs:// 路径** | SDK 直接用 |
| `env.OBJECT_PREFIX` | **与 IAM condition 对齐** | 防止越界写 |

---

## 3. 安全要点(4 条红线自检)

写完 Deployment 后,业务方/Platform review 必跑:

```bash
# 红线 1:Bucket 写 = 档 1 红线,业务方必须先 PM 评估(部署前人工确认)

# 红线 2:不写 log / metric 暴露
grep -E "object.*path|gs://" deployment.yaml log_schema.yaml
# 期望:无业务 object name 命中(mount path / env 中的 gs:// 是合法的)

# 红线 3:不主动观察用户行为
# 由 Cloud Audit Logs 自动处理(不可关闭),业务方确认知情

# 红线 4:Pod lifecycle 与 Bucket 解耦
grep -E "configMapRef.*bucket|secretRef.*bucket" deployment.yaml
# 期望:无命中
```

---

## 4. 常见错误(实战避坑清单)

### ❌ 错误 1:硬编码 SA key 挂 Secret

```yaml
# ❌ 不要这么写
volumes:
- name: google-cloud-key
  secret:
    secretName: gcp-sa-key
env:
- name: GOOGLE_APPLICATION_CREDENTIALS
  value: /var/secrets/google/key.json
# ← 严重违反 ADR-011 §6 红线 + Google 不推荐
```

**修正**:**完全删除这个 volume 和 env**,只用 `serviceAccountName`。

### ❌ 错误 2:业务方 YAML 里直接写 IAM policy

```yaml
# ❌ 不要在 Deployment YAML 里写 IAM
annotations:
  iam.gke.io/gcp-service-account: my-sa@user-bucket-project.iam.gserviceaccount.com
# ← 这是 KSA YAML 字段,不是 Deployment 字段
```

**修正**:**WIF annotation 在 KSA 上,不在 Deployment 上**(详见 `02-ksa-with-wif-annotation.yaml`)。

### ❌ 错误 3:`replicas: 3` 但没说明理由

```yaml
# ❌ 不要这么写
replicas: 3  # 多 Pod 共享 KSA 写 Bucket,横向访问面放大
```

**修正**:默认 `replicas: 1`。多副本 = 业务方额外写评估。

### ❌ 错误 4:`bucket/object` 写死

```yaml
# ❌ 不要 hardcode 具体的 object 路径
env:
- name: FILE_PATH
  value: "gs://user-data/api-data/2026/08/31/foo.csv"
# ← hardcode 路径 = 路径变更要重新部署
```

**修正**:只 hardcode `prefix`,具体路径由应用代码根据业务逻辑生成。

---

## 5. 业务方自检清单(提交前)

- [ ] `role: bucket-writer` label 加上
- [ ] `tenant: tnt-XXX` label 加上
- [ ] `replicas: 1`(默认)
- [ ] `serviceAccountName: api-bucket-writer`(业务方专用 KSA)
- [ ] **不含** SA key / Secret mount
- [ ] **不含** `GOOGLE_APPLICATION_CREDENTIALS` 环境变量
- [ ] 应用代码不写 `logger.info(f"uploaded {object_name}")`
- [ ] 不挂 ConfigMap / Secret 引用 Bucket 内容
- [ ] Pod 镜像固定 tag(不能 `latest`)
- [ ] **PM + Manager 评估完成**(档 1 红线审批)

**全部 ✅ 才交给 infra-gcp 评审 + 执行**。

---

## 6. 实际可用的 YAML 示例

业务方可直接复制 → [`examples/deployment-with-bucket.yaml`](./examples/deployment-with-bucket.yaml)。

---

## 7. 下一步

- 业务方完成自检清单 → 提交给 infra-gcp
- infra-gcp 评审 + 创建 KSA + 配置 WIF + 配 IAM policy → 推到 dev cluster 测试
- qa-gcp 端到端验证(身份链 + 跨 project 访问 + 红线自检)
- 通过 → 生产 + 监控

完整流程见 [`03-full-flow-process.md`](./03-full-flow-process.md)。