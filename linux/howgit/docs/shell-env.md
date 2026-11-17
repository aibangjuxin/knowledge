# 提取环境变量的前两个字符
env_prefix=${e%%-*}
env_suffix=${e#*-}
echo "${env_prefix}"
echo "${env_suffix}"
