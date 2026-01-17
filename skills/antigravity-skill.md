https://antigravity.google/docs/skills

How the agent uses skills
Skills follow a progressive disclosure pattern:

Discovery: When a conversation starts, the agent sees a list of available skills with their names and descriptions
Activation: If a skill looks relevant to your task, the agent reads the full SKILL.md content
Execution: The agent follows the skill's instructions while working on your task
You don't need to explicitly tell the agent to use a skill—it decides based on context. However, you can mention a skill by name if you want to ensure it's used.


您可以通过以下几种方式来“调用”或触发这个 GCP-expert（GCP 平台专家）技能：

方法 1：直接指定角色
最简单直接的方法是告诉我要作为那个角色来回答。

示例： "请作为 GCP 平台专家，帮我解答关于 Shared VPC 和 VPC Peering 的使用场景区别。"

方法 2：引用文件设定
您也可以像这样引用该定义文件，要求我遵循其中的规则（比如它的输出格式、Mermaid 图表要求等）。

示例： "参考 @[.agent/skills/gcp/SKILL.md] 的专家设定，帮我设计一个 GKE 多集群的高可用架构，并画出架构图。"

方法 3：根据问题领域自动触发（隐式）
因为该 Skill 定义了它是 Linux 和 GCP 的专家，如果您的问题非常专业且属于该领域，我通常会自动采用相关的知识库。但为了确保我严格遵守文档里的 格式规范（例如那个严谨的“问题分析 -> 解决方案 -> 代码 -> 可视化 -> 注意事项”流程），建议使用前两种显式调用的方式。

给您的一个固定调用模板 (Fixed Example)
您可以直接复制下面这段话作为 Prompt：

情景：您想要咨询一个 GKE 网络问题

参考 @[.agent/skills/gcp/SKILL.md] 中定义的 GCP-expert 角色：

背景：我正在设计一个生产环境的 GKE 集群，需要暴露多个 gRPC 服务。 问题：应该选择哪种负载均衡器（L4 还是 L7），以及如何配置 Ingress 或 Gateway API 来实现最佳性能？ 要求：请严格按照 Skill 里的 Workflow 步骤（分析 -> 方案 -> 代码 -> 图表 -> 注意事项）进行回答。

