

- the next script will switch the environment
```bash
#!/usr/bin/env bash
# 设置环境变量的脚本

declare -A env_info

env_info=(
  ["dev-cn"]="project=aibang-teng-sit-api-dev cluster=dev-cn-cluster-123789 region=europe-west2 https_proxy=10.98.21.119:3128 private_network=aibang-teng-sit-api-dev-cinternal-vpc3"
  ["dev-in"]="project=aibang-teng-sit-apisit-dev cluster=dev-in-cluster-123456 region=europe-west2 https_proxy=10.98.25.50:3128 private_network=aibang-teng-sit-apisit-dev-cinternal-vpc1"
)

environment=""

# 显示使用帮助
function usage() {
  echo "使用方法: source $0 --environment 环境"
  echo "if using source $0 when script finished . you can verify the proxy"
  echo "Using export |grep https verify the result"
  echo "选项:"
  echo "  --environment, -e   环境名称,必选"
  echo "  --help, -h          显示此帮助消息"
  echo "可用的环境选项:"
  for key in "${!env_info[@]}"; do
    echo "  $key"
  done
}

# 检查参数
if [[ ($# -eq 0) || ($1 != "-e" && $1 != "--environment") ]]; then
  usage
  return 2>/dev/null || exit 1
fi

# 解析参数
while [[ $# -gt 0 ]]; do
  case $1 in
    -e | --environment)
      if [[ -z "$2" ]]; then
        echo "环境选项为空"
        usage
        return 2>/dev/null || exit 1
      fi
      environment="$2"
      shift 2
      ;;
    -h | --help)
      usage
      return 2>/dev/null || exit 0
      ;;
    *)
      usage
      return 2>/dev/null || exit 1
      ;;
  esac
done

if [[ -z "${environment}" ]]; then
  echo "缺少环境选项"
  usage
  return 2>/dev/null || exit 1
fi

if [[ -z "${env_info[$environment]}" ]]; then
  echo "无效的环境: $environment"
  usage
  return 2>/dev/null || exit 1
fi

# 设置环境变量
env_vars="${env_info[$environment]}"
IFS=' ' read -r -a var_array <<< "$env_vars"

for var in "${var_array[@]}"; do
  if [[ $var == *"="* ]]; then
    key="${var%%=*}"
    value="${var#*=}"
    eval "export $key='$value'"
  fi
done

echo "Environment: $environment"
echo "Project: $project"
echo "Region: $region"
echo "Cluster: $cluster"
echo "https_proxy: $https_proxy"
echo "private_network: $private_network"

SCRIPT_NAME="${0##*/}"
info() {
  echo -e "\033[31m ${SCRIPT_NAME}: ${1} \033[0m"
}
echo -e "active $project"
echo -e "\033[31m active $project \033[0m"
echo "gcloud config configurations activate $project"
echo "gcloud config set project $project"
echo "if you want unset the https proxy.Please using next command"
echo "unset https_proxy"
#unset https_proxy
```