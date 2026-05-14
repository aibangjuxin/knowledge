#!/bin/bash

# 需要设置你的 GitHub token
GITHUB_TOKEN="your_token"
REPO="owner/repo"

curl -H "Authorization: token $GITHUB_TOKEN" \
     "https://api.github.com/repos/$REPO/commits?per_page=20" | \
     jq '.[].files[].filename' | sort | uniq