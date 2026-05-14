对于无法直接登录的GKE (Google Kubernetes Engine) 节点，您仍然有几种方法可以获取节点信息，包括Linux版本。以下是一些常用的方法：

1. 使用 kubectl 命令:
   您可以使用 kubectl 命令来获取节点信息。虽然这不会直接给出Linux版本，但可以提供一些有用的信息：

   ```
   kubectl get nodes -o wide
   ```

   这会显示节点的一些基本信息，包括操作系统镜像。

2. 使用 kubectl describe:
   这个命令可以提供更详细的节点信息：

   ```
   kubectl describe node <node-name>
   ```

3. 使用 DaemonSet:
   您可以创建一个 DaemonSet，在每个节点上运行一个 Pod，然后从该 Pod 中收集信息。例如：

   ```yaml
   apiVersion: apps/v1
   kind: DaemonSet
   metadata:
     name: node-info
   spec:
     selector:
       matchLabels:
         name: node-info
     template:
       metadata:
         labels:
           name: node-info
       spec:
         containers:
         - name: node-info
           image: busybox
           command: ["/bin/sh", "-c", "uname -a > /host/node-info.txt && sleep infinity"]
           volumeMounts:
           - name: host
             mountPath: /host
         volumes:
         - name: host
           hostPath:
             path: /tmp
   ```

   部署这个 DaemonSet 后，您可以进入 Pod 并查看 `/tmp/node-info.txt` 文件的内容。

4. 使用 Node Problem Detector:
   Google Cloud 提供了一个名为 Node Problem Detector 的工具，可以收集节点级别的信息。您可以配置它来收集所需的信息。

5. 使用 Google Cloud Console:
   在 Google Cloud Console 中，您可以查看节点池的详细信息，包括操作系统镜像版本。

6. 使用 gcloud 命令:
   您可以使用 gcloud 命令来获取节点池信息：

   ```
   gcloud container node-pools describe <pool-name> --cluster <cluster-name> --zone <zone>
   ```

这些方法中，使用 DaemonSet 可能是获取具体 Linux 版本最直接的方式。
