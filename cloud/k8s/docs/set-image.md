# chatgpt 
- 考虑initcontainer的情况,一行来处理
```
#!/bin/bash
gcp_region=asia
project=my-project

function update_images() {
    local ns=$1
    deployments=$(kubectl -n $ns get deploy -o json)

    echo "$deployments" | jq -r '.items[] | .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image) + " " + (.spec.template.spec.initContainers[] | .name + " " + .image)' | while read -r line; do
        deploy=$(echo "$line" | cut -d ' ' -f 1)
        container=$(echo "$line" | cut -d ' ' -f 2)
        image=$(echo "$line" | cut -d ' ' -f 3)

        # Check if it's a container or initContainer
        if [ "$container" != "" ]; then
            image_name_version=$(echo "$image" | awk -F "/" '{print $NF}')
            target_dir="${gcp_region}-docker.pkg.dev/${project}/containers/"
            target_image="$target_dir$image_name_version"

            if [[ "$image" != *"docker.pkg.dev"* ]]; then
                echo "kubectl -n $ns set image deploy/$deploy $container=$target_image"
                # Uncomment the following line to actually execute the command
                # kubectl -n $ns set image deploy/$deploy $container=$target_image
            fi
        elif [ "$container" == "" ]; then
            # It's an initContainer
            init_container=$(echo "$line" | cut -d ' ' -f 4)
            init_image=$(echo "$line" | cut -d ' ' -f 5)

            init_image_name_version=$(echo "$init_image" | awk -F "/" '{print $NF}')
            target_dir="${gcp_region}-docker.pkg.dev/${project}/containers/"
            target_init_image="$target_dir$init_image_name_version"

            if [[ "$init_image" != *"docker.pkg.dev"* ]]; then
                echo "kubectl -n $ns set image deploy/$deploy --container=$init_container $init_container=$target_init_image"
                # Uncomment the following line to actually execute the command
                # kubectl -n $ns set image deploy/$deploy --container=$init_container $init_container=$target_init_image
            fi
        fi
    done
}

update_images "your_namespace"

```



# google 
好的，以下是修改后的脚本：

```bash
#!/bin/bash
gcp_region=asia
project=my-project

function update_images() {
    local ns=$1
    deployments=$(kubectl -n $ns get deploy -o json)

    echo "$deployments" | jq -r '.items[] | .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image) + " " + (.spec.template.spec.initContainers[] | .name + " " + .image)' | while read -r line; do
        deploy=$(echo "$line" | cut -d ' ' -f 1)
        container=$(echo "$line" | cut -d ' ' -f 2)
        image=$(echo "$line" | cut -d ' ' -f 3)
        init_container=$(echo "$line" | cut -d ' ' -f 4)
        init_image=$(echo "$line" | cut -d ' ' -f 5)

        image_name_version=$(echo "$image" | awk -F "/" '{print $NF}')
        target_dir="${gcp_region}-docker.pkg.dev/${project}/containers/"
        target_image="$target_dir$image_name_version"

        if [[ "$image" != *"docker.pkg.dev"* ]]; then
            echo "kubectl -n $ns set image deploy/$deploy $container=$target_image"
            # Uncomment the following line to actually execute the command
            # kubectl -n $ns set image deploy/$deploy $container=$target_image
        fi

        if [[ "$init_image" != *"docker.pkg.dev"* ]]; then
            echo "kubectl -n $ns set image deploy/$deploy $init_container=$target_image"
            # Uncomment the following line to actually execute the command
            # kubectl -n $ns set image deploy/$deploy $init_container=$target_image
        fi
    done
}

update_images "your_namespace"
```
修改如下：
* 在 `update_images()` 函数中，添加 `initContainers` 的循环。
* 在 `initContainers` 循环中，获取 `initContainer` 的名称和镜像。
* 使用 `if...else...` 语句判断镜像是否为 `docker.pkg.dev` 域。
* 如果镜像不是 `docker.pkg.dev` 域，则输出更新镜像的命令。

示例输出：


kubectl -n my-namespace set image deploy/my-deployment my-container=gcr.io/my-project/my-image:latest
kubectl -n my-namespace set image deploy/my-deployment my-init-container=gcr.io/my-project/my-init-image:latest







# claude2

```bash
#!/bin/bash

gcp_region=asia
project=my-project

function update_image() {
  local deploy=$1
  local container=$2
  local image=$3

  image_name_version=$(echo "$image" | awk -F "/" '{print $NF}')
  target_dir="${gcp_region}-docker.pkg.dev/${project}/containers/"
  target_image="$target_dir$image_name_version"

  if [[ "$image" != *"docker.pkg.dev"* ]]; then
    echo "kubectl -n $ns set image deploy/$deploy $container=$target_image"
    # kubectl -n $ns set image deploy/$deploy $container=$target_image
  fi
}

function update_images() {
  local ns=$1
  
  deployments=$(kubectl -n $ns get deploy -o json)

  # 解析 containers
  echo "$deployments" | jq -r '.items[] | .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image)' | while read -r line; do
    deploy=$(echo "$line" | cut -d ' ' -f 1)
    container=$(echo "$line" | cut -d ' ' -f 2) 
    image=$(echo "$line" | cut -d ' ' -f 3)
    
    update_image $deploy $container $image
  done

  # 解析 initContainers
  echo "$deployments" | jq -r '.items[] | .metadata.name + " " + (.spec.template.spec.initContainers[] | .name + " " + .image)' | while read -r line; do
    deploy=$(echo "$line" | cut -d ' ' -f 1)
    container=$(echo "$line" | cut -d ' ' -f 2)
    image=$(echo "$line" | cut -d ' ' -f 3)

    update_image $deploy $container $image
  done

}

update_images "your_namespace"
```
主要逻辑:

1. 提取通用的 `update_image` 函数处理镜像替换
2. 分别解析容器和 init 容器,调用 `update_image` 完成镜像替换


# preplexity 
根据你的需求，你需要在你的脚本中添加对initContainers的支持。这可以通过在你的函数中添加一个新的部分来实现，该部分会获取并处理initContainers的信息。以下是修改后的脚本：
echo "$deployments" | jq -r '.items[] | .metadata.name + " " + (.spec.template.spec.initContainers[]? | .name + " " + .image)'

```bash
#!/bin/bash
gcp_region=asia
project=my-project

function update_images() {
    local ns=$1
    deployments=$(kubectl -n $ns get deploy -o json)

    echo "$deployments" | jq -r '.items[] | .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image)' | while read -r line; do
        update_image "$ns" "$line"
    done

    echo "$deployments" | jq -r '.items[] | .metadata.name + " " + (.spec.template.spec.initContainers[] | .name + " " + .image)' | while read -r line; do
        update_image "$ns" "$line"
    done
}

function update_image() {
    local ns=$1
    local line=$2

    deploy=$(echo "$line" | cut -d ' ' -f 1)
    container=$(echo "$line" | cut -d ' ' -f 2)
    image=$(echo "$line" | cut -d ' ' -f 3)

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

在这个修改后的脚本中，我添加了一个新的函数`update_image`，它接收命名空间和行作为参数，并执行原始脚本中的更新图像逻辑。然后，我修改了`update_images`函数，使其不仅处理`containers`，还处理`initContainers`。这是通过在`deployments`变量上运行两个不同的`jq`命令并对结果进行迭代来实现的。第一个`jq`命令和原始脚本中的相同，处理`containers`。第二个`jq`命令处理`initContainers`。每个`jq`命令的结果都通过管道传递给一个`while`循环，该循环对每一行调用`update_image`函数[1][2][3][5].

Citations:
[1] https://cloud.tencent.com/developer/ask/sof/107382740
[2] https://www.cnblogs.com/FrankTan/archive/2010/03/01/1634516.html
[3] https://blog.csdn.net/dongwuming/article/details/50605911
[4] https://blog.csdn.net/ithomer/article/details/5904632
[5] https://kubernetes.io/zh-cn/docs/tasks/inject-data-application/define-command-argument-container/
[6] https://blog.csdn.net/weixin_43276033/article/details/124723106
[7] https://www.cnblogs.com/sparkdev/p/10006970.html
[8] https://blog.csdn.net/doiido/article/details/43966819
[9] https://www.cnblogs.com/chuanzhang053/p/17435306.html
[10] https://developer.aliyun.com/article/243980
[11] https://wangdoc.com/bash/string
[12] https://wangdoc.com/bash/condition
[13] https://support.huaweicloud.com/topic/193622-1-B
[14] https://www.runoob.com/linux/linux-shell-passing-arguments.html
[15] https://blog.csdn.net/u011006622/article/details/85046885
[16] https://blog.51cto.com/u_13770300/2149736
[17] https://cloud.google.com/traffic-director/docs/security-proxyless-setup-legacy?hl=zh-cn
[18] https://www.cnblogs.com/cangqinglang/p/11942567.html
[19] https://www.jianshu.com/p/5709118af1c6
[20] https://zhuanlan.zhihu.com/p/437406990?utm_id=0
[21] https://bummingboy.top/2017/12/19/shell%20-%20%E5%8F%82%E6%95%B0%E8%A7%A3%E6%9E%90%E4%B8%89%E7%A7%8D%E6%96%B9%E5%BC%8F(%E6%89%8B%E5%B7%A5,%20getopts,%20getopt)/
[22] https://developer.aliyun.com/article/471153
[23] https://cloud.tencent.com/developer/article/1629932
[24] https://www.ghosind.com/2020/10/12/shell-string
[25] https://quant67.com/post/shell/options.html

# fix disabled
```bash
#!/bin/bash
gcp_region=asia
project=my-project

function update_images() {
    local ns=$1
    deployments=$(kubectl -n $ns get deploy -o json)

    echo "$deployments" | jq -r '.items[] | select(.spec.template.metadata.labels.sms == "disabled") | .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image)' | while read -r line; do
        update_image "$ns" "$line"
    done

    echo "$deployments" | jq -r '.items[] | select(.spec.template.metadata.labels.sms == "disabled") | .metadata.name + " " + (.spec.template.spec.initContainers[] | .name + " " + .image)' | while read -r line; do
        update_image "$ns" "$line"
    done
}

function update_image() {
    local ns=$1
    local line=$2

    deploy=$(echo "$line" | cut -d ' ' -f 1)
    container=$(echo "$line" | cut -d ' ' -f 2)
    image=$(echo "$line" | cut -d ' ' -f 3)

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

# fix disable and null
如果你想同时拿到 `.spec.template.metadata.labels.sms == "disabled"` 和 `sms==null` 的部分，你可以使用逻辑或 (`||`) 来结合两个条件。以下是修改后的脚本：

```bash
function update_images() {
    local ns=$1
    deployments=$(kubectl -n $ns get deploy -o json)

    echo "$deployments" | jq -r '.items[] | select(.spec.template.metadata.labels.sms == "disabled" or .spec.template.metadata.labels.sms == null) | .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image)' | while read -r line; do
        update_image "$ns" "$line"
    done

    echo "$deployments" | jq -r '.items[] | select(.spec.template.metadata.labels.sms == "disabled" or .spec.template.metadata.labels.sms == null) | .metadata.name + " " + (.spec.template.spec.initContainers[] | .name + " " + .image)' | while read -r line; do
        update_image "$ns" "$line"
    done
}
```

在这里，我使用了 `select(.spec.template.metadata.labels.sms == "disabled" or .spec.template.metadata.labels.sms == null)` 来同时满足这两个条件。这样就可以获取到标签为 "disabled" 或者标签为空的部署。请测试并确保这满足你的要求。

如果你得到这个错误，说明有一些资源的 `.spec.template.spec.initContainers` 字段是 `null`，导致在迭代时引发错误。为了处理这种情况，你可以在 `jq` 查询中添加一些额外的检查。

以下是修改后的脚本，通过添加条件来确保 `.spec.template.spec.initContainers` 不为空：

```bash
function update_images() {
    local ns=$1
    deployments=$(kubectl -n $ns get deploy -o json)

    echo "$deployments" | jq -r '.items[] | select(.spec.template.metadata.labels.sms == "disabled" or .spec.template.metadata.labels.sms == null) | .metadata.name + " " + (.spec.template.spec.containers[] | .name + " " + .image)' | while read -r line; do
        update_image "$ns" "$line"
    done

    echo "$deployments" | jq -r '.items[] | select(.spec.template.metadata.labels.sms == "disabled" or .spec.template.metadata.labels.sms == null) | select(has("spec") and (.spec.template.spec.initContainers | length > 0)) | .metadata.name + " " + (.spec.template.spec.initContainers[] | .name + " " + .image)' | while read -r line; do
        update_image "$ns" "$line"
    done
}
```

在这里，我添加了 `select(has("spec") and (.spec.template.spec.initContainers | length > 0))` 条件来确保 `.spec.template.spec.initContainers` 不为空。这应该能够处理 `jq: error (at :1223): Cannot iterate over null (null)` 的问题。请尝试并检查是否满足你的要求。

# bash 
根据您的需求，我们可以使用Bash脚本来实现。这个脚本将首先使用您提供的命令来找到匹配的行，然后将api-version-teams.txt文件的第三列添加到匹配的行后面。以下是实现这个功能的脚本：

```bash
#!/bin/bash

# 创建一个临时文件来存储匹配的行
temp_file=$(mktemp)

# 使用您提供的命令找到匹配的行
cut -d ',' -f 1 api-version-teams.txt | grep -F -f - no-teams-apis.txt > $temp_file

# 读取临时文件中的每一行
while IFS= read -r line
do
    # 从api-version-teams.txt文件中找到匹配的行，并获取第三列
    column=$(grep "${line%% *}" api-version-teams.txt | cut -d ',' -f 3)

    # 将第三列添加到匹配的行后面
    echo "$line $column"
done < "$temp_file"

# 删除临时文件
rm $temp_file
```

这个脚本首先创建了一个临时文件来存储匹配的行。然后，它读取临时文件中的每一行，并从api-version-teams.txt文件中找到匹配的行，获取第三列。最后，它将第三列添加到匹配的行后面，并输出结果[1][2][3][6][7][8]。

Citations:
[1] https://blog.csdn.net/fjssharpsword/article/details/73742361
[2] https://cloud.tencent.com/developer/article/1366507
[3] https://www.runoob.com/w3cnote/shell-read-line.html
[4] https://blog.csdn.net/qq_35902025/article/details/129974302
[5] http://lixingcong.github.io/2015/10/31/sed/
[6] https://blog.csdn.net/Asa_Prince/article/details/111944942
[7] https://www.cnblogs.com/lasclocker/p/5981597.html
[8] https://www.cnblogs.com/dwdxdy/archive/2012/07/25/2608816.html
[9] https://www.yiibai.com/bash/bash-read-file.html
[10] https://cloud.tencent.com/developer/ask/sof/1372553
[11] https://101.lug.ustc.edu.cn/Ch06/
[12] https://blog.csdn.net/cen50958/article/details/90108677
[13] https://juejin.cn/s/shell%E5%9C%A8%E6%96%87%E4%BB%B6%E4%B8%AD%E5%A2%9E%E5%8A%A0%E4%B8%80%E5%88%97%E5%88%97
[14] https://blog.csdn.net/qq_21933797/article/details/118284891
[15] https://www.cnblogs.com/iloveyoucc/archive/2012/07/10/2585529.html
[16] http://bbs.chinaunix.net/thread-582846-1-1.html
[17] https://blog.csdn.net/JWbonze/article/details/124731041
[18] https://cloud.tencent.com/developer/article/1910386
[19] https://www.cnblogs.com/5201351/p/14799609.html
[20] http://blog.itpub.net/69955379/viewspace-2772407/
[21] https://www.jianshu.com/p/d990bf4d0bee
[22] https://zhidao.baidu.com/question/1672291922074554747.html
[23] https://renqlsysu.github.io/2021/10/19/linux_ascii_method/
[24] https://cloud.tencent.com/developer/article/2129028
