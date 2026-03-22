#!/Users/lex/python/openai/bin/python3
# -*- coding: utf-8 -*-
"""
ocr-ollama-3-enhance.py — 极限优化版的两阶段 OCR 脚本

架构改进与并发增强点：
  1. 真正懒加载：延迟所有的重量级包（ollama、json、re 等）的 import，实现终端毫秒级启动，不再卡半秒。
  2. Ollama 提速参数配置：加入了 keep_alive（告别模型卸载的冷启动）、num_ctx（减少极长的无用请求负担）、num_thread（多核CPU利用）。
  3. 异步架构底座 (Asyncio)：将底层通讯改为 asyncio。
  4. 支持批处理 `--batch`：并发发威的地方。如果是文件夹，并发发出 OCR 请求并同时收集结果！

用法示例：
  python ocr-ollama-3-enhance.py                          # 交互式单图处理 (0延迟启动)
  python ocr-ollama-3-enhance.py 1.png                    # 处理单图及 5s 交互确认
  python ocr-ollama-3-enhance.py 1.png --auto-enhance     # 取消交互直接一条龙
  python ocr-ollama-3-enhance.py --batch ~/Downloads/img  # 【并发威力】并发处理整个文件夹
"""

import sys
import os
import time
import select
import argparse
import textwrap
import asyncio
import threading
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
    sys.exit(1)


def pick_image_interactively() -> Path:
    if not DEFAULT_DOWNLOAD_DIR.exists():
        print(f"❌  默认目录不存在：{DEFAULT_DOWNLOAD_DIR}")
        sys.exit(1)

    images = sorted(
        (f for f in DEFAULT_DOWNLOAD_DIR.iterdir() if f.is_file() and f.suffix.lower() in SUPPORTED_EXTS),
        key=lambda x: x.stat().st_mtime, 
        reverse=True  # 按最新的图片排在前面
    )
    if not images:
        print(f"⚠️  {DEFAULT_DOWNLOAD_DIR} 中未找到支持的图片。")
        sys.exit(1)

    print(f"\n📂  默认目录：{DEFAULT_DOWNLOAD_DIR}")
    for i, img in enumerate(images[:20], 1):
        size_kb = img.stat().st_size / 1024
        print(f"    [{i:2d}]  {img.name}  ({size_kb:.1f} KB)")
    if len(images) > 20:
        print("    ... (仅显示最近 20 张)")
    print()
    raw = input("    请输入序号或文件名（直接回车使用第 1 张）：").strip()

    if raw == "":
        return images[0]
    if raw.isdigit():
        idx = int(raw) - 1
        if 0 <= idx < len(images):
            return images[idx]
        print(f"❌  序号超出范围")
        sys.exit(1)
    return resolve_image_path(raw)


# ─────────────── 规则处理 (懒加载 json/re 提速) ───────────────

def rule_based_format(text: str) -> str:
    """内部 import json/re，使得没走到这里时脚本启动完全无粘滞感"""
    import json
    import re
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


# ─────────────── 核心异步模型调用 ────────────────────────────

def _get_async_client():
    try:
        from ollama import AsyncClient
        return AsyncClient(host=OLLAMA_HOST)
    except ImportError:
        print("❌  未安装 ollama 库：")
        print(f"    {sys.executable} -m pip install ollama")
        sys.exit(1)


async def stage1_ocr_async(client, image_path: Path) -> str:
    """Stage 1: 异步 OCR (附加最高效的参数)"""
    from ollama import Message, Image, Options, ResponseError
    print(f"🔍  [Stage 1] 提取开始: {image_path.name}")
    
    with open(image_path, "rb") as f:
        img_bytes = f.read()

    try:
        response = await client.chat(
            model=OCR_MODEL,
            messages=[Message(role="user", content=OCR_PROMPT, images=[Image(value=img_bytes)])],
            options=Options(
                temperature=0.05, 
                top_p=0.9,
                num_ctx=4096, 
                num_thread=max(1, os.cpu_count() or 4)
            ),
            keep_alive="15m"  # 防止频繁冷启动
        )
        return response.message.content
    except ResponseError as e:
        print(f"❌  OCR 错误 ({image_path.name})：{e.error}")
        return ""


async def stage2_enhance_async(client, raw_text: str, model: str, streaming: bool = False) -> str:
    """Stage 2: 异步 AI 强化 (可选流式)"""
    from ollama import Message, Options, ResponseError
    try:
        if streaming:
            stream = await client.chat(
                model=model,
                messages=[
                    Message(role="system", content=ENHANCE_SYSTEM_PROMPT),
                    Message(role="user", content=raw_text),
                ],
                options=Options(
                    temperature=0.1, 
                    top_p=0.85, 
                    num_predict=2048, 
                    num_ctx=4096,
                    num_thread=max(1, os.cpu_count() or 4)
                ),
                keep_alive="15m",
                stream=True
            )
            collected = []
            async for chunk in stream:
                token = chunk.message.content
                if token:
                    sys.stdout.write(token)
                    sys.stdout.flush()
                    collected.append(token)
            return "".join(collected)
        else:
            response = await client.chat(
                model=model,
                messages=[
                    Message(role="system", content=ENHANCE_SYSTEM_PROMPT),
                    Message(role="user", content=raw_text),
                ],
                options=Options(
                    temperature=0.1, 
                    top_p=0.85, 
                    num_predict=2048, 
                    num_ctx=4096,
                    num_thread=max(1, os.cpu_count() or 4)
                ),
                keep_alive="15m"
            )
            return response.message.content
    except ResponseError as e:
        print(f"\n⚠️  增强错误：{e.error}")
        return raw_text


# ──────────────── 倒计时交互确认 ─────────────────────────────

def ask_to_enhance(wait_seconds: int) -> bool:
    """
    在终端打印倒计时。接收任何输入就返回 False (退出 Stage 2)
    """
    stop_event = threading.Event()

    def countdown():
        for remaining in range(wait_seconds, 0, -1):
            if stop_event.is_set():
                return
            sys.stdout.write(f"\r    ⏳ 输入任意字符并回车退出 AI 增强；不输入将在 [{remaining}s] 后继续... ")
            sys.stdout.flush()
            time.sleep(1)
        if not stop_event.is_set():
            sys.stdout.write("\r    ✅ 已超时，默认进入 Stage 2 AI 增强。                         \n")
            sys.stdout.flush()

    t = threading.Thread(target=countdown, daemon=True)
    t.start()

    ready, _, _ = select.select([sys.stdin], [], [], wait_seconds)

    stop_event.set()
    t.join(timeout=0.5)

    if ready:
        user_input = sys.stdin.readline().strip()
        sys.stdout.write(f"\r    ⏭️  输入 [{user_input}]，手动跳过 Stage 2 增强。                 \n")
        sys.stdout.flush()
        return False

    return True  # 超时，默认进入 Stage 2


# ─────────────────────── 并发批量管线 (__核心黑科技__) ────────

async def process_batch(directory: Path, model: str):
    """同时发射整个文件夹的图片给 Ollama 进行并发处理"""
    images = [f for f in directory.iterdir() if f.is_file() and f.suffix.lower() in SUPPORTED_EXTS]
    if not images:
        print(f"文件夹中未找到支持的图片。")
        return
    
    print(f"🚀  开始批量并发处理 {len(images)} 张图片...\n")
    client = _get_async_client()
    
    # 全部并发跑 OCR (考验电脑显存和算力的时候到了)
    start_time = time.time()
    task_ocr = [stage1_ocr_async(client, img) for img in images]
    raw_results = await asyncio.gather(*task_ocr)
    print(f"✅  所有图片 Stage 1 (OCR) 完成！耗时: {time.time()-start_time:.2f}s")

    # 规则处理
    rule_results = [rule_based_format(r) for r in raw_results]

    # 并发跑 Stage 2 (由于批量输出，这里全部使用非流式)
    start_s2 = time.time()
    print(f"\n✨  开始并发批量进入 Stage 2 增强...")
    task_s2 = [stage2_enhance_async(client, r, model, streaming=False) for r in rule_results]
    enhanced_results = await asyncio.gather(*task_s2)
    print(f"✅  所有图片 Stage 2 (强化) 完成！耗时: {time.time()-start_s2:.2f}s")
    
    # 集中保存
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path(__file__).parent / f"output_batch_{ts}"
    out_dir.mkdir(exist_ok=True, parents=True)
    for img, r, e in zip(images, raw_results, enhanced_results):
        out = out_dir / f"{img.stem}.md"
        with open(out, "w", encoding="utf-8") as f:
            f.write(f"# OCR — {img.name}\n\n## 原文\n```\n{r}\n```\n\n## 增强\n{e}\n")
    print(f"\n💾  所有结果已批量保存至：{out_dir}")


# ─────────────────────── 单图线 ────────────────────────────

async def process_single(image_path: Path, args):
    client = _get_async_client()
    
    print(f"\n{DIVIDER}")
    print(f"🔍  [Stage 1] OCR 提取  →  模型: {OCR_MODEL}")
    print(f"    图片: {image_path.name}  ({image_path.stat().st_size / 1024:.1f} KB)")
    print(f"    Ollama: {OLLAMA_HOST}")
    print(DIVIDER)

    t_start = print_stage_start("Stage 1")
    raw_text = await stage1_ocr_async(client, image_path)
    print_stage_end(t_start, "Stage 1 OCR")

    rule_text = rule_based_format(raw_text)
    print(f"\n{EQUALS}\n📄  [Stage 1] OCR 结果（规则格式化）\n{EQUALS}")
    print(rule_text)
    print(EQUALS)

    if args.no_enhance:
        return image_path, raw_text, None

    if args.auto_enhance:
        do_enhance = True
        print("\n    [--auto-enhance] 自动进入 Stage 2 AI 增强...")
    else:
        print()
        do_enhance = ask_to_enhance(args.wait)
        
    if not do_enhance:
        return image_path, raw_text, None

    print(f"\n{DIVIDER}")
    print(f"✨  [Stage 2] AI 增强   →  模型: {args.model}  [流式输出]")
    print(DIVIDER)
    t_start2 = print_stage_start("Stage 2")
    print()

    # 单图场景下，仍然保持流式写入界面，确保最棒的交互体验
    enhanced_text = await stage2_enhance_async(client, rule_text, args.model, streaming=True)

    print()
    print_stage_end(t_start2, f"Stage 2 [{args.model}]")
    print(f"\n{EQUALS}\n✨  [Stage 2] AI 增强完毕\n{EQUALS}")

    return image_path, raw_text, enhanced_text


# ──────────────────────── 主干 ─────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="极限提速版两阶段 OCR：基于 Asyncio 并发架构及 Ollama 模型调优",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            示例：
              python ocr-ollama-3-enhance.py                        # 标准单图流程
              python ocr-ollama-3-enhance.py 1.png                  
              python ocr-ollama-3-enhance.py --batch ~/images       # 【高能】并发整个文件夹
        """),
    )
    parser.add_argument("image",         nargs="?",           help="单图片路径")
    parser.add_argument("--batch",       metavar="DIR",       help="使用并发处理指定文件夹下的所有图片")
    parser.add_argument("--auto-enhance",action="store_true", help="不等待，直接进入 Stage 2")
    parser.add_argument("--no-enhance",  action="store_true", help="仅 Stage 1，跳过 Stage 2")
    parser.add_argument("--save",        action="store_true", help="保存单例结果到 output/")
    parser.add_argument("--model",       default=ENHANCE_MODEL, help=f"Stage 2 模型 (默认: {ENHANCE_MODEL})")
    parser.add_argument("--wait",        type=int, default=5, help="默认倒数确认时间")

    args = parser.parse_args()

    t_global = time.time()
    print(f"\n🚀  任务启动  {_now_str()}")

    if args.batch:
        p = Path(args.batch).expanduser().resolve()
        if not p.is_dir():
            print(f"❌  批量处理目录不存在：{p}")
            sys.exit(1)
        asyncio.run(process_batch(p, args.model))
    else:
        # 单图路线
        image_path = resolve_image_path(args.image) if args.image else pick_image_interactively()
        if image_path.suffix.lower() not in SUPPORTED_EXTS:
            print(f"⚠️  不支持的文件格式：{image_path.suffix}")
            sys.exit(1)
        
        _, raw_text, enhanced_text = asyncio.run(process_single(image_path, args))

        if args.save:
            out_dir = Path(__file__).parent / "output"
            out_dir.mkdir(exist_ok=True)
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            out = out_dir / f"{image_path.stem}_{ts}.md"
            with open(out, "w", encoding="utf-8") as f:
                f.write(f"# OCR — {image_path.name}\n\n## 原文\n```\n{raw_text}\n```\n\n")
                if enhanced_text:
                    f.write(f"## 增强\n{enhanced_text}\n")
            print(f"\n💾  结果已保存：{out}")

    print(f"\n{'─' * 60}")
    print(f"🏁  全面完成  {_now_str()}  |  总流转耗时: {time.time() - t_global:.2f} 秒")
    print(f"{'─' * 60}\n")


if __name__ == "__main__":
    main()
