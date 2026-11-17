如何强制用Main分支覆盖本地的A分支
以下几步可以强制使用主干覆盖本地分支:
切换到需要合并主干的本地分支, 例如A分支:
Copy
git checkout A
从主干(主干为Main)拉取最新提交
Copy
git pull origin Main
强制使用主干要求本地分支
Copy
git reset --hard origin/Main
把本地A分支强制推送到远程 reposoitory 覆盖原有的A分支
Copy
git push --force origin A
在git pull 与 git push --force 间最好备份A分支, 以防数据丢失.
使用以上4步可以强制使用主干覆盖本地分支, 一旦push --force 就意味着远程的A分支变成了Main主干的历史
