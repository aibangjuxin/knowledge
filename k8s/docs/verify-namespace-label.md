- verify 
- 脚本执行没有问题
- 现在获取资源的时候其实是获取的这一个NS的
- 我们其实是要获取整个NS下哪些Pod有这个标签
```bash
#!/bin/bash

# =============================================================================
# Kubernetes NetworkPolicy Resource Information Extraction Script
# Author: Cloud Infrastructure Team
# Purpose: Extract NetworkPolicy, Service, Deployment, and Pod information
# =============================================================================

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration variables
NAMESPACE="${1}"

# Check parameters
if [ -z "$NAMESPACE" ]; then
    echo -e "${RED}Error: Please specify namespace${NC}"
    echo "Usage: $0 <namespace>"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}Error: Namespace '$NAMESPACE' does not exist${NC}"
    exit 1
fi

echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}Kubernetes NetworkPolicy Resource Information Extraction${NC}"
echo -e "${GREEN}Namespace: ${CYAN}$NAMESPACE${NC}"
echo -e "${GREEN}Timestamp: ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${GREEN}==============================================================================${NC}\n"

# =============================================================================
# 1. Extract NetworkPolicy ingress labels
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}[1/4] NetworkPolicy Ingress Labels${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Get all NetworkPolicy
NETPOLS=$(kubectl get networkpolicy -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
NETPOL_COUNT=$(echo "$NETPOLS" | jq '.items | length')

if [ "$NETPOL_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No NetworkPolicy found in this namespace${NC}\n"
else
    echo -e "${GREEN}Found $NETPOL_COUNT NetworkPolicy${NC}"
    echo ""
    
    # Extract and format output
    echo "$NETPOLS" | jq -r '
    .items[] | 
    "╔══════════════════════════════════════════════════════════════",
    "║ NetworkPolicy: \(.metadata.name)",
    "╠══════════════════════════════════════════════════════════════",
    "║ Created: \(.metadata.creationTimestamp)",
    "║",
    "║ Applied to Pods (podSelector):",
    (if (.spec.podSelector.matchLabels | length) > 0 then
      (.spec.podSelector.matchLabels | to_entries[] | "║   • \(.key): \(.value)")
    else
      "║   • (All Pods)"
    end),
    "║",
    "║ Ingress Rules:",
    "║ ─────────────────────────────────────────────────────────────",
    (.spec.ingress[]? | 
      (.from[]? | 
        if .podSelector then
          "║ From Pods (podSelector.matchLabels):",
          (if (.podSelector.matchLabels | length) > 0 then
            (.podSelector.matchLabels | to_entries[] | "║   ✓ \(.key): \(.value)")
          else
            "║   ✓ (All Pods in namespace)"
          end)
        else
          ""
        end,
        if .namespaceSelector then
          "║ From Namespaces (namespaceSelector.matchLabels):",
          (if (.namespaceSelector.matchLabels | length) > 0 then
            (.namespaceSelector.matchLabels | to_entries[] | "║   ✓ \(.key): \(.value)")
          else
            "║   ✓ (All Namespaces)"
          end)
        else
          ""
        end
      )
    ),
    "╚══════════════════════════════════════════════════════════════",
    ""
    '
fi

# =============================================================================
# 2. List all Services and their ClusterIP
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}[2/4] Services and ClusterIP${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

SERVICES=$(kubectl get svc -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
SVC_COUNT=$(echo "$SERVICES" | jq '.items | length')

if [ "$SVC_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No Service found in this namespace${NC}\n"
else
    echo -e "${GREEN}Found $SVC_COUNT Services${NC}"
    echo ""
    
    echo "$SERVICES" | jq -r '
    .items[] | 
    "╔══════════════════════════════════════════════════════════════",
    "║ Service: \(.metadata.name)",
    "╠══════════════════════════════════════════════════════════════",
    "║ Cluster IP:   \(.spec.clusterIP)",
    "║ Type:         \(.spec.type)",
    "║ Ports:        \(.spec.ports | map("\(.name // "unnamed"):\(.port)/\(.protocol)") | join(", "))",
    (if .status.loadBalancer.ingress then
      "║ External IP:  \(.status.loadBalancer.ingress[0].ip // .status.loadBalancer.ingress[0].hostname // "Pending")"
    else
      ""
    end),
    "║ Selector:     \(if .spec.selector then (.spec.selector | to_entries | map("\(.key)=\(.value)") | join(", ")) else "None" end)",
    "║ DNS Name:     \(.metadata.name).\(.metadata.namespace).svc.cluster.local",
    "╚══════════════════════════════════════════════════════════════",
    ""
    '
fi

# =============================================================================
# 3. List all Deployment environment variables
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}[3/4] Deployment Environment Variables${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
DEPLOY_COUNT=$(echo "$DEPLOYMENTS" | jq '.items | length')

if [ "$DEPLOY_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No Deployment found in this namespace${NC}\n"
else
    echo -e "${GREEN}Found $DEPLOY_COUNT Deployments${NC}"
    echo ""
    
    echo "$DEPLOYMENTS" | jq -r '
    .items[] | 
    "╔══════════════════════════════════════════════════════════════",
    "║ Deployment: \(.metadata.name)",
    "╠══════════════════════════════════════════════════════════════",
    "║ Replicas:     \(.spec.replicas) (Ready: \(.status.readyReplicas // 0)/\(.status.replicas // 0))",
    "║ Image:        \(.spec.template.spec.containers[0].image)",
    "║",
    (.spec.template.spec.containers[] | 
      "║ Container: \(.name)",
      "║ ─────────────────────────────────────────────────────────────",
      (if (.env | length) > 0 then
        "║ Environment Variables:",
        (.env[] | 
          if .value then
            "║   • \(.name) = \(.value)"
          elif .valueFrom.fieldRef then
            "║   • \(.name) = (fieldRef) \(.valueFrom.fieldRef.fieldPath)"
          elif .valueFrom.secretKeyRef then
            "║   • \(.name) = (secret) \(.valueFrom.secretKeyRef.name):\(.valueFrom.secretKeyRef.key)"
          elif .valueFrom.configMapKeyRef then
            "║   • \(.name) = (configMap) \(.valueFrom.configMapKeyRef.name):\(.valueFrom.configMapKeyRef.key)"
          elif .valueFrom.resourceFieldRef then
            "║   • \(.name) = (resource) \(.valueFrom.resourceFieldRef.resource)"
          else
            "║   • \(.name) = <unknown-source>"
          end
        )
      else
        "║ Environment Variables: None"
      end),
      (if .envFrom then
        "║",
        "║ Environment From (envFrom):",
        (.envFrom[] | 
          if .configMapRef then
            "║   • ConfigMap: \(.configMapRef.name)"
          elif .secretRef then
            "║   • Secret: \(.secretRef.name)"
          else
            "║   • <unknown>"
          end
        )
      else
        ""
      end)
    ),
    "╚══════════════════════════════════════════════════════════════",
    ""
    '
fi

# =============================================================================
# 4. Match Pods based on NetworkPolicy podSelector
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}[4/4] Matched Pods (based on NetworkPolicy podSelector)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

if [ "$NETPOL_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No NetworkPolicy found, skipping Pod matching${NC}\n"
else
    # Extract all ingress podSelector labels
    INGRESS_LABELS=$(echo "$NETPOLS" | jq -r '
    [.items[] | .spec.ingress[]? | .from[]? | select(.podSelector != null) | .podSelector.matchLabels // {}] | 
    map(select(. != {})) | unique | .[]
    ')
    
    if [ -z "$INGRESS_LABELS" ]; then
        echo -e "${YELLOW}⚠ No podSelector.matchLabels defined in NetworkPolicy ingress${NC}\n"
    else
        LABEL_COUNT=0
        
        # Process each label combination
        echo "$INGRESS_LABELS" | jq -c '.' | while read -r label_set; do
            LABEL_COUNT=$((LABEL_COUNT + 1))
            
            # Build label selector
            LABEL_SELECTOR=$(echo "$label_set" | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')
            
            echo -e "${MAGENTA}┌──────────────────────────────────────────────────────────────┐${NC}"
            echo -e "${MAGENTA}│ Label Selector: ${CYAN}$LABEL_SELECTOR${MAGENTA}${NC}"
            echo -e "${MAGENTA}└──────────────────────────────────────────────────────────────┘${NC}"
            
            # Find matching Pods
            MATCHED_PODS=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')
            POD_COUNT=$(echo "$MATCHED_PODS" | jq '.items | length')
            
            if [ "$POD_COUNT" -eq 0 ]; then
                echo -e "${YELLOW}  ⚠ No matching Pods found${NC}"
            else
                echo -e "${GREEN}  ✓ Found $POD_COUNT matching Pod(s)${NC}"
                echo ""
                
                echo "$MATCHED_PODS" | jq -r '
                .items[] | 
                "  ╔══════════════════════════════════════════════════════════════",
                "  ║ Pod: \(.metadata.name)",
                "  ╠══════════════════════════════════════════════════════════════",
                "  ║ Status:      \(.status.phase)",
                "  ║ Pod IP:      \(.status.podIP // "N/A")",
                "  ║ Node:        \(.spec.nodeName // "N/A")",
                "  ║ Labels:      \(.metadata.labels | to_entries | map("\(.key)=\(.value)") | join(", "))",
                "  ║ Containers:  \([.status.containerStatuses[]? | "\(.name):\(if .ready then "Ready" else "NotReady" end)"] | join(", "))",
                "  ║ Restarts:    \([.status.containerStatuses[]? | .restartCount] | add // 0)",
                "  ║ Age:         \(.metadata.creationTimestamp)",
                "  ╚══════════════════════════════════════════════════════════════",
                ""
                '
            fi
            
            echo ""
        done
    fi
fi

# =============================================================================
# Summary
# =============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Summary${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

TOTAL_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)

echo -e "${CYAN}Namespace:${NC}         $NAMESPACE"
echo -e "${CYAN}NetworkPolicies:${NC}   $NETPOL_COUNT"
echo -e "${CYAN}Services:${NC}          $SVC_COUNT"
echo -e "${CYAN}Deployments:${NC}       $DEPLOY_COUNT"
echo -e "${CYAN}Total Pods:${NC}        $TOTAL_PODS"
echo ""

# Generate DNS record suggestions
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}DNS Record Suggestions (for Cloud DNS)${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

if [ "$SVC_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No Services to create DNS records${NC}\n"
else
    echo -e "${YELLOW}# Configure these variables before executing:${NC}"
    echo -e "${YELLOW}# ZONE_NAME=\"your-dns-zone-name\"${NC}"
    echo -e "${YELLOW}# PROJECT_ID=\"your-gcp-project-id\"${NC}"
    echo -e "${YELLOW}# TTL=300${NC}"
    echo ""
    
    echo "$SERVICES" | jq -r '
    .items[] | 
    select(.spec.clusterIP != "None") |
    "# Service: \(.metadata.name)",
    "gcloud dns record-sets create \(.metadata.name).\(.metadata.namespace).svc.cluster.local. \\",
    "  --zone=\"$ZONE_NAME\" \\",
    "  --type=A \\",
    "  --ttl=$TTL \\",
    "  --rrdatas=\(.spec.clusterIP) \\",
    "  --project=\"$PROJECT_ID\"",
    ""
    '
fi

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Extraction completed successfully${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
```