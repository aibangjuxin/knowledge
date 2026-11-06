# Docker 镜像离线打包与压缩（dexidp/dex 实测）

> **一句话结论**:`docker save` 出来的 tar 内部各层**已经是 gzip 压缩过的 blob**,所以 `docker save | gzip` 几乎压不动(46MB → 45MB)。
> 想真正减小体积,必须**把每一层解 gzip 后换更强的算法(zstd/xz)重新压缩**,并**裁掉不需要的平台**。
> 实测 `dexidp/dex:latest`:多平台 96MB → **单平台 37.7MB(省 60%)**,且 `docker load` 后镜像可正常运行的。

---

## 1. 实测数据(本次真实产出)

环境:Docker **29.0.1**(containerd 镜像存储)、arm64 MacBook(Dex v2.47.0-20261106080804-62cfc03b)

| 产物 | 体积 | 说明 |
|---|---:|---|
| `docker save dexidp/dex:latest`(arm64 单平台,gzip 层) | 46 MB | 原始基线 |
| ↑ 再套一层 `gzip -9` | 45 MB | ❌ 几乎无效 |
| ↑ 再套一层 `zstd -19` | 45 MB | ❌ 几乎无效 |
| **各层换成 zstd(arm64 单平台)** | **34.1 MB** | ✅ 省 26% |
| **各层换成 xz(amd64 单平台)** | **34.2 MB** | ✅ 省 25%,压缩更慢 |
| **各层换成 zstd(amd64 单平台)** | **37.7 MB** | ✅ 兼容性最好 |
| **各层换成 zstd(amd64 + arm64 双平台)** | **71.8 MB** | ✅ 一包通吃 |
| `docker save`(双平台原始 gzip) | 96 MB | 基线 |
| `docker images` 显示 DISK USAGE | 207 MB | 本地 store 存的是**未压缩**层,不是传输体积 |

单层压缩算法对比(以 26.3MB 的 gomplate 层为例):

| 层 | gzip(原始) | zstd -19 | xz -9e |
|---|---:|---:|---:|
| gomplate 二进制层 | 26.3 MB | 18.8 MB | 16.1 MB |
| dex 二进制层 | 14.4 MB | 11.0 MB | 9.7 MB |
| alpine 根文件系统层 | 4.0 MB | 3.4 MB | 3.1 MB |
| **合计(12 层)** | **45.7 MB** | **34.0 MB** | **29.6 MB** |

---

## 2. 为什么 `docker save | gzip` 没用?

Docker 的镜像层在仓库里就是 **gzip 压缩的 blob**(`application/vnd.oci.image.layer.v1.tar+gzip`)。
`docker save` 只是把这些 blob 原样打包进 tar,内容已经是压缩态。
外层再套 gzip/zstd,等于"压压缩过的数据",熵已经被榨干 —— 46MB → 45MB 就是全部收益。

同理,本地 `docker images` 显示的 207MB 是 **containerd store 里解压后的层占用**,跟你要传的东西无关。

**正确思路**:
1. **降层数/降平台**:单平台 vs 多平台(amd64 和 arm64 各一份完整层,直接翻倍);
2. **换压缩算法**:gzip → zstd / xz(同内容再省 25%~35%);
3. **去掉镜像内容本身**(本例中 gomplate 占 98MB 未压缩,但 dex 的 entrypoint 依赖它做配置模板渲染,**不能删**,除非你完全不用 `config.docker.yaml` 模板渲染 —— 那属于改镜像,不在本文范围)。

---

## 3. 产出物

制品目录:`/Users/lex/docker-offline/dex/`

```
dex-amd64-zstd.tar     37.7 MB   ← 部署到 x86_64 服务器用这个(推荐)
dex-arm64-zstd.tar     34.1 MB   ← arm64 机器用这个
dex-multi-zstd.tar     71.8 MB   ← amd64 + arm64 通用
dex-amd64-xz.tar       34.2 MB   ← 体积最小,要求 Docker 29 / 支持 xz 层的 containerd
SHA256SUMS                      ← 传输后校验
```

配套脚本(已入库):[`../scripts/repack-oci-layers.py`](../scripts/repack-oci-layers.py)

---

## 4. 打包步骤(可复现)

### 4.1 准备:确保目标平台的层已在本机

```bash
# 目标机是 x86_64? 先把 amd64 拉下来(容器存储是按平台存的)
docker pull --platform linux/amd64 dexidp/dex:latest
docker pull --platform linux/arm64 dexidp/dex:latest
```

> ⚠️ 常见坑:在 Apple Silicon 上 `docker pull` 默认只拿到 **arm64**。
> 直接把这个包丢到 x86_64 服务器会 `exec format error`。先确认目标机架构:
> ```bash
> uname -m   # x86_64 -> amd64 ; aarch64/arm64 -> arm64
> ```

### 4.2 导出并解包成 OCI layout

```bash
docker save dexidp/dex:latest > multi.tar
mkdir -p oci && tar -xf multi.tar -C oci
ls oci          # blobs/  index.json  manifest.json  oci-layout
```

### 4.3 重压各层并裁剪平台

```bash
python3 scripts/repack-oci-layers.py oci /tmp/dex-amd64-zstd.tar \
    --platform linux/amd64 \
    --tag dexidp/dex:latest \
    --codec zstd --level 19
```

脚本做的事:
- 遍历 index → 找到目标平台的 manifest(跳过本机没有的悬空平台引用);
- 每层 `gzip -dc` → `zstd -19 --long=27` 重压,重算 digest/size,改写 mediaType 为 `...tar+zstd`;
- 重写 manifest blob、生成新的 `index.json`(带 `io.containerd.image.name` 等 annotation)、`manifest.json`、`oci-layout`;
- 重新打成 tar。

### 4.4 校验

```bash
cd /Users/lex/docker-offline/dex && shasum -a 256 -c SHA256SUMS
```

---

## 5. 传输与使用(目标机)

### 5.1 传输

```bash
scp /Users/lex/docker-offline/dex/dex-amd64-zstd.tar user@server:/tmp/
# 或带进度/断点
rsync -avP --progress /Users/lex/docker-offline/dex/ user@server:/opt/dex-images/
```

### 5.2 加载(解压使用)

```bash
cd /tmp && sha256sum dex-amd64-zstd.tar          # 与 SHA256SUMS 比对
docker load -i dex-amd64-zstd.tar
```

看到 `Loaded image: dexidp/dex:latest` 就成功了。**不需要手动解压 tar** —— `docker load` 直接吃这个 OCI archive。

如果环境是旧版 Docker、不认识 zstd 层,可以流式解压后加载,或者改用 gzip 层的包:

```bash
# 流式加载(适用于自制的 tar.gz 包)
zstd -dc dex.tar.zst | docker load
gunzip -c dex.tar.gz | docker load
```

### 5.3 验证与运行

```bash
docker images dexidp/dex                        # 确认在列表里
docker image inspect dexidp/dex:latest --format '{{.Os}}/{{.Architecture}}'
docker run --rm dexidp/dex:latest dex version   # 应输出 Dex Version: v2.47.0-...
```

跨架构时(arm64 上跑 amd64 包)需要 qemu 模拟,显式指定平台:

```bash
docker run --rm --platform linux/amd64 dexidp/dex:latest dex version
```

### 5.4 用 docker-compose / k8s 部署

加载后镜像名保持 `dexidp/dex:latest`,compose 文件里直接写 `image: dexidp/dex:latest` 即可,
不需要在服务器上改任何配置(注意 `imagePullPolicy: IfNotPresent` 或 `Never`,避免它去联网拉取)。

---

## 6. 兼容性说明

| 环境 | 建议 |
|---|---|
| Docker ≥ 25 + containerd 镜像存储(实测 29.0.1) | ✅ zstd / xz 层都能 `docker load` |
| Docker 24 及更早(classic store) | ⚠️ 可能报未知 mediaType,用 `--keep-gzip` 重新打包,或用传统 `docker save \| gzip` |
| 目标机完全离线 | ✅ 本方案不需要 registry,`docker load` 后本地就有 |

降级方案(任何 Docker 都能用,体积基本不省):

```bash
docker save dexidp/dex:latest | gzip -1 > dex.tar.gz
docker load -i dex.tar.gz
```

---

## 7. 常见坑

1. **丢 tag**:`docker load` 后 `docker images` 看不到名字。
   原因是 containerd 镜像存储从 `index.json` 的 `annotations`(`io.containerd.image.name` / `org.opencontainers.image.ref.name`)取名字,不是从 `manifest.json` 的 `RepoTags`。
   本脚本已写入这些 annotation。
2. **架构不匹配**:Apple Silicon 默认拉 arm64,传到 x86 服务器报 `exec format error`。
   解法:`docker pull --platform linux/amd64` 后再打包(见 4.1)。
3. **"省了很多体积"的错觉**:`docker images` 的 DISK USAGE 是解压后的本地占用,别拿它跟 tar 包比。
4. **别再套一层压缩**:zstd 层包外面再 gzip,只会多花 CPU 不省空间。
5. **`--platform` 别写 `linux/arm`**:arm/v7 的层本机根本没有,写了会被跳过。

---

## 8. 脚本速查

```bash
python3 scripts/repack-oci-layers.py <oci_dir> <out.tar> \
    [--platform linux/amd64] [--platform linux/arm64] \   # 不给=保留全部本地平台
    [--tag repo:tag] \                                     # 决定 load 后的镜像名
    [--codec zstd|xz] [--level 19] \                       # 压缩算法与级别
    [--keep-gzip]                                         # 只裁平台,不重压(兼容老 Docker)
```

依赖:`zstd`(xz 模式还需要 `xz`)、`gzip`、Python 3.8+。
