# AI 时代，为什么我更倾向于用 HTML 而不是 Markdown 输出

> 作者：Thariq（@trq212），Claude Code 团队
> 原文：Using Claude Code: The Unreasonable Effectiveness of HTML
> 编译：Cocoon AI

---

## Markdown 的黄金时代过去了

Markdown 确实是 AI 与人类沟通的王者格式：简单、便携、有一定的富文本能力、人类易编辑。Claude 甚至在 ASCII 画图这件事上展现出了惊人的天赋。

但随着 AI 能力越来越强，我逐渐感觉到 **Markdown 已经成了一种限制**：

- 超过一百行的 Markdown 文件，我读不下去
- 我想要更丰富的信息呈现：颜色、图表、交互
- 我希望分享起来足够方便
- 而且坦白说，这些文件我几乎不再自己编辑了——它们更多是作为"规格说明"、"参考文档"、"头脑风暴产物"存在。当我真的需要修改时，我也是让 Claude 来改，这反而让 Markdown 最大的优势（易于人类编辑）变得不那么重要了

所以我开始**更倾向于用 HTML 作为输出格式**，而不是 Markdown。

---

## 为什么是 HTML？

### 信息密度

HTML 能传递的信息量远高于 Markdown。它当然可以做简单的文档结构（标题、格式），但还能表达更多：

- **表格**呈现结构化数据
- **CSS** 精确描述设计数据
- **SVG** 绘制插图和图表
- **\<script\> 标签**内置代码片段
- **JavaScript + CSS** 实现交互
- **SVG + HTML** 描述工作流
- **Canvas** 表达空间数据
- **\<image\> 标签**直接嵌入图片

可以说，Claude 能读取的任何信息，HTML 几乎都能高效地表达出来。这让它成为 AI 向人类传递深度信息的绝佳方式。

Markdown 做不到的时候，Claude 只能退而求其次——用 ASCII 凑合，或者像我截图里看到的这样，用 Unicode 字符来"估算"颜色：

> 附图：Claude Code 尝试在 Markdown 里用 Unicode 字符表现颜色

### 视觉清晰度与可读性

Claude 能完成越来越复杂的工作，意味着它写出来的规格文档和计划也越来越长。

实际情况是：**超过 100 行的 Markdown 文件，我基本不会真的去读**，更别说让团队里的其他人去读了。

HTML 则不同——它可以分区块、加深色主题、配图表，导航和阅读体验完全不在一个层次。

---

## HTML 的另一个优势：所见即分享

HTML 文件天然适合分享。一个 `.html` 文件扔给任何人，浏览器直接打开就是最终效果。

而 Markdown 的分享体验依赖工具链：你在 VS Code 看是这个样子，发到 GitHub 又是另一个样子，粘贴到飞书/Notion/微信公众号又各不相同。

HTML 的呈现是**确定性的**。

---

## 在 Claude Code 团队内部，这已经是主流做法

我开始在内部越来越多地看到 HTML 作为输出的选择，而不仅仅是 Markdown。如果你想看具体例子，可以访问 [thariqs.github.io/html-effectiveness](https://thariqs.github.io/html-effectiveness)，里面有很多实际案例。

---

## 我的判断

不是说 Markdown 不好——它仍然是最适合人类协作编辑的格式之一。

但如果场景是：**AI 向我交付信息，我只需要理解和查看**，那么 HTML 是更好的选择。它让 AI 的输出更易读、更专业、也更易于分享。

未来，随着 AI 生成内容越来越多，这个趋势只会加速。

---

**原文链接**：https://x.com/trq212/status/2052809885763747935
