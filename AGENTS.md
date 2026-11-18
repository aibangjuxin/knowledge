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

### 提交 / 推送闸门（自动执行）

`scripts/sanitize-check.sh` 读取**一张全局规则表**，
在 **commit 前**、**commit message**、**push 前**自动扫描，命中就阻断操作并给出替换建议。

```bash
# 安装钩子（换机器 / 重新 clone 后需重装）
bash scripts/install-sanitize-hooks.sh

# 手动扫描
bash scripts/sanitize-check.sh --staged      # 暂存区新增内容
bash scripts/sanitize-check.sh --commit HEAD # 某次提交新增内容（附历史统计）
bash scripts/sanitize-check.sh --worktree    # 工作区新增内容
bash scripts/sanitize-check.sh --message F   # commit message 文件

# 自动脱敏
scripts/sanitize-replace.sh --file PATH       # 替换文件内容
scripts/sanitize-replace.sh --stdin < F       # 替换 stdin（用于 commit message）
scripts/sanitize-replace.sh --list-rules      # 查看生效的规则表
```

**一张表搞定**：`~/.config/push-replace/replace.txt`（格式见下），
两个仓库共用；需要仓库专属规则时在表里写仓库范围。

```
<代号> <替换值> [仓库范围] [策略]

仓库范围：all（默认） | knowledge | gcp | knowledge,gcp
          仓库名取自 origin 远端地址最后一段（去 .git），取不到则用仓库目录名
策略    ：block（默认，命中即阻断） | allow（只统计报告，不阻断）
```

举例（下面的代号/占位符都是示意，实际用你本机表里的真实值）：

```
<代号A>           <占位符A>                         # 所有仓库，命中即阻断
<代号B>           <占位符B>        knowledge       block   # 只在 knowledge 阻断
<代号B>           <占位符B>        gcp             allow   # gcp 允许保留
<代号C>           <占位符C>        all             allow   # 两仓库都允许保留
```

- **判定范围：只管本次新增 / 推送的内容。**
  已经推送过的历史内容不再追究（只在 `--commit` / `--worktree` 给出统计，不阻断）——
  否则仓库里的遗留代号会让每一次推送都被拦死。
- 路径只查**新增 / 重命名**的；已存在的老路径不再追究。
- 命中判定：代号出现在标识符 / 域名 / 路径等**有意义位置**才算命中；
  base64 / 证书 / JAR 里的随机字节只做汇总提示，不阻断。
- 扫描范围：文件**内容** + 新增文件**路径**（文件名 / 目录名同样会公开）。
- 紧急跳过：`SKIP_SANITIZE=1 git push ...`（对所有扫描模式生效，会打印醒目告警）。
- 钩子装在 `.git/hooks/`（不随仓库提交）；脚本本身不含任何代号。
- 想给某个仓库加**仓库本地**规则，也可以放 `.git/sanitize-denylist.txt`（阻断）
  或 `.git/sanitize-residual.txt`（只报告）—— 仓库本地表优先级高于全局表。

### push 流程与清单的关系（必读）

本机 alias `pushc`（= `bash push-llama.sh`）与 `push.sh` 的完整流程：

```
按规则表替换内容 → 按规则表重命名路径 → git add → 生成 commit message
→ 脱敏 commit message → 闸门复核(--staged) → commit → push → pre-push 闸门
```

- **替换规则** = 全表（block + allow 都替换）；**阻断标准** = 表里 policy=block 的。
- 规则里的「替换值」本身若含代号，会被就地清洗掉（用 block 规则清洗），
  避免「替换完又被自己拦」。
- 替换与扫描用的是**同一套命中判定**（左边界 + base64 片段排除），
  所以「扫出来的」一定能「替换掉」，不会出现反复拦截。
- 新增代号只要加进全局表，push 流程立即生效，无需改脚本。
- `.git/sanitize.conf` 是本机配置（不提交）：`rename=0` 关闭路径重命名。
- 推 `git push --force` 仍然危险（见下文「历史与 Git 操作」）：先确认闸门已跑过。

### 残留处理

全局表里 policy=`allow` 的代号是**明确允许保留**的（另一类客户代号，低敏感），
闸门只统计报告、不阻断；但 push 流程仍会顺带脱敏**被改动文件**里的它们。

若将来决定彻底处理：先在本机确认映射方案
（例如三类客户代号映射到 `clienta` / `clientb` / `clientc` 这类通用名），
再执行替换并提交；清零后把表里的策略从 `allow` 改成 `block` 就会立即生效。

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
