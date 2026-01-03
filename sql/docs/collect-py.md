这个Python脚本主要实现了以下功能:

1. 导入所需的库和模块。
2. 设置日志记录器,以便跟踪执行过程中的日志信息。
3. 定义一个函数 `time_format`,用于格式化时间戳。
4. 定义一个函数 `api_name_filter`,根据 Kubernetes Pod 的名称,提取出相关的 API 名称、版本信息等。
5. 定义一个主要函数 `create_request_to_push`,用于从 Kubernetes 集群获取所有 Pod 的信息,过滤出需要的数据,并将结构化的数据以 JSON 格式上传到 Google Cloud Storage 存储桶中。
6. 定义一个函数 `create_job`,用于启动一个调度器,每 15 分钟执行一次 `create_request_to_push` 函数。
7. 在脚本的主入口点,调用 `create_job` 函数,启动调度器。

下面是每个主要部分的逻辑介绍:

1. 导入库和设置日志记录器:这部分代码导入了所需的 Python 库,并设置了一个日志记录器,用于跟踪脚本执行过程中的日志信息。

2. `time_format` 函数:这个函数接受一个 `datetime` 对象作为参数,并将其格式化为指定的字符串格式。

3. `api_name_filter` 函数:这个函数接受一个 Kubernetes Pod 的名称作为参数,并通过正则表达式提取出相关的 API 名称、版本信息等。根据 Pod 名称的不同格式,函数会返回不同的结果。

4. `create_request_to_push` 函数:这是脚本的核心函数,它执行以下操作:
   - 加载 Kubernetes 集群配置
   - 获取所有命名空间下的 Pod 信息
   - 遍历每个 Pod,使用 `api_name_filter` 函数提取相关信息
   - 构造一个包含所需 Pod 信息的字典列表
   - 将字典列表转换为 JSON 格式的字符串
   - 根据环境变量确定 Google Cloud Storage 存储桶的名称
   - 将 JSON 数据上传到指定的存储桶中

5. `create_job` 函数:这个函数使用了 `schedule` 库,创建了一个调度器,每 15 分钟执行一次 `create_request_to_push` 函数。

6. 主入口点:脚本的主入口点调用了 `create_job` 函数,启动了调度器。

总的来说,这个脚本的主要目的是从 Kubernetes 集群中获取所有 Pod 的信息,过滤出需要的数据,并将其以 JSON 格式上传到 Google Cloud Storage 存储桶中,这个过程会每 15 分钟重复执行一次。


要获取 Pod 当前的 CPU 和内存使用量,我们需要使用 Kubernetes API 的 metrics.k8s.io 组件。以下是修改后的完整代码样例:

```python
# Fetch pods data from gke master and send to bucket
def create_request_to_push():
    log.info("inside create_request_to_push")
    config.load_inclusters_config()
    log.info("after config load")
    log.info("Retrieving pods data")
    core_v1 = client.CoreV1Api()
    metrics_v1beta1 = client.MetricsV1beta1Api()
    ret = core_v1.list_pod_for_all_namespaces(watch=False)
    env = os.getenv("API_PLATFORM_ENV")
    region = os.getenv("API_PLATFORM_REGION")
    pods_data = []
    for item in ret.items:
        try:
            if item.metadata.namespace not in ("kube-system", "cos-auditd", "gmp-system", "gmp-public", "istio-operator", "istio-system", "kube-node-lease", "kube-public", "gremlin"):
                api_name, api_name_with_major_version, major_version, minor_version = api_name_filter(item.metadata.name)
                # 获取 Pod 的 CPU 和内存使用量
                pod_metrics = metrics_v1beta1.read_namespaced_pod_metrics(name=item.metadata.name, namespace=item.metadata.namespace)
                pod = {
                    "api_name": api_name,
                    "api_name_with_major_version": api_name_with_major_version,
                    "env": env,
                    "region": region,
                    "cpu_request": item.spec.containers[0].resources.requests.get("cpu") if item.spec.containers[0].resources.requests else None,
                    "cpu_limit": item.spec.containers[0].resources.limits.get("cpu") if item.spec.containers[0].resources.limits else None,
                    "memory_request": item.spec.containers[0].resources.requests.get("memory") if item.spec.containers[0].resources.requests else None,
                    "memory_limit": item.spec.containers[0].resources.limits.get("memory") if item.spec.containers[0].resources.limits else None,
                    "node_name": item.spec.node_name,
                    "service_account_name": item.spec.service_account_name,
                    "current_cpu_usage": pod_metrics.containers[0].usage.cpu,  # 新增当前 CPU 使用量
                    "current_memory_usage": pod_metrics.containers[0].usage.memory  # 新增当前内存使用量
                }
                pods_data.append(pod)
            else:
                pass
        except Exception as e:
            log.error(e, item.metadata.name)

    # 后续代码保持不变
```

在修改后的代码中,我们引入了 `client.MetricsV1beta1Api()` 来获取 Pod 的指标数据。在 `create_request_to_push` 函数中,我们使用 `metrics_v1beta1.read_namespaced_pod_metrics` 方法获取指定 Pod 的指标数据,其中包括当前的 CPU 和内存使用量。

然后,我们在构造 Pod 信息字典时,新增了 `current_cpu_usage` 和 `current_memory_usage` 两个键,分别存储当前的 CPU 和内存使用量。

其他部分的代码保持不变。这样,在上传到 Google Cloud Storage 的 JSON 数据中,就会包含每个 Pod 当前的 CPU 和内存使用量信息了。

注意,这个修改需要在 Kubernetes 集群中启用了 metrics.k8s.io 组件,否则可能会出现错误。如果遇到任何问题,请查看日志并进行相应的调试和排查。
