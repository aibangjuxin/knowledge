#!/bin/bash
# Simulate the dry-run output
echo "[INFO] ==========================================" >&2
echo "[INFO] Java Pod Debug Script v1.0.0" >&2
echo "[INFO] ==========================================" >&2
echo "" >&2
echo "[INFO] 检查依赖工具..." >&2
echo "[SUCCESS] 依赖检查通过" >&2
echo "[WARNING] Dry-run 模式: 仅显示 YAML 内容" >&2
echo "" >&2

# This is the YAML output (to stdout)
cat << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-debug-1234567890
  namespace: lex
  labels:
    app: java-debug
    purpose: troubleshooting
spec:
  replicas: 1
  selector:
    matchLabels:
      app: java-debug
  template:
    metadata:
      labels:
        app: java-debug
    spec:
      containers:
        - name: target-app
          image: target_image
        - name: debug-sidecar
          image: sidecar_image
EOF

echo "" >&2
echo "[INFO] YAML 文件已保存至: /tmp/java-debug-1234567890.yaml" >&2
