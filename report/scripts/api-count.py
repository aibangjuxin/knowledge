import sys
import random
from typing import List

def calculate_adjusted_bill(daily_costs: list, total_days_in_month: int = 31) -> dict:
    """
    计算基于实际使用天数的调整后账单
    
    参数:
    daily_costs: 每日费用列表
    total_days_in_month: 月份总天数
    """
    # 基础计算
    usage_days = len(daily_costs)
    avg_daily = sum(daily_costs) / usage_days
    max_daily = max(daily_costs)
    
    # 计算基础月度费用
    base_charge = avg_daily * 0.8
    peak_charge = max_daily * 0.2
    monthly_fee = base_charge + peak_charge
    
    # 基于使用天数调整费用
    daily_rate = monthly_fee / total_days_in_month
    adjusted_fee = daily_rate * usage_days
    
    return {
        "使用天数": usage_days,
        "月份总天数": total_days_in_month,
        "平均日费用": round(avg_daily, 2),
        "最高日费用": round(max_daily, 2),
        "基础费用部分": round(base_charge, 2),
        "峰值费用部分": round(peak_charge, 2),
        "原始月度费用": round(monthly_fee, 2),
        "每日费率": round(daily_rate, 2),
        "最终调整费用": round(adjusted_fee, 2)
    }

def generate_costs(days: int, min_cost: int = 60, max_cost: int = 120) -> List[int]:
    """生成指定天数的随机整数费用"""
    return [random.randint(min_cost, max_cost) for _ in range(days)]

def main():
    # 检查命令行参数
    if len(sys.argv) != 2:
        print("使用方法: python api-count.py <天数>")
        sys.exit(1)
    
    try:
        days = int(sys.argv[1])
        if days <= 0:
            raise ValueError("天数必须大于0")
    except ValueError as e:
        print(f"错误: {e}")
        sys.exit(1)
    
    # 设置随机种子以保证结果可复现
    random.seed(2024)
    
    # 生成随机费用数据
    daily_costs = generate_costs(days)
    
    # 计算结果
    result = calculate_adjusted_bill(daily_costs)
    
    # 打印详细结果
    print("\n1. 每日费用明细:")
    for day, cost in enumerate(daily_costs, 1):
        print(f"   第{day:2d}天: ¥{cost}")
    
    print("\n2. 基础统计")
    print(f"   - 实际使用天数：{result['使用天数']}天")
    print(f"   - 月份总天数：{result['月份总天数']}天")
    print(f"   - 平均日费用：¥{result['平均日费用']}")
    print(f"   - 最高日费用：¥{result['最高日费用']}")
    
    print("\n3. 费用计算")
    print(f"   - 基础费用部分：¥{result['基础费用部分']}")
    print(f"   - 峰值费用部分：¥{result['峰值费用部分']}")
    print(f"   - 原始月度费用：¥{result['原始月度费用']}")
    print(f"   - 每日费率：¥{result['每日费率']}")
    print(f"   - 最终调整费用：¥{result['最终调整费用']}")

if __name__ == "__main__":
    main()
