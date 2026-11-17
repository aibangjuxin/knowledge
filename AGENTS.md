# AGENTS.md

## 仓库定位

个人技术知识库（公开仓库），内容为 GCP / K8s / Linux / 网络等工程笔记，
同时通过 GitHub Pages 发布静态站点：<https://aibangjuxin.github.io/knowledge/>

## 内容脱敏约定（必须遵守）

本仓库是 **public**。任何内部资源标识符都不得进入本仓库或其历史，
包括但不限于：组织 / 团队 / 客户代号、项目号或账号名、真实 VPC / 子网 /
集群 / 实例名、内部域名与邮件后缀。

### 占位符约定

统一替换成语义清晰的通用词，使示例仍然可读：

| 原始类别 | 占位符示例 |
|:---|:---|
| 项目号 / 账号 | `example-project`、`example-projectID` |
| 团队代号 | `appteam`、`ukteam` |
| 内部环境前缀 | `internal` |
| 业务系统名 | `example-apiname1` 这类通用名 |

替换时**保留** CIDR、region、拓扑结构与文档可读性——示例仍要能读懂，
只是不能指向真实资源。

> ⚠️ 不要在本仓库内维护「原代号 → 占位符」的对照表，也不要在自检命令里
> 直接写出真实代号——那等于把刚脱敏掉的内容再公开一次。

### 三条容易踩的坑

1. **只替换内容不够，路径也要换。** 目录名、文件名里的代号 sed 改不到，
   必须 `git mv`。同理，commit message 也会被公开看到，别在里面写对照表。
2. **大小写变体要一起处理。** 代号在 header 名、图表标题里常被写成
   `CamelCase` 或全大写，只做小写替换会漏网。
3. **证书 / JAR / 压缩包里的随机字节会误报。** base64 里偶然出现代号字样
   是正常现象，不要去替换——会把证书示例改坏。判断标准是它是否出现在
   标识符、域名、路径、邮箱这些**有意义的位置**。

### 提交前自检

真实代号清单只保存在**本机**，不随仓库提交（仓库里写出清单等于二次泄露）：

- `.git/sanitize-denylist.txt` —— 禁止出现，命中即必须替换后再提交
- `.git/sanitize-residual.txt` —— 已知但尚未处理的残留代号，命中属已知问题

```bash
# 禁用代号（大小写不敏感）：输出必须为空
git ls-files -z | xargs -0 grep -liIF -f .git/sanitize-denylist.txt

# 剔除 base64 长串后再查，用于过滤二进制里的随机字节误报
git ls-files -z | xargs -0 perl -ne \
  's/[A-Za-z0-9+\/=]{30,}/<B64>/g; print "$ARGV: $_" if /(CODE1|CODE2)/i'

# 残留代号：用于摸清待处理范围
git ls-files -z | xargs -0 grep -lIF -f .git/sanitize-residual.txt
```

`.git/` 内的清单不随 clone 分发；换机器或重新 clone 后需由维护者重建，
重建时同样只写在本地，不要提交。

### 敏感度分级（重要）

上述代号属于**低敏感**的内部标识符——它们不是凭据，公开后不直接导致账号失陷。
维护者的口径是：历史中已经存在的痕迹**不再回溯清理**，只要求**今后不再新增**。

因此：不要为了清理这类代号去做「删库重建 + 改名」级别的操作——代价远大于收益。
真正需要紧急处置的是**凭据类内容**（密码、token、私钥、真实账号），那种才走删库重建。

### 残留处理

`.git/sanitize-residual.txt` 中的代号量大且属另一类客户代号，同样属于低敏感，
目前保留在仓库里是可以接受的，无需处理。若将来决定处理：先在本机确认映射方案
（例如三类客户代号映射到 `clienta` / `clientb` / `clientc` 这类通用名），
再执行替换并提交。

## 历史与 Git 操作

- 本仓库历史已被 squash 成两个提交（根提交 + 本说明文件），
  更早的历史在 2026-11-18 通过**删除仓库 + 改名重建**方式彻底清除。
- `gcp/example-infra-gcp-release/` 与 `docs/gcp/example-infra-gcp-release/`
  是私有仓库 release 流程的架构图（HTML/SVG），已脱敏后保留；
  该私有仓库的完整 tar 快照已从公开仓库移除，**不要再把私有仓库打包提交进来**。
- 因此 `git push --force` 在本仓库要格外谨慎：一旦推入含敏感内容的 commit，
  就必须重走「删除仓库 + 改名重建」，仅 force-push 不足以清除服务端旧对象。
- 修改已推送的 commit 时用 `git commit --amend` + `git push --force`，
  让含敏感内容的 blob 变成不可达对象，而不是用新提交把它盖住——
  盖住的话旧 blob 仍可通过对应 SHA 的 URL 直接浏览。
- 本地克隆已执行过 `git reflog expire --expire=now --all && git gc --prune=now`。
  注意 `reflog expire --all` 会连带清掉 `git stash` 的 reflog，
  `git stash list` 会变空但 `stash@{0}` 仍在——必要时用
  `git update-ref --create-reflog` 重建条目。
- `git stash` 中的 `fast-import`（dns-peering 相关）为进行中的工作，请勿随意丢弃。
  它若锚定在旧提交上，会连带保留整棵旧历史，必要时先迁移到当前 main。
