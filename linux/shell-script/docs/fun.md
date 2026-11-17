在Shell脚本中，函数是一种重要的代码复用和模块化的工具。函数可以帮助你简化代码，使其更易于阅读和维护。以下是一些关于如何在Shell脚本中使用函数的基本信息和技巧。

## 函数的定义和调用

在Shell脚本中，你可以使用两种方式定义函数，一种是使用`function`关键字，另一种是直接使用函数名。以下是两种定义方式的示例[1][5]：

```bash
function funcName() {
  # 函数体
}

# 或者

funcName() {
  # 函数体
}
```

函数定义完成后，可以通过函数名来调用函数。如果需要向函数传递参数，可以在函数名后面添加参数，参数之间用空格分隔[1][3][5]。

```bash
funcName arg1 arg2 arg3
```

在函数体内部，可以通过`$n`的形式获取参数的值，例如，`$1`表示第一个参数，`$2`表示第二个参数，以此类推。当参数数量大于等于10时，需要使用`${n}`的形式获取参数[1][7]。

## 函数的返回值

函数的返回值可以通过`return`语句显式返回。如果没有`return`语句，函数将以最后一条命令的运行结果作为返回值[1][5][7]。函数的返回值可以通过特殊变量`$?`获取[1][5]。

```bash
funcName() {
  # 函数体
  return 0  # 返回值
}

funcName  # 调用函数
echo $?  # 输出函数的返回值
```

## 函数的作用域

在Shell脚本中，变量默认是全局的，但是你可以使用`local`命令将变量限定在函数体内部[2]。

```bash
funcName() {
  local localVar="I'm local."  # 局部变量
  globalVar="I'm global."  # 全局变量
}
```

## GKE相关的函数示例

以下是一个使用Shell脚本和函数来操作Google Kubernetes Engine (GKE)的示例。这个函数可以用来设置Google Cloud CLI的默认值[4]。

```bash
function setGCloudConfig() {
  gcloud config set project $1
  gcloud config set compute/region $2
}

# 调用函数，设置项目ID和计算区域
setGCloudConfig PROJECT_ID COMPUTE_REGION
```

在这个示例中，`setGCloudConfig`函数接受两个参数：`PROJECT_ID`和`COMPUTE_REGION`，并使用这两个参数来设置Google Cloud CLI的默认项目和计算区域。

总的来说，函数是Shell脚本中的重要工具，可以帮助你编写更清晰、更易于维护的代码。希望以上的信息和示例可以帮助你更好地理解和使用Shell脚本中的函数。

Citations:
[1] https://www.runoob.com/linux/linux-shell-func.html
[2] https://blog.csdn.net/weixin_66997367/article/details/124162268
[3] https://blog.csdn.net/happyhorizion/article/details/80431327
[4] https://cloud.google.com/kubernetes-engine/docs/tutorials/kueue-cohort?hl=zh-cn
[5] https://c.biancheng.net/view/1009.html
[6] https://blog.csdn.net/weixin_40228200/article/details/120821484
[7] https://www.tiven.cn/p/cc3c1203/
[8] https://cloud.google.com/service-mesh/docs/unified-install/install-anthos-service-mesh-command?hl=zh-cn
[9] https://blog.csdn.net/afei__/article/details/124615557
[10] https://developer.aliyun.com/article/953840
[11] https://blog.csdn.net/weixin_43810067/article/details/124184296
[12] https://theitzy.com/gcp-google-kubernetes-engine-gke-with-devops/
[13] https://www.cnblogs.com/lsdb/p/10148177.html
[14] https://blog.51cto.com/lwops/2595336
[15] https://www.runoob.com/linux/linux-shell-passing-arguments.html
[16] https://shellscript.readthedocs.io/zh_CN/latest/1-syntax/6-functions/
[17] https://toutiao.com/article/6768032296890008075/?source=seo_tt_juhe&upstream_biz=toutiao_pc
[18] https://juejin.cn/post/7054817562621640717
[19] https://blog.csdn.net/qq_49530779/article/details/121948732
[20] https://www.cnblogs.com/diantong/p/11718794.html
[21] https://www.cnblogs.com/XuyeZi/p/12930726.html
[22] https://www.cnblogs.com/struggle-1216/p/13174266.html
[23] https://www.jianshu.com/p/d3cd36c97abc
[24] https://shixiangwang.github.io/home/cn/post/2017-11-26-shell-create-function/
[25] https://pshizhsysu.gitbook.io/shell/shell-can-shu-chuan-di
