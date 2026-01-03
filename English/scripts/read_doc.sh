#!/bin/bash
# 文件名: read_doc.sh
FILE=$1

while IFS= read -r line; do
  if [[ "$line" =~ [\u4e00-\u9fff] ]]; then
    say -v "Ting-Ting" "$line"
  else
    say -v "Samantha" "$line"
  fi
done <"$FILE"
