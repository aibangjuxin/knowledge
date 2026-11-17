对于 GCP Cloud Armor 查看 Targets，我可以帮你编写一个命令行查询方式。

以下是查看 Cloud Armor 安全策略及其关联目标的命令：

```bash
# 列出所有 Cloud Armor 安全策略
gcloud compute security-policies list

# 查看特定安全策略的详细信息，包括其关联的目标
gcloud compute security-policies describe POLICY_NAME

# 列出所有与特定安全策略关联的后端服务
gcloud compute backend-services list --format="table(name,securityPolicy.basename())" --filter="securityPolicy:POLICY_NAME"
```

其中：
1. 第一个命令会列出所有安全策略
2. 第二个命令会显示特定策略的详细配置
3. 第三个命令会显示与该策略关联的所有后端服务

你也可以使用以下命令来查看更详细的信息：

```bash
# 查看特定安全策略的所有规则和目标
gcloud compute security-policies describe POLICY_NAME --format="yaml"
```

如果你想要一个更具体的过滤，可以使用：

```bash
# 使用 JQ 来格式化输出
gcloud compute security-policies describe POLICY_NAME --format=json | jq '.targetResources[]'
```

注意：请将 `POLICY_NAME` 替换为你实际的安全策略名称。