#!/bin/bash

# Script purpose: Add labels to specified deployments
# Usage:
#   ./add-deployment-labels-flexible.sh -n namespace -l key=value -d "deploy1,deploy2,deploy3"
#   ./add-deployment-labels-flexible.sh -n my-namespace -l lex=enabled -d "app1,app2"
# ./add-deployment-labels-flexible.sh -n lex -l lex=enabled -d "nginx-deployment,busybox-deployment" --dry-run

set -e

# Default values
NAMESPACE=""
LABEL=""
DEPLOYMENTS=""
HELP=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -n | --namespace)
    NAMESPACE="$2"
    shift 2
    ;;
  -l | --label)
    LABEL="$2"
    shift 2
    ;;
  -d | --deployments)
    DEPLOYMENTS="$2"
    shift 2
    ;;
  -h | --help)
    HELP=true
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  *)
    echo "Unknown parameter: $1"
    HELP=true
    shift
    ;;
  esac
done

# Show help information
if [ "$HELP" = true ] || [ -z "$NAMESPACE" ] || [ -z "$LABEL" ] || [ -z "$DEPLOYMENTS" ]; then
  echo "Usage: $0 -n <namespace> -l <key=value> -d <deployment1,deployment2,...>"
  echo ""
  echo "Parameters:"
  echo "  -n, --namespace     Target namespace"
  echo "  -l, --label         Label to add (format: key=value)"
  echo "  -d, --deployments   Deployment list (comma separated)"
  echo "  --dry-run           Preview mode, only show operations to be executed without actually executing"
  echo "  -h, --help          Show help information"
  echo ""
  echo "Examples:"
  echo "  $0 -n my-namespace -l lex=enabled -d \"app1,app2,app3\""
  echo "  $0 -n production -l env=prod -d \"web-server,api-server\""
  exit 1
fi

# Parse label
if [[ ! "$LABEL" =~ ^[^=]+=[^=]+$ ]]; then
  echo "❌ Label format error, should be key=value format"
  exit 1
fi

LABEL_KEY=$(echo "$LABEL" | cut -d'=' -f1)
LABEL_VALUE=$(echo "$LABEL" | cut -d'=' -f2)

# Convert deployment string to array
IFS=',' read -ra DEPLOY_ARRAY <<<"$DEPLOYMENTS"

if [ "$DRY_RUN" = true ]; then
  echo "🔍 Preview mode - Operations to be executed:"
else
  echo "🚀 Starting to add labels to deployments..."
fi
echo "Namespace: ${NAMESPACE}"
echo "Label: ${LABEL_KEY}=${LABEL_VALUE}"
echo "Target deployments: ${DEPLOY_ARRAY[*]}"
if [ "$DRY_RUN" = true ]; then
  echo "Mode: Preview mode (will not actually execute)"
fi
echo "=========================================="

# Check if namespace exists
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "❌ Namespace '${NAMESPACE}' does not exist, please check configuration"
  exit 1
fi

# Add label to each deployment
for deploy in "${DEPLOY_ARRAY[@]}"; do
  # Remove spaces
  deploy=$(echo "$deploy" | xargs)

  echo "📝 Processing deployment: ${deploy}"

  # Check if deployment exists
  if ! kubectl get deployment "${deploy}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "⚠️  Deployment '${deploy}' does not exist in namespace '${NAMESPACE}', skipping"
    continue
  fi

  # Check if the label already exists in pod template
  echo "   Checking if label already exists..."
  CURRENT_LABEL_VALUE=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" -o jsonpath="{.spec.template.metadata.labels.${LABEL_KEY}}" 2>/dev/null || echo "")
  
  if [ "$CURRENT_LABEL_VALUE" = "$LABEL_VALUE" ]; then
    echo "   ℹ️  Label ${LABEL_KEY}=${LABEL_VALUE} already exists, skipping update"
    echo "   ✅ ${deploy} no update needed"
  else
    if [ -n "$CURRENT_LABEL_VALUE" ]; then
      echo "   📝 Current label value: ${LABEL_KEY}=${CURRENT_LABEL_VALUE}, will update to: ${LABEL_KEY}=${LABEL_VALUE}"
    else
      echo "   📝 No such label currently, will add: ${LABEL_KEY}=${LABEL_VALUE}"
    fi
    
    if [ "$DRY_RUN" = true ]; then
      echo "   🔍 [Preview] Will execute: kubectl patch deployment ${deploy} -n ${NAMESPACE} --type='merge' -p '{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"${LABEL_KEY}\":\"${LABEL_VALUE}\"}}}}}}'"
      echo "   🔍 [Preview] Will trigger rolling update, recreate pods"
      echo "   ✅ ${deploy} preview completed"
    else
      # Add label to pod template
      echo "   Adding/updating label to pod template..."
      kubectl patch deployment "${deploy}" -n "${NAMESPACE}" --type='merge' \
        -p "{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"${LABEL_KEY}\":\"${LABEL_VALUE}\"}}}}}"

      if [ $? -eq 0 ]; then
        echo "   ✅ ${deploy} label add/update successful"
        
        # Wait for rolling update to complete
        echo "   Waiting for rolling update to complete..."
        kubectl rollout status deployment/"${deploy}" -n "${NAMESPACE}" --timeout=30s

        if [ $? -eq 0 ]; then
          echo "   ✅ ${deploy} rolling update completed"
        else
          echo "   ⚠️  ${deploy} rolling update timeout, please check manually"
        fi
      else
        echo "   ❌ ${deploy} label add/update failed"
        continue
      fi
    fi
  fi

  echo ""
done

echo "=========================================="
echo "🔍 Verification Results:"

# Verify deployment and pods label status
for deploy in "${DEPLOY_ARRAY[@]}"; do
  deploy=$(echo "$deploy" | xargs)
  if kubectl get deployment "${deploy}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "📋 Deployment ${deploy}:"
    
    # Check label in deployment pod template
    TEMPLATE_LABEL_VALUE=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" -o jsonpath="{.spec.template.metadata.labels.${LABEL_KEY}}" 2>/dev/null || echo "")
    if [ "$TEMPLATE_LABEL_VALUE" = "$LABEL_VALUE" ]; then
      echo "   ✅ Pod template label: ${LABEL_KEY}=${TEMPLATE_LABEL_VALUE}"
    else
      echo "   ❌ Pod template label: ${LABEL_KEY}=${TEMPLATE_LABEL_VALUE:-"not set"}"
    fi
    
    # Check actual running pods
    PODS_WITH_LABEL=$(kubectl get pods -n "${NAMESPACE}" -l "app=${deploy},${LABEL_KEY}=${LABEL_VALUE}" --no-headers 2>/dev/null | wc -l)
    TOTAL_PODS=$(kubectl get pods -n "${NAMESPACE}" -l "app=${deploy}" --no-headers 2>/dev/null | wc -l)
    
    if [ "$PODS_WITH_LABEL" -gt 0 ]; then
      echo "   ✅ Running pods: ${PODS_WITH_LABEL}/${TOTAL_PODS} pods have ${LABEL_KEY}=${LABEL_VALUE}"
    else
      echo "   ⚠️  Running pods: 0/${TOTAL_PODS} pods have ${LABEL_KEY}=${LABEL_VALUE}"
    fi
    
    echo ""
  fi
done

echo "=========================================="
echo "📊 Summary:"
TOTAL_DEPLOYMENTS=${#DEPLOY_ARRAY[@]}
SUCCESSFUL_DEPLOYMENTS=0

for deploy in "${DEPLOY_ARRAY[@]}"; do
  deploy=$(echo "$deploy" | xargs)
  if kubectl get deployment "${deploy}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    TEMPLATE_LABEL_VALUE=$(kubectl get deployment "${deploy}" -n "${NAMESPACE}" -o jsonpath="{.spec.template.metadata.labels.${LABEL_KEY}}" 2>/dev/null || echo "")
    if [ "$TEMPLATE_LABEL_VALUE" = "$LABEL_VALUE" ]; then
      ((SUCCESSFUL_DEPLOYMENTS++))
    fi
  fi
done

echo "✅ Successfully configured: ${SUCCESSFUL_DEPLOYMENTS}/${TOTAL_DEPLOYMENTS} deployments"
echo "🏷️  Label: ${LABEL_KEY}=${LABEL_VALUE}"
echo "📦 Namespace: ${NAMESPACE}"

if [ "$SUCCESSFUL_DEPLOYMENTS" -eq "$TOTAL_DEPLOYMENTS" ]; then
  echo ""
  echo "🎉 All deployments have been successfully configured with labels!"
  echo "💡 Now these pods should be able to access services in the target namespace"
else
  echo ""
  echo "⚠️  Some deployments failed to configure, please check the error messages above"
fi

echo ""
echo "✅ Script execution completed!"
