#!/Users/lex/python/openai/bin/python3
# -*- coding: utf-8 -*-
"""
ocr_ollama.py — 使用 Ollama (glm-ocr) 进行图片 OCR 解析
Ollama SDK: 0.6.1+  端口：localhost:11434（可通过环境变量 OLLAMA_HOST 覆盖）

用法：
  python ocr_ollama.py                          # 交互式选择 ~/Downloads 下的图片
  python ocr_ollama.py 33.png                   # 在默认路径 ~/Downloads 下查找
  python ocr_ollama.py /absolute/path/img.png   # 直接使用绝对路径
  python ocr_ollama.py 33.png "自定义 prompt"   # 指定 prompt
"""

import sys
import os
from pathlib import Path
import base64

# ── 可在此修改默认配置 ──────────────────────────────────────────
DEFAULT_DOWNLOAD_DIR = Path("/Users/lex/Downloads")
OLLAMA_HOST         = "http://localhost:11434"
MODEL_NAME          = "glm-ocr"
DEFAULT_PROMPT      = (
    "请帮我解析这张图片里的文字内容，重点提取：标题、日期、金额、说明文字等关键信息。"
)
SUPPORTED_EXTS      = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}
# ────────────────────────────────────────────────────────────────


def resolve_image_path(raw: str) -> Path:
    """
    路径解析策略（优先级依次递减）：
    1. 若是绝对路径且文件存在 → 直接使用
    2. 在 DEFAULT_DOWNLOAD_DIR 下查找文件名 → 优先匹配
    3. 均未找到 → 报错退出
    """
    p = Path(raw)

    # 1. 绝对路径 & 文件存在
    if p.is_absolute() and p.exists():
        return p

    # 2. 在默认下载目录下查找（仅文件名）
    candidate = DEFAULT_DOWNLOAD_DIR / p.name
    if candidate.exists():
        return candidate

    # 3. 相对路径 → 相对于当前工作目录
    cwd_candidate = Path.cwd() / p
    if cwd_candidate.exists():
        return cwd_candidate

    print(f"❌  找不到图片文件：{raw}")
    print(f"    已尝试路径：\n      {p}\n      {candidate}\n      {cwd_candidate}")
    sys.exit(1)


def pick_image_interactively() -> Path:
    """
    若未传入任何图片参数，列出默认目录中所有支持的图片供用户选择。
    """
    if not DEFAULT_DOWNLOAD_DIR.exists():
        print(f"❌  默认目录不存在：{DEFAULT_DOWNLOAD_DIR}")
        sys.exit(1)

    images = sorted(
        f for f in DEFAULT_DOWNLOAD_DIR.iterdir()
        if f.is_file() and f.suffix.lower() in SUPPORTED_EXTS
    )

    if not images:
        print(f"⚠️  默认目录 {DEFAULT_DOWNLOAD_DIR} 中未找到支持的图片文件。")
        print(f"    支持格式：{', '.join(SUPPORTED_EXTS)}")
        sys.exit(1)

    print(f"\n📂  默认目录：{DEFAULT_DOWNLOAD_DIR}")
    print("    可用图片列表：")
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


def image_to_base64(path: Path) -> tuple[str, str]:
    """读取图片并转为 base64，同时返回 MIME type。"""
    ext = path.suffix.lower()
    mime_map = {
        ".png":  "image/png",
        ".jpg":  "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
        ".gif":  "image/gif",
        ".bmp":  "image/bmp",
    }
    mime = mime_map.get(ext, "image/png")
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("utf-8")
    return b64, mime


def call_ollama(image_path: Path, prompt: str) -> str:
    """
    调用 Ollama Python SDK 0.6.1（ollama.Client.chat）。
    images 字段传入图片 bytes，host 通过 Client 实例显式指定。
    """
    try:
        import ollama
    except ImportError:
        print("❌  未安装 ollama 库，请先执行：")
        print(f"    {sys.executable} -m pip install ollama")
        sys.exit(1)

    # 读取图片 bytes（SDK 0.6.x 的 images 字段接受 bytes / base64 str）
    with open(image_path, "rb") as f:
        img_bytes = f.read()

    host = os.environ.get("OLLAMA_HOST", OLLAMA_HOST)
    print(f"\n🔍  正在使用模型 [{MODEL_NAME}] 解析图片：{image_path.name} ...")
    print(f"    Ollama 端点：{host}\n")

    client = ollama.Client(host=host)

    try:
        response = client.chat(
            model=MODEL_NAME,
            messages=[
                ollama.Message(
                    role="user",
                    content=prompt,
                    images=[ollama.Image(value=img_bytes)],  # SDK 0.6.x 需要 Image 包装
                )
            ],
            options=ollama.Options(
                temperature=0.1,   # OCR 任务建议低 temperature 保持精准
                top_p=0.9,
            ),
        )
    except ollama.ResponseError as e:
        print(f"❌  Ollama 服务返回错误：{e.status_code} — {e.error}")
        print("    请确认：1) ollama 服务已启动  2) glm-ocr 模型已拉取")
        print("    检查命令：ollama list")
        sys.exit(1)
    except Exception as e:
        print(f"❌  调用 Ollama 失败：{e}")
        raise

    # SDK 0.6.x 返回 ChatResponse（Pydantic model）
    return response.message.content


def main():
    args = sys.argv[1:]  # 去掉脚本名

    # ── 解析参数 ────────────────────────────────────────────────
    # 支持格式：
    #   (无参数)              → 交互式选择
    #   <image>               → 路径解析 + 默认 prompt
    #   <image> <prompt>      → 路径解析 + 自定义 prompt
    # ────────────────────────────────────────────────────────────
    if len(args) == 0:
        image_path = pick_image_interactively()
        custom_prompt = DEFAULT_PROMPT
    elif len(args) == 1:
        image_path = resolve_image_path(args[0])
        custom_prompt = DEFAULT_PROMPT
    else:
        image_path = resolve_image_path(args[0])
        custom_prompt = args[1]

    # 文件类型检查
    if image_path.suffix.lower() not in SUPPORTED_EXTS:
        print(f"⚠️  不支持的文件格式：{image_path.suffix}")
        print(f"    支持格式：{', '.join(SUPPORTED_EXTS)}")
        sys.exit(1)

    # 调用 Ollama
    result = call_ollama(image_path, custom_prompt)

    print("=" * 60)
    print("📄  OCR 解析结果：")
    print("=" * 60)
    print(result)
    print("=" * 60)


if __name__ == "__main__":
    main()
