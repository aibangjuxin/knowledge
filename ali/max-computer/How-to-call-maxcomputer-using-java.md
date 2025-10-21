# 如何通过 Java SDK 调用 MaxCompute（最简实践）

本文档旨在提供一个最简化的端到端指南，帮助你通过 Java SDK 直接访问阿里云 MaxCompute，执行一个简单的查询，并将其封装成一个可供调用的 API。这个过程**完全不需要**依赖 DataWorks。

---

## 🧩 一、核心目标与实现路径

> 🎯 **目标**：
> 验证 MaxCompute 的可访问性与基本查询能力，并提供一个 Java API 来触发这个验证。

> ✅ **结论**：
> 你只需要一个 **MaxCompute Project**、**AccessKey** 和 **Endpoint**，就可以直接通过 Java SDK 与 MaxCompute 交互。

---

## 🏗️ 二、准备工作：三要素

在开始编码之前，请确保你已准备好以下三个关键信息：

| 要素 | 说明 | 示例 |
| :--- | :--- | :--- |
| **1. MaxCompute Project** | 你的数据存储和计算的逻辑单元，相当于“数据库”。 | `my_mc_project` |
| **2. AccessKey & Secret** | 访问阿里云服务的凭证，建议使用 RAM 用户的 Key。 | `LTAI5t...` / `m4q8g...` |
| **3. Endpoint** | MaxCompute 服务的接入地址，根据你的 Project 所在地域决定。 | `http://service.cn-hangzhou.maxcompute.aliyun.com/api` |

---

## 🚀 三、实现步骤：从代码到 API

### **步骤 1：在项目中添加 Maven 依赖**

在你的 `pom.xml` 文件中，加入 MaxCompute Java SDK 的核心依赖：

```xml
<dependency>
    <groupId>com.aliyun.odps</groupId>
    <artifactId>odps-sdk-core</artifactId>
    <!-- 建议使用最新版本 -->
    <version>0.46.0-public</version>
</dependency>
```

### **步骤 2：创建测试表和数据（可选）**

为了让查询有内容，你可以在 MaxCompute 控制台执行以下 SQL，创建一张测试表并插入数据。

```sql
-- 如果没有表，可以创建一个用于测试
CREATE TABLE IF NOT EXISTS health_check_table (id BIGINT, name STRING);

-- 插入一些数据，如果表已存在且有数据，此步可省略
INSERT OVERWRITE INTO TABLE health_check_table VALUES (1, 'test_user');
```

如果只是为了验证连通性，也可以执行 `SELECT 1;` 这样的简单查询，这样就不需要创建表。

### **步骤 3：编写核心 Java 调用代码**

以下是一个最简单的 Java 类，用于连接 MaxCompute 并执行查询。

```java
import com.aliyun.odps.Odps;
import com.aliyun.odps.Instance;
import com.aliyun.odps.account.AliyunAccount;
import com.aliyun.odps.task.SQLTask;

public class MaxComputeConnector {

    public static boolean checkConnectivity() throws Exception {
        // 1. 从环境变量或配置中心获取凭证信息
        String accessId = System.getenv("ALICLOUD_ACCESS_KEY");
        String accessKey = System.getenv("ALICLOUD_SECRET_KEY");
        String project = System.getenv("MAXCOMPUTE_PROJECT");
        String endpoint = System.getenv("MAXCOMPUTE_ENDPOINT");

        // 2. 创建阿里云账号及 Odps 实例
        AliyunAccount account = new AliyunAccount(accessId, accessKey);
        Odps odps = new Odps(account);
        odps.setEndpoint(endpoint);
        odps.setDefaultProject(project);

        // 3. 定义并执行一个最简单的 SQL
        // String sql = "SELECT * FROM health_check_table LIMIT 1;";
        String sql = "SELECT 1;"; // 使用这个更简单，无需建表

        System.out.println("Executing SQL: " + sql);
        Instance instance = SQLTask.run(odps, sql);
        
        // 4. 等待任务成功
        instance.waitForSuccess();
        
        System.out.println("MaxCompute health check successful. Instance ID: " + instance.getId());
        return true;
    }

    // 你可以独立运行 main 方法来测试
    public static void main(String[] args) {
        try {
            // 在运行前，请确保已设置以下环境变量
            // export ALICLOUD_ACCESS_KEY="your-access-id"
            // export ALICLOUD_SECRET_KEY="your-access-key"
            // export MAXCOMPUTE_PROJECT="your-mc-project"
            // export MAXCOMPUTE_ENDPOINT="your-mc-endpoint"
            if (checkConnectivity()) {
                System.out.println("✅ Connection to MaxCompute is OK.");
            }
        } catch (Exception e) {
            System.err.println("❌ Failed to connect to MaxCompute.");
            e.printStackTrace();
        }
    }
}
```

### **步骤 4：封装成 Spring Boot 健康检查接口**

将上面的调用逻辑封装到一个 Spring Boot 的 Controller 中，即可实现 API 验证。

```java
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class MaxComputeHealthController {

    @GetMapping("/api/health/maxcompute")
    public ResponseEntity<String> checkMaxComputeHealth() {
        try {
            // 调用我们之前创建的连接器
            boolean isSuccess = MaxComputeConnector.checkConnectivity();
            if (isSuccess) {
                return ResponseEntity.ok("OK: Successfully connected to MaxCompute and executed a query.");
            } else {
                // 这种情况理论上不会发生，因为 checkConnectivity 失败会抛异常
                return ResponseEntity.status(500).body("FAILED: Unknown error.");
            }
        } catch (Exception e) {
            // 捕获所有异常，并返回失败信息
            e.printStackTrace();
            return ResponseEntity.status(500).body("FAILED: " + e.getMessage());
        }
    }
}
```

---

## 📊 四、流程图

下面是这个简单 API 的工作流程：

```mermaid
graph TD
    A[HTTP GET /api/health/maxcompute] --> B[MaxComputeHealthController];
    B --> C[调用 MaxComputeConnector.checkConnectivity()];
    C --> D[读取环境变量配置];
    D --> E[创建 Odps 实例];
    E --> F[通过网络连接到 MaxCompute Endpoint];
    F --> G[执行 SQL: SELECT 1];
    G -- 成功 --> H[返回 Instance ID];
    H --> I[Controller 返回 HTTP 200 OK];
    G -- 失败 --> J[抛出异常];
    J --> K[Controller 返回 HTTP 500 FAILED];
```

---

## ⚙️ 五、最佳实践与注意事项

| 类别 | 建议 |
| :--- | :--- |
| **凭证管理** | **绝对不要**将 AccessKey 硬编码在代码中。优先使用**环境变量**或**配置中心**（如 Nacos、Apollo）来管理。 |
| **权限最小化** | 为该程序创建一个专用的 RAM 用户，并只授予其访问目标 Project 的**只读权限**。 |
| **网络访问** | 如果你的 Java 应用部署在 VPC 内，请确保网络策略允许访问 MaxCompute 的 Endpoint 地址。 |
| **健康检查 SQL** | 使用 `SELECT 1;` 作为健康检查查询。它最轻量，不依赖任何表，且能有效验证计算引擎的可用性。 |
| **超时与重试** | 在生产环境中，可以为 `instance.waitForSuccess()` 设置超时时间，并根据需要添加重试逻辑。 |

---

现在，你只需要将上述代码集成到你的项目中，配置好环境变量，然后启动服务，即可通过访问 `/api/health/maxcompute` 来验证与 MaxCompute 的连通性。
