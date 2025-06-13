你可以通过**手动更新 GCP 的 Managed Instance Group (MIG)** 的 **location policy（分布策略）或直接修改 instanceTemplate 并强制重新创建实例**来模拟一个 zone 故障并实现 DR Testing。以下是推荐的做法，适用于 **Regional MIG（即分布于多个 zone 的 MIG）**。

---

## **🎯 目标**

- 当前 MIG 分布在 europe-west2-a 和 europe-west2-b
    
- 现在你想模拟 europe-west2-a zone 故障
    
- 实现目标：将所有实例仅分布到 europe-west2-b 和 europe-west2-c
    

---

## **✅ 步骤说明（推荐方式）**

  

### **步骤 1：更新 Regional MIG 的** 

### **distributionPolicy.zones**

```
gcloud compute instance-groups managed update [MIG_NAME] \
  --region=[REGION] \
  --distribution-policy-zones=europe-west2-b,europe-west2-c
```

- 这条命令会修改 MIG 的 zone 分布策略。
    
- ⚠️ **这不会自动迁移现有实例**，只会影响接下来被替换或扩展的实例位置。
    

---

### **步骤 2：手动触发 Rolling Update（重新创建所有实例）**

  

为了强制现有实例按照新的 zone 策略进行重新部署，你需要触发一次 Rolling Update：

```
gcloud compute instance-groups managed rolling-action start-update [MIG_NAME] \
  --region=[REGION] \
  --type=replace
```

> 这会根据新的 distributionPolicy 把旧实例逐一删除并在新 zone（b、c）中重建。

  

你也可以指定 --max-surge 和 --max-unavailable 控制切换的并发和风险，比如：

```
--max-surge=1 --max-unavailable=0
```

---

### **📝 示例命令（实际替换）**

```
# 更新为 b 和 c zone
gcloud compute instance-groups managed update my-api-mig \
  --region=europe-west2 \
  --distribution-policy-zones=europe-west2-b,europe-west2-c

# 开始 rolling update，重建实例
gcloud compute instance-groups managed rolling-action start-update my-api-mig \
  --region=europe-west2 \
  --type=replace \
  --max-surge=1 \
  --max-unavailable=0
```

---

## **📌 其他方案（仅适合测试）**

  

如果你只是想快速验证 DR，而不想更改分布策略，可以考虑：

  

### **方法：逐个手动删除某个 zone 的实例（GCE 会自动重建）**

```
gcloud compute instances list --filter="zone:(europe-west2-a) AND name~'my-api-mig'" \
  --format="value(name,zone)"
```

然后删除这些实例：

```
gcloud compute instance-groups managed delete-instances my-api-mig \
  --region=europe-west2 \
  --instances=INSTANCE_NAME1,INSTANCE_NAME2
```

由于 MIG 控制，该 zone 的实例会在其余 zone 中重建（根据当前 policy），适合模拟某个 zone 挂掉的行为。

---

## **✅ 建议策略**

|**操作方式**|**说明**|
|---|---|
|修改 distributionPolicy + rolling update|✅ 推荐方式，真实模拟 DR failover|
|手动删除特定 zone 的实例|快速模拟，但不修改策略，适合演练|
|修改 instanceTemplate + update|如果还需要修改镜像等可一并做|

---

如你还希望结合 Mermaid 图解释，可以参考下面：

```
graph TD;
    A[当前 MIG 分布在 A/B] --> B[修改 MIG 策略为 B/C];
    B --> C[执行 Rolling Update];
    C --> D[所有实例重建到 B/C];
```

---

有任何 DR 测试自动化脚本需求也可以继续告诉我，我可以帮你写完整的 gcloud + bash 自动化流程。