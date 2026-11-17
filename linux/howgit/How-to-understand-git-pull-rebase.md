# How-to understand git pull --rebase

> 这条命令到底在做什么?跟 merge 有什么区别?为什么团队里有人天天喊"用 rebase"?

`git pull --rebase` 本质是 **"拉取远端更新,把自己的本地提交挪到远端最新提交之上"**——重写你本地未推送的 commit,把它们"重新播"到远端当前 tip 后面。

它是 `git fetch` + `git rebase` 的组合,默认值其实是 `git pull --merge`(merge 模式)。

---

## 1. 一句话定义

> `git pull --rebase`: 把远端最新提交拉下来,然后**把你本地独有的提交(在远端最新 tip 之后)一个个 cherry-pick 上去**,得到一条干净的线性历史。

引用官方文档原文:

> `git pull --rebase` runs `git rebase`. `git pull --no-rebase` runs `git merge`. `git pull --squash` runs `git merge --squash`. You can also set the configuration options `pull.rebase`, `pull.squash`, or `pull.ff` with your preferred behaviour.[1]

也就是说,`--rebase` 不是默认,而 `git pull` 默认走的是 **merge 模式**(在没有显式指定 reconciliation method 的情况下)。[1]

---

## 2. 跟默认的 merge 模式对比

最直观的对比:同一次同步远端 main 的场景,本地有 2 个未推送的提交:

```
          C1 --- C2 --- C3         (origin/main, 远端最新)
                       \
                        D --- E      (你本地的提交,未推送)
```

### 2.1 默认 `git pull`(merge 模式)

```
          C1 --- C2 --- C3
                       \       \
                        D --- E --- M   (合并提交,保留分叉痕迹)
```

- 生成一个 **M 合并提交**,把你和远端的两条线缝在一起
- 你的提交 D、E 的 **commit hash 不变**
- 历史是 **非线性** 的,看 `git log --graph` 会看到分叉
- M 是个"噪音"提交,只为了记录"我在某个时间点同步了一次远端",代码层面毫无新意

### 2.2 `git pull --rebase`

```
          C1 --- C2 --- C3 --- D' --- E'   (干净的线性历史)
```

- **没有新的合并提交**
- 你的 D、E 被 **重写** 成 D'、E'(因为 parent 变了、commit hash 是根据 parent+tree+author+date 等计算的)
- 历史是 **线性** 的,`git log --graph` 是一条直线
- D、E 的 **commit hash 全变**——这是 rebase 的本质特性

引用 `git-rebase` 官方 DESCRIPTION:

> Transplant a series of commits onto a different starting point. You can also use `git rebase` to reorder or combine commits.[2]

把"transplant"(移植)这个词记住——它就是 rebase 的字面意思:**把一段 commit 序列整棵拔起,移植到另一棵树根上**。

---

## 3. 它的工作机制(Pro Git 原文版)

Pro Git 书 §3.6 把 rebase 的内部步骤讲得很清楚:

> This operation works by going to the common ancestor of the two branches (the one you're on and the one you're rebasing onto), getting the diff introduced by each commit of the branch you're on, saving those diffs to temporary files, resetting the current branch to the same commit as the branch you are rebasing onto, and finally applying each change in turn.[3]

翻译成人话:

1. 找到当前分支和目标分支的 **共同祖先**
2. 把当前分支从祖先之后 **每一个 commit 产生的 diff 暂存** 到临时文件
3. 把当前分支重置到目标分支的 tip(指针直接挪过去,本地独有的提交"消失"——其实还在 reflog 里)
4. 把暂存的 diff 一个个 **cherry-pick 应用** 回去,生成新 commit
5. 新 commit 的作者、时间、内容一致,但 parent 和 hash 都变了

`git pull --rebase` 就是把步骤 1-2 之前多了一步 `git fetch`,把远端最新拿到本地;然后再走 `git rebase`。

---

## 4. 什么时候用、什么时候千万别用

### 4.1 ✅ 推荐用 rebase 的场景

- **本地 feature 分支还没推上去,想把远端 main 的新提交同步进来**:这正是 rebase 的黄金场景
- **想保持 main 分支历史线性、可读**:团队约定 PR merge 前都要 rebase 一次
- **交互式整理本地多次"WIP / 调试输出"提交**:`git pull --rebase` 之后可以 `git rebase -i HEAD~n` 把它们 squash 掉

### 4.2 ❌ 绝对不要 rebase 的场景

引用 Pro Git 书的"金线"警告:

> **Do not rebase commits that exist outside your repository and that people may have based work on.**[3]

具体讲:

- **已经 push 到共享分支的 commit 绝对不能 rebase**。一旦你 rebase 它们然后 force-push,所有基于旧 hash 拉过代码的同事全要 re-merge 一次
- **多人协作的 feature 分支**(不是只有你自己用)也要慎重——同事拉了你 rebase 之前的版本,你再 force-push 就会造成双重历史
- **公共分支如 `main` / `master` / `develop`**——团队所有人都基于它工作,rebase 它们等于制造混乱

Pro Git 给的"灾难示例":你 clone 一个 repo,基于 C3 做工作,远端被同事 force-push 了一次 rebase 后的版本,你 `git pull`(merge 模式)会得到两条重复的 C4/C4' 历史,`git log` 里看到同一个作者/日期/消息的两个 commit,完全没法区分。[3]

**核心判据**:**这个 commit 是只有你自己看到,还是别人也基于它工作了?** 答案决定能不能 rebase。

---

## 5. 几个常被搞混的命令

| 命令 | 等价于 | 用法 |
|------|--------|------|
| `git pull --rebase` | `git fetch` + `git rebase` | 同步远端并 rebase 本地未推送的提交 |
| `git pull --rebase=interactive` | `git fetch` + `git rebase -i` | 同步远端,**交互式**整理(可 squash / reword / drop) |
| `git pull --no-rebase` | `git fetch` + `git merge` | 显式声明走默认 merge 模式 |
| `git pull --autostash` | fetch + rebase,**自动 stash 未提交的本地改动** | 你本地还有未 commit 的工作就想 rebase 时用,避免冲突 stash 手动操作 |
| `git pull --rebase --autostash` | fetch + rebase + autostash | 最常见的"组合拳",本地有 WIP 也能干净 rebase |

官方文档还列了一个 `pull.rebase = merges` 选项,会让 rebase 使用 `git rebase --rebase-merges`,**保留本地 merge commit 的拓扑**——这是给"本地分支内部用了 merge 而不想丢失合并信息"准备的。[1]

---

## 6. 让它成为默认值

如果你个人偏好 rebase(很多团队这样),可以把这条写进 git 全局配置:

```bash
# 全局开启:所有 git pull 默认 rebase
git config --global pull.rebase true

# 仅对某个分支开启(例如只在 main 上 rebase)
git config branch.main.rebase true

# 配合 autostash,处理"本地有未提交改动"
git config --global pull.rebase true
git config --global rebase.autoStash true
```

`pull.rebase` 有四种合法值(官方文档):`true` / `merges` / `false` / `interactive`。[1] `branch.<name>.rebase` 是单分支粒度的覆盖,优先级高于全局。

> **注意**:`branch.autoSetupRebase` 这个变量是**新建分支时**自动给当前分支配 `branch.<name>.rebase=true`,不影响已经存在的分支。它跟 `pull.rebase` 是两个不同的开关。[1]

---

## 7. 出错了怎么办(rebase 不是单向不可逆)

Pro Git 书专门有一节叫 **"Recovering from Upstream Rebase rebase"**——其实就是教你 rebase 出问题怎么回滚。[3]

最常用的两个保险命令:

```bash
# 1. 任何 rebase 开始时,ORIG_HEAD 会被设置成 rebase 前的 tip
git reset --hard ORIG_HEAD     # 一键回到 rebase 前的状态

# 2. 更稳的——用 reflog,无论 ORIG_HEAD 是否被覆盖过
git reflog                     # 找到 rebase 前的 commit hash
git reset --hard <那个hash>
```

如果 rebase 中途遇到冲突,Git 会停下来让你解决。三选一:

```bash
git rebase --continue   # 解决冲突后,继续 rebase 下一个 commit
git rebase --skip       # 跳过当前 commit(慎用,可能丢改动)
git rebase --abort      # 整个 rebase 撤回,回到 rebase 之前的状态
```

`git rebase --abort` 是兜底——只要没 `git gc` 把 reflog 清掉,你的原 commit 都还在。

---

## 8. 实操:一次完整的 pull --rebase 流程

假设你在 feature 分支上开发,远端 main 有人推了新提交,你想同步:

```bash
# 1. 切到 feature 分支
git checkout feature

# 2. fetch 远端最新(只下载,不合并)
git fetch origin

# 3. 查看远端 main 比本地多了什么
git log --oneline HEAD..origin/main

# 4. rebase 你的 feature 到 origin/main 上
git rebase origin/main
# 等价于:git pull --rebase origin main

# 5. 如果有冲突:
#    - 打开冲突文件,删 <<<<<< / ======= / >>>>>>> 标记
#    - git add <冲突文件>
#    - git rebase --continue
#    - 重复直到所有冲突解决

# 6. 推到远端(因为 commit hash 全变了,需要 force-push)
git push --force-with-lease origin feature
```

`--force-with-lease` 比 `--force` 安全——它会先检查远端是不是只有你预期的版本,防止覆盖别人的提交。这是 rebase 之后 push 的标配。

---

## 9. 一张图看清所有 pull 模式

```
git pull = git fetch + <integration>

   <integration> 选择:
   │
   ├── 默认(无 --rebase / --no-rebase):
   │      → git merge(创建 merge commit,如果分叉的话)
   │
   ├── --rebase(= true):
   │      → git rebase(线性历史,本地 commit hash 全变)
   │
   ├── --rebase=merges:
   │      → git rebase --rebase-merges(保留本地 merge commit 拓扑)
   │
   ├── --rebase=interactive:
   │      → git rebase -i(可手动 squash / reword / drop)
   │
   ├── --no-rebase(= false):
   │      → 显式声明走 merge,等同默认
   │
   └── --squash:
          → git merge --squash(把远端所有改动压成 1 个本地 commit)
```

**配置层面**(影响 `git pull` 不带参数时的行为):

```
pull.rebase = true        → 默认 rebase
pull.rebase = merges      → 默认 rebase --rebase-merges
pull.rebase = false       → 默认 merge(显式声明)
pull.rebase = interactive → 默认 rebase -i
pull.ff = only            → 只接受 fast-forward,否则拒绝 pull
pull.ff = false           → 即使能 fast-forward 也强制 merge commit
```

---

## 10. 跟"merge 模式"的取舍对照表

| 维度 | pull --merge(默认) | pull --rebase |
|------|---------------------|----------------|
| 历史形状 | 分叉 + merge commit,非线 | 干净一条直线 |
| 本地 commit hash | **不变** | **全变**(重新生成) |
| push 后续动作 | 直接 `git push` 即可 | 必须 `git push --force-with-lease` |
| 多端协作分享 | 安全(任何人都能基于稳定 hash) | 危险(force-push 会影响别人) |
| 调试 `git bisect` | 噪音多(merge commit 干扰) | 干净(线性历史) |
| 团队约定 | 适合"保留真实合并痕迹" | 适合"线性清洁癖" |
| 适合的分支 | 共享的 `main`/`develop` | 私人的 feature 分支(未推送前) |

**业界主流约定**(不是唯一真理):

- 个人 feature 分支:**rebase**(干净)
- 共享 main 分支:**永远只 merge,绝不 rebase**(稳定)
- 提交 PR 之前:**先 pull --rebase 一次** 让分支最新,再 push

---

## 11. 常见误区

| 误区 | 实际情况 |
|------|----------|
| "pull --rebase 等于 git pull + git rebase 分两步" | 对的,但等价于 `git fetch && git rebase`,所以你本地如果有未提交改动需要 `--autostash` |
| "rebase 会丢 commit" | 不会。只要没 `git gc`,reflog 里都还在;`git reset --hard ORIG_HEAD` 就能找回 |
| "rebase 后再 push 一定安全" | 必须 `--force-with-lease`,不能 `--force`;且 **不能** 在共享分支上 rebase 后 force-push |
| "pull --rebase=interactive 跟 git rebase -i 一样" | 对的,但 pull 时通常没必要——你刚 fetch 完还没动 commit,interactive 用在 fetch 之后整理本地多次 WIP 更合适 |
| "新版本 Git 默认就是 pull --rebase" | **不对**。`git pull` 默认还是 merge,除非你显式设了 `pull.rebase=true` 或加了 `--rebase` 标志[1] |
| "rebase 跟 merge 完全等价,选哪个都行" | 错。**生成的 commit hash 不同**——这意味着 SHA 引用(release notes、issue 链接、CI 缓存、镜像备份)全都受影响 |

---

## 12. 一句话原则

> **没推上去的 commit → 放心 rebase。已经推上去的、别人可能用过的 commit → 永远只 merge,不 rebase。**

记住:`git pull --rebase` 不是"git pull 的升级版",而是 **"fetch + rebase"的便捷别名**,它会**重写你本地未推送 commit 的 hash**。理解这个,你就掌握了 rebase 90% 的应用场景。

## Sources

[1] https://git-scm.com/docs/git-pull — git pull 官方文档
[2] https://git-scm.com/docs/git-rebase — git rebase 官方文档
[3] https://git-scm.com/book/en/v2/Git-Branching-Rebasing — Pro Git §3.6 - Rebasing
