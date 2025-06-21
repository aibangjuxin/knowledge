import ipaddress
import re
import sys

# --- Configuration ---
# Input YAML file name
INPUT_FILE = "api_list.yaml"

def extract_ips_from_file(file_path: str) -> set[str]:
    """
    Step 1: Extract all strings matching the IP/CIDR format from the file.
    Uses regular expressions for searching, ignoring the specific YAML structure.
    Returns a set to automatically handle text-level duplicates.
    """
    print(f"--- Step 1: Extracting IP addresses from '{file_path}' ---")

    # Regular expression to match an IPv4 address or CIDR
    # e.g., "205.188.54.82/32", "205.188.54.82"
    # The '?' makes the CIDR part optional.
    ip_pattern = re.compile(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:/[0-9]{1,2})?\b')

    try:
        with open(file_path, 'r') as f:
            content = f.read()
            # Find all matches
            found_ips = ip_pattern.findall(content)
            # Use a set to perform initial deduplication (Step 2)
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
            # Convert the string to an ipaddress object.
            # strict=False allows host addresses (e.g., 205.188.54.82) to be correctly treated as /32 networks.
            net = ipaddress.ip_network(cidr_str, strict=False)

            # Step 3: Exclude private IP address ranges
            if net.is_private:
                print(f"  [Excluding] {str(net):<18} (Private address)")
                continue

            public_networks.append(net)

        except ValueError:
            # Ignore strings that cannot be parsed
            print(f"  [Ignoring]  '{cidr_str}' is not a valid IP address or CIDR.")
            pass

    if not public_networks:
        return []

    # Steps 4 (subsumption) & 5 (aggregation): ipaddress.collapse_addresses is the core function.
    # It automatically handles subsumed subnets and aggregates adjacent address blocks.
    # 1. It discards subnets that are fully contained within a larger one.
    # 2. It merges adjacent networks that can be combined into a larger CIDR.
    print("\nPerforming network aggregation...")
    optimized_networks = list(ipaddress.collapse_addresses(public_networks))

    print(f"Processing complete. Resulted in {len(optimized_networks)} optimized network ranges.")
    print("----------------------------------------------------")

    return optimized_networks


def main():
    """Main execution function"""

    # Steps 1 & 2
    unique_ip_strings = extract_ips_from_file(INPUT_FILE)

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
        # Sort and print the networks by IP address
        for network in sorted(final_list): 
            print(network)
    print("-------------------------------------")


if __name__ == "__main__":
    main()