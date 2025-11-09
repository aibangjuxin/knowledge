# Claude

# GCP Regional MIG Zone 故障 DR 测试方案

## 问题分析

您的核心需求是：

- 当前环境：2 个实例分布在 2 个 zone
- 测试目标：验证当其中 1 个 zone 故障时，服务能在剩余 zone 保持可用
- 期望结果：确保 zone 级别的高可用性和自动恢复能力

## 解决方案

### 方案设计思路

基于您的场景，推荐采用**渐进式 DR 测试方案**，分为三个阶段：

```mermaid
graph TD
    A[阶段1：环境准备与验证] --> B[阶段2：Zone故障模拟]
    B --> C[阶段3：自动恢复验证]
    C --> D[阶段4：服务可用性确认]

    A --> A1[检查当前实例分布]
    A --> A2[确认MIG配置]
    A --> A3[备份当前配置]

    B --> B1[删除目标zone实例]
    B --> B2[监控MIG行为]

    C --> C1[观察实例重建]
    C --> C2[验证zone分布]

    D --> D1[健康检查验证]
    D --> D2[负载均衡测试]
```

---

## 完整 DR 测试脚本

### 主测试脚本

```bash
#!/bin/bash

#############################################
# GCP Regional MIG Zone DR 测试脚本
# 用途：模拟zone故障并验证自动恢复能力
#############################################

set -e

# ==================== 配置参数 ====================
MIG_NAME="your-mig-name"
REGION="europe-west2"
TARGET_ZONE="europe-west2-a"  # 要模拟故障的zone
EXPECTED_INSTANCE_COUNT=2
HEALTH_CHECK_TIMEOUT=300      # 健康检查超时时间(秒)

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ==================== 函数定义 ====================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取当前实例分布
get_instance_distribution() {
    log_info "获取当前实例分布..."
    gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --region="$REGION" \
        --format="table(instance,zone,status)"
}

# 统计各zone实例数量
count_instances_by_zone() {
    gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --region="$REGION" \
        --format="csv[no-heading](zone)" | sort | uniq -c
}

# 检查MIG配置
check_mig_config() {
    log_info "检查MIG配置..."
    gcloud compute instance-groups managed describe "$MIG_NAME" \
        --region="$REGION" \
        --format="yaml(distributionPolicy,targetSize,autoHealingPolicies)"
}

# 删除指定zone的所有实例
delete_zone_instances() {
    local zone=$1
    log_warn "准备删除zone ${zone} 中的所有实例..."

    # 获取该zone的实例列表
    local instances=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --region="$REGION" \
        --filter="zone:(${zone})" \
        --format="value(instance)")

    if [[ -z "$instances" ]]; then
        log_info "Zone ${zone} 中没有实例，跳过删除。"
        return 0
    fi

    log_info "发现以下实例将被删除："
    echo "$instances"

    # 删除实例
    for instance in $instances; do
        log_info "删除实例: $instance"
        gcloud compute instance-groups managed delete-instances "$MIG_NAME" \
            --region="$REGION" \
            --instances="$instance" \
            --quiet
    done

    log_info "Zone ${zone} 的实例删除完成"
}

# 等待并验证实例重建
wait_for_recovery() {
    local timeout=$1
    local start_time=$(date +%s)

    log_info "等待MIG自动恢复实例..."

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ $elapsed -gt $timeout ]]; then
            log_error "超时！实例恢复时间超过 ${timeout} 秒"
            return 1
        fi

        # 检查当前实例数量
        local current_count=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
            --region="$REGION" \
            --filter="status=RUNNING" \
            --format="value(instance)" | wc -l)

        log_info "当前运行实例数: ${current_count}/${EXPECTED_INSTANCE_COUNT} (耗时: ${elapsed}s)"

        if [[ $current_count -ge $EXPECTED_INSTANCE_COUNT ]]; then
            log_info "✅ 所有实例已恢复"
            return 0
        fi

        sleep 10
    done
}

# 验证zone分布
verify_zone_distribution() {
    log_info "验证实例zone分布..."

    local zone_count=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --region="$REGION" \
        --filter="status=RUNNING" \
        --format="value(zone)" | sort -u | wc -l)

    log_info "实例分布在 ${zone_count} 个zone"

    # 显示详细分布
    log_info "详细zone分布统计："
    count_instances_by_zone

    # 检查是否还有实例在目标zone
    local target_zone_count=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --region="$REGION" \
        --filter="zone:(${TARGET_ZONE}) AND status=RUNNING" \
        --format="value(instance)" | wc -l)

    if [[ $target_zone_count -gt 0 ]]; then
        log_warn "注意：目标zone ${TARGET_ZONE} 仍有 ${target_zone_count} 个实例"
        return 1
    else
        log_info "✅ 目标zone ${TARGET_ZONE} 无运行实例"
        return 0
    fi
}

# 生成测试报告
generate_report() {
    local test_result=$1
    local report_file="dr_test_report_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "======================================"
        echo "  GCP MIG Zone DR 测试报告"
        echo "======================================"
        echo "测试时间: $(date)"
        echo "MIG名称: $MIG_NAME"
        echo "区域: $REGION"
        echo "测试zone: $TARGET_ZONE"
        echo "期望实例数: $EXPECTED_INSTANCE_COUNT"
        echo ""
        echo "测试结果: $test_result"
        echo ""
        echo "最终实例分布:"
        get_instance_distribution
        echo ""
        echo "Zone统计:"
        count_instances_by_zone
    } | tee "$report_file"

    log_info "测试报告已保存至: $report_file"
}

# ==================== 主流程 ====================

main() {
    log_info "=========================================="
    log_info "  开始 Zone DR 测试"
    log_info "=========================================="

    # 阶段1：前置检查
    log_info "【阶段1】环境检查"
    check_mig_config
    echo ""

    log_info "测试前实例分布:"
    get_instance_distribution
    echo ""

    log_info "Zone统计:"
    count_instances_by_zone
    echo ""

    # 确认继续
    read -p "是否继续执行DR测试？这将删除 ${TARGET_ZONE} 中的实例 (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        log_warn "测试已取消"
        exit 0
    fi

    # 阶段2：模拟zone故障
    log_info "【阶段2】模拟Zone故障"
    delete_zone_instances "$TARGET_ZONE"
    echo ""

    # 阶段3：验证自动恢复
    log_info "【阶段3】验证自动恢复"
    if wait_for_recovery "$HEALTH_CHECK_TIMEOUT"; then
        log_info "✅ 实例恢复成功"
    else
        log_error "❌ 实例恢复失败"
        generate_report "FAILED"
        exit 1
    fi
    echo ""

    # 阶段4：验证zone分布
    log_info "【阶段4】验证Zone分布"
    sleep 30  # 等待实例完全启动

    if verify_zone_distribution; then
        log_info "✅ Zone分布验证通过"
        test_result="PASSED ✅"
    else
        log_warn "⚠️  Zone分布可能不符合预期"
        test_result="PARTIAL ⚠️"
    fi
    echo ""

    # 生成报告
    log_info "【测试完成】生成报告"
    generate_report "$test_result"

    log_info "=========================================="
    log_info "  DR测试完成"
    log_info "=========================================="
}

# 执行主流程
main
```

---

## 辅助脚本：持续监控

```bash
#!/bin/bash

#############################################
# MIG 实例分布监控脚本
# 用途：实时监控实例的zone分布情况
#############################################

MIG_NAME="your-mig-name"
REGION="europe-west2"
INTERVAL=5  # 监控间隔(秒)

echo "开始监控 MIG: $MIG_NAME"
echo "按 Ctrl+C 停止"
echo ""

while true; do
    clear
    echo "========================================"
    echo "监控时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================"
    echo ""

    # 显示实例列表
    echo "实例列表:"
    gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --region="$REGION" \
        --format="table(instance,zone,status,lastAttempt.errors.errors[0].code)"

    echo ""
    echo "Zone分布统计:"
    gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --region="$REGION" \
        --format="csv[no-heading](zone,status)" | \
        awk -F',' '{print $1" "$2}' | sort | uniq -c

    echo ""
    echo "----------------------------------------"
    sleep $INTERVAL
done
```

---

## 使用说明

### 1. 准备工作

```bash
# 1. 修改脚本中的配置参数
MIG_NAME="your-actual-mig-name"
REGION="your-region"
TARGET_ZONE="zone-to-test"

# 2. 赋予执行权限
chmod +x dr_test.sh
chmod +x monitor_mig.sh
```

### 2. 执行测试

**终端 1 - 运行 DR 测试:**

```bash
./dr_test.sh
```

**终端 2 - 实时监控(可选):**

```bash
./monitor_mig.sh
```

### 3. 预期结果

| 阶段          | 预期行为                   | 验证指标             |
| ------------- | -------------------------- | -------------------- |
| Zone 故障模拟 | 目标 zone 实例被删除       | 该 zone 实例数=0     |
| 自动恢复      | MIG 在其他 zone 创建新实例 | 总实例数恢复到目标值 |
| Zone 分布     | 新实例分布在其他 zone      | 目标 zone 无新实例   |
| 服务可用性    | 负载均衡继续工作           | 健康检查通过         |

---

## 注意事项

### ⚠️ 测试前检查清单

- [ ] 确认 MIG 配置了 autoHealingPolicy
- [ ] 验证至少配置了 2 个以上的 zone
- [ ] 检查实例模板的健康检查配置
- [ ] 确认测试窗口期间流量较低
- [ ] 准备回滚方案

### ⚠️ 已知限制

1. **Policy 限制**: 如果 MIG 的 distributionPolicy 仍包含目标 zone，实例可能会重新调度回该 zone
2. **资源限制**: 如果其他 zone 配额不足，恢复可能失败
3. **时间延迟**: 实例重建通常需要 2-5 分钟

### 解决方案：强制排除 zone

如需确保实例不回到目标 zone，需要在 MIG 创建时指定 zone 列表：

```bash
# 重建MIG并排除特定zone
gcloud compute instance-groups managed create $MIG_NAME \
  --region=$REGION \
  --template=your-template \
  --size=2 \
  --distribution-policy-zones=europe-west2-b,europe-west2-c
```

---

## 扩展验证(可选)

### 负载均衡健康检查

```bash
# 检查后端服务健康状态
gcloud compute backend-services get-health BACKEND_SERVICE_NAME \
  --region=$REGION \
  --format="table(status.healthStatus[].instance,status.healthStatus[].healthState)"
```

### 流量测试

```bash
# 使用curl持续请求测试
while true; do
  curl -s -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" \
    https://your-service-url.com
  sleep 1
done
```

---

需要我进一步优化脚本或添加其他验证功能吗?例如:

- 自动化的负载测试集成
- Slack/Email 告警通知
- 多 zone 轮询故障测试
- 性能指标采集

# ChatGPT

你的目标非常明确：

> 模拟单个 **zone 故障**，并验证 **Regional MIG** 是否能在其他可用的 zone 内自动恢复实例。

基于你上传的文档内容（dr-mig-zone-test.md），我总结出两种可行且安全的 **DR 测试方案**，并提供相应的脚本供你直接验证。

---

## **一、快速验证方案（推荐）**

### **目标**

验证当某个 zone（如 europe-west2-a）“挂掉”时，Regional MIG 是否会在其他 zone（b、c）自动补建实例。

### **思路**

1. **不修改任何策略**（保持当前 MIG 设置）
2. **手动删除某个 zone 的所有实例**
3. 观察 MIG 是否在其他 zone 自动重建实例

---

### **脚本：mig_zone_dr_test.sh**

```bash
#!/bin/bash

# ========== 参数定义 ==========
MIG_NAME="your-mig-name"
REGION="europe-west2"
ZONE_TO_SIMULATE_DOWN="europe-west2-a"

# ========== Step 1: 显示当前分布 ==========
echo "当前 MIG 实例分布："
gcloud compute instance-groups managed list-instances "$MIG_NAME" \
  --region="$REGION" \
  --format="table(instance, zone, status)"

# ========== Step 2: 获取指定 zone 的实例 ==========
echo "获取 $ZONE_TO_SIMULATE_DOWN 中的实例..."
INSTANCES=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
  --region="$REGION" \
  --filter="zone:($ZONE_TO_SIMULATE_DOWN)" \
  --format="value(instance)")

if [[ -z "$INSTANCES" ]]; then
  echo "✅ $ZONE_TO_SIMULATE_DOWN 中没有实例，无需模拟故障。"
  exit 0
fi

# ========== Step 3: 删除该 zone 实例（模拟故障） ==========
echo "模拟 $ZONE_TO_SIMULATE_DOWN 故障，删除实例..."
for INSTANCE in $INSTANCES; do
  echo "🗑 删除实例：$INSTANCE"
  gcloud compute instance-groups managed delete-instances "$MIG_NAME" \
    --region="$REGION" \
    --instances="$INSTANCE" \
    --quiet
done

# ========== Step 4: 等待 MIG 自愈 ==========
echo "等待 MIG 自动重建实例..."
sleep 90

# ========== Step 5: 再次查看分布 ==========
echo "重新检查实例分布："
gcloud compute instance-groups managed list-instances "$MIG_NAME" \
  --region="$REGION" \
  --format="table(instance, zone, status)"
```

---

### **运行方式**

```
chmod +x mig_zone_dr_test.sh
./mig_zone_dr_test.sh
```

运行完后，观察是否有新实例在 europe-west2-b 或 europe-west2-c 出现。

如果是 ✅，说明你的 MIG 能在 zone 故障时自动恢复。

---

### **验证流程图**

```mermaid
graph TD
    A[当前 MIG: zone a,b] --> B[删除 a zone 实例]
    B --> C[MIG 检测实例数量不足]
    C --> D[MIG 自动在其他 zone 创建实例]
    D --> E[验证实例出现在 b/c zone ✅]
```

---

## **二、完全控制方案（可重复测试）**

当你想**严格指定容灾目标 zone**（例如彻底从 a 迁到 b,c），可以使用此方案。

### **步骤**

#### **1️⃣ 创建一个新的 MIG（带 zone 策略）**

```bash
gcloud compute instance-groups managed create my-dr-test-mig \
  --region=europe-west2 \
  --template=my-template \
  --size=2 \
  --distribution-policy-zones=europe-west2-b,europe-west2-c
```

#### **2️⃣ 观察实例分布：**

```bash
gcloud compute instance-groups managed list-instances my-dr-test-mig \
  --region=europe-west2 \
  --format="table(instance, zone)"
```

#### **3️⃣ 模拟一个 zone 故障：**

```bash
gcloud compute instance-groups managed delete-instances my-dr-test-mig \
  --region=europe-west2 \
  --instances=$(gcloud compute instance-groups managed list-instances my-dr-test-mig \
    --region=europe-west2 --filter="zone:(europe-west2-b)" --format="value(instance)")
```

#### **4️⃣ 验证是否自动重建到 europe-west2-c：**

```bash
gcloud compute instance-groups managed list-instances my-dr-test-mig \
  --region=europe-west2 \
  --format="table(instance, zone, status)"
```

---

## **三、最佳实践与注意事项**

| **项目**           | **建议**                                                                                                                                                    |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 测试类型           | 使用 Regional MIG（必须）                                                                                                                                   |
| 分布策略           | 至少包含 2 个不同 zone                                                                                                                                      |
| 模拟 zone 故障方式 | 手动删除实例 or resize=0 → resize=原值                                                                                                                      |
| 自动恢复验证       | 观察实例重新出现在其他 zone                                                                                                                                 |
| 实际生产 DR        | 结合 [Fault Injection Testing (FIT)](https://cloud.google.com/architecture/dr-drills-fault-injection-gce)![Attachment.tiff](file:///Attachment.tiff) 更真实 |

---

是否希望我进一步帮你扩展这个脚本，让它能：

- 自动检测 MIG 所有 zone；
- 自动选择一个 zone 进行“failover”测试；
- 输出 JSON 格式的前后对比结果？

这样就能实现**一键自动化 DR 测试**，适合定期验证。
