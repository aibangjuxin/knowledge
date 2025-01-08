- [update](#update)
    - [**通过命令行查询修改记录**](#通过命令行查询修改记录)
    - [**通过 Console 查询修改记录**](#通过-console-查询修改记录)
    - [**验证是否修改成功**](#验证是否修改成功)
    - [**总结**](#总结)
- [filter response policy](#filter-response-policy)
    - [替换信息说明](#替换信息说明)
  - [\*\*\*\* 跟踪DNS记录的变化](#-跟踪dns记录的变化)
  - [\*\*\*\* 启用和查看DNS查询日志](#-启用和查看dns查询日志)
  - [\*\*\*\* 管理响应策略](#-管理响应策略)
  - [\*\*\*\* 示例日志过滤条件](#-示例日志过滤条件)

# update
要查询 Google Cloud 中 DNS Response Policy 的修改记录，可以通过 **Cloud Logging (以前叫 Stackdriver)** 查看相关的操作日志，因为 Google Cloud 会记录所有的管理操作日志，包括对 DNS Response Policy 的修改。

以下是两种方式（命令行和 Console）来完成这个任务：

gcloud logging read "resource.labels.method=dns.responsePolicyRules.patch"

---

### **通过命令行查询修改记录**

1. **启用 Cloud Logging**
   确保项目中启用了 Cloud Logging，并且操作日志（Audit Logs）已记录。

2. **过滤 DNS Response Policy 修改记录**
   使用 `gcloud logging read` 命令查询日志，并过滤与 Response Policy 修改相关的日志条目。示例如下：

   ```bash
   gcloud logging read 'resource.type="dns_policy" AND protoPayload.methodName="dns.policies.update"' --limit=50 --format=json
   ```

   - `resource.type="dns_policy"`：表示过滤 DNS Response Policy 相关的资源。
   - `protoPayload.methodName="dns.policies.update"`：表示过滤修改操作的日志。
   - `--limit=50`：显示最近 50 条日志。
   - `--format=json`：以 JSON 格式输出结果，便于进一步分析。

3. **解析结果**
   输出的 JSON 会包含以下关键信息：
   - `protoPayload.request`：包含具体的修改内容。
   - `protoPayload.authenticationInfo.principalEmail`：显示执行操作的用户。
   - `timestamp`：显示操作的时间。

---

### **通过 Console 查询修改记录**

1. **进入 Cloud Logging**
   - 登录到 [Google Cloud Console](https://console.cloud.google.com/).
   - 导航到 **Logging** > **Logs Explorer**。

2. **构建过滤器**
   在 Logs Explorer 中，使用以下过滤器语法：
   ```plaintext
   resource.type="dns_policy"
   protoPayload.methodName="dns.policies.update"
   ```

3. **查看操作记录**
   - Logs Explorer 会显示所有与 DNS Response Policy 修改相关的操作日志。
   - 每条日志条目会显示时间、执行用户、修改内容等详细信息。

---

### **验证是否修改成功**

1. **列出所有 Response Policies**
   使用以下命令验证当前配置是否符合预期：
   ```bash
   gcloud dns policies list
   ```

2. **查看单个 Response Policy 的详情**
   检查某个具体 Response Policy 的配置：
   ```bash
   gcloud dns policies describe [POLICY_NAME]
   ```

3. **日志反查**
   如果发现配置有误，可以通过日志进一步分析修改的来源。

---

### **总结**

- **命令行**：使用 `gcloud logging read` 配合 `dns.policies.update` 方法名过滤日志。
- **Console**：通过 **Logs Explorer** 使用类似的过滤条件。
- 结合日志内容和当前配置的实际状态，可以排查问题或验证修改是否符合预期。


# filter response policy 

Based on the provided JSON log entry, here are some basic filter examples for Cloud Logging to target Response Policy Rule changes in your GCP project:

**1. Filtering by `serviceName`:**

This filter isolates all DNS Response Policy Rule activity.

```gcloud
gcloud logging read "serviceName=dns.googleapis.com"
```

**2. Filtering by `resource.labels.method`:**

This filter specifically targets patch operations on Response Policy Rules.
- 这个没有问题 验证
```gcloud
gcloud logging read "resource.labels.method=dns.responsePolicyRules.patch"

或者我直接页面过滤
dns.responsePolicyRules.update
protoPayload.resourceName="responsePolicyRules/name"

```

**3. Filtering by `protoPayload.methodName`:**

This option allows you to filter based on specific API methods called.  For example, to find updates:

```gcloud
gcloud logging read "protoPayload.methodName=dns.responsePolicyRules.patch"
```

For creates (if you were creating new rules):

```gcloud
gcloud logging read "protoPayload.methodName=dns.responsePolicyRules.create"
```

For deletes:

```gcloud
gcloud logging read "protoPayload.methodName=dns.responsePolicyRules.delete"
```


**4. Filtering by `resource.labels.project_id`:**

This filter narrows down the results to a specific project.  Replace  `YOUR_PROJECT_ID` with your actual project ID.

```gcloud
gcloud logging read "resource.labels.project_id=YOUR_PROJECT_ID"
```

**5. Combining Filters:**

You can combine these filters using `AND` and `OR` operators for more granular control. For example, to find all patch operations in a specific project:

```gcloud
gcloud logging read "resource.labels.method=dns.responsePolicyRules.patch AND resource.labels.project_id=YOUR_PROJECT_ID"
```


**6. Filtering by `protoPayload.resourceName`:**

This allows you to filter by the specific resource name, which includes the policy and rule name. You'll need to adjust the resource name to match your environment.

```gcloud
gcloud logging read "protoPayload.resourceName=projects/YOUR_PROJECT_ID/responsePolicies/YOUR_POLICY_NAME/rules/YOUR_RULE_NAME"
```

**7.  Filtering by specific fields within `protoPayload.request` or `protoPayload.response`:**

You can filter based on the content of the request or response. For example, if you are patching a specific field, you could filter based on its presence in  `protoPayload.request`. This requires careful inspection of the request structure.



Remember to adapt these examples to your specific project and requirements.  You can test and refine these filters directly in the Cloud Logging console to ensure they capture the events you're interested in.  The console also provides a convenient interface for exploring the structure of log entries, which helps in constructing more complex filters.




```json
{
  "insertId": "mdrdppry9vu",
  "logName": "projects/****-*****-prod/logs/cloudaudit.googleapis.com%2Factivity",
  "protoPayload": {
    "@type": "type.googleapis.com/google.cloud.audit.AuditLog",
    "authenticationInfo": {
      "principalEmail": "************@notreceivingmail.abjxc.com"
    },
    "authorizationInfo": {
      "granted": true,
      "permission": "dns.responsePolicyRules.update",
      "permissionType": "ADMIN_WRITE"
    },
    "resourceAttributes": {
      "methodName": "dns.responsePolicyRules.patch",
      "request": {
        "@type": "type.googleapis.com/cloud.dns.api.ResponsePolicyRulesPatchRequest",
        "project": "****-*****-prod",
        "responsePolicyRule": "ss",
        "responsePolicyRule": {
          "dnsName": "search.gcp.aibang.local.com.",
          "localData": {
            "localData": {
              "name": "search.gcp.aibang.local.com.",
              "rrdata": [
                "192.168.1.8"
              ],
              "ttl": 300
            }
          }
        }
      },
      "requestMetadata": {
        "callerIp": "114.114.114.114",
        "destinationAttributes": {},
        "requestAttributes": {
          "auth": {}
        }
      },
      "time": "2020-12-02T07:23:44.316429Z"
    },
    "resourceName": "responsePolicyRules/ss",
    "response": {
      "@type": "type.googleapis.com/cloud.dns.api.ResponsePolicyRulesPatchResponse",
      "responsePolicyRule": {
        "dnsName": "search.gcp.aibang.local.com.",
        "localData": {
          "localData": {
            "name": "search.gcp.aibang.local.com.",
            "rrdata": [
              "192.168.64.47"
            ],
            "ttl": 300,
            "type": "A"
          }
        }
      },
      "ruleName": "ss",
      "serviceName": "dns.googleapis.com"
    },
    "receiveTimestamp": "2020-12-02T07:23:45.240303926Z",
    "source": {
      "method": "dns.responsePolicyRules.patch",
      "project_id": "****-*****-prod"
    },
    "resource": {
      "labels": {
        "method": "dns.responsePolicyRules.patch",
        "project_id": "****-*****-prod"
      }
    },
    "severity": "NOTICE",
    "timestamp": "2020-12-02T07:23:44.275388Z"
}
```

### 替换信息说明

- 将敏感项目名称和邮件地址替换为 `****` 和 `************`，以便隐藏真实信息。
- 其他请求和响应的详细信息保持不变，以便于分析和审计。



在 GCP 中，跟踪 DNS 记录的创建、删除、更新操作以及对特殊的响应策略（response policy）的更改，可以使用 Audit Logs 和 Cloud Logging。GCP 的 Audit Logs 包含对资源的管理操作日志记录，可以用来监控 Cloud DNS 的变更。

以下是跟踪 GCP Cloud DNS 记录相关变更的步骤与示例。

1. 启用 Cloud DNS 审计日志

确保 GCP 项目中已启用 Cloud DNS 的 Admin Activity 日志。该日志记录所有管理操作，包括 DNS 记录和响应策略的创建、更新、删除。

2. 使用 gcloud 命令行查看 Cloud DNS 日志

通过 gcloud 命令可以直接从命令行访问 Cloud Logging 中的日志。以下命令用于查询特定 Cloud DNS 的记录更改：
```bash
gcloud logging read 'resource.type="dns_managed_zone" AND protoPayload.methodName=("dns.changes.create" OR "dns.responsePolicies.patch" OR "dns.responsePolicies.create" OR "dns.responsePolicies.delete")' \
    --project=[PROJECT_ID] \
    --format="json" \
    --limit=20
```
	•	dns.changes.create：表示 DNS 记录的创建。
	•	dns.responsePolicies.create：表示响应策略的创建。
	•	dns.responsePolicies.patch：表示响应策略的更新。
	•	dns.responsePolicies.delete：表示响应策略的删除。

3. 使用过滤条件精确查找变更日志

以下是几个常用的过滤条件，可以根据需求定制查询：

a. 查询某个特定 DNS 记录集的更改

要查询特定 DNS 记录集（例如 example.com.）的更改记录，可以加上 protoPayload.request.resource.name 的过滤条件：

```bash
gcloud logging read 'resource.type="dns_managed_zone" AND protoPayload.methodName="dns.changes.create" AND protoPayload.request.resource.name:"example.com."' \
    --project=[PROJECT_ID] \
    --format="json"
```
b. 查询 DNS 响应策略的创建或更新操作

对于响应策略（Response Policy）操作，可以过滤 dns.responsePolicies.create 和 dns.responsePolicies.patch 方法：

```bash
gcloud logging read 'resource.type="dns_managed_zone" AND (protoPayload.methodName="dns.responsePolicies.create" OR protoPayload.methodName="dns.responsePolicies.patch")' \
    --project=[PROJECT_ID] \
    --format="json"
```
c. 查询 DNS 记录的删除

DNS 记录删除一般可以通过 dns.changes.create 方法过滤，但 delete 操作可以在 protoPayload.request.delete_resource_record_set 中找到。例如：

```bash
gcloud logging read 'resource.type="dns_managed_zone" AND protoPayload.methodName="dns.changes.create" AND protoPayload.request.delete_resource_record_set' \
    --project=[PROJECT_ID] \
    --format="json"
```
4. 查看 Cloud Console 中的详细变更日志

如需更详细的日志信息，可以在 Cloud Console > Logging 中使用下列条件进行过滤：

```bash
resource.type="dns_managed_zone"
protoPayload.methodName=("dns.changes.create", "dns.responsePolicies.patch", "dns.responsePolicies.create", "dns.responsePolicies.delete")
```
示例输出格式

以下是命令输出的 JSON 示例：

```json
[
  {
    "insertId": "1abcde2fgh3ijk4lm5",
    "resource": {
      "type": "dns_managed_zone",
      "labels": {
        "zone_name": "example-zone",
        "project_id": "[PROJECT_ID]"
      }
    },
    "protoPayload": {
      "methodName": "dns.changes.create",
      "request": {
        "resource": {
          "name": "example.com.",
          "type": "A",
          "ttl": 300,
          "rrdatas": [
            "1.2.3.4"
          ]
        }
      },
      "serviceName": "dns.googleapis.com",
      "status": {}
    },
    "timestamp": "2023-10-12T10:00:00Z"
  },
  ...
]
```
注意事项

	1.	项目和权限：确保你有查看 Cloud DNS 相关 Audit Logs 的权限（通常需要 Logging Viewer 角色）。
	2.	日志存储时间：Audit Logs 可能会有存储时间限制，若需长期跟踪可将日志导出至 BigQuery 进行分析和存储。


了解您对监控 GCP 工程中的 DNS 变更信息感兴趣。我为您提供一些相关的命令行和日志筛选的示例:

1. 获取 DNS 记录的创建、更新和删除操作:

   ```
   gcloud logging read "resource.type=dns_resource_record and protoPayload.methodName IN ('createResourceRecordSet', 'updateResourceRecordSet', 'deleteResourceRecordSet')" --format="json"
   ```

   这个命令会列出所有 DNS 记录的增、改、删操作的日志信息。您可以根据需要调整日志的输出格式。

2. 获取 Response Policy 的创建、更新和删除操作:

   ```
   gcloud logging read "resource.type=dns_response_policy and protoPayload.methodName IN ('createResponsePolicy', 'updateResponsePolicy', 'deleteResponsePolicy')" --format="json" 
   ```

   这个命令会列出所有 Response Policy 的增、改、删操作的日志信息。

3. 获取特定 DNS 区域的变更情况:

   ```
   gcloud logging read "resource.type=dns_resource_record AND resource.labels.zone_name='your-zone-name'" --format="json"
   ```

   将 `'your-zone-name'` 替换为您关注的特定 DNS 区域名称。这样可以筛选出该区域内所有 DNS 记录的变更日志。

4. 获取特定 DNS 记录的变更情况:

   ```
   gcloud logging read "resource.type=dns_resource_record AND jsonPayload.name='your.domain.com.'" --format="json"
   ```

   将 `'your.domain.com.'` 替换为您关注的特定 DNS 记录名称。这样可以筛选出该记录的所有变更日志。

您可以根据自己的需求组合这些查询条件,获取更精确的日志信息。同时您也可以利用 GCP 提供的各种日志导出和分析工具,进一步处理和可视化这些日志数据。如果您有任何其他问题,欢迎随时询问我。​​​​​​​​​​​​​​​​


 在Google Cloud Platform (GCP)的DNS管理中，跟踪DNS记录的创建、修改和删除是确保网络安全和合规性的重要措施。以下是一些针对DNS记录和响应策略的日志过滤条件以及命令行示例，帮助你获取相关信息。

## **** 跟踪DNS记录的变化

要跟踪DNS记录的变化，可以使用以下命令：

- **列出DNS记录集的变化**：
  
  ```bash
  gcloud dns record-sets changes list --zone="your-zone-name"
  ```

  此命令将显示指定区域内所有DNS记录集的变化历史，包括变化ID、开始时间和状态。

- **查看特定变化的详细信息**：

  ```bash
  gcloud dns record-sets changes describe CHANGE_ID --zone="your-zone-name"
  ```

  将`CHANGE_ID`替换为你想要查看的具体变化ID，以获取该变化的详细信息。

## **** 启用和查看DNS查询日志

为了监控DNS查询，你需要启用Cloud DNS日志记录。可以通过以下命令来启用或更新日志记录：

- **为公共托管区域启用日志**：

  ```bash
  gcloud dns managed-zones update your-zone-name --log-dns-queries
  ```

- **为私有托管区域启用日志**：

  ```bash
  gcloud dns policies create POLICY_NAME --networks=NETWORK --enable-logging --description="Enable logging for DNS policy"
  ```

一旦启用了日志记录，你可以通过Google Cloud Console中的Logs Explorer查看DNS查询日志。这些日志将包含关于DNS请求和响应的详细信息，例如请求类型、响应代码和延迟等[1][3]。

## **** 管理响应策略

对于响应策略的创建、更新和删除，可以使用以下命令：

- **创建响应策略**：

  ```bash
  gcloud dns response-policies create RESPONSE_POLICY_NAME --networks=NETWORK --description="My new response policy"
  ```

- **列出响应策略规则**：

  ```bash
  gcloud dns response-policies rules list RESPONSE_POLICY_NAME
  ```

- **查看特定响应策略规则的详细信息**：

  ```bash
  gcloud dns response-policies rules describe RESPONSE_POLICY_RULE_NAME --response-policy=RESPONSE_POLICY_NAME
  ```

这些命令将帮助你管理和监控DNS响应策略的创建、更新和删除情况[2][6]。

## **** 示例日志过滤条件

在Logs Explorer中，你可以使用以下过滤条件来查找特定类型的DNS日志：

```json
resource.type="dns_managed_zone"
logName="projects/YOUR_PROJECT_ID/logs/cloudaudit.googleapis.com%2Fdns_queries"
severity="INFO"
```

通过这些条件，你可以筛选出与DNS相关的重要事件，如查询、更新或删除操作。

综上所述，使用这些命令和过滤条件，你可以有效地跟踪GCP中的DNS活动，确保网络安全和合规性。

Sources
[1] Decoding Logs in the Cloud: GCP Cloud DNS Logs - Cado Security https://www.cadosecurity.com/blog/decoding-logs-in-the-cloud-aliyun.cloud-dns-logs
[2] Audit or change logs on Google Cloud DNS? - Stack Overflow https://stackoverflow.com/questions/35484406/audit-or-change-logs-on-google-cloud-dns
[3] Use logging and monitoring | Cloud DNS https://cloud.google.com/dns/docs/monitoring
[4] Google Cloud Platform (GCP) DNS logs | Documentation - Elastic https://www.elastic.co/docs/current/integrations/gcp/dns
[5] Generate Google Cloud DNS sample logs for the GCP module #12003 https://github.com/wazuh/wazuh/issues/12003
[6] Manage response policies and rules | Cloud DNS https://cloud.google.com/dns/docs/zones/manage-response-policies
[7] Detect GCP Cloud DNS Configuration Changes - Trend Micro https://www.trendmicro.com/cloudoneconformity/knowledge-base/gcp/GKE/aliyun.cloud-dns-configuration-changes-detected.html
[8] Enable Cloud DNS Logging for VPC Networks - Trend Micro https://www.trendmicro.com/cloudoneconformity-staging/knowledge-base/gcp/CloudVPC/dns-logging-for-vpcs.html
[9] How To Generate GCP DNS Logs - Stack Overflow https://stackoverflow.com/questions/67908101/how-to-generate-gcp-dns-logs
[10] Cloud DNS audit logging information https://cloud.google.com/dns/docs/audit-logging
[11] gcloud DNS Commands - Google Cloud DNS - huihoo https://download.huihoo.com/google/gdgdev



在 GCP 中，您可以通过 Cloud Audit Logs 跟踪 Cloud DNS 的创建、修改和删除操作，包括特殊的响应策略（Response Policy）的变更。以下是获取这些日志的步骤和示例。

1. 确认 Cloud DNS 审计日志已启用

GCP 默认会为大多数服务启用审计日志，但建议您在 Cloud Console 的日志页面中确认 Cloud DNS 的审计日志已启用。

2. 使用 gcloud 命令行工具查询日志

您可以使用 gcloud 命令行工具查询特定的 Cloud DNS 操作日志。以下是一些常用的查询示例：

a. 查询所有 Cloud DNS 记录的创建、更新和删除操作

gcloud logging read 'resource.type="dns_managed_zone" AND protoPayload.methodName=("dns.changes.create" OR "dns.changes.update" OR "dns.changes.delete")' \
    --project=[PROJECT_ID] \
    --format="json" \
    --limit=100

	•	resource.type="dns_managed_zone"：指定资源类型为 DNS 托管区域。
	•	protoPayload.methodName：过滤特定的操作方法，包括创建、更新和删除。

b. 查询特定响应策略的创建、更新和删除操作

gcloud logging read 'resource.type="dns_managed_zone" AND protoPayload.methodName=("dns.responsePolicies.create" OR "dns.responsePolicies.patch" OR "dns.responsePolicies.delete")' \
    --project=[PROJECT_ID] \
    --format="json" \
    --limit=100

	•	protoPayload.methodName：过滤与响应策略相关的操作方法，包括创建、更新和删除。

3. 在 Cloud Console 中使用高级日志过滤器

您也可以在 Cloud Console 的日志查看器中使用高级过滤器来查询日志。以下是一个示例过滤器：

resource.type="dns_managed_zone"
protoPayload.methodName=("dns.changes.create" OR "dns.changes.update" OR "dns.changes.delete" OR "dns.responsePolicies.create" OR "dns.responsePolicies.patch" OR "dns.responsePolicies.delete")

此过滤器将显示所有与 DNS 记录和响应策略相关的创建、更新和删除操作。

4. 导出日志以供进一步分析

如果您需要对日志进行长期存储或更深入的分析，可以将日志导出到 BigQuery 或 Cloud Storage。有关详细信息，请参阅 导出日志。

注意事项

	•	权限：确保您拥有查看日志的适当权限，通常需要 Logging Viewer 或更高权限。
	•	日志保留期：默认情况下，审计日志保留 90 天。对于长期分析，建议将日志导出并存储。

通过上述方法，您可以有效地跟踪 GCP 中 Cloud DNS 的所有变更操作，包括特殊响应策略的创建、更新和删除。


在 GCP 项目中跟踪 DNS 记录的创建、更改以及 Response Policy 记录的操作，你可以使用 Google Cloud Logging 和 `gcloud` 命令行工具。以下是一些方法和示例：

**1. 使用 `gcloud logging read` 命令过滤日志：**

这是最通用的方法，可以根据各种条件过滤日志。以下是一些示例：

* **跟踪所有 DNS 记录的更改：**

```bash
gcloud logging read "resource.type=dns_managed_zone AND logName:projects/<PROJECT_ID>/logs/cloudaudit.googleapis.com%2Fdata_access"
```

这个命令会过滤 `cloudaudit.googleapis.com%2Fdata_access` 日志，查找所有与 DNS 托管区域 (dns_managed_zone) 相关的 Data Access audit logs，其中包含了记录的创建、修改和删除操作。


* **跟踪特定托管区域的更改：**

```bash
gcloud logging read "resource.type=dns_managed_zone AND resource.labels.dns_zone=<ZONE_NAME> AND logName:projects/<PROJECT_ID>/logs/cloudaudit.googleapis.com%2Fdata_access"
```

将 `<ZONE_NAME>` 替换为你的托管区域名称，例如 `example.com.`。


* **跟踪特定记录类型的更改 (例如 A 记录):**

```bash
gcloud logging read "protoPayload.methodName:CreateChangeSet OR protoPayload.methodName:UpdateChangeSet AND protoPayload.request.changeSets.additions.rrdatas.type=A AND resource.type=dns_managed_zone AND resource.labels.dns_zone=<ZONE_NAME> AND logName:projects/<PROJECT_ID>/logs/cloudaudit.googleapis.com%2Fdata_access"
```

这个命令会过滤创建和更新变更集的操作，并进一步检查添加的记录中是否存在 A 记录。



* **跟踪 Response Policy 记录的更改：**

```bash
gcloud logging read "resource.type=dns_response_policy_rule AND logName:projects/<PROJECT_ID>/logs/cloudaudit.googleapis.com%2Fdata_access"
```

这个命令会查找所有与 DNS 响应策略规则相关的 Data Access audit logs。  你可以进一步添加条件来过滤特定策略或规则的更改。


* **结合多个条件：**  你可以使用 `AND` 和 `OR` 运算符组合多个过滤条件。


**2.  使用 Logging  高级过滤条件：**

Cloud Logging 提供了更高级的过滤选项，例如：

* `protoPayload.resourceName`：可以根据资源的完整名称过滤日志。
* `protoPayload.authenticationInfo.principalEmail`：可以根据执行操作的用户邮箱过滤日志。
* `protoPayload.metadata.*`：可以访问操作相关的元数据。

**3.  在 Logging 中创建日志指标：**

你可以创建基于特定过滤条件的日志指标，以便持续监控 DNS 记录的更改。


**示例 - 跟踪特定区域中 A 记录的创建：**

```bash
gcloud logging read "protoPayload.methodName=CreateChangeSet AND protoPayload.request.changeSets.additions.rrdatas.type=A AND resource.type=dns_managed_zone AND resource.labels.dns_zone=example.com. AND logName:projects/your-project-id/logs/cloudaudit.googleapis.com%2Fdata_access"
```

**记住替换以下内容：**

* `<PROJECT_ID>`: 你的 GCP 项目 ID.
* `<ZONE_NAME>`:  你的 DNS 托管区域名称.


建议在 Google Cloud Console 的 Logging 界面中探索不同的过滤选项，并根据你的具体需求调整命令。 通过组合这些方法和过滤条件，你可以全面地跟踪 GCP 项目中 DNS 记录和 Response Policy 记录的更改。

