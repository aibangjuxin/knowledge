import groovy.json.JsonSlurper
import groovy.json.JsonOutput

println "----ls commond----"
println "ls".execute().text

def command = "pwd"
def process = command.execute().text

println "-------------pwd command execute result"

//println "${process}"

if (process.indexOf("setup") > 0) {
    println "exists keyword setup"
    //throw new Exception("The keyword must exits")
    // I put here for trigger it .
} else {
    println "The setup no exists"
    throw new Exception("The keyword must exits")
}




println " Define the approval payload"

def approvalPayload = JsonOutput.toJson(["event": "APPROVE"])
println "${approvalPayload}"
def gitRepoapiUrl = "https://aip.github.com/api/v3/repos/google-cloud-projects/project_id_123456/pulls/279"
//eg :https://aip.github.com/api/v3/repos/google-cloud-projects/project_id_123456/pulls/279
// Determine whether the pull request exists
def RequestFileName = "request.json"
def requestCommand = "curl -w '%{http_code}' -X GET -u \"account:password\" $gitRepoapiUrl -o $RequestFileName"
//def requesthttpCode = sh(returnStdout: true, script: "$requestCommand").toString().trim()
//println "${requesthttpCode}"
//sh("cat $RequestFileName")
println "----------print gitRepoapiUrl---------"
println "${gitRepoapiUrl}"
println "----------print pr index---------"
def index1 = gitRepoapiUrl.indexOf("project_id_123456")
println "${index1}"

if (gitRepoapiUrl.indexOf("project_id_123456") > 0) {
    def gitCredId = "PDEV-SA"
    println "${gitCredId}"
    println "indx"
}


println "-----------Print demon------------------"
public class Demo {
    public static void main(String[] args) {
        System.out.println("Hello World Demo"); 
        println "abc"
    }
}
new Demo().main(args)

println "-----------print demo finished------------------"

println "Finished"
println "hello" /* a multiline comment starting
                   at the end of a statement */
println 1 /* one */ + 2 /* two */

def jq_home() {
    println "jqddddddddddddddddddd"
}

jq_home()

def name = 'Guillaume' // a plain string
def greeting = "Hello ${name}"

println "${greeting}"


println "---------greet---OK -----------------"
 // * A Class description
class Person {
    /** the name of the person */
    String name
     /* Creates a greeting method for a certain person.
     *
     * @param otherPerson the person to greet
     * @return a greeting message
     */
    String greet(String otherPerson) {
        println "Hello ${otherPerson}"
        //println "Hello ${otherPerson}"+otherPerson
    }
}
new Person().greet("xule")

println 2 /* one */ + 3 /* two */

def definame = 'ddd'
println "${definame}"

println "-----------Begin Dog-----------------"

class Dog {
    static void main(String[] args) {
        println "hello Dog" + args[0]
    }
}


String[] aa = new String[3]; 
aa[0] = "this ia a new "
new Dog().main(aa)
//new is `create a new object instance from a class`
// Dog is class
// main is a method 
// aa 是传参

class Cat {
    String name = "Name"
    String catcat(String othercat) {
        println "only output Cat: ${othercat}+${name}"
    }
}
new Cat().catcat("othercat")
// only output Cat: othercat+Name 

println "-----------Begin Person and age-----------------"
class Personandage {
    String name
    int age
    
    void sayHello() {
        println "Hello, my name is ${name}, and I am ${age} years old."
    }
}
def person = new Personandage(name: "John", age: 30)
println person.name + person.age // output: John30

println "----Personandage--------"
println Personandage.name // output: Personandage


person.sayHello() //output: Hello, my name is John, and I am 30 years old.


import groovy.json.JsonOutput  
class Example {
    static void main(String[] args) {
        def output = JsonOutput.toJson([
            new Student(name: 'John', ID: 1), 
            new Student(name: 'Mark', ID: 2)
        ])
        println(output);
    }
}
 
class Student {
    String name
    int ID;
}

new Example().main("Ld", "David")

class MyClass {
    def method() {
        println '...'
    }
}
new MyClass().method()

println "---------sleep  ========"
// a simple sleep method
Thread.sleep(1000)
println "sleep finished"


println "---------try and catch ========"
try {
    def num = 10 / 0
    // Divide by zero, which will throw an arithmetic exception
    println "Result: ${num}"
} catch (ArithmeticException ex) {
    println "Error: ${ex.message}"
} finally {
    println "Done"
}

println "---------Return keyword optional========"
def foo(n) {
    if(n == 1) {
        "Roshan"
    } else {
        "Dawrani"
    }
}

// assert foo(1) == "Roshan"
// assert foo(2) == "Dawrani"

machinetype = foo(3)
println "${machinetype}"
//这个打印重新定义后的结果
println foo(1)
//这个直接打印函数对应的结果


def exmessage = "error"
println "Error: ${exmessage}"

println "---------assert study========"
def num1 = 10
def num2 = 5

assert num1 > num2 : "num1 should be greater than num2"
println "Assertion passed"
// 如果这个结果不匹配直接就中断
// throw an assertion error.


def check(String name) {
    // name non-null and non-empty according to Groovy Truth
    assert name
    // safe navigation + Groovy Truth to check
    assert name?.size() > 3
    //def pp = name
    //println "${pp}"
}
check("abcdefg")
println "Assertion abcdefg > 3 passed"
// 因为上面字符串大于3所以能执行到上行的打印
// check("abc")
//因为上面字符串< 3所以直接就中断
/*
Caught: Assertion failed: 

assert name?.size() > 3
       |     |      |
       abc   3      false
*/

// assert 下面这个测试 假如store结果!=123那么就抛异常
store = ''
for (i in [1,2,3]) {
    store += i
}

println "---------store========"
println "${store}"

assert store == '123'

assert 4 * ( 2 + 3 ) - 5 == 15 : "test success"
//assert 4 * ( 2 + 3 ) - 5 == 14 : "test failed"
// Caught: java.lang.AssertionError: test failed. Expression: (((4 * (2 + 3)) - 5) == 14



