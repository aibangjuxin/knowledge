```bash
#!/bin/bash

# Set color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check parameters
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 -n <namespace> <deployment-name> [command]"
    echo "Example:"
    echo "  $0 -n default my-deployment              # Enter interactive shell"
    echo "  $0 -n default my-deployment /usr/bin/pip freeze  # Execute specified command"
    exit 1
fi

# Parse parameters
while getopts "n:" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG";;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND-1))
DEPLOYMENT=$1
COMMAND=${@:2}

echo -e "${BLUE}Finding first Pod for Deployment: ${DEPLOYMENT} in namespace ${NAMESPACE}${NC}\n"

# Extract app name from deployment name (remove -deployment suffix)
app_name=${DEPLOYMENT%-deployment}

# Get the first pod
POD=$(kubectl get pods -n ${NAMESPACE} -l app=${app_name} --no-headers -o custom-columns=":metadata.name" | head -n 1)

if [ -z "$POD" ]; then
    echo -e "${YELLOW}Error: No Pod found for Deployment ${DEPLOYMENT} in namespace ${NAMESPACE}${NC}"
    exit 1
fi

echo -e "${GREEN}Pod found: ${POD}${NC}"

# If no command provided, enter interactive shell, otherwise execute the specified command
if [ -z "$COMMAND" ]; then
    echo -e "${BLUE}Entering interactive shell in Pod...${NC}"
    kubectl exec -it ${POD} -n ${NAMESPACE} -- sh -c "(bash || ash || sh)"
else
    echo -e "${BLUE}Executing command: ${COMMAND}${NC}"
    kubectl exec ${POD} -n ${NAMESPACE} -- $COMMAND
fi
```