#!/usr/bin/env bash
# =============================================================================
# copy-secret-cross-ns.sh — Duplicate a K8s Secret from one NS to another
#
# Use case: a Secret lives in the "platform" NS (e.g., abjx-listenerset-int)
# for ListenerSet TLS termination, but a Pod in a "tenant" NS (e.g., team1)
# needs to mount the same cert as a server cert. K8s Secret is namespace-scoped;
# ReferenceGrant does NOT help here. The fix is to duplicate.
#
# Usage: copy-secret-cross-ns.sh <secret-name> <src-ns> <dst-ns>
# Example: copy-secret-cross-ns.sh abjx-lex-eg-secret-team1-tls \
#            abjx-listenerset-int team1
#
# Effect: creates (or replaces) a copy of the Secret in the destination NS.
# The two copies are now independent — any cert rotation must update both.
# =============================================================================

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <secret-name> <src-ns> <dst-ns>" >&2
  echo "  Example: $0 abjx-lex-eg-secret-team1-tls abjx-listenerset-int team1" >&2
  exit 1
fi

SECRET_NAME="$1"
SRC_NS="$2"
DST_NS="$3"

# 1. Verify source exists
if ! kubectl get secret "$SECRET_NAME" -n "$SRC_NS" &>/dev/null; then
  echo "ERROR: source secret $SRC_NS/$SECRET_NAME not found" >&2
  exit 1
fi

# 2. Duplicate, stripping source-ns-specific metadata fields
kubectl get secret "$SECRET_NAME" -n "$SRC_NS" -o json \
  | jq 'del(.metadata.namespace,.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.managedFields) | .metadata.namespace = "'"$DST_NS"'"' \
  | kubectl apply -f -

# 3. Verify both copies exist
echo ""
echo "=== verification ==="
kubectl get secret "$SECRET_NAME" -n "$SRC_NS" -o jsonpath='{.type}' 2>/dev/null | xargs -I{} echo "  source:    $SRC_NS/$SECRET_NAME   type={}"
kubectl get secret "$SECRET_NAME" -n "$DST_NS" -o jsonpath='{.type}' 2>/dev/null | xargs -I{} echo "  duplicate: $DST_NS/$SECRET_NAME  type={}"

# 4. Compare cert data (sha256 of tls.crt) — should match
SRC_HASH=$(kubectl get secret "$SECRET_NAME" -n "$SRC_NS" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | sha256sum | cut -d' ' -f1)
DST_HASH=$(kubectl get secret "$SECRET_NAME" -n "$DST_NS" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | sha256sum | cut -d' ' -f1)
echo ""
echo "  cert sha256 (source):    $SRC_HASH"
echo "  cert sha256 (duplicate): $DST_HASH"
if [[ "$SRC_HASH" == "$DST_HASH" ]]; then
  echo "  ✅ cert data matches"
else
  echo "  ⚠️  cert data MISMATCH — investigate"
  exit 1
fi

echo ""
echo "✅ secret duplicated. Remember: any cert rotation must update both copies."
