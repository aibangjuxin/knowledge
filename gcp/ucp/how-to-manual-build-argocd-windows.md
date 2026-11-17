# 在 Windows 上安装 Argo CD CLI（`go install` 不可用时的完整方案）

> 适用版本：Argo CD **v3.5.6**（与本目录 `install.yaml` 对齐）；上游最新为 **v3.6.1**。
> 目标环境：**Windows 主机 + Git Bash**（`bash` 来自 Git for Windows）。
> 配套文档：[`argocd-cli-guide.md`](./argocd-cli-guide.md)（CLI 命令实战）、[`argocd-api.md`](./argocd-api.md)（REST API）。

---

## 0. 一页速查（TL;DR）

| 场景 | 推荐方案 | 命令 | 耗时 |
|---|---|---|---|
| **只想要一个能用的 `argocd.exe`** | ⭐ 方案 A：下载官方 release 二进制 | `curl` + `sha256sum -c` | < 2 min |
| 想用包管理器 | ⭐ 方案 B：Scoop | `scoop install argocd` | ~3 min |
| 有 Docker Desktop | 方案 C：容器内跑 CLI | `docker run --rm -it quay.io/argoproj/argocd:v3.5.6 argocd ...` | 即时 |
| **不允许任何外来二进制**（合规要求） | 方案 D：源码自行编译 | `git clone` → `go build ./cmd` | 3–10 min |
| **网络也不通**（proxy 也被封） | 方案 D'：离线 vendor 编译 / 交叉编译 | `go mod vendor` → `GOPROXY=off go build -mod=vendor` | 5–15 min |
| 只能访问 K8s 集群 | 方案 E：用 Pod 里的 CLI | `kubectl exec deploy/argocd-server -- argocd ...` | 即时 |

**先看第 1 节**——它会告诉你：**`go install` 对 Argo CD 根本不是"被禁"，而是"本来就不可能成功"**。搞清这一点，后面的选择会清晰很多。

---

## 1. 关键发现：`go install` 对 Argo CD 一定失败（不是策略问题）

很多教程（包括一些博客）会写：

```bash
# ❌ 这条命令对 Argo CD 永远不成立
go install github.com/argoproj/argo-cd/v2/cmd/argocd@latest
go install github.com/argoproj/argo-cd/v3/cmd/argocd@latest
```

### 1.1 原因一：CLI 的 main 包路径不对

Argo CD 仓库里 `cmd/argocd/` **不是一个 main 包**，它只是 cobra 命令的实现（`package commands`）。
真正的入口是仓库根下的 **`cmd/`**（`cmd/main.go`，`package main`），它是一个"多命令合一"二进制：
同一个二进制，靠**文件名**（`filepath.Base(os.Args[0])`）或环境变量 `ARGOCD_BINARY_NAME` 决定自己扮演 CLI 还是 server。

```
argo-cd/cmd/
├── main.go                      ← package main，唯一的 CLI 入口（go build ./cmd）
├── argocd/commands/             ← package commands（不是 main！）
├── argocd-server/commands/
├── argocd-repo-server/commands/
└── ...
```

官方 `.goreleaser.yaml` 里写得很明确：

```yaml
builds:
  - id: argocd-cli
    main: ./cmd                 # ← 就是 ./cmd
    binary: argocd-{{ .Os}}-{{ .Arch}}
```

所以 `cmd/argocd` 这个 package 根本不存在 → 实测报错：

```
$ go install github.com/argoproj/argo-cd/v3/cmd/argocd@v3.5.6
go: github.com/argoproj/argo-cd/v3/cmd/argocd@v3.5.6: module github.com/argoproj/argo-cd/v3@v3.5.6 found,
   but does not contain package github.com/argoproj/argo-cd/v3/cmd/argocd
```

### 1.2 原因二：go.mod 里有 `replace` 指令，Go 工具链直接拒绝

把路径改成正确的 `cmd` 之后，Go 依然报错：

```
$ go install github.com/argoproj/argo-cd/v3/cmd@v3.5.6
go: github.com/argoproj/argo-cd/v3/cmd@v3.5.6 (in github.com/argoproj/argo-cd/v3@v3.5.6):
    The go.mod file for the module providing named packages contains one or
    more replace directives. It must not contain directives that would cause
    it to be interpreted differently than if it were the main module.
```

`go install pkg@version` 这个语法要求"被安装模块的 go.mod 与作为主模块时语义一致"，而 Argo CD 的 `go.mod` 有一整段 `replace`（v3.5.6 第 330 行起）：

```go
replace (
	github.com/golang/protobuf        => github.com/golang/protobuf v1.5.4
	github.com/grpc-ecosystem/grpc-gateway => github.com/grpc-ecosystem/grpc-gateway v1.16.0
	golang.org/x/tools                 => golang.org/x/tools v0.35.0
	gopkg.in/yaml.v2                   => gopkg.in/yaml.v2 v2.4.0      // 规避 CVE-2022-3064
	k8s.io/api                         => k8s.io/api v0.36.1
	...
)
replace github.com/argoproj/argo-cd/gitops-engine => ./gitops-engine   // ← 本地路径 replace
```

v2.11.7 同样如此（实测同样报错）。**Argo CD v2 和 v3 都无法用 `go install` 安装 CLI。**

### 1.3 结论与推论

| 结论 | 影响 |
|---|---|
| `go install` 对 Argo CD **结构性不可用** | 遇到 "go install 被禁" 时，别去找绕过的 `go install` 姿势，**直接换路线** |
| 唯一能在本地 clone 内跑通的"install" 形式是 | `go install ./cmd` —— 但它产出���文件名 `cmd`（不是 `argocd`），且同样需要网络拉依赖 |
| 真正的官方安装方式 | 下载 release 二进制（官方 `cli_installation` 文档里**从头到尾没有提 `go install`**） |
| 想"自己 build" | 可行，且是**供应链合规场景下的标准做法**（见方案 D） |

> ⚠️ **另一类"被禁"也要区分**：如果禁的是**网络**（`proxy.golang.org` / `github.com` 不通），那 `go build` 同样要拉依赖，也会失败 → 必须用 **方案 D'（离线 vendor）** 或 **交叉编译**。

---

## 2. 方案 A（推荐）：直接下载官方 release 二进制

Windows 原生、官方支持、无需 Go 工具链、**240 MB 左右的单个 exe**。

### 2.1 Git Bash 版（推荐，你在 Git Bash 里直接粘贴）

```bash
VERSION=v3.5.6                       # 与集群 argocd-server 版本保持一致
BASE="https://github.com/argoproj/argo-cd/releases/download/${VERSION}"

mkdir -p ~/bin && cd ~/bin

# 下载 CLI 二进制 + 官方校验和文件
# ⚠️ 先按官方文件名下载，校验通过后再改名（sha256sum -c 会按文件名去找文件）
curl -fsSL -o argocd-windows-amd64.exe "${BASE}/argocd-windows-amd64.exe"
curl -fsSL -o cli_checksums.txt "${BASE}/cli_checksums.txt"

# 校验（官方 sha256）
grep 'argocd-windows-amd64.exe' cli_checksums.txt | sha256sum -c -
# 期望输出：argocd-windows-amd64.exe: OK

# 校验通过后改成习惯的名字
mv argocd-windows-amd64.exe argocd.exe && rm -f cli_checksums.txt
```

> `sha256sum` 是 Git Bash 自带 coreutils 的一部分；没有的话用 `shasum -a 256 argocd-windows-amd64.exe` 手动比对。
> `cli_checksums.txt` 里包含所有平台的哈希，所以必须先 `grep` 出目标行（Git Bash 的 `sha256sum -c` 不支持 `--ignore-missing`）。

### 2.2 PowerShell 版（官方文档写法）

```powershell
$version = "v3.5.6"
$url = "https://github.com/argoproj/argo-cd/releases/download/" + $version + "/argocd-windows-amd64.exe"
Invoke-WebRequest -Uri $url -OutFile "argocd.exe"

# 加入用户级 PATH
[Environment]::SetEnvironmentVariable("Path", "$env:Path;C:\Path\To\ArgoCD-CLI", "User")
```

### 2.3 加入 PATH（Git Bash 里的两种做法）

```bash
# 做法 A（推荐）：写进 Windows 用户级 PATH，Git Bash 会继承
#   PowerShell: [Environment]::SetEnvironmentVariable("Path","$env:Path;C:\Users\<你>\bin","User")
#   然后重开一个 Git Bash 窗口
export PATH="$HOME/bin:$PATH"     # 临时验证用

# 做法 B：只对 Git Bash 生效，写进 ~/.bashrc
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

验证：

```bash
argocd version --client
# argocd: v3.5.6
#   BuildDate: 2026-...
#   GitCommit: c2b1e30...
#   GitTreeState: clean
#   GoVersion: go1.26.x
#   Compiler: gc
#   Platform: windows/amd64
```

### 2.4 可选：验证 SLSA provenance（供应链合规场景）

每个 release 附带一份 `argocd-cli.intoto.jsonl` 证明文件，可用 `slsa-verifier` 校验二进制确实由 Argo CD 官方 CI 构建：

```bash
curl -fsSL -O "${BASE}/argocd-cli.intoto.jsonl"
slsa-verifier verify-artifact argocd-windows-amd64.exe \
  --provenance-path argocd-cli.intoto.jsonl \
  --source-uri github.com/argoproj/argo-cd \
  --source-tag v3.5.6
```

### 2.5 ⚠️ Windows 平台注意事项

| 事项 | 说明 |
|---|---|
| **没有 Windows ARM64 官方构建** | `.goreleaser.yaml` 里显式 `ignore: goos: windows, goarch: arm64`。Windows 11 on ARM 只能跑 **amd64 版**（系统自带 x64 模拟层）。需要原生 arm64 就得自己编译（见方案 D） |
| 体积 ~240 MB | 官方二进制内嵌了完整 Web UI 资源。`go build` 出来的 CLI-only 版本约 205 MB；加 `-s -w` 约 147 MB |
| 二进制名字 | 官方 release 的文件名是 `argocd-windows-amd64.exe`（带 `.exe`），落地后重命名为 `argocd.exe` 更顺手。`cmd/main.go` 的 `default` 分支对任意不认识的名字都按 CLI 处理，所以名字其实不挑 |
| 最新稳定版 | 上游 `stable` 分支的 `VERSION` 文件即最新 stable（写文档时为 `3.6.1`）。生产环境请**钉死版本**，与 `argocd-server` 对齐 |

---

## 3. 方案 B：包管理器 / 容器 / WSL

### 3.1 Scoop（Windows 原生，Windows 上最舒服的包管理器）

Scoop 官方 Main bucket 收录了 `argocd`：

```powershell
scoop install argocd
argocd version --client
```

manifest 实测内容（`ScoopInstaller/Main/bucket/argocd.json`）：

```json
{
  "version": "3.6.1",
  "architecture": { "64bit": { "url": ".../v3.6.1/argocd-windows-amd64.exe#/argocd.exe" } },
  "bin": "argocd.exe",
  "checkver": { "github": "https://github.com/argoproj/argo-cd" }
}
```

- 安装位置：`%USERPROFILE%\scoop\apps\argocd\current\argocd.exe`（已在 PATH）
- 只提供 x64；`scoop update argocd` 可升级
- ⚠️ Scoop 的版本跟随上游 latest，**不保证与你的 Argo CD Server 版本一致**。生产用请改用方案 A 钉版本

> ❌ **winget / chocolatey 官方均无 argocd 包**（实测 `microsoft/winget-pkgs` 与 `chocolatey/choco` 的公共仓库都没有该 manifest）。

### 3.2 Docker Desktop

不想在主机上放二进制时，直接用官方镜像：

```bash
# 交互式（需要挂载 kubeconfig）
docker run --rm -it \
  -v ~/.kube:/root/.kube \
  -e ARGOCD_SERVER=argocd.example.com \
  quay.io/argoproj/argocd:v3.5.6 \
  argocd app list

# 一次性
docker run --rm quay.io/argoproj/argocd:v3.5.6 argocd version --client
```

> Git Bash 下 `-v ~/.kube:/root/.kube` 的路径转换：Git Bash 会把 `~/.kube` 转成 Windows 路径，通常没问题；若报错，改用绝对路径 `C:/Users/<你>/.kube:/root/.kube`。

### 3.3 WSL2（如果公司策略是"Windows 主机装 Linux 发行版"）

```bash
# WSL 内
curl -fsSL -o argocd "https://github.com/argoproj/argo-cd/releases/download/v3.5.6/argocd-linux-amd64"
sudo install -m 555 argocd /usr/local/bin/argocd
argocd version --client
```

也可在 WSL 里用 Homebrew（官方文档明确支持 "Mac, Linux and WSL Homebrew"）：`brew install argocd`。

---

## 4. 方案 D：源码自行编译（在 Windows Git Bash 上）

**适用场景**：合规要求"必须从源码构建、可审计、可自签名"；或需要 Windows ARM64 原生版本。

### 4.1 前置条件

| 依赖 | 要求 | 说明 |
|---|---|---|
| Go | **≥ 1.26.3** | `go.mod` 第 3 行 `go 1.26.3`。官方镜像用 `golang:1.26.10` |
| Git | 任意近期版本 | Git for Windows 自带。⚠️ **v2.x 需要 `--recurse-submodules`**（v2 的 `gitops-engine` 是子模块；v3.5.6 起已并入主仓库，普通 clone 即可） |
| make（可选） | GNU make | **Git for Windows 不自带 make**。只用 `go build` 就不需要 |
| gcc（可选） | MinGW | 不需要，建议直接 `CGO_ENABLED=0` |
| 磁盘 | ~3 GB | 源码 + module cache + vendor |
| 网络 | 需能访问 `proxy.golang.org` | 见 4.6 离线方案 |

> 🔥 **Go 版本不够时的坑**：本机 Go < 1.26.3 时，Go 默认 `GOTOOLCHAIN=auto` 会尝试**联网下载**新版工具链。如果网络被封，会报
> `go: downloading go1.26.3 (linux/amd64): ... dial tcp: i/o timeout`。
> 处理方式：`GOTOOLCHAIN=local`（立刻失败，明确提示版本不足）或直接装一个 ≥1.26.3 的 Go。

### 4.2 步骤

```bash
# 1) 取源码（钉死 tag）
cd ~ && git clone --depth 1 -b v3.5.6 https://github.com/argoproj/argo-cd.git
cd argo-cd

# 2) 确认版本基线
cat VERSION            # → 3.5.6
grep '^go ' go.mod      # → go 1.26.3

# 3) 编译（Windows 原生 amd64）
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 \
GODEBUG="tarinsecurepath=0,zipinsecurepath=0" \
go build -v \
  -ldflags "-X github.com/argoproj/argo-cd/v3/common.version=3.5.6 \
            -X github.com/argoproj/argo-cd/v3/common.buildDate=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
            -X github.com/argoproj/argo-cd/v3/common.gitCommit=$(git rev-parse HEAD) \
            -X github.com/argoproj/argo-cd/v3/common.gitTreeState=clean" \
  -o argocd.exe ./cmd

# 4) 验证
./argocd.exe version --client

# 5) 放到 PATH
mkdir -p ~/bin && mv argocd.exe ~/bin/ && export PATH="$HOME/bin:$PATH"
```

### 4.3 关于 `-ldflags`（不写会怎样）

版本信息是通过链接期变量注入的（`common.version` / `common.buildDate` / `common.gitCommit` / `common.gitTreeState` / `common.kubectlVersion`）。
**不打这些 flag 也能编译，但版本号是假的**——实测：

```
$ argocd version --client
argocd: v99.99.99+unknown      # ← 默认值，dangerous：版本对不上还看不出问题
  BuildDate: 1970-01-01T00:00:00Z
  GitCommit:
```

`v99.99.99+unknown` 会让 CLI 自报版本与 Server 不一致，排障时极具误导性。**务必带上 `-ldflags`。**

### 4.4 `make` 目标的选择（别用错）

Makefile 里有三个相关目标，用途完全不同：

```bash
cd ~/argo-cd
mkdir -p dist                                    # 仓库里没有 dist/，被 .gitignore 忽略了

# ① 交付版（推荐）：无调试符号 + 完整 ldflags
make argocd-all GOOS=windows GOARCH=amd64 BIN_NAME=argocd.exe   # → dist/argocd.exe

# ② 开发调试版：带 -gcflags="all=-N -l"，供 Delve 调试
make cli-local                                   # → dist/argocd

# ③ 发布用：会连带构建 Web UI，不要用于纯 CLI 场景
make release-cli
```

实测差异：

| | `make argocd-all` | `make cli-local` | `go build ./cmd` |
|---|---|---|---|
| 产物 | `dist/argocd.exe` | `dist/argocd` | `argocd.exe` |
| 体积 | **205 MB** | **227 MB**（`-gcflags="all=-N -l"` 调试符号） | 205 MB（`-s -w` 可到 147 MB） |
| ldflags | Makefile 自动注入 `version` / `buildDate` / `gitCommit` / `gitTreeState` / `kubectlVersion` / `gitTag` | 同左 | 需手写 |
| 用途 | **分发 / 交付** | **本地调试 / Delve** | 分发 / 交付 |
| 前置 | `make` + `mkdir -p dist` | 同左 | 无 |

> **Windows 上 Makefile 的 `CGO_FLAG` 默认就是 `0`**（Makefile 里只有 `IS_DARWIN` 才置 1），所以不需要额外装 gcc。
> Makefile 的 `LDFLAGS` 会自动带上 `common.gitTag`（当 HEAD 正好在 tag 上时）和 `common.kubectlVersion`，比手写更完整——**有 GNU make 时优先用 `make argocd-all`**。
> ⚠️ 注意 `cli-local` 目标用的是 `$(CLI_NAME)`，**不认 `BIN_NAME`**；想改产物名要用 `argocd-all`。

### 4.5 ⚠️ 已知坑：`ui/dist` 的 embed

`ui/embed.go` 里有：

```go
//go:embed dist/app
//go:embed all:dist/app/assets/images/resources
var Embedded embed.FS
```

这些目录**必须存在**，否则编译直接失败：

```
ui/embed.go:8:12: pattern all:dist/app/assets/images/resources: no matching files found
```

正常 `git clone` 后这些占位文件是在的（已验证）：

```
ui/dist/app/gitkeep
ui/dist/app/assets/images/resources/.gitkeep
```

**但如果你在 clone 后跑过 `git clean -xfd`**（`.gitignore` 里 `ui/dist/app/*` 会命中 `assets/` 目录），这些占位文件会被删掉 → 编译失败。
修复：

```bash
mkdir -p ui/dist/app/assets/images/resources
touch ui/dist/app/gitkeep ui/dist/app/assets/images/resources/.gitkeep
```

### 4.6 网络受限时：离线 vendor 编译

如果 `proxy.golang.org` 不可达，`go build` 一样会失败。解法：**在一台能上网的机器上把依赖 vendor 进源码树，再整体拷贝到 Windows 主机离线编译。**

```bash
# === 在有网络的机器上（Mac/Linux/Windows 均可） ===
cd ~/argo-cd
go mod vendor                     # 实测耗时 ~19s，产出 vendor/ 约 146 MB

# 把整个目录（含 vendor/）打包带走
tar czf argo-cd-v3.5.6-vendor.tgz argo-cd/

# === 在离线 Windows 主机上 ===
tar xzf argo-cd-v3.5.6-vendor.tgz && cd argo-cd
GOFLAGS=-mod=vendor GOPROXY=off CGO_ENABLED=0 GOOS=windows GOARCH=amd64 \
go build -ldflags "-X github.com/argoproj/argo-cd/v3/common.version=3.5.6" \
  -o argocd.exe ./cmd
```

> ✅ 已实测：`GOPROXY=off GOFLAGS=-mod=vendor` 完全离线编译成功，耗时 ~44s（cache 冷时约 2–4 min）。
> `vendor/` 目录也可随源码一起提交到内网 Git，CI 里直接离线构建。

**另一种离线思路：复制 module cache**

```bash
# 有网机器
go mod download
tar czf gomodcache.tgz -C "$(go env GOMODCACHE)" .
# 离线机器
mkdir -p "$(go env GOMODCACHE)" && tar xzf gomodcache.tgz -C "$(go env GOMODCACHE)"
GOFLAGS=-mod=mod GOPROXY=off go build ./cmd
```

> ⚠️ module cache 里的文件是只读的（0444），跨机器拷贝后可能因权限报错；解包后必要时 `chmod -R u+w "$(go env GOMODCACHE)"`。
> （vendor 方式更干净、可审计，优先选它。）

### 4.7 交叉编译（在 Mac / Linux 上直接产出 Windows exe）

**对本仓库最实用的方式**——你手上这台 Mac 就能出 Windows 二进制，再拷贝到 Windows 主机：

```bash
cd ~/argo-cd
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 \
go build -ldflags "-X github.com/argoproj/argo-cd/v3/common.version=3.5.6 \
                  -X github.com/argoproj/argo-cd/v3/common.gitCommit=$(git rev-parse HEAD) \
                  -X github.com/argoproj/argo-cd/v3/common.gitTreeState=clean" \
  -o argocd-windows-amd64.exe ./cmd

# 拷贝到 Windows 主机
scp argocd-windows-amd64.exe windows-host:'C:/Users/<你>/bin/argocd.exe'
# 或者用共享目录 / U 盘 / 内网制品库

# 在 Windows 的 Git Bash 里验证
argocd.exe version --client
```

✅ **已实测**：macOS(arm64) → Windows/amd64 交叉编译 **1 分 35 秒**完成，产物 `PE32+ executable (console) x86-64, for MS Windows`，205 MB。

同理可交叉编译 Windows ARM64（官方不提供，但源码编译可以）：

```bash
CGO_ENABLED=0 GOOS=windows GOARCH=arm64 go build -o argocd-windows-arm64.exe ./cmd
```

### 4.8 自建二进制的"自证身份"

自编译产物没有官方签名，建议至少做两件事：

```bash
# 1) 记录 sha256，随交付物一起分发
sha256sum argocd.exe | tee argocd.exe.sha256

# 2) 用 cosign 对自己的二进制做密钥签名（企业内可用 KMS 托管密钥）
cosign sign-blob --key cosign.key argocd.exe
cosign verify-blob --key cosign.pub --certificate argocd.exe.pem argocd.exe
```

---

## 5. 方案 E：不落地二进制——用集群里现成的 CLI

Argo CD 官方镜像里同时装了 CLI 和各 server 二进制（Dockerfile：`COPY --from=argocd-build .../dist/argocd* /usr/local/bin/`），
所以 **Pod 里就有 `argocd`**，且版本与 Server **天然一致**（这是最省心的版本对齐方式）。

```bash
# 用集群里的 CLI
kubectl -n argocd exec deploy/argocd-server -- argocd version --client
kubectl -n argocd exec deploy/argocd-server -- argocd app list

# 甚至可以直接把容器里其它工具也用起来
kubectl -n argocd exec deploy/argocd-repo-server -- git --version
```

局限：

- 容器里是 **Linux amd64** 二进制，`kubectl cp` 出来拷到 Windows **跑不了**（只能拿去在 Linux 上用）
- `--core` 模式、受管集群凭证等在 Pod 内执行时语义不同
- 需要有 `kubectl` + 集群访问权限（如果这两样也被禁，此路不通）

---

## 6. 版本对齐（三种方案通用）

CLI 是 gRPC-Web 客户端：**低版本 CLI 连高版本 Server 通常没问题；高版本 CLI 连低版本 Server 会报 unknown field / unsupported。**

```bash
# 1) 查 Server 版本
curl -sk https://argocd.example.com/api/version
# {"Version":"v3.5.6+..."}

# 2) 查 Server 镜像
kubectl -n argocd get deploy argocd-server \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# quay.io/argoproj/argocd:v3.5.6

# 3) 查 CLI 版本
argocd version --client
```

三者对齐规则：

| 你的情况 | 建议 |
|---|---|
| 方案 A（下载二进制） | 手动把 `VERSION` 改成与 Server 一致 |
| 方案 B（Scoop） | Scoop 给的是上游最新版，**不保证一致**；版本差太多时改用方案 A |
| 方案 D（自编译） | 用 `-b v3.5.6` 克隆，并在 `-ldflags` 里写相同的 `common.version` |
| 方案 E（Pod 内） | 天然一致 ✅ |

---

## 7. 故障排查速查表

| 现象 | 原因 | 处理 |
|---|---|---|
| `go: ... does not contain package .../cmd/argocd` | main 包路径错 | 用 `./cmd`（见 1.1）；或干脆别用 `go install` |
| `... contains one or more replace directives` | argo-cd go.mod 有 replace | 同上，`go install pkg@version` 对 argo-cd 结构性不可用 |
| `go: downloading go1.26.3 ... i/o timeout` | Go 版本不足 + 网络受限 | 升级 Go 到 ≥1.26.3；或 `GOTOOLCHAIN=local` 看清晰报错 |
| `pattern all:dist/app/assets/images/resources: no matching files found` | `ui/dist` 被 `git clean -xfd` 清掉 | 见 4.5 的修复命令 |
| `go: module lookup disabled by GOPROXY=off` | 离线但没 vendor | 跑 `go mod vendor`，再加 `-mod=vendor` |
| `open dist/argocd: no such file or directory` | 用 `make cli-local` 但没建 `dist/` | `mkdir -p dist` |
| 编译后 `argocd version --client` 显示 `v99.99.99+unknown` | 漏了 `-ldflags` | 见 4.3 |
| `argocd.exe` 双击闪退 / Git Bash 报 "cannot execute binary file" | 下载损坏（常见于代理截断） | 重新 `curl` 并用 `sha256sum -c` 校验 |
| Windows ARM 机上 `argocd.exe` 慢/异常 | 官方无 arm64 构建，跑的是 amd64 模拟 | 自编译 `GOARCH=arm64`，或走 WSL |
| `argocd login` 后找不到配置 | 配置在 `%USERPROFILE%\.config\argocd\config` | 检查 `$HOME` 是否指向同一目录 |
| Git Bash 里路径含空格报错 | `C:\Program Files\...` 未加引号 | 路径一律用双引号包裹；推荐用 `~/bin` 这种无空格路径 |

---

## 8. 场景决策树

```
需要 argocd.exe
│
├─ 网络能访问 github.com？
│   ├─ 能 ──► 【方案 A】下载官方二进制 + sha256 校验   ← 首选，30 秒搞定
│   │        └─ 想用包管理器？ scoop install argocd
│   └─ 不能
│       │
│       ├─ 有 Docker Desktop？ ──► 【方案 C】docker run quay.io/argoproj/argocd:v3.5.6
│       │
│       ├─ 有集群访问权限？ ───► 【方案 E】kubectl exec 到 argocd-server（版本天然对齐）
│       │
│       └─ 只想要一个二进制
│           ├─ 手上有 Mac/Linux？ ──► 【方案 D7】交叉编译 GOOS=windows 后拷过去
│           └─ 只有这台 Windows
│               ├─ 能访问 proxy.golang.org？ ──► 【方案 D】git clone + go build ./cmd
│               └─ 不能 ──► 【方案 D6】有网机器 go mod vendor → 打包 → 离线 -mod=vendor 编译
│
└─ 合规要求"必须自建可审计产物"？ ──► 无论哪条路，都补上 4.8 的 sha256 + cosign 签名
```

---

## 9. 一键脚本

### 9.1 Git Bash：下载 + 校验 + 装到 PATH

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-v3.5.6}"                 # 与 argocd-server 版本对齐
DEST="${2:-$HOME/bin}"
BASE="https://github.com/argoproj/argo-cd/releases/download/${VERSION}"

mkdir -p "$DEST" && cd "$DEST"
curl -fsSL -o argocd-windows-amd64.exe "${BASE}/argocd-windows-amd64.exe"
curl -fsSL -o cli_checksums.txt "${BASE}/cli_checksums.txt"

grep 'argocd-windows-amd64.exe' cli_checksums.txt | sha256sum -c -
mv argocd-windows-amd64.exe argocd.exe
rm -f cli_checksums.txt

chmod +x argocd.exe
export PATH="$DEST:$PATH"
argocd version --client
```

### 9.2 离线可复现构建（在能上网的机器上跑，产出 Windows exe + 校验和）

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION=v3.5.6
REPO="https://github.com/argoproj/argo-cd.git"
WORK="${WORKDIR:-$HOME/argocd-build}"

rm -rf "$WORK" && mkdir -p "$WORK" && cd "$WORK"
git clone --depth 1 -b "$VERSION" "$REPO" argo-cd
cd argo-cd

go mod vendor                     # 让产物可离线重建

CGO_ENABLED=0 GOOS=windows GOARCH=amd64 \
GODEBUG="tarinsecurepath=0,zipinsecurepath=0" \
go build -trimpath \
  -ldflags "-s -w \
    -X github.com/argoproj/argo-cd/v3/common.version=${VERSION#v} \
    -X github.com/argoproj/argo-cd/v3/common.buildDate=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
    -X github.com/argoproj/argo-cd/v3/common.gitCommit=$(git rev-parse HEAD) \
    -X github.com/argoproj/argo-cd/v3/common.gitTreeState=clean" \
  -o "argocd-windows-amd64.exe" ./cmd

sha256sum argocd-windows-amd64.exe > argocd-windows-amd64.exe.sha256
ls -lh argocd-windows-amd64.exe
cat argocd-windows-amd64.exe.sha256
```

> `-trimpath` 会去掉构建机的绝对路径，便于复现；`-s -w` 去掉调试符号，体积从 ~205 MB 降到 ~147 MB。

---

## 10. 参考

- 官方 CLI 安装文档：<https://argo-cd.readthedocs.io/en/stable/cli_installation/>（Windows 一节只有 PowerShell `Invoke-WebRequest`）
- 官方签名资产说明：<https://argo-cd.readthedocs.io/en/stable/operator-manual/signed-release-assets/>
- Release 页面：<https://github.com/argoproj/argo-cd/releases>
- 源码：<https://github.com/argoproj/argo-cd>（tag `v3.5.6`）
- Scoop manifest：<https://github.com/ScoopInstaller/Main/blob/master/bucket/argocd.json>
- 本目录相关文档：[`argocd-cli-guide.md`](./argocd-cli-guide.md) · [`argocd-admin-guide.md`](./argocd-admin-guide.md)

---

## 附录 A：实测记录（本机 macOS arm64，2026-11）

| 步骤 | 结果 |
|---|---|
| `git clone --depth 1 -b v3.5.6` | ✅ 成功，`ui/dist/app/{gitkeep,assets/images/resources/.gitkeep}` 均在 |
| `go build` 交叉编译 `GOOS=windows GOARCH=amd64` | ✅ **1m35s**，产物 205 MB，`PE32+ executable (console) x86-64` |
| `go build ... -ldflags "-s -w"` | ✅ 147 MB |
| `make cli-local` | ✅ 成功（需先 `mkdir -p dist`），产物 227 MB（调试符号） |
| `make argocd-all GOOS=windows GOARCH=amd64 BIN_NAME=argocd.exe` | ✅ 成功，产物 `dist/argocd.exe` 205 MB，ldflags 自动完整注入 |
| `go mod vendor` | ✅ 18.6s，vendor/ 146 MB |
| `GOPROXY=off GOFLAGS=-mod=vendor go build` | ✅ **43.7s** 完全离线编译成功 |
| `go install github.com/argoproj/argo-cd/v3/cmd/argocd@v3.5.6` | ❌ `does not contain package` |
| `go install github.com/argoproj/argo-cd/v3/cmd@v3.5.6` | ❌ `replace directives` 拒绝 |
| `go install github.com/argoproj/argo-cd/v2/cmd/argocd@v2.11.7` | ❌ 同上 |
| `go install github.com/argoproj/argo-cd/v2/cmd@v2.11.7` | ❌ 同上 |
| `go install ./cmd`（在 clone 内） | ⚠️ 能装，但产物名为 `cmd` 而非 `argocd`；版本显示 `v99.99.99+unknown` |
| Scoop manifest | ✅ 存在，v3.6.1，仅 x64 |
| winget / chocolatey manifest | ❌ 均不存在 |

Go 版本要求：`go.mod` → `go 1.26.3`（官方镜像用 `golang:1.26.10`）。
