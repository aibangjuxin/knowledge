#!/usr/bin/env python3

"""
ExternalName Services Validation Script for K8s Cluster Migration

This script validates the configuration and connectivity of ExternalName services
used in the cluster migration process.
"""

import subprocess
import json
import sys
import socket
import ssl
import urllib.request
import urllib.error
from typing import Dict, List, Tuple, Optional
import yaml

class ExternalServiceValidator:
    def __init__(self, namespace: str = "aibang-1111111111-bbdm"):
        self.namespace = namespace
        self.services = [
            "new-cluster-bbdm-api",
            "new-cluster-gateway", 
            "new-cluster-health"
        ]
        self.expected_endpoints = {
            "new-cluster-bbdm-api": "api-name01.kong.dev.aliyun.intracloud.cn.aibang",
            "new-cluster-gateway": "kong.dev.aliyun.intracloud.cn.aibang",
            "new-cluster-health": "api-name01.kong.dev.aliyun.intracloud.cn.aibang"
        }
        self.test_ports = [80, 443]
        
    def run_kubectl_command(self, args: List[str]) -> Tuple[bool, str]:
        """Run kubectl command and return success status and output."""
        try:
            result = subprocess.run(
                ["kubectl"] + args,
                capture_output=True,
                text=True,
                timeout=30
            )
            return result.returncode == 0, result.stdout.strip()
        except subprocess.TimeoutExpired:
            return False, "Command timed out"
        except Exception as e:
            return False, str(e)
    
    def validate_service_exists(self, service_name: str) -> bool:
        """Validate that the ExternalName service exists."""
        print(f"  Checking if service {service_name} exists...")
        success, output = self.run_kubectl_command([
            "get", "service", service_name, "-n", self.namespace
        ])
        
        if success:
            print(f"    ✓ Service {service_name} exists")
            return True
        else:
            print(f"    ✗ Service {service_name} not found")
            return False
    
    def validate_service_type(self, service_name: str) -> bool:
        """Validate that the service is of type ExternalName."""
        print(f"  Checking service type for {service_name}...")
        success, output = self.run_kubectl_command([
            "get", "service", service_name, "-n", self.namespace,
            "-o", "jsonpath={.spec.type}"
        ])
        
        if success and output == "ExternalName":
            print(f"    ✓ Service {service_name} is ExternalName type")
            return True
        else:
            print(f"    ✗ Service {service_name} is not ExternalName type (got: {output})")
            return False
    
    def validate_external_name(self, service_name: str) -> bool:
        """Validate the externalName configuration."""
        print(f"  Checking externalName for {service_name}...")
        success, output = self.run_kubectl_command([
            "get", "service", service_name, "-n", self.namespace,
            "-o", "jsonpath={.spec.externalName}"
        ])
        
        expected = self.expected_endpoints.get(service_name)
        if success and output == expected:
            print(f"    ✓ ExternalName correctly set to {output}")
            return True
        else:
            print(f"    ✗ ExternalName mismatch. Expected: {expected}, Got: {output}")
            return False
    
    def validate_service_ports(self, service_name: str) -> bool:
        """Validate service port configuration."""
        print(f"  Checking port configuration for {service_name}...")
        success, output = self.run_kubectl_command([
            "get", "service", service_name, "-n", self.namespace,
            "-o", "json"
        ])
        
        if not success:
            print(f"    ✗ Failed to get service configuration")
            return False
        
        try:
            service_data = json.loads(output)
            ports = service_data.get("spec", {}).get("ports", [])
            
            if not ports:
                print(f"    ✗ No ports configured")
                return False
            
            port_numbers = [port.get("port") for port in ports]
            print(f"    ✓ Configured ports: {port_numbers}")
            
            # Check if essential ports are present
            essential_ports = [80, 443]
            missing_ports = [p for p in essential_ports if p not in port_numbers]
            
            if missing_ports:
                print(f"    ! Warning: Missing essential ports: {missing_ports}")
            
            return True
            
        except json.JSONDecodeError:
            print(f"    ✗ Failed to parse service configuration")
            return False
    
    def test_dns_resolution(self, hostname: str) -> bool:
        """Test DNS resolution for the hostname."""
        print(f"  Testing DNS resolution for {hostname}...")
        try:
            socket.gethostbyname(hostname)
            print(f"    ✓ DNS resolution successful")
            return True
        except socket.gaierror:
            print(f"    ✗ DNS resolution failed")
            return False
    
    def test_port_connectivity(self, hostname: str, port: int, timeout: int = 10) -> bool:
        """Test TCP connectivity to hostname:port."""
        print(f"  Testing connectivity to {hostname}:{port}...")
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((hostname, port))
            sock.close()
            
            if result == 0:
                print(f"    ✓ Connection successful")
                return True
            else:
                print(f"    ✗ Connection failed")
                return False
        except Exception as e:
            print(f"    ✗ Connection error: {e}")
            return False
    
    def test_http_endpoint(self, hostname: str, port: int, timeout: int = 10) -> bool:
        """Test HTTP/HTTPS endpoint."""
        protocol = "https" if port == 443 else "http"
        url = f"{protocol}://{hostname}:{port}/"
        
        print(f"  Testing HTTP endpoint {url}...")
        try:
            # Create SSL context that doesn't verify certificates for testing
            if protocol == "https":
                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE
                
                request = urllib.request.Request(url)
                response = urllib.request.urlopen(request, timeout=timeout, context=ssl_context)
            else:
                request = urllib.request.Request(url)
                response = urllib.request.urlopen(request, timeout=timeout)
            
            status_code = response.getcode()
            print(f"    ✓ HTTP response received (status: {status_code})")
            return True
            
        except urllib.error.HTTPError as e:
            # HTTP errors (4xx, 5xx) still indicate the endpoint is reachable
            print(f"    ✓ HTTP endpoint reachable (status: {e.code})")
            return True
        except Exception as e:
            print(f"    ✗ HTTP request failed: {e}")
            return False
    
    def validate_service_labels(self, service_name: str) -> bool:
        """Validate service labels and annotations."""
        print(f"  Checking labels and annotations for {service_name}...")
        success, output = self.run_kubectl_command([
            "get", "service", service_name, "-n", self.namespace,
            "-o", "json"
        ])
        
        if not success:
            print(f"    ✗ Failed to get service metadata")
            return False
        
        try:
            service_data = json.loads(output)
            metadata = service_data.get("metadata", {})
            labels = metadata.get("labels", {})
            annotations = metadata.get("annotations", {})
            
            # Check required labels
            required_labels = ["app", "component"]
            missing_labels = [label for label in required_labels if label not in labels]
            
            if missing_labels:
                print(f"    ! Warning: Missing labels: {missing_labels}")
            else:
                print(f"    ✓ Required labels present")
            
            # Check migration annotations
            migration_annotations = [key for key in annotations.keys() if key.startswith("migration.k8s.io/")]
            if migration_annotations:
                print(f"    ✓ Migration annotations found: {len(migration_annotations)}")
            else:
                print(f"    ! Warning: No migration annotations found")
            
            return True
            
        except json.JSONDecodeError:
            print(f"    ✗ Failed to parse service metadata")
            return False
    
    def run_validation(self) -> bool:
        """Run complete validation suite."""
        print("=== ExternalName Services Validation ===")
        print(f"Namespace: {self.namespace}")
        print(f"Services to validate: {self.services}")
        print()
        
        all_passed = True
        
        for service_name in self.services:
            print(f"Validating service: {service_name}")
            service_passed = True
            
            # Service existence and configuration
            if not self.validate_service_exists(service_name):
                service_passed = False
            elif not self.validate_service_type(service_name):
                service_passed = False
            elif not self.validate_external_name(service_name):
                service_passed = False
            elif not self.validate_service_ports(service_name):
                service_passed = False
            else:
                self.validate_service_labels(service_name)
            
            # Network connectivity tests
            if service_name in self.expected_endpoints:
                hostname = self.expected_endpoints[service_name]
                
                if self.test_dns_resolution(hostname):
                    for port in self.test_ports:
                        self.test_port_connectivity(hostname, port)
                        if port in [80, 443]:
                            self.test_http_endpoint(hostname, port)
            
            if service_passed:
                print(f"  ✓ Service {service_name} validation PASSED")
            else:
                print(f"  ✗ Service {service_name} validation FAILED")
                all_passed = False
            
            print()
        
        # Summary
        print("=== Validation Summary ===")
        if all_passed:
            print("✓ All ExternalName services validation PASSED")
            return True
        else:
            print("✗ Some ExternalName services validation FAILED")
            return False

def main():
    """Main function."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Validate ExternalName services for K8s cluster migration")
    parser.add_argument("--namespace", "-n", default="aibang-1111111111-bbdm",
                       help="Kubernetes namespace (default: aibang-1111111111-bbdm)")
    
    args = parser.parse_args()
    
    validator = ExternalServiceValidator(namespace=args.namespace)
    success = validator.run_validation()
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()