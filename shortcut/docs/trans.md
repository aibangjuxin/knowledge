- prompt
```txt
As an English grammar and spelling expert.

Task:
1. Please fix any grammar, spelling, punctuation, or sentence structure issues in the following English input.
2. Output only the corrected English version first (no explanation).
3. Then provide a fluent Chinese translation of the corrected version.

Input:
"""
{selection}
"""
```
---
- js
````js
function escapeShellArg(str) {
  return "'" + str.replace(/'/g, "'\\''") + "'";
}

const removeBackticks = (str) => {
  // remove leading backticks
  str = str.replace(/^(```\n|```)/g, "");

  // remove tailing backticks and everything after
  const index = str.lastIndexOf("```");
  if (index !== -1) {
    return str.slice(0, index);
  }
  return str;
};

function run(input, parameters) {
  const apiEndpoint = "http://localhost:8080/v1/completions";
  const prompt = `<|im_start|>system
As an English grammar and spelling expert.
Task:
1. Please fix any grammar, spelling, punctuation, or sentence structure issues in the following English input.
2. Output only the corrected English version first (no explanation).
3. Then provide a fluent Chinese translation of the corrected version.
Format: 
Corrected: [corrected English text]
Chinese: [Chinese translation]<|im_end|>
<|im_start|>user
Text=\`\`\`I has been working on this project for two week and it's almost finish.\`\`\`<|im_end|>
<|im_start|>assistant
Corrected: I have been working on this project for two weeks and it's almost finished.
Chinese: 我已经在这个项目上工作了两周，快要完成了。<|im_end|>
<|im_start|>user
Text=\`\`\`${input}\`\`\`<|im_end|>
<|im_start|>assistant
`;

  const requestData = {
    prompt: prompt,
    temperature: 0.1,
    stop: ["<|im_end|"],
  };

  const curlCommand = `curl ${apiEndpoint} -X POST -v -H 'Content-Type: application/json' -d ${escapeShellArg(
    JSON.stringify(requestData)
  )}`;

  // Instantiate the Application object
  const app = Application.currentApplication();
  app.includeStandardAdditions = true;

  const apiResultJSON = app.doShellScript(curlCommand);

  // Parse the JSON response and extract the result
  const apiResultObject = JSON.parse(apiResultJSON);
  const result = apiResultObject.choices[0].text;

  return result.trim();
}
````

这个 JavaScript 代码是一个文本翻译和校正工具，主要功能如下：

核心功能
文本翻译和校正：将输入的文本（可能包含中英文混合）翻译或校正为标准英文
API 调用：通过本地 API 服务（localhost:8080）进行文本处理
主要组件
辅助函数：

escapeShellArg() - 转义 shell 命令参数，防止特殊字符导致命令执行问题
removeBackticks() - 移除文本中的 markdown 代码块标记（```）
主函数 run()：

构建提示词：使用 ChatML 格式创建系统提示，包含示例对话
API 请求：向本地 completions 端点发送 POST 请求
Shell 执行：通过 macOS 的 AppleScript 执行 curl 命令
结果处理：解析 JSON 响应并提取翻译结果
使用场景
从示例可以看出，这个工具特别适合处理：

中英文混合的文本
语法错误的英文句子
需要润色的英文表达
比如示例中将 "neither 经理或员工 has been informed" 校正为 "Neither the manager nor the employees have been informed"。

这看起来像是为 macOS Shortcuts 应用设计的自动化脚本，用于快速翻译和校正文本。
