#!/Users/lex/python/openai/bin/python3
# -*- coding: utf-8 -*-
"""
ocr-ollama-4-turbo.py — 基于 v3 的全链路提速版

提速改进点（不改变原有逻辑）：
  1. uvloop        — 替换默认事件循环，底层用 libuv，异步吞吐提升 30-50%
  2. aiofiles      — 图片读取改为真正的异步非阻塞 I/O，不再卡住事件循环
  3. Semaphore     — 批量并发加令牌桶限流，防止 Ollama 排队反而更慢
  4. ProcessPool   — 规则格式化（CPU 密集）扔进进程池并行跑，多核全利用
  5. 懒加载保留    — uvloop / aiofiles 也做懒加载检测，缺包自动提示安装

依赖安装（均为可选，缺少时自动降级）：
  pip install uvloop aiofiles

用法（与 v3 完全相同）：
  python ocr-ollama-4-turbo.py                          # 交互式单图
  python ocr-ollama-4-turbo.py 1.png
  python ocr-ollama-4-turbo.py 1.png --auto-enhance
  python ocr-ollama-4-turbo.py --batch ~/Downloads/img  # 并发批量
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
from concurrent.futures import ProcessPoolExecutor

# ── 默认配置 ────────────────────────────────────────────────
DEFAULT_DOWNLOAD_DIR = Path("/Users/lex/Downloads")
OLLAMA_HOST          = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
OCR_MODEL            = "glm-ocr"
ENHANCE_MODEL        = os.environ.get("ENHANCE_MODEL", "gemma3:270m")
SUPPORTED_EXTS       = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}

# 批量并发限流：同时最多向 Ollama 发多少个请求
# 超过这个数量 Ollama 内部会排队，并发数太大反而更慢
BATCH_CONCURRENCY = int(os.environ.get("BATCH_CONCURRENCY", "4"))

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


# ─────────────── 提速 #1: uvloop 懒加载安装 ──────────────────

def _install_uvloop():
    """尝试启用 uvloop，缺包时自动提示，不强制退出"""
    try:
        import uvloop
        asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
        print("⚡  uvloop 已启用（事件循环提速 ~30-50%）")
        return True
    except ImportError:
        print("ℹ️   uvloop 未安装，使用默认事件循环")
        print(f"    可选安装: {sys.executable} -m pip install uvloop")
        return False


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
        (f for f in DEFAULT_DOWNLOAD_DIR.iterdir()
         if f.is_file() and f.suffix.lower() in SUPPORTED_EXTS),
        key=lambda x: x.stat().st_mtime,
        reverse=True
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
        print("❌  序号超出范围")
        sys.exit(1)
    return resolve_image_path(raw)


# ─────────────── 提速 #4: 规则处理放进进程池 ─────────────────
# 注意：该函数必须定义在模块顶层，才能被 ProcessPoolExecutor pickle

def rule_based_format(text: str) -> str:
    """CPU 密集型规则处理（可在进程池中并行）"""
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


async def rule_based_format_async(loop: asyncio.AbstractEventLoop,
                                   executor: ProcessPoolExecutor,
                                   text: str) -> str:
    """将同步 CPU 密集型规则处理卸载到进程池，不阻塞事件循环"""
    return await loop.run_in_executor(executor, rule_based_format, text)


# ─────────────── 核心异步模型调用 ────────────────────────────

def _get_async_client():
    try:
        from ollama import AsyncClient
        return AsyncClient(host=OLLAMA_HOST)
    except ImportError:
        print("❌  未安装 ollama 库：")
        print(f"    {sys.executable} -m pip install ollama")
        sys.exit(1)


# ─────────────── 提速 #2: aiofiles 异步图片读取 ───────────────

async def _read_image_bytes(image_path: Path) -> bytes:
    """优先使用 aiofiles 异步读取，缺包降级为同步读取"""
    try:
        import aiofiles
        async with aiofiles.open(image_path, "rb") as f:
            return await f.read()
    except ImportError:
        # 降级：用线程池包装同步读取，至少不直接阻塞事件循环
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, image_path.read_bytes)


async def stage1_ocr_async(client, image_path: Path) -> str:
    """Stage 1: 异步 OCR（aiofiles 读取 + 附加最高效参数）"""
    from ollama import Message, Image, Options, ResponseError
    print(f"🔍  [Stage 1] 提取开始: {image_path.name}")

    # 提速 #2: 异步非阻塞读取图片
    img_bytes = await _read_image_bytes(image_path)

    try:
        response = await client.chat(
            model=OCR_MODEL,
            messages=[Message(role="user", content=OCR_PROMPT,
                              images=[Image(value=img_bytes)])],
            options=Options(
                temperature=0.05,
                top_p=0.9,
                num_ctx=4096,
                num_thread=max(1, os.cpu_count() or 4)
            ),
            keep_alive="15m"
        )
        return response.message.content
    except ResponseError as e:
        print(f"❌  OCR 错误 ({image_path.name})：{e.error}")
        return ""


async def stage2_enhance_async(client, raw_text: str, model: str,
                                streaming: bool = False) -> str:
    """Stage 2: 异步 AI 强化（可选流式）"""
    from ollama import Message, Options, ResponseError
    try:
        opts = Options(
            temperature=0.1,
            top_p=0.85,
            num_predict=2048,
            num_ctx=4096,
            num_thread=max(1, os.cpu_count() or 4)
        )
        msgs = [
            Message(role="system", content=ENHANCE_SYSTEM_PROMPT),
            Message(role="user",   content=raw_text),
        ]
        if streaming:
            stream = await client.chat(
                model=model, messages=msgs, options=opts,
                keep_alive="15m", stream=True
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
                model=model, messages=msgs, options=opts, keep_alive="15m"
            )
            return response.message.content
    except ResponseError as e:
        print(f"\n⚠️  增强错误：{e.error}")
        return raw_text


# ──────────────── 倒计时交互确认 ─────────────────────────────

def ask_to_enhance(wait_seconds: int) -> bool:
    stop_event = threading.Event()

    def countdown():
        for remaining in range(wait_seconds, 0, -1):
            if stop_event.is_set():
                return
            sys.stdout.write(
                f"\r    ⏳ 输入任意字符并回车退出 AI 增强；"
                f"不输入将在 [{remaining}s] 后继续... "
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


# ─────────── 提速 #3: 并发批量 + Semaphore 令牌桶 ────────────

async def process_batch(directory: Path, model: str):
    """
    并发处理整个文件夹，但用 Semaphore 限流防止 Ollama 排队。
    规则格式化走 ProcessPoolExecutor 多核并行。
    """
    images = [
        f for f in directory.iterdir()
        if f.is_file() and f.suffix.lower() in SUPPORTED_EXTS
    ]
    if not images:
        print("文件夹中未找到支持的图片。")
        return

    print(f"🚀  开始批量并发处理 {len(images)} 张图片")
    print(f"    并发限制: {BATCH_CONCURRENCY}（可通过 BATCH_CONCURRENCY 环境变量调整）\n")

    client    = _get_async_client()
    semaphore = asyncio.Semaphore(BATCH_CONCURRENCY)  # 提速 #3
    loop      = asyncio.get_event_loop()

    # --- Stage 1: 并发限流 OCR ---
    async def ocr_with_limit(img: Path) -> str:
        async with semaphore:
            return await stage1_ocr_async(client, img)

    start_time = time.time()
    raw_results = await asyncio.gather(*[ocr_with_limit(img) for img in images])
    print(f"✅  所有图片 Stage 1 (OCR) 完成！耗时: {time.time() - start_time:.2f}s")

    # --- 规则格式化: ProcessPoolExecutor 多核并行（提速 #4）---
    with ProcessPoolExecutor(max_workers=os.cpu_count()) as executor:
        rule_tasks   = [rule_based_format_async(loop, executor, r) for r in raw_results]
        rule_results = await asyncio.gather(*rule_tasks)
    print(f"✅  规则格式化完成（多核并行）")

    # --- Stage 2: 并发限流 AI 强化 ---
    async def enhance_with_limit(text: str) -> str:
        async with semaphore:
            return await stage2_enhance_async(client, text, model, streaming=False)

    start_s2 = time.time()
    print(f"\n✨  开始并发批量进入 Stage 2 增强...")
    enhanced_results = await asyncio.gather(
        *[enhance_with_limit(r) for r in rule_results]
    )
    print(f"✅  所有图片 Stage 2 (强化) 完成！耗时: {time.time() - start_s2:.2f}s")

    # --- 保存 ---
    ts      = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path(__file__).parent / f"output_batch_{ts}"
    out_dir.mkdir(exist_ok=True, parents=True)
    for img, r, e in zip(images, raw_results, enhanced_results):
        out = out_dir / f"{img.stem}.md"
        with open(out, "w", encoding="utf-8") as f:
            f.write(
                f"# OCR — {img.name}\n\n"
                f"## 原文\n```\n{r}\n```\n\n"
                f"## 增强\n{e}\n"
            )
    print(f"\n💾  所有结果已批量保存至：{out_dir}")


# ─────────────────────── 单图线 ────────────────────────────

async def process_single(image_path: Path, args):
    client = _get_async_client()
    loop   = asyncio.get_event_loop()

    print(f"\n{DIVIDER}")
    print(f"🔍  [Stage 1] OCR 提取  →  模型: {OCR_MODEL}")
    print(f"    图片: {image_path.name}  ({image_path.stat().st_size / 1024:.1f} KB)")
    print(f"    Ollama: {OLLAMA_HOST}")
    print(DIVIDER)

    t_start  = print_stage_start("Stage 1")
    raw_text = await stage1_ocr_async(client, image_path)
    print_stage_end(t_start, "Stage 1 OCR")

    # 规则格式化（单图时数据量小，进程池开销 > 收益，直接同步调用）
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

    enhanced_text = await stage2_enhance_async(
        client, rule_text, args.model, streaming=True
    )

    print()
    print_stage_end(t_start2, f"Stage 2 [{args.model}]")
    print(f"\n{EQUALS}\n✨  [Stage 2] AI 增强完毕\n{EQUALS}")

    return image_path, raw_text, enhanced_text


# ──────────────────────── 主干 ─────────────────────────────

def main():
    # 提速 #1: 尽早启用 uvloop（在任何 asyncio 调用前）
    _install_uvloop()

    parser = argparse.ArgumentParser(
        description="极限提速版两阶段 OCR v4：uvloop + aiofiles + Semaphore + ProcessPool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            示例：
              python ocr-ollama-4-turbo.py                        # 标准单图流程
              python ocr-ollama-4-turbo.py 1.png
              python ocr-ollama-4-turbo.py --batch ~/images       # 并发整个文件夹
            环境变量：
              OLLAMA_HOST        Ollama 服务地址（默认 http://localhost:11434）
              ENHANCE_MODEL      Stage 2 模型（默认 gemma3:270m）
              BATCH_CONCURRENCY  批量并发数（默认 4）
        """),
    )
    parser.add_argument("image",          nargs="?",          help="单图片路径")
    parser.add_argument("--batch",        metavar="DIR",      help="并发处理指定文件夹下的所有图片")
    parser.add_argument("--auto-enhance", action="store_true", help="不等待，直接进入 Stage 2")
    parser.add_argument("--no-enhance",   action="store_true", help="仅 Stage 1，跳过 Stage 2")
    parser.add_argument("--save",         action="store_true", help="保存单例结果到 output/")
    parser.add_argument("--model",        default=ENHANCE_MODEL,
                        help=f"Stage 2 模型 (默认: {ENHANCE_MODEL})")
    parser.add_argument("--wait",         type=int, default=5, help="倒数确认等待秒数")

    args     = parser.parse_args()
    t_global = time.time()
    print(f"\n🚀  任务启动  {_now_str()}")

    if args.batch:
        p = Path(args.batch).expanduser().resolve()
        if not p.is_dir():
            print(f"❌  批量处理目录不存在：{p}")
            sys.exit(1)
        asyncio.run(process_batch(p, args.model))
    else:
        image_path = (
            resolve_image_path(args.image) if args.image
            else pick_image_interactively()
        )
        if image_path.suffix.lower() not in SUPPORTED_EXTS:
            print(f"⚠️  不支持的文件格式：{image_path.suffix}")
            sys.exit(1)

        _, raw_text, enhanced_text = asyncio.run(process_single(image_path, args))

        if args.save:
            out_dir = Path(__file__).parent / "output"
            out_dir.mkdir(exist_ok=True)
            ts  = datetime.now().strftime("%Y%m%d_%H%M%S")
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