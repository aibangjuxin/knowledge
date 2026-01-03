/*
这段代码定义了一个名为`projectSettings`的映射，它将项目ID映射到目标环境和区域。然后，它从一个名为`urlarray`的数组中获取项目ID，并使用它来查找相应的目标环境和区域。如果找到了相应的设置，则将`targetEnv`和`region`设置为相应的值，并将`exec_node`设置为一个特定的字符串。否则，将`exec_node`设置为另一个特定的字符串。

具体来说，这段代码的执行过程如下：
1. 定义一个名为`projectSettings`的映射，它将项目ID映射到目标环境和区域。
2. 从一个名为`urlarray`的数组中获取项目ID。
3. 使用项目ID在`projectSettings`映射中查找相应的目标环境和区域。
4. 如果找到了相应的设置，则将`targetEnv`和`region`设置为相应的值，并将`exec_node`设置为一个特定的字符串。
5. 否则，将`exec_node`设置为另一个特定的字符串。

需要注意的是，这段代码使用了Groovy的映射和条件语句来实现一个简单的查找和替换操作。它可以用于根据项目ID设置执行节点的名称，以便在后续的代码中使用。

Here's an example of how you can use a map:

def projectSettings = [
    "abcd-12345689-apigwpdv-ccc": ["targetEnv": "dddd", "region": "uk"],
    "abcd-111111111-wwwfpdv-ccc": ["targetEnv": "dddd", "region": "hk"],
    "abcd-111111111-wwwf-prod": ["targetEnv": "kkk", "region": "hk"]
]

def projectId = urlarray[2]
println "${projectId}"

def projectSettingsForId = projectSettings[projectId]
if (projectSettingsForId) {
    targetEnv = projectSettingsForId.targetEnv
    region = projectSettingsForId.region
    exec_node = "wsit-cap-${targetEnv}-${region}-release"
} else {
    exec_node = "macos-linux"
}

3. Consider using a ternary operator: Instead of using an if statement to check if both targetEnv and region have a value, consider using a ternary operator to set the value of exec_node.
考虑使用三元运算符：不要使用if语句来检查targetEnv和region是否都有值，而是考虑使用三进制运算符来设置exec_node的值。
在Groovy中，三元运算符是一种简洁的条件语句，它可以根据条件的真假来返回两个不同的值。三元运算符的语法如下：
condition ? valueIfTrue : valueIfFalse
在Groovy中，三元运算符是一种简洁的条件语句，它可以根据条件的真假来返回两个不同的值。三元运算符的语法如下：

```
condition ? valueIfTrue : valueIfFalse
```

其中，`condition`是一个布尔表达式，如果为`true`，则返回`valueIfTrue`，否则返回`valueIfFalse`。

例如，以下代码使用三元运算符来检查一个数字是否为正数：

```
def num = -5
def isPositive = num > 0 ? true : false
println isPositive
```

在这个例子中，`num > 0`是一个布尔表达式，如果`num`大于0，则返回`true`，否则返回`false`。因此，`isPositive`的值将根据`num`是否为正数而变化。

需要注意的是，虽然三元运算符可以使代码更简洁，但过度使用它们可能会导致代码难以阅读和维护。因此，在使用三元运算符时，应该确保代码易于理解和维护。



Here's an example of how you can use a ternary operator:

def exec_node = (targetEnv && region) ? "wsit-cap-${targetEnv}-${region}-release" : "mac-linux"

def exec_node = (targetEnv && region) ? "wsit-cap-${targetEnv}-${region}-release" : "mac-linux"
*/

/*
String pr = config.pullrequest
def urlarray = pr[8..- 1].split('/')
def projectId = urlarray[2]
println "${projectId}"

def projectMap = [
    "abcd-12345689-apigwpdv-ccc": ["targetEnv": "dddd", "region": "uk"],
    "abcd-111111111-wwwfpdv-ccc": ["targetEnv": "dddd", "region": "hk"]
    // add more project IDs and mappings here
]

def projectInfo = projectMap[projectId]
if (projectInfo) {
    def targetEnv = projectInfo["targetEnv"]
    def region = projectInfo["region"]
    println "Target environment: ${targetEnv}, Region: ${region}"
    def exec_node = "wsit-cap-${targetEnv}-${region}-release"
    //def exec_node = (targetEnv && region) ? "wsit-cap-${targetEnv}-${region}-release" : "mac-linux" 
} else {
    println "Project ID not recognized"
}
*/

string="csrs1234"

if [[ $string == csrs* ]]; then
    result=${string:4} # 如果以 "csrs" 开头，从第五个字符开始截取到结尾
else
    result=${string:0:5} # 如果不以 "csrs" 开头，截取前五个字符
fi

echo $result


以下是一个示例Groovy脚本，它使用输入链接的URL决定Jenkins上要运行的节点：
def node = null
def currentUrl = env.BUILD_URL.split('/')[0..-2].join('/') // get the current build URL and remove the last segment (the build ID)
if (currentUrl.endsWith("prod")) {
    node = "production-node"
} else if (currentUrl.endsWith("test")) {
    node = "test-node"
} else {
    node = "default-node"
}

node(node) {
    // do something on the selected node
}

这个脚本假设有以下三个Jenkins节点：production-node，test-node和default-node。如果构建URL以“prod”结尾，则选择production-node节点运行构建；如果URL以“test”结尾，则选择test-node节点运行构建；否则，默认选择default-node节点。
def node = null
def currentUrl = env.BUILD_URL.split('/')[0..-2].join('/') // get the current build URL and remove the last segment (the build ID)
def field = currentUrl.tokenize('/').last() // extract the last segment of the URL

switch (field) {
    case "production":
        node = "production-node"
        break
    case "test":
        node = "test-node"
        break
    case "staging":
        node = "staging-node"
        break

以下是一个示例Groovy脚本，它从输入链接的URL中提取一个名为environment的字段，并使用switch语句根据该字段选择Jenkins上要运行的节点：
def node = null
def currentUrl = env.BUILD_URL.split('/')[0..-2].join('/') // get the current build URL and remove the last segment (the build ID)
def environment = currentUrl =~ /.*environment=(\w+).*/ ?~ 1 // extract the 'environment' parameter from the URL using a regex

switch (environment) {
    case "production":
        node = "production-node"
        break
    case "test":
        node = "test-node"
        break
    default:
        node = "default-node"
}

node(node) {
    // do something on the selected node
}

这个脚本假设有以下三个Jenkins节点：production-node
，test-node和default-node。它使用正则表达式从构建URL中提取environment参数，并将其与switch语句中的可能值进行匹配以选择适当的节点。如果environment是production，则选择production-node节点运行构建；如果是test，则选择test-node节点运行构建；否则，默认选择default-node节点。


if (field1 && field2) {
    // both fields have a value, do something
} else {
    // at least one field is null or empty, handle the case
}


