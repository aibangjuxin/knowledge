# Cloud Run 容器命令 (Container Command) 与参数 (Arguments) 详解

在 Google Cloud Run 中，无论是部署可响应请求的服务（Service）还是执行一次性任务的作业（Job），您都可以精确控制容器启动时执行的命令。这为您提供了极大的灵活性，例如，使用同一个容器镜像执行不同的任务、在启动时动态传入配置、或进行调试。

本文将详细解释其工作原理，并提供最佳实践。

---

## **核心概念：`ENTRYPOINT` 与 `CMD`**

要理解 Cloud Run 如何控制容器命令，首先必须理解 Dockerfile 中的两个关键指令：`ENTRYPOINT` 和 `CMD`。

-   `ENTRYPOINT`：定义容器的**主可执行程序**。它指定了容器启动时总是会运行的命令，不易被运行时参数覆盖。这使得容器的行为像一个独立的可执行文件。
-   `CMD`：为 `ENTRYPOINT` 提供**默认参数**。`CMD` 的内容可以很容易地在 `gcloud` 命令中被覆盖。

它们组合在一起，决定了容器的默认启动行为。

**示例 `Dockerfile`**

```dockerfile
# ENTRYPOINT 定义了要执行的程序
ENTRYPOINT ["/bin/echo"]

# CMD 提供了默认参数
CMD ["Hello", "from", "Dockerfile"]
```

当这个容器在没有任何额外参数的情况下启动时，它会执行 `/bin/echo Hello from Dockerfile`。

---

## **在 Cloud Run 中覆盖命令与参数**

您可以在部署或执行时，通过 `gcloud` 的标志来覆盖 Dockerfile 中定义的 `ENTRYPOINT` 和 `CMD`。

-   `--command`：覆盖 `ENTRYPOINT`。
-   `--args`：覆盖 `CMD`。

### **1. 在 Cloud Run 作业 (Job) 中使用**

对于执行一次性任务的作业，这是最常见的用法。您可以使用 `gcloud run jobs execute` 来启动一次执行，并动态指定要运行的命令。

**示例 1：打印所有环境变量（您的提问）**

假设您有一个基础的 `ubuntu` 镜像，您想用它来查看容器内部的环境变量。

```bash
# --command 覆盖了默认入口点，设置为 "bash"
# --args 覆盖了默认命令，设置为 "-c" 和 "env"
# 最终在容器内执行的命令是: bash -c env
gcloud run jobs execute your-agent-job \
  --command="bash" \
  --args="-c,env" \
  --region=us-central1 \
  --wait
```

**示例 2：执行一个下载自远程的脚本**

这种模式非常灵活，容器内只需要有 `bash` 和 `curl`，具体的执行逻辑可以动态下载。

```bash
gcloud run jobs execute your-agent-job \
  --args="bash,-c,curl -sSL https://nexus.example.com/releases/1.2.3/deploy.sh | bash" \
  --region=us-central1 \
  --wait
```

> **注意**：当只提供 `--args` 而不提供 `--command` 时，`--args` 会覆盖 Dockerfile 中的 `CMD`，并作为参数传递给 Dockerfile 中定义的 `ENTRYPOINT`。

### **2. 在 Cloud Run 服务 (Service) 中使用**

虽然不那么常用，但您也可以在部署服务时覆盖命令，例如，以不同的模式启动您的应用。

```bash
# 部署一个服务，但以调试模式启动
gcloud run deploy your-web-service \
  --image="gcr.io/my-project/my-app" \
  --command="npm" \
  --args="run,debug" \
  --region=us-central1
```

---

## **最佳实践：使用 `entrypoint.sh` 包装脚本**

为了获得最大的灵活性和可维护性，推荐的最佳实践是使用一个包装脚本（例如 `entrypoint.sh`）作为容器的 `ENTRYPOINT`。

**优势:**

1.  **预处理能力**：在执行主命令前，可以获取密钥、配置凭证等。
2.  **逻辑解耦**：将启动逻辑从 `Dockerfile` 中分离，使其更清晰。
3.  **确保正确的信号处理**：通过在脚本末尾使用 `exec "$@"`，您的应用程序将成为主进程 (PID 1)，能够正确接收来自 Cloud Run 的 `SIGTERM` 信号以实现优雅停机。如果缺少 `exec`，您的应用可能会被强制终止。

### **示例 `Dockerfile`**

```dockerfile
FROM ubuntu:22.04
WORKDIR /app

# 安装您的代理和工具
# COPY ./agent /app/agent

# 复制并设置入口点脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 定义容器的入口点
ENTRYPOINT ["entrypoint.sh"]

# 提供一个默认的、可被覆盖的 CMD
CMD ["/app/agent", "--help"]
```

### **示例 `entrypoint.sh`**

```bash
#!/bin/sh
# 使用 POSIX 兼容的 shell
set -e

echo "Container entrypoint script started."

# 在此添加预检逻辑, e.g., 从 Secret Manager 获取密钥
# export DB_PASSWORD=$(gcloud secrets versions access latest --secret="db-password")

echo "Executing command: $@"

# 使用 exec 将控制权传递给 CMD 或运行时指定的命令
# "$@" 会将所有传递给脚本的参数原封不动地传递给下一个命令
exec "$@"
```

通过这种模式，您的 `gcloud` 命令变得更简洁，只关注于传递业务逻辑参数即可。

```bash
# 使用了 entrypoint.sh 模式后，只需覆盖 CMD (通过 --args)
gcloud run jobs execute your-agent-job \
  --args="/app/agent,run-release,--version,1.2.4" \
  --region=us-central1 \
  --wait
```

---

## **总结**

| 场景 | `gcloud` 命令 | 效果 |
| :--- | :--- | :--- |
| **调试：查看环境变量** | `gcloud run jobs execute ... --command="bash" --args="-c,env"` | 在容器中执行 `bash -c env`。 |
| **动态任务：执行脚本** | `gcloud run jobs execute ... --args="bash,-c,curl ..."` | 使用容器的默认 `ENTRYPOINT` 执行提供的脚本。 |
| **覆盖应用启动模式** | `gcloud run deploy ... --command="npm" --args="run,debug"` | 覆盖 `Dockerfile` 的 `ENTRYPOINT` 和 `CMD`，以调试模式启动服务。 |
| **最佳实践模式** | `gcloud run jobs execute ... --args="/app/agent,arg1,arg2"` | 触发 `entrypoint.sh`，并由它来执行 `/app/agent arg1 arg2`。 |
