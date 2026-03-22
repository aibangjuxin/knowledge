#!/Users/lex/python/openai/bin/python3
# -*- coding: utf-8 -*-
"""
ocr-ollman-3.py — 两阶段 OCR，Stage 1 立即输出后交互确认是否进入 Stage 2

流程：
  1. [Stage 1] glm-ocr  →  立即打印 OCR 原始结果（规则格式化）
  2. 倒计时 10 秒，等待用户输入 Y —— 超时或其他输入则跳过
  3. [Stage 2] qwen3.5:0.8b  →  AI 格式化 / 语法修复（流式输出）

用法：
  python ocr-ollman-3.py                          # 交互式选图
  python ocr-ollman-3.py 1.png                    # 自动在 ~/Downloads 查找
  python ocr-ollman-3.py /abs/path/img.png        # 绝对路径
  python ocr-ollman-3.py 1.png --auto-enhance     # 不等待，直接进入 Stage 2
  python ocr-ollman-3.py 1.png --no-enhance       # 仅 Stage 1，永远跳过 Stage 2
  python ocr-ollman-3.py 1.png --save             # 结果保存到 output/
  python ocr-ollman-3.py 1.png --model mistral    # 指定 Stage 2 模型
  python ocr-ollman-3.py 1.png --wait 15          # 修改等待秒数（默认 10）

环境变量：
  OLLAMA_HOST     覆盖 Ollama 端点（默认 http://localhost:11434）
  ENHANCE_MODEL   覆盖 Stage 2 模型名（默认 qwen3.5:0.8b）
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
OLLAMA_HOST          = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
OCR_MODEL            = "glm-ocr"
ENHANCE_MODEL        = os.environ.get("ENHANCE_MODEL", "gemma3:270m")
SUPPORTED_EXTS       = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}

OCR_PROMPT = (
    "请识别并提取这张图片中的所有文字内容，尽量保留原始格式，"
    "不要推断或补充原图中没有的信息。"
)

# 精简版 system prompt，减少 token 消耗，提升响应速度
ENHANCE_SYSTEM_PROMPT = """\
你是文本格式化助手。将 OCR 原始文字做如下处理（直接输出结果，不要解释）：
- 将字面量 \\n 替换为真实换行
- JSON → 格式化 JSON，首行加 [FORMAT: JSON]
- 代码 → 格式化，首行加 [FORMAT: <语言>]
- 普通文本 → 修复排版，首行加 [FORMAT: TEXT]
- 修复 OCR 误识别（0/O、1/l 等）
"""

DIVIDER = "─" * 60
EQUALS  = "=" * 60


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
    """将字面量 \\n 换成真实换行，并尝试 JSON pretty-print。"""
    cleaned = text.replace("\\n", "\n").replace("\\t", "\t")

    json_match = re.search(r'(\{[\s\S]*\}|\[[\s\S]*\])', cleaned)
    if json_match:
        try:
            obj = json.loads(json_match.group(1))
            before = cleaned[:json_match.start()].strip()
            after  = cleaned[json_match.end():].strip()
            parts  = []
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
    """Stage 1：glm-ocr 提取原始文字"""
    ollama, client = _get_client()

    print(f"\n{DIVIDER}")
    print(f"🔍  [Stage 1] OCR 提取  →  模型: {OCR_MODEL}")
    print(f"    图片: {image_path.name}  ({image_path.stat().st_size / 1024:.1f} KB)")
    print(f"    Ollama: {OLLAMA_HOST}")
    print(DIVIDER)

    t_start = print_stage_start("Stage 1")

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
            options=ollama.Options(temperature=0.05, top_p=0.9),
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
    print()  # 空行分隔，让流式内容更整洁

    collected_chunks = []
    try:
        stream = client.chat(
            model=model,
            messages=[
                ollama.Message(role="system", content=ENHANCE_SYSTEM_PROMPT),
                ollama.Message(role="user",   content=raw_text),
            ],
            options=ollama.Options(
                temperature=0.1,   # 更低温度，减少"思考"过程，加快确定性输出
                top_p=0.85,
                num_predict=1024,  # 限制最大 token，避免无限生成
            ),
            stream=True,           # ← 关键：启用流式
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

    print()  # 流式结束后换行
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

    # select 等待 stdin 可读（仅 Unix/macOS 有效）
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

    return True  # 超时，默认进入 Stage 2


# ─────────────── 保存结果 ────────────────────────────────────

def save_result(image_path: Path, raw: str, enhanced: str | None):
    out_dir = Path(__file__).parent / "output"
    out_dir.mkdir(exist_ok=True)
    ts  = datetime.now().strftime("%Y%m%d_%H%M%S")
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
        description="两阶段 OCR：glm-ocr 提取 + 交互确认后 AI 增强（流式）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            示例：
              python ocr-ollman-3.py 1.png                 # 标准流程（5 秒确认）
              python ocr-ollman-3.py 1.png --auto-enhance  # 直接进入 Stage 2
              python ocr-ollman-3.py 1.png --no-enhance    # 仅 Stage 1
              python ocr-ollman-3.py 1.png --wait 10       # 等待 10 秒
              python ocr-ollman-3.py 1.png --save          # 保存结果
              python ocr-ollman-3.py 1.png --model mistral # 换 Stage 2 模型
        """),
    )
    parser.add_argument("image",         nargs="?",           help="图片路径（可省略交互式选择）")
    parser.add_argument("--auto-enhance",action="store_true", help="不等待，Stage 1 后直接进入 Stage 2")
    parser.add_argument("--no-enhance",  action="store_true", help="仅 Stage 1，跳过 Stage 2")
    parser.add_argument("--save",        action="store_true", help="结果保存到 output/")
    parser.add_argument("--model",       default=ENHANCE_MODEL, metavar="MODEL",
                        help=f"Stage 2 增强模型（默认: {ENHANCE_MODEL}）")
    parser.add_argument("--wait",        type=int, default=5, metavar="SEC",
                        help="等待用户确认的秒数（默认: 5）")

    args = parser.parse_args()

    # 全局计时
    t_global = time.time()
    print(f"\n🚀  任务开始  {_now_str()}")

    # ── 解析图片路径 ──────────────────────────────────────────
    image_path = resolve_image_path(args.image) if args.image else pick_image_interactively()

    if image_path.suffix.lower() not in SUPPORTED_EXTS:
        print(f"⚠️  不支持的文件格式：{image_path.suffix}，支持：{', '.join(SUPPORTED_EXTS)}")
        sys.exit(1)

    # ── Stage 1: OCR ─────────────────────────────────────────
    raw_text  = stage1_ocr(image_path)
    rule_text = rule_based_format(raw_text)

    print(f"\n{EQUALS}")
    print("📄  [Stage 1] OCR 结果（规则格式化）")
    print(EQUALS)
    print(rule_text)
    print(EQUALS)

    # ── 判断是否进入 Stage 2 ──────────────────────────────────
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

    # ── Stage 2: AI 增强（流式）──────────────────────────────
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
