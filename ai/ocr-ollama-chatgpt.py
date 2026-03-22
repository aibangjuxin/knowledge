#!/Users/lex/python/openai/bin/python3
# -*- coding: utf-8 -*-
"""
ocr-ollama-chatgpt.py

基于 ocr-ollama-3.py 的稳定逻辑做轻量增强：
  1. [Stage 1] glm-ocr  →  立即打印 OCR 原始结果（规则格式化）
  2. 倒计时等待；默认自动进入 Stage 2，输入任意字符则退出
  3. [Stage 2] 本地 Ollama 模型  →  AI 格式化 / 语法修复

相较 ocr-ollama-3.py 的调整：
  - 默认等待秒数改为 10
  - 每个阶段打印开始时间 / 结束时间 / 用时
  - 总流程打印开始时间 / 结束时间 / 总用时
  - 保持 Stage 2 为非流式调用，优先稳定输出
  - 为本地小模型增加少量可控参数

用法：
  python ocr-ollama-chatgpt.py
  python ocr-ollama-chatgpt.py 1.png
  python ocr-ollama-chatgpt.py 1.png --auto-enhance
  python ocr-ollama-chatgpt.py 1.png --no-enhance
  python ocr-ollama-chatgpt.py 1.png --save
  python ocr-ollama-chatgpt.py 1.png --model gemma3:270m
  python ocr-ollama-chatgpt.py 1.png --wait 10
"""

import sys
import os
import json
import re
import select
import threading
import time
import argparse
import textwrap
from pathlib import Path
from datetime import datetime

# ── 默认配置 ────────────────────────────────────────────────
DEFAULT_DOWNLOAD_DIR = Path("/Users/lex/Downloads")
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
OCR_MODEL = "glm-ocr"
ENHANCE_MODEL = os.environ.get("ENHANCE_MODEL", "gemma3:270m")
SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}

OCR_PROMPT = (
    "请识别并提取这张图片中的所有文字内容，尽量保留原始格式，"
    "不要推断或补充原图中没有的信息。"
)

ENHANCE_SYSTEM_PROMPT = """\
你是一个精准的文本格式化助手。用户会给你一段由 OCR 识别出来的原始文字。请做以下处理：
- 将字面量 \\n 替换为真实换行（如果还有的话）
- 如果内容是 JSON：输出格式化后的合法 JSON（2 空格缩进），并在最前加注释 [FORMAT: JSON]
- 如果内容是 YAML / HCL / Python / Shell 等代码：格式化并加注释 [FORMAT: <语言>]
- 如果是普通文本：修复换行排版，加注释 [FORMAT: TEXT]
- 修复明显的 OCR 误识别（如 0/O、1/l 混淆等）
- 只输出处理后内容，不要解释，不要添加原文中没有的信息。
"""

DIVIDER = "─" * 60
EQUALS = "=" * 60


def fmt_ts(ts: float | None = None) -> str:
    if ts is None:
        ts = time.time()
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")


def print_stage_header(title: str, model: str | None = None):
    print(f"\n{DIVIDER}")
    if model:
        print(f"{title}  →  模型: {model}")
    else:
        print(title)
    print(f"    开始时间: {fmt_ts()}")
    print(DIVIDER)


def print_stage_footer(started_at: float, label: str):
    ended_at = time.time()
    print(f"    结束时间: {fmt_ts(ended_at)}")
    print(f"    ⏱️  {label} 用时：{ended_at - started_at:.1f}s")


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


# ─────────────────── 规则后处理 ──────────────────────────────

def rule_based_format(text: str) -> str:
    cleaned = text.replace("\\n", "\n").replace("\\t", "\t")

    json_match = re.search(r'(\{[\s\S]*\}|\[[\s\S]*\])', cleaned)
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

def _get_client():
    try:
        import ollama
        return ollama, ollama.Client(host=OLLAMA_HOST)
    except ImportError:
        print("❌  未安装 ollama 库：")
        print(f"    {sys.executable} -m pip install ollama")
        sys.exit(1)


def stage1_ocr(image_path: Path) -> str:
    ollama, client = _get_client()
    started_at = time.time()

    print_stage_header("🔍  [Stage 1] OCR 提取", OCR_MODEL)
    print(f"    图片: {image_path.name}  ({image_path.stat().st_size / 1024:.1f} KB)")
    print(f"    Ollama: {OLLAMA_HOST}")

    with open(image_path, "rb") as f:
        img_bytes = f.read()

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
                num_ctx=4096,
                num_thread=max(1, os.cpu_count() or 4),
            ),
            keep_alive="10m",
        )
    except ollama.ResponseError as e:
        print(f"❌  OCR 错误：{e.status_code} — {e.error}")
        print(f"    确认 {OCR_MODEL} 已拉取：ollama list")
        sys.exit(1)

    print_stage_footer(started_at, "Stage 1")
    return response.message.content


def stage2_enhance(raw_text: str, model: str) -> tuple[str, bool]:
    ollama, client = _get_client()
    started_at = time.time()

    print_stage_header("✨  [Stage 2] AI 增强", model)
    print(f"    输入长度: {len(raw_text)} chars")

    try:
        response = client.chat(
            model=model,
            messages=[
                ollama.Message(role="system", content=ENHANCE_SYSTEM_PROMPT),
                ollama.Message(role="user", content=raw_text),
            ],
            options=ollama.Options(
                temperature=0.1,
                top_p=0.9,
                num_ctx=4096,
                num_predict=2048,
                num_thread=max(1, os.cpu_count() or 4),
            ),
            keep_alive="15m",
        )
    except ollama.ResponseError as e:
        print(f"⚠️  增强模型错误：{e.status_code} — {e.error}")
        print("    跳过 AI 增强，返回规则处理结果。")
        print_stage_footer(started_at, "Stage 2")
        return raw_text, False

    result = (response.message.content or "").strip()

    if not result:
        print("⚠️  Stage 2 返回为空，回退到 Stage 1 规则格式化结果。")
        print_stage_footer(started_at, "Stage 2")
        return raw_text, False

    print_stage_footer(started_at, "Stage 2")
    return result, True


# ──────────────── 10 秒倒计时交互确认 ────────────────────────

def ask_to_enhance(wait_seconds: int) -> bool:
    """
    在终端打印倒计时。
    - 不输入，超时后默认进入 Stage 2
    - 输入任意字符并回车，则退出 Stage 2
    使用 select 实现非阻塞 stdin 读取（macOS / Linux）。
    """
    if not sys.stdin.isatty():
        print("    ℹ️  当前不是交互终端，默认进入 Stage 2。")
        return True

    started_at = time.time()
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
                "\r    ✅ 已超时，默认继续进入 Stage 2。                         \n"
            )
            sys.stdout.flush()

    t = threading.Thread(target=countdown, daemon=True)
    t.start()

    ready, _, _ = select.select([sys.stdin], [], [], wait_seconds)

    stop_event.set()
    t.join(timeout=0.5)

    if ready:
        user_input = sys.stdin.readline().strip()
        if user_input:
            sys.stdout.write(
                f"\r    ⏭️  输入 [{user_input}]，退出 Stage 2 增强。              \n"
            )
            sys.stdout.flush()
            print_stage_footer(started_at, "等待确认")
            return False
        sys.stdout.write("\r    ✅ 已确认，继续进入 Stage 2 AI 增强...                \n")
        sys.stdout.flush()
        print_stage_footer(started_at, "等待确认")
        return True

    print_stage_footer(started_at, "等待确认")
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
    total_started_at = time.time()

    parser = argparse.ArgumentParser(
        description="两阶段 OCR：glm-ocr 提取 + 交互确认后 AI 增强",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            示例：
              python ocr-ollama-chatgpt.py 1.png                 # 标准流程（5 秒确认）
              python ocr-ollama-chatgpt.py 1.png --auto-enhance  # 直接进入 Stage 2
              python ocr-ollama-chatgpt.py 1.png --no-enhance    # 仅 Stage 1
              python ocr-ollama-chatgpt.py 1.png --wait 10       # 等待 10 秒
              python ocr-ollama-chatgpt.py 1.png --save          # 保存结果
              python ocr-ollama-chatgpt.py 1.png --model gemma3:270m
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
    parser.add_argument(
        "--wait",
        type=int,
        default=5,
        metavar="SEC",
        help="等待用户确认的秒数（默认: 5）",
    )

    args = parser.parse_args()

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
        print(f"\n🕒  总开始时间: {fmt_ts(total_started_at)}")
        print(f"🕒  总结束时间: {fmt_ts()}")
        print(f"⏱️  总用时: {time.time() - total_started_at:.1f}s")
        if args.save:
            save_result(image_path, raw_text, None)
        return

    if args.auto_enhance:
        do_enhance = True
        print("\n    [--auto-enhance] 自动进入 Stage 2 AI 增强...")
    else:
        print()
        do_enhance = ask_to_enhance(args.wait)

    if not do_enhance:
        print(f"\n🕒  总开始时间: {fmt_ts(total_started_at)}")
        print(f"🕒  总结束时间: {fmt_ts()}")
        print(f"⏱️  总用时: {time.time() - total_started_at:.1f}s")
        if args.save:
            save_result(image_path, raw_text, None)
        return

    enhanced_text, stage2_ok = stage2_enhance(rule_text, args.model)

    print(f"\n{EQUALS}")
    if stage2_ok:
        print(f"✨  [Stage 2] AI 增强结果  [{args.model}]")
    else:
        print(f"✨  [Stage 2] 回退结果  [{args.model}]")
    print(EQUALS)
    print(enhanced_text)
    print(EQUALS)

    print(f"\n🕒  总开始时间: {fmt_ts(total_started_at)}")
    print(f"🕒  总结束时间: {fmt_ts()}")
    print(f"⏱️  总用时: {time.time() - total_started_at:.1f}s")

    if args.save:
        save_result(image_path, raw_text, enhanced_text)


if __name__ == "__main__":
    main()
