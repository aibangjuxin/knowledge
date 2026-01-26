#!/bin/bash
# Source the .env file if it exists
if [ -f .env ]; then
    export $(cat .env | xargs)
fi

# Check if credentials are set
if [ -z "$API_USERNAME" ] || [ -z "$API_PASSWORD" ]; then
    echo "Error: API_USERNAME and API_PASSWORD must be set in .env file or environment variables."
    exit 1
fi

get_token() {
    response=$(curl --request POST \
    --header "Content-Type: application/json" \
    --data "{
    \"input_token_state\":{
        \"token_type\": \"CREDENTIAL\",
        \"username\": \"$API_USERNAME\",
        \"passwrod\": \"$API_PASSWORD\"
    },
    \"output_token_status\": {
    \"token_type\": \"JWT\"
    }
    }")

    if [ $? -ne 0 ]; then
        echo "Failed to get token"
        exit 1
    fi
    echo $response|awk -F: '{print $2}'|tr -d '}"'
}

token=$(get_token)
echo "print Token"
echo $token

if [ -z "$token" ]; then
    echo "Failed to get token"
    exit 1
fi

echo "Token: $token"
echo "Now will request to get the health check API"
curl -v -x POST -H "trust-Token: $token" https://www.example.com/.well-known/health

echo "Health check api request success"