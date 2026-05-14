#!/usr/bin/env python3
"""
Ingress Configuration Validation Script

This script validates ingress configurations for the K8s cluster migration:
1. Validates YAML syntax and Kubernetes resource definitions
2. Checks for required annotations and labels
3. Verifies canary routing configuration
4. Tests multi-host and multi-path support
5. Validates TLS configuration

Requirements: 2.1, 3.2, 5.1
"""

import os
import sys
import yaml
import json
import subprocess
from typing import Dict, List, Any, Tuple
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class IngressValidator:
    """Validates ingress configurations for migration"""
    
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.info = []
        
    def validate_yaml_syntax(self, file_path: str) -> bool:
        """Validate YAML syntax"""
        try:
            with open(file_path, 'r') as f:
                yaml.safe_load_all(f)
            self.info.append(f"✓ YAML syntax valid: {file_path}")
            return True
        except yaml.YAMLError as e:
            self.errors.append(f"✗ YAML syntax error in {file_path}: {e}")
            return False
        except FileNotFoundError:
            self.errors.append(f"✗ File not found: {file_path}")
            return False
    
    def validate_ingress_resource(self, ingress: Dict[str, Any], file_path: str) -> bool:
        """Validate individual ingress resource"""
        valid = True
        name = ingress.get('metadata', {}).get('name', 'unknown')
        
        # Check required fields
        required_fields = ['apiVersion', 'kind', 'metadata', 'spec']
        for field in required_fields:
            if field not in ingress:
                self.errors.append(f"✗ Missing required field '{field}' in ingress {name}")
                valid = False
        
        # Validate apiVersion and kind
        if ingress.get('apiVersion') != 'networking.k8s.io/v1':
            self.errors.append(f"✗ Invalid apiVersion in {name}: expected 'networking.k8s.io/v1'")
            valid = False
        
        if ingress.get('kind') != 'Ingress':
            self.errors.append(f"✗ Invalid kind in {name}: expected 'Ingress'")
            valid = False
        
        # Validate metadata
        metadata = ingress.get('metadata', {})
        if 'name' not in metadata:
            self.errors.append(f"✗ Missing name in metadata for ingress in {file_path}")
            valid = False
        
        if 'namespace' not in metadata:
            self.warnings.append(f"⚠ Missing namespace in metadata for ingress {name}")
        
        # Validate labels
        labels = metadata.get('labels', {})
        required_labels = ['app', 'component']
        for label in required_labels:
            if label not in labels:
                self.warnings.append(f"⚠ Missing recommended label '{label}' in ingress {name}")
        
        # Validate annotations
        annotations = metadata.get('annotations', {})
        self._validate_annotations(annotations, name)
        
        # Validate spec
        spec = ingress.get('spec', {})
        self._validate_spec(spec, name)
        
        if valid:
            self.info.append(f"✓ Ingress resource valid: {name}")
        
        return valid
    
    def _validate_annotations(self, annotations: Dict[str, str], ingress_name: str):
        """Validate ingress annotations"""
        
        # Check for ingress class
        if 'kubernetes.io/ingress.class' not in annotations:
            self.warnings.append(f"⚠ Missing ingress class annotation in {ingress_name}")
        elif annotations['kubernetes.io/ingress.class'] != 'nginx':
            self.warnings.append(f"⚠ Unexpected ingress class in {ingress_name}: {annotations['kubernetes.io/ingress.class']}")
        
        # Check SSL redirect
        ssl_redirect = annotations.get('nginx.ingress.kubernetes.io/ssl-redirect')
        if ssl_redirect and ssl_redirect.lower() != 'true':
            self.warnings.append(f"⚠ SSL redirect not enabled in {ingress_name}")
        
        # Check canary annotations for canary ingresses
        if 'canary' in ingress_name.lower():
            self._validate_canary_annotations(annotations, ingress_name)
        
        # Check migration-specific annotations
        migration_annotations = [k for k in annotations.keys() if k.startswith('migration.k8s.io/')]
        if migration_annotations:
            self.info.append(f"✓ Found migration annotations in {ingress_name}: {len(migration_annotations)}")
    
    def _validate_canary_annotations(self, annotations: Dict[str, str], ingress_name: str):
        """Validate canary-specific annotations"""
        
        canary_enabled = annotations.get('nginx.ingress.kubernetes.io/canary', 'false')
        if canary_enabled.lower() == 'true':
            # Check for at least one canary routing method
            canary_methods = [
                'nginx.ingress.kubernetes.io/canary-weight',
                'nginx.ingress.kubernetes.io/canary-by-header',
                'nginx.ingress.kubernetes.io/canary-by-cookie'
            ]
            
            has_method = any(method in annotations for method in canary_methods)
            if not has_method:
                self.errors.append(f"✗ Canary enabled but no routing method specified in {ingress_name}")
            
            # Validate weight if present
            weight = annotations.get('nginx.ingress.kubernetes.io/canary-weight')
            if weight:
                try:
                    weight_val = int(weight)
                    if not 0 <= weight_val <= 100:
                        self.errors.append(f"✗ Invalid canary weight in {ingress_name}: {weight}")
                except ValueError:
                    self.errors.append(f"✗ Invalid canary weight format in {ingress_name}: {weight}")
    
    def _validate_spec(self, spec: Dict[str, Any], ingress_name: str):
        """Validate ingress spec"""
        
        # Validate rules
        rules = spec.get('rules', [])
        if not rules:
            self.errors.append(f"✗ No rules defined in ingress {ingress_name}")
            return
        
        for i, rule in enumerate(rules):
            self._validate_rule(rule, ingress_name, i)
        
        # Validate TLS
        tls = spec.get('tls', [])
        if tls:
            self._validate_tls(tls, ingress_name)
        else:
            self.warnings.append(f"⚠ No TLS configuration in ingress {ingress_name}")
    
    def _validate_rule(self, rule: Dict[str, Any], ingress_name: str, rule_index: int):
        """Validate individual ingress rule"""
        
        # Check host
        host = rule.get('host')
        if not host:
            self.warnings.append(f"⚠ No host specified in rule {rule_index} of ingress {ingress_name}")
        elif not self._is_valid_hostname(host):
            self.errors.append(f"✗ Invalid hostname in rule {rule_index} of ingress {ingress_name}: {host}")
        
        # Check HTTP paths
        http = rule.get('http', {})
        paths = http.get('paths', [])
        
        if not paths:
            self.errors.append(f"✗ No paths defined in rule {rule_index} of ingress {ingress_name}")
            return
        
        for j, path in enumerate(paths):
            self._validate_path(path, ingress_name, rule_index, j)
    
    def _validate_path(self, path: Dict[str, Any], ingress_name: str, rule_index: int, path_index: int):
        """Validate individual path"""
        
        path_value = path.get('path')
        if not path_value:
            self.errors.append(f"✗ Missing path in rule {rule_index}, path {path_index} of ingress {ingress_name}")
        
        path_type = path.get('pathType')
        if path_type not in ['Exact', 'Prefix', 'ImplementationSpecific']:
            self.errors.append(f"✗ Invalid pathType in rule {rule_index}, path {path_index} of ingress {ingress_name}: {path_type}")
        
        # Validate backend
        backend = path.get('backend', {})
        service = backend.get('service', {})
        
        if not service.get('name'):
            self.errors.append(f"✗ Missing service name in rule {rule_index}, path {path_index} of ingress {ingress_name}")
        
        port = service.get('port', {})
        if 'number' not in port and 'name' not in port:
            self.errors.append(f"✗ Missing port in rule {rule_index}, path {path_index} of ingress {ingress_name}")
    
    def _validate_tls(self, tls: List[Dict[str, Any]], ingress_name: str):
        """Validate TLS configuration"""
        
        for i, tls_config in enumerate(tls):
            hosts = tls_config.get('hosts', [])
            secret_name = tls_config.get('secretName')
            
            if not hosts:
                self.warnings.append(f"⚠ No hosts specified in TLS config {i} of ingress {ingress_name}")
            
            if not secret_name:
                self.errors.append(f"✗ Missing secretName in TLS config {i} of ingress {ingress_name}")
            
            # Validate hostnames
            for host in hosts:
                if not self._is_valid_hostname(host):
                    self.errors.append(f"✗ Invalid hostname in TLS config {i} of ingress {ingress_name}: {host}")
    
    def _is_valid_hostname(self, hostname: str) -> bool:
        """Basic hostname validation"""
        if not hostname:
            return False
        
        # Allow wildcards
        if hostname.startswith('*.'):
            hostname = hostname[2:]
        
        # Basic checks
        if len(hostname) > 253:
            return False
        
        if hostname.endswith('.'):
            hostname = hostname[:-1]
        
        # Check for valid characters and structure
        import re
        pattern = r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'
        return bool(re.match(pattern, hostname))
    
    def validate_file(self, file_path: str) -> bool:
        """Validate entire ingress file"""
        logger.info(f"Validating file: {file_path}")
        
        if not self.validate_yaml_syntax(file_path):
            return False
        
        try:
            with open(file_path, 'r') as f:
                documents = list(yaml.safe_load_all(f))
            
            valid = True
            for doc in documents:
                if doc and doc.get('kind') == 'Ingress':
                    if not self.validate_ingress_resource(doc, file_path):
                        valid = False
                elif doc and doc.get('kind') == 'ConfigMap':
                    # Validate ConfigMap if it contains ingress configuration
                    self._validate_configmap(doc, file_path)
            
            return valid
            
        except Exception as e:
            self.errors.append(f"✗ Error validating file {file_path}: {e}")
            return False
    
    def _validate_configmap(self, configmap: Dict[str, Any], file_path: str):
        """Validate ConfigMap containing ingress configuration"""
        name = configmap.get('metadata', {}).get('name', 'unknown')
        data = configmap.get('data', {})
        
        # Check for ingress-related configuration
        config_keys = [k for k in data.keys() if 'ingress' in k.lower() or 'config' in k.lower()]
        if config_keys:
            self.info.append(f"✓ Found ingress configuration in ConfigMap {name}: {config_keys}")
            
            # Validate YAML content in ConfigMap data
            for key, value in data.items():
                if key.endswith('.yaml') or key.endswith('.yml'):
                    try:
                        yaml.safe_load(value)
                        self.info.append(f"✓ Valid YAML in ConfigMap {name}, key {key}")
                    except yaml.YAMLError as e:
                        self.errors.append(f"✗ Invalid YAML in ConfigMap {name}, key {key}: {e}")
    
    def validate_canary_configuration(self, main_ingress_path: str, canary_ingress_path: str = None) -> bool:
        """Validate canary configuration between main and canary ingresses"""
        logger.info("Validating canary configuration...")
        
        try:
            # Load main ingress
            with open(main_ingress_path, 'r') as f:
                main_docs = list(yaml.safe_load_all(f))
            
            main_ingresses = [doc for doc in main_docs if doc and doc.get('kind') == 'Ingress']
            
            if canary_ingress_path:
                with open(canary_ingress_path, 'r') as f:
                    canary_docs = list(yaml.safe_load_all(f))
                canary_ingresses = [doc for doc in canary_docs if doc and doc.get('kind') == 'Ingress']
            else:
                # Look for canary ingresses in the same file
                canary_ingresses = [ing for ing in main_ingresses 
                                  if 'canary' in ing.get('metadata', {}).get('name', '').lower()]
            
            # Validate canary pairs
            for main_ing in main_ingresses:
                main_name = main_ing.get('metadata', {}).get('name', '')
                if 'canary' not in main_name.lower():
                    # Look for corresponding canary ingress
                    canary_name = main_name.replace('-migration', '-canary')
                    canary_ing = next((ing for ing in canary_ingresses 
                                     if ing.get('metadata', {}).get('name') == canary_name), None)
                    
                    if canary_ing:
                        self._validate_canary_pair(main_ing, canary_ing)
                    else:
                        self.warnings.append(f"⚠ No canary ingress found for main ingress {main_name}")
            
            return len(self.errors) == 0
            
        except Exception as e:
            self.errors.append(f"✗ Error validating canary configuration: {e}")
            return False
    
    def _validate_canary_pair(self, main_ingress: Dict[str, Any], canary_ingress: Dict[str, Any]):
        """Validate main and canary ingress pair"""
        main_name = main_ingress.get('metadata', {}).get('name', '')
        canary_name = canary_ingress.get('metadata', {}).get('name', '')
        
        # Check that hosts match
        main_hosts = set()
        canary_hosts = set()
        
        for rule in main_ingress.get('spec', {}).get('rules', []):
            if rule.get('host'):
                main_hosts.add(rule['host'])
        
        for rule in canary_ingress.get('spec', {}).get('rules', []):
            if rule.get('host'):
                canary_hosts.add(rule['host'])
        
        if main_hosts != canary_hosts:
            self.warnings.append(f"⚠ Host mismatch between {main_name} and {canary_name}")
        else:
            self.info.append(f"✓ Hosts match between {main_name} and {canary_name}")
        
        # Check canary annotations
        canary_annotations = canary_ingress.get('metadata', {}).get('annotations', {})
        if 'nginx.ingress.kubernetes.io/canary' not in canary_annotations:
            self.errors.append(f"✗ Missing canary annotation in {canary_name}")
    
    def print_results(self):
        """Print validation results"""
        print("\n" + "="*60)
        print("INGRESS VALIDATION RESULTS")
        print("="*60)
        
        if self.info:
            print(f"\n📋 INFO ({len(self.info)}):")
            for msg in self.info:
                print(f"  {msg}")
        
        if self.warnings:
            print(f"\n⚠️  WARNINGS ({len(self.warnings)}):")
            for msg in self.warnings:
                print(f"  {msg}")
        
        if self.errors:
            print(f"\n❌ ERRORS ({len(self.errors)}):")
            for msg in self.errors:
                print(f"  {msg}")
        else:
            print(f"\n✅ NO ERRORS FOUND")
        
        print(f"\nSUMMARY: {len(self.errors)} errors, {len(self.warnings)} warnings, {len(self.info)} info")
        print("="*60)
        
        return len(self.errors) == 0

def main():
    """Main function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Validate ingress configurations for K8s migration')
    parser.add_argument('files', nargs='+', help='Ingress YAML files to validate')
    parser.add_argument('--canary-validation', action='store_true', 
                       help='Perform canary configuration validation')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    validator = IngressValidator()
    
    # Validate each file
    all_valid = True
    for file_path in args.files:
        if not validator.validate_file(file_path):
            all_valid = False
    
    # Perform canary validation if requested
    if args.canary_validation and len(args.files) >= 1:
        if not validator.validate_canary_configuration(args.files[0]):
            all_valid = False
    
    # Print results
    success = validator.print_results()
    
    # Exit with appropriate code
    sys.exit(0 if success and all_valid else 1)

if __name__ == '__main__':
    main()