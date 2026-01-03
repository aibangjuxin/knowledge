# Linux Route Commands Guide

## Overview
This guide covers essential Linux routing commands for managing network routes, including static route configuration, route queries, and policy-based routing with ip rules.

## Table of Contents
- [Basic Route Commands](#basic-route-commands)
- [Static Route Management](#static-route-management)
- [Route Queries](#route-queries)
- [IP Rule Commands](#ip-rule-commands)
- [Advanced Examples](#advanced-examples)
- [Troubleshooting](#troubleshooting)

## Basic Route Commands

### View Current Routes
```bash
# Display routing table (traditional)
route -n

# Display routing table (modern ip command)
ip route show
ip route list
ip r  # shorthand

# Display specific route table
ip route show table main
ip route show table local
```

### Route Command Syntax
```bash
# Traditional route command format
route [add|del] [-net|-host] target [netmask Nm] [gw Gw] [metric N] [dev If]

# Modern ip route command format
ip route [add|del|change|replace] ROUTE
```

## Static Route Management

### Adding Static Routes

#### Using traditional `route` command:
```bash
# Add route to specific network
route add -net 192.168.100.0/24 gw 192.168.1.1

# Add route to specific host
route add -host 10.0.0.5 gw 192.168.1.1

# Add default gateway
route add default gw 192.168.1.1

# Add route via specific interface
route add -net 172.16.0.0/16 dev eth1
```

#### Using modern `ip route` command:
```bash
# Add route to specific network
ip route add 192.168.100.0/24 via 192.168.1.1

# Add route to specific host
ip route add 10.0.0.5 via 192.168.1.1

# Add default gateway
ip route add default via 192.168.1.1

# Add route via specific interface
ip route add 172.16.0.0/16 dev eth1

# Add route with metric
ip route add 192.168.200.0/24 via 192.168.1.1 metric 100

# Add route to specific routing table
ip route add 10.0.0.0/8 via 192.168.1.1 table 100
```

### Deleting Static Routes

#### Using traditional `route` command:
```bash
# Delete route to network
route del -net 192.168.100.0/24

# Delete route to host
route del -host 10.0.0.5

# Delete default gateway
route del default
```

#### Using modern `ip route` command:
```bash
# Delete route to network
ip route del 192.168.100.0/24

# Delete route to host
ip route del 10.0.0.5

# Delete default gateway
ip route del default

# Delete route from specific table
ip route del 10.0.0.0/8 table 100
```

### Replacing Routes
```bash
# Replace existing route
ip route replace 192.168.100.0/24 via 192.168.1.2

# Change route parameters
ip route change 192.168.100.0/24 via 192.168.1.1 metric 50
```

## Route Queries

### Getting Route Information

#### Query specific destination:
```bash
# Get route to specific destination
ip route get 8.8.8.8
ip route get 192.168.100.5

# Get route with source address
ip route get 8.8.8.8 from 192.168.1.10

# Get route via specific interface
ip route get 8.8.8.8 dev eth0
```

#### Example output:
```
$ ip route get 8.8.8.8
8.8.8.8 via 192.168.1.1 dev wlan0 src 192.168.1.100 uid 1000
    cache
```

### Route Table Analysis
```bash
# Show all route tables
ip route show table all

# Show specific route table
ip route show table main
ip route show table local

# Show routes with additional details
ip -details route show

# Show routes in JSON format
ip -json route show
```

## IP Rule Commands

### Understanding Policy Routing
IP rules determine which routing table to use for packet forwarding based on various criteria.

### Viewing Current Rules
```bash
# List all routing rules
ip rule list
ip rule show

# List rules with details
ip -details rule list
```

### Adding IP Rules

#### Basic rule syntax:
```bash
ip rule add [from PREFIX] [to PREFIX] [iif STRING] [oif STRING] [table TABLE_ID] [priority PRIORITY]
```

#### Examples:
```bash
# Route packets from specific source to custom table
ip rule add from 192.168.1.0/24 table 100

# Route packets to specific destination to custom table
ip rule add to 10.0.0.0/8 table 200

# Route packets from specific interface to custom table
ip rule add iif eth1 table 300

# Route packets to specific interface from custom table
ip rule add oif eth0 table 400

# Combined rules
ip rule add from 192.168.1.0/24 to 10.0.0.0/8 table 100 priority 1000

# Rule based on packet mark
ip rule add fwmark 1 table 100

# Rule with priority
ip rule add from 172.16.0.0/16 table 200 priority 500
```

### Deleting IP Rules
```bash
# Delete rule by specification
ip rule del from 192.168.1.0/24 table 100

# Delete rule by priority
ip rule del priority 1000

# Delete all rules for specific table
ip rule del table 100
```

## Advanced Examples

### Multi-homed Setup
```bash
# Create custom routing tables
echo "200 isp1" >> /etc/iproute2/rt_tables
echo "201 isp2" >> /etc/iproute2/rt_tables

# Add routes to custom tables
ip route add default via 192.168.1.1 table isp1
ip route add default via 192.168.2.1 table isp2

# Add rules to use custom tables
ip rule add from 192.168.1.0/24 table isp1
ip rule add from 192.168.2.0/24 table isp2
```

### Load Balancing
```bash
# Add multiple default routes with different weights
ip route add default scope global \
    nexthop via 192.168.1.1 dev eth0 weight 1 \
    nexthop via 192.168.2.1 dev eth1 weight 1
```

### Source-based Routing
```bash
# Route traffic from specific source through specific gateway
ip rule add from 192.168.1.100 table 100 priority 100
ip route add default via 192.168.1.1 table 100
ip route add 192.168.1.0/24 dev eth0 table 100
```

## Troubleshooting

### Common Issues and Solutions

#### Route not working:
```bash
# Check if route exists
ip route get [destination]

# Verify routing table
ip route show

# Check for conflicting rules
ip rule list

# Test connectivity
ping -c 4 [destination]
traceroute [destination]
```

#### Debugging route selection:
```bash
# Enable route debugging (temporary)
echo 1 > /proc/sys/net/ipv4/conf/all/log_martians

# Check kernel routing cache
ip route show cache

# Monitor routing decisions
ip monitor route
```

### Best Practices

1. **Always backup** current routing configuration:
   ```bash
   ip route show > /tmp/routes_backup.txt
   ip rule list > /tmp/rules_backup.txt
   ```

2. **Use specific metrics** for route priorities:
   ```bash
   ip route add 0.0.0.0/0 via 192.168.1.1 metric 100
   ```

3. **Test routes** before making permanent:
   ```bash
   # Test temporary route
   ip route add 10.0.0.0/8 via 192.168.1.1
   # Test connectivity
   ping 10.0.0.1
   # Remove if not working
   ip route del 10.0.0.0/8
   ```

4. **Make routes persistent** by adding to network configuration files:
   - `/etc/network/interfaces` (Debian/Ubuntu)
   - `/etc/sysconfig/network-scripts/route-*` (RHEL/CentOS)
   - `/etc/netplan/` (Ubuntu with netplan)

### Useful Commands for Monitoring
```bash
# Watch routing table changes
watch -n 1 'ip route show'

# Monitor routing events
ip monitor route

# Check routing statistics
cat /proc/net/route

# View routing cache
ip route show cache
```

## Summary

- Use `ip route` for modern Linux routing management
- Use `ip route get` to query specific routes
- Use `ip rule` for policy-based routing
- Always test routes before making them permanent
- Consider using custom routing tables for complex setups
- Monitor routing changes with `ip monitor route`

Remember that routing changes made with `ip` commands are temporary and will be lost after reboot unless added to network configuration files.
