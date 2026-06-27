# Shell Lib 复用与 Shell 测试最佳实践 — 研究笔记

> 适用范围: `common/lib/lib-{log,bucket,gar,secret,dns,iam,gke,jump}.sh` 这一类 `_xxx_` 命名空间、纯 Bash、调用 `gcloud`/`gsutil` 的内部 lib。 当前已用 `bash -n` + shellcheck,但无单元/集成测试。

---

## 1. 测试框架对比 — bats-core 是首选

| 框架 | 优势 | 短板 | 适配度 |
|------|------|------|--------|
| **bats-core** ([github](https://github.com/bats-core/bats-core)) | TAP 协议、社区活跃、CI 友好(`circleci/bats` orb 直接装)、GoogleShell `shellguide` 默认推荐 | mock 机制不是一等公民,需要自己写 PATH shim | ⭐⭐⭐⭐⭐ |
| **shellspec** ([github](https://github.com/shellspec/shellspec)) | BDD DSL、原生 `Mock`/`Intercept`、并行 + kcov 覆盖率 | DSL 学习成本,与你现有 `_xxx_` 命名风格差异大 | ⭐⭐⭐ |
| **shunit2** ([github](https://github.com/kward/shunit2)) | xUnit 风格、纯 POSIX、零外部依赖 | 维护节奏慢(2024 后才转仓库),社区较小 | ⭐⭐ |

**结论**: **bats-core 最适合 8–30 个 lib 函数规模**。它的 `setup()` / `teardown()` 钩子天然契合"每个 lib 函数 = 一组 @test",而 `bash -n + shellcheck` 已经在你的 CI 上,bats 顺势接入即可。shellspec 功能更全但对你这种内部小工具属于过度工程;shunit2 太老。

**改动文件**:
- `common/test/run-tests.bash`(新增,执行 `bats common/test/`)
- `common/test/test_lib-log.bats`(新增示例,见 §2)
- `Makefile` 或 `.github/workflows/shell-test.yml` — 新增 `bats common/test/ --recursive` 步骤

---

## 2. Mock gcloud / gsutil — PATH-inject fake binary

**标准做法是 `export PATH=$FAKE_DIR:$PATH` 让 shell 先找到 stub**,而不是在 bash 里写 wrapper 函数。理由:wrapper 函数只能拦截当前 shell 内的 `gcloud`,如果 lib 内部用了 `bash -c "..."` 或 subshell,函数就丢;fake binary 是真实可执行文件,任何子进程都看到。

参考 [HomericIntelligence/ProjectMnemosyne — bats-shell-test-patterns](https://github.com/HomericIntelligence/ProjectMnemosyne/blob/main/skills/bats-shell-test-patterns.md) 验证过的两种 stub 模式:

**模式 A — 环境变量驱动(简单场景)**:
```bash
# common/test/mocks/gcloud
#!/usr/bin/env bash
case "$1 $2" in
  "storage buckets")       echo "${GCLOUD_BUCKETS_JSON:-[]}" ;;
  "projects describe")     echo "${GCLOUD_PROJECT_JSON:-{}}" ;;
  *) echo '{}' ;;
esac
```

**模式 B — lookup 文件驱动(参数空间大时,例如不同 project × bucket 组合)**:
```bash
# 在 setup() 里
TMP=$(mktemp -d)
cat > "$TMP/gcloud" <<'EOF'
#!/usr/bin/env bash
key="gcloud:$*"
grep -F "$key" "$GCP_LOOKUP" | cut -d$'\t' -f2
EOF
chmod +x "$TMP/gcloud"
export PATH="$TMP:$PATH" GCP_LOOKUP="$TMP/data.tsv"
```
注意:bash 关联数组 **不能** `export` 给子进程(同源 skill 里 #1 失败案例),所以一定要走文件 lookup。

**teardown 必须 `rm -rf "$TMP"`** — 否则 fake binary 会泄漏到下一个 `@test`,造成诡异 flaky。([bats 文档 setup/teardown](https://bats-core.readthedocs.io/en/stable/writing-tests.html))

---

## 3. lib 加载模式 — Lazy source + 命名空间 export

| 模式 | 适用 | 风险 |
|------|------|------|
| 全量 source (顶层 `. common/lib/*.sh`) | 小脚本,启动快无所谓 | 命名冲突,启动慢 |
| Autoload (按需 source) | 工具箱式 | bash 没有原生 autoload,要手写 dispatcher |
| **签名式 lazy source**(推荐) | 你的 lib 现状 | 实现轻量 |

**建议在每个 lib 顶部加 loader guard**:
```bash
# common/lib/lib-bucket.sh
if [[ -z "${_LIB_BUCKET_LOADED:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/lib-log.sh"
    _LIB_BUCKET_LOADED=1
fi
_bucket_create() { _log_info "..."; gcloud storage buckets create ...; }
export -f _bucket_create
```
`export -f` 让子进程/parallel 子 shell 也能调。这呼应 Google styleguide [s7.5 Local Variables](https://google.github.io/styleguide/shellguide.html) 的反向用法 — lib 函数不是 "local",需要跨边界,所以必须 export。

---

## 4. 版本管理 — Semver in header + changelog 对照表

两个机制叠加:

**(a) 每个 lib 文件顶部声明版本**:
```bash
# common/lib/lib-bucket.sh
# LIB_BUCKET_VERSION=2.4.1  # bump on signature change
```

**(b) `common/CHANGELOG.md` 用一张 "release → lib 矩阵表"**:
```
| release | lib-log | lib-bucket | lib-gar | ... |
| 2026.05 | 1.2.0   | 2.4.1      | 0.9.3   |     |
| 2026.06 | 1.2.0   | 2.5.0      | 0.9.3   |     |
```
列不变、行追加,任何 release 一眼看清打了哪些 lib。Git tag 用 `lib-bucket-v2.5.0` 这样可以独立 pin。

release 脚本在执行前 `grep LIB_*_VERSION common/lib/*.sh` 写进 release manifest,作为审计凭证。

---

## 5. 错误处理边界 — `set -euo pipefail` 但要懂得 catch

Google [shellguide s6/s8](https://google.github.io/styleguide/shellguide.html) 推荐库函数**不**自己 `set -e`,而是要求调用方启用。**但** lib 顶层要写 `set -uo pipefail`(故意**不开 -e**),理由:

- **`-e` 必须 catch 的场景**:gcloud 调用失败、文件不存在 — 用 `if ! cmd; then _log_error; return $ERR_GCLOUD; fi` 显式处理(也方便单测断言 `status`)
- **`-e` 必须 catch 掉的场景**:grep 找不存在字符串(`grep pattern file | wc -l` 在 set -e 下会因 pipefail 假阳性退出) — 用 `|| true` 或前面 §2 的 `_rc=0; cmd || _rc=$?` captured-rc 模式(同源 skill 第 6 节)
- **永远不要 catch 的场景**:变量未声明(`-u` 该炸就炸,不然拿到空字符串一路污染下去)

`set -uo pipefail` 的 `-o pipefail` 是关键 — `gcloud ... | jq .foo` 时 jq 失败会带出整条 pipeline 失败,而不是只看到 gcloud 退出 0。

---

## 6. 可观测性 — 三件套

| 维度 | 工具 | 接法 |
|------|------|------|
| 结构化日志 | 已有 `_log_info/warn/error` | 加 `printf '{"ts":"%s","level":"%s","lib":"%s","func":"%s","msg":"%s","trace_id":"%s"}\n' ...` 输出 JSON 行;`LOG_FORMAT=json` 切换 |
| Metrics | OpenTelemetry Collector OTLP | lib 启动时 spawn 一个 background `curl -X POST $OTEL_ENDPOINT/metrics` — bash 没原生 SDK,轻量做法 |
| 分布式追踪 | W3C `traceparent` header | release 脚本生成 `TRACE_ID`,通过 env var 注入 lib,lib 调用 gcloud 时 `--trace-token $TRACE_ID` (gcloud 原生支持) |

最少要做的:把 `_log_*` 升级成 JSON 行 + 加 `_LIB_TRACE_ID` env var 透传。这两项加起来 < 50 行。

---

## 7. lib 与 release 脚本的解耦 — "lib 是 immutable artifact"

核心原则:**lib 一旦被某个 release 引用,签名(参数、返回值语义)就锁死**。lib 的迭代 = 新的 lib 版本号 + 新的 release 引用。

落地三招:
1. **lib 自身有 SemVer + CHANGELOG**(§4)
2. **release manifest 记录 lib 指纹**: `sha256sum common/lib/*.sh > release.lock`,release 脚本启动时 `sha256sum -c release.lock`,不一致就拒绝运行
3. **bats 测试覆盖"旧 release 脚本 + 新 lib"的组合矩阵** — CI 里跑一次 `tests/matrix/old-release-vs-new-lib.bats`,提前发现 breaking change

升级 lib 的流程:`修改 lib → 升 SemVer → 跑 bats → bump release.lock → 发版`。lib 永远不会"偷偷改签名",因为锁文件 + 测试矩阵两道关。

---

## 实操清单(按 ROI 排序)

1. ☐ `brew install bats-core` + `common/test/test_lib-log.bats`(一个示例,跑通 CI 闭环)— 0.5 天
2. ☐ `common/test/mocks/{gcloud,gsutil}` PATH-shim 模板 — 0.5 天
3. ☐ 每个 lib 加 `_LIB_XXX_VERSION` header + `common/CHANGELOG.md` 矩阵表 — 0.5 天
4. ☐ `_log_*` 升级 JSON 行 + `_LIB_TRACE_ID` 透传 — 1 天
5. ☐ `release.lock` + matrix CI — 1 天

## 出处链接

- bats-core: https://github.com/bats-core/bats-core · 文档 https://bats-core.readthedocs.io
- shellspec: https://github.com/shellspec/shellspec
- shunit2: https://github.com/kward/shunit2
- Google Shell Style Guide: https://google.github.io/styleguide/shellguide.html
- ShellCheck: https://www.shellcheck.net/
- Bats 测试模式(已验证)skill: https://github.com/HomericIntelligence/ProjectMnemosyne/blob/main/skills/bats-shell-test-patterns.md
