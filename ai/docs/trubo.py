#!/Users/lex/python/openai/bin/python3
# -*- coding: utf-8 -*-
"""
trubo.py

一个偏“稳态优先”的混合版脚本：
- 单图 / 大图：使用 ocr-ollama-3.py 的同步稳定逻辑
- 批量：保留 turbo 思路，但改为线程池 + 同步 Client，避免 AsyncClient 在大图场景下更脆

为什么新建这个脚本：
- ocr-ollama-3.py 读大图稳定
- ocr-trubo.py 在大图下更容易失败
- 所以这个版本优先保证“大图单张能跑通”，再保留适度的批处理能力

特性：
  1. Stage 1 立即输出 OCR 结果（规则格式化）
  2. 默认 5 秒后自动进入 Stage 2；输入任意字符并回车则跳过
  3. 每个阶段打印开始时间 / 结束时间 / 用时
  4. 支持 --batch，但并发方式更保守，默认并发数较低

用法：
  python trubo.py
  python trubo.py 1.png
  python trubo.py 1.png --auto-enhance
  python trubo.py 1.png --no-enhance
  python trubo.py 1.png --save
  python trubo.py --batch ~/Downloads/images
"""

import argparse
import json
import os
import re
import select
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

# ── 默认配置 ────────────────────────────────────────────────
DEFAULT_DOWNLOAD_DIR = Path("/Users/lex/Downloads")
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
OCR_MODEL = "glm-ocr"
ENHANCE_MODEL = os.environ.get("ENHANCE_MODEL", "gemma3:270m")
SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}
DEFAULT_WAIT_SECONDS = 5
BATCH_CONCURRENCY = int(os.environ.get("BATCH_CONCURRENCY", "2"))
# 我本地有些图是2257x2114的看起来有些大，所以默认设置成2048，好像1536可以处理
MAX_IMAGE_SIDE = int(os.environ.get("OCR_MAX_IMAGE_SIDE", "1536"))
ALIGNMENT = int(os.environ.get("OCR_IMAGE_ALIGNMENT", "32"))

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


# ─────────────── 时间工具 ───────────────────────────────────

def _now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def print_stage_start(label: str) -> float:
    t = time.time()
    print(f"    ⏱️  开始时间: {_now_str()}  [{label}]")
    return t


def print_stage_end(t_start: float, label: str = ""):
    elapsed = time.time() - t_start
    suffix = f"  [{label}]" if label else ""
    print(f"    ✅  结束时间: {_now_str()}{suffix}")
    print(f"    ⏱️  耗　　时: {elapsed:.2f} 秒")


def _parse_sips_dimension(output: str, key: str) -> int | None:
    pattern = rf"{re.esabje(key)}:\s*(\d+)"
    m = re.search(pattern, output)
    return int(m.group(1)) if m else None


def get_image_dimensions(image_path: Path) -> tuple[int | None, int | None]:
    try:
        result = subprocess.run(
            ["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", str(image_path)],
            abjture_output=True,
            text=True,
            check=True,
        )
        width = _parse_sips_dimension(result.stdout, "pixelWidth")
        height = _parse_sips_dimension(result.stdout, "pixelHeight")
        return width, height
    except Exception:
        return None, None


def prepare_image_for_ocr(image_path: Path, max_side: int) -> tuple[Path, bool]:
    """
    使用 macOS 自带 sips 对图片做缩放和格式标准化。
    额外策略：
    - 统一转成 JPEG，规避部分 RGBA PNG 在视觉模型中的兼容性问题
    - 尺寸向下对齐到 ALIGNMENT，降低某些模型张量对齐报错概率
    返回 (实际要发送给模型的路径, 是否为临时预处理文件)。
    """
    width, height = get_image_dimensions(image_path)
    if not width or not height:
        return image_path, False

    longest = max(width, height)
    need_resize = longest > max_side
    need_convert = image_path.suffix.lower() in {".png", ".webp", ".gif", ".bmp"}

    aligned_w = max(ALIGNMENT, (width // ALIGNMENT) * ALIGNMENT)
    aligned_h = max(ALIGNMENT, (height // ALIGNMENT) * ALIGNMENT)
    need_align = aligned_w != width or aligned_h != height

    if not need_resize and not need_convert and not need_align:
        return image_path, False

    fd, tmp_name = tempfile.mkstemp(prefix="ocr_prepared_", suffix=".jpg")
    os.close(fd)
    tmp_path = Path(tmp_name)

    try:
        # 先用 sips 转成 JPEG（顺带去掉 alpha），规避 RGBA PNG 兼容性问题
        subprocess.run(
            ["/usr/bin/sips", "-s", "format", "jpeg", str(image_path), "--out", str(tmp_path)],
            abjture_output=True,
            text=True,
            check=True,
        )

        # 如果超大，先缩放
        if need_resize:
            subprocess.run(
                ["/usr/bin/sips", "--resampleHeightWidthMax", str(max_side), str(tmp_path)],
                abjture_output=True,
                text=True,
                check=True,
            )

        # 再做尺寸对齐，向下取整到 ALIGNMENT
        p_width, p_height = get_image_dimensions(tmp_path)
        if p_width and p_height:
            aligned_pw = max(ALIGNMENT, (p_width // ALIGNMENT) * ALIGNMENT)
            aligned_ph = max(ALIGNMENT, (p_height // ALIGNMENT) * ALIGNMENT)
            if aligned_pw != p_width or aligned_ph != p_height:
                subprocess.run(
                    ["/usr/bin/sips", "--resampleWidth", str(aligned_pw), "--resampleHeight", str(aligned_ph), str(tmp_path)],
                    abjture_output=True,
                    text=True,
                    check=True,
                )
        return tmp_path, True
    except Exception:
        try:
            tmp_path.unlink(missing_ok=True)
        except Exception:
            pass
        return image_path, False


def is_retryable_ocr_error(err_text: str) -> bool:
    markers = [
        "GGML_ASSERT",
        "failed",
        "vision",
        "image",
        "tensor",
    ]
    lowered = err_text.lower()
    return any(m.lower() in lowered for m in markers)


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
        (f for f in DEFAULT_DOWNLOAD_DIR.iterdir()
         if f.is_file() and f.suffix.lower() in SUPPORTED_EXTS),
        key=lambda x: x.stat().st_mtime,
        reverse=True,
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


# ─────────────── 规则后处理 ──────────────────────────────────

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
    """默认先走原图；仅在可重试的 OCR 失败时再做预处理并重试。"""
    ollama, client = _get_client()

    print(f"\n{DIVIDER}")
    print(f"🔍  [Stage 1] OCR 提取  →  模型: {OCR_MODEL}")
    print(f"    图片: {image_path.name}  ({image_path.stat().st_size / 1024:.1f} KB)")
    print(f"    Ollama: {OLLAMA_HOST}")
    print(DIVIDER)

    t_start = print_stage_start("Stage 1 OCR")
    original_bytes = image_path.read_bytes()

    def _chat_with_bytes(img_bytes: bytes):
        return client.chat(
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
            keep_alive="15m",
        )

    try:
        response = _chat_with_bytes(original_bytes)
    except ollama.ResponseError as e:
        err_text = f"{e.error}"
        if not is_retryable_ocr_error(err_text):
            print(f"❌  OCR 错误：{e.status_code} — {e.error}")
            print(f"    确认 {OCR_MODEL} 已拉取：ollama list")
            sys.exit(1)

        print(f"    ⚠️  原图 OCR 失败，尝试预处理后重试：{e.error}")
        prepared_path, is_temp = prepare_image_for_ocr(image_path, MAX_IMAGE_SIDE)

        if prepared_path == image_path:
            print(f"❌  OCR 错误：{e.status_code} — {e.error}")
            print("    原图失败，且没有可用的预处理降级路径。")
            sys.exit(1)

        width, height = get_image_dimensions(image_path)
        p_width, p_height = get_image_dimensions(prepared_path)
        print(
            f"    🖼️  图片预处理重试: {width}x{height} -> {p_width}x{p_height} "
            f"(max_side={MAX_IMAGE_SIDE}, align={ALIGNMENT}, format=jpeg)"
        )

        try:
            response = _chat_with_bytes(prepared_path.read_bytes())
        except ollama.ResponseError as e2:
            print(f"❌  OCR 重试仍失败：{e2.status_code} — {e2.error}")
            print(f"    确认 {OCR_MODEL} 已拉取：ollama list")
            if is_temp:
                try:
                    prepared_path.unlink(missing_ok=True)
                except Exception:
                    pass
            sys.exit(1)

        if is_temp:
            try:
                prepared_path.unlink(missing_ok=True)
            except Exception:
                pass

    print_stage_end(t_start, "Stage 1 OCR")
    return response.message.content


def stage2_enhance(raw_text: str, model: str) -> str:
    ollama, client = _get_client()

    print(f"\n{DIVIDER}")
    print(f"✨  [Stage 2] AI 增强   →  模型: {model}")
    print(DIVIDER)

    t_start = print_stage_start("Stage 2")
    try:
        response = client.chat(
            model=model,
            messages=[
                ollama.Message(role="system", content=ENHANCE_SYSTEM_PROMPT),
                ollama.Message(role="user", content=raw_text),
            ],
            options=ollama.Options(
                temperature=0.1,
                top_p=0.85,
                num_predict=1024,
                num_ctx=4096,
                num_thread=max(1, os.cpu_count() or 4),
            ),
            keep_alive="15m",
        )
    except ollama.ResponseError as e:
        print(f"⚠️  增强模型错误：{e.status_code} — {e.error}")
        print("    跳过 AI 增强，返回规则处理结果。")
        print_stage_end(t_start, f"Stage 2 [{model}]")
        return raw_text

    result = (response.message.content or "").strip()
    if not result:
        print("⚠️  Stage 2 返回为空，回退到 Stage 1 规则格式化结果。")
        print_stage_end(t_start, f"Stage 2 [{model}]")
        return raw_text

    print_stage_end(t_start, f"Stage 2 [{model}]")
    return result


# ──────────────── 倒计时交互确认 ─────────────────────────────

def ask_to_enhance(wait_seconds: int) -> bool:
    """
    - 不输入，超时后默认进入 Stage 2
    - 输入任意字符并回车，跳过 Stage 2
    """
    if not sys.stdin.isatty():
        print("    ℹ️  当前不是交互终端，默认进入 Stage 2。")
        return True

    stop_event = threading.Event()
    t_start = print_stage_start("等待确认")

    def countdown():
        for remaining in range(wait_seconds, 0, -1):
            if stop_event.is_set():
                return
            sys.stdout.write(
                f"\r    ⏳ 输入任意字符并回车跳过 AI 增强；"
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
        print_stage_end(t_start, "等待确认")
        return False

    print_stage_end(t_start, "等待确认")
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


# ─────────────── 批量处理（保守并发）─────────────────────────

def _process_one_in_batch(image_path: Path, model: str) -> tuple[Path, str, str]:
    raw_text = stage1_ocr(image_path)
    rule_text = rule_based_format(raw_text)
    enhanced_text = stage2_enhance(rule_text, model)
    return image_path, raw_text, enhanced_text


def process_batch(directory: Path, model: str):
    images = sorted(
        f for f in directory.iterdir()
        if f.is_file() and f.suffix.lower() in SUPPORTED_EXTS
    )
    if not images:
        print("文件夹中未找到支持的图片。")
        return

    print(f"\n🚀  开始批量处理 {len(images)} 张图片")
    print(f"    并发限制: {BATCH_CONCURRENCY}（大图建议保持 1~2）")

    out_dir = Path(__file__).parent / f"output_batch_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    out_dir.mkdir(exist_ok=True, parents=True)

    with ThreadPoolExecutor(max_workers=BATCH_CONCURRENCY) as executor:
        futures = {
            executor.submit(_process_one_in_batch, img, model): img
            for img in images
        }

        for future in as_completed(futures):
            img = futures[future]
            try:
                image_path, raw_text, enhanced_text = future.result()
            except Exception as exc:
                print(f"❌  批量处理失败：{img.name} — {exc}")
                continue

            out = out_dir / f"{image_path.stem}.md"
            with open(out, "w", encoding="utf-8") as f:
                f.write(f"# OCR — {image_path.name}\n\n")
                f.write("## 原文\n```\n")
                f.write(raw_text)
                f.write("\n```\n\n")
                f.write("## 增强\n")
                f.write(enhanced_text)
                f.write("\n")
            print(f"💾  已保存：{out.name}")

    print(f"\n💾  所有结果已保存至：{out_dir}")


# ──────────────────────── 主流程 ─────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="稳态优先 OCR：单图/大图走同步稳定逻辑，批量走保守并发",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            示例：
              python trubo.py
              python trubo.py 1.png
              python trubo.py 1.png --auto-enhance
              python trubo.py --batch ~/Downloads/images

            环境变量：
              OLLAMA_HOST        Ollama 服务地址（默认 http://localhost:11434）
              ENHANCE_MODEL      Stage 2 模型（默认 gemma3:270m）
              BATCH_CONCURRENCY  批量并发数（默认 2）
              OCR_MAX_IMAGE_SIDE OCR 预处理最大边长（默认 2048）
              OCR_IMAGE_ALIGNMENT OCR 预处理尺寸对齐（默认 32）
        """),
    )
    parser.add_argument("image", nargs="?", help="单图片路径")
    parser.add_argument("--batch", metavar="DIR", help="批量处理指定文件夹")
    parser.add_argument("--auto-enhance", action="store_true", help="不等待，直接进入 Stage 2")
    parser.add_argument("--no-enhance", action="store_true", help="仅 Stage 1，跳过 Stage 2")
    parser.add_argument("--save", action="store_true", help="保存单图结果到 output/")
    parser.add_argument("--model", default=ENHANCE_MODEL, help=f"Stage 2 模型（默认: {ENHANCE_MODEL}）")
    parser.add_argument("--wait", type=int, default=DEFAULT_WAIT_SECONDS, help=f"倒计时秒数（默认: {DEFAULT_WAIT_SECONDS}）")
    args = parser.parse_args()

    t_global = time.time()
    print(f"\n🚀  任务启动  {_now_str()}")

    if args.batch:
        p = Path(args.batch).expanduser().resolve()
        if not p.is_dir():
            print(f"❌  批量处理目录不存在：{p}")
            sys.exit(1)
        process_batch(p, args.model)
        print(f"\n{'─' * 60}")
        print(f"🏁  批量完成  {_now_str()}  |  总流转耗时: {time.time() - t_global:.2f} 秒")
        print(f"{'─' * 60}\n")
        return

    image_path = resolve_image_path(args.image) if args.image else pick_image_interactively()
    if image_path.suffix.lower() not in SUPPORTED_EXTS:
        print(f"⚠️  不支持的文件格式：{image_path.suffix}")
        sys.exit(1)

    raw_text = stage1_ocr(image_path)
    rule_text = rule_based_format(raw_text)

    print(f"\n{EQUALS}")
    print("📄  [Stage 1] OCR 结果（规则格式化）")
    print(EQUALS)
    print(rule_text)
    print(EQUALS)

    enhanced_text = None
    if not args.no_enhance:
        if args.auto_enhance:
            do_enhance = True
            print("\n    [--auto-enhance] 自动进入 Stage 2 AI 增强...")
        else:
            print()
            do_enhance = ask_to_enhance(args.wait)

        if do_enhance:
            enhanced_text = stage2_enhance(rule_text, args.model)

            print(f"\n{EQUALS}")
            print(f"✨  [Stage 2] AI 增强结果  [{args.model}]")
            print(EQUALS)
            print(enhanced_text)
            print(EQUALS)
    else:
        print("\n    [--no-enhance] 已跳过 Stage 2。")

    if args.save:
        save_result(image_path, raw_text, enhanced_text)

    print(f"\n{'─' * 60}")
    print(f"🏁  全面完成  {_now_str()}  |  总流转耗时: {time.time() - t_global:.2f} 秒")
    print(f"{'─' * 60}\n")


if __name__ == "__main__":
    main()
