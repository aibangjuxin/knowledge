在GKE的Pod中进行内存回收可以通过多种方式进行，具体取决于您希望如何管理和优化内存使用。以下是几种常见的内存回收方法：

### 方法一：重新启动Pod

重新启动Pod是最简单和直接的方法。这会清除Pod的所有内存使用，但也会导致服务短暂中断。

```sh
kubectl delete pod <pod-name>
```

### 方法二：使用自动内存管理工具

使用像`Heapster`、`Prometheus`或`Kubernetes Metrics Server`等工具监控内存使用，并自动进行资源管理和回收。

### 方法三：配置资源限制

为Pod设置资源请求和限制，可以防止Pod占用过多内存，并在达到内存限制时强制进行内存回收。

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example-pod
spec:
  containers:
  - name: example-container
    image: your-image
    resources:
      requests:
        memory: "256Mi"
      limits:
        memory: "512Mi"
```

### 方法四：使用自定义的内存管理脚本

可以编写一个自定义的内存管理脚本，定期清理不需要的内存占用，例如删除大文件或停止特定进程。

#### 示例：Shell脚本清理内存

```sh
#!/bin/sh
# 释放缓存
sync; echo 3 > /proc/sys/vm/drop_caches

# 删除临时文件
rm -f /tmp/bigfile

# 停止占用内存的进程
pkill -f "cat /tmp/bigfile"
pkill -f "python -c"
```

将上述脚本放入Pod并定期执行，确保内存占用得到有效管理和回收。

### 方法五：在应用程序中管理内存

确保应用程序有适当的内存管理机制，例如：
- 定期清理不再需要的数据
- 使用高效的数据结构
- 优化算法以减少内存占用

### 方法六：使用CronJob定期清理

可以创建一个Kubernetes CronJob，定期运行清理脚本。

#### 示例：CronJob清理内存

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: memory-cleaner
spec:
  schedule: "0 * * * *"  # 每小时执行一次
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleaner
            image: busybox
            command: ["/bin/sh", "-c"]
            args: ["sync; echo 3 > /proc/sys/vm/drop_caches"]
          restartPolicy: OnFailure
```

### 总结

通过重新启动Pod、使用自动内存管理工具、配置资源限制、自定义内存管理脚本、优化应用程序内存使用或定期运行清理CronJob等方式，可以在GKE的Pod中有效地进行内存回收。选择适合您需求的方法，确保Pod内存使用得到良好的控制和管理。

