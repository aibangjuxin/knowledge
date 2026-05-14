

API rate limiting is the practice of controlling how many requests a client can make within a specific time window. It protects your backend from abuse, ensures fair usage among clients, and maintains reliable performance even under heavy load.

Why API Rate Limiting Matters

→ Prevents server overload
→ Stops malicious bots or brute-force attempts
→ Ensures fair resource distribution
→ Improves API reliability and uptime
→ Helps manage API costs and infrastructure usage

Key Rate Limiting Techniques

1. Fixed Window Rate Limiting

→ Requests are counted within a fixed time window (e.g., 100 requests per minute)
→ Simple to implement
→ Can cause request spikes at window boundaries

2. Sliding Window Log

→ Tracks each request timestamp in a log
→ More accurate smoothing of traffic
→ Higher memory usage

3. Sliding Window Counter

→ Combines fixed window and log techniques
→ Provides smoothed limits without heavy storage
→ Reduces “burst” issues

4. Token Bucket Algorithm

→ Clients collect “tokens” at a fixed rate
→ Each request uses a token
→ Allows controlled bursts while enforcing limits

5. Leaky Bucket Algorithm

→ Processes requests at a constant, fixed rate
→ Queue holds overflow requests
→ Helps smooth fluctuations in traffic

Where Rate Limiting is Applied

→ API Gateways (Kong, NGINX, AWS API Gateway)
→ Reverse proxies
→ Backend application layer
→ CDN edges (Cloudflare, Akamai)
→ Microservices communication layer

Common HTTP Responses for Rate Limiting

→ 429 Too Many Requests — client exceeded limit
→ Retry-After header — tells client how long to wait

Best Practices

→ Set limits based on user roles (free vs. premium)
→ Provide clear error messages with retry instructions
→ Use caching systems like Redis for counters
→ Log all rate limit violations for analysis
→ Avoid extremely strict limits that hinder usability
→ Use adaptive limits for different workloads

Real-World Example

Rate Limit: 100 requests per 1 minute Exceeded: Server returns → 429 Retry-After: 60 seconds 

Add-On: Rate Limiting in Modern API Ecosystems

→ Essential for securing public and partner APIs
→ Enforced in every scalable API architecture
→ Helps maintain predictable performance during traffic spikes

API Mastery Ebook (Add-On)

Get the full deep-dive into API design, security, scalability, and best practices:
API Mastery Ebook: http://codewithdhanian.gumroad.com/l/vrzagk
