# DNS 知识库

## 目录描述
本目录包含DNS（域名系统）相关的知识、配置、故障排除和最佳实践。

## 目录结构
```
dns/
├── dns-peering/              # DNS对等互连相关内容
├── docs/                     # Markdown文档
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `a.md`: DNS A记录相关
- `cloud-dns.md`: 云DNS服务相关
- `demis-dns-switch.md`: DNS切换相关
- `dns-length.md`: DNS长度限制相关
- `dns-log.md`: DNS日志相关
- `dns-migrate.md`: DNS迁移相关
- `dns-peerning.md`: DNS对等互连相关（拼写变体）
- `dns-svc-compare.md`: DNS服务对比
- `dns-v2.md`: DNS版本2相关
- `kube-dns.md`: Kubernetes DNS相关
- `loon-dns.md`: Loon DNS相关
- `merged-scripts.md`: 合并的DNS脚本
- `migrate-dns-enhance.md`: DNS迁移增强
- `priority-response.md`: DNS优先级响应
- `s.md`: DNS记录相关（可能为SRV记录）
- `shared-logs.md`: 共享DNS日志
- `verify-dnspeering.md`: DNS对等互连验证

## 快速检索
- 云DNS: 查看 `docs/` 目录中的 `cloud-dns.md`
- Kubernetes DNS: 查看 `docs/` 目录中的 `kube-dns.md`
- DNS对等互连: 查看 `dns-peering/` 目录及 `docs/` 目录中的 `dns-peerning.md`
- DNS迁移: 查看 `docs/` 目录中的 `dns-migrate.md` 和 `migrate-dns-enhance.md`
- DNS日志: 查看 `docs/` 目录中的 `dns-log.md`
- 服务对比: 查看 `docs/` 目录中的 `dns-svc-compare.md`