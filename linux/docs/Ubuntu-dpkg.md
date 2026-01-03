当查询 Ubuntu 主机的内核版本、系统版本或安装包版本时，可以使用以下命令：

1. 查询内核版本：
```bash
uname -r
```

2. 查询系统版本：
```bash
lsb_release -a
```

3. 查询特定软件包的版本（例如，查询 Nginx 的版本）：
```bash
nginx -v
```

4. 查询所有已安装软件包的版本：
```bash
dpkg -l
```

这些命令将分别提供所需信息的详细输出。
在 Ubuntu 中，你可以使用以下命令在线升级内核：

```bash
sudo apt update
sudo apt upgrade linux-image-generic linux-headers-generic
```

这些命令将更新你的系统中的通用 Linux 内核镜像和头文件包到最新版本。确保在执行这些命令之前先运行 `sudo apt update` 来更新软件包列表。

