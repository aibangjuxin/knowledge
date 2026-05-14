import argparse
import ipaddress
import re
import sys
import json
import logging

def setup_logging():
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )

def extract_ips_from_file(file_path: str) -> set[str]:
    logging.info(f"Extracting IP addresses from '{file_path}'")
    ip_pattern = re.compile(r'\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(?:/[0-2]?[0-9]|/3[0-2])?\b')
    unique_ips = set()
    try:
        with open(file_path, 'r') as f:
            for line in f:
                found_ips = ip_pattern.findall(line)
                unique_ips.update(found_ips)
        logging.info(f"Found {len(unique_ips)} unique IP/CIDR strings.")
        return unique_ips
    except FileNotFoundError:
        logging.error(f"Input file '{file_path}' not found.")
        sys.exit(1)
    except Exception as e:
        logging.error(f"Error reading or parsing the file: {e}")
        sys.exit(1)

def process_ip_list(ip_strings: set[str]) -> tuple[list, list, list]:
    logging.info("Filtering, removing subsumed networks, and aggregating")
    public_networks = []
    invalid_ips = []
    private_ips = []
    for cidr_str in ip_strings:
        try:
            net = ipaddress.ip_network(cidr_str, strict=False)
            if net.is_private:
                logging.info(f"  [Excluding] {str(net):<18} (Private address)")
                private_ips.append(cidr_str)
                continue
            public_networks.append(net)
        except ValueError:
            logging.warning(f"  [Ignoring]  '{cidr_str}' is not a valid IP address or CIDR.")
            invalid_ips.append(cidr_str)

    if not public_networks:
        return [], invalid_ips, private_ips

    logging.info("Performing network aggregation...")
    optimized_networks = list(ipaddress.collapse_addresses(public_networks))
    logging.info(f"Processing complete. Resulted in {len(optimized_networks)} optimized network ranges.")
    return optimized_networks, invalid_ips, private_ips

def main():
    setup_logging()
    parser = argparse.ArgumentParser(description="Extract and optimize IP/CIDR ranges from a file.")
    parser.add_argument("input_file", help="Path to the input file containing IP/CIDR strings.")
    parser.add_argument("--output", "-o", help="Path to save the optimized IP ranges.", default=None)
    parser.add_argument("--json-output", action="store_true", help="Output results in JSON format.")
    args = parser.parse_args()

    unique_ip_strings = extract_ips_from_file(args.input_file)
    if not unique_ip_strings:
        logging.info("No IP/CIDR addresses found in the file.")
        if args.json_output:
            print(json.dumps({"status": "error", "message": "No IP/CIDR addresses found", "results": [], "invalid_ips": [], "private_ips": []}))
        sys.exit(1)

    final_list, invalid_ips, private_ips = process_ip_list(unique_ip_strings)

    results = {
        "status": "success" if final_list else "warning",
        "message": "Validation completed",
        "results": [str(net) for net in sorted(final_list)],
        "invalid_ips": invalid_ips,
        "private_ips": private_ips
    }

    suggestions = []
    if invalid_ips:
        suggestions.append("Invalid IP addresses detected. Please correct the following: " + ", ".join(invalid_ips))
    if private_ips:
        suggestions.append("Private IP addresses detected and excluded: " + ", ".join(private_ips))
    if len(final_list) < len(unique_ip_strings) - len(invalid_ips) - len(private_ips):
        suggestions.append("Some IP ranges were aggregated. Consider using the optimized ranges: " + ", ".join(str(net) for net in sorted(final_list)))

    results["suggestions"] = suggestions

    if args.json_output:
        print(json.dumps(results, indent=2))
    else:
        logging.info("\nFinal Optimized IP Address Ranges")
        if invalid_ips:
            logging.info("Invalid IP/CIDR strings encountered:")
            for ip in invalid_ips:
                logging.info(f"  {ip}")
        if private_ips:
            logging.info("Private IP addresses excluded:")
            for ip in private_ips:
                logging.info(f"  {ip}")
        if not final_list:
            logging.info("No valid public IP address ranges to output.")
        else:
            output_lines = [str(network) for network in sorted(final_list)]
            for line in output_lines:
                print(line)
            if args.output:
                try:
                    with open(args.output, 'w') as f:
                        f.write('\n'.join(output_lines))
                    logging.info(f"Results saved to '{args.output}'")
                except Exception as e:
                    logging.error(f"Error writing to output file: {e}")
        if suggestions:
            logging.info("\nSuggestions for improvement:")
            for suggestion in suggestions:
                logging.info(f"  - {suggestion}")
        logging.info("-------------------------------------")

    # Exit with non-zero status if there are invalid IPs or private IPs
    if invalid_ips or private_ips:
        sys.exit(1)
    sys.exit(0)

if __name__ == "__main__":
    main()
