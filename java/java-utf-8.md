这是一个非常常见的问题，尤其是在处理 CSV 文件时，**文件编码格式（特别是 UTF-8 BOM 和无 BOM 的 UTF-8）**往往会影响 Java 程序对文件头部的解析行为，导致看似“隐藏的 Bug”。

  

  

  

  

✅ 回答关键问题

  

  

  

CSV 是否支持 UTF-8 BOM？

  

  

技术上可以包含 BOM，但绝大多数 CSV 解析库（包括 OpenCSV、Apache Commons CSV 等）默认不处理 BOM。

  

- BOM (Byte Order Mark) 是 UTF-8 编码的一种可选前缀（3 个字节：0xEF 0xBB 0xBF），其目的是标识文本编码。
- 但 CSV 文件格式规范中并没有明确要求或推荐使用 BOM。
- 很多 Java CSV 库在读取 UTF-8 BOM 文件时，会把 BOM 当作内容处理，导致第一列字段前缀多了不可见字符 \uFEFF，从而出现字段不匹配等问题。

  

  

  

  

  

🧭 如何判断和定位这个问题？

  

  

  

1. 查看文件是否有 BOM

  

  

可以用 Linux xxd 或 file 命令查看：

xxd your_file.csv | head

输出前 3 个字节为：

00000000: efbb bf...       # 表示是 UTF-8 BOM

或者用 file：

file your_file.csv

输出：

your_file.csv: UTF-8 Unicode (with BOM) text

  

  

  

  

2. Java 中如何打印 BOM 问题？

  

  

如果你怀疑是 BOM，可以临时添加代码读取文件前几个字节确认：

try (InputStream is = new FileInputStream("your_file.csv")) {

    for (int i = 0; i < 3; i++) {

        int b = is.read();

        System.out.printf("Byte %d: 0x%02X%n", i, b);

    }

}

如果打印出 0xEF 0xBB 0xBF 就是带 BOM 的 UTF-8。

  

  

  

  

🛠️ 解决方案

  

  

  

✅ 方案一：

读取时移除 BOM

  

  

用 Java 标准 IO 去手动处理 BOM：

BufferedReader reader = new BufferedReader(

    new InputStreamReader(new FileInputStream("your_file.csv"), StandardCharsets.UTF_8)

);

  

// 手动去掉 BOM

reader.mark(1);

if (reader.read() != 0xFEFF) {

    reader.reset(); // 没有 BOM，回退

}

  

✅ 方案二：

使用支持 BOM 的 CSV 库

  

  

例如 Apache Commons CSV + BOMInputStream：

InputStream inputStream = new FileInputStream("your_file.csv");

BOMInputStream bomIn = new BOMInputStream(inputStream);

  

Reader reader = new InputStreamReader(bomIn, StandardCharsets.UTF_8);

CSVParser parser = CSVFormat.DEFAULT.withFirstRecordAsHeader().parse(reader);

Apache Commons IO 提供了 BOMInputStream，能自动剥离 BOM。

  

Maven 依赖：

<dependency>

    <groupId>commons-io</groupId>

    <artifactId>commons-io</artifactId>

    <version>2.11.0</version>

</dependency>

  

  

  

  

🧪 示例 CSV Bug 说明

  

  

  

有 BOM 的 CSV 示例（前面看不到的 

\uFEFF

）：

  

\uFEFFname,age

Alice,30

Bob,25

  

解析后出现错误：

  

record.get("name") // 报错：No such header: "name"，实际是 "\uFEFFname"

  

  

  

  

🧩 总结

  

|   |   |
|---|---|
|项目|UTF-8 BOM 支持|
|CSV 标准|不推荐使用 BOM|
|Java 默认读取|不自动去除 BOM|
|解析库表现|会当成数据字段|
|推荐处理方式|使用 BOMInputStream 或手动跳过 BOM|

  

  

  

如果你能确认你的文件来源（比如来自 Windows Excel 保存），很可能默认就是 UTF-8 BOM 格式，可以在 ETL 阶段转换为无 BOM，再输入到系统中。

  

一个 shell 脚本来检测并去除 CSV 文件的 BOM？


下面是一个简单的 Shell 脚本，用于：

  

1. 检测某个 CSV 文件是否为 UTF-8 BOM 编码；
2. 如果是，则去除 BOM 并保存为新的文件（或覆盖原文件）。

  

  

  

  

  

🛠️ Shell 脚本：检测并去除 CSV 文件中的 UTF-8 BOM

  

#!/bin/bash

  

# 使用方式: ./remove_bom.sh input.csv [output.csv]

INPUT_FILE="$1"

OUTPUT_FILE="${2:-$1}"  # 如果没有提供 output 参数，则覆盖原文件

  

if [[ ! -f "$INPUT_FILE" ]]; then

  echo "❌ 输入文件不存在: $INPUT_FILE"

  exit 1

fi

  

# 检查是否有 BOM (前3个字节是 EF BB BF)

BOM_HEX=$(xxd -p -l 3 "$INPUT_FILE")

  

if [[ "$BOM_HEX" == "efbbbf" ]]; then

  echo "✅ 检测到 UTF-8 BOM，开始移除..."

  tail -c +4 "$INPUT_FILE" > "$OUTPUT_FILE"

  echo "🎉 BOM 已移除，输出文件: $OUTPUT_FILE"

else

  echo "ℹ️ 没有检测到 BOM，无需处理: $INPUT_FILE"

fi

  

  

  

  

✅ 使用方法

  

  

  

方式 1：覆盖原文件

  

./remove_bom.sh your_file.csv

  

方式 2：输出到新文件

  

./remove_bom.sh your_file.csv cleaned_file.csv

  

  

  

  

📦 依赖说明

  

  

- 使用了 xxd 检查 BOM。
- 使用 tail -c +4 跳过前 3 个字节。

  

  

这些工具在大多数 Linux/macOS 系统上默认可用。如果你在某些容器环境中没有 xxd，可以用 hexdump -C 代替。

  

  

  

如果你想批量处理一个目录下的所有 CSV 文件，我也可以提供批量版本。是否需要？