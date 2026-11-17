---
https://antigravity.google/docs/skills

### How the agent uses skills
Skills follow a progressive disclosure pattern:

1.  **Discovery:** When a conversation starts, the agent sees a list of available skills with their names and descriptions
2.  **Activation:** If a skill looks relevant to your task, the agent reads the full `SKILL.md` content
3.  **Execution:** The agent follows the skill's instructions while working on your task

You don't need to explicitly tell the agent to use a skill—it decides based on context. However, you can mention a skill by name if you want to ensure it's used.

---

您可以通过以下几种方式来“调用”或触发这个 GCP-expert（GCP 平台专家）技能：

### 方法 1：直接指定角色
最简单直接的方法是告诉我要作为那个角色来回答。

**示例：** "请作为 GCP 平台专家，帮我解答关于 Shared VPC 和 VPC Peering 的使用场景区别。"

### 方法 2：引用文件设定
您也可以像这样引用该定义文件，要求我遵循其中的规则（比如它的输出格式、Mermaid 图表要求等）。

**示例：** "参考 `@[.agent/skills/gcp/SKILL.md]` 的专家设定，帮我设计一个 GKE 多集群的高可用架构，并画出架构图。"

### 方法 3：根据问题领域自动触发（隐式）
因为该 Skill 定义了它是 Linux 和 GCP 的专家，如果您的问题非常专业且属于该领域，我通常会自动采用相关的知识库。但为了确保我严格遵守文档里的格式规范（例如那个严谨的“问题分析 -> 解决方案 -> 代码 -> 可视化 -> 注意事项”流程），建议使用前两种显式调用的方式。

### 给您的一个固定调用模板 (Fixed Example)
您可以直接复制下面这段话作为 Prompt：

```
情景：您想要咨询一个 GKE 网络问题

参考 @[.agent/skills/gcp/SKILL.md] 中定义的 GCP-expert 角色：

背景：我正在设计一个生产环境的 GKE 集群，需要暴露多个 gRPC 服务。
问题：应该选择哪种负载均衡器（L4 还是 L7），以及如何配置 Ingress 或 Gateway API 来实现最佳性能？
要求：请严格按照 Skill 里的 Workflow 步骤（分析 -> 方案 -> 代码 -> 图表 -> 注意事项）进行回答。
```

https://codelabs.developers.google.com/getting-started-with-antigravity-skills?hl=zh-cn#4

---

在 Antigravity 中创建 Skill 遵循特定的目录结构和文件格式。这种标准化可确保 Skills 的可移植性，并确保智能体能够可靠地解析和执行它们。该设计有意简单，依赖于广泛理解的格式（如 Markdown 和 YAML），降低了希望扩展其 IDE 功能的开发者的入门门槛。

### 目录结构
Skills 可以在两个范围内定义，允许进行项目特定和用户特定的自定义：

*   **工作区范围：** 位于 `<workspace-root>/.agent/skills/` 中。这些 Skills 仅在特定项目中可用。这非常适合项目特定的脚本，例如部署到特定环境、该应用的数据管理，或为专有框架生成样板代码。
*   **全局范围：** 位于 `~/.gemini/antigravity/skills/` 中。这些 Skills 在用户机器上的所有项目中都可用。这适用于通用实用程序，例如“格式化 JSON”“生成 UUID”“查看代码样式”或与个人效率工具集成。

```bash
➜  antigravity pwd
➜  antigravity cp -r /Users/lex/git/knowledge/skills/* ./
/Users/lex/.gemini/antigravity
```

**GitHub**
https://github.com › guanyang › blob
·
Translate this page

在对话框中输入 `@[skill-name]` 或 `/skill-name` 即可调用，

```bash
npx skills list
```
Need to install the following packages:
skills@1.5.1
Ok to proceed? (y) y

### Project Skills

GCP-expert ~/git/knowledge/skills/GCP-expert
  Agents: OpenClaw
architectrue ~/git/knowledge/skills/architectrue
  Agents: OpenClaw
englishmail ~/git/knowledge/skills/englishmail
  Agents: OpenClaw
extract-requirements-target ~/git/knowledge/skills/extract-requirements-target
  Agents: OpenClaw
files-to-requirements ~/git/knowledge/skills/files-to-requirements
  Agents: OpenClaw
gcp ~/git/knowledge/skills/gcp
  Agents: OpenClaw
maitreya ~/git/knowledge/skills/maitreya
  Agents: OpenClaw
ob ~/git/knowledge/skills/ob
  Agents: OpenClaw

npm notice
npm notice New minor version of npm available! 11.5.2 -> 11.12.1
npm notice Changelog: https://github.com/npm/cli/releases/tag/v11.12.1
npm notice To update run: npm install -g npm@11.12.1
npm notice

https://github.com/vercel-labs/skills/blob/main/skills/find-skills/SKILL.md

**是的，网络上有类似 `npx skills list` 的工具来管理和发现更多 Skills**。这类工具主要用于AI Agent（如OpenCode、Claude）的技能包管理，支持搜索、安装、更新。 [cloud.tencent](https://cloud.tencent.com/developer/article/2656427)

## 核心管理命令
使用 `npx skills` 就能找到和管理全网 Skills：

```bash
# 列出本地已安装技能
npx skills list    # 或 npx skills ls

# 搜索技能（关键词）
npx skills find "前端"     # 搜前端相关
npx skills find opencode   # 搜OpenCode专属

# 安装单个/多个技能
npx skills add vercel-labs/agent-skills --skill frontend-design
npx skills add baoyu-skills --all

# 检查更新
npx skills check
npx skills update

# 移除技能
npx skills rm blog-post-writer
```

## 热门Skills仓库推荐
| 仓库                       | 技能数量 | 特色场景               |
| :------------------------- | :------- | :---------------------- |
| `vercel-labs/agent-skills` | 50+      | React/Vue全栈开发      |
| `baoyu-skills`             | 18个     | 公众号、小红书内容创作 |
| `anthropics/skills`        | 官方     | Skill创建模板          |
| `awesome-claude-skills`    | 200+     | 社区精选全集           |

## OpenCode专属发现方式
```bash
# 1. 先装技能管理器
npx skills add anthropics/skills -g

# 2. 搜索OpenCode适配技能
npx skills find --agent opencode

# 3. 一键安装推荐套装
npx skills add baoyu-skills vercel-labs/agent-skills --agent opencode
```

## 进阶技巧
**创建自定义Skill**：
```bash
npx skills init my-linux-ops  # 生成模板
# 编辑 SKILL.md 定义Linux运维流程
npx skills add ./my-linux-ops -g
```

**在OpenCode中使用**：
启动 `opencode` 后，它会自动发现 `.opencode/skills/` 目录下的所有技能，无需额外配置。 [opencode](https://opencode.ai/docs/zh-cn/skills/)

**最全资源**：GitHub搜 `awesome-agent-skills` 或访问 `libukai/awesome-agent-skills`，里面有分类收录几百个实战Skills。 [github](https://github.com/libukai/awesome-agent-skills)

这样你就能用 `npx skills find` 一键发现全网最新技能，比手动找仓库快10倍！

```bash
➜  knowledge git:(main) npx skills find "flow"

███████╗██╗  ██╗██╗██╗     ██╗     ███████╗
██╔════╝██║ ██╔╝██║██║     ██║     ██╔════╝
███████╗█████╔╝ ██║██║     ██║     ███████╗
╚════██║██╔═██╗ ██║██║     ██║     ╚════██║
███████║██║  ██╗██║███████╗███████╗███████║
╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚══════╝

Install with npx skills add <owner/repo@skill>

larksuite/cli@lark-workflow-meeting-summary 62K installs
└ https://skills.sh/larksuite/cli/lark-workflow-meeting-summary

larksuite/cli@lark-workflow-standup-report 62K installs
└ https://skills.sh/larksuite/cli/lark-workflow-standup-report

expo/skills@expo-cicd-workflows 19.4K installs
└ https://skills.sh/expo/skills/expo-cicd-workflows

googleworkspace/cli@gws-workflow 10.8K installs
└ https://skills.sh/googleworkspace/cli/gws-workflow

googleworkspace/cli@gws-workflow-email-to-task 10.5K installs
└ https://skills.sh/googleworkspace/cli/gws-workflow-email-to-task

googleworkspace/cli@gws-workflow-meeting-prep 10.3K installs
└ https://skills.sh/googleworkspace/cli/gws-workflow-meeting-prep
---
