可以。对于你的场景，我建议不要追求“装很多工具”，而是建立一个 **不依赖 Homebrew、可放在 `$HOME/bin`、能用 zip/tar.gz 解压、方便校验和删除** 的 GCP/macOS 工具链。

核心原则：

- 优先使用官方发布的单文件二进制或压缩包。
- 安装到 `~/bin`，避免 `sudo` 和写入 `/usr/local/bin`。
- 用 `uname -m` 区分 Apple Silicon 和 Intel。
- 将版本固定在项目或个人目录中，不盲目追最新版。
- 下载后验证 SHA256，特别是公司电脑。
- 把工具分成“必须”“高收益”“按需”三档。

## 一、先准备免安装目录

```bash
mkdir -p "$HOME/bin"
mkdir -p "$HOME/opt"
mkdir -p "$HOME/.config"
```

将 `$HOME/bin` 加入 PATH：

```bash
cat >> "$HOME/.zprofile" <<'EOF'

# Personal portable CLI tools
export PATH="$HOME/bin:$PATH"
EOF

source "$HOME/.zprofile"
```

检查：

```bash
echo "$PATH"
```

如果公司限制不允许修改 `.zprofile`，也可以每次临时执行：

```bash
export PATH="$HOME/bin:$PATH"
```

建议目录结构：

```text
~/bin/
├── gcloud
├── kubectl
├── helm
├── terraform
├── jq
├── yq
└── kustomize

~/opt/
├── google-cloud-sdk/
├── terraform-1.*/
└── kubectl-versions/
```

不要把所有工具直接散落在桌面或 Downloads 中。

## 二、最值得安装的工具

| 优先级 | 工具                | 用途                                     | 推荐安装方式     |
| ------ | ------------------- | ---------------------------------------- | ---------------- |
| 必须   | `gcloud`            | GCP 项目、IAM、GKE、网络、日志、资源管理 | 官方 tar.gz      |
| 必须   | `kubectl`           | Kubernetes/GKE 集群操作                  | 官方单文件二进制 |
| 必须   | `jq`                | 处理 JSON、解析 GCP API 输出             | 官方二进制       |
| 必须   | `curl`              | API、健康检查、下载、调试                | macOS 自带       |
| 必须   | `ssh`               | 连接 VM、IAP、跳板机                     | macOS 自带       |
| 高收益 | `terraform`         | IaC                                      | HashiCorp zip    |
| 高收益 | `helm`              | Helm chart 管理                          | 官方 tar.gz      |
| 高收益 | `yq`                | YAML 查询和修改                          | 官方二进制       |
| 高收益 | `kustomize`         | Kubernetes manifest 组合                 | 官方二进制       |
| 高收益 | `stern`             | 多 Pod 聚合日志                          | GitHub release   |
| 按需   | `k9s`               | Kubernetes 终端 UI                       | GitHub release   |
| 按需   | `grpcurl`           | gRPC 调试                                | GitHub release   |
| 按需   | `gcloud beta/alpha` | GCP 预览功能                             | 随 gcloud        |
| 按需   | `terraform-docs`    | Terraform 文档生成                       | GitHub release   |
| 按需   | `tflint`            | Terraform 静态检查                       | GitHub release   |
| 按需   | `trivy`             | 容器和 IaC 扫描                          | GitHub release   |

Google Cloud CLI 支持 macOS，并且官方提供版本化压缩包；Apple Silicon 使用 arm64 包，Intel Mac 使用 x86_64 包。 [docs.cloud.google](https://docs.cloud.google.com/sdk/docs/downloads-versioned-archives)

## 三、GCP CLI：优先安装 gcloud

先确认架构：

```bash
uname -m
```

结果通常是：

```text
arm64    # Apple Silicon
x86_64   # Intel
```

### Apple Silicon

```bash
cd "$HOME/opt"

curl -LO https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-arm.tar.gz

tar -xzf google-cloud-cli-darwin-arm.tar.gz

rm google-cloud-cli-darwin-arm.tar.gz

"$HOME/opt/google-cloud-sdk/install.sh" \
  --quiet \
  --path-update=false \
  --bash-completion=false
```

将 gcloud 加入 PATH：

```bash
cat >> "$HOME/.zprofile" <<'EOF'

export PATH="$HOME/opt/google-cloud-sdk/bin:$PATH"
EOF

source "$HOME/.zprofile"
```

验证：

```bash
gcloud version
```

初始化：

```bash
gcloud init
```

如果公司账号要求浏览器认证：

```bash
gcloud auth login
```

如果是本地应用默认凭据，例如 Terraform、Python SDK 或本地脚本：

```bash
gcloud auth application-default login
```

常用 GCP 配置：

```bash
gcloud config set project PROJECT_ID
gcloud config set compute/region asia-northeast1
gcloud config set compute/zone asia-northeast1-a
```

查看当前配置：

```bash
gcloud config list
gcloud auth list
gcloud projects list
```

建议给不同工作环境使用不同 configuration：

```bash
gcloud config configurations create work
gcloud config configurations activate work
gcloud config set project YOUR_WORK_PROJECT_ID
```

切换：

```bash
gcloud config configurations list
gcloud config configurations activate work
```

### 更稳妥的安装建议

Google 官方支持把 CLI 解压到 Home 目录，然后运行 `install.sh`；不要求使用 Homebrew。 [docs.cloud.google](https://docs.cloud.google.com/sdk/docs/downloads-versioned-archives)

如果不能执行安装脚本，可以只把目录加入 PATH：

```bash
export PATH="$HOME/opt/google-cloud-sdk/bin:$PATH"
```

但这样可能缺少部分 shell completion 或更新配置。公司环境里建议使用 `--path-update=false`，手动管理 PATH，避免安装脚本修改过多文件。

## 四、kubectl：GKE 必需

Kubernetes 官方建议 `kubectl` 与集群版本保持在一个 minor version 范围内。例如客户端为 1.32 时，通常适用于 1.31、1.32、1.33 集群。 [v1-32.docs.kubernetes](https://v1-32.docs.kubernetes.io/docs/tasks/tools/install-kubectl-macos/)

### Apple Silicon 安装最新版

```bash
cd "$HOME/bin"

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"

chmod +x kubectl
```

Intel Mac：

```bash
cd "$HOME/bin"

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"

chmod +x kubectl
```

验证：

```bash
kubectl version --client
```

GKE 获取凭据：

```bash
gcloud container clusters get-credentials CLUSTER_NAME \
  --region REGION \
  --project PROJECT_ID
```

例如：

```bash
gcloud container clusters get-credentials prod-cluster \
  --region asia-northeast1 \
  --project my-project
```

验证连接：

```bash
kubectl cluster-info
kubectl get nodes
kubectl get namespaces
```

### 固定版本

生产环境不建议始终依赖 `stable.txt`，可以固定版本：

```bash
VERSION="v1.32.4"

curl -LO "https://dl.k8s.io/release/${VERSION}/bin/darwin/arm64/kubectl"
chmod +x kubectl
```

查看服务端版本：

```bash
kubectl version
```

如果你经常维护多个 GKE 集群，建议保留多个版本：

```text
~/bin/
├── kubectl-v1.31
├── kubectl-v1.32
└── kubectl -> kubectl-v1.32
```

切换：

```bash
ln -sf "$HOME/bin/kubectl-v1.31" "$HOME/bin/kubectl"
```

官方也支持把二进制放到 `$HOME/bin`，避免使用 `sudo` 或系统目录。 [docs.aws.amazon](https://docs.aws.amazon.com/en_us/eks/latest/userguide/install-kubectl.html)

## 五、Terraform：直接下载 zip

Terraform 本身是单一可执行文件，下载 zip 后解压即可使用；不需要安装服务或注册系统组件。 [developer.hashicorp](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

先确定版本：

```bash
export TERRAFORM_VERSION="1.16.4"
```

Apple Silicon：

```bash
cd "$HOME/bin"

curl -LO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_darwin_arm64.zip"

unzip -o "terraform_${TERRAFORM_VERSION}_darwin_arm64.zip"

rm "terraform_${TERRAFORM_VERSION}_darwin_arm64.zip"

chmod +x terraform
```

Intel：

```bash
cd "$HOME/bin"

curl -LO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_darwin_amd64.zip"

unzip -o "terraform_${TERRAFORM_VERSION}_darwin_amd64.zip"

rm "terraform_${TERRAFORM_VERSION}_darwin_amd64.zip"

chmod +x terraform
```

验证：

```bash
terraform version
```

如果公司策略不允许执行未验证的下载文件，至少做 SHA256 校验：

```bash
shasum -a 256 terraform_*.zip
```

HashiCorp 提供版本化归档和校验信息，也支持对归档进行完整性验证。 [developer.hashicorp](https://developer.hashicorp.com/terraform/install)

建议项目中固定 Terraform 版本：

```text
infra/
├── .terraform-version
├── main.tf
├── providers.tf
└── versions.tf
```

`.terraform-version`：

```text
1.16.4
```

注意：`.terraform-version` 本身只有在你使用 tfenv 等工具时才会自动生效；Terraform CLI 不会自动读取它来切换版本。公司不能使用 Homebrew 时，可以直接用 `terraform` 单文件版本，或自己写一个简单的版本切换脚本。

## 六、Helm、yq、jq、kustomize

### jq

macOS 通常可能已经带有 `jq`，先检查：

```bash
command -v jq
jq --version
```

如果没有，可以下载官方 release 的 macOS arm64 或 amd64 二进制：

```bash
cd "$HOME/bin"

curl -L \
  -o jq \
  https://github.com/jqlang/jq/releases/latest/download/jq-macos-arm64

chmod +x jq
```

验证：

```bash
jq --version
```

示例：

```bash
gcloud compute instances list --format=json | jq '.[].name'
```

### yq

`yq` 对 YAML 操作非常方便，尤其适合 Kubernetes 和 GitHub Actions 文件。

Apple Silicon：

```bash
cd "$HOME/bin"

curl -L \
  -o yq \
  https://github.com/mikefarah/yq/releases/latest/download/yq_darwin_arm64

chmod +x yq

yq --version
```

查看 Deployment 镜像：

```bash
yq '.spec.template.spec.containers[].image' deployment.yaml
```

批量修改镜像：

```bash
yq -i \
  '.spec.template.spec.containers[0].image = "asia-northeast1-docker.pkg.dev/my-project/repo/app:v2"' \
  deployment.yaml
```

### Helm

下载 Helm release 中对应架构的 tar.gz：

```bash
cd "$HOME/opt"

curl -LO https://get.helm.sh/helm-v3.17.3-darwin-arm64.tar.gz

tar -xzf helm-v3.17.3-darwin-arm64.tar.gz

mv darwin-arm64/helm "$HOME/bin/helm"

rm -rf darwin-arm64 helm-v3.17.3-darwin-arm64.tar.gz

chmod +x "$HOME/bin/helm"
```

验证：

```bash
helm version
```

GKE 私有 Artifact Registry 中使用 Helm 时，可以配置：

```bash
gcloud auth configure-docker asia-northeast1-docker.pkg.dev
```

如果是 OCI Helm registry：

```bash
helm registry login asia-northeast1-docker.pkg.dev \
  -u oauth2accesstoken \
  -p "$(gcloud auth print-access-token)"
```

### kustomize

如果你使用 GitOps、Kustomize overlay 或 Argo CD，这个工具很有价值：

```bash
cd "$HOME/bin"

curl -L \
  -o kustomize.tar.gz \
  https://github.com/kubernetes-sigs/kustomize/releases/latest/download/kustomize_v5.6.0_darwin_arm64.tar.gz

tar -xzf kustomize.tar.gz

chmod +x kustomize

rm kustomize.tar.gz
```

验证：

```bash
kustomize version
```

渲染 manifest：

```bash
kustomize build overlays/prod
```

## 七、强烈推荐的两个日志工具

### stern

`stern` 对多个 Pod、多个容器实时聚合日志非常方便：

```bash
stern api -n production
```

按 label：

```bash
stern . \
  -n production \
  -l app=api
```

只看最近日志：

```bash
stern api \
  -n production \
  --since 30m
```

这通常比反复运行下面的命令高效：

```bash
kubectl logs -f deployment/api -n production
```

### k9s

`k9s` 是终端 Kubernetes UI，适合排查：

- Pod 重启。
- Events。
- ConfigMap。
- Secret。
- Deployment rollout。
- Node 状态。
- Container logs。

它不是必需品，但对日常 GKE 运维提升很明显。建议把它作为“个人便携工具”，不要作为唯一操作方式；脚本和命令行仍然更容易审计和复现。

## 八、网络和 API 调试工具

macOS 自带工具已经足够覆盖大部分工作：

```bash
curl
ssh
scp
dig
nslookup
nc
openssl
awk
sed
grep
cut
sort
uniq
```

建议重点熟练这些命令。

### DNS 检查

```bash
dig example.com
dig +short example.com
dig @8.8.8.8 example.com
```

### TLS 检查

```bash
openssl s_client \
  -connect example.com:443 \
  -servername example.com
```

只看证书摘要：

```bash
echo | openssl s_client \
  -connect example.com:443 \
  -servername example.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

### HTTP 调试

```bash
curl -I https://example.com
curl -v https://example.com
curl --resolve example.com:443:IP_ADDRESS https://example.com
```

### 端口测试

```bash
nc -vz hostname 443
```

### GCP access token 调试

```bash
TOKEN="$(gcloud auth print-access-token)"

curl -H "Authorization: Bearer ${TOKEN}" \
  "https://compute.googleapis.com/compute/v1/projects/PROJECT_ID/zones/ZONE/instances"
```

这类组合对于排查：

- IAM 权限。
- VPC Service Controls。
- Private Google Access。
- 代理。
- mTLS。
- DNS。
- API endpoint。
- OAuth token。

非常有用。

## 九、GCP 相关的实用 shell 别名

可以创建：

```bash
mkdir -p "$HOME/.config/gcp"
touch "$HOME/.config/gcp/aliases.zsh"
```

加入：

```bash
cat >> "$HOME/.config/gcp/aliases.zsh" <<'EOF'
alias gcp-project='gcloud config get-value project'
alias gcp-account='gcloud auth list'
alias gke-contexts='kubectl config get-contexts'
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kctx='kubectl config current-context'

gke-credentials() {
  gcloud container clusters get-credentials "$1" \
    --region "$2" \
    --project "$3"
}
EOF

cat >> "$HOME/.zshrc" <<'EOF'

source "$HOME/.config/gcp/aliases.zsh"
EOF

source "$HOME/.zshrc"
```

使用：

```bash
gke-credentials prod-cluster asia-northeast1 my-project
kgp -n production
```

但要注意，生产环境中不要把过于危险的命令封装成短别名，例如：

```bash
alias kdel='kubectl delete'
```

这种别名容易误操作。可以优先定义只读命令。

## 十、建议的最小安装清单

如果你只能安装少量工具，我建议按这个顺序：

```text
1. gcloud
2. kubectl
3. jq
4. terraform
5. helm
6. yq
7. stern
8. k9s
9. kustomize
10. tflint / trivy / terraform-docs
```

其中最核心的是：

```text
gcloud + kubectl + jq + terraform + helm
```

这五个已经覆盖了绝大多数 GCP cloud infra 工作。

## 十一、一个可重复的便携安装脚本

下面这段不会使用 Homebrew，只会创建目录并检查基础工具：

```bash
#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${HOME}/bin"
OPT_DIR="${HOME}/opt"

mkdir -p "$BIN_DIR" "$OPT_DIR"

cat <<EOF

Portable tool directories created:

  BIN_DIR: $BIN_DIR
  OPT_DIR: $OPT_DIR

Architecture:
  $(uname -m)

Shell:
  $SHELL

Existing commands:
EOF

for command_name in \
  curl \
  ssh \
  openssl \
  dig \
  gcloud \
  kubectl \
  terraform \
  helm \
  jq \
  yq
do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf '  %-12s %s\n' "$command_name" "$(command -v "$command_name")"
  else
    printf '  %-12s missing\n' "$command_name"
  fi
done
```

保存为：

```bash
mkdir -p "$HOME/bin"
nano "$HOME/bin/check-cloud-tools"
chmod +x "$HOME/bin/check-cloud-tools"
```

执行：

```bash
check-cloud-tools
```

## 十二、不要优先安装的工具

在公司受限机器上，以下工具可能不值得一开始安装：

- Docker Desktop：需要系统权限、后台服务和公司安全审批。
- Rancher Desktop：同样可能涉及虚拟机和系统权限。
- Minikube：需要虚拟化或容器运行时。
- Colima：需要额外虚拟化环境。
- GUI 类型的 API 工具：可能被公司软件白名单阻挡。
- 自动修改 shell、证书和代理的安装器。
- 不明来源的“一键安装脚本”。

如果只是操作 GKE，通常不需要在本机运行 Kubernetes。直接使用：

```bash
gcloud
kubectl
helm
terraform
curl
jq
```

就足够了。

## 最终建议

你的公司场景最适合这种组合：

```text
系统自带：
  zsh, ssh, curl, openssl, dig, awk, sed

官方便携包：
  gcloud, kubectl, terraform, helm

GitHub release 二进制：
  jq, yq, stern, k9s, kustomize, tflint, trivy
```

全部安装到：

```text
$HOME/bin
$HOME/opt
```

不需要 Brew，也不需要 `sudo`。其中 `gcloud` 官方提供 macOS arm64/x86_64 压缩包，`kubectl` 官方提供 macOS arm64/amd64 单文件二进制，Terraform 官方提供 zip 归档，因此这套方案与公司“只允许 zip/tar.gz 或便携工具”的限制比较匹配。 [docs.cloud.google](https://docs.cloud.google.com/sdk/docs/downloads-versioned-archives)
