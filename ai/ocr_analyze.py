#!/Users/lex/python/openai/bin/python3
# this script call lm studio's glm-ocr model to analyze image
import sys
from pathlib import Path
import base64
from openai import OpenAI


def main():
    # 1. 检查传入的参数
    if len(sys.argv) < 2:
        print("用法：python ocr_analyze.py image_path [prompt]")
        sys.exit(1)

    image_path = Path(sys.argv[1])
    custom_prompt = (
        "请帮我解析这张图片里的文字内容，重点提取：标题、日期、金额、说明文字等关键信息。"
        if len(sys.argv) == 2 else sys.argv[2]
    )

    if not image_path.exists():
        print(f"错误：图片路径不存在 {image_path}")
        sys.exit(1)

    # 2. 读取图片，转换成 base64
    with open(image_path, "rb") as f:
        img_bytes = f.read()
    img_b64 = base64.b64encode(img_bytes).decode("utf-8")
    mime_type = "image/png" if image_path.suffix.lower() in (".png", ".jpg", ".jpeg") else "image/*"

    # 3. 构建要给 glm-ocr 的消息
    client = OpenAI(
        base_url="http://192.168.31.198:1234/v1",
        api_key="lm-studio",
    )

    MODEL_NAME = "glm-ocr"

    messages = [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": custom_prompt},
                {"type": "image_url", "image_url": {"url": f"data:{mime_type};base64,{img_b64}"}},
            ],
        }
    ]

    resp = client.chat.completions.create(
        model=MODEL_NAME,
        messages=messages,
        temperature=0.7,
        top_p=0.95,
    )

    text = resp.choices[0].message.content
    print("Reply:")
    print(text)


if __name__ == "__main__":
    main()
