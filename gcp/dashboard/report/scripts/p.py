import random
from typing import List
import statistics

def generate_monthly_costs(min_cost: float = 60, max_cost: float = 120, days: int = 31) -> List[float]:
    """生成一个月的随机每日费用"""
    return [round(random.uniform(min_cost, max_cost), 2) for _ in range(days)]

def calculate_monthly_bill(daily_costs: List[float]) -> dict:
    """计算月度账单"""
    avg_cost = statistics.mean(daily_costs)
    max_cost = max(daily_costs)
    
    base_charge = avg_cost * 0.8
    peak_charge = max_cost * 0.2
    final_cost = base_charge + peak_charge
    
    return {
        "daily_costs": daily_costs,
        "average_daily": round(avg_cost, 2),
        "max_daily": round(max_cost, 2),
        "base_charge": round(base_charge, 2),
        "peak_charge": round(peak_charge, 2),
        "final_cost": round(final_cost, 2)
    }

# 生成数据并计算
random.seed(2024)  # 设置随机种子以保证结果可复现
daily_costs = generate_monthly_costs()
bill = calculate_monthly_bill(daily_costs)

# 打印详细结果
print("每日费用明细：")
for day, cost in enumerate(bill["daily_costs"], 1):
    print(f"第{day:2d}天: ¥{cost:.2f}")

print("\n账单汇总：")
print(f"1. 平均日费用：¥{bill['average_daily']}")
print(f"2. 最高日费用：¥{bill['max_daily']}")
print(f"3. 基础费用部分（平均值的80%）：¥{bill['base_charge']}")
print(f"4. 峰值费用部分（最高值的20%）：¥{bill['peak_charge']}")
print(f"\n最终月度费用：¥{bill['final_cost']}")

print("\n费用构成分析：")
print(f"基础费用占比：{(bill['base_charge']/bill['final_cost']*100):.1f}%")
print(f"峰值费用占比：{(bill['peak_charge']/bill['final_cost']*100):.1f}%")
