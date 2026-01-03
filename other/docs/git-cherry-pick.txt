您可以使用 `git cherry-pick` 命令来将某个分支上的特定 commit 合并到 master 分支上。具体操作步骤如下：

1. 切换到 master 分支：`git checkout master`
2. 执行 cherry-pick 命令，
将需要合并的 commit ID 传入：`git cherry-pick <commit ID>`
3. 如果需要合并多个 commit，
可以重复执行 cherry-pick 命令
4. 合并完成后，将修改推送到远程仓库：
`git push origin master`

请注意，使用 cherry-pick 命令合并 commit 时，
可能会导致代码冲突。如果出现冲突，请根据提示进行手动解决。

您可以使用以下命令来查看 commit ID：

```
git log
```

执行该命令后，会显示当前分支的所有 commit 记录，
每个 commit 记录都包含一个唯一的 commit ID。
您可以使用上下箭头来查看不同的 commit 记录，
commit ID 通常显示在每个记录的开头，如下所示：

```
commit 4b5d6e1f8f9b1b2e4f2a5c7b3d4e5f6a7b8c9d0e
Author: John Doe <johndoe@example.com>
Date:   Tue May 4 18:00:00 2023 +0800

    Add new feature
```

在上面的示例中，commit ID 为 `4b5d6e1f8f9b1b2e4f2a5c7b3d4e5f6a7b8c9d0e`。
您可以将其复制并在其他命令中使用。

在 Git 中，`cherry-pick` 
是一种将指定的 commit 应用到当前分支的操作。
它可以将一个或多个 commit 从一个分支复制到另一个分支，
而不需要将整个分支合并。
通常情况下，`cherry-pick` 操作用于将某个分支上的特定 
commit 应用到另一个分支上，以便在不影响其他 commit 的情况下，
将特定的更改合并到目标分支中。

具体来说，`cherry-pick` 命令会将指定的 commit 的更改应用到当前分支上，并创建一个新的 commit 记录。这个新的 commit 记录包含了原始 commit 的更改，但是 commit ID 和提交时间等信息会有所不同。这意味着，`cherry-pick` 操作不会改变原始 commit 的历史记录，而是在当前分支上创建一个新的 commit 记录。

需要注意的是，由于 `cherry-pick` 操作会将指定的 commit 应用到当前分支上，
因此可能会导致代码冲突。如果出现冲突，您需要手动解决冲突，并重新提交更改。



`git log` 命令可以查看当前分支的 commit 记录，
包括 commit ID、作者、提交时间、提交信息等。
如果您在执行 `git log` 命令时，
没有指定分支名称或 commit ID，
那么它会显示当前所在分支的所有 commit 记录。
如果您在不同的分支上进行了 commit 操作，
那么每个分支都会有自己的 commit 记录。
因此，`git log` 命令会记录每个分支的 commit 记录，
并按照提交时间的顺序显示这些记录。

需要注意的是，如果您切换到另一个分支，
那么 `git log` 命令会显示该分支的 commit 记录，
而不是之前的分支。
如果您想要查看其他分支的 commit 记录，
可以在 `git log` 命令后指定分支名称或 commit ID。
例如，`git log branch-name` 可以查看指定分支的 commit 记录。