# Chunk / Batch / Context-Window 关系探索 — embeddinggemma 2K 视角

> **本文不动任何代码**,只探索三个参数之间的关系,并用具体文件大小举例。
> 配套文档: `ollama-warmup-pattern.md`、`embedder-batch-size-tuning.md`。
> 数据基础: `~/git/rag/scripts/probe_chunk_tokens.py`(实测 4422 文件 / 51416 chunks)。

## 1. 一句话核心

> **Chunk 是文件的"片段",Batch 是请求的"打包",Context window 是每个片段的"天花板"。三者独立,不要混为一谈。**

| 名字 | 是什么 | 在哪里设 | 量级 |
|---|---|---|---|
| **Context window** | 模型一次能处理多少 token | 模型决定 (embeddinggemma:300m = 2048) | 2K tokens |
| **Chunk** | 文件被切成的片段 | `chunker.chunk_size` (rag.yaml:73) | 几百~上千 tokens |
| **Batch size** | 一次 HTTP 请求送多少 chunks | `embedder.batch_size` (rag.yaml:31) | 16~48 chunks |
| **Embedding dim** | 每个 chunk 输出向量的维度 | `embedder.dim` (rag.yaml:30) | 768 维 |

## 2. 三个常见误解澄清

### 误解 1: "batch_size × chunk_token = 文件大小"

**错**。真实公式分两步:

```
chunks_per_file  = ceil(file_tokens / (chunk_size - overlap))   ← 第一步:切多少块
requests_per_file = ceil(chunks_per_file / batch_size)          ← 第二步:分多少请求
```

`batch_size` 不参与"把文件切成多少 chunk",**它只决定一次请求塞多少个 chunk**。

### 误解 2: "context window 限制整个请求"

**错**。Context window 是 **per-chunk**(per-input)限制,**不是 per-request**。一次请求送 32 个 chunks,每个 chunk 各自 ≤2048 tokens 是合法的;Ollama 内部逐个 chunk 编码,互不影响。

### 误解 3: "chunk_size 设大点能减少请求数"

**部分对,但有上限**。`chunk_size` 上限是 2048(`embeddinggemma`),而且实际安全上限是 ~1900(留 150 给 BOS/EOS)。chunk_size=2048 是 **危险的**:chunker 切出的 chunk 加上 128 overlap = **2176 tokens,撞 context ceiling**。

## 3. 公式与变量关系图

```
                          ┌─────────────────────────────────────────┐
                          │   文件 (File)                            │
                          │   100 KB English ≈ 25,000 tokens         │
                          │   100 KB Chinese  ≈ 50,000 tokens       │
                          └────────────────┬────────────────────────┘
                                           │
                          ┌────────────────▼────────────────────────┐
                          │   Chunker (rag.yaml:73)                  │
                          │   chunk_size=1024, overlap=128           │
                          │   ────────────────────                   │
                          │   chunks = ceil(25000 / 896) = 28       │
                          └────────────────┬────────────────────────┘
                                           │
                              ┌────────────▼────────────┐
                              │  28 chunks (1152 tok ea)│
                              └────────────┬────────────┘
                                           │
                          ┌────────────────▼────────────────────────┐
                          │   Embedder (rag.yaml:31)                 │
                          │   batch_size=32                          │
                          │   ────────────────────                   │
                          │   requests = ceil(28 / 32) = 1          │
                          └────────────────┬────────────────────────┘
                                           │
                              ┌────────────▼────────────┐
                              │   1 HTTP request to     │
                              │   /v1/embeddings        │
                              └────────────┬────────────┘
                                           │
                          ┌────────────────▼────────────────────────┐
                          │   Ollama 0.30.7                          │
                          │   per-chunk encode (max 2048 tok each)   │
                          │   ────────────────────                   │
                          │   28 × 768-dim vectors                   │
                          └─────────────────────────────────────────┘
```

## 4. 关系矩阵: 参数影响哪个?

| 你调这个参数 ↓ | 影响 ↓ | 跟 2K context 关系 |
|---|---|---|
| `chunker.chunk_size` | **每 chunk 的 token 上限** | 直接相关:chunk_size + overlap ≤ 1900 |
| `chunker.chunk_overlap` | 跟上面一起决定 chunk 最大 token | 直接相加 |
| `embedder.batch_size` | **每 HTTP 请求塞几个 chunks** | **不相关**(per-chunk 不是 per-batch) |
| `embedder.dim` | 输出向量维度 | 不相关(只影响存储) |
| `chunker.header_levels` | 切分粒度 (markdown H1/H2/H3) | 间接:层级多 → 单 chunk 越长 → 易撞墙 |
| `chunker.min_chunk_size` | 最小 chunk token | 不相关 |

## 5. 具体例子: 不同文件大小 + 不同配置

> **下面的表用 `probe_chunk_tokens.py` 同样的公式实时算出**,数字可直接复现。
>
> 公式:`chunks = ceil(file_tokens / (chunk_size - overlap))`
> `requests = ceil(chunks / batch_size)`
>
> 假设英文 1 token ≈ 4 chars,中文 1 token ≈ 2 chars。

### 5.1 全景对照表(同一文件,不同 chunk_size / batch_size 组合)

| 文件 (字节 / tokens) | cs=512/ov=64/bs=16 | cs=1024/ov=128/bs=32 **(PROD)** | cs=1024/ov=128/bs=40 **(probe)** | cs=2048/ov=128/bs=32 🔴 |
|---|---|---|---|---|
| **10 KB** (2500EN / 5000ZH) | ✅ 6ch / 1req | ✅ 3ch / 1req | ✅ 3ch / 1req | 🔴 2ch / 1req |
| **100 KB** (25K EN / 50K ZH) | ✅ 56ch / 4req | ✅ **28ch / 1req** | ✅ 28ch / 1req | 🔴 14ch / 1req |
| **200 KB** (50K EN / 100K ZH) | ✅ 112ch / 7req | ✅ 56ch / 2req | ✅ 56ch / 2req | 🔴 27ch / 1req |
| **500 KB** (125K EN / 250K ZH) | ✅ 280ch / 18req | ✅ 140ch / 5req | ✅ 140ch / 4req | 🔴 66ch / 3req |
| **1 MB max** (262K EN / 524K ZH) | ✅ 586ch / 37req | ✅ 293ch / 10req | ✅ 293ch / 8req | 🔴 137ch / 5req |

🔴 = 撞墙(`chunk_size + overlap > 2048`,会触发 2K context 截断)
🟡 = 警告(接近 1900 安全线)
✅ = 健康(远低于 1900)

### 5.2 你问的 100 KB 文件详解

```
文件: 100 KB 英文 markdown
≈ 25,000 tokens (英文 1 token ≈ 4 chars)
生产配置: chunk_size=1024, overlap=128, batch_size=32
─────────────────────────────────────────────────
chunks  = ceil(25000 / (1024-128)) = ceil(25000/896) = 28
requests = ceil(28 / 32) = 1   ← 一次 HTTP 请求就够!
每个 chunk: 1024 token 上限 + 128 overlap = 1152 token < 1900 ✅
```

**关键洞察**:100 KB / 生产配置 = **28 chunks / 1 request**。这是非常舒服的状态:
- 单 chunk (1152 token) 距 1900 安全线还有 **39% 余量**- 整个文件 1 个 HTTP 请求就搞定,没有 hang bug 风险
- 单 chunk 切分粒度合适(每块 ~1024 token,适合后续 retrieval)

### 5.3 你问的 200 KB 文件详解

```
文件: 200 KB 英文 markdown
≈ 50,000 tokens
生产配置: chunk_size=1024, overlap=128, batch_size=32
─────────────────────────────────────────────────
chunks  = ceil(50000 / 896) = 56
requests = ceil(56 / 32) = 2
每个 chunk: 1152 token < 1900 ✅
```

**200 KB 怎么处理?两种方案对比**:

| 方案 | chunks | requests | per-batch 压力 | 适用场景 |
|---|---|---|---|---|
| **A. 保持 cs=1024** | 56 | 2 | 32 + 24 chunks | ✅ 当前生产配置,够用 |
| **B. 改 cs=2048** | 27 | 1 | 27 chunks | 🔴 撞 2K wall,embedding 退化,不要 |
| **C. 改 cs=768** | 67 | 3 | 32 + 32 + 3 | 适合需要更细检索粒度的代码文件 |

**推荐:方案 A 不动**。56 chunks / 2 requests 完全在健康区。

### 5.4 中文文件的"双倍压力"

中文 1 token ≈ 2 chars,**同样字节数,token 数是英文的 ~2 倍**。

```
文件: 100 KB 中文 markdown
≈ 50,000 tokens (vs 英文 25,000)
生产配置不变:
─────────────────────────────────────────────────
chunks  = ceil(50000 / 896) = 56
requests = ceil(56 / 32) = 2
每个 chunk: 1152 token < 1900 ✅
```

**100 KB 中文 ≈ 200 KB 英文的工作量**。如果你的 corpus 中文占比高,`files_total` 看上去不大,但实际 embedding 计算量翻倍。这就是为什么凌晨 02:00 launchd 任务有时长波动。

## 6. 边界条件 — 何时会出问题?

### 6.1 什么情况下 chunk 会真的超过 1900?

我们用 `scripts/probe_chunk_tokens.py` 实测当前 corpus (4422 文件):

| chunk_size | 实测 max chunk tokens | chunks >1900 (safe) | chunks >2048 (HARD) |
|---|---|---|---|
| **1024 (PROD)** | **1024** | 0 | 0 |
| **2048 (auto_tune 候选)** | **2048** | **2236 (4.74%)** | 0 |

**结论**: 当前生产配置下,**chunker 的两重保险**(`if body_tokens <= chunk_size: return single` + `end = min(idx + chunk_size, len(tokens))`)严格把单 chunk 限制在 chunk_size 以内。

**真正的危险**是 chunk_size 超过 **1772**(`1772 + 128 = 1900` 正好贴安全线),任何 chunk_size ≥ 1773 + overlap=128 = ≥1901 token 就会进入"危险带":

| chunk_size | + overlap 128 | 距 1900 安全线 | 状态 |
|---|---|---|---|
| 1024 (PROD) | 1152 | -748 (39% 余量) | ✅✅✅ |
| 1536 | 1664 | -236 (12% 余量) | ✅ |
| 1664 | 1792 | -108 (6% 余量) | ✅ 紧 |
| **1772** | **1900** | **0** | ⚠️ 贴线 |
| **1773** | **1901** | **+1** | 🟡 进入危险带 |
| **1920** | **2048** | **+148** | 🔴 撞 HARD ceiling |

### 6.2 单一文件过大导致 requests_per_file 暴涨

| 文件大小 | chunks (cs=1024) | requests (bs=32) | 风险 |
|---|---|---|---|
| 100 KB | 28 | 1 | 无 |
| 200 KB | 56 | 2 | 无 |
| 500 KB | 140 | 5 | 注意 |
| 1 MB | 293 | **10** | ⚠️ 长 batch hang 概率上升 (issue #10831) |
| 1.5 MB (超 walker 限制) | 439 | 14 | 🔴 `sources.yaml` max_file_size_bytes=1MB 直接拒绝 |

**1 MB 是 walker 硬上限**(`sources.yaml:36`)。超过 1 MB 的文件根本不会进入 ingest 流程,不需要担心。

## 7. 一张表总结所有参数(你提到的"最终参数表")

| 参数 | 含义 | 当前值 (PROD) | 取值范围 | 跟 2K context 关系 |
|---|---|---|---|---|
| **chunk_size** | 单 chunk 的 token 上限 | **1024** | 256~1900 | 加 overlap ≤ 1900 |
| **chunk_overlap** | 相邻 chunk 共享 token | **128** | 0~chunk_size/2 | 跟 chunk_size 相加 ≤ 1900 |
| **batch_size** | 每 HTTP 请求的 chunks 数 | **32** (→40 推荐) | 8~128 | **不相关** (per-chunk 不是 per-batch) |
| **embedding_dim** | 输出向量维度 | **768** | 模型固定 | 不相关 |
| **max_chunk_size_safe** | 安全 chunk_token 上限 | **1900** | - | 2048 - 150 (BOS/EOS) |
| **context_window** | 模型硬上限 | **2048** | 模型固定 | - |
| **fit_chunks** | 单 chunk 能装多少 tokens | 1024 | ≤ chunk_size | 必须 ≤ 1900 |
| **fit_batches** | 一次请求能装多少 chunks | 32 (→40) | 无硬上限 | 不相关 |

## 8. 决策树:给一个新文件选配置

```
新文件 / 新 corpus 进来?
  │
  ├─ 文件 < 200 KB?
  │    └─ ✅ 当前生产配置 (cs=1024/bs=32) 完全够用,不动
  │
  ├─ 文件 200 KB ~ 500 KB?
  │    └─ 当前配置还够 (5 requests 以内)
  │       但考虑:
  │       - 中文 corpus? → token 数翻倍,实测再决定
  │       - 高频更新? → bs 调到 40 省 3% 时间 (probe_embedder_batch.py)
  │
  ├─ 文件 500 KB ~ 1 MB?
  │    └─ ⚠️ 请求数 5~10,hang 概率开始上升
  │       选项:
  │       a) 保持 cs=1024,接受 5-10 requests
  │       b) 拆分文件 (业务层,不在 RAG 范围)
  │       c) cs 调到 1536 (1664+128=1792 < 1900 安全) ← 折中
  │
  └─ 文件 > 1 MB?
       └─ 🔴 walker 拒绝,sources.yaml max_file_size_bytes 兜底
          不会进 ingest,无需配 RAG
```

## 9. 实操清单:改配置前先跑这两个脚本

```bash
# 1. 评估 corpus 现有 token 分布 (5-10s)
cd ~/git/rag && uv run python scripts/probe_chunk_tokens.py

# 2. 评估新 batch_size 是否更快 (30s ~ 2min)
cd ~/git/rag && uv run python scripts/probe_embedder_batch.py --sizes 32 40 48

# 3. 模拟调到 2048 chunk_size 看看会怎样 (5-10s)
cd ~/git/rag && uv run python scripts/probe_chunk_tokens.py --chunk-size 2048
```

第三步的输出会直接告诉你:**如果改 cs=2048,会新增多少个 >1900 token 的 chunk**。这就是 `auto_tune_loop.py` 应该内置的安全检查。

## 10. 一句话总结

> **Context window 限制 chunk,batch_size 不受限**;**chunk_size + overlap ≤ 1900** 是唯一硬约束;**生产配置 `cs=1024/ov=128/bs=32` 对 ≤200KB 文件完全够用**;**真正的扩展点在 500KB~1MB 文件的 hang 风险**,而不是 chunk_size。

---

*作者: Lex · 数据: `probe_chunk_tokens.py` 4422 文件实测 + 公式推导 · 不修改任何代码逻辑*
*最后更新: 2026-06-10*