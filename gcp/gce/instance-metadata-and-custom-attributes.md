# GCE Instance Metadata — 自定义属性、动态入参与 Pod 侧验证

> **本文档范围**：GCE 实例 metadata server 的完整用法 —— 自定义 key/value 的写入/读取/删除、目录结构与优先级、startup script 动态入参、**在 GKE Pod 里的可验证范围（关键限制）**、guest attributes、以及生产环境的坑。
>
> **不包含**：Workload Identity 的完整配置流程（见 §6 只讲 metadata 相关部分，链接到官方文档）、Secret 管理方案选型。

---

## TL;DR

| 你的问题 | 答案 |
|---|---|
| Metadata 是什么 | 每台 GCE VM 有一个本地 metadata server，`169.254.169.254` / `metadata.google.internal`，VM 内**无需任何凭据**即可读取自己实例的信息 + 自定义 key/value |
| 自定义 Key/Value 怎么写 | `gcloud compute instances add-metadata VM --metadata=k1=v1,k2=v2`；读用 `--format`；删用 `remove-metadata --keys=` |
| 限制 | 总计 **512 KB**；单个 key **128 bytes**；单个 value **256 KB**；key 大小写敏感，必须匹配 `[a-zA-Z0-9-_]+` |
| 你想要的"Image + 不同入参启动"怎么做 | ✅ 标准做法：instance template 定义 image + startup script，per-instance metadata 提供差异化入参，脚本启动时读 metadata 渲染配置。见 §5 |
| 最大的坑 | ① 项目级 metadata 会下发到该 Project 全部 VM，**别放密钥**；② Pod 里读不到自定义 attributes；③ 实例重启后 metadata 变化不会重跑 startup script |

---

## 1. Metadata Server 是什么

每台 Compute Engine 实例都有一个**本地**的 metadata server。它不是外部服务，不走公网，流量不离开这台 VM 本身。

**三个 endpoint 等价**（推荐用第一个）：

| 形式 | 地址 |
|---|---|
| DNS（推荐） | `http://metadata.google.internal/computeMetadata/v1` |
| IPv4 | `http://169.254.169.254/computeMetadata/v1` |
| IPv6（仅 IPv6-only VM） | `http://[fd20:ce::254]/computeMetadata/v1` |
| HTTPS（Preview，Shielded VM） | `https://metadata.google.internal/computeMetadata/v1` |

> ⚠️ 即使 VM 是 IPv6-only，查询 metadata server 仍要用 IPv4 地址 `169.254.169.254`。

**最重要的安全设计**：每个请求必须带 header

```
Metadata-Flavor: Google
```

不带这个 header，metadata server 直接拒绝请求。这既是一个"确认你真的想读 metadata"的开关，也是防 SSRF 的关键 —— 攻击者让应用去请求 `169.254.169.254` 时，如果应用只是盲目转发用户可控的 URL 而不带这个 header，就拿不到东西。

**VM 内的认证是自动的**：任何跑在这台 VM 上的进程（不需要 root，不需要任何凭据）都能读这台 VM 的 metadata server。**反过来，其他 VM 读不到这台 VM 的 metadata server。**

---

## 2. 三层作用域与优先级

这是最常被搞错的地方 —— metadata 有三个作用域，**同名 key 会按优先级覆盖**：

```
instance/attributes/k  ←  优先级最高（单台 VM）
       ↑ 覆盖
zonal (zone 级)        ← 优先级中间（该 zone 的所有 VM）
       ↑ 覆盖
project/attributes/k   ← 优先级最低（整个 Project 的所有 VM）
```

官方定义的覆盖规则：

| 场景 | 行为 |
|---|---|
| 给一个已有 project metadata 的 key 设 zonal 值 | 该 zone 内的 VM 用 zonal 值；其他 zone 继续用 project 值 |
| 给一个已有 zonal 值的 key 改 project 值 | **不生效**，zonal 值继续保留 |
| 某个 zone 没设 zonal 值 | 该 zone 的 VM 继续用 project 值 |

💡 **实践含义**：zonal metadata 的价值是**故障隔离**（同 Project 不同可用区可以配不同值），这是它相对于 project metadata 的主要理由。

> 注意：project 级和 zonal 级 metadata **共用同一个 `project/` 目录**。zonal 值会"写进"该 zone 的 `/project` 视图。

---

## 3. 目录结构

metadata server 是一个**类文件系统**的目录树。**以 `/` 结尾的 entry 是目录**，其内容是每行一个子项。

```
/computeMetadata/v1/
├── instance/                        ← 单台实例的信息
│   ├── attributes/                  ← ★ 自定义 metadata（instance 级）
│   │   ├── my-app-config
│   │   └── startup-script
│   ├── disks/                       ← 目录（带 / 才是目录）
│   │   ├── 0/
│   │   └── 1/
│   ├── network-interfaces/
│   │   └── 0/
│   ├── service-accounts/
│   │   └── default/
│   │       ├── aliases
│   │       ├── email
│   │       ├── identity
│   │       ├── scopes
│   │       └── token
│   ├── guest-attributes/            ← ★ VM 内可写的自定义空间（§7）
│   ├── scheduling/
│   │   └── maintenance-event
│   ├── guest-attributes/
│   ├── hostname
│   ├── id                           ← 唯一 ID
│   ├── image                        ← 启动镜像
│   ├── machine-type
│   ├── name
│   ├── tags
│   └── zone
└── project/                         ← Project 级 + zonal 级
    ├── attributes/                  ← ★ 自定义 metadata（project/zonal 级）
    ├── numeric-project-id           ← Project Number（IAM 里用的那个数字）
    └── project-id                   ← Project ID（人看的那个名字）
```

**读单个值** → 纯文本
```bash
curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/my-app-config" \
     -H "Metadata-Flavor: Google"
```

**读目录** → **必须带尾部 `/`**，返回每行一项的列表
```bash
# 目录
curl "http://metadata.google.internal/computeMetadata/v1/instance/disks/" \
     -H "Metadata-Flavor: Google"
# → 0/
#   1/

# 目录的子目录
curl "http://metadata.google.internal/computeMetadata/v1/instance/disks/0/" \
     -H "Metadata-Flavor: Google"
# → device-name index mode type
```

> ❗ **漏掉尾部 `/` 是最高频的错误**。`.../instance/disks`（无 `/`）返回的是空值/报错，不是目录列表。

**递归读整个目录 → JSON**
```bash
curl "http://metadata.google.internal/computeMetadata/v1/instance/disks/?recursive=true" \
     -H "Metadata-Flavor: Google"
```
```json
[{"deviceName":"boot","index":0,"mode":"READ_WRITE","type":"PERSISTENT"},
 {"deviceName":"persistent-disk-1","index":1,"mode":"READ_WRITE","type":"PERSISTENT"}]
```
递归默认返回 JSON；想要纯文本加 `&alt=text`。

---

## 4. gcloud 完整命令表

### 4.1 写入

```bash
# 单台实例（add 是幂等的 upsert：只动你给的 key，其他 key 不受影响）
gcloud compute instances add-metadata VM_NAME \
    --zone=ZONE \
    --metadata=key-1=value-1,key-2=value-2

# 创建实例时直接带
gcloud compute instances create VM_NAME \
    --zone=ZONE --machine-type=e2-medium \
    --image-family=debian-12 --image-project=debian-cloud \
    --metadata=env=prod,app-version=v2.3.1

# ★ Value 从文件读（脚本太长、或者含特殊字符时必须用这个）
gcloud compute instances add-metadata VM_NAME \
    --metadata-from-file=startup-script=./startup.sh

# Project 级（下发到该 Project 全部 VM）
gcloud compute project-info add-metadata --metadata=key=value

# Zonal 级（只影响该 zone 的 VM）
gcloud compute project-zonal-metadata add \
    --project=PROJECT_ID --zone=ZONE \
    --metadata=key-1=value-1
```

### 4.2 读取 / 审计

```bash
# 你提到的 --format 用法，从简到繁：

# ① 整体 metadata（人类可读）
gcloud compute instances describe VM_NAME --format="value(metadata)"

# ② 打平成 key: value，最适合审计/脚本
gcloud compute instances describe VM_NAME --flatten="metadata[]"

# ③ 只看自定义 attributes
gcloud compute instances describe VM_NAME \
    --format="value(metadata.items.filter('key : my-app-config').value)"

# ④ Project 级
gcloud compute project-info describe --flatten="commonInstanceMetadata[]"

# ⑤ Zonal 级
gcloud compute project-zonal-metadata describe \
    --project=PROJECT_ID --zone=ZONE --flatten="metadata[]"

# ⑥ JSON（写自动化/脚本时用）
gcloud compute instances describe VM_NAME --format=json
```

> 💡 **`--format` 是 gcloud 的通用过滤层**，底层是 JMESPath。审计 metadata 时比裸 `describe` 输出好用得多。

### 4.3 删除

```bash
# 删指定 key
gcloud compute instances remove-metadata VM_NAME --zone=ZONE --keys=key-1,key-2

# ⚠️ 删光所有自定义 metadata（慎用，会把 startup-script 之类一起删掉）
gcloud compute instances remove-metadata VM_NAME --zone=ZONE --all

# Project / Zonal 级
gcloud compute project-info remove-metadata --keys=key-1
gcloud compute project-zonal-metadata remove \
    --project=PROJECT_ID --zone=ZONE --metadata=key-1,key-2
```

> ⚠️ **REST API 的 PATCH 陷阱**：用 `update_mask` 做 zonal metadata 时，**如果 key 在 update_mask 里但没出现在 request body 里，该 key 会被删除**。gcloud CLI 会帮你处理正确，手写 REST 时要非常小心。

### 4.4 需要的 IAM 权限

| 操作 | 权限 |
|---|---|
| 增/改/删自定义 metadata | `compute.instances.get` + `compute.instances.setMetadata` |
| 设 zonal metadata | `compute.instanceSettings.update` |
| 在 VM 外读 metadata | `roles/compute.instanceAdmin.v1` |
| 在 VM 外读 guest attributes | `compute.instances.getGuestAttributes` |

**在 VM 内部读 metadata 不需要任何 IAM 权限** —— metadata server 自动做实例级认证授权。

---

## 5. 你的核心场景：Image + 动态入参启动

你的需求是：**一个 Image，不同实例带不同 key/value，启动时动态读取**。这是 metadata 最经典、最推荐的用法。官方文档明确点名这个场景："Because the Compute Engine predefined metadata keys are the same on every VM, you can reuse your script without having to update it for each VM."

### 5.1 架构

```
┌─────────────────────────────────────────────────────────────┐
│  一份 Image（只包含 agent/程序本身，不含任何环境配置）           │
│  + 一个通用 startup script（不知道任何环境信息）                │
└─────────────────────────────────────────────────────────────┘
                          │
         ┌────────────────┼────────────────┐
         ▼                ▼                ▼
    ┌─────────┐     ┌─────────┐     ┌─────────┐
    │ prod-vm │     │ test-vm │     │ dev-vm  │   ← 同一个 Image
    └─────────┘     └─────────┘     └─────────┘
    instance metadata:              instance metadata:
      env=prod                       env=test
      db-host=10.0.1.5               db-host=10.9.0.3
      replicas=3                     replicas=1
         │                │                │
         └──────── 同一个 startup script 读取并渲染配置 ────────┘
```

### 5.2 完整实现

**Step 1 — 创建一个与实例无关的 startup script**

```bash
#!/bin/bash
# /tmp/startup.sh  —— 这个脚本不知道任何具体环境，所有差异从 metadata 来
set -euo pipefail

MD="http://metadata.google.internal/computeMetadata/v1"

get_meta() {
  curl -s -f -H "Metadata-Flavor: Google" "$MD/$1"
}

# ---- 1. 从 metadata 读取入参 ----
ENV_NAME="$(get_meta instance/attributes/env)"
DB_HOST="$(get_meta instance/attributes/db-host)"
REPLICAS="$(get_meta instance/attributes/replicas)"

# fallback 到 project 级 metadata（instance 没设时）
ENV_NAME="${ENV_NAME:-$(get_meta project/attributes/env)}"

echo "Bootstrapping: env=$ENV_NAME db-host=$DB_HOST replicas=$REPLICAS"

# ---- 2. 渲染出应用的配置文件 ----
install -d -m 0750 /etc/myapp
cat > /etc/myapp/config.yaml <<EOF
env: ${ENV_NAME}
db:
  host: ${DB_HOST}
replicas: ${REPLICAS}
instance_id: $(get_meta instance/id)
zone: $(get_meta instance/zone | sed 's#.*/##')
EOF
chmod 0640 /etc/myapp/config.yaml

# ---- 3. 启动应用 ----
systemctl enable --now myapp
```

**Step 2 — 构建一个干净的自定义 Image**

> 🔴 **最关键的前置条件**：自定义 Image **必须手动安装 Google Guest Environment**。所有 Google 公开镜像都预装了，但你用 `gcloud compute images create` 从自己的实例做出来的镜像，guest environment 不会自动继承过去。
>
> **没有 guest environment，startup script、metadata、OS Login 全都不工作** —— 这是一个"镜像能跑起来但 metadata 读不到"的经典陷阱。
> 见 <https://docs.cloud.google.com/compute/docs/images/install-guest-environment>

```bash
# 创建自定义镜像（务必用 create，别用 deprecated 的 insert）
gcloud compute images create myapp-v1 \
    --source-instance=builder-vm \
    --source-disk=snap-builder-vm \
    --source-snapshot=snap-builder-vm-snap \
    --family=myapp --description="myapp v1" \
    --storage-location=asia-east1
```

**Step 3 — 定义 instance template（Image + 通用 script）**

```bash
gcloud compute instance-templates create myapp-v1 \
    --machine-type=e2-standard-2 \
    --image-family=myapp \
    --metadata-from-file=startup-script=./startup.sh \
    --service-account=myapp-vm@PROJECT_ID.iam.gserviceaccount.com \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --tags=http-server \
    --region=asia-east1

# ⚠️ instance template 创建后不可修改。要改配置 → 建新 template → 滚动更新 MIG
```

**Step 4 — 用不同 metadata 起不同实例**

```bash
# 生产
gcloud compute instances create myapp-prod-1 \
    --source-instance-template=myapp-v1 \
    --zone=asia-east1-b \
    --metadata=env=prod,db-host=10.0.1.5,replicas=3

# 测试（同一份 Image、同一个 script，只有 metadata 不同）
gcloud compute instances create myapp-test-1 \
    --source-instance-template=myapp-v1 \
    --zone=asia-east1-c \
    --metadata=env=test,db-host=10.9.0.3,replicas=1
```

**Step 5 — 验证**

```bash
# 从外部确认 metadata 已写入
gcloud compute instances describe myapp-prod-1 \
    --zone=asia-east1-b --flatten="metadata[]"

# 从外部确认实例已就绪（startup script 是异步跑的）
gcloud compute instances describe myapp-prod-1 \
    --zone=asia-east1-b \
    --format="value(metadata.items.filter('key : guest-config-ready').value)"

# 看 startup script 的输出（日志落在 serial console）
gcloud compute instances get-serial-port-output myapp-prod-1 \
    --zone=asia-east1-b --port=1 | head -100
```

### 5.3 MIG 规模化场景

单机 metadata 直接写就够用。要扩到一组 VM，有三层可选：

| 机制 | 粒度 | 适用 |
|---|---|---|
| **instance template** metadata | 整组统一 | 组内所有 VM 配置相同 |
| **all-instances config** | 整组统一，**不改 template** | 需要频繁改 metadata/label。**只能覆盖 metadata 和 labels 两个属性**，且优先级高于 template |
| **stateful metadata（per-instance config）** | 单台 VM | **某台 VM 需要特殊值，且必须在重建/自愈/更新后依然保留** |

```bash
# all-instances config：不新建 template 就改全组 metadata
gcloud compute instance-groups managed all-instances-config update myapp-mig \
    --region=asia-east1 --metadata=env=prod,log-level=info

# stateful metadata：给 MIG 里某一台打上专属标记
gcloud compute instance-groups managed instance-configs create myapp-cfg \
    --instance=myapp-prod-1 \
    --region=asia-east1 \
    --stateful-metadata=role=leader \
    --no-update-instance        # 不立刻重建这台 VM
```

> 💡 **stateful metadata 的价值在"生命周期穿越"**：普通 metadata 在实例重建后就没了（重新从 template 拉），而 stateful metadata 会在实例重建、自愈、更新、以及所有其他生命周期转换中**保留**。这正是需要"这台机器永远是 leader"这种语义的场景。

> ⚠️ 一个属性**不能同时**出现在 per-instance config 和 all-instances config 里。

### 5.4 超过 256 KB 的 script

startup script 内容算进 metadata 总量限制（512 KB）。脚本较大时用 GCS：

```bash
gcloud compute instances create VM_NAME \
    --metadata-from-file=startup-script-url=gs://BUCKET/startup.sh
```
key 换成 `startup-script-url`，guest agent 会从该公网可访问位置拉取。适用于大于 256 KB 的脚本。

---

## 6. 在 GKE Pod 里验证 Metadata ⚠️

### 6.1 curl 命令

你给的两处笔误：

```bash
# ✅ 正确
curl -s -H "Metadata-Flavor: Google" \
     "http://metadata.google.internal/computeMetadata/v1/instance/attributes/key"
```

### 6.2 GKE 里能不能读到？—— 不能（自定义 attributes）

开启 Workload Identity Federation for GKE 的集群上，每个节点会跑一个 `gke-metadata-server`（DaemonSet），它**拦截**了 Pod 发往 `169.254.169.254:80` 的请求。这个服务是 Compute Engine metadata server 的一个**子集**，只暴露 K8s 工作负载需要的 endpoint。

**Pod 里可用的完整清单**：

| 路径 | 可用 entry |
|---|---|
| `instance/` | `hostname`、`id`、`zone`、`service-accounts/`（`aliases`/`email`/`identity`/`scopes`/`token`） |
| `instance/attributes/` | **仅** `cluster-location`、`cluster-name`、`cluster-uid` |
| `project/` | `project-id`、`numeric-project-id` |

**读其它自定义 attribute 会得到 404**，而且 `gke-metadata-server` Pod 会在 `kube-system` 里打日志：

```
HTTP/404: generic::not_found: no child "", Reason: "NOT_FOUND", UserMessage: "Not Found"
```

用 `istio-proxy` 时错误长得不一样：
```
Error fetching GCP Metadata property gcp_gce_instance_template:
metadata: GCE metadata "instance/attributes/UNSUPPORTED_ATTRIBUTE" not defined
```

所以你在 §5 里设计的方案（instance metadata 带差异化入参）**只在 GCE VM 上成立，不能直接搬到 GKE Pod 里**。

### 6.3 Pod 里能验证的（可用的部分）

```yaml
# 用一个 Pod 验证 GKE metadata server 的可用视图
apiVersion: v1
kind: Pod
metadata:
  name: metadata-probe
spec:
  containers:
  - name: probe
    image: google/cloud-sdk:slim
    command:
    - bash
    - -c
    - |
      set -x
      MD=http://metadata.google.internal/computeMetadata/v1
      H="Metadata-Flavor: Google"

      # ✅ 这些在 GKE Pod 里可以读到
      curl -s -H "$H" $MD/instance/attributes/cluster-name
      curl -s -H "$H" $MD/instance/attributes/cluster-location
      curl -s -H "$H" $MD/instance/attributes/cluster-uid
      curl -s -H "$H" $MD/instance/hostname
      curl -s -H "$H" $MD/instance/zone
      curl -s -H "$H" $MD/project/project-id
      curl -s -H "$H" $MD/project/numeric-project-id

      # ❌ 这个会 404（自定义 attribute）
      curl -s -H "$H" $MD/instance/attributes/env
    serviceAccountName: <你的 KSA>
```

```bash
# 观察 gke-metadata-server 的 404 日志
kubectl logs -n kube-system -l k8s-app=gke-metadata-server --tail=50
```

### 6.4 GKE 里传配置参数 —— 正确的三个选择

| 方案 | 适合 | 说明 |
|---|---|---|
| **ConfigMap**（推荐，非敏感） | env、app-version、replicas、开关类 | K8s 原生，多实例共享一份；滚动更新 |
| **Downward API** | Pod 自己才知道的信息 | 节点名、Pod IP、namespace（`spec.nodeName`）—— 动态注入环境变量，**这部分 K8s 已经做对了** |
| **Secret Manager + Workload Identity** | 密码、token 等敏感值 | Pod 用 Workload Identity 拿短期 token，去 Secret Manager 取真值。**metadata 绝对不放密钥** |

> 💡 **架构上的结论**：K8s 里已经有 ConfigMap / Downward API 这两个一等公民机制，metadata 在容器场景下只剩"拿 GCE 实例级信息"和"拿 token"两个用途。不要为了"统一"把配置全塞进 metadata。

### 6.5 两个补充事实

1. **Token 生命周期**：GKE metadata server 返回的 access token 默认 1 小时有效期并被缓存。客户端库默认在"距离过期 < 3 分 45 秒"时自动刷新 —— **你自己写代码调 GCP API 的话必须实现这个逻辑**。
2. **`hostNetwork: true` 的 Pod 会绕过拦截**，直接打到真实的 GCE metadata server。老的 metadata concealment 文档明确写了它"不限制 hostNetwork Pod"。⚠️ 这意味着这类 Pod 理论上可能拿到 **节点**的 service account token 而非自己的 —— 这正是 Workload Identity 存在的原因。是否在你的集群版本上同样成立，属于**需要在你的集群实测确认**的点，不要照抄文档结论。

---

## 7. Guest Attributes —— VM 内可写的 metadata

普通自定义 metadata 只能从**外部**写入。Guest attributes 反过来：**VM 内的任何进程都能写**（不需要 root），外部**不能写**（只能读）。

| 特性 | 值 |
|---|---|
| 单 value 上限 | 256 KiB |
| 单 key 上限 | 128 bytes |
| 查询频率 | **每 VM 每分钟最多 10 次** |
| 突发 | 超过 3 QPS 会被限流；**超限时 Google 可能直接丢弃正在写入的 guest attribute** |
| 默认状态 | **关闭**，需 `enable-guest-attributes=TRUE` |
| 命名空间 | **必须有 namespace** |

```bash
# 启用
gcloud compute instances add-metadata VM_NAME --metadata=enable-guest-attributes=TRUE

# VM 内写（PUT）
curl -X PUT --data "1.2.3" \
  http://metadata.google.internal/computeMetadata/v1/instance/guest-attributes/myapp/init-status \
  -H "Metadata-Flavor: Google"

# VM 内读整个 namespace（省略 KEY）
curl http://metadata.google.internal/computeMetadata/v1/instance/guest-attributes/myapp/ \
  -H "Metadata-Flavor: Google"

# VM 内删
curl -X DELETE \
  http://metadata.google.internal/computeMetadata/v1/instance/guest-attributes/myapp/init-status \
  -H "Metadata-Flavor: Google"

# VM 外读
gcloud compute instances get-guest-attributes VM_NAME --zone=ZONE
gcloud compute instances get-guest-attributes VM_NAME --query-path=myapp/init-status --zone=ZONE
```

**适合**：startup script 汇报初始化结果、agent 上报 OS 版本、inventory agent 上报已装包列表。
**不适合**：高频数据、状态流 —— 官方明确说它"不是 event streaming / Pub/Sub / 任何数据存储的替代品"。

**安全团队可能在组织级关掉它**：
```bash
gcloud resource-manager org-policies enable-enforce \
    constraints/compute.disableGuestAttributesAccess --project=PROJECT_ID
```

> 💡 在 §5.2 的 startup script 末尾加一行，把初始化结果写进 guest attribute，控制面就能在 VM 外查到"这台机器到底起没起来"—— 比去翻 serial console 日志干净得多。

---

## 8. 动态变更感知（`wait-for-change`）

应用**不需要重启**就能响应 metadata 变更：发起一个长连接请求，metadata 变了服务端才返回。

```bash
# 阻塞直到 value 变化，或 360 秒超时
curl "http://metadata.google.internal/computeMetadata/v1/instance/tags?wait_for_change=true&timeout_sec=360" \
     -H "Metadata-Flavor: Google"
```

可用于：动态 IP 通告、`maintenance-event`（live migration 通知）、滚动配置的优雅 reload。

> ⚠️ 查询参数在官方文档中出现了 `wait-for-change`（功能名）和 `wait_for_change=true`（Windows 示例）两种写法。**实测确认你用的版本接受哪个**，别直接假设。

---

## 9. 使用 Metadata 的好处

| 好处 | 说明 |
|---|---|
| **一份 Image，多环境** | 你的核心诉求。Image 和配置解耦，出问题时"换个 metadata 重启"而不是"重新 build 镜像" |
| **零凭据** | VM 内任何进程读自己实例的 metadata **不需要 token、不需要 API 权限、不需要网络出口**。没有凭证轮换问题 |
| **不出网、不计费、不排队** | metadata server 是本地的，流量不离开这台 VM。启动时读一个值不需要等任何外部 API 的往返 |
| **延迟生效（可热改）** | `add-metadata` 之后 VM 内约 10 秒内可读到，**无需重启实例**。配错了改回来就行 |
| **脚本与实例解耦** | 因为 predefined key 在所有 VM 上都一样，同一个 startup script 可以原样复用到所有实例上 —— "less brittle code" |
| **模板化 / IaC 友好** | instance template 可以把 metadata 和 image 一起版本化，MIG 滚动更新 |
| **SSRF 防护内建** | 强制的 `Metadata-Flavor: Google` header 让"顺手把用户 URL 代理出去"的攻击拿不到数据 |
| **与 token 获取同源** | metadata server 同时是 GCP 凭据的发放点，配置和身份一个入口 |

**反过来，不该用 metadata 的场景**：

- ❌ **放密钥/密码** —— VM 上任何进程都能读，且 project 级 metadata 会下发到该 Project 的**所有** VM
- ❌ **放高频变化的数据** —— 不是 event streaming 的替代品
- ❌ **K8s Pod 的配置中心** —— 用 ConfigMap / Downward API
- ❌ **跨实例共享的状态** —— 用 Firestore / GCS / Database

---

## 10. 常见坑

| # | 坑 | 后果 | 正解 |
|---|---|---|---|
| P1 | **project 级 metadata 放了密钥** | 同 Project 全部 VM 任何进程可读 | 密钥一律走 Secret Manager；metadata 只放非敏感的定位类信息 |
| P2 | **自定义 Image 没装 Guest Environment** | 实例能起来，但 startup script / metadata / OS Login 全部不工作 | 自建镜像前先 `install-guest-environment` |
| P3 | **在 GKE Pod 里读自定义 attributes** | 恒定 404，排查半天 | 见 §6.4；Pod 里用 ConfigMap / Downward API |
| P4 | **漏掉目录的尾部 `/`** | `.../disks` 返回空，不是列表 | 目录类路径必须带 `/` |
| P5 | **重启后改的 metadata 没生效** | 期望热更新但 startup script 不重跑 | startup script **只在开机时跑一次**。动态需求用 `wait-for-change` 或自建 agent |
| P6 | **值里带逗号/等号** | `k=v1,k2=v2` 被错误切分 | 值含特殊字符时改用 `--metadata-from-file` |
| P7 | **手写 REST PATCH zonal metadata** | `update_mask` 里的 key 没出现在 body 里 → **该 key 被删除** | 用 gcloud CLI，或严格保证 mask 与 body 一致 |
| P8 | **header 格式** | `Metadata-Flavor : Google`（冒号前有空格）**2024-01-20 起请求被拒** | 必须是 `Metadata-Flavor: Google` 或 `Metadata-Flavor:Google` |
| P9 | **不重试** | 503/429 是常态（限流、维护、迁移中） | **实现指数退避重试**。503 属于瞬时错误，等几秒重试 |
| P10 | **对 metadata 做了 DNS 缓存** | IP 变了或 DNS 挂了就读不到 | 检查 `/etc/resolv.conf` 里 `nameserver 169.254.169.254`；必要时查 `/etc/hosts` |
| P11 | **误信 `GKE_METADATA` 能挡住一切** | `hostNetwork: true` 的 Pod 可能绕过拦截 | 实测验证；敏感场景用 Workload Identity + 最小权限 node SA |
| P12 | **在 MIG 里用普通 metadata 做"特殊标记"** | 实例一重建标记就没了 | 需要跨生命周期保留的用 **stateful metadata** |
| P13 | **频繁改 MIG metadata 想图省事改 template** | template 不可变 | 用 **all-instances config**（只覆盖 metadata + labels），无需重建 template |
| P14 | **在 startup script 里硬编码环境名** | Image 变成"只服务于一个环境"，§5 的意义就没了 | 所有差异一律从 metadata 读 |

### 状态码速查

| 码 | 含义 | 处理 |
|---|---|---|
| `200` | OK | — |
| `400` | 参数/端点前置条件不满足 | 看错误信息 |
| `403` | 端点被项目/实例设置禁用；或 TCP 层被关 | 查设置 + 网络配置 |
| `404` | 路径不存在 | **GKE 里读到自定义 attribute 也返回这个** |
| `405` | 方法不支持。metadata server **只支持 `GET`**，唯一例外是 guest attributes 允许写 | 改用 GET |
| `429` | 限流 | **退避重试** |
| `503` | server 未就绪 / 迁移中 / 维护中 | 瞬时，等几秒重试 |

**已知限流端点**：`oslogin/`、`instance/service-accounts/identity`、`instance/service-accounts/default/token`（缓存中的 token 不限流）、`instance/guest-attributes/`。

---

## 11. 决策表

| 需求 | 用什么 | 命令/路径 |
|---|---|---|
| 一份 Image + 每实例不同配置 | instance metadata + startup script | `--metadata=env=prod` + `--metadata-from-file=startup-script=./s.sh` |
| 配置太大（>256 KB） | `startup-script-url` 指向 GCS | `gs://BUCKET/startup.sh` |
| 整个 Project 统一配置 | project metadata | `gcloud compute project-info add-metadata` |
| 同 Project 不同 zone 不同值 | zonal metadata | `gcloud compute project-zonal-metadata add` |
| MIG 全组改 metadata 但不重建 template | all-instances config | `all-instances-config update --metadata=` |
| MIG 里某台 VM 的标记要跨重建保留 | stateful metadata | `instance-configs create --stateful-metadata=` |
| 应用要感知配置变化而不重启 | `wait-for-change` | `?wait_for_change=true&timeout_sec=N` |
| 汇报初始化状态给控制面 | guest attributes | `PUT /instance/guest-attributes/ns/key` |
| Pod 拿 GCP 身份 | GKE metadata server 的 token endpoint | `/instance/service-accounts/default/token` |
| Pod 拿非敏感配置 | ConfigMap / Downward API | **不要**用 metadata |
| Pod 拿密钥 | Secret Manager + Workload Identity | **绝对不要**用 metadata |

---

## 12. 权威证据

**Metadata 基础**
- About VM metadata — <https://docs.cloud.google.com/compute/docs/metadata/overview>
- View and query VM metadata — <https://docs.cloud.google.com/compute/docs/metadata/querying-metadata>
- Predefined metadata keys — <https://docs.cloud.google.com/compute/docs/metadata/predefined-metadata-keys>
- Setting and querying guest attributes — <https://docs.cloud.google.com/compute/docs/metadata/manage-guest-attributes>
- Troubleshooting metadata server access issues — <https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshoot-metadata-server>

**gcloud / API**
- `gcloud compute instances add-metadata` — <https://docs.cloud.google.com/sdk/gcloud/reference/compute/instances/add-metadata>
- `gcloud compute instance-templates create` — <https://docs.cloud.google.com/sdk/gcloud/reference/compute/instance-templates/create>
- `instances.setMetadata` REST（限制：key 正则 `[a-zA-Z0-9-_]+`、key <128B、value ≤256KiB）— <https://docs.cloud.google.com/compute/docs/reference/rest/v1/instances/setMetadata>

**规模与生命周期**
- Configure stateful metadata in MIGs — <https://docs.cloud.google.com/compute/docs/instance-groups/configuring-stateful-metadata-in-migs>
- Override instance template properties with an all-instances configuration — <https://docs.cloud.google.com/compute/docs/instance-groups/set-mig-aic>
- `gcloud compute instance-groups managed create-instance` — <https://docs.cloud.google.com/sdk/gcloud/reference/compute/instance-groups/managed/create-instance>

**Startup script**
- About startup scripts — <https://docs.cloud.google.com/compute/docs/instances/startup-scripts>
- Use startup scripts on Linux VMs — <https://docs.cloud.google.com/compute/docs/instances/startup-scripts/linux>
- Install the Guest Environment — <https://docs.cloud.google.com/compute/docs/images/install-guest-environment>

**GKE 侧**
- About Workload Identity Federation for GKE（**§ GKE metadata server 的 endpoint 清单**）— <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity>
- Protecting cluster metadata（metadata concealment）— <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/protecting-cluster-metadata>

---

## 相关文档

- `../gce/scopes.md` — Service Account scopes（metadata 与 identity 的另一层）
- `../gce/instance-groups.md` — MIG 基础
- `../sa/` — Service Account 管理