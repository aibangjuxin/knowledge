这是一个非常典型且务实的 DevOps 场景。因为你强调了是一个“临时任务”且由于平台限制只能使用 `kubectl apply`，不能引入 Kustomize 或 Helm 等复杂工具，我们需要设计一个**基于 Shell 脚本 + 简单的模板替换**的 Pipeline 方案。

这个方案的核心在于：**“自动化搬运工”** —— 既搬运镜像（Nexus -> GAR），也搬运 YAML 配置（Git -> GKE），并在中间做必要的修改。

我将为你生成两个文件：

1. **`pipeline_deploy.sh`**: 这是 Pipeline 的核心逻辑脚本，包含了镜像同步、YAML 修改和部署逻辑。
2. **`repo_structure.md`**: 建议的 Git 仓库目录结构设计及 `.yaml` 文件模板写法。

然后我会分析这个方案的优缺点以及你需要注意的“坑”。

### 文件生成

Pipeline 核心逻辑

11 月 26 日 14:31

Git 仓库结构与配置规范

11 月 26 日 14:31

打开

### 方案深度解析与改进建议

你目前的流程虽然是临时的，但逻辑是通的。我为你生成的脚本实现了：**拉取 Git -> 拉取镜像 -> 推送 GAR -> 修改 YAML -> kubectl apply** 的闭环。

针对你的需求，我有以下几点具体的分析和改进建议：

#### 1. 核心痛点：YAML 如何动态修改？

在只允许 `kubectl apply` 的情况下，最大的难点是如何把 GAR 的新镜像地址填进 YAML 里。

- **当前脚本的做法 (`sed`)**：这是最简单的方法。脚本中使用了 `sed -i "s|image: .*|image: $GAR_IMAGE_FULL|g"`。
    - _风险_：如果你的 Deployment 里有多个容器（Sidecar），这个 `sed` 会把所有容器的镜像都替换成同一个，这会导致灾难。
    - _改进建议_：
        - **如果环境支持 `envsubst`**（大多数 Linux 发行版都有）：将 Git 里的 `deployment.yaml` 中的镜像写成 `image: ${IMAGE_URL}`。然后在脚本里 `export IMAGE_URL=...` 再执行 `envsubst < deploy.yaml > deploy_final.yaml`。这比 `sed` 安全得多。
        - **如果环境支持 `yq`**（Go 编写的 YAML 处理工具，不需要复杂依赖）：`yq -i '.spec.template.spec.containers[0].image = env(GAR_IMAGE_FULL)' deployment.yaml`。这是最推荐的方式，精确且不易出错。

#### 2. 镜像同步的效率与缓存

- **问题**：每次 Pipeline 运行都要 `docker pull` 再 `docker push`。如果镜像很大（例如 Java 应用几百 MB），这会非常慢且浪费流量。
- **解决**：
    - **判断层**：在脚本通过 `gcloud container images describe $GAR_IMAGE_FULL` 检查目标 GAR 里是否已经存在该 Tag。如果存在，直接跳过 Pull/Push 步骤，直接部署。这能节省 90% 的时间。

#### 3. 并发与冲突 (Race Conditions)

- **问题**：既然是 Git 仓库，如果两个管理员同时修改了同一个用户的配置，或者 Pipeline 并发运行，本地 workspace 可能会冲突。
- **解决**：在脚本中，我使用了 `WORK_DIR` 和 `DEPLOY_TEMP_DIR`。建议在 CI Runner 里面为每次构建生成一个随机的后缀 ID（例如 `BUILD_ID`），确保目录隔离。

#### 4. Namespace 管理

- **现状**：你提到了 Namespace，但用户的 Namespace 是固定的还是动态生成的？
- **脚本逻辑**：我在脚本里加了一行 `kubectl create namespace ... --dry-run=client ... | kubectl apply ...`。这确保了如果它是新用户，Namespace 会被自动创建；如果是老用户，则无事发生。这是一个很好的容错设计。

#### 5. 权限与认证 (GCP & Nexus)

- **GCP**: 你的 Pipeline 运行环境（比如 Jenkins Agent 或 GitLab Runner）需要有 `roles/artifactregistry.writer` (用于 Push 镜像) 和 `roles/container.developer` (用于 kubectl apply)。
- **Nexus**: 需要在 CI 里的 Secrets 管理器里存好 Nexus 的用户名密码。不要硬编码在脚本里。

### 总结推荐的“完美”临时路径

1. **Git 侧**：每个用户一个文件夹，`deployment.yaml` 中镜像建议写成变量形式 `${IMAGE_NAME}` (如果使用 envsubst) 或者标准占位符。
2. **Pipeline 侧**：

    - **Step 1**: Check GAR。如果镜像已存在，Skip Sync。
    - **Step 2**: Sync (Nexus -> GAR)。
    - **Step 3**: Render YAML。**强烈建议安装一个 `envsubst` 或 `yq` 放在 pipeline 的基础镜像里**，不要依赖脆弱的 `sed`。
    - **Step 4**: `kubectl apply -f folder/ -n namespace`。

这个方案完全符合你“不引入 Kustomize”、“快速”、“临时”且“基于 kubectl”的要求。

## Pipeline 核心逻辑

```bash
#!/bin/bash
set -e # 遇到错误立即退出

# ==========================================
# 环境变量 inputs (通常由 CI 工具传入)
# ==========================================
# GIT_REPO_URL: Git 仓库地址
# ENV: 环境名称 (e.g., dev, prod) -> 对应 GKE 的 Namespace 或 Cluster Context
# USER_API_ID: 用户的唯一标识 (对应 Git 子目录名)
# NEXUS_IMAGE_FULL: Nexus 中的完整镜像地址 (e.g., nexus.company.com/user-api:v1.0)
# GAR_REPO_BASE: GAR 的基础路径 (e.g., region-docker.pkg.dev/project-id/repo-name)
# ==========================================

echo ">>> [Step 1] 初始化环境: $ENV for User: $USER_API_ID"

# 检查必要参数
if [ -z "$USER_API_ID" ] || [ -z "$NEXUS_IMAGE_FULL" ]; then
  echo "Error: USER_API_ID 或 NEXUS_IMAGE_FULL 未定义"
  exit 1
fi

# 1. 确定目录路径
WORK_DIR="./deploy_workspace"
USER_CONFIG_DIR="$WORK_DIR/users/$USER_API_ID"

# (模拟 git clone，实际 CI 中通常由 Runner 完成)
# git clone $GIT_REPO_URL $WORK_DIR

if [ ! -d "$USER_CONFIG_DIR" ]; then
  echo "Error: 用户目录 $USER_CONFIG_DIR 不存在"
  exit 1
fi

echo ">>> [Step 2] 镜像处理 (Nexus -> GAR)"

# 提取镜像名和 Tag
# 假设 NEXUS_IMAGE_FULL = nexus.company.com/group/app-name:v1.0
IMAGE_NAME_TAG=$(echo "$NEXUS_IMAGE_FULL" | awk -F/ '{print $NF}') # app-name:v1.0
GAR_IMAGE_FULL="$GAR_REPO_BASE/$IMAGE_NAME_TAG"

echo "Src: $NEXUS_IMAGE_FULL"
echo "Dst: $GAR_IMAGE_FULL"

# 登录 Docker (CI 环境需提前配置好 Service Account 或 secrets)
# docker login -u ... -p ... nexus.company.com
# gcloud auth configure-docker region-docker.pkg.dev

# 拉取 -> 打标签 -> 推送
echo "Pulling from Nexus..."
docker pull "$NEXUS_IMAGE_FULL"

echo "Retagging for GAR..."
docker tag "$NEXUS_IMAGE_FULL" "$GAR_IMAGE_FULL"

echo "Pushing to GAR..."
docker push "$GAR_IMAGE_FULL"

echo ">>> [Step 3] 准备 YAML 文件 (替换镜像地址)"

# 创建一个临时部署目录，防止修改 Git 原始内容
DEPLOY_TEMP_DIR="./temp_deploy/$USER_API_ID"
mkdir -p "$DEPLOY_TEMP_DIR"
cp -r "$USER_CONFIG_DIR"/* "$DEPLOY_TEMP_DIR"

# 核心逻辑：替换 Deployment.yaml 中的镜像地址
# 只有 kubectl apply，没有 kustomize，我们用 sed 或 envsubst
# 假设 yaml 里写的是 template 变量，或者我们直接暴力替换旧的 Nexus 域名

TARGET_DEPLOY_YAML="$DEPLOY_TEMP_DIR/deployment.yaml"

if [ -f "$TARGET_DEPLOY_YAML" ]; then
    # 方法 A: 如果你能在 yaml 里写 ${IMAGE_URL}，用 envsubst (推荐)
    # export IMAGE_URL=$GAR_IMAGE_FULL
    # envsubst < "$USER_CONFIG_DIR/deployment.yaml" > "$TARGET_DEPLOY_YAML"

    # 方法 B: 暴力替换 (sed)，寻找 yaml 里 image: 字段
    # 这里假设 yaml 里原本写的是 nexus 地址，或者特定的占位符
    # 使用 sed 将 nexus 域名替换为 GAR 域名
    # 注意：这里使用 | 作为分隔符避免 / 冲突

    # 逻辑：匹配 image: 之后的内容，替换为新的 GAR 地址
    # 这是一个比较粗暴但有效的 sed，仅替换包含 nexus 域名的行
    sed -i "s|image: .*|image: $GAR_IMAGE_FULL|g" "$TARGET_DEPLOY_YAML"

    echo "Updated deployment.yaml image to: $GAR_IMAGE_FULL"
else
    echo "Warning: No deployment.yaml found in $USER_CONFIG_DIR"
fi

echo ">>> [Step 4] 部署到 GKE"

# 切换 Namespace (如果 namespace 是动态的)
TARGET_NAMESPACE="ns-$USER_API_ID-$ENV" # 举例命名规则

# 确保 Namespace 存在 (可选)
kubectl create namespace "$TARGET_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 执行部署
echo "Applying configurations to Namespace: $TARGET_NAMESPACE"
kubectl apply -f "$DEPLOY_TEMP_DIR" -n "$TARGET_NAMESPACE"

echo ">>> [Done] 部署完成"
```

# Git 仓库目录结构设计

为了适应多租户且不使用 Kustomize 的需求，建议采用**基于目录的隔离**结构。

## 1. 目录树

```
/ (Root)
├── users/
│   ├── user-api-001/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   └── configmap.yaml
│   ├── user-api-002/
│   │   ├── ...
│   └── payment-service/
│       ├── ...
└── common/ (可选，存放公共脚本或文档)
```

## 2. YAML 文件规范 (关键点)

为了配合 Pipeline 中的 `sed` 替换逻辑，`deployment.yaml` 需要保持标准格式。

### deployment.yaml 示例

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-api-001
  labels:
    app: user-api-001
spec:
  replicas: 2
  selector:
    matchLabels:
      app: user-api-001
  template:
    metadata:
      labels:
        app: user-api-001
    spec:
      containers:
      - name: main-container
        # Pipeline 会查找 "image:" 这一行并进行整行替换
        # 建议在 Git 中保留一个合法的 Nexus 地址作为默认值，方便本地调试
        image: [nexus.company.com/group/user-api-001:latest](https://nexus.company.com/group/user-api-001:latest)
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
```

### ingress.yaml 示例

由于每个用户的 Ingress 可能不同，建议在这里硬编码路径。

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: user-api-001-ingress
  annotations:
    kubernetes.io/ingress.class: "nginx" # 或 gce
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /user001
        pathType: Prefix
        backend:
          service:
            name: user-api-001-service
            port:
              number: 80
```

## 3. Pipeline 传参设计

CI/CD 系统在触发 Pipeline 时，需要根据 Git 变更或手动输入传递以下参数：

| 参数名             | 描述                | 示例                                      |
| ------------------ | ------------------- | ----------------------------------------- |
| `GIT_REPO_URL`     | 配置仓库地址        | `git@github.com:org/platform-configs.git` |
| `ENV`              | 环境标识            | `prod` / `staging`                        |
| `USER_API_ID`      | 用户目录名          | `user-api-001`                            |
| `NEXUS_IMAGE_FULL` | 原始 Nexus 镜像地址 | `nexus.local/app:v1.2.3`                  |
