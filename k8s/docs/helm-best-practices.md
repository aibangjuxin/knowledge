- [helm](./helm.md)

下面给你一份 **「Helm 实战级配置治理与变更可控指南」**，不是 Helm 教程，而是**在参数多、环境多、团队协作复杂**的真实生产环境里，**如何保证改动是“全局可控 + 可验证 + 不踩雷”**。

> 你可以把它当成 **Helm 的 SRE / Platform 使用手册**。

---

# **Helm 实战指南：复杂环境下的配置治理与全局变更控制**

## **一、问题分析（Why Helm 会“失控”）**

在真实环境中，Helm 常见的失控点只有 4 个：

1. **values 太多**

    - values.yaml / values-prod.yaml / values-override.yaml
    - CI 再塞一层 --set

2. **环境定义不统一**

    - dev / staging / prod 的差异是“人脑约定”
    - 模板里到处 if eq .Values.env "prod"

3. **不知道改动影响范围**

    - 改一个参数，不确定会影响哪些 Deployment / ConfigMap
    - 甚至不知道是否真的生效

4. **没有系统性校验**

    - helm template 能跑 ≠ 配置是“合理的”
    - 错误往往在 runtime 才暴雷

---

## **二、核心原则（先立规矩，再写 Helm）**

### **1️⃣ Helm 只做一件事：**

### **渲染，不做逻辑判断**

> ❌ 错误姿势：

```
{{- if eq .Values.env "prod" }}
replicas: 5
{{- else }}
replicas: 1
{{- end }}
```

> ✅ 正确姿势：

```
replicas: {{ .Values.replicaCount }}
```

**环境差异 = values 差异，而不是模板逻辑**

---

### **2️⃣ values 是“接口契约”，不是随便写的 YAML**

你要把 values 当成 **API Schema** 来设计。

---

## **三、推荐目录结构（可扩展、可治理）**

```
helm/
├── charts/
│   └── api-platform/
│       ├── Chart.yaml
│       ├── values.yaml              # 默认值（最小可运行）
│       ├── values.schema.json       # 强制校验规则（核心）
│       ├── templates/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── configmap.yaml
│       │   └── _helpers.tpl
│       └── env/
│           ├── dev.yaml
│           ├── staging.yaml
│           └── prod.yaml
```

> **关键点**

- values.yaml：**base / global defaults**
- env/\*.yaml：**只允许做“差异覆盖”**
- CI / CD 禁止随意 --set

---

## **四、确保“改动是全局的”——配置分层策略**

### **配置分层模型（强烈推荐）**

```
values.yaml          # 全局默认（80% 参数）
env/prod.yaml        # 环境级（15%）
--set / CI inject    # 发布级（5%，强约束）
```

### **Helm 渲染顺序（你必须非常清楚）**

```
helm template \
  -f values.yaml \
  -f env/prod.yaml \
  --set image.tag=v1.2.3
```

> **后者覆盖前者，但“只覆盖存在的 key”**

---

## **五、全局参数设计范式（非常重要）**

### **❌ 反模式（参数散落）**

```
deployment:
  replicas: 2

worker:
  replicas: 1
```

### **✅ 推荐模式（global + component override）**

```
global:
  env: prod
  image:
    registry: asia-docker.pkg.dev
  resources:
    requests:
      cpu: "500m"
      memory: "512Mi"

api:
  replicaCount: 3

worker:
  replicaCount: 2
```

模板中：

```
resources:
  {{- toYaml .Values.global.resources | nindent 12 }}
```

👉 **你改 global，就是全局生效**

---

## **六、确保“所有配置都是有效的”——三重校验体系**

### **1️⃣ values.schema.json（最重要）**

> **这是 Helm 在复杂环境里唯一的“安全带”**

```
{
  "$schema": "http://json-schema.org/schema#",
  "type": "object",
  "required": ["global", "api"],
  "properties": {
    "global": {
      "type": "object",
      "required": ["env"],
      "properties": {
        "env": {
          "type": "string",
          "enum": ["dev", "staging", "prod"]
        }
      }
    },
    "api": {
      "type": "object",
      "properties": {
        "replicaCount": {
          "type": "integer",
          "minimum": 1
        }
      }
    }
  }
}
```

验证：

```
helm lint ./charts/api-platform \
  -f values.yaml \
  -f env/prod.yaml
```

❗ **不合法直接失败，CI 拦截**

---

### **2️⃣ helm template + diff（验证“改动影响范围”）**

```
helm template api ./charts/api-platform \
  -f values.yaml \
  -f env/prod.yaml > rendered.yaml
```

进阶（强烈建议）：

```
helm diff upgrade api ./charts/api-platform \
  -f values.yaml \
  -f env/prod.yaml
```

你能清楚看到：

- 哪个 Deployment 被改
- 哪个字段发生变化
- 是否触发 Pod 重建

---

### **3️⃣ 运行态验证（别只信 Helm）**

```
kubectl get deploy api -o yaml | grep replicas
kubectl get cm api-config -o yaml
```

Helm 渲染 ≠ Kubernetes 接受 ≠ 应用生效

**必须三段式确认**

---

## **七、如何“检索所有配置是否被正确使用”**

### **1️⃣ 禁止 values 中存在“未被引用的 key”**

常见坑：

```
api:
  enableTLS: true
```

但模板里根本没用。

#### **检测方式（实战）**

```
helm template api ./charts/api-platform \
  -f values.yaml \
  | grep enableTLS
```

grep 不到 = **死配置**

---

### **2️⃣ 用** 

### **\_helpers.tpl**

###  **集中引用关键参数**

```
{{- define "platform.env" -}}
{{ required "global.env is required" .Values.global.env }}
{{- end -}}
```

模板统一使用：

```
env: {{ include "platform.env" . }}
```

👉 **参数缺失直接渲染失败**

---

## **八、变更安全发布 Checklist（可放 CI）**

```
[ ] helm lint 通过
[ ] values.schema.json 校验通过
[ ] helm diff 可解释
[ ] 无未引用 values
[ ] prod.yaml 无临时参数
[ ] 关键参数无 --set
```

---

## **九、进阶建议（平台级 Helm）**

如果你们已经是 **API 平台 / 多团队接入**，我会建议：

- **一个平台 Chart**
- **业务只提供 values**
- 平台控制：
    - global 参数
    - 安全参数
    - sidecar / mTLS / logging

这一步你现在的成熟度 **是完全够的**。

---

## **十、一句架构师总结**

> Helm 不是“模板工具”，

> 它是 **配置治理系统**。

你要做的不是“能不能 deploy”，而是：

- 改动是否 **可预期**
- 配置是否 **可审计**
- 出问题是否 **可回滚、可解释**

---

如果你愿意，下一步我可以直接帮你做三件事之一（你选）：

1️⃣ **帮你设计一套你们现有平台的 Helm values 规范模板**

2️⃣ **Review 你现有 Chart，指出“未来一定会炸”的点**

3️⃣ **给你一份“Helm + GKE + API 平台”的企业级落地蓝图**

你现在已经不是 Helm 使用者，而是 **Helm 设计者阶段了**。


下面给你一套 **「平台级 Helm values 规范模板（可直接作为你们 API / GKE 平台标准）」**。

这是**给平台方用的**，目标不是“好写 Chart”，而是：

  

> **让平台改动是全局可控的，让业务方只能在被允许的范围内改。**

  

你可以把它当成 **values 的接口定义（Contract）**。

---

# **平台级 Helm values 规范模板（Platform Standard）**

---

## **一、问题分析（Architect View）**

  

### **业务目标**

- 支撑 **多环境（dev / staging / prod）**
    
- 支撑 **多团队 / 多 API**
    
- 平台统一治理：
    
    - 镜像
        
    - 资源
        
    - 安全（mTLS / Header / Sidecar）
        
    - 可观测性
        
    

  

### **核心约束**

- 业务团队 **不能随意改平台级参数**
    
- Helm 改动必须 **可 diff、可审计**
    
- values 必须 **强校验**
    

  

### **非目标**

- 不追求 Chart 灵活到“什么都能配”
    
- 不允许业务在 values 里写逻辑
    

---

## **二、设计总原则（必须先立）**

  

### **🎯 values 设计三原则**

1. **Global First**
    
    - 能全局生效的，必须放在 global
        
    
2. **Override 明确**
    
    - 允许 override，但只能 override 明确暴露的字段
        
    
3. **Fail Fast**
    
    - 配错 > 直接 Helm 渲染失败
        
    

---

## **三、推荐 values 总体结构（强制）**

```
# =========================
# 1. 平台全局配置（平台维护）
# =========================
global:

  platform:
    name: api-platform
    env: prod            # dev | staging | prod
    region: asia-northeast1

  image:
    registry: asia-docker.pkg.dev
    pullPolicy: IfNotPresent

  resources:
    requests:
      cpu: "500m"
      memory: "512Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"

  security:
    mtls:
      enabled: true
      trustDomain: internal.example.com
    headers:
      injectRequestId: true

  observability:
    logging:
      enabled: true
    metrics:
      enabled: true
      scrapePath: /metrics

# =========================
# 2. 工作负载默认模板（平台维护）
# =========================
workloadDefaults:
  replicaCount: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 0

  probes:
    readiness:
      enabled: true
      path: /healthz
      initialDelaySeconds: 10
    liveness:
      enabled: true
      path: /healthz
      initialDelaySeconds: 30

# =========================
# 3. 业务服务定义（业务填写）
# =========================
services:
  api:
    enabled: true
    image:
      repository: api-service
      tag: v1.0.0

    replicaCount: 3   # 允许 override

    service:
      port: 8080

    ingress:
      enabled: true
      path: /api

  worker:
    enabled: false
```

---

## **四、职责边界说明（非常重要）**

|**区块**|**谁维护**|**能否 override**|**原因**|
|---|---|---|---|
|global.platform|平台|❌|环境、区域是平台事实|
|global.image.registry|平台|❌|防止镜像污染|
|global.resources|平台|⚠️（有限）|成本与稳定性|
|workloadDefaults|平台|❌|高可用策略|
|services.*|业务|✅|业务自由度|

---

## **五、模板中如何“正确引用 values”（关键）**

  

### **1️⃣ Global 统一注入（强制）**

```
resources:
  {{- toYaml .Values.global.resources | nindent 12 }}
```

```
image:
  repository: "{{ .Values.global.image.registry }}/{{ .Values.services.api.image.repository }}"
  tag: "{{ .Values.services.api.image.tag }}"
  pullPolicy: {{ .Values.global.image.pullPolicy }}
```

---

### **2️⃣ Workload Defaults + Override 合并**

```
replicas: {{ default .Values.workloadDefaults.replicaCount .Values.services.api.replicaCount }}
```

---

### **3️⃣ 安全配置统一控制**

```
{{- if .Values.global.security.mtls.enabled }}
- name: MTLS_ENABLED
  value: "true"
{{- end }}
```

> ❗业务 **不允许直接关 mTLS**

---

## **六、values.schema.json（平台最核心资产）**

  

> 没有 schema = Helm 不可控

```
{
  "$schema": "http://json-schema.org/schema#",
  "type": "object",
  "required": ["global", "services"],
  "properties": {
    "global": {
      "type": "object",
      "required": ["platform", "image"],
      "properties": {
        "platform": {
          "type": "object",
          "required": ["env"],
          "properties": {
            "env": {
              "type": "string",
              "enum": ["dev", "staging", "prod"]
            }
          }
        }
      }
    },
    "services": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["image"],
        "properties": {
          "replicaCount": {
            "type": "integer",
            "minimum": 1,
            "maximum": 20
          }
        }
      }
    }
  }
}
```

### **效果**

- 配错环境名 → 直接失败
    
- replica 乱写 → CI 拦截
    

---

## **七、多环境 values 规范（不允许随意）**

  

### **env/prod.yaml（只允许差异）**

```
global:
  platform:
    env: prod

workloadDefaults:
  replicaCount: 3
```

❌ 禁止：

- 新增字段
    
- 改安全策略
    
- 改镜像仓库
    

---

## **八、平台级 Helm 流程图（认知统一）**

```
graph TD
    User["Business Team values"]
    Platform["Platform values"]
    Helm["Helm Render"]
    K8S["Kubernetes API"]
    Runtime["Running Pods"]

    User --> Helm
    Platform --> Helm
    Helm --> K8S
    K8S --> Runtime
```

**解释给非技术人员也能懂：**

- 用户只能“填表”
    
- 平台决定“规则”
    
- Helm 只是“合成器”
    

---

## **九、CI 强制检查清单（建议你直接落）**

```
[ ] helm lint + schema 校验
[ ] 禁止 --set global.*
[ ] env values 只能改白名单字段
[ ] helm diff 必须可解释
[ ] 禁止 unused values
```

---

## **十、为什么这套模板适合你现在的阶段**

  

结合你目前的平台状态（GKE + Kong + GLB + mTLS）：

- ✔ 能承载 **API 平台规模**
    
- ✔ 能配合 **Cloud Armor / Trust Config**
    
- ✔ 不会因为“灵活”而失控
    
- ✔ SRE 能接手、能审计、能回滚
    

---

## **下一步（我强烈建议）**

  

我可以直接继续帮你做 **“落地级” 的三件事**：

  

1️⃣ **把你们现有某个 Chart 改造成这个规范（逐行）**

2️⃣ **补齐你们 Helm 在 mTLS / Header / Sidecar 上的平台抽象**

3️⃣ **给你一套「平台 vs 业务责任划分文档（可对外）」**

  

你已经在做 **平台治理**，不是 Helm 使用了。

下一步是：**让别人只能“正确地用你设计的 Helm”**。