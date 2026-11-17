可以。先把镜像导出为 `.tar` 文件，以后用 `docker load` 导回来即可。 [docs.siderolabs](https://docs.siderolabs.com/omni/self-hosted/run-omni-airgapped)

## 保存镜像

建议先固定一个具体版本，避免 `latest` 以后变化：

```bash
docker pull dexidp/dex:latest
docker save -o dex.tar dexidp/dex:latest
```

或保存为压缩文件，体积更小：

```bash
docker save dexidp/dex:latest | gzip > dex.tar.gz
```

`docker save` 会把本地镜像保存成 tar 归档文件，可用于离线传输或备份。 [docs.siderolabs](https://docs.siderolabs.com/omni/self-hosted/run-omni-airgapped)

## 之后再导入

```bash
docker load -i dex.tar
```

如果是 gzip 压缩版：

```bash
docker load -i dex.tar.gz
```

导入后确认：

```bash
docker images | grep dex
```

`docker load` 会把 tar 文件中的镜像重新载入本地 Docker 镜像存储。 [docs.siderolabs](https://docs.siderolabs.com/omni/self-hosted/run-omni-airgapped)

## 注意

- `docker save` 保存的是**镜像**；不要用 `docker export`，那是导出容器文件系统，不保留镜像历史和元数据。 [github](https://github.com/mylxsw/growing-up/blob/master/doc/Docker%E7%AE%80%E6%98%8E%E6%95%99%E7%A8%8B.md)
- 如果你要在另一台机器运行，导入后直接：

```bash
docker run -d --name dex -p 5556:5556 dexidp/dex:latest
```

- 若目标机器架构不同（例如 x86 与 ARM），最好在拉取时就指定对应平台，例如：

```bash
docker pull --platform linux/amd64 dexidp/dex:latest
```

Docker Hub 上 Dex 镜像提供 amd64、arm64 等多架构版本。 [hub.docker](https://hub.docker.com/r/dexidp/dex/tags)

```bash
x docker pull dexidp/dex
Using default tag: latest
latest: Pulling from dexidp/dex
d3531b7a4f21: Pull complete
11beb3df3c6d: Pull complete
c7883fe377f7: Pull complete
9da899fac2bd: Pull complete
d41dc7881ab2: Pull complete
44fb28049c68: Pull complete
184ed546ad4a: Pull complete
046f776a4ebe: Pull complete
d4b26497a08b: Pull complete
69455578a261: Pull complete
6e92f1468491: Pull complete
714ca124c048: Pull complete
Digest: sha256:73bf88b2cd21682d3185162625ff3c0c0a9524b3412311714ddf652a79f6224e
Status: Downloaded newer image for dexidp/dex:latest
docker.io/dexidp/dex:latest

docker save dexidp/dex:latest | gzip > dex.tar.gz
✗ du -sh dex.tar.gz
 45M    dex.tar.gz
```