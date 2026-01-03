string="csrs1234"

if [[ $string == csrs* ]]; then
    result=${string:4} # 如果以 "csrs" 开头，从第五个字符开始截取到结尾
else
    result=${string:0:5} # 如果不以 "csrs" 开头，截取前五个字符
fi

echo


在Jenkins Pipeline中，您可以使用Groovy语言来判断参数是否为空，并将其赋值给另一个变量。以下是一个示例：

```
pipeline {
  agent any
  parameters {
    string(name: 'PARAMETER_NAME', defaultValue: '', description: 'Description of parameter')
  }
  stages {
    stage('Example') {
      steps {
        script {
          def parameterValue = params.PARAMETER_NAME ?: 'default_value'
          echo "Parameter value: ${parameterValue}"
        }
      }
    }
  }
}
```
在这个示例中，我们定义了一个
名为`PARAMETER_NAME`的字符串参数，并将其默认值设置为空字符串。
在`Example`阶段中，我们使用Groovy的null合并运算符`?:`来检查参数是否为空。如果参数为空，则将其替换为`default_value`。
最后，我们将参数值打印到控制台。

您可以根据需要修改示例中的变量名和默认值。


可以使用 Groovy 的三元运算符来实现这个功能。示例如下：

def myValue = null
def result = myValue ? myValue : "default value"

println result // 输出: default value
上述代码中，myValue 被赋值为 null，
则三元运算符会判断 myValue 是否为真。由于 myValue 是空值，
所以表达式的值为假，因此返回默认值 "default value"。
你可以根据需要修改变量名、默认值和输出方式等细节


pipeline传入参数 groovy
判断不为空则赋值给A
判断为空则赋值给B
在Jenkins Pipeline中，您可以使用Groovy语言来判断参数是否为空，并将其赋值给不同的变量。以下是一个示例：


```
pipeline {
  agent any
  parameters {
    string(name: 'PARAMETER_NAME', defaultValue: '', description: 'Description of parameter')
  }
  stages {
    stage('Example') {
      steps {
        script {
          def variableA = ''
          def variableB = ''
          if (params.PARAMETER_NAME) {
            variableA = params.PARAMETER_NAME
            //crnumber = params.PARAMETER_NAME
          } else {
            variableB = 'default_value'
            //crnumber = 'default_value'
          }
          echo "Variable A: ${variableA}"
          echo "Variable B: ${variableB}"
          // echo "crnumber#: ${variableA ?: variableB}"
          // echo "crnumber#: ${crnumber}"
        }
      }
    }
  }
}
```
using variableA ==> crnumber
variableB == > null
在这个示例中，我们定义了一个名为`PARAMETER_NAME`的字符串参数，并将其默认值设置为空字符串。
在`Example`阶段中，我们使用Groovy的if-else语句来检查参数是否为空。
如果参数不为空，则将其赋值给`variableA`。
如果参数为空，则将`'default_value'`赋值给`variableB`。最后，我们将变量值打印到控制台。

您可以根据需要修改示例中的变量名和默认值。
如果稍后需要在脚本中更新variableA的值，只需使用相同的语法为其分配一个新值：
If you need to update the value of variableA later in the script, you can simply assign a new value to it using the same syntax:
variableA = 'new_value'
variableA = 'crnumber'

def body = "abc ${variableA}"

上面的例子中其实我可以把VariableA和VariableB 输出为同一个变量



pipeline传入一个参数 groovy
判断参数不为空则赋值给A 结果为a+参数
判断为空则也赋值给A 结果为b
The code block you have provided is a simple variable assignment in Groovy.
variableA = params.PARAMETER_NAME
This line of code assigns the value of the PARAMETER_NAME parameter to the variableA variable.

In the context of the larger codebase you provided, this code block is part of a Jenkins Pipeline script that checks if a parameter is empty or not and assigns its value to different variables accordingly.

If the PARAMETER_NAME parameter is not empty, its value is assigned to variableA. If it is empty, the string 'default_value' is assigned to variableB.

To concatenate a string to the value of variableA, you can use the + operator:

variableA = 'a' + params.PARAMETER_NAME

这行代码检查PARAMETER_NAME是否为空。
如果它不为空，它会将“a”连接到其值，并将结果字符串分配给variableA。
如果它为空，它会将“b”分配给变量A。
This line of code checks if PARAMETER_NAME is empty. If it is not empty, 
it concatenates 'a' to its value and assigns the resulting string to variableA. 
If it is empty, it assigns 'b' to variableA.

////
pipeline传入一个参数 groovy
判断参数不为空则赋值给A 结果为a+参数
判断为空则也赋值给A 结果为b
可以使用如下的Groovy语法来实现这个逻辑：
def param = params.MY_PARAM_NAME ?: '' // 获取pipeline传入的参数，如果为空则设置为''
def A = param ? 'a' + param : 'b' // 根据参数是否为空来赋值A
///
在Jenkins Pipeline中，您可以使用Groovy语言来判断参数是否为空，并将其赋值给不同的变量。以下是一个示例：

```
pipeline {
  agent any
  parameters {
    string(name: 'PARAMETER_NAME', defaultValue: '', description: 'Description of parameter')
  }
  stages {
    stage('Example') {
      steps {
        script {
          def variableA = ''
          if (params.PARAMETER_NAME) {
            variableA = "a${params.PARAMETER_NAME}"
          } else {
            variableA = 'b'
          }
          echo "Variable A: ${variableA}"
        }
      }
    }
  }
}
```

在这个示例中，我们定义了一个名为`PARAMETER_NAME`的字符串参数，并将其默认值设置为空字符串。在`Example`阶段中，我们使用Groovy的if-else语句来检查参数是否为空。
如果参数不为空，则将`a`和参数值拼接起来赋值给`variableA`。如果参数为空，则将`'b'`赋值给`variableA`。最后，我们将变量值打印到控制台。

您可以根据需要修改示例中的变量名和默认值。
