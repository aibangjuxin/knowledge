# Kong 知识库

## 目录描述
本目录包含Kong API网关相关的知识、配置、认证、限流和最佳实践。

## 目录结构
```
kong/
├── docs/                         # Markdown文档
├── kongdp/                       # Kong数据平面相关内容
├── scripts/                      # Shell脚本
└── README.md                     # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `API-Rate-Limiting.md`: API限流相关
- `capture-kong-log.md`: Kong日志收集
- `cp-vs-dp.md`: 控制平面与数据平面对比
- `debug-kong*.md`: Kong调试相关（含AI辅助）
- `kong-*.md`: Kong各种功能相关文档
- `kong-2.8-vs-3.4.md`: Kong版本对比
- `kong-auth*.md`: Kong认证相关
- `kong-hight-availablity.md`: Kong高可用性
- `kong-ipmatcher.lua.md`: Kong IP匹配Lua脚本
- `kong-log-vault-lua.md`: Kong日志和Vault Lua脚本
- `kong-opentelemetry.md`: Kong OpenTelemetry集成
- `kong-plug-limit.md`: Kong插件限制
- `kong-retry-and-describe.md`: Kong重试和描述
- `kong-zero-downtime.md`: Kong零停机部署
- `migrate-kong.md`: Kong迁移
- `payloadsize.md`: 负载大小相关
- `route.md`: 路由配置
- `testcase.md`: 测试用例
- `x-client-cert-leaf.md`: 客户端证书相关

### scripts/ - 脚本
- `git.sh`: Git相关脚本

## 快速检索
- 版本对比: 查看 `docs/` 目录中的 `kong-2.8-vs-3.4.md`
- 认证: 查看 `docs/` 目录中的 `kong-auth*.md` 文件
- 限流: 查看 `docs/` 目录中的 `API-Rate-Limiting.md`
- 高可用: 查看 `docs/` 目录中的 `kong-hight-availablity.md`
- 调试: 查看 `docs/` 目录中的 `debug-kong*.md` 文件
- 迁移: 查看 `docs/` 目录中的 `migrate-kong.md`
- 插件: 查看 `docs/` 目录中的 `kong-ipmatcher.lua.md` 等Lua脚本相关
- 脚本: 查看 `scripts/` 目录