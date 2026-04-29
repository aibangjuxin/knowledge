# Git Blame 与代码格式化：保持历史清晰的工程实践

## 背景

在追求"整洁代码"与"清晰的历史追踪（git blame）"之间，往往存在冲突。

在增加新功能或修复 Bug 的同时，顺便做了一些不相关的代码格式化，这在代码评审（Code Review）和长期维护中通常被视为一种"反模式"。

以下是基于生产级工程实践建议的方案与最佳实践。

---

## 1. 核心原则：原子化提交 (Atomic Commits)

**基本原则**：一个提交只做一件事。

将功能性改动（Logic Changes）与表现形式改动（Formatting/Refactoring）混合在一起，会增加 Code Review 的心智负担，且会污染 git blame，导致难以追溯某行逻辑到底是什么时候、由谁、为了什么目的修改的。

---

## 2. 最佳实践方案

### 方案 A：先格式化，再写逻辑（推荐）

如果你发现文档乱到无法忍受，或者格式化有助于你编写新逻辑：

1. **提交 1**：仅进行格式化改动（Refactor/Style）。提交信息注明：
   ```
   style: format [filename] for better readability
   ```

2. **提交 2**：基于格式化后的版本编写业务逻辑。提交信息注明：
   ```
   feat: add [feature name]
   ```

**优点**：历史清晰，Reviewer 可以快速跳过提交 1，专注于提交 2 的逻辑改动。

### 方案 B：使用 git stash 拆分改动（补救措施）

如果已经改混了，可以使用以下技巧拆分：

1. 使用 `git add -p`（patch mode）交互式地选择你真正需要的逻辑改动进入暂存区
2. 将逻辑改动提交
3. 将剩余的格式化改动撤销（或者作为另一个独立提交）

### 方案 C：配置 IDE 仅对"修改行"进行格式化

现代 IDE（如 VS Code, GoLand, IntelliJ）都支持一种设置：**Format on Save -> Modified Lines Only**。

**做法**：开启此项后，保存时 IDE 只会格式化你动过的那几行逻辑代码，而不会触及文档的其他部分。

**优点**：实现了最小化改动，彻底避免干扰 git blame。

---

## 3. 如何解决 git blame 追踪问题？

如果项目中已经存在大量格式化提交，导致 git blame 满屏都是"Format"信息，你可以利用 Git 的一个高级特性。

### .git-blame-ignore-revs

创建一个名为 `.git-blame-ignore-revs` 的文件，将那些纯格式化的 Commit 哈希值填进去。

**在项目根目录创建文件**：

```bash
# 忽略某次大规模格式化改动
<commit-hash-of-formatting-change>
```

**配置本地 Git 使用该文件**：

```bash
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

**GitHub 支持**：GitHub 也会自动识别此文件。在 GitHub UI 上查看 Blame 时，它会自动跳过这些指定的提交，显示这些行真正的逻辑作者。

---

## 4. 团队层面的长期解决方案

为了避免个人在开发时纠结"要不要格式化"，建议在生产级项目中实施以下自动化流程：

| 措施 | 工具建议 | 目的 |
|------|----------|------|
| 强制 Lint/Format 检查 | Prettier / Gofmt / Ruff | 统一全员风格，不留格式化争议空间 |
| Pre-commit Hook | pre-commit 框架 | 在提交前强制执行格式化，确保入库的代码永远是标准格式 |
| CI 流水线拦截 | GitHub Actions | 发现格式不规范的 PR 直接阻断，要求作者先修复格式 |

---

## 总结建议

对于当前的情况，最专业的做法是：

1. **回滚格式化改动**，只保留逻辑改动进行提交（最小化原则）
2. 如果确实需要格式化，**单独开一个 PR** 或者**单独一个提交**
3. 在 IDE 中开启 **"Format Modified Lines Only"**，从源头避免此类困扰

这样做不仅是为了 git blame 的可追溯性，更是为了降低 Reviewer 的负担，让团队协作更高效。