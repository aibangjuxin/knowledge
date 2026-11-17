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


- enhance it 
```bash
#!/opt/homebrew/bin/bash

# Function: Display usage instructions for the script
show_usage() {
  echo "Usage: $0 <root_certificate_path> <intermediate_certificate_path>"
  echo "Example: $0 root.pem intermediate.pem"
  exit 1
}

# Function: Check if required commands are available
check_dependencies() {
  if ! command -v openssl &>/dev/null; then
    echo "Error: OpenSSL is not installed or not in PATH"
    exit 1
  fi
}

# Function: Determine certificate type by checking basicConstraints and CA
get_cert_type() {
  local cert_file=$1
  local is_ca=$(openssl x509 -in "$cert_file" -noout -text | grep -A1 "Basic Constraints" | grep "CA:TRUE")
  local path_len=$(openssl x509 -in "$cert_file" -noout -text | grep -A1 "Basic Constraints" | grep "pathlen")
  
  if [ -n "$is_ca" ]; then
    if [ -z "$path_len" ]; then
      echo "Root Certificate"
    else
      echo "Intermediate Certificate"
    fi
  else
    echo "End-Entity Certificate"
  fi
}

# Function: Calculate and display certificate details
get_certificate_info() {
  local cert_file=$1
  
  # Check if certificate file exists
  if [ ! -f "$cert_file" ]; then
    echo "Error: Certificate file '$cert_file' does not exist"
    exit 1
  fi
  
  # Validate PEM format and get certificate details
  if ! openssl x509 -in "$cert_file" -noout 2>/dev/null; then
    echo "Error: '$cert_file' is not a valid PEM format certificate"
    exit 1
  fi
  
  # Determine certificate type
  local cert_type=$(get_cert_type "$cert_file")
  
  # Get certificate details
  local fingerprint=$(openssl x509 -in "$cert_file" -noout -fingerprint -sha256 | cut -d'=' -f2)
  local subject=$(openssl x509 -in "$cert_file" -noout -subject | sed 's/subject= //')
  local expiry=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d'=' -f2)
  
  # Output in YAML format
  echo "Certificate Type: $cert_type"
  echo "Fingerprint: SHA256:$fingerprint"
  echo "Subject: $subject"
  echo "Expires: $expiry"
  echo "---"
}

# Main script execution
main() {
  # Check dependencies
  check_dependencies
  
  # Validate arguments
  if [ $# -ne 2 ]; then
    show_usage
  fi
  
  echo "Certificate Information Report"
  echo "Generated on: $(date)"
  echo "---"
  get_certificate_info "$1"
  get_certificate_info "$2"
}

# Execute main function
main "$@"
```