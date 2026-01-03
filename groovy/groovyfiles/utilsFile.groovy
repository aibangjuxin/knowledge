
utilsFile 是一个自定义的 Groovy 类，其中包含了一个名为 parseJsonByFile 的方法。该方法主要用于解析JSON格式的文件并返回解析后的对象。
以下是一个简单的例子，假设有一个名为 data.json 的文件包含以下JSON数据：
{
  "name": "Alice",
  "age": 25,
  "email": "alice@example.com"
}

可以使用 parseJsonByFile 方法来解析该文件：
def fileName = "data.json"
def parsedObject = new utilsFile().parseJsonByFile(fileName)

这将会返回一个解析后的对象，它的属性可以通过点号访问，例如：
assert parsedObject.name == "Alice"
assert parsedObject.age == 25
assert parsedObject.email == "alice@example.com"

需要注意的是，parseJsonByFile 方法只能解析符合JSON格式的文件。如果文件格式错误，将会抛出异常。例如，如果 data.json 文件的内容如下：

This is not a valid JSON file.

则会抛出以下异常：

groovy.json.JsonException: Expected a ':' after a key at character 20 of This is not a valid JSON file.

除了使用 new 关键字实例化 utilsFile 类之外，也可以使用静态导入方式导入 parseJsonByFile 方法，例如：

import static com.example.utils.utilsFile.parseJsonByFile

def fileName = "data.json"
def parsedObject = parseJsonByFile(fileName)

这样，就可以直接使用 parseJsonByFile 方法，而不需要创建 utilsFile 类的实例。

代码def viewjsonStr = sh(returnStdout: true,script:  "cat $fileName").toString().trim()
        println "jsonStr is "+ viewjsonStr

这段 Groovy 代码主要是使用 sh 方法来执行 Shell 命令，读取一个指定文件中的内容，并将读取的内容存储在 viewjsonStr 变量中。
以下是对这段代码的详细解释：
1. 第一行代码使用 sh 方法来执行 Shell 命令，其中 returnStdout: true 选项用于返回命令的输出结果，而 script 参数指定要执行的 Shell 命令。该命令使用 cat 命令来读取 $fileName 文件的内容。
2. toString() 方法将输出结果转换为字符串类型。
3. trim() 方法用于去除字符串开头和结尾的空格。
4. 第二行代码使用 println 方法来输出一个字符串，其中包括 viewjsonStr 变量的值。
因此，该代码的目的是将指定文件中的内容读取到一个字符串中，并输出该字符串。这在调试和查看文件内容时非常有用。

