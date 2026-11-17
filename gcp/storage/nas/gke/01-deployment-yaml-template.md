# 01 · Deployment YAML 完整模板 + 字段注释 + 安全要点

> **本节是业务方视角的"怎么写 Deployment 挂 NAS"的完整参考**
>
> **架构师 lane 边界**:本文档**只生成 YAML 模板 + 字段注释**,**不执行 apply**。实际 `kubectl apply` 由 infra-gcp 用专属 SA 执行(详见 [README.md](./README.md))。

---

## 1. 最简模板(业务方可直接套用)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-with-nas              # ← 业务方命名
  namespace: api-ns              # ← 业务方指定 namespace
  labels:
    app: api
    role: nas-consumer           # ← 必须有这个 label,NetworkPolicy 用
    tenant: tnt-001             # ← 业务方指定 tenant
spec:
  replicas: 1                   # 单 Pod 挂载(ADR-009 §1.3.1 Q2 确认)
  selector:
    matchLabels:
      app: api
      role: nas-consumer
  template:
    metadata:
      labels:
        app: api
        role: nas-consumer       # ← 必须与 NetworkPolicy podSelector 匹配
        tenant: tnt-001
    spec:
      serviceAccountName: api-nas-consumer-sa   # ← 业务方专用 SA(infra-gcp 创建)
      containers:
      - name: api
        image: <业务方镜像>      # ← 业务方填
        ports:
        - containerPort: 8080
        env:
        - name: MOUNT_PATH
          value: /mnt/nas
        # 关键:挂载 NAS 到容器内
        volumeMounts:
        - name: nas-app-folder
          mountPath: /mnt/nas     # ← 容器内可见路径
          readOnly: true         # ← ADR-009 §6.3 红线:默认 ro
        # 安全:不写包含 NAS 路径的 log(红线 2)
        # 业务方需保证应用代码不打印 /mnt/nas/foo.csv 等具体文件名
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
      # 关键:声明卷引用 PVC
      volumes:
      - name: nas-app-folder
        persistentVolumeClaim:
          claimName: pvc-nas-app  # ← PVC 名字(infra-gcp 创建)
```

---

## 2. 字段注释(每个字段为什么这么写)| 字段 | 值 | 为什么 |
|---|---|---|
| `metadata.labels.role: nas-consumer` | **必须有** | NetworkPolicy podSelector 用这个锁定单 Pod 出栈(见 [04-network-policy-nas.yaml](./examples/network-policy-nas.yaml)) |
| `metadata.labels.tenant: tnt-XXX` | **业务方指定** | 跟 Tenant CRD 的 `metadata.name` 对齐,用于 BigQuery billing 归因 |
| `spec.replicas: 1` | **默认 1** | ADR-009 §1.3.1 Q2:挂载范围 = 单个目标 Pod。**不要**改 > 1,除非业务方明确要求 + 走审批 |
| `spec.template.spec.serviceAccountName` | **专用 SA** | 业务方专用 service account,**不是 default**,走 RBAC 最小权限 |
| `volumeMounts[].readOnly: true` | **默认 true** | ADR-009 §6.3 红线 + §8 G1 治理问题。**业务方要 rw 必须先 PM 评估 + POC** |
| `volumes[].persistentVolumeClaim.claimName` | **指向 PVC** | 不要直接挂 PV,要让 Pod 通过 PVC 引用(命名空间隔离) |

---

## 3. 安全要点(4 条红线自检)

写完 Deployment 后,业务方/Platform review 必跑这 4 个 grep:

```bash
# 红线 1:不持久化到 GCP 服务
grep -E "gcs|firestore|bigquery|cloudsql" deployment.yaml
# 期望:无输出

# 红线 2:不写 log / metric 暴露
grep -E "nas.*path|/mnt/nas" deployment.yaml log_schema.yaml
# 期望:无输出

# 红线 3:不主动观察用户行为
grep -E "audit_log.*file_path|audit_log.*file_content" deployment.yaml
# 期望:无输出

# 红线 4:Pod lifecycle 与 NAS 内容解耦
grep -E "configMapRef.*nas|secretRef.*nas" deployment.yaml
# 期望:无输出
```

如果**任一 grep 有输出**,立刻停下来,回到 ADR-009 §6.3 看怎么改。

---

## 4. 常见错误(实战避坑清单)

### ❌ 错误 1:`volumeMounts[].readOnly: false` 但没审批

```yaml
# ❌ 不要这么写(除非已经走 PM + Manager + POC)
volumeMounts:
- name: nas-app-folder
  mountPath: /mnt/nas
  readOnly: false           # ← 这是 rw,需要审批
```

**修正**:改回 `readOnly: true`,或先走 §6.3 Q3 评估流程。

### ❌ 错误 2:`replicas: 3` 但没说明理由

```yaml
# ❌ 不要这么写
replicas: 3                  # ← 多个 Pod 共享一个 NAS PV,横向访问面放大
```

**修正**:默认 `replicas: 1`。如果业务方想多副本 + 共享 NAS,**必须**走 PodSecurity + NetworkPolicy + read-only mount,业务方额外写评估。

### ❌ 错误 3:硬编码凭据在环境变量

```yaml
# ❌ 不要这么写(凭据泄漏)
env:
- name: SMB_USERNAME
  value: "svc-account"      # ← 明文凭据
- name: SMB_PASSWORD
  value: "xxx"              # ← 严重违规
```

**修正**:凭据放在 K8s Secret 里(见 [05-smb-secret-template.yaml](./examples/smb-secret-template.yaml)),CSI driver 通过 `nodePublishSecretRef` 自动读取。

### ❌ 错误 4:挂多个 PV 但没有 NetworkPolicy

```yaml
# ❌ 多个 PVC 但没有 NetworkPolicy = 横向访问面失控
volumes:
- name: nas-1
  persistentVolumeClaim: { claimName: pvc-nas-1 }
- name: nas-2
  persistentVolumeClaim: { claimName: pvc-nas-2 }
```

**修正**:每个挂载场景单独配 NetworkPolicy(见 [04-network-policy-nas.yaml](./examples/network-policy-nas.yaml))。

---

## 5. 业务方自检清单(提交前)

- [ ] `role: nas-consumer` label 加上
- [ ] `tenant: tnt-XXX` label 加上
- [ ] `replicas: 1`(默认)
- [ ] `readOnly: true`(默认)
- [ ] 不含明文凭据(env 里有 secret 也不行)
- [ ] 不含 GCP 持久化 API 调用(`gcs` / `firestore` 等)
- [ ] 应用代码不写 `logger.info(f"processed {filepath}")`
- [ ] 不挂 ConfigMap / Secret 引用 NAS 内容
- [ ] Pod 镜像准备好(不能是 `latest`,要固定 tag)
- [ ] 准备好 `serviceAccountName`(业务方专用 SA,infra-gcp 创建)

**全部 ✅ 才交给 infra-gcp 评审 + 执行**。

---

## 6. 实际可用的 YAML 示例

业务方可直接复制 → [`examples/deployment-with-nas.yaml`](./examples/deployment-with-nas.yaml)。

---

## 7. 下一步

- 业务方完成自检清单 → 提交给 infra-gcp
- infra-gcp 评审 + 套 namespace / SA / NetworkPolicy / Secret → 推到 dev cluster 测试
- qa-gcp 端到端验证(健康检查 + NetworkPolicy 测试 + SMB 路径连通性)
- 通过 → 生产 + 监控

完整流程见 [`03-full-flow-process.md`](./03-full-flow-process.md)。