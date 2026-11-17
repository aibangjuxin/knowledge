#!/usr/bin/env python3
"""
Ingress Configuration Management Script for K8s Cluster Migration

This script provides functionality to:
1. Update Ingress configurations for canary routing
2. Manage multiple hosts and paths
3. Support hot configuration updates
4. Validate Ingress configurations

Requirements: 2.1, 3.2, 5.1 (hot updates)
"""

import os
import sys
import yaml
import json
import argparse
import subprocess
from typing import Dict, List, Any, Optional
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class IngressManager:
    """Manages Ingress configurations for cluster migration"""
    
    def __init__(self, namespace: str = "aibang-1111111111-bbdm"):
        self.namespace = namespace
        self.config_path = "/app/config"
        self.k8s_path = "/app/k8s"
        
    def load_config(self, config_file: str = "ingress-config.yaml") -> Dict[str, Any]:
        """Load ingress configuration from ConfigMap"""
        try:
            config_path = os.path.join(self.config_path, config_file)
            if os.path.exists(config_path):
                with open(config_path, 'r') as f:
                    return yaml.safe_load(f)
            else:
                # Fallback to kubectl get configmap
                result = subprocess.run([
                    'kubectl', 'get', 'configmap', 'ingress-migration-config',
                    '-n', self.namespace, '-o', 'yaml'
                ], capture_output=True, text=True, check=True)
                
                configmap = yaml.safe_load(result.stdout)
                config_data = configmap['data']['ingress-config.yaml']
                return yaml.safe_load(config_data)
                
        except Exception as e:
            logger.error(f"Failed to load configuration: {e}")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict[str, Any]:
        """Get default configuration"""
        return {
            'services': {
                'bbdm-api': {
                    'enabled': True,
                    'old_host': 'api-name01.teamname.dev.aliyun.intracloud.cn.aibang',
                    'new_host': 'api-name01.kong.dev.aliyun.intracloud.cn.aibang',
                    'old_service': 'bbdm-api',
                    'new_service': 'new-cluster-bbdm-api',
                    'namespace': self.namespace,
                    'canary': {
                        'enabled': False,
                        'weight': 0,
                        'header_name': 'X-Canary',
                        'header_value': 'new-cluster',
                        'cookie_name': 'canary'
                    },
                    'paths': [
                        {'path': '/', 'pathType': 'Prefix', 'backend_port': 80},
                        {'path': '/api', 'pathType': 'Prefix', 'backend_port': 80},
                        {'path': '/health', 'pathType': 'Prefix', 'backend_port': 8080}
                    ],
                    'tls': {
                        'enabled': True,
                        'secret_name': 'bbdm-api-tls'
                    }
                }
            },
            'global': {
                'ingress_class': 'nginx',
                'ssl_redirect': True,
                'force_ssl_redirect': True
            }
        }
    
    def update_canary_weight(self, service_name: str, weight: int) -> bool:
        """Update canary weight for a service"""
        try:
            if not 0 <= weight <= 100:
                raise ValueError("Weight must be between 0 and 100")
            
            # Update the canary ingress annotation
            ingress_name = f"{service_name}-canary"
            
            # Patch the ingress with new weight
            patch_data = {
                'metadata': {
                    'annotations': {
                        'nginx.ingress.kubernetes.io/canary': 'true' if weight > 0 else 'false',
                        'nginx.ingress.kubernetes.io/canary-weight': str(weight),
                        'migration.k8s.io/canary-weight': str(weight),
                        'migration.k8s.io/last-updated': datetime.now().isoformat()
                    }
                }
            }
            
            result = subprocess.run([
                'kubectl', 'patch', 'ingress', ingress_name,
                '-n', self.namespace,
                '--type', 'merge',
                '-p', json.dumps(patch_data)
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"Updated canary weight for {service_name} to {weight}%")
                return True
            else:
                logger.error(f"Failed to update canary weight: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Error updating canary weight: {e}")
            return False
    
    def enable_canary_routing(self, service_name: str, routing_type: str = "weight", 
                           weight: int = 5, header_name: str = None, 
                           header_value: str = None) -> bool:
        """Enable canary routing for a service"""
        try:
            ingress_name = f"{service_name}-canary"
            
            annotations = {
                'nginx.ingress.kubernetes.io/canary': 'true',
                'migration.k8s.io/canary-enabled': 'true',
                'migration.k8s.io/canary-type': routing_type,
                'migration.k8s.io/last-updated': datetime.now().isoformat()
            }
            
            if routing_type == "weight":
                annotations['nginx.ingress.kubernetes.io/canary-weight'] = str(weight)
                annotations['migration.k8s.io/canary-weight'] = str(weight)
            
            elif routing_type == "header":
                if header_name and header_value:
                    annotations['nginx.ingress.kubernetes.io/canary-by-header'] = header_name
                    annotations['nginx.ingress.kubernetes.io/canary-by-header-value'] = header_value
                else:
                    annotations['nginx.ingress.kubernetes.io/canary-by-header'] = 'X-Canary'
                    annotations['nginx.ingress.kubernetes.io/canary-by-header-value'] = 'new-cluster'
            
            elif routing_type == "cookie":
                annotations['nginx.ingress.kubernetes.io/canary-by-cookie'] = 'canary'
            
            patch_data = {
                'metadata': {
                    'annotations': annotations
                }
            }
            
            result = subprocess.run([
                'kubectl', 'patch', 'ingress', ingress_name,
                '-n', self.namespace,
                '--type', 'merge',
                '-p', json.dumps(patch_data)
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"Enabled canary routing for {service_name} with type {routing_type}")
                return True
            else:
                logger.error(f"Failed to enable canary routing: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Error enabling canary routing: {e}")
            return False
    
    def disable_canary_routing(self, service_name: str) -> bool:
        """Disable canary routing for a service"""
        try:
            ingress_name = f"{service_name}-canary"
            
            patch_data = {
                'metadata': {
                    'annotations': {
                        'nginx.ingress.kubernetes.io/canary': 'false',
                        'migration.k8s.io/canary-enabled': 'false',
                        'migration.k8s.io/canary-weight': '0',
                        'migration.k8s.io/last-updated': datetime.now().isoformat()
                    }
                }
            }
            
            result = subprocess.run([
                'kubectl', 'patch', 'ingress', ingress_name,
                '-n', self.namespace,
                '--type', 'merge',
                '-p', json.dumps(patch_data)
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"Disabled canary routing for {service_name}")
                return True
            else:
                logger.error(f"Failed to disable canary routing: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Error disabling canary routing: {e}")
            return False
    
    def add_host_path(self, service_name: str, host: str, path: str, 
                     path_type: str = "Prefix", backend_port: int = 80) -> bool:
        """Add a new host/path to an existing ingress"""
        try:
            ingress_name = f"{service_name}-migration"
            
            # Get current ingress
            result = subprocess.run([
                'kubectl', 'get', 'ingress', ingress_name,
                '-n', self.namespace, '-o', 'yaml'
            ], capture_output=True, text=True, check=True)
            
            ingress = yaml.safe_load(result.stdout)
            
            # Add new rule or path
            new_path = {
                'path': path,
                'pathType': path_type,
                'backend': {
                    'service': {
                        'name': 'migration-proxy',
                        'port': {
                            'number': backend_port
                        }
                    }
                }
            }
            
            # Find existing rule for host or create new one
            rules = ingress['spec'].get('rules', [])
            host_found = False
            
            for rule in rules:
                if rule['host'] == host:
                    rule['http']['paths'].append(new_path)
                    host_found = True
                    break
            
            if not host_found:
                new_rule = {
                    'host': host,
                    'http': {
                        'paths': [new_path]
                    }
                }
                rules.append(new_rule)
            
            ingress['spec']['rules'] = rules
            
            # Apply updated ingress
            with open('/tmp/updated_ingress.yaml', 'w') as f:
                yaml.dump(ingress, f)
            
            result = subprocess.run([
                'kubectl', 'apply', '-f', '/tmp/updated_ingress.yaml'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info(f"Added host/path {host}{path} to {service_name}")
                return True
            else:
                logger.error(f"Failed to add host/path: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Error adding host/path: {e}")
            return False
    
    def validate_ingress_config(self, service_name: str) -> Dict[str, Any]:
        """Validate ingress configuration"""
        try:
            validation_result = {
                'valid': True,
                'errors': [],
                'warnings': [],
                'service_name': service_name
            }
            
            # Check if ingress exists
            ingress_name = f"{service_name}-migration"
            result = subprocess.run([
                'kubectl', 'get', 'ingress', ingress_name,
                '-n', self.namespace
            ], capture_output=True, text=True)
            
            if result.returncode != 0:
                validation_result['valid'] = False
                validation_result['errors'].append(f"Ingress {ingress_name} not found")
                return validation_result
            
            # Get ingress details
            result = subprocess.run([
                'kubectl', 'get', 'ingress', ingress_name,
                '-n', self.namespace, '-o', 'yaml'
            ], capture_output=True, text=True, check=True)
            
            ingress = yaml.safe_load(result.stdout)
            
            # Validate TLS configuration
            if 'tls' not in ingress['spec']:
                validation_result['warnings'].append("No TLS configuration found")
            
            # Validate rules
            rules = ingress['spec'].get('rules', [])
            if not rules:
                validation_result['valid'] = False
                validation_result['errors'].append("No routing rules defined")
            
            # Check backend services
            for rule in rules:
                for path in rule['http']['paths']:
                    service_name = path['backend']['service']['name']
                    service_port = path['backend']['service']['port']['number']
                    
                    # Check if service exists
                    svc_result = subprocess.run([
                        'kubectl', 'get', 'service', service_name,
                        '-n', self.namespace
                    ], capture_output=True, text=True)
                    
                    if svc_result.returncode != 0:
                        validation_result['warnings'].append(
                            f"Backend service {service_name} not found"
                        )
            
            return validation_result
            
        except Exception as e:
            logger.error(f"Error validating ingress config: {e}")
            return {
                'valid': False,
                'errors': [str(e)],
                'warnings': [],
                'service_name': service_name
            }
    
    def get_ingress_status(self, service_name: str) -> Dict[str, Any]:
        """Get current status of ingress configuration"""
        try:
            status = {
                'service_name': service_name,
                'main_ingress': {},
                'canary_ingress': {},
                'timestamp': datetime.now().isoformat()
            }
            
            # Get main ingress status
            main_ingress_name = f"{service_name}-migration"
            result = subprocess.run([
                'kubectl', 'get', 'ingress', main_ingress_name,
                '-n', self.namespace, '-o', 'yaml'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                ingress = yaml.safe_load(result.stdout)
                status['main_ingress'] = {
                    'exists': True,
                    'hosts': [rule['host'] for rule in ingress['spec'].get('rules', [])],
                    'annotations': ingress['metadata'].get('annotations', {}),
                    'tls_enabled': 'tls' in ingress['spec']
                }
            else:
                status['main_ingress']['exists'] = False
            
            # Get canary ingress status
            canary_ingress_name = f"{service_name}-canary"
            result = subprocess.run([
                'kubectl', 'get', 'ingress', canary_ingress_name,
                '-n', self.namespace, '-o', 'yaml'
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                ingress = yaml.safe_load(result.stdout)
                annotations = ingress['metadata'].get('annotations', {})
                status['canary_ingress'] = {
                    'exists': True,
                    'enabled': annotations.get('nginx.ingress.kubernetes.io/canary', 'false') == 'true',
                    'weight': int(annotations.get('nginx.ingress.kubernetes.io/canary-weight', '0')),
                    'routing_type': annotations.get('migration.k8s.io/canary-type', 'weight'),
                    'last_updated': annotations.get('migration.k8s.io/last-updated', 'unknown')
                }
            else:
                status['canary_ingress']['exists'] = False
            
            return status
            
        except Exception as e:
            logger.error(f"Error getting ingress status: {e}")
            return {
                'service_name': service_name,
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            }

def main():
    """Main function for CLI usage"""
    parser = argparse.ArgumentParser(description='Manage Ingress configurations for K8s migration')
    parser.add_argument('--namespace', '-n', default='aibang-1111111111-bbdm',
                       help='Kubernetes namespace')
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Update canary weight
    weight_parser = subparsers.add_parser('set-weight', help='Set canary weight')
    weight_parser.add_argument('service', help='Service name')
    weight_parser.add_argument('weight', type=int, help='Canary weight (0-100)')
    
    # Enable canary
    enable_parser = subparsers.add_parser('enable-canary', help='Enable canary routing')
    enable_parser.add_argument('service', help='Service name')
    enable_parser.add_argument('--type', choices=['weight', 'header', 'cookie'], 
                              default='weight', help='Routing type')
    enable_parser.add_argument('--weight', type=int, default=5, help='Initial weight')
    enable_parser.add_argument('--header-name', help='Header name for header-based routing')
    enable_parser.add_argument('--header-value', help='Header value for header-based routing')
    
    # Disable canary
    disable_parser = subparsers.add_parser('disable-canary', help='Disable canary routing')
    disable_parser.add_argument('service', help='Service name')
    
    # Add host/path
    path_parser = subparsers.add_parser('add-path', help='Add host/path to ingress')
    path_parser.add_argument('service', help='Service name')
    path_parser.add_argument('host', help='Host name')
    path_parser.add_argument('path', help='Path')
    path_parser.add_argument('--path-type', default='Prefix', help='Path type')
    path_parser.add_argument('--port', type=int, default=80, help='Backend port')
    
    # Validate configuration
    validate_parser = subparsers.add_parser('validate', help='Validate ingress configuration')
    validate_parser.add_argument('service', help='Service name')
    
    # Get status
    status_parser = subparsers.add_parser('status', help='Get ingress status')
    status_parser.add_argument('service', help='Service name')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    manager = IngressManager(args.namespace)
    
    if args.command == 'set-weight':
        success = manager.update_canary_weight(args.service, args.weight)
        sys.exit(0 if success else 1)
    
    elif args.command == 'enable-canary':
        success = manager.enable_canary_routing(
            args.service, args.type, args.weight, 
            args.header_name, args.header_value
        )
        sys.exit(0 if success else 1)
    
    elif args.command == 'disable-canary':
        success = manager.disable_canary_routing(args.service)
        sys.exit(0 if success else 1)
    
    elif args.command == 'add-path':
        success = manager.add_host_path(
            args.service, args.host, args.path, args.path_type, args.port
        )
        sys.exit(0 if success else 1)
    
    elif args.command == 'validate':
        result = manager.validate_ingress_config(args.service)
        print(json.dumps(result, indent=2))
        sys.exit(0 if result['valid'] else 1)
    
    elif args.command == 'status':
        status = manager.get_ingress_status(args.service)
        print(json.dumps(status, indent=2))

if __name__ == '__main__':
    main()