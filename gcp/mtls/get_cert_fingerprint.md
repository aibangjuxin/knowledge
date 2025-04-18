```bash
#!/bin/bash

# Function: Display usage instructions for the script
# This function is called when incorrect number of arguments is provided
show_usage() {
    echo "Usage: $0 <root_certificate_path> <intermediate_certificate_path>"
    echo "Example: $0 root.pem intermediate.pem"
    exit 1
}

# Function: Calculate and display certificate fingerprint
# Parameters:
#   $1 - Path to the certificate file
#   $2 - Certificate type (root or intermediate)
# Returns:
#   Prints certificate type and SHA-256 fingerprint in YAML format
get_fingerprint() {
    local cert_file=$1
    local cert_type=$2

    # Check if certificate file exists
    if [ ! -f "$cert_file" ]; then
        echo "Error: Certificate file '$cert_file' does not exist"
        exit 1
    fi

    # Validate if the file is a valid PEM format certificate
    # Redirect stderr to /dev/null to suppress OpenSSL error messages
    if ! openssl x509 -in "$cert_file" -noout 2>/dev/null; then
        echo "Error: '$cert_file' is not a valid PEM format certificate"
        exit 1
    fi

    # Calculate SHA-256 fingerprint using OpenSSL
    # Cut the output to only get the fingerprint value after the '=' character
    local fingerprint=$(openssl x509 -in "$cert_file" -noout -fingerprint -sha256 | cut -d'=' -f2)
    
    # Output in YAML format for easy parsing
    echo "Certificate Type: $cert_type"
    echo "Fingerprint: SHA256:$fingerprint"
    echo "---"
}

# Validate number of command line arguments
if [ $# -ne 2 ]; then
    show_usage
fi

# Process and display certificate fingerprints
echo "Certificate Fingerprint Information:"
echo "---"
get_fingerprint "$1" "Root Certificate"
get_fingerprint "$2" "Intermediate Certificate"
```