# Firestore 多项目数据集成与分析架构设计

## 1. 背景与目标

随着业务扩展，平台需要将多个独立项目的数据统一存储在 Firestore 中，并同步到 BigQuery 进行集中分析。当前的数据架构仅为单个项目设计，直接引入多源数据将导致数据污染、统计口径混乱，并破坏现有分析报表的准确性。

**核心目标:**

- **数据隔离**: 确保不同项目的数据在存储和分析层面都清晰隔离，互不干扰。
- **向后兼容**: 新架构必须兼容现有数据和分析报表，保证业务连续性。
- **动态扩展**: 应用程序和数据管道应能轻松支持未来新项目的接入。
- **查询效率**: 保证单项目数据查询的高效性。

---

## 2. Firestore 数据建模方案

为了实现强大的数据隔离和未来的可扩展性，我们采纳并深化 **按顶级集合隔离项目数据** 的方案。

### 2.1. 推荐模型：每个项目一个顶级集合

我们将为每个项目创建一个独立的顶级集合。集合名称将采用统一的前缀和项目标识符的组合，例如 `teams_project_a`、`teams_project_b`。

**Firestore 结构示例:**
```
Firestore Root
├── teams_project_a/      -- 项目A的团队数据
│   ├── {team_id_1}
│   │   └── { team_name: "Alpha", ... }
│   └── {team_id_2}
│       └── { team_name: "Bravo", ... }
│
└── teams_project_b/      -- 项目B的团队数据
    ├── {team_id_3}
    │   └── { team_name: "Charlie", ... }
    └── {team_id_4}
        └── { team_name: "Delta", ... }
```

**优点:**
- **强隔离**: 数据在物理上分离，从根本上避免了数据混淆和“吵闹的邻居”问题。
- **查询高效**: 针对单个项目的查询仅需扫描其专属集合，速度快、成本低。
- **安全规则简单**: 可以轻松地为每个集合路径配置独立的、基于项目的安全访问规则。
- **易于管理**: 备份、恢复或删除单个项目的数据变得非常简单。

### 2.2. 应用程序设计：动态集合访问模式

为了解决“一套代码如何读写多个集合”的核心问题，我们引入 **动态集合访问** 的设计模式。其核心思想是将集合名称的构建逻辑从业务代码中解耦出来。

**实现方式：**

在应用程序的数据访问层（如 Repository 或 Service）中，封装一个方法，根据传入的 `project_id` 动态构建和返回集合引用。

**Python 代码示例 (数据访问仓库):**
```python
from google.cloud import firestore

class TeamRepository:
    def __init__(self):
        self.db = firestore.Client()
        self.base_collection_name = "teams"

    def _get_collection_ref(self, project_id: str):
        """根据项目ID动态构建并返回集合引用。"""
        if not project_id:
            raise ValueError("Project ID cannot be empty.")
        collection_name = f"{self.base_collection_name}_{project_id}"
        return self.db.collection(collection_name)

    def add_team(self, project_id: str, team_data: dict):
        """向指定项目的集合中添加一个新团队。"""
        collection_ref = self._get_collection_ref(project_id)
        # 为保证数据完整性，建议在文档中也冗余一份项目ID
        team_data['source_project'] = project_id
        return collection_ref.add(team_data)

    def get_teams_by_project(self, project_id: str):
        """获取指定项目的所有团队。"""
        collection_ref = self._get_collection_ref(project_id)
        return [doc.to_dict() for doc in collection_ref.stream()]

# 在业务逻辑层调用
# project_id 可以从API请求头、用户认证信息(JWT claim)或配置中获取
repo = TeamRepository()
repo.add_team("project_a", {"team_name": "Omega"})
```

通过这种模式，应用程序上层逻辑无需关心具体的集合名称，只需传递 `project_id` 即可，实现了业务逻辑与数据存储细节的解耦。

---

## 3. BigQuery 数据管道与分析设计

为了在 BigQuery 中实现与 Firestore 同样清晰的隔离和分析能力，我们推荐以下流程。

### 3.1. 数据同步：从多集合到统一表

我们将配置一个数据同步流程（推荐使用 Cloud Functions），该流程会遍历所有项目的集合，并将数据统一写入到 BigQuery 的 **一张** 主表中。在写入时，必须添加 `source_project` 字段。

**BigQuery 目标表示例 (`teams_unified`):**

| 字段名           | 类型      | 描述                 |
| ---------------- | --------- | -------------------- |
| `doc_id`         | `STRING`  | Firestore 文档ID     |
| `source_project` | `STRING`  | 数据来源的项目ID     |
| `team_name`      | `STRING`  | 团队名称             |
| `...`            | `...`     | 其他业务字段         |
| `timestamp`      | `TIMESTAMP`| 文档更新时间         |

**同步流程图:**
```mermaid
flowchart TD
    A[Cloud Scheduler] -- 每日触发 --> B(Cloud Function: SyncManager);
    B -- 遍历项目列表 --> C{For each project...};
    C --> D[读取 teams_{project_id} 集合];
    D -- 添加 source_project 字段 --> E[写入 BigQuery 的 teams_unified 表];
    C -- Loop --> D;
```

### 3.2. 视图层：隔离新旧分析逻辑的关键

直接查询 `teams_unified` 表会让现有报表面临数据污染。解决方案是在原始表和分析工具之间建立一个 **视图（View）抽象层**。

#### 视图一：`teams_legacy_view` (兼容旧报表)

这个视图的目的是 **完全模拟旧的数据结构和范围**，让现有的 Dashboard 无需任何修改即可继续工作。

```sql
CREATE OR REPLACE VIEW `your_dataset.teams_legacy_view` AS
SELECT
  -- 选择所有旧报表需要的字段
  team_name,
  member_count,
  -- ... 其他字段
FROM
  `your_dataset.teams_unified`
WHERE
  source_project = 'project_a' -- 关键：只筛选出原始项目的数据
```

**操作**: 将现有 Dashboard 的数据源从旧表切换到 `teams_legacy_view`。**现有业务无任何感知，无中断。**

#### 视图二：`teams_analytics_view` (面向新分析)

这个视图提供一个完整的、包含所有项目数据的、干净的数据模型，用于所有新的分析和报表。

```sql
CREATE OR REPLACE VIEW `your_dataset.teams_analytics_view` AS
SELECT
  -- 选择所有对分析有用的字段
  doc_id,
  source_project, -- 暴露项目ID，用于筛选和分组
  team_name,
  -- ... 其他字段
  timestamp
FROM
  `your_dataset.teams_unified`
```

**操作**: 所有新报表都基于此视图创建。分析师可以利用 `source_project` 字段轻松实现多项目对比、筛选和聚合分析。

---

## 4. 总结与实施路线图

本设计方案通过在 Firestore 层采用 **按集合隔离**，在应用层实现 **动态集合访问**，并在 BigQuery 端利用 **统一表 + 视图抽象层** 的策略，完美地解决了多项目数据集成带来的隔离性、兼容性和扩展性挑战。

### 实施路线图

1.  **阶段一：应用层改造 (1-2周)**
    -   实现 `TeamRepository` 等数据访问类，支持动态集合读写。
    -   更新所有相关业务逻辑，传递 `project_id`。

2.  **阶段二：数据管道搭建 (1周)**
    -   创建 BigQuery 中的 `teams_unified` 表。
    -   开发并部署用于同步多集合数据的 Cloud Function。
    -   配置 Cloud Scheduler 定时触发同步任务。

3.  **阶段三：视图与报表迁移 (1周)**
    -   在 BigQuery 中创建 `teams_legacy_view` 和 `teams_analytics_view`。
    -   将现有 Dashboard 的数据源平滑切换至 `teams_legacy_view`。
    -   验证所有报表均正常工作。

4.  **阶段四：全面启用 (持续)**
    -   开始将新项目的数据写入其专属集合。
    -   基于 `teams_analytics_view` 开发新的多项目分析报表。
