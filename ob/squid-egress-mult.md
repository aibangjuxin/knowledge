# Squid Egress Multi-Proxy Solution: Third-Party Domain Splitting with Squid + Blue-Coat

## Overview

This document outlines an enhanced solution for the `public_egress_config.yaml` that supports third-party export domain splitting and multi-proxy mode (Squid + Blue-Coat). The solution leverages Squid's ACL capabilities to route requests based on destination domains, allowing users to be assigned specific Squid FQDNs while the backend configuration determines the next-hop proxy.

## Current State Analysis

### public_egress_config.yaml Example
```yaml
## public egress yaml file on API Level
publicEgress:
   ## enabled indicate if this API will need to go out from abjx or not
   ## only with value true, this API can reach to fadns list in third_party_fadn_list part
   enabled: true
## update below list to set the external connectivity
  third_party_fadn_list:
    - fqdn: user-ai-api.azure.com
      port: 443
    - fqdn: login.microsoftonline.com
      port: 443
```

## Proposed Architecture

### 1. Domain-Based Routing with Squid ACLs

The solution leverages Squid's powerful ACL system to route requests based on destination domains:

#### Key ACL Types for Domain-Based Routing
- `dstdomain` - Matches destination server from URL (fast lookup)
- `dstdom_regex` - Regex matching for server domains (for complex patterns)

#### Example ACL Configuration
```conf
# Define domain-based ACLs for different service providers
acl azure_services dstdomain .azure.com
acl microsoft_services dstdomain .microsoftonline.com
acl aws_services dstdomain .amazonaws.com
acl google_services dstdomain .googleapis.com

# Define cache peers for different proxy types
cache_peer azure-proxy.internal:3128 parent 80 1 no-query name=azure-peer
cache_peer microsoft-proxy.internal:3128 parent 80 1 no-query name=microsoft-peer
cache_peer bluecoat-gateway.internal:8080 parent 80 1 no-query name=bluecoat-peer

# Route requests to appropriate peers based on domain
cache_peer_access azure-peer allow azure_services
cache_peer_access microsoft-peer allow microsoft_services
cache_peer_access bluecoat-peer allow aws_services
cache_peer_access bluecoat-peer allow google_services

# Block all other requests from going to peers
cache_peer_access azure-peer deny all
cache_peer_access microsoft-peer deny all
cache_peer_access bluecoat-peer deny all
```

### 2. User Assignment and Onboarding Process

#### User Assignment Flow
1. During onboarding, users are assigned a specific Squid FQDN (e.g., `microsoft.aibang.gcp.uk.local:3128`)
2. The onboarding pipeline maps the user's requested domains to the appropriate proxy configuration
3. Squid configuration is updated to route requests based on the destination domain
4. The next-hop proxy is determined by the Squid configuration, not by the user

#### Example User Configuration
```yaml
publicEgress:
  enabled: true
  proxy:
    fqdn: "microsoft.aibang.gcp.uk.local:3128"  # User's assigned proxy FQDN
```

### 3. Multi-Proxy Architecture

#### Direct Squid Mode
For standard routing where Squid directly connects to the internet:
```conf
# Direct routing for Azure services
acl azure_services dstdomain .azure.com
cache_peer azure-upstream:3128 parent 80 1 no-query name=azure-direct
cache_peer_access azure-direct allow azure_services
cache_peer_access azure-direct deny all
```

#### Blue-Coat Mode (Squid as Forward Proxy)
For Blue-Coat integration where Squid forwards to Blue-Coat as next-hop:
```conf
# Blue-Coat routing for specific services
acl bluecoat_services dstdomain .aws.com .googleapis.com
cache_peer bluecoat-gateway:8080 parent 80 1 no-query name=bluecoat-peer
cache_peer_access bluecoat-peer allow bluecoat_services
cache_peer_access bluecoat-peer deny all
```

### 4. Pipeline Integration

#### Onboarding Pipeline Logic
The onboarding pipeline should handle the mapping between user requests and proxy configurations:

```groovy
def processPublicEgress(config) {
    if (!config.publicEgress.enabled) return

    def activeBackends = []
    def proxyFqdn = config.publicEgress.proxy.fqdn
    
    // Mapping table for proxy FQDN to internal configuration
    def mapping = [
      ~/microsoft\\.aibang\\.gcp\\.uk\\.local:3128/: [code: 1, name: 'microsoft', mode: 'squid', cache_peer: 'ms-peer.internal:3128'],
      ~/bluecoat\\.aibang\\.gcp\\.uk\\.local:3128/: [code: 2, name: 'blue-coat', mode: 'bluecoat', cache_peer: 'bc-peer.internal:8080'],
      ~/azure\\.aibang\\.gcp\\.uk\\.local:3128/: [code: 0, name: 'azure', mode: 'squid', cache_peer: 'azure-peer.internal:3128']
    ]

    def proxyConfig = mapping.findResult { k, v -> proxyFqdn ==~ k ? v : null }
    if (!proxyConfig) {
      error("Unsupported proxy FQDN: ${proxyFqdn}")
    }

    // Deploy/Update Squid configuration with appropriate cache_peer settings
    updateSquidConfig(proxyConfig)

    // Update Firestore with backend service codes
    firestoreService.updateBackendServices(apiId, [proxyConfig.code])
}
```

### 5. Squid Configuration Template

#### Dynamic Squid Configuration
The Squid configuration should be dynamically generated based on the assigned proxy type:

```conf
# Generated Squid configuration for microsoft.aibang.gcp.uk.local
http_port 3128

# ACL definitions based on user's domain requirements
acl microsoft_domains dstdomain .microsoftonline.com .azure.com .office.com
acl localnet src 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12

# Allow local network access
http_access allow localnet
http_access allow microsoft_domains
http_access deny all

# Cache peer configuration based on assigned proxy type
cache_peer ms-peer.internal:3128 parent 80 1 no-query name=microsoft-peer
cache_peer_access microsoft-peer allow microsoft_domains
cache_peer_access microsoft-peer deny all

# Additional configuration for Blue-Coat mode if needed
# cache_peer bluecoat-gateway:8080 parent 80 1 no-query name=bluecoat-peer
# cache_peer_access bluecoat-peer allow bluecoat-allowed-domains
```

### 6. Benefits of This Approach

#### For Users
- **Simplicity**: Users only need to know their assigned proxy FQDN
- **Transparency**: Users don't need to worry about which proxy mode is being used
- **Flexibility**: Same proxy FQDN can route to different next-hop proxies based on destination

#### For Platform
- **Scalability**: Easy to add new proxy types and routing rules
- **Maintainability**: Centralized routing logic in Squid configuration
- **Security**: Fine-grained control over which domains can access which proxies
- **Auditability**: Clear mapping between users, domains, and proxy routes

### 7. Migration Strategy

#### Phase 1: Compatibility
- Maintain backward compatibility with existing `third_party_fadn_list` configuration
- Introduce new `proxy.fqdn` field as optional
- Pipeline checks for new field first, falls back to old method

#### Phase 2: Gradual Migration
- New onboarding uses new schema
- Monitor success rates in BigQuery
- Gradually migrate existing users

#### Phase 3: Full Adoption
- Remove support for old schema
- Optimize based on usage patterns

### 8. Implementation Considerations

#### Security
- Ensure proper NetworkPolicy for Pod-to-proxy communication
- Validate all FQDNs to prevent DNS rebinding attacks
- Implement rate limiting per user/proxy combination

#### Performance
- Use `dstdomain` instead of `dstdom_regex` when possible for faster lookups
- Implement proper caching for DNS lookups
- Monitor Squid performance metrics

#### Monitoring
- Log all routing decisions for audit purposes
- Monitor cache_peer access patterns
- Track user-specific proxy usage

## Conclusion

This solution provides a flexible, scalable approach to multi-proxy egress routing that hides complexity from users while providing fine-grained control for the platform. By leveraging Squid's ACL capabilities, we can route requests to different next-hop proxies based on destination domains, supporting both direct Squid mode and Blue-Coat integration seamlessly.