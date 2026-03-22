#!/Users/lex/python/openai/bin/python3
# -*- coding: utf-8 -*-
"""
last.py

以 ocr-ollama-3.py 为基线的高性能版。
目标：
- 保持原有使用习惯、交互逻辑和输出节奏基本不变
- 只做内部性能优化，不改你当前稳定版本的主逻辑

主要优化：
  1. 复用 Ollama Client，避免 Stage 1 / Stage 2 反复初始化
  2. Stage 1 保持与 ocr-ollama-3.py 一致，优先稳定性
  3. Stage 2 适度增加本地推理参数
  4. 预编译规则处理用到的正则
  5. 图片读取改为 Path.read_bytes()，实现更直接

用法与 ocr-ollama-3.py 基本一致：
  python last.py
  python last.py 1.png
  python last.py 1.png --auto-enhance
  python last.py 1.png --no-enhance
  python last.py 1.png --save
  python last.py 1.png --model mistral
  python last.py 1.png --wait 5
"""

import argparse
import json
import os
import re
import select
import sys
import textwrap
import threading
import time
from datetime import datetime
from functools import lru_cache
from pathlib import Path

# ── 默认配置 ────────────────────────────────────────────────
DEFAULT_DOWNLOAD_DIR = Path("/Users/lex/Downloads")
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
OCR_MODEL = "glm-ocr"
ENHANCE_MODEL = os.environ.get("ENHANCE_MODEL", "gemma3:270m")
SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}

# 如果你的 10 核 Mac 包含 8 个性能核 + 2 个能效核，设置为 8 通常比 10 更快！
# 可以通过环境变量 OLLAMA_NUM_THREAD=8 来外部覆盖，默认仍然使用系统总核心数
CPU_THREADS = int(os.environ.get("OLLAMA_NUM_THREAD", max(1, os.cpu_count() or 4)))
# CPU_THREADS = max(1, os.cpu_count() or 4) # 默认使用系统总核心数
ENHANCE_KEEP_ALIVE = os.environ.get("ENHANCE_KEEP_ALIVE", "15m")
ENHANCE_NUM_CTX = int(os.environ.get("ENHANCE_NUM_CTX", "2048"))
ENHANCE_NUM_PREDICT = int(os.environ.get("ENHANCE_NUM_PREDICT", "1024"))

OCR_PROMPT = (
    "请识别并提取这张图片中的所有文字内容，尽量保留原始格式，"
    "不要推断或补充原图中没有的信息。"
)

ENHANCE_SYSTEM_PROMPT = """\
你是文本格式化助手。将 OCR 原始文字做如下处理（直接输出结果，不要解释）：
- 将字面量 \\n 替换为真实换行
- JSON → 格式化 JSON，首行加 [FORMAT: JSON]
- 代码 → 格式化，首行加 [FORMAT: <语言>]
- 普通文本 → 修复排版，首行加 [FORMAT: TEXT]
- 修复 OCR 误识别（0/O、1/l 等）
"""

DIVIDER = "─" * 60
EQUALS = "=" * 60
JSON_BLOCK_RE = re.compile(r"(\{[\s\S]*\}|\[[\s\S]*\])")


# ─────────────── 时间工具 ─────────────────────────────────────

def _now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def print_stage_start(label: str) -> float:
    t = time.time()
    print(f"    ⏱️  开始时间: {_now_str()}")
    return t


def print_stage_end(t_start: float, label: str = ""):
    elapsed = time.time() - t_start
    suffix = f"  [{label}]" if label else ""
    print(f"    ✅  结束时间: {_now_str()}{suffix}")
    print(f"    ⏱️  耗　　时: {elapsed:.2f} 秒")


# ─────────────────────── 路径工具 ────────────────────────────

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


# ─────────────── 规则后处理 ──────────────────────────────────

def rule_based_format(text: str) -> str:
    cleaned = text.replace("\\n", "\n").replace("\\t", "\t")

    json_match = JSON_BLOCK_RE.search(cleaned)
    if json_match:
        try:
            obj = json.loads(json_match.group(1))
            before = cleaned[:json_match.start()].strip()
            after = cleaned[json_match.end():].strip()
            parts = []
            if before:
                parts.append(before)
            parts.append(json.dumps(obj, ensure_ascii=False, indent=2))
            if after:
                parts.append(after)
            return "\n".join(parts)
        except json.JSONDecodeError:
            pass

    return cleaned


# ─────────────────── Ollama 调用 ─────────────────────────────

@lru_cache(maxsize=1)
def _get_client():
    try:
        import ollama
        return ollama, ollama.Client(host=OLLAMA_HOST)
    except ImportError:
        print("❌  未安装 ollama 库：")
        print(f"    {sys.executable} -m pip install ollama")
        sys.exit(1)


def stage1_ocr(image_path: Path) -> str:
    """Stage 1：glm-ocr 提取原始文字"""
    ollama, client = _get_client()

    print(f"\n{DIVIDER}")
    print(f"🔍  [Stage 1] OCR 提取  →  模型: {OCR_MODEL}")
    print(f"    图片: {image_path.name}  ({image_path.stat().st_size / 1024:.1f} KB)")
    print(f"    Ollama: {OLLAMA_HOST}")
    print(DIVIDER)

    t_start = print_stage_start("Stage 1")
    img_bytes = image_path.read_bytes()

    try:
        response = client.chat(
            model=OCR_MODEL,
            messages=[
                ollama.Message(
                    role="user",
                    content=OCR_PROMPT,
                    images=[ollama.Image(value=img_bytes)],
                )
            ],
            options=ollama.Options(
                temperature=0.05,
                top_p=0.9,
            ),
        )
    except ollama.ResponseError as e:
        print(f"❌  OCR 错误：{e.status_code} — {e.error}")
        print(f"    确认 {OCR_MODEL} 已拉取：ollama list")
        sys.exit(1)

    print_stage_end(t_start, "Stage 1 OCR")
    return response.message.content


def stage2_enhance(raw_text: str, model: str) -> str:
    """Stage 2：通用 LLM 格式化 + 语法修复（流式输出）"""
    ollama, client = _get_client()

    print(f"\n{DIVIDER}")
    print(f"✨  [Stage 2] AI 增强   →  模型: {model}  [流式输出]")
    print(DIVIDER)

    t_start = print_stage_start("Stage 2")
    print()

    collected_chunks = []
    try:
        stream = client.chat(
            model=model,
            messages=[
                ollama.Message(role="system", content=ENHANCE_SYSTEM_PROMPT),
                ollama.Message(role="user", content=raw_text),
            ],
            options=ollama.Options(
                temperature=0.1,
                top_p=0.85,
                num_predict=ENHANCE_NUM_PREDICT,
                num_ctx=ENHANCE_NUM_CTX,
                num_thread=CPU_THREADS,
            ),
            keep_alive=ENHANCE_KEEP_ALIVE,
            stream=True,
        )
        for chunk in stream:
            token = chunk.message.content
            if token:
                sys.stdout.write(token)
                sys.stdout.flush()
                collected_chunks.append(token)

    except ollama.ResponseError as e:
        print(f"\n⚠️  增强模型错误：{e.status_code} — {e.error}")
        print("    跳过 AI 增强，返回规则处理结果。")
        return raw_text

    print()
    print_stage_end(t_start, f"Stage 2 [{model}]")
    return "".join(collected_chunks)


# ──────────────── 倒计时交互确认 ─────────────────────────────

def ask_to_enhance(wait_seconds: int) -> bool:
    """
    在终端打印倒计时。
    - 不输入，超时后默认进入 Stage 2
    - 输入任意字符（或回车）→ 返回 False（退出/跳过）
    使用 select 实现非阻塞 stdin 读取（macOS / Linux）。
    """
    stop_event = threading.Event()

    def countdown():
        for remaining in range(wait_seconds, 0, -1):
            if stop_event.is_set():
                return
            sys.stdout.write(
                f"\r    ⏳ 输入任意字符并回车退出 AI 增强；不输入将在 [{remaining}s] 后继续... "
            )
            sys.stdout.flush()
            time.sleep(1)
        if not stop_event.is_set():
            sys.stdout.write(
                "\r    ✅ 已超时，默认进入 Stage 2 AI 增强。                         \n"
            )
            sys.stdout.flush()

    t = threading.Thread(target=countdown, daemon=True)
    t.start()

    ready, _, _ = select.select([sys.stdin], [], [], wait_seconds)

    stop_event.set()
    t.join(timeout=0.5)

    if ready:
        user_input = sys.stdin.readline().strip()
        sys.stdout.write(
            f"\r    ⏭️  输入 [{user_input}]，手动跳过 Stage 2 增强。                 \n"
        )
        sys.stdout.flush()
        return False

    return True


# ─────────────── 保存结果 ────────────────────────────────────

def save_result(image_path: Path, raw: str, enhanced: str | None):
    out_dir = Path(__file__).parent / "output"
    out_dir.mkdir(exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = out_dir / f"{image_path.stem}_{ts}.md"

    with open(out, "w", encoding="utf-8") as f:
        f.write(f"# OCR 结果 — {image_path.name}\n\n")
        f.write(f"- 时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"- 图片：`{image_path}`\n\n")
        f.write("## Stage 1 原始 OCR（规则格式化）\n\n```\n")
        f.write(raw)
        f.write("\n```\n\n")
        if enhanced:
            f.write("## Stage 2 AI 增强结果\n\n")
            f.write(enhanced)
            f.write("\n")

    print(f"\n💾  结果已保存：{out}")


# ──────────────────────── 主流程 ─────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="两阶段 OCR：glm-ocr 提取 + 交互确认后 AI 增强（高性能版）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            示例：
              python last.py 1.png
              python last.py 1.png --auto-enhance
              python last.py 1.png --no-enhance
              python last.py 1.png --wait 5
              python last.py 1.png --save
              python last.py 1.png --model mistral

            环境变量：
              OLLAMA_HOST          Ollama 服务地址（默认 http://localhost:11434）
              ENHANCE_MODEL        Stage 2 模型（默认 gemma3:270m）
              OCR_KEEP_ALIVE       OCR 模型保活（默认 15m）
              ENHANCE_KEEP_ALIVE   Stage 2 模型保活（默认 15m）
              OCR_NUM_CTX          OCR 上下文（默认 4096）
              ENHANCE_NUM_CTX      Stage 2 上下文（默认 2048）
              ENHANCE_NUM_PREDICT  Stage 2 最大生成 token（默认 1024）
        """),
    )
    parser.add_argument("image", nargs="?", help="图片路径（可省略交互式选择）")
    parser.add_argument("--auto-enhance", action="store_true", help="不等待，Stage 1 后直接进入 Stage 2")
    parser.add_argument("--no-enhance", action="store_true", help="仅 Stage 1，跳过 Stage 2")
    parser.add_argument("--save", action="store_true", help="结果保存到 output/")
    parser.add_argument(
        "--model",
        default=ENHANCE_MODEL,
        metavar="MODEL",
        help=f"Stage 2 增强模型（默认: {ENHANCE_MODEL}）",
    )
    parser.add_argument("--wait", type=int, default=5, metavar="SEC", help="等待用户确认的秒数（默认: 5）")

    args = parser.parse_args()

    t_global = time.time()
    print(f"\n🚀  任务开始  {_now_str()}")

    image_path = resolve_image_path(args.image) if args.image else pick_image_interactively()

    if image_path.suffix.lower() not in SUPPORTED_EXTS:
        print(f"⚠️  不支持的文件格式：{image_path.suffix}，支持：{', '.join(SUPPORTED_EXTS)}")
        sys.exit(1)

    raw_text = stage1_ocr(image_path)
    rule_text = rule_based_format(raw_text)

    print(f"\n{EQUALS}")
    print("📄  [Stage 1] OCR 结果（规则格式化）")
    print(EQUALS)
    print(rule_text)
    print(EQUALS)

    if args.no_enhance:
        print("\n    [--no-enhance] 已跳过 Stage 2。")
        if args.save:
            save_result(image_path, raw_text, None)
        _print_total(t_global)
        return

    if args.auto_enhance:
        do_enhance = True
        print("\n    [--auto-enhance] 自动进入 Stage 2 AI 增强...")
    else:
        print()
        do_enhance = ask_to_enhance(args.wait)

    if not do_enhance:
        if args.save:
            save_result(image_path, raw_text, None)
        _print_total(t_global)
        return

    enhanced_text = stage2_enhance(rule_text, args.model)

    print(f"\n{EQUALS}")
    print(f"✨  [Stage 2] AI 增强完毕  [{args.model}]")
    print(EQUALS)

    if args.save:
        save_result(image_path, raw_text, enhanced_text)

    _print_total(t_global)


def _print_total(t_start: float):
    elapsed = time.time() - t_start
    print(f"\n{'─' * 60}")
    print(f"🏁  全部完成  {_now_str()}  |  总耗时: {elapsed:.2f} 秒")
    print(f"{'─' * 60}\n")


if __name__ == "__main__":
    main()
