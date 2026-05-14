import sys
import calendar
from datetime import date, timedelta


def count_workdays(year, month):
    _, days_in_month = calendar.monthrange(year, month)
    workdays = sum(1 for day in range(1, days_in_month + 1)
                   if date(year, month, day).weekday() < 5)
    return workdays


def calculate_flexible_schedule(year, month, vacation_days):
    workdays = count_workdays(year, month)
    adjusted_workdays = max(workdays - vacation_days, 0)  # 确保不会出现负数
    office_days = round(adjusted_workdays * 0.4)  # 确保办公室天数是调整后工作日的40%
    flexible_days = adjusted_workdays - office_days

    # 计算每周的办公室工作天数
    weeks = len(calendar.monthcalendar(year, month))
    weekly_schedule = [0] * weeks

    # 均匀分配办公室工作日
    for i in range(office_days):
        weekly_schedule[i % weeks] += 1

    return workdays, adjusted_workdays, office_days, flexible_days, weekly_schedule


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("使用方法: python script.py <年月(YYYYMM)> <请假天数>")
        sys.exit(1)

    date_input = sys.argv[1]
    year = int(date_input[:4])
    month = int(date_input[4:])
    vacation_days = int(sys.argv[2])

    if month < 1 or month > 12:
        print("错误: 月份必须在1到12之间")
        sys.exit(1)

    workdays, adjusted_workdays, office_days, flexible_days, weekly_schedule = (
        calculate_flexible_schedule(year, month, vacation_days))

    print(f"{year}年{month}月工作日统计:")
    print(f"总工作日: {workdays}")
    print(f"请假天数: {vacation_days}")
    print(f"调整后工作日: {adjusted_workdays}")
    print(f"办公室工作天数: {office_days}")
    print(f"远程工作天数: {flexible_days}")
    print(f"办公室工作比例: {office_days/adjusted_workdays:.2%}"
          if adjusted_workdays > 0 else "办公室工作比例: 0%")

    print("\n每周计划:")
    for i, days in enumerate(weekly_schedule, 1):
        print(f"W{i}:{days}", end=" ")
    print()  # 换行
