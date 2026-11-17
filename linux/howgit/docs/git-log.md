我一般会把本地修改提交到github,且Log里面,我一般会有个filename=$(git diff --name-only HEAD | tail -n 1)的定义定提交到commit_message,那么我现在想写一个脚本.
统计比如我最近20次的提交中涉及的文件的改动


我来帮你写几个脚本，提供不同的方式来统计最近提交的文件改动：

1. 基础版本 - 显示最近20次提交涉及的文件：
```bash:/Users/lex/git/knowledge/howgit/scripts/git_recent_changes.sh
#!/bin/bash

# 显示最近20次提交涉及的文件列表
git log -20 --name-only --oneline | grep -v "^[0-9a-f]\{7\}" | sort | uniq
```

2. 详细版本 - 包含文件改动统计：
```bash:/Users/lex/git/knowledge/howgit/scripts/git_changes_stats.sh
#!/bin/bash

echo "最近20次提交的文件改动统计："
echo "----------------------------------------"

# 获取最近20次提交的哈希值
commits=$(git log -20 --pretty=format:"%h")

for commit in $commits; do
    echo "提交: $(git log -1 --pretty=format:"%h - %s (%cr)" $commit)"
    echo "修改的文件:"
    git show --stat --oneline $commit | tail -n +2
    echo "----------------------------------------"
done
```

3. 高级版本 - 包含详细的改动统计和文件分类：
```bash:/Users/lex/git/knowledge/howgit/scripts/git_detailed_stats.sh
#!/bin/bash

echo "=== 最近20次提交的详细统计 ==="
echo

# 文件改动统计
echo "文件改动频率统计："
git log -20 --name-only --oneline | grep -v "^[0-9a-f]\{7\}" | sort | uniq -c | sort -nr

echo -e "\n各类型文件的改动统计："
git log -20 --name-only --oneline | grep -v "^[0-9a-f]\{7\}" | grep -v "^$" | while read file; do
    extension="${file##*.}"
    if [ "$extension" = "$file" ]; then
        extension="无扩展名"
    fi
    echo "$extension"
done | sort | uniq -c | sort -nr

echo -e "\n每次提交的改动行数："
git log -20 --pretty=format:"%h - %s" --shortstat
```

其他获取方式：

1. 使用 GitHub API：
```bash:/Users/lex/git/knowledge/howgit/scripts/github_api_stats.sh
#!/bin/bash

# 需要设置你的 GitHub token
GITHUB_TOKEN="your_token"
REPO="owner/repo"

curl -H "Authorization: token $GITHUB_TOKEN" \
     "https://api.github.com/repos/$REPO/commits?per_page=20" | \
     jq '.[].files[].filename' | sort | uniq
```

2. 使用 git log 的格式化输出：
```bash:/Users/lex/git/knowledge/howgit/scripts/git_formatted_log.sh
#!/bin/bash

# 格式化输出最近20次提交的信息
git log -20 --pretty=format:"%h%x09%an%x09%ad%x09%s" --date=short --name-status
```

使用方法：
```bash
chmod +x script_name.sh
./script_name.sh
```

这些脚本各有特点：
1. 第一个脚本最简单，只显示文件列表
2. 第二个脚本显示每次提交的详细信息
3. 第三个脚本提供完整的统计信息
4. GitHub API 方式可以获取更多信息
5. 格式化输出方式可以自定义显示格式

你可以根据需求选择合适的方式，也可以组合使用这些命令来获取更详细的信息。

./git_detail_stats.sh
=== 最近20次提交的详细统计 ===

文件改动频率统计：
   8 .obsidian/workspace.json
   5 gcp/High-availability.md
   4 gcp/firewall-hit.md
   3 gcp/how-node-upgraded.md
   2 kong/kong-hight-availablity.md
   2 kong/capture-kong-log.md
   2 k8s/enhance-probe.md
   2 k8s/endpoint.md
   1 network/curl-request-squid.md
   1 kong/kongdp-setting-timeout.md
   1 kong/kong-healthcheck-rt.md
   1 k8s/scripts/pod_status.sh
   1 k8s/liveness.md
   1 k8s/busybox/nas-service.md
   1 k8s/busybox/nas-deployment.md
   1 gcp/sa/verify-gcp-sa.md
   1 gcp/gcp-upgrade-and-high-availablility.md

各类型文件的改动统计：
  28 md
   8 json
   1 sh

每次提交的改动行数：
.obsidian/workspace.json
gcp/High-availability.md
gcp/firewall-hit.md
gcp/gcp-upgrade-and-high-availablility.md
gcp/how-node-upgraded.md
gcp/sa/verify-gcp-sa.md
k8s/busybox/nas-deployment.md
k8s/busybox/nas-service.md
k8s/endpoint.md
k8s/enhance-probe.md
k8s/liveness.md
k8s/scripts/pod_status.sh
kong/capture-kong-log.md
kong/kong-healthcheck-rt.md
kong/kong-hight-availablity.md
kong/kongdp-setting-timeout.md
network/curl-request-squid.md
``logs
18f5189 - This is for my macOS git push or pull at Sat Feb 15 20:35:09 CST 2025. Last changed file: kong/capture-kong-log.md
 1 file changed, 40 insertions(+)

db19973 - commit_message change dir and edit markdown
 3 files changed, 88 insertions(+), 9 deletions(-)

19f6a42 - commit_message change dir and edit markdown kong
 1 file changed, 1 insertion(+), 1 deletion(-)

4c2eb49 - Merge branch 'main' of github.com:aibangjuxin/knowledge
6a90f7c - commit_message change dir and edit markdown kong
 8 files changed, 1039 insertions(+), 5 deletions(-)

e691348 - Update endpoint.md
 1 file changed, 1 insertion(+), 1 deletion(-)

8ed2fa8 - This is for my iPad Pro git push or pull at Fri Feb 14 14:12:25 UTC 2025. Last changed file: k8s/endpoint.md
 1 file changed, 54 insertions(+)

3c909ca - Update High-availability.md
 1 file changed, 67 insertions(+)

af21532 - Update High-availability.md
 1 file changed, 1 insertion(+), 1 deletion(-)

642f8a5 - commit_message change dir and edit markdown kong
 3 files changed, 395 insertions(+), 1 deletion(-)

3dd0183 - This is for my macOS git push or pull at Fri Feb 14 19:46:33 CST 2025. Last changed file: gcp/High-availability.md
 1 file changed, 5 insertions(+), 2 deletions(-)

8fd43d0 - commit_message change dir and edit markdown kong
 4 files changed, 1436 insertions(+), 4 deletions(-)

c8c04ed - This is for my macOS git push or pull at Fri Feb 14 15:34:28 CST 2025. Last changed file: gcp/how-node-upgraded.md
 1 file changed, 106 insertions(+)

e56e7a4 - commit_message change dir and edit markdown
 2 files changed, 171 insertions(+), 1 deletion(-)

db69a6a - This is for my macOS git push or pull at Fri Feb 14 11:41:57 CST 2025. Last changed file: gcp/firewall-hit.md
 1 file changed, 9 insertions(+), 8 deletions(-)

bfa1802 - This is for my macOS git push or pull at Fri Feb 14 10:54:48 CST 2025. Last changed file: gcp/firewall-hit.md
 1 file changed, 137 insertions(+), 1 deletion(-)

b7bef80 - This is for my macOS git push or pull at Fri Feb 14 10:28:50 CST 2025. Last changed file: gcp/firewall-hit.md
 1 file changed, 28 insertions(+), 22 deletions(-)

cf33dd7 - commit_message change dir and edit markdown
 2 files changed, 39 insertions(+), 1 deletion(-)

c5d5188 - commit_message change dir and edit markdown
 1 file changed, 7 insertions(+)

2bd6041 - commit_message change dir and edit markdown
 3 files changed, 160 insertions(+), 17 deletions(-)

```