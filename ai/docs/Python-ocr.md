- /Users/lex/git/knowledge/ai/ocr-ollama-3.py 目前这个最稳定
- /Users/lex/git/knowledge/ai/last.py 可用了
- /Users/lex/python/openai/bin/python3 /Users/lex/git/knowledge/ai/last.py 1.png
/Users/lex/.local/bin/ocr

```bash
#!/usr/bin/env bash
set -euo pipefail

SWIFT_SCRIPT="/Users/lex/git/knowledge/ios/ocr/main.swift"
DEFAULT_PATH="/Users/lex/Downloads"

usage() {
  echo "Usage: orc [image-path-or-directory]" >&2
  echo "Defaults to: ${DEFAULT_PATH}" >&2
}

resolve_latest_image() {
  local dir="$1"

  find "$dir" -maxdepth 1 -type f \
    \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o \
       -iname "*.webp" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.bmp" -o \
       -iname "*.gif" \) \
    -exec stat -f '%m %N' {} \; | sort -nr | head -n 1 | cut -d' ' -f2-
}

if [[ $# -gt 1 ]]; then
  usage
  exit 2
fi

if [[ $# -eq 0 ]]; then
  TARGET="${DEFAULT_PATH}"
elif [[ "$1" = /* ]]; then
  TARGET="$1"
else
  TARGET="${DEFAULT_PATH}/$1"
fi

if [[ ! -f "${SWIFT_SCRIPT}" ]]; then
  echo "Error: swift script not found: ${SWIFT_SCRIPT}" >&2
  exit 1
fi

if [[ -d "${TARGET}" ]]; then
  IMG="$(resolve_latest_image "${TARGET}")"
  if [[ -z "${IMG}" ]]; then
    echo "Error: no image files found in directory: ${TARGET}" >&2
    exit 1
  fi
else
  IMG="${TARGET}"
fi

if [[ ! -f "${IMG}" ]]; then
  echo "Error: image not found: ${IMG}" >&2
  exit 1
fi

exec /usr/bin/swift "${SWIFT_SCRIPT}" "${IMG}"
```
- add a new ocrp
```bash
#!/usr/bin/env bash
set -euo pipefail

PYTHON_BIN="/Users/lex/python/openai/bin/python3"
PY_SCRIPT="/Users/lex/git/knowledge/ai/trubo.py"
DEFAULT_PATH="/Users/lex/Downloads"

usage() {
  echo "Usage: ocrp [image-path-or-directory]" >&2
  echo "Defaults to: ${DEFAULT_PATH}" >&2
}

resolve_latest_image() {
  local dir="$1"

  find "$dir" -maxdepth 1 -type f \
    \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o \
       -iname "*.webp" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.bmp" -o \
       -iname "*.gif" \) \
    -exec stat -f '%m %N' {} \; | sort -nr | head -n 1 | cut -d' ' -f2-
}

if [[ $# -gt 1 ]]; then
  usage
  exit 2
fi

if [[ $# -eq 0 ]]; then
  TARGET="${DEFAULT_PATH}"
elif [[ "$1" = /* ]]; then
  TARGET="$1"
else
  TARGET="${DEFAULT_PATH}/$1"
fi

if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "Error: python executable not found: ${PYTHON_BIN}" >&2
  exit 1
fi

if [[ ! -f "${PY_SCRIPT}" ]]; then
  echo "Error: python script not found: ${PY_SCRIPT}" >&2
  exit 1
fi

if [[ -d "${TARGET}" ]]; then
  IMG="$(resolve_latest_image "${TARGET}")"
  if [[ -z "${IMG}" ]]; then
    echo "Error: no image files found in directory: ${TARGET}" >&2
    exit 1
  fi
else
  IMG="${TARGET}"
fi

if [[ ! -f "${IMG}" ]]; then
  echo "Error: image not found: ${IMG}" >&2
  exit 1
fi

exec "${PYTHON_BIN}" "${PY_SCRIPT}" "${IMG}"
```



- pwd
/Users/lex/python 
- 创建一个虚拟环境
➜  python python3 -m venv openai
- source 
➜  python source /Users/lex/python/openai/bin/activate

(openai) ➜  python python3 -m pip install openai
Collecting openai
  Downloading openai-2.29.0-py3-none-any.whl.metadata (29 kB)
Collecting anyio<5,>=3.5.0 (from openai)
  Downloading anyio-4.12.1-py3-none-any.whl.metadata (4.3 kB)
Collecting distro<2,>=1.7.0 (from openai)
  Downloading distro-1.9.0-py3-none-any.whl.metadata (6.8 kB)
Collecting httpx<1,>=0.23.0 (from openai)
[notice] A new release of pip is available: 25.3 -> 26.0.1
[notice] To update, run: pip install --upgrade pip
(openai) ➜  python  pip install --upgrade pip
Requirement already satisfied: pip in ./openai/lib/python3.14/site-packages (25.3)
Collecting pip
  Using cached pip-26.0.1-py3-none-any.whl.metadata (4.7 kB)
Using cached pip-26.0.1-py3-none-any.whl (1.8 MB)
Installing collected packages: pip
  Attempting uninstall: pip
    Found existing installation: pip 25.3
    Uninstalling pip-25.3:
      Successfully uninstalled pip-25.3
Successfully installed pip-26.0.1


python3 -m pip install openai requests

(openai) ➜  bin pwd
/Users/lex/python/openai/bin
(openai) ➜  bin ls
 activate       activate.fish   distro   openai   pip3      python    python3.14   𝜋thon
 activate.csh   Activate.ps1    httpx    pip      pip3.14   python3   tqdm


/Users/lex/python/openai/bin/python3 /Users/lex/git/knowledge/ai/ocr_analyze.py /Users/lex/Downloads/33.png


```python
#!/Users/lex/python/openai/bin/python3
import base64
import requests

image_path = "1.png"

with open(image_path, "rb") as f:
    img_bytes = f.read()

img_b64 = base64.b64encode(img_bytes).decode("utf-8")

url = "http://localhost:11434/api/chat"   # Ollama 原生 chat 接口[web:13]

payload = {
    "model": "MedAIBase/PaddleOCR-VL:0.9b",    # 模型名[web:11][web:12]
    "messages": [
        {
            "role": "user",
            "content": "请先做 OCR，把图片中所有文字按自然阅读顺序抄写出来；然后用中文总结 3 点要点。"
        }
    ],
    "images": [img_b64],   # 关键：图像 base64 数组[web:16]
    "stream": False
}

resp = requests.post(url, json=payload)
resp.raise_for_status()
data = resp.json()
print(data["message"]["content"])
```
- how to debug 
```bash
curl -X POST http://localhost:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.5:0.8b",
    "messages": [
      {"role": "user", "content": "说一句你好"}
    ],
    "stream": false
  }'
```


ollama run glm-ocr
ollama run glm-ocr Text Recognition: /Users/lex/Downloads/33.png


/Users/lex/python/openai/bin/pip install ollama


# 绝对路径
python3 ocr_ollama.py /Users/lex/Downloads/33.png

# 仅文件名，自动在 ~/Downloads 查找
python3 ocr_ollama.py 33.png

# 无参数，交互式选图
python3 ocr_ollama.py


# 基础使用（两阶段完整流程）
python3 ocr-ollama-enhance.py 1.png

# 仅 OCR，跳过 AI 增强
python3 ocr-ollama-enhance.py 1.png --no-enhance

# 结果保存到 output/ 目录下的 .md 文件
python3 ocr-ollama-enhance.py 1.png --save

# 换用 mistral 做增强
python3 ocr-ollama-enhance.py 1.png --model mistral

# 查看原始 OCR 不做任何处理
python3 ocr-ollama-enhance.py 1.png --raw-only

# 查看帮助
python3 ocr-ollama-enhance.py --help


对于现在的单张图片处理流程，**纯粹从 Python 并发（多线程/协程）的角度来说，提升非常有限**。原因是我们的流程是严格**串行**的：必须等 Stage 1（OCR）出结果，才能交给 Stage 2（AI 增强）。在跑模型的时候，Python 脚本只是在干等（I/O 阻塞），真正的计算瓶颈在 Ollama 后台。

但这并不代表从脚本层面没有能榨取的速度空间了。我们可以通过以下 **3 个层面** 进一步逼出速度极限：

### 1. 脚本级：优化 Ollama 的调用参数（极其关键）
你可以在调用 `client.chat()` 时增加几项专门用于提速的关键参数：

*   **`keep_alive="10m"` （常驻内存，告别冷启动）**
    默认情况下，如果你闲置了一会儿，Ollama 会把模型从显存/内存卸载。下次运行该脚本时会卡顿几秒钟重新加载模型。加上这个参数能让连续处理时“秒开”。
*   **压缩上下文窗口 (`num_ctx`)**
    如果文本不长，可以强制缩短 `num_ctx`（比如 2048 或 4096），可以节省模型分配资源的时间。
*   **手动拉满 CPU 线程 (`num_thread`)**
    如果你的模型主要是靠 CPU 在推理（而不是 Mac 的 GPU），可以强制分配最大核心数。

**改法示例**（在 [stage1_ocr](cci:1://file:///Users/lex/git/knowledge/ai/ocr-ollama-chatgpt.py:171:0-206:35) 和 [stage2_enhance](cci:1://file:///Users/lex/git/knowledge/ai/ocr-ollama-chatgpt.py:209:0-246:23) 当中）：
```python
response = client.chat(
    model=OCR_MODEL,
    messages=[...],
    options=ollama.Options(
        temperature=0.05, 
        top_p=0.9,
        num_ctx=4096,     # 压缩上下文分配
        num_thread=8      # 根据你的 Mac 核心数来填，比如 8 
    ),
    keep_alive="10m"      # 跑完后模型在显存中保留 10 分钟
)
```

### 2. 架构级：如果要在未来处理多张图（这时候并发就发威了）
虽然单图处理无法并发，但你以后如果要传整个文件夹（比如 `--batch ./images`），Python 的 `asyncio` 就可以大显身手了。

目前 Ollama Python 提供了异步客户端：
```python
import asyncio
from ollama import AsyncClient

async def process_batch(images):
    client = AsyncClient(host=OLLAMA_HOST)
    # 瞬间把 5 张图同时发给 Ollama 提取，而不是一张一张等
    tasks = [stage1_async(client, img) for img in images]
    results = await asyncio.gather(*tasks)
```
*前提是你的电脑内存和显存足够跑起 Ollama 的并发请求。*

### 3. I/O 和启动优化：懒加载库（目前已部分实现）
Python 的一个痛点是引入大体积的库（特别是包含 C 模块的包）非常耗时。你可能没注意到，我们在之前版本的脚本里用了 **懒加载**：
```python
def _get_client():
    import ollama  # 只在真正开始执行到 OCR 时才 import
    ...
```
这样做是因为我们在进入 Python 时会先提示你选图片。如果把 `import ollama` 放在文件最上面，你敲下回车后终端会卡顿半秒到一秒才输出目录让你选。通过**懒加载**，用户交互可以实现真正的“0延迟启动”。脚本里还可以把 `import json`、`import re` 这种尽量往后挪，继续削减前置启动时间。

---

**总结建议**：
如果只是为了处理**单张图更快**，建议尝试加入 `keep_alive="15m"` 和 `num_ctx=4096`。
如果是觉得 `qwen3.5:0.8b` 的生成**依然粘手**，那么从 Python 层面的上限就到这了，剩余的优化空间只能是在硬件侧（确保 Ollama 真的跑上了 Metal GPU）或寻找更小的 100M 级别专用大模型了。需要帮你把参数调优写入脚本吗？



# claude enhance 

(openai) ➜  ai git:(main) ✗ pip install uvloop
Collecting uvloop
  Downloading uvloop-0.22.1-cp314-cp314-macosx_10_13_universal2.whl.metadata (4.9 kB)
Downloading uvloop-0.22.1-cp314-cp314-macosx_10_13_universal2.whl (1.4 MB)
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 1.4/1.4 MB 6.9 MB/s  0:00:00
Installing collected packages: uvloop
Successfully installed uvloop-0.22.1
## 问题分析

当前脚本已经用了 `asyncio` + `asyncio.gather` 做并发，但还有几个可以提速的点：

1. **图片读取是同步 I/O** — `open(image_path, "rb")` 在异步函数里阻塞事件循环
2. **批量处理没有并发限制** — 大文件夹会把所有请求同时打出去，实际上会因为 Ollama 排队反而更慢
3. **`asyncio.run()` 每次创建新事件循环** — 单图模式下无影响，但可以用 `uvloop` 替换默认事件循环，底层用 libuv 提速 30-50%
4. **规则处理是纯 CPU 密集** — 可以用 `ProcessPoolExecutor` 并行处理多张图的规则格式化
5. **图片文件读取可以用 `aiofiles`** — 真正异步 I/O，不阻塞事件循环

核心提速策略：

| 优化点       | 原来            | 优化后                | 预期收益       |
| ------------ | --------------- | --------------------- | -------------- |
| 事件循环     | `asyncio` 默认  | `uvloop`              | ~30-50%        |
| 图片读取     | 同步 `open()`   | `aiofiles` 异步       | 并发时显著     |
| 批量并发控制 | 无限制 `gather` | `Semaphore` 限流      | 防 Ollama 排队 |
| 规则格式化   | 串行            | `ProcessPoolExecutor` | CPU 多核利用   | ## 四个提速改动说明 |

### 提速 #1 — `uvloop`（全局生效）

```bash
pip install uvloop
```

替换 Python 默认事件循环为 libuv 实现，异步 I/O 吞吐提升 **30-50%**，对 Ollama 的 HTTP 长连接效果最明显。缺包时自动降级，不影响运行。

---

### 提速 #2 — `aiofiles`（图片读取）

```bash
pip install aiofiles
```

原来 `open(image_path, "rb")` 是同步阻塞调用，在批量并发时会卡住整个事件循环。改为 `aiofiles.open()` 后真正异步，缺包时自动降级为线程池包装的同步读取（至少不再直接阻塞）。

---

### 提速 #3 — `asyncio.Semaphore`（批量限流）

```python
BATCH_CONCURRENCY = 4  # 可通过环境变量调整
```

原来 `asyncio.gather(*全部任务)` 会把所有请求同时打给 Ollama，Ollama 内部反而串行排队。加了令牌桶后，**同时最多 N 个请求在飞**，实测比无限并发更快。可以通过 `BATCH_CONCURRENCY=8` 按你的硬件调整。

---

### 提速 #4 — `ProcessPoolExecutor`（规则格式化）

`rule_based_format` 里有 `json.loads` + `re.search`，是 CPU 密集型操作。批量处理时把它扔进进程池并行跑，多核全部利用（单图模式下数据量小，直接同步调用，避免进程池启动开销得不偿失）。


ocr-trubo.py 为了提速引入了 AsyncClient + aiofiles + uvloop + 并发，这套链路对吞吐友好，但对“大图单张稳定性”反而更脆

- 