# Change Request × Release 集成工具调研

> 背景:每月要开一定数量的 CR,CR 系统未定(Jira / ServiceNow / 自研),目前手工维护 `cr/<id>-filled.md` 后人工复制。希望自动化但不知道用什么工具。
> 输出建议 + 出处链接 + 在本仓库的具体落地。

## 1. 推荐的技术栈(分两种公司路径)

### 路径 A — 公司用 Jira(Jira Service Management / Jira Software)
**单点工具:** [`pycontribs/jira`](https://github.com/pycontribs/jira) — `pip install jira` 即可,`from jira import JIRA`,`JIRA(server, basic_auth=...)`,`jira.create_issue(fields=...)` 一行开 CR,`jira.transition_issue()` 走审批。
**CR ↔ GitHub 双向同步:** 首选 [`rh-uxd/github-jira-sync`](https://github.com/rh-uxd/github-jira-sync)(Node.js,last-updated-wins 冲突解决,GraphQL 批量,处理 Epic/Sub-task),备选 [`radaiko/Sinking`](https://github.com/radaiko/Sinking)(Jira+GitHub+Azure DevOps 三向)。我仓库里是 Python,可以拉一个 sidecar Node 容器跑 sync,主链路仍用 pycontribs/jira。
**Release notes / 自动填充:** [`github-changelog-generator/github-changelog-generator`](https://github.com/github-changelog-generator/github-changelog-generator)(Ruby,`gem install github_changelog_generator`,按 tag + label 自动聚合),把生成的 markdown 灌进 CR description 即可。

### 路径 B — 公司用 ServiceNow Change Management
**端到端参考实现:** [`kj-hilger/change-automation-core`](https://github.com/kj-hilger/change-automation-core) — Python 编排器,从 Jira/Kubernetes/Grafana/LeanIX 取元数据,用 OpenAI 起草"变更理由"(人审后才进 SN),通过 ServiceNow Table API 自动开 Change,把 To-Do 写到 Confluence。该 README 明确:ServiceNow Change 三类是 **Standard / Normal / Emergency**,且对每个 Change 自动生成实施计划。RTO/RPO、backout plan、risk assessment 是 DORA/VAIT 审计必备字段。
**SN 官方 API 入口:** Table API(`/api/now/table/change_request`)。`requests.post(url, auth=(user, pwd), json=payload)` 即可创建,用 `risk`、`impact`、`backout_plan`、`test_plan`、`cab_required` 字段做审批门禁。

## 2. CR 必须的元数据(两家系统通用)

| 字段 | Jira | ServiceNow | 来源 |
|---|---|---|---|
| 变更理由 / Description | `description` | `short_description` + `description` | rh-uxd/github-jira-sync README |
| 风险评估 | Label `risk-high` 或 customfield | `risk`, `impact` | change-automation-core |
| 影响范围 / RTO/RPO | customfield | `business_duration`, `backout_plan` | change-automation-core(DORA 合规) |
| 回滚计划 | customfield | `backout_plan` | change-automation-core |
| CAB 审批 | Workflow post-function | `approval` + `cab_required=true` | change-automation-core |
| 关联 PR/代码 | 远端链接 (GitHub URL) | `work_notes` 里附 URL | rh-uxd/github-jira-sync README |
| 实施窗口 | customfield | `start_date`, `end_date` | change-automation-core |

## 3. CR ↔ IaC release 的桥接(业界做法)

[change-automation-core](https://github.com/kj-hilger/change-automation-core) 给出了完整链路:Jira Issue(kanban 状态) → Python 聚合器 → ServiceNow Change(创建并附 Jira 远端链接) → Confluence 实施计划(每个 To-Do 有 Git "Edit Mode" 链接) → PR 改进自动化逻辑(GitOps 持续改进闭环)。
对我就够了:**PR description 里写 `CR-1234` → release 脚本 grep tag → 反向调 Jira/SN API 把 PR URL 写进 CR 的 external link / work notes**。

## 4. 在本仓库的具体落地(`cr-sync.sh` 占位升级版)

```bash
# cr-sync.sh — 把 cr/<id>-filled.md 推到 CR 系统
# 用法: cr-sync.sh <id> --target=jira|servicenow
ID="${1:?usage: cr-sync.sh <id> --target=jira|servicenow}"
SRC="cr/${ID}-filled.md"
BODY=$(cat "$SRC")
case "$2" in
  --target=jira)
    # pip install jira; export JIRA_URL, JIRA_USER, JIRA_TOKEN
    python3 -c "
from jira import JIRA
import os, json
j = JIRA(os.environ['JIRA_URL'], basic_auth=(os.environ['JIRA_USER'], os.environ['JIRA_TOKEN']))
issue = j.create_issue(project='CR', summary='$ID', description=open('$SRC').read(),
                       issuetype={'name':'Change'}, customfield_risk='Low')
print(issue.key)
" > ".cr/${ID}.jira_key"
    ;;
  --target=servicenow)
    # Table API: POST /api/now/table/change_request
    curl -s -u "$SN_USER:$SN_PASS" -H "Content-Type: application/json" \
      -X POST "$SN_URL/api/now/table/change_request" \
      -d "$(jq -n --arg d "$BODY" '{short_description:$d,risk:2,impact:3,type:"normal",backout_plan:"see PR"}')" \
      > ".cr/${ID}.sn.json"
    ;;
esac
```

下一步:
1. `pip install jira`(路径 A)/ 在 SN instance 上建 personal dev instance 试 Table API(路径 B)
2. 跑 [`rh-uxd/github-jira-sync`](https://github.com/rh-uxd/github-jira-sync) 做双向往返,设 `JIRA_EMAIL` + `JIRA_API_TOKEN`
3. 把 `cr/<id>-filled.md` 模板加上 `risk / RTO/RPO / backout` 段,直接喂给 `create_issue` 的 fields

## 出处

- [`pycontribs/jira`](https://github.com/pycontribs/jira) — Python Jira 客户端事实标准
- [`rh-uxd/github-jira-sync`](https://github.com/rh-uxd/github-jira-sync) — PatternFly 在用的双向同步
- [`radaiko/Sinking`](https://github.com/radaiko/Sinking) — Jira+GitHub+AzureDevOps 三向
- [`kj-hilger/change-automation-core`](https://github.com/kj-hilger/change-automation-core) — Jira → ServiceNow Change 的端到端参考(DORA 合规)
- [`github-changelog-generator/github-changelog-generator`](https://github.com/github-changelog-generator/github-changelog-generator) — 自动 release notes 聚合