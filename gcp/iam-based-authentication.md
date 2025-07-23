# Summary

- a
- 我有这样一个问题，运行在 GCP 工程 A 里面的一个 GKE 的 Pod

通过 workload Identify 启动 Pod 这个 Pod 需要连接 GCP 工程 B 里面的 pub/sub

我们是通过 IAM Based Authentication 的方式来实现的。

我也验证了 A 工程 GKE SA 绑定了正确的另外一个工程 B 的 GCE SA 比如叫pub-sub@project-b.iam.gserviceaccount.com

B 工程的 GCE SA 也有对应的 Role

那么现在 A 工程的 Pod 报错

failed to connect to pub/sub APIs,

Check your credentials and verify you have proper access to the service.

是不是代码没有走 IAM Based Authentication 的验证方式呢？

帮我整理这个过程？或者可能的 java 代码部分

# Claude

基于你的描述，这是一个典型的跨项目 Workload Identity 认证问题。让我帮你分析整个流程和可能的问题点。

## Workload Identity 跨项目认证流程

```mermaid
flowchart TD
    A[GKE Pod in Project A] --> B[使用Workload Identity]
    B --> C[绑定到KSA Kubernetes Service Account]
    C --> D[KSA绑定到GSA Google Service Account]
    D --> E[GSA: pub-sub@project-b.iam.gserviceaccount.com]
    E --> F[验证Project B的Pub/Sub权限]
    F --> G{认证成功?}
    G -->|Yes| H[访问Project B Pub/Sub]
    G -->|No| I[Authentication Failed]

    subgraph "Project A"
        J[GKE Cluster]
        K[Kubernetes SA]
    end

    subgraph "Project B"
        L[Google Service Account]
        M[Pub/Sub Topics/Subscriptions]
        N[IAM Roles]
    end
```

## 检查清单和可能问题

### 1. Workload Identity 配置验证

```bash
# 检查GKE集群是否启用了Workload Identity
gcloud container clusters describe CLUSTER_NAME \
    --zone=ZONE \
    --project=PROJECT_A \
    --format="value(workloadIdentityConfig.workloadPool)"

# 检查节点池配置
gcloud container node-pools describe NODE_POOL_NAME \
    --cluster=CLUSTER_NAME \
    --zone=ZONE \
    --project=PROJECT_A \
    --format="value(config.workloadMetadataConfig.mode)"
```

### 2. Service Account 绑定验证

```bash
# 检查KSA到GSA的绑定
kubectl describe serviceaccount KSA_NAME -n NAMESPACE

# 检查GSA的IAM绑定
gcloud iam service-accounts get-iam-policy \
    pub-sub@project-b.iam.gserviceaccount.com \
    --project=PROJECT_B
```

### 3. 必需的 IAM 角色配置

| 角色类型               | 角色名称                         | 应用对象       | 作用域    |
| ---------------------- | -------------------------------- | -------------- | --------- |
| Workload Identity User | `roles/iam.workloadIdentityUser` | KSA 绑定到 GSA | Project B |
| Pub/Sub Publisher      | `roles/pubsub.publisher`         | GSA            | Project B |
| Pub/Sub Subscriber     | `roles/pubsub.subscriber`        | GSA            | Project B |
| Pub/Sub Viewer         | `roles/pubsub.viewer`            | GSA            | Project B |

### 4. Java 代码实现

#### 正确的 IAM Based Authentication 方式

```java
import com.google.cloud.pubsub.v1.Publisher;
import com.google.cloud.pubsub.v1.Subscriber;
import com.google.api.gax.core.CredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.pubsub.v1.TopicName;
import com.google.protobuf.ByteString;
import com.google.pubsub.v1.PubsubMessage;

public class PubSubClient {

    private final String projectId = "project-b";
    private final String topicId = "your-topic";

    // 使用默认凭据链，支持Workload Identity
    public Publisher createPublisher() throws IOException {
        TopicName topicName = TopicName.of(projectId, topicId);

        // 不要手动指定凭据，让Google Cloud SDK自动处理
        Publisher publisher = Publisher.newBuilder(topicName)
            .build();

        return publisher;
    }

    // 错误示例：手动指定Service Account Key
    public Publisher createPublisherWrong() throws IOException {
        TopicName topicName = TopicName.of(projectId, topicId);

        // ❌ 这样会绕过Workload Identity
        GoogleCredentials credentials = GoogleCredentials
            .fromStream(new FileInputStream("service-account-key.json"));

        Publisher publisher = Publisher.newBuilder(topicName)
            .setCredentialsProvider(() -> credentials)
            .build();

        return publisher;
    }
}
```

#### 完整的连接测试代码

```java
import com.google.api.core.ApiFuture;
import com.google.cloud.pubsub.v1.Publisher;
import com.google.protobuf.ByteString;
import com.google.pubsub.v1.PubsubMessage;
import java.util.concurrent.TimeUnit;

public class PubSubTest {

    public void testConnection() {
        try {
            // 创建Publisher，使用默认凭据
            Publisher publisher = createPublisher();

            // 发送测试消息
            PubsubMessage message = PubsubMessage.newBuilder()
                .setData(ByteString.copyFromUtf8("Test message"))
                .build();

            ApiFuture<String> messageIdFuture = publisher.publish(message);
            String messageId = messageIdFuture.get();

            System.out.println("Published message ID: " + messageId);

            publisher.shutdown();
            publisher.awaitTermination(1, TimeUnit.MINUTES);

        } catch (Exception e) {
            System.err.println("Connection failed: " + e.getMessage());
            e.printStackTrace();
        }
    }
}
```

## 排查步骤

### 1. Pod 内验证身份

```bash
# 在Pod内执行
kubectl exec -it POD_NAME -- /bin/bash

# 检查元数据服务
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email

# 检查token
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token
```

### 2. 验证权限

```bash
# 使用gcloud在Pod内测试
gcloud auth list
gcloud config set project project-b
gcloud pubsub topics list
```

## 常见问题和解决方案

### 问题 1: 代码使用了错误的认证方式

**症状**: 即使 Workload Identity 配置正确，仍然认证失败

**解决方案**:

- 确保代码中没有手动指定 Service Account Key 文件
- 不要设置`GOOGLE_APPLICATION_CREDENTIALS`环境变量
- 使用默认的`GoogleCredentials.getApplicationDefault()`

### 问题 2: IAM 绑定不正确

```bash
# 正确的绑定命令
gcloud iam service-accounts add-iam-policy-binding \
    pub-sub@project-b.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:project-a.svc.id.goog[NAMESPACE/KSA_NAME]" \
    --project=PROJECT_B
```

### 问题 3: Pod 配置缺少 Service Account

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pubsub-pod
spec:
  serviceAccountName: workload-identity-sa  # 必须指定
  containers:
  - name: app
    image: your-image
```

通过以上检查，应该能够定位到具体的问题所在。最常见的问题是代码中意外使用了其他认证方式，绕过了 Workload Identity 机制。​​​​​​​​​​​​​​​​

# ChatGPT

以下是你遇到的问题的分析、IAM based authentication 的工作原理、可能的错误原因，以及对应的 Java 示例代码检查建议，均以 Markdown 原始格式输出：

🧩 场景说明

你当前的结构是：

- GCP Project A:

- 部署 GKE Pod
- Pod 使用 Workload Identity 绑定到 Project B 的服务账号 pub-sub@project-b.iam.gserviceaccount.com

-
- GCP Project B:

- 托管 Pub/Sub 服务
- 服务账号 pub-sub@project-b.iam.gserviceaccount.com 拥有正确的 Pub/Sub 权限（例如 roles/pubsub.publisher）

-

你遇到的报错：

failed to connect to pub/sub APIs, Check your credentials and verify you have proper access to the service.

✅ 正常流程（Workload Identity + IAM Based Auth）

graph TD;

A[GKE Pod in Project A] --> B[GKE Metadata Server 提供 token];

B --> C[Service Account: pub-sub@project-b];

C --> D[Pub/Sub API in Project B];

正确配置检查流程：

1. Project A 中的 GKE Pod 的 Kubernetes SA 是否绑定了 GCP SA：

gcloud iam service-accounts add-iam-policy-binding \

pub-sub@project-b.iam.gserviceaccount.com \

--role roles/iam.workloadIdentityUser \

--member "serviceAccount:project-a.svc.id.goog[namespace/k8s-sa-name]"

1.

2.  GKE 中的 Pod 是否添加了 annotation：

annotations:

iam.gke.io/gcp-service-account: "pub-sub@project-b.iam.gserviceaccount.com"

2.

3.  GKE Cluster 是否启用了 Workload Identity：

gcloud container clusters describe [CLUSTER_NAME] \

--region=[REGION] \

--format="value(workloadIdentityConfig.workloadPool)"

3. 输出应为 project-a.svc.id.goog

🚨 可能的错误原因分析

|                                                     |                                                  |
| --------------------------------------------------- | ------------------------------------------------ |
| 排查项                                              | 说明                                             |
| 未正确设置 IAM Binding                              | workloadIdentityUser 权限缺失                    |
| Pod annotation 错误或缺失                           | 绑定 SA 的 annotation 没加或拼错                 |
| 应用未使用默认 Application Default Credential (ADC) | Java 代码未使用 ADC 加载 GCP 认证                |
| Pod 没有访问 metadata server 权限                   | 防火墙或 DNS 被屏蔽 metadata                     |
| Pub/Sub Client 初始化方式错误                       | 手动指定了不正确的 key.json 或使用 Basic Auth 等 |

🔍 Java 正确用法参考（使用 ADC）

以下是一个 Java 示例，使用的是 ADC 自动方式，让系统通过 GKE 上下文自动获取绑定的服务账号。

import com.google.cloud.pubsub.v1.Publisher;

import com.google.pubsub.v1.TopicName;

import com.google.protobuf.ByteString;

import com.google.pubsub.v1.PubsubMessage;

public class PubSubPublisher {

public static void main(String[] args) throws Exception {

String projectId = "project-b";

String topicId = "my-topic";

TopicName topicName = TopicName.of(projectId, topicId);

Publisher publisher = Publisher.newBuilder(topicName).build();

String message = "hello world";

ByteString data = ByteString.copyFromUtf8(message);

PubsubMessage pubsubMessage = PubsubMessage.newBuilder().setData(data).build();

publisher.publish(pubsubMessage).get();

publisher.shutdown();

}

}

✅ 注意：上面没有显式传入 service account key，这是 Workload Identity 的要求，必须依赖环境变量 GOOGLE_APPLICATION_CREDENTIALS 未设置。

🧪 验证建议

你可以在 Pod 里运行以下命令，确认当前使用的是哪个 SA：

curl -H "Metadata-Flavor: Google" \

http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email

结果应为：

pub-sub@project-b.iam.gserviceaccount.com

✅ 总结建议

|                           |                                                       |
| ------------------------- | ----------------------------------------------------- |
| 动作                      | 说明                                                  |
| 检查 KSA annotation       | iam.gke.io/gcp-service-account 必须正确配置           |
| 检查 Java 是否自动用 ADC  | 不要在代码中使用 key.json，必须用默认 credential      |
| 检查 IAM 权限             | roles/pubsub.publisher 是否分配给了 pub-sub@project-b |
| 检查 metadata server 通信 | Pod 内 curl metadata 确保能拿到 token                 |

如需我帮你检查你现有 Pod 的 YAML、IAM binding 命令、或 Java 代码片段，可发给我我帮你分析。
