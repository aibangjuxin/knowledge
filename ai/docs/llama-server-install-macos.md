# llama-server 在 macOS 上的安装与升级（Homebrew bottle 坏了，改自编译）

> **一句话结论**
> ★ `brew install llama-server` **不存在**——Homebrew 里这个二进制属于 `llama.cpp` formula。
> 而 `llama.cpp 1.0.0` 的官方 bottle 里，**`llama-server` 是坏的**（`llama-cli` 却能用），
> 根因是 bottle 链接的 ggml **ABI 布局**与 homebrew 的 `ggml` formula **对不上**。
> 可用解法只有一个：**从上游源码自编译**（约 5 分钟），装到 `~/opt/llama.cpp`，
> 再用软链接顶替 Homebrew 的坏版本。

本文所有结论均为 **2026-11-24 在本机（Apple Silicon / macOS / Xcode-beta）实测**，
可用 `otool`/`brew` 命令复现。

---

## 目录

- [1. TL;DR](#1-tldr)
- [2. 症状](#2-症状)
- [3. 根因：ggml ABI 布局对不上](#3-根因ggml-abi-布局对不上)
- [4. 解法：从上游源码编译](#4-解法从上游源码编译)
- [5. 与 Homebrew 共存](#5-与-homebrew-共存)
- [6. 验证](#6-验证)
- [7. 启动参数速查](#7-启动参数速查)
- [8. 以后怎么升级](#8-以后怎么升级)
- [9. 排错表](#9-排错表)
- [10. 交叉引用](#10-交叉引用)

---

## 1. TL;DR

| 项 | 值 |
| :--- | :--- |
| Homebrew 里没有 `llama-server` formula | 用 `llama.cpp`，二进制在 `bin/llama-server` |
| `llama.cpp` 的 brew 最新版 | **1.0.0**（== 上游最新 release v1.0.0，发布于 2026-11-13） |
| `llama-server` 的 bottle 状态 | ❌ **坏的**（`llama-cli` / `llama-bench` 正常） |
| 实际使用版本 | **上游 master 自编译**：`1.0.0-dev (build 1, commit af5c583)` |
| 安装位置 | `~/opt/llama.cpp`（bin + lib + include，34M） |
| 源码位置 | `~/opt/llama.cpp-src`（234M，build 目录已清） |
| PATH 生效方式 | `/opt/homebrew/bin/llama-server` → 软链到 `~/opt/llama.cpp/bin/llama-server` |
| 编译耗时 | 10 核 `-j 10` 约 **3–4 分钟**（clone 约 1 分钟） |

---

## 2. 症状

```bash
$ llama-server --version
dyld[63245]: Library not loaded: @rpath/libllama-server-impl.dylib
  Referenced from: <CEF971CA-...> /opt/homebrew/Cellar/llama.cpp/1.0.0/bin/llama-server
  Reason: tried: '/opt/homebrew/Cellar/llama.cpp/1.0.0/bin/libllama-server-impl.dylib' (no such file)
```

**迷惑点：同一个 bottle 里的其它二进制是好的**——

```bash
$ llama-cli --version
version: 1.0.0 (build 12359, commit b1b770d90)
built with AppleClang 21.0.0.21000401 for Darwin arm64     # ✅ 能跑
```

而且 `llama-cli` 依赖的 `libllama-server-impl.dylib` **文件是存在的**
（在 `/opt/homebrew/Cellar/llama.cpp/1.0.0/lib/` 下），只是 **rpath 指错了目录**。
所以第一反应会以为是「装漏了文件」，其实真正致命的是下面第 3 节那件事。

---

## 3. 根因：ggml ABI 布局对不上

### 3.1 事实：同一个 `llama.cpp` bottle 里，两个二进制的依赖完全不同

```bash
$ otool -L .../llama.cpp/1.0.0/bin/llama-server | awk '/@rpath/{print $1}'
@rpath/libllama-server-impl.dylib
@rpath/libllama-common.1.dylib
@rpath/libmtmd.1.dylib
@rpath/libllama.1.dylib
@rpath/libggml.1.dylib
@rpath/libggml-cpu.1.dylib      ← ← ← 这一批根本不存在
@rpath/libggml-blas.1.dylib     ← ← ←
@rpath/libggml-metal.1.dylib    ← ← ←
@rpath/libggml-rpc.1.dylib      ← ← ←
@rpath/libggml-base.1.dylib

$ otool -L .../llama.cpp/1.0.0/bin/llama-cli | awk '/@rpath/{print $1}'
@rpath/libllama-cli-impl.dylib
@rpath/libllama-common.1.dylib
@rpath/libllama-server-impl.dylib
@rpath/libllama.1.dylib
@rpath/libmtmd.1.dylib          # ← 没有一个 ggml-*，所以它能跑
```

### 3.2 事实：homebrew 的 `ggml` formula 只提供「合并版」dylib

```bash
$ brew list --versions ggml
ggml 0.27.0 1.0.0

$ ls /opt/homebrew/Cellar/ggml/1.0.0/lib/
libggml.1.0.0.dylib  libggml.1.dylib  libggml.dylib
libggml-base.1.0.0.dylib  libggml-base.1.dylib  libggml-base.dylib
# ← 只有 libggml + libggml-base，没有 libggml-cpu / metal / blas / rpc

$ ls /opt/homebrew/Cellar/ggml/1.0.0/libexec/
libggml-blas.so  libggml-cpu-apple_m1.so  libggml-cpu-apple_m2_m3.so
libggml-cpu-apple_m4.so  libggml-metal.so
# ← 后端变成了 .so 插件（运行时 dlopen），不再是链接期依赖的 .dylib
```

### 3.3 结论

| | 期望的（bottle 链接期依赖） | 实际提供的（ggml formula） | 结果 |
| :--- | :--- | :--- | :--- |
| ggml 主库 | `libggml.1.dylib` / `libggml-base.1.dylib` | ✅ 有 | OK |
| ggml 后端 | `libggml-cpu.1.dylib` `libggml-metal.1.dylib` `libggml-blas.1.dylib` `libggml-rpc.1.dylib` | ❌ 只有 `libexec/*.so` 插件 | **dyld 加载失败** |
| rpath | `llama-server` 写的是 `@loader_path`（应为 `@loader_path/../lib`） | dylib 在 `../lib` | **也找不到** |

> 换句话说：**homebrew-core 的 `llama.cpp 1.0.0` bottle 是按 ggml 的「拆分 dylib」布局打的，
> 而同期的 `ggml 1.0.0` formula 已经改成「合并 dylib + .so 插件」布局**，
> 两者对不上 → `llama-server` 起不来。
> `llama-cli` 因为不链接 ggml 后端而幸免于难。

### 3.4 顺带说：老笔记里的画面已经过时

[`llam-server.md`](llam-server.md) 里记的是 ggml **0.10.0** 时代的样子——
那时后端确实是拆分的 `.so`（`libexec/libggml-cpu-apple_m4.so`），
日志里能看到 `load_backend: loaded BLAS backend from .../libexec/libggml-blas.so`。
**1.0.0 之后布局变了**，所以老笔记里的升级命令（`brew upgrade llama-server`）
现在既没有这个 formula、也修不好这个问题。

---

## 4. 解法：从上游源码编译

### 4.1 一次性脚本（可直接复制）

```bash
# 1) 拉源码（master = 最新）
git clone --depth 1 https://github.com/ggml-org/llama.cpp ~/opt/llama.cpp-src
cd ~/opt/llama.cpp-src
git log -1 --format='%H %cd %s'
# af5c58347fdbc2cd19e65b278e81c8f528f8a175 Mon Nov 23 17:12:33 2026 -0800 ...

# 2) 配置（两个参数是必须的，见 4.2）
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_METAL=ON \
  -DLLAMA_CURL=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_UI_GZIP=OFF \
  -DCMAKE_INSTALL_RPATH="@loader_path/../lib"

# 3) 编译（10 核约 3–4 分钟）
cmake --build build --config Release -j 10

# 4) 安装到固定前缀
cmake --install build --prefix ~/opt/llama.cpp
```

### 4.2 两个必须参数（踩过才知道）

| 参数 | 不加会怎样 | 为什么 |
| :--- | :--- | :--- |
| `-DLLAMA_UI_GZIP=OFF` | 构建失败：`CMake Error: Unable to read from file: .../ui-gzip/_gzip/_app/immutable/assets/0.Bk7okzR2.css` | **上游 bug**：`scripts/ui-assets.cmake` 用相对路径调 `file(READ)`，在 macOS 上解析到错误目录。顺带也免去了从 HuggingFace 拉 WebUI 资源（国内网络常常拉不动） |
| `-DCMAKE_INSTALL_RPATH="@loader_path/../lib"` | 装完直接跑会报 `no LC_RPATH's found` | CMake 安装时默认**清空** rpath；必须显式指定 `@loader_path/../lib`（二进制在 `bin/`，dylib 在 `lib/`） |

### 4.3 `-DLLAMA_CURL=OFF` 的代价

关闭 curl 后 **`llama-server` 没有内置模型下载能力**（`-hf user/repo` 会不可用）。
拉模型请另用 `huggingface-cli` / `ollama` 那套，或直接把本地 `.gguf` 指过去。

### 4.4 装完长这样

```
~/opt/llama.cpp/
├── bin/     llama-server  llama-cli  llama-bench  llama-quantize  llama-embedding ... (+ 全部 dylib)
├── lib/     libllama*.dylib  libggml*.dylib
└── include/
```

---

## 5. 与 Homebrew 共存

Homebrew 的 keg **不卸载**，只是「摘掉软链接」，随时能切回去：

```bash
# 摘掉 brew 的（63 个软链接；brew 的 llama-server 是坏的）
brew unlink llama.cpp

# 把自编译的软链到 PATH 里（/opt/homebrew/bin 在 PATH 靠前）
for f in ~/opt/llama.cpp/bin/*; do
  case "$f" in *.dylib) continue;; esac
  b=$(basename "$f")
  [ -x "$f" ] && ln -sf "$f" "/opt/homebrew/bin/$b"
done

# 切回 brew 版本（注意：llama-server 仍然是坏的）
brew link llama.cpp
```

```bash
$ which llama-server
/opt/homebrew/bin/llama-server
$ ls -l /opt/homebrew/bin/llama-server
lrwxr-xr-x ... /opt/homebrew/bin/llama-server -> /Users/lex/opt/llama.cpp/bin/llama-server
```

---

## 6. 验证

```bash
$ llama-server --version
version: 1.0.0-dev (build 1, commit af5c583)
built with AppleClang 21.0.0.21000320 for Darwin arm64

$ llama-server -m ~/models/unsloth/gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf \
      --host 127.0.0.1 --port 8099 -ngl 99 -c 4096 &
...
srv  load_model: initializing, n_slots = 4, n_ctx_slot = 4096, kv_unified = 'true'
srv  server_run_i: model loaded
srv  server_on_li: listening on http://127.0.0.1:8099

$ curl -s http://127.0.0.1:8099/health
{"status":"ok"}

$ curl -s http://127.0.0.1:8099/v1/models | python3 -m json.tool | head -8
{"models": [{"name": ".../gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf", "type": "model", ...}]}

$ curl -s http://127.0.0.1:8099/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"Say hi in 3 words"}],"max_tokens":32,"temperature":0}'
{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Hello, how are you?"}}],
 "usage":{"completion_tokens":7,"prompt_tokens":22,"total_tokens":29},
 "system_fingerprint":"b1-af5c583"}
```

**实测性能**（gemma-4-E4B QAT UD-Q4_K_XL，Metal 全量卸载）：

```
eval time = 183.78 ms / 7 tokens (30.63 ms per token, 32.65 tokens per second)
graphs reused = 68        graph reallocs = 0
```

---

## 7. 启动参数速查

| 参数 | 说明 | 实测/建议 |
| :--- | :--- | :--- |
| `-m /path/model.gguf` | 模型路径（必填） | 本地 GGUF；无内置下载（curl 已关） |
| `--host 127.0.0.1` | 监听地址 | **别用 0.0.0.0**，OpenAI 兼容接口无鉴权 |
| `--port 8099` | 端口 | 默认 8080 |
| `-ngl 99` | 卸载到 Metal 的层数 | Apple Silicon 必开；99 = 全部 |
| `-c 4096` | **总**上下文长度 | 会切成 `n_slots` 份；`-c 4096` → 4 slots × 1024（`n_ctx_slot`） |
| `-np 1` | 并行 slot 数 | 默认 4；并发高时调大 |
| `--jinja` | 用模型自带 chat template | 换模型时经常需要 |
| `--api-key` | 给 OpenAI 兼容接口加 key | 本地也要加的话用这个 |

> ⚠️ `-c` 是**总**上下文，不是每个 slot 的。
> 想要「4 路并发 × 8192 上下文」，要写 `-c 32768`。

---

## 8. 以后怎么升级

master 一直在动，想跟最新版就三步：

```bash
cd ~/opt/llama.cpp-src
git pull --depth 1                 # 或 git fetch --depth 1 && git reset --hard origin/master
cmake --build build --config Release -j 10
cmake --install build --prefix ~/opt/llama.cpp
llama-server --version              # 确认 commit 变了
```

软链接已经指向 `~/opt/llama.cpp/bin/`，**装完即生效，不用再 link**。

如果上游改了 dylib 布局，可能还要补 `-DCMAKE_INSTALL_RPATH`——保险起见可以把这句固化在 configure 里：

```bash
cmake -B build -DCMAKE_INSTALL_RPATH="@loader_path/../lib" ...
```

---

## 9. 排错表

| 现象 | 原因 | 处理 |
| :--- | :--- | :--- |
| `dyld: Library not loaded: @rpath/libllama-server-impl.dylib` | brew bottle 的 rpath 只有 `@loader_path` | 用自编译版；或 `install_name_tool -add_rpath @loader_path/../lib` 修 rpath |
| `dyld: Library not loaded: @rpath/libggml-cpu.1.dylib` | bottle 依赖已不存在的 ggml 拆分 dylib | **必须自编译**，无法靠改 rpath 解决 |
| `no LC_RPATH's found` | `cmake --install` 清空了 rpath | 加 `-DCMAKE_INSTALL_RPATH="@loader_path/../lib"` |
| `UI: file failed to compress: .../0.Bk7okzR2.css` | 上游 UI 资源脚本的相对路径 bug | 加 `-DLLAMA_UI_GZIP=OFF` |
| `UI: download dist.tar.gz.sha256 from b1 failed` | HuggingFace 拉不到 UI 资源 | 同上（关掉 GZIP 就不会去拉） |
| `brew: No available formula with the name "llama-server"` | 本来就没有这个 formula | 用 `llama.cpp` |
| `llama-cli` 正常但 `llama-server` 崩 | 两者依赖不同（见 §3） | 同上，自编译 |
| 端口被占用 | 上一次没退干净 | `pkill -f 'llama-server -m'` |
| 中文提问返回空 content | 多半是模型把内容写进了 reasoning 字段 | 换 `--jinja` 或看 `reasoning_content` 字段 |

---

## 10. 交叉引用

| 场景 | 文档 |
| :--- | :--- |
| llama.cpp / llama-server 早期笔记（ggml 0.10.0 时代，布局已变） | [llam-server.md](llam-server.md) |
| Ollama 综合使用 | [ollama.md](ollama.md) |
| Ollama 排错 | [debug-ollama.md](debug-ollama.md) |
| Embedding 冷启动 hang 的 warmup 防御 | [ollama-warmup-pattern.md](ollama-warmup-pattern.md) |
| Embedder batch_size 调优 | [embedder-batch-size-tuning.md](embedder-batch-size-tuning.md) |
| OCR（本地 GGUF 多模态） | [Python-ocr.md](Python-ocr.md) |

**官方链接**：

- llama.cpp 源码：https://github.com/ggml-org/llama.cpp
- release（bXXXX 编号 / 语义化版本）：https://github.com/ggml-org/llama.cpp/releases
- 构建文档：https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md
- server 文档：https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- Homebrew formula：https://github.com/Homebrew/homebrew-core/blob/master/Formula/l/llama.cpp.rb
- ggml formula：https://github.com/Homebrew/homebrew-core/blob/master/Formula/g/ggml.rb
