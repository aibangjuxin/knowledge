`kubectl set image` 命令和 `kubectl -n $ns patch` 命令都可以更新 Kubernetes 资源的镜像。两者的区别如下：

**`kubectl set image` 命令**

* 使用 `set` 子命令更新镜像。
* 会创建一个新的 Deployment、Pod、StatefulSet 或 Job，然后将旧的 Pod 逐渐替换为新的 Pod。
* 需要指定 `CONTAINER` 和 `IMAGE` 参数。

**`kubectl -n $ns patch` 命令**

* 使用 `patch` 子命令更新镜像。
* 会直接更新现有的 Deployment、Pod、StatefulSet 或 Job。
* 可以使用 `json` 或 `yaml` 格式的文件来指定更新内容。

以下是两种命令的具体示例：

**`kubectl set image` 命令**

```
kubectl set image deployment my-deployment my-container=gcr.io/my-project/my-image:latest
```

该命令将 Deployment `my-deployment` 的 `my-container` 容器的镜像更新为 `gcr.io/my-project/my-image:latest`。

**`kubectl -n $ns patch` 命令**


kubectl -n my-namespace patch deployment my-deployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"my-container","image":"gcr.io/my-project/my-image:latest"}]}}}'


该命令将 Deployment `my-deployment` 的 `my-container` 容器的镜像更新为 `gcr.io/my-project/my-image:latest`。

**两种命令的优缺点**

`kubectl set image` 命令的优点是使用简单，不需要指定更新内容的格式。缺点是更新操作会导致 Pod 的重新创建，可能会影响应用的可用性。

`kubectl -n $ns patch` 命令的优点是更新操作不会导致 Pod 的重新创建，不会影响应用的可用性。缺点是使用复杂，需要指定更新内容的格式。

**选择哪种命令**

选择哪种命令取决于具体需求。如果需要快速更新镜像，并且可以容忍 Pod 的重新创建，可以使用 `kubectl set image` 命令。如果需要避免 Pod 的重新创建，可以使用 `kubectl -n $ns patch` 命令。


`kubectl set image` 和 `kubectl patch` 是 Kubernetes 中用于更新容器镜像的两种不同方法，它们有一些关键的区别。

### 1. kubectl set image

`kubectl set image` 是 Kubernetes 提供的一种方便的方式，用于更新 Deployment、StatefulSet 等资源中的容器镜像。该命令允许你通过简单的命令行参数来指定新的容器镜像，然后 Kubernetes 将负责完成滚动更新。

示例：
```bash
kubectl set image deployment/my-deployment my-container=new-image:tag
```

#### 特点：
- **方便性：** 简单易用，不需要手动处理复杂的 JSON 或 YAML。
- **滚动更新：** Kubernetes 会负责按照滚动更新策略逐步替换 Pod，确保服务的高可用性。
- **集成性：** 与其他资源控制器（如 Deployment）直接集成，不需要深入了解资源对象的详细配置。

### 2. kubectl patch

`kubectl patch` 允许你直接对资源对象的 JSON 或 YAML 进行局部修改。通过使用 `kubectl patch`，你可以更细粒度地控制更新，包括容器镜像的修改。

示例：
```bash
kubectl patch deployment/my-deployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"my-container","image":"new-image:tag"}]}}}}'
```

#### 特点：
- **灵活性：** 可以手动编辑 JSON 或 YAML，实现更灵活的修改。
- **直接修改：** 直接修改资源对象的配置，没有高级别的抽象。
- **潜在风险：** 需要确保修改的 JSON 或 YAML 是有效的，否则可能导致配置错误。

### 关于 kubectl -n $ns patch 命令是否会影响 replicaset 的值的改变

`kubectl -n $ns patch` 命令通常用于直接修改资源对象的配置，而不涉及 replicaset 的值的改变。如果你修改的是 Deployment，Kubernetes 将会负责更新对应的 replicaset。

Replicaset 是由 Deployment 控制的，而不是直接通过 `kubectl -n $ns patch` 命令修改。修改 Deployment 的配置，例如使用 `kubectl set image` 或 `kubectl -n $ns patch`，将会触发 Deployment 的更新，然后由 Kubernetes 系统负责管理 replicaset 的变化，确保新的 Pod 版本逐步替换旧的 Pod。

总的来说，`kubectl -n $ns patch` 主要用于直接编辑资源对象的配置，而 replicaset 的管理通常是由 Kubernetes 控制器负责的。


通过 kubectl -n $ns patch 更新了 Deployment 的容器镜像，Kubernetes 控制器系统会处理 replicaset 的更新，确保新的 Pod 逐步替换旧的 Pod，从而实现滚动更新的效果


是的，您说的没错。通过 `kubectl -n $ns patch` 更新了 Deployment 的容器镜像，Kubernetes 控制器系统会处理 ReplicaSet 的更新，确保新的 Pod 逐步替换旧的 Pod，从而实现滚动更新的效果。

具体来说，Kubernetes 控制器系统会执行以下步骤：

1. 创建一个新的 ReplicaSet，该 ReplicaSet 使用新的容器镜像。
2. 将新的 ReplicaSet 的 Pod 逐渐调度到集群中。
3. 将旧的 ReplicaSet 的 Pod 逐渐删除。

在整个更新过程中，Kubernetes 控制器系统会确保集群中始终保持 `spec.replicas` 指定的 Pod 数量。

以下是更新 Deployment 的示例：


kubectl -n my-namespace patch deployment my-deployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"my-container","image":"gcr.io/my-project/my-image:latest"}]}}}'


该命令将 Deployment `my-deployment` 的 `my-container` 容器的镜像更新为 `gcr.io/my-project/my-image:latest`。

在更新完成后，ReplicaSet 的 `spec.template.spec.containers` 字段将会发生改变，新的容器镜像将会替换旧的容器镜像。

[Image of 更新 Deployment 后 ReplicaSet 的变化]

因此，通过 `kubectl -n $ns patch` 更新 Deployment 的容器镜像，ReplicaSet 的镜像也会发生改变。


```bash
#!/bin/bash
gcp_region=asia
project=my-project

function update_images() {
    local ns=$1
    deployments=$(kubectl -n $ns get deploy -o json)

    echo "$deployments" | jq -r '.items[] | .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image)' | while read -r line; do
        deploy=$(echo "$line" | cut -d ' ' -f 1)
        container=$(echo "$line" | cut -d ' ' -f 2)
        image=$(echo "$line" | cut -d ' ' -f 3)

        update_image $deploy $container $image
    done

    echo "$deployments" | jq -r '.items[] | .metadata.name + " " + (.spec.template.spec.initContainers[] | .name + " " + .image)' | while read -r line; do
        deploy=$(echo "$line" | cut -d ' ' -f 1)
        container=$(echo "$line" | cut -d ' ' -f 2)
        image=$(echo "$line" | cut -d ' ' -f 3)

        update_image $deploy $container $image
    done
}

function update_image() {
    deploy=$1
    container=$2
    image=$3

    local ns=$4
    image_name_version=$(echo "$image" | awk -F "/" '{print $NF}')
    target_dir="${gcp_region}-docker.pkg.dev/${project}/containers/"
    target_image="$target_dir$image_name_version"

    if [[ "$image" != *"docker.pkg.dev"* ]]; then
        echo "kubectl -n $ns set image deploy/$deploy $container=$target_image"
        # Uncomment the following line to actually execute the command
        # kubectl -n $ns set image deploy/$deploy $container=$target_image
    fi
}

update_images "your_namespace"
```
