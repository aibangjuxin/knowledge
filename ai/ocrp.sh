#!/usr/bin/env bash
# /Users/lex/.local/bin/ocrp
set -euo pipefail

PYTHON_BIN="/Users/lex/python/openai/bin/python3"
PY_SCRIPT="/Users/lex/git/knowledge/ai/ocr-llama.py"
#PY_SCRIPT="/Users/lex/git/knowledge/ai/ocr-ollama-3.py"
DEFAULT_PATH="/Users/lex/Downloads"

usage() {
  echo "Usage: ocrp [image-path-or-directory]" >&2
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

if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "Error: python executable not found: ${PYTHON_BIN}" >&2
  exit 1
fi

if [[ ! -f "${PY_SCRIPT}" ]]; then
  echo "Error: python script not found: ${PY_SCRIPT}" >&2
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

exec "${PYTHON_BIN}" "${PY_SCRIPT}" "${IMG}"