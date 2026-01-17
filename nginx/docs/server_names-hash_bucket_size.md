# Understanding nginx server_names_hash_bucket_size

## Overview

The `server_names_hash_bucket_size` directive in nginx is a configuration parameter that controls the size of hash table buckets used for efficient lookup of server names when processing virtual hosts. This directive plays a crucial role in nginx's internal optimization mechanism for handling server name lookups.

## Basic Information

- **Directive**: `server_names_hash_bucket_size`
- **Syntax**: `server_names_hash_bucket_size size;`
- **Default Value**: Depends on the processor's cache line size (typically 32, 64, or 128)
- **Context**: http only
- **Related Directive**: `server_names_hash_max_size` (default: 512)

## Purpose and Function

The `server_names_hash_bucket_size` directive determines the size of hash table buckets used to store server names defined in `server_name` directives. When nginx processes incoming requests, it uses these hash tables to quickly determine which server block should handle the request based on the Host header.

The hash table mechanism allows nginx to efficiently match server names without having to iterate through all defined server names, significantly improving performance when you have many virtual hosts.

## When to Adjust This Setting

You should consider adjusting `server_names_hash_bucket_size` when:

1. **You receive an error message**: `could not build the server_names_hash, you should increase server_names_hash_bucket_size`
2. **You have long server names**: If your server names are unusually long, they may not fit in the default bucket size
3. **You have many server names**: When you have numerous server names that exceed the capacity of the default hash table configuration

## Common Error Scenarios

### Error Message
```
nginx: [emerg] could not build the server_names_hash, you should increase server_names_hash_bucket_size
```

### What Causes This Error?
This error occurs when:
- Server names are too long to fit in the default hash bucket size
- Too many server names are defined, exceeding the hash table capacity
- The combination of server names and their lengths exceeds the allocated hash space

### Example Scenario
```nginx
server {
    listen 80;
    # This long server name might cause the error with default settings
    server_name very-long-subdomain-name-with-many-characters.example.com www.very-long-subdomain-name-with-many-characters.example.com;
}
```

## How to Fix the Error

### Solution 1: Increase server_names_hash_bucket_size
Add the directive to the http context in your nginx configuration:

```nginx
http {
    # Increase the bucket size (try 64, 128, or higher as needed)
    server_names_hash_bucket_size 64;
    
    # ... rest of your configuration
}
```

### Solution 2: Also consider server_names_hash_max_size
Sometimes you may need to adjust both directives:

```nginx
http {
    # Increase both directives if needed
    server_names_hash_max_size 1024;
    server_names_hash_bucket_size 128;
    
    # ... rest of your configuration
}
```

## Effects of Changing the Value

### Increasing the Value

**Positive Effects:**
- Accommodates longer server names
- Allows more server names to be stored in the hash table
- Prevents the "could not build server_names_hash" error

**Potential Drawbacks:**
- Slightly increased memory usage
- Negligible impact on performance (usually positive due to fewer collisions)

### Typical Values
- **Default**: Usually 32, 64, or 128 (depends on CPU cache line size)
- **Small sites**: 64 is often sufficient
- **Medium sites**: 128 is commonly used
- **Large sites with many long names**: 256 or higher may be needed

## Configuration Best Practices

### 1. Placement
Always place these directives in the `http` context, not in `server` or `location` blocks:

```nginx
# CORRECT placement
http {
    server_names_hash_bucket_size 64;
    # ... other configuration
}

# INCORRECT placement
server {
    server_names_hash_bucket_size 64;  # This won't work
}
```

### 2. Testing Changes
After making changes, always test your configuration:

```bash
nginx -t
```

Then reload nginx:

```bash
nginx -s reload
```

### 3. Monitoring
Watch for the error message after adding new server names to ensure the hash table size remains adequate.

## Relationship with server_names_hash_max_size

Both directives work together:
- `server_names_hash_max_size`: Controls the maximum size of the hash table (number of entries)
- `server_names_hash_bucket_size`: Controls the size of each bucket in the hash table

Think of it this way:
- `server_names_hash_max_size` = how many "slots" are available in the hash table
- `server_names_hash_bucket_size` = how much data each slot can hold

## Performance Considerations

- **Memory Usage**: Larger values use slightly more memory but can improve lookup performance
- **CPU Cache**: The default values are optimized for typical CPU cache line sizes
- **Hash Collisions**: Larger bucket sizes reduce hash collisions, improving performance

## Troubleshooting Tips

1. **Start Small**: Begin with 64 and increase incrementally if needed
2. **Check Related Directives**: Sometimes `server_names_hash_max_size` also needs adjustment
3. **Restart Required**: Changes require nginx to be reloaded/restarted
4. **Test Thoroughly**: Always test configuration after changes

## Example Configuration

Here's a complete example showing proper usage:

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    # Hash table optimizations
    server_names_hash_max_size 1024;
    server_names_hash_bucket_size 128;
    
    # Other http configuration
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    # Server blocks
    server {
        listen 80;
        server_name example.com www.example.com;
        # ... server configuration
    }
    
    server {
        listen 80;
        server_name another-site.com www.another-site.com;
        # ... server configuration
    }
}
```

## Conclusion

The `server_names_hash_bucket_size` directive is an important nginx optimization parameter that most users don't need to touch under normal circumstances. However, when you start encountering the "could not build server_names_hash" error or when managing many virtual hosts with long names, understanding and properly configuring this directive becomes essential for nginx to function correctly.

Remember to always test your configuration after making changes and monitor your server to ensure the new values adequately handle your server name requirements.