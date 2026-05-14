你可以通过创建或编辑 `.gitignore` 文件来忽略以点开头的目录。以下是具体操作：

```bash
# 在项目根目录创建或编辑 .gitignore 文件
echo ".*/" >> .gitignore
```

或者直接编辑 `.gitignore` 文件：

```plaintext:/Users/lex/git/knowledge/.gitignore
# 忽略所有以点开头的目录
.*/

# 如果你想保留某些特定的点开头目录，可以使用 !
!.github/
```

说明：
1. `.*/` 会忽略所有以点开头的目录
2. 如果已经提交过这些目录，需要先从 git 缓存中删除：
```bash
# 从 git 缓存中删除已跟踪的隐藏目录
git rm -r --cached .*
```

1. 然后重新提交更改：
```bash
git add .gitignore
git commit -m "更新 .gitignore：忽略点开头的目录"
```

这样设置后，git 将不会跟踪以点开头的目录。