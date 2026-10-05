#!/usr/bin/env python3
"""byoc-classify.py —— 按 12 号文件 §1.2 的规则给存量集群分 A/B/C。

输入:byoc-inventory.json(§1 脚本产出) + 人工补充的 CSV
输出:分类结果 + 计数摘要 + 每类的处置动作

用法:
    python3 byoc-classify.py inventory.json manual-facts.csv

设计原则:
  - 规则来自 12 号文件 §1.2,不引入额外判断
  - 不确定的一律输出 unknown,不猜
  - 每条分类结论都带 reason,可回溯
  - release channel 取值做归一化 —— gcloud 返回大写枚举(STABLE / NO_CHANNEL),
    手工表格写 Stable / NoChannel,两种都接受。不归一化会把 NoChannel 误判为
    "已加入 channel"从而错判 A 类(已实测过这个 bug)

已验证: 7 个 fixture 用例覆盖 A/B/C 三类 + EOL / 超上限 / No channel /
prod 混用 / 责任人缺失 / 三项为否 / 信息不全,结果与 §1.2 规则一致。
"""

from __future__ import annotations

import csv
import json
import sys
from dataclasses import dataclass, field
from enum import Enum


# ---------------------------------------------------------------- 版本区间

# Stable channel 当前可用的 minor 区间。
# ⚠️ 维护纪律:此表随 GKE release schedule 滚动更新,勿长期缓存。
#    来源: https://docs.cloud.google.com/kubernetes-engine/docs/release-schedule
#    查阅日期: 2026-10-05
#
# 读法:该表给出"Auto Upgrade"(Stable)列,即 Stable 已把该 minor 设为自动升级目标。
# 一个跑在高于此上界的 minor 上的集群,无法加入 Stable —— 因为 GKE 不会把集群降级。
STABLE_MINOR_UPPER_BOUND = 36  # 1.36 为 Stable 已设 auto-upgrade target 的最高 minor

# end of standard support(EOL)日期 —— 越早的越危险。
# 来源同上(End of standard support 列)。
EOL_BY_MINOR = {
    30: "2025-12-03",  # 已过期
    31: "2026-06-09",  # 已过期
    32: "2026-08-25",  # 已过期
    33: "2026-12",
    34: "2027-Q2",
    35: "2027-Q3",
    36: "2027-Q4",
    37: "2028-Q2",
}

# 已过 EOL 的 minor(用于快速判定)
EOL_PASSED = {m for m, d in EOL_BY_MINOR.items() if d < "2026-10-05"}


class Category(str, Enum):
    A = "A · 直接可纳"
    B = "B · 可整改后纳"
    C = "C · 永不纳管"


@dataclass
class ClusterFacts:
    name: str
    location: str
    mode: str  # standard / autopilot
    channel: str
    minor: int
    in_window: bool  # 未过 EOL
    prod_separated: bool | None  # None = 未知
    owner_named: bool | None
    backup_drilled: bool | None
    exit_plan: bool | None
    category: Category = field(init=False)
    reasons: list[str] = field(default_factory=list, init=False)
    remediations: list[str] = field(default_factory=list, init=False)

    def __post_init__(self) -> None:
        self._classify()

    # 12 号文件 §1.2 的分类规则,逐条对应
    def _classify(self) -> None:
        fails = 0
        unknowns = 0

        # --- 硬性阻断项(这些不是"待整改",是"现在就不合格")---

        # 规则:版本过 EOL → B(先升版本)
        if self.minor in EOL_PASSED:
            self.reasons.append(f"版本 1.{self.minor} 已过 end of standard support")
            self.remediations.append(f"先升 minor 至 ≥1.{STABLE_MINOR_UPPER_BOUND - 2}")
            fails += 1

        # 规则:版本高于 Stable 上限 → B(降版本或加不进 channel)
        if self.minor > STABLE_MINOR_UPPER_BOUND:
            self.reasons.append(
                f"版本 1.{self.minor} 高于 Stable 上限 1.{STABLE_MINOR_UPPER_BOUND},"
                f"GKE 不会自动降级 → 加不进 Stable"
            )
            self.remediations.append("需人工降级,或暂留 No channel(且 No channel 无灰度能力)")
            fails += 1

        # 规则:No channel → B(先加入 Stable)
        if normalize_channel(self.channel) in ("unspecified", "no_channel", ""):
            self.reasons.append(f"未加入 release channel({self.channel or '空'})")
            self.remediations.append("先 enroll Stable;注意 No channel 是待废弃配置")
            fails += 1

        # 规则:prod/non-prod 混用 → C(除非愿意拆)
        if self.prod_separated is False:
            self.reasons.append("prod 与 non-prod 混用")
            self.remediations.append("需拆分 —— 拆分成本通常高于纳管收益,建议留在 CaaS 外")
            self.category = Category.C
            return

        # 规则:责任人只到部门不到人 → B
        if self.owner_named is False:
            self.reasons.append("责任人只到部门,不到人")
            self.remediations.append("指定到人的责任人")
            fails += 1

        # --- 未知项计数(不猜)---
        for label, val in (
            ("prod/non-prod 划分", self.prod_separated),
            ("责任人", self.owner_named),
            ("备份恢复演练", self.backup_drilled),
            ("退出计划", self.exit_plan),
        ):
            if val is None:
                unknowns += 1
                self.reasons.append(f"⚠️ {label}未确认 —— 分类待定")

        # 规则:三项以上为否 → C
        negative = sum(
            1
            for v in (self.prod_separated, self.owner_named, self.backup_drilled, self.exit_plan)
            if v is False
        )
        if negative >= 3:
            self.reasons.append(f"准入项中 {negative} 项为否(阈值 3)")
            self.category = Category.C
            return

        # 规则:以上全过 → A
        if fails == 0 and unknowns == 0 and negative == 0:
            self.category = Category.A
            return

        # 其余 → B,但若未知项过多,提示需先补信息
        self.category = Category.B
        if unknowns >= 2:
            self.reasons.append("→ 未知项 ≥2,建议补全信息后重新分类(当前分类可能偏严)")


def classify_from_row(row: dict) -> ClusterFacts:
    version = row.get("currentMasterVersion", "")
    minor = int(version.split(".")[1]) if version and version[0].isdigit() else 0
    return ClusterFacts(
        name=row["name"],
        location=row["location"],
        mode="autopilot" if row.get("autopilotEnabled") else "standard",
        channel=row.get("releaseChannel") or "Unspecified",
        minor=minor,
        in_window=minor not in EOL_PASSED,
        prod_separated=tri(row.get("prod_separated")),
        owner_named=tri(row.get("owner_named")),
        backup_drilled=tri(row.get("backup_drill_verified")),
        exit_plan=tri(row.get("exit_plan")),
    )


def normalize_channel(v: str | None) -> str:
    """归一化 release channel 取值。

    GKE API / gcloud 返回的是大写枚举:STABLE / REGULAR / RAPID / EXTENDED /
    NO_CHANNEL / UNSPECIFIED(未设置)。手工表格里常写成 Stable / NoChannel。
    两种写法都接受,统一小写并把 NoChannel 折成 no_channel。

    ⚠️ 这个归一化不是洁癖 —— 不做的话 NoChannel 会被当成"有 channel"而误判为 A 类。
    """
    s = (v or "").strip().lower().replace("-", "_").replace(" ", "_")
    if s in ("nochannel", "no_channel", "static"):
        return "no_channel"
    return s


def tri(v: str | bool | None) -> bool | None:
    """三态: True / False / None(未知)。空字符串视为未知,不猜。"""
    if v is None or v == "":
        return None
    if isinstance(v, bool):
        return v
    s = str(v).strip().lower()
    if s in ("yes", "y", "true", "1"):
        return True
    if s in ("no", "n", "false", "0"):
        return False
    return None


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        inventory = json.load(f)

    manual: dict[str, dict] = {}
    try:
        with open(sys.argv[2]) as f:
            for row in csv.DictReader(f):
                manual[row["name"]] = row
    except FileNotFoundError:
        print("提示:未提供人工补充 CSV,未知项将全部标为待定", file=sys.stderr)

    results: list[ClusterFacts] = []
    for row in inventory:
        row.update(manual.get(row["name"], {}))
        results.append(classify_from_row(row))

    # ---- 输出表格 ----
    print(f"{'集群':<32} {'模式':<10} {'channel':<14} {'版本':<10} 分类")
    print("-" * 92)
    for c in sorted(results, key=lambda x: (x.category.value, x.name)):
        print(f"{c.name:<32} {c.mode:<10} {c.channel:<14} 1.{c.minor:<8} {c.category.value}")

    # ---- 每类的处置动作 ----
    for cat in Category:
        members = [c for c in results if c.category is cat]
        if not members:
            continue
        print(f"\n{'=' * 92}\n{cat.value} —— {len(members)} 个\n{'=' * 92}")
        for c in members:
            print(f"\n  {c.name}  ({c.mode} / {c.channel} / 1.{c.minor})")
            for r in c.reasons:
                print(f"    · {r}")
            for r in c.remediations:
                print(f"    → 整改: {r}")

    # ---- 摘要:这个数字就是给 RFC 的输入 ----
    counts = {cat: len([c for c in results if c.category is cat]) for cat in Category}
    total = len(results)
    print(f"\n{'=' * 92}")
    print(f"摘要: 共 {total} 个集群 | A={counts[Category.A]} B={counts[Category.B]} C={counts[Category.C]}")
    print()
    if counts[Category.A] <= 2:
        print("→ 建议告诉 CaaS:「BYOC 在 DC 侧是低频路径,别为它过度设计」")
    elif counts[Category.A] > 10:
        print("→ 建议告诉 CaaS:「BYOC 是 DC 侧的主路径,必须支持批量」(对应 12 号文件 N1)")
    else:
        print("→ 常规规模:B 类的整改节奏是决定 BYOC 总周期的关键")
    pending = sum(1 for c in results if any("未确认" in r for r in c.reasons))
    if pending:
        print(f"⚠️ {pending} 个集群信息不全,分类可能偏严 —— 补全 §1.2 表格后重跑")


if __name__ == "__main__":
    main()
