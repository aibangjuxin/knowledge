import argparse
import ipaddress
import re
import sys
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

def process_ip_list(ip_strings: set[str]) -> tuple[list, list]:
    logging.info("Filtering, removing subsumed networks, and aggregating")
    public_networks = []
    invalid_ips = []
    for cidr_str in ip_strings:
        try:
            net = ipaddress.ip_network(cidr_str, strict=False)
            if net.is_private:
                logging.info(f"  [Excluding] {str(net):<18} (Private address)")
                continue
            public_networks.append(net)
        except ValueError:
            logging.warning(f"  [Ignoring]  '{cidr_str}' is not a valid IP address or CIDR.")
            invalid_ips.append(cidr_str)

    if not public_networks:
        return [], invalid_ips

    logging.info("Performing network aggregation...")
    optimized_networks = list(ipaddress.collapse_addresses(public_networks))
    logging.info(f"Processing complete. Resulted in {len(optimized_networks)} optimized network ranges.")
    return optimized_networks, invalid_ips

def main():
    setup_logging()
    parser = argparse.ArgumentParser(description="Extract and optimize IP/CIDR ranges from a file.")
    parser.add_argument("input_file", help="Path to the input file containing IP/CIDR strings.")
    parser.add_argument("--output", "-o", help="Path to save the optimized IP ranges.", default=None)
    args = parser.parse_args()

    unique_ip_strings = extract_ips_from_file(args.input_file)
    if not unique_ip_strings:
        logging.info("No IP/CIDR addresses found in the file.")
        return

    final_list, invalid_ips = process_ip_list(unique_ip_strings)

    logging.info("\nFinal Optimized IP Address Ranges")
    if invalid_ips:
        logging.info("Invalid IP/CIDR strings encountered:")
        for ip in invalid_ips:
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
    logging.info("-------------------------------------")

if __name__ == "__main__":
    main()
