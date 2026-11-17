下面是一份 **macOS（Homebrew 安装）下 /opt/homebrew/bin/rg（ripgrep）使用手册**，内容可直接作为 .md 文档使用。

---

# **ripgrep（rg）使用手册（macOS）**

## **1. 工具简介**

rg（ripgrep）是一个 **高性能的递归搜索工具**，用于在文件中搜索文本内容。

**核心特点：**

- 默认递归搜索当前目录
- 自动忽略 .gitignore / .ignore 中的规则
- 支持正则表达式（Rust regex）
- 搜索速度远快于 grep
- 默认只搜索文本文件（跳过 binary）

Homebrew 安装路径通常为：

```
/opt/homebrew/bin/rg
```

---

## **2. 基本语法**

```
rg [OPTIONS] PATTERN [PATH ...]
```

| **参数** | **说明**                 |
| -------- | ------------------------ |
| PATTERN  | 要搜索的字符串或正则     |
| PATH     | 搜索路径（默认当前目录） |

---

## **3. 最基础用法**

### **3.1 在当前目录递归搜索字符串**

```
rg "error"
```

等价于：

```
rg "error" .
```

---

### **3.2 在指定目录搜索**

```
rg "timeout" ./src
```

---

### **3.3 搜索多个路径**

```
rg "OOM" ./src ./config
```

---

## **4. 常用高频参数（必会）**

### **4.1 忽略大小写**

```
rg -i "timeout"
```

---

### **4.2 显示行号**

```
rg -n "Exception"
```

---

### **4.3 只显示匹配内容（不显示整行）**

```
rg -o "http[s]?://[^ ]+"
```

---

### **4.4 显示匹配前后行（上下文）**

```
rg -C 3 "NullPointerException"
```

等价于：

```
rg --context 3 "NullPointerException"
```

---

### **4.5 仅搜索指定文件类型**

```
rg "timeout" -t yaml
rg "timeout" -t java
```

常见类型：

| **类型** | **说明** |
| -------- | -------- |
| -t java  | Java     |
| -t go    | Go       |
| -t yaml  | YAML     |
| -t json  | JSON     |
| -t sh    | Shell    |
| -t md    | Markdown |

查看支持的类型：

```
rg --type-list
```

---

### **4.6 按文件扩展名搜索**

```
rg "image:" -g "*.yaml"
```

排除某类文件：

```
rg "debug" -g "!*.log"
```

---

## **5. 忽略规则与强制搜索**

### **5.1 忽略** 

### **.gitignore**

### **（默认行为）**

```
rg "password"
```

---

### **5.2 强制忽略** 

### **.gitignore**

```
rg -uu "password"
```

| **参数** | **说明**                    |
| -------- | --------------------------- |
| -u       | 搜索被 gitignore 忽略的文件 |
| -uu      | 包括 binary 文件            |

---

### **5.3 手动排除目录**

```
rg "token" --glob "!node_modules/*"
```

---

## **6. 正则表达式搜索（高级）**

### **6.1 基础正则**

```
rg "v[0-9]+\.[0-9]+\.[0-9]+"
```

---

### **6.2 多条件 OR**

```
rg "OOMKilled|OutOfMemoryError"
```

---

### **6.3 只匹配完整单词**

```
rg -w "timeout"
```

---

### **6.4 使用 PCRE（支持 lookaround）**

```
rg -P "(?<=X-Request-ID: ).*"
```

---

## **7. 只列出匹配的文件名**

```
rg -l "deprecated"
```

反向：**列出不匹配的文件**

```
rg -L "deprecated"
```

---

## **8. 与其他命令配合（实战）**

### **8.1 搜索后统计文件数量**

```
rg -l "timeout" | wc -l
```

---

### **8.2 搜索并分页查看**

```
rg "Exception" | less -R
```

---

### **8.3 搜索 Kubernetes YAML 里的 image**

```
rg "image:" -g "*.yaml"
```

---

### **8.4 查找 GKE / K8S 中的 memory limit**

```
rg "memory:" -g "*.yaml"
```

---

## **9. 性能与调试参数**

### **9.1 显示搜索耗时（调试用）**

```
rg "error" --stats
```

---

### **9.2 限制最大文件大小**

```
rg "token" --max-filesize 1M
```

---

## **10. 常见对比（rg vs grep）**

| **功能**       | **rg**   | **grep** |
| -------------- | -------- | -------- |
| 递归搜索       | 默认     | -r       |
| gitignore 支持 | 默认     | ❌       |
| 速度           | 极快     | 慢       |
| 正则           | 默认     | 可选     |
| binary 处理    | 自动跳过 | 需手动   |

---

## **11. 查看内置帮助**

```
rg --help
```

查看完整 man 手册：

```
man rg
```

---

## **12. 推荐使用场景（结合你当前工作）**

- 排查 **GKE YAML / Helm**
- 搜索 **Java OOM / GC / JVM 参数**
- 排查 **Kong / Nginx 配置**
- 批量查找 **timeout / retry / memory limit**
- CI Pipeline 日志分析

---

## **13. 一句话总结**

> **rg = 现代版 grep + git-aware + 正则友好 + 极速**

如果你需要，我可以：

- 给你 **K8S / GKE / Java 专用 rg 搜索模板**
- 或者帮你写一个 **rg + awk + sed 的排障脚本组合**
