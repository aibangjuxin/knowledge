# pURL 与 Artifact 概念细化

本文档细化两个在软件供应链安全、CI/CD、依赖管理场景中**高频出现、但常被混淆**的概念:

- **pURL** (Package URL) — 用于**唯一标识一个软件包**的标准化字符串
- **Artifact** (工件 / 构建产物) — 软件开发与 CI/CD 流程中**可交付的、有实际内容的产物**

---

## 一、pURL (Package URL)

### 1. 概念定义

pURL 全称 **Package URL**,由 [packageurl.org](https://packageurl.org/) 维护,是 [OWASP CycloneDX](https://cyclonedx.org/specification/overview/) 漏洞与 SBOM (Software Bill of Materials) 标准引用的**唯一包标识符规范**。

它的核心使命:用**一个字符串**把"我是哪个生态、哪个包、哪个版本、从哪儿来"讲清楚 — 并且**任何工具都能用同一份代码把字符串还原成结构化对象**。

pURL 本身**不是**:
- 不是一个下载 URL (虽然长得像,但你拿去 `curl` 经常 404)
- 不是一个漏洞编号、不是 PURL
- 不是一个指纹、不是哈希
- 不是一个注册中心 API 调用

它**就是**一种**结构化的命名约定**,像条形码一样唯一指代一个软件包。

### 2. 语法结构

pURL 的通用语法如下 (来自 [pURL 规范](https://github.com/package-url/purl-spec)):

```
scheme:type/namespace/name@version?qualifiers#subpath
```

各部分含义:

| 段 | 必填 | 含义 | 示例 |
|----|------|------|------|
| `scheme` | 是 | 固定为 `pkg:` 前缀 | `pkg:` |
| `type` | 是 | 包所属生态/包管理器类型 | `npm`、`maven`、`pypi`、`docker`、`oci`、`github`、`generic` 等 |
| `namespace` | 否 | 命名空间,通常是组织/用户/组 | `@angular`、`org.springframework` |
| `name` | 是 | 包名 | `core`、`spring-core` |
| `version` | 否 | 版本号 | `1.2.3`、`20.0.0-RELEASE` |
| `qualifiers` | 否 | 附加键值对,进一步定位 | `arch=x86_64`、`os=linux` |
| `subpath` | 否 | 包内部子路径 | `lib/utils.js` |

**最小可解析形态**:`pkg:<type>/<name>@<version>`

### 3. 跨生态示例

| 生态 | pURL |
|------|------|
| npm (JavaScript) | `pkg:npm/lodash@4.17.21` |
| npm (scoped) | `pkg:npm/%40angular/core@15.0.0` (`@` 编码为 `%40`) |
| PyPI (Python) | `pkg:pypi/requests@2.31.0` |
| Maven (Java) | `pkg:maven/org.springframework/spring-core@5.3.27` |
| Maven (无 group) | `pkg:maven/commons-lang/commons-lang@2.6` |
| NuGet (.NET) | `pkg:nuget/Newtonsoft.Json@13.0.3` |
| Go module | `pkg:golang/github.com%2Fgolang%2Fgrpc@v1.55.0` (`/` 编码为 `%2F`) |
| Docker / OCI | `pkg:docker/library/nginx@1.25.2` |
| OCI 通用 | `pkg:oci/library/alpine@3.18.3?arch=amd64&os=linux` |
| RubyGems | `pkg:gem/rails@7.0.4` |
| Cargo (Rust) | `pkg:cargo/serde@1.0.183` |
| Generic (任意下载) | `pkg:generic/openssl@1.1.1k?download_url=https://openssl.org/source/openssl-1.1.1k.tar.gz` |
| GitHub 仓库 | `pkg:github/package-url/purl-spec@244fd47e07d1004f0aed9c403bb38c4e074e2b25` |

> 编码规则:`/ @ ? # = &` 等保留字符在非位置段必须 URL-encode。完整规则见 [pURL-spec §3 Encoding](https://github.com/package-url/purl-spec/blob/master/PURL-SPECIFICATION.rst)。

### 4. pURL 的"值"在哪里 — 它解决什么问题

1. **跨生态统一指代**:Maven 用 GAV (`groupId:artifactId:version`)、npm 用 `name@version`、Go 用 module path+tag。pURL 把这堆方言归一。
2. **SBOM 的骨干字段**:CycloneDX 和 SPDX 两个主流 SBOM 规范的 `<component>` / `<Package>` 节点都直接以 pURL 作为**主键**。CISA 的 VEX、最低安全要求都在 push SBOM,SBOM 没 pURL 就不完整。
3. **漏洞匹配 (VEX)**:GHSA / CVE 数据库里的 advisory 通常会附 pURL;扫描器发现 `lodash@4.17.20` 时,精确匹配 GHSA-p6mc-m468-83gw 的受影响 pURL 列表,得出"命中"结论。
4. **依赖图拼接**:不同工具 (npm、maven、pip) 出的依赖图可以通过 pURL 串起来,组成跨语言的全局依赖图。
5. **可读 + 可解析**:人看得懂、机器 parse 得了,且**正反一致** — `packageurl-python` / `packageurl-go` / `packageurl-java` 等多语言库能把它解析回结构化对象。

### 5. pURL 与相邻概念的边界

| 概念 | 区别 |
|------|------|
| **URL** (资源定位) | pURL 长得像 URL,但**默认不可直接 GET**,它只命名,不定位 (除非带 `download_url` 之类的 qualifier) |
| **URN** | URN 是更通用的"唯一名",pURL 是 URN 思想在"软件包"这个领域的具体落地 |
| **GAV / Coordinates** | 是各生态私有的坐标语言;pURL 是它们的**超集 + 中间表示** |
| **SWID / CPE** | CPE 是 NVD 漏洞库用的"产品标识符" (例如 `cpe:2.3:a:apache:log4j:2.14.1:*:*:*:*:*:*:*`),粒度更粗;pURL 是包粒度。两者**互补**,CPE 在 OS/平台层、pURL 在包层 |
| **Hash (SHA-256)** | 哈希能识别"这一坨字节",但**不携带版本/生态/来源**信息;pURL 反过来 |

### 6. 实战代码片段 (Python)

使用官方库 `packageurl-python`:

```python
from packageurl import PackageURL

# 解析
p = PackageURL.from_string("pkg:pypi/requests@2.31.0?extra=security")
print(p.type)         # pypi
print(p.name)         # requests
print(p.version)      # 2.31.0
print(p.qualifiers)   # {'extra': 'security'}

# 反向构造
p2 = PackageURL(
    type="maven",
    namespace="org.springframework",
    name="spring-core",
    version="5.3.27",
)
print(p2.to_string())
# pkg:maven/org.springframework/spring-core@5.3.27
```

CLI (在 npm/PEP 生态很常见):

```bash
pip install packageurl
packageurl parse "pkg:maven/org.springframework/spring-core@5.3.27"
```

### 7. 常见误用

- ❌ 把 pURL 写进 `location` 字段当成下载链接用
- ❌ 省略 namespace 后再让消费者去猜 (例:把 `spring-core` 写成 `pkg:maven/spring-core@5.3.27`,失去 group 之后 Maven 内部仍能识别,但**跨工具匹配会失败**)
- ❌ 忘记对 `/` `@` `%` 进行编码,导致 `packageurl.from_string` 抛错
- ❌ 把 build hash 写进 `name`:`pkg:docker/app@sha256_abc123...` 应放进 qualifiers `digest=sha256:abc...`,因为 hash 跟版本是不同语义
- ❌ 把 `version` 写成 git commit sha 整段:`pkg:github/...@244fd47e07d1004f0aed9c403bb38c4e074e2b25` 是合法的(GitHub type 例外),但 pURL 规范**优先鼓励**用语义化版本

### 8. 速查 — 各生态 type 表

| Type | 生态 | Namespace 含义 |
|------|------|----------------|
| `npm` | Node.js | scope (`@foo` → `foo`) |
| `pypi` | Python | 通常空,有些包使用 |
| `maven` | Java/JVM | `groupId` |
| `nuget` | .NET | 通常空 |
| `golang` | Go | 模块路径 (`github.com/x/y`) |
| `gem` | Ruby | 通常空 |
| `cargo` | Rust | 通常空 |
| `composer` | PHP | `vendor` |
| `cocoapods` | iOS/macOS | 通常空 |
| `oci` / `docker` | 容器镜像 | 仓库路径 (`library`) |
| `deb` | Debian/Ubuntu | 包命名空间 (vendor) |
| `rpm` | RHEL/Fedora | vendor |
| `generic` | 任意 | 自由 |
| `github` / `gitlab` / `bitbucket` | 源码仓 | org/owner |

完整列表见 [pURL-spec 附录](https://github.com/package-url/purl-spec/blob/master/PURL-SPECIFICATION.rst#appendix-a-purl-types)。

---

## 二、Artifact (工件 / 构建产物)

### 1. 概念定义

**Artifact** 在 IT (尤其在 CI/CD、DevOps、构建系统语境中) 指的是:

> 在**开发、编译、构建、测试或发布**过程中产生的、有**实际内容**、可被**消费、传输、存储、审计**的**可交付产物**。

Artifact 的**关键特征**:

1. **有内容** — 不是抽象占位符,是个真东西 (文件、压缩包、镜像、文档等)
2. **可识别** — 通常配**唯一 ID / hash / 名称** (例如 `myapp-1.2.3.tar.gz` + sha256)
3. **可消费** — 下游步骤 (部署、扫描、签名、发布) 能直接拿它干别的事
4. **可追溯** — 能从它反推"哪次 commit 出的、谁出的、跑过哪些测试"

### 2. Artifact 的常见形态

| 形态 | 示例 | 典型场景 |
|------|------|----------|
| **压缩包** | `app-1.0.tar.gz`、`release.zip` | 源代码发布、版本发布 |
| **二进制可执行** | `app.exe`、`myapp.bin` | C/C++/Go/Rust 编译产物 |
| **容器镜像** | `gcr.io/proj/app:v1.2.3` (layer tar 集合) | 容器化部署 |
| **JAR / WAR / EAR** | `spring-core-5.3.27.jar` | JVM 生态构建产物 |
| **Wheel / sdist** | `requests-2.31.0-py3-none-any.whl`、`requests-2.31.0.tar.gz` | Python 打包 |
| **npm tarball** | `lodash-4.17.21.tgz` | Node.js 打包 |
| **Helm chart** | `mychart-1.0.0.tgz` | K8s 应用打包 |
| **文档产物** | `api-docs-v3.html`、`CHANGELOG.md` | 自动生成、发布 |
| **签名 / SBOM** | `app-1.0.tar.gz.sig`、`app-1.0.spdx.json` | 供应链安全、审计 |
| **测试报告** | `junit-report.xml`、`coverage.html` | CI 质量门禁 |
| **基础设施产物** | Terraform plan、Ansible role tarball、CloudFormation template | IaC 流水线 |
| **模型权重** | `model.safetensors`、`pytorch_model.bin` | ML 训练产物 |
| **包仓库元数据** | `Packages` (apt)、`POM` (maven)、`index.json` | 注册中心索引 |

### 3. Artifact 在 CI/CD 流水线中的位置

以一个典型流水线为例:

```
1. 开发者 push commit
       │
       ▼
2. CI 拉取代码 + 依赖
       │
       ▼
3. 构建 (build/test/package)
       │
       ▼
4. 【产出 Artifact】──→ 存到 Artifactory / Harbor / GCS / S3 / npm registry
       │
       ▼
5. 扫描 (SAST / SCA / DAST / 容器扫描) ── 读 artifact
       │
       ▼
6. 签名 (cosign / sigstore / GPG) ── 写新 artifact
       │
       ▼
7. 部署到 staging / production ── 拉 artifact
       │
       ▼
8. 发布 (tagged release) ── 标 artifact 为"正式"
```

**Artifact 是流水线的"交接物"** — 它的存在让"构建"和"部署"两步可以**解耦**、跨机器/跨团队/跨时间窗交接。

### 4. Artifact 的关键属性

| 属性 | 含义 | 典型实现 |
|------|------|----------|
| **名称 + 版本** | 标识 + 语义 | `app-1.2.3.tar.gz` |
| **内容哈希** | 防篡改、可寻址 | SHA-256 |
| **签名** | 来源可信 | cosign (Sigstore)、GPG、PGP |
| **元数据** | 溯源 (provenance) | SLSA provenance、in-toto attestation |
| **SBOM** | 物料清单 (含 pURL 列表) | CycloneDX、SPDX |
| **VEX** | 已知漏洞声明 | CycloneDX VEX、OpenVEX |
| **签名时间戳** | 何时被签 | RFC 3161 TSA |
| **存储路径 / 仓库** | 在哪取 | `harbor.acme.com/proj/app:v1.2.3` |

**这些属性的集合 = "可信 Artifact"**。具体规范参见 [SLSA (Supply-chain Levels for Software Artifacts)](https://slsa.dev/) 框架,从 L0 到 L3 逐步要求构建来源可验证。

### 5. Artifact 的存储系统

不同生态有不同 registry / repository:

| 类别 | 工具 | 存什么 |
|------|------|--------|
| 通用制品库 | JFrog Artifactory、SonaType Nexus、Harbor | 任意格式 |
| 容器镜像 | Harbor、Docker Hub、ECR、GCR、ACR | OCI image + helm chart |
| 语言包注册中心 | npmjs、PyPI、Maven Central、crates.io、RubyGems | 各生态包 |
| 对象存储 + 自定义元数据 | GCS、S3、Azure Blob + DB 索引 | 大型/自定义 |
| Sigstore / cosign | 公共签名/Rekor | 签名 + 透明日志 |
| 内网 | 自建 Nexus、minio、Harbor | 离线/内网部署 |

### 6. Artifact 的生命周期

```
[产生 build] → [打标签 tag] → [存进仓库 store] → [扫描 scan]
                                                       │
                                                       ▼
[退役 retire] ← [归档 archive] ← [回滚 rollback] ← [部署 deploy]
```

- **回滚**:找老版本 artifact 重新部署 (而不是 git checkout 老 commit 再构建一次,避免二进制漂移)
- **退役**:在 registry 上 mark 这个 artifact "deprecated",`npm deprecate` / Harbor 标签管理
- **归档**:进入冷存储,满足合规追溯要求

### 7. Artifact 的"反模式"

| 反模式 | 后果 |
|--------|------|
| artifact **不进仓库、直接 ssh 拷到生产机** | 不可追溯、不可回滚、不可审计 |
| artifact **不签名直接拉** | 供应链中间人攻击 (Supply Chain Attack) 无人发现 |
| artifact **覆盖式发布 (覆写同名 tag)** | 一旦发现问题,老版本二进制**已无法取回** |
| artifact **没版本号,用 commit sha 命名** | 可定位,但人脑不可读、不符合 semver 工具链 |
| artifact **包含 secret / 凭据** | 一次推送,**所有下载者**都拿到明文凭据 — 灾难 |
| artifact **不存 hash** | 无法验证"我下载的是不是当初那个" |
| artifact **太大不打压缩** | 拉一次网费一半预算 (尤其 image 多层) |

### 8. Artifact vs Package vs Build

| 术语 | 侧重点 | 关系 |
|------|--------|------|
| **Build** | 行为 (动词) | "一次构建"产生 0 到 N 个 artifact |
| **Package** | 行为 + 生态载体 | "打个 npm 包",产物也是一个 artifact |
| **Artifact** | 产物本身 (名词) | 包含 package 但不限于 (测试报告、SBOM、签名也是) |

简化理解:**"Build 出 Package,Package 是 Artifact 的一种"**。

---

## 三、pURL 与 Artifact 的关系

这两者**不并列**,而是**互补**:

- **Artifact** 是"那一坨东西" (the thing)
- **pURL** 是"那张名牌" (the name for the thing)

举例:今天发版的 `app:v1.2.3` Docker 镜像是一个 **Artifact**。这个 artifact 在 SBOM / 漏洞扫描 / 依赖图里**被引用**时,通常用一条 **pURL**:

```
pkg:oci/proj/app@1.2.3?arch=amd64&os=linux
```

对照表:

| 维度 | Artifact | pURL |
|------|----------|------|
| 本质 | 一坨字节 (file / image / package) | 一个字符串 |
| 角色 | 物质 | 命名 |
| 唯一性来源 | 内容哈希 (sha256) | 字符串本身 |
| 是否有"内容" | 有 | 没有 (只是个指针) |
| 是否可直接消费 | 可以 (拉下来跑) | 不可以 (要解析 → 找到对应 artifact) |
| 谁定义 | 生态 (OCI / JAR / wheel) | packageurl.org 规范 |
| 主用场景 | 部署、发布、存储 | SBOM、漏洞、依赖图、审计 |

**一个 artifact 可以有多个 pURL** (例如 Maven 的 `org.springframework:spring-core:5.3.27` 既可以用 `pkg:maven/...` 也可以按内部规范给出 `pkg:generic/...`);反过来**一个 pURL 可以指向多个 artifact** (不同镜像源、备份站 — 实际同一版本同一包)。

---

## 四、典型应用场景串联

看一次完整的供应链追踪,把两个概念串起来:

```
1. CI 构建 my-app ──→ 产出 Artifact: container image `my-app:v1.2.3`
                                    │
                                    ▼
2. 镜像推到 Harbor ──→ 触发 SCA 扫描 ──→ 解析 image 内 OS 包
                                    │
                                    ▼
3. SCA 工具发现 openssl-1.1.1k-9.amzn2.x86_64 ──→ 构造 pURL:
       pkg:rpm/openssl@1.1.1k?arch=x86_64&distro=amazon-linux-2
                                    │
                                    ▼
4. 拿这个 pURL 去 GHSA 数据库查 ──→ 命中 CVE-2023-0286 (HIGH)
                                    │
                                    ▼
5. 在 VEX 中声明:"my-app:v1.2.3 受 CVE-2023-0286 影响,
   但我们通过 <mitigation> 缓解,无需升级"
       VEX 引用 pURL + artifact 路径
                                    │
                                    ▼
6. 运维根据 VEX 决定:
   - 接受风险 (业务可以接受)
   - 拉取更新的 base image 重出 `my-app:v1.2.4`
   - 拉取**老的** `my-app:v1.2.3` 做应急回滚
       ── 这里的 v1.2.3 就是 Artifact
       ── 这里的 openssl pURL 就是 pURL
```

---

## 五、规范与扩展阅读

- pURL 规范: https://github.com/package-url/purl-spec
- pURL 官方实现: packageurl-python / packageurl-go / packageurl-java / packageurl-js
- OWASP CycloneDX: https://cyclonedx.org/specification/overview/
- SPDX (Linux Foundation): https://spdx.dev/specifications/
- SLSA Framework: https://slsa.dev/
- in-toto attestation: https://github.com/in-toto/attestation
- CISA SBOM 最低字段: https://www.cisa.gov/sbom
- Sigstore / cosign: https://docs.sigstore.dev/

---

## 六、TL;DR

- **pURL** = `pkg:<type>/<namespace>/<name>@<version>?<qualifiers>` — 一种**跨生态、机器可解析**的包命名约定,是 SBOM 和漏洞扫描的指代语言。
- **Artifact** = 构建流程的**实际产物** (镜像、压缩包、二进制、SBOM、签名…),是流水线的**物质交接物**。
- 关系:Artifact 是**物质**,pURL 是**物质的名牌**。一个描述字节,一个描述身份。
- 落地:发版 → 产物变 Artifact,扫码 → 用 pURL 引用 Artifact,漏洞追溯 → pURL 跨生态匹配,合规 → Artifact 配 SBOM+签名+VEX。
