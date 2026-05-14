
若要排除以 "kube-" 开头的系统 namespace，你可以在循环之前添加一个条件来检查 namespace 名称。以下是修改后的脚本：

```bash
#!/bin/bash

# 获取所有的 namespace，但排除以 "kube-" 开头的系统 namespace
namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | grep -vE '^kube-')

# 循环处理每个 namespace
for namespace in $namespaces; do
    echo "Namespace: $namespace"

    # 获取该 namespace 下的 deployments 数量
    deployment_count=$(kubectl get deployments --namespace=$namespace --no-headers | wc -l)
    echo "Number of Deployments: $deployment_count"

    # 获取该 namespace 下的 pods 数量
    pod_count=$(kubectl get pods --namespace=$namespace --no-headers | wc -l)
    echo "Number of Pods: $pod_count"

    echo "----------------------"
done
```

如果你想在循环过程中跳过某些特定的 namespace，你可以使用条件语句来检查该 namespace 是否需要被跳过。在 Bash 脚本中，你可以使用 `continue` 语句来实现这一点。以下是一个示例：

```bash
#!/bin/bash

# 获取所有的 namespace，但排除以 "kube-" 开头的系统 namespace
namespaces=$(kubectl get namespaces -o jsonpath='{.items[?(@.metadata.name !~ /^kube-/)].metadata.name}')

# 循环处理每个 namespace
for namespace in $namespaces; do
    # 在这里添加条件，如果需要跳过某个 namespace，可以使用 if 语句
    if [ "$namespace" == "namespace_to_skip" ]; then
        echo "Skipping $namespace"
        continue
    fi

    echo "Processing Namespace: $namespace"

    # 获取该 namespace 下的 deployments 数量
    deployment_count=$(kubectl get deployments --namespace=$namespace --no-headers | wc -l)
    echo "Number of Deployments: $deployment_count"

    # 获取该 namespace 下的 pods 数量
    pod_count=$(kubectl get pods --namespace=$namespace --no-headers | wc -l)
    echo "Number of Pods: $pod_count"

    echo "----------------------"
done
```

在这个例子中，如果 `namespace_to_skip` 是需要跳过的 namespace，那么它会输出 "Skipping namespace_to_skip" 并继续到下一个 namespace。你可以根据实际情况修改条件语句来适应你想要跳过的 namespace。

