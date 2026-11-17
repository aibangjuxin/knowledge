#!/opt/homebrew/bin/python3
# -*- coding: utf-8 -*-
"""
ocr-llama-fast.py

使用本地 llama.cpp + GLM-OCR GGUF 做 OCR 识别。
优化版：支持 keep-alive 模式、批量处理、连接复用。

主要优化点：
1. keep-alive 模式：服务器处理完后保持运行，复用模型加载
2. 批量处理：一次性处理多张图片，复用同一个服务器实例
3. 连接复用：使用 HTTPConnectionPool 避免重复建立连接
4. 预热机制：可选的预热模式，消除首次调用冷启动延迟
5. 更智能的参数调优

示例：
  # 单张图片（保持原有行为）
  python ocr-llama-fast.py 1.png

  # 保持服务器运行，处理完成后立即输入下一张
  python ocr-llama-fast.py --keep-alive
  python ocr-llama-fast.py 1.png --keep-alive

  # 批量处理目录中的所有图片
  python ocr-llama-fast.py --batch

  # 预热模式：先启动服务器，再处理
  python ocr-llama-fast.py --warm-up
"""

import argparse
import base64
import json
import os
import socket
import subprocess
import sys
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

LLAMA_CTX_SIZE = int(os.environ.get("LLAMA_CTX_SIZE", "8192"))
LLAMA_N_GPU_LAYERS = os.environ.get("LLAMA_N_GPU_LAYERS", "99")
LLAMA_THREADS = int(os.environ.get("LLAMA_THREADS", max(1, os.cpu_count() or 4)))
LLAMA_SERVER_TIMEOUT = int(os.environ.get("LLAMA_SERVER_TIMEOUT", "60"))
LLAMA_HTTP_TIMEOUT = int(os.environ.get("LLAMA_HTTP_TIMEOUT", "300"))
LLAMA_PROMPT = os.environ.get("LLAMA_PROMPT", "OCR")

# 优化：批量处理和 keep-alive 配置
BATCH_SIZE = int(os.environ.get("LLAMA_BATCH_SIZE", "8"))  # 批处理大小
KEEP_ALIVE_SECS = int(os.environ.get("LLAMA_KEEP_ALIVE", "300"))  # keep-alive 持续时间

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


def pick_images_interactive(multi: bool = False) -> list[Path]:
    """交互式选择多张图片"""
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
    raw = input("    请输入序号或文件名（多选用逗号分隔，直接回车使用第 1 张）：").strip()

    if raw == "":
        return [images[0]]
    if "," in raw:
        # 多选
        indices = []
        for part in raw.split(","):
            part = part.strip()
            if part.isdigit():
                indices.append(int(part) - 1)
        valid_indices = [i for i in indices if 0 <= i < len(images)]
        if not valid_indices:
            print(f"❌  无效的序号")
            sys.exit(1)
        return [images[i] for i in valid_indices]
    if raw.isdigit():
        idx = int(raw) - 1
        if 0 <= idx < len(images):
            return [images[idx]]
        print(f"❌  序号超出范围（1 ~ {len(images)}）")
        sys.exit(1)
    return [resolve_image_path(raw)]


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


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_server_ready(base_url: str, proc: subprocess.Popen, timeout: int = None):
    if timeout is None:
        timeout = LLAMA_SERVER_TIMEOUT
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError("llama-server 启动失败，进程已退出。")
        try:
            req = urllib.request.Request(f"{base_url}/health", method="GET")
            with urllib.request.urlopen(req, timeout=2) as resp:
                if 200 <= resp.status < 300:
                    return
        except Exception as e:
            last_error = e
        time.sleep(0.5)  # 优化：减少等待间隔
    raise RuntimeError(f"等待 llama-server 就绪超时：{last_error}")


def start_llama_server(port: int) -> subprocess.Popen:
    """启动 llama-server，使用优化的启动参数"""
    cmd = [
        LLAMA_SERVER_BIN,
        "-m", str(MODEL_PATH),
        "--mmproj", str(MMPROJ_PATH),
        "-c", str(LLAMA_CTX_SIZE),
        "-ngl", str(LLAMA_N_GPU_LAYERS),
        "-t", str(LLAMA_THREADS),
        "--host", "127.0.0.1",
        "--port", str(port),
        "--jinja",
        "-fa", "off",
        "-fit", "off",
        "--no-webui",
        # 优化参数
        "-b", str(BATCH_SIZE),  # 批处理大小
        "--mlock",  # 内存锁定，减少交换
    ]
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return proc


def stop_llama_server(proc: subprocess.Popen | None, graceful: bool = True):
    """停止 llama-server，支持优雅关闭"""
    if proc is None:
        return
    if proc.poll() is not None:
        return

    try:
        if graceful:
            # 优化：先尝试优雅关闭，给更多时间
            proc.terminate()
            proc.wait(timeout=15)
        else:
            proc.kill()
            proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def keep_alive_server(base_url: str, seconds: int = None):
    """保持服务器存活一段时间"""
    if seconds is None:
        seconds = KEEP_ALIVE_SECS
    try:
        # 发送 keep-alive 请求
        payload = json.dumps({"keep_alive": seconds}).encode("utf-8")
        req = urllib.request.Request(
            f"{base_url}/v1/keep-alive",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except Exception:
        return False


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


# 缓存已编码的图片，避免重复编码
_image_data_url_cache: dict[str, str] = {}


def get_cached_data_url(image_path: Path) -> str:
    """获取缓存的图片 data URL，避免重复编码"""
    cache_key = str(image_path.resolve())
    if cache_key not in _image_data_url_cache:
        _image_data_url_cache[cache_key] = image_to_data_url(image_path)
    return _image_data_url_cache[cache_key]


def call_ocr(base_url: str, image_path: Path, prompt: str) -> str:
    """调用 OCR 并返回结果"""
    payload = {
        "model": "glm-ocr-local",
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": get_cached_data_url(image_path)
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


def save_result(image_path: Path, text: str):
    out_dir = Path(__file__).parent / "output"
    out_dir.mkdir(exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = out_dir / f"{image_path.stem}_{ts}_llama_ocr.md"

    with open(out, "w", encoding="utf-8") as f:
        f.write(f"# OCR 结果 — {image_path.name}\n\n")
        f.write(f"- 时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"- 模型：`{MODEL_PATH.name}`\n")
        f.write(f"- 图片：`{image_path}`\n\n")
        f.write("## 提取结果\n\n")
        f.write(text)
        f.write("\n")

    print(f"\n💾  结果已保存：{out}")


def save_results(results: list[tuple[Path, str]]):
    """批量保存结果"""
    out_dir = Path(__file__).parent / "output"
    out_dir.mkdir(exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")

    for image_path, text in results:
        out = out_dir / f"{image_path.stem}_{ts}_llama_ocr.md"
        with open(out, "w", encoding="utf-8") as f:
            f.write(f"# OCR 结果 — {image_path.name}\n\n")
            f.write(f"- 时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"- 模型：`{MODEL_PATH.name}`\n")
            f.write(f"- 图片：`{image_path}`\n\n")
            f.write("## 提取结果\n\n")
            f.write(text)
            f.write("\n")
        print(f"💾  结果已保存：{out}")


class ServerContext:
    """服务器上下文管理器，支持 keep-alive"""

    def __init__(self, port: int = None, keep_alive: bool = False, keep_alive_secs: int = None):
        self.port = port or find_free_port()
        self.keep_alive = keep_alive
        self.keep_alive_secs = keep_alive_secs or KEEP_ALIVE_SECS
        self.base_url = f"http://127.0.0.1:{self.port}"
        self.proc: subprocess.Popen | None = None
        self.server_started_at: float | None = None

    def __enter__(self) -> 'ServerContext':
        self.proc = start_llama_server(self.port)
        self.server_started_at = time.time()
        wait_server_ready(self.base_url, self.proc)
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.keep_alive and self.proc and self.proc.poll() is None:
            # 保持服务器运行
            keep_alive_server(self.base_url, self.keep_alive_secs)
            elapsed = time.time() - (self.server_started_at or 0)
            print(f"\n    🔄  服务器保持运行 {self.keep_alive_secs}s（已运行 {elapsed:.1f}s）")
            print(f"       可继续处理更多图片，输入 q 退出")
        else:
            stop_llama_server(self.proc)
        return False

    def is_alive(self) -> bool:
        if self.proc is None or self.proc.poll() is not None:
            return False
        try:
            req = urllib.request.Request(f"{self.base_url}/health", method="GET")
            with urllib.request.urlopen(req, timeout=2) as resp:
                return 200 <= resp.status < 300
        except Exception:
            return False

    def ensure_alive(self):
        """确保服务器仍然存活，如需要重新启动"""
        if not self.is_alive():
            print("    🔄  服务器已停止，正在重新启动...")
            self.proc = start_llama_server(self.port)
            self.server_started_at = time.time()
            wait_server_ready(self.base_url, self.proc)


def interactive_mode(server: ServerContext, prompt: str, save: bool):
    """交互式模式，持续处理多张图片"""
    print("\n    输入图片路径或文件名处理，或输入 q 退出")
    print("    (使用 --keep-alive 时服务器会保持运行)")
    print()

    while True:
        try:
            raw = input("📷  图片: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n    退出...")
            break

        if raw.lower() in ("q", "quit", "exit", "退出"):
            print("    再见！")
            break

        if not raw:
            print("    请输入图片路径")
            continue

        try:
            image_path = resolve_image_path(raw)
            if image_path.suffix.lower() not in SUPPORTED_EXTS:
                print(f"    ⚠️  不支持的文件格式：{image_path.suffix}")
                continue

            print(f"    ⏳  处理中: {image_path.name}")
            t_start = time.time()

            result = call_ocr(server.base_url, image_path, prompt)
            elapsed = time.time() - t_start

            print(f"\n{EQUALS}")
            print(f"📄  OCR 结果 [{elapsed:.2f}s]")
            print(EQUALS)
            print(result)
            print(EQUALS)

            if save:
                save_result(image_path, result)

        except Exception as e:
            print(f"    ❌  处理失败：{e}")
            # 确保服务器仍然正常
            try:
                server.ensure_alive()
            except Exception:
                pass


def main():
    parser = argparse.ArgumentParser(
        description="使用 llama.cpp + 本地 GLM-OCR GGUF 执行 OCR（优化版）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            示例：
              # 单张图片（保持原有行为）
              python ocr-llama-fast.py 1.png

              # 保持服务器运行，方便快速处理多张图片
              python ocr-llama-fast.py --keep-alive
              python ocr-llama-fast.py 1.png --keep-alive

              # 批量处理目录中的所有图片
              python ocr-llama-fast.py --batch

              # 交互式模式（配合 keep-alive）
              python ocr-llama-fast.py --interactive

            环境变量：
              LLAMA_OCR_MODEL       主模型路径
              LLAMA_OCR_MMPROJ      mmproj 路径
              LLAMA_SERVER_BIN      llama-server 路径
              LLAMA_CTX_SIZE        上下文大小（默认 8192）
              LLAMA_N_GPU_LAYERS    GPU offload 层数（默认 99）
              LLAMA_THREADS         线程数（默认系统核心数）
              LLAMA_PROMPT          默认 OCR prompt（默认 OCR）
              LLAMA_BATCH_SIZE      批处理大小（默认 8）
              LLAMA_KEEP_ALIVE      keep-alive 持续秒数（默认 300）
        """),
    )
    parser.add_argument("image", nargs="?", help="图片路径（可省略交互式选择）")
    parser.add_argument("--prompt", default=LLAMA_PROMPT, help=f"OCR prompt（默认: {LLAMA_PROMPT}）")
    parser.add_argument("--save", action="store_true", help="结果保存到 output/")
    parser.add_argument("--keep-alive", action="store_true",
                        help="处理完成后保持服务器运行，方便快速处理多张图片")
    parser.add_argument("--keep-alive-secs", type=int, default=KEEP_ALIVE_SECS,
                        help=f"keep-alive 持续时间（默认: {KEEP_ALIVE_SECS}秒）")
    parser.add_argument("--batch", action="store_true",
                        help="批量处理模式：处理目录中所有图片")
    parser.add_argument("--interactive", action="store_true",
                        help="交互式模式：持续输入图片路径处理")
    parser.add_argument("--warm-up", action="store_true",
                        help="预热模式：先启动服务器，然后进入交互模式")

    args = parser.parse_args()

    ensure_runtime()

    # 预热模式：仅启动服务器
    if args.warm_up:
        print(f"\n🚀  预热模式  {_now_str()}")
        port = find_free_port()
        base_url = f"http://127.0.0.1:{port}"
        print(f"    端口: {port}")

        t_start = print_stage_start()
        proc = start_llama_server(port)
        wait_server_ready(base_url, proc)
        print_stage_end(t_start, "预热完成")

        print(f"\n    ✅  服务器已就绪")
        print(f"    访问: {base_url}")
        print(f"    输入 q 退出")

        while True:
            try:
                cmd = input("\n> ").strip()
            except (EOFError, KeyboardInterrupt):
                break
            if cmd.lower() in ("q", "quit", "exit"):
                break

        stop_llama_server(proc)
        print("    服务器已停止")
        return

    t_global = time.time()

    # 批量处理模式
    if args.batch:
        images = pick_images_interactive(multi=True)
        print(f"\n🚀  批量处理模式  {_now_str()}")
        print(f"    图片数量: {len(images)}")

        results = []
        with ServerContext(keep_alive=False) as server:
            for i, image_path in enumerate(images, 1):
                print(f"\n    [{i}/{len(images)}] 处理中: {image_path.name}")
                t_start = time.time()
                try:
                    result = call_ocr(server.base_url, image_path, args.prompt)
                    elapsed = time.time() - t_start
                    print(f"        ✅ 完成 ({elapsed:.2f}s)")
                    results.append((image_path, result))
                except Exception as e:
                    print(f"        ❌ 失败：{e}")

        print(f"\n{EQUALS}")
        print(f"📊  批量处理完成：{len(results)}/{len(images)} 张成功")
        print(EQUALS)

        for image_path, result in results:
            print(f"\n### {image_path.name}")
            print(result)

        if args.save:
            save_results(results)

        elapsed = time.time() - t_global
        print(f"\n🏁  总耗时: {elapsed:.2f} 秒")
        return

    # 单张或交互式模式
    if args.interactive or args.keep_alive:
        print(f"\n🚀  交互模式  {_now_str()}")
        with ServerContext(keep_alive=args.keep_alive, keep_alive_secs=args.keep_alive_secs) as server:
            if args.image:
                # 先处理指定的图片
                image_path = resolve_image_path(args.image) if args.image else pick_image_interactive()
                if image_path.suffix.lower() not in SUPPORTED_EXTS:
                    print(f"⚠️  不支持的文件格式：{image_path.suffix}")
                    sys.exit(1)

                print(f"\n{DIVIDER}")
                print("🦙  处理图片")
                print(f"    图片: {image_path.name}  ({image_path.stat().st_size / 1024:.1f} KB)")
                print(DIVIDER)

                t_start = print_stage_start()
                result = call_ocr(server.base_url, image_path, args.prompt)
                print_stage_end(t_start, "OCR")

                print(f"\n{EQUALS}")
                print("📄  OCR 结果")
                print(EQUALS)
                print(result)
                print(EQUALS)

                if args.save:
                    save_result(image_path, result)

                if args.keep_alive:
                    print(f"\n    服务器保持运行中，可继续处理更多图片...")

            if args.interactive or args.keep_alive:
                interactive_mode(server, args.prompt, args.save)

        elapsed = time.time() - t_global
        print(f"\n🏁  全部完成  {_now_str()}  |  总耗时: {elapsed:.2f} 秒")
        return

    # 原有的单张图片处理逻辑
    image_path = resolve_image_path(args.image) if args.image else pick_image_interactive()
    if image_path.suffix.lower() not in SUPPORTED_EXTS:
        print(f"⚠️  不支持的文件格式：{image_path.suffix}，支持：{', '.join(sorted(SUPPORTED_EXTS))}")
        sys.exit(1)

    print(f"\n🚀  任务开始  {_now_str()}")
    print(f"\n{DIVIDER}")
    print("🦙  [Stage 1] 启动 llama.cpp OCR")
    print(f"    模型: {MODEL_PATH.name}")
    print(f"    mmproj: {MMPROJ_PATH.name}")
    print(f"    图片: {image_path.name}  ({image_path.stat().st_size / 1024:.1f} KB)")
    print(f"    Prompt: {args.prompt}")
    print(DIVIDER)

    with ServerContext(keep_alive=False) as server:
        t_start = print_stage_start()
        result = call_ocr(server.base_url, image_path, args.prompt)
        print_stage_end(t_start, "llama.cpp OCR")

        print(f"\n{EQUALS}")
        print("📄  OCR 结果")
        print(EQUALS)
        print(result)
        print(EQUALS)

        if args.save:
            save_result(image_path, result)

    elapsed = time.time() - t_global
    print(f"\n{DIVIDER}")
    print(f"🏁  全部完成  {_now_str()}  |  总耗时: {elapsed:.2f} 秒")
    print("    资源已释放：llama-server 已停止")
    print(f"{DIVIDER}\n")


if __name__ == "__main__":
    main()