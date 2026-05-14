#!/usr/bin/env python3
import json
import subprocess
import argparse
import sys
import math

def parse_cpu(quantity):
    """Converts CPU quantity string to millicores."""
    if not quantity:
        return 0
    if quantity.endswith('m'):
        return int(quantity[:-1])
    return int(float(quantity) * 1000)

def parse_memory(quantity):
    """Converts memory quantity string to MiB."""
    if not quantity:
        return 0
    
    # Handle plain numbers (bytes)
    if quantity.isdigit():
        return int(quantity) // (1024 * 1024)

    units = {
        'Ki': 1 / 1024,
        'Mi': 1,
        'Gi': 1024,
        'Ti': 1024 * 1024,
        'K': 1 / 1024 / 1.024, # 1000 multiplier vs 1024
        'M': 1 / 1.024,
        'G': 1000 / 1.024, # Approximation for decimal G
    }
    
    for unit, multiplier in units.items():
        if quantity.endswith(unit):
            value = float(quantity[:-len(unit)])
            return int(value * multiplier)
            
    return 0 # Fallback

def format_cpu(millicores):
    """Formats millicores back to standard string."""
    if millicores >= 1000 and millicores % 1000 == 0:
        return str(millicores // 1000)
    return f"{millicores}m"

def format_memory(mib):
    """Formats MiB back to standard string."""
    if mib >= 1024 and mib % 1024 == 0:
        return f"{mib // 1024}Gi"
    return f"{mib}Mi"

def run_kubectl(args, dry_run=False):
    cmd = ['kubectl'] + args
    print(f"Executing: {' '.join(cmd)}")
    if dry_run:
        return ""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error executing kubectl: {e.stderr}", file=sys.stderr)
        sys.exit(1)

def get_deployments(namespace, mock_file=None):
    if mock_file:
        with open(mock_file, 'r') as f:
            return json.load(f)
    
    output = run_kubectl(['get', 'deploy', '-n', namespace, '-o', 'json'])
    return json.loads(output)

def analyze_deployments(deployments_json):
    total_cpu = 0
    total_mem = 0
    running_cpu = 0
    running_mem = 0
    
    unhealthy_deployments = []
    
    for item in deployments_json.get('items', []):
        name = item['metadata']['name']
        spec = item.get('spec', {})
        replicas = spec.get('replicas', 0)
        status = item.get('status', {})
        ready_replicas = status.get('readyReplicas', 0)
        
        # Calculate resources per pod
        pod_cpu = 0
        pod_mem = 0
        
        template_spec = spec.get('template', {}).get('spec', {})
        containers = template_spec.get('containers', [])
        
        for container in containers:
            resources = container.get('resources', {})
            limits = resources.get('limits', {})
            requests = resources.get('requests', {})
            
            # Use limits if available, otherwise requests, otherwise 0
            c_cpu = limits.get('cpu') or requests.get('cpu')
            c_mem = limits.get('memory') or requests.get('memory')
            
            pod_cpu += parse_cpu(c_cpu)
            pod_mem += parse_memory(c_mem)
            
        deployment_total_cpu = pod_cpu * replicas
        deployment_total_mem = pod_mem * replicas
        
        total_cpu += deployment_total_cpu
        total_mem += deployment_total_mem
        
        # Check health
        # Definition of unhealthy: replicas > 0 BUT readyReplicas == 0
        # This means it's completely failing to start (CrashLoop, Pending, etc.)
        if replicas > 0 and ready_replicas == 0:
            unhealthy_deployments.append({
                'name': name,
                'replicas': replicas,
                'cpu_saving': deployment_total_cpu,
                'mem_saving': deployment_total_mem
            })
        else:
            running_cpu += deployment_total_cpu
            running_mem += deployment_total_mem
            
    return {
        'total_cpu': total_cpu,
        'total_mem': total_mem,
        'running_cpu': running_cpu,
        'running_mem': running_mem,
        'unhealthy': unhealthy_deployments
    }

def scale_down_unhealthy(namespace, unhealthy_list, dry_run=False):
    print("\n--- Scaling Down Unhealthy Deployments ---")
    for deploy in unhealthy_list:
        name = deploy['name']
        replicas = deploy['replicas']
        
        print(f"Scaling down {name} (was {replicas} replicas)...")
        
        # 1. Annotate with original replicas for recovery
        run_kubectl([
            'annotate', 'deploy', name, '-n', namespace, 
            f'x-optimization/original-replicas={replicas}', '--overwrite'
        ], dry_run=dry_run)
        
        # 2. Scale to 0
        run_kubectl([
            'scale', 'deploy', name, '-n', namespace, '--replicas=0'
        ], dry_run=dry_run)

def restore_deployments(namespace, dry_run=False):
    print(f"\n--- Restoring Deployments in {namespace} ---")
    # Get all deployments
    deployments = get_deployments(namespace)
    
    for item in deployments.get('items', []):
        metadata = item['metadata']
        name = metadata['name']
        annotations = metadata.get('annotations', {})
        
        if 'x-optimization/original-replicas' in annotations:
            original_replicas = annotations['x-optimization/original-replicas']
            print(f"Restoring {name} to {original_replicas} replicas...")
            
            run_kubectl([
                'scale', 'deploy', name, '-n', namespace, 
                f'--replicas={original_replicas}'
            ], dry_run=dry_run)
            
            # Remove annotation
            run_kubectl([
                'annotate', 'deploy', name, '-n', namespace, 
                'x-optimization/original-replicas-'
            ], dry_run=dry_run)

def generate_report(stats, namespace):
    print("\n" + "="*40)
    print(f"Resource Optimization Report for Namespace: {namespace}")
    print("="*40)
    
    print(f"{'Metric':<20} | {'CPU':<10} | {'Memory':<10}")
    print("-" * 46)
    print(f"{'Total Requested':<20} | {format_cpu(stats['total_cpu']):<10} | {format_memory(stats['total_mem']):<10}")
    print(f"{'Running (Healthy)':<20} | {format_cpu(stats['running_cpu']):<10} | {format_memory(stats['running_mem']):<10}")
    print(f"{'Potential Savings':<20} | {format_cpu(stats['total_cpu'] - stats['running_cpu']):<10} | {format_memory(stats['total_mem'] - stats['running_mem']):<10}")
    
    print("\nUnhealthy Deployments (Candidates for Scale Down):")
    if not stats['unhealthy']:
        print("  None found.")
    else:
        for d in stats['unhealthy']:
            print(f"  - {d['name']}: {d['replicas']} replicas (Saving: {format_cpu(d['cpu_saving'])} CPU, {format_memory(d['mem_saving'])} Mem)")

def generate_quota_yaml(stats, namespace, buffer_percent=10):
    """Generates a ResourceQuota with a safety buffer."""
    
    # Base is running usage
    base_cpu = stats['running_cpu']
    base_mem = stats['running_mem']
    
    # Add buffer
    limit_cpu = int(base_cpu * (1 + buffer_percent/100))
    limit_mem = int(base_mem * (1 + buffer_percent/100))
    
    yaml_content = f"""
apiVersion: v1
kind: ResourceQuota
metadata:
  name: {namespace}-optimization-quota
  namespace: {namespace}
spec:
  hard:
    requests.cpu: "{format_cpu(limit_cpu)}"
    requests.memory: "{format_memory(limit_mem)}"
    limits.cpu: "{format_cpu(limit_cpu)}"
    limits.memory: "{format_memory(limit_mem)}"
"""
    return yaml_content

def main():
    parser = argparse.ArgumentParser(description='Optimize K8s Namespace Resources')
    parser.add_argument('--namespace', required=True, help='Target Kubernetes Namespace')
    parser.add_argument('--dry-run', action='store_true', help='Simulate actions without changes')
    parser.add_argument('--restore', action='store_true', help='Restore previously scaled down deployments')
    parser.add_argument('--mock-file', help='Path to mock JSON file for testing')
    parser.add_argument('--apply', action='store_true', help='Actually apply changes (scale down). Default is report only.')
    
    args = parser.parse_args()
    
    if args.restore:
        restore_deployments(args.namespace, dry_run=args.dry_run)
        return

    print(f"Fetching deployments from {args.namespace}...")
    try:
        deployments = get_deployments(args.namespace, args.mock_file)
    except Exception as e:
        print(f"Failed to get deployments: {e}")
        sys.exit(1)
        
    stats = analyze_deployments(deployments)
    generate_report(stats, args.namespace)
    
    if args.apply:
        if stats['unhealthy']:
            scale_down_unhealthy(args.namespace, stats['unhealthy'], dry_run=args.dry_run)
        else:
            print("\nNo unhealthy deployments to scale down.")
            
        print("\n--- Recommended ResourceQuota ---")
        print(generate_quota_yaml(stats, args.namespace))
        print("\n(Save this to a file and apply with 'kubectl apply -f ...')")
    else:
        print("\n[INFO] Run with --apply to scale down unhealthy deployments and generate quota.")

if __name__ == "__main__":
    main()
