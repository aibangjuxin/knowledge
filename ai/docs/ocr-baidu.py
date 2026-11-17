#!/opt/homebrew/bin/python3
# -*- coding: utf-8 -*-
"""
ocr-baidu.py

使用本地 llama.cpp + PaddleOCR-VL (GGUF) 做单次 OCR 提取。

与 ocr-llama.py 的关系：完全相同的脚本结构（图片解析、预处理、启动
llama-server、HTTP OCR 调用、JSON/YAML 格式化、保存结果），仅替换
默认模型路径与少量标签文字。调用逻辑、图片预处理、API 路径、错误
处理、参数解析均未修改 —— 见原 ocr-llama.py。

设计目标：

设计目标：
- 保持使用习惯简单，尽量接近现有 OCR 脚本
- 不依赖 Ollama
- 每次运行时临时启动 llama-server
- OCR 完成后立即停止 server，尽快释放内存/显存

示例：
  python ocr-llama.py
  python ocr-llama.py 1.png
  python ocr-llama.py /absolute/path/to/img.png
  python ocr-llama.py 1.png --save
  python ocr-llama.py 1.png --prompt "OCR markdown"
"""

import argparse
import base64
import json
import os
import re
import shutil
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
SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".heic", ".tif", ".tiff"}

MODEL_PATH = Path(
    os.environ.get(
        "PADDLE_OCR_MODEL",
        "/Users/lex/models/PaddlePaddle/PaddleOCR-VL-1.6-GGUF.gguf",
    )
)
MMPROJ_PATH = Path(
    os.environ.get(
        "PADDLE_OCR_MMPROJ",
        "/Users/lex/models/PaddlePaddle/PaddleOCR-VL-1.6-GGUF-mmproj.gguf",
    )
)
LLAMA_SERVER_BIN = os.environ.get("LLAMA_SERVER_BIN", "/opt/homebrew/bin/llama-server")

LLAMA_CTX_SIZE = int(os.environ.get("LLAMA_CTX_SIZE", "8192"))
LLAMA_N_GPU_LAYERS = os.environ.get("LLAMA_N_GPU_LAYERS", "auto")
LLAMA_THREADS = int(os.environ.get("LLAMA_THREADS", max(1, os.cpu_count() or 4)))
LLAMA_SERVER_TIMEOUT = int(os.environ.get("LLAMA_SERVER_TIMEOUT", "60"))
LLAMA_HTTP_TIMEOUT = int(os.environ.get("LLAMA_HTTP_TIMEOUT", "300"))
LLAMA_PROMPT = os.environ.get(
    "LLAMA_PROMPT",
    "Extract all visible text exactly. If the image contains JSON, YAML, shell, or code, preserve line breaks and indentation. Return only the extracted text.",
)
OCR_IMAGE_MAX_EDGE = int(os.environ.get("OCR_IMAGE_MAX_EDGE", "2200"))
OCR_IMAGE_MIN_EDGE = int(os.environ.get("OCR_IMAGE_MIN_EDGE", "320"))
LLAMA_CLI_BIN = os.environ.get("LLAMA_CLI_BIN", "/opt/homebrew/bin/llama-cli")
FORMATTER_MODEL_PATH = Path(
    os.environ.get(
        "OCR_FORMATTER_MODEL",
        "/Users/lex/.cache/lm-studio/models/lmstudio-community/gemma-3-1b-it-GGUF/gemma-3-1b-it-Q4_K_M.gguf",
    )
)
FORMATTER_TIMEOUT = int(os.environ.get("OCR_FORMATTER_TIMEOUT", "120"))

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


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_server_ready(base_url: str, proc: subprocess.Popen):
    deadline = time.time() + LLAMA_SERVER_TIMEOUT
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
        time.sleep(1)
    raise RuntimeError(f"等待 llama-server 就绪超时：{last_error}")


def start_llama_server(port: int) -> subprocess.Popen:
    cmd = [
        LLAMA_SERVER_BIN,
        "-m", str(MODEL_PATH),
        "--mmproj", str(MMPROJ_PATH),
        "-c", str(LLAMA_CTX_SIZE),
        "-ngl", str(LLAMA_N_GPU_LAYERS),
        "-t", str(LLAMA_THREADS),
        "-np", "1",
        "--host", "127.0.0.1",
        "--port", str(port),
        "--jinja",
        "-fa", "off",
        "-fit", "on",
        "--no-mmproj-offload",
        "-cram", "0",
        "--no-webui",
    ]
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return proc


def stop_llama_server(proc: subprocess.Popen | None):
    if proc is None:
        return
    if proc.poll() is not None:
        return

    try:
        proc.terminate()
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


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


def get_image_size(image_path: Path) -> tuple[int | None, int | None]:
    if not shutil.which("sips"):
        return None, None
    try:
        proc = subprocess.run(
            ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(image_path)],
            check=True,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (subprocess.SubprocessError, OSError):
        return None, None

    width = height = None
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.startswith("pixelWidth:"):
            width = int(line.split(":", 1)[1].strip())
        elif line.startswith("pixelHeight:"):
            height = int(line.split(":", 1)[1].strip())
    return width, height


def prepare_image(image_path: Path, work_dir: Path, max_edge: int, enable: bool) -> tuple[Path, str]:
    """Convert large or non-PNG/JPEG screenshots to a temporary PNG for steadier OCR."""
    if not enable:
        return image_path, "原图"
    if not shutil.which("sips"):
        return image_path, "原图（未找到 sips）"

    width, height = get_image_size(image_path)
    suffix = image_path.suffix.lower()
    needs_convert = suffix in {".heic", ".tif", ".tiff", ".gif", ".bmp", ".webp"}
    needs_resize = bool(width and height and max(width, height) > max_edge and min(width, height) >= OCR_IMAGE_MIN_EDGE)
    if not needs_convert and not needs_resize:
        return image_path, "原图"

    out = work_dir / f"{image_path.stem}_ocr_input.png"
    cmd = ["sips", "-s", "format", "png"]
    if needs_resize:
        cmd.extend(["-Z", str(max_edge)])
    cmd.extend([str(image_path), "--out", str(out)])
    subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=60)
    new_width, new_height = get_image_size(out)
    old_desc = f"{width}x{height}" if width and height else "unknown"
    new_desc = f"{new_width}x{new_height}" if new_width and new_height else "unknown"
    return out, f"预处理 PNG（{old_desc} -> {new_desc}）"


def call_ocr(base_url: str, image_path: Path, prompt: str) -> str:
    payload = {
        "model": "paddle-ocr-local",
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


def strip_markdown_fence(text: str) -> str:
    cleaned = text.strip()
    match = re.fullmatch(r"```(?:json|yaml|yml|text|txt)?\s*\n(.*?)\n```", cleaned, flags=re.S | re.I)
    if match:
        return match.group(1).strip()
    return cleaned


def extract_fenced_block(text: str, names: tuple[str, ...]) -> str | None:
    pattern = r"```(?:" + "|".join(re.escape(n) for n in names) + r")\s*\n(.*?)\n```"
    match = re.search(pattern, text, flags=re.S | re.I)
    return match.group(1).strip() if match else None


def likely_yaml(text: str) -> bool:
    lines = [line for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    if not lines:
        return False
    hits = sum(1 for line in lines if re.match(r"^\s*[-\w\"'.]+:\s*.*$", line) or re.match(r"^\s*-\s+\w", line))
    return hits >= max(2, len(lines) // 3)


def format_json_text(text: str) -> str | None:
    candidates = [
        extract_fenced_block(text, ("json",)),
        strip_markdown_fence(text),
    ]
    stripped = text.strip()
    start_chars = [i for i in [stripped.find("{"), stripped.find("[")] if i >= 0]
    if start_chars:
        start = min(start_chars)
        end = max(stripped.rfind("}"), stripped.rfind("]"))
        if end > start:
            candidates.append(stripped[start:end + 1])

    for candidate in candidates:
        if not candidate:
            continue
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        return json.dumps(parsed, ensure_ascii=False, indent=2)
    return None


def format_yaml_text(text: str) -> str | None:
    candidate = extract_fenced_block(text, ("yaml", "yml")) or strip_markdown_fence(text)
    if not likely_yaml(candidate):
        return None
    if not shutil.which("ruby"):
        return None

    ruby_code = (
        "require 'yaml'; require 'date'; "
        "obj = YAML.safe_load(STDIN.read, permitted_classes: [Date, Time, Symbol], aliases: true); "
        "exit 2 unless obj.is_a?(Hash) || obj.is_a?(Array); "
        "print YAML.dump(obj).sub(/\\A---\\s*\\n/, '')"
    )
    try:
        proc = subprocess.run(
            ["ruby", "-e", ruby_code],
            input=candidate,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (subprocess.SubprocessError, OSError):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def format_with_local_llm(text: str, mode: str) -> str | None:
    if not Path(LLAMA_CLI_BIN).exists() or not FORMATTER_MODEL_PATH.exists():
        return None

    prompt = textwrap.dedent(f"""\
        Clean up OCR text from a screenshot.
        Goal: output only the corrected content.
        Mode: {mode}
        Rules:
        - Preserve the original meaning and keys.
        - Do not add explanations.
        - If the text is JSON or YAML, repair obvious OCR punctuation errors and keep readable indentation.
        - If uncertain, return the input content unchanged.

        OCR text:
        ```text
        {text}
        ```
    """)
    cmd = [
        LLAMA_CLI_BIN,
        "-m", str(FORMATTER_MODEL_PATH),
        "-p", prompt,
        "-n", "2048",
        "-c", "4096",
        "-ngl", "auto",
        "--temp", "0",
        "--log-disable",
        "--no-display-prompt",
        "--simple-io",
        "-st",
        "--no-warmup",
    ]
    try:
        proc = subprocess.run(cmd, check=False, capture_output=True, text=True, timeout=FORMATTER_TIMEOUT)
    except (subprocess.SubprocessError, OSError):
        return None
    cleaned = clean_llama_cli_output(proc.stdout, prompt)
    return strip_markdown_fence(cleaned) if proc.returncode == 0 and cleaned else None


def clean_llama_cli_output(stdout: str, prompt: str) -> str:
    text = stdout.strip()
    if prompt in text:
        text = text.split(prompt, 1)[1]
    for marker in ("\n[ Prompt:", "\ncommon_memory_breakdown_print:", "\nggml_metal_free:"):
        if marker in text:
            text = text.split(marker, 1)[0]
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if stripped == "Exiting..." or stripped.startswith(">"):
            continue
        if stripped.startswith("[ Prompt:") or stripped.startswith("build      :"):
            continue
        lines.append(line)
    return "\n".join(lines).strip()


def postprocess_text(text: str, mode: str, use_llm: bool) -> tuple[str, str]:
    if mode == "none":
        return text.strip(), "未格式化"

    result = None
    label = "未格式化"
    if mode in {"auto", "json"}:
        result = format_json_text(text)
        if result is not None:
            label = "JSON 格式化"
    if result is None and mode in {"auto", "yaml"}:
        result = format_yaml_text(text)
        if result is not None:
            label = "YAML 格式化"

    if result is None:
        result = strip_markdown_fence(text)

    if use_llm and label == "未格式化":
        llm_result = format_with_local_llm(result, mode)
        if llm_result:
            result = llm_result
            if mode in {"auto", "json"}:
                result = format_json_text(result) or result
            if mode in {"auto", "yaml"}:
                result = format_yaml_text(result) or result
            label = f"{label} + 本地小模型清理" if label != "未格式化" else "本地小模型清理"

    return result.strip(), label


def save_result(image_path: Path, text: str):
    out_dir = Path(__file__).parent / "output"
    out_dir.mkdir(exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = out_dir / f"{image_path.stem}_{ts}_paddle_ocr.md"

    with open(out, "w", encoding="utf-8") as f:
        f.write(f"# OCR 结果 — {image_path.name}\n\n")
        f.write(f"- 时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"- 模型：`{MODEL_PATH.name}`\n")
        f.write(f"- 图片：`{image_path}`\n\n")
        f.write("## 提取结果\n\n")
        f.write(text)
        f.write("\n")

    print(f"\n💾  结果已保存：{out}")


def main():
    parser = argparse.ArgumentParser(
        description="使用 llama.cpp + 本地 PaddleOCR-VL GGUF 执行单次 OCR，并在结束后立即释放资源",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            示例：
              python ocr-baidu.py
              python ocr-baidu.py 1.png
              python ocr-baidu.py 1.png --save
              python ocr-baidu.py 1.png --prompt "OCR markdown"
              python ocr-baidu.py 1.png --format json
              python ocr-baidu.py 1.png --llm-format

            环境变量：
              PADDLE_OCR_MODEL      主模型路径（默认 PaddleOCR-VL-1.6-GGUF）
              PADDLE_OCR_MMPROJ     mmproj 路径
              LLAMA_SERVER_BIN      llama-server 路径
              LLAMA_CTX_SIZE        上下文大小（默认 8192）
              LLAMA_N_GPU_LAYERS    GPU offload 层数（默认 auto）
              LLAMA_THREADS         线程数（默认系统核心数）
              LLAMA_PROMPT          默认 OCR prompt（默认 OCR）
              OCR_IMAGE_MAX_EDGE    图片预处理最长边（默认 2200）
              OCR_FORMATTER_MODEL   可选文本清理小模型
        """),
    )
    parser.add_argument("image", nargs="?", help="图片路径（可省略交互式选择）")
    parser.add_argument("--prompt", default=LLAMA_PROMPT, help=f"OCR prompt（默认: {LLAMA_PROMPT}）")
    parser.add_argument("--format", choices=("auto", "json", "yaml", "none"), default="auto", help="OCR 后格式化方式（默认 auto）")
    parser.add_argument("--llm-format", action="store_true", help="使用本地小模型再做一次轻量格式清理（更慢，默认关闭）")
    parser.add_argument("--no-preprocess", action="store_true", help="跳过图片预处理，直接把原图交给 OCR 模型")
    parser.add_argument("--max-edge", type=int, default=OCR_IMAGE_MAX_EDGE, help=f"图片预处理最长边（默认 {OCR_IMAGE_MAX_EDGE}）")
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
    t_global = time.time()
    tmp_dir_obj = tempfile.TemporaryDirectory(prefix="ocr_llama_")

    print(f"\n{DIVIDER}")
    print("🐼  [Stage 1] 启动 PaddleOCR-VL (llama.cpp)")
    print(f"    模型: {MODEL_PATH.name}")
    print(f"    mmproj: {MMPROJ_PATH.name}")
    print(f"    图片: {image_path.name}  ({image_path.stat().st_size / 1024:.1f} KB)")
    print(f"    Prompt: {args.prompt}")
    print(f"    格式化: {args.format}{' + 本地小模型' if args.llm_format else ''}")
    print(DIVIDER)

    t_start = print_stage_start()
    try:
        request_image, image_note = prepare_image(
            image_path,
            Path(tmp_dir_obj.name),
            max(512, args.max_edge),
            not args.no_preprocess,
        )
        print(f"    图片输入: {image_note}")
        proc = start_llama_server(port)
        wait_server_ready(base_url, proc)
        raw_result = call_ocr(base_url, request_image, args.prompt)
        result, format_label = postprocess_text(raw_result, args.format, args.llm_format)
    finally:
        stop_llama_server(proc)
        tmp_dir_obj.cleanup()

    print_stage_end(t_start, f"llama.cpp OCR / {format_label}")

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
