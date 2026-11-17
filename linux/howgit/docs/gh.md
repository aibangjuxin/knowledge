# GitHub CLI (`gh`) 速览

> ⚠️ **本文已合并至 [gh-user-guide.md](../gh-user-guide.md)**，内容以该文档为准。
>
> 本文件保留为入口指针，避免旧链接失效；如需修改 `gh` 相关文档，请直接编辑
> [linux/howgit/gh-user-guide.md](../gh-user-guide.md)。

## 一句话总结

`gh` 是 GitHub 官方 CLI，把 **PR / Issue / CI / Release** 整套协作流程搬进终端：

| 想干什么 | 原生 Git | `gh` |
| --- | --- | --- |
| 发起 PR | 去网页点 | `gh pr create --base <base> --head <head> --title "..." --body "..."` |
| 看 PR 详情 | 去网页点 | `gh pr view`（终端直接打印） |
| 看改动 | `git diff` + 网页 | `gh pr diff` |
| 看 CI | 去 Actions 页面 | `gh pr checks --watch` / `gh run view <id> --log-failed` |
| Code Review | 网页评论 | `gh pr review --approve / --request-changes` |
| 合并 + 清理分支 | 网页点 | `gh pr merge --squash --delete-branch` |
| 拉别人的 PR | `git fetch origin pull/.../head` | `gh pr checkout 123` |

## 最重要的三条认知

1. **`gh pr/issue/run` 默认都不开浏览器**，只在终端输出；只有显式加 `--web` 才会跳浏览器。
2. **`gh browse` 是例外** —— 它默认会开浏览器，只想要 URL 时加 `-n / --no-browser`。
3. **想在终端看「网页信息」** 用 `--json` + `--jq` 结构化取字段，例如：
   ```bash
   gh pr view --json number,title,url,mergeable,reviewDecision,statusCheckRollup \
     --jq '{n: .number, url, mergeable, reviewDecision}'
   ```

完整命令清单、CI 脚本化、`gh api` / `gh search` 兜底、常见坑速查表，全部见
**[gh-user-guide.md](../gh-user-guide.md)**。
