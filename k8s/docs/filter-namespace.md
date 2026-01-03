



# 获取所有的namespace
kubectl get namespaces -o json | jq -r '.items[].metadata.name'|grep -Ev "^kube-|default"




# 获取所有的namespace 并排出 默认的 kube-system namespace
# 下面是一行输出的
namespaces=$(kubectl get ns -o jsonpath="{.items[*].metadata.name}") 
# 下面是多行输出的
kubectl get namespaces -o json | jq -r '.items[].metadata.name' | tr '\n' '\n'



# success
kubectl get namespaces -o json | jq -r '.items[] | select(.metadata.name != "kube-system") | .metadata.name'

# success
# 获取所有命名空间，并排除以kube-开头的命名空间和默认的default命名空间
kubectl get namespaces -o json | jq -r '.items[] | select(.metadata.name | startswith("kube-") | not) | select(.metadata.name != "default") | .metadata.name'
# 获取所有命名空间，并排除以kube-开头的命名空间和默认的default命名空间 且 命名空间名以abc开头
kubectl get namespaces -o json | jq -r '.items[] | select(.metadata.name | startswith("kube-") | not) | select(.metadata.name != "default") | select(.metadata.name | startswith("abc") | not) | .metadata.name'





# shell命令来获取所有命名空间并排除以kube-开头的命名空间和默认的default命名空间
kubectl get namespaces --no-headers=true | awk '{if($1 !~ /^kube-/ && $1 != "default") print $1}'
kubectl get namespaces -o json | jq -r '.items[] | select(.metadata.name != "default" and (.metadata.name | startswith("kube-") | not)) | .metadata.name'



# 获取所有的label为nsType = runtime 的namespace 名字 一行输出的结果
#all_namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
all_namespaces=$(kubectl get namespace -l nsType=runtime -o name -o jsonpath='{.items[*].metadata.name}')

kubectl get namespace aibang -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp

帮我写这样一个Shell.我的目的是想要预删除一些不在使用的namespace.我的基本原则是判断其一些Resource的数量
#获取所有namespace
all_namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
#循环遍历所有namespace
for namespace in $all_namespaces; do
我想要在循环的时候排除掉一些命名空间，比如以kube-开头的命名空间   、default等
然后对于其他的命名空间，执行一些操作，比如获取这些命名空间下所有的
networkpolicy deployment svc hpa pod等等
我还想判断上面这些资源的数量，比如networkpolicy的数量、deployment svc hpa pod的数量等等



以下是你描述的需求的一个 Shell 脚本：

```bash
#!/bin/bash

# 获取所有命名空间（排除以 "kube-" 开头和 "default" 的命名空间）
all_namespaces=$(kubectl get namespaces -o json | jq -r '.items[] | select(.metadata.name | startswith("kube-") | not) | select(.metadata.name != "default") | .metadata.name')

# 循环遍历所有命名空间
for namespace in $all_namespaces; do
    echo "Namespace: $namespace"
    kubectl get namespace $namespace -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp
    # 获取 networkpolicy 的数量
    networkpolicy_count=$(kubectl get networkpolicy --namespace=$namespace --no-headers | wc -l)
    echo "Number of Network Policies: $networkpolicy_count"

    # 获取 deployment 的数量
    deployment_count=$(kubectl get deployments --namespace=$namespace --no-headers | wc -l)
    echo "Number of Deployments: $deployment_count"

    # 获取 service 的数量
    service_count=$(kubectl get services --namespace=$namespace --no-headers | wc -l)
    echo "Number of Services: $service_count"

    # 获取 hpa 的数量
    hpa_count=$(kubectl get hpa --namespace=$namespace --no-headers | wc -l)
    echo "Number of Horizontal Pod Autoscalers: $hpa_count"

    # 获取 pod 的数量
    pod_count=$(kubectl get pods --namespace=$namespace --no-headers|grep -v "^certificate" | wc -l)
    echo "Number of Pods: $pod_count"
    if [ $deployment_count -eq 0 ]; then
        echo -e "\033[31m  Delete this namespace: $namespace \033[0m"
    fi
    # 判断 Pod、Deployment 和 Service 的数量是否都为0
    if [ $pod_count -eq 0 ] && [ $deployment_count -eq 0 ] && [ $service_count -eq 0 ]; then
        echo -e "\033[31m namespace: $namespace resource is empty, delete it \033[0m"
    fi

    echo "--------------------------------------"
done
```

