# 三平台Bug查询结果示例

下面的表格展示了来自Google、Aliyun和AWS三个平台的bug查询结果示例：

| platform | eid | jira |
|----------|-----|------|
| google | ISSUE-1001 | P1 |
| google | ISSUE-1002 | P2 |
| google | ISSUE-1003 | P3 |
| aliyun | ALI-2001 | Critical |
| aliyun | ALI-2002 | Major |
| aliyun | ALI-2003 | Minor |
| aws | AWS-3001 | Blocker |
| aws | AWS-3002 | High |
| aws | AWS-3003 | Medium |

> 说明：
> - platform: 表示问题来源平台（google/aliyun/aws）
> - eid: 表示问题的唯一标识符
> - jira: 表示问题的优先级/等级

这个表格展示了合并后的查询结果，每一行代表一个bug记录，包含了该bug的平台来源、问题ID和优先级信息。不同平台可能使用不同的优先级系统，比如：
- Google可能使用P1、P2、P3等级别
- Aliyun可能使用Critical、Major、Minor等级别
- AWS可能使用Blocker、High、Medium等级别