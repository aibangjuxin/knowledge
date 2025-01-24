
如果希望在脚本执行后，https_proxy 的值依然在你的终端会话中生效，可以通过以下方法实现。

source a.sh -e dev-cn 

遇到问题可能会退出终端?


方法 1：在当前 Shell 会话中运行脚本

你可以通过 source 命令运行脚本（即 source a.sh 或 . a.sh），这样脚本中的环境变量会直接在当前 Shell 会话中生效。

示例脚本内容（a.sh）：

#!/bin/bash

# 参数处理
while getopts "e:" opt; do
  case $opt in
    e)
      ENV=$OPTARG
      ;;
    *)
      echo "Usage: $0 -e <environment>"
      exit 1
      ;;
  esac
done

if [ -z "$ENV" ]; then
  echo "Error: Environment not specified. Use -e <environment>."
  exit 1
fi

# 设置 https_proxy
export https_proxy="http://192.168.12.5:3128"
echo "Proxy set: $https_proxy"

# 获取 GKE 凭据
gcloud container clusters get-credentials "$ENV" --region your-region --project your-project

# 验证连接
kubectl get nodes

使用方式：

运行脚本时使用 source：

source a.sh -e dev-hk

或者使用点号：

. a.sh -e dev-hk

在这种情况下，脚本中的 export https_proxy 设置将影响当前 Shell 会话，后续在终端中运行的命令会继承此代理配置。

方法 2：将代理设置保存到 Shell 环境

如果希望脚本执行后自动将代理永久保留，可以直接将 https_proxy 设置添加到 Shell 的配置文件（如 ~/.bashrc 或 ~/.zshrc）。

修改脚本内容：

#!/bin/bash

# 设置 https_proxy
export https_proxy="http://192.168.12.5:3128"
echo "Proxy set: $https_proxy"

# 写入代理到当前用户的配置文件
if ! grep -q "export https_proxy=http://192.168.12.5:3128" ~/.bashrc; then
  echo "export https_proxy=http://192.168.12.5:3128" >> ~/.bashrc
fi

# 加载新配置
source ~/.bashrc

# 获取 GKE 凭据
gcloud container clusters get-credentials "$1" --region your-region --project your-project

# 验证连接
kubectl get nodes

使用方式：

直接执行脚本：

./a.sh -e dev-hk

脚本执行后，代理会被写入到 ~/.bashrc，并加载到当前 Shell 会话中，代理配置会长期生效。

方法 3：临时代理设置并在脚本中提示手动操作

如果你只希望脚本自动设置代理，但在终端会话中仍然可用，可以通过在脚本中打印提示，提醒用户手动运行 export 命令。

示例脚本：

#!/bin/bash

# 参数处理
while getopts "e:" opt; do
  case $opt in
    e)
      ENV=$OPTARG
      ;;
    *)
      echo "Usage: $0 -e <environment>"
      exit 1
      ;;
  esac
done

if [ -z "$ENV" ]; then
  echo "Error: Environment not specified. Use -e <environment>."
  exit 1
fi

# 设置 https_proxy
export https_proxy="http://192.168.12.5:3128"
echo "Proxy temporarily set for this script: $https_proxy"

# 提示用户如何设置代理为长期生效
echo "To make the proxy persistent, run the following command in your terminal:"
echo "export https_proxy=http://192.168.12.5:3128"

# 获取 GKE 凭据
gcloud container clusters get-credentials "$ENV" --region your-region --project your-project

# 验证连接
kubectl get nodes

推荐方式
	1.	如果脚本只在当前会话中使用代理，推荐 方法 1，用 source 运行脚本即可。
	2.	如果需要代理长期生效，可以采用 方法 2，将代理设置写入到配置文件（如 ~/.bashrc）。
	3.	如果需要灵活控制，可采用 方法 3，让用户手动决定是否长期设置代理。

根据你的需求选择合适的方法即可！

我想写这样一个Shell脚本.这个脚本主要是让我连接我不同的GCP project的,进一步连接对应的Cluster的,直接执行
1 会让我输入对应的数字 
2 我的数字会对应比如1 HK 2 UK 3 IN 4 US 
HK 对应的 region asia-east2
UK 对应的 region europe-west2
IN 对应的 region asia-south1
US 对应的 region us-central1
3 比如我输入的是1 那么代表的是我要选择HK这个region
下一步提示我输入对应的env 信息
比如我输入pdev dev sit uat ppd prd 这些

比如我输入的是dev 

那么我上面完成的是dev-hk这个环境
