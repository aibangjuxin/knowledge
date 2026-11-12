# FOSS 是什么？——自由与开源软件完全指南

> 面向安全团队 / 合规团队 / 平台工程团队的 FOSS 科普与落地手册
> 关键词：FOSS、开源合规、许可证、SBOM、软件供应链、Copyleft

---

## 📖 目录

1. [一句话定义](#1-一句话定义)
2. [Free 与 Open 的区别（两个词，不是同义词）](#2-free-与-open-的区别两个词不是同义词)
3. [FOSS 的四个核心自由](#3-foss-的四个核心自由)
4. [常见开源许可证速查](#4-常见开源许可证速查)
5. [许可证传染性与合规风险](#5-许可证传染性与合规风险)
6. [FOSS 与软件供应链安全](#6-foss-与软件供应链安全)
7. [SBOM：让 FOSS 可审计](#7-sbom让-foss-可审计)
8. [企业落地实践（如何避免违规）](#8-企业落地实践如何避免违规)
9. [常用工具链](#9-常用工具链)
10. [检测与修复脚本](#10-检测与修复脚本)
11. [检查清单](#11-检查清单)
12. [常见误区澄清](#12-常见误区澄清)
13. [参考资源](#13-参考资源)

---

## 1. 一句话定义

> **FOSS = Free and Open-Source Software（自由与开源软件）**
> 指**源代码公开可得**、**任何人可以检视、修改、再分发**，并且**采用许可证明确授予这些权利**的软件。

在企业语境里，人们常常把 FOSS 直接简称为"开源软件"。它的范围远不止 Linux 内核，还包括：

| 类别 | 例子 |
|------|------|
| 操作系统 | Linux Kernel、FreeBSD、ReactOS |
| 编程语言 | Go、Rust、Python、TypeScript、PHP |
| Web 框架 | Django、Spring Boot、Flask、Gin、Nuxt |
| 数据库 | PostgreSQL、MySQL、MariaDB、Redis、ClickHouse |
| 中间件 | Nginx、Kafka、RabbitMQ、Envoy |
| 容器生态 | Docker、Kubernetes、containerd、Helm |
| CI/CD | Jenkins、GitLab CE、Drone |
| 监控 | Prometheus、Grafana、OpenTelemetry |
| 工具链 | Git、Vim、tmux、ripgrep、Terraform |

---

## 2. Free 与 Open 的区别（两个词，不是同义词）

这是理解 FOSS 最重要的一点。

### 2.1 "Free as in Beer" vs "Free as in Freedom"

| 说法 | 含义 |
|------|------|
| **Free as in Beer** | 免费（不收钱），但源代码闭源 |
| **Free as in Freedom** | 免费 **且** 你拥有检视、修改、再分发的自由 |

FOSS 指的是 **Free as in Freedom**。仅仅"免费下载安装"不等于开源；同样，**免费软件也可以是专有的**（proprietary / closed-source）。

### 2.2 Richard Stallman 的四大自由（FSF 视角）

Stallman 在 1989 年 GNU 宣言中提出，软件自由分四层：

1. **自由 0 — 运行**：作为你的自由的一部分，为任何目的运行这份软件的自由。
2. **自由 1 — 研究与修改**：获得源代码，并有权修改它以做你需要的事的自由。
3. **自由 2 — 再分发**：可以自由地把精确的副本重新分发给他人的自由。
4. **自由 3 — 分发修改版**：可以自由地分发改进后的版本，让整个社区受益的自由。

> **Free Software 的本质是"自由"，而不是"免费"。** 一个项目可以收费（商业支持、托管服务），只要它依然提供这四项自由，依然是 FOSS（例如 Red Hat、GitLab、SUSE）。

### 2.3 为什么"开源"不等于"可以随便用"

开源 ≠ 无条件使用。**许可证（License）**才是决定"你能怎么用"的合同。软件可以"开源"，但同时附带严格的义务（最典型的是 GPL 的 Copyleft）。

---

## 3. FOSS 的四个核心自由

从工程与合规角度重新表述这四项自由，便于落地：

| 自由 | 工程含义 | 合规含义 |
|------|----------|----------|
| 检视（Study） | 可以审计源码，安全审计、漏洞挖掘 | 供应商可验证，不被黑盒绑架 |
| 修改（Modify） | 可打补丁、适配场景、修复 bug | 有后路，不被单一厂商 lock-in |
| 再分发（Redistribute） | 可内嵌到商业产品 | 可构建私有产品 |
| 传播修改（Share） | 贡献回社区，形成生态 | 修改版需回馈（Copyleft） |

### 3.1 FOSS 的现实价值（为什么要推 FOSS）

- **安全透明**：源码公开，安全研究者可以审计；供应链攻击（XzUtils、event-stream、Log4Shell）时，你能自己验证。
- **成本可控**：避免 License 费用与供应商锁定。
- **技术自主**：不被单一厂商的 EOL（End of Life）节奏绑架。
- **合规友好**：多数许可证清晰，允许商业使用（需尽调）。
- **人才与生态**：招聘、社区支持、文档丰富。

---

## 4. 常见开源许可证速查

### 4.1 宽松型（Permissive）—— 商用友好

| 许可证 | 商用 | 修改 | 分发 | 闭源分发 | 强制开源 | 专利条款 | 备注 |
|--------|------|------|------|----------|----------|----------|------|
| **MIT** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 最宽松，Go/Rust 生态常用 |
| **BSD-2-Clause** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 与 MIT 几乎等价 |
| **BSD-3-Clause** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 多了"不得用作者名背书"条款 |
| **Apache-2.0** | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | **含显式专利授权**，企业首选 |
| **ISC** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 极简 |

> **Apache-2.0 vs MIT**：Apache-2.0 多了 (1) 显式专利授权与专利诉讼终止条款；(2) NOTICE 文件保留要求；(3) 变更声明要求。企业合规场景推荐 Apache-2.0。

### 4.2 弱 Copyleft（弱著佐权）

| 许可证 | 商用 | 闭源分发 | 强制开源范围 | 备注 |
|--------|------|----------|--------------|------|
| **LGPL-2.1 / LGPL-3.0** | ✅ | ✅ | 仅限被修改的库本身 | 动态链接通常安全，**静态链接需注意** |
| **MPL-2.0** | ✅ | ✅ | 仅限被修改的文件（文件级 Copyleft） | Firefox 采用；比 LGPL 更直观 |

> **LGPL 的关键点**：以"库"形式使用、动态链接 → 一般不触发开源义务；把 LGPL 代码**静态链接进你的闭源程序**并分发 → 需要提供 LGPL 部分源码或提供可链接的替换库。

### 4.3 强 Copyleft（Copyleft / 著佐权）

| 许可证 | 商用 | 闭源分发 | 触发义务 | 备注 |
|--------|------|----------|----------|------|
| **GPL-2.0 / GPL-3.0** | ✅ | ❌ | **整个衍生作品必须开源** | 最强的"传染性" |
| **LGPL** | ✅ | ✅ | 见上 | 弱化版 GPL |
| **AGPL-3.0** | ✅ | ❌ | **即使作为 SaaS 网络服务提供，也必须开源** | 对闭源 SaaS 威胁最大 |

> ⚠️ **AGPL 是云服务厂商的"毒药条款"**：MongoDB、Elasticsearch（SSPL/Elastic License）都因此转向自研许可证。若你打算把某个 AGPL 项目作为 SaaS 对外提供服务，必须开源你的全部衍生代码——这通常是商业大忌。

### 4.4 源码可用（Source Available）≠ 开源

这些许可证**禁止**你把代码用作竞争产品，通常**不**满足 OSI 定义：

| 许可证 | 特征 |
|--------|------|
| **SSPL** (Server Side Public License) | 服务端使用需开源；MongoDB 用过 |
| **BUSL-1.1** | 一定期限后转为 GPL，期内有使用限制；MariaDB、HashiCorp 用过 |
| **Elastic License 2.0** | 禁止托管为竞争服务；Elastic 使用 |
| **BSL** (Business Source License) | 商业友好，附加"禁止竞争"条款 |
| **CC BY-NC / CC BY-SA** | 内容创作许可，**通常不是软件许可**，用于文档/素材 |
| **CC BY-NC-SA** | 含 NC（非商业）与 SA（同许可），代码场景基本不可用 |

> ❗ **合规红线**：带 **NC（Non-Commercial）** 的许可证用于商业产品属于违规。

---

## 5. 许可证传染性与合规风险

### 5.1 Copyleft 的"传染"到底传染什么

Copyleft 不是"整个公司都开源"，而是**沿着"衍生作品"边界传染**：

```
你的闭源主程序
   └── 链接 / 静态包含 GPL 库
          └── ⚠️ 整个组合体被认定为 GPL 衍生作品 → 必须整体以 GPL 发布
```

判断要点：

| 场景 | 是否传染 |
|------|----------|
| **进程内调用**（Java import Python 无关场景；C 程序 `link` GPL 库） | ✅ 传染 |
| **静态链接** GPL 库 | ✅ 传染 |
| **动态链接** GPL 库 | ⚠️ 有争议（FSF 认为传染） |
| **动态链接** LGPL 库 | ❌ 不传染（需提供替换能力） |
| **Fork 后独立进程、通过网络/API 通信** | ❌ 不传染（这是 AGPL 存在的原因） |
| **只是复制粘贴几行代码** | ⚠️ 需做实质性判断，别抄 |

### 5.2 常见违规场景（Violation）

| 违规类型 | 典型表现 | 后果 |
|----------|----------|----------|
| **许可证冲突** | 同一产品内 MIT + GPL(v3) 混用 | 必须整体 GPLv3 开放 |
| **AGPL 泄露** | 闭源 SaaS 内嵌 AGPL 服务 | 需公开全部衍生代码；已被判例（Artifex、GitLab vs. 木马纸） |
| **MIT 版权声明丢失** | 删掉了 LICENSE 文件中的版权声明 | 违反 MIT 第 1 条，需修复 |
| **Apache-2.0 NOTICE 丢失** | 分发时未保留 NOTICE | 违规 |
| **署名条款违反** | BSD-3 的"不得用作者名背书"被破坏 | 违规 |
| **专利条款触发** | 发起专利诉讼指控开源贡献者 | Apache-2.0 专利授权终止 |
| **商标滥用** | 用项目名/Logo 为自己产品背书 | 违反商标条款（如 Redis、Elastic） |
| **源代码未提供** | 分发二进制但未按 GPL 提供对应源码 | 违规 |
| **SBOM 缺失** | 无法举证依赖树 | 无法通过审计 |
| **商业许可证过期** | 使用了社区版但按企业功能 | 需补购 |

### 5.3 修复违规的通用路径

```
发现 → 定位依赖 → 判断影响 → 选择策略 → 修复 → 验证 → 留档
```

1. **定位**：用 SBOM + 依赖扫描工具找出违规组件及版本。
2. **判断**：
   - 是许可证本身不允许（如 NC）→ 替换组件。
   - 是 Copyleft 传染 → 评估：换用宽松库 / 改为独立进程 + API 调用 / 接受开源义务。
   - 是文件缺失（LICENSE/NOTICE）→ 补齐即可。
3. **修复**：
   - **替换法**：用宽松许可证的等价库替换（如 `GPL libxml2` → `MIT pugixml`）。
   - **隔离法**：把 GPL/AGPL 组件拆成独立进程，通过 HTTP/gRPC 通信（AGPL 仍会传染服务端，需额外确认）。
   - **降级法**：使用旧版本（无漏洞且许可证宽松的版本）。
   - **买断法**：购买商业许可证（Red Hat、Elastic、Synopsys 等）。
   - **开源化**：接受义务，按 GPL 发布自有代码并履行源码提供义务。
4. **验证**：重新生成 SBOM，跑许可证策略检查。
5. **留档**：保留原始声明、审批记录、例外说明，作为审计证据。

---

## 6. FOSS 与软件供应链安全

FOSS 本身不是安全漏洞的来源，但**依赖关系**是最大的攻击面。

### 6.1 供应链风险全景

```
你的应用
 ├── 直接依赖 (npm / pip / go modules / maven)
 ├── 传递依赖 (transitive, 往往 10~100 倍于直接依赖)
 ├── 基础镜像 (base image)
 ├── 构建工具链 (compiler, CI action)
 └── 制品仓库 (registry, mirror)
        ↑ 每一层都可能被投毒
```

### 6.2 典型供应链攻击手法

| 手法 | 案例 | 教训 |
|------|------|------|
| **拼写抢注**（typosquatting） | `requests` → `reqests` | 锁定精确版本 + 校验 hash |
| **依赖混淆**（dependency confusion） | 内部包名被公共 registry 抢注 | 用 scope 隔离 + 私有源优先 |
| **维护者账号劫持** | event-stream / ua-parser-js | 开启 2FA + 发布签名 + 监控发布异常 |
| **恶意包版本** | xz-utils 后门（2024，CVE-2024-3094） | 构建期扫描 + 关键包手动审核 |
| **构建脚本注入** | npm postinstall 脚本 | 禁用生命周期脚本 + 沙箱构建 |
| **上游投毒** | 3xM International 事件流公司 | SBOM + 组件来源白名单 |
| **SBOM 欺骗** | 组件声明与实际不符 | 运行时文件清单 + 签名验证 |

### 6.3 FOSS 组件的纵深防御措施

| 措施 | 作用 | 工具 |
|------|------|------|
| **SBOM 持续生成** | 知道自己在用什么 | Syft、Trivy、Microsoft CycloneDX |
| **签名验证** | 防篡改 | Sigstore/cosign、in-toto、Notary |
| **依赖锁定** | 防止版本漂移 | `package-lock.json`、`go.sum`、`poetry.lock` |
| **私有源 + 代理** | 阻断拼写抢注 | Nexus/Artifactory 代理 + 白名单 |
| **许可策略引擎** | 构建时拦截违规 | Nexus IQ、FOSSA、License Finder |
| **SBOM 归档到制品** | 事后可追溯 | `cosign attest sbom` |
| **OSV / CVE 监控** | 持续告警 | OSV-Scanner、Dependabot、Renovate |

> 💡 **关键认知**：**FOSS 的最大优势恰恰是"可审计"**。闭源组件你无法验证；FOSS 组件你可以审计源码、构建可复现产物（reproducible build）、验证签名。所以推 FOSS 与强化供应链安全是同一件事的两面。

---

## 7. SBOM：让 FOSS 可审计

### 7.1 SBOM 是什么

**SBOM（Software Bill of Materials，软件物料清单）** 是一份列出软件中所有组件的机器可读清单。

标准格式：
- **SPDX**（Linux 基金会）—— 许可证表达最强，业界主流
- **CycloneDX**（OWASP）—— 组件、漏洞、SBOM 签名生态完善
- **SWID Tag**（ISO/IEC 19770-2:2015）—— 软件标识标签

### 7.2 SBOM 里有什么

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "components": [
    {
      "name": "golang.org/x/net",
      "version": "v0.17.0",
      "purl": "pkg:golang/golang.org/x/net@v0.17.0",
      "licenses": [{ "license": { "id": "BSD-3-Clause" } }],
      "hashes": [{ "alg": "SHA-256", "content": "..." }],
      "purl": "pkg:golang/golang.org/x/net@v0.17.0",
      "externalReferences": [{ "url": "https://cs.opensource.google/go/x/net" }]
    }
  ]
}
```

注意 SBOM 里 **licenses 字段** 就是许可证合规的自动化抓手。

### 7.3 SBOM 落地节奏

| 阶段 | 动作 |
|------|------|
| **构建期** | 每次 CI 构建自动生成 SBOM，随制品归档 |
| **发布期** | 用 cosign 对 SBOM 做签名/attestation，绑定镜像 digest |
| **运行期** | 部署时校验 SBOM 签名，与实际运行文件清单比对 |
| **响应期** | CVE 公告 → 自动查 SBOM → 评估影响面 → 通知责任人 |

> 欧盟 **Cyber Resilience Act (CRA)** 与 **DORA**、美国 **EO 14028**、中国《网络安全法》及等保测评均在不同程度上要求或强烈建议提供 SBOM。

---

## 8. 企业落地实践（如何避免违规）

### 8.1 政策层面

建立一份**《开源软件使用政策》**，至少包含：

1. **许可分类白名单**：允许 MIT / BSD / Apache-2.0 / ISC / MPL-2.0 / LGPL（动态链接）。
2. **需审批名单**：GPL / AGPL / SSPL / BUSL / 任何 CC-BY-NC 类。
3. **禁止名单**：含 NC 条款、来源不明、无许可证的代码。
4. **例外流程**：谁可以批、批什么、有效期多久、如何留档。
5. **义务要求**：分发二进制时必须附带 LICENSE/NOTICE/源码提供方式。
6. **组件准入**：新依赖必须先扫描再引入；优先使用公司内部已审核的"黄金依赖列表"。

### 8.2 流程层面

```
开发者提交代码
      ↓
CI 阶段：许可证扫描 + 漏洞扫描 + SBOM 生成
      ↓
策略门禁（Policy Gate）：违规 → 直接失败构建
      ↓
例外申请 → 安全/法务审批 → 记录例外（有效期 + 复审日期）
      ↓
发布：制品 + SBOM + 许可证声明文件 一起归档
      ↓
季度审计：复核例外是否仍必要，新 CVE 导致的许可影响评估
```

### 8.3 技术层面

- **构建门禁示例**（GitHub Actions）：

```yaml
- name: License compliance gate
  run: |
    syft "$IMAGE" -o cyclonedx-json > sbom.json
    npx license-checker --production --summary
    # 或使用 FOSSA / ScanCode CLI 严格模式
    scan --license-reference ./license-policy.yml sbom.json --fail-on-policy-violation
```

- **FOSSA / Nexus IQ 策略示例**：

```yaml
# Nexus IQ 策略（示意）
- name: "禁止 AGPL 进入生产依赖"
  format: "maven2"          # 或 npm / docker / golang
  policy:
    - condition: true
      action: fail
      flags:
        - "deny AGPL*"
        - "deny GPL-3.0*"

- name: "强制 Apache/MIT 白名单"
  format: "npm"
  policy:
    - condition: true
      action: fail
      flags:
        - "allow Apache-2.0"
        - "allow MIT"
        - "allow BSD-*"
```

### 8.4 法务义务清单（分发时别忘）

- [ ] 保留所有第三方 `LICENSE` / `COPYING` 文件（在 `THIRD_PARTY_LICENSES/` 目录）
- [ ] 保留 `NOTICE` 文件及其中列出的归属声明
- [ ] 保留源码中每个文件的原始版权头注释
- [ ] 按 Apache-2.0 要求保留修改说明（若有修改）
- [ ] GPL 类组件：随二进制提供**完整对应源码** + 构建脚本 + 安装说明（提供方式可以是"书面offer"或"随附tarball"）
- [ ] 标注"本产品包含第三方开源软件"及归属清单（THIRD_PARTY_NOTICES）
- [ ] 不使用上游项目的商标/Logo 暗示背书

---

## 9. 常用工具链

### 9.1 许可证扫描

| 工具 | 语言生态 | 说明 |
|------|----------|------|
| **SCANOSS / ScanCode CLI** | 通用（源码级） | 最准的代码级许可证识别，AGPL 首选 |
| **FOSSA** | 多生态 | SaaS，策略即代码，有免费额度 |
| **Nexus IQ** | Maven/npm/… | 企业级策略引擎，与 CI 深度集成 |
| **License Finder** (Ruby) | 多生态 | Ruby 官方，报告友好 |
| **license-expression** (Python) | 通用 | SPDX 表达式解析库 |
| **pip-licenses / go-licenses / license-checker** | 单生态 | 单生态轻量方案 |
| **Black Duck** | 多生态 | 商业 SBBOM 方案，与 FOSSA 竞品 |

### 9.2 供应链与 SBOM

| 工具 | 用途 |
|------|------|
| **Syft** | 从镜像/文件系统/目录生成 SBOM（CycloneDX/SPDX） |
| **Grype** | 基于 SBOM 的漏洞扫描 |
| **Trivy** | 一站式：漏洞 + 许可证 + 密钥 + 配置 + SBOM 生成 |
| **cosign / Sigstore** | 镜像与 SBOM 签名、attestation |
| **Notary v2 / Notation** | 制品签名（OCI 原生） |
| **OSV-Scanner** | 基于 OSV 数据库的依赖漏洞扫描 |
| **in-toto / SLSA** | 供应链完整性框架（provenance 证明） |
| **Scorecard** (OpenSSF) | 开源项目安全健康度打分 |

### 9.3 依赖管理

| 生态 | 锁定文件 | 私有源建议 |
|------|----------|-----------|
| Node.js | `package-lock.json` / `pnpm-lock.yaml` | `.npmrc` 设置 `registry` + `scope` 隔离 |
| Python | `poetry.lock` / `requirements.txt` + hash | `pip.conf` + `index-url` |
| Go | `go.sum` + `GOPRIVATE`/`GONOSUMDB` | `GOPROXY` 指向内部代理 |
| Java | Maven `dependency:tree` + Nexus | Nexus/Artifactory 代理 + 仓库级白名单 |
| Rust | `Cargo.lock` | crates.io 代理 + 审计（`cargo audit`） |

### 9.4 社区健康度评估

开源组件引入前，用 **OpenSSF Scorecard** 看看项目健康度：

```bash
# 手动查看某项目的 Scorecard 评分
curl -s https://api.securityscorecards.dev/projects/github.com/golang/go | jq '.checks[].score'
```

关注维度：分支保护、危险 workflow 触发器、依赖更新工具、签名发布、SAST、模糊测试。

---

## 10. 检测与修复脚本

### 10.1 生成 SBOM

```bash
# 从容器镜像生成 CycloneDX SBOM
syft your-image:latest -o cyclonedx-json > sbom.json

# 从当前目录生成 SPDX SBOM
syft dir:. -o spdx-json > sbom.spdx.json

# Trivy 一条命令搞定（漏洞 + 许可证 + SBOM）
trivy image --format cyclonedx --output sbom.json your-image:latest
```

### 10.2 扫描并按许可证分类

```bash
# Trivy 列出所有许可证
trivy image --scanners license --format json your-image:latest \
  | jq -r '.Results[].Licenses[]?.Name' | sort | uniq -c | sort -rn

# 找出所有 Copyleft / 强传染组件
trivy image --scanners license --format json your-image:latest \
  | jq -r '.Results[] | .Target as $t | .Licenses[]?
           | select(.Name|test("GPL|AGPL|LGPL|MPL|SSPL|BUSL|CC-BY-NC"))
           | "\($t)\t\(.Name)"'
```

### 10.3 依赖树全量排查

```bash
# Go：列出所有依赖及其许可证
go list -m all | while read -r mod ver; do
  echo "$mod $ver"
done

# Node.js：生产依赖许可证
npm ls --all --json \
  | jq -r '.dependencies | to_entries[] | "\(.key)\t\(.value.licenses // "UNKNOWN")"' \
  | sort -u

# Python
pip-licenses --format=csv --with-urls --with-desc > licenses.csv

# Maven
mvn license:aggregate-add-third-party -DgenerateReports=true
```

### 10.4 判定是否违反 Copyleft

```bash
# 找出被静态链接进二进制的 GPL 符号
nm -C ./your-binary 2>/dev/null | grep -i "gpl" | head -20

# 检查 ELF 依赖（找动态链接的库）
ldd ./your-binary

# Java：检查 JAR 的许可证
for jar in $(find . -name "*.jar"); do
  unzip -p "$jar" META-INF/LICENSE* 2>/dev/null | head -3 | sed "s|^|$jar: |"
done
```

### 10.5 一键生成第三方声明文件

```bash
#!/usr/bin/env bash
# generate-tt-licenses.sh —— 收集并生成 THIRD_PARTY_NOTICES
set -euo pipefail

OUT_DIR="${1:-THIRD_PARTY_NOTICES}"
mkdir -p "$OUT_DIR"

# 1) 收集容器/依赖树中的许可证
syft dir:. -o spdx-json 2>/dev/null \
  | jq -r '.packages[]? | select(.licenseDeclared != "NOASSERTION")
           | "\(.name)@\(.versionInfo // "unknown")\t\(.licenseDeclared)"' \
  | sort -u > "$OUT_DIR/components.tsv"

# 2) 复制仓库内自带的 LICENSE 文件
find . -type f \( -iname "LICENSE*" -o -iname "COPYING*" -o -iname "NOTICE*" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" \
  -exec cp --parents {} "$OUT_DIR"/ \; 2>/dev/null || true

echo "✅ 已生成：$OUT_DIR"
echo "   - components.tsv  （组件与许可证清单）"
echo "   - 各第三方 LICENSE 原文副本"
```

```bash
chmod +x generate-tt-licenses.sh
./generate-tt-licenses.sh
```

---

## 11. 检查清单

### 11.1 开源组件引入前（准入）

- [ ] 使用公司"黄金依赖列表"中的组件优先
- [ ] 确认许可证类型属于白名单或已获审批
- [ ] 确认项目健康度（OpenSSF Scorecard、维护活跃度、issue 响应）
- [ ] 确认无已知高危 CVE（Trivy / OSV-Scanner）
- [ ] 确认无恶意行为（`postinstall` 脚本、二进制 blob、混淆代码）
- [ ] 确认依赖树（传递依赖）整体无违规
- [ ] 在 SCA 系统中登记，指定责任人

### 11.2 构建与发布

- [ ] SBOM 自动生成并随制品归档
- [ ] SBOM 已用 cosign 签名并绑定制品 digest
- [ ] 许可证策略门禁在 CI 中生效（违规阻断构建）
- [ ] THIRD_PARTY_NOTICES 随发行包分发
- [ ] 所有 LICENSE / NOTICE / 版权头完整保留
- [ ] GPL 类组件已按要求提供对应源码
- [ ] 未使用上游商标/Logo 暗示背书

### 11.3 运维期

- [ ] 定期扫描新披露 CVE 与许可证变更（例如某许可证被 relicensing）
- [ ] 例外审批记录有到期复审
- [ ] 依赖自动更新（Renovate / Dependabot）开启，且更新走同样的门禁
- [ ] 季度复核：是否可移除高风险/冗余依赖（减少攻击面即减少许可风险）

### 11.4 事件响应

- [ ] 收到上游组件被投毒 / 0day 公告时，可快速从 SBOM 定位受影响制品
- [ ] 有"从 SBOM 查影响面"的应急流程（参考本目录 [quick-reference.md](quick-reference.md)）

---

## 12. 常见误区澄清

| 误区 | 事实 |
|------|------|
| "开源软件更安全" | 源码公开 ≠ 代码无漏洞。Log4Shell、Heartbleed 都是 FOSS。开源的优势是**可审计**和**可修复**，不是天生安全 |
| "免费 = 开源" | Freeware 闭源免费很常见。免费且闭源 ≠ FOSS |
| "只用了几个函数，不算使用" | 复制粘贴代码片段同样受许可证约束，"实质性相似"由法院判定 |
| "内部使用不触发 GPL" | 仅"不分发"时确实无分发义务。但云上提供 AGPL 服务、对外提供 SaaS → AGPL 明确触发 |
| "用了 Apache-2.0 就没风险" | 仍需保留 NOTICE、版权声明、修改说明；且需履行专利条款 |
| "MIT 和 BSD 没区别" | BSD-3 有"不得背书"条款，Apache-2.0 有专利授权，差异在企业场景很关键 |
| "动态链接就不传染" | LGPL 动态链接一般安全，但 **GPL 动态链接**在 FSF 立场下会传染，法律上仍有争议 |
| "我 fork 了就不受原许可证约束" | Fork 仍是衍生作品，GPL 要求你的 fork 也以 GPL 发布 |
| "AGPL 就是 GPL 加个 A" | AGPL 专门堵住"不分发就规避"的漏洞，把"通过网络提供服务"也算作分发 |
| "SBOM 生成完就合规了" | SBOM 是**证据和工具**，不等于合规结论；仍需策略判定与法务判断 |

---

## 13. 参考资源

### 标准与规范

- **OSI 开源定义**：https://opensource.org/osd
- **SPDX 许可证列表**：https://spdx.org/licenses/
- **CycloneDX 规范**：https://cyclonedx.org/
- **SLSA 供应链框架**：https://slsa.dev/
- **OpenSSF Scorecard**：https://scorecard.dev/

### 工具文档

- Trivy：https://trivy.dev/
- Syft：https://github.com/anchore/syft
- Grype：https://github.com/anchore/grype
- FOSSA：https://fossa.io/docs/
- ScanCode：https://scancode.io/
- cosign / Sigstore：https://docs.sigstore.dev/

### 法律与合规

- GNU 许可证列表与 FAQ：https://www.gnu.org/licenses/
- Software Freedom Law Center：https://softwarefreedom.org/
- OpenChain (ISO 5230)：https://openchainproject.org/
- 欧盟 Cyber Resilience Act：https://digital-strategy.ec.europa.eu/

### 延伸阅读

- 本目录 [quick-reference.md](quick-reference.md) —— 容器安全应急命令速查
- 本目录 [remediation-strategies.md](remediation-strategies.md) —— 违规修复策略矩阵
- 本目录 [ci-cd-integration.md](ci-cd-integration.md) —— CI/CD 集成详解
- 本目录 [detection-tools.md](detection-tools.md) —— 检测工具对比

---

**版本**：1.0
**维护团队**：Security Team
**更新日期**：2025-11-10
**适用范围**：全员（研发 / 安全 / 法务 / 平台工程）
