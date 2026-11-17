[Rule]

# Cloudflare 自身不要代理（容易被反爬虫判断）所以 Cloudflare 域名必须直连

DOMAIN-SUFFIX,cloudflare.com,DIRECT
DOMAIN-SUFFIX,cloudflarechallenge.com,DIRECT
DOMAIN-SUFFIX,challenges.cloudflare.com,DIRECT
DOMAIN-SUFFIX,cloudflareinsights.com,DIRECT
DOMAIN-SUFFIX,static.cloudflareinsights.com,DIRECT
DOMAIN-SUFFIX,cf-ns.com,DIRECT
DOMAIN-SUFFIX,cfapi.net,DIRECT
DOMAIN-SUFFIX,cfargotunnel.com,DIRECT
DOMAIN-SUFFIX,cfusercontent.com,DIRECT

# Claude / Anthropic 主域名（必须）

DOMAIN-SUFFIX,claude.ai,PROXY
DOMAIN-SUFFIX,anthropic.com,PROXY
DOMAIN-SUFFIX,accounts.anthropic.com,PROXY

# Claude API / 后端服务

DOMAIN-SUFFIX,api.anthropic.com,PROXY
DOMAIN-SUFFIX,static.anthropic.com,PROXY

# Cloudflare 核心域名（校验 / BOT 管理）

DOMAIN-SUFFIX,cloudflare.com,PROXY
DOMAIN-SUFFIX,cloudflare-dns.com,PROXY
DOMAIN-SUFFIX,cloudflareinsights.com,PROXY
DOMAIN-SUFFIX,cloudflarechallenge.com,PROXY
DOMAIN-SUFFIX,challenge.cloudflare.com,PROXY
DOMAIN-SUFFIX,challenges.cloudflare.com,PROXY
DOMAIN-SUFFIX,cf-ns.com,PROXY

# Cloudflare CDN / Edge 网络

DOMAIN-SUFFIX,workers.dev,PROXY
DOMAIN-SUFFIX,pages.dev,PROXY
DOMAIN-SUFFIX,cfusercontent.com,PROXY
DOMAIN-SUFFIX,cfargotunnel.com,PROXY
DOMAIN-SUFFIX,cfapi.net,PROXY

# Cloudflare 性能与 Bot 检测脚本

DOMAIN-SUFFIX,static.cloudflareinsights.com,PROXY
DOMAIN-SUFFIX,js.cloudflare.com,PROXY

# Claude 使用的第三方资源（防止加载失败）

DOMAIN-SUFFIX,sentry.io,PROXY
DOMAIN-SUFFIX,intercom.io,PROXY
DOMAIN-SUFFIX,intercomcdn.com,PROXY
DOMAIN-SUFFIX,ingest.sentry.io,PROXY
DOMAIN-SUFFIX,cdn.segment.com,PROXY

# 建议兜底（可选，但强烈推荐）

DOMAIN-KEYWORD,anthropic,PROXY
DOMAIN-KEYWORD,claude,PROXY
DOMAIN-KEYWORD,cloudflare,PROXY
