#!/bin/bash

# Simple wrapper script to run DR validation with configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/dr-config.env"
DR_SCRIPT="$SCRIPT_DIR/gce-dr-validation.sh"

echo "GCE DR Test Runner"
echo "=================="

# Check if config file exists
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Loading configuration from: $CONFIG_FILE"
    source "$CONFIG_FILE"
else
    echo "Warning: Configuration file not found at $CONFIG_FILE"
    echo "Please copy dr-config.env.example to dr-config.env and customize it"
    echo
    echo "Using default values..."
fi

# Validate required variables
if [[ -z "$MIG_NAME" || "$MIG_NAME" == "your-mig-name" ]]; then
    echo "Error: Please set MIG_NAME in $CONFIG_FILE"
    exit 1
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "your-project-id" ]]; then
    echo "Error: Please set PROJECT_ID in $CONFIG_FILE"
    exit 1
fi

# Run the DR validation script
exec "$DR_SCRIPT" "$@"