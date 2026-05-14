import calendar
import sys
from datetime import date, timedelta


def is_workday(day):
    return day.weekday() < 5  # 0-4 are Monday to Friday


def count_workdays(year, month):
    _, days_in_month = calendar.monthrange(year, month)
    workdays = sum(
        1 for day in range(1, days_in_month + 1) if is_workday(date(year, month, day))
    )
    return workdays


def calculate_flexible_days(year, month, vacation_days):
    workdays = count_workdays(year, month)

    # 减去假期天数
    adjusted_workdays = workdays - vacation_days

    office_days = round(adjusted_workdays * 0.4)
    flexible_days = adjusted_workdays - office_days

    # 计算每周平均灵活办公天数
    weeks_in_month = len(calendar.monthcalendar(year, month))
    flexible_days_per_week = round(flexible_days / weeks_in_month, 1)

    print(f"{year}年{month}月工作日统计:")
    print(f"总工作日: {workdays}")
    print(f"请假天数: {vacation_days}")
    print(f"调整后工作日: {adjusted_workdays}")
    print(f"办公室天数: {office_days}")
    print(f"灵活办公天数: {flexible_days}")
    print(f"每周平均灵活办公天数: {flexible_days_per_week}")


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

    calculate_flexible_days(year, month, vacation_days)
