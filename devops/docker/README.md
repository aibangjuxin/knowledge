# Docker 镜像离线打包与压缩

> **一句话结论**:`docker save` 出来的 tar 里面每一层**已经是 gzip 压缩过的 blob**,
> 所以 `docker save | gzip` 几乎压不动(实测 46MB → 45MB)。
> 真正能减小体积的做法是:**裁掉不需要的平台 + 把每层换用更强的算法(zstd/xz)重新压缩**。
> 实测 `dexidp/dex:latest`:多平台 96MB → **单平台 37.7MB(省 60%)**,`docker load` 后可直接运行。

---

## 目录

| 文档 | 内容 | 适合谁 |
|---|---|---|
| [01-offline-image-packaging.md](docs/01-offline-image-packaging.md) | 原理 + 实测数据 + 打包/传输/加载/部署完整步骤 + 兼容性 + 常见坑 | 要把镜像搬到离线服务器 / 嫌包太大的人 |

配套脚本:[`scripts/repack-oci-layers.py`](scripts/repack-oci-layers.py)

---

## 速查卡

| 维度 | 事实 |
|---|---|
| 目标 | 把本地已 `pull` 的镜像打成 tar,压缩后离线搬运到目标服务器 `docker load` |
| 关键认知 | 镜像层在仓库里就是 gzip blob;外层再压 = 压压缩过的数据,无效 |
| 有效手段 | ① 单平台裁剪 ② 层重压 gzip → zstd(-19)/xz(-9e) ③ 补 `index.json` annotation 保证 load 后有 tag |
| 实测收益 | `dexidp/dex` 多平台 96MB → amd64 单平台 zstd **37.7MB** / xz **34.2MB** |
| 产物位置 | `/Users/lex/docker-offline/dex/`(含 `SHA256SUMS`) |
| 加载方式 | `docker load -i xxx.tar`(不需要手动解压;老环境用 `zstd -dc xxx.tar \| docker load`) |
| 兼容底线 | Docker ≥ 25 / containerd 镜像存储;更老的用 `--keep-gzip` 重新打包 |
| 头号坑 | Apple Silicon 默认拉 arm64,传到 x86 服务器会 `exec format error` |

---

## 30 秒版

```bash
# 1) 目标机是 x86_64 的话,先把 amd64 拉下来
docker pull --platform linux/amd64 dexidp/dex:latest

# 2) 导出 + 解包成 OCI layout
docker save dexidp/dex:latest > multi.tar
mkdir -p oci && tar -xf multi.tar -C oci

# 3) 重压各层 + 裁平台
python3 scripts/repack-oci-layers.py oci /tmp/dex-amd64-zstd.tar \
    --platform linux/amd64 --tag dexidp/dex:latest --codec zstd --level 19

# 4) 传输
rsync -avP /tmp/dex-amd64-zstd.tar user@server:/tmp/

# 5) 目标机加载并验证
docker load -i /tmp/dex-amd64-zstd.tar
docker run --rm dexidp/dex:latest dex version
```
