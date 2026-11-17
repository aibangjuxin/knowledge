# buildpacks/imgutil —— CNB 生态的镜像操作库

> **一句话结论**:`buildpacks/imgutil` 是 Cloud Native Buildpacks(CNB)官方组织下的 **Go 镜像操作库**(不是 CLI),
> 它把「读写 OCI 镜像 / 追加层 / 换基础镜像(rebase)/ 推拉多架构 manifest」这套底层能力封装成统一接口,
> `pack` CLI 和 `lifecycle` 都建立在它之上。
> 想理解 `pack build` 到底怎么造出镜像、或自己写工具改镜像,**这是唯一该读的源码**。

| 维度 | 事实 |
|---|---|
| 仓库 | [github.com/buildpacks/imgutil](https://github.com/buildpacks/imgutil) |
| 定位 | 库(library),无 CLI、无官方 release tag |
| 语言 / 许可 | Go / Apache-2.0 |
| 维护方 | buildpacks 官方组织(CNB 规范维护者) |
| 版本策略 | 只发 pseudo-version:`v0.0.0-<日期>-<commit>`,**没有 v1 tag** |
| 最近版本(2026-11) | `v0.0.0-20261114233731-3665d0bdb3f4` |
| 核心依赖 | `github.com/google/go-containerregistry`、`docker/cli`、`moby/moby/client` |
| 主要使用方 | `buildpacks/pack`(CLI)、`buildpacks/lifecycle`(exporter/rebaser) |
| 一句话类比 | "Dockerfile 时代的 `docker build` 底层零件"之于 CNB 时代 |

---

## 1. 它解决什么问题

在传统 Dockerfile 世界里,"造镜像"这件事被 `docker build` / `buildah` / `kaniko` 这些 **CLI** 垄断,
你只能通过命令行参数间接控制镜像长什么样。CNB(`pack build`)需要更细粒度的控制:

- 导出阶段要把 **build 层** 和 **run 层** 分别装配成镜像;
- 增量构建时要把上一版镜像的层 **直接复用**(不重新打包、不重传);
- `pack rebase` 要把应用镜像 **换到新的基础镜像** 上,同时保持应用层的 diffID 不变;
- 产物既可能要 **单架构**,也可能是 **多架构 manifest list**。

`imgutil` 就是干这件事的:提供一套 **`Image` / `ImageIndex` 抽象**,把「镜像存在哪」
(本地 daemon / 远端 registry / 磁盘上的 OCI layout)和「怎么改镜像」两件事解耦。

```
              ┌──────────── imgutil.Image (统一接口) ────────────┐
              │  WithEditableManifest + WithEditableConfig       │
              │  + WithEditableLayers                            │
              └───────┬──────────────┬──────────────┬───────────┘
                      │              │              │
                 local.Image    remote.Image    layout.Image
              (Docker daemon)  (registry)   (OCI layout 目录)
                      │              │              │
              local.Store    remote(ggcr)     ggcr layout
```

三个后端都复用同一个 `CNBImageCore`(内嵌 `v1.Image`),只额外实现各自的
`Found()` / `Identifier()` / `Save()` / `Delete()` 等"落地"动作。
`Kind()` 方法会返回 `"local"` / `"remote"` / `"layout"`,便于上层做分支判断。

---

## 2. 核心接口

### 2.1 `imgutil.Image`(根包 `image.go`)

```go
type Image interface {
    WithEditableManifest   // Annotations / Digest / MediaType 的读写
    WithEditableConfig     // Entrypoint / Env / Label / OS / Variant ...
    WithEditableLayers     // AddLayer / ReuseLayer / Rebase / GetLayer / TopLayer

    // 查询
    Found() bool           // 镜像是否存在于目标存储
    Identifier() (Identifier, error)
    Kind() string          // local / remote / layout
    Name() string
    UnderlyingImage() v1.Image
    Valid() bool           // manifest 的层是否齐全(registry 上校验用)

    // 落地
    Delete() error
    Rename(name string)
    Save(additionalNames ...string) error
    SaveAs(name string, additionalNames ...string) error
    SaveFile() (string, error)  // 导出成 docker archive,返回文件路径
}
```

三个 `WithEditable*` 子接口是关键设计:

| 子接口 | 管什么 | 常用方法 |
|---|---|---|
| `WithEditableManifest` | manifest 级别 | `SetAnnotations`、`AnnotateRefName`、`MediaType`、`Digest` |
| `WithEditableConfig` | config file 级别 | `SetLabel`、`SetEnv`、`SetEntrypoint`、`SetOS`/`SetVariant`、`SetHistory` |
| `WithEditableLayers` | 层级别 | `AddLayer`、`ReuseLayer`、`AddOrReuseLayerWithHistory`、`Rebase`、`GetLayer`、`TopLayer` |

### 2.2 `imgutil.ImageIndex`(`index.go`)

多架构镜像(index / manifest list)的对应接口:
`AddManifest` / `RemoveManifest` / `SetArchitecture` / `SetOS` / `SetVariant` /
`IndexManifest()` / `Push()` / `SaveDir()`。

---

## 3. 功能清单(它到底能干什么)

| 能力 | API | 说明 |
|---|---|---|
| 新建空镜像 | `imgutil.NewCNBImage(ImageOptions)` | 无 base image 时用 `empty.Image` 起手 |
| 从已有镜像加载 | `FromBaseImage(name)` | 作为工作镜像的基底 |
| 追加层 | `AddLayer(path)` / `AddLayerWithDiffIDAndHistory(path, diffID, history)` | `path` 是 tar 文件 |
| **层复用** | `ReuseLayer(diffID)` / `AddOrReuseLayerWithHistory(path, diffID, history)` | 增量构建关键:层直接从上一版镜像搬过来,避免重复上传 |
| **Rebase** | `Rebase(baseTopLayerDiffID string, newBase Image)` | 把应用镜像换到新基础镜像上,应用层 diffID 不变 |
| 查层 | `GetLayer(diffID)` / `TopLayer()` | 返回未压缩内容 / 顶层 diffID |
| 改配置 | `SetLabel` / `SetEnv` / `SetEntrypoint` / `SetOS` / `SetVariant` / `SetHistory` | 直接改 config file |
| 改 manifest | `SetAnnotations` / `AnnotateRefName` | `org.opencontainers.image.ref.name` 等 |
| **Media type 转换** | `WithMediaTypes(imgutil.OCITypes / DockerTypes)` + `EnsureMediaTypesAndLayers` | OCI ↔ Docker manifest/config/layer 类型互转 |
| 多架构 | `NewCNBIndex` / `ImageIndex.AddManifest` | 组装 manifest list |
| 认证 / 私有仓库 | `authn.Keychain`、`WithRegistrySetting(repo, insecure)` | `insecure=true` 走 HTTP 或跳过 TLS 校验 |
| 导出 tar | `SaveFile()` | 输出 docker archive 供离线搬运 |

---

## 4. 几个必须知道的实现细节

### 4.1 时间戳归一化 = 可复现构建

```go
// new.go
var NormalizedDateTime = time.Date(1980, time.January, 1, 0, 0, 1, 0, time.UTC)
```

除非显式 `WithCreatedAt(t)`,所有写入镜像的 `created` 时间都被固定为 **1980-01-01 00:00:01 UTC**,
每一层 history 的时间也一样(`SetCreatedAtAndHistory`)。
这样同样的输入能产出**同样的 digest**,构建可复现。代价是镜像里的时间戳全是 1980 年。

### 4.2 history 默认被抹平

只有显式传 `WithHistory()` 才会 `PreserveHistory`;否则新增层的 history 会被替换成
`emptyHistory`(只有归一化时间,无命令描述)。此外 `NormalizedHistory()` 会**丢弃 `EmptyLayer` 标记的条目**,
并保证 history 条数与层数一致。

> **实践含义**:想保留 `docker history` 里的构建命令,必须开 `WithHistory()`;
> 否则镜像的 `docker history` 会是一长串空条目。

### 4.3 Media type 的"重建式"转换

`EnsureMediaTypesAndLayers` 不是简单改字符串,而是:
**读原 manifest/config/layers → 用空镜像重建一个新 manifest → 按目标 media type 重新 append 层 → 校验层数一致**。
这保证转换后 manifest 与 config 中的 media type 字段自洽,不会出现"manifest 说 OCI、config 说 Docker"的坏镜像。

### 4.4 Windows 特殊处理

新建 Windows 镜像时,若 config 里 `OS == "windows"` 且没有任何 diffID,
会自动追加一个 Windows 基础层(`layer.WindowsBaseLayer()`),否则 Windows 容器起不来。

### 4.5 Rebase 的实现

`Rebase` 内部调用 go-containerregistry 的 `mutate.Rebase`,并额外把新 base 的
`Architecture` / `OS` / `OSVersion` 同步到 config。
`baseTopLayerDiffID` 用于定位"应用层从哪一层开始",定位不到会报
`could not find base layer in image`。

---

## 5. 快速上手

### 5.1 拉一个远端镜像,改 label,再推回去

```go
package main

import (
    "log"

    "github.com/google/go-containerregistry/pkg/authn"
    "github.com/buildpacks/imgutil"
    "github.com/buildpacks/imgutil/remote"
)

func main() {
    img, err := remote.NewImage(
        "registry.example.com/myapp:latest",
        authn.DefaultKeychain,
        imgutil.WithMediaTypes(imgutil.OCITypes),
    )
    if err != nil {
        log.Fatal(err)
    }
    if !img.Found() {
        log.Fatal("image not found")
    }

    if err := img.SetLabel("io.buildpacks.stacks.jammy", "jammy"); err != nil {
        log.Fatal(err)
    }
    if err := img.Save(); err != nil {   // 推回 Name() 指向的位置
        log.Fatal(err)
    }
}
```

### 5.2 从基础镜像造一个新镜像(本地 daemon)

```go
import (
    "github.com/buildpacks/imgutil"
    "github.com/buildpacks/imgutil/local"
)

img, err := local.NewImage("myapp:latest",
    imgutil.FromBaseImage("ubuntu:22.04"),
    imgutil.WithDefaultPlatform(imgutil.Platform{OS: "linux", Architecture: "amd64"}),
    imgutil.WithMediaTypes(imgutil.DockerTypes),
)
_ = img.AddLayer("./app-layer.tar")
_ = img.Save()
```

### 5.3 写成磁盘上的 OCI layout(不碰 daemon、不碰 registry)

```go
import "github.com/buildpacks/imgutil/layout"

img, err := layout.NewImage("/tmp/myapp-layout",
    imgutil.FromBaseImage("ubuntu:22.04"),
)
_ = img.AddLayer("./app-layer.tar")
_ = img.Save()   // 生成 /tmp/myapp-layout/{oci-layout,index.json,blobs/}
```

`layout` 后端还支持 **sparse layout**:`layout.Path.AppendImage()` 可以只写 manifest/config
而**不写层 blob**(层被引用但 `blobs/` 里没有),适合"只登记不落盘"的场景。

---

## 6. 它在 CNB 体系里的位置

```
用户代码
  │  pack build / kpack Image
  ▼
lifecycle(analyzer→detector→restorer→builder→exporter)   ← 直接使用 imgutil.Image
  │  exporter 阶段:装配 build 层 + run 层
  ▼
imgutil.Image (local / remote / layout)
  │  go-containerregistry (v1.Image / v1.ImageIndex / mutate)
  ▼
Docker daemon  /  OCI registry  /  OCI layout
```

- `pack` 用它在本地 daemon、registry 之间搬运和改写镜像;
- `lifecycle` 的 `exporter` 用它把层目录装配成镜像,`rebaser` 用它实现 `pack rebase`:
  ```go
  // lifecycle/rebaser.go
  func (r *Rebaser) Rebase(appImage imgutil.Image, newBaseImage imgutil.Image, additionalNames []string) (RebaseReport, error)
  ```
- `lifecycle` 还用 `imgutil.Image` 读取 `io.buildpacks.*` 系列 label 与 `TargetMetadata`。

---

## 7. 坑与注意事项

| 坑 | 说明 | 应对 |
|---|---|---|
| **containerd 快照器回归** | 2025 年 `pack builder create` 生成的镜像在 containerd 镜像存储下,同一个 blob 被用于两个不同 DiffID,导致 `skopeo copy` 报 `used for two different DiffID values`。根因在 imgutil 的 containerd snapshotter 支持,见 [imgutil#300](https://github.com/buildpacks/imgutil/issues/300) / [pack#2490](https://github.com/buildpacks/pack/issues/2490) | 已于 2025-11 修复并由 pack 升级依赖;本地若仍异常,回退 `overlay2` 存储驱动或降级 pack |
| **没有 semver** | 只有 pseudo-version,`go get` 拿到的可能是任意提交 | 显式在 go.mod 里 pin 版本;升级前看 release notes |
| **history 默认丢失** | 不开 `WithHistory()` 就看不到构建命令历史 | 需要审计/溯源时务必开启 |
| **时间戳被改写为 1980** | 有意为之(可复现),但会让某些按时间排序/过滤的工具困惑 | 接受,或显式 `WithCreatedAt` |
| **`ReuseLayer` 需要 previous image** | 没有 `WithPreviousImage` 时调用会报 `failed to reuse layer because no previous image was provided` | 复用场景必须同时传 previous image |
| **`GetLayer` 可能触发全量下载** | local 后端注释明确写了:必要时会把**所有层**从 daemon 下载下来 | 大镜像慎用,注意 IO |
| **insecure registry** | `WithRegistrySetting(repo, true)` 会 `InsecureSkipVerify` | 仅限内网测试环境 |

---

## 8. 延伸阅读

- 源码:[github.com/buildpacks/imgutil](https://github.com/buildpacks/imgutil)
  - 根包:`image.go`(接口)、`cnb_image.go`(`CNBImageCore` 实现)、`new.go`(构造 + media type 转换)、`options.go`(选项)、`index.go`(多架构)
  - 后端:`local/`(daemon)、`remote/`(registry)、`layout/`(OCI layout)
- API 文档:[pkg.go.dev/github.com/buildpacks/imgutil](https://pkg.go.dev/github.com/buildpacks/imgutil)
- 上游:[buildpacks/pack](https://github.com/buildpacks/pack) · [buildpacks/lifecycle](https://github.com/buildpacks/lifecycle)
- 底层库:[google/go-containerregistry](https://github.com/google/go-containerregistry)(ggcr,负责 `v1.Image` / `mutate` / `remote`)
- 相关主题:[../docker/docs/01-offline-image-packaging.md](../docker/docs/01-offline-image-packaging.md) —— 镜像离线打包与压缩(与 imgutil 的"层"概念直接相关)
