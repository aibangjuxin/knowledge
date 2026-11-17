在 Ubuntu 下比较 JSON 文件或普通文件，除了 `diff` 和 `sdiff`，还有很多更强大或更适合特定场景的工具，尤其是针对 JSON 这种结构化数据，专用工具能提供更清晰的对比结果。以下是一些常用工具分类推荐：

### **一、通用文件比较工具（支持各种文本文件）**

1. **meld**
   - 图形化工具，支持文件夹和文件对比，界面直观，可直接编辑并合并差异，适合可视化操作。
   - 安装：`sudo apt install meld`
   - 使用：`meld file1.json file2.json`

2. **vimdiff**
   - Vim 编辑器的差异对比模式，支持分屏显示、语法高亮，适合习惯命令行的用户。
   - 使用：`vimdiff file1.json file2.json`（在 Vim 中可通过 `:diffget`/`:diffput` 合并差异）

3. **colordiff**
   - `diff` 的增强版，给差异内容添加颜色标记，输出更易读。
   - 安装：`sudo apt install colordiff`
   - 使用：`colordiff file1.json file2.json`

4. **diffoscope**
   - 支持对比多种格式文件（包括文本、二进制、压缩包等），会递归解析文件内容（如解压压缩包后对比内部文件）。
   - 安装：`sudo apt install diffoscope`
   - 使用：`diffoscope file1.json file2.json`

### **二、JSON 专用对比工具（结构化对比）**

由于 JSON 有严格的格式和层级结构，通用工具可能因缩进、键顺序等无关差异干扰结果，专用工具会忽略格式差异，只对比内容逻辑。

1. **jq + diff**
   - `jq` 是 JSON 处理工具，可先标准化 JSON（排序键、统一缩进），再用 `diff` 对比。
   - 安装：`sudo apt install jq`
   - 使用：
     ```bash
     # 标准化并对比（忽略键顺序和缩进差异）
     jq --sort-keys . file1.json > file1_formatted.json
     jq --sort-keys . file2.json > file2_formatted.json
     diff file1_formatted.json file2_formatted.json
     ```

2. **json-diff**
   - 直接对比两个 JSON 文件的内容差异，输出结构化的差异描述（如新增、删除、修改的键值）。
   - 安装：需先安装 Node.js，再用 npm 安装：
     ```bash
     sudo apt install nodejs npm
     npm install -g json-diff
     ```
   - 使用：`json-diff file1.json file2.json`

3. **jsondiffpatch**
   - 另一个 JSON 差异工具，支持生成差异补丁（可用于后续合并），也可通过命令行输出对比结果。
   - 安装：`npm install -g jsondiffpatch`
   - 使用：`jsondiffpatch file1.json file2.json`

4. **gron + diff**
   - `gron` 将 JSON 转换为可 grep 的单行键值对格式，再用 `diff` 对比，适合快速定位键值变化。
   - 安装：`sudo apt install gron`
   - 使用：
     ```bash
     gron file1.json > file1.gron
     gron file2.json > file2.gron
     diff file1.gron file2.gron
     ```

### **三、其他实用工具**

- **kompare**：KDE 桌面环境的图形化对比工具，支持文件和文件夹对比，功能类似 meld。  
  安装：`sudo apt install kompare`
- **dwdiff**：基于单词级别的差异对比，适合文本内容（非结构化）的精细对比。  
  安装：`sudo apt install dwdiff`

### **总结推荐**

- **快速命令行对比 JSON**：`jq + colordiff`（标准化后带颜色输出）。
- **图形化操作**：`meld`（简单直观，支持 JSON 语法高亮）。
- **结构化 JSON 差异**：`json-diff`（直接输出键值级别的变化）。

根据需求选择即可，结构化工具对 JSON 的对比效果通常优于通用文本对比工具。
