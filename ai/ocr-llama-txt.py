#!/opt/homebrew/bin/python3
# -*- coding: utf-8 -*-
"""
ocr-llama.py

使用本地 llama.cpp + GGUF 模型做两阶段 OCR：
1. GLM-OCR 负责图片文字提取
2. Gemma 负责中英文文本整理、明显 OCR 误识别修正与基础合法性校验

设计目标：
- 不依赖 Ollama
- 只在运行时临时启动 llama-server
- Stage 1 / Stage 2 各自按需加载，完成后立即释放
- 保持使用方式简单，尽量接近现有 OCR 脚本

示例：
  python ocr-llama.py
  python ocr-llama.py 1.png
  python ocr-llama.py /absolute/path/to/img.png
  python ocr-llama.py 1.png --save
  python ocr-llama.py 1.png --prompt "OCR markdown"
  python ocr-llama.py 1.png --no-enhance
"""

import argparse
import base64
import json
import os
import socket
import subprocess
import sys
import tempfile
import textwrap
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

# ── 默认配置 ────────────────────────────────────────────────
DEFAULT_DOWNLOAD_DIR = Path("/Users/lex/Downloads")
SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}

MODEL_PATH = Path(
    os.environ.get(
        "LLAMA_OCR_MODEL",
        "/Users/lex/.cache/lm-studio/models/ggml-org/GLM-OCR-GGUF/GLM-OCR-Q8_0.gguf",
    )
)
MMPROJ_PATH = Path(
    os.environ.get(
        "LLAMA_OCR_MMPROJ",
        "/Users/lex/.cache/lm-studio/models/ggml-org/GLM-OCR-GGUF/mmproj-GLM-OCR-Q8_0.gguf",
    )
)
LLAMA_SERVER_BIN = os.environ.get("LLAMA_SERVER_BIN", "/opt/homebrew/bin/llama-server")
ENHANCE_MODEL_PATH = Path(
    os.environ.get(
        "LLAMA_ENHANCE_MODEL",
        "/Users/lex/.cache/lm-studio/models/lmstudio-community/gemma-3-1b-it-GGUF/gemma-3-1b-it-Q4_K_M.gguf",
    )
)

OCR_CTX_SIZE = int(os.environ.get("OCR_CTX_SIZE", os.environ.get("LLAMA_CTX_SIZE", "4096")))
OCR_N_GPU_LAYERS = os.environ.get("OCR_N_GPU_LAYERS", os.environ.get("LLAMA_N_GPU_LAYERS", "8"))
OCR_THREADS = int(os.environ.get("OCR_THREADS", os.environ.get("LLAMA_THREADS", str(max(1, os.cpu_count() or 4)))))
ENHANCE_CTX_SIZE = int(os.environ.get("LLAMA_ENHANCE_CTX_SIZE", "4096"))
ENHANCE_N_GPU_LAYERS = os.environ.get("LLAMA_ENHANCE_N_GPU_LAYERS", "99")
ENHANCE_THREADS = int(os.environ.get("LLAMA_ENHANCE_THREADS", str(OCR_THREADS)))
LLAMA_SERVER_TIMEOUT = int(os.environ.get("LLAMA_SERVER_TIMEOUT", "60"))
LLAMA_HTTP_TIMEOUT = int(os.environ.get("LLAMA_HTTP_TIMEOUT", "300"))
LLAMA_PROMPT = os.environ.get("LLAMA_PROMPT", "OCR")
OCR_MAX_SIDE = int(os.environ.get("OCR_MAX_SIDE", "1280"))
ENHANCE_TEMPERATURE = float(os.environ.get("LLAMA_ENHANCE_TEMPERATURE", "0.1"))
ENHANCE_PROMPT = """你是 OCR 文本整理助手。请只输出整理后的最终文本，不要解释。

目标：
1. 保留原文语义，不要凭空补充事实。
2. 修复明显 OCR 错误，例如中英文混排中的错字、错位空格、乱码、0/O、1/l/I、标点误识别。
3. 对中英文做自然排版：
   - 中文语句通顺
   - 英文单词边界合理
   - 段落、换行、列表尽量整理清楚
4. 如果原文明显是 JSON、代码、表格或键值内容，尽量按原结构整理。
5. 不要总结，不要改写，不要删减重要信息。

请处理下面这段 OCR 原文：
"""

DIVIDER = "─" * 60
EQUALS = "=" * 60


def _now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def print_stage_start() -> float:
    t = time.time()
    print(f"    ⏱️  开始时间: {_now_str()}")
    return t


def print_stage_end(t_start: float, label: str = ""):
    elapsed = time.time() - t_start
    suffix = f"  [{label}]" if label else ""
    print(f"    ✅  结束时间: {_now_str()}{suffix}")
    print(f"    ⏱️  耗　　时: {elapsed:.2f} 秒")


def resolve_image_path(raw: str) -> Path:
    p = Path(raw)
    if p.is_absolute() and p.exists():
        return p
    candidate = DEFAULT_DOWNLOAD_DIR / p.name
    if candidate.exists():
        return candidate
    cwd_candidate = Path.cwd() / p
    if cwd_candidate.exists():
        return cwd_candidate
    print(f"❌  找不到图片文件：{raw}")
    print(f"    已尝试：\n      {p}\n      {candidate}\n      {cwd_candidate}")
    sys.exit(1)


def pick_image_interactively() -> Path:
    if not DEFAULT_DOWNLOAD_DIR.exists():
        print(f"❌  默认目录不存在：{DEFAULT_DOWNLOAD_DIR}")
        sys.exit(1)

    images = sorted(
        f for f in DEFAULT_DOWNLOAD_DIR.iterdir()
        if f.is_file() and f.suffix.lower() in SUPPORTED_EXTS
    )
    if not images:
        print(f"⚠️  {DEFAULT_DOWNLOAD_DIR} 中未找到支持的图片。")
        sys.exit(1)

    print(f"\n📂  默认目录：{DEFAULT_DOWNLOAD_DIR}")
    for i, img in enumerate(images, 1):
        size_kb = img.stat().st_size / 1024
        print(f"    [{i:2d}]  {img.name}  ({size_kb:.1f} KB)")
    print()
    raw = input("    请输入序号或文件名（直接回车使用第 1 张）：").strip()

    if raw == "":
        return images[0]
    if raw.isdigit():
        idx = int(raw) - 1
        if 0 <= idx < len(images):
            return images[idx]
        print(f"❌  序号超出范围（1 ~ {len(images)}）")
        sys.exit(1)
    return resolve_image_path(raw)


def ensure_runtime():
    if not Path(LLAMA_SERVER_BIN).exists():
        print(f"❌  未找到 llama-server：{LLAMA_SERVER_BIN}")
        print("    可检查：brew install llama.cpp")
        sys.exit(1)
    if not MODEL_PATH.exists():
        print(f"❌  未找到模型文件：{MODEL_PATH}")
        sys.exit(1)
    if not MMPROJ_PATH.exists():
        print(f"❌  未找到 mmproj 文件：{MMPROJ_PATH}")
        sys.exit(1)
    if not ENHANCE_MODEL_PATH.exists():
        print(f"❌  未找到增强模型文件：{ENHANCE_MODEL_PATH}")
        sys.exit(1)
    if not Path("/usr/bin/sips").exists():
        print("❌  未找到 sips，无法做图片预处理。")
        sys.exit(1)


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def prepare_image_for_ocr(image_path: Path) -> Path:
    """
    用 macOS 自带 sips 做轻量预处理：
    - 转成 JPEG，规避部分 PNG / alpha 兼容性问题
    - 如果图片过大，缩到 OCR_MAX_SIDE，减少 mmproj 显存压力
    """
    tmp_dir = Path(tempfile.mkdtemp(prefix="ocr-llama-img-"))
    out_path = tmp_dir / f"{image_path.stem}.jpg"

    try:
        subprocess.run(
            ["/usr/bin/sips", "-s", "format", "jpeg", str(image_path), "--out", str(out_path)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            ["/usr/bin/sips", "--resampleHeightWidthMax", str(OCR_MAX_SIDE), str(out_path)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"图片预处理失败：{e}") from e

    return out_path


def wait_server_ready(base_url: str, proc: subprocess.Popen):
    deadline = time.time() + LLAMA_SERVER_TIMEOUT
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            detail = ""
            log_path = getattr(proc, "_stderr_log_path", None)
            if log_path and Path(log_path).exists():
                try:
                    detail = Path(log_path).read_text(encoding="utf-8", errors="replace")[-4000:]
                except OSError:
                    detail = ""
            if detail:
                raise RuntimeError(f"llama-server 启动失败，进程已退出。\n\n{detail}")
            raise RuntimeError("llama-server 启动失败，进程已退出。")
        try:
            req = urllib.request.Request(f"{base_url}/health", method="GET")
            with urllib.request.urlopen(req, timeout=2) as resp:
                if 200 <= resp.status < 300:
                    return
        except Exception as e:
            last_error = e
        time.sleep(1)
    raise RuntimeError(f"等待 llama-server 就绪超时：{last_error}")


def start_llama_server(
    port: int,
    model_path: Path,
    ctx_size: int,
    gpu_layers: str,
    threads: int,
    mmproj_path: Path | None = None,
    fit_mode: str = "off",
    extra_args: list[str] | None = None,
) -> subprocess.Popen:
    cmd = [
        LLAMA_SERVER_BIN,
        "-m", str(model_path),
        "-c", str(ctx_size),
        "-ngl", str(gpu_layers),
        "-t", str(threads),
        "--host", "127.0.0.1",
        "--port", str(port),
        "--jinja",
        "-fa", "off",
        "-fit", fit_mode,
        "--no-webui",
    ]
    if mmproj_path is not None:
        cmd[3:3] = ["--mmproj", str(mmproj_path)]
    if extra_args:
        cmd.extend(extra_args)
    stderr_log = tempfile.NamedTemporaryFile(prefix="ocr-llama-", suffix=".log", delete=False)
    stderr_log_path = stderr_log.name
    stderr_log.close()
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=open(stderr_log_path, "w", encoding="utf-8"),
        text=True,
    )
    proc._stderr_log_path = stderr_log_path
    return proc


def stop_llama_server(proc: subprocess.Popen | None):
    if proc is None:
        return
    log_path = getattr(proc, "_stderr_log_path", None)
    if proc.poll() is not None:
        if log_path:
            try:
                Path(log_path).unlink(missing_ok=True)
            except OSError:
                pass
        return

    try:
        proc.terminate()
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)
    finally:
        if log_path:
            try:
                Path(log_path).unlink(missing_ok=True)
            except OSError:
                pass


def image_to_data_url(image_path: Path) -> str:
    suffix = image_path.suffix.lower()
    mime = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
        ".gif": "image/gif",
        ".bmp": "image/bmp",
    }.get(suffix, "application/octet-stream")
    encoded = base64.b64encode(image_path.read_bytes()).decode("utf-8")
    return f"data:{mime};base64,{encoded}"


def call_ocr(base_url: str, image_path: Path, prompt: str) -> str:
    payload = {
        "model": "glm-ocr-local",
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": image_to_data_url(image_path)
                        },
                    },
                    {
                        "type": "text",
                        "text": prompt,
                    },
                ],
            }
        ],
        "temperature": 0.02,
        "stream": False,
    }

    req = urllib.request.Request(
        f"{base_url}/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=LLAMA_HTTP_TIMEOUT) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"llama-server HTTP 错误：{e.code} {detail}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"调用 llama-server 失败：{e}") from e

    try:
        return body["choices"][0]["message"]["content"].strip()
    except (KeyError, IndexError, TypeError) as e:
        raise RuntimeError(f"无法解析 llama-server 响应：{body}") from e


def call_text_enhance(base_url: str, raw_text: str) -> str:
    payload = {
        "model": "gemma-local",
        "messages": [
            {
                "role": "user",
                "content": f"{ENHANCE_PROMPT.rstrip()}\n\n{raw_text}",
            }
        ],
        "temperature": ENHANCE_TEMPERATURE,
        "stream": False,
    }

    req = urllib.request.Request(
        f"{base_url}/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=LLAMA_HTTP_TIMEOUT) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"增强模型 HTTP 错误：{e.code} {detail}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"调用增强模型失败：{e}") from e

    try:
        return body["choices"][0]["message"]["content"].strip()
    except (KeyError, IndexError, TypeError) as e:
        raise RuntimeError(f"无法解析增强模型响应：{body}") from e


def save_result(image_path: Path, raw_text: str, enhanced_text: str | None):
    out_dir = Path(__file__).parent / "output"
    out_dir.mkdir(exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = out_dir / f"{image_path.stem}_{ts}_llama_ocr.md"

    with open(out, "w", encoding="utf-8") as f:
        f.write(f"# OCR 结果 — {image_path.name}\n\n")
        f.write(f"- 时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"- OCR 模型：`{MODEL_PATH.name}`\n")
        if enhanced_text is not None:
            f.write(f"- 整理模型：`{ENHANCE_MODEL_PATH.name}`\n")
        f.write(f"- 图片：`{image_path}`\n\n")
        f.write("## Stage 1 OCR 原文\n\n")
        f.write(raw_text)
        f.write("\n\n")
        if enhanced_text is not None:
            f.write("## Stage 2 整理结果\n\n")
            f.write(enhanced_text)
            f.write("\n")

    print(f"\n💾  结果已保存：{out}")


def main():
    parser = argparse.ArgumentParser(
        description="使用 llama.cpp + 本地 GLM-OCR GGUF 执行单次 OCR，并在结束后立即释放资源",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            示例：
              python ocr-llama.py
              python ocr-llama.py 1.png
              python ocr-llama.py 1.png --save
              python ocr-llama.py 1.png --prompt "OCR markdown"
              python ocr-llama.py 1.png --no-enhance

            环境变量：
              LLAMA_OCR_MODEL       主模型路径
              LLAMA_OCR_MMPROJ      mmproj 路径
              LLAMA_ENHANCE_MODEL   文本整理模型路径
              LLAMA_SERVER_BIN      llama-server 路径
              LLAMA_CTX_SIZE        上下文大小（默认 8192）
              LLAMA_N_GPU_LAYERS    GPU offload 层数（默认 99）
              LLAMA_THREADS         线程数（默认系统核心数）
              LLAMA_PROMPT          默认 OCR prompt（默认 OCR）
        """),
    )
    parser.add_argument("image", nargs="?", help="图片路径（可省略交互式选择）")
    parser.add_argument("--prompt", default=LLAMA_PROMPT, help=f"OCR prompt（默认: {LLAMA_PROMPT}）")
    parser.add_argument("--no-enhance", action="store_true", help="仅做 OCR，不进入文本整理阶段")
    parser.add_argument("--save", action="store_true", help="结果保存到 output/")
    args = parser.parse_args()

    ensure_runtime()

    print(f"\n🚀  任务开始  {_now_str()}")
    image_path = resolve_image_path(args.image) if args.image else pick_image_interactively()
    if image_path.suffix.lower() not in SUPPORTED_EXTS:
        print(f"⚠️  不支持的文件格式：{image_path.suffix}，支持：{', '.join(sorted(SUPPORTED_EXTS))}")
        sys.exit(1)

    port = find_free_port()
    base_url = f"http://127.0.0.1:{port}"
    proc = None
    prepared_image = None
    t_global = time.time()

    print(f"\n{DIVIDER}")
    print("🦙  [Stage 1] 启动 llama.cpp OCR")
    print(f"    模型: {MODEL_PATH.name}")
    print(f"    mmproj: {MMPROJ_PATH.name}")
    print(f"    图片: {image_path.name}  ({image_path.stat().st_size / 1024:.1f} KB)")
    print(f"    Prompt: {args.prompt}")
    print(DIVIDER)

    t_start = print_stage_start()
    try:
        prepared_image = prepare_image_for_ocr(image_path)
        proc = start_llama_server(
            port=port,
            model_path=MODEL_PATH,
            ctx_size=OCR_CTX_SIZE,
            gpu_layers=OCR_N_GPU_LAYERS,
            threads=OCR_THREADS,
            mmproj_path=MMPROJ_PATH,
            fit_mode="on",
            extra_args=["-np", "1", "--no-mmproj-offload", "-cram", "0"],
        )
        wait_server_ready(base_url, proc)
        raw_result = call_ocr(base_url, prepared_image, args.prompt)
    finally:
        stop_llama_server(proc)
        if prepared_image is not None:
            try:
                prepared_image.unlink(missing_ok=True)
                prepared_image.parent.rmdir()
            except OSError:
                pass

    print_stage_end(t_start, "llama.cpp OCR")

    print(f"\n{EQUALS}")
    print("📄  [Stage 1] OCR 结果")
    print(EQUALS)
    print(raw_result)
    print(EQUALS)

    enhanced_result = None
    if not args.no_enhance:
        port = find_free_port()
        base_url = f"http://127.0.0.1:{port}"
        proc = None

        print(f"\n{DIVIDER}")
        print("✨  [Stage 2] Gemma 文本整理")
        print(f"    模型: {ENHANCE_MODEL_PATH.name}")
        print(DIVIDER)

        t_start = print_stage_start()
        try:
            proc = start_llama_server(
                port=port,
                model_path=ENHANCE_MODEL_PATH,
                ctx_size=ENHANCE_CTX_SIZE,
                gpu_layers=ENHANCE_N_GPU_LAYERS,
                threads=ENHANCE_THREADS,
                mmproj_path=None,
                fit_mode="off",
            )
            wait_server_ready(base_url, proc)
            enhanced_result = call_text_enhance(base_url, raw_result)
        finally:
            stop_llama_server(proc)

        print_stage_end(t_start, "Gemma Enhance")

        print(f"\n{EQUALS}")
        print("✨  [Stage 2] 文本整理结果")
        print(EQUALS)
        print(enhanced_result)
        print(EQUALS)

    if args.save:
        save_result(image_path, raw_result, enhanced_result)

    elapsed = time.time() - t_global
    print(f"\n{DIVIDER}")
    print(f"🏁  全部完成  {_now_str()}  |  总耗时: {elapsed:.2f} 秒")
    if args.no_enhance:
        print("    资源已释放：OCR server 已停止")
    else:
        print("    资源已释放：OCR server 与整理 server 都已停止")
    print(f"{DIVIDER}\n")


if __name__ == "__main__":
    main()
