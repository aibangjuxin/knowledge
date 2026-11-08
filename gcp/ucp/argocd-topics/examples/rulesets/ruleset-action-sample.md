# Ruleset × Action 全套实验手册（`ruleset-action-sample`）

> **一句话目标**：用**可复现的实验**证明一件事 —— 「GitHub Ruleset」和「GitHub Actions」是靠一个字符串咬合的，
> 而且这个咬合**真的会在合并那一刻拦住人**。
>
> **配套文档**：
> - 原理与配置拆解：[`06-dev-branch-guard-x-cr-prefix-action.md`](./06-dev-branch-guard-x-cr-prefix-action.md)（理论篇）
> - 自动化版本：[`verify-cr-prefix.sh`](../../verify-cr-prefix.sh)（`--poc` 一键跑完实验 A/B）
>
> **本文所有"实测输出"都是真的跑出来的**（`aibangjuxin/knowledge`，2026-11-08），
> 不是"预期"，也不是文档抄的。命令可以原样复制执行。

---

## 目录

| 实验 | 验证什么 | 结果 |
|---|---|---|
| [0](#实验-0-·-准备受管分支) | 让一个分支真正进入 ruleset 的射程 | `feature/cr-prefix-verify` 已受管 |
| [A](#实验-a-·-不合规-→-必须被拦住) | 不合规 → check 变红 → 合并被拒 | ✅ 拦住 |
| [B](#实验-b-·-合规-→-必须放行) | 合规 → check 变绿 → 真的合进去 | ✅ 放行 |
| [C](#实验-c-·-标题与-commit-的-cr-号不一致) | 规则到底管多严 | ⚠️ 仍然放行（当前规则的边界） |
| [D](#实验-d-·-base-有-workflow、head-没有-→-照样跑) | workflow 到底从哪来 | ✅ 照样跑（merge ref 规则） |
| [E](#实验-e-·-base-和-head-都没有-workflow-→-永久卡死) | 复现 PR #219 的卡死 | ✅ 复现 |
| [F](#实验-f-·-删分支--强推) | `deletion` / `non_fast_forward` 两条规则 | ✅ 都被拒 |
| [G](#实验-g-·-三种合并方式) | `allowed_merge_methods` | squash/merge 行，rebase 拒 |
| [H](#实验-h-·-pr-到-main-→-check-照跑但没人消费) | ★ `ref_name` 管的是**目标**分支 | 🔥 不合规也合并成功了 |
| [I](#实验-i-·-本地-hook-与-ci-规则的耦合) | 为什么规则用"包含"而不是"必须开头" | ✅ 复现 |

---

## 0. 前置条件

| 项 | 值 | 检查命令 |
|---|---|---|
| 仓库 | `aibangjuxin/knowledge` | — |
| 本地路径 | `/Users/lex/git/knowledge` | — |
| Ruleset | `dev-branch-guard`（id `26786098`），`target: branch`，`enforcement: active` | `gh api repos/aibangjuxin/knowledge/rulesets/26786098` |
| 受管分支 | `feature/**` `git-apps/**` `fix/**` `codex/**` | 同上 `conditions.ref_name.include` |
| 校验器 | `.github/workflows/cr-prefix.yml`，check 名 = `cr-prefix` | `git ls-tree main .github/workflows/` |
| 规则 | `CH[0-9]+`（**包含**语义，不要求开头） | 看 workflow 的 `PREFIX_REGEX` |
| gh CLI | v2.103.2，已登录 | `gh auth status` |

### ★ 一次性把分页器关掉（否则每条 `gh` 命令都要按 `q`）

```bash
export GH_PAGER=cat
export PAGER=cat
```

> `gh` 在 stdout 是终端时会自动用 `less` 分页，输出停在 `(END)` 等按键。
> 这就是"要不停按 ESC"的根因。

### 基线快照（实验前先存一份，便于事后对比）

```bash
cd /Users/lex/git/knowledge
REPO=aibangjuxin/knowledge

# 规则集现状
gh api repos/$REPO/rulesets --jq '.[] | "\(.id)\t\(.name)\t\(.enforcement)"'

# 每个分支上实际生效的规则（★ 权威接口）
for b in main feature/cr-prefix-verify git-apps/lex codex/add-cr-prefix-ci; do
  printf '%-32s ' "$b"
  gh api "repos/$REPO/rules/branches/$b" --jq '[.[]|.type]|if length==0 then "(none)" else join(",") end'
done
```

**实测基线**：

```
26786098  dev-branch-guard    active
26786097  main-branch-guard   disabled

main                            (none)
feature/cr-prefix-verify       deletion,non_fast_forward,pull_request,required_status_checks
git-apps/lex                   deletion,non_fast_forward,pull_request,required_status_checks
codex/add-cr-prefix-ci         deletion,non_fast_forward,pull_request,required_status_checks
```

> ★ 注意 `main` 是 `(none)` —— `main-branch-guard`（07）还是 disabled。
> 这就是实验 H 要对比的东西。

---

## 实验 0 · 准备受管分支

**你要做的第一件事已经有了**：

```bash
cd /Users/lex/git/knowledge
git checkout -b feature/cr-prefix-verify      # ← 你已经建好了
```

推上去，并确认它**进入 ruleset 射程**：

```bash
git push -u origin feature/cr-prefix-verify

gh api repos/aibangjuxin/knowledge/rules/branches/feature/cr-prefix-verify \
  --jq '[.[]|"\(.ruleset_id):\(.type)"]|join(", ")'
```

**实测输出**：

```
26786098:deletion, 26786098:non_fast_forward, 26786098:pull_request, 26786098:required_status_checks
```

✅ **4 条规则全在** → 这个分支现在是受管分支。

### ★★ 这里是最容易搞错的一步

```
   lab/xxx  ──PR──►  feature/cr-prefix-verify
   （源分支）        （目标分支 = 受管）
                       ↑ ruleset 的 ref_name 匹配的是【目标分支】
```

> **ruleset 的 `ref_name` 管的是 PR 的目标分支（base），不是你的开发分支。**
> 所以"我从 `feature/xxx` 提 PR"**不**受管；"我往 `feature/xxx` 合 PR"才受管。
> → 本手册的所有实验，**都把 PR 的 base 设成 `feature/cr-prefix-verify`**。

### 还要确认 workflow 在位

```bash
git ls-tree feature/cr-prefix-verify .github/workflows/
# 期望：100644 blob ... .github/workflows/cr-prefix.yml
```

---

## 实验 A · 不合规 → 必须被拦住

**🎯 目的**：证明"规则不是摆设"，不合规的 PR **合不进去**，**管理员也合不进去**。

### 步骤

```bash
cd /Users/lex/git/knowledge
git checkout feature/cr-prefix-verify
git checkout -b lab/a-nocr

echo "lab A" > lab-a.md && git add lab-a.md
git commit -m "lab: 这个 commit 故意不带 CH 号"     # ← 没有 CH + 数字
git push -u origin lab/a-nocr

gh pr create --base feature/cr-prefix-verify \
             --head lab/a-nocr \
             --title "lab: 这个 PR 标题故意不带 CH 号" \
             --body "实验 A：不合规应被拦住"
```

> ★ commit message 用 `lab: ...` 这种 Conventional Commits 格式是**必须的** ——
> 本地有 `commit-msg` hook 会拦（见 [实验 I](#实验-i-·-本地-hook-与-ci-规则的耦合)）。

### 观察

```bash
# ① check 结论
gh pr checks <PR号> --repo aibangjuxin/knowledge

# ② 合并状态
gh pr view <PR号> --repo aibangjuxin/knowledge --json mergeStateStatus -q .mergeStateStatus

# ③ 强行合并（模拟"管理员手滑点了合并"）
gh api --method PUT repos/aibangjuxin/knowledge/pulls/<PR号>/merge \
   --input - <<< '{"merge_method":"squash"}'
```

### 实测输出

```
cr-prefix   failure   ← 红叉
mergeStateStatus: BLOCKED
```

强行合并被拒：

```json
{
  "message": "Repository rule violations found\n\nRequired status check \"cr-prefix\" is failing.\n\n",
  "status": "405"
}
```

✅ **判定**：`failure` + `BLOCKED` + API 合并 405 = 门禁真实生效，
**且 `bypass_actors: []` 意味着连仓库 owner 都绕不过去**。

> ★ 这就是"Ruleset + Action"和"靠人自觉"的分水岭：
> 服务器在**合并那一刻**重新求值，不看 PR 作者说了什么。

---

## 实验 B · 合规 → 必须放行

**🎯 目的**：证明门禁**没有误伤**（否则就是"把所有人都锁死"的坏规则）。

### 步骤

```bash
git checkout feature/cr-prefix-verify
git checkout -b lab/b-withcr

echo "lab B" > lab-b.md && git add lab-b.md
git commit -m "feat(lab): add CH013456 marker"        # ← 含 CH + 数字
git push -u origin lab/b-withcr

gh pr create --base feature/cr-prefix-verify \
             --head lab/b-withcr \
             --title "CH013456 lab: 合规的 PR 标题" \
             --body "实验 B：合规应放行"
```

### 观察

```bash
gh pr checks <PR号> --repo aibangjuxin/knowledge
gh pr view <PR号> --repo aibangjuxin/knowledge --json mergeStateStatus -q .mergeStateStatus
```

### 实测输出

```
cr-prefix   success   ← 绿勾
mergeStateStatus: CLEAN
```

✅ **判定**：绿勾 + `CLEAN` → 门禁只拦不合规的。

### 再真的合进去

```bash
gh pr merge <PR号> --repo aibangjuxin/knowledge --squash
git fetch origin
git log --oneline origin/feature/cr-prefix-verify -1
```

**实测**：`feature/cr-prefix-verify` 上多了一条 squash 提交。

> ★ **这一步会改动受管分支**。做完实验 B 之后要恢复原状，见[清理](#清理)。
> （受管分支不能强推、不能删 → 清理需要走[逃生通道](#逃生通道（受管分支的唯一正确恢复方式）)。）

---
下面部分是我模拟的一个完整的正常过程
```bash
➜  knowledge git:(main) git checkout -b feature/cr-prefix-verify
Switched to a new branch 'feature/cr-prefix-verify'
➜  knowledge git:(feature/cr-prefix-verify) pwd
/Users/lex/git/knowledge
➜  knowledge git:(feature/cr-prefix-verify) ✗ git add .
➜  knowledge git:(feature/cr-prefix-verify) ✗ git commit -m "feat(lab): commit 里写的是 CH013456"
[feature/cr-prefix-verify 2ee959d0] feat(lab): commit 里写的是 CH013456
 4 files changed, 1732 insertions(+)
 create mode 100644 gcp/ucp/argocd-topics/examples/rulesets/06-dev-branch-guard-x-cr-prefix-action.md
 create mode 100644 gcp/ucp/argocd-topics/examples/rulesets/ruleset-action-sample.md
 create mode 100755 gcp/ucp/argocd-topics/verify-cr-prefix.sh
➜  knowledge git:(feature/cr-prefix-verify) git push
Enumerating objects: 18, done.
Counting objects: 100% (18/18), done.
Delta compression using up to 10 threads
Compressing objects: 100% (11/11), done.
Writing objects: 100% (11/11), 29.94 KiB | 9.98 MiB/s, done.
Total 11 (delta 7), reused 0 (delta 0), pack-reused 0 (from 0)
remote: Resolving deltas: 100% (7/7), completed with 7 local objects.
remote: error: GH013: Repository rule violations found for refs/heads/feature/cr-prefix-verify.
remote: Review all repository rules at https://github.com/aibangjuxin/knowledge/rules?ref=refs%2Fheads%2Ffeature%2Fcr-prefix-verify
remote:
remote: - Changes must be made through a pull request. ==>  ← 真正的原因（pull_request 规则）
remote:
remote: - Required status check "cr-prefix" is expected. " ← 因为没有 PR，就没有 check run
remote:
To github.com:aibangjuxin/knowledge.git
 ! [remote rejected]   feature/cr-prefix-verify -> feature/cr-prefix-verify (push declined due to repository rule violations)
error: failed to push some refs to 'github.com:aibangjuxin/knowledge.git'

 原因找到了 —— pull_request 那条规则：受管分支不允许直接 push，任何改动必须走 PR。GitHub 把两条违规
 都列了出来：


   remote: - Changes must be made through a pull request.      ← 真正的原因
   remote: - Required status check "cr-prefix" is expected.     ← 因为没有 PR，就没有 check

那么我按照下面这个计划来进行一次推送
 Plan:
 - git checkout -b docs/cr-prefix-lab (from current HEAD, carrying the commit) ==> 等于是新建一个 branch
 - git push -u origin docs/cr-prefix-lab ==> 推送成功（docs/cr-prefix-lab 不受管 → 直接推）。
 - `gh pr create --base feature/cr-prefix-verify --head docs/cr-prefix-lab --title "CH013456 docs: add ruleset x action lab docs" --body "把 ruleset × action 的实验手册与脚本通过 PR 合入受管分支（受管分支不允许直接 push）"`
    - wait for cr-prefix check → should be success
 - merge (squash or merge)
 - then git checkout feature/cr-prefix-verify && git reset --hard origin/feature/cr-prefix-verify
   (to sync local) — careful: after merge, the remote protected branch has the squashed commit;
   local feature/cr-prefix-verify has 2ee959d0. Reset local to origin.
 - delete docs/cr-prefix-lab (local + remo


➜  knowledge git:(feature/cr-prefix-verify) git checkout -b docs/cr-prefix-lab
Switched to a new branch 'docs/cr-prefix-lab'
➜  knowledge git:(docs/cr-prefix-lab) git push -u origin docs/cr-prefix-lab ==> 推送到一个没有保护的分支 Push to the non-protected branch worked immediately. Now open the PR. 推送成功（docs/cr-prefix-lab 不受管 → 直接推）。
Enumerating objects: 15, done.
Counting objects: 100% (15/15), done.
Delta compression using up to 10 threads
Compressing objects: 100% (8/8), done.
Writing objects: 100% (8/8), 1.52 KiB | 1.52 MiB/s, done.
Total 8 (delta 7), reused 0 (delta 0), pack-reused 0 (from 0)
remote: Resolving deltas: 100% (7/7), completed with 7 local objects.
remote:
remote: Create a pull request for 'docs/cr-prefix-lab' on GitHub by visiting:
remote:      https://github.com/aibangjuxin/knowledge/pull/new/docs/cr-prefix-lab
remote:
remote: GitHub found 60 vulnerabilities on aibangjuxin/knowledge's default branch (8 critical, 20 high, 32 moderate). To find out more, visit:
remote:      https://github.com/aibangjuxin/knowledge/security/dependabot
remote:
To github.com:aibangjuxin/knowledge.git
 * [new branch]        docs/cr-prefix-lab -> docs/cr-prefix-lab
branch 'docs/cr-prefix-lab' set up to track 'origin/docs/cr-prefix-lab'.

➜  knowledge git:(docs/cr-prefix-lab) gh pr create --base feature/cr-prefix-verify --head docs/cr-prefix-lab --title "CH013456 docs: add ruleset x action lab docs" --body "把 ruleset × action 的实验手册与脚本通过 PR 合入受管分支（受管分支不允许直接 push）" ==> 现在开 PR 走受管分支

Creating pull request for docs/cr-prefix-lab into feature/cr-prefix-verify in aibangjuxin/knowledge

https://github.com/aibangjuxin/knowledge/pull/233


HEAD_SHA=$(gh api repos/aibangjuxin/knowledge/pulls/233 --jq .head.sha)

gh api "repos/aibangjuxin/knowledge/commits/${HEAD_SHA}/check-runs" \
  --jq '[.check_runs[] | select(.name == "cr-prefix")] | last | "\(.status) \(.conclusion)"'

 


➜  knowledge git:(docs/cr-prefix-lab) gh pr view 233 --repo aibangjuxin/knowledge --json mergeStateStatus -q .mergeStateStatus
➜  knowledge git:(docs/cr-prefix-lab) gh pr view 233 --repo aibangjuxin/knowledg

CH013456 docs: add ruleset x action lab docs aibangjuxin/knowledge#233
Open • aibangjuxin wants to merge 1 commit into feature/cr-prefix-verify from docs/cr-prefix-lab • about 2 minutes ago
+34 -0 • ✓ Checks passing


  把 ruleset × action 的实验手册与脚本通过 PR 合入受管分支（受管分支不允许直接 push）


View this pull request on GitHub: https://github.com/aibangjuxin/knowledge/pull/233
我最终登录页面也能看到这个，而且也有这个对应的cr-prefix 也能看起来这个结果是成功的

aibangjuxin
wants to merge 1 commit into
feature/cr-prefix-verify ==> 这个其实就是我受保护的这个 feature/cr-prefix-verify (base = protected branch).
from
docs/cr-prefix-lab


这个时候再切回到这个受保护的 branch
➜  knowledge git:(docs/cr-prefix-lab) git checkout feature/cr-prefix-verify
Switched to branch 'feature/cr-prefix-verify'
Your branch is ahead of 'origin/feature/cr-prefix-verify' by 1 commit.
  (use "git push" to publish your local commits)

 「受控分支上是不是没法 pull？」 → 可以，完全可以。 pull 是纯本地操作，ruleset 只管"往远端推"，管不到拉取。

 「我理解我的远端已经 OK 了，本地拉取不受影响？」 → 对，但有个前提：本地不能有"远端没有"的 commit。这次正是
 因为你本地多了一个已被 squash 掉的重复 commit，两边历史分叉，pull 才被迫造 merge commit，才撞上 hook。


➜  knowledge git:(feature/cr-prefix-verify) git pull
remote: Enumerating objects: 1, done.
remote: Counting objects: 100% (1/1), done.
remote: Total 1 (delta 0), reused 0 (delta 0), pack-reused 0 (from 0)
Unpacking objects: 100% (1/1), 903 bytes | 451.00 KiB/s, done.
From github.com:aibangjuxin/knowledge
   d40edeae..2a1f261a  feature/cr-prefix-verify -> origin/feature/cr-prefix-verify

❌ 提交被拦截：主题行不符合 Conventional Commits。

   当前主题行：Merge branch 'feature/cr-prefix-verify' of github.com:aibangjuxin/knowledge into feature/cr-prefix-verify

   规则：<type>(<scope>): <祈使句摘要>
   示例：
     docs(gcp): add GKE metadata exploration doc
     fix(auth): handle expired token refresh
     chore(vscode): add todo-plus extension vsix

   如需跳过此检查：git commit --no-verify
Not committing merge; use 'git commit' to complete the merge

### 方案 A（推荐）：本地直接对齐远端

 理由：已验证 git diff 275892cc 2a1f261a 为空 → 你本地那个 commit 的内容已经在远端了（squash 版），本地这份
 是冗余的。

 ```bash
   git merge --abort
   git fetch origin
   git reset --hard origin/feature/cr-prefix-verify
 ```



➜  knowledge git:(feature/cr-prefix-verify) git fetch origin
➜  knowledge git:(feature/cr-prefix-verify) git reset --hard origin/feature/cr-prefix-verify
HEAD is now at 2a1f261a feat(lab): commit 里写的是 CH013456 (#233)
➜  knowledge git:(feature/cr-prefix-verify) git pull
Already up to date.


治本：怎么让它不再发生

 ① 不要在受管分支上直接 commit，所有改动都在侧分支（docs/xxx）做。==> 其实这个就是我的原始初衷，我定义这个对应的/Users/lex/git/gcp/ucp/argocd-topics/examples/rulesets/06-repo-feature-conventions.json /Users/lex/git/knowledge/.github/workflows/cr-prefix.yml 规则就是不想让用户随意的在这个上面commit ==> 当然，我在这里测试的时候用了下面四个这样的规则，其实真正对我的生产环境来说，我可能仅仅是不让到main 或者dev 对于个人用户来说，你随便，但是你必须通过 PR 的形式默置到 dev Branch ==> 然后dev ==> main
```yaml
      "include": [
        "refs/heads/feature/**",
        "refs/heads/git-apps/**",
        "refs/heads/fix/**",
        "refs/heads/codex/**"
      ],
```
 

 ② PR 合并后，用 fast-forward 同步受管分支：

 ```bash
   git checkout feature/cr-prefix-verify
   git fetch origin
   git pull --ff-only        # 只允许 FF
 ```

 │ 关键：只要本地没有"远端没有"的 commit，pull 本来就是 fast-forward，根本不会造 merge commit，hook也就没机
 │ 会触发。 这次之所以出事，是因为你本地多了一个已被 squash 掉的重复 commit。


```


## 实验 C · 标题与 commit 的 CR 号不一致

**🎯 目的**：搞清楚当前规则**到底管多严**（POC 阶段要知道边界在哪）。

### 步骤

```bash
git checkout feature/cr-prefix-verify
git checkout -b lab/c-mixed

echo "lab C" > lab-c.md && git add lab-c.md
git commit -m "feat(lab): commit 里写的是 CH013456"
git push -u origin lab/c-mixed

gh pr create --base feature/cr-prefix-verify --head lab/c-mixed \
             --title "CH999999 lab: 标题里写的是另一个号" --body "实验 C"
```

### 实测输出

```
cr-prefix   success
mergeStateStatus: CLEAN
```

✅ **判定**：**依然放行**。当前规则只做"**是否包含** `CH` + 数字"的判断，
**不校验标题和 commit 里的号是不是同一个**。

> ★ 想收紧的话有三个旋钮（见 `06-dev-branch-guard-x-cr-prefix-action.md` §8.4）：
> ① 锁死位数（`CH[0-9]{6}`）② 锁死词边界 ③ 增加"标题与 commit 号一致"的比对。
> POC 阶段**不用管**，但要知道现在没有这三条。

---

## 实验 D · base 有 workflow、head 没有 → 照样跑

**🎯 目的**：搞清楚 `pull_request` 事件的 workflow 到底从哪来
（这一条纠正了"workflow 必须写在 head 分支"的直觉）。

### 步骤

```bash
# 从一个【没有】workflow 的老分支切出来当源分支
git checkout origin/codex/add-cr-prefix-ci
git checkout -b lab/d-nowf

echo "lab D" > lab-d.md && git add lab-d.md
git commit -m "lab: no cr prefix"
git push -u origin lab/d-nowf

# 但 PR 的 base 选 feature/cr-prefix-verify（它【有】workflow）
gh pr create --base feature/cr-prefix-verify --head lab/d-nowf \
             --title "lab: head 没 workflow，但 base 有" --body "实验 D"
```

### 实测输出

```
cr-prefix   failure      ← ★ 照样跑了！
mergeStateStatus: BLOCKED
```

✅ **判定**：**head 没有 workflow，照样跑**。

> ★★ **正确结论**：
> `pull_request` 事件用的 workflow 文件取自 **PR 的 merge ref（base ∪ head 合成结果）**，
> 所以 **base 有、或者 head 有，任意一边有就会跑**。
> 三组对照（全部实测）：

| base 有 wf？ | head 有 wf？ | check 跑了？ |
|---|---|---|
| ❌ | ✅ | ✅ 跑（PR #220） |
| ✅ | ❌ | ✅ 跑（**实验 D**） |
| ❌ | ❌ | ❌ **不跑**（PR #219 → 卡死） |

---

## 实验 E · base 和 head 都没有 workflow → 永久卡死

**🎯 目的**：复现 PR #219 的"卡死"，这是门禁上线后最常见的事故。

### 步骤

```bash
# base 和 head 都用没有 workflow 的分支
git checkout origin/codex/add-cr-prefix-ci
git checkout -b lab/e-nowf

echo "lab E" > lab-e.md && git add lab-e.md
git commit -m "lab: no cr prefix"
git push -u origin lab/e-nowf

gh pr create --base codex/add-cr-prefix-ci --head lab/e-nowf \
             --title "lab: base 和 head 都没有 workflow" --body "实验 E"
```

### 观察

```bash
gh pr checks <PR号> --repo aibangjuxin/knowledge        # 永远等不到 cr-prefix
gh pr view <PR号> --repo aibangjuxin/knowledge --json mergeStateStatus -q .mergeStateStatus
gh api repos/aibangjuxin/knowledge/commits/<head_sha>/check-runs \
  --jq '.check_runs[].name'                             # 看不到 cr-prefix
```

### 实测（对齐历史 PR #219）

```
PR #219: base=codex/add-cr-prefix-ci  head=feat/CH013456-pfb-gcp-v0.1.0
         check-runs → 只有 github-advanced-security，没有 cr-prefix
         结果：2026-11-08 05:25:41 被关闭，未合并
```

✅ **判定**：**不是"规则太严"，是"检查从来没跑过"**。

### 怎么救

```bash
# 把 workflow 补到任意一边（base 或 head 都行）
git checkout main -- .github/workflows/cr-prefix.yml
git add .github/workflows/cr-prefix.yml
git commit -m "ci(lab): add cr-prefix workflow so the check can run"
git push
# → 立刻恢复：check 会跑，PR 状态变成可合/不可合
```

### ★ 排查口诀

```bash
gh api repos/O/R/commits/<head_sha>/check-runs --jq '.check_runs[].name'
# 看不到 cr-prefix → 就是这个问题（不是 PR 标题写错了）
git ls-tree origin/<base分支> .github/workflows/     # 再确认 base 侧
```

---

## 实验 F · 删分支 / 强推

**🎯 目的**：验证 `deletion` 和 `non_fast_forward` 两条规则。

### F-1 强推

```bash
git push --force origin HEAD~1:feature/cr-prefix-verify
```

**实测输出**：

```
 ! [remote rejected] feature/cr-prefix-verify (push declined due to repository rule violations)
error: failed to push some refs to 'https://github.com/aibangjuxin/knowledge.git'
```

✅ 被拒（`non_fast_forward`）。

### F-2 删分支（两条路径都被拒）

```bash
git push origin --delete feature/cr-prefix-verify
gh api --method DELETE repos/aibangjuxin/knowledge/git/refs/heads/feature/cr-prefix-verify
```

**实测输出**：

```
 ! [remote rejected] feature/cr-prefix-verify (push declined due to repository rule violations)
```

```json
{ "message": "Repository rule violations found\n\nCannot delete this branch\n\n", "status": "422" }
```

✅ 两条路径都被拒（`deletion`）。

> ★★ **注意这个副作用**：**受管分支删不掉**。
> 所以实验 B 把提交合进 `feature/cr-prefix-verify` 之后，恢复原状必须走[逃生通道](#逃生通道（受管分支的唯一正确恢复方式）)。

---

## 实验 G · 三种合并方式

**🎯 目的**：验证 `allowed_merge_methods: ["squash", "merge"]`。

| 方式 | 结果 | 实测最终 commit message |
|---|---|---|
| `squash` | ✅ 允许 | `feat(lab): add CH013456 marker for squash (#228)` |
| `merge` | ✅ 允许 | `Merge pull request #229 from ...` 空行 `CH013456 lab: merge commit test` |
| `rebase` | ❌ 拒绝 | — |

**rebase 被拒的实测报文**：

```json
{ "message": "Rebase merges are not allowed on this repository.", "status": "405" }
```

### ★ 一个值得记住的细节

squash 后的最终 commit message 用的是哪个？

- **PR 只有一个 commit** → 用**那个 commit 的 subject**（实测：`feat(lab): ... (#228)`）
- **PR 有多个 commit** → 用 **PR 标题**（GitHub 默认）

> 这就是为什么 workflow **既要查 PR 标题、又要查每个 commit**：
> 单 commit 时标题用不上，多 commit 时标题才是最终 message 的来源。

---

## 实验 H · PR 到 main → check 照跑但没人消费

**🎯 目的**：★ 验证最容易搞错的那条语义 —— **ruleset 管的是 PR 的目标分支**。

### 步骤

```bash
# 同样的不合规内容，但 PR 的 base 换成 main
git checkout feature/cr-prefix-verify
git checkout -b lab/h-tomain

echo "lab H" > lab-h.md && git add lab-h.md
git commit -m "lab: 同样不合规，但目标是 main"
git push -u origin lab/h-tomain

gh pr create --base main --head lab/h-tomain \
             --title "lab: 同样不合规，但目标是 main" --body "实验 H"
```

### 观察

```bash
gh pr checks <PR号> --repo aibangjuxin/knowledge                        # check 照样跑！
gh pr view <PR号> --repo aibangjuxin/knowledge --json mergeStateStatus -q .mergeStateStatus
gh api repos/aibangjuxin/knowledge/branches/main \
  --jq '[.[]|.type]|if length==0 then "(none)" else join(",") end'
```

### 实测输出

```
PR#231  base=main  check=failure
mergeStateStatus = UNSTABLE          ← ★ 不是 BLOCKED！
main 上生效规则 = (none)
--- 尝试合并 ---
  合并成功 -> 2d172967659008b94e863b2a2bc7f274baae0380
```

✅ **判定**：**同一个 check、同样的红叉，在 main 上不仅没拦住，PR 还被成功合并了。**

```
   lab/xxx  ──PR──►  feature/cr-prefix-verify   → BLOCKED，合不进去
   lab/xxx  ──PR──►  main                      → UNSTABLE，照样合进去
   （check 都是 failure，内容完全一样）
```

> ★★★ 这是本手册最想让你记住的一课：
> **"CI 有没有跑" ≠ "门禁有没有生效"。**
> 后者取决于 **ruleset 的 `ref_name` 有没有命中 PR 的目标分支**。
>
> - `main` 上 `mergeStateStatus = UNSTABLE` 而不是 `BLOCKED`
>   —— `UNSTABLE` 的含义是"有 check 没通过，但**没有任何规则要求它必须通过**"。
> - 同理，`main` 上 `rules/branches/main = (none)` → 连 `deletion` / `non_fast_forward` 也没有。
>
> ★ **实验 H 会真的往 main 合进一个提交**（因为 main 完全没保护）。
> 做完一定要回滚：
> ```bash
> git fetch origin
> git push --force origin cff9994c:main      # ★ main 没受管，所以能直接强推
> ```
> （⚠️ 强推后那个 PR 在网页上仍然显示 `merged=true`，但 main 已经回到原样 —— 合并提交变成孤儿。）

---

## 实验 I · 本地 hook 与 CI 规则的耦合

**🎯 目的**：解释为什么 workflow 的规则是"**包含** `CH[0-9]+`"而不是"**必须以 CH 开头**"。

### 步骤

```bash
cd /Users/lex/git/knowledge
git checkout feature/cr-prefix-verify
git checkout -b lab/i-hook

echo "x" > lab-i.md && git add lab-i.md
git commit -m "CH013456 lab: 想让 CR 号开头"      # ← 会被本地 hook 拦！
```

### 实测输出

```
❌ 提交被拦截：主题行不符合 Conventional Commits。

   当前主题行：CH013456 lab: 想让 CR 号开头

   规则：<type>(<scope>): <祈使句摘要>
   示例：
     docs(gcp): add GKE metadata exploration doc
```

### 判定

| 写法 | 本地 hook | CI `cr-prefix` | 结论 |
|---|---|---|---|
| `CH013456 lab: xxx` | ❌ **拦截** | （到不了 CI） | **两头都过不去** |
| `feat(lab): add CH013456 marker` | ✅ 放行 | ✅ 通过 | ★ **唯一可行的合规写法** |
| `lab: no cr prefix` | ✅ 放行 | ❌ **拦截** | ← 这才是服务端门禁该拦的 |

✅ **判定**：这正是 `cr-prefix.yml` 头注释里写的那句话 ——
*"It is CONTAINS, not 'must start with', on purpose: the repo also has a local Conventional Commits hook."*

> ★ 这也解释了**为什么实验 A 的 commit 要写成 `lab: ...` 而不是 `CH...` 开头的**：
> 只有"本地能提交出去但服务端拦下来"的那一类，才是服务端门禁该管的东西。

---

## 验收清单

跑完全部实验后，逐条打勾：

| # | 断言 | 怎么验 | 实测 |
|---|---|---|---|
| 1 | `feature/cr-prefix-verify` 受管 | `rules/branches/feature/cr-prefix-verify` | ✅ 4 条规则 |
| 2 | 不合规 → check 红 | 实验 A | ✅ `failure` |
| 3 | 不合规 → 合并状态 BLOCKED | 实验 A | ✅ `BLOCKED` |
| 4 | 不合规 → 管理员也合不了 | `PUT /pulls/N/merge` | ✅ HTTP 405 |
| 5 | 合规 → check 绿 | 实验 B | ✅ `success` |
| 6 | 合规 → CLEAN 且能合 | 实验 B | ✅ `CLEAN` |
| 7 | 标题/commit 号不一致仍放行 | 实验 C | ✅ `success`（当前规则的边界） |
| 8 | head 无 workflow 但 base 有 → 照样跑 | 实验 D | ✅ `failure` |
| 9 | base/head 都无 → 永久卡死 | 实验 E | ✅ 复现 #219 |
| 10 | 强推受管分支被拒 | 实验 F-1 | ✅ `push declined` |
| 11 | 删受管分支被拒（git + API） | 实验 F-2 | ✅ 422 `Cannot delete this branch` |
| 12 | squash / merge 允许 | 实验 G | ✅ 允许 |
| 13 | rebase 拒绝 | 实验 G | ✅ 405 `Rebase merges are not allowed` |
| 14 | PR 到 main 不被拦（且真的合进去了） | 实验 H | ✅ `UNSTABLE` + 合并成功 |
| 15 | 本地 hook 拦 CH 开头 | 实验 I | ✅ 被拦 |

---

## 清理

```bash
cd /Users/lex/git/knowledge

# ① 关掉所有实验 PR
for pr in $(gh api repos/aibangjuxin/knowledge/pulls --jq '.[]|select(.head.ref|startswith("lab/"))|.number'); do
  gh api --method PATCH repos/aibangjuxin/knowledge/pulls/$pr --input - >/dev/null <<< '{"state":"closed"}'
done

# ② 删实验分支（lab/* 不受管，可以直接删）
for b in $(gh api repos/aibangjuxin/knowledge/branches --jq '.[].name' | grep '^lab/'); do
  gh api --method DELETE "repos/$REPO/git/refs/heads/$b" >/dev/null
done

# ③ 恢复受管分支到实验前的状态（★ 受管分支不能强推 → 见下面的逃生通道）
git fetch origin
git log --oneline origin/feature/cr-prefix-verify -1
```

### 逃生通道（受管分支的唯一正确恢复方式）

> 受管分支：**不能强推、不能删**。
> 要恢复它，只能**临时把 ruleset 降级**。

```bash
REPO=aibangjuxin/knowledge
RS=26786098

# ① 取回完整 JSON（★ PUT 是全量替换，只传一个字段会把规则全清空）
gh api repos/$REPO/rulesets/$RS > /tmp/rs.json

# ② 临时 disabled
jq '.enforcement="disabled"' /tmp/rs.json \
  | gh api --method PUT repos/$REPO/rulesets/$RS --input -

# ③ 现在可以强推 / 删分支了
git push --force origin cff9994c:feature/cr-prefix-verify
# git push origin --delete feature/cr-prefix-verify

# ④ ★ 恢复 active（规则一条都不会少）
jq '.enforcement="active"' /tmp/rs.json \
  | gh api --method PUT repos/$REPO/rulesets/$RS --input -

# ⑤ 确认复原
gh api repos/$REPO/rulesets/$RS --jq '"\(.enforcement) rules=\([.rules[].type]|join(","))"'
```

**实测**：

```
  → 已临时 disabled
  → 分支已删除 ✅
  → 已恢复 active
  → 当前 enforcement=active, rules=deletion,non_fast_forward,pull_request,required_status_checks
```

> ★ 这条逃生通道本身就是一次"Ruleset 运维演练"：
> **改 ruleset 永远是"取回完整 JSON → 改一个字段 → 整体 PUT 回去"**，
> 绝不能 `gh api -X PUT ... -f enforcement=active`（那会把所有规则清空）。

---

## 故障排查表

| 症状 | 根因 | 解法 |
|---|---|---|
| PR 上看不到 `cr-prefix` 这个 check | **base 和 head 都没有 workflow** | 把 workflow 补到任意一边（实验 E） |
| check 一直是 "Expected — Waiting for status to be reported" | 同上（check 从没跑过） | 同上 |
| check 一直 pending | Actions 没额度 / workflow 报错 | 看 Actions 页签的运行日志 |
| 合并框灰掉，但看不出哪条不满足 | required check 名字对不上 | `gh api repos/O/R/rulesets/<id> --jq '.rules[]|select(.type=="required_status_checks")'` |
| 全员卡死、所有 PR 都合不了 | `context` 拼错了一个字符 | 核对 job 的 `name` == ruleset 的 `context` |
| 本地 `git commit` 被拦 | 本地 `commit-msg` hook（Conventional Commits） | `git commit --no-verify`（仅调试）或按 `<type>(<scope>): ...` 写 |
| 本地过了、CI 红了 | 两边正则不一致 | 统一 `PREFIX_REGEX` |
| `git push` 报奇怪的错、`git log` 里没有自己的 commit | metadata 规则（本仓库没启用）→ 不适用 | — |
| 强推 / 删分支被拒 | `deletion` / `non_fast_forward` 正常生效 | 要改就走逃生通道 |
| 删不掉受管分支 | 同上 | 逃生通道（先 disabled） |
| `gh` 命令要不停按 `q`/ESC | `gh` 自动用了 `less` 分页 | `export GH_PAGER=cat` |

---

## 命令速查

```bash
export GH_PAGER=cat                      # ★ 关掉分页器
REPO=aibangjuxin/knowledge

# 规则集
gh api repos/$REPO/rulesets --jq '.[]|"\(.id)\t\(.name)\t\(.enforcement)"'
gh api repos/$REPO/rulesets/26786098 --jq '.rules[]|.type'

# ★ 分支上实际生效的规则（权威）
gh api repos/$REPO/rules/branches/<分支> --jq '[.[]|.type]|join(", ")'

# PR 状态
gh pr view <N> --repo $REPO --json mergeStateStatus -q .mergeStateStatus
gh pr checks <N> --repo $REPO

# check 跑了没
gh api repos/$REPO/commits/<head_sha>/check-runs --jq '.check_runs[]|"\(.name)\t\(.conclusion)"'

# 强行合并（看门禁拦不拦）
gh api --method PUT repos/$REPO/pulls/<N>/merge --input - <<< '{"merge_method":"squash"}'

# 切 enforcement（★ 必须带完整 payload）
gh api repos/$REPO/rulesets/<id> > /tmp/rs.json
jq '.enforcement="active"' /tmp/rs.json | gh api --method PUT repos/$REPO/rulesets/<id> --input -
```

---

## 附录 A · 自动化版本

上面 A/B 两个实验（不合规被拦 / 合规放行）可以用一条命令跑完：

```bash
cd /Users/lex/git/gcp/ucp/argocd-topics
./verify-cr-prefix.sh --poc
```

**实测输出**：

```
── 用例 NEG：fail
   PR #222  cr-prefix 结论 : failure      merge 状态 : BLOCKED
   ✓ 不合规 → check 变红     ✓ PR 被挡住
── 用例 POS：pass
   PR #223  cr-prefix 结论 : success       merge 状态 : CLEAN
   ✓ 合规 → check 变绿
```

它会自动创建分支 / PR、轮询 check、打印结论、**然后清理干净**（关 PR + 删分支）。

## 附录 B · 相关文件

| 文件 | 作用 |
|---|---|
| [`06-repo-feature-conventions.json`](./06-repo-feature-conventions.json) | 门禁的"锁"：分支保护 + 绑定 `cr-prefix` |
| [`07-commit-message-cr-prefix-protected.json`](./07-commit-message-cr-prefix-protected.json) | 主分支版本（**当前 disabled** → 实验 H 的根因） |
| [`workflows/cr-prefix-check.yaml`](./workflows/cr-prefix-check.yaml) | 校验器仓库模板（严格版 `^CR[0-9]{6}`） |
| `/Users/lex/git/knowledge/.github/workflows/cr-prefix.yml` | ★ 你实际在用的校验器（宽松版 `CH[0-9]+`） |
| [`06-dev-branch-guard-x-cr-prefix-action.md`](./06-dev-branch-guard-x-cr-prefix-action.md) | 理论篇：逐段拆解 + 线上实测 + 5 个缺口 |
| [`verify-cr-prefix.sh`](../../verify-cr-prefix.sh) | 自查 + `--poc` 自动化对抗 |
| [`git-apps/15-commit-message-cr-prefix.md`](../../git-apps/15-commit-message-cr-prefix.md) | 完整方案（两条路线、squash 坑、计划限制） |
| [`git-apps/16-ruleset-install-runbook.md`](../../git-apps/16-ruleset-install-runbook.md) | 安装 / 联调 / 验收 / 回滚 Runbook |
