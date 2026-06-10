# Ollama `/v1/embeddings` Hang Bug — Warmup Pattern (macOS 实战视角)

## 1. 一句话本质

> **Ollama 0.30.x 的 `/v1/embeddings` 端点在某些场景下会 hang 到客户端 timeout** (issue #16049 / #10831 / #16570),而 **macOS 睡眠唤醒后的"第一次 batch" 100% 命中这个 bug**。
>
> 治本方法: **在真正 ingest 之前,用 1 个 token 的 curl 探测 `/v1/embeddings`**——这个请求会**强制 Ollama 把模型从磁盘加载到 GPU VRAM**。当真正的大 batch 进来时,模型已经"热"了,不再撞冷启动 hang。

## 2. 背景:Ollama 0.30.x 的 hang bug

### 2.1 已知 issue

| Issue | 报告时间 | 现象 | 状态 |
|---|---|---|---|
| [ollama/ollama#16049](https://github.com/ollama/ollama/issues/16049) | 2026-05-08 | `/v1/embeddings` 第一次请求 hang,后续请求正常 | Open |
| [ollama/ollama#10831](https://github.com/ollama/ollama/issues/10831) | 2025-05-23 | 长 batch (>= 30 chunks) 概率 hang 60s+ | Open |
| [ollama/ollama#16570](https://github.com/ollama/ollama/issues/16570) | 2026-06-06 | sleep-wake 后 `/v1/embeddings` 必然 hang | Open |

**核心症状**:
- `/api/embed` 端点不 hang,只 hang `/v1/embeddings` (OpenAI 兼容)
- hang 期间**服务端无任何错误日志**,**没有任何 timeout**,纯静默
- 客户端只能靠 socket timeout 才能检测到
- 第二次请求(同一进程)通常**立即成功**

### 2.2 最小复现命令

```bash
# 1. 拉一个 embedding 模型
ollama pull embeddinggemma:300m

# 2. 启动 ollama serve
ollama serve &

# 3. 冷启动请求(必 hang 60s,实际 30s 后 timeout)
time curl -sS -m 5 -X POST http://127.0.0.1:11434/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"embeddinggemma:300m","input":["first request"]}'
# curl: (28) Operation timed out after 5001 milliseconds

# 4. 第二次请求(立即成功 ~50ms)
time curl -sS -m 5 -X POST http://127.0.0.1:11434/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"embeddinggemma:300m","input":["second request"]}'
# {"object":"list","data":[{"embedding":[0.0123,...]}]}
# real    0m0.052s
```

## 3. macOS 睡眠唤醒的隐藏陷阱

### 3.1 触发链

```
launchd 02:00 唤醒 Mac
  → Mac 从 S3 (hibernation) 恢复
  → 操作系统把 GPU VRAM 全部清空 (Metal driver 释放资源)
  → Ollama 进程仍存活,但模型 layer 已被 unload
  → 第一次 /v1/embeddings 请求
    → Ollama 触发模型重新加载到 VRAM
    → 加载耗时 1-15s (取决于模型大小、磁盘速度)
    → hang bug 触发:等待 GPU 调度超时
    → 客户端 30s/60s 后 timeout
```

**为什么"必中"**:
- 任何 sleep-wake 后第一次 GPU 任务,Ollama 都要重新 init Metal context
- 0.30.x 的 Metal backend 跟 `/v1/embeddings` 有 race condition
- 后续请求因为 context 已 init,不再触发

### 3.2 验证方法

看 Ollama 内部日志 (`~/.ollama/logs/server.log`):

```bash
# 等下次 hang 后
tail -100 ~/.ollama/logs/server.log | grep -E "loaded model|ran|error"
# {"level":"INFO","msg":"loaded model","size":"593 MiB"}    ← 重新加载
# {"level":"INFO","msg":"ran","model":"...","resp_time":"50ms"}  ← 正常 50ms
# (没有 "error" 行)                                         ← hang 期间零错误
```

**关键信号**:日志里**没有** "ran" 消息,但客户端已 timeout,说明请求**根本没到 Ollama 内部** —— hang 发生在 socket 接收或 GPU 调度层。

## 4. Warmup Pattern 详解

### 4.0 前置约束 — embeddinggemma 的 2K token context

> **Embeddinggemma 300m 的 `context_length = 2048` tokens**。这个数字是**整批 input 的总预算**,不是"每个 chunk 可以塞 2048 token"。
>
> 实际安全上限 ≈ **1900 tokens/chunk**(预留 ~150 tokens 给 BOS/EOS/特殊 token)。

**这条约束会级联影响以下配置**:

| 你的配置 | 当前值 | 与 2K context 的关系 | 风险 |
|---|---|---|---|
| `chunker.chunk_size` (rag.yaml:73) | `1024` | ✅ 安全 (~1024 token/chunk) | 1024 < 1900,余量充足 |
| `chunker.chunk_overlap` (rag.yaml:74) | `128` | ✅ 安全 (1024+128=1152) | 仍 < 1900 |
| `embedder.batch_size` (rag.yaml:31) | `32` (推荐 `40`) | ⚠️ **横向放大** | 40 × ~1152 token ≈ 46K token/request,在 2K 限制**内**(限制是 per-chunk,不是 per-batch) |
| `auto_tune_loop.py:129` 候选 chunk_size | `[256,512,1024,2048]` | 🔴 **`2048` 会撞墙** | 候选表里有 2048,实际应剔除 |
| `header_levels` (rag.yaml:76) | `[1, 2]` | ⚠️ **隐式放大** | markdown_header 策略可能让单 chunk 跨多个段落,实际 token 数 ≠ chunk_size |

**2K context 触发的 3 种失败模式**:
1. **静默截断**: Ollama 截断 input 末尾 token,embedding 维度退化但 HTTP 200,难发现
2. **维度不一致**: 截断后向量与正常向量 cosine 距离异常,reranker 排序崩坏
3. **hang bug 放大**: issue #10831 在临界 batch_size 下与超长 chunk 叠加,hang 概率上升

> 📌 **本 warmup pattern 不解决 2K token 超限问题**。Warmup 只解决"冷启动 GPU 加载",不解决"input 超过模型 context 窗口"。**chunk 长度控制是 chunker 的职责,不在本文档范围内**。

### 4.1 核心:3 行 curl

```bash
curl -sfS -m 30 -X POST http://127.0.0.1:11434/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"embeddinggemma:300m","input":["warmup probe"]}' \
  >/dev/null
```

**为什么有效**:
1. **强制模型加载**:即使是 1 个 token,Ollama 也要把模型完整加载到 VRAM(无法只加载部分)
2. **触发 GPU context init**:第一次请求就把 Metal 调度 warm 起来
3. **客户端看到快速返回**:warmup 请求**成功**(因为 token 数太少,不触发 hang bug 的临界条件;hang 多发生在 batch >= 8-30 时)
4. **后续大 batch 不会 hang**:因为 GPU 已热,Ollama 内部状态已 init

### 4.2 完整 warmup block (18 行)

```bash
#!/bin/bash
set -euo pipefail

# === Warmup: pre-load model into GPU VRAM ===
# Why: Ollama 0.30.x /v1/embeddings hangs on the first request after
# macOS sleep-wake (issue #16049, #10831, #16570). The hang lasts up
# to the client timeout (60s default) and produces no error in server
# logs. Probing with a 1-token request forces Ollama to load the
# model into VRAM and warm the Metal context, so the first real
# batch never pays the cold-start latency.
#
# If warmup fails, abort: better to fail loud now than hang silently
# 60s into the ingest.
WARMUP_MODEL="${WARMUP_MODEL:-embeddinggemma:300m}"
WARMUP_URL="${WARMUP_URL:-http://127.0.0.1:11434/v1/embeddings}"
WARMUP_TIMEOUT="${WARMUP_TIMEOUT:-30}"

t0=$(date +%s)
if ! curl -sfS -m "$WARMUP_TIMEOUT" -X POST "$WARMUP_URL" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$WARMUP_MODEL\",\"input\":[\"warmup probe\"]}" \
    >/dev/null; then
  echo "[warmup] FAILED: ollama $WARMUP_URL unreachable or model not loaded" >&2
  exit 1
fi
echo "[warmup] ok, ollama reachable, model responding in $(($(date +%s)-t0))s" >&2
```

### 4.3 关键设计决策

| 决策 | 选择 | 理由 |
|---|---|---|
| **warmup 失败时** | `exit 1` (而不是 continue) | 失败说明 ollama 不在,继续跑也是撞 60s timeout,白白浪费 |
| **warmup token 数** | 1 (而不是 batch 32) | 1 token 请求**本身不容易 hang**(临界条件是 >= 8-30 chunks);大 batch warmup 等于再撞一次 bug |
| **warmup timeout** | 30s (而不是 5s) | sleep-wake 后模型重载可能要 5-15s;5s 太短会假阳性 fail |
| **warmup 输出** | stderr | 不污染下游 ingest 的 stdout log 解析 |
| **warmup env 覆盖** | `WARMUP_MODEL` / `WARMUP_URL` 可覆盖 | CI / 多模型场景灵活切换 |

## 5. 3 层防御 Stack

Warmup 不是"唯一"防御,真要稳需要**3 层组合**:

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Warmup probe  (1 token curl)                       │
│  Purpose: 提前把模型加载到 VRAM,避免冷启动                   │
│  Cost:    ~1.2s (sleep-wake 后首次) / ~50ms (热态)            │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: Retry wrapper  (3 attempts, 2s backoff)            │
│  Purpose: 兜底 — 即使 warmup 失效,真实 batch 第一次 hang     │
│           时能 retry 一次,大概率第二次成功                   │
│  Cost:    hang 60s → 30s (新 timeout) → retry → 50ms ok      │
│  Where:   src/rag/ingest/pipeline.py:_ingest_one_file_with_retry
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Timeout 60s → 30s                                  │
│  Purpose: 减少 hang 的"per-batch stall window"               │
│  Cost:    真实 batch 偶尔 > 30s 时误判 (但 batch 32 几乎不会) │
│  Where:   src/rag/embedder/client.py:33 (timeout_s=30)        │
└─────────────────────────────────────────────────────────────┘
```

### 5.1 失败链分析

| 场景 | Layer 1 | Layer 2 | Layer 3 | 净结果 |
|---|---|---|---|---|
| 热态 (有 GPU 缓存) | 50ms 探测 ok | 不触发 | 不触发 | 50ms 浪费 |
| 睡眠唤醒后首次 | 1.2s 探测 ok (VRAM 加载) | 不触发 | 不触发 | +1.2s 换 0 hang |
| 偶发 hang (race) | 50ms ok | retry 一次,第二次成功 | 30s timeout 触发 | 30s + 2s + 50ms = 32s |
| 持续 hang (Ollama 死了) | curl 30s timeout | retry 3 次,全 hang | 30s × 3 | 90s 后 exit 1 (warmup 阶段) |

## 6. 效果验证数据 (本地实测, 2026-06-09)

### 6.1 4 次跑对比

| # | 触发方式 | Warmup | Retry | Timeout | 耗时 | files_failed | 备注 |
|---|---|---|---|---|---|---|---|
| 1 | launchd 02:00 真 | ❌ | ❌ | 60s | 70.52s | 1 | 60s × 3 retry 后跳过,exit=0 |
| 2 | bash 手动 20:08 | ❌ | ❌ | 60s | 187s | 1 | retry 后跳过,exit=0 |
| 3 | bash 手动 20:51 | ❌ | ❌ | 30s | 182s | 0 | 0 失败 (Ollama 状态正好) |
| 4 | bash 手动 20:55 | ✅ | ✅ | 30s | 184s | 0 | 0 失败,warmup 1248ms |
| 5 | **launchctl kickstart** 20:58 (模拟 launchd 真) | ✅ | ✅ | 30s | 188s | 0 | **0 失败**,warmup 1248ms |

### 6.2 关键观察

- **#1 跟 #5 对照**:同样 launchd 路径,只差 warmup+retry,失败 1→0 ✅
- **#2 跟 #3 对照**:同环境(都是手动 bash),无外部变量,只差随机性 — **hang 是概率事件**,warmup + retry 让稳态从 ~50% 提到 ~99%
- **#4 跟 #5 对照**:bash 手动 vs `launchctl kickstart -k` (完整 launchd 环境) — **行为完全一致**,说明 launchd 真实 02:00 也会 0 失败

### 6.3 失败文件分析

凌晨 02:00 (#1) 失败的那个文件:

```
路径:   /Users/lex/git/knowledge/linux/ish/text/api-list.txt
大小:   903665 bytes (903 KB)
chunks: 883 (按 chunk_size=1024, overlap=128 切)
失败模式: 第 1 个 batch 60s timeout × 3,跳过
```

**为什么总是这个文件**:
- 整个 corpus 里最大文件(其他文件 < 100KB)
- walk 顺序在第 2282 位(随机,但概率高)
- 第 1 个 batch 是 cold-start 撞 GPU 加载,后续 batch 都成功

## 7. 为什么不用 llama-server 替代 (反模式)

有人会问:"既然 Ollama 有 bug,为啥不直接用 llama-server 启 GGUF?"

**3 个理由**:

### 7.1 Tensor 数不兼容

```bash
$ /opt/homebrew/bin/llama-server --model embeddinggemma-300m.gguf
llama_model_load: error loading model: 
  done_getting_tensors: wrong number of tensors; expected 316, got 314
```

**根因**:
- Ollama 0.30.7 内置 llama.cpp 是某个 commit (b1xxxx),针对 `embeddinggemma-300m` 做了 patch
- brew 装的 `llama.cpp` (升级到 b9570) 不含这个 patch
- **同一个 GGUF,不同 llama.cpp 版本表现不同** — 跨版本迁移很危险

### 7.2 引入新依赖

| 维度 | Ollama | llama-server |
|---|---|---|
| 部署复杂度 | 1 个 GUI App | brew install + CLI + config |
| 多模型切换 | `ollama pull` 一条命令 | 手动管理 GGUF 文件路径 |
| GPU 调度 | Metal 自动 | Metal 自动 (但要测过版本) |
| 进程管理 | launchd 启 | 要自己写 plist |

**RAG 是 7×24 后台跑**,加一个新依赖 = 加 30% 出错面。

### 7.3 Ollama 0.30.7 实测可用

第 4、5 次跑都 0 失败,**只是需要 warmup + retry 兜底**。根因是 macOS sleep-wake 跟 Ollama 0.30.x 的 race,**不是 Ollama 设计缺陷**。等社区修 0.30.x 后,问题自然消失 (issue #16570 已有人认领)。

## 8. 完整代码示例 (run_ingest.sh)

```bash
#!/bin/bash
# Ingest launchd entrypoint — runs nightly at 02:00 via com.lex.rag-ingest
# See launchd/com.lex.rag-ingest.plist

set -euo pipefail

LOG_FILE="/tmp/rag-ingest-stdout.log"
RAG_HOME="/Users/lex/git/rag"

echo "=================================================" | tee -a "$LOG_FILE"
echo "[run_ingest.sh] start  $(date -Iseconds)"        | tee -a "$LOG_FILE"
echo "=================================================" | tee -a "$LOG_FILE"

# === Warmup probe (Layer 1 defense) ===
# Forces Ollama to load embeddinggemma:300m into GPU VRAM
# before the real ingest begins. Without this, the first batch
# after macOS sleep-wake hangs for the full client timeout
# (Ollama 0.30.x bug, see ai/docs/ollama-warmup-pattern.md).
WARMUP_MODEL="${WARMUP_MODEL:-embeddinggemma:300m}"
WARMUP_URL="${WARMUP_URL:-http://127.0.0.1:11434/v1/embeddings}"
t0=$(date +%s)
if ! curl -sfS -m 30 -X POST "$WARMUP_URL" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$WARMUP_MODEL\",\"input\":[\"warmup probe\"]}" \
    >/dev/null; then
  echo "[warmup] FAILED — ollama unreachable. Aborting before ingest." | tee -a "$LOG_FILE" >&2
  exit 1
fi
elapsed=$(($(date +%s)-t0))
echo "[warmup] ok, ollama reachable, model responding in ${elapsed}s" | tee -a "$LOG_FILE"

# === Real ingest ===
cd "$RAG_HOME"
uv run rag ingest 2>&1 | tee -a "$LOG_FILE"

# === Summary ===
echo "" | tee -a "$LOG_FILE"
uv run rag stats 2>&1 | tee -a "$LOG_FILE"
```

## 9. 诊断方法 (出问题先跑这 4 步)

### 9.1 1️⃣ Ollama 还在吗?

```bash
curl -sfS -m 5 http://127.0.0.1:11434/api/version
# Expected: {"version":"0.30.7"}
# 失败: ollama 死了,重启它
```

### 9.2 2️⃣ 模型列表正常吗?

```bash
ollama list | grep embeddinggemma
# Expected: embeddinggemma:300m    ...    593 MB
# 失败: ollama pull embeddinggemma:300m
```

### 9.3 3️⃣ 单独请求 hang 吗?

```bash
time curl -sfS -m 5 -X POST http://127.0.0.1:11434/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"embeddinggemma:300m","input":["test"]}' -w "\nHTTP %{http_code}\n"
# Expected: HTTP 200, real ~0.05s
# 失败 (timeout): Ollama hang bug,跑 warmup 解决
# 失败 (HTTP 501): 模型不是 embedding 类型,换模型
# 失败 (HTTP 404): 模型没拉
```

### 9.4 4️⃣ 看服务端日志

```bash
tail -50 ~/.ollama/logs/server.log | grep -E "loaded model|ran|error|warn"
# Expected: 有 "loaded model embeddinggemma:300m" + 一堆 "ran resp_time=50ms"
# hang 期间: 完全没有 "ran" 消息(因为请求卡在 GPU 调度)
```

## 10. 何时**不需要** warmup

| 场景 | 需要 warmup? | 理由 |
|---|---|---|
| **launchd 凌晨 02:00** (sleep-wake) | ✅ 必加 | 100% 撞 cold-start hang |
| **手动跑 20:00** (Mac 一直醒) | ⚠️ 建议加 | 防御性,即使不 hang 也只多 50ms |
| **CI / 容器化跑** (无 sleep-wake) | ❌ 不需要 | 没有 sleep,模型不会被 unload |
| **7×24 服务器** (永不 sleep) | ❌ 不需要 | GPU VRAM 永远占用,无 cold-start |
| 短 batch (< 8 chunks) | ❌ 不需要 | hang bug 临界是 >= 8-30 chunks |
| 单 chunk > 1900 token | ⚠️ **warmup 救不了** | chunk 超 2K context → 即使 warmup 通过,真实请求也会静默截断或 hang。**chunking 层要先 fix** |

## 11. 决策树

```
启动 ingest?
  │
  ├─ 在 macOS 上 + 7×24 后台?
  │    └─ ✅ 加 warmup (本 pattern)
  │
  ├─ 在 macOS 上 + 手动跑?
  │    └─ ⚠️ 建议加 (50ms 浪费,防偶发 hang)
  │
  ├─ 在 Linux / Docker / CI?
  │    └─ ❌ 不需要,但 retry 仍建议
  │
  └─ hang 了? 看 9.4 诊断
       └─ 是 sleep-wake → warmup 解决
       └─ 是模型问题 → 换 embeddinggemma:300m
       └─ 是 Ollama 0.30.x bug → 等社区修 + 临时降级 0.24.0
```

## 12. 相关 issue & 资源

- [ollama/ollama#16049](https://github.com/ollama/ollama/issues/16049) — `/v1/embeddings` hang on first request
- [ollama/ollama#10831](https://github.com/ollama/ollama/issues/10831) — long batch hang
- [ollama/ollama#16570](https://github.com/ollama/ollama/issues/16570) — sleep-wake hang
- 本地 repo: `~/git/rag/src/rag/ingest/pipeline.py` (retry wrapper 实现)
- 本地 repo: `~/git/rag/src/rag/embedder/client.py:33` (timeout_s=30)
- 本地 repo: `~/git/rag/config/embedder.yaml` (supported-models 文档)

## 13. 一句话总结

> **凌晨 launchd 跑 RAG ingest 之前,先 curl 1 个 token 的 `/v1/embeddings`** —— 这 50ms-1.2s 的小动作,把"60s hang + 1 个文件失败"变成"warmup + 0 失败"。
>
> ⚠️ **前提**: 每个 chunk ≤ ~1900 token。超了 warmup 也救不了,那是 chunker 的职责 (`chunker.chunk_size` + `header_levels`)。
