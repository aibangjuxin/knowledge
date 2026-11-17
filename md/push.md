我来看看你的脚本，然后帮你集成 Ollama 来生成智能 commit message。好的，我来为你分析需求并生成集成 Ollama 的新脚本。

核心改动是：在 `git commit` 前，调用本地 Ollama API，基于 `git diff --cached` 的内容生成智能 commit message，替代原来的 `chore: sync ...` 默认格式。用户通过 `-m` 传入的消息则作为 prompt 的补充上下文。

先画一下新增的流程：现在生成脚本：语法检查通过，脚本已就绪。以下是关键改动说明：

**新增的核心逻辑（`git add` 之后、`git commit` 之前）**

| 步骤                           | 说明                                                                                                                      |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `ollama_is_available()`        | `curl` 探测 `OLLAMA_HOST/api/tags`，超时 5s，不影响主流程                                                                 |
| `ollama_generate_commit_msg()` | 把 `git diff --cached` 截断到 3000 字符，拼入 prompt，POST 到 `/api/generate`，用 `python3` 解析 JSON 的 `.response` 字段 |
| `-m` 参数的角色变化            | 不再是最终 message，而是作为 **"User hint"** 注入 prompt，给 AI 额外上下文                                                |
| 降级策略                       | Ollama 不可达 / 返回空 → 自动回退到 `chore: sync BRANCH DATE`（如有 `-m` 则带上 hint）                                    |

**环境变量控制**

```bash
# 使用远程 Ollama
OLLAMA_HOST=http://192.168.1.10:11434 ./push-replace.sh

# 切换模型
ENHANCE_MODEL=llama3.2:3b ./push-replace.sh -m "refactor auth module"
```

**依赖**：`python3`（用于 JSON 转义和解析，通常系统自带）。若无 `python3`，脚本会回退到 `sed` 做基础转义，不会崩溃。

- ![push](./ollama_commit_flow.svg)