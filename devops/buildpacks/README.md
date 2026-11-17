# Buildpacks / CNB 生态

> **一句话结论**:Cloud Native Buildpacks(CNB)是一套「**不写 Dockerfile 也能把源码变成可运行镜像**」的规范,
> `pack` 是它的 CLI,`lifecycle` 是它的参考实现,`imgutil` 是它操作 OCI 镜像的底层库。

---

## 目录

| 文档 | 内容 | 适合谁 |
|---|---|---|
| [imgutil.md](imgutil.md) | CNB 官方镜像操作库:三个存储后端(local/remote/layout)、`Image`/`ImageIndex` 接口、层复用与 rebase、可复现构建的时间戳归一化、containerd 快照器回归坑 | 要读 `pack build` 源码 / 自己写镜像改写工具 / 排查导出镜像异常 |

---

## 速查卡

| 维度 | 事实 |
|---|---|
| 规范 | CNB(Cloud Native Buildpacks),CNCF 孵化项目,buildpacks 官方组织维护 |
| 工具链 | `pack` CLI(本地/CI 构建)、`lifecycle`(analyzer→detector→restorer→builder→exporter)、`kpack`(K8s 控制器)、`buildpacks-community` |
| 镜像底座 | builder 镜像 = build image(工具链)+ run image(运行时)+ 若干 buildpack |
| 镜像层模型 | build 层和 run 层**分开导出**;应用层可从上一版镜像**复用**;基础镜像可整段**rebase** |
| 关键库 | [`imgutil`](imgutil.md) —— 封装 OCI 镜像读写;底层是 `google/go-containerregistry` |
| 与 Dockerfile 的差别 | 构建步骤不写在仓库里,而是写在 buildpack 里;基础 OS/运行时随 builder 版本走 |
| 何时**不该**用 | 需要自定义系统包 / 精细控制多阶段 / 追求最短构建时长 —— 那种场景手写 Dockerfile 更快 |

---

## 30 秒版

```bash
# 用官方 builder 把源码变成镜像(不需要 Dockerfile)
pack build myapp --builder paketobuildpacks/builder-jammy-base:latest myapp:latest

# 换基础镜像(rebase):应用层不变,只换 run image
pack rebase myapp:latest myapp:latest --run-image paketobuildpacks/run-jammy-base:latest
```
