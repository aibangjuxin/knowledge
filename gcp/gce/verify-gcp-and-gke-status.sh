#!/bin/bash

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Step 0: GCE Forwarding Rules ===${NC}"
echo "Listing forwarding rules..."
gcloud compute forwarding-rules list

echo ""
read -p "Enter a Forwarding Rule name to describe (or press Enter to skip): " fr_name

if [ -n "$fr_name" ]; then
    echo -e "${YELLOW}Describing Forwarding Rule: $fr_name${NC}"
    gcloud compute forwarding-rules describe "$fr_name"
else
    echo "Skipping description."
fi

echo ""
echo -e "${GREEN}=== Step 1: Managed Instance Groups (MIGs) ===${NC}"
echo "Listing managed instance groups..."
gcloud compute instance-groups managed list

echo ""
echo -e "${GREEN}=== Step 2: Filter MIGs and check Autoscaler ===${NC}"
read -p "Enter a keyword to filter Instance Group names (or press Enter to skip filtering): " mig_keyword

if [ -n "$mig_keyword" ]; then
    echo -e "${YELLOW}Filtering for MIGs containing '$mig_keyword' and showing autoscaler info...${NC}"
    # Fetch JSON, filter by name containing keyword (using gcloud filter or jq), then extract autoscaler
    # Using gcloud filter for efficiency
    gcloud compute instance-groups managed list --filter="name ~ $mig_keyword" --format="json" | jq '.[] | {name: .name, autoscaler: .autoscaler}'
else
    echo "Skipping filtering."
fi

echo ""
echo -e "${GREEN}=== Step 3: DNS Managed Zones ===${NC}"
echo "Listing managed zones..."
# Get list of zones (name only) for selection
zones=$(gcloud dns managed-zones list --format="value(name)")
# Display with index
i=1
declare -a zone_array
for zone in $zones; do
    echo "[$i] $zone"
    zone_array[$i]=$zone
    ((i++))
done

echo ""
echo -e "${GREEN}=== Step 4: Select DNS Zone to List Record Sets ===${NC}"
if [ ${#zone_array[@]} -eq 0 ]; then
    echo "No DNS zones found."
else
    read -p "Select a zone number (1-$((i-1))) to list record sets: " zone_choice
    selected_zone=${zone_array[$zone_choice]}

    if [ -n "$selected_zone" ]; then
        echo -e "${YELLOW}Listing record sets for zone: $selected_zone${NC}"
        gcloud dns record-sets list --zone="$selected_zone"
    else
        echo -e "${RED}Invalid selection.${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=== Step 5: Kubernetes Namespaces ===${NC}"
echo "Listing namespaces..."
namespaces=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')

# Display with index
j=1
declare -a ns_array
for ns in $namespaces; do
    echo "[$j] $ns"
    ns_array[$j]=$ns
    ((j++))
done

echo ""
echo -e "${GREEN}=== Step 6: Select Namespace to List Resources ===${NC}"
if [ ${#ns_array[@]} -eq 0 ]; then
    echo "No namespaces found."
else
    read -p "Select a namespace number (1-$((j-1))) to list all resources: " ns_choice
    selected_ns=${ns_array[$ns_choice]}

    if [ -n "$selected_ns" ]; then
        echo -e "${YELLOW}Listing all resources in namespace: $selected_ns${NC}"
        kubectl get all -n "$selected_ns"
    else
        echo -e "${RED}Invalid selection.${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=== Verification Complete ===${NC}"
