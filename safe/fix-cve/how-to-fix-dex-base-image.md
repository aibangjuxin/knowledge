# dex Base Image 修复 Runbook —— alpine 3.21 EOL

> 编写日期：2026-11-05
> 关联文档：[how-to-autofix-cve.md](./how-to-autofix-cve.md)（整体方案与验证契约）、[how-to-use-dependabot.md](./how-to-use-dependabot.md)（依赖层自动化）、[cve-cwe.md](./cve-cwe.md)、[how-to-fix-cve-with-base-image-constraints.md](./how-to-fix-cve-with-base-image-constraints.md)（**当换 base 需要走内部准入流程、或想在 Dockerfile 里卸包消 CVE 时看这份**）
>
> **本文定位**：不是通用教程，是**你们这一个具体 case 的完整可执行方案**。
> 目标镜像：`europe-west2-docker.pkg.dev/myproject/containers/dex@sha256:23f4f869a06398b79eceb5266ad6e522a894fc18163e5e37a810666e51aaf2ae`
> 触发问题：`built from os(alpine) version (3.21) which support end of life on 2026-11-01 00:00:00+00`
>
> 标注「**需实测**」的步骤表示：我无法访问你们的 GCP project，必须由你们在项目里跑一次确认。

---

## 0. 结论摘要

| 项 | 结论 |
|---|---|
| **问题性质** | **不是 CVE**，是 **OS 生命周期（EOL）**问题。Alpine 3.21 已于 2026-11-01 停止支持（4 天前），最后补丁 `3.21.9` 之后不再有更新 → **在 3.21 上做任何 `apk upgrade` 都修不掉** |
| **能否自动修** | ✅ **能，而且很简单** —— 这是所有 CVE 类型里最适合自动化的一类（纯机械操作，无 API 破坏风险） |
| **上游是否已修** | ✅ **已修**。dex 上游 master 已用 `alpine:3.24.3`（EOL 2028-06-01），且提供 **`distroless` 变体** |
| **推荐方案** | **先做"跟上游"（升 dex 版本）**，再评估"自建切 distroless"（一劳永逸消除 OS 包） |
| **能否靠 Dependabot 修** | ⚠️ **基本不行** —— `docker` ecosystem 无 security update；且 dex 用 `ARG BASE_IMAGE` 间接写法，Dependabot 解析不到。详见 §7 |
| **工作量估计** | 手工跑通 0.5–1 天；做成自动化 1–2 周（见 [how-to-autofix-cve.md](./how-to-autofix-cve.md) Phase 2） |

---

## 1. 现状盘点

### 1.1 我们知道的事实

```
镜像：europe-west2-docker.pkg.dev/myproject/containers/dex
digest：sha256:23f4f869a06398b79eceb5266ad6e522a894fc18163e5e37a810666e51aaf2ae
位置：europe-west2（→ Artifact Analysis 用 --location=europe）
问题：base OS = alpine 3.21，EOL 2026-11-01
今天：2026-11-05
```

### 1.2 Step 0 —— 确认 finding 来源（**先做这个，别跳**）

这条 finding 的文案不像标准 CVE 格式（没有 CVE ID，没有 package 名），**必须先确定它是谁报出来的**，因为：

- 不同来源的字段结构和"修复语义"不同；
- **如果 Artifact Analysis 复现不出这类 finding，整个"推 GAR → 拿报告 → 验证"的闭环就不成立**，方案要改。

```bash
# A. 在 SCC 里找这条 finding
gcloud scc findings list --project=myproject \
  --filter='state="ACTIVE" AND category="CONTAINER_VULNERABILITY"' \
  --format=json | jq '.[] | select(.resourceName | test("dex")) '

# B. 在 Artifact Analysis 里查这个 digest 的扫描结果
gcloud artifacts docker images describe \
  europe-west2-docker.pkg.dev/myproject/containers/dex@sha256:23f4f869... \
  --show-package-vulnerability --show-sbom-references --show-image-basis

# C. 直接触发一次按需扫描，看报告长什么样
gcloud artifacts docker images scan \
  europe-west2-docker.pkg.dev/myproject/containers/dex@sha256:23f4f869... \
  --remote --location=europe
```

**判定表：**

| Step 0 结果 | 含义 | 下一步 |
|---|---|---|
| SCC / Artifact Analysis 里有对应记录 | ✅ 闭环成立 | 继续 §4 |
| 只有第三方工具有（Trivy/Snyk/BlackDuck 等） | ⚠️ 闭环需改造 | 引入第三方扫描器做验证，或让 Artifact Analysis 开连续扫描 |
| 两边都没有 | ❌ finding 来自别处 | 回到源头确认是哪条 pipeline 报的 |

### 1.3 摸清镜像现状

```bash
IMAGE=europe-west2-docker.pkg.dev/myproject/containers/dex
DIGEST=sha256:23f4f869a06398b79eceb5266ad6e522a894fc18163e5e37a810666e51aaf2ae

# 拉下来看层和 base
docker pull $IMAGE@$DIGEST
docker history --no-trunc $IMAGE@$DIGEST | head -20

# 看本地镜像的 OS 版本
docker run --rm --entrypoint sh $IMAGE@$DIGEST -c 'cat /etc/alpine-release; apk info -vv | head'

# 谁在跑这个镜像（GKE）
kubectl get deploy,sts,ds -A -o json | jq -r '
  .items[] | select(.spec.template.spec.containers[].image | contains("containers/dex"))
  | "\(.kind)/\(.metadata.namespace)/\(.metadata.name)"'

# GAR 仓库里 dex 有哪些 tag / digest
gcloud artifacts docker images list $IMAGE --include-tags
```

> **最后一条命令很关键** —— 如果 GAR 里有 `v2.4x` 这类较新的 tag（上游已用 alpine 3.24 的版本），那修复可能只是"换个 tag 重新部署"，连重建都不用。

---

## 2. 上游 dex 实测（2026-11-05）

这部分是本方案成立的关键依据，全部来自 `github.com/dexidp/dex` master 分支实测。

### 2.1 上游 Dockerfile 的关键结构

```dockerfile
ARG BASE_IMAGE=alpine                                       # ← base 由 build arg 决定

FROM --platform=$BUILDPLATFORM tonistiigi/xx:1.10.0@sha256:40fe... AS xx
FROM --platform=$BUILDPLATFORM golang:1.27.3-alpine3.24@sha256:d200... AS builder

# ... 构建 dex 二进制 ...

FROM alpine:3.24.3@sha256:be26... AS stager
FROM ghcr.io/hairyhenderson/gomplate:v5.3.1@sha256:9c73... AS gomplate
FROM alpine AS user-setup                                    # ← 注意：这是裸 alpine
FROM gcr.io/distroless/static-debian13:nonroot@sha256:25ac... AS distroless

FROM $BASE_IMAGE                                             # ← 最终形态由 BASE_IMAGE 决定
COPY --from=builder /go/bin/dex /usr/local/bin/dex
COPY --from=builder /go/bin/docker-entrypoint /usr/local/bin/docker-entrypoint
# Copy module files for CVE scanning / dependency analysis.
COPY --from=builder /usr/local/src/dex/go.mod /usr/local/src/dex/go.sum /usr/local/src/dex/
USER dex:dex
ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]
CMD ["dex", "serve", "/etc/dex/config.docker.yaml"]
```

### 2.2 六个对本方案有利的发现

| # | 发现 | 对方案的意义 |
|---|---|---|
| **F1** | **上游已用 `alpine:3.24.3`**（EOL 2028-06-01），不再是 3.21 | **方案 A（跟上游）零成本** |
| **F2** | **`ARG BASE_IMAGE` 可以切换 base**，CI 里 `build-args: BASE_IMAGE=${{ matrix.variant }}`，matrix = `alpine` / `distroless` | **方案 C（切 distroless）零成本** |
| **F3** | Dockerfile 里有 `COPY --from=builder .../go.mod .../go.sum`，注释明写 *"For CVE scanning / dependency analysis"* | **Go 依赖也完整暴露给 SCA**，不用额外处理 |
| **F4** | 上游自己跑 Trivy rootfs 扫描（`artifacts.yaml` 里的 `aquasecurity/trivy-action`，SARIF 上传到 Security tab），还有每日 Trivy DB cache workflow | **上游的 CI 做法可以直接抄**（见 §6.3） |
| **F5** | 上游发布 `alpine` 和 `distroless` 两个 variant，tag 规则：`<version>` / `latest` = alpine；`<version>-distroless` / `latest-distroless` = distroless | 拉上游镜像时**可以直接选 distroless 变体** |
| **F6** | 上游用 cosign + GitHub OIDC 签名，并做 build provenance attestation | 可以在你们的流程里**校验上游镜像签名** |

### 2.3 上游版本参考

- 最新 release tag（实测）：**`v2.46.1`**
- 发布平台：`ghcr.io/dexidp/dex` 和 `docker.io/dexidp/dex`
- 支持架构：`linux/amd64`、`linux/arm/v7`、`linux/arm64`、`linux/ppc64le`、`linux/s390x`
- 上游构建用的 Go：**1.27.3**（builder image 是 `golang:1.27.3-alpine3.24`）

> ⚠️ **需实测**：你们镜像里的 dex 版本是多少？用 `docker run --rm <image> dex version` 或看 `/etc/dex/config.docker.yaml` 旁的镜像 label 确认。
> 如果你们停在很老的版本（比如 v2.3x），**升版本本身可能带来 breaking change**（dex 的 config 结构、connector 配置在 2.x 期间有变更）→ 那时"只换 base 不升版本"（方案 B）更稳。

### 2.4 Alpine 生命周期对照表（实测，2026-11-05）

| Alpine | EOL 日期 | 最新 patch | 状态 |
|---|---|---|---|
| 3.20 | 2026-04-01 | 3.20.10 | 已 EOL |
| **3.21** | **2026-11-01** | 3.21.9 | **已 EOL（你们的镜像）** |
| 3.22 | 2027-05-01 | 3.22.7 | 维护中 |
| 3.23 | 2027-11-01 | 3.23.7 | 维护中 |
| **3.24** | **2028-06-01** | 3.24.3 | **推荐（上游在用）** |

---

## 3. 三个候选方案

| | **A. 跟上游** | **B. 自建 + 升 base** | **C. 自建 + 切 distroless** |
|---|---|---|---|
| **动作** | 升 dex 版本到用 alpine 3.24 的 release，拉上游镜像推自己 GAR | 用现有 dex 源码 + 你们自己的 Dockerfile，`FROM alpine:3.24.3` | 同 B，但 `BASE_IMAGE=distroless` |
| **OS 包残留** | 少（alpine 3.24 仍有 apk 包，但都比 3.21 新） | 少 | **几乎没有**（distroless 只有 static-debian13 基础层） |
| **EOL 复发** | 3.24 → 2028-06 | 同 A | **几乎免疫**（Debian 系，生命周期长得多） |
| **风险** | dex 版本升级的 breaking change | 最低（只换 OS） | 中（无 shell、用户 uid 65532、路径/权限差异） |
| **工作量** | 最低（可能只是换 tag 重新部署） | 低 | 低 |
| **需要自建镜像？** | 否（可直接 pull 上游） | 是 | 是 |
| **推荐度** | ⭐⭐⭐ **先做这个** | ⭐⭐ | ⭐⭐ 值得评估 |

### 3.1 为什么"切 distroless"值得认真评估

dex 是 OIDC provider，跑在 GKE 里，**大概率不需要在容器里开 shell 调试**。切 distroless 的收益：

- **Alpine EOL 问题从根上消失** —— 以后不用每年跟 EOL 日期赛跑；
- **攻击面大幅缩小** —— distroless 只有必要的静态二进制和 CA 证书，没有 shell、没有 apk、没有包管理器；
- **镜像体积小一个量级**；
- **和你们"Binary Authorization / 最小权限"的整体方向一致**。

**切 distroless 的坑（必须逐条核对）**：

| 坑 | 说明 | 怎么查 |
|---|---|---|
| 没有 `/bin/sh` | 任何 `kubectl exec ... sh` 调试都会失败 | 确认运维流程不依赖 exec |
| 用户是 `nonroot` (uid 65532) | 挂载卷、emptyDir 的写权限 | 检查 `securityContext` 和 PVC 权限 |
| dex 的 Dockerfile 覆盖了 `/etc/passwd` | 上游用 `COPY --from=user-setup` 把 dex 用户(uid 1001)写进去 | 你们的 manifest 里 `runAsUser` 要和它对齐 |
| `/var/dex` 和 `/etc/dex` 的写权限 | dex 需要写存储后端（如果用 sqlite） | 检查 storage 配置 |
| ConfigMap/Secret 挂载路径 | distroless 没有默认 shell 展开变量 | 用 `subPath` 显式挂 |

> 💡 **决策建议**：先做 A（当天能上，风险最低），把"切 distroless"作为独立的架构改进项排期 —— 因为它涉及运行时行为变化，不该和"修一个 EOL"混在同一个 PR 里（**一次 PR 只改一类**，见 [how-to-autofix-cve.md](./how-to-autofix-cve.md) §9.2）。

---

## 4. 执行步骤（方案 A：跟上游）

> 假设你们已经完成了 §1.2（确认 finding 来源）和 §1.3（摸清现状）。

### Phase 0 —— 决策准备（1 小时）

- [ ] 确认 finding 来源（§1.2）
- [ ] 确认当前 dex 版本、当前 tag、谁在跑它（§1.3）
- [ ] 查 GAR 里有没有更新的 dex tag（可能连重建都不用）
- [ ] 确认 **dex 版本升级有没有 breaking change**：对比 [dex release notes](https://github.com/dexidp/dex/releases) 的目标版本
- [ ] 决定：走 A 还是 B

### Phase 1 —— 构建 / 获取候选镜像（半天）

**如果走 A（用上游镜像）：**

```bash
# 上游镜像（alpine 变体）
docker pull ghcr.io/dexidp/dex:v2.46.1
# 或 distroless 变体
docker pull ghcr.io/dexidp/dex:v2.46.1-distroless

# 推到你们自己的 GAR（保留自己的 tag 体系）
docker tag ghcr.io/dexidp/dex:v2.46.1 \
  europe-west2-docker.pkg.dev/myproject/containers/dex:v2.46.1
docker push europe-west2-docker.pkg.dev/myproject/containers/dex:v2.46.1
```

> ⚠️ **务必校验上游签名**（上游用 cosign + GitHub OIDC 签名，见 F6）：
> ```bash
> cosign verify ghcr.io/dexidp/dex:v2.46.1 \
>   --certificate-identity-regexp "https://github.com/dexidp/dex/.*" \
>   --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
> ```

**如果走 B/C（自建）：**

```bash
git clone https://github.com/dexidp/dex.git && cd dex
git checkout v2.46.1     # 或你们当前版本的下一个

# 方案 B：升 base
docker buildx build --platform linux/amd64 \
  --build-arg BASE_IMAGE=alpine \
  -t europe-west2-docker.pkg.dev/myproject/containers/dex:v2.46.1-alpine324 \
  --push .

# 方案 C：切 distroless
docker buildx build --platform linux/amd64 \
  --build-arg BASE_IMAGE=distroless \
  -t europe-west2-docker.pkg.dev/myproject/containers/dex:v2.46.1-distroless \
  --push .
```

> ⚠️ **需实测**：自建时 `BASE_IMAGE` 传的是**名字**（`alpine` / `distroless`），不是具体 tag —— 因为 Dockerfile 里 `FROM $BASE_IMAGE`。要指定 alpine 的具体版本，得改上游 Dockerfile 里的 `FROM alpine:3.24.3@sha256:...` 那几行。
> **这也正是 Dependabot 抓不到这个依赖的原因**（见 §7）。

### Phase 2 —— 验证（关键，走验证契约）

按 [how-to-autofix-cve.md](./how-to-autofix-cve.md) 第 4 章的契约执行。

```bash
cd /Users/lex/git/knowledge/safe/fix-cve   # 或你放脚本的地方

OLD=europe-west2-docker.pkg.dev/myproject/containers/dex@sha256:23f4f869a06398b79eceb5266ad6e522a894fc18163e5e37a810666e51aaf2ae
NEW=europe-west2-docker.pkg.dev/myproject/containers/dex:v2.46.1
```

**Step 2.1 —— 同一批 DB、同一时段扫两次**

```bash
# baseline（旧镜像）
gcloud artifacts docker images scan "$OLD" --remote --location=europe --async

# candidate（新镜像）
gcloud artifacts docker images scan "$NEW" --remote --location=europe --async

# 轮询两个操作直到都完成
gcloud artifacts docker images get-operation <OP_BASELINE>
gcloud artifacts docker images get-operation <OP_CANDIDATE>
```

**Step 2.2 —— 取漏洞列表**

```bash
gcloud artifacts docker images list-vulnerabilities \
  projects/myproject/locations/europe/scans/<SCAN_ID> --format=json > findings.json
```

**Step 2.3 —— 差分判定（三条必须全过）**

| # | 判定 | 怎么算 |
|---|---|---|
| **D1** | 目标命中消失 | candidate 里不再有 `os(alpine) 3.21 EOL` 那条；且 alpine 版本 ≠ 3.21 |
| **D2** | 无新增 | `candidate.findings ⊆ baseline.findings`（同一 DB 前提下） |
| **D3** | digest 变了 | `candidate digest ≠ 23f4f869...` |

**D2 的实现要点**：因为两次扫描之间 DB 可能更新，**如果 candidate 出现了 baseline 没有的 finding，要重跑一次 baseline 扫描再比**，而不是直接判失败。

**Step 2.4 —— 冒烟（D4）**

dex 是 OIDC provider，冒烟至少要覆盖：

```bash
# 1) 容器能启动且不 panic
kubectl -n <ns> apply -f <candidate 的 deployment 副本>   # 或本地 docker run
kubectl logs -f deploy/<name> -n <ns> | head -50

# 2) 健康检查 / OIDC discovery 端点
curl -fsS http://<host>/.well-known/openid-configuration | jq .

# 3) 关键 endpoint
curl -fsS http://<host>/dex/keys | jq .

# 4) 如果连了真实 IdP（Google/GitHub），做一次真实的 authorize 流程
# 5) storage 后端读写正常（如果用 sqlite）
```

**Step 2.5 —— distroless 额外检查（走方案 C 才需要）**

```bash
# 确认没有 shell（预期失败）
kubectl exec deploy/<name> -n <ns> -- /bin/sh -c 'id' ; echo "exit=$?"

# 确认运行用户
kubectl exec deploy/<name> -n <ns> -- id   # distroless 有 id 吗？static-debian13 有 /usr/bin/id

# 确认挂载卷可写
kubectl exec deploy/<name> -n <ns> -- /busybox/touch /var/dex/test 2>/dev/null || \
  echo "⚠️ 无法直接验证卷写权限，改用应用级验证"
```

### Phase 3 —— 部署（灰度）

**Step 3.1 —— 换 digest**

```bash
# 拿到新 digest
NEW_DIGEST=$(gcloud artifacts docker images describe \
  europe-west2-docker.pkg.dev/myproject/containers/dex:v2.46.1 \
  --format='value(image_summary.digest)')
echo $NEW_DIGEST
```

> ⚠️ **这一整步是最容易漏的**。改了镜像但没改 K8s manifest → 集群还在跑旧的有洞镜像 → SCC finding 假闭环。
> **建议用 kustomize / Helm 管理 image digest，不要手改 YAML。**

**Step 3.2 —— 灰度**

```bash
# 单副本灰度
kubectl -n <ns> set image deploy/<name> <container>=<IMAGE>@$NEW_DIGEST
kubectl -n <ns> rollout status deploy/<name> --timeout=5m
kubectl -n <ns> get pods -l app=<name> -o wide

# 观察
kubectl -n <ns> logs deploy/<name> --tail=100
```

**Step 3.3 —— 全量 + 确认 finding 关闭**

```bash
# 确认 SCC finding 状态变化
gcloud scc findings list --project=myproject \
  --filter='state="ACTIVE" AND category="CONTAINER_VULNERABILITY"' \
  --format=json | jq '.[] | select(.resourceName | test("dex")) | {name, state}'

# 确认新 digest 的扫描记录存在且干净
gcloud artifacts docker images describe "$IMAGE@$NEW_DIGEST" --show-package-vulnerability
```

### Phase 4 —— 收尾

- [ ] SCC finding 关闭（**这是客观的闭环证据**）
- [ ] 旧 digest 的 tag 清理（`gcloud artifacts docker images delete`）
- [ ] 记录到台账：旧 digest → 新 digest、变更原因、验证证据链接
- [ ] 旧镜像 digest 保留一个观察期（先不删 tag，确认没问题再删）

---

## 5. 回滚方案

```bash
# 回滚到旧 digest（前提：旧 digest 的镜像还没被清理）
kubectl -n <ns> set image deploy/<name> <container>=<IMAGE>@sha256:23f4f869...
kubectl -n <ns> rollout status deploy/<name> --timeout=5m
```

**回滚触发条件：**
- 冒烟测试失败；
- OIDC 登录流程异常；
- distroless 下出现权限/路径问题；
- 灰度期间错误率上升。

> ⚠️ **回滚的前提是旧 digest 还在 GAR 里** → 所以 Phase 4 里"旧 digest 保留观察期"不是可选项。

---

## 6. 防复发

### 6.1 让它下次自动被发现

| 手段 | 配置 | 覆盖 |
|---|---|---|
| **Artifact Analysis 连续扫描** | GAR 仓库设置里开（push 时自动扫） | 任何新推的镜像 |
| **定期 EOL 巡检** | 每月跑一次：扫所有 GAR 镜像的 base OS，比对 Alpine/Debian EOL 表 | **比扫描器更早**（EOL 是日历驱动的） |
| **SCC 台账** | 按镜像维度排优先级 | 影响面排序 |
| **Binary Authorization** | continuous validation | 阻止有洞镜像进生产 |

### 6.2 让它下次自动被修

| 手段 | 可行性 |
|---|---|
| **Dependabot `docker` ecosystem** | ⚠️ **不可行** —— 见 §7 |
| **Renovate** | ✅ 可行（支持 `ARG`/`FROM` 解析，比 Dependabot 强） |
| **自建 `gcp-cve-fix`** | ✅ 可行 —— 见 [how-to-autofix-cve.md](./how-to-autofix-cve.md) Phase 2 |
| **人工巡检 + 提醒** | 兜底 |

### 6.3 抄上游的 CI 做法（推荐）

dex 上游的 `artifacts.yaml` 已经示范了一套完整的做法（见 F4），**值得直接抄**：

```yaml
# 简化版
- name: Prepare image fs for scanning
  run: |
    docker export $(docker create --rm $IMAGE) -o docker-image.tar
    mkdir -p docker-image && tar -xf docker-image.tar -C docker-image

- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@0.36.0
  with:
    input: docker-image
    format: sarif
    output: trivy-results.sarif
    scan-type: "rootfs"
    scan-ref: "."

- name: Upload Trivy scan results to GitHub Security tab
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: trivy-results.sarif
```

**但要清楚它的定位**：Trivy 是**检测**层，**不能替代** Artifact Analysis 的权威结论。
**建议双轨：Trivy 在 CI 里跑得快、能在 PR 阶段拦住；Artifact Analysis 在 GAR 上跑、是台账和门禁的权威。**

---

## 7. 为什么 Dependabot 修不了这个 case（重要）

即使你们配了 Dependabot，这个 case 也**大概率不会被自动修**。两个原因：

### 原因 1：`docker` ecosystem 没有 security updates

官方矩阵实测：**`docker` 的 Security updates 一列是 ❌**。
Dependabot 的 docker ecosystem 只做 **version updates**（升 base image tag），不会因为 base image EOL 而开 PR。

### 原因 2：dex 的 Dockerfile 用 `ARG BASE_IMAGE` 间接引用

```dockerfile
ARG BASE_IMAGE=alpine
...
FROM $BASE_IMAGE
```

Dependabot 的 docker 解析器**按 `FROM` 行的字面 tag 做 SemVer 解析**，它解析不了 build arg 的值 → **它根本看不到"alpine"这个依赖**。

> 即使你们把 `FROM alpine:3.21` 写死，Dependabot 也只会开一个"升到 alpine:3.22"的 version update PR —— 而 **3.22 在 2027-05-01 也会 EOL**。它治不了"生命周期"问题，只治"版本落后"问题。

### 结论

| | 能修这个 case 吗 |
|---|---|
| Dependabot | ❌ |
| Renovate | ⚠️ 能检测到 `FROM` 更新，但**同样管不了 EOL 日历** → EOL 巡检还是要自己做 |
| **自建 `gcp-cve-fix` + 定期 EOL 巡检** | ✅ |

→ 这正是为什么 [how-to-autofix-cve.md](./how-to-autofix-cve.md) 把 **T1（OS 生命周期）** 单独列为一类的原因：**它需要的是"日历驱动的守护"，不是"漏洞驱动的响应"。**

---

## 8. 需要你们确认的事项

| # | 问题 | 影响 |
|---|---|---|
| 1 | **那条 EOL finding 是哪个工具报的？** | 决定验证闭环成不成立（§1.2） |
| 2 | **你们镜像里的 dex 版本是多少？** | 决定升版本有没有 breaking change（§2.3） |
| 3 | **这个 dex 镜像是你们自己 build 的，还是 pull 上游推到自己 GAR 的？** | 决定走 A 还是 B/C |
| 4 | **dex 有没有接真实的 IdP（Google/GitHub）？** | 决定冒烟测试怎么做（§2.4） |
| 5 | **运维流程里有没有"进容器 exec 排查"的习惯？** | 决定方案 C（distroless）可行性 |
| 6 | **GAR 仓库的连续扫描 / SBOM 生成开了吗？** | 决定 §6.1 的防复发基础 |

---

## 9. 附录

### 9.1 完整命令清单

```bash
# ---------- 镜像信息 ----------
gcloud artifacts docker images list <IMAGE> --include-tags
gcloud artifacts docker images describe <IMAGE@digest> \
  --show-package-vulnerability --show-sbom-references --show-image-basis --show-provenance

# ---------- 扫描 ----------
gcloud artifacts docker images scan <IMAGE> --remote --location=europe [--async]
gcloud artifacts docker images get-operation <OPERATION>
gcloud artifacts docker images list-vulnerabilities \
  projects/<p>/locations/europe/scans/<SCAN_ID>

# ---------- 构建与推送 ----------
docker buildx build --platform linux/amd64 \
  --build-arg BASE_IMAGE=distroless \
  -t <IMAGE>:v2.46.1-distroless --push .
gcloud artifacts docker images delete <IMAGE@digest>

# ---------- K8s ----------
kubectl get deploy,sts,ds -A -o json | jq -r '...'
kubectl -n <ns> set image deploy/<name> <c>=<IMAGE>@<digest>
kubectl -n <ns> rollout status deploy/<name> --timeout=5m
kubectl -n <ns> logs deploy/<name> --tail=100

# ---------- 安全台账 ----------
gcloud scc findings list --project=myproject \
  --filter='state="ACTIVE" AND category="CONTAINER_VULNERABILITY"'

# ---------- 门禁 ----------
gcloud container binauthz attestors list
gcloud container binauthz policy get <policy> --format=json

# ---------- 上游签名校验 ----------
cosign verify ghcr.io/dexidp/dex:v2.46.1 \
  --certificate-identity-regexp "https://github.com/dexidp/dex/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

### 9.2 参考

| 主题 | 链接 |
|---|---|
| dex 源码 / Dockerfile | <https://github.com/dexidp/dex/blob/master/Dockerfile> |
| dex 上游构建 workflow（SBOM/cosign/Trivy） | <https://github.com/dexidp/dex/blob/master/.github/workflows/artifacts.yaml> |
| dex release notes（查 breaking change） | <https://github.com/dexidp/dex/releases> |
| Alpine 生命周期 | <https://endoflife.date/alpine> |
| Debian 生命周期（distroless 用） | <https://endoflife.date/debian> |
| Artifact Analysis | <https://cloud.google.com/artifact-registry/docs/artifact-analysis> |
| Binary Authorization | <https://cloud.google.com/binary-authorization/docs/overview> |
| Trivy | <https://github.com/aquasecurity/trivy> |
| cosign | <https://github.com/sigstore/cosign> |
