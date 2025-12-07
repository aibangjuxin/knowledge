Events:
Type Reason Age From Message

---

Normal Scheduled 111s default-scheduler Successfully assigned lex/nginx-deployment-gemini-779d6ddfc7-fpk99 to qnap-k3s-q21ca01210
Warning Failed 98s (x2 over 111s) kubelet Failed to pull image "nginx:1.14.2": rpc error: code = Unknown desc = failed to pull and unpack image
"docker.io/library/nginx:1.14.2": failed to resolve reference "docker.io/library/nginx:1.14.2": failed to do request: Head
"<https://registry-1.docker.io/v2/library/nginx/manifests/1.14.2>": dial tcp 162.220.12.226:443: connect: connection refused
Normal Pulling 71s (x3 over 111s) kubelet Pulling image "nginx:1.14.2"
Warning Failed 11s kubelet Failed to pull image "nginx:1.14.2": rpc error: code = Unknown desc = failed to pull and unpack image
"docker.io/library/nginx:1.14.2": failed to resolve reference "docker.io/library/nginx:1.14.2": failed to do request: Head
"<https://registry-1.docker.io/v2/library/nginx/manifests/1.14.2>": dial tcp 69.63.187.12:443: i/o timeout
Warning Failed 11s (x3 over 111s) kubelet Error: ErrImagePull
Normal BackOff <invalid> (x3 over 110s) kubelet Back-off pulling image "nginx:1.14.2"
Warning Failed <invalid> (x3 over 110s) kubelet Error: ImagePullBackOffi

镜像 tag 必须在 containerd 中存在，而不是 docker 中存在

下面根据你提供的目录结构，进一步确认 QNAP 上 Container Station 与 k3s 之间的镜像与运行时关系，并给出你当前镜像无法被 k3s 使用的根本原因和可行解决方案。

⸻

1. 问题分析：为什么你在 NAS 上 docker tag 了镜像，但 k3s Pod 仍然拉不到？

你的目录显示：

/share/CACHEDEV1_DATA/.qpkg/container-station/bin

里面有：
• docker
• dockerd
• system-docker
• kubectl
• lxc
• busybox
• supervisord

重点：QNAP 的 docker 和 k3s 的 containerd 是两个不同的运行时。
你用 docker pull / docker tag 的镜像不会自动进入 k3s 所使用的 containerd。

这就是你看到 ImagePullBackOff 的真正原因。

⸻

2. QNAP 上实际结构（非常关键）

组件 使用者 路径 是否你能直接用
Docker Container Station /share/.../docker ✔
system-docker QNAP 内部系统 /share/.../system-docker ✘（不要动）
containerd k3s /var/lib/rancher/k3s/agent/containerd ✔ 但不可直接操作
crictl k3s /var/lib/rancher/k3s/data/.../bin/crictl ✔（用于导入镜像）

因此：

docker ≠ k3s 的运行时

你：

docker pull nginx:1.21.3-alpine
docker tag nginx:1.21.3-alpine nginx:1.14.2

→ 这个镜像只进入 QNAP Container Station
→ k3s 的 containerd 完全看不见

⸻

3. 解决方案（你现在要选一个方式）

✅ 方法 1（推荐）：把 docker 镜像导出 → 导入到 k3s 的 containerd

① 在 NAS 上导出 docker 镜像

docker save nginx:1.14.2 -o /tmp/nginx-1.14.2.tar

② 找到 k3s 内置的 ctr（路径每台机器不同）

通常：

find /var/lib/rancher/k3s -name ctr

假设找到：

/var/lib/rancher/k3s/data/<hash>/bin/ctr

③ 导入镜像到 k3s（关键）

/var/lib/rancher/k3s/data/<hash>/bin/ctr -n k8s.io images import /tmp/nginx-1.14.2.tar

④ 验证 containerd 镜像是否可用

crictl images

应该能看到：

nginx 1.14.2 <IMAGE-ID>

此时：

Pod 就能使用它，不会再从 docker.io 拉取镜像。

⸻

✅ 方法 2：在 Pod 上设置 imagePullPolicy=Never

如果镜像已导入 containerd，则可以避免拉取：

imagePullPolicy: Never

但要配合 ctr/crictl 导入镜像使用。

⸻

✅ 方法 3：给 k3s 配置本地 registry（高级但强大）

你也可以在 NAS 上建一个本地私有 registry：

docker run -d -p 5000:5000 --restart=always --name registry registry:2

然后 k3s 配置：

/etc/rancher/k3s/registries.yaml

⸻

4. 用流程图帮你确认正确流程

graph TD
A["你使用 docker pull/tag"] --> B["镜像进入 QNAP Container Station"]
B --> C["k3s 使用 containerd（不同镜像库）"]
C --> D["Pod 无法找到镜像 → ImagePullBackOff"]

    D --> E["解决：docker save 导出镜像"]
    E --> F["使用 ctr/crictl 导入到 k3s containerd"]
    F --> G["Pod 直接使用本地镜像，成功运行"]

⸻

5. 注意事项
   • 千万不要修改 system-docker 的内容（破坏 QTS 系统）
   • 不要误把 docker 镜像当成 k3s 镜像
   • k3s 的 containerd 镜像必须用 ctr/crictl 导入
   • 导入镜像后可设置：imagePullPolicy: IfNotPresent
   • 导入后如仍失败，需检查：kubectl describe pod

⸻

✅ 我可以继续帮你自动生成以下内容：
• ✔ 适用于 QNAP 的镜像导入脚本（.sh）
• ✔ 自动检测 ctr / crictl 的路径
• ✔ 自动导入镜像到 k3s containerd
• ✔ 生成一个 nginx Deployment 模版（使用本地镜像）

你想让我生成吗？
