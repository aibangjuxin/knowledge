# crane：无 Docker daemon 的镜像操作 CLI

> **一句话结论**
> ★ `crane` 是 Google 开源的 [go-containerregistry](https://github.com/google/go-containerregistry) 里的命令行工具，
> **不依赖 Docker daemon、不需要本地镜像库**，直接对着 registry 的 HTTP API 操作容器镜像。
> 它的价值在于：**可以只看不动（查 digest/manifest）、可以整镜像搬家（copy 且保留 digest）、
> 可以给镜像「加一层 / 改元数据」（append / mutate）**——
> 这三件事用 `docker` 都做不了或做得很别扭。

本机实测版本：**crane 0.22.1**（`brew install crane`，2026-11-24），
所有命令输出均为真实执行结果，不是文档抄写。

---

## 目录

- [1. 它是什么 / 什么时候该用它](#1-它是什么--什么时候该用它)
- [2. 安装与认证](#2-安装与认证)
- [3. 必须先懂的 6 个概念](#3-必须先懂的-6-个概念)
- [4. 命令地图（22 个子命令）](#4-命令地图22-个子命令)
- [5. 十个实战场景（带实测输出）](#5-十个实战场景带实测输出)
- [6. 坑清单（12 条，全部实测）](#6-坑清单12-条全部实测)
- [7. 与 docker / skopeo / regctl / cosign 怎么选](#7-与-docker--skopeo--regctl--cosign-怎么选)
- [8. 在 Cloud Build / GAR 流水线里怎么用](#8-在-cloud-build--gar-流水线里怎么用)
- [9. 交叉引用](#9-交叉引用)
- [10. 官方文档与源码](#10-官方文档与源码)

---

## 1. 它是什么 / 什么时候该用它

### 定位

| 维度 | 说明 |
| :--- | :--- |
| 出身 | Google 的 `google/go-containerregistry`（GCR 客户端库），`crane` 是它的 CLI 前端 |
| 语言 | Go，单静态二进制，无运行时依赖 |
| 通信方式 | 直接实现 OCI Distribution Spec（`/v2/` API），**不需要 dockerd、不需要 containerd、不需要本地镜像库** |
| 能力边界 | 只管**镜像（image）**：manifest / config / layer / index / tag / digest。**不跑容器**（那是 docker/runc 的事） |
| 典型场景 | CI 里搬镜像、查镜像真身、给镜像加层改配置、离线导出镜像、多架构裁剪 |

### 和 docker 命令的对应关系

| 你想干的事 | docker | crane |
| :--- | :--- | :--- |
| 看镜像真身（digest） | `docker inspect` / `docker manifest inspect` | `crane digest` / `crane manifest` |
| 拉镜像到本地 | `docker pull`（要 daemon，占几百 MB） | `crane pull`（直接写 tarball/OCI 目录） |
| 推镜像 | `docker push`（要 daemon） | `crane push` / `crane copy` |
| 跨仓库搬运 | `docker tag` + `docker push`（**digest 会变**） | `crane copy`（**digest 不变**） |
| 给镜像加一层 | 只能 `Dockerfile` + `docker build` | `crane append`（一行命令，不跑构建） |
| 改 entrypoint/env/label | `docker commit` 或改 Dockerfile 重建 | `crane mutate`（不重建层） |
| 离线导出 | `docker save` | `crane export`（文件系统 tar）/ `crane pull`（镜像 tarball） |

### 什么时候**不该**用它

- 要**运行**容器 → 用 `docker run` / `podman run` / `kubectl`；
- 要**构建**镜像 → 用 `docker build` / `kaniko` / `buildpacks` / Cloud Build；
- 要**签名与验签** → 用 `cosign`（crane 不做签名）；
- 要**扫漏洞** → 用 `trivy` / `grype` / Artifact Analysis（crane 只能把镜像取出来给你扫）。

---

## 2. 安装与认证

### 安装

```bash
brew install crane            # macOS / Linux
# 或直接下二进制（静态链接）
# https://github.com/google/go-containerregistry/releases
crane version                 # 0.22.1
```

### 认证

crane 读 `~/.docker/config.json`（与 docker 共享凭证），
也可以用 docker 的 credential helper（`crane auth get` 就是一个 helper 实现）。

```bash
# 普通 registry
crane auth login reg.example.com -u USER -p 'PASSWORD'
crane auth login reg.example.com -u USER --password-stdin < token.txt   # 更安全

# 读凭证（作为 docker credential helper 用）
crane auth get reg.example.com
# {"Username":"USER","Secret":"******"}
```

**GCP / Artifact Registry（GAR）**——用户名固定是 `oauth2accesstoken`，密码是 access token：

```bash
export GAR_HOST=asia-northeast1-docker.pkg.dev
export GAR_REPO=asia-northeast1-docker.pkg.dev/example-project/my-app

crane auth login "$GAR_HOST" \
  -u oauth2accesstoken \
  -p "$(gcloud auth print-access-token)"

crane ls "$GAR_REPO"                      # 列出 tag
crane digest "$GAR_REPO/app:v1"           # 查 digest
crane copy "$GAR_REPO/app:v1" "$GAR_REPO/app:v2"   # 同仓库打新 tag（digest 不变）
```

> ⚠️ access token 默认 1 小时过期。CI 里每次现取，不要把 token 写进文件长期使用。
> 更稳的做法是用 Service Account 的短期 token，或在 Cloud Build 里直接用 SA 身份（无需 crane 登录）。

---

## 3. 必须先懂的 6 个概念

镜像在 registry 里的结构（这一层搞不懂，crane 的命令就会看不懂）：

```
image reference = <registry>/<repo>:<tag>          人类可读的名字（可变）
                = <registry>/<repo>@sha256:xxxx    内容的唯一指纹（不可变）

digest (sha256:xxxx)  ← 由 manifest 字节算出来，改任何一点就变
   │
   └── manifest      "这个镜像由哪些层组成、怎么组装"
         ├── config  "运行时信息"：entrypoint / cmd / env / labels / 工作目录 / 用户
         ├── layers  "内容 blob"（tar.gz），可与别的镜像共享
         │
index (image index)   "多架构清单"：一个 index 里有多个 manifest（amd64 / arm64 / ...）
   └── 其中 platform=unknown/unknown 的条目通常是 **attestation（provenance）** 清单
```

**crane 的每个子命令，几乎都对应上面某一层的读或写**：

| 命令 | 操作的对象 |
| :--- | :--- |
| `crane digest` / `crane manifest` / `crane config` / `crane blob` | 读 manifest / config / layer |
| `crane ls` / `crane catalog` | 读 tag 列表 / repo 列表 |
| `crane index list` | 读 index 里的各个 manifest |
| `crane copy` / `crane tag` / `crane push` / `crane delete` | 写 manifest / tag |
| `crane append` / `crane mutate` / `crane flatten` / `crane rebase` | **改**镜像（层或 config） |
| `crane pull` / `crane export` / `crane validate` | 取回本地 |

---

## 4. 命令地图（22 个子命令）

```bash
crane --help
```

### 只读（不下载层，最快，占用带宽最少）

| 命令 | 作用 |
| :--- | :--- |
| `crane digest IMAGE` | 取 digest（只 HEAD manifest，不拉层） |
| `crane manifest IMAGE` | 输出 manifest JSON |
| `crane config IMAGE` | 输出 image config JSON（entrypoint/env/labels/架构） |
| `crane blob BLOB` | 取单个 layer blob（可重定向成 .tar.gz） |
| `crane ls REPO` | 列 repo 下的 tag |
| `crane catalog REGISTRY` | 列 registry 下的 repo |
| `crane index list IMAGE` | 列出 index 内每个 manifest 及其 platform |
| `crane validate --remote IMAGE` | 校验远端镜像结构完整性 |

### 搬运 / 发布

| 命令 | 作用 |
| :--- | :--- |
| `crane copy SRC DST` | **跨 registry / 跨 repo 搬运，保留 digest**（别名 `cp`） |
| `crane tag IMG TAG` | 在**同一 repo** 内加一个 tag（不下载内容） |
| `crane push PATH IMAGE` | 推本地 tarball / OCI layout 到 registry |
| `crane delete IMAGE` | 删 tag（manifest 与 blob 仍在） |

### 改镜像（crane 的杀手锏）

| 命令 | 作用 | 典型用途 |
| :--- | :--- | :--- |
| `crane append` | **给镜像加一层**（`--new_layer` tarball） | 补 CA 证书、塞配置、应急打补丁 |
| `crane mutate` | 改 config：entrypoint / cmd / env / label / annotation / user | 改启动参数、加环境变量、打标记 |
| `crane flatten` | 把多层压成一层 | 减小体积、清理层历史 |
| `crane rebase` | 把镜像的 base 换成另一个 | 换基础镜像（保留上层改动） |
| `crane index append / filter` | 组装 / 裁剪多架构 index | 做私有多架构镜像 |

### 取回本地 / 本地环境

| 命令 | 作用 |
| :--- | :--- |
| `crane pull IMAGE TARBALL` | 拉成 docker 风格 tarball（默认）或 OCI 目录（`--format=oci`） |
| `crane export IMAGE TARBALL` | 导出**合并后的文件系统** tar（可直接解包部署） |
| `crane validate --tarball FILE` | 校验本地 tarball 是否自洽 |
| `crane registry serve` | **起一个本地 registry**（内存/磁盘），测试用 |

### 全局 flag（对所有子命令有效）

```bash
--platform linux/amd64      # 指定架构（默认 all，即多架构 index）
--insecure                  # 允许 HTTP / 跳过 TLS 校验（自建 registry 用）
--allow-nondistributable-artifacts
-v, --verbose               # 打印完整 HTTP 交互（排错神器）
```

---

## 5. 十个实战场景（带实测输出）

> 前置：起一个本地 registry 当「靶子」，不需要 Docker。
> ```bash
> crane registry serve --address 127.0.0.1:5555 --disk /tmp/crane-registry &
> curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5555/v2/    # → 200
> ```

### S1 · 查镜像真身，不下载任何层

```bash
$ crane digest index.docker.io/library/alpine:3.19
sha256:6baf43584bcb78f2e5847d1de515f23499913ac9f12bdf834811a3145eb11ca1

$ crane config index.docker.io/library/alpine:3.19 | head -c 120
{"architecture":"amd64","config":{"Env":["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],"Cmd":["/bin/sh"],"WorkingDir":"/"}
```

**用途**：CI 里校验「我以为推上去了的镜像」到底是哪一份；对比 tag 是否被覆盖。
**成本**：只有 manifest 的 HEAD/GET，几十 KB，不受镜像体积影响。

### S2 · 跨仓库搬运，**digest 保持不变**

```bash
$ crane copy index.docker.io/library/alpine:3.19 127.0.0.1:5555/demo/alpine:3.19
2026/11/24 10:03:56 pushed blob: sha256:6098877f...
2026/11/24 10:03:56 127.0.0.1:5555/demo/alpine@sha256:5d8c15d7...: digest: sha256:5d8c15d7... size: 838
2026/11/24 10:03:56 127.0.0.1:5555/demo/alpine:3.19: digest: sha256:6baf4358... size: 8077
                                                    ↑ 与源仓库的 digest 完全一致
```

**这是 crane 与 `docker tag` + `docker push` 的本质区别**：
docker 重新打包会改变 digest，crane 是**逐 blob 复制**，所以镜像的「身份」不变。

**用途**：把 Docker Hub 的镜像「原样」搬进 GAR（合规要求保留原始 digest 时）；跨集群/跨账号同步。

### S3 · 多架构裁剪（解决 Apple Silicon 拉成 arm64 的坑）

```bash
$ crane copy --platform linux/amd64 index.docker.io/library/alpine:3.19 127.0.0.1:5555/demo/alpine:amd64-only
2026/11/24 10:04:44 127.0.0.1:5555/demo/alpine:amd64-only: digest: sha256:b58899f0... size: 1022

$ crane manifest 127.0.0.1:5555/demo/alpine:amd64-only | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["mediaType"], len(d["layers"]))'
application/vnd.oci.image.manifest.v1+json 1
```

**效果**：原本是 index（多架构 + attestation，共 13 个 manifest），
裁剪后变成**单一 amd64 manifest，只有 1 层**。
→ 体积骤降、**没有 arm64/x86 混用导致的 `exec format error`**。

> 与本仓库 [01-offline-image-packaging.md](01-offline-image-packaging.md) 配合：
> 那篇讲「怎么把镜像压小」，这篇给的是**不用 docker daemon 就能裁平台**的手段，
> 可以直接串进离线打包流程。

### S4 · 给镜像「加一层」（append）

```bash
$ echo 'hello-from-crane' > /tmp/extra/hello.txt
$ tar -C /tmp/extra -cf /tmp/layer.tar hello.txt

$ crane append --base 127.0.0.1:5555/demo/alpine:3.19 \
      --new_layer /tmp/layer.tar \
      --new_tag 127.0.0.1:5555/demo/alpine:appended
2026/11/24 10:04:01 existing blob: sha256:17a39c0b...
2026/11/24 10:04:01 127.0.0.1:5555/demo/alpine:appended: digest: sha256:6a10f1f4... size: 1052

$ crane export 127.0.0.1:5555/demo/alpine:appended /tmp/fs.tar && tar -tf /tmp/fs.tar | grep hello
hello.txt                       ← 新层真的进去了
```

**关键点**：
- 原来的层**一个都没重建**（日志里是 `existing blob`），只有新层是新 blob；
- 不需要 Dockerfile、不需要构建器、不需要 daemon，**几秒钟出一个新镜像**；
- 每次 append 都会产生**新的 digest**（层变了，manifest 就变了）。

**典型用途**：
1. 给私有 CA 装进镜像：`--new_layer ca.crt`；
2. 应急打补丁：把修好的二进制打进去再推；
3. 给 distroless 镜像塞一个 shell/证书/配置。

> ⚠️ 生产上给镜像加层会**破坏与原始镜像的 digest 对应关系**，
> 扫描、准入策略、供应链证据都会以新 digest 为准——这是好事（可追溯），但要在流程里讲清楚。

### S5 · 改镜像元数据（mutate）

```bash
$ crane mutate --repo 127.0.0.1:5555/demo/alpine \
      --cmd=-c --cmd='echo hi' \
      127.0.0.1:5555/demo/alpine:3.19
2026/11/24 10:04:30 127.0.0.1:5555/demo/alpine@sha256:18797ec5...: digest: sha256:18797ec5... size: 898

$ crane config 127.0.0.1:5555/demo/alpine@sha256:18797ec5... | python3 -c 'import json,sys; print(json.load(sys.stdin)["config"]["Cmd"])'
['-c', 'echo hi']
```

**可改的东西**：`--entrypoint` `--cmd` `--env` `--label` `--annotation`
`--user` `--workdir` `--exposed-ports` `--set-platform` `--append`（同时加层）。

**三个必须记住的规则（实测踩过）**：

| 规则 | 现象 | 正确写法 |
| :--- | :--- | :--- |
| `--cmd` / `--entrypoint` **不能传 JSON 数组** | `Error: invalid argument "[\"-c\", \"echo hi\"]" for "--cmd" flag: parse error on line 1, column 2: bare \" in non-quoted-field` | **重复传 flag**：`--cmd=-c --cmd='echo hi'` |
| `--repo` 与 `--tag` **互斥** | `Error: repository can't be set when a tag is specified` | 推**到别的 repo** 用 `--repo`；**同 repo 加 tag** 用 `--tag` |
| 用 `--repo` 时推的是 **digest 不是 tag** | 输出形如 `repo@sha256:...`，repo 里看不到新 tag | 想让它有 tag，就 `--repo X` 之后再 `crane tag X@sha256:... v1` |

### S6 · 打 tag / 删 tag

```bash
$ crane tag 127.0.0.1:5555/demo/alpine:3.19 v3.19-alias
2026/11/24 10:04:39 127.0.0.1:5555/demo/alpine:v3.19-alias: digest: sha256:6baf4358... size: 8077

$ crane ls 127.0.0.1:5555/demo/alpine
3.19
appended
v3.19-alias

$ crane delete 127.0.0.1:5555/demo/alpine:v3.19-alias
$ crane ls 127.0.0.1:5555/demo/alpine
3.19
appended
```

**`crane delete` 只删 tag**：删完之后
`crane digest 127.0.0.1:5555/demo/alpine@sha256:6baf4358...` **仍然能解析**——
manifest 与 blob 还占着存储。→ 真正省空间要靠 GAR 的 cleanup policy
（见 [gcp/artifact-registry/cleanup-policy-assessment.md](../../../gcp/artifact-registry/cleanup-policy-assessment.md)）。

### S7 · 离线导出与校验

```bash
# A) 镜像 tarball（docker 风格，可 docker load）
$ crane pull 127.0.0.1:5555/demo/alpine:3.19 /tmp/alpine.tar
$ ls -lh /tmp/alpine.tar && tar -tf /tmp/alpine.tar | head -3
-rw-r--r--  3.3M /tmp/alpine.tar
sha256:83b2b670...
17a39c0ba978...tar.gz
manifest.json

# B) 校验 tarball 自洽性（diffids 与 config 是否对得上）
$ crane validate --tarball /tmp/alpine.tar
PASS: /tmp/alpine.tar

# C) OCI layout —— 注意：产出的是「目录」，不是 tar
$ crane pull --format=oci 127.0.0.1:5555/demo/alpine:3.19 /tmp/alpine-oci
$ ls /tmp/alpine-oci
blobs
index.json
oci-layout

# D) 合并后的文件系统（直接解包即可部署，不需要容器运行时）
$ crane export 127.0.0.1:5555/demo/alpine:3.19 /tmp/fs.tar
```

**A vs C vs D 的区别**（选错了会白折腾）：

| 产物 | 形态 | 用途 |
| :--- | :--- | :--- |
| `pull`（默认 `tarball`） | 单个 tar | `docker load` / 存档 |
| `pull --format=oci` | **目录**（`blobs/` + `index.json`） | OCI layout，喂给 `crane push` 或 `podman load` |
| `pull --format=legacy` | docker legacy tar | 老版本兼容 |
| `export` | 单个 tar，**内容是合并文件系统** | 直接解包到服务器跑（无 daemon 场景） |

### S8 · 本地起 registry 做验证（无需 Docker）

```bash
crane registry serve --address 127.0.0.1:5555 --disk /tmp/crane-registry
# 内存模式：进程退出数据就没了；--disk 模式落盘
```

> ⚠️ 这是**玩具级 registry 实现**，只适合测试。
> 实测 `crane validate --remote` 在它上面会误报
> `validating layers: mismatched number of diffids: len(ConfigFile.RootFS.DiffIDs)=2, len(layers)=0`。
> **别用它当真 registry**，也别把它的报错当成镜像有问题。

### S9 · GAR 实战：把 Docker Hub 镜像搬进 GAR（保留 digest）

```bash
export GAR=asia-northeast1-docker.pkg.dev/example-project/my-app
crane auth login asia-northeast1-docker.pkg.dev \
  -u oauth2accesstoken -p "$(gcloud auth print-access-token)"

crane copy index.docker.io/library/alpine:3.19 "$GAR/alpine:3.19"
crane digest "$GAR/alpine:3.19"
crane ls "$GAR"
```

### S10 · 查多架构镜像里到底有什么（含 attestation）

```bash
$ crane index list index.docker.io/library/alpine:3.19
Digest                                     MediaType            Platform
sha256:b58899f069c47216f6002a6850143dc...  oci.image.manifest.v1+json  linux/amd64
sha256:ea72def7a47260a6b8cea592a2d0e07b...  oci.image.manifest.v1+json  unknown/unknown
sha256:f55c074e5390129e8d7d3dd452939d4...  oci.image.manifest.v1+json  linux/arm/v6
sha256:12bd48f39929e06326042c34d1666c...  oci.image.manifest.v1+json  unknown/unknown
sha256:fb10a3bec072387d30e2f5db86543c1...  oci.image.manifest.v1+json  linux/arm/v7
sha256:5cd72f301a291887075a70d8b14aed6...  oci.image.manifest.v1+json  linux/arm64/v8
...（amd64/armv6/armv7/arm64/386/ppc64le/s390x + 一堆 unknown/unknown）
```

**`unknown/unknown` 是什么？**——那些是 **attestation（构建来源证明）清单**，
由 BuildKit / Cloud Build / cosign 挂在 index 上。
**它们不是坏镜像**；`crane copy` 默认会一起搬过去（保 provenance 链）。

---

## 6. 坑清单（12 条，全部实测）

| # | 现象 | 原因 | 处理 |
| :-- | :--- | :--- | :--- |
| 1 | `--cmd='["-c","echo hi"]'` 报 YAML parse error | `--cmd`/`--entrypoint` **不是 JSON 数组**，是「重复传 flag」 | `--cmd=-c --cmd='echo hi'` |
| 2 | `repository can't be set when a tag is specified` | `--repo` 与 `--tag` 互斥 | 二选一 |
| 3 | `--repo` 推完 repo 里没有新 tag | `--repo` 是 **push by digest** | 再 `crane tag repo@sha256:... v1` |
| 4 | `crane pull --format=oci out.tar` 报 `is a directory` | oci 格式产出的是**目录** | 用目录路径，或用默认 tarball 格式 |
| 5 | `crane validate --remote` 报 diffids mismatch | 玩具 registry（`crane registry serve`）实现不全 | 换真实 registry 验证 |
| 6 | 拷贝多 tag 报 `repository can only contain the characters...` | `--all-tags` 时 **SRC 必须是 repo（不带 tag）** | `crane copy --all-tags index.docker.io/library/alpine <dst>` |
| 7 | `crane delete` 后 digest 还能解析 | delete **只删 tag**，manifest/blob 仍在 | 靠 GAR cleanup policy 清存储 |
| 8 | `TLS handshake timeout`（连 pkg.dev / 跳转后的 `*-docker.pkg.dev`） | registry 307 跳到别的域，而那个域**在本机不可达** | 用 `crane -v` 看跳转链路；检查 DNS/代理（**本机实测 `*.pkg.dev` 被解析到 198.0.5.144/145 且不可达，而 gcr.io / ghcr.io / docker.io 正常**） |
| 9 | 以为有 `crane sbom` | 0.22.1 **没有** `sbom` 子命令（旧版有，勿照抄老博客） | 用 `crane export` + `syft`/`trivy` 出 SBOM |
| 10 | `crane ls` 看到 `sha256-xxxx` 这种怪 tag | registry 自动生成的 **digest 别名 tag** | `crane ls -O` 过滤掉 |
| 11 | 往 registry 推本机自签证书的镜像失败 | 缺 `--insecure`（或 CA 不受信） | `--insecure`；生产别用 |
| 12 | 以为 `crane copy` 会重新打包、digest 会变 | **copy 保留 digest**（这正是它的价值） | 想改内容用 `append`/`mutate`，digest 一定会变 |

---

## 7. 与 docker / skopeo / regctl / cosign 怎么选

| 工具 | 定位 | 比 crane 强在哪 | 比 crane 弱在哪 |
| :--- | :--- | :--- | :--- |
| **crane** | Google 的极简 OCI 客户端 | 单二进制、命令直白、`-v` 排错友好 | 无签名、无扫描、无构建 |
| `docker buildx`/`docker build` | 构建 + 推送 | 能构建、能运行 | 依赖 daemon；搬运会改 digest |
| `skopeo` | RedHat 的成熟 OCI 客户端 | 生态久、`--all`/签名集成好 | 依赖较多、命令更长 |
| `regctl` | 微软的 OCI 客户端 | 交互式 shell（`regctl image ls`）、生态插件多 | 学习成本略高 |
| `cosign` | 签名 / 验签 / attach 证明 | **唯一能做 SBOM、attestation、签名准入的工具** | 不管搬运 |
| `trivy`/`grype` | 漏洞扫描 | 扫描能力强 | 不管搬运 |
| `oras` | 以 artifact 为中心（不只是 image） | 通用 artifact 分发 | image 场景不如 crane 直白 |

**组合拳（工程上最常见）**：

```bash
crane copy    docker.io/x/y:tag        $GAR/x/y:tag   # 搬运，digest 不变
crane append  --new_layer fix.tar      $GAR/x/y:tag   # 打补丁
cosign sign   $GAR/x/y@sha256:...                     # 签名
trivy image --exit-code 1 $GAR/x/y@sha256:...         # 门禁
```

---

## 8. 在 Cloud Build / GAR 流水线里怎么用

crane 非常适合塞进 Cloud Build 的 step（不需要 daemon、不需要特权）：

```yaml
steps:
  # ① 只查 digest（秒级，不拉层）→ 作为后续步骤的输入
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    id: 'digest'
    entrypoint: bash
    script:
      - |
        install -m 0755 -d /workspace/bin
        curl -sSL https://github.com/google/go-containerregistry/releases/download/v0.22.1/go-containerregistry_Linux_x86_64.tar.gz \
          | tar -xz -C /workspace/bin crane
        /workspace/bin/crane auth login asia-northeast1-docker.pkg.dev \
          -u oauth2accesstoken -p "$(gcloud auth print-access-token)"
        /workspace/bin/crane digest \
          asia-northeast1-docker.pkg.dev/$PROJECT_ID/my-app/app:$COMMIT_SHA \
          | tee /workspace/out/digest.txt

  # ② 用上一步的 digest 做部署（不可变引用）
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: bash
    script:
      - |
        DIGEST=$(cat /workspace/out/digest.txt)
        gcloud run deploy my-app \
          --image "asia-northeast1-docker.pkg.dev/$PROJECT_ID/my-app/app@$DIGEST" \
          --region asia-northeast1
```

**在 Cloud Build 里用 crane 的三条原则**：

1. **不要 `crane auth login` 存 token**——直接用 build SA 的身份（`gcloud auth print-access-token` 现取）；
2. **能用 `crane digest` 就不 `docker pull`**——前者几十 KB，后者几百 MB，直接决定 build-minute 和 egress 账单；
3. **跨仓库搬运用 `crane copy`**——保留 digest，扫描结果、准入策略、审计链都不会断。

> 与 [gcp/gcp-cloud-build/mindmap.md](../../../gcp/gcp-cloud-build/mindmap.md) 的
> 「制品不可变（digest 晋级）」一条直接对应：
> crane 是把「tag 引用」升级成「digest 引用」最省事的工具。

---

## 9. 交叉引用

| 场景 | 去哪看 |
| :--- | :--- |
| 镜像离线打包 / 压缩 / 平台不匹配 | [01-offline-image-packaging.md](01-offline-image-packaging.md) |
| GAR 存储与清理策略（删 tag 不删 blob 的后果） | [gcp/artifact-registry/cleanup-policy-assessment.md](../../../gcp/artifact-registry/cleanup-policy-assessment.md) |
| Cloud Build 流水线 / 制品不可变 / digest 晋级 | [gcp/gcp-cloud-build/mindmap.md](../../../gcp/gcp-cloud-build/mindmap.md)、[gcp/gcp-cloud-build/how-to-autofix-cve-with-cloud-build.md](../../../gcp/gcp-cloud-build/how-to-autofix-cve-with-cloud-build.md) |
| 换 base 镜像修 CVE 的边界条件 | [safe/fix-cve/how-to-fix-cve-with-base-image-constraints.md](../../../safe/fix-cve/how-to-fix-cve-with-base-image-constraints.md) |
| Buildpacks（不用 Dockerfile 出镜像） | [devops/buildpacks/](../../buildpacks/) |

---

## 10. 官方文档与源码

- 项目主页：https://github.com/google/go-containerregistry/tree/main/cmd/crane
- crane README（命令页）：https://github.com/google/go-containerregistry/tree/main/cmd/crane#readme
- go-containerregistry 库：https://pkg.go.dev/github.com/google/go-containerregistry
- OCI Distribution Spec：https://github.com/opencontainers/distribution-spec
- OCI Image Spec：https://github.com/opencontainers/image-spec
- cosign（签名配套）：https://github.com/sigstore/cosign
