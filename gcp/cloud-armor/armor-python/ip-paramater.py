import ipaddress
import re
import sys

def extract_ips_from_file(file_path: str) -> set[str]:
    """
    Step 1: Extract all strings matching the IP/CIDR format from the file.
    Uses regular expressions for searching, ignoring the specific YAML structure.
    Returns a set to automatically handle text-level duplicates.
    """
    print(f"--- Step 1: Extracting IP addresses from '{file_path}' ---")

    ip_pattern = re.compile(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:/[0-9]{1,2})?\b')

    try:
        with open(file_path, 'r') as f:
            content = f.read()
            found_ips = ip_pattern.findall(content)
            unique_ips = set(found_ips)
            print(f"Found {len(unique_ips)} unique IP/CIDR strings.")
            print("----------------------------------------------------")
            return unique_ips
    except FileNotFoundError:
        print(f"Error: Input file '{file_path}' not found.")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading or parsing the file: {e}")
        sys.exit(1)

def process_ip_list(ip_strings: set[str]) -> list:
    """
    Performs the core processing on the extracted list of IP strings.
    - Step 3: Exclude private IP address ranges.
    - Steps 4 & 5: Handle subsumed networks and aggregate adjacent ones.
    """
    print("--- Steps 3, 4, 5: Filtering, removing subsumed networks, and aggregating ---")

    public_networks = []
    for cidr_str in ip_strings:
        try:
            net = ipaddress.ip_network(cidr_str, strict=False)
            if net.is_private:
                print(f"  [Excluding] {str(net):<18} (Private address)")
                continue
            public_networks.append(net)
        except ValueError:
            print(f"  [Ignoring]  '{cidr_str}' is not a valid IP address or CIDR.")
            pass

    if not public_networks:
        return []

    print("\nPerforming network aggregation...")
    optimized_networks = list(ipaddress.collapse_addresses(public_networks))
    print(f"Processing complete. Resulted in {len(optimized_networks)} optimized network ranges.")
    print("----------------------------------------------------")
    return optimized_networks

def main():
    """Main execution function"""
    
    # --- CHANGE START ---
    # Check if a command-line argument (the filename) was provided.
    if len(sys.argv) < 2:
        print("Error: No input file specified.")
        print(f"Usage: python3 {sys.argv[0]} <path_to_file>")
        sys.exit(1)

    # Get the input file path from the first command-line argument.
    input_file_path = sys.argv[1]
    # --- CHANGE END ---

    # Steps 1 & 2
    unique_ip_strings = extract_ips_from_file(input_file_path)

    if not unique_ip_strings:
        print("No IP/CIDR addresses found in the file.")
        return

    # Steps 3, 4, 5
    final_list = process_ip_list(unique_ip_strings)

    # Print the final result
    print("\n--- Final Optimized IP Address Ranges ---")
    if not final_list:
        print("No valid public IP address ranges to output.")
    else:
        for network in sorted(final_list): 
            print(network)
    print("-------------------------------------")


if __name__ == "__main__":
    main()
