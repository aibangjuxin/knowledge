nas 部署 paddleocr-vl-pipeline
```bash
docker login
https://www.paddlepaddle.org.cn/en/install/quick?docurl=/documentation/docs/en/install/docker/linux-docker_en.html

the next comman can't found the image
docker run -d \
  --restart always \
  -p 18080:8000 \
  --name paddleocr-vl-nas \
  paddleocr/paddleocr-vl-pipeline:1.5
```



/Users/lex/.local/bin/orc
```bash
#!/usr/bin/env bash
set -euo pipefail

SWIFT_SCRIPT="/Users/lex/git/knowledge/ios/ocr/main.swift"

usage() {
  echo "Usage: orc /absolute/path/to/image.png" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

IMG="$1"
if [[ "${IMG}" != /* ]]; then
  echo "Error: please pass an absolute path (got: ${IMG})" >&2
  exit 2
fi

if [[ ! -f "${SWIFT_SCRIPT}" ]]; then
  echo "Error: swift script not found: ${SWIFT_SCRIPT}" >&2
  exit 1
fi

if [[ ! -f "${IMG}" ]]; then
  echo "Error: image not found: ${IMG}" >&2
  exit 1
fi

exec /usr/bin/swift "${SWIFT_SCRIPT}" "${IMG}"
```
- enhance 

```bash
#!/usr/bin/env bash
set -euo pipefail

SWIFT_SCRIPT="/Users/lex/git/knowledge/ios/ocr/main.swift"
DEFAULT_PATH="/Users/lex/Downloads"

usage() {
  echo "Usage: orc [image-path-or-directory]" >&2
  echo "Defaults to: ${DEFAULT_PATH}" >&2
}

resolve_latest_image() {
  local dir="$1"

  find "$dir" -maxdepth 1 -type f \
    \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o \
       -iname "*.webp" -o -iname "*.tif" -o -iname "*.tiff" -o -iname "*.bmp" -o \
       -iname "*.gif" \) \
    -exec stat -f '%m %N' {} \; | sort -nr | head -n 1 | cut -d' ' -f2-
}

if [[ $# -gt 1 ]]; then
  usage
  exit 2
fi

if [[ $# -eq 0 ]]; then
  TARGET="${DEFAULT_PATH}"
elif [[ "$1" = /* ]]; then
  TARGET="$1"
else
  TARGET="${DEFAULT_PATH}/$1"
fi

if [[ ! -f "${SWIFT_SCRIPT}" ]]; then
  echo "Error: swift script not found: ${SWIFT_SCRIPT}" >&2
  exit 1
fi

if [[ -d "${TARGET}" ]]; then
  IMG="$(resolve_latest_image "${TARGET}")"
  if [[ -z "${IMG}" ]]; then
    echo "Error: no image files found in directory: ${TARGET}" >&2
    exit 1
  fi
else
  IMG="${TARGET}"
fi

if [[ ! -f "${IMG}" ]]; then
  echo "Error: image not found: ${IMG}" >&2
  exit 1
fi

exec /usr/bin/swift "${SWIFT_SCRIPT}" "${IMG}
```