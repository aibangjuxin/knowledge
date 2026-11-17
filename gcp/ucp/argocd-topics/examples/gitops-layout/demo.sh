#!/usr/bin/env bash
# =============================================================================
#  demo.sh · Argo CD GitOps 全流程 Demo
# -----------------------------------------------------------------------------
#  这个脚本把 examples/gitops-layout/ 里的那套结构，**用命令行**完整跑一遍：
#
#     ① 建集群（kind，模拟 dev-01 / dev-02 / prod-01 / prod-02）
#     ② 安装 Argo CD 控制面
#     ③ 起一个本地 Git HTTP 服务，把示例仓库"改写"成演示仓库
#     ④ argocd login 登录
#     ⑤ 注册 Git 仓库（Repository）
#     ⑥ 注册托管集群（Cluster Secret）
#     ⑦ 建 AppProject（边界层）
#     ⑧ 用 CLI 建根 Application（App of Apps 入口）→ Argo CD 自己拉 AppSet
#     ⑨ 等待 Application 生成 + 同步
#     ⑩ 验证：AppProject / ApplicationSet / Application / 集群内真实资源
#     ⑪ 清理
#
#  用法：
#     ./demo.sh                 # = plan + apply + verify（推荐第一次跑）
#     ./demo.sh plan            # 只打印将要执行的命令（离线，不需要任何环境）
#     ./demo.sh apply           # 只执行创建
#     ./demo.sh verify          # 只做验证（对已建好的环境）
#     ./demo.sh cleanup         # 清理（删 kind 集群 / 停服务 / 删工作目录）
#
#  依赖：bash>=3.2（macOS 自带 3.2 也能跑）、docker、kind、kubectl、argocd、git、python3
#  目标环境：Linux（生产用法）；macOS 同样可用（脚本已做兼容处理）
#
#  ⚠️ 安全提示：脚本**不会**修改你的原始仓库。所有改写（repoURL / server 地址）
#     都发生在 $WORKDIR 下的副本里。
# =============================================================================

set -Eeuo pipefail

# =============================================================================
# 0. 路径与默认值
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../examples/gitops-layout
UC_P_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"               # ucp/（仓库根）

WORKDIR="${WORKDIR:-${TMPDIR:-/tmp}/ucp-gitops-demo}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
CTRL_CLUSTER="${CTRL_CLUSTER:-argocd}"        # Argo CD 控制面所在的 kind 集群
CLUSTERS="${CLUSTERS:-dev-01 dev-02 prod-01 prod-02}"
REPO_NAME="${REPO_NAME:-ucp-gitops-demo}"
GIT_PORT="${GIT_PORT:-18081}"                 # 本地 Git HTTP 服务端口
ARGO_PORT="${ARGO_PORT:-18080}"               # Argo CD API 本地转发端口
ARGOCD_MANIFEST="${ARGOCD_MANIFEST:-}"        # Argo CD 安装清单（本地路径或 URL）
REPO_URL="${REPO_URL:-}"                      # 留空 = 自动起本地 Git HTTP 服务
KIND_VERSION="${KIND_VERSION:-v0.30.0}"
ARGOCD_CLI_VERSION="${ARGOCD_CLI_VERSION:-v3.5.6}"

WITH_GATEKEEPER="${WITH_GATEKEEPER:-0}"      # 1 = 保留 OPA 组件（需要 Gatekeeper CRD）
WITH_GATEWAY="${WITH_GATEWAY:-0}"            # 1 = 保留 Gateway 组件（需要 Gateway API CRD）
INSTALL_TOOLS="${INSTALL_TOOLS:-0}"          # 1 = 自动下载 kind / argocd CLI
KEEP="${KEEP:-0}"                            # 1 = 结束后保留工作目录
DRY_RUN=0

# 运行时状态
GIT_PID=""
PORTFWD_PID=""
ARGOCD_SERVER=""
ARGOCD_PASSWORD=""
BIN_DIR="$WORKDIR/bin"
# 自动下载的 kind / argocd 放到这里 → 提前加进 PATH（否则后面找不到）
mkdir -p "$BIN_DIR" 2>/dev/null || true
export PATH="$BIN_DIR:$PATH"

# =============================================================================
# 1. 输出 helpers（macOS / Linux 通用）
# =============================================================================

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'; C_BLD=$'\033[1m';  C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_BLD=""; C_RST=""
fi

log()  { printf '%s\n' "$*"; }
info() { printf '%s==>%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
err()  { printf '%s  ✗%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

section() {
  printf '\n%s%s%s\n' "$C_BLD" "════════════════════════════════════════════════════════════" "$C_RST"
  printf '%s%s%s\n' "$C_BLD" "$*" "$C_RST"
  printf '%s%s%s\n' "$C_BLD" "════════════════════════════════════════════════════════════" "$C_RST"
}

# 统一的"执行 or 打印"包装：plan 模式只打印命令
run() {
  local desc="$1"; shift
  printf '  %s\n' "$C_BLD$desc$C_RST"
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    $ %s\n' "$*"
    return 0
  fi
  "$@"
}

# 需要 shell 展开（管道 / 重定向 / 变量）的复杂命令用这个
run_sh() {
  local desc="$1"; local body="$2"
  printf '  %s\n' "$C_BLD$desc$C_RST"
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    $ %s\n' "$body"
    return 0
  fi
  bash -c "$body"
}

have() { command -v "$1" >/dev/null 2>&1; }

# base64 解码（从 stdin 读；macOS 的 base64 与 GNU 的参数不一样）
# 依次尝试三种写法，哪种能用就用哪种 —— 因为 macOS 自带的 base64
# 不认 --decode，而 GNU coreutils 的 base64 不认 -d。
b64d() {
  local data; data="$(cat)"
  if printf '%s' "$data" | base64 -d 2>/dev/null; then return 0; fi
  if printf '%s' "$data" | base64 --decode 2>/dev/null; then return 0; fi
  printf '%s' "$data" | openssl base64 -d -A 2>/dev/null
}

# =============================================================================
# 2. 参数解析
# =============================================================================

usage() {
  cat <<'EOF'
用法: demo.sh [命令] [选项]

命令:
  plan       只打印将要执行的完整命令（离线，无需 docker/kind/集群）
  apply      执行创建（建集群 → 装 Argo CD → 建 AppProject/AppSet/App → 同步）
  verify     对已经建好的环境做验证与资源清单罗列
  cleanup    清理：删 kind 集群、停后台服务、（可选）删工作目录
  demo       plan + apply + verify（默认）

选项:
  --clusters "dev-01 dev-02"   参与演示的集群（默认 dev-01 dev-02 prod-01 prod-02）
  --repo-url URL               用你自己的 Git 仓库（跳过本地 Git 服务）
  --argocd-manifest PATH|URL   Argo CD 安装清单（默认用仓库根的 install.yaml）
  --with-gatekeeper            保留 OPA 组件（需要先装 Gatekeeper CRD）
  --with-gateway               保留 Gateway 组件（需要先装 Gateway API CRD）
  --install-tools              自动下载 kind / argocd CLI 到工作目录
  --keep                       结束后保留工作目录
  --no-color                   关掉颜色
  -h, --help                   显示本帮助

示例:
  ./demo.sh plan
  ./demo.sh --clusters "dev-01" apply
  ./demo.sh --repo-url https://github.com/myorg/platform.git apply
EOF
}

CMD="demo"
while [[ $# -gt 0 ]]; do
  case "$1" in
    plan|apply|verify|cleanup|demo) CMD="$1"; shift ;;
    --clusters) CLUSTERS="$2"; shift 2 ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --argocd-manifest) ARGOCD_MANIFEST="$2"; shift 2 ;;
    --with-gatekeeper) WITH_GATEKEEPER=1; shift ;;
    --with-gateway) WITH_GATEWAY=1; shift ;;
    --install-tools) INSTALL_TOOLS=1; shift ;;
    --keep) KEEP=1; shift ;;
    --no-color) NO_COLOR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "未知参数: $1"; usage; exit 1 ;;
  esac
done

# =============================================================================
# 3. 工具准备
# =============================================================================

detect_platform() {
  local os arch
  case "$(uname -s)" in
    Linux)  os=linux ;;
    Darwin) os=darwin ;;
    *) die "不支持的操作系统: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) die "不支持的架构: $(uname -m)" ;;
  esac
  printf '%s-%s' "$os" "$arch"
}

install_kind() {
  if have kind; then
    ok "kind 已安装: $(kind version 2>/dev/null | head -1)"
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    log "    $ kind download  → $BIN_DIR/kind   (需要网络)"
    return 0
  fi
  [[ $INSTALL_TOOLS -eq 1 ]] || die "找不到 kind。请安装后重试，或加 --install-tools 让脚本自动下载。"
  local plat; plat="$(detect_platform)"
  mkdir -p "$BIN_DIR"
  info "下载 kind ${KIND_VERSION} ($plat)"
  curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${plat}" -o "$BIN_DIR/kind" \
    || die "下载 kind 失败（需要网络）"
  chmod +x "$BIN_DIR/kind"
  ok "kind 已就绪: $BIN_DIR/kind"
}

install_argocd_cli() {
  if have argocd; then
    ok "argocd CLI 已安装: $(argocd version --short 2>/dev/null || argocd version 2>/dev/null | head -1)"
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    log "    $ curl argocd CLI ${ARGOCD_CLI_VERSION} → $BIN_DIR/argocd   (需要网络)"
    return 0
  fi
  [[ $INSTALL_TOOLS -eq 1 ]] || die "找不到 argocd CLI。请安装后重试，或加 --install-tools。"
  local plat; plat="$(detect_platform)"
  mkdir -p "$BIN_DIR"
  info "下载 argocd CLI ${ARGOCD_CLI_VERSION} ($plat)"
  curl -fsSL "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_CLI_VERSION}/argo-cd-${plat}" \
    -o "$BIN_DIR/argocd" || die "下载 argocd CLI 失败（需要网络）"
  chmod +x "$BIN_DIR/argocd"
  ok "argocd CLI 已就绪: $BIN_DIR/argocd"
}

resolve_argocd_manifest() {
  if [[ -n "$ARGOCD_MANIFEST" ]]; then printf '%s' "$ARGOCD_MANIFEST"; return 0; fi
  local local_manifest="$UC_P_ROOT/install.yaml"
  if [[ -f "$local_manifest" ]]; then printf '%s' "$local_manifest"; return 0; fi
  printf '%s' "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
}

# =============================================================================
# 4. STEP 00 · 环境自检
# =============================================================================

step_preflight() {
  section "STEP 00 · 环境自检"
  log "  bash: ${BASH_VERSION}"
  log "  OS:   $(uname -s) $(uname -m)"

  local missing=0 c
  for c in kubectl git python3 curl; do
    if have "$c"; then ok "$c: $(command -v "$c")"; else err "缺少 $c"; missing=1; fi
  done
  [[ $missing -eq 0 ]] || die "缺少基础工具，请先安装"

  if have docker; then
    if docker info >/dev/null 2>&1; then
      ok "docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    elif [[ $DRY_RUN -eq 1 ]]; then
      warn "docker daemon 没跑起来（plan 模式不阻塞）"
    else
      die "docker 客户端在，但 daemon 没跑起来。请先启动 Docker。"
    fi
  else
    [[ $DRY_RUN -eq 1 ]] || die "找不到 docker。本 Demo 用 kind 起临时集群。"
    warn "找不到 docker（plan 模式不阻塞）"
  fi

  install_kind
  install_argocd_cli
  ok "工作目录: $WORKDIR"
}

# =============================================================================
# 5. STEP 01 · 创建演示集群
# =============================================================================

# kind 的容器名是 <cluster>-control-plane，且所有 kind 集群共享同一个 docker
# 网络 → Argo CD（在 argocd 集群里）可以直接用 https://<cluster>-control-plane:6443
# 访问其它集群。这就是写进 cluster.yaml 的 server 地址。
kind_cluster_url() { printf 'https://%s-control-plane:6443' "$1"; }

step_create_clusters() {
  section "STEP 01 · 创建演示集群（kind）"
  log "  说明：Argo CD 控制面单独放在一个 kind 集群里（$CTRL_CLUSTER），"
  log "        其余集群模拟被纳管的业务集群（$CLUSTERS）。"
  log "        它们共享 docker 的 kind 网络 → 集群之间可以用容器名互访。"

  # 控制面集群：Linux 上需要把 host.docker.internal 指到宿主机 docker 网关，
  # 否则容器里的 Argo CD 访问不到宿主机上的 Git HTTP 服务。
  local kind_cfg="$WORKDIR/kind-${CTRL_CLUSTER}.yaml"
  mkdir -p "$WORKDIR"
  {
    printf 'kind: Cluster\napiVersion: kind.x-k8s.io/v1alpha4\nnodes:\n- role: control-plane\n'
    if [[ "$(uname -s)" != "Darwin" ]]; then
      local gw
      gw="$(docker network inspect kind -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
      if [[ -n "$gw" ]]; then
        printf '  extraHostEntries:\n  - ip: %s\n    hostnames: ["host.docker.internal"]\n' "$gw"
        log "  已把 host.docker.internal 指向 docker 网关 $gw"
      fi
    else
      log "  macOS：Docker Desktop 自带 host.docker.internal，无需额外配置"
    fi
  } > "$kind_cfg"

  local c
  for c in $CTRL_CLUSTER $CLUSTERS; do
    if [[ $DRY_RUN -eq 0 ]] && kind get clusters 2>/dev/null | grep -qx "$c"; then
      ok "kind 集群 $c 已存在，跳过"
      continue
    fi
    if [[ "$c" == "$CTRL_CLUSTER" ]]; then
      run "创建 kind 集群 $c" kind create cluster --name "$c" --config "$kind_cfg" --wait 120s
    else
      run "创建 kind 集群 $c" kind create cluster --name "$c" --wait 120s
    fi
  done

  run "列出 kind 集群" kind get clusters
}

# =============================================================================
# 6. STEP 02 · 安装 Argo CD 控制面
# =============================================================================

step_install_argocd() {
  section "STEP 02 · 安装 Argo CD 控制面"
  local manifest; manifest="$(resolve_argocd_manifest)"
  log "  安装清单: $manifest"
  log "  说明：Argo CD 的各个 Deployment（server / repo-server / redis / dex …）"
  log "        就绪之后，我们才能用 CLI 登录并创建 Application。"

  run_sh "创建 namespace" \
    "kubectl --context 'kind-$CTRL_CLUSTER' create namespace '$ARGOCD_NS' --dry-run=client -o yaml | kubectl --context 'kind-$CTRL_CLUSTER' apply -f -"
  run "安装 Argo CD" kubectl --context "kind-$CTRL_CLUSTER" apply -n "$ARGOCD_NS" -f "$manifest"
  run "等待 Deployment 就绪" kubectl --context "kind-$CTRL_CLUSTER" -n "$ARGOCD_NS" wait --for=condition=Available deploy --all --timeout=300s
}

# =============================================================================
# 7. STEP 03 · 准备演示用 Git 仓库
# =============================================================================

# 本地 Git smart-HTTP 服务（包装 git http-backend）。
# 为什么不用 git daemon：git:// 协议能否被 Argo CD 接受取决于版本，
# http:// + smart protocol 是最通用的本地做法。
write_git_http_server() {
  cat > "$BIN_DIR/git_http_server.py" <<'PYEOF'
#!/usr/bin/env python3
"""最小 Git smart-HTTP 服务（包装 git http-backend）。"""
import os, subprocess, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = sys.argv[1]
PORT = int(sys.argv[2])


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _proxy(self):
        path, _, query = self.path.partition('?')
        length = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(length) if length else b''
        env = dict(os.environ)
        env.update({
            'GIT_PROJECT_ROOT': ROOT,
            'GIT_HTTP_EXPORT_ALL': '1',
            'REQUEST_METHOD': self.command,
            'PATH_INFO': path,
            'QUERY_STRING': query,
            'CONTENT_TYPE': self.headers.get('Content-Type', ''),
            'CONTENT_LENGTH': str(length),
            'REMOTE_USER': 'git',
            'REMOTE_ADDR': self.client_address[0],
            'SERVER_PROTOCOL': 'HTTP/1.1',
            'HTTP_CONTENT_ENCODING': self.headers.get('Content-Encoding', ''),
            'GIT_AUTHOR_NAME': 'demo', 'GIT_AUTHOR_EMAIL': 'demo@localhost',
            'GIT_COMMITTER_NAME': 'demo', 'GIT_COMMITTER_EMAIL': 'demo@localhost',
        })
        proc = subprocess.run(['git', 'http-backend'], input=body, env=env, capture_output=True)
        head, sep, payload = proc.stdout.partition(b'\r\n\r\n')
        status, headers = 200, []
        for line in head.split(b'\r\n'):
            if not line:
                continue
            key, _, value = line.partition(b':')
            key = key.decode().strip()
            value = value.decode().strip()
            if key.lower() == 'status':
                status = int(value.split()[0])
            else:
                headers.append((key, value))
        self.send_response(status)
        for key, value in headers:
            self.send_header(key, value)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = _proxy
    do_POST = _proxy

    def log_message(self, *_args):
        pass


if __name__ == '__main__':
    srv = ThreadingHTTPServer(('0.0.0.0', PORT), Handler)
    print('git http server on :%d root=%s' % (PORT, ROOT), flush=True)
    srv.serve_forever()
PYEOF
}

# 把示例仓库复制一份并改写地址（repoURL / 各集群 server / 演示用镜像）
write_rewriter() {
  cat > "$BIN_DIR/rewrite_manifests.py" <<'PYEOF'
#!/usr/bin/env python3
"""复制 gitops-layout 并改写其中的 repoURL / server / 镜像。"""
import argparse, json, os, shutil

ap = argparse.ArgumentParser()
ap.add_argument('--src', required=True)
ap.add_argument('--dst', required=True)
ap.add_argument('--repo-url', required=True)
ap.add_argument('--cluster-map', required=True)   # JSON: {"dev-01": "https://..."}
ap.add_argument('--keep-components', default='')  # 逗号分隔，保留的集群级组件
args = ap.parse_args()

src, dst = os.path.abspath(args.src), os.path.abspath(args.dst)
cmap = json.loads(args.cluster_map)
keep = {c for c in args.keep_components.split(',') if c}

if os.path.exists(dst):
    shutil.rmtree(dst)
shutil.copytree(src, dst, ignore=shutil.ignore_patterns('.git'))

for junk in ('README.md', 'preview-appset.py', 'validate-clusters.py', 'demo.sh',
             'appset-simulator.py', 'render-check.py', 'ci-check.sh',
             'new-cluster.sh', 'enable-component.sh',
             'render-check.policy.yaml', 'appset-simulator.policy.yaml'):
    p = os.path.join(dst, junk)
    if os.path.exists(p):
        os.remove(p)

clusters_dir = os.path.join(dst, 'bootstrap', 'clusters')

# 1) 只保留选中的集群
for name in sorted(os.listdir(clusters_dir)):
    if name.startswith('_'):
        continue
    path = os.path.join(clusters_dir, name)
    if not os.path.isdir(path):      # README.md 之类的普通文件，跳过
        continue
    if name not in cmap:
        shutil.rmtree(path)

# 2) 改写所有文本文件里的地址
for root, _dirs, files in os.walk(dst):
    for name in files:
        if not name.endswith(('.yaml', '.yml')):
            continue
        path = os.path.join(root, name)
        with open(path, encoding='utf-8') as fh:
            text = fh.read()
        original = text
        for cluster, url in cmap.items():
            text = text.replace('https://%s.k8s.example.com' % cluster, url)
        text = text.replace('https://github.com/example/platform.git', args.repo_url)
        # 示例里的私有镜像不存在 → 换成公开镜像，让 Demo 能真的同步成功
        text = text.replace('ghcr.io/example/api:1.0.0', 'nginx:1.27-alpine')
        if text != original:
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write(text)

# 3) 集群级组件（OPA / Gateway）依赖 CRD，默认摘掉
for comp in ('gatekeeper', 'gateway'):
    if comp in keep:
        continue
    for name in sorted(os.listdir(clusters_dir)):
        if name.startswith('_') or not os.path.isdir(os.path.join(clusters_dir, name)):
            continue
        p = os.path.join(clusters_dir, name, 'components', comp + '.yaml')
        if os.path.exists(p):
            os.remove(p)

# 4) Repository 换成无凭据版本（本地 HTTP 仓库不需要认证）
repo_manifest = """apiVersion: argoproj.io/v1alpha1
kind: Repository
metadata:
  name: platform-repo
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: platform
spec:
  url: %s
  type: git
  insecure: true
""" % args.repo_url
with open(os.path.join(dst, 'bootstrap', 'repositories.yaml'), 'w', encoding='utf-8') as fh:
    fh.write(repo_manifest)

print('演示仓库已生成: %s' % dst)
print('  repoURL   : %s' % args.repo_url)
for cluster, url in sorted(cmap.items()):
    print('  %-9s -> %s' % (cluster, url))
PYEOF
}

# 打印 Application 状态汇总（兼容 v2/v3 不同的 JSON 形状）
write_app_status_helper() {
  cat > "$BIN_DIR/app_status.py" <<'PYEOF'
#!/usr/bin/env python3
"""把 `argocd app list -o json` 汇总成一张表。用法: app_status.py <json> [--not-synced]"""
import json, sys

raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    data = data.get('items', [])

if '--not-synced' in sys.argv:
    print(sum(1 for a in data
              if (a.get('status', {}) or {}).get('sync', {}).get('status') != 'Synced'))
    sys.exit(0)

print('  %-24s %-10s %-10s %s' % ('APP', 'SYNC', 'HEALTH', 'DESTINATION'))
for a in sorted(data, key=lambda x: x.get('metadata', {}).get('name', '')):
    st = a.get('status', {}) or {}
    sync = (st.get('sync') or {}).get('status', '-')
    health = (st.get('health') or {}).get('status', '-')
    dest = (a.get('spec', {}).get('destination') or {}).get('server', '-')
    print('  %-24s %-10s %-10s %s' % (a.get('metadata', {}).get('name', '?'), sync, health, dest))
PYEOF
}

step_prepare_repo() {
  section "STEP 03 · 准备演示用 Git 仓库"
  log "  说明：Argo CD 只认 Git 里的清单，所以这里："
  log "        ① 把示例仓库复制一份到 $WORKDIR/repo"
  log "        ② 改写 repoURL（指向本地 Git 服务）和各集群的 server（指向 kind 集群）"
  log "        ③ git init + commit + 裸仓库，供 Argo CD 拉取"

  mkdir -p "$WORKDIR/repo" "$BIN_DIR"
  write_rewriter
  write_git_http_server
  write_app_status_helper

  if [[ -z "$REPO_URL" ]]; then
    REPO_URL="http://host.docker.internal:${GIT_PORT}/${REPO_NAME}.git"
    log "  本地 Git 服务地址: $REPO_URL"

    if [[ $DRY_RUN -eq 0 ]]; then
      nohup python3 "$BIN_DIR/git_http_server.py" "$WORKDIR" "$GIT_PORT" \
        > "$WORKDIR/git-http.log" 2>&1 &
      GIT_PID=$!
      printf '%s' "$GIT_PID" > "$WORKDIR/git-http.pid"
      sleep 1
      ok "Git HTTP 服务已启动 (pid $GIT_PID)"
    else
      run "启动 Git HTTP 服务" echo "python3 '$BIN_DIR/git_http_server.py' '$WORKDIR' '$GIT_PORT' &"
    fi
  else
    log "  使用外部仓库: $REPO_URL"
  fi

  # 集群 → server 地址映射（JSON）
  # 手工拼 JSON：集群名是 dev-01 这种形式，值是 URL，不含需要转义的字符。
  local map_json="" c first=1
  for c in $CLUSTERS; do
    if [[ $first -eq 1 ]]; then
      map_json="{\"$c\":\"$(kind_cluster_url "$c")\"}"
      first=0
    else
      map_json="$map_json,\"$c\":\"$(kind_cluster_url "$c")\"}"
    fi
  done

  local keep_components=""
  [[ $WITH_GATEKEEPER -eq 1 ]] && keep_components="gatekeeper"
  [[ $WITH_GATEWAY -eq 1 ]] && keep_components="${keep_components:+$keep_components,}gateway"

  run_sh "改写清单地址" \
    "python3 '$BIN_DIR/rewrite_manifests.py' --src '$SCRIPT_DIR' --dst '$WORKDIR/repo' --repo-url '$REPO_URL' --cluster-map '$map_json' --keep-components '$keep_components'"

  run_sh "初始化 Git 仓库" \
    "cd '$WORKDIR/repo' && git init -q -b main && git add -A && git -c user.email=demo@localhost -c user.name=demo commit -qm 'demo: gitops layout' && git clone -q --bare . '$WORKDIR/${REPO_NAME}.git' && echo '裸仓库: $WORKDIR/${REPO_NAME}.git'"

  run "校验改写后的集群清单" python3 "$SCRIPT_DIR/validate-clusters.py" --path "$WORKDIR/repo"
}

# =============================================================================
# 8. STEP 04 · 登录 Argo CD
# =============================================================================

ensure_port_forward() {
  # 端口转发是"验证"命令的前置条件；已存在就别重复起
  # （重复起会占端口，报 "address already in use"）。
  if [[ -n "$PORTFWD_PID" ]] && kill -0 "$PORTFWD_PID" 2>/dev/null; then
    return 0
  fi
  nohup kubectl --context "kind-$CTRL_CLUSTER" -n "$ARGOCD_NS" \
    port-forward svc/argocd-server "$ARGO_PORT:80" --address 127.0.0.1 \
    > "$WORKDIR/portforward.log" 2>&1 &
  PORTFWD_PID=$!
  printf '%s' "$PORTFWD_PID" > "$WORKDIR/portforward.pid"
  sleep 3
}

step_login() {
  section "STEP 04 · 登录 Argo CD（argocd login）"
  log "  说明：Argo CD 首次安装会生成一个一次性 admin 密码"
  log "        （Secret: argocd-initial-admin-secret）。CLI 登录后会把 token"
  log "        存到本机 ~/.local/share/argocd/…，后续命令不用重复登录。"

  run_sh "端口转发 Argo CD API" \
    "kubectl --context 'kind-$CTRL_CLUSTER' -n '$ARGOCD_NS' port-forward svc/argocd-server '$ARGO_PORT:80' --address 127.0.0.1 > '$WORKDIR/portforward.log' 2>&1 & echo \$! > '$WORKDIR/portforward.pid'"
  if [[ $DRY_RUN -eq 0 ]]; then
    PORTFWD_PID="$(cat "$WORKDIR/portforward.pid")"
    sleep 2
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "  （plan 模式：跳过实际登录）"
    return 0
  fi

  ARGOCD_PASSWORD="$(kubectl --context "kind-$CTRL_CLUSTER" -n "$ARGOCD_NS" \
    get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | b64d)"
  [[ -n "$ARGOCD_PASSWORD" ]] || die "取不到 admin 密码（Secret argocd-initial-admin-secret）"

  # argocd-server 同时提供 http 与 https：先试 http（免 TLS 折腾），失败再试 https
  if argocd login "http://127.0.0.1:${ARGO_PORT}" --username admin --password "$ARGOCD_PASSWORD" >/dev/null 2>&1; then
    ARGOCD_SERVER="http://127.0.0.1:${ARGO_PORT}"
  elif argocd login "https://127.0.0.1:${ARGO_PORT}" --username admin --password "$ARGOCD_PASSWORD" --insecure >/dev/null 2>&1; then
    ARGOCD_SERVER="https://127.0.0.1:${ARGO_PORT}"
  else
    die "argocd login 失败。查看 $WORKDIR/portforward.log"
  fi
  ok "已登录: $ARGOCD_SERVER"
  run "确认账号" argocd account get
}

# =============================================================================
# 9. STEP 05 · 注册 Git 仓库
# =============================================================================

step_register_repo() {
  section "STEP 05 · 注册 Git 仓库（Repository）"
  log "  说明：Repository 是 Argo CD 的仓库/凭据登记处。生产用 GitHub App 或 PAT；"
  log "        本地 Demo 用无凭据的 http 仓库（spec.insecure: true）。"

  run_sh "创建 Repository" \
    "kubectl --context 'kind-$CTRL_CLUSTER' -n '$ARGOCD_NS' apply -f '$WORKDIR/repo/bootstrap/repositories.yaml'"
  run "查看仓库列表" argocd repo list
}

# =============================================================================
# 10. STEP 06 · 注册被纳管的集群
# =============================================================================

step_register_clusters() {
  section "STEP 06 · 注册被纳管的集群（Cluster Secret）"
  log "  说明：Argo CD 认识一个集群，靠的是 argocd namespace 里的一个 Secret"
  log "        （label: argocd.argoproj.io/secret-type=cluster）。"
  log "        这里用 kubectl 声明式创建（生产也常用 argocd cluster add）。"
  log "        地址用容器名 https://<cluster>-control-plane:6443 —— 只有集群内可达。"

  local c
  for c in $CLUSTERS; do
    if [[ $DRY_RUN -eq 1 ]]; then
      run "为 $c 创建 Cluster Secret" \
        echo "kubectl -n '$ARGOCD_NS' create secret generic '$c' --from-literal=name='$c' --from-literal=server='$(kind_cluster_url "$c")' --from-literal=config='{\"bearerToken\":\"<token>\",\"tlsClientConfig\":{\"insecure\":true}}' && kubectl -n '$ARGOCD_NS' label secret '$c' argocd.argoproj.io/secret-type=cluster"
      continue
    fi

    # 造一个 cluster-admin 的 SA + token，供 Argo CD 操作该集群
    kubectl --context "kind-$c" create sa argocd-demo -n kube-system --dry-run=client -o yaml \
      | kubectl --context "kind-$c" apply -f - >/dev/null
    kubectl --context "kind-$c" create clusterrolebinding argocd-demo \
      --clusterrole=cluster-admin --serviceaccount=kube-system:argocd-demo >/dev/null 2>&1 || true

    local token
    token="$(kubectl --context "kind-$c" create token argocd-demo -n kube-system --duration=8760h 2>/dev/null || true)"
    if [[ -z "$token" ]]; then
      token="$(kubectl --context "kind-$c" create token argocd-demo -n kube-system --duration=24h 2>/dev/null || true)"
    fi
    [[ -n "$token" ]] || die "拿不到 $c 的 ServiceAccount token"

    kubectl --context "kind-$CTRL_CLUSTER" -n "$ARGOCD_NS" create secret generic "$c" \
      --type=Opaque \
      --from-literal="name=$c" \
      --from-literal="server=$(kind_cluster_url "$c")" \
      --from-literal="config={\"bearerToken\":\"$token\",\"tlsClientConfig\":{\"insecure\":true}}" \
      --dry-run=client -o yaml \
      | kubectl --context "kind-$CTRL_CLUSTER" -n "$ARGOCD_NS" apply -f - >/dev/null
    kubectl --context "kind-$CTRL_CLUSTER" -n "$ARGOCD_NS" label secret "$c" \
      argocd.argoproj.io/secret-type=cluster --overwrite >/dev/null
    ok "集群 $c 已注册"
  done

  run "查看 Argo CD 眼中的集群" argocd cluster list
}

# =============================================================================
# 11. STEP 07 · 创建 AppProject（边界层）
# =============================================================================

step_create_projects() {
  section "STEP 07 · 创建 AppProject（边界层：能做什么）"
  log "  说明：AppProject 定义「允许的源仓库 / 目标集群 / 资源类型 / 谁能动」。"
  log "        ⚠️ 必须**先于**根应用创建 —— 否则根应用引用的 project 不存在，"
  log "           第一次同步就会报 \"project not found\"。"

  run_sh "apply AppProject" \
    "kubectl --context 'kind-$CTRL_CLUSTER' -n '$ARGOCD_NS' apply -f '$WORKDIR/repo/bootstrap/appprojects/'"
  run "查看 AppProject 列表" argocd proj list
}

# =============================================================================
# 12. STEP 08 · 创建根 Application（App of Apps 入口）
# =============================================================================

step_create_root_app() {
  section "STEP 08 · 创建根 Application（App of Apps 入口）"
  log "  说明：根应用只同步 bootstrap/ 目录；bootstrap/ 里的 ApplicationSet 被应用后，"
  log "        会自动为每个「集群 × 组件」生成一个 Application。"
  log "        这里用 CLI 创建，验证「命令行也能驱动整套体系」。"

  if [[ $DRY_RUN -eq 1 ]]; then
    run "创建根应用" \
      echo "argocd app create root-bootstrap --repo '$REPO_URL' --path bootstrap --dest-server https://kubernetes.default.svc --dest-namespace '$ARGOCD_NS' --project platform --sync-policy automated --self-heal --prune"
    return 0
  fi

  # 同名应用已存在就先删掉（不带级联删除，集群资源保留）
  argocd app delete root-bootstrap --cascade=false --server "$ARGOCD_SERVER" >/dev/null 2>&1 || true

  argocd app create root-bootstrap \
    --repo "$REPO_URL" \
    --path bootstrap \
    --dest-server https://kubernetes.default.svc \
    --dest-namespace "$ARGOCD_NS" \
    --project platform \
    --sync-policy automated \
    --self-heal \
    --prune \
    --server "$ARGOCD_SERVER" >/dev/null
  ok "根应用已创建"

  run "查看根应用" argocd app get root-bootstrap --server "$ARGOCD_SERVER"
}

# =============================================================================
# 13. STEP 09 · 等待生成与同步
# =============================================================================

step_wait_sync() {
  section "STEP 09 · 等待 Application 生成与同步"
  log "  说明：ApplicationSet 是**异步**工作的 —— 根应用同步成功后，"
  log "        控制器才会去扫 Git 里的 clusters/*/components/*.yaml 生成 Application。"
  log "        生成出来的 Application 再各自去同步自己那份 overlay。"

  if [[ $DRY_RUN -eq 1 ]]; then
    run "等待根应用同步" echo "argocd app wait root-bootstrap --sync --timeout 300s"
    run "等待子应用同步" echo "轮询 argocd app list -o json，直到全部 Synced"
    return 0
  fi

  argocd app wait root-bootstrap --sync --timeout 300s --server "$ARGOCD_SERVER" \
    || warn "根应用未在超时内达成 Synced（继续往下看状态）"

  # 等 ApplicationSet 生成出 Application
  local n
  for _ in $(seq 1 30); do
    n="$(argocd app list --server "$ARGOCD_SERVER" -o name 2>/dev/null | grep -c . || true)"
    [[ "${n:-0}" -gt 1 ]] && break
    sleep 5
  done
  ok "已生成 ${n:-0} 个 Application"

  # 等所有 Application 同步完成
  for _ in $(seq 1 60); do
    local pending
    pending="$(argocd app list --server "$ARGOCD_SERVER" -o json 2>/dev/null \
      | python3 "$BIN_DIR/app_status.py" --not-synced 2>/dev/null || echo 1)"
    [[ "${pending:-1}" == "0" ]] && break
    sleep 5
  done
  ok "同步流程结束"
}

# =============================================================================
# 14. STEP 10 · 验证与资源清单罗列
# =============================================================================

step_verify() {
  section "STEP 10 · 验证与资源清单"

  if [[ $DRY_RUN -eq 1 ]]; then
    log "  （plan 模式：只列出会执行的验证命令）"
    run "AppProject 列表" echo "argocd proj list"
    run "ApplicationSet 列表" echo "argocd appset list"
    run "Application 列表" echo "argocd app list -o wide"
    run "集群内资源" echo "kubectl --context kind-dev-01 -n platform-dev get deploy,svc,po"
    return 0
  fi

  ARGOCD_SERVER="${ARGOCD_SERVER:-http://127.0.0.1:${ARGO_PORT}}"
  ensure_port_forward

  log ""
  log "① AppProject（边界层）"
  argocd proj list --server "$ARGOCD_SERVER" || true

  log ""
  log "② ApplicationSet（生成层）"
  argocd appset list --server "$ARGOCD_SERVER" || true

  log ""
  log "③ Application（同步单元）"
  argocd app list -o wide --server "$ARGOCD_SERVER" || true

  log ""
  log "④ Argo CD 控制面里的 CR 清单"
  kubectl --context "kind-$CTRL_CLUSTER" -n "$ARGOCD_NS" \
    get appproject,applicationset,application,repository --no-headers 2>/dev/null \
    | awk '{printf "     %-16s %-30s %s\n", $1, $2, $3}' || true

  log ""
  log "⑤ 各集群内的真实资源（验证真的 apply 下去了）"
  local c
  for c in $CLUSTERS; do
    local ns
    ns="platform-$(echo "$c" | cut -d- -f1)"
    log "  ── $c (namespace: $ns)"
    kubectl --context "kind-$c" -n "$ns" get deploy,svc,po -o wide 2>/dev/null \
      | sed 's/^/     /' || true
  done

  log ""
  log "⑥ 渲染结果抽样（Argo CD 实际 apply 的清单）"
  local app
  app="$(argocd app list --server "$ARGOCD_SERVER" -o name 2>/dev/null | grep -v root-bootstrap | head -1 || true)"
  if [[ -n "$app" ]]; then
    argocd app manifests "$app" --server "$ARGOCD_SERVER" 2>/dev/null | head -30 | sed 's/^/     /'
  fi

  log ""
  log "⑦ 同步状态汇总"
  argocd app list --server "$ARGOCD_SERVER" -o json 2>/dev/null \
    | python3 "$BIN_DIR/app_status.py" 2>/dev/null || true
}

# =============================================================================
# 15. 清理
# =============================================================================

step_cleanup() {
  section "STEP 11 · 清理"

  if [[ $DRY_RUN -eq 0 && -f "$WORKDIR/git-http.pid" ]]; then
    kill "$(cat "$WORKDIR/git-http.pid")" 2>/dev/null && ok "已停止 Git HTTP 服务" || true
  fi
  if [[ $DRY_RUN -eq 0 && -f "$WORKDIR/portforward.pid" ]]; then
    kill "$(cat "$WORKDIR/portforward.pid")" 2>/dev/null && ok "已停止端口转发" || true
  fi

  if have kind; then
    local c
    for c in $CTRL_CLUSTER $CLUSTERS; do
      if kind get clusters 2>/dev/null | grep -qx "$c"; then
        run "删除 kind 集群 $c" kind delete cluster --name "$c"
      fi
    done
  fi

  if [[ $KEEP -eq 0 && $DRY_RUN -eq 0 ]]; then
    run "删除工作目录" rm -rf "$WORKDIR"
  else
    log "  保留工作目录: $WORKDIR"
  fi
}

# =============================================================================
# 16. 主流程
# =============================================================================

do_plan() {
  DRY_RUN=1
  section "PLAN · 接下来会执行什么（不会真的执行）"
  step_preflight
  step_create_clusters
  step_install_argocd
  step_prepare_repo
  step_login
  step_register_repo
  step_register_clusters
  step_create_projects
  step_create_root_app
  step_wait_sync
  step_verify
  log ""
  log "以上是 plan 输出。执行 \`./demo.sh apply\` 才会真的动手。"
}

do_apply() {
  step_preflight
  step_create_clusters
  step_install_argocd
  step_prepare_repo
  step_login
  step_register_repo
  step_register_clusters
  step_create_projects
  step_create_root_app
  step_wait_sync
}

main() {
  case "$CMD" in
    plan)  do_plan ;;
    apply) do_apply; step_verify ;;
    verify)
      step_verify
      ;;
    cleanup) step_cleanup ;;
    demo)
      do_plan
      echo ""
      do_apply
      step_verify
      log ""
      log "清理请执行: ./demo.sh cleanup"
      ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
