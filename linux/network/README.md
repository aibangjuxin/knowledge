# Network 知识库

## 目录描述
本目录包含网络技术相关的知识、协议分析、网络工具使用和网络故障排除。

## 目录结构
```
network/
├── docs/                             # Markdown文档
├── reports/                          # 报告文件
├── scripts/                          # Shell脚本
├── wrk/                              # WRK压力测试工具相关内容
└── README.md                         # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `curl-*.md`: Curl命令行工具使用技巧
- `protocal.md`: 网络协议相关
- `README-explorer-domain.md`: 域名探索工具说明
- `README-ipv6-test.md`: IPv6测试说明
- `squid-proxy.md`: Squid代理相关
- `tailscale.md`: Tailscale VPN相关
- `testipv6.md`: IPv6测试相关
- `ipv6-test.html`: IPv6测试页面

### scripts/ - 脚本
- `explorer-domain*.sh`: 域名探索相关脚本（支持Claude、Gemini、Grok、Kimi、Qwen等）
- `test-ipv6-local.sh`: 本地IPv6测试脚本

### reports/ - 报告
- `domain_report_*.txt`: 域名分析报告

### 根目录
- `nhf-flow.html` / `nhf-flow-enhance.html`: NHF 出网机制可视化架构图
- `nhf-egress-ip.md`: NHF 出网源 IP 定位 —— 给 on-prem 邮件服务器(`128.171.x.x`)授权白名单该填什么;结论:出局 IP = NHF 实例 Shared VPC 主网卡地址(`10.72.x.x`,子网 `10.72.0.0/18`),须按网段授权并确认回程路由
- `smtp-egress-nhf-squid-analysis.md`: GKE 公网出网发邮件的可行性分析（NHF 三层路由 + Squid 代理边界）；结论：邮件服务器 IP 不在 `128.0.0.0/2` 内，Squid 是 HTTP 代理无法承载 SMTP

### wrk/ - 压力测试
- WRK压力测试工具相关内容

## 快速检索
- HTTP请求测试: 查看 `docs/` 目录中的 `curl-*.md` 文件
- 代理配置: 查看 `docs/` 目录中的 `squid-proxy.md`
- 域名分析: 查看 `scripts/` 目录中的 `explorer-domain*.sh` 脚本及 `reports/` 目录中的 `domain_report_*.txt` 报告
- IPv6测试: 查看 `docs/` 目录中的 `testipv6.md` 和 `scripts/` 目录中的 `test-ipv6-local.sh`
- VPN: 查看 `docs/` 目录中的 `tailscale.md`
- 压力测试: 查看 `wrk/` 目录