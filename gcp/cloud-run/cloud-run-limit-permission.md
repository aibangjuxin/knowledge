## Cloud Run Job 参数与权限深度解析

本文档旨在深度分析 Cloud Run Job 在部署（`deploy`）和执行（`execute`）两个阶段的参数配置差异，并基于此提供权限最小化的最佳实践。

### 核心结论

`gcloud run jobs execute` 命令的设计哲学是分离 **作业定义 (Definition)** 和 **作业执行 (Execution)**。

-   **作业定义 (`gcloud run jobs deploy`)**: 这相当于为作业创建一个静态的“蓝图”，包含其运行所需的核心资源、身份和安全边界。这些属性一旦定义，就是该作业版本的固有属性。
-   **作业执行 (`gcloud run jobs execute`)**: 这相当于运行这个已经定义好的“蓝图”，并允许在运行时临时微调一小部分输入参数，但绝对无法改变“蓝图”本身。

这种分离是实现权限最小化和安全运维的关键。您可以安全地创建一个权限较低的服务账号，它只有执行作业的权限 (`roles/run.invoker`)，而没有部署新版本的权限 (`roles/run.developer`)。

---

### 参数分类详解

#### 1. 作业定义参数 (仅在 `deploy` 时可修改)

这些参数定义了作业的静态蓝图，在 `execute` 时绝对不能修改。

| 分类 | 参数 | 说明 | 为什么不能在 `execute` 时修改？ |
| --- | --- | --- | --- |
| **核心身份** | `--image` | 容器镜像 | 这是最核心的安全边界。如果执行时可以更改镜像，就等于可以运行任意代码，所有其他权限控制都将失效。 |
| **资源规格** | `--cpu`, `--memory` | CPU 和内存分配 | 这些决定了基础设施的成本和容量。允许执行时动态修改会使资源规划和成本控制变得不可预测。 |
| **执行行为** | `--max-retries` | 失败后的最大重试次数 | 这是作业容错模型的一部分，属于固有的健壮性设计，应在定义时确定。 |
| **环境变量** | `--set-env-vars` | 默认的环境变量 | 这是作业定义的一部分，提供了基础配置。`execute` 时可以用 `--update-env-vars` 临时覆盖，但不能改变这个默认值。 |
| **安全与身份** | `--service-account` | 作业运行时使用的服务账号 | 这是作业的“身份”。随意更改身份会破坏权限模型，导致潜在的权限提升攻击。 |
| | `--set-secrets` | 挂载 Secret Manager 中的密钥 | 密钥的访问权限是敏感的安全配置，必须在定义时严格审查和确定。 |
| | `--binary-authorization` | 二进制授权策略 | 这是供应链安全的关键环节，用于确保只有受信任的镜像才能部署，绝不能在执行时绕过。 |
| **网络配置** | `--vpc-connector`, `--vpc-egress` | VPC 连接器和出口设置 | 网络边界是核心安全控制之一，定义了作业可以访问哪些网络资源。执行时更改会带来严重安全风险。 |
| **元数据** | `--labels` | 资源的标签 | 标签通常用于计费、资源分组和策略执行，属于管理层面的静态元数据。 |
| **加密** | `--encryption-key` | 用于加密容器的 CMEK 密钥 | 数据静态加密策略是合规性和安全性的基本要求，必须在定义时指定。 |

#### 2. 执行时可覆盖参数 (临时生效)

这些参数仅对当次执行有效，可以临时覆盖作业定义中的默认值。

| 参数 | 说明 | `deploy` 中的对应参数 | 安全风险与最小化权限考量 |
| --- | --- | --- | --- |
| `--update-env-vars` | 更新或添加本次执行的环境变量。 | `--set-env-vars` | **低风险**。这是最常见的覆盖场景。您可以允许执行者传入配置值（如处理日期、目标 bucket），而无需改变代码或镜像。只要服务账号本身的权限受限，风险就是可控的。 |
| `--clear-env-vars` | 清除所有在 `deploy` 时设置的默认环境变量。 | `--set-env-vars` | **低风险**。用于在特定执行中忽略默认配置。 |
| `--args` | 覆盖容器的启动命令参数 (entrypoint/CMD)。 | `--args` | **中等风险**。这比环境变量的风险略高，因为它可能改变程序的执行逻辑分支。但由于代码和镜像本身是固定的，其能造成的改变是有限和可预期的。 |
| `--task-timeout` | 覆盖单个任务的超时时间。 | `--task-timeout` | **低风险**。允许根据本次执行的具体负载临时调整超时。 |

> **注意**: 任务数量 (`--tasks`) 是在 `deploy` 时定义的，决定了作业的并行度，在 `execute` 时**无法**修改。

---

### 权限模型与最小化建议

```mermaid
graph TD
    A[Service Account 权限设计] --> B{权限分离};
    B --> C[部署者 (Deployer)];
    B --> D[执行者 (Invoker)];

    subgraph "部署 (deploy)"
        C --> E[定义作业蓝图];
        E --> F[镜像: --image];
        E --> G[资源: --cpu, --memory];
        E --> H[网络: --vpc-connector];
        E --> I[安全: --service-account];
    end

    subgraph "执行 (execute)"
        D --> J[运行已定义作业];
        J --> K[覆盖临时参数];
        K --> L[环境变量: --update-env-vars];
        K --> M[启动参数: --args];
        K --> N[任务配置: --task-timeout];
    end

    C -- 授予 --> O[roles/run.developer 或更高];
    D -- 授予 --> P[roles/run.invoker];
```

### IAM 角色配置示例

#### 仅执行权限的 Service Account

```bash
# 创建执行专用的 Service Account
gcloud iam service-accounts create job-executor \
    --display-name="Job Executor Only"

# 只赋予执行权限 (不能部署或修改作业定义)
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:job-executor@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/run.invoker"
```

#### 具有部署权限的 Service Account

```bash
# 创建具有部署权限的 Service Account
gcloud iam service-accounts create job-deployer \
    --display-name="Job Deployer Limited"

# 赋予部署和执行权限
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:job-deployer@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/run.developer"
```

---

### 总结

您的理解是正确的：

-   ✅ **镜像、资源、网络和安全配置**绝对不能在 `execute` 时修改。
-   ✅ **只有 `args`、`env-vars`、`task-timeout`** 等少数参数可以在 `execute` 时临时覆盖。

这种设计有助于实现权限最小化，可以安全地允许 Service Account 执行 Job 并覆盖运行时参数，而不用担心核心配置被篡改。