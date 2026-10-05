# 21 · 存量集群分类自查 —— 采集脚本 + 分类引擎

> **这是什么**:`12-byoc-scaleup-playbook.md` §1.2 那张表的**可执行实现**。
> 手工填 N 行表在 20+ 集群规模下不可行 —— 本文件提供采集脚本 + 分类规则引擎,产出结构化 A/B/C 结果。
>
> **⚠️ 本次未执行任何采集。** DC 环境的 `gcloud` 认证已失效,无法拉取真实集群清单。
> **本文件交付的是工具与规则,不是分类结果。** 任何"A 类 X 个"的数字都必须由你在
> 可用环境跑一次脚本得出,不得引用本文件。
>
> **可直接运行的脚本**(`scripts/` 目录,已过语法检查与 7 用例回归):
> - [`scripts/byoc-inventory.sh`](./scripts/byoc-inventory.sh) —— 只读采集
> - [`scripts/byoc-classify.py`](./scripts/byoc-classify.py) —— 分类引擎

---

## 0. 为什么必须是脚本而不是表格

| 规模           | 手工表格                        | 脚本                        |
| -------------- | ------------------------------- | --------------------------- |
| 3 个集群       | 可行                            | 过度工程                    |
| 20 个集群      | 两天,且容易抄错版本号            | 20 分钟                    |
| 20 个 × 每月复查 | 不可持续                        | 一条命令                    |

**更重要的是**:`12` §3.1 已经指出"BYOC 评估必须可自动化,输出结构化四态"。
**你自己交付的分类自查,就应该先按 CaaS 将来要用的形态做** ——
否则你交的是一张手工表,CaaS 实现方按"一个流程"估排期,然后在第 20 个集群上撞墙。

---

## 1. 采集脚本(只读,不改任何集群)

```bash
#!/usr/bin/env bash
# byoc-inventory.sh —— 存量 GKE 集群清单采集(只读)
#
# 安全性:仅调用 gcloud list/describe,不产生任何写操作。
# 建议先在非生产账号下跑通,确认输出字段无误。
#
# 用法:
#   ./byoc-inventory.sh > byoc-inventory.json
#
# 前置:gcloud auth 有效,且账号对目标项目有 container.clusters.get 权限。

set -euo pipefail

PROJECT="${PROJECT:?必须指定 PROJECT 环境变量,例:PROJECT=my-project ./byoc-inventory.sh}"
STABLE_CHANNEL="Stable"

echo "==> 采集项目 ${PROJECT} 的 GKE 集群…" >&2

gcloud container clusters list \
  --project "${PROJECT}" \
  --format=json > /tmp/byoc-clusters-raw.json

# 提取分类所需的最小字段集
jq '[
  .[] | {
    name:              .name,
    location:          .location,
    status:            .status,
    currentMasterVersion: .currentMasterVersion,
    releaseChannel:    (.releaseChannel.channel // "Unspecified"),
    # 网络模式:Autopilot 必须 private;Standard 可 private 或 public
    privateCluster:    (.privateClusterConfig // {} | has("enablePrivateEndpoint") | not),
    autopilotEnabled:  (.autopilot.enabled // false),
    # 版本 skew 校验需要节点池版本
    nodePoolVersions:  [(.nodePools[]?.version // "unknown")],
    # 集群创建时间(EOL 风险参考)
    createTime:        .createTime,
    # 标签:责任人 / 业务线通常挂在这里
    resourceLabels:    (.resourceLabels // {}),
    # 归属信息(GKE 里常常缺失,需从别处补)
    description:       (.description // ""),
    # Fleet 归组(rollout sequencing 前提)
    fleetMembership:   (.fleetMembership // "none"),
    # 备份/DR 证据
    backupConfig:      (.backupConfig // null),
    # 网络 Policy
    networkPolicyEnabled: ((.networkPolicy // {}).enabled // false),
    # Security posture 证据
    securityPostureConfig: (.securityPostureConfig // null)
  }
]' /tmp/byoc-clusters-raw.json
```

### 1.1 采集不到的字段(必须人工补,不要伪造)

| 字段                     | 为什么 gcloud 拿不到                    | 从哪补                        |
| ------------------------ | --------------------------------------- | ----------------------------- |
| **责任人(到人)**          | GKE 不存                                 | CMDB / Jira / 组织架构        |
| **prod / non-prod 划分**  | GKE 不存                                 | 业务方确认                    |
| **备份是否验证过**        | 只有 `backupConfig` 配置,**无验证记录** | 备份系统的最近一次恢复演练记录 |
| **是否有退出计划**        | 无                                       | 业务方 / 项目台账             |
| **是否有跨集群强依赖**    | 无                                       | 业务方 / 网络拓扑图           |
| **业务方是否愿意配合**     | 无                                       | **只能去问**                  |

> ⚠️ **"备份验证过"是最容易自欺的一栏。**
> `backupConfig.enabled: true` 只说明备份任务在跑,**不说明恢复演练做过**。
> CaaS 的 BYOC 准入检查必须区分这两个状态(见 `05-byoc-onboarding-pack.md` §3)。

### 1.2 需要人工填写的表格(脚本跑完后补这几列)

| 集群 | 责任人(到人) | prod/non-prod | 备份**恢复演练**过? | 有退出计划? | 有跨集群强依赖? | 业务方配合意愿 |
| ---- | ------------ | ------------- | ------------------- | ----------- | -------------- | -------------- |
|      |              |               |                     |             |                |                |

---

## 2. 分类引擎(消费采集结果 + 人工补充)

```python
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
```

---

## 3. 这份脚本同时证明了什么(给评审会)

跑完之后,你在 RFC 评审会上有三句话可以说:

| #   | 话术                                                              | 数据支撑                                      |
| --- | ----------------------------------------------------------------- | --------------------------------------------- |
| 1   | "**A 类只有 X 个,BYOC 在 DC 侧是长尾路径。**"                    | 脚本输出的 A 类计数                          |
| 2   | "**BYOC 评估必须自动化**(12 号文件 N2)。我这边一份自查脚本都写了,你们的人工填表撑不住 N 个集群。" | §2 这份脚本的存在本身                        |
| 3   | "**C 类 Y 个是预期内的正常结局**(N3),请在 §9.4 明确这批集群的归属。" | C 类计数 + 整改成本评估                      |

> **第 2 条最有杀伤力** —— 你不是在提需求,你是在**证明需求存在**:
> 一份 200 行的分类脚本,就是"人工填表不可行"的实证。

---

## 4. 与其它文件的衔接

| 分类结果           | 下一步动作                                      | 出处                          |
| ------------------ | ----------------------------------------------- | ----------------------------- |
| **A 类**           | 选 1 个作为第 0 批,按 §2.3 六条判据复核          | `12` §2.3 / `05` 八阶段      |
| **B 类**           | 排整改;整改动作**本身应被 CaaS 编排**(第 3+ 批通过标准) | `12` §2.3                    |
| **C 类**           | 写进台账,明确留在 CaaS 外;⚠️ 版本高的 C 类需处理 EOL | `12` §1.1 / `20` §2.2        |
| **全部**            | 纳管前检查**节点池版本 skew ≤ 2**              | `20` §2.3 ⚠️ 原准入条件没有这条 |

> ⚠️ **C 类不等于"不用管"**。一个 minor 已过 EOL 的 C 类集群,GKE 仍会自动升级它。
> **它留在 CaaS 外,但它的 EOL 风险依然存在** —— 需在台账里标注并定期复查。

---

## 5. 本文件的已知限制(诚实留白)

| 限制                          | 说明                                                                    |
| ----------------------------- | ----------------------------------------------------------------------- |
| ⚠️ **本次未执行采集**          | DC 环境 gcloud 认证失效,无真实数据。**本文件不含任何集群数量结论**      |
| `STABLE_MINOR_UPPER_BOUND`   | 硬编码为 36,基于 2026-10-05 的 release schedule[1]。**须按月更新**     |
| `EOL_BY_MINOR`               | 同上,含 `2027-Q2` 这类季度精度值,精度低于日级                          |
| 采集不到的事实               | §1.1 已列出 6 项,必须人工补,脚本不猜                                   |
| "有跨集群强依赖"未进分类      | 12 号文件把它列为**排序维度**(§2.2 ②)而非准入条件,本脚本按此处理        |
| Extended channel 冲突未查    | 见 `20` §2.4 —— 若某集群想走 Extended,需先实测。Extended 的官方禁用清单含 Config Sync 与 Policy Controller[2] |
| 节点 skew 未进分类            | §1 已采集 `nodePoolVersions`,但**未纳入 A/B/C 判定** —— 见下 ⚠️         |
| EOL 判定依据                 | "过 EOL 即无法加入/留在该 channel",依据 GKE versioning:过 end of support 后 GKE 自动升级且 exclusion 不阻止[5] |
| 两步升级未纳入分类            | 1.33+ 控制面 minor 升级有 soak 与回滚窗,但它作用于**升级过程**,不构成"能否纳管"的准入条件[4] |

### 5.1 ⚠️ 已发现但未实现:节点版本 skew 检查

采集脚本已取到 `nodePoolVersions`,但分类规则里**没有** skew 判定。原因是:
`12` 号文件 §1.2 的分类表里没有这一列,**它是我在 `20` §2.3 新发现的约束**。

> **建议的下一步**:把 skew 检查加进 `BYOC ADMISSIBLE` 的硬性条件
> (见 `20` §2.3:节点最多落后控制面 2 个 minor,且不得跑已 EOL 的 minor)[3]。
> 一个 skew 超限的集群,控制面一升级就会连带触发节点池重建 ——
> **这正是"纳管后突然出事"最典型的来源,而原 RFC §9.1 准入条件里没有这一条。**
>
> 在拿到 `20` §2.4 的 Extended 实测结论之前,建议先按 `20` 的硬约束重写本引擎的判定层。

---

## 6. 修订记录

| 日期       | 内容                                                        |
| ---------- | ----------------------------------------------------------- |
| 2026-10-05 | 初版:采集脚本 + 分类引擎。未执行采集(gcloud 认证失效)       |

---

## Sources

[1] https://docs.cloud.google.com/kubernetes-engine/docs/release-schedule — GKE release schedule
[2] https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels — About release channels
[3] https://docs.cloud.google.com/kubernetes-engine/versioning — GKE versioning and support
[4] https://docs.cloud.google.com/kubernetes-engine/docs/concepts/about-rollout-sequencing — About cluster upgrades with rollout sequencing
[5] https://docs.cloud.google.com/kubernetes-engine/docs/concepts/maintenance-windows-and-exclusions — Maintenance windows and exclusions
