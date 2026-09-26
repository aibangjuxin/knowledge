GitHub 官方命令行工具 `gh` 不仅仅是 `git` 的简单包装，它把原本需要在网页端（GitHub.com）来回切换的很多操作直接带回到了终端中。

如果你平时习惯了纯 Git 命令行，那么 `gh` 最核心的价值在于：**它打通了 Git 代码提交与 GitHub 平台工作流（PR、Issue、Actions、Release）之间的壁垒**。

以下是 `gh` 相比原生 Git 拥有、且能极大提升日常效率的几个核心杀手级功能：

---

### 一、 终端原生处理 Pull Request (PR) —— 免去网页反复切标签

这是日常使用频率最高的功能。传统 Git 只能提交代码，而 `gh` 可以直接管理整个 PR 生命周期：

* **一键创建 PR**：
在本地分支改完代码后，直接运行 `gh pr create`，它会自动检测当前分支，弹出生动简洁的交互界面让你选择目标分支、填写 Title 和 Body，甚至可以直接关联 Issue。
* **终端内 Review 与审批**：
* 查看 PR 列表：`gh pr list`
* 查看特定 PR 详情、改动的文件（Diff）及评论：`gh pr view <编号>`
* **直接在终端进行 Code Review**：`gh pr review`（支持直接 Approve、Request Changes 或留言）。


* **本地快速检出与测试**：
别人提了一个 PR，你想在本地拉下来测试，不用去搞一堆复杂的 `git fetch origin pull/...`，直接一句：`gh pr checkout <PR编号>` 搞定。
* **终端合并**：
审核没问题后，直接在命令行 `gh pr merge --squash --delete-branch` 一气呵成。

---

### 二、 Actions 持续集成监控 —— 不用打开浏览器看流水线

作为架构和基础设施工程师，经常需要排查 CI/CD 流水线：

* **查看运行状态**：输入 `gh run list` 可以直接看到最近的 GitHub Actions 运行历史（成功、失败、耗时）。
* **实时查看日志**：发现某个 Pipeline 报错了，不用去网页上点半天找日志，直接用 `gh run view <run-id> --log-failed` 把失败的日志直接打印在终端里排查。
* **手动触发**：`gh workflow run <12345>` 可以直接在终端触发一个工作流。

---

### 三、 Issue 与项目管理 —— 把终端当看板

* **快速提 Issue**：`gh issue create --title "Bug: 网关路由异常" --body "..."`
* **指派与过滤**：`gh issue list --assignee "@me" --label "bug"` 可以直接在终端筛选属于你的任务。

---

### 四、 极其强大的扩展生态 (`gh extension`)

如果官方自带的功能还不够，`gh` 支持安装丰富的官方或第三方扩展，比如：

* **`gh repo clone` / `gh repo fork**`：秒级克隆或 Fork 仓库。
* 社区还有各种增强扩展（例如快速搜索 PR、管理 Codespaces 等）。

---

### 💡 总结对比

| 操作场景 | 原生 Git | GitHub CLI (`gh`) |
| --- | --- | --- |
| **代码提交/推送** | `git add` / `git commit` / `git push` | 同样支持，底层一致 |
| **发起 Pull Request** | 需去 GitHub 网页端点新建 | `gh pr create`（全交互式） |
| **Code Review / 合并** | 网页端网页点点点 | `gh pr view` / `gh pr review` / `gh pr merge` |
| **查看 CI 流水线状态** | 网页端 Actions 页面 | `gh run list` / `gh run view --log-failed` |

**简而言之**：Git 帮你把代码推送到远端，而 `gh` 帮你把远端 GitHub 平台上的所有协作流程（PR、CI、Issue）无缝拉回到了你的 Terminal 终端里。如果你不想在终端和浏览器之间频繁切换，`gh` 是一个非常值得习惯的效率神器。